#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>
#include <atomic>
#include "viture_device_carina.h"
#include "GestureEngine.h"

@class HandTracker;
static HandTracker *g_tracker = nil;
static std::atomic<int> g_engineStatus{0};
static std::atomic<int> g_carinaCallbacks{0};

enum {
    kEngineStatusStarting = 0,
    kEngineStatusCarina = 1,
    kEngineStatusFrontCamera = 2,
    kEngineStatusUnavailable = 3,
    kEngineStatusPermissionDenied = 4,
};

static void CarinaCameraCallback(char *imageLeft0,
                                 char *imageRight0,
                                 char *imageLeft1,
                                 char *imageRight1,
                                 double timestamp,
                                 int width,
                                 int height);

static int FindVitureProductID() {
    // The Carina SDK identifies Luma Ultra as product 0x1104. Keep the
    // lookup behind the vendor check so a random USB camera is never passed
    // to the SDK.
    io_iterator_t iterator = IO_OBJECT_NULL;
    CFMutableDictionaryRef matching = IOServiceMatching(kIOUSBDeviceClassName);
    if (!matching || IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) != KERN_SUCCESS) {
        return -1;
    }

    int productID = -1;
    io_service_t service = IO_OBJECT_NULL;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        CFTypeRef vendorValue = IORegistryEntryCreateCFProperty(service, CFSTR("idVendor"),
                                                                  kCFAllocatorDefault, 0);
        CFTypeRef productValue = IORegistryEntryCreateCFProperty(service, CFSTR("idProduct"),
                                                                   kCFAllocatorDefault, 0);
        int vendor = 0;
        int product = 0;
        if (vendorValue && productValue &&
            CFGetTypeID(vendorValue) == CFNumberGetTypeID() &&
            CFGetTypeID(productValue) == CFNumberGetTypeID()) {
            CFNumberGetValue((CFNumberRef)vendorValue, kCFNumberIntType, &vendor);
            CFNumberGetValue((CFNumberRef)productValue, kCFNumberIntType, &product);
            if (vendor == 0x35CA && product == 0x1104) {
                productID = product;
            }
        }
        if (vendorValue) CFRelease(vendorValue);
        if (productValue) CFRelease(productValue);
        IOObjectRelease(service);
        if (productID >= 0) break;
    }
    IOObjectRelease(iterator);
    return productID;
}

@interface HandTracker : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, assign) BOOL isClicking;
@property (nonatomic, assign) CGSize screenSize;
@property (nonatomic, assign) CGPoint lastMousePos;
@property (nonatomic, assign) BOOL hasFirstPos;
@property (nonatomic, assign) XRDeviceProviderHandle carinaHandle;
@property (nonatomic, assign) BOOL usingCarina;
@end

@implementation HandTracker

- (instancetype)init {
    self = [super init];
    if (self) {
        _isClicking = NO;
        _hasFirstPos = NO;
        _carinaHandle = NULL;
        _usingCarina = NO;
        _screenSize = CGDisplayBounds(CGMainDisplayID()).size;
    }
    return self;
}

- (void)start {
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        if (!granted) {
            NSLog(@"Mighty Mouse: camera permission was denied.");
            g_engineStatus.store(kEngineStatusPermissionDenied);
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self setupCarina]) {
                [self setupCamera];
            }
        });
    }];
}

- (BOOL)setupCarina {
    int productID = FindVitureProductID();
    if (productID < 0) {
        return NO;
    }

    XRDeviceProviderHandle handle = xr_device_provider_create(productID);
    if (!handle || xr_device_provider_get_device_type(handle) != XR_DEVICE_TYPE_VITURE_CARINA) {
        if (handle) xr_device_provider_destroy(handle);
        return NO;
    }

    int callbackResult = xr_device_provider_register_callbacks_carina(handle,
                                                                       NULL,
                                                                       NULL,
                                                                       NULL,
                                                                       CarinaCameraCallback);
    g_carinaCallbacks.store(0);
    int initializeResult = callbackResult == 0
        ? xr_device_provider_initialize(handle, NULL, NULL)
        : callbackResult;
    int startResult = initializeResult == 0
        ? xr_device_provider_start(handle)
        : initializeResult;
    if (startResult != 0) {
        NSLog(@"Mighty Mouse: Luma Ultra tracking camera unavailable (SDK result %d).", startResult);
        if (initializeResult == 0) xr_device_provider_shutdown(handle);
        xr_device_provider_destroy(handle);
        return NO;
    }

    self.carinaHandle = handle;
    self.usingCarina = YES;
    g_engineStatus.store(kEngineStatusStarting);
    NSLog(@"Mighty Mouse: Luma Ultra tracking-camera SDK started; waiting for frames.");

    // SpaceWalker may own the tracking interface. The SDK can report start
    // success before its USB callback stream is actually available, so give
    // it a short window and then fall back with an explicit status.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.usingCarina && g_carinaCallbacks.load() == 0) {
            NSLog(@"Mighty Mouse: no Luma Ultra tracking frames; falling back to front USB camera.");
            [self stopCarina];
            [self setupCamera];
        }
    });
    return YES;
}

