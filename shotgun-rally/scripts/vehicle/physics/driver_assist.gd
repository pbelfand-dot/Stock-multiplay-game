extends RefCounted
## The driver aids (an AssistConfig), each on or off on its own. They sit
## between the controls and the car and change only what each wheel's brake,
## the throttle and the steering are asked for:
##   * ABS: a braking wheel past its tyre's peak slip gets its brake eased off,
##     in proportion, so it brakes near the peak and can still steer
##   * traction control: holds the driven wheels' spin at their tyres' peak (less while they
##     corner: the combined-slip ellipse), from what the tyres can take, never cutting below the
##     throttle where the engine neither drives nor brakes
##   * stability control: compares the car's yaw rate with what the steering
##     asks for (as far as the grip allows) and brakes one wheel to turn it back:
##     sliding round too far, the outside front; not turning enough, the inside rear
##   * steering smoothing (keys: the steering ramps in, slower the faster it's
##     going, and back out quicker; a stick: only a touch of filtering, it's
##     analog already), damping (slower at speed), speed-sensitive steering
##     (full input = the most angle the front tyres can use at this speed, the
##     rest in proportion, so all of a stick's travel means something at 200
##     km/h; not while the handbrake's pulled: a hairpin flick wants all the
##     lock) and countersteer help (sliding, the front wheels pointed where the
##     car is going)
##   * drift assist (an arcade aid: the one that also pushes on the body): in a
##     drift your steering sets the angle: into the corner more (up to ~40 deg,
##     with the throttle), let go and it straightens, countersteer and it
##     straightens quicker; it steers the front wheels for it and turns the body
##     toward that angle, damped, and never lets it swing round into a spin
##     (_drift_state, drift_torque); below ~25 km/h it steps aside (a U-turn, a
##     tight hairpin are the driver's). With it on it does countersteer help's job
##   * high-speed stability (an arcade aid too): from ~90 km/h it damps yaw the
##     steering didn't ask for: lane changes settle at once, a clip is caught
##     (stability_torque)
## With them all on, a car driven inside its grip does exactly what it does
## with them off.

const TireModel = preload("res://scripts/vehicle/physics/tire_model.gd")
const EngineModel = preload("res://scripts/vehicle/physics/engine.gd")

var cfg: Resource                  # AssistConfig
var abs_ease := [1.0, 1.0, 1.0, 1.0]   # each wheel's share of its pedal brake ABS leaves on
var tc_cut := 1.0                  # the throttle share traction control leaves
var _tc_i := 1.0                   # (its integral part: where the throttle sits with the slip at the target)
var _esc_ref := 0.0                # stability control's reference yaw rate (rad/s: the steering's, lagged as the car's yaw is)
var esc_wheel := -1                # the wheel stability control is braking (-1: none) ...
var esc_torque := 0.0              # ... with this much (N m)
var esc_cut := 1.0                 # the throttle share stability control leaves (sliding round)
var countersteer := 0.0            # rad the countersteer help turned the wheels (+ = right)
var drift_hold := 0.0              # N m the drift assist is turning the body with (+ = to the left)
var stability_hold := 0.0          # N m high-speed stability is turning the body with (+ = to the left)
var drifting := false              # drift assist sees a drift
var _beta := 0.0                   # the body's slip angle last tick (rad)
var _beta_rate := 0.0              # how fast it's changing (rad/s, smoothed)
var _drift_want := 0.0             # the angle the driver's asking for (rad, signed like the slip)
var _drift_err := 0.0              # the slip past it (rad, signed)
var _drift_boost := 1.0            # countersteering: straighten up quicker
var _drift_slow := 1.0             # 0: a slow handbrake turn, left alone .. 1: the assist's own

var _smooth := 0.0
var _counter_k := 0.0              # (SIM street) how much countersteering room is open (0..1)
var understeer := -1.0             # (SIM street) the car's understeer gradient as driven (rad per g; learned, _learn)
var _lat_prev := 0.0               # (its lateral g a tick ago: steady cornering only)


func setup(assists: Resource) -> void:
	cfg = assists
	reset()


