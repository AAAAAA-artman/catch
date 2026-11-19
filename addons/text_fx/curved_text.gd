@tool
class_name CurvedText
extends Node2D
## 可移植的「弯曲文字」节点。
##
## 自带排版：把字符串逐字摆到弧线 / 圆环 / 波浪 / 贝塞尔曲线上，
## 每个字跟随曲线切线旋转，并且自带「缓慢消失」动画。
##
## 不依赖任何 shader、任何项目资源、任何 post-processing，
## 所以在 gl_compatibility / mobile / forward+ 下表现一致。
## 直接把这个文件（和 text_fx.gd）复制到别的项目即可使用。
##
## 最小用法：
##     var t := CurvedText.new()
##     t.text = "你终于被听见了"
##     t.font_size = 64
##     t.curve_mode = CurvedText.CurveShape.ARC
##     t.radius = 700.0
##     t.position = Vector2(640, 300)
##     add_child(t)
##     t.fade_out(4.0)          # 用 4 秒缓慢消失

signal finished

enum CurveShape {
	STRAIGHT, ## 直线（也会逐字排版，方便做字距/抖动）
	ARC,      ## 圆弧：radius 越大越平，负数则方向相反
	CIRCLE,   ## 整圆：文字沿一圈排开
	WAVE,     ## 正弦波
	BEZIER,   ## 二次贝塞尔拱形（bezier_bulge 控制拱高）
}

enum Align {
	START,  ## 从原点开始向右铺
	CENTER, ## 以原点为中心
	END,    ## 到原点结束
}

enum PlayMode {
	NONE,
	FADE_OUT, ## 缓慢消失
	FADE_IN,  ## 缓慢浮现
}

# ---------------------------------------------------------------- 文字内容
@export_group("文字")
@export_multiline var text: String = "你终于被听见了":
	set(value):
		text = value
		_rebuild()
@export var font: Font:
	set(value):
		font = value
		_rebuild()
@export_range(8, 256, 1) var font_size: int = 48:
	set(value):
		font_size = maxi(8, value)
		_rebuild()
@export_range(-20.0, 80.0, 0.5) var glyph_spacing: float = 0.0:
	set(value):
		glyph_spacing = value
		_rebuild()
@export var align: Align = Align.CENTER:
	set(value):
		align = value
		_rebuild()

# ---------------------------------------------------------------- 曲线形状
@export_group("曲线")
@export var curve_mode: CurveShape = CurveShape.ARC:
	set(value):
		curve_mode = value
		_rebuild()
@export_range(-4000.0, 4000.0, 1.0) var radius: float = 900.0:
	set(value):
		radius = value
		_rebuild()
@export_range(0.0, 3.0, 0.01) var rotate_follow: float = 1.0:
	# 1 = 每个字完全跟随切线旋转，0 = 所有字都水平（"拱形但不斜"）
	set(value):
		rotate_follow = value
		_rebuild()
@export_range(-1.0, 1.0, 0.01) var rotate_bias: float = 0.0:
	set(value):
		rotate_bias = value
		_rebuild()
@export_range(0.0, 600.0, 1.0) var bezier_bulge: float = 220.0:
	set(value):
		bezier_bulge = value
		_rebuild()
@export_range(0.0, 400.0, 1.0) var wave_amplitude: float = 40.0:
	set(value):
		wave_amplitude = value
		_rebuild()
@export_range(20.0, 2000.0, 1.0) var wave_length: float = 520.0:
	set(value):
		wave_length = maxf(20.0, value)
		_rebuild()

# ---------------------------------------------------------------- 外观
@export_group("外观")
@export var color_start: Color = Color("fff3e8"):
	set(value):
		color_start = value
		queue_redraw()
@export var color_end: Color = Color("f7d292"):
	set(value):
		color_end = value
		queue_redraw()
@export_range(1, 8, 1) var outline_size: int = 0:
	set(value):
		outline_size = value
		queue_redraw()
@export var outline_color: Color = Color(0.02, 0.02, 0.04, 0.55):
	set(value):
		outline_color = value
		queue_redraw()
@export_range(0.0, 1.0, 0.01) var base_alpha: float = 1.0:
	set(value):
		base_alpha = value
		queue_redraw()

# ---------------------------------------------------------------- 手写/呼吸感
@export_group("呼吸感")
@export_range(0.0, 40.0, 0.5) var jitter: float = 0.0:
	# 每个字的随机位移，>0 会有一点手写感
	set(value):
		jitter = value
		_rebuild()
@export_range(0.0, 0.6, 0.01) var jitter_rotate: float = 0.0:
	set(value):
		jitter_rotate = value
		_rebuild()
