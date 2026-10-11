extends Camera3D
## The replay's cameras (replay.gd poses the cars, then calls update() every frame). One
## camera, many ways of filming the car it follows (`target`):
##   CHASE        the game's own chase camera (a SeatCam worked as a rig: the same distance
##                behind at any speed, swinging round after the car; rally or street style)
##   COCKPIT      your seat (the SeatCam's seat view: the crew, the wheel, the road's shiver);
##                another driver's car with an interior of its own from its driver's eyes,
##                one without from the hood
##   HOOD, BUMPER, WHEEL, SIDE, FRONT   bolted to the car (from its body's own box), no easing
##   FPV DRONE    the home screen's drone (menu_backdrop.gd): a little quad on a spring round
##                the car, swooping from behind to alongside, over the roof and ahead,
##                banking into its turns, a wide lens; never into the ground or behind a tree
##   HELICOPTER   high and off to the side, tracking (the showcase's)
##   TRACKSIDE TV a camera by the road ahead of the car, on the outside of the next bend (a
##                crane over the road's edge, a highway's shoulder, a circuit's tower): it pans
##                and zooms (the field of view by the distance) to keep the car framed, and
##                when the car's gone by (or a trunk's in the way) the next one's set up further on
##   FREE FOLLOW  an orbit locked on the car: drag with the right mouse button (or the right
##                stick) round it, the wheel (or the triggers, W / S) zooms, Q / E lower and
##                raise it; it turns with the car, eased
##   FREE CAM     fly anywhere: WASD (left stick), Q / E (LB / RB) down and up, shift (RT)
##                fast, ctrl (LT) slow, the right mouse button held (right stick) to look
##   CAM 1..n     placed cameras (P: "place a camera here" drops one where the camera is):
##                fixed, they turn to follow the car and zoom with the distance
##   DIRECTOR     cuts between the placed cameras by itself: the nearest one that can see the
##                car, held a moment before the next cut
## No camera goes below the ground (a ray down from above it, the stage's own land as the
## fallback). Placed cameras are kept for the stage (its mode and seed) beside the profile.

const SeatCam = preload("res://scripts/vehicle/seat_cam.gd")
const Cockpit = preload("res://scripts/vehicle/cockpit.gd")
const CarLamps = preload("res://scripts/vehicle/car_lamps.gd")

const BASE_MODES := ["chase", "cockpit", "hood", "bumper", "wheel", "drone", "heli", "tv", "orbit", "free", "side", "front"]
const TITLES := {"chase": "CHASE", "cockpit": "COCKPIT", "hood": "HOOD", "bumper": "BUMPER", "wheel": "WHEEL",
	"side": "SIDE", "front": "FRONT", "drone": "FPV DRONE", "heli": "HELICOPTER", "tv": "TRACKSIDE TV",
	"orbit": "FREE FOLLOW", "free": "FREE CAM", "director": "DIRECTOR"}
## Where the drone heads round the car (car-local: x right, y up, z behind), in turn (the home
## screen's drone, menu_backdrop.gd)
const DRONE_LEGS := [Vector3(0.0, 1.1, 7.0), Vector3(3.4, 0.9, 1.5), Vector3(0.0, 3.4, -4.0), Vector3(-3.2, 1.0, 2.0),
	Vector3(0.0, 0.7, 9.0), Vector3(2.6, 2.2, -1.0)]
const DRONE_LEG_TIME := 2.6          # s of the replay's clock on each
const DRONE_STEP := 1.0 / 120.0      # its flight in steps this short, whatever the frame rate
const FREE_SPEED := 14.0             # m/s the free cam flies (x4 fast, x0.25 slow)
const STICK_LOOK := 2.2              # rad/s at full stick
const CLEAR := 0.4                   # m the free cameras keep above the ground
const TELEPORT := 40.0               # m in a frame: the replay jumped (scrubbed): the cameras start afresh
const SHOT_MIN := 2.0                # s the director holds a camera at least

signal message(text: String)         # (the bar flashes it) "CAM 2 PLACED", "DIRECTOR: CAM 1" ...

