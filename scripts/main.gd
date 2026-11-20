extends Control

const BASE_SCORE := {"neutral": 60, "positive": 40, "negative": 120}
## 每句好感度的基准值。keybr 打字分只用于"分数/速度"记录，
## 好感度单独按"句子类型 × 打字表现"算，**与句子长度无关**，
## 否则长句（新文案最长 36 字）会一句涨几十点，一阶段就打满。
const AFFECTION_PER_SENTENCE := {"neutral": 6.5, "positive": 4.5, "negative": 9.5}
## 判定"打得快/慢"的参考速度（字符/分），用来给好感度做 0.6~1.4 倍的浮动
const REFERENCE_CPM := {"hanzi": 45.0, "pinyin": 120.0}
## 句子库分三个阶段（对应《游戏总文案》的阶段一/二/三），跟着好感度推进。
const SENTENCE_PHASES := ["phase1", "phase2", "phase3"]
const ERROR_LOCK_SECONDS := 0.75
## 第二阶段进度到多少时，父母合影开始闪现
const PARENTS_FLASH_AT := 0.70
## 闪现期间从 overheard（偷听到的）好句子池抽句
const OVERHEARD_SENTENCES := 3

## 每个阶段 10 句（三阶段共 30 句）
const ROUNDS_PER_STAGE := 10
const STAGE_COUNT := 3
const MAX_ROUNDS := ROUNDS_PER_STAGE * STAGE_COUNT
const MAX_VALUE := 100.0

var phase := "title"
var round_number := 0
var affection := 0.0
var pressure := 0.0
var numbness := 0.0
var score := 0
var best_score := 0
var best_speed := 0.0
var correct_characters := 0
var mistakes := 0
var phrase_mistakes := 0
var error_flash := false
var error_flash_id := 0
var input_lock_left := 0.0
## voice playing -> input locked
var voice_waiting := false
## voice wait timeout guard
const VOICE_WAIT_LIMIT := 8.0
var _voice_wait_elapsed := 0.0
var has_started_typing := false
var phrase_elapsed := 0.0
var time_left := 0.0
var time_limit := 0.0
var current_kind := "neutral"
var current_sentence := ""
var current_pinyin := PackedStringArray()
var current_target := ""
var last_sentence := ""
## 当前句的说话人（father / mother，来自 sentence_data 的 speaker 标签）
var current_speaker := ""
## 当前句的语音长度类型（short / long / long_short / short_long）
var current_voice_len := ""
var input_mode := "hanzi"
var records := {
	"hanzi": {"best_score": 0, "best_speed": 0.0},
	"pinyin": {"best_score": 0, "best_speed": 0.0}
}
var rng := RandomNumberGenerator.new()
var kind_deck: Array[String] = []
## 抽取状态：已经抽过的句子 "phase:kind" -> Array[String]
var _used_texts := {}
## 当前连续同类型句数
var _kind_run := 0
## 上一句的类型（池名）
var _last_kind := ""
## 上一句的档位 1~5
var _last_tier := 3
## 连续同「侧」句数（-1 坏 / 0 中 / +1 好）
## 判上限必须按侧算：坏2→坏1 交替时"同档位"计数会被重置，导致连续坏句不受控
var _side_run := 0
var _last_side := 0

@onready var title_label: Label = %TitleLabel
@onready var state_label: Label = %StateLabel
@onready var round_label: Label = %RoundLabel
@onready var sentence_label: RichTextLabel = %SentenceLabel
@onready var hanzi_row: HFlowContainer = %HanziRow
@onready var pinyin_row: HFlowContainer = %PinyinRow
@onready var sentence_lane: Control = %SentenceLane
var pinyin_cells: Array = []
var character_targets: Array[Label] = []
@onready var cursor_rect: ColorRect = %CursorRect
var cursor_tween: Tween
@onready var stats_label: Label = %StatsLabel
@onready var input_box: LineEdit = %InputBox
@onready var affection_bar: ProgressBar = %AffectionBar
@onready var pressure_bar: Control = %PressureBar
@onready var numbness_bar: Control = %NumbnessBar
@onready var time_bar: Control = $TimeBar
@onready var feedback_label: Label = %FeedbackLabel
@onready var pause_overlay: ColorRect = %PauseOverlay
var feedback_tween: Tween
@onready var text_fx_root: Node2D = $Stage/TextFx
@onready var story_overlay: Control = $StoryOverlay
@onready var voice_player: Node = $Voice
@onready var bgm_player: Node = $Bgm
@onready var sfx_player: Node = $Sfx
@onready var hud_layout: Node = $HudLayout
@onready var circle_fx: Control = %CircleFx
@onready var mood_layer: Control = %MoodLayer
@onready var phase2_room: Control = %Phase2Room
@onready var parents_flash: Control = %ParentsFlash
@onready var phase3_gallery: Control = %Phase3Gallery
@onready var ambient: Node = $Ambient
@onready var stress_audio: Node = $StressAudio
@onready var tears_fx: Control = %TearsFx
@onready var p3_tears: Control = %Phase3TearsFx

# ---- 剧情流程 ----
# 五段剧情的统一叫法与 BGM 对应：
#   prologue   回家路上→进门→睡着        Circulation
#   act1_intro 过渡文本一（梦中醒来，变小、被声音淹没）Dream Street
#   act1_end   第一段游戏后的剧情         There's Something Outside
#   act2_end   第二段游戏后的剧情         萍逢
#   epilogue   第三段→结局                萍逢
# 触发点：开局 prologue → act1_intro（**都在第一段游戏开始之前**）；
#         第一段游戏结束 act1_end；第二段游戏结束 act2_end；
#         第三段游戏结束 epilogue。
const STORY_PROLOGUE := "prologue"
const STORY_ACT1_INTRO := "act1_intro"
const STORY_ACT1_END := "act1_end"
const STORY_ACT2_END := "act2_end"
const STORY_EPILOGUE := "epilogue"
## 三段游戏的划分阈值（好感度 1/3、2/3）
const STORY_MID_1 := MAX_VALUE / 3.0
const STORY_MID_2 := MAX_VALUE * 2.0 / 3.0
var story_seen := {}
var story_resume := ""      # 剧情结束后要接的流程："start" / "advance" / "ending"
var pending_message := ""   # 剧情结束后要显示的下一句提示

# 弯曲文字（addons/text_fx）在场景里的落点：HUD 下方、句子卡片上方那条空带
## 弧线文字画在 Stage 里（664x400 的设计稿尺寸），所以锚点和字号都按这个尺子来
const CURVED_TEXT_ANCHOR := Vector2(332.0, 132.0)
const CURVED_BANNER_ANCHOR := Vector2(332.0, 120.0)

## ---- 画面飘字的节奏（想改手感就动这几个数）----
## 淡入时长（秒）。越大出现得越慢。
const SENTENCE_FADE_IN := 2.2
## 淡入时从下方往上滑的距离（像素）
const SENTENCE_FADE_DRIFT := 26.0
## 打完这句话后淡出的时长
const SENTENCE_FADE_OUT := 0.7
# 挡开/结局这类横幅要先独占屏幕一会儿，下一句的弧线文字晚一点再进场
var curved_arc_defer := 0.0

# ---- 抵抗（Alt）：不再直接跳句，而是把这句话的计时快速推到底 ----
## ---- 抵抗（Alt）新规则 ----
## 按住固定 2.5 秒，这句话被跳过
const RESIST_HOLD_TIME := 2.5
## 每抵抗一句：麻木固定 +14
const RESIST_NUMBNESS := 14.0
## 每抵抗一句：好感 -3（不加压力）
const RESIST_AFFECTION_LOSS := 3.0

## ---- 句子五档（1 = 最坏，5 = 最好）----
## 每档对压力 / 好感的影响
const TIER_PRESSURE := {1: 12.0, 2: 8.0, 3: 1.0, 4: -8.0, 5: -14.0}
const TIER_AFFECTION_BONUS := {1: 0.75, 2: 0.90, 3: 1.00, 4: 1.10, 5: 1.25}
## 抽取权重（中性最多，两端最少）
const TIER_WEIGHT := {1: 1.2, 2: 2.4, 3: 5.0, 4: 2.4, 5: 1.2}
## 连续同侧上限：坏（1/2）最多 2 次，好（4/5）与中性最多 4 次
const TIER_MAX_RUN := {1: 2, 2: 2, 3: 4, 4: 4, 5: 4}
var resisting := false
## 抵抗剩余时间（秒）
var resist_hold_left := 0.0
## 当前句的档位 1~5
var current_tier := 3

# 开发者模式：免死（压力/麻木不会导致失败）
var debug_invincible := false

# ---- 紧张音：剩余时间少于某个比例时循环播放 ----
## 剩余时间 / 总时间 低于这个比例就进"紧张状态"
const TENSION_RATIO := 0.3
## 第三阶段：每接受一句话，泪水强度涨多少（模拟逐渐流泪）
const P3_TEARS_STEP := 0.135
## 每个阶段开头固定播放的句子（key = round_number）
##   第一段：1「你什么时候回来的」→ 2「房门别关上啊」
##   第二段：11「不要把门关上」→ 12「一进屋就看见你房间关着个门难看死了」
##   第三段：21「门开着吧要不都看不见你」
## 终章 5 句的配图：每打完一句换下一张，没下一张就停在最后一张
const FINAL_IMAGES := [
	"res://art/story/fin_1.jpg",
	"res://art/story/fin_2.jpg",
	"res://art/story/fin_3.jpg",
	"res://art/story/fin_4.jpg",
]

## 终章 → Ending 期间循环播放的曲子
const FINAL_BGM := "res://audio/bgm/out_of_love.mp3"

const OPENERS := {
	1: "你什么时候回来的",
	2: "房门别关上啊",
	11: "不要把门关上",
	12: "一进屋就看见你房间关着个门难看死了",
	21: "门开着吧要不都看不见你",
}
## 同类型句子连续抽取的硬上限（坏句可能致死，只允许连续 2 次）
const MAX_RUN := {"neutral": 4, "positive": 4, "negative": 2}

const P3_TEARS_MAX := 0.95


func _ready() -> void:
	rng.randomize()
	_apply_font_to_static_labels()
	_load_records()
	input_box.text_changed.connect(_on_text_changed)
	story_overlay.finished.connect(_on_story_finished)
	_hide_stat_labels()
	_create_main_menu()
	_build_pause_menu()
	_build_tutorial_overlay()
	_build_ending_layer()
	_show_menu()
	if bgm_player != null:
		bgm_player.play("res://audio/bgm/intro_circulation.mp3")


func _process(delta: float) -> void:
	_update_mood_layer()
	# 终章：只累计用时（不计时、不加压力、不跑环境音）
	if phase == "final":
		if input_lock_left > 0.0:
			input_lock_left = maxf(0.0, input_lock_left - delta)
		phrase_elapsed += delta
		_update_ambient()
		_update_stress_audio()
		return
	if phase != "playing":
		return
	# ---- 语音等待：播完才放开输入 ----
	if voice_waiting:
		_voice_wait_elapsed += delta
		var still_playing: bool = voice_player != null and voice_player.is_playing()
		if not still_playing or _voice_wait_elapsed >= VOICE_WAIT_LIMIT:
			voice_waiting = false
			_voice_wait_elapsed = 0.0
			if input_lock_left <= 0.0:
				if input_mode == "hanzi":
					input_box.editable = true
					input_box.call_deferred("grab_focus")
				state_label.text = "可以开始输入"

	if input_lock_left > 0.0:
		input_lock_left = maxf(0.0, input_lock_left - delta)
		if input_lock_left == 0.0 and not voice_waiting:
			if input_mode == "hanzi":
				input_box.editable = true
				input_box.call_deferred("grab_focus")
			state_label.text = "可以继续输入"
	phrase_elapsed += delta
	if resisting:
		# 抵抗：独立的固定 2.5 秒计时，不消耗本句时间
		_tick_resist(delta)
	else:
		time_left = maxf(0.0, time_left - delta)
	# 左竖条显示"剩余时间"，所以是反向
	if time_bar != null:
		time_bar.value = 100.0 * (time_left / maxf(time_limit, 0.001))
	_update_tension_audio()
	_update_ambient()
	_update_stress_audio()
	if time_left <= 0.0:
		_end_resist()
		_fade_out_curved_sentence()
		pressure = minf(MAX_VALUE, pressure + 20.0)
		_update_bars()
		if sfx_player != null:
			sfx_player.play_sentence_fail()
		if _check_loss():
			return
		_advance_sentence("没能接住这句话。压力 +20")


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		# Alt 松开 = 结束抵抗
		if key.keycode == KEY_ALT and not key.pressed and resisting:
			_end_resist()
		return
	if phase == "ending":
		if key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			_skip_ending()
			accept_event()
		return
	if phase == "tutorial":
		if key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			_close_tutorial()
			accept_event()
		return
	if phase == "story":
		return
	if key.keycode == KEY_ESCAPE:
		if _pause_settings_open:
			# 先关设置浮层，回到暂停菜单
			_close_pause_settings()
			accept_event()
			return
		if phase == "playing" or phase == "final":
			_pause_game()
			accept_event()
		elif phase == "paused":
			_resume_game()
			accept_event()
		elif phase == "won" or phase == "lost":
			_return_to_menu()
			accept_event()
		return
	if phase == "menu":
		# 主界面里 Esc 关闭设置面板
		if key.keycode == KEY_ESCAPE and main_menu != null and main_menu.is_in_settings():
			main_menu.call("_close_settings")
			accept_event()
	elif (phase == "won" or phase == "lost") and key.keycode == KEY_R:
		_start_game(input_mode)
		accept_event()
	elif (phase == "won" or phase == "lost") and (key.keycode == KEY_1 or key.keycode == KEY_2):
		_start_game("hanzi" if key.keycode == KEY_1 else "pinyin")
		accept_event()
	elif phase == "playing" and key.keycode == KEY_ALT:
		_begin_resist()
		accept_event()
	elif (phase == "playing" or phase == "final") and input_mode == "pinyin":
		_handle_pinyin_key(key)


