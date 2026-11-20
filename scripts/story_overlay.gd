extends Control
## 剧情演出层：全屏背景图 + 底部对话框（打字机效果），空格 / 回车 / 点击推进。
##
## 这个脚本自己不决定什么时候播哪段剧情——那是 main.gd 的流程控制；
## 剧情文本在 scripts/story_data.gd 里。
##
## 用法：
##     @onready var story_overlay: Control = $StoryOverlay
##     story_overlay.finished.connect(_on_story_finished)
##     story_overlay.play("intro")

signal finished(segment_id: String)

const TYPE_SPEED := 38.0   ## 每秒显示多少字
const FADE_TIME := 0.45
const FAST_FORWARD_INTERVAL := 0.15
const ADVANCE_HINT := "空格 / 回车 / 点击 继续  ·  按住 Ctrl 快进"

var _lines: Array = []
var _index := -1
var _segment_id := ""
var _full_text := ""
var _typing := false
var _playing := false
var _shown := 0.0
var _fast_forward_elapsed := 0.0
var _tween: Tween

var _bg: TextureRect
var _bg_path := ""
var _bg_tween: Tween
## 换图时的黑屏过渡层
var _blackout: ColorRect
## 4:3 相框（剧情里插入的照片）
var _photo_frame: Panel
var _photo: TextureRect
var _photo_path := ""
var _photo_anim: Tween
## 「信」的竖排呈现（epilogue 里的父母台词）
var _letter_layer: Control = null
var _letter_labels: Array = []
var _letter_started := false
var _dim: ColorRect
var _panel: PanelContainer
var _speaker: Label
var _text: Label
var _hint: Label


func _ready() -> void:
	_build_ui()
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if not _playing:
		return
	if Input.is_key_pressed(KEY_CTRL):
		if _typing:
			_advance()
		_fast_forward_elapsed += delta
		if _fast_forward_elapsed >= FAST_FORWARD_INTERVAL:
			_next_line()
		return
	_fast_forward_elapsed = 0.0
	if not _typing:
		return
	_shown += TYPE_SPEED * delta
	var count := mini(int(_shown), _full_text.length())
	_text.text = _full_text.substr(0, count)
	if count >= _full_text.length():
		_typing = false
		_hint.text = ADVANCE_HINT


## 播放一段剧情。segment_id 见 StoryData.SEGMENTS。
func play(segment_id: String) -> void:
	var segment := StoryData.segment(segment_id)
	if segment.is_empty():
		push_warning("StoryOverlay: 找不到剧情段 %s" % segment_id)
		visible = false
		finished.emit(segment_id)
		return
	_segment_id = segment_id
	_lines = segment.get("lines", [])
	if _blackout != null:
		_blackout.color = Color(0, 0, 0, 0)
	var background: String = segment.get("background", "")
	_bg_path = ""
	if background != "":
		var texture: Texture2D = load(background)
		if texture != null:
			_bg.texture = texture
			_bg_path = background
	if _bg != null:
		_bg.modulate = Color.WHITE
	_index = -1
	_reset_photo()
	_clear_letter()
	# 相框放在最后（盖在背景上、对话框下）
	if _dim != null:
		move_child(_photo_frame, _dim.get_index())
	_playing = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_kill_tween()
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	set_process(true)
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_TIME)
	_next_line()


## 跳过当前剧情（带淡出），用于"跳过剧情"按钮。
func skip_all() -> void:
	if _playing:
		_finish()


## 立刻结束剧情、立即发 finished（不带淡出）。给测试和"一键跳过"用。
func finish_now() -> void:
	if not _playing:
		return
	_kill_tween()
	if _blackout != null:
		_blackout.color = Color(0, 0, 0, 0)
	if _bg_tween != null and _bg_tween.is_valid():
		_bg_tween.kill()
	_playing = false
	_typing = false
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	finished.emit(_segment_id)


# ================================================================ 内部

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


## 按行切换背景。路径没变就什么都不做，避免每行都重载。
## 清掉「信」的竖排文字
func _clear_letter() -> void:
	_letter_started = false
	_letter_labels.clear()
	if _letter_layer != null:
		_letter_layer.visible = false
		for c in _letter_layer.get_children():
			if c.name == "Scrim":
				continue
			c.queue_free()


