extends Control
## 第三阶段画面：全家福照片序列 + 入场的「交替 → 拉开」过场。
##
## 节奏（按需求）：
##   1) 本阶段**第一句**时：第 1 张（房间）和第 2 张（合影）在**画面中心小框**里交替闪现
##   2) 打完第一句：中心框体**拉开**成整屏
##   3) 之后：照片一张张填满整屏
##
## 节点直接挂在 Main 根下（避免被 Stage/Clip 的 clip_contents 裁掉）。

## 图片列表（索引与 SLIDE_AT 对应）
const SLIDES := [
	"res://b83e92790a4ae298b79847dfb619ad5f.jpg",       # 0 房间里
	"res://art/stage/p3_2_parents.png",                # 1 父母合影
	"res://art/stage/p3_3_three_black.jpg",            # 2 三人·全黑脸
	"res://art/stage/p3_4_three_glasses.jpg",          # 3 三人·墨镜
	"res://art/stage/p3_5_three_bright.jpg",           # 4 三人·明亮
	"res://art/stage/p3_6_three_shadow.jpg",           # 5 三人·有影子
	"res://art/stage/p3_7_three_close.jpg",            # 6 三人·近景
]

## 每张图从阶段三的多少进度开始显示
const SLIDE_AT := [0.00, 0.34, 0.50, 0.66, 0.80, 0.90, 0.97]

## ---- 入场：中心小框里交替 ----
const INTRO_SIZE_RATIO := 0.46
const INTRO_SWAP := 0.55
const INTRO_A := 0
const INTRO_B := 1

## ---- 拉开动画 ----
const EXPAND_TIME := 1.5
const FULL_DIM := 0.62
const INTRO_DIM := 0.94

## 后续照片切换的交叉淡入时长
const SWAP_FADE := 1.4

var _progress := 0.0
var _active := false
var _index := -1

var _intro := false
var _intro_timer := 0.0
var _intro_show_b := false
var _expanded := false

var _root: Control
var _base: TextureRect
var _cover: TextureRect
var _swap: TextureRect
var _fade_tween: Tween = null
var _expand_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_base = _make_rect()
	_root.add_child(_base)
	_cover = _make_rect()
	_root.add_child(_cover)
	_swap = _make_rect()
	_root.add_child(_swap)
	_root.visible = false


func _make_rect() -> TextureRect:
	var r := TextureRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.modulate.a = 0.0
	return r


func _tex(i: int) -> Texture2D:
	i = clampi(i, 0, SLIDES.size() - 1)
	var p: String = SLIDES[i]
	if not ResourceLoader.exists(p):
		return null
	return load(p)


# ================================================================ 对外接口

func set_active(on: bool) -> void:
	_active = on
	# 进入第三阶段时**不显示任何东西** —— 第一句要保持原布局
	# 图片只在第一句打完后（expand_to_full）才开始交替
	if _root != null:
		_root.visible = false
	visible = on
	if on:
		_intro = false
		_intro_timer = 0.0
		_intro_show_b = false
		_expanded = false
		_index = -1
		# 不清 texture，等 expand 时再填
	else:
		_kill_tweens()
		_intro = false
		_expanded = false
		_index = -1
		for r in [_base, _cover, _swap]:
			if r != null:
				r.modulate.a = 0.0


func is_active() -> bool:
	return _active


func set_progress(value: float) -> void:
	_progress = clampf(value, 0.0, 1.0)
	if _intro or not _expanded:
		return
	var want := _index_for(_progress)
	if want != _index:
		_show_slide(want)


## 打完第一句时调用：把中心框拉开成整屏
func expand_to_full() -> void:
	if _expanded or not _active:
		return
	_expanded = true
	_kill_tweens()

	# 先把小框交替打开（第一句期间它是隐藏的）
	if _root != null:
		_root.visible = true

	_swap.modulate.a = 0.0
	_swap.texture = null

	_index = 1
	_cover.texture = _tex(_index)
	_cover.modulate = Color(INTRO_DIM, INTRO_DIM, INTRO_DIM, 1.0)
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_apply_rect(_cover, _intro_rect())

	var vp := get_viewport_rect().size
	_expand_tween = create_tween()
	_expand_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_expand_tween.set_parallel(true)
	_expand_tween.tween_property(_cover, "offset_left", 0.0, EXPAND_TIME)
	_expand_tween.tween_property(_cover, "offset_top", 0.0, EXPAND_TIME)
	_expand_tween.tween_property(_cover, "offset_right", vp.x, EXPAND_TIME)
	_expand_tween.tween_property(_cover, "offset_bottom", vp.y, EXPAND_TIME)
	_expand_tween.tween_property(_cover, "modulate",
		Color(FULL_DIM, FULL_DIM, FULL_DIM, 1.0), EXPAND_TIME)