- (void)stopCarina {
    if (self.carinaHandle) {
        xr_device_provider_stop(self.carinaHandle);
        xr_device_provider_shutdown(self.carinaHandle);
        xr_device_provider_destroy(self.carinaHandle);
        self.carinaHandle = NULL;
    }
    self.usingCarina = NO;
}

// ... setupCamera remains the same as previous version ...
- (void)setupCamera {
    self.session = [[AVCaptureSession alloc] init];
    self.session.sessionPreset = AVCaptureSessionPreset1280x720;

    AVCaptureDevice *vitureDevice = nil;
    AVCaptureDeviceDiscoverySession *discoverySession = [AVCaptureDeviceDiscoverySession 
        discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeExternal] 
        mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
    
    for (AVCaptureDevice *device in discoverySession.devices) {
        if ([[device localizedName] containsString:@"USB Camera"]) {
            vitureDevice = device;
            break;
        }
    }
    if (!vitureDevice) vitureDevice = discoverySession.devices.firstObject;

    if (!vitureDevice) {
        NSLog(@"Mighty Mouse: no external camera was found.");
        return;
    }

    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:vitureDevice error:&error];
    if (!input || error) {
        NSLog(@"Mighty Mouse: could not open camera %@: %@",
              vitureDevice.localizedName,
              error.localizedDescription ?: @"unknown error");
        return;
    }
    if (![self.session canAddInput:input]) {
        NSLog(@"Mighty Mouse: camera input could not be added.");
        return;
    }
    [self.session addInput:input];

    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    dispatch_queue_t videoQueue = dispatch_queue_create("com.viture.handtracking", DISPATCH_QUEUE_SERIAL);
    [output setSampleBufferDelegate:self queue:videoQueue];
    if (![self.session canAddOutput:output]) {
        NSLog(@"Mighty Mouse: camera video output could not be added.");
        return;
    }
    [self.session addOutput:output];
    
    NSRect screenRect = [[NSScreen mainScreen] frame];
    [self.session startRunning];
    g_engineStatus.store(kEngineStatusFrontCamera);
    NSLog(@"Mighty Mouse: camera session started with %@.", vitureDevice.localizedName);
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    [self processPixelBuffer:pixelBuffer];
}

- (void)processCarinaImage:(char *)image width:(int)width height:(int)height {
    if (!image || width <= 0 || height <= 0) return;

    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn result = CVPixelBufferCreateWithBytes(kCFAllocatorDefault,
                                                    (size_t)width,
                                                    (size_t)height,
                                                    kCVPixelFormatType_OneComponent8,
                                                    image,
                                                    (size_t)width,
                                                    NULL,
                                                    NULL,
                                                    NULL,
                                                    &pixelBuffer);
    if (result == kCVReturnSuccess) {
        [self processPixelBuffer:pixelBuffer];
        CVPixelBufferRelease(pixelBuffer);
    }
}

- (void)processPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer) return;
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer options:@{}];
    VNDetectHumanHandPoseRequest *request = [[VNDetectHumanHandPoseRequest alloc] init];

    NSError *visionError = nil;
    [handler performRequests:@[request] error:&visionError];
    
    if (request.results.count > 0) {
        [self processHand:request.results.firstObject];
    }
}

