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
const ADVANCE_HINT := "空格 / 回车 / 点击 继续　·　按住 Ctrl 快进"

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
func _apply_line_bg(path: String) -> void:
	if path.is_empty() or path == _bg_path:
		return
	if not ResourceLoader.exists(path):
		push_warning("StoryOverlay: 背景不存在 %s" % path)
		return
	var texture: Texture2D = load(path)
	if texture == null:
		return
	_bg.texture = texture
	_bg_path = path
	# 短淡入，避免硬切
	if _bg_tween != null and _bg_tween.is_valid():
		_bg_tween.kill()
	_bg.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_bg_tween = create_tween()
	_bg_tween.tween_property(_bg, "modulate:a", 1.0, 0.55)


func _next_line() -> void:
	_index += 1
	if _index >= _lines.size():
		_finish()
		return
	var line: Dictionary = _lines[_index]
	# 逐行背景：某一行写了 "bg" 就在这里换图（带一次短淡入）
	_apply_line_bg(String(line.get("bg", "")))
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
	_panel.offset_top = -248.0
	_panel.offset_right = -78.0
	_panel.offset_bottom = -54.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.038, 0.055, 0.88)
	style.border_color = Color(0.30, 0.28, 0.34, 0.75)
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
