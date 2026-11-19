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

const SHADER_PATH := "res://shaders/tears.gdshader"

## 淡入 / 停留 / 淡出（秒）
const FADE_IN := 0.22
const HOLD := 0.50
const FADE_OUT := 0.75

## 峰值强度（1.0 = shader 全部效果）
const PEAK := 1.0

var _rect: ColorRect
var _mat: ShaderMaterial
var _strength := 0.0
var _tween: Tween = null
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 根节点必须保持可见 —— 否则子节点的 visible 无效，整个滤镜画不出来
	visible = true

	if not ResourceLoader.exists(SHADER_PATH):
		push_warning("TearsFx: 找不到 %s" % SHADER_PATH)
		return

	_rect = ColorRect.new()
	_rect.name = "TearRect"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.color = Color.WHITE
	_rect.visible = false

	var sh: Shader = load(SHADER_PATH)
	if sh == null:
		return
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("strength", 0.0)
	_rect.material = _mat
	add_child(_rect)


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
