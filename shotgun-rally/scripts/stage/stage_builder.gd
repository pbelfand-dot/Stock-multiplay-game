extends Node3D
## Turns a StageGen into the world: the gravel road (crowned, with two worn
## wheel tracks, loose stones on the crown and out toward the edges where the
## grip is worse (StageGen.lane_grip), berms of thrown-out gravel on the outside
## of the bends), spectators behind tape at the jumps, the start and finish and
## some slow corners, flat grass run-off then rolling ground out to ~75 m, a low-poly
## forest that crowds the INSIDE of corners (so you can't see round them:
## that's what the notes are for), rocks on the inside of "don't cut" corners,
## mud puddles, the start / finish arches, and the sky and sun.
## Every surface the tyres can touch says what it is (meta "surface").

const MeshBuf = preload("res://scripts/stage/mesh_buf.gd")
const Crowd = preload("res://scripts/stage/crowd.gd")

const GRAVEL := Color(0.71, 0.6, 0.44)
const TRACK := Color(0.6, 0.5, 0.36)
const VERGE := Color(0.5, 0.52, 0.3)
const GRASS := Color(0.34, 0.54, 0.21)
const GRASS_FAR := Color(0.28, 0.46, 0.19)
const DIRT := Color(0.45, 0.36, 0.25)
## Road cross-section at the normal width (5.6 m): [d, height, colour of the strip
## to the next point]. The edges move with the road's width (_road_x); the
## crown and the two wheel tracks don't (the cars are the same width)
const ROAD_X := [[-3.1, -0.03, VERGE], [-2.8, 0.0, GRAVEL], [-1.25, 0.04, TRACK], [-0.55, 0.05, GRAVEL],
	[0.55, 0.05, TRACK], [1.25, 0.04, GRAVEL], [2.8, 0.0, VERGE], [3.1, -0.03, VERGE]]
## Ground beyond the road, each side, at the normal width (moves out with a
## wider road): [d, height above the road, noise amplitude]. Flush with the
## road's edge and nearly flat for ~6 m past it: slide wide and you're on the
## grass with time to catch it (no ditch to drop a wheel in, no bank to trip
## on); the hills only start further out.
const GROUND_X := [[2.9, -0.03, 0.0], [5.0, -0.05, 0.0], [8.5, -0.04, 0.06], [12.0, 0.05, 0.25],
	[18.0, 0.15, 0.6], [30.0, 0.35, 1.4], [50.0, 0.7, 2.4], [78.0, 1.2, 3.6], [112.0, 1.8, 4.6], [154.0, 2.4, 5.6]]
const TREE_LINE := 7.6              # m off the centreline (at the normal width) where the trees start

const CHUNK := 160.0                # trees are grouped per this much road ...
const TREE_DRAW := 520.0            # ... and a group further away than this isn't drawn
var mood := "day"                  # the light (_environment): set before build
var _range: MeshInstance3D      # the ranges on the horizon (they keep their distance: _process)
var _mountain_y := 0.0
var _horizon := Color(0.72, 0.82, 0.9)   # the sky at the horizon (the mountains fade into it)
const FAR_DRAW := 340.0             # the far belt (76-150 m off the road): drawn closer than this (the fog has the rest)
const FERN_DRAW := 150.0            # the ferns and undergrowth along the verges

var st
var start_clocks: Array = []        # the countdown boards at the start line (driver's side, co-driver's side)
var tree_count := 0
var crowd_count := 0
var people_count := 0
var _clearings: Array = []          # [Vector2 (x, z), radius]: no trees there (a crowd stands there)
var _noise := FastNoiseLite.new()
var _road_grid := {}                # 20 m cells -> [sample indices], to keep trees off the road
var _rng := RandomNumberGenerator.new()


func build(stage) -> void:
	_prepare(stage)
	for step in STEPS:
		call(step[0])


## The same, a step a frame, reporting progress (0..1, what) so a loading
## screen can show it. Needs to be in the tree.
func build_async(stage, report: Callable) -> void:
	_prepare(stage)
	for i in STEPS.size():
		report.call(float(i) / STEPS.size(), STEPS[i][1])
		await get_tree().process_frame
		if not is_inside_tree():
			return
		call(STEPS[i][0])
	report.call(1.0, "")


const STEPS := [["_environment", "Checking the weather"], ["_mountains", "Raising the mountains"], ["_road", "Grading the gravel road"],
	["_ground", "Shaping the hills"], ["_base", "Shaping the hills"],
	["_spectators", "Letting the spectators in"], ["_forest", "Planting ten thousand trees"], ["_rocks", "Rolling rocks onto the inside of the bends"],
	["_puddles", "Filling the puddles"], ["_loose_stones", "Raking out the loose gravel"],
	["_arches", "Putting up the start and finish"]]


func _prepare(stage) -> void:
	st = stage
	_rng.seed = hash([st.seed_used, "props"])
	_noise.seed = st.seed_used
	_noise.frequency = 0.012
	for i in st.pts.size():
		var key := Vector2i(floori(st.pts[i].x / 20.0), floori(st.pts[i].z / 20.0))
		if not _road_grid.has(key):
			_road_grid[key] = []
		_road_grid[key].append(i)


# ── road ──────────────────────────────────────────────────────────────────

