extends Control
## 主界面：背景图 + 「接住」渐变标题 + 开始游戏 / 设置 / 离开
##
## 设置项：音量、全屏、模式（默认拼音）
## 设置会存到 user://settings.cfg，下次启动自动读取。

signal start_pressed(mode: String)
signal quit_pressed()

const SETTINGS_PATH := "user://settings.cfg"


var settings := {
	"volume": 80.0,
	"fullscreen": false,
	"mode": "pinyin",       ## 默认拼音模式
	"tutorial_seen": false, ## 是否已经看过第一次的操作说明
}

@onready var _title: Label = $Title
@onready var _buttons: VBoxContainer = $Buttons
@onready var _settings_panel: Panel = $Settings
@onready var _volume_slider: HSlider = $Settings/Contents/Volume/Slider
@onready var _volume_value: Label = $Settings/Contents/Volume/Value
@onready var _fullscreen_btn: Button = $Settings/Contents/Fullscreen/Toggle
@onready var _mode_btn: Button = $Settings/Contents/Mode/Toggle
var _in_settings := false


func _ready() -> void:
	_load_settings()
	_apply_settings()
	_refresh_setting_labels()


## 从暂停菜单打开「只显示设置」的浮层（不显示标题和主按钮）
func open_settings_overlay() -> void:
	visible = true
	_in_settings = true
	_buttons.visible = false
	_title.visible = false
	_settings_panel.visible = true
	_refresh_setting_labels()


func close_settings_overlay() -> void:
	_settings_panel.visible = false
	_in_settings = false
	_title.visible = true
	_buttons.visible = true
	visible = false


# ================================================================ 回调

func _on_start() -> void:
	if _in_settings:
		return
	# 操作说明改在游戏内弹出，主界面这里直接进游戏
	start_pressed.emit(String(settings["mode"]))


## 是否已经看过游戏内的操作说明
func has_seen_tutorial() -> bool:
	return bool(settings["tutorial_seen"])


## 标记已看过操作说明（游戏内关闭时调用）
func mark_tutorial_seen() -> void:
	settings["tutorial_seen"] = true
	_save_settings()


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
		settings["tutorial_seen"] = bool(cfg.get_value("game", "tutorial_seen", settings["tutorial_seen"]))
	if String(settings["mode"]) != "hanzi":
		settings["mode"] = "pinyin"


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", float(settings["volume"]))
	cfg.set_value("display", "fullscreen", bool(settings["fullscreen"]))
	cfg.set_value("game", "mode", String(settings["mode"]))
	cfg.set_value("game", "tutorial_seen", bool(settings["tutorial_seen"]))
	cfg.save(SETTINGS_PATH)


# ================================================================ 对外

## 打开主界面（回到菜单时调用）
func open() -> void:
	visible = true
	_in_settings = false
	_settings_panel.visible = false
	_title.visible = true
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
