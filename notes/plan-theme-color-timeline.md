# Plan: 谱面主题色时间线 (Theme Color Timeline)

## 1. 功能概述

在编辑器中新增一套"主题色时间线"系统，允许用户在谱面的特定时间点设定颜色关键帧，并定义关键帧之间的颜色过渡方式（突变、线性等）。

**核心约束**：
- **仅在 Custom 主题（index 3）激活时生效** — 其他主题下颜色时间线完全无效
- **驱动 `global.themeColorCustom`** — 颜色关键帧的值是该时间点 `themeColorCustom` 应变成的目标颜色，通过现有的 `theme_custom_set_color()` → `theme_custom_apply()` 传播到整个渲染链
- **无需修改任何 Draw 事件** — 现有的 Custom 主题渲染管线（`objMain.themeColor` → 粒子/shader/进度条等）已经消费 `themeColorCustom`，只需在 Step 中按时更新即可
- **数据仅保存在 .dyn 项目工程文件中，不影响 XML 导出**

---

## 2. 数据结构设计

### 2.1 颜色关键帧结构

```
ColorKeyframe {
    time: double          // 时间点（毫秒），与音符/TimingPoint的time一致
    color: int            // RGB颜色值（0xRRGGBB），即该时间点 themeColorCustom 的目标值
    interp: enum          // 到下一个关键帧的过渡模式
}
```

### 2.2 过渡模式 (Interpolation Mode)

| 值 | 名称 | 说明 |
|----|------|------|
| 0  | `INTERP_SMOOTH` | 线性插值（HSV空间，色相走最短路径） |
| 1  | `INTERP_SMOOTH_RGB` | 线性插值（RGB空间） |
| 2  | `INTERP_INSTANT` | 突变（到达下一关键帧时间点时瞬间切换） |

### 2.3 数据存储位置

- **C++ 侧**: `Chart` 结构体新增 `std::vector<ColorKeyframe> colorKeyframes` 字段
- **GML 侧**: 通过 DyCore API 进行读写操作
- **.dyn 文件**: 序列化到每个 chart 对象中，key 名为 `"colorKeyframes"`
- **XML 导出**: 完全忽略此字段（XML 导出走 `format/xml.cpp` 独立路径，不经过 Chart 的 `to_json`）

---

## 3. C++ 后端改动 (DyCore)

### 3.1 新增文件

#### `DyCore/src/project/colorKeyframe.h`
```cpp
#pragma once
#include <json.hpp>

enum class ColorInterp : int {
    Smooth = 0,       // HSV线性插值（最短色相路径）
    SmoothRGB = 1,    // RGB线性插值
    Instant = 2       // 突变
};

struct ColorKeyframe {
    double time;         // 毫秒
    int color;           // 0xRRGGBB
    ColorInterp interp;
};

void to_json(nlohmann::json& j, const ColorKeyframe& ck);
void from_json(const nlohmann::json& j, ColorKeyframe& ck);

// 根据时间查询当前应显示的颜色
// keyframes需已按time升序排列
// baseColor: 无关键帧或时间在所有关键帧之前时的回退颜色
int color_keyframe_resolve(const std::vector<ColorKeyframe>& keyframes,
                           double time, int baseColor);
```

#### `DyCore/src/project/colorKeyframe.cpp`
- JSON 序列化/反序列化（keys: `time`, `color`, `interp`）
- `color_keyframe_resolve()`:
  1. 空数组 → 返回 `baseColor`
  2. 二分查找找到 `time` 左右两侧的关键帧
  3. `time < 第一个关键帧` → 返回 `baseColor`
  4. `time >= 最后一个关键帧` → 返回最后一个的颜色
  5. 根据 `interp` 模式计算：
     - `INSTANT`: 返回左侧关键帧颜色
     - `Smooth`: 进度 `t = (time - left.time) / (right.time - left.time)`，HSV 空间插值（色相走最短弧）
     - `SmoothRGB`: 同上进度比例，RGB 各通道线性插值

