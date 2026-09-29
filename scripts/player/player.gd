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
const CashArt = preload("res://scripts/art/cash_art.gd")
const GunArt = preload("res://scripts/art/gun_art.gd")
const DriveCam = preload("res://scripts/vehicle/drive_cam.gd")
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
const EMOTES := ["", "finger", "fistpump", "watch", "point", "dance", "smoke_cough", "smoke_chill",
	"flash", "fan"]   # 4 sync bits: max 16
const HELD_EMOTES := ["flash", "fan"]   # stay up until you press it again (or 20 s)
const EMOTE_TIME := 2.4
const ROLL_SPEED := 2.2
var emote := 0              # index into EMOTES (synced)
var _emote_t := 0.0
var _dance_tilt := 0.0
var _arrive_t := -1.0             # elevator arrival: seconds in (-1 = not arriving)
const ARRIVE_WAIT := 1.2          # ding, doors slide open
const ARRIVE_WALK := 1.9          # walk out onto the floor
var puff: CPUParticles3D          # smoke out of the mouth (smoke emotes)
var _puffing := false
var _coughed := false
var seat := -1              # desk chair id we're sitting in (synced), -1 = standing
var carried_chair: Node3D
var zippo: Node3D
var _zippo_t := 0.0
var _cigar_was := 0.0
var cash_stack: Node3D           # the stack in your hand (sized by your cash on hand)
var _stack_amount := -1.0         # what the current stack was built for
var held_fan: Node3D
# BIG IRON: the gun you've got out (from the match's `drawn`, so everyone sees it)
var gun_node: Node3D
var _gun_key := ""
var _shot_cd := 0.0
var _aim_t := 0.0                 # > 0: arms up, aiming (after a shot, or holding right click)
var _kick := 0.0                  # recoil still settling (radians of camera pitch)
var photo_aim := false            # photo mode: hold the aim for the shot
# driving: the car we're in (ours: we simulate it) / a remote player's "in a car" flag
var driving = null
var drive_cam: Camera3D
var _in_car := false
var riding = null               # a cab we're a passenger in (World.cab / CabRide drives it)
var _in_cab := false            # (remote) they're riding in a cab
var _cash_t := 0.0
# smooth motion (physics runs at 60 Hz, the screen often faster). Remote
# puppets and anyone in a car are physics-interpolated. Our own body on foot
# isn't (mouse look has to turn it this frame, not a tick later): it and the
# camera are drawn between the last two ticks by hand (see _process).
var _tick_prev := Vector3.ZERO
var _tick_cur := Vector3.ZERO
var _head_pos := Vector3(0, 1.62, 0)   # where the head/camera sits in the body (before that offset)
var _target_vel := Vector3.ZERO        # remote: how they're moving (between their 20 Hz updates)
var _target_t := 0.0


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
	process_physics_priority = 10      # after the cars move: seated in one, we sit where it is *now*
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
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		cam.fov = 80
		cam.near = 0.05
		cam.far = Graphics.cur.far
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
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_fx()
	_target_pos = global_position
	_tick_prev = global_position
	_tick_cur = global_position


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
	held_cigar.visible = false
	held_gun.visible = false
	if is_local:
		zippo = Props.zippo()
		zippo.rotation = Vector3(-PI / 2, 0, 0)
		zippo.visible = false
		model.prop_left.add_child(zippo)
	cash_stack = null                   # the old hands (and what was in them) are gone
	held_fan = null
	gun_node = null
	_gun_key = ""
	_stack_amount = -1.0


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
	if driving != null:                  # in the car: E gets out, C switches the camera
		if world.ui_blocking():
			return
		if event.is_action_pressed("interact"):
			exit_car()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("dive") and drive_cam:
			drive_cam.toggle()
			model.set_first_person(drive_cam.cockpit)
		return
	if not world.ui_blocking():
		for i in range(1, EMOTES.size()):
			var act: String = "emote_" + EMOTES[i]
			if InputMap.has_action(act) and event.is_action_pressed(act):   # not every emote has a hotkey
				play_emote(EMOTES[i])
		if event.is_action_pressed("spread_cash"):
			world.toggle_spread()
		if event.is_action_pressed("draw_gun"):
			cycle_gun()
		if seat >= 0 and (event.is_action_pressed("jump") or event.is_action_pressed("dive")):
			stand_up()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * Config.mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * Config.mouse_sensitivity, -1.45, 1.45)
		head.rotation.x = pitch


