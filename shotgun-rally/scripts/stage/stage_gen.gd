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
const MAX_GRADE := 0.16         # steepest the road gets (16 %)
const ROAD_W := 5.6             # gravel width (m), the normal width: the start and finish areas
## ... but the width changes along the stage, section by section, like real
## gravel roads (Finland: wide hard roads, then narrow technical bits): narrow
## where it's twisty, wide where it's open (widths[], width_at)
const WIDTHS := [4.6, 5.6, 6.8]                # narrow technical, normal, wide and fast
const START_S := 40.0           # the car waits here (start line)
const FINISH_BACK := 110.0      # flying finish this far before the end of the road
const CLEARANCE := 55.0         # two parts of the road that aren't neighbours stay this far apart (m)
## JUMPS, like Finland's: a gentle run-up, a short sharp brow, then a long landing
## slope that falls about as fast as a car flies off the brow (so it lands going
## the same way as the road, four wheels together), a dip and a climb back up.
## Flight time ~ 2 v (run-up + landing grade) / g: ~1 s at 110 km/h, ~0.7 s at
## 80; under ~60 km/h the brow is too gentle to leave the ground at all.
const JUMP_EASE := 14.0         # m to ease into the run-up / out of the climb back
const JUMP_BROW := 1.5          # half-length of the brow (m): sharp, so a fast car takes off
const JUMP_SAG := 45.0          # m from the landing slope back to climbing (the dip)
const JUMP_CLIMB := 0.05        # grade of the climb back (the jump ends at the height it started)

## Corners are graded from the radius of the line a car can drive through them
## using the whole road (like the driver-test-app pacenote engine): 6 = nearly
## flat, 1 = very slow. Upper bound of that radius for grades 1..6 (m).
const GRADE_LIMITS := [25.0, 45.0, 75.0, 120.0, 200.0, 350.0]
const LINE_SPARE := 2.6         # the driving line's sideways room = the road's width minus this (the car, a bit spare)

var seed_used := 0
var pieces: Array = []          # [{kind: "straight", len} | {kind: "arc", dir, r, ang, r2, ang2}]
var pts := PackedVector3Array()
var heading := PackedFloat32Array()
var curv := PackedFloat32Array()
var widths := PackedFloat32Array()   # road width at each sample (m)
var length := 0.0               # metres of road
var finish_s := 0.0
var corners: Array = []         # [{s0, s1, dir, r_min, r_in, r_out, ang (deg), line_r, grade, shape, mods}]
var crests: Array = []          # [{s, h, w, jump}] (+ a jump's shape: big, up, down, a, land, u, x0, prof)
var puddles: Array = []         # [{s, d, r}]
var rocks: Array = []           # [{s, d, r}] on the inside of some corners: "don't cut"
var _rng := RandomNumberGenerator.new()
## Story rallies give a stage some character (set before generate(); none = an
## ordinary stage, exactly as before): narrow 0..1 leans the road narrow;
## puddles x as many puddles (the extras from their own random numbers).
var opts := {}
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
	_make_widths()
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
		[_rng.randf_range(2.5, 5.0), _rng.randf_range(320, 520), _rng.randf() * TAU],
		[_rng.randf_range(1.0, 2.2), _rng.randf_range(150, 240), _rng.randf() * TAU],
	]
	crests.clear()
	# JUMPS on the long straights (a run-up and room to land in a straight line),
	# where the hillside isn't too steep (on a slope the jump just tilts with it,
	# but a steep one would push the landing past MAX_GRADE)
	var zones: Array = []                            # [from, to] each jump takes up
	for run in _straight_runs(96.0):
		var at: float = run.x + _rng.randf_range(36.0, 46.0)
		if at < START_S + 140.0 or at > finish_s - 240.0 or run.y - at < 58.0:
			continue
		var steepest := 0.0
		for x in [-40.0, -20.0, 0.0, 20.0, 40.0, 60.0]:
			steepest = maxf(steepest, absf(_hill_grade(at + x)))
		if steepest > 0.1 or (not zones.is_empty() and at - zones[-1].y < 60.0):
			continue
		# on a calm hillside about half are BIG ones ("caution, jump"): ~1.05 s of air at 120
		var j := _make_jump(at, steepest < 0.04 and _rng.randf() < 0.55)
		crests.append(j)
		zones.append(Vector2(at + j.x0, at + j.prof.size()))
	# blind crests every 180-380 m around them
	var s := START_S + 140.0
	while s < finish_s - 80.0:
		var clear := true
		for z in zones:
			if s > z.x - 45.0 and s < z.y + 25.0:
				s = z.y + 25.0
				clear = false
		if clear:
			crests.append({"s": s, "h": _rng.randf_range(1.0, 1.8), "w": _rng.randf_range(16.0, 26.0), "jump": false})
			s += _rng.randf_range(180.0, 380.0)
	crests.sort_custom(func(p, q): return p.s < q.s)
	for i in pts.size():
		pts[i].y = height_at(i * STEP)
	_limit_grade()


