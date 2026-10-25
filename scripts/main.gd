extends Node2D
## App flow and presentation. Scoring lives in rhythm_judge.gd; tracking is IPC.
const Judge = preload("res://scripts/rhythm_judge.gd")
const Preview = preload("res://scripts/hand_preview.gd")
const HandArt = preload("res://scripts/hand_art.gd")
const COUNTDOWN_AUDIO = preload("res://assets/audio/countdown.mp3")
const SPLASH_AUDIO = preload("res://assets/audio/water_splash.mp3")
const COUNTDOWN_LEAD_IN := 0.0251
const Jukebox = preload("res://scripts/title_jukebox.gd")
const Wordmark = preload("res://scripts/arcade_wordmark.gd")
const UI = preload("res://scripts/ui_theme.gd")
const FONT = UI.BODY
const BOLD = UI.DISPLAY
const CREAM := UI.CREAM
const MUTED := UI.MUTED
const CYAN := UI.CYAN
const GOLD := UI.GOLD
const RED := UI.RED
const INK := UI.INK

@onready var world = $BeachWorld
@onready var music: AudioStreamPlayer = $Music
@onready var tracker = $TrackerBridge
@onready var layer: CanvasLayer = $Interface

var title_jukebox: Control
var screens: Dictionary = {}
var state := "title"
var previous_screen := "title"
var input_mode := "camera"
const SONG_KEYS := ["sweet_rally", "paradise", "make_u_whole", "eatin_good", "free_your_mind"]
const SONG_NAMES := ["sweet rally", "Paradise", "Make U Whole", "Eatin’ Good", "Free Your Mind"]
var song_selectors: Array[OptionButton] = []
var chart_key := "sweet_rally"
var practice := false
var demo := false
var quit_after_round := false
var test_mode := false
var camera_latency := 0.080
var audio_offset := 0.0
var volume := 0.8
var judge = Judge.new()
var chart: Dictionary = {}
var audio_time := 0.0
var last_audio_time := 0.0
var song_length := 62.0
var audio_finished := false
var audio_tail := 0.0
const INITIAL_CALIBRATION_TIME := 2.0
const HAND_SETTLE_TIME := 0.5
const BOB_DIALOGUE := [
	"Howdy, bros, and welcome to Frat Flicks! We are throwing the most epic Aggie beach party, complete with maroon cups of sweet tea.",
	"But we've got a situation, and you'll have to save the party using just your laptop webcam—no gaming gear or controllers needed!",
	"First things first, to set your baseline, just rest your elbows on the table and hold your hands still for 2 seconds to calibrate.",
	"Once the track starts, it's go time. When you see a wave trying to crash the vibe, flick your hands UP to knock it out!",
	"You gotta keep the rhythm, because every time you miss, you lose 10 to 15 percent on the vibe meter.",
	"Don't panic though, hitting streaks will regenerate your vibe.",
	"If that meter hits zero, it's 'Vibe Killed' and the party is totally busted. But if you can survive until the song ends, you win!"
]
var setup_complete := false
var calibration_anchors: Dictionary = {}
const BACKGROUND_MUSIC_STATES := ["intro", "tutorial", "calibrate"]
var intro_music: AudioStreamPlayer
var bob_audio: AudioStreamPlayer
var bob_voice_clips: Array[AudioStream] = []
var bob_voice_pending := false
var bob_focus_paused := false
var app_focused := true
var dialogue_page := 0
var dialogue_characters := 0.0
var transitioning := false
var quitting := false
var fade_overlay: ColorRect
var fade_tween: Tween
var best_score := 0
const RECOVERY_COUNTDOWN := 3.0
var countdown_elapsed := 0.0
var countdown_audio: AudioStreamPlayer
var splash_audio: AudioStreamPlayer
var splash_events := 0
var countdown_starts := 0
var countdown := RECOVERY_COUNTDOWN
var countdown_resumes := false
var automatic_recovery := false
var input_enabled_at := 0.0
var stable_hands := 0.0
var missing_hands := 0.0
var heartbeat_timer := 0.0
var tracker_process := -1
var tracker_start_time := -100.0
var owned_tracker := false
var external_tracker := false
var result_won := false
var last_feedback := 0.0
var labels: Dictionary = {}
var buttons: Dictionary = {}
var previews: Array = []
var vibe_bar: ProgressBar
var song_bar: ProgressBar
var calibration_bar: ProgressBar
var pause_reason := "Take a breath. The beach can wait."
var settings_controls: Dictionary = {}
var status_notice := ""

func _ready() -> void:
	get_tree().auto_accept_quit = false
	var args := OS.get_cmdline_user_args()
	test_mode = "--test-mode" in args
	external_tracker = "--external-tracker" in args
	if not test_mode:
		_load_settings()
		_fit_starting_window()
	if "--keyboard" in args:
		input_mode = "keyboard"
	for argument in args:
		if argument.begins_with("--chart=") and argument.get_slice("=", 1) in SONG_KEYS:
			chart_key = argument.get_slice("=", 1)
	practice = practice or "--practice" in args
	demo = "--autoplay" in args
	quit_after_round = "--quit-after-round" in args
	tracker.flick_received.connect(_on_camera_flick)
	tracker.state_received.connect(_on_tracker_state)
	tracker.connection_changed.connect(_on_connection_changed)
	music.finished.connect(_on_music_finished)
	_build_audio()
	_build_interface()
	_load_chart()
	_show("title")
	if demo:
		input_mode = "keyboard"
		_start_round()

func _process(delta: float) -> void:
	if quitting:
		return
	title_jukebox.set_volume(volume)
	bob_audio.volume_db = linear_to_db(maxf(volume, 0.0001))
	intro_music.volume_db = linear_to_db(maxf(volume, 0.0001)) - 18.0
	tracker.poll()
	heartbeat_timer += delta
	if heartbeat_timer >= 2.0:
		heartbeat_timer = 0.0
		if tracker.online:
			tracker.command("ping")
	var hands: Dictionary = tracker.state.get("hands", {}) if tracker.online else {}
	if app_focused and _hands_visible():
		stable_hands = minf(3.0, stable_hands + delta)
		missing_hands = 0.0
	else:
		stable_hands = 0.0
		missing_hands += delta
		calibration_anchors.clear()
	for preview in previews:
		preview.hands = hands
		preview.is_online = tracker.online and tracker.state.get("camera_ready", false)
		preview.queue_redraw()
	if state == "intro":
		_tick_dialogue(delta)
	elif state == "calibrate" and app_focused:
		_update_calibration()
	elif state == "paused" and automatic_recovery and app_focused:
		_update_recovery()
	elif state == "countdown":
		_tick_countdown(delta)
	elif state == "playing":
		if input_mode == "camera" and not _hands_visible():
			_pause("Show both hands. The song will continue automatically.", true)
			return
		_update_clock(delta)
		if demo:
			_autoplay()
		judge.expire(_judge_clock())
		_drain_misses()
		world.clock = audio_time
		world.status = judge.status
		world.vibe = judge.vibe
		_update_hud()
		if judge.lost:
			_finish(false)
		elif audio_finished and _judge_clock() > float(judge.beats.back()["t"]) + Judge.HIT_WINDOW + 0.002:
			_finish(true)
	_update_status()

func _update_clock(delta: float) -> void:
	var position: float
	if audio_finished:
		audio_tail += delta
		position = song_length + audio_tail + audio_offset
	else:
		position = music.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency() + audio_offset
	# Godot's audio thread may report a small backwards step between mixes.
	audio_time = maxf(last_audio_time, maxf(0.0, position))
	last_audio_time = audio_time

