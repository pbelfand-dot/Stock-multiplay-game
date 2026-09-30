extends RefCounted
## A car dealership on its lot off the highway: a glass showroom with the
## flagship spinning on the turntable, two more cars inside, a row out front,
## the pylon, lot lights and flags. [E] at the sales desk opens that brand's
## showroom menu. One per brand (Brands, and the lots in Highway.dealers):
##   BEMZE          off the downtown leg (exit at station 1980, or up Levee Rd from
##                  Magnolia Heights): its glass front faces the lot entrance (-x)
##   MERCEDEZ BANZ, PORSHA, AUDY   round the loop, off the return leg: the glass faces
##                  the highway (+z), the row out front beside the exit, the way back
##                  on across the lot to the west
## Kit pieces: tools/blender/build_bemze.py (Dealer_* + the cars). BEMZE uses
## them as they come; the others get copies with the roundels and the BEMZE
## lettering taken off and the colours swapped for their own (Brands look,
## see VARIANT / RECOLOR), their own lettering, and an emblem each (parodies:
## a three-pointed star in a ring, a crest, four rings).
## Draws: the building and props are merged per material (Batcher); the
## display cars only draw within DRAW, the loop showrooms within FAR. Load
## time: a loop lot's display cars aren't built with the world but one a frame
## once a camera first comes within WAKE.

