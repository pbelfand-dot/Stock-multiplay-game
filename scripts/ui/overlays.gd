extends RefCounted
## Small full-screen overlays: mugshot and day/game summary.

const UI = preload("res://scripts/ui/ui_theme.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const DayEvents = preload("res://scripts/sim/day_events.gd")


class Mugshot extends Control:
	## Booking photo: your actual character in front of the lineup wall,
	## holding the NYPD placard. Front shot, flash, then side profile.
	const Character = preload("res://scripts/art/character.gd")
	const Props = preload("res://scripts/art/props.gd")
	const S = preload("res://scripts/art/shapes.gd")

	var booking := 4298
	var who := "TRADER"
	var t := 0.0
	var vp: SubViewport
	var tex_rect: TextureRect
	var model
	var placard: Node3D

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func _setup_world() -> void:
		vp = SubViewport.new()
		vp.size = Vector2i(1280, 720)
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		tex_rect = TextureRect.new()
		tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex_rect.texture = vp.get_texture()
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tex_rect)
		move_child(tex_rect, 0)
		var w := Node3D.new()
		vp.add_child(w)
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.3, 0.31, 0.35)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color.WHITE
		env.ambient_light_energy = 0.5
		var we := WorldEnvironment.new()
		we.environment = env
		w.add_child(we)
		var l := DirectionalLight3D.new()
		l.rotation_degrees = Vector3(-20, 10, 0)
		l.light_energy = 0.7
		w.add_child(l)
		# lineup wall with height lines
		var wall := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(8, 4, 0.1)
		wall.mesh = bm
		wall.material_override = S.mat(Color(0.36, 0.37, 0.42), false)
		wall.position = Vector3(0, 2, -0.8)
		w.add_child(wall)
		for i in 14:
			var ln := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(8, 0.025 if i % 2 == 0 else 0.012, 0.02)
			ln.mesh = lm
			ln.material_override = S.mat(Color(0.12, 0.12, 0.14), false)
			ln.position = Vector3(0, 0.3 + i * 0.15, -0.74)
			w.add_child(ln)
			if i % 2 == 0:
				var tl := Label3D.new()
				tl.text = "%d'" % (1 + i / 2)
				tl.font_size = 48
				tl.pixel_size = 0.003
				tl.outline_size = 0
				tl.modulate = Color(0.12, 0.12, 0.14)
				tl.position = Vector3(-1.2, 0.36 + i * 0.15, -0.73)
				w.add_child(tl)
		model = Character.new()
		model.rotation.y = PI
		w.add_child(model)
		var cam := Camera3D.new()
		cam.position = Vector3(0, 1.4, 1.55)
		cam.fov = 42
		w.add_child(cam)
		cam.look_at(Vector3(0, 1.3, 0))
		cam.current = true

	func play(no: int, pname: String, look: Dictionary) -> void:
		if vp == null:
			_setup_world()
		booking = no
		who = pname.to_upper()
		model.build(look)
		model.pose = "placard"
		model.eyes_open = 0.55
		model.rotation.y = PI
		placard = Props.placard(no)
		placard.position = Vector3(0, 0.3, -0.3)
		model.j.spine.add_child(placard)
		t = 0.0
		visible = true
		Sfx.play("flash")

	func _process(delta: float) -> void:
		if not visible:
			return
		if t < 2.2 and t + delta >= 2.2:
			Sfx.play("flash")
			model.rotation.y = -PI / 2   # side profile
			if placard:
				placard.visible = false
			model.pose = "cuffed"
		t += delta
		if t > 4.5:
			visible = false
		queue_redraw()

	func _draw() -> void:
		var s := size
		var f := UI.bold()
		var cap := "%s  —  BOOKED FOR SECURITIES FRAUD" % who
		var cw := f.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
		draw_string_outline(f, Vector2(s.x / 2 - cw / 2, 70), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, 10, Color.BLACK)
		draw_string(f, Vector2(s.x / 2 - cw / 2, 70), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, UI.GOLD)
		if t < 0.15 or (t > 2.2 and t < 2.35):
			draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.8))


