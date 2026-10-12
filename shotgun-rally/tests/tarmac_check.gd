extends SceneTree
## The owner's three tarmac complaints, measured the way they were reported, with the game's
## out-of-the-box settings (SIM street handling in cut up, the default driver aids, the car's
## factory ABS / traction control / stability control; Track Mode's cold mediums and the GT3
## car's own ABS and TC levels), on a flat asphalt pad:
##   * ACCELERATION: the M5 (KAISER 5 G, the G90) from a standstill and rolling, flat out:
##     0-60 mph and 0-100 km/h, 60-100 mph from a 60 mph cruise in the gear the box holds there,
##     100-200 km/h, against the real car's figures (BMW: 0-100 km/h 3.5 s, 0-200 km/h 10.9 s;
##     Car and Driver: 0-60 mph 3.0 s with a 1-ft rollout; MotorWeek 3.1 s and a 129 mph
##     quarter mile; FastestLaps 100-200 km/h 6.4 s; 60-100 mph ~3.7-4.2 s from those)
##   * a GT3 car's STANDING LAUNCH in Track Mode on keys: parked on the grid's handbrake, then
##     the throttle flat with NO steering (a 1.7 deg/s nudge of yaw, as a bump or the camber
##     gives): it goes straight, and 0-100 km/h in a GT3's ~3.5 s. And on the throttle at
##     80 km/h a 0.2 / 0.4 s tap of a key doesn't spin it (it used to: 116 deg on a 0.2 s tap)
##   * a HIGHWAY LANE CHANGE at 200 km/h (the M5, cut up), on keys (right 0.45 s, left 0.45 s)
##     and a stick (one sine): no tyre smoke, no tyre marks, the tyres well inside their grip,
##     the body slip under 1.5 deg, stability control never braking; and the keys at 200 km/h:
##     a 0.3 s tap is a calm move (under 0.3 g), a key held 2 s a hard turn (over 0.75 g) with
##     the front tyres short of their peak and the road wheels under 2 deg (they swung to
##     7.7 deg and ploughed on, smoking)
##   * the AUTOMATIC on part throttle (the M5, cut up): gently on the throttle up to a 100 km/h
##     cruise it's in one of its top two gears under 3,000 rpm (it held each gear to 6,850 rpm
##     whatever the throttle, cruising at 4,000-5,000), floored from there it kicks down three
##     gears or more in one change; and on keys a 1.5 s lift after a pull doesn't change up
## Run: godot --headless --fixed-fps 120 --path . -s tests/tarmac_check.gd
## Prints one [tarmac] line per check; exits 1 on any FAIL.

const MPH := 1.609344

var RallyCar
var Catalog
var Modes
var DriftFx
var SkidMarks
var car
var fx
var marks
var cases: Array = []
var ci := -1
var c: Dictionary
var t := 0.0
var m := {}
var fails := 0
var _prev_v := Vector3.ZERO
var _x0 := Vector3.ZERO
var _yaw0 := 0.0


class FakeStage:
	var kind := "highway"
	var length := 100.0
	var sections := [{"s0": 0.0, "s1": 100.0, "surface": "asphalt"}]


func _initialize() -> void:
	RallyCar = load("res://scripts/vehicle/rally_car.gd")
	Catalog = load("res://scripts/game/catalog.gd")
	Modes = load("res://scripts/game/modes.gd")
	DriftFx = load("res://scripts/vehicle/drift_fx.gd")
	SkidMarks = load("res://scripts/vehicle/skid_marks.gd")
	if RallyCar == null or not RallyCar.can_instantiate():
		print("[tarmac] FAIL the car's script doesn't compile")
		quit(1)
		return
	var cfg = root.get_node_or_null("Config")
	_check(cfg != null and cfg.street_handling == "sim" and not bool(cfg.aids.traction_control) and bool(cfg.aids.speed_sensitive_steering),
		"out of the box: STREET HANDLING SIM, the default aids (the cars' factory traction control is their own)")
	var pad := StaticBody3D.new()
	pad.set_meta("surface", "asphalt")
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(20000, 2, 20000)
	cs.shape = bx
	pad.add_child(cs)
	pad.position = Vector3(0, -1, 0)
	root.add_child(pad)
	cases = [
		{"k": "standing", "car": "kaiser_5g"},
		{"k": "roll", "car": "kaiser_5g", "from": 60.0 * MPH, "to": 100.0 * MPH, "n": "60-100 mph", "lo": 3.2, "hi": 4.6},
		{"k": "roll", "car": "kaiser_5g", "from": 100.0, "to": 200.0, "n": "100-200 km/h", "lo": 6.0, "hi": 8.0},
	]
	for id in ["affalter", "elfer_r", "kaiser4_gt3"]:
		cases.append({"k": "launch", "car": id, "track": true})
	for id in ["affalter", "elfer_r"]:
		for hold in [0.2, 0.4]:
			cases.append({"k": "powertap", "car": id, "track": true, "v": 80.0, "hold": hold})
	for dev in ["kb", "pad"]:
		cases.append({"k": "lane", "car": "kaiser_5g", "v": 200.0, "dev": dev})
	for hold in [0.3, 2.0]:
		cases.append({"k": "key", "car": "kaiser_5g", "v": 200.0, "hold": hold})
	cases.append({"k": "cruise", "car": "kaiser_5g"})
	cases.append({"k": "lift", "car": "kaiser_5g"})
	_next()


