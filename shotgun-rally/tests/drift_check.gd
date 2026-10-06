extends SceneTree
## Drifting on tarmac with a keyboard, the car out of the box (ARCADE tyre grip,
## tarmac tyres and setup, the default driver aids), on a flat asphalt pad:
##   * a handbrake entry caught with full opposite lock and full throttle: it
##     stays on its wheels (the extra grip used to roll it: the tip guard) and
##     drives on; nor does full lock held at 110 km/h or a flick left-right-left
##     tip it over (both did)
##   * the rear-drive car, a handbrake hairpin held with full lock and throttle:
##     it holds a drift (body slip under 50 deg) and keeps its speed, where with
##     drift assist off it swings round and stalls
##   * the rear-drive car through linked S-bends on the handbrake: no spin
##   * slowly, a handbrake U-turn swings it round just as it does without the assist
## Run: godot --headless --fixed-fps 120 --path . -s tests/drift_check.gd
## Prints one [drift] line per check; exits 1 on any FAIL.

var RallyCar
var Catalog
var car
var pad
var fails := 0
var _cases: Array = []
var _i := -1
var _t := 0.0
var _r := {}
var _out := {}


func _initialize() -> void:
	RallyCar = load("res://scripts/vehicle/rally_car.gd")
	Catalog = load("res://scripts/game/catalog.gd")
	pad = StaticBody3D.new()
	pad.set_meta("surface", "asphalt")
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(4000, 2, 4000)
	cs.shape = bx
	pad.add_child(cs)
	pad.position = Vector3(0, -1, 0)
	root.add_child(pad)
	# each: the car, the speed, the inputs in phases [until t, steer, throttle, handbrake]
	_cases = [
		{"id": "catch", "car": "kestrel", "v": 70, "ph": [[1.0, 0, 0.3, 0], [1.5, 1, 0, 1], [3.0, -1, 1, 0], [6.0, 0, 0.3, 0]]},
		{"id": "hairpin", "car": "martello", "v": 50, "ph": [[1.0, 0, 0.2, 0], [1.6, 1, 0, 1], [3.6, 1, 1, 0], [6.0, 0, 0.3, 0]]},
		{"id": "hairpin_off", "car": "martello", "v": 50, "ph": [[1.0, 0, 0.2, 0], [1.6, 1, 0, 1], [3.6, 1, 1, 0], [6.0, 0, 0.3, 0]], "drift": false},
		{"id": "linked", "car": "martello", "v": 70, "ph": [[1.0, 0, 0.3, 0], [1.4, -1, 0, 1], [2.4, -1, 1, 0], [2.8, 1, 0, 1], [3.8, 1, 1, 0], [6.0, 0, 0.3, 0]]},
		{"id": "lock110", "car": "kestrel", "v": 110, "ph": [[5.0, 1, -1, 0]]},
		{"id": "flick", "car": "kestrel", "v": 90, "ph": [[1.3, -1, 1, 0], [2.0, 1, 1, 0], [2.6, -1, 1, 0], [5.0, 0, 1, 0]]},
		{"id": "uturn", "car": "kestrel", "v": 30, "ph": [[1.0, 0, 0.0, 0], [1.6, 1, 0, 1], [4.0, 1, 0.6, 0]]},
		{"id": "uturn_off", "car": "kestrel", "v": 30, "ph": [[1.0, 0, 0.0, 0], [1.6, 1, 0, 1], [4.0, 1, 0.6, 0]], "drift": false},
	]
	_next()


func _next() -> void:
	if _i >= 0:
		_out[_cases[_i].id] = _r.duplicate()
		print("[drift]   %-12s max body slip %5.1f deg, most roll %4.1f deg, turned %4.0f deg, end %3.0f km/h" % [_cases[_i].id, _r.beta,
			_r.roll, absf(_r.turn), _r.kmh])
		car.queue_free()
	_i += 1
	_t = 0.0
	_r = {"beta": 0.0, "roll": 0.0, "turn": 0.0, "kmh": 0.0}
	if _i >= _cases.size():
		return
	var c: Dictionary = _cases[_i]
	car = RallyCar.new()
	car.grip_assist = 2.0                                 # ARCADE, out of the box
	car.setup = Catalog.setup(c.car, {}, {}, {"tyre": "tarmac", "preset": "tarmac"})
	root.add_child(car)
	car.place(Vector3.ZERO, 0.0)


