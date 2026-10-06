extends Node3D
## One corner of the car (a *_WheelPoint node): this node is the suspension
## mount, at the top of the travel; its ShapeCast3D sweeps a tyre-sized sphere
## straight down the travel (the strut's axis), every physics tick:
##   * where the sphere first touches is where the tyre is: the compression is
##     how far up the travel that is, the contact point and the ground's normal
##     come with it. A sphere, not a ray: a ray drops into every crack between
##     the road's panels and snags on edges; a sphere rolls over them like a tyre
##   * the spring + damper + bump stop (suspension.gd), and the anti-roll bar's
##     push (the car works it out from both corners of the axle), push the body
##     up at the contact point, along the ground's normal, by the strut force's
##     share that's square to the ground. That's the tyre's load. Pushing at the
##     contact, not the body's middle, is what makes braking dip the nose and
##     cornering roll the body
##   * the tyre (tire_model.gd): the contact patch's own velocity (the body's,
##     plus its spin times the lever arm to the patch), split along and across
##     the wheel's heading in the ground's plane. Across: it winds up the side
##     slip and the curve turns that into a side force. Along: the wheel has its
##     own spin, driven by the drive torque, slowed by the brakes and rolling
##     resistance, and the difference between its surface speed and the ground's
##     is the slip ratio, which gives the force along the wheel (its reaction
##     slows or speeds the spin). Both share one patch of rubber (the combined-
##     slip ellipse: braking hard leaves less for turning), and a heavily loaded
##     tyre grips less per newton (load sensitivity). Both pushed at the patch
##   * the tyre's states are stiff, so the car steps them several times a tick
##     (with the body's velocity held), implicitly, with the drivetrain and the
##     brakes solved in between (drivetrain.gd); the body gets the average force
##   * what it touches says what surface it is (its meta "surface": surfaces.gd),
##     and the tyre's figures are taken on that surface (TireModel.on_surface):
##     each wheel on its own, so two wheels on grass and two on gravel pull
##   * the wheel's mass isn't carried by the suspension here: in the air it hangs
##     at full droop
## The node's own Y rotation is the steering (the car sets it). The WheelMesh
## child is only the look: put where the simulation says.

const Suspension = preload("res://scripts/vehicle/physics/suspension.gd")
const TireModel = preload("res://scripts/vehicle/physics/tire_model.gd")
const Surfaces = preload("res://scripts/vehicle/physics/surfaces.gd")

@export var front := true

var car: RigidBody3D
var cfg: Resource                  # SuspensionConfig
var tire: Resource                 # TireConfig (on its reference surface, gravel)
var surface: Resource              # SurfaceConfig: what it's on (or was, last on the ground)
var surface_tire: Resource         # the tyre on that surface (TireModel.on_surface)
var surface_mu := 1.0              # grip x this on top of the surface's (the game's grip across the road; a test's ice patch)
var surface_override: Resource     # a SurfaceConfig to be on whatever it touches (a puddle: mud), or null
var radius := 0.32
var width := 0.2
var inertia := 1.1                 # kg m², the wheel's spin

# set by the car each tick
var drive_torque := 0.0            # N m of extra drive (the lab's and tests' test torque; the engine comes through the drivetrain)
var brake_torque := 0.0            # N m the brake (and handbrake) can apply (friction)
var anti_roll := 0.0               # N the anti-roll bar pushes this corner up with (- = pulls it down)

# for the drivetrain, each substep
var i_eff := 1.1                   # kg m²: how heavy the wheel feels (its inertia + the tyre's grip resisting)
var resist_torque := 0.0           # N m of friction holding it (brake + rolling resistance)
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
var omega := 0.0                   # rad/s, the wheel's spin (+ = rolling forward)
var slip_long := 0.0               # the slip ratio state (+ = spinning up, -1 = locked going forward)
var long_force := 0.0              # N along the wheel, + = pushing the car forward
var spin := 0.0                    # rad (the look)

var _mu_x := 1.0
var _mu_y := 1.0
var _fx := 0.0
var _fy := 0.0
var _n := 0
var _prev_compression := 0.0
var _was_grounded := false
var _drop := 0.0                   # the look in the air: how far down the travel the wheel hangs
var _surface_of: Object            # the collider `surface` is for


## Hook the corner up (the car calls it): the suspension it uses and the tyre.
func setup(the_car: RigidBody3D, suspension: Resource, tyre: Resource, tyre_radius: float, tyre_width: float,
		wheel_inertia: float) -> void:
	car = the_car
	cfg = suspension
	tire = tyre
	radius = tyre_radius
	width = tyre_width
	inertia = wheel_inertia
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
	_on_surface(null)


## Once a tick, first: sweep, and work out the compression and how fast it's
## changing (the car then works out the anti-roll bars from both corners and
## calls settle()).
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
		# fall back to the cast's. Already in the ground at the top of the travel (bottomed
		# out on a big landing), the sweep doesn't see what it starts inside and says
		# "free": the plane says fully squashed, and that's what it is.
		var rough: float = cfg.travel * cast.get_closest_collision_safe_fraction()
		var down := rough
		var across := axis.dot(normal)
		if across < -0.2:
			var exact := (radius - (global_position - contact).dot(normal)) / across
			if absf(exact - rough) < 0.02 or exact <= 0.0:
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