func _handle_pinyin_key(key: InputEventKey) -> void:
	if input_lock_left > 0.0 or voice_waiting:
		accept_event()
		return
	if key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return
	if key.keycode == KEY_BACKSPACE:
		if not input_box.text.is_empty():
			input_box.text = input_box.text.substr(0, input_box.text.length() - 1)
			_on_text_changed(input_box.text)
		accept_event()
		return
	if key.unicode < 32 or key.unicode > 126:
		return
	input_box.text += String.chr(key.unicode)
	_on_text_changed(input_box.text)
	accept_event()


## 打字游戏里所有字用的字体（纳米全大宋，1.ttf，58936 字形，免费商用）
const GAME_FONT_PATH := "res://fonts/nanodasong.ttf"
var _game_font: Font = null


## 懒加载游戏字体；找不到就回退到引擎默认字体。
func _game_font_resource() -> Font:
	if _game_font == null:
		if ResourceLoader.exists(GAME_FONT_PATH):
			_game_font = load(GAME_FONT_PATH)
		if _game_font == null:
			_game_font = ThemeDB.fallback_font
	return _game_font


func _make_label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	var font := _game_font_resource()
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## 场景里静态的 Label / RichTextLabel 也换成本次选定的字体，
## 这样对局中的句子卡片、状态行、反馈提示风格统一。
func _apply_font_to_static_labels() -> void:
	var font := _game_font_resource()
	if font == null:
		return
	for node in find_children("*", "", true, false):
		if node is Label:
			(node as Label).add_theme_font_override("font", font)
		elif node is RichTextLabel:
			var rtl := node as RichTextLabel
			rtl.add_theme_font_override("normal_font", font)
			rtl.add_theme_font_override("bold_font", font)
		elif node is LineEdit:
			(node as LineEdit).add_theme_font_override("font", font)
		elif node is ProgressBar:
			pass


## Ending 画面：半透明黑底 + 白字从下往上飘
func _build_ending_layer() -> void:
	_ending_layer = Control.new()
	_ending_layer.name = "EndingLayer"
	_ending_layer.z_index = 45
	_ending_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_ending_layer.visible = false
	add_child(_ending_layer)
	_ending_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vp := get_viewport_rect().size

	# 半透明黑底
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.0, 0.0, 0.0, 0.74)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ending_layer.add_child(scrim)

	# 滚动容器：手动算每一行的 y，避免 VBox 在滚动容器里算不出高度
	_ending_roll = Control.new()
	_ending_roll.name = "Roll"
	_ending_roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ending_layer.add_child(_ending_roll)

	var font := _game_font_resource()
	const FS := 25
	const LINE_H := 46.0
	var col_w := vp.x * 0.72
	var col_x := vp.x * 0.14
	var y := 0.0
	for raw in EndingText.LINES:
		var text := String(raw)
		if text != "":
			var l := Label.new()
			l.text = text
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if font != null:
				l.add_theme_font_override("font", font)
			l.add_theme_font_size_override("font_size", FS)
			l.add_theme_color_override("font_color", Color(0.95, 0.94, 0.90, 0.95))
			l.position = Vector2(col_x, y)
			l.size = Vector2(col_w, LINE_H)
			_ending_roll.add_child(l)
		y += LINE_H
	_ending_content_h = y

	# 底部渐变暗带 + 跳过提示
	var foot := TextureRect.new()
	foot.name = "FootGrad"
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.anchor_left = 0.0
	foot.anchor_right = 1.0
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_top = -100.0
	foot.offset_bottom = 0.0
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0))
	g.set_color(1, Color(0, 0, 0, 0.9))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	foot.texture = gt
	_ending_layer.add_child(foot)

	var hint := Label.new()
	hint.name = "SkipHint"
	hint.text = "空格 / 回车 / 点击 跳过"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font != null:
		hint.add_theme_font_override("font", font)
	hint.add_theme_font_size_override("font_size", 17)
	hint.add_theme_color_override("font_color", Color(0.72, 0.72, 0.70, 0.95))
	# 放右上角，避免和滚动文字打架
	hint.anchor_left = 1.0
	hint.anchor_right = 1.0
	hint.anchor_top = 0.0
	hint.anchor_bottom = 0.0
	hint.offset_left = -320.0
	hint.offset_right = -24.0
	hint.offset_top = 18.0
	hint.offset_bottom = 46.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ending_layer.add_child(hint)


## 播放 Ending 滚动。全部滚完会自动进结算画面。
func _play_ending_roll() -> void:
	if _ending_layer == null:
		_end_game(true)
		return
	phase = "ending"
	pause_overlay.hide()
	story_overlay.hide()
	# 只隐藏对局 HUD，保留第三阶段的全屏照片做底
	_set_game_hud_visible(false)
	if phase3_gallery != null:
		phase3_gallery.visible = true
		if phase3_gallery.has_method("snap_full"):
			phase3_gallery.snap_full()
	_ending_layer.visible = true

	var vp := get_viewport_rect().size
	_ending_roll.position = Vector2(0.0, vp.y)
	if _ending_tween != null and _ending_tween.is_valid():
		_ending_tween.kill()
	# 速度约 30 像素/秒，太短的话给个下限
	var duration: float = maxf(26.0, (_ending_content_h + vp.y) / 30.0)
	_ending_tween = create_tween()
	_ending_tween.tween_property(_ending_roll, "position:y", -_ending_content_h - 60.0, duration)
	_ending_tween.tween_callback(_on_ending_finished)


func _on_ending_finished() -> void:
	if phase != "ending":
		return
	if _ending_tween != null and _ending_tween.is_valid():
		_ending_tween.kill()
	if _ending_layer != null:
		_ending_layer.visible = false
	_save_records()
	# ED 播完 → 回主界面（而不是停在结算页）
	_return_to_menu()


## 跳过 Ending
func _skip_ending() -> void:
	if phase != "ending":
		return
	_on_ending_finished()


## 游戏内的操作说明浮层（第一次进入时弹一次）
func _build_tutorial_overlay() -> void:
	_tutorial_layer = Control.new()
	_tutorial_layer.name = "TutorialLayer"
	_tutorial_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tutorial_layer.z_index = 55
	_tutorial_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_tutorial_layer.visible = false
	add_child(_tutorial_layer)
	_tutorial_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.02, 0.03, 0.04, 0.72)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_layer.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.04, 0.04, 0.97)
	style.border_color = Color(1.0, 0.94, 0.0, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 36.0
	style.content_margin_right = 36.0
	style.content_margin_top = 26.0
	style.content_margin_bottom = 24.0
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)

	var font := _game_font_resource()

	var head := Label.new()
	head.text = "操作说明"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font != null:
		head.add_theme_font_override("font", font)
	head.add_theme_font_size_override("font_size", 30)
	head.add_theme_color_override("font_color", Color(0.97, 0.95, 0.90))
	vb.add_child(head)

	var lines := [
		"· 屏幕上会出现一句话，把它完整打出来就算「接住」",
		"· 打错要整句重打，压力 +8",
		"· 按住 Alt 可以抵抗跳过这句：麻木 +14、好感 −3，但不加压力",
		"· 左条是剩余时间，右边两条是压力与麻木，任一满 100 就失败",
		"· Esc 打开暂停菜单（继续 / 设置 / 回主界面）",
		"· 打字方式（拼音 / 汉字）可在「设置」里切换，默认拼音",
	]
	for t in lines:
		var l := Label.new()
		l.text = t
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(620, 0)
		if font != null:
			l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", 20)
		l.add_theme_color_override("font_color", Color(0.88, 0.87, 0.82))
		vb.add_child(l)

	var tip := Label.new()
	tip.text = "按 空格 / 回车 或点下面按钮开始"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font != null:
		tip.add_theme_font_override("font", font)
	tip.add_theme_font_size_override("font_size", 16)
	tip.add_theme_color_override("font_color", Color(0.70, 0.70, 0.66))
	vb.add_child(tip)

	var ok := Button.new()
	ok.text = "明白了，开始"
	ok.custom_minimum_size = Vector2(260, 50)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.focus_mode = Control.FOCUS_NONE
	if font != null:
		ok.add_theme_font_override("font", font)
	ok.add_theme_font_size_override("font_size", 24)
	ok.add_theme_color_override("font_color", Color(1.0, 0.96, 0.84))
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1, 1, 1, 0.08)
	st.border_color = Color(1.0, 0.94, 0.0, 0.5)
	st.set_border_width_all(1)
	st.set_corner_radius_all(6)
	ok.add_theme_stylebox_override("normal", st)
	var hv := st.duplicate() as StyleBoxFlat
	hv.bg_color = Color(1, 1, 1, 0.16)
	ok.add_theme_stylebox_override("hover", hv)
	ok.pressed.connect(_close_tutorial)
	vb.add_child(ok)


func _maybe_show_tutorial() -> void:
	if _tutorial_layer == null:
		return
	if main_menu != null and main_menu.has_seen_tutorial():
		return
	phase = "tutorial"
	_tutorial_layer.visible = true
	input_box.editable = false
	state_label.text = "先看一下操作说明"


func _close_tutorial() -> void:
	if _tutorial_layer == null or not _tutorial_layer.visible:
		return
	_tutorial_layer.visible = false
	if main_menu != null:
		main_menu.mark_tutorial_seen()
	phase = "playing"
	input_box.editable = input_mode == "hanzi" and input_lock_left <= 0.0 and not voice_waiting
	state_label.text = "正在对话"
	_apply_input_box_visibility()
	# 教程期间 phase != "playing"，_place_cursor_after_layout 会被跳过，
	# 字格一直是没按真实宽度排过的状态（会变成巨大单字）。这里补一次。
	_layout_sentence()
	call_deferred("_place_cursor_after_layout")
	if input_box.editable:
		input_box.call_deferred("grab_focus")


## 构建暂停菜单的四颗按钮（继续 / 设置 / 回主界面 / 离开）
func _build_pause_menu() -> void:
	var contents := pause_overlay.get_node_or_null("Center/PauseCard/PauseContents")
	if contents == null:
		return
	var hint := contents.get_node_or_null("PauseHint") as Label
	if hint != null:
		hint.text = "Esc 继续对话 · 下面是菜单"

	var specs := [
		["继续游戏", _resume_game],
		["设置", _open_pause_settings],
		["返回主界面", _return_to_menu],
		["离开游戏", _quit_game],
	]
	for it in specs:
		var b := Button.new()
		b.text = String(it[0])
		b.custom_minimum_size = Vector2(300, 46)
		b.focus_mode = Control.FOCUS_NONE
		var font := _game_font_resource()
		if font != null:
			b.add_theme_font_override("font", font)
		b.add_theme_font_size_override("font_size", 24)
		b.add_theme_color_override("font_color", Color(0.93, 0.90, 0.84))
		b.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.78))
		var st := StyleBoxFlat.new()
		st.bg_color = Color(1, 1, 1, 0.05)
		st.border_color = Color(1.0, 0.94, 0.0, 0.35)
		st.set_border_width_all(1)
		st.set_corner_radius_all(6)
		b.add_theme_stylebox_override("normal", st)
		var hv := st.duplicate() as StyleBoxFlat
		hv.bg_color = Color(1, 1, 1, 0.14)
		b.add_theme_stylebox_override("hover", hv)
		b.pressed.connect(it[1])
		contents.add_child(b)


func _pause_game() -> void:
	if phase != "playing" and phase != "final":
		return
	_paused_from = phase
	phase = "paused"
	if resisting:
		_end_resist()
	input_box.editable = false
	state_label.text = "已暂停"
	pause_overlay.show()


func _resume_game() -> void:
	if phase != "paused":
		return
	if _pause_settings_open:
		_close_pause_settings()
		return
	phase = _paused_from if _paused_from != "" else "playing"
	pause_overlay.hide()
	input_box.editable = input_mode == "hanzi" and input_lock_left <= 0.0 and not voice_waiting
	state_label.text = "正在对话"
	_apply_input_box_visibility()
	if input_box.editable:
		input_box.call_deferred("grab_focus")


func _open_pause_settings() -> void:
	if main_menu == null:
		return
	_pause_settings_open = true
	pause_overlay.hide()
	main_menu.call("open_settings_overlay")


func _close_pause_settings() -> void:
	_pause_settings_open = false
	if main_menu != null:
		main_menu.call("close_settings_overlay")
	# 回到暂停菜单
	pause_overlay.show()


func _return_to_menu() -> void:
	if voice_player != null:
		voice_player.stop_all()
	if sfx_player != null:
		sfx_player.stop_all()
	if ambient != null:
		ambient.stop_all()
	if stress_audio != null:
		stress_audio.stop_all()
	_end_resist()
	_set_tension(false)
	_clear_curved_text()
	_pause_settings_open = false
	pause_overlay.hide()
	_show_menu()


func _quit_game() -> void:
	get_tree().quit()


## 创建主界面（代码生成，不改场景文件）
## 永久隐藏顶部「第 X / 30 句」和「分数/准确率/最快」这两块统计
func _hide_stat_labels() -> void:
	if round_label != null:
		round_label.visible = false
	if stats_label != null:
		stats_label.visible = false
	var sb := get_node_or_null("StatsBack")
	if sb != null:
		sb.visible = false


func _create_main_menu() -> void:
	var script_res := load("res://scripts/main_menu.gd")
	if script_res == null:
		push_warning("Main: 找不到 main_menu.gd，直接进标题态")
		_show_title()
		return
	main_menu = Control.new()
	main_menu.set_script(script_res)
	main_menu.name = "MainMenu"
	main_menu.z_index = 60
	add_child(main_menu)
	# 程序化创建的 Control 默认尺寸是 0，必须显式铺满，
	# 否则背景图和按钮都会按 0 尺寸布局（挤在左上角）
	main_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_menu.offset_left = 0.0
	main_menu.offset_top = 0.0
	main_menu.offset_right = 0.0
	main_menu.offset_bottom = 0.0
	main_menu.start_pressed.connect(_on_menu_start)
	main_menu.quit_pressed.connect(_on_menu_quit)


