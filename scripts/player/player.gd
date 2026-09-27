extends CharacterBody3D
## First-person player. The owning peer simulates movement and broadcasts
## its transform; every other peer shows an interpolated puppet.

const WALK := 4.5
const SPRINT := 7.5
const JUMP := 4.6
const GRAVITY := 12.0
const REACH := 2.6
const SEND_RATE := 1.0 / 20.0
const Character = preload("res://scripts/art/character.gd")
const Props = preload("res://scripts/art/props.gd")

var peer_id := 1
var display_name := "Trader"
var look := {}
var is_local := false
var world   # set by World

var pitch := 0.0
var raining := false
var diving := 0.0
var _dive_cd := 0.0
var _brrt_acc := 0.0
var _send_acc := 0.0
var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _has_target := false

var cam: Camera3D
var ray: RayCast3D
var head: Node3D
var body_mesh: Node3D     # the Character model (hidden for our own view)
var model
var fp_arm: Node3D
var busy := false         # at a terminal / slot machine (synced)
var _last_pos := Vector3.ZERO
var _speed := 0.0
var name_tag: Label3D
var smoke: CPUParticles3D
var bills: CPUParticles3D
var held_cigar: Node3D
var held_gun: Node3D
var powder_fx := 0.0


func setup(id: int, pname: String, player_look: Dictionary, local: bool, w) -> void:
	peer_id = id
	display_name = pname
	look = player_look
	is_local = local
	world = w
	name = str(id)
	set_multiplayer_authority(id)


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	_build_body()
	head = Node3D.new()
	head.position.y = 1.62
	add_child(head)
	if is_local:
		cam = Camera3D.new()
		cam.fov = 80
		cam.near = 0.05
		head.add_child(cam)
		cam.current = true
		ray = RayCast3D.new()
		ray.target_position = Vector3(0, 0, -REACH)
		ray.collision_mask = 1 | 8
		ray.add_exception(self)
		cam.add_child(ray)
		body_mesh.visible = false
		name_tag.visible = false
	_build_fx()
	_target_pos = global_position


func _build_body() -> void:
	model = Character.new()
	model.name = "Model"
	model.build(look)
	add_child(model)
	body_mesh = model
	name_tag = Label3D.new()
	name_tag.text = display_name
	name_tag.position.y = 2.2
	name_tag.font_size = 48
	name_tag.pixel_size = 0.005
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.outline_size = 10
	var f = load("res://assets/fonts/Oswald-Bold.woff2")
	if f:
		name_tag.font = f
	add_child(name_tag)


func _build_fx() -> void:
	smoke = CPUParticles3D.new()
	smoke.emitting = false
	smoke.amount = 40
	smoke.lifetime = 2.5
	smoke.direction = Vector3(0, 1, 0)
	smoke.spread = 40
	smoke.initial_velocity_min = 0.2
	smoke.initial_velocity_max = 0.6
	smoke.gravity = Vector3(0, 0.3, 0)
	smoke.scale_amount_min = 0.5
	smoke.scale_amount_max = 1.4
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.85, 0.85, 0.85, 0.45)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = smat
	smoke.mesh = sm
	smoke.position = Vector3(0.15, 1.6, -0.35)
	add_child(smoke)

	bills = CPUParticles3D.new()
	bills.emitting = false
	bills.amount = 60
	bills.lifetime = 1.6
	bills.direction = Vector3(0, 0.4, -1)
	bills.spread = 25
	bills.initial_velocity_min = 4
	bills.initial_velocity_max = 7
	bills.gravity = Vector3(0, -3, 0)
	bills.angular_velocity_min = -360
	bills.angular_velocity_max = 360
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.01, 0.1)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.35, 0.7, 0.35)
	bm.material = bmat
	bills.mesh = bm
	bills.position = Vector3(0.3, 1.35, -0.5)
	add_child(bills)

	# held props: first-person arm for us, the model's right hand for others
	if is_local:
		fp_arm = Props.fp_arm(look)
		fp_arm.position = Vector3(0.3, -0.28, -0.42)
		fp_arm.rotation = Vector3(0.08, 0.12, 0)
		cam.add_child(fp_arm)
		fp_arm.visible = false
		var grip: Node3D = fp_arm.get_node("Grip")
		held_cigar = Props.cigar()
		held_cigar.rotation = Vector3(0, 0.5, 0)
		grip.add_child(held_cigar)
		held_gun = Props.flex_gun()
		held_gun.position = Vector3(0, -0.02, 0.02)
		grip.add_child(held_gun)
		# keep our own smoke small and off to the side so it doesn't blind us
		smoke.amount = 14
		smoke.scale_amount_min = 0.3
		smoke.scale_amount_max = 0.7
		smoke.position = Vector3(0.45, 1.45, -0.6)
	else:
		held_cigar = Props.cigar()
		held_cigar.rotation = Vector3(-PI / 2, 0, 0)
		model.prop_right.add_child(held_cigar)
		held_gun = Props.flex_gun()
		held_gun.rotation = Vector3(-PI / 2, 0, 0)
		model.prop_right.add_child(held_gun)
		smoke.position = Vector3(0.1, 1.62, -0.3)
		bills.position = Vector3(0.3, 1.35, -0.6)
	held_cigar.visible = false
	held_gun.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_local or world == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * Config.mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * Config.mouse_sensitivity, -1.45, 1.45)
		head.rotation.x = pitch


