extends RefCounted
## The city's streets on the LAKESHORE LOOP (cut up), and what's on them: a grid under the
## expressway's viaduct (LoopBuilder._city), drawn cheaply. Static, called from LoopBuilder._city:
##
##   CityStreets.plan(builder) -> Dictionary: where the streets go, before any building is placed
##     (the buildings keep off them: its "foot", CitySkyline's footprints in 100 m cells), and the
##     billboards by the expressway
##   CityStreets.fill(builder, plan, placed) -> {xfs, cols, tops}: the blocks' gaps filled with drawn
##     buildings (the towers' box and its window shader), once the front rows and the far tier stand
##   CityStreets.dress(builder, plan, tops, night): the streets drawn, their lamps, trees, parked
##     cars, the signs on the roofs and the billboards
##
## The grid, in road coordinates (s along the expressway, d across it), both sides:
##   * long streets at LONG m from the road's middle (between the front rows and the far tier,
##     and further out): none beside the viaduct (a street there took the front rows' best plots:
##     the buildings the road sees)
##   * cross streets every BLOCK m of road, from beside the viaduct (VIADUCT_GAP m out from its
##     barrier) out to the city's edge (straight: a line of constant s), meeting each long street
##     at its kerb (a zebra there)
##   * none in the water, off the city's ground, up the hills at its ends, on a ramp, nearer
##     another part of the road than its own, at the gas station, under an overpass's pier
## A street: a road (a lane each way and a parking strip each side, ROAD_HALF m to the kerb) and
## a pavement (WALK m), one strip of triangles on the ground as drawn, its markings and paving
## from a shader (no texture), pulled a hair toward the camera so the land never shows through.
## On it: lamps every LAMP_EVERY m (sides in turn, an arm over the lane; at night the head glows
## and the shader lays its pool on the street: no real lights), trees in the pavement, cars parked
## in the strips (stand-ins in the sizes and paints of the traffic's cars that can be shown:
## low boxes, each a few dozen triangles; the real models are tens of thousands each). Signs:
## on some roofs near the road, and billboards on poles by the expressway, their boards above
## the sound walls (generic shop words from tools/city_signs.py: no real names); lit at night.
## The same city every time (its own dice). The node "CityStreets" keeps what it placed in its
## metas for the tests (tests/city_check.gd).

const EnvAssets = preload("res://scripts/stage/env_assets.gd")
const Graphics = preload("res://scripts/render/graphics.gd")
const CitySkyline = preload("res://scripts/stage/city_skyline.gd")
const VehicleRegistry = preload("res://scripts/game/vehicle_registry.gd")

const VIADUCT_GAP := 3.0             # m from the viaduct's outer barrier: where a cross street starts
const LONG := [195.0, 420.0]         # m from the road's middle: the long streets (between the front rows and the far tier, and further out)
const EDGE := 600.0                  # m: no street further out (the city's 650 m round its middle)
const BLOCK := Vector2(115.0, 165.0) # m of road between two cross streets
const ROAD_HALF := 5.0               # m: half a street's road (a 3 m lane, a 2 m parking strip)
const LANE := 3.0
const WALK := 2.5                    # m: the pavement each side
const HALF := ROAD_HALF + WALK
const STEP := 8.0                    # m between a street's samples
const MIN_RUN := 40.0                # m: a shorter piece isn't drawn
const PIECE := 400.0                 # m: a long street drawn in pieces this long (each culled on its own)
const LAMP_EVERY := 34.0             # m along a street (each side every other one)
const LAMP_REACH := 2.0              # m: the arm, from the kerb out over the lane
const TREE_EVERY := 18.0
const PARK_EVERY := 6.0              # m: a parking space
const BOARD_EVERY := Vector2(260.0, 420.0)   # m of road between two billboards on a side
const BOARD := Vector2(14.0, 7.0)    # m: a billboard's board
const BOARD_OUT := 20.0              # m past the viaduct's outer barrier: a billboard's pole
const BOARD_UP := 11.0               # m: its foot over the road (seen over the 4.1 m sound walls from a car's seat)
const GAP := 4.0                     # m between two of the fill's buildings (and from the others)
const FILL_IN := 16.0                # m past the viaduct's outer barrier: the fill's nearest
const NAME := "CityStreets"
const SIGNS := 32                    # faces in the signs' image (tools/city_signs.py: 4 x 8)
const CELL := 300.0                  # m: the trees and parked cars drawn in squares this big (each culled on its own), the lamps in twice that

## Sizes of the parked cars' stand-ins by the traffic's type: length, width, height (m).
const CAR_SIZE := {"compact": Vector3(3.9, 1.72, 1.48), "sedan": Vector3(4.75, 1.8, 1.45), "luxury": Vector3(5.0, 1.88, 1.47),
	"suv": Vector3(4.85, 1.95, 1.75), "crossover": Vector3(4.5, 1.85, 1.62), "van": Vector3(4.9, 1.9, 1.95), "minivan": Vector3(4.9, 1.9, 1.75)}

static var _street_shader: Shader = null
static var _thing_shader: Shader = null
static var _sign_shader: Shader = null


# ── the plan ────────────────────────────────────────────────────────────

static func plan(b) -> Dictionary:
	var st = b.st
	var out := {"runs": [], "foot": {}, "streets": [], "boards": [], "zones": [], "piers": [], "blockers": [], "crowded": _crowded(st)}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([st.seed_used, "streets"])
	_blockers(b, out)
	for z in _zones(st):
		var s0: float = z[0]
		var s1: float = z[1]
		var longs := []                                     # [d, side, (unused: false)]
		for side in [1.0, -1.0]:
			for dd in LONG:
				longs.append([float(dd) * side, side, false])
		var n := int((s1 - s0) / STEP)
		var ground := []                                    # per long street: its samples' ground (NAN: no street there)
		for l in longs:
			var arr := PackedFloat32Array()
			arr.resize(n + 1)
			for k in n + 1:
				arr[k] = _ok(b, out, s0 + k * STEP, float(l[0]))
			ground.append(arr)
		var cross := []
		var s := s0 + rng.randf_range(40.0, 90.0)
		while s < s1 - 40.0:
			cross.append(s)
			s += rng.randf_range(BLOCK.x, BLOCK.y)
		var mouths := {}                                    # long street -> [[s, its side the cross street's on]]
		for cs in cross:
			for side in [1.0, -1.0]:
				_cross(b, out, longs, ground, s0, cs, side, mouths)
		for li in longs.size():
			_long(b, out, longs[li], ground[li], s0, mouths.get(li, []))
		out.zones.append({"s0": s0, "s1": s1, "longs": longs, "cross": cross})
		_boards(b, out, s0, s1, rng)
	return out


## The city's stretches of road, a stretch across the loop's start joined into one (s past the
## loop's length: world_at wraps).
static func _zones(st) -> Array:
	var out := []
	for z in st.zones:
		if z.kind == "city":
			out.append([float(z.s0), float(z.s1)])
	for a in out.duplicate():
		for c in out.duplicate():
			if a != c and absf(float(a[1]) - st.length) < 1.0 and float(c[0]) < 1.0:
				out.erase(a)
				out.erase(c)
				out.append([float(a[0]), st.length + float(c[1])])
				return out
	return out


