extends Control
## THE TAILOR — customize your trader: outfit, colors, pinstripes, shirt,
## tie, pants, shoes, hair, skin tone, beard, glasses, hat, watch, chain.
## Live 3D preview on a turntable (drag to spin). Saved to settings and sent
## to everyone when you join a game.

const UI = preload("res://scripts/ui/ui_theme.gd")
const Character = preload("res://scripts/art/character.gd")

signal done

var look := {}
var preview
var vp: SubViewport
var turn := 0.0
var _dragging := false
var rows: VBoxContainer
var _pose_i := 0

const POSES := ["idle", "smoke", "hold", "cheer", "aim"]
const LABELS := {
	"outfit": "OUTFIT", "hair_style": "HAIR", "beard": "FACIAL HAIR", "glasses": "GLASSES",
	"hat": "HAT", "shoe_style": "SHOES", "watch": "WATCH",
}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	look = Character.full_look(Config.look if not Config.look.is_empty() else Character.player_look(0))
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.05, 0.06)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 24
	h.offset_top = 20
	h.offset_right = -24
	h.offset_bottom = -20
	h.add_theme_constant_override("separation", 20)
	add_child(h)

	# ---------------- preview ----------------
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	left.add_child(UI.lbl("THE TAILOR", 64, UI.GOLD, true))
	left.add_child(UI.lbl("\"Dress for the job you want. The job is securities fraud.\"", 18, UI.DIM))
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.gui_input.connect(_on_preview_input)
	left.add_child(svc)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	_build_stage()
	var pr := HBoxContainer.new()
	left.add_child(pr)
	var pose_btn := UI.btn("STRIKE A POSE", UI.NAVY_2, 20)
	pose_btn.pressed.connect(func():
		_pose_i = (_pose_i + 1) % POSES.size()
		preview.pose = POSES[_pose_i])
	pr.add_child(pose_btn)
	pr.add_child(UI.lbl("   drag to spin", 16, UI.DIM))

	# ---------------- options ----------------
	var right := PanelContainer.new()
	right.custom_minimum_size.x = 620
	right.add_theme_stylebox_override("panel", UI.panel_box(Color(0.05, 0.07, 0.12, 0.95), UI.GOLD, 16, 3))
	h.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)
	var foot := HBoxContainer.new()
	rv.add_child(foot)
	var rnd := UI.btn("RANDOMIZE", Color(0.35, 0.15, 0.55), 22)
	rnd.pressed.connect(func():
		look = Character.full_look(Character.random_look())
		_refresh())
	foot.add_child(rnd)
	var rst := UI.btn("RESET", UI.NAVY_2, 22)
	rst.pressed.connect(func():
		look = Character.full_look(Character.player_look(0))
		_refresh())
	foot.add_child(rst)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	var ok := UI.btn("SAVE & BACK", UI.GREEN.darkened(0.3), 24)
	ok.pressed.connect(_save)
	foot.add_child(ok)
	_refresh()


func _build_stage() -> void:
	var w := Node3D.new()
	vp.add_child(w)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.1, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 0.96, 0.92)
	env.ambient_light_energy = 0.45
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 0.8
	key.shadow_enabled = true
	w.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.5, 2.2, -1.5)
	rim.light_color = Color(1, 0.8, 0.4)
	rim.light_energy = 1.2
	rim.omni_range = 5
	w.add_child(rim)
	# red carpet pedestal
	var ped := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.7
	cm.bottom_radius = 0.75
	cm.height = 0.12
	ped.mesh = cm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.55, 0.05, 0.07)
	ped.material_override = pm
	ped.position.y = -0.06
	w.add_child(ped)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.72
	tm.outer_radius = 0.77
	ring.mesh = tm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(1, 0.78, 0.2)
	gm.metallic = 0.8
	gm.roughness = 0.3
	ring.material_override = gm
	w.add_child(ring)
	preview = Character.new()
	preview.rotation.y = PI
	w.add_child(preview)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.2, 2.55)
	cam.fov = 40
	w.add_child(cam)
	cam.look_at(Vector3(0, 1.08, 0))
	cam.current = true


func _process(delta: float) -> void:
	if preview and not _dragging:
		turn += delta * 0.35
	if preview:
		preview.rotation.y = PI + sin(turn) * 0.9


func _on_preview_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_dragging = e.pressed
	elif e is InputEventMouseMotion and _dragging:
		turn += e.relative.x * 0.01


