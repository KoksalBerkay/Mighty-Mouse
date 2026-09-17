#import <Foundation/Foundation.h>

#include <algorithm>
#include <cmath>
#include <mutex>

#include "Preferences.h"

static NSString *const kCursorGainKey = @"CursorGain";
static NSString *const kCursorSmoothingKey = @"CursorSmoothing";
static NSString *const kCursorDeadzoneKey = @"CursorDeadzone";
static NSString *const kCursorMaxStepKey = @"CursorMaxStep";
static NSString *const kPinchEnterRatioKey = @"PinchEnterRatio";
static NSString *const kPinchExitRatioKey = @"PinchExitRatio";
static NSString *const kPinchActivationDelayKey = @"PinchActivationDelay";
static NSString *const kDragHoldDurationKey = @"DragHoldDuration";
static NSString *const kDragMovementThresholdKey = @"DragMovementThreshold";
static NSString *const kScrollSpeedKey = @"ScrollSpeed";
static NSString *const kScrollAccelerationKey = @"ScrollAcceleration";
static NSString *const kScrollSmoothingKey = @"ScrollSmoothing";
static NSString *const kScrollActivationDelayKey = @"ScrollActivationDelay";
static NSString *const kScrollDeadzoneKey = @"ScrollDeadzone";
static NSString *const kInvertScrollKey = @"InvertScroll";
static NSString *const kScrollClutchEnabledKey = @"ScrollClutchEnabled";
static NSString *const kScrollPoseSensitivityKey = @"ScrollPoseSensitivity";

static std::mutex g_settingsMutex;
static GestureSettings g_settings = {};
static bool g_settingsLoaded = false;

GestureSettings DefaultGestureSettings() {
    return GestureSettings{
        .cursorGain = 1.60,
        .cursorSmoothing = 0.38,
        // Zero disables these optional guards. The prior cursor behavior was
        // direct and responsive; users can opt into extra filtering in the
        // settings window when their camera needs it.
        .cursorDeadzone = 0.0,
        .cursorMaxStep = 0.0,
        .pinchEnterRatio = 0.28,
        .pinchExitRatio = 0.42,
        .pinchActivationDelay = 0.10,
        .dragHoldDuration = 0.35,
        .dragMovementThreshold = 0.045,
        .scrollSpeed = 2.20,
        .scrollAcceleration = 0.15,
        .scrollSmoothing = 0.32,
        .scrollActivationDelay = 0.22,
        .scrollDeadzone = 0.012,
        .invertScroll = false,
        .scrollClutchEnabled = true,
        .scrollPoseSensitivity = 1.00,
    };
}

static double Clamped(double value, double minimum, double maximum) {
    return std::max(minimum, std::min(maximum, value));
}

static GestureSettings NormalizeSettings(GestureSettings settings) {
    settings.cursorGain = Clamped(settings.cursorGain, 1.0, 2.6);
    settings.cursorSmoothing = Clamped(settings.cursorSmoothing, 0.12, 0.55);
    settings.cursorDeadzone = Clamped(settings.cursorDeadzone, 0.0, 0.025);
    settings.cursorMaxStep = Clamped(settings.cursorMaxStep, 0.0, 600.0);

    settings.pinchEnterRatio = Clamped(settings.pinchEnterRatio, 0.18, 0.40);
    settings.pinchExitRatio = Clamped(settings.pinchExitRatio,
                                      settings.pinchEnterRatio + 0.08,
                                      0.60);
    settings.pinchActivationDelay = Clamped(settings.pinchActivationDelay, 0.04, 0.25);
    settings.dragHoldDuration = Clamped(settings.dragHoldDuration, 0.20, 0.90);
    settings.dragMovementThreshold = Clamped(settings.dragMovementThreshold, 0.018, 0.12);

    settings.scrollSpeed = Clamped(settings.scrollSpeed, 0.25, 3.0);
    settings.scrollAcceleration = Clamped(settings.scrollAcceleration, 0.0, 1.0);
    settings.scrollSmoothing = Clamped(settings.scrollSmoothing, 0.12, 0.65);
    settings.scrollActivationDelay = Clamped(settings.scrollActivationDelay, 0.10, 0.50);
    settings.scrollDeadzone = Clamped(settings.scrollDeadzone, 0.004, 0.05);
    settings.scrollPoseSensitivity = Clamped(settings.scrollPoseSensitivity, 0.0, 1.0);
    return settings;
}

static void RegisterDefaults(NSUserDefaults *defaults) {
    GestureSettings settings = DefaultGestureSettings();
    [defaults registerDefaults:@{
        kCursorGainKey: @(settings.cursorGain),
        kCursorSmoothingKey: @(settings.cursorSmoothing),
        kCursorDeadzoneKey: @(settings.cursorDeadzone),
        kCursorMaxStepKey: @(settings.cursorMaxStep),
        kPinchEnterRatioKey: @(settings.pinchEnterRatio),
        kPinchExitRatioKey: @(settings.pinchExitRatio),
        kPinchActivationDelayKey: @(settings.pinchActivationDelay),
        kDragHoldDurationKey: @(settings.dragHoldDuration),
        kDragMovementThresholdKey: @(settings.dragMovementThreshold),
        kScrollSpeedKey: @(settings.scrollSpeed),
        kScrollAccelerationKey: @(settings.scrollAcceleration),
        kScrollSmoothingKey: @(settings.scrollSmoothing),
        kScrollActivationDelayKey: @(settings.scrollActivationDelay),
        kScrollDeadzoneKey: @(settings.scrollDeadzone),
        kInvertScrollKey: @(settings.invertScroll),
        kScrollClutchEnabledKey: @(settings.scrollClutchEnabled),
        kScrollPoseSensitivityKey: @(settings.scrollPoseSensitivity),
    }];
}

