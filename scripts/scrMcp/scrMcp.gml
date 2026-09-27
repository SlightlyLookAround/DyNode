/// MCP main-thread bridge and expression handlers.

function mcp_complete(_requestId, _ok, _result, _error = "") {
    DyCore_mcp_complete(json_stringify({
        requestId: _requestId,
        ok: _ok,
        result: is_undefined(_result) ? {} : _result,
        error: _error
    }));
}

function mcp_get_selection_info() {
    var _ids = [];
    var _notes = editor_get_selected_notes();
    for (var i = 0, l = array_length(_notes); i < l; i++) {
        array_push(_ids, _notes[i].noteID);
    }
    return { count: array_length(_ids), noteIDs: _ids };
}

function mcp_bind_expr_symbols(_nprop, _index) {
    expr_init();
    expr_set_var("time", 0)
        .set_getter(method({_nprop: _nprop}, function() { return _nprop.time; }))
        .set_setter(method({_nprop: _nprop}, function(val) { _nprop.time = val; }));
    expr_set_var("pos", 0)
        .set_getter(method({_nprop: _nprop}, function() { return _nprop.position; }))
        .set_setter(method({_nprop: _nprop}, function(val) { _nprop.position = val; }));
    expr_set_var("wid", 0)
        .set_getter(method({_nprop: _nprop}, function() { return _nprop.width; }))
        .set_setter(method({_nprop: _nprop}, function(val) { _nprop.width = val; }));
    expr_set_var("len", 0)
        .set_getter(method({_nprop: _nprop}, function() { return _nprop.lastTime; }))
        .set_setter(method({_nprop: _nprop}, function(val) { _nprop.set_length(val); }));
    expr_set_var("side", 0)
        .set_getter(method({_nprop: _nprop}, function() { return _nprop.side; }))
        .set_setter(method({_nprop: _nprop}, function(val) { _nprop.side = (val % 3 + 3) % 3; }));
    expr_set_var("htime", 0)
        .set_getter(method({_nprop: _nprop}, function() { return _nprop.time; }))
        .set_setter(method({_nprop: _nprop}, function(val) {
            var subTime = _nprop.time + _nprop.lastTime;
            _nprop.time = val;
            _nprop.set_length(subTime - _nprop.time);
        }));
    expr_set_var("etime", 0)
        .set_getter(method({_nprop: _nprop}, function() { return _nprop.time + _nprop.lastTime; }))
        .set_setter(method({_nprop: _nprop}, function(val) {
            var headTime = _nprop.time;
            _nprop.set_length(val - headTime);
            _nprop.time = val - _nprop.lastTime;
        }));
    expr_set_var("index", _index).set_setter(undefined);

    expr_set_var("bpm", 0)
        .set_setter(undefined)
        .set_getter(method({_nprop: _nprop}, function() {
            if (dyc_get_timingpoints_count() == 0) {
                throw "Timing information is not set correctly. BPM cannot be read.";
            }
            return dyc_get_timingpoint_at(_nprop.time).get_bpm();
        }));
    expr_set_var("meter", 0)
        .set_setter(undefined)
        .set_getter(method({_nprop: _nprop}, function() {
            if (dyc_get_timingpoints_count() == 0) {
                throw "Timing information is not set correctly. meter cannot be read.";
            }
            return dyc_get_timingpoint_at(_nprop.time).meter;
        }));
    expr_set_var("tptime", 0)
        .set_setter(undefined)
        .set_getter(method({_nprop: _nprop}, function() {
            if (dyc_get_timingpoints_count() == 0) {
                throw "Timing information is not set correctly. tptime cannot be read.";
            }
            return dyc_get_timingpoint_at(_nprop.time).time;
        }));
    expr_set_var("bar", 0)
        .set_getter(method({_nprop: _nprop}, function() {
            if (dyc_get_timingpoints_count() == 0) {
                throw "Timing information is not set correctly. Bar cannot be read.";
            }
            return time_to_bar_dyn(_nprop.time);
        }))
        .set_setter(method({_nprop: _nprop}, function(val) {
            if (dyc_get_timingpoints_count() == 0) {
                throw "Timing information is not set correctly. Bar cannot be set.";
            }
            var currentBar = time_to_bar_dyn(_nprop.time);
            _nprop.time = time_add_bar_delta_dyn(_nprop.time, val - currentBar);
        }));
    expr_set_var("abar", 0)
        .set_getter(undefined)
        .set_setter(method({_nprop: _nprop}, function(val) {
            if (dyc_get_timingpoints_count() == 0) {
                throw "Timing information is not set correctly. Bar cannot be set.";
            }
            _nprop.time = bar_to_time_dyn(val);
        }));
}