## epilogue 的「父母」台词 = 那封信：竖排显示，最新一行在最下方，旧行往上推
func _update_letter_for_line(line: Dictionary) -> void:
	if _letter_layer == null:
		return
	var speaker := String(line.get("speaker", ""))
	var text := String(line.get("text", ""))
	var is_letter: bool = _segment_id == "epilogue" and speaker == "父母"
	if is_letter:
		_letter_started = true
		_add_letter_line(text)
		# 信期间不显示底部对话框
		if _panel != null:
			_panel.visible = false
	elif _letter_started:
		# 信之后的旁白：底部对话框回来，信留在背后
		if _panel != null:
			_panel.visible = true


func _add_letter_line(text: String) -> void:
	var vp := get_viewport_rect().size
	var font := _letter_font()
	var fs := 26
	var line_h := 48.0
	var col_w := vp.x * 0.62
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", fs)
	# 越早的行越淡，最新的最亮
	label.add_theme_color_override("font_color", Color(0.95, 0.94, 0.90, 0.95))
	label.size = Vector2(col_w, line_h)
	_letter_layer.add_child(label)
	_letter_labels.append(label)
	_relayout_letter(vp, col_w, line_h)
	_letter_layer.visible = true


## 最新一行固定在屏幕 72% 高度，其余向上排
func _relayout_letter(vp: Vector2, col_w: float, line_h: float) -> void:
	var n := _letter_labels.size()
	var base_y: float = vp.y * 0.72
	var col_x := (vp.x - col_w) * 0.5
	for i in range(n):
		var l: Label = _letter_labels[i]
		l.position = Vector2(col_x, base_y - float(n - 1 - i) * line_h)
		# 越旧越淡
		var age := float(n - 1 - i)
		l.add_theme_color_override("font_color",
			Color(0.95, 0.94, 0.90, clampf(0.95 - age * 0.08, 0.25, 0.95)))


func _letter_font() -> Font:
	var p := "res://fonts/nanodasong.ttf"
	if ResourceLoader.exists(p):
		return load(p)
	return null


## 换图时的黑屏过渡时长
const BLACKOUT_IN := 0.22
const BLACKOUT_HOLD := 0.16
const BLACKOUT_OUT := 0.30


## 按行切换背景。路径没变就什么都不做，避免每行都重载。
## 换图走一次「黑屏过渡」：淡到全黑 → 换图 → 淡回来，避免硬切突兀。
func _apply_line_bg(path: String) -> void:
	if path.is_empty() or path == _bg_path:
		return
	if not ResourceLoader.exists(path):
		push_warning("StoryOverlay: 背景不存在 %s" % path)
		return
	var texture: Texture2D = load(path)
	if texture == null:
		return
	if _bg_tween != null and _bg_tween.is_valid():
		_bg_tween.kill()
	_blackout.color = Color(0, 0, 0, 0)
	_bg_tween = create_tween()
	_bg_tween.tween_property(_blackout, "color:a", 1.0, BLACKOUT_IN)
	_bg_tween.tween_interval(BLACKOUT_HOLD)
	_bg_tween.tween_callback(func() -> void:
		_bg.texture = texture
		_bg_path = path
	)
	_bg_tween.tween_property(_blackout, "color:a", 0.0, BLACKOUT_OUT)


## 逐行照片：在 4:3 框里显示 / 收起
func _apply_line_photo(path: String) -> void:
	if path == _photo_path:
		return
	if path.is_empty():
		_reset_photo()
		return
	if not ResourceLoader.exists(path):
		push_warning("StoryOverlay: 照片不存在 %s" % path)
		return
	var texture: Texture2D = load(path)
	if texture == null:
		return
	_photo.texture = texture
	_photo_path = path
	_layout_photo_frame()
	if _photo_anim != null and _photo_anim.is_valid():
		_photo_anim.kill()
	_photo_frame.visible = true
	_photo_frame.modulate = Color(1, 1, 1, 0)
	_photo_anim = create_tween()
	_photo_anim.tween_interval(BLACKOUT_IN + BLACKOUT_HOLD)
	_photo_anim.tween_property(_photo_frame, "modulate:a", 1.0, 0.45)


## 4:3 相框放在画面上半部中央（避开底部对话框）
func _layout_photo_frame() -> void:
	if _photo_frame == null:
		return
	var vp := get_viewport_rect().size
	var h := vp.y * 0.68
	var w := h * 4.0 / 3.0
	if w > vp.x * 0.66:
		w = vp.x * 0.66
		h = w * 3.0 / 4.0
	_photo_frame.position = Vector2((vp.x - w) * 0.5, vp.y * 0.04)
	_photo_frame.size = Vector2(w, h)


func _reset_photo() -> void:
	_photo_path = ""
	if _photo_anim != null and _photo_anim.is_valid():
		_photo_anim.kill()
	if _photo_frame != null:
		_photo_frame.visible = false
		_photo_frame.modulate = Color(1, 1, 1, 1)


func _next_line() -> void:
	_index += 1
	if _index >= _lines.size():
		_finish()
		return
	var line: Dictionary = _lines[_index]
	# epilogue 里父母说的那封信：竖排堆叠呈现，不用底部对话框
	_update_letter_for_line(line)
	# 逐行背景：某一行写了 "bg" 就在这里换图（走黑屏过渡）
	_apply_line_bg(String(line.get("bg", "")))
	# 逐行照片：某一行写了 "photo" 就在 4:3 框里显示这张图
	_apply_line_photo(String(line.get("photo", "")))
	var speaker: String = line.get("speaker", "")
	_speaker.text = speaker
	_speaker.visible = speaker != ""
	_full_text = line.get("text", "")
	_text.text = ""
	_shown = 0.0
	_fast_forward_elapsed = 0.0
	_typing = true
	_hint.text = "按住 Ctrl 快进"


func _advance() -> void:
	if _typing:
		# 正在打字：一次补全
		_shown = float(_full_text.length())
		_text.text = _full_text
		_typing = false
		_hint.text = ADVANCE_HINT
		return
	_next_line()


func _finish() -> void:
	_playing = false
	_typing = false
	if _blackout != null:
		_blackout.color = Color(0, 0, 0, 0)
	if _bg_tween != null and _bg_tween.is_valid():
		_bg_tween.kill()
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	_tween.tween_callback(func() -> void:
		visible = false
		finished.emit(_segment_id)
	)


func _input(event: InputEvent) -> void:
	if not _playing or not visible:
		return
	var advance := false
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_SPACE or key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
				advance = true
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			advance = true
	if advance:
		_advance()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 背景图：铺满、保持比例裁切
	_bg = TextureRect.new()
	_bg.name = "Background"
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# 4:3 相框（默认隐藏）—— 和游戏里的画面框一样：黑底 + 黄色描边
	_photo_frame = Panel.new()
	_photo_frame.name = "PhotoFrame"
	_photo_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_photo_frame.visible = false
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0, 0, 0, 1)
	frame_style.border_color = Color(1.0, 0.94, 0.0, 0.9)
	frame_style.set_border_width_all(2)
	_photo_frame.add_theme_stylebox_override("panel", frame_style)
	add_child(_photo_frame)

	_photo = TextureRect.new()
	_photo.name = "Photo"
	_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_photo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_photo.offset_left = 2.0
	_photo.offset_top = 2.0
	_photo.offset_right = -2.0
	_photo.offset_bottom = -2.0
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_photo_frame.add_child(_photo)

	# 「信」层：竖排白字，逐行向上堆叠（类似 ED）
	_letter_layer = Control.new()
	_letter_layer.name = "Letter"
	_letter_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_letter_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_letter_layer.visible = false
	add_child(_letter_layer)

	# 暗底：信是白字，压在照片上必须压暗才能读
	var letter_scrim := ColorRect.new()
	letter_scrim.name = "Scrim"
	letter_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	letter_scrim.color = Color(0.0, 0.0, 0.0, 0.55)
	letter_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_letter_layer.add_child(letter_scrim)

	# 黑屏过渡层：换背景 / 插照片时从这里过一下
	_blackout = ColorRect.new()
	_blackout.name = "Blackout"
	_blackout.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blackout.color = Color(0, 0, 0, 0)
	_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_blackout)

	# 压暗层：让底部对话框上的字更容易读
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.02, 0.02, 0.04, 0.26)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	# 底部对话框
	_panel = PanelContainer.new()
	_panel.name = "Dialogue"
	_panel.anchor_left = 0.0
	_panel.anchor_top = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 78.0
	_panel.offset_top = -212.0
	_panel.offset_right = -78.0
	_panel.offset_bottom = -22.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.038, 0.055, 0.55)
	style.border_color = Color(0.55, 0.52, 0.60, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 30.0
	style.content_margin_right = 30.0
	style.content_margin_top = 22.0
	style.content_margin_bottom = 16.0
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)

	_speaker = Label.new()
	_speaker.name = "Speaker"
	_speaker.add_theme_font_size_override("font_size", 22)
	_speaker.add_theme_color_override("font_color", Color("f7d292"))
	column.add_child(_speaker)

	_text = Label.new()
	_text.name = "Text"
	_text.add_theme_font_size_override("font_size", 27)
	_text.add_theme_color_override("font_color", Color("fff3e8"))
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_text)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color("8d8798"))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_hint)