func reset() -> void:
	abs_ease = [1.0, 1.0, 1.0, 1.0]
	tc_cut = 1.0
	esc_wheel = -1
	esc_torque = 0.0
	esc_cut = 1.0
	_counter_k = 0.0
	_tc_i = 1.0
	_esc_ref = 0.0
	_lat_prev = 0.0
	countersteer = 0.0
	drift_hold = 0.0
	stability_hold = 0.0
	drifting = false
	_beta = 0.0
	_beta_rate = 0.0
	_drift_want = 0.0
	_drift_err = 0.0
	_drift_slow = 1.0
	_smooth = 0.0


## Any aid on?
func any() -> bool:
	return cfg.anti_lock or cfg.traction_control or cfg.stability_control or cfg.steering_smoothing \
		or cfg.steering_damping or cfg.countersteer_help or cfg.speed_sensitive_steering or cfg.drift_assist \
		or cfg.high_speed_stability


## Where the steering asks the front wheels to point (the rack, rad, + = right)
## and how fast they may turn there (a share of the rack's speed).
func steering(car, dt: float, input: float) -> Vector2:
	var v := absf(float(car.speed))
	var street := _street(car)
	# (SIM street: sliding, or the handbrake pulled, the keys stay as quick as the rally's: a slide is caught
	# and a drift held by quick hands)
	var catching := street and (absf(body_slip(car)) > deg_to_rad(cfg.counter_from_deg) or float(car.inp.handbrake) > 0.05)
	var s := _ease(input, v, bool(car.inp.get("analog", false)), dt, street and not catching)
	var lock := deg_to_rad(car.config.steering.max_angle_deg)
	var target := angle_for(car, s)
	var rate := 1.0
	if cfg.steering_damping:
		rate = clampf(cfg.damping_speed / maxf(v, 0.1), 0.35, 1.0)
	countersteer = 0.0
	var align := _front_travel(car, lock)
	if street:
		_learn(car, dt, v)
		# sliding, steering toward the slide may reach where the front axle's going plus the
		# front tyres' peak slip angle (the driver catches it: nothing steers for them)
		var beta := absf(body_slip(car))
		var open := clampf((beta - deg_to_rad(cfg.counter_from_deg)) / maxf(deg_to_rad(cfg.counter_full_deg - cfg.counter_from_deg), 0.001), 0.0, 1.0)
		_counter_k = move_toward(_counter_k, open, dt / cfg.counter_time)
		if _counter_k > 0.0 and absf(s) > 0.0 and signf(s) == signf(align):
			var room: float = absf(align) + deg_to_rad(car.wheels[0].surface_tire.lateral_peak_deg)
			target = signf(s) * minf(maxf(absf(target), lerpf(absf(target), absf(s) * room, _counter_k)), lock)
	_drift_state(car, dt, s, v)
	if drifting:
		# drift assist steers: the fronts a little inside where the front axle's going
		# (a held drift needs the front tyres working too, or the rear's grip swings
		# it straight), plus more countersteer while the slide's past the angle you're
		# asking for (less while it's short of it); countersteering straightens it quicker
		var bite: float = deg_to_rad(car.wheels[0].surface_tire.lateral_peak_deg) * cfg.drift_front_bite * -signf(_beta)
		if absf(_drift_want) < 1e-3:
			bite = 0.0
		var steer_to: float = clampf(align + bite + cfg.drift_steer_gain * _drift_err * _drift_boost, -lock, lock)
		steer_to = lerpf(target, steer_to, _drift_slow)         # (slow: the driver's own steering)
		countersteer = steer_to - target
		target = steer_to
	elif cfg.countersteer_help and v > 3.0 and not cfg.drift_assist:
		var rear := (absf(car.wheels[2].slip_angle_deg()) + absf(car.wheels[3].slip_angle_deg())) * 0.5
		var k: float = clampf((rear - cfg.countersteer_from_deg) / maxf(cfg.countersteer_full_deg - cfg.countersteer_from_deg, 0.5),
			0.0, 1.0) * cfg.countersteer_strength
		if k > 0.0:
			var blended := lerpf(target, align, k)
			countersteer = blended - target
			target = blended
	return Vector2(target, rate)


