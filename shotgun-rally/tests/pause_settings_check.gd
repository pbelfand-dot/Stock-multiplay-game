extends SceneTree
## SETTINGS opened again and again, from the main menu and from the pause menu (ESC on
## a stage), driven as a player would: mouse clicks on the real buttons, the mouse
## wheel to scroll down to GRAPHICS, the ESC key. Every time:
##   * the panel opens, and it's the only one (none left over from the time before),
##     its BACK wired once
##   * QUALITY clicked round all four levels in a row, each click the next level (the
##     bug: only the first click after opening did anything), CAR LIGHTS and RENDER
##     SCALE round theirs, TYRE GRIP round its four; on the stage the sun's shadows
##     follow the level at once
##   * the wheel scrolls the page, not the sliders it passes over
##   * closed by BACK or by ESC: the panel's gone. On the stage that's back to the pause
##     menu, still paused (the car held, ESC doesn't resume through the settings), its
##     SETTINGS button in focus; ESC again resumes
##   * ENTER in the settings presses the button in focus, it doesn't start the stage
##     behind them (unpaused, it does)
##   * the home screen's buttons take clicks (the panels' empty holder sat on them)
##   * no engine or script errors
## Whole rounds leave each setting where it was; they're put back at the end anyway
## (the other tests share user://).
## Run: godot --headless --path . -s tests/pause_settings_check.gd [-- --profile=/tmp/some.cfg]
## Prints [pause] lines; exits 1 on any FAIL.

const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")
const GraphicsSettings = preload("res://scripts/ui/graphics_settings.gd")
const LoadingScreen = preload("res://scripts/ui/loading_screen.gd")
const Graphics = preload("res://scripts/render/graphics.gd")
const ROUNDS := 6

