extends Node3D
## Highway traffic: a microscopic simulation, client-side for now (every peer
## runs its own; nothing is networked).
##
## CAR FOLLOWING - the Intelligent Driver Model (IDM). Every car has its own
## desired speed (its lane's typical speed +-10%, Highway.LANE_SPEED: 35 / 31.5
## / 28 m/s, so 25-38; trucks 22-26), safe time headway T (1.2-1.8 s), max
## acceleration a, comfortable deceleration b and jam gap s0:
##   acc = a * (1 - (v/v0)^4 - (s*/s)^2),  s* = s0 + v*T + v*dv / (2*sqrt(a*b))
## so traffic bunches up behind slow trucks and spreads out again on its own.
## A lane also caps speed (right lane slower). Curves ahead (ramps, the
## roundabouts) are taken at sqrt(a_lat * R) with a braking-distance profile.
## LANE CHANGES - MOBIL-lite: only when safe (both gaps > s0 and the new
## follower never has to brake harder than B_SAFE) and worth it (own gain +
## politeness * follower's gain > threshold, with a keep-right bias). Trucks
## stay in the two right lanes. Merging from an on-ramp and moving over for
## an exit are mandatory, with a relaxed threshold. Blinkers flash meanwhile.
## RAMPS - the flyover on-ramps feed the auxiliary lane (lane 3); cars merge
## left from it; exiting cars move into it and leave on the off-ramp; the local
## road's roundabout turns them round onto the on-ramp. Cars spawn / recycle
## only inside the two end tunnels, so nothing ever pops in or out in view.
##
## EXTERNAL CARS - register_obstacle(node) makes traffic treat any Node3D (a
## player's car, a player on foot) as a vehicle in whatever lane / ramp it's
## in: cars brake for it, and lane changes check the gap around it. Every
## traffic car is an AnimatableBody3D (collision layer 1) you can hit.
## READ ACCESS - active_cars(), car_of(body), and the Highway data (`hw`):
## lane_center / forward / speed_limit / route("home_to_office").
## MIX - mostly everyday cars in everyday colors; about 1 in NICE_EVERY is a
## "nice car" from `nice_models` (add_nice_model / append kit prop names;
## empty = the kit's own coupes).
##
## COST - the sim runs at SIM_HZ and only while the camera is anywhere near
## the highway (asleep = zero cost in the office). Rendering packs the visible
## cars into one MultiMesh per (model, surface) and per wheel type (~50 draw
## calls for the pool); colliders only wake up within BODY_DIST of the camera.
##
## FUTURE (networked cut-up mode): per-car state is tiny (path/lane, s, v,
## lane-change progress): the host could run this and broadcast
## [id, lane, s, v] at ~5 Hz for clients to extrapolate.

const Highway = preload("res://scripts/world/highway.gd")
const PropKit = preload("res://scripts/art/prop_kit.gd")

const SIM_HZ := 20.0
const POOL := 56
const NICE_EVERY := 12          # about one in this many cars is a "nice car"
const LC_TIME := 2.6            # seconds to cross into the next lane
const LC_OLD := 0.7             # until this far across, a lane-changer still minds (and blocks) its old lane
const B_SAFE := 4.0             # MOBIL: max braking imposed on the new follower
const B_SAFE_MUST := 6.5        # ... for mandatory changes (merge / exit)
const A_TH := 0.25              # MOBIL threshold (m/s^2)
const KEEP_RIGHT := 0.25        # bias toward the right lanes
const MAX_DECEL := 9.0          # physical braking limit
const B_CURVE := 1.8            # how hard drivers brake for a curve ahead
const EXIT_P := 0.28            # share of cars that take the next exit
const LOOK := 250.0             # how far ahead a car looks for its leader
const VIS_DIST := 360.0         # cars farther than this from the camera aren't drawn
const BODY_DIST := 220.0        # colliders only near the camera
const LOD_DIST := 110.0         # beyond this a car is two colored boxes (2 draw calls for all of them)
## Everyday traffic: model -> weight.
const REGULAR := {
	"TCar_Sedan_Silver": 5, "TCar_Sedan_White": 4, "TCar_Sedan_Black": 3, "TCar_Sedan_Grey": 4, "TCar_Sedan_Blue": 2,
	"TCar_Sedan_Red": 2, "TCar_Hatch_Grey": 3, "TCar_Hatch_Blue": 2, "TCar_Hatch_White": 2,
	"TCar_SUV_Black": 3, "TCar_SUV_White": 3, "TCar_SUV_Silver": 3, "TCar_SUV_Grey": 2,
	"TCar_Pickup_White": 2, "TCar_Pickup_Grey": 2, "TCar_Pickup_Red": 1, "TCar_Taxi": 1,
	"TCar_Truck_White": 3, "TCar_Truck_Red": 2,
}
const NICE_DEFAULT := ["TCar_Coupe_Red", "TCar_Coupe_Black", "TCar_Coupe_Yellow"]

## Kit prop names for the occasional nice car. Append to it (or add_nice_model)
## any time; cars pick up new models when they next come out of a tunnel.
var nice_models: Array = []
var nice_layouts := {}          # optional: model -> {L, W, H, wheel, axles, track, r} (see cars_layout.json)
								# (+ "flip": the kit car faces -z; + "paint": Color for its CarPaint surface)
