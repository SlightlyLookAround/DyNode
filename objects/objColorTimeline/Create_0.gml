/// @description Color timeline panel — lists color keyframes, lets the user add/edit/delete them.

persistent = false;

scroll = 0;
scrollTarget = 0;
rowH = 36;
panelW = 900;
panelH = 700;
x0 = (BASE_RES_W - panelW) / 2;
y0 = max(20, (BASE_RES_H - panelH) / 2);
titleH = 56;
btnH = 40;
btnY = y0 + titleH + 10;
listY = btnY + btnH + 18;
listH = panelH - (listY - y0) - 60;
footerY = y0 + panelH - 30;

// Buttons
buttons = [];
var _defs = [
    ["toggle", 160],
    ["add", 180],
    ["clear", 180],
    ["close", 140],
];
var _bx = x0 + 28;
for(var i = 0; i < array_length(_defs); i++) {
    array_push(buttons, {
        kind: _defs[i][0],
        x: _bx,
        y: btnY,
        w: _defs[i][1],
        h: btnH
    });
    _bx += _defs[i][1] + 14;
}

// Close button (X) top-right
closeBtnX = x0 + panelW - 40;
closeBtnY = y0 + titleH / 2;
closeBtnR = 18;

// Cached keyframe list
entries = [];
_maxScroll = 0;

function _refresh_entries() {
    entries = dyc_color_keyframes_get_all();
    _maxScroll = max(0, array_length(entries) * rowH - listH);
}

_refresh_entries();
