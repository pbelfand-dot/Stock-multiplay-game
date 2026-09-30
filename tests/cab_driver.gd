extends Node
## Cabs drive you there (CabRide): call one from the Magnolia Heights stand to
## BEMZE, from BEMZE downtown, from downtown home; then from downtown to each
## dealership round the loop in turn (MERCEDEZ BANZ, PORSHA, AUDY). The cab
## really drives the whole way (no "shortcut" skip), you're in the back the
## whole time, you get out at the destination and the cab leaves. Then "let
## me out here" (E) and SPACE (skip).
##   godot --headless --path . -- --cabcheck --host --autostart --commute=0 --day_seconds=1800
##   (a long day: the rides take ~6 game minutes and the closing bell's summary would block E)

var w
var m


func _ready() -> void:
	_run.call_deferred()


func _say(s: String) -> void:
	print("[cab] ", s)


func _done(ok: bool, why := "") -> void:
	Engine.time_scale = 1.0
	_say(("CAB PASS " if ok else "CAB FAIL: ") + why)
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
	get_tree().create_timer(900.0).timeout.connect(func(): _done(false, "global timeout"))
	if not await _wait(func(): return get_node_or_null("/root/Main/World/Match") != null, 30.0):
		_done(false, "no match")
		return
	m = get_node("/root/Main/World/Match")
	w = m.world
	if not await _wait(func(): return m.phase == "trading" and w.local_player != null and w.cab != null, 30.0):
		_done(false, "no trading day / no cabs (phase %s)" % m.phase)
		return
	await get_tree().create_timer(1.0).timeout
	var p = w.local_player
	var hb = w.builder.hood
	var lot: Vector3 = hb.hw.dealership_lot
	var lobby: Vector3 = w.builder.street.lobby_exit
	var home: Dictionary = w.home_of(Net.my_id())
	var stand: Vector3 = hb.taxi[1].pos
	p.teleport(stand)
	await get_tree().create_timer(0.3).timeout
	Engine.time_scale = 3.0
	for leg in [["dealer", lot, 45.0], ["downtown", lobby, 25.0], ["home", home.get("drive", Vector3.ZERO), 30.0]]:
		if not await _leg(p, leg[0], leg[1], leg[2]):
			return
	# the dealerships round the loop, eastbound all the way: downtown -> MERCEDEZ BANZ ->
	# PORSHA -> AUDY, driven for real; from there a cab would take us on round the loop
	p.teleport(hb.taxi[0].pos)
	await get_tree().create_timer(0.5).timeout
	for dl in hb.hw.loop_dealers():
		if not await _leg(p, dl.brand, dl.stop, 25.0):
			return
	for back in ["home", "downtown", "dealer"]:
		if w.cab.plan(back).size() < 50:
			_done(false, "no cab from %s to %s" % [w.cab.where_am_i(), back])
			return
	_say("from %s: cabs home, downtown and to BEMZE planned (round the loop, through the tunnel)" % w.cab.where_am_i())
	p.teleport(home.get("drive", Vector3.ZERO) + Vector3(0, 0.3, 0))
	await get_tree().create_timer(0.5).timeout
	# "let me out here": E once it's rolling
	if not w.hood.ride("dealer"):
		_done(false, "no cab from home to BEMZE")
		return
	await get_tree().create_timer(2.0).timeout
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	if not await _wait(func(): return not w.cab.active, 15.0):
		_done(false, "E didn't stop the cab (stopping %s, speed %.1f, at %s, from %s)" % [w.cab._stopping,
				w.cab.cab.speed if w.cab.cab else -1.0, w.cab.cab.global_position if w.cab.cab else Vector3.ZERO, w.cab.where_am_i()])
		return
	if p.global_position.distance_to(lot) < 60.0 or p.riding != null:
		_done(false, "\"let me out here\" still took us to BEMZE")
		return
	_say("E: the cab pulled over and let us out on the way (%.0f m driven)" % w.cab.driven)
	# SPACE: skip to the end
	if not w.hood.ride("dealer"):
		_done(false, "no second cab to BEMZE")
		return
	await get_tree().create_timer(0.5).timeout
	var sp := InputEventAction.new()
	sp.action = "jump"
	sp.pressed = true
	Input.parse_input_event(sp)
	if not await _wait(func(): return not w.cab.active, 5.0) or not w.cab.skipped:
		_done(false, "SPACE didn't skip the ride")
		return
	if p.global_position.distance_to(lot) > 45.0:
		_done(false, "skipped, but ended %.0f m from BEMZE" % p.global_position.distance_to(lot))
		return
	_say("SPACE: skipped straight to BEMZE")
	_done(true, "hood -> BEMZE -> downtown -> home, downtown -> Mercedez Banz -> Porsha -> Audy driven for real, get out early, skip")


## One ride, driven all the way: call the cab to `to`, sit in the back, get out within `tol` of `at`.
func _leg(p, to: String, at: Vector3, tol: float) -> bool:
	var from: String = w.cab.where_am_i()
	if not w.hood.ride(to):
		_done(false, "no cab from %s to %s" % [from, to])
		return false
	if not w.cab.active or p.riding == null:
		_done(false, "the cab didn't come / we're not in it (%s -> %s)" % [from, to])
		return false
	var L := 0.0
	for i in w.cab.path.size() - 1:
		L += w.cab.path[i].distance_to(w.cab.path[i + 1])
	var t0 := Time.get_ticks_msec()
	var in_back := true
	var last_at := Vector3.ZERO
	while w.cab.active and (Time.get_ticks_msec() - t0) < 150000:
		await get_tree().physics_frame
		var c = w.cab.cab
		if c != null and is_instance_valid(c):
			last_at = c.global_position
		if c != null and is_instance_valid(c) and p.global_position.distance_to(c.global_position) > 3.0:
			in_back = false
	var game_s := (Time.get_ticks_msec() - t0) / 1000.0 * Engine.time_scale
	if w.cab.active:
		_done(false, "%s -> %s: still driving after %.0f s (cab at %s)" % [from, to, game_s, w.cab.cab.global_position])
		return false
	if w.cab.skipped or w.cab.driven < L * 0.8:
		_done(false, "%s -> %s: the cab didn't drive it (drove %.0f of %.0f m, skipped %s, last at %s)" % [from, to, w.cab.driven, L, w.cab.skipped, last_at])
		return false
	if not in_back or p.riding != null:
		_done(false, "%s -> %s: we weren't in the back the whole ride / still in the cab" % [from, to])
		return false
	var off: float = Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length()
	if off > tol:
		_done(false, "%s -> %s: dropped %.0f m from it at %s" % [from, to, off, p.global_position])
		return false
	if w.cabs.has(Net.my_id()):
		_done(false, "the cab stayed after the ride")
		return false
	_say("%s -> %s: drove %.0f m in %.0f s (game), out %.0f m from the door" % [from, to, w.cab.driven, game_s, off])
	await get_tree().create_timer(0.5).timeout
	return true