## No steeper than MAX_GRADE either way (a gravel road, not a ski jump: a crest on top
## of a steep drop used to throw the car 7 m down onto the flat at 110 km/h), then
## round the corners that leaves so the brows and dips stay smooth.
func _limit_grade() -> void:
	var step_max := MAX_GRADE * STEP
	for i in range(1, pts.size()):
		pts[i].y = clampf(pts[i].y, pts[i - 1].y - step_max, pts[i - 1].y + step_max)
	for i in range(pts.size() - 2, -1, -1):
		pts[i].y = clampf(pts[i].y, pts[i + 1].y - step_max, pts[i + 1].y + step_max)
	for _pass in 3:
		var ys := PackedFloat32Array()
		for p in pts:
			ys.append(p.y)
		for i in range(1, pts.size() - 1):
			pts[i].y = (ys[i - 1] + ys[i] * 2.0 + ys[i + 1]) * 0.25


## Elevation of the road at s (m): two rolling hills plus the crests, flat at the start and finish.
func height_at(s: float) -> float:
	var y := 0.0
	for hl in _hills:
		y += hl[0] * sin(s / hl[1] * TAU + hl[2])
	for c in crests:
		if c.jump:
			# the jump's own shape, worked out once (_make_jump), every metre
			var prof: PackedFloat32Array = c.prof
			var f: float = s - c.s - c.x0
			if f >= 0.0 and f < prof.size() - 1:
				var i := int(f)
				y += lerpf(prof[i], prof[i + 1], f - i)
			elif f >= prof.size() - 1:
				y += prof[prof.size() - 1]
			continue
		# a blind crest: a smooth bump, sharp enough to hide what's behind; its far side
		# is longer and gentler, so you come down onto road going down with you
		var u: float = (s - c.s) / (c.w if s < c.s else c.w * 1.6)
		if absf(u) < 1.0:
			y += c.h * 0.5 * (1.0 + cos(u * PI))
	var flat := smoothstep(0.0, 120.0, s) * smoothstep(length, finish_s - 20.0, s)
	return y * flat


## A jump with its brow at s: pick its grades and lengths, then add up its
## height every metre. The climb back is as long as it takes to end up level.
func _make_jump(s: float, big := false) -> Dictionary:
	var j := {"s": s, "jump": true, "big": big,
		"up": _rng.randf_range(0.07, 0.085) if big else _rng.randf_range(0.05, 0.075),     # run-up grade
		"down": _rng.randf_range(0.15, 0.16) if big else _rng.randf_range(0.11, 0.14),     # landing slope
		"a": _rng.randf_range(28.0, 40.0),          # run-up length (m)
		"land": _rng.randf_range(45.0, 60.0),       # landing slope length (m)
		"u": 0.0}
	j.x0 = -(j.a + JUMP_EASE)
	# where the dip ends: how far down it's got, then a climb back of the right length
	var drop := _integrate_jump(j, j.land + JUMP_SAG)
	j.u = maxf(0.0, -drop / JUMP_CLIMB - JUMP_EASE * 0.5)
	var x1: float = j.land + JUMP_SAG + j.u + JUMP_EASE
	var prof := PackedFloat32Array()
	var y := 0.0
	var x: float = j.x0
	prof.append(0.0)
	while x < x1:
		y += (_jump_grade(j, x + 0.25) + _jump_grade(j, x + 0.75)) * 0.5
		x += 1.0
		prof.append(y)
	j.prof = prof
	j.h = j.up * j.a                                # how high the brow stands over the run-up's start
	j.w = j.a                                       # (the co-driver calls it from halfway up the run-up)
	return j


