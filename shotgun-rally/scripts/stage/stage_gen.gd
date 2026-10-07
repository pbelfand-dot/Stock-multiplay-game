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
var bridges: Array = []         # [{s0, s1, depth}] wooden bridges over a gully (depth: m below the deck)
var sections: Array = []        # [{s0, s1, surface ("gravel" | "asphalt")}], end to end (_make_sections)
var joins: Array = []           # [{s, to}]: where the surface changes (to: what it is after)
var patches: Array = []         # [{s0, s1, d0, d1, surface, kind}]: gravel, ice, snow lying on the asphalt
var _rng := RandomNumberGenerator.new()
## Story rallies give a stage some character (set before generate(); none = an
## ordinary stage, exactly as before): narrow 0..1 leans the road narrow;
## puddles x as many puddles (the extras from their own random numbers);
## surface "gravel" (the default) / "tarmac" / "mixed", ice true: snow and ice
## on the asphalt (_make_sections, _make_patches).
var opts := {}
var _hills: Array = []          # [[amp, wavelength, phase] x2]
## The KIND of road (opts.kind): "rally" (the default: everything above), "touge" (a
## Japanese mountain pass: two narrow lanes of asphalt, hairpins and S-bends climbing
## (opts.dir "up") or falling ("down") across the mountainside, no jumps, no villages)
## or "highway" (the cutting-up mode's: HIGHWAY_LANES lanes one way, long straights and
## sweepers of 900-2,500 m, grades of a few per cent).
var kind := "rally"
const TOUGE_W := 6.4            # a touge's two lanes (m), give or take a little
const TOUGE_RISE := 0.075       # how much a touge climbs a metre of road (on average, before smoothing)
const HIGHWAY_LANES := 4
const LANE_W := 3.6
const HIGHWAY_SHOULDER := 1.5   # each side, outside the edge lines
const HIGHWAY_W := HIGHWAY_LANES * LANE_W + 2.0 * HIGHWAY_SHOULDER
const TOUGE_NAMES := ["KAZEMAKI", "AKAZAWA", "MIZUGAKI", "TSUKIKAGE", "KUROISHI", "HAYATE", "SHIRANAMI",
	"YUKIZURI", "OBORO", "KIRIGAMINE", "SAKAGURA", "HOTARUBI"]


## A touge's name (from its seed): "KAZEMAKI PASS".
func touge_name() -> String:
	return "%s PASS" % TOUGE_NAMES[absi(hash([seed_used, "touge"])) % TOUGE_NAMES.size()]


## Build the stage. `target` is roughly how long the road is (m).
func generate(seed_value: int, target := 2600.0) -> void:
	seed_used = seed_value
	kind = str(opts.get("kind", "rally"))
	if kind != "rally":
		opts = opts.duplicate()
		opts["surface"] = "tarmac"                   # (a touge and a highway are asphalt end to end)
	for attempt in 60:
		_rng.seed = hash([seed_value, attempt])
		_make_pieces(target)
		_sample()
		if _clear_of_itself():
			break
	finish_s = length - FINISH_BACK
	_make_sections()
	mountain = opts.get("surface", "gravel") == "tarmac" and kind != "highway"
	_make_widths()
	_make_elevation()
	_find_corners()
	if kind != "rally":
		_make_patches()                              # (snow and ice if asked; no puddles, bridges or villages)
		return
	_place_extras()
	_place_bridges()
	_make_patches()
	_place_towns()
	_place_villages()


# ── pieces ────────────────────────────────────────────────────────────────

func _make_pieces(target: float) -> void:
	if kind == "highway":
		_highway_pieces(target)
		return
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


