extends Control
## 主界面：背景图 + 「接住」渐变标题 + 开始游戏 / 设置 / 离开
##
## 设置项：音量、全屏、模式（默认拼音）
## 设置会存到 user://settings.cfg，下次启动自动读取。

signal start_pressed(mode: String)
signal quit_pressed()

const BG_PATH := "res://art/ui/menu_bg.jpg"
const FONT_PATH := "res://fonts/nanodasong.ttf"
const TITLE_SHADER := "res://shaders/title_gradient.gdshader"
const SETTINGS_PATH := "user://settings.cfg"

const TITLE_TEXT := "接住"

var settings := {
	"volume": 80.0,
	"fullscreen": false,
	"mode": "pinyin",       ## 默认拼音模式
}

var _bg: TextureRect
var _title: Label
var _title_mat: ShaderMaterial
var _buttons: VBoxContainer
var _settings_panel: Panel
var _volume_slider: HSlider
var _volume_value: Label
var _fullscreen_btn: Button
var _mode_btn: Button
var _font: Font
var _in_settings := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	_load_settings()
	_build()
	_apply_settings()
	_refresh_setting_labels()


# ================================================================ 构建界面

func _build() -> void:
	# 背景
	_bg = TextureRect.new()
	_bg.name = "Bg"
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(BG_PATH):
		_bg.texture = load(BG_PATH)
	add_child(_bg)

	# 底部压暗，保证按钮可读
	var dim := TextureRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.0))
	grad.set_color(1, Color(0, 0, 0, 0.55))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	dim.texture = gt
	add_child(dim)

	# 标题
	_title = Label.new()
	_title.name = "Title"
	_title.text = TITLE_TEXT
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font != null:
		_title.add_theme_font_override("font", _font)
	_title.add_theme_font_size_override("font_size", 148)
	_title.anchor_left = 0.0
	_title.anchor_right = 1.0
	_title.anchor_top = 0.0
	_title.anchor_bottom = 0.0
	_title.offset_top = 40.0
	_title.offset_bottom = 260.0
	if ResourceLoader.exists(TITLE_SHADER):
		_title_mat = ShaderMaterial.new()
		_title_mat.shader = load(TITLE_SHADER)
		_title_mat.set_shader_parameter("band_top", 0.05)
		_title_mat.set_shader_parameter("band_bottom", 0.30)
		_title.material = _title_mat
	add_child(_title)

	# 主按钮列
	_buttons = VBoxContainer.new()
	_buttons.name = "Buttons"
	_buttons.anchor_left = 0.5
	_buttons.anchor_right = 0.5
	_buttons.anchor_top = 0.5
	_buttons.anchor_bottom = 0.5
	_buttons.offset_left = -190.0
	_buttons.offset_right = 190.0
	# 对齐背景里那三张照片：间距 116，首个按钮中心在屏幕中心往下 30
	_buttons.offset_top = -4.0
	_buttons.offset_bottom = 340.0
	_buttons.add_theme_constant_override("separation", 48)
	add_child(_buttons)

	_add_menu_button("开始游戏", _on_start)
	_add_menu_button("设置", _on_open_settings)
	_add_menu_button("离开", _on_quit)

	_build_settings_panel()


func _add_menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(380, 68)
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	if _font != null:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 38)
	b.add_theme_color_override("font_color", Color(0.94, 0.92, 0.86, 0.92))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.80, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.94, 0.70, 1.0))
	# 悬停时一点点底色，更像可点
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1.0, 1.0, 1.0, 0.06)
	hover.set_corner_radius_all(6)
	b.add_theme_stylebox_override("hover", hover)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(1.0, 1.0, 1.0, 0.12)
	pressed.set_corner_radius_all(6)
	b.add_theme_stylebox_override("pressed", pressed)
	b.pressed.connect(cb)
	_buttons.add_child(b)
	return b


