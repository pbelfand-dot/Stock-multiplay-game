extends SceneTree
## The drift dirt (scripts/vehicle/drift_fx.gd) on a flat gravel pad:
##   * rolling straight and slow: nothing
##   * a handbrake slide: dust and stones, mostly off the rear tyres
##   * flat out in a straight line: a light dust trail, no stones
##   * in the air: nothing new
##   * landing a jump: a burst of dust and stones
## Run: godot --headless --fixed-fps 120 --path . -s tests/fx_check.gd
## Prints one [fx] line per check; exits 1 on any FAIL.

var RallyCar
var DriftFx
var car
var fx
var fails := 0
var _steps := ["slow", "handbrake", "fast", "air", "land"]
var _step := -1
var _t := 0.0
var _spawned := {}


func _initialize() -> void:
	RallyCar = load("res://scripts/vehicle/rally_car.gd")
	DriftFx = load("res://scripts/vehicle/drift_fx.gd")
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
	fx = DriftFx.new()
	fx.car = car
	car.add_child(fx)
	_next()


func _next() -> void:
	_step += 1
	_t = 0.0
	_spawned = {"puffs": 0, "stones": 0, "rear": 0.0, "front": 0.0, "n": 0, "p0": fx.puffs_made, "s0": fx.stones_made}
	if _step >= _steps.size():
		return
	car.place(Vector3.ZERO, 0.0)
	car.inp = {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": false}


func _physics_process(dt: float) -> bool:
	if _step >= _steps.size():
		return _finish()
	_t += dt
	match _steps[_step]:
		"slow":
			if _t < 0.05:
				car.linear_velocity = Vector3(0, 0, -8.0)
			car.inp = {"steer": 0.0, "throttle": 0.12, "brake": 0.0, "handbrake": false}
		"handbrake":
			if _t < 0.05:
				car.linear_velocity = Vector3(0, 0, -50.0 / 3.6)
			car.inp = {"steer": 1.0, "throttle": 0.0, "brake": 0.0, "handbrake": true}
		"fast":
			if _t < 0.05:
				car.linear_velocity = Vector3(0, 0, -30.0)
			car.inp = {"steer": 0.0, "throttle": 1.0, "brake": 0.0, "handbrake": false}
		"air":
			if _t < 0.05:
				car.place(Vector3(0, 30, 0), 0.0)
				car.linear_velocity = Vector3(0, 0, -20.0)
		"land":
			if _t < 0.05:
				car.place(Vector3(0, 1.5, 0), 0.0)
			if _t < 0.5:                                 # held up in the air, then dropped at 10 m/s
				car.global_position.y = 1.5 + 0.6
				car.linear_velocity = Vector3(0, 0, -10.0)
	if _t <= 0.5:                                        # settling: count from here on
		_spawned.p0 = fx.puffs_made
		_spawned.s0 = fx.stones_made
	else:
		_spawned.puffs = fx.puffs_made - _spawned.p0
		_spawned.stones = fx.stones_made - _spawned.s0
		_spawned.rear += (fx.intensity[2] + fx.intensity[3]) * 0.5
		_spawned.front += (fx.intensity[0] + fx.intensity[1]) * 0.5
		_spawned.n += 1
	if _t > 1.6:
		_report(_steps[_step])
		_next()
	return false


func _report(kind: String) -> void:
	var n := maxf(_spawned.n, 1)
	var rear: float = _spawned.rear / n
	var front: float = _spawned.front / n
	var msg := "%s: %d puffs, %d stones in 1.1 s, rear tyres %.2f, front %.2f (%.0f km/h)" % [
		kind, _spawned.puffs, _spawned.stones, rear, front, car.kmh()]
	match kind:
		"slow":
			fails += _check(_spawned.puffs == 0 and _spawned.stones == 0, msg + " -> nothing")
		"handbrake":
			fails += _check(_spawned.puffs > 15 and _spawned.stones > 25 and rear > 0.6 and rear >= front, msg + " -> lots, mostly the rears")
		"fast":
			fails += _check(_spawned.puffs > 0 and _spawned.stones == 0, msg + " -> a light trail, no stones")
		"air":
			fails += _check(_spawned.puffs == 0 and _spawned.stones == 0, msg + " -> nothing")
		"land":
			fails += _check(_spawned.puffs >= 12 and _spawned.stones >= 16, msg + " -> a burst on landing")


func _check(ok: bool, msg: String) -> int:
	print("[fx] %s %s" % ["ok  " if ok else "FAIL", msg])
	return 0 if ok else 1


func _finish() -> bool:
	print("[fx] %s" % ("FX OK" if fails == 0 else "FX FAIL"))
	quit(1 if fails > 0 else 0)
	return true