#### `DyCore/src/project/colorKeyframeAPI.cpp`
导出给 GML 的 C API：
```cpp
DyCore_color_keyframes_count()                          // 当前chart的颜色关键帧数量
DyCore_color_keyframe_get(double index)                 // 指定索引的关键帧 (JSON字符串)
DyCore_color_keyframes_get_all()                        // 所有关键帧 (JSON数组字符串)
DyCore_color_keyframe_insert(double time, double color, double interp)  // 插入（自动排序）
DyCore_color_keyframe_delete(double time)               // 删除指定time
DyCore_color_keyframe_change(double time, double newColor, double newInterp)  // 修改
DyCore_color_keyframes_reset()                          // 清空
DyCore_color_keyframe_resolve(double time, double baseColor)  // 查询解析颜色
```

### 3.2 修改现有文件

#### `DyCore/src/project/project.h` — Chart 结构体
```cpp
struct Chart {
    // ... 现有字段 ...
    std::vector<TimingPoint> timingPoints;
    std::vector<ColorKeyframe> colorKeyframes;  // 新增
    // ...
};
```

#### `DyCore/src/project/project.cpp` — JSON 序列化
- `to_json(Chart)`: 新增序列化 `colorKeyframes` 数组（仅当非空时写入）
- `from_json(Chart)`: 用 `j.value("colorKeyframes", json::array())` 安全读取，缺失时为空数组（向后兼容）

#### `DyCore/src/project/projectManager.cpp` — update_current_chart
- `update_current_chart()`: 新增同步 colorKeyframes

### 3.3 版本兼容性

`colorKeyframes` 是 Chart 级别的可选字段，老 .dyn 文件缺失此字段时自动回退为空数组。`DYN_FILE_FORMAT_VERSION` 保持为 1，无需版本升级。

---

## 4. GML 前端改动

### 4.1 DyCore 包装层 (`scripts/scrDyCore/scrDyCore.gml`)

新增一组函数：
```gml
function dyc_color_keyframes_count() { ... }
function dyc_color_keyframe_get(_index) { ... }
function dyc_color_keyframes_get_all() { ... }
function dyc_color_keyframe_insert(_time, _color, _interp) { ... }
function dyc_color_keyframe_delete(_time) { ... }
function dyc_color_keyframe_change(_time, _newColor, _newInterp) { ... }
function dyc_color_keyframes_reset() { ... }
function dyc_color_keyframe_resolve(_time, _baseColor) { ... }
```

### 4.2 颜色时间线编辑函数 (`scripts/scrEditor/scrEditor.gml`)

在现有 `TIMING POINT FUNCTION` region 之后新增 `COLOR KEYFRAME FUNCTION` region：

```gml
#region COLOR KEYFRAME FUNCTION

function color_keyframe_count() { ... }

// 交互式创建关键帧（复用 timing_point_create 的选中音符取时间逻辑）
function color_keyframe_create(_record = false) { ... }

// 编辑已有关键帧行
function color_keyframe_change(_time, _record = false) { ... }

// 删除指定时间的关键帧
function color_keyframe_delete(_time, _record = false) { ... }

// 获取当前播放时间的解析颜色（仅Custom主题有效）
function color_keyframe_get_current_color() {
    if(global.themeAt != 3) return undefined;  // 非Custom主题不生效
    var _baseColor = global.themeColorCustom;
    if(dyc_color_keyframes_count() == 0) return _baseColor;
    return dyc_color_keyframe_resolve(objMain.nowTime, _baseColor);
}

#endregion
```

### 4.3 每帧颜色更新 — 通过 Custom 主题管线 (`objects/objmain/Step_0.gml`)

**这是整个渲染集成的唯一注入点**，无需改动任何 Draw 事件：

```gml
// 颜色时间线：仅 Custom 主题生效，驱动 themeColorCustom
if(global.themeAt == 3) {
    var _ckColor = color_keyframe_get_current_color();
    if(_ckColor != undefined && _ckColor != global.themeColorCustom) {
        theme_custom_set_color(_ckColor);
        // theme_custom_set_color 内部已调用 theme_custom_apply()
        // → 更新 global.themes[3].color + objMain.themeColor
        // → 所有下游渲染自动跟随
    }
}
```

**为什么只需要这一步**：
- `theme_custom_set_color(col)` 已经完成了完整的颜色传播链：
  1. `global.themeColorCustom = col`
  2. `theme_custom_apply()` → 更新 `global.themes[3].color` 和 `objMain.themeColor`
  3. 所有 Draw 事件读取 `theme_get().color` 或 `objMain.themeColor` 时自动拿到新颜色
  4. `shd_hsv_trans` shader 的 uniform 在 Draw 中基于当前主题色实时计算，无需额外更新

