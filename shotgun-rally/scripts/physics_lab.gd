extends Node3D
## The physics lab (scenes/physics_lab.tscn): somewhere to try physics v2 and
## watch its telemetry. Run it: godot --path . scenes/physics_lab.tscn
##   * a big flat gravel pad
##   * a strip of full-width bumps (8 cm, ~0.8 m long), to see the car pitch
##   * a lane of bumps under the left wheels only, to see it roll
## Keys: R back on the pad   J drop it from a metre up   B roll it over the
## bumps at 12 m/s   N over the left-side bumps   F3 numbers   F4 force arrows
## Phase 1 has no tyre grip (it can't drive yet): these set it going instead.
## The tests build the same course (build_course) without the scene.
## A picture: ... scenes/physics_lab.tscn -- --screenshot=out.png [--lab=drop|bumps|left
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

var car: RigidBody3D
var cam: Camera3D
var _orbit := 0.6
var _shot_t := 0.0


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
	hint.text = "R reset   J drop 1 m   B bumps   N left-side bumps   F3 numbers   F4 forces"
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
	car.telemetry.vectors = config != null and config.flag("vectors")


## The lab's ground and bumps under `parent`.
static func build_course(parent: Node) -> void:
	var gravel := _mat(Color(0.62, 0.55, 0.43))
	_slab(parent, Vector3(0.0, -0.5, -40.0), Vector3(200.0, 1.0, 200.0), gravel, "gravel")
	var bump_mat := _mat(Color(0.5, 0.44, 0.34))
	for i in BUMP_N:
		var z := BUMPS_Z - i * BUMP_GAP
		_bump(parent, Vector3(0.0, 0.0, z), 4.0, bump_mat)                       # full width
		_bump(parent, Vector3(BUMP_LANE_X - 0.77, 0.0, z), 0.7, bump_mat)        # under the left wheels only


## Set the car rolling straight ahead at `v` m/s from `at` (the lab's keys, the tests).
static func launch(c: RigidBody3D, at: Vector3, v: float) -> void:
	c.place(at, 0.0)
	c.linear_velocity = Vector3(0.0, 0.0, -v)


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
