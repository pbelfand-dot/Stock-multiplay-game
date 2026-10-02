extends Node3D
## Highway traffic: a microscopic simulation. The HOST runs it (for everyone:
## it stays awake while any player or player car is near the highway) and
## broadcasts a snapshot SNAP_HZ times a second; clients don't simulate, they
## coast each car along its lane / ramp between snapshots and blend out the
## small corrections (see NETWORK below). Single player = the host.
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
## CUTTING UP - most nice (sports) cars and the odd everyday one (CUT_NICE /
## CUT_OTHER) are "cutters": they want 45-56 m/s whatever the lane says, sit
## closer (T 0.4-0.6 s), close in late (s* has dv^2 / 2b instead of IDM's
## v * dv / 2 sqrt(ab)), pull and brake harder, ignore keep-right and the cars
## they pass (politeness ~0), look for a gap every few tenths of a second and
## cross a lane in LC_TIME_CUT: they weave through on either side. They take
## gaps others wouldn't (braking B_SAFE_CUT themselves, B_SAFE_MUST for whoever
## they cut up) but never one a player closing from behind couldn't brake for.
## RAMPS - the flyover on-ramps feed the auxiliary lane (lane 3); cars merge
## left from it; exiting cars move into it and leave on the off-ramp; the local
## road's roundabout turns them round onto the on-ramp.
## THE LOOP - the highway is a ring (stations wrap at hw.length): leaders,
## gaps and "how far to my exit" are all measured the short way forward round
## it. Traffic lives in a BUBBLE round everyone (every player, on foot or in a
## car, every registered car, the camera): cars more than DESPAWN from all of
## them go back to the pool, and each lane within BUBBLE (along the road) of
## anyone is topped up to one car per SPACING m, new cars appearing at least
## SPAWN_MIN away from everyone (past VIS_DIST: never in view). A stretch
## round someone that's (nearly) empty fills at once: from WARM_MIN, or from
## JUMP_MIN if they only just cut there (a cab, the elevator: nobody sees the
## cars arrive). The ramps and roundabout loops get topped up now and then
## (RAMP_MIN away). So the pool is spent where people are, and the ~7.5 km
## ring costs no more than the old 2.5 km road.
##
## EXTERNAL CARS - register_obstacle(node) makes traffic treat any Node3D (a
## player's car, a player on foot) as a vehicle in whatever lane / ramp it's
## in: cars brake for it, and lane changes check the gap around it. One with
## the "siren" meta (a patrol car) coming up behind in your lane (within
## SIREN_M): you move over for it, either side, as soon as there's a gap. Every
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
## NETWORK - each client gets the cars within RELEVANT m of its player only
## (so a packet stays ~1 KB however big the pool; cars it stops hearing about
## are put away on its side). Per car 12 bytes: id, model (index into model_table()), flags
## (waiting / on the mainline / eastbound / cutter), lane + the lane it's leaving, path
## (index into the sorted Highway.paths names), s (f32), speed (cm/s, u16),
## lane-change progress (u8). snapshot() packs them, apply_snapshot() unpacks
## on a client (`remote` = true). The world sends them (World._traffic_snap).

const Highway = preload("res://scripts/world/highway.gd")
const PropKit = preload("res://scripts/art/prop_kit.gd")