### 4.4 编辑器入口 (`objects/objeditor/Step_1.gml`)

新增快捷键检测（可选，也可纯通过面板操作）：
- 选中音符后按快捷键 → 设定该音符时间为颜色关键帧
- 或通过快捷键打开颜色时间线面板

---

## 5. 颜色时间线面板 (UI)

### 5.1 新建对象 `objColorTimeline`

参照 `objKeybindPanel` 的设计风格，创建模态面板：

**`objects/objColorTimeline/Create_0.gml`**:
- 面板尺寸：`panelW = 900`, `panelH = 700`（可调）
- 居中定位：`x0 = (BASE_RES_W - panelW) / 2`, `y0 = 20`
- 深度：`-1000`（与 KeybindPanel 一致）
- 滚动状态（scroll / scrollTarget）、行高 `rowH = 32`
- 按钮区：[添加关键帧] [清空所有] [关闭]
- 关键帧列表：从 `dyc_color_keyframes_get_all()` 读取，按 time 排序
- 标题提示当前仅 Custom 主题有效（如果当前不是 Custom 主题，在标题下方显示提示文字）

**`objects/objColorTimeline/Step_0.gml`**:
- 调用 `global.__InputManager.freeze()` 冻结游戏输入（与 KeybindPanel 行为一致）
- Esc 关闭面板：`keyboard_check_pressed(vk_escape)` → `instance_destroy()`
- 关闭按钮 `×` 点击检测
- 滚轮滚动列表
- 点击行 → 打开该关键帧的编辑（`dyc_get_string()` 弹窗）
- "添加"按钮 → 调用 `color_keyframe_create()`
- "清空"按钮 → `dyc_show_question()` 确认后 `dyc_color_keyframes_reset()`

**`objects/objColorTimeline/Draw_75.gml`**:
- 半透明黑色全屏背景：`draw_rectangle(0, 0, BASE_RES_W, BASE_RES_H)` + `c_black, 0.5`
- 深色面板：`CleanRectangleXYWH(...).Blend(0x101014, 0.96).Border(2, _col, 0.8).Rounding(14)`
- 标题栏："Color Timeline / 颜色时间线"
- 如果当前不是 Custom 主题，标题下方显示警告文字（灰色/红色）
- 按钮区：与 KeybindPanel 完全一致的按钮样式
- 列表区每行：
  - 左侧颜色色块（小矩形，填充该关键帧的 color）
  - 中间时间（复用 `format_time_ms()`）
  - 右侧过渡模式标签
  - hover 高亮、选中态
- 滚动条：与 KeybindPanel 一致
- Footer 提示

### 5.2 面板中的 Esc 行为（不响应全局 Esc 退出弹窗）

实现方式与 objKeybindPanel 完全一致：

1. 面板 Step 首先调用 `global.__InputManager.freeze()` → 冻结所有 `bind_*` 查询
2. 全局 `global_quit`（绑 Esc）通过 `bind_down()` 查询，被 freeze 后返回 false → 不触发退出确认
3. 面板自身用原始 `keyboard_check_pressed(vk_escape)` → 关闭自身
4. 在 `scrKeybind.gml` 的 `_ensure_cache()` 中加入检查：

```gml
// scrKeybind.gml line 393, 修改为：
cachePanelOpen = instance_exists(objKeybindPanel)
    || instance_exists(objColorTimeline)    // 新增
    || keybind_overlay_blocks_input();
```

### 5.3 关闭按钮

面板右上角绘制 `×` 关闭按钮（与标题同行），鼠标可点击：

```gml
// Draw: 关闭按钮区域
var _closeBtnX = x0 + panelW - 40;
var _closeBtnY = y0 + titleH / 2;
// 绘制圆形/方形按钮 + "×" 文字
// Step: 点击检测 → instance_destroy()
```

---

## 6. 关键帧编辑子流程

### 6.1 创建关键帧

1. 用户在编辑器中选中一个音符（或处于某个播放位置）
2. 通过快捷键或面板中的"添加"按钮触发
3. 获取时间：
   - 选中 1 个音符 → 自动取该音符的 `time`（复用 `timing_point_create` 的逻辑）
   - 否则 → 当前播放时间 `objMain.nowTime`
