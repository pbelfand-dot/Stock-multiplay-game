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
##     that's square to the ground. That's the tyre's load. Pushing at the
##     contact, not the body's middle, is what makes braking dip the nose and
##     cornering roll the body
##   * the tyre (tire_model.gd): the contact patch's own velocity (the body's,
##     plus its spin times the lever arm to the patch), split along and across
##     the wheel's heading in the ground's plane; the sideways part winds up the
##     slip state and the curve turns it into a side force, mu x load at most,
##     pushed at the patch too (phase 2; along the wheel comes in phase 3)
##   * the wheel has no mass of its own here: in the air it hangs at full droop
## The node's own Y rotation is the steering (the car sets it). The WheelMesh
## child is only the look: put where the simulation says.

const Suspension = preload("res://scripts/vehicle/physics/suspension.gd")
const TireModel = preload("res://scripts/vehicle/physics/tire_model.gd")

@export var front := true

var car: RigidBody3D
var cfg: Resource                  # SuspensionConfig
var tire: Resource                 # TireConfig
var surface_mu := 1.0              # the surface's grip relative to the tyre's reference (phase 6)
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
var heading := Vector3.FORWARD     # world: along the wheel, in the ground's plane
var v_long := 0.0                  # m/s: the contact patch's speed along the wheel ...
var v_lat := 0.0                   # ... and across it (+ = toward the wheel's right)
var slip_lat := 0.0                # the sideways slip state (tan of the slip angle; + = sliding left)
var lateral_force := 0.0           # N, + = pushing the car to the wheel's right
var spin := 0.0                    # rad (the look)

var _prev_compression := 0.0
var _was_grounded := false
var _drop := 0.0                   # the look in the air: how far down the travel the wheel hangs


## Hook the corner up (the car calls it): the suspension it uses and the tyre.
func setup(the_car: RigidBody3D, suspension: Resource, tyre: Resource, tyre_radius: float, tyre_width: float) -> void:
	car = the_car
	cfg = suspension
	tire = tyre
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
		contact = cast.get_collision_point(0)
		normal = cast.get_collision_normal(0)
		collider = cast.get_collider(0)
		# How far down the travel the sphere touches. The cast's own answer comes
		# in ~2 mm steps (each step would read as a jolt of suspension speed), so
		# solve it exactly: the centre on the strut's line, one radius off the
		# ground's plane at the contact. At an edge, where the plane guess is off,
		# fall back to the cast's.
		var rough: float = cfg.travel * cast.get_closest_collision_safe_fraction()
		var down := rough
		var across := axis.dot(normal)
		if across < -0.2:
			var exact := (radius - (global_position - contact).dot(normal)) / across
			if absf(exact - rough) < 0.02:
				down = exact
		down = clampf(down, 0.0, cfg.travel)
		compression = cfg.travel - down
		wheel_center = global_position + axis * down
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
		lateral_force = 0.0
		slip_lat = 0.0                               # off the ground the carcass springs back
		return
	strut_force = Suspension.force(cfg, compression, compression_velocity)
	var square := maxf(-axis.dot(normal), 0.0)      # the strut's push that's square to the ground
	load = strut_force * square
	# the tyre: the patch's velocity along / across the wheel, in the ground's plane
	var fwd := -global_transform.basis.z
	heading = (fwd - normal * fwd.dot(normal)).normalized()
	var right := heading.cross(normal)
	var vc := _point_velocity(contact)
	v_long = vc.dot(heading)
	v_lat = vc.dot(right)
	spin += v_long / radius * dt                     # rolling freely (until phase 3 gives it its own spin)
	slip_lat = TireModel.lateral_slip(tire, slip_lat, v_long, v_lat, dt)
	var mu: float = tire.lateral_mu * surface_mu
	lateral_force = TireModel.lateral_force(tire, slip_lat, load, mu, v_long, v_lat)
	car.apply_force(normal * load + right * lateral_force, contact - car.global_position)


## The slip angle the tyre is at (deg, + = its patch sliding toward its right).
func slip_angle_deg() -> float:
	return -rad_to_deg(atan(slip_lat))


## Place the wheel's look (call every frame): on the ground, or hanging in the air.
func update_visual(dt: float) -> void:
	if mesh == null:
		return
	var target: float = cfg.travel - compression if grounded else cfg.travel
	_drop = target if grounded else move_toward(_drop, target, dt * 2.0)
	mesh.position = Vector3(0.0, -_drop, 0.0)
	mesh.rotation = Vector3(-spin, 0.0, 0.0)          # (steering: this node's own rotation)


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