func _physics_process(delta: float) -> void:
	if is_local:
		var start := global_position        # (a teleport since the last tick starts here: no smear)
		if driving != null:
			_drive_tick(delta)
		elif riding != null:
			_seat_in_cab(riding)
		else:
			_local_move(delta)
		_tick_prev = start
		_tick_cur = global_position
		_send_acc += delta
		if _send_acc >= SEND_RATE:
			_send_acc = 0.0
			var flags := (1 if raining else 0) | (2 if diving > 0.0 else 0) | (4 if world.ui_blocking() else 0) \
					| (emote << 3) | ((seat + 1) << 7) | ((1 << 12) if driving != null else 0) \
					| ((1 << 13) if riding != null else 0)
			world._p_tf.rpc(global_position, rotation.y, pitch, flags)
	else:
		var their_car = world.cars.get(peer_id) if _in_car else null
		var their_cab = world.cabs.get(peer_id) if _in_cab else null
		if their_cab != null and is_instance_valid(their_cab):
			_seat_in_cab(their_cab)           # glued to their cab's back seat (no lag behind it at 70 mph)
		elif their_car != null and is_instance_valid(their_car):
			_seat_at(their_car)
		elif _has_target:
			# dead reckoning: keep walking the way they were going, ease toward the prediction
			_target_t += delta
			var want := _target_pos + _target_vel * minf(_target_t, 0.2)
			var coast := global_position + _target_vel * delta if _target_t < 0.2 else global_position
			global_position = coast.lerp(want, 1.0 - exp(-delta * 10.0))
			if global_position.distance_to(want) > 6.0:
				global_position = want
				reset_physics_interpolation()
			rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-delta * 12.0))
	_update_fx()


