extends Resource
## The driver aids, each its own switch (the game's Settings), all off by
## default: that's the base physics. They only change what the controls ask
## for (each wheel's brake, the throttle, where the steering is pointed),
## never the physics, so with them all on, a car driven within its grip does
## exactly what it does with them off. Edit the figures in the inspector.

@export_group("Switches")
## Anti-lock brakes: a wheel locking gets its brake eased off.
@export var anti_lock := false
## Traction control: driven wheels spinning past their grip get the throttle cut.
@export var traction_control := false
## Stability control: a single wheel's brake turns the car back toward where the
## steering points when it slides too far (or won't turn).
@export var stability_control := false
## Steering smoothing: the input eased in and out (keys and taps).
@export var steering_smoothing := false
## Steering damping: at speed the wheels turn more slowly.
@export var steering_damping := false
## Countersteer help: when the tail slides, the front wheels are pointed where the car is going.
@export var countersteer_help := false
## Speed-sensitive steering: never more angle than the front tyres can use at
## this speed (full input on keys doesn't plough on with the wheels turned too far).
@export var speed_sensitive_steering := false
## Drift assist: in a drift your steering sets the angle (into the corner more,
## let go straight, countersteer straight quicker), and it never spins (an arcade
## aid: it steers the fronts and turns the body). With it on it also does
## countersteer help's job.
@export var drift_assist := false
## High-speed stability: at speed, yaw the steering didn't ask for (a wobble, a
## clipped tail) is damped (an arcade aid: a turning force on the body).
@export var high_speed_stability := false

@export_group("ABS")
## How far past the tyre's peak slip a wheel may lock before its brake is fully off
## (a share of the slip ratio).
@export_range(0.01, 0.5, 0.01) var abs_band := 0.1

@export_group("Traction control")
## How far past the tyre's peak slip a driven wheel may spin before the throttle is fully cut.
@export_range(0.01, 1.0, 0.01) var tc_band := 0.15
## Below this speed the spin is measured against it instead (so it can pull away).
@export_range(0.5, 10.0, 0.1, "suffix:m/s") var tc_low_speed := 3.0

@export_group("Stability control")
## Brake torque per rad/s the car yaws off what the steering asks for (N m).
@export_range(0.0, 20000.0, 100.0, "suffix:N m/(rad/s)") var esc_gain := 4000.0
## The most it brakes one wheel with (N m).
@export_range(0.0, 5000.0, 50.0, "suffix:N m") var esc_max := 1500.0
## How far off (rad/s) before it steps in.
@export_range(0.0, 1.0, 0.01, "suffix:rad/s") var esc_deadband := 0.1

@export_group("Steering")
## Smoothing a stick: its time constant (s). A stick is analog already: just a touch.
@export_range(0.01, 0.6, 0.01, "suffix:s") var smoothing_time := 0.04
## Smoothing keys: how fast the steering ramps in (full input per second) slowly,
## up to key_rate_from, and at speed, from key_rate_to; back out key_return
## times quicker. At 200 km/h a 0.15 s tap is a ~30 % input, not all the grip.
@export_range(0.5, 20.0, 0.1, "suffix:/s") var key_rate_slow := 5.0
@export_range(0.5, 20.0, 0.1, "suffix:/s") var key_rate_fast := 2.0
@export_range(0.0, 80.0, 0.5, "suffix:m/s") var key_rate_from := 15.0
@export_range(1.0, 100.0, 0.5, "suffix:m/s") var key_rate_to := 55.0
@export_range(1.0, 6.0, 0.1) var key_return := 2.5
## Damping: above this speed the wheels turn more slowly (in proportion).
@export_range(1.0, 60.0, 0.5, "suffix:m/s") var damping_speed := 12.0
## Countersteer help's strength (1 = the wheels pointed fully where it's going).
## At 0.7 the fronts were left pointing a little into the slide, still pushing it
## round: a keyboard lane change at 100 km/h off the throttle spun the car
## (tests/handling_check.gd "keys"); 0.9 catches it.
@export_range(0.0, 1.0, 0.01) var countersteer_strength := 0.9
## Countersteer help starts when the rear tyres slide past this slip angle, and is
## at full strength by the second.
@export_range(0.0, 30.0, 0.5, "suffix:deg") var countersteer_from_deg := 4.0
@export_range(1.0, 40.0, 0.5, "suffix:deg") var countersteer_full_deg := 10.0
## Speed-sensitive steering: full input asks the front tyres for this share of
## their grip at this speed (the rest of the stick in proportion). Before, full
## input asked for their peak and a fifth of a stick already had most of it at
## 200 km/h: a stick was all or nothing at speed.
@export_range(0.5, 1.0, 0.01) var speed_sensitive_grip := 0.98

