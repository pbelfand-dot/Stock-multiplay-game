extends RefCounted
## A rally stage, generated from a seed and described as DATA: the builder
## (meshes + collision), the co-driver's map, the AI co-driver and the car's position
## tracking all read the same arrays. Nothing here makes nodes.
##
## THE ROAD is a chain of pieces: straights and arcs (an arc can be two arcs
## back to back: a corner that TIGHTENS or OPENS). It's sampled every STEP m
## into a centerline: pts[i] (x, elevation, z), heading[i] (yaw, 0 = -Z, + =
## turning right), curv[i] (1/R, + = right). Position on the road is (s, d):
## s = metres from the start line, d = sideways, + = right of the direction of
## travel. The start line is s = START_S, the flying finish FINISH_BACK m
## before the end, so there's room to stop.
##
## Same seed -> same stage on every machine (host and co-driver build their own).

const STEP := 2.0
const ROAD_W := 5.6             # gravel width (m)
const START_S := 40.0           # the car waits here (start line)
const FINISH_BACK := 110.0      # flying finish this far before the end of the road
const CLEARANCE := 55.0         # two parts of the road that aren't neighbours stay this far apart (m)

## Corners are graded from the radius of the line a car can drive through them
## using the whole road (like the driver-test-app pacenote engine): 6 = nearly
## flat, 1 = very slow. Upper bound of that radius for grades 1..6 (m).
const GRADE_LIMITS := [25.0, 45.0, 75.0, 120.0, 200.0, 350.0]
const LINE_ROOM := 3.0          # sideways room the driving line gets (road minus the car, a bit spare)

var seed_used := 0
var pieces: Array = []          # [{kind: "straight", len} | {kind: "arc", dir, r, ang, r2, ang2}]
var pts := PackedVector3Array()
var heading := PackedFloat32Array()
var curv := PackedFloat32Array()
var length := 0.0               # metres of road
var finish_s := 0.0
var corners: Array = []         # [{s0, s1, dir, r_min, r_in, r_out, ang (deg), line_r, grade, shape, mods}]
var crests: Array = []          # [{s, h, w, jump}]
var puddles: Array = []         # [{s, d, r}]
var rocks: Array = []           # [{s, d, r}] on the inside of some corners: "don't cut"
var _rng := RandomNumberGenerator.new()
var _hills: Array = []          # [[amp, wavelength, phase] x2]


## Build the stage. `target` is roughly how long the road is (m).
func generate(seed_value: int, target := 2600.0) -> void:
	seed_used = seed_value
	for attempt in 60:
		_rng.seed = hash([seed_value, attempt])
		_make_pieces(target)
		_sample()
		if _clear_of_itself():
			break
	finish_s = length - FINISH_BACK
	_make_elevation()
	_find_corners()
	_place_extras()


# ── pieces ────────────────────────────────────────────────────────────────

func _make_pieces(target: float) -> void:
	pieces = [{"kind": "straight", "len": START_S + 40.0}]
	var total := START_S + 40.0
	var yaw := 0.0                  # where the road points, relative to the start (rad)
	var last_dir := 0
	while total < target - 140.0:
		# a straight (often short: rally roads are busy)
		var sl: float = [_rng.randf_range(15, 45), _rng.randf_range(30, 90), _rng.randf_range(80, 200)][_pick([5, 4, 2])]
		pieces.append({"kind": "straight", "len": sl})
		total += sl
		# a corner, or a run of them (S-bends link with no straight in between)
		var run := 1 + (1 if _rng.randf() < 0.35 else 0) + (1 if _rng.randf() < 0.12 else 0)
		for k in run:
			var c := _corner(yaw, last_dir if k > 0 else 0)
			if k > 0:
				pieces.append({"kind": "straight", "len": _rng.randf_range(0.0, 12.0)})
			pieces.append(c)
			yaw += c.dir * (c.ang + c.ang2)
			last_dir = c.dir
			total += c.r * c.ang + c.r2 * c.ang2
	pieces.append({"kind": "straight", "len": FINISH_BACK + 30.0})


