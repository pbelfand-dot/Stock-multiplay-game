extends Control
## The start clock on screen, for both seats (the real one is out by the road):
## five red lights that go out one a second with the count in big numbers, then
## a green GO. The gantry is art (assets/ui/start_lights.png, Higgsfield: five
## dark lenses); the lit lamps are drawn over its lenses. While the stage runs,
## the stage time sits small at the top, with any penalties under it.

const RED := Color(1.0, 0.18, 0.12)
const GREEN := Color(0.25, 1.0, 0.35)
const OFF := Color(0.16, 0.05, 0.05)
const AMBER := Color(1.0, 0.75, 0.2)
## Where the art's lenses are, in its pixels (900 x 220): the first's centre,
## the step to the next, the glass's radius.
const LENS0 := Vector2(107.0, 97.5)
const LENS_STEP := 172.5
const LENS_R := 60.0
const GANTRY_W := 560.0

var state := "grid"             # the game's state
var count := 5                  # countdown: 5 .. 1, 0 = GO
var since_go := 99.0            # seconds since GO (the green stays up for a moment)
var time_text := ""             # the stage clock
var pen_text := ""              # "+10 s JUMP START" ...
var _bold: Font
var _medium: Font
var _box := StyleBoxFlat.new()
var _gantry: Texture2D
var hold := {}                  # (screenshots) {"state", "count"}: shown whatever the game says


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bold = load("res://assets/fonts/Oswald-Bold.woff2")
	_medium = load("res://assets/fonts/Oswald-Medium.woff2")
	_box.bg_color = Color(0.03, 0.03, 0.04, 0.82)
	_box.set_corner_radius_all(18)
	_box.border_color = Color(1, 1, 1, 0.15)
	_box.set_border_width_all(2)
	if ResourceLoader.exists("res://assets/ui/start_lights.png"):
		_gantry = load("res://assets/ui/start_lights.png")


func _process(_dt: float) -> void:
	if not hold.is_empty():
		state = hold.state
		count = hold.count
	queue_redraw()


func _draw() -> void:
	var cx := size.x * 0.5
	var counting := state == "countdown" or (state == "running" and since_go < 1.6)
	if state == "grid" or counting:
		var go := state == "running" or count <= 0
		var big := "READY" if state == "grid" else ("GO!" if go else str(count))
		var size_px := 64 if state == "grid" else 130
		var col_txt := Color(0.85, 0.85, 0.85) if state == "grid" else (GREEN if go else RED)
		if _gantry:
			var k := GANTRY_W / _gantry.get_width()
			var top := size.y * 0.08
			var at := Vector2(cx - GANTRY_W * 0.5, top)
			draw_texture_rect(_gantry, Rect2(at, _gantry.get_size() * k), false)
			for i in 5:
				var lit := state != "grid" and (go or i < count)
				if lit:
					_lamp(at + (LENS0 + Vector2(LENS_STEP * i, 0.0)) * k, LENS_R * k, GREEN if go else RED)
			var below := top + _gantry.get_height() * k
			_text(big, Vector2(cx, below + (70.0 if state == "grid" else 128.0)), size_px, col_txt, _bold)
		else:
			var panel := Rect2(cx - 230.0, size.y * 0.1, 460.0, 250.0)
			draw_style_box(_box, panel)
			for i in 5:
				var lit := go or i < count
				var col := (GREEN if go else RED) if lit and state != "grid" else OFF
				var c := Vector2(cx + (i - 2) * 76.0, panel.position.y + 52.0)
				draw_circle(c, 28.0, Color(0, 0, 0, 0.6))
				draw_circle(c, 24.0, col)
				if lit and state != "grid":
					draw_circle(c - Vector2(7, 7), 7.0, Color(1, 1, 1, 0.35))
			_text(big, Vector2(cx, panel.position.y + 205.0), size_px, col_txt, _bold)
	if state in ["running", "finished"] and time_text != "":
		_text(time_text, Vector2(cx, 54.0), 40, Color.WHITE, _bold)
		if pen_text != "":
			_text(pen_text, Vector2(cx, 88.0), 22, AMBER, _medium)


## A lit lamp in one of the art's lenses: a glow round it, the glass bright,
## hotter in the middle, and the glint at the top left.
func _lamp(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c, r * 1.55, Color(col, 0.10))
	draw_circle(c, r * 1.25, Color(col, 0.22))
	draw_circle(c, r * 0.97, col.darkened(0.35))
	draw_circle(c, r * 0.8, col)
	draw_circle(c, r * 0.45, col.lerp(Color.WHITE, 0.45))
	draw_circle(c + Vector2(-r * 0.38, -r * 0.42), r * 0.16, Color(1, 1, 1, 0.55))


## Centered text with a dark outline, baseline at `at`.
func _text(t: String, at: Vector2, px: int, col: Color, font: Font) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var p := Vector2(at.x - w * 0.5, at.y)
	draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 10, Color(0, 0, 0, 0.85))
	draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
