#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>
#include <atomic>
#include <mutex>
#include "viture_device_carina.h"
#include "GestureEngine.h"
#include "Preferences.h"
#include "GestureInterpreter.h"
#include "GestureGeometry.h"
#include "CursorMotion.h"

@class HandTracker;
static HandTracker *g_tracker = nil;
static std::atomic<int> g_engineStatus{0};
static std::atomic<int> g_carinaCallbacks{0};
static std::atomic<bool> g_trackingEnabled{true};
static std::mutex g_eventMutex;

enum {
    kPinchIdle = 0,
    kPinchCandidate = 1,
    kPinchArmed = 2,
};

enum {
    kEngineStatusStarting = 0,
    kEngineStatusCarina = 1,
    kEngineStatusFrontCamera = 2,
    kEngineStatusUnavailable = 3,
    kEngineStatusPermissionDenied = 4,
};

static CGFloat DistanceBetweenPoints(VNRecognizedPoint *first, VNRecognizedPoint *second) {
    if (!first || !second) return 0.0;
    return hypot(first.location.x - second.location.x,
                 first.location.y - second.location.y);
}

static GestureLandmark VisionLandmark(VNHumanHandPoseObservation *hand,
                                      VNRecognizedPointKey name) {
    VNRecognizedPoint *point = [hand recognizedPointForJointName:name error:nil];
    if (!point) return GestureLandmark{0.0, 0.0, 0.0};
    return GestureLandmark{point.location.x, point.location.y, point.confidence};
}

static double FingerExtensionScore(VNHumanHandPoseObservation *hand,
                                   VNRecognizedPointKey tipName,
                                   VNRecognizedPointKey pipName,
                                   VNRecognizedPointKey dipName,
                                   VNRecognizedPointKey mcpName) {
    return GestureFingerExtensionScore(VisionLandmark(hand, tipName),
                                       VisionLandmark(hand, pipName),
                                       VisionLandmark(hand, dipName),
                                       VisionLandmark(hand, mcpName));
}

static double FingerFoldScore(VNHumanHandPoseObservation *hand,
                              VNRecognizedPointKey tipName,
                              VNRecognizedPointKey pipName,
                              VNRecognizedPointKey mcpName) {
    return GestureFingerFoldScore(VisionLandmark(hand, tipName),
                                  VisionLandmark(hand, pipName),
                                  VisionLandmark(hand, mcpName));
}

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
@property (nonatomic, strong) VNDetectHumanHandPoseRequest *handPoseRequest;
@property (nonatomic, assign) BOOL isClicking;
@property (nonatomic, assign) CGSize screenSize;
@property (nonatomic, assign) CGPoint lastMousePos;
@property (nonatomic, assign) BOOL hasFirstPos;
@property (nonatomic, assign) XRDeviceProviderHandle carinaHandle;
@property (nonatomic, assign) BOOL usingCarina;
@property (nonatomic, assign) NSInteger pinchState;
@property (nonatomic, assign) CFAbsoluteTime pinchStartTime;
@property (nonatomic, assign) CFAbsoluteTime pinchLockoutUntil;
@property (nonatomic, assign) CGPoint pinchStartIndex;
@property (nonatomic, assign) CGPoint pinchAnchor;
@property (nonatomic, assign) BOOL dragActive;
@property (nonatomic, assign) CFAbsoluteTime lastHandSeenTime;
@property (nonatomic, assign) ScrollInterpreter *scrollInterpreter;
@property (nonatomic, assign) ScrollPoseClassifier *scrollPoseClassifier;
@property (nonatomic, assign) CursorMotion *cursorMotion;
@property (nonatomic, assign) CGEventSourceRef eventSource;
@property (nonatomic, assign) CFAbsoluteTime pointingPoseStartTime;
@property (nonatomic, assign) BOOL pointingPoseActive;
@end

@implementation HandTracker

- (instancetype)init {
    self = [super init];
    if (self) {
        _isClicking = NO;
        _handPoseRequest = [[VNDetectHumanHandPoseRequest alloc] init];
        _handPoseRequest.maximumHandCount = 1;
        _hasFirstPos = NO;
        _carinaHandle = NULL;
        _usingCarina = NO;
        _pinchState = 0;
        _pinchStartTime = 0.0;
        _pinchLockoutUntil = 0.0;
        _pinchStartIndex = CGPointZero;
        _pinchAnchor = CGPointZero;
        _dragActive = NO;
        _lastHandSeenTime = 0.0;
        _scrollInterpreter = new ScrollInterpreter();
        _scrollPoseClassifier = new ScrollPoseClassifier();
        _cursorMotion = new CursorMotion();
        _eventSource = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
        _pointingPoseStartTime = 0.0;
        _pointingPoseActive = NO;
        _screenSize = CGDisplayBounds(CGMainDisplayID()).size;
    }
    return self;
}

