extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.test_mode = false # Exercise production audio-clock branch, not injected dt.
	app._begin_keyboard()
	var recorder := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, recorder)
	recorder.set_recording_active(true)
	app._begin_countdown()
	var labels_seen: Dictionary = {"3": 0.0}
	var started := Time.get_ticks_msec()
	while app.state == "countdown" and Time.get_ticks_msec() - started < 8000:
		app._tick_countdown(0.001) # Deliberately wrong dt; playback must own timing.
		var digit: String = app.labels["countdown"].text
		if not labels_seen.has(digit):
			labels_seen[digit] = app.countdown_elapsed
		await process_frame
	var passed: bool = app.state == "playing" and labels_seen.has("2") and labels_seen.has("1")
	passed = passed and float(labels_seen.get("2", 0.0)) >= 1.0 and float(labels_seen.get("2", 9.0)) < 1.1
	passed = passed and float(labels_seen.get("1", 0.0)) >= 2.0 and float(labels_seen.get("1", 9.0)) < 2.1
	passed = passed and app.countdown_elapsed >= 3.0 and app.countdown_elapsed < 3.1
	await create_timer(0.55).timeout
	recorder.set_recording_active(false)
	var recording := recorder.get_recording()
	if recording != null:
		recording.save_to_wav("/tmp/frat_countdown_mixed.wav")
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	print("COUNTDOWN_AUDIO_CLOCK ", JSON.stringify({"success": passed, "digits_at_audio_seconds": labels_seen, "song_at_audio_seconds": app.countdown_elapsed}))
	app._return_title()
	app.tracker.close()
	app.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	quit(0 if passed else 1)
