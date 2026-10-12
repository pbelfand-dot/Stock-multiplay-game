extends SceneTree
## How the car FEELS, in numbers: scripted test drives on a flat asphalt pad, on
## a keyboard (keys: full on or off, tapped) and a controller (a stick and
## triggers: part-way, ramped), for touge and for cutting up through traffic.
##   * steering response: a step of steering at 60 / 120 / 200 km/h; how long the
##     car takes to reach half and 90 % of the turn it settles to (ms)
##   * the grip limit: steering wound on slowly at 80 km/h; the most g, how far it
##     falls once past the peak (a snap), and how loud the tyres are (the squeal /
##     dust cue, 0..1) at 80 / 90 / 100 % of the peak
##   * drift angle control: a handbrake flick into a drift, held on the throttle,
##     then steering into the corner / straight / countersteer: does the drift
##     angle follow the steering? and how much of the front wheels' angle is the
##     driver's (the rest: countersteer help)
##   * a long drift: a drifter (keys or stick) holding 30 deg for 6 s: how
##     steady, how long it stays a drift, the speed it bleeds
##   * a touge hairpin: brake from 100, handbrake flick, round 180 deg on the
##     throttle: time, the slowest point, the exit speed, the most slip, a spin?
##   * linked S-bends: a drift one way, flicked into a drift the other way
##   * cutting up: a lane change (3.5 m) at 150 / 200 / 250 km/h, a quick flick at
##     200, emergency braking from 200 / 150 (and steering while braking), a clip
##     on the rear corner at 150 (hands off): the wobble after, the most slip,
##     how long it takes to settle, a spin?
## Configs: --cfg=oob (out of the box: ARCADE grip, tarmac tyres and setup, the
## default aids), oob_nodrift (the same, drift assist off), sim (REAL tyres,
## every aid off), street (SIM STREET, the road modes' out of the box: the car's
## real road tyres, Catalog.street_grip, the default aids less SIM's three).
## --car=kestrel (4WD) | martello (rear drive) | any car. --only=prefix.
## Run: godot --headless --fixed-fps 120 --path . -s tests/feel_check.gd -- --cfg=oob --car=kestrel

var RallyCar
var Catalog
var car
var pad
var cfg := "oob"
var car_id := "kestrel"
var cases: Array = []
var ci := -1
var t := 0.0
var c: Dictionary
var m := {}                         # this case's measurements
var log_rows: Array = []            # per tick: [t, beta, yaw, lat_g, kmh, steer_in, wheel, cs, slip, x, z, heading]
var _prev_v := Vector3.ZERO
var _yaw0 := 0.0
var _x0 := Vector3.ZERO
var _slide := 0.0                   # +1 / -1: the side the drift went (for the drift sign)
var results := {}
var diag := []                      # what-if changes to the test car only (not the game): csoff, keep:<share>, mu:<sealed x>, scale


func _initialize() -> void:
	RallyCar = load("res://scripts/vehicle/rally_car.gd")
	Catalog = load("res://scripts/game/catalog.gd")
	if RallyCar == null or not RallyCar.can_instantiate():
		print("[feel] FAIL the car's script doesn't compile")
		quit(1)
		return
	var only := ""
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"cfg": cfg = kv[1]
			"car": car_id = kv[1]
			"only": only = kv[1]
			"diag": diag = Array(kv[1].split("+"))
	pad = StaticBody3D.new()
	pad.set_meta("surface", "asphalt")
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(8000, 2, 8000)
	cs.shape = bx
	pad.add_child(cs)
	pad.position = Vector3(0, -1, 0)
	root.add_child(pad)
	for v in [60, 120, 200]:
		cases.append({"n": "step %d kb" % v, "k": "step", "v": v, "amt": 1.0})
		cases.append({"n": "step %d pad" % v, "k": "step", "v": v, "amt": 0.3})
	for v in [120, 200]:
		for amt in [0.1, 0.2, 0.5]:
			cases.append({"n": "gain %d pad %.1f" % [v, amt], "k": "step", "v": v, "amt": amt})
	cases.append({"n": "limit 80 pad", "k": "ramp", "v": 80})
	cases.append({"n": "limit 80 pad nolim", "k": "ramp", "v": 80, "nolim": true})
	for dev in ["kb", "pad"]:
		for hold in ["into", "neutral", "counter"]:
			cases.append({"n": "drift %s %s" % [dev, hold], "k": "dctl", "v": 70, "dev": dev, "hold": hold})
	cases.append({"n": "drift pad half", "k": "dctl", "v": 70, "dev": "pad", "hold": "half"})
	cases.append({"n": "long drift kb", "k": "dhold", "v": 70, "dev": "kb"})
	cases.append({"n": "long drift pad", "k": "dhold", "v": 70, "dev": "pad"})
	cases.append({"n": "hairpin kb", "k": "hairpin", "v": 100, "dev": "kb"})
	cases.append({"n": "hairpin pad", "k": "hairpin", "v": 100, "dev": "pad"})
	cases.append({"n": "linked S kb", "k": "linked", "v": 70, "dev": "kb"})
	cases.append({"n": "power out pad", "k": "power", "v": 50, "dev": "pad"})
	for v in [150, 200, 250]:
		cases.append({"n": "lane %d kb" % v, "k": "lane", "v": v, "dev": "kb"})
		cases.append({"n": "lane %d pad" % v, "k": "lane", "v": v, "dev": "pad"})
		cases.append({"n": "sine %d pad" % v, "k": "sine", "v": v, "dev": "pad"})
	cases.append({"n": "flick 200 kb", "k": "flick", "v": 200})
	cases.append({"n": "brake 200", "k": "brake", "v": 200, "steer": 0.0})
	cases.append({"n": "brake 150", "k": "brake", "v": 150, "steer": 0.0})
	cases.append({"n": "brake 150 steer pad", "k": "brake", "v": 150, "steer": 0.2})
	cases.append({"n": "clip 150", "k": "clip", "v": 150})
	cases.append({"n": "top speed", "k": "top", "v": 120})
	if only != "":
		cases = cases.filter(func(x): return x.n.begins_with(only))
	_next()


func _make_car() -> void:
	car = RallyCar.new()
	car.grip_assist = 0.0 if cfg == "sim" else 2.0
	car.setup = Catalog.setup(car_id, {}, {}, {"tyre": "tarmac", "preset": "tarmac"})
	if cfg == "street":
		car.setup.street = Catalog.street_grip(car_id)
	root.add_child(car)
	car.place(Vector3.ZERO, 0.0)
	var TM = load("res://scripts/vehicle/physics/tire_model.gd")
	for d in diag:
		var kv: PackedStringArray = d.split(":")
		match kv[0]:
			"keep":                                       # a sliding tyre keeps this share sideways (rear)
				car.config.rear_tire.lateral_shape = TM.shape_keeping(float(kv[1]))
			"keepall":
				car.config.front_tire.lateral_shape = TM.shape_keeping(float(kv[1]))
				car.config.rear_tire.lateral_shape = TM.shape_keeping(float(kv[1]))
			"mu":                                         # sealed grip x this (instead of ARCADE's x1.3)
				for tt in [car.config.front_tire, car.config.rear_tire]:
					tt.sealed_grip = tt.sealed_grip / 1.3 * float(kv[1])


func _aids() -> void:
	if car.assists == null:
		return
	if cfg == "sim":
		for k in ["anti_lock", "traction_control", "stability_control", "steering_smoothing", "steering_damping",
				"countersteer_help", "speed_sensitive_steering", "drift_assist", "high_speed_stability"]:
			if k in car.assists:
				car.assists.set(k, false)
	elif cfg == "oob_nodrift":
		if "drift_assist" in car.assists:
			car.assists.drift_assist = false
	if c.get("nolim", false):
		car.assists.speed_sensitive_steering = false
	if diag.has("csoff"):
		car.assists.countersteer_help = false
	if diag.has("scale"):
		car.assists.speed_sensitive_steering = false
	car._set_aids()                                     # (SIM STREET runs a copy: hand it the switches)


func _next() -> void:
	if ci >= 0:
		_report()
		car.queue_free()
	ci += 1
	if ci >= cases.size():
		_summary()                                      # (every summary ends in _done(): it quits, 1 on any FAIL)
		return
	c = cases[ci]
	t = 0.0
	m = {}
	log_rows = []
	_slide = 0.0
	_make_car()


