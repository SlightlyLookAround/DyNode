/// @description Draw the keybind overlay.

var _col = theme_get().color;

draw_set_color_alpha(c_black, 0.82);
draw_rectangle(0, 0, BASE_RES_W, BASE_RES_H, false);

var _titleStr = keybind_text_cjk(i18n_get("kb_overlay_title"));
scribble(_titleStr, "KB_OL_TITLE")
    .starting_format("mSpaceMono", c_white)
    .align(fa_center, fa_middle)
    .scale(keybind_text_scale(_titleStr), keybind_text_scale(_titleStr))
    .draw(BASE_RES_W / 2, 48);

var _presetLabel = i18n_get("kb_preset_" + keybind_get_preset());
if(array_length(variable_struct_get_names(global.__KeyBindManager.userBindings)) > 0)
    _presetLabel += " (" + i18n_get("kb_preset_custom") + ")";
_presetLabel = keybind_text_cjk(_presetLabel);
scribble(_presetLabel, "KB_OL_PRESET")
    .starting_format("mSpaceMono", _col)
    .align(fa_center, fa_middle)
    .scale(keybind_text_scale(_presetLabel), keybind_text_scale(_presetLabel))
    .draw(BASE_RES_W / 2, 86);

_draw_keybind_column(colA, marginX);
_draw_keybind_column(colB, marginX + colW + colGap);

// Scroll indicator
if(maxScroll > 0) {
    var _contentH = maxRows * rowH;
    var _thumbH = max(40, listH * listH / _contentH);
    var _trackH = listH - _thumbH;
    CleanRectangleXYWH(marginX / 2, listY + _thumbH / 2 + _trackH * scroll / maxScroll, 6, _thumbH)
        .Blend(_col, 0.8)
        .Border(0, _col, 0)
        .Rounding(3)
        .Draw();
}

var _hintStr = keybind_text_cjk(i18n_get("kb_overlay_hint"));
scribble(_hintStr, "KB_OL_HINT")
    .starting_format("mSpaceMono", c_white)
    .align(fa_center, fa_middle)
    .scale(keybind_text_scale(_hintStr), keybind_text_scale(_hintStr))
    .draw(BASE_RES_W / 2, BASE_RES_H - 36);