const SIM_HZ := 20.0
const SNAP_HZ := 10.0           # host -> clients
const SNAP_SNAP := 12.0         # a correction bigger than this (m) jumps instead of blending
const POOL := 176             # shared by everyone's bubbles (~90 cars each)
const BUBBLE := 650.0         # traffic lives within this far (along the road) of anyone
const DESPAWN := 760.0        # ... and goes back to the pool once this far (straight line) from everyone
const SPAWN_MIN := 420.0      # new cars appear at least this far from everyone (past VIS_DIST)
const WARM_MIN := 150.0       # an (almost) empty stretch round someone fills from this close
const INNER := 350.0          # ... "round someone": this far either way
const JUMP_MIN := 50.0        # ... and from this close if they only just got there (a cut: nobody sees it happen)
const RAMP_MIN := 220.0       # a ramp / local-road loop is topped up (every 15 s) this far from everyone
const SPACING := 105.0        # top a lane up to one car per this many m (round a player: ~40% denser than the old road)
const RELEVANT := 700.0       # a client hears about the cars this close to its player
const NICE_EVERY := 12          # about one in this many cars is a "nice car"
const LC_TIME := 2.6            # seconds to cross into the next lane
const LC_TIME_CUT := 1.3        # ... a cutter
const LC_OLD := 0.7             # until this far across, a lane-changer still minds (and blocks) its old lane
const B_SAFE := 4.0             # MOBIL: max braking imposed on the new follower
const B_SAFE_MUST := 6.5        # ... for mandatory changes (merge / exit)
const A_TH := 0.25              # MOBIL threshold (m/s^2)
const KEEP_RIGHT := 0.25        # bias toward the right lanes
const CUT_NICE := 0.7           # share of nice cars that cut up
const CUT_OTHER := 0.02         # ... and of everyday cars (not trucks)
const CUT_V0 := [45.0, 56.0]    # a cutter's desired speed (100-125 mph: over every lane's)
const A_TH_CUT := 0.1           # a cutter changes lanes for less
const B_SAFE_CUT := 6.0         # ... and will brake this hard in the new lane to get in
const V_MAX := 60.0             # nobody goes faster
const SIREN_M := 250.0          # a patrol car with its lights on this close behind you in your lane: move over
const SIREN_GAIN := 3.0         # ... (that much incentive, m/s^2, on top of MOBIL's)
const MAX_DECEL := 9.0          # physical braking limit
const B_CURVE := 1.8            # how hard drivers brake for a curve ahead
const EXIT_P := 0.32            # share of cars that take the next exit (the ramps and local roads see more)
const LOOK := 250.0             # how far ahead a car looks for its leader
const VIS_DIST := 360.0         # cars farther than this from the camera aren't drawn
const BODY_DIST := 220.0        # colliders only near the camera
const LOD_DIST := 110.0         # beyond this a car is two colored boxes (2 draw calls for all of them)
## Everyday traffic: model -> weight.
const REGULAR := {
	"TCar_Sedan_Silver": 5, "TCar_Sedan_White": 4, "TCar_Sedan_Black": 3, "TCar_Sedan_Grey": 4, "TCar_Sedan_Blue": 2,
	"TCar_Sedan_Red": 2, "TCar_Hatch_Grey": 3, "TCar_Hatch_Blue": 2, "TCar_Hatch_White": 2,
	"TCar_SUV_Black": 3, "TCar_SUV_White": 3, "TCar_SUV_Silver": 3, "TCar_SUV_Grey": 2,
	"TCar_Pickup_White": 2, "TCar_Pickup_Grey": 2, "TCar_Pickup_Red": 1, "TCar_Taxi": 7,      # New York: yellow cabs everywhere
	"TCar_Truck_White": 3, "TCar_Truck_Red": 2,
}
const NICE_DEFAULT := ["TCar_Coupe_Red", "TCar_Coupe_Black", "TCar_Coupe_Yellow"]

## Kit prop names for the occasional nice car. Append to it (or add_nice_model)
## any time; cars pick up new models when they next come out of the pool.
var nice_models: Array = []
var nice_layouts := {}          # optional: model -> {L, W, H, wheel, axles, track, r} (see cars_layout.json)
								# (+ "flip": the kit car faces -z; + "paint": Color for its CarPaint surface)
const FLIP := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
const LOOP_AABB := AABB(Vector3(-700, -20, 100), Vector3(4000, 60, 1450))   # the whole ring (+ ramps): never culled


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
	var siren := false          # ... a patrol car: traffic moves over for it
	var node: Node3D            # traffic: its AnimatableBody3D; obstacle: the registered node
	var shape: CollisionShape3D
	var lane_changes := 0
	var cutter := false         # weaves through traffic (see CUTTING UP)
	var lc_time := LC_TIME      # seconds to cross a lane
	var vis := Vector3.ZERO     # client: where it was drawn minus where the host says (blends to 0)

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
var viewers_node: Node          # World.players_node: every player keeps a bubble of traffic round them
var _maint_t := 0.0
var _ramp_t := {}               # ramp / loop path -> sim_time a car was last put on it
var _last_vs: Array = []        # where the viewers were at the last _bubble (who just jumped somewhere)
var remote := false             # a client: cars come from the host's snapshots
var snapshots := 0              # client: how many applied
var _snap_t := 0.0
var _path_names: Array = []
signal snapshot_ready()         # time to send (World packs one per client: snapshot([their position]))
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
	c.siren = node.has_meta("siren")
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