## Per 50 m of road (wrapped): 1 where another part of the loop comes within the streets'
## reach of it (EDGE and a margin), else 0 (nothing to check there).
static func _crowded(st) -> PackedByteArray:
	var bins := int(ceil(st.length / 50.0))
	var out := PackedByteArray()
	out.resize(bins)
	out.fill(0)
	var every := maxi(int(50.0 / st.STEP), 1)
	var window := int((EDGE + 150.0) / st.STEP)
	var reach := EDGE + 120.0
	for i in range(0, st._n, every):
		var a: Vector3 = st.pts[i]
		for j in range(0, st._n, every):
			var dij: int = absi(i - j)
			if mini(dij, st._n - dij) <= window:
				continue
			var c: Vector3 = st.pts[j]
			if Vector2(a.x - c.x, a.z - c.z).length() < reach:
				var k := int(float(i) * st.STEP / 50.0) % bins
				for kk in [k - 1, k, k + 1]:
					out[posmod(kk, bins)] = 1
				break
	return out


## What the streets and the buildings keep off: the overpasses (their decks over the city and the
## piers on the ground) and the gas station.
static func _blockers(b, out: Dictionary) -> void:
	var st = b.st
	for o in st.overpasses:
		var s: float = o.s
		if st.zone_at(s) != "city":
			continue
		var c: Vector3 = st.world_at(s, (st.OUTER_L + st.OUTER_R) * 0.5)
		var h: float = st.heading_at(s) + deg_to_rad(float(o.angle))
		var along := Vector2(sin(h), -cos(h))
		for u in [-60.0, 60.0]:
			out.piers.append(Vector2(c.x, c.z) + along * float(u))
		var r := {"c": Vector2(c.x, c.z), "ax": along, "az": Vector2(-along.y, along.x), "hx": 78.0, "hz": 9.0}
		CitySkyline._add(out.foot, r)
		out.blockers.append(r)
	if not st.station.is_empty():
		var c: Vector3 = st.station.c
		var r := {"c": Vector2(c.x, c.z), "ax": Vector2(st.station.u.x, st.station.u.z).normalized(),
			"az": Vector2(st.station.w.x, st.station.w.z).normalized(), "hx": st.STATION_HALF.x + 14.0, "hz": st.STATION_HALF.y + 14.0}
		CitySkyline._add(out.foot, r)
		out.blockers.append(r)


## The ground's height at (s, d) if a street can be there, else NAN.
static func _ok(b, out: Dictionary, s: float, d: float) -> float:
	var st = b.st
	var p: Vector3 = st.world_at(s, d)
	if absf(d) > EDGE or not st.in_city(p.x, p.z):
		return NAN
	var g: float = b._drawn_y(s, d)
	if g < 1.5 or g > st.city_ground + 4.0:                 # (the lake; the hills at the city's ends)
		return NAN
	if b._ramp_dist(p.x, p.z) < st.RAMP_W + HALF + 3.0:
		return NAN
	var q := Vector2(p.x, p.z)
	for r in out.blockers:
		if r.hz < 12.0:
			continue                                        # (an overpass's deck: over the street; its piers below)
		if CitySkyline.overlap(r, {"c": q, "ax": Vector2.RIGHT, "az": Vector2.UP, "hx": HALF, "hz": HALF}):
			return NAN
	for pr in out.piers:
		if q.distance_to(pr) < HALF + 3.0:
			return NAN
	if _other_road(b, out, p, s, absf(d)):
		return NAN
	return g


## Is another part of the road (or this one round a bend) nearer (x, z) than its own road
## (dist m off, at s)? (The builder's road grid: a sample every 10 m; only where another part
## of the road comes within the city's reach at all: _crowded.)
static func _other_road(b, pl: Dictionary, p: Vector3, s: float, dist: float) -> bool:
	if dist < 40.0 or (pl.crowded as PackedByteArray)[int(b.st.wrap_s(s) / 50.0) % (pl.crowded as PackedByteArray).size()] == 0:
		return false
	var st = b.st
	var own := int(st.wrap_s(s) / st.STEP)
	var window := int((dist + 60.0) / st.STEP)
	var cells := int(ceil(dist / 100.0)) + 1
	var key := Vector2i(floori(p.x / 100.0), floori(p.z / 100.0))
	var lim2 := (dist - 10.0) * (dist - 10.0)
	for dx in range(-cells, cells + 1):
		for dz in range(-cells, cells + 1):
			for i in b._road_grid.get(key + Vector2i(dx, dz), []):
				var di: int = absi(int(i) - own)
				if mini(di, st._n - di) <= window:
					continue
				var q: Vector3 = st.pts[i]
				if (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z) < lim2:
					return true
	return false


## A cross street at s, one side: from beside the viaduct out, broken where a long street
## crosses it (its pieces end at that street's kerbs) and where it can't go.
static func _cross(b, out: Dictionary, longs: Array, ground: Array, s0: float, cs: float, side: float, mouths: Dictionary) -> void:
	var st = b.st
	var ki := clampi(int(round((cs - s0) / STEP)), 0, (ground[0] as PackedFloat32Array).size() - 1)
	var bands := []                                         # [|d| inner kerb, |d| outer kerb, long index] of the long streets there
	var start: float = absf(st.OUTER_R if side > 0.0 else st.OUTER_L) + VIADUCT_GAP   # (from beside the viaduct: no street under it)
	var start_j := false
	var start_li := -1
	for li in longs.size():
		var l: Array = longs[li]
		if float(l[1]) != side:
			continue
		var there := not is_nan((ground[li] as PackedFloat32Array)[ki])
		if bool(l[2]):
			start = absf(float(l[0])) + (ROAD_HALF if there else 0.0)
			start_j = there
			start_li = li if there else -1
		elif there:
			bands.append([absf(float(l[0])) - ROAD_HALF, absf(float(l[0])) + ROAD_HALF, li])
	var ds := []
	var x := start
	while x <= EDGE:
		ds.append([x, -1])
		x += STEP
	for bd in bands:
		ds.append([float(bd[0]), int(bd[2])])
		ds.append([float(bd[1]), int(bd[2])])
	ds.sort_custom(func(a, c): return float(a[0]) < float(c[0]))
	var run := []                                           # [[|d|, ground, junction long index]]
	var flush := func():
		if run.size() >= 2 and float(run[run.size() - 1][0]) - float(run[0][0]) >= MIN_RUN:
			_add_cross(b, out, cs, side, run, mouths, longs)
		run.clear()
	for e in ds:
		var ad: float = e[0]
		var inside := false
		for bd in bands:
			if ad > float(bd[0]) + 0.01 and ad < float(bd[1]) - 0.01:
				inside = true
		var g := NAN if inside else _ok(b, out, cs, ad * side)
		if is_nan(g):
			flush.call()
			continue
		if not run.is_empty() and ad - float(run[run.size() - 1][0]) < 0.5:
			if int(e[1]) >= 0:
				run[run.size() - 1][2] = int(e[1])
			continue
		var j: int = int(e[1])
		if run.is_empty() and absf(ad - start) < 0.01 and start_j:
			j = start_li
		run.append([ad, g, j])
		if int(e[1]) >= 0 and run.size() >= 2:            # (a long street's inner kerb: this piece ends there)
			var inner := false
			for bd in bands:
				if absf(ad - float(bd[0])) < 0.01:
					inner = true
			if inner:
				flush.call()
	flush.call()


static func _add_cross(b, out: Dictionary, cs: float, side: float, run: Array, mouths: Dictionary, longs: Array) -> void:
	var st = b.st
	var fwd: Vector3 = st.forward_at(cs)
	var c := PackedVector3Array()
	var a := PackedVector3Array()
	var u := PackedFloat32Array()
	var gl := PackedFloat32Array()
	var gr := PackedFloat32Array()
	var ss := PackedFloat32Array()
	var d0: float = run[0][0]
	for e in run:
		var d: float = float(e[0]) * side
		var p: Vector3 = st.world_at(cs, d)
		c.append(Vector3(p.x, float(e[1]), p.z))
		a.append(fwd)
		u.append(float(e[0]) - d0)
		gl.append(b._drawn_y(cs - HALF, d))
		gr.append(b._drawn_y(cs + HALF, d))
		ss.append(cs)
	var r := {"kind": "cross", "c": c, "a": a, "u": u, "gl": gl, "gr": gr, "s": ss, "mouths": [],
		"j0": int(run[0][2]) >= 0, "j1": int(run[run.size() - 1][2]) >= 0}
	out.runs.append(r)
	for end in [run[0], run[run.size() - 1]]:
		var li: int = end[2]
		if li < 0:
			continue
		if not mouths.has(li):
			mouths[li] = []
		# (which side of the long street it's on: its +d side or not)
		var mid: float = (float(run[0][0]) + float(run[run.size() - 1][0])) * 0.5 * side
		mouths[li].append([cs, 1.0 if mid > float(longs[li][0]) else -1.0])
	var c0: Vector3 = r.c[0]
	var c1: Vector3 = r.c[r.c.size() - 1]
	var dir := Vector2(c1.x - c0.x, c1.z - c0.z)
	var len := dir.length()
	var fr := {"c": Vector2(c0.x + c1.x, c0.z + c1.z) * 0.5, "ax": dir / maxf(len, 0.01), "az": Vector2(fwd.x, fwd.z), "hx": len * 0.5, "hz": HALF}
	CitySkyline._add(out.foot, fr)
	out.streets.append(fr)


## A long street's pieces where it can go (each its samples' ground), with where the cross
## streets meet it.
static func _long(b, out: Dictionary, l: Array, ground: PackedFloat32Array, s0: float, mouths: Array) -> void:
	var st = b.st
	var d: float = l[0]
	var k := 0
	var n := ground.size()
	while k < n:
		if is_nan(ground[k]):
			k += 1
			continue
		var k1 := k
		while k1 + 1 < n and not is_nan(ground[k1 + 1]):
			k1 += 1
		if float(k1 - k) * STEP >= MIN_RUN:
			var cc := PackedVector3Array()
			var aa := PackedVector3Array()
			var uu := PackedFloat32Array()
			var gl := PackedFloat32Array()
			var gr := PackedFloat32Array()
			var ss := PackedFloat32Array()
			var u := 0.0
			for i in range(k, k1 + 1):
				var s := s0 + i * STEP
				var p: Vector3 = st.world_at(s, d)
				var c := Vector3(p.x, ground[i], p.z)
				if not cc.is_empty():
					var pc: Vector3 = cc[cc.size() - 1]
					u += Vector2(c.x - pc.x, c.z - pc.z).length()
				cc.append(c)
				aa.append(st.right_at(s))
				uu.append(u)
				gl.append(b._drawn_y(s, d - HALF))
				gr.append(b._drawn_y(s, d + HALF))
				ss.append(s)
			var r := {"kind": "long", "c": cc, "a": aa, "u": uu, "gl": gl, "gr": gr, "s": ss, "mouths": [], "j0": false, "j1": false}
			var sa := s0 + k * STEP
			var sb := s0 + k1 * STEP
			for m in mouths:
				var ms: float = m[0]
				if ms >= sa and ms <= sb:
					var f := (ms - sa) / STEP
					var i0 := mini(int(f), r.u.size() - 2)
					r.mouths.append([lerpf(r.u[i0], r.u[i0 + 1], f - i0), float(m[1])])
			out.runs.append(r)
			var i := 0
			while i < r.c.size() - 1:                       # (its footprint: a rectangle every 4 samples)
				var j := mini(i + 4, r.c.size() - 1)
				var a: Vector3 = r.c[i]
				var c2: Vector3 = r.c[j]
				var dir := Vector2(c2.x - a.x, c2.z - a.z)
				var len := dir.length()
				var ax := dir / maxf(len, 0.01)
				var fr := {"c": Vector2(a.x + c2.x, a.z + c2.z) * 0.5, "ax": ax, "az": Vector2(-ax.y, ax.x), "hx": len * 0.5 + 1.0, "hz": HALF}
				CitySkyline._add(out.foot, fr)
				out.streets.append(fr)
				i = j
		k = k1 + 1


## The billboards by the expressway: each side every few hundred metres, BOARD_OUT m past the
## viaduct's barrier, its board above the sound walls, turned to the drivers coming up to it.
static func _boards(b, out: Dictionary, s0: float, s1: float, rng: RandomNumberGenerator) -> void:
	var st = b.st
	for side in [1.0, -1.0]:
		var s := s0 + rng.randf_range(80.0, 300.0)
		while s < s1 - 80.0:
			var d: float = (st.OUTER_R + BOARD_OUT) if side > 0.0 else (st.OUTER_L - BOARD_OUT)
			var g := _ok(b, out, s, d)
			var clear: bool = not is_nan(g) and b._ramp_dist(st.world_at(s, d).x, st.world_at(s, d).z) > 40.0
			for o in st.overpasses:
				clear = clear and absf(st.wrap_s(s) - float(o.s)) > 90.0
			for gt in st.gantries:
				clear = clear and absf(st.wrap_s(s) - float(gt.s)) > 60.0
			if clear:
				var p: Vector3 = st.world_at(s, d)
				var deck: float = st.world_at(s, 0.0).y
				var fwd: Vector3 = st.forward_at(s)
				var right: Vector3 = st.right_at(s)
				# (its face to the traffic coming up to it on its side: ours on the right, theirs on the left)
				var n: Vector3 = (-fwd * cos(deg_to_rad(25.0)) - right * sin(deg_to_rad(25.0))) if side > 0.0 \
					else (fwd * cos(deg_to_rad(25.0)) + right * sin(deg_to_rad(25.0)))
				var bas := Basis(Vector3.UP.cross(n).normalized(), Vector3.UP, n)
				var foot := {"c": Vector2(p.x, p.z), "ax": Vector2(bas.x.x, bas.x.z), "az": Vector2(bas.z.x, bas.z.z), "hx": BOARD.x * 0.5 + 1.0, "hz": 2.0}
				var free := true
				var key := Vector2i(floori(p.x / 100.0), floori(p.z / 100.0))
				for dx in range(-1, 2):
					for dz in range(-1, 2):
						for o in out.foot.get(key + Vector2i(dx, dz), []):
							free = free and not CitySkyline.overlap(foot, o, 1.0)
				if free:
					CitySkyline._add(out.foot, foot)
					out.boards.append({"at": Vector3(p.x, g, p.z), "basis": bas, "bottom": deck + BOARD_UP,
						"faces": [rng.randi() % SIGNS, rng.randi() % SIGNS], "foot": foot})
			s += rng.randf_range(BOARD_EVERY.x, BOARD_EVERY.y)


## Is footprint r clear of the streets, the billboards and what the streets keep off (gap m)?
static func clear_of(pl: Dictionary, r: Dictionary, gap := 2.0) -> bool:
	var key := Vector2i(floori(r.c.x / 100.0), floori(r.c.y / 100.0))
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for o in pl.foot.get(key + Vector2i(dx, dz), []):
				if CitySkyline.overlap(r, o, gap):
					return false
	return true


# ── the fill: drawn buildings in the blocks' gaps ─────────────────────────