# ------------------------------------------------------------------ option rows

func _refresh() -> void:
	preview.build(look)
	preview.pose = POSES[_pose_i]
	for c in rows.get_children():
		c.queue_free()
	_cycle("outfit")
	var outfit: String = look.outfit
	_swatches("TOP COLOR" if outfit != "suit" else "SUIT COLOR", "suit", Character.SUIT_COLORS)
	if outfit == "suit":
		_toggle("PINSTRIPES", "pinstripe")
		_swatches("SHIRT", "shirt", [Color(0.96, 0.96, 0.97), Color(0.7, 0.8, 0.95), Color(0.95, 0.85, 0.9), Color(0.1, 0.1, 0.12), Color(0.95, 0.9, 0.7)])
	if outfit in ["suit", "shirt"]:
		_swatches("TIE", "tie", Character.ACCENT_COLORS)
		_toggle("LONG TIE (presidential)", "long_tie")
	_swatches("PANTS", "pants", [null] + Character.SUIT_COLORS + [Color(0.2, 0.25, 0.4)])
	_cycle("shoe_style")
	_swatches("SHOE COLOR", "shoes", [Color(0.07, 0.07, 0.08), Color(0.35, 0.2, 0.1), Color(0.9, 0.9, 0.9), Color(0.8, 0.15, 0.15), Color(0.15, 0.3, 0.75)])
	_cycle("hair_style")
	_swatches("HAIR COLOR", "hair", Character.HAIR_COLORS)
	_swatches("SKIN TONE", "skin", Character.SKIN_TONES)
	_cycle("beard")
	_cycle("glasses")
	_cycle("hat")
	if look.hat in ["headband", "beanie", "cap", "bowler", "bucket"]:
		_swatches("HAT COLOR", "hat_color", Character.ACCENT_COLORS)
	_cycle("watch")
	_toggle("GOLD CHAIN", "chain")
	_toggle("PINKY RING", "ring")
	_toggle("BLOODSHOT EYES", "bloodshot")


func _row(title: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	var l := UI.lbl(title, 20, UI.TEXT, true)
	l.custom_minimum_size.x = 190
	r.add_child(l)
	rows.add_child(r)
	return r


func _cycle(key: String) -> void:
	var r := _row(LABELS.get(key, key.to_upper()))
	var opts: Array = Character.OPTIONS[key]
	var prev := UI.btn(" < ", UI.NAVY_2, 20)
	var val := UI.lbl(str(look[key]).to_upper(), 22, UI.GOLD, true)
	val.custom_minimum_size.x = 170
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var next := UI.btn(" > ", UI.NAVY_2, 20)
	prev.pressed.connect(func(): _step(key, -1))
	next.pressed.connect(func(): _step(key, 1))
	r.add_child(prev)
	r.add_child(val)
	r.add_child(next)


func _step(key: String, d: int) -> void:
	var opts: Array = Character.OPTIONS[key]
	var i := opts.find(look[key])
	look[key] = opts[posmod(i + d, opts.size())]
	Sfx.play("click")
	_refresh()


func _swatches(title: String, key: String, colors: Array) -> void:
	var r := _row(title)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(flow)
	for c in colors:
		var b := Button.new()
		b.custom_minimum_size = Vector2(34, 34)
		var col: Color = c if c != null else Color(0.3, 0.3, 0.3)
		var sel: bool = (look.get(key) == c) or (c == null and look.get(key) == null)
		var sb := UI.panel_box(col, UI.GOLD if sel else Color(0, 0, 0, 0.5), 17, 3 if sel else 2)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", UI.panel_box(col.lightened(0.15), Color.WHITE, 17, 3))
		b.add_theme_stylebox_override("pressed", sb)
		if c == null:
			b.text = "="
			b.tooltip_text = "match the top"
		var cv = c
		b.pressed.connect(func():
			look[key] = cv
			Sfx.play("click")
			_refresh())
		flow.add_child(b)


func _toggle(title: String, key: String) -> void:
	var r := _row(title)
	var b := UI.btn("ON" if look[key] else "OFF", UI.GREEN.darkened(0.3) if look[key] else UI.NAVY_2, 20)
	b.custom_minimum_size.x = 90
	b.pressed.connect(func():
		look[key] = not look[key]
		Sfx.play("click")
		_refresh())
	r.add_child(b)


func _save() -> void:
	Config.look = Character.sanitize(look)
	Config.save_settings()
	Sfx.play("cash")
	done.emit()
