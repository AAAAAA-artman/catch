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

@onready var _rig: Node2D = $Rig
@onready var _rig_home := _rig.position
@onready var _sprite: AnimatedSprite2D = $Rig/AnimatedSprite2D


func _ready() -> void:
	_sprite.play("常态")
	_sprite.animation_finished.connect(_on_anim_finished)
	hide()


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
	tw.tween_property(_rig, "position", _rig_home + Vector2(6.0, -4.0), 0.05)
	tw.tween_property(_rig, "position", _rig_home + Vector2(-5.0, 2.0), 0.05)
	tw.tween_property(_rig, "position", _rig_home + Vector2(3.0, -2.0), 0.05)
	tw.tween_property(_rig, "position", _rig_home, 0.09)


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
		_rig.position = _rig_home
	if _sprite != null:
		_sprite.play("常态")
