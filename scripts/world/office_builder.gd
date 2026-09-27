extends RefCounted
## Builds the whole office: red-carpet trading floor, CRT desks, elevator,
## lounge, casino corner, TV wall, ticker strip, whiteboard, hoop, holding cell.
## Furniture and fixtures come from the Blender props kit (PropKit); plain
## walls/floor/ceiling are boxes with small procedural textures. Collisions
## are invisible boxes (they also feed the nav mesh bake).
##
## Coordinates: floor spans x -20..20, z -14..14. North (z-) = windows.

const W := 40.0
const D := 28.0
const H := 3.4

# the newer clips' palette: blue-grey carpet, pale grey-blue walls, slate bands
const C_CARPET := Color(0.44, 0.49, 0.6)
const C_WALL := Color(0.74, 0.76, 0.8)
const C_TRIM := Color(0.27, 0.3, 0.38)
const C_WAINSCOT := Color(0.44, 0.48, 0.57)
const C_CEIL := Color(0.84, 0.85, 0.87)
const C_DESK := Color(0.92, 0.92, 0.9)
const C_BEIGE := Color(0.86, 0.8, 0.66)
const C_METAL := Color(0.6, 0.62, 0.66)
const C_DARK := Color(0.12, 0.12, 0.14)
const SKY_LAYER := 2
const Character = preload("res://scripts/art/character.gd")
const Props = preload("res://scripts/art/props.gd")
const PropKit = preload("res://scripts/art/prop_kit.gd")
const Batcher = preload("res://scripts/art/batcher.gd")

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
const RESTROOM_DOOR_Z := 2.2
var ball_spawn := Vector3(-16.5, 1.0, -9.5)
var rng := RandomNumberGenerator.new()


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
	rng.seed = 2024
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
	_restroom()
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
	_decor()
	for i in 6:
		spawn_points.append(Vector3(-3.0 + i * 1.2, 0.1, 10.5))
	# merge all static geometry by material (characters animate: skip them)
	var skip: Array = [tv_screen]
	for n in npcs.values():
		skip.append(n.get_node("Model"))
	for n in root.find_children("Model", "", true, false):
		skip.append(n)
	Batcher.merge_static(root, skip, 10.0)


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
		mi.add_child(_body(BoxShape3D.new(), size))
	p.add_child(mi)
	return mi


func _body(sh: Shape3D, size: Vector3) -> StaticBody3D:
	if sh is BoxShape3D:
		sh.size = size
	elif sh is CylinderShape3D:
		sh.radius = size.x
		sh.height = size.y
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = sh
	sb.add_child(cs)
	return sb


