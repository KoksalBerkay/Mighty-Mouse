#import <Foundation/Foundation.h>

#include <algorithm>
#include <mutex>

#include "Preferences.h"

static NSString *const kSettingsDomain = @"com.fankahou.mightymouse";
static NSString *const kCursorGainKey = @"CursorGain";
static NSString *const kCursorSmoothingKey = @"CursorSmoothing";
static NSString *const kPinchEnterRatioKey = @"PinchEnterRatio";
static NSString *const kPinchExitRatioKey = @"PinchExitRatio";
static NSString *const kPinchActivationDelayKey = @"PinchActivationDelay";
static NSString *const kDragHoldDurationKey = @"DragHoldDuration";
static NSString *const kDragMovementThresholdKey = @"DragMovementThreshold";
static NSString *const kScrollSpeedKey = @"ScrollSpeed";
static NSString *const kScrollSmoothingKey = @"ScrollSmoothing";
static NSString *const kScrollActivationDelayKey = @"ScrollActivationDelay";
static NSString *const kScrollDeadzoneKey = @"ScrollDeadzone";
static NSString *const kInvertScrollKey = @"InvertScroll";

static std::mutex g_settingsMutex;
static GestureSettings g_settings = {};
static bool g_settingsLoaded = false;

GestureSettings DefaultGestureSettings() {
    return GestureSettings{
        .cursorGain = 1.60,
        .cursorSmoothing = 0.26,
        .pinchEnterRatio = 0.28,
        .pinchExitRatio = 0.42,
        .pinchActivationDelay = 0.10,
        .dragHoldDuration = 0.35,
        .dragMovementThreshold = 0.045,
        .scrollSpeed = 1.00,
        .scrollSmoothing = 0.32,
        .scrollActivationDelay = 0.22,
        .scrollDeadzone = 0.012,
        .invertScroll = false,
    };
}

static double Clamped(double value, double minimum, double maximum) {
    return std::max(minimum, std::min(maximum, value));
}

static GestureSettings NormalizeSettings(GestureSettings settings) {
    settings.cursorGain = Clamped(settings.cursorGain, 1.0, 2.6);
    settings.cursorSmoothing = Clamped(settings.cursorSmoothing, 0.12, 0.55);

    settings.pinchEnterRatio = Clamped(settings.pinchEnterRatio, 0.18, 0.40);
    settings.pinchExitRatio = Clamped(settings.pinchExitRatio,
                                      settings.pinchEnterRatio + 0.08,
                                      0.60);
    settings.pinchActivationDelay = Clamped(settings.pinchActivationDelay, 0.04, 0.25);
    settings.dragHoldDuration = Clamped(settings.dragHoldDuration, 0.20, 0.90);
    settings.dragMovementThreshold = Clamped(settings.dragMovementThreshold, 0.018, 0.12);

    settings.scrollSpeed = Clamped(settings.scrollSpeed, 0.25, 3.0);
    settings.scrollSmoothing = Clamped(settings.scrollSmoothing, 0.12, 0.65);
    settings.scrollActivationDelay = Clamped(settings.scrollActivationDelay, 0.10, 0.50);
    settings.scrollDeadzone = Clamped(settings.scrollDeadzone, 0.004, 0.05);
    return settings;
}

static void RegisterDefaults(NSUserDefaults *defaults) {
    GestureSettings settings = DefaultGestureSettings();
    [defaults registerDefaults:@{
        kCursorGainKey: @(settings.cursorGain),
        kCursorSmoothingKey: @(settings.cursorSmoothing),
        kPinchEnterRatioKey: @(settings.pinchEnterRatio),
        kPinchExitRatioKey: @(settings.pinchExitRatio),
        kPinchActivationDelayKey: @(settings.pinchActivationDelay),
        kDragHoldDurationKey: @(settings.dragHoldDuration),
        kDragMovementThresholdKey: @(settings.dragMovementThreshold),
        kScrollSpeedKey: @(settings.scrollSpeed),
        kScrollSmoothingKey: @(settings.scrollSmoothing),
        kScrollActivationDelayKey: @(settings.scrollActivationDelay),
        kScrollDeadzoneKey: @(settings.scrollDeadzone),
        kInvertScrollKey: @(settings.invertScroll),
    }];
}

static GestureSettings ReadSettings(NSUserDefaults *defaults) {
    GestureSettings settings{
        .cursorGain = [defaults doubleForKey:kCursorGainKey],
        .cursorSmoothing = [defaults doubleForKey:kCursorSmoothingKey],
        .pinchEnterRatio = [defaults doubleForKey:kPinchEnterRatioKey],
        .pinchExitRatio = [defaults doubleForKey:kPinchExitRatioKey],
        .pinchActivationDelay = [defaults doubleForKey:kPinchActivationDelayKey],
        .dragHoldDuration = [defaults doubleForKey:kDragHoldDurationKey],
        .dragMovementThreshold = [defaults doubleForKey:kDragMovementThresholdKey],
        .scrollSpeed = [defaults doubleForKey:kScrollSpeedKey],
        .scrollSmoothing = [defaults doubleForKey:kScrollSmoothingKey],
        .scrollActivationDelay = [defaults doubleForKey:kScrollActivationDelayKey],
        .scrollDeadzone = [defaults doubleForKey:kScrollDeadzoneKey],
        .invertScroll = [defaults boolForKey:kInvertScrollKey],
    };
    return NormalizeSettings(settings);
}

static void WriteSettings(NSUserDefaults *defaults, GestureSettings settings) {
    settings = NormalizeSettings(settings);
    [defaults setDouble:settings.cursorGain forKey:kCursorGainKey];
    [defaults setDouble:settings.cursorSmoothing forKey:kCursorSmoothingKey];
    [defaults setDouble:settings.pinchEnterRatio forKey:kPinchEnterRatioKey];
    [defaults setDouble:settings.pinchExitRatio forKey:kPinchExitRatioKey];
    [defaults setDouble:settings.pinchActivationDelay forKey:kPinchActivationDelayKey];
    [defaults setDouble:settings.dragHoldDuration forKey:kDragHoldDurationKey];
    [defaults setDouble:settings.dragMovementThreshold forKey:kDragMovementThresholdKey];
    [defaults setDouble:settings.scrollSpeed forKey:kScrollSpeedKey];
    [defaults setDouble:settings.scrollSmoothing forKey:kScrollSmoothingKey];
    [defaults setDouble:settings.scrollActivationDelay forKey:kScrollActivationDelayKey];
    [defaults setDouble:settings.scrollDeadzone forKey:kScrollDeadzoneKey];
    [defaults setBool:settings.invertScroll forKey:kInvertScrollKey];
}

void LoadGestureSettings() {
    @autoreleasepool {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        RegisterDefaults(defaults);
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
    }
}

void ResetGestureSettings() {
    SaveGestureSettings(DefaultGestureSettings());
}
