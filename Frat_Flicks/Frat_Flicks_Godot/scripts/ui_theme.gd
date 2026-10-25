extends RefCounted
## Four-point layout rhythm; one display face and one body face.
const GRID := 4.0
const RADIUS := 8
const TYPE_RAMP := [12, 16, 20, 24, 32, 40, 56, 80, 128]
const BODY = preload("res://assets/fonts/DejaVuSans.ttf")
const DISPLAY = preload("res://assets/fonts/DejaVuSansMono-Bold.ttf")
const CREAM := Color("fff4db")
const MUTED := Color("b7c7cf")
const CYAN := Color("79d4d0")
const GOLD := Color("edc484")
const RED := Color("ee9886")
const INK := Color("102232")
const MAROON := Color("500000")

static func rect(value: Rect2) -> Rect2:
	return Rect2(value.position.snapped(Vector2(GRID, GRID)), value.size.snapped(Vector2(GRID, GRID)))

static func font_size(requested: int) -> int:
	var nearest: int = TYPE_RAMP[0]
	for candidate in TYPE_RAMP:
		if absi(candidate - requested) < absi(nearest - requested):
			nearest = candidate
	return nearest
