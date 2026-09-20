/// @description KeyBindManager & custom keybind query API.
/// Design doc: keybinds-design.md
/// - Action registry entries are declared in scrKeybindRegistry.gml
/// - Final bindings = built-in defaults -> preset overrides -> user overrides (config.json "keybinds")
/// - Query API: bind_down() / bind() / bind_axis() / bind_choice() / bind_chord()
///   (semantics mirror the old keycheck_* wrappers, see keybinds-design.md 9.1)

#macro KBT_PRESS 0      // edge trigger
#macro KBT_HOLD 1       // hold (also used for hold-based axes with pos/neg)
#macro KBT_AXIS 2       // two-key difference, edge trigger
#macro KBT_CHOICE 3     // one key per discrete value
#macro KBT_CHORD 4      // multiple keys held at once

#macro KEYBIND_CONFIG_VERSION 1

// ---------------- Key name conversion ----------------
// Pure condition-based lookups (no struct lookup tables): vk <-> name mapping
// must be reliable in every runtime, this is what the panel displays.

function keybind_name_to_vk(_name) {
    var _n = string_upper(string_trim(_name));
    if(_n == "") return -1;

    // Single letter / digit
    if(string_length(_n) == 1) {
        var _o = ord(_n);
        if((_o >= ord("A") && _o <= ord("Z")) || (_o >= 48 && _o <= 57))
            return _o;
    }

    // Numpad0..Numpad9
    if(string_length(_n) == 7 && string_pos("NUMPAD", _n) == 1) {
        var _d = string_char_at(_n, 7);
        if(_d >= "0" && _d <= "9")
            return vk_numpad0 + real(_d);
    }

    // F1..F12
    if(string_char_at(_n, 1) == "F" && string_length(_n) > 1) {
        var _num = string_delete(_n, 1, 1);
        if(regex_is_integer(_num)) {
            var _f = real(_num);
            if(_f >= 1 && _f <= 12)
                return vk_f1 + (_f - 1);
        }
    }

    switch(_n) {
        case "ESCAPE": case "ESC": return vk_escape;
        case "ENTER": case "RETURN": return vk_enter;
        case "BACKSPACE": return vk_backspace;
        case "SPACE": return vk_space;
        case "TAB": return vk_tab;
        case "DELETE": case "DEL": return vk_delete;
        case "INSERT": return vk_insert;
        case "HOME": return vk_home;
        case "END": return vk_end;
        case "PAGEUP": return vk_pageup;
        case "PAGEDOWN": return vk_pagedown;
        case "UP": return vk_up;
        case "DOWN": return vk_down;
        case "LEFT": return vk_left;
        case "RIGHT": return vk_right;
        case "GRAVE": case "BACKTICK": case "TILDE": case "`": return 192;
        case "MINUS": case "-": return 189;
        case "EQUAL": case "PLUS": case "=": return 187;
        case "COMMA": case ",": return 188;
        case "PERIOD": case "DOT": case ".": return 190;
        case "SLASH": case "/": return 191;
        case "SEMICOLON": case ";": return 186;
        case "APOSTROPHE": case "'": return 222;
        case "LBRACKET": case "[": return 219;
        case "RBRACKET": case "]": return 221;
        case "BACKSLASH": case "\\": return 220;
    }

    // Raw virtual-key fallback: "#112" or "112"
    if(string_char_at(_n, 1) == "#")
        _n = string_delete(_n, 1, 1);
    if(regex_is_integer(_n)) {
        var _v = real(_n);
        if(_v >= 8 && _v <= 255) return _v;
    }
    return -1;
}

function keybind_vk_to_name(_vk) {
    if(_vk >= ord("A") && _vk <= ord("Z")) return chr(_vk);
    if(_vk >= 48 && _vk <= 57) return chr(_vk);
    if(_vk >= vk_numpad0 && _vk <= vk_numpad9)
        return "Numpad" + string(_vk - vk_numpad0);
    if(_vk >= vk_f1 && _vk <= vk_f12)
        return "F" + string(_vk - vk_f1 + 1);
    switch(_vk) {
        case vk_escape: return "Escape";
        case vk_enter: return "Enter";
        case vk_backspace: return "Backspace";
        case vk_space: return "Space";
        case vk_tab: return "Tab";
        case vk_delete: return "Delete";
        case vk_insert: return "Insert";
        case vk_home: return "Home";
        case vk_end: return "End";
        case vk_pageup: return "PageUp";
        case vk_pagedown: return "PageDown";
        case vk_up: return "Up";
        case vk_down: return "Down";
        case vk_left: return "Left";
        case vk_right: return "Right";
        case 192: return "`";
        case 189: return "-";
        case 187: return "=";
        case 188: return ",";
        case 190: return ".";
        case 191: return "/";
        case 186: return ";";
        case 222: return "'";
        case 219: return "[";
        case 221: return "]";
        case 220: return "\\";
    }
    return "#" + string(_vk);
}