static GestureSettings ReadSettings(NSUserDefaults *defaults) {
    GestureSettings settings{
        .cursorGain = [defaults doubleForKey:kCursorGainKey],
        .cursorSmoothing = [defaults doubleForKey:kCursorSmoothingKey],
        .cursorDeadzone = [defaults doubleForKey:kCursorDeadzoneKey],
        .cursorMaxStep = [defaults doubleForKey:kCursorMaxStepKey],
        .pinchEnterRatio = [defaults doubleForKey:kPinchEnterRatioKey],
        .pinchExitRatio = [defaults doubleForKey:kPinchExitRatioKey],
        .pinchActivationDelay = [defaults doubleForKey:kPinchActivationDelayKey],
        .dragHoldDuration = [defaults doubleForKey:kDragHoldDurationKey],
        .dragMovementThreshold = [defaults doubleForKey:kDragMovementThresholdKey],
        .scrollSpeed = [defaults doubleForKey:kScrollSpeedKey],
        .scrollAcceleration = [defaults doubleForKey:kScrollAccelerationKey],
        .scrollSmoothing = [defaults doubleForKey:kScrollSmoothingKey],
        .scrollActivationDelay = [defaults doubleForKey:kScrollActivationDelayKey],
        .scrollDeadzone = [defaults doubleForKey:kScrollDeadzoneKey],
        .invertScroll = [defaults boolForKey:kInvertScrollKey],
        .scrollClutchEnabled = [defaults boolForKey:kScrollClutchEnabledKey],
        .scrollPoseSensitivity = [defaults doubleForKey:kScrollPoseSensitivityKey],
    };
    return NormalizeSettings(settings);
}

static void WriteSettings(NSUserDefaults *defaults, GestureSettings settings) {
    settings = NormalizeSettings(settings);
    [defaults setDouble:settings.cursorGain forKey:kCursorGainKey];
    [defaults setDouble:settings.cursorSmoothing forKey:kCursorSmoothingKey];
    [defaults setDouble:settings.cursorDeadzone forKey:kCursorDeadzoneKey];
    [defaults setDouble:settings.cursorMaxStep forKey:kCursorMaxStepKey];
    [defaults setDouble:settings.pinchEnterRatio forKey:kPinchEnterRatioKey];
    [defaults setDouble:settings.pinchExitRatio forKey:kPinchExitRatioKey];
    [defaults setDouble:settings.pinchActivationDelay forKey:kPinchActivationDelayKey];
    [defaults setDouble:settings.dragHoldDuration forKey:kDragHoldDurationKey];
    [defaults setDouble:settings.dragMovementThreshold forKey:kDragMovementThresholdKey];
    [defaults setDouble:settings.scrollSpeed forKey:kScrollSpeedKey];
    [defaults setDouble:settings.scrollAcceleration forKey:kScrollAccelerationKey];
    [defaults setDouble:settings.scrollSmoothing forKey:kScrollSmoothingKey];
    [defaults setDouble:settings.scrollActivationDelay forKey:kScrollActivationDelayKey];
    [defaults setDouble:settings.scrollDeadzone forKey:kScrollDeadzoneKey];
    [defaults setBool:settings.invertScroll forKey:kInvertScrollKey];
    [defaults setBool:settings.scrollClutchEnabled forKey:kScrollClutchEnabledKey];
    [defaults setDouble:settings.scrollPoseSensitivity forKey:kScrollPoseSensitivityKey];
}

static id PersistentObjectForKey(NSUserDefaults *defaults, NSString *key) {
    NSString *domainName = [[NSBundle mainBundle] bundleIdentifier];
    if (!domainName) return nil;
    NSDictionary *persistentDomain = [defaults persistentDomainForName:domainName];
    return persistentDomain[key];
}

void LoadGestureSettings() {
    @autoreleasepool {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        RegisterDefaults(defaults);

        // Versions before the cursor regression registered these as 0.003 and
        // 220. Reset only those old untouched defaults once; preserve any
        // deliberately customized values.
        double savedDeadzone = [PersistentObjectForKey(defaults, kCursorDeadzoneKey) doubleValue];
        double savedMaxStep = [PersistentObjectForKey(defaults, kCursorMaxStepKey) doubleValue];
        if (fabs(savedDeadzone - 0.003) < 0.0001 && fabs(savedMaxStep - 220.0) < 0.1) {
            [defaults setDouble:0.0 forKey:kCursorDeadzoneKey];
            [defaults setDouble:0.0 forKey:kCursorMaxStepKey];
            [defaults synchronize];
        }
        GestureSettings loaded = ReadSettings(defaults);
        std::lock_guard<std::mutex> lock(g_settingsMutex);
        g_settings = loaded;
        g_settingsLoaded = true;
    }
}

GestureSettings CurrentGestureSettings() {
    std::lock_guard<std::mutex> lock(g_settingsMutex);
    if (!g_settingsLoaded) {
        g_settings = DefaultGestureSettings();
        g_settingsLoaded = true;
    }
    return g_settings;
}

void SaveGestureSettings(const GestureSettings &settings) {
    GestureSettings normalized = NormalizeSettings(settings);
    {
        std::lock_guard<std::mutex> lock(g_settingsMutex);
        g_settings = normalized;
        g_settingsLoaded = true;
    }

    @autoreleasepool {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        RegisterDefaults(defaults);
        WriteSettings(defaults, normalized);
        [defaults synchronize];
    }
}

void ResetGestureSettings() {
    SaveGestureSettings(DefaultGestureSettings());
}
