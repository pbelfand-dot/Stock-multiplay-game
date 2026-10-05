extends SceneTree
## Physics v2, phase 1: the chassis on its four suspension corners, in the lab
## course (scripts/physics_lab.gd), at 120 ticks a second.
##   * static: it sits level at the ride height the springs and its weight give
##     (each corner squashed by its share of the weight / the spring rate)
##   * bounce: lifted 5 cm and let go, it bounces at about the ride frequency
##     (~1.5 Hz, a little less for the damping) and settles within ~2 s
##   * drop: from a metre up it lands on the bump stops without the body
##     hitting the ground, doesn't bounce back into the air, and settles
##   * bumps: rolling over full-width bumps pitches it; over bumps under the
##     left wheels only, it rolls; the forces act at the corners, nothing levels it
## Run: godot --headless --fixed-fps 120 --path . -s tests/physics_v2_check.gd
## Prints [physics] lines; exits 1 on any FAIL.

const Lab = preload("res://scripts/physics_lab.gd")
const Suspension = preload("res://scripts/vehicle/physics/suspension.gd")

var car: RigidBody3D
var fails := 0
var _phase := -1
var _t := 0.0
var _log: Array = []               # per tick: [t, y, pitch, roll, grounded, max comp, min body clearance]
var _y0 := 0.0
var _lift_t := 0.0
var _phases := ["static", "bounce", "drop", "bumps", "left bumps"]


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	var course := Node3D.new()
	root.add_child(course)
	Lab.build_course(course)
	car = (load(Lab.CAR_SCENE) as PackedScene).instantiate()
	root.add_child(car)
	_next()


func _process(_dt: float) -> bool:
	if car == null or not ("wheels" in car) or car.wheels.size() != 4:   # a script didn't load: say so, don't hang
		fails += _check(false, "the v2 car loaded with its four wheels")
		_phase = _phases.size()
		return _done()
	return false


func _next() -> void:
	_phase += 1
	_t = 0.0
	_log.clear()
	if _phase >= _phases.size():
		return
	match _phases[_phase]:
		"static":
			car.place(Lab.PAD, 0.0)
		"bounce":
			car.place(Lab.PAD, 0.0)
		"drop":
			car.place(Lab.PAD, 0.0)
			car.global_position.y += 1.0
		"bumps":
			Lab.launch(car, Vector3(0.0, 0.0, Lab.BUMPS_Z + 10.0), 12.0)
		"left bumps":
			Lab.launch(car, Vector3(Lab.BUMP_LANE_X, 0.0, Lab.BUMPS_Z + 10.0), 12.0)


func _physics_process(dt: float) -> bool:
	if _phase >= _phases.size():
		return _done()
	_t += dt
	var name: String = _phases[_phase]
	if name == "bounce" and _t > 2.0 and _y0 == 0.0:
		_y0 = car.global_position.y                  # settled: lift it 5 cm and let go
		_lift_t = _t
		car.global_position.y += 0.05
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		_log.clear()
	var xf := car.global_transform
	var fwd := -xf.basis.z
	var max_c := 0.0
	for w in car.wheels:
		max_c = maxf(max_c, w.compression)
	_log.append([_t, car.global_position.y, rad_to_deg(asin(clampf(fwd.y, -1, 1))), rad_to_deg(asin(clampf(xf.basis.x.y, -1, 1))),
		car.grounded, max_c, _clearance()])
	var length := {"static": 3.0, "bounce": 5.5, "drop": 4.5, "bumps": 4.0, "left bumps": 4.0}
	if _t >= length[name]:
		call(StringName("_judge_" + name.replace(" ", "_")))
		_next()
	return false


## How far the lowest corner of the body box is above the ground (y = 0) (m).
func _clearance() -> float:
	var cfg = car.config
	var lo := INF
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var p: Vector3 = car.global_transform * (cfg.body_center + cfg.body_size * 0.5 * Vector3(sx, sy, sz))
				lo = minf(lo, p.y)
	return lo


func _judge_static() -> void:
	var cfg = car.config
	var loads: Array = cfg.static_loads(9.8)
	var want_f: float = Suspension.static_compression(cfg.front_suspension, loads[0])
	var want_r: float = Suspension.static_compression(cfg.rear_suspension, loads[1])
	var c: Array = car.comp
	var err := maxf(maxf(absf(c[0] - want_f), absf(c[1] - want_f)), maxf(absf(c[2] - want_r), absf(c[3] - want_r)))
	var last: Array = _log[_log.size() - 1]
	var height_err: float = absf(last[1] - car.ride_height())
	fails += _check(err < 0.004, "static: each corner squashed by its share of the weight (front %.1f / rear %.1f mm, want %.1f / %.1f, off by %.1f mm at most)" % [
		(c[0] + c[1]) * 500.0, (c[2] + c[3]) * 500.0, want_f * 1000.0, want_r * 1000.0, err * 1000.0])
	fails += _check(height_err < 0.005, "static: at its ride height (%.3f m, want %.3f)" % [last[1], car.ride_height()])
	fails += _check(absf(last[2]) < 0.3 and absf(last[3]) < 0.1, "static: level (pitch %+.2f, roll %+.2f deg)" % [last[2], last[3]])
	fails += _check(car.linear_velocity.length() < 0.01 and car.grounded == 4, "static: still, on all four (%.3f m/s)" % car.linear_velocity.length())


