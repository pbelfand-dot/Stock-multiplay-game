extends SceneTree
## The garage's SETUP tab, in numbers: the tyres and the setup on a flat pad.
##   * cornering flat out at 80 km/h on asphalt and on gravel, with gravel tyres
##     and with tarmac tyres: tarmac tyres corner harder on asphalt and much
##     worse on gravel; gravel tyres are the better bet on gravel
##   * the tarmac setup rolls less in the same corner, and stands at the same height
##   * AUTO picks tarmac on a tarmac stage, gravel on a gravel one; a choice sticks
## Run: godot --headless --fixed-fps 120 --path . -s tests/tuning_check.gd

var RallyCar
var Catalog
var StageGen
var car
var pad
var fails := 0
var _cases: Array = []
var _i := -1
var _t := 0.0
var _acc := {}
var _res := {}


func _initialize() -> void:
	RallyCar = load("res://scripts/vehicle/rally_car.gd")
	Catalog = load("res://scripts/game/catalog.gd")
	StageGen = load("res://scripts/stage/stage_gen.gd")
	for surf in ["asphalt", "gravel"]:
		for tyre in ["gravel", "tarmac"]:
			_cases.append({"surface": surf, "tyre": tyre, "preset": "gravel"})
	_cases.append({"surface": "asphalt", "tyre": "tarmac", "preset": "tarmac"})
	_next()


func _next() -> void:
	_i += 1
	_t = 0.0
	_acc = {"n": 0, "lat": 0.0, "roll": 0.0}
	if car:
		car.queue_free()
		pad.queue_free()
	if _i >= _cases.size():
		return
	var c: Dictionary = _cases[_i]
	pad = StaticBody3D.new()
	pad.set_meta("surface", c.surface)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(4000, 2, 4000)
	cs.shape = bx
	pad.add_child(cs)
	pad.position = Vector3(0, -1, 0)
	root.add_child(pad)
	car = RallyCar.new()
	car.setup = {"tyre": c.tyre, "preset": c.preset}
	root.add_child(car)
	car.place(Vector3.ZERO, 0.0)


func _physics_process(dt: float) -> bool:
	if _i >= _cases.size():
		return _finish()
	var c: Dictionary = _cases[_i]
	_t += dt
	if _t < 0.6:
		if _t <= dt * 1.5:
			c["ride"] = car.ride_height()
		car.place(Vector3.ZERO, 0.0)
		car.set_speed(80.0 / 3.6)
		car.inp = {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": false}
		return false
	var spd: float = car.speed
	var thr := clampf((80.0 / 3.6 - spd) * 0.6, 0.0, 1.0)
	car.inp = {"steer": 1.0, "throttle": thr, "brake": 0.0, "handbrake": false}
	if _t > 4.0:
		_acc.n += 1
		_acc.lat += absf(car.angular_velocity.y) * car.linear_velocity.length() / 9.81
		_acc.roll += absf(rad_to_deg(asin(clampf(car.global_transform.basis.x.y, -1.0, 1.0))))
	if _t > 7.0:
		c["lat"] = _acc.lat / maxf(_acc.n, 1)
		c["roll"] = _acc.roll / maxf(_acc.n, 1)
		c["kinds"] = "%s/%s" % [car.tyre_kind, car.setup_kind]
		print("[tuning]   %-7s %s tyres, %s setup: %.2f g, %.1f deg of roll (car says %s), stands %.3f m" % [c.surface, c.tyre, c.preset,
			c.lat, c.roll, c.kinds, c.ride])
		_res["%s %s %s" % [c.surface, c.tyre, c.preset]] = c
		_next()
	return false


func _finish() -> bool:
	var ag: Dictionary = _res["asphalt gravel gravel"]
	var at: Dictionary = _res["asphalt tarmac gravel"]
	var gg: Dictionary = _res["gravel gravel gravel"]
	var gt: Dictionary = _res["gravel tarmac gravel"]
	var att: Dictionary = _res["asphalt tarmac tarmac"]
	fails += _check(at.lat > ag.lat * 1.04, "on asphalt the tarmac tyres corner harder: %.2f g vs %.2f" % [at.lat, ag.lat])
	fails += _check(gt.lat < gg.lat * 0.88, "on gravel they're much worse: %.2f g vs %.2f on gravel tyres" % [gt.lat, gg.lat])
	fails += _check(att.roll < at.roll * 0.85, "the tarmac setup rolls less: %.1f deg vs %.1f" % [att.roll, at.roll])
	fails += _check(absf(att.ride - at.ride) < 0.005, "... and stands at the same height (%.3f m vs %.3f)" % [att.ride, at.ride])
	fails += _check(att.kinds == "tarmac/tarmac" and ag.kinds == "gravel/gravel", "the car took the tyres and setup it was given")
	# AUTO, and a choice that sticks
	var tarmac = StageGen.new()
	tarmac.opts = {"surface": "tarmac"}
	tarmac.generate(3)
	var gravel = StageGen.new()
	gravel.generate(3)
	var auto: Dictionary = Catalog.setup("kestrel")
	var a1: Dictionary = Catalog.for_stage(auto, tarmac)
	var a2: Dictionary = Catalog.for_stage(auto, gravel)
	var fixed: Dictionary = Catalog.for_stage(Catalog.setup("kestrel", {}, {}, {"tyre": "gravel", "preset": "tarmac"}), tarmac)
	fails += _check(auto.tyre == "auto" and a1.tyre == "tarmac" and a1.preset == "tarmac" and a2.tyre == "gravel" and a2.preset == "gravel",
		"AUTO: tarmac tyres and setup on a tarmac stage, gravel on a gravel one")
	fails += _check(fixed.tyre == "gravel" and fixed.preset == "tarmac", "a choice in the garage sticks whatever the stage")
	print("[tuning] %s" % ("TUNING OK" if fails == 0 else "TUNING FAIL"))
	quit(1 if fails > 0 else 0)
	return true


func _check(ok: bool, msg: String) -> int:
	print("[tuning] %s %s" % ["ok  " if ok else "FAIL", msg])
	return 0 if ok else 1
