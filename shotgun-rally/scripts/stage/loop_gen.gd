extends "res://scripts/stage/stage_gen.gd"
## The LAKESHORE LOOP: cut up's one map, the same every time (tools/loop_map.py
## designs it into data/maps/lakeshore_loop.json). A ~28 km loop of divided
## highway: a city expressway on a viaduct, the lakeshore and three suspension
## bridges, hills and tunnels, and back to the city. It never ends: s wraps round.
##
## The same road API as StageGen (the car, the traffic, the score and the
## builder all read it), with s taken round the loop: any s works (the game
## keeps the player's s growing lap after lap; the traffic's too), world_at(s, d)
## is on the road's banked surface, locate() finds a point's s within the loop.
## Our carriageway: d from -7.2 to +7.2 (four lanes, d = 0 between the second and
## third), the right shoulder out to SHOULDER_R, the median barrier at d =
## MEDIAN_D, the other carriageway beyond it (ONCOMING_D: its centre).

const DATA := "res://data/maps/lakeshore_loop.json"
const CARRIAGEWAY := 14.4            # four lanes (m)
const SHOULDER_R := 3.0              # the right shoulder (AASHTO: 10 ft)
const SHOULDER_L := 1.0              # the left one, against the median
const MEDIAN := 2.0                  # median, kerb to kerb, the barrier in the middle
const BARRIER_H := 1.07              # the median's concrete barrier (42 in single slope)
const EDGE := CARRIAGEWAY * 0.5      # our lanes' edge lines are at d = +-EDGE
const MEDIAN_D := -(EDGE + SHOULDER_L + MEDIAN * 0.5)          # the median barrier's middle
const ONCOMING_D := MEDIAN_D - MEDIAN * 0.5 - SHOULDER_L - EDGE  # the other carriageway's middle
const OUTER_R := EDGE + SHOULDER_R + 0.4                        # our outer barrier
const OUTER_L := ONCOMING_D - EDGE - SHOULDER_R - 0.4           # theirs

var data := {}
var bank := PackedFloat32Array()     # cross-fall every STEP m (+: the right side down)
var spans: Array = []                # the suspension bridges [{s0, s1, towers, deck, sag, tower_h, main, name}]
var tunnels: Array = []              # [{s0, s1, name}]
var zones: Array = []                # [{s0, s1, kind}] "city", "lake", "hills"
var support: Array = []              # [{s0, s1, kind}] "ground", "viaduct", "bridge", "tunnel"
var ramps: Array = []                # [{s, side, kind, len}]
var overpasses: Array = []
var gantries: Array = []
var lakes: Array = []
var land_hills: Array = []
var city: Array = []
var city_ground := 4.0
var _n := 0                          # samples round the loop (pts has one more: the start again)
var _bumps := FastNoiseLite.new()
var extra_r := PackedFloat32Array()  # per sample: an acceleration/deceleration lane's width on our right (0..LANE_W)
var extra_l := PackedFloat32Array()  # ... on the other carriageway's right (our left)
var _ramp_paths := {}
var _hill_grid := {}                 # 500 m cells -> the hills that reach into them (land_at)
const HILL_CELL := 500.0


func generate(seed_value: int, _target := 2600.0) -> void:
	seed_used = seed_value
	kind = "loop"
	opts = opts.duplicate()
	opts["surface"] = "tarmac"
	opts["kind"] = "loop"
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	pieces = data.pieces
	_sample()
	_n = pts.size() - 1
	length = _n * STEP
	finish_s = INF                   # (no finish: you drive until you stop)
	var ys: Array = data.y
	var bs: Array = data.bank
	bank.resize(_n + 1)
	for i in _n + 1:
		pts[i].y = float(ys[i % _n])
		bank[i] = float(bs[i % _n])
	pts[_n] = Vector3(pts[0].x, pts[0].y, pts[0].z)    # (it closes: the last sample is the first)
	widths.resize(pts.size())
	widths.fill(CARRIAGEWAY + SHOULDER_R + SHOULDER_L)
	sections = [{"s0": 0.0, "s1": length, "surface": "asphalt"}]
	joins = []
	patches = []
	puddles = []
	bridges = []                     # (the rally stages' wooden bridges: none)
	crests = []
	corners = []
	spans = data.bridges
	tunnels = data.tunnels
	zones = data.zones
	support = data.support
	ramps = data.ramps
	overpasses = data.overpasses
	gantries = data.gantries
	lakes = data.lakes
	land_hills = data.hills
	city = data.city
	city_ground = float(data.get("city_ground", 4.0))
	_hill_grid.clear()
	for k in land_hills.size():
		var hl = land_hills[k]
		var reach: float = float(hl.r) * 2.0
		for cx in range(floori((hl.x - reach) / HILL_CELL), floori((hl.x + reach) / HILL_CELL) + 1):
			for cz in range(floori((hl.z - reach) / HILL_CELL), floori((hl.z + reach) / HILL_CELL) + 1):
				var key := Vector2i(cx, cz)
				if not _hill_grid.has(key):
					_hill_grid[key] = []
				_hill_grid[key].append(hl)
	_extra_lanes()
	_find_toll()
	_bumps.seed = 7
	_bumps.frequency = 1.0 / 260.0
	_bumps.fractal_octaves = 3


