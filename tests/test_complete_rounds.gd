extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.test_mode = true
	var failures: Array[String] = []
	for key in app.SONG_KEYS:
		app._select_song(key)
		app.input_mode = "keyboard"
		app.demo = true
		app.practice = false
		app.music.pitch_scale = 4.0 # Speed the real decoder, not the song clock.
		app._start_round()
		var started := Time.get_ticks_msec()
		while app.state == "playing" and Time.get_ticks_msec()-started < 70000:
			await process_frame
		if app.state != "results" or not app.result_won or app.judge.hits != app.judge.beats.size() or app.judge.misses != 0:
			failures.append(key)
		print("COMPLETE_SONG ", JSON.stringify({"song":key,"hits":app.judge.hits,"misses":app.judge.misses,"won":app.result_won}), " ", Time.get_ticks_msec()-started)
		app._return_title()
	app._select_song("sweet_rally")
	app.demo=false
	app._start_round()
	var started := Time.get_ticks_msec()
	while app.state == "playing" and Time.get_ticks_msec()-started < 15000:
		await process_frame
	if app.state != "results" or app.result_won or app.judge.misses != 9:
		failures.append("no-input loss")
	print("COMPLETE_ROUNDS_TESTS ", JSON.stringify({"failures":failures}))
	app._return_title()
	app.queue_free()
	await process_frame
	await create_timer(.3).timeout
	quit(0 if failures.is_empty() else 1)
