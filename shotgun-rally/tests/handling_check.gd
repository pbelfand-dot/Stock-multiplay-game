extends SceneTree
## How the car handles, in numbers, on a flat gravel pad (no stage):
##   * steady cornering at 50 / 80 / 110 km/h, holding the speed, at several
##     amounts of steering: the sideways grip (g) it reaches, the front and
##     rear slip angles, and whether FULL steering is the most grip (if half
##     steering corners harder, full lock is past the tyres' peak: that's the
##     "always understeering and losing traction" a keyboard player feels)
##   * a lift-off turn-in and a handbrake turn rotate the car
##   * it brakes straight and stays straight flat out
##   * the wheels: a launch spins them up and pulls away; full brake while
##     steering locks the fronts (no ABS), half brake turns the car more
## Run: godot --headless --fixed-fps 120 --path . -s tests/handling_check.gd [-- --report]
## Prints one [handling] line per check; exits 1 on any FAIL.

var RallyCar
var car
var fails := 0
var report := false
var _steps: Array = []
var _step := -1
var _t := 0.0
var _acc := {}
var _yaw0 := 0.0


func _initialize() -> void:
	RallyCar = load("res://scripts/vehicle/rally_car.gd")
	report = OS.get_cmdline_user_args().has("--report")
	var pad := StaticBody3D.new()
	pad.set_meta("surface", "gravel")
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(4000, 2, 4000)
	cs.shape = bx
	pad.add_child(cs)
	pad.position = Vector3(0, -1, 0)
	root.add_child(pad)
	car = RallyCar.new()
	root.add_child(car)
	car.place(Vector3.ZERO, 0.0)
	for kmh in [50.0, 80.0, 110.0]:
		for amount in [0.25, 0.5, 0.75, 1.0]:
			_steps.append({"kind": "corner", "kmh": kmh, "steer": amount})
	_steps.append({"kind": "liftoff"})
	_steps.append({"kind": "handbrake"})
	_steps.append({"kind": "straight"})
	_steps.append({"kind": "launch"})
	_steps.append({"kind": "lock", "brake": 1.0})
	_steps.append({"kind": "lock", "brake": 0.5})
	_next()