## Our own body on foot: draw it (and the camera in its head) where it is
## between the last two physics ticks, so walking is smooth at any frame rate.
## Turning stays instant (the body isn't interpolated). In a car the body is
## interpolated with the car instead.
func _process(_delta: float) -> void:
	if not is_local or model == null:
		return
	var off := Vector3.ZERO
	if driving == null and riding == null and global_position.is_equal_approx(_tick_cur):
		var f := Engine.get_physics_interpolation_fraction()
		off = global_basis.inverse() * (_tick_prev.lerp(_tick_cur, f) - _tick_cur)
	model.position = off
	head.position = _head_pos + off


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
	if _arrive_t >= 0.0:            # elevator arrival: wait for the doors, then walk out
		_arrive_t += delta
		input = Vector2.ZERO
		speed = WALK * 0.62
		if _arrive_t > ARRIVE_WAIT + ARRIVE_WALK:
			_arrive_t = -1.0
	if EMOTES[emote] == "dance" and (input != Vector2.ZERO or Input.is_action_just_pressed("jump")):
		emote = 0                  # moving ends the dance
		_emote_t = 0.0
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	if _arrive_t > ARRIVE_WAIT:
		dir = Vector3(0, 0, -1)     # straight out onto the floor (look around all you want)
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
	var busy_hands: bool = blocked or world.phone_up()   # clicks on the phone aren't shots
	if holding and not busy_hands and Input.is_action_just_pressed("fire"):
		ball.request_throw(-cam.global_basis.z)
	# money gun
	raining = (not holding and not busy_hands and m != null and m.effect_left(peer_id, "moneygun") > 0.0
		and Input.is_action_pressed("fire"))
	if raining:
		_brrt_acc -= delta
		if _brrt_acc <= 0.0:
			_brrt_acc = 0.22
			Sfx.play("brrt", -6.0, randf_range(0.9, 1.1))
	# BIG IRON: click fires (hold for the automatics), right click aims
	_shot_cd = maxf(_shot_cd - delta, 0.0)
	if gun_node and _gun_key != "" and not holding and not busy_hands and seat < 0:
		var d: Dictionary = Rules.LUXURY[_gun_key]
		var trig: bool = Input.is_action_pressed("fire") if d.auto else Input.is_action_just_pressed("fire")
		if trig and _shot_cd <= 0.0:
			_fire(d)
		if Input.is_action_pressed("aim"):
			_aim_t = maxf(_aim_t, 0.2)
	if _kick > 0.0:                   # recoil climbs, then most of it settles back
		var back := minf(_kick, delta * 0.6)
		_kick -= back
		pitch = clampf(pitch - back * 0.7, -1.45, 1.45)
	# the camera rides the body's eyes (sitting, diving, dancing all move it),
	# set back a little so looking down shows your chest, not the floor in front of it
	var eye: Vector3 = model.basis * (model.global_transform.affine_inverse() * model.j["eyes"].global_position) \
			if model.j.has("eyes") else Vector3(0, 1.62, 0)     # (in the body's frame, whatever offset the model is drawn at)
	var turn: float = model.body_yaw() if EMOTES[emote] == "dance" else 0.0   # the view turns with the dance
	eye += Basis(Vector3.UP, turn) * Vector3(0, 0, 0.03)
	_head_pos = _head_pos.lerp(eye, clampf(delta * 18.0, 0.0, 1.0))
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
			var aiming: bool = gun_node != null and Input.is_action_pressed("aim") and not blocked
			cam.fov = lerpf(cam.fov, 62.0 if aiming else 80.0, delta * (10.0 if aiming else 3.0))
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
	var smoking_emote: bool = EMOTES[emote].begins_with("smoke_")
	held_cigar.visible = (cigar_on or smoking_emote) and not gun_on
	_update_puff(smoking_emote)
	if m != null:
		var wk: String = "iced" if m.lux_count(peer_id, "roflex_iced") > 0 else ("gold" if m.lux_count(peer_id, "roflex") > 0 else str(look.get("watch", "silver")))
		if wk != _watch_kind:
			_watch_kind = wk
			model.set_watch(wk)
	model.bloodshot = bool(look.get("bloodshot", false)) or cigar_on or (m != null and m.effect_left(peer_id, "powder") > 0.0)
	held_gun.visible = gun_on
	_update_held_cash(m)
	_update_gun(m, gun_on or jailed_now(m) or driving != null or _in_car)
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
	var airborne := global_position.y > 0.45
	if riding != null or _in_cab:
		model.pose = "sit"
	elif driving != null or _in_car:
		model.pose = "drive"
	elif diving > 0.0:
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
	elif gun_node and gun_node.visible:
		var rifle: bool = Rules.LUXURY[_gun_key].rifle
		model.pose = ("rifle" if rifle else "pistol") + ("_aim" if _aim_t > 0.0 else "")
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


# ---------------------------------------------------------------- driving

## Get behind the wheel: our body sits in the driver's seat, the chase cam
## takes over, the car is ours to simulate.
func enter_car(car) -> void:
	if driving != null or car == null:
		return
	if EMOTES[emote] != "":
		emote = 0
		_emote_t = 0.0
	stand_up()
	driving = car
	car.simulate = true
	collision_layer = 0
	collision_mask = 0
	drive_cam = DriveCam.new()
	world.add_child(drive_cam)
	drive_cam.follow(car)
	model.set_first_person(false)
	Sfx.play("click", -2.0, 0.6)
	_seat_in_car()
	_ride_smooth(true)