@export_range(0.0, 30.0, 0.5) var float_amplitude: float = 0.0:
	# 持续上下浮动幅度（0 = 静止）
	set(value):
		float_amplitude = value
		set_process(float_amplitude > 0.0 or _animating)
@export_range(0.0, 6.0, 0.05) var float_speed: float = 1.0
@export_range(0.0, 6.0, 0.05) var float_phase: float = 0.9

# ---------------------------------------------------------------- 缓慢消失
@export_group("缓慢消失")
@export_range(0.0, 30.0, 0.05) var fade_duration: float = 3.5:
	# 0 = 等外部调用 seek() 手动推进（做时间轴动画时很有用）
	set(value):
		fade_duration = value
@export_range(0.0, 10.0, 0.05) var fade_delay: float = 0.0
@export_range(0.0, 1.0, 0.01) var fade_stagger: float = 0.45:
	# 每个字错开的比例：0 = 一起淡出，0.45 = 从左到右依次淡出
	set(value):
		fade_stagger = clampf(value, 0.0, 1.0)
@export_range(0.5, 4.0, 0.05) var fade_power: float = 1.25
	# >1 先保持清晰再快速变淡；<1 一上来就开始变淡
@export var fade_drift: Vector2 = Vector2(0.0, -26.0)
	# 消失时整体缓慢漂移的位移
@export var fade_glyph_drift: Vector2 = Vector2(0.0, -10.0)
	# 每个字额外的漂移（会和整体漂移叠加）
@export_range(0.0, 1.0, 0.01) var fade_shrink: float = 0.86
@export_range(0.0, 12.0, 0.05) var fade_wobble: float = 0.0
	# 消失时左右摇摆的角度（弧度），做"飘散"的感觉
@export var free_when_done: bool = true
@export var auto_play: bool = false

# ---------------------------------------------------------------- 内部状态
var _glyphs: Array[Dictionary] = []
var _width := 0.0
var _time := 0.0
var _anim_mode: PlayMode = PlayMode.NONE
var _animating := false
var _clock := 0.0
var _progress := 0.0
var _curve_s0 := 0.0
var _curve_span := 0.0
var _bezier_offset := 0.0
var _bezier_span := 1.0
var _bezier_points: Array[Vector2] = []
var _bezier_lengths: Array[float] = []
var _fallback_font: Font = null


func _ready() -> void:
	_rebuild()
	if auto_play == false:
		set_process(float_amplitude > 0.0 or _animating)
	if auto_play:
		fade_out(fade_duration, fade_delay)


func _process(delta: float) -> void:
	_time += delta
	if _animating:
		_clock += delta
		var total := maxf(fade_duration, 0.0001)
		_progress = clampf((_clock - fade_delay) / total, 0.0, 1.0)
		if _clock >= fade_delay + total:
			_animating = false
			_progress = 1.0
			set_process(float_amplitude > 0.0)
			# 先记下是否要自毁：finished 的回调里可能马上开始下一段动画
			# （例如「逐字浮现 → 停一下 → 缓慢消失」），那时候不能释放自己。
			var should_free := free_when_done
			finished.emit()
			if should_free and not _animating:
				queue_free()
				return
	queue_redraw()


# ================================================================ 公共 API

## 缓慢消失。duration = 秒；stagger 越大越像"从左到右一个字一个字淡掉"。
func fade_out(duration: float = -1.0, delay: float = 0.0, stagger: float = -1.0) -> void:
	if duration >= 0.0:
		fade_duration = duration
	fade_delay = maxf(delay, 0.0)
	if stagger >= 0.0:
		fade_stagger = clampf(stagger, 0.0, 1.0)
	_start_animation(PlayMode.FADE_OUT)


## 缓慢浮现（fade_out 的反向），适合段落逐字出现。
func fade_in(duration: float = 1.6, delay: float = 0.0, stagger: float = -1.0) -> void:
	if duration >= 0.0:
		fade_duration = duration
	fade_delay = maxf(delay, 0.0)
	if stagger >= 0.0:
		fade_stagger = clampf(stagger, 0.0, 1.0)
	_start_animation(PlayMode.FADE_IN)


## 手动定位动画进度（0 = 刚出现，1 = 完全消失）。
## 外部用公式或 AnimationPlayer 驱动时用这个，而不是让它自己走时钟。
func seek(p: float) -> void:
	_animating = false
	set_process(float_amplitude > 0.0)
	if _anim_mode == PlayMode.NONE:
		_anim_mode = PlayMode.FADE_OUT
	_progress = clampf(p, 0.0, 1.0)
	queue_redraw()


## 当前进度（0..1）。
func get_progress() -> float:
	return _progress


## 文字排版后的总宽度（像素，含字距），可用于自己算位置。
func get_layout_width() -> float:
	return _width