## One corner. Its direction leans back toward the start heading so the stage
## meanders forward instead of curling into itself; `force_flip` makes the
## second half of an S-bend go the other way.
func _corner(yaw: float, force_flip: int) -> Dictionary:
	# radius classes, from hairpin to fast sweeper
	var cls := _pick([2, 3, 4, 4, 3, 2])
	var r: float = [12.0, 22.0, 38.0, 65.0, 110.0, 190.0][cls] * _rng.randf_range(0.85, 1.2)
	var ang_deg: float
	match cls:
		0: ang_deg = _rng.randf_range(120, 175)       # hairpin
		1: ang_deg = _rng.randf_range(70, 130)
		2: ang_deg = _rng.randf_range(45, 110)
		3: ang_deg = _rng.randf_range(30, 85)
		_: ang_deg = _rng.randf_range(20, 60)
	var dir := 1 if _rng.randf() < clampf(0.5 - yaw / PI, 0.1, 0.9) else -1
	if force_flip != 0:
		dir = -force_flip
	var c := {"kind": "arc", "dir": dir, "r": r, "ang": deg_to_rad(ang_deg), "r2": 0.0, "ang2": 0.0}
	# a quarter of the corners change radius halfway: tightens (r2 smaller) or opens
	if cls >= 1 and _rng.randf() < 0.25:
		var total_ang: float = c.ang
		c.ang = total_ang * _rng.randf_range(0.4, 0.6)
		c.ang2 = total_ang - c.ang
		c.r2 = r * (0.5 if _rng.randf() < 0.6 else 1.9)
	return c


func _pick(weights: Array) -> int:
	var sum := 0.0
	for w in weights:
		sum += w
	var x := _rng.randf() * sum
	for i in weights.size():
		x -= weights[i]
		if x <= 0.0:
			return i
	return weights.size() - 1


# ── centerline ────────────────────────────────────────────────────────────

func _sample() -> void:
	pts = PackedVector3Array()
	heading = PackedFloat32Array()
	curv = PackedFloat32Array()
	var p := Vector3.ZERO
	var h := 0.0
	var ks: Array = []        # curvature per metre, piece by piece
	for pc in pieces:
		if pc.kind == "straight":
			ks.append([pc.len, 0.0])
		else:
			ks.append([pc.r * pc.ang, pc.dir / pc.r])
			if pc.ang2 > 0.0:
				ks.append([pc.r2 * pc.ang2, pc.dir / pc.r2])
	pts.append(p)
	heading.append(h)
	curv.append(0.0)
	# walk the pieces a STEP at a time; a step that spans two pieces gets both curvatures
	var queue := ks
	var qi := 0
	var left_in_piece: float = queue[0][0]
	while qi < queue.size():
		var need := STEP
		var dh := 0.0
		while need > 1e-6 and qi < queue.size():
			var take := minf(need, left_in_piece)
			dh += take * queue[qi][1]
			need -= take
			left_in_piece -= take
			if left_in_piece <= 1e-6:
				qi += 1
				if qi < queue.size():
					left_in_piece = queue[qi][0]
		if need > 1e-6:
			break             # the last partial step: drop it
		var mid := h + dh * 0.5
		p += Vector3(sin(mid), 0.0, -cos(mid)) * STEP
		h += dh
		pts.append(p)
		heading.append(h)
		curv.append(dh / STEP)
	length = (pts.size() - 1) * STEP


## True if no two far-apart parts of the road come closer than CLEARANCE.
func _clear_of_itself() -> bool:
	var cell := CLEARANCE
	var grid := {}
	for i in pts.size():
		var key := Vector2i(floori(pts[i].x / cell), floori(pts[i].z / cell))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)
	var skip := int(CLEARANCE * 3.0 / STEP)     # neighbours along the road don't count
	for i in range(0, pts.size(), 2):
		var c := Vector2i(floori(pts[i].x / cell), floori(pts[i].z / cell))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for j in grid.get(c + Vector2i(dx, dz), []):
					if absi(j - i) > skip and Vector2(pts[i].x - pts[j].x, pts[i].z - pts[j].z).length() < CLEARANCE:
						return false
	return true


