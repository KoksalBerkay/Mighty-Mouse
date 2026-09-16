#include "CursorMotion.h"

#include <algorithm>
#include <cmath>

static double Clamp(double value, double minimum, double maximum) {
    return std::max(minimum, std::min(maximum, value));
}

CursorMotion::CursorMotion() {
    Reset();
}

void CursorMotion::Reset() {
    currentPoint_ = {0.0, 0.0};
    hasPoint_ = false;
}

CursorMotionResult CursorMotion::Update(const CursorPoint &target,
                                        double screenMinimumDimension,
                                        const GestureSettings &settings,
                                        bool dragging) {
    if (!hasPoint_) {
        currentPoint_ = target;
        hasPoint_ = true;
        return CursorMotionResult{currentPoint_, false};
    }

    double alpha = dragging
        ? std::min(0.60, settings.cursorSmoothing + 0.10)
        : settings.cursorSmoothing;
    alpha = Clamp(alpha, 0.05, 1.0);
    CursorPoint smoothed{
        currentPoint_.x + (target.x - currentPoint_.x) * alpha,
        currentPoint_.y + (target.y - currentPoint_.y) * alpha,
    };
    double deltaX = smoothed.x - currentPoint_.x;
    double deltaY = smoothed.y - currentPoint_.y;
    double distance = std::hypot(deltaX, deltaY);
    double deadzonePixels = std::max(0.0, settings.cursorDeadzone) *
                            std::max(1.0, screenMinimumDimension);
    if (distance <= deadzonePixels) {
        return CursorMotionResult{currentPoint_, false};
    }

    if (settings.cursorMaxStep > 0.0 && distance > settings.cursorMaxStep) {
        double scale = settings.cursorMaxStep / distance;
        smoothed.x = currentPoint_.x + deltaX * scale;
        smoothed.y = currentPoint_.y + deltaY * scale;
    }
    currentPoint_ = smoothed;
    return CursorMotionResult{currentPoint_, true};
}

