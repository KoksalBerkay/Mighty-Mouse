#include <iostream>
#include <thread>
#include <chrono>
#include <atomic>

// Cocoa/Objective-C++ headers
#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#endif

#include "GestureEngine.h"

int main() {
    setenv("OS_ACTIVITY_MODE", "disable", 1);
    std::cout << "--- Starting Hand Tracking Overlay ---" << std::endl;

    // 1. Start Hand Tracking (Apple Vision)
    // This will initialize the camera and the full-screen transparent window
    std::cout << "Starting Apple Vision Hand Tracking..." << std::endl;
    StartGestureEngine();

    std::cout << "OVERLAY ONLINE. Drawing white dot over Space Walker." << std::endl;
    std::cout << "Press Ctrl + C to stop" << std::endl;
    // 2. THE BLOCKING RUN LOOP
    // NSApp run is required to process the Vision frames and update the UI
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [NSApp run]; 
    }
    // --- Cleanup ---
    StopGestureEngine();

    return 0;
}