/// "Ctrl+Shift+Z" -> { vk, ctrl, shift, alt }; undefined when unparsable.
function keybind_parse_key(_str) {
    if(!is_string(_str)) return undefined;
    var _parts = string_split(string_trim(_str), "+");
    var _ctrl = false, _shift = false, _alt = false, _vk = -1;
    for(var i=0; i<array_length(_parts); i++) {
        var _p = string_upper(string_trim(_parts[i]));
        if(_p == "") continue;
        if(_p == "CTRL" || _p == "CONTROL") _ctrl = true;
        else if(_p == "SHIFT") _shift = true;
        else if(_p == "ALT") _alt = true;
        else {
            if(_vk != -1) return undefined;
            _vk = keybind_name_to_vk(_p);
            if(_vk == -1) return undefined;
        }
    }
    if(_vk == -1) return undefined;
    return { vk: _vk, ctrl: _ctrl, shift: _shift, alt: _alt };
}

function keybind_key_to_string(_key) {
    if(!is_struct(_key)) return "";
    var _s = "";
    if(_key.ctrl) _s += "Ctrl+";
    if(_key.shift) _s += "Shift+";
    if(_key.alt) _s += "Alt+";
    return _s + keybind_vk_to_name(_key.vk);
}

function _keybind_key_sig(_key) {
    return string(_key.vk) + "|" + string(_key.ctrl) + "|" + string(_key.shift) + "|" + string(_key.alt);
}

// ---------------- Action copy / parse helpers ----------------

function _keybind_copy_keys(_keys) {
    var _out = [];
    for(var i=0; i<array_length(_keys); i++)
        _out[i] = { vk: _keys[i].vk, ctrl: _keys[i].ctrl, shift: _keys[i].shift, alt: _keys[i].alt };
    return _out;
}

function _keybind_copy_action(_a) {
    var _c = {
        id: _a.id,
        context: _a.context,
        type: _a.type,
        reserved: _a.reserved,
        keys: _keybind_copy_keys(_a.keys),
        pos: _keybind_copy_keys(_a.pos),
        neg: _keybind_copy_keys(_a.neg),
        choices: [],
    };
    for(var i=0; i<array_length(_a.choices); i++)
        _c.choices[i] = _keybind_copy_keys(_a.choices[i]);
    return _c;
}

/// Normalizes a key spec (vk | string | array of those) into key structs.
function _keybind_key_list(_keys, _mods = undefined) {
    var _out = [];
    if(_keys == undefined) return _out;
    if(!is_array(_keys)) _keys = [_keys];
    for(var i=0; i<array_length(_keys); i++) {
        var _vk = is_string(_keys[i]) ? keybind_name_to_vk(_keys[i]) : _keys[i];
        if(_vk == -1 || _vk == undefined) continue;
        var _k = { vk: _vk, ctrl: false, shift: false, alt: false };
        if(_mods != undefined) {
            if(variable_struct_exists(_mods, "ctrl") && _mods.ctrl) _k.ctrl = true;
            if(variable_struct_exists(_mods, "shift") && _mods.shift) _k.shift = true;
            if(variable_struct_exists(_mods, "alt") && _mods.alt) _k.alt = true;
        }
        array_push(_out, _k);
    }
    return _out;
}

function _keybind_parse_key_array(_raw) {
    var _out = [];
    if(is_string(_raw)) {
        var _k = keybind_parse_key(_raw);
        if(_k == undefined) return undefined;
        return [_k];
    }
    if(!is_array(_raw)) return undefined;
    for(var i=0; i<array_length(_raw); i++) {
        var _k = keybind_parse_key(_raw[i]);
        if(_k == undefined) return undefined;
        array_push(_out, _k);
    }
    if(array_length(_out) == 0) return undefined;
    return _out;
}