func _build_settings_panel() -> void:
	_settings_panel = Panel.new()
	_settings_panel.name = "Settings"
	_settings_panel.anchor_left = 0.5
	_settings_panel.anchor_right = 0.5
	_settings_panel.anchor_top = 0.5
	_settings_panel.anchor_bottom = 0.5
	_settings_panel.offset_left = -260.0
	_settings_panel.offset_right = 260.0
	_settings_panel.offset_top = -190.0
	_settings_panel.offset_bottom = 190.0
	_settings_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.04, 0.04, 0.97)
	style.border_color = Color(1.0, 0.94, 0.0, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 34.0
	style.content_margin_right = 34.0
	style.content_margin_top = 26.0
	style.content_margin_bottom = 26.0
	_settings_panel.add_theme_stylebox_override("panel", style)
	add_child(_settings_panel)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 34.0
	vb.offset_right = -34.0
	vb.offset_top = 26.0
	vb.offset_bottom = -26.0
	vb.add_theme_constant_override("separation", 22)
	_settings_panel.add_child(vb)

	var head := _make_label("设置", 32, Color(0.97, 0.95, 0.90))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(head)

	# 音量
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 14)
	vb.add_child(row1)
	row1.add_child(_make_label("音量", 26, Color(0.92, 0.90, 0.85)))
	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0
	_volume_slider.max_value = 100
	_volume_slider.step = 1
	_volume_slider.custom_minimum_size = Vector2(230, 34)
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.value_changed.connect(_on_volume_changed)
	row1.add_child(_volume_slider)
	_volume_value = _make_label("80", 22, Color(0.85, 0.92, 0.80))
	_volume_value.custom_minimum_size = Vector2(56, 0)
	_volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row1.add_child(_volume_value)

	# 全屏
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 14)
	vb.add_child(row2)
	row2.add_child(_make_label("全屏", 26, Color(0.92, 0.90, 0.85)))
	_fullscreen_btn = _make_value_button("关")
	_fullscreen_btn.custom_minimum_size = Vector2(120, 40)
	_fullscreen_btn.pressed.connect(_on_toggle_fullscreen)
	row2.add_child(_fullscreen_btn)

	# 模式
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 14)
	vb.add_child(row3)
	row3.add_child(_make_label("模式", 26, Color(0.92, 0.90, 0.85)))
	_mode_btn = _make_value_button("拼音")
	_mode_btn.custom_minimum_size = Vector2(120, 40)
	_mode_btn.pressed.connect(_on_toggle_mode)
	row3.add_child(_mode_btn)

	var tip := _make_label("（模式决定进入游戏后的打字方式）", 17, Color(0.72, 0.72, 0.68))
	vb.add_child(tip)

	# 返回
	var back := _make_value_button("返回")
	back.custom_minimum_size = Vector2(200, 46)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_close_settings)
	vb.add_child(back)


func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	if _font != null:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _make_value_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if _font != null:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", Color(1.0, 0.96, 0.84))
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1.0, 1.0, 1.0, 0.08)
	st.border_color = Color(1.0, 0.94, 0.0, 0.45)
	st.set_border_width_all(1)
	st.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", st)
	var hv := st.duplicate() as StyleBoxFlat
	hv.bg_color = Color(1.0, 1.0, 1.0, 0.16)
	b.add_theme_stylebox_override("hover", hv)
	return b


# ================================================================ 回调

func _on_start() -> void:
	if _in_settings:
		return
	start_pressed.emit(String(settings["mode"]))


func _on_open_settings() -> void:
	_in_settings = true
	_buttons.visible = false
	_settings_panel.visible = true
	_refresh_setting_labels()


func _close_settings() -> void:
	_in_settings = false
	_settings_panel.visible = false
	_buttons.visible = true
	_save_settings()


func _on_quit() -> void:
	quit_pressed.emit()


func _on_volume_changed(v: float) -> void:
	settings["volume"] = v
	_volume_value.text = str(int(v))
	_apply_volume()


func _on_toggle_fullscreen() -> void:
	settings["fullscreen"] = not bool(settings["fullscreen"])
	_apply_fullscreen()
	_refresh_setting_labels()
	_save_settings()


func _on_toggle_mode() -> void:
	settings["mode"] = "hanzi" if String(settings["mode"]) == "pinyin" else "pinyin"
	_refresh_setting_labels()
	_save_settings()


# ================================================================ 设置应用

func _apply_settings() -> void:
	_volume_slider.value = float(settings["volume"])
	_apply_volume()
	_apply_fullscreen()


func _apply_volume() -> void:
	var v := clampf(float(settings["volume"]), 0.0, 100.0)
	var db := -80.0 if v <= 0.5 else linear_to_db(v / 100.0)
	AudioServer.set_bus_volume_db(0, db)
	AudioServer.set_bus_mute(0, v <= 0.5)


func _apply_fullscreen() -> void:
	var want := bool(settings["fullscreen"])
	var mode := DisplayServer.window_get_mode()
	var is_fs := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if want and not is_fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not want and is_fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _refresh_setting_labels() -> void:
	if _volume_value != null:
		_volume_value.text = str(int(float(settings["volume"])))
	if _fullscreen_btn != null:
		_fullscreen_btn.text = "开" if bool(settings["fullscreen"]) else "关"
	if _mode_btn != null:
		_mode_btn.text = "拼音" if String(settings["mode"]) == "pinyin" else "汉字"


# ================================================================ 存档

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		settings["volume"] = float(cfg.get_value("audio", "volume", settings["volume"]))
		settings["fullscreen"] = bool(cfg.get_value("display", "fullscreen", settings["fullscreen"]))
		settings["mode"] = String(cfg.get_value("game", "mode", settings["mode"]))
	if String(settings["mode"]) != "hanzi":
		settings["mode"] = "pinyin"


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", float(settings["volume"]))
	cfg.set_value("display", "fullscreen", bool(settings["fullscreen"]))
	cfg.set_value("game", "mode", String(settings["mode"]))
	cfg.save(SETTINGS_PATH)


# ================================================================ 对外

## 打开主界面（回到菜单时调用）
func open() -> void:
	visible = true
	_in_settings = false
	_settings_panel.visible = false
	_buttons.visible = true
	_refresh_setting_labels()


func close() -> void:
	visible = false
	_in_settings = false
	_settings_panel.visible = false


func is_in_settings() -> bool:
	return _in_settings


func current_mode() -> String:
	return String(settings["mode"])
