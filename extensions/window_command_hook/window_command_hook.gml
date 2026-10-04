#define window_command_hook_init
//#init window_command_hook_init
// [GMRT-WA-15767] 这几行原来是注释掉的 //#macro 指令，在 GMRT 下未定义的标识符会直接抛
// "window_command_close is not defined" 并崩溃（YYC 下未定义标识符会静默当 0，
// 所以没暴露出来），这里改成真正的宏定义，两个运行时都能用。
// 说明与还原步骤见 notes/GMRT-15767-workaround.md。
#macro window_command_close    $F060
#macro window_command_maximize $F030
#macro window_command_minimize $F020
#macro window_command_restore  $F120
#macro window_command_resize   $F000
#macro window_command_move     $F010

#define window_command_hook_prepare_buffer
/// (size:int)->buffer~
var _size = argument0;
gml_pragma("global", "global.__window_command_hook_buffer = undefined");
var _buf = global.__window_command_hook_buffer;
if (_buf == undefined) {
    _buf = buffer_create(_size, buffer_grow, 1);
    global.__window_command_hook_buffer = _buf;
} else if (buffer_get_size(_buf) < _size) {
    buffer_resize(_buf, _size);
}
buffer_seek(_buf, buffer_seek_start, 0);
return _buf;