func _judge_clock() -> float:
	return audio_time - (camera_latency if input_mode == "camera" else 0.0)

func _on_camera_flick(hand: String, age: float) -> void:
	if state != "playing" or input_mode != "camera" or demo or not _hands_visible():
		return
	# Ignore camera events captured before the countdown completed.
	if Time.get_unix_time_from_system() - age < input_enabled_at:
		return
	_update_clock(0.0)
	# The slider estimates the entire capture/inference delay; measured age is
	# a lower bound, rather than a second delay to add to the slider.
	_flick(hand, audio_time - maxf(camera_latency, age))

func _flick(hand: String, event_time: float) -> void:
	if state != "playing":
		return
	var result: Dictionary = judge.flick(hand, event_time)
	_drain_misses()
	world.flash(hand, not result.is_empty())
	world.status = judge.status
	if not result.is_empty():
		var message := "Perfect!  +2" if result["perfect"] else "90%  CLOSE HIT  +1" if result["close_hit"] else "+1  NICE FLICK"
		_feedback(message, CYAN)
		world.effects.back()["message"] = "Perfect! +2" if result["perfect"] else "90% +1" if result["close_hit"] else "+1"
		labels["timing"].text = "%+d ms" % int(float(result["offset"]) * 1000.0)
	elif judge.last_attempt_penalized:
		_feedback("OFF BEAT  /  -3% VIBE", RED)
		labels["timing"].text = "One deliberate flick per wave."
	_update_hud()

func _build_audio() -> void:
	intro_music = AudioStreamPlayer.new()
	intro_music.name = "SelectedSongIntroMusic"
	add_child(intro_music)
	intro_music.finished.connect(_on_intro_music_finished)
	bob_audio = AudioStreamPlayer.new()
	bob_audio.name = "BobNarration"
	add_child(bob_audio)
	for i in BOB_DIALOGUE.size():
		bob_voice_clips.append(load("res://assets/audio/bob/bob_%02d.mp3" % (i + 1)))
	countdown_audio = AudioStreamPlayer.new()
	countdown_audio.name = "CountdownAudio"
	countdown_audio.stream = COUNTDOWN_AUDIO
	add_child(countdown_audio)
	splash_audio = AudioStreamPlayer.new()
	splash_audio.name = "MissSplashAudio"
	splash_audio.stream = SPLASH_AUDIO
	splash_audio.max_polyphony = 16
	add_child(splash_audio)

func _on_intro_music_finished() -> void:
	if state in BACKGROUND_MUSIC_STATES and app_focused:
		intro_music.play()

func _drain_misses() -> void:
	var expired: Array[int] = judge.take_misses()
	for index in expired:
		world.miss(judge.beats[index]["lane"])
		splash_audio.volume_db = linear_to_db(maxf(volume, 0.0001)) - 6.0
		splash_audio.play()
		splash_events += 1
	if not expired.is_empty():
		_feedback("MISSED", RED)

func _autoplay() -> void:
	for i in judge.beats.size():
		if judge.status[i] == 0 and audio_time >= float(judge.beats[i]["t"]):
			var hand := "L" if judge.beats[i]["lane"] == "down" else "R"
			_flick(hand, float(judge.beats[i]["t"]))

func _load_chart() -> bool:
	if chart_key not in SONG_KEYS:
		chart_key = SONG_KEYS[0]
	var chart_path := "res://assets/beatmaps/%s.json" % chart_key
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(chart_path))
	if not parsed is Dictionary or not parsed.get("beats", []) is Array:
		status_notice = "Beatmap could not be loaded. Extract the complete project."
		return false
	chart = parsed
	if not judge.configure(chart["beats"], practice):
		status_notice = "This beatmap contains invalid targets."
		return false
	music.stream = load("res://assets/audio/title_music/%s.mp3" % chart_key)
	if music.stream == null:
		status_notice = "Song could not be loaded. Extract the complete project."
		return false
	song_length = music.stream.get_length()
	world.beats = judge.beats
	world.status = judge.status
	return true

func _transition_to(next: String) -> void:
	if transitioning:
		return
	transitioning = true
	fade_overlay.visible = true
	fade_overlay.modulate.a = 0.0
	fade_tween = create_tween()
	fade_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade_tween.tween_property(fade_overlay, "modulate:a", 1.0, 0.28)
	fade_tween.tween_callback(func(): _show(next))
	fade_tween.tween_property(fade_overlay, "modulate:a", 0.0, 0.36)
	fade_tween.tween_callback(func(): transitioning = false; fade_overlay.visible = false)

func _start_intro(mode: String = "camera") -> void:
	if transitioning or state != "title":
		return
	if not _load_chart():
		return
	intro_music.stream = load("res://assets/audio/title_music/%s.mp3" % chart_key)
	intro_music.volume_db = linear_to_db(maxf(volume, 0.0001)) - 18.0
	intro_music.stream_paused = false
	title_jukebox.set_active(false)
	input_mode = mode
	demo = false
	dialogue_page = 0
	world.intro_elapsed = 0.0
	_set_dialogue_page()
	if mode == "camera" and not tracker.online:
		_start_tracker()
	_transition_to("intro")

func _set_dialogue_page() -> void:
	bob_audio.stop()
	bob_voice_pending = true
	dialogue_characters = 0.0
	labels["bob_text"].text = BOB_DIALOGUE[dialogue_page]
	labels["bob_text"].visible_characters = 0
	labels["dialogue_page"].text = "%02d / %02d" % [dialogue_page + 1, BOB_DIALOGUE.size()]
	_update_dialogue_controls()

func _tick_dialogue(delta: float) -> void:
	if transitioning or bob_focus_paused or not app_focused:
		return
	if bob_voice_pending and state == "intro":
		bob_voice_pending = false
		bob_audio.stream = bob_voice_clips[dialogue_page]
		bob_audio.stream_paused = false
		bob_audio.volume_db = linear_to_db(maxf(volume, 0.0001))
		bob_audio.play()
	dialogue_characters = minf(float(BOB_DIALOGUE[dialogue_page].length()), dialogue_characters + delta * 48.0)
	labels["bob_text"].visible_characters = int(dialogue_characters)
	_update_dialogue_controls()

func _update_dialogue_controls() -> void:
	var complete: bool = labels["bob_text"].visible_characters >= BOB_DIALOGUE[dialogue_page].length()
	var last_page := dialogue_page == BOB_DIALOGUE.size() - 1
	buttons["dialogue_next"].visible = not (last_page and complete)
	buttons["dialogue_next"].text = "NEXT >" if complete else "SHOW TEXT >"
	buttons["dialogue_back"].disabled = dialogue_page == 0
	buttons["intro_begin"].visible = last_page and complete

func _next_dialogue() -> void:
	if state != "intro" or transitioning:
		return
	if labels["bob_text"].visible_characters < BOB_DIALOGUE[dialogue_page].length():
		dialogue_characters = float(BOB_DIALOGUE[dialogue_page].length())
		labels["bob_text"].visible_characters = int(dialogue_characters)
		_update_dialogue_controls()
	elif dialogue_page < BOB_DIALOGUE.size() - 1:
		dialogue_page += 1
		_set_dialogue_page()
	else:
		_finish_intro()

func _previous_dialogue() -> void:
	if state == "intro" and not transitioning and dialogue_page > 0:
		dialogue_page -= 1
		_set_dialogue_page()

func _skip_intro() -> void:
	if state != "intro" or transitioning:
		return
	bob_audio.stop()
	bob_voice_pending = false
	_transition_to("tutorial")

