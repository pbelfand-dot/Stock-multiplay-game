extends SceneTree
## The cars with models of their own (CarSpecs, assets/models/cars/), each on a
## flat gravel pad:
##   * it builds: its body, four wheels where its physics wheels are, its paint
##     (the livery shader on the "paint" surface), its own numbers (weight, engine)
##   * standing, it sits on its wheels: all four down, the model's tyres on the
##     ground (within 3 cm), the body clear of it
##   * flat out from a standstill: 0-100 km/h in a sane time for that car
##     (CHECKS: the real car's, give or take the game's tyres), the right wheels
##     driven (rear-drive: the fronts roll free; front-drive: the rears)
##   * the garage swaps it: a car built as the KESTREL becomes it (apply_setup):
##     its weight, wheelbase and body change, and back; the cars on the shared
##     body each weigh their own (the COMET 1,230 kg, the MARTELLO 960)
## Prints one [models] line per check; exits 1 on any FAIL.
## Run: godot --headless --fixed-fps 120 --path . -s tests/car_models_check.gd

## 0-100 km/h (s) each must beat on gravel, flat out from a standstill (the real
## car's on tarmac, give or take: these are on gravel, auto-shifting).
const CHECKS := {"nimbus": 11.0, "rotora_fc": 9.5, "kaiser": 8.0, "rotora_fd": 8.0, "vierrad": 6.5, "ocelot": 6.0,
	"hachi": 12.0, "sylph": 9.0, "sedici": 7.0}

var RallyCar
var Catalog
var car
var pad
var fails := 0
var ids: Array = []
var i := -1
var t := 0.0
var phase := ""
var t100 := -1.0
var res := {}
var front_spin := 0.0
var rear_spin := 0.0


func _initialize() -> void:
	RallyCar = load("res://scripts/vehicle/rally_car.gd")
	Catalog = load("res://scripts/game/catalog.gd")
	if not RallyCar.can_instantiate():
		print("[models] FAIL the car script doesn't compile")
		quit(1)
		return
	for c in Catalog.CARS:
		if str(c.get("model", "")) != "":
			ids.append(c.id)
	pad = StaticBody3D.new()
	pad.set_meta("surface", "gravel")
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(4000, 2, 4000)
	cs.shape = bx
	pad.add_child(cs)
	pad.position = Vector3(0, -1, 0)
	root.add_child(pad)
	_next()


func _next() -> void:
	if car:
		car.queue_free()
		car = null
	i += 1
	t = 0.0
	t100 = -1.0
	front_spin = 0.0
	rear_spin = 0.0
	if i >= ids.size():
		phase = "swap"
		return
	phase = "settle"
	car = RallyCar.new()
	car.setup = Catalog.setup(ids[i], {}, {}, {"tyre": "gravel", "preset": "gravel"})
	root.add_child(car)
	car.set_outside(true)
	car.place(Vector3.ZERO, 0.0)


