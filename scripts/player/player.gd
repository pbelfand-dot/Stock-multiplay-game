extends CharacterBody3D
## First-person player. The owning peer simulates movement and broadcasts
## its transform; every other peer shows an interpolated puppet.

const WALK := 4.5
const SPRINT := 7.5
const JUMP := 4.6
const GRAVITY := 12.0
const REACH := 2.6
const SEND_RATE := 1.0 / 20.0

var peer_id := 1
var display_name := "Trader"
var suit := Color(0.35, 0.36, 0.4)
var is_local := false
var world   # set by World

var pitch := 0.0
var raining := false
var _send_acc := 0.0
var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _has_target := false

var cam: Camera3D
var ray: RayCast3D
var head: Node3D
var body_mesh: Node3D
var name_tag: Label3D
var smoke: CPUParticles3D
var bills: CPUParticles3D
var held_cigar: Node3D
var held_gun: Node3D
var powder_fx := 0.0


func setup(id: int, pname: String, color: Color, local: bool, w) -> void:
	peer_id = id
	display_name = pname
	suit = color
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
		ray.collision_mask = 1
		ray.add_exception(self)
		cam.add_child(ray)
		body_mesh.visible = false
		name_tag.visible = false
	_build_fx()
	_target_pos = global_position


func _build_body() -> void:
	body_mesh = Node3D.new()
	add_child(body_mesh)
	var m := func(c: Color) -> StandardMaterial3D:
		var s := StandardMaterial3D.new()
		s.albedo_color = c
		s.roughness = 0.9
		return s
	var torso := MeshInstance3D.new()
	var tb := CapsuleMesh.new()
	tb.radius = 0.3
	tb.height = 1.1
	torso.mesh = tb
	torso.position.y = 1.05
	torso.material_override = m.call(suit)
	body_mesh.add_child(torso)
	for side in [-0.13, 0.13]:
		var leg := MeshInstance3D.new()
		var lm := CapsuleMesh.new()
		lm.radius = 0.11
		lm.height = 0.75
		leg.mesh = lm
		leg.position = Vector3(side, 0.38, 0)
		leg.material_override = m.call(suit.darkened(0.2))
		body_mesh.add_child(leg)
	var shirt := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.14, 0.4, 0.05)
	shirt.mesh = sb
	shirt.position = Vector3(0, 1.3, -0.28)
	shirt.material_override = m.call(Color(0.95, 0.95, 0.95))
	body_mesh.add_child(shirt)
	var tie := MeshInstance3D.new()
	var tbm := BoxMesh.new()
	tbm.size = Vector3(0.05, 0.32, 0.06)
	tie.mesh = tbm
	tie.position = Vector3(0, 1.28, -0.29)
	tie.material_override = m.call(Color(0.1, 0.1, 0.12))
	body_mesh.add_child(tie)
	var h := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.24
	hs.height = 0.5
	h.mesh = hs
	h.position.y = 1.78
	h.material_override = m.call(Color(0.96, 0.8, 0.66))
	body_mesh.add_child(h)
	var hair := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.46, 0.14, 0.46)
	hair.mesh = hb
	hair.position = Vector3(0, 1.97, 0.02)
	hair.material_override = m.call(Color(0.15, 0.1, 0.07))
	body_mesh.add_child(hair)
	var shades := MeshInstance3D.new()
	var shb := BoxMesh.new()
	shb.size = Vector3(0.4, 0.09, 0.05)
	shades.mesh = shb
	shades.position = Vector3(0, 1.82, -0.22)
	shades.material_override = m.call(Color(0.02, 0.02, 0.02))
	body_mesh.add_child(shades)
	var watch := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(0.1, 0.06, 0.1)
	watch.mesh = wb
	watch.position = Vector3(0.36, 0.78, 0)
	watch.material_override = m.call(Color(1, 0.8, 0.2))
	body_mesh.add_child(watch)
	name_tag = Label3D.new()
	name_tag.text = display_name
	name_tag.position.y = 2.3
	name_tag.font_size = 48
	name_tag.pixel_size = 0.005
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.outline_size = 10
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

	# held props (shown in view for local, in hand for others)
	var parent: Node3D = cam if is_local else self
	held_cigar = Node3D.new()
	parent.add_child(held_cigar)
	var c := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.035
	cm.height = 0.35
	c.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.5, 0.33, 0.15)
	c.material_override = cmat
	c.rotation.x = PI / 2
	held_cigar.add_child(c)
	var tipm := MeshInstance3D.new()
	var ts := SphereMesh.new()
	ts.radius = 0.035
	ts.height = 0.07
	tipm.mesh = ts
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(1, 0.4, 0.05)
	tmat.emission_enabled = true
	tmat.emission = Color(1, 0.35, 0.05)
	tmat.emission_energy_multiplier = 3
	tipm.material_override = tmat
	tipm.position = Vector3(0, 0, -0.18)
	held_cigar.add_child(tipm)
	held_cigar.position = Vector3(0.32, -0.3, -0.62) if is_local else Vector3(0.15, 1.6, -0.3)
	if is_local:
		held_cigar.scale = Vector3.ONE * 0.6
		held_cigar.rotation = Vector3(0.15, 0.35, 0)
		# keep our own smoke small and off to the side so it doesn't blind us
		smoke.amount = 14
		smoke.scale_amount_min = 0.3
		smoke.scale_amount_max = 0.7
		smoke.position = Vector3(0.45, 1.45, -0.6)
	held_cigar.visible = false

	held_gun = Node3D.new()
	parent.add_child(held_gun)
	var g := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.12, 0.14, 0.32)
	g.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.85, 0.08, 0.08)
	g.material_override = gmat
	held_gun.add_child(g)
	var grip := MeshInstance3D.new()
	var grm := BoxMesh.new()
	grm.size = Vector3(0.08, 0.18, 0.1)
	grip.mesh = grm
	grip.material_override = gmat
	grip.position = Vector3(0, -0.14, 0.08)
	held_gun.add_child(grip)
	var flex := Label3D.new()
	flex.text = "FLEX"
	flex.font_size = 24
	flex.pixel_size = 0.004
	flex.position = Vector3(0.065, 0.0, 0.0)
	flex.rotation.y = PI / 2
	held_gun.add_child(flex)
	held_gun.position = Vector3(0.28, -0.25, -0.5) if is_local else Vector3(0.35, 1.3, -0.35)
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
			world._p_tf.rpc(global_position, rotation.y, pitch, raining)
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
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif not blocked and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP
	move_and_slide()
	if global_position.y < -10.0:
		global_position = world.spawn_point(0)
	# money gun
	raining = (not blocked and m != null and m.effect_left(peer_id, "moneygun") > 0.0
		and Input.is_action_pressed("fire"))
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
	held_cigar.visible = cigar_on
	held_gun.visible = gun_on
	if smoke.emitting != cigar_on:
		smoke.emitting = cigar_on
	if bills.emitting != raining:
		bills.emitting = raining


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
func net_tf(pos: Vector3, yaw: float, p: float, rain: bool) -> void:
	_target_pos = pos
	_target_yaw = yaw
	pitch = p
	raining = rain
	if not _has_target:
		global_position = pos
		_has_target = true