class Summary extends PanelContainer:
	## After hours: the day's results. The host starts the next day from here
	## (or ENTER), saves, or closes it to walk around and shop first.
	signal start_pressed          # READY toggle (or, when the run is over, the host's back-to-lobby)
	signal force_pressed          # host: START ANYWAY
	signal save_pressed
	signal close_pressed

	var body: VBoxContainer
	var save_lbl: Label
	var ready_lbl: Label
	var ready_btn: Button
	var _over := false

	func _ready() -> void:
		add_theme_stylebox_override("panel", UI.panel_box(Color(0.04, 0.06, 0.1, 0.95), UI.GOLD, 20, 5))
		UI.center(self, Vector2(880, 700))
		body = VBoxContainer.new()
		body.add_theme_constant_override("separation", 4)
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
			body.add_child(UI.lbl("Overhead paid (desk rent, terminals, bottle service): -%s" % Rules.money(s.get("overhead", 0.0)), 20, UI.RED))
			body.add_child(UI.lbl("Fund: %s   /   Quota: %s" % [Rules.money(s.balance), Rules.money(s.quota)], 26))
			if not over:
				body.add_child(UI.lbl("Tomorrow's quota: %s" % Rules.money(s.next_quota), 22, UI.DIM))
		else:
			body.add_child(UI.lbl("DAY %d CLOSED" % s.day, 56, UI.GOLD, true))
			if over:
				body.add_child(UI.lbl("WINNER: %s" % s.get("winner", "nobody"), 40, UI.GREEN, true))
			body.add_child(UI.lbl("Quota: %s" % Rules.money(s.quota), 22, UI.DIM))
			body.add_child(UI.lbl("Everyone paid overhead: -%s" % Rules.money(s.get("overhead", 0.0)), 20, UI.RED))
			var rank := 1
			for r in s.get("ranking", []):
				body.add_child(UI.lbl("%d. %s  %s%s" % [rank, r.name, Rules.money(r.balance), "  (BUSTED)" if r.busted else ""], 26, UI.RED if r.busted else UI.TEXT))
				rank += 1
		if s.get("event", "") != "":
			var ev: Dictionary = DayEvents.info(s.event)
			body.add_child(UI.lbl("TODAY WAS: %s" % ev.name, 22, ev.get("color", UI.GOLD), true))
		if s.get("champ", 0) > 0:
			body.add_child(UI.lbl("%s takes the championship trophy home (%d total). It stays on their desk." % [
					s.get("winner", ""), int(s.champ)], 20, UI.GOLD, true))
		var mine: Array = s.get("contracts", {}).get(Net.my_id(), [])
		if not mine.is_empty():
			var done := 0
			for c in mine:
				done += 1 if c.done else 0
			body.add_child(UI.lbl("Tony's contracts: %d / %d done" % [done, mine.size()], 20, UI.GREEN if done > 0 else UI.DIM))
		body.add_child(UI.lbl("— DESK STATS —", 22, UI.DIM, true))
		var mvp := ""
		var mvp_v := -INF
		for id in s.players:
			var p: Dictionary = s.players[id]
			var st: Dictionary = p.stats
			if st.is_empty():
				continue
			body.add_child(UI.lbl("%s   P&L %s   trades %d   arrests %d   best %s" % [p.name, Rules.money(st.pnl_day), st.trades, st.arrests, Rules.money(st.biggest)], 20))
			var xp: Dictionary = s.get("xp", {}).get(id, {})
			if not xp.is_empty():
				body.add_child(UI.lbl("      +%d XP  →  %s (%d XP)%s" % [int(xp.gain), Rules.RANKS[xp.rank].name, int(xp.xp),
						"   RANK UP!" if xp.ranked_up else ""], 18, UI.GOLD if xp.ranked_up else UI.DIM, xp.ranked_up))
			if st.pnl_day > mvp_v:
				mvp_v = st.pnl_day
				mvp = p.name
		if mvp != "":
			body.add_child(UI.lbl("WOLF OF THE DAY: %s" % mvp, 26, UI.GOLD, true))
		var tomorrow: String = s.get("tomorrow", "")
		if not over and tomorrow != "":
			var tv: Dictionary = DayEvents.info(tomorrow)
			body.add_child(UI.lbl("TOMORROW: %s — %s" % [tv.name, tv.forecast], 22, tv.get("color", UI.GOLD), true))
		elif not over and s.has("tomorrow"):
			body.add_child(UI.lbl("TOMORROW: a normal day. Probably.", 20, UI.DIM))
		if not over:
			body.add_child(UI.lbl("The market waits for you. Close this to walk around, hit Tony up, go shopping." if Net.is_server()
					else "The host starts the next day. Close this to walk around and shop in the meantime.", 18, UI.DIM))
		var sv: Dictionary = s.get("saved", {})
		if sv.has("slot"):
			body.add_child(UI.lbl(("✓ Game saved%s — CONTINUE from the main menu anytime." % (" to iCloud Drive" if sv.get("cloud", false) else ""))
					if not over else "Run saved as finished (busted runs can't be continued).", 16, UI.GREEN if not over else UI.DIM))
		elif sv.has("error"):
			body.add_child(UI.lbl("Couldn't write the save file.", 16, UI.RED))
		save_lbl = UI.lbl("", 16, UI.GREEN)
		body.add_child(save_lbl)
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(sp)
		_over = over
		ready_lbl = UI.lbl("", 18, UI.GOLD, true)
		ready_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		body.add_child(ready_lbl)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		body.add_child(row)
		ready_btn = null
		if over:
			if Net.is_server():
				var back := UI.btn("BACK TO THE LOBBY  [ENTER]", UI.GREEN.darkened(0.3), 24)
				back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				back.pressed.connect(func(): start_pressed.emit())
				row.add_child(back)
			else:
				var wait := UI.lbl("Waiting for the host...", 20, UI.GOLD, true)
				wait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(wait)
		else:
			ready_btn = UI.btn("", UI.GREEN.darkened(0.3), 24)
			ready_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ready_btn.pressed.connect(func(): start_pressed.emit())
			row.add_child(ready_btn)
			if Net.is_server():
				if Net.players.size() > 1:
					var force := UI.btn("START ANYWAY", UI.RED.darkened(0.35), 20)
					force.pressed.connect(func(): force_pressed.emit())
					row.add_child(force)
				var sv_btn := UI.btn("SAVE GAME", UI.GOLD.darkened(0.4), 22)
				sv_btn.pressed.connect(func(): save_pressed.emit())
				row.add_child(sv_btn)
		var close := UI.btn("CLOSE  [ESC]", UI.NAVY_2, 22)
		close.pressed.connect(func(): close_pressed.emit())
		row.add_child(close)
		visible = true
		update_ready(s.day, {})

	## Who's pressed READY: "READY 1/3 — waiting on Bob, Dave".
	func update_ready(day_done: int, ready: Dictionary) -> void:
		if ready_lbl == null or _over:
			return
		var waiting: Array = []
		for id in Net.players:
			if not ready.has(id):
				waiting.append(Net.player_name(id))
		var me_ready := ready.has(Net.my_id())
		if ready_btn:
			ready_btn.text = ("✓ READY — waiting  [ENTER to cancel]" if me_ready else "READY FOR DAY %d  [ENTER]" % (day_done + 1))
		if Net.players.size() <= 1:
			ready_lbl.text = ""
		else:
			ready_lbl.text = "READY %d/%d%s" % [Net.players.size() - waiting.size(), Net.players.size(),
					("  ·  waiting on " + ", ".join(waiting)) if not waiting.is_empty() else ""]

	func show_saved(info: Dictionary) -> void:
		if save_lbl:
			save_lbl.text = saved_text(info)
			save_lbl.add_theme_color_override("font_color", UI.RED if info.has("error") else UI.GREEN)

	## "✓ Saved to iCloud Drive. CONTINUE picks up at day 3" (the pause menu uses it too).
	static func saved_text(info: Dictionary) -> String:
		if info.has("error"):
			return str(info.error)
		var where := " to iCloud Drive" if info.get("cloud", false) else ""
		if info.get("mid_day", false):
			return "✓ Saved%s: this morning's bell. CONTINUE restarts day %d (today's trades aren't in it)." % [where, int(info.next_day)]
		return "✓ Saved%s. CONTINUE picks up at day %d." % [where, int(info.next_day)]


