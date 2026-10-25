extends SceneTree
const Judge = preload("res://scripts/rhythm_judge.gd")
const World = preload("res://scripts/beach_world.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world = World.new()
	for lane in ["down","up"]:
		var target: Vector2 = world.TARGETS[lane]
		check(world.note_center(lane,1.0).is_equal_approx(target),"wave crosses exact target on beat")
		var previous: Vector2 = world.note_center(lane,.95)
		for i in range(96,114):
			var position: Vector2 = world.note_center(lane,i/100.0)
			check(position.y > previous.y,"wave moves continuously before and after target")
			previous=position
		var before: Vector2 = target - world.note_center(lane,.999)
		var after: Vector2 = world.note_center(lane,1.001) - target
		check(before.distance_to(after)<.002,"velocity stays continuous through target")
	world.free()
	for offset in [-.30,-.22,0.0,.22,.30]:
		var judge=Judge.new()
		judge.configure([{"t":2.0,"lane":"down"}],true)
		check(not judge.flick("L",2.0+offset).is_empty(),"deliberate near hits accepted")
	for offset in [-.301,.301]:
		var judge=Judge.new()
		judge.configure([{"t":2.0,"lane":"down"}],true)
		check(judge.flick("L",2.0+offset).is_empty() and judge.stray_flicks==1,"outside timing window is an off-beat attempt")
	var judge=Judge.new()
	judge.configure([{"t":2.0,"lane":"down"},{"t":3.0,"lane":"up"}],true)
	judge.flick("L",2.0)
	var initial_vibe: float = judge.vibe
	judge.flick("R",2.0)
	check(judge.stray_flicks==1 and is_equal_approx(judge.vibe,initial_vibe-.03),"wrong-lane input costs three percent")
	check(judge.perfect_streak==0 and judge.combo==0,"off-beat attempt ends streak")
	check(is_equal_approx(judge.accuracy(),.5),"off-beat attempt affects accuracy")
	judge.flick("R",2.05)
	check(judge.stray_flicks==1 and not judge.last_attempt_penalized,"rapid duplicate debounced without extra penalty")
	check(not judge.flick("R",3.0).is_empty(),"other hand remains playable after debounce")
	judge.configure([{"t":2.0,"lane":"down"},{"t":2.0,"lane":"up"}],true)
	check(not judge.flick("L",2.0).is_empty() and not judge.flick("R",2.0).is_empty(),"simultaneous genuine two-hand notes work")
	for key in ["sweet_rally","paradise","make_u_whole","eatin_good","free_your_mind"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/beatmaps/%s.json" % key))
		judge.configure(data["beats"])
		for beat in data["beats"]:
			judge.flick("L" if beat["lane"]=="down" else "R", float(beat["t"])+.22)
		check(not judge.lost and judge.hits==data["beats"].size() and judge.stray_flicks==0,"forgiving deliberate full run: "+key)
		judge.configure(data["beats"])
		for i in 200:
			judge.flick("L",i*.05)
			judge.flick("R",i*.05)
			if judge.lost:
				break
		check(judge.lost and judge.stray_flicks>0,"blind rapid spam cannot win: "+key)
	judge.configure([{"t":2.0,"lane":"down"}],true)
	check(judge.stray_flicks==0 and judge.last_attempt["L"] < 0,"new round clears spam state")
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.test_mode=true
	app._begin_keyboard()
	app._start_round()
	app.judge.configure([{"t":2.0,"lane":"down"}],true)
	app._flick("L",0.0)
	check(app.labels["feedback"].text.contains("-3%") and app.judge.stray_flicks==1,"off-beat feedback reaches actual HUD")
	check(app.splash_events==0,"off-target gesture does not play missed-wave splash")
	app._flick("L",.05)
	check(app.judge.stray_flicks==1,"app ignores duplicate penalties")
	app._flick("L",2.0)
	check(app.judge.hits==1 and app.judge.score==2,"deliberate hit still scores after off-target attempt")
	app._finish(true)
	check(app.labels["result_misses"].text.contains("1 off-beat"),"results report off-beat attempts")
	app._restart_round()
	check(app.judge.stray_flicks==0,"retry clears penalties")
	app._return_title()
	app.title_jukebox.set_active(false)
	await create_timer(.15).timeout
	app.queue_free()
	await process_frame
	await create_timer(.15).timeout
	print("BALANCED_PLAY_TESTS ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
