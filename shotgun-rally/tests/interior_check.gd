extends SceneTree
## The cars whose models have an interior of their own (parts.json "cockpit":
## tools/import_car.py): the crew adapt to it, it isn't replaced.
##   * the cockpit builds none of its own (no shell, dash, seats or wheel) and the
##     car's body is drawn from inside
##   * the driver's eyes are in the car (inside its body, on the side of its
##     steering wheel: a right-hand-drive car's on the right) and the co-driver's
##     on the other side
##   * the gloves grip its own wheel's rim (in its plane, on its radius); turning
##     the steering turns its wheel about its own axis
##   * an H-pattern box: at a change, the hand nearer the middle (the left one in
##     a right-hand-drive car) goes to its own gear knob and takes it through the
##     gate to the next gear (2nd: back and to the left), leaves it there and goes
##     back to the wheel. A sequential: pulled back, it springs back. An
##     automatic, or no lever modelled: the hand stays on the wheel
##   * the handbrake: that hand goes to its own lever and pulls it
##   * a car without one keeps the cockpit's own interior; a model with no cabin at all
##     (parts.json "view": "hood") gets none made up: the camera sits low over its bonnet, in
##     front of its windscreen, and its body is drawn
##   * the gloves never float: round the wheel both ways, on the handbrake and
##     reaching for the gear lever, each forearm ends at its glove's wrist (a
##     wheel out of reach: the driver slides their seat forward, the forearm
##     stretches the rest, not much), in every car, ours too
## Prints one [interior] line per check; exits 1 on any FAIL.
## Run: godot --headless --path . -s tests/interior_check.gd

const DT := 1.0 / 60.0

var RallyCar
var Catalog
var Cockpit
var CarSpecs
var st
var fails := 0


func _initialize() -> void:
	RallyCar = load("res://scripts/vehicle/rally_car.gd")
	Catalog = load("res://scripts/game/catalog.gd")
	Cockpit = load("res://scripts/vehicle/cockpit.gd")
	CarSpecs = load("res://scripts/vehicle/car_specs.gd")
	st = load("res://scripts/stage/stage_gen.gd").new()
	st.generate(4)


var _done := false


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true                                     # (in the first frame: a car added in _initialize isn't ready yet)
	var own := 0
	var ours := 0
	var hood := 0
	for c in Catalog.CARS:
		var model := str(c.get("model", ""))
		if model == "":
			continue
		var info: Dictionary = CarSpecs.parts(model)
		if info.has("cockpit"):
			own += 1
			_own(c.id, info.cockpit)
		elif str(info.get("view", "")) == "hood":
			hood += 1
			_hood(c.id)
		else:
			ours += 1
			_ours(c.id)
	fails += _check(own >= 5, "%d cars keep their own interior, %d from over the bonnet (no cabin), %d the cockpit's" % [own, hood, ours])
	# (the bonnet-view cars have no crew in sight: no cabin to sit them in)
	var seen: Array = Catalog.CARS.filter(func(c): return str(c.get("model", "")) != "" and str(CarSpecs.parts(str(c.model)).get("view", "")) != "hood")
	for id in ["kestrel"] + Array(seen.map(func(c): return c.id)):
		_reach(id)
	# the driver-fit anchors (fit_debug.gd, the F9 overlay's) in every car: head under the roof, the
	# wheel in front of the eyes, the hands in reach, the pedals ahead of and below the seat, the door outside
	var FitDebug = load("res://scripts/vehicle/fit_debug.gd")
	var why: Array = []
	var fitted := 0
	for c in Catalog.CARS:
		if str(CarSpecs.parts(str(c.get("model", ""))).get("view", "")) == "hood":
			continue
		fitted += 1
		var made: Array = _car(c.id)
		var j: Array = FitDebug.judge(FitDebug.fit(made[0], made[1]), made[0])
		if not j[0]:
			why.append("%s: %s" % [c.id, j[1]])
		made[0].queue_free()
	fails += _check(why.is_empty(), "driver fit: head, seat, hands, pedals and door anchors sane in %d of %d cars (the bonnet-view ones have no seat)%s" % [
		fitted - why.size(), fitted, "" if why.is_empty() else " (" + " | ".join(why) + ")"])
	print("[interior] %s" % ("INTERIOR OK" if fails == 0 else "INTERIOR FAIL"))
	quit(1 if fails > 0 else 0)
	return true


