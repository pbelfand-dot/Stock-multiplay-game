extends SceneTree
## The road's edges: slide off and you can save it.
##   * the ground: rays down every few metres along two stages, from the road's
##     edge out to 6 m past it, both sides: it's flush with the edge (no ditch to
##     drop a wheel in, no bank to trip on) and no step between samples (but at
##     a bridge: its gully is meant to be there, and its rails stop you)
##   * no tree trunk within 4.5 m of the road's edge (the wall stands back)
##   * running wide: the car goes off the road at 70 km/h, 10 and 15 deg out,
##     sliding; after 0.4 s the "driver" gently steers back: at 10 deg (a drift
##     run wide) it's back on the road within a few seconds; at 15 deg (a big
##     moment: it can reach the trees) it at least stays on its wheels
## Run: godot --headless --fixed-fps 120 --path . -s tests/runoff_check.gd
## Prints [runoff] lines; exits 1 on any FAIL.

const SEEDS := [3, 15]
const RUNOFF := 6.0             # m past the edge that must be flat
const MAX_DIP := 0.12           # m below / above the road's edge
const MAX_STEP := 0.12          # m between samples 0.5 m apart (a slope a tyre rolls over, not a lip)

var StageGen
var StageBuilder
var RallyCar
var Autopilot
var fails := 0
var _phase := 0
var _st
var _builder
var _car
var _ap
var _t := 0.0
var _hint := -1
var _runs: Array = []
var _run := -1
var _m := {}


func _initialize() -> void:
	StageGen = load("res://scripts/stage/stage_gen.gd")
	StageBuilder = load("res://scripts/stage/stage_builder.gd")
	RallyCar = load("res://scripts/vehicle/rally_car.gd")
	Autopilot = load("res://scripts/vehicle/autopilot.gd")
	_build(SEEDS[0])


func _build(seed_value: int) -> void:
	if _builder:
		_builder.queue_free()
	_st = StageGen.new()
	_st.generate(seed_value)
	_builder = StageBuilder.new()
	root.add_child(_builder)
	_builder.build(_st)


func _physics_process(dt: float) -> bool:
	_t += dt
	match _phase:
		0, 2:                                        # let the collision shapes register, then scan
			if _t > 0.2:
				_scan(SEEDS[_phase / 2])
				_trees(SEEDS[_phase / 2])
				_t = 0.0
				if _phase == 0:
					_build(SEEDS[1])
					_phase = 2
				else:
					_phase = 3
		3:
			_start_slides()
			_phase = 4
		4:
			return _slide(dt)
	return false


func _scan(seed_value: int) -> void:
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var worst_dip := 0.0
	var worst_step := 0.0
	var where := ""
	var step_at := ""
	var s: float = _st.START_S + 20.0
	while s < _st.finish_s:
		if _st.on_bridge(s, 8.0):                    # (a bridge's rails are what stop you there)
			s += 6.0
			continue
		var half: float = _st.width_at(s) * 0.5
		var edge_y: float = _st.world_at(s, half).y
		for side in [-1.0, 1.0]:
			var prev := NAN
			var x := half
			while x <= half + RUNOFF:
				var p: Vector3 = _st.world_at(s, side * x)
				var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4.0, p + Vector3.DOWN * 4.0)
				var hit := space.intersect_ray(q)
				if not hit.is_empty() and not _is_obstacle(hit.collider):
					var dh: float = hit.position.y - edge_y
					if absf(dh) > absf(worst_dip):
						worst_dip = dh
						where = "s %.0f, %.1f m past the %s edge" % [s, x - half, "left" if side < 0 else "right"]
					if not is_nan(prev) and absf(hit.position.y - prev) > worst_step:
						worst_step = absf(hit.position.y - prev)
						step_at = "s %.0f, %.1f m past the %s edge, on %s" % [s, x - half, "left" if side < 0 else "right", hit.collider.name]
					prev = hit.position.y
				x += 0.5
		s += 6.0
	fails += _check(absf(worst_dip) < MAX_DIP, "seed %d: the ground out to %.0f m past the edge is flush with it (worst %+.2f m, %s)" % [
		seed_value, RUNOFF, worst_dip, where])
	fails += _check(worst_step < MAX_STEP, "seed %d: no step in it (worst %.3f m in 0.5 m, %s)" % [seed_value, worst_step, step_at])


## Trees are things to hit, not the ground.
func _is_obstacle(o: Object) -> bool:
	return o is Node and (o as Node).name in ["Trunks"]


