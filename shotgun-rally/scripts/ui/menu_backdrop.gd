extends Node3D
## Behind the home screen: the game itself. A short stage, golden evening
## light, and your own car (from the garage, in its livery) driving it flat out
## by itself, filmed like rally TV: an FPV drone chasing it (swooping from low
## behind to alongside, over the roof and ahead, banking into its turns),
## trackside cameras it flashes past, a chase camera, a helicopter shot. In the
## garage the car parks on a straight and the camera circles it slowly
## (show_car() repaints it as you shop).
## Built a step a frame after the menu appears (ready_to_show when it's there).

signal ready_to_show

const StageGen = preload("res://scripts/stage/stage_gen.gd")
const StageBuilder = preload("res://scripts/stage/stage_builder.gd")
const RallyCar = preload("res://scripts/vehicle/rally_car.gd")
const DriftFx = preload("res://scripts/vehicle/drift_fx.gd")
const Autopilot = preload("res://scripts/vehicle/autopilot.gd")
const SEED := 2217                  # Lakeland SS1: fast, a big jump, pretty
const LENGTH := 1700.0

var st
var car
var cam: Camera3D
var showroom := false
var built := false
var _ap
var _hint := -1
var _shot := {}
var _shot_t := 0.0
var _shot_i := 0
var _park_s := 0.0
var _orbit := 0.0
var _stuck := 0.0
var _setup := {}
# the FPV drone: where it is, how fast it's going, how far it's banked
var _drone := Vector3.ZERO
var _drone_v := Vector3.ZERO
var _drone_roll := 0.0
var _drone_leg := 0
var _drone_leg_t := 0.0
var _wobble_t := 0.0
## where the drone heads, round the car (car-local: x right, y up, z behind), in turn
const DRONE_LEGS := [Vector3(0.0, 1.1, 7.0), Vector3(3.4, 0.9, 1.5), Vector3(0.0, 3.4, -4.0), Vector3(-3.2, 1.0, 2.0),
	Vector3(0.0, 0.7, 9.0), Vector3(2.6, 2.2, -1.0)]
const DRONE_LEG_TIME := 2.6       # s on each
const DRONE_STEP := 1.0 / 120.0   # its flight is worked out in steps this short, whatever the frame rate


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 58.0
	cam.near = 0.05
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	_build.call_deferred()


func _build() -> void:
	st = StageGen.new()
	st.generate(SEED, LENGTH)
	var builder = StageBuilder.new()
	builder.mood = "golden"
	add_child(builder)
	await builder.build_async(st, func(_f: float, _w: String): pass)
	if not is_inside_tree():
		return
	car = RallyCar.new()
	car.name = "MenuCar"
	car.setup = _setup
	add_child(car)
	car.set_simulating(true)
	car.set_outside(true)
	var fx = DriftFx.new()
	fx.car = car
	car.add_child(fx)
	_ap = Autopilot.new(st)
	_park_s = st.START_S + 300.0                  # a straight well away from the start arch
	for run in st._straight_runs(40.0):
		if run.x > st.START_S + 150.0:
			_park_s = (run.x + run.y) * 0.5
			break
	if showroom:                                  # (the garage opened before the car was built)
		car.place(st.world_at(_park_s, 0.0), st.heading_at(_park_s))
	else:
		_restart()
	built = true
	_next_shot()
	ready_to_show.emit()


## Paint the car (the garage calls this as you shop): a Catalog.setup.
func show_car(setup: Dictionary) -> void:
	_setup = setup
	if car and car.apply_setup(setup):              # another car: its own body and wheels, put down again
		if showroom:
			car.place(st.world_at(_park_s, 0.0), st.heading_at(_park_s))
		else:
			_restart()


## Garage: park and circle the car; home: back to racing.
func set_showroom(on: bool) -> void:
	if showroom == on:
		return
	showroom = on
	if car == null:
		return
	if on:
		car.place(st.world_at(_park_s, 0.0), st.heading_at(_park_s))
		_hint = -1
		_orbit = 0.6
	else:
		_restart()
		_next_shot()


func _restart() -> void:
	var s0: float = st.START_S + 10.0
	car.place(st.world_at(s0, 0.0), st.heading_at(s0))
	car.linear_velocity = st.forward_at(s0) * 14.0
	_hint = -1
	_stuck = 0.0


