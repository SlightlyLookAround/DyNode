#include <doctest/doctest.h>

#include "colorKeyframe.h"
#include <vector>

TEST_CASE("ColorKeyframeResolve - empty keyframes") {
    std::vector<ColorKeyframe> kfs;
    CHECK(color_keyframe_resolve(kfs, 1000.0, 0xAABBCC) == 0xAABBCC);
}

TEST_CASE("ColorKeyframeResolve - before first keyframe") {
    std::vector<ColorKeyframe> kfs = {{5000.0, 0xFF0000, ColorInterp::Smooth}};
    CHECK(color_keyframe_resolve(kfs, 1000.0, 0x0000FF) == 0x0000FF);
}

TEST_CASE("ColorKeyframeResolve - at first keyframe") {
    std::vector<ColorKeyframe> kfs = {{5000.0, 0xFF0000, ColorInterp::Smooth}};
    CHECK(color_keyframe_resolve(kfs, 5000.0, 0x0000FF) == 0xFF0000);
}

TEST_CASE("ColorKeyframeResolve - after last keyframe") {
    std::vector<ColorKeyframe> kfs = {{5000.0, 0xFF0000, ColorInterp::Smooth}};
    CHECK(color_keyframe_resolve(kfs, 99999.0, 0x0000FF) == 0xFF0000);
}

TEST_CASE("ColorKeyframeResolve - instant interpolation") {
    std::vector<ColorKeyframe> kfs = {
        {1000.0, 0xFF0000, ColorInterp::Instant},
        {5000.0, 0x00FF00, ColorInterp::Instant}
    };
    // Before crossing the second keyframe, stay on first color.
    CHECK(color_keyframe_resolve(kfs, 3000.0, 0x000000) == 0xFF0000);
    // At second keyframe, switch to second color.
    CHECK(color_keyframe_resolve(kfs, 5000.0, 0x000000) == 0x00FF00);
    // After second keyframe.
    CHECK(color_keyframe_resolve(kfs, 8000.0, 0x000000) == 0x00FF00);
}

TEST_CASE("ColorKeyframeResolve - RGB interpolation") {
    std::vector<ColorKeyframe> kfs = {
        {0.0, 0xFF0000, ColorInterp::SmoothRGB},
        {1000.0, 0x0000FF, ColorInterp::SmoothRGB}
    };
    // At midpoint: (255,0,0) -> (0,0,255), t=0.5 → (128,0,128)
    int result = color_keyframe_resolve(kfs, 500.0, 0x000000);
    int r = (result >> 16) & 0xFF;
    int g = (result >> 8) & 0xFF;
    int b = result & 0xFF;
    CHECK(r == 128);
    CHECK(g == 0);
    CHECK(b == 128);
}

TEST_CASE("ColorKeyframeResolve - HSV interpolation red to green") {
    std::vector<ColorKeyframe> kfs = {
        {0.0, 0xFF0000, ColorInterp::Smooth},  // hue=0
        {1000.0, 0x00FF00, ColorInterp::Smooth}  // hue=120
    };
    // At midpoint: hue should be 60 (yellow)
    int result = color_keyframe_resolve(kfs, 500.0, 0x000000);
    int r = (result >> 16) & 0xFF;
    int g = (result >> 8) & 0xFF;
    int b = result & 0xFF;
    // Yellow ≈ (255, 255, 0)
    CHECK(r == 255);
    CHECK(g == 255);
    CHECK(b == 0);
}

TEST_CASE("ColorKeyframeResolve - multiple keyframes") {
    std::vector<ColorKeyframe> kfs = {
        {0.0, 0xFF0000, ColorInterp::SmoothRGB},
        {1000.0, 0x00FF00, ColorInterp::SmoothRGB},
        {2000.0, 0x0000FF, ColorInterp::Instant}
    };
    // In second segment (1000-2000), interp is Instant, so at 1500 → green
    CHECK(color_keyframe_resolve(kfs, 1500.0, 0x000000) == 0x00FF00);
    // At 2000 → blue
    CHECK(color_keyframe_resolve(kfs, 2000.0, 0x000000) == 0x0000FF);
}

TEST_CASE("ColorKeyframe JSON roundtrip") {
    ColorKeyframe ck{1234.5, 0xAABBCC, ColorInterp::SmoothRGB};
    nlohmann::json j = ck;
    CHECK(j["time"] == 1234.5);
    CHECK(j["color"] == 0xAABBCC);
    CHECK(j["interp"] == 1);

    auto ck2 = j.get<ColorKeyframe>();
    CHECK(ck2.time == doctest::Approx(1234.5));
    CHECK(ck2.color == 0xAABBCC);
    CHECK(ck2.interp == ColorInterp::SmoothRGB);
}
