extends Control
## Track Mode's race screen, top left: your position and lap (P3 / 12 · LAP 4 / 10, or the
## qualifying clock), the timing tower (each car's place, number, name, and its gap: to the leader
## in a race, its best lap in qualifying; PIT in the pits, +5 for a penalty, OUT retired), the gaps
## to the cars ahead of you and behind on the road, and the flag being shown to you (top middle:
## GREEN, YELLOW, BLUE, BLACK AND WHITE, BLACK, RED, CHEQUERED). The rows: the leaders and the
## cars round you when the field's bigger than the tower.

const ROWS := 12                   # rows the tower shows
const ROW_H := 30.0
const YOU := Color(1.0, 0.82, 0.25)
const FLAG_COL := {"green": Color(0.2, 0.8, 0.3), "yellow": Color(1.0, 0.85, 0.1), "blue": Color(0.2, 0.45, 1.0),
	"bw": Color(0.9, 0.9, 0.9), "black": Color(0.05, 0.05, 0.05), "red": Color(0.9, 0.1, 0.1), "chequered": Color(1, 1, 1)}
const FLAG_TEXT := {"green": "GREEN FLAG", "yellow": "YELLOW FLAG: NO OVERTAKING", "blue": "BLUE FLAG: LET THE LEADER BY",
	"bw": "BLACK AND WHITE: TRACK LIMITS", "black": "BLACK FLAG: DISQUALIFIED", "red": "RED FLAG: SLOW DOWN, NO OVERTAKING",
	"chequered": "CHEQUERED FLAG"}

var head := ""                     # "P3 / 12   LAP 4 / 10"
var sub := ""                      # "GT  ·  RACE"
var rows: Array = []               # [{pos, number, name, text, you, pit, pens, out}]
var ahead := ""                    # "+1.234  VARGA"
var behind := ""
var flag := ""                     # a key of FLAG_TEXT or ""
var flag_t := 0.0                  # s the flag's been up (it pulses, the green fades)
var _bold: Font
var _medium: Font
var _box := StyleBoxFlat.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bold = load("res://assets/fonts/Oswald-Bold.woff2")
	_medium = load("res://assets/fonts/Oswald-Medium.woff2")
	_box.bg_color = Color(0.02, 0.03, 0.05, 0.66)
	_box.set_corner_radius_all(6)


func _process(dt: float) -> void:
	flag_t += dt
	queue_redraw()


## The flag shown now ("" none): its timer restarts when it changes.
func set_flag(f: String) -> void:
	if f != flag:
		flag = f
		flag_t = 0.0


func _draw() -> void:
	var x0 := 28.0
	var y := 26.0
	if head != "":
		draw_style_box(_box, Rect2(x0 - 10.0, y - 6.0, 330.0, 84.0))
		_text(head, Vector2(x0, y + 40.0), 38, Color.WHITE, _bold)
		_text(sub, Vector2(x0, y + 68.0), 18, Color(0.8, 0.8, 0.8), _medium)
		y += 92.0
	if not rows.is_empty():
		draw_style_box(_box, Rect2(x0 - 10.0, y - 4.0, 330.0, rows.size() * ROW_H + 8.0))
		for r in rows:
			var col: Color = YOU if bool(r.get("you", false)) else Color.WHITE
			if bool(r.get("out", false)):
				col = Color(0.55, 0.55, 0.55)
			if bool(r.get("you", false)):
				draw_rect(Rect2(x0 - 10.0, y - 2.0, 330.0, ROW_H), Color(1.0, 0.82, 0.25, 0.16))
			_text("%2d" % int(r.pos), Vector2(x0, y + 22.0), 20, col, _bold)
			draw_rect(Rect2(x0 + 30.0, y + 4.0, 34.0, 22.0), Color(0.12, 0.12, 0.14, 0.9))
			_text_c(str(r.get("number", "")), Vector2(x0 + 47.0, y + 21.0), 16, col, _bold)
			_text(str(r.name), Vector2(x0 + 72.0, y + 22.0), 20, col, _medium)
			var t := str(r.get("text", ""))
			if bool(r.get("pit", false)):
				t = "PIT"
			_text_r(t, Vector2(x0 + 310.0, y + 22.0), 18, col, _medium)
			if float(r.get("pens", 0.0)) > 0.0:
				_text_r("+%d" % int(r.pens), Vector2(x0 + 236.0, y + 22.0), 15, Color(1.0, 0.65, 0.2), _bold)
			y += ROW_H
		y += 10.0
	if ahead != "" or behind != "":
		draw_style_box(_box, Rect2(x0 - 10.0, y - 4.0, 330.0, 60.0))
		_text(ahead, Vector2(x0, y + 20.0), 18, Color(1.0, 0.55, 0.45), _medium)
		_text(behind, Vector2(x0, y + 46.0), 18, Color(0.5, 1.0, 0.6), _medium)
	if flag != "" and not (flag == "green" and flag_t > 4.0):
		_flag_banner()


func _flag_banner() -> void:
	var cx := size.x * 0.5
	var w := 640.0
	var r := Rect2(cx - w * 0.5, 120.0, w, 46.0)
	var col: Color = FLAG_COL.get(flag, Color.WHITE)
	var a := 0.75 + 0.25 * sin(flag_t * 6.0) if flag in ["yellow", "blue", "red", "bw", "black"] else 0.9
	if flag == "chequered":
		for i in 32:
			for j in 2:
				var c := Color.WHITE if (i + j) % 2 == 0 else Color.BLACK
				draw_rect(Rect2(r.position.x + i * w / 32.0, r.position.y + j * 23.0, w / 32.0, 23.0), Color(c, 0.85))
		_text_c(FLAG_TEXT[flag], Vector2(cx, r.position.y + 34.0), 28, Color(1.0, 0.82, 0.25), _bold)
		return
	if flag == "bw":
		draw_colored_polygon(PackedVector2Array([r.position, r.position + Vector2(w, 0), r.position + Vector2(0, 46)]), Color(1, 1, 1, a))
		draw_colored_polygon(PackedVector2Array([r.position + Vector2(w, 0), r.position + Vector2(w, 46), r.position + Vector2(0, 46)]), Color(0, 0, 0, a))
	else:
		draw_rect(r, Color(col, a))
	var tc := Color.BLACK if flag in ["yellow", "green", "chequered"] else Color.WHITE
	if flag == "bw":
		tc = Color(1.0, 0.82, 0.25)
	_text_c(FLAG_TEXT.get(flag, flag.to_upper()), Vector2(cx, r.position.y + 33.0), 26, tc, _bold)


func _text(t: String, at: Vector2, px: int, col: Color, font: Font) -> void:
	draw_string_outline(font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 6, Color(0, 0, 0, 0.8))
	draw_string(font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _text_c(t: String, at: Vector2, px: int, col: Color, font: Font) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	_text(t, Vector2(at.x - w * 0.5, at.y), px, col, font)


func _text_r(t: String, at: Vector2, px: int, col: Color, font: Font) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	_text(t, Vector2(at.x - w, at.y), px, col, font)