func _on_menu_start(mode: String) -> void:
	_pause_settings_open = false
	pause_overlay.hide()
	if _tutorial_layer != null:
		_tutorial_layer.visible = false
	if main_menu != null:
		main_menu.close()
	_set_game_hud_visible(true)
	# 主界面可能改了音量，重新应用一次
	_start_game(mode)


func _on_menu_quit() -> void:
	get_tree().quit()


## 进入主界面：隐藏所有对局 HUD
func _show_menu() -> void:
	phase = "menu"
	pause_overlay.hide()
	feedback_label.hide()
	cursor_rect.hide()
	story_overlay.hide()
	_set_game_hud_visible(false)
	if main_menu != null:
		main_menu.open()
	_sync_bgm_for_act()


## 对局 HUD 的整体显隐（主界面用）
func _set_game_hud_visible(on: bool) -> void:
	for node in [time_bar, pressure_bar, numbness_bar,
			get_node_or_null("TimeCaption"),
			get_node_or_null("PressureCaption"),
			get_node_or_null("NumbnessCaption"),
			get_node_or_null("%SentencePanel"),
			circle_fx, tears_fx, p3_tears,
			get_node_or_null("Stage"), get_node_or_null("Backdrop")]:
		if node != null:
			node.visible = on
	if on:
		# 回到对局时恢复各组件的正常显隐规则
		_set_final_hud(false)
		if not _dialog_hidden_p3:
			pass
	# 画面层（一/二/三阶段）由各自的状态机管，这里只在离开对局时统一收掉，
	# 否则 _set_game_hud_visible(true) 会把二阶段房间强行打开
	if not on:
		if mood_layer != null:
			mood_layer.set_active(false)
		if phase2_room != null:
			phase2_room.set_active(false)
		if phase3_gallery != null:
			phase3_gallery.reset()
		if parents_flash != null:
			parents_flash.stop_flash()
	if title_label != null:
		title_label.visible = false


func _show_title() -> void:
	phase = "title"
	pause_overlay.hide()
	feedback_label.hide()
	cursor_rect.hide()
	state_label.text = "第一场 · 面对一段对话"
	sentence_label.text = "选择打字方式，接住那些向你靠近的句子。"
	sentence_label.show()
	hanzi_row.hide()
	pinyin_row.hide()
	input_box.show()
	input_box.text = ""
	_last_input_length = 0  # 换句/进剧情时同步重置击键计数
	input_box.editable = false
	if round_label != null and false:
		round_label.text = "1 汉字   2 拼音"
	_refresh_stats()
	_update_bars()
	_clear_curved_text()
	story_overlay.hide()
	story_seen.clear()


func _start_game(mode: String) -> void:
	input_mode = mode
	pause_overlay.hide()
	feedback_label.hide()
	best_score = int(records[mode]["best_score"])
	best_speed = float(records[mode]["best_speed"])
	phase = "playing"
	round_number = 0
	affection = 0.0
	if has_node("%CircleFx"):
		%CircleFx.hide_now()
	if mood_layer != null:
		mood_layer.reset()
	if phase2_room != null:
		phase2_room.reset()
	if phase3_gallery != null:
		phase3_gallery.reset()
	_dialog_home_rect = Rect2()
	_dialog_hidden_p3 = false
	_phase3_first_round = -1
	_ending_muted = false
	_reset_phase3_tears()
	# 终章状态复位
	_final_queue.clear()
	_final_done = 0
	_final_played = false
	_final_finishing = false
	_final_image_index = -1
	_final_music_on = false
	_set_final_hud(false)
	if tears_fx != null:
		tears_fx.hide_now()
	# 恢复对话框位置（上一局第三阶段可能把它移开了）
	if _dialog_swing_tween != null and _dialog_swing_tween.is_valid():
		_dialog_swing_tween.kill()
	if hud_layout != null:
		hud_layout.call_deferred("_apply_all")
	if ambient != null:
		ambient.stop_all()
	if stress_audio != null:
		stress_audio.stop_all()
	pressure = 0.0
	numbness = 0.0
	score = 0
	correct_characters = 0
	mistakes = 0
	phrase_mistakes = 0
	input_lock_left = 0.0
	voice_waiting = false
	_voice_wait_elapsed = 0.0
	has_started_typing = false
	last_sentence = ""
	_reset_draw_state()
	input_box.editable = false
	_update_bars()
	_clear_curved_text()
	curved_arc_defer = 0.0
	story_seen.clear()
	_set_tension(false)
	story_resume = "start"
	_play_story(STORY_PROLOGUE)


func _advance_sentence(message: String) -> void:
	if affection >= MAX_VALUE:
		_end_game(true)
		return
	if round_number >= MAX_ROUNDS:
		_end_game(false)
		return
	round_number += 1
	# 登记第三阶段第一句的句号，供布局切换判定
	if _story_stage() == 3 and _phase3_first_round < 0:
		_phase3_first_round = round_number
	# 阶段开头的固定句优先（按顺序播）
	var entry: Dictionary = _opener_entry(round_number)
	if not entry.is_empty():
		current_tier = int(entry.get("tier", 3))
		current_kind = _tier_kind(current_tier)
		_kind_run = 1
		_last_tier = current_tier
		_last_side = _tier_side(current_tier)
		_side_run = 1
		_last_kind = current_kind
	else:
		# 闪现触发后，接下来几句改成从"偷听到的"好句子池抽
		if _is_special_sentence():
			entry = _draw_overheard()
			if not entry.is_empty():
				current_tier = 5
				current_kind = "positive"
		if entry.is_empty() or not entry.has("text"):
			current_tier = _pick_next_tier()
			current_kind = _tier_kind(current_tier)
			entry = _draw_sentence(current_kind, current_tier)
			current_tier = int(entry.get("tier", current_tier))
	current_sentence = entry["text"]
	current_pinyin = PackedStringArray(entry["pinyin"])
	current_speaker = String(entry.get("speaker", ""))
	current_voice_len = String(entry.get("len", ""))
	current_target = current_sentence if input_mode == "hanzi" else " ".join(current_pinyin)
	last_sentence = current_sentence
	# 限时跟着句子长度走：7 秒 + 每字 1.5 秒，后半段再收紧 15%
	var base_limit := 7.0 + float(current_target.length()) * 1.5
	time_limit = base_limit if round_number <= 8 else base_limit * 0.85
	time_left = time_limit
	phrase_elapsed = 0.0
	phrase_mistakes = 0
	input_lock_left = 0.0
	voice_waiting = false
	_voice_wait_elapsed = 0.0
	has_started_typing = false
	error_flash = false
	error_flash_id += 1
	if cursor_tween and cursor_tween.is_running():
		cursor_tween.kill()
	cursor_rect.hide()
	input_box.text = ""
	_last_input_length = 0  # 换句/进剧情时同步重置击键计数
	input_box.editable = input_mode == "hanzi"
	# 第三阶段（面板已移到中央）不要输入框
	_apply_input_box_visibility()
	if input_mode == "hanzi":
		input_box.call_deferred("grab_focus")
	else:
		input_box.release_focus()
	state_label.text = message
	if round_number > 1:
		_show_feedback(message, Color("f7d292"))
	sentence_label.hide()
	hanzi_row.visible = input_mode == "hanzi"
	pinyin_row.visible = input_mode == "pinyin"
	if input_mode == "pinyin":
		_build_pinyin_cells()
	else:
		_build_hanzi_cells()
	_update_typing_progress("")
	call_deferred("_place_cursor_after_layout")
	if round_label != null and false:
		round_label.text = "第 %d / %d 句" % [round_number, MAX_ROUNDS]
	input_box.placeholder_text = "在这里输入汉字"
	_refresh_stats()
	if hud_layout != null:
		hud_layout.call_deferred("_apply_all")
	# 第三阶段对话框要保持移开。_apply_all 是 deferred 的，
	# 所以要更晚一步推（call_deferred 再嵌一层）。
	if _dialog_hidden_p3:
		call_deferred("_apply_dialog_hidden_instant")
	_play_sentence_voice()
	if phase == "playing":
		if curved_arc_defer > 0.0:
			var delay := curved_arc_defer
			curved_arc_defer = 0.0
			get_tree().create_timer(delay).timeout.connect(_spawn_current_sentence_arc)
		else:
			_spawn_curved_sentence(current_sentence, current_kind)
	# 第一句真正开始打字前，弹一次操作说明（只弹一次）
	if round_number == 1:
		_maybe_show_tutorial()


## 每个阶段 10 句的句子类型牌堆。
## 越往后负面句越多（压力感递增），但每阶段都保证有正面句，不至于一路挨骂。
## 当前句子池所属阶段（按句数判定，和阶段画面 / 剧情 / 同心圆保持一致）
func _sentence_phase() -> String:
	var idx := clampi((round_number - 1) / ROUNDS_PER_STAGE, 0, STAGE_COUNT - 1)
	match idx:
		0:
			return "phase1"
		1:
			return "phase2"
		_:
			return "phase3"


## 同步输入框的显隐。
## 汉字模式的输入框不能 visible=false —— 隐藏的 Control 无法持有焦点，
## 中文输入法收不到组字，表现就是"打不了字"。隐藏时只把 alpha 设 0。
func _apply_input_box_visibility() -> void:
	if input_box == null:
		return
	var want_show: bool = (input_mode == "hanzi") and (not _dialog_hidden_p3)
	if input_mode == "hanzi":
		input_box.visible = true
		input_box.modulate = Color(1.0, 1.0, 1.0, 1.0 if want_show else 0.0)
	else:
		input_box.visible = false
		input_box.modulate = Color(1.0, 1.0, 1.0, 1.0)


## 重置抽取状态（开局调用）
func _reset_draw_state() -> void:
	_used_texts.clear()
	_kind_run = 0
	_last_kind = ""
	_last_tier = 3
	_side_run = 0
	_last_side = 0


func _used_key(phase: String, kind: String) -> String:
	return phase + ":" + kind


## 档位 → 池名（1/2 坏，3 中，4/5 好）
func _tier_kind(tier: int) -> String:
	if tier <= 2:
		return "negative"
	if tier >= 4:
		return "positive"
	return "neutral"


## 档位 → 大方向（-1 坏 / 0 中 / +1 好），用于连续上限
func _tier_side(tier: int) -> int:
	if tier <= 2:
		return -1
	if tier >= 4:
		return 1
	return 0


## 某阶段某池里还没被抽过的句子；tier=0 表示不限档位
func _remaining_pool(phase: String, kind: String, tier: int = 0) -> Array:
	var all: Array = SentenceData.pool(phase, kind)
	if all.is_empty():
		return []
	var used: Array = _used_texts.get(_used_key(phase, kind), [])
	var out: Array = []
	for e in all:
		if used.has(String(e["text"])):
			continue
		if tier > 0 and int(e.get("tier", 3)) != tier:
			continue
		out.append(e)
	return out


## 选下一句的档位（1~5）。
##   · 中性权重最高，两端（1/5）最低
##   · 连续抽到同一侧时，另一侧权重提高、同侧压低
##   · 硬上限：坏侧最多连续 2 句，中性 / 好侧最多 4 句
func _pick_next_tier() -> int:
	var phase := _sentence_phase()
	var tiers: Array[int] = [1, 2, 3, 4, 5]
	var remain := {}
	var total_left := 0
	for t in tiers:
		var kind := _tier_kind(t)
		var n := _remaining_pool(phase, kind, t).size()
		if n == 0:
			# 该档抽完了 → 清空整个池的已用记录，允许重抽
			_used_texts.erase(_used_key(phase, kind))
			n = _remaining_pool(phase, kind, t).size()
			if n == 0:
				n = _remaining_pool(phase, kind, 0).size()
		remain[t] = n
		total_left += n
	if total_left <= 0:
		return 3

	var w := {}
	for t in tiers:
		w[t] = float(TIER_WEIGHT.get(t, 1.0))

	if _kind_run >= 1 and _last_tier > 0:
		var run_f := float(_kind_run)
		for t in tiers:
			if t == _last_tier:
				w[t] *= maxf(0.10, 1.0 - 0.35 * run_f)
			else:
				w[t] *= 1.0 + 0.50 * run_f

	# 硬上限：按『同侧』算（坏侧 2 句，中/好侧 4 句）
	var side_cap := 4
	if _last_side < 0:
		side_cap = 2
	elif _last_side == 0:
		side_cap = 4
	if _side_run >= side_cap:
		for t in tiers:
			if _tier_side(t) == _last_side:
				w[t] = 0.0

	var total := 0.0
	for t in tiers:
		if int(remain[t]) <= 0:
			w[t] = 0.0
		total += float(w[t])
	if total <= 0.0:
		for t in tiers:
			if int(remain[t]) > 0:
				return t
		return 3

	var roll := rng.randf() * total
	for t in tiers:
		roll -= float(w[t])
		if roll <= 0.0:
			return t
	return 3


## 取阶段开头的固定句（找不到就返回空字典，退回随机）
func _opener_entry(n: int) -> Dictionary:
	if not OPENERS.has(n):
		return {}
	var want: String = OPENERS[n]
	var phase := _sentence_phase()
	for k in ["neutral", "positive", "negative"]:
		for e in SentenceData.pool(phase, k):
			if String(e["text"]) == want:
				return e
	for k in ["neutral", "positive", "negative"]:
		for e in SentenceData.pool(phase, k):
			var t := String(e["text"])
			if t.contains(want) or want.contains(t):
				return e
	push_warning("Main: 固定开头句找不到 -> %s" % want)
	return {}