## The front axle's direction of travel, relative to the car (rad, + = to its right).
func _front_travel(car, lock: float) -> float:
	var xf: Transform3D = car.global_transform
	var p: Vector3 = xf * Vector3(0.0, 0.0, car.config.front_axle)
	var vf: Vector3 = car.linear_velocity + car.angular_velocity.cross(p - xf * car.center_of_mass)
	var local := xf.basis.transposed() * vf
	return clampf(atan2(local.x, -local.z), -lock, lock)


## The body's slip angle: between where it points and where it's going (rad,
## + = going to the right of where it points: the nose swung left), 0 crawling.
static func body_slip(car) -> float:
	var b: Basis = car.global_transform.basis
	var v: Vector3 = car.linear_velocity
	var fwd := v.dot(-b.z)
	var side := v.dot(b.x)
	if fwd * fwd + side * side < 4.0:
		return 0.0
	return atan2(side, fwd)


## Drift assist's reading of the slide, each tick (with the steering): drifting
## once the body's past drift_enter_deg (out again under drift_exit_deg, or slow),
## the angle the driver asks for, and how far off it the slide is.
##   * steering into the corner asks for up to drift_angle_deg (more throttle,
##     more of it: off the throttle it settles at drift_lift_share of that); the
##     angle on offer shrinks at speed (drift_fast_deg at drift_fast_speed): at
##     200 km/h a drift is a twitch, not a slide
##   * letting go asks for none: it straightens up; countersteering too, quicker
##   * with the handbrake pulled it doesn't straighten (the flick's the point),
##     it only stops it swinging past the angle
func _drift_state(car, dt: float, s: float, v: float) -> void:
	var beta := body_slip(car)
	var was := drifting
	if not cfg.drift_assist or int(car.grounded) < 2 or absf(beta) > deg_to_rad(100.0) or v < cfg.drift_min_speed * 0.5:
		drifting = false
	elif drifting:
		drifting = absf(beta) > deg_to_rad(cfg.drift_exit_deg)
	else:
		drifting = absf(beta) > deg_to_rad(cfg.drift_enter_deg)
	_beta_rate = 0.0 if not was else lerpf(_beta_rate, (beta - _beta) / dt, clampf(dt * 30.0, 0.0, 1.0))
	_beta = beta
	if not drifting:
		_drift_err = 0.0
		_drift_want = 0.0
		return
	var side := signf(beta)
	var into := clampf(-s * side, -1.0, 1.0)              # + = steering into the corner (the way it's turning)
	var fast: float = clampf((v - cfg.drift_full_speed) / maxf(cfg.drift_fast_speed - cfg.drift_full_speed, 1.0), 0.0, 1.0)
	var most: float = deg_to_rad(lerpf(cfg.drift_angle_deg, cfg.drift_fast_deg, fast))
	var thr := clampf(float(car.inp.throttle), 0.0, 1.0)
	var want: float = maxf(into, 0.0) * most * lerpf(cfg.drift_lift_share, 1.0, thr)
	_drift_slow = clampf((v - cfg.drift_uturn_speed) / maxf(cfg.drift_uturn_speed * 0.5, 0.1), 0.0, 1.0)
	if float(car.inp.handbrake) > 0.05:
		var room: float = lerpf(PI, most + deg_to_rad(cfg.drift_handbrake_deg), _drift_slow)
		want = maxf(want, minf(absf(beta), room))
	# the angle it holds moves toward what's asked for at drift_angle_rate (from the
	# slip it had when the drift began): letting go eases it straight rather than
	# snapping it, so keys can hold an angle between on and off
	_drift_boost = 1.0 + maxf(-into, 0.0) * cfg.drift_counter_boost
	var held := absf(beta) if not was or signf(_drift_want) != side else absf(_drift_want)
	held = move_toward(held, want, deg_to_rad(cfg.drift_angle_rate) * _drift_boost * dt)
	_drift_want = side * held
	_drift_err = beta - _drift_want


