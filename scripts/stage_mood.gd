extends Control
## 第一阶段画面动态效果。
##
## 规则（按需求）：
##   · 把一套「同一房间，模糊度递增」的图片放进中间的框里
##   · 随着阶段一好感度上升，整体越来越暗，
##     最终压到「最后一张参考图」的暗度（那张图本身不进游戏，只用来定暗度）
##   · 过程中会随机在**相邻**模糊度的图片之间切换（不会跳太远）
##   · 全程带一点轻微摇晃
##
## 用法：
##     mood.set_progress(0.0 ~ 1.0)   # 阶段一好感度进度
##     mood.set_active(true/false)

## 可用图片（按模糊度从轻到重排序）
const IMAGES := [
	"res://art/stage/mood_0.jpg",
	"res://art/stage/mood_1.jpg",
	"res://art/stage/mood_2.jpg",
	"res://art/stage/mood_3.jpg",
	"res://art/stage/mood_4.jpg",
]

## 最后那张参考图的亮度 / 干净图的亮度 ≈ 0.57
## 进度到 1 时所有图都会被压到这个亮度
const FINAL_BRIGHTNESS := 0.57

## 相邻模糊度切换
const SWAP_INTERVAL_MIN := 1.3
const SWAP_INTERVAL_MAX := 3.0
const SWAP_CHANCE := 0.62
const SWAP_FADE := 1.1

## 摇晃
const SHAKE_AMPLITUDE := 3.6
const SHAKE_SPEED := 1.15
## 容器要比画框大一点，摇晃时才不会露边
const BLEED := 10.0

var _progress := 0.0
var _shown_brightness := 1.0

var _holder: Control
var _base: TextureRect
var _over: TextureRect

var _index := 0
var _swap_timer := 0.0
var _swap_target_interval := 2.0
var _fade_tween: Tween = null
var _shake_time := 0.0
var _active := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_shown_brightness = 1.0
	_apply_brightness()
	_set_index(0)
	_pick_next_interval()
	visible = false


func _build() -> void:
	_holder = Control.new()
	_holder.name = "Holder"
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_holder.offset_left = -BLEED
	_holder.offset_top = -BLEED
	_holder.offset_right = BLEED
	_holder.offset_bottom = BLEED
	add_child(_holder)

	_base = _make_rect()
	_holder.add_child(_base)
	_over = _make_rect()
	_holder.add_child(_over)


func _make_rect() -> TextureRect:
	var rect := TextureRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	return rect


func _load(index: int) -> Texture2D:
	var path: String = IMAGES[clampi(index, 0, IMAGES.size() - 1)]
	if not ResourceLoader.exists(path):
		return null
	return load(path)


func _set_index(index: int) -> void:
	_index = clampi(index, 0, IMAGES.size() - 1)
	var tex := _load(_index)
	if tex != null:
		_base.texture = tex
	_over.texture = null
	_over.modulate.a = 0.0


## 阶段一好感度进度：0 = 最清晰、1 = 压到最暗
func set_progress(value: float) -> void:
	_progress = clampf(value, 0.0, 1.0)


func set_active(on: bool) -> void:
	_active = on
	visible = on
	if on:
		_swap_timer = 0.0
		_pick_next_interval()


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	if not _active:
		return

	# 1) 亮度：平滑逼近目标
	var target := lerpf(1.0, FINAL_BRIGHTNESS, _progress)
	_shown_brightness = lerpf(_shown_brightness, target, clampf(delta * 1.6, 0.0, 1.0))
	_apply_brightness()

	# 2) 摇晃：两条不同频率的正弦叠加，看起来像轻微的呼吸式晃动
	_shake_time += delta * SHAKE_SPEED
	var amp := SHAKE_AMPLITUDE * (0.7 + 0.3 * _progress)
	var ox := sin(_shake_time * 1.7) * amp + sin(_shake_time * 3.9) * amp * 0.35
	var oy := cos(_shake_time * 1.3) * amp * 0.8 + cos(_shake_time * 4.3) * amp * 0.3
	_holder.position = Vector2(ox, oy)

	# 3) 随机切到相邻模糊度
	_swap_timer += delta
	if _swap_timer >= _swap_target_interval:
		_swap_timer = 0.0
		_pick_next_interval()
		if randf() < SWAP_CHANCE:
			_swap_to_adjacent()


func _apply_brightness() -> void:
	_holder.modulate = Color(_shown_brightness, _shown_brightness, _shown_brightness, 1.0)


func _pick_next_interval() -> void:
	_swap_target_interval = randf_range(SWAP_INTERVAL_MIN, SWAP_INTERVAL_MAX)


## 在相邻（±1）里随机挑一个，不会跨级跳
func _swap_to_adjacent() -> void:
	var options: Array[int] = []
	if _index > 0:
		options.append(_index - 1)
	if _index < IMAGES.size() - 1:
		options.append(_index + 1)
	if options.is_empty():
		return
	var next_index: int = options[randi() % options.size()]
	_crossfade_to(next_index)


## 两张图交叉淡入，避免硬切
func _crossfade_to(index: int) -> void:
	var tex := _load(index)
	if tex == null:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_index = index
	_over.texture = tex
	_over.modulate.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(_over, "modulate:a", 1.0, SWAP_FADE)
	_fade_tween.tween_callback(func() -> void:
		if not is_instance_valid(_over) or not is_instance_valid(_base):
			return
		_base.texture = _over.texture
		_over.modulate.a = 0.0
		_over.texture = null
	)


## 立即切到最清晰的图（重开游戏时用）
func reset() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_progress = 0.0
	_shown_brightness = 1.0
	_index = 0
	_swap_timer = 0.0
	_shake_time = 0.0
	_set_index(0)
	_apply_brightness()
	if _holder != null:
		_holder.position = Vector2.ZERO