const PropKit = preload("res://scripts/art/prop_kit.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const Brands = preload("res://scripts/sim/brands.gd")
const CarScript = preload("res://scripts/vehicle/car.gd")
const RoadMesh = preload("res://scripts/world/road_mesh.gd")
const Batcher = preload("res://scripts/art/batcher.gd")

const SHOWROOM := Vector2(30.0, 18.0)
const DRAW := 260.0                   # the display cars only draw this close (they're detailed)
const FAR := 1500.0                   # a loop showroom's building, lettering at most this far
const WAKE := 700.0                   # a loop lot's display cars get built when a camera first comes this close
## A brand's copy of a kit piece: which surfaces to leave out ("Kind:vertex colour"),
## except below `min_y` (the showroom's door handles are the same chrome as its roundels).
const VARIANT := {
	"Dealer_Showroom": [2.0, ["Gloss:070708", "Gloss:ff720c", "Gloss:f7f7f2", "Metal:ccd1d8", "Metal:e5e5e5", "Glow:f7f7ff",
		"Glow:f2f2f7"]],
	"Dealer_Turntable": [-9.0, ["Gloss:070708", "Gloss:ff720c", "Gloss:f7f7f2", "Metal:ccd1d8", "Metal:e5e5e5"]],
	"Dealer_Desk": [-9.0, ["Gloss:070708", "Gloss:ff720c", "Gloss:f7f7f2", "Metal:ccd1d8", "Metal:e5e5e5"]],
	"Dealer_Pylon": [-9.0, ["Gloss:070708", "Gloss:ff720c", "Gloss:f7f7f2", "Gloss:282b30", "Metal:ccd1d8", "Metal:e5e5e5",
		"Glow:f2f2f7", "Paint:0f0f14"]],
	"Dealer_Flag": [-9.0, ["Paint:111116"]],
	"Dealer_KeyBox": [-9.0, ["Metal:e5e5ea"]],
}
## ...and its colours: kit vertex colour ("Kind:" first, then any kind) -> Brands look key.
const RECOLOR := {"e5e8ea": "wall", "Glow:e5e8ea": "face", "33353a": "trim", "191a1d": "band", "141419": "band",
	"c6c9cc": "floor", "a8aaaf": "floor_d", "ff720c": "accent", "ff8c26": "accent", "e57f26": "accent", "d8dbe5": "accent"}

static var _variants := {}            # "brand|prop" -> [[ArrayMesh, Material], ...]

var world
var b                                 # office builder (solid, add_interact, npc)
var brand := "bemze"
var root: Node3D
var turntable: Node3D
var spinner: Node3D                   # Mercedez Banz: the star on the roof
var center := Vector3.ZERO
var rot := -PI / 2                    # BEMZE: the showroom's glass front faces the lot entrance (-x)
var _font: Font
var _lot := Vector3.ZERO
var _pending: Array = []              # display cars still to build: [key, parent, pos, yaw, paint]


func _init(w, br := "bemze") -> void:
	world = w
	b = w.builder
	brand = br


func build(lot: Vector3) -> Node3D:
	root = Node3D.new()
	root.name = "Dealership" if brand == "bemze" else "Dealership_" + brand
	world.add_child(root)
	var loop := brand != "bemze"
	var kit := PropKit.has("Dealer_Showroom")
	var st := Node3D.new()                # the building + props: merged per material at the end
	st.name = "Static"
	root.add_child(st)
	if loop:
		# on the lot's north half, the glass front to the highway; the east end clear of the exit
		center = lot + Vector3(8.0, 0.0, -10.0)
		rot = 0.0
	else:
		# the showroom on the east side of the lot, its glass front to the entrances
		center = lot + Vector3(15.0, 0.0, 0.0)
	var basis := Basis(Vector3.UP, rot)
	var at := func(local: Vector3) -> Vector3:
		return center + basis * local
	if kit:
		_place("Dealer_Showroom", st, center, rot)
	else:
		b.box(Vector3(SHOWROOM.x, 0.1, SHOWROOM.y), center + Vector3(0, 0.05, 0), Color(0.85, 0.86, 0.88), false, st)
	# walls: back, left, right (a door for delivering cars), the glass front (the entrance), the roof
	for w in [[Vector3(0, 3.5, -8.85), Vector3(30, 7, 0.3)], [Vector3(-14.85, 3.5, 0), Vector3(0.3, 7, 18)],
			[Vector3(14.85, 3.5, -7.0), Vector3(0.3, 7, 4.0)], [Vector3(14.85, 3.5, 3.0), Vector3(0.3, 7, 12.0)],
			[Vector3(14.85, 5.4, -2.5), Vector3(0.3, 3.2, 5.0)],
			[Vector3(-8.5, 2.5, 8.94), Vector3(13.0, 5.0, 0.2)], [Vector3(8.5, 2.5, 8.94), Vector3(13.0, 5.0, 0.2)],
			[Vector3(0, 4.0, 8.94), Vector3(4.0, 2.0, 0.2)], [Vector3(0, 7.22, 1.0), Vector3(30.6, 0.45, 20.6)]]:
		b.solid(w[1], at.call(w[0]), root, rot)
		if not kit:
			b.box(w[1], at.call(w[0]), Color(0.3, 0.32, 0.36) if w[0].z < 8.0 else Color(0.6, 0.75, 0.85), false, st).rotation.y = rot
	if loop:
		_sign_band(st, at)
	else:
		var sign := Label3D.new()
		sign.visible = not kit                 # the kit's sign band has the lettering
		sign.text = "BEMZE"
		sign.font_size = 200
		sign.pixel_size = 0.012
		sign.outline_size = 0
		sign.modulate = Color(1, 1, 1)
		sign.position = at.call(Vector3(0, 6.0, 9.3))
		sign.rotation.y = rot
		root.add_child(sign)
	# the flagship spins on the turntable; two more on the floor
	var tt: Vector3 = at.call(Vector3(0, 0, -1.5))
	if PropKit.has("Dealer_Turntable"):
		_place("Dealer_Turntable", st, tt, rot)
	turntable = Node3D.new()
	turntable.position = tt + Vector3(0, 0.222, 0)
	turntable.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF    # spun in _process (tick)
	root.add_child(turntable)
	b.solid(Vector3(5.0, 1.2, 5.0), tt + Vector3(0, 0.6, 0), root)
	# the display: the brand's lineup, flagship first (a small range comes round
	# again in other factory colours); none yet = an empty floor. BEMZE's are
	# built now; the loop lots' when someone first comes near (see tick)
	var cars := Brands.lineup(brand)
	var spots: Array = [[turntable, Vector3.ZERO, 0.6, false], [root, at.call(Vector3(-9.0, 0, -3.0)), rot + 0.5, true],
		[root, at.call(Vector3(9.0, 0, 4.0)), rot - 2.3, true]]
	for k in 4:          # the row out front, facing the road
		if loop:
			spots.append([root, lot + Vector3(10.5 + k * 5.5, 0, 9.0), PI + 0.6, true])
		else:
			spots.append([root, lot + Vector3(-18.0, 0, -15.0 + k * 10.0), PI / 2 + 0.35, true])
	var shown := spots.size() if not cars.is_empty() else 0
	for i in shown:
		var sp: Array = spots[i]
		var col = null if i < cars.size() else Rules.PAINTS[(i * 3 + 2) % Rules.PAINTS.size()][1]
		if sp[3]:             # a solid box so you can't drive through it
			b.solid(Vector3(1.95, 1.4, 4.9), sp[1] + Vector3(0, 0.7, 0), root, sp[2])
		if loop:
			_pending.append([cars[i % cars.size()], sp[0], sp[1], sp[2], col])
		else:
			_display(cars[i % cars.size()], sp[0], sp[1], sp[2], col)
	_lot = lot
	# the sales desk: [E] for the showroom menu
	var desk: Vector3 = at.call(Vector3(-8.0, 0, 5.0))
	if PropKit.has("Dealer_Desk"):
		_place("Dealer_Desk", st, desk, rot)
	var body: Node3D = b.solid(Vector3(2.2, 1.0, 0.9), desk + Vector3(0, 0.5, 0), root, rot)
	b.add_interact(body, "dealer", Brands.index(brand), "[E] Talk to sales: buy a %s, pick your ride, respray" % Brands.name_of(brand))
	b.npc(at.call(Vector3(-8.0, 0, 4.0)), rot, "anchor", "", "idle")
	if PropKit.has("Dealer_KeyBox"):
		_place("Dealer_KeyBox", st, at.call(Vector3(-10.0, 1.4, -8.68)), rot)
	# pylon at the entrance, lights on the corners, flags along the road
	var py: Vector3 = lot + (Vector3(23.0, 0, 16.0) if loop else Vector3(-26.0, 0, -17.0))
	var py_rot := 0.45 if loop else 0.4
	if PropKit.has("Dealer_Pylon"):
		_place("Dealer_Pylon", st, py, py_rot)
		if loop:
			_pylon_faces(st, py, py_rot)
		else:
			var pl := Label3D.new()
			pl.visible = false                 # the kit pylon carries the roundel + lettering
			pl.text = "BEMZE"
			pl.font_size = 64
			pl.pixel_size = 0.012
			pl.outline_size = 0
			pl.position = lot + Vector3(-26.0, 6.9, -17.0) + Basis(Vector3.UP, 0.4) * Vector3(0, 0, 0.31)
			pl.rotation.y = 0.4
			root.add_child(pl)
	for c in [Vector2(-28, -18), Vector2(28, -18), Vector2(-28, 18), Vector2(28, 18)]:
		if PropKit.has("Dealer_LotLight"):
			PropKit.place("Dealer_LotLight", st, lot + Vector3(c.x, 0, c.y), 0.0)
		b.solid(Vector3(0.3, 8.0, 0.3), lot + Vector3(c.x, 4.0, c.y), root)
	var flags := 4 if loop else 6
	for k in flags:
		if PropKit.has("Dealer_Flag"):
			var fp: Vector3 = lot + (Vector3(5.5 + k * 4.5, 0, 18.8) if loop else Vector3(-24.0 + k * 7.0, 0, -19.0))
			_place("Dealer_Flag", st, fp, randf_range(-0.4, 0.4))
	if loop:
		_statement(st, lot + Vector3(-13.0, 0, 15.0), at)
	var lt := OmniLight3D.new()
	lt.position = at.call(Vector3(0, 6.0, 0))
	lt.omni_range = 20.0
	lt.light_energy = 1.2
	root.add_child(lt)
	Batcher.merge_static(st)
	if loop:
		for mi in st.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visibility_range_end = FAR
	return root


## A kit piece: BEMZE's as it comes, the other brands' copy (see _variant).
func _place(prop: String, parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	if brand == "bemze":
		return PropKit.place(prop, parent, pos, yaw)
	var n := Node3D.new()
	n.name = prop
	n.position = pos
	n.rotation.y = yaw
	for part in _variant(prop, brand):
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.material_override = part[1]
		n.add_child(mi)
	parent.add_child(n)
	return n


## A brand's copy of a kit piece: the VARIANT surfaces left out, the RECOLOR
## colours swapped for the brand's look. Made once per brand and piece.
static func _variant(prop: String, br: String) -> Array:
	var key := br + "|" + prop
	if _variants.has(key):
		return _variants[key]
	var look: Dictionary = Brands.BRANDS[br].look.duplicate()
	look["floor_d"] = (look.get("floor", Color.GRAY) as Color).darkened(0.12)
	var spec: Array = VARIANT.get(prop, [0.0, []])
	var out: Array = []
	for part in PropKit.parts(prop):
		var mat: Material = part[1]
		var kind := ""
		for k in ["Paint", "Gloss", "Metal", "Glow", "Glass"]:
			if mat == PropKit.material(k):
				kind = k
		# the same vertex arrays (so it batches like the original), new colours, fewer triangles
		var arr: Array = (part[0] as ArrayMesh).surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var col: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		if col.size() != v.size():
			out.append(part)
			continue
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
		var keep := PackedInt32Array()
		for t in range(0, idx.size() - 2, 3):
			var hx := col[idx[t]].to_html(false)
			var low := minf(v[idx[t]].y, minf(v[idx[t + 1]].y, v[idx[t + 2]].y))
			if (kind + ":" + hx) in spec[1] and low >= float(spec[0]):
				continue
			keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
		if keep.is_empty():
			continue
		for i in col.size():
			var h := col[i].to_html(false)
			var lk: String = RECOLOR.get(kind + ":" + h, RECOLOR.get(h, ""))
			if look.has(lk):
				col[i] = look[lk]
		arr[Mesh.ARRAY_COLOR] = col
		arr[Mesh.ARRAY_INDEX] = keep
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.append([am, mat])
	_variants[key] = out
	return out


## A car on display: the real model (no physics), and it only draws when
## you're near. col: its paint (null = factory).
func _display(key: String, parent: Node3D, pos: Vector3, yaw: float, col = null) -> void:
	var c = CarScript.new()
	c.preview = true
	c.setup(key, 0, col)
	c.position = pos
	c.rotation.y = yaw
	parent.add_child(c)
	for mi in c.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = DRAW


func tick(delta: float) -> void:
	if turntable:
		turntable.rotation.y += delta * 0.3
	if spinner:
		spinner.rotation.y += delta * 0.5
	# a loop lot's display cars: one a frame, once a camera's within WAKE (none built at load)
	if not _pending.is_empty():
		var cam: Camera3D = world.get_viewport().get_camera_3d()
		var eye: Vector3 = cam.global_position if cam else (world.local_player.global_position if world.local_player else _lot)
		if eye.distance_to(_lot) < WAKE:
			var d: Array = _pending.pop_front()
			_display(d[0], d[1], d[2], d[3], d[4])


# ------------------------------------------------------------------ the loop brands' identity

func _look(k: String) -> Color:
	return Brands.BRANDS[brand].look[k]


## The brand's lettering: Mercedez wide and plain, Porsha wide-spaced
## condensed, Audy tight and bold.
func _brand_font() -> Font:
	if _font == null:
		var fv := FontVariation.new()
		match brand:
			"mercedez":
				fv.base_font = ThemeDB.fallback_font
				fv.spacing_glyph = 10
			"porsha":
				fv.base_font = load("res://assets/fonts/Oswald-Medium.woff2")
				fv.spacing_glyph = 22
			_:
				fv.base_font = load("res://assets/fonts/Oswald-Bold.woff2")
				fv.spacing_glyph = 4
		_font = fv
	return _font


## Lettering centred at pos: capitals `cap` m tall, no wider than max_w.
func _text(txt: String, pos: Vector3, cap: float, max_w: float, col: Color, yaw: float, parent: Node3D,
		range_end := 600.0) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	l.font = _brand_font()
	l.font_size = 96
	l.pixel_size = cap / (96 * 0.72)
	var w := l.font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 96).x
	if w * l.pixel_size > max_w:
		l.pixel_size = max_w / w
	l.modulate = col
	l.outline_size = 0
	l.double_sided = false
	l.position = pos
	l.rotation.y = yaw
	l.visibility_range_end = range_end
	parent.add_child(l)
	return l


## The name on the sign band over the glass (lit), the emblem to its left; the
## same, smaller, on the brand wall inside; a thin accent line along the
## canopy's edge.
func _sign_band(st: Node3D, at: Callable) -> void:
	var m := RoadMesh.new()
	var bx: Basis = Basis(Vector3.UP, rot)
	var es: float = {"mercedez": 0.8, "porsha": 1.3, "audy": 0.85}[brand]         # the emblem's half-height
	var ew: float = es * {"mercedez": 1.92, "porsha": 0.8, "audy": 3.35}[brand]    # ...and its width
	for spot in [[Vector3(0, 6.0, 9.3), 1.05 if brand == "mercedez" else 1.3, 19.0, 1.0],
			[Vector3(0, 3.4, -8.6), 0.5, 5.0, 0.35]]:        # [centre, capitals, widest, emblem scale]
		var k: float = spot[3]
		var l := _text(Brands.name_of(brand), Vector3.ZERO, spot[1], spot[2] - ew * k, _look("ink"), rot, root,
				FAR if k >= 1.0 else 60.0)
		var tw: float = l.font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 96).x * l.pixel_size
		var x0: float = spot[0].x - (ew * k + 1.0 * k + tw) / 2.0
		l.position = at.call(Vector3(x0 + (ew + 1.0) * k + tw / 2.0, spot[0].y, spot[0].z))
		_emblem(m, at.call(Vector3(x0 + ew * k / 2.0, spot[0].y + 0.02, spot[0].z - 0.02)), bx.x, Vector3.UP, bx.z, es * k, true)
	m.box(at.call(Vector3(0, 7.0, 11.33)), Vector3(30.66, 0.07, 0.06), _look("accent"))    # (loop showrooms: rot 0)
	m.instance(st, PropKit.material("Glow"), "BrandSign").set_meta("no_batch", true)      # (see _statement)


## The pylon's lit faces (both sides): the emblem, the name, what's inside.
func _pylon_faces(st: Node3D, py: Vector3, yaw: float) -> void:
	var m := RoadMesh.new()
	var bx := Basis(Vector3.UP, yaw)
	for side in [1.0, -1.0]:
		var f: Vector3 = bx.z * side
		var r: Vector3 = bx.x * side
		var yy := yaw if side > 0 else yaw + PI
		_emblem(m, py + Vector3(0, 7.55, 0) + f * 0.31, r, Vector3.UP, f, 0.55, true)
		var nm := Brands.name_of(brand).replace(" ", "\n")
		_text(nm, py + Vector3(0, 6.2 if nm.contains("\n") else 6.1, 0) + f * 0.31, 0.3, 1.3, _look("ink"), yy, root, 400.0)
		for k in 3:
			_text(["NEW", "CERTIFIED", "SERVICE"][k], py + Vector3(0, 4.6 - k * 0.5, 0) + f * 0.3, 0.2, 1.2,
					Color(0.93, 0.93, 0.95), yy, root, 250.0)
	m.instance(st, PropKit.material("Glow"), "PylonFaces").set_meta("no_batch", true)


## Between the two ramps, facing the highway: Mercedez Banz a star in a ring
## on a slim pole (and another turning on the roof), Porsha its crest on a
## black totem, Audy the four rings on a plinth.
func _statement(st: Node3D, base: Vector3, at: Callable) -> void:
	var m := RoadMesh.new()
	var f := Vector3(0, 0, 1)
	var r := Vector3(1, 0, 0)
	var steel := Color(0.72, 0.74, 0.78)
	match brand:
		"mercedez":
			m.box(base + Vector3(0, 0.2, 0), Vector3(2.4, 0.4, 2.4), _look("band"), true)
			m.box(base + Vector3(0, 2.4, 0), Vector3(0.22, 4.0, 0.22), steel)
			_emblem(m, base + Vector3(0, 6.3, 0), r, Vector3.UP, f, 2.0, false)
			b.solid(Vector3(2.4, 6.0, 2.4), base + Vector3(0, 3.0, 0), root)
			# the star on the roof, on a mast, turning
			var roof: Vector3 = at.call(Vector3(-9.0, 7.56, -3.0))
			m.box(roof + Vector3(0, 0.9, 0), Vector3(0.3, 1.8, 0.3), steel)
			spinner = Node3D.new()
			spinner.position = roof + Vector3(0, 4.1, 0)
			spinner.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			root.add_child(spinner)
			var sm := RoadMesh.new()
			_emblem(sm, Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK, 2.2, false)
			sm.instance(spinner, PropKit.material("Metal"), "RoofStar", FAR)
		"porsha":
			m.box(base + Vector3(0, 3.3, 0), Vector3(3.0, 6.6, 0.6), _look("band"), true)
			m.box(base + Vector3(0, 6.62, 0), Vector3(3.1, 0.06, 0.66), _look("accent"))
			for side in [1.0, -1.0]:
				_emblem(m, base + Vector3(0, 4.55, 0) + f * 0.31 * side, r * side, Vector3.UP, f * side, 2.3, false)
				_text("PORSHA", base + Vector3(0, 1.9, 0) + f * 0.31 * side, 0.34, 2.4, _look("ink"), 0.0 if side > 0 else PI, root, 300.0)
			b.solid(Vector3(3.0, 6.6, 0.6), base + Vector3(0, 3.3, 0), root)
		"audy":
			m.box(base + Vector3(0, 0.25, 0), Vector3(8.4, 0.5, 1.4), Color(0.72, 0.72, 0.7), true)
			m.box(base + Vector3(0, 0.52, 0.71), Vector3(8.4, 0.06, 0.02), _look("accent"))
			for x in [-2.6, 2.6]:
				m.box(base + Vector3(x, 1.5, 0), Vector3(0.18, 2.0, 0.18), steel)
			_emblem(m, base + Vector3(0, 3.6, 0), r, Vector3.UP, f, 1.3, false)
			b.solid(Vector3(8.4, 4.0, 1.4), base + Vector3(0, 2.0, 0), root)
	# (RoadMesh isn't indexed and the kit pieces are: batched together, SurfaceTool keeps only
	# the indexed triangles. These few stay their own draws.)
	m.instance(st, PropKit.material("Metal"), "Statement").set_meta("no_batch", true)