func _integrate_jump(j: Dictionary, to: float) -> float:
	var y := 0.0
	var x: float = j.x0
	while x < to:
		y += _jump_grade(j, x + 0.25) * 0.5
		x += 0.5
	return y


## The jump's grade x m from its brow (+ = uphill).
func _jump_grade(j: Dictionary, x: float) -> float:
	var a: float = j.a
	var land: float = j.land
	var u: float = j.u
	if x < -a - JUMP_EASE:
		return 0.0
	if x < -a:
		return j.up * smoothstep(-a - JUMP_EASE, -a, x)
	if x < -JUMP_BROW:
		return j.up
	if x < JUMP_BROW:
		return lerpf(j.up, -j.down, smoothstep(-JUMP_BROW, JUMP_BROW, x))
	if x < land:
		return -j.down
	if x < land + JUMP_SAG:
		return lerpf(-j.down, JUMP_CLIMB, smoothstep(land, land + JUMP_SAG, x))
	if x < land + JUMP_SAG + u:
		return JUMP_CLIMB
	return JUMP_CLIMB * (1.0 - smoothstep(land + JUMP_SAG + u, land + JUMP_SAG + u + JUMP_EASE, x))


## The rolling hills' own grade at s.
func _hill_grade(s: float) -> float:
	var g := 0.0
	for hl in _hills:
		g += hl[0] * TAU / hl[1] * cos(s / hl[1] * TAU + hl[2])
	return g


## Grip across the road (x the surface's): the two worn wheel tracks, packed
## by every car before you, grip best; the loose crown between them a little
## less, and the "marbles" out toward the edges least, so running wide costs
## you. The builder paints the same bands (darker tracks).
static func lane_grip(d: float, half := ROAD_W * 0.5) -> float:
	var a := absf(d)
	if a > half + 0.3:
		return 1.0                                  # off the road: just the ground's own surface
	var track := smoothstep(0.35, 0.6, a) * (1.0 - smoothstep(1.2, 1.45, a))
	return lerpf(lerpf(0.93, 1.0, track), 0.84, smoothstep(1.4, maxf(half - 0.2, 1.6), a))


## The road's width along the stage: sections of 280-600 m, each narrow, normal
## or wide (twisty sections lean narrow, open ones wide), blended over ~40 m;
## the start and finish areas are normal width. Its own random numbers, so it
## doesn't change the rest of the stage.
func _make_widths() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_used, "width"])
	var raw := PackedFloat32Array()
	raw.resize(pts.size())
	var i := 0
	while i < pts.size():
		var n := int(rng.randf_range(280.0, 600.0) / STEP)
		var twist := 0.0
		for j in range(i, mini(i + n, pts.size())):
			twist += absf(curv[j])
		twist /= maxf(mini(i + n, pts.size()) - i, 1)          # mean 1/R: ~0.004 open .. ~0.02 twisty
		var weights := [0.5 + twist * 90.0, 2.0, maxf(1.6 - twist * 70.0, 0.15)]
		var narrow: float = opts.get("narrow", 0.0)
		weights[0] += narrow * 4.0
		weights[2] *= 1.0 - narrow * 0.85
		var x: float = rng.randf() * (weights[0] + weights[1] + weights[2])
		var w: float = WIDTHS[0] if x < weights[0] else (WIDTHS[1] if x < weights[0] + weights[1] else WIDTHS[2])
		for j in range(i, mini(i + n, pts.size())):
			raw[j] = w
		i += n
	# blend the steps (two passes of a 40 m box), then normal width at the start and finish
	for _pass in 2:
		var src := raw.duplicate()
		for j in pts.size():
			var sum := 0.0
			var cnt := 0
			for q in range(maxi(0, j - 10), mini(pts.size(), j + 11)):
				sum += src[q]
				cnt += 1
			raw[j] = sum / cnt
	widths.resize(pts.size())
	for j in pts.size():
		var sj := j * STEP
		var w: float = lerpf(ROAD_W, raw[j], smoothstep(START_S + 130.0, START_S + 190.0, sj))
		widths[j] = lerpf(w, ROAD_W, smoothstep(finish_s - 170.0, finish_s - 110.0, sj))


