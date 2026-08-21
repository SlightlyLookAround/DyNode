#pragma once
#include <json.hpp>
#include <vector>

enum class ColorInterp : int {
    Smooth = 0,      // HSV linear interpolation (shortest hue arc)
    SmoothRGB = 1,   // RGB linear interpolation
    Instant = 2      // Instant switch
};

struct ColorKeyframe {
    double time;       // milliseconds
    int color;         // 0xRRGGBB
    ColorInterp interp;
};

void to_json(nlohmann::json &j, const ColorKeyframe &ck);
void from_json(const nlohmann::json &j, ColorKeyframe &ck);

// Resolve the color at a given time from a sorted keyframe list.
// Returns baseColor when keyframes is empty or time is before the first keyframe.
int color_keyframe_resolve(const std::vector<ColorKeyframe> &keyframes,
                           double time, int baseColor);
