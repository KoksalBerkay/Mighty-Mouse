
.PHONY: all build run

all: build

build:
	clang++ main.mm GestureEngine.mm -o mighty_mouse \
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
    -framework IOKit \
    -framework AppKit \
    -arch arm64

run: build
	DYLD_LIBRARY_PATH=./aarch64 ./mighty_mouse 2>/dev/null
