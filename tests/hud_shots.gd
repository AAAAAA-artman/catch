extends SceneTree
## 新版式截图：标题页 + 对局中（含满数值）+ 高数值状态

const OUT := "C:/Users/16436/Documents/deepseek-harness/default-workspace/catch_shots/"

var game: Node
var ov: Control


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(8)
	ov = game.get_node("StoryOverlay")
	_save("hud_00_title.png")

	game._start_game("hanzi")
	await _frames(4)
	ov.finish_now()
	await _frames(24)

	# 正常状态
	game.affection = 20.0
	game.pressure = 18.0
	game.numbness = 10.0
	game.time_left = game.time_limit * 0.72
	game._update_bars()
	await _frames(20)
	_save("hud_01_normal.png")

	# 高压状态
	game.affection = 55.0
	game.pressure = 62.0
	game.numbness = 40.0
	game.time_left = game.time_limit * 0.25
	game._update_bars()
	await _frames(20)
	_save("hud_02_danger.png")

	# 危险状态
	game.affection = 88.0
	game.pressure = 92.0
	game.numbness = 85.0
	game.time_left = game.time_limit * 0.06
	game._update_bars()
	await _frames(20)
	_save("hud_03_critical.png")

	print("HUD_SHOT: DONE")
	quit()


func _save(name: String) -> void:
	root.get_texture().get_image().save_png(OUT + name)
	print("HUD_SHOT: ", name)


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
