#include <iostream>
#include <thread>
#include <chrono>
#include <atomic>
#include <cmath>

// Cocoa/Objective-C++ headers
#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ApplicationServices/ApplicationServices.h>
#endif

#include "GestureEngine.h"
#include "Preferences.h"

static BOOL AccessibilityPermissionGranted() {
    return AXIsProcessTrusted();
}

enum {
    kQuickCursorGain = 1,
    kQuickCursorSmoothing = 2,
    kQuickScrollSpeed = 3,
    kQuickScrollDirection = 4,
    kQuickScrollAcceleration = 5,
    kQuickScrollClutch = 6,
};

enum {
    kSettingCursorGain = 101,
    kSettingCursorSmoothing = 102,
    kSettingCursorDeadzone = 103,
    kSettingCursorMaxStep = 104,
    kSettingPinchSensitivity = 105,
    kSettingPinchStabilization = 106,
    kSettingDragHold = 107,
    kSettingDragMovement = 108,
    kSettingScrollSpeed = 109,
    kSettingScrollAcceleration = 110,
    kSettingScrollSmoothing = 111,
    kSettingScrollActivation = 112,
    kSettingScrollDeadzone = 113,
};

@interface MightyMouseAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenuItem *cameraStatusItem;
@property (nonatomic, strong) NSMenuItem *inputStatusItem;
@property (nonatomic, strong) NSMenuItem *trackingToggleItem;
@property (nonatomic, strong) NSWindow *settingsWindow;
@property (nonatomic, strong) NSSlider *cursorGainSlider;
@property (nonatomic, strong) NSSlider *cursorSmoothingSlider;
@property (nonatomic, strong) NSSlider *cursorDeadzoneSlider;
@property (nonatomic, strong) NSSlider *cursorMaxStepSlider;
@property (nonatomic, strong) NSSlider *pinchSensitivitySlider;
@property (nonatomic, strong) NSSlider *pinchStabilizationSlider;
@property (nonatomic, strong) NSSlider *dragHoldSlider;
@property (nonatomic, strong) NSSlider *dragMovementSlider;
@property (nonatomic, strong) NSSlider *scrollSpeedSlider;
@property (nonatomic, strong) NSSlider *scrollAccelerationSlider;
@property (nonatomic, strong) NSSlider *scrollSmoothingSlider;
@property (nonatomic, strong) NSSlider *scrollActivationSlider;
@property (nonatomic, strong) NSSlider *scrollDeadzoneSlider;
@property (nonatomic, strong) NSButton *invertScrollButton;
@property (nonatomic, strong) NSButton *scrollClutchButton;
@property (nonatomic, strong) NSMutableDictionary *settingValueLabels;
@property (nonatomic, strong) NSArray *cursorGainPresetItems;
@property (nonatomic, strong) NSArray *cursorSmoothingPresetItems;
@property (nonatomic, strong) NSArray *scrollSpeedPresetItems;
@property (nonatomic, strong) NSArray *scrollAccelerationPresetItems;
@property (nonatomic, strong) NSArray *scrollDirectionPresetItems;
@property (nonatomic, strong) NSArray *scrollClutchPresetItems;
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

    self.trackingToggleItem = [[NSMenuItem alloc]
        initWithTitle:@"Pause Tracking"
        action:@selector(toggleTracking:)
        keyEquivalent:@"p"];
    self.trackingToggleItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    self.trackingToggleItem.target = self;
    [menu addItem:self.trackingToggleItem];

    NSMenuItem *quickSettings = [[NSMenuItem alloc]
        initWithTitle:@"Quick Settings"
        action:nil
        keyEquivalent:@""];
    NSMenu *quickMenu = [[NSMenu alloc] initWithTitle:@"Quick Settings"];
    self.cursorGainPresetItems = [self addPresetSubmenuTo:quickMenu
                                                      title:@"Cursor Sensitivity"
                                                       kind:kQuickCursorGain
                                                     values:@[@1.30, @1.60, @2.00]
                                                     labels:@[@"Low", @"Balanced", @"High"]];
    self.cursorSmoothingPresetItems = [self addPresetSubmenuTo:quickMenu
                                                          title:@"Cursor Response"
                                                           kind:kQuickCursorSmoothing
                                                         values:@[@0.18, @0.26, @0.38]
                                                         labels:@[@"Steady", @"Balanced", @"Responsive"]];
    self.scrollSpeedPresetItems = [self addPresetSubmenuTo:quickMenu
                                                     title:@"Scroll Speed"
                                                      kind:kQuickScrollSpeed
                                                    values:@[@0.60, @1.00, @1.50, @2.20]
                                                    labels:@[@"Slow", @"Balanced", @"Fast", @"Very Fast"]];
    self.scrollAccelerationPresetItems = [self addPresetSubmenuTo:quickMenu
                                                           title:@"Scroll Acceleration"
                                                            kind:kQuickScrollAcceleration
                                                          values:@[@0.00, @0.15, @0.35]
                                                          labels:@[@"Off", @"Mild", @"Strong"]];
    self.scrollClutchPresetItems = [self addPresetSubmenuTo:quickMenu
                                                    title:@"Scroll Clutch"
                                                     kind:kQuickScrollClutch
                                                   values:@[@NO, @YES]
                                                   labels:@[@"Off", @"On"]];
    self.scrollDirectionPresetItems = [self addPresetSubmenuTo:quickMenu
                                                          title:@"Scroll Direction"
                                                           kind:kQuickScrollDirection
                                                         values:@[@NO, @YES]
                                                         labels:@[@"Natural", @"Reversed"]];
    quickSettings.submenu = quickMenu;
    [menu addItem:quickSettings];

    NSMenuItem *settings = [[NSMenuItem alloc]
        initWithTitle:@"Open Settings…"
        action:@selector(openSettings:)
        keyEquivalent:@","];
    settings.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    settings.target = self;
    [menu addItem:settings];

    NSMenuItem *reset = [[NSMenuItem alloc]
        initWithTitle:@"Restore Default Settings"
        action:@selector(resetSettings:)
        keyEquivalent:@""];
    reset.target = self;
    [menu addItem:reset];

    NSMenuItem *privacy = [[NSMenuItem alloc]
        initWithTitle:@"Open Privacy & Security Settings…"
        action:@selector(openPrivacySettings:)
        keyEquivalent:@""];
    privacy.target = self;
    [menu addItem:privacy];

    NSMenuItem *quit = [[NSMenuItem alloc]
        initWithTitle:@"Quit Mighty Mouse"
        action:@selector(quit:)
        keyEquivalent:@"q"];
    quit.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    quit.target = self;
    [menu addItem:quit];
    self.statusItem.menu = menu;
    self.settingValueLabels = [NSMutableDictionary dictionary];
    [self refreshStatus];
}