## The blocks between the streets, each filled where nothing stands with drawn buildings (lots
## along the streets, rows behind them, now and then an open lot: a car park, a yard): low (2-4
## storeys) between the viaduct and the first long street, where the library's buildings
## are the ones seen from the road; further out taller in the middle of town, now and then a
## tower. placed: the footprints
## already standing (the front rows, the drawn towers, the far tier; CitySkyline's rects).
## Returns {xfs, cols} (the towers' box: x across the road, z along it, scaled), district (each
## one's: CitySkyline's 1 km) and tops (each roof: [Transform3D at its middle, its size across and
## along, how far off the road, which side], for the signs).
static func fill(b, pl: Dictionary, placed: Array) -> Dictionary:
	var st = b.st
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([st.seed_used, "city fill"])
	var out := {"xfs": [], "cols": [], "tops": [], "district": []}
	var palette := [Color(0.5, 0.5, 0.48), Color(0.56, 0.53, 0.47), Color(0.44, 0.46, 0.5), Color(0.6, 0.59, 0.56),
		Color(0.38, 0.4, 0.42), Color(0.53, 0.48, 0.42), Color(0.46, 0.5, 0.53), Color(0.62, 0.55, 0.48), Color(0.66, 0.64, 0.6)]
	# what stands, in road coordinates: [s0, s1, |d|0, |d|1, side] (each corner located)
	var boxes := []
	for r in placed + pl.blockers + pl.boards.map(func(bd): return bd.foot):
		var e = _sd_box(b, r)
		if e != null:
			boxes.append(e)
	var grid := {}                                         # 50 m of s -> [box]
	for e0 in boxes:
		# (and a lap on: the city across the loop's start is one stretch, its s past the length)
		for e in [e0, [float(e0[0]) + st.length, float(e0[1]) + st.length, e0[2], e0[3], e0[4]]]:
			for k in range(int(floor(e[0] / 50.0)), int(floor(e[1] / 50.0)) + 1):
				if not grid.has(k):
					grid[k] = []
				grid[k].append(e)
	for z in pl.zones:
		var s0: float = z.s0
		var s1: float = z.s1
		var cuts: Array = [s0 - HALF] + z.cross + [s1 + HALF]
		for side in [1.0, -1.0]:
			var ds := []                                    # the long streets' |d| on this side (and beside the viaduct: the first block's inner edge)
			for l in z.longs:
				if float(l[1]) == side:
					ds.append(absf(float(l[0])))
			ds.sort()
			ds.push_front(absf(st.OUTER_R if side > 0.0 else st.OUTER_L) + FILL_IN - HALF - GAP)
			ds.append(EDGE + 45.0 + HALF)                   # (out to the city's edge)
			for bi in ds.size() - 1:
				var da: float = float(ds[bi]) + HALF + GAP
				var db: float = float(ds[bi + 1]) - HALF - GAP
				var band := bi
				for ci in cuts.size() - 1:
					# (s is metres along the road's middle: out on the inside of a bend a metre of s
					# is less than a metre on the ground, so the margins in s are wider there)
					var ks := INF
					for sx in [float(cuts[ci]), (float(cuts[ci]) + float(cuts[ci + 1])) * 0.5, float(cuts[ci + 1])]:
						ks = minf(ks, _s_scale(st, sx, da * side, db * side))      # (where a bend starts in the block)
					var sa: float = float(cuts[ci]) + (HALF + GAP) / ks
					var sb: float = float(cuts[ci + 1]) - (HALF + GAP) / ks
					if (sb - sa) * ks < 14.0 or db - da < 12.0:
						continue
					_fill_block(b, pl, out, grid, sa, sb, da, db, side, band, z, rng, palette, ks)
	return out


## A footprint's extent in road coordinates: [s0, s1, |d|0, |d|1, side], or null (off the city).
static func _sd_box(b, r: Dictionary):
	var st = b.st
	var hint := _hint(b, r.c)
	if hint < 0:
		return null
	var smin := INF
	var smax := -INF
	var dmin := INF
	var dmax := -INF
	var ref := -1.0
	for u in [-1.0, 1.0]:
		for v in [-1.0, 1.0]:
			var q: Vector2 = r.c + r.ax * r.hx * u + r.az * r.hz * v
			var loc: Dictionary = st.locate(Vector3(q.x, 0.0, q.y), hint)
			var s: float = loc.s
			if ref < 0.0:
				ref = s
			s = ref + wrapf(s - ref, -st.length * 0.5, st.length * 0.5)
			smin = minf(smin, s)
			smax = maxf(smax, s)
			dmin = minf(dmin, float(loc.d))
			dmax = maxf(dmax, float(loc.d))
	if dmin < 0.0 and dmax > 0.0:
		return [smin, smax, 0.0, maxf(-dmin, dmax), 0.0]      # (across the road: both sides)
	var side := 1.0 if dmin >= 0.0 else -1.0
	return [smin, smax, minf(absf(dmin), absf(dmax)), maxf(absf(dmin), absf(dmax)), side]


## The road sample nearest (x, z) (the builder's road grid), or -1.
static func _hint(b, c: Vector2) -> int:
	var key := Vector2i(floori(c.x / 100.0), floori(c.y / 100.0))
	var best := -1
	var best_d := INF
	for dx in range(-7, 8):
		for dz in range(-7, 8):
			for i in b._road_grid.get(key + Vector2i(dx, dz), []):
				var p: Vector3 = b.st.pts[i]
				var dd := Vector2(p.x - c.x, p.z - c.y).length_squared()
				if dd < best_d:
					best_d = dd
					best = i
	return best


## The ground's metres a metre of s at d (the least of da and db; s is along the road's middle).
static func _s_scale(st, s: float, da: float, db: float) -> float:
	var k := INF
	for d in [da, db]:
		var a: Vector3 = st.world_at(s - 1.0, d)
		var c: Vector3 = st.world_at(s + 1.0, d)
		k = minf(k, Vector2(c.x - a.x, c.z - a.z).length() * 0.5)
	return clampf(k, 0.25, 4.0)


