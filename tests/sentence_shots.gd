extends SceneTree
## 新句子库的排版验收：分别渲染短句 / 中句 / 长句（汉字模式 + 拼音模式）

const OUT_DIR := "C:/Users/16436/Documents/deepseek-harness/default-workspace/catch_shots/"

var game: Node
var ov: Control


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(6)
	game._start_game("hanzi")
	await _frames(4)
	ov = game.get_node("StoryOverlay")
	ov.finish_now()
	await _frames(8)

	await _show("不要把门关上", "hanzi", "short_hanzi")
	await _show("你每天加班多久啊租房的室友怎么样", "hanzi", "mid_hanzi")
	await _show("妈妈今天出门看到一个衣服很适合你下次你回家咱们一起去看", "hanzi", "long_hanzi")
	await _show("你每天加班多久啊租房的室友怎么样", "pinyin", "mid_pinyin")
	await _show("妈妈今天出门看到一个衣服很适合你下次你回家咱们一起去看", "pinyin", "long_pinyin")

	print("SENT_SHOT: DONE")
	quit()


func _show(text: String, mode: String, tag: String) -> void:
	var entry := _find_entry(text)
	if entry.is_empty():
		print("SENT_SHOT: 找不到句子 ", text)
		return
	game.input_mode = mode
	game.phase = "playing"
	game.affection = 0.0
	game.round_number = 0
	for kind in ["neutral", "positive", "negative"]:
		game.sentence_bags["phase1:" + kind] = [entry.duplicate()]
	game._advance_sentence("测试 " + tag)
	await _frames(8)
	root.get_texture().get_image().save_png(OUT_DIR + "sentence_" + tag + ".png")
	print("SENT_SHOT: ", tag, " len=", game.current_sentence.length(), " text=", game.current_sentence)


func _find_entry(text: String) -> Dictionary:
	for phase in SentenceData.POOLS.keys():
		for kind in SentenceData.POOLS[phase].keys():
			for item in SentenceData.POOLS[phase][kind]:
				if item["text"] == text:
					return item.duplicate()
	return {}


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame
