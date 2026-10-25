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
	root.size = Vector2i(1280, 720)
	var judge = Judge.new()
	for offset in [-0.30, -0.30, 0.30, 0.30]:
		judge.configure([{"t": 2.0, "lane": "down"}], true)
		var hit: Dictionary = judge.flick("L", 2.0 + offset)
		check(not hit.is_empty() and hit["close_hit"] and hit["quality"] == 0.9, "new expanded range accepts near hits")
	judge.configure([{"t": 2.0, "lane": "down"}], true)
	check(judge.flick("L", 1.699).is_empty(), "outside new range remains rejected")
	judge.configure([{"t": 1.0, "lane": "down"}, {"t": 1.1, "lane": "down"}], true)
	check(judge.flick("L", 1.09)["index"] == 1, "overlapping windows pick nearest wave")
	check(judge.status[0] == 0, "nearest later hit leaves earlier wave pending")
	check(judge.flick("L", 1.29)["index"] == 0, "earlier pending wave remains hittable inside grace")
	check(judge.hits == 2, "both overlapping notes score exactly once")
	judge.configure([{"t": 1.0, "lane": "down"}, {"t": 1.4, "lane": "down"}], true)
	check(judge.flick("L", 1.2)["index"] == 0, "ties choose earliest note predictably")
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.test_mode = true
	var box = app.title_jukebox
	check(box.tracks.size() == 5 and box.audio.playing and box.active, "title autoplays five supplied MP3 tracks")
	var before: float = box.spin
	await create_timer(0.15).timeout
	check(box.spin > before, "record visibly rotates during playback")
	box.pause_button.pressed.emit()
	check(box.paused and box.audio.stream_paused and box.pause_button.text == "PLAY", "pause button works")
	before = box.spin
	await create_timer(0.12).timeout
	check(is_equal_approx(box.spin, before), "record stops spinning while paused")
	box.pause_button.pressed.emit()
	check(not box.paused and not box.audio.stream_paused, "play resumes track")
	box.controls[2].pressed.emit()
	check(box.current_index == 1 and box.animating, "next selects track and slides decks")
	await create_timer(0.6).timeout
	check(box.display_index == 1 and not box.animating, "slide settles on selected track")
	box.controls[0].pressed.emit()
	await create_timer(0.6).timeout
	check(box.current_index == 0 and box.display_index == 0, "previous returns to prior song")
	# End every actual MP3 decoder, including the last-to-first loop.
	for expected in [1, 2, 3, 4, 0]:
		box.audio.seek(box.audio.stream.get_length() - 0.05)
		await create_timer(0.8).timeout
		check(box.current_index == expected and box.audio.playing, "actual song completion advances to " + str(expected))
	check(box.tracks[0]["name"] == "sweet rally" and box.tracks[4]["name"] == "Free Your Mind", "uploaded titles are displayed correctly")
	check(box.tracks[4]["artist"] == "Prospa, Cloonee, Sybil", "actual artist metadata retained")
	app._open_settings()
	check(box.active and box.audio.playing, "playlist continues through title settings")
	app._close_settings()
	box.set_volume(0.25)
	check(box.volume_level == 0.25, "playlist supports existing volume preference")
	app.input_mode = "keyboard"
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = app.buttons["press_start"].get_global_rect().get_center()
	click.pressed = true
	app.get_viewport().push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	app.get_viewport().push_input(click, true)
	await process_frame
	check(app.transitioning, "actual mouse click reaches Press Start")
	check(not box.active and not box.audio.playing, "press start immediately silences title playlist")
	await create_timer(0.75).timeout
	check(app.state == "intro" and not box.audio.playing, "title songs do not leak into Bob dialogue")
	app._return_title()
	check(box.active and box.audio.playing and not box.animating, "returning to title restarts usable carousel")
	box.step(1)
	app._begin_keyboard()
	check(not box.active and not box.audio.playing and not box.animating, "leaving mid-slide safely stops animation and music")
	app.tracker.close()
	app.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("JUKEBOX_TESTS ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
