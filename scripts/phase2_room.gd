extends Control
## 第二阶段画面：新房间背景 + 门上的立绘动画（沿用之前做的烛光法线光照系统）。
##
## 节奏（按需求）：
##   · 常态：一直循环播「常态」待机
##   · 阶段二好感度到 50% → 触发一次「跳吓」
##   · 之后随机穿插「大幅度」动作（小概率再跳吓一次），播完回到常态
##
## 素材全部复用 lighting/ 模块，不重复造轮子：
##   albedo/常态.png 大幅度.png 跳吓.png   —— 3 列 × 2 行图集，每格 1000×1302
##   normal/*.png                          —— 一一对应的法线图
##   sprite_normal_lit.gdshader            —— 法线光照
##   sprite_normal_lighting.gd             —— 逐帧火光跟随 + 跳吓逆光

const BG_PATH := "res://art/stage/phase2_room.png"

const ANIM_SHEETS := {
	"常态": "res://lighting/albedo/常态.png",
	"大幅度": "res://lighting/albedo/大幅度.png",
	"跳吓": "res://lighting/albedo/跳吓.png",
}
const ANIM_FRAMES := {"常态": 5, "大幅度": 5, "跳吓": 6}
const ANIM_SPEED := {"常态": 5.0, "大幅度": 3.2, "跳吓": 6.5}

## 图集：3 列 × 2 行，每格 1000 × 1302
const FRAME_W := 1000.0
const FRAME_H := 1302.0
const COLS := 3
const SHEET_PX := Vector2(3000.0, 2604.0)

## 立绘摆位（画面窗口内的像素坐标，站在门洞里）
## 目标：脑袋顶到门框高度，脚略微被画面下沿裁掉一点
const SPRITE_POS := Vector2(407.0, 155.0)
const SPRITE_SCALE := 0.46

## 阶段二进度到这个值时触发跳吓
const SCARE_AT := 0.5
## 随机动作
const ACTION_MIN := 2.2
const ACTION_MAX := 4.5
## 随机动作里再跳吓一次的概率
const RESCARE_CHANCE := 0.22

var _progress := 0.0
var _active := false
var _scare_done := false
var _action_timer := 3.0

var _bg: TextureRect
var _rig: Node2D
var _sprite: AnimatedSprite2D
var _driver: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	visible = false


func _build() -> void:
	# 1) 背景
	_bg = TextureRect.new()
	_bg.name = "Bg"
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists(BG_PATH):
		_bg.texture = load(BG_PATH)
	add_child(_bg)

	# 2) 立绘骨架
	_rig = Node2D.new()
	_rig.name = "Rig"
	_rig.position = SPRITE_POS
	_rig.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	add_child(_rig)

	_sprite = AnimatedSprite2D.new()
	_sprite.name = "AnimatedSprite2D"
	# 压到同心圆（CircleFx，z_index = 12）之上，跳吓时头能穿过去
	_sprite.z_index = 14
	_sprite.sprite_frames = _build_frames()
	_sprite.centered = true
	_sprite.animation = "常态"
	_sprite.material = _build_material()
	_rig.add_child(_sprite)
	_sprite.play("常态")
	_sprite.animation_finished.connect(_on_anim_finished)

	# 3) 法线光照驱动器（直接复用原模块脚本）
	var driver_script := load("res://lighting/sprite_normal_lighting.gd")
	if driver_script != null:
		_driver = Node.new()
		_driver.name = "NormalLightDriver"
		_driver.set_script(driver_script)
		_driver.set("rig_path", ^"../AnimatedSprite2D")
		_driver.set("frame_px", Vector2(FRAME_W, FRAME_H))
		_driver.set("sheet_px", SHEET_PX)
		var normal_path: String = "res://lighting/normal/常态.png"
		if ResourceLoader.exists(normal_path):
			_driver.set("normal_sheet", load(normal_path))
		_rig.add_child(_driver)


func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim_name in ANIM_SHEETS.keys():
		var key := String(anim_name)
		sf.add_animation(key)
		sf.set_animation_loop(key, key == "常态")
		sf.set_animation_speed(key, float(ANIM_SPEED[key]))
		var path: String = ANIM_SHEETS[key]
		if not ResourceLoader.exists(path):
			continue
		var sheet: Texture2D = load(path)
		var count: int = int(ANIM_FRAMES[key])
		for i in count:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			var col := i % COLS
			var row := int(i / COLS)
			atlas.region = Rect2(float(col) * FRAME_W, float(row) * FRAME_H, FRAME_W, FRAME_H)
			sf.add_frame(key, atlas)
	return sf