var game                             # the Game: its stage, its cockpit, the chase style
var st
var target: Node3D                   # the car followed (a RallyCar)
var target_vel := Vector3.ZERO       # its recorded velocity (the replay's, m/s)
var mode := "chase"
var placed: Array = []               # placed cameras: [Vector3 position]
var shot := -1                       # the placed camera on (CAM n, or the director's pick)
var input_on := true                 # (tests) off: no keys or sticks read here
var free_pos := Vector3.ZERO
var free_yaw := 0.0
var free_pitch := -0.2
var orbit_yaw := 0.5                 # rad round the car from straight behind (+ = to its right)
var orbit_pitch := 0.3               # rad up
var orbit_dist := 7.0                # m
var orbit_lift := 0.0                # m the orbit's centre is raised (Q / E)

var _rig                             # SeatCam: the chase and cockpit views, worked here
var _prev_p := Vector3.ZERO          # the target's position at the last update (its motion in the replay)
var _have_prev := false
var _drone := Vector3.ZERO
var _drone_v := Vector3.ZERO
var _drone_roll := 0.0
var _drone_leg := 0
var _drone_leg_t := 0.0
var _drone_acc := Vector3.ZERO
var _wobble_t := 0.0
var _heli := Vector3.ZERO
var _heli_side := 1.0
var _tv := {}                        # {pos, s, blocked}: the trackside camera now
var _tv_hint := -1
var _tv_side := 1.0
var _los_t := 0.0
var _aim := Vector3.ZERO             # where the turning cameras look (eased onto the car)
var _fov_s := 60.0                   # their field of view (eased)
var _fresh := true                   # a new mode, target or a jump: the eased cameras start where they belong
var _head := Vector3.FORWARD         # the orbit's idea of the car's heading (eased)
var _mouse := Vector2.ZERO           # mouse motion with the look button held, since the last update
var _wheel := 0.0                    # mouse wheel clicks since the last update (+ = toward you: zoom in)
var _shot_t := 0.0                   # s the director's current camera has been on
var _dims := {}                      # car instance id -> AABB (its body, in its own space)
var _save_key := ""


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	near = 0.03
	far = 1200.0
	fov = 60.0


## Hook up to the game (its stage, cockpit and chase style), its placed cameras loaded.
func setup(g) -> void:
	game = g
	st = g.st
	_save_key = "%s_%d" % [str(g.mode) if str(g.mode) != "" else "rally", int(g.seed_value)]
	_load_placed()


## Every mode now, in order: the fixed ones, then a CAM n per placed camera and the DIRECTOR.
func modes() -> Array:
	var out: Array = BASE_MODES.duplicate()
	for i in placed.size():
		out.append("cam%d" % (i + 1))
	if not placed.is_empty():
		out.append("director")
	return out


## A mode's name for the bar.
func title(m := "") -> String:
	if m == "":
		m = mode
	if m.begins_with("cam"):
		return "CAM %s" % m.substr(3)
	if m == "director":
		return "DIRECTOR · CAM %d" % (shot + 1) if shot >= 0 else "DIRECTOR"
	if m == "cockpit" and target and not _has_eye(target):
		return "COCKPIT (HOOD)"
	return TITLES.get(m, m.to_upper())


func set_mode(m: String) -> void:
	if not m in modes():
		return
	var was := mode
	mode = m
	if m.begins_with("cam"):
		shot = int(m.substr(3)) - 1
	elif m == "director":
		shot = _director_pick(-1)
		_shot_t = 0.0
	if m == "free" and was != "free":
		free_pos = global_position                   # (the free cam takes off from what you were seeing)
		var f := -global_transform.basis.z
		free_yaw = atan2(-f.x, -f.z)
		free_pitch = asin(clampf(f.y, -1.0, 1.0))
	if m == "orbit" and was != "orbit" and target:
		var rel := global_position - target.global_position
		var head := _flat(-target.global_transform.basis.z)
		var flat := Vector3(rel.x, 0.0, rel.z)
		# (from a camera near the car the orbit starts where it was looking from; from further
		# off, behind the car and to its right)
		if flat.length() > 1.0 and rel.length() < 15.0:
			orbit_yaw = (-head).signed_angle_to(flat.normalized(), Vector3.UP)
			orbit_dist = clampf(rel.length(), 3.0, 12.0)
			orbit_pitch = clampf(asin(clampf(rel.y / maxf(rel.length(), 0.1), -1.0, 1.0)), 0.1, 1.45)
		else:
			orbit_yaw = 0.5
			orbit_dist = 7.0
			orbit_pitch = 0.3
	_fresh = true
	_apply_view()


func cycle(step: int) -> void:
	var list := modes()
	var i := list.find(mode)
	set_mode(list[posmod(i + step, list.size())])


