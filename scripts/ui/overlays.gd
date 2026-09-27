extends RefCounted
## Small full-screen overlays: mugshot and day/game summary.

const UI = preload("res://scripts/ui/ui_theme.gd")
const Rules = preload("res://scripts/sim/rules.gd")


class Mugshot extends Control:
	var booking := 4298
	var who := "TRADER"
	var suit := Color(0.2, 0.2, 0.3)
	var t := 0.0

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func play(no: int, pname: String, color: Color) -> void:
		booking = no
		who = pname.to_upper()
		suit = color
		t = 0.0
		visible = true
		Sfx.play("flash")

	func _process(delta: float) -> void:
		if not visible:
			return
		if t < 2.2 and t + delta >= 2.2:
			Sfx.play("flash")
		t += delta
		if t > 4.5:
			visible = false
		queue_redraw()

	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.28, 0.29, 0.33))
		var f := UI.bold()
		for i in 12:
			var y := s.y - 40 - i * (s.y / 12.0)
			draw_line(Vector2(0, y), Vector2(s.x, y), Color(0.1, 0.1, 0.12), 3)
			draw_string(f, Vector2(20, y - 4), "%d'" % (3 + i / 2) if i % 2 == 0 else "", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.1, 0.1, 0.12))
		var side := t > 2.2
		var cx := s.x / 2
		var head_c := Vector2(cx + (30 if side else 0), s.y * 0.33)
		# body
		draw_rect(Rect2(cx - 150, s.y * 0.45, 300, s.y * 0.6), suit)
		draw_rect(Rect2(cx - 30, s.y * 0.45, 60, 120), Color(0.95, 0.95, 0.95))
		draw_rect(Rect2(cx - 10, s.y * 0.46, 20, 110), Color(0.15, 0.3, 0.7))
		draw_circle(head_c, 95, Color(0.96, 0.8, 0.66))
		draw_rect(Rect2(head_c.x - 95, head_c.y - 110, 190, 55), Color(0.15, 0.1, 0.07))
		if not side:
			draw_circle(head_c + Vector2(-35, -5), 16, Color.WHITE)
			draw_circle(head_c + Vector2(35, -5), 16, Color.WHITE)
			draw_circle(head_c + Vector2(-35, -3), 7, Color.BLACK)
			draw_circle(head_c + Vector2(35, -3), 7, Color.BLACK)
			draw_line(head_c + Vector2(-25, 45), head_c + Vector2(25, 45), Color(0.3, 0.1, 0.1), 5)
		else:
			draw_circle(head_c + Vector2(60, -5), 14, Color.WHITE)
			draw_circle(head_c + Vector2(66, -3), 6, Color.BLACK)
		# placard
		if not side:
			var pr := Rect2(cx - 170, s.y * 0.58, 340, 170)
			draw_rect(pr, Color(0.06, 0.06, 0.07))
			draw_rect(pr, Color(0.4, 0.4, 0.4), false, 4)
			var w1 := f.get_string_size("NYPD", HORIZONTAL_ALIGNMENT_LEFT, -1, 72).x
			draw_string(f, Vector2(cx - w1 / 2, pr.position.y + 80), "NYPD", HORIZONTAL_ALIGNMENT_LEFT, -1, 72, Color.WHITE)
			var num := "%06d" % booking
			var w2 := f.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 56).x
			draw_string(f, Vector2(cx - w2 / 2, pr.position.y + 145), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color(0.85, 0.85, 0.85))
		var cap := "%s  —  BOOKED FOR SECURITIES FRAUD" % who
		var cw := f.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
		draw_string_outline(f, Vector2(cx - cw / 2, 70), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, 10, Color.BLACK)
		draw_string(f, Vector2(cx - cw / 2, 70), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, UI.GOLD)
		# flash
		if t < 0.15 or (t > 2.2 and t < 2.35):
			draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.8))


class Summary extends PanelContainer:
	var body: VBoxContainer

	func _ready() -> void:
		add_theme_stylebox_override("panel", UI.panel_box(Color(0.04, 0.06, 0.1, 0.95), UI.GOLD, 20, 5))
		UI.center(self, Vector2(760, 560))
		body = VBoxContainer.new()
		body.add_theme_constant_override("separation", 6)
		add_child(body)
		visible = false

	func show_summary(s: Dictionary) -> void:
		for c in body.get_children():
			c.queue_free()
		var over: bool = s.get("over", false)
		if s.mode == "coop":
			var passed: bool = s.get("passed", false)
			body.add_child(UI.lbl("DAY %d CLOSED" % s.day, 56, UI.GOLD, true))
			body.add_child(UI.lbl("QUOTA MET. THE FUND LIVES." if passed else "MISSED QUOTA. THE FUND IS BUSTED.", 32, UI.GREEN if passed else UI.RED, true))
			body.add_child(UI.lbl("Fund: %s   /   Quota: %s" % [Rules.money(s.balance), Rules.money(s.quota)], 26))
			if not over:
				body.add_child(UI.lbl("Tomorrow's quota: %s" % Rules.money(s.next_quota), 22, UI.DIM))
		else:
			body.add_child(UI.lbl("DAY %d CLOSED" % s.day, 56, UI.GOLD, true))
			if over:
				body.add_child(UI.lbl("WINNER: %s" % s.get("winner", "nobody"), 40, UI.GREEN, true))
			body.add_child(UI.lbl("Quota: %s" % Rules.money(s.quota), 22, UI.DIM))
			var rank := 1
			for r in s.get("ranking", []):
				body.add_child(UI.lbl("%d. %s  %s%s" % [rank, r.name, Rules.money(r.balance), "  (BUSTED)" if r.busted else ""], 26, UI.RED if r.busted else UI.TEXT))
				rank += 1
		body.add_child(UI.lbl("— DESK STATS —", 22, UI.DIM, true))
		var mvp := ""
		var mvp_v := -INF
		for id in s.players:
			var p: Dictionary = s.players[id]
			var st: Dictionary = p.stats
			if st.is_empty():
				continue
			body.add_child(UI.lbl("%s   P&L %s   trades %d   arrests %d   best %s" % [p.name, Rules.money(st.pnl_day), st.trades, st.arrests, Rules.money(st.biggest)], 20))
			if st.pnl_day > mvp_v:
				mvp_v = st.pnl_day
				mvp = p.name
		if mvp != "":
			body.add_child(UI.lbl("WOLF OF THE DAY: %s" % mvp, 26, UI.GOLD, true))
		if over:
			body.add_child(UI.lbl("RUN OVER. Host: press ENTER to go back to the lobby.", 20, UI.DIM))
		else:
			body.add_child(UI.lbl("Next day starts shortly... hit Tony up for items.", 20, UI.DIM))
		visible = true