func _road() -> void:
	var mb := MeshBuf.new()
	var n: int = st.pts.size()
	var prev: Array = []
	for i in n:
		var s: float = i * st.STEP
		var c: Vector3 = st.pts[i]
		var r: Vector3 = st.right_at(s)
		var row: Array = []
		var berm := _berm(i)
		var half: float = st.widths[i] * 0.5
		for x in _road_x(half):
			row.append(c + r * x[0] + Vector3.UP * (x[1] + _berm_lift(berm, x[0], half)))
		if not prev.is_empty():
			var shade := 0.94 + 0.06 * sin(s * 0.37) * cos(s * 0.11)
			for k in ROAD_X.size() - 1:
				var col: Color = ROAD_X[k][2] * shade
				col.a = 1.0
				mb.quad(prev[k], prev[k + 1], row[k + 1], row[k], col, true)
		prev = row
	_add(mb, "gravel", "Road")
	# the start line
	var sl := MeshBuf.new()
	var s0: float = st.START_S
	var a: Vector3 = st.world_at(s0, -2.8) + Vector3.UP * 0.07
	var b: Vector3 = st.world_at(s0, 2.8) + Vector3.UP * 0.07
	var f: Vector3 = st.forward_at(s0) * 0.4
	sl.quad(a - f, b - f, b + f, a + f, Color(0.95, 0.95, 0.92))
	_add(sl, "", "StartLine")


## The berm at sample i: cars throw gravel to the outside of a bend, so it piles
## up there, higher the tighter the bend. Vector2(side of the road it's on (-1
## left / +1 right), height in m)
func _berm(i: int) -> Vector2:
	var k := 0.0
	for j in range(maxi(0, i - 4), mini(st.curv.size(), i + 5)):
		k += st.curv[j]
	k /= 9.0
	return Vector2(-signf(k), clampf(absf(k) * 2.0, 0.0, 0.06))      # a low ridge a slide rides over, not a kerb


## How much a road cross-section point at d is lifted by a berm (road half-width `half`).
static func _berm_lift(berm: Vector2, d: float, half := 2.8) -> float:
	if absf(d) < half - 0.1 or signf(d) != berm.x:
		return 0.0
	return berm.y * (1.0 if absf(d) < half + 0.2 else 0.5)


## The road's cross-section for a half-width: the edges and verges move, the
## crown and the wheel tracks stay.
static func _road_x(half: float) -> Array:
	var out: Array = []
	for x in ROAD_X:
		var d: float = x[0]
		if absf(d) > 2.0:
			d += signf(d) * (half - 2.8)
		out.append([d, x[1], x[2]])
	return out


## Loose stones where the grip is worse: out toward the edges (thickest in the
## berms) and a few on the crown between the wheel tracks. Never in the tracks.
## In chunks of road, each drawn only when the camera is near (they're small).
func _loose_stones() -> void:
	var rock := SphereMesh.new()
	rock.radius = 0.5
	rock.height = 0.7
	rock.radial_segments = 5
	rock.rings = 1
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	rock.material = m
	var shades := [Color(0.42, 0.4, 0.38), Color(0.5, 0.45, 0.39), Color(0.35, 0.33, 0.32), Color(0.56, 0.5, 0.41)]
	var per_chunk := int(CHUNK / st.STEP)
	for c0 in range(0, st.pts.size(), per_chunk):
		var xfs: Array = []
		var cols: Array = []
		for i in range(c0, mini(c0 + per_chunk, st.pts.size())):
			var s: float = i * st.STEP
			var berm := _berm(i)
			var half: float = st.widths[i] * 0.5
			var spots: Array = []
			for side in [-1.0, 1.0]:
				var n_edge := 2 + _rng.randi() % 2 + (3 if berm.x == side and berm.y > 0.05 else 0)
				for k in n_edge:
					spots.append(side * _rng.randf_range(1.5, half + 0.05))
			if _rng.randf() < 0.6:
				spots.append(_rng.randf_range(-0.35, 0.35))
			for d in spots:
				var at: float = s + _rng.randf_range(0.0, st.STEP)
				var p: Vector3 = st.world_at(at, d) + Vector3.UP * (_road_height(d, half) + _berm_lift(berm, d, half) + 0.01)
				var sz := _rng.randf_range(0.07, 0.17)
				var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(sz, sz * 0.55, sz * _rng.randf_range(0.8, 1.3)))
				xfs.append(Transform3D(b, p))
				cols.append(shades[_rng.randi() % shades.size()])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = rock
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
			mm.set_instance_color(i, cols[i])
		var mi := MultiMeshInstance3D.new()
		mi.name = "LooseStones%d" % c0
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 140.0
		mi.visibility_range_end_margin = 20.0
		add_child(mi)


## The road surface's height across the road (the crown and the edges), at d.
static func _road_height(d: float, half := 2.8) -> float:
	var xs := _road_x(half)
	for j in xs.size() - 1:
		var a: Array = xs[j]
		var b: Array = xs[j + 1]
		if d >= a[0] and d <= b[0]:
			return lerpf(a[1], b[1], (d - a[0]) / (b[0] - a[0]))
	return 0.0


# ── spectators ────────────────────────────────────────────────────────────

## Where the crowds stand: both sides of every jump's landing, the start and
## the finish, and the outside of some slow corners' exits. Well back from the
## road (7-10 m past the edge) on the bank, behind tape, in a clearing.
func _spectators() -> void:
	var spots: Array = [[st.START_S + 6.0, -1.0, 14], [st.START_S + 10.0, 1.0, 12],
		[st.finish_s + 15.0, -1.0, 12], [st.finish_s + 22.0, 1.0, 10]]
	for c in st.crests:
		if c.jump:
			for side in [-1.0, 1.0]:
				spots.append([c.s + _rng.randf_range(12.0, 24.0), side, 10 + _rng.randi() % 8])
	for c in st.corners:
		if (c.grade <= 3 or c.shape != "") and _rng.randf() < 0.3:
			spots.append([c.s1 + _rng.randf_range(4.0, 12.0), -float(c.dir), 5 + _rng.randi() % 8])
	var jackets := [Color(0.85, 0.15, 0.12), Color(0.15, 0.35, 0.8), Color(0.95, 0.75, 0.1), Color(0.95, 0.45, 0.1),
		Color(0.2, 0.6, 0.25), Color(0.92, 0.92, 0.9), Color(0.12, 0.12, 0.14), Color(0.55, 0.2, 0.6)]
	var skins := [Color(0.96, 0.8, 0.66), Color(0.86, 0.66, 0.5), Color(0.62, 0.44, 0.3), Color(0.42, 0.29, 0.2)]
	var hats := [Color(0.85, 0.15, 0.12), Color(0.12, 0.12, 0.14), Color(0.15, 0.35, 0.8), Color(0.95, 0.95, 0.95)]
	var flags := [Color(0.1, 0.35, 0.9), Color(0.92, 0.12, 0.12), Color(1.0, 0.82, 0.1), Color(0.1, 0.7, 0.3), Color(0.98, 0.98, 1.0)]
	for sp in spots:
		var s: float = clampf(sp[0], 4.0, st.length - 4.0)
		var side: float = sp[1]
		var n: int = sp[2]
		var back: float = st.width_at(s) * 0.5 + _rng.randf_range(7.0, 10.0)
		var centre: Vector3 = st.world_at(s, side * back)
		if _near_road(centre, back - 1.5):
			continue                                    # another bit of road comes past here
		var people: Array = []
		var rows := 1 + mini(n / 6, 2)
		var per_row := ceili(float(n) / rows)
		for k in n:
			var row := k / per_row
			var along := (k % per_row - per_row * 0.5) * 0.85 + _rng.randf_range(-0.2, 0.2)
			var deep := row * 0.95 + _rng.randf_range(-0.15, 0.15)
			var at := clampf(s + along, 0.0, st.length)
			var i0 := clampi(int(at / st.STEP), 0, st.pts.size() - 1)
			var extra: float = st.widths[i0] * 0.5 - 2.8
			var p: Vector3 = st.world_at(at, side * (back + deep))
			p.y = _ground_height(st.pts[i0].y, back + deep - extra, p) - 0.05
			var look: Vector3 = st.world_at(at, 0.0) - p
			look.y = 0.0
			var basis := Basis.looking_at(look.normalized(), Vector3.UP) if look.length() > 0.1 else Basis()
			basis = basis.scaled(Vector3.ONE * _rng.randf_range(0.9, 1.08))
			people.append({"xf": Transform3D(basis, p - centre), "phase": _rng.randf(),
				"flag": _rng.randf() < 0.28, "hat": _rng.randf() < 0.45})
		var crowd := Crowd.new()
		crowd.name = "Crowd%d" % crowd_count
		crowd.position = centre
		crowd.people = people
		add_child(crowd)
		crowd.build(jackets, skins, hats, flags, _rng)
		_tape(s, side, back - 1.4, per_row * 0.85 + 2.5)
		_clearings.append([Vector2(centre.x, centre.z), per_row * 0.45 + rows + 3.5])
		crowd_count += 1
		people_count += n


## Red-and-white tape on posts between a crowd and the road (d m out, `length` long).
func _tape(s: float, side: float, d: float, length: float) -> void:
	var mb := MeshBuf.new()
	var post_col := Color(0.82, 0.8, 0.75)
	var steps := maxi(int(length / 0.5), 2)
	var prev_top := Vector3.ZERO
	for k in steps + 1:
		var at := clampf(s - length * 0.5 + k * 0.5, 0.0, st.length)
		var i0 := clampi(int(at / st.STEP), 0, st.pts.size() - 1)
		var extra: float = st.widths[i0] * 0.5 - 2.8
		var p: Vector3 = st.world_at(at, side * d)
		p.y = _ground_height(st.pts[i0].y, d - extra, p)
		var top := p + Vector3.UP * 0.92
		if k % 5 == 0:                                   # a post every 2.5 m
			var w: Vector3 = st.forward_at(at) * 0.03
			mb.tri_raw(p - w, p + w, top + w, post_col)
			mb.tri_raw(p - w, top + w, top - w, post_col)
			mb.tri_raw(top + w, p + w, p - w, post_col)
			mb.tri_raw(top - w, top + w, p - w, post_col)
		if k > 0:
			var col := Color(0.9, 0.12, 0.1) if k % 2 == 0 else Color(0.95, 0.95, 0.95)
			var h := Vector3.UP * 0.07
			mb.tri_raw(prev_top - h, top - h, top + h, col)
			mb.tri_raw(prev_top - h, top + h, prev_top + h, col)
			mb.tri_raw(top + h, top - h, prev_top - h, col)
			mb.tri_raw(prev_top + h, top + h, prev_top - h, col)
		prev_top = top
	var mi := _add(mb, "", "Tape")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _in_clearing(p: Vector3) -> bool:
	for c in _clearings:
		if Vector2(p.x, p.z).distance_to(c[0]) < c[1]:
			return true
	return false


