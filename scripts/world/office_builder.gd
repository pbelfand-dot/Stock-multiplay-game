extends RefCounted
## Builds the whole office out of primitives (no art budget needed).
## Red-carpet trading floor, CRT desks, elevator, lounge, casino corner,
## TV wall, ticker strip, whiteboard, hoop, and a holding cell.
##
## Coordinates: floor spans x -20..20, z -14..14. North (z-) = windows.

const W := 40.0
const D := 28.0
const H := 3.4

const C_CARPET := Color(0.55, 0.05, 0.06)
const C_WALL := Color(0.93, 0.84, 0.72)
const C_TRIM := Color(0.42, 0.06, 0.08)
const C_CEIL := Color(0.86, 0.87, 0.9)
const C_DESK := Color(0.92, 0.92, 0.9)
const C_BEIGE := Color(0.86, 0.8, 0.66)
const C_SCREEN := Color(0.05, 0.1, 0.18)
const C_METAL := Color(0.6, 0.62, 0.66)
const C_DARK := Color(0.12, 0.12, 0.14)
const C_CHAIR := Color(0.1, 0.45, 0.6)

var mats := {}
var root: Node3D
var nav: NavigationRegion3D
var interactables: Array = []   # [{node, type, id}]
var spawn_points: Array = []
var elevator_pos := Vector3(0, 0.1, 11.5)
var jail_pos := Vector3(0, 0.1, 42.0)
var tv_screen: MeshInstance3D
var ticker_label: Label3D
var slot_machines: Array = []
var npcs := {}                  # speaker name -> Node3D (has "Bubble" Label3D)
var hoop_rim := Vector3(-W / 2 + 0.5, 2.05, -9.5)
var ball_spawn := Vector3(-16.5, 1.0, -9.5)


func mat(c: Color, emissive: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%s" % [c.to_html(), emissive]
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	mats[key] = m
	return m


func build(parent: Node3D) -> void:
	root = Node3D.new()
	root.name = "Office"
	parent.add_child(root)
	nav = NavigationRegion3D.new()
	nav.name = "Nav"
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_max_climb = 0.25
	nm.filter_baking_aabb = AABB(Vector3(-W / 2, -1, -D / 2), Vector3(W, 4, D))
	nav.navigation_mesh = nm
	root.add_child(nav)
	_environment()
	_shell()
	_windows_and_skyline()
	_ceiling_lights()
	_bullpen()
	_elevator()
	_lounge()
	_casino()
	_tv_wall()
	_west_wall()
	_bell_podium()
	_ticker()
	_holding_cell()
	_streamer_corner()
	for i in 6:
		spawn_points.append(Vector3(-3.0 + i * 1.2, 0.1, 10.5))


# ------------------------------------------------------------------ helpers

func box(size: Vector3, pos: Vector3, color: Color, collide := true, parent: Node3D = null, emissive := 0.0) -> MeshInstance3D:
	var p := parent if parent else (nav as Node3D)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat(color, emissive)
	mi.position = pos
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	p.add_child(mi)
	return mi


func cyl(radius: float, height: float, pos: Vector3, color: Color, collide := false, parent: Node3D = null) -> MeshInstance3D:
	var p := parent if parent else (nav as Node3D)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 14
	mi.mesh = cm
	mi.material_override = mat(color)
	mi.position = pos
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = height
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	p.add_child(mi)
	return mi


func sphere(radius: float, pos: Vector3, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var p := parent if parent else (nav as Node3D)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = mat(color)
	mi.position = pos
	p.add_child(mi)
	return mi


func label(text: String, pos: Vector3, size: int, color: Color, rot_y := 0.0, parent: Node3D = null) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.005
	l.modulate = color
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.6)
	l.position = pos
	l.rotation.y = rot_y
	l.double_sided = false
	(parent if parent else root).add_child(l)
	return l


func add_interact(node: Node3D, type: String, id: int, prompt: String) -> void:
	# Separate Area-less marker: we raycast against StaticBody3D and read meta.
	for c in node.get_children():
		if c is StaticBody3D:
			c.set_meta("interact", type)
			c.set_meta("interact_id", id)
			c.set_meta("prompt", prompt)
	interactables.append({"node": node, "type": type, "id": id})


# ------------------------------------------------------------------ pieces

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.78, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 0.97, 0.92)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	root.add_child(sun)
	for p in [Vector3(-10, 3.0, -5), Vector3(8, 3.0, -5), Vector3(-10, 3.0, 7), Vector3(10, 3.0, 7)]:
		var o := OmniLight3D.new()
		o.position = p
		o.omni_range = 14.0
		o.light_energy = 0.6
		o.light_color = Color(1, 0.96, 0.88)
		root.add_child(o)


