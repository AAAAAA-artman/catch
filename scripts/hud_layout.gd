extends Node
## 通常布局和字号保存在 GameHUD 中，仅按句长调整台词字号。
@onready var _game := get_parent()
@onready var _panel: PanelContainer = $"../GameHUD/SentencePanel"
@onready var _label: RichTextLabel = $"../GameHUD/%SentenceLabel"


func _ready() -> void:
	_apply_all()
	_panel.resized.connect(_apply_all)


func _apply_all() -> void:
	var length := maxi(1, String(_game.current_sentence).length())
	var font_size := clampi(int(_panel.size.x * 0.85 / (1.02 * length)), 14, 27)
	_label.add_theme_font_size_override("normal_font_size", font_size)
