/// @description Difficulty-diff storage ("存储不同难度差分").
/// Stores multiple chart difficulties inside one .dyn project and switches
/// between them with Ctrl+O / Ctrl+P once the feature is enabled.
///
/// Feature flag follows the dyn project file:
/// - enabled: master switch (O+P toggles it only while not locked)
/// - created: locked after the first difficulty difference is created
/// Undo stacks are independent per difficulty and live only in memory.

#macro DIFF_STORAGE_META_KEY "difficultyDiff"

function diff_storage_init() {
    global.diffStorageEnabled = false;
    global.diffStorageCreated = false;
    global.diffStorageUndo = {};
    global.diffStorageChordPrev = false;
    global.diffStorageDeletePrev = false;
    // Alt+1..6 semi-transparent preview of another difficulty chart.
    global.diffPreviewActive = -1;
    global.diffPreviewNotes = [];
    global.diffPreviewCacheMin = 0;
    global.diffPreviewCacheMax = 0;
    global.diffPreviewAnnoId = "diff_storage_preview";
    global.diffPreviewGhosts = [];
    global.diffPreviewEditMode = -1;
}

#macro DIFF_PREVIEW_ALPHA 0.3

function diff_storage_get_meta() {
    var _index = 0;
    try {
        _index = dyc_project_get_current_chart_index();
    } catch (e) {
        _index = 0;
    }
    return {
        enabled: global.diffStorageEnabled,
        created: global.diffStorageCreated,
        activeIndex: _index
    };
}

function diff_storage_apply_meta(meta) {
    if(!is_struct(meta)) {
        global.diffStorageEnabled = false;
        global.diffStorageCreated = false;
        return;
    }
    global.diffStorageEnabled = variable_struct_exists(meta, "enabled") ? meta.enabled : false;
    global.diffStorageCreated = variable_struct_exists(meta, "created") ? meta.created : false;
}

function diff_storage_diff_name(diff) {
    return difficulty_num_to_name(diff);
}

function diff_storage_is_enabled() {
    return global.diffStorageEnabled;
}

function diff_storage_is_locked() {
    return global.diffStorageCreated;
}

// ---------------- Undo stacks (in-memory, per difficulty) ----------------

function diff_storage_undo_key(index) {
    return string(index);
}

function diff_storage_undo_reset_all() {
    global.diffStorageUndo = {};
}

function diff_storage_undo_save_current() {
    if(!instance_exists(objEditor)) return;
    var _index = dyc_project_get_current_chart_index();
    var _key = diff_storage_undo_key(_index);
    global.diffStorageUndo[$ _key] = {
        stack: objEditor.operationStack,
        pointer: objEditor.operationPointer,
        count: objEditor.operationCount
    };
}

function diff_storage_undo_clear_at(index) {
    var _key = diff_storage_undo_key(index);
    if(variable_struct_exists(global.diffStorageUndo, _key))
        variable_struct_remove(global.diffStorageUndo, _key);
}

function diff_storage_undo_load(index) {
    if(!instance_exists(objEditor)) return;
    var _key = diff_storage_undo_key(index);
    if(variable_struct_exists(global.diffStorageUndo, _key)) {
        var _saved = global.diffStorageUndo[$ _key];
        objEditor.operationStack = _saved.stack;
        objEditor.operationPointer = _saved.pointer;
        objEditor.operationCount = _saved.count;
    } else {
        objEditor.operationStack = [];
        objEditor.operationPointer = -1;
        objEditor.operationCount = 0;
    }
    objEditor.operationStackStep = [];
    objEditor.operationMergeLastRequest = 0;
    objEditor.operationMergeLastRequestCount = 0;
    objEditor.operationMergeLastRequestType = undefined;
    objEditor.operationSyncTime = [INF, -INF];
}

// ---------------- GML-side chart visual/state refresh ----------------

