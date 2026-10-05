extends SceneTree
## How much the car bounces: the autopilot drives a stage and this measures the
## body's vertical motion (what you feel in the seat) after the first 5 s:
##   * RMS vertical acceleration of the body (m/s^2) and of the driver's eye
##   * RMS pitch and roll rate (deg/s)
##   * the hardest single jolt (a landing), and how often it bounces up / down
## (only while it's moving on the road: off the road is meant to be rough, a beached
## car is put back on the road, like R, and the two seconds after that don't count)
## Run: godot --headless --fixed-fps 60 --path . -s tests/ride_check.gd -- --seed=3 [--secs=40]
## Prints [ride] lines; fails if the ride is rougher than the limits below.

const MAX_EYE_ACC := 4.5        # m/s^2 RMS at the driver's eye (before the rework: 8.5-11)
const MAX_JOLT := 95.0          # m/s^2: the hardest single hit (a jump landing); it was ~250 (25 g)

var StageGen
var StageBuilder
var RallyCar
var Autopilot
var st
var car
var ap
var t := 0.0
var hint := -1
var secs := 40.0
var _prev_v := Vector3.ZERO
var _prev_eye_v := 0.0
var _prev_eye := Vector3.ZERO
var _n := 0
var _acc2 := 0.0
var _eye2 := 0.0
var _pitch2 := 0.0
var _roll2 := 0.0
var _flips := 0
var _last_sign := 0.0
var _air := 0
var _stop := 0
var _hf2 := 0.0
var _lp_acc := 0.0
var _stuck := 0.0
var _since_reset := 99.0
var _peak := 0.0


func _initialize() -> void:
	StageGen = load("res://scripts/stage/stage_gen.gd")
	StageBuilder = load("res://scripts/stage/stage_builder.gd")
	RallyCar = load("res://scripts/vehicle/rally_car.gd")
	Autopilot = load("res://scripts/vehicle/autopilot.gd")
	var seed_value := 3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.split("=")[1])
		if a.begins_with("--secs="):
			secs = float(a.split("=")[1])
	st = StageGen.new()
	st.generate(seed_value)
	var b = StageBuilder.new()
	root.add_child(b)
	b.build(st)
	car = RallyCar.new()
	root.add_child(car)
	car.place(st.world_at(st.START_S - 4.0, 0.0), st.heading_at(st.START_S))
	ap = Autopilot.new(st)


func _physics_process(dt: float) -> bool:
	t += dt
	var at: Dictionary = st.locate(car.global_position, hint)
	hint = at.i
	car.set_lanes(st, at.s, at.d)                    # the clean wheel tracks grip, the loose gravel doesn't
	car.inp = ap.drive(car, at.s, at.d) if t > 1.0 else {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": false}
	# stuck (beached, spun): put it back on the road like R does, and don't count the
	# next 2 s (a dropped-in car isn't the ride)
	_since_reset += dt
	_stuck = _stuck + dt if car.linear_velocity.length() < 1.0 and t > 3.0 else 0.0
	if _stuck > 3.0:
		_stuck = 0.0
		_since_reset = 0.0
		car.place(st.world_at(at.s + 5.0, 0.0), st.heading_at(at.s + 5.0))
	var v: Vector3 = car.linear_velocity
	var acc := (v - _prev_v) / dt
	_prev_v = v
	var eye: Vector3 = car.global_transform * Vector3(-0.37, 0.6, 0.26)
	var eye_v := (eye.y - _prev_eye.y) / dt
	var eye_acc := (eye_v - _prev_eye_v) / dt
	_prev_eye = eye
	_prev_eye_v = eye_v
	if t > 5.0 and _since_reset > 2.0 and car.speed > 5.0 and absf(at.d) < 3.2:
		_peak = maxf(_peak, absf(acc.y))
		var w_local: Vector3 = car.global_transform.basis.inverse() * car.angular_velocity
		_n += 1
		_acc2 += acc.y * acc.y
		_eye2 += eye_acc * eye_acc
		_pitch2 += pow(rad_to_deg(w_local.x), 2)
		_roll2 += pow(rad_to_deg(w_local.z), 2)
		var sgn := signf(v.y) if absf(v.y) > 0.05 else _last_sign
		if sgn != _last_sign and _last_sign != 0.0:
			_flips += 1
		_last_sign = sgn
		if car.grounded < 4:
			_air += 1
		for c in car.comp:
			if c > car.BUMP_STOP:
				_stop += 1
				break
		_lp_acc = lerpf(_lp_acc, acc.y, 0.15)       # ~1.5 Hz low-pass: what's left is the buzz
		_hf2 += pow(acc.y - _lp_acc, 2)
	if t > 5.0 + secs:
		var n := float(maxi(_n, 1))
		var eye_rms := sqrt(_eye2 / n)
		var hz := _flips / 2.0 / secs
		print("[ride] body vertical %.2f m/s^2 RMS, eye %.2f m/s^2 RMS, pitch %.1f deg/s, roll %.1f deg/s, bounce %.2f Hz (%.0f km/h avg)" % [
			sqrt(_acc2 / n), eye_rms, sqrt(_pitch2 / n), sqrt(_roll2 / n), hz, at.s / t * 3.6])
		print("[ride] fast shaking (> ~2 Hz) %.2f m/s^2 RMS, a wheel off the ground %.0f %% of the time, on a bump stop %.0f %%, hardest jolt %.0f m/s^2 (%.1f g)" % [
			sqrt(_hf2 / n), 100.0 * _air / n, 100.0 * _stop / n, _peak, _peak / 9.8])
		var ok := eye_rms < MAX_EYE_ACC and _peak < MAX_JOLT
		print("[ride] %s" % ("RIDE OK" if ok else "RIDE FAIL (eye < %.1f m/s^2 RMS, hardest jolt < %.0f m/s^2)" % [MAX_EYE_ACC, MAX_JOLT]))
		quit(0 if ok else 1)
		return true
	return false
