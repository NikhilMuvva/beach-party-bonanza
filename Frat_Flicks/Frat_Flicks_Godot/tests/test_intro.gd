extends SceneTree
var app
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func hands(x: float = 0.3, present: bool = true) -> void:
	app.tracker.accept_packet({"protocol": 1, "session": "intro-test", "type": "state", "camera_ready": true, "frame_age_ms": 0.0, "hands": {"L": {"x": x, "y": 0.5}, "R": {"x": 0.7, "y": 0.5}} if present else {}, "calibration": {}})

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.test_mode = true
	check(app.state == "title", "opening is arcade title")
	check(ProjectSettings.get_setting("application/config/name") == "Frat Flicks", "window renamed Frat Flicks")
	check(app.labels["best_score"].text == "000000", "title shows real empty high score")
	app.buttons["press_start"].pressed.emit()
	check(app.transitioning and app.fade_overlay.visible, "press start launches fade")
	app._start_intro("keyboard")
	check(app.input_mode == "camera", "double-start is ignored during fade")
	await create_timer(0.75).timeout
	check(app.state == "intro" and not app.transitioning and not app.fade_overlay.visible, "fade ends in Bob scene")
	check(app.world.mode == "intro", "Bob animated atlas is the scene background")
	check(app.labels["bob_text"].text.begins_with("Howdy, bros, and welcome to Frat Flicks!"), "authored dialogue starts correctly")
	check(not app.music.playing, "song cannot start during dialogue")
	check(not app.buttons["intro_begin"].visible, "begin remains hidden on early pages")
	var initial_page: int = app.dialogue_page
	app._next_dialogue()
	check(app.dialogue_page == initial_page and app.labels["bob_text"].visible_characters == app.BOB_DIALOGUE[0].length(), "first click can reveal current text without skipping")
	app._next_dialogue()
	check(app.dialogue_page == 1 and app.labels["bob_text"].visible_characters == 0, "next advances one page")
	app._previous_dialogue()
	check(app.dialogue_page == 0, "back revisits previous page")
	app._finish_intro()
	check(app.state == "intro" and not app.transitioning, "begin cannot bypass earlier dialogue")
	for index in app.BOB_DIALOGUE.size():
		app._tick_dialogue(100.0)
		check(app.labels["bob_text"].visible_characters == app.BOB_DIALOGUE[index].length(), "page fully reveals " + str(index))
		check(app.dialogue_page == index, "typewriter never advances pages automatically")
		check(app.buttons["intro_begin"].visible == (index == app.BOB_DIALOGUE.size() - 1), "begin visibility follows final-page completion")
		if index < app.BOB_DIALOGUE.size() - 1:
			app.buttons["dialogue_next"].pressed.emit()
	check(app.buttons["intro_begin"].text == "BEGIN!", "final retro button says BEGIN!")
	app.buttons["intro_begin"].pressed.emit()
	await create_timer(0.75).timeout
	check(app.state == "tutorial" and not app.music.playing, "begin opens instructions before gameplay")
	app._instructions_ready()
	check(app.state == "calibrate" and not app.setup_complete, "camera instructions lead to initial baseline")
	hands()
	app._process(0.5)
	hands()
	app._process(1.0)
	check(app.state == "calibrate", "initial baseline requires more than 1.5 seconds")
	hands(0.5)
	check(app.stable_hands == 0.0, "moving a hand resets the baseline hold")
	app._process(0.5)
	hands(0.3, false)
	app._process(0.1)
	check(app.stable_hands == 0.0, "missing hands reset calibration")
	hands()
	app._process(1.0)
	hands()
	app._process(0.99)
	check(app.state == "calibrate", "calibration cannot finish before two seconds")
	hands()
	app._process(0.01)
	check(app.state == "countdown" and app.setup_complete and app.countdown == 3.0, "two-second hold automatically starts countdown")
	hands()
	app._process(3.0)
	check(app.state == "playing" and app.music.playing and app.judge.score == 0, "camera route reaches actual gameplay with a fresh score")
	app._return_title()
	app._start_intro("keyboard")
	await create_timer(0.75).timeout
	check(app.state == "intro" and app.dialogue_page == 0, "replay resets Bob to first page")
	app.dialogue_page = app.BOB_DIALOGUE.size() - 1
	app._set_dialogue_page()
	app._tick_dialogue(100.0)
	app._finish_intro()
	await create_timer(0.75).timeout
	app._instructions_ready()
	check(app.state == "countdown" and app.input_mode == "keyboard", "keyboard path bypasses webcam calibration")
	check(app.world.intro_frame(0.0) != app.world.intro_frame(0.22), "animated intro advances atlas frames")
	check(app.world.intro_frame(0.0) == app.world.intro_frame(app.world.intro_total), "intro loops cleanly")
	var world_code := FileAccess.get_file_as_string("res://scripts/beach_world.gd")
	check(not world_code.contains("GIG 'EM") and not world_code.contains("_draw_aggie_party"), "old sign and stick figures removed")
	app.tracker.close()
	app.music.stop()
	app.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("INTRO_TESTS ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
