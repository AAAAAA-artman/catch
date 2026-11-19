extends SceneTree
## 音效触发验收：逐项验证 7 个触发点是否都正确触发

var game: Node
var sfx: Node


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(8)
	sfx = game.get_node("Sfx")
	var ov: Control = game.get_node("StoryOverlay")

	# 0) 资源加载
	for key in ["accept_normal", "accept_positive",
			"accept_negative_1", "accept_negative_2", "sentence_complete", "stage_complete"]:
		var st = sfx._stream(key)
		print("SFX 资源 ", key, " = ", ("%.2fs" % st.get_length()) if st else "缺失")
	print("SFX 击键样本数 = ", sfx._key_streams.size(), "，通道数 = ", sfx._keys.size())

	game._start_game("hanzi")
	await _frames(4)
	await _skip_all_story()
	await _frames(8)
	print("SFX 开局完成, 当前句 = ", game.current_sentence, " 类型 = ", game.current_kind)

	# 1) 打字音：逐字输入
	sfx.stop_all()
	var target: String = game.current_target
	for i in range(1, mini(target.length(), 4) + 1):
		var partial := target.substr(0, i)
		game.input_box.text = partial
		game.input_box.text_changed.emit(partial)
		await _frames(2)
	var key_playing := false
	for p in sfx._keys:
		if p.playing:
			key_playing = true
	print("SFX 1) 逐字输入 4 字 → 击键声播放中 = ", key_playing)

	# 2~3) 完成普通句子：回车音 + 接受音
	sfx.stop_all()
	var before: float = game.affection
	game.phrase_elapsed = 20.0
	game.input_box.text = target
	game.input_box.text_changed.emit(target)
	await _frames(2)
	print("SFX 2) 完成 %s 句 → 一次性音效播放数 = %d" % [game.current_kind, _playing_oneshots()])

	# 4) 负面句子：压力低 → negative_1
	if game.phase == "story":
		ov.finish_now()
		game.skip_voice_wait()
		await _frames(6)
	game.current_kind = "negative"
	game.pressure = 20.0
	sfx.stop_all()
	sfx.play_accept("negative", game.pressure, 100.0)
	await _frames(2)
	print("SFX 4) 负面句 + 压力20 → ", _last_oneshot())

	# 5) 负面句子：压力高 → negative_2
	sfx.stop_all()
	sfx.play_accept("negative", 70.0, 100.0)
	await _frames(2)
	print("SFX 5) 负面句 + 压力70 → ", _last_oneshot())

	# 6) 正面句子 → accept_positive
	sfx.stop_all()
	sfx.play_accept("positive", 10.0, 100.0)
	await _frames(2)
	print("SFX 6) 正面句 → ", _last_oneshot())

	# 7) 普通句子 → accept_normal
	sfx.stop_all()
	sfx.play_accept("neutral", 10.0, 100.0)
	await _frames(2)
	print("SFX 7) 普通句 → ", _last_oneshot())

	# 8) 阶段满进剧情 → stage_complete
	# 直接调用"进入剧情"的内部流程，绕开打字结算（前面的测试已经打乱了好几轮状态，
	# 靠结算推好感不可靠）。这一步只验证 stage_complete 是否被触发。
	sfx.stop_all()
	game.affection = game.STORY_MID_1 + 1.0
	game._update_bars()
	game.phase = "playing"
	var entered: bool = game._start_story_chain("测试")
	await process_frame
	var found := _find_playing("stage_complete")
	print("SFX 8) _start_story_chain 返回=", entered, " phase=", game.phase)
	print("SFX 8) 阶段满进剧情(phase=", game.phase, ") → stage_complete 播放中 = ", found)

	print("SFX DONE")
	quit()


func _playing_oneshots() -> int:
	var n := 0
	for p in sfx._oneshots:
		if p.playing:
			n += 1
	return n


func _last_oneshot() -> String:
	for p in sfx._oneshots:
		if p.playing and p.stream:
			return p.stream.resource_path.split("/")[-1]
	return "(无)"


func _find_playing(name: String) -> bool:
	for p in sfx._oneshots:
		if p.playing and p.stream and name in p.stream.resource_path:
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