## A highway: long straights and sweepers (900-2,500 m radius, 8-35 degrees), never
## two the same way running, so it heads on rather than curling round.
func _highway_pieces(target: float) -> void:
	pieces = [{"kind": "straight", "len": START_S + 160.0}]
	var total := START_S + 160.0
	var yaw := 0.0
	while total < target - 400.0:
		var sl := _rng.randf_range(250.0, 800.0)
		pieces.append({"kind": "straight", "len": sl})
		total += sl
		var r := _rng.randf_range(900.0, 2500.0)
		var ang := deg_to_rad(_rng.randf_range(8.0, 35.0))
		var dir := 1 if _rng.randf() < clampf(0.5 - yaw / (PI * 0.5), 0.1, 0.9) else -1
		pieces.append({"kind": "arc", "dir": dir, "r": r, "ang": ang, "r2": 0.0, "ang2": 0.0})
		yaw += dir * ang
		total += r * ang
	pieces.append({"kind": "straight", "len": FINISH_BACK + 120.0})


## One corner. Its direction leans back toward the start heading so the stage
## meanders forward instead of curling into itself; `force_flip` makes the
## second half of an S-bend go the other way.
func _corner(yaw: float, force_flip: int) -> Dictionary:
	# radius classes, from hairpin to fast sweeper (a mountain road: more hairpins and slow corners)
	var cls := _pick([4, 4, 4, 3, 2, 1] if opts.get("surface", "gravel") == "tarmac" else [2, 3, 4, 4, 3, 2])
	if kind == "touge":
		cls = _pick([6, 5, 4, 3, 1, 0])               # a pass: hairpins, tight S-bends, a few faster ones
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
	if kind == "highway":
		# long, low rises: a few metres over a kilometre or so (2-3 % at most)
		_hills = [[_rng.randf_range(3.0, 6.0), _rng.randf_range(1400, 2200), _rng.randf() * TAU],
			[_rng.randf_range(0.6, 1.2), _rng.randf_range(500, 800), _rng.randf() * TAU]]
		for i in pts.size():
			pts[i].y = height_at(i * STEP)
		_limit_grade()
		return
	# JUMPS on the long straights (a run-up and room to land in a straight line),
	# where the hillside isn't too steep (on a slope the jump just tilts with it,
	# but a steep one would push the landing past MAX_GRADE)
	var zones: Array = []                            # [from, to] each jump takes up
	for run in (_straight_runs(96.0) if kind == "rally" else []):
		var at: float = run.x + _rng.randf_range(36.0, 46.0)
		if at < START_S + 140.0 or at > finish_s - 240.0 or run.y - at < 58.0:
			continue
		if not all_gravel(at - 70.0, at + 170.0):
			continue                                     # (no Finnish jumps on an asphalt road)
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
			s += _rng.randf_range(180.0, 380.0) * (2.0 if kind == "touge" else 1.0)
	crests.sort_custom(func(p, q): return p.s < q.s)
	if mountain:
		_make_terrain()
	for i in pts.size():
		pts[i].y = height_at(i * STEP)
	_limit_grade()
	if mountain:
		_fit_terrain()


## No steeper than MAX_GRADE either way (a gravel road, not a ski jump: a crest on top
## of a steep drop used to throw the car 7 m down onto the flat at 110 km/h), then
## round the corners that leaves so the brows and dips stay smooth.
func _limit_grade() -> void:
	var step_max := max_grade() * STEP
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


## The steepest the road may get: a rally stage's MAX_GRADE, a touge a little less
## (it climbs all the way, so it's steep for longer), a highway 4 %.
func max_grade() -> float:
	return {"highway": 0.04, "touge": 0.13}.get(kind, MAX_GRADE)


## Elevation of the road at s (m): two rolling hills (on a mountain stage, the
## mountainside) plus the crests, the crests flat at the start and finish.
func height_at(s: float) -> float:
	var y := 0.0
	if not mountain:
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
	if mountain:
		return _mountain_road(s) + y * flat * 0.7
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
	if kind != "rally":
		widths.resize(pts.size())
		var wrng := RandomNumberGenerator.new()
		wrng.seed = hash([seed_used, "width"])
		var wobble := [wrng.randf() * TAU, wrng.randf_range(300.0, 600.0)]
		for j in pts.size():
			widths[j] = HIGHWAY_W if kind == "highway" else TOUGE_W + 0.3 * sin(j * STEP / wobble[1] * TAU + wobble[0])
		return
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


# ── puddles ───────────────────────────────────────────────────────────────

func _place_extras() -> void:
	puddles.clear()
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
	puddles = puddles.filter(func(p): return all_gravel(p.s - p.r - 2.0, p.s + p.r + 2.0))   # (mud puddles: the gravel's)


# ── bridges ───────────────────────────────────────────────────────────────

const BRIDGE_GAP := 600.0       # m at least between two bridges


## Wooden bridges over a gully with a stream in it, on straight, level road away
## from the corners, the crests and jumps, and the start and finish: about one
## every 1-1.5 km, 14-22 m long. Their own random numbers, so the rest of the
## stage is the same with or without them; puddles on one are taken away.
## opts.bridges = 0: none.
func _place_bridges() -> void:
	bridges.clear()
	if float(opts.get("bridges", 1.0)) <= 0.0:
		return
	var brng := RandomNumberGenerator.new()
	brng.seed = hash([seed_used, "bridges"])
	for max_curv in [1.0 / 220.0, 1.0 / 140.0]:      # (a twisty stage with none: try again, allowing a gentle bend)
		var s := START_S + 200.0 + brng.randf_range(0.0, 250.0)
		while s < finish_s - 200.0:
			s = snappedf(s, STEP)                    # (its ends on the road's samples: the road stops exactly where it starts)
			var span := snappedf(brng.randf_range(14.0, 22.0), STEP)
			if _bridge_fits(s, span, max_curv):
				bridges.append({"s0": s, "s1": s + span, "depth": brng.randf_range(2.8, 4.0)})
				s += span + BRIDGE_GAP + brng.randf_range(0.0, 500.0)
			else:
				s += 6.0
		if not bridges.is_empty():
			break
	puddles = puddles.filter(func(p): return not on_bridge(p.s, p.r + 8.0))


## Can a bridge go from s for `span` m? Straight (or nearly: no more curvature
## than max_curv) from 10 m before it to 10 m after, level, not on a corner, a
## crest or a jump (or their run-up and landing).
func _bridge_fits(s: float, span: float, max_curv: float) -> bool:
	var a := s - 10.0
	var b := s + span + 10.0
	if not all_gravel(a, b):
		return false                                     # (wooden bridges are on the gravel roads)
	for i in range(int(a / STEP), int(b / STEP) + 2):
		if i < 0 or i >= curv.size() or absf(curv[i]) > max_curv:
			return false
	for c in corners:
		if c.s1 > a and c.s0 < b:
			return false
	for c in crests:
		var lo: float = c.s - c.w * 0.5 - 15.0
		var hi: float = c.s + c.w * 0.8 + 15.0
		if c.jump:
			lo = c.s + c.x0 - 25.0
			hi = c.s + c.x0 + c.prof.size() + 25.0
		if hi > a and lo < b:
			return false
	return absf(point_at(s + span).y - point_at(s).y) < span * 0.03


## The bridge at s (within `margin` m of it), or an empty Dictionary.
func bridge_at(s: float, margin := 0.0) -> Dictionary:
	for b in bridges:
		if s >= b.s0 - margin and s <= b.s1 + margin:
			return b
	return {}


func on_bridge(s: float, margin := 0.0) -> bool:
	return not bridge_at(s, margin).is_empty()


## How far the ground is dug down at road coordinates (s, d) for a bridge's gully
## (m): deepest under the middle of the bridge, banks under its ends, closing in
## 35-70 m out to each side.
func gully_depth(s: float, d: float) -> float:
	var b := bridge_at(s)
	if b.is_empty():
		return 0.0
	var u: float = (s - b.s0) / (b.s1 - b.s0)
	return b.depth * smoothstep(0.0, 0.3, u) * smoothstep(0.0, 0.3, 1.0 - u) * (1.0 - smoothstep(35.0, 70.0, absf(d)))


