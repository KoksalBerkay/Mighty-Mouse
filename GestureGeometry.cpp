#include "GestureGeometry.h"

#include <algorithm>
#include <cmath>
#include <initializer_list>

static constexpr double kPi = 3.14159265358979323846;

static double Distance(const GestureLandmark &first, const GestureLandmark &second) {
    return std::hypot(first.x - second.x, first.y - second.y);
}

static double Clamp(double value, double minimum, double maximum) {
    return std::max(minimum, std::min(maximum, value));
}

static double ConfidenceWeight(std::initializer_list<double> confidences) {
    double minimum = 1.0;
    for (double confidence : confidences) minimum = std::min(minimum, confidence);
    if (minimum < 0.30) return 0.0;
    return 0.70 + 0.30 * Clamp(minimum, 0.0, 1.0);
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

double GestureFingerExtensionScore(const GestureLandmark &tip,
                                   const GestureLandmark &pip,
                                   const GestureLandmark &dip,
                                   const GestureLandmark &mcp) {
    double confidence = ConfidenceWeight({tip.confidence, pip.confidence,
                                          dip.confidence, mcp.confidence});
    if (confidence == 0.0) return 0.0;
    double pipAngle = GestureJointAngle(mcp, pip, tip);
    double dipAngle = GestureJointAngle(pip, dip, tip);
    double extension = Distance(tip, mcp) / std::max(0.01, Distance(pip, mcp));
    double pipScore = Clamp((pipAngle - 118.0) / 52.0, 0.0, 1.0);
    double dipScore = Clamp((dipAngle - 115.0) / 55.0, 0.0, 1.0);
    double extensionScore = Clamp((extension - 1.05) / 0.70, 0.0, 1.0);
    return (0.50 * pipScore + 0.30 * dipScore + 0.20 * extensionScore) * confidence;
}

double GestureFingerFoldScore(const GestureLandmark &tip,
                              const GestureLandmark &pip,
                              const GestureLandmark &mcp) {
    double confidence = ConfidenceWeight({tip.confidence, pip.confidence, mcp.confidence});
    if (confidence == 0.0) return 0.0;
    double pipAngle = GestureJointAngle(mcp, pip, tip);
    double tipToMCP = Distance(tip, mcp);
    double pipToMCP = Distance(pip, mcp);
    double bendScore = Clamp((150.0 - pipAngle) / 65.0, 0.0, 1.0);
    double compressionScore = Clamp((1.35 - tipToMCP / std::max(0.01, pipToMCP)) / 0.55,
                                    0.0,
                                    1.0);
    return (0.65 * bendScore + 0.35 * compressionScore) * confidence;
}

bool GestureFingerIsExtended(const GestureLandmark &tip,
                             const GestureLandmark &pip,
                             const GestureLandmark &dip,
                             const GestureLandmark &mcp) {
    return GestureFingerExtensionScore(tip, pip, dip, mcp) >= 0.40;
}

bool GestureFingerIsFolded(const GestureLandmark &tip,
                           const GestureLandmark &pip,
                           const GestureLandmark &mcp) {
    return GestureFingerFoldScore(tip, pip, mcp) >= 0.35;
}
