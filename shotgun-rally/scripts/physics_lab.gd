extends Node3D
## The physics lab (scenes/physics_lab.tscn): somewhere to try physics v2 and
## watch its telemetry. Run it: godot --path . scenes/physics_lab.tscn
##   * a big flat gravel pad, with room for a skid pad (circles at a steady speed)
##   * a strip of full-width bumps (8 cm, ~0.8 m long), to see the car pitch
##   * a lane of bumps under the left wheels only, to see it roll
##   * a 10 degree side slope, to see the tyres hold a parked car
## Keys: left / right (A D) steer   up (W) throttle   down (S) brakes (stopped,
## hold it: reverse)   E / Q change up / down (it changes by itself too)
## C a tow at 15 m/s through the centre of mass   R back on the pad   J drop it from a metre up
## B roll it over the bumps at 12 m/s   N over the left-side bumps   P park it
## across the side slope (O: nose uphill)   F3 numbers   F4 force arrows
## The tests build the same course (build_course) without the scene.
## A picture: ... scenes/physics_lab.tscn -- --screenshot=out.png [--lab=drop|bumps|left|skid|slope|brake|launch
## --shot_wait=1.5 --vectors]

const RallyCarV2 = preload("res://scripts/vehicle/physics/rally_car_v2.gd")
const CAR_SCENE := "res://scenes/rally_car_v2.tscn"
const PAD := Vector3(0.0, 0.0, 0.0)
const BUMPS_Z := -30.0             # the full-width bumps start here (the car drives -Z) ...
const BUMP_LANE_X := 10.0          # ... and the left-side ones in a lane over here
const BUMP_N := 6
const BUMP_GAP := 4.0              # m between bumps
const BUMP_R := 1.0                # each bump is the top of a cylinder this big ...
const BUMP_H := 0.08               # ... standing this far out of the ground
const SKID := Vector3(-150.0, 0.0, 150.0)   # skid pad runs start here, heading -Z (open ground all round)
const SLOPE := Vector3(80.0, 0.0, 120.0)    # the side slope's middle (its top surface passes through here)
const SLOPE_DEG := 10.0            # tilted about the car's long axis (Z): left side up
const TOW_SPEED := 15.0

var car: RigidBody3D
var cam: Camera3D
var _orbit := 0.6
var _shot_t := 0.0
var _tow := false
var _hold_steer := false           # keep a preset steering (the skid pad picture) until a key is pressed
var _auto_brake := false           # the braking picture: full brakes without a key
var _auto_throttle := false        # the launch picture: full throttle without a key


func _ready() -> void:
	Engine.physics_ticks_per_second = RallyCarV2.TICKS
	build_course(self)
	_light()
	car = (load(CAR_SCENE) as PackedScene).instantiate()
	car.show_telemetry = true
	add_child(car)
	car.place(PAD, 0.0)
	cam = Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	cam.current = true
	var hint := Label.new()
	hint.text = "arrows steer / throttle / brake   E Q gears   C tow   R reset   J drop   B / N bumps   P / O slope   F3 numbers   F4 forces"
	hint.add_theme_font_size_override("font_size", 16)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 14)
	var ui := CanvasLayer.new()
	ui.add_child(hint)
	add_child(ui)
	var config := get_node_or_null("/root/Config")   # (by path: the tests load this script without the autoloads)
	match config.arg("lab") if config else "":
		"drop":
			car.global_position.y += 1.0
		"bumps":
			launch(car, Vector3(0.0, 0.0, BUMPS_Z + 8.0), 12.0)
		"left":
			launch(car, Vector3(BUMP_LANE_X, 0.0, BUMPS_Z + 8.0), 12.0)
		"skid":
			launch(car, SKID, TOW_SPEED)
			_tow = true
			car.inp.steer = 0.3
			_hold_steer = true
		"slope":
			park_on_slope(car)
		"brake":
			launch(car, SKID, 25.0)
			_auto_brake = true
		"launch":
			car.place(SKID, 0.0)
			_auto_throttle = true
	car.telemetry.vectors = config != null and config.flag("vectors")


## The lab's ground and bumps under `parent`.
static func build_course(parent: Node) -> void:
	var gravel := _mat(Color(0.62, 0.55, 0.43))
	_slab(parent, Vector3(0.0, -0.5, 0.0), Vector3(600.0, 1.0, 600.0), gravel, "gravel")
	# the side slope: a slab tilted about Z, its top through SLOPE + 1.5 m (clear of the flat)
	var slope := StaticBody3D.new()
	slope.set_meta("surface", "gravel")
	var tilt := Basis(Vector3.BACK, deg_to_rad(SLOPE_DEG))
	slope.transform = Transform3D(tilt, slope_top() - tilt * Vector3(0.0, 0.5, 0.0))
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(16.0, 1.0, 16.0)
	cs.shape = b
	slope.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = b.size
	mi.mesh = bm
	mi.material_override = _mat(Color(0.56, 0.5, 0.4))
	slope.add_child(mi)
	parent.add_child(slope)
	var bump_mat := _mat(Color(0.5, 0.44, 0.34))
	for i in BUMP_N:
		var z := BUMPS_Z - i * BUMP_GAP
		_bump(parent, Vector3(0.0, 0.0, z), 4.0, bump_mat)                       # full width
		_bump(parent, Vector3(BUMP_LANE_X - 0.77, 0.0, z), 0.7, bump_mat)        # under the left wheels only