func _shell() -> void:
	box(Vector3(W, 0.2, D), Vector3(0, -0.1, 0), C_CARPET)                        # floor
	box(Vector3(W, 0.2, D), Vector3(0, H + 0.1, 0), C_CEIL, false, root)          # ceiling
	# south wall with elevator gap
	box(Vector3(W / 2 - 1.3, H, 0.3), Vector3(-(W / 4 + 0.65), H / 2, D / 2), C_WALL)
	box(Vector3(W / 2 - 1.3, H, 0.3), Vector3(W / 4 + 0.65, H / 2, D / 2), C_WALL)
	box(Vector3(2.6, H - 2.4, 0.3), Vector3(0, 2.4 + (H - 2.4) / 2, D / 2), C_WALL)
	box(Vector3(0.3, H, D), Vector3(-W / 2, H / 2, 0), C_WALL)                     # west
	box(Vector3(0.3, H, D), Vector3(W / 2, H / 2, 0), C_WALL)                      # east
	# red trim bands
	for z in [D / 2 - 0.16, -D / 2 + 0.16]:
		box(Vector3(W, 0.25, 0.04), Vector3(0, H - 0.3, z), C_TRIM, false, root)
		box(Vector3(W, 0.12, 0.04), Vector3(0, 0.06, z), C_TRIM, false, root)
	for x in [-W / 2 + 0.16, W / 2 - 0.16]:
		box(Vector3(0.04, 0.25, D), Vector3(x, H - 0.3, 0), C_TRIM, false, root)
		box(Vector3(0.04, 0.12, D), Vector3(x, 0.06, 0), C_TRIM, false, root)


func _windows_and_skyline() -> void:
	# North wall: low sill + frames + glass, skyline beyond.
	box(Vector3(W, 0.9, 0.3), Vector3(0, 0.45, -D / 2), C_WALL)
	box(Vector3(W, 0.4, 0.3), Vector3(0, H - 0.2, -D / 2), C_WALL)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.85, 1.0, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var g := box(Vector3(W, H - 1.3, 0.05), Vector3(0, 0.9 + (H - 1.3) / 2, -D / 2), Color.WHITE)
	g.material_override = glass
	var x := -W / 2
	while x <= W / 2:
		box(Vector3(0.18, H, 0.34), Vector3(x, H / 2, -D / 2), Color(0.55, 0.55, 0.58), false, root)
		x += 4.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var skyline := Node3D.new()
	root.add_child(skyline)
	for i in 70:
		var bw := rng.randf_range(3, 8)
		var bh := rng.randf_range(10, 60)
		var bx := rng.randf_range(-90, 90)
		var bz := rng.randf_range(-35, -110)
		var shade := rng.randf_range(0.55, 0.8)
		box(Vector3(bw, bh, bw), Vector3(bx, bh / 2 - 20, bz), Color(shade * 0.85, shade * 0.9, shade), false, skyline)
		# window stripes
		for k in int(bh / 6):
			box(Vector3(bw + 0.05, 0.6, bw + 0.05), Vector3(bx, -20 + 3 + k * 6.0, bz), Color(0.75, 0.85, 0.95), false, skyline)
	# spire like the Empire State in the trailer
	box(Vector3(8, 80, 8), Vector3(10, 20, -70), Color(0.66, 0.7, 0.78), false, skyline)
	box(Vector3(4, 12, 4), Vector3(10, 66, -70), Color(0.66, 0.7, 0.78), false, skyline)
	cyl(0.4, 14, Vector3(10, 79, -70), Color(0.66, 0.7, 0.78), false, skyline)


