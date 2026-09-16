# Mighty Mouse 🖱️🕶️

**Mighty Mouse** is a macOS menu-bar utility that uses Apple Vision hand tracking to control the cursor with VITURE glasses cameras. It supports the VITURE Luma Ultra tracking-camera SDK when available and falls back to the glasses' external USB camera when SpaceWalker owns the tracking interface.

By utilizing a relative displacement strategy, this tool anchors your hand interactions to the virtual world while SpaceWalker handles the head-tracking, providing a seamless "spatial" interaction experience without hardware resource conflicts.

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
- **Click:** Bring thumb and index together briefly. The pointer is latched during the pinch so small index movement is ignored.
- **Drag:** Keep the pinch held beyond the click hold and move deliberately.
- **Scroll:** Hold index and middle fingers up with ring and little fingers curled; move the two-finger pair vertically. A short dwell prevents accidental scrolling.
- **Pause:** Choose **Pause Tracking** from the hand-icon menu when you need normal mouse control.

## 🚀 Installation & Build

### 1. Clone the Repository
```bash
git clone [https://github.com/yourusername/mighty-mouse.git](https://github.com/yourusername/mighty-mouse.git)
cd mighty-mouse
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