## Drift assist: the turning force (N m, round the car's up axis, + = to the
## left) that brings the slide to the angle asked for: in proportion to how far
## off it is (gently while it's short of it: the throttle and the fronts do
## that, firmly while it's past it), damped by how fast the angle's changing (no
## overshoot, no tank-slapper straightening up), and well past the angle a hard
## stop (no spin). Fades out at walking pace.
func drift_torque(car) -> float:
	drift_hold = 0.0
	if not drifting:
		return 0.0
	var full: float = cfg.drift_strength * float(car.mass) * 9.8 * (car.config.rear_axle - car.config.front_axle)
	var side := signf(_beta)
	var past := _drift_err * side                         # + = more angle than asked for
	var t: float = -side * full * (past * (1.0 if past > 0.0 else float(cfg.drift_grow_share))) * _drift_boost
	t -= full * cfg.drift_damping * _beta_rate
	var over := absf(_beta) - absf(_drift_want) - deg_to_rad(cfg.drift_stop_deg)
	if over > 0.0:
		t -= side * full * over * 4.0
	var spd: float = car.linear_velocity.length()
	t = clampf(t, -full * 1.5, full * 1.5) * clampf((spd - cfg.drift_min_speed * 0.5) / (cfg.drift_min_speed * 0.5), 0.0, 1.0) * _drift_slow
	drift_hold = t
	return drift_hold


## High-speed stability (an arcade aid, its own switch): from hs_from_speed,
## at full strength by hs_full_speed, a turning force against any yaw beyond what
## the steering asks for (the turn the front wheels' angle makes at this speed,
## as far as the grip allows): a wobble after a lane change, a tail kicked out by
## a clip, a twitch, damped at once. It never adds turn the car isn't making, and
## stays out of a drift you're steering into or a handbrake turn.
func stability_torque(car) -> float:
	stability_hold = 0.0
	if not cfg.high_speed_stability or int(car.grounded) < 2 or float(car.inp.handbrake) > 0.05:
		return 0.0
	var v: float = car.linear_velocity.length()
	var k: float = clampf((v - cfg.hs_from_speed) / maxf(cfg.hs_full_speed - cfg.hs_from_speed, 1.0), 0.0, 1.0)
	if k <= 0.0 or (drifting and absf(_drift_want) > deg_to_rad(cfg.drift_enter_deg)):
		return 0.0
	var base: float = car.config.rear_axle - car.config.front_axle
	var mu: float = 0.5 * (car.wheels[0].surface_tire.lateral_mu + car.wheels[2].surface_tire.lateral_mu)
	var r_max := mu * 9.8 / maxf(v, 1.0)
	var want := clampf(-v * tan(float(car.steer)) / base, -r_max, r_max)   # rad/s it asks for (+ = left)
	var r: float = car.angular_velocity.dot(car.global_transform.basis.y)
	var extra := r - want
	if signf(r) == signf(want) and absf(r) < absf(want):
		extra = 0.0                                   # turning less than asked: not its business
	var full: float = float(car.mass) * 9.8 * base
	var beta := body_slip(car)
	if _street(car):
		# (SIM street: a car cornering hard runs a degree or two of body slip; damping that pushed the
		# rears to grip less and the car turned less than it was steered. Only a slide past it counts)
		beta = signf(beta) * maxf(absf(beta) - deg_to_rad(cfg.hs_street_slip_from_deg), 0.0)
	var t: float = -full * (float(cfg.hs_yaw_damping) * extra + float(cfg.hs_slip_damping) * beta) * k
	stability_hold = clampf(t, -full * 0.6, full * 0.6)
	return stability_hold