func _build_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists("res://lighting/sprite_normal_lit.gdshader"):
		mat.shader = load("res://lighting/sprite_normal_lit.gdshader")
	# 光照参数：沿用 demo 的调子，稍微压暗以贴合新背景
	mat.set_shader_parameter("normal_atlas_offset", Vector2.ZERO)
	mat.set_shader_parameter("normal_atlas_scale", Vector2(1.0 / 3.0, FRAME_H / SHEET_PX.y))
	mat.set_shader_parameter("normal_strength", 1.0)
	mat.set_shader_parameter("normal_flip_y", false)
	mat.set_shader_parameter("light_screen_uv", Vector2(0.6, 0.6))
	mat.set_shader_parameter("light_color", Color(1.0, 0.87, 0.6))
	mat.set_shader_parameter("light_energy", 2.6)
	mat.set_shader_parameter("light_range", 0.38)
	mat.set_shader_parameter("light_height", 0.55)
	mat.set_shader_parameter("falloff_power", 2.3)
	mat.set_shader_parameter("spec_strength", 0.16)
	mat.set_shader_parameter("spec_power", 28.0)
	mat.set_shader_parameter("ambient_sky", Color(0.26, 0.3, 0.44))
	mat.set_shader_parameter("ambient_ground", Color(0.08, 0.07, 0.08))
	mat.set_shader_parameter("ambient_level", 0.42)
	mat.set_shader_parameter("ambient_tint", 0.34)
	mat.set_shader_parameter("rim_strength", 0.28)
	mat.set_shader_parameter("backlight_mix", 0.0)
	mat.set_shader_parameter("brightness", 1.15)
	mat.set_shader_parameter("saturation", 1.05)
	var normal_path: String = "res://lighting/normal/常态.png"
	if ResourceLoader.exists(normal_path):
		mat.set_shader_parameter("normal_tex", load(normal_path))
	return mat


## 阶段二进度 0~1
func set_progress(value: float) -> void:
	_progress = clampf(value, 0.0, 1.0)
	if _active and not _scare_done and _progress >= SCARE_AT:
		_scare_done = true
		_play_once("跳吓")


func set_active(on: bool) -> void:
	_active = on
	visible = on
	if on:
		if _sprite != null and _sprite.animation != "常态":
			_play_once("常态")
		_action_timer = randf_range(ACTION_MIN, ACTION_MAX)
	else:
		_scare_done = false
		_progress = 0.0


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	if not _active or _sprite == null:
		return
	# 跳吓触发后，常态期间随机来一次大幅度 / 跳吓
	if _scare_done and _sprite.animation == "常态":
		_action_timer -= delta
		if _action_timer <= 0.0:
			_action_timer = randf_range(ACTION_MIN, ACTION_MAX)
			if randf() < RESCARE_CHANCE:
				_play_once("跳吓")
			else:
				_play_once("大幅度")


func _play_once(anim_name: String) -> void:
	if _sprite == null or not _sprite.sprite_frames.has_animation(anim_name):
		return
	_sprite.play(anim_name)
	if anim_name == "跳吓":
		action_landed_jolt()


## 跳吓伴随的轻微镜头冲击（只动自己的位置，不影响布局）
func action_landed_jolt() -> void:
	if _rig == null:
		return
	var tw := create_tween()
	tw.tween_property(_rig, "position", SPRITE_POS + Vector2(6.0, -4.0), 0.05)
	tw.tween_property(_rig, "position", SPRITE_POS + Vector2(-5.0, 2.0), 0.05)
	tw.tween_property(_rig, "position", SPRITE_POS + Vector2(3.0, -2.0), 0.05)
	tw.tween_property(_rig, "position", SPRITE_POS, 0.09)


func _on_anim_finished() -> void:
	if _sprite == null:
		return
	if _sprite.animation != "常态":
		_sprite.play("常态")


## 重开一局时复位
func reset() -> void:
	_scare_done = false
	_progress = 0.0
	_action_timer = randf_range(ACTION_MIN, ACTION_MAX)
	if _rig != null:
		_rig.position = SPRITE_POS
	if _sprite != null:
		_sprite.play("常态")
