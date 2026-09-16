#include "GestureInterpreter.h"

#include <algorithm>
#include <cmath>

static double Clamp(double value, double minimum, double maximum) {
    return std::max(minimum, std::min(maximum, value));
}

static int Sign(double value) {
    return value < 0.0 ? -1 : (value > 0.0 ? 1 : 0);
}

ScrollInterpreter::ScrollInterpreter() {
    Reset();
}

void ScrollInterpreter::Reset() {
    state_ = State::Idle;
    candidateStartTime_ = 0.0;
    filteredPoint_ = {0.0, 0.0};
    hasFilteredPoint_ = false;
    scrollRemainder_ = 0.0;
    lastDirection_ = 0;
    reversalAccumulator_ = 0.0;
}

bool ScrollInterpreter::IsEngaged() const {
    return state_ != State::Idle;
}

bool ScrollInterpreter::IsClutched() const {
    return state_ == State::Clutched;
}

bool ScrollInterpreter::IsScrolling() const {
    return state_ == State::Scrolling;
}

int ScrollInterpreter::ProcessFrame(const ScrollFrame &frame,
                                    const GestureSettings &settings) {
    if (!frame.hasHand) {
        Reset();
        return 0;
    }

    // A pinch while scrolling is a clutch, not a click. It freezes output and
    // forces the next two-finger pose to establish a new movement baseline.
    if (frame.clutchPose && settings.scrollClutchEnabled && state_ != State::Idle) {
        state_ = State::Clutched;
        hasFilteredPoint_ = false;
        scrollRemainder_ = 0.0;
        lastDirection_ = 0;
        reversalAccumulator_ = 0.0;
        return 0;
    }

    if (state_ == State::Clutched) {
        if (!frame.scrollPose) {
            Reset();
            return 0;
        }
        state_ = State::Candidate;
        candidateStartTime_ = frame.timestamp;
        filteredPoint_ = frame.point;
        hasFilteredPoint_ = true;
        return 0;
    }

    if (!frame.scrollPose) {
        Reset();
        return 0;
    }

    if (state_ == State::Idle) {
        state_ = State::Candidate;
        candidateStartTime_ = frame.timestamp;
        filteredPoint_ = frame.point;
        hasFilteredPoint_ = true;
        return 0;
    }

    if (state_ == State::Candidate) {
        if (frame.timestamp - candidateStartTime_ < settings.scrollActivationDelay) {
            return 0;
        }
        state_ = State::Scrolling;
        filteredPoint_ = frame.point;
        hasFilteredPoint_ = true;
        scrollRemainder_ = 0.0;
        lastDirection_ = 0;
        reversalAccumulator_ = 0.0;
        return 0;
    }

    if (!hasFilteredPoint_) {
        filteredPoint_ = frame.point;
        hasFilteredPoint_ = true;
        return 0;
    }

    double alpha = Clamp(settings.scrollSmoothing, 0.12, 0.65);
    GesturePoint nextPoint{
        filteredPoint_.x + (frame.point.x - filteredPoint_.x) * alpha,
        filteredPoint_.y + (frame.point.y - filteredPoint_.y) * alpha,
    };
    double deltaY = nextPoint.y - filteredPoint_.y;
    filteredPoint_ = nextPoint;

    double magnitude = std::fabs(deltaY);
    if (magnitude <= settings.scrollDeadzone) return 0;

    double usableDelta = std::copysign(magnitude - settings.scrollDeadzone, deltaY);
    double directionAdjustedDelta = settings.invertScroll ? -usableDelta : usableDelta;
    int direction = Sign(directionAdjustedDelta);

    // Require a meaningful sustained movement before reversing direction. It
    // prevents a tremor or filtering overshoot from flipping the scroll while
    // still allowing an intentional reversal within the same session.
    if (lastDirection_ != 0 && direction != lastDirection_) {
        reversalAccumulator_ += std::fabs(directionAdjustedDelta);
        double reversalThreshold = std::max(settings.scrollDeadzone * 3.0, 0.025);
        if (reversalAccumulator_ < reversalThreshold) return 0;
        lastDirection_ = direction;
        reversalAccumulator_ = 0.0;
    } else {
        reversalAccumulator_ = 0.0;
        lastDirection_ = direction;
    }

    double normalizedVelocity = Clamp(magnitude * 18.0, 0.0, 1.0);
    double acceleration = 1.0 + settings.scrollAcceleration * normalizedVelocity;
    scrollRemainder_ += directionAdjustedDelta * 70.0 * settings.scrollSpeed * acceleration;

    int scrollLines = static_cast<int>(Clamp(scrollRemainder_, -6.0, 6.0));
    if (scrollLines != 0) scrollRemainder_ -= scrollLines;
    return scrollLines;
}
