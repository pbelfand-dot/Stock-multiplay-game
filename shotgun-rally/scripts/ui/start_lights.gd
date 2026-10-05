extends Control
## The start clock on screen, for both seats (the real one is out by the road):
## five red lights that go out one a second with the count in big numbers, then
## a green GO. While the stage runs, the stage time sits small at the top, with
## any penalties under it.

const RED := Color(1.0, 0.18, 0.12)
const GREEN := Color(0.25, 1.0, 0.35)
const OFF := Color(0.16, 0.05, 0.05)
const AMBER := Color(1.0, 0.75, 0.2)

var state := "grid"             # the game's state
var count := 5                  # countdown: 5 .. 1, 0 = GO
var since_go := 99.0            # seconds since GO (the green stays up for a moment)
var time_text := ""             # the stage clock
var pen_text := ""              # "+10 s JUMP START" ...
var _bold: Font
var _medium: Font
var _box := StyleBoxFlat.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bold = load("res://assets/fonts/Oswald-Bold.woff2")
	_medium = load("res://assets/fonts/Oswald-Medium.woff2")
	_box.bg_color = Color(0.03, 0.03, 0.04, 0.82)
	_box.set_corner_radius_all(18)
	_box.border_color = Color(1, 1, 1, 0.15)
	_box.set_border_width_all(2)


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var cx := size.x * 0.5
	var counting := state == "countdown" or (state == "running" and since_go < 1.6)
	if state == "grid" or counting:
		var panel := Rect2(cx - 230.0, size.y * 0.1, 460.0, 250.0)
		draw_style_box(_box, panel)
		var go := state == "running" or count <= 0
		for i in 5:
			var lit := go or i < count
			var col := (GREEN if go else RED) if lit and state != "grid" else OFF
			var c := Vector2(cx + (i - 2) * 76.0, panel.position.y + 52.0)
			draw_circle(c, 28.0, Color(0, 0, 0, 0.6))
			draw_circle(c, 24.0, col)
			if lit and state != "grid":
				draw_circle(c - Vector2(7, 7), 7.0, Color(1, 1, 1, 0.35))
		var big := "READY" if state == "grid" else ("GO!" if go else str(count))
		var size_px := 64 if state == "grid" else 130
		var col_txt := Color(0.85, 0.85, 0.85) if state == "grid" else (GREEN if go else RED)
		_text(big, Vector2(cx, panel.position.y + 205.0), size_px, col_txt, _bold)
	if state in ["running", "finished"] and time_text != "":
		_text(time_text, Vector2(cx, 54.0), 40, Color.WHITE, _bold)
		if pen_text != "":
			_text(pen_text, Vector2(cx, 88.0), 22, AMBER, _medium)


## Centered text with a dark outline, baseline at `at`.
func _text(t: String, at: Vector2, px: int, col: Color, font: Font) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var p := Vector2(at.x - w * 0.5, at.y)
	draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 10, Color(0, 0, 0, 0.85))
	draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
