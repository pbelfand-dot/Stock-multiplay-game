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
var ramp_r := PackedFloat32Array()   # per sample: a ramp's middle's d where its lane's still on our widened edge (0: none)
var ramp_l := PackedFloat32Array()   # ... on the other carriageway's
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
	_find_station()
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


## THE GAS STATION (cut up starts at its pumps): a services forecourt where one of our side's
## junctions ends up, its exit's and its next entry's ramps (their ends ~60 m apart: the
## forecourt joins them), on the ground (the city's, mostly: the towers keep off it), out of the
## lakes, clear of the highway
## (_find_station: the same one every time). station = {off, on (the two ramps), c (the
## forecourt's middle, on its plane), u (across it: from the exit's end to the entry's), w (out:
## away from the highway), gy (the plane's rise a metre of u), s (the highway's s nearest it),
## flat (how far the land's off the plane)}. land_at flattens the ground under it.
var station := {}
const STATION_HALF := Vector2(34.0, 24.0)    # m: half the forecourt, across (u) and out (w)
const STATION_EASE := 24.0                   # m round it where the land eases back to its own
const STATION_SINK := 0.2                    # m: the land under it, below its top (its kerb)
## The pumps' places (u, w from the middle): two rows of four lanes between the islands, the
## first row at the pumps, every car nosed towards the entry's side; a racer's slot picks one.
const STATION_SPOTS := [[3.0, -6.0], [3.0, 0.0], [3.0, -12.0], [3.0, 6.0], [-6.0, -6.0], [-6.0, 0.0], [-6.0, -12.0], [-6.0, 6.0]]

func _find_station() -> void:
	station = {}
	var best := -INF
	for off in ramps:
		if off.side != "right" or off.kind != "off":
			continue
		for on in ramps:
			if on.side != "right" or on.kind != "on":
				continue
			var gap := gore_ds(float(on.s), float(off.s))
			if gap < 300.0 or gap > 800.0:
				continue
			var c := _station_at(off, on)
			if c.is_empty():
				continue
			# flattest, least tilted; then the nearest the start
			var score := -float(c.flat) * 2.0 - absf(float(c.gy)) * 60.0 - absf(gore_ds(float(on.s), START_S)) * 0.0005
			if score > best:
				best = score
				station = c


## A forecourt where these two ramps end, or {} if there's no room for one there.
func _station_at(off: Dictionary, on: Dictionary) -> Dictionary:
	var po := ramp_path(off)
	var pn := ramp_path(on)
	var eo: Vector3 = po.pts[po.pts.size() - 1]
	var en: Vector3 = pn.pts[pn.pts.size() - 1]
	var span := Vector2(en.x - eo.x, en.z - eo.z)
	if span.length() < 20.0 or span.length() > 70.0:
		return {}
	var u := Vector3(span.x, 0.0, span.y).normalized()
	var w := u.cross(Vector3.UP)
	var ho: float = po.heads[po.heads.size() - 1]
	var hn: float = pn.heads[pn.heads.size() - 1]
	if Vector3(sin(ho) + sin(hn), 0.0, -cos(ho) - cos(hn)).dot(w) < 0.0:
		w = -w                                          # (out: the way both ramps' ends head)
	var mid := (eo + en) * 0.5
	var out := {"off": off, "on": on, "c": mid + w * (STATION_HALF.y - 4.0), "u": u, "w": w,
		"gy": (en.y - eo.y) / span.length(), "flat": 0.0}
	out.c.y = mid.y
	if absf(float(out.gy)) > 0.05:
		return {}
	# the land under it and round it: no water, no city, not far off the plane; the highway
	# (any part of the loop) well clear
	var flat := 0.0
	var hx: float = STATION_HALF.x + 8.0
	var hy: float = STATION_HALF.y + 8.0
	var a := -hx
	while a <= hx + 0.01:
		var b := -hy
		while b <= hy + 0.01:
			var p: Vector3 = out.c + u * a + w * b
			var g := land_at(p.x, p.z)
			if g < 1.0:
				return {}                               # (in a lake)
			flat = maxf(flat, absf(g - (float(out.c.y) + float(out.gy) * a - 0.3)))
			b += 8.0
		a += 9.0
	if flat > 3.0:
		return {}
	for q in [[-1, -1], [0, -1], [1, -1], [-1, 0], [1, 0], [-1, 1], [0, 1], [1, 1]]:
		var at := locate(out.c + u * hx * q[0] + w * hy * q[1])
		var dd: float = float(at.d)
		if absf(dd - (0.0 if dd > ONCOMING_D * 0.5 else ONCOMING_D)) < EDGE + 30.0:
			return {}
	out.flat = flat
	out.s = float(locate(out.c).s)
	return out