## Set the car rolling straight ahead at `v` m/s from `at` (the lab's keys, the tests).
static func launch(c: RigidBody3D, at: Vector3, v: float) -> void:
	c.place(at, 0.0)
	c.set_speed(v)


## The middle of the side slope's top surface.
static func slope_top() -> Vector3:
	return SLOPE + Vector3(0.0, 1.5, 0.0)


## Put the car on the side slope, square to it, still: across it (yaw 0) or,
## yaw PI / 2, nose uphill.
static func park_on_slope(c: RigidBody3D, yaw := 0.0) -> void:
	c.place(slope_top(), 0.0)
	var tilt := Basis(Vector3.BACK, deg_to_rad(SLOPE_DEG))
	c.global_transform = Transform3D(tilt * Basis(Vector3.UP, -yaw), slope_top() + tilt * Vector3(0.0, c.ride_height(), 0.0))
	c.reset_physics_interpolation()


## A tow along the car's heading toward `target` m/s, through the centre of mass
## (call every physics tick): there's no engine until phase 5. Not part of the car.
static func tow(c: RigidBody3D, target: float) -> void:
	var fwd := -c.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var v := c.linear_velocity.dot(fwd)
	c.apply_central_force(fwd * c.mass * clampf((target - v) * 2.0, -4.0, 4.0))


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	match e.keycode:
		KEY_R:
			car.place(PAD, 0.0)
		KEY_J:
			car.place(PAD, 0.0)
			car.global_position.y += 1.0
		KEY_B:
			launch(car, Vector3(0.0, 0.0, BUMPS_Z + 12.0), 12.0)
		KEY_N:
			launch(car, Vector3(BUMP_LANE_X, 0.0, BUMPS_Z + 12.0), 12.0)
		KEY_C:
			_tow = not _tow
		KEY_E:
			car.drivetrain.shift_up()
		KEY_Q:
			car.drivetrain.shift_down()
		KEY_P:
			_tow = false
			park_on_slope(car)
		KEY_O:
			_tow = false
			park_on_slope(car, PI / 2.0)


func _physics_process(_dt: float) -> void:
	var keys := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		keys -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		keys += 1.0
	if keys != 0.0:
		_hold_steer = false
	if not _hold_steer:
		car.inp.steer = keys
	car.inp.throttle = 1.0 if _auto_throttle or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W) else 0.0
	car.inp.brake = 1.0 if _auto_brake or Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S) else 0.0
	if _tow:
		tow(car, TOW_SPEED)


func _process(dt: float) -> void:
	var config := get_node_or_null("/root/Config")
	if config and config.flag("screenshot"):
		_shot_t += dt
		if _shot_t > float(config.arg("shot_wait", 1.5)):
			get_viewport().get_texture().get_image().save_png(config.arg("screenshot"))
			get_tree().quit(0)
	_orbit += dt * 0.1
	var c := car.global_position
	var want := c + Vector3(sin(_orbit) * 7.0, 2.6, cos(_orbit) * 7.0)
	cam.global_position = cam.global_position.lerp(want, clampf(dt * 3.0, 0.0, 1.0))
	cam.look_at(c + Vector3.UP * 0.3, Vector3.UP)


func _light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(30.0), 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment = e
	add_child(env)


static func _slab(parent: Node, at: Vector3, size: Vector3, m: Material, surface: String) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.set_meta("surface", surface)
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	body.add_child(mi)
	parent.add_child(body)


## A bump across the course: the top of a cylinder lying across it, `width` m wide.
static func _bump(parent: Node, at: Vector3, width: float, m: Material) -> void:
	var body := StaticBody3D.new()
	body.position = at + Vector3(0.0, BUMP_H - BUMP_R, 0.0)
	body.rotation.z = PI / 2.0                       # the cylinder's axis across the course (x)
	body.set_meta("surface", "gravel")
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = BUMP_R
	cyl.height = width
	cs.shape = cyl
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = BUMP_R
	cm.bottom_radius = BUMP_R
	cm.height = width
	cm.radial_segments = 48
	mi.mesh = cm
	mi.material_override = m
	body.add_child(mi)
	parent.add_child(body)


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	return m