- (void)dealloc {
    delete _scrollInterpreter;
    delete _scrollPoseClassifier;
    delete _cursorMotion;
    if (_eventSource) CFRelease(_eventSource);
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
    output.alwaysDiscardsLateVideoFrames = YES;
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

    NSError *visionError = nil;
    [handler performRequests:@[self.handPoseRequest] error:&visionError];
    if (visionError) return;
    
    if (self.handPoseRequest.results.count > 0) {
        self.lastHandSeenTime = CFAbsoluteTimeGetCurrent();
        [self processHand:self.handPoseRequest.results.firstObject];
    } else if (self.pinchState != kPinchIdle || self.scrollInterpreter->IsEngaged()) {
        // Vision occasionally loses the hand for a few frames. Do not leave
        // a drag pressed or a scroll mode latched when that happens.
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (self.lastHandSeenTime == 0.0 || now - self.lastHandSeenTime >= 0.18) {
            [self resetInteraction];
        }
    }
}

- (void)postMouseEvent:(CGEventType)type at:(CGPoint)point {
    std::lock_guard<std::mutex> lock(g_eventMutex);
    if (!self.eventSource) return;
    CGEventRef event = CGEventCreateMouseEvent(self.eventSource, type, point, kCGMouseButtonLeft);
    if (event) {
        CGEventPost(kCGHIDEventTap, event);
        CFRelease(event);
    }
}

- (void)postClickAt:(CGPoint)point {
    [self postMouseEvent:kCGEventLeftMouseDown at:point];
    [self postMouseEvent:kCGEventLeftMouseUp at:point];
}

- (void)postScrollLines:(int)lines {
    if (lines == 0) return;
    std::lock_guard<std::mutex> lock(g_eventMutex);
    if (!self.eventSource) return;
    CGEventRef scroll = CGEventCreateScrollWheelEvent(self.eventSource,
                                                       kCGScrollEventUnitLine,
                                                       1,
                                                       lines);
    if (scroll) {
        CGEventPost(kCGHIDEventTap, scroll);
        CFRelease(scroll);
    }
}

