#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Starts the AVFoundation camera feed and Apple Vision hand tracking
void StartGestureEngine();

// Stops the camera and cleans up memory
void StopGestureEngine();

#ifdef __cplusplus
}
#endif