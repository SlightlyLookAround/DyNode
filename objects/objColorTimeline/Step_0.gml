/// @description Panel interactions. Modal: game input frozen while open.

global.__InputManager.freeze();

// Esc closes the panel.
if(keyboard_check_pressed(vk_escape)) {
    instance_destroy();
    exit;
}

// Scrolling
var _wheel = mouse_wheel_up() - mouse_wheel_down();
if(pos_inbound(mouse_x, mouse_y, x0, y0, x0 + panelW, y0 + panelH))
    scrollTarget = clamp(scrollTarget - _wheel * rowH * 3, 0, _maxScroll);
scroll = lerp(scroll, scrollTarget, 0.3);
if(abs(scroll - scrollTarget) < 0.5)
    scroll = scrollTarget;

// Refresh entries each frame (lightweight JSON call).
_refresh_entries();

// Clicks
if(mouse_check_button_pressed(mb_left)) {
    var _mx = mouse_x;
    var _my = mouse_y;

    // Close button (X)
    if(pos_inbound(_mx, _my, closeBtnX - closeBtnR, closeBtnY - closeBtnR, closeBtnX + closeBtnR, closeBtnY + closeBtnR)) {
        instance_destroy();
        exit;
    }

    // Buttons
    for(var i = 0; i < array_length(buttons); i++) {
        var _b = buttons[i];
        if(pos_inbound(_mx, _my, _b.x, _b.y, _b.x + _b.w, _b.y + _b.h)) {
            switch(_b.kind) {
                case "toggle":
                    var _newVal = !dyc_color_timeline_get_enabled();
                    dyc_color_timeline_set_enabled(_newVal);
                    announcement_play(i18n_get(_newVal ? "color_timeline_toggle_on" : "color_timeline_toggle_off"), 3000);
                    break;
                case "add":
                    color_keyframe_create(true);
                    _refresh_entries();
                    break;
                case "clear":
                    if(dyc_color_keyframes_count() > 0) {
                        if(dyc_show_question(i18n_get("color_timeline_clear_confirm"))) {
                            dyc_color_keyframes_reset();
                            _refresh_entries();
                            announcement_play(i18n_get("color_timeline_clear"), 3000);
                        }
                    }
                    break;
                case "close":
                    instance_destroy();
                    exit;
            }
            exit;
        }
    }

    // List row click — edit or delete
    if(pos_inbound(_mx, _my, x0, listY, x0 + panelW, listY + listH)) {
        var _idx = floor((_my - listY + scroll) / rowH);
        if(_idx >= 0 && _idx < array_length(entries)) {
            var _kf = entries[_idx];
            // Right half of row → delete, left half → edit
            if(_mx > x0 + panelW - 100) {
                color_keyframe_delete(_kf.time, true);
                _refresh_entries();
            } else {
                color_keyframe_change(_kf.time, true);
                _refresh_entries();
            }
        }
    }
}
