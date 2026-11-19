extends SceneTree


func _initialize() -> void:
	var scene := load("res://scenes/main.tscn")
	var game: Variant = scene.instantiate()
	root.add_child(game)
	call_deferred("_check_game", game)


func _check_game(game: Variant) -> void:
	for layer in ["Background", "BossArea", "HUD", "SentencePanel", "Feedback", "PauseOverlay"]:
		assert(game.has_node(layer))
	game._start_game("pinyin")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	var time_before_pause: float = game.time_left
	game._input(escape)
	assert(game.phase == "paused")
	assert(game.pause_overlay.visible)
	game._process(1.0)
	assert(game.time_left == time_before_pause)
	game._input(escape)
	assert(game.phase == "playing")
	assert(not game.pause_overlay.visible)
	assert(game.kind_deck.size() == 16)
	assert(game.kind_deck.slice(0, 8).count("negative") == 1)
	assert(game.kind_deck.slice(8, 16).count("negative") == 4)
	assert(game.kind_deck.count("special") == 0)
	var ordinary_door_line := false
	for entry in game.SENTENCES["neutral"]:
		if entry["text"] == "门还没关上吗":
			ordinary_door_line = true
	assert(ordinary_door_line)
	assert(game.current_pinyin.size() == game.current_sentence.length())
	assert(game.current_target.contains(" "))
	assert(not game.cursor_rect.visible)
	game._layout_sentence()
	var start_position: Vector2 = game.pinyin_row.position
	game._process(1.0)
	assert(game.pinyin_row.position == start_position)
	game._on_text_changed("#")
	assert(game.input_lock_left > 0.0)
	assert(game.pressure == 8.0)
	assert(game.input_box.text.is_empty())
	assert(not game.cursor_rect.visible)
	game._start_game("hanzi")
	assert(game.current_target == game.current_sentence)
	assert(not game.cursor_rect.visible)
	for i in range(1, 16):
		game._advance_sentence("测试下一句")
	assert(game.round_number == 16)
	game.current_kind = "neutral"
	game.time_left = 9.0
	game.phrase_elapsed = 9.0
	game._complete_sentence()
	assert(game.score >= 60)
	assert(game.affection > 0.0)
	game.current_kind = "neutral"
	game.input_mode = "hanzi"
	assert(game._affection_from_score(100) == 12)
	game.current_kind = "positive"
	assert(game._affection_from_score(100) == 8)
	game.current_kind = "negative"
	assert(game._affection_from_score(100) == 18)
	game.input_mode = "pinyin"
	assert(game._affection_from_score(1000) == 18)
	game._start_game("hanzi")
	game.current_kind = "negative"
	game.phrase_elapsed = 5.0
	game._complete_sentence()
	assert(game.affection > 0.0)
	assert(game.pressure >= 18.0)
	print("SMOKE TEST PASSED")
	quit()
