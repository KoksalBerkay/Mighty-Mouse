# Mighty Mouse 🖱️🕶️

**Mighty Mouse** is a macOS menu-bar utility that uses Apple Vision hand tracking to control the cursor with VITURE glasses cameras. It supports the VITURE Luma Ultra tracking-camera SDK when available and falls back to the glasses' external USB camera when SpaceWalker owns the tracking interface.

By utilizing a relative displacement strategy, this tool anchors your hand interactions to the virtual world while SpaceWalker handles the head-tracking, providing a seamless "spatial" interaction experience without hardware resource conflicts.

## Maintained fork

This repository is a maintained fork of [fankahou/Mighty-Mouse](https://github.com/fankahou/Mighty-Mouse). It keeps the original project and attribution while adding a more complete menu-bar application experience and ongoing gesture usability improvements.

Notable additions in this fork include:

- Persistent menu-bar controls for cursor, pinch, drag, and scroll behavior.
- A stable menu-bar launcher, pause control, privacy-settings shortcut, and quit action.
- Improved pinch-to-click and drag interaction with release-based clicking and cursor anchoring.
- Angle-tolerant two-finger scrolling with scroll clutching, smoothing, acceleration, and direction controls.
- Continuous index/middle-finger pose scoring with hysteresis so Vision jitter is less likely to cancel scrolling or stall ordinary pointing.
- Deterministic tests for gesture geometry, cursor motion, scroll interpretation, and pose classification.

The maintained fork is published at `https://github.com/KoksalBerkay/Mighty-Mouse`.

---

## ✨ Features

- **Apple Vision Integration:** Leverages the native Vision framework for robust hand pose detection.
- **SpaceWalker Awareness:** The menu bar status reports when SpaceWalker is preventing access to the Luma Ultra tracking camera.
- **Natural Interaction:**
  - **Point:** Move the system cursor by moving your hand.
  - **Pinch:** A short, stabilized index-to-thumb pinch clicks without moving the cursor.
  - **Drag:** Hold the pinch and intentionally move after the hold threshold.
  - **Scroll:** Extend the index and middle fingers while curling the ring and little fingers, then move vertically.
- **Safe Control:** Pause or resume gesture output from the menu bar without quitting the app.
- **Comfort Controls:** Adjust cursor response, pinch stabilization, drag thresholds, and scroll behavior from the menu bar.
- **Persistent Preferences:** Settings are saved automatically and can be restored to recommended defaults at any time.
- **Silicon Optimized:** Native `arm64` support for M1, M2, and M3 Macs.
- **Clean Console:** Automatically suppresses framework-level warnings for a focused developer experience.

---

## 🛠️ Prerequisites

### Hardware
- **VITURE Luma Ultra** glasses for the dedicated stereo tracking-camera path.
- **Apple Silicon Mac** (M1 or newer).

### Permissions
To function, macOS requires you to grant the following permissions in **System Settings > Privacy & Security**:
1. **Camera:** To access the glasses' sensor feed.
2. **Accessibility:** To allow the app to post mouse events and control the cursor.
3. **Input Monitoring:** To track gestures while the app is in the background.

---

## 🎮 Gesture Guide

- **Move:** Hold up only your index finger and move it naturally.
- **Click:** Bring thumb and index together, wait for the pinch to arm, then release. Mighty Mouse sends the click at the frozen cursor position, so the release does not need to be precisely timed.
- **Drag:** Keep the pinch held beyond the drag hold duration and move deliberately past the movement threshold. Release the pinch to stop dragging.
- **Scroll:** Hold index and middle fingers up with ring and little fingers curled; wait for the short activation dwell, then move the two-finger pair vertically. The pose accepts rotated or diagonal hands. Finger geometry is scored continuously, so small Vision jitters no longer immediately cancel scrolling or send cursor movement instead.
- **Scroll reposition:** While scrolling, pinch to engage the clutch. Move your hand to a new position without generating reverse scrolling, then return to the two-finger pose to establish a fresh baseline.
- **Pause:** Choose **Pause Tracking** from the hand-icon menu when you need normal mouse control.

## ⚙️ Comfort Settings

Open the hand-icon menu in the macOS menu bar. **Quick Settings** provides one-click presets for cursor sensitivity, cursor response, scroll speed, and scroll direction. Choose **Open Settings…** for fine control over:

- Cursor sensitivity and response smoothing.
- Cursor movement deadzone and maximum movement step.
- Pinch sensitivity and stabilization delay.
- Drag hold duration and movement threshold.
- Scroll speed, acceleration, smoothing, activation delay, and noise filter.
- Scroll clutch enable/disable.
- Two-finger pose sensitivity: Easy accepts more borderline finger shapes; Strict requires a clearer index-and-middle pose. Balanced is recommended.
- Natural or reversed scroll direction.

Every change applies immediately and is saved automatically for the next launch. Choose **Restore Default Settings** from either the menu or the settings window to return to the recommended defaults.

For development, `make test` runs deterministic scroll-state and rotated-finger geometry tests before packaging the app.

## 🚀 Installation & Build

### 1. Clone the Repository
```bash
git clone https://github.com/KoksalBerkay/Mighty-Mouse.git
cd Mighty-Mouse
```

### 2. Add SDK Libraries

Ensure your VITURE SDK binaries are located in the following structure:

- `./aarch64/libcarina_vio.dylib`

- `./aarch64/libglasses.dylib`

### 3. Build and Run

Use the provided `Makefile` to compile the application:

```bash
make
```

Use `make run` when launching from the repository during development.
---

### Part 3: Structure and License

---

## 📂 Project Structure

- `main.mm`: App lifecycle and environment setup.
- `GestureEngine.mm`: Core hand tracking logic, coordinate mapping, and mouse event injection.
- `include/`: SDK headers for VITURE hardware.
- `aarch64/`: ARM64 dynamic libraries.
- `Makefile`: Optimized build instructions for Apple Clang.

---

## ⚖️ License

Distributed under the **MIT License**. See `LICENSE` for more information.

---

## ⚠️ Disclaimer
This is an independent community project and is not an official VITURE product. Use at your own risk. Always ensure you are in a safe environment when using AR hand-tracking.