## Once a tick, second: the load (the spring, damper, bump stop and anti-roll
## bar) and the contact patch's velocity (the car then runs the substeps:
## tyre_predict, the drivetrain, tyre_finalize; then apply_forces).
func settle() -> void:
	var axis := -global_transform.basis.y
	if not grounded:
		strut_force = 0.0
		load = 0.0
		slip_lat = 0.0                               # off the ground the carcass springs back
		slip_long = 0.0
		resist_torque = brake_torque
	else:
		if surface_override:
			if surface != surface_override:
				surface = surface_override
				surface_tire = TireModel.on_surface(tire, surface)
				_surface_of = null                       # (looked up again once it's off)
		elif collider != _surface_of:
			_on_surface(collider)
		strut_force = Suspension.force(cfg, compression, compression_velocity, anti_roll)
		var square := maxf(-axis.dot(normal), 0.0)  # the strut's push that's square to the ground
		load = strut_force * square
		# the tyre: the patch's velocity along / across the wheel, in the ground's plane
		var fwd := -global_transform.basis.z
		heading = (fwd - normal * fwd.dot(normal)).normalized()
		var vc := _point_velocity(contact)
		v_long = vc.dot(heading)
		v_lat = vc.dot(heading.cross(normal))
		var t := surface_tire
		var lf := TireModel.load_mu_factor(t, load)      # a heavily loaded tyre grips less per newton
		_mu_y = t.lateral_mu * surface_mu * lf
		_mu_x = t.longitudinal_mu * surface_mu * lf
		resist_torque = brake_torque + t.rolling_resistance * load * radius
	_fx = 0.0
	_fy = 0.0
	_n = 0


## A substep, first half: the side slip, and the wheel's spin from its tyre (and
## any test drive torque) alone, with its effective inertia (i_eff) for the
## drivetrain and brakes, which come next (drivetrain.gd).
func tyre_predict(h: float) -> void:
	if not grounded:
		omega += h * drive_torque / inertia
		i_eff = inertia
		return
	slip_lat = TireModel.lateral_slip(surface_tire, slip_lat, v_long, v_lat, h)
	var p: Array = TireModel.spin_predict(surface_tire, omega, slip_long, slip_lat, v_long, load, _mu_x, _mu_y, inertia, radius,
		drive_torque, h)
	omega = p[0]
	i_eff = p[1]


## A substep, second half (the spin is final): the slip ratio follows, and the forces.
func tyre_finalize(h: float) -> void:
	if not grounded:
		return
	slip_long = TireModel.slip_after(surface_tire, slip_long, omega, v_long, radius, h)
	_fx += TireModel.long_force(surface_tire, slip_long, slip_lat, omega, v_long, load, _mu_x, _mu_y, radius)
	_fy += TireModel.lateral_force(surface_tire, slip_long, slip_lat, load, _mu_x, _mu_y, v_long, v_lat)
	_n += 1


## After the substeps: push the body with the averaged forces at the patch.
func apply_forces(dt: float) -> void:
	spin += omega * dt
	if not grounded or _n == 0:
		long_force = 0.0
		lateral_force = 0.0
		return
	var fx := _fx / _n
	var fy := _fy / _n
	# (the combined slip keeps them inside the ellipse; this only catches the damping's extra)
	var limit := maxf(_mu_x, _mu_y) * load
	var total := sqrt(fx * fx + fy * fy)
	if total > limit:
		fx *= limit / total
		fy *= limit / total
	long_force = fx
	lateral_force = fy
	car.apply_force(normal * load + heading * fx + heading.cross(normal) * fy, contact - car.global_position)


## The slip angle the tyre is at (deg, + = its patch sliding toward its right).
func slip_angle_deg() -> float:
	return -rad_to_deg(atan(slip_lat))


## The wheel's own speed at its rim (m/s): what a wheel-speed sensor would read.
func wheel_speed() -> float:
	return omega * radius


## The car was put somewhere new (place()): forget where the suspension was, or its
## next tick reads the jump from the old spot to the new one as the suspension
## moving that far in 1/120 s and the damper kicks the car into the air.
func reset() -> void:
	grounded = false
	_was_grounded = false
	compression = 0.0
	_prev_compression = 0.0
	compression_velocity = 0.0
	slip_lat = 0.0
	slip_long = 0.0
	omega = 0.0


## On the co-driver's machine (the car isn't simulated there): the streamed
## compression, and the wheel rolling with the car (`dt`: the tick).
func show_remote(c: float, car_speed: float, dt: float) -> void:
	compression = c
	grounded = c > 0.005
	spin += car_speed / radius * dt


## Place the wheel's look (call every frame): on the ground, or hanging in the air.
func update_visual(dt: float) -> void:
	if mesh == null:
		return
	var target: float = cfg.travel - compression if grounded else cfg.travel
	_drop = target if grounded else move_toward(_drop, target, dt * 2.0)
	mesh.position = Vector3(0.0, -_drop, 0.0)
	mesh.rotation = Vector3(-spin, 0.0, 0.0)          # (steering: this node's own rotation)


## Now on what `collider` is (null: the default, gravel).
func _on_surface(c: Object) -> void:
	_surface_of = c
	surface = Surfaces.of(c)
	surface_tire = TireModel.on_surface(tire, surface)


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
