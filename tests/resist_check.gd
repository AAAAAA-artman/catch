extends SceneTree
## 抵抗机制 + 新增音效验收

var game: Node
var sfx: Node
var ov: Control


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(8)
	sfx = game.get_node("Sfx")
	ov = game.get_node("StoryOverlay")

	# 资源
	for key in ["resist", "mistake", "sentence_fail", "game_over"]:
		var st = sfx._stream(key)
		print("R 资源 ", key, " = ", ("%.2fs" % st.get_length()) if st else "缺失")

	game._start_game("hanzi")
	await _frames(4)
	await _skip_all_story()

	# ---------- 抵抗：固定 2.5 秒跳句 ----------
	print("\nR === 抵抗机制（固定 2.5 秒）===")
	sfx.stop_all()
	var t0: float = game.time_left
	var numb0: float = game.numbness
	var aff0: float = game.affection
	var pre0: float = game.pressure
	game._begin_resist()
	print("R 按下 Alt: resisting=", game.resisting, " 抵抗音=", sfx.is_resisting(),
		" 按住时长=", snappedf(game.RESIST_HOLD_TIME, 0.1), "s")
	for i in range(60):
		await process_frame
	print("R 按住 1.0s: 剩余计时=", snappedf(game.resist_hold_left, 0.1), "（应约 1.5）")
	print("R 本句时间不变: ", snappedf(t0, 1), " → ", snappedf(game.time_left, 1))
	# 继续按到跳句（headless 帧率不稳定，用状态判断而不是死等帧数）
	var guard := 0
	while game.resisting and guard < 1200:
		await process_frame
		guard += 1
	print("R 按住满: resisting=", game.resisting,
		" 麻木 ", snappedf(numb0, 0.1), "→", snappedf(game.numbness, 0.1),
		"（应 +", int(game.RESIST_NUMBNESS), "）")
	print("R 好感 ", snappedf(aff0, 0.1), "→", snappedf(game.affection, 0.1),
		"（应 -", int(game.RESIST_AFFECTION_LOSS), "）")
	print("R 压力 ", snappedf(pre0, 0.1), "→", snappedf(game.pressure, 0.1), "（应不变）")

	# ---------- 半途松手：不跳句 ----------
	print("\nR === 半途松手 ===")
	if game.phase == "story":
		await _skip_all_story()
	sfx.stop_all()
	var n1: float = game.numbness
	game._begin_resist()
	for i in range(30):
		await process_frame
	game._end_resist()
	await _frames(6)
	print("R 按住 0.5s 后松手: resisting=", game.resisting,
		" 麻木 ", snappedf(n1, 0.1), "→", snappedf(game.numbness, 0.1), "（应不变）")

	# ---------- 误触 ----------
	print("\nR === 误触 ===")
	if game.phase == "story":
		await _skip_all_story()
	sfx.stop_all()
	game.input_box.text = "错"
	game.input_box.text_changed.emit("错")
	await _frames(2)
	print("R 打错字: mistake=", _playing("mistake"), " sentence_fail=", _playing("sentence_fail"))

	# ---------- 游戏失败 ----------
	print("\nR === 游戏失败 ===")
	if game.phase == "story":
		await _skip_all_story()
	sfx.stop_all()
	game.pressure = 100.0
	game._update_bars()
	game._check_loss()
	await _frames(2)
	print("R 失败: phase=", game.phase, " game_over 播放=", _playing("game_over"))

	print("\nR DONE")
	quit()


func _playing(name: String) -> bool:
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