func _make_car() -> void:
	car = RallyCar.new()
	var st := FakeStage.new()
	if c.get("track", false):
		st.kind = "circuit"
		var s: Dictionary = Catalog.for_stage(Catalog.setup(c.car, {}, {}, {"tyre": "auto", "preset": "auto"}), st)
		s["race_sim"] = true
		s["race"] = Modes.race_opts({"class": "gt", "session": "practice"})
		car.setup = s
	else:
		car.setup = Catalog.for_stage(Catalog.setup(c.car), st)     # (cut up: the highway, SIM street)
	root.add_child(car)
	car.place(Vector3.ZERO, 0.0)
	fx = DriftFx.new()
	fx.car = car
	root.add_child(fx)
	marks = SkidMarks.new()
	marks.car = car
	marks.fx = fx
	root.add_child(marks)


func _next() -> void:
	if ci >= 0:
		_report()
		car.queue_free()
		fx.queue_free()
		marks.queue_free()
	ci += 1
	if ci >= cases.size():
		print("[tarmac] %s" % ("TARMAC OK" if fails == 0 else "TARMAC FAIL"))
		quit(1 if fails > 0 else 0)
		return
	c = cases[ci]
	t = 0.0
	m = {}
	_make_car()


## In the gear the automatic holds at v cruising (the highest-revving one under its upshift).
func _gear_for(v: float) -> void:
	var d = car.drivetrain
	var w: float = v / car.wheels[2].radius
	var g := 1
	while g < d.gears() and w * d.ratio_for(g) * 60.0 / TAU > d.cfg.upshift_rpm - 400.0:
		g += 1
	d.gear = g
	d._next_gear = g
	d.omega_e = w * d.ratio_for(g)
	d.clutch = 1.0


func _roll_start(v0: float) -> void:
	car.place(Vector3.ZERO, 0.0)
	car.set_speed(v0)
	_gear_for(v0)
	_x0 = car.global_position
	_yaw0 = car.global_rotation.y


