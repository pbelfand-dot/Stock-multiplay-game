extends Node3D
## Behind the home screen: the game itself. A short stage, golden evening
## light, and your own car (from the garage, in its livery) driving it flat out
## by itself, filmed like rally TV: trackside cameras it flashes past, a chase
## camera, a helicopter shot. In the garage the car parks on a straight and the
## camera circles it slowly (show_car() repaints it as you shop).
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
	add_child(car)
	car.set_simulating(true)
	car.set_outside(true)
	if not _setup.is_empty():
		car.apply_setup(_setup)
	var fx = DriftFx.new()
	fx.car = car
	car.add_child(fx)
	_ap = Autopilot.new(st)
	_park_s = st.START_S + 300.0                  # a straight well away from the start arch
	for run in st._straight_runs(40.0):
		if run.x > st.START_S + 150.0:
			_park_s = (run.x + run.y) * 0.5
			break
	_restart()
	built = true
	_next_shot()
	ready_to_show.emit()


## Paint the car (the garage calls this as you shop): a Catalog.setup.
func show_car(setup: Dictionary) -> void:
	_setup = setup
	if car:
		car.apply_setup(setup)


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
	if showroom:
		car.inp = {"steer": 0.0, "throttle": 0.0, "brake": 1.0, "handbrake": false}
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


func _next_shot() -> void:
	var kinds := ["trackside", "chase", "trackside", "heli", "trackside", "front"]
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
		_:
			_shot = {"kind": kind}
	if kind != "trackside":
		var c: Vector3 = car.global_position
		cam.global_position = c + Vector3(0.0, 3.0, 0.0) - (-car.global_transform.basis.z) * 8.0
