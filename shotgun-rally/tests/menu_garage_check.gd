extends SceneTree
## The garage behind the home screen (scripts/ui/menu_garage.gd), headless, on a throwaway
## save, driven as a player would (keys, a pad's shoulder button, clicks):
##   * the menu comes up with the garage behind it (not the old stage), quickly: the room's
##     meshes and furniture, and the save's car parked on the spot, standing on the floor;
##     the cover over the menu fades once it's ready
##   * CARS: the grid of every car (five columns, a picture on each tile) and the camera to the
##     showroom orbit; the arrows go from column to column; ENTER on a tile puts that car's own
##     model on the spot, ENTER again makes it the car you drive (Profile and the save file);
##     CUSTOMISE opens the garage on it, where ▶ swaps the car on the spot and keeps the focus,
##     ESC back to the grid; ESC again leaves it on the spot, and a fresh menu with the save
##     read again (the next launch) parks it there
##   * the camera: the home loop and the CARS orbit sampled all the way round, and the real
##     camera through switches between them: inside the room, 0.3 m clear of every piece of
##     furniture and of the biggest car in the garage, the car in front of it
##   * no engine or script errors
## Run: godot --headless --path . -s tests/menu_garage_check.gd -- --profile=/tmp/some.cfg (a save it wipes)
## Prints [garage] lines; exits 1 on any FAIL.

const MenuGarage = preload("res://scripts/ui/menu_garage.gd")
const GarageRoom = preload("res://scripts/ui/garage_room.gd")
const GaragePanel = preload("res://scripts/ui/garage_panel.gd")
const CarGrid = preload("res://scripts/ui/car_grid.gd")
const CarColumns = preload("res://scripts/game/car_columns.gd")
const Profile = preload("res://scripts/game/profile.gd")
const Catalog = preload("res://scripts/game/catalog.gd")
const CarSpecs = preload("res://scripts/vehicle/car_specs.gd")
const CLEAR := 0.3                   # m the camera keeps from the furniture and the car

var fails := 0
var main
var errors := ErrorLog.new()


