extends Control
## What the desk CRTs show: a little live trading terminal (the ticker, its
## candles, a watchlist, the fund and the clock), drawn into a SubViewport and
## put on every monitor on the floor. A few of these are shared across all
## the desks (each on a different ticker, rotating), so it costs almost nothing.

const UI = preload("res://scripts/ui/ui_theme.gd")
const Rules = preload("res://scripts/sim/rules.gd")

const BG := Color(0.02, 0.05, 0.09)
const GRN := Color(0.25, 1.0, 0.5)
const RED := Color(1.0, 0.32, 0.3)
const DIM := Color(0.45, 0.6, 0.7)
const CANDLES := 34

var match_node
var slot := 0                 # which screen of the set (picks the ticker)
var sym := ""
var _acc := 0.0
var _rot := 0.0


func _process(delta: float) -> void:
	_acc += delta
	_rot += delta
	if _rot > 25.0 or sym == "":
		_rot = 0.0
		_pick()
	if _acc >= 0.25:
		_acc = 0.0
		queue_redraw()


func _pick() -> void:
	if match_node == null or match_node.m_assets.is_empty():
		return
	var n: int = match_node.m_assets.size()
	var i := (slot * 5 + int(Time.get_ticks_msec() / 25000.0)) % n
	sym = match_node.m_assets[i].sym


func _draw() -> void:
	var font := UI.medium()
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if match_node == null or sym == "":
		draw_string(font, Vector2(20, 60), "BAGHOLDER TERMINAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, GRN)
		return
	var a: Dictionary = match_node.asset_mirror(sym)
	if a.is_empty():
		return
	var ch: float = (a.price / a.open_day - 1.0) * 100.0 if a.open_day > 0.0 else 0.0
	var col := GRN if ch >= 0.0 else RED
	# header: the ticker, its price, the day's move
	draw_rect(Rect2(0, 0, size.x, 44), Color(0.05, 0.1, 0.16))
	draw_string(font, Vector2(12, 32), sym, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1))
	draw_string(font, Vector2(120, 32), Rules.price_str(a.price), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, col)
	draw_string(font, Vector2(size.x - 190, 32), "%s%.2f%%" % ["+" if ch >= 0.0 else "", ch], HORIZONTAL_ALIGNMENT_RIGHT, 110, 26, col)
	# the candles
	var list_w := 128.0
	var plot := Rect2(8, 52, size.x - list_w - 20, size.y - 52 - 40)
	var candles: Array = a.candles.slice(maxi(0, a.candles.size() - (CANDLES - 1)))
	candles.append(a.cur)
	var lo := INF
	var hi := -INF
	for c in candles:
		lo = minf(lo, c[2])
		hi = maxf(hi, c[1])
	var pad := maxf((hi - lo) * 0.08, hi * 0.0005)
	lo -= pad
	hi += pad
	for i in 5:
		var gy := plot.position.y + plot.size.y * i / 4.0
		draw_line(Vector2(plot.position.x, gy), Vector2(plot.end.x, gy), Color(1, 1, 1, 0.06), 1.0)
	var cw := plot.size.x / CANDLES
	var x0 := plot.position.x + (CANDLES - candles.size()) * cw
	for i in candles.size():
		var c: Array = candles[i]
		var x := x0 + i * cw + cw * 0.5
		var up: bool = c[3] >= c[0]
		var cc := GRN if up else RED
		var yh: float = plot.position.y + plot.size.y * (1.0 - (c[1] - lo) / (hi - lo))
		var yl: float = plot.position.y + plot.size.y * (1.0 - (c[2] - lo) / (hi - lo))
		var yo: float = plot.position.y + plot.size.y * (1.0 - (c[0] - lo) / (hi - lo))
		var yc: float = plot.position.y + plot.size.y * (1.0 - (c[3] - lo) / (hi - lo))
		draw_line(Vector2(x, yh), Vector2(x, yl), cc, 1.5)
		draw_rect(Rect2(x - cw * 0.33, minf(yo, yc), cw * 0.66, maxf(absf(yc - yo), 1.5)), cc)
	var py: float = plot.position.y + plot.size.y * (1.0 - (a.price - lo) / (hi - lo))
	draw_dashed_line(Vector2(plot.position.x, py), Vector2(plot.end.x, py), Color(col, 0.7), 1.0, 5.0)
	# the watchlist
	var lx := size.x - list_w - 4
	draw_rect(Rect2(lx - 6, 52, list_w + 10, plot.size.y), Color(0.04, 0.08, 0.13))
	var n: int = match_node.m_assets.size()
	for k in mini(9, n):
		var w: Dictionary = match_node.m_assets[(slot * 3 + k) % n]
		var wc: float = (w.price / w.open_day - 1.0) * 100.0 if w.open_day > 0.0 else 0.0
		var wy := 74.0 + k * 26.0
		draw_string(font, Vector2(lx, wy), w.sym, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.85, 0.9, 0.95) if w.sym != sym else Color(1, 0.85, 0.3))
		draw_string(font, Vector2(lx + 52, wy), "%s%.1f%%" % ["+" if wc >= 0.0 else "", wc], HORIZONTAL_ALIGNMENT_RIGHT, 72, 16,
				GRN if wc >= 0.0 else RED)
	# the bottom strip: the fund and the clock
	draw_rect(Rect2(0, size.y - 34, size.x, 34), Color(0.05, 0.1, 0.16))
	var acct: int = match_node.acct_for(Net.my_id())
	var eq: float = match_node.equity_of(acct)
	var t: float = maxf(match_node.time_left, 0.0)
	var phase: String = match_node.phase
	var right := "%d:%02d" % [int(t) / 60, int(t) % 60] if phase == "trading" else ("PRE-MARKET" if phase == "morning" else "CLOSED")
	draw_string(font, Vector2(12, size.y - 10), "%s %s" % ["FUND" if Net.mode == "coop" else "ACCT", Rules.money(eq)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UI.GOLD)
	draw_string(font, Vector2(size.x - 160, size.y - 10), right, HORIZONTAL_ALIGNMENT_RIGHT, 150, 20, DIM)
	# scanlines: it's a CRT
	var y := 0.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.12), 1.0)
		y += 3.0
