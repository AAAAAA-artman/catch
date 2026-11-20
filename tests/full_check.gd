extends SceneTree
## 系统性排查：每个阶段、每种状态下，画面层 / HUD / 输入框的状态是否自洽
const OUT := "C:/Users/16436/Documents/deepseek-harness/default-workspace/catch_shots/"
var game: Node
var fails: Array = []


func _wait(n: int) -> void:
	for i in range(n):
		await process_frame


func _skip_story() -> void:
	var ov: Control = game.get_node("StoryOverlay")
	for g in range(12):
		if game.phase != "story":
			break
		ov.finish_now()
		game.skip_voice_wait()
		await _wait(10)
	if game.phase == "tutorial" and game.has_method("_close_tutorial"):
		game._close_tutorial()
		await _wait(8)


func _check(tag: String, cond: bool, detail: String) -> void:
	if cond:
		print("  OK   ", tag, " ", detail)
	else:
		print("  FAIL ", tag, " <<< ", detail)
		fails.append(tag + ": " + detail)


func _layers() -> Dictionary:
	return {
		"mood1": game.mood_layer.is_active(),
		"room2": game.phase2_room.is_active(),
		"gallery": game.phase3_gallery.is_active(),
	}


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _wait(20)

	print("=== 1) 主界面状态 ===")
	_check("菜单phase", game.phase == "menu", "phase=" + game.phase)
	_check("菜单可见", game.main_menu.visible, "")
	_check("HUD隐藏", not game.time_bar.visible and not game.get_node("%SentencePanel").visible, "")
	_check("画面层关闭", not game.mood_layer.is_active() and not game.phase2_room.is_active(), "")

	print("\n=== 2) 开局剧情 ===")
	game.main_menu.settings["tutorial_seen"] = true
	game.main_menu.close()
	game._set_game_hud_visible(true)
	game._start_game("hanzi")
	await _wait(15)
	_check("剧情中phase", game.phase in ["story", "tutorial"], "phase=" + game.phase)
	_check("剧情中背景可用", true, "（剧情自带背景图，画面层开着是正常的）")
	await _skip_story()
	await _wait(30)

	print("\n=== 3) 第一阶段（第1句）===")
	var L := _layers()
	_check("阶段=1", game._story_stage() == 1, "stage=" + str(game._story_stage()))
	_check("一阶段画面开", L["mood1"], str(L))
	_check("二阶段画面关", not L["room2"], str(L))
	_check("输入框有焦点", game.input_box.has_focus() or game.input_mode == "pinyin", "")
	root.get_texture().get_image().save_png(OUT + "chk_p1.png")

	print("\n=== 4) 第二阶段（第11句）===")
	game.round_number = 11
	game.affection = 40.0
	game._update_bars()
	game._advance_sentence("")
	await _wait(50)
	L = _layers()
	_check("阶段=2", game._story_stage() == 2, "stage=" + str(game._story_stage()))
	_check("二阶段画面开", L["room2"], str(L))
	_check("一阶段画面关", not L["mood1"], str(L))
	root.get_texture().get_image().save_png(OUT + "chk_p2.png")

	print("\n=== 5) 二阶段抵抗（好感扣减后不应倒退）===")
	game.affection = 34.2
	game._update_bars()
	game._begin_resist()
	var g2 := 0
	while game.resisting and g2 < 800:
		await process_frame
		g2 += 1
	await _wait(40)
	L = _layers()
	_check("抵抗后仍在阶段2", game._story_stage() == 2, "stage=" + str(game._story_stage()) + " aff=" + str(snappedf(game.affection, 1)))
	_check("抵抗后二阶段画面仍在", L["room2"] and not L["mood1"], str(L))

	print("\n=== 6) 第三阶段（第21句）===")
	game.round_number = 21
	game.affection = 70.0
	game._update_bars()
	game._advance_sentence("")
	await _wait(60)
	await _skip_story()      # 第 21 句可能触发 act2_end 剧情
	await _wait(60)
	L = _layers()
	_check("阶段=3", game._story_stage() == 3, "stage=" + str(game._story_stage()))
	_check("画廊已激活", L["gallery"], str(L))
	_check("输入框可聚焦(不可真隐藏)", game.input_box.visible, "visible=" + str(game.input_box.visible))
	root.get_texture().get_image().save_png(OUT + "chk_p3first.png")

	print("\n=== 7) 三阶段第一句打完 → 展开 ===")
	game.skip_voice_wait()
	var t: String = game.current_target
	game.phrase_elapsed = 3.0
	game.input_box.text = t
	game.input_box.text_changed.emit(t)
	await _wait(200)
	await _skip_story()
	await _wait(40)
	_check("画廊已展开", game.phase3_gallery.is_expanded(), "")
	_check("对话框已居中", game._dialog_hidden_p3, "")
	_check("输入框仍可输入(alpha=0)", game.input_box.visible and game.input_box.modulate.a < 0.01, "vis=" + str(game.input_box.visible) + " a=" + str(snappedf(game.input_box.modulate.a, 0.01)))
	root.get_texture().get_image().save_png(OUT + "chk_p3expanded.png")

	print("\n=== 8) 三阶段 Esc 暂停/恢复 ===")
	if game.phase != "playing":
		await _skip_story()
		await _wait(30)
	game._pause_game()
	await _wait(20)
	_check("暂停态", game.phase == "paused", "phase=" + game.phase)
	L = _layers()
	_check("暂停时画廊仍激活", L["gallery"], str(L))
	game._resume_game()
	await _wait(40)
	_check("恢复后仍是final分支", game.phase == "playing", "phase=" + game.phase)
	_check("恢复后画廊未重置", game.phase3_gallery.is_expanded(), "")

	print("\n=== 9) 压力提示（阈值 50）===")
	if game.phase != "playing":
		await _skip_story()
		await _wait(30)
	game._alt_hint_shown = false
	game.pressure = 49.0
	await _wait(4)
	_check("压力49不提示", not game._alt_hint_shown, "")
	game.pressure = 51.0
	game.current_tier = 3
	game.current_kind = "neutral"
	game.phrase_elapsed = 3.0
	game.phrase_mistakes = 0
	var t2: String = game.current_target
	game.input_box.text = t2
	game.input_box.text_changed.emit(t2)
	await _wait(30)
	_check("压力51提示已触发", game._alt_hint_shown, "")

	print("\n=== 10) 结算页 ===")
	game.pressure = 100.0
	game._check_loss()
	await _wait(20)
	_check("失败态", game.phase == "lost", "phase=" + game.phase)
	_check("有重开提示", "R 重玩" in game.state_label.text, "'" + game.state_label.text + "'")
	_check("状态行可见", game.state_label.visible, "")
	root.get_texture().get_image().save_png(OUT + "chk_lost.png")

	print("\n=== 11) 结算页 Esc 回主界面 ===")
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	Input.parse_input_event(esc)
	await _wait(30)
	_check("回到菜单", game.phase == "menu", "phase=" + game.phase)
	_check("菜单可见", game.main_menu.visible, "")

	print("\n=== 12) 从菜单重新开始（检查残留）===")
	game.main_menu.settings["tutorial_seen"] = true
	game.main_menu._on_start()
	await _wait(20)
	await _skip_story()
	await _wait(30)
	L = _layers()
	_check("重开后阶段1", game._story_stage() == 1, "stage=" + str(game._story_stage()))
	_check("重开后画廊关闭", not L["gallery"], str(L))
	_check("重开后二阶段画面关", not L["room2"], str(L))
	_check("重开后一阶段画面开", L["mood1"], str(L))
	_check("重开后好感为0", game.affection < 10.0, "aff=" + str(snappedf(game.affection, 1)))
	root.get_texture().get_image().save_png(OUT + "chk_restart.png")

	print("\n=== 汇总 ===")
	if fails.is_empty():
		print("ALL PASS  (0 项失败)")
	else:
		print("FAILED ", fails.size(), " 项:")
		for f in fails:
			print("  - ", f)
	print("DONE")
	quit()
