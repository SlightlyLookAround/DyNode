/// @description Reset Tags & Time Update & Activate notes

// Pull metadata from DyCore.

var _metadata = dyc_chart_get_metadata();
chartTitle = _metadata.title;
chartDifficulty = _metadata.difficulty;
chartSideType = _metadata.sideType;

#region TIME UPDATE

// Music Speed Adjust

    var _muspdchange = bind_axis("main_music_speed");
    if(_muspdchange != 0) {
        musicSpeed += 0.1 * _muspdchange;
        musicSpeed = max(musicSpeed, 0.1);
        _set_channel_speed(musicSpeed);
        
        announcement_play(i18n_get("anno_music_speed") + ": x" + string_format(musicSpeed, 1, 1), 3000, "music_speed");
    }

// Keyboard Time & Speed Adjust

    var _spdchange = bind_axis("main_note_speed");
    _spdchange += editor_select_is_going()? 0: wheelcheck_up_ctrl() - ((animTargetPlaybackSpeed > 0.2) * wheelcheck_down_ctrl());
    animTargetPlaybackSpeed += 0.1 * _spdchange;
    
    if(_spdchange != 0) {
    	announcement_play(i18n_get("anno_note_speed") + ": x" + string_format(animTargetPlaybackSpeed, 1, 2), 3000, "anno_note_speed");
    	
    	if(animTargetPlaybackSpeed == 0.2 && _spdchange < 0)
    		announcement_warning("anno_note_speed_warn");
    }
    
    playbackSpeed = lerp_a(playbackSpeed, animTargetPlaybackSpeed, animSpeed);
    
    var _timchange = bind_axis("main_time_scroll");
    var _timscr = wheelcheck_up() - wheelcheck_down();
    _timchange += 3 * bind_axis("main_time_scroll_shift");
    _timchange += 0.2 * bind_axis("main_time_scroll_fine");   // fine scroll: 0.2x adtimeSpeed (10ms/frame)

    if(_timchange != 0 || _timscr != 0) {
        if(nowPlaying) {
            nowTime += (_timchange * adtimeSpeed * global.timeManager.get_fps_scale() + _timscr * scrolltimeSpeed);
            musicResyncRequest = true;
        }
        else {
            animTargetTime += (_timchange * adtimeSpeed * global.timeManager.get_fps_scale() + _timscr * scrolltimeSpeed);
        }
    }

    if(nowPlaying && bind_down("main_replay_to_start")) {
    	nowTime = -PLAYBACK_EMPTY_TIME;
    	musicResyncRequest = true;
    }

