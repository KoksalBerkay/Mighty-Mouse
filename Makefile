
APP_BUNDLE := Mighty Mouse.app
APP_ID := com.fankahou.mightymouse
SIGNING_REQUIREMENT := /private/tmp/mighty_mouse.csreq

.PHONY: all build run test sign-app

all: build

build:
	clang++ main.mm GestureEngine.mm Preferences.mm GestureInterpreter.cpp GestureGeometry.cpp -o mighty_mouse \
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
	clang++ GestureInterpreter.cpp GestureInterpreterTests.cpp GestureGeometry.cpp GestureGeometryTests.cpp -o work/gesture_interpreter_tests -arch arm64
	./work/gesture_interpreter_tests

# Sign the local bundle with a stable identifier requirement. Ad-hoc signing
# without this override uses the executable cdhash, which makes macOS privacy
# permissions appear to disappear after every rebuild.
sign-app: build
	cp mighty_mouse '$(APP_BUNDLE)/Contents/MacOS/mighty_mouse'
	install_name_tool -delete_rpath ./aarch64 -add_rpath '@executable_path/../Frameworks' '$(APP_BUNDLE)/Contents/MacOS/mighty_mouse'
	csreq -r '=designated => identifier "$(APP_ID)"' -b '$(SIGNING_REQUIREMENT)'
	codesign --force --sign - '$(APP_BUNDLE)/Contents/Frameworks/libcarina_vio.dylib'
	codesign --force --sign - '$(APP_BUNDLE)/Contents/Frameworks/libglasses.dylib'
	codesign --force --sign - --requirements '$(SIGNING_REQUIREMENT)' '$(APP_BUNDLE)/Contents/MacOS/mighty_mouse'
	codesign --force --sign - --requirements '$(SIGNING_REQUIREMENT)' '$(APP_BUNDLE)'
