#include "GestureGeometry.h"

#include <algorithm>
#include <cmath>

static constexpr double kPi = 3.14159265358979323846;

static double Distance(const GestureLandmark &first, const GestureLandmark &second) {
    return std::hypot(first.x - second.x, first.y - second.y);
}

double GestureJointAngle(const GestureLandmark &first,
                         const GestureLandmark &joint,
                         const GestureLandmark &last) {
    double firstX = first.x - joint.x;
    double firstY = first.y - joint.y;
    double lastX = last.x - joint.x;
    double lastY = last.y - joint.y;
    double firstLength = std::hypot(firstX, firstY);
    double lastLength = std::hypot(lastX, lastY);
    if (firstLength < 0.001 || lastLength < 0.001) return 0.0;
    double cosine = (firstX * lastX + firstY * lastY) / (firstLength * lastLength);
    cosine = std::max(-1.0, std::min(1.0, cosine));
    return std::acos(cosine) * 180.0 / kPi;
}

bool GestureFingerIsExtended(const GestureLandmark &tip,
                              const GestureLandmark &pip,
                              const GestureLandmark &dip,
                              const GestureLandmark &mcp) {
    if (tip.confidence < 0.45 || pip.confidence < 0.40 ||
        dip.confidence < 0.40 || mcp.confidence < 0.35) {
        return false;
    }
    double pipAngle = GestureJointAngle(mcp, pip, tip);
    double dipAngle = GestureJointAngle(pip, dip, tip);
    double extension = Distance(tip, mcp) / std::max(0.01, Distance(pip, mcp));
    return pipAngle >= 142.0 && dipAngle >= 135.0 && extension >= 1.16;
}

bool GestureFingerIsFolded(const GestureLandmark &tip,
                           const GestureLandmark &pip,
                           const GestureLandmark &mcp) {
    if (tip.confidence < 0.35 || pip.confidence < 0.30 || mcp.confidence < 0.30) {
        return false;
    }
    double pipAngle = GestureJointAngle(mcp, pip, tip);
    double tipToMCP = Distance(tip, mcp);
    double pipToMCP = Distance(pip, mcp);
    return pipAngle <= 150.0 || tipToMCP <= pipToMCP * 1.18;
}
