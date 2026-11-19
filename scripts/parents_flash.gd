extends Control
## 第二阶段「闪现」画面：那张父母合影。
##
## 需求：
##   · 不是让人看清，而是让人**注意到有这件事出现了**
##   · 所以亮度和透明度都压得很低，只做一闪一闪的替换
##   · 蓝色背景（MoodLayer / 房间背景）会被它短暂顶掉
##
## 用法：
##     flash.begin_flash()   开始闪烁替换
##     flash.stop_flash()    停止并还原

const IMAGE_PATH := "res://art/stage/parents_flash.png"

## 闪一下亮、一下灭的节奏
const ON_TIME_MIN := 0.10
const ON_TIME_MAX := 0.26
const OFF_TIME_MIN := 0.14
const OFF_TIME_MAX := 0.42

## 出现时的最高不透明度（压得很低，只求"被注意到"）
const PEAK_ALPHA := 0.30
## 亮度压暗（1.0 = 原色，越小越暗）
const DIM := 0.55

var _tex: TextureRect
var _flash_time := 0.0
var _on_duration := 0.2
var _off_duration := 0.25
var _showing := false
var _active := false
var _target_alpha := 0.0
var _alpha := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

	_tex = TextureRect.new()
	_tex.name = "Flash"
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_tex.modulate = Color(DIM, DIM, DIM, 0.0)
	if ResourceLoader.exists(IMAGE_PATH):
		_tex.texture = load(IMAGE_PATH)
	add_child(_tex)
	_pick_durations()


func begin_flash() -> void:
	if _active:
		return
	_active = true
	visible = true
	_flash_time = 0.0
	_showing = false
	_alpha = 0.0
	_pick_durations()


func stop_flash() -> void:
	_active = false
	_showing = false
	_target_alpha = 0.0
	_alpha = 0.0
	if _tex != null:
		_tex.modulate = Color(DIM, DIM, DIM, 0.0)
	visible = false


func is_flashing() -> bool:
	return _active


func _pick_durations() -> void:
	_on_duration = randf_range(ON_TIME_MIN, ON_TIME_MAX)
	_off_duration = randf_range(OFF_TIME_MIN, OFF_TIME_MAX)


func _process(delta: float) -> void:
	if not _active or _tex == null:
		return
	_flash_time += delta
	if _showing:
		if _flash_time >= _on_duration:
			_showing = false
			_flash_time = 0.0
			_target_alpha = 0.0
			_pick_durations()
	else:
		if _flash_time >= _off_duration:
			_showing = true
			_flash_time = 0.0
			_target_alpha = PEAK_ALPHA
			_pick_durations()

	# 快速逼近目标透明度（一闪而过，不要平滑到看不出来）
	_alpha = lerpf(_alpha, _target_alpha, clampf(delta * 26.0, 0.0, 1.0))
	_tex.modulate = Color(DIM, DIM, DIM, _alpha)