func set_target(c: Node3D) -> void:
	if c == target:
		return
	target = c
	_have_prev = false
	_fresh = true
	_apply_view()


## "Place a camera here": a fixed camera where this one is now (kept above the ground).
func place_here() -> int:
	var p := global_position
	p.y = maxf(p.y, ground_at(p) + 0.3)
	placed.append(p)
	_save_placed()
	message.emit("CAM %d PLACED" % placed.size())
	return placed.size() - 1


func clear_placed() -> void:
	placed.clear()
	shot = -1
	_save_placed()
	if mode.begins_with("cam") or mode == "director":
		set_mode("free")
	message.emit("PLACED CAMERAS CLEARED")


# ── input (mouse) ─────────────────────────────────────────────────────────

func _unhandled_input(e: InputEvent) -> void:
	if not current or not input_on:
		return
	if e is InputEventMouseMotion and Input.is_action_pressed("replay_look"):
		_mouse += (e as InputEventMouseMotion).relative
	elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		var b := (e as InputEventMouseButton).button_index
		if b == MOUSE_BUTTON_WHEEL_UP:
			_wheel += 1.0
		elif b == MOUSE_BUTTON_WHEEL_DOWN:
			_wheel -= 1.0


# ── every frame ───────────────────────────────────────────────────────────