function mcp_note_prop_copy(_nprop) {
    return {
        time: _nprop.time,
        pos: _nprop.position,
        wid: _nprop.width,
        len: _nprop.lastTime,
        side: _nprop.side,
        htime: _nprop.time,
        etime: _nprop.time + _nprop.lastTime
    };
}

function mcp_collect_scope_notes(_scope, _noteIDs) {
    if (_scope == "selection") {
        return editor_get_selected_notes();
    }
    if (_scope == "noteIDs") {
        var _out = [];
        for (var i = 0, l = array_length(_noteIDs); i < l; i++) {
            var _n = dyc_get_note(_noteIDs[i]);
            if (!is_undefined(_n)) array_push(_out, _n);
        }
        return _out;
    }
    var _out = [];
    for (var i = 0, l = DyCore_get_note_count(); i < l; i++) {
        array_push(_out, dyc_get_note_at_index_direct(i));
    }
    return _out;
}

function mcp_apply_expression(_expression, _scope, _noteIDs, _dryRun) {
    var _targets = mcp_collect_scope_notes(_scope, _noteIDs);
    var _applied = 0;
    var _failed = [];
    var _samples = [];

    for (var i = 0, l = array_length(_targets); i < l; i++) {
        var _noteProp = _targets[i];
        if (_noteProp.noteType == 3) continue;
        try {
            var _nprop = _noteProp.copy();
            var _before = mcp_note_prop_copy(_nprop);
            mcp_bind_expr_symbols(_nprop, i);
            var _ok = expr_exec(_expression);
            if (_ok < 0) {
                array_push(_failed, { index: i, noteID: _noteProp.noteID, error: "expression failed" });
                continue;
            }
            if (!_dryRun) {
                dyc_update_note(_nprop, true);
            }
            _applied++;
            if (_dryRun && array_length(_samples) < 3) {
                array_push(_samples, {
                    noteID: _noteProp.noteID,
                    before: _before,
                    after: mcp_note_prop_copy(_nprop)
                });
            }
        } catch (e) {
            array_push(_failed, { index: i, noteID: _noteProp.noteID, error: string(e) });
        }
    }

    if (!_dryRun && _applied > 0) {
        note_sort_all(true);
        operation_merge_last_request(1, OPERATION_TYPE.EXPR);
    }

    return {
        ok: array_length(_failed) == 0,
        applied: _applied,
        failed: _failed,
        dryRun: _dryRun,
        sample: _samples
    };
}

function mcp_evaluate_expression(_expression, _context) {
    var _ctx = is_struct(_context) ? _context : {};
    var _nprop = new sNoteProp({
        time: _ctx[$ "time"] ?? 0,
        side: _ctx[$ "side"] ?? 0,
        width: _ctx[$ "wid"] ?? _ctx[$ "width"] ?? 1,
        position: _ctx[$ "pos"] ?? _ctx[$ "position"] ?? 2.5,
        lastTime: _ctx[$ "len"] ?? _ctx[$ "lastTime"] ?? 0
    });
    mcp_bind_expr_symbols(_nprop, _ctx[$ "index"] ?? 0);
    try {
        var _seqs = string_split(_expression, ";", true);
        var _last = 0;
        for (var i = 0, l = array_length(_seqs); i < l; i++) {
            var _seg = string_trim(_seqs[i]);
            if (_seg == "") continue;
            var _res = expr_eval(_seg);
            _last = is_struct(_res) ? _res.get_value() : _res;
        }
        return {
            ok: true,
            values: mcp_note_prop_copy(_nprop),
            final: _last
        };
    } catch (e) {
        return { ok: false, error: string(e) };
    }
}