## The brand's emblem centred at c in the plane (r, u), facing f, `size` its
## half-height. flat: a lit sign (thin, the sign's colours); else a chunky
## metal piece.
func _emblem(m, c: Vector3, r: Vector3, u: Vector3, f: Vector3, size: float, flat: bool) -> void:
	var depth := 0.02 if flat else size * 0.12
	var silver := Color(0.86, 0.88, 0.92) if flat else Color(0.8, 0.82, 0.86)
	match brand:
		"mercedez":
			_ring(m, c, r, u, f, size * 0.9, size * 0.12, depth, silver)
			_star(m, c, r, u, f, size * 0.84, depth * (1.0 if flat else 1.6), silver)
		"porsha":
			_crest(m, c, r, u, f, size, depth)
		"audy":
			var R := size * 0.5
			for k in 4:
				_ring(m, c + r * (k - 1.5) * R * 1.5, r, u, f, R, R * 0.2, depth, silver)


## A flat ring (annulus), radius R, `w` wide, `depth` thick.
static func _ring(m, c: Vector3, r: Vector3, u: Vector3, f: Vector3, R: float, w: float, depth: float, col: Color) -> void:
	var n := 36
	var P := func(a: float, rad: float, z: float) -> Vector3:
		return c + (r * cos(a) + u * sin(a)) * rad + f * z
	var ri := R - w / 2.0
	var ro := R + w / 2.0
	var hz := depth / 2.0
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var out: Vector3 = r * cos((a0 + a1) / 2.0) + u * sin((a0 + a1) / 2.0)
		for z in [hz, -hz]:
			m.quad(P.call(a0, ri, z), P.call(a0, ro, z), P.call(a1, ro, z), P.call(a1, ri, z), col, f * signf(z))
		m.quad(P.call(a0, ro, hz), P.call(a1, ro, hz), P.call(a1, ro, -hz), P.call(a0, ro, -hz), col.darkened(0.15), out)
		m.quad(P.call(a0, ri, hz), P.call(a1, ri, hz), P.call(a1, ri, -hz), P.call(a0, ri, -hz), col.darkened(0.25), -out)


