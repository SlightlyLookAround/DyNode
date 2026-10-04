

// [GMRT-WA-15767] GMRT 0.22 下 texturegroup_load("texFonts", true) 的预取不会完成：
// 状态会从 loading(1) 掉回 unloaded(0)，永远等不到 texturegroup_status_fetched，
// 加载画面就会一直卡住（GMRT 只认 fetched）。这里放宽条件并加超时兜底。
// 说明与还原步骤见 notes/GMRT-15767-workaround.md。
texWait = texWait + delta_time / 1000000;
var _texStatus = texturegroup_get_status("texFonts");
if(_texStatus == texturegroup_status_fetched
|| _texStatus == texturegroup_status_loaded
|| texWait > 2) {
    instance_destroy();
    instance_create_depth(0, 0, 0, objManager);
}

if(delta_time < 1/20 * 1000000) {
    timer += delta_time / 1000000;
}
logoAlpha = clamp((timer - logoDelayTime) / logoFadeInTime, 0, 1);
