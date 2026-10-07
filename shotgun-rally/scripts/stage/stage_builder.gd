extends Node3D
## Turns a StageGen into the world: the road, gravel (crowned, with two worn
## wheel tracks, looser gravel on the crown and out toward the edges where the
## grip is worse (StageGen.lane_grip), berms of thrown-out gravel on the outside
## of the bends) or asphalt (edge lines, a centre line, gravel dragged onto it,
## snow and ice: _road), spectators behind tape at the jumps, the start and finish and
## some slow corners, flat grass run-off then rolling ground out to ~75 m, a low-poly
## forest that crowds the INSIDE of corners (so you can't see round them:
## that's what the notes are for), mud puddles, wooden bridges over gullies with
## a stream in them, the start / finish arches, and the sky and sun.
## Every surface the tyres can touch says what it is (meta "surface").

const MeshBuf = preload("res://scripts/stage/mesh_buf.gd")
const Crowd = preload("res://scripts/stage/crowd.gd")
const WorldMaterials = preload("res://scripts/render/world_materials.gd")   # the materials, sky and sun
const Graphics = preload("res://scripts/render/graphics.gd")

const GRAVEL := Color(0.71, 0.6, 0.44)
const TRACK := Color(0.6, 0.5, 0.36)
const VERGE := Color(0.5, 0.52, 0.3)
const GRASS := Color(0.34, 0.54, 0.21)
const GRASS_FAR := Color(0.28, 0.46, 0.19)
const DIRT := Color(0.45, 0.36, 0.25)
## The asphalt (tarmac stages and sections): dark, a white line along each edge, a
## dashed centre line where it's wide enough, a gravel shoulder; no wheel tracks,
## no berms. Snow and ice lying on it (StageGen.patches).
const ASPHALT := Color(0.27, 0.27, 0.28)
const PAINT := Color(0.9, 0.9, 0.86)
const SHOULDER := Color(0.5, 0.46, 0.38)
const SNOW := Color(0.93, 0.95, 0.98)
const YELLOW := Color(0.95, 0.72, 0.1)
const ICE := Color(0.5, 0.62, 0.74)
const CENTRE_LINE_W := 5.4          # roads at least this wide get a centre line
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
## The ground's points on a mountain stage (m out, at the normal width): closer
## together, the mountainside isn't a straight line between them (_mountain_h).
const MOUNTAIN_X := [[2.9], [5.0], [6.5], [8.5], [10.5], [13.0], [17.0], [22.0], [30.0], [40.0], [52.0], [66.0],
	[82.0], [100.0], [122.0], [154.0]]
const ROCK := Color(0.52, 0.49, 0.45)
var _lowest := INF                  # the lowest the ground goes (the mountainside's far field goes under it)

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