## 直接换一张图（终章配图用），带淡入
func show_image(path: String, fade: float = 0.85) -> void:
	if _cover == null or not _active:
		return
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	if tex == null:
		return
	if _cover.texture == tex:
		return
	# 先铺到 _swap，再交叉淡入
	var vp := get_viewport_rect().size
	_swap.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_apply_rect(_swap, Rect2(Vector2.ZERO, vp))
	_swap.texture = tex
	_swap.modulate = Color(FULL_DIM, FULL_DIM, FULL_DIM, 0.0)
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_swap, "modulate", Color(FULL_DIM, FULL_DIM, FULL_DIM, 1.0), fade)
	_fade_tween.tween_callback(func() -> void:
		if not is_instance_valid(_cover) or not is_instance_valid(_swap):
			return
		_cover.texture = _swap.texture
		_cover.modulate = Color(FULL_DIM, FULL_DIM, FULL_DIM, 1.0)
		_swap.modulate.a = 0.0
		_swap.texture = null
	)


func is_expanded() -> bool:
	return _expanded


func reset() -> void:
	_kill_tweens()
	_progress = 0.0
	_index = -1
	_intro = false
	_expanded = false
	if _base != null:
		_base.modulate.a = 0.0
		_base.texture = null
	if _cover != null:
		_cover.modulate.a = 0.0
		_cover.texture = null
	if _swap != null:
		_swap.modulate.a = 0.0
		_swap.texture = null


# ================================================================ 内部

func _process(delta: float) -> void:
	if not _active or not _intro:
		return
	_intro_timer += delta
	if _intro_timer >= INTRO_SWAP:
		_intro_timer = 0.0
		_intro_show_b = not _intro_show_b
		_show_intro_pair()


func _show_intro_pair() -> void:
	var area := _intro_rect()
	_base.modulate.a = 0.0
	_base.texture = null
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_swap.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

	for r in [_cover, _swap]:
		_apply_rect(r, area)

	if _intro_show_b:
		_cover.texture = _tex(INTRO_A)
		_swap.texture = _tex(INTRO_B)
		_cover.modulate = Color(INTRO_DIM, INTRO_DIM, INTRO_DIM, 0.0)
		_swap.modulate = Color(INTRO_DIM, INTRO_DIM, INTRO_DIM, 1.0)
	else:
		_cover.texture = _tex(INTRO_B)
		_swap.texture = _tex(INTRO_A)
		_cover.modulate = Color(INTRO_DIM, INTRO_DIM, INTRO_DIM, 1.0)
		_swap.modulate = Color(INTRO_DIM, INTRO_DIM, INTRO_DIM, 0.0)


func _intro_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var side := minf(vp.x, vp.y) * INTRO_SIZE_RATIO
	var w := side * 1.35
	var h := side
	return Rect2(Vector2((vp.x - w) * 0.5, (vp.y - h) * 0.5), Vector2(w, h))


func _apply_rect(r: TextureRect, rect: Rect2) -> void:
	r.anchor_left = 0.0
	r.anchor_top = 0.0
	r.anchor_right = 0.0
	r.anchor_bottom = 0.0
	r.offset_left = rect.position.x
	r.offset_top = rect.position.y
	r.offset_right = rect.position.x + rect.size.x
	r.offset_bottom = rect.position.y + rect.size.y


func _index_for(p: float) -> int:
	# 展开之后：**整段第三阶段都停在合影这一张**，
	# 直到好感度升满才换成最后一张（要求：背景到满好感前不更换）。
	if _expanded:
		if p >= 0.999:
			return SLIDES.size() - 1
		return 1
	var idx := 0
	for i in SLIDE_AT.size():
		if p >= float(SLIDE_AT[i]):
			idx = i
	return idx


func _show_slide(index: int) -> void:
	index = clampi(index, 0, SLIDES.size() - 1)
	var tex := _tex(index)
	if tex == null:
		return
	_index = index

	var vp := get_viewport_rect().size
	_swap.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_apply_rect(_swap, Rect2(Vector2.ZERO, vp))
	_swap.texture = tex
	_swap.modulate = Color(FULL_DIM, FULL_DIM, FULL_DIM, 0.0)

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_swap, "modulate", Color(FULL_DIM, FULL_DIM, FULL_DIM, 1.0), SWAP_FADE)
	_fade_tween.tween_callback(func() -> void:
		if not is_instance_valid(_cover) or not is_instance_valid(_swap):
			return
		_cover.texture = _swap.texture
		_cover.modulate = Color(FULL_DIM, FULL_DIM, FULL_DIM, 1.0)
		_swap.modulate.a = 0.0
		_swap.texture = null
	)


func _kill_tweens() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	if _expand_tween != null and _expand_tween.is_valid():
		_expand_tween.kill()
