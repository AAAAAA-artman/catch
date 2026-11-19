# 文字特效 addon · CurvedText / TextFX

**一句话**：把一串文字逐字摆到曲线（直线 / 圆弧 / 整圆 / 正弦波 / 贝塞尔拱）上，每个字跟着曲线切线旋转，并自带「缓慢消失」动画。全部用 `Node2D` + `draw_char` 画出来，**不写 shader、不依赖任何图片/字体资源**，把 `addons/text_fx/` 整个目录拷进任何 Godot 4.7 工程就能用。

## 为什么不用 shader

| 方案 | 依赖什么 | gl_compatibility | mobile | web | forward+ |
| --- | --- | :---: | :---: | :---: | :---: |
| SDF / UV 变形文字 shader | 字体图集、自定义 fragment shader，很多效果还要 screen texture | 要额外做兼容 | 看 GPU | 看 WebGL 能力 | 可用 |
| **本 addon（逐字 `draw_char`）** | 只要 CanvasItem 能画东西 | ✅ | ✅ | ✅ | ✅ |

每一笔都落在「这个字画在这个位置、这个角度、这个透明度」上，不经过片元着色器、不读屏幕纹理、不吃光照，所以四种渲染后端结果完全一致。代价是**每个字一次绘制调用**（见「八、注意事项」第 3 条）。

---

## 一、文件清单

| 文件 | 作用 | 是否必须 |
| --- | --- | :---: |
| `curved_text.gd` | 节点本体，`class_name CurvedText extends Node2D`：排版 + 绘制 + 淡入淡出 | 必须 |
| `text_fx.gd` | 静态工厂，`class_name TextFX extends RefCounted`：预设 + 一行生成 | 可选（不用它也能直接 `CurvedText.new()`） |
| `curved_text.gd.uid`、`text_fx.gd.uid` | Godot 4.4+ 的脚本 UID 边车文件，跟着脚本一起拷，别改名 | 建议保留 |
| `demo/demo_text_fx.gd`、`demo/text_fx_demo.tscn` | 演示场景，编辑器里 F6 直接跑 | 可删 |

`text_fx.gd` 只是「预设参数表 + 建节点」的糖，`curved_text.gd` 自身不依赖它。

---

## 二、三步移植

### 1. 拷目录

把 `addons/text_fx/` **整个目录**拷到目标项目的同名位置：

```
目标项目/addons/text_fx/curved_text.gd
目标项目/addons/text_fx/text_fx.gd
目标项目/addons/text_fx/demo/…
```

拷完回编辑器（或重启 Godot），让它重新扫描脚本、把 `class_name CurvedText` / `class_name TextFX` 注册成全局类。目录名保持 `text_fx`，不要改成别的（脚本内部没有引用目录名，但保持同名省得以后升级时对不上）。

### 2. 项目设置：不需要任何配置

- 不用改渲染后端（`gl_compatibility` / `mobile` / `forward_plus` 都行）
- 不用开 2D 抗锯齿、不用开 HDR、不用加 autoload、不用注册 layer name
- 不用准备字形图集、不用准备任何 `res://` 图片

唯一值得留意的是中文字体：`font` 留空时会自动回退到系统字体，如果你的目标平台系统字体名对不上，手动给 `font` 赋一个 `.ttf` 资源即可（见「八、注意事项」第 1 条）。

### 3. 代码里用起来

```gdscript
TextFX.whisper(get_tree().current_scene, "门还没有关上", Vector2(640, 420))
```

或者自己 `new` 一个，完整控制参数：

```gdscript
var t := CurvedText.new()
t.text = "你终于被听见了"
t.font_size = 64
t.curve_mode = CurvedText.CurveShape.ARC
t.radius = 700.0
t.position = Vector2(640, 300)
add_child(t)
t.fade_out(4.0)
```

---

## 三、快速开始

```gdscript
extends Node2D

func _ready() -> void:
	# 建（或复用）一层 CanvasLayer，layer 默认 20
	var layer := TextFX.ui_layer(self)

	# 一行一条：预设 + 自动缓慢消失
	TextFX.whisper(layer, "门还没有关上", Vector2(640, 420))
	TextFX.banner(layer, "接住了", Vector2(640, 200))
```

要自己配参数，就直接建节点（先设参数、后 `add_child`，这样只排一次版）：