## Out the driver's door (only when it's nearly stopped, unless `force`:
## pulled over / arrested).
func exit_car(force := false) -> void:
	if driving == null:
		return
	if absf(driving.speed) > 4.0 and not force:
		world.hud.show_toast("Slow down first.", Color(1, 0.6, 0.3))
		return
	var car = driving
	car.in_throttle = 0.0
	car.in_brake = 1.0
	car.in_steer = 0.0
	car.in_handbrake = true
	driving = null
	collision_layer = 2
	collision_mask = 1
	_ride_smooth(false)
	teleport(car.to_global(car.ref.door + Vector3(-0.7, 0.1, 0)))
	rotation.y = car.global_rotation.y
	if drive_cam:
		drive_cam.queue_free()
		drive_cam = null
	cam.current = true
	model.set_first_person(true)
	Sfx.play("click", -2.0, 0.5)


func _drive_tick(delta: float) -> void:
	var car = driving
	if car == null or not is_instance_valid(car):
		driving = null
		return
	var blocked: bool = world.ui_blocking()
	if blocked:
		car.in_throttle = 0.0
		car.in_brake = 0.3
		car.in_steer = 0.0
		car.in_handbrake = false
	else:
		car.in_throttle = Input.get_action_strength("move_forward")
		car.in_brake = Input.get_action_strength("move_back")
		car.in_steer = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
		car.in_handbrake = Input.is_action_pressed("jump")
	_seat_in_car()
	world.send_car(car)


## In a car our body is physics-interpolated along with it (both move on the
## tick, so it stays glued to the seat as drawn); on foot it's drawn by hand.
func _ride_smooth(on: bool) -> void:
	if not is_local:
		return
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON if on else Node.PHYSICS_INTERPOLATION_MODE_OFF
	model.position = Vector3.ZERO
	head.position = _head_pos
	reset_physics_interpolation()


## Our body rides in the driver's seat (everyone sees us in there).
func _seat_in_car() -> void:
	_seat_at(driving)


func _seat_at(car) -> void:
	var eye: Vector3 = car.ref.eye
	global_position = car.to_global(Vector3(eye.x, eye.y - 1.19, eye.z + 0.05))
	rotation = Vector3(0, car.global_rotation.y, 0)
	velocity = Vector3.ZERO


## The back seat, behind the front passenger.
func _seat_in_cab(cab) -> void:
	var eye: Vector3 = cab.ref.eye
	global_position = cab.to_global(Vector3(-eye.x, eye.y - 1.19 - 0.4, eye.z + 1.0))
	rotation = Vector3(0, cab.global_rotation.y, 0)
	velocity = Vector3.ZERO


## Into the back of a cab: the camera follows the cab, the driver drives.
func board_cab(cab) -> void:
	if driving != null or cab == null:
		return
	if EMOTES[emote] != "":
		emote = 0
		_emote_t = 0.0
	stand_up()
	riding = cab
	collision_layer = 0
	collision_mask = 0
	if drive_cam == null:
		drive_cam = DriveCam.new()
		world.add_child(drive_cam)
	drive_cam.follow(cab)
	model.set_first_person(false)
	_seat_in_cab(cab)
	_ride_smooth(true)
	Sfx.play("click", -2.0, 0.6)


## Out of the cab onto the curb at `at`.
func leave_cab(at: Vector3, yaw: float) -> void:
	if riding == null:
		return
	riding = null
	collision_layer = 2
	collision_mask = 1
	_ride_smooth(false)
	teleport(at)
	rotation.y = yaw
	if drive_cam:
		drive_cam.queue_free()
		drive_cam = null
	cam.current = true
	model.set_first_person(true)
	Sfx.play("click", -2.0, 0.5)


# ---------------------------------------------------------------- guns (BIG IRON)

