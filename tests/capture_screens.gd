extends SceneTree
## Internal visual QA: run with a real display / Xvfb and -- --test-mode.
var app
var directory := ""

func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(name + ".png"))

func run() -> void:
	directory = OS.get_environment("BEACH_CAPTURE_DIR")
	if directory.is_empty():
		push_error("Set BEACH_CAPTURE_DIR to an absolute temporary folder")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1280, 720)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.test_mode = true
	await capture("01_title")
	app.title_jukebox.step(1)
	await create_timer(0.26).timeout
	await capture("01_carousel_slide")
	await create_timer(0.4).timeout
	await capture("01_carousel_next")
	app._start_intro("camera")
	await create_timer(0.75).timeout
	app._tick_dialogue(100.0)
	await capture("02_bob_intro")
	for index in range(1, app.BOB_DIALOGUE.size()):
		app._next_dialogue()
		app._tick_dialogue(100.0)
		await capture("bob_page_%02d" % (index + 1))
	app._finish_intro()
	await create_timer(0.75).timeout
	await capture("03_after_begin")
	app._begin_camera()
	await capture("02_calibration")
	app._begin_keyboard()
	await capture("03_tutorial")
	app._begin_countdown()
	await capture("04_countdown")
	app._start_round()
	app.music.stream_paused = true
	app.set_process(false)
	app.audio_time = 3.85
	app.world.clock = 3.85
	app.world.beats = [{"t": 3.85, "lane": "down"}, {"t": 3.85, "lane": "up"}]
	app.world.status = PackedByteArray([0, 0])
	app.judge.score = 26
	app.judge.lane_scores = {"L": 14, "R": 12}
	app.judge.perfect_streak = 8
	app.judge.accuracy_credit = 16.2
	app.judge.hits = 17
	app.judge.combo = 8
	app.judge.vibe = 0.76
	app._update_hud()
	await capture("05_gameplay")
	app.world.clock = 3.97
	await capture("05_wave_past_target")
	app.world.clock = 4.09
	await capture("05_wave_continuing")
	app.world.clock = 3.85
	await create_timer(0.8).timeout
	await capture("05_gameplay_motion")
	app.world.hand_progress = {"L": 1.0, "R": 1.0}
	await capture("05_hands_flick")
	app.world.hand_progress = {"L": 1.0, "R": 0.0}
	await capture("05_hands_mixed")
	app.world.hand_progress = {"L": 0.0, "R": 0.0}
	app._pause()
	await capture("06_pause")
	app._finish(true)
	await capture("07_win")
	app._finish(false)
	await capture("08_lose")
	app._return_title()
	app._open_settings()
	await capture("09_settings")
	app._quit()
