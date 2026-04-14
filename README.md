Mighty Mouse 🖱️🕶️
Mighty Mouse is a lightweight spatial utility for macOS that enables Apple Vision-powered hand tracking for the VITURE Pro/One glasses. It allows you to control the macOS cursor using natural hand gestures (point and pinch) directly on top of the SpaceWalker app.

By utilizing a relative displacement strategy, this tool allows you to anchor your hand interactions to the virtual world while SpaceWalker handles the head-tracking, providing a seamless "spatial" interaction experience.

✨ Features
Hand Tracking via Apple Vision: Uses the built-in cameras on the VITURE glasses to track hand poses with high precision.

SpaceWalker Compatible: Designed to run concurrently with the official SpaceWalker app without IMU resource conflicts.

Pinch-to-Click: Natural "pinch" gesture (Index + Thumb) triggers system-level mouse down/up events.

High Performance: Written in Objective-C++ with ARC and optimized for Apple Silicon (M1/M2/M3).

Silent Background Operation: Suppresses framework warnings to keep your console clean.

🛠️ Prerequisites
Hardware: VITURE Pro or VITURE One AR Glasses.

OS: macOS (Apple Silicon arm64 required).

Permissions: * Camera: The app will request access to use the "USB Camera" (the glasses).

Accessibility: You must grant the app (or your Terminal) Accessibility and Input Monitoring permissions in System Settings > Privacy & Security to allow it to move the cursor.

📁 Repository Structure
Plaintext
.
├── main.mm               # App entry point and lifecycle
├── GestureEngine.mm      # Vision-based tracking & event logic
├── include/              # VITURE SDK Headers
├── aarch64/              # Compiled VITURE libraries (.dylib)
└── Makefile              # Build & Run script
🚀 Getting Started
1. Installation

Clone the repository and ensure your VITURE libraries are placed in the ./aarch64 directory.

2. Building and Running

The included Makefile handles the compilation, linking of frameworks, and execution.

Bash
make
3. Usage

Plug in your VITURE glasses.

Open the SpaceWalker app.

Run the make command.

Raise your hand into the field of view of the glasses.

Point to move the cursor; Pinch to click and drag.

🏗️ Build Configuration
The binary is compiled using clang++ with the following flags:

Frameworks: AVFoundation, Vision, CoreGraphics, AppKit.

Libraries: Links against libcarina_vio.dylib and libglasses.dylib.

Runtime: Suppresses system activity logs (2>/dev/null) for a clean output.

⚠️ Known Issues / Notes
Console Warnings: You may see "Continuity Camera" deprecation warnings on some macOS versions; these are safely ignored by the build script's output redirection.

IMU Access: This version purposefully avoids direct IMU access to prevent conflicts with SpaceWalker's driver.

Disclaimer: This is an experimental tool and is not affiliated with VITURE. Use at your own risk.