func _physics_process(dt: float) -> void:
	if not built:
		return
	var at: Dictionary = st.locate(car.global_position, _hint)
	_hint = at.i
	car.set_lanes(st, at.s, at.d)
	if showroom:                                  # parked (the handbrake too: a held brake alone picks reverse)
		car.inp = {"steer": 0.0, "throttle": 0.0, "brake": 1.0, "handbrake": true}
		return
	car.inp = _ap.drive(car, at.s, at.d)
	# round again from the start at the end of the road, or if it ever gets stuck / rolls
	_stuck = _stuck + dt if car.linear_velocity.length() < 2.0 else 0.0
	if at.s > st.finish_s - 20.0 or _stuck > 2.5 or car.global_transform.basis.y.y < 0.3:
		_restart()
		_next_shot()


func _process(dt: float) -> void:
	if not built:
		return
	var c: Vector3 = car.global_position
	var fwd: Vector3 = -car.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	if showroom:
		# circle the parked car, low, framed to the right of the garage panel
		_orbit += dt * 0.16
		var p := c + Vector3(cos(_orbit) * 5.2, 1.15, sin(_orbit) * 5.2)
		var right := (c - p).cross(Vector3.UP).normalized()
		_place(p, c + Vector3.UP * 0.3 - right * 1.9, dt, 4.0)      # look left of it: the car sits right of the panel
		return
	_shot_t += dt
	var at: Dictionary = st.locate(c, _hint)
	match _shot.kind:
		"trackside":                     # a camera on the bank: the car comes at it and flashes past
			_place(_shot.pos, c + Vector3.UP * 0.4, dt, 0.0)
			cam.fov = lerpf(cam.fov, clampf(70.0 - 900.0 / maxf(_shot.pos.distance_to(c), 8.0), 26.0, 60.0), dt * 2.0)
			if at.s > _shot.s + 22.0 or _shot_t > 9.0:
				_next_shot()
		"chase":
			_place(c - fwd * 7.5 + Vector3.UP * 2.3, c + fwd * 4.0 + Vector3.UP * 0.6, dt, 5.0)
			cam.fov = lerpf(cam.fov, 62.0, dt * 2.0)
			if _shot_t > 5.5:
				_next_shot()
		"heli":                          # high and to the side, tracking
			var right := fwd.cross(Vector3.UP).normalized()
			_place(c + right * _shot.side * 16.0 + Vector3.UP * 11.0 - fwd * 4.0, c + fwd * 6.0, dt, 2.0)
			cam.fov = lerpf(cam.fov, 50.0, dt * 2.0)
			if _shot_t > 6.0:
				_next_shot()
		"fpv":
			_fpv(dt, c, fwd)
			if _shot_t > 13.0:
				_next_shot()
		"front":                         # just ahead of the bonnet, looking back at it
			_place(c + fwd * 6.5 + Vector3.UP * 0.9, c + Vector3.UP * 0.5, dt, 6.0)
			cam.fov = lerpf(cam.fov, 55.0, dt * 2.0)
			if _shot_t > 4.0:
				_next_shot()


## Move the camera to p looking at t; smooth > 0 eases it there (per second).
func _place(p: Vector3, t: Vector3, dt: float, smooth: float) -> void:
	var to := p if smooth <= 0.0 else cam.global_position.lerp(p, clampf(dt * smooth, 0.0, 1.0))
	if to.distance_to(t) > 0.1:
		cam.global_transform = Transform3D(Basis(), to).looking_at(t, Vector3.UP)


