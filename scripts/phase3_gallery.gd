extends Control
## 第三阶段画面：按好感度顺序逐张触发全家福照片，第 2 张起铺满全屏。
##
## 节点直接挂在 Main 根下（不在 Stage/Clip 里，避免被 clip_contents 裁掉）。
## 层级用 z_index 控制：压在游戏内容之上，但低于时间条/对话框。
##
## 节奏（按需求）：
##   · 第 1 张（房间里的怪物，4:3）→ 小屏，只占画面窗口
##   · 第 2 张起（父母合影 / 三人合影系列，16:9）→ **全屏**
##   · 随阶段三好感度上升一张一张换

## 每张图的配置：path / at（阶段三进度 0~1）/ full / fade
const SLIDES := [
	{
		"path": "res://b83e92790a4ae298b79847dfb619ad5f.jpg",
		"at": 0.00, "full": false, "fade": 1.6,
	},
	{
		"path": "res://art/stage/p3_2_parents.png",
		"at": 0.34, "full": true, "fade": 1.4,
	},
	{
		"path": "res://art/stage/p3_3_three_black.jpg",
		"at": 0.50, "full": true, "fade": 1.4,
	},
	{
		"path": "res://art/stage/p3_4_three_glasses.jpg",
		"at": 0.66, "full": true, "fade": 1.4,
	},
	{
		"path": "res://art/stage/p3_5_three_bright.jpg",
		"at": 0.80, "full": true, "fade": 1.4,
	},
	{
		"path": "res://art/stage/p3_6_three_shadow.jpg",
		"at": 0.90, "full": true, "fade": 1.4,
	},
	{
		"path": "res://art/stage/p3_7_three_close.jpg",
		"at": 0.97, "full": true, "fade": 1.4,
	},
]

## 小屏模式下照片占画面窗口的比例
const INSET_RATIO := 0.94

## 全屏时的亮度（压暗，让上层 HUD 文字仍然读得清）
const FULL_DIM := 0.62
## 小屏时不压暗
const INSET_DIM := 0.92

var _progress := 0.0
var _active := false
var _index := -1

var _root: Control
var _base: TextureRect
var _over: TextureRect
var _fade_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_base = _make_rect()
	_root.add_child(_base)
	_over = _make_rect()
	_root.add_child(_over)

	_root.visible = false


func _make_rect() -> TextureRect:
	var r := TextureRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.modulate.a = 0.0
	return r


## 阶段三进度 0~1
func set_progress(value: float) -> void:
	_progress = clampf(value, 0.0, 1.0)
	var want := _index_for(_progress)
	if want != _index:
		_show_slide(want, _index < 0)


func set_active(on: bool) -> void:
	_active = on
	# 自己的 visible 也要开，否则子节点再可见也画不出来
	visible = on
	if _root != null:
		_root.visible = on
	if on:
		_index = -1
		set_progress(_progress)
	else:
		if _fade_tween != null and _fade_tween.is_valid():
			_fade_tween.kill()
		_index = -1
		if _base != null:
			_base.modulate.a = 0.0
		if _over != null:
			_over.modulate.a = 0.0


func is_active() -> bool:
	return _active


func _index_for(p: float) -> int:
	var idx := 0
	for i in SLIDES.size():
		if p >= float(SLIDES[i]["at"]):
			idx = i
	return idx


func _show_slide(index: int, first: bool) -> void:
	index = clampi(index, 0, SLIDES.size() - 1)
	var cfg: Dictionary = SLIDES[index]
	var path: String = cfg["path"]
	if not ResourceLoader.exists(path):
		push_warning("Phase3Gallery: 找不到 %s" % path)
		return
	var tex: Texture2D = load(path)
	if tex == null:
		return

	_layout_for(cfg)
	_index = index
	# 全屏时压暗，保证对话框/时间条文字仍然可读
	var dim := FULL_DIM if bool(cfg["full"]) else INSET_DIM
	_base.modulate = Color(dim, dim, dim, _base.modulate.a)

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	if first:
		_base.texture = tex
		_base.modulate.a = 0.0
		_fade_tween = create_tween()
		_fade_tween.tween_property(_base, "modulate:a", 1.0, float(cfg["fade"]))
		return

	_over.texture = tex
	_over.modulate.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(_over, "modulate:a", 1.0, float(cfg["fade"]))
	_fade_tween.tween_callback(func() -> void:
		if not is_instance_valid(_base) or not is_instance_valid(_over):
			return
		_base.texture = _over.texture
		_base.modulate.a = 1.0
		_over.modulate.a = 0.0
		_over.texture = null
	)


## 全屏铺满 or 只占画面窗口
func _layout_for(cfg: Dictionary) -> void:
	var full: bool = bool(cfg["full"])
	for r in [_base, _over]:
		if full:
			r.anchor_left = 0.0
			r.anchor_top = 0.0
			r.anchor_right = 1.0
			r.anchor_bottom = 1.0
			r.offset_left = 0.0
			r.offset_top = 0.0
			r.offset_right = 0.0
			r.offset_bottom = 0.0
		else:
			# 小屏：完整塞进画面窗口（保持图片比例，不裁切）
			var area := _stage_rect()
			var avail := area.size * INSET_RATIO
			var tex_size := Vector2(4.0, 3.0)
			if r == _base and _base.texture != null:
				tex_size = _base.texture.get_size()
			elif r == _over and _over.texture != null:
				tex_size = _over.texture.get_size()
			var fit := minf(avail.x / maxf(tex_size.x, 1.0), avail.y / maxf(tex_size.y, 1.0))
			var w := tex_size.x * fit
			var h := tex_size.y * fit
			r.anchor_left = 0.0
			r.anchor_top = 0.0
			r.anchor_right = 0.0
			r.anchor_bottom = 0.0
			r.offset_left = area.position.x + (area.size.x - w) * 0.5
			r.offset_top = area.position.y + (area.size.y - h) * 0.5
			r.offset_right = r.offset_left + w
			r.offset_bottom = r.offset_top + h
			# 小屏完整显示，不裁切
			r.stretch_mode = TextureRect.STRETCH_SCALE
			continue
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED


## 画面窗口（Stage）在屏幕上的矩形
func _stage_rect() -> Rect2:
	var main := get_tree().current_scene
	if main != null:
		var stage := main.get_node_or_null("Stage") as Control
		if stage != null and stage.size.x > 1.0:
			return Rect2(stage.global_position, stage.size)
	var vp := get_viewport().get_visible_rect().size
	return Rect2(vp.x * 0.18, vp.y * 0.03, vp.x * 0.60, vp.y * 0.62)


func reset() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_progress = 0.0
	_index = -1
	if _base != null:
		_base.modulate.a = 0.0
		_base.texture = null
	if _over != null:
		_over.modulate.a = 0.0
		_over.texture = null