func _finish_intro() -> void:
	if state != "intro" or transitioning or dialogue_page != BOB_DIALOGUE.size() - 1 or labels["bob_text"].visible_characters < BOB_DIALOGUE[dialogue_page].length():
		return
	bob_audio.stop()
	bob_voice_pending = false
	_transition_to("tutorial")

func _instructions_ready() -> void:
	if state != "tutorial" or transitioning:
		return
	if input_mode == "camera":
		_begin_camera()
	else:
		_begin_countdown()

func _begin_camera() -> void:
	input_mode = "camera"
	demo = false
	stable_hands = 0.0
	setup_complete = false
	calibration_anchors.clear()
	_show("calibrate")
	if not tracker.online:
		_start_tracker()

func _begin_keyboard() -> void:
	input_mode = "keyboard"
	demo = false
	tracker.command("round", {"active": false})
	_show("tutorial")

func _start_tracker() -> void:
	if test_mode:
		return
	if external_tracker:
		status_notice = "Waiting for the launcher's tracker. Check camera permission and the launcher terminal."
		return
	if tracker_process > 0 and OS.is_process_running(tracker_process):
		status_notice = "Tracker setup is still running. Check its terminal and camera permission."
		return
	if Time.get_ticks_msec() / 1000.0 - tracker_start_time < 4.0:
		return
	tracker_start_time = Time.get_ticks_msec() / 1000.0
	if not tracker.listening:
		status_notice = tracker.error
		return
	var root := ProjectSettings.globalize_path("res://")
	var launcher := root.path_join("launch.py")
	if not FileAccess.file_exists(launcher):
		status_notice = "Run the included Start.command next to the source project to start the tracker."
		return
	var python := "python3" if OS.get_name() != "Windows" else "python"
	for candidate in [root.path_join(".venv311/bin/python"), root.path_join(".venv311/Scripts/python.exe"), "/usr/local/bin/python3", "/opt/homebrew/bin/python3"]:
		if FileAccess.file_exists(candidate):
			python = candidate
			break
	tracker_process = OS.create_process(python, PackedStringArray([launcher, "--tracker-only", "--profile", OS.get_user_data_dir().path_join("flick_calibration.json")]), true)
	owned_tracker = tracker_process > 0
	status_notice = "Starting camera. First setup may take a minute; check the launcher terminal."

func _begin_countdown(resuming: bool = false) -> void:
	if input_mode == "camera" and not _calibration_ready():
		if resuming:
			automatic_recovery = true
			_show("paused")
			_update_recovery()
		else:
			_show("calibrate")
		return
	countdown_resumes = resuming
	countdown = RECOVERY_COUNTDOWN
	countdown_elapsed = 0.0
	if not resuming:
		if not _load_chart():
			_show("title")
			return
		world.clock = 0.0
		world.effects.clear()
	tracker.command("round", {"active": false})
	_update_hud()
	labels["countdown"].text = "3"
	labels["countdown_title"].text = "HANDS FOUND / RESUMING" if resuming else ("KEYBOARD / GET SET" if input_mode == "keyboard" else "HANDS READY / GET SET")
	labels["countdown_hint"].text = "A = left / L = right" if input_mode == "keyboard" else "Keep both hands in view."
	_show("countdown")
	countdown_audio.volume_db = linear_to_db(maxf(volume, 0.0001)) - 4.0
	countdown_audio.play(COUNTDOWN_LEAD_IN)
	countdown_starts += 1

func _tick_countdown(delta: float) -> void:
	if input_mode == "camera" and not _hands_visible():
		countdown = RECOVERY_COUNTDOWN
		if countdown_resumes:
			automatic_recovery = true
			_show("paused")
			_update_recovery()
		else:
			_show("calibrate")
		return
	if test_mode:
		# Deterministic clock injection for synthetic scene tests, without a device.
		countdown_elapsed += delta
	elif countdown_audio.playing:
		var audible := countdown_audio.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency() - COUNTDOWN_LEAD_IN
		countdown_elapsed = maxf(countdown_elapsed, maxf(0.0, audible))
	else:
		# A completed clip must not strand the game if a slow frame skipped GO.
		countdown_elapsed = RECOVERY_COUNTDOWN
	countdown = maxf(0.0, RECOVERY_COUNTDOWN - countdown_elapsed)
	labels["countdown"].text = str(maxi(1, int(ceil(countdown))))
	if countdown <= 0.0:
		if countdown_resumes:
			_continue_round()
		else:
			_start_round()

func _start_round() -> void:
	if not _load_chart():
		_show("title")
		return
	if input_mode == "camera" and not _calibration_ready():
		_show("calibrate")
		return
	setup_complete = true
	automatic_recovery = false
	countdown_resumes = false
	input_enabled_at = Time.get_unix_time_from_system()
	audio_time = 0.0
	last_audio_time = 0.0
	audio_tail = 0.0
	audio_finished = false
	missing_hands = 0.0
	world.clock = 0.0
	world.effects.clear()
	labels["feedback"].text = "FILL THE RING. THEN FLICK."
	labels["feedback"].modulate = Color.WHITE
	labels["timing"].text = ""
	music.stream_paused = false
	music.volume_db = linear_to_db(maxf(volume, 0.001)) - 2.0
	tracker.command("round", {"active": input_mode == "camera"})
	_show("playing")
	music.play()
	_update_hud()

func _pause(reason: String = "Song paused. Resume when you are ready.", tracking_loss: bool = false) -> void:
	if state != "playing":
		return
	pause_reason = reason
	automatic_recovery = tracking_loss
	music.stream_paused = true
	tracker.command("round", {"active": false})
	labels["pause_reason"].text = reason
	labels["pause_title"].text = "LOOKING FOR HANDS" if tracking_loss else "SONG PAUSED"
	buttons["resume"].text = "WAITING FOR BOTH HANDS" if tracking_loss else "RESUME SONG"
	buttons["resume"].disabled = tracking_loss
	_show("paused")

func _hands_visible() -> bool:
	var hands: Dictionary = tracker.state.get("hands", {})
	var packet_age := maxf(0.0, Time.get_ticks_msec() / 1000.0 - tracker.last_seen)
	return tracker.online and tracker.state.get("camera_ready", false) and packet_age + float(tracker.state.get("frame_age_ms", 0.0)) / 1000.0 <= 0.5 and hands.has("L") and hands.has("R")

func _update_recovery() -> void:
	labels["pause_title"].text = "LOOKING FOR HANDS"
	labels["pause_reason"].text = "Show both hands. Your song, score and streak are held."
	buttons["resume"].text = "CHECKING HANDS…" if _hands_visible() else "WAITING FOR BOTH HANDS"
	buttons["resume"].disabled = true
	if _calibration_ready():
		_begin_countdown(true)

func _resume() -> void:
	if state != "paused":
		return
	if input_mode == "camera":
		if not _calibration_ready():
			automatic_recovery = true
			_update_recovery()
			if not tracker.online:
				_start_tracker()
			return
		_begin_countdown(true)
	else:
		_continue_round()

func _continue_round() -> void:
	automatic_recovery = false
	countdown_resumes = false
	missing_hands = 0.0
	input_enabled_at = Time.get_unix_time_from_system()
	tracker.command("round", {"active": input_mode == "camera"})
	music.stream_paused = false
	_show("playing")

func _switch_keyboard_resume() -> void:
	input_mode = "keyboard"
	_resume()

func _on_music_finished() -> void:
	if state in ["playing", "paused"] or (state == "countdown" and countdown_resumes):
		audio_finished = true
		audio_tail = 0.0

