extends Node
## The commute, end to end on a real (headless, host-only) match:
##   --commutecheck --host --autostart --commute=60
## Day 1 morning: you wake up at home with your car in the driveway; an AI
## driver takes your car down the real route (neighborhood loop, on-ramp,
## the highway, off-ramp, the downtown roundabout, the street) to the lobby,
## you take the elevator up: on time. Day 2 you oversleep: black screen, the
## bell rings without you (LATE), you walk in late and it's counted.

const Rules = preload("res://scripts/sim/rules.gd")
const AiDriver = preload("res://scripts/vehicle/ai_driver.gd")

var m
var w


func _ready() -> void:
	_run.call_deferred()


func _say(msg: String) -> void:
	print("[commute] " + msg)


func _done(ok: bool, msg: String) -> void:
	Engine.time_scale = 1.0
	print("[commute] %s %s" % ["COMMUTE PASS" if ok else "COMMUTE FAIL:", msg])
	Sfx.quit_game(0 if ok else 1)


func _wait(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > secs:
			return false
	return true


func _run() -> void:
	if not await _wait(func(): return get_node_or_null("/root/Main/World/Match") != null, 20.0):
		_done(false, "no match")
		return
	m = get_node("/root/Main/World/Match")
	w = m.world
	if not await _wait(func(): return m.phase == "morning", 20.0):
		_done(false, "day 1 didn't start with a morning (phase %s)" % m.phase)
		return
	await get_tree().create_timer(0.5).timeout
	var me = w.local_player
	var home: Dictionary = w.home_of(1)
	# no car yet: the driveway's empty; a cab costs the fare and crawls
	if w.cars.get(1) != null or m.car_of(1) != "":
		_done(false, "started with a car (%s)" % m.car_of(1))
		return
	var bal0: float = m.ledger.get_acct(0).balance
	if not w.hood.ride("downtown"):
		_done(false, "no cab without a car in the morning")
		return
	if not await _wait(func(): return m.ledger.get_acct(0).balance <= bal0 - Rules.CAB_FARE + 0.5, 3.0) or not w.hud.busy():
		_done(false, "cab fare / ride wrong: %f -> %f, riding %s" % [bal0, m.ledger.get_acct(0).balance, w.hud.busy()])
		return
	_say("no car: a cab downtown, $%d, %d s stuck in traffic" % [int(Rules.CAB_FARE), int(Rules.CAB_RIDE_S)])
	w.hud._asleep = 0.01
	await get_tree().create_timer(0.3).timeout
	# buy the used TOROLA; next wake-up it's in the driveway
	m.request_buy_car("beater", 0)
	if not await _wait(func(): return m.car_of(1) == "beater", 3.0):
		_done(false, "couldn't buy the used car")
		return
	w._on_morning({})
	await get_tree().create_timer(0.3).timeout
	if w.hood.ride("downtown"):
		_done(false, "got a cab in rush hour with a car in the driveway")
		return
	var car = w.cars.get(1)
	if home.is_empty() or me.global_position.distance_to(home.spawn) > 1.5 or car == null \
			or car.global_position.distance_to(home.drive) > 2.0:
		_done(false, "didn't wake up at home with the car in the driveway (home %s, me %s, car %s)" % [
				str(home.get("address")), me.global_position, car.global_position if car else null])
		return
	_say("woke up at %s (%s), the used TOROLA in the driveway, no cab for you now, bell in %d s" % [home.address, "rented" if home.rented else "owned", int(m.time_left)])
	# the drive: an AI driver chases a rabbit down the real route
	var hw = w.builder.hood.hw
	var pts: PackedVector3Array = hw.route("home_to_office").points
	car.global_position = pts[0] + Vector3(0, 0.4, 0)
	car.look_at(pts[3] + Vector3(0, 0.4, 0), Vector3.UP)
	car.rotation.x = 0.0
	car.rotation.z = 0.0
	car.simulate = true                          # the AI drives (the player's hands off the wheel)
	var ai = AiDriver.new()
	ai.mode = "path"
	ai.path = pts
	ai.cruise = 34.0
	car.add_child(ai)
	car.debug_hits = Config.cli.has("verbose")
	var crashes: Array = []
	car.crashed.connect(func(i): crashes.append(i))
	Engine.time_scale = 3.0
	for dy in [0.3, 0.9]:
		var q := PhysicsRayQueryParameters3D.create(car.global_position + Vector3(0, dy, 0), car.global_position + Vector3(0, dy, 0) - car.global_basis.z * 6.0)
		q.exclude = [car.get_rid()]
		var hh: Dictionary = w.get_world_3d().direct_space_state.intersect_ray(q)
		if not hh.is_empty():
			print("  ahead y+%.1f: %s at %s (parent %s)" % [dy, hh.collider.name, hh.position, hh.collider.get_parent().name])
	var idx := 0
	var t := 0.0
	var lobby: Vector3 = w.builder.street.lobby_exit
	var start_bell: float = m.time_left
	while t < 240.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		idx = ai._pi
		if Config.cli.has("verbose") and absf(t - 9.0) < 0.01:
			for dy in [0.35, 0.6, 1.0]:
				for side in [-0.8, 0.0, 0.8]:
					var o: Vector3 = car.global_position + car.global_basis * Vector3(side, dy, -1.5)
					var q := PhysicsRayQueryParameters3D.create(o, o - car.global_basis.z * 4.0)
					q.exclude = [car.get_rid()]
					var hh: Dictionary = w.get_world_3d().direct_space_state.intersect_ray(q)
					print("  probe y%.2f x%.1f: %s" % [dy, side, "clear" if hh.is_empty() else "%s at %s n=%s (%s)" % [hh.collider.name, hh.position, hh.normal, hh.collider.get_parent().name]])
			print("  car rot %s yaw %.2f pts0 %s pts1 %s pts2 %s" % [car.rotation, car.rotation.y, pts[0], pts[1], pts[2]])
		if Config.cli.has("verbose") and int(t * 60) % 120 == 0:
			print("  t %.0f car %s spd %.1f idx %d/%d thr %.1f br %.1f st %.2f" % [t, car.global_position, car.speed, idx, pts.size(), car.in_throttle, car.in_brake, car.in_steer])
		if car.global_position.distance_to(lobby) < 14.0 or ai.done:
			break
	Engine.time_scale = 1.0
	ai.queue_free()
	var drove: float = car.global_position.distance_to(lobby)
	if drove > 20.0:
		_done(false, "the AI didn't make it downtown in %.0f s (stuck %.0f m from the lobby at %s, route point %d/%d, %d hits)" % [
				t, drove, car.global_position, idx, pts.size(), crashes.size()])
		return
	var game_t := t * 3.0
	_say("the AI drove the route in %.0f s of game time (%d m: loop, on-ramp, highway, off-ramp, roundabout, street; %d hits)" % [game_t, int(_route_len(pts)), crashes.size()])
	# park, walk in, take the elevator: on time
	car.speed = 0.0
	car.velocity = Vector3.ZERO
	car.simulate = false
	w.leave_street()
	if not await _wait(func(): return m.arrived.has(1), 3.0) or float(m.arrived[1]) != 0.0:
		_done(false, "arrival not counted as on time (%s)" % str(m.arrived))
		return
	_say("made it in on time (%d s to spare)" % int(m.time_left))
	m.ledger.get_acct(0).balance = 1_000_000.0          # no trades today: don't let the run bust
	m.time_left = 0.5
	if not await _wait(func(): return m.phase == "trading", 5.0):
		_done(false, "the bell never rang")
		return
	if m.is_late(1):
		_done(false, "on time but marked late")
		return
	# day 2: overslept
	m.ledger.get_acct(0).balance = 1_000_000.0
	m.time_left = 0.5
	if not await _wait(func(): return m.phase == "intermission", 5.0):
		_done(false, "day 1 didn't end")
		return
	Config.cli["oversleep"] = 4.0
	m.request_start()
	if not await _wait(func(): return m.phase == "morning", 5.0):
		_done(false, "no day 2 morning")
		return
	await get_tree().process_frame
	if not w.hud.busy():
		_done(false, "overslept but not asleep (late %s)" % str(m.late))
		return
	if not await _wait(func(): return not w.hud.busy(), 8.0):
		_done(false, "never woke up")
		return
	_say("day 2: overslept 4 s (black screen, can't move), then the alarm")
	m.time_left = 0.5
	if not await _wait(func(): return m.phase == "trading", 5.0):
		_done(false, "the day 2 bell never rang")
		return
	if not m.is_late(1):
		_done(false, "missed the bell but not marked late")
		return
	await get_tree().create_timer(1.5).timeout
	w.leave_street()
	if not await _wait(func(): return m.arrived.has(1), 3.0) or float(m.arrived[1]) <= 0.5 or m.is_late(1):
		_done(false, "late arrival not counted (%s)" % str(m.arrived))
		return
	_done(true, "home -> highway -> office on time (%.0f s drive, %d s commute), overslept day 2, walked in %.1f s late" % [
			t * 3.0, int(start_bell), float(m.arrived[1])])


func _route_len(pts: PackedVector3Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += pts[i].distance_to(pts[i - 1])
	return l