func _ceiling_lights() -> void:
	var x := -16.0
	while x <= 16.0:
		var z := -11.0
		while z <= 11.0:
			box(Vector3(1.8, 0.03, 1.1), Vector3(x, H - 0.01, z), Color(1, 1, 0.97), false, root, 1.4)
			z += 4.4
		x += 4.0


func _bullpen() -> void:
	var id := 0
	for row_z in [-9.5, -5.5, -1.5, 2.5]:
		var x := -13.0
		while x <= 7.0:
			_desk(Vector3(x, 0, row_z), id)
			id += 1
			x += 4.0


func _desk(p: Vector3, id: int) -> void:
	box(Vector3(1.9, 0.06, 0.9), p + Vector3(0, 0.75, 0), C_DESK)
	for dx in [-0.88, 0.88]:
		box(Vector3(0.06, 0.75, 0.85), p + Vector3(dx, 0.375, 0), C_METAL, false)
	# cubicle divider behind
	box(Vector3(1.9, 1.3, 0.06), p + Vector3(0, 0.65, -0.48), Color(0.8, 0.76, 0.7))
	# CRT
	var crt := box(Vector3(0.6, 0.5, 0.55), p + Vector3(0, 1.03, -0.12), C_BEIGE)
	box(Vector3(0.5, 0.38, 0.02), Vector3(0, 0.0, 0.28), C_SCREEN, false, crt, 0.6)
	box(Vector3(0.3, 0.05, 0.3), p + Vector3(0, 0.79, -0.12), C_BEIGE, false)
	var scr := label("BTC", Vector3(0, 0.02, 0.3), 36, Color(0.3, 1, 0.5), 0.0, crt)
	scr.name = "ScreenText"
	# keyboard + mouse + lamp
	box(Vector3(0.55, 0.03, 0.18), p + Vector3(0, 0.795, 0.22), C_BEIGE, false)
	box(Vector3(0.08, 0.03, 0.12), p + Vector3(0.45, 0.795, 0.22), C_BEIGE, false)
	cyl(0.02, 0.4, p + Vector3(-0.7, 0.98, -0.2), C_DARK)
	var shade := cyl(0.12, 0.12, p + Vector3(-0.7, 1.2, -0.12), C_DARK)
	shade.rotation.x = 0.6
	# chair
	cyl(0.25, 0.08, p + Vector3(0, 0.48, 0.85), C_CHAIR, false)
	box(Vector3(0.48, 0.5, 0.08), p + Vector3(0, 0.8, 1.1), C_CHAIR, false)
	cyl(0.04, 0.45, p + Vector3(0, 0.22, 0.85), C_DARK, false)
	add_interact(crt, "terminal", id, "[E] Trade")


func _elevator() -> void:
	var z := D / 2 - 0.1
	box(Vector3(2.8, 2.6, 0.2), Vector3(0, 1.3, z + 0.1), C_METAL, false, root)
	box(Vector3(1.1, 2.3, 0.08), Vector3(-0.56, 1.15, z - 0.05), Color(0.72, 0.74, 0.78), true)
	box(Vector3(1.1, 2.3, 0.08), Vector3(0.56, 1.15, z - 0.05), Color(0.72, 0.74, 0.78), true)
	box(Vector3(0.5, 0.2, 0.05), Vector3(0, 2.5, z - 0.1), C_DARK, false, root)
	label("12", Vector3(0, 2.5, z - 0.14), 40, Color(0.2, 1, 0.3), PI)
	box(Vector3(0.12, 0.25, 0.05), Vector3(1.6, 1.2, z - 0.1), C_METAL, false, root)


