/// @description Clear Tags & Update Editor

// Clear selection tags and then update
editorSelectSingleTarget = -999;
editorSelectSingleTargetInbound = -999;
editorSelectedSingleInboundLast = editorSelectedSingleInbound;
editorSelectedSingleInbound = -999;
editorSelectOccupied = false;
editorSelectDragOccupied = false;
editorSelectInbound = false;

editorModeSwitching --;
editorModeSwitching = max(editorModeSwitching, 0);

editorSelectCount = 0;
var _note_found = false;

if(editorMode < 5) {
    with(objNote) {
        var _hl = false;
        if(stateType == NOTE_STATES.SELECTED) {
            objEditor.editorSelectCount ++;
            objEditor.editorSelectInbound |= _mouse_inbound_check() || _mouse_inbound_check(1);
            objEditor.editorSelectOccupied = 1;
            objEditor.editorSelectDragOccupied |= isDragging;
            if(isDragging) _hl = true;
        }
        else if((stateType == NOTE_STATES.ATTACH || stateType == NOTE_STATES.DROP) && id == editor_get_note_attaching_center()) {
            _hl = true;
        }
        else if(stateType == NOTE_STATES.ATTACH_SUB || stateType == NOTE_STATES.DROP_SUB) {
            _hl = true;
        }
        
        // Update Highlight Lines
        if(_hl && objEditor.editorHighlightLineEnabled) {
            _note_found = true;
            objEditor.editorHighlightLine = true;
            objEditor.editorHighlightLineFix = 1;
            objEditor.editorHighlightTime = time;
            objEditor.editorHighlightPosition = position;
            objEditor.editorHighlightSide = side;
            objEditor.editorHighlightWidth = width;
            if(stateType == NOTE_STATES.ATTACH_SUB || stateType == NOTE_STATES.DROP_SUB) {
                objEditor.editorHighlightTime = sinst.time;
            }
        }
    }
}

// Fix: highlight line flickering issue
if(!_note_found) {
    with(objEditor) {
        if(editorHighlightLineFix)
            editorHighlightLineFix --;
        else
            editorHighlightLine = false;
    }
}

editorSelectMultiple = editorSelectCount > 1;

