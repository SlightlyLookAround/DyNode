#include "mcpTools.h"

#include <algorithm>

#include "editor.h"
#include "mcpBridge.h"
#include "mcpServer.h"
#include "note.h"
#include "notePoolManager.h"
#include "note_json.h"
#include "project.h"
#include "projectManager.h"
#include "timing.h"

namespace mcp {
namespace {

bool bridge_submit(const std::string& kind, const nlohmann::json& payload,
                   nlohmann::json& out, std::string& err) {
    return McpBridge::inst().submit(kind, payload, out, err);
}

ToolOutcome ok_json(nlohmann::json payload) {
    ToolOutcome o;
    o.isError = false;
    o.payload = std::move(payload);
    return o;
}

ToolOutcome err_json(const std::string& message) {
    ToolOutcome o;
    o.isError = true;
    o.payload = nlohmann::json{{"ok", false}, {"error", message}};
    return o;
}

nlohmann::json note_to_tool_json(const Note& n) {
    return nlohmann::json{{"noteID", n.noteID},
                          {"subNoteID", n.subNoteID},
                          {"side", n.side},
                          {"type", n.type},
                          {"time", n.time},
                          {"width", n.width},
                          {"position", n.position},
                          {"lastTime", n.lastTime},
                          {"beginTime", n.beginTime}};
}

bool parse_note_partial(const nlohmann::json& j, Note& n, std::string& err) {
    try {
        if (j.contains("time")) j.at("time").get_to(n.time);
        if (j.contains("side")) j.at("side").get_to(n.side);
        if (j.contains("width")) j.at("width").get_to(n.width);
        if (j.contains("position")) j.at("position").get_to(n.position);
        if (j.contains("lastTime")) j.at("lastTime").get_to(n.lastTime);
        else if (j.contains("length")) j.at("length").get_to(n.lastTime);
        if (j.contains("beginTime")) j.at("beginTime").get_to(n.beginTime);
        if (j.contains("type")) j.at("type").get_to(n.type);
        if (j.contains("noteID")) j.at("noteID").get_to(n.noteID);
        if (j.contains("subNoteID")) j.at("subNoteID").get_to(n.subNoteID);
        return true;
    } catch (const std::exception& e) {
        err = e.what();
        return false;
    }
}

ToolOutcome tool_get_status(const nlohmann::json&) {
    auto& pool = get_note_pool_manager();
    auto& timing = get_timing_manager();
    nlohmann::json out{
        {"running", true},
        {"editorReady", gmeditor_is_ready()},
        {"noteCount", pool.get_note_count()},
        {"timingCount", timing.count()},
        {"projectPath", ProjectManager::inst().get_project_path()},
        {"url", McpServer::inst().info().value("url", std::string{})},
        {"token", McpServer::inst().info().value("token", std::string{})},
    };
    try {
        out["projectMetadata"] = ProjectManager::inst().get_project_metadata();
    } catch (...) {
        out["projectMetadata"] = nlohmann::json::object();
    }
    try {
        out["chartMetadata"] = ProjectManager::inst().get_chart_metadata();
    } catch (...) {
        out["chartMetadata"] = nlohmann::json::object();
    }
    try {
        auto diffs = ProjectManager::inst().get_chart_difficulties();
        out["difficulties"] = diffs;
    } catch (...) {
        out["difficulties"] = nlohmann::json::array();
    }

    nlohmann::json selection;
    std::string err;
    if (bridge_submit("get_selection", nlohmann::json::object(), selection, err)) {
        out["selectionCount"] = selection.value("count", 0);
        if (selection.contains("noteIDs")) out["selectionNoteIDs"] = selection["noteIDs"];
    } else {
        out["selectionCount"] = -1;
        out["selectionError"] = err;
    }
    return ok_json(out);
}

ToolOutcome tool_list_notes(const nlohmann::json& args) {
    const double timeMin = args.value("timeMin", -std::numeric_limits<double>::infinity());
    const double timeMax = args.value("timeMax", std::numeric_limits<double>::infinity());
    const int limit = std::max(1, args.value("limit", 200));
    const bool hasSide = args.contains("side");
    const bool hasType = args.contains("type");
    const bool selectedOnly = args.value("selectedOnly", false);
    const int side = args.value("side", 0);
    const int type = args.value("type", 0);
    std::vector<std::string> selectedIds;
    if (selectedOnly) {
        nlohmann::json sel;
        std::string selErr;
        if (!bridge_submit("get_selection", nlohmann::json::object(), sel, selErr)) {
            return err_json(selErr);
        }
        if (sel.contains("noteIDs")) {
            for (const auto& id : sel["noteIDs"]) selectedIds.push_back(id.get<std::string>());
        }
    }

    std::vector<Note> notes;
    get_note_pool_manager().get_notes(notes, true);

    nlohmann::json arr = nlohmann::json::array();
    int matched = 0;
    for (const auto& n : notes) {
        if (n.time < timeMin || n.time > timeMax) continue;
        if (hasSide && n.side != side) continue;
        if (hasType && n.type != type) continue;
        if (selectedOnly) {
            if (std::find(selectedIds.begin(), selectedIds.end(), n.noteID) == selectedIds.end()) continue;
        }
        ++matched;
        if (static_cast<int>(arr.size()) < limit) arr.push_back(note_to_tool_json(n));
    }
    return ok_json({{"notes", arr}, {"total", matched}});
}

ToolOutcome tool_insert_notes(const nlohmann::json& args) {
    if (!args.contains("notes") || !args["notes"].is_array()) {
        return err_json("notes array is required");
    }
    // When the GameMaker editor is live, note mutations MUST run on the main
    // thread: render/activation read the pool without locks and HTTP-thread
    // writes race those reads (silent native crash, often first seen on save).
    // Headless/unit-test paths have no renderer, so C++ may mutate directly.
    if (gmeditor_is_ready()) {
        nlohmann::json result;
        std::string err;
        if (!bridge_submit("insert_notes", args, result, err)) {
            return err_json(err);
        }
        return ok_json(result);
    }

    auto& pool = get_note_pool_manager();
    nlohmann::json created = nlohmann::json::array();
    nlohmann::json failed = nlohmann::json::array();
    for (const auto& item : args["notes"]) {
        Note n{};
        n.beginTime = 0;
        std::string err;
        if (!parse_note_partial(item, n, err)) {
            failed.push_back({{"error", err}});
            continue;
        }
        try {
            if (n.noteID.empty()) n.noteID = generate_note_id();
            if (create_note(n, false, true) < 0) {
                failed.push_back({{"noteID", n.noteID}, {"error", "create_note failed"}});
                continue;
            }
            created.push_back(n.noteID);
        } catch (const std::exception& e) {
            failed.push_back({{"noteID", n.noteID}, {"error", e.what()}});
        }
    }
    pool.array_sort_request();
    return ok_json({{"created", created},
                    {"count", created.size()},
                    {"failed", failed}});
}

ToolOutcome tool_update_notes(const nlohmann::json& args) {
    if (!args.contains("updates") || !args["updates"].is_array()) {
        return err_json("updates array is required");
    }
    if (gmeditor_is_ready()) {
        nlohmann::json result;
        std::string err;
        if (!bridge_submit("update_notes", args, result, err)) {
            return err_json(err);
        }
        return ok_json(result);
    }

    auto& pool = get_note_pool_manager();
    nlohmann::json updated = nlohmann::json::array();
    nlohmann::json failed = nlohmann::json::array();
    for (const auto& item : args["updates"]) {
        if (!item.contains("noteID")) {
            failed.push_back({{"error", "noteID is required"}});
            continue;
        }
        const std::string noteID = item.at("noteID").get<std::string>();
        if (!pool.note_exists(noteID)) {
            failed.push_back({{"noteID", noteID}, {"error", "note not found"}});
            continue;
        }
        try {
            Note n = pool.get_note(noteID);
            std::string err;
            if (!parse_note_partial(item, n, err)) {
                failed.push_back({{"noteID", noteID}, {"error", err}});
                continue;
            }
            n.noteID = noteID;
            if (modify_note(n) < 0) {
                failed.push_back({{"noteID", noteID}, {"error", "modify_note failed"}});
                continue;
            }
            updated.push_back(noteID);
        } catch (const std::exception& e) {
            failed.push_back({{"noteID", noteID}, {"error", e.what()}});
        }
    }
    pool.array_sort_request();
    return ok_json({{"updated", updated}, {"failed", failed}});
}

ToolOutcome tool_delete_notes(const nlohmann::json& args) {
    if (gmeditor_is_ready()) {
        nlohmann::json result;
        std::string err;
        if (!bridge_submit("delete_notes", args, result, err)) {
            return err_json(err);
        }
        return ok_json(result);
    }

    auto& pool = get_note_pool_manager();
    std::vector<std::string> ids;
    if (args.contains("noteIDs") && args["noteIDs"].is_array()) {
        for (const auto& id : args["noteIDs"]) ids.push_back(id.get<std::string>());
    } else if (args.contains("filter")) {
        if (!args.value("confirm", false)) {
            return err_json("filter delete requires confirm:true");
        }
        const auto& f = args["filter"];
        const double timeMin = f.value("timeMin", -std::numeric_limits<double>::infinity());
        const double timeMax = f.value("timeMax", std::numeric_limits<double>::infinity());
        const bool hasSide = f.contains("side");
        const bool hasType = f.contains("type");
        std::vector<Note> notes;
        pool.get_notes(notes, true);
        for (const auto& n : notes) {
            if (n.time < timeMin || n.time > timeMax) continue;
            if (hasSide && n.side != f.at("side").get<int>()) continue;
            if (hasType && n.type != f.at("type").get<int>()) continue;
            ids.push_back(n.noteID);
        }
    } else {
        return err_json("provide noteIDs or filter");
    }

    nlohmann::json deletedIds = nlohmann::json::array();
    for (const auto& id : ids) {
        if (note_exists(id) && delete_note(id) == 0) {
            deletedIds.push_back(id);
        }
    }
    return ok_json({{"deleted", deletedIds.size()}, {"noteIDs", deletedIds}});
}
ToolOutcome tool_list_timing_points(const nlohmann::json&) {
    auto& timing = get_timing_manager();
    std::vector<TimingPoint> points;
    timing.get_timing_points(points);
    nlohmann::json arr = nlohmann::json::array();
    for (const auto& tp : points) {
        arr.push_back({{"time", tp.time},
                       {"beatLength", tp.beatLength},
                       {"meter", tp.meter},
                       {"bpm", tp.get_bpm()}});
    }
    return ok_json({{"timingPoints", arr}, {"count", arr.size()}});
}

bool parse_timing_point(const nlohmann::json& j, TimingPoint& tp, std::string& err) {
    try {
        if (j.contains("time")) j.at("time").get_to(tp.time);
        else if (j.contains("offset")) j.at("offset").get_to(tp.time);
        else {
            err = "time/offset is required";
            return false;
        }
        if (j.contains("beatLength")) j.at("beatLength").get_to(tp.beatLength);
        else if (j.contains("bpm")) {
            double bpm = 0;
            j.at("bpm").get_to(bpm);
            if (bpm <= 0) {
                err = "bpm must be positive";
                return false;
            }
            tp.set_bpm(bpm);
        } else {
            err = "beatLength/bpm is required";
            return false;
        }
        tp.meter = j.value("meter", 4);
        return true;
    } catch (const std::exception& e) {
        err = e.what();
        return false;
    }
}

ToolOutcome tool_set_timing_points(const nlohmann::json& args) {
    if (!args.contains("timingPoints") || !args["timingPoints"].is_array()) {
        return err_json("timingPoints array is required");
    }
    const std::string mode = args.value("mode", std::string("replace"));
    auto& timing = get_timing_manager();
    if (mode == "replace") {
        timing.clear();
    } else if (mode != "merge") {
        return err_json("mode must be replace or merge");
    }
    int count = 0;
    nlohmann::json failed = nlohmann::json::array();
    for (const auto& item : args["timingPoints"]) {
        TimingPoint tp{};
        std::string err;
        if (!parse_timing_point(item, tp, err)) {
            failed.push_back({{"error", err}, {"item", item}});
            continue;
        }
        timing.add_timing_point(tp);
        ++count;
    }
    timing.sort();
    return ok_json({{"count", count}, {"failed", failed}});
}

ToolOutcome tool_insert_timing_point(const nlohmann::json& args) {
    TimingPoint tp{};
    std::string err;
    if (!parse_timing_point(args, tp, err)) return err_json(err);
    get_timing_manager().add_timing_point(tp);
    get_timing_manager().sort();
    return ok_json({{"ok", true}, {"time", tp.time}});
}

ToolOutcome tool_delete_timing_point(const nlohmann::json& args) {
    if (!args.contains("time")) return err_json("time is required");
    const double time = args.at("time").get<double>();
    get_timing_manager().delete_timing_point_at_time(time);
    return ok_json({{"ok", true}, {"time", time}});
}

ToolOutcome tool_apply_expression(const nlohmann::json& args) {
    if (!args.contains("expression") || !args["expression"].is_string()) {
        return err_json("expression is required");
    }
    nlohmann::json payload = {
        {"expression", args.at("expression").get<std::string>()},
        {"scope", args.value("scope", std::string("selection"))},
        {"dryRun", args.value("dryRun", false)},
    };
    if (args.contains("noteIDs")) payload["noteIDs"] = args["noteIDs"];

    nlohmann::json result;
    std::string err;
    if (!bridge_submit("apply_expression", payload, result, err)) {
        return err_json(err);
    }
    return ok_json(result);
}

ToolOutcome tool_evaluate_expression(const nlohmann::json& args) {
    if (!args.contains("expression") || !args["expression"].is_string()) {
        return err_json("expression is required");
    }
    nlohmann::json payload = {
        {"expression", args.at("expression").get<std::string>()},
        {"context", args.value("context", nlohmann::json::object())},
    };
    nlohmann::json result;
    std::string err;
    if (!bridge_submit("evaluate_expression", payload, result, err)) {
        return err_json(err);
    }
    return ok_json(result);
}

ToolOutcome tool_get_expression_reference(const nlohmann::json&) {
    return ok_json(expression_reference_json());
}

}  // namespace

McpToolRegistry& McpToolRegistry::inst() {
    static McpToolRegistry inst;
    return inst;
}

void McpToolRegistry::register_tool(ToolSpec spec, ToolHandler handler) {
    std::lock_guard<std::mutex> lock(mtx);
    tools.push_back(Entry{std::move(spec), std::move(handler)});
}

std::vector<ToolSpec> McpToolRegistry::list_tools() const {
    std::lock_guard<std::mutex> lock(mtx);
    std::vector<ToolSpec> out;
    out.reserve(tools.size());
    for (const auto& e : tools) out.push_back(e.spec);
    return out;
}

bool McpToolRegistry::has_tool(const std::string& name) const {
    std::lock_guard<std::mutex> lock(mtx);
    return std::any_of(tools.begin(), tools.end(),
                       [&](const Entry& e) { return e.spec.name == name; });
}

ToolOutcome McpToolRegistry::call(const std::string& name,
                                  const nlohmann::json& arguments) const {
    ToolHandler handler;
    {
        std::lock_guard<std::mutex> lock(mtx);
        for (const auto& e : tools) {
            if (e.spec.name == name) {
                handler = e.handler;
                break;
            }
        }
    }
    if (!handler) return err_json("unknown tool: " + name);
    try {
        return handler(arguments);
    } catch (const std::exception& e) {
        return err_json(e.what());
    }
}

void McpToolRegistry::clear() {
    std::lock_guard<std::mutex> lock(mtx);
    tools.clear();
}

nlohmann::json expression_reference_json() {
    return nlohmann::json{
        {"variables",
         {
             {{"name", "time"}, {"access", "rw"}, {"desc", "note time in ms"}},
             {{"name", "pos"}, {"access", "rw"}, {"desc", "note position"}},
             {{"name", "wid"}, {"access", "rw"}, {"desc", "note width"}},
             {{"name", "len"}, {"access", "rw"}, {"desc", "hold length (lastTime)"}},
             {{"name", "side"}, {"access", "rw"}, {"desc", "0 front / 1 back / 2 side"}},
             {{"name", "htime"}, {"access", "rw"}, {"desc", "hold head time"}},
             {{"name", "etime"}, {"access", "rw"}, {"desc", "hold end time"}},
             {{"name", "index"}, {"access", "r"}, {"desc", "index in current scope"}},
             {{"name", "bpm"}, {"access", "r"}, {"desc", "BPM at note time"}},
             {{"name", "meter"}, {"access", "r"}, {"desc", "meter at note time"}},
             {{"name", "tptime"}, {"access", "r"}, {"desc", "timing point time"}},
             {{"name", "bar"}, {"access", "rw"}, {"desc", "bar position"}},
             {{"name", "abar"}, {"access", "w"}, {"desc", "absolute bar (write-only)"}},
         }},
        {"functions",
         {"pow", "sin", "cos", "step", "clamp", "exp", "floor", "ceil", "round",
          "rand", "randr", "irand", "irandr", "btt", "ttb", "tabd"}},
        {"constants", {{"pi", 3.14159265358979323846}}},
        {"operators",
         {"+", "-", "*", "/", "%", "<<", ">>", ">", ">=", "<", "<=", "==", "!=",
          "&", "|", "^", "&&", "||", "=", "!", "unary +/-"}},
        {"sequence", "Separate statements with ';'. Last statement value is returned."},
        {"scopes",
         {{"selection", "apply to currently selected notes"},
          {"all", "apply to every non-sub note"},
          {"noteIDs", "apply to explicit noteID list"}}},
    };
}

void register_default_tools() {
    auto& reg = McpToolRegistry::inst();
    reg.clear();

    auto obj = [](const char* type, const char* desc) {
        return nlohmann::json{{"type", type}, {"description", desc}};
    };

    reg.register_tool(
        {"get_status",
         "Read editor/project status including note, timing and selection counts.",
         {{"type", "object"}, {"properties", nlohmann::json::object()}}},
        tool_get_status);

    reg.register_tool(
        {"get_expression_reference",
         "Catalog of DyNode advanced-expression variables, functions and operators.",
         {{"type", "object"}, {"properties", nlohmann::json::object()}}},
        tool_get_expression_reference);

    reg.register_tool(
        {"list_notes",
         "List chart notes with optional time/side/type filters.",
         {{"type", "object"},
          {"properties",
           {{"timeMin", obj("number", "inclusive lower time bound (ms)")},
            {"timeMax", obj("number", "inclusive upper time bound (ms)")},
            {"side", obj("integer", "0 front / 1 back / 2 side")},
            {"type", obj("integer", "0 normal / 1 chain / 2 hold")},
            {"limit", obj("integer", "max notes to return (default 200)")}}}}},
        tool_list_notes);

    reg.register_tool(
        {"insert_notes",
         "Insert notes in batch. Each note: side, type, time, width, position[, lastTime, beginTime, noteID].",
         {{"type", "object"},
          {"properties", {{"notes", {{"type", "array"}, {"items", {{"type", "object"}}}}}}},
          {"required", nlohmann::json::array({"notes"})}}},
        tool_insert_notes);

    reg.register_tool(
        {"update_notes",
         "Update existing notes by noteID. Only provided fields are changed.",
         {{"type", "object"},
          {"properties", {{"updates", {{"type", "array"}, {"items", {{"type", "object"}}}}}}},
          {"required", nlohmann::json::array({"updates"})}}},
        tool_update_notes);

    reg.register_tool(
        {"delete_notes",
         "Delete notes by noteID list, or by filter when confirm=true.",
         {{"type", "object"},
          {"properties",
           {{"noteIDs", {{"type", "array"}, {"items", {{"type", "string"}}}}},
            {"filter", {{"type", "object"}}},
            {"confirm", obj("boolean", "required true when using filter")}}}}},
        tool_delete_notes);

    reg.register_tool(
        {"list_timing_points",
         "List timing points (time, beatLength, meter, bpm).",
         {{"type", "object"}, {"properties", nlohmann::json::object()}}},
        tool_list_timing_points);

    reg.register_tool(
        {"set_timing_points",
         "Replace or merge timing points. Each point: time|offset and beatLength|bpm, meter.",
         {{"type", "object"},
          {"properties",
           {{"timingPoints", {{"type", "array"}, {"items", {{"type", "object"}}}}},
            {"mode", obj("string", "replace | merge (default replace)")}}},
          {"required", nlohmann::json::array({"timingPoints"})}}},
        tool_set_timing_points);

    reg.register_tool(
        {"insert_timing_point",
         "Insert a single timing point.",
         {{"type", "object"},
          {"properties",
           {{"time", obj("number", "time in ms")},
            {"offset", obj("number", "alias of time")},
            {"beatLength", obj("number", "ms per beat")},
            {"bpm", obj("number", "alternative to beatLength")},
            {"meter", obj("integer", "beats per bar (default 4)")}}}}},
        tool_insert_timing_point);

    reg.register_tool(
        {"delete_timing_point",
         "Delete the timing point at the given time.",
         {{"type", "object"},
          {"properties", {{"time", obj("number", "timing point time in ms")}}},
          {"required", nlohmann::json::array({"time"})}}},
        tool_delete_timing_point);

    reg.register_tool(
        {"apply_expression",
         "Run an advanced-expression sequence on notes (selection/all/noteIDs).",
         {{"type", "object"},
          {"properties",
           {{"expression", obj("string", "expression sequence, statements separated by ';'")},
            {"scope", obj("string", "selection | all | noteIDs")},
            {"noteIDs", {{"type", "array"}, {"items", {{"type", "string"}}}}},
            {"dryRun", obj("boolean", "evaluate without writing notes")}}},
          {"required", nlohmann::json::array({"expression"})}}},
        tool_apply_expression);

    reg.register_tool(
        {"evaluate_expression",
         "Evaluate an expression against a synthetic note context without mutating the chart.",
         {{"type", "object"},
          {"properties",
           {{"expression", obj("string", "expression sequence")},
            {"context", {{"type", "object"}}}}},
          {"required", nlohmann::json::array({"expression"})}}},
        tool_evaluate_expression);
}

}  // namespace mcp
