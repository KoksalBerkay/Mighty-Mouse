#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Starts the AVFoundation camera feed and Apple Vision hand tracking
void StartGestureEngine();

// Stops the camera and cleans up memory
void StopGestureEngine();

// Returns a short, human-readable status for the menu bar item.
const char *GestureEngineStatus();

// Enables or pauses cursor/scroll gesture output without stopping the app.
void SetGestureTrackingEnabled(bool enabled);
bool GestureTrackingIsEnabled();

#ifdef __cplusplus
}
#endif
