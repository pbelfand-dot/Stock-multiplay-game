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
var pitch := -0.12                # (a little down: the wheel, your hands and their gauntlets in view, as Assetto Corsa's)
var reading := false
var view := "seat"              # "seat" | "chase" | "orbit"
## The chase camera's style: "rally" (high and back, looking down on the road ahead)
## or "street" (cut up and the touge: low and close, over the roof to the horizon, as
## Assetto Corsa's cut-up servers film it). Either way it stays the same distance
## behind at any speed; Config.chase_height raises or lowers it.
var chase_style := "rally"
var force_read := false         # tests / screenshots: eyes on the map board
var _read_blend := 0.0
var _lean := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _acc_local := Vector3.ZERO
var _bump := 0.0
var _orbit := 0.6               # rad around the car
var _buzz_t := 0.0
var _rev_t := 0.0                    # (the engine's shiver through the body: its own clock)
const JITTER_DEG := 0.08             # deg rms the view shivers at 200 km/h, flat out (the video study:
                                     # a real dash cam at speed ~0.2 deg; a game's often none)
var _neck_v := 0.0
var _slide_look := 0.0               # rad the head's turned toward where the car's going (LOOK INTO SLIDES)
const SLIDE_LOOK_K := 0.7            # of the slide's angle (the way it's going vs the way it points) ...
const SLIDE_LOOK_MAX := 0.7          # ... up to 40 deg, as far as a neck turns comfortably
var _chase_dir := Vector3.FORWARD    # the way the chase camera looks (smoothed)
var _chase_y := 0.0                   # the height it follows (smoothed)
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
	# (a slide: the head turns toward where the car's going, the way a drifting driver looks
	# through the side window at the corner, eased so it doesn't swing with every twitch)
	var want_look := 0.0
	if seat == "driver" and Config.look_into_slide and view == "seat":
		var v_loc: Vector3 = car.global_transform.basis.inverse() * car.linear_velocity
		if v_loc.length() > 5.0 and -v_loc.z > 1.0:
			var beta := atan2(v_loc.x, -v_loc.z)            # + : going to the right of where it points
			var past := signf(beta) * maxf(absf(beta) - deg_to_rad(4.0), 0.0)   # (no turn for a road car's few degrees)
			want_look = clampf(-past * SLIDE_LOOK_K, -SLIDE_LOOK_MAX, SLIDE_LOOK_MAX)
	_slide_look = lerpf(_slide_look, want_look, clampf(dt * 4.0, 0.0, 1.0))
	var look_yaw := lerpf(yaw + _slide_look, BOOK_LOOK.x, b)
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
	var rough := 1.8 if car.on_surface == "gravel" else 1.0      # (gravel shakes more than asphalt)
	_buzz_t += dt * (14.0 + spd * 0.4)
	var buzz := clampf(spd / 30.0, 0.0, 1.0) * 0.0022 * rough
	shake += Vector3(sin(_buzz_t * 1.7) + sin(_buzz_t * 3.1) * 0.5, sin(_buzz_t * 2.3) + sin(_buzz_t * 4.7) * 0.4, 0.0) * buzz
	# and a shiver that turns the view a hair (not just moves it): the road at speed and the
	# engine's revs through the body, more on the throttle; at 200 km/h flat out ~JITTER_DEG rms
	var revs: float = clampf(float(car.get("rpm") if car.get("rpm") != null else 0.0), 0.0, 1.0)
	var thr: float = clampf(float(car.inp.get("throttle", 0.0)) if "inp" in car else 0.0, 0.0, 1.0)
	_rev_t += dt * (9.0 + revs * 9.0)
	var shiver := deg_to_rad(JITTER_DEG) * 1.41 * (clampf(spd / 55.0, 0.0, 1.0) * 0.7 * rough + revs * (0.15 + 0.35 * thr))
	var jitter := Vector2(sin(_rev_t * 2.1) * 0.6 + sin(_buzz_t * 3.7) * 0.4, sin(_rev_t * 1.3) * 0.5 + sin(_buzz_t * 2.9) * 0.5) * shiver
	var street_chase := view == "chase" and chase_style == "street"
	# (the chase view barely widens: widening it with speed made the car shrink away, as
	# if the camera fell back)
	# (the seat: COCKPIT FOV (Settings, vertical degrees; Assetto Corsa-like by default), a hair
	# wider at speed)
	var fov_want: float = Config.cockpit_fov + clampf(spd / 45.0, 0.0, 1.0) * 3.0
	if view == "chase":
		fov_want = (70.0 if street_chase else 74.0) + clampf(spd / 70.0, 0.0, 1.0) * 4.0
	fov = lerpf(fov, fov_want, clampf(dt * 2.0, 0.0, 1.0))

	var head := Transform3D(Basis.from_euler(Vector3(look_pitch + jitter.x, look_yaw, jitter.y), EULER_ORDER_YXZ), eye + _lean + shake)
	match view:
		"orbit":
			_orbit += dt * 0.22
			var c := xf.origin + Vector3.UP * 0.6
			global_transform = Transform3D(Basis(), c + Vector3(cos(_orbit) * 7.5, 2.2, sin(_orbit) * 7.5)).looking_at(c, Vector3.UP)
			_chase_ready = false
		"chase":
			# behind and above, along the way the car is GOING (so a slide shows). Only that
			# way is smoothed (the camera swings round after the car), never the distance:
			# it stays the same at any speed (easing the position itself let it trail ~11 m
			# further back at 200 km/h). Higher or lower by Config.chase_height (Settings)
			var fwd := -xf.basis.z
			var vel: Vector3 = car.linear_velocity
			var dir := Vector3(fwd.x, 0.0, fwd.z).normalized()
			if vel.length() > 4.0 and vel.dot(fwd) > 0.0:
				dir = dir.lerp(Vector3(vel.x, 0.0, vel.z).normalized(), 0.5).normalized()
			if not _chase_ready:
				_chase_dir = dir
				_chase_y = xf.origin.y
				_chase_ready = true
			# (street: it swings round a little later, so the car moves about the frame as it weaves)
			_chase_dir = _chase_dir.slerp(dir, clampf(dt * (5.5 if street_chase else 7.0), 0.0, 1.0)).normalized()
			_chase_y = lerpf(_chase_y, xf.origin.y, clampf(dt * 12.0, 0.0, 1.0))     # (a bump soaked up, a hill followed)
			var back := 5.2 if street_chase else 6.5
			var up := (1.1 if street_chase else 2.3) + Config.chase_height     # (above the car's origin, itself ~0.4 m up)
			var base := Vector3(xf.origin.x, _chase_y, xf.origin.z)
			var look := base + (Vector3.UP * 0.8 + _chase_dir * 14.0 if street_chase else Vector3.UP * 0.9 + _chase_dir * 3.0)
			global_transform = Transform3D(Basis(), base - _chase_dir * back + Vector3.UP * up + shake * (2.0 if street_chase else 1.0)).looking_at(look, Vector3.UP)
			global_transform.basis = global_transform.basis * Basis.from_euler(Vector3(jitter.x, 0.0, jitter.y) * 0.6)
		_:
			global_transform = xf * head
			_chase_ready = false