func _lounge() -> void:
	# couch
	box(Vector3(2.4, 0.45, 0.9), Vector3(-16, 0.225, 12.6), Color(0.4, 0.42, 0.46))
	box(Vector3(2.4, 0.5, 0.25), Vector3(-16, 0.7, 13.0), Color(0.4, 0.42, 0.46), false)
	# yellow beanbag
	var bb := sphere(0.55, Vector3(-12.5, 0.35, 12.2), Color(0.98, 0.72, 0.1))
	bb.scale = Vector3(1, 0.65, 1)
	# round coffee table
	cyl(0.6, 0.4, Vector3(-16, 0.2, 10.8), C_BEIGE, true)
	# plant
	cyl(0.22, 0.4, Vector3(-19.2, 0.2, 7), Color(0.9, 0.9, 0.88))
	sphere(0.45, Vector3(-19.2, 0.8, 7), Color(0.2, 0.55, 0.25))
	# vending machine
	var vm := box(Vector3(1.0, 2.0, 0.8), Vector3(-19.4, 1.0, 9.5), Color(0.05, 0.25, 0.7))
	vm.rotation.y = PI / 2
	label("MONSTAR\nENERGY", Vector3(0, 0.55, 0.42), 48, Color(0.7, 1, 0.3), 0.0, vm)
	box(Vector3(0.7, 1.0, 0.02), Vector3(0, -0.1, 0.41), Color(0.1, 0.1, 0.15), false, vm, 0.3)
	# Dealer NPC (the cigar guy from the trailer)
	var dealer := Node3D.new()
	dealer.position = Vector3(-15.0, 0, 8.6)
	dealer.rotation.y = PI * 0.9
	nav.add_child(dealer)
	var body := box(Vector3(0.6, 1.1, 0.35), Vector3(0, 0.95, 0), C_DARK, true, dealer)
	box(Vector3(0.62, 0.5, 0.37), Vector3(0, -0.8, 0), C_DARK, false, body)
	sphere(0.24, Vector3(0, 1.72, 0), Color(0.96, 0.8, 0.66), dealer)
	box(Vector3(0.44, 0.12, 0.44), Vector3(0, 1.9, -0.02), Color(0.12, 0.1, 0.08), false, dealer)
	box(Vector3(0.12, 0.35, 0.02), Vector3(0, 1.2, 0.18), Color(0.95, 0.95, 0.95), false, dealer)
	for ex in [-0.08, 0.08]:
		sphere(0.035, Vector3(ex, 1.76, 0.21), Color(0.05, 0.05, 0.05), dealer)
	var cigar := cyl(0.025, 0.2, Vector3(0.1, 1.64, 0.26), Color(0.45, 0.28, 0.12), false, dealer)
	cigar.rotation.x = PI / 2
	sphere(0.03, Vector3(0.1, 1.64, 0.36), Color(1, 0.4, 0.1), dealer)
	label("TONY \"THE PLUG\"\n[E] Shop", Vector3(0, 2.25, 0), 40, Color(1, 0.85, 0.3), 0.0, dealer).billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_interact(body, "shop", 0, "[E] Talk to Tony")


func _casino() -> void:
	label("BAG SLOTS", Vector3(W / 2 - 0.2, 2.9, -8.5), 90, Color(1, 0.85, 0.1), -PI / 2)
	var i := 0
	for z in [-12.0, -10.0, -8.0, -6.0]:
		var sm := Node3D.new()
		sm.position = Vector3(W / 2 - 0.8, 0, z)
		sm.rotation.y = -PI / 2
		nav.add_child(sm)
		var body := box(Vector3(1.1, 1.9, 0.9), Vector3(0, 0.95, 0), Color(0.18, 0.12, 0.3), true, sm)
		box(Vector3(1.15, 0.4, 0.95), Vector3(0, 1.1, 0), Color(1, 0.72, 0.1), false, body, 0.4)
		box(Vector3(0.85, 0.5, 0.02), Vector3(0, 0.2, 0.46), Color(0.95, 0.95, 0.9), false, body, 0.2)
		for k in 3:
			box(Vector3(0.03, 0.5, 0.03), Vector3(-0.14 + k * 0.28 - 0.14, 0.2, 0.47), Color(0.4, 0.1, 0.6), false, body)
		box(Vector3(0.95, 0.1, 0.4), Vector3(0, -0.2, 0.55), C_DARK, false, body)
		var lever := cyl(0.03, 0.6, Vector3(0.65, 0.35, 0.1), C_METAL, false, body)
		sphere(0.08, Vector3(0, 0.33, 0), Color(0.15, 0.25, 0.8), lever)
		var l := label("777", Vector3(0, 0.2, 0.48), 64, Color(0.9, 0.1, 0.1), 0.0, body)
		l.name = "ReelText"
		add_interact(body, "slots", i, "[E] Play slots")
		slot_machines.append(body)
		i += 1