# ── elevation ─────────────────────────────────────────────────────────────

func _make_elevation() -> void:
	_hills = [
		[_rng.randf_range(3.0, 7.0), _rng.randf_range(260, 480), _rng.randf() * TAU],
		[_rng.randf_range(1.5, 3.5), _rng.randf_range(110, 200), _rng.randf() * TAU],
	]
	# crests every 180-380 m; on a long-enough straight some are JUMPS (sharper, taller)
	crests.clear()
	var s := START_S + 140.0
	while s < finish_s - 80.0:
		var straight := _straight_room(s)
		var jump := straight > 70.0 and _rng.randf() < 0.45
		crests.append({"s": s, "h": _rng.randf_range(1.6, 2.4) if jump else _rng.randf_range(1.0, 1.8),
			"w": _rng.randf_range(9.0, 12.0) if jump else _rng.randf_range(16.0, 26.0), "jump": jump})
		s += _rng.randf_range(180.0, 380.0)
	for i in pts.size():
		pts[i].y = height_at(i * STEP)


## Elevation of the road at s (m): two rolling hills plus the crests, flat at the start and finish.
func height_at(s: float) -> float:
	var y := 0.0
	for hl in _hills:
		y += hl[0] * sin(s / hl[1] * TAU + hl[2])
	for c in crests:
		var u: float = (s - c.s) / c.w
		if absf(u) < 1.0:
			y += c.h * 0.5 * (1.0 + cos(u * PI))      # a smooth bump, sharp enough to hide what's behind
	var flat := smoothstep(0.0, 120.0, s) * smoothstep(length, finish_s - 20.0, s)
	return y * flat


## How much straight road there is around s (m): no corner within that distance either way.
func _straight_room(s: float) -> float:
	var i := clampi(int(s / STEP), 0, curv.size() - 1)
	var a := i
	var b := i
	while a > 0 and absf(curv[a]) < 1.0 / 400.0:
		a -= 1
	while b < curv.size() - 1 and absf(curv[b]) < 1.0 / 400.0:
		b += 1
	return minf(i - a, b - i) * STEP * 2.0


# ── corners (what the AI co-driver calls) ─────────────────────────────────

func _find_corners() -> void:
	corners.clear()
	var s := 0.0
	for pc in pieces:
		if pc.kind == "straight":
			s += pc.len
			continue
		var l1: float = pc.r * pc.ang
		var l2: float = pc.r2 * pc.ang2
		var total_ang: float = rad_to_deg(pc.ang + pc.ang2)
		var r_min: float = pc.r if pc.ang2 == 0.0 else minf(pc.r, pc.r2)
		# the driving line uses the road's width over the WHOLE corner: the room term uses the total angle
		var room: float = LINE_ROOM / maxf(0.02, 1.0 - cos(deg_to_rad(minf(total_ang, 179.0)) * 0.5))
		var line_r: float = r_min + room
		var c := {"s0": s, "s1": s + l1 + l2, "dir": pc.dir, "r_min": r_min, "r_in": pc.r,
			"r_out": pc.r2 if pc.ang2 > 0.0 else pc.r, "ang": total_ang, "line_r": line_r,
			"grade": grade_for(pc.r + room), "shape": "", "mods": []}
		if total_ang >= 120.0 and line_r < 32.0:
			c.shape = "hairpin"
		elif total_ang >= 75.0 and total_ang <= 105.0 and line_r < 24.0:
			c.shape = "square"
		s += l1 + l2
		if pc.ang2 > 0.0 and pc.r2 < pc.r / 1.6:
			# TIGHTENS: called by the entry ("3 right tightens 2"); the tight part decides hairpin / caution
			var g2: int = grade_for(pc.r2 + room)
			if g2 > 0 and g2 < c.grade or (c.grade == 0 and g2 > 0):
				c.mods.append("tightens")
				c["grade2"] = g2
				if c.grade == 0:
					c.grade = mini(6, g2 + 1)
		elif pc.ang2 > 0.0 and pc.r2 > pc.r * 1.6 and c.grade > 0:
			c.mods.append("opens")
		if c.grade == 0 and c.shape == "":
			continue                                   # gentler than grade 6: not called
		if total_ang > 110.0 and c.shape != "hairpin":
			c.mods.append("long")
		corners.append(c)