# ── ground ────────────────────────────────────────────────────────────────

func _ground() -> void:
	var mb := MeshBuf.new()
	var n: int = st.pts.size()
	var stride := 2                                     # every 4 m is plenty off the road
	for side in [-1.0, 1.0]:
		var prev: Array = []
		for i in range(0, n, stride):
			var s: float = i * st.STEP
			var c: Vector3 = st.pts[i]
			var r: Vector3 = st.right_at(s)
			var extra: float = st.widths[i] * 0.5 - 2.8         # a wider road pushes the ground out
			# on the inside of a bend the ground can't reach past the bend's centre: clamp it
			var reach := 1e9
			for j in range(maxi(0, i - 12), mini(n, i + 13)):
				var k: float = st.curv[j]
				if signf(k) == side and absf(k) > 1e-4:
					reach = minf(reach, 0.85 / absf(k))
			# ... and never out over another stretch of the same road (after a bend the road
			# comes back past this spot): stop where some other road is closer than ours
			for g in GROUND_X:
				var gd: float = g[0] + extra
				var probe: Vector3 = c + r * (gd * side)
				if g[0] > 4.0 and _nearest_road(probe) < gd - 2.5:
					reach = minf(reach, maxf(3.4 + extra, gd - 6.0))
					break
			var row: Array = []
			var cols: Array = []
			var berm := _berm(i)
			for gi in GROUND_X.size():
				var g: Array = GROUND_X[gi]
				var d: float = minf(g[0] + extra, maxf(reach, 3.4 + extra))
				var p: Vector3 = c + r * (d * side)
				var h: float = g[1] + g[2] * _noise.get_noise_2d(p.x, p.z)
				if berm.x == side and gi < 2:
					h += berm.y * (0.5 if gi == 0 else 0.2)       # the berm tapers off into the grass
				row.append(p + Vector3.UP * h)
				var col: Color = GRASS.lerp(GRASS_FAR, clampf(d / 60.0, 0.0, 1.0))
				col = col * (0.92 + 0.12 * _noise.get_noise_2d(p.z * 3.0, p.x * 3.0))
				col.a = 1.0
				cols.append(col if d > 4.0 + extra else GRASS * 0.85)
			if not prev.is_empty():
				for k in GROUND_X.size() - 1:
					mb.quad(prev[k], prev[k + 1], row[k + 1], row[k], cols[k], true)
			prev = row
	_add(mb, "grass", "Ground")


