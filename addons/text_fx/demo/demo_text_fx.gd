extends Control
## 文字特效演示场：把 CurvedText / TextFX 的每种曲线和「缓慢消失」都摆一遍。
## 这个场景完全独立，不依赖接住项目的任何东西，可以直接搬到别的项目里跑（F6 运行）。

const SHOWCASE := [
	# 大弧线：像一句悬浮在房间里的话
	{"text": "你终于被听见了", "mode": CurvedText.CurveShape.ARC, "radius": 1500.0, "size": 52, "x": 620.0, "y": 96.0},
	# 中等弧线
	{"text": "字幕沿着弧线弯过来", "mode": CurvedText.CurveShape.ARC, "radius": 900.0, "size": 34, "x": 620.0, "y": 192.0},
	# 正弦波
	{"text": "文字可以弯成波浪", "mode": CurvedText.CurveShape.WAVE, "amplitude": 26.0, "length": 260.0, "size": 34, "x": 620.0, "y": 302.0},
	# 二次贝塞尔拱形
	{"text": "也可以弯成拱形", "mode": CurvedText.CurveShape.BEZIER, "bulge": 52.0, "size": 34, "x": 620.0, "y": 462.0},
	# 整圆：rot 0 = 字保持水平，只沿圆周排开
	{"text": "绕成一整圈悬浮着", "mode": CurvedText.CurveShape.CIRCLE, "radius": 96.0, "size": 20, "x": 1080.0, "y": 132.0, "rotate": 0.0},
	# 反向弧（下凹），最后一个慢慢淡掉
	{"text": "逐渐变淡，像被房间吸走", "mode": CurvedText.CurveShape.ARC, "radius": -1000.0, "size": 30, "x": 620.0, "y": 606.0},
]

const CYCLE_SECONDS := 9.0

var _items: Array[CurvedText] = []
var _clock := 0.0


func _ready() -> void:
	_build_background()
	for cfg in SHOWCASE:
		_make(cfg)
	_restart()


func _process(delta: float) -> void:
	_clock += delta
	if _clock >= CYCLE_SECONDS:
		_restart()


func _restart() -> void:
	_clock = 0.0
	for item in _items:
		if not is_instance_valid(item):
			continue
		item.seek(0.0)
		item.fade_out(item.fade_duration, 0.35, item.fade_stagger)


func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color("0b0d14")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var hint := Label.new()
	hint.text = "TextFX / CurvedText demo   ——   每个字沿曲线排版，然后缓慢淡出"
	hint.position = Vector2(32.0, 24.0)
	hint.add_theme_color_override("font_color", Color("8d8798"))
	hint.add_theme_font_size_override("font_size", 15)
	add_child(hint)


func _make(cfg: Dictionary) -> void:
	var node := CurvedText.new()
	node.text = cfg["text"]
	node.curve_mode = cfg["mode"]
	node.align = CurvedText.Align.CENTER
	node.font_size = int(cfg["size"])
	node.outline_size = 5
	node.outline_color = Color(0.02, 0.02, 0.04, 0.6)
	node.color_start = Color("fff3e8")
	node.color_end = Color("f7d292")
	node.jitter = 0.0
	node.fade_duration = CYCLE_SECONDS - 1.2
	node.fade_stagger = 0.7
	node.fade_power = 1.2
	node.free_when_done = false
	node.fade_drift = Vector2(0.0, -30.0)
	node.fade_glyph_drift = Vector2(0.0, -8.0)
	node.fade_shrink = 0.9
	node.float_amplitude = 2.1
	node.position = Vector2(cfg["x"], cfg["y"])
	if cfg.has("radius"):
		node.radius = cfg["radius"]
	if cfg.has("amplitude"):
		node.wave_amplitude = cfg["amplitude"]
		node.wave_length = cfg["length"]
	if cfg.has("bulge"):
		node.bezier_bulge = cfg["bulge"]
	if cfg.has("rotate"):
		# 0 = 所有字保持水平，只沿圆周排开（环形文字更好读）
		node.rotate_follow = cfg["rotate"]
	add_child(node)
	_items.append(node)
