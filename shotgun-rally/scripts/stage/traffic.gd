extends Node3D
## CUTTING UP's traffic: the registry's traffic cars (VehicleRegistry.traffic_pool:
## the generic saloon, crossover and people mover often, the premium ones now and
## then) driving a highway StageGen's lanes. Kinematic: each car is an
## AnimatableBody3D moved along the road every physics tick (the player's car
## hits them as solid things and bounces off), not a simulated car.
##
## How they drive: the Intelligent Driver Model (Treiber et al. 2000) for speed:
## each wants its own speed (the slow lanes slower) and keeps a time gap to the
## car ahead in its lane, braking smoothly as it closes; the player counts as a
## car too. Lane changes: MOBIL (Kesting, Treiber, Helbing 2007): it moves over
## when the other lane lets it go faster than it can here (by a threshold, a little
## politeness for whoever it would cut up), never if the car behind there would
## have to brake hard; then it eases across over LANE_CHANGE_T s.
##
## Only the stretch round the player is populated (BEHIND m back to AHEAD m on):
## a car that drops out of it comes back somewhere else in it, in a gap.
##
## On the LAKESHORE LOOP (a LoopGen: its s goes on round and round, no end) there's
## more: on hard and insane the traffic comes in PACKS (a block of cars across all
## the lanes, close together, at nearly one speed: threading through one is the
## game), with open road between; ONCOMING traffic on the other carriageway (seen,
## not hit: the median barrier's between); cars JOIN from the on-ramps (down the
## ramp, along the acceleration lane, merging when there's a gap: lane -1 is that
## extra lane) and some LEAVE by the off-ramps.

const VehicleRegistry = preload("res://scripts/game/vehicle_registry.gd")

const AHEAD := 650.0
const BEHIND := 160.0
const IDM_A := 1.4              # m/s^2: how hard they speed up
const IDM_B := 2.5              # m/s^2: how hard they like to brake
const IDM_T := 1.3              # s: the time gap they keep
const IDM_S0 := 3.0             # m: bumper to bumper, stopped
const MOBIL_P := 0.3            # politeness
const MOBIL_GAIN := 0.15        # m/s^2 better before it bothers
const B_SAFE := 3.5             # m/s^2: no change that makes the car behind brake harder than this
const LANE_CHANGE_T := 3.0      # s to cross a lane
const PLAYER_HALF_LEN := 2.3

var st
var diff := {}
var lanes := 4
var lane_d: Array = []          # d of each lane: lane 0 the slow (right-hand) one
var cars: Array = []            # {id, body, wheels, s, lane, to, t, d, v, v0, half_len, half_w, crashed, think}
var running := false            # (frozen on the grid: they'd all have driven off by GO)
var player := {"s": 0.0, "d": 0.0, "v": 0.0}
var _pool: Array = []           # {scene, weight, paints, half_len, half_w}
var _rng := RandomNumberGenerator.new()
var _next_id := 0
var _target := 0
var looped := false             # a LoopGen: no end to the road, oncoming traffic, ramps
var oncoming: Array = []        # {body, wheels, s, d, v} on the other carriageway (going -s)
var ramp_cars: Array = []       # {body, wheels, path, k, v, mode ("join" / "exit"), r, m}
var _joined := {}               # on-ramp -> the player's lap it last fed (one car per pass)


