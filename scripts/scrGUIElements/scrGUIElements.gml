

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

function BarColorChannel(_id, _x, _y, _channel) : Bar(_id, _x, _y, _channel, 0, 0) constructor {
	channel = _channel;
	range = [0, 255];
	active = true;
	saveColddown = 0;
	
	get_active = function() {
		return global.themeAt == 3;
	}
	get_value = function() {
		switch(channel) {
			case "R": return colour_get_red(global.themeColorCustom) / 255;
			case "G": return colour_get_green(global.themeColorCustom) / 255;
			case "B": return colour_get_blue(global.themeColorCustom) / 255;
		}
		return 0;
	}
	custom_action = function() {
		var _v = round(get());
		var _r = colour_get_red(global.themeColorCustom);
		var _g = colour_get_green(global.themeColorCustom);
		var _b = colour_get_blue(global.themeColorCustom);
		switch(channel) {
			case "R": _r = _v; break;
			case "G": _g = _v; break;
			case "B": _b = _v; break;
		}
		theme_custom_set_color(make_colour_rgb(_r, _g, _b));
		if(saveColddown <= 0) {
			save_config();
			saveColddown = 500;
		}
	}
	
	static __stepColor = step;
	static step = function() {
		__stepColor();
		if(saveColddown > 0)
			saveColddown -= delta_time/1000;
	}
	
	static __drawColor = draw;
	static draw = function() {
		if(global.themeAt != 3) return;
		__drawColor();
	}
	
	update_active();
	value = get_value();
	aval = value;
	atval = value;
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

		var _content = i18n_get("tab_particle_density") + ": " + _label;
		if(has_cjk(_content)) _content = cjk_prefix() + _content;
		scribble(_content, "GUI_"+name)
			.starting_format(font, c_white)
			.scale(GUI_MSDF_SCALE, GUI_MSDF_SCALE)
			.align(fa_center, fa_middle)
			.draw(_x, _y);
	}

	set_wh(300, 35);
}