# ── the mountainside (tarmac stages) ──────────────────────────────────────

## MOUNTAIN stages (the tarmac ones): the road climbs across a hillside, Monte
## Carlo / Corsica style, instead of rolling through a forest. The ground is one
## slope tilted across the stage's general direction (MOUNTAIN_SLOPE) with broad
## ridges on it (terrain_at). The road keeps to it along the centre line, so it
## runs level along the slope and climbs or drops as it turns across it (a pair
## of hairpins is a switchback), and the builder cuts it in: a bank on the uphill
## side, a drop on the other (armco or a stone wall where it's steep), and
## villages along the way. Its own random numbers.
const MOUNTAIN_SLOPE := 0.24
var mountain := false
var _tilt := Vector2.ZERO               # the slope (rise per metre in x, z)
var _ridges: Array = []                 # [[amplitude (m), wave (rad per m, in x and z), phase]]
var _t0 := 0.0                          # the mountainside's height at the start line: the road's zero there


func _make_terrain() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_used, "mountain"])
	var along := Vector2(pts[pts.size() - 1].x - pts[0].x, pts[pts.size() - 1].z - pts[0].z).normalized()
	_tilt = Vector2(-along.y, along.x) * MOUNTAIN_SLOPE * (1.0 if rng.randf() < 0.5 else -1.0)
	if kind == "touge":
		# a pass climbs the mountain (or comes down it): the slope runs along the road,
		# with a little across it so it hangs on a hillside
		# (~5 % of its length in all, however far apart its ends wound up: TOUGE_RISE a metre of road)
		var up := -1.0 if str(opts.get("dir", "up")) == "down" else 1.0
		var apart := Vector2(pts[pts.size() - 1].x - pts[0].x, pts[pts.size() - 1].z - pts[0].z).length()
		_tilt = along * minf(TOUGE_RISE * length * 0.66 / maxf(apart, 1.0), 0.3) * up + Vector2(-along.y, along.x) * MOUNTAIN_SLOPE * 0.35 * (1.0 if rng.randf() < 0.5 else -1.0)
	_ridges.clear()
	for k in 2:
		var a := rng.randf() * TAU
		var wl: float = rng.randf_range(300.0, 450.0) if k == 0 else rng.randf_range(110.0, 180.0)
		_ridges.append([rng.randf_range(4.0, 7.0) if k == 0 else rng.randf_range(1.0, 2.0), Vector2(cos(a), sin(a)) * TAU / wl, rng.randf() * TAU])
	_t0 = 0.0
	var i0 := int(START_S / STEP)
	_t0 = terrain_at(pts[i0].x, pts[i0].z)


## The mountainside's height at (x, z) (0 at the start line): the slope, bent to
## meet the road (_fit_terrain). Flat (0) on a stage that isn't a mountain one.
func terrain_at(x: float, z: float) -> float:
	if not mountain:
		return 0.0
	var y: float = _tilt.x * (x - pts[0].x) + _tilt.y * (z - pts[0].z) - _t0
	for r in _ridges:
		y += r[0] * sin(r[1].x * x + r[1].y * z + r[2])
	if not _fit.is_empty():
		var fx := clampf((x - _fit_o.x) / FIT_CELL, 0.0, _fit_nx - 1.001)
		var fz := clampf((z - _fit_o.y) / FIT_CELL, 0.0, _fit_nz - 1.001)
		var ix := int(fx)
		var iz := int(fz)
		var k := iz * _fit_nx + ix
		var u := fx - ix
		var v := fz - iz
		y += lerpf(lerpf(_fit[k], _fit[k + 1], u), lerpf(_fit[k + _fit_nx], _fit[k + _fit_nx + 1], u), v)
	return y


