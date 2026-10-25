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
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.test_mode = true
	for key in app.SONG_KEYS:
		app._select_song(key)
		app._start_intro("keyboard")
		await create_timer(.8).timeout
		var expected := "res://assets/audio/title_music/%s.mp3" % key
		check(app.intro_music.stream.resource_path == expected, "selected song under Bob: " + key)
		check(app.intro_music.playing and app.bob_audio.playing, "song and narration play together")
		check(not app.music.playing and not app.title_jukebox.active, "no gameplay or carousel audio overlap")
		check(is_equal_approx(app.intro_music.volume_db, app.bob_audio.volume_db - 18.0), "music stays quieter than narration")
		app._tick_dialogue(100)
		var position: float = app.intro_music.get_playback_position()
		app._next_dialogue()
		await process_frame
		check(app.intro_music.playing and app.intro_music.get_playback_position() >= position, "next page does not restart song")
		app._tick_dialogue(.01)
		app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		check(app.intro_music.stream_paused and app.bob_audio.stream_paused, "focus pauses both")
		app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		check(not app.intro_music.stream_paused, "focus resumes background song")
		app.intro_music.seek(app.intro_music.stream.get_length() - .05)
		await create_timer(.3).timeout
		check(app.intro_music.playing and app.intro_music.get_playback_position() < .5, "short song loops during dialogue")
		app.dialogue_page = 6
		app._set_dialogue_page()
		app._tick_dialogue(100)
		app._finish_intro()
		check(app.intro_music.playing and not app.bob_audio.playing, "begin keeps song and stops narration")
		await create_timer(.8).timeout
		check(app.state == "tutorial" and app.intro_music.playing, "song continues through instructions")
		app._show("calibrate")
		check(app.intro_music.playing and app.intro_music.stream.resource_path == expected, "selected song continues in two-second setup")
		app.intro_music.seek(app.intro_music.stream.get_length() - .05)
		await create_timer(.3).timeout
		check(app.intro_music.playing and app.intro_music.get_playback_position() < .5, "setup background loops while waiting for hands")
		app._show("title")
		app._show("calibrate")
		check(app.intro_music.playing, "direct/retry hand setup starts background")
		app._begin_countdown()
		check(not app.intro_music.playing, "countdown has no background song")
		app._start_round()
		check(app.music.playing and app.music.get_playback_position() < .1, "game song starts from zero")
		app._return_title()
		check(not app.intro_music.playing, "title return stops background")
	app.tracker.close()
	app.queue_free()
	await process_frame
	await create_timer(.2).timeout
	print("INTRO_MUSIC_TESTS ", JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