func setup(stage, difficulty: Dictionary, seed_value: int, player_s: float) -> void:
	st = stage
	diff = difficulty
	_rng.seed = hash([seed_value, "traffic"])
	lanes = stage.HIGHWAY_LANES
	lane_d.clear()
	var edge: float = lanes * stage.LANE_W * 0.5
	for k in lanes:
		lane_d.append(edge - stage.LANE_W * (k + 0.5))       # lane 0 at the right edge
	for e in VehicleRegistry.traffic_pool():
		var path := "res://assets/models/cars/%s/%s.glb" % [e.model, e.model]
		if not ResourceLoader.exists(path):
			continue
		var scene: PackedScene = load(path)
		var probe: Node3D = scene.instantiate()
		var box := _bounds(probe)
		probe.free()
		_pool.append({"id": e.id, "scene": scene, "weight": float(e.weight), "paints": e.paints,
			"half_len": box.size.z * 0.5, "half_w": box.size.x * 0.5, "height": box.size.y})
	_target = int(round(float(diff.get("density", 12.0)) * (AHEAD + BEHIND) / 1000.0))
	looped = stage.has_method("wrap_s")
	if _pool.is_empty():
		return
	player.s = player_s
	if _packs():
		# packs ahead, open road between (the first a little way up the road)
		var s := player_s + 140.0
		while s < player_s + AHEAD:
			_spawn_pack(s)
			s += _rng.randf_range(float(diff.pack_gap[0]), float(diff.pack_gap[1]))
	else:
		# the first lot: ahead of the start, spread out (none right beside the grid)
		for k in _target:
			var s: float = player_s + 70.0 + (AHEAD - 70.0) * (k + _rng.randf()) / _target
			_spawn(s)
	if looped:
		var n_on := int(_target * 0.6)
		for k in n_on:
			_spawn_oncoming(player_s - 150.0 + (AHEAD + 450.0) * (k + _rng.randf()) / maxf(n_on, 1))


## Does this difficulty bring its traffic in packs?
func _packs() -> bool:
	return looped and diff.has("pack")


## The d of a lane: 0 .. lanes-1, or -1 (a ramp's extra lane, right of lane 0).
func _ld(lane: int) -> float:
	return float(lane_d[0]) + st.LANE_W if lane < 0 else float(lane_d[lane])


## A pack at s: rows of cars across the lanes, close behind each other, at nearly one
## speed (the slowest lane's, give or take): a block to thread.
func _spawn_pack(s: float) -> void:
	var n := _rng.randi_range(int(diff.pack[0]), int(diff.pack[1]))
	var pack_v := lerpf(float(diff.speed[0]), float(diff.speed[1]), _rng.randf_range(0.15, 0.6)) / 3.6
	var row_s := s
	var placed := 0
	while placed < n:
		var row: Array = range(lanes)
		row.shuffle()
		var in_row := mini(_rng.randi_range(2, lanes), n - placed)
		for k in in_row:
			var c := _spawn_at(row_s + _rng.randf_range(-5.0, 5.0), int(row[k]))
			if not c.is_empty():
				c.v0 = pack_v * _rng.randf_range(0.97, 1.05) * (1.0 + 0.03 * (lanes - 1 - int(row[k])))
				c.v = c.v0 * 0.98
			placed += 1
		row_s += _rng.randf_range(11.0, 22.0)


## Cars a km on this highway now (the tests check the density).
func count() -> int:
	return cars.size()


## Where a reset puts the player at s: the middle of the lane with the most room there
## (its nearest car, ahead or behind, furthest away), not the road's centre line, which
## on a highway runs between two lanes, often through a car (a crashed one stays put).
func clear_lane_d(s: float) -> float:
	var best := 0.0
	var room := -1.0
	for k in lanes:
		var near := 1e9
		for c in cars:
			if absf(float(c.d) - float(lane_d[k])) < st.LANE_W * 0.75:
				near = minf(near, absf(float(c.s) - s) - float(c.half_len))
		if near > room:
			room = near
			best = float(lane_d[k])
	return best


func _physics_process(dt: float) -> void:
	if not running or st == null:
		return
	for c in cars:
		_drive(c, dt)
	for c in cars:
		_place(c, dt)
	# out of the stretch round the player: back in somewhere else
	for c in cars.duplicate():
		var rel: float = float(c.s) - float(player.s)
		if rel < -BEHIND - 40.0 or rel > AHEAD + 120.0 or (not looped and float(c.s) > st.length - 40.0):
			if _packs():
				_remove(c)
			else:
				_respawn(c)
	if _packs():
		_refill_packs()
	if looped:
		_ramp_traffic(dt)
		_oncoming_traffic(dt)


