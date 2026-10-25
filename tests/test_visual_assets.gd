extends SceneTree
const HandArt = preload("res://scripts/hand_art.gd")
const UI = preload("res://scripts/ui_theme.gd")
var failures: Array[String] = []
var checks := 0
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
	app.set_process(false)
	var normal: StyleBoxFlat = app.buttons["press_start"].get_theme_stylebox("normal")
	check(normal.bg_color == UI.MAROON, "press start uses TAMU maroon")
	check(app.buttons["press_start"].get_theme_color("font_color") == UI.CREAM, "maroon button has readable cream text")
	app.world.mode = "playing"
	for hand in ["L", "R"]:
		var side := "left" if hand == "L" else "right"
		var sprite: Sprite2D = app.world.hand_sprites[hand]
		app.world.hand_flash[hand] = 0.0
		app.world.hand_progress[hand] = 0.0
		app.world._update_hand(hand)
		check(sprite.texture.resource_path.ends_with("frat_" + side + "_hand_normal_position.png"), "normal artwork mapped to " + side)
		var before: Vector2 = sprite.position + HandArt.WRIST_ANCHORS[hand] * HandArt.DISPLAY_SCALE
		app.world.hand_progress[hand] = 1.0
		app.world._update_hand(hand)
		check(sprite.texture.resource_path.ends_with("frat_" + side + "_hand_flick_position.png"), "flick artwork mapped to " + side)
		var after: Vector2 = sprite.position + HandArt.WRIST_ANCHORS[hand] * HandArt.DISPLAY_SCALE
		check(before.is_equal_approx(after), "pose switch keeps wrist fixed for " + side)
		check(not sprite.flip_h, "handedness uses original art without mirroring")
		check(sprite.material is ShaderMaterial, "black backdrop removed in renderer")
		app.world.hand_progress[hand] = 0.0
		app.world.flash(hand, false)
		app.world._update_hand(hand)
		check(sprite.texture == HandArt.pose(hand, true), "keyboard/camera event triggers flick pose")
	app.world.elapsed = 0.0
	app.world._process(0.25)
	check(is_equal_approx(float(app.world.scenery_material.get_shader_parameter("scene_time")), 0.25), "background time advances independently of paused song")
	var code := FileAccess.get_file_as_string("res://scripts/beach_world.gd")
	check(not code.contains("else 0.78"), "wave tint no longer changes by lane")
	check(not code.contains("_draw_aggie_umbrellas") and not code.contains("_draw_aggie_party"), "no extra themed props or stick figures")
	app.tracker.close()
	app.title_jukebox.set_active(false)
	app.intro_music.stop()
	app.bob_audio.stop()
	await create_timer(.15).timeout
	app.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("VISUAL_ASSET_TESTS ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