// Time Operation

    if(nowPlaying && !(_timchange != 0 || _timscr != 0)) {
        var dT = global.timeManager.get_delta(-1, false) / 1000;
        if(!global.recordManager.is_recording())
            dT *= musicSpeed;
    	nowTime += dT;

        // Audio offset correction.
        if(!global.recordManager.is_recording()) {
            var curOffset = nowTime - sfmod_channel_get_position(channel);
            if(abs(curOffset) > 15 && abs(curOffset) < 50) {
                nowTime += -curOffset * 0.05;
                // if(DEBUG_MODE)
                //     show_debug_message("Add offset correction: " + string(-curOffset * 0.05) + " ms");
            }
        }
    }
    
        
    if(music != undefined) {
        // Play music at chart's beginning
        if(nowTime < 0) {
            FMODGMS_Chan_PauseChannel(channel);
            sfmod_channel_set_position(0, channel, sampleRate);
            channelPaused = true;
        }
        else if(nowPlaying && channelPaused && !global.recordManager.is_recording()) {
            FMODGMS_Chan_ResumeChannel(channel);
            sfmod_channel_set_position(nowTime, channel, sampleRate);
            channelPaused = false;
        }
        
        // Top Bar Adjust Part
        
    		topBarMouseInbound = (mouse_y <= topBarMouseH && mouse_y >= 0) || alt_ishold();
            topBarMouseInbound = topBarMouseInbound && editor_get_editmode() >= 4 && !global.__InputManager.is_frozen();
            if(topBarMouseInbound || topBarMousePressed || _timchange != 0 || _timscr != 0) {
            	animTargetTopBarIndicatorA = 0.3;
            	topBarTimeLastTime = 2000;
            }
            else
                animTargetTopBarIndicatorA = 0;
            
            topBarIndicatorA = lerp(topBarIndicatorA, 
                animTargetTopBarIndicatorA, animSpeed * global.timeManager.get_fps_scale());

            topBarTimeLastTime -= global.timeManager.get_delta() / 1000;
            if(editor_get_editmode() < 5) topBarTimeLastTime = 1;
        	
            animTargetTopBarTimeGradA = topBarMouseInbound || topBarMousePressed;
        	animTargetTopBarTimeA = topBarTimeLastTime > 0;
        	topBarTimeA = lerp_a(topBarTimeA, animTargetTopBarTimeA, 0.2);
        	topBarTimeGradA = lerp_a(topBarTimeGradA, animTargetTopBarTimeGradA, 0.2);
                
        
            if(mouse_check_button_pressed(mb_left) && topBarMouseInbound) {
                topBarMousePressed = true;
                topBarMouseLastX = -5;
            }
                
            
            if(topBarMousePressed) {
            	mouse_clear_hold(); // Clear the Hold Buffer
                if(mouse_check_button_released(mb_left)) {
                	topBarMousePressed = false;
                	mouse_clear(mb_left);
                }
                    
                else {
                    if(nowPlaying) {
                        if(abs(topBarMouseLastX - mouse_x) >= 2) {
                            musicProgress = mouse_x / BASE_RES_W;
                            nowTime = musicProgress * musicLength;
                            musicResyncRequest = true;
                        }
                        topBarMouseLastX = mouse_x;
                    }
                    else {
                        musicProgress = mouse_x / BASE_RES_W;
                        animTargetTime = musicProgress * musicLength;
                    }
                }
            }
        
        // If music ends then stop
        if((FMODGMS_Chan_Is_Playing(channel)<=0 || nowTime >= musicLength) && nowPlaying) {
        	
            // Channel gets invalid, create another one.
            _create_channel();
            FMODGMS_Snd_PlaySound(music, channel);
            _set_channel_speed(musicSpeed);
            FMODGMS_Chan_PauseChannel(channel);
            nowTime = musicLength;
            animTargetTime = musicLength;
            dyc_video_pause();
            
            nowPlaying = false;

            // Trigger playback end event
            if(editor_get_editmode() == 5)
            	on_playback_end();
        }
        
        musicProgress = clamp(nowTime, 0, musicLength) / musicLength;
        
        animTargetTime = clamp(animTargetTime, -timeBoundLimit, musicLength);
    }
    
    else {
        musicProgress = 0;
    }

// Update and Sync Time & musicTime

    if(nowPlaying) {
        if(music != undefined)
            nowTime = clamp(nowTime, -timeBoundLimit, musicLength);
        animTargetTime = nowTime;
    }
    else {
        nowTime = lerp_lim_a(nowTime, animTargetTime, animSpeed, 10000);
        
        if(abs(nowTime - animTargetTime) < 1)
            nowTime = animTargetTime; // Speeeed up
    }
    
    if(musicResyncRequest) {
        time_music_sync();
        musicResyncRequest = false;
    }

#endregion

#region Chart Properties Update

	// Adjust Difficulty
	var _diff_delta = bind_axis("main_difficulty");
	chartDifficulty += _diff_delta;
	chartDifficulty = clamp(chartDifficulty, 0, global.difficultyCount - 1);
    if(_diff_delta != 0)
        dyc_chart_set_difficulty(chartDifficulty);

    var noteCount = dyc_get_note_count();

    var _editMode = editor_get_editmode();

    if(_editMode == 5 && objMain.nowPlaying) {
        while(chartNotesArrayAt < noteCount &&
            dyc_get_note_time_at_index(chartNotesArrayAt) <= nowTime) {
                if(!note_hit(dyc_get_note_at_index(chartNotesArrayAt), true))
                    break;
                chartNotesArrayAt ++;
            }
    }
    
    chartNotesArrayAt = dyc_get_note_index_upperbound(nowTime);
	chartNotesArrayAt = clamp(chartNotesArrayAt, 0, noteCount);

#endregion

#region NOTES ACTIVATE & DEACTIVATE

    if(editor_get_editmode() < 5) {
        var _activeNotes = dyc_get_active_notes(objMain.nowTime, objMain.playbackSpeed);
        for(var i = 0; i < array_length(_activeNotes); i++) {
            var note = _activeNotes[i];
            note_check_and_activate(note);
        }
    }

#endregion