## A big flat field under everything: whatever the ribbons miss is still green.
func _base() -> void:
	var lo := INF
	var mn := Vector3(INF, 0, INF)
	var mx := Vector3(-INF, 0, -INF)
	for p in st.pts:
		lo = minf(lo, p.y)
		mn = Vector3(minf(mn.x, p.x), 0, minf(mn.z, p.z))
		mx = Vector3(maxf(mx.x, p.x), 0, maxf(mx.z, p.z))
	var y := lo - 1.6
	mn -= Vector3(200, 0, 200)
	mx += Vector3(200, 0, 200)
	var mb := MeshBuf.new()
	mb.quad(Vector3(mn.x, y, mn.z), Vector3(mx.x, y, mn.z), Vector3(mx.x, y, mx.z), Vector3(mn.x, y, mx.z), GRASS_FAR * 0.9)
	var body := _add(mb, "", "Base")
	var sb := StaticBody3D.new()
	sb.set_meta("surface", "grass")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(mx.x - mn.x, 2.0, mx.z - mn.z)
	cs.shape = box
	cs.position = Vector3((mn.x + mx.x) * 0.5, y - 1.0, (mn.z + mx.z) * 0.5)
	sb.add_child(cs)
	add_child(sb)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Mesh + (if `surface` isn't "") a static body with its triangles.
func _add(mb, surface: String, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mb.mesh()
	mi.material_override = MeshBuf.material()
	add_child(mi)
	if surface != "" and not mb.faces.is_empty():
		var sb := StaticBody3D.new()
		sb.name = node_name + "Body"
		sb.set_meta("surface", surface)
		var cs := CollisionShape3D.new()
		cs.shape = mb.shape()
		sb.add_child(cs)
		add_child(sb)
	return mi


# ── forest ────────────────────────────────────────────────────────────────

func _forest() -> void:
	# trees are grouped in chunks of road (CHUNK m) so each chunk can be culled and
	# faded out by distance: thousands of trees, but only the nearby ones are drawn
	var chunks := {}                                 # chunk index -> {kind: [Transform3D]}
	var trunks := StaticBody3D.new()
	trunks.name = "Trunks"
	trunks.set_meta("surface", "grass")
	add_child(trunks)
	var n: int = st.pts.size()
	for i in range(0, n, 2):                         # every 4 m of road
		var s: float = i * st.STEP
		if s < st.START_S - 30.0:
			continue
		var c: Vector3 = st.pts[i]
		var r: Vector3 = st.right_at(s)
		var k: float = st.curv[mini(i + 4, n - 1)]
		var extra: float = st.widths[i] * 0.5 - 2.8              # a wider road: the trees stand back
		for side in [-1.0, 1.0]:
			var inside: bool = signf(k) == side and absf(k) > 1.0 / 160.0
			# [from, to (m off the centreline), chance, how many tries]: a dense wall along
			# the road, thick forest behind it, and a far belt out to 150 m so it never
			# opens up into empty grass
			var slots: Array = [[TREE_LINE, 11.0, 0.95 if inside else 0.75, 2],     # the wall along the road
				[11.0, 18.0, 0.9, 5], [18.0, 40.0, 0.85, 7], [40.0, 76.0, 0.85, 5], [76.0, 150.0, 0.8, 8]]
			if inside:
				slots.append([TREE_LINE, TREE_LINE + 3.0, 0.8, 1])          # thicker on the inside of bends
			for sl in slots:
				for t in sl[3]:
					if _rng.randf() > sl[2]:
						continue
					var d: float = _rng.randf_range(sl[0], sl[1]) + extra
					var along: Vector3 = st.forward_at(s) * _rng.randf_range(-2.0, 2.0)
					var p: Vector3 = c + r * (d * side) + along
					if _near_road(p, TREE_LINE - 0.4 + maxf(extra, 0.0)) or _in_clearing(p):
						continue
					p.y = _ground_height(c.y, d - extra, p) - 0.15
					var kind: String = ["pine", "pine", "pine", "round", "birch", "bush"][_rng.randi() % 6]
					if d - extra < 6.0 and kind == "bush":
						kind = "round"
					if sl[0] >= 76.0:
						kind = (["pine", "pine", "round", "birch"][_rng.randi() % 4]) + "_far"   # no shadows, drawn nearer
					var sc := _rng.randf_range(0.85, 1.55)
					var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * sc), p)
					var ci := int(s / CHUNK)
					if not chunks.has(ci):
						chunks[ci] = {}
					if not chunks[ci].has(kind):
						chunks[ci][kind] = []
					chunks[ci][kind].append(xf)
					tree_count += 1
					if d - extra < 12.0 and kind != "bush":
						var cs := CollisionShape3D.new()
						var cyl := CylinderShape3D.new()
						cyl.radius = 0.28 * sc
						cyl.height = 4.0
						cs.shape = cyl
						cs.position = p + Vector3.UP * 2.0
						trunks.add_child(cs)
	# undergrowth: ferns between the road and the trees (no collision: you drive through them)
	for i in range(0, n, 2):
		var s: float = i * st.STEP
		if s < st.START_S - 30.0:
			continue
		var c: Vector3 = st.pts[i]
		var r: Vector3 = st.right_at(s)
		var extra: float = st.widths[i] * 0.5 - 2.8
		for side in [-1.0, 1.0]:
			for t in 3:
				var d: float = _rng.randf_range(4.4, 14.0) + extra
				var p: Vector3 = c + r * (d * side) + st.forward_at(s) * _rng.randf_range(-2.0, 2.0)
				if _near_road(p, 4.0 + maxf(extra, 0.0)) or _in_clearing(p):
					continue
				p.y = _ground_height(c.y, d - extra, p) - 0.05
				var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.7, 1.3)), p)
				var ci := int(s / CHUNK)
				if not chunks.has(ci):
					chunks[ci] = {}
				if not chunks[ci].has("fern"):
					chunks[ci]["fern"] = []
				chunks[ci]["fern"].append(xf)
	var meshes := {}
	for kind in ["pine", "round", "birch", "bush", "fern"]:
		meshes[kind] = _tree_mesh(kind)
	var mat := MeshBuf.material()
	for ci in chunks:
		for kind in chunks[ci]:
			var list: Array = chunks[ci][kind]
			if list.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[kind.trim_suffix("_far")]
			mm.instance_count = list.size()
			for j in list.size():
				mm.set_instance_transform(j, list[j])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Trees_%d_%s" % [ci, kind]
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.visibility_range_end = FAR_DRAW if kind.ends_with("_far") else (FERN_DRAW if kind == "fern" else TREE_DRAW)
			mmi.visibility_range_end_margin = 40.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			if kind == "bush" or kind == "fern" or kind.ends_with("_far"):
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)


func _ground_height(road_y: float, d: float, p: Vector3) -> float:
	var h := 0.0
	for g in range(GROUND_X.size() - 1):
		var a: Array = GROUND_X[g]
		var b: Array = GROUND_X[g + 1]
		if d >= a[0] and d <= b[0]:
			var u: float = (d - a[0]) / (b[0] - a[0])
			var ha: float = a[1] + a[2] * _noise.get_noise_2d(p.x, p.z)
			var hb: float = b[1] + b[2] * _noise.get_noise_2d(p.x, p.z)
			h = lerpf(ha, hb, u)
			break
	if d > GROUND_X[-1][0]:
		h = GROUND_X[-1][1]
	return road_y + h


## Distance (flat) from p to the nearest centerline sample, up to ~40 m (INF if none near).
func _nearest_road(p: Vector3) -> float:
	var best := INF
	var c := Vector2i(floori(p.x / 20.0), floori(p.z / 20.0))
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for i in _road_grid.get(c + Vector2i(dx, dz), []):
				var q: Vector3 = st.pts[i]
				best = minf(best, Vector2(p.x - q.x, p.z - q.z).length())
	return best


