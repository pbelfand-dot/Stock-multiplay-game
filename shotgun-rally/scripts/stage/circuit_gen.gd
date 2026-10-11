extends "res://scripts/stage/loop_gen.gd"
## Track Mode's permanent circuit (tools/circuit_map.py designs it into data/maps/<id>.json):
## CINDER RIDGE, ~5 km clockwise, the same every time and on every machine.
##
## The same road API as LoopGen and StageGen (the car, the autopilot, the HUD, the builder
## read it), s taken round the lap: any s works (a car's s keeps growing lap after lap, as on
## the highway loop), world_at(s, d) is on the track's cambered surface, locate() finds a
## point's s within the lap. s = 0 is the start/finish line; d > 0 is right of the way round.
## Across the track, from the centreline out: the asphalt to the white line (half_at(s)),
## the kerbs outside it at the corners (kerb_at), the run-off (grass, gravel or asphalt:
## runoff_at), the barrier (barrier_at: armco, a tyre wall, or a concrete wall with debris
## fencing). The pit lane runs alongside the pit straight on the right, behind the pit wall
## (pit: its taper in, the limiter line, the boxes, the line out, the taper back).

const DIR := "res://data/maps/"
const KERB_GRIP := 0.92              # a kerb's grip against the track's (painted concrete: a touch less)

var circuit_id := "cinder_ridge"
var track_corners: Array = []        # [{n, name, dir, s0, s_apex, s1, r_min, angle, v_apex, v_entry}]
var kerbs: Array = []                # [{s0, s1, side, w, kind}]
var runoff_l: Array = []             # [{s0, s1, kind, w}]
var runoff_r: Array = []
var barrier_l: Array = []            # [{s0, s1, kind, d}]
var barrier_r: Array = []
var pit := {}
var grid: Array = []                 # [{k, s, d}]
var sectors: Array = []              # [s1, s2]
var drs: Array = []                  # [{detect, s0, s1}]
var marshals: Array = []
var boards: Array = []
var stands: Array = []
var lights: Array = []
var half := PackedFloat32Array()     # the half-width to the white lines, every STEP m
var lap_estimate := 0.0
var description := ""
var _kerb_idx := []                  # per sample: the kerbs there (indices into kerbs), for kerb_at


func generate(seed_value: int, _target := 0.0) -> void:
	seed_used = seed_value
	kind = "circuit"
	opts = opts.duplicate()
	opts["surface"] = "tarmac"
	opts["kind"] = "circuit"
	circuit_id = str(opts.get("circuit", circuit_id))
	data = JSON.parse_string(FileAccess.get_file_as_string(DIR + circuit_id + ".json"))
	var xs: Array = data.x
	var zs: Array = data.z
	var hs: Array = data.heading
	var cs: Array = data.curv
	var ys: Array = data.y
	var bs: Array = data.bank
	var ws: Array = data.half
	_n = xs.size()
	length = _n * STEP
	finish_s = INF                   # (laps: the session decides when it's over)
	pts = PackedVector3Array()
	heading = PackedFloat32Array()
	curv = PackedFloat32Array()
	bank = PackedFloat32Array()
	half = PackedFloat32Array()
	pts.resize(_n + 1)
	heading.resize(_n + 1)
	curv.resize(_n + 1)
	bank.resize(_n + 1)
	half.resize(_n + 1)
	for i in _n + 1:
		var j := i % _n
		pts[i] = Vector3(float(xs[j]), float(ys[j]), float(zs[j]))
		# (the heading keeps growing round the lap: the last sample is the first, a turn on)
		heading[i] = float(hs[j]) + (TAU if i == _n else 0.0)
		curv[i] = float(cs[j])
		bank[i] = float(bs[j])
		half[i] = float(ws[j])
	widths.resize(pts.size())
	for i in pts.size():
		widths[i] = half[i] * 2.0
	extra_r.resize(_n + 1)
	extra_l.resize(_n + 1)
	ramp_r.resize(_n + 1)
	ramp_l.resize(_n + 1)
	sections = [{"s0": 0.0, "s1": length, "surface": "asphalt"}]
	joins = []
	patches = []
	puddles = []
	bridges = []
	crests = []
	corners = []                     # (a rally stage's pacenote corners: the circuit's are track_corners)
	spans = []
	tunnels = []
	zones = [{"s0": 0.0, "s1": length, "kind": "circuit"}]
	support = [{"s0": 0.0, "s1": length, "kind": "ground"}]
	ramps = []
	overpasses = []
	gantries = []
	lakes = []
	city = []
	land_hills = data.get("hills", [])
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
	track_corners = data.corners
	kerbs = data.kerbs
	runoff_l = data.runoff_l
	runoff_r = data.runoff_r
	barrier_l = data.barrier_l
	barrier_r = data.barrier_r
	pit = data.pit
	grid = data.grid
	sectors = data.sectors
	drs = data.drs
	marshals = data.marshals
	boards = data.boards
	stands = data.stands
	lights = data.lights
	lap_estimate = float(data.get("lap_estimate", 0.0))
	description = str(data.get("description", ""))
	toll = {}
	station = {}
	_kerb_idx.resize(_n)
	for i in _n:
		_kerb_idx[i] = []
	for k in kerbs.size():
		var kb: Dictionary = kerbs[k]
		var i0 := int(float(kb.s0) / STEP)
		var i1 := int(float(kb.s1) / STEP)
		var cnt := posmod(i1 - i0, _n) + 1
		for q in cnt:
			_kerb_idx[posmod(i0 + q, _n)].append(k)
	_bumps.seed = 11
	_bumps.frequency = 1.0 / 180.0
	_bumps.fractal_octaves = 3


