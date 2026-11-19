extends SceneTree
## 剧情系统视觉验收（窗口模式）：四个剧情段各截一张 + 结算页

const OUT_DIR := "C:/Users/16436/Documents/deepseek-harness/default-workspace/catch_shots/"
const SEGMENTS := ["prologue", "act1_intro", "act1_end", "act2_end", "epilogue"]

var game: Node
var overlay: Control


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	overlay = game.get_node("StoryOverlay")
	await _frames(8)
	_save("story_00_title.png")

	game._start_game("hanzi")
	await _frames(4)
	overlay.finish_now()
	await _frames(6)

	# 逐段直接播放并截图（纯视觉验收，不依赖好感度流程）
	for seg in SEGMENTS:
		game.phase = "playing"
		game._play_story(seg)
		await _frames(42)
		_save("story_" + seg + ".png")
		overlay.finish_now()
		await _frames(4)
		game.phase = "playing"
		game.story_seen.erase(seg)

	# 结算页
	game.affection = 100.0
	game._update_bars()
	game.phase = "playing"
	game._end_game(true)
	await _frames(30)
	_save("story_result.png")

	print("STORY_SHOT: DONE")
	quit()


func _save(name: String) -> void:
	root.get_texture().get_image().save_png(OUT_DIR + name)
	print("STORY_SHOT: ", name, " phase=", game.phase, " 段=", overlay.get("_segment_id"))


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame
