extends SceneTree
var app
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func hands(session: String = "polish") -> void:
	app.tracker.accept_packet({"protocol":1,"session":session,"type":"state","camera_ready":true,"frame_age_ms":0.0,"hands":{"L":{},"R":{}},"calibration":{}})
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.test_mode = true
	app.input_mode = "keyboard"
	var enter := InputEventKey.new()
	enter.physical_keycode=KEY_ENTER
	enter.pressed=true
	app._unhandled_key_input(enter)
	check(app.input_mode == "keyboard", "Enter respects keyboard launch mode")
	await create_timer(.8).timeout
	app._return_title()
	app._begin_camera()
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	for i in 10:
		hands()
		app._process(.25)
	check(app.state == "calibrate" and app.stable_hands == 0, "unfocused hand setup cannot start game")
	check(app.intro_music.stream_paused, "unfocused setup music stays paused")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	hands()
	app._process(.25)
	check(app.state == "calibrate", "focus return requires fresh stable hands")
	app.buttons["calibration_keyboard"].pressed.emit()
	check(app.state == "tutorial" and app.input_mode == "keyboard", "camera setup offers usable keyboard fallback")
	app._begin_countdown()
	check(app.labels["countdown_hint"].text.contains("A = left"), "keyboard countdown has relevant instructions")
	app._start_round()
	app.input_mode = "camera"
	hands()
	# Initial connection/session change intentionally pauses until a fresh hold.
	app.stable_hands=1.0
	app.setup_complete=true
	app._continue_round()
	app.tracker.command("round", {"active":true})
	var old_ids: Array = app.tracker.pending.keys()
	hands("restarted")
	check(app.state == "paused" and app.automatic_recovery, "fast tracker restart pauses for clean recovery")
	for old_id in old_ids:
		check(not app.tracker.pending.has(old_id), "old session command discarded")
	app.stable_hands=1.0
	check(app._hands_visible(), "fresh heartbeat accepted")
	app.tracker.last_seen -= .6
	check(not app._hands_visible(), "stale heartbeat cannot keep hands ready")
	var config := ConfigFile.new()
	config.set_value("audio","volume",{"bad":true})
	config.set_value("audio","audio_offset",NAN)
	config.set_value("audio","camera_latency",99.0)
	config.set_value("game","best_score",-10)
	config.set_value("game","chart","kick")
	config.save("user://release_test_settings.cfg")
	app._load_settings("user://release_test_settings.cfg")
	check(app.volume == .8 and app.audio_offset == 0.0, "malformed settings fall back safely")
	check(app.camera_latency == .25 and app.best_score == 0 and app.chart_key == "sweet_rally", "settings clamp and removed track migrates")
	DirAccess.remove_absolute("user://release_test_settings.cfg")
	app._return_title()
	app._start_intro("keyboard")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(.8).timeout
	app._tick_dialogue(.1)
	check(not app.bob_audio.playing and app.intro_music.stream_paused, "focus loss during fade cannot start speech or music")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	app._tick_dialogue(.1)
	check(app.bob_audio.playing and not app.intro_music.stream_paused, "return from fade resumes intro cleanly")
	app._return_title()
	app.queue_free()
	await process_frame
	await create_timer(.2).timeout
	print("RELEASE_POLISH_TESTS ", JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
