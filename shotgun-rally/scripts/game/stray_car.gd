extends Node3D
## The touge's stray car: now and then a local driver out on the pass. Mostly one
## coming up the other way in its own lane (Japan drives on the left: ours is the
## left lane, theirs the right as you look up the road), sometimes one pottering
## along ahead in yours for you to get past. It takes the bends at a local's pace
## (slower in the hairpins), its lamps lit at night. Hit it and it stops where it
## is, hazards blinking, until you're well past. Each machine has its own (online:
## nobody else sees yours); one at a time, ~40-90 s apart.
##   setup(stage, seed, night)  tick(dt, player_s, player_pos)  bump(pos)

const VehicleRegistry = preload("res://scripts/game/vehicle_registry.gd")
const CarLamps = preload("res://scripts/vehicle/car_lamps.gd")
const CarLook = preload("res://scripts/render/car_look.gd")
const AHEAD := [260.0, 420.0]   # m ahead of the player it turns up (round a bend or two, out of sight)
const FIRST := [20.0, 45.0]     # s into the run before the first one
const GAP := [40.0, 90.0]       # s between one leaving and the next
const ONCOMING := 0.7           # the share coming the other way
const ONCOMING_KMH := [45.0, 65.0]
const AHEAD_KMH := [32.0, 46.0]
const LAT := 3.2                # m/s^2: how hard it takes a bend (a local, not racing)
const DECEL := 3.0              # m/s^2 it brakes for one
const GONE_BEHIND := 140.0      # m behind the player: it's gone

var st
var night := false
var enabled := true
var car := {}                   # {body, lamps, s, d, v, v0, dir (+1 with us, -1 toward us), crashed, half_len}
var spawned := 0                # (tests) how many have turned up
var crashes := 0                # (tests) how many were hit
var _pool: Array = []           # {scene, paints, half_len, half_w, height}
var _rng := RandomNumberGenerator.new()
var _wait := 0.0


func setup(stage, seed_value: int, is_night: bool) -> void:
	st = stage
	night = is_night
	name = "StrayCar"
	_rng.seed = hash([seed_value, "stray"])
	_wait = _rng.randf_range(FIRST[0], FIRST[1])
	var seen_only := OS.get_cmdline_user_args().has("--seen_cars_only")   # (screenshots: no no-AI cars)
	for e in VehicleRegistry.traffic_pool():
		var path := "res://assets/models/cars/%s/%s.glb" % [e.model, e.model]
		if not ResourceLoader.exists(path) or (seen_only and VehicleRegistry.no_ai(e.id)):
			continue
		var scene: PackedScene = load(path)
		var probe: Node3D = scene.instantiate()
		var box := _bounds(probe)
		probe.free()
		_pool.append({"scene": scene, "paints": e.paints, "half_len": box.size.z * 0.5, "half_w": box.size.x * 0.5,
			"height": box.size.y})


func lane_d(dir: int) -> float:
	return st.LANE_W * 0.5 * (1.0 if dir < 0 else -1.0)       # (toward us: the right as we look up the road)


## Each physics tick while the run is on: maybe one turns up; it drives; it goes.
func tick(dt: float, player_s: float, player_pos: Vector3) -> void:
	if car.is_empty():
		if not enabled or _pool.is_empty():
			return
		_wait -= dt
		if _wait <= 0.0:
			_spawn(player_s)
		return
	if not car.crashed:
		_drive(dt)
	var behind: float = player_s - float(car.s)
	if behind > GONE_BEHIND or float(car.s) < 2.0 or float(car.s) > st.length - 2.0 \
			or (int(car.dir) > 0 and float(car.s) > st.finish_s + 20.0):
		_remove()
		return
	_pose(dt)


func _spawn(player_s: float) -> void:
	var s: float = player_s + _rng.randf_range(AHEAD[0], AHEAD[1])
	if s > st.finish_s - 40.0:
		_wait = 5.0                                  # (too near the finish: maybe later, if they're slow)
		return
	spawn_at(s, -1 if _rng.randf() < ONCOMING else 1)


## One at s, going dir (+1 with us, -1 toward us). (Also the tests' and pictures'.)
func spawn_at(s: float, dir: int) -> void:
	if not car.is_empty() or _pool.is_empty():
		return
	var m: Dictionary = _pool[_rng.randi() % _pool.size()]
	var body := AnimatableBody3D.new()
	body.name = "Stray"
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
	CarLook.glow_model(model)                        # (its lamps glow: dim by day, full at night)
	var kmh: Array = ONCOMING_KMH if dir < 0 else AHEAD_KMH
	var v0: float = _rng.randf_range(kmh[0], kmh[1]) / 3.6
	car = {"body": body, "model": model, "s": s, "d": lane_d(dir), "v": v0, "v0": v0, "dir": dir, "crashed": false,
		"half_len": float(m.half_len), "lamps": null}
	var wheels: Array = []
	for n in model.find_children("Wheel_*", "Node3D", true, false):
		wheels.append(n)
	car["wheels"] = wheels
	car.v = minf(v0, _want())                        # (not into a hairpin flat out)
	_pose(0.0)
	if night:
		car.lamps = CarLamps.fit(body, model, true, false)   # (no tail light: the lights the screen can pay for are few)
	spawned += 1


## Along its lane at its pace, braking for the bends it can see coming.
func _drive(dt: float) -> void:
	var want := _want()
	car.v = move_toward(float(car.v), want, (DECEL if want < float(car.v) else 1.5) * dt)
	car.s = float(car.s) + int(car.dir) * float(car.v) * dt


## The most it should be doing here: its cruising speed, or what lets it slow in
## time for the tightest bend in the next 50 m.
func _want() -> float:
	var want: float = car.v0
	var look := 0.0
	while look <= 50.0:
		var v_bend := sqrt(LAT * _radius(float(car.s) + int(car.dir) * look))
		want = minf(want, sqrt(v_bend * v_bend + 2.0 * DECEL * look))
		look += st.STEP
	return want


func _radius(s: float) -> float:
	var i := clampi(int(s / st.STEP), 0, st.curv.size() - 1)
	return 1.0 / maxf(absf(st.curv[i]), 1.0 / 400.0)


func _pose(dt: float) -> void:
	var s: float = clampf(float(car.s), 1.0, st.length - 1.0)
	var p: Vector3 = st.world_at(s, float(car.d))
	var ahead: Vector3 = st.world_at(clampf(s + int(car.dir) * 2.0, 0.5, st.length - 0.5), float(car.d))
	(car.body as AnimatableBody3D).global_transform = Transform3D(Basis.looking_at((ahead - p).normalized(), Vector3.UP), p)
	var spin := float(car.v) * dt / 0.33
	for w in car.wheels:
		(w as Node3D).rotate_object_local(Vector3.RIGHT, -spin)


## The player's car hit something at pos: if it was this one, it stops.
func bump(pos: Vector3) -> void:
	if car.is_empty() or car.crashed:
		return
	if (car.body as Node3D).global_position.distance_to(pos) < float(car.half_len) + 3.0:
		car.crashed = true
		car.v = 0.0
		crashes += 1
		if car.lamps:
			car.lamps.hazards(true)


func _remove() -> void:
	(car.body as Node).queue_free()
	car = {}
	_wait = _rng.randf_range(GAP[0], GAP[1])


## Its paint (as the traffic's: the models' material named "paint").
static func _paint(model: Node, paint) -> void:
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
		while p != null and p is Node3D:
			xf = (p as Node3D).transform * xf
			if p == n:
				break
			p = p.get_parent()
		b = xf * b
		box = b if first else box.merge(b)
		first = false
	return box