func _next() -> void:
	_step += 1
	_t = 0.0
	_acc = {"n": 0, "lat": 0.0, "af": 0.0, "ar": 0.0, "beta": 0.0, "kmh": 0.0}
	if _step >= _steps.size():
		return
	car.place(Vector3(0.0, 0.0, 0.0), 0.0)
	car.inp = {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": false}


func _physics_process(dt: float) -> bool:
	if _step >= _steps.size():
		return _finish()
	var s: Dictionary = _steps[_step]
	_t += dt
	match s.kind:
		"corner":
			# get up to speed in a straight line (the pad is big), then hold the speed and steer
			var want: float = s.kmh / 3.6
			var spd: float = car.speed
			var thr := clampf((want - spd) * 0.6, 0.0, 1.0)
			var brk := clampf((spd - want) * 0.3, 0.0, 1.0) if spd > want + 1.5 else 0.0
			if _t < 2.0:
				car.place(Vector3(0, 0, 0), 0.0)          # launched at speed: no long run-up
				car.set_speed(want)                       # (the wheels turning with it)
				car.inp = {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": false}
				_t = 2.0
			else:
				car.inp = {"steer": s.steer, "throttle": thr, "brake": brk, "handbrake": false}
			if _t > 6.0:
				var m := _measure()
				_acc.n += 1
				for k in ["lat", "af", "ar", "beta", "kmh"]:
					_acc[k] += m[k]
			if _t > 9.0:
				for k in ["lat", "af", "ar", "beta", "kmh"]:
					_acc[k] /= maxf(_acc.n, 1)
				s["result"] = _acc.duplicate()
				if report:
					print("[handling]   %3.0f km/h steer %3.0f%%: %.2f g, front slip %4.1f deg, rear %4.1f deg, body %+5.1f deg (held %3.0f km/h)" % [
						s.kmh, s.steer * 100.0, _acc.lat, _acc.af, _acc.ar, _acc.beta, _acc.kmh])
				_next()
		"liftoff":
			# 80 km/h, steer in hard while lifting and dabbing the brake: the nose must bite
			if _t < 0.1:
				car.set_speed(80.0 / 3.6)
				_yaw0 = car.global_rotation.y
			var brake := 0.4 if _t < 0.6 else 0.0
			car.inp = {"steer": 1.0, "throttle": 0.0, "brake": brake, "handbrake": false}
			if _t > 1.5:
				var turned := absf(wrapf(car.global_rotation.y - _yaw0, -PI, PI))
				s["result"] = {"deg": rad_to_deg(turned)}
				_next()
		"handbrake":
			# the rears lock at once; the body takes a moment to start turning
			if _t < 0.1:
				car.set_speed(50.0 / 3.6)
				_yaw0 = car.global_rotation.y
			car.inp = {"steer": 1.0, "throttle": 0.0, "brake": 0.0, "handbrake": _t < 1.5}
			if _t > 1.5:
				var turned := absf(wrapf(car.global_rotation.y - _yaw0, -PI, PI))
				s["result"] = {"deg": rad_to_deg(turned)}
				_next()
		"straight":
			car.inp = {"steer": 0.0, "throttle": 1.0, "brake": 0.0, "handbrake": false}
			if _t > 12.0:
				s["result"] = {"yaw": rad_to_deg(absf(car.global_rotation.y)), "kmh": car.kmh()}
				_next()
		"launch":
			# from a standstill, flat out: how far the rear wheels spin ahead of the ground
			car.inp = {"steer": 0.0, "throttle": 1.0, "brake": 0.0, "handbrake": false}
			if _t > 0.2:
				_acc.lat = maxf(_acc.lat, (_spin_ahead(car.wheels[2]) + _spin_ahead(car.wheels[3])) * 0.5)
			if _t > 1.5:
				s["result"] = {"slip": _acc.lat, "kmh": car.kmh()}
				_next()
		"lock":
			# 100 km/h, then brake + full steering for 1 s: locked fronts don't steer
			if _t < 0.1:
				car.set_speed(100.0 / 3.6)
				_yaw0 = car.global_rotation.y
			car.inp = {"steer": 1.0, "throttle": 0.0, "brake": s.brake, "handbrake": false}
			if _t > 0.15:
				_acc.n += 1
				_acc.af += 1.0 if minf(car.wheels[0].slip_long, car.wheels[1].slip_long) < -0.4 else 0.0   # a front sliding, (nearly) locked
			if _t > 1.1:
				# how far the way it's GOING turned (locked fronts don't steer it, even if the tail swings)
				var v: Vector3 = car.linear_velocity
				var course := absf(wrapf(atan2(v.x, -v.z), -PI, PI))
				s["result"] = {"deg": rad_to_deg(course), "locked": _acc.af / maxf(_acc.n, 1.0), "kmh": car.kmh()}
				_next()
	return false


## How far a wheel's rim runs ahead of the ground (its slip ratio, measured against
## at least 3 m/s so a crawl doesn't read as huge).
func _spin_ahead(w) -> float:
	return (w.omega * w.radius - w.v_long) / maxf(absf(w.v_long), 3.0)


## Sideways g (along the car's right), slip angles at each axle and the body slip.
func _measure() -> Dictionary:
	var xf: Transform3D = car.global_transform
	var fwd := -xf.basis.z
	var right := xf.basis.x
	var v: Vector3 = car.linear_velocity
	var w: Vector3 = car.angular_velocity
	var vlong := v.dot(fwd)
	var lat_acc := absf(w.y * vlong) / 9.8           # v * yaw rate (steady state)
	var vf := v + w.cross(xf.basis * Vector3(0, 0, car.config.front_axle))
	var vr := v + w.cross(xf.basis * Vector3(0, 0, car.config.rear_axle))
	var af := absf(rad_to_deg(car.steer - atan2(vf.dot(right), vf.dot(fwd))))
	var ar := absf(rad_to_deg(atan2(vr.dot(right), vr.dot(fwd))))
	var beta := rad_to_deg(atan2(v.dot(right), maxf(vlong, 1.0)))
	return {"lat": lat_acc, "af": af, "ar": ar, "beta": beta, "kmh": vlong * 3.6}


func _check(ok: bool, msg: String) -> int:
	print("[handling] %s %s" % ["ok  " if ok else "FAIL", msg])
	return 0 if ok else 1


func _finish() -> bool:
	# cornering: at each speed, full steering must be (about) the most grip
	for kmh in [50.0, 80.0, 110.0]:
		var best := 0.0
		var full := 0.0
		var full_r: Dictionary = {}
		for s in _steps:
			if s.kind == "corner" and s.kmh == kmh and s.has("result"):
				best = maxf(best, s.result.lat)
				if s.steer == 1.0:
					full = s.result.lat
					full_r = s.result
		fails += _check(full >= best * 0.95, "%3.0f km/h: full steering %.2f g (best %.2f g), front slip %.1f deg, rear %.1f deg" % [
			kmh, full, best, full_r.get("af", 0.0), full_r.get("ar", 0.0)])
		fails += _check(full > 0.7 and full < 1.25, "%3.0f km/h: corners at %.2f g on gravel (0.7 .. 1.25)" % [kmh, full])
	for s in _steps:
		match s.kind:
			"liftoff":
				fails += _check(s.result.deg > 25.0, "lift-off turn-in at 80 km/h rotated %.0f deg in 1.5 s" % s.result.deg)
			"handbrake":
				fails += _check(s.result.deg > 60.0, "handbrake turn at 50 km/h rotated %.0f deg in 1.5 s" % s.result.deg)
			"straight":
				fails += _check(s.result.yaw < 3.0, "flat out for 12 s: %.0f km/h, drifted %.1f deg off straight" % [s.result.kmh, s.result.yaw])
			"launch":
				# flat out from a standstill a 400 N m car spins its tyres on gravel for a moment
				# (no traction control): they must spin, and it must still pull away briskly
				fails += _check(s.result.slip > 0.03 and s.result.kmh > 30.0, "launch: the rear wheels spin up (%.0f %% ahead of the ground at most) and it pulls away: %.0f km/h after 1.5 s" % [s.result.slip * 100.0, s.result.kmh])
	var full: Dictionary = {}
	var half: Dictionary = {}
	for s in _steps:
		if s.kind == "lock" and s.has("result"):
			if s.brake == 1.0:
				full = s.result
			else:
				half = s.result
	if not full.is_empty() and not half.is_empty():
		fails += _check(full.locked > 0.5, "full brake at 100 km/h, steering: a front wheel locks up and slides (%.0f %% of the time)" % (full.locked * 100.0))
		fails += _check(half.deg > full.deg * 1.6, "half brake still steers: its path turned %.0f deg vs %.0f locked (the fronts locked %.0f %% of the time)" % [half.deg, full.deg, half.locked * 100.0])
	print("[handling] %s" % ("HANDLING OK" if fails == 0 else "HANDLING FAIL"))
	quit(1 if fails > 0 else 0)
	return true