/// Applies a serialized override ("Ctrl+Z" / ["Del","Backspace"] / {pos,neg} / choice array)
/// onto an action struct. Returns whether the raw value was valid for the action's type.
function _keybind_apply_raw(_act, _raw) {
    // Explicit unbind token
    if(is_string(_raw) && string_upper(string_trim(_raw)) == "NONE") {
        if(_act.type == KBT_CHOICE) return false;
        _act.keys = [];
        _act.pos = [];
        _act.neg = [];
        return true;
    }

    switch(_act.type) {
        case KBT_CHOICE:
            if(!is_array(_raw)) return false;
            if(array_length(_raw) != array_length(_act.choices)) return false;
            var _choices = [];
            for(var i=0; i<array_length(_raw); i++) {
                var _slot = _keybind_parse_key_array(_raw[i]);
                if(_slot == undefined) return false;
                _choices[i] = _slot;
            }
            _act.choices = _choices;
            return true;

        case KBT_AXIS:
            if(!is_struct(_raw)) return false;
            var _ap = _axis_raw_side(_raw, "pos");
            var _an = _axis_raw_side(_raw, "neg");
            if(_ap == undefined || _an == undefined) return false;
            _act.pos = _ap;
            _act.neg = _an;
            return true;

        case KBT_HOLD:
            // Raw shape decides the binding form: {pos, neg} struct for axis-style holds
            // (main_time_scroll etc.), key strings for plain holds. Whichever form is not
            // set gets cleared so the effective binding stays unambiguous.
            if(is_struct(_raw)) {
                var _hp = _axis_raw_side(_raw, "pos");
                var _hn = _axis_raw_side(_raw, "neg");
                if(_hp == undefined || _hn == undefined) return false;
                _act.pos = _hp;
                _act.neg = _hn;
                _act.keys = [];
                return true;
            }
            var _hkeys = _keybind_parse_key_array(_raw);
            if(_hkeys == undefined) return false;
            _act.keys = _hkeys;
            _act.pos = [];
            _act.neg = [];
            return true;

        default:    // KBT_PRESS, KBT_CHORD
            var _pkeys = _keybind_parse_key_array(_raw);
            if(_pkeys == undefined) return false;
            _act.keys = _pkeys;
            return true;
    }
}

function _axis_raw_side(_raw, _side) {
    if(!variable_struct_exists(_raw, _side)) return undefined;
    return _keybind_parse_key_array(variable_struct_get(_raw, _side));
}

function _keybind_collect_action_keys(_act, _out) {
    for(var i=0; i<array_length(_act.keys); i++) array_push(_out, _act.keys[i]);
    for(var i=0; i<array_length(_act.pos); i++) array_push(_out, _act.pos[i]);
    for(var i=0; i<array_length(_act.neg); i++) array_push(_out, _act.neg[i]);
    for(var c=0; c<array_length(_act.choices); c++)
        for(var i=0; i<array_length(_act.choices[c]); i++)
            array_push(_out, _act.choices[c][i]);
}

/// Conflict signatures for an action.
/// Chords are one composite signature (O+P does not collide with plain O);
/// axis/hold pos/neg and choice options stay independent slots.
function _keybind_action_signatures(_act) {
    var _out = [];
    if(_act.type == KBT_CHORD) {
        if(array_length(_act.keys) == 0) return _out;
        var _parts = [];
        for(var i=0; i<array_length(_act.keys); i++)
            array_push(_parts, _keybind_key_sig(_act.keys[i]));
        array_sort(_parts, true);
        array_push(_out, "CHORD:" + string_join_ext("+", _parts));
        return _out;
    }
    if(_act.type == KBT_CHOICE) {
        for(var c=0; c<array_length(_act.choices); c++) {
            for(var i=0; i<array_length(_act.choices[c]); i++)
                array_push(_out, _keybind_key_sig(_act.choices[c][i]));
        }
        return _out;
    }
    for(var i=0; i<array_length(_act.keys); i++)
        array_push(_out, _keybind_key_sig(_act.keys[i]));
    for(var i=0; i<array_length(_act.pos); i++)
        array_push(_out, _keybind_key_sig(_act.pos[i]));
    for(var i=0; i<array_length(_act.neg); i++)
        array_push(_out, _keybind_key_sig(_act.neg[i]));
    return _out;
}

function _keybind_action_has_key(_act, _sig) {
    var _sigs = _keybind_action_signatures(_act);
    for(var i=0; i<array_length(_sigs); i++)
        if(_sigs[i] == _sig) return true;
    return false;
}

/// Serializes an action's effective binding back to the raw config form.
function _keybind_normalize_raw(_act) {
    var _isAxis = array_length(_act.pos) > 0 || array_length(_act.neg) > 0;

    if(_act.type == KBT_CHOICE) {
        var _out = [];
        for(var i=0; i<array_length(_act.choices); i++)
            _out[i] = _keybind_keys_raw(_act.choices[i]);
        return _out;
    }
    if(_isAxis)
        return { pos: _keybind_keys_raw(_act.pos), neg: _keybind_keys_raw(_act.neg) };
    return _keybind_keys_raw(_act.keys);
}

function _keybind_keys_raw(_keys) {
    if(array_length(_keys) == 1) return keybind_key_to_string(_keys[0]);
    var _out = [];
    for(var i=0; i<array_length(_keys); i++)
        array_push(_out, keybind_key_to_string(_keys[i]));
    return _out;
}

