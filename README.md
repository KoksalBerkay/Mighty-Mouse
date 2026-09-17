# Mighty Mouse 🖱️🕶️

Mighty Mouse is a macOS menu-bar utility that turns hand movements captured by
VITURE glasses into cursor, click, drag, and scroll input. It uses Apple Vision
for hand-pose detection and can run beside SpaceWalker without trying to take
over its head-tracking controls.

This repository is a maintained fork of
[fankahou/Mighty-Mouse](https://github.com/fankahou/Mighty-Mouse). The fork
keeps the original attribution and adds a fuller menu-bar application,
persistent settings, more stable gesture handling, and a safer optional SDK
setup flow.

## ✨ What it does

- **Point:** Raise only your index finger and move your hand to move the
  cursor.
- **Click:** Pinch your thumb and index finger together, then release. The app
  clicks at the cursor position captured when the pinch began.
- **Drag:** Hold the pinch past the drag threshold and move your hand. Release
  the pinch to finish dragging.
- **Scroll:** Raise your index and middle fingers, curl the other fingers, and
  move the pair vertically. Rotated and diagonal hand poses are supported.
- **Scroll reposition:** Pinch while scrolling to pause output while you move
  your hand to a new position. Return to the two-finger pose to set a new
  baseline.
- **Pause:** Pause gesture output from the menu bar whenever you need normal
  mouse control.

## 🧭 How it works

1. Mighty Mouse asks macOS for camera frames and uses Apple Vision to locate
   hand landmarks.
2. The gesture interpreter classifies pointing, pinching, dragging, and
   two-finger scrolling with stabilization and hysteresis to reduce accidental
   state changes caused by camera jitter.
3. Relative hand movement becomes CoreGraphics mouse and scroll events. The
   relative mapping lets SpaceWalker continue handling the spatial display and
   head tracking.
4. When the optional VITURE SDK is installed, Mighty Mouse first tries the
   Luma Ultra tracking-camera path. If SpaceWalker owns that interface or the
   SDK is unavailable, it falls back to the glasses' external USB camera.

## 📌 Current status

- macOS on Apple Silicon (`arm64`).
- Designed for VITURE glasses and the SpaceWalker workflow.
- Builds locally from source with Apple Clang.
- The repository does not contain a prebuilt app or VITURE SDK files.
- Public releases contain source only. A signed and notarized downloadable app
  is still future work.

## 🧰 Requirements

### 🕶️ Hardware

- Apple Silicon Mac (M1 or newer).
- VITURE glasses with an available camera feed.
- The optional VITURE SDK if you want to use the dedicated Luma Ultra
  tracking-camera path.

### 🔐 macOS permissions

Grant these permissions in **System Settings > Privacy & Security**:

1. **Camera**, so Mighty Mouse can read the glasses' camera feed.
2. **Accessibility**, so it can post mouse events and control the cursor.
3. **Input Monitoring**, so gesture tracking can continue while the app is in
   the background.

## 🚀 Install and run

### 1. 📥 Clone the repository

```bash
git clone https://github.com/KoksalBerkay/Mighty-Mouse.git
cd Mighty-Mouse
```

### 2. ✅ Run the tests

The test target covers gesture geometry, cursor motion, scroll interpretation,
pose classification, and the default Quick Settings values.

```bash
make test
```

### 3. 🛠️ Build the menu-bar app

```bash
make sign-app
open "Mighty Mouse.app"
```

`make sign-app` creates an ignored app bundle in the repository, copies in the
native executable, and ad-hoc signs it for local use. On first launch, grant
the required macOS permissions to this app identity.

For development, `make build` creates the executable and `make run` launches
it directly without creating an app bundle.

### 4. 📦 Optional: set up the VITURE SDK

Mighty Mouse does not host, redistribute, or link against the VITURE SDK at
build time. Download the SDK directly from VITURE, then open the menu-bar hand
icon and choose **SDK not installed — Set Up SDK…**. Select the downloaded
`.zip`, `.tar.gz`, or `.tgz` archive. An extracted SDK folder is also accepted.

The setup utility validates the archive and copies only the required arm64
libraries into this app-owned directory:

```text
~/Library/Application Support/Mighty Mouse/VITURE SDK/
```

The original SDK archive or folder is never modified or deleted. If the SDK is
not installed, the app continues to offer the external USB-camera fallback.
The same menu provides an uninstaller that removes only Mighty Mouse's exact
app-owned SDK directory and, optionally, Mighty Mouse's own preferences.

The SDK is obtained and used under VITURE's terms. Read the
[VITURE SDK License Agreement](https://www.viture.com/viture-sdk-license-agreement)
before installing it.

### 5. 📁 Install outside the repository (optional)

For a local app installation under your user account:

```bash
mkdir -p "$HOME/Applications"
ditto "Mighty Mouse.app" "$HOME/Applications/Mighty Mouse.app"
open -a "$HOME/Applications/Mighty Mouse.app"
```

Ad-hoc signing is intended for local development. A public downloadable app
will need an Apple Developer ID signature and notarization.

## 🖐️ Menu-bar controls

The hand icon provides:

- Camera and cursor-permission status.
- SDK setup, validation, and uninstall.
- Pause and resume tracking.
- Quick Settings for common adjustments.
- Fine-grained settings for cursor, pinch, drag, and scroll behavior.
- Shortcuts to the relevant macOS privacy settings.

New installations and **Restore Default Settings** use these Quick Settings
defaults:

| Menu choice | Default |
| --- | --- |
| Cursor Response | Responsive |
| Scroll Speed | Very Fast |
| Two-Finger Pose | Strict |

Settings apply immediately and are saved for the next launch. Existing custom
preferences are preserved until you change them or choose **Restore Default
Settings**.

## 🗂️ Project structure

- `main.mm`: App lifecycle, menu-bar controls, settings window, and SDK setup
  actions.
- `GestureEngine.mm`: Camera selection, Vision frame processing, coordinate
  mapping, and mouse-event injection.
- `GestureInterpreter.cpp`: Gesture state transitions and stabilization.
- `GestureGeometry.cpp`: Finger-pose geometry and scoring.
- `CursorMotion.cpp`: Relative cursor movement and filtering.
- `VitureSDKManager.mm`: SDK validation, local installation, uninstallation,
  and runtime loading.
- `Preferences.mm`: Persistent gesture settings and default values.
- `Makefile`: Test, build, app-bundle, and local-signing commands.

The VITURE SDK headers and dynamic libraries are intentionally absent from the
repository and app bundle. The app declares only the small runtime ABI it uses
and resolves the SDK symbols after installation.

## 📄 License

Mighty Mouse's source code is distributed under the [MIT License](LICENSE).
The VITURE SDK is separate third-party software and is not covered by this
repository's license.

Mighty Mouse is an independent community project and is not an official VITURE
product. Use it at your own risk, and make sure you can safely see and control
your environment while using hand-tracking input.