## Invisible collider (a Node3D with a StaticBody3D child) — the physical
## stand-in for a prop. Interact metadata and labels hang off it.
func solid(size: Vector3, pos: Vector3, parent: Node3D = null, rot_y := 0.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rot_y
	n.add_child(_body(BoxShape3D.new(), size))
	(parent if parent else (nav as Node3D)).add_child(n)
	return n


func solid_cyl(radius: float, height: float, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.add_child(_body(CylinderShape3D.new(), Vector3(radius, height, 0)))
	nav.add_child(n)
	return n


## A Blender prop (see tools/blender/build_props.py for origins; front = +Z).
func prop(name: String, pos: Vector3, rot_y := 0.0, parent: Node3D = null, scl := 1.0) -> Node3D:
	return PropKit.place(name, parent if parent else root, pos, rot_y, scl)


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


## Small tiling textures so big flat surfaces don't look like plastic.
func textured(c: Color, kind: String, tile: float) -> StandardMaterial3D:
	var key := "tex_%s_%s" % [kind, c.to_html()]
	if mats.has(key):
		return mats[key]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for y in n:
		for x in n:
			var v := c
			match kind:
				"carpet":
					v = c.darkened(r.randf() * 0.1 + (0.04 if (x + y) % 8 < 2 else 0.0))
				"ceiling":   # acoustic tile with a speckle, T-bar grid at the edges
					if x < 2 or y < 2:
						v = Color(0.93, 0.93, 0.94)
					elif x < 3 or y < 3:
						v = c.darkened(0.18)
					else:
						v = c.darkened(r.randf() * 0.07)
				"tile":      # square floor tiles with grout
					v = c.darkened(0.2) if x % 32 < 2 or y % 32 < 2 else c.darkened(r.randf() * 0.04)
				"block":     # cinder blocks: 2 rows per tile, staggered
					var row := y / 32
					var bx := (x + (16 if row % 2 else 0)) % 64
					v = c.darkened(0.25) if y % 32 < 2 or bx < 2 else c.darkened(r.randf() * 0.06)
			img.set_pixel(x, y, v)
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.95
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mats[key] = m
	return m


# ------------------------------------------------------------------ pieces

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.78, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 0.97, 0.92)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	# The sun only lights the skyline (render layer 2). Indoors it was always
	# fully shadowed by the ceiling anyway, so this skips a whole-office shadow
	# pass without changing the look.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 0.9
	sun.light_cull_mask = SKY_LAYER
	root.add_child(sun)
	for p in [Vector3(-10, 3.0, -5), Vector3(8, 3.0, -5), Vector3(-10, 3.0, 7), Vector3(10, 3.0, 7)]:
		var o := OmniLight3D.new()
		o.position = p
		o.omni_range = 14.0
		o.light_energy = 0.6
		o.light_color = Color(1, 0.96, 0.88)
		root.add_child(o)


func _shell() -> void:
	box(Vector3(W, 0.2, D), Vector3(0, -0.1, 0), C_CARPET).material_override = textured(C_CARPET, "carpet", 0.5)
	box(Vector3(W, 0.2, D), Vector3(0, H + 0.1, 0), C_CEIL, false, root).material_override = textured(C_CEIL, "ceiling", 0.6)
	# south wall with elevator gap
	box(Vector3(W / 2 - 1.3, H, 0.3), Vector3(-(W / 4 + 0.65), H / 2, D / 2), C_WALL)
	box(Vector3(W / 2 - 1.3, H, 0.3), Vector3(W / 4 + 0.65, H / 2, D / 2), C_WALL)
	box(Vector3(2.6, H - 2.4, 0.3), Vector3(0, 2.4 + (H - 2.4) / 2, D / 2), C_WALL)
	# west wall with the restroom door (opening z 1.7..2.7)
	var dz0 := RESTROOM_DOOR_Z - 0.5
	var dz1 := RESTROOM_DOOR_Z + 0.5
	box(Vector3(0.3, H, dz0 + D / 2), Vector3(-W / 2, H / 2, (dz0 - D / 2) / 2), C_WALL)
	box(Vector3(0.3, H, D / 2 - dz1), Vector3(-W / 2, H / 2, (dz1 + D / 2) / 2), C_WALL)
	box(Vector3(0.3, H - 2.25, 1.0), Vector3(-W / 2, 2.25 + (H - 2.25) / 2, RESTROOM_DOOR_Z), C_WALL)
	box(Vector3(0.3, H, D), Vector3(W / 2, H / 2, 0), C_WALL)                      # east
	# slate soffit band under the ceiling, darker wainscot + chair rail, baseboard
	for z in [D / 2 - 0.17, -D / 2 + 0.17]:
		box(Vector3(W, 0.3, 0.05), Vector3(0, H - 0.15, z), C_TRIM, false, root)
		if z > 0:
			_wainscot(Vector3(W, 0, 0.05), Vector3(0, 0, z))
	for x in [-W / 2 + 0.17, W / 2 - 0.17]:
		box(Vector3(0.05, 0.3, D), Vector3(x, H - 0.15, 0), C_TRIM, false, root)
	_wainscot(Vector3(0, 0, D), Vector3(W / 2 - 0.17, 0, 0))
	# west side: stop at the restroom door
	_wainscot(Vector3(0, 0, dz0 + D / 2), Vector3(-W / 2 + 0.17, 0, (dz0 - D / 2) / 2))
	_wainscot(Vector3(0, 0, D / 2 - dz1), Vector3(-W / 2 + 0.17, 0, (dz1 + D / 2) / 2))


## Lower wall band: darker panel to 0.95 m, a slate chair rail, a baseboard.
func _wainscot(span: Vector3, at: Vector3) -> void:
	var t := Vector3(0.05, 0, 0.05)
	var size := span + t
	box(Vector3(size.x, 0.95, size.z), at + Vector3(0, 0.475, 0), C_WAINSCOT, false, root)
	box(Vector3(size.x + 0.02, 0.05, size.z + 0.02), at + Vector3(0, 0.97, 0), C_TRIM, false, root)
	box(Vector3(size.x + 0.02, 0.1, size.z + 0.02), at + Vector3(0, 0.05, 0), C_TRIM, false, root)


## A small restroom behind the west-wall door (tile floor, toilet, sink + mirror).
func _restroom() -> void:
	var z := RESTROOM_DOOR_Z
	var x0 := -W / 2 - 3.0
	var tile := textured(Color(0.93, 0.94, 0.96), "tile", 0.4)
	box(Vector3(3.0, 0.2, 3.6), Vector3(x0 + 1.5, -0.1, z), Color.WHITE).material_override = tile
	box(Vector3(3.0, 0.2, 3.6), Vector3(x0 + 1.5, H + 0.1, z), C_CEIL, false, root)
	box(Vector3(0.2, H, 3.6), Vector3(x0 - 0.1, H / 2, z), Color(0.62, 0.78, 0.86))
	box(Vector3(3.2, H, 0.2), Vector3(x0 + 1.5, H / 2, z - 1.9), Color(0.62, 0.78, 0.86))
	box(Vector3(3.2, H, 0.2), Vector3(x0 + 1.5, H / 2, z + 1.9), Color(0.62, 0.78, 0.86))
	solid(Vector3(0.45, 0.8, 0.7), Vector3(x0 + 0.4, 0.4, z - 1.0))
	prop("Toilet", Vector3(x0 + 0.35, 0, z - 1.05), PI / 2)
	prop("Sink", Vector3(x0 + 1.6, 0, z + 1.6), PI)
	prop("CeilingLight", Vector3(x0 + 1.5, H, z))
	var lt := OmniLight3D.new()
	lt.position = Vector3(x0 + 1.5, H - 0.4, z)
	lt.omni_range = 4.5
	lt.light_energy = 0.8
	root.add_child(lt)
	# door: frame on the office side, leaf swung open into the restroom
	var door := prop("DoorFrame", Vector3(-W / 2, 0, z), PI / 2)
	var leaf := prop("DoorLeaf", Vector3(-0.49, 0, -0.06), 1.45, door)
	leaf.rotation.y = 1.45
	var sign := label("RESTROOM", Vector3(0.8, 1.6, 0.02), 30, Color(0.15, 0.2, 0.35), 0.0, door)
	sign.pixel_size = 0.004
	sign.outline_size = 0


func _windows_and_skyline() -> void:
	# North wall: low sill wall + header, glass, window bays with blinds.
	box(Vector3(W, 0.9, 0.3), Vector3(0, 0.45, -D / 2), C_WAINSCOT)
	box(Vector3(W, 0.4, 0.3), Vector3(0, H - 0.2, -D / 2), C_WALL)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.85, 1.0, 0.16)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	var g := box(Vector3(W, H - 1.3, 0.05), Vector3(0, 0.9 + (H - 1.3) / 2, -D / 2), Color.WHITE)
	g.material_override = glass
	var x := -W / 2 + 2.0
	while x < W / 2:
		prop("WindowBay", Vector3(x, 0, -D / 2 + 0.1))
		x += 4.0
	# skyline: towers from the kit, the Empire State–style spire front and center
	var skyline := Node3D.new()
	skyline.name = "Skyline"
	root.add_child(skyline)
	var r := RandomNumberGenerator.new()
	r.seed = 12
	var kinds := ["TowerA", "TowerB", "TowerC", "TowerD", "TowerA", "TowerC"]
	for i in 64:
		var bx := r.randf_range(-100, 100)
		var bz := r.randf_range(-48, -125)
		if absf(bx - 10) < 9 and bz > -80:
			continue   # keep the spire's view clear
		var pos := Vector3(bx, -20 - r.randf_range(0, 8), bz)
		PropKit.place(kinds[r.randi() % kinds.size()], skyline, pos, (r.randi() % 4) * PI / 2,
				r.randf_range(0.7, 1.35), _haze(pos))
	PropKit.place("EmpireState", skyline, Vector3(10, -20, -72), 0.0, 1.0, 0.25)
	PropKit.place("EmpireState", skyline, Vector3(-38, -24, -105), PI / 2, 0.8, 0.5)
	for mi in skyline.find_children("*", "MeshInstance3D", true, false):
		mi.layers = SKY_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## How much a tower at `pos` fades into the sky.
