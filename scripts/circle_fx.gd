extends Control
## 同心圆结算特效。
##
## 每句句子结算后调用 play()：
##   · 全屏浮现两个同心圆（外圆固定、内圆随「阶段好感度」缩放）
##   · 内圆里浮出刚接住的那句话
##   · 淡入 → 停留 → 淡出，全程不挡操作
##
## 关键：内圆跟的是**阶段好感度**（当前阶段内的进度 0~1），
## 不是总好感度。所以每进新阶段，内圆会重新从小开始长。

## 外圆半径 = 屏幕短边 × 这个比例
const R_OUT_RATIO := 0.455
## 内圆最小 / 最大半径 = 外圆 × 比例
## 范围拉大（0.14~0.92，相差 6.6 倍），让每句的大小变化一眼可见
const R_IN_MIN := 0.14
const R_IN_MAX := 0.92

const FADE_IN := 0.22
const HOLD := 1.15
const FADE_OUT := 0.38
## 内圆从旧值过渡到新值的时间
const INNER_EASE := 1.1
## 先显示旧尺寸多久，再开始变化（让玩家看清"变化前 → 变化后"）
const HOLD_BEFORE_CHANGE := 0.45

const RING_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const OUTER_WIDTH := 2.6
const INNER_WIDTH := 2.0
## 内圆里的黑色半透明底，保证文字看得清
const DISC_ALPHA := 0.72

var _text := ""
## 目标内圆比例（阶段好感度）
var _target_inner := R_IN_MIN
## 当前绘制的内圆比例（带缓动）
var _inner := R_IN_MIN
## 上一句的内圆比例（这一句开场先用它，再变到新值）
var _prev_inner := R_IN_MIN
var _alpha := 0.0
var _font: Font = null

var _fade_tween: Tween = null
var _inner_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_alpha = 0.0


func set_font(font: Font) -> void:
	_font = font
	queue_redraw()


## 阶段好感度 0~1 → 内圆半径比例
func inner_ratio_for(progress: float) -> float:
	return lerpf(R_IN_MIN, R_IN_MAX, clampf(progress, 0.0, 1.0))


## 播放一次结算特效
##   sentence  刚接住的句子
##   progress  阶段好感度（0~1）
func play(sentence: String, progress: float) -> void:
	_text = sentence
	_target_inner = inner_ratio_for(progress)

	# 【稳定性关键】被打断时 _commit_inner 可能没跑过，
	# 所以开场一律以「屏幕上此刻实际画着的尺寸」为起点，
	# 而不是沿用可能已经过期的 _prev_inner。
	_prev_inner = _inner

	# 跨阶段：新目标明显比当前小 → 说明进了新阶段，内圆该从头长
	if _target_inner < _prev_inner - 0.15:
		_prev_inner = R_IN_MIN

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	if _inner_tween != null and _inner_tween.is_valid():
		_inner_tween.kill()

	visible = true

	# ---- 内圆动画：先用"上一句的尺寸"出现，停一下，再变到新尺寸 ----
	# 这样玩家能明确看出"从多大长到多大"，而不是一出现就是最终大小。
	_inner = _prev_inner
	_set_inner(_prev_inner)

	_inner_tween = create_tween()
	# 1) 先停在旧尺寸
	_inner_tween.tween_interval(HOLD_BEFORE_CHANGE)
	# 2) 再过渡到新尺寸（带一点回弹感）
	_inner_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_inner_tween.tween_method(_set_inner, _prev_inner, _target_inner, INNER_EASE)
	_inner_tween.tween_callback(_commit_inner)

	# ---- 淡入 → 停留 → 淡出 ----
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_alpha, _alpha, 1.0, FADE_IN)
	_fade_tween.tween_interval(HOLD)
	_fade_tween.tween_method(_set_alpha, 1.0, 0.0, FADE_OUT)
	_fade_tween.tween_callback(_on_finished)


## 动画结束后把"当前尺寸"记成"上一句尺寸"，供下一句开场使用
func _commit_inner() -> void:
	_prev_inner = _target_inner


## 立刻收掉（进剧情 / 结算 / 暂停时用）
func hide_now() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	if _inner_tween != null and _inner_tween.is_valid():
		_inner_tween.kill()
	# 记下被打断时画到的位置，下次从它继续，避免尺寸跳变
	_prev_inner = _inner
	_alpha = 0.0
	visible = false
	queue_redraw()


func _set_inner(value: float) -> void:
	_inner = value
	queue_redraw()


func _set_alpha(value: float) -> void:
	_alpha = value
	queue_redraw()


func _on_finished() -> void:
	visible = false
	_alpha = 0.0
	queue_redraw()


func _draw() -> void:
	if _alpha <= 0.001:
		return
	var size_now := size
	if size_now.x < 2.0 or size_now.y < 2.0:
		size_now = get_viewport_rect().size
	var center := size_now * 0.5
	var r_out := minf(size_now.x, size_now.y) * R_OUT_RATIO
	var r_in := r_out * _inner
	var a := _alpha

	# 内圆里的黑色底（让文字浮出来）
	if r_in > 1.0:
		_draw_soft_disc(center, r_in, Color(0.0, 0.0, 0.0, DISC_ALPHA * a))

	# 内圆
	if r_in > 1.0:
		draw_arc(center, r_in, 0.0, TAU, 160, _with_alpha(RING_COLOR, a), INNER_WIDTH, true)

	# 外圆
	draw_arc(center, r_out, 0.0, TAU, 200, _with_alpha(RING_COLOR, a * 0.92), OUTER_WIDTH, true)

	# 句子文字：放在内圆中间偏上，自动缩字号 + 换行
	if _text.is_empty():
		return
	var font := _font
	if font == null:
		font = ThemeDB.fallback_font
	var usable := r_in * 1.66
	var font_size := _fit_font_size(font, _text, usable, r_in * 0.9)
	var line_h := font.get_height(font_size) * 1.18
	var total_h := line_h * _count_lines(font, _text, usable, font_size)
	var top := center.y - total_h * 0.5 + font.get_ascent(font_size)
	draw_multiline_string(font, Vector2(center.x - usable * 0.5, top), _text,
		HORIZONTAL_ALIGNMENT_CENTER, usable, font_size, -1, Color(1, 0.97, 0.93, a))


## 半透明圆盘：用中心实心圆 + 边缘渐隐近似，避免锯齿
func _draw_soft_disc(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center, radius, color, true, -1.0, true)


func _count_lines(font: Font, text: String, width: float, font_size: int) -> int:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if w <= width:
		return 1
	# 按可用宽度粗估需要几行（中文按字宽累加）
	var lines := 1
	var x := 0.0
	for ch in text:
		var cw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if x > 0.0 and x + cw > width:
			lines += 1
			x = 0.0
		x += cw
	return lines


## 字号自适应：**单行优先，但单行必须够大（≥20）**。
## 短句保持一整行好看；长句该折行就折行，不会缩成一条看不清的小字。
func _fit_font_size(font: Font, text: String, width: float, height: float) -> int:
	const MIN_SINGLE := 20
	const MAX_FS := 38
	var best_multi := 0
	var single := 0
	for fs in range(MAX_FS, 11, -1):
		var lines := _count_lines(font, text, width, fs)
		if lines > 4:
			continue
		var total := font.get_height(fs) * 1.18 * float(lines)
		if total > height:
			continue
		if lines == 1 and single == 0:
			single = fs
		best_multi = maxi(best_multi, fs)
		# 单行已经够大就不用再找了
		if single >= MIN_SINGLE:
			return single
	if single >= MIN_SINGLE:
		return single
	return maxi(best_multi, 13)


func _with_alpha(color: Color, a: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * a)