// ---------------- KeyBindManager ----------------

function KeyBindManager() constructor {
    actions = {};       // id -> action struct (effective bindings)
    defaults = {};      // id -> action struct (registry defaults, pristine)
    presetLayer = {};   // id -> action struct (defaults + preset applied)
    order = [];         // registration order (conflict resolution: first wins)
    presets = {};       // name -> { bindings: raw override struct }
    presetOrder = [];
    preset = "dynode";
    userBindings = {};  // id -> raw serialized user override (kept for config.json)

    // Per-frame key state cache (keyed on global.frameCurrentTime)
    cacheFrame = -1;
    cacheVks = [];
    cachePressed = {};
    cacheHeld = {};
    cachePanelOpen = false;

    static register = function(_act) {
        if(variable_struct_exists(actions, _act.id))
            throw "Duplicate keybind action id: " + _act.id;
        actions[$ _act.id] = _act;
        defaults[$ _act.id] = _keybind_copy_action(_act);
        array_push(order, _act.id);
        _rebuild_cache_list();
    }

    static get = function(_id) {
        if(!variable_struct_exists(actions, _id)) return undefined;
        return actions[$ _id];
    }

    static _rebuild_cache_list = function() {
        var _set = {};
        var _vk = [];
        for(var i=0; i<array_length(order); i++) {
            var _a = actions[$ order[i]];
            _collect_vks(_a.keys, _set, _vk);
            _collect_vks(_a.pos, _set, _vk);
            _collect_vks(_a.neg, _set, _vk);
            for(var c=0; c<array_length(_a.choices); c++)
                _collect_vks(_a.choices[c], _set, _vk);
        }
        cacheVks = _vk;
        cacheFrame = -1;    // force refresh next query
    }

    static _collect_vks = function(_keys, _set, _list) {
        for(var i=0; i<array_length(_keys); i++) {
            var _k = string(_keys[i].vk);
            if(!variable_struct_exists(_set, _k)) {
                _set[$ _k] = true;
                array_push(_list, _keys[i].vk);
            }
        }
    }

    /// Refreshes the per-frame key state cache once per frame (keyboard state is
    /// stable within a frame, so all queries are pure table lookups afterwards).
    static _ensure_cache = function() {
        if(cacheFrame == global.frameCurrentTime) return;
        cacheFrame = global.frameCurrentTime;
        // The keybind panel and the toggle-mode overlay are both modal: while
        // either is open, every game binding is suppressed (Esc, Backspace,
        // chords, ...) so panel/overlay keys never leak through.
        cachePanelOpen = instance_exists(objKeybindPanel)
            || instance_exists(objColorTimeline)
            || keybind_overlay_blocks_input();
        cachePressed = {};
        cacheHeld = {};
        for(var i=0; i<array_length(cacheVks); i++) {
            var _k = string(cacheVks[i]);
            cachePressed[$ _k] = keyboard_check_pressed(cacheVks[i]);
            cacheHeld[$ _k] = keyboard_check(cacheVks[i]);
        }
    }

    static _mods_match = function(_key) {
        if(_key.ctrl != ctrl_ishold()) return false;
        if(_key.shift != shift_ishold()) return false;
        if(_key.alt != alt_ishold()) return false;
        return true;
    }

    /// Mirrors keycheck_down / keycheck_down_ctrl:
    /// - modifier-less bindings are blocked while the console input group is focused
    /// - modifier bindings skip the input group check (console Ctrl+V paste relies on it)
    /// - a triggered modifier binding locks the direct state (prevents cross-frame repeats)
    static _key_down = function(_key) {
        if(cachePanelOpen) return false;
        if(global.__InputManager.is_frozen()) return false;
        if(!_mods_match(_key)) return false;
        var _hasMods = _key.ctrl || _key.shift || _key.alt;
        if(!_hasMods && !input_group_validate()) return false;
        var _r = cachePressed[$ string(_key.vk)];
        if(_hasMods && _r) input_direct_state_lock();
        return _r;
    }

    /// Mirrors keycheck / keycheck_ctrl (hold semantics, direct state lock aware).
    static _key_hold = function(_key) {
        if(cachePanelOpen) return false;
        if(global.__InputManager.is_frozen()) return false;
        if(input_direct_state_lock_get()) return false;
        if(!_mods_match(_key)) return false;
        var _hasMods = _key.ctrl || _key.shift || _key.alt;
        if(!_hasMods && !input_group_validate()) return false;
        return cacheHeld[$ string(_key.vk)];
    }

    static load_defaults = function() {
        for(var i=0; i<array_length(order); i++) {
            var _id = order[i];
            actions[$ _id] = _keybind_copy_action(defaults[$ _id]);
        }
        _rebuild_cache_list();
    }

    /// Resets effective bindings to defaults, applies the named preset on top and
    /// snapshots the result (used as the revert target for user overrides).
    static apply_preset = function(_name) {
        load_defaults();
        if(variable_struct_exists(presets, _name)) {
            var _ov = presets[$ _name].bindings;
            var _names = variable_struct_get_names(_ov);
            for(var i=0; i<array_length(_names); i++) {
                var _id = _names[i];
                if(!variable_struct_exists(actions, _id)) continue;
                if(!_keybind_apply_raw(actions[$ _id], variable_struct_get(_ov, _id)))
                    show_debug_message_safe("Keybinds: preset '" + _name + "' has an invalid entry for '" + _id + "'.");
            }
        }
        preset = _name;
        presetLayer = {};
        for(var i=0; i<array_length(order); i++)
            presetLayer[$ order[i]] = _keybind_copy_action(actions[$ order[i]]);
        _rebuild_cache_list();
    }

    static load_from_config = function(_cfg) {
        userBindings = {};
        if(!is_struct(_cfg)) {
            apply_preset("dynode");
            return;
        }

        var _ver = variable_struct_exists(_cfg, "version") ? _cfg.version : 1;
        if(_ver > KEYBIND_CONFIG_VERSION) {
            show_debug_message_safe("Keybinds: config version " + string(_ver)
                + " is newer than supported (" + string(KEYBIND_CONFIG_VERSION) + "); defaults restored.");
            apply_preset("dynode");
            return;
        }

        var _preset = variable_struct_exists(_cfg, "preset") && is_string(_cfg.preset) ? _cfg.preset : "dynode";
        if(!variable_struct_exists(presets, _preset)) _preset = "dynode";
        apply_preset(_preset);

        if(variable_struct_exists(_cfg, "bindings") && is_struct(_cfg.bindings)) {
            var _b = _cfg.bindings;
            var _names = variable_struct_get_names(_b);
            for(var i=0; i<array_length(_names); i++) {
                var _id = _names[i];
                var _raw = variable_struct_get(_b, _id);
                if(!variable_struct_exists(actions, _id)) {
                    show_debug_message_safe("Keybinds: unknown action '" + _id + "' ignored.");
                    continue;
                }
                if(!_keybind_apply_raw(actions[$ _id], _raw)) {
                    show_debug_message_safe("Keybinds: invalid binding for '" + _id + "' ignored.");
                    continue;
                }
                userBindings[$ _id] = _raw;
            }
        }

        _resolve_conflicts();
        _rebuild_cache_list();
    }

    static serialize = function() {
        var _b = {};
        var _names = variable_struct_get_names(userBindings);
        for(var i=0; i<array_length(_names); i++)
            _b[$ _names[i]] = userBindings[$ _names[i]];
        return {
            version: KEYBIND_CONFIG_VERSION,
            preset: preset,
            bindings: _b
        };
    }

    /// Same-context exact-binding duplicates among user overrides: the later registered
    /// action reverts to its preset-layer binding and the override is dropped.
    static _resolve_conflicts = function() {
        var _map = {};
        for(var i=0; i<array_length(order); i++) {
            var _id = order[i];
            if(!variable_struct_exists(userBindings, _id)) continue;
            var _a = actions[$ _id];
            var _sigs = _keybind_action_signatures(_a);
            for(var j=0; j<array_length(_sigs); j++) {
                var _sig = _sigs[j] + "@" + _a.context;
                if(variable_struct_exists(_map, _sig)) {
                    show_debug_message_safe("Keybinds: '" + _id + "' conflicts with '"
                        + _map[$ _sig] + "' (same key in context '" + _a.context + "'); reverted to preset binding.");
                    _revert_to_preset(_id);
                    break;
                }
                _map[$ _sig] = _id;
            }
        }
    }

    static _revert_to_preset = function(_id) {
        if(!variable_struct_exists(presetLayer, _id)) return;
        actions[$ _id] = _keybind_copy_action(presetLayer[$ _id]);
        var _nb = {};
        var _names = variable_struct_get_names(userBindings);
        for(var i=0; i<array_length(_names); i++)
            if(_names[i] != _id) _nb[$ _names[i]] = userBindings[$ _names[i]];
        userBindings = _nb;
    }
}

