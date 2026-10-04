event_inherited();

fType = variable_instance_get(id, "fType");
filter = variable_instance_get(id, "filter");
fname = variable_instance_get(id, "fname");
dir = filename_drive(program_directory);
fTitle = variable_instance_get(id, "fTitle");

maxWidth = 0.5*BASE_RES_W;

// [GMRT-WA-15767] 变通实现：原先写在房间实例上的「实例创建代码」。
// GMRT 0.22.x 有 bug（YoYo #15767）：项目里只要有实例创建代码，加载 WAD 时就会崩溃，
// 所以把代码移到对象事件里，改由变量定义 xRatio 控制（默认 -1 = 保持房间编辑器里的 x）。
// 说明与还原步骤见 notes/GMRT-15767-workaround.md。GMRT 修复后请按该文档还原。
var _xRatio = variable_instance_get(id, "xRatio");
if (is_real(_xRatio) && _xRatio >= 0)
    x = resor_to_x(_xRatio);