static func _fill_block(b, pl: Dictionary, out: Dictionary, grid: Dictionary, sa: float, sb: float, da: float, db: float, side: float, band: int,
		z: Dictionary, rng: RandomNumberGenerator, palette: Array, ks: float) -> void:
	var st = b.st
	# lots along s (each 16-32 m on the ground), rows out from the street (18-30 m deep); the rows
	# between the front and the back of a deep block now and then left open
	var cols := []
	var x := sa
	var gap_s := GAP / ks
	while (sb - x) * ks >= 14.0:
		var w := minf(rng.randf_range(16.0, 32.0) / ks, sb - x)
		if (sb - (x + w)) * ks < 14.0:
			w = sb - x
		cols.append([x, x + w])
		x += w + gap_s
	var rows := []
	var y := da
	while db - y >= 12.0:
		var dep := minf(rng.randf_range(18.0, 30.0), db - y)
		if db - (y + dep) < 12.0:
			dep = db - y
		rows.append([y, y + dep])
		y += dep + GAP
	var centre := 1.0 - absf(((sa + sb) * 0.5 - z.s0) / maxf(z.s1 - z.s0, 1.0) - 0.5) * 2.0
	for ri in rows.size():
		var row: Array = rows[ri]
		var inner: bool = ri > 0 and ri < rows.size() - 1
		for col in cols:
			if rng.randf() < (0.45 if inner else 0.1):
				continue                                    # (an open lot)
			var s_lo: float = col[0]
			var s_hi: float = col[1]
			var d_lo: float = row[0]
			var d_hi: float = row[1]
			if _taken(grid, s_lo - gap_s, s_hi + gap_s, d_lo - GAP, d_hi + GAP, side):
				continue
			var sm := (s_lo + s_hi) * 0.5
			var dm := (d_lo + d_hi) * 0.5 * side
			var lo := INF
			var hi := -INF
			var ok := true
			for e in [[s_lo, d_lo], [s_hi, d_lo], [s_lo, d_hi], [s_hi, d_hi], [sm, absf(dm)]]:
				var p: Vector3 = st.world_at(float(e[0]), float(e[1]) * side)
				if not st.in_city(p.x, p.z):
					ok = false
					break
				var g: float = b._drawn_y(float(e[0]), float(e[1]) * side)
				lo = minf(lo, g)
				hi = maxf(hi, g)
			if not ok or lo < 1.5 or hi - lo > CitySkyline.FLAT or lo > st.city_ground + 4.0:
				continue
			var mid: Vector3 = st.world_at(sm, dm)
			var along := Vector2(st.world_at(s_hi, dm).x - st.world_at(s_lo, dm).x, st.world_at(s_hi, dm).z - st.world_at(s_lo, dm).z).length()
			var across := d_hi - d_lo
			if b._ramp_dist(mid.x, mid.z) < Vector2(along, across).length() * 0.5 + st.RAMP_W + 4.0:
				continue
			if _other_road(b, pl, mid, sm, absf(dm)):
				continue
			if not clear_of(pl, CitySkyline._rect(Transform3D(Basis(Vector3.UP, -st.heading_at(sm)), mid), across, along), 1.0):
				continue                                    # (the last word: clear of every street, what's built and the billboards)
			# its height: storeys by how far out (lower further), the middle of town taller, now and then a tower
			# (between the viaduct and the first long street low: under the sound walls'
			# line from the road, the library's buildings in front stay the ones seen there)
			var storeys: float = [rng.randf_range(2.0, 4.0), rng.randf_range(3.0, 10.0), rng.randf_range(2.0, 7.0)][mini(band, 2)]
			storeys *= 0.75 + 0.5 * centre if band > 0 else 1.0
			if band > 0 and rng.randf() < [0.0, 0.08, 0.05][mini(band, 2)]:
				storeys = rng.randf_range(12.0, 28.0) * (0.7 + 0.5 * centre)
			var hgt := maxf(storeys, 2.0) * 3.5 + rng.randf_range(0.0, 2.0)
			var bas := Basis(Vector3.UP, -st.heading_at(sm)) * Basis.from_scale(Vector3(across, hgt, along))
			var xf := Transform3D(bas, Vector3(mid.x, lo + hgt * 0.5 - 0.5, mid.z))
			out.xfs.append(xf)
			out.cols.append((palette[rng.randi() % palette.size()] as Color) * rng.randf_range(0.92, 1.06))
			out.tops.append([Transform3D(Basis(Vector3.UP, -st.heading_at(sm)), Vector3(mid.x, lo - 0.5 + hgt, mid.z)), across, along, absf(dm), side])
			out.district.append(int(st.wrap_s(sm) / CitySkyline.DISTRICT))
			var e2 := [s_lo, s_hi, d_lo, d_hi, side]
			for k in range(int(floor(s_lo / 50.0)), int(floor(s_hi / 50.0)) + 1):
				if not grid.has(k):
					grid[k] = []
				grid[k].append(e2)


static func _taken(grid: Dictionary, s0: float, s1: float, d0: float, d1: float, side: float) -> bool:
	for k in range(int(floor(s0 / 50.0)), int(floor(s1 / 50.0)) + 1):
		for e in grid.get(k, []):
			if float(e[1]) < s0 or float(e[0]) > s1 or float(e[3]) < d0 or float(e[2]) > d1:
				continue
			if float(e[4]) == 0.0 or float(e[4]) == side:
				return true
	return false


# ── drawn: the streets, the lamps, the trees, the parked cars, the signs ──