function keybind_manager_init() {
    global.__KeyBindManager = new KeyBindManager();
}

// ---------------- Registration API (used by scrKeybindRegistry) ----------------

function keybind_register(_id, _context, _type, _keys, _mods = undefined, _opts = undefined) {
    var _act = {
        id: _id,
        context: _context,
        type: _type,
        reserved: false,
        keys: _keybind_key_list(_keys, _mods),
        pos: [],
        neg: [],
        choices: [],
    };
    if(_opts != undefined && variable_struct_exists(_opts, "reserved"))
        _act.reserved = _opts.reserved;
    global.__KeyBindManager.register(_act);
}

function keybind_register_axis(_id, _context, _pos, _neg, _mods = undefined, _opts = undefined) {
    keybind_register(_id, _context, KBT_AXIS, undefined, _mods, _opts);
    var _act = global.__KeyBindManager.get(_id);
    _act.pos = _keybind_key_list(_pos, _mods);
    _act.neg = _keybind_key_list(_neg, _mods);
    global.__KeyBindManager.defaults[$ _id].pos = _keybind_copy_keys(_act.pos);
    global.__KeyBindManager.defaults[$ _id].neg = _keybind_copy_keys(_act.neg);
    global.__KeyBindManager._rebuild_cache_list();
}

function keybind_register_hold_axis(_id, _context, _pos, _neg, _mods = undefined, _opts = undefined) {
    keybind_register(_id, _context, KBT_HOLD, undefined, _mods, _opts);
    var _act = global.__KeyBindManager.get(_id);
    _act.pos = _keybind_key_list(_pos, _mods);
    _act.neg = _keybind_key_list(_neg, _mods);
    global.__KeyBindManager.defaults[$ _id].pos = _keybind_copy_keys(_act.pos);
    global.__KeyBindManager.defaults[$ _id].neg = _keybind_copy_keys(_act.neg);
    global.__KeyBindManager._rebuild_cache_list();
}

