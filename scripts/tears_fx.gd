extends Control
## 泪水滤镜：接到负面句子时，最上层短暂盖一层「眼前涌上泪水」的效果。
##
## 视觉语言（不是"哭得很惨"，而是"一瞬间看不清了"）：
##   · 水波扭曲 —— 透过水膜看东西，画面轻微晃
##   · 纵向泪痕 —— 沿 Y 轴往下拖一点
##   · 边缘模糊 —— 越靠边越糊，中心尽量保持可读
##   · 去饱和 + 泛蓝 —— 视野发冷
##   · 暗角收窄 —— 视野变窄
##   · 水珠高光 —— 几处反光点
##
## 强度由 strength 统一控制，脚本做淡入 → 停留 → 淡出。
##
## 位置：挂在最上层（z_index 高于 HUD），但 mouse_filter = IGNORE 不挡操作。

## 淡入 / 停留 / 淡出（秒）
const FADE_IN := 0.22
const HOLD := 0.50
const FADE_OUT := 0.75

## 峰值强度（1.0 = shader 全部效果）
const PEAK := 1.0

@onready var _rect: ColorRect = $TearRect
@onready var _mat: ShaderMaterial = _rect.material
var _strength := 0.0
var _tween: Tween = null
var _time := 0.0
## 常驻模式（第三阶段流泪，不用一次性动画）
var _persistent := false


func _ready() -> void:
	show()


## 播一次泪水（负面句结算时调用）
##   intensity 0~1，可用来挂钩压力（压力越高泪越重）
func play(intensity: float = 1.0) -> void:
	if _rect == null or _mat == null:
		return
	_strength = PEAK * clampf(intensity, 0.25, 1.5)
	visible = true
	_rect.visible = true

	if _tween != null and _tween.is_valid():
		_tween.kill()

	_mat.set_shader_parameter("strength", 0.0)
	_tween = create_tween()
	# 淡入
	_tween.tween_method(_set_strength, 0.0, _strength, FADE_IN)
	# 停留
	_tween.tween_interval(HOLD)
	# 淡出
	_tween.tween_method(_set_strength, _strength, 0.0, FADE_OUT)
	_tween.tween_callback(_on_finished)


## 立刻收掉（进剧情 / 结算 / 重开时用）
func hide_now() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_persistent = false
	_strength = 0.0
	if _mat != null:
		_mat.set_shader_parameter("strength", 0.0)
	if _rect != null:
		_rect.visible = false


func _set_strength(value: float) -> void:
	_strength = value
	if _mat != null:
		_mat.set_shader_parameter("strength", value)


func _on_finished() -> void:
	_set_strength(0.0)
	if _rect != null:
		_rect.visible = false


func _process(delta: float) -> void:
	# 推进 shader 时间（水波流动 / 水珠闪烁）
	if _rect == null or not _rect.visible or _mat == null:
		return
	_time += delta
	_mat.set_shader_parameter("time_sec", _time)


## ---- 常驻模式：第三阶段「逐渐流泪」用 ----
## 和 play() 的一次性动画不同，set_level() 会一直保持这个强度，
## 由外部按「接受了几句」不断累加。

## 直接设置常驻强度（0 = 关闭）
func set_level(level: float, blur_boost: float = 1.0, droplet_boost: float = 1.0) -> void:
	if _rect == null or _mat == null:
		return
	var v := clampf(level, 0.0, 1.0)
	_persistent = v > 0.001
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_strength = v
	_mat.set_shader_parameter("strength", v)
	_mat.set_shader_parameter("blur_boost", blur_boost)
	_mat.set_shader_parameter("droplet_boost", droplet_boost)
	_rect.visible = _persistent


## 当前常驻强度（0~1）
func get_level() -> float:
	return _strength if _persistent else 0.0