func _car(id: String):
	var car = RallyCar.new()
	car.setup = Catalog.setup(id)
	root.add_child(car)
	car.freeze = true
	car.set_physics_process(false)                   # this test sets the steering, the gear
	var cp = Cockpit.new()
	car.add_child(cp)
	cp.build(car, st)
	cp.set_process(false)
	car.inp = {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": false}
	car.steer = 0.0
	car.gear = 1
	return [car, cp]


func _run(cp, seconds: float) -> void:
	for f in roundi(seconds / DT):
		cp._process(DT)


func _own(id: String, ck: Dictionary) -> void:
	var made: Array = _car(id)
	var car = made[0]
	var cp = made[1]
	var h = cp.hands
	car.set_outside(false)
	fails += _check(cp.own_interior() and cp._steer_node == null and cp._needles.is_empty() and car.body_model.visible
		and car.cockpit_nodes.has("wheel"),
		"%s: its own interior (%s-hand drive, %s): none of ours built, its body drawn from inside" % [id, ck.side, ck.gearbox])
	# the eyes: in the body, on the steering wheel's side; the co-driver across
	var off: Vector3 = car.model_offset()
	var eye: Vector3 = cp.eye_driver - off
	var lo := Vector3(car._model_info.body_min[0], car._model_info.body_min[1], car._model_info.body_min[2])
	var hi := Vector3(car._model_info.body_max[0], car._model_info.body_max[1], car._model_info.body_max[2])
	var inside: bool = eye.x > lo.x + 0.2 and eye.x < hi.x - 0.2 and eye.y > lo.y + 0.5 and eye.y < hi.y - 0.1 and eye.z > lo.z + 1.0 and eye.z < hi.z - 1.0
	var sx := 1.0 if ck.side == "right" else -1.0
	if int(ck.get("seats", 2)) == 1:
		# a single-seater: the driver in the middle, behind a wheel in the middle; no co-driver
		fails += _check(inside and absf(eye.x) < 0.05 and absf(cp.wheel_c.x - off.x) < 0.05 and cp.solo,
			"%s: a single-seater, the driver's eyes in the car, in the middle like its wheel (%.2f, %.2f, %.2f m), no co-driver" % [
			id, eye.x, eye.y, eye.z])
	else:
		fails += _check(inside and signf(eye.x) == sx and signf(cp.eye_codriver.x) == -sx and signf(cp.wheel_c.x) == sx,
			"%s: the driver's eyes in the car, %s of the middle like its wheel (%.2f, %.2f, %.2f m), the co-driver's across" % [
			id, ck.side, eye.x, eye.y, eye.z])
	# the gloves on its rim
	_run(cp, 0.5)
	var axis: Vector3 = cp._wheel_axis
	var worst := 0.0
	for k in 2:
		var rel: Vector3 = (h._gloves[k] as Node3D).transform.origin - cp.wheel_c
		var along := rel.dot(axis)
		worst = maxf(worst, maxf(absf(along), absf((rel - axis * along).length() - cp.wheel_r)))
	fails += _check(worst < 0.03, "%s: both gloves on its rim (r %.0f mm; off it by %.1f cm at most)" % [id, cp.wheel_r * 1000.0, worst * 100.0])
	# steering turns its wheel about its axis
	car.steer = 0.06
	_run(cp, 0.6)
	var wn: Node3D = car.cockpit_nodes.wheel
	var ref := axis.cross(Vector3.RIGHT).normalized()
	var turned: Vector3 = wn.basis * ref
	var ang := ref.signed_angle_to(turned, axis)
	fails += _check(absf(cp._wheel_turn) > 0.5 and absf(ang + cp._wheel_turn) < 0.02 and absf(wn.basis.get_rotation_quaternion().get_axis().dot(axis)) > 0.99,
		"%s: steering turns its own wheel (%.0f deg about its column, clockwise for right)" % [id, rad_to_deg(-ang)])
	car.steer = 0.0
	_run(cp, 1.0)
	# the hand that shifts and pulls the handbrake: the one nearer the middle
	var k := 0 if ck.side == "right" else 1
	fails += _check(h.shift_hand == k, "%s: the %s hand works the gears and the handbrake" % [id, "left" if k == 0 else "right"])
	var kind: String = h.gear_kind
	var lever = car.cockpit_nodes.get("shifter")
	car.gear = 2
	if kind in ["h4", "h5", "h6"]:
		var knob0: Vector3 = h._gear.transform * Vector3(0.0, h._gear_len, 0.0)
		_run(cp, 0.2)
		var on_knob: bool = (h._gloves[k] as Node3D).transform.origin.distance_to(h._gear_grip().origin) < 0.02
		_run(cp, 0.6)
		var knob1: Vector3 = h._gear.transform * Vector3(0.0, h._gear_len, 0.0)
		var moved: Vector3 = knob1 - knob0               # 1st (forward, left) -> 2nd (back, left)
		var l: float = h._gear_len                     # (how far the knob goes: as long as the lever is)
		fails += _check(on_knob and h._hand[k].mode == "grip" and h._gate.is_equal_approx(h._h_gate(2))
			and moved.z > 0.25 * l and absf(moved.x) < 0.01 and lever != null and not lever.basis.is_equal_approx(Basis()),
			"%s: changing up, the hand takes its own knob from 1st back to 2nd (%.0f cm) and goes back to the wheel" % [id, moved.z * 100.0])
		car.gear = 3
		_run(cp, 0.8)
		var knob3: Vector3 = h._gear.transform * Vector3(0.0, h._gear_len, 0.0)
		fails += _check(h._gate.is_equal_approx(h._h_gate(3)) and knob3.z < knob1.z - 0.25 * l and knob3.x > knob1.x + 0.1 * l,
			"%s: ... and through the gate to 3rd (forward, across to the %s)" % [id, "right" if kind == "h4" else "middle"])
	elif kind == "seq_model":
		_run(cp, 0.17)
		var pulled: float = h._gear_kick
		_run(cp, 0.6)
		fails += _check(pulled > 0.5 and absf(h._gear_kick) < 0.01 and h._hand[k].mode == "grip",
			"%s: its sequential lever pulled back for 2nd, springing back after" % id)
	else:
		_run(cp, 0.2)
		fails += _check(h._hand[0].mode == "grip" and h._hand[1].mode == "grip",
			"%s: no gear lever to work (%s): both hands stay on the wheel" % [id, "an automatic" if ck.gearbox == "auto" else "none modelled"])
	# the handbrake
	var hb = car.cockpit_nodes.get("handbrake")
	if hb:
		var grip0: Vector3 = h._lever_grip().origin
		car.inp.handbrake = true
		_run(cp, 0.4)
		var grip1: Vector3 = h._lever_grip().origin
		var on_it: bool = (h._gloves[k] as Node3D).transform.origin.distance_to(grip1) < 0.02
		fails += _check(h._hand[k].mode == "brake" and on_it and (grip1.y > grip0.y + 0.03 or grip1.z > grip0.z + 0.05)
			and not hb.basis.is_equal_approx(Basis()),
			"%s: the handbrake: the hand on its own lever, pulled (the grip %.0f cm up, %.0f back)" % [
			id, (grip1.y - grip0.y) * 100.0, (grip1.z - grip0.z) * 100.0])
		car.inp.handbrake = false
	car.queue_free()


## The gap between each forearm's end and its glove's wrist: steering one way to
## the other (hand over hand), the handbrake, a gear change, at 60 fps.
func _reach(id: String) -> void:
	var made: Array = _car(id)
	var car = made[0]
	var cp = made[1]
	var m = cp._models.get("driver")
	if m == null:
		fails += _check(false, "%s: the driver model loaded" % id)
		car.queue_free()
		return
	var worst := 0.0
	var where := ""
	var most := 1.0
	var states := []
	for i in 15:
		states.append(["steering %+.2f" % (-0.35 + i * 0.05), -0.35 + i * 0.05, false, 1, 0.6])
	states.append(["the handbrake", 0.0, true, 1, 0.6])
	states.append(["changing gear", 0.0, false, 2, 0.6])
	for st_ in states:
		car.steer = st_[1]
		car.inp.handbrake = st_[2]
		car.gear = st_[3]
		for f in roundi(st_[4] / DT):
			cp._process(DT)
			for k in 2:
				var g: float = m.bone("LeftHand" if k == 0 else "RightHand").distance_to(cp.hands.wrists[k])
				most = maxf(most, m.stretch[k])
				if g > worst:
					worst = g
					where = "%s, %s hand" % [st_[0], "left" if k == 0 else "right"]
	fails += _check(worst < 0.015 and most < 1.6,
		"%s: the gloves stay on the sleeves (the worst gap %.1f cm: %s; forearms stretched x%.2f at most)" % [id, worst * 100.0, where, most])
	car.queue_free()


func _ours(id: String) -> void:
	var made: Array = _car(id)
	var car = made[0]
	var cp = made[1]
	fails += _check(not cp.own_interior() and cp._steer_node != null and cp.eye_driver == Cockpit.EYE_DRIVER,
		"%s: no interior good enough of its own: the cockpit's" % id)
	car.queue_free()


## A model with no cabin: nothing made up (no shell, dash or wheel of ours), the body drawn in the
## driver's view, the eyes on the middle line over the bonnet: above the belt, in the front half,
## ahead of the windscreen's foot.
func _hood(id: String) -> void:
	var made: Array = _car(id)
	var car = made[0]
	var cp = made[1]
	car.set_outside(false)
	var eye: Vector3 = cp.eye_driver - car.model_offset()
	var info: Dictionary = car._model_info
	var mid := (float(info.body_min[2]) + float(info.body_max[2])) * 0.5
	var ok: bool = cp.hood and not cp.own_interior() and cp._steer_node == null and cp._needles.is_empty() and car.body_model.visible \
		and absf(eye.x) < 0.01 and eye.y > float(info.belt) and eye.y < float(info.body_max[1]) and eye.z < mid - 0.3 and eye.z > float(info.body_min[2]) + 0.5
	fails += _check(ok, "%s: no cabin in its model: none made up, its body seen from over the bonnet (eye at %s, the belt at %.2f)" % [id, str(eye), float(info.belt)])
	car.queue_free()


func _check(ok: bool, msg: String) -> int:
	print("[interior] %s %s" % ["ok  " if ok else "FAIL", msg])
	return 0 if ok else 1