func _tv_wall() -> void:
	var tv := Node3D.new()
	tv.position = Vector3(W / 2 - 0.2, 1.9, 5.5)
	tv.rotation.y = -PI / 2
	root.add_child(tv)
	box(Vector3(4.4, 2.5, 0.12), Vector3.ZERO, C_DARK, false, tv)
	tv_screen = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(4.2, 2.3)
	tv_screen.mesh = q
	tv_screen.position = Vector3(0, 0, 0.07)
	tv.add_child(tv_screen)


func _west_wall() -> void:
	# Whiteboard — MONEY TALKS
	var wb := Node3D.new()
	wb.position = Vector3(-W / 2 + 0.2, 1.6, -1.5)
	wb.rotation.y = PI / 2
	root.add_child(wb)
	box(Vector3(3.6, 1.6, 0.06), Vector3.ZERO, Color(0.97, 0.97, 0.97), false, wb)
	box(Vector3(3.7, 0.05, 0.12), Vector3(0, -0.82, 0.05), C_METAL, false, wb)
	label("MONEY\nTALKS", Vector3(0, 0, 0.05), 150, Color(0.1, 0.1, 0.12), 0.0, wb).outline_size = 0
	# Basketball hoop + certificates
	var hp := Node3D.new()
	hp.position = Vector3(-W / 2 + 0.2, 2.5, -9.5)
	hp.rotation.y = PI / 2
	root.add_child(hp)
	box(Vector3(1.5, 1.0, 0.05), Vector3.ZERO, Color(0.95, 0.95, 0.97), false, hp)
	box(Vector3(0.6, 0.45, 0.06), Vector3(0, -0.12, 0.01), Color(0.9, 0.15, 0.1), false, hp)
	box(Vector3(0.5, 0.35, 0.07), Vector3(0, -0.12, 0.01), Color(0.95, 0.95, 0.97), false, hp)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.2
	tm.outer_radius = 0.24
	rim.mesh = tm
	rim.material_override = mat(Color(0.95, 0.3, 0.1))
	rim.position = Vector3(0, -0.4, 0.3)
	hp.add_child(rim)
	for k in 4:
		box(Vector3(0.4, 0.3, 0.03), Vector3(-1.4 - (k % 2) * 0.5, 0.1 - (k / 2) * 0.4, 0), Color(0.45, 0.3, 0.15), false, hp)
		box(Vector3(0.34, 0.24, 0.035), Vector3(-1.4 - (k % 2) * 0.5, 0.1 - (k / 2) * 0.4, 0.005), Color(0.96, 0.93, 0.85), false, hp)
	# arcade cabinet
	var ac := box(Vector3(0.9, 1.9, 0.8), Vector3(-W / 2 + 0.7, 0.95, -5.5), Color(0.9, 0.5, 0.05))
	box(Vector3(0.02, 0.6, 0.6), Vector3(0.46, 0.35, 0), Color(0.1, 0.1, 0.2), false, ac, 0.5)


