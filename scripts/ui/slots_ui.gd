extends PanelContainer
## BAG SLOTS: 3 reels, -/+ bet, pull the lever. Server decides the result.

const UI = preload("res://scripts/ui/ui_theme.gd")
const Rules = preload("res://scripts/sim/rules.gd")

signal closed

var match_node
var bet_idx := 1
var spinning := false
var reels := [4, 4, 4]
var offsets := [0.0, 0.0, 0.0]
var stop_at := [-1.0, -1.0, -1.0]
var result: Array = []
var result_payout := 0.0
var _t := 0.0

var reel_view: Control
var bet_lbl: Label
var result_lbl: Label
var win_lbl: Label
var spin_btn: Button
var coins: CPUParticles2D
var confetti: CPUParticles2D


func setup(m) -> void:
	match_node = m
	m.slot_result.connect(_on_result)


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.panel_box(Color(0.14, 0.08, 0.24), UI.GOLD, 24, 6))
	UI.center(self, Vector2(720, 620))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var title := UI.lbl("BAG SLOTS", 64, UI.GOLD, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	win_lbl = UI.lbl("$0", 44, Color(1, 0.3, 0.4), true)
	win_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(win_lbl)
	reel_view = Control.new()
	reel_view.custom_minimum_size = Vector2(640, 260)
	reel_view.draw.connect(_draw_reels)
	v.add_child(reel_view)
	var bet_row := HBoxContainer.new()
	bet_row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(bet_row)
	var minus := UI.btn("  -  ", UI.RED.darkened(0.1), 34)
	minus.pressed.connect(func(): _bet(-1))
	bet_row.add_child(minus)
	var bb := PanelContainer.new()
	bb.add_theme_stylebox_override("panel", UI.panel_box(Color(0.1, 0.1, 0.14), Color(0.3, 0.3, 0.4), 8, 2))
	bb.custom_minimum_size.x = 220
	bet_row.add_child(bb)
	bet_lbl = UI.lbl("$300", 40, UI.GREEN.lightened(0.2), true)
	bet_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bb.add_child(bet_lbl)
	var plus := UI.btn("  +  ", UI.GREEN.darkened(0.1), 34)
	plus.pressed.connect(func(): _bet(1))
	bet_row.add_child(plus)
	var act := HBoxContainer.new()
	act.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(act)
	spin_btn = UI.btn("PULL LEVER  [SPACE]", Color(0.15, 0.25, 0.8), 30)
	spin_btn.pressed.connect(spin)
	act.add_child(spin_btn)
	var leave := UI.btn("WALK AWAY [ESC]", UI.NAVY_2, 22)
	leave.pressed.connect(func(): closed.emit())
	act.add_child(leave)
	result_lbl = UI.lbl("Three 7s pays 60x. Two cherries pays 2x. House always wins (mostly).", 18, UI.DIM)
	result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(result_lbl)
	coins = _burst(Color(1, 0.75, 0.1), Vector2(18, 18))
	confetti = _burst(Color(1, 1, 1), Vector2(8, 16))
	confetti.color_ramp = _rainbow()
	_bet(0)


func _burst(col: Color, sz: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 120
	p.lifetime = 1.8
	p.explosiveness = 0.95
	p.direction = Vector2(0, -1)
	p.spread = 80
	p.initial_velocity_min = 350
	p.initial_velocity_max = 750
	p.gravity = Vector2(0, 900)
	p.angular_velocity_min = -400
	p.angular_velocity_max = 400
	p.scale_amount_min = sz.x / 4.0
	p.scale_amount_max = sz.y / 4.0
	p.color = col
	p.position = Vector2(360, 330)
	add_child(p)
	return p


func _rainbow() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0, 0.25, 0.5, 0.75, 1])
	g.colors = PackedColorArray([Color.RED, Color.YELLOW, Color.GREEN, Color.CYAN, Color.MAGENTA])
	return g


func _bet(d: int) -> void:
	bet_idx = clampi(bet_idx + d, 0, Rules.SLOT_BETS.size() - 1)
	bet_lbl.text = Rules.money(Rules.SLOT_BETS[bet_idx])


func spin() -> void:
	if spinning:
		return
	spinning = true
	result = []
	stop_at = [-1.0, -1.0, -1.0]
	_t = 0.0
	win_lbl.text = "..."
	match_node.request_slot(Rules.SLOT_BETS[bet_idx])
	# safety: unlock if the server rejects the spin
	get_tree().create_timer(3.0).timeout.connect(func():
		if spinning and result.is_empty():
			spinning = false
			win_lbl.text = "$0")