static func dress(b, pl: Dictionary, tops: Array, night: float) -> Node3D:
	var st = b.st
	var root := Node3D.new()
	root.name = NAME
	b.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([st.seed_used, "street things"])
	var view := Graphics.view_distance()
	# the streets: a mesh a district (1 km of road) a kind, the long ones in pieces
	var strips := {}                                        # "district/kind" -> arrays
	for r in pl.runs:
		for piece in _pieces(r):
			var key := "%d/%s" % [_district(st, r, float(r.u[int((piece[0] + piece[1]) / 2)])), r.kind]
			if not strips.has(key):
				strips[key] = {"chunks": [], "kind": r.kind}
			strips[key].chunks.append(_strip(r, piece[0], piece[1]))
	var mat_long := _street_material(night, 0.9985)
	var mat_cross := _street_material(night, 0.998)
	for key in strips:
		var e: Dictionary = strips[key]
		var vv := PackedVector3Array()
		var uv := PackedVector2Array()
		var col := PackedColorArray()
		for ch in e.chunks:
			vv.append_array(ch[0])
			uv.append_array(ch[1])
			col.append_array(ch[2])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = vv
		var nrm := PackedVector3Array()
		nrm.resize(vv.size())
		nrm.fill(Vector3.UP)
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_COLOR] = col
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.name = "Streets_" + key.replace("/", "_")
		mi.mesh = m
		mi.material_override = mat_long if e.kind == "long" else mat_cross
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 2400.0 * view
		mi.visibility_range_end_margin = 200.0
		root.add_child(mi)
	# along each street: lamps, trees, parked cars
	var lamps := {}
	var trees := {}
	var cars := {}                                          # "district/type" -> [xf], colours
	var lamp_pts := []
	var tree_pts := []
	var car_feet := []
	var pool := _car_pool()
	for r in pl.runs:
		var len: float = r.u[r.u.size() - 1]
		var k := 0
		while (k + 0.5) * LAMP_EVERY < len:
			var u := (k + 0.5) * LAMP_EVERY
			var sd := 1.0 if k % 2 == 0 else -1.0
			k += 1
			if u < 10.0 or len - u < 10.0 or _near_mouth(r, u, sd, HALF + 1.5):
				continue
			var f := _frame(r, u)
			var at: Vector3 = f[0] + f[1] * sd * (ROAD_HALF + 0.5)
			at.y = _ground(r, u, sd)
			var xf := Transform3D(Basis(-f[1] * sd, Vector3.UP, (-f[1] * sd).cross(Vector3.UP)), at)
			_put(lamps, _cell(at, 2.0), xf)
			lamp_pts.append(at)
		var t := 0
		while (t + 0.5) * TREE_EVERY < len:
			var u := (t + 0.5) * TREE_EVERY
			t += 1
			for sd in [1.0, -1.0]:
				if u < 12.0 or len - u < 12.0 or _near_mouth(r, u, sd, HALF + 2.5) or _near_lamp(u, sd, 4.0):
					continue
				var f := _frame(r, u)
				var at: Vector3 = f[0] + f[1] * sd * (ROAD_HALF + 1.4)
				at.y = _ground(r, u, sd) - 0.1
				var sc := rng.randf_range(0.55, 0.8)
				_put(trees, _cell(at), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.15), sc)), at))
				tree_pts.append(at)
		if pool.is_empty():
			continue
		var p := 0
		while 14.0 + (p + 0.5) * PARK_EVERY < len - 14.0:
			var u := 14.0 + (p + 0.5) * PARK_EVERY
			p += 1
			for sd in [1.0, -1.0]:
				if rng.randf() > 0.3 or _near_mouth(r, u, sd, HALF + 4.0):
					continue
				var e: Dictionary = pool[_weighted(pool, rng)]
				var sz: Vector3 = CAR_SIZE.get(e.type, CAR_SIZE.sedan)
				var f := _frame(r, u + rng.randf_range(-0.4, 0.4))
				var at: Vector3 = f[0] + f[1] * sd * (LANE + 1.0 + rng.randf_range(-0.1, 0.1))
				at.y = _ground(r, u, sd) + 0.02
				var bas := Basis(f[1], Vector3.UP, (f[1] as Vector3).cross(Vector3.UP))   # (its length along the street, either way)
				bas = bas.rotated(Vector3.UP, (PI if rng.randf() < 0.5 else 0.0) + rng.randf_range(-0.04, 0.04))
				var key := _cell(at)
				if not cars.has(key):
					cars[key] = [[], []]
				cars[key][0].append(Transform3D(bas.scaled_local(Vector3(sz.y, sz.z, sz.x)), at))
				cars[key][1].append(e.paints[rng.randi() % e.paints.size()])
				car_feet.append({"c": Vector2(at.x, at.z), "ax": Vector2(bas.x.x, bas.x.z), "az": Vector2(bas.z.x, bas.z.z), "hx": sz.y * 0.5, "hz": sz.x * 0.5})
	var thing := _thing_material(night)
	var lamp_mesh := _lamp_mesh()
	for ck in lamps:
		_mm(root, lamp_mesh, lamps[ck], [], "Lamps_%d_%d" % [ck.x, ck.y], thing, 0.0, 900.0 * view)
	var lib := _tree_meshes(b)
	for ck in trees:
		var list: Array = trees[ck]
		for kind in lib.size():
			var part := list.filter(func(xf): return absi(hash([int(xf.origin.x), int(xf.origin.z)])) % lib.size() == kind)
			if part.is_empty():
				continue
			var lv: Array = lib[kind]
			for li in lv.size():
				var mmi := _mm(root, lv[li][0], part, [], "Trees_%d_%d_%d_%d" % [ck.x, ck.y, kind, li], null, float(lv[li][1]), float(lv[li][2]) * view)
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var car := _car_mesh()
	for ck in cars:
		_mm(root, car, cars[ck][0], cars[ck][1], "Parked_%d_%d" % [ck.x, ck.y], thing, 0.0, 320.0 * view)
	# signs: on some roofs near the road (facing it), and the billboards
	var signs := []
	var sign_custom := []
	for tp in tops:
		var xf: Transform3D = tp[0]
		var across: float = tp[1]
		var along: float = tp[2]
		if float(tp[3]) > 330.0 or xf.origin.y - st.city_ground < 14.0 or rng.randf() > 0.3:
			continue
		var w := clampf(along * 0.7, 6.0, 14.0)
		var toward: Vector3 = xf.basis.x * -float(tp[4])          # (its x across the road: toward it)
		var at: Vector3 = xf.origin + toward * (across * 0.5 - 1.5)
		var bas := Basis(toward.cross(Vector3.UP) * -1.0, Vector3.UP, toward).scaled(Vector3.ONE * w)
		signs.append(Transform3D(bas, at))
		sign_custom.append(Color(float(rng.randi() % SIGNS) / SIGNS, 0.0, 0.0, 0.0))
	var smat := _sign_material(night)
	if not signs.is_empty():
		var mmi := _mm(root, _roof_sign_mesh(), signs, [], "RoofSigns", smat, 0.0, 2600.0 * view, sign_custom)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var boards := []
	var board_custom := []
	for bd in pl.boards:
		var at: Vector3 = bd.at
		boards.append(Transform3D(bd.basis, Vector3(at.x, float(bd.bottom), at.z)))
		board_custom.append(Color(float(bd.faces[0]) / SIGNS, float(bd.faces[1]) / SIGNS, 0.0, 0.0))
	if not boards.is_empty():
		_mm(root, _board_mesh(), boards, [], "Billboards", smat, 0.0, 3000.0 * view, board_custom)
	root.set_meta("lamps", lamp_pts)
	root.set_meta("trees", tree_pts)
	root.set_meta("cars", car_feet)
	root.set_meta("signs", signs.size())
	root.set_meta("boards", pl.boards.map(func(bd): return bd.foot))
	root.set_meta("runs", pl.runs.size())
	root.set_meta("streets", pl.streets)                    # (each street's footprint, its pavements too)
	return root


## A run's pieces to draw: [first sample, last sample], PIECE m at most each.
static func _pieces(r: Dictionary) -> Array:
	var out := []
	var i := 0
	var n: int = r.c.size()
	while i < n - 1:
		var j := i + 1
		while j < n - 1 and float(r.u[j]) - float(r.u[i]) < PIECE:
			j += 1
		out.append([i, j])
		i = j
	return out


## A strip's triangles (samples i0..i1): its edges on the ground as drawn, UV (m along, m across
## from its middle), colour (how far to its start and end / 16 m, and whether each is a junction).
static func _strip(r: Dictionary, i0: int, i1: int) -> Array:
	var vv := PackedVector3Array()
	var uv := PackedVector2Array()
	var cols := PackedColorArray()
	var len: float = r.u[r.u.size() - 1]
	for i in range(i0, i1):
		var q := []
		for k in [i, i + 1]:
			var c: Vector3 = r.c[k]
			var a: Vector3 = r.a[k]
			var u: float = r.u[k]
			var col := Color(clampf(u / 16.0, 0.0, 1.0), clampf((len - u) / 16.0, 0.0, 1.0), 1.0 if r.j0 else 0.0, 1.0 if r.j1 else 0.0)
			var lp := c - a * HALF
			var rp := c + a * HALF
			lp.y = float(r.gl[k]) + 0.04
			rp.y = float(r.gr[k]) + 0.04
			q.append([lp, rp, u, col])
		for t in [[0, 0], [0, 1], [1, 1], [0, 0], [1, 1], [1, 0]]:
			var v: Array = q[t[0]]
			vv.append(v[0] if t[1] == 0 else v[1])
			uv.append(Vector2(float(v[2]), -HALF if t[1] == 0 else HALF))
			cols.append(v[3])
	return [vv, uv, cols]


## The point on a run's middle u m along, and its across direction.
static func _frame(r: Dictionary, u: float) -> Array:
	var n: int = r.u.size()
	var i := _index(r, u)
	var f := clampf((u - float(r.u[i])) / maxf(float(r.u[i + 1]) - float(r.u[i]), 0.001), 0.0, 1.0)
	var c: Vector3 = (r.c[i] as Vector3).lerp(r.c[i + 1], f)
	var a: Vector3 = (r.a[i] as Vector3).lerp(r.a[i + 1], f).normalized()
	return [c, a]


## The ground at a run's edge (side sd) u m along.
static func _ground(r: Dictionary, u: float, sd: float) -> float:
	var i := _index(r, u)
	var f := clampf((u - float(r.u[i])) / maxf(float(r.u[i + 1]) - float(r.u[i]), 0.001), 0.0, 1.0)
	var g: PackedFloat32Array = r.gr if sd > 0.0 else r.gl
	var c: float = lerpf(r.c[i].y, r.c[i + 1].y, f)
	return lerpf(c, lerpf(g[i], g[i + 1], f), 0.75)


## The sample a run's point u m along comes after (its samples are ~STEP apart: a guess, then
## a step or two either way).
static func _index(r: Dictionary, u: float) -> int:
	var n: int = r.u.size()
	var i := clampi(int(u / STEP), 0, n - 2)
	while i > 0 and float(r.u[i]) > u:
		i -= 1
	while i < n - 2 and float(r.u[i + 1]) < u:
		i += 1
	return i