## Where the left wrist goes on each gun (gun-local: grip at the origin, barrel
## -z, gun's left = -x): under the handguard / pump for long guns, wrapped
## round the left of the grip for pistols.
const SUPPORT := {
	"pistol": Vector3(-0.04, -0.07, 0.035), "deagle": Vector3(-0.045, -0.075, 0.04),
	"smg": Vector3(-0.035, -0.03, -0.07), "shotgun": Vector3(-0.04, -0.07, -0.2),
	"ak": Vector3(-0.04, -0.03, -0.15), "ak_gold": Vector3(-0.04, -0.03, -0.15),
}


func jailed_now(m) -> bool:
	return m != null and m.is_jailed(peer_id)


## Q: out comes your first gun, then the next, then back in the holster.
func cycle_gun() -> void:
	var m = world.match_node if world else null
	if m == null:
		return
	var mine: Array = m.guns_of(peer_id)
	if mine.is_empty():
		world.hud.show_toast("You don't own a gun. BIG IRON is on the street, next to the Chavél store.", Color(1, 0.6, 0.3))
		return
	var at := mine.find(m.gun_of(peer_id))
	m.request_draw("" if at == mine.size() - 1 else mine[at + 1])


## Build / swap / hide the gun in your hand to match what the match says you
## have out (a money gun or cuffs put it away).
func _update_gun(m, hide: bool) -> void:
	var key: String = m.gun_of(peer_id) if m != null else ""
	if key != _gun_key:
		if gun_node and is_instance_valid(gun_node):
			gun_node.queue_free()
		gun_node = null
		_gun_key = key
		if key != "" and Rules.is_gun(key):
			gun_node = GunArt.make(key)
			gun_node.rotation = Vector3(-PI / 2, 0, 0)      # barrel out of the fist, like the cops' pistols
			model.prop_right.add_child(gun_node)
			if is_local or _near_me(12.0):
				Sfx.play("rack", -4.0 if is_local else -12.0)
	if gun_node:
		gun_node.visible = not hide
	_aim_t = maxf(_aim_t - get_physics_process_delta_time(), 0.0)
	if photo_aim:
		_aim_t = maxf(_aim_t, 0.2)
	# the barrel points where we're looking when aiming (low and ahead when not);
	# aiming, the arms follow the look up and down
	var aiming := _aim_t > 0.0
	model.aim_pitch = clampf(pitch, -0.9, 1.0) if aiming and gun_node else 0.0
	if gun_node and gun_node.visible:
		var rifle: bool = Rules.LUXURY[_gun_key].rifle
		var pt: float = pitch if aiming else (-0.55 if rifle else -0.3)
		var dir: Vector3 = (-global_basis.z * cos(pt) + Vector3.UP * sin(pt)).normalized()
		gun_node.global_basis = Basis.looking_at(dir, Vector3.UP)
		# second hand on the gun: rifles always, pistols when aiming (wraps the grip)
		var sup: Variant = SUPPORT.get(_gun_key) if (rifle or aiming) else null
		model.left_hand_to(gun_node.global_transform * (sup as Vector3) if sup != null else null)
	else:
		model.left_hand_to(null)


func _near_me(r: float) -> bool:
	var me = world.local_player if world else null
	return me != null and is_instance_valid(me) and me.global_position.distance_to(global_position) < r


## Pull the trigger: flash, bang, kick, a hole where it lands (pellets for the
## shotgun), then tell the host (which tells everyone and decides the heat).
func _fire(d: Dictionary) -> void:
	_shot_cd = float(d.rate)
	_aim_t = 1.4
	GunArt.flash(gun_node, d.big)
	Sfx.play("shot_big" if d.big else "shot", -1.0, randf_range(0.94, 1.06))
	get_tree().create_timer(0.4).timeout.connect(func(): Sfx.play("casing", -16.0, randf_range(0.9, 1.1)))
	var k: float = float(d.kick) * randf_range(0.8, 1.2)
	pitch = clampf(pitch + k, -1.45, 1.45)
	_kick += k
	rotation.y += randf_range(-0.3, 0.3) * k
	var from := cam.global_position
	var fwd := -cam.global_basis.z
	var spread := 0.05 if int(d.pellets) > 1 else (0.004 + minf(_speed, 6.0) * 0.004)
	var first := from + fwd * 60.0
	for n in int(d.pellets):
		var dir := (fwd + cam.global_basis.x * randf_range(-spread, spread) + cam.global_basis.y * randf_range(-spread, spread)).normalized()
		var hit: Dictionary = world.shoot_ray(from, dir, self)
		if n == 0 and not hit.is_empty():
			first = hit.position
	world.match_node.request_shot(first)