## 抽一句：抽过的不会再抽到。tier>0 时优先在该档内抽。
func _draw_sentence(kind: String, tier: int = 0) -> Dictionary:
	var phase := _sentence_phase()
	var options: Array = []
	if tier > 0:
		options = _remaining_pool(phase, kind, tier)
	if options.is_empty():
		options = _remaining_pool(phase, kind, 0)
	if options.is_empty():
		_used_texts.erase(_used_key(phase, kind))
		options = SentenceData.pool(phase, kind).duplicate()
	if options.is_empty():
		options = SentenceData.pool("phase1", kind).duplicate()
	if options.is_empty():
		return {}

	if options.size() > 1:
		var filtered: Array = []
		for e in options:
			if String(e["text"]) != last_sentence:
				filtered.append(e)
		if not filtered.is_empty():
			options = filtered

	var pick: Dictionary = options[rng.randi() % options.size()]
	var used: Array = _used_texts.get(_used_key(phase, kind), [])
	used.append(String(pick["text"]))
	_used_texts[_used_key(phase, kind)] = used

	var picked_tier := int(pick.get("tier", 3))
	if picked_tier == _last_tier:
		_kind_run += 1
	else:
		_kind_run = 1
		_last_tier = picked_tier
	var picked_side := _tier_side(picked_tier)
	if picked_side == _last_side:
		_side_run += 1
	else:
		_side_run = 1
		_last_side = picked_side
	_last_kind = _tier_kind(picked_tier)
	return pick


## 句子变长后按长度缩字号，保证整句在一行里放得下（原设计固定 34/25）。
## 汉字格字号。返回的是"每字格子"的基准尺寸，
## 真正的字号由对话框可用宽度和行数一起决定（见 _fit_hanzi_size）。
func _hanzi_font_size() -> int:
	return _fit_hanzi_size()


func _pinyin_font_size() -> int:
	return _fit_pinyin_size()


func _build_hanzi_cells() -> void:
	for child in hanzi_row.get_children():
		hanzi_row.remove_child(child)
		child.queue_free()
	character_targets.clear()
	var hanzi_size := _hanzi_font_size()
	for character in current_sentence:
		var letter := _make_label(character, hanzi_size, Color("fff3e8"))
		# 卡片式字格：等宽等高，字距靠 padding 控制而不是 separation
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.custom_minimum_size = Vector2(float(hanzi_size) * 1.06, float(hanzi_size) * 1.34)
		hanzi_row.add_child(letter)
		character_targets.append(letter)
	# FlowContainer 会自动换行，这里强制让它按可用宽度重排
	hanzi_row.queue_sort()
	_reveal_cells(hanzi_row.get_children())


func _build_pinyin_cells() -> void:
	for child in pinyin_row.get_children():
		pinyin_row.remove_child(child)
		child.queue_free()
	pinyin_cells.clear()
	character_targets.clear()
	var pinyin_size := _pinyin_font_size()
	for i in current_pinyin.size():
		var syllable: String = current_pinyin[i]
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		pinyin_row.add_child(cell)
		var letters := HBoxContainer.new()
		letters.add_theme_constant_override("separation", 0)
		letters.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_child(letters)
		var glyphs: Array[Label] = []
		for character in syllable:
			var letter := _make_label(character, pinyin_size, Color("f2e4d6"))
			letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			# 不再给固定最小宽度：让字形自己决定宽度，最紧凑
			letter.custom_minimum_size = Vector2(0.0, float(pinyin_size) * 1.30)
			letters.add_child(letter)
			glyphs.append(letter)
			character_targets.append(letter)
		# 注意：分隔点不再放进音节格（否则会把那一格撑宽，汉字就和拼音错位）
		# 它作为独立节点插在格与格之间，见下面的 _add_pinyin_separator
		var hanzi := _make_label(current_sentence.substr(i, 1), pinyin_size, Color("a9a4a9"))
		hanzi.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hanzi.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hanzi.custom_minimum_size = Vector2(0.0, float(pinyin_size) * 1.32)
		cell.add_child(hanzi)
		pinyin_cells.append({"letters": glyphs, "hanzi": hanzi})
		# 音节之间插一个小圆点（独立节点，不属于任何格）
		if i < current_pinyin.size() - 1:
			# 分隔点用小字号画：大字号下 "·" 的字形宽度会把整行撑宽
			var dot_size := maxi(8, int(float(pinyin_size) * 0.55))
			var sep := _make_label("·", dot_size, Color("a9a4a9"))
			sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sep.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			sep.custom_minimum_size = Vector2(float(pinyin_size) * 0.34, float(pinyin_size) * 1.30)
			pinyin_row.add_child(sep)
			character_targets.append(sep)
	_reveal_cells(pinyin_row.get_children())


## 让对话框里的字格一个接一个淡入（和画面上的飘字同时开始）
func _reveal_cells(cells: Array) -> void:
	if cells.is_empty():
		return
	if _cell_tween != null and _cell_tween.is_valid():
		_cell_tween.kill()
	# 让"逐字浮现"的总时长和画面飘字的淡入大致同步
	var n := maxi(cells.size(), 1)
	var dur := 0.45
	var step := clampf((SENTENCE_FADE_IN * 0.80 - dur) / float(n), 0.02, 0.12)
	_cell_tween = create_tween()
	_cell_tween.set_parallel(true)
	var i := 0
	for cell in cells:
		var c := cell as CanvasItem
		if c == null:
			continue
		c.modulate.a = 0.0
		_cell_tween.tween_property(c, "modulate:a", 1.0, dur).set_delay(step * float(i))
		i += 1


func _update_pinyin_progress(typed: String) -> void:
	var offset := 0
	for i in current_pinyin.size():
		var syllable: String = current_pinyin[i]
		var consumed := clampi(typed.length() - offset, 0, syllable.length())
		var letters: Array = pinyin_cells[i]["letters"]
		for j in letters.size():
			var letter: Label = letters[j]
			var position := offset + j
			var color := Color("f2e4d6")
			if position < typed.length():
				color = Color("78dbc2")
			elif position == typed.length() and error_flash:
				color = Color("ff777e")
			elif j == syllable.length():
				color = Color("a9a4a9")
			letter.add_theme_color_override("font_color", color)
		var hanzi: Label = pinyin_cells[i]["hanzi"]
		hanzi.add_theme_color_override("font_color", Color("f2e4d6") if consumed == syllable.length() else Color("a9a4a9"))
		offset += syllable.length() + 1


func _update_hanzi_progress(typed: String) -> void:
	for i in character_targets.size():
		var color := Color("fff3e8")
		if i < typed.length():
			color = Color("78dbc2")
		elif i == typed.length() and error_flash:
			color = Color("ff777e")
		character_targets[i].add_theme_color_override("font_color", color)


func _update_typing_progress(typed: String) -> void:
	if input_mode == "pinyin":
		_update_pinyin_progress(typed)
	else:
		_update_hanzi_progress(typed)
	_move_cursor(typed.length(), true)


func _layout_sentence() -> void:
	var row: Control = hanzi_row if input_mode == "hanzi" else pinyin_row
	if not row.visible:
		return
	var lane: Control = %SentenceLane
	# FlowContainer 需要明确宽度才能正确折行；折行后按实际高度撑开 lane，
	# 否则第二行会被后面的控件压住（看起来像"溢出"）
	# 宽度必须先定，否则 FlowContainer 会按"每行一个字"算高度，得出天文数字
	var available := lane.size.x
	if available <= 1.0:
		available = _dialog_inner_size().x
	row.size.x = available
	row.position = Vector2(0.0, 2.0)
	# 用「格子宽度」自己算行数，不依赖 get_combined_minimum_size（它此时不准）
	var row_h := _measure_flow_height(row, available)
	row.size.y = row_h
	lane.custom_minimum_size = Vector2(0.0, row_h + 6.0)
	# 第三阶段：字浮在照片上，内容居中（FlowContainer 默认左对齐）
	# 必须等 FlowContainer 排完再量，所以要 deferred
	if _sentence_phase() == "phase3" and _dialog_hidden_p3:
		call_deferred("_center_row_content", row, lane, available)


func _place_cursor_after_layout() -> void:
	if phase == "playing" or phase == "final":
		_layout_sentence()
		if has_started_typing:
			_move_cursor(input_box.text.length(), false)


func _move_cursor(index: int, animate: bool) -> void:
	if cursor_tween and cursor_tween.is_running():
		cursor_tween.kill()
	if not has_started_typing or index >= character_targets.size():
		cursor_rect.hide()
		return
	var target: Label = character_targets[index]
	if not target.is_visible_in_tree() or target.size.x <= 0.0:
		return
	var destination := target.global_position + Vector2(0.0, target.size.y - 3.0)
	var width := maxf(target.size.x, 10.0)
	if animate and cursor_rect.visible:
		cursor_tween = create_tween().set_trans(Tween.TRANS_LINEAR)
		cursor_tween.tween_property(cursor_rect, "global_position", destination, 0.1)
		cursor_rect.size = Vector2(width, 3.0)
	else:
		cursor_rect.global_position = destination
		cursor_rect.size = Vector2(width, 3.0)
	cursor_rect.show()


func _flash_error() -> void:
	error_flash = true
	has_started_typing = false
	error_flash_id += 1
	var flash_id := error_flash_id
	_update_typing_progress("")
	await get_tree().create_timer(0.35).timeout
	if flash_id == error_flash_id and phase == "playing":
		error_flash = false
		_update_typing_progress(input_box.text)


func _on_text_changed(value: String) -> void:
	if voice_waiting:
		# 语音播放期间不接受输入，把内容退回
		if input_box != null:
			input_box.text = ""
		return
	# ---- 终章：输错不重来，只退掉打错的那一位 ----
	if phase == "final":
		if input_lock_left > 0.0:
			return
		if not current_target.begins_with(value):
			if input_box != null and not value.is_empty():
				var trimmed := value.left(value.length() - 1)
				input_box.text = trimmed
				input_box.caret_column = trimmed.length()
				_last_input_length = trimmed.length()
			if sfx_player != null:
				sfx_player.play_mistake()
			return
		_play_typing_sfx(value)
		if not value.is_empty():
			has_started_typing = true
		_update_typing_progress(value)
		if value == current_target:
			_complete_final_sentence()
		return
	if phase != "playing":
		return
	if input_lock_left > 0.0:
		return
	if not current_target.begins_with(value):
		mistakes += 1
		phrase_mistakes += 1
		pressure = minf(MAX_VALUE, pressure + 8.0)
		input_box.text = ""
		_last_input_length = 0  # 清空后重打，第一个字也要有击键声
		input_box.caret_column = 0
		input_lock_left = ERROR_LOCK_SECONDS
		if input_mode == "hanzi":
			input_box.editable = false
		state_label.text = "输入错误：整句重打，停顿 0.75 秒，压力 +8"
		_show_feedback("输入错误 · 压力 +8", Color("ff777e"))
		_flash_error()
		# 误触只播 mistake 音；sentence_fail 留给"时间耗尽"
		if sfx_player != null:
			sfx_player.play_mistake()
		_update_bars()
		_refresh_stats()
		_check_loss()
		return
	error_flash = false
	# 空串也调用：内部会把 _last_input_length 归零（清空/重打时的关键）
	_play_typing_sfx(value)
	if not value.is_empty():
		has_started_typing = true
	_update_typing_progress(value)
	if value == current_target:
		_complete_sentence()


func _complete_sentence() -> void:
	if phase == "final":
		_complete_final_sentence()
		return
	var length := current_target.length()
	var speed := float(length) * 60.0 / maxf(phrase_elapsed, 0.5)
	correct_characters += length
	best_speed = maxf(best_speed, speed)
	var unique_characters := {}
	for character in current_target:
		unique_characters[character] = true
	# keybr: score = CPM × 不同字符数 ÷ (错误数 + 1) × (字符数 ÷ 50)。
	var typing_score := roundi(speed * float(unique_characters.size()) * float(length) / (50.0 * float(phrase_mistakes + 1)))
	var gained: int = int(BASE_SCORE[current_kind]) + typing_score
	score += gained
	var message := "接住了。+%d 分，速度 %.0f 字符/分" % [gained, speed]
	var affection_gain := _affection_from_performance(speed)
	affection = minf(MAX_VALUE, affection + affection_gain)
	# 压力按「五档」变化：坏句加压、好句减压
	var dp: float = float(TIER_PRESSURE.get(current_tier, 4.0))
	if dp >= 0.0:
		pressure = minf(MAX_VALUE, pressure + dp)
	else:
		pressure = maxf(0.0, pressure + dp)
	# 负面句才涌上泪水；坏2（tier1）最重，坏1（tier2）弱一些
	if current_tier == 1:
		_play_tears(1.0)
	elif current_tier == 2:
		_play_tears(0.55)
	_fade_out_curved_sentence()
	_update_bars()
	_save_records()
	_play_circle_result()
	_notify_phase3_first_done()
	_build_up_phase3_tears()
	if sfx_player != null:
		sfx_player.play_sentence_complete()
		sfx_player.play_accept(current_kind, pressure, MAX_VALUE)
	if _check_loss():
		return
	# 好感满：先打「终章 5 句」，打完才播结尾剧情 epilogue
	if affection >= MAX_VALUE and not _final_played:
		_spawn_curved_banner("你接住她们了", "positive", 3.2)
		if not _dialog_hidden_p3:
			sentence_label.text = "你接住她们了"
			sentence_label.show()
			state_label.text = "你接住她们了"
		_start_final_phase()
		return
	if _start_story_chain(message):
		return
	_advance_sentence(message)


## 负面句结算时叠一层泪水滤镜。强度跟压力挂钩：
## 压力越高，泪越重（25% ~ 100%）。
func _play_tears(scale: float = 1.0) -> void:
	if tears_fx == null:
		return
	var intensity := lerpf(0.55, 1.0, clampf(pressure / MAX_VALUE, 0.0, 1.0)) * scale
	tears_fx.play(intensity)