## Counts the engine's and the scripts' errors (warnings aside).
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
		print("[garage] FAIL needs -- --profile=/some/throwaway.cfg (it wipes the save)")
		print("[garage] GARAGE FAIL (1)")
		quit(1)
		return
	Profile.reset()                                               # a new save: the rally car, the STROMER 4
	Profile.save()
	OS.add_logger(errors)
	await _run()
	if main:
		main.queue_free()
		await _frames(3)
	OS.remove_logger(errors)
	print("[garage] %s" % ("GARAGE OK" if fails == 0 else "GARAGE FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func check(ok: bool, what: String) -> void:
	print("[garage] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _run() -> void:
	# the home screen comes up, the garage behind it
	var t0 := Time.get_ticks_msec()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var up := await _until(func(): return main.menu != null and main.menu.backdrop != null and main.menu.backdrop.built, 60.0)
	var menu = main.menu
	var g = menu.backdrop if menu else null
	check(up and g != null and g.get_script() == MenuGarage, "the home screen's backdrop is the garage")
	if not up or g == null or g.get_script() != MenuGarage:
		return
	var ms := Time.get_ticks_msec() - t0
	check(ms < 8000, "ready %d ms after the menu was made (the room and the car: %d ms; %d triangles in the room)" % [ms, g.build_ms, g.room.triangles()])
	_check_room(g)
	_check_parked(g, Profile.setup(), "the save's car (%s)" % Profile.car)
	await _until(func(): return not menu._cover.visible, 3.0)
	check(not menu._cover.visible, "the cover over the menu faded once the garage was ready")
	_no_errors("the home screen")
	_check_paths(g)
	_check_live_camera(g)
	_no_errors("the camera")
	await _cars(menu, g)
	_no_errors("CARS")
	await _modes_pick(menu)
	_no_errors("MODES")
	await _next_launch()
	_no_errors("the next launch")


func _check_room(g) -> void:
	var room: Node3D = g.get_node_or_null("Room")
	var meshes: Array = room.find_children("*", "MeshInstance3D", false, false) if room else []
	check(meshes.size() >= 20, "the room's built: %d meshes (one a material)" % meshes.size())
	var names: Array = g.room.props.map(func(p): return p.name)
	var want := ["door", "light box", "helmet shelf", "seat", "tyre rack A", "tyre rack B", "cabinets", "lift", "tool chest",
		"detailing", "workbench", "personnel door"]
	var missing := want.filter(func(n): return not n in names)
	check(missing.is_empty(), "its furniture is all there%s" % ("" if missing.is_empty() else ": missing " + ", ".join(missing)))
	# every piece inside the room, standing on the floor or hung from the walls / ceiling
	var out := []
	var room_box := AABB(Vector3(-GarageRoom.HALF_W, 0.0, -GarageRoom.HALF_D) - Vector3.ONE * 0.01,
		Vector3(GarageRoom.HALF_W * 2.0, GarageRoom.HEIGHT, GarageRoom.HALF_D * 2.0) + Vector3.ONE * 0.02)
	for p in g.room.props:
		if not room_box.encloses(p.box):
			out.append(p.name)
	check(out.is_empty(), "every piece is inside the room%s" % ("" if out.is_empty() else ": not " + ", ".join(out)))


## The car on the spot: the setup's own model, its wheels on the floor, under the light box.
func _check_parked(g, setup: Dictionary, what: String) -> void:
	var car = g.car
	var want := str(setup.get("model", ""))
	var on_spot: bool = Vector2(car.global_position.x, car.global_position.z).distance_to(Vector2(MenuGarage.SPOT.x, MenuGarage.SPOT.z)) < 0.05
	var box: AABB = g.car_box()
	var under := GarageRoom.LIGHT_BOX
	var lit: bool = absf(box.get_center().x - under.get_center().x) < 0.5 and absf(box.get_center().z - under.get_center().z) < 1.0
	check(car.model_id == want and car.body_model != null and car.body_model.visible and on_spot and lit,
		"%s parked on the spot under the light box (model '%s', at %.2f, %.2f)" % [what, car.model_id, car.global_position.x, car.global_position.z])
	check(box.position.y > -0.06 and box.position.y < 0.08 and box.end.y < 2.4,
		"%s stands on the floor (its lowest point %.3f m, its top %.2f m)" % [what, box.position.y, box.end.y])


## The biggest car in the garage, on the spot (each car's model's measured body; the cars on
## the shared body are smaller): the box the camera has to keep clear of.
func _biggest_car() -> AABB:
	var half_l := 2.2
	var half_w := 0.95
	var top := 1.5
	for c in Catalog.CARS:
		var info: Dictionary = CarSpecs.parts(str(c.get("model", ""))) if c.has("model") else {}
		var lo: Array = info.get("body_min", [])
		var hi: Array = info.get("body_max", [])
		if lo.size() == 3 and hi.size() == 3:
			half_w = maxf(half_w, maxf(-float(lo[0]), float(hi[0])))
			half_l = maxf(half_l, maxf(-float(lo[2]), float(hi[2])))
			top = maxf(top, float(hi[1]))
	var s := MenuGarage.SPOT
	return AABB(Vector3(s.x - half_w, 0.0, s.z - half_l), Vector3(half_w * 2.0, top, half_l * 2.0))


## What's wrong with a camera here ("" if nothing): out of the room, too near the
## furniture or the car, or not looking at the car.
func _camera_problem(g, xf: Transform3D, car: AABB) -> String:
	var p := xf.origin
	var m := CLEAR
	if absf(p.x) > GarageRoom.HALF_W - m or absf(p.z) > GarageRoom.HALF_D - m or p.y < m or p.y > GarageRoom.LIGHT_BOX.position.y - m:
		return "out of the room at %s" % p
	for o in g.room.props:
		var d := _box_distance(o.box, p)
		if d < m:
			return "%.2f m from the %s at %s" % [d, o.name, p]
	var dc := _box_distance(car, p)
	if dc < m + 0.1:
		return "%.2f m from the car at %s" % [dc, p]
	var to := (car.get_center() - p).normalized()
	if to.dot(-xf.basis.z) < cos(deg_to_rad(40.0)):
		return "not looking at the car from %s" % p
	return ""


static func _box_distance(b: AABB, p: Vector3) -> float:
	var q := Vector3(clampf(p.x, b.position.x, b.end.x), clampf(p.y, b.position.y, b.end.y), clampf(p.z, b.position.z, b.end.z))
	return q.distance_to(p)


## The two paths, all the way round (the orbit from a dozen starting angles).
func _check_paths(g) -> void:
	var car := _biggest_car()
	var bad := ""
	var near := INF
	for k in 800:
		var t: float = MenuGarage.HOME_LAP * k / 800.0
		var xf: Transform3D = g._home_xf(t)
		bad = _camera_problem(g, xf, car)
		if bad != "":
			bad = "t %.1f s: %s" % [t, bad]
			break
		near = minf(near, _nearest(g, xf.origin))
	check(bad == "", "the home loop stays in the room, clear of the furniture and the biggest car (%.1f x %.1f m), looking at it%s (nearest furniture %.2f m)"
		% [car.size.x, car.size.z, "" if bad == "" else ": " + bad, near])
	var keep: float = g._phase
	bad = ""
	near = INF
	for start in 12:
		g._phase = TAU * start / 12.0
		for k in 120:
			var xf: Transform3D = g._orbit_xf(MenuGarage.ORBIT_LAP * k / 120.0)
			var b := _camera_problem(g, xf, car)
			if b != "" and bad == "":
				bad = b
			near = minf(near, _nearest(g, xf.origin))
	g._phase = keep
	check(bad == "", "the CARS orbit too%s (nearest furniture %.2f m)" % ["" if bad == "" else ": " + bad, near])


func _nearest(g, p: Vector3) -> float:
	var d := INF
	for o in g.room.props:
		d = minf(d, _box_distance(o.box, p))
	return d


## The real camera, stepped through ~10 minutes, CARS opened and closed now and then (the
## move between the paths too).
func _check_live_camera(g) -> void:
	var car := _biggest_car()
	g.set_process(false)
	var bad := ""
	var switches := 0
	var dt := 0.05
	for i in 12000:
		if i % 900 == 450:
			g.set_showroom(not g.showroom)
			switches += 1
		g._process(dt)
		var b := _camera_problem(g, g.cam.global_transform, car)
		if b != "":
			bad = "%.1f s: %s" % [i * dt, b]
			break
	if g.showroom:
		g.set_showroom(false)
	g.set_process(true)
	check(bad == "", "the camera itself, %d switches between the paths in 10 minutes: always in the room and clear%s"
		% [switches, "" if bad == "" else ": " + bad])


# ── CARS ──────────────────────────────────────────────────────────────────

func _cars(menu, g) -> void:
	await _click(_home_button(menu, "CARS"))
	await _frames(6)
	var p = menu._open
	check(p != null and p.get_script() == CarGrid and g.showroom, "CARS opens the car grid, the camera to the showroom")
	if p == null or p.get_script() != CarGrid:
		return
	var pics: int = p._tiles.values().filter(func(t): return (t as Button).icon != null).size()
	check(p._columns.size() == 5 and p._tiles.size() == Catalog.CARS.size() and pics == p._tiles.size(),
		"five columns, a tile with its picture for each of the %d cars (%d pictures)" % [p._tiles.size(), pics])
	var start: Button = p._tiles.get(Profile.car)
	check(root.gui_get_focus_owner() == start, "keys and pads start on the car you drive (%s)" % Profile.car)
	# the arrow keys go from column to column
	await _key(KEY_LEFT)
	await _frames(2)
	var f := root.gui_get_focus_owner()
	check(f is Button and f != start and (f as Button).has_meta("car"), "← moves to a car in the next column (%s)" % (f.get_meta("car") if f and f.has_meta("car") else "?"))
	# the STROMER 4's tile: ENTER puts it on the spot, ENTER again drives it
	var tile: Button = p._tiles["stromer"]
	tile.grab_focus()
	var before: String = g.car.model_id
	await _key(KEY_ENTER)
	await _frames(3)
	var want := str(Catalog.car("stromer").get("model", ""))
	check(p._sel == "stromer" and g.car.setup == Profile.setup_for("stromer") and g.car.model_id == want and g.car.body_model.visible,
		"ENTER on a tile puts that car on the spot: the STROMER 4 ('%s' -> '%s')" % [before, g.car.model_id])
	check(Profile.car != "stromer" or before == want, "...not driven yet")
	await _key(KEY_ENTER)
	await _frames(2)
	var cf := ConfigFile.new()
	cf.load(Profile.path())
	check(Profile.car == "stromer" and str(cf.get_value("garage", "car", "")) == "stromer",
		"ENTER again: it's the car you drive (Profile: %s, the save file: %s)" % [Profile.car, cf.get_value("garage", "car", "")])
	# CUSTOMISE: the garage on that car; ▶ the next one on the spot; BACK to the grid
	await _click(_button(p, "CUSTOMISE"))
	await _frames(4)
	var gp = menu._open
	check(gp != null and gp.get_script() == GaragePanel and gp._car().id == "stromer" and g.showroom, "CUSTOMISE opens the garage on the STROMER 4")
	if gp != null and gp.get_script() == GaragePanel:
		(gp._buttons()[1] as Button).grab_focus()
		await _key(KEY_ENTER)
		await _frames(3)
		var shown: Dictionary = gp._car()
		check(shown.id != "stromer" and g.car.setup == Profile.setup_for(shown.id), "▶ in the garage puts the next car on the spot: %s" % shown.id)
		var focus := root.gui_get_focus_owner()
		check(focus is Button and (focus as Button).text == "▶", "▶ still has the focus after the panel redrew")
		await _key(KEY_ESCAPE)
		await _frames(4)
		check(menu._open != null and menu._open.get_script() == CarGrid and g.showroom, "ESC from the garage goes back to the grid")
	await _key(KEY_ESCAPE)
	await _frames(4)
	check(menu._open == null and not g.showroom, "ESC closes CARS, the camera back on the home loop")
	_check_parked(g, Profile.setup_for("stromer"), "the STROMER 4, back on the home screen,")


## MODES: a touge's START opens the car grid on STREET, only its cars to pick, on the car you drive
## (a street car); ESC goes back to MODES; START IN THIS ONE starts the touge in it.
func _modes_pick(menu) -> void:
	var started := []
	for c in menu.mode.get_connections():
		menu.mode.disconnect(c.callable)                     # (not a real start: the test only hears it)
	menu.mode.connect(func(m): started.append(m))
	await _click(_home_button(menu, "MODES"))
	await _frames(4)
	var go := _button(menu._open, "START  ·  NEW PASS")
	check(go != null, "MODES: the touge's START")
	if go == null:
		return
	await _click(go)
	await _frames(4)
	var p = menu._open
	var ok: bool = p != null and p.get_script() == CarGrid and str(p.mode.get("mode", "")) == "touge"
	check(ok and started.is_empty(), "the touge's START opens the car grid first (not started yet)")
	if not ok:
		return
	var open: Array = p._tiles.keys().filter(func(id): return not (p._tiles[id] as Button).disabled)
	check(open.size() == CarColumns.cars_in("street").size() and open.all(func(id): return CarColumns.column_of(Catalog.car(id)) == "street"),
		"...only its STREET cars to pick (%d of %d)" % [open.size(), p._tiles.size()])
	check(p._sel == Profile.car, "...on the car you drive (a street car: %s)" % Profile.car)
	await _key(KEY_ESCAPE)
	await _frames(4)
	check(menu._open != null and menu._open.get_script().resource_path.ends_with("modes_panel.gd"), "ESC goes back to MODES")
	await _click(_button(menu._open, "START  ·  NEW PASS"))
	await _frames(4)
	await _click(_button(menu._open, "START IN THIS ONE"))
	await _frames(2)
	check(started.size() == 1 and str(started[0].get("mode", "")) == "touge" and Profile.car == "stromer",
		"START IN THIS ONE starts the touge in it (%d started, %s)" % [started.size(), Profile.car])


## The next launch: the save read again from the file, a new menu, the car you chose on the spot.
func _next_launch() -> void:
	main.menu.get_parent().queue_free()
	main.menu = null
	await _frames(2)
	Profile.reset()                                               # (forget it all: as a new run of the game)
	Profile._loaded = false
	Profile.ensure_loaded()
	check(Profile.car == "stromer", "read again from the save, the car you drive is the STROMER 4")
	main.show_menu()
	var up := await _until(func(): return main.menu != null and main.menu.backdrop.built, 60.0)
	check(up, "a new home screen came up")
	if up:
		_check_parked(main.menu.backdrop, Profile.setup(), "next launch: the STROMER 4")


# ── helpers ───────────────────────────────────────────────────────────────

func _home_button(menu, title: String) -> Button:
	for item in menu._home.get_children():
		if item.has_meta("button"):
			for l in item.find_children("*", "Label", true, false):
				if (l as Label).text == title:
					return item.get_meta("button")
	return null


func _button(n: Node, text: String) -> Button:
	for b in n.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


func _click(c: Control) -> void:
	var at := c.get_global_rect().get_center()
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	root.push_input(m, true)
	await process_frame
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		e.position = at
		e.global_position = at
		root.push_input(e, true)
		await process_frame


func _key(code: Key) -> void:
	for down in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = down
		# once: Input hands a parsed event on to the window by itself (headless too), so pushing it
		# as well delivered every key twice (ESC from the garage went back to the grid, then home)
		if DisplayServer.get_name() == "headless":
			root.push_input(k)
		else:
			Input.parse_input_event(k)
		await _frames(2)


func _no_errors(tag: String) -> void:
	var e := errors.take()
	check(e.is_empty(), "%s: no errors%s" % [tag, "" if e.is_empty() else ": " + " | ".join(e.slice(0, 3))])


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
