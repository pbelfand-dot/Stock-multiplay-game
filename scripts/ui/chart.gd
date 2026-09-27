extends Control
## Candlestick chart like the trailer's terminal: candles, volume, price
## axis on the right, time axis on the bottom, entry lines, pen drawings.

const UI = preload("res://scripts/ui/ui_theme.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const VISIBLE := 60
const AXIS_W := 78.0
const TIME_H := 26.0

var match_node
var sym := "BTC"
var pen_enabled := false
var strokes: Array = []          # Array[PackedVector2Array] in normalized (0..1) coords
var _drawing := false
var show_volume := true


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func clear_drawings() -> void:
	strokes.clear()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not pen_enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drawing = event.pressed
		if event.pressed:
			strokes.append(PackedVector2Array([event.position / size]))
	elif event is InputEventMouseMotion and _drawing and not strokes.is_empty():
		strokes[-1].append(event.position / size)
		queue_redraw()


func _draw() -> void:
	var font := UI.medium()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.06, 0.11))
	if match_node == null:
		return
	var a: Dictionary = match_node.asset_mirror(sym)
	if a.is_empty():
		return
	var candles: Array = a.candles.slice(maxi(0, a.candles.size() - (VISIBLE - 1)))
	candles.append(a.cur)
	var plot := Rect2(8, 8, size.x - AXIS_W - 16, size.y - TIME_H - 16)
	var lo := INF
	var hi := -INF
	var vmax := 0.0001
	for c in candles:
		lo = minf(lo, c[2])
		hi = maxf(hi, c[1])
		vmax = maxf(vmax, c[4])
	var acct: Dictionary = match_node.my_acct()
	for pos in acct.get("positions", []):
		if pos.sym == sym:
			lo = minf(lo, pos.entry)
			hi = maxf(hi, pos.entry)
	var pad := maxf((hi - lo) * 0.08, hi * 0.0005)
	lo -= pad
	hi += pad
	var y_of := func(p: float) -> float:
		return plot.position.y + plot.size.y * (1.0 - (p - lo) / (hi - lo))

	# grid + price axis
	for i in 6:
		var p := lerpf(lo, hi, i / 5.0)
		var y: float = y_of.call(p)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(1, 1, 1, 0.06), 1.0)
		draw_line(Vector2(plot.end.x + 4, y), Vector2(plot.end.x + 10, y), UI.LINE, 1.0)
		draw_string(font, Vector2(plot.end.x + 14, y + 6), Rules.price_str(p), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.DIM)
	draw_line(Vector2(plot.end.x + 4, plot.position.y), Vector2(plot.end.x + 4, plot.end.y), UI.LINE, 1.5)

	# candles
	var n := VISIBLE
	var cw := plot.size.x / n
	var start_x := plot.position.x + (n - candles.size()) * cw
	for i in candles.size():
		var c: Array = candles[i]
		var x := start_x + i * cw + cw * 0.5
		var up: bool = c[3] >= c[0]
		var col := UI.GREEN if up else UI.RED
		if show_volume:
			var vh: float = (c[4] / vmax) * plot.size.y * 0.18
			draw_rect(Rect2(x - cw * 0.35, plot.end.y - vh, cw * 0.7, vh), Color(col, 0.35))
		draw_line(Vector2(x, y_of.call(c[1])), Vector2(x, y_of.call(c[2])), col, 1.5)
		var y1: float = y_of.call(c[0])
		var y2: float = y_of.call(c[3])
		draw_rect(Rect2(x - cw * 0.34, minf(y1, y2), cw * 0.68, maxf(absf(y2 - y1), 1.5)), col)

	# time axis (mm:ss of market clock)
	var t_now: float = match_node.m_ci * 5.0
	for i in range(0, candles.size(), 12):
		var x := start_x + i * cw + cw * 0.5
		var secs := int(t_now - (candles.size() - 1 - i) * 5.0)
		draw_string(font, Vector2(x - 16, size.y - 8), "%02d:%02d" % [(secs / 60) % 60, secs % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.DIM)

	# entry lines for our positions
	for pos in acct.get("positions", []):
		if pos.sym != sym:
			continue
		var y: float = y_of.call(pos.entry)
		var col := UI.GREEN if pos.side > 0 else UI.RED
		draw_dashed_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), col, 1.5, 8.0)
		draw_string(font, Vector2(plot.position.x + 6, y - 4), "%s x%d %s" % ["LONG" if pos.side > 0 else "SHORT", pos.lev, pos.trader], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)

	# live price tag
	var py: float = y_of.call(a.price)
	var up_day: bool = a.price >= a.open_day
	var tag_col := UI.GREEN if up_day else UI.RED
	draw_line(Vector2(plot.position.x, py), Vector2(plot.end.x + 4, py), Color(tag_col, 0.5), 1.0)
	draw_rect(Rect2(plot.end.x + 4, py - 11, AXIS_W - 6, 22), tag_col)
	draw_string(font, Vector2(plot.end.x + 10, py + 6), Rules.price_str(a.price), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.BLACK)

	# pen strokes
	for s in strokes:
		if s.size() < 2:
			continue
		var pts := PackedVector2Array()
		for v in s:
			pts.append(v * size)
		draw_polyline(pts, UI.GOLD, 2.5, true)