func _haze(pos: Vector3) -> float:
	return clampf((Vector2(pos.x, pos.z).length() - 30.0) / 90.0, 0.0, 0.85)


func _ceiling_lights() -> void:
	var x := -18.0
	while x <= 18.0:
		var z := -12.0
		while z <= 12.0:
			prop("CeilingLight", Vector3(x, H, z))
			z += 3.0
		x += 3.0


func _bullpen() -> void:
	var id := 0
	for row_z in [-9.5, -5.5, -1.5, 2.5]:
		var x := -13.0
		while x <= 7.0:
			_desk(Vector3(x, 0, row_z), id)
			id += 1
			x += 4.0


func _desk(p: Vector3, id: int) -> void:
	solid(Vector3(1.9, 0.06, 0.9), p + Vector3(0, 0.75, 0))
	prop("Desk", p)
	solid(Vector3(1.9, 1.3, 0.06), p + Vector3(0, 0.65, -0.48))
	prop("Divider", p + Vector3(0, 0, -0.48))
	# the terminal: collider node centered on the CRT, model sits on the desk
	var crt := solid(Vector3(0.58, 0.52, 0.55), p + Vector3(0, 1.04, -0.12))
	prop("CRT", Vector3(0, -0.26, 0), 0.0, crt)
	var scr := label("BTC", Vector3(0, 0.055, 0.3), 36, Color(0.3, 1, 0.5), 0.0, crt)
	scr.pixel_size = 0.0022
	scr.outline_size = 0
	scr.name = "ScreenText"
	prop("Keyboard", p + Vector3(0, 0.78, 0.2), rng.randf_range(-0.05, 0.05))
	prop("Mouse", p + Vector3(0.42, 0.78, 0.2), rng.randf_range(-0.2, 0.2))
	prop("Lamp", p + Vector3(-0.7, 0.78, -0.25), 0.45)
	prop("Chair", p + Vector3(rng.randf_range(-0.1, 0.1), 0, 0.85), PI + rng.randf_range(-0.35, 0.35))
	# desk clutter: every desk a little different
	prop(["Mug", "DeskPhone", "Mug", "Papers"][rng.randi() % 4], p + Vector3(0.6, 0.78, -0.22), rng.randf_range(-PI, PI))
	match rng.randi() % 4:
		0:
			prop("Cash", p + Vector3(0.62, 0.78, 0.2), rng.randf_range(-0.3, 0.3))
		1:
			prop("Ashtray", p + Vector3(0.75, 0.78, 0.22), rng.randf_range(-PI, PI))
		2:
			prop("Papers", p + Vector3(-0.5, 0.78, 0.18), rng.randf_range(-0.3, 0.3))
	if rng.randf() < 0.5:
		prop("Trash", p + Vector3(-0.55, 0, -0.1))
	add_interact(crt, "terminal", id, "[E] Trade")


