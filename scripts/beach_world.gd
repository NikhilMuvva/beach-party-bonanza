extends Node2D
## Music-clock animation with symmetric, center-anchored wave lanes.
const Judge = preload("res://scripts/rhythm_judge.gd")
const UI = preload("res://scripts/ui_theme.gd")

const BEACH = preload("res://assets/art/sunset_beach.jpg")
const INTRO = preload("res://assets/art/intro_atlas.png")
const WAVE = preload("res://assets/art/wave_incoming.png")
const CRASH = preload("res://assets/art/wave_crash.png")
const HandArt = preload("res://scripts/hand_art.gd")
const CYAN := UI.CYAN
const GOLD := UI.GOLD
const CREAM := UI.CREAM
const STARTS := {"down": Vector2(256, 272), "up": Vector2(1024, 272)}
const TARGETS := {"down": Vector2(352, 488), "up": Vector2(928, 488)}

var mode := "title"
var elapsed := 0.0
var intro_elapsed := 0.0
var scenery: Sprite2D
var scenery_material: ShaderMaterial
var clock := 0.0
var beats: Array = []
var status := PackedByteArray()
var effects: Array[Dictionary] = []
var hand_flash := {"L": 0.0, "R": 0.0}
var hand_progress := {"L": 0.0, "R": 0.0}
var hand_y := {"L": 0.5, "R": 0.5}
var miss_flash := 0.0
var vibe := 1.0
var hand_sprites: Dictionary = {}
var intro_durations: Array = []
var intro_total := 0.0