```gdscript
func show_banner(layer: CanvasLayer) -> void:
	var t := CurvedText.new()
	t.text = "接住了"
	t.font_size = 76
	t.glyph_spacing = 6.0
	t.curve_mode = CurvedText.CurveShape.ARC
	t.radius = 1750.0
	t.align = CurvedText.Align.CENTER
	t.color_start = Color("fff3e8")
	t.color_end = Color("f7a26b")
	t.outline_size = 7
	t.fade_stagger = 0.45
	t.fade_drift = Vector2(0.0, -18.0)
	t.position = Vector2(640, 200)
	layer.add_child(t)   # 入树时 _ready() 会排一次版

	t.fade_out(2.6)      # 2.6 秒缓慢消失
```

### 为什么建议放在 CanvasLayer 上、layer 20 以上

Godot 的 `CanvasLayer` 规则：**layer 数字越大越靠前**。典型分层：

```
CanvasLayer layer = 0      ← 游戏世界（2D 相机在这里动）
CanvasLayer layer = 1~10   ← 全屏后期滤镜
CanvasLayer layer = 20+    ← 文字特效 / UI        ← 放这里
```

两个原因：

1. **不被后期滤镜吃掉。** 全屏滤镜通常是一层 `CanvasLayer` 上盖一张全屏 `ColorRect`。文字如果画在它下面，会被一起压暗、染黄、加颗粒和暗角 —— 而「缓慢消失」的最后半秒 alpha 很低，正好是最容易被颗粒和暗角糊成噪点的时候。
2. **不跟相机跑。** `Node2D` 挂在世界层里会随 2D 相机移动、缩放；挂在 `CanvasLayer` 下，`position` 就等于屏幕坐标，不会跟着镜头飘。

> 反过来说，如果你**想让**文字被滤镜调色（更融进画面），就把它放到滤镜层下面 —— 这是取舍，不是错。
> 想让文字被场景里的物体挡住，就别挂在 20 层：把它放进世界层，用 `z_index` 和遮挡物排先后（文字比前景小即可）。

`TextFX.ui_layer(host, layer, layer_name)` 会先找 `host` 下有没有同名 `CanvasLayer`，有就复用，所以可以放心反复调用。

---

## 四、完整参数表

所有参数都是 `@export`，检视面板里带 range 限制，拖动着就能看到效果。

### 4.0 改了之后会怎样：重排 / 重绘 / 无 setter

这一点决定了哪些参数「改一下就有反应」、哪些要等下一次重绘：

| 行为 | 参数 | 说明 |
| --- | --- | --- |
| **触发重新排版** | `text`、`font`、`font_size`、`glyph_spacing`、`align`、`curve_mode`、`radius`、`rotate_follow`、`rotate_bias`、`bezier_bulge`、`wave_amplitude`、`wave_length`、`jitter`、`jitter_rotate` | 都带 `set` 并调 `_rebuild()`：字要重新摆位置，成本较高 |
| **只触发重绘** | `color_start`、`color_end`、`outline_size`、`outline_color`、`base_alpha` | 带 `set` 并调 `queue_redraw()`：不重排，只重画 |
| **只开关 `_process`** | `float_amplitude` | 有 `set`，但只做「按值开关 `_process`」；开着时每帧都会重绘，所以运行中改它立刻生效 |
| **普通变量，没有 setter** | `float_speed`、`float_phase`、`fade_duration`*、`fade_delay`、`fade_stagger`*、`fade_power`、`fade_drift`、`fade_glyph_drift`、`fade_shrink`、`fade_wobble`、`free_when_done`、`auto_play` | 改它们不会主动触发重排/重绘。动画期间每帧都会 `queue_redraw()`，所以运行中改仍然生效；**静止状态下改了想立刻看到，就自己叫一次 `t.queue_redraw()`** |

\* `fade_duration` / `fade_stagger` 有 setter，但 setter 里只是赋值 / 夹取范围，同样不会触发重排或重绘。

### 枚举

曲线枚举叫 **`CurveShape`**，**不是 `Curve`** —— `Curve` 是 Godot 内置类名，同名会报 `The member "Curve" shadows a native class` 解析错误。枚举成员名保持不变。

| 枚举 | 值 | 说明 |
| --- | --- | --- |
| `CurveShape.STRAIGHT` | 0 | 直线（也会逐字排版，方便做字距、抖动、逐字动效） |
| `CurveShape.ARC` | 1 | 圆弧：`radius` 越大越平，负数方向相反 |
| `CurveShape.CIRCLE` | 2 | 整圆：文字沿一圈排开（整段均匀摊满 360°） |
| `CurveShape.WAVE` | 3 | 正弦波 |
| `CurveShape.BEZIER` | 4 | 二次贝塞尔拱形，`bezier_bulge` 控制拱高 |
| `Align.START` | 0 | 从原点开始向右铺 |
| `Align.CENTER` | 1 | 以原点为中心（默认） |
| `Align.END` | 2 | 到原点结束 |
| `PlayMode.NONE` | 0 | 没有动画在跑 |
| `PlayMode.FADE_OUT` | 1 | 缓慢消失 |
| `PlayMode.FADE_IN` | 2 | 缓慢浮现 |

