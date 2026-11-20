@tool
extends Control
## 竖条：压力 / 麻木 / 时间。带装饰纹理。
##
## 视觉模型：
##   · 底图 = 装饰纹理（bar_time / bar_pressure / bar_numbness）
##   · 上层 = 暗色遮罩，按 value 盖住"已消耗"的部分
##     - fill_from_top = true （时间条）：值越少，下端盖得越多 → 看起来从上往下减少
##     - fill_from_top = false（压力/麻木）：值越多，上端盖得越少 → 从下往上涨
##
## 用法：
##     bar.texture_path = "res://art/hud/bar_pressure.png"
##     bar.value = 62.0        # 0~100

@export var texture_path := "":
	set(v):
		texture_path = v
		_tex = null
		if is_inside_tree():
			_reload()
		queue_redraw()

@export var fill_from_top := false
## 遮罩颜色（盖住"没有值"的那部分）
@export var mask_color := Color(0.05, 0.05, 0.08, 0.88)
## 纹理没加载成功时的保底色
@export var fallback_color := Color(0.35, 0.35, 0.42)
@export var border_color := Color(1.0, 0.94, 0.0, 0.75)
@export var border_width := 1.0
@export var ticks := 0

## 0 ~ 100
var value := 0.0:
	set(v):
		value = clampf(v, 0.0, 100.0)
		queue_redraw()

var ratio := 0.0:
	set(v):
		ratio = clampf(v, 0.0, 1.0)
		value = ratio * 100.0

var _tex: Texture2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reload()


func _ensure_texture() -> bool:
	if _tex != null:
		return true
	if texture_path.is_empty():
		return false
	if not ResourceLoader.exists(texture_path):
		return false
	_tex = load(texture_path)
	return _tex != null


func _reload() -> void:
	_tex = null
	if texture_path.is_empty():
		queue_redraw()
		return
	if ResourceLoader.exists(texture_path):
		_tex = load(texture_path)
	queue_redraw()


func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	if full.size.x <= 0.0 or full.size.y <= 0.0:
		return

	# 1) 底图
	if _ensure_texture():
		draw_texture_rect(_tex, full, false)
	else:
		draw_rect(full, fallback_color, true)

	# 2) 遮罩：把"没有值"的一段盖暗
	var frac := value / 100.0
	var mask_h := size.y * (1.0 - frac)
	if mask_h > 0.5:
		var mask_rect: Rect2
		if fill_from_top:
			# 时间条：亮区贴着底部，顶部先被消耗
			#   满 = 全亮；剩 50% = 下半亮（上半已消耗）
			#   剩 15% = 底部一小截亮
			# → 视觉上"进度从顶部往下退"，像沙漏里的水往下流
			mask_rect = Rect2(0.0, 0.0, size.x, mask_h)
		else:
			# 压力 / 麻木：亮区是「已积累」，从底部往上涨
			mask_rect = Rect2(0.0, 0.0, size.x, mask_h)
		draw_rect(mask_rect, mask_color, true)

	# 3) 刻度
	if ticks > 1:
		var c := Color(1.0, 1.0, 1.0, 0.16)
		for i in range(1, ticks):
			var y := size.y * float(i) / float(ticks)
			draw_line(Vector2(0.0, y), Vector2(size.x, y), c, 1.0)

	# 4) 描边
	if border_width > 0.0:
		draw_rect(full, border_color, false, border_width)