func _elevator() -> void:
	var z := D / 2 - 0.15
	prop("Elevator", Vector3(0, 0, z), PI)
	solid(Vector3(1.1, 2.3, 0.08), Vector3(-0.56, 1.15, z - 0.03))
	solid(Vector3(1.1, 2.3, 0.08), Vector3(0.56, 1.15, z - 0.03))
	label("12", Vector3(0, 2.46, z - 0.22), 40, Color(0.2, 1, 0.3), PI).outline_size = 0


func _lounge() -> void:
	solid(Vector3(2.4, 0.45, 0.9), Vector3(-16, 0.225, 12.6))
	prop("Couch", Vector3(-16, 0, 12.7), PI)
	prop("Beanbag", Vector3(-12.5, 0, 12.2), 0.4)
	solid_cyl(0.6, 0.45, Vector3(-16, 0.225, 10.8))
	prop("CoffeeTable", Vector3(-16, 0, 10.8))
	prop("Plant", Vector3(-16.2, 0.45, 10.9), 0.0, null, 0.45)
	solid(Vector3(0.8, 0.8, 0.75), Vector3(-17.8, 0.4, 9.9), null, 1.08)
	prop("Armchair", Vector3(-17.8, 0, 9.9), 1.08)
	solid_cyl(0.23, 0.9, Vector3(-19.2, 0.45, 7))
	prop("Plant", Vector3(-19.2, 0, 7), 0.7)
	# vending machine
	var vm := solid(Vector3(1.0, 2.0, 0.8), Vector3(-19.4, 1.0, 9.5), null, PI / 2)
	prop("Vending", Vector3(0, -1.0, 0), 0.0, vm)
	var vl := label("MONSTAR", Vector3(0, 0.83, 0.42), 44, Color(0.55, 1, 0.3), 0.0, vm)
	vl.pixel_size = 0.004
	var ve := label("ENERGY", Vector3(-0.13, 0.35, 0.49), 48, Color(1, 1, 1), 0.0, vm)
	ve.pixel_size = 0.004
	ve.outline_modulate = Color(0.05, 0.2, 0.6)
	# Dealer NPC (the cigar guy from the trailer)
	var dealer := npc(Vector3(-15.0, 0, 8.6), PI * 0.9, "dealer", "TONY \"THE PLUG\"\n[E] Shop", "smoke")
	var cig = Props.cigar()
	cig.rotation = Vector3(-PI / 2, 0, 0)
	dealer.get_node("Model").prop_right.add_child(cig)
	add_interact(dealer.get_node("Hitbox"), "shop", 0, "[E] Talk to Tony")