## 本句涨多少好感度。
##
## 【为什么按"剩余句数"算而不是按类型给固定值】
##   固定值 + 打字表现浮动会让阶段长度漂移 —— 打得快就 7 句进下一阶段，
##   打得慢就 13 句，剧情节奏完全不可控。
##   改成「本阶段还差多少好感 ÷ 本阶段还剩几句」之后，
##   无论快慢都大致是 10 句走完一个阶段，打字表现只做 ±25% 的微调。
func _affection_from_performance(speed: float) -> int:
	var start := _stage_start_value()
	var target := start + (MAX_VALUE / float(STAGE_COUNT))
	var sentences_left := maxi(1, ROUNDS_PER_STAGE - _stage_index_in_stage())
	var base := (target - affection) / float(sentences_left)
	if base <= 0.0:
		base = 1.0

	var reference: float = REFERENCE_CPM[input_mode]
	var skill := clampf(speed / maxf(reference, 1.0), 0.75, 1.25)
	var penalty := 1.0 / (1.0 + 0.25 * float(phrase_mistakes))
	# 档位加权：越好的句子涨得越多，越坏的越少
	var kind_bonus: float = float(TIER_AFFECTION_BONUS.get(current_tier, 1.0))
	var gain := base * skill * penalty * kind_bonus
	# 夹住单句涨幅，避免一次暴涨或几乎不涨
	gain = clampf(gain, base * 0.5, base * 1.8)
	return maxi(1, roundi(gain))


## 当前阶段序号（0 / 1 / 2）
func _stage_number() -> int:
	return clampi((round_number - 1) / ROUNDS_PER_STAGE, 0, STAGE_COUNT - 1)


## 本阶段内是第几句（0 开始）
func _stage_index_in_stage() -> int:
	return (round_number - 1) % ROUNDS_PER_STAGE


## 本阶段的好感度起点
func _stage_start_value() -> float:
	return MAX_VALUE * float(_stage_number()) / float(STAGE_COUNT)


## 本阶段的好感度目标值
func _stage_bonus() -> float:
	return MAX_VALUE * float(_stage_number() + 1) / float(STAGE_COUNT)


## 本阶段内的好感度进度 0~1
func _stage_progress() -> float:
	var start := _stage_start_value()
	var end := _stage_bonus()
	return clampf((affection - start) / maxf(end - start, 0.001), 0.0, 1.0)


func _check_loss() -> bool:
	if debug_invincible:
		return false
	if pressure >= MAX_VALUE:
		_game_over_text = "你崩溃了"
		_end_game(false)
		return true
	if numbness >= MAX_VALUE:
		_game_over_text = "你再也不会听见了"
		_end_game(false)
		return true
	return false


func _end_game(won: bool) -> void:
	phase = "won" if won else "lost"
	if circle_fx != null:
		circle_fx.hide_now()
	if tears_fx != null:
		tears_fx.hide_now()
	_end_resist()
	if voice_player != null:
		voice_player.stop_all()
	if bgm_player != null:
		bgm_player.stop()
	if sfx_player != null:
		sfx_player.stop_all()
	if ambient != null:
		ambient.stop_all()
	if stress_audio != null:
		stress_audio.stop_all()
	# 失败音必须在 stop_all() 之后播，否则会被立刻掐掉
	if not won and sfx_player != null:
		sfx_player.play_game_over()
	story_overlay.hide()
	pause_overlay.hide()
	feedback_label.hide()
	cursor_rect.hide()
	hanzi_row.hide()
	input_box.editable = false
	input_box.text = ""
	_last_input_length = 0  # 换句/进剧情时同步重置击键计数
	pinyin_row.hide()
	sentence_label.show()
	sentence_label.text = "你接住她们了" if won else (_game_over_text if _game_over_text != "" else "这场对话暂时结束了。")
	# 结算提示：顶部的 RoundLabel 已隐藏，所以把提示放在状态行
	state_label.visible = true
	if won:
		state_label.text = "胜利 · R 重玩   1 汉字   2 拼音   Esc 回主界面"
	else:
		state_label.text = "失败 · R 重玩   1 汉字   2 拼音   Esc 回主界面"
	_save_records()
	_refresh_stats()
	_spawn_curved_banner(sentence_label.text, "positive" if won else "cold", 7.0)


func _update_bars() -> void:
	affection_bar.value = affection
	pressure_bar.value = pressure
	numbness_bar.value = numbness


func _refresh_stats() -> void:
	var accuracy := 100.0
	if correct_characters + mistakes > 0:
		accuracy = 100.0 * float(correct_characters) / float(correct_characters + mistakes)
	var mode_name := "汉字" if input_mode == "hanzi" else "拼音"
	stats_label.text = "%s模式   分数 %d   准确率 %.0f%%   本模式最高分 %d   最快 %.0f 字符/分" % [mode_name, score, accuracy, best_score, best_speed]


