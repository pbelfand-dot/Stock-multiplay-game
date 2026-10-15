extends SceneTree
## The start-up (EngineSound.start_up: the owner's recordings, assets/sfx/vehicle/), in the real
## menu and on a real stage, on a throwaway save:
##   * the garage: DRIVE THIS ONE on the car grid shuts the door and starts the car on the spot
##     (the starter, then its engine up), which idles and then fades out and goes; an electric car
##     (the STROMER 4) the door and no starter; the garage panel's DRIVE THIS ONE does the same
##   * a stage: silent while the loading screen's up (the engine off), then once it's gone the door
##     (from inside in the seat view) and the starter, the engine full up a moment later
##   * no engine or script errors
## Run: godot --headless --path . -s tests/start_up_check.gd -- --profile=/tmp/some.cfg (a save it wipes)
## Prints [startup] lines; exits 1 on any FAIL.

const CarGrid = preload("res://scripts/ui/car_grid.gd")
const GaragePanel = preload("res://scripts/ui/garage_panel.gd")
const LoadingScreen = preload("res://scripts/ui/loading_screen.gd")
const EngineSound = preload("res://scripts/vehicle/engine_sound.gd")
const Profile = preload("res://scripts/game/profile.gd")

var fails := 0
var main
var errors := ErrorLog.new()


class ErrorLog extends Logger:
	var lines: Array = []
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		lines.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> Array:
		_lock.lock()
		var out := lines.duplicate()
		lines.clear()
		_lock.unlock()
		return out


func _initialize() -> void:
	if Profile.path() == "user://profile.cfg":
		print("[startup] FAIL needs -- --profile=/some/throwaway.cfg (it wipes the save)")
		print("[startup] STARTUP FAIL (1)")
		quit(1)
		return
	Profile.reset()
	Profile.save()
	OS.add_logger(errors)
	await _run()
	if main:
		main.queue_free()
		await _frames(3)
	OS.remove_logger(errors)
	print("[startup] %s" % ("STARTUP OK" if fails == 0 else "STARTUP FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func check(ok: bool, what: String) -> void:
	print("[startup] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var up := await _until(func(): return main.menu != null and main.menu.backdrop != null and main.menu.backdrop.built, 60.0)
	check(up, "the home screen and its garage came up")
	if not up:
		return
	var menu = main.menu
	var g = menu.backdrop
	errors.take()
	menu._show("cars")
	await _frames(4)
	var p = menu._open
	check(p != null and p.get_script() == CarGrid, "CARS: the car grid")
	if p == null or p.get_script() != CarGrid:
		return
	# a car with an engine: DRIVE THIS ONE
	p._pick("kaiser")
	await _frames(2)
	p._go()
	var e = _garage_engine(g)
	check(e != null and e.level == 0.0 and e.starting, "DRIVE THIS ONE: the car on the spot gets its start-up (engine off till it fires)")
	if e == null:
		return
	await _until(func(): return _level(g) >= 1.0, 3.0)
	e = _garage_engine(g)
	check(e != null and e.doors == 1 and e.starts == 1 and e.level >= 1.0,
		"... the door, the starter, then its engine full up (doors %d, starters %d)" % [e.doors if e else -1, e.starts if e else -1])
	var gone := await _until(func(): return _garage_engine(g) == null, g.GARAGE_IDLE + 4.0)
	check(gone, "... it idles %.1f s, then fades out and goes" % g.GARAGE_IDLE)
	await _frames(2)
	# an electric car: the door, no starter
	p._pick("stromer")
	await _frames(2)
	p._go()
	await _until(func(): return _level(g) >= 1.0, 3.0)
	var ev = _garage_engine(g)
	check(ev != null and ev.doors == 1 and ev.starts == 0,
		"an electric car (the STROMER 4): the door, no starter (starters %d)" % (ev.starts if ev else -1))
	# the garage panel's DRIVE THIS ONE
	menu._custom = "kaiser"
	menu._show("garage")
	await _frames(4)
	var gp = menu._open
	if gp != null and gp.get_script() == GaragePanel:
		gp._select()
		await _until(func(): return _garage_engine(g) == null or _garage_engine(g).starts > 0, 2.0)
		var ge = _garage_engine(g)
		check(ge != null and ge.doors == 1 and ge.starts == 1, "the garage panel's DRIVE THIS ONE starts it too")
	else:
		check(false, "the garage panel opened")
	_no_errors("the garage")
	# a stage: off while loading, the door and the starter once it shows
	Profile.select_car("kestrel")
	root.get_node("Net").solo()
	var o: Dictionary = main.quick_opts(7)
	o["length"] = 900.0
	main.load_stage(7, 1, o)
	var built := await _until(func(): return main.game != null and main.game.built, 300.0)
	var game = main.game
	check(built and game._engine != null and game._engine.level == 0.0 and not game._engine_started and _count(LoadingScreen) > 0,
		"a stage built behind its loading screen: the engine off, not started")
	if not built:
		return
	await _until(func(): return _count(LoadingScreen) == 0, 10.0)
	var started := await _until(func(): return game._engine_started, 3.0)
	var door := ""
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2500 and (door == "" or game._engine.level < 1.0):
		for c in game._engine.get_children():
			if c is AudioStreamPlayer3D and c.stream and c.stream.resource_path.contains("door_shut"):
				door = c.stream.resource_path.get_file()
		await process_frame
	var want := "door_shut_in_" if game.cam.view == "seat" else "door_shut_out_"
	check(started and game._engine.doors == 1 and door.begins_with(want), "the loading screen gone: the door shuts (%s, the %s view)" % [door, game.cam.view])
	check(game._engine.starts == 1 and game._engine.level >= 1.0, "... the starter, and the engine's full up (level %.2f)" % game._engine.level)
	_no_errors("the stage")


## The garage car's start-up engine (null: none, or on its way out).
func _garage_engine(g):
	var e = g.car.get_node_or_null("GarageEngine") if g.car else null
	return null if e == null or e.is_queued_for_deletion() else e


func _level(g) -> float:
	var e = _garage_engine(g)
	return e.level if e else 1.0


func _no_errors(tag: String) -> void:
	var e := errors.take()
	check(e.is_empty(), "%s: no errors%s" % [tag, "" if e.is_empty() else ": " + " | ".join(e.slice(0, 3))])


func _count(script: Script) -> int:
	var n := 0
	for c in root.find_children("*", "", true, false):
		if c.get_script() == script and not c.is_queued_for_deletion():
			n += 1
	return n


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _until(cond: Callable, limit: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > limit * 1000.0:
			return false
		await process_frame
	return true
