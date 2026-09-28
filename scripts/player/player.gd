extends CharacterBody3D
## First-person player. The owning peer simulates movement and broadcasts
## its transform; every other peer shows an interpolated puppet.

const Rules = preload("res://scripts/sim/rules.gd")
const WALK := 4.5
const SPRINT := 7.5
const JUMP := 4.6
const GRAVITY := 12.0
const REACH := 2.6
const SEND_RATE := 1.0 / 20.0
const Character = preload("res://scripts/art/character.gd")
const Props = preload("res://scripts/art/props.gd")
const PropKit = preload("res://scripts/art/prop_kit.gd")

var peer_id := 1
var display_name := "Trader"
var look := {}
var _watch_kind := ""
var _sway_t := 0.0
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
var body_mesh: Node3D     # the Character model (our own too: first-person body, head hidden)
var model
var busy := false         # at a terminal / slot machine (synced)
var _last_pos := Vector3.ZERO
var _speed := 0.0
var name_tag: Label3D
var smoke: CPUParticles3D
var bills: CPUParticles3D
var held_cigar: Node3D
var held_gun: Node3D
var powder_fx := 0.0
# emotes (F finger, V fist pump, Z show watch, X point) and chairs
const EMOTES := ["", "finger", "fistpump", "watch", "point", "dance"]
const EMOTE_TIME := 2.4
const ROLL_SPEED := 2.2
var emote := 0              # index into EMOTES (synced)
var _emote_t := 0.0
var _dance_tilt := 0.0
var seat := -1              # desk chair id we're sitting in (synced), -1 = standing
var carried_chair: Node3D
var finger_prop: Node3D
var zippo: Node3D
var _zippo_t := 0.0
var _cigar_was := 0.0
var cash_stack: Node3D
var _cash_t := 0.0


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
		ray.collision_mask = 1 | 8 | 16
		ray.add_exception(self)
		cam.add_child(ray)
		cam.cull_mask &= ~Character.FP_LAYER     # our own head isn't drawn for us (still casts a shadow)
		model.set_first_person(true)
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

	# held props go in the model's hands (ours too: you see your own hands in first person)
	if is_local:   # keep our own smoke small and off to the side so it doesn't blind us
		smoke.amount = 14
		smoke.scale_amount_min = 0.3
		smoke.scale_amount_max = 0.7
		smoke.position = Vector3(0.45, 1.45, -0.6)
	else:
		smoke.position = Vector3(0.1, 1.62, -0.3)
		bills.position = Vector3(0.3, 1.35, -0.6)
	_attach_props()


## Cigar / money gun / finger / Zippo / cash stack live in the model's hands.
## Called again after the Tailor rebuilds the body.
func _attach_props() -> void:
	held_cigar = Props.cigar()
	held_cigar.rotation = Vector3(-PI / 2, 0, 0)
	model.prop_right.add_child(held_cigar)
	held_gun = Props.flex_gun()
	held_gun.rotation = Vector3(-PI / 2, 0, 0)
	model.prop_right.add_child(held_gun)
	finger_prop = Props.finger(look.get("skin", Color(0.88, 0.7, 0.58)))
	finger_prop.visible = false
	model.prop_right.add_child(finger_prop)
	held_cigar.visible = false
	held_gun.visible = false
	if is_local:
		zippo = Props.zippo()
		zippo.rotation = Vector3(-PI / 2, 0, 0)
		zippo.visible = false
		model.prop_left.add_child(zippo)
		cash_stack = null


## New clothes from the Tailor: rebuild the body (and first-person arm) and
## re-attach whatever we were holding.
func apply_look(l: Dictionary) -> void:
	if l == look:
		return
	look = l
	model.build(look)          # frees the old hands and everything in them
	_watch_kind = ""
	_attach_props()


