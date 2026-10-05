extends RigidBody3D
## Physics v2 (docs/physics_rebuild.md), built alongside the current car
## (scripts/vehicle/rally_car.gd) until it can replace it.
## Phase 1: the chassis. A RigidBody3D with the mass, centre of mass and inertia
## of a ~1,280 kg AWD rally car (data/cars/awd_rally.tres), on four suspension
## corners (rally_wheel.gd: a ShapeCast3D tyre each, spring + damper + bump
## stop pushing at the contact patch). Nothing is faked: no damping on the
## body, no levelling, no smoothing; pitch and roll come from where the forces
## act.
## Phase 2: the tyres grip sideways (slip angle -> side force at each patch)
## and the front wheels steer: input x lock, no faster than the rack turns,
## split by the Ackermann geometry. No drive or brakes yet (phase 3).
## Runs at 120 physics ticks a second (the scene that uses it sets that).
##
## The scene (scenes/rally_car_v2.tscn): RallyCarV2 (this) > CollisionShape3D x2,
## CarMesh, CenterOfMass, FL / FR / RL / RR _WheelPoint (rally_wheel.gd, each
## with a ShapeCast3D and a WheelMesh), Telemetry (F3 numbers, F4 force arrows).
## Made with RallyCarV2.new() instead, it builds the same nodes itself.
## The car faces -Z; the origin is the middle of the chassis at mount height.

signal landed(impact: float)       # came down onto its wheels (m/s downward)

const RallyWheel = preload("res://scripts/vehicle/physics/rally_wheel.gd")
const Telemetry = preload("res://scripts/vehicle/physics/rally_telemetry.gd")
const DEFAULT_CONFIG := "res://data/cars/awd_rally.tres"
const TICKS := 120                 # physics ticks per second (see the plan: the wheels are stiff)
const NAMES := ["FL", "FR", "RL", "RR"]

## The car's numbers (a CarConfig resource).
@export var config: Resource
## Show the telemetry HUD from the start (F3 toggles it).
@export var show_telemetry := false