var fails := 0
var main
var config
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
	config = root.get_node("Config")
	var keep := _settings_now()
	OS.add_logger(errors)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _menu_rounds()
	await _pause_rounds()
	main.queue_free()                                             # (gone before the quit: nothing left over at exit)
	await _frames(3)
	OS.remove_logger(errors)
	_put_back(keep)
	print("[pause] %s" % ("PAUSE OK" if fails == 0 else "PAUSE FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func check(ok: bool, what: String) -> void:
	print("[pause] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


# ── the main menu ─────────────────────────────────────────────────────────

func _menu_rounds() -> void:
	await _until(func(): return main.menu != null and main.menu.backdrop.built, 120.0)   # (the stage behind it built first)
	var menu = main.menu
	check(menu != null and menu.backdrop.built, "the main menu's up")
	if menu == null:
		return
	errors.take()
	var home := _home_button(menu, "SETTINGS")
	if home == null:
		check(false, "the home screen has SETTINGS")
		return
	for r in ROUNDS:
		await _click(home)
		await _frames(12)                                         # (it slides in)
		var p: Control = menu._open
		check(p != null and p.get_script() == SettingsPanel and not menu._home.visible,
			"menu %d: clicking SETTINGS on the home screen opens it" % (r + 1))
		if p == null or p.get_script() != SettingsPanel:
			return
		await _use_panel("menu %d" % (r + 1), p, null)
		await _close(p, r, "menu %d" % (r + 1))
		check(_count(SettingsPanel) == 0 and menu._open == null and menu._home.visible
			and root.gui_get_focus_owner() == _home_button(menu, "PLAY NOW"),
			"menu %d: closed, the panel's gone, the home buttons back (PLAY NOW in focus)" % (r + 1))
		_no_errors("menu %d" % (r + 1))


func _home_button(menu, title: String) -> Button:
	for item in menu._home.get_children():
		if item.has_meta("button"):
			for l in item.find_children("*", "Label", true, false):
				if (l as Label).text == title:
					return item.get_meta("button")
	return null


# ── the pause menu, on a stage ────────────────────────────────────────────

func _pause_rounds() -> void:
	root.get_node("Net").solo()
	var o: Dictionary = main.quick_opts(7)
	o["length"] = 900.0                                           # (a short stage: quicker to build)
	main.load_stage(7, 1, o)
	await _until(func(): return main.game != null and main.game.built and _count(LoadingScreen) == 0, 300.0)
	var g = main.game
	check(g != null and g.built, "a stage loaded (the menu's gone: %s)" % (main.menu == null))
	if g == null or not g.built:
		return
	errors.take()
	var suns: Array = g.find_children("*", "DirectionalLight3D", true, false).filter(func(s): return s.shadow_enabled)
	for r in ROUNDS:
		var tag := "pause %d" % (r + 1)
		await _esc()
		check(g._pause.visible and g.paused() and _visible(g._pause_settings), "%s: ESC pauses, the pause menu has SETTINGS" % tag)
		await _click(g._pause_settings)
		await _frames(4)
		var p: Control = null
		if g._settings:
			for n in g._settings.get_children():
				if n.get_script() == SettingsPanel:
					p = n
		check(p != null and not g._pause.visible and g.paused(), "%s: clicking SETTINGS opens it over the stage, the pause menu out of the way" % tag)
		if p == null:
			return
		await _frames(2)
		# (paused: no throttle, the brake at 0.4; parked on the grid unpaused it'd be 0.6 and the handbrake)
		var held: bool = float(g.car.inp.get("throttle", 1.0)) == 0.0 and is_equal_approx(float(g.car.inp.get("brake", 0.0)), 0.4)
		check(held and g.paused(), "%s: still paused under it (the car held on the brake)" % tag)
		await _use_panel(tag, p, suns)
		await _close(p, r, tag)
		check(_count(SettingsPanel) == 0 and g._settings == null, "%s: closed, the panel's gone" % tag)
		check(g._pause.visible and g.paused() and root.gui_get_focus_owner() == g._pause_settings,
			"%s: back on the pause menu, still paused, SETTINGS in focus%s" % [tag, " (ESC took it back, didn't resume)" if r % 2 == 1 else ""])
		await _esc()
		check(not g._pause.visible and not g.paused(), "%s: ESC again resumes" % tag)
		check(g._pause_settings.pressed.get_connections().size() == 1, "%s: the pause menu's SETTINGS still wired once" % tag)
		_no_errors(tag)
	# ENTER in the settings presses the button in focus (BACK): not the countdown behind it
	await _esc()
	await _click(g._pause_settings)
	await _frames(4)
	await _key(KEY_ENTER)
	await _frames(6)
	check(g.state == "grid" and g.paused() and g._settings == null,
		"ENTER in the settings presses BACK and doesn't start the stage behind it (still %s, paused)" % g.state)
	await _esc()
	await _key(KEY_ENTER)
	await _frames(6)
	check(not g.paused() and g.state == "countdown", "and unpaused, ENTER starts the countdown (%s)" % g.state)
	_no_errors("ENTER")


# ── in the panel ──────────────────────────────────────────────────────────

## The panel's checks, then its buttons clicked round (back where they started).
## suns: on a stage, the suns whose shadows should follow the level (null: the menu).
func _use_panel(tag: String, p: Control, suns) -> void:
	check(_count(SettingsPanel) == 1 and _count(GraphicsSettings) == 1 and p.back.get_connections().size() == 1,
		"%s: one settings panel, one GRAPHICS in it, BACK wired once" % tag)
	var scroll: ScrollContainer = p.find_children("*", "ScrollContainer", true, false)[0]
	var sliders := _sliders_now()
	var others := _others_now()
	var quality := _row_button(p, "QUALITY")
	if quality == null:
		check(false, "%s: GRAPHICS has its QUALITY button" % tag)
		return
	var steps: Array = [Graphics.level()]
	var ok := await _into_view(scroll, quality)
	var shadows_ok := true
	for k in 4:
		await _click(quality)
		await _frames(2)
		var want: String = Graphics.LEVELS[(Graphics.LEVELS.find(steps[-1]) + 1) % 4]
		ok = ok and Graphics.level() == want and quality.text == want.to_upper()
		steps.append(Graphics.level())
		if suns:
			for s in suns:
				shadows_ok = shadows_ok and is_equal_approx(s.directional_shadow_max_distance, float(Graphics.get_value("shadow_distance")))
	check(ok, "%s: QUALITY clicked 4 times in a row, a new level each time: %s" % [tag, " > ".join(steps)])
	if suns != null:
		check(shadows_ok and not suns.is_empty(), "%s: the stage's sun took each level at once (%d sun%s)" % [tag, suns.size(), "" if suns.size() == 1 else "s"])
	var lit: Array = await _step_round(scroll, _row_button(p, "CAR LIGHTS"), ["auto", "on", "off"],
		func(): return Graphics.car_lights())
	var scales: Array = await _step_round(scroll, _row_button(p, "RENDER SCALE"), [0.0, 1.0, 0.85, 0.7, 0.5],
		func(): return Graphics.render_scale_setting())
	check(lit[0] and scales[0], "%s: CAR LIGHTS and RENDER SCALE step round too (%s; %s)" % [tag, " > ".join(lit[1]), " > ".join(scales[1])])
	var grips: Array = await _step_round(scroll, _row_button(p, "TYRE GRIP  (RALLY)"), [2.0, 1.5, 1.0, 0.0],
		func(): return config.grip_assist)
	check(grips[0], "%s: TYRE GRIP steps round its four (%s)" % [tag, " > ".join(grips[1])])
	check(_sliders_now() == sliders, "%s: the wheel scrolled the page, not the sliders under it" % tag)
	check(_others_now() == others, "%s: nothing else changed (the aids, INVERT MOUSE Y, the other choices)" % tag)


## b scrolled into sight and clicked once per choice: each click the next of keys (read
## back by now()), ending where it began. Returns [ok, what it went through].
func _step_round(scroll: ScrollContainer, b: Button, keys: Array, now: Callable) -> Array:
	if b == null:
		return [false, ["(no button)"]]
	var ok := await _into_view(scroll, b)
	var seen: Array = [now.call()]
	ok = ok and keys.has(seen[0])
	for k in keys.size():
		var want = keys[(keys.find(seen[-1]) + 1) % keys.size()]
		await _click(b)
		seen.append(now.call())
		ok = ok and seen[-1] == want
	return [ok and seen[-1] == seen[0], seen.map(func(x): return str(x))]


## BACK clicked (even rounds) or ESC (odd rounds).
func _close(p: Control, r: int, tag: String) -> void:
	var back := _button(p, ["BACK"])
	if r % 2 == 0:
		await _click(back)
	else:
		await _esc()
	await _frames(3)
	check(not is_instance_valid(p) or p.is_queued_for_deletion() or not p.is_inside_tree(),
		"%s: %s closes it" % [tag, "BACK" if r % 2 == 0 else "ESC"])


## The wheel over the panel's left column until b is all in sight (as the player scrolls
## down to GRAPHICS, or back up to the aids).
func _into_view(scroll: ScrollContainer, b: Control) -> bool:
	var at := scroll.get_global_rect()
	var spot := Vector2(at.position.x + 150.0, at.get_center().y)
	for i in 80:
		var view := scroll.get_global_rect()
		var r := b.get_global_rect()
		if r.position.y >= view.position.y and r.end.y <= view.end.y:
			await _frames(3)
			if b.get_global_rect() == r:                          # (settled: not still gliding)
				return true
			continue
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_DOWN if r.end.y > view.end.y else MOUSE_BUTTON_WHEEL_UP
		e.factor = 1.0
		e.position = spot
		e.global_position = spot
		e.pressed = true
		root.push_input(e, true)
		e = e.duplicate()
		e.pressed = false
		root.push_input(e, true)
		await process_frame
	return false


# ── helpers ───────────────────────────────────────────────────────────────

## A mouse click in the middle of c: the pointer moves there, the left button goes down and up.
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


## The ESC key, down and up (through Input, as the keyboard does: the game asks Input
## for "pause"; the menu gets it as ui_cancel).
func _esc() -> void:
	await _key(KEY_ESCAPE)


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


## The button on the row with this title (the settings' cycles: a label, then the button).
func _row_button(n: Node, title: String) -> Button:
	for l in n.find_children("*", "Label", true, false):
		if (l as Label).text == title:
			for b in l.get_parent().get_children():
				if b is Button:
					return b
	return null


func _button(n: Node, texts: Array) -> Button:
	for b in n.find_children("*", "Button", true, false):
		if (b as Button).text in texts:
			return b
	return null


## Nodes running this script in the tree (not on their way out).
func _count(script: Script) -> int:
	var n := 0
	for c in root.find_children("*", "", true, false):
		if c.get_script() == script and not c.is_queued_for_deletion():
			n += 1
	return n


func _visible(c: Control) -> bool:
	return c != null and c.is_visible_in_tree()


func _sliders_now() -> Array:
	return [config.mouse_sens, config.volume, config.sfx_volume, config.voice_volume, config.call_early, config.time_of_day]


func _others_now() -> Array:
	return [config.aids.duplicate(), config.invert_y, config.street_handling, config.quick_surface, Graphics.renderer()]


func _settings_now() -> Dictionary:
	return {"level": Graphics.level(), "scale": Graphics.render_scale_setting(), "lights": Graphics.car_lights(),
		"grip": config.grip_assist, "sliders": _sliders_now(), "aids": config.aids.duplicate(), "invert": config.invert_y}


func _put_back(keep: Dictionary) -> void:
	Graphics.set_level(keep.level)
	Graphics.set_render_scale(keep.scale)
	Graphics.set_car_lights(keep.lights)
	config.grip_assist = keep.grip
	config.aids = keep.aids
	config.invert_y = keep.invert
	var s: Array = keep.sliders
	config.mouse_sens = s[0]
	config.volume = s[1]
	config.sfx_volume = s[2]
	config.voice_volume = s[3]
	config.call_early = s[4]
	config.time_of_day = s[5]
	config.save()


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