func _judge_bounce() -> void:
	var cfg = car.config
	var loads: Array = cfg.static_loads(9.8)
	var f_front: float = Suspension.ride_frequency(cfg.front_suspension, loads[0] / 9.8)
	var f_rear: float = Suspension.ride_frequency(cfg.rear_suspension, loads[1] / 9.8)
	# swings through the settled height (counted once it's more than 1.5 mm past it
	# the other way: not the last sub-millimetre wobble), and what's left later
	var crossings: Array = []
	var side := 0.0
	for e in _log:
		var dy: float = e[1] - _y0
		if absf(dy) > 0.0015 and signf(dy) != side:
			if side != 0.0:
				crossings.append(e[0])
			side = signf(dy)
	var hz := 0.0
	if crossings.size() >= 2:
		hz = (crossings.size() - 1) / 2.0 / (crossings[crossings.size() - 1] - crossings[0])
	var after2 := 0.0
	var after3 := 0.0
	for e in _log:
		if e[0] - _lift_t > 2.0:
			after2 = maxf(after2, absf(e[1] - _y0))
		if e[0] - _lift_t > 3.0:
			after3 = maxf(after3, absf(e[1] - _y0))
	fails += _check(hz > 1.0 and hz < 1.8, "bounce: %.2f Hz (springs alone: front %.2f, rear %.2f Hz; damping slows it a little; %d swings)" % [
		hz, f_front, f_rear, crossings.size()])
	fails += _check(after2 < 0.006 and after3 < 0.002, "bounce: settles (from 50 mm: %.1f mm after 2 s, %.1f mm after 3 s)" % [after2 * 1000.0, after3 * 1000.0])


func _judge_drop() -> void:
	var landed := -1.0
	var unsettled := 0.0                             # the last time it was more than 5 mm off its ride height
	var hops := 0.0                                  # time with no wheel down after first touching
	var min_clear := INF
	var max_c := 0.0
	var dt := 1.0 / 120.0
	for e in _log:
		if landed < 0.0 and e[4] > 0:
			landed = e[0]
		if landed >= 0.0:
			if e[4] == 0:
				hops += dt
			min_clear = minf(min_clear, e[6])
			max_c = maxf(max_c, e[5])
			if absf(e[1] - car.ride_height()) > 0.005:
				unsettled = e[0]
	var last: Array = _log[_log.size() - 1]
	var travel: float = car.config.front_suspension.travel
	fails += _check(min_clear > 0.03, "drop 1 m: the body never touches the ground (lowest %.0f mm above it; deepest squash %.0f of %.0f mm travel)" % [
		min_clear * 1000.0, max_c * 1000.0, travel * 1000.0])
	fails += _check(hops < 0.05, "drop 1 m: no bounce back into the air (%.2f s with no wheel down after landing)" % hops)
	fails += _check(absf(last[1] - car.ride_height()) < 0.01 and car.linear_velocity.length() < 0.02,
		"drop 1 m: settled at its ride height (within 5 mm %.1f s after landing)" % (unsettled - landed))


func _judge_bumps() -> void:
	var pitch := 0.0
	var roll := 0.0
	for e in _log:
		pitch = maxf(pitch, absf(e[2]))
		roll = maxf(roll, absf(e[3]))
	fails += _check(pitch > 0.4 and roll < 0.3, "bumps: they pitch it (up to %.1f deg) without rolling it (%.2f deg)" % [pitch, roll])
	fails += _check(car.global_transform.basis.y.y > 0.99 and _log[_log.size() - 1][4] == 4, "bumps: still upright, all four down after")


func _judge_left_bumps() -> void:
	var roll := 0.0
	for e in _log:
		roll = maxf(roll, absf(e[3]))
	fails += _check(roll > 0.4, "left-side bumps: they roll it (up to %.1f deg)" % roll)
	fails += _check(car.global_transform.basis.y.y > 0.99, "left-side bumps: still upright")


func _check(ok: bool, msg: String) -> int:
	print("[physics] %s %s" % ["ok  " if ok else "FAIL", msg])
	return 0 if ok else 1


func _done() -> bool:
	fails += _check(Engine.physics_ticks_per_second == 120, "running at %d ticks a second" % Engine.physics_ticks_per_second)
	print("[physics] %s" % ("PHYSICS V2 OK" if fails == 0 else "PHYSICS V2 FAIL"))
	quit(1 if fails > 0 else 0)
	return true
