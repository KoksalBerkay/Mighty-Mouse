#include <iostream>
#include <thread>
#include <chrono>
#include <atomic>

// Cocoa/Objective-C++ headers
#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#endif

#include "GestureEngine.h"

@interface MightyMouseAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenuItem *cameraStatusItem;
@property (nonatomic, strong) NSMenuItem *inputStatusItem;
@end

@implementation MightyMouseAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.statusItem = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSVariableStatusItemLength];

    NSImage *icon = [NSImage imageWithSystemSymbolName:@"hand.point.up.left.fill"
                                accessibilityDescription:@"Mighty Mouse"];
    if (icon) {
        self.statusItem.button.image = icon;
    } else {
        self.statusItem.button.title = @"MM";
    }
    self.statusItem.button.toolTip = @"Mighty Mouse";

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Mighty Mouse"];
    menu.delegate = self;
    NSMenuItem *status = [[NSMenuItem alloc]
        initWithTitle:@"Mighty Mouse is running"
        action:nil
        keyEquivalent:@""];
    status.enabled = NO;
    [menu addItem:status];

    self.cameraStatusItem = [[NSMenuItem alloc]
        initWithTitle:@"Camera: checking…"
        action:nil
        keyEquivalent:@""];
    self.cameraStatusItem.enabled = NO;
    [menu addItem:self.cameraStatusItem];

    self.inputStatusItem = [[NSMenuItem alloc]
        initWithTitle:@"Cursor control: checking…"
        action:nil
        keyEquivalent:@""];
    self.inputStatusItem.enabled = NO;
    [menu addItem:self.inputStatusItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *settings = [[NSMenuItem alloc]
        initWithTitle:@"Open Privacy & Security Settings…"
        action:@selector(openPrivacySettings:)
        keyEquivalent:@""];
    settings.target = self;
    [menu addItem:settings];

    NSMenuItem *quit = [[NSMenuItem alloc]
        initWithTitle:@"Quit Mighty Mouse"
        action:@selector(quit:)
        keyEquivalent:@"q"];
    quit.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    quit.target = self;
    [menu addItem:quit];
    self.statusItem.menu = menu;
    [self refreshStatus];
}

- (void)menuWillOpen:(NSMenu *)menu {
    [self refreshStatus];
}

- (void)refreshStatus {
    AVAuthorizationStatus cameraAuthorization =
        [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    switch (cameraAuthorization) {
        case AVAuthorizationStatusAuthorized:
            self.cameraStatusItem.title = [NSString stringWithFormat:@"Tracking: %s", GestureEngineStatus()];
            break;
        case AVAuthorizationStatusNotDetermined:
            self.cameraStatusItem.title = @"Camera: permission not requested";
            break;
        case AVAuthorizationStatusDenied:
            self.cameraStatusItem.title = @"Camera: blocked in System Settings";
            break;
        case AVAuthorizationStatusRestricted:
            self.cameraStatusItem.title = @"Camera: restricted by macOS";
            break;
    }

    self.inputStatusItem.title = CGPreflightPostEventAccess()
        ? @"Cursor control: allowed"
        : @"Cursor control: Accessibility permission needed";
}

- (void)openPrivacySettings:(id)sender {
    NSURL *url = [NSURL URLWithString:
        @"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

@end

int main() {
    setenv("OS_ACTIVITY_MODE", "disable", 1);
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        MightyMouseAppDelegate *delegate = [[MightyMouseAppDelegate alloc] init];
        app.delegate = delegate;

        std::cout << "--- Mighty Mouse starting ---" << std::endl;
        std::cout << "Use the menu bar hand icon to quit." << std::endl;
        std::cout << "Camera authorization: "
                  << (long)[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]
                  << std::endl;
        std::cout << "Accessibility post-event access: "
                  << (CGPreflightPostEventAccess() ? "allowed" : "needed")
                  << std::endl;
        if (!CGPreflightPostEventAccess()) {
            std::cout << "Requesting Accessibility permission..." << std::endl;
            CGRequestPostEventAccess();
        }
        StartGestureEngine();
        [app run];

        StopGestureEngine();
    }

    return 0;
}
