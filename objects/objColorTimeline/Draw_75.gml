/// @description Draw the color timeline panel.

var _col = theme_get().color;
var _isCustom = (global.themeAt == 3);

// Backdrop & panel
draw_set_color_alpha(c_black, 0.5);
draw_rectangle(0, 0, BASE_RES_W, BASE_RES_H, false);

CleanRectangleXYWH(x0 + panelW / 2, y0 + panelH / 2, panelW, panelH)
    .Blend(0x101014, 0.96)
    .Border(2, _col, 0.8)
    .Rounding(14)
    .Draw();

// Title
var _titleStr = keybind_text_cjk(i18n_get("color_timeline_title"));
scribble(_titleStr, "CK_TITLE")
    .starting_format("mSpaceMono", c_white)
    .align(fa_left, fa_middle)
    .scale(keybind_text_scale(_titleStr), keybind_text_scale(_titleStr))
    .draw(x0 + 28, y0 + titleH / 2);

// Close button (X)
var _closeHover = pos_inbound(mouse_x, mouse_y, closeBtnX - closeBtnR, closeBtnY - closeBtnR, closeBtnX + closeBtnR, closeBtnY + closeBtnR);
var _xStr = "X";
scribble(_xStr, "CK_CLOSE")
    .starting_format("mSpaceMono", _closeHover ? c_white : 0xaaaaaa)
    .align(fa_center, fa_middle)
    .scale(0.85, 0.85)
    .draw(closeBtnX, closeBtnY);

// Warning if not custom theme
if(!_isCustom) {
    var _warnStr = keybind_text_cjk(i18n_get("color_timeline_not_custom"));
    scribble(_warnStr, "CK_WARN")
        .starting_format("mSpaceMono", 0xff8844)
        .align(fa_right, fa_middle)
        .scale(keybind_text_scale(_warnStr), keybind_text_scale(_warnStr))
        .draw(x0 + panelW - 70, y0 + titleH / 2);
}

// Buttons
var _tlEnabled = dyc_color_timeline_get_enabled();
for(var i = 0; i < array_length(buttons); i++) {
    var _b = buttons[i];
    var _hover = pos_inbound(mouse_x, mouse_y, _b.x, _b.y, _b.x + _b.w, _b.y + _b.h);
    var _label = keybind_text_cjk(i18n_get("color_timeline_" + _b.kind));
    var _isActive = (_b.kind == "toggle" && _tlEnabled);

    CleanRectangleXYWH(_b.x + _b.w / 2, _b.y + _b.h / 2, _b.w, _b.h)
        .Blend(_isActive ? merge_color(_col, c_black, 0.4) : (_hover ? 0x2a2a33 : 0x1a1a21), 0.95)
        .Border(1, _isActive ? _col : 0x555560, 0.9)
        .Rounding(8)
        .Draw();

    scribble(_label, "CK_BTN_" + _b.kind)
        .starting_format("mSpaceMono", _isActive ? c_white : 0xdddddd)
        .align(fa_center, fa_middle)
        .scale(keybind_text_scale(_label), keybind_text_scale(_label))
        .draw(_b.x + _b.w / 2, _b.y + _b.h / 2);
}

// List
var _top = listY - rowH / 2;
var _bottom = listY + listH + rowH / 2;

if(array_length(entries) == 0) {
    var _emptyStr = keybind_text_cjk(i18n_get("color_timeline_empty"));
    scribble(_emptyStr, "CK_EMPTY")
        .starting_format("mSpaceMono", 0x666666)
        .align(fa_center, fa_middle)
        .scale(keybind_text_scale(_emptyStr), keybind_text_scale(_emptyStr))
        .draw(x0 + panelW / 2, listY + listH / 2);
} else {
    for(var i = 0; i < array_length(entries); i++) {
        var _ey = listY + i * rowH + rowH / 2 - scroll;
        if(_ey < _top || _ey > _bottom) continue;

        var _kf = entries[i];
        var _hover = pos_inbound(mouse_x, mouse_y, x0 + 16, _ey - rowH / 2 + 2, x0 + panelW - 16, _ey + rowH / 2 - 2);

        if(_hover) {
            CleanRectangleXYWH(x0 + panelW / 2, _ey, panelW - 32, rowH - 6)
                .Blend(0x2a2a33, 0.9)
                .Border(0, _col, 0)
                .Rounding(6)
                .Draw();
        }

        // Color swatch
        var _swX = x0 + 36;
        var _swY = _ey;
        var _swW = 24;
        var _swH = 20;
        draw_set_color(_kf.color);
        draw_rectangle(_swX - _swW / 2, _swY - _swH / 2, _swX + _swW / 2, _swY + _swH / 2, false);
        draw_set_color(0x555555);
        draw_rectangle(_swX - _swW / 2, _swY - _swH / 2, _swX + _swW / 2, _swY + _swH / 2, true);
        draw_set_color(c_white);

        // Time
        var _timeStr = format_time_ms(_kf.time);
        scribble(_timeStr, "CK_T_" + string(i))
            .starting_format("mSpaceMono", c_white)
            .align(fa_left, fa_middle)
            .scale(0.75, 0.75)
            .draw(x0 + 60, _ey);

        // Color hex
        var _hex = color_to_hex(_kf.color);
        scribble(_hex, "CK_C_" + string(i))
            .starting_format("mSpaceMono", 0xbbbbbb)
            .align(fa_left, fa_middle)
            .scale(0.75, 0.75)
            .draw(x0 + 260, _ey);

        // Interp mode
        var _interpKey = "color_timeline_interp_smooth";
        switch(_kf.interp) {
            case 0: _interpKey = "color_timeline_interp_smooth"; break;
            case 1: _interpKey = "color_timeline_interp_smooth_rgb"; break;
            case 2: _interpKey = "color_timeline_interp_instant"; break;
        }
        var _interpStr = keybind_text_cjk(i18n_get(_interpKey));
        scribble(_interpStr, "CK_I_" + string(i))
            .starting_format("mSpaceMono", 0x999999)
            .align(fa_left, fa_middle)
            .scale(keybind_text_scale(_interpStr), keybind_text_scale(_interpStr))
            .draw(x0 + 420, _ey);

        // Delete hint on hover
        if(_hover) {
            var _delStr = keybind_text_cjk(i18n_get("color_timeline_delete_hint"));
            scribble(_delStr, "CK_DEL_" + string(i))
                .starting_format("mSpaceMono", 0xff5555)
                .align(fa_right, fa_middle)
                .scale(keybind_text_scale(_delStr), keybind_text_scale(_delStr))
                .draw(x0 + panelW - 30, _ey);
        }
    }
}

// Scrollbar
if(_maxScroll > 0) {
    var _contentH = array_length(entries) * rowH;
    var _thumbH = max(40, listH * listH / _contentH);
    var _trackH = listH - _thumbH;
    CleanRectangleXYWH(x0 + panelW - 10, listY + _thumbH / 2 + _trackH * scroll / _maxScroll, 5, _thumbH)
        .Blend(_col, 0.8)
        .Border(0, _col, 0)
        .Rounding(2)
        .Draw();
}

// Footer hint
var _hintStr = keybind_text_cjk(i18n_get("color_timeline_hint"));
scribble(_hintStr, "CK_HINT")
    .starting_format("mSpaceMono", 0x999999)
    .align(fa_left, fa_middle)
    .scale(keybind_text_scale(_hintStr), keybind_text_scale(_hintStr))
    .draw(x0 + 28, footerY);