## Film the target this frame. dt: the real frame time; dt_play: how far the replay's clock
## moved (seconds; less than zero rewinding, zero paused): the drone and the helicopter fly
## by it (they keep up at 4x, hover when it's paused), the operator's easing by dt.
func update(dt: float, dt_play: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var xf: Transform3D = target.global_transform
	var p := xf.origin
	if _have_prev and p.distance_to(_prev_p) > TELEPORT:
		_fresh = true
	var mouse := _mouse * Config.mouse_sens * 1.2 * Vector2(1.0, -1.0 if Config.invert_y else 1.0)
	_mouse = Vector2.ZERO
	var look_in := mouse
	if input_on:
		look_in += Controls.look_stick() * STICK_LOOK * dt * Vector2(1.0, -1.0 if Config.invert_y else 1.0)
	match mode:
		"chase":
			_rig_view("chase", dt)
		"cockpit":
			if _has_eye(target):
				_rig_view("seat", dt, mouse)        # (the rig reads the right stick itself, as in the car)
			else:
				_hood(xf)
		"hood":
			_hood(xf)
		"bumper":
			var b := _box(target)
			var y := b.position.y + b.size.y * 0.27
			_put(xf * Vector3(0.0, y, b.position.z - 0.06), xf * Vector3(0.0, y, b.position.z - 20.0), xf.basis.y)
			fov = 75.0
		"wheel":
			var b2 := _box(target)
			var hw := maxf(-b2.position.x, b2.end.x)
			var fa: float = float(target.config.front_axle) if target.get("config") else b2.position.z * 0.62
			var g := b2.position.y
			_put(xf * Vector3(hw + 0.3, g + 0.36, fa + 1.0), xf * Vector3(hw - 0.2, g + 0.3, fa - 12.0), xf.basis.y)
			fov = 68.0
		"side":
			var hw2 := maxf(-_box(target).position.x, _box(target).end.x)
			_put(xf * Vector3(-(hw2 + 1.5), 0.75, 1.6), xf * Vector3(-0.4, 0.55, -14.0), xf.basis.y)
			fov = 72.0
		"front":
			var b3 := _box(target)
			_put(xf * Vector3(0.0, 1.05, b3.position.z - 5.5), xf * Vector3(0.0, 0.55, 0.0), Vector3.UP)
			fov = 58.0
		"drone":
			_drone_cam(dt, dt_play, p, _flat(-xf.basis.z))
		"heli":
			_heli_cam(dt, dt_play, p, _flat(-xf.basis.z))
		"tv":
			_tv_cam(dt, p)
		"orbit":
			_orbit_cam(dt, p, _flat(-xf.basis.z), look_in)
		"free":
			_free_cam(dt, look_in)
		"director":
			_director(dt, p)
			_placed_cam(dt, p)
		_:
			if mode.begins_with("cam"):
				_placed_cam(dt, p)
	_prev_p = p
	_have_prev = true
	_fresh = false


## The chase or seat view, worked by the game's own SeatCam (a rig: not a camera that's on);
## look: the mouse's turn of the head this frame (the seat view).
func _rig_view(view: String, dt: float, look := Vector2.ZERO) -> void:
	if _rig == null:
		_rig = SeatCam.new()
		_rig.name = "Rig"
		_rig.top_level = true
		add_child(_rig)
		_rig.set_process(false)
		_rig.set_physics_process(false)
		_rig.set_process_unhandled_input(false)
		_rig.current = false
	if _rig.car != target or _rig.view != view or _fresh:
		_rig.car = target
		_rig.view = view
		_rig.set("_chase_ready", false)
		if view == "seat":
			_rig.seat = _seat() if target == game.car else "driver"
			_rig.eye = _eye(target)
			_rig.yaw = 0.0
			_rig.pitch = -0.12
			if target == game.car and game.cockpit:
				_rig.aim_at_wheel(game.cockpit.wheel_c)
	_rig.chase_style = game.cam.chase_style if game.cam else "rally"
	_rig.yaw = clampf(_rig.yaw - look.x, -SeatCam.YAW_MAX, SeatCam.YAW_MAX)
	_rig.pitch = clampf(_rig.pitch - look.y, SeatCam.PITCH_MIN, SeatCam.PITCH_MAX)
	_rig.fov = fov
	_rig._process(maxf(dt, 1e-4))
	global_transform = _rig.global_transform
	fov = _rig.fov


func _hood(xf: Transform3D) -> void:
	var b := _box(target)
	var y := b.position.y + b.size.y * 0.8
	var z := b.position.z * 0.36
	_put(xf * Vector3(0.0, y, z), xf * Vector3(0.0, y - 0.9, b.position.z - 20.0), xf.basis.y)
	fov = 68.0


## The FPV drone: a damped spring toward its spot round the car, carrying the car's own motion
## (in the replay's clock, so it keeps up at any speed and hovers when it's paused), banking
## into the turns it makes, a wide lens, a touch of prop-wash wobble.
func _drone_cam(dt: float, dt_play: float, c: Vector3, fwd: Vector3) -> void:
	var h_all := absf(dt_play)
	var right := fwd.cross(Vector3.UP).normalized()
	if _fresh:
		_drone = c + Vector3.UP * 1.5 - fwd * 8.0
		_drone_v = target_vel
		_drone_leg = 0
		_drone_leg_t = 0.0
		_drone_roll = 0.0
	_drone_leg_t += h_all
	if _drone_leg_t > DRONE_LEG_TIME:
		_drone_leg_t = 0.0
		_drone_leg = (_drone_leg + 1) % DRONE_LEGS.size()
	var o: Vector3 = DRONE_LEGS[_drone_leg]
	var goal := c + right * o.x + Vector3.UP * o.y - fwd * o.z
	var carv := (c - _prev_p) / h_all if h_all > 1e-5 and _have_prev and not _fresh else Vector3.ZERO
	var steps := ceili(minf(h_all, 0.25) / DRONE_STEP)
	var h := minf(h_all, 0.25) / maxi(steps, 1)
	for i in steps:
		_drone_acc = (goal - _drone) * 7.0 + (carv - _drone_v) * 4.2
		_drone_v += _drone_acc * h
		_drone += _drone_v * h
	# never below half a metre over the ground, never behind a tree from the car
	var floor_y := ground_at(_drone) + 0.5
	if _drone.y < floor_y:
		_drone.y = floor_y
		_drone_v.y = maxf(_drone_v.y, 0.0)
	var from := c + Vector3.UP * 0.8
	var hit := _ray(from, _drone)
	if not hit.is_empty():
		_drone = (hit.position as Vector3).lerp(from, 0.15)
	var ahead := (_drone - c).dot(fwd)
	var look := c + fwd * 3.0 * clampf(1.0 - ahead / 4.0, 0.0, 1.0) + Vector3.UP * 0.4
	var view := (look - _drone).normalized()
	var side := view.cross(Vector3.UP).normalized()
	var bank := clampf(-_drone_acc.dot(side) * 0.035, -0.75, 0.75)
	_drone_roll = lerpf(_drone_roll, bank, clampf(dt * 5.0, 0.0, 1.0))
	_wobble_t += dt
	var wob := Vector3(sin(_wobble_t * 37.0) * 0.004 + sin(_wobble_t * 23.0) * 0.003, 0.0, sin(_wobble_t * 29.0) * 0.006)
	if _drone.distance_to(look) > 0.2:
		var xf := Transform3D(Basis(), _drone).looking_at(look, Vector3.UP)
		xf.basis = xf.basis * Basis(Vector3.FORWARD, _drone_roll) * Basis.from_euler(wob)
		global_transform = xf
	fov = 96.0 if _fresh else lerpf(fov, 96.0, clampf(dt * 3.0, 0.0, 1.0))


## The helicopter: high and off to one side, a little behind, eased after the car.
func _heli_cam(dt: float, dt_play: float, c: Vector3, fwd: Vector3) -> void:
	var right := fwd.cross(Vector3.UP).normalized()
	var want := c - fwd * 14.0 + right * 12.0 * _heli_side + Vector3.UP * 13.0
	if _fresh:
		_heli = want
	else:
		_heli = _heli.lerp(want, 1.0 - exp(-2.5 * absf(dt_play)))
	_heli.y = maxf(_heli.y, ground_at(_heli) + 4.0)
	_put(_heli, c + fwd * 5.0, Vector3.UP)
	fov = 48.0


## The trackside TV camera: by the road ahead, pans and zooms after the car, the next one set up
## further on once it's gone by.
func _tv_cam(dt: float, c: Vector3) -> void:
	var at: Dictionary = st.locate(c, _tv_hint)
	_tv_hint = int(at.i)
	var s_car := float(at.s)
	var fwd_s: Vector3 = st.forward_at(s_car)
	var v := target_vel
	var dir := 1.0
	if v.length() > 2.0:
		dir = 1.0 if v.dot(fwd_s) >= 0.0 else -1.0
	elif (-target.global_transform.basis.z).dot(fwd_s) < 0.0:
		dir = -1.0
	var replace := _fresh or _tv.is_empty()
	if not replace:
		var past := _ds(s_car, float(_tv.s)) * dir        # + : the car's gone by it
		replace = past > 22.0 or past < -330.0 or c.distance_to(_tv.pos) > 420.0
		_los_t += dt
		if _los_t > 0.2:
			_los_t = 0.0
			var blocked := not _ray(_tv.pos, c + Vector3.UP * 0.7).is_empty()
			_tv.blocked = float(_tv.blocked) + 0.2 if blocked else 0.0
			replace = replace or float(_tv.blocked) > 0.8
	if replace:
		_tv_place(s_car, dir, v.length())
		_aim = c + Vector3.UP * 0.7
		_fov_s = _tv_fov(c)
	_aim = _aim.lerp(c + Vector3.UP * 0.7, clampf(dt * 9.0, 0.0, 1.0))
	_fov_s = lerpf(_fov_s, _tv_fov(c), clampf(dt * 4.0, 0.0, 1.0))
	_put(_tv.pos, _aim, Vector3.UP)
	fov = _fov_s


func _tv_fov(c: Vector3) -> float:
	var dist := c.distance_to(global_position if _tv.is_empty() else _tv.pos)
	return clampf(rad_to_deg(2.0 * atan(5.0 / maxf(dist, 1.0))), 10.0, 62.0)


## Where the next trackside camera stands: ~2.5 s up the road (45-170 m), on the outside of
## the bend there. On a stage a crane over the road's edge line, 4 m up (the trees stand back
## from the road, the touge's cedars close: their canopies have no collision, so the camera
## keeps to the road's own airspace, and a spot with a trunk, a bank or a wall close by is passed
## over for the next one along); on a highway beyond its own carriageway's shoulder; on a circuit
## up a tower past the run-off, over the catch fences.
func _tv_place(s_car: float, dir: float, v: float) -> void:
	var s0 := s_car + dir * clampf(v * 2.6, 45.0, 170.0)
	var k := _curv(s0)
	if absf(k) > 0.002:
		_tv_side = -signf(k) * dir
	else:
		_tv_side = -_tv_side
	var first := {}
	for step in [0.0, 9.0, -9.0, 18.0, 27.0, -18.0, 36.0]:
		for side in [_tv_side, -_tv_side]:
			var spot := _tv_spot(s0 + dir * float(step), side)
			if first.is_empty():
				first = spot
			if _clear(spot.pos, 3.0):
				_tv = spot
				_los_t = 0.0
				return
	first.pos = (first.pos as Vector3) + Vector3.UP * 4.0     # (nowhere clear: higher, over the first spot)
	_tv = first
	_los_t = 0.0


## A trackside spot at road position s, on one side (+1: the right).
func _tv_spot(s: float, side: float) -> Dictionary:
	if st.has_method("wrap_s"):
		s = float(st.wrap_s(s))
	else:
		s = clampf(s, 4.0, float(st.length) - 4.0)
	var half: float = float(st.width_at(s)) * 0.5 - 0.8
	var up := 4.0
	if st.has_method("half_at"):                      # a circuit: off the track, a tower over the fences
		half = float(st.half_at(s)) + 6.0
		up = 8.0
	elif st.has_method("wrap_s"):                     # the loop: beyond its own carriageway's shoulder
		side = 1.0
		half += 3.4
		up = 3.0
	var road: Vector3 = st.world_at(s, side * half)
	var g := ground_at(Vector3(road.x, road.y + 40.0, road.z), 40.0)
	return {"pos": Vector3(road.x, maxf(g + 1.2, road.y + up), road.z), "s": s, "blocked": 0.0}


## Nothing solid (a trunk, a bank, a wall) within r of p (the traffic doesn't count).
func _clear(p: Vector3, r: float) -> bool:
	if not is_inside_tree():
		return true
	var q := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = r
	q.shape = ball
	q.transform = Transform3D(Basis(), p)
	q.collision_mask = 1
	for h in get_world_3d().direct_space_state.intersect_shape(q, 8):
		var col: Object = h.collider
		if col and not col.has_meta("traffic"):
			return false
	return true


## Free follow: an orbit round the car, turned with it (eased); the right mouse button or the
## right stick swings it round, the wheel / triggers / W S zoom, A D swing it too, Q E lower
## and raise it.
func _orbit_cam(dt: float, c: Vector3, fwd: Vector3, look_in: Vector2) -> void:
	if _fresh:
		_head = fwd
	_head = _head.slerp(fwd, clampf(dt * 2.0, 0.0, 1.0)).normalized()
	orbit_yaw -= look_in.x
	orbit_pitch = clampf(orbit_pitch + look_in.y, -0.05, 1.45)
	var zoom := _wheel
	_wheel = 0.0
	if input_on:
		zoom += (Input.get_action_strength("replay_fly_forward") - Input.get_action_strength("replay_fly_back")) * dt * 2.5
		zoom += (Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)) * dt * 2.5
		orbit_yaw += (Input.get_action_strength("replay_fly_right") - Input.get_action_strength("replay_fly_left")) * dt * 1.5
		orbit_pitch = clampf(orbit_pitch + (Input.get_action_strength("replay_fly_up") - Input.get_action_strength("replay_fly_down")) * dt * 0.8, -0.05, 1.45)
	orbit_dist = clampf(orbit_dist * pow(0.88, zoom), 2.5, 60.0)
	var back := (-_head).rotated(Vector3.UP, orbit_yaw)
	var centre := c + Vector3.UP * (0.6 + orbit_lift)
	var p := centre + back * cos(orbit_pitch) * orbit_dist + Vector3.UP * sin(orbit_pitch) * orbit_dist
	p.y = maxf(p.y, ground_at(p) + CLEAR)
	_put(p, centre, Vector3.UP)
	fov = 62.0


## The free cam: flies by its own keys, in real time (the replay can be paused under it).
func _free_cam(dt: float, look_in: Vector2) -> void:
	free_yaw -= look_in.x
	free_pitch = clampf(free_pitch - look_in.y, -1.5, 1.5)
	var basis := Basis.from_euler(Vector3(free_pitch, free_yaw, 0.0), EULER_ORDER_YXZ)
	var move := Vector3.ZERO
	var spd := FREE_SPEED
	if input_on:
		move += -basis.z * (Input.get_action_strength("replay_fly_forward") - Input.get_action_strength("replay_fly_back"))
		move += basis.x * (Input.get_action_strength("replay_fly_right") - Input.get_action_strength("replay_fly_left"))
		move += Vector3.UP * (Input.get_action_strength("replay_fly_up") - Input.get_action_strength("replay_fly_down"))
		spd *= lerpf(1.0, 4.0, Input.get_action_strength("replay_fly_fast"))
		spd *= lerpf(1.0, 0.25, Input.get_action_strength("replay_fly_slow"))
	spd *= pow(1.25, _wheel)
	_wheel = 0.0
	var was := free_pos
	free_pos += move.limit_length(1.0) * spd * dt
	var floor_y := ground_at(Vector3(free_pos.x, maxf(was.y, free_pos.y), free_pos.z)) + CLEAR
	free_pos.y = maxf(free_pos.y, floor_y)
	global_transform = Transform3D(basis, free_pos)
	fov = 70.0


