
display_reset(4, true);

// Prefetch the large dynamic font texture group into vram.
texturegroup_load("texFonts", true);

typist = scribble_typist().in(1, 10);
timer = 0;

logoAlpha = 0;
logoFadeInTime = 0.4;   // in seconds
logoDelayTime = 0.2;

// [GMRT-WA-15767] GMRT 0.22.x 还没有实现矢量图（SVG）抗锯齿这三个函数，直接调用会在启动时报
// "ReferenceError: draw_get_svg_aa_level is not defined"，所以用开关包起来：
// GMRT 下保持 false（跳过；矢量图不启用抗锯齿）；以后用 GMS2/YYC 构建并想恢复抗锯齿时改成 true。
// 说明与还原步骤见 notes/GMRT-15767-workaround.md。
var _gmrtSvgAA = false;
if (_gmrtSvgAA)
{
    if (draw_get_svg_aa_level() == 0)
    {
        draw_enable_svg_aa(true);
        draw_set_svg_aa_level(1);
    }
}
