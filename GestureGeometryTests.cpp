#include "GestureGeometry.h"

#include <cmath>
#include <cstdlib>
#include <iostream>

static constexpr double kPi = 3.14159265358979323846;

static void Expect(bool condition, const char *message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << std::endl;
        std::exit(1);
    }
}

static GestureLandmark Rotate(const GestureLandmark &point, double degrees) {
    double radians = degrees * kPi / 180.0;
    return GestureLandmark{
        point.x * std::cos(radians) - point.y * std::sin(radians),
        point.x * std::sin(radians) + point.y * std::cos(radians),
        point.confidence,
    };
}

static void TestExtendedFingerIsRotationInvariant() {
    GestureLandmark mcp{0.0, 0.0, 0.95};
    GestureLandmark pip{0.0, 0.30, 0.95};
    GestureLandmark dip{0.0, 0.60, 0.95};
    GestureLandmark tip{0.0, 1.00, 0.95};
    for (double angle : {0.0, 30.0, 75.0, 120.0, 165.0}) {
        Expect(GestureFingerIsExtended(Rotate(tip, angle),
                                       Rotate(pip, angle),
                                       Rotate(dip, angle),
                                       Rotate(mcp, angle)),
               "extended finger should remain extended when rotated");
    }
}

static void TestFoldedFingerIsRecognized() {
    GestureLandmark mcp{0.0, 0.0, 0.95};
    GestureLandmark pip{0.0, 0.35, 0.95};
    GestureLandmark tip{0.28, 0.10, 0.95};
    Expect(GestureFingerIsFolded(tip, pip, mcp),
           "bent finger should be recognized as folded");
}

void RunGestureGeometryTests() {
    TestExtendedFingerIsRotationInvariant();
    TestFoldedFingerIsRecognized();
    std::cout << "Gesture geometry tests passed" << std::endl;
}
