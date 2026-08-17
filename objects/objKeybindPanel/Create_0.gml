/// @description Keybind settings panel (click a row to rebind, capture, presets, reset).

persistent = false;

capturing = "";
// Capture phase: -1 = single key, 0 = axis negative side, 1 = axis positive side
capturePhase = -1;
captureNegKey = "";
scroll = 0;
scrollTarget = 0;
rowH = 32;
panelW = 1000;
panelH = 960;
x0 = (BASE_RES_W - panelW) / 2;
y0 = 20;
titleH = 56;
btnH = 44;
btnY = y0 + titleH + 10;
listY = btnY + btnH + 18;
listH = panelH - (listY - y0) - 60;
footerY = y0 + panelH - 30;

// Buttons: [kind, arg, width]
buttons = [];
var _defs = [
    ["preset", "dynode", 210],
    ["preset", "dynamaker", 210],
    ["resetall", "", 280],
    ["close", "", 150],
];
var _bx = x0 + 28;
for(var i=0; i<array_length(_defs); i++) {
    array_push(buttons, {
        kind: _defs[i][0],
        arg: _defs[i][1],
        x: _bx,
        y: btnY,
        w: _defs[i][2],
        h: btnH
    });
    _bx += _defs[i][2] + 14;
}

// Action list grouped by context
entries = [];
var _ctxs = ["editor", "main", "global"];
var _ids = keybind_action_ids();
for(var c=0; c<array_length(_ctxs); c++) {
    array_push(entries, { header: true, ctx: _ctxs[c], id: "" });
    for(var i=0; i<array_length(_ids); i++) {
        var _a = keybind_get_action(_ids[i]);
        if(_a.context == _ctxs[c])
            array_push(entries, { header: false, ctx: _ctxs[c], id: _ids[i] });
    }
}
maxScroll = max(0, array_length(entries) * rowH - listH);

// Same-context exact-key conflict map: id -> array of conflicting action ids
conflicts = {};

function _refresh_conflicts() {
    conflicts = {};
    var _ids = keybind_action_ids();
    var _map = {};
    for(var i=0; i<array_length(_ids); i++) {
        var _a = keybind_get_action(_ids[i]);
        var _keys = [];
        _keybind_collect_action_keys(_a, _keys);
        for(var j=0; j<array_length(_keys); j++) {
            var _sig = _keybind_key_sig(_keys[j]) + "@" + _a.context;
            if(variable_struct_exists(_map, _sig)) {
                var _oid = _map[$ _sig];
                if(!variable_struct_exists(conflicts, _ids[i])) conflicts[$ _ids[i]] = [];
                if(!array_contains(conflicts[$ _ids[i]], _oid))
                    array_push(conflicts[$ _ids[i]], _oid);
                if(!variable_struct_exists(conflicts, _oid)) conflicts[$ _oid] = [];
                if(!array_contains(conflicts[$ _oid], _ids[i]))
                    array_push(conflicts[$ _oid], _ids[i]);
            }
            else _map[$ _sig] = _ids[i];
        }
    }
}

function end_capture() {
    capturing = "";
    capturePhase = -1;
    captureNegKey = "";
    io_clear();
    global.__InputManager.unfreeze();
}

/// Axis-shaped actions (pos/neg slots) get a two-phase capture (negative, then positive).
function _is_axis_action(_act) {
    return _act.type == KBT_AXIS || array_length(_act.pos) > 0 || array_length(_act.neg) > 0;
}