@export_group("Drift assist")
## A drift: the body's slip angle (between where it points and where it's going)
## past drift_enter_deg; over when it's back under drift_exit_deg.
@export_range(1.0, 30.0, 0.5, "suffix:deg") var drift_enter_deg := 6.0
@export_range(0.5, 20.0, 0.5, "suffix:deg") var drift_exit_deg := 2.0
## Steering fully into the corner on full throttle asks for this angle (part-way:
## in proportion); off the throttle, drift_lift_share of it.
@export_range(5.0, 70.0, 0.5, "suffix:deg") var drift_angle_deg := 40.0
@export_range(0.0, 1.0, 0.01) var drift_lift_share := 0.4
## At speed less angle's on offer: all of it to drift_full_speed, drift_fast_deg by drift_fast_speed.
@export_range(5.0, 80.0, 0.5, "suffix:m/s") var drift_full_speed := 28.0
@export_range(10.0, 100.0, 0.5, "suffix:m/s") var drift_fast_speed := 50.0
@export_range(0.0, 60.0, 0.5, "suffix:deg") var drift_fast_deg := 12.0
## With the handbrake pulled it lets the tail round this much further (a hairpin).
@export_range(0.0, 60.0, 0.5, "suffix:deg") var drift_handbrake_deg := 20.0
## How fast the angle it holds follows the steering (deg/s): letting go of the
## keys eases the drift straight instead of snapping it, and taps hold it between.
@export_range(5.0, 400.0, 1.0, "suffix:deg/s") var drift_angle_rate := 45.0
## The front wheels in a drift: this share of their peak slip angle inside where
## the front axle's going (so they carry their part of the corner), and ...
@export_range(0.0, 2.0, 0.01) var drift_front_bite := 0.8
## ... extra countersteer per rad of slip past the angle asked for.
@export_range(0.0, 3.0, 0.01) var drift_steer_gain := 0.6
## Countersteering straightens it this much quicker (x, at full countersteer).
@export_range(0.0, 3.0, 0.01) var drift_counter_boost := 0.8
## Its turning force: x the car's weight x its wheelbase, per rad off the angle
## (short of the angle only drift_grow_share of it: the throttle does that),
## damped by drift_damping per rad/s the angle's changing; a hard stop
## drift_stop_deg past the angle asked for.
@export_range(0.0, 3.0, 0.01) var drift_strength := 1.0
@export_range(0.0, 1.0, 0.01) var drift_grow_share := 0.3
@export_range(0.0, 2.0, 0.01) var drift_damping := 0.25
@export_range(0.0, 40.0, 0.5, "suffix:deg") var drift_stop_deg := 12.0
## Below this speed it fades out (a slow handbrake spin in a hairpin is yours).
@export_range(0.0, 20.0, 0.5, "suffix:m/s") var drift_min_speed := 6.0

@export_group("High-speed stability")
## It comes in from this speed, all of it by the second.
@export_range(0.0, 80.0, 0.5, "suffix:m/s") var hs_from_speed := 25.0
@export_range(1.0, 100.0, 0.5, "suffix:m/s") var hs_full_speed := 40.0
## Its turning force against yaw past what the steering asks for, x the car's
## weight x its wheelbase per rad/s, and against the body's slip angle per rad.
@export_range(0.0, 5.0, 0.01) var hs_yaw_damping := 1.0
@export_range(0.0, 5.0, 0.01) var hs_slip_damping := 0.5
