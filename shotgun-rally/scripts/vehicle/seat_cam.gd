extends Camera3D
## Your eyes in the car (first person, both seats). Mouse / right stick to
## look around (you can look out of the side windows), and the head leans
## with the g-forces: braking pitches you forward, a hard left throws you
## right, a landing bumps you down.
## CO-DRIVER: hold "read notes" (right mouse / Q / left trigger) and your eyes
## drop to the map board in your lap; let go and they come back up to the road.
## You can't watch both: that's the game.
##
## Two outside views too (the game picks): "orbit" circles the car on the
## start line and at the finish, "chase" follows behind it (the driver's C).
##
## The car moves on the physics tick; the camera follows its INTERPOLATED
## transform every frame, so it's smooth at any frame rate.

const YAW_MAX := 2.0            # rad: almost over your shoulder
const PITCH_MIN := -1.25
const PITCH_MAX := 0.5
const BOOK_LOOK := Vector2(0.06, -0.98)   # yaw, pitch that puts the map board in view
const NECK_K := 380.0           # the neck's spring (1/s^2): ~3 Hz
const NECK_C := 30.0            # ... and damping: it settles in a bob or two
const NECK_STEP := 1.0 / 120.0  # s: the neck is worked out in steps no longer than this
const NECK_LOW := -0.035        # m: how far the head can drop ...
const NECK_HIGH := 0.025        # ... and rise

var car
var seat := "driver"
var eye := Vector3.ZERO
var yaw := 0.0
var pitch := -0.06
var reading := false
var view := "seat"              # "seat" | "chase" | "orbit"
## The chase camera's style: "rally" (high and back, looking down on the road ahead)
## or "street" (cut up and the touge: low and close, over the roof to the horizon, as
## Assetto Corsa's cut-up servers film it; the view widens with speed).
var chase_style := "rally"
var force_read := false         # tests / screenshots: eyes on the map board
var _read_blend := 0.0
var _lean := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _acc_local := Vector3.ZERO
var _bump := 0.0
var _orbit := 0.6               # rad around the car
var _buzz_t := 0.0
var _neck_v := 0.0
var _chase_pos := Vector3.ZERO
var _chase_ready := false


func attach(the_car, seat_name: String, eye_pos: Vector3) -> void:
	car = the_car
	seat = seat_name
	eye = eye_pos
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fov = 78.0
	near = 0.03
	far = 900.0
	# don't draw the inside of your own helmet
	cull_mask = 0xFFFFF & ~(1 << (1 if seat == "driver" else 2))
	current = true


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * Config.mouse_sens
		pitch -= e.relative.y * Config.mouse_sens * (-1.0 if Config.invert_y else 1.0)
		yaw = clampf(yaw, -YAW_MAX, YAW_MAX)
		pitch = clampf(pitch, PITCH_MIN, PITCH_MAX)


## Acceleration is measured on the physics tick (the velocity only changes there).
func _physics_process(dt: float) -> void:
	if car == null:
		return
	var vel: Vector3 = car.linear_velocity
	var acc := (vel - _prev_vel) / dt
	_prev_vel = vel
	_acc_local = _acc_local.lerp(car.global_transform.basis.inverse() * acc, 0.25)


func bump(amount: float) -> void:
	_bump = maxf(_bump, amount)


