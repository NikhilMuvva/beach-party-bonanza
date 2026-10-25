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
	check(app.bob_voice_clips.size() == 7, "seven narration pages loaded")
	for clip in app.bob_voice_clips:
		check(clip != null and clip.get_length() > 2.0, "valid spoken audio clip")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/bob/dialogue.json"))
	check(manifest["pages"] == Array(app.BOB_DIALOGUE), "spoken script matches displayed dialogue")
	check(not app.bob_audio.playing, "title has no Bob voice")
	app._start_intro("keyboard")
	check(not app.bob_audio.playing, "narration waits for title fade")
	await create_timer(.8).timeout
	check(app.state == "intro" and app.bob_audio.playing, "first page speaks after fade")
	check(not app.title_jukebox.active, "title music stopped for speech")
	app.set_process(false)
	var first = app.bob_audio.stream
	app._next_dialogue()
	check(app.dialogue_page == 0 and app.bob_audio.stream == first and app.bob_audio.playing, "show text leaves current speech playing")
	app._next_dialogue()
	check(app.dialogue_page == 1 and not app.bob_audio.playing, "next stops old speech immediately")
	app._tick_dialogue(.01)
	check(app.bob_audio.stream == app.bob_voice_clips[1] and app.bob_audio.playing, "next starts matching page voice")
	app._previous_dialogue()
	app._tick_dialogue(.01)
	check(app.dialogue_page == 0 and app.bob_audio.stream == first and app.bob_audio.playing, "back replays matching voice")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(app.bob_audio.stream_paused and app.bob_focus_paused, "focus loss pauses speech")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not app.bob_audio.stream_paused and not app.bob_focus_paused, "return resumes speech")
	app.volume = .25
	app._process(0)
	check(is_equal_approx(app.bob_audio.volume_db, linear_to_db(.25)), "voice follows volume setting")
	for i in 7:
		app.dialogue_page = i
		app._set_dialogue_page()
		app._tick_dialogue(.01)
		check(app.bob_audio.stream == app.bob_voice_clips[i] and app.bob_audio.playing, "page clip plays " + str(i))
		app.bob_audio.seek(app.bob_audio.stream.get_length()-.05)
		await create_timer(.2).timeout
		check(not app.bob_audio.playing and app.dialogue_page == i, "speech ends without auto-advancing " + str(i))
	app._tick_dialogue(100)
	app._finish_intro()
	check(not app.bob_audio.playing and not app.bob_voice_pending, "begin silences narration")
	await create_timer(.8).timeout
	check(app.state == "tutorial" and not app.bob_audio.playing, "no voice leaks into tutorial")
	app._return_title()
	app._start_intro("keyboard")
	await create_timer(.8).timeout
	app._tick_dialogue(.01)
	check(app.dialogue_page == 0 and app.bob_audio.playing, "reopening intro restarts first voice")
	app._return_title()
	check(not app.bob_audio.playing and not app.bob_voice_pending, "title exit clears speech")
	app.tracker.close()
	app.queue_free()
	await process_frame
	await create_timer(.2).timeout
	print("BOB_VOICE_TESTS ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