## The FPV drone: a little quad flying a spring toward its spot round the car (the
## car's own speed carried, so it keeps up), banking into the turns it makes as
## FPV drones do, a wide lens, a touch of prop-wash wobble; never into the
## ground, and in front of a tree rather than behind it.
func _fpv(dt: float, c: Vector3, fwd: Vector3) -> void:
	_drone_leg_t += dt
	if _drone_leg_t > DRONE_LEG_TIME:
		_drone_leg_t = 0.0
		_drone_leg = (_drone_leg + 1) % DRONE_LEGS.size()
	var right := fwd.cross(Vector3.UP).normalized()
	var o: Vector3 = DRONE_LEGS[_drone_leg]
	var goal := c + right * o.x + Vector3.UP * o.y - fwd * o.z
	var carv: Vector3 = car.linear_velocity
	var steps := ceili(minf(dt, 0.1) / DRONE_STEP)
	var h := minf(dt, 0.1) / maxi(steps, 1)
	var acc := Vector3.ZERO
	for i in steps:
		# a damped spring toward the goal, relative to the car's own motion
		acc = (goal - _drone) * 7.0 + (carv - _drone_v) * 4.2
		_drone_v += acc * h
		_drone += _drone_v * h
	# never below 0.5 m over the ground, never behind a tree from the car
	var space := get_world_3d().direct_space_state
	var down := PhysicsRayQueryParameters3D.create(_drone + Vector3.UP * 3.0, _drone - Vector3.UP * 3.0, 1, [car.get_rid()])
	var g := space.intersect_ray(down)
	if not g.is_empty() and _drone.y < g.position.y + 0.5:
		_drone.y = g.position.y + 0.5
		_drone_v.y = maxf(_drone_v.y, 0.0)
	var los := PhysicsRayQueryParameters3D.create(c + Vector3.UP * 0.8, _drone, 1, [car.get_rid()])
	var hit := space.intersect_ray(los)
	if not hit.is_empty():
		_drone = (hit.position as Vector3).lerp(c + Vector3.UP * 0.8, 0.15)
	# look ahead of the car (at the car itself once the drone's out in front),
	# banked by the turn the drone is making
	var ahead := (_drone - c).dot(fwd)
	var look := c + fwd * 3.0 * clampf(1.0 - ahead / 4.0, 0.0, 1.0) + Vector3.UP * 0.4
	var view := (look - _drone).normalized()
	var side := view.cross(Vector3.UP).normalized()
	var bank := clampf(-acc.dot(side) * 0.035, -0.75, 0.75)
	_drone_roll = lerpf(_drone_roll, bank, clampf(dt * 5.0, 0.0, 1.0))
	_wobble_t += dt
	var wob := Vector3(sin(_wobble_t * 37.0) * 0.004 + sin(_wobble_t * 23.0) * 0.003, 0.0, sin(_wobble_t * 29.0) * 0.006)
	if _drone.distance_to(look) > 0.2:
		var xf := Transform3D(Basis(), _drone).looking_at(look, Vector3.UP)
		xf.basis = xf.basis * Basis(Vector3.FORWARD, _drone_roll) * Basis.from_euler(wob)
		cam.global_transform = xf
	cam.fov = lerpf(cam.fov, 96.0, clampf(dt * 3.0, 0.0, 1.0))


func _next_shot() -> void:
	var kinds := ["fpv", "trackside", "chase", "fpv", "heli", "trackside", "front"]
	var kind: String = kinds[_shot_i % kinds.size()]
	_shot_i += 1
	_shot_t = 0.0
	var at: Dictionary = st.locate(car.global_position, _hint)
	match kind:
		"trackside":
			var s: float = minf(at.s + randf_range(55.0, 80.0), st.finish_s - 30.0)
			var side := -1.0 if randf() < 0.5 else 1.0
			var half: float = st.width_at(s) * 0.5
			var p: Vector3 = st.world_at(s, side * (half + randf_range(1.0, 2.2))) + Vector3.UP * randf_range(0.7, 1.4)
			_shot = {"kind": kind, "s": s, "pos": p}
			cam.global_position = p
		"heli":
			_shot = {"kind": kind, "side": -1.0 if randf() < 0.5 else 1.0}
		"fpv":
			_shot = {"kind": kind}
			var cf: Vector3 = -car.global_transform.basis.z
			_drone = car.global_position + Vector3.UP * 1.5 - cf * 8.0
			_drone_v = car.linear_velocity
			_drone_leg = 0
			_drone_leg_t = 0.0
		_:
			_shot = {"kind": kind}
	if kind != "trackside" and kind != "fpv":
		var c: Vector3 = car.global_position
		cam.global_position = c + Vector3(0.0, 3.0, 0.0) - (-car.global_transform.basis.z) * 8.0