## Someone else fired: see the flash, hear it (quieter the further away).
func remote_fire(hit: Vector3) -> void:
	if gun_node == null or _gun_key == "":
		return
	var d: Dictionary = Rules.LUXURY[_gun_key]
	_aim_t = 1.4
	GunArt.flash(gun_node, d.big)
	var me = world.local_player if world else null
	var dist: float = me.global_position.distance_to(global_position) if me else 0.0
	if dist < 70.0:
		Sfx.play("shot_big" if d.big else "shot", -1.0 - dist * 0.45, randf_range(0.94, 1.06))
	var tip: Node3D = gun_node.get_node_or_null("Muzzle")
	var from: Vector3 = tip.global_position if tip else global_position + Vector3(0, 1.4, 0)
	if from.distance_to(hit) > 0.05:
		for n in int(d.pellets):
			var to := hit + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (0.06 if n > 0 else 0.0) * from.distance_to(hit) * 0.05
			world.shoot_ray(from, (to - from).normalized(), self)


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
	_cash_t = secs


func _update_fp_emote(delta: float) -> void:
	_cash_t = maxf(_cash_t - delta, 0.0)
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


## Arriving by elevator: stand in the car while the doors open, then walk out.
func begin_arrival() -> void:
	_arrive_t = 0.0
	pitch = 0.0
	head.rotation.x = 0.0
	if seat >= 0:
		stand_up()


func arriving() -> bool:
	return _arrive_t >= 0.0


## Start an emote by name (hotkeys and the emote wheel). Dancing again stops it.
func play_emote(e: String) -> void:
	var i := EMOTES.find(e)
	if i <= 0:
		return
	if e == "dance":
		if seat >= 0:
			return
		if EMOTES[emote] == "dance":
			emote = 0
			_emote_t = 0.0
			return
		emote = i
		_emote_t = Character.clip_length("dance") * 3.0
		return
	if e in HELD_EMOTES:
		if EMOTES[emote] == e:                   # pressed again: put it away
			emote = 0
			_emote_t = 0.0
			return
		var m = world.match_node if world else null
		if is_local and m != null and m.cash_of(peer_id) < 100.0:
			world.hud.show_toast("No cash on you. Hit an ATM first (office by the elevator, or outside the bank).", Color(1, 0.6, 0.3))
			return
		emote = i
		_emote_t = 20.0
		Sfx.play("brrt" if e == "flash" else "cash", -8.0, 1.4)
		return
	emote = i
	# rotoscoped emotes play their whole clip once; the rest are short
	var clip_len: float = Character.clip_length(e) if e in ["finger", "watch", "smoke_cough", "smoke_chill"] else 0.0
	_emote_t = clip_len if clip_len > 0.0 else EMOTE_TIME
	if e == "watch":
		Sfx.play("coin", -4.0, 1.3)


