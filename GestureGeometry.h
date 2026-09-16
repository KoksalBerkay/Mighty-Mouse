#pragma once

struct GestureLandmark {
    double x;
    double y;
    double confidence;
};

double GestureJointAngle(const GestureLandmark &first,
                         const GestureLandmark &joint,
                         const GestureLandmark &last);

// Continuous scores make pose classification tolerant of Vision jitter. A
// score of 0 means no evidence and 1 means strong geometric evidence.
double GestureFingerExtensionScore(const GestureLandmark &tip,
                                   const GestureLandmark &pip,
                                   const GestureLandmark &dip,
                                   const GestureLandmark &mcp);

double GestureFingerFoldScore(const GestureLandmark &tip,
                              const GestureLandmark &pip,
                              const GestureLandmark &mcp);

bool GestureFingerIsExtended(const GestureLandmark &tip,
                              const GestureLandmark &pip,
                              const GestureLandmark &dip,
                              const GestureLandmark &mcp);

bool GestureFingerIsFolded(const GestureLandmark &tip,
                           const GestureLandmark &pip,
                           const GestureLandmark &mcp);