## 重新排版（改了曲线参数后如果 setter 没触发，可以手动叫一次）。
func rebuild() -> void:
	_rebuild()


func _start_animation(mode: PlayMode) -> void:
	_anim_mode = mode
	_clock = 0.0
	_progress = 0.0
	_animating = true
	set_process(true)


# ================================================================ 字体

## 没指定 font 时用主题默认字体；如果它没有中文/emoji 字形，自动换成系统字体。
## 这样同一个节点在 Windows / macOS / Linux / Web 上都能显示中日韩文字。
static func default_font() -> Font:
	var fallback := ThemeDB.fallback_font
	if fallback == null:
		return null
	if fallback.has_char("接".unicode_at(0)):
		return fallback
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray([
		"Microsoft YaHei", "微软雅黑", "PingFang SC", "Hiragino Sans GB",
		"Noto Sans CJK SC", "Source Han Sans SC", "SimHei", "sans-serif",
	])
	sys.allow_system_fallback = true
	if sys.has_char("接".unicode_at(0)):
		return sys
	return fallback


func _resolve_font() -> Font:
	if font != null:
		return font
	if _fallback_font == null:
		_fallback_font = default_font()
	return _fallback_font


# ================================================================ 排版

func _rebuild() -> void:
	if not is_inside_tree():
		return
	_glyphs.clear()
	var resolved := _resolve_font()
	if resolved == null or text.is_empty():
		_width = 0.0
		queue_redraw()
		return

	var chars: Array[String] = []
	for i in text.length():
		chars.append(text.substr(i, 1))

	# 逐字推进宽度：用前缀宽度差分保留字距调整（kerning）
	var advances: Array[float] = []
	var prev := 0.0
	for i in chars.size():
		var w := resolved.get_string_size(text.substr(0, i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		advances.append(w - prev)
		prev = w
	_width = prev + glyph_spacing * float(maxi(0, chars.size() - 1))

	var s0 := 0.0
	match align:
		Align.CENTER:
			s0 = -_width * 0.5
		Align.END:
			s0 = -_width
		_:
			s0 = 0.0
	_curve_s0 = s0
	_curve_span = _width

	if curve_mode == CurveShape.BEZIER:
		_build_bezier(_width, s0)

	var cursor := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(text)
	for i in chars.size():
		var ch := chars[i]
		if ch != " " and ch != "\n":
			var sample := _sample_at(s0 + cursor + advances[i] * 0.5)
			# 采样点取的是这个字"推进量的中点"，而 draw_char 是从基线左端画的，
			# 所以沿切线往回退半个字宽，字才真正落在曲线上、整段文字也才居中对齐。
			var tangent: Vector2 = sample["tangent"]
			var glyph := {
				"char": ch,
				"pos": (sample["pos"] as Vector2) - tangent * (advances[i] * 0.5),
				"rot": sample["rot"],
				"advance": advances[i],
				"frac": 0.0 if chars.size() <= 1 else float(i) / float(chars.size() - 1),
			}
			if jitter > 0.0:
				glyph["pos"] = (glyph["pos"] as Vector2) + Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
			if jitter_rotate > 0.0:
				glyph["rot"] = (glyph["rot"] as float) + rng.randf_range(-jitter_rotate, jitter_rotate)
			_glyphs.append(glyph)
		cursor += advances[i] + glyph_spacing
	queue_redraw()


func _sample_at(s: float) -> Dictionary:
	var pos := Vector2.ZERO
	var tangent := Vector2.RIGHT
	match curve_mode:
		CurveShape.STRAIGHT:
			pos = Vector2(s, 0.0)
		CurveShape.ARC:
			var r := radius
			if absf(r) < 1.0:
				r = 1.0
			var a := s / r
			pos = Vector2(r * sin(a), r * (1.0 - cos(a)))
			tangent = Vector2(cos(a), sin(a))
		CurveShape.CIRCLE:
			# 整圆：整段文字均匀摊满 360°，与字数/总宽无关
			var r := maxf(absf(radius), 10.0)
			var u := clampf((s - _curve_s0) / maxf(_curve_span, 0.0001), 0.0, 1.0)
			var a := u * TAU - PI * 0.5
			pos = Vector2(r * cos(a), r * sin(a) + r)
			tangent = Vector2(-sin(a), cos(a))
		CurveShape.WAVE:
			var x := s
			var k := TAU / wave_length
			var slope := wave_amplitude * k * cos(x * k)
			pos = Vector2(x, wave_amplitude * sin(x * k))
			tangent = Vector2(1.0, slope).normalized()
		CurveShape.BEZIER:
			var sample := _sample_bezier(s)
			pos = sample["pos"]
			tangent = sample["tangent"]
		_:
			pos = Vector2(s, 0.0)
	# rotate_follow=0 时所有字都不旋转（水平），=1 时完全贴着切线
	var rot := tangent.angle() * rotate_follow + rotate_bias
	return {"pos": pos, "rot": rot, "tangent": tangent}


func _build_bezier(total_width: float, s0: float) -> void:
	_bezier_points.clear()
	_bezier_lengths.clear()
	_bezier_offset = s0
	_bezier_span = maxf(total_width, 0.0001)
	var a := Vector2(s0, 0.0)
	var b := Vector2(s0 + total_width, 0.0)
	# 二次贝塞尔的峰值只有控制点高度的一半，乘 2 之后 bezier_bulge 就是实际拱高
	var c := Vector2(s0 + total_width * 0.5, -bezier_bulge * 2.0)
	const STEPS := 96
	var last := a
	var accum := 0.0
	_bezier_points.append(a)
	_bezier_lengths.append(0.0)
	for i in range(1, STEPS + 1):
		var t := float(i) / float(STEPS)
		var p := _quad_bezier(a, c, b, t)
		accum += p.distance_to(last)
		last = p
		_bezier_points.append(p)
		_bezier_lengths.append(accum)


func _quad_bezier(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * u * u + c * 2.0 * u * t + b * t * t


func _sample_bezier(s: float) -> Dictionary:
	var total := 0.0 if _bezier_lengths.is_empty() else _bezier_lengths[_bezier_lengths.size() - 1]
	if total <= 0.0 or _bezier_points.size() < 2:
		return {"pos": Vector2(s, 0.0), "tangent": Vector2.RIGHT}
	# s 是"文字推进距离"（可能为负，因为居中/右对齐），先归一化到 0..1 再换成弧长
	var u := clampf((s - _bezier_offset) / _bezier_span, 0.0, 1.0)
	var target := u * total
	# 按弧长二分找到区间（保证每个字沿曲线等距）
	var lo := 0
	var hi := _bezier_lengths.size() - 1
	while lo < hi - 1:
		var mid := (lo + hi) / 2
		if _bezier_lengths[mid] <= target:
			lo = mid
		else:
			hi = mid
	var seg := _bezier_lengths[hi] - _bezier_lengths[lo]
	var f := 0.0 if seg <= 0.0 else (target - _bezier_lengths[lo]) / seg
	var p: Vector2 = _bezier_points[lo].lerp(_bezier_points[hi], f)
	var tangent: Vector2 = (_bezier_points[hi] - _bezier_points[lo]).normalized()
	return {"pos": p, "tangent": tangent}


# ================================================================ 绘制

func _draw() -> void:
	if _glyphs.is_empty():
		return
	var resolved := _resolve_font()
	if resolved == null:
		return

	var count := _glyphs.size()
	for i in count:
		var glyph: Dictionary = _glyphs[i]
		var frac: float = glyph["frac"]
		var alpha := 1.0
		var offset := Vector2.ZERO
		var scale := 1.0
		var extra_rot := 0.0

		if _anim_mode != PlayMode.NONE:
			var local := _fade_local(frac)
			if _anim_mode == PlayMode.FADE_IN:
				local = 1.0 - local
			alpha = pow(clampf(1.0 - local, 0.0, 1.0), fade_power)
			offset += fade_drift * local
			offset += fade_glyph_drift * local * (frac * 2.0 - 1.0)
			scale = lerpf(1.0, fade_shrink, local)
			if fade_wobble > 0.0:
				extra_rot = sin(local * PI * 2.0 + frac * 4.0) * fade_wobble * local

		if float_amplitude > 0.0:
			offset.y += sin(_time * float_speed + float(frac) * float_phase) * float_amplitude

		var final_alpha := alpha * base_alpha
		if final_alpha <= 0.002:
			continue

		var pos: Vector2 = (glyph["pos"] as Vector2) + offset
		var rot: float = (glyph["rot"] as float) + extra_rot
		var color := color_start.lerp(color_end, frac)
		color.a = clampf(color.a * final_alpha, 0.0, 1.0)

		draw_set_transform(pos, rot, Vector2(scale, scale))
		var ch: String = glyph["char"]
		if outline_size > 0:
			var oc := outline_color
			oc.a = clampf(oc.a * final_alpha, 0.0, 1.0)
			draw_char_outline(resolved, Vector2.ZERO, ch, font_size, outline_size, oc)
		draw_char(resolved, Vector2.ZERO, ch, font_size, color)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 第 i 个字此刻的消失进度（0 = 还在，1 = 已消失）。
func _fade_local(frac: float) -> float:
	var span := maxf(1.0 - fade_stagger, 0.0001)
	var start := fade_stagger * frac
	return clampf((_progress - start) / span, 0.0, 1.0)
