/// @description Update Editor

#region Beatlines
    
    var timingPoints = dyc_get_timingpoints();
    animBeatlineTargetAlphaM = editorMode != 5 && array_length(timingPoints);
    beatlineAlphaMul = lerp_a(beatlineAlphaMul, animBeatlineTargetAlphaM, animSpeed);
    if(array_length(timingPoints)) {
        var _modchg = bind_down("editor_beatline_mode_next") - bind_down("editor_beatline_mode_prev");
        var _groupchg = bind_down("editor_beatline_group_switch");
        beatlineNowGroup += _groupchg;
        beatlineNowGroup %= 2;
        beatlineNowMode += _modchg;
        beatlineNowMode = clamp(beatlineNowMode, 0, array_length(beatlineModes[beatlineNowGroup])-1);

        if(_modchg != 0 || _groupchg != 0) {
        	set_div(beatlineDivs[beatlineNowGroup][beatlineNowMode], false);
            announcement_play(i18n_get("beatline_divs", [string(get_div()),
            	chr(beatlineNowGroup+ord("A"))]), 3000, "beatlineDiv");
        }

        if(bind_down("editor_beatline_div_custom")) {
        	if(editor_set_div())
	        	announcement_play(i18n_get("beatline_divs", [string(get_div()),
	            	chr(beatlineNowGroup+ord("A"))]), 3000, "beatlineDiv");
        }

        var _findiv = bind_axis("editor_beatline_div_fine");
        if(_findiv != 0) {
        	set_div(clamp(get_div() + _findiv, 1, 128), false);
        	announcement_play(i18n_get("beatline_divs", [string(get_div()),
            	chr(beatlineNowGroup+ord("A"))]), 3000, "beatlineDiv");
        }

        animBeatlineTargetAlpha[0] += 0.7 * bind_down("editor_beatline_side_down");
        animBeatlineTargetAlpha[1] += 0.7 * bind_down("editor_beatline_side_left");
        animBeatlineTargetAlpha[2] += 0.7 * bind_down("editor_beatline_side_right");

        if(bind_down("editor_beatline_side_down") || bind_down("editor_beatline_side_left") || bind_down("editor_beatline_side_right")) {
            if(editor_get_editmode() == 5)
                editor_set_editmode(4);
        }

        for(var i=0; i<3; i++) {
            if(animBeatlineTargetAlpha[i] > 1.4)
                animBeatlineTargetAlpha[i] = 0;
            beatlineAlpha[i] = lerp_a(beatlineAlpha[i], min(animBeatlineTargetAlpha[i], 1), animSpeed);
        }
        
        for(var i=0; i<=beatlineMaxDiv; i++)
            beatlineEnabled[i] = 0;
        if(beatlineDivs[beatlineNowGroup][beatlineNowMode] == get_div()) {
        	var l = array_length(beatlineModes[beatlineNowGroup][beatlineNowMode]);
	        for(var i=0; i<l; i++)
	            beatlineEnabled[beatlineModes[beatlineNowGroup][beatlineNowMode][i]] = 1;
        }
        else {
        	beatlineEnabled[1] = 1;
            if(get_div()<=beatlineMaxDiv)
        		beatlineEnabled[get_div()] = 1;
        }
    }
    else {
        if(bind_down("editor_beatline_side_down") || bind_down("editor_beatline_side_left") || bind_down("editor_beatline_side_right")) {
            announcement_warning("beatline_without_timing");
        }
    }

#endregion

#region Note Edit

    // Wheel width adjust
    var _delta_width = wheelcheck_up_ctrl() - wheelcheck_down_ctrl();
    if(_delta_width != 0) {
        with(objNote) if(stateType == NOTE_STATES.SELECTED) {
            if(!is_struct(origPropWidthAdjust))
                origPropWidthAdjust = get_prop();
            width += _delta_width * 0.05;
            update_prop();
            objEditor.editorWidthAdjustTime = 0;
        }
    }
    
    if(editorWidthAdjustTime < editorWidthAdjustTimeThreshold) {
        editorWidthAdjustTime += global.timeManager.get_delta() / 1000;
        if(editorWidthAdjustTime >= editorWidthAdjustTimeThreshold) {
            with(objNote) if(stateType == NOTE_STATES.SELECTED) {
                operation_step_add(OPERATION_TYPE.MOVE, origPropWidthAdjust, get_prop());
                origPropWidthAdjust = -1;
            }
            operation_merge_last_request(1, OPERATION_TYPE.SETWIDTH);
        }
    }
    editorWidthAdjustTime = min(editorWidthAdjustTime, 10000);

#endregion