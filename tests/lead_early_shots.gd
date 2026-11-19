extends SceneTree
## 早期版 + 文字特效 的视觉验收截图（窗口模式运行）

const OUT_DIR := "C:/Users/16436/Documents/deepseek-harness/default-workspace/catch_shots/"

var _reveal_done := false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		print("EARLY_SHOT: LOAD_FAIL")
		quit(1)
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	await _frames(6)
	_save("early_00_title.png")

	game._start_game("hanzi")
	var fx: Node = game.get_node("TextFx")
	var node: CurvedText = _first(fx)
	if node == null:
		print("EARLY_SHOT: NO_CURVED_NODE")
		quit(1)
		return
	node.finished.connect(func() -> void: _reveal_done = true)

	await _until_progress(fx, 0.35, 300)
	_save("early_01_reveal.png")

	await _until_done(300)
	await _frames(4)
	_save("early_02_full.png")

	await _until_progress(fx, 0.5, 900)
	_save("early_03_fading.png")

	await _until_progress(fx, 0.94, 900)
	_save("early_04_gone.png")

	game._block_sentence()
	await _frames(24)
	_save("early_05_block.png")

	game._end_game(true)
	await _frames(80)
	_save("early_06_end.png")

	print("EARLY_SHOT: DONE")
	quit()


func _first(fx: Node) -> CurvedText:
	for child in fx.get_children():
		if child is CurvedText:
			return child
	return null


func _save(file_name: String) -> void:
	root.get_texture().get_image().save_png(OUT_DIR + file_name)
	var line := "EARLY_SHOT: " + file_name
	var fx: Node = root.get_node_or_null("Main/TextFx")
	if fx == null:
		for child in root.get_children():
			var f = child.get_node_or_null("TextFx")
			if f != null:
				fx = f
	if fx != null:
		for child in fx.get_children():
			if child is CurvedText:
				line += " | text=%s progress=%.3f" % [child.text, child.get_progress()]
	print(line)


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _until_done(max_frames: int) -> void:
	for i in range(max_frames):
		if _reveal_done:
			return
		await process_frame


func _until_progress(fx: Node, target: float, max_frames: int) -> void:
	for i in range(max_frames):
		var node: CurvedText = _first(fx)
		if node != null and node.get_progress() >= target:
			return
		await process_frame
