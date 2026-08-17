/// @description Draw the keybind settings panel.

var _col = theme_get().color;

// Backdrop & panel
draw_set_color_alpha(c_black, 0.5);
draw_rectangle(0, 0, BASE_RES_W, BASE_RES_H, false);

CleanRectangleXYWH(x0 + panelW / 2, y0 + panelH / 2, panelW, panelH)
    .Blend(0x101014, 0.96)
    .Border(2, _col, 0.8)
    .Rounding(14)
    .Draw();

// Title + preset indicator
var _titleStr = keybind_text_cjk(i18n_get("kb_panel_title"));
scribble(_titleStr, "KB_P_TITLE")
    .starting_format("mSpaceMono", c_white)
    .align(fa_left, fa_middle)
    .scale(keybind_text_scale(_titleStr), keybind_text_scale(_titleStr))
    .draw(x0 + 28, y0 + titleH / 2);

var _presetLabel = i18n_get("kb_panel_preset_label") + ": " + i18n_get("kb_preset_" + keybind_get_preset());
if(array_length(variable_struct_get_names(global.__KeyBindManager.userBindings)) > 0)
    _presetLabel += " (" + i18n_get("kb_preset_custom") + ")";
_presetLabel = keybind_text_cjk(_presetLabel);
scribble(_presetLabel, "KB_P_PRESET")
    .starting_format("mSpaceMono", _col)
    .align(fa_right, fa_middle)
    .scale(keybind_text_scale(_presetLabel), keybind_text_scale(_presetLabel))
    .draw(x0 + panelW - 28, y0 + titleH / 2);

// Buttons
for(var i=0; i<array_length(buttons); i++) {
    var _b = buttons[i];
    var _active = false;
    var _label = "";
    switch(_b.kind) {
        case "preset":
            _label = i18n_get("kb_preset_" + _b.arg);
            _active = keybind_get_preset() == _b.arg
                && array_length(variable_struct_get_names(global.__KeyBindManager.userBindings)) == 0;
            break;
        case "resetall": _label = i18n_get("kb_panel_reset_all"); break;
        case "close": _label = i18n_get("kb_panel_close"); break;
    }
    var _hover = pos_inbound(mouse_x, mouse_y, _b.x, _b.y, _b.x + _b.w, _b.y + _b.h);

    CleanRectangleXYWH(_b.x + _b.w / 2, _b.y + _b.h / 2, _b.w, _b.h)
        .Blend(_active ? merge_color(_col, c_black, 0.4) : (_hover ? 0x2a2a33 : 0x1a1a21), 0.95)
        .Border(1, _active ? _col : 0x555560, 0.9)
        .Rounding(8)
        .Draw();

    var _labelStr = keybind_text_cjk(_label);
    scribble(_labelStr, "KB_P_BTN_" + _b.kind + _b.arg)
        .starting_format("mSpaceMono", _active ? c_white : 0xdddddd)
        .align(fa_center, fa_middle)
        .scale(keybind_text_scale(_labelStr), keybind_text_scale(_labelStr))
        .draw(_b.x + _b.w / 2, _b.y + _b.h / 2);
}

// Action rows
var _top = listY - rowH / 2;
var _bottom = listY + listH + rowH / 2;
for(var i=0; i<array_length(entries); i++) {
    var _ey = listY + i * rowH + rowH / 2 - scroll;
    if(_ey < _top || _ey > _bottom) continue;

    var _e = entries[i];
    if(_e.header) {
        CleanLine(x0 + 20, _ey + rowH / 2 - 4, x0 + panelW - 20, _ey + rowH / 2 - 4)
            .Blend(_col, 0.6)
            .Cap(true, true)
            .Draw();
        var _hStr = keybind_text_cjk(i18n_get("kb_ctx_" + _e.ctx));
        scribble(_hStr, "KB_P_H_" + _e.ctx)
            .starting_format("mSpaceMono", _col)
            .align(fa_left, fa_middle)
            .scale(keybind_text_scale(_hStr), keybind_text_scale(_hStr))
            .draw(x0 + 28, _ey);
        continue;
    }

    var _hover = pos_inbound(mouse_x, mouse_y, x0 + 16, _ey - rowH / 2 + 2, x0 + panelW - 16, _ey + rowH / 2 - 2);
    var _capturing = capturing == _e.id;

    if(_capturing || _hover) {
        CleanRectangleXYWH(x0 + panelW / 2, _ey, panelW - 32, rowH - 6)
            .Blend(_capturing ? merge_color(_col, c_black, 0.5) : 0x2a2a33, 0.9)
            .Border(0, _col, 0)
            .Rounding(6)
            .Draw();
    }

    var _name = keybind_action_display_name(_e.id);
    if(keybind_get_action(_e.id).reserved)
        _name += " *";
    _name = keybind_text_cjk(_name);
    var _nameCol = keybind_is_customized(_e.id) ? _col : c_white;
    scribble(_name, "KB_P_N_" + _e.id + string(_nameCol))
        .starting_format("mSpaceMono", _nameCol)
        .align(fa_left, fa_middle)
        .scale(keybind_text_scale(_name), keybind_text_scale(_name))
        .draw(x0 + 40, _ey);

    var _bind = keybind_text_cjk(keybind_binding_display(_e.id));
    var _bindCol = _capturing ? _col : 0xbbbbbb;
    if(variable_struct_exists(conflicts, _e.id)) {
        // Same-context key conflict: highlight the binding and mark the row.
        _bind += " !";
        _bindCol = 0xff5555;
    }
    scribble(_bind, "KB_P_B_" + _e.id + _bind)
        .starting_format("mSpaceMono", _bindCol)
        .align(fa_right, fa_middle)
        .scale(keybind_text_scale(_bind), keybind_text_scale(_bind))
        .draw(x0 + panelW - 40, _ey);
}

// Scrollbar
if(maxScroll > 0) {
    var _contentH = array_length(entries) * rowH;
    var _thumbH = max(40, listH * listH / _contentH);
    var _trackH = listH - _thumbH;
    CleanRectangleXYWH(x0 + panelW - 10, listY + _thumbH / 2 + _trackH * scroll / maxScroll, 5, _thumbH)
        .Blend(_col, 0.8)
        .Border(0, _col, 0)
        .Rounding(2)
        .Draw();
}

// Capture overlay
if(capturing != "") {
    draw_set_color_alpha(c_black, 0.7);
    draw_rectangle(x0, listY, x0 + panelW, listY + listH, false);

    var _capName = keybind_action_display_name(capturing);
    if(capturePhase >= 0)
        _capName += capturePhase == 0 ? "  [-]" : "  [+]";
    var _capMsg = keybind_text_cjk(i18n_get("kb_panel_capture", [_capName]));
    scribble(_capMsg, "KB_P_CAP_" + capturing + string(capturePhase))
        .starting_format("mSpaceMono", _col)
        .align(fa_center, fa_middle)
        .scale(keybind_text_scale(_capMsg), keybind_text_scale(_capMsg))
        .draw(x0 + panelW / 2, listY + listH / 2);
}

// Footer hint
var _hintStr = keybind_text_cjk(i18n_get("kb_panel_hint"));
scribble(_hintStr, "KB_P_HINT")
    .starting_format("mSpaceMono", 0x999999)
    .align(fa_left, fa_middle)
    .scale(keybind_text_scale(_hintStr), keybind_text_scale(_hintStr))
    .draw(x0 + 28, footerY);
var _rnoteStr = keybind_text_cjk(i18n_get("kb_reserved_note"));
scribble(_rnoteStr, "KB_P_RNOTE")
    .starting_format("mSpaceMono", 0x999999)
    .align(fa_right, fa_middle)
    .scale(keybind_text_scale(_rnoteStr), keybind_text_scale(_rnoteStr))
    .draw(x0 + panelW - 28, footerY);
