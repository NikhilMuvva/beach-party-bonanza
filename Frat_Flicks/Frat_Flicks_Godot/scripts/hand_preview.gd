extends Control
## Mirrored local camera preview with consistent hand-lane colors.
const UI = preload("res://scripts/ui_theme.gd")
const CONNECTIONS := [[0,1],[1,2],[2,3],[3,4],[0,5],[5,6],[6,7],[7,8],[5,9],[9,10],[10,11],[11,12],[9,13],[13,14],[14,15],[15,16],[13,17],[17,18],[18,19],[19,20],[0,17]]
var hands: Dictionary = {}
var is_online := false
var video: ImageTexture
var refresh := 0.0

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	refresh += delta
	if refresh < 1.0 / 30.0:
		return
	refresh = 0.0
	if not is_online:
		video = null
		return
	var path := OS.get_user_data_dir().path_join("camera_preview.jpg")
	if FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		var image := Image.new()
		if image.load_jpg_from_buffer(bytes) == OK:
			if video == null:
				video = ImageTexture.create_from_image(image)
			else:
				video.update(image)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101f30"))
	if video != null and is_online:
		draw_texture_rect(video, Rect2(Vector2.ZERO, size), false)
	draw_rect(Rect2(Vector2.ZERO, size), UI.GOLD, false, 2.0)
	# Small shell motifs and crisp corners keep the beach/arcade identity.
	for side in [-1, 1]:
		var shell := Vector2(12 if side == -1 else size.x - 12, size.y - 12)
		draw_arc(shell, 8, PI, TAU, 12, UI.GOLD, 2.0, true)
		for rib in [-1, 0, 1]:
			draw_line(shell, shell + Vector2(rib * 6, -6), UI.GOLD, 1.0, true)
	if video == null:
		draw_string(UI.BODY, Vector2(16, size.y * 0.5), "CAMERA OFFLINE" if not is_online else "WAITING FOR VIDEO", HORIZONTAL_ALIGNMENT_CENTER, size.x - 32, 12, UI.MUTED)
	for hand in ["L", "R"]:
		var data: Dictionary = hands.get(hand, {})
		var points: Array = data.get("landmarks", [])
		if points.size() != 21:
			continue
		var color := UI.CYAN
		for edge in CONNECTIONS:
			var a: Array = points[edge[0]]
			var b: Array = points[edge[1]]
			if a.size() != 2 or b.size() != 2:
				continue
			draw_line(Vector2(a[0], a[1]) * size, Vector2(b[0], b[1]) * size, color, 2.0, true)
		for point in points:
			if point.size() == 2:
				draw_circle(Vector2(point[0], point[1]) * size, 3.0, color)
	if hands.is_empty():
		var center := size * 0.5
		for side in [-1, 1]:
			var p := center + Vector2(side * 42, 12)
			draw_arc(p, 22, 0, TAU, 32, Color(0.55, 0.7, 0.75, 0.35), 2.0, true)
			draw_line(p + Vector2(-7, -10), p + Vector2(-7, -43), Color(0.55, 0.7, 0.75, 0.35), 5.0, true)
			draw_line(p + Vector2(7, -10), p + Vector2(7, -48), Color(0.55, 0.7, 0.75, 0.35), 5.0, true)
