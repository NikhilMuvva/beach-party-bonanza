extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var failures: Array[String] = []
	for key in ["clap", "kick", "invalid_saved_song"]:
		app.chart_key = key
		if not app._load_chart() or app.chart_key != "sweet_rally" or not app.music.stream.resource_path.ends_with("sweet_rally.mp3"):
			failures.append("legacy song fallback: " + key)
	for selector in app.song_selectors:
		if selector.item_count != 5:
			failures.append("selector count")
		for i in selector.item_count:
			if selector.get_item_text(i).contains("Original"):
				failures.append("removed choice remains")
	for path in ["res://assets/audio/song.ogg", "res://assets/audio/song_kick.ogg", "res://assets/audio/check.wav", "res://assets/audio/check_kick.wav", "res://assets/beatmaps/beatmap.json", "res://assets/beatmaps/beatmap_kick.json"]:
		if FileAccess.file_exists(path):
			failures.append("removed asset remains: " + path)
	app.tracker.close()
	app.queue_free()
	await process_frame
	await create_timer(.2).timeout
	print("FINAL_PLAYLIST_TESTS ", JSON.stringify({"failures":failures}))
	quit(0 if failures.is_empty() else 1)
