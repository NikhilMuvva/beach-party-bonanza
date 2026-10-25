extends SceneTree
## Run after import: godot --headless --path . --script tests/test_runner.gd
const Judge = preload("res://scripts/rhythm_judge.gd")
const Bridge = preload("res://scripts/tracker_bridge.gd")
var checks := 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for variant in ["sweet_rally", "paradise", "make_u_whole", "eatin_good", "free_your_mind"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/beatmaps/%s.json" % variant))
		var beats: Array = data["beats"]
		check(beats.size() > 10, "supplied chart note count")
		var judge = Judge.new()
		check(judge.configure(beats), "chart validates")
		for run_number in 5:
			judge.configure(beats)
			for beat in beats:
				var hand := "L" if beat["lane"] == "down" else "R"
				var result: Dictionary = judge.flick(hand, float(beat["t"]))
				check(not result.is_empty(), "full chart hit %s / %d" % [variant, run_number])
			judge.expire(300.0)
			check(judge.hits == beats.size() and judge.misses == 0 and not judge.lost, "full run exact score")
			check(judge.best_combo == beats.size() and is_equal_approx(judge.vibe, 1.0), "full run combo/vibe")
		judge.configure(beats)
		judge.expire(300.0)
		check(judge.lost and judge.misses == 9, "ninth unmitigated miss loses")
		judge.configure(beats, true)
		judge.expire(300.0)
		check(not judge.lost and judge.misses == beats.size() and judge.vibe == 0.0, "practice resolves whole chart")
	var one := [{"t": 2.0, "lane": "down"}, {"t": 3.0, "lane": "up"}]
	for offset in [-0.30, 0.0, 0.30]:
		var judge = Judge.new()
		judge.configure(one)
		check(not judge.flick("L", 2.0 + offset).is_empty(), "inclusive hit window boundary %.3f" % offset)
		check(judge.flick("L", 2.0 + offset).is_empty(), "one note scores only once")
	var judge = Judge.new()
	judge.configure(one)
	check(judge.flick("L", 1.699).is_empty(), "early flick ignored")
	check(judge.flick("R", 2.0).is_empty(), "wrong physical hand cannot hit wave")
	check(not judge.flick("L", 2.0).is_empty(), "correct hand after wrong-hand input")
	check(judge.flick("L", 3.0).is_empty(), "wrong physical hand cannot hit gull")
	check(not judge.flick("R", 3.0).is_empty(), "correct right-hand gull")
	judge.configure(one)
	judge.expire(2.30)
	check(judge.misses == 0, "target remains pending at positive boundary")
	judge.expire(2.301)
	check(judge.misses == 1, "miss after boundary")
	judge.configure([{"t": 1.0, "lane": "down"}, {"t": 1.0, "lane": "up"}])
	check(not judge.flick("L", 1.0).is_empty() and not judge.flick("R", 1.0).is_empty(), "simultaneous two-hand notes")
	for bad in [[], [{"t": -1.0, "lane": "up"}], [{"t": "NaN", "lane": "up"}], [{"t": 2.0, "lane": "bogus"}], [{"t": 2.0, "lane": "up"}, {"t": 1.0, "lane": "up"}]]:
		check(not Judge.new().configure(bad), "reject malformed chart")
	await test_protocol()
	await test_ui()
	# Audio playback resources are released by the mixer on its next buffer.
	await create_timer(0.1).timeout
	print("GODOT_TESTS ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func test_protocol() -> void:
	var bridge = Bridge.new()
	var received: Array = []
	bridge.flick_received.connect(func(hand, age): received.append([hand, age]))
	var now := Time.get_unix_time_from_system()
	var heartbeat := {"protocol": 1, "session": "test", "type": "state", "hands": {}, "calibration": {}}
	bridge.accept_packet(heartbeat)
	var event := {"protocol": 1, "session": "test", "type": "flick", "id": "1", "hand": "L", "captured_unix": now}
	bridge.accept_packet(event)
	bridge.accept_packet(event)
	check(received.size() == 1, "duplicate UDP events ignored")
	event["id"] = "2"
	event["hand"] = "R"
	bridge.accept_packet(event)
	check(received.size() == 2 and received[1][0] == "R", "independent simultaneous protocol inputs")
	event["id"] = "3"
	event["captured_unix"] = now - 2.0
	bridge.accept_packet(event)
	check(received.size() == 2, "stale camera packet rejected")
	event["session"] = "old-session"
	event["captured_unix"] = now
	bridge.accept_packet(event)
	check(received.size() == 2, "old session rejected")
	bridge.free()

func test_ui() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var app = packed.instantiate()
	root.add_child(app)
	await process_frame
	app.test_mode = true
	check(app.state == "title" and app.screens.size() == 9, "complete UI instantiated")
	check(not app.buttons.has("capture_down"), "manual calibration removed")
	app._open_settings()
	check(app.state == "settings", "settings reachable")
	app._close_settings()
	check(app.state == "title", "settings returns to title")
	app._begin_keyboard()
	check(app.state == "tutorial" and app.input_mode == "keyboard", "explicit keyboard tutorial")
	app._begin_countdown()
	check(app.state == "countdown", "countdown reachable")
	app._start_round()
	check(app.state == "playing" and app.music.playing, "music and round start together")
	app.audio_time = float(app.judge.beats[0]["t"])
	app._flick("L", app.audio_time)
	check(app.judge.hits == 1 and app.labels["score"].text == "002", "real HUD reflects hit")
	check(app.judge.lane_scores["L"] == 2 and app.judge.perfect_streak == 1, "perfect left earns two")
	var scoring = Judge.new()
	scoring.configure([{"t": 1.0, "lane": "down"}, {"t": 2.0, "lane": "up"}, {"t": 3.0, "lane": "down"}, {"t": 4.0, "lane": "up"}], true)
	scoring.flick("L", 1.0)
	scoring.flick("R", 2.04)
	check(scoring.score == 4 and scoring.perfect_streak == 2, "consecutive perfects award +2 independently")
	scoring.flick("L", 3.10)
	check(scoring.score == 5 and scoring.perfect_streak == 0 and scoring.lane_scores["L"] == 3, "ordinary hit earns one and resets perfect streak")
	scoring.expire(4.46)
	check(scoring.perfect_streak == 0 and scoring.misses == 1, "miss ends perfect streak")
	app._pause("Test pause")
	var frozen_clock: float = app.audio_time
	await process_frame
	check(app.state == "paused" and app.music.stream_paused and app.audio_time == frozen_clock, "pause freezes both music and judge clock")
	app._resume()
	check(app.state == "playing" and not app.music.stream_paused, "resume")
	app._finish(true)
	check(app.state == "results" and app.labels["result_title"].text == "VIBE SURVIVED.", "win screen")
	app._finish(false)
	check(app.labels["result_title"].text == "VIBE KILLED.", "lose screen")
	app._return_title()
	check(app.state == "title" and not app.music.playing, "replay returns to title")
	app._begin_camera()
	check(app.state == "calibrate", "camera path reaches calibration")
	app._begin_countdown()
	check(app.state == "calibrate", "missing camera cannot begin gameplay")
	app.tracker.close()
	app.queue_free()
	await process_frame