## Smoke emotes: puffs out of the mouth on the exhales/coughs baked into the clip.
func _update_puff(on: bool) -> void:
	if puff == null:
		puff = CPUParticles3D.new()
		puff.emitting = false
		puff.one_shot = false
		puff.amount = 18
		puff.lifetime = 1.8
		puff.direction = Vector3(0, 0.4, -1)
		puff.spread = 22
		puff.initial_velocity_min = 0.35
		puff.initial_velocity_max = 0.8
		puff.gravity = Vector3(0, 0.25, 0)
		puff.damping_min = 0.4
		puff.damping_max = 0.8
		puff.scale_amount_min = 0.35
		puff.scale_amount_max = 1.1
		puff.mesh = smoke.mesh
		puff.local_coords = false
		add_child(puff)
	var fx: Dictionary = model.clip_fx if on else {}
	var want: bool = float(fx.get("puff", 0.0)) > 0.5
	if model.j.has("eyes"):
		puff.global_transform = model.j["eyes"].global_transform.translated_local(Vector3(0, -0.07, -0.06))   # the lips
	if want != _puffing:
		_puffing = want
		puff.emitting = want
	var coughing: bool = float(fx.get("cough", 0.0)) > 0.5
	if coughing and not _coughed:
		Sfx.play("cough", -4.0 if is_local else -10.0, randf_range(0.95, 1.08))
	_coughed = coughing


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
	_target_vel = Vector3.ZERO
	_tick_prev = pos
	_tick_cur = pos
	if is_inside_tree():
		reset_physics_interpolation()


## Called by World when this player's owner broadcasts its transform.
func net_tf(pos: Vector3, yaw: float, p: float, flags: int) -> void:
	if _has_target and _target_t > 0.001:
		var v := (pos - _target_pos) / clampf(_target_t, 0.02, 1.0)
		_target_vel = v if v.length() < 15.0 else Vector3.ZERO     # (a jump: an elevator, a taxi)
	_target_t = 0.0
	_target_pos = pos
	_target_yaw = yaw
	pitch = p
	raining = flags & 1 != 0
	diving = 0.5 if flags & 2 != 0 else 0.0
	busy = flags & 4 != 0
	emote = (flags >> 3) & 15
	_set_seat(((flags >> 7) & 31) - 1)
	_in_car = flags & (1 << 12) != 0
	_in_cab = flags & (1 << 13) != 0
	if not _has_target:
		global_position = pos
		_has_target = true


# ---------------------------------------------------------------- cash in hand

## The stack in your right hand while you flash it (or run it through a
## counter): rebuilt when your cash on hand changes, so more money = a
## bigger stack, and the top bill riffles. The fan for the money-spread pose.
func _update_held_cash(m) -> void:
	var e: String = EMOTES[emote]
	var cash: float = m.cash_of(peer_id) if m != null else 0.0
	var show_stack := (e == "flash" or _cash_t > 0.0) and cash >= 100.0
	if show_stack:
		var tier: float = floor(cash / 1000.0) * 1000.0          # rebuild on $1K changes, not every cent
		if cash_stack == null or not is_instance_valid(cash_stack) or tier != _stack_amount:
			if cash_stack and is_instance_valid(cash_stack):
				cash_stack.queue_free()
			cash_stack = CashArt.hand_stack(maxf(tier, 100.0))
			cash_stack.position = Vector3(0.0, -0.01, -0.05)
			cash_stack.rotation = Vector3(-PI / 2, 0.0, 0.0)          # stands up out of the fist, band facing out
			model.prop_right.add_child(cash_stack)
			_stack_amount = tier
		var rf: Node3D = cash_stack.get_node_or_null("Riffle")
		if rf:
			rf.rotation.z = -absf(sin(Time.get_ticks_msec() / 1000.0 * 14.0)) * 0.45
	if cash_stack and is_instance_valid(cash_stack):
		cash_stack.visible = show_stack
	if e == "fan":
		if held_fan == null or not is_instance_valid(held_fan):
			held_fan = CashArt.fan()
			held_fan.position = Vector3(0.0, -0.01, -0.05)
			held_fan.rotation = Vector3(-PI / 2, 0.0, 0.0)           # opens up out of the fist, facing out
			held_fan.scale = Vector3.ONE * 1.15
			model.prop_right.add_child(held_fan)
		held_fan.visible = true
	elif held_fan and is_instance_valid(held_fan):
		held_fan.visible = false
