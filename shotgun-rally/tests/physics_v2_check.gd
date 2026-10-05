extends SceneTree
## Physics v2 in the lab course (scripts/physics_lab.gd), at 120 ticks a second.
## Phase 1, the chassis on its four suspension corners:
##   * static: it sits level at the ride height the springs and its weight give
##     (each corner squashed by its share of the weight / the spring rate)
##   * bounce: lifted 5 cm and let go, it bounces at about the ride frequency
##     (~1.5 Hz, a little less for the damping) and settles within ~2 s
##   * drop: from a metre up it lands on the bump stops without the body
##     hitting the ground, doesn't bounce back into the air, and settles
##   * bumps: rolling over full-width bumps pitches it; over bumps under the
##     left wheels only, it rolls; the forces act at the corners, nothing levels it
## Phase 2, the tyres grip sideways and the front wheels steer:
##   * skid pad: towed round at 15 m/s with the wheel held at 2, 4, 8 and 15
##     degrees: the cornering force grows with the steering (at first just what
##     the geometry asks: v^2 x angle / wheelbase) and tops out at the tyres'
##     grip (mu g), never past it; front and rear slip angles reported
##   * side slope: parked across a 10 degree slope with no brakes, the tyres hold
##     it (the carcass sticks like a spring at a standstill): no creep, no wobble
##   * straight: at 20 m/s with the wheel straight it runs straight
## Phase 3, the wheels spin and the brakes work:
##   * a drive torque below the grip: it accelerates by exactly what the torque
##     gives (minus rolling resistance, with the wheels' own inertia to spin
##     up), the tyres barely slipping; well above it: wheelspin, and only
##     what the tyres can take
##   * brakes below the lock: exactly the torque's deceleration, no locking;
##     full pedal from 100 km/h: the wheels lock (they lock only because the
##     brakes beat the grip) and it slides to a stop on what a locked tyre keeps
##   * coasting: rolling resistance slows it, slowly
##   * nose up the slope: the brakes hold it; let go, it rolls back down
## Phase 4, one patch of rubber for both jobs, and load:
##   * at the cornering limit, brakes on: it loses cornering grip (the ellipse)
##     and the two together never pass the tyres' grip
##   * the same corner entered braking (trail braking) rotates the car more than
##     coasting into it: the nose loads and bites, the tail goes light
##   * a tyre with twice the load grips less per newton (load sensitivity)
## Run: godot --headless --fixed-fps 120 --path . -s tests/physics_v2_check.gd
## Prints [physics] lines; exits 1 on any FAIL.

const Lab = preload("res://scripts/physics_lab.gd")
const Suspension = preload("res://scripts/vehicle/physics/suspension.gd")
const TireModel = preload("res://scripts/vehicle/physics/tire_model.gd")

var car: RigidBody3D
var fails := 0
var _phase := -1
var _t := 0.0
var _log: Array = []               # per tick: [t, y, pitch, roll, grounded, max comp, min body clearance]
var _y0 := 0.0
var _lift_t := 0.0
var _phases := ["static", "bounce", "drop", "bumps", "left bumps", "skid 2", "skid 4", "skid 8", "skid 15",
	"side slope", "straight", "drive gently", "wheelspin", "brake gently", "brake locked", "coast",
	"slope braked", "slope rolling", "brake in turn", "turn in coasting", "turn in braking", "load"]
var _turn := {}                    # "coasting" / "braking" -> yaw gain
var _v0 := Vector3.ZERO
var _skid := {}                    # steering deg -> {a: lateral accel m/s², front / rear slip deg}
var _yaw0 := 0.0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	var course := Node3D.new()
	root.add_child(course)
	Lab.build_course(course)
	car = (load(Lab.CAR_SCENE) as PackedScene).instantiate()
	root.add_child(car)                              # (ready on the first frame: the runs start then)


func _process(_dt: float) -> bool:
	if car == null or not ("wheels" in car) or car.wheels.size() != 4:   # a script didn't load: say so, don't hang
		fails += _check(false, "the v2 car loaded with its four wheels")
		_phase = _phases.size()
		return _done()
	return false