func _finish(won: bool) -> void:
	result_won = won
	music.stop()
	tracker.command("round", {"active": false})
	labels["result_eyebrow"].text = "DEMO COMPLETE" if demo else ("YOU SAVED THE BEACH" if won else "THE PARTY NEEDS YOU")
	labels["result_title"].text = "VIBE SURVIVED." if won else "VIBE KILLED."
	labels["result_title"].add_theme_color_override("font_color", CREAM if won else RED)
	labels["result_body"].text = "Both waves cleared. Gig 'em." if won else "Lower both fingers to reset. Find the beat. Come back swinging."
	labels["result_hits"].text = str(judge.hits)
	labels["result_combo"].text = str(judge.best_combo)
	labels["result_accuracy"].text = "%d%%" % int(round(judge.accuracy() * 100))
	labels["result_misses"].text = "%d missed waves  /  %d off-beat flicks  /  %d targets" % [judge.misses, judge.stray_flicks, judge.beats.size()]
	if not demo and judge.score > best_score:
		best_score = judge.score
		labels["best_score"].text = "%06d" % best_score
		if not test_mode:
			_save_settings()
	labels["result_mode"].text = "AUTOPLAY DEMONSTRATION" if demo else ("PRACTICE RUN" if practice else "CAMERA FLICKS" if input_mode == "camera" else "KEYBOARD RUN")
	_show("results")
	if quit_after_round:
		print("ROUND_RESULT ", JSON.stringify({"won": won, "hits": judge.hits, "misses": judge.misses, "targets": judge.beats.size(), "best_combo": judge.best_combo}))
		_quit()

func _restart_round() -> void:
	if state != "results":
		return
	music.stop()
	music.stream_paused = false
	countdown_audio.stop()
	splash_audio.stop()
	demo = false
	automatic_recovery = false
	countdown_resumes = false
	audio_time = 0.0
	last_audio_time = 0.0
	world.clock = 0.0
	world.effects.clear()
	for hand in ["L", "R"]:
		world.hand_flash[hand] = 0.0
	if not _load_chart():
		_return_title()
		return
	if input_mode == "camera" and not _calibration_ready():
		_begin_camera()
	else:
		_begin_countdown()

func _return_title() -> void:
	countdown_audio.stop()
	splash_audio.stop()
	music.stop()
	music.stream_paused = false
	automatic_recovery = false
	countdown_resumes = false
	demo = false
	tracker.command("round", {"active": false})
	_show("title")

func _show(next: String) -> void:
	if next in BACKGROUND_MUSIC_STATES:
		var song_path := "res://assets/audio/title_music/%s.mp3" % chart_key
		if intro_music.stream == null or intro_music.stream.resource_path != song_path:
			intro_music.stream = load(song_path)
		intro_music.volume_db = linear_to_db(maxf(volume, 0.0001)) - 18.0
		if not intro_music.playing:
			intro_music.stream_paused = false
			intro_music.play()
		intro_music.stream_paused = not app_focused
	else:
		intro_music.stop()
	if next != "intro":
		bob_audio.stop()
		bob_voice_pending = false
		bob_focus_paused = false
	title_jukebox.set_active(next == "title" or (next == "settings" and previous_screen == "title"))
	if next not in ["countdown", "playing"]:
		countdown_audio.stop()
	state = next
	for key in screens:
		screens[key].visible = key == next or (key == "playing" and next in ["paused", "countdown"])
	screens[next].move_to_front()
	world.mode = "title" if next == "title" else ("paused" if next == "paused" else next)
	if next == "settings" and previous_screen == "title":
		world.mode = "title"
	if next == "tutorial":
		buttons["instructions_ready"].text = "START ROUND / SPACE" if input_mode == "keyboard" else "SET UP HANDS / SPACE"
	labels["feedback"].visible = next == "playing"
	labels["timing"].visible = next == "playing"
	get_viewport().gui_release_focus()

func _on_tracker_state(data: Dictionary) -> void:
	var hands: Dictionary = data.get("hands", {})
	if state == "calibrate" and hands.has("L") and hands.has("R"):
		for hand in ["L", "R"]:
			var position := Vector2(float(hands[hand].get("x", 0.5)), float(hands[hand].get("y", 0.5)))
			if not calibration_anchors.has(hand):
				calibration_anchors[hand] = position
			elif position.distance_to(calibration_anchors[hand]) > 0.05:
				stable_hands = 0.0
				calibration_anchors.clear()
				break
	for hand in ["L", "R"]:
		var entry: Dictionary = hands.get(hand, {})
		var progress: Array = entry.get("progress", [])
		world.hand_progress[hand] = (float(progress[0]) + float(progress[1])) * 0.5 if progress.size() == 2 else 0.0
		world.hand_y[hand] = float(entry.get("y", 0.5))

func _on_connection_changed(online: bool) -> void:
	if online:
		status_notice = ""
		tracker.command("round", {"active": false})
		if state == "playing" and input_mode == "camera":
			stable_hands = 0.0
			_pause("Tracker reconnected. Hold both hands in view.", true)
	else:
		stable_hands = 0.0

func _calibration_ready() -> bool:
	var required := HAND_SETTLE_TIME if setup_complete else INITIAL_CALIBRATION_TIME
	return tracker.online and tracker.state.get("camera_ready", false) and stable_hands >= required and _hands_visible()

func _update_calibration() -> void:
	calibration_bar.value = minf(1.0, stable_hands / INITIAL_CALIBRATION_TIME) * 100
	if not tracker.online:
		labels["calibration_notice"].text = status_notice if not status_notice.is_empty() else "Connecting the camera. Allow access when prompted."
	elif not tracker.state.get("camera_ready", false):
		labels["calibration_notice"].text = str(tracker.state.get("error", "Waiting for the camera."))
	elif not _hands_visible():
		labels["calibration_notice"].text = "Show both hands. Bob is waiting for your two-second hold."
	else:
		labels["calibration_notice"].text = "Hold still: %.1f / 2.0 seconds" % minf(stable_hands, INITIAL_CALIBRATION_TIME)
	if _calibration_ready():
		setup_complete = true
		_begin_countdown()

func _update_status() -> void:
	var ready: bool = tracker.online and tracker.state.get("camera_ready", false)
	var camera_status := "TRACKER ONLINE" if ready else "CAMERA CONNECTING" if tracker.online else "TRACKER OFFLINE"
	labels["title_status"].text = status_notice if not status_notice.is_empty() else camera_status + "   /   PROCESSED ON YOUR LAPTOP"
	labels["title_status"].add_theme_color_override("font_color", CREAM if ready else Color(CREAM, 0.7))
	var fps := float(tracker.state.get("fps", 0.0)) if tracker.online else 0.0
	var hands: Dictionary = tracker.state.get("hands", {}) if tracker.online else {}
	labels["tracker_stats"].text = "%02d FPS  /  L %s  /  R %s" % [int(fps), "READY" if hands.has("L") else "--", "READY" if hands.has("R") else "--"]
	labels["camera_title"].text = "AGGIE BEACH / LIVE" if ready else "AGGIE BEACH / " + ("KEYBOARD" if input_mode == "keyboard" else "CONNECTING")
	labels["hud_mode"].text = "AUTOPLAY DEMO" if demo else "KEYBOARD" if input_mode == "keyboard" else "CAMERA  /  %d FPS" % int(fps)
	if state == "playing" and Time.get_ticks_msec() / 1000.0 - last_feedback > 0.65:
		labels["feedback"].modulate.a = move_toward(labels["feedback"].modulate.a, 0.0, 0.045)