const STEPS := [["_environment", "Checking the weather"], ["_mountains", "Raising the mountains"], ["_road", "Laying the road"],
	["_ground", "Shaping the hills"], ["_base", "Shaping the hills"], ["_towns", "Closing the town's streets"], ["_villages", "Building the villages"],
	["_barriers", "Bolting up the armco"], ["_spectators", "Letting the spectators in"], ["_forest", "Planting ten thousand trees"],
	["_puddles", "Filling the puddles"], ["_bridges", "Building the bridges"], ["_roadside", "Putting up the signs"],
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
	for b in st.bridges:                             # no trees down in a bridge's gully
		var mid: float = (b.s0 + b.s1) * 0.5
		for d in range(-60, 61, 12):
			var p: Vector3 = st.world_at(mid, d)
			_clearings.append([Vector2(p.x, p.z), 14.0])


# ── road ──────────────────────────────────────────────────────────────────

func _road() -> void:
	var bufs := {}                                   # surface -> MeshBuf: each its own body (what the tyres feel)
	var n: int = st.pts.size()
	var prev_g: Array = []
	var prev_a: Array = []
	for i in n:
		var s: float = i * st.STEP
		var c: Vector3 = st.pts[i]
		var r: Vector3 = st.right_at(s)
		var half: float = st.widths[i] * 0.5
		var berm := _berm(i)
		# both cross-sections at every sample (cheap): the gravel's and the asphalt's
		var row_g: Array = []
		for x in _road_x(half):
			row_g.append(c + r * x[0] + Vector3.UP * (x[1] + _berm_lift(berm, x[0], half)))
		var xs_a := _asphalt_pts(half)
		var row_a: Array = []
		for d in xs_a:
			row_a.append(c + r * d + Vector3.UP * _road_height(d, half))
		if i > 0 and not st.on_bridge(s - st.STEP * 0.5):   # (a bridge's deck is the road there)
			var sm: float = s - st.STEP * 0.5
			var shade := 0.94 + 0.06 * sin(s * 0.37) * cos(s * 0.11)
			if st.surface_at(sm) == "gravel":
				for k in ROAD_X.size() - 1:
					var col: Color = ROAD_X[k][2] * shade
					col.a = 1.0
					_buf(bufs, "gravel").quad(prev_g[k], prev_g[k + 1], row_g[k + 1], row_g[k], col, true)
			else:
				var wide: bool = st.width_at(sm) >= CENTRE_LINE_W
				for k in xs_a.size() - 1:
					var dm: float = (xs_a[k] + xs_a[k + 1]) * 0.5
					var patch: Dictionary = st.patch_at(sm, dm)
					var surf: String = patch.surface if not patch.is_empty() else "asphalt"
					var shoulder: bool = k == 0 or k == xs_a.size() - 2
					var col := _highway_col(k, xs_a.size() - 2, sm, shade, patch) if st.kind == "highway" \
						else _asphalt_col(k, xs_a.size() - 2, sm, wide, shade, patch)
					if shoulder and surf == "asphalt":
						surf = "gravel"                          # (the shoulder: loose stuff)
					_buf(bufs, surf).quad(prev_a[k], prev_a[k + 1], row_a[k + 1], row_a[k], col, true)
		prev_g = row_g
		prev_a = row_a
	for surf in bufs:
		var mi := _add(bufs[surf], surf, "Road" if surf == "gravel" else "Road_" + surf, _surface_material(surf))
		if surf == "ice":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the start line
	var sl := MeshBuf.new()
	var s0: float = st.START_S
	var hw: float = maxf(st.width_at(s0) * 0.5, 2.8)
	var a: Vector3 = st.world_at(s0, -hw) + Vector3.UP * 0.07
	var b: Vector3 = st.world_at(s0, hw) + Vector3.UP * 0.07
	var f: Vector3 = st.forward_at(s0) * 0.4
	sl.quad(a - f, b - f, b + f, a + f, Color(0.95, 0.95, 0.92))
	_add(sl, "", "StartLine")


static func _buf(bufs: Dictionary, surf: String):
	if not bufs.has(surf):
		bufs[surf] = MeshBuf.new()
	return bufs[surf]


## The asphalt's cross-section points for a half-width (d, m): the shoulder, the
## edge line, the lanes (meeting the wheel-track points the patches use, +-1.25),
## the centre line, and the same on the other side. Its heights are the gravel
## road's (_road_height): the same crown, so the two meet flush at a join.
static func _asphalt_x(half: float) -> Array:
	return [-(half + 0.3), -half, -(half - 0.14), -1.25, -0.55, -0.07, 0.07, 0.55, 1.25, half - 0.14, half, half + 0.3]


## The asphalt's cross-section: a highway's (its lanes StageGen.LANE_W apart, the
## edge lines, asphalt shoulders, a verge) or the two-lane road's (_asphalt_x).
func _asphalt_pts(half: float) -> Array:
	if st.kind != "highway":
		return _asphalt_x(half)
	var edge: float = st.HIGHWAY_LANES * st.LANE_W * 0.5
	var out: Array = [-(half + 0.3), -half, -edge - 0.15, -edge]
	for k in range(1, st.HIGHWAY_LANES):
		var d: float = -edge + k * st.LANE_W
		out += [d - 0.08, d + 0.08]
	out += [edge, edge + 0.15, half, half + 0.3]
	return out


## A highway's strip k (of _asphalt_pts): the verges, the solid edge lines, the
## dashed lane lines (3 m painted, 9 m gap), the lanes and shoulders.
func _highway_col(k: int, last: int, s: float, shade: float, patch: Dictionary) -> Color:
	var col := ASPHALT * (0.97 + 0.03 * shade)
	if k == 0 or k == last:
		col = SHOULDER * shade
	elif k == 2 or k == last - 2:
		col = PAINT
	elif k >= 4 and k <= last - 4 and k % 2 == 0 and fmod(s, 12.0) < 3.0:
		col = PAINT
	return _lying_on(col, s, shade, patch)


## The colour of asphalt strip k (of _asphalt_x; `last` is the far shoulder's) at
## s, with whatever's lying on it (a patch: gravel, snow, ice). A touge's centre
## line is solid yellow (no overtaking), as on Japanese mountain roads.
func _asphalt_col(k: int, last: int, s: float, wide: bool, shade: float, patch: Dictionary) -> Color:
	var col := ASPHALT * (0.97 + 0.03 * shade)
	if k == 0 or k == last:
		col = SHOULDER * shade
	elif k == 1 or k == last - 1:
		col = PAINT
	elif k == 5 and st.kind == "touge":
		col = YELLOW
	elif k == 5 and wide and fmod(s, 12.0) < 4.5:
		col = PAINT                                      # the dashed centre line
	return _lying_on(col, s, shade, patch)


func _lying_on(col: Color, s: float, shade: float, patch: Dictionary) -> Color:
	if not patch.is_empty():
		match patch.surface:
			"snow":
				col = SNOW * (0.97 + 0.03 * shade)
			"ice":
				col = col.lerp(ICE, 0.65)
			"gravel":
				# dragged on: thick at a join, thinning out over JOIN_DIRT m; a dusty smear in a corner
				var thick := 0.75
				if patch.kind == "join":
					thick = lerpf(0.9, 0.3, clampf((s - float(patch.s0)) / (float(patch.s1) - float(patch.s0)), 0.0, 1.0))
				col = col.lerp(GRAVEL * 0.9, thick)
	col.a = 1.0
	return col


## The material for a road surface's mesh (WorldMaterials: textured from MEDIUM up, the
## vertex colours as the colour; ice shines).
static func _surface_material(surf: String) -> Material:
	return WorldMaterials.road(surf)


## The berm at sample i: cars throw gravel to the outside of a bend, so it piles
## up there, higher the tighter the bend. Vector2(side of the road it's on (-1
## left / +1 right), height in m)
func _berm(i: int) -> Vector2:
	if st.surface_at(i * st.STEP) != "gravel":
		return Vector2.ZERO                              # (asphalt: nothing thrown out)
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
	if st.kind != "rally":
		return                                       # (a touge at dawn, a highway: nobody watching)
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
	for sp in spots + _town_spots:
		var s: float = clampf(sp[0], 4.0, st.length - 4.0)
		var side: float = sp[1]
		var n: int = sp[2]
		var in_town: bool = sp.size() > 3                 # (on a pavement or a square, at its height)
		var back: float = sp[3] if in_town else st.width_at(s) * 0.5 + _rng.randf_range(7.0, 10.0)
		var centre: Vector3 = st.world_at(s, side * back)
		if _near_road(centre, back - 1.5):
			continue                                    # another bit of road comes past here
		if not in_town and (not st.villages.is_empty() or not st.towns.is_empty()) and _in_clearing(centre):
			continue                                    # (a house, or another crowd, is there)
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
			if in_town:
				p.y = st.pts[i0].y + PAVE_H - 0.02
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
		if not in_town:
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
	var prof: Array = MOUNTAIN_X if st.mountain else GROUND_X     # (on a mountain: the mountainside's, _mountain_h)
	var stride := 2                                     # every 4 m is plenty off the road
	var rows: Array = []                             # every 4 m, every 2 m round a bridge (its gully)
	for i in n:
		if i % stride == 0 or st.on_bridge(i * st.STEP, 6.0):
			rows.append(i)
	for side in [-1.0, 1.0]:
		var prev: Array = []
		for i in rows:
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
			for g in prof:
				var gd: float = g[0] + extra
				var probe: Vector3 = c + r * (gd * side)
				if g[0] > 4.0 and _nearest_road(probe) < gd - 2.5:
					reach = minf(reach, maxf(3.4 + extra, gd - 6.0))
					break
			var row: Array = []
			var cols: Array = []
			var berm := _berm(i)
			for gi in prof.size():
				var g: Array = prof[gi]
				var d: float = minf(g[0] + extra, maxf(reach, 3.4 + extra))
				var p: Vector3 = c + r * (d * side)
				var col: Color = GRASS.lerp(GRASS_FAR, clampf(d / 60.0, 0.0, 1.0))
				col = col * (0.92 + 0.12 * _noise.get_noise_2d(p.z * 3.0, p.x * 3.0))
				if st.mountain:
					p.y = _mountain_h(c.y, d - extra, p)
					col = _mountain_col(col, p, p.y - c.y, d - extra)
				else:
					var h: float = g[1] + g[2] * _noise.get_noise_2d(p.x, p.z) - st.gully_depth(s, d * side)
					if berm.x == side and gi < 2:
						h += berm.y * (0.5 if gi == 0 else 0.2)       # the berm tapers off into the grass
					p.y += h
					var dug: float = st.gully_depth(s, d * side)
					if dug > 0.0:                                     # a gully's banks: earth showing, mud at the bottom
						col = col.lerp(MUD, clampf(dug / 2.5, 0.0, 0.85))
				_lowest = minf(_lowest, p.y)
				row.append(p)
				col.a = 1.0
				var verge := GRASS * 0.85
				if st.mountain and st.opts.get("ice", false):
					verge = _mountain_col(verge, p, 0.0, d - extra)          # (snow on the verge too)
				verge.a = 1.0
				cols.append(col if d > 4.0 + extra or st.gully_depth(s, d * side) > 0.0 else verge)
			if not prev.is_empty():
				for k in prof.size() - 1:
					mb.quad(prev[k], prev[k + 1], row[k + 1], row[k], cols[k], true)
			prev = row
	_add(mb, "grass", "Ground")


## The ground on a mountain stage, d m out from the road's edge (at the normal
## width: as GROUND_X) at p: flush with the road and flat for the first couple of
## metres (room to save a slide), then into the mountainside (StageGen.terrain_at):
## above the road a bank, steeper where it's cut in deep, below it a drop; lumpy
## further out.
func _mountain_h(road_y: float, d: float, p: Vector3) -> float:
	var t: float = st.terrain_at(p.x, p.z)
	var near := road_y - 0.03 - 0.02 * smoothstep(2.9, 5.0, d)
	var w := smoothstep(4.4, 13.0, d)
	var cut := maxf(t - road_y, 0.0) * 0.5 * smoothstep(4.4, 7.5, d) * (1.0 - smoothstep(9.0, 18.0, d))
	var lump: float = minf(0.5 + 0.03 * d, 3.0) * _noise.get_noise_2d(p.x, p.z) * smoothstep(9.0, 30.0, d) * (1.0 - smoothstep(110.0, 150.0, d))
	return lerpf(near, t, w) + cut + lump


## The colour of the mountainside: rock where a bank is cut in above the road,
## snow lying about on a winter stage.
func _mountain_col(col: Color, p: Vector3, rise: float, d: float) -> Color:
	if rise > 0.7 and d < 26.0:
		var rock := ROCK * (0.9 + 0.15 * _noise.get_noise_2d(p.x * 4.0, p.z * 4.0))
		col = col.lerp(rock, clampf((rise - 0.7) / 1.6, 0.0, 0.9) * (1.0 - smoothstep(16.0, 26.0, d)))
	if st.opts.get("ice", false) and _noise.get_noise_2d(p.x * 0.7 + 50.0, p.z * 0.7) > -0.2:
		col = col.lerp(SNOW * 0.97, 0.85)
	return col


## A big flat field under everything: whatever the ribbons miss is still green.
func _base() -> void:
	var lo := INF
	var mn := Vector3(INF, 0, INF)
	var mx := Vector3(-INF, 0, -INF)
	for p in st.pts:
		lo = minf(lo, p.y)
		mn = Vector3(minf(mn.x, p.x), 0, minf(mn.z, p.z))
		mx = Vector3(maxf(mx.x, p.x), 0, maxf(mx.z, p.z))
	if st.mountain:
		_far_terrain(mn - Vector3(FAR_OUT, 0, FAR_OUT), mx + Vector3(FAR_OUT, 0, FAR_OUT))
		return
	var deepest := 0.0
	for b in st.bridges:
		deepest = maxf(deepest, b.depth)
	var y := lo - maxf(1.6, deepest + 1.2)           # (below the bottom of any gully)
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


## On a mountain stage the mountainside carries on past the ground along the
## road: a coarse grid of it (FAR_CELL m) out to FAR_OUT m round the stage, so the
## valley below and the slope above go on into the haze. Near the road it's kept
## well under the ground (which is already there) and the road itself: how near
## the road each grid point is, and the lowest road near it, spread out a ring of
## cells at a time from the cells the road passes through.
const FAR_CELL := 20.0
const FAR_OUT := 420.0
const FAR_NEAR := 9                 # cells: within this many of the road it's tucked under


func _far_terrain(mn: Vector3, mx: Vector3) -> void:
	var nx := int((mx.x - mn.x) / FAR_CELL) + 2
	var nz := int((mx.z - mn.z) / FAR_CELL) + 2
	var dist := PackedInt32Array()
	dist.resize(nx * nz)
	dist.fill(99)
	var low := PackedFloat32Array()
	low.resize(nx * nz)
	low.fill(INF)
	var frontier: Array = []
	for p in st.pts:
		var ix := clampi(int(round((p.x - mn.x) / FAR_CELL)), 0, nx - 1)
		var iz := clampi(int(round((p.z - mn.z) / FAR_CELL)), 0, nz - 1)
		var k := iz * nx + ix
		if dist[k] != 0:
			dist[k] = 0
			frontier.append(k)
		low[k] = minf(low[k], p.y)
	for ring in FAR_NEAR + 1:
		var next: Array = []
		for k in frontier:
			var ix: int = k % nx
			var iz: int = k / nx
			for dz in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var x2: int = ix + dx
					var z2: int = iz + dz
					if x2 < 0 or z2 < 0 or x2 >= nx or z2 >= nz:
						continue
					var k2 := z2 * nx + x2
					if dist[k2] > ring + 1:
						if dist[k2] == 99:
							next.append(k2)
						dist[k2] = ring + 1
					if dist[k2] == ring + 1:
						low[k2] = minf(low[k2], low[k])
		frontier = next
	var ice: bool = st.opts.get("ice", false)
	var verts: Array = []
	verts.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var k := iz * nx + ix
			var x: float = mn.x + ix * FAR_CELL
			var z: float = mn.z + iz * FAR_CELL
			var t: float = st.terrain_at(x, z)
			var y := t - 1.0
			if dist[k] <= FAR_NEAR:
				y = lerpf(minf(t, low[k]) - 4.5, t - 1.0, smoothstep(FAR_NEAR - 2.5, FAR_NEAR, float(dist[k])))
			verts[k] = Vector3(x, y, z)
	var mb := MeshBuf.new()
	for iz in nz - 1:
		for ix in nx - 1:
			var k := iz * nx + ix
			var a: Vector3 = verts[k]
			var col: Color = GRASS_FAR * (0.88 + 0.12 * _noise.get_noise_2d(a.x * 0.5, a.z * 0.5))
			if ice and _noise.get_noise_2d(a.x * 0.7 + 50.0, a.z * 0.7) > -0.2:
				col = col.lerp(SNOW * 0.95, 0.85)
			col.a = 1.0
			mb.quad(a, verts[k + 1], verts[k + nx + 1], verts[k + nx], col, true)
	var mi := _add(mb, "grass", "Mountainside")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Mesh + (if `surface` isn't "") a static body with its triangles.
func _add(mb, surface: String, node_name: String, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mb.mesh(WorldMaterials.smooth(node_name))
	mi.material_override = mat if mat else WorldMaterials.for_part(node_name, surface)
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
				# (a mountainside: trees here and there, open slopes between)
				var sparse: float = (0.5 if sl[0] < 18.0 or inside else 0.2) if st.mountain else 1.0
				for t in sl[3]:
					if _rng.randf() > sl[2] * sparse:
						continue
					var d: float = _rng.randf_range(sl[0], sl[1]) + extra
					var along: Vector3 = st.forward_at(s) * _rng.randf_range(-2.0, 2.0)
					var p: Vector3 = c + r * (d * side) + along
					if _near_road(p, TREE_LINE - 0.4 + maxf(extra, 0.0)) or _in_clearing(p):
						continue
					p.y = _ground_height(c.y, d - extra, p) - 0.15
					var kind: String = ["pine", "pine", "pine", "round", "birch", "bush"][_rng.randi() % 6]
					if st.kind == "touge":
						kind = ["cedar", "cedar", "cedar", "cedar", "round", "bush"][_rng.randi() % 6]   # sugi forest
					if d - extra < 6.0 and kind == "bush":
						kind = "round"
					if sl[0] >= 76.0:
						kind = ((["cedar", "cedar", "round", "pine"] if st.kind == "touge" else ["pine", "pine", "round", "birch"])[_rng.randi() % 4]) + "_far"   # no shadows, drawn nearer
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
	for kind in ["pine", "round", "birch", "bush", "fern", "cedar"]:
		meshes[kind] = _tree_mesh(kind)
	var mat := WorldMaterials.foliage()
	var view := Graphics.view_distance()                 # (the graphics quality: how far they're drawn)
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
			var near: float = (FERN_DRAW if kind == "fern" else TREE_DRAW) * (0.65 if OS.has_feature("web") else 1.0) * view
			mmi.visibility_range_end = FAR_DRAW * view if kind.ends_with("_far") else near
			mmi.visibility_range_end_margin = 40.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			if kind == "bush" or kind == "fern" or kind.ends_with("_far"):
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)


func _ground_height(road_y: float, d: float, p: Vector3) -> float:
	if st.mountain:
		return _mountain_h(road_y, d, p)
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
		"cedar":
			# a Japanese cedar (sugi): a tall straight trunk and a narrow dark spire
			_cyl(mb, Vector3.ZERO, 0.2, 3.0, 5, Color(0.42, 0.28, 0.2))
			var dark := [Color(0.1, 0.26, 0.16), Color(0.12, 0.3, 0.18), Color(0.14, 0.33, 0.2), Color(0.16, 0.36, 0.21)]
			for t in 4:
				_cone(mb, Vector3(0, 2.4 + t * 1.6, 0), 1.25 - t * 0.22, 2.4, 6, dark[t])
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


# ── mountain roads: armco, stone walls, villages ──────────────────────────

const ARMCO := Color(0.74, 0.76, 0.78)
const RAIL_WHITE := Color(0.92, 0.93, 0.93)  # a Japanese guardrail: painted white
const CONCRETE := Color(0.68, 0.68, 0.66)
const POST := Color(0.38, 0.39, 0.41)
const STONE := Color(0.63, 0.59, 0.52)
const HOUSE_WALLS := [Color(0.93, 0.88, 0.76), Color(0.9, 0.78, 0.6), Color(0.94, 0.84, 0.8), Color(0.87, 0.87, 0.83),
	Color(0.95, 0.92, 0.84), Color(0.84, 0.72, 0.58)]
const ROOFS := [Color(0.66, 0.32, 0.22), Color(0.6, 0.3, 0.2), Color(0.72, 0.38, 0.26), Color(0.36, 0.37, 0.41)]
const SHUTTERS := [Color(0.25, 0.45, 0.32), Color(0.3, 0.45, 0.62), Color(0.47, 0.31, 0.2), Color(0.6, 0.22, 0.18)]
const GLASS_DARK := Color(0.13, 0.15, 0.19)


## Where the road drops away on a mountain stage (the ground 9 m out more than a
## metre below the road), a barrier along that edge, 0.6 m past it: armco (a steel
## W-beam on posts), or a low stone wall (through a village always). Hit it and it
## stops you, and keeps you on the mountain.
func _barriers() -> void:
	if st.kind == "highway":
		_highway_barriers()
		return
	if not st.mountain:
		return
	var touge: bool = st.kind == "touge"
	var n: int = st.pts.size()
	var body := StaticBody3D.new()
	body.name = "Barriers"
	body.set_meta("surface", "gravel")
	add_child(body)
	var steel := MeshBuf.new()
	var stone := MeshBuf.new()
	for side in [-1.0, 1.0]:
		var need := PackedByteArray()
		need.resize(n)
		for i in n:
			var s: float = i * st.STEP
			var c: Vector3 = st.pts[i]
			var extra: float = st.widths[i] * 0.5 - 2.8
			var p9: Vector3 = c + st.right_at(s) * ((9.0 + extra) * side)
			need[i] = 1 if c.y - _mountain_h(c.y, 9.0, p9) > 1.0 and s > st.START_S - 30.0 and s < st.length - 6.0 \
				and st.town_at(s, 8.0).is_empty() else 0         # (a town has its own barriers)
			if touge and s > st.START_S - 30.0 and s < st.length - 6.0 and absf(st.curv[i]) > 1.0 / 45.0 and signf(st.curv[i]) == -side:
				need[i] = 1                                  # (a pass has guardrail round the outside of every tight bend)
		# runs of it, grown 6 m each way; a short one isn't worth it
		var i := 0
		while i < n:
			if need[i] == 0:
				i += 1
				continue
			var j := i
			while j < n and need[j] == 1:
				j += 1
			var a := maxi(i - 3, 0)
			var b := mini(j + 3, n - 1)
			if (b - a) * st.STEP >= 14.0:
				var walled: bool = not st.village_at(a * st.STEP, 30.0).is_empty() or _rng.randf() < (0.15 if touge else 0.3)
				for k in range(a, b):
					_barrier_bit(k * st.STEP, (k + 1) * st.STEP, side, walled, stone if walled else steel, body)
			i = j + 1
	_add(steel, "", "Armco", WorldMaterials.steel({"painted": touge}))
	_add(stone, "", "StoneWalls")


## One 2 m piece of barrier, from s0 to s1 on `side`: armco or a stone wall, and its collision.
func _barrier_bit(s0: float, s1: float, side: float, walled: bool, mb, body: StaticBody3D) -> void:
	var d0: float = side * (st.width_at(s0) * 0.5 + 0.6)
	var d1: float = side * (st.width_at(s1) * 0.5 + 0.6)
	var e0: Vector3 = st.world_at(s0, d0) - Vector3.UP * 0.05
	var e1: Vector3 = st.world_at(s1, d1) - Vector3.UP * 0.05
	var r: Vector3 = st.right_at(s0) * side
	var touge: bool = st.kind == "touge"
	if walled:
		var shade := 0.9 + 0.2 * _rng.randf()
		var stone_col: Color = CONCRETE if touge else STONE     # (a touge's: a concrete parapet)
		_box(mb, e0 + Vector3.UP * 0.32, e1 + Vector3.UP * 0.32, r, 0.45, 0.8, _shade(stone_col, shade))
		_box(mb, e0 + Vector3.UP * 0.76, e1 + Vector3.UP * 0.76, r, 0.5, 0.1, _shade(stone_col, shade * 1.08))    # the coping
		_wall(body, (e0 + e1) * 0.5 + Vector3.UP * 0.4, e1 - e0, r, 0.45, 0.85)
	else:
		_box(mb, e0 - Vector3.UP * 0.3, e0 + Vector3.UP * 0.72, st.forward_at(s0), 0.1, 0.12, RAIL_WHITE if touge else POST)
		var beam := -r * 0.09                                  # the beam's on the road side of the posts
		_box(mb, e0 + beam + Vector3.UP * 0.58, e1 + beam + Vector3.UP * 0.58, r, 0.06, 0.32, RAIL_WHITE if touge else ARMCO)
		_wall(body, (e0 + e1) * 0.5 + Vector3.UP * 0.45, e1 - e0, r, 0.25, 0.9)


## The villages (StageGen.villages): houses close to the road on both sides, two
## storeys with shutters and tiled roofs, built into the hillside on a stone
## plinth; a church tower in the middle; a sign with the name on the way in.
## Every house is solid.
func _villages() -> void:
	if st.villages.is_empty():
		return
	var mb := MeshBuf.new()
	var body := StaticBody3D.new()
	body.name = "Village"
	body.set_meta("surface", "gravel")
	add_child(body)
	for v in st.villages:
		var mid: float = (v.s0 + v.s1) * 0.5
		var church_side := -1.0 if _rng.randf() < 0.5 else 1.0
		var at: float = v.s0 - 22.0
		_sign(at, st.width_at(at) * 0.5 + 1.4, v.name, Color(0.96, 0.96, 0.94))
		var s: float = v.s0
		while s < v.s1:
			for side in [-1.0, 1.0]:
				if side == church_side and absf(s - mid) < 14.0:
					continue
				if _rng.randf() < 0.82:
					_house(s, side, mb, body)
			s += _rng.randf_range(12.0, 16.0)
		_church(mid, church_side, mb, body)
	var mi := _add(mb, "", "Houses")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## A house at s on `side`: its front along the road, 2.6-4.5 m back from the edge.
func _house(s: float, side: float, mb, body: StaticBody3D) -> void:
	var along := _rng.randf_range(7.0, 10.0)
	var deep := _rng.randf_range(6.0, 8.0)
	var tall := _rng.randf_range(5.6, 7.6)
	var half_w: float = st.width_at(s) * 0.5
	var back := half_w + _rng.randf_range(2.6, 4.5)
	var wall: Color = HOUSE_WALLS[_rng.randi() % HOUSE_WALLS.size()]
	var roof: Color = ROOFS[_rng.randi() % ROOFS.size()]
	var shutter: Color = SHUTTERS[_rng.randi() % SHUTTERS.size()]
	_building(s, side, back, along, deep, tall, wall, roof, shutter, 2 if tall > 6.4 else 1, mb, body)


## The church: a square tower (bell openings, a pyramid roof) at the front, the
## nave behind it.
func _church(s: float, side: float, mb, body: StaticBody3D) -> void:
	var half_w: float = st.width_at(s) * 0.5
	var stone := Color(0.8, 0.75, 0.66)
	var c: Vector3 = _building(s, side, half_w + 12.0, 9.0, 13.0, 8.0, stone, ROOFS[0], Color(0, 0, 0, 0), 0, mb, body)
	# the tower, on the road side of the nave
	var f: Vector3 = st.forward_at(s)
	var r: Vector3 = st.right_at(s) * side
	var foot: Vector3 = st.world_at(s, side * (half_w + 8.0))
	if c == Vector3.INF or _near_road(foot, half_w + 6.0):
		return
	var road_y: float = st.point_at(s).y
	var low := minf(road_y, _ground_height(road_y, half_w + 8.0 - (half_w - 2.8), foot)) - 0.8
	var top := road_y + 15.0
	_box(mb, Vector3(foot.x, low, foot.z), Vector3(foot.x, top, foot.z), f, 4.2, 4.2, stone)
	for k in 4:                                          # the bell openings, one each side
		var out: Vector3 = [f, -f, r, -r][k]
		var w: Vector3 = out.cross(Vector3.UP).normalized() * 0.55
		var o: Vector3 = Vector3(foot.x, top - 2.2, foot.z) + out * 2.12
		_face(mb, o - w - Vector3.UP * 0.9, o + w - Vector3.UP * 0.9, o + w + Vector3.UP * 0.9, o - w + Vector3.UP * 0.9, out, GLASS_DARK)
	var apex := Vector3(foot.x, top + 4.5, foot.z)
	var h := 2.4
	var cs := [Vector3(foot.x, top, foot.z) + (f + r) * h, Vector3(foot.x, top, foot.z) + (f - r) * h,
		Vector3(foot.x, top, foot.z) + (-f - r) * h, Vector3(foot.x, top, foot.z) + (-f + r) * h]
	for k in 4:
		mb.tri_raw(cs[k], cs[(k + 1) % 4], apex, _shade(ROOFS[3], 0.9 + 0.1 * (k % 2)))
		mb.tri_raw(apex, cs[(k + 1) % 4], cs[k], _shade(ROOFS[3], 0.9 + 0.1 * (k % 2)))
	_wall(body, Vector3(foot.x, (low + top) * 0.5, foot.z), f * 4.2, r, 4.2, top - low)
	_clearings.append([Vector2(foot.x, foot.z), 5.0])


## A building at s on `side`, its front `back` m from the centre line, `along` x
## `deep` x `tall` m, a gabled roof (ridge along the road), on a stone plinth down
## to the ground under its lowest corner; windows with shutters on the front (rows:
## 0 = none), a door. Its centre, or Vector3.INF if another bit of road is there.
func _building(s: float, side: float, back: float, along: float, deep: float, tall: float, wall: Color, roof: Color,
		shutter: Color, rows: int, mb, body: StaticBody3D) -> Vector3:
	var f: Vector3 = st.forward_at(s)
	var r: Vector3 = st.right_at(s) * side                 # away from the road
	var c: Vector3 = st.world_at(s, side * (back + deep * 0.5))
	if _near_road(c, back + deep * 0.5 - 1.0):
		return Vector3.INF
	var road_y: float = st.point_at(s).y
	var extra: float = st.width_at(s) * 0.5 - 2.8
	var floor_y := road_y + 0.15
	var lowest := floor_y
	for a in [-0.5, 0.5]:
		for b in [-0.5, 0.5]:
			var q: Vector3 = c + f * (a * along) + r * (b * deep)
			lowest = minf(lowest, _ground_height(road_y, back + deep * (0.5 + b) - extra, q))
	var bottom := lowest - 0.6
	var eave := floor_y + tall
	_box(mb, Vector3(c.x, bottom, c.z), Vector3(c.x, floor_y + 0.25, c.z), f, along + 0.1, deep + 0.1, _shade(STONE, 0.95))
	_box(mb, Vector3(c.x, floor_y + 0.25, c.z), Vector3(c.x, eave, c.z), f, along, deep, wall)
	# the roof: two slopes and the gable ends, overhanging a little
	var o := 0.45
	var rise := deep * 0.3
	var e := Vector3(c.x, eave, c.z)
	var ridge0 := e - f * (along * 0.5 + o) + Vector3.UP * rise
	var ridge1 := e + f * (along * 0.5 + o) + Vector3.UP * rise
	for side_k in [-1.0, 1.0]:
		var lip: Vector3 = r * side_k * (deep * 0.5 + o) - Vector3.UP * 0.15
		var a0: Vector3 = e - f * (along * 0.5 + o) + lip
		var a1: Vector3 = e + f * (along * 0.5 + o) + lip
		_face(mb, a0, a1, ridge1, ridge0, (r * side_k + Vector3.UP).normalized(), _shade(roof, 1.0 if side_k < 0 else 0.86))
		_face(mb, a0, ridge0, ridge1, a1, -(r * side_k + Vector3.UP).normalized(), _shade(roof, 0.6))
	for end_k in [-1.0, 1.0]:
		var g0: Vector3 = e + f * (end_k * along * 0.5) - r * (deep * 0.5)
		var g1: Vector3 = e + f * (end_k * along * 0.5) + r * (deep * 0.5)
		var gt: Vector3 = e + f * (end_k * along * 0.5) + Vector3.UP * rise
		var out: Vector3 = f * end_k
		if (g1 - g0).cross(gt - g0).dot(out) < 0.0:
			mb.tri_raw(g0, gt, g1, wall)
		else:
			mb.tri_raw(g0, g1, gt, wall)
	# the front: windows with shutters, a door
	var front := c - r * (deep * 0.5 + 0.03)
	var cols := maxi(int(along / 2.4), 2)
	for row in rows:
		var y := floor_y + 1.4 + row * 2.7
		for k in cols:
			var x := (k - (cols - 1) * 0.5) * (along / cols)
			if row == 0 and k == cols / 2:
				var dc := Vector3(front.x, floor_y + 0.25, front.z) + f * x
				_face(mb, dc - f * 0.55, dc + f * 0.55, dc + f * 0.55 + Vector3.UP * 2.1, dc - f * 0.55 + Vector3.UP * 2.1, -r, _shade(SHUTTERS[2], 0.8))
				continue
			var wc := Vector3(front.x, y, front.z) + f * x
			_face(mb, wc - f * 0.45 - Vector3.UP * 0.6, wc + f * 0.45 - Vector3.UP * 0.6, wc + f * 0.45 + Vector3.UP * 0.6,
				wc - f * 0.45 + Vector3.UP * 0.6, -r, GLASS_DARK)
			for sk in [-1.0, 1.0]:
				var sc: Vector3 = wc + f * (sk * 0.7) - r * 0.02
				_face(mb, sc - f * 0.24 - Vector3.UP * 0.62, sc + f * 0.24 - Vector3.UP * 0.62, sc + f * 0.24 + Vector3.UP * 0.62,
					sc - f * 0.24 + Vector3.UP * 0.62, -r, shutter)
	_wall(body, Vector3(c.x, (bottom + eave) * 0.5, c.z), f * along, r, deep, eave - bottom)
	_clearings.append([Vector2(c.x, c.z), maxf(along, deep) * 0.75])
	return c


# ── towns ─────────────────────────────────────────────────────────────────

const PAVEMENT := Color(0.62, 0.62, 0.6)
const KERB := Color(0.8, 0.8, 0.77)
const COBBLES := [Color(0.56, 0.51, 0.45), Color(0.62, 0.56, 0.48)]
const FENCE := Color(0.72, 0.74, 0.76)
const PAVE_W := 1.6                 # the pavement's width (m)
const PAVE_H := 0.12                # the kerb's height
var _town_spots: Array = []         # crowds in town: [s, side, how many, m out] (_spectators)


## The towns (StageGen.towns): both sides of the road a raised pavement with a
## kerb, crowd barriers along it (the whole way through: the side streets are
## closed), buildings shoulder to shoulder behind it, 2-3 storeys, on stone plinths
## down to the hillside; a side street or two between them (a stub of road) and the
## square (cobbles, a fountain, a crowd); a name sign on the way in. All solid.
func _towns() -> void:
	if st.towns.is_empty():
		return
	var mb := MeshBuf.new()
	var pave := MeshBuf.new()
	var squares := MeshBuf.new()
	var body := StaticBody3D.new()
	body.name = "Town"
	body.set_meta("surface", "gravel")
	add_child(body)
	for t in st.towns:
		var at: float = t.s0 - 26.0
		_sign(at, st.width_at(at) * 0.5 + 1.4, t.name, Color(0.96, 0.96, 0.94))
		var gaps: Array = [[t.square_s - 12.0, t.square_s + 12.0, t.square_side]]
		for sd in t.streets:
			gaps.append([sd[0] - 4.5, sd[0] + 4.5, sd[1]])
		for side in [-1.0, 1.0]:
			var s: float = t.s0 - 8.0
			while s < t.s1 + 8.0 - 0.01:
				var s2: float = minf(s + st.STEP, t.s1 + 8.0)
				_pavement_bit(s, s2, side, pave)
				_fence_bit(s, s2, side, mb, body)
				s = s2
			# the buildings, shoulder to shoulder, the gaps left open
			s = t.s0
			while s < t.s1:
				var w := _rng.randf_range(6.5, 10.0)
				var clear := true
				for g in gaps:
					if g[2] == side and s + w > g[0] and s < g[1]:
						clear = false
				if clear:
					var mid := s + w * 0.5
					var tall := _rng.randf_range(6.6, 10.4)
					_building(mid, side, st.width_at(mid) * 0.5 + PAVE_W + 0.2, w - 0.15, _rng.randf_range(8.0, 10.0), tall,
						HOUSE_WALLS[_rng.randi() % HOUSE_WALLS.size()], ROOFS[_rng.randi() % ROOFS.size()],
						SHUTTERS[_rng.randi() % SHUTTERS.size()], 3 if tall > 9.0 else 2, mb, body)
				s += w
			# a crowd on the pavement here and there, behind the barrier
			for k in 2:
				_town_spots.append([lerpf(t.s0, t.s1, _rng.randf_range(0.1, 0.9)), side, 6 + _rng.randi() % 5, st.width_at(t.s0) * 0.5 + 1.0])
		_square(t.square_s, t.square_side, squares, mb, body)
		for sd in t.streets:
			_side_street(sd[0], sd[1], squares)
		# no trees in town
		var cs: float = t.s0 - 24.0
		while cs < t.s1 + 24.0:
			for side in [-1.0, 1.0]:
				var p: Vector3 = st.world_at(cs, side * (st.width_at(cs) * 0.5 + 9.0))
				_clearings.append([Vector2(p.x, p.z), 12.0])
			cs += 8.0
	_add(pave, "asphalt", "Pavements")
	_add(squares, "asphalt", "TownSquares")
	var mi := _add(mb, "", "TownBuildings")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## A town point: road coordinates (s, d), h m above the road's centre line.
func _tp(s: float, d: float, h: float) -> Vector3:
	return st.world_at(s, d) + Vector3.UP * h


## 2 m of pavement on `side`: the kerb's face, the top, the back down to the ground.
func _pavement_bit(s0: float, s1: float, side: float, mb) -> void:
	var h0: float = st.width_at(s0) * 0.5
	var h1: float = st.width_at(s1) * 0.5
	var shade := 0.95 + 0.05 * sin(s0 * 1.7)
	var a0 := _tp(s0, side * h0, PAVE_H)
	var a1 := _tp(s1, side * h1, PAVE_H)
	var b0 := _tp(s0, side * (h0 + PAVE_W), PAVE_H)
	var b1 := _tp(s1, side * (h1 + PAVE_W), PAVE_H)
	mb.quad(a0, b0, b1, a1, _shade(PAVEMENT, shade), true)
	var out: Vector3 = -st.right_at(s0) * side
	_face(mb, _tp(s0, side * h0, -0.02), _tp(s1, side * h1, -0.02), a1, a0, out, KERB)
	_face(mb, b0, b1, _tp(s1, side * (h1 + PAVE_W), -0.8), _tp(s0, side * (h0 + PAVE_W), -0.8), -out, _shade(STONE, 0.9))
	# the kerb's face is solid too (a wheel hits it)
	mb.faces.append_array(PackedVector3Array([_tp(s0, side * h0, -0.02), _tp(s1, side * h1, -0.02), a1, _tp(s0, side * h0, -0.02), a1, a0]))


## 2 m of crowd barrier on the pavement (steel rails and bars between posts), solid.
func _fence_bit(s0: float, s1: float, side: float, mb, body: StaticBody3D) -> void:
	var e0 := _tp(s0, side * (st.width_at(s0) * 0.5 + 0.35), PAVE_H)
	var e1 := _tp(s1, side * (st.width_at(s1) * 0.5 + 0.35), PAVE_H)
	var r: Vector3 = st.right_at(s0) * side
	_box(mb, e0, e0 + Vector3.UP * 1.1, st.forward_at(s0), 0.05, 0.05, POST)
	for y in [0.15, 1.05]:
		_box(mb, e0 + Vector3.UP * y, e1 + Vector3.UP * y, r, 0.04, 0.05, FENCE)
	for k in range(1, 4):                                # the bars between (you see through it)
		var b: Vector3 = e0.lerp(e1, k / 4.0)
		_box(mb, b + Vector3.UP * 0.15, b + Vector3.UP * 1.05, st.forward_at(s0), 0.025, 0.025, FENCE)
	_wall(body, (e0 + e1) * 0.5 + Vector3.UP * 0.55, e1 - e0, r, 0.2, 1.1)


## The town square at s on `side`: cobbles behind the pavement, 24 m along the
## road and 16 m deep, a fountain in the middle, a crowd.
func _square(s: float, side: float, mb, deco, body: StaticBody3D) -> void:
	var half: float = st.width_at(s) * 0.5
	var d0 := half + PAVE_W
	for i in 12:
		for j in 8:
			var sa := s - 12.0 + i * 2.0
			var da := d0 + j * 2.0
			var col: Color = COBBLES[(i + j) % 2] * (0.95 + 0.08 * _rng.randf())
			col.a = 1.0
			mb.quad(_tp(sa, side * da, PAVE_H), _tp(sa, side * (da + 2.0), PAVE_H), _tp(sa + 2.0, side * (da + 2.0), PAVE_H),
				_tp(sa + 2.0, side * da, PAVE_H), col, true)
	# its edge: a plinth down to the hillside
	for i in 12:
		var sa := s - 12.0 + i * 2.0
		_face(mb, _tp(sa, side * (d0 + 16.0), PAVE_H), _tp(sa + 2.0, side * (d0 + 16.0), PAVE_H), _tp(sa + 2.0, side * (d0 + 16.0), -3.0),
			_tp(sa, side * (d0 + 16.0), -3.0), st.right_at(sa) * side, _shade(STONE, 0.85))
	# the fountain: an eight-sided basin, a column, water
	var c := _tp(s, side * (d0 + 8.0), PAVE_H)
	for k in 8:
		var a0 := TAU * k / 8.0
		var a1 := TAU * (k + 1) / 8.0
		var p0 := c + Vector3(cos(a0), 0.0, sin(a0)) * 2.2
		var p1 := c + Vector3(cos(a1), 0.0, sin(a1)) * 2.2
		_face(deco, p0, p1, p1 + Vector3.UP * 0.6, p0 + Vector3.UP * 0.6, (p0 + p1 - c * 2.0).normalized(), _shade(STONE, 1.05))
		deco.tri(c + Vector3.UP * 0.45, p0 + Vector3.UP * 0.45, p1 + Vector3.UP * 0.45, Color(0.25, 0.4, 0.45))
	_box(deco, c, c + Vector3.UP * 2.4, Vector3.RIGHT, 0.5, 0.5, _shade(STONE, 1.1))
	_wall(body, c + Vector3.UP * 0.6, Vector3.FORWARD * 4.2, Vector3.RIGHT, 4.2, 1.2)
	_town_spots.append([s + 6.0, side, 14, d0 + 4.5])
	_town_spots.append([s - 6.0, side, 10, d0 + 3.5])


## A side street at s on `side`: a 6 m stub of road between the buildings, behind the pavement.
func _side_street(s: float, side: float, mb) -> void:
	var half: float = st.width_at(s) * 0.5
	var d0 := half + PAVE_W
	var col := ASPHALT * 1.05
	col.a = 1.0
	mb.quad(_tp(s - 3.2, side * d0, PAVE_H - 0.01), _tp(s - 3.2, side * (d0 + 16.0), PAVE_H - 0.01),
		_tp(s + 3.2, side * (d0 + 16.0), PAVE_H - 0.01), _tp(s + 3.2, side * d0, PAVE_H - 0.01), col, true)


# ── puddles, arches ───────────────────────────────────────────────────────

# ── bridges ───────────────────────────────────────────────────────────────

const PLANK := 0.33                 # m of deck per plank, along the road
const DECK_TOP := 0.05              # the deck's top above the road's centre line (level with the crown)
const DECK_DEPTH := 0.28            # the deck's planks and joists, top to underside
const WOOD := [Color(0.47, 0.33, 0.2), Color(0.52, 0.37, 0.22), Color(0.43, 0.3, 0.18), Color(0.55, 0.4, 0.25)]
const TIMBER := Color(0.52, 0.38, 0.24)
const MUD := Color(0.33, 0.27, 0.2)


## Each bridge: a plank deck the car drives on (surface "wood") with timber wheel
## guards along its edges, posts and two rails each side (hit them and they
## stop you), joists and trestles with cross braces down to the gully floor,
## the floor (mud) and the stream.
func _bridges() -> void:
	for bi in st.bridges.size():
		var b: Dictionary = st.bridges[bi]
		var deck := MeshBuf.new()
		var frame := MeshBuf.new()
		var floor_mb := MeshBuf.new()
		var rails := StaticBody3D.new()
		rails.name = "BridgeRails%d" % bi
		rails.set_meta("surface", "wood")
		add_child(rails)
		# the planks
		var s: float = b.s0
		var k := 0
		while s < b.s1 - 0.01:
			var s2: float = minf(s + PLANK, b.s1)
			var h0 := _deck_half(s)
			var h1 := _deck_half(s2)
			var col: Color = WOOD[k % WOOD.size()] * (0.93 + 0.14 * _rng.randf())
			col.a = 1.0
			deck.quad(_deck(s, -h0), _deck(s, h0), _deck(s2, h1), _deck(s2, -h1), col, true)
			s = s2
			k += 1
		# along it, every 2 m: the deck's edge boards, the wheel guards, posts and rails, joists
		var n := int(round((b.s1 - b.s0) / st.STEP))
		for j in n + 1:
			var sa: float = b.s0 + j * st.STEP
			var r: Vector3 = st.right_at(sa)
			for side in [-1.0, 1.0]:
				var edge: Vector3 = _deck(sa, side * _deck_half(sa))
				var post: Vector3 = edge + r * side * 0.1
				_box(frame, post - Vector3.UP * DECK_DEPTH, post + Vector3.UP * 1.05, r, 0.13, 0.13, TIMBER)
				if j == n:
					continue
				var sb: float = sa + st.STEP
				var edge2: Vector3 = _deck(sb, side * _deck_half(sb))
				var post2: Vector3 = edge2 + st.right_at(sb) * side * 0.1
				_face(frame, edge, edge2, edge2 - Vector3.UP * DECK_DEPTH, edge - Vector3.UP * DECK_DEPTH, r * side, _shade(TIMBER, 0.9))
				var guard: Vector3 = r * side * 0.12
				_box(frame, edge - guard + Vector3.UP * 0.09, edge2 - guard + Vector3.UP * 0.09, r, 0.2, 0.18, _shade(TIMBER, 1.1))
				for y in [0.55, 0.98]:
					_box(frame, post + Vector3.UP * y, post2 + Vector3.UP * y, r, 0.08, 0.13, TIMBER)
				var joist: Vector3 = r * side * 0.5
				_box(frame, edge - joist - Vector3.UP * (DECK_DEPTH + 0.12), edge2 - joist - Vector3.UP * (DECK_DEPTH + 0.12), r, 0.2, 0.24, _shade(TIMBER, 0.8))
				# the rail's collision: a 1 m wall along the segment, and the wheel guard
				_wall(rails, (post + post2) * 0.5 + Vector3.UP * 0.55, post2 - post, r, 0.16, 1.0)
				_wall(rails, (edge + edge2) * 0.5 - guard + Vector3.UP * 0.09, edge2 - edge, r, 0.2, 0.18)
			# a trestle every 4 m where the gully is deep enough
			if j % 2 == 1 and st.gully_depth(sa, 0.0) > 0.6:
				var half := _deck_half(sa) - 0.5
				var top_l := _deck(sa, -half) - Vector3.UP * (DECK_DEPTH + 0.24)
				var top_r := _deck(sa, half) - Vector3.UP * (DECK_DEPTH + 0.24)
				var foot_l := _gully_floor(sa, -half) - Vector3.UP * 0.3
				var foot_r := _gully_floor(sa, half) - Vector3.UP * 0.3
				var fwd: Vector3 = st.forward_at(sa)
				_box(frame, foot_l, top_l, fwd, 0.22, 0.22, TIMBER)
				_box(frame, foot_r, top_r, fwd, 0.22, 0.22, TIMBER)
				_box(frame, top_l - r * 0.3, top_r + r * 0.3, fwd, 0.22, 0.2, _shade(TIMBER, 0.85))
				if top_l.y - foot_l.y > 1.4:
					_box(frame, foot_l + Vector3.UP * 0.5, top_r - Vector3.UP * 0.2, fwd, 0.09, 0.12, _shade(TIMBER, 0.75))
					_box(frame, foot_r + Vector3.UP * 0.5, top_l - Vector3.UP * 0.2, fwd, 0.09, 0.12, _shade(TIMBER, 0.75))
		# the gully floor under the deck (the ground's ribbons stop at the road's edges)
		for j in n:
			var sa: float = b.s0 + j * st.STEP
			var sb: float = sa + st.STEP
			var ha: float = st.width_at(sa) * 0.5 + 0.1
			var hb: float = st.width_at(sb) * 0.5 + 0.1
			floor_mb.quad(_gully_floor(sa, -ha), _gully_floor(sa, ha), _gully_floor(sb, hb), _gully_floor(sb, -hb), MUD, true)
		var dm := _add(deck, "wood", "BridgeDeck%d" % bi)
		dm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_add(frame, "", "BridgeFrame%d" % bi)
		_add(floor_mb, "mud", "GullyFloor%d" % bi)
		_stream(b, bi)


## The stream along the bottom of a bridge's gully: a flat sheet of water.
func _stream(b: Dictionary, bi: int) -> void:
	var len: float = b.s1 - b.s0
	var sa: float = b.s0 + len * 0.28
	var sb: float = b.s1 - len * 0.28
	var y: float = st.point_at((b.s0 + b.s1) * 0.5).y - 0.03 - b.depth + 0.35
	var corners: Array = []
	for p in [st.world_at(sa, -60.0), st.world_at(sa, 60.0), st.world_at(sb, 60.0), st.world_at(sb, -60.0)]:
		corners.append(Vector3(p.x, y, p.z))
	var mb := MeshBuf.new()
	mb.quad(corners[0], corners[1], corners[2], corners[3], Color(0.13, 0.22, 0.22))
	var mi := MeshInstance3D.new()
	mi.name = "Stream%d" % bi
	mi.mesh = mb.mesh()
	mi.material_override = WorldMaterials.water()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Half the deck's width at s: the road's, and a little more.
func _deck_half(s: float) -> float:
	return st.width_at(s) * 0.5 + 0.25


## A point on the deck's top (road coordinates s, d).
func _deck(s: float, d: float) -> Vector3:
	var p: Vector3 = st.world_at(s, d)
	return Vector3(p.x, st.point_at(s).y + DECK_TOP, p.z)


## The gully's floor under the road (road coordinates s, d).
func _gully_floor(s: float, d: float) -> Vector3:
	var p: Vector3 = st.world_at(s, d)
	return Vector3(p.x, st.point_at(s).y + GROUND_X[0][1] - st.gully_depth(s, d), p.z)


## A box from a to b (its centre line), w wide (along `side`) and h tall.
func _box(mb, a: Vector3, b: Vector3, side: Vector3, w: float, h: float, col: Color) -> void:
	var along := (b - a).normalized()
	var up := along.cross(side).normalized()
	side = up.cross(along).normalized()
	var hw := side * (w * 0.5)
	var hh := up * (h * 0.5)
	var c := [a - hw - hh, a + hw - hh, a + hw + hh, a - hw + hh, b - hw - hh, b + hw - hh, b + hw + hh, b - hw + hh]
	_face(mb, c[1], c[5], c[6], c[2], side, col)
	_face(mb, c[0], c[3], c[7], c[4], -side, col)
	_face(mb, c[3], c[2], c[6], c[7], up, _shade(col, 1.08))
	_face(mb, c[0], c[4], c[5], c[1], -up, _shade(col, 0.8))
	_face(mb, c[0], c[1], c[2], c[3], -along, _shade(col, 0.9))
	_face(mb, c[4], c[7], c[6], c[5], along, _shade(col, 0.9))


## A quad facing `out` (whichever way round its corners come).
func _face(mb, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(out) < 0.0:
		mb.quad(a, d, c, b, col)
	else:
		mb.quad(a, b, c, d, col)


## A collision box on `body`: centred at c, `along` long (and pointing that way),
## thick across (`side`) and tall.
func _wall(body: StaticBody3D, c: Vector3, along: Vector3, side: Vector3, thick: float, tall: float) -> void:
	var z := along.normalized()
	var x := Vector3.UP.cross(z).normalized()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(thick, tall, along.length())
	cs.shape = box
	cs.transform = Transform3D(Basis(x, z.cross(x), z), c)
	body.add_child(cs)


static func _shade(col: Color, k: float) -> Color:
	return Color(col.r * k, col.g * k, col.b * k, 1.0)


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
	mi.material_override = WorldMaterials.puddle()
	add_child(mi)


func _arches() -> void:
	_arch(st.START_S + 2.0, "START", Color(0.85, 0.15, 0.12))
	_arch(st.finish_s, "GOAL" if st.kind == "touge" else "FINISH", Color(0.1, 0.35, 0.8))
	var sd: float = maxf(st.width_at(st.finish_s) * 0.5 + 1.0, 3.8)
	_sign(st.finish_s - 100.0, sd, "FLYING FINISH 100", Color(0.95, 0.8, 0.1))
	_sign(st.finish_s + 70.0, sd, "STOP", Color(0.85, 0.12, 0.1))
	# the start clocks: one each side of the line (in front of the arch posts, which
	# used to hide them), turned toward the car so both crew can read the count
	var cd: float = maxf(st.width_at(st.START_S) * 0.5 + 0.5, 3.3)
	for d in [-cd, cd]:
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
		pole.position = st.world_at(s, side * maxf(st.width_at(s) * 0.5 + 0.8, 3.6)) + Vector3.UP * 2.3
		add_child(pole)
	var banner := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(maxf(st.width_at(s) + 2.0, 7.6), 0.9, 0.15)
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


# ── highway and touge roadside ────────────────────────────────────────────

## A highway's concrete barriers (New Jersey profile: a wide foot, a narrower
## wall), both sides the whole way, just past the shoulders; solid in 8 m pieces.
func _highway_barriers() -> void:
	var body := StaticBody3D.new()
	body.name = "Barriers"
	body.set_meta("surface", "gravel")
	add_child(body)
	var mb := MeshBuf.new()
	var n: int = st.pts.size()
	for side in [-1.0, 1.0]:
		var i := 0
		while i < n - 1:
			var j := mini(i + 4, n - 1)
			var s0: float = i * st.STEP
			var s1: float = j * st.STEP
			var e0: Vector3 = st.world_at(s0, side * (st.width_at(s0) * 0.5 + 0.45))
			var e1: Vector3 = st.world_at(s1, side * (st.width_at(s1) * 0.5 + 0.45))
			var r: Vector3 = st.right_at(s0) * side
			_box(mb, e0 + Vector3.UP * 0.14, e1 + Vector3.UP * 0.14, r, 0.62, 0.28, CONCRETE)
			_box(mb, e0 + Vector3.UP * 0.56, e1 + Vector3.UP * 0.56, r, 0.26, 0.56, _shade(CONCRETE, 1.05))
			_wall(body, (e0 + e1) * 0.5 + Vector3.UP * 0.45, e1 - e0, r, 0.5, 0.9)
			i = j
	_add(mb, "", "ConcreteBarriers")


## What stands beside the road: a highway's lamp posts and distance gantries; a
## touge's curve mirrors and chevrons at the hairpins, kilometre posts, the pass's
## name board and a vending machine at the start.
func _roadside() -> void:
	if st.kind == "highway":
		_highway_props()
	elif st.kind == "touge":
		_touge_props()


const LAMP := Color(0.55, 0.57, 0.6)
const GANTRY_GREEN := Color(0.05, 0.38, 0.2)


func _highway_props() -> void:
	var mb := MeshBuf.new()
	var s: float = st.START_S + 30.0
	while s < st.length - 20.0:
		var half: float = st.width_at(s) * 0.5
		var base: Vector3 = st.world_at(s, -(half + 1.3))
		var r: Vector3 = st.right_at(s)
		_box(mb, base, base + Vector3.UP * 9.0, st.forward_at(s), 0.18, 0.18, LAMP)
		_box(mb, base + Vector3.UP * 9.0, base + Vector3.UP * 9.0 + r * 2.4, Vector3.UP, 0.12, 0.12, LAMP)
		_box(mb, base + Vector3.UP * 8.9 + r * 2.2, base + Vector3.UP * 8.9 + r * 2.9, Vector3.UP, 0.35, 0.16, Color(0.9, 0.88, 0.75))
		s += 70.0
	_add(mb, "", "LampPosts")
	# distance gantries: every 2 km, how far to the finish
	var g := MeshBuf.new()
	var gs: float = st.START_S + 600.0
	while gs < st.finish_s - 300.0:
		var half2: float = st.width_at(gs) * 0.5 + 1.6
		var a: Vector3 = st.world_at(gs, -half2)
		var b: Vector3 = st.world_at(gs, half2)
		var f: Vector3 = st.forward_at(gs)
		for p in [a, b]:
			_box(g, p, p + Vector3.UP * 6.6, f, 0.35, 0.35, LAMP)
		_box(g, a + Vector3.UP * 6.4, b + Vector3.UP * 6.4, Vector3.UP, 0.4, 0.3, LAMP)
		var mid: Vector3 = st.world_at(gs, -st.LANE_W)
		_box(g, mid + Vector3.UP * 5.4 - st.right_at(gs) * 3.2, mid + Vector3.UP * 5.4 + st.right_at(gs) * 3.2, -f, 0.08, 1.7, GANTRY_GREEN)
		var lab := Label3D.new()
		lab.text = "FINISH  %.0f km" % ((st.finish_s - gs) / 1000.0)
		lab.font_size = 96
		lab.pixel_size = 0.009
		lab.modulate = Color(0.97, 0.97, 0.95)
		lab.outline_size = 0
		lab.position = mid + Vector3.UP * 5.4 - f * 0.06
		lab.rotation.y = -st.heading_at(gs)
		add_child(lab)
		gs += 2000.0
	_add(g, "", "Gantries")


const MIRROR_ORANGE := Color(0.95, 0.42, 0.08)
const CHEVRON_YELLOW := Color(0.98, 0.82, 0.1)


func _touge_props() -> void:
	var mb := MeshBuf.new()
	var shiny := StandardMaterial3D.new()
	shiny.albedo_color = Color(0.82, 0.86, 0.9)
	shiny.metallic = 1.0
	shiny.roughness = 0.08
	for c in st.corners:
		if c.r_min > 30.0:
			continue
		var mid: float = (c.s0 + c.s1) * 0.5
		var out_side: float = -float(c.dir)                  # (a right-hander's outside is on the left)
		var half: float = st.width_at(mid) * 0.5
		# the curve mirror on the outside of the apex, turned to show what's coming round
		var base: Vector3 = st.world_at(mid, out_side * (half + 1.5))
		_box(mb, base, base + Vector3.UP * 3.0, st.forward_at(mid), 0.09, 0.09, MIRROR_ORANGE)
		var mirror := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.42
		cm.bottom_radius = 0.42
		cm.height = 0.05
		mirror.mesh = cm
		mirror.material_override = shiny
		mirror.position = base + Vector3.UP * 3.2
		var face: Vector3 = (st.world_at(mid, 0.0) - base).normalized()
		mirror.basis = Basis.looking_at(face, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
		add_child(mirror)
		_box(mb, base + Vector3.UP * 3.2 - face * 0.03, base + Vector3.UP * 3.2 - face * 0.06, Vector3.UP, 0.95, 0.95, MIRROR_ORANGE)
		# chevrons along the outside: yellow boards, the arrow pointing the way it turns
		for k in range(-2, 3):
			var cs: float = clampf(mid + k * 9.0, c.s0, c.s1)
			var p: Vector3 = st.world_at(cs, out_side * (half + 1.0))
			_box(mb, p, p + Vector3.UP * 1.1, st.forward_at(cs), 0.07, 0.07, RAIL_WHITE)
			var board_c: Vector3 = p + Vector3.UP * 1.35
			_box(mb, board_c - st.right_at(cs) * 0.02, board_c + st.right_at(cs) * 0.02, -st.forward_at(cs), 0.55, 0.45, CHEVRON_YELLOW)
			var arrow := Label3D.new()
			arrow.text = ">" if c.dir > 0 else "<"
			arrow.font_size = 96
			arrow.pixel_size = 0.006
			arrow.modulate = Color(0.05, 0.05, 0.05)
			arrow.outline_size = 0
			arrow.position = board_c - st.forward_at(cs) * 0.04
			arrow.rotation.y = -st.heading_at(cs)
			add_child(arrow)
	# kilometre posts: every 500 m on the left
	var s: float = st.START_S + 500.0
	while s < st.finish_s:
		var p: Vector3 = st.world_at(s, -(st.width_at(s) * 0.5 + 0.9))
		_box(mb, p, p + Vector3.UP * 0.9, st.forward_at(s), 0.14, 0.14, RAIL_WHITE)
		var km := Label3D.new()
		km.text = "%.1f" % ((s - st.START_S) / 1000.0)
		km.font_size = 40
		km.pixel_size = 0.005
		km.modulate = Color(0.1, 0.25, 0.6)
		km.outline_size = 0
		km.position = p + Vector3.UP * 0.7 - st.forward_at(s) * 0.08
		km.rotation.y = -st.heading_at(s)
		add_child(km)
		s += 500.0
	# the pass's name board and a vending machine by the start
	_sign(st.START_S - 18.0, -(st.width_at(st.START_S) * 0.5 + 1.6), st.touge_name(), Color(0.45, 0.28, 0.16))
	var vm_at: Vector3 = st.world_at(st.START_S - 10.0, st.width_at(st.START_S) * 0.5 + 2.4)
	var f2: Vector3 = st.forward_at(st.START_S - 10.0)
	_box(mb, vm_at, vm_at + Vector3.UP * 1.8, f2, 0.9, 0.75, Color(0.92, 0.18, 0.15))
	_box(mb, vm_at + Vector3.UP * 0.5 - st.right_at(st.START_S) * 0.39, vm_at + Vector3.UP * 1.6 - st.right_at(st.START_S) * 0.39, f2, 0.7, 0.04, Color(0.75, 0.9, 1.0))
	_add(mb, "", "TougeProps")


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
	elif mood == "night":
		rock = Color(0.012, 0.015, 0.022)               # (dark against the night sky)
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
## the trees, warm and long-shadowed), "overcast" (grey sky, soft light, fog): a
## photographed sky, the sun where it is in the photo, the graphics quality's shadows
## and effects (WorldMaterials.setup).
func _environment() -> void:
	var w: Dictionary = WorldMaterials.setup(self, mood)
	mood = w.mood
	_horizon = w.horizon