## The front wheels' angle for this much steering input (rad, + = right): the
## input x the lock, or with speed-sensitive steering (and the handbrake off) a
## share of the front tyres' grip: half a stick asks for half of what they can
## give at this speed, all of it for speed_sensitive_grip of it: the geometry of
## that turn plus the slip angle the tyre's curve needs for that much force. So
## all of a stick's travel means something at 200 km/h (a fifth of it, a fifth
## of the grip), and full input never ploughs on past the tyres' peak.
func angle_for(car, s: float) -> float:
	var lock := deg_to_rad(car.config.steering.max_angle_deg)
	var v := absf(float(car.speed))
	if not cfg.speed_sensitive_steering or v <= 1.0 or float(car.inp.handbrake) >= 0.05:
		return s * lock
	var t: Resource = car.wheels[0].surface_tire
	var base: float = car.config.rear_axle - car.config.front_axle
	if _street(car):
		# SIM street: the stick asks for that share of the grip, through the turn's geometry
		# and the car's understeer; the last of the travel adds the front tyres' peak slip
		var most: float = t.lateral_mu                  # (the most it corners at: its tyres, or the real car's skid pad if less)
		var st = car.get("street")
		if st != null and (st as Array).size() > 0:
			most = minf(most, float(st[0]))
		if not bool(car.inp.get("analog", false)):
			# (keys: a race car's tyres as they are now, cold, worn, wet: a held key asks for the grip they
			# have; 1 for every other car. A stick, and the AI driving with one, keeps the whole range)
			most *= 0.25 * (float(car.wheels[0].race_mu) + float(car.wheels[1].race_mu) + float(car.wheels[2].race_mu) + float(car.wheels[3].race_mu))
		var a: float = clampf(absf(s), 0.0, 1.0) * cfg.street_grip_share * most * 9.8
		if understeer < 0.0:
			understeer = deg_to_rad(float(car.config.understeer))
		var d: float = atan(base * a / (v * v)) + understeer * a / 9.8
		var last: float = clampf((absf(s) - cfg.street_peak_from) / maxf(1.0 - cfg.street_peak_from, 0.01), 0.0, 1.0)
		if not bool(car.inp.get("analog", false)):
			# keys: a held key is a hard turn, not the fronts pushed past their peak (at 200 km/h that swung
			# the wheels from 0.5 to 7.7 deg and ploughed on, smoking): the peak's slip only slowly (a hairpin)
			last *= 1.0 - _street_fast(v)
		d += last * deg_to_rad(t.lateral_peak_deg)
		return signf(s) * minf(d, lock)
	var f: float = clampf(absf(s), 0.0, 1.0) * cfg.speed_sensitive_grip
	var geometry: float = atan(base * t.lateral_mu * 9.8 * f / (v * v))
	var c: float = t.lateral_shape
	var x: float = tan(asin(f) / c) / (tan(PI / (2.0 * c)) / tan(deg_to_rad(t.lateral_peak_deg)))
	return signf(s) * minf(geometry + atan(x), lock)


## Steering smoothing: the input eased (-1..1). A stick (analog) only filtered
## a touch; keys ramp in at key_rate_slow per second up to key_rate_from m/s,
## easing to key_rate_fast by key_rate_to (a tap is a small, quick correction at
## 200 km/h, all of it at a hairpin), and back out key_return times quicker. SIM
## street (`street`: not while sliding) ramps by street_key_rate instead.
func _ease(input: float, v: float, analog: bool, dt: float, street := false) -> float:
	if not cfg.steering_smoothing:
		_smooth = input
	elif analog:
		_smooth += (input - _smooth) * (1.0 - exp(-dt / cfg.smoothing_time))
	else:
		var up: float = lerpf(cfg.key_rate_slow, cfg.key_rate_fast,
			clampf((v - cfg.key_rate_from) / maxf(cfg.key_rate_to - cfg.key_rate_from, 1.0), 0.0, 1.0))
		if street:
			# SIM street: in proportion to the time held, slower the faster it's going (the stick asks for a
			# share of the grip, so this is how fast the cornering builds): key_rate_slow up to key_rate_from,
			# street_key_rate from street_key_to (between, in proportion on a log scale): at 200 km/h a 0.3 s
			# tap is a lane change (~0.2 g), a key held 1.3 s all the grip. (It was a lane change's worth at
			# once and all of it after a second, the fronts pushed past their peak.)
			up = cfg.key_rate_slow * pow(cfg.street_key_rate / cfg.key_rate_slow, _street_fast(v))
		var goal := input
		var outward := absf(goal) > absf(_smooth) and (signf(goal) == signf(_smooth) or absf(_smooth) < 1e-4)
		_smooth = move_toward(_smooth, goal, (up if outward else up * cfg.key_return) * dt)
	return _smooth


