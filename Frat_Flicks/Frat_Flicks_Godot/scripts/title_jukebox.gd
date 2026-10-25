extends Control
## Native record-deck carousel. Playlist changes are driven by real song endings.
const UI = preload("res://scripts/ui_theme.gd")
const PLAYLIST_PATH := "res://assets/audio/title_playlist.json"
var tracks: Array[Dictionary] = []
var streams: Array[AudioStream] = []
var audio: AudioStreamPlayer
var current_index := 0
var display_index := 0
var slide := 0.0
var spin := 0.0
var active := false
var paused := false
var animating := false
var advance_pending := false
var animation: Tween
var controls: Array[Button] = []
var pause_button: Button
var start_button: Button
var error_message := ""
var volume_level := 0.8

func _ready() -> void:
	clip_contents = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	audio = AudioStreamPlayer.new()
	audio.name = "TitlePlaylistAudio"
	add_child(audio)
	audio.finished.connect(_song_finished)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLAYLIST_PATH))
	if parsed is Array:
		for entry in parsed:
			if not entry is Dictionary or not ResourceLoader.exists(str(entry.get("path", ""))):
				continue
			var stream: AudioStream = load(str(entry["path"]))
			if stream == null or stream.get_length() <= 0.0:
				continue
			tracks.append(entry)
			streams.append(stream)
	if tracks.is_empty():
		error_message = "No title tracks found. Check title_playlist.json."
	controls.append(_button("< PREV", Rect2(336, 184, 112, 40), func(): step(-1)))
	pause_button = _button("PAUSE", Rect2(464, 184, 112, 40), toggle_pause)
	controls.append(pause_button)
	controls.append(_button("NEXT >", Rect2(592, 184, 112, 40), func(): step(1)))
	for button in controls:
		button.disabled = tracks.is_empty()
	set_volume(volume_level)

func _button(text: String, rect: Rect2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_override("font", UI.DISPLAY)
	button.add_theme_font_size_override("font_size", 12)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color.TRANSPARENT if state == "focus" else Color("681414") if state == "hover" else Color("250909") if state in ["pressed", "disabled"] else UI.MAROON
		box.border_color = UI.CREAM if state == "focus" else Color(UI.CREAM, 0.35)
		box.set_border_width_all(2 if state == "focus" else 1)
		box.set_corner_radius_all(8)
		button.add_theme_stylebox_override(state, box)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, UI.CREAM)
	button.add_theme_color_override("font_disabled_color", Color(UI.CREAM, 0.45))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	add_child(button)
	return button

func set_volume(value: float) -> void:
	volume_level = clampf(value, 0.0, 1.0)
	if audio != null:
		audio.volume_db = linear_to_db(maxf(volume_level, 0.0001)) - 8.0

func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	if not active:
		audio.stop()
		paused = false
		pause_button.text = "PAUSE"
		if animation != null and animation.is_valid():
			animation.kill()
		animating = false
		advance_pending = false
		display_index = current_index
		slide = 0.0
		_set_controls(false)
	elif not streams.is_empty():
		_play_current()
	queue_redraw()

func _play_current() -> void:
	paused = false
	pause_button.text = "PAUSE"
	audio.stream_paused = false
	audio.stream = streams[current_index]
	audio.play()

func toggle_pause() -> void:
	if not active or streams.is_empty():
		return
	paused = not paused
	audio.stream_paused = paused
	pause_button.text = "PLAY" if paused else "PAUSE"
	queue_redraw()

func _song_finished() -> void:
	if active and not paused:
		if animating:
			advance_pending = true
		else:
			step(1)

func step(direction: int) -> void:
	if not active or streams.is_empty() or animating:
		return
	var turn := 1 if direction >= 0 else -1
	current_index = posmod(current_index + turn, tracks.size())
	_play_current()
	animating = true
	_set_controls(true)
	animation = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	animation.tween_property(self, "slide", float(turn), 0.52)
	animation.tween_callback(_finish_slide)

func _finish_slide() -> void:
	display_index = current_index
	slide = 0.0
	animating = false
	_set_controls(false)
	if advance_pending:
		advance_pending = false
		_song_finished()

func _set_controls(disabled: bool) -> void:
	for button in controls:
		button.disabled = disabled or tracks.is_empty()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if active and not paused:
		spin = fmod(spin + delta * 1.5, TAU)
	queue_redraw()

