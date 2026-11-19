extends Node
## 开发者模式（Dev）—— 快速进入游戏测试。
##
## 快捷键（任何 phase 下都生效）：
##   F1  直接开始汉字模式，跳过开场剧情
##   F2  直接开始拼音模式，跳过开场剧情
##   F3  跳到指定好感度（分段：0 / 34 / 68 / 96，连按轮换）
##   F4  好感度直接拉满 → 触发结局剧情
##   F5  时间条拉到 5%（观察紧张音 + 时间条方向）
##   F6  压力 +30（观察压力条）
##   F7  麻木 +30（观察麻木条）
##   F8  重播当前剧情段（方便看台词排版）
##   F9  打印当前状态到输出
##   F10 自动完美通过当前句（等同手打满分）  ⭐
##   F12 开/关"免死"（压力/麻木不会失败）
##
## 想关掉：把本节点 visible 设为 false，或直接删掉场景里的 Dev 节点。

@export var enabled := true

var _game: Node
var _boost_index := 0
const BOOST_STEPS := [0.0, 34.0, 68.0, 96.0]


func _ready() -> void:
	_game = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if not enabled or _game == null:
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return

	match key.keycode:
		KEY_F1:
			_dev_start("hanzi")
		KEY_F2:
			_dev_start("pinyin")
		KEY_F3:
			_boost_index = (_boost_index + 1) % BOOST_STEPS.size()
			_game.affection = BOOST_STEPS[_boost_index]
			_game._update_bars()
			_game._refresh_stats()
			print("[Dev] 好感度 → ", _game.affection)
		KEY_F4:
			_game.affection = _game.MAX_VALUE
			_game._update_bars()
			_game._advance_sentence("Dev: 好感度拉满")
			print("[Dev] 好感度拉满，触发结局")
		KEY_F5:
			if _game.phase == "playing":
				_game.time_left = _game.time_limit * 0.05
				print("[Dev] 时间 → 5%")
		KEY_F6:
			_game.pressure = minf(_game.MAX_VALUE, _game.pressure + 30.0)
			_game._update_bars()
			print("[Dev] 压力 → ", _game.pressure)
		KEY_F7:
			_game.numbness = minf(_game.MAX_VALUE, _game.numbness + 30.0)
			_game._update_bars()
			print("[Dev] 麻木 → ", _game.numbness)
		KEY_F8:
			_dev_replay_story()
		KEY_F9:
			_dev_print_state()
		KEY_F10:
			_dev_auto_accept()
		KEY_F12:
			_game.debug_invincible = not bool(_game.debug_invincible)
			print("[Dev] 免死 = ", _game.debug_invincible)
		_:
			return
	get_viewport().set_input_as_handled()


## 直接进游戏：跳过标题与开场剧情，并给一个干净的初始状态
func _dev_start(mode: String) -> void:
	print("[Dev] 直接开局：", mode)
	_game._start_game(mode)
	# 跳过 prologue
	if _game.phase == "story":
		var overlay := _game.get_node_or_null("StoryOverlay")
		if overlay != null:
			overlay.finish_now()


func _dev_replay_story() -> void:
	var overlay := _game.get_node_or_null("StoryOverlay")
	if overlay == null:
		return
	var seg := String(overlay.get("_segment_id"))
	if seg.is_empty():
		seg = "prologue"
	_game._play_story(seg)
	print("[Dev] 重播剧情段 ", seg)


func _dev_print_state() -> void:
	print("=== [Dev] 状态 ===")
	print("  phase=", _game.phase, "  模式=", _game.input_mode)
	print("  当前句=", _game.current_sentence, " (", _game.current_sentence.length(), " 字)")
	print("  好感=", _game.affection, "  压力=", _game.pressure, "  麻木=", _game.numbness)
	print("  剩余时间=", snappedf(_game.time_left, 0.1), "/", snappedf(_game.time_limit, 0.1))
	print("  回合=", _game.round_number, "/", _game.MAX_ROUNDS)
	print("  已播剧情=", _game.story_seen)


## 自动完美通过当前句：直接把整句填进输入框并触发结算。
## 用于跳过打字、快速推进剧情/数值，表现等价于"手打满分"。
func _dev_auto_accept() -> void:
	if _game.phase != "playing":
		print("[Dev] 当前不在游戏中（phase=", _game.phase, "），无法自动通过")
		return
	var target: String = String(_game.current_target)
	if target.is_empty():
		print("[Dev] 没有当前句子")
		return
	# 清掉可能存在的语音锁 / 错误锁，避免结算被拦
	_game.skip_voice_wait()
	_game.input_lock_left = 0.0
	_game.phrase_mistakes = 0
	# 打满表现（速度给到参考值的 1.4 倍 → 单句好感接近上限）
	_game.phrase_elapsed = maxf(float(target.length()) * 60.0 / (120.0 * 1.4), 0.3)
	# 整句一次性写入并触发结算
	_game.input_box.text = target
	_game.input_box.text_changed.emit(target)
	print("[Dev] 自动通过：", _game.current_sentence, " (好感 ", snappedf(_game.affection, 0.1), ")")