func _next() -> void:
	_phase += 1
	_t = 0.0
	_log.clear()
	if _phase >= _phases.size():
		return
	match _phases[_phase]:
		"static":
			car.place(Lab.PAD, 0.0)
		"bounce":
			car.place(Lab.PAD, 0.0)
		"drop":
			car.place(Lab.PAD, 0.0)
			car.global_position.y += 1.0
		"bumps":
			Lab.launch(car, Vector3(0.0, 0.0, Lab.BUMPS_Z + 10.0), 12.0)
		"left bumps":
			Lab.launch(car, Vector3(Lab.BUMP_LANE_X, 0.0, Lab.BUMPS_Z + 10.0), 12.0)
		"skid 2", "skid 4", "skid 8", "skid 15":
			Lab.launch(car, Lab.SKID, 15.0)
			car.inp.steer = float(_phases[_phase].split(" ")[1]) / car.config.steering.max_angle_deg
		"side slope":
			Lab.park_on_slope(car)
		"straight":
			Lab.launch(car, Lab.SKID, 20.0)
			_yaw0 = car.global_rotation.y
		"drive gently", "wheelspin":
			car.place(Lab.SKID, 0.0)
		"brake gently":
			Lab.launch(car, Lab.SKID, 25.0)
		"brake locked":
			Lab.launch(car, Lab.SKID, 100.0 / 3.6)
		"coast":
			Lab.launch(car, Lab.SKID, 20.0)
		"slope braked", "slope rolling":
			Lab.park_on_slope(car, PI / 2.0)
		"brake in turn":
			Lab.launch(car, Lab.SKID, 15.0)
			car.inp.steer = 8.0 / car.config.steering.max_angle_deg
		"turn in coasting", "turn in braking":
			Lab.launch(car, Lab.SKID, 20.0)
			car.inp.steer = 2.5 / car.config.steering.max_angle_deg     # ~7 m/s²: under the limit
	_v0 = car.global_position
	_inputs(_phases[_phase])


## The pedals and the test torque for this run (set again every tick).
func _inputs(name: String) -> void:
	for w in car.wheels:
		w.drive_torque = {"drive gently": 400.0, "wheelspin": 2500.0}.get(name, 0.0)
	car.inp.brake = {"brake gently": 0.3, "brake locked": 1.0, "slope braked": 1.0, "turn in braking": 0.25}.get(name, 0.0)
	if name == "brake in turn":
		car.inp.brake = 0.4 if _t >= 4.0 else 0.0


func _physics_process(dt: float) -> bool:
	if _phase < 0:
		_next()
		return false
	if _phase >= _phases.size():
		return _done()
	_t += dt
	var name: String = _phases[_phase]
	if name.begins_with("skid") or (name == "brake in turn" and _t < 4.0):
		Lab.tow(car, 15.0)
	elif name == "straight":
		Lab.tow(car, 20.0)
	_inputs(name)
	if name == "bounce" and _t > 2.0 and _y0 == 0.0:
		_y0 = car.global_position.y                  # settled: lift it 5 cm and let go
		_lift_t = _t
		car.global_position.y += 0.05
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		_log.clear()
	var xf := car.global_transform
	var fwd := -xf.basis.z
	var max_c := 0.0
	for w in car.wheels:
		max_c = maxf(max_c, w.compression)
	var w: Array = car.wheels
	_log.append([_t, car.global_position.y, rad_to_deg(asin(clampf(fwd.y, -1, 1))), rad_to_deg(asin(clampf(xf.basis.x.y, -1, 1))),
		car.grounded, max_c, _clearance(),
		car.linear_velocity.length(), rad_to_deg(car.angular_velocity.y),                       # 7, 8
		(w[0].slip_angle_deg() + w[1].slip_angle_deg()) * 0.5, (w[2].slip_angle_deg() + w[3].slip_angle_deg()) * 0.5,  # 9, 10
		car.global_position, car.linear_velocity.dot(xf.basis.x),                                 # 11, 12
		car.linear_velocity.dot(fwd), _max_slip(), _all_locked(), car.accel, car.linear_velocity,  # 13-17
		(car.wheel_angles[0] + car.wheel_angles[1]) * 0.5])                                         # 18
	var length := {"static": 3.0, "bounce": 5.5, "drop": 4.5, "bumps": 4.0, "left bumps": 4.0,
		"skid 2": 5.0, "skid 4": 5.0, "skid 8": 5.0, "skid 15": 5.0, "side slope": 5.0, "straight": 3.0,
		"drive gently": 3.0, "wheelspin": 2.0, "brake gently": 2.0, "brake locked": 6.0, "coast": 3.0,
		"slope braked": 4.0, "slope rolling": 2.0, "brake in turn": 5.5, "turn in coasting": 1.4, "turn in braking": 1.4,
		"load": 0.1}
	if name.begins_with("skid") and _t >= length[name]:
		_judge_skid(int(name.split(" ")[1]))
		_next()
	elif _t >= length[name]:
		call(StringName("_judge_" + name.replace(" ", "_")))
		_next()
	return false


## How far the lowest corner of the body box is above the ground (y = 0) (m).
func _clearance() -> float:
	var cfg = car.config
	var lo := INF
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var p: Vector3 = car.global_transform * (cfg.body_center + cfg.body_size * 0.5 * Vector3(sx, sy, sz))
				lo = minf(lo, p.y)
	return lo


func _judge_static() -> void:
	var cfg = car.config
	var loads: Array = cfg.static_loads(9.8)
	var want_f: float = Suspension.static_compression(cfg.front_suspension, loads[0])
	var want_r: float = Suspension.static_compression(cfg.rear_suspension, loads[1])
	var c: Array = car.comp
	var err := maxf(maxf(absf(c[0] - want_f), absf(c[1] - want_f)), maxf(absf(c[2] - want_r), absf(c[3] - want_r)))
	var last: Array = _log[_log.size() - 1]
	var height_err: float = absf(last[1] - car.ride_height())
	fails += _check(err < 0.004, "static: each corner squashed by its share of the weight (front %.1f / rear %.1f mm, want %.1f / %.1f, off by %.1f mm at most)" % [
		(c[0] + c[1]) * 500.0, (c[2] + c[3]) * 500.0, want_f * 1000.0, want_r * 1000.0, err * 1000.0])
	fails += _check(height_err < 0.005, "static: at its ride height (%.3f m, want %.3f)" % [last[1], car.ride_height()])
	fails += _check(absf(last[2]) < 0.3 and absf(last[3]) < 0.1, "static: level (pitch %+.2f, roll %+.2f deg)" % [last[2], last[3]])
	fails += _check(car.linear_velocity.length() < 0.01 and car.grounded == 4, "static: still, on all four (%.3f m/s)" % car.linear_velocity.length())


func _judge_bounce() -> void:
	var cfg = car.config
	var loads: Array = cfg.static_loads(9.8)
	var f_front: float = Suspension.ride_frequency(cfg.front_suspension, loads[0] / 9.8)
	var f_rear: float = Suspension.ride_frequency(cfg.rear_suspension, loads[1] / 9.8)
	# swings through the settled height (counted once it's more than 1.5 mm past it
	# the other way: not the last sub-millimetre wobble), and what's left later
	var crossings: Array = []
	var side := 0.0
	for e in _log:
		var dy: float = e[1] - _y0
		if absf(dy) > 0.0015 and signf(dy) != side:
			if side != 0.0:
				crossings.append(e[0])
			side = signf(dy)
	var hz := 0.0
	if crossings.size() >= 2:
		hz = (crossings.size() - 1) / 2.0 / (crossings[crossings.size() - 1] - crossings[0])
	var after2 := 0.0
	var after3 := 0.0
	for e in _log:
		if e[0] - _lift_t > 2.0:
			after2 = maxf(after2, absf(e[1] - _y0))
		if e[0] - _lift_t > 3.0:
			after3 = maxf(after3, absf(e[1] - _y0))
	fails += _check(hz > 1.0 and hz < 1.8, "bounce: %.2f Hz (springs alone: front %.2f, rear %.2f Hz; damping slows it a little; %d swings)" % [
		hz, f_front, f_rear, crossings.size()])
	fails += _check(after2 < 0.006 and after3 < 0.002, "bounce: settles (from 50 mm: %.1f mm after 2 s, %.1f mm after 3 s)" % [after2 * 1000.0, after3 * 1000.0])


func _judge_drop() -> void:
	var landed := -1.0
	var unsettled := 0.0                             # the last time it was more than 5 mm off its ride height
	var hops := 0.0                                  # time with no wheel down after first touching
	var min_clear := INF
	var max_c := 0.0
	var dt := 1.0 / 120.0
	for e in _log:
		if landed < 0.0 and e[4] > 0:
			landed = e[0]
		if landed >= 0.0:
			if e[4] == 0:
				hops += dt
			min_clear = minf(min_clear, e[6])
			max_c = maxf(max_c, e[5])
			if absf(e[1] - car.ride_height()) > 0.005:
				unsettled = e[0]
	var last: Array = _log[_log.size() - 1]
	var travel: float = car.config.front_suspension.travel
	fails += _check(min_clear > 0.03, "drop 1 m: the body never touches the ground (lowest %.0f mm above it; deepest squash %.0f of %.0f mm travel)" % [
		min_clear * 1000.0, max_c * 1000.0, travel * 1000.0])
	fails += _check(hops < 0.05, "drop 1 m: no bounce back into the air (%.2f s with no wheel down after landing)" % hops)
	fails += _check(absf(last[1] - car.ride_height()) < 0.01 and car.linear_velocity.length() < 0.02,
		"drop 1 m: settled at its ride height (within 5 mm %.1f s after landing)" % (unsettled - landed))


func _judge_bumps() -> void:
	var pitch := 0.0
	var roll := 0.0
	for e in _log:
		pitch = maxf(pitch, absf(e[2]))
		roll = maxf(roll, absf(e[3]))
	fails += _check(pitch > 0.4 and roll < 0.3, "bumps: they pitch it (up to %.1f deg) without rolling it (%.2f deg)" % [pitch, roll])
	fails += _check(car.global_transform.basis.y.y > 0.99 and _log[_log.size() - 1][4] == 4, "bumps: still upright, all four down after")


func _judge_left_bumps() -> void:
	var roll := 0.0
	for e in _log:
		roll = maxf(roll, absf(e[3]))
	fails += _check(roll > 0.4, "left-side bumps: they roll it (up to %.1f deg)" % roll)
	fails += _check(car.global_transform.basis.y.y > 0.99, "left-side bumps: still upright")


## Steady state on the skid pad (the last 1.5 s): cornering force, slip angles, how steady.
func _judge_skid(deg: int) -> void:
	var a := 0.0
	var sf := 0.0
	var sr := 0.0
	var n := 0
	var yaw: Array = []
	for e in _log:
		if e[0] > _log[_log.size() - 1][0] - 1.5:
			a += e[7] * deg_to_rad(absf(e[8]))      # v x yaw rate: the cornering acceleration
			sf += absf(e[9])
			sr += absf(e[10])
			yaw.append(absf(e[8]))
			n += 1
	a /= n
	sf /= n
	sr /= n
	var spread: float = yaw.max() - yaw.min()
	_skid[deg] = {"a": a, "front": sf, "rear": sr}
	var base: float = car.config.rear_axle - car.config.front_axle
	var geo := 15.0 * 15.0 * deg_to_rad(deg) / base     # what the geometry alone would give (no slip)
	var mu_g: float = car.config.front_tire.lateral_mu * 9.8
	print("[physics]      skid pad, wheel at %2d deg: %.2f m/s² (%.2f g; geometry alone %.1f), slip front %.2f / rear %.2f deg, yaw rate steady within %.2f deg/s" % [
		deg, a, a / 9.8, geo, sf, sr, spread])
	if deg <= 4:
		fails += _check(spread < 0.2 and car.grounded == 4, "skid pad %d deg: a steady circle" % deg)
	else:                                            # at the limit it hunts, like a real car: it must hold on
		fails += _check(yaw.max() < 60.0 and car.grounded == 4 and car.global_transform.basis.y.y > 0.95,
			"skid pad %d deg: at the limit it holds on (no spin, no lift: yaw rate %.0f-%.0f deg/s)" % [deg, yaw.min(), yaw.max()])
	if deg <= 4:
		fails += _check(absf(a - minf(geo, mu_g)) < geo * 0.15, "skid pad %d deg: below the limit the car goes where it's steered (%.2f vs %.2f m/s²)" % [deg, a, geo])
	if deg == 15:
		# rises with the steering to the limit; past the fronts' peak slip it tops out (and
		# fades a little: steering past the peak scrubs)
		var order: bool = _skid[2].a < _skid[4].a and _skid[4].a < _skid[8].a and _skid[15].a > 0.85 * _skid[8].a
		fails += _check(order, "skid pad: more steering, more cornering force, until it tops out (%.1f, %.1f, %.1f, %.1f m/s²)" % [
			_skid[2].a, _skid[4].a, _skid[8].a, _skid[15].a])
		fails += _check(a > 0.75 * mu_g and a < 1.05 * mu_g, "skid pad 15 deg: at the tyres' grip and never past it (%.2f m/s², mu g = %.2f)" % [a, mu_g])


func _judge_side_slope() -> void:
	var start: Vector3 = Vector3.ZERO
	for e in _log:
		if e[0] >= 2.5:                              # settled on its springs (the body leans downhill first)
			start = e[11]
			break
	var last: Array = _log[_log.size() - 1]
	var across: Vector3 = car.global_transform.basis.x     # down the slope (phase 2 has no brakes: along the car it could roll)
	var drift: float = absf(((last[11] as Vector3) - start).dot(across))
	fails += _check(drift < 0.003 and absf(last[12]) < 0.001,
		"side slope %.0f deg, no brakes: the tyres hold it (%.1f mm in 2.5 s, %.2f mm/s at the end)" % [Lab.SLOPE_DEG, drift * 1000.0, absf(last[12]) * 1000.0])
	fails += _check(car.grounded == 4 and car.global_transform.basis.y.dot(Vector3.UP) > 0.95, "side slope: on all four, upright")


func _judge_straight() -> void:
	var yaw := 0.0
	var lat := 0.0
	for e in _log:
		if e[0] > 0.5:
			yaw = maxf(yaw, absf(e[8]))
			lat = maxf(lat, absf(e[12]))
	var turned := rad_to_deg(absf(wrapf(car.global_rotation.y - _yaw0, -PI, PI)))
	fails += _check(yaw < 0.5 and lat < 0.05 and turned < 0.5,
		"straight at 20 m/s: runs straight (yaw rate %.2f deg/s at most, %.3f m/s sideways, %.2f deg off its heading)" % [yaw, lat, turned])


func _max_slip() -> float:
	var m := 0.0
	for w in car.wheels:
		m = m if absf(m) > absf(w.slip_long) else w.slip_long
	return m


func _all_locked() -> bool:
	for w in car.wheels:
		if w.omega != 0.0:
			return false
	return true


## The car's mass with the four wheels' spin added (the drive spins them up too).
func _m_eff() -> float:
	var r: float = car.config.tyre_radius
	return car.mass + 4.0 * car.config.wheel_inertia / (r * r)


## Mean acceleration along the car between t0 and t1 (from the logged speed).
func _accel(t0: float, t1: float) -> float:
	var a: Array = []
	var b: Array = []
	for e in _log:
		if a.is_empty() and e[0] >= t0:
			a = e
		if e[0] <= t1:
			b = e
	return (b[13] - a[13]) / (b[0] - a[0])


func _judge_drive_gently() -> void:
	var r: float = car.config.tyre_radius
	var rr: float = car.config.front_tire.rolling_resistance
	var want: float = (4.0 * 400.0 / r - rr * car.mass * 9.8) / _m_eff()
	var got := _accel(0.5, 3.0)
	var slip := 0.0
	for e in _log:
		slip = maxf(slip, absf(e[14]))
	fails += _check(absf(got - want) < want * 0.05 and slip < 0.06,
		"400 N m on each wheel: %.2f m/s² (torque / mass with the wheels' inertia, minus rolling resistance: %.2f), slip ratio %.1f %% at most" % [got, want, slip * 100.0])


func _judge_wheelspin() -> void:
	var got := _accel(0.5, 2.0)
	var last: Array = _log[_log.size() - 1]
	var mu_g: float = car.config.front_tire.longitudinal_mu * 9.8
	fails += _check(last[14] > 0.3 and got > 0.6 * mu_g and got < 1.0 * mu_g,
		"2,500 N m on each wheel (more than the grip): wheelspin (slip ratio %.0f %%), %.2f m/s² (what the tyres can take: under mu g = %.1f)" % [last[14] * 100.0, got, mu_g])


func _judge_brake_gently() -> void:
	var r: float = car.config.tyre_radius
	var rr: float = car.config.front_tire.rolling_resistance
	var want: float = -(car.config.brake_torque * 0.3 / r + rr * car.mass * 9.8) / _m_eff()
	var got := _accel(0.3, 2.0)
	var slip := 0.0
	for e in _log:
		slip = maxf(slip, absf(e[14]))
	fails += _check(absf(got - want) < absf(want) * 0.07 and slip < 0.1,
		"brakes at 30 %%: %.2f m/s² (the brakes' torque / mass with the wheels: %.2f), no locking (slip %.1f %% at most)" % [got, want, slip * 100.0])


func _judge_brake_locked() -> void:
	var stop_t := -1.0
	var locked := 0
	var moving := 0
	for e in _log:
		if e[13] > 2.0:
			moving += 1
			if e[15]:
				locked += 1
		if stop_t < 0.0 and e[13] < 0.05:
			stop_t = e[0]
	var dist: float = (car.global_position - _v0).length()
	var v0 := 100.0 / 3.6
	var mean_decel := v0 / stop_t if stop_t > 0.0 else 0.0
	var mu_g: float = car.config.front_tire.longitudinal_mu * 9.8
	# (each wheel locks once its brake has beaten its grip and stopped its spin: the
	# rears, whose brakes only just beat their grip, take a moment longer)
	fails += _check(stop_t > 0.0 and locked > moving * 0.75,
		"full brakes from 100 km/h: all four wheels lock (for %d %% of the stop) and it stops, %.1f m in %.1f s" % [100 * locked / maxi(moving, 1), dist, stop_t])
	var kept := -TireModel.longitudinal_curve(car.config.front_tire, -1.0)   # a locked tyre's share of its grip
	fails += _check(mean_decel > (kept - 0.08) * mu_g and mean_decel < (kept + 0.06) * mu_g,
		"full brakes: it slides on locked tyres, %.2f m/s² (%.2f g; a locked tyre keeps %.0f %% of its grip)" % [
			mean_decel, mean_decel / 9.8, kept * 100.0])


func _judge_coast() -> void:
	var rr: float = car.config.front_tire.rolling_resistance
	var want: float = -rr * car.mass * 9.8 / _m_eff()
	var got := _accel(0.5, 3.0)
	fails += _check(absf(got - want) < absf(want) * 0.15, "coasting at 20 m/s: rolling resistance slows it %.3f m/s² (want %.3f)" % [got, want])


func _judge_slope_braked() -> void:
	var start: Vector3 = Vector3.ZERO
	for e in _log:
		if e[0] >= 1.5:
			start = e[11]
			break
	var moved: float = (car.global_position - start).length()
	fails += _check(moved < 0.003 and absf(car.linear_velocity.length()) < 0.002,
		"nose up a %.0f deg slope, brakes on: it holds (%.1f mm in 2.5 s)" % [Lab.SLOPE_DEG, moved * 1000.0])


func _judge_slope_rolling() -> void:
	var rr: float = car.config.front_tire.rolling_resistance
	var th := deg_to_rad(Lab.SLOPE_DEG)
	var want: float = -(car.mass * 9.8 * (sin(th) - rr * cos(th))) / _m_eff()
	var got := _accel(0.3, 1.8)
	fails += _check(absf(got - want) < absf(want) * 0.1, "brakes off: it rolls back down, %.2f m/s² (gravity minus rolling resistance: %.2f)" % [got, want])


## Acceleration across and along the car's path (m/s², horizontal) from a log row.
func _lat_long(e: Array) -> Vector2:
	var a: Vector3 = e[16]
	var v: Vector3 = e[17]
	a.y = 0.0
	v.y = 0.0
	var d := v.normalized()
	var along := a.dot(d)
	return Vector2((a - d * along).length(), along)


func _judge_brake_in_turn() -> void:
	var before := 0.0
	var nb := 0
	var during := 0.0
	var nd := 0
	var most := 0.0
	for e in _log:
		var al := _lat_long(e)
		if e[0] > 3.0 and e[0] < 4.0:
			before += al.x
			nb += 1
		if e[0] > 4.3 and e[0] < 5.3:
			during += al.x
			nd += 1
		if e[0] > 3.0:
			most = maxf(most, al.length())
	before /= nb
	during /= nd
	var mu_g: float = car.config.front_tire.lateral_mu * 9.8
	fails += _check(during < 0.85 * before, "braking at the cornering limit: it loses cornering grip (%.1f m/s² across before, %.1f braking)" % [before, during])
	fails += _check(most < 1.05 * mu_g, "braking at the limit: braking and cornering together never pass the grip (%.1f m/s² at most, mu g = %.1f)" % [most, mu_g])


## How much the car rotates for its steering, entering a 2.5 degree turn at 20 m/s:
## yaw rate / the yaw rate the geometry would give at that speed (1 = neutral).
func _yaw_gain() -> float:
	var base: float = car.config.rear_axle - car.config.front_axle
	var g := 0.0
	var n := 0
	for e in _log:
		if e[0] > 0.5 and e[0] < 1.3 and absf(e[18]) > 0.01:
			g += deg_to_rad(absf(e[8])) / (e[13] * absf(e[18]) / base)
			n += 1
	return g / maxi(n, 1)


func _judge_turn_in_coasting() -> void:
	_turn["coasting"] = _yaw_gain()
	var rear := 0.0
	for e in _log:
		rear = maxf(rear, absf(e[10]))
	print("[physics]      turning in, coasting: yaw for the steering %.2f, rear slip %.1f deg at most" % [_turn.coasting, rear])


func _judge_turn_in_braking() -> void:
	var g := _yaw_gain()
	var rear := 0.0
	var front := 0.0
	for e in _log:
		rear = maxf(rear, absf(e[10]))
		front = maxf(front, absf(e[9]))
	fails += _check(g > _turn.coasting * 1.05, "trail braking: entering the turn on the brakes rotates the car more (yaw for the steering %.2f vs %.2f coasting)" % [
		g, _turn.coasting])
	fails += _check(rear < 12.0, "trail braking: the tail steps out, it doesn't spin (rear slip %.1f deg at most, front %.1f)" % [rear, front])


func _judge_load() -> void:
	var t: Resource = car.config.front_tire
	var nominal: float = t.nominal_load
	var py := tan(deg_to_rad(t.lateral_peak_deg))
	var per_n_1: float = TireModel.combined(t, 0.0, py, nominal, 1.0, TireModel.load_mu_factor(t, nominal)).y / nominal
	var per_n_2: float = TireModel.combined(t, 0.0, py, 2.0 * nominal, 1.0, TireModel.load_mu_factor(t, 2.0 * nominal)).y / (2.0 * nominal)
	fails += _check(per_n_2 < per_n_1 and absf(per_n_2 / per_n_1 - (1.0 - t.load_sensitivity)) < 0.01,
		"load sensitivity: a tyre with twice the load grips %.0f %% less per newton (%.3f vs %.3f)" % [(1.0 - per_n_2 / per_n_1) * 100.0, per_n_2, per_n_1])


func _check(ok: bool, msg: String) -> int:
	print("[physics] %s %s" % ["ok  " if ok else "FAIL", msg])
	return 0 if ok else 1


func _done() -> bool:
	fails += _check(Engine.physics_ticks_per_second == 120, "running at %d ticks a second" % Engine.physics_ticks_per_second)
	print("[physics] %s" % ("PHYSICS V2 OK" if fails == 0 else "PHYSICS V2 FAIL"))
	quit(1 if fails > 0 else 0)
	return true
