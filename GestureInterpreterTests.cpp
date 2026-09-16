#include "GestureInterpreter.h"

#include <cstdlib>
#include <iostream>

void RunGestureGeometryTests();

static void Expect(bool condition, const char *message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << std::endl;
        std::exit(1);
    }
}

static GestureSettings TestSettings() {
    GestureSettings settings{};
    settings.cursorGain = 1.60;
    settings.cursorSmoothing = 0.26;
    settings.cursorDeadzone = 0.003;
    settings.cursorMaxStep = 220.0;
    settings.pinchEnterRatio = 0.28;
    settings.pinchExitRatio = 0.42;
    settings.pinchActivationDelay = 0.10;
    settings.dragHoldDuration = 0.35;
    settings.dragMovementThreshold = 0.045;
    settings.scrollActivationDelay = 0.20;
    settings.scrollDeadzone = 0.005;
    settings.scrollSmoothing = 0.65;
    settings.scrollSpeed = 1.0;
    settings.scrollAcceleration = 0.0;
    return settings;
}

static ScrollFrame Frame(double time, double y, bool scroll = true, bool clutch = false) {
    return ScrollFrame{time, true, scroll, clutch, GesturePoint{0.5, y}};
}

static void TestActivationAndNoise() {
    ScrollInterpreter interpreter;
    GestureSettings settings = TestSettings();
    Expect(interpreter.ProcessFrame(Frame(0.00, 0.50), settings) == 0,
           "scroll pose should begin as a candidate");
    Expect(interpreter.ProcessFrame(Frame(0.10, 0.50), settings) == 0,
           "activation dwell should suppress output");
    Expect(interpreter.ProcessFrame(Frame(0.21, 0.50), settings) == 0,
           "scroll should activate without an initial jump");
    Expect(interpreter.IsScrolling(), "interpreter should enter scrolling state");
    Expect(interpreter.ProcessFrame(Frame(0.24, 0.502), settings) == 0,
           "deadzone should suppress camera noise");
    Expect(interpreter.ProcessFrame(Frame(0.27, 0.55), settings) > 0,
           "deliberate upward movement should scroll");
}

static void TestClutchRebasesAfterBoundary() {
    ScrollInterpreter interpreter;
    GestureSettings settings = TestSettings();
    interpreter.ProcessFrame(Frame(0.00, 0.50), settings);
    interpreter.ProcessFrame(Frame(0.21, 0.50), settings);
    Expect(interpreter.ProcessFrame(Frame(0.25, 0.95), settings) > 0,
           "movement toward the boundary should scroll");

    Expect(interpreter.ProcessFrame(Frame(0.30, 0.95, false, true), settings) == 0,
           "clutch should stop scrolling");
    Expect(interpreter.IsClutched(), "clutch should enter the clutched state");
    Expect(interpreter.ProcessFrame(Frame(0.35, 0.90), settings) == 0,
           "repositioning should not scroll during activation dwell");
    Expect(interpreter.ProcessFrame(Frame(0.56, 0.90), settings) == 0,
           "rebased scroll pose should activate without a jump");
    Expect(interpreter.ProcessFrame(Frame(0.60, 0.85), settings) < 0,
           "deliberate movement after rebasing should reverse intentionally");
}

static void TestShortReverseIsIgnored() {
    ScrollInterpreter interpreter;
    GestureSettings settings = TestSettings();
    interpreter.ProcessFrame(Frame(0.00, 0.50), settings);
    interpreter.ProcessFrame(Frame(0.21, 0.50), settings);
    Expect(interpreter.ProcessFrame(Frame(0.25, 0.60), settings) > 0,
           "initial movement should scroll");
    Expect(interpreter.ProcessFrame(Frame(0.28, 0.59), settings) == 0,
           "small reversal should be ignored");
}

int main() {
    TestActivationAndNoise();
    TestClutchRebasesAfterBoundary();
    TestShortReverseIsIgnored();
    RunGestureGeometryTests();
    std::cout << "Gesture interpreter tests passed" << std::endl;
    return 0;
}