func _physics_process(delta: float) -> void:
	if is_local:
		_local_move(delta)
		_send_acc += delta
		if _send_acc >= SEND_RATE:
			_send_acc = 0.0
			var flags := (1 if raining else 0) | (2 if diving > 0.0 else 0) | (4 if world.ui_blocking() else 0)
			world._p_tf.rpc(global_position, rotation.y, pitch, flags)
	else:
		if _has_target:
			global_position = global_position.lerp(_target_pos, clampf(delta * 12.0, 0, 1))
			if global_position.distance_to(_target_pos) > 6.0:
				global_position = _target_pos
			rotation.y = lerp_angle(rotation.y, _target_yaw, clampf(delta * 12.0, 0, 1))
	_update_fx()


func _local_move(delta: float) -> void:
	var m = world.match_node
	var blocked: bool = world.ui_blocking()
	var input := Vector2.ZERO
	if not blocked:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var speed := SPRINT if Input.is_action_pressed("sprint") else WALK
	if m and m.effect_left(peer_id, "powder") > 0.0:
		speed *= 1.6
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	_dive_cd = maxf(_dive_cd - delta, 0.0)
	if diving > 0.0:
		# committed to the dive: keep sliding, slowly lose speed
		diving -= delta
		velocity.x *= 0.985
		velocity.z *= 0.985
	else:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		if not blocked and _dive_cd <= 0.0 and is_on_floor() and Input.is_action_just_pressed("dive"):
			var fwd := -transform.basis.z
			velocity.x = fwd.x * speed * 1.7
			velocity.z = fwd.z * speed * 1.7
			velocity.y = 2.8
			diving = 0.75
			_dive_cd = 1.8
			Sfx.play("whoosh")
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif not blocked and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP
	move_and_slide()
	if global_position.y < -10.0:
		global_position = world.spawn_point(0)
	# basketball throw takes priority over the money gun
	var ball = world.ball
	var holding: bool = ball != null and ball.holder == peer_id
	if holding and not blocked and Input.is_action_just_pressed("fire"):
		ball.request_throw(-cam.global_basis.z)
	# money gun
	raining = (not holding and not blocked and m != null and m.effect_left(peer_id, "moneygun") > 0.0
		and Input.is_action_pressed("fire"))
	if raining:
		_brrt_acc -= delta
		if _brrt_acc <= 0.0:
			_brrt_acc = 0.22
			Sfx.play("brrt", -6.0, randf_range(0.9, 1.1))
	# dive camera: drop low and roll
	head.position.y = lerpf(head.position.y, 0.55 if diving > 0.0 else 1.62, delta * 10.0)
	head.rotation.z = lerpf(head.rotation.z, 0.25 if diving > 0.0 else 0.0, delta * 8.0)
	# head bob / powder shake
	if cam:
		if m and m.effect_left(peer_id, "powder") > 0.0:
			powder_fx += delta
			cam.h_offset = sin(powder_fx * 31.0) * 0.012
			cam.fov = lerpf(cam.fov, 92.0, delta * 3.0)
		else:
			cam.h_offset = 0.0
			cam.fov = lerpf(cam.fov, 80.0, delta * 3.0)


func _update_fx() -> void:
	var m = world.match_node if world else null
	var cigar_on: bool = m != null and m.effect_left(peer_id, "cigar") > 0.0
	var gun_on: bool = m != null and m.effect_left(peer_id, "moneygun") > 0.0
	var holding_ball: bool = world != null and world.ball != null and world.ball.holder == peer_id
	held_cigar.visible = cigar_on and not gun_on
	model.bloodshot = bool(look.get("bloodshot", false)) or cigar_on or (m != null and m.effect_left(peer_id, "powder") > 0.0)
	held_gun.visible = gun_on
	if smoke.emitting != cigar_on:
		smoke.emitting = cigar_on
	if bills.emitting != raining:
		bills.emitting = raining
	if is_local:
		fp_arm.visible = cigar_on or gun_on or holding_ball
		return
	# animate the remote model from what we know about this player
	var dt := get_physics_process_delta_time()
	var flat := global_position - _last_pos
	flat.y = 0.0
	_speed = lerpf(_speed, flat.length() / maxf(dt, 0.001), 0.25)
	_last_pos = global_position
	model.move_speed = _speed
	model.look_pitch(pitch)
	var jailed: bool = m != null and m.is_jailed(peer_id)
	if diving > 0.0:
		model.pose = "dive"
	elif jailed:
		model.pose = "cuffed"
	elif gun_on:
		model.pose = "hold"
	elif holding_ball:
		model.pose = "hold"
	elif busy:
		model.pose = "type_stand"
	elif cigar_on:
		model.pose = "smoke"
	else:
		model.pose = "idle"


## What the crosshair is pointing at: {type, id, prompt} or {}
func look_target() -> Dictionary:
	if ray == null:
		return {}
	ray.force_raycast_update()
	if not ray.is_colliding():
		return {}
	var col := ray.get_collider()
	if col and col.has_meta("interact"):
		return {"type": col.get_meta("interact"), "id": col.get_meta("interact_id"), "prompt": col.get_meta("prompt")}
	return {}


func teleport(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	_target_pos = pos


## Called by World when this player's owner broadcasts its transform.
func net_tf(pos: Vector3, yaw: float, p: float, flags: int) -> void:
	_target_pos = pos
	_target_yaw = yaw
	pitch = p
	raining = flags & 1 != 0
	diving = 0.5 if flags & 2 != 0 else 0.0
	busy = flags & 4 != 0
	if not _has_target:
		global_position = pos
		_has_target = true
