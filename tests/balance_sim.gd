extends SceneTree
## 模拟真实玩家打完整一局，打印每句的分数/好感度，定位"一阶段就打满"的原因

var game: Node


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(6)
	game._start_game("pinyin" if OS.get_cmdline_user_args().size() > 0 else "hanzi")
	await _frames(4)
	var ov: Control = game.get_node("StoryOverlay")
	ov.finish_now()
	await _frames(8)

	print("=== 模拟：", game.input_mode, "模式，真实速度 ===")
	for n in range(20):
		if game.phase == "story":
			print("  [剧情 %s]" % ov.get("_segment_id"))
			ov.finish_now()
			await _frames(6)
			continue
		if game.phase != "playing":
			print("  结束 phase=", game.phase, " 好感=", game.affection)
			break
		var t: String = game.current_target
		var text: String = game.current_sentence
		var kind: String = game.current_kind
		# 真实玩家：汉字 60 字符/分，拼音 180 字符/分
		var cpm := 60.0 if game.input_mode == "hanzi" else 180.0
		game.phrase_elapsed = float(t.length()) * 60.0 / cpm
		game.phrase_mistakes = 0
		var before: float = game.affection
		game.input_box.text = t
		game.input_box.text_changed.emit(t)
		await _frames(4)
		print("  第%2d句 len=%2d kind=%-8s 好感 %5.1f → %5.1f (+%4.1f) phase=%s" % [
			n + 1, text.length(), kind, before, game.affection, game.affection - before, game.phase])
	print("SIM: DONE")
	quit()


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame
