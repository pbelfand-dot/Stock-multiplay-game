extends SceneTree
## SIM STREET handling (Settings > STREET HANDLING: the road modes), measured the
## way the magazines measure real cars, on a flat asphalt pad:
##   * the skid pad: held at 76 km/h (a 300 ft pad's speed at about 1 g), the
##     steering wound on slowly until the car can't turn any tighter: the most
##     lateral g it holds for a second
##   * braking: 100 to 0 km/h, the pedal flat with ABS (as the tests are run): the
##     distance, and the average deceleration in g
## Each car against its own figure (Catalog.street_grip: the real skid-pad g, and
## braking ~1.1x that on road tyres): within 10 % sideways, 12 % braking. And the
## same car on the rally game's ARCADE grip, for comparison (printed, not judged),
## and SIM's aids: no drift assist, countersteer help or high-speed stability.
## Run: godot --headless --fixed-fps 120 --path . -s tests/sim_check.gd [-- --car=akatsuki]

const CARS := ["akatsuki", "raiden", "hellhound", "hachi", "lancer", "kaiser_2", "elfer_rs", "kestrel", "elfer_r"]
const PAD_KMH := 76.0
const RAMP_S := 12.0                # s to wind the steering on to RAMP_TO
const RAMP_TO := 0.7
const LAT_TOL := 0.10
const BRAKE_TOL := 0.12

var RallyCar
var Catalog
var TM
var AssistConfig
var car
var cases: Array = []
var ci := -1
var c: Dictionary
var t := 0.0
var _prev_v := Vector3.ZERO
var _lat: Array = []                # lateral g each tick (the skid pad)
var _x0 := Vector3.ZERO
var _spun := false
var results: Array = []
var fails := 0
var trace := false


func _initialize() -> void:
	RallyCar = load("res://scripts/vehicle/rally_car.gd")
	Catalog = load("res://scripts/game/catalog.gd")
	TM = load("res://scripts/vehicle/physics/tire_model.gd")
	AssistConfig = load("res://scripts/vehicle/physics/config/assist_config.gd")
	if RallyCar == null or not RallyCar.can_instantiate():
		print("[sim] FAIL the car's script doesn't compile")
		quit(1)
		return
	var only := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--car="):
			only = Array(a.trim_prefix("--car=").split(","))
		elif a == "--trace":
			trace = true
	var pad := StaticBody3D.new()
	pad.set_meta("surface", "asphalt")
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(8000, 2, 8000)
	cs.shape = bx
	pad.add_child(cs)
	pad.position = Vector3(0, -1, 0)
	root.add_child(pad)
	for id in (only if not only.is_empty() else CARS):
		for sim in [true, false]:
			cases.append({"car": id, "sim": sim, "k": "pad"})
			cases.append({"car": id, "sim": sim, "k": "brake"})
	_hook()
	_next()


class FakeStage:
	var kind := "loop"
	var length := 100.0
	var sections := [{"s0": 0.0, "s1": 100.0, "surface": "asphalt"}]


## The game's hook: Catalog.for_stage gives a car its street tyres on the road
## kinds only, and only while Settings say SIM.
func _hook() -> void:
	var st := FakeStage.new()
	var cfg = root.get_node_or_null("Config")
	var was: String = cfg.street_handling if cfg else ""
	if cfg:
		cfg.street_handling = "sim"
	for k in ["loop", "touge", "highway", "rally"]:
		st.kind = k
		var s: Dictionary = Catalog.for_stage(Catalog.setup("akatsuki"), st)
		if s.has("street") != (k != "rally"):
			print("[sim] FAIL for_stage on a %s stage: street %s" % [k, s.get("street")])
			fails += 1
	if cfg:
		cfg.street_handling = "arcade"
		st.kind = "loop"
		if Catalog.for_stage(Catalog.setup("akatsuki"), st).has("street"):
			print("[sim] FAIL for_stage: street tyres with STREET HANDLING on ARCADE")
			fails += 1
		cfg.street_handling = was
	print("[sim] for_stage hook checked (Config %s)" % ("present" if cfg else "absent: SIM assumed"))


func _make_car() -> void:
	car = RallyCar.new()
	car.grip_assist = 2.0                                  # (the game's out of the box: SIM overrides it on the road)
	var a: Resource = AssistConfig.new()                   # the game's default aids ...
	a.steering_smoothing = false                           # ... less the steering's filters (the test steers itself)
	a.speed_sensitive_steering = false
	a.countersteer_help = true
	a.drift_assist = true
	a.high_speed_stability = true
	a.anti_lock = false                                    # (SIM: the car's factory ABS; ...
	if c.k == "brake" and not (c.sim and bool(Catalog.street_grip(c.car)[2])):
		a.anti_lock = true                                 # ... the rest braked at the threshold, as the magazines' drivers do)
	car.assists = a
	var s: Dictionary = Catalog.setup(c.car, {}, {}, {"tyre": "tarmac", "preset": "tarmac"})
	if c.sim:
		s.street = Catalog.street_grip(c.car)
	car.setup = s
	root.add_child(car)
	car.place(Vector3.ZERO, 0.0)


func _next() -> void:
	if ci >= 0:
		_report()
		car.queue_free()
	ci += 1
	if ci >= cases.size():
		_summary()
		return
	c = cases[ci]
	t = 0.0
	_lat = []
	_spun = false
	_make_car()