func _physics_process(dt: float) -> bool:
	if ci >= cases.size():
		return true
	t += dt
	var v0: float = c.v / 3.6
	if t < 0.5:
		_aids()
		car.place(Vector3.ZERO, 0.0)
		car.set_speed(v0)
		car.inp = {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": false}
		_prev_v = car.linear_velocity
		_yaw0 = car.global_rotation.y
		_x0 = car.global_position
		return false
	var b: Basis = car.global_transform.basis
	var vel: Vector3 = car.linear_velocity
	var fwd := -b.z
	var right := b.x
	var hv := Vector2(vel.x, vel.z).length()
	var beta := rad_to_deg(atan2(vel.dot(right), vel.dot(fwd))) if hv > 3.0 else 0.0
	var yaw := rad_to_deg(car.angular_velocity.y)
	_prev_v = vel
	var lat_g: float = car.angular_velocity.y * hv / 9.81 if absf(beta) < 20.0 else (vel - _prev_v).dot(right) / dt / 9.81   # (steady: yaw x speed)
	var heading := rad_to_deg(wrapf(car.global_rotation.y - _yaw0, -PI, PI))
	var inp := _drive(beta, yaw, hv, heading)
	if diag.has("scale") and hv > 1.0 and not inp.handbrake:
		# full stick = the useful angle at this speed (what speed-sensitive steering clamps to), the rest in proportion
		var tt: Resource = car.wheels[0].surface_tire
		var base: float = car.config.rear_axle - car.config.front_axle
		var useful: float = atan(base * tt.lateral_mu * 9.8 / (hv * hv)) + deg_to_rad(tt.lateral_peak_deg) * 0.6
		inp.steer = float(inp.steer) * minf(useful / deg_to_rad(car.config.steering.max_angle_deg), 1.0)
	car.inp = inp
	if OS.get_cmdline_user_args().has("--trace") and int(t * 120.0) % 12 == 0:
		print("[tr] t %.2f in %+.1f/%.1f/%d beta %+6.1f yaw %+6.1f %3.0f km/h wheel %+5.1f want %+5.1f hold %+6.0f rear slip %+5.1f/%+5.1f sr %+.2f/%+.2f" % [t, float(inp.steer), float(inp.throttle), int(inp.handbrake), beta, yaw, hv * 3.6,
			rad_to_deg(car.steer), rad_to_deg(car.assist._drift_want), car.assist.drift_hold, car.wheels[2].slip_angle_deg(), car.wheels[3].slip_angle_deg(), car.wheels[2].slip_long, car.wheels[3].slip_long])
	log_rows.append([t, beta, yaw, lat_g, hv * 3.6, float(inp.steer), rad_to_deg(car.steer), rad_to_deg(car.assist.countersteer),
		car.grip_use if "grip_use" in car else car.slip, car.global_position.x - _x0.x, car.global_position.z - _x0.z, heading, float(inp.throttle)])
	if t > c.get("dur", _dur()):
		_next()
	return false


func _dur() -> float:
	match c.k:
		"step": return 3.5
		"ramp": return 6.5
		"dctl": return 4.5
		"dhold": return 8.0
		"hairpin": return 7.0
		"linked": return 6.0
		"lane": return 5.0
		"sine": return 5.0
		"flick": return 4.0
		"power": return 4.0
		"brake": return 9.0
		"clip": return 4.5
		"top": return 25.0
	return 5.0


## A hold-the-speed throttle (and brake above it).
func _hold(v: float) -> float:
	return clampf((v - car.speed) * 0.6, 0.0, 1.0)


func _drive(beta: float, yaw: float, hv: float, heading: float) -> Dictionary:
	var v0: float = c.v / 3.6
	var s := 0.0
	var thr := 0.0
	var brk := 0.0
	var hb := false
	match c.k:
		"step":
			s = c.amt if t > 1.0 else 0.0
			thr = _hold(v0)
		"ramp":
			s = clampf((t - 1.0) / 5.0, 0.0, 1.0)
			thr = _hold(v0)
		"dctl":
			# a flick right on the handbrake, the throttle on, then hold the steering
			var kb: bool = c.dev == "kb"
			if t < 1.0:
				thr = _hold(v0)
			elif t < 1.5:
				s = 1.0 if kb else 0.8
				hb = true
			else:
				var into := 1.0 if kb else 0.8
				s = {"into": into, "neutral": 0.0, "counter": -into, "half": 0.4}[c.hold]
				thr = 1.0 if kb else 0.8
		"dhold":
			# a drifter: in a right-hand drift the tail is out to the left (beta < 0);
			# hold |beta| at 30: too little: steer in / more throttle, too much: countersteer
			if t < 1.0:
				thr = _hold(v0)
			elif t < 1.5:
				s = 1.0
				hb = true
			else:
				var e := 30.0 - absf(beta)            # + = wants more angle
				if c.dev == "kb":
					s = 1.0 if e > 6.0 else (-1.0 if e < -6.0 else 0.0)
					thr = 1.0 if e > -3.0 else 0.0
				else:
					s = clampf(e / 20.0, -1.0, 1.0)
					thr = clampf(0.6 + e / 25.0, 0.0, 1.0)
		"hairpin":
			# brake from 100 to the turn, a handbrake flick, round 180 deg on the throttle
			var kb: bool = c.dev == "kb"
			if t < 1.6:
				brk = 1.0 if t > 0.6 else 0.0
			elif t < 2.0:
				s = 1.0 if kb else 0.9
				hb = true
			elif absf(heading) < 165.0 and not m.has("t180"):
				s = 1.0 if kb else 0.9
				thr = 1.0 if kb else 0.6
			else:
				s = 0.0
				thr = 1.0 if kb else 0.7
		"linked":
			# drift right (handbrake flick, held into it on the throttle), then flick it
			# left (a dab of handbrake) and hold that, then let go
			if t < 1.0:
				thr = _hold(v0)
			elif t < 1.4:
				s = 1.0
				hb = true
			elif t < 2.6:
				s = 1.0
				thr = 1.0
			elif t < 2.85:
				s = -1.0
				hb = true
			elif t < 4.2:
				s = -1.0
				thr = 1.0
			else:
				thr = 0.5
		"lane":
			# a driver changing one lane (3.5 m) to the right: aims the car a few degrees
			# toward the new lane, then straight down it; on keys, presses or lets go
			thr = _hold(v0)
			if t > 1.0:
				var y: float = car.global_position.x - _x0.x
				var psi := -deg_to_rad(heading)                   # + = pointing right
				var r: float = -car.angular_velocity.y           # + = turning right
				# about what full input turns it by: 1.5 g (ARCADE); in SIM street the stick asks for
				# a share of the car's own grip (DriverAssist.angle_for), so the driver knows that
				var full_g: float = float(Catalog.street_grip(car_id)[0]) * 9.8 if cfg == "street" else 15.0
				var r_full: float = full_g / maxf(hv, 5.0)
				# (aiming at the lane: rad of heading per m off it; in SIM street smaller corrections the
				# faster it goes, as a driver makes at 200: a fixed gain there hunts without yaw damping)
				var aim: float = minf(0.05, 2.2 / maxf(hv, 5.0)) if cfg == "street" else 0.05
				var r_want := clampf((clampf((3.5 - y) * aim, -0.09, 0.09) - psi) * 2.5, -r_full, r_full)
				var u := clampf(r_want / r_full + 2.0 * (r_want - r) / r_full, -1.0, 1.0)
				s = (signf(u) if absf(u) > 0.3 else 0.0) if c.dev == "kb" else u
		"sine":
			thr = _hold(v0)
			s = 0.3 * sin((t - 1.0) / 1.2 * TAU) if t > 1.0 and t < 2.2 else 0.0
		"power":
			# out of a slow corner: stick half over, the throttle floored
			thr = _hold(v0) if t < 1.0 else 1.0
			s = 0.5 if t > 1.0 else 0.0
		"flick":
			thr = _hold(v0)
			s = 1.0 if t > 1.0 and t < 1.15 else 0.0
		"brake":
			brk = 1.0 if t > 1.0 else 0.0
			thr = _hold(v0) if t <= 1.0 else 0.0
			s = c.steer if t > 1.5 else 0.0
		"clip":
			thr = _hold(v0)
			if not m.has("clipped") and t > 1.0:
				m.clipped = true
				# a car's rear corner clipped sideways (3 m/s worth of the car's weight)
				var b: Basis = car.global_transform.basis
				var at: Vector3 = b * Vector3(-0.8, 0.0, car.config.rear_axle)
				car.apply_impulse(b.x * float(car.mass) * 3.0, at)
		"top":
			thr = 1.0
	if c.k == "hairpin" and absf(heading) >= 165.0 and not m.has("t180"):
		m.t180 = t
		m.v180 = hv * 3.6
	return {"steer": s, "throttle": thr, "brake": brk, "handbrake": hb, "analog": c.get("dev", "") == "pad" or c.n.contains("pad")}


# ── measurements ────────────────────────────────────────────────────────

func _rows(t0: float, t1: float) -> Array:
	return log_rows.filter(func(r): return r[0] >= t0 and r[0] <= t1)


func _max_abs(rows: Array, i: int) -> float:
	var x := 0.0
	for r in rows:
		x = maxf(x, absf(r[i]))
	return x


func _mean(rows: Array, i: int) -> float:
	var s := 0.0
	for r in rows:
		s += r[i]
	return s / maxf(rows.size(), 1)


## Time (s after t0) the column first reaches this share of its value at t_end.
func _rise(i: int, t0: float, t_end: float, share: float) -> float:
	var goal := 0.0
	for r in log_rows:
		if r[0] <= t_end:
			goal = r[i]
	for r in log_rows:
		if r[0] >= t0 and absf(r[i]) >= absf(goal) * share:
			return r[0] - t0
	return INF


## After t0: how long until |yaw rate| stays under `lim` deg/s, and how many times it changes sign (a wobble).
func _settle(t0: float, lim: float) -> Vector2:
	var last_big := t0
	var flips := 0
	var prev := 0.0
	for r in log_rows:
		if r[0] < t0:
			continue
		if absf(r[2]) > lim:
			last_big = r[0]
		if absf(r[2]) > 0.5:
			if prev != 0.0 and signf(r[2]) != signf(prev):
				flips += 1
			prev = r[2]
	return Vector2(last_big - t0, flips)


func _report() -> void:
	var line := ""
	match c.k:
		"step":
			var t50 := _rise(2, 1.0, 1.8, 0.5)
			var t90 := _rise(2, 1.0, 1.8, 0.9)
			var w90 := _rise(6, 1.0, 1.8, 0.9)
			var tail := _rows(3.0, 3.4)
			m.t50 = t50 * 1000.0
			m.t90 = t90 * 1000.0
			m.yaw = absf(_mean(tail, 2))
			line = "yaw response: half in %4.0f ms, 90 %% in %4.0f ms (wheels 90 %% in %4.0f ms); settles at %5.1f deg/s, %.2f g" % [t50 * 1000.0,
				t90 * 1000.0, w90 * 1000.0, _mean(tail, 2), _mean(tail, 3)]
		"ramp":
			var peak := 0.0
			var tp := 0.0
			for r in log_rows:
				if absf(r[3]) > peak:
					peak = absf(r[3])
					tp = r[0]
			var after := _rows(tp, tp + 0.6)
			var low := peak
			for r in after:
				low = minf(low, absf(r[3]))
			var cue := [0.0, 0.0, 0.0]
			var shares := [0.8, 0.9, 1.0]
			for k in 3:
				for r in log_rows:
					if r[0] >= 1.2 and r[0] <= tp and absf(r[3]) >= peak * shares[k] - 0.02:
						cue[k] = r[8]
						break
			var end := _rows(6.0, 6.5)
			m.peak = peak
			m.quiet = 0.0
			for rr in log_rows:
				if rr[0] >= 1.2 and rr[0] <= tp and absf(rr[3]) <= peak * 0.5:
					m.quiet = maxf(m.quiet, rr[8])
			m.snap = 100.0 * (1.0 - low / maxf(peak, 0.01))
			m.cue = cue
			line = "peak %.2f g at steer %.2f, then falls %2.0f %% within 0.6 s; end %.2f g, slip %4.1f deg; squeal/dust cue at 80/90/100 %% of peak: %.2f / %.2f / %.2f" % [
				peak, clampf((tp - 1.0) / 5.0, 0.0, 1.0), m.snap, _mean(end, 3), _max_abs(_rows(1.0, 6.5), 1), cue[0], cue[1], cue[2]]
		"dctl":
			var hold := _rows(2.0, 4.4)
			var bm := _mean(hold, 1)
			var wheel := _mean(hold, 6)
			var cs := _mean(hold, 7)
			var v_in := _rows(1.45, 1.55)
			var v_out := _rows(4.35, 4.45)
			m.beta = absf(bm)
			m.beta_end = absf(log_rows[-1][1])
			var straight := INF
			for r in log_rows:
				if r[0] > 1.5 and absf(r[1]) < 3.0:
					straight = r[0] - 1.5
					break
			m.straight = straight
			m.kmh_in = _mean(v_in, 4)
			m.kmh_out = _mean(v_out, 4)
			line = "drift angle while held: %5.1f deg (end %5.1f); straight %s; front wheels %+5.1f deg, %+5.1f of it the aids'; speed %3.0f -> %3.0f km/h" % [
				absf(bm), m.beta_end, ("%.2f s after" % straight) if straight < INF else "never", wheel, cs, m.kmh_in, m.kmh_out]
		"dhold":
			var rows := _rows(1.6, 8.0)
			var drifting := 0.0
			var spun := false
			for r in rows:
				if absf(r[1]) >= 15.0 and absf(r[1]) <= 50.0:
					drifting += 1.0 / 120.0
				if absf(r[1]) > 90.0:
					spun = true
			var dr := rows.filter(func(r): return absf(r[1]) >= 15.0)
			var mean := _mean(dr, 1)
			var sd := 0.0
			for r in dr:
				sd += pow(absf(r[1]) - absf(mean), 2.0)
			sd = sqrt(sd / maxf(dr.size(), 1))
			m.drift_s = drifting
			m.spun = spun
			line = "held a drift (15-50 deg) for %.1f of 6.4 s; angle %4.1f +- %4.1f deg; speed %3.0f -> %3.0f km/h%s" % [drifting, absf(mean), sd,
				_mean(_rows(1.55, 1.65), 4), log_rows[-1][4], "  SPUN" if spun else ""]
		"hairpin":
			var spun := _max_abs(log_rows, 1) > 90.0
			var slowest := 999.0
			for r in _rows(1.6, 7.0):
				slowest = minf(slowest, r[4])
			m.spun = spun
			line = "round 180 deg in %s; slowest %3.0f km/h, %s; most slip %4.1f deg%s" % [
				("%.1f s" % (m.t180 - 1.6)) if m.has("t180") else "NEVER", slowest,
				("out at %3.0f km/h" % m.v180) if m.has("v180") else "-", _max_abs(log_rows, 1), "  SPUN" if spun else ""]
		"linked":
			var a := _max_abs(_rows(1.0, 2.8), 1)
			var bb := _max_abs(_rows(2.8, 6.0), 1)
			var spun := _max_abs(log_rows, 1) > 90.0
			m.spun = spun
			line = "first drift %4.1f deg, second %4.1f deg; out at %3.0f km/h%s" % [a, bb, log_rows[-1][4], "  SPUN" if spun else ""]
		"lane":
			var done := INF
			var over := 0.0
			var reached := INF
			for r in log_rows:
				if r[0] < 1.0:
					continue
				over = maxf(over, r[9] - 3.5)
				if r[9] >= 3.2 and reached == INF:
					reached = r[0]
				if absf(r[9] - 3.5) > 0.3 or absf(r[11]) > 1.0:
					done = INF
				elif done == INF:
					done = r[0] - 1.0
			var flips := _settle(reached if reached < INF else 4.0, 1.0).y
			m.done = done
			m.over = over
			m.beta = _max_abs(log_rows, 1)
			m.wobble = flips
			line = "in the next lane and straight %s; overshoot %4.2f m; most yaw %4.1f deg/s, most slip %4.1f deg; %d wobbles after" % [
				("%.2f s after starting" % done) if done < INF else "NEVER", over, _max_abs(log_rows, 2), m.beta, int(flips)]
		"sine":
			var end_t := 2.2
			var st := _settle(end_t, 1.0)
			var r_end: Array = log_rows[-1]
			var dx := absf(r_end[9])
			m.offset = dx
			m.settle = st.x
			m.wobble = st.y
			m.beta = _max_abs(log_rows, 1)
			line = "moved over %4.1f m; most yaw %4.1f deg/s, most slip %4.1f deg; settles (yaw < 1 deg/s) %.2f s after, %d wobbles; heading off %+.1f deg" % [
				dx, _max_abs(log_rows, 2), m.beta, st.x, int(st.y), r_end[11]]
		"flick":
			var st := _settle(1.15, 1.0)
			m.beta = _max_abs(log_rows, 1)
			m.turned = log_rows[-1][11]
			line = "most slip %4.1f deg, most yaw %4.1f deg/s; settles %.2f s after, %d wobbles; turned %+.1f deg" % [m.beta, _max_abs(log_rows, 2),
				st.x, int(st.y), log_rows[-1][11]]
		"brake":
			var dist := 0.0
			var stop_t := 9.0
			var prev: Array = []
			for r in log_rows:
				if r[0] >= 1.0 and r[0] < 1.0 + stop_t:
					if not prev.is_empty():
						dist += Vector2(r[9] - prev[9], r[10] - prev[10]).length()
					prev = r
					if r[4] < 3.0:
						stop_t = r[0] - 1.0
			var during := _rows(1.0, 1.0 + stop_t)
			m.dist = dist
			m.yaw = _max_abs(during, 2)
			m.beta = _max_abs(during, 1)
			line = "stopped in %5.1f m (%.1f s); most yaw %4.1f deg/s, most slip %4.1f deg, heading %+.1f deg" % [dist, stop_t, _max_abs(during, 2),
				_max_abs(during, 1), during[-1][11] if not during.is_empty() else 0.0]
		"clip":
			var after := _rows(1.0, 4.5)
			var mx := _max_abs(after, 1)
			var back := INF
			for r in after:
				if r[0] > 1.2 and absf(r[1]) < 3.0 and absf(r[2]) < 5.0:
					back = r[0] - 1.0
					break
			m.beta = mx
			m.back = back
			m.spun = mx > 90.0
			line = "most slip %4.1f deg, most yaw %4.1f deg/s; straight again %s%s" % [mx, _max_abs(after, 2),
				("%.2f s after" % back) if back < INF else "never", "  SPUN" if m.spun else ""]
		"power":
			m.beta = _max_abs(_rows(1.0, 4.0), 1)
			m.gain = log_rows[-1][4] - _mean(_rows(0.95, 1.05), 4)
			line = "most slip %4.1f deg; gained %3.0f km/h in 3 s" % [m.beta, m.gain]
		"top":
			line = "flat out from 120: %3.0f km/h after 24 s" % log_rows[-1][4]
	results[c.n] = m.duplicate()
	print("[feel] %-11s %-8s %-12s | %-20s %s" % [cfg, car_id, "+".join(diag), c.n, line])


## The feel, held to limits (out of the box; REAL with every aid off is the pure
## sim and only checked to be the tyres as they always were). A check runs if
## its cases ran (--only can pick some). Exits 1 on any FAIL.
var fails := 0

func _summary() -> void:
	var r := results
	if cfg == "street":
		_street_summary()
		return
	if cfg == "sim":
		_lim(["limit 80 pad"], func(): return absf(r["limit 80 pad"].peak - 1.34) < 0.06,
			func(): return "pure sim (REAL, aids off): the real tyres' grip, %.2f g (always ~1.34)" % r["limit 80 pad"].peak)
		_lim(["drift kb into"], func(): return r["drift kb into"].beta > 35.0,
			func(): return "pure sim: no aid holds a drift for you (held into it: %.0f deg)" % r["drift kb into"].beta)
		_done()
		return
	# touge
	for dev in ["kb", "pad"]:
		var into := "drift %s into" % dev
		var neu := "drift %s neutral" % dev
		var cnt := "drift %s counter" % dev
		_lim([into], func(): return r[into].beta >= (20.0 if dev == "kb" else 15.0) and r[into].beta <= 45.0,
			func(): return "%s: steering into the drift holds it at %.0f deg" % [dev, r[into].beta])
		_lim([neu], func(): return r[neu].straight <= 0.8,
			func(): return "%s: let go in a drift and it straightens (%.2f s)" % [dev, r[neu].straight])
		_lim([neu, cnt], func(): return r[cnt].straight <= r[neu].straight + 0.02,
			func(): return "%s: countersteer straightens it quicker (%.2f s vs %.2f letting go)" % [dev, r[cnt].straight, r[neu].straight])
	_lim(["drift pad half", "drift pad into"], func(): return r["drift pad half"].beta >= 4.0 and r["drift pad half"].beta <= r["drift pad into"].beta - 5.0,
		func(): return "pad: half as much steering, a smaller drift (%.0f deg vs %.0f)" % [r["drift pad half"].beta, r["drift pad into"].beta])
	_lim(["long drift pad"], func(): return r["long drift pad"].drift_s >= 5.0 and not r["long drift pad"].spun,
		func(): return "pad: a long drift held %.1f of 6.4 s" % r["long drift pad"].drift_s)
	_lim(["long drift kb"], func(): return r["long drift kb"].drift_s >= 3.0 and not r["long drift kb"].spun,
		func(): return "keys: a long drift held %.1f of 6.4 s" % r["long drift kb"].drift_s)
	for dev in ["kb", "pad"]:
		var hp := "hairpin %s" % dev
		_lim([hp], func(): return r[hp].has("t180") and not r[hp].spun and r[hp].v180 >= 50.0,
			func(): return "%s: a hairpin (brake from 100, handbrake flick, throttle): round, no spin, out at %.0f km/h" % [dev, r[hp].get("v180", 0.0)])
	_lim(["linked S kb"], func(): return not r["linked S kb"].spun,
		func(): return "keys: linked S-bends, left to right on the handbrake: no spin")
	# cutting up
	for v in [150, 200, 250]:
		for dev in ["kb", "pad"]:
			var ln := "lane %d %s" % [v, dev]
			# (keys at 250: 3.7 s. That's past either car's top speed, 183 km/h on the
			# limiter, and the 960 kg MARTELLO settles a shade slower there)
			var keys_s := 3.7 if v >= 250 else 3.5
			_lim([ln], func(): return r[ln].done <= (keys_s if dev == "kb" else 2.5) and r[ln].over <= 1.0 and r[ln].beta <= 3.0 and r[ln].wobble <= 2,
				func(): return "%s: a lane change at %d km/h done in %.2f s, %.2f m overshoot, %.1f deg slip, %d wobbles" % [dev, v, r[ln].done, r[ln].over, r[ln].beta, int(r[ln].wobble)])
		var sn := "sine %d pad" % v
		_lim([sn], func(): return r[sn].settle <= 0.8 and r[sn].wobble <= 1 and r[sn].beta <= 5.0,
			func(): return "pad: a quick weave at %d km/h settles in %.2f s, %d wobbles, %.1f deg slip" % [v, r[sn].settle, int(r[sn].wobble), r[sn].beta])
	_lim(["flick 200 kb"], func(): return r["flick 200 kb"].beta <= 3.0 and absf(r["flick 200 kb"].turned) <= 8.0,
		func(): return "keys: a quick flick at 200 km/h: %.1f deg slip, turned %.1f deg (no snap)" % [r["flick 200 kb"].beta, r["flick 200 kb"].turned])
	for v in [200, 150]:
		var bk := "brake %d" % v
		_lim([bk], func(): return r[bk].yaw <= 3.0 and r[bk].dist <= (115.0 if v == 200 else 70.0),
			func(): return "emergency braking from %d km/h: %.0f m, straight (%.1f deg/s yaw at most)" % [v, r[bk].dist, r[bk].yaw])
	_lim(["brake 150 steer pad"], func(): return r["brake 150 steer pad"].beta <= 12.0,
		func(): return "braking from 150 and steering: it steers, no spin (%.1f deg slip)" % r["brake 150 steer pad"].beta)
	_lim(["clip 150"], func(): return r["clip 150"].beta <= 20.0 and r["clip 150"].back <= 1.0,
		func(): return "clipped on the rear corner at 150: %.0f deg slip at most, straight again in %.2f s" % [r["clip 150"].beta, r["clip 150"].back])
	for v in [120, 200]:
		var a := "gain %d pad 0.2" % v
		var b := "gain %d pad 0.5" % v
		_lim([a, b], func(): return r[a].yaw / maxf(r[b].yaw, 0.1) >= 0.25 and r[a].yaw / maxf(r[b].yaw, 0.1) <= 0.65,
			func(): return "pad at %d km/h: a fifth of the stick turns it %.0f %% as much as half (in proportion)" % [v, 100.0 * r[a].yaw / maxf(r[b].yaw, 0.1)])
		for dev in ["kb", "pad"]:
			var st := "step %d %s" % [v, dev]
			_lim([st], func(): return r[st].t90 <= 350.0,
				func(): return "%s at %d km/h: the car turns 90 %% as much as it will in %.0f ms" % [dev, v, r[st].t90])
	# both
	_lim(["limit 80 pad"], func(): return r["limit 80 pad"].cue[0] >= 0.1 and r["limit 80 pad"].cue[1] >= 0.2 and r["limit 80 pad"].cue[2] >= 0.4 and r["limit 80 pad"].quiet <= 0.05,
		func(): return "the squeal warns before the limit: %.2f at 80 %% of the grip, %.2f at 90, %.2f at the limit (%.2f at half)" % [r["limit 80 pad"].cue[0],
			r["limit 80 pad"].cue[1], r["limit 80 pad"].cue[2], r["limit 80 pad"].quiet])
	_lim(["limit 80 pad"], func(): return r["limit 80 pad"].peak >= 1.35 and r["limit 80 pad"].peak <= 1.75,
		func(): return "ARCADE grip on tarmac tyres: %.2f g (1.9 rolled it and wouldn't let a drift live)" % r["limit 80 pad"].peak)
	_done()


## SIM STREET through traffic, on keys and a pad: no arcade helpers, so the bar is
## a real car's (Assetto Corsa's): it can be driven, not that it forgives.
func _street_summary() -> void:
	var r := results
	var g: float = Catalog.street_grip(car_id)[0]
	for v in [150, 200]:
		for dev in ["kb", "pad"]:
			var ln := "lane %d %s" % [v, dev]
			# (keys: the test's on-off driver hunts round the lane for a while without the
			# arcade's yaw damping, so on keys it's judged on staying in control: no
			# slide, no big overshoot; on a pad, settled too)
			# (SIM street has no yaw-damping aid out of the box any more: the test's on-off key
			# driver overshoots up to ~2 m at 200 km/h, though the car itself settles in ~0.6 s
			# with no rebound after an open-loop key lane change: /root/srwork/feel's harness)
			var most_over: float = 2.0 if dev == "kb" and v >= 200 else 1.5
			_lim([ln], func(): return r[ln].beta <= 5.0 and r[ln].over <= most_over and (dev == "kb" or (r[ln].done <= 4.0 and r[ln].wobble <= 3)),
				func(): return "street %s: a lane change at %d km/h done in %.2f s, %.2f m overshoot, %.1f deg slip, %d wobbles" % [dev, v, r[ln].done, r[ln].over, r[ln].beta, int(r[ln].wobble)])
	_lim(["flick 200 kb"], func(): return r["flick 200 kb"].beta <= 6.0,
		func(): return "street keys: a quick flick at 200 km/h: %.1f deg slip, turned %.1f deg" % [r["flick 200 kb"].beta, r["flick 200 kb"].turned])
	for v in [200, 150]:
		var bk := "brake %d" % v
		var most: float = pow(v / 3.6, 2.0) / (2.0 * 0.8 * g * 9.81) + v / 3.6 * 0.25   # (within 80 % of its tyres, the pedal's travel)
		_lim([bk], func(): return r[bk].yaw <= 3.0 and r[bk].dist <= most,
			func(): return "street: emergency braking from %d km/h: %.0f m (at most %.0f), straight (%.1f deg/s yaw)" % [v, r[bk].dist, most, r[bk].yaw])
	_lim(["brake 150 steer pad"], func(): return r["brake 150 steer pad"].beta <= 12.0,
		func(): return "street: braking from 150 and steering: it steers, no spin (%.1f deg slip)" % r["brake 150 steer pad"].beta)
	# (a hard clip on the rear corner at 150, hands off: in SIM street the car's own
	# stability control (its brakes) fights it, as a real car's would; HIGH-SPEED STABILITY
	# (CUT UP, TOUGE), off out of the box, catches it. Printed)
	if results.has("clip 150"):
		print("[feel] info %-8s street: clipped on the rear corner at 150, hands off: %.0f deg slip at most%s" % [car_id, r["clip 150"].beta,
			" (spun)" if r["clip 150"].beta > 90.0 else ", straight again in %.2f s" % r["clip 150"].back])
	_lim(["limit 80 pad nolim"], func(): return absf(r["limit 80 pad nolim"].peak / g - 1.0) <= 0.12,
		func(): return "street: its grip %.2f g (the real car's skid pad %.2f)" % [r["limit 80 pad nolim"].peak, g])
	_done()


## The rear-drive car against the 4WD one (results from both runs: --car=both).
func _lim(need: Array, ok: Callable, msg: Callable) -> void:
	for n in need:
		if not results.has(n):
			return
	var good: bool = ok.call()
	if not good:
		fails += 1
	print("[feel] %s %-8s %s" % ["ok  " if good else "FAIL", car_id, msg.call()])


func _done() -> void:
	print("[feel] %s" % ("FEEL OK" if fails == 0 else "FEEL FAIL"))
	quit(1 if fails > 0 else 0)
