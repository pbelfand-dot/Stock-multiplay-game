extends Camera3D
## The camera while you drive. CHASE: behind and above, swings round after the
## car (so you see it slide), pulls back and widens with speed, shakes on a
## hit. COCKPIT: the driver's eyes, with the dash and the wheel in front of you.
## C switches.
## The car moves on the physics tick; the camera moves every frame, from where
## the car is *drawn* (its physics-interpolated transform), so it's smooth at
## any frame rate. The camera itself isn't interpolated (it'd lag a tick).

const Character = preload("res://scripts/art/character.gd")

var car
var cockpit := false
var _yaw := 0.0
var _shake := 0.0
var _pos := Vector3.ZERO


func follow(c) -> void:
	car = c
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var xf: Transform3D = c.get_global_transform_interpolated()
	_yaw = xf.basis.get_euler().y
	_pos = _chase_spot(xf)
	global_position = _pos
	c.crashed.connect(func(i): _shake = maxf(_shake, clampf(i / 25.0, 0.1, 0.6)))
	near = 0.05
	cull_mask &= ~Character.FP_LAYER     # our own head isn't drawn (the cockpit view sits in it)
	current = true


func toggle() -> void:
	cockpit = not cockpit


func _chase_spot(xf: Transform3D) -> Vector3:
	var sp: float = absf(car.speed)
	var back := 6.4 + sp * 0.04
	var basis := Basis(Vector3.UP, _yaw)
	return xf.origin + basis * Vector3(0, 2.5 + sp * 0.008, back)


func _process(dt: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	_shake = maxf(_shake - dt * 1.5, 0.0)
	var jolt := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.12
	var sp: float = absf(car.speed)
	var xf: Transform3D = car.get_global_transform_interpolated()
	if cockpit:
		global_transform = xf * Transform3D(Basis(), car.ref.eye + (Vector3(0, 0.02, 0.0) if car.ref.get("kit", false) else Vector3(0, 0.02, -0.14)))
		rotate_object_local(Vector3.RIGHT, -0.06)
		fov = lerpf(fov, 72.0 + sp * 0.12, 1.0 - exp(-dt * 3.0))
		position += jolt * 0.4
		return
	# swing round behind the car, a bit late (you see it rotate in a slide);
	# frame-rate independent smoothing (exp), so 60 or 144 fps look the same
	_yaw = lerp_angle(_yaw, xf.basis.get_euler().y, 1.0 - exp(-dt * 4.0))
	_pos = _pos.lerp(_chase_spot(xf), 1.0 - exp(-dt * 10.0))
	global_position = _pos + jolt
	var ahead: Vector3 = xf.origin + Basis(Vector3.UP, _yaw) * Vector3(0, 1.1, -7.0)
	look_at(ahead, Vector3.UP)
	fov = lerpf(fov, 70.0 + clampf(sp * 0.3, 0.0, 22.0), 1.0 - exp(-dt * 3.0))
