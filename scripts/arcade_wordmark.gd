extends Control
## Original 5×7 block lettering: code-native wordmark, no external font dependency.
const UI = preload("res://scripts/ui_theme.gd")
const GLYPHS := {
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"]
}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	_word("FRAT", Vector2(456, 180), 16)
	_word("FLICKS", Vector2(360, 324), 16)

func _word(word: String, origin: Vector2, unit: int) -> void:
	for pass_index in 3:
		var offset: Vector2 = [Vector2(8, 12), Vector2(4, 4), Vector2.ZERO][pass_index]
		var color: Color = [Color("1c0000"), Color("a58e87"), UI.CREAM][pass_index]
		for letter in word.length():
			var rows: Array = GLYPHS[word[letter]]
			for row in 7:
				for column in 5:
					if rows[row][column] == "1":
						var pos: Vector2 = origin + Vector2(letter * unit * 6 + column * unit, row * unit) + offset
						draw_rect(Rect2(pos, Vector2(unit, unit)), color)