func _casino() -> void:
	label("BAG SLOTS", Vector3(W / 2 - 0.2, 2.7, -8.5), 90, Color(1, 0.85, 0.1), -PI / 2)
	var i := 0
	for z in [-12.0, -10.0, -8.0, -6.0]:
		var sm := Node3D.new()
		sm.position = Vector3(W / 2 - 0.8, 0, z)
		sm.rotation.y = -PI / 2
		nav.add_child(sm)
		prop("SlotMachine", Vector3.ZERO, 0.0, sm)
		var body := solid(Vector3(1.1, 1.9, 0.9), Vector3(0, 0.95, 0), sm)
		var sign := label("DEGEN SLOTS", Vector3(0, 0.85, 0.2), 64, Color(1, 0.88, 0.15), 0.0, body)
		sign.pixel_size = 0.0027
		sign.outline_modulate = Color(0.5, 0.1, 0.0)
		sign.name = "Marquee"
		var bet := label("$300", Vector3(0, -0.09, 0.5), 40, Color(0.3, 1.0, 0.4), 0.0, body)
		bet.pixel_size = 0.0022
		bet.outline_size = 0
		bet.name = "Bet"
		body.add_child(_jackpot_fx())
		for k in 3:
			var l := label("7", Vector3(-0.29 + k * 0.29, 0.21, 0.45), 64, Color(0.85, 0.1, 0.1), 0.0, body)
			l.pixel_size = 0.0028
			l.outline_size = 0
			l.name = "Reel%d" % k
		add_interact(body, "slots", i, "[E] Play slots")
		slot_machines.append(body)
		i += 1


## One-shot burst of gold coins + confetti for a slot win (World triggers it).
func _jackpot_fx() -> Node3D:
	var fx := Node3D.new()
	fx.name = "Jackpot"
	fx.position = Vector3(0, 0.85, 0.35)
	var coins := CPUParticles3D.new()
	coins.name = "Coins"
	coins.emitting = false
	coins.one_shot = true
	coins.explosiveness = 0.85
	coins.amount = 36
	coins.lifetime = 1.8
	coins.mesh = PropKit.mesh("Coin")
	coins.material_override = PropKit.material("Metal")
	coins.direction = Vector3(0, 1, 0.7)
	coins.spread = 55.0
	coins.initial_velocity_min = 2.2
	coins.initial_velocity_max = 4.2
	coins.gravity = Vector3(0, -7.0, 0)
	coins.angular_velocity_min = -540.0
	coins.angular_velocity_max = 540.0
	coins.scale_amount_min = 1.0
	coins.scale_amount_max = 1.6
	fx.add_child(coins)
	var confetti := CPUParticles3D.new()
	confetti.name = "Confetti"
	confetti.emitting = false
	confetti.one_shot = true
	confetti.explosiveness = 0.9
	confetti.amount = 60
	confetti.lifetime = 2.2
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.018)
	confetti.mesh = q
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	confetti.material_override = cm
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	g.colors = PackedColorArray([Color(1, 0.2, 0.4), Color(0.2, 0.8, 1), Color(1, 0.85, 0.1), Color(0.4, 1, 0.4), Color(0.8, 0.3, 1)])
	confetti.color_initial_ramp = g
	confetti.direction = Vector3(0, 1, 0.5)
	confetti.spread = 70.0
	confetti.initial_velocity_min = 1.5
	confetti.initial_velocity_max = 3.5
	confetti.gravity = Vector3(0, -2.5, 0)
	confetti.damping_min = 1.0
	confetti.damping_max = 2.0
	confetti.angular_velocity_min = -720.0
	confetti.angular_velocity_max = 720.0
	fx.add_child(confetti)
	return fx


func _tv_wall() -> void:
	var tv := Node3D.new()
	tv.position = Vector3(W / 2 - 0.2, 1.9, 5.5)
	tv.rotation.y = -PI / 2
	root.add_child(tv)
	prop("TV", Vector3.ZERO, 0.0, tv)
	tv_screen = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(4.2, 2.3)
	tv_screen.mesh = q
	tv_screen.position = Vector3(0, 0, 0.07)
	tv.add_child(tv_screen)


func _west_wall() -> void:
	# Whiteboard — MONEY TALKS
	var wb := Node3D.new()
	wb.position = Vector3(-W / 2 + 0.16, 1.6, -1.5)
	wb.rotation.y = PI / 2
	root.add_child(wb)
	prop("Whiteboard", Vector3.ZERO, 0.0, wb)
	var mt := label("MONEY\nTALKS", Vector3(0, 0.05, 0.04), 150, Color(0.1, 0.1, 0.12), 0.0, wb)
	mt.outline_size = 0
	# Basketball hoop + framed certificates
	var hp := Node3D.new()
	hp.position = Vector3(-W / 2 + 0.2, 2.5, -9.5)
	hp.rotation.y = PI / 2
	root.add_child(hp)
	prop("Hoop", Vector3.ZERO, 0.0, hp)
	for k in 4:
		prop("Certificate", Vector3(-1.4 - (k % 2) * 0.5, 0.1 - (k / 2) * 0.4, -0.02), 0.0, hp)
	# arcade cabinet
	solid(Vector3(0.9, 1.9, 0.8), Vector3(-W / 2 + 0.7, 0.95, -5.5))
	prop("Arcade", Vector3(-W / 2 + 0.62, 0, -5.5), PI / 2)


func _bell_podium() -> void:
	solid(Vector3(0.9, 1.1, 0.6), Vector3(7, 0.55, 8.0))
	prop("BellPodium", Vector3(7, 0, 8.0))
	var l := label("OPENING BELL\nhost: press ENTER", Vector3(7, 1.9, 8.0), 40, Color(1, 0.9, 0.5))
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.name = "BellLabel"


