extends SceneTree
## The garage behind the home screen (scripts/ui/menu_garage.gd), headless, on a throwaway
## save, driven as a player would (keys, a pad's shoulder button, clicks):
##   * the menu comes up with the garage behind it (not the old stage), quickly: the room's
##     meshes and furniture, and the save's car parked on the spot, standing on the floor;
##     the cover over the menu fades once it's ready
##   * CARS: the camera goes to the showroom orbit; ▶ (ENTER on it) and RB swap the car on
##     the spot for the next one's own model, and ▶ keeps the focus as the panel redraws;
##     DRIVE THIS ONE makes it the car you drive, in Profile and in the save file; BACK (ESC)
##     leaves it on the spot, and a fresh menu with the save read again (the next launch)
##     parks it there
##   * the camera: the home loop and the CARS orbit sampled all the way round, and the real
##     camera through switches between them: inside the room, 0.3 m clear of every piece of
##     furniture and of the biggest car in the garage, the car in front of it
##   * no engine or script errors
## Run: godot --headless --path . -s tests/menu_garage_check.gd -- --profile=/tmp/some.cfg (a save it wipes)
## Prints [garage] lines; exits 1 on any FAIL.

const MenuGarage = preload("res://scripts/ui/menu_garage.gd")
const GarageRoom = preload("res://scripts/ui/garage_room.gd")
const GaragePanel = preload("res://scripts/ui/garage_panel.gd")
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
	check(p != null and p.get_script() == GaragePanel and g.showroom, "CARS opens the garage panel, the camera to the showroom")
	if p == null or p.get_script() != GaragePanel:
		return
	var next: Button = p._buttons()[1]
	check(root.gui_get_focus_owner() == next and next.text == "▶", "keys and pads start on ▶")
	# ▶ with ENTER: the next car on the spot (its setup: paint, livery, wheels); ▶ keeps the focus
	next.grab_focus()
	await _key(KEY_ENTER)
	await _frames(3)
	var shown: Dictionary = p._car()
	var focus := root.gui_get_focus_owner()
	check(shown.id != Profile.car and g.car.setup == Profile.setup_for(shown.id) and g.car.model_id == str(shown.get("model", "")),
		"▶ puts the next car on the spot: %s" % shown.id)
	check(focus is Button and (focus as Button).text == "▶", "▶ still has the focus after the panel redrew")
	# a pad's RB: the one after
	var was: String = shown.id
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb.pressed = true
	root.push_input(rb)
	await _frames(3)
	shown = p._car()
	check(shown.id != was and g.car.setup == Profile.setup_for(shown.id), "a pad's RB flips to the one after: %s" % shown.id)
	# from the car before the STROMER 4 (owned from the start, a body of its own), ▶ swaps the body
	var at := -1
	for k in Catalog.CARS.size():
		if Catalog.CARS[k].id == "stromer":
			at = k
	var prev: Dictionary = Catalog.CARS[posmod(at - 1, Catalog.CARS.size())]
	p._i = posmod(at - 1, Catalog.CARS.size())
	p._rebuild()
	await _frames(2)
	var before: String = g.car.model_id
	(p._buttons()[1] as Button).grab_focus()
	await _key(KEY_ENTER)
	await _frames(3)
	var want := str(Catalog.car("stromer").get("model", ""))
	check(p._car().id == "stromer" and g.car.model_id == want and want != before and g.car.body_model.visible,
		"▶ from the %s swaps the body on the spot for the STROMER 4's ('%s' -> '%s')" % [prev.id, before, g.car.model_id])
	var drive := _button(p, "DRIVE THIS ONE")
	check(drive != null, "DRIVE THIS ONE offered (it's owned)")
	if drive == null:
		return
	await _click(drive)
	await _frames(2)
	var cf := ConfigFile.new()
	cf.load(Profile.path())
	check(Profile.car == "stromer" and str(cf.get_value("garage", "car", "")) == "stromer",
		"DRIVE THIS ONE: it's the car you drive (Profile: %s, the save file: %s)" % [Profile.car, cf.get_value("garage", "car", "")])
	await _key(KEY_ESCAPE)
	await _frames(4)
	check(menu._open == null and not g.showroom, "ESC closes CARS, the camera back on the home loop")
	_check_parked(g, Profile.setup_for("stromer"), "the STROMER 4, back on the home screen,")


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
		Input.parse_input_event(k)
		if DisplayServer.get_name() == "headless":
			root.push_input(k)                                    # (no window here to hand it on)
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