## THE TOLL PLAZA: one across both carriageways where the road runs straight on the ground,
## clear of the ramps, overpasses and gantries (_find_toll: the same spot every time).
## toll = {s, half (m along, either side of s), approach (m before it where lanes are kept),
## layout ("open": every lane open, gates up, full speed; "mixed": the right-hand lane of each
## carriageway closed (a cash booth shut), the traffic out of it beforehand, the open ones
## slowed; "event": all open, gates up, the lane lights green, for a race), closed: [lanes]}.
## opts.toll picks the layout ("open" by default: cut up's gameplay first).
var toll := {}
const TOLL_HALF := 16.0              # the islands and booths: 32 m along the road
const TOLL_APPROACH := 320.0         # lanes kept from this far before (and the closed lane emptied before that)
const TOLL_SPEED := {"open": 0.0, "mixed": 16.7, "event": 0.0}   # m/s the traffic slows to through it (0: not at all)

func _find_toll() -> void:
	var best := -1.0
	var best_score := -INF
	var s := 400.0
	while s < length - 400.0:
		var ok := true
		var x := s - TOLL_APPROACH - 80.0
		var bend := 0.0
		while x <= s + TOLL_HALF + 140.0:
			if support_at(x) != "ground" or tunnel_at(x, 60.0).size() > 0 or span_at(x, 60.0).size() > 0:
				ok = false
				break
			bend = maxf(bend, absf(curv_at(x)))
			x += 20.0
		if ok:
			for r in ramps:
				if absf(_wrapped_ds(float(r.s), s)) < 600.0:
					ok = false
			for o in overpasses:
				if absf(_wrapped_ds(float(o.s), s)) < 300.0:
					ok = false
			for g in gantries:
				if absf(_wrapped_ds(float(g.s), s)) < 260.0:
					ok = false
		if ok and bend < 1.0 / 1500.0:
			var score := -bend * 10000.0 + (1.0 if zone_at(s) == "lake" else 0.0)
			if score > best_score:
				best_score = score
				best = s
		s += 25.0
	if best < 0.0:
		toll = {}
		return
	var layout := str(opts.get("toll", "open"))
	if not TOLL_SPEED.has(layout):
		layout = "open"
	toll = {"s": best, "half": TOLL_HALF, "approach": TOLL_APPROACH, "layout": layout,
		"closed": [0] if layout == "mixed" else [], "speed": float(TOLL_SPEED[layout])}


func _wrapped_ds(a: float, b: float) -> float:
	return fposmod(a - b + length * 0.5, length) - length * 0.5


## Where s is against the toll plaza: -1 none, 0 its approach (lanes kept), 1 at the booths.
func toll_zone(s: float) -> int:
	if toll.is_empty():
		return -1
	var ds := _wrapped_ds(s, float(toll.s))
	if absf(ds) <= float(toll.half) + 4.0:
		return 1
	if ds < 0.0 and ds > -(float(toll.half) + float(toll.approach)):
		return 0
	return -1


## This lane shut at the plaza (the mixed layout's cash booth): traffic leaves it beforehand.
func toll_closed(lane: int) -> bool:
	return not toll.is_empty() and lane in toll.get("closed", [])