class Unbox extends Control:
	## First-person Crownwell unboxing: the green box opens, the watch rises and
	## spins in the light. Plays for ~3.2 s when you buy a watch.
	const PropKit = preload("res://scripts/art/prop_kit.gd")

	var vp: SubViewport
	var lid: Node3D
	var watch: Node3D
	var world3d: Node3D
	var caption: Label
	var t := 0.0
	var iced := false

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
		set_process(false)

	func _setup() -> void:
		vp = SubViewport.new()
		vp.size = Vector2i(900, 700)
		vp.own_world_3d = true
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var tr := TextureRect.new()
		tr.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		tr.custom_minimum_size = Vector2(900, 700)
		tr.position = -Vector2(450, 330)
		tr.texture = vp.get_texture()
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
		world3d = Node3D.new()
		vp.add_child(world3d)
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color.WHITE
		env.ambient_light_energy = 0.7
		var we := WorldEnvironment.new()
		we.environment = env
		world3d.add_child(we)
		var l := DirectionalLight3D.new()
		l.rotation_degrees = Vector3(-50, 30, 0)
		world3d.add_child(l)
		var cam := Camera3D.new()
		cam.position = Vector3(0, 0.46, 0.44)
		cam.rotation_degrees = Vector3(-44, 0, 0)
		cam.fov = 34
		world3d.add_child(cam)
		PropKit.place("WatchBoxBase", world3d)
		lid = PropKit.place("WatchBoxLid", world3d, Vector3(0, 0.08, -0.1))
		caption = UI.lbl("", 64, UI.GOLD, true)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		caption.position.y -= 190
		caption.add_theme_color_override("font_outline_color", Color.BLACK)
		caption.add_theme_constant_override("outline_size", 12)
		add_child(caption)

	func play(is_iced: bool) -> void:
		if vp == null:
			_setup()
		iced = is_iced
		if watch:
			watch.queue_free()
		watch = PropKit.place("WatchIced" if iced else "WatchGold", world3d, Vector3(0, 0.09, 0.01))
		watch.rotation.x = -0.5
		caption.text = "CROWNWELL GENÈVE\n%s" % ("ICED OUT" if iced else "DATEJUST")
		caption.modulate.a = 0.0
		t = 0.0
		visible = true
		set_process(true)
		Sfx.play("jackpot")

	func _process(delta: float) -> void:
		t += delta
		var open := clampf((t - 0.3) / 0.6, 0.0, 1.0)
		lid.rotation.x = -open * 1.9
		watch.position.y = 0.09 + clampf((t - 0.9) / 0.6, 0.0, 1.0) * 0.045
		watch.rotation.y = t * 1.6
		caption.modulate.a = clampf((t - 0.8) * 3.0, 0.0, 1.0) * clampf((3.2 - t) * 3.0, 0.0, 1.0)
		modulate.a = clampf(t * 5.0, 0.0, 1.0) * clampf((3.3 - t) * 4.0, 0.0, 1.0)
		if t > 3.3:
			visible = false
			set_process(false)
