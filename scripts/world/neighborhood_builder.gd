extends RefCounted
## MAGNOLIA HEIGHTS: a slightly worn working-class neighborhood of modest
## starter homes (ranches, shotguns, craftsman bungalows, tin-roof shotguns),
## ~750 m out from downtown along a six-lane highway with live traffic.
##
## Layout (world, y up, -z = north; downtown street at z = 240, x -40..40):
##   downtown east end --connector--> roundabout (82, 241) --> junction by the
##   highway: an at-grade exit from westbound + a flyover on-ramp that crosses
##   the highway and merges eastbound. The highway (highway.gd) runs x 80..1150
##   at z ~365-385 between two tunnels. At station 600 the mirror-image
##   interchange: an eastbound exit to the hood road and roundabout, and a
##   flyover on-ramp back west. Magnolia Heights is south of it: Magnolia St
##   (east from the roundabout), Delta Ave (south), Pecan St, Levee Rd.
## 30 houses from houses_kit.glb (tools/blender/build_houses.py); 6 of them are
## for sale (Rules.HOUSES) and have full interiors that line up with the shell.
##
## Everything is built under one "Hood" node with its own batching and
## visibility ranges, so none of it costs anything from the office.

const Highway = preload("res://scripts/world/highway.gd")
const RoadMesh = preload("res://scripts/world/road_mesh.gd")
const PropKit = preload("res://scripts/art/prop_kit.gd")
const Batcher = preload("res://scripts/art/batcher.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const TrafficScript = preload("res://scripts/world/traffic.gd")
const RealtorUI = preload("res://scripts/ui/realtor_ui.gd")

const GROUND_Y := -0.25
const SKY := 2                   # sun-lit render layer (the office builder's SKY_LAYER)
const INT_LAYER := 1 << 10       # house interiors: lit by their own lamps only
const LAWN_Y := 0.1
const WALK_Y := 0.12
const FAR_RANGE := 800.0
const MID_RANGE := 230.0
const INT_RANGE := 55.0
const SETBACK := 13.0            # street centerline -> front wall of a house
const LOT_D := 28.0              # lot depth behind the sidewalk (7 m from the centerline)

const ASPHALT := Color(0.2, 0.205, 0.215)
const ASPHALT_L := ASPHALT
const LINE_W := Color(0.88, 0.88, 0.85)
const LINE_Y := Color(0.92, 0.74, 0.16)
const CONCRETE := Color(0.7, 0.69, 0.66)
const CONCRETE_D := Color(0.55, 0.54, 0.52)
const SIDEWALK := Color(0.68, 0.68, 0.66)
const DIRT := Color(0.42, 0.36, 0.28)
const GRASS := Color(0.29, 0.42, 0.19)
const LAWN := Color(0.27, 0.45, 0.17)

## Siding / trim / roof palettes (tinted at runtime, see _house_mats).
const SIDING := [Color(0.66, 0.8, 0.9), Color(0.95, 0.95, 0.93), Color(0.7, 0.88, 0.76), Color(0.96, 0.88, 0.58),
	Color(0.7, 0.71, 0.72), Color(0.95, 0.8, 0.8), Color(0.45, 0.6, 0.78), Color(0.93, 0.93, 0.9)]
const ROOFS := [Color(0.42, 0.42, 0.44), Color(0.3, 0.3, 0.32), Color(0.45, 0.36, 0.3), Color(0.36, 0.4, 0.38)]

## The streets, lot by lot. [type, lot width, number, buyable id or "", siding index, extras]
## extras: d = driveway, c = parked car, f = front picket fence, t = front yard tree,
##         p = pine, b = back yard stuff, w = wood back fence
const MAGNOLIA_N := [["bungalow", 17.0, 101, "", 6, "dtwb"], ["shotgun", 11.0, 103, "", 1, "wb"],
	["ranch", 20.0, 105, "ranch_a", 0, "dcfw"], ["tin", 9.5, 107, "", 1, "b"], ["tin", 9.5, 109, "", 3, "w"],
	["bungalow", 16.0, 111, "", 2, "dpwb"], ["ranch", 21.0, 113, "ranch_b", 4, "dctwb"]]
const MAGNOLIA_S := [["ranch", 19.0, 100, "", 7, "dcwb"], ["shotgun", 11.0, 102, "shotgun_a", 1, "wb"],
	["shotgun", 11.0, 104, "", 5, "w"], ["bungalow", 16.0, 106, "", 3, "dctb"], ["ranch", 19.0, 108, "", 5, "dwb"],
	["bungalow", 16.0, 110, "", 6, "dpw"], ["shotgun", 11.0, 112, "", 2, "b"], ["tin", 10.0, 114, "", 1, "w"]]
const PECAN_N := [["bungalow", 17.0, 401, "bungalow_a", 0, "dptwb"], ["ranch", 19.0, 403, "", 3, "dcwb"],
	["shotgun", 11.0, 405, "", 2, "w"], ["bungalow", 16.0, 407, "", 4, "dcb"], ["tin", 10.0, 409, "", 1, "b"],
	["ranch", 19.0, 411, "", 6, "dtwb"], ["bungalow", 16.0, 413, "", 5, "dw"]]
const PECAN_S := [["tin", 9.0, 400, "", 1, "b"], ["tin", 9.0, 402, "", 1, "w"], ["tin", 9.0, 404, "tin_a", 1, "b"],
	["tin", 9.0, 406, "", 1, ""], ["tin", 9.0, 408, "", 1, "b"], ["bungalow", 30.0, 410, "bungalow_b", 7, "dcptwb"],
	["ranch", 21.0, 412, "", 2, "dcwb"], ["shotgun", 11.0, 414, "", 5, "wb"]]
const DOORS := {"ranch": "Door_White", "shotgun": "Door_Red", "bungalow": "Door_White", "tin": "Door_Wood"}
const PARKED := ["TCar_Sedan_Silver", "TCar_Pickup_Red", "TCar_SUV_White", "TCar_Hatch_Blue", "TCar_Sedan_Grey",
	"TCar_Pickup_Grey", "TCar_SUV_Silver", "TCar_Sedan_Red", "TCar_Hatch_Grey"]

var b                       # office builder
var root: Node3D
var hw: Highway              # the road data (highway.gd)
var traffic
var layout := {}            # houses_layout.json
var cars_layout := {}
var houses: Array = []      # one Dictionary per house (see _house)
var buyable := {}           # house id -> index into houses
var taxi: Array = []        # [{pos, yaw, label}] 0 = downtown, 1 = Magnolia Heights
var hood_rect := Rect2()
var r2 := Vector3.ZERO      # the Magnolia Heights roundabout
var street_names: Array = []
var g_far: Node3D
var g_mid: Node3D
var g_road: Node3D
var g_dyn: Node3D           # doors, labels, interiors: never batched
var mats := {}
var road_mat: StandardMaterial3D
var glow_mat: StandardMaterial3D
var rng := RandomNumberGenerator.new()
var build_ms := 0
var dealership_marker: Marker3D      # the empty lot for the car dealership (world position = its center)
var _tree_blockers: Array = []
var _tree_rects: Array = []
var _lot_mesh
var _font: Font   # [center Vector2, radius] spots trees keep out of


func _init(builder) -> void:
	b = builder


func build() -> Node3D:
	var t0 := Time.get_ticks_msec()
	rng.seed = 1977
	root = Node3D.new()
	root.name = "Hood"
	b.root.add_child(root)
	for n in ["Road", "Far", "Mid", "Dyn"]:
		var g := Node3D.new()
		g.name = n
		root.add_child(g)
	g_road = root.get_node("Road")
	g_far = root.get_node("Far")
	g_mid = root.get_node("Mid")
	g_dyn = root.get_node("Dyn")
	hw = Highway.new()
	r2 = hw.roundabout_hood
	layout = _json("res://assets/props/houses_layout.json")
	cars_layout = _json("res://assets/props/cars_layout.json")
	road_mat = StandardMaterial3D.new()
	road_mat.vertex_color_use_as_albedo = true
	road_mat.roughness = 0.95
	glow_mat = PropKit.material("Glow")
	_ground()
	_mainline()
	_tunnel(true)
	_tunnel(false)
	_ramps()
	_local_roads()
	_highway_furniture()
	_neighborhood()
	_taxi_stands()
	_downtown_gap()
	_scatter_trees()
	_downtown_impostor()
	_finish()
	traffic = TrafficScript.new()
	traffic.name = "Traffic"
	root.add_child(traffic)
	traffic.setup(hw)
	build_ms = Time.get_ticks_msec() - t0
	b = null      # the office builder keeps us; don't keep it back (RefCounted cycle)
	return root


static func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing " + path)
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


# ================================================================== helpers

## Mainline point that keeps going straight past the ends (tunnel hills).
func _pt(s: float, d: float, y := 0.0) -> Vector3:
	if s < 0.0:
		return hw.point(0.0, d, y) + hw.tangent(0.0) * s
	if s > hw.length:
		return hw.point(hw.length, d, y) + hw.tangent(hw.length) * (s - hw.length)
	return hw.point(s, d, y)


static func yaw_of(dir: Vector3) -> float:
	return atan2(dir.x, dir.z)


func prop(nm: String, pos: Vector3, rot := 0.0, parent: Node3D = null, scl := 1.0) -> Node3D:
	return PropKit.place(nm, parent if parent else g_mid, pos, rot, scl)


func solid(size: Vector3, pos: Vector3, rot_y := 0.0, parent: Node3D = null, rot_x := 0.0) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	sb.position = pos
	sb.rotation = Vector3(rot_x, rot_y, 0)
	(parent if parent else g_dyn).add_child(sb)
	return sb


func label(text: String, pos: Vector3, size: int, color: Color, rot_y := 0.0, parent: Node3D = null,
		pixel := 0.005, range_end := 80.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 0
	l.position = pos
	l.rotation.y = rot_y
	l.double_sided = false
	l.visibility_range_end = range_end
	if _font == null:
		_font = load("res://assets/fonts/Oswald-Bold.woff2")
	if _font:
		l.font = _font
	(parent if parent else g_dyn).add_child(l)
	return l


func interact(sb: StaticBody3D, type: String, id: int, prompt: String) -> void:
	sb.set_meta("interact", type)
	sb.set_meta("interact_id", id)
	sb.set_meta("prompt", prompt)


## A parked car from the traffic kit (body + wheels), nose along `yaw`.
func parked_car(model: String, pos: Vector3, yaw: float, parent: Node3D = null) -> void:
	var n := prop(model, pos, yaw, parent)
	var lay: Dictionary = cars_layout.get(model, {})
	for az in lay.get("axles", []):
		for sx in [-1.0, 1.0]:
			var w := prop(lay.get("wheel", "Wheel_Car"), Vector3(sx * float(lay.track), float(lay.r), float(az)), 0.0, n)
			w.rotation.x = rng.randf_range(0, TAU)


# ================================================================== ground

func _ground() -> void:
	var rects := [Rect2(-300, 262, 1700, 540), Rect2(-300, 60, 1700, 158), Rect2(53, 218, 1347, 44), Rect2(-300, 218, 247, 44)]
	for r: Rect2 in rects:
		# collision: one slab per rect
		var sb := solid(Vector3(r.size.x, 2.0, r.size.y), Vector3(r.position.x + r.size.x / 2, GROUND_Y - 1.0,
				r.position.y + r.size.y / 2), 0.0, g_road)
		sb.name = "Ground"
		# visuals: 100 m tiles of 10 m cells with patchy vertex colors
		var tx := r.position.x
		while tx < r.end.x - 0.01:
			var tz := r.position.y
			while tz < r.end.y - 0.01:
				var w := minf(300.0, r.end.x - tx)
				var h := minf(300.0, r.end.y - tz)
				var m := RoadMesh.new()
				var cell := 10.0
				var nx := maxi(int(ceil(w / cell)), 1)
				var nz := maxi(int(ceil(h / cell)), 1)
				for i in nx:
					for j in nz:
						var x0 := tx + w * i / nx
						var x1 := tx + w * (i + 1) / nx
						var z0 := tz + h * j / nz
						var z1 := tz + h * (j + 1) / nz
						var k := sin(x0 * 0.043 + z0 * 0.021) * 0.5 + sin(x0 * 0.011 - z0 * 0.037) * 0.5
						var c := GRASS.lerp(Color(0.46, 0.5, 0.26), clampf(k * 0.6 + 0.2, 0.0, 1.0) * 0.6)
						c = c.darkened(rng.randf_range(0.0, 0.06))
						m.quad(Vector3(x0, GROUND_Y, z0), Vector3(x1, GROUND_Y, z0), Vector3(x1, GROUND_Y, z1),
								Vector3(x0, GROUND_Y, z1), c, Vector3.UP)
				m.instance(g_road, road_mat, "Ground").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				tz += 300.0
			tx += 300.0


# ================================================================== highway

## Lane markings: 1 station of dash every 4 (3 m on, 9 m off).
func _mainline() -> void:
	var n := hw.cl.size()
	var chunk := 50
	var i0 := 0
	while i0 < n - 1:
		var m := RoadMesh.new()
		var i1 := mini(i0 + chunk, n - 1)
		for i in range(i0, i1):
			var sa := i * Highway.STEP
			var sb := (i + 1) * Highway.STEP
			var sm := (sa + sb) * 0.5
			var dash := i % 4 == 0
			for dir in [1, -1]:
				var aux: bool = hw.has_aux(dir, sm)
				var strips: Array = []   # [d0, d1, color]
				var e0 := Highway.EDGE_IN
				strips.append([Highway.MEDIAN, e0 - 0.08, ASPHALT])
				strips.append([e0 - 0.08, e0 + 0.08, LINE_Y])
				for k in Highway.LANES:
					var l0 := e0 + Highway.LANE_W * k + 0.08
					var l1 := e0 + Highway.LANE_W * (k + 1) - 0.08
					strips.append([l0, l1, ASPHALT])
					var lc := LINE_W if (k < Highway.LANES - 1 and dash) or (k == Highway.LANES - 1 and (not aux or i % 2 == 0)) else ASPHALT
					strips.append([l1, l1 + 0.16, lc])
				var eo := Highway.EDGE_OUT + 0.08
				var outer := Highway.EDGE_OUT + Highway.OUT_SH
				if aux:
					strips.append([eo, eo + Highway.LANE_W - 0.16, ASPHALT])
					strips.append([eo + Highway.LANE_W - 0.16, eo + Highway.LANE_W, LINE_W])
					outer = Highway.EDGE_OUT + Highway.LANE_W + Highway.AUX_SH
					eo += Highway.LANE_W
				strips.append([eo, outer, ASPHALT])
				for st in strips:
					var d0: float = st[0] * dir
					var d1: float = st[1] * dir
					m.quad(hw.point(sa, d0), hw.point(sa, d1), hw.point(sb, d1), hw.point(sb, d0), st[2], Vector3.UP, true)
				# skirt at the outer edge
				var oa := hw.point(sa, outer * dir)
				var ob := hw.point(sb, outer * dir)
				m.quad(oa, ob, ob + Vector3(0, -0.7, 0), oa + Vector3(0, -0.7, 0), DIRT, hw.right(sm) * dir)
			# median jersey barrier
			var prof := [[-0.4, 0.0], [-0.3, 0.08], [-0.13, 0.3], [-0.1, 0.82], [0.1, 0.82], [0.13, 0.3], [0.3, 0.08], [0.4, 0.0]]
			for k in prof.size() - 1:
				var pa: Array = prof[k]
				var pb: Array = prof[k + 1]
				var nrm := Vector2(-(pb[1] - pa[1]), pb[0] - pa[0])
				var upv := hw.right(sm) * nrm.x + Vector3.UP * nrm.y
				var col := CONCRETE if k != 3 else CONCRETE.lightened(0.05)
				m.quad(hw.point(sa, pa[0], pa[1]), hw.point(sa, pb[0], pb[1]), hw.point(sb, pb[0], pb[1]),
						hw.point(sb, pa[0], pa[1]), col, upv, true)
		m.instance(g_road, road_mat, "Mainline", 1500.0).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		i0 = i1


## Tunnel + portal + the hill it goes through. west=true: s 0..60, else the east end.
func _tunnel(west: bool) -> void:
	var sp: float = hw.s_portal_w if west else hw.s_portal_e     # portal face station
	var se: float = 0.0 if west else hw.length                    # inner end
	var sg := -1.0 if west else 1.0                               # direction from portal into the hill
	var m := RoadMesh.new()
	var gm := RoadMesh.new()
	var H := 7.5
	var W := Highway.EDGE_OUT + Highway.OUT_SH + 0.3
	var dark := Color(0.3, 0.3, 0.32)
	var steps := int(absf(sp - se) / Highway.STEP)
	for i in steps:
		var sa := sp + sg * i * Highway.STEP
		var sb := sp + sg * (i + 1) * Highway.STEP
		for dd in [-W, W]:
			m.quad(hw.point(sa, dd, 0), hw.point(sb, dd, 0), hw.point(sb, dd, H), hw.point(sa, dd, H), dark.darkened(0.1),
					hw.right(sa) * -signf(dd), true)
		m.quad(hw.point(sa, -W, H), hw.point(sa, W, H), hw.point(sb, W, H), hw.point(sb, -W, H), dark.darkened(0.35),
				Vector3.DOWN)
		for dd in [-0.4, 0.4]:
			m.quad(hw.point(sa, dd, 0.8), hw.point(sb, dd, 0.8), hw.point(sb, dd, H), hw.point(sa, dd, H), dark,
					hw.right(sa) * signf(dd), true)
		if i % 3 == 1:   # ceiling light strips over each bore
			for dd in [-7.5, 7.5]:
				var c := hw.point(sa, dd, H - 0.05)
				var t := hw.tangent(sa) * 1.2
				var r := hw.right(sa) * 0.35
				gm.quad(c - t - r, c + t - r, c + t + r, c - t + r, Color(1, 0.9, 0.7), Vector3.DOWN)
	# the far end is black: cars appear out of the dark
	m.quad(hw.point(se, -W, 0), hw.point(se, W, 0), hw.point(se, W, H), hw.point(se, -W, H), Color(0.02, 0.02, 0.02),
			hw.tangent(se) * sg * -1.0, true)
	# portal face (thick concrete wall with two bores), wing walls and the hill
	var PW := 26.0
	var PH := 12.0
	var face := func(d0: float, d1: float, y0: float, y1: float) -> void:
		m.quad(hw.point(sp, d0, y0), hw.point(sp, d1, y0), hw.point(sp, d1, y1), hw.point(sp, d0, y1), CONCRETE,
				hw.tangent(sp) * -sg)
	face.call(-PW, -W, 0.0, PH)
	face.call(W, PW, 0.0, PH)
	face.call(-W, W, H, PH)
	face.call(-0.4, 0.4, 0.0, H)
	var cap := hw.point(sp, 0, PH)
	m.quad(hw.point(sp, -PW - 0.5, PH), hw.point(sp, PW + 0.5, PH), hw.point(sp, PW + 0.5, PH + 0.6),
			hw.point(sp, -PW - 0.5, PH + 0.6), CONCRETE_D, hw.tangent(sp) * -sg)
	# the hill: a mesa over the tunnel whose slopes run down to the ground
	var top := 13.0
	var back := 40.0
	var sb2 := sp + sg * (absf(sp - se) + back)
	var outer := 52.0
	var g := func(s: float, d: float, y: float) -> Vector3:
		return _pt(s, d, y)
	var sl := func(a: Vector3, bb: Vector3, c: Vector3, dd: Vector3, up: Vector3) -> void:
		var col := GRASS.darkened(rng.randf_range(0.0, 0.08))
		m.quad(a, bb, c, dd, col, up, true)
	# top + portal-side cliff (the portal wall), side slopes, back slope
	var n := 8
	for k in n:
		var s0 := lerpf(sp, sb2, float(k) / n)
		var s1 := lerpf(sp, sb2, float(k + 1) / n)
		sl.call(g.call(s0, -PW, top), g.call(s0, PW, top), g.call(s1, PW, top), g.call(s1, -PW, top), Vector3.UP)
		for side in [-1.0, 1.0]:
			sl.call(g.call(s0, side * PW, top), g.call(s1, side * PW, top), g.call(s1, side * outer, GROUND_Y),
					g.call(s0, side * outer, GROUND_Y), Vector3.UP)
	for side in [-1.0, 1.0]:   # triangular wing walls beside the portal
		m.tri(g.call(sp, side * PW, top), g.call(sp, side * outer, GROUND_Y), g.call(sp, side * PW, GROUND_Y), CONCRETE_D,
				hw.tangent(sp) * -sg, true)
	face.call(-PW, PW, PH + 0.6, top)
	var s_end := sb2 + sg * 55.0
	sl.call(g.call(sb2, -PW, top), g.call(sb2, PW, top), g.call(s_end, PW, GROUND_Y), g.call(s_end, -PW, GROUND_Y), Vector3.UP)
	for side in [-1.0, 1.0]:
		sl.call(g.call(sb2, side * PW, top), g.call(s_end, side * PW, GROUND_Y), g.call(s_end, side * outer, GROUND_Y),
				g.call(sb2, side * outer, GROUND_Y), Vector3.UP)
	m.instance(g_road, road_mat, "Tunnel", 1500.0)
	gm.instance(g_road, glow_mat, "TunnelLights", 400.0)
	# trees on top of the hill
	for k in 14:
		var s := lerpf(sp, sb2, rng.randf())
		var d := rng.randf_range(-PW + 3.0, PW - 3.0)
		prop(["TreePine", "TreeOak", "TreeSmall"][k % 3], g.call(s, d, top), rng.randf_range(0, TAU), g_far,
				rng.randf_range(0.8, 1.2))
	# invisible stop at the inner end so nobody walks out of the world
	var ce := hw.point(se + sg * -2.0, 0, 4)
	solid(Vector3(40, 10, 1), ce, yaw_of(hw.tangent(se)), g_road)
	_tree_blockers.append([Vector2(hw.point((sp + sb2) / 2, 0).x, hw.point((sp + sb2) / 2, 0).z), 110.0])


## Ramp decks: a lane with shoulders; parapets when raised; retaining walls
## down to the ground except where the ramp flies over the highway (a bridge
## span with a median pier); tapers into the aux lane cross-section at the end
## that meets the highway.
func _ramps() -> void:
	for nm in ["dt_on", "dt_off", "hood_on", "hood_off", "dealer_off"]:
		var p = hw.paths[nm]
		var joins_end: bool = nm.ends_with("_on")      # which end meets the mainline
		var m := RoadMesh.new()
		var n: int = p.pts.size()
		var span_pier_done := false
		for i in n - 1:
			var a: Vector3 = p.pts[i]
			var c: Vector3 = p.pts[i + 1]
			var ta: Vector3 = p.tan[i]
			var tc: Vector3 = p.tan[i + 1]
			var ra := Vector3(ta.x, 0, ta.z).normalized().cross(Vector3.UP).normalized()
			var rc := Vector3(tc.x, 0, tc.z).normalized().cross(Vector3.UP).normalized()
			# distance (along the ramp) from the mainline junction: taper over 60 m
			var dj: float = (p.length - p.cum[i]) if joins_end else p.cum[i]
			var t := clampf(dj / 60.0, 0.0, 1.0)
			var lsh := lerpf(0.0, 0.8, t)
			var lw := lerpf(Highway.LANE_W, 4.0, t) / 2.0
			var rsh := lerpf(Highway.AUX_SH, 1.8, t)
			var y_lift := 0.012 * t
			var strips := [[-lw - lsh, -lw, ASPHALT], [-lw, -lw + 0.15, LINE_W if t > 0.95 else ASPHALT], [-lw + 0.15, lw - 0.15, ASPHALT],
				[lw - 0.15, lw, LINE_W], [lw, lw + rsh, ASPHALT]]
			var up := Vector3.UP
			for stp in strips:
				if stp[1] - stp[0] < 0.01:
					continue
				var o := Vector3(0, y_lift, 0)
				m.quad(a + ra * stp[0] + o, a + ra * stp[1] + o, c + rc * stp[1] + o, c + rc * stp[0] + o, stp[2], up, true)
			var ea := [a + ra * (-lw - lsh), a + ra * (lw + rsh)]
			var ec := [c + rc * (-lw - lsh), c + rc * (lw + rsh)]
			var raised := a.y > 0.4 or c.y > 0.4
			var mid := (a + c) * 0.5
			var loc: Vector2 = hw.locate(mid)
			var over := absf(loc.y) < Highway.EDGE_OUT + Highway.OUT_SH + 3.0 and mid.y > 4.0
			for side in 2:
				var sgn := -1.0 if side == 0 else 1.0
				var ea_: Vector3 = ea[side]
				var ec_: Vector3 = ec[side]
				var outv := (ra + rc).normalized() * sgn
				if raised:   # parapet
					var h := Vector3(0, 0.9, 0)
					var inset := -outv * 0.3
					m.quad(ea_ + inset, ec_ + inset, ec_ + inset + h, ea_ + inset + h, CONCRETE, -outv, true)
					m.quad(ea_, ec_, ec_ + h, ea_ + h, CONCRETE.darkened(0.08), outv, true)
					m.quad(ea_ + h, ec_ + h, ec_ + inset + h, ea_ + inset + h, CONCRETE.lightened(0.05), Vector3.UP)
				var bottom := GROUND_Y - 0.3 if not over else maxf(a.y, c.y) - 1.3
				var ya := Vector3(ea_.x, bottom if not over else a.y - 1.3, ea_.z)
				var yc := Vector3(ec_.x, bottom if not over else c.y - 1.3, ec_.z)
				m.quad(ea_, ec_, yc, ya, CONCRETE_D if raised else DIRT, outv, not over)
			if over:   # bridge span: deck underside + girders; a pier in the median
				var da := [ea[0] - Vector3(0, 1.3, 0), ea[1] - Vector3(0, 1.3, 0)]
				var dc := [ec[0] - Vector3(0, 1.3, 0), ec[1] - Vector3(0, 1.3, 0)]
				m.quad(da[0], da[1], dc[1], dc[0], CONCRETE_D.darkened(0.2), Vector3.DOWN)
				if absf(loc.y) < 2.0 and not span_pier_done:
					span_pier_done = true
					var pb := Vector3(mid.x, 0.8, mid.z)
					m.obox(pb, ta, Vector3(1.6, mid.y - 1.3 - 0.8, 1.6), CONCRETE, true)
			# abutment faces where the embankment meets the span
			var loc_a: Vector2 = hw.locate(a)
			var loc_c: Vector2 = hw.locate(c)
			var edge := Highway.EDGE_OUT + Highway.OUT_SH + 3.0
			if a.y > 4.0 and ((absf(loc_a.y) >= edge) != (absf(loc_c.y) >= edge)):
				var ee: Array = ea if absf(loc_a.y) >= edge else ec
				var tt := ta
				m.quad(ee[0], ee[1], Vector3(ee[1].x, GROUND_Y, ee[1].z), Vector3(ee[0].x, GROUND_Y, ee[0].z), CONCRETE,
						tt * (1.0 if absf(loc_a.y) >= edge else -1.0), true)
		m.instance(g_road, road_mat, "Ramp_" + nm, 1500.0)
		for k in range(0, n, 3):
			_tree_blockers.append([Vector2(p.pts[k].x, p.pts[k].z), 12.0])


## The downtown connector and the hood road (2 lanes, double yellow), plus
## their roundabouts (ring + a raised island with a tree).
func _local_roads() -> void:
	for nm in ["dt_road", "hood_road", "dealer_road"]:
		var p = hw.paths[nm]
		var m := RoadMesh.new()
		for i in p.pts.size() - 1:
			var a: Vector3 = p.pts[i]
			var c: Vector3 = p.pts[i + 1]
			var ra: Vector3 = p.tan[i].cross(Vector3.UP).normalized()
			var rc: Vector3 = p.tan[i + 1].cross(Vector3.UP).normalized()
			var strips := [[-5.0, -4.2, ASPHALT_L], [-4.2, -4.05, LINE_W], [-4.05, -0.2, ASPHALT_L], [-0.2, -0.08, LINE_Y],
				[-0.08, 0.08, ASPHALT_L], [0.08, 0.2, LINE_Y], [0.2, 4.05, ASPHALT_L], [4.05, 4.2, LINE_W], [4.2, 5.0, ASPHALT_L]]
			for st in strips:
				m.quad(a + ra * st[0], a + ra * st[1], c + rc * st[1], c + rc * st[0], st[2], Vector3.UP, true)
			for sg in [-1.0, 1.0]:
				m.quad(a + ra * 5.0 * sg, c + rc * 5.0 * sg, c + rc * 5.0 * sg + Vector3(0, -0.5, 0),
						a + ra * 5.0 * sg + Vector3(0, -0.5, 0), DIRT, ra * sg)
			if i % 3 == 0:
				_tree_blockers.append([Vector2(a.x, a.z), 10.0])
		m.instance(g_road, road_mat, "LocalRoad", 1500.0)
	for c in [hw.roundabout_dt, hw.roundabout_hood]:
		_roundabout(c)
	_dealership_lot()


## The empty lot a car dealership will go on (the owner builds it): flat
## asphalt with a curb, a Marker3D "DealershipLot" at its center.
func _dealership_lot() -> void:
	var r: Rect2 = hw.dealership_rect
	var m := RoadMesh.new()
	var c := Vector3(r.get_center().x, 0.0, r.get_center().y)
	m.box(c + Vector3(0, GROUND_Y / 2.0 - 0.1, 0), Vector3(r.size.x, -GROUND_Y + 0.2, r.size.y), ASPHALT, true)
	for e in [[Vector3(0, 0, -r.size.y / 2), Vector3(r.size.x, 0.15, 0.3)], [Vector3(0, 0, r.size.y / 2), Vector3(r.size.x, 0.15, 0.3)],
			[Vector3(-r.size.x / 2, 0, 0), Vector3(0.3, 0.15, r.size.y)], [Vector3(r.size.x / 2, 0, 0), Vector3(0.3, 0.15, r.size.y)]]:
		# curbs all round, with gaps where the exit ramp and the Levee Rd road come in
		var at: Vector3 = c + e[0]
		var sz: Vector3 = e[1]
		if sz.x > 1.0:
			var gap_x: float = hw.paths["dealer_off"].at(hw.paths["dealer_off"].length).x if e[0].z < 0 else r.position.x + 6.0
			var x0 := r.position.x
			var x1 := r.end.x
			for seg in [[x0, gap_x - 6.0], [gap_x + 6.0, x1]]:
				if seg[1] - seg[0] > 0.5:
					m.box(Vector3((seg[0] + seg[1]) / 2.0, 0.075, at.z), Vector3(seg[1] - seg[0], 0.15, 0.3), CONCRETE, true)
		else:
			m.box(at + Vector3(0, 0.075, 0), sz, CONCRETE, true)
	m.instance(g_road, road_mat, "DealershipLot", 1500.0)
	var mk := Marker3D.new()
	mk.name = "DealershipLot"
	mk.position = c
	g_dyn.add_child(mk)
	dealership_marker = mk
	_tree_blockers.append([Vector2(c.x, c.z), 45.0])


func _roundabout(c: Vector3) -> void:
	var m := RoadMesh.new()
	var n := 36
	var R := Highway.RB_R
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var rings := [[6.0, 6.3, LINE_W], [6.3, R - 0.45, ASPHALT_L], [R - 0.45, R - 0.3, LINE_W], [R - 0.3, R, ASPHALT_L]]
		for rr in rings:
			m.quad(c + d0 * rr[0], c + d0 * rr[1], c + d1 * rr[1], c + d1 * rr[0], rr[2], Vector3.UP, true)
		# the island: curb + grass, raised
		m.quad(c + d0 * 6.0, c + d1 * 6.0, c + d1 * 6.0 + Vector3(0, 0.18, 0), c + d0 * 6.0 + Vector3(0, 0.18, 0),
				CONCRETE, d0, true)
		m.tri(c + Vector3(0, 0.18, 0), c + d0 * 6.0 + Vector3(0, 0.18, 0), c + d1 * 6.0 + Vector3(0, 0.18, 0),
				GRASS.lightened(0.05), Vector3.UP, true)
		m.quad(c + d0 * R, c + d1 * R, c + d1 * R + Vector3(0, -0.5, 0), c + d0 * R + Vector3(0, -0.5, 0), DIRT, d0)
	m.instance(g_road, road_mat, "Roundabout", 1500.0)
	prop("TreeOak", c + Vector3(0, 0.18, 0), 0.7, g_far, 0.9)
	for k in 6:
		var a := TAU * k / 6 + 0.3
		prop("BushFlower", c + Vector3(cos(a) * 4.2, 0.18, sin(a) * 4.2), a, g_mid)
	_tree_blockers.append([Vector2(c.x, c.z), R + 8.0])


func _highway_furniture() -> void:
	var L: float = hw.length
	# median lights
	var s := hw.s_portal_w + 30.0
	while s < hw.s_portal_e - 20.0:
		if absf(s - Highway.SB_DOWNTOWN) > 16.0 and absf(s - Highway.SB_HOOD) > 16.0:
			prop("HwyLight", hw.point(s, 0, 0.82), yaw_of(hw.tangent(s)), g_far)
		s += 66.0
	# sign gantries
	_gantry(395.0, ["MAGNOLIA HEIGHTS", "EXIT 7  ·  RIGHT LANE"], ["DOWNTOWN · FINANCIAL DIST", "EXIT 3  ·  1/4 MI"])
	_gantry(700.0, ["DEALER ROW", "EXIT 8  ·  1/4 MI"], ["DOWNTOWN", "2 MI  ·  MAGNOLIA HTS 1"])
	_gantry(90.0, ["MAGNOLIA HEIGHTS", "1/2 MI"], ["TUNNEL", "LIGHTS ON"])
	# guardrails and sound walls (station ranges chosen to stay clear of the ramps)
	for r in [[1, 64.0, 240.0], [-1, 64.0, 112.0], [-1, 152.0, 225.0], [-1, 612.0, L - 64.0]]:
		_guardrail(r[0], r[1], r[2])
	for r in [[1, 560.0, 588.0], [1, 614.0, Highway.DEALER_S - 8.0], [1, Highway.DEALER_S + 118.0, L - 70.0]]:
		_soundwall(r[0], r[1], r[2])


func _gantry(s: float, eb: Array, wb: Array) -> void:
	var m := RoadMesh.new()
	var t := hw.tangent(s)
	var W := Highway.EDGE_OUT + Highway.OUT_SH + 3.2
	for dd in [-W, W]:
		m.obox(hw.point(s, dd, 0), t, Vector3(0.55, 8.4, 0.55), Color(0.62, 0.64, 0.67), true)
		solid(Vector3(0.6, 8.4, 0.6), hw.point(s, dd, 4.2), yaw_of(t), g_road)
	for y in [7.2, 8.1]:   # the truss: two chords + a deck of struts
		var a := hw.point(s, -W, y)
		var c := hw.point(s, W, y)
		var r := t * 0.25
		for off in [-0.6, 0.6]:
			var o: Vector3 = t * off
			m.quad(a + o - Vector3(0, 0.12, 0), c + o - Vector3(0, 0.12, 0), c + o + Vector3(0, 0.12, 0),
					a + o + Vector3(0, 0.12, 0), Color(0.6, 0.62, 0.66), -t * signf(off))
			m.quad(a + o + Vector3(0, 0.12, 0) - r * 0.4, c + o + Vector3(0, 0.12, 0) - r * 0.4,
					c + o + Vector3(0, 0.12, 0) + r * 0.4, a + o + Vector3(0, 0.12, 0) + r * 0.4, Color(0.66, 0.68, 0.7), Vector3.UP)
	# a green sign over each carriageway, facing its traffic
	for side in [[1, eb], [-1, wb]]:
		var dir: int = side[0]
		var txt: Array = side[1]
		var dc := dir * (Highway.EDGE_IN + Highway.LANE_W * 1.8)
		var face := hw.point(s - dir * 0.75, dc, 0)
		var fwd := -t * dir               # the sign faces oncoming traffic
		var r := fwd.cross(Vector3.UP).normalized()
		var w := 7.5
		var hh := Vector3(0, 2.4, 0)
		var base := face + Vector3(0, 7.8 - 1.2, 0)
		m.quad(base - r * w / 2, base + r * w / 2, base + r * w / 2 + hh, base - r * w / 2 + hh, Color(0.05, 0.38, 0.2), fwd)
		m.quad(base - r * w / 2 - fwd * 0.1, base + r * w / 2 - fwd * 0.1, base + r * w / 2 + hh - fwd * 0.1,
				base - r * w / 2 + hh - fwd * 0.1, Color(0.4, 0.42, 0.45), -fwd)
		var l1 := label(txt[0], base + hh * 0.66 + fwd * 0.03, 120, Color(0.97, 0.97, 0.95), yaw_of(fwd), g_dyn, 0.012, 700.0)
		l1.outline_size = 0
		var l2 := label(txt[1], base + hh * 0.26 + fwd * 0.03, 80, Color(0.97, 0.97, 0.95), yaw_of(fwd), g_dyn, 0.012, 700.0)
		l2.outline_size = 0
	m.instance(g_far, road_mat, "Gantry", 900.0)


func _guardrail(dir: int, s0: float, s1: float) -> void:
	var m := RoadMesh.new()
	var d := dir * (Highway.EDGE_OUT + Highway.OUT_SH - 0.4)
	var s := s0
	var steel := Color(0.72, 0.73, 0.75)
	while s < s1:
		var s2 := minf(s + Highway.STEP * 2.0, s1)
		var a := hw.point(s, d, 0)
		var c := hw.point(s2, d, 0)
		var inward := -hw.right(s) * dir
		for yy in [[0.5, 0.8]]:
			m.quad(a + Vector3(0, yy[0], 0), c + Vector3(0, yy[0], 0), c + Vector3(0, yy[1], 0), a + Vector3(0, yy[1], 0),
					steel, inward, true)
			m.quad(a + Vector3(0, yy[1], 0), c + Vector3(0, yy[1], 0), c + Vector3(0, yy[1], 0) - inward * 0.12,
					a + Vector3(0, yy[1], 0) - inward * 0.12, steel.darkened(0.1), Vector3.UP)
		m.obox(a - inward * 0.15 + Vector3(0, -0.2, 0), hw.tangent(s), Vector3(0.12, 0.95, 0.12), Color(0.5, 0.5, 0.52))
		s = s2
	m.instance(g_far, road_mat, "Guardrail", 500.0)


func _soundwall(dir: int, s0: float, s1: float) -> void:
	var m := RoadMesh.new()
	var d := dir * 24.0
	var s := s0
	var k := 0
	while s < s1:
		var s2 := minf(s + 6.0, s1)
		var a := hw.point(s, d, GROUND_Y)
		var c := hw.point(s2, d, GROUND_Y)
		var r := hw.right(s) * dir
		var col := Color(0.72, 0.7, 0.65).darkened(0.03 * (k % 3))
		var h := Vector3(0, 4.7, 0)
		m.quad(a, c, c + h, a + h, col, -r, true)
		m.quad(a + r * 0.3, c + r * 0.3, c + h + r * 0.3, a + h + r * 0.3, col.darkened(0.08), r, true)
		m.quad(a + h, c + h, c + h + r * 0.3, a + h + r * 0.3, col.lightened(0.05), Vector3.UP)
		for yb in [1.6, 3.2]:     # panel joints
			var o := Vector3(0, yb, 0) - r * 0.01
			m.quad(a + o, c + o, c + o + Vector3(0, 0.05, 0), a + o + Vector3(0, 0.05, 0), col.darkened(0.2), -r)
		m.obox(a - r * 0.1, hw.tangent(s), Vector3(0.45, 5.0, 0.5), col.darkened(0.12))   # pilaster
		s = s2
		k += 1
	m.instance(g_far, road_mat, "SoundWall", 900.0)


# ================================================================== neighborhood

func _house_mats(siding: Color, trim: Color, roof: Color, filler: bool) -> Dictionary:
	var key := "%s|%s|%s|%s" % [siding.to_html(), trim.to_html(), roof.to_html(), filler]
	if mats.has(key):
		return mats[key]
	var d := {}
	var sm := StandardMaterial3D.new()
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = siding
	sm.albedo_texture = _lap_texture()
	sm.uv1_triplanar = true
	sm.uv1_world_triplanar = true
	sm.uv1_scale = Vector3.ONE / 0.72
	sm.roughness = 0.85
	d["Siding"] = sm
	var tm := PropKit.material("Paint").duplicate() as StandardMaterial3D
	tm.albedo_color = trim
	d["Trim"] = tm
	for k in ["Roof", "RoofZ"]:
		var rm := PropKit.material("Paint").duplicate() as StandardMaterial3D
		rm.albedo_color = roof
		rm.roughness = 0.95
		d[k] = rm
	if filler:   # no interior behind the glass: a dark, glossy pane you can't see through
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.16, 0.2, 0.26)
		gm.roughness = 0.12
		gm.metallic_specular = 0.9
		d["Glass"] = gm
	var sc := StandardMaterial3D.new()
	sc.albedo_color = Color(0.06, 0.06, 0.07, 0.55)
	sc.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sc.roughness = 0.9
	d["Screen"] = sc
	mats[key] = d
	return d


var _lap_tex: ImageTexture
var _roof_mats := {}


## Asphalt shingles: courses of staggered tabs, grey-scale (the vertex colors
## carry each house's roof color). Rows run along x ("Roof", side gables) or
## along z ("RoofZ", front gables) in the triplanar top projection.
func _roof_mat(along_z: bool) -> StandardMaterial3D:
	if _roof_mats.has(along_z):
		return _roof_mats[along_z]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for y in n:
		for x in n:
			var u := y if along_z else x      # along the course
			var v := x if along_z else y      # across courses
			var course := v / 16
			var tab := (u + (8 if course % 2 else 0)) % 16
			var c := 0.9 + r.randf() * 0.1
			if v % 16 >= 14:
				c = 0.55                        # the shadow line under each course
			elif tab == 0:
				c = 0.72                        # the slot between tabs
			elif (u / 16 + course) % 5 == 0:
				c *= 0.9                        # the odd weathered tab
			img.set_pixel(x, y, Color(c, c, c))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / 1.0         # 16 px = 25 cm courses
	m.roughness = 0.95
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_roof_mats[along_z] = m
	return m


func _lap_texture() -> ImageTexture:
	if _lap_tex:
		return _lap_tex
	var img := Image.create(8, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		var v := 1.0
		var k := y % 16
		if k == 15:
			v = 0.62          # the shadow line under each board
		elif k == 14:
			v = 0.8
		elif k < 4:
			v = 0.97 + k * 0.01
		for x in 8:
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	_lap_tex = ImageTexture.create_from_image(img)
	return _lap_tex


var _baked := {}      # "prop|siding|trim|roof|filler" -> [[ArrayMesh, Material], ...]


## A house shell with its siding / trim / roof colors baked into the vertex
## colors, so every house shares the same few materials (and batches together).
func _house_node(prop: String, pos: Vector3, rot: float, siding: Color, trim: Color, roof: Color, filler: bool) -> Node3D:
	var key := "%s|%s|%s|%s|%s" % [prop, siding.to_html(), trim.to_html(), roof.to_html(), filler]
	if not _baked.has(key):
		var hm := _house_mats(Color.WHITE, Color.WHITE, Color.WHITE, filler)
		var tints := {"Siding": siding, "Trim": trim, "Roof": roof, "RoofZ": roof}
		var list: Array = []
		for part in PropKit._parts.get(prop, []):
			var kind := ""
			for k in ["Siding", "Trim", "Roof", "RoofZ", "Glass", "Screen"]:
				if part[1] == PropKit.material(k):
					kind = k
			var mesh: Mesh = part[0]
			var mat: Material = part[1]
			if tints.has(kind):
				var arr: Array = mesh.surface_get_arrays(0)
				var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
				var t: Color = tints[kind]
				for i in cols.size():
					cols[i] = Color(cols[i].r * t.r, cols[i].g * t.g, cols[i].b * t.b)
				arr[Mesh.ARRAY_COLOR] = cols
				var am := ArrayMesh.new()
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				mesh = am
				mat = hm["Siding"] if kind == "Siding" else (_roof_mat(kind == "RoofZ") if kind.begins_with("Roof") else PropKit.material("Paint"))
			elif hm.has(kind):
				mat = hm[kind]
			list.append([mesh, mat])
		_baked[key] = list
	var n := Node3D.new()
	n.name = prop
	n.position = pos
	n.rotation.y = rot
	for part in _baked[key]:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.material_override = part[1]
		n.add_child(mi)
	g_far.add_child(n)
	return n


## Swap a placed kit prop's surfaces to this house's tinted materials.
func _tint(node: Node3D, hm: Dictionary) -> void:
	var by_kind := {}
	for k in ["Siding", "Trim", "Roof", "RoofZ", "Glass", "Screen"]:
		by_kind[PropKit.material(k)] = k
	for mi in node.get_children():
		if mi is MeshInstance3D and by_kind.has(mi.material_override):
			var k: String = by_kind[mi.material_override]
			if hm.has(k):
				mi.material_override = hm[k]


func _neighborhood() -> void:
	var xm0 := r2.x + Highway.RB_R
	var xe := r2.x + 140.0
	var zm := r2.z
	var zp := r2.z + 70.0
	hood_rect = Rect2(r2.x - 70.0, r2.z - 50.0, 240.0, 170.0)
	var m := RoadMesh.new()
	# streets: [a, b] centerline + which sides get sidewalks [from, to] along the street
	_street(m, Vector3(xm0 - 1.0, 0, zm), Vector3(xe + 4.0, 0, zm), [[r2.x + 16.0, xe - 5.5], [r2.x + 16.0, xe - 7.0]])
	_street(m, Vector3(r2.x - 7.0, 0, zp), Vector3(xe + 4.0, 0, zp), [[r2.x + 7.0, xe - 7.0], [r2.x - 7.0, xe + 7.0]])
	_street(m, Vector3(r2.x, 0, zm + Highway.RB_R - 1.0), Vector3(r2.x, 0, zp + 4.0), [[zm + 16.0, zp + 7.0], [zm + 16.0, zp - 7.0]])
	_street(m, Vector3(xe, 0, zm - 4.0), Vector3(xe, 0, zp + 4.0), [[zm + 7.0, zp - 7.0], [zm + 7.0, zp + 7.0]])
	m.instance(g_road, road_mat, "Streets", 1500.0).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	street_names = [["MAGNOLIA ST", zm, "x"], ["PECAN ST", zp, "x"], ["DELTA AVE", r2.x, "z"], ["LEVEE RD", xe, "z"]]
	# the four rows of houses
	_row(MAGNOLIA_N, "Magnolia St", zm, -1, r2.x + 20.0, xe - 7.0)
	_row(MAGNOLIA_S, "Magnolia St", zm, 1, r2.x + 9.0, xe - 7.0)
	_row(PECAN_N, "Pecan St", zp, -1, r2.x + 9.0, xe - 7.0)
	_row(PECAN_S, "Pecan St", zp, 1, r2.x + 9.0, xe - 7.0)
	# west of Delta Ave: a little park with the neighborhood sign
	var pm := RoadMesh.new()
	pm.box(Vector3(r2.x - 38.0, (LAWN_Y + GROUND_Y) / 2, zm + 41.0), Vector3(62.0, LAWN_Y - GROUND_Y, 56.0), LAWN.lightened(0.04), true)
	pm.instance(g_road, road_mat, "Park", 1500.0)
	var mon := prop("HoodMonument", Vector3(r2.x - 20.0, LAWN_Y, zm + 17.0), -PI / 4, g_far)
	solid(Vector3(5.8, 1.8, 0.9), mon.position + Vector3(0, 0.9, 0), -PI / 4)
	var ml := label("MAGNOLIA HEIGHTS", mon.position + Basis(Vector3.UP, -PI / 4) * Vector3(0, 0.82, 0.4), 96,
			Color(0.2, 0.22, 0.2), -PI / 4, g_dyn, 0.0085, 150.0)
	ml.outline_size = 0
	var ms := label("EST. 1958", mon.position + Basis(Vector3.UP, -PI / 4) * Vector3(0, 0.5, 0.4), 40,
			Color(0.3, 0.3, 0.28), -PI / 4, g_dyn, 0.0085, 150.0)
	ms.outline_size = 0
	for k in 7:
		prop(["TreeOak", "TreeSmall", "TreePine"][k % 3], Vector3(r2.x - 60.0 + k * 7.0, LAWN_Y, zm + 55.0 + (k % 2) * 8.0),
				rng.randf_range(0, TAU), g_far, rng.randf_range(0.8, 1.15))
	prop("Bench", Vector3(r2.x - 30.0, LAWN_Y, zm + 30.0), PI * 0.25, g_mid)
	# utility poles + wires down the north side of both streets
	_pole_line(zm - 4.8, r2.x + 22.0, xe - 4.0)
	_pole_line(zp - 4.8, r2.x - 2.0, xe - 4.0)
	# street name signs + stop signs at the corners
	_corner_sign(Vector3(xe + 5.0, WALK_Y, zm + 5.0), "MAGNOLIA ST", "LEVEE RD", true)
	_corner_sign(Vector3(xe - 5.0, WALK_Y, zp - 5.0), "PECAN ST", "LEVEE RD", true)
	_corner_sign(Vector3(r2.x + 5.0, WALK_Y, zp - 5.0), "PECAN ST", "DELTA AVE", true)
	_corner_sign(Vector3(r2.x + 16.0, WALK_Y, zm + 8.0), "MAGNOLIA ST", "DELTA AVE", false)
	_tree_rects.append(hood_rect.grow(4.0))


## A straight residential street: road, curbs, grass strip, sidewalks (+ curb ramps).
func _street(m, a: Vector3, bb: Vector3, walks: Array) -> void:
	var along_x := absf(bb.x - a.x) > absf(bb.z - a.z)
	var L := (bb - a).length()
	var c := (a + bb) / 2.0
	var sz := Vector3(L, 0.0 - GROUND_Y, 8.0) if along_x else Vector3(8.0, 0.0 - GROUND_Y, L)
	m.box(c + Vector3(0, GROUND_Y / 2.0, 0), sz, ASPHALT_L, true)
	# double yellow
	for o in [-0.1, 0.1]:
		var lc := c + (Vector3(0, 0.004, o) if along_x else Vector3(o, 0.004, 0))
		m.box(lc, Vector3(L - 16.0, 0.008, 0.1) if along_x else Vector3(0.1, 0.008, L - 16.0), LINE_Y)
	for side in [-1, 1]:
		var span: Array = walks[0 if side < 0 else 1]
		var u0: float = span[0]
		var u1: float = span[1]
		var mid := (u0 + u1) / 2.0
		var len := u1 - u0
		var off := func(dist: float) -> Vector3:
			return Vector3(mid, 0, c.z + side * dist) if along_x else Vector3(c.x + side * dist, 0, mid)
		var szf := func(w: float, h: float) -> Vector3:
			return Vector3(len, h, w) if along_x else Vector3(w, h, len)
		m.box(off.call(4.1) + Vector3(0, (0.14 + GROUND_Y) / 2, 0), szf.call(0.2, 0.14 - GROUND_Y), CONCRETE, true)   # curb
		m.box(off.call(4.85) + Vector3(0, (LAWN_Y + GROUND_Y) / 2, 0), szf.call(1.3, LAWN_Y - GROUND_Y), LAWN, true)
		m.box(off.call(6.25) + Vector3(0, (WALK_Y + GROUND_Y) / 2, 0), szf.call(1.5, WALK_Y - GROUND_Y), SIDEWALK, true)
		var k := 0.0
		while k < len - 1.5:   # sidewalk joints
			var jp: Vector3 = off.call(6.25)
			jp = Vector3(u0 + k, WALK_Y + 0.003, jp.z) if along_x else Vector3(jp.x, WALK_Y + 0.003, u0 + k)
			m.box(jp, Vector3(0.03, 0.006, 1.5) if along_x else Vector3(1.5, 0.006, 0.03), SIDEWALK.darkened(0.15))
			k += 1.5
		var ramp := solid(szf.call(0.7, 0.05), off.call(3.85) + Vector3(0, 0.05, 0), 0.0, g_road,
				(side * -0.22) if along_x else 0.0)
		if not along_x:
			ramp.rotation = Vector3(0, 0, side * 0.22)


## A row of lots along a street. side = -1: north of an east-west street (the
## houses face south, +z), +1: south of it (they face north).
func _row(lots: Array, street: String, zc: float, side: int, x0: float, x1: float) -> void:
	var total := 0.0
	for l in lots:
		total += l[1]
	var spare := maxf((x1 - x0) - total, 0.0) / lots.size()
	var x := x0
	_lot_mesh = RoadMesh.new()
	for l in lots:
		var w: float = l[1] + spare
		_lot(l, street, Vector3(x + w / 2.0, 0, zc), side, w)
		x += w
	_lot_mesh.instance(g_road, road_mat, "Lots", 900.0).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _lot(l: Array, street: String, sc: Vector3, side: int, w: float) -> void:
	var type: String = l[0]
	var number: int = l[2]
	var id: String = l[3]
	var extras: String = l[5]
	var T: Dictionary = layout.types[type]
	var rot := 0.0 if side < 0 else PI                 # house front (+z local) toward the street
	var fwd := Vector3(0, 0, -side)                     # from the house toward the street
	var lot_front := sc.z + side * 7.0                  # sidewalk outer edge
	var lot_back := sc.z + side * (7.0 + LOT_D)
	var house_pos := Vector3(sc.x, 0.0, sc.z + side * SETBACK)
	var xf := Transform3D(Basis(Vector3.UP, rot), house_pos)
	var H := func(p: Vector3) -> Vector3:
		return xf * p
	var HW: float = T.W
	# lawn (with the driveway and walkway cut out), driveway, walkway
	var has_drive := extras.contains("d")
	var dside := 1.0 if (number % 4) < 2 else -1.0            # driveway left or right of the house
	var drive_x := sc.x + dside * (HW / 2.0 + 2.2) * (1.0 if side < 0 else -1.0)
	if has_drive and absf(drive_x - sc.x) + 1.6 > w / 2.0:
		has_drive = false
	var entry: Array = T.entry
	var walk_x: float = (H.call(Vector3(entry[0], 0, 0))).x
	var cuts: Array = [Rect2(walk_x - 0.65, minf(lot_front, sc.z + side * (SETBACK - float(T.porch_front))), 1.3,
			absf(lot_front - (sc.z + side * (SETBACK - float(T.porch_front)))))]
	if has_drive:
		var dz0 := lot_front
		var dz1 := sc.z + side * (SETBACK + 7.0)
		cuts.append(Rect2(drive_x - 1.6, minf(dz0, dz1), 3.2, absf(dz1 - dz0)))
	var m = _lot_mesh
	var lot := Rect2(sc.x - w / 2.0, minf(lot_front, lot_back), w, LOT_D)
	for r in _subtract(lot, cuts):
		m.box(Vector3(r.get_center().x, (LAWN_Y + GROUND_Y) / 2, r.get_center().y), Vector3(r.size.x, LAWN_Y - GROUND_Y, r.size.y),
				LAWN.darkened(rng.randf_range(0.0, 0.05)), true)
	var wr: Rect2 = cuts[0]
	m.box(Vector3(wr.get_center().x, (LAWN_Y + 0.02 + GROUND_Y) / 2, wr.get_center().y), Vector3(wr.size.x, LAWN_Y + 0.02 - GROUND_Y, wr.size.y),
			Color(0.66, 0.64, 0.6) if type != "ranch" else Color(0.6, 0.57, 0.52), true)
	if type == "ranch":   # stepping stones look
		var zz := wr.position.y + 0.3
		while zz < wr.end.y - 0.3:
			m.box(Vector3(wr.get_center().x, LAWN_Y + 0.025, zz), Vector3(1.2, 0.01, 0.05), Color(0.45, 0.43, 0.4))
			zz += 0.6
	if has_drive:
		var dr: Rect2 = cuts[1]
		m.box(Vector3(dr.get_center().x, (LAWN_Y + 0.02 + GROUND_Y) / 2, dr.get_center().y), Vector3(dr.size.x, LAWN_Y + 0.02 - GROUND_Y, dr.size.y),
				Color(0.64, 0.63, 0.6), true)
		# the apron across the grass strip + a crack or two
		m.box(Vector3(drive_x, (LAWN_Y + 0.02 + GROUND_Y) / 2, sc.z + side * 4.85), Vector3(3.2, LAWN_Y + 0.02 - GROUND_Y, 1.3),
				Color(0.64, 0.63, 0.6), true)
		m.box(Vector3(drive_x + 0.3, LAWN_Y + 0.025, dr.get_center().y), Vector3(0.04, 0.01, dr.size.y * 0.6), Color(0.45, 0.44, 0.42))
		if extras.contains("c"):
			var model: String = PARKED[number % PARKED.size()]
			parked_car(model, Vector3(drive_x, LAWN_Y + 0.02, sc.z + side * (SETBACK + 2.0)), rot + PI if number % 2 else rot)
			solid(Vector3(2.0, 1.6, 4.8), Vector3(drive_x, LAWN_Y + 0.8, sc.z + side * (SETBACK + 2.0)), 0.0)
	# the house
	var buy := id != ""
	var sidc: Color = SIDING[int(l[4]) % SIDING.size()]
	var trim := Color(0.97, 0.97, 0.95)
	if type == "shotgun" and number % 3 == 1:
		trim = Color(0.62, 0.1, 0.08)
	if type == "tin" and number % 2 == 0:
		sidc = Color(0.96, 0.96, 0.94)
	var roof: Color = ROOFS[number % ROOFS.size()]
	_house_node("House_" + type, house_pos, rot, sidc, trim, roof, not buy)
	var hroot := Node3D.new()
	hroot.name = "House_%s_%d" % [street.replace(" ", ""), number]
	hroot.transform = xf
	g_dyn.add_child(hroot)
	var colls: Array = T.shell_colliders if buy else T.filler_colliders
	_colliders(hroot, colls)
	# bushes along the front, bins, mailbox, trees, fences, back yard
	for bp in T.get("bushes", []):
		prop(["Bush", "BushDark", "BushFlower"][(number + int(bp[0] * 7)) % 3], H.call(Vector3(bp[0], LAWN_Y, bp[1])), rng.randf_range(0, TAU))
	var mb_pos := Vector3((drive_x if has_drive else walk_x) + 1.2 * (1 if number % 2 else -1), LAWN_Y, sc.z + side * 4.7)
	prop("Mailbox", mb_pos, rot)
	solid(Vector3(0.3, 1.3, 0.3), mb_pos + Vector3(0, 0.65, 0))
	var bins_at: Vector3 = H.call(Vector3((HW / 2.0 + 0.7) * (-dside if side < 0 else dside), LAWN_Y, -1.5))
	prop(["TrashBin_Green", "TrashBin_Blue", "TrashBin_Black"][number % 3], bins_at, rot + rng.randf_range(-0.3, 0.3))
	prop("TrashBin_Blue" if number % 3 != 1 else "TrashBin_Black", bins_at + Basis(Vector3.UP, rot) * Vector3(0, 0, -0.8), rot + 0.2)
	if extras.contains("t"):
		var tp: Vector3 = H.call(Vector3(-HW / 2.0 + 1.0, LAWN_Y, 3.6))
		prop("TreeOak", tp, rng.randf_range(0, TAU), g_far, rng.randf_range(0.85, 1.1))
		solid(Vector3(0.6, 3.0, 0.6), tp + Vector3(0, 1.5, 0))
	if extras.contains("p"):
		var pp: Vector3 = H.call(Vector3(HW / 2.0 + 2.8, LAWN_Y, 2.0))
		if absf(pp.x - sc.x) < w / 2.0 - 1.0:
			prop("TreePine", pp, rng.randf_range(0, TAU), g_far, rng.randf_range(0.9, 1.25))
			solid(Vector3(0.6, 3.0, 0.6), pp + Vector3(0, 1.5, 0))
	if extras.contains("f"):   # white picket fence along the front, gaps for the walk and drive
		var fz := sc.z + side * 7.3
		var fx := sc.x - w / 2.0 + 1.2
		while fx < sc.x + w / 2.0 - 1.1:
			if absf(fx - walk_x) > 1.9 and (not has_drive or absf(fx - drive_x) > 2.9):
				prop("FencePicket", Vector3(fx, LAWN_Y, fz), rot)
			fx += 2.4
	if extras.contains("w"):   # wood privacy fence round the back yard
		var bz := lot_back - side * 0.3
		var fx2 := sc.x - w / 2.0 + 1.2
		while fx2 < sc.x + w / 2.0 - 1.1:
			prop("FenceWood", Vector3(fx2, LAWN_Y, bz), rot + PI)
			fx2 += 2.4
		solid(Vector3(w, 1.9, 0.2), Vector3(sc.x, LAWN_Y + 0.95, bz))
	if extras.contains("b"):
		var by: Vector3 = H.call(Vector3(rng.randf_range(-1.5, 1.5), LAWN_Y, -float(T.D) - 3.5))
		var what := ["Grill", "LawnChair", "Doghouse", "KidBike"]
		prop(what[number % 4], by, rng.randf_range(0, TAU))
		prop("LawnChair", by + Vector3(1.4, 0, 0.6), rng.randf_range(0, TAU))
		prop("TreeSmall" if number % 2 else "TreePine", H.call(Vector3(HW / 2.0 - 1.0, LAWN_Y, -float(T.D) - 6.0)),
				rng.randf_range(0, TAU), g_far, rng.randf_range(0.7, 1.0))
	# house number (over the porch / by the door)
	var num: Array = T.number
	var nl := label(str(number), H.call(Vector3(num[0], num[1], num[2] + 0.01)), 64,
			Color(0.08, 0.08, 0.08) if type != "shotgun" else Color(0.95, 0.95, 0.9), rot, g_dyn, 0.004, 45.0)
	nl.outline_size = 0
	# the front door (and the shotgun's screen door): hinged leaves that can swing
	var dd: Dictionary = T.door
	var door := _door(DOORS[type] if not (type == "bungalow" and number % 3 == 0) else "Door_Blue", H.call(Vector3(dd.hinge[0], dd.hinge[1], dd.hinge[2])), rot, float(dd.w), not buy)
	var screen: Node3D = null
	if T.has("screen_door"):
		var sd: Dictionary = T.screen_door
		screen = _door("Door_Screen", H.call(Vector3(sd.hinge[0], sd.hinge[1], sd.hinge[2])), rot, float(sd.w), not buy)
	var h := {"id": id, "type": type, "street": street, "number": number, "address": "%d %s" % [number, street],
		"xf": xf, "rot": rot, "door": door, "screen": screen, "door_open": 0.0, "interior": null, "lights": [],
		"entry": H.call(Vector3(entry[0], entry[1] + 0.1, entry[2])), "mailbox": mb_pos, "mailbox_label": null,
		"sign": null, "sign_labels": [], "spawn": Vector3.ZERO, "spawn_yaw": 0.0, "front": fwd}
	var body: StaticBody3D = door.get_node("Body")
	if buy:
		_buyable(h, l, sc, side, rot, walk_x, H)
	else:
		interact(body, "hood_knock", houses.size(), "[E] Knock")
	houses.append(h)


func _door(nm: String, hinge: Vector3, rot: float, w: float, fixed := false) -> Node3D:
	var piv := Node3D.new()
	piv.name = "Door"
	piv.position = hinge
	piv.rotation.y = rot
	g_dyn.add_child(piv)
	if fixed:   # a shut filler door never moves: its mesh goes in the static batch
		PropKit.place(nm, g_mid, hinge, rot)
	else:
		var leaf := PropKit.place(nm, piv, Vector3.ZERO, 0.0)
		for mi in leaf.get_children():
			if mi is MeshInstance3D:
				mi.layers = SKY
				mi.visibility_range_end = MID_RANGE
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sb := solid(Vector3(w, 2.05, 0.08), Vector3(w / 2.0, 1.03, 0.0), 0.0, piv)
	sb.name = "Body"
	return piv


func _colliders(parent: Node3D, list: Array) -> void:
	for c in list:
		var cc: Array = c.c
		var ss: Array = c.s
		solid(Vector3(ss[0], ss[1], ss[2]), Vector3(cc[0], cc[1], cc[2]), 0.0, parent, float(c.get("rx", 0.0)))


## A house that's for sale: its interior, lights, the realtor's sign, the spawn by the bed.
func _buyable(h: Dictionary, l: Array, sc: Vector3, side: int, rot: float, walk_x: float, H: Callable) -> void:
	var id: String = h.id
	buyable[id] = houses.size()
	var I: Dictionary = layout.interiors[id]
	var inode := Node3D.new()
	inode.name = "Interior_" + id
	inode.transform = h.xf
	g_dyn.add_child(inode)
	PropKit.place("Int_" + id, inode, Vector3.ZERO, 0.0)
	_colliders(inode, I.colliders)
	for lt in I.lights:
		var o := OmniLight3D.new()
		o.position = Vector3(lt[0], lt[1], lt[2])
		o.omni_range = float(lt[3])
		o.light_energy = float(lt[4])
		o.light_color = Color(1.0, 0.93, 0.8)
		o.light_cull_mask = 1 | INT_LAYER
		o.shadow_enabled = false
		o.distance_fade_enabled = true
		o.distance_fade_begin = INT_RANGE - 15.0
		o.distance_fade_length = 10.0
		inode.add_child(o)
		h.lights.append(o)
	h.interior = inode
	var sp: Array = I.spawn
	h.spawn = h.xf * Vector3(sp[0], sp[1], sp[2])
	h.spawn_yaw = float(sp[3]) + rot
	h.bed = h.xf * Vector3(I.bed[0], I.bed[1], I.bed[2])
	h.clock = h.xf * Vector3(I.clock[0], I.clock[1], I.clock[2])
	h.price = float(Rules.HOUSES[id].price)
	# the realtor's FOR SALE sign on the front lawn, beside the walk
	var sx := walk_x + (2.2 if h.number % 2 == 0 else -2.2)
	var spos := Vector3(sx, LAWN_Y, sc.z + side * 8.6)
	var sign := Node3D.new()
	sign.name = "ForSale_" + id
	sign.position = spos
	sign.rotation.y = rot + PI                   # face the street
	g_dyn.add_child(sign)
	var sp_node := PropKit.place("ForSaleSign", sign, Vector3.ZERO, 0.0)
	for mi in sp_node.get_children():
		if mi is MeshInstance3D:
			mi.layers = SKY
			mi.visibility_range_end = MID_RANGE
	for face in [1.0, -1.0]:
		var yaw := 0.0 if face > 0 else PI
		var t := label("FOR SALE", Vector3(0, 1.18, face * 0.03), 44, Color(0.75, 0.06, 0.08), yaw, sign, 0.0042, 60.0)
		var p := label(RealtorUI.price_str(h.price), Vector3(0, 0.97, face * 0.03), 40, Color(0.1, 0.1, 0.12), yaw, sign, 0.0042, 60.0)
		var r := label("MAXED OUT REALTY", Vector3(0, 1.31, face * 0.03), 22, Color(1, 1, 1), yaw, sign, 0.0042, 40.0)
		var o := label("OPEN HOUSE", Vector3(0, 1.7, face * 0.024), 26, Color(1, 1, 1), yaw, sign, 0.0042, 40.0)
		h.sign_labels.append([t, p, r, o])
	var sb := solid(Vector3(1.2, 1.9, 0.3), Vector3(0, 0.95, 0), 0.0, sign)
	interact(sb, "hood_sign", buyable[id], "[E] %s — %s" % [h.address, Rules.money(h.price)])
	h.sign = sign
	h.sign_body = sb
	# a name plate on the mailbox for whoever buys it
	var mbl := label("", h.mailbox + Vector3(0, 1.12, 0) + Basis(Vector3.UP, rot) * Vector3(0.125, 0, 0), 28,
			Color(1, 1, 1), rot + PI / 2, g_dyn, 0.004, 30.0)
	mbl.outline_size = 6
	mbl.outline_modulate = Color(0, 0, 0, 0.8)
	h.mailbox_label = mbl
	# for-sale houses stand open (open house)
	h.door_open = 1.62
	h.door.rotation.y = rot + h.door_open
	if h.screen:
		h.screen.rotation.y = rot - 1.7


## Rects of `r` not covered by any rect in `cuts` (axis-aligned, simple sweep).
static func _subtract(r: Rect2, cuts: Array) -> Array:
	var out: Array = [r]
	for c in cuts:
		var nxt: Array = []
		for p in out:
			var cc: Rect2 = p.intersection(c)
			if cc.size.x <= 0.001 or cc.size.y <= 0.001:
				nxt.append(p)
				continue
			if cc.position.x > p.position.x:
				nxt.append(Rect2(p.position.x, p.position.y, cc.position.x - p.position.x, p.size.y))
			if cc.end.x < p.end.x:
				nxt.append(Rect2(cc.end.x, p.position.y, p.end.x - cc.end.x, p.size.y))
			if cc.position.y > p.position.y:
				nxt.append(Rect2(cc.position.x, p.position.y, cc.size.x, cc.position.y - p.position.y))
			if cc.end.y < p.end.y:
				nxt.append(Rect2(cc.position.x, cc.end.y, cc.size.x, p.end.y - cc.end.y))
		out = nxt
	return out


func _pole_line(z: float, x0: float, x1: float) -> void:
	var xs: Array = []
	var x := x0
	while x <= x1:
		xs.append(x)
		x += 36.0
	var attach: Array = layout.props.get("pole_wires", [])
	var wires := RoadMesh.new()
	var prev: Array = []
	for i in xs.size():
		var nm := "UtilityPoleLight" if i % 2 == 0 else ("UtilityPoleTx" if i % 3 == 1 else "UtilityPole")
		var pos := Vector3(xs[i], LAWN_Y, z)
		prop(nm, pos, -PI / 2, g_far)     # crossarm across the line, the light arm over the street
		solid(Vector3(0.3, 10.0, 0.3), pos + Vector3(0, 5.0, 0))
		# attach points are in the pole's frame (crossarm along its x = world z here)
		var pts: Array = []
		for a in attach:
			pts.append(pos + Vector3(0.0, a[1], a[0]))
		if not prev.is_empty():
			for k in pts.size():
				_wire(wires, prev[k], pts[k], 0.5 if k < 3 else 0.35)
		prev = pts
	wires.instance(g_far, road_mat, "Wires", 400.0)


## A sagging wire between two points: a thin cross-shaped ribbon, 8 segments.
func _wire(m, a: Vector3, c: Vector3, sag: float) -> void:
	var n := 8
	var col := Color(0.08, 0.08, 0.09)
	var prev := a
	for k in range(1, n + 1):
		var t := float(k) / n
		var p := a.lerp(c, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
		var dirv := (p - prev).normalized()
		var side := dirv.cross(Vector3.UP).normalized() * 0.02
		var up := Vector3(0, 0.02, 0)
		m.quad(prev - up, p - up, p + up, prev + up, col, side)
		m.quad(prev - side, p - side, p + side, prev + side, col, Vector3.UP)
		prev = p


func _corner_sign(pos: Vector3, a: String, bb: String, stop: bool) -> void:
	prop("StreetSign", pos, 0.0)
	solid(Vector3(0.15, 3.0, 0.15), pos + Vector3(0, 1.5, 0))
	for face in [[0.0, a, Vector3(0, 2.85, 0.03)], [PI, a, Vector3(0, 2.85, -0.03)],
			[PI / 2, bb, Vector3(0.03, 2.6, 0)], [-PI / 2, bb, Vector3(-0.03, 2.6, 0)]]:
		var l := label(face[1], pos + face[2], 36, Color(1, 1, 1), face[0], g_dyn, 0.005, 60.0)
		l.outline_size = 0
	if stop:
		var sp := pos + Vector3(0.9, 0, 0.9)
		prop("StopSign", sp, PI * 0.75)
		var sl := label("STOP", sp + Vector3(0, 2.3, 0) + Basis(Vector3.UP, PI * 0.75) * Vector3(0, 0, 0.07), 60,
				Color(1, 1, 1), PI * 0.75, g_dyn, 0.005, 60.0)
		sl.outline_size = 0


# ================================================================== taxis + downtown link

func _taxi_stands() -> void:
	# downtown: the south sidewalk at the east end of the block, facing the road
	var so := Vector3(0, 0, 240)
	var spots := [[so + Vector3(36.5, 0.12, 7.2), PI, "DOWNTOWN"], [Vector3(r2.x + 22.0, WALK_Y, r2.z + 6.3), PI, "MAGNOLIA HEIGHTS"]]
	for i in spots.size():
		var pos: Vector3 = spots[i][0]
		var rot: float = spots[i][1]
		var n := Node3D.new()
		n.name = "Taxi_%d" % i
		n.position = pos
		n.rotation.y = rot
		g_dyn.add_child(n)
		var tp := PropKit.place("TaxiStand", n, Vector3.ZERO, 0.0)
		for mi in tp.get_children():
			if mi is MeshInstance3D:
				mi.layers = SKY
				mi.visibility_range_end = 400.0
		var sb := solid(Vector3(3.2, 2.6, 1.3), Vector3(0, 1.3, -0.35), 0.0, n)
		interact(sb, "hood_taxi", i, "[E] Call a ride (TAXI · RIDESHARE)")
		var pole := solid(Vector3(0.7, 3.2, 0.5), Vector3(1.9, 1.6, 0.2), 0.0, n)
		interact(pole, "hood_taxi", i, "[E] Call a ride (TAXI · RIDESHARE)")
		var t := label("TAXI · RIDESHARE", Vector3(0, 2.7, 0.42), 56, Color(0.1, 0.1, 0.1), 0.0, n, 0.005, 120.0)
		t.outline_size = 0
		var t2 := label("TAXI", Vector3(1.9, 2.83, 0.24), 48, Color(0.1, 0.1, 0.1), 0.0, n, 0.005, 120.0)
		t2.outline_size = 0
		var t3 := label(spots[i][2], Vector3(0, 2.25, -0.66), 34, Color(0.95, 0.95, 0.95), 0.0, n, 0.005, 40.0)
		t3.outline_size = 6
		var front := Basis(Vector3.UP, rot) * Vector3(0, 0, 1)
		taxi.append({"pos": pos + front * 1.4 + Vector3(0, 0.15, 0), "yaw": rot + PI, "name": spots[i][2]})
		# a cab waiting at the curb
		var cab_at := pos + front * 3.4
		parked_car("TCar_Taxi", Vector3(cab_at.x - 2.0, 0.0, cab_at.z), PI / 2, g_dyn)
		solid(Vector3(4.6, 1.5, 1.9), Vector3(cab_at.x - 2.0, 0.75, cab_at.z), 0.0, g_road)
	# spawn facing along the sidewalk: downtown looks west down the block, the hood east down Magnolia
	taxi[0].yaw = PI / 2
	taxi[1].yaw = -PI / 2


## The gap through the downtown east end block: road + sidewalks out to the roundabout.
func _downtown_gap() -> void:
	var m := RoadMesh.new()
	var z := 240.0
	var x0 := 40.0
	var x1 := hw.roundabout_dt.x - Highway.RB_R + 0.5
	m.box(Vector3((x0 + x1) / 2, GROUND_Y / 2 - 0.1, z), Vector3(x1 - x0, -GROUND_Y + 0.2, 10.0), ASPHALT_L, true)
	for side in [-1.0, 1.0]:
		m.box(Vector3((x0 + x1) / 2, 0.004, z + side * 0.1), Vector3(x1 - x0 - 2.0, 0.008, 0.1), LINE_Y)
		m.box(Vector3((x0 + 53.0) / 2, (WALK_Y + GROUND_Y) / 2, z + side * 7.25), Vector3(53.0 - x0, WALK_Y - GROUND_Y, 4.5), SIDEWALK, true)
		m.box(Vector3((53.0 + x1) / 2, (WALK_Y + GROUND_Y) / 2, z + side * 6.2), Vector3(x1 - 53.0, WALK_Y - GROUND_Y, 2.4), SIDEWALK, true)
		var ramp := solid(Vector3(x1 - x0, 0.05, 0.6), Vector3((x0 + x1) / 2, 0.04, z + side * 4.8), 0.0, g_road, side * -0.2)
		ramp.name = "CurbRamp"
		# nobody walks off the ends of the sidewalk into the tower field
		solid(Vector3(0.3, 3.0, 5.0), Vector3(x1, 1.5, z + side * 7.6), 0.0, g_road)
	m.instance(g_road, road_mat, "DowntownGap", 1500.0)
	for k in 3:
		prop("StreetLamp", Vector3(58.0 + k * 11.0, WALK_Y, 240.0 + 5.8 * (1 if k % 2 else -1)), 0.0 if k % 2 else PI, g_far)


func _scatter_trees() -> void:
	var kinds := ["TreeOak", "TreePine", "TreeSmall", "TreePine", "TreeOak"]
	var placed := 0
	var tries := 0
	while placed < 230 and tries < 4000:
		tries += 1
		var p := Vector3(rng.randf_range(60.0, 1200.0), GROUND_Y, rng.randf_range(240.0, 700.0))
		var loc: Vector2 = hw.locate(p)
		if absf(loc.y) < 30.0 or absf(loc.y) > 280.0:
			continue
		if p.x < 60.0 and absf(p.z - 240.0) < 30.0:
			continue
		var ok := true
		for tr in _tree_rects:
			if (tr as Rect2).has_point(Vector2(p.x, p.z)):
				ok = false
		for bl in _tree_blockers:
			if Vector2(p.x, p.z).distance_to(bl[0]) < bl[1]:
				ok = false
				break
		if not ok:
			continue
		prop(kinds[placed % kinds.size()], p, rng.randf_range(0, TAU), g_far, rng.randf_range(0.8, 1.35))
		placed += 1
	# a few low bushes along the sound wall on the neighborhood side
	var s := 620.0
	while s < hw.s_portal_e - 80.0:
		prop("BushDark" if int(s) % 2 else "Bush", hw.point(s, 26.5, GROUND_Y), rng.randf_range(0, TAU), g_mid, 1.4)
		s += 9.0


## From out here (330 m+) the detailed downtown block (thousands of small
## batches) is swapped for this: the two rows of buildings as banded boxes.
## HoodController gives the real block a matching visibility range.
func _downtown_impostor() -> void:
	var m := RoadMesh.new()
	var top := 31.4
	var rows := [[b.street.NORTH, 222.0, 230.6, 231.0], [b.street.SOUTH, 249.4, 258.0, 249.0]]
	for row in rows:
		for st in row[0]:
			var x: float = st.x
			var wall: Color = b.street.UPPER_WALL[st.upper]
			var z0: float = row[1]
			var z1: float = row[2]
			m.box(Vector3(x, top / 2, (z0 + z1) / 2), Vector3(12.0, top, z1 - z0), wall, false, wall.darkened(0.2))
			var face: float = row[3]
			var out := -1.0 if face < 240.0 else 1.0
			for f in 9:        # window bands facing the street
				var y := 6.2 + f * 3.0
				m.quad(Vector3(x - 5.0, y - 0.9, face - out * -0.02), Vector3(x + 5.0, y - 0.9, face - out * -0.02),
						Vector3(x + 5.0, y + 0.9, face - out * -0.02), Vector3(x - 5.0, y + 0.9, face - out * -0.02),
						Color(0.45, 0.58, 0.72), Vector3(0, 0, -out))
			m.box(Vector3(x, 2.2, face), Vector3(11.0, 4.4, 0.3), Color(0.35, 0.37, 0.4))
	for sx in [-1.0, 1.0]:   # the end blocks
		m.box(Vector3(sx * 46.4, top / 2, 240.0 + (0.0 if sx < 0 else -14.75)), Vector3(12.4, top, 40.0 if sx < 0 else 10.5),
				Color(0.6, 0.58, 0.55), false)
		if sx > 0:
			m.box(Vector3(46.4, top / 2, 254.75), Vector3(12.4, top, 10.5), Color(0.6, 0.58, 0.55), false)
	var mi := m.instance(g_road, road_mat, "DowntownImpostor")
	mi.visibility_range_begin = 330.0
	mi.visibility_range_begin_margin = 20.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ================================================================== batching

func _finish() -> void:
	for g in [g_far, g_mid, g_road]:
		for mi in g.find_children("*", "MeshInstance3D", true, false):
			mi.layers = SKY
	Batcher.merge_static(g_far, [], 90.0)
	Batcher.merge_static(g_mid, [], 60.0)
	for mi in g_far.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null and mi.visibility_range_end <= 0.0:
			mi.visibility_range_end = FAR_RANGE
			mi.visibility_range_end_margin = 40.0
	for mi in g_mid.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null:
			mi.visibility_range_end = MID_RANGE
			mi.visibility_range_end_margin = 20.0
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# interiors: each merged on its own (their lamps must not spill into other houses)
	for h in houses:
		if h.interior == null:
			continue
		var inode: Node3D = h.interior
		for mi in inode.find_children("*", "MeshInstance3D", true, false):
			mi.layers = 1 | INT_LAYER
		Batcher.merge_static(inode, [], 0.0)
		for mi in inode.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh != null:
				mi.visibility_range_end = INT_RANGE
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# drop the emptied mesh holders' names from the prop tree (keeps the scene tidy)
	for g in [g_far, g_mid]:
		for n in g.get_children():
			if n is Node3D and not (n is MeshInstance3D) and n.get_child_count() > 0:
				var all_empty := true
				for c in n.get_children():
					if not (c is MeshInstance3D and c.mesh == null):
						all_empty = false
						break
				if all_empty:
					n.queue_free()


# ================================================================== queries

func in_hood(p: Vector3) -> bool:
	return hood_rect.has_point(Vector2(p.x, p.z))
