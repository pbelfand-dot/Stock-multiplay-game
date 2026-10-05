extends SceneTree
## The cockpit: the driver's gloves and the dials.
##   * the gloves cover the driver's sleeve ends, wherever the hands are (on the
##     wheel straight, turned hand over hand both ways, on the handbrake): every
##     vertex left of the forearm near the wrist is skinned on the CPU (as the
##     renderer does) and must be inside its gauntlet, and none may reach past
##     the wrist into the glove's hand (it would poke out of it)
##   * the bare hands are cut out of the body (not shrunk: that made spikes)
##   * the dials have their numbers (revs 0-8, km/h 0-200), the shift lights
##     come on with the revs
## Run: godot --headless --path . -s tests/cockpit_check.gd
## Prints [cockpit] lines; exits 1 on any FAIL.

var Cockpit
var DriverHands
var car
var cockpit
var fails := 0
var _states := [
	{"name": "straight", "steer": 0.0, "handbrake": false},
	{"name": "turned left", "steer": -0.3, "handbrake": false},
	{"name": "turned right", "steer": 0.3, "handbrake": false},
	{"name": "on the handbrake", "steer": 0.0, "handbrake": true},
]
var _i := -1
var _t := 0.0


func _initialize() -> void:
	Cockpit = load("res://scripts/vehicle/cockpit.gd")
	DriverHands = load("res://scripts/vehicle/driver_hands.gd")
	var st = load("res://scripts/stage/stage_gen.gd").new()
	st.generate(4)
	car = load("res://scripts/vehicle/rally_car.gd").new()
	root.add_child(car)
	car.freeze = true
	car.set_physics_process(false)                   # this test sets the steering, the revs
	cockpit = Cockpit.new()
	car.add_child(cockpit)
	cockpit.build(car, st)
	if not cockpit._models.has("driver"):
		fails += _check(false, "the driver model loaded")
		_i = _states.size()
		return
	var d = cockpit._models.driver
	fails += _check(d._hand_mesh != null and not d._hand_mesh.visible and _tris(d._hand_mesh) > 500,
		"the driver's bare hands are cut out of the body and hidden (%d triangles)" % (_tris(d._hand_mesh) if d._hand_mesh else 0))
	fails += _check(d.skel.get_bone_pose_scale(d._b.LeftHand).is_equal_approx(Vector3.ONE),
		"the hand bones aren't shrunk (that pulled the sleeves into spikes)")
	var cd = cockpit._models.get("codriver")
	fails += _check(cd != null and cd._hand_mesh == null, "the co-driver keeps their own hands")
	_dials()
	_next()


func _process(dt: float) -> bool:
	if _i >= _states.size():
		return _done()
	_t += dt
	if _t > 1.2:                                     # the wheel's turned, the hands have shuffled and settled
		_measure(_states[_i])
		_next()
	return false


func _next() -> void:
	_i += 1
	_t = 0.0
	if _i < _states.size():
		car.steer = _states[_i].steer
		car.inp = {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": _states[_i].handbrake}


## Skin the forearm verts near each wrist and check them against the gauntlets.
func _measure(state: Dictionary) -> void:
	var d = cockpit._models.driver
	var mi: MeshInstance3D = d._body
	var skin: Skin = mi.skin
	var sk: Skeleton3D = d.skel
	var bind_xf := []
	var bind_bone := []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = sk.find_bone(skin.get_bind_name(b))
		bind_bone.append(bone)
		bind_xf.append(mi.global_transform * sk.get_bone_global_pose(bone) * skin.get_bind_pose(b))
	var arr := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bw = arr[Mesh.ARRAY_BONES]
	var ww = arr[Mesh.ARRAY_WEIGHTS]
	var per := int(bw.size() / verts.size())
	var used := {}
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for i in idx:
		used[i] = true                               # only verts the body still draws
	for k in 2:
		var fore: int = d._b["LeftForeArm" if k == 0 else "RightForeArm"]
		var cuff: Transform3D = (cockpit.hands._cuffs[k] as Node3D).global_transform.affine_inverse()
		var lo := INF                                # the nearest a vert gets to the wrist, along the forearm (m)
		var out := -INF                              # the furthest a vert inside the gauntlet's length sticks out of it (m)
		var n := 0
		for v in used:
			var wf := 0.0
			var p := Vector3.ZERO
			for j in per:
				var w: float = ww[v * per + j]
				if w <= 0.0:
					continue
				var b: int = bw[v * per + j]
				p += (bind_xf[b] * verts[v]) * w
				if bind_bone[b] == fore:
					wf += w
			if wf < 0.3:
				continue
			var q := cuff * p
			if q.y > 0.12 or Vector2(q.x, q.z).length() > 0.15:
				continue                             # up the arm, nowhere near the glove
			n += 1
			lo = minf(lo, q.y)
			if q.y >= 0.0 and q.y <= DriverHands.CUFF[-2][0]:
				out = maxf(out, Vector2(q.x, q.z).length() - DriverHands._cuff_r(q.y))
		var side := "left" if k == 0 else "right"
		fails += _check(n > 20 and lo > 0.0, "%s: the %s sleeve stops %.1f cm short of the wrist (%d verts near it)" % [
			state.name, side, lo * 100.0, n])
		fails += _check(out < 0.0, "%s: the %s sleeve's end is inside the gauntlet (%.1f cm %s)" % [
			state.name, side, absf(out) * 100.0, "to spare" if out < 0.0 else "sticking out"])


## The dials' numbers and the shift lights.
func _dials() -> void:
	var texts := []
	for l in cockpit.find_children("*", "Label3D", true, false):
		texts.append(l.text)
	var rpm_ok := true
	for i in 9:
		rpm_ok = rpm_ok and str(i) in texts
	fails += _check(rpm_ok, "the rev counter is numbered 0-8")
	var kmh_ok := true
	for v in [50, 100, 150, 200]:
		kmh_ok = kmh_ok and str(v) in texts
	fails += _check(kmh_ok, "the speedo is numbered 0-200")
	fails += _check("x1000 RPM" in texts and "KM/H" in texts, "the dials say what they show")


func _lights(rpm: float) -> int:
	car.rpm = rpm
	cockpit._process(0.016)
	var lit := 0
	for m in cockpit._shift_leds:
		lit += 1 if m.emission_energy_multiplier > 0.0 else 0
	return lit


func _check(ok: bool, msg: String) -> int:
	print("[cockpit] %s %s" % ["ok  " if ok else "FAIL", msg])
	return 0 if ok else 1


func _tris(m: MeshInstance3D) -> int:
	var t := 0
	for s in m.mesh.get_surface_count():
		t += m.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	return t


func _done() -> bool:
	var idle := _lights(0.0)
	var high := _lights(0.85)                        # 0.18 + 0.85 * 0.82 = 0.877 of the dial: ~7000 rpm
	fails += _check(idle == 0 and high == 4, "shift lights: none at idle, 4 of 5 near the red line (%d, %d)" % [idle, high])
	print("[cockpit] %s" % ("COCKPIT OK" if fails == 0 else "COCKPIT FAIL"))
	quit(1 if fails > 0 else 0)
	return true
