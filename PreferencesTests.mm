#include <cmath>
#include <iostream>

#include "Preferences.h"

static bool NearlyEqual(double actual, double expected) {
    return std::fabs(actual - expected) < 0.0001;
}

int main() {
    GestureSettings defaults = DefaultGestureSettings();
    if (!NearlyEqual(defaults.cursorSmoothing, 0.38)) {
        std::cerr << "Expected Responsive cursor response by default\n";
        return 1;
    }
    if (!NearlyEqual(defaults.scrollSpeed, 2.20)) {
        std::cerr << "Expected Very Fast scroll speed by default\n";
        return 1;
    }
    if (!NearlyEqual(defaults.scrollPoseSensitivity, 1.00)) {
        std::cerr << "Expected Strict two-finger pose by default\n";
        return 1;
    }

    std::cout << "Default menu preset values passed\n";
    return 0;
}
