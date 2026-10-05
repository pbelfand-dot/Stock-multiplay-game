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
## Smoothing's time constant (s).
@export_range(0.01, 0.6, 0.01, "suffix:s") var smoothing_time := 0.2
## Damping: above this speed the wheels turn more slowly (in proportion).
@export_range(1.0, 60.0, 0.5, "suffix:m/s") var damping_speed := 12.0
## Countersteer help's strength (1 = the wheels pointed fully where it's going).
@export_range(0.0, 1.0, 0.01) var countersteer_strength := 0.7
