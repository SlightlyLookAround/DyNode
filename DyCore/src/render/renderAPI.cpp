#include <json.hpp>
#include <vector>

#include "api.h"
#include "note.h"
#include "render.h"
#include "utils.h"

DYCORE_API double DyCore_add_sprite_data(const char* spriteData) {
    auto j = nlohmann::json::parse(spriteData);
    SpriteData data = {.name = j["name"],
                       .size = {j["width"], j["height"]},
                       .uv0 = {j["uv00"], j["uv01"]},
                       .uv1 = {j["uv10"], j["uv11"]},
                       .paddingLR = j["paddingLR"],
                       .paddingTop = j["paddingTop"],
                       .paddingBottom = j["paddingBottom"]};
    data.caculate_uv_values();

    SpriteDrawSetting setting;
    setting.type = static_cast<SPRITE_DRAW_TYPE>(j["type"].get<int>());
    std::vector<int> dataVec = j["data"].get<std::vector<int>>();
    for (size_t i = 0; i < dataVec.size(); i++) {
        setting.data[i] = dataVec[i];
    }
    data.drawSetting = setting;
    get_sprite_manager().add_sprite(data);
    return 0.0;
}

/// notesJson: [{time,side,width,position,noteType,lastTime}, ...]
DYCORE_API double DyCore_set_diff_preview_notes(const char* notesJson,
                                                double alphaMul) {
    try {
        auto j = nlohmann::json::parse(notesJson ? notesJson : "[]");
        std::vector<Note> notes;
        if (j.is_array()) {
            notes.reserve(j.size());
            for (const auto& item : j) {
                Note n{};
                n.time = item.value("time", 0.0);
                n.side = item.value("side", 0);
                n.width = item.value("width", 1.0);
                n.position = item.value("position", 2.5);
                n.type = item.value("noteType", 0);
                n.lastTime = item.value("lastTime", 0.0);
                n.beginTime = n.time;
                notes.push_back(n);
            }
        }
        set_diff_preview_notes(std::move(notes), alphaMul);
        return 0;
    } catch (const std::exception& e) {
        print_debug_message(std::string("Error setting diff preview notes: ") +
                            e.what());
        clear_diff_preview_notes();
        return -1;
    }
}

DYCORE_API double DyCore_clear_diff_preview_notes() {
    clear_diff_preview_notes();
    return 0;
}

DYCORE_API double DyCore_get_note_rendering_vertex_buffer_bound() {
    return get_vertex_buffer_bound();
}

DYCORE_API double DyCore_prepare_note_rendering() {
    try {
        return static_cast<double>(prepare_note_rendering());
    } catch (const std::exception& e) {
        print_debug_message(std::string("Error preparing note rendering: ") +
                            e.what());
        return -1;
    }
}

DYCORE_API double DyCore_render_active_notes(char* vertexBuffer, double nowTime,
                                             double noteSpeed, double state) {
    try {
        auto result =
            render_active_notes(vertexBuffer, nowTime, noteSpeed, state);
        return static_cast<double>(result);
    } catch (const std::exception& e) {
        print_debug_message(std::string("Error rendering active notes: ") +
                            e.what());
        return -1;
    }
}