## A placed camera: where it was put, turned onto the car (eased), zoomed with the distance.
func _placed_cam(dt: float, c: Vector3) -> void:
	if shot < 0 or shot >= placed.size():
		return
	var p: Vector3 = placed[shot]
	var want := c + Vector3.UP * 0.6
	var f := clampf(rad_to_deg(2.0 * atan(4.5 / maxf(p.distance_to(c), 1.0))), 6.0, 70.0)
	if _fresh:
		_aim = want
		_fov_s = f
	_aim = _aim.lerp(want, clampf(dt * 8.0, 0.0, 1.0))
	_fov_s = lerpf(_fov_s, f, clampf(dt * 4.0, 0.0, 1.0))
	_put(p, _aim, Vector3.UP)
	fov = _fov_s


## The director: the nearest placed camera that can see the car; a cut only once the camera on
## has been held SHOT_MIN s and another's clearly better (or this one's lost the car).
func _director(dt: float, c: Vector3) -> void:
	_shot_t += dt
	if placed.is_empty():
		return
	if shot < 0 or shot >= placed.size():
		shot = _director_pick(-1)
		_shot_t = 0.0
		_fresh = true
		return
	_los_t += dt
	if _los_t < 0.15 and not _fresh:
		return
	_los_t = 0.0
	var best := _director_pick(shot)
	if best != shot and _shot_t >= SHOT_MIN:
		shot = best
		_shot_t = 0.0
		_fresh = true
		message.emit("DIRECTOR: CAM %d" % (shot + 1))


