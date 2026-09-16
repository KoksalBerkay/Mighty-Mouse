#pragma once

#include "Preferences.h"

struct GesturePoint {
    double x;
    double y;
};

struct ScrollFrame {
    double timestamp;
    bool hasHand;
    bool scrollPose;
    bool clutchPose;
    GesturePoint point;
};

struct ScrollPoseEvidence {
    double indexExtension;
    double middleExtension;
    double ringFold;
    double littleFold;
};

// Converts noisy per-finger evidence into a stable two-finger intent. It is
// intentionally separate from ScrollInterpreter so uncertain poses can stop
// cursor movement without prematurely emitting scroll events.
class ScrollPoseClassifier {
public:
    ScrollPoseClassifier();

    bool Update(const ScrollPoseEvidence &evidence,
                double timestamp,
                double sensitivity);
    void Reset();
    bool IsIntentLikely() const;
    bool IsConfirmed() const;
    double Score() const;

private:
    bool confirmed_;
    bool candidateActive_;
    bool releaseActive_;
    double candidateStartTime_;
    double releaseStartTime_;
    double score_;
    double intentThreshold_;
    bool intentLikely_;
};

// Converts a stable two-finger pose into relative scroll lines. This class is
// deliberately independent of Vision and CoreGraphics so its state transitions
// can be tested with deterministic landmark traces.
class ScrollInterpreter {
public:
    ScrollInterpreter();

    // Returns the number of vertical scroll lines to post for this frame.
    int ProcessFrame(const ScrollFrame &frame, const GestureSettings &settings);

    void Reset();
    bool IsEngaged() const;
    bool IsClutched() const;
    bool IsScrolling() const;

private:
    enum class State {
        Idle,
        Candidate,
        Scrolling,
        Clutched,
    };

    State state_;
    double candidateStartTime_;
    GesturePoint filteredPoint_;
    bool hasFilteredPoint_;
    double scrollRemainder_;
    int lastDirection_;
    double reversalAccumulator_;
};
