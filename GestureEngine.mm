#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>
#import <CoreGraphics/CoreGraphics.h>
#include "GestureEngine.h"

@interface HandTracker : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, assign) BOOL isClicking;
@property (nonatomic, assign) CGSize screenSize;
@property (nonatomic, assign) CGPoint lastMousePos;
@property (nonatomic, assign) BOOL hasFirstPos;
@end

@implementation HandTracker

- (instancetype)init {
    self = [super init];
    if (self) {
        _isClicking = NO;
        _hasFirstPos = NO;
        _screenSize = CGDisplayBounds(CGMainDisplayID()).size;
    }
    return self;
}

- (void)start {
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        if (!granted) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setupCamera];
        });
    }];
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

    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:vitureDevice error:&error];
    if ([self.session canAddInput:input]) [self.session addInput:input];

    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    dispatch_queue_t videoQueue = dispatch_queue_create("com.viture.handtracking", DISPATCH_QUEUE_SERIAL);
    [output setSampleBufferDelegate:self queue:videoQueue];
    if ([self.session canAddOutput:output]) [self.session addOutput:output];
    
    NSRect screenRect = [[NSScreen mainScreen] frame];
    [self.session startRunning];
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer options:@{}];
    VNDetectHumanHandPoseRequest *request = [[VNDetectHumanHandPoseRequest alloc] init];
    
    [handler performRequests:@[request] error:nil];
    
    if (request.results.count > 0) {
        [self processHand:request.results.firstObject];
    }
}

- (void)processHand:(VNHumanHandPoseObservation *)hand {
    VNRecognizedPoint *indexTip = [hand recognizedPointForJointName:VNHumanHandPoseObservationJointNameIndexTip error:nil];
    VNRecognizedPoint *thumbTip = [hand recognizedPointForJointName:VNHumanHandPoseObservationJointNameThumbTip error:nil];
    
    if (indexTip.confidence < 0.5 || thumbTip.confidence < 0.5) return;

    // 1. CALCULATE MIDPOINT (Prevents shifting during pinch)
    CGFloat midX = (indexTip.x + thumbTip.x) / 2.0;
    CGFloat midY = (indexTip.y + thumbTip.y) / 2.0;

    // 2. PINCH DETECTION
    CGFloat dist = hypot(indexTip.x - thumbTip.x, indexTip.y - thumbTip.y);
    BOOL isPinchingNow = (dist < 0.05); // Adjust sensitivity here

    // 3. SMOOTHING & MAPPING
    CGFloat targetX = midX * self.screenSize.width;
    CGFloat targetY = (1.0 - midY) * self.screenSize.height;

    if (!self.hasFirstPos) {
        self.lastMousePos = CGPointMake(targetX, targetY);
        self.hasFirstPos = YES;
    }

    // High smoothing for the dot, low latency for the click
    CGFloat alpha = 0.25; 
    CGPoint smoothedPos = CGPointMake(
        (targetX * alpha) + (self.lastMousePos.x * (1.0 - alpha)),
        (targetY * alpha) + (self.lastMousePos.y * (1.0 - alpha))
    );
    self.lastMousePos = smoothedPos;

    // 4. GENERATE SYSTEM CLICKS
    CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
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
    if(src) CFRelease(src);
}

- (void)stop {
    if (self.session) {
        [self.session stopRunning];
        self.session = nil;
    }
}
@end

static HandTracker *g_tracker = nil;

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
}