func _bell_podium() -> void:
	box(Vector3(0.9, 1.1, 0.6), Vector3(7, 0.55, 8.0), Color(0.25, 0.15, 0.1))
	var bell := cyl(0.18, 0.22, Vector3(7, 1.25, 8.0), Color(1, 0.8, 0.2))
	bell.scale = Vector3(1, 1, 1)
	var l := label("OPENING BELL\nhost: press ENTER", Vector3(7, 1.9, 8.0), 40, Color(1, 0.9, 0.5))
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.name = "BellLabel"


func _ticker() -> void:
	box(Vector3(W - 1, 0.5, 0.05), Vector3(0, H - 0.7, -D / 2 + 0.2), Color(0.03, 0.03, 0.04), false, root)
	ticker_label = label("", Vector3(0, H - 0.7, -D / 2 + 0.24), 76, Color(0.2, 1, 0.3))
	ticker_label.name = "Ticker"
	# small ticker above elevator too
	box(Vector3(6, 0.3, 0.05), Vector3(0, H - 0.45, D / 2 - 0.2), Color(0.03, 0.03, 0.04), false, root)


func _holding_cell() -> void:
	var c := jail_pos
	var cell := Node3D.new()
	cell.name = "HoldingCell"
	root.add_child(cell)
	box(Vector3(6, 0.2, 6), c + Vector3(0, -0.2, 0), Color(0.35, 0.36, 0.38), true, cell)
	box(Vector3(6, 0.2, 6), c + Vector3(0, 3.0, 0), Color(0.3, 0.3, 0.32), true, cell)
	box(Vector3(6, 3, 0.2), c + Vector3(0, 1.4, -3), Color(0.45, 0.46, 0.5), true, cell)
	box(Vector3(0.2, 3, 6), c + Vector3(-3, 1.4, 0), Color(0.45, 0.46, 0.5), true, cell)
	box(Vector3(0.2, 3, 6), c + Vector3(3, 1.4, 0), Color(0.45, 0.46, 0.5), true, cell)
	box(Vector3(6, 3, 0.1), c + Vector3(0, 1.4, 3), Color(0, 0, 0, 0), true, cell).visible = false
	for k in 13:
		cyl(0.03, 3, c + Vector3(-2.8 + k * 0.46, 1.4, 2.95), C_METAL, false, cell)
	# lineup height lines on back wall
	for k in 8:
		box(Vector3(5.8, 0.02, 0.02), c + Vector3(0, 0.3 + k * 0.3, -2.88), Color(0.15, 0.15, 0.15), false, cell)
	label("NYPD HOLDING — sit tight", c + Vector3(0, 2.6, -2.85), 60, Color(1, 1, 1), 0.0, cell)
	var lt := OmniLight3D.new()
	lt.position = c + Vector3(0, 2.6, 0)
	lt.omni_range = 7
	cell.add_child(lt)
	# benches
	box(Vector3(4, 0.45, 0.6), c + Vector3(0, 0.22, -2.5), Color(0.3, 0.3, 0.32), true, cell)


func npc(pos: Vector3, rot_y: float, suit: Color, skin: Color, hair: Color, title: String) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rot_y
	nav.add_child(n)
	var body := box(Vector3(0.6, 1.1, 0.35), Vector3(0, 0.95, 0), suit, true, n)
	box(Vector3(0.62, 0.5, 0.37), Vector3(0, -0.8, 0), suit.darkened(0.2), false, body)
	sphere(0.24, Vector3(0, 1.72, 0), skin, n)
	box(Vector3(0.44, 0.12, 0.44), Vector3(0, 1.9, -0.02), hair, false, n)
	for ex in [-0.08, 0.08]:
		sphere(0.035, Vector3(ex, 1.76, 0.21), Color(0.05, 0.05, 0.05), n)
	box(Vector3(0.12, 0.35, 0.02), Vector3(0, 1.2, 0.18), Color(0.95, 0.95, 0.95), false, n)
	var tag := label(title, Vector3(0, 2.2, 0), 34, Color(1, 1, 1), 0.0, n)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var bubble := label("", Vector3(0, 2.65, 0), 40, Color(1, 0.95, 0.3), 0.0, n)
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.name = "Bubble"
	bubble.width = 900
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD
	bubble.outline_size = 14
	return n


