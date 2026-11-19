extends SceneTree
## 完整流程 + BGM 验收：走完三段游戏与五段剧情，打印 BGM 变化

var game: Node


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(8)
	var ov: Control = game.get_node("StoryOverlay")
	var bgm: Node = game.get_node("Bgm")
	print("FLOW 标题页 BGM = ", _track(bgm))

	game._start_game("hanzi")
	await _frames(6)
	print("FLOW 开局 剧情=", ov.get("_segment_id"), " BGM=", _track(bgm))
	ov.finish_now()
	await _frames(10)
	print("FLOW 第一段游戏 BGM=", _track(bgm))

	var guard := 0
	while game.phase != "won" and guard < 40:
		guard += 1
		if game.phase == "story":
			print("FLOW 剧情 ", ov.get("_segment_id"), " BGM=", _track(bgm))
			ov.finish_now()
			await _frames(8)
			continue
		if game.phase != "playing":
			break
		var t: String = game.current_target
		game.phrase_elapsed = float(t.length()) * 60.0 / 60.0
		game.input_box.text = t
		game.input_box.text_changed.emit(t)
		await _frames(3)
		if game.phase == "playing":
			print("FLOW   游戏 好感=%5.1f 阶段=%s BGM=%s" % [
				game.affection, game._sentence_phase(), _track(bgm)])

	for i in range(160):
		await process_frame
	print("FLOW 结束 phase=", game.phase, " BGM=", _track(bgm), " (应静音)")
	print("FLOW DONE")
	quit()


func _track(bgm: Node) -> String:
	if bgm == null:
		return "(无节点)"
	if not bgm.is_playing():
		return "(静音)"
	return bgm.current_path().split("/")[-1]


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame

## 连续跳过所有排队剧情，直到真正进入 playing
func _skip_all_story() -> void:
	var ov: Control = game.get_node("StoryOverlay")
	for guard in range(8):
		if game.phase != "story":
			return
		ov.finish_now()
		game.skip_voice_wait()
		for i in range(10):
			await process_frame