function diff_storage_cleanup_gml_notes() {
    instance_destroy(objNote);
    global.noteIDMan.clear();
    global.activationMan.clear();
    dyc_active_props_cache_invalidate();
    if(instance_exists(objMain)) {
        objMain.chartNotesArrayAt = 0;
        objMain.chartNotesArrayActivated = [[], [], []];
        objMain.nowCombo = 0;
    }
    if(instance_exists(objEditor)) {
        note_select_reset();
        objEditor.editorSelectCount = 0;
        objEditor.editorSelectMultiple = false;
        objEditor.editorSelectOccupied = false;
        objEditor.editorSelectDragOccupied = false;
        objEditor.editorSelectArea = false;
        objEditor.editorSelectAreaPosition = undefined;
        objEditor.editorSelectSingleTarget = -999;
        objEditor.editorSelectSingleTargetInbound = -999;
        objEditor.editorSelectedSingleInbound = -999;
        objEditor.editorSelectedSingleInboundLast = -999;
        objEditor.editorNoteAttaching = -1;
        objEditor.copyStack = [];
        objEditor.copyRequest = false;
        objEditor.cutRequest = false;
        objEditor.attachRequest = false;
        objEditor.noteSortRequest = true;
    }
}

function diff_storage_sync_chart_vars() {
    if(!instance_exists(objMain)) return;
    var _metadata = dyc_chart_get_metadata();
    if(!is_struct(_metadata)) return;
    objMain.chartTitle = _metadata.title;
    objMain.chartDifficulty = _metadata.difficulty;
    objMain.chartSideType = _metadata.sideType;
}

/// Switch the editor to an already-stored difficulty-diff chart index.
function diff_storage_load(index, silent = false) {
    index = floor(index);
    var _count = dyc_project_get_chart_count();
    if(index < 0 || index >= _count) return false;

    var _prevIndex = dyc_project_get_current_chart_index();
    if(index == _prevIndex) {
        diff_storage_sync_chart_vars();
        return true;
    }

    // Persist live edits of the outgoing chart, then swap undo stacks.
    dyc_project_update_current_chart();
    diff_storage_undo_save_current();

    diff_storage_cleanup_gml_notes();

    if(dyc_project_set_current_chart(index) < 0) {
        announcement_error(i18n_get("diff_storage_switch_failed"));
        return false;
    }

    diff_storage_cleanup_gml_notes();
    diff_storage_undo_load(index);
    diff_storage_sync_chart_vars();

    var _diff = objMain.chartDifficulty;
    var _name = diff_storage_diff_name(_diff);
    if(!silent)
        announcement_play(i18n_get("diff_storage_switched", _name), 3000, "diff_storage_switch");
    return true;
}

// ---------------- Feature toggle (O+P) ----------------

function diff_storage_toggle() {
    if(!instance_exists(objMain)) return;

    if(global.diffStorageEnabled) {
        if(global.diffStorageCreated) {
            announcement_warning(i18n_get("diff_storage_cannot_disable"), 6000);
            return;
        }
        global.diffStorageEnabled = false;
        announcement_play(i18n_get("diff_storage_toggle_off"), 3000, "diff_storage_toggle");
        return;
    }

    global.diffStorageEnabled = true;
    announcement_play(i18n_get("diff_storage_toggle_on"), 3000, "diff_storage_toggle");
}

// ---------------- Ctrl+O / Ctrl+P flow ----------------

/// @param {Real} delta +1 for Ctrl+P (next), -1 for Ctrl+O (prev)
function diff_storage_on_difficulty_axis(delta) {
    if(delta == 0) return;

    if(!global.diffStorageEnabled) {
        // Original indicator-only behavior.
        var _diff = objMain.chartDifficulty + delta;
        _diff = clamp(_diff, 0, global.difficultyCount - 1);
        objMain.chartDifficulty = _diff;
        dyc_chart_set_difficulty(_diff);
        return;
    }

    var _current = objMain.chartDifficulty;
    var _target = clamp(_current + delta, 0, global.difficultyCount - 1);
    if(_target == _current) return;

    var _existing = dyc_project_find_chart_by_difficulty(_target);
    if(_existing >= 0) {
        diff_storage_load(_existing);
        return;
    }

    // Direction of this navigation step: +1 next / -1 previous.
    diff_storage_create_flow(_target, _current, delta > 0 ? 1 : -1);
}