## Where the road can't keep to the slope (it's no steeper than MAX_GRADE, and
## smoothed) the slope is bent to meet it, so it isn't in a canyon or up on a dyke:
## the road's height minus the slope's, in the cells of a grid (FIT_CELL m) the road
## crosses, spread out from there (relaxed: each other cell the average of its
## neighbours, fading), so it eases back to the plain slope over ~150 m.
const FIT_CELL := 16.0
const FIT_OUT := 320.0
var _fit := PackedFloat32Array()
var _fit_o := Vector2.ZERO
var _fit_nx := 0
var _fit_nz := 0


func _fit_terrain() -> void:
	_fit = PackedFloat32Array()
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in pts:
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.z))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.z))
	_fit_o = mn - Vector2(FIT_OUT, FIT_OUT)
	var nx := int((mx.x - mn.x + 2.0 * FIT_OUT) / FIT_CELL) + 2
	var nz := int((mx.y - mn.y + 2.0 * FIT_OUT) / FIT_CELL) + 2
	var field := PackedFloat32Array()
	field.resize(nx * nz)
	# twice: the second time what's left over (the grid's cells are coarser than the road's bends)
	for _pass in 2:
		var sum := PackedFloat32Array()
		sum.resize(nx * nz)
		var cnt := PackedInt32Array()
		cnt.resize(nx * nz)
		for p in pts:
			var k := int(round((p.z - _fit_o.y) / FIT_CELL)) * nx + int(round((p.x - _fit_o.x) / FIT_CELL))
			sum[k] += p.y - terrain_at(p.x, p.z)
			cnt[k] += 1
		var add := PackedFloat32Array()
		add.resize(nx * nz)
		var free := PackedInt32Array()               # the cells the road doesn't cross (not edge cells)
		for k in nx * nz:
			if cnt[k] > 0:
				add[k] = sum[k] / cnt[k]
			elif k % nx > 0 and k % nx < nx - 1 and k >= nx and k < nx * (nz - 1):
				free.append(k)
		for _it in 40:
			var src := add.duplicate()
			for k in free:
				add[k] = (src[k - 1] + src[k + 1] + src[k - nx] + src[k + nx]) * 0.2475
		for k in nx * nz:
			field[k] += add[k]
		_fit_nx = nx
		_fit_nz = nz
		_fit = field.duplicate()


## The road's height on the mountainside at s, level through the start and the finish.
func _mountain_road(s: float) -> float:
	var p := point_at(s)
	var f := point_at(minf(finish_s + 30.0, length))
	var y := terrain_at(p.x, p.z) * smoothstep(START_S + 20.0, START_S + 150.0, s)
	return lerpf(y, terrain_at(f.x, f.z), smoothstep(finish_s - 90.0, finish_s, s))


## VILLAGES on the asphalt (a mountain road's, or a mixed stage's tarmac): one
## every 900-1400 m, on a stretch of 110-160 m that bends no tighter than 70 m,
## clear of the start, the finish and a join. Houses close to the road, a church
## tower, stone walls; the builder makes them. Their own random numbers.
const VILLAGE_NAMES := ["VALBRUNE", "SAINT-ORSO", "LES ARCELLES", "CASTELROC", "MONTAGNOLE", "PRAZ-SUR-ARVE",
	"SAINT-JULIEN", "LA BAUME", "COL-DE-FER", "BELVÉDÈRE", "LUCÉRAC", "ROQUEVAL"]
var villages: Array = []        # [{s0, s1, name}]


func _place_villages() -> void:
	villages.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_used, "villages"])
	var s := START_S + 260.0 + rng.randf_range(0.0, 300.0)
	while s < finish_s - 320.0:
		var l := rng.randf_range(110.0, 160.0)
		var ok := surface_at(s - 30.0) == "asphalt" and surface_at(s + l + 30.0) == "asphalt" and _gentle(s, s + l, 1.0 / 70.0) \
			and s + l < finish_s - 220.0 and town_at(s, l + 120.0).is_empty() and town_at(s + l, 120.0).is_empty()
		for j in joins:
			ok = ok and (j.s < s - 80.0 or j.s > s + l + 80.0)
		if ok:
			villages.append({"s0": s, "s1": s + l, "name": VILLAGE_NAMES[absi(hash([seed_used, villages.size()])) % VILLAGE_NAMES.size()]})
			s += l + rng.randf_range(900.0, 1400.0)
		else:
			s += 40.0