## The car ahead in a lane (and its gap, bumper to bumper), the player included.
func _leader(lane: int, s: float, half_len: float, me = null) -> Dictionary:
	var best := {"gap": INF, "v": 0.0}
	for o in cars:
		if o == me:
			continue
		if int(o.lane) != lane and int(o.to) != lane:
			continue
		var gap: float = float(o.s) - s - float(o.half_len) - half_len
		if float(o.s) > s and gap < float(best.gap):
			best = {"gap": gap, "v": float(o.v)}
	if _player_in(lane):
		var pg: float = float(player.s) - s - PLAYER_HALF_LEN - half_len
		if float(player.s) > s and pg < float(best.gap):
			best = {"gap": pg, "v": float(player.v)}
	return best


## The car behind in a lane (for MOBIL): {gap, v, car}.
func _follower(lane: int, s: float, half_len: float, me) -> Dictionary:
	var best := {"gap": INF, "v": 0.0, "car": null}
	for o in cars:
		if o == me or (int(o.lane) != lane and int(o.to) != lane):
			continue
		var gap: float = s - float(o.s) - float(o.half_len) - half_len
		if float(o.s) < s and gap < float(best.gap):
			best = {"gap": gap, "v": float(o.v), "car": o}
	return best


## Whether the player's car overlaps a lane (straddling the line: both).
func _player_in(lane: int) -> bool:
	return absf(float(player.d) - _ld(lane)) < st.LANE_W * 0.5 + 0.95


func _lane_of(d: float, slack := 0.0) -> int:
	var best := -1
	var bd := INF
	for k in lanes:
		var x: float = absf(d - float(lane_d[k]))
		if x < bd:
			bd = x
			best = k
	return best if bd < st.LANE_W * 0.5 + slack else -1


## IDM: the acceleration for speed v wanting v0, gap and closing speed to the car ahead.
static func idm(v: float, v0: float, gap: float, v_lead: float) -> float:
	var free := 1.0 - pow(v / maxf(v0, 0.1), 4.0)
	if gap == INF:
		return IDM_A * free
	var s_star := IDM_S0 + maxf(0.0, v * IDM_T + v * (v - v_lead) / (2.0 * sqrt(IDM_A * IDM_B)))
	return IDM_A * (free - pow(s_star / maxf(gap, 0.1), 2.0))


func _drive(c: Dictionary, dt: float) -> void:
	if c.crashed:
		c.v = maxf(float(c.v) - 7.0 * dt, 0.0)              # hit: it stops where it is (hazards on)
		c.s = float(c.s) + float(c.v) * dt
		return
	var lead := _leader(int(c.to), float(c.s), float(c.half_len), c)
	if int(c.to) != int(c.lane):                             # mid-change: mind both lanes
		var other := _leader(int(c.lane), float(c.s), float(c.half_len), c)
		if float(other.gap) < float(lead.gap):
			lead = other
	var a := idm(float(c.v), float(c.v0), float(lead.gap), float(lead.v))
	c.v = maxf(float(c.v) + maxf(a, -9.0) * dt, 0.0)
	c.s = float(c.s) + float(c.v) * dt
	# the acceleration lane runs out: stop at its end rather than go through the barrier
	if int(c.lane) == -1 and int(c.to) == -1 and looped and st.extra_lane(float(c.s) + 25.0) < 1.5:
		c.v = maxf(float(c.v) - 6.0 * dt, 0.0)
	# lane changes: finishing one, or thinking about one now and then
	if int(c.to) != int(c.lane):
		c.t = float(c.t) + dt / LANE_CHANGE_T
		if float(c.t) >= 1.0:
			c.lane = c.to
			c.t = 0.0
	elif int(c.lane) == -1 and not c.has("exit"):
		_merge(c)                                            # joining from a ramp: into lane 0 at the first gap
	elif c.has("exit"):
		_exit_lane(c)
	else:
		c.think = float(c.think) - dt * float(diff.get("lane_changes", 0.7))
		if float(c.think) <= 0.0:
			c.think = _rng.randf_range(1.0, 3.0)
			_mobil(c, a)


func _mobil(c: Dictionary, a_here: float) -> void:
	var best_gain := MOBIL_GAIN
	var best_lane := -1
	for to in [int(c.lane) - 1, int(c.lane) + 1]:
		if to < 0 or to >= lanes:
			continue
		var lead := _leader(to, float(c.s), float(c.half_len), c)
		var back := _follower(to, float(c.s), float(c.half_len), c)
		if float(lead.gap) < 4.0 or float(back.gap) < 4.0:
			continue                                         # no room
		var a_there := idm(float(c.v), float(c.v0), float(lead.gap), float(lead.v))
		var b_new := 0.0
		var b_old := 0.0
		if back.car != null:
			b_old = idm(float(back.v), float(back.car.v0), INF if lead.gap == INF else float(lead.gap) + float(back.gap), float(lead.v))
			b_new = idm(float(back.v), float(back.car.v0), float(back.gap), float(c.v))
			if b_new < -B_SAFE:
				continue                                     # it'd make them brake hard
		var keep_right := 0.25 if to < int(c.lane) else -0.1  # (keep right unless overtaking)
		var gain: float = a_there - a_here + MOBIL_P * (b_new - b_old) + keep_right
		if gain > best_gain:
			best_gain = gain
			best_lane = to
	if best_lane >= 0:
		c.to = best_lane
		c.t = 0.0


func _place(c: Dictionary, dt: float) -> void:
	var u: float = smoothstep(0.0, 1.0, float(c.t))
	c.d = lerpf(_ld(int(c.lane)), _ld(int(c.to)), u)
	var s: float = float(c.s) if looped else clampf(float(c.s), 1.0, st.length - 1.0)
	var p: Vector3 = st.world_at(s, float(c.d))
	var ahead: Vector3 = st.world_at(s + 2.0 if looped else minf(s + 2.0, st.length - 0.5), float(c.d))
	var fwd: Vector3 = (ahead - p).normalized()
	if int(c.to) != int(c.lane):                             # (turned a little toward the lane it's going to)
		var r: Vector3 = st.right_at(s)
		var side := signf(_ld(int(c.to)) - _ld(int(c.lane)))
		fwd = (fwd + r * side * 0.06 * sin(u * PI)).normalized()
	var basis := Basis.looking_at(fwd, st.up_at(s) if looped else Vector3.UP)
	(c.body as AnimatableBody3D).global_transform = Transform3D(basis, p)
	var spin := float(c.v) * dt / 0.33
	for w in c.wheels:
		(w as Node3D).rotate_object_local(Vector3.RIGHT, -spin)


func _pick_model() -> Dictionary:
	var sum := 0.0
	for m in _pool:
		sum += float(m.weight)
	var x := _rng.randf() * sum
	for m in _pool:
		x -= float(m.weight)
		if x <= 0.0:
			return m
	return _pool[-1]


## A new car at s, in a lane with room (none: not spawned).
func _spawn(s: float) -> void:
	var m := _pick_model()
	var lane := _free_lane(s, float(m.half_len))
	if lane < 0:
		return
	_spawn_at(s, lane, m)


## A new car at s in a lane (m: its model, else one picked): the car, or {} if there's
## no room there.
func _spawn_at(s: float, lane: int, m := {}) -> Dictionary:
	if m.is_empty():
		m = _pick_model()
	for o in cars:
		if (int(o.lane) == lane or int(o.to) == lane) and absf(float(o.s) - s) < float(o.half_len) + float(m.half_len) + 6.0:
			return {}
	var body := _body_for(m)
	var wheels: Array = body.get_meta("wheels")
	var v0: float = _lane_speed(maxi(lane, 0))
	var c := {"id": _next_id, "model": m.id, "body": body, "wheels": wheels, "s": s, "lane": lane, "to": lane, "t": 0.0,
		"d": _ld(lane), "v": v0 * _rng.randf_range(0.9, 1.0), "v0": v0, "half_len": float(m.half_len),
		"half_w": float(m.half_w), "crashed": false, "think": _rng.randf_range(0.5, 3.0), "m": m}
	_next_id += 1
	cars.append(c)
	_place(c, 0.0)
	return c


## A traffic car's body: the model, painted, in a kinematic box the player hits.
func _body_for(m: Dictionary, solid := true) -> Node3D:
	var body: Node3D = AnimatableBody3D.new() if solid else Node3D.new()
	body.name = "Traffic%d" % _next_id
	if solid:
		(body as AnimatableBody3D).sync_to_physics = true
		body.set_meta("surface", "gravel")
		body.set_meta("traffic", true)
	var model: Node3D = m.scene.instantiate()
	body.add_child(model)
	if solid:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(m.half_w) * 2.0, float(m.height) * 0.85, float(m.half_len) * 2.0)
		cs.shape = box
		cs.position = Vector3(0, float(m.height) * 0.5, 0)
		body.add_child(cs)
	add_child(body)
	_paint(model, m.paints[_rng.randi() % m.paints.size()])
	var wheels: Array = []
	for n in model.find_children("Wheel_*", "Node3D", true, false):
		wheels.append(n)
	body.set_meta("wheels", wheels)
	return body


func _remove(c: Dictionary) -> void:
	cars.erase(c)
	(c.body as Node).queue_free()


func _respawn(c: Dictionary) -> void:
	_remove(c)
	# faster than the traffic: new cars appear ahead; slower: they come up from behind
	var ahead: bool = float(player.v) > float(diff.speed[0]) / 3.6 * 0.8
	var s: float = float(player.s) + (_rng.randf_range(AHEAD * 0.75, AHEAD) if ahead else -_rng.randf_range(BEHIND * 0.7, BEHIND))
	if looped or (s > st.START_S + 20.0 and s < st.length - 80.0):
		_spawn(s)


func _free_lane(s: float, half_len: float) -> int:
	var order: Array = range(lanes)
	order.shuffle()
	for lane in order:
		var ok := true
		for o in cars:
			if (int(o.lane) == lane or int(o.to) == lane) and absf(float(o.s) - s) < float(o.half_len) + half_len + 12.0:
				ok = false
				break
		if ok and absf(float(player.s) - s) < 30.0 and _player_in(lane):
			ok = false
		if ok:
			return lane
	return -1


func _lane_speed(lane: int) -> float:
	var sp: Array = diff.get("speed", [80.0, 120.0])
	return lerpf(float(sp[0]), float(sp[1]), (lane + _rng.randf()) / lanes) / 3.6   # (lane 0, the right-hand one, slowest)


## The player hit this car: it stops (and the score knows).
func hit(body: Node) -> Dictionary:
	for c in cars:
		if c.body == body:
			c.crashed = true
			return c
	return {}


## What the score needs: [{id, s, d, v, half_len, half_w}].
func snapshot() -> Array:
	var out: Array = []
	for c in cars:
		out.append({"id": c.id, "s": c.s, "d": c.d, "v": c.v, "half_len": c.half_len, "half_w": c.half_w})
	return out


func _paint(model: Node, paint) -> void:
	var col: Color = paint if paint is Color else Color(float(paint[0]), float(paint[1]), float(paint[2]))
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if mat and mat.resource_name == "paint" and mat is StandardMaterial3D:
				var m2: StandardMaterial3D = mat.duplicate()
				m2.albedo_color = col
				(mi as MeshInstance3D).set_surface_override_material(i, m2)


static func _bounds(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		var xf: Transform3D = (mi as Node3D).transform
		var p: Node = mi.get_parent()
		while p != null and p is Node3D:                    # (up to and including the model's root: its scale too)
			xf = (p as Node3D).transform * xf
			if p == n:
				break
			p = p.get_parent()
		b = xf * b
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


# ── the loop's packs, ramps and oncoming traffic ─────────────────────────

## Packs: a new one up the road once the last one's well inside the stretch (or
## behind, for a player slower than the traffic), while there's room for one.
func _refill_packs() -> void:
	if cars.size() + int(diff.pack[0]) > int(_target * 1.3):
		return
	var far := -INF
	var near := INF
	for c in cars:
		far = maxf(far, float(c.s) - float(player.s))
		near = minf(near, float(c.s) - float(player.s))
	var gap := _rng.randf_range(float(diff.pack_gap[0]), float(diff.pack_gap[1]))
	if far < AHEAD - gap:
		_spawn_pack(float(player.s) + maxf(far + gap, AHEAD * 0.7))
	elif float(player.v) < float(diff.speed[0]) / 3.6 * 0.8 and near > -BEHIND + gap:
		_spawn_pack(float(player.s) - BEHIND)


## Joining from a ramp's acceleration lane: into lane 0 when there's a gap (a smaller
## one than a lane change would take: it has to go before the lane ends).
func _merge(c: Dictionary) -> void:
	var lead := _leader(0, float(c.s), float(c.half_len), c)
	var back := _follower(0, float(c.s), float(c.half_len), c)
	if float(lead.gap) > 5.0 and float(back.gap) > 6.0:
		c.to = 0
		c.t = 0.0


## A car taking the next exit: over into the deceleration lane when it's there and
## there's room; at the gore it leaves the highway down the ramp.
func _exit_lane(c: Dictionary) -> void:
	var r: Dictionary = c.exit
	var ds: float = st.gore_ds(float(c.s), float(r.s))
	if int(c.lane) == 0 and ds > -float(r.len) + 50.0 and ds < -15.0:
		var back := _follower(-1, float(c.s), float(c.half_len), c)
		if float(back.gap) > 5.0:
			c.to = -1
			c.t = 0.0
	elif ds > 30.0:
		c.erase("exit")                                       # (missed it: carries on)


func _ramp_traffic(dt: float) -> void:
	var lap := floori(float(player.s) / st.length)
	for r in st.ramps:
		if r.side != "right":
			continue
		var ahead: float = st.gore_ds(float(r.s), float(player.s))
		if r.kind == "on" and ahead > 200.0 and ahead < 700.0 and _joined.get(r.s, -1) != lap:
			# a car coming down the ramp, timed to reach the gore about when the player does
			_joined[r.s] = lap
			var m := _pick_model()
			var path: Dictionary = st.ramp_path(r)
			var v := _rng.randf_range(19.0, 25.0)
			var k := minf(float(path.len), v * ahead / maxf(float(player.v), 15.0))
			var body := _body_for(m)
			ramp_cars.append({"body": body, "wheels": body.get_meta("wheels"), "path": path, "k": k, "v": v, "mode": "join", "r": r, "m": m})
		elif r.kind == "off" and ahead > 150.0 and ahead < 500.0:
			# now and then a car in the slow lane takes this exit
			for c in cars:
				if int(c.lane) == 0 and not c.has("exit") and not c.crashed and _rng.randf() < 0.001:
					var ds: float = st.gore_ds(float(c.s), float(r.s))
					if ds > -float(r.len) - 200.0 and ds < -float(r.len) + 40.0:
						c.exit = r
	# cars on a ramp's own road: along its path
	for rc in ramp_cars.duplicate():
		var path: Dictionary = rc.path
		if rc.mode == "join":
			rc.k = float(rc.k) - float(rc.v) * dt
			if float(rc.k) <= 0.0:
				# at the gore: on the highway now, in the acceleration lane
				ramp_cars.erase(rc)
				var c := {"id": _next_id, "model": rc.m.id, "body": rc.body, "wheels": rc.wheels, "s": float(player.s) + st.gore_ds(float(rc.r.s), float(player.s)),
					"lane": -1, "to": -1, "t": 0.0, "d": _ld(-1), "v": float(rc.v), "v0": _lane_speed(0) * 1.05,
					"half_len": float(rc.m.half_len), "half_w": float(rc.m.half_w), "crashed": false, "think": 1.0, "m": rc.m}
				_next_id += 1
				cars.append(c)
				continue
		else:
			rc.k = float(rc.k) + float(rc.v) * dt
			rc.v = maxf(float(rc.v) - 2.0 * dt, 14.0)
			if float(rc.k) >= float(path.len) - 8.0:
				ramp_cars.erase(rc)
				(rc.body as Node).queue_free()
				continue
		_place_on_path(rc, dt)
	# cars that reached the gore of their exit go onto its ramp
	for c in cars.duplicate():
		if c.has("exit") and int(c.lane) == -1 and st.gore_ds(float(c.s), float(c.exit.s)) >= 0.0:
			cars.erase(c)
			ramp_cars.append({"body": c.body, "wheels": c.wheels, "path": st.ramp_path(c.exit), "k": 0.0, "v": float(c.v), "mode": "exit", "r": c.exit, "m": c.m})


func _place_on_path(rc: Dictionary, dt: float) -> void:
	var path: Dictionary = rc.path
	var pts: PackedVector3Array = path.pts
	var f := clampf(float(rc.k) / 4.0, 0.0, pts.size() - 1.001)
	var i := int(f)
	var p := pts[i].lerp(pts[i + 1], f - i)
	var dir := (pts[i + 1] - pts[i]).normalized()
	if rc.mode == "join":
		dir = -dir                                            # (it drives the path backwards, towards the gore)
	(rc.body as Node3D).global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), p)
	var spin := float(rc.v) * dt / 0.33
	for w in rc.wheels:
		(w as Node3D).rotate_object_local(Vector3.RIGHT, -spin)


## The other carriageway: cars the other way round the loop, steady speeds, keeping to
## their lanes (seen across the barrier); back in up the road once they've passed.
func _spawn_oncoming(s: float) -> void:
	var m := _pick_model()
	var lane := _rng.randi() % lanes
	for o in oncoming:
		if int(o.lane) == lane and absf(float(o.s) - s) < 26.0:
			return
	var body := _body_for(m, false)
	var sp: Array = diff.get("speed", [80.0, 120.0])
	var v := lerpf(float(sp[0]), float(sp[1]), (lane + _rng.randf()) / lanes) / 3.6
	# their lane 0, the slow one, is on their right: our far left
	var d: float = st.ONCOMING_D - (st.EDGE - st.LANE_W * (lane + 0.5))
	oncoming.append({"body": body, "wheels": body.get_meta("wheels"), "s": s, "d": d, "v": v, "lane": lane})


func _oncoming_traffic(dt: float) -> void:
	for o in oncoming.duplicate():
		o.s = float(o.s) - float(o.v) * dt
		if float(o.s) < float(player.s) - 220.0:
			oncoming.erase(o)
			(o.body as Node).queue_free()
			_spawn_oncoming(float(player.s) + AHEAD + _rng.randf_range(0.0, 350.0))
			continue
		var s: float = o.s
		var p: Vector3 = st.world_at(s, float(o.d))
		var back: Vector3 = st.world_at(s - 2.0, float(o.d))
		(o.body as Node3D).global_transform = Transform3D(Basis.looking_at((back - p).normalized(), st.up_at(s)), p)
		var spin := float(o.v) * dt / 0.33
		for w in o.wheels:
			(w as Node3D).rotate_object_local(Vector3.RIGHT, -spin)