func _update_hud() -> void:
	labels["left_score"].text = "LEFT  %03d" % judge.lane_scores["L"]
	labels["right_score"].text = "RIGHT  %03d" % judge.lane_scores["R"]
	labels["score"].text = "%03d" % judge.score
	labels["combo"].text = "%02d" % judge.perfect_streak
	labels["vibe_percent"].text = "%d%%" % int(round(judge.vibe * 100.0))
	var color := CYAN if judge.vibe > 0.60 else GOLD if judge.vibe > 0.30 else RED
	var fill: StyleBoxFlat = vibe_bar.get_theme_stylebox("fill")
	fill.bg_color = color
	vibe_bar.value = judge.vibe * 100.0
	song_bar.value = clampf(audio_time / song_length, 0.0, 1.0) * 100
	labels["song_time"].text = "%02d:%02d / %02d:%02d" % [int(audio_time) / 60, int(audio_time) % 60, int(song_length) / 60, int(song_length) % 60]
	labels["hud_practice"].text = "PRACTICE / NO FAIL" if practice else ""

func _feedback(message: String, color: Color) -> void:
	labels["feedback"].text = message
	labels["feedback"].add_theme_color_override("font_color", color)
	labels["feedback"].modulate = Color.WHITE
	last_feedback = Time.get_ticks_msec() / 1000.0

func _unhandled_key_input(event: InputEvent) -> void:
	if transitioning:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode
	if key == 0:
		key = event.keycode
	if key == KEY_F11:
		var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif key == KEY_T:
		tracker.command("preview", {"visible": not tracker.state.get("preview", false)})
	elif key == KEY_ESCAPE:
		if state == "playing":
			_pause()
		elif state == "paused":
			_resume()
		elif state == "settings":
			_close_settings()
		elif state != "title":
			_return_title()
	elif state == "title":
		if key in [KEY_ENTER, KEY_SPACE]:
			_start_intro(input_mode)
		elif key == KEY_K:
			_start_intro("keyboard")
	elif state == "intro" and key in [KEY_ENTER, KEY_SPACE]:
		_next_dialogue()
	elif state == "intro" and key == KEY_LEFT:
		_previous_dialogue()
	elif state == "calibrate":
		if key in [KEY_ENTER, KEY_SPACE] and _calibration_ready():
			setup_complete = true
			_begin_countdown()
	elif state == "tutorial" and key in [KEY_ENTER, KEY_SPACE]:
		_instructions_ready()
	elif state == "playing":
		if key == KEY_P:
			_pause()
		elif input_mode == "keyboard" and not demo:
			_update_clock(0.0)
			if key in [KEY_A, KEY_LEFT, KEY_DOWN]:
				_flick("L", audio_time)
			elif key in [KEY_L, KEY_RIGHT, KEY_UP]:
				_flick("R", audio_time)
	elif state == "paused" and key in [KEY_ENTER, KEY_SPACE, KEY_P]:
		_resume()
	elif state == "results" and key in [KEY_ENTER, KEY_SPACE, KEY_R]:
		_restart_round()
	get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and is_node_ready():
		app_focused = true
		bob_focus_paused = false
		bob_audio.stream_paused = false
		intro_music.stream_paused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and not demo:
		app_focused = false
		stable_hands = 0.0
		calibration_anchors.clear()
		if state in BACKGROUND_MUSIC_STATES:
			bob_focus_paused = true
			bob_audio.stream_paused = true
			intro_music.stream_paused = true
		elif state == "playing":
			_pause("Window paused. Return when you are ready.")
		elif state == "countdown":
			if countdown_resumes:
				automatic_recovery = false
				labels["pause_title"].text = "SONG PAUSED"
				labels["pause_reason"].text = "Window paused. Return when you are ready."
				buttons["resume"].disabled = false
				buttons["resume"].text = "RESUME SONG"
				_show("paused")
			else:
				_return_title()
		elif state == "paused":
			automatic_recovery = false
			buttons["resume"].disabled = false
			buttons["resume"].text = "RESUME SONG"

func _quit() -> void:
	if quitting:
		return
	quitting = true
	if not test_mode:
		_save_settings()
	intro_music.stop()
	bob_audio.stop()
	title_jukebox.set_active(false)
	countdown_audio.stop()
	splash_audio.stop()
	music.stop()
	tracker.command("round", {"active": false})
	tracker.command("shutdown")
	# Allow the audio mixer and camera sidecar to finish their queued shutdown.
	await get_tree().create_timer(0.15).timeout
	if owned_tracker and tracker_process > 0 and OS.is_process_running(tracker_process):
		OS.kill(tracker_process)
	tracker.close()
	get_tree().quit()

func _open_settings() -> void:
	previous_screen = state
	_show("settings")

func _close_settings() -> void:
	if not test_mode:
		_save_settings()
	_load_chart()
	_show(previous_screen)

func _load_settings(path: String = "user://settings.cfg") -> void:
	var config := ConfigFile.new()
	if config.load(path) == OK:
		camera_latency = _safe_setting(config, "audio", "camera_latency", 0.08, 0.0, 0.25)
		audio_offset = _safe_setting(config, "audio", "audio_offset", 0.0, -0.25, 0.25)
		best_score = int(_safe_setting(config, "game", "best_score", 0.0, 0.0, 999999.0))
		volume = _safe_setting(config, "audio", "volume", 0.8, 0.0, 1.0)
		chart_key = str(config.get_value("game", "chart", "sweet_rally"))
		if chart_key not in SONG_KEYS:
			chart_key = "sweet_rally"
		practice = config.get_value("game", "practice", false) == true

func _safe_setting(config: ConfigFile, section: String, key: String, fallback: float, minimum: float, maximum: float) -> float:
	var value: Variant = config.get_value(section, key, fallback)
	if not (value is float or value is int):
		return fallback
	var number := float(value)
	return clampf(number, minimum, maximum) if is_finite(number) else fallback

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "camera_latency", camera_latency)
	config.set_value("audio", "audio_offset", audio_offset)
	config.set_value("audio", "volume", volume)
	config.set_value("game", "chart", chart_key)
	config.set_value("game", "practice", practice)
	config.set_value("game", "best_score", best_score)
	if config.save("user://settings.cfg.tmp") == OK:
		if DirAccess.rename_absolute("user://settings.cfg.tmp", "user://settings.cfg") != OK:
			status_notice = "Could not save settings. Check folder permissions."
	else:
		status_notice = "Could not save settings. Check folder permissions."

# ------------------------- Interface construction -------------------------

func _screen(key: String) -> Control:
	var root := Control.new()
	root.name = key.capitalize()
	root.size = Vector2(1280, 720)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	screens[key] = root
	return root

func _style(color: Color, border: Color = Color.TRANSPARENT, radius: int = UI.RADIUS) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.shadow_color = Color(0.01, 0.025, 0.04, 0.18)
	style.shadow_size = 0
	return style

func _panel(parent: Control, rect: Rect2, color: Color = Color(0.04, 0.09, 0.14, 0.94)) -> Panel:
	var panel := Panel.new()
	rect = UI.rect(rect)
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", _style(color, Color(0.65, 0.8, 0.85, 0.16)))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel

func _label(parent: Control, text: String, rect: Rect2, font_size: int = 18, color: Color = CREAM, bold: bool = false, centered: bool = false, wrapped: bool = false) -> Label:
	var label := Label.new()
	if wrapped:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	rect = UI.rect(rect)
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_override("font", BOLD if bold else FONT)
	label.add_theme_font_size_override("font_size", UI.font_size(font_size))
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", 4)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _body(parent: Control, text: String, rect: Rect2, font_size: int = 17, color: Color = MUTED) -> Label:
	# Enable wrapping before assigning text, so a single-line minimum width is
	# never cached for a paragraph that belongs inside a fixed-width card.
	return _label(parent, text, rect, font_size, color, false, false, true)