## Where s is against the plaza for traffic going `dir` (+1 ours, up s; -1 the other
## carriageway's, down s): -1 none, 0 its approach, 1 at the booths.
func toll_zone_dir(s: float, dir: int) -> int:
	if dir > 0 or toll.is_empty():
		return toll_zone(s)
	var ds := _wrapped_ds(s, float(toll.s))
	if absf(ds) <= float(toll.half) + 4.0:
		return 1
	if ds > 0.0 and ds < float(toll.half) + float(toll.approach):
		return 0
	return -1


## At the plaza the lanes fan out (each carriageway's spread about its middle, TOLL_SPREAD
## times): the booths' islands stand on the lane lines with a full lane's room between them
## (3.6 m clear, 0.9 m islands), the outer ones on the shoulder and the median. Eased in over
## SPREAD_EASE m before and out after (about 1.3 m sideways for the outer lanes over 160 m:
## the traffic and the lines drift out, nobody has to change lanes).
const TOLL_SPREAD := 1.25
const TOLL_ISLAND_W := 0.9
const SPREAD_HOLD := 40.0            # m past the islands' ends the lanes stay spread
const SPREAD_EASE := 160.0

func toll_spread(s: float) -> float:
	if toll.is_empty():
		return 1.0
	var x := absf(_wrapped_ds(s, float(toll.s))) - float(toll.half) - SPREAD_HOLD
	if x <= 0.0:
		return TOLL_SPREAD
	if x >= SPREAD_EASE:
		return 1.0
	return lerpf(TOLL_SPREAD, 1.0, smoothstep(0.0, 1.0, x / SPREAD_EASE))


## A lane's d (where it'd be on the open road) where it really is at s: fanned out at the plaza.
func toll_d(d: float, s: float) -> float:
	var k := toll_spread(s)
	if k == 1.0:
		return d
	var mid: float = 0.0 if d > MEDIAN_D else ONCOMING_D
	return mid + (d - mid) * k


## A line at d (the autopilot's, astride a lane line) moved into the middle of the nearest
## lane where the plaza's islands are (and the lanes spread: toll_d); elsewhere d.
func toll_lane_d(d: float, s: float) -> float:
	var sp := toll_spread(s)
	if sp == 1.0:
		return d
	var mid: float = 0.0 if d > MEDIAN_D else ONCOMING_D
	var k := clampi(int(floor((d - mid) / LANE_W + 2.0)), 0, 3)
	# (eased over with the lanes' fanning out: no step in the line)
	return lerpf(d, toll_d(mid + (float(k) - 1.5) * LANE_W, s), (sp - 1.0) / (TOLL_SPREAD - 1.0))


func touge_name() -> String:
	return str(data.get("name", "LAKESHORE LOOP"))


func describe() -> String:
	return "HIGHWAY · %.0f KM LOOP" % (length / 1000.0)


func max_grade() -> float:
	return 0.04


# ── round the loop ────────────────────────────────────────────────────────

## s brought into [0, length).
func wrap_s(s: float) -> float:
	return fposmod(s, length)


## The s round the loop nearest `near` (which can be any number of laps on) for a
## point at `s_in_loop` (0 .. length): a car's s keeps growing as it goes round.
func unwrap(s_in_loop: float, near: float) -> float:
	var base := near - wrap_s(near)
	var best := base + s_in_loop
	for k in [-1.0, 1.0]:
		var c: float = base + s_in_loop + k * length
		if absf(c - near) < absf(best - near):
			best = c
	return best


## The sample index for s (wrapped), and how far on to the next.
func _at(s: float) -> Vector2:
	var f := wrap_s(s) / STEP
	var i := mini(int(f), _n - 1)
	return Vector2(i, f - i)


func point_at(s: float) -> Vector3:
	var a := _at(s)
	return pts[int(a.x)].lerp(pts[int(a.x) + 1], a.y)


func heading_at(s: float) -> float:
	var a := _at(s)
	return lerpf(heading[int(a.x)], heading[int(a.x) + 1], a.y)


func bank_at(s: float) -> float:
	var a := _at(s)
	return lerpf(bank[int(a.x)], bank[int(a.x) + 1], a.y)


func curv_at(s: float) -> float:
	return curv[int(_at(s).x)]


func width_at(_s: float) -> float:
	return CARRIAGEWAY + SHOULDER_R + SHOULDER_L


