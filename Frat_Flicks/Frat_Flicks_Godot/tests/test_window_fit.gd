extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	DisplayServer.window_set_size(Vector2i(1920,1080))
	app._fit_starting_window()
	await process_frame
	var size := DisplayServer.window_get_size()
	var usable := DisplayServer.screen_get_usable_rect()
	var ok := size.x <= usable.size.x and size.y <= usable.size.y and absf(float(size.x)/size.y - 16.0/9.0) < .01
	print("WINDOW_FIT_TEST ", JSON.stringify({"success":ok,"size":str(size),"usable":str(usable)}))
	app.test_mode=true
	app._quit()