func _physics_process(dt: float) -> bool:
	if _i >= _cases.size():
		return _finish()
	var c: Dictionary = _cases[_i]
	_t += dt
	if _t < 0.5:
		if c.has("drift") and car.assists:
			car.assists.drift_assist = c.drift
		car.place(Vector3.ZERO, 0.0)
		car.set_speed(c.v / 3.6)
		car.inp = {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": false}
		return false
	var p: Array = c.ph[-1]
	for ph in c.ph:
		if _t < ph[0]:
			p = ph
			break
	var thr := float(p[2])
	if thr < 0.0:                                         # (-1: hold the speed it started at)
		thr = clampf((c.v / 3.6 - car.speed) * 0.6, 0.0, 1.0)
	car.inp = {"steer": float(p[1]), "throttle": thr, "brake": 0.0, "handbrake": p[3] > 0}
	var v: Vector3 = car.linear_velocity
	var b: Basis = car.global_transform.basis
	if Vector2(v.x, v.z).length() > 4.0:
		_r.beta = maxf(_r.beta, absf(rad_to_deg(atan2(v.dot(b.x), v.dot(-b.z)))))
	_r.roll = maxf(_r.roll, absf(rad_to_deg(asin(clampf(b.x.y, -1.0, 1.0)))))
	_r.turn += rad_to_deg(car.angular_velocity.y) * dt
	_r.kmh = car.kmh()
	if _t > c.ph[-1][0]:
		_next()
	return false


func _finish() -> bool:
	var o := _out
	fails += _check(o.catch.roll < 15.0 and o.catch.kmh > 30.0,
		"a handbrake entry caught with full opposite lock and throttle: it stays on its wheels (most roll %.0f deg) and drives on at %.0f km/h" % [o.catch.roll, o.catch.kmh])
	fails += _check(o.lock110.roll < 15.0 and o.flick.roll < 15.0,
		"turning hard on the extra grip doesn't tip it over: full lock held at 110 km/h, most roll %.0f deg; a flick left-right-left at 90 on the throttle, %.0f deg (both rolled it before the tip guard)" % [
			o.lock110.roll, o.flick.roll])
	fails += _check(o.hairpin.beta < 50.0 and o.hairpin.kmh > 30.0 and (o.hairpin_off.beta > 60.0 or o.hairpin_off.kmh < 20.0),
		"rear drive, a handbrake hairpin held with full lock and throttle: drifts at up to %.0f deg and leaves at %.0f km/h (drift assist off: %.0f deg, %.0f km/h)" % [
			o.hairpin.beta, o.hairpin.kmh, o.hairpin_off.beta, o.hairpin_off.kmh])
	fails += _check(o.linked.beta < 50.0 and o.linked.kmh > 30.0,
		"rear drive, linked S-bends on the handbrake: no spin (%.0f deg at most, %.0f km/h)" % [o.linked.beta, o.linked.kmh])
	fails += _check(absf(o.uturn.turn) > 150.0 and absf(absf(o.uturn.turn) - absf(o.uturn_off.turn)) < 15.0,
		"slowly (30 km/h), a handbrake U-turn still swings it round: %.0f deg (drift assist off: %.0f)" % [absf(o.uturn.turn), absf(o.uturn_off.turn)])
	print("[drift] %s" % ("DRIFT OK" if fails == 0 else "DRIFT FAIL"))
	quit(1 if fails > 0 else 0)
	return true


func _check(ok: bool, msg: String) -> int:
	print("[drift] %s %s" % ["ok  " if ok else "FAIL", msg])
	return 0 if ok else 1
