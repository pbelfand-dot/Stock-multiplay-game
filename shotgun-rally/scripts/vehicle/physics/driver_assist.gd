extends RefCounted
## The driver aids (an AssistConfig), each on or off on its own. They sit
## between the controls and the car and change only what each wheel's brake,
## the throttle and the steering are asked for:
##   * ABS: a braking wheel past its tyre's peak slip gets its brake eased off,
##     in proportion, so it brakes near the peak and can still steer
##   * traction control: a driven wheel spinning past its peak gets the throttle cut
##   * stability control: compares the car's yaw rate with what the steering
##     asks for (as far as the grip allows) and brakes one wheel to turn it back:
##     sliding round too far, the outside front; not turning enough, the inside rear
##   * steering smoothing (the input eased), damping (slower at speed),
##     speed-sensitive steering (never more angle than the front tyres can use
##     at this speed; not while the handbrake's pulled: a hairpin flick wants
##     all the lock) and countersteer help (sliding, the front wheels pointed
##     where the car is going)
## With them all on, a car driven inside its grip does exactly what it does
## with them off.

var cfg: Resource                  # AssistConfig
var abs_ease := [1.0, 1.0, 1.0, 1.0]   # each wheel's share of its pedal brake ABS leaves on
var tc_cut := 1.0                  # the throttle share traction control leaves
var esc_wheel := -1                # the wheel stability control is braking (-1: none) ...
var esc_torque := 0.0              # ... with this much (N m)
var countersteer := 0.0            # rad the countersteer help turned the wheels (+ = right)

var _smooth := 0.0


func setup(assists: Resource) -> void:
	cfg = assists
	reset()


func reset() -> void:
	abs_ease = [1.0, 1.0, 1.0, 1.0]
	tc_cut = 1.0
	esc_wheel = -1
	esc_torque = 0.0
	countersteer = 0.0
	_smooth = 0.0


## Any aid on?
func any() -> bool:
	return cfg.anti_lock or cfg.traction_control or cfg.stability_control or cfg.steering_smoothing \
		or cfg.steering_damping or cfg.countersteer_help or cfg.speed_sensitive_steering


## Where the steering asks the front wheels to point (the rack, rad, + = right)
## and how fast they may turn there (a share of the rack's speed).
func steering(car, dt: float, input: float) -> Vector2:
	var s := input
	if cfg.steering_smoothing:
		_smooth += (input - _smooth) * (1.0 - exp(-dt / cfg.smoothing_time))
		s = _smooth
	else:
		_smooth = input
	var v := absf(float(car.speed))
	var lock := deg_to_rad(car.config.steering.max_angle_deg)
	var target := s * lock
	if cfg.speed_sensitive_steering and v > 1.0 and float(car.inp.handbrake) < 0.05:
		# no more than helps: the geometry of the tightest turn the fronts' grip
		# allows at this speed, plus their peak slip angle (less is left alone)
		var t: Resource = car.wheels[0].surface_tire
		var base: float = car.config.rear_axle - car.config.front_axle
		var useful: float = atan(base * t.lateral_mu * 9.8 / (v * v)) + deg_to_rad(t.lateral_peak_deg)
		target = clampf(target, -useful, useful)
	var rate := 1.0
	if cfg.steering_damping:
		rate = clampf(cfg.damping_speed / maxf(v, 0.1), 0.35, 1.0)
	countersteer = 0.0
	if cfg.countersteer_help and v > 3.0:
		var rear := (absf(car.wheels[2].slip_angle_deg()) + absf(car.wheels[3].slip_angle_deg())) * 0.5
		var k: float = clampf((rear - 4.0) / 8.0, 0.0, 1.0) * cfg.countersteer_strength
		if k > 0.0:
			# the front axle's direction of travel, relative to the car (+ = to its right)
			var xf: Transform3D = car.global_transform
			var p: Vector3 = xf * Vector3(0.0, 0.0, car.config.front_axle)
			var vf: Vector3 = car.linear_velocity + car.angular_velocity.cross(p - xf * car.center_of_mass)
			var local := xf.basis.transposed() * vf
			var align := clampf(atan2(local.x, -local.z), -lock, lock)
			var blended := lerpf(target, align, k)
			countersteer = blended - target
			target = blended
	return Vector2(target, rate)


## The steering input that gets the wheels' target (-1..1) this tick through the
## smoothing: what a driver who knows the car presses (the autopilot drives with
## it, so the aid's easing doesn't make it weave). Without smoothing: the target.
func input_for(target: float, dt: float) -> float:
	if not cfg.steering_smoothing:
		return target
	var a := 1.0 - exp(-dt / cfg.smoothing_time)
	return clampf(_smooth + (target - _smooth) / a, -1.0, 1.0)


## The throttle after traction control.
func throttle(car, dt: float, thr: float) -> float:
	if not cfg.traction_control or car.drivetrain == null:
		tc_cut = 1.0
		return thr
	var dir := signf(car.drivetrain.ratio())
	var worst := 0.0
	for w in car.wheels:
		if not w.grounded:
			continue
		var spin: float = dir * (w.omega * w.radius - w.v_long) / maxf(absf(w.v_long), cfg.tc_low_speed)
		worst = maxf(worst, spin - w.surface_tire.longitudinal_peak)
	var want := clampf(1.0 - worst / cfg.tc_band, 0.0, 1.0)
	tc_cut = move_toward(tc_cut, want, dt * (20.0 if want < tc_cut else 8.0))
	return thr * tc_cut


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
	_stability(car)
	if esc_wheel >= 0:
		out[esc_wheel] += esc_torque
	return out


func _stability(car) -> void:
	esc_wheel = -1
	esc_torque = 0.0
	var v := float(car.speed)
	if not cfg.stability_control or v < 5.0 or float(car.inp.handbrake) > 0.05:
		return
	var base: float = car.config.rear_axle - car.config.front_axle
	var mu: float = 0.5 * (car.wheels[0].surface_tire.lateral_mu + car.wheels[2].surface_tire.lateral_mu)
	var r_max := mu * 9.8 / v
	var want := clampf(-v * tan(float(car.steer)) / base, -r_max, r_max)   # yaw rate it asks for (+ = left)
	var r: float = car.angular_velocity.dot(car.global_transform.basis.y)
	var e := want - r                               # the yaw it needs to add (+ = to the left)
	var dead: float = cfg.esc_deadband + 0.1 * absf(want)
	if absf(e) < dead:
		return
	var sliding := absf(r) > absf(want) or signf(r) != signf(want)   # round more than asked, or the wrong way
	var left := e > 0.0                             # braking a left wheel turns it left
	esc_wheel = (0 if left else 1) if sliding else (2 if left else 3)
	esc_torque = minf(cfg.esc_gain * (absf(e) - dead), cfg.esc_max)