## TOWNS (on a mountain road, most stages one): a stretch of 260-360 m through the
## streets: buildings shoulder to shoulder right behind the pavements, crowd
## barriers along the kerbs, a side street or two and a square; corners up to a
## right-angle (no hairpins). The builder makes them; villages keep away. Its own
## random numbers.
const TOWN_NAMES := ["SAINT-AUBAN", "PORTOVAL", "BOURG-LA-ROCHE", "VILLEFRANQUE", "SAN MARCO ALTO", "CASTELMONT"]
var towns: Array = []           # [{s0, s1, name, square_s, square_side, streets: [[s, side]]}]


func _place_towns() -> void:
	towns.clear()
	if not mountain:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_used, "towns"])
	if rng.randf() > 0.75:
		return
	var l := rng.randf_range(260.0, 360.0)
	var tries: Array = []
	var s := START_S + 240.0
	while s + l < finish_s - 260.0:
		tries.append(s)
		s += 20.0
	if tries.is_empty():
		return
	var start := rng.randi() % tries.size()
	for k in tries.size():
		var a: float = tries[(start + k) % tries.size()]
		if surface_at(a - 30.0) == "asphalt" and surface_at(a + l + 30.0) == "asphalt" and _gentle(a - 10.0, a + l + 10.0, 1.0 / 18.0):
			var t := {"s0": a, "s1": a + l, "name": TOWN_NAMES[absi(hash([seed_used, "town"])) % TOWN_NAMES.size()],
				"square_s": a + l * rng.randf_range(0.4, 0.6), "square_side": -1.0 if rng.randf() < 0.5 else 1.0, "streets": []}
			for q in 1 + rng.randi() % 2:                # side streets, away from the square
				var at := snappedf(a + l * rng.randf_range(0.15, 0.85), STEP)
				if absf(at - t.square_s) > 40.0:
					t.streets.append([at, -1.0 if rng.randf() < 0.5 else 1.0])
			towns.append(t)
			return


## The town at s (within `margin` m of it), or {}.
func town_at(s: float, margin := 0.0) -> Dictionary:
	for t in towns:
		if s >= t.s0 - margin and s <= t.s1 + margin:
			return t
	return {}


## Does the road bend no tighter than max_k (1/m) from a to b?
func _gentle(a: float, b: float, max_k: float) -> bool:
	for i in range(maxi(int(a / STEP), 0), mini(int(b / STEP) + 1, curv.size())):
		if absf(curv[i]) > max_k:
			return false
	return true


## The village at s (within `margin` m of it), or {}.
func village_at(s: float, margin := 0.0) -> Dictionary:
	for v in villages:
		if s >= v.s0 - margin and s <= v.s1 + margin:
			return v
	return {}


# ── surfaces ──────────────────────────────────────────────────────────────

const JOIN_DIRT := 50.0         # m of gravel carried onto the asphalt after a join from gravel
## roughly how much grip, against gravel (the autopilot's corner speeds)
const SURFACE_GRIP := {"gravel": 1.0, "asphalt": 1.25, "snow": 0.45, "ice": 0.15}