const FLIP := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)


class Car:
	extends RefCounted
	var id := 0
	var model := ""
	var nice := false
	var truck := false
	var L := 4.7
	var W := 1.9
	var lay := {}
	var on_main := true
	var dir := 1
	var lane := 2
	var from_lane := 2
	var lc_t := 1.0             # 1 = settled in `lane`
	var path = null             # Highway.RoadPath when not on the mainline
	var s := 0.0
	var v := 0.0
	var acc := 0.0
	var v0 := 30.0
	var T := 1.4
	var a := 1.6
	var b := 2.5
	var s0 := 2.0
	var p := 0.3
	var exit_wanted := false
	var lc_cool := 0.0
	var wheel := 0.0
	var waiting := false        # recycled, waiting inside a tunnel for a gap
	var obstacle := false       # a registered outside vehicle (not simulated here)
	var node: Node3D            # traffic: its AnimatableBody3D; obstacle: the registered node
	var shape: CollisionShape3D
	var lane_changes := 0

	func prog() -> float:       # distance along the direction of travel (mainline)
		return s * dir


var hw: Highway
var cars: Array = []
var obstacles: Array = []       # Car objects with obstacle = true
var rng := RandomNumberGenerator.new()
var awake := false
var sim_time := 0.0
var stats := {"lane_changes": 0, "merges": 0, "exits": 0, "recycled": 0, "steps": 0, "missed_exits": 0}
var force_awake := false        # tests / screenshots
var _acc := 0.0
var _lists := {}                # "m<dir>_<lane>" / path name -> Array[Car] sorted by progress
var _mm := {}                   # prop -> Array[MultiMeshInstance3D] (one per surface)
var _layout := {}
var _blink: MultiMeshInstance3D
var _lod_body: MultiMeshInstance3D
var _lod_cab: MultiMeshInstance3D
var _bodies_on := false
var HIDE := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -500, 0))


func setup(highway, seed_val := 4242) -> void:
	hw = highway
	rng.seed = seed_val
	var f := FileAccess.open("res://assets/props/cars_layout.json", FileAccess.READ)
	if f:
		_layout = JSON.parse_string(f.get_as_text())
	_spawn_pool()
	_blinker_mm()
	_lod_body = _box_mm(true, Color(1, 1, 1))
	_lod_cab = _box_mm(false, Color(0.1, 0.12, 0.15))


# ------------------------------------------------------------------ public API

## Treat an outside Node3D as a vehicle in whatever lane / ramp it's on: traffic
## follows it (brakes for it), and won't change lanes into it. length/width in m.
## Its speed is measured from how it moves (or its `velocity` / `linear_velocity`).
func register_obstacle(node: Node3D, length := 4.6, width := 1.9) -> void:
	for o in obstacles:
		if o.node == node:
			return
	var c := Car.new()
	c.obstacle = true
	c.node = node
	c.L = length
	c.W = width
	c.waiting = true            # until it's located on a lane
	c.set_meta("last", node.global_position)
	obstacles.append(c)


func unregister_obstacle(node: Node3D) -> void:
	for o in obstacles.duplicate():
		if o.node == node or not is_instance_valid(o.node):
			obstacles.erase(o)


func add_nice_model(prop: String, layout := {}) -> void:
	if not nice_models.has(prop):
		nice_models.append(prop)
	if not layout.is_empty():
		nice_layouts[prop] = layout


## Every car currently on the road: [{node, id, model, nice, truck, on_main, dir,
## lane, path, s, speed, position, forward}] (lane: 0 fast .. 2 right, 3 aux;
## path: "" on the mainline, else a Highway.paths name).
func active_cars() -> Array:
	var out: Array = []
	for c in cars:
		if c.waiting:
			continue
		var xf := car_transform(c)
		out.append({"node": c.node, "id": c.id, "model": c.model, "nice": c.nice, "truck": c.truck, "on_main": c.on_main,
			"dir": c.dir, "lane": c.lane if c.on_main else -1, "path": "" if c.on_main else str(c.path.name),
			"s": c.s, "speed": c.v, "position": xf.origin, "forward": xf.basis.z})
	return out


## The traffic car behind a collider (e.g. from a collision), or null.
func car_of(body: Node) -> Car:
	for c in cars:
		if c.node == body:
			return c
	return null


# ------------------------------------------------------------------ pool

func _pick_regular() -> String:
	var total := 0
	for m in REGULAR:
		total += REGULAR[m]
	var r := rng.randi_range(1, total)
	for m in REGULAR:
		r -= REGULAR[m]
		if r <= 0:
			return m
	return REGULAR.keys()[0]


func _nice_list() -> Array:
	var out: Array = []
	for m in nice_models:
		if PropKit.has(str(m)):
			out.append(str(m))
	return out if not out.is_empty() else NICE_DEFAULT