func _physics_process(dt: float) -> bool:
	if ci >= cases.size() or car == null or not is_instance_valid(car):
		return true
	t += dt
	var b: Basis = car.global_transform.basis
	var vel: Vector3 = car.linear_velocity
	var acc := (vel - _prev_v) / dt
	_prev_v = vel
	var hv := Vector2(vel.x, vel.z).length()
	var kmh := hv * 3.6
	var beta := rad_to_deg(atan2(vel.dot(b.x), vel.dot(-b.z))) if hv > 3.0 else 0.0
	var heading := rad_to_deg(wrapf(car.global_rotation.y - _yaw0, -PI, PI))
	var inp := {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": false}
	var done := false
	match c.k:
		"standing":
			if t >= 1.0:
				inp.throttle = 1.0
				for mk in [[60.0 * MPH, "60mph"], [100.0, "100"], [200.0, "200"]]:
					if kmh >= mk[0] and not m.has(mk[1]):
						m[mk[1]] = t - 1.0
			done = m.has("200") or t > 20.0
		"roll":
			var v0: float = c.from / 3.6
			if t < 0.5:
				_roll_start(v0)
			elif not m.has("go"):
				inp.throttle = clampf((v0 - car.speed) * 0.5 + 0.2, 0.0, 1.0)   # (cruising there)
				if t > 3.0:
					m.go = t
			else:
				inp.throttle = 1.0
				if kmh >= c.to:
					m.time = t - m.go
			done = m.has("time") or t > 20.0
		"launch":
			if t < 2.0:
				inp.handbrake = true                       # (the grid: parked on the line)
				inp.brake = 0.6
				_yaw0 = car.global_rotation.y
				_x0 = car.global_position
			else:
				inp.throttle = 1.0                         # lights out: W flat
				if not m.has("nudged") and t > 2.5:
					m.nudged = true
					car.angular_velocity += b.y * 0.03
				m.head = maxf(m.get("head", 0.0), absf(heading))
				m.beta = maxf(m.get("beta", 0.0), absf(beta))
				m.off = maxf(m.get("off", 0.0), absf(car.global_position.x - _x0.x))   # (it faces -z: sideways is x)
				if kmh >= 100.0 and not m.has("100"):
					m["100"] = t - 2.0
			done = t > 10.0
		"powertap":
			var v0: float = c.v / 3.6
			if t < 0.5:
				_roll_start(v0)
			else:
				inp.throttle = 1.0
				if t > 1.0 and t < 1.0 + c.hold:
					inp.steer = 1.0
				m.beta = maxf(m.get("beta", 0.0), absf(beta))
			done = t > 5.0
		"lane":
			var v0: float = c.v / 3.6
			inp.throttle = clampf((v0 - car.speed) * 0.6, 0.0, 1.0)
			if t < 0.5:
				_roll_start(v0)
			elif t > 1.0:
				var u := t - 1.0
				if c.dev == "kb":
					inp.steer = 1.0 if u < 0.45 else (-1.0 if u >= 0.7 and u < 1.15 else 0.0)
				else:
					inp.steer = 0.3 * sin(u / 2.4 * TAU) if u < 2.4 else 0.0
					inp.analog = true
				m.off = car.global_position.x - _x0.x
			done = t > 6.0
		"key":
			var v0: float = c.v / 3.6
			inp.throttle = clampf((v0 - car.speed) * 0.6, 0.0, 1.0)
			if t < 0.5:
				_roll_start(v0)
			elif t > 1.0 and t < 1.0 + c.hold:
				inp.steer = 1.0
			done = t > 4.5
		"cruise":
			var dt_ = car.drivetrain
			if t < 0.5:
				_roll_start(50.0 / 3.6)
			elif t < 16.0:
				inp.throttle = clampf((100.0 / 3.6 - car.speed) * 0.1 + 0.1, 0.0, 0.4)   # (gently up to 100 and holding it)
				m.gear = dt_.gear
				m.rpm = dt_.rpm()
				m.kmh = kmh
			else:
				inp.throttle = 1.0                         # (floored)
				if not m.has("kick") and dt_.gear < int(m.gear) and not dt_.shifting():
					m.kick = t - 16.0
					m.kick_gear = dt_.gear
					m.kick_rpm = dt_.rpm()
			done = t > 18.0
		"lift":
			var dt_ = car.drivetrain
			if t < 0.5:
				_roll_start(100.0 / 3.6)
			elif t < 2.0:
				inp.throttle = 1.0                         # (a pull on the key ...)
				m.gear0 = dt_._next_gear if dt_.shifting() else dt_.gear
			elif t < 3.5:
				m.gear1 = maxi(int(m.get("gear1", 0)), dt_.gear if not dt_.shifting() else dt_._next_gear)   # (... and off it)
			else:
				inp.throttle = 1.0
			done = t > 4.0
	car.inp = inp
	if t > 0.6:
		for k in 4:
			m.fx = maxf(m.get("fx", 0.0), fx.intensity[k])
		m.latg = maxf(m.get("latg", 0.0), absf(acc.dot(b.x)) / 9.81)
		m.beta_all = maxf(m.get("beta_all", 0.0), absf(beta))
		var pk: float = car.wheels[0].surface_tire.lateral_peak_deg
		m.front = maxf(m.get("front", 0.0), maxf(absf(car.wheels[0].slip_angle_deg()), absf(car.wheels[1].slip_angle_deg())) / pk)
		m.wheel = maxf(m.get("wheel", 0.0), absf(rad_to_deg(car.steer)))
		m.esc = int(m.get("esc", 0)) + (1 if car.assist.esc_wheel >= 0 else 0)
	if done:
		_next()
	return false


func _report() -> void:
	match c.k:
		"standing":
			var t60 := float(m.get("60mph", INF))
			var t100 := float(m.get("100", INF))
			var t200 := float(m.get("200", INF))
			_check(t60 > 2.6 and t60 < 3.8 and t100 > 2.8 and t100 < 4.0,
				"the M5 G90 from a standstill: 0-60 mph %.2f s, 0-100 km/h %.2f s (the real car: 3.0 s with a 1-ft rollout, BMW's 0-100 3.5 s)" % [t60, t100])
			_check(t200 > 9.0 and t200 < 12.0, "... 0-200 km/h %.2f s (BMW: 10.9 s)" % t200)
		"roll":
			var tr := float(m.get("time", INF))
			_check(tr > float(c.lo) and tr < float(c.hi), "the M5 G90 rolling %s flat out from a cruise: %.2f s (real: %s)" % [c.n, tr,
				"~3.7-4.2 s" if c.n == "60-100 mph" else "6.4 s (FastestLaps) / 7.4 s (BMW's 0-100 and 0-200)"])
		"launch":
			var t100 := float(m.get("100", INF))
			_check(float(m.head) < 2.0 and float(m.beta) < 2.0 and float(m.off) < 1.5 and t100 < 4.0,
				"%s (Track Mode, cold mediums, its own TC): a standing launch on keys, no steering, stays straight (heading %.1f deg, body slip %.1f deg, %.2f m off its line), 0-100 km/h %.2f s" % [
				c.car, float(m.head), float(m.beta), float(m.off), t100])
		"powertap":
			_check(float(m.beta) < 6.0, "%s on the throttle at 80 km/h, a key tapped %.1f s: no spin (the most body slip %.1f deg)" % [c.car, c.hold, float(m.beta)])
		"lane":
			var ok: bool = fx.puffs_made == 0 and marks.made == 0 and float(m.fx) < 0.05 and float(m.beta_all) < 1.5 and float(m.front) < 0.5 \
				and int(m.esc) == 0 and absf(float(m.off)) > 1.0
			_check(ok, "the M5 changing lanes at 200 km/h (%s): moved over %.1f m, %.2f g, body slip %.1f deg, front tyres at %.0f %% of their peak slip, %d smoke puffs, %d tyre-mark pieces, stability control %s" % [
				"keys" if c.dev == "kb" else "a stick", absf(float(m.off)), float(m.latg), float(m.beta_all), float(m.front) * 100.0, fx.puffs_made, marks.made,
				"never braking" if int(m.esc) == 0 else "braking %d ticks" % int(m.esc)])
		"key":
			if c.hold < 1.0:
				_check(float(m.latg) > 0.08 and float(m.latg) < 0.3 and float(m.wheel) < 1.0,
					"the M5 at 200 km/h, a 0.3 s tap of a key: a calm move (%.2f g, the road wheels at most %.1f deg)" % [float(m.latg), float(m.wheel)])
			else:
				_check(float(m.latg) > 0.75 and float(m.front) < 1.0 and float(m.wheel) < 2.0 and fx.puffs_made == 0,
					"the M5 at 200 km/h, a key held 2 s: a hard turn (%.2f g) with the front tyres short of their peak (%.0f %%), the road wheels at most %.1f deg, no smoke (%d puffs)" % [
					float(m.latg), float(m.front) * 100.0, float(m.wheel), fx.puffs_made])
		"cruise":
			var n: int = car.drivetrain.gears()
			_check(int(m.gear) >= n - 1 and float(m.rpm) < 3000.0, "the M5's automatic, gently up to a %.0f km/h cruise: in gear %d of %d at %.0f rpm" % [float(m.kmh), int(m.gear), n, float(m.rpm)])
			_check(m.has("kick") and float(m.kick) < 0.6 and int(m.gear) - int(m.get("kick_gear", 99)) >= 3,
				"... floored from there it kicks down from %d to %s in %s (at %s rpm)" % [int(m.gear), str(m.get("kick_gear", "-")), "%.2f s" % float(m.kick) if m.has("kick") else "never",
				"%.0f" % float(m.kick_rpm) if m.has("kick") else "-"])
		"lift":
			_check(int(m.gear1) <= int(m.gear0), "the M5 on keys: a 1.5 s lift after a pull doesn't change up (gear %d on the key, %d off it)" % [int(m.gear0), int(m.gear1)])


func _check(ok: bool, msg: String) -> void:
	print("[tarmac] %s %s" % ["ok  " if ok else "FAIL", msg])
	if not ok:
		fails += 1