## The best placed camera for the car now (a camera that sees it over one that doesn't, then the
## nearest); keep: the one on now, which wins unless another is a third nearer or it can't see.
func _director_pick(keep: int) -> int:
	if target == null or placed.is_empty():
		return -1
	var c := target.global_position + Vector3.UP * 0.7
	var best := -1
	var best_score := INF
	var keep_score := INF
	for i in placed.size():
		var p: Vector3 = placed[i]
		var d := p.distance_to(c)
		var score := d + (0.0 if _ray(p, c).is_empty() else 10000.0)
		if i == keep:
			keep_score = score
		if score < best_score:
			best_score = score
			best = i
	if keep >= 0 and keep_score < 10000.0 and keep_score <= best_score * 1.33:
		return keep
	return best


# ── helpers ───────────────────────────────────────────────────────────────

## The cockpit's seat for your car ("driver", or "codriver" riding shotgun).
func _seat() -> String:
	var s := str(game.my_seat) if game else "driver"
	return "codriver" if s == "codriver" else "driver"


## Can the cockpit camera sit in this car? Yours always (its cockpit); another's if its model
## has an interior of its own.
func _has_eye(c) -> bool:
	if game and c == game.car and game.cockpit:
		return true
	return c.has_method("cockpit_info") and not c.cockpit_info().is_empty()


## The driver's eyes in car c (its own space).
func _eye(c) -> Vector3:
	if game and c == game.car and game.cockpit:
		return game.cockpit.eye_for(_seat())
	var info: Dictionary = c.cockpit_info() if c.has_method("cockpit_info") else {}
	if info.has("eye"):
		var e: Array = info.eye
		return Vector3(float(e[0]), float(e[1]), float(e[2])) + c.model_offset()
	return Cockpit.EYE_DRIVER


## Your car seen from its seat or from outside: the body or the cockpit drawn, your own helmet
## hidden from your eyes (as the game's own camera does it).
func _apply_view() -> void:
	if game == null or not is_instance_valid(game.car):
		return
	var mine: bool = mode == "cockpit" and target == game.car and game.cockpit != null
	game.car.set_outside(not mine)
	if game.cockpit:
		game.cockpit.visible = (mine and not game.cockpit.hood) or game.cockpit.own_interior()
		game.cockpit.set_my_seat(_seat() if mine else "")
	cull_mask = 0xFFFFF & ~(1 << (1 if _seat() == "driver" else 2)) if mine else 0xFFFFF


