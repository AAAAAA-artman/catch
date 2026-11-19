extends SceneTree
## 紧张音 + 字体 + sentence_fail 时机验收

const OUT := "C:/Users/16436/Documents/deepseek-harness/default-workspace/catch_shots/"

var game: Node
var sfx: Node
var ov: Control


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(8)
	sfx = game.get_node("Sfx")
	ov = game.get_node("StoryOverlay")

	# ---- 资源 ----
	var ts = sfx._stream("tension")
	print("T 资源 tension = ", ("%.2fs" % ts.get_length()) if ts else "缺失")

	# ---- 字体 ----
	var font: Font = game._game_font_resource()
	print("T 字体 = ", (font.get_font_name() if font else "null"),
		" 有'接'字 = ", (font.has_char("接".unicode_at(0)) if font else false))

	game._start_game("hanzi")
	await _frames(4)
	ov.finish_now()
	await _frames(8)

	# ---- 紧张音：剩余时间变化 ----
	print("\nT === 紧张音 ===")
	game.time_limit = 20.0
	game.time_left = 20.0
	game._update_tension_audio()
	print("T 剩余 100% → tension=", sfx.is_tension(), " (应 false)")

	game.time_left = 8.0     # 40%
	game._update_tension_audio()
	print("T 剩余 40%  → tension=", sfx.is_tension(), " (应 false)")

	game.time_left = 5.9     # 29.5%
	game._update_tension_audio()
	print("T 剩余 29.5% → tension=", sfx.is_tension(), " (应 true)")
	await _frames(30)
	print("T   播放器状态 playing=", sfx._tension_player.playing,
		" vol=", snappedf(sfx._tension_player.volume_db, 0.1))

	game.time_left = 12.0    # 恢复到 60%
	game._update_tension_audio()
	print("T 剩余 60%  → tension=", sfx.is_tension(), " (应 false)")

	# ---- 打错字：只播 mistake ----
	print("\nT === 打错字音效 ===")
	sfx.stop_all()
	await _frames(2)
	game.input_box.text = "错"
	game.input_box.text_changed.emit("错")
	await _frames(2)
	print("T 打错字: mistake=", _playing("mistake"), " sentence_fail=", _playing("sentence_fail"),
		" (应 true / false)")

	# ---- 超时：播 sentence_fail ----
	print("\nT === 超时音效 ===")
	if game.phase == "story":
		ov.finish_now()
		await _frames(6)
	sfx.stop_all()
	await _frames(2)
	game.time_left = 0.0
	game.time_limit = 20.0
	var p0: float = game.pressure
	await _frames(4)
	print("T 超时: sentence_fail=", _playing("sentence_fail"),
		" 压力 %.1f → %.1f" % [p0, game.pressure])

	# ---- 截图看字体 ----
	print("\nT === 字体截图 ===")
	game._start_game("hanzi")
	await _frames(4)
	ov.finish_now()
	await _frames(20)
	root.get_texture().get_image().save_png(OUT + "font_hanzi.png")
	print("T 截图 font_hanzi.png 当前句=", game.current_sentence)

	print("\nT DONE")
	quit()


func _playing(name: String) -> bool:
	for p in sfx._oneshots:
		if p.playing and p.stream and name in p.stream.resource_path:
			return true
	return false


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame
