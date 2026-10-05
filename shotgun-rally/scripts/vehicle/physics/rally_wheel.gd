extends Node3D
## One corner of the car (a *_WheelPoint node): this node is the suspension
## mount, at the top of the travel; its ShapeCast3D sweeps a tyre-sized sphere
## straight down the travel (the strut's axis), every physics tick:
##   * where the sphere first touches is where the tyre is: the compression is
##     how far up the travel that is, the contact point and the ground's normal
##     come with it. A sphere, not a ray: a ray drops into every crack between
##     the road's panels and snags on edges; a sphere rolls over them like a tyre
##   * the spring + damper + bump stop (suspension.gd) push the body up at the
##     contact point, along the ground's normal, by the strut force's share
##     that's square to the ground. That's the tyre's load, which the tyre
##     forces will use (phase 2 on). Pushing at the contact, not the body's
##     middle, is what makes braking dip the nose and cornering roll the body
##   * the wheel has no mass of its own here: in the air it hangs at full droop
## The WheelMesh child is only the look: put where the simulation says.

const Suspension = preload("res://scripts/vehicle/physics/suspension.gd")

@export var front := true

var car: RigidBody3D
var cfg: Resource                  # SuspensionConfig
var radius := 0.32
var width := 0.2
var cast: ShapeCast3D
var mesh: Node3D

# this tick (read by the car, the telemetry, the tests)
var grounded := false
var compression := 0.0             # m up from full droop
var compression_velocity := 0.0    # m/s, + = squashing
var strut_force := 0.0             # N along the strut
var load := 0.0                    # N square to the ground: what the tyre presses with
var contact := Vector3.ZERO        # world
var normal := Vector3.UP           # world
var collider: Object
var wheel_center := Vector3.ZERO   # world
var spin := 0.0                    # rad (the look)

var _prev_compression := 0.0
var _was_grounded := false
var _drop := 0.0                   # the look in the air: how far down the travel the wheel hangs


## Hook the corner up (the car calls it): the suspension it uses and the tyre.
func setup(the_car: RigidBody3D, suspension: Resource, tyre_radius: float, tyre_width: float) -> void:
	car = the_car
	cfg = suspension
	radius = tyre_radius
	width = tyre_width
	cast = get_node_or_null("ShapeCast3D")
	if cast == null:
		cast = ShapeCast3D.new()
		cast.name = "ShapeCast3D"
		add_child(cast)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	cast.shape = sphere
	cast.target_position = Vector3(0.0, -cfg.travel, 0.0)
	cast.collision_mask = 1                          # the ground and everything on it, not other cars
	cast.max_results = 1
	cast.margin = 0.0
	cast.enabled = false                             # swept on demand, in step(), so it's this tick's
	cast.clear_exceptions()
	cast.add_exception(car)
	mesh = get_node_or_null("WheelMesh")
	if mesh == null:
		mesh = Node3D.new()
		mesh.name = "WheelMesh"
		add_child(mesh)
	if mesh.get_child_count() == 0:                  # an empty WheelMesh: a plain tyre and rim
		mesh.add_child(_tyre_mesh())
	_drop = cfg.travel


## This tick: sweep, work out the compression, push the body (call from the
## car's _physics_process).
func step(dt: float) -> void:
	cast.force_shapecast_update()
	var axis := -global_transform.basis.y            # down the strut
	if cast.is_colliding():
		var fraction := cast.get_closest_collision_safe_fraction()
		compression = cfg.travel * (1.0 - fraction)
		contact = cast.get_collision_point(0)
		normal = cast.get_collision_normal(0)
		collider = cast.get_collider(0)
		wheel_center = global_position + axis * cfg.travel * fraction
		grounded = true
	else:
		compression = 0.0
		collider = null
		wheel_center = global_position + axis * cfg.travel
		contact = wheel_center + axis * radius
		normal = -axis
		grounded = false
	if grounded and _was_grounded:
		compression_velocity = (compression - _prev_compression) / dt
	elif grounded:
		# just landed: the mount's own speed toward the ground (there's no last tick to compare with)
		compression_velocity = maxf(_point_velocity(global_position).dot(axis), 0.0)
	else:
		compression_velocity = 0.0
	_prev_compression = compression
	_was_grounded = grounded
	if not grounded:
		strut_force = 0.0
		load = 0.0
		return
	strut_force = Suspension.force(cfg, compression, compression_velocity)
	var square := maxf(-axis.dot(normal), 0.0)      # the strut's push that's square to the ground
	load = strut_force * square
	car.apply_force(normal * load, contact - car.global_position)


## Place the wheel's look (call every frame): on the ground, or hanging in the air.
func update_visual(dt: float, steer_angle := 0.0) -> void:
	if mesh == null:
		return
	var target: float = cfg.travel - compression if grounded else cfg.travel
	_drop = target if grounded else move_toward(_drop, target, dt * 2.0)
	mesh.position = Vector3(0.0, -_drop, 0.0)
	mesh.rotation = Vector3(spin, steer_angle, 0.0)


## A point on the car's velocity (world), from its linear and angular velocity.
func _point_velocity(p: Vector3) -> Vector3:
	var com: Vector3 = car.global_transform * car.center_of_mass
	return car.linear_velocity + car.angular_velocity.cross(p - com)


func _tyre_mesh() -> Node3D:
	var root := Node3D.new()
	var tyre := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = width
	cm.radial_segments = 16
	cm.rings = 1
	tyre.mesh = cm
	tyre.rotation.z = PI / 2.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.1, 0.11)
	m.roughness = 0.95
	tyre.material_override = m
	root.add_child(tyre)
	var rim := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = radius * 0.6
	rm.bottom_radius = radius * 0.6
	rm.height = width + 0.01
	rm.radial_segments = 8
	rm.rings = 1
	rim.mesh = rm
	rim.rotation.z = PI / 2.0
	var mr := StandardMaterial3D.new()
	mr.albedo_color = Color(0.85, 0.85, 0.82)
	mr.roughness = 0.4
	rim.material_override = mr
	root.add_child(rim)
	return root
