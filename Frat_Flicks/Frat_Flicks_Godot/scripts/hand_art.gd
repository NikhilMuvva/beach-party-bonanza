extends RefCounted
## Supplied artwork is kept intact. A canvas matte removes its black backdrop.
const POSES := {
	"L": {"up": preload("res://assets/art/hands/frat_left_hand_flick_position.png"), "down": preload("res://assets/art/hands/frat_left_hand_normal_position.png")},
	"R": {"up": preload("res://assets/art/hands/frat_right_hand_flick_position.png"), "down": preload("res://assets/art/hands/frat_right_hand_normal_position.png")}
}
const WRIST_ANCHORS := {"L": Vector2(152, 704), "R": Vector2(370, 704)}
const DISPLAY_SCALE := 0.4

static func pose(hand: String, raised: bool) -> Texture2D:
	return POSES[hand]["up" if raised else "down"]

static func material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
	void fragment() {
		vec4 pixel = texture(TEXTURE, UV);
		float ink = max(pixel.r, max(pixel.g, pixel.b));
		pixel.a *= smoothstep(0.035, 0.085, ink);
		COLOR = pixel;
	}"""
	var result := ShaderMaterial.new()
	result.shader = shader
	return result
