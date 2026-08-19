/// @description Overlay input handling (raw keys - game input is blocked in toggle mode).

if(holdMode) {
    // Hold mode: visible while the help-overlay key is held.
    var _vk = keybind_action_primary_vk("main_help_overlay");
    if(_vk < 0 || !keyboard_check(_vk))
        instance_destroy();
}
else {
    // Toggle mode: close on the overlay's own binding or Escape.
    var _close = keybind_action_primary_vk("global_shortcuts_overlay");
    if(keyboard_check_pressed(vk_escape) || (_close > 0 && keyboard_check_pressed(_close)))
        instance_destroy();
}

// Mouse wheel scrolling
var _wheel = mouse_wheel_up() - mouse_wheel_down();
scrollTarget = clamp(scrollTarget - _wheel * 90, 0, maxScroll);

// Scrollbar drag / click-to-position
if(maxScroll > 0) {
    var _contentH = maxRows * rowH;
    var _thumbH = max(40, listH * listH / _contentH);
    var _trackH = listH - _thumbH;
    var _sbx = marginX / 2;

    if(mouse_check_button_released(mb_left)) {
        scrollDragging = false;
    }

    if(scrollDragging) {
        var _trackY = listY + _thumbH / 2;
        var _mouseFrac = clamp((mouse_y - _trackY - scrollDragOffset) / _trackH, 0, 1);
        scrollTarget = clamp(round(_mouseFrac * maxScroll), 0, maxScroll);
    }
    else if(mouse_check_button_pressed(mb_left)) {
        var _thumbCenter = listY + _thumbH / 2 + _trackH * scroll / maxScroll;
        var _thumbTop = _thumbCenter - _thumbH / 2;
        var _thumbBottom = _thumbCenter + _thumbH / 2;
        var _halfH = clamp(mouse_y, listY, listY + listH);

        if(abs(mouse_x - _sbx) < 24
            && _halfH >= _thumbTop && _halfH <= _thumbBottom) {
            scrollDragging = true;
            scrollDragOffset = mouse_y - _thumbTop;
        }
        else if(abs(mouse_x - _sbx) < 24
            && mouse_y >= listY && mouse_y <= listY + listH) {
            scrollTarget = clamp(round(_thumbH * (_halfH - listY) / _trackH), 0, maxScroll);
        }
    }
}

// Smooth scroll lerp
scroll = lerp(scroll, scrollTarget, 0.3);
if(abs(scroll - scrollTarget) < 0.5)
    scroll = scrollTarget;
