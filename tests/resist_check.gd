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
	ov.finish_now()
	await _frames(8)

	# ---------- 抵抗：计时加速 ----------
	print("\nR === 抵抗机制 ===")
	var t0: float = game.time_left
	var limit: float = game.time_limit
	sfx.stop_all()
	game._begin_resist()
	print("R 按下 Alt: resisting=", game.resisting, " 抵抗音播放=", sfx.is_resisting(),
		" 剩余=%.2f/%.2f" % [t0, limit])
	var numb0: float = game.numbness
	for i in range(30):
		await process_frame
	var t1: float = game.time_left
	print("R 按住 0.5s: 剩余 %.2f → %.2f (下降 %.2f，正常应 %.2f)" % [
		t0, t1, t0 - t1, 30.0 / 60.0])
	print("R 麻木 %.1f → %.1f (抵抗代价)" % [numb0, game.numbness])

	# 松手
	game._end_resist()
	print("R 松开 Alt: resisting=", game.resisting, " 抵抗音播放=", sfx.is_resisting())
	var t2: float = game.time_left
	for i in range(15):
		await process_frame
	print("R 松手 0.25s: 剩余 %.2f → %.2f (下降 %.2f，应为正常速度)" % [
		t2, game.time_left, t2 - game.time_left])

	# ---------- 抵抗到时间归零 ----------
	print("\nR === 抵抗到超时 ===")
	if game.phase == "story":
		ov.finish_now()
		await _frames(6)
	sfx.stop_all()
	game.time_left = 0.3
	var p0: float = game.pressure
	game._begin_resist()
	for i in range(40):
		await process_frame
	game._end_resist()
	await _frames(4)
	print("R 计时归零: 压力 %.1f → %.1f (应 +20)" % [p0, game.pressure])
	print("R 句子失败音播放 = ", _playing("sentence_fail"))

	# ---------- 误触 ----------
	print("\nR === 误触 ===")
	if game.phase == "story":
		ov.finish_now()
		await _frames(6)
	sfx.stop_all()
	game.input_box.text = "错"
	game.input_box.text_changed.emit("错")
	await _frames(2)
	print("R 打错字: mistake=", _playing("mistake"), " sentence_fail=", _playing("sentence_fail"))

	# ---------- 游戏失败 ----------
	print("\nR === 游戏失败 ===")
	if game.phase == "story":
		ov.finish_now()
		await _frames(6)
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
