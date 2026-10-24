extends Control
## Temporary integration scene. Replace with rhythm gameplay when ready.
@onready var status_label: Label = $CenterContainer/PanelContainer/VBoxContainer/StatusLabel
@onready var event_label: Label = $CenterContainer/PanelContainer/VBoxContainer/EventLabel
@onready var position_label: Label = $CenterContainer/PanelContainer/VBoxContainer/PositionLabel

func _ready() -> void:
    UDPBridge.flick_received.connect(_on_flick)
    UDPBridge.pose_received.connect(_on_pose)
    UDPBridge.status_received.connect(_on_status)

func _on_flick(hand: String, direction: String) -> void:
    event_label.text = "Flick: %s %s" % [hand, direction]
    print("Flick: ", hand, " ", direction)

func _on_pose(hand: String, pos: Vector2) -> void:
    position_label.text = "Latest pose: %s (%.2f, %.2f)" % [hand, pos.x, pos.y]

func _on_status(is_ready: bool, hands_visible: int) -> void:
    status_label.text = "Calibrated: %s | Hands visible: %s" % [is_ready, hands_visible]