func _process(dt: float) -> void:
	if car == null:
		return
	# your own helmet (and the co-driver's body) only hidden from your own eyes: outside, all of you shows
	cull_mask = 0xFFFFF & ~(1 << (1 if seat == "driver" else 2)) if view == "seat" else 0xFFFFF
	var stick: Vector2 = Controls.look_stick()
	yaw = clampf(yaw - stick.x * 2.4 * dt, -YAW_MAX, YAW_MAX)
	pitch = clampf(pitch - stick.y * 1.8 * dt, PITCH_MIN, PITCH_MAX)
	if stick == Vector2.ZERO and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		yaw = lerpf(yaw, 0.0, clampf(dt * 1.5, 0.0, 1.0))      # no mouse: drift back to the road
	reading = force_read or (seat == "codriver" and Input.is_action_pressed("read_notes"))
	_read_blend = move_toward(_read_blend, 1.0 if reading else 0.0, dt * 5.0)
	var b := smoothstep(0.0, 1.0, _read_blend)
	var look_yaw := lerpf(yaw, BOOK_LOOK.x, b)
	var look_pitch := lerpf(pitch, BOOK_LOOK.y, b)

	# g-forces: the head lags the car (car-local acceleration -> lean the other way).
	# Up and down it's a head on a neck: a soft spring that soaks up the hits and
	# settles (it used to snap the view down on every jolt, which read as bouncing)
	var xf: Transform3D = car.get_global_transform_interpolated()
	var target := Vector3(-_acc_local.x * 0.0035, 0.0, -_acc_local.z * 0.004)
	target = target.clamp(Vector3(-0.07, 0.0, -0.07), Vector3(0.07, 0.0, 0.07))
	_lean.x = lerpf(_lean.x, target.x, clampf(dt * 8.0, 0.0, 1.0))
	_lean.z = lerpf(_lean.z, target.z, clampf(dt * 8.0, 0.0, 1.0))
	var push := clampf(_acc_local.y, -40.0, 40.0) * 0.6        # how hard the seat moves under you
	# in small fixed steps, whatever the frame rate: one step per frame went unstable
	# below ~20 fps and slammed the view up and down 6 cm every frame (the "rapid
	# bouncing" with nothing on the road); at the end of its travel it stops dead
	var steps := ceili(minf(dt, 0.1) / NECK_STEP)
	var h := minf(dt, 0.1) / maxi(steps, 1)
	for i in steps:
		_neck_v += (-NECK_K * _lean.y - NECK_C * _neck_v - push) * h
		_lean.y += _neck_v * h
		if _lean.y < NECK_LOW or _lean.y > NECK_HIGH:
			_lean.y = clampf(_lean.y, NECK_LOW, NECK_HIGH)
			_neck_v = 0.0
	_bump = move_toward(_bump, 0.0, dt * 0.6)
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * _bump * 0.008
	# the gravel through the seat: a fine buzz that grows with speed (more off the road),
	# and the view opens up a little when you're quick
	var spd: float = car.linear_velocity.length()
	var rough := 1.0 if car.on_surface == "gravel" else 1.8
	_buzz_t += dt * (14.0 + spd * 0.4)
	var buzz := clampf(spd / 30.0, 0.0, 1.0) * 0.0022 * rough
	shake += Vector3(sin(_buzz_t * 1.7) + sin(_buzz_t * 3.1) * 0.5, sin(_buzz_t * 2.3) + sin(_buzz_t * 4.7) * 0.4, 0.0) * buzz
	var street_chase := view == "chase" and chase_style == "street"
	var fov_want := (72.0 + clampf(spd / 70.0, 0.0, 1.0) * 16.0) if street_chase else 76.0 + clampf(spd / 45.0, 0.0, 1.0) * 8.0
	fov = lerpf(fov, fov_want, clampf(dt * 2.0, 0.0, 1.0))

	var head := Transform3D(Basis.from_euler(Vector3(look_pitch, look_yaw, 0.0), EULER_ORDER_YXZ), eye + _lean + shake)
	match view:
		"orbit":
			_orbit += dt * 0.22
			var c := xf.origin + Vector3.UP * 0.6
			global_transform = Transform3D(Basis(), c + Vector3(cos(_orbit) * 7.5, 2.2, sin(_orbit) * 7.5)).looking_at(c, Vector3.UP)
			_chase_ready = false
		"chase":
			# behind and above, along the way the car is GOING (so a slide shows), smoothed
			var fwd := -xf.basis.z
			var vel: Vector3 = car.linear_velocity
			var dir := Vector3(fwd.x, 0.0, fwd.z).normalized()
			if vel.length() > 4.0:
				dir = dir.lerp(Vector3(vel.x, 0.0, vel.z).normalized(), 0.5).normalized()
			var back := 5.2 if street_chase else 6.5
			var up := 1.1 if street_chase else 2.3                 # (above the car's origin, itself ~0.4 m up: ~1.5 m)
			var want := xf.origin - dir * back + Vector3.UP * up
			if not _chase_ready:
				_chase_pos = want
				_chase_ready = true
			# (street: it trails a little more, so the car moves about the frame as it weaves)
			_chase_pos = _chase_pos.lerp(want, clampf(dt * (5.5 if street_chase else 7.0), 0.0, 1.0))
			var look := xf.origin + (Vector3.UP * 0.8 + dir * 14.0 if street_chase else Vector3.UP * 0.9 + dir * 3.0)
			global_transform = Transform3D(Basis(), _chase_pos + shake * (2.0 if street_chase else 1.0)).looking_at(look, Vector3.UP)
		_:
			global_transform = xf * head
			_chase_ready = false