### 4.1 文字（`@export_group("文字")`）

| 变量名 | 类型 | 默认值 | 作用 | 取值范围 |
| --- | --- | --- | --- | --- |
| `text` | `String` | `"你终于被听见了"` | 要显示的文字。多行输入框 | 任意字符串；`\n` 不会排版成第二行（见坑 7） |
| `font` | `Font` | `null` | 字体资源。留空时自动选字体（见坑 1） | 任意 `Font`；`null` = 自动回退 |
| `font_size` | `int` | `48` | 字号（像素） | 8 ~ 256，步进 1 |
| `glyph_spacing` | `float` | `0.0` | 额外字距：正数拉开、负数收紧 | −20 ~ 80，步进 0.5 |
| `align` | `Align` | `Align.CENTER` | 整串相对 `position` 的对齐方式 | `START` / `CENTER` / `END` |

### 4.2 曲线（`@export_group("曲线")`）

| 变量名 | 类型 | 默认值 | 作用 | 取值范围 |
| --- | --- | --- | --- | --- |
| `curve_mode` | `CurveShape` | `CurveShape.ARC` | 用哪种曲线排版 | `STRAIGHT` / `ARC` / `CIRCLE` / `WAVE` / `BEZIER` |
| `radius` | `float` | `900.0` | 半径。`ARC`：正数拱向上、绝对值越大越平、负数反向；`CIRCLE`：圆半径（取绝对值，最小 10），**整段文字均匀摊满 360°，与字数无关** | −4000 ~ 4000，步进 1 |
| `rotate_follow` | `float` | `1.0` | 每字跟随曲线切线旋转的程度，五种曲线公式统一：`字角度 = 切线角 × rotate_follow + rotate_bias`。`1` 完全贴切线，`0` 全部水平（拱形但不斜），`>1` 夸张化 | 0 ~ 3，步进 0.01 |
| `rotate_bias` | `float` | `0.0` | 给所有字额外加一个固定旋转（弧度），**五种曲线都生效** | −1 ~ 1，步进 0.01 |
| `bezier_bulge` | `float` | `220.0` | 贝塞尔拱的**实际拱高**（像素，拱顶相对基线的高度），`0` = 完全平 | 0 ~ 600，步进 1 |
| `wave_amplitude` | `float` | `40.0` | 正弦波振幅（像素） | 0 ~ 400，步进 1 |
| `wave_length` | `float` | `520.0` | 一个完整波长的像素长度，越小波形越密 | 20 ~ 2000，步进 1 |

> `radius` 只在 `ARC` / `CIRCLE` 下生效，`bezier_bulge` 只在 `BEZIER` 下生效，`wave_*` 只在 `WAVE` 下生效；切模式时旧参数会留着，切回来就恢复，不用重输。
> **`rotate_follow` / `rotate_bias` 对五种曲线一视同仁**：旋转都由「切线角」算出来。`STRAIGHT` 的切线角恒为 0，所以 `rotate_follow` 在那里看不出效果，但 `rotate_bias` 照样能让整串倾斜。
> **`CIRCLE` 不按总宽换算角度**：整段文字永远均匀摊满一整圈。字数越多、字距越挤；想稀疏一点就调大 `radius`。
> **`BEZIER` 的端点和 `align` 联动**：`START` 从原点起拱、`CENTER` 左右对称、`END` 在原点收尾，字沿弧长等距分布。

### 4.3 外观（`@export_group("外观")`）

| 变量名 | 类型 | 默认值 | 作用 | 取值范围 |
| --- | --- | --- | --- | --- |
| `color_start` | `Color` | `Color("fff3e8")` | 首字颜色，按字的序号线性插值到 `color_end` | 任意颜色 |
| `color_end` | `Color` | `Color("f7d292")` | 末字颜色（渐变终点） | 任意颜色 |
| `outline_size` | `int` | `0` | 描边宽度，`0` = 不描边 | 面板范围 1 ~ 8 步进 1；`0` 也是合法值 = 关闭 |
| `outline_color` | `Color` | `Color(0.02, 0.02, 0.04, 0.55)` | 描边颜色（带 alpha） | 任意颜色 |
| `base_alpha` | `float` | `1.0` | 整体透明度乘数，在动画 alpha 之上再乘一次 | 0 ~ 1，步进 0.01 |

