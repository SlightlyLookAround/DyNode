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
}

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
}