function mcp_insert_notes(_notes) {
    var _created = [];
    var _failed = [];
    for (var i = 0, l = array_length(_notes); i < l; i++) {
        try {
            var _src = _notes[i];
            var _prop = new sNoteProp({
                time: _src[$ "time"] ?? 0,
                side: _src[$ "side"] ?? 0,
                width: _src[$ "width"] ?? 1,
                position: _src[$ "position"] ?? 0,
                lastTime: _src[$ "lastTime"] ?? _src[$ "length"] ?? 0,
                noteType: _src[$ "type"] ?? _src[$ "noteType"] ?? 0,
                noteID: _src[$ "noteID"] ?? "",
                subNoteID: _src[$ "subNoteID"] ?? "",
                beginTime: _src[$ "beginTime"] ?? 0
            });
            if (_prop.noteID == "") _prop.noteID = note_generate_id();
            dyc_create_note(_prop, false);
            array_push(_created, _prop.noteID);
        } catch (e) {
            array_push(_failed, { index: i, error: string(e) });
        }
    }
    note_sort_all(true);
    return { ok: array_length(_failed) == 0, created: _created, count: array_length(_created), failed: _failed };
}

function mcp_update_notes(_updates) {
    var _updated = [];
    var _failed = [];
    for (var i = 0, l = array_length(_updates); i < l; i++) {
        try {
            var _u = _updates[i];
            var _id = _u[$ "noteID"] ?? "";
            if (_id == "" || !dyc_note_exists(_id)) {
                array_push(_failed, { noteID: _id, error: "note not found" });
                continue;
            }
            var _prop = dyc_get_note(_id);
            if (!is_undefined(_u[$ "time"])) _prop.time = _u[$ "time"];
            if (!is_undefined(_u[$ "width"])) _prop.width = _u[$ "width"];
            if (!is_undefined(_u[$ "position"])) _prop.position = _u[$ "position"];
            if (!is_undefined(_u[$ "side"])) _prop.side = _u[$ "side"];
            if (!is_undefined(_u[$ "type"])) _prop.noteType = _u[$ "type"];
            if (!is_undefined(_u[$ "lastTime"])) _prop.lastTime = _u[$ "lastTime"];
            if (!is_undefined(_u[$ "beginTime"])) _prop.beginTime = _u[$ "beginTime"];
            dyc_update_note(_prop, false);
            array_push(_updated, _id);
        } catch (e) {
            array_push(_failed, { index: i, error: string(e) });
        }
    }
    note_sort_all(true);
    return { ok: array_length(_failed) == 0, updated: _updated, failed: _failed };
}

function mcp_delete_notes(_payload) {
    var _deleted = [];
    var _ids = _payload[$ "noteIDs"];
    if (is_array(_ids)) {
        for (var i = 0, l = array_length(_ids); i < l; i++) {
            var _id = _ids[i];
            if (dyc_note_exists(_id)) {
                note_delete(_id, false);
                array_push(_deleted, _id);
            }
        }
        return { ok: true, deleted: array_length(_deleted), noteIDs: _deleted };
    }
    if (!(_payload[$ "confirm"] ?? false)) {
        return { ok: false, error: "filter delete requires confirm:true" };
    }
    var _f = _payload[$ "filter"] ?? {};
    var _tmin = _f[$ "timeMin"] ?? -1000000000;
    var _tmax = _f[$ "timeMax"] ?? 1000000000;
    var _hasSide = !is_undefined(_f[$ "side"]);
    var _hasType = !is_undefined(_f[$ "type"]);
    var _targets = [];
    for (var i = 0, l = DyCore_get_note_count(); i < l; i++) {
        var _n = dyc_get_note_at_index_direct(i);
        if (_n.noteType == 3) continue;
        if (_n.time < _tmin || _n.time > _tmax) continue;
        if (_hasSide && _n.side != _f[$ "side"]) continue;
        if (_hasType && _n.noteType != _f[$ "type"]) continue;
        array_push(_targets, _n.noteID);
    }
    for (var i = 0, l = array_length(_targets); i < l; i++) {
        note_delete(_targets[i], false);
        array_push(_deleted, _targets[i]);
    }
    note_sort_all(true);
    return { ok: true, deleted: array_length(_deleted), noteIDs: _deleted };
}

