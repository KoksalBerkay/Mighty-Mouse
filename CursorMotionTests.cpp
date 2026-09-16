#include "CursorMotion.h"

#include <cmath>
#include <cstdlib>
#include <iostream>

static void Expect(bool condition, const char *message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << std::endl;
        std::exit(1);
    }
}

static GestureSettings ResponsiveSettings() {
    GestureSettings settings{};
    settings.cursorSmoothing = 0.38;
    settings.cursorDeadzone = 0.0;
    settings.cursorMaxStep = 0.0;
    return settings;
}

static void TestResponsiveMovementIsNotCappedByDefault() {
    CursorMotion motion;
    GestureSettings settings = ResponsiveSettings();
    motion.Update(CursorPoint{0.0, 0.0}, 1080.0, settings, false);
    CursorMotionResult result = motion.Update(CursorPoint{1000.0, 0.0},
                                               1080.0,
                                               settings,
                                               false);
    Expect(result.moved, "responsive cursor should move on a target change");
    Expect(result.point.x > 220.0,
           "uncapped responsive cursor should not retain the old 220 px limit");
}

static void TestResponsiveMovementConverges() {
    CursorMotion motion;
    GestureSettings settings = ResponsiveSettings();
    motion.Update(CursorPoint{0.0, 0.0}, 1080.0, settings, false);
    CursorMotionResult result{};
    for (int frame = 0; frame < 30; frame++) {
        result = motion.Update(CursorPoint{1000.0, 750.0}, 1080.0, settings, false);
    }
    Expect(std::hypot(result.point.x - 1000.0, result.point.y - 750.0) < 2.0,
           "responsive cursor should converge to the target");
}

void RunCursorMotionTests() {
    TestResponsiveMovementIsNotCappedByDefault();
    TestResponsiveMovementConverges();
    std::cout << "Cursor motion tests passed" << std::endl;
}