func _button(parent: Control, text: String, rect: Rect2, action: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	rect = UI.rect(rect)
	button.position = rect.position
	button.size = rect.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", BOLD)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", INK if primary else CREAM)
	button.add_theme_color_override("font_hover_color", INK if primary else CREAM)
	button.add_theme_color_override("font_pressed_color", INK if primary else CREAM)
	button.add_theme_color_override("font_disabled_color", Color("647783"))
	button.add_theme_stylebox_override("normal", _style(CYAN if primary else Color("1b3445"), Color(0.7, 0.85, 0.9, 0.2), UI.RADIUS))
	button.add_theme_stylebox_override("hover", _style(Color("a2f4eb") if primary else Color("2b4b5d"), CYAN, UI.RADIUS))
	button.add_theme_stylebox_override("pressed", _style(Color("50bcb6") if primary else Color("19303d"), CYAN, UI.RADIUS))
	button.add_theme_stylebox_override("disabled", _style(Color("1b2b38"), Color(0.6, 0.7, 0.7, 0.10), UI.RADIUS))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, GOLD, UI.RADIUS))
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _bar(parent: Control, rect: Rect2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	rect = UI.rect(rect)
	bar.position = rect.position
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _style(Color("203d4c"), Color.TRANSPARENT, 4))
	bar.add_theme_stylebox_override("fill", _style(color, Color.TRANSPARENT, 4))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	bar.size = rect.size
	return bar

func _texture(parent: Control, texture: Texture2D, rect: Rect2) -> TextureRect:
	var control := TextureRect.new()
	control.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	control.texture = texture
	rect = UI.rect(rect)
	control.position = rect.position
	control.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(control)
	control.size = rect.size
	return control

func _header(parent: Control, section: String) -> void:
	_label(parent, "FRAT FLICKS", Rect2(48, 24, 400, 28), 16, CREAM, true)
	_label(parent, section, Rect2(48, 52, 600, 24), 12, CYAN, true)
	_button(parent, "BACK", Rect2(1120, 24, 112, 40), _return_title)

func _build_interface() -> void:
	_build_title()
	_build_intro()
	_build_calibration()
	_build_tutorial()
	_build_countdown()
	_build_hud()
	_build_pause()
	_build_results()
	_build_settings()
	var transition_layer := CanvasLayer.new()
	transition_layer.layer = 20
	add_child(transition_layer)
	fade_overlay = ColorRect.new()
	fade_overlay.size = Vector2(1280, 720)
	fade_overlay.color = Color("0b1424")
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	fade_overlay.visible = false
	transition_layer.add_child(fade_overlay)

func _retro_button(parent: Control, text: String, rect: Rect2, action: Callable) -> Button:
	var button := _button(parent, text, rect, action, true)
	for key in ["normal", "hover", "pressed", "focus"]:
		var box: StyleBoxFlat = button.get_theme_stylebox(key)
		box.set_corner_radius_all(0)
		box.set_border_width_all(4)
		box.border_color = CREAM
		box.shadow_size = 0
		box.bg_color = Color.TRANSPARENT if key == "focus" else (Color("681414") if key == "hover" else Color("380000") if key == "pressed" else UI.MAROON)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, CREAM)
	button.add_theme_font_size_override("font_size", 24)
	return button

func _hand_texture(parent: Control, hand: String, raised: bool, rect: Rect2) -> TextureRect:
	var control := _texture(parent, HandArt.pose(hand, raised), rect)
	control.material = HandArt.material()
	control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return control

func _build_title() -> void:
	var root := _screen("title")
	var wordmark := Wordmark.new()
	wordmark.size = Vector2(1280, 480)
	wordmark.scale = Vector2(0.625, 0.625)
	wordmark.position = Vector2(240, 8)
	root.add_child(wordmark)
	_label(root, "1P / TWO HANDS", Rect2(48, 32, 288, 24), 16, CREAM, true)
	_label(root, "BEST SCORE", Rect2(448, 28, 384, 24), 16, CREAM, true, true)
	labels["best_score"] = _label(root, "%06d" % best_score, Rect2(448, 52, 384, 28), 24, CREAM, true, true)
	_button(root, "SETTINGS", Rect2(1080, 32, 152, 48), _open_settings)
	_label(root, "TEXAS A&M / AGGIE BEACH RHYTHM", Rect2(256, 88, 768, 24), 16, CREAM, true, true)
	_label(root, "PLAY NEXT", Rect2(48, 112, 320, 24), 12, CREAM, true)
	_song_selector(root, Rect2(48, 144, 304, 40))
	_button(root, "USE PREVIEW SONG", Rect2(48, 192, 304, 40), func():
		if not title_jukebox.tracks.is_empty():
			_select_song(str(title_jukebox.tracks[title_jukebox.current_index]["path"]).get_file().get_basename()))
	title_jukebox = Jukebox.new()
	title_jukebox.name = "TitleJukebox"
	title_jukebox.position = Vector2(120, 304)
	title_jukebox.size = Vector2(1040, 224)
	root.add_child(title_jukebox)
	buttons["press_start"] = _retro_button(root, "PRESS START", Rect2(416, 548, 448, 64), func(): _start_intro(input_mode))
	title_jukebox.start_button = buttons["press_start"]
	buttons["press_start"].self_modulate.a = 0.0
	_button(root, "KEYBOARD  [K]", Rect2(416, 628, 216, 44), func(): _start_intro("keyboard"))
	_button(root, "WATCH DEMO", Rect2(648, 628, 216, 44), func(): demo = true; input_mode = "keyboard"; _begin_countdown())
	labels["title_status"] = _label(root, "TRACKER OFFLINE", Rect2(224, 688, 832, 24), 12, MUTED, true, true)
	for control in root.get_children():
		if control is Button and control != buttons["press_start"]:
			for key in ["normal", "hover", "pressed"]:
				var box: StyleBoxFlat = control.get_theme_stylebox(key)
				box.bg_color = Color("681414") if key == "hover" else Color("250909") if key == "pressed" else Color("341415")
				box.border_color = Color(CREAM, 0.35)


func _build_intro() -> void:
	var root := _screen("intro")
	_label(root, "FRAT FLICKS / THE BEACH NEEDS YOU", Rect2(48, 28, 720, 32), 16, CREAM, true)
	_button(root, "TITLE SCREEN", Rect2(1024, 24, 208, 48), _return_title)
	var card := _panel(root, Rect2(48, 464, 1184, 208), Color("102232"))
	var border: StyleBoxFlat = card.get_theme_stylebox("panel")
	border.set_corner_radius_all(4)
	border.set_border_width_all(4)
	border.border_color = CREAM
	var inset := Panel.new()
	inset.position = Vector2(12, 12)
	inset.size = Vector2(1160, 184)
	var inset_style := _style(Color.TRANSPARENT, Color(CREAM, 0.32), 0)
	inset.add_theme_stylebox_override("panel", inset_style)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(inset)
	var speaker := _panel(card, Rect2(28, -20, 144, 40), UI.MAROON)
	_label(speaker, "BOB", Rect2(12, 4, 120, 32), 20, CREAM, true, true)
	labels["bob_text"] = _label(card, "", Rect2(32, 32, 1120, 108), 20, CREAM, false, false, true)
	labels["dialogue_page"] = _label(card, "01 / 07", Rect2(32, 156, 192, 32), 16, MUTED, true)
	buttons["dialogue_skip"] = _button(card, "SKIP INTRO", Rect2(488, 152, 192, 40), _skip_intro)
	buttons["dialogue_back"] = _button(card, "< BACK", Rect2(704, 152, 192, 40), _previous_dialogue)
	buttons["dialogue_next"] = _button(card, "NEXT >", Rect2(920, 152, 232, 40), _next_dialogue, true)
	buttons["intro_begin"] = _retro_button(card, "BEGIN!", Rect2(920, 148, 232, 48), _finish_intro)
	_set_dialogue_page()

