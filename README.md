# Mighty Mouse 🖱️🕶️

**Mighty Mouse** is a high-performance spatial utility for macOS that enables Apple Vision-powered hand tracking for **VITURE Pro/One** glasses. It allows you to control the macOS cursor using natural hand gestures (point and pinch) directly on top of the **SpaceWalker** app.

By utilizing a relative displacement strategy, this tool anchors your hand interactions to the virtual world while SpaceWalker handles the head-tracking, providing a seamless "spatial" interaction experience without hardware resource conflicts.

---

## ✨ Features

- **Apple Vision Integration:** Leverages the native Vision framework for robust hand pose detection.
- **SpaceWalker Compatibility:** Designed to run alongside the official SpaceWalker app by avoiding IMU (HID) locks.
- **Natural Interaction:** - **Point:** Move the system cursor by moving your hand.
  - **Pinch:** Index-to-thumb pinch triggers a Left Mouse Click (supports dragging).
- **Silicon Optimized:** Native `arm64` support for M1, M2, and M3 Macs.
- **Clean Console:** Automatically suppresses framework-level warnings for a focused developer experience.

---

## 🛠️ Prerequisites

### Hardware
- **VITURE Pro** or **VITURE One** AR Glasses.
- **Apple Silicon Mac** (M1 or newer).

### Permissions
To function, macOS requires you to grant the following permissions in **System Settings > Privacy & Security**:
1. **Camera:** To access the glasses' sensor feed.
2. **Accessibility:** To allow the app to post mouse events and control the cursor.
3. **Input Monitoring:** To track gestures while the app is in the background.

---

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

Use the provided `Makefile` to compile and launch the application:

```bash
make
```
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