func height_at(s: float) -> float:
	return point_at(s).y


## World position of (s, d), on the road's banked surface.
func world_at(s: float, d: float) -> Vector3:
	return point_at(s) + right_at(s) * d + Vector3.UP * (-d * bank_at(s))


## The road's up at s (tilted by its banking).
func up_at(s: float) -> Vector3:
	var b := bank_at(s)
	return (Vector3.UP + right_at(s) * b).normalized()


func surface_at(_s: float) -> String:
	return "asphalt"


func surface_at_d(_s: float, _d: float) -> String:
	return "asphalt"


func lane_mu(_s: float, _d: float) -> float:
	return 1.0


func grip_at(_s: float, _d := 0.0) -> float:
	return SURFACE_GRIP.get("asphalt", 1.3)


## Road coordinates of a world position: {s (0 .. length), d, i}. `hint`: a sample
## near the answer (the last one), so tracking a car is cheap; -1 searches the loop.
func locate(p: Vector3, hint := -1) -> Dictionary:
	var best := -1
	var best_d2 := INF
	var lo := 0
	var count := _n
	if hint >= 0:
		lo = hint - 40
		count = 81
	for k in count:
		var i := posmod(lo + k, _n)
		var dx := p.x - pts[i].x
		var dz := p.z - pts[i].z
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best = i
	var a := pts[best]
	var b := pts[best + 1]
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var t := Vector2(p.x - a.x, p.z - a.z).dot(ab) / maxf(ab.length_squared(), 1e-6)
	if t < 0.0:
		best = posmod(best - 1, _n)
		a = pts[best]
		b = pts[best + 1]
		ab = Vector2(b.x - a.x, b.z - a.z)
		t = Vector2(p.x - a.x, p.z - a.z).dot(ab) / maxf(ab.length_squared(), 1e-6)
	t = clampf(t, 0.0, 1.0)
	var s := (best + t) * STEP
	var side := right_at(s)
	var on := a.lerp(b, t)
	var d := Vector2(p.x - on.x, p.z - on.z).dot(Vector2(side.x, side.z))
	return {"s": s, "d": d, "i": best}


# ── what's along it ───────────────────────────────────────────────────────

func _in(list: Array, s: float, margin := 0.0) -> Dictionary:
	var w := wrap_s(s)
	for r in list:
		if w >= float(r.s0) - margin and w <= float(r.s1) + margin:
			return r
	return {}


func zone_at(s: float) -> String:
	var z := _in(zones, s)
	return str(z.kind) if not z.is_empty() else "city"


func support_at(s: float) -> String:
	var z := _in(support, s)
	return str(z.kind) if not z.is_empty() else "ground"


func span_at(s: float, margin := 0.0) -> Dictionary:
	return _in(spans, s, margin)


func tunnel_at(s: float, margin := 0.0) -> Dictionary:
	return _in(tunnels, s, margin)


## The land's height at x, z (the water is at 0): the highest hill there, the lakes
## carved out, small bumps on top (the same as tools/loop_map.py's, plus the bumps).
func land_at(x: float, z: float) -> float:
	var h := 4.0
	for hl in _hill_grid.get(Vector2i(floori(x / HILL_CELL), floori(z / HILL_CELL)), []):
		var d2: float = ((x - hl.x) * (x - hl.x) + (z - hl.z) * (z - hl.z)) / (hl.r * hl.r)
		if d2 < 4.0:
			var t := 1.0 - d2 / 4.0
			h = maxf(h, 4.0 + (float(hl.h) - 4.0) * t * t * (3.0 - 2.0 * t))
	h += _bumps.get_noise_2d(x, z) * 3.0 * clampf((h - 3.0) / 6.0, 0.0, 1.0)
	for lk in lakes:
		var c := cos(-float(lk.rot))
		var sn := sin(-float(lk.rot))
		var dx: float = x - lk.x
		var dz: float = z - lk.z
		var u: float = (dx * c - dz * sn) / lk.a
		var v: float = (dx * sn + dz * c) / lk.b
		var e := u * u + v * v
		if e < 1.6:
			var sh := clampf((1.3 - e) / 0.3, 0.0, 1.0)
			h = lerpf(h, -float(lk.depth), sh)
	return h


