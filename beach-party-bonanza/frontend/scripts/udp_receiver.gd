extends Node
## Local Python sidecar -> Godot bridge. Contract: ../docs/UDP_PROTOCOL.md
signal flick_received(hand: String, direction: String)
signal pose_received(hand: String, position: Vector2)
signal status_received(is_ready: bool, hands_visible: int)

const PORT: int = 4242
var peer: PacketPeerUDP = PacketPeerUDP.new()

func _ready() -> void:
    var err: Error = peer.bind(PORT, "127.0.0.1")
    if err != OK:
        push_error("Could not bind UDP port %s. Is another Godot instance running?" % PORT)
    else:
        print("Listening for Python hand tracking on 127.0.0.1:%s" % PORT)

func _process(_delta: float) -> void:
    # Drain all available packets to avoid accumulating outdated positions.
    while peer.get_available_packet_count() > 0:
        var raw: String = peer.get_packet().get_string_from_utf8()
        var msg: Variant = JSON.parse_string(raw)
        if typeof(msg) != TYPE_DICTIONARY or msg.get("v", 0) != 1:
            continue
        match msg.get("type", ""):
            "flick":
                var hand: String = str(msg.get("hand", ""))
                var direction: String = str(msg.get("event", ""))
                if hand in ["L", "R"] and direction in ["UP", "DOWN"]:
                    flick_received.emit(hand, direction)
            "pose":
                var hand: String = str(msg.get("hand", ""))
                if hand in ["L", "R"]:
                    var pos := Vector2(float(msg.get("x", 0.5)), float(msg.get("y", 0.5)))
                    pose_received.emit(hand, pos)
            "status":
                status_received.emit(bool(msg.get("ready", false)), int(msg.get("hands", 0)))

func _exit_tree() -> void:
    peer.close()