## The road's sections: gravel all the way (the default: an ordinary stage, just
## as before), asphalt all the way (opts.surface "tarmac": a mountain road), or
## "mixed": two or three sections, gravel and asphalt in turn (like Rally
## Catalunya's), each join in the middle of a straight. Its own random numbers.
func _make_sections() -> void:
	sections.clear()
	joins.clear()
	var kind: String = opts.get("surface", "gravel")
	if kind != "mixed":
		sections = [{"s0": 0.0, "s1": length, "surface": "asphalt" if kind == "tarmac" else "gravel"}]
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_used, "surface"])
	var splits: Array = [rng.randf_range(0.4, 0.6)] if rng.randf() < 0.5 else [rng.randf_range(0.28, 0.4), rng.randf_range(0.6, 0.74)]
	var surf := "gravel" if rng.randf() < 0.5 else "asphalt"
	var runs := _straight_runs(50.0)
	var s0 := 0.0
	for u in splits:
		var at := _join_spot(START_S + (finish_s - START_S) * float(u), runs)
		if at < s0 + 300.0 or at > finish_s - 200.0:
			continue
		sections.append({"s0": s0, "s1": at, "surface": surf})
		surf = "asphalt" if surf == "gravel" else "gravel"
		joins.append({"s": at, "to": surf})
		s0 = at
	sections.append({"s0": s0, "s1": length, "surface": surf})


## Where a join goes near `want`: the middle of the nearest straight (within 300
## m), or else the straightest spot within 150 m.
func _join_spot(want: float, runs: Array) -> float:
	var best := -1.0
	for r in runs:
		var mid: float = snappedf((r.x + r.y) * 0.5, STEP)
		if absf(mid - want) < 300.0 and (best < 0.0 or absf(mid - want) < absf(best - want)):
			best = mid
	if best >= 0.0:
		return best
	var lo := int(maxf(want - 150.0, 0.0) / STEP)
	var hi := mini(int((want + 150.0) / STEP), curv.size() - 1)
	var bi := lo
	for i in range(lo, hi + 1):
		if absf(curv[i]) < absf(curv[bi]):
			bi = i
	return bi * STEP


## What lies on the asphalt (its own random numbers): gravel dragged onto it, for
## JOIN_DIRT m after a join from gravel (all across) and on the inside of slow
## corners where the cars cut them (the co-driver adds "don't cut"); and with
## opts.ice, Monte Carlo's winter: ice across a lane (or, on a straight, the whole
## road) and snow along an edge. Across the road a patch goes from d0 to d1 (m
## from the centre line, + = right); its edges are the wheel tracks (+-1.25), the
## centre line or beyond the road's edge, which is where the builder's strips meet,
## so what you see is exactly where the grip changes.
func _make_patches() -> void:
	patches.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_used, "patches"])
	for j in joins:
		if j.to == "asphalt":
			patches.append({"s0": j.s, "s1": j.s + JOIN_DIRT, "d0": -99.0, "d1": 99.0, "surface": "gravel", "kind": "join"})
	for c in corners:
		if surface_at(c.s0) != "asphalt" or surface_at(c.s1) != "asphalt":
			continue
		if (c.grade > 3 and c.shape == "") or c.ang < 40.0 or rng.randf() > 0.4:
			continue
		var l: float = c.s1 - c.s0
		patches.append({"s0": c.s0 + l * 0.2, "s1": c.s1 - l * 0.05, "d0": 1.25 if c.dir > 0 else -99.0,
			"d1": 99.0 if c.dir > 0 else -1.25, "surface": "gravel", "kind": "cut"})
		c.mods.append("dont-cut")
	if opts.get("ice", false):
		rng.seed = hash([seed_used, "ice"])              # (its own numbers: the corners' dirt doesn't move it)
		var s := START_S + 160.0 + rng.randf_range(0.0, 200.0)
		while s < finish_s - 90.0:
			var right := rng.randf() < 0.5
			var snow := rng.randf() < 0.5
			var l := rng.randf_range(35.0, 110.0) if snow else rng.randf_range(10.0, 26.0)
			if surface_at(s) != "asphalt" or surface_at(s + l) != "asphalt" or (not snow and _slow_corner(s - 25.0, s + l + 10.0)):
				s += 30.0
				continue
			if snow:                                     # ploughed to the side, a strip of it along one edge
				patches.append({"s0": s, "s1": s + l, "d0": 1.25 if right else -99.0, "d1": 99.0 if right else -1.25,
					"surface": "snow", "kind": "snow"})
			else:                                        # ice: a lane in the shade, or the whole road on a straight
				var whole := rng.randf() < 0.5 and _straightish(s - 30.0, s + l + 20.0)
				patches.append({"s0": s, "s1": s + l, "d0": -99.0 if whole or not right else 0.0,
					"d1": 99.0 if whole or right else 0.0, "surface": "ice", "kind": "ice"})
			s += l + rng.randf_range(200.0, 450.0)
	patches.sort_custom(func(a, b): return a.s0 < b.s0)


