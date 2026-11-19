extends Node
## ============================================================================
## sprite_normal_lighting.gd —— 法线光照驱动器（多动画 + 逐帧火光跟随）
##
## 【它做什么】
##   1. 每帧把「当前动画当前帧」映射到法线图集的对应格子
##   2. 每帧更新烛火在屏幕上的位置（火光跟着手走）
##   3. 遇到「跳吓」的关键帧，切到逆光剪影模式
##
## 【三套动画的帧数与火光位置】
##   常态   5 帧
##   大幅度 5 帧
##   跳吓   6 帧（第 2/3/4 帧是头部凑近的惊吓帧）
##   每帧火光位置写死在 FLAME_UV 里（由图像分析得出）
## ============================================================================

@export var rig_path: NodePath = ^"../AnimatedSprite2D"
@export var normal_sheet: Texture2D

## 每个动画对应的法线图集（换动画时必须一起换，否则光照全错）
@export var normal_sheets := {
	"常态": "res://lighting/normal/常态.png",
	"大幅度": "res://lighting/normal/大幅度.png",
	"跳吓": "res://lighting/normal/跳吓.png",
}

## 当前已绑定的法线图集名（避免每帧重复 load）
var _bound_normal_name := ""

## 图集划分：3 列 x 2 行，每格 2000 x 2605
@export var atlas_columns := 3
@export var atlas_rows := 2
@export var frame_px := Vector2(2000.0, 2605.0)
@export var sheet_px := Vector2(6000.0, 6000.0)

@export var enable := true
@export var normal_strength := 1.0
@export var normal_flip_y := false

## 光源位置平滑系数（0=不平滑，0.9=非常平滑）
## 火焰逐帧位置有微小抖动，不平滑会让受光区域忽大忽小
@export var light_smoothing := 0.75

## ====== 逐帧火光位置（帧内归一化 UV，相对整帧 2000x2605）======
## 由图像分析得出：取烛火核心的质心。见 flame_pos.json
const FLAME_UV := {
	"default": [   # 常态 / 大幅度 共用（两者差异很小）
		Vector2(0.712, 0.548),
		Vector2(0.691, 0.560),
		Vector2(0.692, 0.548),
		Vector2(0.716, 0.548),
		Vector2(0.690, 0.549),
	],
	"大幅度": [
		Vector2(0.712, 0.547),
		Vector2(0.707, 0.490),
		Vector2(0.708, 0.435),
		Vector2(0.734, 0.508),
		Vector2(0.692, 0.548),
	],
	"跳吓": [
		Vector2(0.712, 0.547),
		Vector2(0.661, 0.566),
		Vector2(0.560, 0.548),
		Vector2(0.627, 0.539),
		Vector2(0.694, 0.531),
		Vector2(0.671, 0.548),
	],
}

## ====== 跳吓逆光：这些帧头部凑近，光在头后 ======
## 在这些帧里把「角色受光」压成剪影，只留轮廓暖边
const BACKLIGHT_FRAMES := {
	"跳吓": [3, 4],
}

## 逆光时的参数（会被推给 shader）
@export var backlight_ambient := 0.10
@export var backlight_spec := 0.0
@export var backlight_rim := 0.85
## 正向光时恢复的值
@export var normal_ambient := 0.30
@export var normal_spec := 0.16
@export var normal_rim := 0.28

var _anim: AnimatedSprite2D
var _mat: ShaderMaterial
var _last_frame := -1
var _last_anim := ""
var _last_region := Rect2()
var _film_node: Node = null
var _bounce_mat: ShaderMaterial = null
var _smooth_uv := Vector2(-1.0, -1.0)


func _ready() -> void:
	var n := get_node_or_null(rig_path)
	if n == null:
		push_error("sprite_normal_lighting: 找不到 %s" % rig_path)
		return
	if not (n is AnimatedSprite2D):
		push_error("sprite_normal_lighting: 需要 AnimatedSprite2D")
		return
	_anim = n as AnimatedSprite2D
	_mat = _anim.material as ShaderMaterial
	if _mat == null:
		push_error("sprite_normal_lighting: AnimatedSprite2D 上没有 ShaderMaterial")
		return
	var existing = _mat.get_shader_parameter("normal_tex")
	if normal_sheet != null:
		_mat.set_shader_parameter("normal_tex", normal_sheet)
	elif existing == null:
		push_error("sprite_normal_lighting: 没有法线图集")
		return
	# 找到背景漫反射材质
	var bg := get_parent().get_node_or_null("BounceLayer/BounceRect")
	if bg != null and bg is ColorRect and bg.material != null:
		_bounce_mat = bg.material

	_refresh()


func _process(_delta: float) -> void:
	if not enable or _mat == null or _anim == null:
		return
	var f: int = _anim.frame
	var an: String = _anim.animation
	var reg := _current_region()
	if f != _last_frame or an != _last_anim or not reg.is_equal_approx(_last_region):
		_refresh()


