extends Node
## Highway patrol. The host runs it: holding 110+ mph for a few seconds can
## get you clocked; a patrol car spawns behind you (lights, siren) and the AI
## chases you down. Get PURSUIT_LOST_M away for PURSUIT_LOST_S seconds (or make
## it crash out) and you lost them; get boxed in / stopped next to it for
## PURSUIT_BUST_S and you're pulled over. Cop cars stream to everyone like
## player cars do.

const Rules = preload("res://scripts/sim/rules.gd")
const CarScript = preload("res://scripts/vehicle/car.gd")
const AiDriver = preload("res://scripts/vehicle/ai_driver.gd")

var world
var chases := {}          # server: peer -> {cop, t_far, t_close, t}
var npc := {}             # everyone: cop id -> Car (ours if we're the host)
var _speeding := {}       # server: peer -> seconds over the limit
var _cooldown := {}       # server: peer -> seconds until they can be clocked again
var _tick := 0.0
var _send := 0.0
var _next_id := 1


func _init(w) -> void:
	world = w


func _physics_process(dt: float) -> void:
	if Net.is_server():
		_server(dt)
	for id in npc:
		_lights(npc[id], dt)


# ---------------------------------------------------------------- host

func _server(dt: float) -> void:
	var m = world.match_node
	_tick -= dt
	if _tick <= 0.0:
		_tick = 1.0
		for peer in world.cars:
			var c = world.cars[peer]
			if not is_instance_valid(c) or chases.has(peer) or m.is_jailed(peer):
				continue
			_cooldown[peer] = maxf(_cooldown.get(peer, 0.0) - 1.0, 0.0)
			if c.mph() > Rules.PURSUIT_MPH and _driven(peer):
				_speeding[peer] = _speeding.get(peer, 0.0) + 1.0
				if _speeding[peer] >= 4.0 and _cooldown[peer] <= 0.0 and randf() < 0.35:
					start(peer)
			else:
				_speeding[peer] = maxf(_speeding.get(peer, 0.0) - 1.0, 0.0)
	for peer in chases.keys():
		_step(peer, dt)
	_send -= dt
	if _send <= 0.0:
		_send = 0.05
		for id in npc:
			var c = npc[id]
			world._npc_car_tf.rpc(id, c.key, c.global_position, c.quaternion, c.speed, c.steer)


func _driven(peer: int) -> bool:
	var p = world.player_node(peer)
	return p != null and (p.driving != null or p.get("_in_car"))


## A patrol car clocked `peer`: it comes up from behind, lights on.
func start(peer: int) -> void:
	var target = world.cars.get(peer)
	if target == null or chases.has(peer):
		return
	var id := _next_id
	_next_id += 1
	var cop = _spawn(id, world.pursuit_spawn(target))
	cop.simulate = true
	var ai = AiDriver.new()
	ai.target = target
	cop.add_child(ai)
	chases[peer] = {"cop": id, "t_far": 0.0, "t_close": 0.0, "t": 0.0}
	world.match_node.s_pursuit.rpc(peer, "start")
	world.match_node._add_heat(peer, 15.0)


func _step(peer: int, dt: float) -> void:
	var ch: Dictionary = chases[peer]
	var cop = npc.get(ch.cop)
	var target = world.cars.get(peer)
	if cop == null or target == null or not Net.players.has(peer) or world.match_node.is_jailed(peer):
		_end(peer, "")
		return
	ch.t += dt
	var d: float = cop.global_position.distance_to(target.global_position)
	# boxed in / stopped next to the cop: pulled over
	ch.t_close = ch.t_close + dt if d < 8.0 and target.mph() < 8.0 else 0.0
	if ch.t_close >= Rules.PURSUIT_BUST_S:
		world.match_node.server_pull_over(peer)
		_end(peer, "busted")
		return
	# far enough for long enough (or the cop's wrecked and stuck): lost them
	ch.t_far = ch.t_far + dt if d > Rules.PURSUIT_LOST_M else maxf(ch.t_far - dt * 0.5, 0.0)
	if ch.t_far >= Rules.PURSUIT_LOST_S or ch.t > 150.0:
		_end(peer, "lost")


func _end(peer: int, stage: String) -> void:
	var ch: Dictionary = chases.get(peer, {})
	chases.erase(peer)
	_cooldown[peer] = 45.0
	_speeding[peer] = 0.0
	if ch.has("cop"):
		_remove(ch.cop)
		world._npc_car_gone.rpc(ch.cop)
	if stage != "":
		world.match_node.s_pursuit.rpc(peer, stage)


# ---------------------------------------------------------------- everyone

func _spawn(id: int, xf: Transform3D):
	var c = CarScript.new()
	c.setup("cop", 0)
	c.name = "Cop_%d" % id
	c.global_transform = xf
	world.cars_node.add_child(c)
	c.global_transform = xf
	npc[id] = c
	var siren := AudioStreamPlayer3D.new()
	siren.stream = Sfx.looped("siren")
	siren.unit_size = 14.0
	siren.max_distance = 260.0
	siren.volume_db = -2.0
	c.add_child(siren)
	if siren.stream:
		siren.play()
	var bar := Node3D.new()
	bar.name = "LightBar"
	bar.position = Vector3(0, c.ref.box.y + 0.08, 0.1)
	c.add_child(bar)
	for side in [-1, 1]:
		var q = c._glow_quad(Vector2(0.55, 0.12), Color(1, 0.1, 0.1) if side < 0 else Color(0.1, 0.3, 1))
		q.position = Vector3(side * 0.3, 0, 0)
		q.rotation.x = -PI / 2
		q.name = "Red" if side < 0 else "Blue"
		bar.add_child(q)
		var l := OmniLight3D.new()
		l.light_color = Color(1, 0.1, 0.1) if side < 0 else Color(0.15, 0.3, 1)
		l.omni_range = 9.0
		l.light_energy = 0.0
		l.position = Vector3(side * 0.3, 0.2, 0)
		l.name = "L" + q.name
		bar.add_child(l)
	return c


func _remove(id: int) -> void:
	var c = npc.get(id)
	npc.erase(id)
	if c and is_instance_valid(c):
		c.queue_free()


## Remote copy of a host cop car.
func net_car(id: int, key: String, pos: Vector3, rot: Quaternion, spd: float, st: float) -> void:
	var c = npc.get(id)
	if c == null or not is_instance_valid(c):
		c = _spawn(id, Transform3D(Basis(rot), pos))
	c.net_state(pos, rot, spd, st, false)


func _lights(c, _dt: float) -> void:
	if not is_instance_valid(c):
		return
	var bar: Node3D = c.get_node_or_null("LightBar")
	if bar == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var red_on := fmod(t * 3.0, 1.0) < 0.5
	(bar.get_node("Red") as Node3D).visible = red_on
	(bar.get_node("Blue") as Node3D).visible = not red_on
	(bar.get_node("LRed") as OmniLight3D).light_energy = 2.5 if red_on else 0.0
	(bar.get_node("LBlue") as OmniLight3D).light_energy = 0.0 if red_on else 2.5
