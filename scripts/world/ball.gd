extends RigidBody3D
## Office basketball. Physics runs on the host; everyone else sees synced
## positions. Grab with E, throw with left mouse. Swish = fund bonus.

const RADIUS := 0.16
const THROW_SPEED := 9.5
const SCORE_BONUS := 1_000.0
const SYNC := 1.0 / 20.0

var world
var holder := 0
var last_thrower := 0
var _sync_acc := 0.0
var _net_pos := Vector3.ZERO
var _score_cooldown := 0.0


func setup(w) -> void:
	world = w


func _ready() -> void:
	name = "Ball"
	collision_layer = 8
	collision_mask = 1
	mass = 0.6
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.7
	pm.friction = 0.6
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = RADIUS
	cs.shape = sh
	add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = RADIUS
	sm.height = RADIUS * 2
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.45, 0.1)
	mi.material_override = mat
	add_child(mi)
	for r in [0.0, PI / 2]:
		var seam := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = RADIUS * 0.97
		tm.outer_radius = RADIUS * 1.02
		seam.mesh = tm
		var sm2 := StandardMaterial3D.new()
		sm2.albedo_color = Color(0.1, 0.05, 0.02)
		seam.material_override = sm2
		seam.rotation.z = r
		add_child(seam)
	set_meta("interact", "ball")
	set_meta("interact_id", 0)
	set_meta("prompt", "[E] Grab ball")
	global_position = world.builder.ball_spawn
	_net_pos = global_position
	if not Net.is_server():
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	else:
		var hoop := Area3D.new()
		hoop.collision_layer = 0
		hoop.collision_mask = 8
		var hs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.2
		hs.shape = sph
		hoop.add_child(hs)
		world.add_child.call_deferred(hoop)
		hoop.set_deferred("global_position", world.builder.hoop_rim)
		hoop.body_entered.connect(_on_hoop)


func _physics_process(delta: float) -> void:
	var local = world.local_player
	if holder != 0 and local and holder == local.peer_id:
		# our own held ball: glue it to our view for zero-lag feel
		global_position = local.cam.global_position + (-local.cam.global_basis.z) * 0.55 + Vector3(0, -0.15, 0)
	elif not Net.is_server():
		global_position = global_position.lerp(_net_pos, clampf(delta * 15.0, 0, 1))
	if not Net.is_server():
		return
	_score_cooldown = maxf(_score_cooldown - delta, 0.0)
	if holder != 0:
		var p = world.player_node(holder)
		if p == null or world.match_node.is_jailed(holder):
			_drop()
		elif p != local:
			var fwd := Vector3(0, 0, -1).rotated(Vector3.RIGHT, p.pitch).rotated(Vector3.UP, p.rotation.y)
			global_position = p.global_position + Vector3(0, 1.45, 0) + fwd * 0.55
	if global_position.y < -5.0 or global_position.length() > 60.0:
		_reset()
	_sync_acc += delta
	if _sync_acc >= SYNC:
		_sync_acc = 0.0
		_s_ball.rpc(global_position, holder)


func _drop() -> void:
	holder = 0
	freeze = false


func _reset() -> void:
	holder = 0
	freeze = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_position = world.builder.ball_spawn


func _on_hoop(body: Node) -> void:
	if body != self or _score_cooldown > 0.0 or linear_velocity.y > 0.0 or last_thrower == 0:
		return
	_score_cooldown = 2.0
	var m = world.match_node
	if m.phase == "trading":
		m.ledger.adjust(m.acct_for(last_thrower), SCORE_BONUS)
		m._push_state()
	m._s_toast.rpc("SWISH! %s drains it. +$1,000" % Net.player_name(last_thrower))
	_s_swish.rpc()


# ---------------------------------------------------------------- requests

func request_grab() -> void:
	_req_grab.rpc_id(1)


func request_throw(dir: Vector3) -> void:
	_req_throw.rpc_id(1, dir)


@rpc("any_peer", "call_local", "reliable")
func _req_grab() -> void:
	if not Net.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	var p = world.player_node(id)
	if holder != 0 or p == null or p.global_position.distance_to(global_position) > 3.5:
		return
	holder = id
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_s_ball.rpc(global_position, holder)


@rpc("any_peer", "call_local", "reliable")
func _req_throw(dir: Vector3) -> void:
	if not Net.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if holder != id:
		return
	var p = world.player_node(id)
	holder = 0
	last_thrower = id
	freeze = false
	if p:
		var fwd := Vector3(0, 0, -1).rotated(Vector3.RIGHT, p.pitch).rotated(Vector3.UP, p.rotation.y)
		global_position = p.global_position + Vector3(0, 1.45, 0) + fwd * 0.6
	linear_velocity = dir.normalized() * THROW_SPEED + Vector3(0, 1.5, 0)
	_s_ball.rpc(global_position, holder)


@rpc("authority", "call_local", "unreliable_ordered")
func _s_ball(pos: Vector3, h: int) -> void:
	_net_pos = pos
	holder = h


@rpc("authority", "call_local", "reliable")
func _s_swish() -> void:
	Sfx.play("swish", 4.0)
	Sfx.play("cash")
