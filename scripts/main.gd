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
var input_mode := "hanzi"
var records := {
	"hanzi": {"best_score": 0, "best_speed": 0.0},
	"pinyin": {"best_score": 0, "best_speed": 0.0}
}
var rng := RandomNumberGenerator.new()
var kind_deck: Array[String] = []
var sentence_bags := {}

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

# ---- 剧情流程 ----
# 五段剧情的统一叫法与 BGM 对应：
#   prologue   回家路上→进门→睡着        Circulation
#   act1_intro 梦中醒来（变小、被声音淹没） Dream Street
#   act1_end   第一段游戏后的剧情         There's Something Outside
#   act2_end   第二段游戏后的剧情         萍逢
#   epilogue   第三段→结局                萍逢
# 触发点：开局 prologue；第一段游戏结束 act1_intro→act1_end；
#         第二段游戏结束 act2_end；第三段游戏结束 epilogue。
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
## 抵抗时计时推进的倍率（正常 1 秒 = 抵抗时 8 秒）
const RESIST_TIME_SCALE := 8.0
## 抵抗时累计多久算"浪费"一点压力（秒，真实时间）
const RESIST_PRESSURE_TICK := 0.45
## 每次 tick 增加的压力
const RESIST_PRESSURE_PER_TICK := 3.0
var resisting := false

# 开发者模式：免死（压力/麻木不会导致失败）
var debug_invincible := false

# ---- 紧张音：剩余时间少于某个比例时循环播放 ----
## 剩余时间 / 总时间 低于这个比例就进"紧张状态"
const TENSION_RATIO := 0.3


func _ready() -> void:
	rng.randomize()
	_apply_font_to_static_labels()
	_load_records()
	input_box.text_changed.connect(_on_text_changed)
	story_overlay.finished.connect(_on_story_finished)
	_show_title()
	if bgm_player != null:
		bgm_player.play("res://audio/bgm/intro_circulation.mp3")


func _process(delta: float) -> void:
	_update_mood_layer()
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
		# 抵抗：把这句的计时器快速推到终点，而不是直接判定跳过
		_tick_resist(delta)
		time_left = maxf(0.0, time_left - delta * RESIST_TIME_SCALE)
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
	if phase == "story":
		return
	if key.keycode == KEY_ESCAPE:
		if phase == "playing":
			phase = "paused"
			input_box.editable = false
			state_label.text = "已暂停 · 按 Esc 继续"
			pause_overlay.show()
			accept_event()
		elif phase == "paused":
			phase = "playing"
			pause_overlay.hide()
			input_box.editable = input_mode == "hanzi" and input_lock_left <= 0.0 and not voice_waiting
			state_label.text = "正在对话"
			if input_box.editable:
				input_box.call_deferred("grab_focus")
			accept_event()
		return
	if phase == "title" and (key.keycode == KEY_1 or key.keycode == KEY_2):
		_start_game("hanzi" if key.keycode == KEY_1 else "pinyin")
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
	elif phase == "playing" and input_mode == "pinyin":
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
	_build_kind_deck()
	sentence_bags.clear()
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
	current_kind = kind_deck[round_number - 1]
	# 闪现触发后，接下来几句改成从"偷听到的"好句子池抽
	var entry: Dictionary
	if _is_special_sentence():
		entry = _draw_overheard()
		if not entry.is_empty():
			current_kind = "positive"
	if entry.is_empty() or not entry.has("text"):
		entry = _draw_sentence(current_kind)
	current_sentence = entry["text"]
	current_pinyin = PackedStringArray(entry["pinyin"])
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
	input_box.visible = input_mode == "hanzi" and not _dialog_hidden_p3
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


## 每个阶段 10 句的句子类型牌堆。
## 越往后负面句越多（压力感递增），但每阶段都保证有正面句，不至于一路挨骂。
func _build_kind_deck() -> void:
	var stage1: Array[String] = ["neutral", "neutral", "neutral", "neutral", "neutral", "neutral", "positive", "positive", "negative", "negative"]
	var stage2: Array[String] = ["neutral", "neutral", "neutral", "neutral", "neutral", "positive", "positive", "negative", "negative", "negative"]
	var stage3: Array[String] = ["neutral", "neutral", "neutral", "neutral", "positive", "positive", "negative", "negative", "negative", "negative"]
	_shuffle(stage1)
	_shuffle(stage2)
	_shuffle(stage3)
	kind_deck = stage1
	kind_deck.append_array(stage2)
	kind_deck.append_array(stage3)


func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var other := rng.randi_range(0, i)
		var saved = items[i]
		items[i] = items[other]
		items[other] = saved


func _sentence_phase() -> String:
	if affection >= STORY_MID_2:
		return "phase3"
	if affection >= STORY_MID_1:
		return "phase2"
	return "phase1"


func _draw_sentence(kind: String) -> Dictionary:
	var phase := _sentence_phase()
	var bag_key := phase + ":" + kind
	if not sentence_bags.has(bag_key) or sentence_bags[bag_key].is_empty():
		var bag: Array = SentenceData.pool(phase, kind).duplicate()
		if bag.is_empty():
			bag = SentenceData.pool("phase1", kind).duplicate()
		_shuffle(bag)
		sentence_bags[bag_key] = bag
	var options: Array = sentence_bags[bag_key]
	if options.size() > 1 and options.back()["text"] == last_sentence:
		var first = options.pop_front()
		options.push_back(first)
	return options.pop_back()


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


func _place_cursor_after_layout() -> void:
	if phase == "playing":
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
	match current_kind:
		"neutral":
			affection = minf(MAX_VALUE, affection + affection_gain)
			pressure = minf(MAX_VALUE, pressure + 5.0)
		"positive":
			affection = minf(MAX_VALUE, affection + affection_gain)
			pressure = maxf(0.0, pressure - 12.0)
		"negative":
			affection = minf(MAX_VALUE, affection + affection_gain)
			pressure = minf(MAX_VALUE, pressure + 18.0)
			# 负面句：眼前涌上泪水
			_play_tears()
	_fade_out_curved_sentence()
	_update_bars()
	_save_records()
	_play_circle_result()
	_notify_phase3_first_done()
	if sfx_player != null:
		sfx_player.play_sentence_complete()
		sfx_player.play_accept(current_kind, pressure, MAX_VALUE)
	if _check_loss():
		return
	if _start_story_chain(message):
		return
	_advance_sentence(message)


## 负面句结算时叠一层泪水滤镜。强度跟压力挂钩：
## 压力越高，泪越重（25% ~ 100%）。
func _play_tears() -> void:
	if tears_fx == null:
		return
	var intensity := lerpf(0.55, 1.0, clampf(pressure / MAX_VALUE, 0.0, 1.0))
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
	# 句子类型只做轻微加权：负面句稍微更"伤"，正面句稍缓和
	var kind_bonus: float = {"neutral": 1.0, "positive": 0.92, "negative": 1.10}.get(current_kind, 1.0)
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
	if pressure >= MAX_VALUE or numbness >= MAX_VALUE:
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
	sentence_label.text = "你终于被听见了。" if won else "这场对话暂时结束了。"
	state_label.text = "胜利 · 好感度已满" if won else "失败 · 压力或麻木已满，或句子用尽"
	round_label.text = "R 重玩   1 汉字   2 拼音"
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
	var center_y := stage_size.y * (0.30 if lines.size() <= 1 else 0.34)
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
	# 第一段游戏打完 → 先 act1_intro，再 act1_end
	if not story_seen.has(STORY_ACT1_INTRO) and affection >= STORY_MID_1:
		return STORY_ACT1_INTRO
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
			_end_game(true)
	story_resume = ""


# ============================================================ 语音
# 长度型（short/long/long_short/short_long）从 VoiceData 反查；
# 说话人：14 = 父亲（father），23 = 母亲（mother）。

## 对局中的 BGM：
##   第一段游戏（act1_intro 之后）        Dream Street
##   第二段游戏（act1_end 之后）          There's Something Outside
##   第三段游戏（act2_end 之后）          萍逢
func _sync_bgm_for_act() -> void:
	if bgm_player == null:
		return
	if story_seen.has(STORY_ACT2_END):
		bgm_player.play("res://audio/bgm/pengfeng.mp3")
	elif story_seen.has(STORY_ACT1_END):
		bgm_player.play("res://audio/bgm/something_outside.mp3")
	else:
		bgm_player.play("res://audio/bgm/dream_street.mp3")


