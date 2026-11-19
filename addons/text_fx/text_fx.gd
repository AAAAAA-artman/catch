class_name TextFX
extends RefCounted
## 文字特效的「开箱即用」入口：预设 + 一行代码生成。
##
## 和 CurvedText 一样不依赖任何项目资源，复制 addons/text_fx/ 整个目录即可移植。
## 典型用法：
##     TextFX.whisper(self, "门还没有关上", Vector2(640, 420))
##     TextFX.banner(self, "接住了", Vector2(640, 200))
##     var layer := TextFX.ui_layer(self)          # 自动建一层 UI 画布（默认 layer=20）
##     TextFX.whisper(layer, "……", Vector2(640, 300))


## 生成一条带「弯曲 + 缓慢消失」的文字，并返回节点（可以继续改属性）。
## at 是相对 parent 的坐标；如果 parent 是 CanvasLayer，就等于屏幕坐标。
static func spawn(parent: Node, text: String, at: Vector2, preset_name: String = "whisper", overrides: Dictionary = {}) -> CurvedText:
	if parent == null:
		push_warning("TextFX.spawn: parent 为空")
		return null
	var node := CurvedText.new()
	node.name = "CurvedText"
	node.text = text
	var cfg := preset(preset_name)
	var play: String = "out"
	if cfg.has("play"):
		play = cfg["play"]
		cfg.erase("play")
	# 先配参数再入树，入树时 _ready() 会一次性排版
	for key in cfg.keys():
		node.set(key, cfg[key])
	for key in overrides.keys():
		node.set(key, overrides[key])
	node.position = at
	parent.add_child(node)
	match play:
		"out":
			node.fade_out()
		"in":
			node.fade_in()
	return node


## 低语：小小一条拱形文字，慢慢浮起并淡掉。
static func whisper(parent: Node, text: String, at: Vector2, overrides: Dictionary = {}) -> CurvedText:
	return spawn(parent, text, at, "whisper", overrides)


## 大字横幅：大弧线、粗描边，适合"接住了 / 成功"这类反馈。
static func banner(parent: Node, text: String, at: Vector2, overrides: Dictionary = {}) -> CurvedText:
	return spawn(parent, text, at, "banner", overrides)


## 逐字浮现，用来替代 Label 的淡入。
static func reveal(parent: Node, text: String, at: Vector2, overrides: Dictionary = {}) -> CurvedText:
	return spawn(parent, text, at, "reveal", overrides)


## 飘散：波浪 + 摇摆 + 缩小，边散边消失。
static func scatter(parent: Node, text: String, at: Vector2, overrides: Dictionary = {}) -> CurvedText:
	return spawn(parent, text, at, "scatter", overrides)


## 环：文字绕成完整一圈，慢慢消失。
static func ring(parent: Node, text: String, at: Vector2, overrides: Dictionary = {}) -> CurvedText:
	return spawn(parent, text, at, "ring", overrides)


## 派生的预设参数（返回字典，属性名 = CurvedText 的 @export）。
static func preset(preset_name: String) -> Dictionary:
	match preset_name:
		"whisper":
			return {
				"curve_mode": CurvedText.CurveShape.ARC,
				"radius": 1500.0,
				"font_size": 40,
				"color_start": Color("fff3e8"),
				"color_end": Color("f7d292"),
				"outline_size": 4,
				"outline_color": Color(0.02, 0.02, 0.04, 0.6),
				"fade_duration": 4.0,
				"fade_power": 1.3,
				"fade_stagger": 0.6,
				"fade_drift": Vector2(0.0, -38.0),
				"fade_glyph_drift": Vector2(0.0, -14.0),
				"fade_shrink": 0.92,
				"float_amplitude": 3.0,
				"float_speed": 1.1,
				"play": "out",
			}
		"banner":
			return {
				"curve_mode": CurvedText.CurveShape.ARC,
				"radius": 1750.0,
				"font_size": 76,
				"glyph_spacing": 6.0,
				"color_start": Color("fff3e8"),
				"color_end": Color("f7a26b"),
				"outline_size": 7,
				"outline_color": Color(0.03, 0.02, 0.05, 0.72),
				"fade_duration": 2.6,
				"fade_power": 1.5,
				"fade_stagger": 0.25,
				"fade_drift": Vector2(0.0, -18.0),
				"fade_glyph_drift": Vector2.ZERO,
				"fade_shrink": 0.98,
				"play": "out",
			}
		"reveal":
			return {
				"curve_mode": CurvedText.CurveShape.ARC,
				"radius": 1300.0,
				"font_size": 56,
				"color_start": Color("fff3e8"),
				"color_end": Color("c8c3d8"),
				"outline_size": 5,
				"outline_color": Color(0.02, 0.02, 0.04, 0.55),
				"fade_duration": 1.8,
				"fade_power": 1.0,
				"fade_stagger": 0.65,
				"fade_drift": Vector2(0.0, 16.0),
				"fade_glyph_drift": Vector2.ZERO,
				"fade_shrink": 1.0,
				"play": "in",
			}
		"scatter":
			return {
				"curve_mode": CurvedText.CurveShape.WAVE,
				"wave_amplitude": 26.0,
				"wave_length": 420.0,
				"font_size": 44,
				"color_start": Color("c8c3d8"),
				"color_end": Color("6f6a86"),
				"outline_size": 3,
				"outline_color": Color(0.02, 0.02, 0.04, 0.5),
				"fade_duration": 3.2,
				"fade_power": 1.15,
				"fade_stagger": 0.8,
				"fade_drift": Vector2(0.0, -70.0),
				"fade_glyph_drift": Vector2(16.0, -24.0),
				"fade_shrink": 0.72,
				"fade_wobble": 0.16,
				"play": "out",
			}
		"ring":
			return {
				"curve_mode": CurvedText.CurveShape.CIRCLE,
				"radius": 190.0,
				"font_size": 34,
				"color_start": Color("f7d292"),
				"color_end": Color("a9a4a9"),
				"outline_size": 3,
				"outline_color": Color(0.02, 0.02, 0.04, 0.5),
				"fade_duration": 3.5,
				"fade_power": 1.2,
				"fade_stagger": 0.9,
				"fade_drift": Vector2.ZERO,
				"fade_glyph_drift": Vector2.ZERO,
				"fade_shrink": 0.9,
				"play": "out",
			}
		_:
			return {
				"curve_mode": CurvedText.CurveShape.ARC,
				"radius": 1200.0,
				"font_size": 48,
				"fade_duration": 3.0,
				"fade_stagger": 0.5,
				"outline_size": 4,
				"play": "out",
			}


## 在 host 下面要一层 TextFx 画布并返回它。
## layer 建议：场景世界 0 → 后期滤镜 10 → UI/文字特效 20+。
## 已经存在同名同层节点时直接复用，所以可以放心反复调用。
static func ui_layer(host: Node, layer: int = 20, layer_name: String = "TextFxLayer") -> CanvasLayer:
	if host == null:
		return null
	var existing := host.get_node_or_null(NodePath(layer_name))
	if existing is CanvasLayer:
		return existing as CanvasLayer
	var canvas := CanvasLayer.new()
	canvas.name = layer_name
	canvas.layer = layer
	host.add_child(canvas)
	return canvas