function keybind_register_choice(_id, _context, _choices, _mods = undefined, _opts = undefined) {
    keybind_register(_id, _context, KBT_CHOICE, undefined, _mods, _opts);
    var _act = global.__KeyBindManager.get(_id);
    for(var i=0; i<array_length(_choices); i++)
        _act.choices[i] = _keybind_key_list(_choices[i], _mods);
    global.__KeyBindManager.defaults[$ _id].choices = [];
    for(var i=0; i<array_length(_act.choices); i++)
        global.__KeyBindManager.defaults[$ _id].choices[i] = _keybind_copy_keys(_act.choices[i]);
    global.__KeyBindManager._rebuild_cache_list();
}

function keybind_register_chord(_id, _context, _keys, _opts = undefined) {
    keybind_register(_id, _context, KBT_CHORD, _keys, undefined, _opts);
}

function keybind_preset_register(_name, _bindings) {
    var _m = global.__KeyBindManager;
    _m.presets[$ _name] = { bindings: _bindings };
    array_push(_m.presetOrder, _name);
}

// ---------------- Query API ----------------

function bind_down(_id) {
    var _m = global.__KeyBindManager;
    var _a = _m.get(_id);
    if(_a == undefined || _a.type != KBT_PRESS) return false;
    _m._ensure_cache();
    for(var i=0; i<array_length(_a.keys); i++)
        if(_m._key_down(_a.keys[i])) return true;
    return false;
}

function bind(_id) {
    var _m = global.__KeyBindManager;
    var _a = _m.get(_id);
    if(_a == undefined || _a.type != KBT_HOLD) return false;
    _m._ensure_cache();
    for(var i=0; i<array_length(_a.keys); i++)
        if(_m._key_hold(_a.keys[i])) return true;
    return false;
}

/// Two-key difference. KBT_AXIS actions sample press edges (W/S, Q/E, `-`/`=`);
/// KBT_HOLD actions with pos/neg slots sample held state (D/A time scrolling).
function bind_axis(_id) {
    var _m = global.__KeyBindManager;
    var _a = _m.get(_id);
    if(_a == undefined) return 0;
    if(_a.type != KBT_AXIS && _a.type != KBT_HOLD) return 0;
    if(array_length(_a.pos) == 0 && array_length(_a.neg) == 0) return 0;
    _m._ensure_cache();

    var _edge = _a.type == KBT_AXIS;
    var _p = 0;
    for(var i=0; i<array_length(_a.pos); i++) {
        if(_edge ? _m._key_down(_a.pos[i]) : _m._key_hold(_a.pos[i])) {
            _p = 1;
            break;
        }
    }
    var _n = 0;
    for(var i=0; i<array_length(_a.neg); i++) {
        if(_edge ? _m._key_down(_a.neg[i]) : _m._key_hold(_a.neg[i])) {
            _n = 1;
            break;
        }
    }
    return _p - _n;
}

/// Discrete choice: _n is 1-based (bind_choice("editor_mode", 1) checks the "1" slot).
function bind_choice(_id, _n) {
    var _m = global.__KeyBindManager;
    var _a = _m.get(_id);
    if(_a == undefined || _a.type != KBT_CHOICE) return false;
    if(_n < 1 || _n > array_length(_a.choices)) return false;
    _m._ensure_cache();
    var _slot = _a.choices[_n - 1];
    for(var i=0; i<array_length(_slot); i++)
        if(_m._key_down(_slot[i])) return true;
    return false;
}