func _physics_process(dt: float) -> bool:
	if ci >= cases.size() or car == null or not is_instance_valid(car):
		return true
	t += dt
	var v0: float = (PAD_KMH if c.k == "pad" else 100.0) / 3.6
	if t < 0.5:
		car.place(Vector3.ZERO, 0.0)
		car.set_speed(v0)
		_gear_for(v0)
		car.inp = {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": false}
		_prev_v = car.linear_velocity
		_x0 = car.global_position
		return false
	var b: Basis = car.global_transform.basis
	var vel: Vector3 = car.linear_velocity
	var acc := (vel - _prev_v) / dt
	_prev_v = vel
	var hv := Vector2(vel.x, vel.z).length()
	if c.k == "pad":
		var fwd_v := vel.dot(-b.z)
		var beta := rad_to_deg(atan2(vel.dot(b.x), maxf(absf(fwd_v), 0.1)))
		if absf(beta) > 20.0:
			_spun = true
		var thr := clampf((v0 - fwd_v) * 0.25 + 0.15, 0.0, 1.0)
		car.inp = {"steer": RAMP_TO * minf((t - 0.5) / RAMP_S, 1.0), "throttle": thr, "brake": 0.0, "handbrake": false}
		_lat.append(absf(acc.dot(b.x)) / 9.81)
		if trace and c.sim and int(t * 120.0) % 30 == 0:
			var w: Array = car.wheels
			print("[tr] t %.2f steer %.2f thr %.2f %3.0f km/h lat %.2f beta %+5.1f slip f %+5.1f/%+5.1f r %+5.1f/%+5.1f sr r %+.2f/%+.2f load %4.0f/%4.0f/%4.0f/%4.0f gear %s" % [t,
				float(car.inp.steer), thr, hv * 3.6, _lat[-1], beta, w[0].slip_angle_deg(), w[1].slip_angle_deg(), w[2].slip_angle_deg(), w[3].slip_angle_deg(),
				w[2].slip_long, w[3].slip_long, w[0].load, w[1].load, w[2].load, w[3].load, str(car.drivetrain.gear) if car.drivetrain else "-"])
		if t > 0.5 + RAMP_S + 2.0 or _spun:
			_next()
	else:
		car.inp = {"steer": 0.0, "throttle": 0.0, "brake": 1.0, "handbrake": false}
		if trace and c.sim and int(t * 120.0) % 24 == 0:
			var w: Array = car.wheels
			print("[tr] t %.2f %3.0f km/h dec %.2f sr %+.2f/%+.2f/%+.2f/%+.2f load %4.0f/%4.0f/%4.0f/%4.0f abs %s" % [t, hv * 3.6, -acc.dot(-b.z) / 9.81,
				w[0].slip_long, w[1].slip_long, w[2].slip_long, w[3].slip_long, w[0].load, w[1].load, w[2].load, w[3].load, str(car.assist.abs_ease)])
		if hv < 0.3 or t > 8.0:
			_next()
	return false


## In the gear the auto-shift would have it in at v (set_speed leaves it in first).
func _gear_for(v: float) -> void:
	var dt = car.drivetrain
	if dt == null:
		return
	var w: float = v / car.wheels[2].radius
	var g := 1
	while g < dt.gears() and w * dt.ratio_for(g) * 60.0 / TAU > dt.cfg.upshift_rpm - 400.0:
		g += 1
	dt.gear = g
	dt.omega_e = w * dt.ratio_for(g)


func _report() -> void:
	var g_want: float = Catalog.street_grip(c.car)[0]
	var kind: String = Catalog.street_grip(c.car)[1]
	var r := {"car": c.car, "sim": c.sim, "k": c.k}
	if c.k == "pad":
		var best := 0.0
		var win := 120                                      # 1 s at 120 Hz
		var sum := 0.0
		for i in _lat.size():
			sum += float(_lat[i])
			if i >= win:
				sum -= float(_lat[i - win])
				best = maxf(best, sum / win)
		r.g = best
		r.want = g_want
		r.ok = absf(best / g_want - 1.0) <= LAT_TOL
		r.spun = _spun
	else:
		var d: float = car.global_position.distance_to(_x0)
		var v0 := 100.0 / 3.6
		r.dist = d
		r.g = v0 * v0 / (2.0 * d) / 9.81
		var brake: float = TM.STREET_KINDS[kind].brake
		r.want = g_want * brake
		r.ok = absf(r.g / r.want - 1.0) <= BRAKE_TOL
	if c.sim:
		r.aids_ok = not car.assist.cfg.drift_assist and not car.assist.cfg.countersteer_help and not car.assist.cfg.high_speed_stability \
			and car.assist.cfg.anti_lock == (bool(Catalog.street_grip(c.car)[2]) or c.k == "brake")
		if not r.ok or not r.aids_ok:
			fails += 1
	results.append(r)
	if c.k == "pad":
		print("[sim] %-10s %-6s skid pad %.2f g (real %.2f)%s %s" % [c.car, "SIM" if c.sim else "arcade", r.g, r.want,
			" spun" if r.spun else "", ("ok" if r.ok else "OFF") if c.sim else ""])
	else:
		print("[sim] %-10s %-6s 100-0 %.1f m = %.2f g (want ~%.2f) %s" % [c.car, "SIM" if c.sim else "arcade", r.dist, r.g, r.want,
			("ok" if r.ok else "OFF") if c.sim else ""])


func _summary() -> void:
	var lat_err := []
	for r in results:
		if r.sim and r.k == "pad":
			lat_err.append(r.g / r.want)
	var mean := 0.0
	for e in lat_err:
		mean += e
	mean /= maxf(lat_err.size(), 1)
	print("[sim] skid pad, SIM: measured / real %.3f on average (TireModel.STREET_CAL %.3f)" % [mean, TM.STREET_CAL])
	if fails == 0:
		print("SIM OK")
		quit(0)
	else:
		print("SIM FAIL %d" % fails)
		quit(1)