## (SIM street) 0 at key_rate_from or slower .. 1 at street_key_to or faster.
func _street_fast(v: float) -> float:
	return clampf((v - cfg.key_rate_from) / maxf(cfg.street_key_to - cfg.key_rate_from, 1.0), 0.0, 1.0)


## (SIM street) Learns the car's understeer as it's driven: in a steady corner (gripping,
## not braking, its cornering g barely changing) the front wheels' angle past the turn's
## geometry, per g, eased toward over learn_time. Every car's is its own (its tyres, its
## weight split, its bars: a GT3 ~0.3 deg/g, an SUV more), and it grows near the limit;
## steering through it, half a stick is half the grip whatever the car.
func _learn(car, dt: float, v: float) -> void:
	if understeer < 0.0:
		understeer = deg_to_rad(float(car.config.understeer))
	var r: float = car.angular_velocity.dot(car.global_transform.basis.y)
	var lat := v * absf(r) / 9.8                      # its cornering g (steady: v x yaw rate)
	var steady: bool = absf(lat - _lat_prev) < float(cfg.learn_steady) * dt
	_lat_prev = lat
	if int(car.grounded) < 4 or v < 12.0 or lat < cfg.learn_from_g or not steady or float(car.inp.brake) > 0.1 \
			or float(car.inp.handbrake) > 0.05 or absf(body_slip(car)) > deg_to_rad(4.0):
		return
	var steer := absf(float(car.steer))
	if signf(float(car.steer)) != -signf(r):         # (steering the way it's turning: + steer = right, + r = left)
		return
	var base: float = car.config.rear_axle - car.config.front_axle
	var seen := clampf((steer - atan(base * lat * 9.8 / (v * v))) / lat, 0.0, deg_to_rad(cfg.learn_most_deg))
	understeer += (seen - understeer) * clampf(dt / cfg.learn_time, 0.0, 1.0)


## SIM street handling on for this car (its own road tyres: Catalog.street_grip)?
static func _street(car) -> bool:
	var st = car.get("street")
	return st != null and not (st as Array).is_empty()


## The steering input that gets the wheels to `target` (a share of the lock,
## -1..1) this tick through the smoothing and speed-sensitive steering: what a
## driver who knows the car presses (the autopilot drives with it, as a stick,
## so the aids' easing doesn't make it weave).
func input_for(car, target: float, dt: float) -> float:
	var lock := deg_to_rad(car.config.steering.max_angle_deg)
	var goal := absf(target) * lock
	var lo := 0.0
	var hi := 1.0
	if angle_for(car, 1.0) <= goal:
		lo = 1.0
	else:
		for i in 14:                                   # (angle_for rises with the input: halve the gap)
			var mid := 0.5 * (lo + hi)
			if angle_for(car, mid) < goal:
				lo = mid
			else:
				hi = mid
	var want := signf(target) * lo
	if not cfg.steering_smoothing:
		return want
	var a := 1.0 - exp(-dt / cfg.smoothing_time)
	return clampf(_smooth + (want - _smooth) / a, -1.0, 1.0)


