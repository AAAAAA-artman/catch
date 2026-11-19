extends SceneTree
## 流程冒烟测试（headless）：标题 → prologue → act1_intro → 第一段游戏
## → act1_end → 第二段游戏 → act2_end → 第三段游戏 → 终章 5 句 → epilogue → 结算

const EXPECT_ORDER := ["prologue", "act1_intro", "act1_end", "act2_end", "epilogue"]

var game: Node
var overlay: Control
var seen_order: Array[String] = []


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(6)
	overlay = game.get_node("StoryOverlay")
	print("T0 初始 phase = ", game.phase)

	game._start_game("hanzi")
	await _frames(4)
	await _drain_stories("开局")

	# 第一段游戏 → 1/3
	_push_to(35.0)
	await _frames(4)
	await _drain_stories("1/3 后")

	# 第二段游戏 → 2/3
	_push_to(69.0)
	await _frames(4)
	await _drain_stories("2/3 后")

	# 第三段游戏 → 满（基准 6.5 × 0.6 也能到 100）
	# 好感满后会先进「终章 5 句」，打完才播 epilogue
	_push_to(100.0)
	await _frames(4)
	await _drain_final()
	await _drain_stories("终章后")

	print("T9  最终 phase = ", game.phase, "（won 表示进结算）")
	print("T10 剧情播放顺序 = ", seen_order)
	var ok: bool = seen_order.size() == EXPECT_ORDER.size()
	if ok:
		for i in EXPECT_ORDER.size():
			if seen_order[i] != EXPECT_ORDER[i]:
				ok = false
				print("  ✗ 第 ", i + 1, " 段应为 ", EXPECT_ORDER[i], "，实际 ", seen_order[i])
	print("T11 顺序检查 = ", ("PASS" if ok else "FAIL"))

	game._start_game("pinyin")
	await _frames(4)
	print("T12 重开后 phase = ", game.phase, " 段 = ", overlay.get("_segment_id"))
	print("STORY_FLOW: DONE")
	quit()


func _push_to(value: float) -> void:
	# 直接把好感设到目标值，再走一次结算触发剧情检查。
	# （新的好感算法按"阶段内剩余句数"均分，单句涨幅很小，
	#   靠结算慢慢爬要打十几句，测试里直接设值更快也更稳定。）
	game.affection = value
	game.phrase_elapsed = 20.0
	game.phrase_mistakes = 0
	game._update_bars()
	game._complete_sentence()
	print("   好感度 → ", snappedf(game.affection, 0.1))


## 打完终章句子池（好感满后的独立段）
func _drain_final() -> void:
	for guard in range(10):
		if game.phase != "final":
			return
		game.skip_voice_wait()
		var t: String = game.current_target
		game.input_box.text = t
		game.input_box.text_changed.emit(t)
		for i in range(12):
			await process_frame
	# 最后一句打完有 1.1 秒延迟才播 epilogue，多等一会儿
	for i in range(90):
		await process_frame


## 把当前排队的所有剧情一次播完（连续段会依次触发）
func _drain_stories(tag: String) -> void:
	for guard in range(8):
		if game.phase != "story":
			return
		var seg: String = String(overlay.get("_segment_id"))
		seen_order.append(seg)
		print("  [", tag, "] 剧情 ", seg)
		overlay.finish_now()
		for i in range(6):
			await process_frame


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame
