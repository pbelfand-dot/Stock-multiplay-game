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
	if _pool.is_empty():
		return
	# the first lot: ahead of the start, spread out (none right beside the grid)
	for k in _target:
		var s: float = player_s + 70.0 + (AHEAD - 70.0) * (k + _rng.randf()) / _target
		_spawn(s)


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
		if rel < -BEHIND - 40.0 or rel > AHEAD + 120.0 or float(c.s) > st.length - 40.0:
			_respawn(c)


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
	return absf(float(player.d) - float(lane_d[lane])) < st.LANE_W * 0.5 + 0.95


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
	# lane changes: finishing one, or thinking about one now and then
	if int(c.to) != int(c.lane):
		c.t = float(c.t) + dt / LANE_CHANGE_T
		if float(c.t) >= 1.0:
			c.lane = c.to
			c.t = 0.0
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
	c.d = lerpf(float(lane_d[int(c.lane)]), float(lane_d[int(c.to)]), u)
	var s: float = clampf(float(c.s), 1.0, st.length - 1.0)
	var p: Vector3 = st.world_at(s, float(c.d))
	var ahead: Vector3 = st.world_at(minf(s + 2.0, st.length - 0.5), float(c.d))
	var fwd: Vector3 = (ahead - p).normalized()
	if int(c.to) != int(c.lane):                             # (turned a little toward the lane it's going to)
		var r: Vector3 = st.right_at(s)
		var side := signf(float(lane_d[int(c.to)]) - float(lane_d[int(c.lane)]))
		fwd = (fwd + r * side * 0.06 * sin(u * PI)).normalized()
	var basis := Basis.looking_at(fwd, Vector3.UP)
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
	var body := AnimatableBody3D.new()
	body.name = "Traffic%d" % _next_id
	body.sync_to_physics = true
	body.set_meta("surface", "gravel")
	body.set_meta("traffic", true)
	var model: Node3D = m.scene.instantiate()
	body.add_child(model)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(float(m.half_w) * 2.0, float(m.height) * 0.85, float(m.half_len) * 2.0)
	cs.shape = box
	cs.position = Vector3(0, float(m.height) * 0.5, 0)
	body.add_child(cs)
	add_child(body)
	_paint(model, m.paints[_rng.randi() % m.paints.size()])
	load("res://scripts/render/car_look.gd").glow_model(model)    # (its lamps: running lights by day, full at night)
	var wheels: Array = []
	for n in model.find_children("Wheel_*", "Node3D", true, false):
		wheels.append(n)
	var v0: float = _lane_speed(lane)
	var c := {"id": _next_id, "model": m.id, "body": body, "wheels": wheels, "s": s, "lane": lane, "to": lane, "t": 0.0,
		"d": float(lane_d[lane]), "v": v0 * _rng.randf_range(0.9, 1.0), "v0": v0, "half_len": float(m.half_len),
		"half_w": float(m.half_w), "crashed": false, "think": _rng.randf_range(0.5, 3.0)}
	_next_id += 1
	cars.append(c)
	_place(c, 0.0)


func _respawn(c: Dictionary) -> void:
	cars.erase(c)
	(c.body as Node).queue_free()
	# faster than the traffic: new cars appear ahead; slower: they come up from behind
	var ahead: bool = float(player.v) > float(diff.speed[0]) / 3.6 * 0.8
	var s: float = float(player.s) + (_rng.randf_range(AHEAD * 0.75, AHEAD) if ahead else -_rng.randf_range(BEHIND * 0.7, BEHIND))
	if s > st.START_S + 20.0 and s < st.length - 80.0:
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