func _trees(seed_value: int) -> void:
	var trunks: Node = _builder.get_node_or_null("Trunks")
	var nearest := INF
	if trunks:
		for cs in trunks.get_children():
			var p: Vector3 = (cs as Node3D).position
			var at: Dictionary = _st.locate(p, -1)
			if at.s < _st.START_S or at.s > _st.length - 5.0:
				continue
			nearest = minf(nearest, absf(at.d) - _st.width_at(at.s) * 0.5)
	fails += _check(nearest > 4.0, "seed %d: the nearest tree trunk is %.1f m past the road's edge (> 4)" % [seed_value, nearest])


## Slides off both sides, on a few straights of the second stage.
func _start_slides() -> void:
	_car = RallyCar.new()
	root.add_child(_car)
	_ap = Autopilot.new(_st)
	var runs: Array = _st._straight_runs(60.0).filter(func(r): return not _st.on_bridge((r.x + r.y) * 0.5, 40.0))   # (not at a bridge: its rails stop you)
	for k in mini(runs.size(), 3):
		for side in [-1.0, 1.0]:
			_runs.append({"s": (runs[k].x + runs[k].y) * 0.5, "side": side, "deg": 10.0 if k % 2 == 0 else 15.0})
	_next()


func _next() -> void:
	_run += 1
	_t = 0.0
	_hint = -1
	if _run >= _runs.size():
		return
	var r: Dictionary = _runs[_run]
	var s: float = r.s
	var a := deg_to_rad(r.deg)
	_car.place(_st.world_at(s, r.side * 1.0), _st.heading_at(s) + r.side * a * 1.5)
	var fwd: Vector3 = _st.forward_at(s)
	var right: Vector3 = _st.right_at(s)
	# 70 km/h, heading out toward the edge, the nose pointing out further still (sliding),
	# the wheels rolling with it (not skidding up to speed)
	var v: Vector3 = (fwd * cos(a) + right * r.side * sin(a)) * 70.0 / 3.6
	_car.set_speed(v.dot(-_car.global_transform.basis.z))
	_car.linear_velocity = v
	_car.angular_velocity = Vector3.UP * -r.side * 0.4
	_m = {"max_d": 0.0, "upright": true, "back": -1.0}


func _slide(dt: float) -> bool:
	if _run >= _runs.size():
		print("[runoff] %s" % ("RUNOFF OK" if fails == 0 else "RUNOFF FAIL"))
		quit(1 if fails > 0 else 0)
		return true
	var at: Dictionary = _st.locate(_car.global_position, _hint)
	_hint = at.i
	_car.set_lanes(_st, at.s, at.d)
	var half: float = _st.width_at(at.s) * 0.5
	var off: float = absf(at.d) - half
	_m.max_d = maxf(_m.max_d, off)
	_m.upright = _m.upright and _car.global_transform.basis.y.y > 0.5
	if _t < 0.4:
		_car.inp = {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": false}    # it runs wide
	else:
		_car.inp = _save_it(at)                                                       # then: save it
	if _m.back < 0.0 and _t > 0.4 and _m.max_d > 0.0 and off < -0.8:
		_m.back = _t
	if _t > 9.0 or _m.back >= 0.0:
		var r: Dictionary = _runs[_run]
		fails += _check(_m.upright and (_m.back >= 0.0 or r.deg > 12.0), "off the %s at 70 km/h, %.0f deg: %.1f m onto the grass, %s, back on the road %s" % [
			"left" if r.side < 0 else "right", r.deg, _m.max_d, "upright" if _m.upright else "ROLLED",
			"after %.1f s" % _m.back if _m.back >= 0.0 else "NEVER (stuck: %.0f km/h, %.1f m off, facing %.0f deg off the road)" % [
				_car.linear_velocity.length() * 3.6, off, rad_to_deg(absf(angle_difference(_car.rotation.y, -_st.heading_at(at.s))))]])
		_next()
	return false


## A person rejoining the road: aim for a point on it 18 m ahead, gently, a
## little throttle (not the autopilot: it's built to race the line, and slams
## the steering back on).
func _save_it(at: Dictionary) -> Dictionary:
	var target: Vector3 = _st.world_at(at.s + 18.0, 0.0)
	var fwd: Vector3 = -_car.global_transform.basis.z
	var to: Vector3 = target - _car.global_position
	var err := Vector2(fwd.x, fwd.z).angle_to(Vector2(to.x, to.z))     # + = the target is to the right
	return {"steer": clampf(err * 1.2, -0.7, 0.7), "throttle": 0.35, "brake": 0.0, "handbrake": false}


func _check(ok: bool, msg: String) -> int:
	print("[runoff] %s %s" % ["ok  " if ok else "FAIL", msg])
	return 0 if ok else 1
