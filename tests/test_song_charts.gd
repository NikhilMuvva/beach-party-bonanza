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
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.test_mode = true
	check(Judge.TRAVEL_TIME == 2.4 and Judge.HIT_WINDOW == 0.30, "slower travel and expanded hit allowance")
	check(app.song_selectors[0].item_count == 5, "five playable song/chart choices on title")
	var patterns: Array = []
	for key in app.SONG_KEYS:
		app._select_song(key)
		check(app._load_chart(), "loads " + key)
		check(app.music.stream.resource_path.ends_with(key + ".mp3"), "correct audio " + key)
		check(app.song_selectors[1].selected == app.SONG_KEYS.find(key), "settings mirrors selection")
		check(not patterns.has(app.chart["pattern"]), "distinct phrase pattern " + key)
		patterns.append(app.chart["pattern"])
		var previous := -10.0
		var hands := {"L": -10.0, "R": -10.0}
		app.judge.configure(app.chart["beats"], true)
		for beat in app.chart["beats"]:
			var t := float(beat["t"])
			var hand := "L" if beat["lane"] == "down" else "R"
			check(t - previous >= 0.8499 and t - hands[hand] >= 1.2999, "camera-friendly target spacing")
			check(t >= Judge.TRAVEL_TIME and t < app.song_length - 0.6, "note fits audio and approach")
			var grid_error := 100.0
			for grid_t in app.chart["detected_beats"]:
				grid_error = minf(grid_error, absf(float(grid_t)-t))
			check(grid_error <= 0.061, "target follows detected audio beat")
			check(not app.judge.flick(hand, t).is_empty(), "complete chart playable")
			previous=t
			hands[hand]=t
		check(app.judge.hits == app.chart["beats"].size() and app.judge.misses == 0, "perfect full song run")
		app.input_mode="keyboard"
		app.state = "playing"
		app._finish(true)
		app._restart_round()
		check(app.chart_key == key and app.judge.score == 0, "retry retains selected song")
		app._start_round()
		check(app.music.playing and not app.title_jukebox.active, "game audio starts alone")
		app._finish(true)
		app._return_title()
		check(app.chart_key == key and app.title_jukebox.active, "return retains choice and resumes carousel")
	app.tracker.close()
	app.queue_free()
	await process_frame
	await create_timer(.2).timeout
	print("SONG_CHART_TESTS ", JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