## Car c's body box in its own space (cached): the model's meshes, or its collision boxes.
func _box(c) -> AABB:
	var id: int = c.get_instance_id()
	if not _dims.has(id):
		var body = c.get("body_model")
		if body != null and is_instance_valid(body):
			_dims[id] = CarLamps.bounds(c, body)
		elif c.get("config") != null:
			var cfg: Resource = c.config
			_dims[id] = AABB(cfg.body_center - cfg.body_size * 0.5, cfg.body_size).merge(AABB(cfg.cabin_center - cfg.cabin_size * 0.5, cfg.cabin_size))
		else:
			_dims[id] = AABB(Vector3(-0.9, -0.45, -2.2), Vector3(1.8, 1.35, 4.4))
	return _dims[id]


## Put the camera at p looking at t (up: which way is up).
func _put(p: Vector3, t: Vector3, up: Vector3) -> void:
	var d := t - p
	if d.length_squared() < 1e-4:
		return
	if absf(d.normalized().dot(up.normalized())) > 0.995:
		up = Vector3.FORWARD
	global_transform = Transform3D(Basis(), p).looking_at(t, up)


static func _flat(v: Vector3) -> Vector3:
	var f := Vector3(v.x, 0.0, v.z)
	return f.normalized() if f.length_squared() > 1e-6 else Vector3.FORWARD


## How far a is along the road past b (round a loop: the short way).
func _ds(a: float, b: float) -> float:
	var x := a - b
	if st.has_method("wrap_s"):
		return wrapf(x, -float(st.length) * 0.5, float(st.length) * 0.5)
	return x


## The road's curvature at s (+ : bending right).
func _curv(s: float) -> float:
	if st.has_method("curv_at"):
		return float(st.curv_at(s))
	var cv: PackedFloat32Array = st.curv
	if cv.is_empty():
		return 0.0
	return cv[clampi(int(s / float(st.STEP)), 0, cv.size() - 1)]


## The ground under p: a ray down from a little above it (from `above` m over it: a camera that
## has sunk into a hill comes back out), the traffic's cars not counted; where the ray finds
## nothing, the stage's own land (the loop's lakes: their water).
func ground_at(p: Vector3, above := 1.0) -> float:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space:
		var ex: Array = []
		for i in 4:
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * above, p - Vector3.UP * 600.0, 1, ex)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				break
			var col: Object = hit.collider
			if col and col.has_meta("traffic"):
				ex.append(hit.rid)
				continue
			return (hit.position as Vector3).y
	return _land(p)


## The stage's own land at p (no physics): the loop's and the circuit's land, a mountain stage's
## slope, the road where it's over the road.
func _land(p: Vector3) -> float:
	var h := 0.0
	if st == null:
		return h
	if st.has_method("land_at"):
		h = maxf(float(st.land_at(p.x, p.z)), 0.0)
	elif st.has_method("terrain_at"):
		h = float(st.terrain_at(p.x, p.z))
	var at: Dictionary = st.locate(p)
	if absf(float(at.d)) < float(st.width_at(float(at.s))) * 0.5 + 2.0:
		h = maxf(h, float(st.world_at(float(at.s), float(at.d)).y))
	return h


## A ray from a to b through the stage (not the cars, not the traffic): what it hits first, or {}.
func _ray(a: Vector3, b: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}
	var space := get_world_3d().direct_space_state
	var ex: Array = []
	for i in 4:
		var q := PhysicsRayQueryParameters3D.create(a, b, 1, ex)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return {}
		var col: Object = hit.collider
		if col and col.has_meta("traffic"):
			ex.append(hit.rid)
			continue
		return hit
	return {}


# ── the placed cameras, kept per stage ────────────────────────────────────

func _store_path() -> String:
	var Profile = load("res://scripts/game/profile.gd")
	return str(Profile.path()).get_base_dir().path_join("replay_cams.cfg")


func _load_placed() -> void:
	placed.clear()
	var cf := ConfigFile.new()
	if cf.load(_store_path()) != OK:
		return
	var saved = cf.get_value("placed", _save_key, [])
	if saved is Array:
		for v in saved:
			if v is Vector3:
				placed.append(v)


func _save_placed() -> void:
	var cf := ConfigFile.new()
	cf.load(_store_path())
	if placed.is_empty():
		if cf.has_section_key("placed", _save_key):
			cf.erase_section_key("placed", _save_key)
	else:
		cf.set_value("placed", _save_key, placed.duplicate())
	cf.save(_store_path())