func _near_road(p: Vector3, dist: float) -> bool:
	var c := Vector2i(floori(p.x / 20.0), floori(p.z / 20.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for i in _road_grid.get(c + Vector2i(dx, dz), []):
				var q: Vector3 = st.pts[i]
				if Vector2(p.x - q.x, p.z - q.z).length() < dist:
					return true
	return false


## Low-poly tree meshes (origin at the foot of the trunk).
func _tree_mesh(kind: String) -> ArrayMesh:
	var mb := MeshBuf.new()
	var bark := Color(0.38, 0.27, 0.18)
	match kind:
		"pine":
			_cyl(mb, Vector3.ZERO, 0.22, 1.6, 5, bark)
			var greens := [Color(0.16, 0.36, 0.2), Color(0.19, 0.42, 0.22), Color(0.22, 0.47, 0.24)]
			for t in 3:
				_cone(mb, Vector3(0, 1.2 + t * 1.5, 0), 1.9 - t * 0.45, 2.6, 7, greens[t])
		"round":
			_cyl(mb, Vector3.ZERO, 0.24, 2.2, 5, bark)
			_blob(mb, Vector3(0, 3.6, 0), Vector3(2.0, 1.8, 2.0), Color(0.3, 0.55, 0.22))
			_blob(mb, Vector3(0.6, 4.5, 0.3), Vector3(1.3, 1.2, 1.3), Color(0.35, 0.6, 0.25))
		"birch":
			_cyl(mb, Vector3.ZERO, 0.16, 3.4, 5, Color(0.9, 0.88, 0.82))
			_blob(mb, Vector3(0, 4.3, 0), Vector3(1.3, 1.6, 1.3), Color(0.45, 0.66, 0.28))
		"bush":
			_blob(mb, Vector3(0, 0.55, 0), Vector3(1.2, 0.8, 1.2), Color(0.26, 0.5, 0.2))
		"fern":
			# a spiky clump: a few leaning fronds (thin cones) round a middle
			var fg := [Color(0.22, 0.48, 0.18), Color(0.28, 0.56, 0.2), Color(0.18, 0.42, 0.16)]
			for k in 5:
				var a := k * TAU / 5.0
				var lean := Vector3(cos(a), 0.0, sin(a)) * 0.28
				_cone(mb, lean, 0.16, 0.75, 4, fg[k % 3])
			_cone(mb, Vector3.ZERO, 0.2, 0.9, 5, fg[1])
	return mb.mesh()


func _cyl(mb, base: Vector3, r: float, h: float, seg: int, col: Color) -> void:
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var p0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		mb.tri_raw(p0, p1, p1 + Vector3.UP * h, col)
		mb.tri_raw(p0, p1 + Vector3.UP * h, p0 + Vector3.UP * h, col)


func _cone(mb, base: Vector3, r: float, h: float, seg: int, col: Color) -> void:
	var top := base + Vector3.UP * h
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var p0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		mb.tri_raw(p0, p1, top, col * (0.9 + 0.15 * (k % 2)))
		mb.tri_raw(p1, p0, base, col * 0.75)


## A squashed octahedron-ish ball (8 faces + a belt: chunky low poly).
func _blob(mb, c: Vector3, sz: Vector3, col: Color) -> void:
	var seg := 6
	var top := c + Vector3(0, sz.y, 0)
	var bot := c - Vector3(0, sz.y * 0.8, 0)
	var ring_hi: Array = []
	var ring_lo: Array = []
	for k in seg:
		var a := TAU * k / seg
		ring_hi.append(c + Vector3(cos(a) * sz.x * 0.8, sz.y * 0.35, sin(a) * sz.z * 0.8))
		ring_lo.append(c + Vector3(cos(a + 0.5) * sz.x, -sz.y * 0.2, sin(a + 0.5) * sz.z))
	for k in seg:
		var k1 := (k + 1) % seg
		var shade := 0.92 + 0.14 * float(k % 3) / 2.0
		mb.tri_raw(ring_hi[k], ring_hi[k1], top, col * (shade + 0.08))
		mb.tri_raw(ring_lo[k], ring_hi[k1], ring_hi[k], col * shade)
		mb.tri_raw(ring_lo[k], ring_lo[k1], ring_hi[k1], col * (shade - 0.06))
		mb.tri_raw(ring_lo[k1], ring_lo[k], bot, col * 0.7)


# ── rocks, puddles, arches ────────────────────────────────────────────────

func _rocks() -> void:
	var body := StaticBody3D.new()
	body.name = "Rocks"
	body.set_meta("surface", "gravel")
	add_child(body)
	var mb := MeshBuf.new()
	for rk in st.rocks:
		var p: Vector3 = st.world_at(rk.s, rk.d)
		var r: float = rk.r
		_blob(mb, p + Vector3.UP * r * 0.35, Vector3(r, r * 0.75, r * 0.9), Color(0.55, 0.54, 0.5))
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = r * 0.85
		cs.shape = sph
		cs.position = p + Vector3.UP * r * 0.3
		body.add_child(cs)
	if not mb.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "RockMesh"
		mi.mesh = mb.mesh()
		mi.material_override = MeshBuf.material()
		add_child(mi)


func _puddles() -> void:
	var mb := MeshBuf.new()
	for pd in st.puddles:
		var c: Vector3 = st.world_at(pd.s, pd.d) + Vector3.UP * 0.075
		var f: Vector3 = st.forward_at(pd.s)
		var r: Vector3 = st.right_at(pd.s)
		var seg := 9
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var p0: Vector3 = c + f * cos(a0) * pd.r * 1.3 + r * sin(a0) * pd.r * 0.8
			var p1: Vector3 = c + f * cos(a1) * pd.r * 1.3 + r * sin(a1) * pd.r * 0.8
			mb.tri(c, p0, p1, Color(0.3, 0.22, 0.14))
	var mi := MeshInstance3D.new()
	mi.name = "Puddles"
	mi.mesh = mb.mesh()
	var m := MeshBuf.material()
	m.roughness = 0.15
	m.metallic_specular = 0.8
	mi.material_override = m
	add_child(mi)


func _arches() -> void:
	_arch(st.START_S + 2.0, "START", Color(0.85, 0.15, 0.12))
	_arch(st.finish_s, "FINISH", Color(0.1, 0.35, 0.8))
	_sign(st.finish_s - 100.0, 3.8, "FLYING FINISH 100", Color(0.95, 0.8, 0.1))
	_sign(st.finish_s + 70.0, 3.8, "STOP", Color(0.85, 0.12, 0.1))
	# the start clocks: one each side of the line (in front of the arch posts, which
	# used to hide them), turned toward the car so both crew can read the count
	for d in [-3.3, 3.3]:
		start_clocks.append(_start_clock(st.world_at(st.START_S + 0.6, d)))


## What the start clocks show ("5" .. "1", "GO", "--") and in what colour.
func set_start_clock(text: String, col: Color) -> void:
	for c in start_clocks:
		(c.mesh as TextMesh).text = text
		(c.material_override as StandardMaterial3D).albedo_color = col


func _start_clock(p: Vector3) -> MeshInstance3D:
	var post := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 1.6, 0.12)
	post.mesh = bm
	post.position = p + Vector3.UP * 0.8
	add_child(post)
	var board := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(1.3, 0.8, 0.08)
	board.mesh = bb
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.08, 0.08, 0.09)
	board.material_override = bmat
	board.position = p + Vector3.UP * 1.75
	# face the car waiting behind the line
	var car_at: Vector3 = st.world_at(st.START_S - 3.0, 0.0)
	board.rotation.y = atan2(car_at.x - p.x, car_at.z - p.z)
	add_child(board)
	# 3D text (a mesh, lit by nothing: it glows like an LED board)
	var lbl := MeshInstance3D.new()
	var tm := TextMesh.new()
	tm.text = "--"
	tm.font = load("res://assets/fonts/Oswald-Bold.woff2")
	tm.font_size = 64
	tm.pixel_size = 0.008
	tm.depth = 0.01
	tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mesh = tm
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(1.0, 0.3, 0.2)
	lbl.material_override = lm
	lbl.rotation.y = board.rotation.y
	lbl.position = board.position + lbl.basis.z * 0.06
	add_child(lbl)
	return lbl