func _unhandled_input(event: InputEvent) -> void:
	if not is_local or world == null:
		return
	if not world.ui_blocking():
		for i in range(1, EMOTES.size()):
			if event.is_action_pressed("emote_" + EMOTES[i]):
				if EMOTES[i] == "dance":
					if seat >= 0:
						continue
					if EMOTES[emote] == "dance":      # press again to stop
						emote = 0
						_emote_t = 0.0
						continue
					emote = i
					_emote_t = Character.clip_length("dance") * 3.0
					continue
				emote = i
				_emote_t = EMOTE_TIME
				if EMOTES[i] == "watch":
					Sfx.play("coin", -4.0, 1.3)
		if seat >= 0 and (event.is_action_pressed("jump") or event.is_action_pressed("dive")):
			stand_up()
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
			var flags := (1 if raining else 0) | (2 if diving > 0.0 else 0) | (4 if world.ui_blocking() else 0) \
					| (emote << 3) | ((seat + 1) << 6)
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
	if seat >= 0:
		speed = ROLL_SPEED
	if m and m.effect_left(peer_id, "powder") > 0.0:
		speed *= 1.6
	var bp: float = m.pressure_of(peer_id) if m else 0.0
	if bp > Rules.PRESSURE_WOBBLY:   # high blood pressure: heavy legs
		speed *= lerpf(1.0, 0.6, (bp - Rules.PRESSURE_WOBBLY) / (Rules.PRESSURE_MAX - Rules.PRESSURE_WOBBLY))
	if EMOTES[emote] == "dance" and (input != Vector2.ZERO or Input.is_action_just_pressed("jump")):
		emote = 0                  # moving ends the dance
		_emote_t = 0.0
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
		if seat < 0 and not blocked and _dive_cd <= 0.0 and is_on_floor() and Input.is_action_just_pressed("dive"):
			var fwd := -transform.basis.z
			velocity.x = fwd.x * speed * 1.7
			velocity.z = fwd.z * speed * 1.7
			velocity.y = 2.8
			diving = 0.75
			_dive_cd = 1.8
			Sfx.play("whoosh")
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif seat < 0 and not blocked and Input.is_action_just_pressed("jump"):
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
	# the camera rides the body's eyes (sitting, diving, dancing all move it),
	# set back a little so looking down shows your chest, not the floor in front of it
	var eye: Vector3 = to_local(model.j["eyes"].global_position) if model.j.has("eyes") else Vector3(0, 1.62, 0)
	var turn: float = model.body_yaw() if EMOTES[emote] == "dance" else 0.0   # the view turns with the dance
	eye += Basis(Vector3.UP, turn) * Vector3(0, 0, 0.03)
	head.position = head.position.lerp(eye, clampf(delta * 18.0, 0.0, 1.0))
	head.rotation.y = lerp_angle(head.rotation.y, turn, clampf(delta * 10.0, 0.0, 1.0))
	# dancing: tip the view down a bit so your own hands are in the shot
	_dance_tilt = lerpf(_dance_tilt, -0.5 if EMOTES[emote] == "dance" else 0.0, clampf(delta * 5.0, 0.0, 1.0))
	head.rotation.x = clampf(pitch + _dance_tilt, -1.45, 1.45)
	if seat >= 0 and carried_chair:   # the chair swivels a little behind your yaw
		carried_chair.rotation.y = lerp_angle(carried_chair.rotation.y, PI, delta * 4.0)
	_update_fp_emote(delta)
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
		# blood pressure: the room sways and throbs
		var bpk := clampf((m.pressure_of(peer_id) - Rules.PRESSURE_WOBBLY) / (Rules.PRESSURE_MAX - Rules.PRESSURE_WOBBLY), 0.0, 1.0) if m else 0.0
		_sway_t += delta
		cam.rotation.z = sin(_sway_t * 1.3) * 0.05 * bpk
		cam.rotation.y = sin(_sway_t * 0.9 + 1.0) * 0.035 * bpk
		cam.v_offset = sin(_sway_t * 7.0) * 0.01 * bpk