/// Scan further along the same navigation direction for an existing chart.
/// @param {Real} targetDiff Difficulty slot that does not exist yet.
/// @param {Real} direction +1 = search upward, -1 = search downward.
/// @returns {Real} Nearest existing difficulty in that direction, or -1.
function diff_storage_find_existing_in_direction(targetDiff, direction) {
    var _d = targetDiff + direction;
    while(_d >= 0 && _d < global.difficultyCount) {
        if(dyc_project_find_chart_by_difficulty(_d) >= 0)
            return _d;
        _d += direction;
    }
    return -1;
}

function diff_storage_create_flow(targetDiff, sourceDiff, direction = 1) {
    var _targetName = diff_storage_diff_name(targetDiff);
    var _sourceName = diff_storage_diff_name(sourceDiff);
    var _nearbyDiff = diff_storage_find_existing_in_direction(targetDiff, direction);

    // Step 1: ask whether to create this difficulty in the project.
    // If a farther chart already exists in the same direction, "No" jumps to it
    // instead of aborting (so deleted middle difficulties do not trap navigation).
    if(_nearbyDiff >= 0) {
        var _nearbyName = diff_storage_diff_name(_nearbyDiff);
        var _skipKey = direction < 0
            ? "diff_storage_q_skip_prev"
            : "diff_storage_q_skip_next";
        var _msg = i18n_get("diff_storage_q_create", _targetName)
            + "\n" + i18n_get(_skipKey, [_nearbyName, _targetName]);
        var _q1 = dyc_show_question_ync(_msg);
        if(_q1 < 0) return; // Cancel aborts the whole flow.
        if(_q1 == 0) {
            // No = jump to the existing farther difficulty, create nothing.
            var _nearbyIndex = dyc_project_find_chart_by_difficulty(_nearbyDiff);
            if(_nearbyIndex >= 0)
                diff_storage_load(_nearbyIndex);
            return;
        }
        // Yes = continue into the create flow below.
    } else {
        var _q1b = dyc_show_question(i18n_get("diff_storage_q_create", _targetName));
        if(!_q1b) return;
    }

    // Step 2: yes = copy current, no = blank (keep timing points), cancel = abort.
    var _q2 = dyc_show_question_ync(i18n_get("diff_storage_q_based_on", [_sourceName]));
    if(_q2 < 0) return;
    var _copyFromCurrent = _q2 > 0;

    var _newIndex = dyc_project_create_chart(targetDiff, _copyFromCurrent);
    if(_newIndex < 0) {
        announcement_error(i18n_get("diff_storage_create_failed", _targetName));
        return;
    }

    // Fresh difficulty difference always starts with an empty undo stack.
    diff_storage_undo_clear_at(_newIndex);
    diff_storage_load(_newIndex, true);

    var _successMsg = _copyFromCurrent
        ? i18n_get("diff_storage_created_from", [_sourceName, _targetName])
        : i18n_get("diff_storage_created_blank", _targetName);
    announcement_play(_successMsg, 5000, "diff_storage_create");

    if(!global.diffStorageCreated) {
        global.diffStorageCreated = true;
        announcement_warning(i18n_get("diff_storage_first_create_notice"), 8000, "diff_storage_first");
    }
}

// ---------------- F10: export independent dyn ----------------

function diff_storage_export_independent() {
    if(!global.diffStorageEnabled) {
        announcement_warning(i18n_get("diff_storage_export_disabled"), 4000);
        return;
    }
    if(!instance_exists(objMain)) return;

    var _diff = dyc_chart_get_difficulty();
    if(_diff == undefined) _diff = objMain.chartDifficulty;
    var _name = diff_storage_diff_name(_diff);
    var _defaultFile = map_get_alt_title() + "_" + difficulty_num_to_char(_diff) + "_independent.dyn";
    var _file = dyc_get_save_filename(
        "DyNode File (*.dyn)|*.dyn",
        _defaultFile,
        program_directory,
        "Export Independent Project 导出独立工程文件");
    if(_file == "") return;

    dyc_project_update_current_chart();
    var _result = DyCore_project_export_current_as_single(_file, DYCORE_COMPRESSION_LEVEL);
    if(_result < 0) {
        announcement_error(i18n_get("diff_storage_export_failed", _name));
        return;
    }
    announcement_play(i18n_get("diff_storage_export_success", _name), 5000, "diff_storage_export");
}