> 描边的 range 从 1 开始，但默认值是 0：代码里是 `if outline_size > 0` 才画描边，所以 0 就是「关」，面板上想开就至少拖到 1。

### 4.4 呼吸感（`@export_group("呼吸感")`）

| 变量名 | 类型 | 默认值 | 作用 | 取值范围 |
| --- | --- | --- | --- | --- |
| `jitter` | `float` | `0.0` | 每个字的随机位移半径（像素），`>0` 有手写感。随机种子取自 `text` 的 hash，同一句话每次重排位置固定，不会闪 | 0 ~ 40，步进 0.5 |
| `jitter_rotate` | `float` | `0.0` | 每个字的随机旋转（弧度），正负对称 | 0 ~ 0.6，步进 0.01 |
| `float_amplitude` | `float` | `0.0` | 整串持续上下浮动幅度（像素），`0` = 静止（会关掉 `_process`） | 0 ~ 30，步进 0.5 |
| `float_speed` | `float` | `1.0` | 浮动速度 | 0 ~ 6，步进 0.05 |
| `float_phase` | `float` | `0.9` | 首字到末字的相位差（弧度）：`0` = 所有字一起上下，大一点像波浪从左传到右 | 0 ~ 6，步进 0.05 |

### 4.5 缓慢消失（`@export_group("缓慢消失")`）

| 变量名 | 类型 | 默认值 | 作用 | 取值范围 |
| --- | --- | --- | --- | --- |
| `fade_duration` | `float` | `3.5` | 单个字从全亮到全透明的时长（秒） | 0 ~ 30，步进 0.05 |
| `fade_delay` | `float` | `0.0` | 动画开始前等待（秒） | 0 ~ 10，步进 0.05 |
| `fade_stagger` | `float` | `0.45` | 逐字错开比例：`0` = 所有字同时淡，`0.45` = 从左到右依次淡 | 0 ~ 1，步进 0.01 |
| `fade_power` | `float` | `1.25` | 淡出曲线：`>1` 先保持清晰再快速变淡，`<1` 一上来就开始变淡 | 0.5 ~ 4，步进 0.05 |
| `fade_drift` | `Vector2` | `Vector2(0, -26)` | 消失过程中整串累计漂移的位移（像素） | 任意 `Vector2` |
| `fade_glyph_drift` | `Vector2` | `Vector2(0, -10)` | 每个字额外的漂移，按字的位置 ±1 加权（左半往负方向、右半往正方向）；和 `fade_drift` 叠加 | 任意 `Vector2` |
| `fade_shrink` | `float` | `0.86` | 消失过程中缩到的缩放比例 | 0 ~ 1，步进 0.01 |
| `fade_wobble` | `float` | `0.0` | 消失时左右摇摆的角度（弧度），做「飘散」感 | 0 ~ 12，步进 0.05 |
| `free_when_done` | `bool` | `true` | 动画自然走完后自动 `queue_free()` | `true` / `false` |
| `auto_play` | `bool` | `false` | 入树后自动 `fade_out()` | `true` / `false` |

> `fade_stagger` 越接近 1，「逐字」就越像硬切（每个字几乎瞬间消失）；接近 0 才是整串一起淡。默认 0.45 是「能看出顺序」的中间值。

---

## 五、公共方法

### 5.1 `CurvedText`

| 成员 | 说明 | 示例 |
| --- | --- | --- |
| `fade_out(duration := -1.0, delay := 0.0, stagger := -1.0)` | 缓慢消失。参数传负数表示「沿用导出参数里的值」 | `t.fade_out(4.0, 0.3, 0.6)` |
| `fade_in(duration := 1.6, delay := 0.0, stagger := -1.0)` | 缓慢浮现（`fade_out` 的反向），适合段落逐字出现 | `t.fade_in(1.8, 0.0, 0.65)` |
| `seek(p: float)` | 手动把动画进度定到 `p`（0 = 刚出现，1 = 完全消失），并停掉内部时钟。没动画模式时会先切到 `FADE_OUT` | `t.seek(0.35)` |
| `get_progress() -> float` | 当前进度（0 ~ 1） | `print(t.get_progress())` |
| `get_layout_width() -> float` | 排版后的总宽度（像素，含字距），用来自己算位置 | `var w := t.get_layout_width()` |
| `rebuild() -> void` | 手动重新排版（改了参数但 setter 没触发时用） | `t.radius = 600.0; t.rebuild()` |
| `signal finished` | 动画自然走完时发出，**在 `queue_free()` 之前**；回调里如果又开了下一段动画（`fade_in` / `fade_out` / `seek`），节点不会被释放 | `t.finished.connect(func() -> void: t.fade_out(2.0))` |
| `static default_font() -> Font` | 返回自动回退选出来的字体（主题默认字体，或 CJK 系统字体） | `var f := CurvedText.default_font()` |

