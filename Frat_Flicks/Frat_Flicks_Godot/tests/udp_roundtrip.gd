extends SceneTree
## A real UDP integration fixture, driven by test_udp_roundtrip.py.
const Bridge = preload("res://scripts/tracker_bridge.gd")
var bridge
var hits: Array[String] = []
var sent := false

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	bridge = Bridge.new()
	root.add_child(bridge)
	bridge.flick_received.connect(func(hand, _age): hits.append(hand))
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		bridge.poll()
		if bridge.online and not sent:
			bridge.command("round", {"active": true})
			sent = true
		if hits.size() >= 2:
			await create_timer(0.15).timeout
			bridge.poll()
			break
		await create_timer(0.01).timeout
	var success: bool = hits == ["L", "R"] and bridge.pending.is_empty()
	print("UDP_ROUNDTRIP ", JSON.stringify({"success": success, "hands": hits, "pending": bridge.pending.size()}))
	bridge.close()
	bridge.queue_free()
	quit(0 if success else 1)