// ---------------- Shift+Delete: delete current difficulty difference ----------------

function diff_storage_delete_current() {
    if(!global.diffStorageEnabled) {
        announcement_warning(i18n_get("diff_storage_delete_disabled"), 4000);
        return;
    }
    if(!global.diffStorageCreated) {
        announcement_warning(i18n_get("diff_storage_delete_none"), 4000);
        return;
    }

    var _count = dyc_project_get_chart_count();
    if(_count <= 1) {
        announcement_warning(i18n_get("diff_storage_delete_last"), 4000);
        return;
    }

    var _oldIndex = dyc_project_get_current_chart_index();
    var _oldMeta = dyc_chart_get_metadata();
    var _oldName = is_struct(_oldMeta)
        ? diff_storage_diff_name(_oldMeta.difficulty)
        : diff_storage_diff_name(objMain.chartDifficulty);

    // Deleting a difficulty difference is not undoable — drop its undo stack.
    diff_storage_undo_clear_at(_oldIndex);
    // Do not keep the outgoing chart's live edits; the chart itself is removed.
    diff_storage_cleanup_gml_notes();

    var _newIndex = DyCore_project_delete_current_chart();
    if(_newIndex < 0) {
        announcement_error(i18n_get("diff_storage_delete_failed", _oldName));
        return;
    }

    diff_storage_cleanup_gml_notes();
    // Deleted chart's undo stack is gone; restore the adjacent chart's stack.
    // Note: delete_current_chart already loaded notes/timing for the new index.
    // We must not call set_current_chart again (would double-load); just sync UI.
    if(instance_exists(objEditor))
        diff_storage_undo_load(_newIndex);
    diff_storage_sync_chart_vars();

    var _newName = diff_storage_diff_name(objMain.chartDifficulty);
    announcement_play(i18n_get("diff_storage_deleted", [_oldName, _newName]), 5000, "diff_storage_delete");
}

// ---------------- Per-frame keybind polling ----------------

function diff_storage_step() {
    if(!instance_exists(objMain)) return;

    // O+P chord: edge-triggered feature toggle.
    var _chord = bind_chord("main_diff_storage_toggle");
    if(_chord && !global.diffStorageChordPrev)
        diff_storage_toggle();
    global.diffStorageChordPrev = _chord;

    // F10: export independent dyn (only when the feature switch is on).
    if(global.diffStorageEnabled && bind_down("main_diff_storage_export"))
        diff_storage_export_independent();

    // Shift+Delete: delete current difficulty difference.
    var _del = bind_down("main_diff_storage_delete");
    if(_del && !global.diffStorageDeletePrev)
        diff_storage_delete_current();
    global.diffStorageDeletePrev = _del;

    diff_storage_preview_step();
}

// ---------------- Alt+1..6 difficulty preview overlay ----------------

/// Left Alt only (right Alt keeps its existing bindings).
function diff_storage_lalt_held() {
    if(!variable_global_exists("__InputManager")) return false;
    if(global.__InputManager.is_frozen()) return false;
    if(!keyboard_check(vk_lalt)) return false;
    // If only right Alt is down, vk_lalt may still report on some layouts.
    if(keyboard_check(vk_ralt) && !keyboard_check(vk_lalt)) return false;
    return true;
}