func _update_fx() -> void:
	var m = world.match_node if world else null
	var cigar_on: bool = m != null and m.effect_left(peer_id, "cigar") > 0.0
	var gun_on: bool = m != null and m.effect_left(peer_id, "moneygun") > 0.0
	var holding_ball: bool = world != null and world.ball != null and world.ball.holder == peer_id
	held_cigar.visible = cigar_on and not gun_on
	if m != null:
		var wk: String = "iced" if m.lux_count(peer_id, "roflex_iced") > 0 else ("gold" if m.lux_count(peer_id, "roflex") > 0 else str(look.get("watch", "silver")))
		if wk != _watch_kind:
			_watch_kind = wk
			model.set_watch(wk)
	model.bloodshot = bool(look.get("bloodshot", false)) or cigar_on or (m != null and m.effect_left(peer_id, "powder") > 0.0)
	held_gun.visible = gun_on
	if smoke.emitting != cigar_on:
		smoke.emitting = cigar_on
	if bills.emitting != raining:
		bills.emitting = raining
	# animate the model (ours too, for the first-person body)
	var dt := get_physics_process_delta_time()
	var flat := global_position - _last_pos
	flat.y = 0.0
	_speed = lerpf(_speed, flat.length() / maxf(dt, 0.001), 0.25)
	_last_pos = global_position
	if is_local:
		busy = world.ui_blocking()
	model.move_speed = _speed
	model.look_pitch(0.0 if is_local else pitch)   # our own neck stays put (the camera does the looking)
	var jailed: bool = m != null and m.is_jailed(peer_id)
	finger_prop.visible = EMOTES[emote] == "finger"
	var airborne := global_position.y > 0.45
	if diving > 0.0:
		model.pose = "dive"
	elif holding_ball and airborne:
		model.pose = "dunk"
	elif seat >= 0:
		model.pose = "sit_" + EMOTES[emote] if emote > 0 else ("sit_smoke" if cigar_on else "sit")
	elif emote > 0:
		model.pose = EMOTES[emote]
	elif is_local and _zippo_t > 0.0:
		model.pose = "light"
	elif is_local and _cash_t > 0.0:
		model.pose = "hold"
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


# ---------------------------------------------------------------- chairs + emotes

func sit(chair_id: int) -> void:
	if seat >= 0 or not world.builder.chairs.has(chair_id):
		return
	if EMOTES[emote] == "dance":
		emote = 0
		_emote_t = 0.0
	var c: Dictionary = world.builder.chairs[chair_id]
	teleport(c.pos + Vector3(0, 0.1, 0))
	rotation.y = c.rot + PI
	_set_seat(chair_id)
	Sfx.play("click", -2.0, 0.7)


func stand_up() -> void:
	_set_seat(-1)


## Swap the desk's static chair for one we carry around (everyone sees it).
func _set_seat(id: int) -> void:
	if id == seat or world == null:
		return
	if seat >= 0 and world.builder.chairs.has(seat):
		world.builder.chairs[seat].node.visible = true
	if carried_chair:
		carried_chair.queue_free()
		carried_chair = null
	seat = id if world.builder.chairs.has(id) else -1
	if seat >= 0:
		world.builder.chairs[seat].node.visible = false
		carried_chair = PropKit.place("Chair", self, Vector3(0, 0, 0.12), PI)


## First-person: hold a fat cash stack out in front (money counter).
func show_cash_stack(secs: float) -> void:
	if cash_stack == null:
		cash_stack = PropKit.place("Cash", model.prop_right, Vector3(0.0, -0.02, -0.06), PI / 2)
	cash_stack.visible = true
	_cash_t = secs


func _update_fp_emote(delta: float) -> void:
	if cash_stack:
		_cash_t = maxf(_cash_t - delta, 0.0)
		cash_stack.visible = _cash_t > 0.0
		if cash_stack.visible:   # riffle the stack
			cash_stack.position = Vector3(0.0, -0.02 + sin(_cash_t * 20.0) * 0.006, -0.06)
	var m = world.match_node
	# the Zippo: flick it open and light up whenever a fresh cigar starts
	var cig: float = m.effect_left(peer_id, "cigar") if m else 0.0
	if cig > _cigar_was + 1.0:
		_zippo_t = 1.4
		Sfx.play("click", -2.0, 1.8)
	_cigar_was = cig
	_zippo_t = maxf(_zippo_t - delta, 0.0)
	zippo.visible = _zippo_t > 0.0
	if zippo.visible:
		var fl: Node3D = zippo.get_node("Flame")
		fl.scale = Vector3.ONE * (0.8 + randf() * 0.5)
	# emotes run out (the body plays them; you see your own hands in first person)
	_emote_t = maxf(_emote_t - delta, 0.0)
	if _emote_t <= 0.0:
		emote = 0


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
	emote = (flags >> 3) & 7
	_set_seat(((flags >> 6) & 31) - 1)
	if not _has_target:
		global_position = pos
		_has_target = true
