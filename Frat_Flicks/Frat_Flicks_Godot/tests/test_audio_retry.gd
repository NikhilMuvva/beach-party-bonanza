extends SceneTree
const Judge = preload("res://scripts/rhythm_judge.gd")
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
	for offset in [-0.30, -0.30, 0.30, 0.30]:
		var judge = Judge.new()
		judge.configure([{"t": 2.0, "lane": "down"}], true)
		var hit: Dictionary = judge.flick("L", 2.0 + offset)
		check(not hit.is_empty() and hit["points"] == 1 and hit["close_hit"], "forgiving near hit earns one")
		check(is_equal_approx(judge.accuracy(), 0.9) and judge.misses == 0, "near hit counts as ninety percent accuracy")
		check(judge.flick("L", 2.0 + offset).is_empty(), "near hit cannot score twice")
	for offset in [-0.301, 0.301]:
		var judge = Judge.new()
		judge.configure([{"t": 2.0, "lane": "down"}], true)
		check(judge.flick("L", 2.0 + offset).is_empty(), "outside enlarged window still rejected")
	var perfect = Judge.new()
	perfect.configure([{"t": 2.0, "lane": "down"}], true)
	check(perfect.flick("L", 2.05)["perfect"] and perfect.score == 2, "perfect timing unchanged")
	var judge = Judge.new()
	judge.configure([{"t": 1.0, "lane": "down"}, {"t": 2.0, "lane": "up"}], true)
	judge.flick("R", 2.20)
	check(judge.take_misses() == [0], "expiry inside flick reports its miss")
	check(judge.take_misses().is_empty(), "miss drain is exactly once")
	check(is_equal_approx(judge.accuracy(), 0.45), "miss and ninety-percent hit use weighted accuracy")
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.test_mode = true
	check(app.splash_audio.stream.resource_path.ends_with("water_splash.mp3"), "supplied splash is connected")
	check(app.countdown_audio.stream.resource_path.ends_with("countdown.mp3"), "supplied countdown is connected")
	app._begin_keyboard()
	app._start_round()
	app.judge.configure([{"t": 1.0, "lane": "down"}, {"t": 1.0, "lane": "up"}, {"t": 2.0, "lane": "down"}], true)
	app.judge.expire(1.31)
	app._drain_misses()
	check(app.splash_events == 2 and app.world.effects.size() == 2, "each simultaneous miss triggers its splash and effect")
	app._drain_misses()
	check(app.splash_events == 2, "miss sound never duplicates")
	app._flick("L", 2.20)
	check(app.splash_events == 2 and app.labels["feedback"].text.contains("90%"), "close hit has ninety-percent feedback and no miss sound")
	for won in [true, false]:
		app._finish(won)
		app.buttons["result_retry"].pressed.emit()
		check(app.state == "countdown" and not app.demo, "win/loss retry goes directly to a real countdown")
		check(app.judge.score == 0 and app.judge.misses == 0 and app.audio_time == 0.0, "retry resets round score and song")
		check(app.countdown_audio.playing and not app.music.playing, "countdown clip plays before song")
		app._tick_countdown(1.0)
		check(app.labels["countdown"].text == "2", "second cue shows two")
		app._tick_countdown(1.0)
		check(app.labels["countdown"].text == "1", "third cue shows one")
		app._tick_countdown(1.0)
		check(app.state == "playing" and app.music.playing, "final cue starts fresh song")
	app._finish(false)
	app.buttons["result_title_screen"].pressed.emit()
	check(app.state == "title" and not app.music.playing and not app.countdown_audio.playing, "title button is separate and silences countdown")
	app._begin_keyboard()
	app._start_round()
	app._finish(false)
	app.input_mode = "camera"
	app.tracker.online = false
	app._restart_round()
	check(app.state == "calibrate" and app.judge.score == 0, "camera retry waits for hands without replaying story")
	check(not app.countdown_audio.playing, "countdown cannot sound before camera setup is ready")
	app._return_title()
	app._begin_keyboard()
	app._begin_countdown()
	app.input_mode = "camera"
	app._tick_countdown(0.5)
	check(app.state == "calibrate" and not app.countdown_audio.playing, "hand loss cancels sound along with countdown")
	app.tracker.close()
	app.music.stop()
	app.countdown_audio.stop()
	app.splash_audio.stop()
	app.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("AUDIO_RETRY_TESTS ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