## Road width at s (m).
func width_at(s: float) -> float:
	var f := clampf(s / STEP, 0.0, widths.size() - 1.001)
	var i := int(f)
	return lerpf(widths[i], widths[i + 1], f - i)


## Every stretch of (nearly) straight road at least `min_len` m long: [Vector2(from, to)].
func _straight_runs(min_len: float) -> Array:
	var out: Array = []
	var start := -1
	for i in curv.size():
		var straight := absf(curv[i]) < 1.0 / 400.0
		if straight and start < 0:
			start = i
		if (not straight or i == curv.size() - 1) and start >= 0:
			if (i - start) * STEP >= min_len:
				out.append(Vector2(start * STEP, i * STEP))
			start = -1
	return out



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
		var line_room: float = width_at(s + (l1 + l2) * 0.5) - LINE_SPARE      # a narrow road: a tighter line
		var room: float = line_room / maxf(0.02, 1.0 - cos(deg_to_rad(minf(total_ang, 179.0)) * 0.5))
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
			var ps: float = s + k * _rng.randf_range(6, 12)
			var pd := minf(1.6, width_at(ps) * 0.5 - 1.2)
			puddles.append({"s": ps, "d": _rng.randf_range(-pd, pd), "r": _rng.randf_range(1.4, 2.4)})
		s += _rng.randf_range(260.0, 520.0)
	var more: float = opts.get("puddles", 1.0)
	if more > 1.0:
		var prng := RandomNumberGenerator.new()
		prng.seed = hash([seed_used, "puddles"])
		var ps := START_S + 150.0
		while ps < finish_s - 60.0:
			var pd := minf(1.6, width_at(ps) * 0.5 - 1.2)
			puddles.append({"s": ps, "d": prng.randf_range(-pd, pd), "r": prng.randf_range(1.4, 2.4)})
			ps += prng.randf_range(260.0, 520.0) / (more - 1.0)
	for c in corners:
		if (c.grade <= 4 or c.shape != "") and _rng.randf() < 0.45:
			var apex: float = (c.s0 + c.s1) * 0.5
			var rr := _rng.randf_range(0.55, 0.85)
			rocks.append({"s": apex, "d": c.dir * (width_at(apex) * 0.5 + 0.5 + rr), "r": rr})   # just off the inside edge
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
	# project onto the segment best..best+1, or best-1..best if the point is behind
	# best (otherwise s sticks at best's value for a while: it moved in 2 m jerks)
	var a := pts[best]
	var b := pts[best + 1]
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var t := ap.dot(ab) / maxf(ab.length_squared(), 1e-6)
	if t < 0.0 and best > 0:
		best -= 1
		a = pts[best]
		b = pts[best + 1]
		ab = Vector2(b.x - a.x, b.z - a.z)
		ap = Vector2(p.x - a.x, p.z - a.z)
		t = ap.dot(ab) / maxf(ab.length_squared(), 1e-6)
	t = clampf(t, 0.0, 1.0)
	var s := (best + t) * STEP
	var side := right_at(s)
	var on := a.lerp(b, t)
	var d := Vector2(p.x - on.x, p.z - on.z).dot(Vector2(side.x, side.z))
	return {"s": s, "d": d, "i": best}