#region Input Checks

    var _attach_reset_request = false, _attach_sync_request = false;
    
    if(bind_down("editor_toggle_grid_y")) {
        editorGridYEnabled = !editorGridYEnabled;
        announcement_adjust("adjust_grid_y", editorGridYEnabled);
    }

    if(bind_down("editor_toggle_grid_x")) {
        editorGridXEnabled = !editorGridXEnabled;
        announcement_adjust("adjust_grid_x", editorGridXEnabled);
    }

    if(bind_down("editor_toggle_highlight")) {
        editorHighlightLineEnabled = !editorHighlightLineEnabled;
        announcement_adjust("adjust_highlight", editorHighlightLineEnabled);
    }

    if(bind_down("editor_timing_point_create")) {
        timing_point_create(true);
    }

    if(bind_down("editor_color_timeline")) {
        color_timeline_panel_toggle();
    }

    if(bind_down("editor_undo")) {
        operation_undo();
    }
    else if(bind_down("editor_redo")) {
        operation_redo();
    }
    operation_synctime_sync();

    if(bind_down("editor_default_width_mode")) {
    	editorDefaultWidthMode ++;
    	editorDefaultWidthMode %= 4;
    	announcement_set("default_width_mode", editorDefaultWidthModeName[editorDefaultWidthMode]);
    	_attach_reset_request = true;
    }
    if(bind_down("editor_default_width_set")) {
    	_attach_sync_request = editor_set_default_width_qbox();
    }

    if(bind_down("editor_beatline_style")) {
    	beatlineStyleCurrent ++;
    	beatlineStyleCurrent %= BEATLINE_STYLES_COUNT;
    	global.beatlineStyle = beatlineStyleCurrent;
    	announcement_set("beatline_style", beatlineStylesName[beatlineStyleCurrent]);
    }

    if(bind_down("editor_advanced_expr"))
    	advanced_expr();

    if(bind_down("editor_multi_side_binding")) {
        editorSelectMultiSidesBinding = !editorSelectMultiSidesBinding;
        announcement_adjust("multiple_sides_selection_property_binding", editorSelectMultiSidesBinding);
    }

    if(bind_down("editor_select_all")) {
        editor_select_all();
        global.__InputManager._ioclear();
    }

    // Alternate undo / redo bindings (Dynamaker preset: Shift+Left / Shift+Right)
    if(bind_down("editor_undo_alt")) {
        operation_undo();
    }
    else if(bind_down("editor_redo_alt")) {
        operation_redo();
    }

    // Notes operation

    if(editor_select_count() > 0) {
    	if(bind_down("editor_mirror")) {
	    	with(objNote) {
	    		if(stateType == NOTE_STATES.SELECTED) {
	    			origProp = get_prop();
	    			position = 5 - position;
	    			operation_step_add(OPERATION_TYPE.MOVE, origProp, get_prop());
                    update_prop();
	    		}
	    	}
            operation_merge_last_request(1, OPERATION_TYPE.MIRROR);
	    	announcement_play(i18n_get("notes_mirror", string(editor_select_count())));
	    }
	    if(bind_down("editor_mirror_copy")) {
	    	with(objNote) {
	    		if(stateType == NOTE_STATES.SELECTED) {
	    			var prop = get_prop();
	    			prop.position = 5 - prop.position;
	    			note_select_reset(id);
	    			build_note(prop, true, true, true);
	    		}
	    	}
            operation_merge_last_request(1, OPERATION_TYPE.MIRROR);
	    	announcement_play(i18n_get("notes_mirror_copy", string(editor_select_count())));
	    }
	    if(bind_down("editor_rotate")) {
	    	var _found = 0;
	    	with(objNote) {
	    		if(stateType == NOTE_STATES.SELECTED)
		    		if(side > 0) {
		    			origProp = get_prop();
			    		side = 1 + (!(side - 1));
			    		operation_step_add(OPERATION_TYPE.MOVE, origProp, get_prop());
			    		_found ++;
                        update_prop();
			    	}
	    	}
	    	if(_found>0) {
                operation_merge_last_request(1, OPERATION_TYPE.ROTATE);
	    		announcement_play(i18n_get("notes_rotate", string(_found)));
                if(!editor_lrside_get() && !objEditor.copyMultipleSides)
	    		    editorSide = 1 + (!(editorSide - 1));
	    	}
	    		
	    	else
	    		announcement_warning("warning_notes_rotate");
	    }
	    if(bind_down("editor_rotate_copy")) {
	    	var _found = 0;
	    	with(objNote) {
	    		if(stateType == NOTE_STATES.SELECTED)
		    		if(side > 0) {
		    			var prop = get_prop();
			    		prop.side = 1 + (!(prop.side - 1));
			    		note_select_reset(id);
			    		build_note(prop, true, true, true);
			    		_found ++;
			    	}
	    	}
	    	if(_found>0) {
                operation_merge_last_request(1, OPERATION_TYPE.ROTATE);
	    		announcement_play(i18n_get("notes_rotate_copy", string(_found)));
                if(!editor_lrside_get() && !objEditor.copyMultipleSides)
	    		    editorSide = 1 + (!(editorSide - 1));
	    	}
	    		
	    	else
	    		announcement_warning("warning_notes_rotate_copy");
	    }
	    if(bind_down("editor_set_width")) {
	    	with(objNote)
	    		if(stateType == NOTE_STATES.SELECTED) {
	    			origProp = get_prop();
			    	width = editor_get_default_width();
			    	operation_step_add(OPERATION_TYPE.MOVE, origProp, get_prop());
                    update_prop();
	    		}
            operation_merge_last_request(1, OPERATION_TYPE.SETWIDTH);
	    	announcement_play(i18n_get("notes_set_width", [string_format(editor_get_default_width(), 1, 2),
	    		string(editor_select_count())]));
	    }
	    if(bind_down("editor_set_type_note")) {
	    	with(objNote)
	    		if(stateType == NOTE_STATES.SELECTED)
			    	if(noteType < 2) {
			    		var _prop = get_prop();
			    		note_delete(noteID, true);
			    		_prop.noteType = 0;
			    		build_note(_prop, true, true, true);
			    	}
            operation_merge_last_request(1, OPERATION_TYPE.SETTYPE);
			announcement_play(i18n_get("notes_set_type", ["NOTE", string(editor_select_count())]));
	    }
	    if(bind_down("editor_set_type_chain")) {
	    	with(objNote)
	    		if(stateType == NOTE_STATES.SELECTED)
			    	if(noteType < 2) {
			    		var _prop = get_prop();
			    		note_delete(noteID, true);
			    		_prop.noteType = 1;
			    		build_note(_prop, true, true, true);
			    	}
            operation_merge_last_request(1, OPERATION_TYPE.SETTYPE);
			announcement_play(i18n_get("notes_set_type", ["CHAIN", string(editor_select_count())]));
	    }

        if(bind_down("editor_duplicate_quick")) {
            editor_note_duplicate_quick();
        }
    }


    editorGridWidthEnabled = !ctrl_ishold();

    // Editor Side Switch
    if(bind_down("editor_side_next")) {      // Now only switch between front and dual-sides
        if(editorLRSide)
            editor_set_editside(0);
        else if(editor_get_editside() != 0)
            editor_set_editside(0);
        else
            editor_set_editside(3);
    }
    if(editorLRSide && !editorLRSideLock && !editor_select_is_area()) {
        editorSide = mouse_x*2 < BASE_RES_W? 1:2;
    }
    if(editorSide != editorLastSide) {
        _attach_sync_request = true;
    }
    
    // Editor Mode Switch
    for(var i=1; i<=5; i++)
        if(bind_choice("editor_mode", i)) {
            if(editorMode != i)
                _attach_reset_request = true;
            editor_set_editmode(i);
        }

    if(bind_down("editor_paste_mode_enter") && array_length(copyStack) && editorSelectCount == 0) {
        editorModeBeforeCopy = editorMode;
        editor_set_editmode(0); // Paste Mode
        _attach_reset_request = true;
    }
    if(bind_down("editor_escape")) {
        if(editorMode == 0) {
            editor_set_editmode(editorModeBeforeCopy);
            _attach_reset_request = true;
        }
        else {
            if(game_end_confirm())
                return;
        }
    }
    
    // Copies Mirror
    if(editorMode == 0) {
        if(bind_down("editor_paste_mirror")) {
            for(var i=0, l=array_length(copyStack); i<l; i++)
                copyStack[i].position = 5 - copyStack[i].position;
            _attach_reset_request = true;
        }
        if(bind_down("editor_paste_type_note")) {
            for(var i=0, l=array_length(copyStack); i<l; i++)
                copyStack[i].noteType = 0;
            _attach_reset_request = true;
        }
        if(bind_down("editor_paste_type_chain")) {
            for(var i=0, l=array_length(copyStack); i<l; i++)
                copyStack[i].noteType = 1;
            _attach_reset_request = true;
        }
    }

    // Sync or Destroy attached instance
    if(editorNoteAttaching != -1) {
        if(array_length(editorNoteAttaching) == 0 || !instance_exists(editorNoteAttaching[0])) {
        	if(singlePaste) {
        		editor_set_editmode(editorModeBeforeCopy);
            }
        	editorNoteAttaching = -1;
        }
        if(_attach_reset_request) {
            var i=0, l=array_length(editorNoteAttaching);
            for(; i<l; i++)
                instance_destroy(editorNoteAttaching[i]);
            editorNoteAttaching = -1;
            if(editorMode != 0) editorNoteAttachingCenter = 0;
        }
        if(_attach_sync_request) {
            if(!copyMultipleSides) {
                var i=0, l=array_length(editorNoteAttaching);
                for(; i<l; i++) {
                    editorNoteAttaching[i].change_side(editorSide);
                    if(editorMode != 0)
                        editorNoteAttaching[i].width = editor_get_default_width();
                }
            }
            else {
                var i=0, l=array_length(editorNoteAttaching);
                var _orig_side = l > 0 ? editor_get_note_attaching_center().side : 0;
                var _side_delta = editorSide - _orig_side;
                for(; i<l; i++) {
                    var _side = editorNoteAttaching[i].side;
                    if(editorLRSide && _orig_side > 0) {
                        if(_side > 0 && _side_delta != 0) {
                            _side = _side == 1?2:1;
                            editorNoteAttaching[i].change_side(_side);
                        }
                    }   // Flip the LR side.
                    else {
                        _side += 3 + _side_delta;
                        _side %= 3;
                        editorNoteAttaching[i].change_side(_side);
                    }   // Rotate clockwise
                    
                    if(editorMode != 0)
                        editorNoteAttaching[i].width = editor_get_default_width();
                }
            }
        }
    }
    
    editorLastSide = editorSide;
   

    switch editorMode {
        case 0:
            if(editorNoteAttaching == -1) {
                var _side_mask = 0;
                editorNoteAttaching = [];
                for(var i=0, l=array_length(copyStack); i<l; i++) {
                    var _str = copyStack[i];
                    _side_mask |= 1<<_str.side;
                    array_push(editorNoteAttaching, note_build_attach(
                        _str.noteType,
                        _str.side,
                        _str.width,
                        _str.position,
                        _str.time,
                        _str.lastTime
                        ));
                    if(_str.noteID == attachRequestCenterID) {
                        show_debug_message("Set attaching center.");
                        editorNoteAttachingCenter = i;
                        attachRequestCenterID = undefined;
                    }
                }
                if(_side_mask == 1 || _side_mask == 2 || _side_mask == 4) {
                    for (var i = 0; i < array_length(editorNoteAttaching); i ++) {
                        editorNoteAttaching[i].change_side(editor_get_editside())
                    }
                    copyMultipleSides = false;
                }
                else {
                    copyMultipleSides = true;
                }
            }
            
            // Change the attaching notes' center.
            var _chg = 0;
            _chg += bind_axis("editor_paste_center");
            _chg += alt_ishold() * (mouse_wheel_up() - mouse_wheel_down());
            var _len = array_length(editorNoteAttaching);
            editorNoteAttachingCenter = (editorNoteAttachingCenter + _chg + _len) % _len; 
            if(copyMultipleSides && !editorLRSide)
                editor_set_editside(editor_get_note_attaching_center().side, true);
            
            break;
        case 1:
        case 2:
        case 3:
            if(editorNoteAttaching == -1) {
                editorNoteAttaching = [note_build_attach(editorMode - 1, editorSide, editor_get_default_width())];
                editorNoteAttachingCenter = 0;
            }
            break;
            
        case 4:
        default:
            break;
    }
    
    // Copy

    if(bind_down("editor_copy"))
    	copy();
    if(bind_down("editor_cut"))
    	cut();
    if(copyRequest || cutRequest || attachRequest) {
        var _cnt = 0;
        var _newCopyStack = [];
        _newCopyStack = [];
        with(objNote) {
            if(stateType == NOTE_STATES.SELECTED && noteType <= 2) {
                array_push(_newCopyStack, get_prop());
                _cnt ++;
                if(objEditor.cutRequest || objEditor.attachRequest) {
                    note_delete(noteID, true);
                }
            }
        }
        array_sort(_newCopyStack, function (_a, _b) { 
            return sign(_a.time == _b.time? _a.position - _b.position : _a.time - _b.time); });
        
        if(_cnt == 0) {
            attachRequestCenterID = undefined;
            singlePaste = false;
        }
        else {
        	copyStack = _newCopyStack;
        	if(cutRequest) {
	            announcement_play(i18n_get("cut_notes", string(_cnt)));
                operation_merge_last_request(1, OPERATION_TYPE.CUT);
            }
	        else if(copyRequest)
	            announcement_play(i18n_get("copy_notes", string(_cnt)));
	        else if(attachRequest) {
	            editor_set_editmode(0);
	            operation_merge_last_request(2, OPERATION_TYPE.ATTACH);
	        }
        }
        
    }
    cutRequest = 0;
    copyRequest = 0;
    attachRequest = 0;

#endregion

#region Sync to DyCore

dyc_editor_sync_states(
    { editMode: editorMode }
);

#endregion