# the same names as the current car, so the game, cockpit, FX and tests can use either
var inp := {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": false}
var simulate := true
var speed := 0.0                   # along the car (m/s, + = forward)
var steer := 0.0                   # front wheel angle (rad)
var grounded := 0                  # tyres touching
var comp := [0.0, 0.0, 0.0, 0.0]   # spring compression per corner (m)
var wheel_angles := [0.0, 0.0]     # front left / right road-wheel angles (rad, + = right)
var accel := Vector3.ZERO          # the body's acceleration last tick (m/s², world)
var on_surface := "gravel"
var wheels: Array = []             # RallyWheel: FL, FR, RL, RR
var telemetry: CanvasLayer

var _air := 0.0
var _rack := 0.0                   # the steering rack: the "bicycle" front-wheel angle (rad, + = right)
var _prev_v := Vector3.ZERO


func _ready() -> void:
	if config == null:
		config = load(DEFAULT_CONFIG)
	mass = config.mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = config.center_of_mass
	inertia = config.inertia
	# no invented drag on the body: REPLACE the project's default damping with none
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	collision_layer = 2
	collision_mask = 1
	can_sleep = false
	var pm := PhysicsMaterial.new()
	pm.friction = 0.4                                # the body sliding on its roof / side
	pm.bounce = 0.05
	physics_material_override = pm
	if find_children("*", "CollisionShape3D", false, false).is_empty():
		_box("Body", config.body_size, config.body_center)
		_box("Cabin", config.cabin_size, config.cabin_center)
	var com_marker := get_node_or_null("CenterOfMass") as Node3D
	if com_marker == null:
		com_marker = Marker3D.new()
		com_marker.name = "CenterOfMass"
		add_child(com_marker)
	com_marker.position = config.center_of_mass
	var mounts: Array = config.mounts()
	for k in 4:
		var w = get_node_or_null(NAMES[k] + "_WheelPoint")
		if w == null:
			w = RallyWheel.new()
			w.name = NAMES[k] + "_WheelPoint"
			add_child(w)
		w.position = mounts[k]
		w.front = k < 2
		w.setup(self, config.front_suspension if k < 2 else config.rear_suspension,
			config.front_tire if k < 2 else config.rear_tire, config.tyre_radius, config.tyre_width, config.wheel_inertia)
		wheels.append(w)
	telemetry = get_node_or_null("Telemetry")
	if telemetry == null:
		telemetry = Telemetry.new()
		telemetry.name = "Telemetry"
		add_child(telemetry)
	telemetry.car = self
	telemetry.visible = show_telemetry


func _box(n: String, size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = n
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = at
	add_child(cs)


## Put the car down at (pos, yaw), still, sitting at its ride height above pos.
func place(pos: Vector3, yaw: float) -> void:
	global_transform = Transform3D(Basis(Vector3.UP, -yaw), pos + Vector3.UP * ride_height())
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_v = Vector3.ZERO
	_rack = 0.0                                      # wheels straight (a car put down doesn't keep its old lock)
	inp.steer = 0.0
	_steer(0.0)
	for w in wheels:
		w.slip_lat = 0.0
		w.slip_long = 0.0
		w.omega = 0.0
	reset_physics_interpolation()


## Set it rolling straight ahead at v m/s, the wheels turning with it (a car
## launched with still wheels would skid them up to speed first).
func set_speed(v: float) -> void:
	linear_velocity = -global_transform.basis.z * v
	_prev_v = linear_velocity
	for w in wheels:
		w.omega = v / w.radius


## How high the mounts sit above flat ground with the car standing still (m),
## from the springs and the weight on them.
func ride_height() -> float:
	var loads: Array = config.static_loads(_gravity())
	var Suspension = RallyWheel.Suspension
	var c: float = (Suspension.static_compression(config.front_suspension, loads[0])
		+ Suspension.static_compression(config.rear_suspension, loads[1])) * 0.5
	var travel: float = (config.front_suspension.travel + config.rear_suspension.travel) * 0.5
	return config.tyre_radius + travel - c - config.mount_height


func set_simulating(on: bool) -> void:
	simulate = on
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = not on


func kmh() -> float:
	return absf(speed) * 3.6


func _physics_process(dt: float) -> void:
	if not simulate:
		return
	speed = linear_velocity.dot(-global_transform.basis.z)
	accel = (linear_velocity - _prev_v) / dt
	_prev_v = linear_velocity
	_steer(dt)
	_brakes()
	var was := grounded
	grounded = 0
	for k in 4:
		var w = wheels[k]
		w.step(dt)
		comp[k] = w.compression
		if w.grounded:
			grounded += 1
			if w.collider and w.collider.has_meta("surface"):
				on_surface = w.collider.get_meta("surface")
	if grounded == 0:
		_air += dt
	else:
		if was == 0 and _air > 0.25:
			landed.emit(maxf(-linear_velocity.y, 0.0))
		_air = 0.0


## The pedal: the brakes' torque, split front / rear by the bias, left / right evenly.
func _brakes() -> void:
	var pedal := clampf(float(inp.brake), 0.0, 1.0)
	var front: float = config.brake_torque * config.brake_bias * 0.5 * pedal
	var rear: float = config.brake_torque * (1.0 - config.brake_bias) * 0.5 * pedal
	for k in 4:
		wheels[k].brake_torque = front if k < 2 else rear


## The rack follows the input (no faster than rack_speed); each front wheel's
## angle from the geometry: with full Ackermann the inside wheel turns more, so
## both roll round the same centre (on the rear axle's line).
func _steer(dt: float) -> void:
	if wheels.size() != 4:                           # not set up yet (placed before it's in the tree)
		return
	var st: Resource = config.steering
	var lock := deg_to_rad(st.max_angle_deg)
	_rack = move_toward(_rack, clampf(float(inp.steer), -1.0, 1.0) * lock, deg_to_rad(st.rack_speed_deg) * dt)
	steer = _rack
	var a := absf(_rack)
	var inner := a
	var outer := a
	if a > 1e-4:
		var base: float = config.rear_axle - config.front_axle
		var r := base / tan(a)                       # the turn's radius at the rear axle's middle
		var half: float = config.front_track * 0.5
		inner = lerpf(a, atan(base / (r - half)), st.ackermann)
		outer = lerpf(a, atan(base / (r + half)), st.ackermann)
	var s := signf(_rack)
	# turning right (+), the right wheel (FR) is on the inside
	wheel_angles = [s * (outer if s > 0.0 else inner), s * (inner if s > 0.0 else outer)]
	for k in 2:
		wheels[k].rotation.y = -wheel_angles[k]      # + steer = right = clockwise from above


func _process(dt: float) -> void:
	for k in 4:
		wheels[k].update_visual(dt)


func _gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
