/// @description Panel interactions. The panel is modal: game input stays frozen
/// (bind_* queries return false) while the panel uses raw mouse / keyboard.

global.__InputManager.freeze();

if(capturing != "") {
    // Capture mode: Esc cancels, Backspace restores the default, any other key applies.
    // Axis actions capture the negative side first, then the positive side.
    if(keyboard_check_pressed(vk_escape)) {
        end_capture();
    }
    else if(keyboard_check_pressed(vk_backspace)) {
        keybind_reset(capturing);
        save_config();
        announcement_play(i18n_get("kb_bind_reset", [keybind_action_display_name(capturing)]));
        end_capture();
    }
    else {
        var _vk = keybind_capture_scan();
        if(_vk > 0) {
            var _mods = keybind_capture_mods();
            var _keyStr = keybind_key_to_string({ vk: _vk, ctrl: _mods.ctrl, shift: _mods.shift, alt: _mods.alt });

            if(capturePhase == 0) {
                // Negative side captured; wait for the positive side.
                captureNegKey = _keyStr;
                capturePhase = 1;
                io_clear();
            }
            else {
                var _raw = _keyStr;
                if(capturePhase == 1)
                    _raw = { pos: _keyStr, neg: captureNegKey };

                var _res = keybind_set_binding(capturing, _raw);
                if(_res.ok) {
                    save_config();
                    announcement_play(i18n_get("kb_bind_set",
                        [keybind_action_display_name(capturing), keybind_binding_string_raw(capturing)]));
                    if(keybind_get_action(capturing).reserved)
                        announcement_warning("kb_reserved");
                }
                else if(array_length(_res.conflict) > 0) {
                    var _names = "";
                    for(var i=0; i<array_length(_res.conflict); i++)
                        _names += (i > 0 ? ", " : "") + keybind_action_display_name(_res.conflict[i]);
                    announcement_warning(i18n_get("kb_conflict", [_names]));
                }
                else {
                    announcement_warning("kb_bind_invalid");
                }
                end_capture();
            }
        }
    }
}
else {
    if(keyboard_check_pressed(vk_escape)) {
        instance_destroy();
    }

        // Scrolling
        var _wheel = mouse_wheel_up() - mouse_wheel_down();
        if(pos_inbound(mouse_x, mouse_y, x0, y0, x0 + panelW, y0 + panelH))
            scrollTarget = clamp(scrollTarget - _wheel * rowH * 3, 0, maxScroll);
        scroll = lerp(scroll, scrollTarget, 0.3);
        if(abs(scroll - scrollTarget) < 0.5)
            scroll = scrollTarget;

        _refresh_conflicts();

    // Clicks
    if(mouse_check_button_pressed(mb_left)) {
        var _mx = mouse_x;
        var _my = mouse_y;
        var _hit = false;

        for(var i=0; i<array_length(buttons); i++) {
            var _b = buttons[i];
            if(pos_inbound(_mx, _my, _b.x, _b.y, _b.x + _b.w, _b.y + _b.h)) {
                switch(_b.kind) {
                    case "preset":
                        if(keybind_set_preset(_b.arg)) {
                            save_config();
                            announcement_play(i18n_get("kb_preset_set", [i18n_get("kb_preset_" + _b.arg)]));
                        }
                        break;
                    case "resetall":
                        keybind_reset_all();
                        save_config();
                        announcement_play("kb_reset_all_done");
                        break;
                    case "close":
                        instance_destroy();
                        break;
                }
                _hit = true;
                break;
            }
        }

        if(!_hit && pos_inbound(_mx, _my, x0, listY, x0 + panelW, listY + listH)) {
            var _idx = floor((_my - listY + scroll) / rowH);
            if(_idx >= 0 && _idx < array_length(entries)) {
                var _e = entries[_idx];
                if(!_e.header) {
                    var _act = keybind_get_action(_e.id);
                    // Choice / chord actions don't fit the single-key capture flow.
                    if(_act.type == KBT_CHOICE || _act.type == KBT_CHORD) {
                        announcement_warning("kb_not_rebindable");
                    }
                    else {
                        capturing = _e.id;
                        capturePhase = _is_axis_action(_act) ? 0 : -1;
                        captureNegKey = "";
                        io_clear();
                    }
                }
            }
        }
    }
}
