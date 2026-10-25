extends Node
## Loopback-only JSON. Camera pixels never enter the network protocol.

signal flick_received(hand: String, age_seconds: float)
signal state_received(data: Dictionary)
signal connection_changed(online: bool)

const PORT := 5005
const CONTROL_PORT := 5006
const PROTOCOL := 1
var socket := PacketPeerUDP.new()
var listening := false
var online := false
var last_seen := -100.0
var state: Dictionary = {}
var session := ""
var seen_ids: Dictionary = {}
var command_counter := 0
var pending: Dictionary = {}
var error := ""

func _ready() -> void:
	var result := socket.bind(PORT, "127.0.0.1", 262144)
	listening = result == OK
	if not listening:
		error = "Tracker port 5005 is busy. Close other copies of the game."
	else:
		socket.set_dest_address("127.0.0.1", CONTROL_PORT)

func poll() -> void:
	if not listening:
		return
	var budget := 160
	while socket.get_available_packet_count() > 0 and budget > 0:
		budget -= 1
		var packet := socket.get_packet()
		if socket.get_packet_ip() != "127.0.0.1" or packet.size() > 16384:
			continue
		var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if parsed is Dictionary:
			accept_packet(parsed)
	var now := Time.get_ticks_msec() / 1000.0
	if online and now - last_seen > 1.5:
		online = false
		connection_changed.emit(false)
	for id in pending.keys():
		var entry: Dictionary = pending[id]
		if now - float(entry["sent"]) > 0.30:
			if int(entry["tries"]) >= 4:
				pending.erase(id)
			else:
				_send(entry["data"])
				entry["tries"] += 1
				entry["sent"] = now

func accept_packet(data: Dictionary) -> void:
	if int(data.get("protocol", -1)) != PROTOCOL:
		return
	var incoming_session := str(data.get("session", ""))
	if incoming_session.is_empty() or incoming_session.length() > 100:
		return
	var kind := str(data.get("type", ""))
	if kind not in ["state", "flick", "ack"]:
		return
	if kind == "state":
		if not data.get("hands", {}) is Dictionary or not data.get("calibration", {}) is Dictionary:
			return
		if session != incoming_session:
			session = incoming_session
			seen_ids.clear()
			pending.clear()
			online = false
		state = data
		last_seen = Time.get_ticks_msec() / 1000.0
		if not online:
			online = true
			connection_changed.emit(true)
		state_received.emit(data)
	elif kind == "ack":
		if incoming_session == session:
			pending.erase(str(data.get("id", "")))
	elif kind == "flick":
		# Require a current heartbeat and matching session before accepting input.
		if not online or incoming_session != session:
			return
		var hand := str(data.get("hand", ""))
		var id := str(data.get("id", ""))
		if hand not in ["L", "R"] or id.is_empty() or id in seen_ids:
			return
		var capture_time := float(data.get("captured_unix", 0.0))
		var age := Time.get_unix_time_from_system() - capture_time
		if not is_finite(age) or age < -0.05 or age > 0.5:
			return
		seen_ids[id] = true
		if seen_ids.size() > 256:
			seen_ids.erase(seen_ids.keys()[0])
		flick_received.emit(hand, maxf(0.0, age))

func command(action: String, values: Dictionary = {}) -> void:
	if not listening:
		return
	if action == "round":
		for old_id in pending.keys():
			if pending[old_id]["data"].get("command") == "round":
				pending.erase(old_id)
	command_counter += 1
	var id := "%d-%d" % [Time.get_ticks_msec(), command_counter]
	var data := values.duplicate()
	data["protocol"] = PROTOCOL
	data["command"] = action
	data["id"] = id
	if not session.is_empty():
		data["session"] = session
	_send(data)
	pending[id] = {"data": data, "tries": 1, "sent": Time.get_ticks_msec() / 1000.0}

func _send(data: Dictionary) -> void:
	socket.put_packet(JSON.stringify(data).to_utf8_buffer())

func close() -> void:
	socket.close()
	listening = false
	online = false
	pending.clear()
