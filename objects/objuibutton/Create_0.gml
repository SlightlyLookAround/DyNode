
content = variable_instance_get(id, "content");
scale = variable_instance_get(id, "scale");

fontColor = c_white;
scriElement = scribble(cjk_prefix()+i18n_get(content))
    .starting_format("fDynamix16", fontColor)
    .transform(scale, scale)
    .align(fa_left, fa_top);
scriHeight = scriElement.get_height();

gradAlpha = 0;
gradMin = 0.05;
animTargetGradAlpha = 0;
animSpeed = 0.2;
shadowDistance = 3;

eventFunc = function () {
    announcement_play("按钮 "+content+" 被按下了 lol");
}

// [GMRT-WA-15767] 变通实现：原先写在房间实例上的「实例创建代码」。
// GMRT 0.22.x 有 bug（YoYo #15767）：项目里只要有实例创建代码，加载 WAD 时就会崩溃，
// 所以把每个实例的差异改由变量定义控制：
//   xRatio      —— 默认 -1（保持房间编辑器里的 x）；需要按屏幕比例定位的实例填 0.05
//   eventAction —— 默认 ""（沿用上面的默认回调）；点击行为不同的实例填对应动作名
// 说明与还原步骤见 notes/GMRT-15767-workaround.md。GMRT 修复后请按该文档还原。
var _xRatio = variable_instance_get(id, "xRatio");
if (is_real(_xRatio) && _xRatio >= 0)
    x = resor_to_x(_xRatio);

switch (variable_instance_get(id, "eventAction")) {
    // 返回上一页（rCredits、rProjectInit 里的返回按钮）。
    case "go_back":
        eventFunc = function () {
            room_goto(rStartPage);
        };
        break;

    // 项目创建页：确认后校验输入并进入主界面。
    case "project_create":
        eventFunc = function () {
            var _mus = objUIInputManager.get_input("music");
            var _title = objUIInputManager.get_input("title");
            var _ltype = objUIInputManager.get_input("leftType");
            var _rtype = objUIInputManager.get_input("rightType");
            var _bg = objUIInputManager.get_input("background");
            var _chart = objUIInputManager.get_input("chart");
            var _difficulty = objUIInputManager.get_input("difficulty");
            if(_mus == "" && (_chart == "" || filename_ext(_chart) != ".dy")) {
                announcement_error("need_a_music_file_error");
                return;
            }

            objManager.initVars = {
                mus: _mus,
                title: _title,
                ltype: _ltype,
                rtype: _rtype,
                bg: _bg,
                chart: _chart,
                diff: _difficulty
            };
            room_goto(rMain);
        };
        break;

    // 起始页：进入「项目创建」页。
    case "project_new":
        eventFunc = function () {
            room_goto(rProjectInit);
        };
        break;

    // 起始页：以工程文件方式直接打开。
    case "project_open":
        eventFunc = function () {
            objManager.initWithProject = true;
            room_goto(rMain);
        };
        break;

    // 起始页：关于 / 制作人员名单。
    case "about":
        eventFunc = function () {
            room_goto(rCredits);
        };
        break;
}
