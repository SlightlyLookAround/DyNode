#pragma once

#include "json.hpp"
#include "note.h"

using nlohmann::json;

inline void to_json(json &j, const NoteExportView &view) {
    j = json{{"time", view.note.time},       {"side", view.note.side},
             {"width", view.note.width},     {"position", view.note.position},
             {"length", view.note.lastTime}, {"type", view.note.type}};
}

inline void from_json(const json &j, Note &n) {
    j.at("time").get_to(n.time);
    j.at("side").get_to(n.side);
    j.at("width").get_to(n.width);
    j.at("position").get_to(n.position);
    j.at("length").get_to(n.lastTime);
    j.at("type").get_to(n.type);
    j.at("noteID").get_to(n.noteID);
    j.at("subNoteID").get_to(n.subNoteID);
    j.at("beginTime").get_to(n.beginTime);
}

inline void to_json(json &j, const Note &n) {
    j = json{{"time", n.time},          {"side", n.side},
             {"width", n.width},        {"position", n.position},
             {"length", n.lastTime},    {"type", n.type},
             {"noteID", n.noteID},      {"subNoteID", n.subNoteID},
             {"beginTime", n.beginTime}};
}
