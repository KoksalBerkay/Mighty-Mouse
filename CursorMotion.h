#pragma once

#include "Preferences.h"

struct CursorPoint {
    double x;
    double y;
};

struct CursorMotionResult {
    CursorPoint point;
    bool moved;
};

class CursorMotion {
public:
    CursorMotion();

    CursorMotionResult Update(const CursorPoint &target,
                              double screenMinimumDimension,
                              const GestureSettings &settings,
                              bool dragging);
    void Reset();

private:
    CursorPoint currentPoint_;
    bool hasPoint_;
};