### 5.2 `TextFX`（静态工厂）

| 方法 | 说明 | 示例 |
| --- | --- | --- |
| `spawn(parent, text, at, preset_name := "whisper", overrides := {}) -> CurvedText` | 按预设建一条文字并返回节点，`overrides` 是覆盖字典（键 = `CurvedText` 的 `@export` 属性名） | `TextFX.spawn(layer, "喂", Vector2(640, 300), "ring", {"font_size": 44})` |
| `whisper(parent, text, at, overrides := {}) -> CurvedText` | 低语：小小一条拱形文字，慢慢浮起并淡掉 | `TextFX.whisper(layer, "……", Vector2(640, 420))` |
| `banner(parent, text, at, overrides := {}) -> CurvedText` | 大字横幅：大弧线、粗描边，适合「成功 / 接住了」这类反馈 | `TextFX.banner(layer, "接住了", Vector2(640, 200))` |
| `reveal(parent, text, at, overrides := {}) -> CurvedText` | 逐字浮现，用来替代 `Label` 的淡入 | `TextFX.reveal(layer, "第二幕", Vector2(640, 160))` |
| `scatter(parent, text, at, overrides := {}) -> CurvedText` | 飘散：波浪 + 摇摆 + 缩小，边散边消失 | `TextFX.scatter(layer, "再见", Vector2(640, 380))` |
| `ring(parent, text, at, overrides := {}) -> CurvedText` | 环：文字绕成完整一圈，慢慢消失 | `TextFX.ring(layer, "门 / 光 / 你", Vector2(640, 340))` |
| `preset(preset_name) -> Dictionary` | 只返回预设参数字典，不建节点（自己拿去改） | `var cfg := TextFX.preset("banner")` |
| `ui_layer(host, layer := 20, layer_name := "TextFxLayer") -> CanvasLayer` | 在 `host` 下建（或复用）一层 `CanvasLayer` 并返回 | `var ui := TextFX.ui_layer(self)` |

> `spawn` 的顺序是：先赋 `text` → 再套预设 → 再套 `overrides` → 最后才 `add_child()`。所以入树时只排一次版，也不会出现「先闪一下默认参数」。
> `at` 是相对 `parent` 的坐标；`parent` 是 `CanvasLayer` 时就等于屏幕坐标。
> 位置只由 `at` 决定，`overrides` 里写 `position` 会被后面的赋值覆盖（但写 `text` 是有效的，它比 `at` 先设，比 `overrides` 后设）。

---

## 六、预设

`TextFX.preset()` 返回的就是一张「属性名 → 值」的表，键名和 `CurvedText` 的 `@export` 完全一致，所以你可以直接改字典、也可以照样写成 `overrides`。

| 预设 | 曲线与关键参数 | 适合场合 |
| --- | --- | --- |
| `whisper` | `ARC`，`radius 1500`，40px，描边 4，`fade_duration 4.0`，`stagger 0.6`，漂移 −38，缩到 0.92，轻微浮动 3 | 环境低语、内心独白、旁白注释。**最常用** |
| `banner` | `ARC`，`radius 1750`，76px，`glyph_spacing 6`，描边 7，`fade_duration 2.6`，`stagger 0.25`，缩到 0.98 | 大反馈：「成功 / 接住了 / 你赢了」这类要砸出来的字 |
| `reveal` | `ARC`，`radius 1300`，56px，描边 5，`play = "in"`，`fade_duration 1.8`，`stagger 0.65`，向下漂移 +16 | 替代 `Label` 的淡入，一段话逐字浮现 |
| `scatter` | `WAVE`，`amplitude 26`、`length 420`，44px，`stagger 0.8`，漂移 −70，逐字漂移 `(16, −24)`，缩到 0.72，摇摆 0.16 | 消散、被吹走、告别、记忆碎掉 |
| `ring` | `CIRCLE`，`radius 190`，34px，`stagger 0.9`，不漂移，缩到 0.9 | 环绕标题、法阵 / 印记、环形 UI 文字。文字越长越挤，`radius` 要跟着放大 |
| `default`（兜底） | `ARC`，`radius 1200`，48px，描边 4，`fade_duration 3.0`，`stagger 0.5` | 不挑预设、或者传了个不认识的名字时走这组 |

