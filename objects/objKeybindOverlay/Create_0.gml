/// @description Read-only keybind list overlay (F12 toggle / hold H).

persistent = true;

holdMode = false;       // toggle mode blocks game input; hold mode lets the game run
scroll = 0;
scrollTarget = 0;
rowH = 34;
colW = 760;
colGap = 60;
marginX = 140;
titleH = 90;
listY = 120;
listH = BASE_RES_H - listY - 70;

// Column A: editor; Column B: main + global
colA = [];
colB = [];

function keybind_overlay_rebuild_lists() {
    colA = [];
    colB = [];
    var _ctxs = ["editor", "main", "global"];
    var _ids = keybind_action_ids();
    for(var c=0; c<array_length(_ctxs); c++) {
        var _target = c == 0 ? colA : colB;
        array_push(_target, { header: true, ctx: _ctxs[c], id: "" });
        for(var i=0; i<array_length(_ids); i++) {
            var _a = keybind_get_action(_ids[i]);
            if(_a != undefined && _a.context == _ctxs[c])
                array_push(_target, { header: false, ctx: _ctxs[c], id: _ids[i] });
        }
    }
    maxScroll = max(0, max(array_length(colA), array_length(colB)) * rowH - listH);
    maxRows = max(array_length(colA), array_length(colB));
}

keybind_overlay_rebuild_lists();

// Scrollbar drag state
scrollDragging = false;
scrollDragOffset = 0;

function _draw_keybind_column(_list, _cx) {
    var _accent = theme_get().color;
    var _top = listY - rowH / 2;
    var _bottom = listY + listH + rowH / 2;

    for(var i=0; i<array_length(_list); i++) {
        var _ey = listY + i * rowH + rowH / 2 - scroll;
        if(_ey < _top || _ey > _bottom) continue;

        var _e = _list[i];
        if(_e.header) {
            CleanLine(_cx, _ey + rowH / 2 - 4, _cx + colW, _ey + rowH / 2 - 4)
                .Blend(_accent, 0.6)
                .Cap(true, true)
                .Draw();
            var _hStr = keybind_text_cjk(i18n_get("kb_ctx_" + _e.ctx));
            scribble(_hStr, "KB_OL_H_" + _e.ctx)
                .starting_format("mSpaceMono", _accent)
                .align(fa_left, fa_middle)
                .scale(keybind_text_scale(_hStr), keybind_text_scale(_hStr))
                .draw(_cx, _ey);
            continue;
        }

        var _name = keybind_text_cjk(keybind_action_display_name(_e.id));
        var _nameCol = c_white;
        if(keybind_is_customized(_e.id)) _nameCol = _accent;
        scribble(_name, "KB_OL_N_" + _e.id + string(_nameCol))
            .starting_format("mSpaceMono", _nameCol)
            .align(fa_left, fa_middle)
            .scale(keybind_text_scale(_name), keybind_text_scale(_name))
            .draw(_cx, _ey);

        var _bind = keybind_text_cjk(keybind_binding_display(_e.id));
        var _bindCol = keybind_is_customized(_e.id) ? _accent : 0xbbbbbb;
        scribble(_bind, "KB_OL_B_" + _e.id + _bind)
            .starting_format("mSpaceMono", _bindCol)
            .align(fa_right, fa_middle)
            .scale(keybind_text_scale(_bind), keybind_text_scale(_bind))
            .draw(_cx + colW, _ey);
    }
}