func _ready() -> void:
	var animation: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/intro_animation.json"))
	intro_durations = animation["durations"]
	for duration in intro_durations:
		intro_total += float(duration)
	# Animate only the scenery: slow palm sway and ocean drift leave UI untouched.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scenery = Sprite2D.new()
	scenery.texture = BEACH
	scenery.position = Vector2(640, 360)
	scenery.scale = Vector2(1280.0 / BEACH.get_width(), 720.0 / BEACH.get_height())
	scenery.z_index = -10
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
	uniform float scene_time = 0.0;
	void fragment() {
		vec2 uv = UV;
		float water = smoothstep(0.50, 0.56, uv.y) * (1.0 - smoothstep(0.76, 0.84, uv.y));
		water *= smoothstep(0.18, 0.25, uv.x);
		uv.x += sin(uv.y * 120.0 + scene_time * 1.6) * 0.009 * water;
		uv.y += sin(uv.x * 24.0 - scene_time * 1.25) * 0.005 * water;
		float palm = (1.0 - smoothstep(0.10, 0.22, uv.x)) * smoothstep(0.28, 0.44, uv.y) * (1.0 - smoothstep(0.70, 0.88, uv.y));
		uv.x += sin(scene_time * 0.9) * 0.010 * palm;
		COLOR = texture(TEXTURE, clamp(uv, vec2(0.0), vec2(1.0)));
	}"""
	scenery_material = ShaderMaterial.new()
	scenery_material.shader = shader
	scenery.material = scenery_material
	add_child(scenery)
	for hand in ["L", "R"]:
		var sprite := Sprite2D.new()
		sprite.texture = HandArt.pose(hand, false)
		sprite.centered = false
		sprite.scale = Vector2.ONE * HandArt.DISPLAY_SCALE
		sprite.material = HandArt.material()
		sprite.flip_h = false
		sprite.z_index = 3
		add_child(sprite)
		hand_sprites[hand] = sprite

func _process(delta: float) -> void:
	elapsed += delta
	if mode == "intro":
		intro_elapsed += delta
	scenery.visible = mode not in ["title", "intro"]
	scenery_material.set_shader_parameter("scene_time", elapsed)
	for hand in hand_flash:
		hand_flash[hand] = maxf(0.0, hand_flash[hand] - delta)
	miss_flash = maxf(0.0, miss_flash - delta * 2.0)
	var effect_delta := delta if mode == "playing" else 0.0
	for i in range(effects.size() - 1, -1, -1):
		effects[i]["life"] -= effect_delta
		if effects[i]["life"] <= 0.0:
			effects.remove_at(i)
	for hand in hand_sprites:
		_update_hand(hand)
	queue_redraw()

func flash(hand: String, hit: bool = false) -> void:
	hand_flash[hand] = 0.24
	if hit:
		var lane: String = "down" if hand == "L" else "up"
		effects.append({"lane": lane, "life": 0.6, "duration": 0.6, "hit": true})

func miss(lane: String) -> void:
	miss_flash = 0.18
	effects.append({"lane": lane, "life": 0.4, "duration": 0.4, "hit": false})

func _draw() -> void:
	if mode == "title":
		_draw_arcade_background()
		return
	if mode == "intro":
		_draw_intro()
		return
	_draw_ocean_glints()
	_draw_animated_surf()
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.04, 0.08, 0.15, 0.25))
	# A quiet top and bottom scrim keeps the HUD legible over sunset pixels.
	for i in 24:
		var alpha := 0.65 * pow(1.0 - float(i) / 24.0, 2)
		draw_rect(Rect2(0, i * 7, 1280, 7), Color(0.025, 0.055, 0.09, alpha))
		draw_rect(Rect2(0, 720 - (i + 1) * 5, 1280, 5), Color(0.025, 0.055, 0.09, alpha))
	if mode in ["playing", "paused", "countdown"]:
		_draw_lanes()
		_draw_notes()
		_draw_effects()
	if miss_flash > 0.0:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0.9, 0.25, 0.2, miss_flash))

func intro_frame(at_time: float) -> int:
	var remaining := fmod(at_time, maxf(intro_total, 0.01))
	var frame := 0
	for duration in intro_durations:
		if remaining < float(duration):
			break
		remaining -= float(duration)
		frame += 1
	return mini(frame, intro_durations.size() - 1)

func _draw_intro() -> void:
	var frame := intro_frame(intro_elapsed)
	var region := Rect2((frame % 6) * 512, (frame / 6) * 280, 512, 280)
	# Show Bob unobscured; the dialogue covers only the lower part of the scene.
	draw_texture_rect_region(INTRO, Rect2(0, 0, 1280, 700), region)
	draw_rect(Rect2(0, 700, 1280, 20), Color("102232"))
	for strip in 12:
		draw_rect(Rect2(0, strip * 8, 1280, 8), Color(0.025, 0.055, 0.09, 0.52 * (1.0 - strip / 12.0)))

func _draw_arcade_background() -> void:
	# Original arcade scene inspired by the supplied layout, with Aggie colors.
	draw_rect(Rect2(0, 0, 1280, 720), Color("200708"))
	for band in 48:
		var t := band / 48.0
		var color := Color("200708").lerp(Color("500000"), pow(t, 2.0))
		draw_rect(Rect2(0, band * 10, 1280, 10), color)
	for i in 52:
		var x := float((i * 179 + 52) % 1240 + 20)
		var y := float((i * 79 + 28) % 420 + 20)
		var alpha := 0.18 + 0.24 * pow(0.5 + 0.5 * sin(elapsed * 0.7 + i * 2.4), 4.0)
		draw_rect(Rect2(x, y, 2, 2), Color(CREAM, alpha))
		if i % 13 == 0:
			draw_line(Vector2(x - 4, y + 1), Vector2(x + 6, y + 1), Color(GOLD, alpha * 0.7), 1.0)
			draw_line(Vector2(x + 1, y - 4), Vector2(x + 1, y + 6), Color(GOLD, alpha * 0.7), 1.0)
	draw_rect(Rect2(0, 472, 1280, 248), Color("21090b"))
	for x in range(-1280, 2561, 160):
		draw_line(Vector2(640 + (x - 640) * 0.04, 472), Vector2(x, 720), Color(CREAM, 0.12), 1.0, true)
	for i in 12:
		var progress := fmod(i / 12.0 + elapsed * 0.025, 1.0)
		var y := 472.0 + progress * progress * 248.0
		draw_line(Vector2(0, y), Vector2(1280, y), Color(CREAM, 0.06 + progress * 0.12), 1.0, true)
	draw_line(Vector2(0, 472), Vector2(1280, 472), Color(CREAM, 0.35), 2.0)

func _draw_ocean_glints() -> void:
	for i in 20:
		var x := float((i * 173 + 80) % 1248 + 16)
		if x < 272.0:
			continue
		var y := float(368 + (i * 37) % 192)
		var phase := 0.5 + 0.5 * sin(elapsed * 1.2 + i * 1.7)
		var alpha := pow(phase, 6.0) * 0.50
		draw_rect(Rect2(x + sin(elapsed * 0.9 + i) * 16.0, y, 12, 2), Color(CREAM, alpha))
		if i % 4 == 0:
			draw_rect(Rect2(x + 4, y - 4, 2, 10), Color(GOLD, alpha * 0.8))

func _draw_animated_surf() -> void:
	# Wide, low-contrast foam ribbons make water motion visible at normal scale.
	for row in 4:
		var points := PackedVector2Array()
		for x in range(272, 1297, 16):
			var y := 380.0 + row * 48.0 + sin(x * 0.010 + elapsed * (1.3 + row * 0.12)) * 6.0
			y += sin(x * 0.025 - elapsed * 0.9) * 3.0
			points.append(Vector2(x, y))
		draw_polyline(points, Color(CREAM, 0.14 + row * 0.015), 2.0, true)

func _draw_lanes() -> void:
	for lane in ["down", "up"]:
		var color := CYAN
		var start: Vector2 = STARTS[lane]
		var target: Vector2 = TARGETS[lane]
		for i in range(1, 13):
			var t := float(i) / 13.0
			var p := start.lerp(target, t * t)
			draw_circle(p, 1.0 + t * 1.6, Color(color, 0.12 + t * 0.12))
		var pulse := _beat_emphasis(lane)
		draw_circle(target, 65, Color(0.025, 0.06, 0.10, 0.52))
		draw_arc(target, 65, 0, TAU, 72, Color(color, 0.55 + pulse * 0.25), 2.5, true)
		draw_arc(target, 73 + pulse * 3, PI * 0.13, PI * 0.86, 40, Color(color, 0.18), 1.5, true)
		draw_line(target + Vector2(-8, 0), target + Vector2(8, 0), Color(color, 0.4), 1.5)
		draw_line(target + Vector2(0, -8), target + Vector2(0, 8), Color(color, 0.4), 1.5)

func _beat_emphasis(lane: String) -> float:
	var emphasis := 0.0
	for beat in beats:
		if beat["lane"] == lane:
			emphasis = maxf(emphasis, 1.0 - smoothstep(0.0, 0.15, absf(float(beat["t"]) - clock)))
	return emphasis

func wave_rect(center: Vector2, scale_value: float, swell: float, mirrored: bool) -> Rect2:
	# Compute size first, then anchor BOTH axes around the same target center.
	var dimensions := Vector2(160.0 * swell, 104.0 / swell) * scale_value
	var rect := Rect2(center - dimensions * 0.5, dimensions)
	if mirrored:
		rect.position.x += rect.size.x
		rect.size.x = -rect.size.x
	return rect

func note_center(lane: String, progress: float) -> Vector2:
	# Continue along the same curve through the ring; never clamp at the beat.
	return STARTS[lane].lerp(TARGETS[lane], pow(maxf(progress, 0.0), 2.0))

func _draw_notes() -> void:
	for i in beats.size():
		if i >= status.size() or status[i] != 0:
			continue
		var beat: Dictionary = beats[i]
		var offset := float(beat["t"]) - clock
		var progress := 1.0 - offset / Judge.TRAVEL_TIME
		if progress < 0.0 or offset < -Judge.HIT_WINDOW:
			continue
		var lane: String = beat["lane"]
		var amount := clampf(progress, 0.0, 1.0)
		var center := note_center(lane, progress)
		var emphasis := 1.0 - smoothstep(0.0, 0.15, absf(offset))
		var scale_value := lerpf(0.16, 1.0, amount) * (1.0 + emphasis * 0.24)
		var color := CYAN
		var alpha := minf(1.0, progress * 5.0)
		if emphasis > 0.0:
			for ring in range(4, 0, -1):
				draw_circle(center, (48.0 + ring * 8.0) * scale_value, Color(color, 0.024 * emphasis))
			draw_arc(center, 60.0 * scale_value, 0, TAU, 64, Color(color, 0.7 * emphasis), 2.0, true)
		# Swell changes size, never the center. Freeze animation with the music.
		var swell := 1.0 + sin(clock * 8.0 + i) * 0.04
		# Canvas reflection preserves the center; negative destination sizes do not
		# mirror texture regions consistently across Godot rendering backends.
		var dest := wave_rect(Vector2.ZERO, scale_value, swell, false)
		draw_set_transform(center, 0.0, Vector2(-1.0 if lane == "up" else 1.0, 1.0))
		draw_texture_rect_region(WAVE, dest, Rect2(7, 399, 1238, 602), Color(1.0, 1.0, 1.0, alpha))
		draw_set_transform(Vector2.ZERO)
		if emphasis > 0.0:
			for droplet in 3:
				var phase := fmod(clock * 2.0 + droplet / 3.0, 1.0)
				draw_circle(center + Vector2((droplet - 1) * 24, -40 - sin(phase * PI) * 16) * scale_value, 2.0 * scale_value, Color(color, (1.0 - phase) * emphasis))

func _draw_effects() -> void:
	for effect in effects:
		var lane: String = effect["lane"]
		var life := float(effect["life"])
		var t := 1.0 - life / float(effect["duration"])
		var p: Vector2 = TARGETS[lane]
		var color := CYAN
		if not effect["hit"]:
			color = Color("ff947d")
		draw_arc(p, 65 + t * 58, 0, TAU, 64, Color(color, 1.0 - t), 3.0 * (1.0 - t), true)
		if effect["hit"]:
			draw_string(UI.DISPLAY, p + Vector2(-80, -80 - t * 65), str(effect.get("message", "+1")), HORIZONTAL_ALIGNMENT_CENTER, 160, 20, Color(color, 1.0 - t))
			for i in 10:
				var angle := float(i) / 10 * TAU
				var pos := p + Vector2.from_angle(angle) * (30 + t * 100)
				draw_rect(Rect2(pos, Vector2(5, 5) * (1.0 - t)), Color(color, 1.0 - t))
			if t < 0.55:
				draw_texture_rect_region(CRASH, Rect2(p - Vector2(82, 78), Vector2(164, 138)), Rect2(8, 309, 1241, 821), Color(1, 1, 1, (1.0 - t * 1.8) * 0.8))

func _update_hand(hand: String) -> void:
	var sprite: Sprite2D = hand_sprites[hand]
	sprite.visible = mode in ["playing", "paused", "countdown"]
	var wrist := Vector2(128 if hand == "L" else 1152, 664)
	var raised := float(hand_flash[hand]) > 0.0 or float(hand_progress[hand]) > 0.7
	sprite.texture = HandArt.pose(hand, raised)
	var lift := float(hand_flash[hand]) / 0.24 * 8.0
	wrist.y += clampf((float(hand_y[hand]) - 0.5) * 24, -8, 8) - lift
	sprite.position = wrist - HandArt.WRIST_ANCHORS[hand] * HandArt.DISPLAY_SCALE
