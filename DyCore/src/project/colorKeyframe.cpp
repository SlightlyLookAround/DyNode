#include "colorKeyframe.h"

#include <algorithm>
#include <cmath>

namespace {

struct HSV {
    double h, s, v;  // h in [0,360), s,v in [0,1]
};

HSV rgb_to_hsv(int r, int g, int b) {
    double rd = r / 255.0;
    double gd = g / 255.0;
    double bd = b / 255.0;
    double cmax = std::max({rd, gd, bd});
    double cmin = std::min({rd, gd, bd});
    double diff = cmax - cmin;

    HSV hsv;
    hsv.v = cmax;
    if (cmax == 0.0) {
        hsv.s = 0.0;
        hsv.h = 0.0;
        return hsv;
    }
    hsv.s = diff / cmax;
    if (diff < 1e-10) {
        hsv.h = 0.0;
        return hsv;
    }
    if (cmax == rd)
        hsv.h = 60.0 * fmod((gd - bd) / diff, 6.0);
    else if (cmax == gd)
        hsv.h = 60.0 * ((bd - rd) / diff + 2.0);
    else
        hsv.h = 60.0 * ((rd - gd) / diff + 4.0);
    if (hsv.h < 0.0) hsv.h += 360.0;
    return hsv;
}

int hsv_to_rgb(const HSV &hsv) {
    double c = hsv.v * hsv.s;
    double x = c * (1.0 - fabs(fmod(hsv.h / 60.0, 2.0) - 1.0));
    double m = hsv.v - c;
    double rd, gd, bd;

    if (hsv.h < 60) {
        rd = c; gd = x; bd = 0;
    } else if (hsv.h < 120) {
        rd = x; gd = c; bd = 0;
    } else if (hsv.h < 180) {
        rd = 0; gd = c; bd = x;
    } else if (hsv.h < 240) {
        rd = 0; gd = x; bd = c;
    } else if (hsv.h < 300) {
        rd = x; gd = 0; bd = c;
    } else {
        rd = c; gd = 0; bd = x;
    }

    int r = static_cast<int>(std::round((rd + m) * 255.0));
    int g = static_cast<int>(std::round((gd + m) * 255.0));
    int b = static_cast<int>(std::round((bd + m) * 255.0));
    return (r << 16) | (g << 8) | b;
}

// Interpolate between two HSV colors taking the shortest hue path.
HSV lerp_hsv(const HSV &a, const HSV &b, double t) {
    HSV result;
    // Shortest hue arc
    double diff = b.h - a.h;
    if (diff > 180.0)
        diff -= 360.0;
    else if (diff < -180.0)
        diff += 360.0;
    result.h = a.h + diff * t;
    if (result.h < 0.0) result.h += 360.0;
    if (result.h >= 360.0) result.h -= 360.0;
    result.s = a.s + (b.s - a.s) * t;
    result.v = a.v + (b.v - a.v) * t;
    return result;
}

int lerp_rgb(int colA, int colB, double t) {
    int rA = (colA >> 16) & 0xFF, gA = (colA >> 8) & 0xFF, bA = colA & 0xFF;
    int rB = (colB >> 16) & 0xFF, gB = (colB >> 8) & 0xFF, bB = colB & 0xFF;
    int r = static_cast<int>(std::round(rA + (rB - rA) * t));
    int g = static_cast<int>(std::round(gA + (gB - gA) * t));
    int b = static_cast<int>(std::round(bA + (bB - bA) * t));
    return (r << 16) | (g << 8) | b;
}

}  // namespace

void to_json(nlohmann::json &j, const ColorKeyframe &ck) {
    j["time"] = ck.time;
    j["color"] = ck.color;
    j["interp"] = static_cast<int>(ck.interp);
}

void from_json(const nlohmann::json &j, ColorKeyframe &ck) {
    j.at("time").get_to(ck.time);
    j.at("color").get_to(ck.color);
    ck.interp = static_cast<ColorInterp>(j.value("interp", 0));
}

int color_keyframe_resolve(const std::vector<ColorKeyframe> &keyframes,
                           double time, int baseColor) {
    if (keyframes.empty()) return baseColor;
    if (time < keyframes.front().time) return baseColor;

    // Binary search: find the last keyframe with time <= given time.
    auto it = std::upper_bound(
        keyframes.begin(), keyframes.end(), time,
        [](double t, const ColorKeyframe &ck) { return t < ck.time; });

    // it points to the first element with ck.time > time.
    // The left keyframe is the one before it.
    auto leftIt = std::prev(it);

    // Past the last keyframe: return its color.
    if (it == keyframes.end()) return leftIt->color;

    const auto &left = *leftIt;
    const auto &right = *it;

    if (right.time <= left.time) return left.color;  // degenerate

    switch (left.interp) {
        case ColorInterp::Instant:
            return left.color;

        case ColorInterp::Smooth: {
            double t = (time - left.time) / (right.time - left.time);
            int rA = (left.color >> 16) & 0xFF, gA = (left.color >> 8) & 0xFF,
                bA = left.color & 0xFF;
            int rB = (right.color >> 16) & 0xFF, gB = (right.color >> 8) & 0xFF,
                bB = right.color & 0xFF;
            HSV hsvA = rgb_to_hsv(rA, gA, bA);
            HSV hsvB = rgb_to_hsv(rB, gB, bB);
            HSV result = lerp_hsv(hsvA, hsvB, t);
            return hsv_to_rgb(result);
        }

        case ColorInterp::SmoothRGB: {
            double t = (time - left.time) / (right.time - left.time);
            return lerp_rgb(left.color, right.color, t);
        }

        default:
            return left.color;
    }
}