## Lane k (going `dir`) ahead of station s, for an outside driver (the cops):
## [gap from s to the tail of the first car whose middle is ahead of s (1e6 if
## none), its speed, the gap back from s to the nose of the first one behind (1e6)].
## Cars and registered obstacles both count; `skip` nodes don't.
func lane_scan(dir: int, k: int, s: float, skip: Array = []) -> Array:
	var ahead := 1e6
	var v_ahead := 0.0
	var behind := 1e6
	for o in _lists.get(_key_m(dir, k), []):
		if skip.has(o.node):
			continue
		var d: float = hw.ds(s, o.s) * dir
		if d >= 0.0:
			if d - o.L / 2.0 < ahead:
				ahead = d - o.L / 2.0
				v_ahead = o.v
		elif -d - o.L / 2.0 < behind:
			behind = -d - o.L / 2.0
	return [ahead, v_ahead, behind]


## The traffic car behind a collider (e.g. from a collision), or null.
func car_of(body: Node) -> Car:
	for c in cars:
		if c.node == body:
			return c
	return null


# ------------------------------------------------------------------ network

## Every model a car can be, in an order all peers agree on (the nice ones are
## added the same way everywhere, see World._nice_traffic).
func model_table() -> Array:
	var out: Array = REGULAR.keys()
	for m in NICE_DEFAULT + nice_models:
		if not out.has(m):
			out.append(m)
	return out


func _paths() -> Array:
	if _path_names.is_empty():
		_path_names = hw.paths.keys()
		_path_names.sort()
	return _path_names


## A client: stop simulating, hide everything until the host's first snapshot.
func set_remote(on: bool) -> void:
	remote = on
	if on:
		for c in cars:
			c.waiting = true


## The host's traffic, packed (see NETWORK in the header): the cars on the road
## within `radius` of any of `centers` (all of them if none given).
const SNAP_MAX := 100               # cars per snapshot: 4 + 100 * 12 bytes stays under the ENet MTU (1392)


func snapshot(centers: Array = [], radius := RELEVANT) -> PackedByteArray:
	var models := model_table()
	var paths := _paths()
	var pick: Array = []
	for c in cars:
		if c.waiting:
			continue
		if not centers.is_empty():
			var p := _cpos(c)
			var near := false
			for q in centers:
				if p.distance_squared_to(q) < radius * radius:
					near = true
					break
			if not near:
				continue
		pick.append(c)
	if pick.size() > SNAP_MAX and not centers.is_empty():
		# keep it one unfragmented packet: the nearest cars win (an oversized unreliable
		# packet is lost whole on any dropped fragment, and a steady stream of them starves the link)
		var q0: Vector3 = centers[0]
		pick.sort_custom(func(a, b): return _cpos(a).distance_squared_to(q0) < _cpos(b).distance_squared_to(q0))
		pick.resize(SNAP_MAX)
	var b := PackedByteArray()
	b.resize(4 + pick.size() * 12)
	b.encode_float(0, sim_time)
	var o := 4
	for c in pick:
		b.encode_u8(o, c.id)
		b.encode_u8(o + 1, maxi(models.find(c.model), 0))
		b.encode_u8(o + 2, (1 if c.waiting else 0) | (2 if c.on_main else 0) | (4 if c.dir > 0 else 0) | (8 if c.cutter else 0))
		b.encode_u8(o + 3, c.lane | (c.from_lane << 2))
		b.encode_u8(o + 4, 255 if c.on_main or c.path == null else paths.find(str(c.path.name)))
		b.encode_float(o + 5, c.s)
		b.encode_u16(o + 9, clampi(int(c.v * 100.0), 0, 65535))
		b.encode_u8(o + 11, int(clampf(c.lc_t, 0.0, 1.0) * 255.0))
		o += 12
	return b


## A client: take the host's word for every car. Where a car was already
## drawn close by, keep drawing it there and let the difference fade out.
## Cars not in it are off the road (or out of our range): put away.
func apply_snapshot(b: PackedByteArray) -> void:
	if b.size() < 4:
		return
	sim_time = b.decode_float(0)      # (the blinkers flash in step with the host)
	var models := model_table()
	var paths := _paths()
	var seen := {}
	var o := 4
	while o + 12 <= b.size():
		var id := b.decode_u8(o)
		if id >= cars.size():
			o += 12
			continue
		seen[id] = true
		var c: Car = cars[id]
		var fl := b.decode_u8(o + 2)
		var was_shown := not c.waiting
		var before := _xf(c) if was_shown else Transform3D()
		if fl & 1:
			c.waiting = true
			o += 12
			continue
		var mi := b.decode_u8(o + 1)
		var model: String = models[mi] if mi < models.size() else REGULAR.keys()[0]
		if model != c.model:
			_apply_model(c, model)
			was_shown = false
		c.waiting = false
		c.on_main = (fl & 2) != 0
		c.dir = 1 if (fl & 4) != 0 else -1
		c.cutter = (fl & 8) != 0
		c.lc_time = LC_TIME_CUT if c.cutter else LC_TIME
		var ln := b.decode_u8(o + 3)
		c.lane = ln & 3
		c.from_lane = (ln >> 2) & 3
		var pi := b.decode_u8(o + 4)
		c.path = null if c.on_main or pi >= paths.size() else hw.paths[paths[pi]]
		if not c.on_main and c.path == null:
			c.waiting = true
			o += 12
			continue
		c.s = b.decode_float(o + 5)
		c.v = b.decode_u16(o + 9) / 100.0
		c.lc_t = b.decode_u8(o + 11) / 255.0
		var err := before.origin - _xf(c, false).origin if was_shown else Vector3.ZERO
		c.vis = err if err.length() < SNAP_SNAP else Vector3.ZERO
		o += 12
	for c in cars:
		if not seen.has(c.id):
			c.waiting = true
	snapshots += 1


## A client between snapshots: roll each car on along its lane / ramp at its
## speed (no decisions; the next snapshot has them).
func _coast(dt: float) -> void:
	var fade := exp(-dt * 4.0)
	sim_time += dt
	for c in cars:
		if c.waiting:
			continue
		c.vis *= fade
		var ds: float = c.v * dt
		c.wheel = fmod(c.wheel + ds / float(c.lay.get("r", 0.34)), TAU)
		if c.on_main:
			c.s = hw.wrap_s(c.s + ds * c.dir)
			if c.lc_t < 1.0:
				c.lc_t = minf(c.lc_t + dt / c.lc_time * clampf(c.v / 8.0, 0.35, 1.0), 1.0)
				if c.lc_t >= 1.0:
					c.from_lane = c.lane
			continue
		c.s += ds
		if c.s >= c.path.length:
			var over: float = c.s - c.path.length
			if c.path.next == "aux":
				var dir: int = c.path.aux_dir
				c.on_main = true
				c.dir = dir
				c.lane = 3
				c.from_lane = 3
				c.lc_t = 1.0
				c.s = (hw.aux[dir].a if dir > 0 else hw.aux[dir].b) + over * dir
				c.path = null
			elif c.path.next != "" and hw.paths.has(c.path.next):
				c.path = hw.paths[c.path.next]
				c.s = over
			else:
				c.s = c.path.length


## Test hook (smoke test): a client sends where it draws each car; the host
## compares with its own and keeps the result in `probe_result`.
var probe_result := {}


func probe() -> void:
	var pts := PackedFloat32Array()
	for c in cars:
		if not c.waiting:
			var p := _xf(c).origin
			pts.append_array([float(c.id), p.x, p.z])
	_probe.rpc_id(1, pts)


@rpc("any_peer", "reliable")
func _probe(pts: PackedFloat32Array) -> void:
	var n := 0
	var good := 0
	var worst := 0.0
	var i := 0
	while i + 2 < pts.size():
		var c: Car = cars[int(pts[i])] if int(pts[i]) < cars.size() else null
		if c != null and not c.waiting:
			var p := _xf(c).origin
			var e := Vector2(p.x - pts[i + 1], p.z - pts[i + 2]).length()
			n += 1
			worst = maxf(worst, e)
			if e < 6.0:
				good += 1
		i += 3
	probe_result = {"cars": n, "good": good, "worst": worst, "from": multiplayer.get_remote_sender_id()}


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


## (Re)choose what this car is. Only called while it's out of sight (back in the pool).
func _assign_model(c: Car) -> void:
	c.nice = rng.randi_range(1, NICE_EVERY) == 1
	_apply_model(c, _nice_list()[rng.randi() % _nice_list().size()] if c.nice else _pick_regular())


func _apply_model(c: Car, model: String) -> void:
	c.model = model
	c.nice = not REGULAR.has(model)
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
	c.cutter = not c.truck and rng.randf() < (CUT_NICE if c.nice else CUT_OTHER)
	c.lc_time = LC_TIME
	c.exit_wanted = rng.randf() < EXIT_P
	if c.cutter:   # cutting up: way over the lane speeds, close, hard on both pedals, nobody else matters
		c.v0 = rng.randf_range(CUT_V0[0], CUT_V0[1])
		c.T = rng.randf_range(0.4, 0.6)
		c.a = rng.randf_range(3.5, 4.5)
		c.b = rng.randf_range(5.0, 6.0)
		c.s0 = 1.5
		c.p = rng.randf_range(0.0, 0.05)
		c.lc_time = LC_TIME_CUT
		c.exit_wanted = false   # it's going round and round


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
		c.waiting = true              # in the pool: the bubbles round the players put it on the road
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
		if ad > Highway.EDGE_IN - 0.4 and ad < Highway.EDGE_OUT + Highway.LANE_W and absf(pos.y) < 2.5:
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
	var dv := v - v_lead
	# closing in: a cutter leaves it late (just the distance to shed the difference at b),
	# everyone else starts easing off early (IDM's v * dv / 2 sqrt(ab))
	var brake: float = dv * maxf(dv, 0.0) / (2.0 * c.b) if c.cutter else v * dv / (2.0 * sqrt(c.a * c.b))
	var ss: float = c.s0 + maxf(0.0, v * c.T + brake)
	var g := maxf(gap, 0.1)
	return c.a * (free - (ss / g) * (ss / g))


## First car ahead of progress `pr` in list k (skipping `me`), and its progress
## (on the mainline: measured forward round the loop, so it can be > the loop).
func _ahead(k: String, pr: float, me, main: bool) -> Array:
	var arr: Array = _lists.get(k, [])
	var best = null
	var bd := INF
	var L: float = hw.length
	for o in arr:
		if o == me:
			continue
		var d: float = fposmod(o.prog() - pr, L) if main else o.s - pr
		if d > 0.0 and d < bd:
			bd = d
			best = o
	return [best, pr + bd]


func _behind(k: String, pr: float, me, main: bool) -> Array:
	var arr: Array = _lists.get(k, [])
	var best = null
	var bd := INF
	var L: float = hw.length
	for o in arr:
		if o == me:
			continue
		var d: float = fposmod(pr - o.prog(), L) if main else pr - o.s
		if d >= 0.0 and d < bd:
			bd = d
			best = o
	return [best, pr - bd]


## How far ahead (forward round the loop, in car c's direction) station `at` is.
func _to(c, at: float) -> float:
	return fposmod((at - c.s) * c.dir, hw.length)


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
	var aux_rest := INF
	if lane == 3 and hw.aux.has(c.dir):
		aux_rest = ((hw.aux[c.dir].b if c.dir > 0 else hw.aux[c.dir].a) - c.s) * c.dir
	if r[0] != null and r[1] - pr <= aux_rest + 1.0:      # (the aux lane ends: nobody "ahead" round the loop in it)
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
	if c.lane < Highway.LANES and not c.cutter:     # a lane caps you: the right lane is slower (not a cutter)
		v0 = minf(v0, float(Highway.LANE_SPEED[c.lane]) * 1.1)
		if c.exit_wanted and hw.aux.has(c.dir):   # your exit's coming up: ease off, find the gap
			var ex1: float = hw.aux[c.dir].b if c.dir > 0 else hw.aux[c.dir].a
			var d1: float = _to(c, ex1)
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
		var v1 := clampf(c.v + c.acc * dt, 0.0, V_MAX)
		var ds := maxf(0.0, (c.v + v1) * 0.5 * dt)
		c.v = v1
		c.wheel = fmod(c.wheel + ds / float(c.lay.get("r", 0.34)), TAU)
		if c.on_main:
			c.s = hw.wrap_s(c.s + ds * c.dir)
			if c.lc_t < 1.0:   # slower sideways when crawling (you steer, you don't slide)
				c.lc_t = minf(c.lc_t + dt / c.lc_time * clampf(c.v / 8.0, 0.35, 1.0), 1.0)
				if c.lc_t >= 1.0:
					c.from_lane = c.lane
		else:
			c.s += ds
		_transitions(c)
	_rebuild_lists()            # lane changes this step moved cars: the bubble must see where they are
	_maint_t -= dt
	if _maint_t <= 0.0:
		_maint_t = 0.25
		_bubble()


func _transitions(c) -> void:
	if c.on_main:
		if hw.aux.has(c.dir) and c.exit_wanted and c.lane != 3:
			var ex0: float = hw.aux[c.dir].b if c.dir > 0 else hw.aux[c.dir].a
			if _to(c, ex0) > hw.length - 60.0:  # just went past it: next time round
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


## Roughly where a car is (the centerline under it on the mainline): cheap, for range checks.
func _cpos(c) -> Vector3:
	return hw.pos(c.s) if c.on_main else c.path.at(c.s)


## Everyone traffic should be alive round: the camera, every registered car
## (and whatever it's watching), every player; each with their station, if
## they're anywhere near the loop. [{p: Vector3, s: float}]
func _viewers() -> Array:
	var pts: Array = []
	var cp := _camera_pos()
	if cp.x < 1e5:
		pts.append(cp)
	for o in obstacles:
		if is_instance_valid(o.node):
			pts.append(o.node.global_position)
	if viewers_node != null and is_instance_valid(viewers_node):
		for n in viewers_node.get_children():
			if n is Node3D:
				pts.append((n as Node3D).global_position)
	var out: Array = []
	for p in pts:
		var dup := false
		for v in out:
			if (v.p as Vector3).distance_squared_to(p) < 60.0 * 60.0:
				dup = true
				break
		if dup or not _near(p):
			continue
		var loc: Vector2 = hw.locate(p)
		if absf(loc.y) < 900.0:
			out.append({"p": p, "s": loc.x})
	return out


func _recycle(c: Car) -> void:
	c.waiting = true                 # back to the pool as a new car (new model, new driver)
	c.vis = Vector3.ZERO
	_assign_model(c)
	_roll(c)
	stats.recycled += 1


## Is world point p at least `r` from every viewer?
func _clear_of(vs: Array, p: Vector3, r: float) -> bool:
	for v in vs:
		if (v.p as Vector3).distance_squared_to(p) < r * r:
			return false
	return true


## The bubbles (a few times a second): put away cars nobody's near; top each
## lane near anyone up to one car per SPACING, out of sight (see the header).
func _bubble() -> void:
	var vs := _viewers()
	for c in cars:
		if c.waiting:
			continue
		var p := _cpos(c)
		var near := false
		for v in vs:
			if (v.p as Vector3).distance_squared_to(p) < DESPAWN * DESPAWN:
				near = true
				break
		if not near:
			_recycle(c)
	if vs.is_empty():
		return
	var free: Array = cars.filter(func(c): return c.waiting)
	if free.is_empty():
		return
	var budget := 10
	var target := int(2.0 * BUBBLE / SPACING)
	var was: Array = _last_vs
	_last_vs = []
	for v in vs:
		_last_vs.append(v.p)
	for v in vs:
		var sv: float = v.s
		var v_warm := false
		# just arrived (a cut: a cab ride, the elevator, a respawn - not driving up): fill right round them
		var jumped := true
		for q in was:
			if (q as Vector3).distance_squared_to(v.p) < 120.0 * 120.0:
				jumped = false
				break
		# someone just arrived (a cab, the elevator, waking up): fill their stretch now, not over seconds
		var here := 0
		for c in cars:
			if not c.waiting and c.on_main and absf(hw.ds(sv, c.s)) < INNER:
				here += 1
		if here < target * 6 * INNER / BUBBLE * 0.4:
			budget = maxi(budget, 60)
		for dir in [1, -1]:
			for lane in 3:
				if free.is_empty() or budget <= 0:
					return
				var key := _key_m(dir, lane)
				var cnt := 0
				var inner := 0
				for o in _lists.get(key, []):
					var dd := absf(hw.ds(sv, o.s))
					if dd < BUBBLE:
						cnt += 1
						if dd < INNER:
							inner += 1
				# warm: the stretch round them is (nearly) empty - they just got here (a cab, the
				# elevator, waking up) - so fill it now, from WARM_MIN, several cars a go
				var inner_target := target * INNER / BUBBLE
				var warm := inner < inner_target * 0.4
				if (cnt >= target and not warm) or cnt >= int(target * 1.3):
					continue
				v_warm = v_warm or warm
				var r_min := (JUMP_MIN if jumped else WARM_MIN) if warm else SPAWN_MIN
				var r_max := INNER if warm else BUBBLE
				for attempt in (24 if warm else 4):
					if budget <= 0 or (cnt >= target and not warm) or (warm and inner >= inner_target * 0.8):
						break
					var off := rng.randf_range(r_min, r_max)
					var up := rng.randf() < 0.6                  # mostly upstream: they drive into view
					var st: float = hw.wrap_s(sv + (-off if up else off) * dir)
					if not _clear_of(vs, hw.lane_center(dir, lane, st), r_min):
						continue
					var q := _ahead(key, st * dir, null, true)
					var qb := _behind(key, st * dir, null, true)
					if (q[0] != null and q[1] - st * dir < 45.0) or (qb[0] != null and st * dir - qb[1] < 45.0):
						continue
					var c: Car = null
					for f in free:
						if not (f.truck and lane == 0):
							c = f
							break
					if c == null:
						break
					c.on_main = true
					c.path = null
					c.dir = dir
					c.lane = lane
					c.from_lane = lane
					c.s = st
					var v_new: float = _v0_of(c) * 0.95
					if q[0] != null and q[1] - st * dir < (220.0 if c.cutter else 120.0):
						v_new = minf(_v0_of(c), q[0].v + 2.0)
					# anyone coming up faster behind (a cutter, a player) must be able to stop for it
					if qb[0] != null and qb[0].v > v_new and st * dir - qb[1] < 45.0 + pow(qb[0].v - v_new, 2.0) / 8.0:
						continue
					free.erase(c)
					c.waiting = false
					c.lc_t = 1.0
					c.lc_cool = rng.randf_range(0.5, 2.0)
					c.v = v_new
					_push(key, c)
					budget -= 1
					cnt += 1
					inner += 1 if off < INNER else 0
					if not warm:
						break
		# the nearby ramps and roundabout loops get a car or two now and then (exits feed them
		# too, but a lap of the local road takes the best part of a minute)
		for pn in ["dt_loop", "hood_loop", "dt_on", "hood_on"]:
			if free.is_empty() or budget <= 0:
				return
			var path = hw.paths[pn]
			if _lists.get(pn, []).size() >= 2 or sim_time < float(_ramp_t.get(pn, -1e9)) + (0.0 if v_warm else 15.0):
				continue
			var ps: float = clampf(path.length * rng.randf_range(0.05, 0.8), 40.0, path.length - 40.0)
			var roomy := true
			for o in _lists.get(pn, []):
				if absf(o.s - ps) < 40.0:
					roomy = false
			var at: Vector3 = path.at(ps)
			if not roomy or at.distance_to(v.p) > BUBBLE or not _clear_of(vs, at, WARM_MIN if v_warm else RAMP_MIN):
				continue
			_ramp_t[pn] = sim_time
			var c: Car = null
			for f in free:
				if not f.truck:
					c = f
					break
			if c == null:
				continue
			free.erase(c)
			c.waiting = false
			c.on_main = false
			c.path = path
			c.s = ps
			c.v = path.limit_ahead(ps, 20.0) * 0.8
			_push(pn, c)
			budget -= 1


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
	c.lc_cool = rng.randf_range(0.6, 1.4) if not c.cutter else rng.randf_range(0.2, 0.4)
	var must := 0            # -1 must go left, +1 must go right
	if c.lane == 3 and not c.exit_wanted:
		must = -1            # merging from the on-ramp
	elif c.exit_wanted and hw.aux.has(c.dir):
		var ex: float = hw.aux[c.dir].b if c.dir > 0 else hw.aux[c.dir].a
		var dist: float = _to(c, ex)
		if dist > 0.0 and dist < 900.0 and c.lane < 3:
			must = 1
	elif c.truck and c.lane == 0:
		must = 1
	if must != 0:
		c.lc_cool = 0.25       # keep looking for the gap
	# lights in the mirror: get out of its way (either side, the first safe gap)
	var siren := 0.0
	if must == 0:
		var mb := _behind(_key_m(c.dir, c.lane), c.prog(), c, true)
		if mb[0] != null and mb[0].siren and c.prog() - mb[1] < SIREN_M:
			siren = SIREN_GAIN
			c.lc_cool = 0.25
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
		if new_acc < -(B_SAFE_MUST if mand else (B_SAFE_CUT if c.cutter else B_SAFE)) * 0.8:
			continue           # you'd have to stomp on the brakes over there
		var f_gain := 0.0
		if behind[0] != null:
			var fb = behind[0]
			if fb.obstacle:   # an outside car behind: give it a generous gap
				if gap_b < 8.0 + fb.v * 0.8:
					continue
				# a cutter never dives in front of a player closing on it faster than they could brake for
				if c.cutter and fb.v > c.v and gap_b < 8.0 + fb.v * 0.8 + pow(fb.v - c.v, 2.0) / 8.0:
					continue
			else:
				var f_new := idm(fb, fb.v, gap_b, c.v, fb.v0)
				if f_new < -(B_SAFE_MUST if mand or c.cutter else B_SAFE):   # (a cutter cuts you up: you brake harder for it)
					continue
				f_gain = f_new - fb.acc
		if mand:
			best_k = k
			break
		var bias := KEEP_RIGHT if k > c.lane else -KEEP_RIGHT
		if c.truck:
			bias *= 3.0
		if c.cutter:
			bias = 0.0         # either side will do
		var gain: float = new_acc - cur_acc + c.p * f_gain + bias + siren
		if gain > (A_TH_CUT if c.cutter else A_TH) and gain > best_gain:
			best_gain = gain
			best_k = k
	if best_k >= 0:
		c.from_lane = c.lane
		c.lane = best_k
		c.lc_t = 0.0
		_push(_key_m(c.dir, best_k), c)     # (now: so a car from the far side can't take the same gap this step)
		c.lc_cool = 0.3 if must != 0 else (rng.randf_range(0.8, 1.8) if c.cutter else rng.randf_range(3.0, 6.0))   # heading for an exit: keep going over
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
			mmi.custom_aabb = LOOP_AABB
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # (see _draw)
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
	_blink.custom_aabb = LOOP_AABB
	_blink.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blink.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	mmi.custom_aabb = LOOP_AABB
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(mmi)
	return mmi


## Where a car is drawn right now (between sim steps; plus a client's fading correction).
func _xf(c, with_vis := true, lag := 0.0) -> Transform3D:
	var xf := car_transform(c, c.v * (_acc - lag))
	if with_vis:
		xf.origin += c.vis
	return xf


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
					* 6.0 * c.lc_t * (1.0 - c.lc_t) / c.lc_time
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


static func _near(p: Vector3) -> bool:
	return p.z > 120.0 and p.x > -700.0 and p.x < 3300.0 and p.z < 1550.0


func _process(delta: float) -> void:
	var cp := _camera_pos()
	var near := _near(cp)
	if not near and not remote:
		# the host simulates for everyone: any player (on foot or in a car) near the highway
		for o in obstacles:
			if is_instance_valid(o.node) and _near(o.node.global_position):
				near = true
				break
	awake = force_awake or near
	for arr in _mm.values():
		for mmi in arr:
			mmi.visible = awake
	_blink.visible = awake
	_lod_body.visible = awake
	_lod_cab.visible = awake
	if remote:
		_acc = 0.0
		_coast(delta)                      # (also while asleep: we're ready when we look)
		if not awake:
			return
	else:
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
		_snap_t -= delta
		if _snap_t <= 0.0:
			_snap_t = 1.0 / SNAP_HZ
			snapshot_ready.emit()
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
			var xf := _xf(c)
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
	# physics objects (your car, the camera on it) are drawn interpolated, a tick
	# behind the sim: draw traffic at that same moment so it lines up with them.
	# The MultiMeshes themselves must NOT be physics-interpolated (they're not,
	# see _mm_for): we set every instance every frame, already at the right
	# moment, and slot i is whichever car comes i-th this frame. Interpolated,
	# the renderer blends each slot from the last tick's buffer to this frame's:
	# every car smears back toward where it was, and a slot that now holds a
	# different car draws a car flying between the two ("mush" at speed, when
	# cars pass in and out of view / LOD every frame)
	var lag := 1.0 / Engine.physics_ticks_per_second if get_tree().physics_interpolation else 0.0
	for c in cars:
		if c.waiting:
			continue
		var xf := _xf(c, true, lag)
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
