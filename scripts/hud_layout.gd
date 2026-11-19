extends Node
## HUD 版式驱动器（严格 16:9，设计稿 = 1920x1080）。
##
## 版式（与设计稿一致）：
##
##   ┌──────────────────────────────────────────────────────────┐
##   │ ╲╲   ┌──────────────────────────────┐        ▮  ▮        │
##   │ ╲╲   │                              │        ▮  ▮        │
##   │ 斜    │        画面窗口 Stage         │      压力 麻木      │
##   │ 纹    │                              │        ▮  ▮        │
##   │ 时    └──────────────────────────────┘        ▮  ▮        │
##   │ 间    ┌──────────────────────────────┐                   │
##   │ 条    │      黑底对话框（黄边）         │                   │
##   └────  └──────────────────────────────┘                │
##   └──────────────────────────────────────────────────────────┘
##
## 所有坐标写在 1920x1080 的设计稿空间里，运行时按 16:9 等比缩放。

const DESIGN := Vector2(1920.0, 1080.0)

## ---- 设计稿坐标（1920x1080，改这里就能调版式）----
const TIME_RECT := Rect2(120.0, 20.0, 88.0, 1040.0)
const STAGE_RECT := Rect2(510.0, 30.0, 900.0, 690.0)
const DIALOG_RECT := Rect2(310.0, 740.0, 1290.0, 290.0)
const PRESSURE_RECT := Rect2(1645.0, 65.0, 46.0, 940.0)
const NUMBNESS_RECT := Rect2(1740.0, 65.0, 46.0, 940.0)

const TITLE_POS := Vector2(120.0, 1074.0)
const ROUND_POS := Vector2(510.0 + 900.0 - 20.0 - 420.0, 42.0)
const STATS_POS := Vector2(510.0 + 900.0 - 20.0 - 420.0, 68.0)

## 对话框内边距（设计稿像素）
const PAD_X := 34.0
const PAD_Y := 22.0
## 对话框里可用宽度 / 高度
const DIALOG_INNER_W := 1290.0 - PAD_X * 2.0

var _scale := 1.0
var _origin := Vector2.ZERO
var _game: Node = null


func _ready() -> void:
	_game = get_parent()
	_apply_all()
	get_viewport().size_changed.connect(_apply_all)


func project(rect: Rect2) -> Rect2:
	return Rect2(_origin + rect.position * _scale, rect.size * _scale)


func project_point(p: Vector2) -> Vector2:
	return _origin + p * _scale


func _apply_all() -> void:
	var view := get_viewport().get_visible_rect().size
	_scale = minf(view.x / DESIGN.x, view.y / DESIGN.y)
	_origin = (view - DESIGN * _scale) * 0.5

	var host := get_parent()
	if host == null:
		return

	_place(host, "Backdrop", Rect2(Vector2.ZERO, DESIGN))
	_place(host, "Stage", STAGE_RECT)
	_place(host, "TimeBar", TIME_RECT)
	_place(host, "PressureBar", PRESSURE_RECT)
	_place(host, "NumbnessBar", NUMBNESS_RECT)
	_place(host, "SentencePanel", DIALOG_RECT)

	_point(host, "TitleLabel", TITLE_POS)
	_point(host, "RoundLabel", ROUND_POS)
	_point(host, "StatsLabel", STATS_POS)
	# 统计文字背后的半透明底（画面变亮时保证可读）
	var back := host.get_node_or_null(NodePath("StatsBack")) as Control
	if back != null:
		var br := project(Rect2(ROUND_POS.x - 8.0, ROUND_POS.y - 6.0, 436.0, 58.0))
		back.offset_left = br.position.x
		back.offset_top = br.position.y
		back.offset_right = br.position.x + br.size.x
		back.offset_bottom = br.position.y + br.size.y

	# 右对齐、宽度限定在画面窗口内，防止文字伸出
	for nm in ["RoundLabel", "StatsLabel"]:
		var lab := host.get_node_or_null(NodePath(nm)) as Label
		if lab != null:
			lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			lab.size = Vector2(420.0 * _scale, 24.0 * _scale)
			lab.clip_text = false

	# 好感度标签隐藏（本期不加好感度条）
	var aff := host.get_node_or_null(NodePath("AffectionCaption")) as Label
	if aff != null:
		aff.visible = false
	var aff_panel := host.get_node_or_null(NodePath("AffectionPanel")) as Control
	if aff_panel != null:
		aff_panel.visible = false

	_point(host, "TimeCaption", Vector2(TIME_RECT.position.x - 6.0, 1062.0))
	_point(host, "PressureCaption", Vector2(PRESSURE_RECT.position.x - 8.0, NUMBNESS_RECT.end.y + 12.0))
	_point(host, "NumbnessCaption", Vector2(NUMBNESS_RECT.position.x - 8.0, NUMBNESS_RECT.end.y + 12.0))

	_scale_fonts(host)
	_fit_dialog_fonts(host)


func _place(host: Node, node_name: String, rect: Rect2) -> void:
	var control := host.get_node_or_null(NodePath(node_name)) as Control
	if control == null:
		return
	var r := project(rect)
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = r.position.x
	control.offset_top = r.position.y
	control.offset_right = r.position.x + r.size.x
	control.offset_bottom = r.position.y + r.size.y


func _point(host: Node, node_name: String, pos: Vector2) -> void:
	var control := host.get_node_or_null(NodePath(node_name)) as Control
	if control == null:
		return
	control.position = project_point(pos)


func _scale_fonts(host: Node) -> void:
	var sizes := {
		"TitleLabel": 26, "RoundLabel": 18, "StatsLabel": 12,
		"StateLabel": 22,
		"TimeCaption": 22, "PressureCaption": 22, "NumbnessCaption": 22,
		"PauseTitle": 40, "PauseHint": 24,
	}
	for key in sizes.keys():
		var label := _find_any(host, String(key))
		if label == null:
			continue
		var base: int = int(sizes[key])
		var px := maxi(10, roundi(float(base) * _scale))
		label.add_theme_font_size_override("font_size", px)

	var input_box := _find_any(host, "InputBox")
	if input_box != null:
		input_box.add_theme_font_size_override("font_size", maxi(12, roundi(30.0 * _scale)))


## 对话框里的台词按字数缩字号，保证永远放得下（不溢出、不换行）
func _fit_dialog_fonts(host: Node) -> void:
	if _game == null:
		_game = host
	if _game == null:
		return
	var text := ""
	if "current_sentence" in _game:
		text = String(_game.current_sentence)
	var n := maxi(1, text.length())

	# 台词大字：可用宽度 / 每字宽度，上限 40
	var usable := DIALOG_INNER_W * 0.90 * _scale
	var fit_by_width := int(usable / (1.02 * float(n)))
	var px := clampi(fit_by_width, roundi(18.0 * _scale), roundi(40.0 * _scale))

	for node in host.find_children("SentenceLabel", "", true, false):
		var rtl := node as RichTextLabel
		if rtl != null:
			rtl.add_theme_font_size_override("normal_font_size", maxi(14, px))
			rtl.add_theme_font_override("normal_font", _game._game_font_resource())

func _find_any(host: Node, node_name: String) -> Control:
	var direct := host.get_node_or_null(NodePath(node_name)) as Control
	if direct != null:
		return direct
	for n in host.find_children(node_name, "", true, false):
		var c := n as Control
		if c != null:
			return c
	return null