func _load_records() -> void:
	if not FileAccess.file_exists("user://records.json"):
		return
	var file := FileAccess.open("user://records.json", FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	if data is Dictionary:
		if data.has("hanzi") and data.has("pinyin"):
			records = data
		else:
			records["hanzi"] = {"best_score": int(data.get("best_score", 0)), "best_speed": float(data.get("best_speed", 0.0))}
	best_score = int(records["hanzi"]["best_score"])
	best_speed = float(records["hanzi"]["best_speed"])


func _save_records() -> void:
	best_score = maxi(best_score, score)
	records[input_mode] = {"best_score": best_score, "best_speed": best_speed}
	var file := FileAccess.open("user://records.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(records))


func _show_feedback(message: String, color: Color) -> void:
	if feedback_tween and feedback_tween.is_running():
		feedback_tween.kill()
	# 第三阶段面板在屏幕中央，反馈文字要挪到面板下方，别压住内容
	if _dialog_hidden_p3:
		var panel: Control = %SentencePanel
		if panel != null:
			feedback_label.anchor_top = 0.0
			feedback_label.anchor_bottom = 0.0
			feedback_label.offset_top = panel.position.y + panel.size.y + 16.0
			feedback_label.offset_bottom = feedback_label.offset_top + 48.0
	else:
		var vp := get_viewport_rect().size
		feedback_label.anchor_top = 0.5
		feedback_label.anchor_bottom = 0.5
		feedback_label.offset_top = -24.0
		feedback_label.offset_bottom = 24.0
	feedback_label.text = message
	feedback_label.add_theme_color_override("font_color", color)
	feedback_label.modulate = Color.WHITE
	feedback_label.show()
	feedback_tween = create_tween()
	feedback_tween.tween_interval(1.25)
	feedback_tween.tween_property(feedback_label, "modulate:a", 0.0, 0.35)
	feedback_tween.tween_callback(feedback_label.hide)




# ============================================================ 弯曲文字特效
# 用的是 addons/text_fx 里可移植的 CurvedText / TextFX：
# 文字沿弧线逐字排版，然后按字错开、缓慢淡出。
# 换到别的项目时，把 addons/text_fx 整个目录复制过去就能用。

func _clear_curved_text() -> void:
	_curved_sentence_nodes.clear()
	if text_fx_root == null:
		return
	for child in text_fx_root.get_children():
		if not (child is CurvedText):
			continue
		# 正在淡出、且淡完会自己释放的节点：留着让它把淡出演完，
		# 否则换句时旧文字会"啪"地消失，看不到淡出过程。
		if child._anim_mode == CurvedText.PlayMode.FADE_OUT and child.free_when_done:
			continue
		child.queue_free()


func _curved_tone(tone: String) -> Dictionary:
	match tone:
		"positive":
			return {
				"color_start": Color("eafff6"),
				"color_end": Color("78dbc2"),
				"outline_color": Color(0.01, 0.06, 0.05, 0.62),
			}
		"negative":
			return {
				"color_start": Color("ffe6e8"),
				"color_end": Color("ff777e"),
				"outline_color": Color(0.08, 0.01, 0.02, 0.62),
			}
		"cold":
			return {
				"color_start": Color("ded9ea"),
				"color_end": Color("6f6a86"),
				"outline_color": Color(0.02, 0.02, 0.04, 0.62),
			}
		_:
			return {
				"color_start": Color("fff3e8"),
				"color_end": Color("f7d292"),
				"outline_color": Color(0.02, 0.02, 0.04, 0.62),
			}


## 出现一句新句子：直接淡入 + 微平移，**一直停在画面上**，
## 直到这句话打完（或超时）才淡出。
## 第一阶段用平直排版，第二/三阶段才弯成弧线。
func _spawn_curved_sentence(body: String, tone: String) -> void:
	if text_fx_root == null or body.is_empty():
		return
	# 第三阶段展开后：字显示在中央面板里（平直 + 拼音 + 输入反馈），
	# 不再额外画一层飘字，避免和照片/面板重叠。
	if _sentence_phase() == "phase3" and _dialog_hidden_p3:
		return
	_clear_curved_text()
	var settings := _curved_tone(tone)
	# 一二阶段飘字：统一用主界面「接住」的暖白纯色（不再走灰绿渐变）
	if _sentence_phase() != "phase3":
		settings["color_start"] = Color("f7f2e6")
		settings["color_end"] = Color("f7f2e6")
	var plan := _plan_curved_lines(body)
	var font_size: int = plan["font_size"]
	var lines: PackedStringArray = plan["lines"]
	settings["font_size"] = font_size
	settings["fade_duration"] = SENTENCE_FADE_IN
	# stagger = 0 → 整句话作为一个整体一起淡入（不是逐字）
	settings["fade_stagger"] = 0.0
	settings["fade_power"] = 1.0
	settings["free_when_done"] = false
	# 微平移：淡入时从下方滑到位（漂移量在淡入过程中线性收为 0）
	settings["fade_drift"] = Vector2(0.0, SENTENCE_FADE_DRIFT)
	settings["fade_glyph_drift"] = Vector2.ZERO
	settings["fade_shrink"] = 1.0
	var phase_name := _sentence_phase()
	if phase_name == "phase1" or phase_name == "phase3":
		# 第一阶段 + 第三阶段：平直，不弯
		settings["curve_mode"] = CurvedText.CurveShape.STRAIGHT
		settings["rotate_follow"] = 0.0
		settings["radius"] = 0.0
	else:
		settings["curve_mode"] = CurvedText.CurveShape.ARC
		settings["radius"] = 560.0
		settings["rotate_follow"] = 1.0
	var stage_size := _stage_size()
	var line_gap := float(font_size) * 1.42
	# 一二阶段的飘字往下靠（原来在画框 30%/34%，现在移到 60%/64%）
	var center_y := stage_size.y * (0.60 if lines.size() <= 1 else 0.64)
	# 第三阶段面板会移到屏幕中央，飘字上移避免重叠
	if _sentence_phase() == "phase3" and _dialog_hidden_p3:
		center_y = stage_size.y * 0.14
	for i in lines.size():
		var y := center_y + (float(i) - float(lines.size() - 1) * 0.5) * line_gap
		var anchor := Vector2(stage_size.x * 0.5, y)
		var node := TextFX.spawn(text_fx_root, lines[i], anchor, "reveal", settings)
		if node != null:
			_curved_sentence_nodes.append(node)


## 把当前飘在画面上的句子淡出（打完 / 超时 / 进剧情时调用）
func _fade_out_curved_sentence() -> void:
	var nodes := _curved_sentence_nodes.duplicate()
	_curved_sentence_nodes.clear()
	for node in nodes:
		if node == null or not is_instance_valid(node):
			continue
		node.free_when_done = true
		node.fade_out(SENTENCE_FADE_OUT, 0.0, 0.3)


## 延迟进场用的回调：仍处于对局中才把当前句子摆成弧线。
func _spawn_current_sentence_arc() -> void:
	if phase != "playing":
		return
	_spawn_curved_sentence(current_sentence, current_kind)


## 大字横幅：用在"挡开了 / 胜利 / 失败"这种节点，弯得更夸张、消失更慢。
func _spawn_curved_banner(body: String, tone: String, hold: float = 5.5) -> void:
	if text_fx_root == null or body.is_empty():
		return
	_clear_curved_text()
	var caption := body.trim_suffix("。").trim_suffix(".")
	var settings := _curved_tone(tone)
	settings["font_size"] = _fit_curved_font_size(caption, 62, 28)
	settings["radius"] = 900.0
	settings["fade_duration"] = hold
	settings["fade_stagger"] = 0.3
	settings["fade_drift"] = Vector2(0.0, -52.0)
	# 短句（3 字以内）把弧线收紧，不然看着像一条直线
	if caption.length() <= 3:
		settings["radius"] = 300.0
	var stage_size := _stage_size()
	TextFX.spawn(text_fx_root, caption, Vector2(stage_size.x * 0.5, stage_size.y * 0.26), "banner", settings)


# ============================================================ 剧情流程
# 触发顺序：开局 intro → 好感度 ≥1/3 mid1 → ≥2/3 mid2 → 好感度满 ending。
# 剧情期间 phase = "story"，游戏输入和计时全部暂停；演完自动回到游戏。

## 当前好感度下、该接着播的剧情段（按流程顺序，一次只返回一段）。
## 三段游戏各自的"结束标记"是 act1_end / act2_end / epilogue，
## 中间过场 intro 段的 act1_intro 与 act1_end 连着播。
func _next_story_id() -> String:
	# 注意：act1_intro（过渡文本一）**不在**这里按好感度触发 ——
	# 它在开局 prologue 之后立刻播完，然后才是第一段游戏。
	# 这里只留第一段游戏之后的 act1_end。
	if not story_seen.has(STORY_ACT1_END) and affection >= STORY_MID_1:
		return STORY_ACT1_END
	# 第二段游戏打完 → act2_end
	if not story_seen.has(STORY_ACT2_END) and affection >= STORY_MID_2:
		return STORY_ACT2_END
	# 第三段游戏打完 → epilogue
	if not story_seen.has(STORY_EPILOGUE) and affection >= MAX_VALUE:
		return STORY_EPILOGUE
	return ""


func _play_story(story_id: String) -> void:
	phase = "story"
	if circle_fx != null:
		circle_fx.hide_now()
	if tears_fx != null:
		tears_fx.hide_now()
	story_seen[story_id] = true
	input_box.editable = false
	input_box.release_focus()
	input_box.text = ""
	_last_input_length = 0  # 换句/进剧情时同步重置击键计数
	cursor_rect.hide()
	feedback_label.hide()
	pause_overlay.hide()
	state_label.text = "剧情"
	_end_resist()
	_set_tension(false)
	if voice_player != null:
		voice_player.stop_all()
	# 结尾剧情：把所有对局音效 / 环境音 / 心跳呼吸都停掉，只留 BGM
	if story_id == STORY_EPILOGUE:
		_ending_muted = true
		if ambient != null:
			ambient.stop_all()
		if stress_audio != null:
			stress_audio.stop_all()
		if sfx_player != null:
			sfx_player.stop_all()
	if sfx_player != null:
		# 只有"阶段满、要进剧情"时播好感音；开场 prologue 不算
		if story_id != STORY_PROLOGUE:
			sfx_player.play_stage_complete()
	_clear_curved_text()
	_sync_bgm_for_story(story_id)
	story_overlay.play(story_id)


## 剧情段自带的 BGM 写在 story_data.gd 的 "bgm" 字段里。
## act1_intro 是过场，沿用上一段的曲子（Dream Street），不切歌。
func _sync_bgm_for_story(story_id: String) -> void:
	if bgm_player == null:
		return
	# 终章已经接管 BGM（OUT of love），结尾剧情期间不切歌
	if _final_music_on:
		bgm_player.play(FINAL_BGM)
		return
	var segment := StoryData.segment(story_id)
	var bgm: String = segment.get("bgm", "")
	if bgm.is_empty():
		return
	bgm_player.play(bgm)


func _start_story_chain(message: String) -> bool:
	var next_story := _next_story_id()
	if next_story == "":
		return false
	pending_message = message
	# epilogue 是最后一段剧情，演完直接进结算（不再回对局）
	story_resume = "ending" if next_story == STORY_EPILOGUE else "advance"
	_play_story(next_story)
	return true


func _on_story_finished(_segment_id: String) -> void:
	story_overlay.hide()

	# 开场 prologue 演完 → 先接「过渡文本一」（act1_intro），
	# 播完才真正开始第一段游戏的输入。
	if story_resume == "start" and not story_seen.has(STORY_ACT1_INTRO):
		story_resume = "start"
		_play_story(STORY_ACT1_INTRO)
		return

	# 一次跨过多个阈值时，把该播的剧情连续播完
	# （epilogue 播完时 story_seen 已含 epilogue，_next_story_id 会返回空）
	if story_resume != "ending" and _start_story_chain(pending_message):
		return
	match story_resume:
		"start":
			phase = "playing"
			input_box.editable = input_mode == "hanzi"
			if input_mode == "hanzi":
				input_box.call_deferred("grab_focus")
			_advance_sentence("对话开始。")
			_sync_bgm_for_act()
		"advance":
			phase = "playing"
			input_box.editable = input_mode == "hanzi"
			if input_mode == "hanzi":
				input_box.call_deferred("grab_focus")
			_advance_sentence(pending_message)
			_sync_bgm_for_act()
		"ending":
			# 终章已打完、结尾剧情也演完 → 播 Ending 滚动字幕
			_play_ending_roll()
	story_resume = ""


# ============================================================ 语音
# 长度型（short/long/long_short/short_long）从 VoiceData 反查；
# 说话人：14 = 父亲（father），23 = 母亲（mother）。

## 对局中的 BGM：
##   第一段游戏（act1_intro 之后）        Dream Street
##   第二段游戏（act1_end 之后）          There's Something Outside
##   第三段游戏（act2_end 之后）          萍逢
func _sync_bgm_for_act() -> void:
	if phase == "menu":
		if bgm_player != null:
			bgm_player.play("res://audio/bgm/intro_circulation.mp3")
		return
	if bgm_player == null:
		return
	if story_seen.has(STORY_ACT2_END):
		bgm_player.play("res://audio/bgm/pengfeng.mp3")
	elif story_seen.has(STORY_ACT1_END):
		bgm_player.play("res://audio/bgm/something_outside.mp3")
	else:
		bgm_player.play("res://audio/bgm/dream_street.mp3")


func _sentence_speaker() -> String:
	# 优先用句子自带的 speaker 标签，没有才回退到按内容查表
	if current_speaker != "":
		return current_speaker
	return SpeakerData.speaker_of(current_sentence)


func _play_sentence_voice() -> void:
	if voice_player == null or current_sentence.is_empty():
		return
	var started: bool = false
	if current_voice_len != "":
		started = voice_player.play(current_voice_len, _sentence_speaker())
	else:
		started = voice_player.play_for_sentence(current_sentence, _sentence_speaker())
	# 语音开始播放 -> 锁住输入，等它播完再放开
	if started:
		voice_waiting = true
		_voice_wait_elapsed = 0.0
		if input_box != null:
			input_box.editable = false
		state_label.text = "正在听…"
	else:
		voice_waiting = false


# ============================================================ 音效
# 打字音按"新增字符数"补音；输入法整句上屏时不会只响一声。

var _last_input_length := 0
## 主界面（开始游戏 / 设置 / 离开）
var main_menu: Control = null
## 暂停菜单里是否开着设置浮层
var _pause_settings_open := false
## 暂停前处于哪个 phase（playing / final），恢复时要用
var _paused_from := "playing"
## 游戏内的操作说明浮层
var _tutorial_layer: Control = null
## Ending 画面（半透明黑底 + 白字上飘）
var _ending_layer: Control = null
var _ending_roll: Control = null
var _ending_tween: Tween = null
var _ending_content_h := 0.0
## 失败原因（显示在文本框里）
var _game_over_text := ""
## 当前飘在画面上的句子节点（长句会拆成多行，所以是数组）
var _curved_sentence_nodes: Array[Node2D] = []
## 对话框字格逐字浮现用的 tween
var _cell_tween: Tween = null
# ============================================================ 终章（好感满后）
## 好感度满、结局剧情演完之后进入。
## 这一段的规则和主流程完全独立：
##   · 压力 / 麻木 / 时间条全部隐藏，也不再变化
##   · 只从 sentence_data 的 "final" 池按顺序取句
##   · 输错不用整句重打，只退掉错的那一位
##   · 全部打完 → 游戏正式结束

func _start_final_phase() -> void:
	phase = "final"
	_final_played = true
	# 清掉上一句还没淡完的飘字，避免终章画面残留
	_clear_curved_text()
	_final_queue = SentenceData.pool("final", "positive").duplicate()
	_final_done = 0
	_set_final_hud(true)
	# 终章开始换成 OUT of love，并一直 loop 到 ED 播完
	_final_music_on = true
	if bgm_player != null:
		bgm_player.play(FINAL_BGM)
	# 数值全部冻结（显示也用不到）
	pressure = 0.0
	numbness = 0.0
	if ambient != null:
		ambient.stop_all()
	if stress_audio != null:
		stress_audio.stop_all()
	# 照片保持全屏、泪眼保持最重，情绪不断
	if phase3_gallery != null:
		if not phase3_gallery.is_active():
			phase3_gallery.set_active(true)
		if not phase3_gallery.is_expanded():
			phase3_gallery.expand_to_full()
	# 终章固定用「居中透明面板」的布局
	if not _dialog_hidden_p3:
		_promote_dialog_center(true)
	if p3_tears != null:
		p3_tears.set_level(1.0, 3.8, 2.2)
	# 终章配图从第一张开始
	_final_image_index = -1
	_advance_final_image()
	_advance_final_sentence("")


## 隐藏 / 恢复「压力、麻木、时间」三组 HUD
func _set_final_hud(hide_them: bool) -> void:
	for node in [time_bar, pressure_bar, numbness_bar,
			get_node_or_null("TimeCaption"),
			get_node_or_null("PressureCaption"),
			get_node_or_null("NumbnessCaption")]:
		if node != null:
			node.visible = not hide_them


## 终章换下一张配图（没有下一张就停在当前，不重复）
func _advance_final_image() -> void:
	if phase3_gallery == null or not phase3_gallery.has_method("show_image"):
		return
	var next_index := _final_image_index + 1
	if next_index >= FINAL_IMAGES.size():
		return   # 图片用完了，停在最后一张
	_final_image_index = next_index
	phase3_gallery.show_image(FINAL_IMAGES[next_index], 0.85)


func _advance_final_sentence(message: String) -> void:
	if _final_queue.is_empty():
		_end_game(true)
		return
	var entry: Dictionary = _final_queue.pop_front()
	_final_done += 1
	current_kind = "positive"
	current_sentence = String(entry["text"])
	current_pinyin = PackedStringArray(entry["pinyin"])
	current_speaker = String(entry.get("speaker", ""))
	current_voice_len = String(entry.get("len", ""))
	current_tier = int(entry.get("tier", 3))
	current_target = current_sentence if input_mode == "hanzi" else " ".join(current_pinyin)
	last_sentence = current_sentence
	# 不计时：给一个很大的值，UI 也已隐藏
	time_limit = 9999.0
	time_left = 9999.0
	phrase_elapsed = 0.0
	phrase_mistakes = 0
	input_lock_left = 0.0
	voice_waiting = false
	_voice_wait_elapsed = 0.0
	has_started_typing = false
	error_flash = false
	error_flash_id += 1
	if cursor_tween and cursor_tween.is_running():
		cursor_tween.kill()
	cursor_rect.hide()
	input_box.text = ""
	_last_input_length = 0
	input_box.editable = input_mode == "hanzi"
	_apply_input_box_visibility()
	if input_mode == "hanzi":
		input_box.call_deferred("grab_focus")
	else:
		input_box.release_focus()
	state_label.text = message
	state_label.visible = not _dialog_hidden_p3
	sentence_label.hide()
	hanzi_row.visible = input_mode == "hanzi"
	pinyin_row.visible = input_mode == "pinyin"
	if input_mode == "pinyin":
		_build_pinyin_cells()
	else:
		_build_hanzi_cells()
	_update_typing_progress("")
	call_deferred("_place_cursor_after_layout")
	_spawn_curved_sentence(current_sentence, "positive")


func _complete_final_sentence() -> void:
	_fade_out_curved_sentence()
	# 不加好感、不加压力、不加分 —— 和所有资源无关
	if sfx_player != null:
		sfx_player.play_sentence_complete()
	if _final_queue.is_empty():
		if _final_finishing:
			return
		_final_finishing = true
		state_label.text = "全部接住了"
		_show_feedback("全部接住了。", Color("fff2c8"))
		await get_tree().create_timer(1.1).timeout
		# 终章打完 → 播结尾剧情 epilogue，它演完才真正结束
		pending_message = ""
		story_resume = "ending"
		_play_story(STORY_EPILOGUE)
		return
	_show_feedback("接住了。", Color("f7d292"))
	_advance_final_image()
	_advance_final_sentence("")


## 第三阶段：每接受一句话，画面就往「泪眼模糊」推一档。
## 强度只增不减，模拟主角逐渐控制不住地流泪。
func _build_up_phase3_tears() -> void:
	if _story_stage() != 3 or not _dialog_hidden_p3:
		return
	if p3_tears == null:
		return
	_p3_tears_level = minf(P3_TEARS_MAX, _p3_tears_level + P3_TEARS_STEP)
	# 越往后越糊：blur 倍率随强度递增
	var blur_boost := lerpf(1.5, 3.8, _p3_tears_level)
	var drop_boost := lerpf(1.3, 2.6, _p3_tears_level)
	p3_tears.set_level(_p3_tears_level, blur_boost, drop_boost)


## 清掉第三阶段的泪水（重开 / 离开第三阶段时）
func _reset_phase3_tears() -> void:
	_p3_tears_level = 0.0
	if p3_tears != null:
		p3_tears.set_level(0.0)


## 第三阶段把对话框移开的 tween
var _dialog_swing_tween: Tween = null
## 对话框的原始 offset_top（用于复位）
var _dialog_home_rect := Rect2()
## 第三阶段是否已把对话框移开
var _dialog_hidden_p3 := false
## 第三阶段第一句的 round_number
var _phase3_first_round := -1
## 结尾剧情开始后：环境音 / 心跳呼吸全部静音
var _ending_muted := false
## 第三阶段当前泪水强度 0~1
var _p3_tears_level := 0.0
## 终章（好感满后的独立句子池）剩余句子
var _final_queue: Array = []
var _final_done := 0
## 终章配图当前显示到第几张
var _final_image_index := -1
## 终章 BGM 已接管（进 epilogue 也不换歌）
var _final_music_on := false
## 终章是否已经打过（决定 epilogue 的时机）
var _final_played := false
## 终章收尾是否已经开始（防重复触发）
var _final_finishing := false## 面板原始背景样式（移到中央时换透明）
var _dialog_home_style: StyleBox = null
## 父母合影闪现是否已触发过（一个阶段只触发一次）
var _parents_flash_fired := false
## 本阶段还要从 overheard 池抽几句（>0 表示正在用偷听句子）
## 特殊句的编排：本阶段每句是否为特殊句
var _special_plan: Array[bool] = []
## 本阶段第几句（0 开始）
var _special_index := 0
## 这一阶段用过的偷听句（避免重复）
var _overheard_used: Array[String] = []


func _play_typing_sfx(value: String) -> void:
	# 关键：无论内容是否为空，都必须同步"上一次长度"。
	# 否则打错 → 清空输入框 → 重新从第一个字开始打时，
	# 新增字数会算成负数，第一个字就没有击键声了。
	var current_len := value.length()
	var added := current_len - _last_input_length
	_last_input_length = current_len
	if sfx_player == null or added <= 0:
		return
	# 一次上屏多个字时，逐字补音（内部有节流，不会爆音）
	var times := mini(added, 6)
	for i in times:
		sfx_player.play_typing()


# ============================================================ 抵抗（Alt）
# 旧行为：按 Alt 直接跳过这句话、麻木 +22。
# 新行为：按住 Alt，这句话的倒计时以 8 倍速飞走，期间麻木条缓慢上涨；
#         松手立刻恢复正常速度。计时归零后按"超时"结算（压力 +20）。
#         这样抵抗仍然有用（快速脱身），但不再是无代价的跳过。

func _begin_resist() -> void:
	if phase != "playing" or resisting:
		return
	resisting = true
	resist_hold_left = RESIST_HOLD_TIME
	if sfx_player != null:
		sfx_player.start_resist()
	state_label.text = "正在抵抗… %.1f 秒" % RESIST_HOLD_TIME


func _end_resist() -> void:
	if not resisting:
		return
	resisting = false
	resist_hold_left = 0.0
	if sfx_player != null:
		sfx_player.stop_resist()
	if phase == "playing":
		state_label.text = "正在对话"


## 抵抗计时：按住满 2.5 秒就跳掉这句
func _tick_resist(delta: float) -> void:
	resist_hold_left = maxf(0.0, resist_hold_left - delta)
	state_label.text = "正在抵抗… %.1f 秒" % resist_hold_left
	if resist_hold_left <= 0.0:
		_finish_resist_sentence()


## 抵抗成功跳句：麻木固定 +，好感 -，压力不变
func _finish_resist_sentence() -> void:
	if not resisting:
		return
	_end_resist()
	numbness = minf(MAX_VALUE, numbness + RESIST_NUMBNESS)
	affection = maxf(0.0, affection - RESIST_AFFECTION_LOSS)
	_update_bars()
	_fade_out_curved_sentence()
	if sfx_player != null:
		sfx_player.play_sentence_fail()
	if _check_loss():
		return
	_advance_sentence("你避开了这句话。麻木 +%d，好感 -%d" % [int(RESIST_NUMBNESS), int(RESIST_AFFECTION_LOSS)])


# ============================================================ 紧张音
# 剩余时间低于 30% 时，循环播放"カタカタ震える"作为紧迫感；
# 超时、换句、进剧情、松手回血都会立刻关掉。

func _update_tension_audio() -> void:
	if time_limit <= 0.0:
		return
	var ratio := time_left / time_limit
	_set_tension(ratio <= TENSION_RATIO)


func _set_tension(on: bool) -> void:
	if sfx_player != null:
		sfx_player.set_tension(on)


## 画面窗口只有 664 宽，长句按字数缩字号，保证弧线文字不冲出画框。
func _fit_curved_font_size(body: String, base: int, minimum: int) -> int:
	var n := maxi(1, body.length())
	# 用画面窗口的**真实屏幕宽度**算（设计稿尺寸和屏幕尺寸不是一回事）
	var usable := _stage_size().x * 0.90
	var fit := int(usable / (1.05 * float(n)))
	return clampi(fit, minimum, base)


## 画面窗口（Stage）当前的像素尺寸
func _stage_size() -> Vector2:
	var stage_node := get_node_or_null("Stage") as Control
	if stage_node != null and stage_node.size.x > 1.0:
		return stage_node.size
	return Vector2(600.0, 460.0)


# ============================================================ 对话框内自适应排版
# 目标：整句永远完整落在黑底对话框内，允许自动换行，字距紧凑。

## 对话框内可用宽度（占对话框的比例，留出内边距和安全边）
const DIALOG_WIDTH_RATIO := 0.92
## 最多允许几行
const MAX_TEXT_LINES := 3


## 把 FlowContainer 里的内容水平居中（它本身不支持 alignment）
func _center_row_content(row: Control, lane: Control, available: float) -> void:
	var right := 0.0
	for child in row.get_children():
		var c := child as Control
		if c == null:
			continue
		right = maxf(right, c.position.x + c.size.x)
	if right <= 0.0 or right >= available - 2.0:
		row.position.x = 0.0
		return
	row.position.x = (available - right) * 0.5


## 对话框内容区的实际像素尺寸（考虑版式缩放与 Panel 内边距）
func _dialog_inner_size() -> Vector2:
	var panel: Control = %SentencePanel
	if panel == null or panel.size.x <= 1.0:
		return Vector2(804.0, 153.0)
	var pad := Vector2.ZERO
	var sb := panel.get_theme_stylebox("panel")
	if sb != null:
		pad = Vector2(sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT),
			sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM))
	return Vector2(panel.size.x - pad.x, panel.size.y - pad.y)


