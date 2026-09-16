#pragma once

struct GestureLandmark {
    double x;
    double y;
    double confidence;
};

double GestureJointAngle(const GestureLandmark &first,
                         const GestureLandmark &joint,
                         const GestureLandmark &last);

bool GestureFingerIsExtended(const GestureLandmark &tip,
                              const GestureLandmark &pip,
                              const GestureLandmark &dip,
                              const GestureLandmark &mcp);

bool GestureFingerIsFolded(const GestureLandmark &tip,
                           const GestureLandmark &pip,
                           const GestureLandmark &mcp);