- (void)processHand:(VNHumanHandPoseObservation *)hand {
    VNRecognizedPoint *indexTip = [hand recognizedPointForJointName:VNHumanHandPoseObservationJointNameIndexTip error:nil];
    VNRecognizedPoint *thumbTip = [hand recognizedPointForJointName:VNHumanHandPoseObservationJointNameThumbTip error:nil];

    if (!g_trackingEnabled.load()) return;
    GestureSettings settings = CurrentGestureSettings();
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();

    // Use hand-relative pinch distance so clicking is stable at different
    // distances from the camera. Hysteresis prevents natural fingertip jitter
    // from repeatedly entering and leaving the pinch state.
    VNRecognizedPoint *wrist = [hand recognizedPointForJointName:VNHumanHandPoseObservationJointNameWrist error:nil];
    VNRecognizedPoint *middleMCP = [hand recognizedPointForJointName:VNHumanHandPoseObservationJointNameMiddleMCP error:nil];
    CGFloat palmScale = DistanceBetweenPoints(wrist, middleMCP);
    CGFloat pinchRatio = palmScale > 0.01
        ? DistanceBetweenPoints(indexTip, thumbTip) / palmScale
        : 1.0;
    const CGFloat minimumIndexConfidence = 0.45;
    const CGFloat minimumThumbConfidence = 0.45;
    const CGFloat pinchEnterRatio = settings.pinchEnterRatio;
    const CGFloat pinchExitRatio = settings.pinchExitRatio;
    BOOL isPinchingNow = indexTip.confidence >= minimumIndexConfidence &&
                         thumbTip.confidence >= minimumThumbConfidence &&
                         pinchRatio < (self.pinchState == kPinchIdle ? pinchEnterRatio : pinchExitRatio);

    // Finger geometry is evaluated from local joints rather than wrist
    // distance. That makes the pose tolerant of diagonal and rotated hands.
    VNRecognizedPoint *indexPIP = [hand recognizedPointForJointName:VNHumanHandPoseObservationJointNameIndexPIP error:nil];
    VNRecognizedPoint *indexDIP = [hand recognizedPointForJointName:VNHumanHandPoseObservationJointNameIndexDIP error:nil];
    VNRecognizedPoint *indexMCP = [hand recognizedPointForJointName:VNHumanHandPoseObservationJointNameIndexMCP error:nil];
    VNRecognizedPoint *middleTip = [hand recognizedPointForJointName:VNHumanHandPoseObservationJointNameMiddleTip error:nil];
    VNRecognizedPoint *middlePIP = [hand recognizedPointForJointName:VNHumanHandPoseObservationJointNameMiddlePIP error:nil];
    VNRecognizedPoint *middleDIP = [hand recognizedPointForJointName:VNHumanHandPoseObservationJointNameMiddleDIP error:nil];
    VNRecognizedPoint *middleMCPPoint = [hand recognizedPointForJointName:VNHumanHandPoseObservationJointNameMiddleMCP error:nil];
    // Keep continuous evidence instead of making each finger a hard yes/no.
    // Vision can move a joint a few pixels between frames, especially when
    // the hand is diagonal. The classifier adds dwell and release hysteresis
    // on top of these scores so a borderline two-finger pose does not leak
    // through as cursor movement.
    double indexExtensionScore = FingerExtensionScore(
        hand,
        VNHumanHandPoseObservationJointNameIndexTip,
        VNHumanHandPoseObservationJointNameIndexPIP,
        VNHumanHandPoseObservationJointNameIndexDIP,
        VNHumanHandPoseObservationJointNameIndexMCP);
    double middleExtensionScore = FingerExtensionScore(
        hand,
        VNHumanHandPoseObservationJointNameMiddleTip,
        VNHumanHandPoseObservationJointNameMiddlePIP,
        VNHumanHandPoseObservationJointNameMiddleDIP,
        VNHumanHandPoseObservationJointNameMiddleMCP);
    double ringFoldScore = FingerFoldScore(
        hand,
        VNHumanHandPoseObservationJointNameRingTip,
        VNHumanHandPoseObservationJointNameRingPIP,
        VNHumanHandPoseObservationJointNameRingMCP);
    double littleFoldScore = FingerFoldScore(
        hand,
        VNHumanHandPoseObservationJointNameLittleTip,
        VNHumanHandPoseObservationJointNameLittlePIP,
        VNHumanHandPoseObservationJointNameLittleMCP);

    bool scrollPoseNow = false;
    bool scrollIntentNow = false;
    if (isPinchingNow) {
        // A pinch is reserved for click/drag and should also force a fresh
        // two-finger acquisition after a scroll clutch.
        self.scrollPoseClassifier->Reset();
    } else {
        ScrollPoseEvidence evidence{
            indexExtensionScore,
            middleExtensionScore,
            ringFoldScore,
            littleFoldScore,
        };
        scrollPoseNow = self.scrollPoseClassifier->Update(
            evidence,
            static_cast<double>(now),
            settings.scrollPoseSensitivity);
        scrollIntentNow = self.scrollPoseClassifier->IsIntentLikely();
    }

    CGPoint scrollPoint = indexTip
        ? (middleTip
        ? CGPointMake((indexTip.location.x + middleTip.location.x) / 2.0,
                      (indexTip.location.y + middleTip.location.y) / 2.0)
        : indexTip.location)
        : CGPointZero;
    ScrollFrame scrollFrame{
        static_cast<double>(now),
        true,
        static_cast<bool>(scrollPoseNow),
        static_cast<bool>(isPinchingNow && self.scrollInterpreter->IsScrolling()),
        GesturePoint{scrollPoint.x, scrollPoint.y},
    };
    int scrollLines = self.scrollInterpreter->ProcessFrame(scrollFrame, settings);
    if (scrollLines != 0) [self postScrollLines:scrollLines];
    if (self.scrollInterpreter->IsEngaged() || scrollIntentNow) {
        self.pointingPoseStartTime = 0.0;
        self.pointingPoseActive = NO;
        return;
    }

    // Pinch is a latched interaction. The pointer is held at its anchor while
    // the pinch settles. A short, stable pinch followed by release is a click;
    // a deliberate movement after the drag hold threshold becomes a drag.
    if (isPinchingNow) {
        if (self.pinchState == kPinchIdle && now < self.pinchLockoutUntil) return;
        if (self.pinchState == kPinchIdle) {
            self.pinchState = kPinchCandidate;
            self.pinchStartTime = now;
            self.pinchStartIndex = indexTip.location;
            if (!self.hasFirstPos) {
                self.lastMousePos = [NSEvent mouseLocation];
                self.hasFirstPos = YES;
            }
            self.pinchAnchor = self.lastMousePos;
            self.dragActive = NO;
        } else if (self.pinchState == kPinchCandidate &&
                   now - self.pinchStartTime >= settings.pinchActivationDelay) {
            self.pinchState = kPinchArmed;
        }

        if (self.pinchState == kPinchArmed &&
            now - self.pinchStartTime >= settings.dragHoldDuration) {
            CGFloat intentionalMovement = hypot(indexTip.location.x - self.pinchStartIndex.x,
                                                indexTip.location.y - self.pinchStartIndex.y);
            if (intentionalMovement > settings.dragMovementThreshold) {
                if (!self.isClicking) {
                    [self postMouseEvent:kCGEventLeftMouseDown at:self.pinchAnchor];
                    self.isClicking = YES;
                }
                self.dragActive = YES;
            }
        }
        if (!self.dragActive) return;
    } else if (self.pinchState != kPinchIdle) {
        if (self.isClicking) {
            self.isClicking = NO;
            [self postMouseEvent:kCGEventLeftMouseUp at:self.lastMousePos];
        } else if (self.pinchState == kPinchArmed) {
            [self postClickAt:self.pinchAnchor];
            self.pinchLockoutUntil = now + 0.08;
        }
        self.pinchState = kPinchIdle;
        self.pinchStartTime = 0.0;
        self.dragActive = NO;
        return;
    }

    // Keep cursor movement permissive: Vision's index confidence is the
    // reliable pointing signal, while the stricter finger pose is reserved
    // for recognizing scroll. Requiring every other finger to be folded made
    // normal pointing intermittently disappear at different hand angles.
    if (indexTip.confidence < minimumIndexConfidence) return;

    // EDGE-TO-EDGE MAPPING LOGIC. The camera center is 0.5; gain stretches
    // the reachable area while clamping keeps the pointer on-screen.
    CGFloat gain = settings.cursorGain;
    CGFloat mappedX = (indexTip.location.x - 0.5) * gain + 0.5;
    CGFloat mappedY = (indexTip.location.y - 0.5) * gain + 0.5;
    mappedX = fmax(0.0, fmin(1.0, mappedX));
    mappedY = fmax(0.0, fmin(1.0, mappedY));
    CGFloat targetX = mappedX * self.screenSize.width;
    CGFloat targetY = (1.0 - mappedY) * self.screenSize.height;

    if (!self.hasFirstPos) {
        self.lastMousePos = CGPointMake(targetX, targetY);
        self.hasFirstPos = YES;
    }

    CursorMotionResult motion = self.cursorMotion->Update(
        CursorPoint{targetX, targetY},
        fmin(self.screenSize.width, self.screenSize.height),
        settings,
        self.dragActive);
    if (!motion.moved) return;
    CGPoint smoothedPos = CGPointMake(motion.point.x, motion.point.y);
    self.lastMousePos = smoothedPos;

    CGEventType type = self.dragActive ? kCGEventLeftMouseDragged : kCGEventMouseMoved;
    [self postMouseEvent:type at:smoothedPos];
}

- (void)resetInteraction {
    if (self.isClicking) {
        [self postMouseEvent:kCGEventLeftMouseUp at:self.lastMousePos];
    }
    self.isClicking = NO;
    self.pinchState = kPinchIdle;
    self.pinchStartTime = 0.0;
    self.pinchLockoutUntil = 0.0;
    self.dragActive = NO;
    self.scrollInterpreter->Reset();
    self.scrollPoseClassifier->Reset();
    self.cursorMotion->Reset();
    self.pointingPoseStartTime = 0.0;
    self.pointingPoseActive = NO;
    self.lastHandSeenTime = 0.0;
    self.hasFirstPos = NO;
}

- (void)stop {
    [self resetInteraction];
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
    g_trackingEnabled.store(true);
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

extern "C" void SetGestureTrackingEnabled(bool enabled) {
    g_trackingEnabled.store(enabled);
    if (!enabled && g_tracker) {
        [g_tracker resetInteraction];
    }
}

extern "C" bool GestureTrackingIsEnabled() {
    return g_trackingEnabled.load();
}

extern "C" const char *GestureEngineStatus() {
    if (!g_trackingEnabled.load()) return "paused";
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