> `"default"` 不是一个显式的 case：代码里 `match` 的 `_` 兜底分支就是那组参数，所以传 `"default"` 或任何未知名字都会得到它。
> 预设**只覆盖它列出来的键**，没列的一律保持类默认值（比如 `align` 永远是 `CENTER`，`free_when_done` 永远是 `true`）。

---

## 七、手动驱动时间轴

`seek()` 是给「不想让它自己走时钟」的场景准备的：它会把内部 `_animating` 关掉，之后进度完全由你给。

### 方式 A：自己算

```gdscript
var t: CurvedText
var _elapsed := 0.0

func _process(delta: float) -> void:
	_elapsed += delta
	var p := clampf(_elapsed / 3.0, 0.0, 1.0)
	p = ease(p, 1.5)          # 缓动交给 ease() / 自己写曲线
	t.seek(p)
```

### 方式 B：`AnimationPlayer` 方法轨道

在 `AnimationPlayer` 里新建动画，加一条**方法调用（Call Method）**轨道：

```
目标节点：CurvedText
方法：seek
参数：1 个 float
关键帧：时间 0.0 → 0.0，时间 3.0 → 1.0
```

这样整条文字就变成一个可被打断、可被倒放、可被 `animation_finished` 信号感知的普通动画。

### 手动做「浮现」

`seek()` 本身不改变动画方向；要手动做浮现，先调一次 `fade_in()` 把模式设成 `FADE_IN`，再驱动 `seek(0 → 1)`：

```gdscript
t.fade_in(1.0)   # 只为把模式设成 FADE_IN
t.seek(0.0)      # 立刻接管，从头开始
```

> `seek()` 只影响淡入淡出这一条时间轴，`float_amplitude` 的呼吸照常跑。
> 想「循环播放」不要指望它自己重来：淡完就 `finished` 了，节点还会按 `free_when_done` 被销毁（见坑 5）。

---

## 八、注意事项 / 坑

### 坑 1：中文字体是自动回退的

`font` 留空时，节点会先试 `ThemeDB.fallback_font`；如果它没有中文字形，就新建一个 `SystemFont`，依次尝试 `Microsoft YaHei` / `微软雅黑` / `PingFang SC` / `Hiragino Sans GB` / `Noto Sans CJK SC` / `Source Han Sans SC` / `SimHei` / `sans-serif`，并打开 `allow_system_fallback`。

所以 Windows / macOS / Linux 上一般「什么都不配就能显示中文」。但**发布到 Web 或移动端时，目标设备不一定有这些字体名**，一旦找不到就可能显示成方框。要稳，就在项目里带一个 `.ttf`：

```gdscript
t.font = load("res://fonts/your_cjk.ttf")
```

字体只在第一次用到时解析并缓存，不会每帧查系统。

### 坑 2：`draw_char` 是按基线画的

`draw_char()` 的落点是**字的基线左端**，不是视觉中心。所以节点 `position` 的 `y` 是基线位置，字身整体在它**上方**（ascent），下方只留 descent。

```gdscript
# 想让一行的"视觉中心"落在 y = 360，一般要往下补一点
t.position = Vector2(640, 360 + t.font_size * 0.35)
```

同理：`align = CENTER` 居中的是**排版宽度**，不是字形的墨迹框，两侧留白会略有差异；像素级对齐请按 `get_layout_width()` 自己微调。

### 坑 3：每个字都是一次独立绘制

`_draw()` 对每个字执行一次 `draw_set_transform()` + `draw_char()`；开了描边则是 `draw_char_outline()` + `draw_char()` 两次。也就是：

| 字数 | 绘制调用量（带描边） | 体感 |
| --- | ---: | --- |
| 十几 ~ 几十字 | 30 ~ 100 次 | 完全没压力，同时开十几条也没事 |
| 100 字上下 | 约 200 次 | 桌面端还行，移动端 / Web 要留意 |
| 几百字 | 400+ 次 | 该合并了：静态长文本改用一次 `draw_string()`，只把要动的部分交给 `CurvedText` |

另外 `_rebuild()` 是 `O(n²)` 级别的：它对每个字都调一次 `get_string_size(前缀)` 来保 kerning。所以**每帧改 `text` / `jitter` 会变成每帧重排** —— 十几二十个字随便改，长文本请「一次排版，只动进度」。

### 坑 4：`@tool` 可以在编辑器里预览

