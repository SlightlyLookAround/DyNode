/// @description Keybind action registry.
/// Registers every rebindable action with its DyNode-current default binding
/// (see keybinds-design.md appendix A) plus the built-in presets.
/// Called from objmanager Create, before load_config / save_config.

function keybind_registry_init() {

    // ==== A.1 Editor: beatlines & editor state ====

    keybind_register("editor_beatline_mode_next", "editor", KBT_PRESS, ord("V"));
    keybind_register("editor_beatline_mode_prev", "editor", KBT_PRESS, ord("C"));
    keybind_register("editor_beatline_group_switch", "editor", KBT_PRESS, ord("G"));
    keybind_register("editor_beatline_div_custom", "editor", KBT_PRESS, 192);
    keybind_register("editor_beatline_side_down", "editor", KBT_PRESS, vk_down);
    keybind_register("editor_beatline_side_left", "editor", KBT_PRESS, vk_left);
    keybind_register("editor_beatline_side_right", "editor", KBT_PRESS, vk_right);
    keybind_register("editor_toggle_grid_y", "editor", KBT_PRESS, ord("Z"));
    keybind_register("editor_toggle_grid_x", "editor", KBT_PRESS, ord("X"));
    keybind_register("editor_toggle_highlight", "editor", KBT_PRESS, ord("H"));
    keybind_register("editor_timing_point_create", "editor", KBT_PRESS, ord("Y"));
    keybind_register("editor_color_timeline", "editor", KBT_PRESS, ord("Z"), { ctrl: true, shift: true });
    keybind_register("editor_undo", "editor", KBT_PRESS, ord("Z"), { ctrl: true });
    keybind_register("editor_redo", "editor", KBT_PRESS, ord("Y"), { ctrl: true });
    keybind_register("editor_default_width_mode", "editor", KBT_PRESS, ord("L"));
    keybind_register("editor_default_width_set", "editor", KBT_PRESS, ord("K"));
    keybind_register("editor_beatline_style", "editor", KBT_PRESS, ord("J"));
    keybind_register("editor_advanced_expr", "editor", KBT_PRESS, [ord("0"), vk_numpad0]);
    keybind_register("editor_multi_side_binding", "editor", KBT_PRESS, ord("B"));
    keybind_register("editor_select_all", "editor", KBT_PRESS, ord("A"), { ctrl: true });
    keybind_register("editor_side_next", "editor", KBT_PRESS, vk_up);

    // ==== A.2 Editor: selected notes operations ====

    keybind_register("editor_mirror", "editor", KBT_PRESS, ord("M"));
    keybind_register("editor_mirror_copy", "editor", KBT_PRESS, ord("M"), { ctrl: true });
    keybind_register("editor_rotate", "editor", KBT_PRESS, ord("R"));
    keybind_register("editor_rotate_copy", "editor", KBT_PRESS, ord("R"), { ctrl: true });
    keybind_register("editor_set_width", "editor", KBT_PRESS, ord("V"), { ctrl: true });
    keybind_register("editor_set_type_note", "editor", KBT_PRESS,
        [ord("1"), vk_numpad1], { ctrl: true });
    keybind_register("editor_set_type_chain", "editor", KBT_PRESS,
        [ord("2"), vk_numpad2], { ctrl: true });
    keybind_register("editor_duplicate_quick", "editor", KBT_PRESS, ord("D"), { ctrl: true });

    // ==== A.3 Editor: per-note (objnote, every instance) ====

    keybind_register("editor_note_delete", "editor", KBT_PRESS, [vk_delete, vk_backspace]);
    keybind_register("editor_note_timing_point", "editor", KBT_PRESS, ord("T"));
    keybind_register("editor_note_timing_point_delete", "editor", KBT_PRESS, vk_delete, { ctrl: true });
    keybind_register("editor_note_width_copy", "editor", KBT_PRESS, ord("C"), { ctrl: true });
    keybind_register_axis("editor_note_nudge_pos", "editor", vk_right, vk_left, { ctrl: true });
    keybind_register_axis("editor_note_nudge_time", "editor", vk_up, vk_down, { ctrl: true });
    keybind_register_axis("editor_note_nudge_pos_fine", "editor", vk_right, vk_left, { ctrl: true, shift: true });
    keybind_register_axis("editor_note_nudge_time_fine", "editor", vk_up, vk_down, { ctrl: true, shift: true });

    // ==== A.4 Editor: modes & clipboard ====

    keybind_register_choice("editor_mode", "editor", [
        [ord("1"), vk_numpad1],
        [ord("2"), vk_numpad2],
        [ord("3"), vk_numpad3],
        [ord("4"), vk_numpad4],
        [ord("5"), vk_numpad5],
    ]);
    keybind_register("editor_paste_mode_enter", "editor", KBT_PRESS, ord("V"), { ctrl: true });
    keybind_register("editor_paste_mirror", "editor", KBT_PRESS, ord("M"));
    keybind_register("editor_paste_type_note", "editor", KBT_PRESS,
        [ord("1"), vk_numpad1], { ctrl: true });
    keybind_register("editor_paste_type_chain", "editor", KBT_PRESS,
        [ord("2"), vk_numpad2], { ctrl: true });
    keybind_register_axis("editor_paste_center", "editor", vk_right, vk_left, { ctrl: true });
    keybind_register("editor_copy", "editor", KBT_PRESS, ord("C"), { ctrl: true });
    keybind_register("editor_cut", "editor", KBT_PRESS, ord("X"), { ctrl: true });
    keybind_register("editor_escape", "editor", KBT_PRESS, vk_escape, undefined, { reserved: true });

    // ==== A.5 Main ====

    keybind_register("main_music_load", "main", KBT_PRESS, vk_f3);
    keybind_register("main_bg_load", "main", KBT_PRESS, vk_f4);
    keybind_register("main_bg_reset", "main", KBT_PRESS, vk_f4, { ctrl: true });
    keybind_register("main_export_xml", "main", KBT_PRESS, vk_f5);
    keybind_register("main_export_raw", "main", KBT_PRESS, vk_f6);
    keybind_register("main_debug_info", "main", KBT_PRESS, vk_f11);
    keybind_register("main_show_bar", "main", KBT_PRESS, ord("B"), { ctrl: true });
    keybind_register("main_scoreboard", "main", KBT_PRESS, ord("P"));
    keybind_register("main_particles", "main", KBT_PRESS, ord("O"));
    keybind_register("main_hitsound", "main", KBT_PRESS, ord("H"), { ctrl: true });
    keybind_register("main_set_title", "main", KBT_PRESS, ord("T"), { ctrl: true });
    keybind_register("main_side_type", "main", KBT_PRESS, ord("F"), { ctrl: true });
    keybind_register("main_fade_other_notes", "main", KBT_PRESS, ord("F"));
    keybind_register("main_replay", "main", KBT_PRESS, vk_enter);
    keybind_register("main_replay_to_start", "main", KBT_PRESS, vk_enter);
    keybind_register("main_offset_add", "main", KBT_PRESS, ord("U"));
    keybind_register_axis("main_offset", "main", 187, 189);
    keybind_register_axis("main_global_offset", "main", 187, 189, { ctrl: true });
    keybind_register("main_simplify", "main", KBT_PRESS, ord("N"));
    keybind_register("main_randomize", "main", KBT_PRESS, vk_f6, { ctrl: true });
    keybind_register_chord("main_clear_all", "main", [vk_delete, vk_backspace]);
    keybind_register("main_play_pause", "main", KBT_PRESS, vk_space);
    keybind_register_axis("main_music_speed", "main", ord("W"), ord("S"));
    keybind_register_axis("main_note_speed", "main", ord("E"), ord("Q"));
    keybind_register_hold_axis("main_time_scroll", "main", ord("D"), ord("A"));
    keybind_register_axis("main_difficulty", "main", ord("P"), ord("O"), { ctrl: true });
    keybind_register_chord("main_diff_storage_toggle", "main", [ord("O"), ord("P")]);
    keybind_register("main_diff_storage_export", "main", KBT_PRESS, vk_f10);
    keybind_register("main_diff_storage_delete", "main", KBT_PRESS, vk_delete, { shift: true });

    // ==== A.6 Global (objmanager) ====

    keybind_register("global_fullscreen", "global", KBT_PRESS, vk_f7);
    keybind_register("global_debug_layer", "global", KBT_PRESS, vk_f11, { ctrl: true });
    keybind_register("global_map_load", "global", KBT_PRESS, vk_f2);
    keybind_register("global_save", "global", KBT_PRESS, ord("S"), { ctrl: true });
    keybind_register("global_save_as", "global", KBT_PRESS, ord("S"), { ctrl: true, shift: true });
    keybind_register("global_project_load", "global", KBT_PRESS, vk_f1);
    keybind_register("global_project_new", "global", KBT_PRESS, ord("N"), { ctrl: true });
    keybind_register("global_screenshot", "global", KBT_PRESS, vk_f12, { ctrl: true });
    keybind_register("global_shortcuts_overlay", "global", KBT_PRESS, vk_f12, undefined, { reserved: true });
    keybind_register("global_autosave", "global", KBT_PRESS, vk_f8);
    keybind_register("global_theme", "global", KBT_PRESS, vk_f9);
    keybind_register("global_quit", "global", KBT_PRESS, vk_escape, undefined, { reserved: true });

    // ==== A.7 Dynamaker-compat actions (unbound by default) ====

    keybind_register("main_replay_from_start", "main", KBT_PRESS, undefined);
    keybind_register("editor_snap_time_disable", "editor", KBT_HOLD, undefined);
    keybind_register("editor_snap_x_disable", "editor", KBT_HOLD, undefined);
    keybind_register_hold_axis("main_time_scroll_fine", "main", undefined, undefined);
    keybind_register("main_speed_reset", "main", KBT_PRESS, undefined);
    keybind_register("main_help_overlay", "main", KBT_HOLD, undefined);
    keybind_register("editor_undo_alt", "editor", KBT_PRESS, undefined);
    keybind_register("editor_redo_alt", "editor", KBT_PRESS, undefined);
    keybind_register_axis("editor_beatline_div_fine", "editor", undefined, undefined);
    keybind_register_hold_axis("main_time_scroll_shift", "main", ord("D"), ord("A"), { shift: true });

    // ==== Presets ====

    keybind_preset_register("dynode", {});

    // Dynamaker style (keybinds-design.md section 8 ruling table).
    // R/M also free editor_rotate / editor_mirror in place - their Ctrl+R / Ctrl+M
    // copy variants stay and cover the functionality.
    keybind_preset_register("dynamaker", {
        main_offset: { pos: "P", neg: "O" },
        main_replay_from_start: ["R", "M"],
        editor_rotate: "None",
        editor_mirror: "None",
        editor_snap_time_disable: "Z",
        editor_snap_x_disable: "X",
        main_time_scroll_fine: { pos: "Shift+D", neg: "Shift+A" },
        main_time_scroll_shift: { pos: "Ctrl+D", neg: "Ctrl+A" },
        main_speed_reset: "Shift+R",
        main_help_overlay: "H",
        editor_undo_alt: "Shift+Left",
        editor_redo_alt: "Shift+Right",
        editor_beatline_div_fine: { pos: "Shift+V", neg: "Shift+C" },
        main_particles: "Shift+O",
        main_scoreboard: "Shift+P",
        editor_toggle_highlight: "Shift+H",
        main_fade_other_notes: "Shift+F",
        editor_toggle_grid_y: "Shift+Z",
        editor_toggle_grid_x: "Shift+X",
        global_fullscreen: ["F7", "F"],
    });
}