function diff_storage_preview_clear(hideAnno = true) {
    if(global.diffPreviewActive < 0 && array_length(global.diffPreviewNotes) == 0
        && array_length(global.diffPreviewGhosts) == 0)
        return;
    global.diffPreviewActive = -1;
    global.diffPreviewNotes = [];
    global.diffPreviewCacheMin = 0;
    global.diffPreviewCacheMax = 0;
    global.diffPreviewEditMode = -1;
    diff_storage_preview_destroy_ghosts();
    dyc_clear_diff_preview_notes();
    if(hideAnno && variable_global_exists("announcementMan"))
        announcement_play("", 1, global.diffPreviewAnnoId);
}

function diff_storage_preview_destroy_ghosts() {
    if(!variable_global_exists("diffPreviewGhosts")) return;
    var g = global.diffPreviewGhosts;
    for(var i=0; i<array_length(g); i++)
        if(instance_exists(g[i]))
            instance_destroy(g[i]);
    global.diffPreviewGhosts = [];
}

/// Edit-mode ghosts: real note instances drawn through the normal draw_event
/// with fade-other-notes alpha (0.5), so they look identical to live notes.
function diff_storage_preview_rebuild_ghosts() {
    diff_storage_preview_destroy_ghosts();
    if(global.diffPreviewActive < 0) return;
    if(!instance_exists(objMain)) return;

    var _notes = global.diffPreviewNotes;
    var _ghosts = [];
    for(var i=0; i<array_length(_notes); i++) {
        var n = _notes[i];
        if(!is_struct(n)) continue;
        if(n.noteType == 3) continue;
        // Cull far-off-screen notes to keep instance count reasonable.
        var _y = note_time_to_y(n.time, n.side);
        if(n.side == 0 && (_y > BASE_RES_H + 120 || _y < -120 - n.lastTime * objMain.playbackSpeed))
            continue;

        var _obj = _note_get_object_asset(n.noteType);
        var inst = instance_create_depth(0, 0, 5, _obj);
        inst.isDiffPreview = true;
        inst.noteType = n.noteType;
        inst.side = n.side;
        inst.time = n.time;
        inst.width = n.width;
        inst.position = n.position;
        inst.lastTime = n.lastTime;
        inst.beginTime = n.time;
        inst.noteID = "";
        inst.subNoteID = "";
        inst.sinst = -999;
        inst.finst = -999;
        inst.selectTolerance = false;
        inst.attaching = false;
        inst.selectInbound = false;
        inst.drawVisible = true;
        inst.image_alpha = DIFF_PREVIEW_ALPHA;
        inst.animTargetA = DIFF_PREVIEW_ALPHA;
        inst.lastAlpha = DIFF_PREVIEW_ALPHA;
        inst.animTargetLstA = DIFF_PREVIEW_ALPHA;
        inst._prop_init(true);
        if(n.noteType == 2) {
            inst.pHeight = max(inst.originalHeight,
                objMain.playbackSpeed * max(n.lastTime, 0)
                + inst.dFromBottom + inst.uFromTop);
        }
        array_push(_ghosts, inst);
    }
    global.diffPreviewGhosts = _ghosts;
}

/// Visible time window for the current playview (with a small margin).
function diff_storage_preview_time_range() {
    var _spd = max(objMain.playbackSpeed, 0.05);
    var _ahead = (BASE_RES_H + 240) / _spd;
    var _behind = (objMain.targetLineBelow + objMain.targetLineBelowH + 240) / _spd;
    return [objMain.nowTime - _behind, objMain.nowTime + _ahead];
}

function diff_storage_preview_apply_notes() {
    // Playback mode uses the C++ note renderer (same sprites/geometry, alpha*0.5).
    // Edit mode uses real note instances + draw_event (identical to faded notes).
    dyc_set_diff_preview_notes(global.diffPreviewNotes, DIFF_PREVIEW_ALPHA);
    var _em = editor_get_editmode();
    global.diffPreviewEditMode = _em;
    if(_em < 5 && _em >= 0)
        diff_storage_preview_rebuild_ghosts();
    else
        diff_storage_preview_destroy_ghosts();
}