function bind_chord(_id) {
    var _m = global.__KeyBindManager;
    var _a = _m.get(_id);
    if(_a == undefined || _a.type != KBT_CHORD) return false;
    if(array_length(_a.keys) == 0) return false;
    _m._ensure_cache();
    for(var i=0; i<array_length(_a.keys); i++)
        if(!_m._key_hold(_a.keys[i])) return false;
    return true;
}

// ---------------- Editing / display helpers (panel, console) ----------------

/// Prefixes a string with the CJK font tag when it contains CJK glyphs.
/// scribble's default font (mSpaceMono) has no CJK glyphs; without the tag
/// every CJK character renders as "?".
function keybind_text_cjk(_str) {
    if(has_cjk(_str)) return cjk_prefix() + _str;
    return _str;
}

/// Text scale for panel/overlay drawing: CJK (30px noto) needs a smaller scale
/// than the latin mono font to fit the same row height.
function keybind_text_scale(_str) {
    return has_cjk(_str) ? 0.55 : 0.75;
}

function keybind_action_exists(_id) {
    return variable_struct_exists(global.__KeyBindManager.actions, _id);
}

function keybind_get_action(_id) {
    return global.__KeyBindManager.get(_id);
}

function keybind_action_ids() {
    return global.__KeyBindManager.order;
}

function keybind_action_display_name(_id) {
    return i18n_get("kb_" + _id);
}

function keybind_binding_string_raw(_id) {
    var _a = keybind_get_action(_id);
    if(_a == undefined) return "";
    if(_a.type == KBT_CHOICE) {
        var _parts = [];
        for(var i=0; i<array_length(_a.choices); i++)
            _parts[i] = _keybind_keys_string(_a.choices[i]);
        return string_join_ext("/", _parts);
    }
    var _isAxis = array_length(_a.pos) > 0 || array_length(_a.neg) > 0;
    if(_isAxis)
        return _keybind_keys_string(_a.neg) + "/" + _keybind_keys_string(_a.pos);
    if(_a.type == KBT_CHORD)
        return _keybind_keys_string(_a.keys, " + ");
    return _keybind_keys_string(_a.keys);
}

function _keybind_keys_string(_keys, _sep = "/") {
    if(array_length(_keys) == 0) return "-";
    var _parts = [];
    for(var i=0; i<array_length(_keys); i++)
        array_push(_parts, keybind_key_to_string(_keys[i]));
    return string_join_ext(_sep, _parts);
}

function keybind_binding_display(_id) {
    var _s = keybind_binding_string_raw(_id);
    if(_s == "" || _s == "-") return i18n_get("kb_unbound");
    return _s;
}

function keybind_action_primary_vk(_id) {
    var _a = keybind_get_action(_id);
    if(_a == undefined) return -1;
    if(array_length(_a.keys) > 0) return _a.keys[0].vk;
    if(array_length(_a.pos) > 0) return _a.pos[0].vk;
    return -1;
}

function keybind_is_customized(_id) {
    return variable_struct_exists(global.__KeyBindManager.userBindings, _id);
}

/// Sets a user override from a raw serialized value.
/// Returns { ok, error, conflict } - conflict holds the colliding action ids when set.
function keybind_set_binding(_id, _raw) {
    var _m = global.__KeyBindManager;
    if(!variable_struct_exists(_m.actions, _id))
        return { ok: false, error: "unknown action '" + _id + "'", conflict: [] };

    var _copy = _keybind_copy_action(_m.actions[$ _id]);
    if(!_keybind_apply_raw(_copy, _raw))
        return { ok: false, error: "invalid binding for '" + _id + "'", conflict: [] };

    // Same-context conflict check against all other actions' effective bindings.
    var _sigs = _keybind_action_signatures(_copy);
    var _conflict = [];
    for(var i=0; i<array_length(_m.order); i++) {
        var _oid = _m.order[i];
        if(_oid == _id) continue;
        var _oa = _m.actions[$ _oid];
        if(_oa.context != _copy.context) continue;
        for(var j=0; j<array_length(_sigs); j++)
            if(_keybind_action_has_key(_oa, _sigs[j])) {
                array_push(_conflict, _oid);
                break;
            }
    }
    if(array_length(_conflict) > 0)
        return { ok: false, error: "key already in use", conflict: _conflict };

    _m.actions[$ _id] = _copy;
    _m.userBindings[$ _id] = _keybind_normalize_raw(_copy);
    _m._rebuild_cache_list();
    return { ok: true, error: "", conflict: [] };
}

