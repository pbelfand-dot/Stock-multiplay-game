extends Camera3D
## Your eyes in the car (first person, both seats). Mouse / right stick to
## look around (you can look out of the side windows), and the head leans
## with the g-forces: braking pitches you forward, a hard left throws you
## right, a landing bumps you down.
## CO-DRIVER: hold "read notes" (right mouse / Q / left trigger) and your eyes
## drop to the roadbook in your lap; let go and they come back up to the road.
## You can't watch both: that's the game.
##
## The car moves on the physics tick; the camera follows its INTERPOLATED
## transform every frame, so it's smooth at any frame rate.

const YAW_MAX := 2.0            # rad: almost over your shoulder
const PITCH_MIN := -1.25
const PITCH_MAX := 0.5
const BOOK_LOOK := Vector2(0.06, -0.98)   # yaw, pitch that puts the roadbook in view

var car
var seat := "driver"
var eye := Vector3.ZERO
var yaw := 0.0
var pitch := -0.06
var reading := false
var force_read := false         # tests / screenshots: eyes on the roadbook
var _read_blend := 0.0
var _lean := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _acc_local := Vector3.ZERO
var _bump := 0.0


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

	# g-forces: the head lags the car (car-local acceleration -> lean the other way)
	var xf: Transform3D = car.get_global_transform_interpolated()
	var target := Vector3(-_acc_local.x * 0.0035, -absf(_acc_local.y) * 0.001, -_acc_local.z * 0.004)
	target = target.clamp(Vector3(-0.07, -0.05, -0.07), Vector3(0.07, 0.03, 0.07))
	_lean = _lean.lerp(target, clampf(dt * 8.0, 0.0, 1.0))
	_bump = move_toward(_bump, 0.0, dt * 0.6)
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * _bump * 0.02

	var head := Transform3D(Basis.from_euler(Vector3(look_pitch, look_yaw, 0.0), EULER_ORDER_YXZ), eye + _lean + shake)
	global_transform = xf * head