func touge_name() -> String:
	return str(data.get("name", "CINDER RIDGE"))


func describe() -> String:
	return "CIRCUIT · %.2f KM · %d CORNERS" % [length / 1000.0, track_corners.size()]


func max_grade() -> float:
	return 0.075


# ── across the track ──────────────────────────────────────────────────────

## The half-width to the white line at s.
func half_at(s: float) -> float:
	var a := _at(s)
	return lerpf(half[int(a.x)], half[int(a.x) + 1], a.y)


func width_at(s: float) -> float:
	return half_at(s) * 2.0


## A range list's entry holding s (wrapped; ranges may wrap past the line), or {}.
func range_at(list: Array, s: float) -> Dictionary:
	var w := wrap_s(s)
	for r in list:
		var a := float(r.s0)
		var b := float(r.s1)
		if (a <= b and w >= a and w < b) or (a > b and (w >= a or w < b)):
			return r
	return {}


## The kerb at (s, d) or {}: one laid outside the white line on that side, d in it.
func kerb_at(s: float, d: float) -> Dictionary:
	var i := int(wrap_s(s) / STEP) % _n
	var h := half_at(s)
	for k in _kerb_idx[i]:
		var kb: Dictionary = kerbs[k]
		if signf(d) == float(kb.side) and absf(d) >= h - 0.05 and absf(d) <= h + float(kb.w):
			if not range_at([kb], s).is_empty():
				return kb
	return {}


## The kerb's width outside the white line on `side` at s (0: none).
func kerb_w(s: float, side: int) -> float:
	var i := int(wrap_s(s) / STEP) % _n
	var best := 0.0
	for k in _kerb_idx[i]:
		var kb: Dictionary = kerbs[k]
		if int(kb.side) == side and not range_at([kb], s).is_empty():
			best = maxf(best, float(kb.w))
	return best


## The run-off on `side` (-1 left, +1 right) at s: {kind, w (m out from the white line)}.
func runoff_at(s: float, side: int) -> Dictionary:
	return range_at(runoff_r if side > 0 else runoff_l, s)


## The barrier on `side` at s: {kind, d (from the centreline, signed)}.
func barrier_at(s: float, side: int) -> Dictionary:
	return range_at(barrier_r if side > 0 else barrier_l, s)


## What a tyre at (s, d) is on: the track's asphalt, a kerb, the run-off's surface, the pit lane.
func surface_at_d(s: float, d: float) -> String:
	if in_pit_lane(s, d):
		return "asphalt"
	var h := half_at(s)
	if absf(d) <= h:
		return "asphalt"
	if not kerb_at(s, d).is_empty():
		return "kerb"
	var r := runoff_at(s, 1 if d > 0.0 else -1)
	if r.is_empty():
		return "grass"
	return "asphalt" if str(r.kind) == "pit" else str(r.kind)


func surface_at(_s: float) -> String:
	return "asphalt"


func grip_at(s: float, d := 0.0) -> float:
	var sf := surface_at_d(s, d)
	if sf == "kerb":
		return SURFACE_GRIP.get("asphalt", 1.25) * KERB_GRIP
	return SURFACE_GRIP.get(sf, SURFACE_GRIP.get("asphalt", 1.25))


## Inside the white lines (or on them: a wheel on the line is in): track limits for one point.
func on_track(s: float, d: float, margin := 0.0) -> bool:
	return absf(d) <= half_at(s) + margin


# ── the pits ──────────────────────────────────────────────────────────────

## s brought to the pit straight's range (-length/2 .. length/2 round the line).
func around_line(s: float) -> float:
	var w := wrap_s(s)
	return w - length if w > length * 0.5 else w


## The pit lane's inner edge at s (where its asphalt starts, from the track's right edge): along
## the taper in it swings from the track's edge to behind the wall, and back out on the taper out.
func pit_inner_d(s: float) -> float:
	var x := around_line(s)
	var h := half_at(s)
	var lane0 := float(pit.lane_d0)
	if x < float(pit.s_in0) or x > float(pit.s_out1):
		return INF
	if x < float(pit.s_in1):
		return lerpf(h, lane0, smoothstep(float(pit.s_in0), float(pit.s_in1), x))
	if x > float(pit.s_out0):
		return lerpf(lane0, h, smoothstep(float(pit.s_out0), float(pit.s_out1), x))
	return lane0


## The pit lane's outer edge at s (the garages' side), INF outside it.
func pit_outer_d(s: float) -> float:
	var x := around_line(s)
	if x < float(pit.s_in0) or x > float(pit.s_out1):
		return INF
	var inner := pit_inner_d(s)
	var full := float(pit.lane_d1)
	var lane_w := full - float(pit.lane_d0)
	if x < float(pit.s_in1):
		return inner + lerpf(4.0, lane_w, smoothstep(float(pit.s_in0), float(pit.s_in1), x))
	if x > float(pit.s_out0):
		return inner + lerpf(lane_w, 4.0, smoothstep(float(pit.s_out0), float(pit.s_out1), x))
	return full


func in_pit_lane(s: float, d: float) -> bool:
	if d <= 0.0:
		return false
	var a := pit_inner_d(s)
	return a != INF and d >= a - 0.3 and d <= pit_outer_d(s) + 0.3


## Between the pit limiter's lines (the lane's speed limit holds here).
func in_pit_limit(s: float, d: float) -> bool:
	var x := around_line(s)
	return x >= float(pit.s_lim0) and x <= float(pit.s_lim1) and in_pit_lane(s, d)


## Box k (0 = the first along): its stop's middle (s, d), facing up the lane.
func box_sd(k: int) -> Vector2:
	var n := int(pit.boxes)
	var span := float(pit.s_box1) - float(pit.s_box0)
	var s := float(pit.s_box0) + span * (float(k) + 0.5) / n
	return Vector2(wrap_s(s), float(pit.box_d))


## A car's place in its box: [position, heading].
func box_spot(k: int) -> Array:
	var sd := box_sd(k)
	return [world_at(sd.x, sd.y) + Vector3.UP * 0.6, heading_at(sd.x)]


# ── the grid, sectors, DRS ─────────────────────────────────────────────────

## Grid place k (0: pole): [position, heading].
func grid_spot(k: int) -> Array:
	var g: Dictionary = grid[clampi(k, 0, grid.size() - 1)]
	return [world_at(float(g.s), float(g.d)) + Vector3.UP * 0.6, heading_at(float(g.s))]


## The sector s is in: 0, 1 or 2.
func sector_of(s: float) -> int:
	var w := wrap_s(s)
	if w < float(sectors[0]):
		return 0
	if w < float(sectors[1]):
		return 1
	return 2


## The DRS zone s is in (its index), or -1.
func drs_zone(s: float) -> int:
	for k in drs.size():
		if not range_at([{"s0": drs[k].s0, "s1": drs[k].s1}], s).is_empty():
			return k
	return -1


# ── the land ──────────────────────────────────────────────────────────────

## The land's height at x, z, away from the track: rolling ground at the track's mean height
## with the ridge's mounds; the builder eases it into the track's edges.
func land_at(x: float, z: float) -> float:
	var h := -1.0
	for hl in _hill_grid.get(Vector2i(floori(x / HILL_CELL), floori(z / HILL_CELL)), []):
		var d2: float = ((x - hl.x) * (x - hl.x) + (z - hl.z) * (z - hl.z)) / (hl.r * hl.r)
		if d2 < 4.0:
			var t := 1.0 - d2 / 4.0
			h = maxf(h, -1.0 + float(hl.h) * t * t * (3.0 - 2.0 * t))
	return h + _bumps.get_noise_2d(x, z) * 2.5


func in_city(_x: float, _z: float) -> bool:
	return false