## The throttle after traction control (and stability control's cut while it catches a slide).
func throttle(car, dt: float, thr: float) -> float:
	if cfg.stability_control:
		thr *= esc_cut
	if not cfg.traction_control or car.drivetrain == null:
		tc_cut = 1.0
		return thr
	var dir := signf(car.drivetrain.ratio())
	var front: float = car.drivetrain.split()
	var worst := -1.0
	for k in 4:
		var w = car.wheels[k]
		if not w.grounded or (front <= 0.01 and k < 2) or (front >= 0.99 and k >= 2):
			continue
		var t: Resource = w.surface_tire
		# a driven wheel's spin against what its tyre can use: its peak slip ratio (x tc_target), less what
		# the grip sideways takes (the combined-slip ellipse: cornering hard, it may spin less), so the tyre
		# keeps its grip sideways under power; before, it let the spin run a band past the peak and the
		# rears, spinning, lost their grip sideways (a GT3 on cold slicks spun on a tap of steering)
		var spin: float = dir * (w.omega * w.radius - w.v_long) / maxf(absf(w.v_long), cfg.tc_low_speed)
		var side: float = absf(w.slip_lat) / maxf(tan(deg_to_rad(t.lateral_peak_deg)), 0.005)
		var room: float = sqrt(maxf(1.0 - side * side, 0.0))
		worst = maxf(worst, spin - t.longitudinal_peak * cfg.tc_target * room)
		# (and a driven axle sliding sideways past its peak: power oversteer, the tail stepping out
		# on the throttle, as the real systems count it; tc_side_band of a peak's worth past it cuts it all)
		worst = maxf(worst, (side - 1.0) * cfg.tc_band / cfg.tc_side_band)
	# what the driven tyres can take at that spin (the throttle that makes it: _tc_room), trimmed by how
	# the spin's actually going (the integral part), and a sudden spin caught at once. Before, it cut on
	# the spin alone: to nothing and back, again and again, pulling away at a third of the grip
	_tc_i = clampf(_tc_i - dt * cfg.tc_gain * worst / cfg.tc_band, 0.3, 1.3)
	var want := clampf(_tc_room(car) * _tc_i - maxf(worst - 0.5 * cfg.tc_band, 0.0) / cfg.tc_band, 0.0, 1.0)
	tc_cut = move_toward(tc_cut, want, dt * (12.0 if want < tc_cut else 6.0))
	# never below the throttle where the engine neither drives nor brakes the wheels (as the real systems'
	# engine drag control): cutting to nothing was a lift, the engine braking the rears mid-corner, and the
	# lift-off oversteer spun the car it was catching
	return maxf(thr * tc_cut, minf(thr, _throttle_for(car.drivetrain, 0.0)))


## The throttle that makes `need` N m at the crank past the engine's own friction at these revs
## (EngineModel.friction: more with the throttle shut): torque x thr = need + f0 + (1 - thr) c.
static func _throttle_for(d, need: float) -> float:
	var e: Resource = d.eng
	var r: float = maxf(d.rpm(), 0.0)
	var full: float = d.gross_torque(r, 1.0) + maxf(float(d.extra_torque), 0.0)
	var f0: float = e.friction + e.friction_per_rpm * r
	var c: float = e.closed_throttle_per_rpm * r + e.regen_torque * clampf(r / maxf(e.limiter_rpm * 0.05, 1.0), 0.0, 1.0)
	return clampf((need + f0 + c) / maxf(full + c, 1.0), 0.0, 1.0) if need < INF else 1.0


## (Traction control) The throttle share whose torque (past the engine's own friction) the
## driven tyres can just take, each at its target spin with its grip sideways as it is now (the
## combined slip: TireModel.combined), axle by axle as the centre diff shares the drive (an open
## diff: twice the lighter side's); above 1 the engine can't spin them. A real system's
## tyre-force estimate, so it holds the spin where the tyres pull hardest instead of hunting.
func _tc_room(car) -> float:
	var d = car.drivetrain
	var g: float = absf(d.ratio())
	if g <= 0.0 or d.shifting():
		return 1.0
	var b: float = d.split()
	var need := INF                                  # N m at the crank the tyres can take
	for axle in 2:
		var share: float = b if axle == 0 else 1.0 - b
		if share < 0.01:
			continue
		var f := [0.0, 0.0]
		for side in 2:
			var w = car.wheels[axle * 2 + side]
			if not w.grounded:
				continue
			var t: Resource = w.surface_tire
			var lf: float = TireModel.load_mu_factor(t, w.load) * w.surface_mu * w.race_mu
			f[side] = TireModel.combined(t, t.longitudinal_peak * cfg.tc_target, w.slip_lat, w.load,
				t.longitudinal_mu * lf, t.lateral_mu * lf).x
		var diff: Resource = d.cfg.front_diff if axle == 0 else d.cfg.rear_diff
		var open: bool = diff == null or int(diff.kind) == 0
		var axle_f: float = 2.0 * minf(f[0], f[1]) if open else f[0] + f[1]
		need = minf(need, axle_f * float(car.wheels[axle * 2].radius) / (g * share * d.efficiency))
	return _throttle_for(d, need)