func _arch(s: float, text: String, col: Color) -> void:
	var f: Vector3 = st.forward_at(s)
	var yaw: float = st.heading_at(s)
	for side in [-1.0, 1.0]:
		var pole := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.25, 4.6, 0.25)
		pole.mesh = pm
		pole.position = st.world_at(s, side * 3.6) + Vector3.UP * 2.3
		add_child(pole)
	var banner := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(7.6, 0.9, 0.15)
	banner.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	banner.material_override = mat
	banner.position = st.world_at(s, 0.0) + Vector3.UP * 4.4
	banner.rotation.y = -yaw
	add_child(banner)
	for face in [1.0, -1.0]:
		var lab := Label3D.new()
		lab.text = text
		lab.font_size = 110
		lab.pixel_size = 0.006
		lab.modulate = Color.WHITE
		lab.outline_size = 0
		lab.position = banner.position - f * 0.09 * face
		lab.rotation.y = -yaw + (0.0 if face > 0.0 else PI)
		add_child(lab)


func _sign(s: float, d: float, text: String, col: Color) -> void:
	var p: Vector3 = st.world_at(s, d)
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.1, 1.8, 0.1)
	post.mesh = pm
	post.position = p + Vector3.UP * 0.9
	add_child(post)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 0.6, 0.06)
	board.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	board.material_override = mat
	board.position = p + Vector3.UP * 2.0
	board.rotation.y = -st.heading_at(s)
	add_child(board)
	var lab := Label3D.new()
	lab.text = text
	lab.font_size = 48
	lab.pixel_size = 0.006
	lab.modulate = Color(0.05, 0.05, 0.05)
	lab.outline_size = 0
	lab.position = board.position - st.forward_at(s) * 0.04
	lab.rotation.y = -st.heading_at(s)
	add_child(lab)


# ── sky ───────────────────────────────────────────────────────────────────