## Streamer corner: TJZ at his stream desk, KIMCHEE and ROARING KITTEH.
func _streamer_corner() -> void:
	var base := Vector3(16.5, 0, 12.0)
	box(Vector3(2.2, 0.06, 0.9), base + Vector3(0, 0.75, 0), C_DARK)
	box(Vector3(0.06, 0.75, 0.85), base + Vector3(-1.05, 0.375, 0), C_METAL, false)
	box(Vector3(0.06, 0.75, 0.85), base + Vector3(1.05, 0.375, 0), C_METAL, false)
	# three monitors with charts
	for k in 3:
		var mon := box(Vector3(0.6, 0.38, 0.04), base + Vector3(-0.65 + k * 0.65, 1.1, -0.25), C_DARK, false)
		box(Vector3(0.56, 0.34, 0.01), Vector3(0, 0, 0.025), Color(0.05, 0.3, 0.15), false, mon, 0.8)
	# ring light + mic
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.26
	tm.outer_radius = 0.3
	ring.mesh = tm
	ring.material_override = mat(Color(1, 1, 1), 2.0)
	ring.position = base + Vector3(0, 1.55, -1.1)
	ring.rotation.x = PI / 2
	nav.add_child(ring)
	cyl(0.02, 1.5, base + Vector3(0, 0.75, -1.1), C_METAL)
	cyl(0.04, 0.12, base + Vector3(0.3, 0.9, 0.2), C_DARK)
	var live_sign := label("KWIK LIVE", base + Vector3(0, 2.5, 1.9), 90, Color(0.6, 0.3, 1), PI)
	live_sign.outline_size = 16
	var tj := npc(base + Vector3(0, 0, 0.85), PI, Color(0.1, 0.1, 0.12), Color(0.9, 0.72, 0.58), Color(0.1, 0.07, 0.05), "TJZ  (LIVE)")
	box(Vector3(0.5, 0.08, 0.1), Vector3(0, 1.93, 0), C_DARK, false, tj)  # headset band
	npcs["TJZ"] = tj
	var kc := npc(base + Vector3(-2.6, 0, -1.4), PI * 0.8, Color(0.95, 0.95, 0.95), Color(0.93, 0.78, 0.62), Color(0.05, 0.05, 0.05), "KIMCHEE")
	var chain := MeshInstance3D.new()
	var cm := TorusMesh.new()
	cm.inner_radius = 0.16
	cm.outer_radius = 0.19
	chain.mesh = cm
	chain.material_override = mat(Color(1, 0.8, 0.15), 0.5)
	chain.position = Vector3(0, 1.45, -0.12)
	chain.rotation.x = 1.2
	kc.add_child(chain)
	npcs["KIMCHEE"] = kc
	var rk := npc(base + Vector3(-4.4, 0, -0.6), PI * 1.15, Color(0.25, 0.3, 0.2), Color(0.95, 0.8, 0.66), Color(0.5, 0.3, 0.15), "ROARING KITTEH")
	box(Vector3(0.5, 0.06, 0.5), Vector3(0, 1.8, 0), Color(0.9, 0.1, 0.1), false, rk)  # headband
	for s in [-0.14, 0.14]:
		var ear := box(Vector3(0.1, 0.16, 0.05), Vector3(s, 2.02, 0), Color(0.5, 0.3, 0.15), false, rk)
		ear.rotation.z = 0.3 * sign(s)
	npcs["ROARING KITTEH"] = rk
	var jc := npc(Vector3(W / 2 - 1.5, 0, 1.6), -PI / 2, Color(0.95, 0.95, 0.95), Color(0.95, 0.8, 0.7), Color(0.85, 0.85, 0.85), "JIM CRAMMER")
	npcs["JIM CRAMMER"] = jc


func bake_nav() -> void:
	nav.bake_navigation_mesh(false)
