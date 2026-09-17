
APP_BUNDLE := Mighty Mouse.app
APP_ID := com.koksalberkay.mightymouse
SIGNING_REQUIREMENT := /private/tmp/mighty_mouse.csreq

.PHONY: all build run test prepare-app sign-app

all: build

build:
	clang++ main.mm GestureEngine.mm Preferences.mm GestureInterpreter.cpp GestureGeometry.cpp CursorMotion.cpp -o mighty_mouse \
	-fobjc-arc \
    -I./include \
    ./aarch64/libcarina_vio.dylib \
    ./aarch64/libglasses.dylib \
    -Wl,-rpath,./aarch64 \
    -framework AVFoundation \
    -framework Vision \
    -framework CoreGraphics \
    -framework Foundation \
    -framework CoreMedia \
    -framework CoreVideo \
    -framework CoreFoundation \
    -framework ApplicationServices \
    -framework IOKit \
    -framework AppKit \
    -arch arm64

run: build
	DYLD_LIBRARY_PATH=./aarch64 ./mighty_mouse 2>/dev/null

test:
	mkdir -p work
	clang++ GestureInterpreter.cpp GestureInterpreterTests.cpp GestureGeometry.cpp GestureGeometryTests.cpp CursorMotion.cpp CursorMotionTests.cpp -o work/gesture_interpreter_tests -arch arm64
	./work/gesture_interpreter_tests

# Create the menu-bar app structure from the tracked bundle metadata. The
# generated bundle is ignored so local builds never add app binaries to git.
prepare-app:
	mkdir -p '$(APP_BUNDLE)/Contents/MacOS' '$(APP_BUNDLE)/Contents/Frameworks'
	cp Info.plist '$(APP_BUNDLE)/Contents/Info.plist'
	cp ./aarch64/libcarina_vio.dylib '$(APP_BUNDLE)/Contents/Frameworks/libcarina_vio.dylib'
	cp ./aarch64/libglasses.dylib '$(APP_BUNDLE)/Contents/Frameworks/libglasses.dylib'

# Build and sign a launchable local menu-bar app. This is ad-hoc signed for
# local use; public distribution should use a Developer ID certificate and
# notarization.
sign-app: build prepare-app
	cp mighty_mouse '$(APP_BUNDLE)/Contents/MacOS/mighty_mouse'
	install_name_tool -delete_rpath ./aarch64 -add_rpath '@executable_path/../Frameworks' '$(APP_BUNDLE)/Contents/MacOS/mighty_mouse'
	csreq -r '=designated => identifier "$(APP_ID)"' -b '$(SIGNING_REQUIREMENT)'
	codesign --force --sign - '$(APP_BUNDLE)/Contents/Frameworks/libcarina_vio.dylib'
	codesign --force --sign - '$(APP_BUNDLE)/Contents/Frameworks/libglasses.dylib'
	codesign --force --sign - --requirements '$(SIGNING_REQUIREMENT)' '$(APP_BUNDLE)/Contents/MacOS/mighty_mouse'
	codesign --force --sign - --requirements '$(SIGNING_REQUIREMENT)' '$(APP_BUNDLE)'