## Mountains all round the horizon: three ridgelines one behind the other, the
## far ones paler (they fade into the sky's horizon colour), snow on the highest
## peaks, mist at their feet. They're a ring ~600-800 m out that follows the
## camera across the ground (not up and down): like the real thing, they never
## get any closer. No fog on them (the fog would hide them; the haze is in their
## colours) and no shadows.
func _mountains() -> void:
	var lo := INF
	for p in st.pts:
		lo = minf(lo, p.y)
	_mountain_y = lo - 25.0
	var seg := 160
	var layers := [[830.0, 260.0, 0.58], [730.0, 185.0, 0.4], [640.0, 120.0, 0.24]]   # radius, tallest, haze
	var rock := Color(0.24, 0.31, 0.38) if mood != "golden" else Color(0.34, 0.27, 0.34)
	if mood == "overcast":
		rock = Color(0.34, 0.36, 0.38)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var noise := FastNoiseLite.new()
	noise.seed = st.seed_used + 77
	noise.frequency = 1.0
	noise.fractal_octaves = 4
	for li in layers.size():
		var radius: float = layers[li][0]
		var tall: float = layers[li][1]
		var haze: float = layers[li][2]
		if mood == "overcast":
			haze = minf(haze * 1.7, 0.9)                     # the fog swallows them too
		var base := verts.size()
		for k in seg + 1:
			var a := TAU * k / seg
			# ridges: broad swells and sharp peaks, a different line per layer
			var n := noise.get_noise_2d(cos(a) * 2.2 + li * 9.0, sin(a) * 2.2)
			var peaks := pow(clampf(noise.get_noise_2d(cos(a) * 6.0 - li * 5.0, sin(a) * 6.0) * 0.5 + 0.5, 0.0, 1.0), 2.2)
			var h := tall * clampf(0.35 + n * 0.6 + peaks * 0.75, 0.08, 1.15)
			var dir := Vector3(cos(a), 0.0, sin(a))
			verts.append(dir * radius + Vector3.UP * h)
			verts.append(dir * radius + Vector3.DOWN * 60.0)
			var c := rock.lerp(_horizon, haze)
			c.a = haze
			cols.append(c)
			cols.append(c)
			uvs.append(Vector2(tall * 0.74, 0.0))                     # the snow line (the shader paints it)
			uvs.append(Vector2(tall * 0.74, 0.0))
		for k in seg:
			var a0 := base + k * 2
			idx.append_array([a0, a0 + 2, a0 + 1, a0 + 1, a0 + 2, a0 + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform vec3 horizon : source_color;
varying float y;
void vertex() { y = VERTEX.y; }
void fragment() {
	vec3 c = COLOR.rgb;
	vec3 snow = mix(vec3(0.94, 0.95, 0.97), horizon, COLOR.a * 0.6);
	c = mix(c, snow, smoothstep(UV.x - 4.0, UV.x + 4.0, y));          // snow above the snow line
	c = mix(c, mix(horizon, vec3(0.92), 0.15), (1.0 - smoothstep(-25.0, 70.0, y)) * 0.85);   // mist at the feet
	ALBEDO = c;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("horizon", _horizon)
	_range = MeshInstance3D.new()
	_range.name = "Mountains"
	_range.mesh = mesh
	_range.material_override = m
	_range.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_range.extra_cull_margin = 2000.0
	add_child(_range)
	_range.position = Vector3(st.pts[0].x, _mountain_y, st.pts[0].z)


func _process(_dt: float) -> void:
	if _range == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam:
		var c := cam.global_position
		_range.global_position = Vector3(c.x, _mountain_y, c.z)

## The light: "day" (high sun, blue sky), "golden" (an evening sun low through
## the trees, warm and long-shadowed), "overcast" (grey sky, soft light, fog).
func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.55, 0.85)
	sm.sky_horizon_color = Color(0.72, 0.82, 0.9)
	sm.ground_horizon_color = Color(0.6, 0.7, 0.62)
	sm.ground_bottom_color = Color(0.25, 0.35, 0.22)
	match mood:
		"golden":
			sm.sky_top_color = Color(0.3, 0.42, 0.7)
			sm.sky_horizon_color = Color(1.0, 0.7, 0.42)
			sm.ground_horizon_color = Color(0.7, 0.55, 0.4)
		"overcast":
			sm.sky_top_color = Color(0.52, 0.56, 0.6)
			sm.sky_horizon_color = Color(0.7, 0.72, 0.74)
			sm.ground_horizon_color = Color(0.55, 0.58, 0.56)
	sky.sky_material = sm
	_horizon = sm.sky_horizon_color
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.4     # the rest is a neutral grey: the cabin isn't blue
	env.ambient_light_color = Color(0.62, 0.62, 0.6)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.8, 0.86)
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.96, 0.88)
	match mood:
		"golden":
			sun.rotation = Vector3(deg_to_rad(-16.0), deg_to_rad(65.0), 0.0)
			sun.light_color = Color(1.0, 0.72, 0.45)
			sun.light_energy = 1.15
			env.ambient_light_color = Color(0.62, 0.55, 0.52)
			env.fog_light_color = Color(0.95, 0.72, 0.52)
			env.fog_density = 0.006
		"overcast":
			sun.rotation = Vector3(deg_to_rad(-70.0), deg_to_rad(20.0), 0.0)
			sun.light_color = Color(0.85, 0.88, 0.92)
			sun.light_energy = 0.45
			env.ambient_light_energy = 0.85
			env.fog_light_color = Color(0.68, 0.71, 0.73)
			env.fog_density = 0.016
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