## Three pointed blades from the centre (one straight up), ridged down the middle.
static func _star(m, c: Vector3, r: Vector3, u: Vector3, f: Vector3, R: float, depth: float, col: Color) -> void:
	for k in 3:
		var a := PI / 2.0 + TAU * k / 3.0
		var tip: Vector3 = c + (r * cos(a) + u * sin(a)) * R
		var s0: Vector3 = c + (r * cos(a + PI / 3.0) + u * sin(a + PI / 3.0)) * R * 0.16
		var s1: Vector3 = c + (r * cos(a - PI / 3.0) + u * sin(a - PI / 3.0)) * R * 0.16
		for sg in [1.0, -1.0]:
			var ridge: Vector3 = f * depth * 0.5 * sg
			m.tri(c + ridge, s0, tip + ridge * 0.3, col, f * sg + (s0 - c).normalized() * 0.3)
			m.tri(c + ridge, tip + ridge * 0.3, s1, col.darkened(0.12), f * sg + (s1 - c).normalized() * 0.3)


## A crest: a gold shield, quartered: red-and-black bars, gold with black
## antler-ish bars; a small gold shield in the middle with a black leaping blob.
func _crest(m, c: Vector3, r: Vector3, u: Vector3, f: Vector3, H: float, depth: float) -> void:
	var gold := Color(0.93, 0.72, 0.26)
	var red := Color(0.72, 0.06, 0.08)
	var ink := Color(0.04, 0.04, 0.045)
	var W := H * 0.8
	var shield := PackedVector2Array([Vector2(-0.5, 0.5), Vector2(-0.25, 0.45), Vector2(0.0, 0.5), Vector2(0.25, 0.45),
		Vector2(0.5, 0.5), Vector2(0.5, 0.02), Vector2(0.45, -0.2), Vector2(0.32, -0.38), Vector2(0.0, -0.52),
		Vector2(-0.32, -0.38), Vector2(-0.45, -0.2), Vector2(-0.5, 0.02)])
	var P := func(q: Vector2, z: float) -> Vector3:
		return c + r * q.x * W + u * q.y * H + f * z
	var fill := func(poly: PackedVector2Array, z: float, col: Color, face: Vector3) -> void:
		var tris := Geometry2D.triangulate_polygon(poly)
		for i in range(0, tris.size() - 2, 3):
			m.tri(P.call(poly[tris[i]], z), P.call(poly[tris[i + 1]], z), P.call(poly[tris[i + 2]], z), col, face)
	var scaled := func(k: float, off: Vector2) -> PackedVector2Array:
		var out := PackedVector2Array()
		for q in shield:
			out.append(q * k + off)
		return out
	var hz := depth / 2.0
	fill.call(shield, hz, gold, f)
	fill.call(shield, -hz, gold.darkened(0.2), -f)
	for i in shield.size():          # the rim
		var q0: Vector2 = shield[i]
		var q1: Vector2 = shield[(i + 1) % shield.size()]
		m.quad(P.call(q0, hz), P.call(q1, hz), P.call(q1, -hz), P.call(q0, -hz), gold.darkened(0.3), P.call((q0 + q1) * 0.5, 0.0) - c)
	var inner: PackedVector2Array = scaled.call(0.84, Vector2(0, -0.02))
	var z1 := hz + 0.004
	for qd in 4:
		var rx := Rect2(-0.5 if qd % 2 == 0 else 0.0, 0.0 if qd < 2 else -0.6, 0.5, 0.6)
		var box := PackedVector2Array([rx.position, Vector2(rx.end.x, rx.position.y), rx.end, Vector2(rx.position.x, rx.end.y)])
		var striped := qd == 0 or qd == 3          # the red-and-black quarters; the others gold with black bars
		for piece in Geometry2D.intersect_polygons(inner, box):
			fill.call(piece, z1, ink if striped else gold.lightened(0.08), f)
			var y := rx.position.y + 0.04
			while y < rx.end.y - 0.02:
				var band := PackedVector2Array([Vector2(rx.position.x, y), Vector2(rx.end.x, y), Vector2(rx.end.x, y + 0.05),
					Vector2(rx.position.x, y + 0.05)])
				for s in Geometry2D.intersect_polygons(piece, band):
					fill.call(s, z1 + 0.003, red if striped else ink, f)
				y += 0.1 if striped else 0.14
	fill.call(scaled.call(0.34, Vector2(0, 0.0)), z1 + 0.01, gold.darkened(0.1), f)
	fill.call(scaled.call(0.28, Vector2(0, 0.005)), z1 + 0.013, gold.lightened(0.15), f)
	fill.call(PackedVector2Array([Vector2(-0.05, -0.1), Vector2(0.06, -0.02), Vector2(0.07, 0.1), Vector2(0.0, 0.05),
		Vector2(-0.07, 0.09), Vector2(-0.03, -0.01)]), z1 + 0.016, ink, f)