## A point on the forecourt: across (a) and out (b) from its middle, on its plane, `up` over it.
func station_at(a: float, b: float, up := 0.0) -> Vector3:
	var p: Vector3 = station.c + station.u * a + station.w * b
	p.y = float(station.c.y) + float(station.gy) * a + up
	return p


## Slot k's place at the pumps: [position, heading] (headings as heading_at's).
func station_spot(k: int) -> Array:
	var q: Array = STATION_SPOTS[posmod(k, STATION_SPOTS.size())]
	var f: Vector3 = station.u
	return [station_at(float(q[0]), float(q[1])), atan2(f.x, -f.z)]


## The way out from slot k's place to the highway (Autopilot.route): on past the pumps, round
## onto the entry ramp's line, up it to its gore (on the highway's edge).
func station_route(k: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	if station.is_empty():
		return out
	var q: Array = STATION_SPOTS[posmod(k, STATION_SPOTS.size())]
	for t in [0.0, 8.0, 14.0]:
		out.append(station_at(float(q[0]) + t, float(q[1])))
	var path := ramp_path(station.on)
	var pts: PackedVector3Array = path.pts
	var e := pts[pts.size() - 1]
	var h: float = path.heads[pts.size() - 1]
	var dir := Vector3(sin(h), 0.0, -cos(h))         # (out of the ramp, into the forecourt)
	out.append(e + dir * 12.0)
	out.append(e + dir * 6.0)
	for i in range(pts.size() - 1, -1, -1):
		out.append(pts[i])
	return out


## Is (x, z) on the forecourt (within `margin` m of it)?
func on_station(x: float, z: float, margin := 0.0) -> bool:
	if station.is_empty():
		return false
	var rel := Vector3(x - float(station.c.x), 0.0, z - float(station.c.z))
	return absf(rel.dot(station.u)) < STATION_HALF.x + margin and absf(rel.dot(station.w)) < STATION_HALF.y + margin


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
	if not station.is_empty():
		# (the gas station's forecourt: the land flat under it, easing back to its own round it)
		var rel := Vector3(x - float(station.c.x), 0.0, z - float(station.c.z))
		var a := rel.dot(station.u)
		var e := Vector2(maxf(absf(a) - STATION_HALF.x, 0.0), maxf(absf(rel.dot(station.w)) - STATION_HALF.y, 0.0)).length()
		if e < STATION_EASE:
			h = lerpf(float(station.c.y) + float(station.gy) * a - STATION_SINK, h, smoothstep(0.0, STATION_EASE, e))
	return h


## Is (x, z) in the city (where the towers stand)?
func in_city(x: float, z: float) -> bool:
	for c in city:
		if (x - c.x) * (x - c.x) + (z - c.z) * (z - c.z) < c.r * c.r:
			return true
	return false


## A ramp's road: {pts, heads, len, nose, nose_s, nose_d, on_road}, from its gore (where it
## meets the highway, in the middle of its extra lane) out to where it ends, 4 m a point. It
## curves away from the gore (260 m radius, eased in over RAMP_EASE m), on the highway's
## surface while it's still on the highway's widened edge (_extra_lanes), until its barrier's
## clear of the highway's: its nose (pts[nose]; nose_s: the highway's sample there or just past
## it, nose_d: the ramp's middle's d there). From there it's a road of its own, down to the
## ground (RAMP_GRADE); it ends RAMP_LEN out. on_road: up to the nose, each point's (m from the
## gore the way it walks, d). An exit's traffic drives it from the gore out; an entry's from
## the end in.
const RAMP_LEN := 264.0              # m: an exit's and the next entry's ramps the same side (a junction's two,
                                     # their gores 520 m apart) come together ~280 m out: they end ~40 m apart
const RAMP_EASE := 44.0
const RAMP_W := 3.2                  # half the ramp's road (its lane and shoulders)
const RAMP_GRADE := 0.07

func ramp_path(r: Dictionary) -> Dictionary:
	var key := "%s/%s/%.1f" % [r.side, r.kind, r.s]
	if _ramp_paths.has(key):
		return _ramp_paths[key]
	var right: bool = r.side == "right"
	var gore: float = r.s
	var mid: float = 0.0 if right else ONCOMING_D   # its carriageway's middle
	var d0: float = (EDGE + LANE_W * 0.5) if right else (ONCOMING_D - EDGE - LANE_W * 0.5)
	var travel := 1.0 if right else -1.0          # which way round the loop its carriageway's traffic goes
	var walk := travel * (1.0 if r.kind == "off" else -1.0)   # which way the path walks from the gore
	var away := 1.0 if right else -1.0            # which way (in d) it leaves
	var p := world_at(gore, d0)
	var h := heading_at(gore) + (0.0 if walk > 0.0 else PI)
	var y := p.y
	var pts := PackedVector3Array()
	var heads := PackedFloat32Array()
	var on_road := PackedVector2Array()
	var n := int(RAMP_LEN / 4.0)
	var hint := int(wrap_s(gore) / STEP)
	var nose := -1
	for k in n + 1:
		if nose < 0 or k == nose + 1:
			var loc := locate(p, hint)
			hint = int(loc.i)
			on_road.append(Vector2(gore_ds(float(loc.s), gore) * walk, float(loc.d)))
			if nose < 0:
				# on the highway's edge: on its surface, until its barrier's (the inside one's foot,
				# RAMP_W + 0.45 in) clear of the highway's (0.75 out from the road's edge) by 0.1 m
				y = world_at(float(loc.s), float(loc.d)).y
				if absf(float(loc.d) - mid) - RAMP_W - 0.45 >= EDGE + SHOULDER_R + 0.85:
					nose = k
		pts.append(Vector3(p.x, y, p.z))
		heads.append(h)
		# turning away from the road: right of travel for our ramps, left for theirs, either way the walk goes
		h += (1.0 / 260.0) * smoothstep(0.0, RAMP_EASE, k * 4.0) * away * signf(walk) * 4.0
		p += Vector3(sin(h), 0.0, -cos(h)) * 4.0
		if nose >= 0:
			var g := maxf(land_at(p.x, p.z), city_ground if in_city(p.x, p.z) else -1.0)
			y = move_toward(y, maxf(g, 0.5) + 0.3, RAMP_GRADE * 4.0 * smoothstep(0.0, 40.0, (k + 1 - nose) * 4.0))
	if nose < 0 or nose > on_road.size() - 2:
		nose = on_road.size() - 2
	# the highway's sample at the nose (or just past it, the way it walks), and the ramp's middle there
	var s_n := wrap_s(gore + walk * on_road[nose].x)
	var nose_s := wrap_s((ceilf(s_n / STEP) if walk > 0.0 else floorf(s_n / STEP)) * STEP)
	var a_s := gore_ds(nose_s, gore) * walk
	var t := clampf((a_s - on_road[nose].x) / maxf(on_road[nose + 1].x - on_road[nose].x, 0.01), 0.0, 1.0)
	var out := {"pts": pts, "heads": heads, "len": n * 4.0, "nose": nose, "nose_s": nose_s,
		"nose_d": lerpf(on_road[nose].y, on_road[nose + 1].y, t), "on_road": on_road}
	_ramp_paths[key] = out
	return out


## The ramps' extra lanes, sample by sample: a deceleration lane before an exit (a 60 m
## taper, then full), an acceleration lane after an entry (full, then an 80 m taper),
## on the right of whichever carriageway the ramp is on, the way its traffic goes. Between
## the gore and the ramp's nose (past an exit's gore, before an entry's) the ramp's lane is
## still on the highway, curving away: the edge goes out with it (the ramp's outer edge 0.2 m
## in from its road's: the highway's barrier, 0.4 m out, stands where the ramp's own does), and
## ramp_r / ramp_l say where its middle is.
func _extra_lanes() -> void:
	extra_r.resize(_n)
	extra_l.resize(_n)
	extra_r.fill(0.0)
	extra_l.fill(0.0)
	ramp_r.resize(_n)
	ramp_l.resize(_n)
	ramp_r.fill(0.0)
	ramp_l.fill(0.0)
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
		# from the gore to the nose: the ramp's lane on the widened edge
		var path := ramp_path(r)
		var on: PackedVector2Array = path.on_road
		var walk := travel * (1.0 if r.kind == "off" else -1.0)
		var mid: float = 0.0 if r.side == "right" else ONCOMING_D
		var a_nose := gore_ds(float(path.nose_s), float(r.s)) * walk
		var i := int((ceilf(float(r.s) / STEP) if walk > 0.0 else floorf(float(r.s) / STEP)))
		var k := 0
		while true:
			var a := gore_ds(i * STEP, float(r.s)) * walk
			if a > a_nose + 0.01:
				break
			while k < on.size() - 2 and on[k + 1].x < a:
				k += 1
			var t := clampf((a - on[k].x) / maxf(on[k + 1].x - on[k].x, 0.01), 0.0, 1.0)
			var d := lerpf(on[k].y, on[k + 1].y, t)
			var w := maxf(LANE_W, absf(d - mid) + RAMP_W - 0.2 - EDGE - SHOULDER_R)
			var j := posmod(i, _n)
			if r.side == "right":
				extra_r[j] = maxf(extra_r[j], w)
				ramp_r[j] = d
			else:
				extra_l[j] = maxf(extra_l[j], w)
				ramp_l[j] = d
			i += int(walk)


## s - s0 the nearest way round the loop (-length/2 .. length/2).
func gore_ds(s: float, s0: float) -> float:
	return fposmod(s - s0 + length * 0.5, length) - length * 0.5


## The extra lane's width on our right at s (0: none).
func extra_lane(s: float) -> float:
	return extra_r[int(_at(s).x)]