function diff_storage_preview_step() {
    if(!variable_global_exists("diffPreviewActive")) return;
    if(!instance_exists(objMain)) {
        diff_storage_preview_clear();
        return;
    }

    // Requires difficulty-diff charts to exist in this project.
    if(!global.diffStorageEnabled || !global.diffStorageCreated
        || dyc_project_get_chart_count() <= 1) {
        diff_storage_preview_clear();
        return;
    }

    if(!diff_storage_lalt_held()) {
        diff_storage_preview_clear();
        return;
    }

    // Collect held 1..6 (main row + numpad). Exactly one required.
    var _held = -1;
    var _heldCount = 0;
    for(var i=0; i<6; i++) {
        var _k = ord("1") + i;
        var _nk = vk_numpad1 + i;
        if(keyboard_check(_k) || keyboard_check(_nk)) {
            _held = i;
            _heldCount ++;
        }
    }
    // 0 keys or 2+ keys (e.g. Alt+1+2) → no preview.
    if(_heldCount != 1 || _held < 0) {
        diff_storage_preview_clear();
        return;
    }

    var _diff = _held;
    if(_diff == objMain.chartDifficulty) {
        diff_storage_preview_clear();
        return;
    }
    if(dyc_project_find_chart_by_difficulty(_diff) < 0) {
        diff_storage_preview_clear();
        return;
    }

    var _range = diff_storage_preview_time_range();
    var _needFetch = (global.diffPreviewActive != _diff)
        || (_range[0] < global.diffPreviewCacheMin)
        || (_range[1] > global.diffPreviewCacheMax);

    if(_needFetch) {
        // Fetch a wider window so scrolling does not re-query every frame.
        var _pad = (_range[1] - _range[0]) * 0.25 + 200;
        var _min = _range[0] - _pad;
        var _max = _range[1] + _pad;
        global.diffPreviewNotes = dyc_project_get_diff_preview_notes(
            _diff, _min, _max, true);
        global.diffPreviewCacheMin = _min;
        global.diffPreviewCacheMax = _max;
        global.diffPreviewActive = _diff;
        diff_storage_preview_apply_notes();
    } else {
        // Rebuild edit-mode ghosts if the editor mode changed while held.
        var _em = editor_get_editmode();
        if(global.diffPreviewEditMode != _em) {
            global.diffPreviewEditMode = _em;
            if(_em < 5 && _em >= 0)
                diff_storage_preview_rebuild_ghosts();
            else
                diff_storage_preview_destroy_ghosts();
            dyc_set_diff_preview_notes(global.diffPreviewNotes, DIFF_PREVIEW_ALPHA);
        }
    }

    var _msg = i18n_get("diff_storage_previewing", diff_storage_diff_name(_diff));
    announcement_play(_msg, 2500, global.diffPreviewAnnoId);
}

/// Draw preview notes under live notes.
/// Edit mode: call each ghost instance's draw_event (same as real/faded notes).
/// Playback mode: C++ renderer already includes preview notes with alpha 0.5.
function diff_storage_preview_draw() {
    if(!variable_global_exists("diffPreviewActive")) return;
    if(global.diffPreviewActive < 0) return;
    if(!instance_exists(objMain)) return;
    if(editor_get_editmode() >= 5) return; // handled by C++ note renderer

    var _ghosts = global.diffPreviewGhosts;
    for(var i=0; i<array_length(_ghosts); i++) {
        var inst = _ghosts[i];
        if(!instance_exists(inst)) continue;
        inst.image_alpha = DIFF_PREVIEW_ALPHA;
        inst.lastAlpha = DIFF_PREVIEW_ALPHA;
        inst.drawVisible = true;
        // Keep geometry in sync with current nowTime / playbackSpeed.
        inst._prop_init(true);
        if(inst.noteType == 2) {
            inst.pHeight = max(inst.originalHeight,
                objMain.playbackSpeed * max(inst.lastTime, 0)
                + inst.dFromBottom + inst.uFromTop);
            with(inst) {
                draw_event(false);
                draw_event(true);
            }
        } else {
            with(inst) draw_event();
        }
    }
}