func _build_calibration() -> void:
	var root := _screen("calibrate")
	_header(root, "02 / TWO-SECOND HAND SETUP")
	_label(root, "Rest your elbows. Hold still.", Rect2(100, 120, 1080, 60), 36, CREAM, true, true)
	_body(root, "Keep both hands visible and still for 2 seconds. Setup completes automatically.\nThen lower index + middle to arm each hand, and extend them together to flick.", Rect2(232, 192, 820, 64), 18, CREAM)
	var preview := Preview.new()
	preview.position = Vector2(400, 280)
	preview.size = Vector2(480, 270)
	root.add_child(preview)
	previews.append(preview)
	labels["tracker_stats"] = _label(root, "CONNECTING", Rect2(400, 560, 480, 24), 14, CYAN, true, true)
	labels["calibration_notice"] = _label(root, "Allow camera access when prompted.", Rect2(240, 596, 800, 32), 15, GOLD, false, true)
	calibration_bar = _bar(root, Rect2(400, 640, 480, 4), CYAN)
	buttons["calibration_keyboard"] = _button(root, "USE KEYBOARD", Rect2(920, 568, 280, 56), _begin_keyboard)
	_button(root, "RECONNECT", Rect2(80, 568, 240, 56), func(): tracker.command("reconnect"); _start_tracker())

func _build_tutorial() -> void:
	var root := _screen("tutorial")
	_header(root, "01 / HOW TO FLICK")
	var card := _panel(root, Rect2(116, 112, 1048, 552))
	_label(card, "Flick on the beat.", Rect2(40, 24, 968, 56), 35, CREAM, true, true)
	_body(card, "Flick when the obstacle fills its ring. Your left and right hands play independently.", Rect2(72, 88, 908, 44), 18, CREAM)
	_hand_texture(card, "L", true, Rect2(80, 140, 160, 188))
	_texture(card, preload("res://assets/art/wave_incoming.png"), Rect2(232, 160, 132, 124))
	_label(card, "LEFT = WAVES", Rect2(64, 312, 408, 32), 23, CYAN, true, true)
	_label(card, "Keyboard: A / ← / ↓", Rect2(64, 352, 408, 28), 15, MUTED, false, true)
	_hand_texture(card, "R", true, Rect2(612, 140, 160, 188))
	var right_wave := _texture(card, preload("res://assets/art/wave_incoming.png"), Rect2(768, 160, 132, 124))
	right_wave.flip_h = true
	_label(card, "RIGHT = WAVES", Rect2(580, 312, 408, 32), 23, CYAN, true, true)
	_label(card, "Keyboard: L / → / ↑", Rect2(580, 352, 408, 28), 15, MUTED, false, true)
	_body(card, "Lift index + middle together, then lower both to reset. One flick per wave.\nMissed wave: -12% vibe. Off-beat flick: -3%. Hits restore vibe.", Rect2(112, 400, 824, 64), 17, CREAM)
	buttons["instructions_ready"] = _retro_button(card, "SET UP HANDS / SPACE", Rect2(324, 480, 400, 48), _instructions_ready)

func _build_countdown() -> void:
	var root := _screen("countdown")
	var card := _panel(root, Rect2(496, 460, 288, 212), Color(0.04, 0.09, 0.14, 0.98))
	labels["countdown_title"] = _label(card, "HANDS READY / GET SET", Rect2(16, 16, 256, 24), 12, CYAN, true, true)
	labels["countdown"] = _label(card, "3", Rect2(16, 40, 256, 112), 80, CREAM, true, true)
	labels["countdown_hint"] = _label(card, "Keep both hands in view.", Rect2(16, 164, 256, 24), 16, MUTED, false, true)

func _build_hud() -> void:
	var root := _screen("playing")
	var top := _panel(root, Rect2(32, 24, 1216, 104), Color(0.025, 0.065, 0.10, 0.96))
	_label(top, "FRAT FLICKS", Rect2(24, 16, 248, 32), 24, CREAM, true)
	labels["hud_mode"] = _label(top, "CAMERA", Rect2(24, 56, 248, 24), 12, CYAN, true)
	labels["hud_practice"] = _label(top, "", Rect2(24, 80, 248, 16), 12, GOLD)
	_label(top, "POINTS", Rect2(296, 12, 128, 24), 12, MUTED, true)
	labels["score"] = _label(top, "000", Rect2(296, 36, 128, 56), 40, CREAM, true)
	_label(top, "PERFECT STREAK", Rect2(456, 12, 184, 24), 12, MUTED, true)
	labels["combo"] = _label(top, "00", Rect2(456, 36, 160, 56), 40, GOLD, true)
	_label(top, "VIBE", Rect2(672, 12, 128, 24), 12, MUTED, true)
	labels["vibe_percent"] = _label(top, "100%", Rect2(912, 12, 96, 24), 16, CREAM, true)
	vibe_bar = _bar(top, Rect2(672, 48, 336, 16), CYAN)
	_label(top, "KEEP THE RHYTHM", Rect2(672, 72, 336, 20), 12, MUTED)
	_button(top, "PAUSE", Rect2(1040, 28, 152, 48), _pause)
	labels["feedback"] = _label(root, "FILL THE RING. THEN FLICK.", Rect2(256, 144, 768, 40), 24, CREAM, true, true)
	labels["timing"] = _label(root, "", Rect2(448, 184, 384, 24), 12, MUTED, false, true)
	var preview_panel := _panel(root, Rect2(464, 216, 352, 232), Color(0.025, 0.065, 0.10, 0.96))
	preview_panel.name = "CameraFrame"
	labels["camera_title"] = _label(preview_panel, "AGGIE BEACH / LIVE", Rect2(16, 8, 320, 24), 12, CREAM, true, true)
	var preview := Preview.new()
	preview.position = Vector2(16, 36)
	preview.size = Vector2(320, 180)
	preview_panel.add_child(preview)
	previews.append(preview)
	_panel(root, Rect2(224, 560, 256, 104), Color(0.025, 0.065, 0.10, 0.96))
	_panel(root, Rect2(800, 560, 256, 104), Color(0.025, 0.065, 0.10, 0.96))
	labels["left_score"] = _label(root, "LEFT  000", Rect2(224, 568, 256, 40), 24, CYAN, true, true)
	labels["right_score"] = _label(root, "RIGHT  000", Rect2(800, 568, 256, 40), 24, CYAN, true, true)
	_label(root, "CYAN WAVE", Rect2(224, 608, 256, 24), 12, CYAN, true, true)
	_label(root, "CYAN WAVE", Rect2(800, 608, 256, 24), 12, CYAN, true, true)
	_label(root, "[A]  LEFT FLICK", Rect2(224, 636, 256, 24), 12, CREAM, false, true)
	_label(root, "[L]  RIGHT FLICK", Rect2(800, 636, 256, 24), 12, CREAM, false, true)
	song_bar = _bar(root, Rect2(48, 696, 960, 4), GOLD)
	labels["song_time"] = _label(root, "00:00 / 01:02", Rect2(1040, 676, 192, 24), 12, CREAM, false, true)

