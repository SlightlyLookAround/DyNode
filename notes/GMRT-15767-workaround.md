# GMRT #15767 变通：把「实例创建代码」移到对象事件

> 变更分支：`codex/gmrt-15767-workaround`
> 代码标记：`[GMRT-WA-15767]`（用 `git grep -n GMRT-WA-15767` 可以找到所有改动点）

## 背景

GMRT 0.22.x（含 LTS2026 自带的 GMRT 0.22.4）有一个已知 bug：**项目里只要有「实例创建代码」
（房间编辑器里给单个实例写的 Creation Code），运行时加载 WAD 就会崩溃**，日志形如：

```
Loading WAD: D:\DYNSource\Build\build\assets\DyNode.Default.wad
Unhandled exception: Error: Failed to load script
  DyNode__rooms_x2F_rCredits_x2F_InstanceCreationCode_inst_1F0E7606 from wad
```

官方 bug 跟踪：[YoYoGames/GameMaker-Bugs#15767](https://github.com/YoYoGames/GameMaker-Bugs/issues/15767)
（当前状态 open，里程碑 GMRT 0.23.0；报告者在 0.22.37 上同样复现）。

原因是 GMRT 的 GML 编译器不会给 `rooms/<房间>/InstanceCreationCode_inst_*.gml` 生成 IR
（`Build/build/out` 里这些脚本没有 `.gmir`），但房间数据里仍然引用了这些脚本，
运行时按名字去 WAD 里加载就失败了。GMS2 YYC 走的是另一条编译路径，所以之前用 YYC 一直正常。

## 本次改动

把 11 处实例创建代码搬到对象事件里，实例之间的差异改用**变量定义**
（也就是房间编辑器里的 Overridden Properties）传递。新增的对象变量定义：

另外还绕开了 GMRT 的第二个坑（见后面「附带的第二个坑」一节）：objPreInit 里
矢量图（SVG）抗锯齿的调用被开关关掉了。

| 对象 | 变量 | 默认值 | 含义 |
| --- | --- | --- | --- |
| objTextBox / objUIButton / objUIFileInput | `xRatio` | `-1` | 按屏幕比例重定位 x（`resor_to_x`）；`-1` = 保持房间编辑器里的位置 |
| objUIButton | `eventAction` | `""` | 按钮点击行为；`""` = 沿用对象里原有的默认回调（announcement） |

`xRatio`、`eventAction` 的读取与分发写在对应对象的 Create 事件末尾
（objCredits 继承 objTextBox，所以它的 Create 里 `event_inherited()` 就会执行到这段逻辑）。

### 第三批：启动流程、白字、崩溃与校验错误

修完上面两条后 GMRT 能进游戏了，但依次又暴露了四个问题，一并绕开：

1. **卡在 Loading 界面** —— `texturegroup_load("texFonts", true)` 的预取在 GMRT 下不会完成：
   状态从 loading(1) 掉回 unloaded(0)，永远等不到 `texturegroup_status_fetched`，
   objPreInit Step 就迟迟不创建 objManager。现在 loaded/fetched 都算完成，并加 2 秒超时兜底。
2. **字体全白块** —— texFonts 纹理组在 GMRT 下根本没加载（`sprite_get_texture(sprMsdfNotoSans, 0)`
   只返回 1×1 占位贴图）。把 `DyNode.yyp` 里 texFonts 组的 `"loadType":"dynamicpages"` 改成
   `"default"`（开机随其它组一起加载）后，组状态变 loaded/fetched，贴图恢复。
3. **`window_command_close is not defined`（GMRT 直接崩）** —— 扩展 `window_command_hook.gml`
   里几个命令码原本是以 `//#macro` 形式注释掉的指令；YYC 下未定义标识符静默当 0，
   GMRT 会抛 ReferenceError。现在换成真正的 `#macro`（$F060 等），顺带恢复「关窗口前确认」行为。
4. **运行时改 AA 触发 Dawn 校验错误**（YoYo #15328）—— `display_reset()` 会重建 swapchain，
   GMRT 下会报 `GetCurrentTexture was not called on [Surface] ... prior to calling Present`，
   并连带 `__shdCleanAntialias` 的 pipeline 报错（AA=4 分支顶点输出超限，每帧刷屏）。
   新增宏 `APPLY_RUNTIME_DISPLAY_RESET`（`scripts/scrWindow/scrWindow.gml`，默认 false），
   objPreInit / objManager / scrRecorder 里 4 处 display_reset 都由它控制；
   GMRT 期间不启用 MSAA / vsync，校验错误归零。

### 第四批：MSDF 图集拆帧 + Clean Shapes 顶点输出打包

5. **GMRT 会把超过 2048 的贴图页缩小打包，MSDF 字形因此碎成一片**
   GMRT 0.22 的资源编译器固定按 2048 上限打包贴图页，而本项目的 Windows 贴图页设置是
   8192x8192（最后一次 YYC 构建产物 `texfonts_0.yytex` 头里确实是 8192x8192），于是
   4096x8192 的 MSDF 图集被缩成 1024x2048。MSDF 的 RGB 距离场一旦被重采样就会损坏，
   字形显示为碎片。现在的做法：
   * 用脚本把 11746 个字形格子**逐像素**重新打包成 7 张 2044x2044 的帧
     （`sprMsdfNotoSans` 由 1 帧变 7 帧，图集 JSON 的坐标同步改写为
     2044 x 14308 的虚拟图集；2044 = 2048 页 − 组边框 2px×2），GMRT 因此 1:1 打包、
     不再重采样，字形保真；
   * `scripts/__scribble_font_add_msdf_from_project` 里按“字形所在帧”取
     `sprite_get_uvs` / `sprite_get_texture`（带 `[GMRT-WA-15767]` 标记），
     并保留把 GMRT 缩放页 UV 换算回真实范围的兜底逻辑。
   实测 `texFonts.output.json`：7 页 2048x2048，每个条目 `cropWidth == w`（无缩放），
   界面中文字形清晰。

6. **Clean Shapes 的着色器在 WebGPU 下无法创建 pipeline（黑屏）**
   Clean 的 3 个绘制着色器各声明约 31 个 varying（≈58 个分量），对应 30 个顶点输出，
   超过 WebGPU 的 16 个上限，Dawn 创建 pipeline 失败 → 整帧提交失效 → 窗口全黑 +
   每帧校验报错刷屏。现已把
   `shaders/__shdcleanantialias`、`__shdCleanAntialiasLegacy`、`__shdcleanjaggies`
   的 varying 打包进 15 个 vec4（`v_packed0..14` + `#define` 保持原变量名不变），
   数据本身不变，GMS2/YYC 同样适用。此后校验错误为 0，Clean 绘制的面板/线条恢复正常。

7. **把 `undefined` 传给扩展的 REAL 参数会直接崩溃**（`REAL argument is undefined`）
   点「打开项目」进主界面时，`objMain` 的 `_create_channel()` 第一次执行，`channel` 仍是
   `undefined`，`FMODGMS_Chan_RemoveChannel(undefined)` 在 YYC 下被宽松地当成 0，
   GMRT 则直接抛 `REAL argument is undefined`。现在这两处 FMOD 调用
   （`_create_channel()`、`volume_set_main()`）都先用 `is_undefined()` 判断。
   项目里同类模式（如 `music`）本来就带判断，只有这两处漏了。
   遇到其它同类报错时，按同样方式在调用前加判断即可。

8. **GMRT 打不开路径里带非 ASCII 字符的文件**（背景图加载不出来）
   工程目录形如 `C:\ALLFILES\DyNode\Works\[天SP] Efferverscence\`，`sprite_add()`
   对该目录下的 JPEG/PNG 一律返回 -1。实测对照：同一个 JPEG 复制到纯 ASCII 路径后
   能正常加载（1500x1500），而 PNG 放进含中文的目录后同样失败 —— 是路径编码问题，
   不是图片格式问题。现在 `image_load()` 在首次 `sprite_add()` 失败后，会把文件复制到
   `program_directory`／`temp_directory` 下的纯 ASCII 临时文件再加载一次，加载完即删；
   YYC 下首次就成功，不会进入这段。工程里保存的仍然是原始路径。
   注意：`video_load()`（DyCore/FFmpeg 那条路）还没有加同样的处理，遇到带中文路径的
   视频可能同样打不开，按需照抄即可。

9. **GMRT 不绘制起点在负坐标的精灵**（背景图"加载成功但完全看不见"）
   背景是居中绘制的：1500x1500 的图在 1920x1080 下 `_sy = (1080 - 1500*1.28)/2 = -420`，
   GMRT 会整张跳过；YYC 正常。对照实验：同一张图同样缩放画在 (200,300) 能显示，
   画在 (960,-420) 就完全不显示。现在 [objMain/Draw_72.gml] 改为把屏幕外的部分裁掉、
   用 `draw_sprite_part_ext()` 只画屏幕内区域（YYC 下裁剪结果与原来一致）。
   注意：其它"起点为负"的绘制在 GMRT 下同样会消失，例如开启 `bgBlured` 后的
   `draw_surface(application_surface, 0, targetLineBelow - _nh)`，遇到时按同样方法裁剪。

10. **录像 / 带 BGA 视频的项目一点就闪退**
   日志里的异常是 `[json.exception.type_error.302] type must be number, but is string`，
   发生在录制开始（`-- Recording audio offset ...` 之后）。原因：GMRT 的 `json_stringify()`
   会把 `int64` 值编码成 `"@i64@780$i64$"` 这样的字符串（YYC 写成 JSON 数字），
   而 DyCore 的 `DyCore_ffmpeg_start_recording()` 用 nlohmann 解析并期望数字，于是抛异常。
   现在 `dyc_ffmpeg_start_recording()` 里不再对 width/height/fps 用 `int64()`，直接传普通数值；
   实测 start/finish 都返回 0，不再抛异常。项目里其它用 `int64()` 生成 JSON 的地方
   （例如 Snitch 的 analytics 负载）在 GMRT 下也会被编成这种标记字符串，需要时同样处理。

11. **加载工程后第一次击键就崩**（`part_emitter_region: emitter must belong to given particle system`）
    `project_load()` 的流程是：先 `room_goto(rMain)`（此时 objMain 的 Create 已经建好粒子系统、
    粒子类型和发射器），下一帧才延迟执行真正的加载，而加载一进来就 `map_reset()` ——
    `map_reset()` 会销毁粒子系统/类型/发射器，销毁之后却没有重建。
    YYC 下沿用已销毁的 id 还能"苟住"，GMRT 会严格校验 emitter 的归属，于是第一次击键的
    `note_emit_particles()` 直接抛异常。现在把粒子系统/类型/发射器的创建收进 objMain 的
    `_partsys_recreate()`，`map_reset()` 销毁后立即调用它重建。
    实测（加载工程后手动设置 region + burst）：不再报错，`part_particles_count` 返回 1。

    另外加了两道兜底，避免"系统/发射器已失效"时直接崩：
    * `scrNote.note_emit_particles()`：调用 `part_particles_count()` 之前先
      `part_system_exists()` 检查，失效就 `objMain._partsys_recreate()`；
    * `objMain._partemit_init()`：设置 region 前检查系统与
      `part_emitter_exists(partSysNote, _pe)`，缺系统就整体重建、缺发射器就补建一个。

    实测（人为把粒子系统销毁后走正常 `note_emit_particles()`）：自动重建并成功发射，
    不再抛异常。

上面两处批量改动都是脚本生成的，脚本留在 `notes/gmrt-workaround-tools/`：

* `split_msdf_atlas.py` —— 把 MSDF 图集重新打包成 ≤2044 的帧并改写
  `datafiles/sprMsdfNotoSans.json`（字体更新后可以重跑）；
* `pack_clean_shapes_varyings.py` —— 把 Clean Shapes 的 varying 打包成 vec4
  （升级 Clean Shapes 之后可以重跑）。

### 附带的第二个坑：GMRT 没有实现 SVG 抗锯齿函数

修完上面这个问题后，GMRT 能加载 WAD 了，但启动时又报：

```
Unhandled exception: ReferenceError: draw_get_svg_aa_level is not defined
```

`objects/objPreInit/Create_0.gml` 里原本会在启动时调用
`draw_get_svg_aa_level()` / `draw_enable_svg_aa()` / `draw_set_svg_aa_level()`，
这三个是 GMS2 的矢量图（SVG）抗锯齿开关，GMRT 0.22.x 还没有实现。

现在这三行被 `var _gmrtSvgAA = false;` 开关包住（代码标记同样是 `[GMRT-WA-15767]`）：

* GMRT 下保持 `false`：跳过调用，矢量图不启用抗锯齿（不崩）；
* 以后用 GMS2/YYC 构建并想恢复抗锯齿，把 `_gmrtSvgAA` 改成 `true` 即可；
* GMRT 实现这三个函数后，删掉开关、恢复成原来的 `if (draw_get_svg_aa_level() == 0)` 即可。

实例映射（原文件已删除，内容见下表）：

| 房间 | 实例 | 对象 | 原创建代码 | 现在 |
| --- | --- | --- | --- | --- |
| rCredits | inst_1F0E7606 | objCredits | `x = resor_to_x(0.05);` | `xRatio = 0.05` |
| rCredits | inst_4FE3C2BD | objUIButton | `x = resor_to_x(0.05);` + 返回起始页的回调 | `xRatio = 0.05`，`eventAction = "go_back"` |
| rProjectInit | inst_57925B3C | objUIFileInput | `x = resor_to_x(0.05)` | `xRatio = 0.05` |
| rProjectInit | inst_4D3CE07A | objUIFileInput | `x = resor_to_x(0.05)` | `xRatio = 0.05` |
| rProjectInit | inst_1D9D7800 | objUIFileInput | `x = resor_to_x(0.05)` | `xRatio = 0.05` |
| rProjectInit | inst_71FB034A | objUIButton | `x = resor_to_x(0.05)` + 校验输入并 `room_goto(rMain)` | `xRatio = 0.05`，`eventAction = "project_create"` |
| rProjectInit | inst_9C053CC | objUIButton | 返回起始页的回调（无 x） | `eventAction = "go_back"` |
| rStartPage | inst_71FB034A_1 | objUIButton | `x = resor_to_x(0.05)` + `room_goto(rProjectInit)` | `xRatio = 0.05`，`eventAction = "project_new"` |
| rStartPage | inst_6C7B47DC | objUIButton | `x = resor_to_x(0.05)` + `initWithProject = true; room_goto(rMain)` | `xRatio = 0.05`，`eventAction = "project_open"` |
| rStartPage | inst_3FCB4889 | objTextBox | `x = resor_to_x(0.05)` | `xRatio = 0.05` |
| rStartPage | inst_6FCDFC63 | objUIButton | `x = resor_to_x(0.05)` + `room_goto(rCredits)` | `xRatio = 0.05`，`eventAction = "about"` |

### 各实例原始创建代码（删除前的完整内容）

`rooms/rCredits/InstanceCreationCode_inst_1F0E7606.gml`
```gml
x = resor_to_x(0.05);
```

`rooms/rCredits/InstanceCreationCode_inst_4FE3C2BD.gml`
```gml
x = resor_to_x(0.05);

eventFunc = function() {
	room_goto(rStartPage);
}
```

`rooms/rprojectinit/InstanceCreationCode_inst_57925B3C.gml`（4D3CE07A、1D9D7800 相同）
```gml

x = resor_to_x(0.05)
```

`rooms/rprojectinit/InstanceCreationCode_inst_71FB034A.gml`
```gml
x = resor_to_x(0.05)

eventFunc = function() {
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
}
```

`rooms/rprojectinit/InstanceCreationCode_inst_9C053CC.gml`
```gml

eventFunc = function() {
	room_goto(rStartPage);
}
```

`rooms/rstartpage/InstanceCreationCode_inst_71FB034A_1.gml`
```gml
x = resor_to_x(0.05)

eventFunc = function() {
	room_goto(rProjectInit);
}
```

`rooms/rstartpage/InstanceCreationCode_inst_6C7B47DC.gml`
```gml
x = resor_to_x(0.05)

eventFunc = function() {
	objManager.initWithProject = true;
	room_goto(rMain);
}
```

`rooms/rstartpage/InstanceCreationCode_inst_3FCB4889.gml`
```gml
x = resor_to_x(0.05)
```

`rooms/rstartpage/InstanceCreationCode_inst_6FCDFC63.gml`
```gml
x = resor_to_x(0.05)

eventFunc = function() {
	room_goto(rCredits);
}
```

## 日后 GMRT 修复后如何还原

1. 确认升级后的 GMRT 已修复 #15767（可以先用本文档「验证方法」里的思路跑一遍：
   确认 wad.json 里重新出现 `InstanceCreationCode_*` 且运行时不再报错）。
2. 整体还原本次变通（推荐，一次撤销所有相关改动）：

   ```
   git log --oneline -- notes/GMRT-15767-workaround.md   # 找到本次变通的提交
   git revert <commit>                                   # 还原该提交
   ```

   如果不想用 revert（例如后续改动较多），也可以手动还原：
   * 恢复 11 个 `InstanceCreationCode_*.gml` 文件（内容见上），放回
     `rooms/<房间>/` 目录；
   * 把三个房间 .yy 里对应实例的 `"hasCreationCode":false` 改回 `true`；
   * 删掉实例上新增的 `xRatio` / `eventAction` Overridden Property；
   * 删掉 objTextBox / objUIButton / objUIFileInput 的 `xRatio`、objUIButton 的
     `eventAction` 变量定义；
   * 删掉三个对象 Create 事件里带 `[GMRT-WA-15767]` 标记的代码块。
   * 把 objPreInit Create 事件里带 `[GMRT-WA-15767]` 标记的 `_gmrtSvgAA` 开关去掉，
     恢复成原来的 `if (draw_get_svg_aa_level() == 0) { ... }`。
   * 扩展只改了 `extensions/window_command_hook/window_command_hook.gml`：把带
     `[GMRT-WA-15767]` 标记的真 `#macro` 恢复成原来的 `//#macro` 注释。
   * 删掉 `scripts/scrWindow/scrWindow.gml` 里的 `APPLY_RUNTIME_DISPLAY_RESET` 宏，
     并把 objPreInit / objManager / scrRecorder 里 4 处 `display_reset` 的 `if` 包壳去掉。
   * 把 `DyNode.yyp` 里 texFonts 组的 `"loadType"` 从 `"default"` 改回 `"dynamicpages"`。
   * 删掉 `scripts/__scribble_font_add_msdf_from_project/` 里带 `[GMRT-WA-15767]` 的 UV 换算代码。
   * 图集拆帧：把 `sprites/sprmsdfnotosans/` 与 `datafiles/sprMsdfNotoSans.json` 还原成
     拆分前的单帧 4096x8192 版本，并去掉 Scribble 载入器里带 `[GMRT-WA-15767]` 的
     “按帧取 UV/纹理”代码（`git revert` 会自动完成这些）。
   * Clean 着色器：把 `shaders/__shdcleanantialias`、`__shdCleanAntialiasLegacy`、
     `__shdcleanjaggies` 的 `v_packed*` 打包块换回原来的 `varying` 声明列表
     （数据含义不变，只是写法）。

## 验证记录（2026-10-04）

* `Build/build/out` 里 470 个脚本全部生成 `.gmir`，`Build/DyNode.wad.json` 里
  `InstanceCreationCode` 出现次数为 0；
* 用 GMRT 0.22.4 重新编译后直接运行 `Build/build/DyNode.exe`：
  不再出现 `Failed to load script ... from wad`，窗口标题 `DyNode Modified` 正常出现并持续运行；
* 第三批改动后 `ReferenceError` / `is not defined` / `GetCurrentTexture` 均为 0；
  只有 `Failed to load Vulkan` 回退（GMRT 用 D3D12 后端）和
  `Grid index out of bounds` 这类提示；
* 第四批改动后：`VALIDATION ERROR`、`infringes limits` 均为 0；
  `texFonts` 打成 7 张 2048x2048 页且每项 `cropWidth == w`（无缩放）；
  实际运行截图确认「开始页面 / 新建项目」等中文字形清晰、背景三角形正常；
* 仍然存在但不影响运行的提示：`Failed to load Vulkan`（GMRT 回退 D3D12）、
  `Warning: no handler found for chunk with ID: STRG`、`Grid index out of bounds`。

> 注意：如果 GameMaker IDE 一直开着这个工程，改动磁盘上的 .yy/.gml 后需要在 IDE 里
> 重新加载工程（或关掉重开）再编译，否则 IDE 可能用旧的内存状态覆盖这些文件。

## 验证方法

用 GMRT 编译后检查 `Build/build/out` 与 `Build/DyNode.wad.json`：

```powershell
# 编译产物里不应再有 InstanceCreationCode 相关脚本（变通生效）
Select-String -LiteralPath D:\DYNSource\Build\DyNode.wad.json -Pattern "InstanceCreationCode"
# 运行时不应再出现 "Failed to load script ... from wad"
```