## Is there a slow corner (grade 1-2, a hairpin, a square) between a and b?
func _slow_corner(a: float, b: float) -> bool:
	for c in corners:
		if c.s1 > a and c.s0 < b and (c.grade <= 2 or c.shape != ""):
			return true
	return false


## Is the road nearly straight (no tighter than 150 m) all the way from a to b?
func _straightish(a: float, b: float) -> bool:
	for i in range(maxi(int(a / STEP), 0), mini(int(b / STEP) + 1, curv.size())):
		if absf(curv[i]) > 1.0 / 150.0:
			return false
	return true


## The stage's surface in words (the start line's title): "GRAVEL", "TARMAC",
## "TARMAC · SNOW AND ICE", "MIXED · GRAVEL / TARMAC / GRAVEL".
func describe() -> String:
	var names: Array = sections.map(func(x): return "TARMAC" if x.surface == "asphalt" else "GRAVEL")
	var out: String = names[0] if names.size() == 1 else "MIXED · " + " / ".join(names)
	for p in patches:
		if p.kind == "ice" or p.kind == "snow":
			return out + " · SNOW AND ICE"
	return out


## The road's own surface at s: "gravel" or "asphalt".
func surface_at(s: float) -> String:
	for sec in sections:
		if s < sec.s1:
			return sec.surface
	return sections[-1].surface if not sections.is_empty() else "gravel"


## Is the road gravel all the way from a to b?
func all_gravel(a: float, b: float) -> bool:
	for sec in sections:
		if sec.surface != "gravel" and sec.s1 > a and sec.s0 < b:
			return false
	return true


## What's under a tyre at road coordinates (s, d): the section's own surface, or
## what's lying on it there (gravel dragged on, ice, snow).
func surface_at_d(s: float, d: float) -> String:
	var out := surface_at(s)
	for p in patches:
		if p.s0 > s:
			break
		if s <= p.s1 and d >= p.d0 and d <= p.d1:
			out = p.surface
	return out


## The patch (of `kind`, or any) at road coordinates (s, d), or {}.
func patch_at(s: float, d: float, kind := "") -> Dictionary:
	var out := {}
	for p in patches:
		if p.s0 > s:
			break
		if s <= p.s1 and d >= p.d0 and d <= p.d1 and (kind == "" or p.kind == kind):
			out = p
	return out


## Grip across the road at (s, d), on top of the surface's own: on gravel the
## wheel tracks and the loose stuff (lane_grip); asphalt, ice and snow are the
## same all the way across.
func lane_mu(s: float, d: float) -> float:
	if surface_at_d(s, d) == "gravel":
		return lane_grip(d, width_at(s) * 0.5)
	return 1.0


## Roughly how much grip a car on the line d at s has, against gravel (the
## autopilot's corner speeds): more on the asphalt, much less on ice and snow
## under either side's tyres.
func grip_at(s: float, d := 0.0) -> float:
	var g: float = SURFACE_GRIP.get(surface_at(s), 1.0)
	for p in patches:
		if p.s0 > s + 4.0:
			break
		if s <= p.s1 + 4.0 and p.d0 < d + 0.9 and p.d1 > d - 0.9:
			g = minf(g, SURFACE_GRIP.get(p.surface, 1.0))
	return g


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