func _refresh() -> void:
	_last_frame = _anim.frame
	_last_anim = _anim.animation
	_last_region = _current_region()

	# ---- 1. 法线格子 ----
	var offset := Vector2.ZERO
	var nscale := Vector2(1.0, 1.0)
	var reg := _last_region
	if reg.size.x > 0.0 and reg.size.y > 0.0:
		offset = Vector2(reg.position.x / maxf(sheet_px.x, 1.0),
			reg.position.y / maxf(sheet_px.y, 1.0))
		nscale = Vector2(reg.size.x / maxf(sheet_px.x, 1.0),
			reg.size.y / maxf(sheet_px.y, 1.0))
	# 【关键】动画名变了就要换法线图集
	# 否则播「跳吓」却采样「常态」的法线，光照完全错位（实测表现为整帧发黑）
	var want := _anim.animation
	if want != _bound_normal_name and normal_sheets.has(want):
		var path: String = normal_sheets[want]
		var tex: Texture2D = load(path)
		if tex != null:
			_mat.set_shader_parameter("normal_tex", tex)
			_bound_normal_name = want

	_mat.set_shader_parameter("normal_atlas_offset", offset)
	_mat.set_shader_parameter("normal_atlas_scale", nscale)
	_mat.set_shader_parameter("normal_strength", normal_strength)
	_mat.set_shader_parameter("normal_flip_y", normal_flip_y)

	# ---- 2. 火光位置：帧内 UV -> 屏幕 UV ----
	var fuv := _flame_screen_uv()
	# 【平滑】逐帧光源位置会有小跳变（火焰本身在抖），
	# 直接跟会让整块受光面积忽大忽小，看起来像闪烁。
	# 用低通滤波压掉高频抖动，保留慢速移动。
	if light_smoothing > 0.0:
		if _smooth_uv.x < 0.0:
			_smooth_uv = fuv
		else:
			_smooth_uv = _smooth_uv.lerp(fuv, 1.0 - light_smoothing)
		fuv = _smooth_uv
	_mat.set_shader_parameter("light_screen_uv", fuv)
	# 同步给全屏滤镜：这样 bloom/glow 的光晕也跟着手走，
	# 否则滤镜会用它自己写死的位置，光晕和烛火对不上。
	var film := _find_film()
	if film != null:
		film.set("light_uv", fuv)
	# 同步给背景漫反射
	if _bounce_mat != null:
		_bounce_mat.set_shader_parameter("light_uv", fuv)

	# ---- 3. 跳吓逆光 ----
	var backlit := _is_backlit()
	_mat.set_shader_parameter("backlight_mix", 1.0 if backlit else 0.0)
	if backlit:
		_mat.set_shader_parameter("ambient_level", backlight_ambient)
		_mat.set_shader_parameter("spec_strength", backlight_spec)
		_mat.set_shader_parameter("rim_strength", backlight_rim)
	else:
		_mat.set_shader_parameter("ambient_level", normal_ambient)
		_mat.set_shader_parameter("spec_strength", normal_spec)
		_mat.set_shader_parameter("rim_strength", normal_rim)


## 当前帧火光在「屏幕 UV」里的位置。
##
## 【关键认知（之前在这里错过两次）】
##   AnimatedSprite2D + AtlasTexture 的行为是：
##   **AtlasTexture 把 region 裁成一张独立纹理**，然后当普通贴图画。
##   所以：
##     · shader 里的 UV 就是「这一帧内部的 0~1」
##     · 这一帧在屏幕上的矩形 = global_position ± 帧尺寸*scale/2（centered）
##   （不是"整张 6000x6000 图集"参与定位！我一开始按图集算，
##     结果坐标跑到 y=-108 画面外，光晕位置全错。）
##
##   正确公式：
##     屏幕像素 = global_position + (帧内UV - 0.5) * 帧尺寸 * global_scale
func _flame_screen_uv() -> Vector2:
	var f: int = _anim.frame
	var an: String = _anim.animation
	var table: Array = FLAME_UV.get(an, FLAME_UV["default"])
	if f < 0 or f >= table.size():
		table = FLAME_UV["default"]
	f = clampi(f, 0, table.size() - 1)
	var fu: Vector2 = table[f]

	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return fu

	# 这一帧在屏幕上的实际尺寸 = 帧像素尺寸 * 缩放
	var reg := _last_region
	var frame_px_size := reg.size
	if frame_px_size.x <= 0.0 or frame_px_size.y <= 0.0:
		frame_px_size = frame_px
	var drawn := Vector2(frame_px_size.x * _anim.global_scale.x,
		frame_px_size.y * _anim.global_scale.y)

	# 帧内 UV -> 屏幕像素
	var screen_px := _anim.global_position + (fu - Vector2(0.5, 0.5)) * drawn
	return Vector2(screen_px.x / vp.x, screen_px.y / vp.y)


func _is_backlit() -> bool:
	var lst = BACKLIGHT_FRAMES.get(_anim.animation, [])
	return _anim.frame in lst


func _current_region() -> Rect2:
	if _anim == null or _anim.sprite_frames == null:
		return Rect2()
	var an := _anim.animation
	if an == "" or not _anim.sprite_frames.has_animation(an):
		return Rect2()
	var cnt := _anim.sprite_frames.get_frame_count(an)
	if cnt <= 0:
		return Rect2()
	var f := clampi(_anim.frame, 0, cnt - 1)
	var tex := _anim.sprite_frames.get_frame_texture(an, f)
	var at := tex as AtlasTexture
	if at == null:
		return Rect2()
	return at.region


## 找到场景里的全屏滤镜（candle_film），把烛火位置同步过去。
func _find_film() -> Node:
	if _film_node != null and is_instance_valid(_film_node):
		return _film_node
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_parent()
	if root == null:
		return null
	_film_node = _search_film(root)
	return _film_node


func _search_film(n: Node) -> Node:
	if n is CanvasLayer and n.get_script() != null:
		if n.has_method("set_mood"):
			return n
	for c in n.get_children():
		var r := _search_film(c)
		if r != null:
			return r
	return null