## Each wheel's brake torque: the pedal's (eased by ABS) and stability control's.
func brakes(car, dt: float, pedal: Array) -> Array:
	var out := pedal.duplicate()
	for k in 4:
		var w = car.wheels[k]
		var want := 1.0
		if cfg.anti_lock and w.grounded and absf(w.v_long) > 2.0:
			var past: float = -w.slip_long * signf(w.v_long) - w.surface_tire.longitudinal_peak   # locking past the peak
			want = clampf(1.0 - past / cfg.abs_band, 0.0, 1.0)
		abs_ease[k] = move_toward(abs_ease[k], want, dt * 30.0)
		out[k] = pedal[k] * abs_ease[k]
	_stability(car, dt)
	if esc_wheel >= 0:
		out[esc_wheel] += esc_torque
	return out


## Stability control: the yaw rate the steering asks for (as far as the grip allows,
## through the car's understeer, lagged by esc_ref_time as a car's yaw follows its steering:
## a real ESC's reference model) against the car's, plus the body's slip angle past
## esc_slip_deg (a wide slide the yaw rate misses); off by more than the deadband, one wheel's brake turns it back (sliding
## round: the outside front; not turning enough: the inside rear), harder on a heavier
## car, and sliding round it cuts the engine too, as a real ESC does.
func _stability(car, dt := 1.0 / 120.0) -> void:
	esc_wheel = -1
	esc_torque = 0.0
	var v := float(car.speed)
	if not cfg.stability_control or v < 5.0 or float(car.inp.handbrake) > 0.05:
		esc_cut = 1.0
		_esc_ref = car.angular_velocity.dot(car.global_transform.basis.y)
		return
	var base: float = car.config.rear_axle - car.config.front_axle
	var mu: float = 0.5 * (car.wheels[0].surface_tire.lateral_mu + car.wheels[2].surface_tire.lateral_mu)
	var r_max := mu * 9.8 / v
	# (a steady corner's yaw rate for this steering: v x angle / (wheelbase + understeer x v²); the
	# wheelbase alone asked a road car for more turn than it makes, and the instant's steering, unlagged,
	# read every unwinding of the wheel as a slide: it braked a wheel and cut the engine in lane changes)
	var us: float = understeer if understeer >= 0.0 else deg_to_rad(float(car.config.understeer))
	var now := clampf(-v * tan(float(car.steer)) / (base + us / 9.8 * v * v), -r_max, r_max)
	_esc_ref += (now - _esc_ref) * clampf(dt / maxf(cfg.esc_ref_time, dt), 0.0, 1.0)
	var want := _esc_ref                            # yaw rate it asks for (+ = left)
	var r: float = car.angular_velocity.dot(car.global_transform.basis.y)
	var e := want - r                               # the yaw it needs to add (+ = to the left)
	var beta := body_slip(car)                      # (+ = going right of where it points: the nose swung left)
	var past := absf(beta) - deg_to_rad(cfg.esc_slip_deg)
	if past > 0.0:
		e -= signf(beta) * past * cfg.esc_slip_gain
	var dead: float = cfg.esc_deadband + 0.1 * absf(want)
	var sliding := absf(r) > absf(want) or signf(r) != signf(want) or past > 0.0   # round more than asked, or the wrong way
	esc_cut = clampf(1.0 - (absf(e) - dead) / cfg.esc_cut_band, cfg.esc_cut_floor, 1.0) if sliding else 1.0
	if absf(e) < dead:
		return
	var heavy: float = float(car.mass) / 1500.0
	var left := e > 0.0                             # braking a left wheel turns it left
	esc_wheel = (0 if left else 1) if sliding else (2 if left else 3)
	esc_torque = minf(cfg.esc_gain * heavy * (absf(e) - dead), cfg.esc_max * heavy)