## (Re)choose what this car is. Only called while it's out of sight (spawn / tunnel).
func _assign_model(c: Car) -> void:
	c.nice = rng.randi_range(1, NICE_EVERY) == 1
	c.model = _nice_list()[rng.randi() % _nice_list().size()] if c.nice else _pick_regular()
	var lay: Dictionary = nice_layouts.get(c.model, _layout.get(c.model, {}))
	if lay.is_empty():   # another kit's car: size it from its mesh, wheels are part of the body
		var ab := AABB()
		var first := true
		for part in PropKit._parts.get(c.model, []):
			var m: Mesh = part[0]
			ab = m.get_aabb() if first else ab.merge(m.get_aabb())
			first = false
		lay = {"L": maxf(ab.size.z, 3.5), "W": maxf(ab.size.x, 1.6), "H": maxf(ab.size.y, 1.2), "wheel": "", "kind": "nice"}
	c.lay = lay
	c.L = float(lay.get("L", 4.7))
	c.W = float(lay.get("W", 1.85))
	c.truck = str(lay.get("kind", "car")) == "truck"
	if c.shape:
		(c.shape.shape as BoxShape3D).size = Vector3(c.W, float(lay.get("H", 1.5)), c.L)
		c.shape.position = Vector3(0, float(lay.get("H", 1.5)) / 2.0, 0)


func _roll(c: Car) -> void:
	if c.truck:
		c.v0 = rng.randf_range(22.0, 26.0)
		c.T = rng.randf_range(1.6, 1.8)
		c.a = rng.randf_range(0.7, 1.0)
		c.b = 2.0
		c.s0 = 3.0
		c.p = 0.5
	else:
		# its "own" lane's typical speed +-10%: some cruise, some fly (nice cars mostly fly)
		var pref := rng.randi_range(0, 2) if not c.nice else rng.randi_range(0, 1)
		c.v0 = clampf(float(Highway.LANE_SPEED[pref]) * rng.randf_range(0.9, 1.1), 25.0, 38.0)
		c.T = rng.randf_range(1.2, 1.8) if not c.nice else rng.randf_range(1.2, 1.45)
		c.a = rng.randf_range(1.3, 2.3) if not c.nice else rng.randf_range(2.2, 3.0)
		c.b = rng.randf_range(2.2, 3.0)
		c.s0 = 2.0
		c.p = rng.randf_range(0.1, 0.5)
	c.exit_wanted = rng.randf() < EXIT_P


func _spawn_pool() -> void:
	for i in POOL:
		var c := Car.new()
		c.id = i
		var body := AnimatableBody3D.new()
		body.name = "TrafficCar_%d" % i
		body.collision_layer = 1
		body.collision_mask = 0
		body.sync_to_physics = true
		body.set_meta("traffic_id", i)
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		cs.disabled = true
		body.add_child(cs)
		add_child(body)
		body.global_position = Vector3(0, -600 - i * 4.0, 0)
		c.node = body
		c.shape = cs
		_assign_model(c)
		_roll(c)
		cars.append(c)
	# a few (never trucks) start on the ramps and loops, the rest spread over the lanes
	var ramp_names := ["dt_loop", "hood_loop", "dt_on", "hood_on", "dt_loop", "hood_loop"]
	var on_ramps := {}
	for c in cars:
		if ramp_names.is_empty():
			break
		if c.truck:
			continue
		var n: String = ramp_names.pop_back()
		var path = hw.paths[n]
		var taken: Array = on_ramps.get(n, [])
		c.on_main = false
		c.path = path
		c.s = path.length * (0.2 + 0.35 * taken.size())
		c.v = path.limit_ahead(c.s, 20.0) * 0.8
		taken.append(c)
		on_ramps[n] = taken
	var per_lane := {}
	for c in cars:
		if not c.on_main:
			continue
		c.dir = 1 if c.id % 2 == 0 else -1
		c.lane = [1, 2, 2][rng.randi() % 3] if c.truck else rng.randi_range(0, 2)
		c.from_lane = c.lane
		var key := "%d_%d" % [c.dir, c.lane]
		var at: float = per_lane.get(key, rng.randf_range(20.0, 60.0))
		c.s = at if c.dir > 0 else hw.length - at
		per_lane[key] = at + rng.randf_range(40.0, 130.0)
		if per_lane[key] > hw.length - 20.0:
			c.waiting = true
		c.v = _v0_of(c) * 0.9
	_rebuild_lists()


# ------------------------------------------------------------------ obstacles

## Put registered outside vehicles on the network (lane / ramp, s, speed).
func _locate_obstacles(dt: float) -> void:
	for o in obstacles.duplicate():
		if not is_instance_valid(o.node):
			obstacles.erase(o)
			continue
		var pos: Vector3 = o.node.global_position
		var last: Vector3 = o.get_meta("last")
		o.set_meta("last", pos)
		var vel := (pos - last) / maxf(dt, 0.001)
		var nv = o.node.get("velocity") if "velocity" in o.node else o.node.get("linear_velocity")
		if nv is Vector3:
			vel = nv
		o.waiting = true
		var loc: Vector2 = hw.locate(pos)
		var ad := absf(loc.y)
		if ad > Highway.EDGE_IN - 0.4 and ad < Highway.EDGE_OUT + Highway.LANE_W and absf(pos.y) < 2.5 \
				and loc.x > 1.0 and loc.x < hw.length - 1.0:
			var dir := 1 if loc.y > 0.0 else -1
			var k := clampi(int((ad - Highway.EDGE_IN) / Highway.LANE_W), 0, 3)
			if k == 3 and not hw.has_aux(dir, loc.x):
				if ad > Highway.EDGE_OUT + 1.0:
					continue            # on the shoulder
				k = 2
			o.on_main = true
			o.dir = dir
			o.lane = k
			o.s = loc.x
			var frac := (ad - Highway.EDGE_IN) / Highway.LANE_W - k
			o.from_lane = k + (1 if frac > 0.72 else (-1 if frac < 0.28 else 0))   # straddling the line
			o.from_lane = clampi(o.from_lane, 0, 3)
			o.lc_t = 0.0 if o.from_lane != k else 1.0
			o.v = maxf(vel.dot(hw.forward(dir, loc.x)), 0.0)
			o.waiting = false
			continue
		# a ramp or local road: the nearest path sample within 3.5 m (and at deck height)
		var best = null
		var bs := 0.0
		var bd := 3.5
		for pn in hw.paths:
			var pth = hw.paths[pn]
			if pth.next == "" or pn.ends_with("_road"):
				continue
			if not _path_box(pn).grow(4.0).has_point(Vector2(pos.x, pos.z)):
				continue
			var i := 0
			while i < pth.pts.size():
				var q: Vector3 = pth.pts[i]
				var d := Vector2(q.x - pos.x, q.z - pos.z).length()
				if d < bd and absf(q.y - pos.y) < 2.5:
					bd = d
					best = pth
					bs = pth.cum[i]
				i += 2
		if best != null:
			o.on_main = false
			o.path = best
			o.s = bs
			o.v = maxf(vel.dot(best.tangent(bs)), 0.0)
			o.waiting = false


var _boxes := {}


func _path_box(pn: String) -> Rect2:
	if not _boxes.has(pn):
		var r := Rect2()
		var first := true
		for q in hw.paths[pn].pts:
			if first:
				r = Rect2(q.x, q.z, 0, 0)
				first = false
			else:
				r = r.expand(Vector2(q.x, q.z))
		_boxes[pn] = r
	return _boxes[pn]


# ------------------------------------------------------------------ sim

func _key_m(dir: int, lane: int) -> String:
	return "m%d_%d" % [dir, lane]


func _rebuild_lists() -> void:
	_lists.clear()
	for c in cars + obstacles:
		if c.waiting:
			continue
		if c.on_main:
			_push(_key_m(c.dir, c.lane), c)
			if c.lc_t < LC_OLD and c.from_lane != c.lane:   # still partly in the old lane
				_push(_key_m(c.dir, c.from_lane), c)
		else:
			_push(c.path.name, c)
	for k in _lists:
		var arr: Array = _lists[k]
		if k.begins_with("m"):
			arr.sort_custom(func(x, y): return x.prog() < y.prog())
		else:
			arr.sort_custom(func(x, y): return x.s < y.s)


func _push(k: String, c) -> void:
	if not _lists.has(k):
		_lists[k] = []
	_lists[k].append(c)


static func idm(c, v: float, gap: float, v_lead: float, v0: float) -> float:
	var free := 1.0 - pow(v / maxf(v0, 0.1), 4.0)
	if gap >= 1e5:
		return c.a * free
	var ss: float = c.s0 + maxf(0.0, v * c.T + v * (v - v_lead) / (2.0 * sqrt(c.a * c.b)))
	var g := maxf(gap, 0.1)
	return c.a * (free - (ss / g) * (ss / g))


## First car ahead of progress `pr` in list k (skipping `me`), and its progress.
func _ahead(k: String, pr: float, me, main: bool) -> Array:
	var arr: Array = _lists.get(k, [])
	var best = null
	var bp := INF
	for o in arr:
		if o == me:
			continue
		var op: float = o.prog() if main else o.s
		if op > pr and op < bp:
			bp = op
			best = o
	return [best, bp]


func _behind(k: String, pr: float, me, main: bool) -> Array:
	var arr: Array = _lists.get(k, [])
	var best = null
	var bp := -INF
	for o in arr:
		if o == me:
			continue
		var op: float = o.prog() if main else o.s
		if op <= pr and op > bp:
			bp = op
			best = o
	return [best, bp]


## The car (or registered obstacle) this one follows: [leader or null, gap, leader speed].
func leader_of(c) -> Array:
	if c.on_main:
		return _leader_main(c, c.lane)
	var r := _ahead(c.path.name, c.s, c, false)
	if r[0] != null:
		return [r[0], r[1] - c.s - (r[0].L + c.L) / 2.0, r[0].v]
	var rest: float = c.path.length - c.s
	if rest > LOOK:
		return [null, 1e6, 0.0]
	if c.path.next == "aux":
		var dir: int = c.path.aux_dir
		var entry: float = hw.aux[dir].a if dir > 0 else hw.aux[dir].b
		var q := _ahead(_key_m(dir, 3), entry * dir - 0.001, c, true)
		if q[0] != null:
			return [q[0], rest + (q[1] - entry * dir) - (q[0].L + c.L) / 2.0, q[0].v]
		return [null, 1e6, 0.0]
	if c.path.next == "":
		return [null, 1e6, 0.0]
	var q2 := _ahead(c.path.next, -1.0, c, false)
	if q2[0] != null:
		return [q2[0], rest + q2[1] - (q2[0].L + c.L) / 2.0, q2[0].v]
	return [null, 1e6, 0.0]


func _leader_main(c, lane: int) -> Array:
	var pr: float = c.prog()
	var r := _ahead(_key_m(c.dir, lane), pr, c, true)
	if r[0] != null:
		return [r[0], r[1] - pr - (r[0].L + c.L) / 2.0, r[0].v]
	if lane == 3 and hw.aux.has(c.dir):   # the aux lane runs onto the off-ramp
		var ex: float = hw.aux[c.dir].b if c.dir > 0 else hw.aux[c.dir].a
		var rest: float = (ex - c.s) * c.dir
		var off: String = hw.aux[c.dir].off
		var q := _ahead(off, -1.0, c, false)
		if q[0] != null:
			return [q[0], rest + q[1] - (q[0].L + c.L) / 2.0, q[0].v]
	return [null, 1e6, 0.0]


## The fastest you can go now and still make every curve ahead at a
## comfortable deceleration: min over sample points of sqrt(lim^2 + 2*b*dist),
## looking into the next path too.
func _curve_speed(c) -> float:
	var best: float = c.v0
	var path = c.path
	var s: float = c.s
	var dist := 0.0
	var reach: float = c.v * c.v / (2.0 * B_CURVE) + 12.0
	while dist <= reach and path != null:
		var lim: float = path.lim[path.idx(s)]
		best = minf(best, sqrt(lim * lim + 2.0 * B_CURVE * dist))
		s += 4.0
		dist += 4.0
		if s > path.length:
			if path.next == "" or path.next == "aux":
				break
			s -= path.length
			path = hw.paths[path.next]
	return best


func _v0_of(c) -> float:
	if not c.on_main:
		return _curve_speed(c)
	var v0: float = c.v0
	if c.lane < Highway.LANES:     # a lane caps you: the right lane is slower
		v0 = minf(v0, float(Highway.LANE_SPEED[c.lane]) * 1.1)
		if c.exit_wanted and hw.aux.has(c.dir):   # your exit's coming up: ease off, find the gap
			var ex1: float = hw.aux[c.dir].b if c.dir > 0 else hw.aux[c.dir].a
			var d1: float = (ex1 - c.s) * c.dir
			if d1 > 0.0 and d1 < 320.0:
				v0 = minf(v0, float(Highway.LANE_SPEED[2]) * (0.85 if c.lane == 2 else 0.95))
	if c.lane == 3 and hw.aux.has(c.dir):
		var ex: float = hw.aux[c.dir].b if c.dir > 0 else hw.aux[c.dir].a
		var dist: float = (ex - c.s) * c.dir
		v0 = minf(v0, float(Highway.LANE_SPEED[2]))
		if c.exit_wanted or dist < 160.0:   # the aux lane becomes the off-ramp: slow for its curves
			var off = hw.paths[hw.aux[c.dir].off]
			var k := 0.0
			while k < 160.0:
				var lim: float = off.lim[off.idx(k)]
				v0 = minf(v0, sqrt(lim * lim + 2.0 * B_CURVE * maxf(dist + k, 0.0)))
				k += 8.0
	return v0


func _acc_of(c) -> float:
	var l := leader_of(c)
	var v0 := _v0_of(c)
	var acc := idm(c, c.v, l[1], l[2], v0)
	if c.v > v0 + 0.3:   # over the curve / lane speed: IDM only eases off, drivers actually brake
		acc = minf(acc, -(c.v - v0) * 1.6)
	if c.on_main and c.lc_t < LC_OLD and c.from_lane != c.lane:   # mid lane change: mind both lanes
		var l2 := _leader_main(c, c.from_lane)
		acc = minf(acc, idm(c, c.v, l2[1], l2[2], v0))
	return clampf(acc, -MAX_DECEL, c.a)


func step(dt: float) -> void:
	sim_time += dt
	stats.steps += 1
	_locate_obstacles(dt)
	_rebuild_lists()
	for c in cars:
		if not c.waiting:
			c.acc = _acc_of(c)
	for c in cars:
		if not c.waiting and c.on_main:
			c.lc_cool -= dt
			if c.lc_t >= 1.0 and c.lc_cool <= 0.0:
				_consider_lane_change(c)
	for c in cars:
		if c.waiting:
			continue
		var v1 := clampf(c.v + c.acc * dt, 0.0, 45.0)
		var ds := maxf(0.0, (c.v + v1) * 0.5 * dt)
		c.v = v1
		c.wheel = fmod(c.wheel + ds / float(c.lay.get("r", 0.34)), TAU)
		if c.on_main:
			c.s += ds * c.dir
			if c.lc_t < 1.0:   # slower sideways when crawling (you steer, you don't slide)
				c.lc_t = minf(c.lc_t + dt / LC_TIME * clampf(c.v / 8.0, 0.35, 1.0), 1.0)
				if c.lc_t >= 1.0:
					c.from_lane = c.lane
		else:
			c.s += ds
		_transitions(c)
	_rebuild_lists()            # lane changes this step moved cars: respawn must see where they are
	_try_respawn()


func _transitions(c) -> void:
	if c.on_main:
		if hw.aux.has(c.dir) and c.exit_wanted and c.lane != 3:
			var ex0: float = hw.aux[c.dir].b if c.dir > 0 else hw.aux[c.dir].a
			if (c.s - ex0) * c.dir >= 0.0:       # missed it: maybe next time
				c.exit_wanted = false
				stats.missed_exits += 1
		if c.lane == 3 and hw.aux.has(c.dir):
			var ex: float = hw.aux[c.dir].b if c.dir > 0 else hw.aux[c.dir].a
			if (c.s - ex) * c.dir >= 0.0:        # onto the off-ramp
				var over: float = (c.s - ex) * c.dir
				c.on_main = false
				c.path = hw.paths[hw.aux[c.dir].off]
				c.s = over
				c.exit_wanted = false
				stats.exits += 1
				return
		if (c.dir > 0 and c.s >= hw.length - 4.0) or (c.dir < 0 and c.s <= 4.0):
			c.waiting = true                     # deep in a tunnel: back to the pool as a new car
			_assign_model(c)
			_roll(c)
			stats.recycled += 1
		return
	if c.s < c.path.length:
		return
	var over: float = c.s - c.path.length
	if c.path.next == "aux":
		var dir: int = c.path.aux_dir
		c.on_main = true
		c.dir = dir
		c.lane = 3
		c.from_lane = 3
		c.lc_t = 1.0
		c.lc_cool = rng.randf_range(0.3, 1.0)
		c.s = (hw.aux[dir].a if dir > 0 else hw.aux[dir].b) + over * dir
		c.exit_wanted = false
		c.path = null
		stats.merges += 1
	else:
		c.path = hw.paths[c.path.next]
		c.s = over


## Put waiting cars back at a tunnel entrance with room to spare (new model,
## new driver: this is the only place cars change, deep inside a tunnel).
func _try_respawn() -> void:
	for c in cars:
		if not c.waiting:
			continue
		var entries := [[1, 0], [1, 1], [1, 2], [-1, 0], [-1, 1], [-1, 2]]
		for i in range(entries.size() - 1, 0, -1):   # seeded shuffle: the sim is reproducible
			var j := rng.randi_range(0, i)
			var t = entries[i]
			entries[i] = entries[j]
			entries[j] = t
		var placed := false
		for e in entries:
			var dir: int = e[0]
			var lane: int = e[1]
			if c.truck and lane == 0:
				continue
			var s_in: float = 6.0 if dir > 0 else hw.length - 6.0
			var q := _ahead(_key_m(dir, lane), s_in * dir - 30.0, null, true)
			var gap: float = (q[1] - s_in * dir) if q[0] != null else 1e6
			if gap < 70.0:
				continue
			c.waiting = false
			c.on_main = true
			c.path = null
			c.dir = dir
			c.lane = lane
			c.from_lane = lane
			c.lc_t = 1.0
			c.s = s_in
			c.v = minf(_v0_of(c), q[0].v + 2.0) if q[0] != null else _v0_of(c) * 0.95
			_push(_key_m(dir, lane), c)
			_lists[_key_m(dir, lane)].sort_custom(func(x, y): return x.prog() < y.prog())
			placed = true
			break
		if not placed:
			return          # the tunnels are full this step; try again next one


func _lane_ok(c, k: int) -> bool:
	if k < 0 or k > 3:
		return false
	if k == 3:   # only to exit, and not in the first 30 m where the on-ramp merges in
		var entry: float = hw.aux[c.dir].a if c.dir > 0 else hw.aux[c.dir].b
		return c.exit_wanted and hw.has_aux(c.dir, c.s) and hw.has_aux(c.dir, c.s + c.dir * 12.0) \
				and (c.s - entry) * c.dir > 15.0
	if c.truck and k == 0:
		return false
	return true


func _consider_lane_change(c) -> void:
	c.lc_cool = rng.randf_range(0.6, 1.4)
	var must := 0            # -1 must go left, +1 must go right
	if c.lane == 3 and not c.exit_wanted:
		must = -1            # merging from the on-ramp
	elif c.exit_wanted and hw.aux.has(c.dir):
		var ex: float = hw.aux[c.dir].b if c.dir > 0 else hw.aux[c.dir].a
		var dist: float = (ex - c.s) * c.dir
		if dist > 0.0 and dist < 900.0 and c.lane < 3:
			must = 1
	elif c.truck and c.lane == 0:
		must = 1
	if must != 0:
		c.lc_cool = 0.25       # keep looking for the gap
	var cur_acc: float = c.acc
	var best_k := -1
	var best_gain := -INF
	for k in [c.lane - 1, c.lane + 1]:
		if not _lane_ok(c, k):
			continue
		var mand := (must != 0 and signi(k - c.lane) == must)
		if must != 0 and not mand:
			continue
		var pr: float = c.prog()
		var lk := _key_m(c.dir, k)
		var ahead := _ahead(lk, pr, c, true)
		var behind := _behind(lk, pr, c, true)
		var gap_f := 1e6
		var v_l := 0.0
		if ahead[0] != null:
			gap_f = ahead[1] - pr - (ahead[0].L + c.L) / 2.0
			v_l = ahead[0].v
		var gap_b := 1e6
		if behind[0] != null:
			gap_b = pr - behind[1] - (behind[0].L + c.L) / 2.0
		if gap_f < c.s0 + 1.0 or gap_b < 3.0:
			continue
		var new_acc := idm(c, c.v, gap_f, v_l, _lane_v0(c, k))
		if new_acc < -(B_SAFE_MUST if mand else B_SAFE) * 0.8:
			continue           # you'd have to stomp on the brakes over there
		var f_gain := 0.0
		if behind[0] != null:
			var fb = behind[0]
			if fb.obstacle:   # an outside car behind: give it a generous gap
				if gap_b < 8.0 + fb.v * 0.8:
					continue
			else:
				var f_new := idm(fb, fb.v, gap_b, c.v, fb.v0)
				if f_new < -(B_SAFE_MUST if mand else B_SAFE):
					continue
				f_gain = f_new - fb.acc
		if mand:
			best_k = k
			break
		var bias := KEEP_RIGHT if k > c.lane else -KEEP_RIGHT
		if c.truck:
			bias *= 3.0
		var gain: float = new_acc - cur_acc + c.p * f_gain + bias
		if gain > A_TH and gain > best_gain:
			best_gain = gain
			best_k = k
	if best_k >= 0:
		c.from_lane = c.lane
		c.lane = best_k
		c.lc_t = 0.0
		c.lc_cool = 0.3 if must != 0 else rng.randf_range(3.0, 6.0)   # heading for an exit: keep going over
		c.lane_changes += 1
		stats.lane_changes += 1


## Desired speed as if in lane k (for the lane-change incentive).
func _lane_v0(c, k: int) -> float:
	var keep: int = c.lane
	c.lane = k
	var v := _v0_of(c)
	c.lane = keep
	return v


## Smallest bumper gap between consecutive traffic cars in the same lane /
## path (tests: nothing should ever overlap). Registered obstacles don't count.
func min_gap() -> float:
	var best := INF
	var groups := {}
	for c in cars:
		if c.waiting:
			continue
		var k := _key_m(c.dir, c.lane) if c.on_main else str(c.path.name)
		if not groups.has(k):
			groups[k] = []
		groups[k].append(c)
	for k in groups:
		var arr: Array = groups[k]
		var main := str(k).begins_with("m")
		arr.sort_custom(func(x, y): return (x.prog() if main else x.s) < (y.prog() if main else y.s))
		for i in range(1, arr.size()):
			var x = arr[i - 1]
			var y = arr[i]
			var g: float = ((y.prog() - x.prog()) if main else (y.s - x.s)) - (x.L + y.L) / 2.0
			if g < best:
				best = g
				last_pair = [x, y]
	return best


var last_pair: Array = []     # the two cars of the last min_gap() (debugging)


func describe_car(c) -> String:
	return "#%d %s %s dir %d lane %d<-%d lc %.2f s %.1f v %.1f acc %.1f L %.1f %s" % [c.id, c.model, "main" if c.on_main else (str(c.path.name) if c.path else "?"),
			c.dir, c.lane, c.from_lane, c.lc_t, c.s, c.v, c.acc, c.L, "exit" if c.exit_wanted else ""]


# ------------------------------------------------------------------ render + colliders

func _mm_for(prop: String) -> Array:
	if _mm.has(prop):
		return _mm[prop]
	var out: Array = []
	if prop != "" and PropKit.has(prop):
		var count := POOL * (4 if prop.begins_with("Wheel") else 1)
		for part in PropKit._parts[prop]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part[0]
			mm.instance_count = count
			mm.visible_instance_count = 0
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = part[1]
			var lay_p: Dictionary = nice_layouts.get(prop, {})
			if lay_p.has("paint") and part[1] == PropKit.material("CarPaint"):
				var pm := (part[1] as StandardMaterial3D).duplicate() as StandardMaterial3D
				pm.albedo_color = lay_p.paint
				mmi.material_override = pm
			mmi.layers = 2              # lit by the sun like the rest of the outdoors
			mmi.custom_aabb = AABB(Vector3(-100, -20, 100), Vector3(1400, 60, 700))
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			out.append(mmi)
	_mm[prop] = out
	return out


func _blinker_mm() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.1, 0.1, 0.1)
	mm.mesh = bm
	mm.instance_count = POOL * 2
	mm.visible_instance_count = 0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.6, 0.05)
	_blink = MultiMeshInstance3D.new()
	_blink.multimesh = mm
	_blink.material_override = mat
	_blink.custom_aabb = AABB(Vector3(-100, -20, 100), Vector3(1400, 60, 700))
	_blink.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_blink)


func _box_mm(colored: bool, col: Color) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colored
	mm.mesh = BoxMesh.new()
	mm.instance_count = POOL
	mm.visible_instance_count = 0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.vertex_color_use_as_albedo = colored
	mat.roughness = 0.4
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.layers = 2
	mmi.custom_aabb = AABB(Vector3(-100, -20, 100), Vector3(1400, 60, 700))
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func car_transform(c, lead := 0.0) -> Transform3D:
	var fwd: Vector3
	var p: Vector3
	if c.on_main:
		var s: float = c.s + c.dir * lead
		var t: float = smoothstep(0.0, 1.0, c.lc_t)
		var d: float = lerpf(Highway.lane_d(c.dir, c.from_lane), Highway.lane_d(c.dir, c.lane), t)
		p = hw.point(s, d, 0.0)
		fwd = hw.tangent(s) * c.dir
		if c.lc_t < 1.0 and c.v > 1.0:   # yaw into the lane change
			var dd: float = (Highway.lane_d(c.dir, c.lane) - Highway.lane_d(c.dir, c.from_lane)) \
					* 6.0 * c.lc_t * (1.0 - c.lc_t) / LC_TIME
			fwd = (fwd * c.v + hw.right(s) * dd).normalized()
	else:
		var s2: float = minf(c.s + lead, c.path.length)
		p = c.path.at(s2)
		fwd = c.path.tangent(s2)
	var x := Vector3.UP.cross(fwd).normalized()
	var y := fwd.cross(x).normalized()
	return Transform3D(Basis(x, y, fwd), p)


## Where "the player" is for waking up / drawing / colliders: `watch` if set
## (e.g. the player's car), else the active camera.
var watch: Node3D


func _camera_pos() -> Vector3:
	if watch != null and is_instance_valid(watch):
		return watch.global_position
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_position if cam else Vector3(1e6, 0, 1e6)


func _process(delta: float) -> void:
	var cp := _camera_pos()
	var near := cp.z > 120.0 and cp.x > -120.0 and cp.x < 1350.0 and cp.z < 900.0
	awake = force_awake or near
	for arr in _mm.values():
		for mmi in arr:
			mmi.visible = awake
	_blink.visible = awake
	_lod_body.visible = awake
	_lod_cab.visible = awake
	if not awake:
		return
	_acc += delta
	var n := 0
	while _acc >= 1.0 / SIM_HZ and n < 4:
		_acc -= 1.0 / SIM_HZ
		step(1.0 / SIM_HZ)
		n += 1
	if n == 4:
		_acc = 0.0
	if DisplayServer.get_name() == "headless":
		return
	_draw(cp)


## Colliders follow the cars on the physics tick (only near the camera).
func _physics_process(_dt: float) -> void:
	var cp := _camera_pos()
	var on := awake
	for c in cars:
		var want := false
		if on and not c.waiting:
			var xf := car_transform(c, c.v * _acc)
			want = xf.origin.distance_squared_to(cp) < BODY_DIST * BODY_DIST
			if want:
				c.node.global_transform = xf
		if c.shape.disabled == want:
			c.shape.disabled = not want
		if not want and c.node.global_position.y > -100.0:
			c.node.global_position = Vector3(0, -600 - c.id * 4.0, 0)


func _draw(cp: Vector3) -> void:
	var counts := {}
	var blinks := 0
	var lods := 0
	var flash := fmod(sim_time, 0.7) < 0.35
	for c in cars:
		if c.waiting:
			continue
		var xf := car_transform(c, c.v * _acc)
		var d2 := xf.origin.distance_squared_to(cp)
		if d2 > VIS_DIST * VIS_DIST:
			continue
		if d2 > LOD_DIST * LOD_DIST:   # far: a painted box + a dark cabin
			var h: float = float(c.lay.get("H", 1.5))
			var col: Array = c.lay.get("color", [0.6, 0.6, 0.62])
			_lod_body.multimesh.set_instance_transform(lods, xf * Transform3D(Basis.from_scale(Vector3(c.W, h * 0.5, c.L * 0.97)),
					Vector3(0, 0.3 + h * 0.25, 0)))
			_lod_body.multimesh.set_instance_color(lods, Color(col[0], col[1], col[2]))
			var truck: bool = c.truck
			_lod_cab.multimesh.set_instance_transform(lods, xf * Transform3D(Basis.from_scale(
					Vector3(c.W * 0.86, h * 0.4 if not truck else h * 0.3, c.L * (0.45 if not truck else 0.22))),
					Vector3(0, 0.3 + h * (0.68 if not truck else 0.25), -c.L * 0.05 if not truck else c.L * 0.36)))
			lods += 1
			continue
		var i: int = counts.get(c.model, 0)
		counts[c.model] = i + 1
		var flip: bool = c.lay.get("flip", false)
		for mmi in _mm_for(c.model):
			mmi.multimesh.set_instance_transform(i, xf * FLIP if flip else xf)
		var w: String = c.lay.get("wheel", "")
		if w != "":
			var wi: int = counts.get(w, 0)
			counts[w] = wi + 4
			var wmm := _mm_for(w)
			var tr: float = c.lay.get("track", 0.8)
			var r: float = c.lay.get("r", 0.34)
			var k := 0
			for az in c.lay.get("axles", [1.4, -1.4]):
				for sx in [-1.0, 1.0]:
					var wx := xf * Transform3D(Basis(Vector3.RIGHT, c.wheel), Vector3(sx * tr, r, az))
					if flip and sx > 0.0:          # kit wheels: rim on +x; the car's +x side gets it turned round
						wx = wx * FLIP
					for mmi in wmm:
						mmi.multimesh.set_instance_transform(wi + k, wx)
					k += 1
		if c.on_main and c.lc_t < 1.0 and c.from_lane != c.lane and flash and blinks < POOL * 2 - 1:
			# turn signal on the side it's moving to (+x = the car's left)
			var side := -1.0 if (c.lane > c.from_lane) else 1.0
			var hx: float = c.W / 2.0 - 0.02
			for zz in [c.L / 2.0 - 0.05, -c.L / 2.0 + 0.05]:
				_blink.multimesh.set_instance_transform(blinks, xf * Transform3D(Basis(), Vector3(side * hx, 0.75, zz)))
				blinks += 1
	for prop in _mm:
		var n: int = counts.get(prop, 0)
		for mmi in _mm[prop]:
			mmi.multimesh.visible_instance_count = n
	_blink.multimesh.visible_instance_count = blinks
	_lod_body.multimesh.visible_instance_count = lods
	_lod_cab.multimesh.visible_instance_count = lods
