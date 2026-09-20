

function ButtonSideSwitcher(_id, _x, _y, _side) : StateButton(_id, _x, _y, "", 0) constructor {
    side = _side;
    content = string_char_at("DLR", _side+1);
    get_value = function () {
        return editor_get_editmode() != 5 && editor_get_editside() == side;
    }
    
    custom_action = function (val) {
        if(!val) {
            editor_set_editside(side);
            return true;
        }
        return val;
    }
}

function BarVolumeMain(_id, _x, _y) : Bar(_id, _x, _y, i18n_get("tab_main_volume"), 0, 0) constructor {
	range = [0, 1];
// 	updateColddown = 200;
    get_active = function () {
        return objMain.music!=undefined;
    }
    get_value = function () {
        return objMain.volume_get_main();
    }
    custom_action = function() {
        objMain.volume_set_main(value);
    }
    
    update_active();
    value = get_value();
    aval = value;
    atval = value;
}

function BarVolumeHitSound(_id, _x, _y) : Bar(_id, _x, _y, i18n_get("tab_hitsound_volume"), 0, 0) constructor {
	range = [0, 1];
	active = true;
	get_active = function() {
		return instance_exists(objMain);
	}
    get_value = function () {
    	if(!active) return;
    	return objMain.volume_get_hitsound();
    }
    custom_action = function() {
        objMain.volume_set_hitsound(value);
    }
    
    update_active();
    value = get_value();
    aval = value;
    atval = value;
}

function BarBackgroundDim(_id, _x, _y) : Bar(_id, _x, _y, i18n_get("tab_bg_dim"), 0, 0) constructor {
	range = [0, 1];
	active = true;
	get_active = function() {
		return instance_exists(objMain);
	}
	get_value = function () {
    	if(!active) return;
    	return objMain.bgDim;
    }
    custom_action = function() {
    	objMain.bgDim = value;
    }
    
    update_active();
    value = get_value();
    aval = value;
    atval = value;
}

function BarColorChannel(_id, _x, _y, _slot) : Bar(_id, _x, _y, "", 0, 0) constructor {
	// _slot: 0/1/2 — first/second/third channel in the current edit mode (RGB or HSV)
	slot = _slot;
	range = [0, 255];
	active = true;
	saveColddown = 0;

	get_active = function() {
		return global.themeAt == 3;
	}

	// Keep labels/range in sync when the RGB/HSV mode switch flips.
	static __sync_channel_ui = function() {
		var _hsv = global.themeColorEditMode == 1;
		var _labels = _hsv ? ["H", "S", "V"] : ["R", "G", "B"];
		content = _labels[slot];
		range = (_hsv && slot == 0) ? [0, 360] : [0, 255];
	}

	get_value = function() {
		__sync_channel_ui();
		var _col = global.themeColorCustom;
		if(global.themeColorEditMode == 1) {
			var _hsv = color_rgb_to_hsv(_col);
			switch(slot) {
				case 0: return _hsv[0];
				case 1: return _hsv[1];
				case 2: return _hsv[2];
			}
			return 0;
		}
		switch(slot) {
			case 0: return colour_get_red(_col) / 255;
			case 1: return colour_get_green(_col) / 255;
			case 2: return colour_get_blue(_col) / 255;
		}
		return 0;
	}
	custom_action = function() {
		__sync_channel_ui();
		var _v = round(get());
		if(global.themeColorEditMode == 1) {
			var _hsv = color_rgb_to_hsv(global.themeColorCustom);
			switch(slot) {
				case 0: _hsv[0] = clamp(_v / 360, 0, 1); break;
				case 1: _hsv[1] = clamp(_v / 255, 0, 1); break;
				case 2: _hsv[2] = clamp(_v / 255, 0, 1); break;
			}
			theme_custom_set_color(color_hsv_to_rgb(_hsv[0], _hsv[1], _hsv[2]));
		} else {
			var _r = colour_get_red(global.themeColorCustom);
			var _g = colour_get_green(global.themeColorCustom);
			var _b = colour_get_blue(global.themeColorCustom);
			switch(slot) {
				case 0: _r = _v; break;
				case 1: _g = _v; break;
				case 2: _b = _v; break;
			}
			theme_custom_set_color(make_colour_rgb(_r, _g, _b));
		}
		if(saveColddown <= 0) {
			save_config();
			saveColddown = 500;
		}
	}

	static __stepColor = step;
	static step = function() {
		__sync_channel_ui();
		__stepColor();
		if(saveColddown > 0)
			saveColddown -= delta_time/1000;
	}

	static __drawColor = draw;
	static draw = function() {
		if(global.themeAt != 3) return;
		__sync_channel_ui();
		__drawColor();
	}

	__sync_channel_ui();
	update_active();
	value = get_value();
	aval = value;
	atval = value;
}

/// Checkbox for switching custom-theme color edit mode (RGB ↔ HSV).
/// Hidden unless Custom theme (themeAt == 3) is active.
function HSVModeCheckbox(_id, _x, _y, _l = 30) : Checkbox(
	_id, _x, _y, _l,
	i18n_get("tab_color_hsv_mode"),
	0,
	function (val) {
		global.themeColorEditMode = val ? 0 : 1;
		save_config();
		return global.themeColorEditMode == 1;
	},
	function () {
		return global.themeColorEditMode == 1;
	},
	function () {
		return global.themeAt == 3;
	}
) constructor {
	static __drawHSVChk = draw;
	static draw = function() {
		if(global.themeAt != 3) return;
		__drawHSVChk();
	}
}

function ParticleDensityButton(_id, _x, _y) : GUIElement() constructor {
	__init(_id, _x, _y, "", undefined, undefined);

	range = [0, 2];
	_density_labels = [
		i18n_get("particle_density_low"),
		i18n_get("particle_density_mid"),
		i18n_get("particle_density_high"),
	];

	get_value = function() {
		return global.particleDensity;
	}

	get_active = function() {
		return global.particleEffects == 1;
	}

	custom_action = function() {
		global.particleDensity = (global.particleDensity + 1) % 3;
		save_config();
	}

	static click = function() {
		if(!active) return;
		custom_action();
		show_debug_message("ParticleDensityButton "+name+" clicked. Density: "+string(global.particleDensity));
	}

	static draw = function() {
		if(!active) return;
		var _x = acenter.x;
		var _y = acenter.y;
		var _density = global.particleDensity;
		var _label = _density_labels[_density];

		CleanRectangleXYWH(_x, _y, width*ascale, height*ascale)
			.Blend(color, alpha)
			.Border(0, color, 0)
			.Rounding(rounding)
			.Draw();

		// Match Button text metrics (recording / keybinds) instead of GUI_MSDF_SCALE.
		var _raw = i18n_get("tab_particle_density") + ": " + _label;
		var _scl = has_cjk(_raw) ? 0.65 : 1;
		var _content = _raw;
		if(has_cjk(_raw)) _content = cjk_prefix() + _raw;
		scribble(_content, "GUI_"+name)
			.starting_format(font, c_white)
			.align(fa_center, fa_middle)
			.scale(_scl, _scl)
			.fit_to_box(width, height)
			.draw(_x, _y);
	}

	set_wh(300, 35);
}
