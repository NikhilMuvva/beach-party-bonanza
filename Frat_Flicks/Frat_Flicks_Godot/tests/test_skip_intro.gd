extends SceneTree
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280,720)
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.test_mode = true
	app._select_song("paradise")
	app._start_intro("keyboard")
	await create_timer(.8).timeout
	for page in 7:
		app._show("intro")
		app.dialogue_page = page
		app._set_dialogue_page()
		app._tick_dialogue(.01)
		check(app.buttons["dialogue_skip"].is_visible_in_tree(), "skip visible on page " + str(page))
		check(app.labels["bob_text"].visible_characters < app.BOB_DIALOGUE[page].length(), "skip available before text completes")
		var position: float = app.intro_music.get_playback_position()
		var click := InputEventMouseButton.new()
		click.button_index=MOUSE_BUTTON_LEFT
		click.position=app.buttons["dialogue_skip"].get_global_rect().get_center()
		click.pressed=true
		app.get_viewport().push_input(click,true)
		click=click.duplicate()
		click.pressed=false
		app.get_viewport().push_input(click,true)
		check(app.transitioning and not app.bob_audio.playing and not app.bob_voice_pending, "mouse skip stops voice immediately")
		check(app.intro_music.playing, "skip retains background music")
		app._skip_intro()
		await create_timer(.8).timeout
		check(app.state == "tutorial" and not app.transitioning, "skip transitions to instructions once")
		check(app.intro_music.get_playback_position() >= position, "music continues without restart")
		check(app.chart_key == "paradise" and app.input_mode == "keyboard", "skip preserves song and controls")
	app._skip_intro()
	check(app.state == "tutorial" and not app.transitioning, "skip outside intro ignored")
	app._instructions_ready()
	check(app.state == "countdown" and not app.intro_music.playing, "normal instructions continue into countdown")
	app.tracker.close()
	app.queue_free()
	await process_frame
	await create_timer(.2).timeout
	print("SKIP_INTRO_TESTS ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