4. 输入颜色：`dyc_get_string()` 弹出原生输入框，提示输入 RRGGBB 十六进制值（与 `CommandThemeCustom` 一致）
5. 选择过渡模式：`dyc_get_string()` 提供选项 `0=SmoothHSV / 1=SmoothRGB / 2=Instant`
6. 调用 `dyc_color_keyframe_insert(time, color, interp)`
7. announcement 确认

### 6.2 编辑关键帧

1. 在面板中点击已有关键帧行
2. 弹出编辑：`dyc_get_string()`，格式 `"时间 , RRGGBB , 过渡模式"`
3. 修改后调用 `dyc_color_keyframe_change()`

### 6.3 删除关键帧

1. 在面板中通过删除按钮或快捷键触发
2. 调用 `dyc_color_keyframe_delete(time)`

---

## 7. Undo/Redo 集成

在 `scrConstructor.gml` 的 `OPERATION_TYPE` enum 中新增：
```gml
CKADD,       // 添加颜色关键帧
CKREMOVE,    // 删除颜色关键帧
CKCHANGE,    // 修改颜色关键帧
```

在 `scrEditor.gml` 的 `operation_do()` 中处理这三种操作类型的回退/重做。

---

## 8. 快捷键注册

在 `scrKeybindRegistry.gml` 中新增：
```gml
keybind_register("editor_color_timeline", "editor", KBT_PRESS, <某个键>);
```

建议：`Ctrl+T` 或其他未占用组合（需确认当前键位占用情况）。

---

## 9. i18n 国际化

在 `datafiles/lang/zh-cn.json` 和 `en-US.json` 中新增：

```json
{
    "color_timeline_title":                "颜色时间线" / "Color Timeline",
    "color_timeline_add":                  "添加关键帧" / "Add Keyframe",
    "color_timeline_clear":                "清空所有" / "Clear All",
    "color_timeline_close":                "关闭" / "Close",
    "color_timeline_hint":                 "点击行编辑 | 滚轮滚动" / "Click row to edit | Scroll to navigate",
    "color_timeline_interp_smooth":        "线性 (HSV)" / "Smooth (HSV)",
    "color_timeline_interp_smooth_rgb":    "线性 (RGB)" / "Smooth (RGB)",
    "color_timeline_interp_instant":       "突变" / "Instant",
    "color_timeline_empty":                "暂无关键帧" / "No keyframes yet",
    "color_timeline_not_custom":           "仅在自定义主题下生效" / "Only active with Custom theme",
    "color_timeline_add_success":          "已添加颜色关键帧 @ {0}" / "Color keyframe added @ {0}",
    "color_timeline_delete_success":       "已删除颜色关键帧 @ {0}" / "Color keyframe deleted @ {0}",
    "color_timeline_change_success":       "已修改颜色关键帧" / "Color keyframe modified",
    "color_timeline_clear_confirm":        "确定清空所有颜色关键帧？" / "Clear all color keyframes?",
    "color_timeline_q_time":               "输入时间点 (ms):" / "Enter time (ms):",
    "color_timeline_q_color":              "输入颜色 (RRGGBB):" / "Enter color (RRGGBB):",
    "color_timeline_q_interp":             "过渡模式 (0=线性HSV 1=线性RGB 2=突变):" / "Interp (0=SmoothHSV 1=SmoothRGB 2=Instant):"
}
```

---

## 10. 实现优先级与分步计划

### Phase 1: 后端数据层
1. 创建 `colorKeyframe.h` / `colorKeyframe.cpp` — 数据结构 + JSON 序列化 + resolve 函数
2. 创建 `colorKeyframeAPI.cpp` — 导出 C API
3. 修改 `project.h` — Chart 结构体新增 `colorKeyframes`
4. 修改 `project.cpp` — to_json / from_json 新增字段处理
5. 修改 `projectManager.cpp` — update_current_chart 同步
6. 编写单元测试

### Phase 2: GML 包装层
7. `scrDyCore.gml` — 新增 `dyc_color_keyframe_*` 包装函数
8. `scrEditor.gml` — 新增 `COLOR KEYFRAME FUNCTION` region
9. `scrConstructor.gml` — 新增 OPERATION_TYPE（CKADD / CKREMOVE / CKCHANGE）

### Phase 3: UI 面板
10. 创建 `objColorTimeline` 对象（Create / Step / Draw / Destroy）
11. `scrKeybindRegistry.gml` — 注册面板快捷键
12. `scrKeybind.gml` — `cachePanelOpen` 加入 `instance_exists(objColorTimeline)`
13. i18n 字符串