## 对话框里留给"字格区域"的高度：扣掉状态行、输入框、VBox 间距、Panel 内边距。
func _lane_available_height() -> float:
	var panel: Control = %SentencePanel
	if panel == null or panel.size.y <= 1.0:
		return 100.0
	var contents: Control = panel.get_node_or_null("Contents")
	var state: Control = %StateLabel
	var input: Control = %InputBox

	var pad := 0.0
	var sb := panel.get_theme_stylebox("panel")
	if sb != null:
		pad = sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM)

	var used := 0.0
	var visible_count := 0
	if state != null and state.visible:
		used += state.size.y
		visible_count += 1
	if input != null and input.visible:
		used += input.size.y
		visible_count += 1
	visible_count += 1     # 字格区域本身
	var sep := 10.0
	if contents != null:
		sep = float(contents.get_theme_constant("separation"))
	used += sep * float(maxi(0, visible_count - 1))
	# 留 6px 余量，避免贴着输入框
	return maxf(panel.size.y - pad - used - 6.0, 40.0)


## 用字体实际度量一段文字的宽度（比估算准）
func _measure_text_width(text: String, fs: int) -> float:
	var f := _game_font_resource()
	if f == null:
		return float(text.length()) * float(fs)
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


## 汉字格字号：宽高双约束，从大到小试。
func _fit_hanzi_size() -> int:
	var n := maxi(1, current_sentence.length())
	var avail_w := _dialog_inner_size().x * DIALOG_WIDTH_RATIO
	var avail_h := _lane_available_height()
	for fs in range(40, 15, -1):
		# 逐格贪心装箱（和 HFlowContainer 的真实行为一致）
		var x := 0.0
		var rows := 1
		for ch in current_sentence:
			var w := maxf(_measure_text_width(ch, fs), float(fs) * 0.9)
			if x > 0.0 and x + w > avail_w:
				rows += 1
				x = 0.0
			x += w
		var cell_h := 1.34 * float(fs)
		if float(rows) * cell_h + 2.0 * float(rows - 1) <= avail_h:
			return fs
	return 16


## 拼音格字号：同样的宽高双约束。
## 单格宽 = 音节文字宽 + 分隔点宽(0.42×字号)
## 单格高 = 拼音行(1.30×字号) + 汉字行(1.32×字号) + 间距
func _fit_pinyin_size() -> int:
	if current_pinyin.is_empty():
		return 20
	var avail_w := _dialog_inner_size().x * DIALOG_WIDTH_RATIO
	var avail_h := _lane_available_height()
	var h_sep := 2.0
	if pinyin_row != null:
		h_sep = float(pinyin_row.get_theme_constant("h_separation"))
	for fs in range(26, 9, -1):
		var x := 0.0
		var rows := 1
		for syllable in current_pinyin:
			# 音节格 + 分隔点 + FlowContainer 本身的横向间距
			var w := _measure_text_width(syllable, fs) + float(fs) * 0.34 + h_sep
			if x > 0.0 and x + w > avail_w:
				rows += 1
				x = 0.0
			x += w
		var cell_h := 2.75 * float(fs) + 2.0
		if float(rows) * cell_h + 2.0 * float(rows - 1) <= avail_h:
			return fs
	return 9


## 估算 FlowContainer 折行后的总高度：按子节点实际宽度累加，超过可用宽度就换行。
func _measure_flow_height(flow: Control, available: float) -> float:
	var x := 0.0
	var rows := 1
	var row_height := 0.0
	for child in flow.get_children():
		var c := child as Control
		if c == null or not c.visible:
			continue
		var w := maxf(c.size.x, c.get_combined_minimum_size().x)
		var h := maxf(c.size.y, c.get_combined_minimum_size().y)
		if x > 0.0 and x + w > available:
			rows += 1
			x = 0.0
		x += w
		row_height = maxf(row_height, h)
	return maxf(row_height * float(rows) + 2.0 * float(rows - 1), 8.0)


# ============================================================ 同心圆结算特效

## 当前阶段内的好感度进度（0~1）。注意是「阶段」而不是总好感度：
## 阶段1: 0 → 1/3，阶段2: 1/3 → 2/3，阶段3: 2/3 → 满
## 所以每进新阶段，内圆会重新从小开始长。
func _stage_affection_progress() -> float:
	var start := 0.0
	var end := STORY_MID_1
	if affection >= STORY_MID_2:
		start = STORY_MID_2
		end = MAX_VALUE
	elif affection >= STORY_MID_1:
		start = STORY_MID_1
		end = STORY_MID_2
	return clampf((affection - start) / maxf(end - start, 0.001), 0.0, 1.0)


## 每句结算后让同心圆浮现，内圆按当前阶段好感度缩放
func _play_circle_result() -> void:
	if circle_fx == null:
		return
	# 让特效拿到游戏用的中文字体（默认字体没有汉字）
	if circle_fx.has_method("set_font"):
		circle_fx.set_font(_game_font_resource())
	# 用「按阶段句数 + 阶段起点」算的进度，和画面/剧情判定一致；
	# 不再用按好感阈值切段的 _stage_affection_progress（两者会打架导致跳变）
	circle_fx.play(current_sentence, _stage_progress())


# ============================================================ 第一阶段画面动态
# 好感度从 0 涨到 1/3（阶段一结束）期间，画面越来越暗，
# 同时随机在相邻模糊度的图片之间切换，并带轻微摇晃。
# 阶段一结束后停在最暗，不再变化。

## 阶段一的进度 0~1（1 = 阶段一结束）
func _mood_progress() -> float:
	return clampf(affection / maxf(STORY_MID_1, 0.001), 0.0, 1.0)


func _update_mood_layer() -> void:
	# 只有真正在游玩/剧情里才显示（标题画面不显示）
	# paused 也算在对局里：否则暂停时 _update_mood_layer 会把画面层全关掉，
	# 终章按 Esc 再回来时三阶段照片被 set_active 重新初始化（重播入场交替）
	var in_game := phase in ["playing", "story", "won", "lost", "final", "paused"]
	# 终章沿用第三阶段的画面（全屏照片 + 居中面板）
	var stage := 3 if (phase == "final" or (phase == "paused" and _paused_from == "final")) else _story_stage()
	var want_mood1 := in_game and stage <= 1
	# 第三阶段第一句仍保留二阶段房间画面，
	# 等打完第一句（画廊展开）才切走，这样第一句和之前完全一样。
	var gallery_expanded: bool = phase3_gallery != null and phase3_gallery.is_expanded()
	var want_room2 := in_game and (stage == 2 or (stage >= 3 and not gallery_expanded))
	var want_gallery3 := in_game and stage >= 3

	if mood_layer != null:
		if mood_layer.is_active() != want_mood1:
			mood_layer.set_active(want_mood1)
		if want_mood1:
			mood_layer.set_progress(_mood_progress())

	if phase2_room != null:
		if phase2_room.is_active() != want_room2:
			phase2_room.set_active(want_room2)
		if want_room2:
			phase2_room.set_progress(_stage2_progress())

	_update_parents_flash(in_game)

	if phase3_gallery != null:
		if phase3_gallery.is_active() != want_gallery3:
			phase3_gallery.set_active(want_gallery3)
			# 进入 / 离开第三阶段时，对话框跟着移开 / 移回
			if want_gallery3:
				pass   # 移开动作在第一句打完后由 _notify_phase3_first_done 触发
			else:
				_promote_dialog_center(false)
				_reset_phase3_tears()
		if want_gallery3:
			phase3_gallery.set_progress(_stage3_progress())

	# 二阶段有真实立绘了，占位的「……」就不用了
	var presence := get_node_or_null("Stage/Clip/BossArea/Presence") as Control
	if presence != null:
		presence.visible = not want_room2


## 当前处在剧情的第几阶段（1/2/3），按好感度阈值分
func _story_stage() -> int:
	if affection >= STORY_MID_2:
		return 3
	if affection >= STORY_MID_1:
		return 2
	return 1


## 阶段二进度 0~1（好感度 1/3 → 2/3）
func _stage2_progress() -> float:
	var span := maxf(STORY_MID_2 - STORY_MID_1, 0.001)
	return clampf((affection - STORY_MID_1) / span, 0.0, 1.0)


## 把一句长句拆成 1~2 行，并选一个能放下的字号。
## 单行放得下就用单行；放不下就按可用宽度平均拆两行，尽量避免把词拆断。
func _plan_curved_lines(body: String) -> Dictionary:
	var stage_size := _stage_size()
	var usable := stage_size.x * 0.90
	var n := maxi(1, body.length())
	var font_size := 54
	# 从大字号往下试，找到"能塞进 2 行"的最大字号
	for fs in range(54, 17, -1):
		var capacity := maxi(1, int(usable / (1.02 * float(fs))))
		var lines_needed := int(ceil(float(n) / float(capacity)))
		if lines_needed <= 2:
			font_size = fs
			break
		font_size = fs
	var capacity := maxi(1, int(usable / (1.02 * float(font_size))))
	if n <= capacity:
		return {"font_size": font_size, "lines": PackedStringArray([body])}
	# 需要两行：优先在标点处断开，其次取中间
	var half := int(ceil(float(n) * 0.5))
	var break_at := _find_break_point(body, half, capacity)
	var first := body.substr(0, break_at)
	var second := body.substr(break_at)
	return {"font_size": font_size, "lines": PackedStringArray([first, second])}


## 在 mid 附近找一个合适的断句点（标点优先，否则就 mid）
func _find_break_point(body: String, mid: int, capacity: int) -> int:
	var puncts := "，。、！？；：,.!?;: "
	var lo := maxi(1, mid - 6)
	var hi := mini(body.length() - 1, mid + 6)
	for d in range(0, 7):
		for idx in [mid - d, mid + d]:
			if idx <= lo - 1 or idx >= hi + 1:
				continue
			if idx < 1 or idx >= body.length():
				continue
			var ch := body.substr(idx - 1, 1)
			if puncts.contains(ch):
				return idx
	# 没标点就按容量切（保证每行都不超宽）
	var cap := maxi(1, mini(capacity, body.length() - 1))
	if mid > cap:
		return cap
	return maxi(1, mid)


# ============================================================ 父母合影闪现

