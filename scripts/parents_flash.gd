extends Control
## 第二阶段「浮现」画面：那张父母合影。
##
## 需求（改版）：
##   · 不是让人看清，而是让人**注意到有这件事出现了**
##   · 亮度和透明度都压得很低
##   · **淡入淡出**，不再是一闪一闪的硬切换
##   · 只有「特殊句」才会触发这个效果
##
## 用法：
##     flash.begin_show()    淡入并停在那里
##     flash.end_show()      淡出
##     flash.play_once()     完整演一遍（淡入 → 停留 → 淡出），自动收

const IMAGE_PATH := "res://art/stage/parents_flash.png"

## 出现时的最高不透明度（压得很低，只求"被注意到"）
const PEAK_ALPHA := 0.30
## 亮度压暗（1.0 = 原色，越小越暗）
const DIM := 0.55

## 淡入 / 淡出时长
const FADE_IN := 1.4
const FADE_OUT := 1.6
## play_once 时中间停留多久
const HOLD := 3.0

@onready var _tex: TextureRect = $Flash
var _tween: Tween = null
var _visible_now := false
var _alpha := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 根节点必须保持可见（否则子节点不渲染）
	visible = true

	if ResourceLoader.exists(IMAGE_PATH):
		_tex.texture = load(IMAGE_PATH)


## 淡入并保持（进入特殊句期间调用）
func begin_show() -> void:
	if _visible_now:
		return
	_visible_now = true
	_kill_tween()
	_tween = create_tween()
	_tween.tween_method(_set_alpha, _alpha, PEAK_ALPHA, FADE_IN)


## 淡出（离开特殊句时调用）
func end_show() -> void:
	if not _visible_now and _alpha <= 0.001:
		return
	_visible_now = false
	_kill_tween()
	_tween = create_tween()
	_tween.tween_method(_set_alpha, _alpha, 0.0, FADE_OUT)


## 完整演一遍：淡入 → 停留 → 淡出
func play_once() -> void:
	_kill_tween()
	_visible_now = true
	_tween = create_tween()
	_tween.tween_method(_set_alpha, _alpha, PEAK_ALPHA, FADE_IN)
	_tween.tween_interval(HOLD)
	_tween.tween_method(_set_alpha, PEAK_ALPHA, 0.0, FADE_OUT)
	_tween.tween_callback(func() -> void:
		_visible_now = false
	)


func is_showing() -> bool:
	return _visible_now or _alpha > 0.001


func _set_alpha(a: float) -> void:
	_alpha = a
	if _tex != null:
		_tex.modulate = Color(DIM, DIM, DIM, a)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


## 立刻收掉（进剧情 / 结算 / 重开时用）
func stop_flash() -> void:
	_visible_now = false
	_kill_tween()
	_alpha = 0.0
	if _tex != null:
		_tex.modulate = Color(DIM, DIM, DIM, 0.0)


## 兼容旧接口名
func begin_flash() -> void:
	begin_show()


func is_flashing() -> bool:
	return is_showing()
