extends SceneTree
## 复现并验证：打错 → 输入被清空 → 重新从第一个字开始打，首字必须有击键声

var game: Node
var sfx: Node


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(8)
	sfx = game.get_node("Sfx")
	var ov: Control = game.get_node("StoryOverlay")

	# ---------- 汉字模式 ----------
	game._start_game("hanzi")
	await _frames(4)
	await _skip_all_story()
	await _frames(10)
	print("=== 汉字模式 ===")
	await _test_mode("hanzi")

	# ---------- 拼音模式 ----------
	game._start_game("pinyin")
	await _frames(4)
	await _skip_all_story()
	await _frames(10)
	print("=== 拼音模式 ===")
	await _test_mode("pinyin")

	print("KEY DONE")
	quit()


func _test_mode(mode: String) -> void:
	var target: String = game.current_target
	print("  目标=", target, " (", target.length(), ")")

	# 1) 正常打 3 个字符，应该有声
	sfx.stop_all()
	await _frames(2)
	for i in range(1, mini(3, target.length()) + 1):
		_type(target.substr(0, i))
		await _frames(2)
	print("  1) 正常打 3 字 → 击键声=", _any_key_playing())

	# 2) 打错一个字 → 触发清空
	await _frames(2)
	if mode == "hanzi":
		_type(target.substr(0, 3) + "错")
	else:
		_press_ascii("q")     # 拼音模式只收 ASCII，按一个错的字母
	await _frames(3)
	print("  2) 打错后 available=", game.input_box.text, " 锁定中=", game.input_lock_left > 0.0)
	print("     清空后 _last_input_length=", game._last_input_length)

	# 3) 等锁定结束
	var guard := 0
	while game.input_lock_left > 0.0 and guard < 300:
		await process_frame
		guard += 1
	print("  3) 锁定结束，_last_input_length=", game._last_input_length)

	# 4) 重新打第一个字 —— 关键检查点
	sfx.stop_all()
	await _frames(3)
	_type(target.substr(0, 1))
	await _frames(3)
	var ok := _any_key_playing()
	print("  4) 重打第一个字 → 击键声=", ok, ("  ✓" if ok else "  ✗ 没有声音！"))
	game.input_box.text = ""
	game._last_input_length = 0
	await _frames(2)


## 汉字模式直接设文本；拼音模式走 _handle_pinyin_key
func _type(value: String) -> void:
	if game.input_mode == "hanzi":
		game.input_box.text = value
		game.input_box.text_changed.emit(value)
	else:
		# 拼音：逐字符模拟按键
		var prev: String = game.input_box.text
		var next := value
		for ch in next.substr(prev.length()):
			var ev := InputEventKey.new()
			ev.keycode = OS.find_keycode_from_string(ch.to_upper())
			ev.unicode = ch.unicode_at(0)
			ev.pressed = true
			game._handle_pinyin_key(ev)


func _press_ascii(ch: String) -> void:
	var ev := InputEventKey.new()
	ev.keycode = OS.find_keycode_from_string(ch.to_upper())
	ev.unicode = ch.unicode_at(0)
	ev.pressed = true
	game._handle_pinyin_key(ev)


func _any_key_playing() -> bool:
	for p in sfx._keys:
		if p.playing:
			return true
	return false


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame

## 连续跳过所有排队剧情，直到真正进入 playing
func _skip_all_story() -> void:
	var ov: Control = game.get_node("StoryOverlay")
	for guard in range(8):
		if game.phase != "story":
			break
		ov.finish_now()
		game.skip_voice_wait()
		for i in range(10):
			await process_frame
	# 第一次进入游戏会弹操作说明，测试里直接关掉
	if game.phase == "tutorial" and game.has_method("_close_tutorial"):
		game._close_tutorial()
		for i in range(8):
			await process_frame
