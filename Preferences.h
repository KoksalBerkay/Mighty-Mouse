#pragma once

#include <stdbool.h>

// Values are deliberately expressed in normalized, UI-independent units so
// the gesture engine can consume one immutable snapshot per video frame.
struct GestureSettings {
    double cursorGain;
    double cursorSmoothing;
    double cursorDeadzone;
    double cursorMaxStep;

    double pinchEnterRatio;
    double pinchExitRatio;
    double pinchActivationDelay;
    double dragHoldDuration;
    double dragMovementThreshold;

    double scrollSpeed;
    double scrollAcceleration;
    double scrollSmoothing;
    double scrollActivationDelay;
    double scrollDeadzone;
    bool invertScroll;
    bool scrollClutchEnabled;
    double scrollPoseSensitivity;
};

GestureSettings DefaultGestureSettings();

// Loads the persisted settings and registers defaults. Call once before the
// gesture engine starts. Reads after that are safe from the camera queue.
void LoadGestureSettings();

// Returns a synchronized copy of the current settings.
GestureSettings CurrentGestureSettings();

// Applies settings immediately and persists them for the next launch.
void SaveGestureSettings(const GestureSettings &settings);

// Restores only Mighty Mouse's own preference keys.
void ResetGestureSettings();
