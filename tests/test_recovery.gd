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

func hands(visible: bool, camera_ready: bool = true, age: float = 0.0) -> void:
	app.tracker.accept_packet({"protocol": 1, "session": "recovery-test", "type": "state", "camera_ready": camera_ready, "frame_age_ms": age, "hands": {"L": {}, "R": {}} if visible else {}, "calibration": {}})

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.test_mode = true
	app._begin_keyboard()
	app._start_round()
	app.audio_time = 2.0
	app.last_audio_time = 2.0
	app.music.seek(2.0)
	app._flick("L", 2.0)
	var score: int = app.judge.score
	var hits: int = app.judge.hits
	var status: PackedByteArray = app.judge.status.duplicate()
	app.world.clock = 2.0
	app.input_mode = "camera"
	hands(false)
	app._process(0.016)
	check(app.state == "paused" and app.automatic_recovery, "missing hands automatically pause")
	check(app.music.stream_paused, "song freezes during hand loss")
	for i in 20:
		hands(false)
		app._process(0.25)
	check(app.state == "paused" and app.audio_time == 2.0, "waiting keeps clock frozen indefinitely")
	check(app.judge.score == score and app.judge.misses == 0, "waiting cannot penalize score or streak")
	hands(true)
	app._process(0.25)
	check(app.state == "paused", "hands must settle before recovery")
	hands(true)
	app._process(0.25)
	check(app.state == "countdown" and app.countdown == 3.0, "both hands start three-second recovery countdown")
	app._process(1.0)
	check(app.labels["countdown"].text == "2" and app.music.stream_paused, "countdown displays two while audio stays paused")
	app._on_camera_flick("R", 0.0)
	check(app.judge.hits == hits, "countdown never scores input")
	hands(false)
	app._process(0.1)
	check(app.state == "paused" and app.countdown == 3.0, "hand loss cancels countdown and resets all three seconds")
	hands(true)
	app._process(0.5)
	check(app.state == "countdown", "reappearing hands automatically retry")
	for i in 2:
		hands(true)
		app._process(1.0)
	check(app.state == "countdown" and app.labels["countdown"].text == "1", "full countdown cannot resume early")
	hands(true)
	app._process(1.0)
	check(app.state == "playing" and not app.music.stream_paused, "three seconds resume existing song")
	check(app.audio_time == 2.0 and app.world.clock == 2.0, "resume keeps music and wave positions")
	check(app.judge.score == score and app.judge.status == status, "resume never reloads chart or resets score")
	app._on_camera_flick("R", 0.1)
	check(app.judge.hits == hits, "pre-resume queued camera events rejected")
	hands(true, true, 501.0)
	app._process(0.016)
	check(app.state == "paused", "stale frames cannot masquerade as tracked hands")
	hands(true, false)
	app._process(1.0)
	check(app.state == "paused", "disconnected camera never starts countdown")
	hands(true)
	app._process(0.5)
	check(app.state == "countdown", "camera recovery resumes detection without a button")
	app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(app.state == "paused" and not app.automatic_recovery, "focus loss cancels automatic countdown")
	app._switch_keyboard_resume()
	check(app.state == "playing" and app.input_mode == "keyboard", "keyboard fallback remains usable")
	app._pause("Manual pause")
	hands(true)
	app._process(1.0)
	check(app.state == "paused", "manual pause remains manual")
	# Symmetry and anchor checks cover every swell phase and both handedness paths.
	for scale_value in [0.16, 1.0, 1.24]:
		for swell in [0.96, 1.0, 1.04]:
			for lane in ["down", "up"]:
				var target: Vector2 = app.world.TARGETS[lane]
				var rect: Rect2 = app.world.wave_rect(target, scale_value, swell, lane == "up")
				check(rect.get_center().is_equal_approx(target), "wave remains centered during swell / " + lane)
				check(app.world.note_center(lane, 1.0).is_equal_approx(target), "on-beat center matches ring")
				check(app.world.note_center(lane, 1.08).y > target.y, "late wave continues past ring")
	check(app.world.TARGETS["down"].x + app.world.TARGETS["up"].x == 1280, "wave lanes mirror around screen center")
	check(app.screens["playing"].get_node("CameraFrame").position.y == 216, "camera moved up onto grid")
	check(not FileAccess.get_file_as_string("res://scripts/beach_world.gd").contains("beach_party.jpg"), "corner photograph removed from renderer")
	app.tracker.close()
	app.music.stop()
	app.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("RECOVERY_TESTS ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