func _on_result(peer: int, r: Array, payout: float, bet: float) -> void:
	if peer != Net.my_id() or not spinning:
		return
	result = r
	result_payout = payout
	stop_at = [_t + 0.6, _t + 1.0, _t + 1.4]
	var _unused = bet


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if spinning:
		var all_stopped := true
		for i in 3:
			if stop_at[i] < 0.0 or _t < stop_at[i]:
				offsets[i] += delta * (14.0 + i * 3.0)
				all_stopped = false
			else:
				reels[i] = result[i]
				offsets[i] = 0.0
		if all_stopped and not result.is_empty():
			spinning = false
			_show_result()
	reel_view.queue_redraw()


func _show_result() -> void:
	var bet: float = Rules.SLOT_BETS[bet_idx]
	if result_payout > 0.0:
		win_lbl.text = Rules.money(result_payout)
		coins.restart()
		coins.emitting = true
		if result_payout >= bet * 10:
			confetti.restart()
			confetti.emitting = true
			result_lbl.text = "WINNER WINNER. %s" % Rules.money(result_payout)
		else:
			result_lbl.text = "Small win."
	else:
		win_lbl.text = "$0"
		result_lbl.text = "Nothing. Again?"


func _draw_reels() -> void:
	var w := reel_view.size.x
	var h := reel_view.size.y
	reel_view.draw_rect(Rect2(0, 0, w, h), Color(0.35, 0.1, 0.55))
	var rw := w / 3.0 - 20
	for i in 3:
		var x := 10 + i * (rw + 20)
		var rect := Rect2(x, 10, rw, h - 20)
		reel_view.draw_rect(rect, Color(0.97, 0.95, 0.88))
		# symbol above, center, below — scrolling
		var base: int = reels[i]
		var frac: float = fposmod(offsets[i], 1.0)
		var shift := int(floor(offsets[i]))
		for k in [-1, 0, 1]:
			var idx := posmod(base - shift + k, 5)
			var cy: float = rect.position.y + rect.size.y / 2 + (k + frac) * (rect.size.y / 2.2)
			if cy < rect.position.y + 20 or cy > rect.end.y - 20:
				continue
			_draw_symbol(Vector2(x + rw / 2, cy), idx, 1.0 if k == 0 and not spinning else 0.8)
		reel_view.draw_rect(rect, Color(0.2, 0.05, 0.3), false, 6)
	reel_view.draw_line(Vector2(0, h / 2), Vector2(w, h / 2), Color(1, 0.8, 0.1, 0.35), 3)


func _draw_symbol(c: Vector2, idx: int, s: float) -> void:
	var cv := reel_view
	match Rules.SLOT_SYMBOLS[idx]:
		"CHERRY":
			cv.draw_line(c + Vector2(-18, 5) * s, c + Vector2(6, -40) * s, Color(0.2, 0.5, 0.15), 5)
			cv.draw_line(c + Vector2(20, 10) * s, c + Vector2(6, -40) * s, Color(0.2, 0.5, 0.15), 5)
			cv.draw_circle(c + Vector2(-18, 18) * s, 22 * s, Color(0.85, 0.05, 0.1))
			cv.draw_circle(c + Vector2(20, 22) * s, 22 * s, Color(0.85, 0.05, 0.1))
			cv.draw_circle(c + Vector2(-24, 12) * s, 6 * s, Color(1, 1, 1, 0.6))
		"CLOVER":
			for d in [Vector2(0, -20), Vector2(20, 0), Vector2(0, 20), Vector2(-20, 0)]:
				cv.draw_circle(c + d * s, 20 * s, Color(0.1, 0.65, 0.2))
			cv.draw_circle(c, 10 * s, Color(0.05, 0.4, 0.1))
			cv.draw_line(c + Vector2(0, 18) * s, c + Vector2(10, 48) * s, Color(0.1, 0.5, 0.15), 6)
		"BELL":
			var pts := PackedVector2Array([c + Vector2(0, -42) * s, c + Vector2(22, -30) * s, c + Vector2(28, 10) * s,
				c + Vector2(40, 28) * s, c + Vector2(-40, 28) * s, c + Vector2(-28, 10) * s, c + Vector2(-22, -30) * s])
			cv.draw_colored_polygon(pts, Color(1, 0.75, 0.1))
			cv.draw_circle(c + Vector2(0, 34) * s, 9 * s, Color(0.8, 0.5, 0.05))
		"DIAMOND":
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -44) * s, c + Vector2(36, 0) * s, c + Vector2(0, 44) * s, c + Vector2(-36, 0) * s]), Color(0.2, 0.6, 1))
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -44) * s, c + Vector2(12, 0) * s, c + Vector2(0, 44) * s, c + Vector2(-12, 0) * s]), Color(0.6, 0.85, 1))
		"SEVEN":
			var f := UI.bold()
			var fs := int(96 * s)
			var sw := f.get_string_size("7", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			cv.draw_string_outline(f, c + Vector2(-sw.x / 2, fs * 0.36), "7", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, Color(0.4, 0, 0))
			cv.draw_string(f, c + Vector2(-sw.x / 2, fs * 0.36), "7", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.1, 0.1))


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		spin()
		get_viewport().set_input_as_handled()