func _ticker() -> void:
	box(Vector3(W - 1, 0.5, 0.05), Vector3(0, H - 0.75, -D / 2 + 0.3), Color(0.03, 0.03, 0.04), false, root)
	box(Vector3(W - 0.9, 0.04, 0.08), Vector3(0, H - 0.49, -D / 2 + 0.3), C_METAL, false, root)
	box(Vector3(W - 0.9, 0.04, 0.08), Vector3(0, H - 1.01, -D / 2 + 0.3), C_METAL, false, root)
	ticker_label = label("", Vector3(0, H - 0.75, -D / 2 + 0.34), 76, Color(0.2, 1, 0.3))
	ticker_label.name = "Ticker"
	# small ticker above elevator too
	box(Vector3(6, 0.3, 0.05), Vector3(0, H - 0.55, D / 2 - 0.22), Color(0.03, 0.03, 0.04), false, root)


func _holding_cell() -> void:
	var c := jail_pos
	var cell := Node3D.new()
	cell.name = "HoldingCell"
	root.add_child(cell)
	var block := textured(Color(0.62, 0.63, 0.66), "block", 0.8)
	box(Vector3(6, 0.2, 6), c + Vector3(0, -0.2, 0), Color(0.35, 0.36, 0.38), true, cell)
	box(Vector3(6, 0.2, 6), c + Vector3(0, 3.0, 0), Color(0.3, 0.3, 0.32), true, cell)
	box(Vector3(6, 3, 0.2), c + Vector3(0, 1.4, -3), Color.WHITE, true, cell).material_override = block
	box(Vector3(0.2, 3, 6), c + Vector3(-3, 1.4, 0), Color.WHITE, true, cell).material_override = block
	box(Vector3(0.2, 3, 6), c + Vector3(3, 1.4, 0), Color.WHITE, true, cell).material_override = block
	box(Vector3(6, 3, 0.1), c + Vector3(0, 1.4, 3), Color(0, 0, 0, 0), true, cell).visible = false
	prop("CellBars", c + Vector3(0, -0.1, 2.95), 0.0, cell)
	# precinct hallway outside the bars (so you don't stare into the void)
	box(Vector3(10, 0.2, 3), c + Vector3(0, -0.2, 4.5), Color(0.35, 0.36, 0.38), false, cell)
	box(Vector3(10, 0.2, 3), c + Vector3(0, 3.0, 4.5), Color(0.3, 0.3, 0.32), false, cell)
	box(Vector3(10, 3.2, 0.2), c + Vector3(0, 1.4, 6.0), Color.WHITE, false, cell).material_override = block
	box(Vector3(10, 0.9, 0.05), c + Vector3(0, 0.45, 5.88), Color(0.2, 0.3, 0.55), false, cell)
	label("PRECINCT 12  ·  NO TRADING", c + Vector3(0, 2.2, 5.87), 50, Color(0.9, 0.9, 0.95), PI, cell)
	# lineup height lines on back wall
	for k in 8:
		box(Vector3(5.8, 0.02, 0.02), c + Vector3(0, 0.3 + k * 0.3, -2.88), Color(0.15, 0.15, 0.15), false, cell)
	label("NYPD HOLDING — sit tight", c + Vector3(0, 2.6, -2.85), 60, Color(1, 1, 1), 0.0, cell)
	var lt := OmniLight3D.new()
	lt.position = c + Vector3(0, 2.6, 0)
	lt.omni_range = 7
	cell.add_child(lt)
	solid(Vector3(4, 0.5, 0.6), c + Vector3(0, 0.15, -2.55), cell)
	prop("CellBench", c + Vector3(0, -0.1, -2.55), 0.0, cell)
	prop("CellToilet", c + Vector3(2.3, -0.1, -2.5), 0.0, cell)