脚本带 `@tool`，所以把 `CurvedText` 加到场景里，**在编辑器里就能实时看到**排版、曲线、颜色、描边、抖动。改 `text` / `curve_mode` / `radius` / `font_size` 会立刻重排。

动画（淡入淡出、呼吸浮动）属于运行时行为，预览请看按 F6 / F5 的真实运行效果。

### 坑 5：`free_when_done` 默认是 `true`

动画自然走完 → 发 `finished` → 如果 `free_when_done` 为真、且信号回调里没有重新开动画，就 `queue_free()`。

```gdscript
# 要复用/循环，先关掉自动销毁
t.free_when_done = false
```

否则「淡完那一刻节点就没了」，下一次再调 `fade_out()` 已经没有节点可用。

有一个已经处理好的细节：**可以在 `finished` 回调里直接接下一段动画**（「浮现 → 停留 → 缓慢消失」这种排队），引擎发完信号后会重新检查是否又有动画在跑，有就不释放节点：

```gdscript
t.finished.connect(func() -> void:
	t.fade_out(2.5)      # 紧接着淡出，节点不会被销毁
)
```

这个判定是**同步**的：回调里当场调 `fade_out()` / `fade_in()` / `seek()` 才算数；如果用 `await` 隔一帧再开，节点已经被释放了。

### 坑 6：`auto_play` 默认是 `false`

默认不会自己动，必须显式 `fade_out()` / `fade_in()`。想「入树即淡出」就把 `auto_play = true`，此时 `_ready()` 会执行 `fade_out(fade_duration, fade_delay)` —— 注意它**不带 stagger 参数**，用的是节点自己的 `fade_stagger`。

### 坑 7：换行不生效

`text` 里的 `\n` 会被当成「不绘制、但推进光标」的字符，**不会真的换行**。多行文字请拆成多个 `CurvedText` 节点，各自给 `position`。

### 坑 8：`align = CENTER` 时，字数变化会让文字左右跳

居中对齐是「以 `position` 为中心重新排」，所以打字机式逐字追加时，每加一个字整串都会重新居中、左右抖一下。要稳用 `Align.START`，或者干脆一个字一个节点。

这不是对齐算法不准（每个字都会沿切线回退半个推进量，三种对齐都贴得很准），纯粹是因为「总宽在变」。`BEZIER` 的拱形端点也一样会跟着 `align` 平移。

### 坑 9：模式不匹配的参数是「静默无效」

`radius` 在 `WAVE` 下不起作用、`wave_amplitude` 在 `ARC` 下不起作用、`bezier_bulge` 只在 `BEZIER` 下起作用。这些不会报错也不会报警告，调了没反应先检查 `curve_mode`。

`rotate_follow` 是个例外中的例外：它在 `STRAIGHT` 下也没有效果（直线没有切线，切线角恒为 0），但那是因为「乘 0」，不是参数被禁用 —— 同一个公式在五种曲线下都在跑，所以 `rotate_bias` 在直线模式下照样有效。

### 坑 10：先设参数、后 `add_child`

没入树时各个 setter 里的 `_rebuild()` 会直接 return（`is_inside_tree()` 为 false），真正的排版发生在 `_ready()`。所以「new → 配参数 → add_child」只会排一次版，是最省的做法；反过来「add_child 后再挨个改参数」会重排好几次（结果一样，只是白花时间）。

`TextFX.spawn()` 就是照这个顺序写的。

### 坑 11：`seek()` 会接管，也会覆盖动画方向

`seek()` 把 `_animating` 设为 `false` 并停掉时钟；如果当前是 `PlayMode.NONE`，它会顺手把模式设成 `FADE_OUT`。所以「先 `fade_in()` 再 `seek()`」才是浮现，单独 `seek()` 是消失。

### 坑 12：`fade_duration = 0` 不是「暂停」

`fade_duration = 0` 时内部总时长按 `0.0001` 算，只要动画在跑就会**瞬间完成**（然后 `finished` + 可能 `queue_free`）。它适合「我只想用 `seek()` 手动喂进度」，不适合「定格」。

---

## 九、加第 6 种曲线

曲线采样全部收在 `_sample_at(s: float) -> Dictionary` 里：输入是「沿排版方向已经走了多少像素」，输出 `{"pos": Vector2, "rot": float, "tangent": Vector2}`。

- `pos`：这个采样点的位置
- `tangent`：这个点的**单位切线方向**（`Vector2`）
- `rot`：字的角度，由框架在 `_sample_at` 末尾统一算出来：`tangent.angle() * rotate_follow + rotate_bias`

所以加新曲线时**只需要给 `pos` 和 `tangent`**，`rotate_follow` / `rotate_bias` 自动就对它生效了 —— 不用自己算 `rot`。