func _draw() -> void:
	_draw_start_button()
	if tracks.is_empty():
		draw_string(UI.BODY, Vector2(240, 96), error_message, HORIZONTAL_ALIGNMENT_CENTER, 560, 16, UI.CREAM)
		return
	# Paint the distant decks first; the current/arriving deck is always in front.
	var order: Array[int] = [-2, 2, -1, 1, 0]
	if slide > 0.5:
		order = [-2, 2, -1, 0, 1]
	elif slide < -0.5:
		order = [-2, 2, 1, 0, -1]
	for offset in order:
		var distance := float(offset) - slide
		if absf(distance) > 1.8:
			continue
		var center := Vector2(520 + distance * 360, 88)
		var depth := clampf(1.0 - absf(distance), 0.0, 1.0)
		var zoom := lerpf(0.84, 1.0, depth)
		var index := posmod(display_index + offset, tracks.size())
		draw_set_transform(center, distance * 0.035, Vector2.ONE * zoom)
		_deck(index, depth)
	draw_set_transform(Vector2.ZERO)

func _deck(index: int, depth: float) -> void:
	var opacity := lerpf(0.42, 1.0, depth)
	var ink := Color(UI.CREAM, opacity)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("341415").lerp(Color("500000"), depth * 0.35)
	style.border_color = Color(UI.CREAM, lerpf(0.15, 0.7, depth))
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	draw_style_box(style, Rect2(-184, -88, 368, 176))
	var disc_spin := spin if active and index == current_index else 0.0
	var disc := Vector2(-104, 4)
	draw_circle(disc, 56, Color("130b0e"))
	for ring in [28, 36, 44, 52]:
		draw_arc(disc, ring, 0, TAU, 64, Color(UI.CREAM, 0.09 * opacity), 1.0, true)
	for arc in 2:
		var angle := disc_spin + arc * PI
		draw_arc(disc, 48, angle, angle + 0.65, 20, Color(UI.CREAM, 0.23 * opacity), 2.0, true)
	draw_circle(disc, 20, UI.MAROON)
	draw_circle(disc + Vector2.from_angle(disc_spin) * 12, 3, ink)
	draw_circle(disc, 3, UI.CREAM)
	draw_line(Vector2(-36, -52), Vector2(-44, 0), ink, 3.0, true)
	draw_line(Vector2(-44, 0), Vector2(-66, 20), ink, 3.0, true)
	draw_circle(Vector2(-36, -52), 4, ink)
	draw_string(UI.BODY, Vector2(-24, -48), str(tracks[index].get("artist", "")), HORIZONTAL_ALIGNMENT_LEFT, 188, 12, ink)
	draw_string(UI.BODY, Vector2(-24, -12), str(tracks[index]["name"]), HORIZONTAL_ALIGNMENT_LEFT, 188, 20, ink)
	draw_string(UI.DISPLAY, Vector2(-24, 12), "%02d / %02d" % [index + 1, tracks.size()], HORIZONTAL_ALIGNMENT_LEFT, 188, 12, Color(UI.CREAM, opacity * 0.7))
	var position := audio.get_playback_position() if index == current_index else 0.0
	var length := streams[index].get_length()
	var fraction := clampf(position / length, 0.0, 1.0)
	draw_rect(Rect2(-24, 28, 184, 4), Color(UI.CREAM, opacity * 0.15))
	draw_rect(Rect2(-24, 28, 184 * fraction, 4), ink)
	var state_text := ("PAUSED" if paused else "NOW PLAYING") if active and index == current_index else ("PREVIOUS" if index == posmod(current_index - 1, tracks.size()) else "UP NEXT")
	draw_string(UI.DISPLAY, Vector2(-24, 56), state_text, HORIZONTAL_ALIGNMENT_LEFT, 188, 12, ink)
	draw_string(UI.DISPLAY, Vector2(100, 56), "%02d:%02d" % [int(position) / 60, int(position) % 60], HORIZONTAL_ALIGNMENT_LEFT, 64, 12, ink)

func _draw_start_button() -> void:
	if start_button == null:
		return
	# Paint with the same continuously refreshed canvas as the carousel. The
	# native Button remains the keyboard/mouse/accessibility interaction target.
	var rect := Rect2(start_button.position - position, start_button.size)
	var color := UI.MAROON
	if start_button.get_draw_mode() == BaseButton.DRAW_PRESSED:
		color = Color("380000")
	elif start_button.is_hovered():
		color = Color("681414")
	draw_rect(rect, color)
	draw_rect(rect, UI.CREAM, false, 4.0)
	draw_string(UI.DISPLAY, rect.position + Vector2(0, 40), "PRESS START", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 24, UI.CREAM)
	if start_button.has_focus():
		draw_rect(rect.grow(4), Color(UI.CREAM, 0.6), false, 1.0)

func _exit_tree() -> void:
	if animation != null and animation.is_valid():
		animation.kill()
	if is_instance_valid(audio):
		audio.stop()