- (void)processHand:(VNHumanHandPoseObservation *)hand {
    VNRecognizedPoint *indexTip = [hand recognizedPointForJointName:VNHumanHandPoseObservationJointNameIndexTip error:nil];
    VNRecognizedPoint *thumbTip = [hand recognizedPointForJointName:VNHumanHandPoseObservationJointNameThumbTip error:nil];
    
    // Cursor movement only needs a reliable index fingertip. Requiring the
    // thumb as well makes pointing fail whenever the thumb is out of frame.
    const CGFloat minimumIndexConfidence = 0.25;
    const CGFloat minimumThumbConfidence = 0.35;
    if (indexTip.confidence < minimumIndexConfidence) {
        return;
    }

    // 1. EDGE-TO-EDGE MAPPING LOGIC
    // The camera center is 0.5. We subtract 0.5 to center the coordinates at 0.0.
    // Then we multiply by a 'gain' factor (e.g., 1.5) to stretch the reach.
    CGFloat gain = 1.6; 
    CGFloat mappedX = (indexTip.x - 0.5) * gain + 0.5;
    CGFloat mappedY = (indexTip.y - 0.5) * gain + 0.5;

    // Clamp values between 0.0 and 1.0 so the mouse doesn't disappear
    mappedX = fmax(0.0, fmin(1.0, mappedX));
    mappedY = fmax(0.0, fmin(1.0, mappedY));

    // 2. Mapping to Screen Size
    CGFloat targetX = mappedX * self.screenSize.width;
    CGFloat targetY = (1.0 - mappedY) * self.screenSize.height;

    // 3. Smoothing (Exponential Moving Average)
    if (!self.hasFirstPos) {
        self.lastMousePos = CGPointMake(targetX, targetY);
        self.hasFirstPos = YES;
    }

    CGFloat alpha = 0.30; // Increased slightly for better responsiveness with high gain
    CGPoint smoothedPos = CGPointMake(
        (targetX * alpha) + (self.lastMousePos.x * (1.0 - alpha)),
        (targetY * alpha) + (self.lastMousePos.y * (1.0 - alpha))
    );
    self.lastMousePos = smoothedPos;

    // 4. Pinch & Click Logic. Pinching requires a confident thumb; pointing
    // remains active when only the index fingertip is confidently visible.
    BOOL isPinchingNow = NO;
    if (thumbTip.confidence >= minimumThumbConfidence) {
        CGFloat dist = hypot(indexTip.x - thumbTip.x, indexTip.y - thumbTip.y);
        isPinchingNow = (dist < 0.05);
    }

    CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if (src) {
        if (isPinchingNow && !self.isClicking) {
            self.isClicking = YES;
            CGEventRef down = CGEventCreateMouseEvent(src, kCGEventLeftMouseDown, smoothedPos, kCGMouseButtonLeft);
            CGEventPost(kCGHIDEventTap, down);
            CFRelease(down);
        } else if (!isPinchingNow && self.isClicking) {
            self.isClicking = NO;
            CGEventRef up = CGEventCreateMouseEvent(src, kCGEventLeftMouseUp, smoothedPos, kCGMouseButtonLeft);
            CGEventPost(kCGHIDEventTap, up);
            CFRelease(up);
        } else {
            CGEventType type = self.isClicking ? kCGEventLeftMouseDragged : kCGEventMouseMoved;
            CGEventRef move = CGEventCreateMouseEvent(src, type, smoothedPos, kCGMouseButtonLeft);
            CGEventPost(kCGHIDEventTap, move);
            CFRelease(move);
        }
        CFRelease(src);
    }
}

- (void)stop {
    if (self.session) {
        [self.session stopRunning];
        self.session = nil;
    }
    [self stopCarina];
}
@end

static void CarinaCameraCallback(char *imageLeft0,
                                 char *imageRight0,
                                 char *imageLeft1,
                                 char *imageRight1,
                                 double timestamp,
                                 int width,
                                 int height) {
    g_carinaCallbacks.fetch_add(1);
    HandTracker *tracker = g_tracker;
    if (tracker) {
        if (g_carinaCallbacks.load() == 1) {
            g_engineStatus.store(kEngineStatusCarina);
            NSLog(@"Mighty Mouse: first Luma Ultra tracking frame received (%dx%d).", width, height);
        }
        // The callback's buffers are valid for the duration of this call.
        // Process left0 synchronously before returning to the SDK thread.
        [tracker processCarinaImage:imageLeft0 width:width height:height];
    }
}

extern "C" void StartGestureEngine() {
    if (!g_tracker) {
        g_tracker = [[HandTracker alloc] init];
        [g_tracker start];
    }
}

extern "C" void StopGestureEngine() {
    if (g_tracker) {
        [g_tracker stop];
        g_tracker = nil;
    }
    g_engineStatus.store(kEngineStatusUnavailable);
}

extern "C" const char *GestureEngineStatus() {
    switch (g_engineStatus.load()) {
        case kEngineStatusCarina:
            return "Luma Ultra tracking camera active";
        case kEngineStatusFrontCamera:
            return "front USB camera active (fallback)";
        case kEngineStatusPermissionDenied:
            return "camera permission denied";
        case kEngineStatusUnavailable:
            return "tracking unavailable";
        case kEngineStatusStarting:
        default:
            return "starting camera/tracking";
    }
}
