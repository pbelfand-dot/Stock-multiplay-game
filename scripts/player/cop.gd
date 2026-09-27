extends CharacterBody3D
## NYPD-style cop. Chases the raid target on the server using the baked
## navmesh; clients only see interpolated positions.

const SPEED := 6.6          # a bit slower than a sprinting player (7.5)
const CATCH_DIST := 1.25
const DISTRACT_RADIUS := 7.0

var target_id := 0
var world
var agent: NavigationAgent3D
var distracted := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _repath := 0.0


func setup(w, target: int) -> void:
	world = w
	target_id = target


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	_build_body()
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 0.8
	agent.radius = 0.45
	add_child(agent)
	_net_pos = global_position
	var siren := AudioStreamPlayer3D.new()
	siren.stream = Sfx.looped("siren")
	siren.unit_size = 6.0
	siren.volume_db = -6.0
	siren.autoplay = true
	add_child(siren)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 2.3, 0)
	light.omni_range = 5.0
	light.light_color = Color(1, 0.1, 0.1)
	light.name = "Beacon"
	add_child(light)


func _process(_d: float) -> void:
	var l: OmniLight3D = get_node_or_null("Beacon")
	if l:
		var blue := int(Time.get_ticks_msec() / 250) % 2 == 0
		l.light_color = Color(0.1, 0.3, 1) if blue else Color(1, 0.1, 0.1)


func _build_body() -> void:
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.1, 0.14, 0.35)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.93, 0.76, 0.6)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1, 0.8, 0.2)
	var torso := MeshInstance3D.new()
	var tb := CapsuleMesh.new()
	tb.radius = 0.32
	tb.height = 1.2
	torso.mesh = tb
	torso.position.y = 1.0
	torso.material_override = blue
	add_child(torso)
	var h := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.24
	hs.height = 0.5
	h.mesh = hs
	h.position.y = 1.78
	h.material_override = skin
	add_child(h)
	var hat := MeshInstance3D.new()
	var hc := CylinderMesh.new()
	hc.top_radius = 0.27
	hc.bottom_radius = 0.22
	hc.height = 0.16
	hat.mesh = hc
	hat.position.y = 2.0
	hat.material_override = blue
	add_child(hat)
	var badge := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.1, 0.1, 0.03)
	badge.mesh = bb
	badge.position = Vector3(0.12, 1.35, -0.31)
	badge.material_override = gold
	add_child(badge)
	var stache := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.2, 0.05, 0.04)
	stache.mesh = sb
	stache.position = Vector3(0, 1.72, -0.23)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.08, 0.06)
	stache.material_override = dark
	add_child(stache)
	var gun := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(0.08, 0.1, 0.3)
	gun.mesh = gb
	gun.position = Vector3(0, 1.3, -0.5)
	gun.material_override = dark
	add_child(gun)


func _physics_process(delta: float) -> void:
	if not Net.is_server():
		global_position = global_position.lerp(_net_pos, clampf(delta * 10.0, 0, 1))
		rotation.y = lerp_angle(rotation.y, _net_yaw, clampf(delta * 10.0, 0, 1))
		return
	var target: Node3D = world.player_node(target_id)
	if target == null:
		return
	if not is_on_floor():
		velocity.y -= 12.0 * delta
	else:
		velocity.y = 0.0
	# Making it rain distracts cops — they stop to grab bills.
	if distracted > 0.0:
		distracted -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	for p in world.players_node.get_children():
		if p.raining and p.global_position.distance_to(global_position) < DISTRACT_RADIUS:
			distracted = 1.2
			return
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.25
		agent.target_position = target.global_position
	var next := agent.get_next_path_position()
	var to := next - global_position
	to.y = 0.0
	if to.length() < 0.05 or agent.is_navigation_finished():
		to = target.global_position - global_position
		to.y = 0.0
	var dir := to.normalized()
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	if dir.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 10.0, 0, 1))
	move_and_slide()
	var flat := target.global_position - global_position
	flat.y = 0.0
	if flat.length() < CATCH_DIST and absf(target.global_position.y - global_position.y) < 1.5:
		world.match_node.server_cop_caught(target_id)


func net_update(pos: Vector3, yaw: float) -> void:
	_net_pos = pos
	_net_yaw = yaw