func _decor() -> void:
	# things the trailer's office is full of: filing cabinets, a water cooler,
	# wall clocks, plants and a couple of trash cans
	for z in [-9.7, -5.7]:
		solid(Vector3(0.62, 1.32, 0.46), Vector3(9.7, 0.66, z))
		prop("FilingCabinet", Vector3(9.7, 0, z), -PI / 2)
	solid(Vector3(0.36, 1.4, 0.36), Vector3(-19.5, 0.7, 4.6))
	prop("WaterCooler", Vector3(-19.5, 0, 4.6), PI / 2)
	prop("Clock", Vector3(-6, 2.6, D / 2 - 0.15), PI)
	prop("BulletinBoard", Vector3(-9.5, 1.65, D / 2 - 0.15), PI)
	# the office is a mess: loose bills, paper balls and cigar butts on the carpet
	var mess := ["Bill", "Bill", "Bill", "PaperBall", "CigarButt"]
	for i in 34:
		var p := Vector3(rng.randf_range(-17, 17), 0.0, rng.randf_range(-12, 11))
		prop(mess[rng.randi() % mess.size()], p, rng.randf_range(-PI, PI))
	prop("Clock", Vector3(W / 2 - 0.15, 2.6, -2.0), -PI / 2)
	for p in [Vector3(12.8, 0, -13.2), Vector3(-19.2, 0, 13.0), Vector3(19.2, 0, -3.8)]:
		solid_cyl(0.23, 0.9, p + Vector3(0, 0.45, 0))
		prop("Plant", p, rng.randf_range(-PI, PI))


## A character NPC. The node's front is +Z (the model inside is turned to face it).
func npc(pos: Vector3, rot_y: float, preset: String, title: String, pose: String = "idle") -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rot_y
	nav.add_child(n)
	var hit := box(Vector3(0.6, 1.8, 0.45), Vector3(0, 0.9, 0), Color(0, 0, 0), true, n)
	hit.visible = false
	hit.name = "Hitbox"
	var model = Character.new()
	model.name = "Model"
	model.build(Character.preset(preset))
	model.rotation.y = PI
	model.pose = pose
	n.add_child(model)
	var tag := label(title, Vector3(0, 2.15, 0), 34, Color(1, 1, 1), 0.0, n)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var bubble := label("", Vector3(0, 2.6, 0), 40, Color(1, 0.95, 0.3), 0.0, n)
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.name = "Bubble"
	bubble.width = 900
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD
	bubble.outline_size = 14
	return n


## Streamer corner: TJZ at his stream desk, KIMCHEE and ROARING KITTEH.
func _streamer_corner() -> void:
	var base := Vector3(16.5, 0, 12.0)
	solid(Vector3(2.2, 0.06, 0.9), base + Vector3(0, 0.75, 0))
	prop("StreamDesk", base)
	prop("RingLight", base + Vector3(0, 0, -1.1))
	prop("NeonBoard", base + Vector3(0, 2.5, 1.83), PI)
	var live_sign := label("KWIK LIVE", base + Vector3(0, 2.5, 1.78), 90, Color(0.75, 0.5, 1), PI)
	live_sign.outline_size = 16
	live_sign.outline_modulate = Color(0.3, 0.05, 0.6)
	prop("GamingChair", base + Vector3(0, 0, 0.95), PI)
	var tj := npc(base + Vector3(0, 0, 0.9), PI, "tjz", "TJZ  (LIVE)", "type")
	npcs["TJZ"] = tj
	var kc := npc(base + Vector3(-2.6, 0, -1.4), PI * 0.8, "kimchee", "KIMCHEE", "hold")
	kc.get_node("Model").prop_right.add_child(Props.phone())
	npcs["KIMCHEE"] = kc
	var rk := npc(base + Vector3(-4.4, 0, -0.6), PI * 1.15, "kitteh", "ROARING KITTEH")
	npcs["ROARING KITTEH"] = rk
	var jc := npc(Vector3(W / 2 - 1.5, 0, 1.6), -PI / 2, "crammer", "JIM CRAMMER", "cheer")
	npcs["JIM CRAMMER"] = jc


func bake_nav() -> void:
	nav.bake_navigation_mesh(false)