还有两个内部量，做「跟宽度有关」的曲线时会用到：

| 内部量 | 含义 |
| --- | --- |
| `_curve_s0` | 本次排版的起点偏移（`CENTER` 时是 `-宽度/2`，`END` 时是 `-宽度`） |
| `_curve_span` | 本次排版的跨度（= 排版总宽度） |

`CIRCLE` 就是靠 `(s - _curve_s0) / _curve_span` 把整段文字归一化到 0~1，再乘 `TAU`，才做到「不管多少字都均匀摊满一圈」。

### 1. 在枚举末尾加一项

```gdscript
enum CurveShape {
	STRAIGHT, ## 直线
	ARC,      ## 圆弧
	CIRCLE,   ## 整圆
	WAVE,     ## 正弦波
	BEZIER,   ## 二次贝塞尔拱形
	SPIRAL,   ## 螺旋（新加的）
}
```

**必须加在末尾。** 枚举值是按序号序列化的，插在中间会让所有旧场景里存的 `curve_mode` 含义整体错位。
同时记得把名字写成 `CurveShape`（见「四、参数表 · 枚举」的说明），别改回 `Curve`。

### 2. 在 `_sample_at` 的 `match` 里加分支

```gdscript
		CurveShape.SPIRAL:
			var a := s / 70.0                     # 沿弧长的角速度
			var r := spiral_radius + s * 0.35     # 阿基米德螺旋：越走越远
			pos = Vector2(cos(a), sin(a)) * r
			tangent = Vector2(-sin(a), cos(a))    # 单位切线；rot 由框架统一算
```

`pos` 建议保证 `s = 0` 时约为原点、`s` 增大时朝右推进，这样 `align` 的 START/CENTER/END 才是直觉的。

`tangent` **必须是单位向量**：`tangent.angle()` 只看方向、不看长度，所以角度本身不会错；但排版时每个字会沿切线回退半个推进量（`pos - tangent * advance * 0.5`）来对齐，长度不是 1 就会让整段文字整体偏移。`ARC` / `CIRCLE` / `WAVE` 返回的都是单位向量，自己写的时候补一个 `.normalized()`。

### 3. 想加自己的参数

照现有写法，一个 `@export_range` + 一个 `_rebuild()` 的 setter：

```gdscript
@export_range(10.0, 400.0, 1.0) var spiral_radius: float = 80.0:
	set(value):
		spiral_radius = value
		_rebuild()
```

改完回编辑器，`curve_mode` 下拉里就有 `SPIRAL` 了。

### 4. 如果曲线需要「等弧长」采样

`BEZIER` 是特殊的：它先 `_build_bezier()` 打一张 96 段的弧长表，再由 `_sample_bezier()` 按「文字推进距离 → 归一化 → 弧长」二分查表，这样字距才是均匀的（否则控制点附近字会挤在一起）。

你自己的曲线如果想要严格等距，照抄这套 `_bezier_points` / `_bezier_lengths` 的做法即可；不求严格的话，直接像 `SPIRAL` 那样解析式求值就行。

---

## 十、演示场景

编辑器里打开 `addons/text_fx/demo/text_fx_demo.tscn`，按 **F6** 直接运行。它会摆出六条示例：两种半径的圆弧、波浪、贝塞尔拱、整圆、以及 `radius` 为负的反向弧。

- 每条按自己的 `fade_duration` 缓慢淡掉，**9 秒一轮自动重播**（demo 里把 `free_when_done` 设成了 `false`，再用 `seek(0.0) + fade_out()` 重来 —— 这也是「手动时间轴」的一个现成例子）。
- 波浪和拱形那两条的纵向位置、`bezier_bulge` 都单独调过（`bulge = 52`），避免和上下行挤在一起 —— 自己改文案后记得回头调行距。
- 右侧那个整圆用的是 `rotate_follow = 0`（字保持水平、只沿圆周排开，更好读）；想让字贴着圆周转就把它改回 `1`。

这个场景**不依赖任何项目资源**，可以直接搬走当参考。

---

## 一句话总结

**只想要「文字慢慢淡掉、顺着弧线弯过来」**：拷 `addons/text_fx/` 两个 `.gd`，`TextFX.ui_layer(self)` 建一层，`TextFX.whisper(layer, "…", Vector2(640, 420))` 一行就完事。

**想要完全自定义**：`CurvedText.new()` → 改 `@export` 参数 → `add_child()` → `fade_out()`；要跟动画时间轴对齐就改用 `seek()`。
