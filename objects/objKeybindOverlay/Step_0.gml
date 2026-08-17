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

var _wheel = mouse_wheel_up() - mouse_wheel_down();
scrollTarget = clamp(scrollTarget + _wheel * 90, 0, maxScroll);
scroll = lerp(scroll, scrollTarget, 0.3);
if(abs(scroll - scrollTarget) < 0.5)
    scroll = scrollTarget;