## Is (x, z) in the city (where the towers stand)?
func in_city(x: float, z: float) -> bool:
	for c in city:
		if (x - c.x) * (x - c.x) + (z - c.z) * (z - c.z) < c.r * c.r:
			return true
	return false


## A ramp's road: {pts, heads, len}, from its gore (where it meets the highway, in the
## middle of its extra lane) out to where it ends, 4 m a point. It runs alongside
## the highway at first, then curves away (260 m radius) and down to the ground (6 %).
## An exit's traffic drives it from the gore out; an entry's from the end in.
func ramp_path(r: Dictionary) -> Dictionary:
	var key := "%s/%s/%.1f" % [r.side, r.kind, r.s]
	if _ramp_paths.has(key):
		return _ramp_paths[key]
	var right: bool = r.side == "right"
	var gore: float = r.s
	var d0: float = (EDGE + LANE_W * 0.5 + SHOULDER_R - LANE_W * 0.5) if right else (ONCOMING_D - EDGE - SHOULDER_R + LANE_W * 0.5 - LANE_W * 0.5)
	d0 = (EDGE + LANE_W * 0.5) if right else (ONCOMING_D - EDGE - LANE_W * 0.5)
	var travel := 1.0 if right else -1.0          # which way round the loop its carriageway's traffic goes
	var walk := travel * (1.0 if r.kind == "off" else -1.0)   # which way the path walks from the gore
	var away := 1.0 if right else -1.0            # which way (in d) it leaves
	var p := world_at(gore, d0)
	var h := heading_at(gore) + (0.0 if walk > 0.0 else PI)
	var y := p.y
	var pts := PackedVector3Array()
	var heads := PackedFloat32Array()
	var n := 90
	for k in n + 1:
		pts.append(Vector3(p.x, y, p.z))
		heads.append(h)
		var u := float(k) / n
		# turning away from the road: right of travel for our ramps, left for theirs, either way the walk goes
		h += (1.0 / 260.0) * smoothstep(0.08, 0.35, u) * away * signf(walk) * 4.0
		p += Vector3(sin(h), 0.0, -cos(h)) * 4.0
		var g := maxf(land_at(p.x, p.z), city_ground if in_city(p.x, p.z) else -1.0)
		y = move_toward(y, maxf(g, 0.5) + 0.3, 0.06 * 4.0 * smoothstep(0.1, 0.3, u))
	var out := {"pts": pts, "heads": heads, "len": n * 4.0}
	_ramp_paths[key] = out
	return out


## The ramps' extra lanes, sample by sample: a deceleration lane before an exit (a 60 m
## taper, then full), an acceleration lane after an entry (full, then an 80 m taper),
## on the right of whichever carriageway the ramp is on, the way its traffic goes.
func _extra_lanes() -> void:
	extra_r.resize(_n)
	extra_l.resize(_n)
	extra_r.fill(0.0)
	extra_l.fill(0.0)
	for r in ramps:
		var len_: float = r.len
		var travel := 1.0 if r.side == "right" else -1.0
		var i0 := int((float(r.s) - len_ - 100.0) / STEP)
		var i1 := int((float(r.s) + len_ + 100.0) / STEP)
		for i in range(i0, i1 + 1):
			var s := i * STEP
			var ds := gore_ds(s, float(r.s)) * travel           # m past the gore, the way its traffic goes
			var w := 0.0
			if r.kind == "off" and ds > -len_ and ds <= 0.0:
				w = clampf((ds + len_) / 60.0, 0.0, 1.0)
			elif r.kind == "on" and ds >= 0.0 and ds < len_:
				w = clampf((len_ - ds) / 80.0, 0.0, 1.0)
			if w > 0.0:
				var j := posmod(i, _n)
				if r.side == "right":
					extra_r[j] = maxf(extra_r[j], w * LANE_W)
				else:
					extra_l[j] = maxf(extra_l[j], w * LANE_W)


## s - s0 the nearest way round the loop (-length/2 .. length/2).
func gore_ds(s: float, s0: float) -> float:
	return fposmod(s - s0 + length * 0.5, length) - length * 0.5


## The extra lane's width on our right at s (0: none).
func extra_lane(s: float) -> float:
	return extra_r[int(_at(s).x)]