static func _near_mouth(r: Dictionary, u: float, sd: float, m: float) -> bool:
	for mo in r.mouths:
		if float(mo[1]) == sd and absf(u - float(mo[0])) < m:
			return true
	return false


static func _near_lamp(u: float, sd: float, m: float) -> bool:
	var k := int(floor(u / LAMP_EVERY))
	for kk in [k - 1, k, k + 1]:
		if kk < 0:
			continue
		var lsd := 1.0 if kk % 2 == 0 else -1.0
		if lsd == sd and absf(u - (kk + 0.5) * LAMP_EVERY) < m:
			return true
	return false


## The district (CitySkyline's: 1 km of road) of a run's point u m along.
static func _district(st, r: Dictionary, u: float) -> int:
	var i := _index(r, u)
	return int(st.wrap_s(float(r.s[i])) / CitySkyline.DISTRICT)


## The square (CELL m, times k: the lamps' twice that, drawn further) a point's in.
static func _cell(p: Vector3, k := 1.0) -> Vector2i:
	return Vector2i(floori(p.x / (CELL * k)), floori(p.z / (CELL * k)))


static func _put(d: Dictionary, k, xf: Transform3D) -> void:
	if not d.has(k):
		d[k] = []
	d[k].append(xf)


static func _mm(root: Node3D, mesh: Mesh, xfs: Array, cols: Array, nm: String, mat: Material, begin: float, end: float, custom := []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.use_custom_data = not custom.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
		if mm.use_colors:
			mm.set_instance_color(k, cols[k])
		if mm.use_custom_data:
			mm.set_instance_custom_data(k, custom[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	if mat != null:
		mmi.material_override = mat
	mmi.visibility_range_begin = begin
	mmi.visibility_range_begin_margin = 10.0 if begin > 0.0 else 0.0
	mmi.visibility_range_end = end
	mmi.visibility_range_end_margin = 60.0
	root.add_child(mmi)
	return mmi


## The cars that may be parked: the traffic's own pool less the ones never shown (no-AI).
static func _car_pool() -> Array:
	var out := []
	for e in VehicleRegistry.traffic_pool():
		if not VehicleRegistry.no_ai(str(e.id)) and not (e.paints as Array).is_empty():
			out.append(e)
	return out


static func _weighted(pool: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for e in pool:
		total += float(e.weight)
	var x := rng.randf() * total
	for k in pool.size():
		x -= float(pool[k].weight)
		if x <= 0.0:
			return k
	return pool.size() - 1


## The street trees: one of the library's broadleaves (its real mesh near, the far card beyond:
## 8 triangles), else the drawn one. [[mesh, from, to]] per kind.
static func _tree_meshes(b) -> Array:
	if b._lib_trees_ok():
		var biomes = load("res://scripts/stage/biomes.gd")
		var verge: Dictionary = biomes.for_stage(b.st)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([b.st.seed_used, "street trees"])
		var pool: Array = (verge.get("broad", []) as Array).duplicate()
		var out := []
		while not pool.is_empty() and out.is_empty():          # (one species along the streets: half the draws of two)
			var id: String = biomes.pick(pool, rng)
			pool = pool.filter(func(e): return str(e[0]) != id)
			var near: Mesh = EnvAssets.mesh(id, "LOD1")
			var far: Mesh = EnvAssets.mesh(id, "BB")
			if near != null and far != null:
				out.append([[near, 0.0, 110.0], [far, 110.0, 1100.0]])
		if not out.is_empty():
			return out
	return [[[b._tree_mesh(false), 0.0, 700.0]]]


# ── the meshes ───────────────────────────────────────────────────────────

## A street lamp (its foot at the origin on the pavement, its arm out along +x over the road):
## an 8 m pole, the arm, the head (its glass: the vertex colour's alpha 0, lit at night).
static func _lamp_mesh() -> ArrayMesh:
	var gb := preload("res://scripts/stage/geo_buf.gd").new()
	var steel := Color(0.34, 0.35, 0.36, 1.0)
	_box(gb, Vector3(0, 4.0, 0), Vector3(0.18, 8.0, 0.18), steel)
	_box(gb, Vector3(LAMP_REACH * 0.5, 7.9, 0), Vector3(LAMP_REACH, 0.1, 0.1), steel)
	_box(gb, Vector3(LAMP_REACH, 7.86, 0), Vector3(0.75, 0.16, 0.32), steel)
	gb.box(Vector3(LAMP_REACH, 7.77, 0), Vector3(0.62, 0.03, 0.24), Basis(), Color(0.85, 0.85, 0.8, 0.0))
	return gb.mesh()


## A parked car's stand-in, 1 m long, wide and high (the instance scales it to its type's size;
## its middle on the ground at the origin, its length along z): the body, the glasshouse, the
## wheels under it (the body's paint: the instance's colour).
static func _car_mesh() -> ArrayMesh:
	var gb := preload("res://scripts/stage/geo_buf.gd").new()
	var body := Color(1, 1, 1, 1)
	var glass := Color(0.09, 0.1, 0.12, 1)
	var tyre := Color(0.05, 0.05, 0.05, 1)
	_box(gb, Vector3(0, 0.42, 0), Vector3(1.0, 0.44, 1.0), body)
	_box(gb, Vector3(0, 0.82, -0.04), Vector3(0.86, 0.36, 0.5), glass)
	for x in [-1.0, 1.0]:
		for zz in [-1.0, 1.0]:
			_box(gb, Vector3(x * 0.44, 0.19, zz * 0.32), Vector3(0.12, 0.38, 0.14), tyre)
	return gb.mesh()


## A sign on a roof (unit wide: the instance scales it): the face (u, v 0..1: its cell in the
## signs' image; the vertex alpha 1), the back and the legs (plain, alpha 0). Its face to +z.
static func _roof_sign_mesh() -> ArrayMesh:
	var gb := preload("res://scripts/stage/geo_buf.gd").new()
	var steel := Color(0.3, 0.31, 0.32, 0.0)
	var face := Color(1, 1, 1, 1)
	var y0 := 0.12
	var y1 := y0 + 0.5
	gb.quad(Vector3(-0.5, y0, 0.01), Vector3(0.5, y0, 0.01), Vector3(0.5, y1, 0.01), Vector3(-0.5, y1, 0.01),
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), face)
	gb.quad(Vector3(0.5, y0, -0.01), Vector3(-0.5, y0, -0.01), Vector3(-0.5, y1, -0.01), Vector3(0.5, y1, -0.01),
		Vector2(0, 0), Vector2(0, 0), Vector2(0, 0), Vector2(0, 0), steel)
	for x in [-0.35, 0.35]:
		_box(gb, Vector3(x, y0 * 0.5, -0.04), Vector3(0.03, y0, 0.03), steel)
	return gb.mesh()


## A billboard (the origin at the middle of its board's foot, BOARD_UP over the road): the board's
## two faces (each its own cell: the instance's custom data r and g, picked in the shader by the
## vertex alpha: 1 the front, 0.5 the back), its frame, the pole down from it (35 m: its foot in
## the ground, however far down that is).
static func _board_mesh() -> ArrayMesh:
	var gb := preload("res://scripts/stage/geo_buf.gd").new()
	var steel := Color(0.32, 0.33, 0.34, 0.0)
	_box(gb, Vector3(0, -17.5, -0.5), Vector3(0.9, 35.0, 0.9), steel)
	var hw := BOARD.x * 0.5
	for f in [[0.06, Color(1, 1, 1, 1), false], [-0.06, Color(1, 1, 1, 0.5), true]]:
		var z: float = f[0]
		var a := Vector3(-hw, 0.0, z)
		var bb := Vector3(hw, 0.0, z)
		var c := Vector3(hw, BOARD.y, z)
		var d := Vector3(-hw, BOARD.y, z)
		if f[2]:
			gb.quad(bb, a, d, c, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), f[1])
		else:
			gb.quad(a, bb, c, d, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), f[1])
	_box(gb, Vector3(0, -0.15, 0), Vector3(BOARD.x + 0.3, 0.3, 0.4), steel)
	_box(gb, Vector3(0, BOARD.y + 0.1, 0), Vector3(BOARD.x + 0.3, 0.2, 0.4), steel)
	return gb.mesh()


## A box with no bottom (nobody sees it: 10 triangles), GeoBuf's faces.
static func _box(gb, at: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var c := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	for f in [[4, 5, 6, 7], [1, 0, 3, 2], [0, 4, 7, 3], [5, 1, 2, 6], [7, 6, 2, 3]]:
		gb.quad(at + c[f[0]], at + c[f[1]], at + c[f[2]], at + c[f[3]], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col)


# ── the materials ────────────────────────────────────────────────────────

## The streets: asphalt, the centre line dashed, the parking strips' lines, the kerbs, the
## pavement's slabs, a zebra where a cross street meets a long one; at night the lamps' pools
## (each lamp's place along the street worked out as dress() puts them). pull: the strip's
## distance from the camera times this (a little nearer than the land under it).
static func _street_material(night: float, pull: float) -> ShaderMaterial:
	if _street_shader == null:
		_street_shader = Shader.new()
		_street_shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform float night = 0.0;
uniform float pull = 0.998;
uniform float road_half = %.2f;
uniform float lane = %.2f;
uniform float lamp_every = %.2f;
uniform float reach = %.2f;
varying vec2 wxz;
void vertex() {
	wxz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vp.xyz *= pull;                                  // (nearer the camera along its own line of sight: same place on screen)
	POSITION = PROJECTION_MATRIX * vp;
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	float u = UV.x;
	float v = UV.y;
	float av = abs(v);
	float n = vnoise(wxz * 0.11) * 0.6 + vnoise(wxz * 0.9) * 0.4;
	float road = step(av, road_half);
	vec3 asphalt = vec3(0.15, 0.152, 0.158) * (0.82 + 0.36 * n);
	vec2 slab = abs(fract(vec2(u, av) / vec2(1.5, 1.25)) - 0.5);
	vec3 walk = vec3(0.46, 0.45, 0.43) * (0.9 + 0.2 * n) * (1.0 - 0.16 * step(0.46, max(slab.x, slab.y)));
	vec3 col = mix(walk, asphalt, road);
	col = mix(col, vec3(0.56, 0.56, 0.54), step(road_half - 0.2, av) * step(av, road_half + 0.15));   // (the kerb)
	vec2 fw = fwidth(UV);
	float aa = clamp(1.0 - max(fw.x, fw.y) * 0.6, 0.0, 1.0);         // (far off the lines fade: no shimmer)
	float centre = step(av, 0.08) * step(0.45, fract(u / 6.0));
	float strip = step(abs(av - lane), 0.06);
	float dist0 = COLOR.r * 16.0;
	float dist1 = COLOR.g * 16.0;
	float zebra = (step(dist0, 4.0) * step(1.0, dist0) * COLOR.b + step(dist1, 4.0) * step(1.0, dist1) * COLOR.a)
		* step(av, road_half - 0.4) * step(0.5, fract(v / 1.0 + 0.25));
	float paint = max(max(centre, strip) * step(4.0, min(dist0 + (1.0 - COLOR.b) * 99.0, dist1 + (1.0 - COLOR.a) * 99.0)), zebra) * road * aa;
	col = mix(col, vec3(0.78, 0.78, 0.74), paint);
	ALBEDO = col;
	ROUGHNESS = mix(0.86, 0.72, road) - 0.1 * paint;
	SPECULAR = 0.35;
	// at night the street lamps' pools: each lamp (LAMP_EVERY apart, sides in turn, its head over
	// the lane), the nearest three summed; none within 10 m of the street's ends (none there)
	float k = floor(u / lamp_every);
	float pool = 0.0;
	for (int j = -1; j <= 1; j++) {
		float kk = k + float(j);
		float sd = mod(kk, 2.0) < 0.5 ? 1.0 : -1.0;
		vec2 head = vec2((kk + 0.5) * lamp_every, sd * (road_half + 0.5 - reach));
		vec2 dv = vec2(u, v) - head;
		pool += exp(-dot(dv, dv) / 46.0) * step(0.0, kk);
	}
	pool *= smoothstep(9.0, 11.0, dist0) * smoothstep(9.0, 11.0, dist1);
	EMISSION = col * vec3(1.0, 0.8, 0.56) * min(pool, 1.2) * night * 1.6;
}
""" % [ROAD_HALF, LANE, LAMP_EVERY, LAMP_REACH]
	var m := ShaderMaterial.new()
	m.shader = _street_shader
	m.set_shader_parameter("night", night)
	m.set_shader_parameter("pull", pull)
	return m


## The lamps and the parked cars: their vertex colour (times the instance's: a car's paint); a
## lamp's glass (alpha 0) lit at night.
static func _thing_material(night: float) -> ShaderMaterial:
	if _thing_shader == null:
		_thing_shader = Shader.new()
		_thing_shader.code = """
shader_type spatial;
uniform float night = 0.0;
void fragment() {
	float glass = 1.0 - COLOR.a;
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.55;
	METALLIC = 0.2;
	EMISSION = glass * vec3(1.0, 0.84, 0.6) * (0.05 + 5.0 * night);
}
"""
	var m := ShaderMaterial.new()
	m.shader = _thing_shader
	m.set_shader_parameter("night", night)
	return m


## The signs: a face (vertex alpha 1; the back of a billboard 0.5) shows its cell of the signs'
## image (the instance's custom data: r the front's cell / 32, g the back's), lit at night where
## the image's alpha says (the lettering of a neon sign, all of a backlit one); a billboard's
## whole face floodlit a little. The rest steel.
static func _sign_material(night: float) -> ShaderMaterial:
	if _sign_shader == null:
		_sign_shader = Shader.new()
		_sign_shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform float night = 0.0;
uniform sampler2D signs : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying float cell;
varying float face;
void vertex() {
	face = COLOR.a;
	cell = COLOR.a > 0.75 ? INSTANCE_CUSTOM.r : INSTANCE_CUSTOM.g;
}
void fragment() {
	float idx = floor(cell * 32.0 + 0.5);
	vec2 at = vec2(mod(idx, 4.0), floor(idx / 4.0));
	vec2 uv = (at + clamp(UV, vec2(0.004), vec2(0.996))) / vec2(4.0, 8.0);
	vec4 t = texture(signs, uv);
	float is_face = step(0.25, face);
	ALBEDO = mix(vec3(0.3, 0.31, 0.32), t.rgb, is_face);
	ROUGHNESS = mix(0.6, 0.45, is_face);
	METALLIC = mix(0.4, 0.0, is_face);
	EMISSION = is_face * t.rgb * (t.a * (0.15 + 2.4 * night) + 0.25 * night);
}
"""
	var m := ShaderMaterial.new()
	m.shader = _sign_shader
	m.set_shader_parameter("night", night)
	var tex = load("res://assets/environment_runtime/city/signs.png") if ResourceLoader.exists("res://assets/environment_runtime/city/signs.png") else null
	m.set_shader_parameter("signs", tex)
	return m
