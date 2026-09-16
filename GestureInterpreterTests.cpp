#include "GestureInterpreter.h"

#include <cstdlib>
#include <iostream>

void RunGestureGeometryTests();
void RunCursorMotionTests();

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
    settings.cursorDeadzone = 0.0;
    settings.cursorMaxStep = 0.0;
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
    settings.scrollClutchEnabled = true;
    settings.scrollPoseSensitivity = 0.50;
    return settings;
}

static ScrollFrame Frame(double time, double y, bool scroll = true, bool clutch = false) {
    return ScrollFrame{time, true, scroll, clutch, GesturePoint{0.5, y}};
}

static ScrollPoseEvidence PoseEvidence(double index,
                                       double middle,
                                       double ring,
                                       double little) {
    return ScrollPoseEvidence{index, middle, ring, little};
}

static void TestScrollPoseClassifierUsesStableEvidence() {
    ScrollPoseClassifier classifier;

    Expect(!classifier.Update(PoseEvidence(0.92, 0.88, 0.78, 0.74), 0.00, 0.50),
           "two-finger pose should dwell before confirmation");
    Expect(classifier.IsIntentLikely(),
           "strong two-finger evidence should suppress cursor during dwell");
    Expect(!classifier.Update(PoseEvidence(0.78, 0.84, 0.62, 0.66), 0.05, 0.50),
           "two-finger pose should remain a candidate during dwell");
    Expect(classifier.Update(PoseEvidence(0.86, 0.82, 0.70, 0.68), 0.11, 0.50),
           "stable two-finger evidence should confirm after dwell");
    Expect(classifier.IsConfirmed(), "classifier should report a confirmed pose");
}

static void TestScrollPoseClassifierRejectsOpenHand() {
    ScrollPoseClassifier classifier;
    Expect(!classifier.Update(PoseEvidence(0.92, 0.90, 0.05, 0.04), 0.00, 0.50),
           "open hand should not confirm as a two-finger pose");
    Expect(!classifier.IsIntentLikely(),
           "open hand should not suppress normal cursor movement");
}

static void TestScrollPoseClassifierReleasesWithHysteresis() {
    ScrollPoseClassifier classifier;
    classifier.Update(PoseEvidence(0.92, 0.90, 0.82, 0.80), 0.00, 0.50);
    Expect(classifier.Update(PoseEvidence(0.92, 0.90, 0.82, 0.80), 0.11, 0.50),
           "classifier should confirm before testing release hysteresis");
    Expect(classifier.Update(PoseEvidence(0.40, 0.38, 0.10, 0.10), 0.16, 0.50),
           "one noisy frame should not release the scroll pose");
    Expect(!classifier.Update(PoseEvidence(0.40, 0.38, 0.10, 0.10), 0.33, 0.50),
           "sustained loss of pose should release after hysteresis");
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

static void TestClutchCanBeDisabled() {
    ScrollInterpreter interpreter;
    GestureSettings settings = TestSettings();
    settings.scrollClutchEnabled = false;
    interpreter.ProcessFrame(Frame(0.00, 0.50), settings);
    interpreter.ProcessFrame(Frame(0.21, 0.50), settings);
    Expect(interpreter.IsScrolling(), "scroll should activate before testing clutch preference");
    Expect(interpreter.ProcessFrame(Frame(0.25, 0.50, false, true), settings) == 0,
           "disabled clutch should not emit scroll output");
    Expect(!interpreter.IsEngaged(), "disabled clutch should exit the scroll session");
}

int main() {
    TestScrollPoseClassifierUsesStableEvidence();
    TestScrollPoseClassifierRejectsOpenHand();
    TestScrollPoseClassifierReleasesWithHysteresis();
    TestActivationAndNoise();
    TestClutchRebasesAfterBoundary();
    TestShortReverseIsIgnored();
    TestClutchCanBeDisabled();
    RunGestureGeometryTests();
    RunCursorMotionTests();
    std::cout << "Gesture interpreter tests passed" << std::endl;
    return 0;
}