func _physics_process(dt: float) -> bool:
	if phase == "done":
		return true
	if phase == "swap":
		_swap()
		return true
	t += dt
	var id: String = ids[i]
	if phase == "settle":
		car.inp = {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": false}   # (held, the brake would pick reverse)
		if t > 1.5:
			_standing(id)
			phase = "launch"
			t = 0.0
		return false
	car.inp = {"steer": 0.0, "throttle": 1.0, "brake": 0.0, "handbrake": false}
	if t < 2.0:
		for k in 2:
			front_spin += absf(car.wheels[k].omega * car.wheels[k].radius - car.speed)
			rear_spin += absf(car.wheels[k + 2].omega * car.wheels[k + 2].radius - car.speed)
	if t100 < 0.0 and car.kmh() >= 100.0:
		t100 = t
	if t > 14.0 or t100 > 0.0:
		var spec: Dictionary = car.CarSpecs.SPECS[car.model_id]
		var lim: float = CHECKS[id]
		fails += _check(t100 > 0.0 and t100 < lim, "%s: 0-100 km/h in %s (under %.1f s; %d kg, %d N m)" % [id,
			"%.1f s" % t100 if t100 > 0.0 else "never", lim, car.mass, spec.torque])
		var drive: String = spec.drive
		var ok := true
		if drive == "rwd":
			ok = rear_spin > front_spin * 4.0 + 1.0
		elif drive == "fwd":
			ok = front_spin > rear_spin * 4.0 + 1.0
		fails += _check(ok, "%s: %s, the wheels that slip pulling away (front %.0f, rear %.0f)" % [id, drive, front_spin, rear_spin])
		_next()
	return false


func _standing(id: String) -> void:
	var bm: Node3D = car.body_model
	var ok: bool = bm != null and car.model_id == car.setup.model and bm.get_node_or_null("Body") != null \
		and car._model_wheels.size() == 4
	var paint := false
	if ok:
		var body := bm.get_node("Body") as MeshInstance3D
		for s in body.mesh.get_surface_count():
			if body.get_surface_override_material(s) is ShaderMaterial:
				paint = true
	var spec: Dictionary = car.CarSpecs.SPECS[car.model_id] if car.CarSpecs.SPECS.has(car.model_id) else {}
	fails += _check(ok and paint and is_equal_approx(car.mass, float(spec.get("mass", -1.0))),
		"%s: built with its own body (%s), painted (%s), its own weight (%d kg)" % [id, car.model_id, paint, car.mass])
	if not ok:
		return
	var worst := 0.0
	var where := []
	for k in 4:
		var mw: Array = car._model_wheels[k]
		var r: float = car._model_info.radius[k]
		var bottom: float = (mw[0] as Node3D).global_position.y - r
		worst = maxf(worst, absf(bottom))
		where.append("%.3f" % bottom)
		var phys: Vector3 = car.wheels[k].global_position
		var off := Vector2((mw[0] as Node3D).global_position.x - phys.x, (mw[0] as Node3D).global_position.z - phys.z).length()
		worst = maxf(worst, off)
	fails += _check(car.grounded == 4 and worst < 0.03, "%s: sits on its wheels (all 4 down: %d; the model's tyres' bottoms %s m, worst off %.3f m)" % [
		id, car.grounded, ", ".join(where), worst])
	var aabb := AABB()
	var body := bm.get_node("Body") as MeshInstance3D
	aabb = body.global_transform * body.get_aabb()
	fails += _check(aabb.position.y > 0.0 and aabb.position.y < 0.4, "%s: the body clear of the ground (its lowest point %.2f m up)" % [id, aabb.position.y])


func _swap() -> void:
	phase = "done"
	car = RallyCar.new()
	car.setup = Catalog.setup("kestrel")
	root.add_child(car)
	car.place(Vector3.ZERO, 0.0)
	var m0: float = car.mass
	var wb0: float = car.config.rear_axle - car.config.front_axle
	var swapped: bool = car.apply_setup(Catalog.setup("rotora_fd"))
	var wb1: float = car.config.rear_axle - car.config.front_axle
	var ok: bool = swapped and car.model_id == "rx7_fd" and absf(car.mass - 1260.0) < 1.0 and absf(wb1 - 2.425) < 0.01 \
		and car.body_model != null and car.body_model.get_node_or_null("Body") != null
	fails += _check(ok, "the garage swaps the car: KESTREL (%d kg, %.2f m between the axles) -> ROTORA FD (%d kg, %.2f m, its own body)" % [m0, wb0, car.mass, wb1])
	var back: bool = car.apply_setup(Catalog.setup("kestrel"))
	fails += _check(back and car.model_id == "" and absf(car.mass - m0) < 1.0 and car.body_model != null,
		"... and back (%d kg, the Higgsfield body)" % car.mass)
	fails += _check(not car.apply_setup(Catalog.setup("comet")), "a car on the same body (the COMET) is a repaint, not a swap")
	fails += _check(absf(car.mass - 1230.0) < 1.0, "... at its own weight, a World Rally Car's 1,230 kg (%d kg)" % car.mass)
	car.apply_setup(Catalog.setup("martello"))
	var spring: float = car.config.front_suspension.spring_rate
	car.apply_setup(Catalog.setup("kestrel"))
	fails += _check(absf(car.mass - 1300.0) < 1.0 and spring < car.config.front_suspension.spring_rate * 0.8,
		"the MARTELLO 037 weighs a Group B car's 960 kg, its springs softer with it; the KESTREL an R4's 1,300 (%d kg)" % car.mass)
	print("[models] %s" % ("MODELS OK" if fails == 0 else "MODELS FAIL"))
	quit(1 if fails > 0 else 0)


func _check(ok: bool, msg: String) -> int:
	print("[models] %s %s" % ["ok  " if ok else "FAIL", msg])
	return 0 if ok else 1
