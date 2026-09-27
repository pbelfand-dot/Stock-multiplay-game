extends RefCounted
## Small full-screen overlays: mugshot and day/game summary.

const UI = preload("res://scripts/ui/ui_theme.gd")
const Rules = preload("res://scripts/sim/rules.gd")


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