/// Removes the user override; the action falls back to its preset-layer binding.
function keybind_reset(_id) {
    var _m = global.__KeyBindManager;
    if(variable_struct_exists(_m.userBindings, _id)) {
        _m._revert_to_preset(_id);
        _m._rebuild_cache_list();
    }
}

/// Full reset: user overrides cleared, preset back to built-in defaults.
function keybind_reset_all() {
    var _m = global.__KeyBindManager;
    _m.userBindings = {};
    _m.apply_preset("dynode");
}

function keybind_set_preset(_name) {
    var _m = global.__KeyBindManager;
    if(!variable_struct_exists(_m.presets, _name)) return false;
    _m.userBindings = {};
    _m.apply_preset(_name);
    return true;
}

function keybind_get_preset() {
    return global.__KeyBindManager.preset;
}

function keybind_serialize_config() {
    if(!variable_global_exists("__KeyBindManager")) return undefined;
    return global.__KeyBindManager.serialize();
}

// ---------------- Key capture helpers (panel) ----------------

/// All known key codes (minus modifiers) for capture-mode scanning.
function _keybind_capture_vk_list() {
    static _list = undefined;
    if(_list != undefined) return _list;
    var _out = [];
    for(var i=0; i<26; i++) array_push(_out, ord("A") + i);
    for(var i=0; i<10; i++) array_push(_out, 48 + i);
    for(var i=0; i<10; i++) array_push(_out, vk_numpad0 + i);
    for(var i=1; i<=12; i++) array_push(_out, vk_f1 + (i - 1));
    var _fixed = [vk_escape, vk_enter, vk_backspace, vk_space, vk_tab, vk_delete,
        vk_insert, vk_home, vk_end, vk_pageup, vk_pagedown,
        vk_up, vk_down, vk_left, vk_right,
        192, 189, 187, 188, 190, 191, 186, 222, 219, 221, 220];
    for(var i=0; i<array_length(_fixed); i++) array_push(_out, _fixed[i]);
    _list = _out;
    return _out;
}

/// Raw (unfiltered) scan for a pressed non-modifier key; -1 when none.
function keybind_capture_scan() {
    var _vks = _keybind_capture_vk_list();
    for(var i=0; i<array_length(_vks); i++)
        if(keyboard_check_pressed(_vks[i])) return _vks[i];
    return -1;
}

function keybind_capture_mods() {
    return {
        ctrl: keyboard_check(vk_control),
        shift: keyboard_check(vk_shift),
        alt: keyboard_check(vk_alt)
    };
}

// ---------------- Overlay / panel instances ----------------

function keybind_overlay_toggle() {
    if(instance_exists(objKeybindOverlay)) {
        with(objKeybindOverlay)
            instance_destroy();
    }
    else {
        var _inst = instance_create_depth(0, 0, -900, objKeybindOverlay);
        // Rebuild after Create so late-registered actions always appear.
        with(_inst) keybind_overlay_rebuild_lists();
    }
}

function keybind_overlay_hold(_down) {
    if(_down) {
        if(!instance_exists(objKeybindOverlay)) {
            var _inst = instance_create_depth(0, 0, -900, objKeybindOverlay);
            _inst.holdMode = true;
        }
    }
    else {
        with(objKeybindOverlay)
            if(holdMode) instance_destroy();
    }
}

/// The toggle-mode overlay is modal (blocks game input like the debug overlay);
/// the hold-mode overlay lets the game keep running underneath.
function keybind_overlay_blocks_input() {
    if(!instance_exists(objKeybindOverlay)) return false;
    with(objKeybindOverlay)
        if(!holdMode) return true;
    return false;
}

function keybind_panel_open() {
    if(!instance_exists(objKeybindPanel)) {
        // Persistent overlay caches its list at Create; refresh so new actions show.
        if(instance_exists(objKeybindOverlay))
            with(objKeybindOverlay)
                keybind_overlay_rebuild_lists();
        instance_create_depth(0, 0, -1000, objKeybindPanel);
    }
}

function keybind_panel_toggle() {
    if(instance_exists(objKeybindPanel)) {
        with(objKeybindPanel)
            instance_destroy();
    }
    else {
        instance_create_depth(0, 0, -1000, objKeybindPanel);
    }
}

function color_timeline_panel_open() {
    if(!instance_exists(objColorTimeline))
        instance_create_depth(0, 0, -1000, objColorTimeline);
}

function color_timeline_panel_toggle() {
    if(instance_exists(objColorTimeline)) {
        with(objColorTimeline)
            instance_destroy();
    }
    else {
        instance_create_depth(0, 0, -1000, objColorTimeline);
    }
}