## 第二阶段进度到 70% 时，那张父母合影开始在背景里闪。
## 目的不是让人看清，而是让人**注意到有这件事出现了**，
## 所以透明度压到 0.30、亮度压到 0.55，只做一闪一闪的替换。
func _update_parents_flash(in_game: bool) -> void:
	if parents_flash == null:
		return

	# 第二阶段、且进度到阈值之后才启用这套「特殊句」机制
	var enabled := in_game and _story_stage() == 2 and _stage2_progress() >= PARENTS_FLASH_AT

	if enabled and not _parents_flash_fired:
		_parents_flash_fired = true
		_overheard_used.clear()
		_build_special_plan()
		print("[剧情] 特殊句编排生效：", _special_plan)
	elif not enabled and _parents_flash_fired:
		_parents_flash_fired = false
		_special_plan.clear()
		parents_flash.end_show()

	# 父母合影只在「特殊句」期间淡入，普通句淡出
	var want_show := enabled and _is_special_sentence()
	if want_show:
		parents_flash.begin_show()
	else:
		parents_flash.end_show()


## 本阶段特殊句编排规则：
##   · 以「1 句特殊 → 1 句普通 → 2 句特殊」为一个循环
##   · 阶段内**最后一句一定是特殊句**
##   · 只有特殊句会触发父母合影浮现
func _build_special_plan() -> void:
	var total := ROUNDS_PER_STAGE
	_special_plan.clear()
	_special_plan.resize(total)
	# 编排节奏：特 → 普 → 特 → 特 → 普 → 特 → 特 → 普 ...
	# 也就是「1句特殊 → 1句普通 → 2句特殊」循环，
	# 让每轮结尾的特殊和下一轮开头的普通错开，避免连着一长串都是特殊。
	var i := 0
	while i < total:
		_special_plan[i] = true          # 1 句特殊
		i += 1
		if i >= total:
			break
		_special_plan[i] = false         # 1 句普通
		i += 1
		if i >= total:
			break
		_special_plan[i] = true          # 2 句特殊
		i += 1
		if i >= total:
			break
		_special_plan[i] = true
		i += 1
		# 下一轮先来一句普通（避免连续特殊）
		if i < total:
			_special_plan[i] = false
			i += 1
	# 最后一句强制特殊（临近尾声一定触发浮现）
	_special_plan[total - 1] = true
	# 最后两句也保证至少有一句特殊，让收尾更有仪式感
	if total >= 2 and not _special_plan[total - 2]:
		_special_plan[total - 2] = true


## 当前这句是不是特殊句
func _is_special_sentence() -> bool:
	if _special_plan.is_empty():
		return false
	var idx := _stage_index_in_stage()
	if idx < 0 or idx >= _special_plan.size():
		return false
	return _special_plan[idx]


## 从 overheard 好句子池拿一句（用完就减一）
func _draw_overheard() -> Dictionary:
	var bag: Array = SentenceData.pool("overheard", "positive")
	if bag.is_empty():
		return {}
	# 过滤掉这一阶段已经用过的
	var fresh: Array = []
	for item in bag:
		if not _overheard_used.has(String(item["text"])):
			fresh.append(item)
	if fresh.is_empty():
		_overheard_used.clear()
		fresh = bag.duplicate()
	var pick: Dictionary = fresh[randi() % fresh.size()]
	_overheard_used.append(String(pick["text"]))
	return pick


## 阶段三进度 0~1（好感度 2/3 → 满）
func _stage3_progress() -> float:
	var span := maxf(MAX_VALUE - STORY_MID_2, 0.001)
	return clampf((affection - STORY_MID_2) / span, 0.0, 1.0)


# ============================================================ 环境音
# 第一阶段：切菜声（压力驱动）+ 全程耳鸣（麻木驱动）

func _update_ambient() -> void:
	if ambient == null:
		return
	var in_game := phase in ["playing", "story", "won", "lost", "final"]
	# 结尾剧情开始后，环境音彻底停掉（包括胜利结算画面）
	if _ending_muted:
		in_game = false
	ambient.update_state(_story_stage(), pressure, numbness, in_game)


## 心跳 + 呼吸：只由压力驱动
func _update_stress_audio() -> void:
	if stress_audio == null:
		return
	var in_game := phase in ["playing", "story", "won", "lost", "final"]
	if _ending_muted:
		in_game = false
	stress_audio.update_state(pressure, in_game)


## 跳过语音等待（测试 / 开发者快捷键用）。
## 正常游玩时语音播完会自动解锁；这里提供手动解锁，便于自动化测试和快速调试。
func skip_voice_wait() -> void:
	voice_waiting = false
	_voice_wait_elapsed = 0.0
	if input_lock_left <= 0.0 and input_box != null:
		if input_mode == "hanzi":
			input_box.editable = true
			input_box.call_deferred("grab_focus")
		state_label.text = "可以开始输入"


## 第三阶段第一句打完之后：把中心小框拉开成全屏，并让对话框向下移开
func _notify_phase3_first_done() -> void:
	if _story_stage() != 3:
		return
	if phase3_gallery == null or phase3_gallery.is_expanded():
		return   # 已经切换过了，不重复触发
	# 必须正好是第三阶段第 1 句打完才切换。
	# 否则第二阶段最后一句把好感推过阈值时 stage 已是 3，会提前触发。
	if _phase3_first_round < 0 or round_number != _phase3_first_round:
		return
	# 1) 照片拉开成全屏
	phase3_gallery.expand_to_full()
	# 2) 把对话框（输入区）移到屏幕中央并放大
	_promote_dialog_center(true)


## 第三阶段切换后的布局：
##   把 SentencePanel 从「底部横条」变成「屏幕中央的大面板」
##   —— 汉字格 / 拼音格 / 输入框都在里面，平直显示，带输入反馈
func _promote_dialog_center(promote: bool) -> void:
	var panel: Control = %SentencePanel
	if panel == null:
		return
	if _dialog_swing_tween != null and _dialog_swing_tween.is_valid():
		_dialog_swing_tween.kill()

	# 记录原始坐标 / 背景样式（第一次切换时保存）
	if _dialog_home_rect.size.x <= 0.0:
		_dialog_home_rect = Rect2(
			panel.offset_left, panel.offset_top,
			panel.offset_right - panel.offset_left,
			panel.offset_bottom - panel.offset_top)
	if _dialog_home_style == null:
		_dialog_home_style = panel.get_theme_stylebox("panel")

	# 第三阶段把黑底面板换成完全透明的样式，字直接浮在照片上
	if promote:
		panel.add_theme_stylebox_override("panel", _make_transparent_panel_style())
		_apply_input_box_visibility()
		if state_label != null:
			state_label.visible = false
	elif _dialog_home_style != null:
		panel.add_theme_stylebox_override("panel", _dialog_home_style)
		if state_label != null:
			state_label.visible = true

	_dialog_hidden_p3 = promote

	var vp := get_viewport_rect().size
	var target: Rect2
	if promote:
		# 屏幕中央：宽度占 78%，高度按内容算（不要固定大块空白）
		var w := vp.x * 0.78
		var h := panel.get_combined_minimum_size().y + 24.0
		h = clampf(h, _dialog_home_rect.size.y * 1.15, vp.y * 0.55)
		target = Rect2(Vector2((vp.x - w) * 0.5, (vp.y - h) * 0.5), Vector2(w, h))
	else:
		target = _dialog_home_rect
		_apply_input_box_visibility()

	_dialog_swing_tween = create_tween()
	_dialog_swing_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	_dialog_swing_tween.set_parallel(true)
	_dialog_swing_tween.tween_property(panel, "offset_left", target.position.x, 1.1)
	_dialog_swing_tween.tween_property(panel, "offset_top", target.position.y, 1.1)
	_dialog_swing_tween.tween_property(panel, "offset_right", target.position.x + target.size.x, 1.1)
	_dialog_swing_tween.tween_property(panel, "offset_bottom", target.position.y + target.size.y, 1.1)
	# 宽度变了 → 字格必须按新宽度重排
	_dialog_swing_tween.chain().tween_callback(_rebuild_cells_for_width)
	# 第三阶段不要输入框：输入靠字格反馈
	_apply_input_box_visibility()


## 面板尺寸变化后，按新宽度重建字格（字号/折行都会变）
func _rebuild_cells_for_width() -> void:
	if phase != "playing":
		return
	if input_mode == "pinyin":
		_build_pinyin_cells()
	else:
		_build_hanzi_cells()
	_layout_sentence()
	_update_typing_progress(input_box.text if input_box != null else "")
	_apply_p3_text_outline()
	# 隐藏输入框后，面板高度要贴合内容（否则下方留一片空白）
	if _dialog_hidden_p3:
		call_deferred("_refit_panel_height_soon")


## 第三阶段用的「几乎透明」面板样式：只留一点点暗底保证文字可读，
## 没有边框、没有圆角、没有可见的框。
func _make_transparent_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.0)   # 完全透明，靠字描边保证可读
	sb.border_width_left = 0
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_right = 0
	sb.corner_radius_bottom_left = 0
	# 保留内边距，避免字贴边
	var home_margin := 26.0
	sb.content_margin_left = home_margin
	sb.content_margin_right = home_margin
	sb.content_margin_top = 18.0
	sb.content_margin_bottom = 16.0
	return sb


## 第三阶段的字是直接浮在照片上的，给字格加描边保证可读
func _apply_p3_text_outline() -> void:
	if not _dialog_hidden_p3:
		return
	var dark := Color(0.0, 0.0, 0.0, 0.72)
	for row in [hanzi_row, pinyin_row]:
		if row == null:
			continue
		_apply_outline_recursive(row, dark)


func _apply_outline_recursive(node: Node, color: Color) -> void:
	for child in node.get_children():
		var label := child as Label
		if label != null:
			label.add_theme_constant_override("outline_size", 5)
			label.add_theme_color_override("font_outline_color", color)
		_apply_outline_recursive(child, color)


## 瞬时把对话框设到「中央」状态（换句复位后立即推回去）
func _apply_dialog_hidden_instant() -> void:
	var panel: Control = %SentencePanel
	if panel == null or _dialog_home_rect.size.x <= 0.0:
		return
	if not _dialog_hidden_p3:
		return
	if _dialog_swing_tween != null and _dialog_swing_tween.is_valid():
		_dialog_swing_tween.kill()
	var vp := get_viewport_rect().size
	var w := vp.x * 0.78
	var h := panel.get_combined_minimum_size().y + 24.0
	h = clampf(h, _dialog_home_rect.size.y * 1.15, vp.y * 0.55)
	var px := (vp.x - w) * 0.5
	var py := (vp.y - h) * 0.5
	panel.offset_left = px
	panel.offset_top = py
	panel.offset_right = px + w
	panel.offset_bottom = py + h
	# 宽度变了 → 字格按新宽度重排
	call_deferred("_rebuild_cells_for_width")


## 面板高度贴合内容（第三阶段隐藏输入框后用）
func _fit_panel_height_to_content() -> void:
	if not _dialog_hidden_p3:
		return
	var panel: Control = %SentencePanel
	if panel == null:
		return
	_apply_input_box_visibility()   # 不参与测量

	# 用内容实际高度度量（get_combined_minimum_size 在刚重建字格时可能还没刷新）
	var need: float = _measure_panel_content_height(panel)
	var cur: float = panel.offset_bottom - panel.offset_top
	var vp := get_viewport_rect().size
	var new_h: float = clampf(need, 100.0, vp.y * 0.62)
	if absf(new_h - cur) < 4.0:
		return
	var cy: float = (panel.offset_top + panel.offset_bottom) * 0.5
	panel.offset_top = cy - new_h * 0.5
	panel.offset_bottom = cy + new_h * 0.5


## 量面板内容的真实高度：状态行(隐藏时0) + 句子行 + lane + 内边距
func _measure_panel_content_height(panel: Control) -> float:
	var contents := panel.get_node_or_null("Contents") as Control
	if contents == null:
		return panel.get_combined_minimum_size().y + 8.0
	var total := 0.0
	var sep := 10.0
	var first := true
	for child in contents.get_children():
		var c := child as Control
		if c == null or not c.visible:
			continue
		if c is Label or c is RichTextLabel or c is HFlowContainer or c is Control:
			var h := c.size.y
			if h <= 0.0:
				h = c.get_combined_minimum_size().y
			total += h
			if not first:
				total += sep
			first = false
	# 加上面板内边距
	var sb := panel.get_theme_stylebox("panel")
	if sb != null:
		total += sb.content_margin_top + sb.content_margin_bottom
	return total + 6.0


## 延迟再校一次（字格刚重建时高度还没算准）
func _refit_panel_height_soon() -> void:
	get_tree().create_timer(0.10).timeout.connect(_refit_flow_geometry)
	get_tree().create_timer(0.40).timeout.connect(_refit_flow_geometry)


## 按字格的真实边界修正 lane / row 高度，然后重算面板高度。
##
## FlowContainer 的高度依赖当前可用宽度，而它自己的
## get_combined_minimum_size() 在宽度定下来之前是错的。
## 分两步：先给足高度让它把行排完，下一帧再量真实底边收回。
func _refit_flow_geometry() -> void:
	if not _dialog_hidden_p3 or phase != "playing":
		return
	var row: Control = hanzi_row if input_mode == "hanzi" else pinyin_row
	if row == null or not row.visible:
		return
	var lane: Control = %SentenceLane

	# 第一步：撑开，让所有行都排出来（不被裁剪）
	var wide: float = 900.0
	row.size.y = wide
	lane.custom_minimum_size = Vector2(0.0, wide + 6.0)
	await get_tree().process_frame
	await get_tree().process_frame

	# 第二步：量真实底边，收回合适高度
	var bottom := 0.0
	for child in row.get_children():
		var c := child as Control
		if c == null or not c.visible:
			continue
		bottom = maxf(bottom, c.position.y + c.size.y)
	if bottom <= 1.0:
		return
	row.size.y = bottom + 2.0
	lane.custom_minimum_size = Vector2(0.0, bottom + 6.0)
	await get_tree().process_frame
	_fit_panel_height_to_content()
	# 居中要在最终高度定下来之后再做
	call_deferred("_center_row_content", row, lane, lane.size.x)
