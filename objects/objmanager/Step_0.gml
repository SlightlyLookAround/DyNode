/// @description Input check & Exts update

#region Window command

if(os_type == os_windows) {
	if(bind_down("global_fullscreen")) {
		window_toggle_fullscreen();
	}
	window_check_fullscreen();

	if(window_command_check(window_command_close)) {
		if(game_end_confirm())
			return;
	}
}
else {
	if(bind_down("global_fullscreen")) {
		global.fullscreen = !global.fullscreen;
		window_set_fullscreen(global.fullscreen);
	}
}

#endregion

#region AnnoMan Step

global.announcementMan.step();

#endregion


camera_set_view_size(view_camera[0], BASE_RES_W, BASE_RES_H);

var _fmoderr = FMODGMS_Sys_Update();

if(_fmoderr < 0) {
    show_debug_message("FMOD ERROR:\n"+FMODGMS_Util_GetErrorMessage());
}

if(bind_down("global_debug_layer")) {
	debugLayer = !debugLayer;
	show_debug_overlay(debugLayer);

	global.debugGizmos = !global.debugGizmos;
}
	
	

if(room == rMain) {
	if(bind_down("global_map_load"))
	    map_load();
	if(bind_down("global_save"))
		project_save();
	else if(bind_down("global_save_as"))
		project_save_as();
	if(bind_down("global_project_load"))
	    project_load();
	if(bind_down("global_project_new"))
		project_new();
	
	
	
	// For New Project Initialization --- related codes in rStartPage and rProjectInit
		// If there is a init struct
		if(initVars != undefined) {
			var _str = initVars;
			dyc_chart_set_metadata({
				title: _str.title,
				sideType: [_str.ltype, _str.rtype],
				difficulty: difficulty_char_to_num(string_char_at(_str.diff, 1)),
				charter: "",
				artist: ""
			});
			if(_str.mus != "")
				music_load(_str.mus);
			if(_str.bg != "") background_load(_str.bg);
			if(_str.chart != "") map_load(_str.chart);
			initVars = undefined;

			analytics_track_event("ProjectCreate");
		}
		
		// Or there is a init project
		if(initWithProject) {
			initWithProject = false;
			
			if(!project_load()) room_goto(rStartPage);
		}
}    
    
if(bind_down("global_screenshot")) {
	var _file = SYSFIX + program_directory + "Screenshots\\" + random_id(9) + ".png"
	screen_save(_file);
	announcement_play(i18n_get("screenshot_save") + _file)
}

else if(bind_down("global_shortcuts_overlay")) {
	// In-game keybind overlay (replaces the external shortcuts.html link)
	keybind_overlay_toggle();
}

// Hold-mode help overlay (H in the Dynamaker preset)
if(bind("main_help_overlay"))
	keybind_overlay_hold(true);
else
	keybind_overlay_hold(false);

if(bind_down("global_autosave"))
	switch_autosave();

if(bind_down("global_theme"))
	theme_next();

if(bind_down("global_quit")) {
	if(!instance_exists(objEditor)) {
		if(game_end_confirm())
			return;
	}
}

// Debug functions

if(DEBUG_MODE) {
	if(keycheck_down_ctrl(vk_numpad0))
		project_auto_save();
	if(keycheck_down_ctrl(vk_numpad8)) {
		_debug_start_record();
	}
	if(keycheck_down_ctrl(vk_numpad9)) {
		_debug_stop_record();
	}
	if(keycheck_down_ctrl(vk_numpad5)) {
		var result = lua_run();
		if(result.state == "error") {
			announcement_error(
				$"Lua run failed.\nDetails:\n[scale,0.6]{result.error}"
			);
		}
	}
}

// Update project time

if(delta_time < 1000000)
	projectTime += delta_time / 1000;