### Phase 4: 渲染集成（最小改动）
14. `objmain/Step_0.gml` — 新增 3 行：Custom 主题守卫 + `color_keyframe_get_current_color()` + `theme_custom_set_color()`
15. 验证：无关键帧时行为与现在完全一致

### Phase 5: 收尾
16. Undo/Redo 集成
17. 测试：创建/编辑/删除关键帧、播放预览、.dyn 保存/加载、XML 导出不受影响、非 Custom 主题不生效
18. 边界情况：无关键帧回退、单关键帧、首尾关键帧外的时间、主题切换时的颜色恢复

---

## 11. 涉及文件清单

### 新增文件
| 文件 | 语言 | 说明 |
|------|------|------|
| `DyCore/src/project/colorKeyframe.h` | C++ | 数据结构定义 |
| `DyCore/src/project/colorKeyframe.cpp` | C++ | 序列化 + 解析逻辑 |
| `DyCore/src/project/colorKeyframeAPI.cpp` | C++ | GML 可调用的 C API |
| `DyCore/tests/colorKeyframe_test.cpp` | C++ | 单元测试 |
| `objects/objColorTimeline/Create_0.gml` | GML | 面板初始化 |
| `objects/objColorTimeline/Step_0.gml` | GML | 面板交互 |
| `objects/objColorTimeline/Draw_75.gml` | GML | 面板渲染 |
| `objects/objColorTimeline/Destroy_0.gml` | GML | 清理（解冻输入） |

### 修改文件
| 文件 | 改动 |
|------|------|
| `DyCore/src/project/project.h` | Chart 新增 `colorKeyframes` 字段 |
| `DyCore/src/project/project.cpp` | JSON 序列化新增 `colorKeyframes` 字段 |
| `DyCore/src/project/projectManager.cpp` | `update_current_chart()` 同步 colorKeyframes |
| `DyCore/src/project/projectAPI.cpp` | 新增导出函数声明 |
| `DyNode.yyp` | 注册新对象、新脚本资源 |
| `scripts/scrDyCore/scrDyCore.gml` | 新增 `dyc_color_keyframe_*` 包装函数 |
| `scripts/scrEditor/scrEditor.gml` | 新增 `COLOR KEYFRAME FUNCTION` region |
| `scripts/scrConstructor/scrConstructor.gml` | 新增 OPERATION_TYPE |
| `scripts/scrKeybindRegistry/scrKeybindRegistry.gml` | 注册面板快捷键 |
| `scripts/scrKeybind/scrKeybind.gml` | `cachePanelOpen` 加入 objColorTimeline |
| `objects/objmain/Step_0.gml` | 新增颜色时间线驱动逻辑（~5行） |
| `datafiles/lang/zh-cn.json` | 新增中文 i18n 字符串 |
| `datafiles/lang/en-US.json` | 新增英文 i18n 字符串 |

---

## 12. 设计约束与注意事项

1. **Custom 主题守卫**：所有颜色时间线逻辑（解析、应用、面板提示）都检查 `global.themeAt == 3`，非 Custom 主题时完全无效。
2. **复用现有管线**：`theme_custom_set_color()` → `theme_custom_apply()` 已完成全部颜色传播（`global.themes[3].color`、`objMain.themeColor`、scribble `[c_custom]` 标签），无需改动 Draw 事件。
3. **向后兼容**：老 .dyn 文件缺失 `colorKeyframes` 字段时自动回退为空数组。
4. **XML 隔离**：XML 导出走 `format/xml.cpp` 独立路径，不经过 Chart 的 `to_json`。
5. **性能**：`color_keyframe_resolve()` 使用二分查找 O(log N)，每帧一次查询，对渲染无影响。
6. **面板行为一致性**：完全复用 objKeybindPanel 的模态模式（freeze 输入、独立处理 Esc、深度 -1000、主题色边框、圆角矩形）。
7. **Esc 隔离**：`cachePanelOpen` 检查 + `InputManager.freeze()` 双重保障，面板打开期间全局 Esc 不触发退出弹窗。
8. **主题切换边界**：从 Custom 切换到其他主题时，`themeColorCustom` 保持最后值不变（现有行为）；切回 Custom 时，时间线根据当前时间重新生效。
