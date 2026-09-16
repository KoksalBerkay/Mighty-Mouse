#include "GestureInterpreter.h"

#include <algorithm>
#include <cmath>

static double Clamp(double value, double minimum, double maximum) {
    return std::max(minimum, std::min(maximum, value));
}

static int Sign(double value) {
    return value < 0.0 ? -1 : (value > 0.0 ? 1 : 0);
}

ScrollPoseClassifier::ScrollPoseClassifier() {
    Reset();
}

void ScrollPoseClassifier::Reset() {
    confirmed_ = false;
    candidateActive_ = false;
    releaseActive_ = false;
    candidateStartTime_ = 0.0;
    releaseStartTime_ = 0.0;
    score_ = 0.0;
    intentThreshold_ = 0.30;
    intentLikely_ = false;
}

bool ScrollPoseClassifier::Update(const ScrollPoseEvidence &evidence,
                                  double timestamp,
                                  double sensitivity) {
    double pairScore = std::min(evidence.indexExtension, evidence.middleExtension);
    double foldScore = std::min(evidence.ringFold, evidence.littleFold);
    score_ = 0.65 * pairScore + 0.35 * foldScore;

    double normalizedSensitivity = Clamp(sensitivity, 0.0, 1.0);
    double acquireThreshold = 0.44 + normalizedSensitivity * 0.12;
    double releaseThreshold = acquireThreshold - 0.16;
    intentThreshold_ = acquireThreshold - 0.20;
    bool enoughFingerEvidence = pairScore >= 0.34 && foldScore >= 0.12;
    intentLikely_ = enoughFingerEvidence && score_ >= intentThreshold_;

    if (confirmed_) {
        if (enoughFingerEvidence && score_ >= releaseThreshold) {
            releaseActive_ = false;
            intentLikely_ = true;
            return true;
        }
        if (!releaseActive_) {
            releaseActive_ = true;
            releaseStartTime_ = timestamp;
        }
        if (timestamp - releaseStartTime_ < 0.16) {
            intentLikely_ = true;
            return true;
        }
        confirmed_ = false;
        releaseActive_ = false;
        candidateActive_ = false;
        intentLikely_ = false;
        return false;
    }

    if (enoughFingerEvidence && score_ >= acquireThreshold) {
        if (!candidateActive_) {
            candidateActive_ = true;
            candidateStartTime_ = timestamp;
        }
        if (timestamp - candidateStartTime_ >= 0.10) {
            confirmed_ = true;
            candidateActive_ = false;
            return true;
        }
    } else {
        candidateActive_ = false;
    }
    return false;
}

bool ScrollPoseClassifier::IsIntentLikely() const {
    return confirmed_ || candidateActive_ || intentLikely_;
}

bool ScrollPoseClassifier::IsConfirmed() const {
    return confirmed_;
}

double ScrollPoseClassifier::Score() const {
    return score_;
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
