extends CanvasLayer
## ============================================================================
## candle_film.gd —— 烛光电影感全屏滤镜（后处理）
##
## 挂在 CanvasLayer 上，layer 设成高于游戏内容但低于暂停 UI 的层级。
## 内部自己建一个全屏 ColorRect，材质套 candle_film.gdshader。
##
## 为什么用 CanvasLayer 而不是往 main.tscn 里塞节点：
##   滤镜是纯视觉层，和 gameplay 完全解耦。删掉这个节点游戏照常运行，
##   加入也不影响任何现有脚本的节点路径。
##
## 与游戏状态的联动（在 main 里每帧调用 set_mood）：
##   · 压力高 → 对比更高、暗角更重、颗粒更粗（胸闷感）
##   · 麻木高 → 饱和度掉下去、雾更厚（世界变灰变远）
##   · 好感高 → 烛光更暖更亮、bloom 更强（房间更"有人气"）
## ============================================================================

@export var shader_path := "res://lighting/candle_film.gdshader"

## 滤镜所在 CanvasLayer 的层级（必须比游戏内容大）
@export var film_layer := 10

## 烛火在屏幕上的归一化位置（0~1）。
## 由 NormalLightDriver 每帧更新，这样 bloom/glow 会跟着手走。
@export var light_uv := Vector2(0.89, 0.42)

## 火焰抖动幅度
@export var flicker_amount := 0.0016

## 画面基准（先在这里调好"常态"，mood 只做增量）
@export var base_exposure := 0.95
@export var base_contrast := 0.98
@export var base_saturation := 0.74
@export var base_vignette := 0.42
@export var base_grain := 0.024
@export var base_bloom := 0.30
@export var base_glow := 0.13
@export var base_haze := 0.030
@export var base_midtone := 0.95

## 情绪增量幅度
@export var pressure_contrast := 0.22
@export var pressure_vignette := 0.34
@export var pressure_grain := 0.022
@export var numbness_desat := 0.42
@export var numbness_haze := 0.10
@export var affection_bloom := 0.34
@export var affection_glow := 0.22

## 麻木时的中间调变化
## 【为什么是「抬」而不是「压」】
##   麻木的观感应该是「世界变灰、变平、变远」，而不是「世界变黑」。
##   压暗会让角色整只消失 —— 玩家就看不见 Boss 了，玩法上不可接受。
##   正确的做法：抬中间调（画面变平，对比降低）+ 加雾（远近层次糊掉）+ 去色。
@export var numbness_flat := 0.26

var _rect: ColorRect
var _mat: ShaderMaterial
var _pressure := 0.0
var _numbness := 0.0
var _affection := 0.0
var _t := 0.0


func _ready() -> void:
	layer = film_layer
	_rect = ColorRect.new()
	_rect.name = "FilmRect"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.WHITE
	var sh: Shader = load(shader_path)
	if sh == null:
		push_error("candle_film: 找不到 %s" % shader_path)
		return
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect.material = _mat
	add_child(_rect)
	_apply()


func _process(delta: float) -> void:
	_t += delta
	_apply()


## main.gd 每帧把情绪值推进来（0..1）
func set_mood(affection: float, pressure: float, numbness: float) -> void:
	_affection = clampf(affection, 0.0, 1.0)
	_pressure = clampf(pressure, 0.0, 1.0)
	_numbness = clampf(numbness, 0.0, 1.0)


func _apply() -> void:
	if _mat == null:
		return

	# 烛火位置的细微抖动：让 bloom/glow 跟着火焰一起呼吸
	var flick := (sin(_t * 8.3) + sin(_t * 14.7) * 0.55) * flicker_amount
	_mat.set_shader_parameter("light_uv", Vector2(light_uv.x + flick, light_uv.y + flick * 0.6))

	_mat.set_shader_parameter("exposure", base_exposure)
	_mat.set_shader_parameter("contrast", base_contrast + _pressure * pressure_contrast - _numbness * 0.12)
	# 麻木：抬中间调让画面变平（不是变黑），角色始终看得见
	_mat.set_shader_parameter("midtone_lift", base_midtone + _numbness * numbness_flat)
	_mat.set_shader_parameter("saturation", maxf(0.0, base_saturation - _numbness * numbness_desat))
	_mat.set_shader_parameter("vignette_strength", base_vignette + _pressure * pressure_vignette)
	_mat.set_shader_parameter("grain_amount", base_grain + _pressure * pressure_grain)
	_mat.set_shader_parameter("bloom_strength", base_bloom + _affection * affection_bloom)
	_mat.set_shader_parameter("glow_strength", base_glow + _affection * affection_glow)
	_mat.set_shader_parameter("haze_amount", base_haze + _numbness * numbness_haze)