## Grade 1..6 for a driving-line radius; 0 = gentler than 6 (not worth a call).
func grade_for(line_r: float) -> int:
	for g in GRADE_LIMITS.size():
		if line_r <= GRADE_LIMITS[g]:
			return g + 1
	return 0


# ── puddles and rocks ─────────────────────────────────────────────────────

func _place_extras() -> void:
	puddles.clear()
	rocks.clear()
	var s := START_S + 90.0
	while s < finish_s - 60.0:
		var n := 1 + (1 if _rng.randf() < 0.4 else 0)
		for k in n:
			puddles.append({"s": s + k * _rng.randf_range(6, 12), "d": _rng.randf_range(-1.6, 1.6), "r": _rng.randf_range(1.4, 2.4)})
		s += _rng.randf_range(260.0, 520.0)
	for c in corners:
		if (c.grade <= 4 or c.shape != "") and _rng.randf() < 0.45:
			var apex: float = (c.s0 + c.s1) * 0.5
			var rr := _rng.randf_range(0.55, 0.85)
			rocks.append({"s": apex, "d": c.dir * (ROAD_W * 0.5 + 0.5 + rr), "r": rr})   # just off the inside edge
			c.mods.append("dont-cut")


# ── queries ───────────────────────────────────────────────────────────────

## Centerline point at s (interpolated).
func point_at(s: float) -> Vector3:
	var f := clampf(s / STEP, 0.0, pts.size() - 1.001)
	var i := int(f)
	return pts[i].lerp(pts[i + 1], f - i)


func heading_at(s: float) -> float:
	var f := clampf(s / STEP, 0.0, heading.size() - 1.001)
	var i := int(f)
	return lerpf(heading[i], heading[i + 1], f - i)


## Unit vector pointing along the road at s (flat).
func forward_at(s: float) -> Vector3:
	var h := heading_at(s)
	return Vector3(sin(h), 0.0, -cos(h))


## Unit vector to the right of the road at s (flat).
func right_at(s: float) -> Vector3:
	var h := heading_at(s)
	return Vector3(cos(h), 0.0, sin(h))


## World position of road coordinates (s, d) (on the road surface).
func world_at(s: float, d: float) -> Vector3:
	return point_at(s) + right_at(s) * d


## Road coordinates of a world position: {s, d, i}. `hint` = an index near
## the answer (the last one), so tracking a car is cheap; -1 = search all.
func locate(p: Vector3, hint := -1) -> Dictionary:
	var lo := 0
	var hi := pts.size() - 2
	if hint >= 0:
		lo = maxi(0, hint - 40)
		hi = mini(pts.size() - 2, hint + 40)
	var best := -1
	var best_d2 := INF
	for i in range(lo, hi + 1):
		var dx := p.x - pts[i].x
		var dz := p.z - pts[i].z
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best = i
	# project onto the segment best..best+1
	var a := pts[best]
	var b := pts[best + 1]
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	var s := (best + t) * STEP
	var side := right_at(s)
	var on := a.lerp(b, t)
	var d := Vector2(p.x - on.x, p.z - on.z).dot(Vector2(side.x, side.z))
	return {"s": s, "d": d, "i": best}