function mcp_handle_job(_job) {
    var _kind = _job.kind;
    var _payload = _job.payload;
    var _requestId = _job.requestId;
    try {
        switch (_kind) {
            case "get_selection":
                mcp_complete(_requestId, true, mcp_get_selection_info());
                break;
            case "apply_expression":
                var _res = mcp_apply_expression(
                    _payload[$ "expression"],
                    _payload[$ "scope"] ?? "selection",
                    _payload[$ "noteIDs"] ?? [],
                    _payload[$ "dryRun"] ?? false
                );
                mcp_complete(_requestId, true, _res);
                break;
            case "insert_notes":
                mcp_complete(_requestId, true, mcp_insert_notes(_payload[$ "notes"] ?? []));
                break;
            case "update_notes":
                mcp_complete(_requestId, true, mcp_update_notes(_payload[$ "updates"] ?? []));
                break;
            case "delete_notes":
                mcp_complete(_requestId, true, mcp_delete_notes(_payload));
                break;
            case "evaluate_expression":
                var _res = mcp_evaluate_expression(
                    _payload[$ "expression"],
                    _payload[$ "context"] ?? {}
                );
                mcp_complete(_requestId, true, _res);
                break;
            default:
                mcp_complete(_requestId, false, {}, "unknown job kind: " + string(_kind));
                break;
        }
    } catch (e) {
        mcp_complete(_requestId, false, {}, string(e));
    }
}

function mcp_step() {
    if (!DyCore_mcp_is_running()) return;
    var _jobsJson = DyCore_mcp_take_jobs();
    if (_jobsJson == "" || _jobsJson == "[]") return;
    try {
        var _jobs = json_parse(_jobsJson);
        for (var i = 0, l = array_length(_jobs); i < l; i++) {
            mcp_handle_job(_jobs[i]);
        }
    } catch (e) {
        show_debug_message("mcp_step error: " + string(e));
    }
}

function mcp_prefs_path() {
    return working_directory + "mcp_prefs.json";
}

function mcp_prefs_load() {
    var _prefs = { defaultStart: false, port: 8765 };
    try {
        var _path = mcp_prefs_path();
        if (file_exists(_path)) {
            var _buf = buffer_load(_path);
            if (_buf != -1) {
                var _text = buffer_read(_buf, buffer_text);
                buffer_delete(_buf);
                var _j = json_parse(_text);
                if (is_struct(_j)) {
                    if (!is_undefined(_j.defaultStart)) _prefs.defaultStart = _j.defaultStart;
                    if (!is_undefined(_j.port)) _prefs.port = _j.port;
                }
            }
        }
    } catch (e) {
        show_debug_message("mcp_prefs_load: " + string(e));
    }
    return _prefs;
}

function mcp_prefs_save(_prefs) {
    try {
        var _buf = buffer_create(256, buffer_grow, 1);
        buffer_write(_buf, buffer_text, json_stringify(_prefs));
        buffer_save(_buf, mcp_prefs_path());
        buffer_delete(_buf);
    } catch (e) {
        show_debug_message("mcp_prefs_save: " + string(e));
    }
}

function mcp_save_info_file(_info) {
    try {
        var _path = working_directory + "mcp_info.json";
        var _buf = buffer_create(512, buffer_grow, 1);
        buffer_write(_buf, buffer_text, json_stringify(_info));
        buffer_save(_buf, _path);
        buffer_delete(_buf);
    } catch (e) {
        show_debug_message("mcp_save_info_file: " + string(e));
    }
}
function mcp_start_if_enabled() {
    // Launch auto-start is OFF by default; enable via console: mcpserv default on
    var _prefs = mcp_prefs_load();
    if (!_prefs.defaultStart) {
        show_debug_message("MCP auto-start disabled (mcpserv default on to enable).");
        return undefined;
    }
    var _port = _prefs.port;
    if (variable_global_exists("mcpPort")) _port = global.mcpPort;
    var _info = json_parse(DyCore_mcp_start(_port));
    if (_info[$ "ok"]) {
        var _url = string(_info[$ "url"]);
        var _token = string(_info[$ "token"] ?? "");
        announcement_play("MCP ready: " + _url);
        show_debug_message("MCP INFO " + json_stringify(_info));
        // Persist token so external tools can read it.
        try {
            var _path = working_directory + "mcp_info.json";
            var _buf = buffer_create(1024, buffer_grow, 1);
            buffer_write(_buf, buffer_text, json_stringify(_info));
            buffer_save(_buf, _path);
            buffer_delete(_buf);
            show_debug_message("MCP token saved: " + _path);
        } catch (e) {
            show_debug_message("MCP token save failed: " + string(e));
        }
    } else {
        announcement_error("MCP start failed: " + string(_info[$ "error"] ?? "unknown"));
        show_debug_message("MCP start failed: " + json_stringify(_info));
    }
    return _info;
}

function mcp_stop() {
    return json_parse(DyCore_mcp_stop());
}