- (NSArray *)addPresetSubmenuTo:(NSMenu *)parent
                           title:(NSString *)title
                            kind:(NSInteger)kind
                          values:(NSArray *)values
                          labels:(NSArray *)labels {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    NSMenu *submenu = [[NSMenu alloc] initWithTitle:title];
    NSMutableArray *presetItems = [NSMutableArray arrayWithCapacity:values.count];
    for (NSUInteger index = 0; index < values.count; index++) {
        NSMenuItem *preset = [[NSMenuItem alloc]
            initWithTitle:labels[index]
            action:@selector(applyQuickSetting:)
            keyEquivalent:@""];
        preset.target = self;
        preset.tag = kind;
        preset.representedObject = values[index];
        [submenu addItem:preset];
        [presetItems addObject:preset];
    }
    item.submenu = submenu;
    [parent addItem:item];
    return presetItems;
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

    self.inputStatusItem.title = AccessibilityPermissionGranted()
        ? @"Cursor control: allowed"
        : @"Cursor control: Accessibility permission needed";
    self.trackingToggleItem.title = GestureTrackingIsEnabled()
        ? @"Pause Tracking"
        : @"Resume Tracking";
    [self refreshQuickSettingsState];
}

- (void)refreshQuickSettingsState {
    GestureSettings settings = CurrentGestureSettings();
    for (NSMenuItem *item in self.cursorGainPresetItems) {
        item.state = fabs([item.representedObject doubleValue] - settings.cursorGain) < 0.001
            ? NSControlStateValueOn : NSControlStateValueOff;
    }
    for (NSMenuItem *item in self.cursorSmoothingPresetItems) {
        item.state = fabs([item.representedObject doubleValue] - settings.cursorSmoothing) < 0.001
            ? NSControlStateValueOn : NSControlStateValueOff;
    }
    for (NSMenuItem *item in self.scrollSpeedPresetItems) {
        item.state = fabs([item.representedObject doubleValue] - settings.scrollSpeed) < 0.001
            ? NSControlStateValueOn : NSControlStateValueOff;
    }
    for (NSMenuItem *item in self.scrollAccelerationPresetItems) {
        item.state = fabs([item.representedObject doubleValue] - settings.scrollAcceleration) < 0.001
            ? NSControlStateValueOn : NSControlStateValueOff;
    }
    for (NSMenuItem *item in self.scrollDirectionPresetItems) {
        item.state = [item.representedObject boolValue] == settings.invertScroll
            ? NSControlStateValueOn : NSControlStateValueOff;
    }
    for (NSMenuItem *item in self.scrollClutchPresetItems) {
        item.state = [item.representedObject boolValue] == settings.scrollClutchEnabled
            ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void)applyQuickSetting:(NSMenuItem *)sender {
    GestureSettings settings = CurrentGestureSettings();
    double value = [sender.representedObject doubleValue];
    switch (sender.tag) {
        case kQuickCursorGain:
            settings.cursorGain = value;
            break;
        case kQuickCursorSmoothing:
            settings.cursorSmoothing = value;
            break;
        case kQuickScrollSpeed:
            settings.scrollSpeed = value;
            break;
        case kQuickScrollAcceleration:
            settings.scrollAcceleration = value;
            break;
        case kQuickScrollDirection:
            settings.invertScroll = [sender.representedObject boolValue];
            break;
        case kQuickScrollClutch:
            settings.scrollClutchEnabled = [sender.representedObject boolValue];
            break;
    }
    SaveGestureSettings(settings);
    [self refreshSettingsControls];
    [self refreshQuickSettingsState];
}

- (NSString *)valueDescriptionForSettingTag:(NSInteger)tag settings:(GestureSettings)settings {
    switch (tag) {
        case kSettingCursorGain:
            return [NSString stringWithFormat:@"%.2fx", settings.cursorGain];
        case kSettingCursorSmoothing:
            if (settings.cursorSmoothing < 0.22) return @"Steady";
            if (settings.cursorSmoothing < 0.36) return @"Balanced";
            return @"Responsive";
        case kSettingCursorDeadzone:
            return [NSString stringWithFormat:@"%.3f", settings.cursorDeadzone];
        case kSettingCursorMaxStep:
            return [NSString stringWithFormat:@"%.0f px", settings.cursorMaxStep];
        case kSettingPinchSensitivity:
            if (settings.pinchEnterRatio < 0.24) return @"Firm";
            if (settings.pinchEnterRatio < 0.32) return @"Balanced";
            return @"Gentle";
        case kSettingPinchStabilization:
            return [NSString stringWithFormat:@"%.0f ms", settings.pinchActivationDelay * 1000.0];
        case kSettingDragHold:
            return [NSString stringWithFormat:@"%.0f ms", settings.dragHoldDuration * 1000.0];
        case kSettingDragMovement:
            return [NSString stringWithFormat:@"%.3f", settings.dragMovementThreshold];
        case kSettingScrollSpeed:
            return [NSString stringWithFormat:@"%.2fx", settings.scrollSpeed];
        case kSettingScrollAcceleration:
            if (settings.scrollAcceleration < 0.10) return @"Off";
            if (settings.scrollAcceleration < 0.28) return @"Mild";
            return @"Strong";
        case kSettingScrollSmoothing:
            if (settings.scrollSmoothing < 0.24) return @"Steady";
            if (settings.scrollSmoothing < 0.44) return @"Balanced";
            return @"Responsive";
        case kSettingScrollActivation:
            return [NSString stringWithFormat:@"%.0f ms", settings.scrollActivationDelay * 1000.0];
        case kSettingScrollDeadzone:
            return [NSString stringWithFormat:@"%.3f", settings.scrollDeadzone];
    }
    return @"";
}

- (void)refreshSettingValueLabels {
    if (!self.settingValueLabels) return;
    GestureSettings settings = CurrentGestureSettings();
    for (NSNumber *tagNumber in self.settingValueLabels) {
        NSTextField *label = self.settingValueLabels[tagNumber];
        label.stringValue = [self valueDescriptionForSettingTag:tagNumber.integerValue
                                                        settings:settings];
    }
}

- (NSSlider *)addSliderRowToView:(NSView *)view
                           title:(NSString *)title
                              tag:(NSInteger)tag
                          minimum:(double)minimum
                          maximum:(double)maximum
                            value:(double)value
                                y:(CGFloat)y {
    NSTextField *titleLabel = [NSTextField labelWithString:title];
    titleLabel.frame = NSMakeRect(24.0, y + 5.0, 148.0, 22.0);
    [view addSubview:titleLabel];

    NSSlider *slider = [NSSlider sliderWithValue:value
                                         minValue:minimum
                                         maxValue:maximum
                                            target:self
                                            action:@selector(settingsChanged:)];
    slider.frame = NSMakeRect(174.0, y, 270.0, 30.0);
    slider.tag = tag;
    slider.continuous = YES;
    [view addSubview:slider];

    NSTextField *valueLabel = [NSTextField labelWithString:@""];
    valueLabel.frame = NSMakeRect(450.0, y + 5.0, 56.0, 22.0);
    valueLabel.alignment = NSTextAlignmentRight;
    valueLabel.textColor = [NSColor secondaryLabelColor];
    [view addSubview:valueLabel];
    self.settingValueLabels[@(tag)] = valueLabel;
    return slider;
}

- (NSTextField *)addSectionTitleToView:(NSView *)view title:(NSString *)title y:(CGFloat)y {
    NSTextField *label = [NSTextField labelWithString:title];
    label.frame = NSMakeRect(24.0, y, 470.0, 24.0);
    label.font = [NSFont boldSystemFontOfSize:14.0];
    [view addSubview:label];
    return label;
}

- (void)buildSettingsWindow {
    self.settingValueLabels = [NSMutableDictionary dictionary];
    NSRect frame = NSMakeRect(0.0, 0.0, 520.0, 760.0);
    self.settingsWindow = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self.settingsWindow.title = @"Mighty Mouse Settings";
    self.settingsWindow.releasedWhenClosed = NO;

    NSView *content = self.settingsWindow.contentView;
    NSTextField *description = [NSTextField labelWithString:
        @"Changes apply immediately and are saved automatically."];
    description.frame = NSMakeRect(24.0, 714.0, 470.0, 24.0);
    description.textColor = [NSColor secondaryLabelColor];
    [content addSubview:description];

    [self addSectionTitleToView:content title:@"Cursor" y:674.0];
    GestureSettings settings = CurrentGestureSettings();
    self.cursorGainSlider = [self addSliderRowToView:content
                                               title:@"Sensitivity"
                                                  tag:kSettingCursorGain
                                              minimum:1.0
                                              maximum:2.6
                                                value:settings.cursorGain
                                                    y:638.0];
    self.cursorSmoothingSlider = [self addSliderRowToView:content
                                                    title:@"Response"
                                                       tag:kSettingCursorSmoothing
                                                   minimum:0.12
                                                   maximum:0.55
                                                     value:settings.cursorSmoothing
                                                         y:602.0];
    self.cursorDeadzoneSlider = [self addSliderRowToView:content
                                                   title:@"Movement deadzone"
                                                      tag:kSettingCursorDeadzone
                                                  minimum:0.0
                                                  maximum:0.025
                                                    value:settings.cursorDeadzone
                                                        y:566.0];
    self.cursorMaxStepSlider = [self addSliderRowToView:content
                                                 title:@"Maximum step"
                                                    tag:kSettingCursorMaxStep
                                                minimum:0.0
                                                maximum:600.0
                                                  value:settings.cursorMaxStep
                                                      y:530.0];

    [self addSectionTitleToView:content title:@"Click and Drag" y:494.0];
    self.pinchSensitivitySlider = [self addSliderRowToView:content
                                                      title:@"Pinch sensitivity"
                                                         tag:kSettingPinchSensitivity
                                                     minimum:0.18
                                                     maximum:0.40
                                                       value:settings.pinchEnterRatio
                                                           y:458.0];
    self.pinchStabilizationSlider = [self addSliderRowToView:content
                                                        title:@"Pinch stabilization"
                                                           tag:kSettingPinchStabilization
                                                       minimum:0.04
                                                       maximum:0.25
                                                         value:settings.pinchActivationDelay
                                                             y:422.0];
    self.dragHoldSlider = [self addSliderRowToView:content
                                             title:@"Drag hold"
                                                tag:kSettingDragHold
                                            minimum:0.20
                                            maximum:0.90
                                              value:settings.dragHoldDuration
                                                  y:386.0];
    self.dragMovementSlider = [self addSliderRowToView:content
                                                 title:@"Drag movement"
                                                    tag:kSettingDragMovement
                                                minimum:0.018
                                                maximum:0.12
                                                  value:settings.dragMovementThreshold
                                                      y:350.0];

    [self addSectionTitleToView:content title:@"Scrolling" y:314.0];
    self.scrollSpeedSlider = [self addSliderRowToView:content
                                                title:@"Speed"
                                                   tag:kSettingScrollSpeed
                                               minimum:0.25
                                               maximum:3.0
                                                 value:settings.scrollSpeed
                                                     y:278.0];
    self.scrollAccelerationSlider = [self addSliderRowToView:content
                                                       title:@"Acceleration"
                                                          tag:kSettingScrollAcceleration
                                                      minimum:0.0
                                                      maximum:1.0
                                                        value:settings.scrollAcceleration
                                                            y:242.0];
    self.scrollSmoothingSlider = [self addSliderRowToView:content
                                                    title:@"Response"
                                                       tag:kSettingScrollSmoothing
                                                   minimum:0.12
                                                   maximum:0.65
                                                     value:settings.scrollSmoothing
                                                         y:206.0];
    self.scrollActivationSlider = [self addSliderRowToView:content
                                                     title:@"Activation delay"
                                                        tag:kSettingScrollActivation
                                                      minimum:0.10
                                                      maximum:0.50
                                                        value:settings.scrollActivationDelay
                                                          y:170.0];
    self.scrollDeadzoneSlider = [self addSliderRowToView:content
                                                  title:@"Noise filter"
                                                     tag:kSettingScrollDeadzone
                                                 minimum:0.004
                                                 maximum:0.05
                                                   value:settings.scrollDeadzone
                                                       y:134.0];

    self.invertScrollButton = [NSButton checkboxWithTitle:@"Reverse scroll direction"
                                                    target:self
                                                    action:@selector(settingsChanged:)];
    self.invertScrollButton.frame = NSMakeRect(24.0, 102.0, 250.0, 24.0);
    [content addSubview:self.invertScrollButton];

    self.scrollClutchButton = [NSButton checkboxWithTitle:@"Use pinch as scroll clutch"
                                                    target:self
                                                    action:@selector(settingsChanged:)];
    self.scrollClutchButton.frame = NSMakeRect(24.0, 76.0, 250.0, 24.0);
    [content addSubview:self.scrollClutchButton];

    NSButton *reset = [NSButton buttonWithTitle:@"Restore Defaults"
                                          target:self
                                          action:@selector(resetSettings:)];
    reset.frame = NSMakeRect(24.0, 32.0, 150.0, 32.0);
    [content addSubview:reset];

    NSTextField *help = [NSTextField labelWithString:
        @"Pinch and release to click. Hold and move deliberately to drag."];
    help.frame = NSMakeRect(190.0, 36.0, 300.0, 24.0);
    help.textColor = [NSColor secondaryLabelColor];
    [content addSubview:help];
    [self refreshSettingsControls];
}

- (void)refreshSettingsControls {
    if (!self.settingsWindow) return;
    GestureSettings settings = CurrentGestureSettings();
    self.cursorGainSlider.doubleValue = settings.cursorGain;
    self.cursorSmoothingSlider.doubleValue = settings.cursorSmoothing;
    self.cursorDeadzoneSlider.doubleValue = settings.cursorDeadzone;
    self.cursorMaxStepSlider.doubleValue = settings.cursorMaxStep;
    self.pinchSensitivitySlider.doubleValue = settings.pinchEnterRatio;
    self.pinchStabilizationSlider.doubleValue = settings.pinchActivationDelay;
    self.dragHoldSlider.doubleValue = settings.dragHoldDuration;
    self.dragMovementSlider.doubleValue = settings.dragMovementThreshold;
    self.scrollSpeedSlider.doubleValue = settings.scrollSpeed;
    self.scrollAccelerationSlider.doubleValue = settings.scrollAcceleration;
    self.scrollSmoothingSlider.doubleValue = settings.scrollSmoothing;
    self.scrollActivationSlider.doubleValue = settings.scrollActivationDelay;
    self.scrollDeadzoneSlider.doubleValue = settings.scrollDeadzone;
    self.invertScrollButton.state = settings.invertScroll
        ? NSControlStateValueOn : NSControlStateValueOff;
    self.scrollClutchButton.state = settings.scrollClutchEnabled
        ? NSControlStateValueOn : NSControlStateValueOff;
    [self refreshSettingValueLabels];
}

- (void)settingsChanged:(id)sender {
    GestureSettings settings = CurrentGestureSettings();
    NSInteger tag = [sender tag];
    switch (tag) {
        case kSettingCursorGain:
            settings.cursorGain = self.cursorGainSlider.doubleValue;
            break;
        case kSettingCursorSmoothing:
            settings.cursorSmoothing = self.cursorSmoothingSlider.doubleValue;
            break;
        case kSettingCursorDeadzone:
            settings.cursorDeadzone = self.cursorDeadzoneSlider.doubleValue;
            break;
        case kSettingCursorMaxStep:
            settings.cursorMaxStep = self.cursorMaxStepSlider.doubleValue;
            break;
        case kSettingPinchSensitivity:
            settings.pinchEnterRatio = self.pinchSensitivitySlider.doubleValue;
            settings.pinchExitRatio = settings.pinchEnterRatio + 0.14;
            break;
        case kSettingPinchStabilization:
            settings.pinchActivationDelay = self.pinchStabilizationSlider.doubleValue;
            break;
        case kSettingDragHold:
            settings.dragHoldDuration = self.dragHoldSlider.doubleValue;
            break;
        case kSettingDragMovement:
            settings.dragMovementThreshold = self.dragMovementSlider.doubleValue;
            break;
        case kSettingScrollSpeed:
            settings.scrollSpeed = self.scrollSpeedSlider.doubleValue;
            break;
        case kSettingScrollAcceleration:
            settings.scrollAcceleration = self.scrollAccelerationSlider.doubleValue;
            break;
        case kSettingScrollSmoothing:
            settings.scrollSmoothing = self.scrollSmoothingSlider.doubleValue;
            break;
        case kSettingScrollActivation:
            settings.scrollActivationDelay = self.scrollActivationSlider.doubleValue;
            break;
        case kSettingScrollDeadzone:
            settings.scrollDeadzone = self.scrollDeadzoneSlider.doubleValue;
            break;
        default:
            if (sender == self.invertScrollButton) {
                settings.invertScroll = self.invertScrollButton.state == NSControlStateValueOn;
            } else if (sender == self.scrollClutchButton) {
                settings.scrollClutchEnabled = self.scrollClutchButton.state == NSControlStateValueOn;
            } else {
                return;
            }
            break;
    }
    SaveGestureSettings(settings);
    [self refreshSettingsControls];
    [self refreshQuickSettingsState];
}

- (void)openSettings:(id)sender {
    if (!self.settingsWindow) [self buildSettingsWindow];
    [self refreshSettingsControls];
    [NSApp activateIgnoringOtherApps:YES];
    [self.settingsWindow makeKeyAndOrderFront:nil];
}

- (void)resetSettings:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Restore default Mighty Mouse settings?";
    alert.informativeText = @"Your current gesture preferences will be replaced with the recommended defaults.";
    [alert addButtonWithTitle:@"Restore Defaults"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    ResetGestureSettings();
    [self refreshSettingsControls];
    [self refreshQuickSettingsState];
}

- (void)toggleTracking:(id)sender {
    SetGestureTrackingEnabled(!GestureTrackingIsEnabled());
    [self refreshStatus];
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
        std::cout << "Accessibility trust: "
                  << (AccessibilityPermissionGranted() ? "allowed" : "needed")
                  << std::endl;
        LoadGestureSettings();
        if (!AccessibilityPermissionGranted()) {
            std::cout << "Requesting Accessibility permission..." << std::endl;
            NSDictionary *options = @{
                (__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES
            };
            AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
        }
        StartGestureEngine();
        [app run];

        StopGestureEngine();
    }

    return 0;
}