func _build_pause() -> void:
	var root := _screen("paused")
	var overlay := ColorRect.new()
	overlay.color = Color(0.015, 0.04, 0.07, 0.32)
	overlay.size = Vector2(1280, 720)
	root.add_child(overlay)
	var card := _panel(root, Rect2(288, 460, 704, 220), Color(0.04, 0.09, 0.14, 0.98))
	labels["pause_title"] = _label(card, "SONG PAUSED", Rect2(24, 16, 656, 40), 24, CREAM, true, true)
	labels["pause_reason"] = _label(card, pause_reason, Rect2(24, 60, 656, 40), 16, CREAM, false, true, true)
	buttons["resume"] = _button(card, "RESUME SONG", Rect2(24, 116, 656, 44), _resume, true)
	_button(card, "USE KEYBOARD", Rect2(24, 172, 316, 32), _switch_keyboard_resume)
	_button(card, "TITLE SCREEN", Rect2(364, 172, 316, 32), _return_title)

func _build_results() -> void:
	var root := _screen("results")
	var card := _panel(root, Rect2(168, 112, 948, 536))
	labels["result_eyebrow"] = _label(card, "YOU SAVED THE BEACH", Rect2(40, 28, 868, 32), 14, CYAN, true, true)
	labels["result_title"] = _label(card, "VIBE SURVIVED.", Rect2(24, 80, 896, 88), 58, CREAM, true, true)
	labels["result_body"] = _body(card, "", Rect2(72, 180, 808, 52), 18, CREAM)
	var xs := [79, 363, 647]
	var names := ["CLEAN FLICKS", "BEST STREAK", "HIT RATE"]
	var keys := ["result_hits", "result_combo", "result_accuracy"]
	for i in 3:
		labels[keys[i]] = _label(card, "0", Rect2(xs[i], 258, 220, 71), 46, GOLD if i == 1 else CYAN, true, true)
		_label(card, names[i], Rect2(xs[i], 338, 220, 24), 12, MUTED, true, true)
	labels["result_misses"] = _label(card, "", Rect2(48, 384, 848, 24), 13, MUTED, false, true)
	buttons["result_title_screen"] = _button(card, "TITLE SCREEN", Rect2(200, 436, 264, 56), _return_title)
	buttons["result_retry"] = _button(card, "TRY AGAIN", Rect2(488, 436, 264, 56), _restart_round, true)
	labels["result_mode"] = _label(root, "", Rect2(272, 664, 740, 24), 12, CREAM, true, true)

func _build_settings() -> void:
	var root := _screen("settings")
	var card := _panel(root, Rect2(224, 72, 836, 584))
	_label(card, "Tune the party.", Rect2(32, 20, 768, 56), 36, CREAM, true)
	_label(card, "AUDIO & INPUT", Rect2(36, 96, 740, 24), 12, CYAN, true)
	_slider(card, "Camera delay compensation", 140, 0, 250, camera_latency * 1000, func(v): camera_latency = v / 1000, "ms")
	_slider(card, "Global audio offset", 216, -250, 250, audio_offset * 1000, func(v): audio_offset = v / 1000, "ms")
	_slider(card, "Master volume", 292, 0, 100, volume * 100, func(v): volume = v / 100, "%")
	_label(card, "CHART", Rect2(36, 384, 88, 28), 12, CYAN, true)
	_song_selector(card, Rect2(144, 376, 624, 40))
	var checkbox := CheckBox.new()
	checkbox.position = Vector2(33, 430)
	checkbox.size = Vector2(750, 32)
	checkbox.text = "Practice mode (keep playing at zero vibe)"
	checkbox.button_pressed = practice
	checkbox.add_theme_font_override("font", FONT)
	checkbox.add_theme_font_size_override("font_size", 16)
	checkbox.add_theme_icon_override("checked", preload("res://assets/art/check_on.svg"))
	checkbox.add_theme_icon_override("unchecked", preload("res://assets/art/check_off.svg"))
	checkbox.toggled.connect(func(value): practice = value)
	card.add_child(checkbox)
	_button(card, "SAVE & BACK", Rect2(32, 504, 768, 52), _close_settings, true)
	_body(root, "Camera delay moves input judgments earlier. Audio offset shifts the chart against the music.\nDefaults: 80 ms camera compensation, 0 ms audio offset. F11 toggles fullscreen.", Rect2(228, 664, 836, 48), 12)

func _slider(parent: Control, text: String, y: float, minimum: float, maximum: float, value: float, callback: Callable, unit: String) -> void:
	_label(parent, text, Rect2(36, y, 650, 27), 17, CREAM)
	var amount := _label(parent, "%+d %s" % [int(value), unit] if minimum < 0 else "%d %s" % [int(value), unit], Rect2(644, y, 156, 27), 16, GOLD, true)
	var slider := HSlider.new()
	slider.position = Vector2(38, y + 36)
	slider.size = Vector2(756, 20)
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 1
	slider.value = value
	slider.add_theme_stylebox_override("slider", _style(Color("2d4f5e"), Color.TRANSPARENT, 3))
	slider.add_theme_stylebox_override("grabber_area", _style(CYAN, Color.TRANSPARENT, 3))
	slider.value_changed.connect(func(v): callback.call(v); amount.text = "%+d %s" % [int(v), unit] if minimum < 0 else "%d %s" % [int(v), unit])
	parent.add_child(slider)

func _select_song(key: String) -> void:
	if key not in SONG_KEYS:
		return
	chart_key = key
	for selector in song_selectors:
		selector.selected = SONG_KEYS.find(key)
	if state == "title":
		_load_chart()
	if not test_mode:
		_save_settings()

func _song_selector(parent: Control, rect: Rect2) -> OptionButton:
	var selector := OptionButton.new()
	selector.position = rect.position
	selector.size = rect.size
	selector.fit_to_longest_item = false
	for song_name in SONG_NAMES:
		selector.add_item(song_name)
	selector.selected = SONG_KEYS.find(chart_key)
	selector.add_theme_font_override("font", FONT)
	selector.add_theme_font_size_override("font_size", 16)
	selector.add_theme_color_override("font_color", CREAM)
	selector.add_theme_stylebox_override("normal", _style(UI.MAROON, Color(CREAM, 0.35)))
	selector.add_theme_stylebox_override("hover", _style(Color("681414"), CREAM))
	selector.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, CREAM))
	selector.item_selected.connect(func(index): _select_song(SONG_KEYS[index]))
	parent.add_child(selector)
	song_selectors.append(selector)
	return selector

func _exit_tree() -> void:
	if fade_tween != null and fade_tween.is_valid():
		fade_tween.kill()
	for player in [music, intro_music, bob_audio, countdown_audio, splash_audio]:
		if is_instance_valid(player):
			player.stop()
	if is_instance_valid(tracker):
		tracker.close()

func _fit_starting_window() -> void:
	if DisplayServer.get_name() == "headless" or DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var usable := DisplayServer.screen_get_usable_rect()
	var current := DisplayServer.window_get_size()
	var available := usable.size - Vector2i(32, 64)
	if current.x > available.x or current.y > available.y:
		var scale_factor := minf(float(available.x) / 1280.0, float(available.y) / 720.0)
		var fitted := Vector2i(Vector2(1280, 720) * maxf(0.25, scale_factor))
		DisplayServer.window_set_size(fitted)
		DisplayServer.window_set_position(usable.position + (usable.size - fitted) / 2)
