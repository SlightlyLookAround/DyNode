#include "api.h"
#include "colorKeyframe.h"
#include "json.hpp"
#include "projectManager.h"

using nlohmann::json;

// Returns the color keyframe count for the current chart.
DYCORE_API double DyCore_color_keyframes_count() {
    auto &pm = ProjectManager::inst();
    std::vector<ColorKeyframe> kfs;
    pm.get_color_keyframes(kfs);
    return static_cast<double>(kfs.size());
}

// Returns all color keyframes as a JSON array string.
DYCORE_API const char *DyCore_color_keyframes_get_all() {
    static std::string result;
    auto &pm = ProjectManager::inst();
    std::vector<ColorKeyframe> kfs;
    pm.get_color_keyframes(kfs);
    result = json(kfs).dump();
    return result.c_str();
}

// Returns a single color keyframe at index as a JSON string.
DYCORE_API const char *DyCore_color_keyframe_get(double index) {
    static std::string result;
    auto &pm = ProjectManager::inst();
    std::vector<ColorKeyframe> kfs;
    pm.get_color_keyframes(kfs);
    int idx = static_cast<int>(index);
    if (idx < 0 || idx >= static_cast<int>(kfs.size())) {
        result = "{}";
        return result.c_str();
    }
    result = json(kfs[idx]).dump();
    return result.c_str();
}

// Inserts a color keyframe. Automatically sorted by time.
DYCORE_API double DyCore_color_keyframe_insert(double time, double color,
                                               double interp) {
    ColorKeyframe ck;
    ck.time = time;
    ck.color = static_cast<int>(color);
    ck.interp = static_cast<ColorInterp>(static_cast<int>(interp));
    ProjectManager::inst().insert_color_keyframe(ck);
    return 0;
}

// Deletes the color keyframe at the given time (within 1ms tolerance).
DYCORE_API double DyCore_color_keyframe_delete(double time) {
    ProjectManager::inst().delete_color_keyframe(time);
    return 0;
}

// Changes the color keyframe at the given time.
DYCORE_API double DyCore_color_keyframe_change(double time, double newColor,
                                               double newInterp) {
    ProjectManager::inst().change_color_keyframe(
        time, static_cast<int>(newColor),
        static_cast<ColorInterp>(static_cast<int>(newInterp)));
    return 0;
}

// Clears all color keyframes.
DYCORE_API double DyCore_color_keyframes_reset() {
    ProjectManager::inst().clear_color_keyframes();
    return 0;
}

// Resolves the color at a given time from the current chart's keyframes.
// Returns baseColor when no keyframes apply.
DYCORE_API double DyCore_color_keyframe_resolve(double time, double baseColor) {
    std::vector<ColorKeyframe> kfs;
    ProjectManager::inst().get_color_keyframes(kfs);
    return static_cast<double>(
        color_keyframe_resolve(kfs, time, static_cast<int>(baseColor)));
}

// Returns 1 if color timeline is enabled, 0 otherwise.
DYCORE_API double DyCore_color_timeline_get_enabled() {
    return ProjectManager::inst().get_color_timeline_enabled() ? 1 : 0;
}

// Sets the color timeline enabled state.
DYCORE_API double DyCore_color_timeline_set_enabled(double enabled) {
    ProjectManager::inst().set_color_timeline_enabled(enabled > 0);
    return 0;
}