func _sentence_speaker() -> String:
	# 按句子内容查表（scripts/speaker_data.gd，172 句全部有归属）
	return SpeakerData.speaker_of(current_sentence)


func _play_sentence_voice() -> void:
	if voice_player == null or current_sentence.is_empty():
		return
	var started: bool = voice_player.play_for_sentence(current_sentence, _sentence_speaker())
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
## 当前飘在画面上的句子节点（长句会拆成多行，所以是数组）
var _curved_sentence_nodes: Array[Node2D] = []
## 对话框字格逐字浮现用的 tween
var _cell_tween: Tween = null
## 第三阶段把对话框移开的 tween
var _dialog_swing_tween: Tween = null
## 对话框的原始 offset_top（用于复位）
var _dialog_home_rect := Rect2()
## 第三阶段是否已把对话框移开
var _dialog_hidden_p3 := false
## 第三阶段第一句的 round_number
var _phase3_first_round := -1
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
	_state_resist_tick = 0.0
	if sfx_player != null:
		sfx_player.start_resist()
	state_label.text = "正在抵抗 · 这句话飞速滑过，松手可停"


func _end_resist() -> void:
	if not resisting:
		return
	resisting = false
	_state_resist_tick = 0.0
	if sfx_player != null:
		sfx_player.stop_resist()
	if phase == "playing":
		state_label.text = "正在对话"


var _state_resist_tick := 0.0


## 抵抗期间按真实时间累积压力（麻木条上涨），表示"硬扛的代价"。
func _tick_resist(delta: float) -> void:
	_state_resist_tick += delta
	if _state_resist_tick >= RESIST_PRESSURE_TICK:
		_state_resist_tick -= RESIST_PRESSURE_TICK
		numbness = minf(MAX_VALUE, numbness + RESIST_PRESSURE_PER_TICK)
		_update_bars()


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
	circle_fx.play(current_sentence, _stage_affection_progress())


# ============================================================ 第一阶段画面动态
# 好感度从 0 涨到 1/3（阶段一结束）期间，画面越来越暗，
# 同时随机在相邻模糊度的图片之间切换，并带轻微摇晃。
# 阶段一结束后停在最暗，不再变化。

## 阶段一的进度 0~1（1 = 阶段一结束）
func _mood_progress() -> float:
	return clampf(affection / maxf(STORY_MID_1, 0.001), 0.0, 1.0)


func _update_mood_layer() -> void:
	# 只有真正在游玩/剧情里才显示（标题画面不显示）
	var in_game := phase in ["playing", "story", "won", "lost"]
	var stage := _story_stage()          # 1 / 2 / 3
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
	var in_game := phase in ["playing", "story", "won", "lost"]
	ambient.update_state(_story_stage(), pressure, numbness, in_game)


## 心跳 + 呼吸：只由压力驱动
func _update_stress_audio() -> void:
	if stress_audio == null:
		return
	var in_game := phase in ["playing", "story", "won", "lost"]
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

	# 记录原始坐标（第一次切换时保存）
	if _dialog_home_rect.size.x <= 0.0:
		_dialog_home_rect = Rect2(
			panel.offset_left, panel.offset_top,
			panel.offset_right - panel.offset_left,
			panel.offset_bottom - panel.offset_top)

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
		if input_box != null:
			input_box.visible = input_mode == "hanzi"

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
	if input_box != null:
		input_box.visible = false


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
	# 隐藏输入框后，面板高度要贴合内容（否则下方留一片空白）
	if _dialog_hidden_p3:
		call_deferred("_fit_panel_height_to_content")


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
	var need: float = panel.get_combined_minimum_size().y + 8.0
	var cur: float = panel.offset_bottom - panel.offset_top
	if absf(need - cur) < 4.0:
		return
	var vp := get_viewport_rect().size
	var new_h: float = clampf(need, 120.0, vp.y * 0.55)
	var cy: float = (panel.offset_top + panel.offset_bottom) * 0.5
	panel.offset_top = cy - new_h * 0.5
	panel.offset_bottom = cy + new_h * 0.5
