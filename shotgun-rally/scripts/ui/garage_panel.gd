extends PanelContainer
## CARS, the garage. Pick a kind of car (ALL, RALLY, JDM, EURO ... : the registry's
## categories) and flick through them (◀ ▶): what each costs, the real car's numbers,
## how it drives (power, weight, grip, brakes, the drive split), and the one you drive. A car
## you own can be painted (main, accent and stripe colours: free), given a
## livery and wheels (bought once, then yours on any car), a race number,
## upgrades (engine, tyres, brakes: three steps each), and its tyres and setup
## for gravel or tarmac (free; AUTO matches the stage). The car on the garage's spot
## behind the menu (MenuGarage) is the one you're looking at and shows every change as you
## make it; DRIVE THIS ONE (or buying it) makes it yours to drive, saved, and it's the car
## on the spot from then on. A pad's LB / RB flip through the cars too; the button you were
## on keeps the focus as the panel redraws (keys and pads). Everything is in Profile.

signal back
signal changed                      # credits or the car changed: the menu redraws its chips

const UI = preload("res://scripts/ui/ui_kit.gd")
const Catalog = preload("res://scripts/game/catalog.gd")
const Profile = preload("res://scripts/game/profile.gd")
const CarSpecs = preload("res://scripts/vehicle/car_specs.gd")
const VehicleRegistry = preload("res://scripts/game/vehicle_registry.gd")
## The garage's tabs: the registry's categories, in this order (those with cars).
const KINDS := [["", "ALL"], ["rally", "RALLY"], ["jdm", "JDM"], ["euro", "EURO"], ["american", "AMERICAN"],
	["hyper", "HYPER"], ["race", "RACE"]]

var backdrop
var _i := 0
var _kind := ""
var _tab := "paint"
var _body: VBoxContainer
var _note: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.panel_skin("rally"))
	custom_minimum_size = Vector2(720, 0)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 7)
	add_child(_body)
	for k in Catalog.CARS.size():
		if Catalog.CARS[k].id == Profile.car:
			_i = k
	_tab = get_node("/root/Config").arg("garage_tab", _tab)      # (pictures: --garage_tab=setup)
	_rebuild()
	_first_focus.call_deferred()


## Opened from the home screen with keys or a pad: start on ▶ (or DRIVE THIS ONE).
func _first_focus() -> void:
	if not is_inside_tree() or get_viewport().gui_get_focus_owner() != null:
		return
	var buttons := _buttons()
	if buttons.size() > 1:
		(buttons[1] as Button).grab_focus()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventJoypadButton and e.pressed:
		match (e as InputEventJoypadButton).button_index:
			JOY_BUTTON_LEFT_SHOULDER:
				_flip(-1)
				get_viewport().set_input_as_handled()
			JOY_BUTTON_RIGHT_SHOULDER:
				_flip(1)
				get_viewport().set_input_as_handled()


## The panel's buttons, top to bottom.
func _buttons() -> Array:
	return _body.find_children("*", "Button", true, false)


func _car() -> Dictionary:
	return Catalog.CARS[_i]


## The cars on the tab picked (their places in Catalog.CARS).
func _shown() -> Array:
	var out := []
	for k in Catalog.CARS.size():
		if _kind == "" or str(Catalog.CARS[k].get("category", "")) == _kind:
			out.append(k)
	return out


func _rebuild() -> void:
	# the button in focus (keys, a pad): the same one gets it back once the panel's redrawn
	var had := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focus_at := -1
	var focus_text := ""
	if had is Button and is_ancestor_of(had):
		focus_at = _buttons().find(had)
		focus_text = (had as Button).text
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var car := _car()
	var owned := Profile.owns("cars", car.id)
	var setup := Profile.setup_for(car.id)
	if backdrop:
		backdrop.show_car(setup)
	# ◀ name ▶
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.add_child(UI.label("GARAGE", 40, UI.CREAM, true))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(UI.button("◀", _flip.bind(-1), 24, 52))
	var name := UI.label(car.name, 30, UI.YELLOW, true)
	name.custom_minimum_size = Vector2(250, 0)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(name)
	head.add_child(UI.button("▶", _flip.bind(1), 24, 52))
	_body.add_child(head)
	# the kinds of car: a tab each (those the garage has)
	var kinds := HBoxContainer.new()
	kinds.add_theme_constant_override("separation", 6)
	for kd in KINDS:
		if kd[0] != "" and not Catalog.CARS.any(func(c): return str(c.get("category", "")) == kd[0]):
			continue
		var kb := UI.button(kd[1], _pick_kind.bind(kd[0]), 15, 88)
		if kd[0] == _kind:
			UI.mark(kb)
		kinds.add_child(kb)
	_body.add_child(kinds)
	# the real car's numbers (the registry's researched specs), no badges
	var e = VehicleRegistry.entry(car.id)
	var sp: Dictionary = e.get("specs", {}) if e else {}
	if sp.has("power_hp"):
		var hp := "%d hp" % roundi(float(sp.power_hp))
		if sp.get("power_rating"):
			hp += " " + str(sp.power_rating)              # (a 1970 car's: gross, more than the engine gives in the game)
		var bits := [hp, "%s kg" % _money(int(sp.get("weight_kg", 0))), str(sp.get("drivetrain", ""))]
		if sp.get("transmission"):
			bits.append(str(sp.transmission).split(" (")[0])
		var yr = e.get("real", {}).get("year") if e.get("real") else null
		_body.add_child(UI.label(("%d  ·  " % int(yr) if yr else "") + "  ·  ".join(bits), 16, UI.CREAM))
	var blurb := UI.label(car.blurb, 17, UI.DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(676, 0)
	_body.add_child(blurb)
	# how it drives (with its upgrades): its power and weight (its own engine and
	# body: CarSpecs), the grip and brakes its upgrades add, which wheels drive
	var cfg: Resource = CarSpecs.config(str(setup.get("model", "")), float(setup.get("mass", 0.0)))
	var ps := CarSpecs.power_ps(cfg, setup.power)
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 22)
	stats.add_theme_constant_override("v_separation", 6)
	stats.add_child(UI.stat_bar("POWER", sqrt(ps / 1600.0), "%d PS" % roundi(ps), 150.0))
	stats.add_child(UI.stat_bar("WEIGHT", (2600.0 - cfg.mass) / 1700.0, "%d kg" % roundi(cfg.mass), 150.0))
	stats.add_child(UI.stat_bar("GRIP", (setup.grip - 0.94) / 0.18, "%+d %%" % roundi((setup.grip - 1.0) * 100.0), 150.0))
	stats.add_child(UI.stat_bar("BRAKES", (setup.brakes - 0.95) / 0.3, "%+d %%" % roundi((setup.brakes - 1.0) * 100.0), 150.0))
	var front := roundi(setup.drive_front * 100.0)
	var layout := "FRONT-DRIVE" if front >= 100 else ("REAR-DRIVE" if front <= 0 else "%d/%d F/R%s" % [front, 100 - front,
		" slides" if setup.drive_front < 0.25 else ""])
	stats.add_child(UI.stat_bar("DRIVE", 1.0 - setup.drive_front, layout, 150.0))
	_body.add_child(stats)
	# buy / drive it
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 14)
	if not owned:
		var b := UI.button("BUY  ·  %s CR" % _money(car.price), _buy_car, 24, 320)
		b.disabled = Profile.credits < car.price
		act.add_child(b)
		if b.disabled:
			act.add_child(UI.label("Need %s more: finish stages to earn credits." % _money(car.price - Profile.credits), 17, UI.DIM))
	elif Profile.car == car.id:
		act.add_child(UI.label("✓  THE CAR YOU DRIVE", 24, Color(0.5, 1.0, 0.5), true))
	else:
		act.add_child(UI.button("DRIVE THIS ONE", _select, 24, 320))
	_body.add_child(act)
	if owned:
		var tabs := HBoxContainer.new()
		tabs.add_theme_constant_override("separation", 8)
		for t in [["paint", "PAINT"], ["livery", "LIVERY"], ["wheels", "WHEELS"], ["number", "NUMBER"], ["upgrades", "UPGRADES"], ["setup", "SETUP"]]:
			var tb := UI.button(t[1], func(): _tab = t[0]; _rebuild(), 18, 104)
			if t[0] == _tab:
				UI.mark(tb)
			tabs.add_child(tb)
		_body.add_child(tabs)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 8)
		content.custom_minimum_size = Vector2(0, 120)
		_body.add_child(content)
		match _tab:
			"paint": _paint(content, setup)
			"livery": _liveries(content, setup)
			"wheels": _wheels(content, setup)
			"number": _number(content, setup)
			"upgrades": _upgrades(content)
			"setup": _tuning(content, setup)
	else:
		_body.add_child(UI.label("Buy it to paint it and upgrade it. This is how it comes.", 18, UI.DIM))
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	bottom.add_child(UI.button("BACK", func(): back.emit(), 20, 140))
	_note = UI.label("", 18, UI.YELLOW)
	bottom.add_child(_note)
	_body.add_child(bottom)
	if focus_at >= 0:
		_refocus(focus_at, focus_text)


## After a redraw: focus the button with the same words in the same place, else one with
## the same words, else the one in the same place.
func _refocus(at: int, text: String) -> void:
	var buttons := _buttons()
	if buttons.is_empty():
		return
	var pick: Button = null
	if at < buttons.size() and (buttons[at] as Button).text == text:
		pick = buttons[at]
	if pick == null:
		for b in buttons:
			if (b as Button).text == text and text != "":
				pick = b
				break
	if pick == null:
		pick = buttons[mini(at, buttons.size() - 1)]
	pick.grab_focus()


func _flip(d: int) -> void:
	var shown := _shown()
	var at := shown.find(_i)
	_i = shown[posmod(at + d, shown.size())] if at >= 0 else shown[0]
	_rebuild()


func _pick_kind(kind: String) -> void:
	_kind = kind
	var shown := _shown()
	if not shown.has(_i):
		_i = shown[0]
	_rebuild()


func _buy_car() -> void:
	var car := _car()
	if Profile.buy("cars", car.id, car.price):
		Profile.select_car(car.id)
		changed.emit()
		_rebuild()
		_note.text = "%s is yours. It's the car you drive now." % car.name


func _select() -> void:
	Profile.select_car(_car().id)
	changed.emit()
	_rebuild()


# ── tabs ──────────────────────────────────────────────────────────────────

func _paint(box: VBoxContainer, setup: Dictionary) -> void:
	var cols: Array = []
	for c in Catalog.COLOURS:
		cols.append(c[1])
	for slot in [[0, "MAIN"], [1, "ACCENT"], [2, "STRIPE"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var l := UI.label(slot[1], 18, UI.DIM)
		l.custom_minimum_size = Vector2(84, 0)
		row.add_child(l)
		row.add_child(UI.swatches(cols, setup.colours[slot[0]], func(k: int):
			var now: Array = setup.colours.duplicate()
			now[slot[0]] = cols[k]
			Profile.set_paint(_car().id, "colours", now)
			_rebuild()))
		box.add_child(row)
	var reset := UI.button("FACTORY COLOURS", func():
		Profile.set_paint(_car().id, "colours", _car().colours.duplicate())
		_rebuild(), 16, 200)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(reset)


func _liveries(box: VBoxContainer, setup: Dictionary) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	for l in Catalog.LIVERIES:
		var mine := Profile.owns("liveries", l.id, _car().id)
		var tag := "IN USE" if setup.livery == l.id else ("" if mine else "%s CR" % _money(l.price))
		var name: String = l.name
		if l.id == _car().livery:
			name += " (ITS OWN)"
		var b := UI.button("%s   %s" % [name, tag], _livery.bind(l), 18, 330)
		b.disabled = not mine and Profile.credits < l.price
		grid.add_child(b)
	box.add_child(grid)


func _livery(l: Dictionary) -> void:
	if not Profile.owns("liveries", l.id, _car().id):
		if not Profile.buy("liveries", l.id, l.price):
			return
		changed.emit()
	Profile.set_paint(_car().id, "livery", l.id)
	_rebuild()


func _wheels(box: VBoxContainer, setup: Dictionary) -> void:
	for w in Catalog.WHEELS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var chip := ColorRect.new()
		chip.color = w.colour
		chip.custom_minimum_size = Vector2(34, 34)
		row.add_child(chip)
		var mine := Profile.owns("wheels", w.id)
		var tag := "ON THE CAR" if setup.wheels == w.id else ("" if mine else "%s CR" % _money(w.price))
		var b := UI.button("%s   %s" % [w.name, tag], _wheel.bind(w), 18, 300)
		b.disabled = not mine and Profile.credits < w.price
		row.add_child(b)
		box.add_child(row)


func _wheel(w: Dictionary) -> void:
	if not Profile.owns("wheels", w.id):
		if not Profile.buy("wheels", w.id, w.price):
			return
		changed.emit()
	Profile.set_paint(_car().id, "wheels", w.id)
	_rebuild()


func _number(box: VBoxContainer, setup: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.add_child(UI.button("−", _bump.bind(-1, setup.number), 30, 70))
	var n := UI.label(str(setup.number), 64, UI.CREAM, true)
	n.custom_minimum_size = Vector2(120, 0)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(n)
	row.add_child(UI.button("+", _bump.bind(1, setup.number), 30, 70))
	box.add_child(row)
	box.add_child(UI.label("On both front doors, black on a white roundel. 1 to 99.", 17, UI.DIM))


func _bump(d: int, now: int) -> void:
	Profile.set_paint(_car().id, "number", posmod(now - 1 + d, 99) + 1)
	_rebuild()


## The tyres and the setup (free): each a button that steps through AUTO, GRAVEL,
## TARMAC, with what the choice does.
func _tuning(box: VBoxContainer, setup: Dictionary) -> void:
	for key in Catalog.TUNING:
		var t: Dictionary = Catalog.TUNING[key]
		var choices: Array = t.choices
		var at := maxi(0, choices.map(func(c): return c[0]).find(str(setup.get(key, "auto"))))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var l := UI.label(t.name, 22, UI.CREAM, true)
		l.custom_minimum_size = Vector2(90, 0)
		row.add_child(l)
		row.add_child(UI.button(choices[at][1], func():
			Profile.set_tuning(_car().id, key, choices[(at + 1) % choices.size()][0])
			_rebuild(), 18, 130))
		var what := UI.label(choices[at][2], 15, UI.DIM)
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		what.custom_minimum_size = Vector2(420, 0)
		row.add_child(what)
		box.add_child(row)


func _upgrades(box: VBoxContainer) -> void:
	for part in Catalog.UPGRADES:
		var u: Dictionary = Catalog.UPGRADES[part]
		var lvl := Profile.level(_car().id, part)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var l := UI.label(u.name, 22, UI.CREAM, true)
		l.custom_minimum_size = Vector2(110, 0)
		row.add_child(l)
		row.add_child(UI.label("●".repeat(lvl) + "○".repeat(3 - lvl), 24, UI.YELLOW))
		var now := "+%d %% %s" % [roundi(u.add[lvl - 1] * 100.0), u.stat] if lvl > 0 else "stock"
		var nl := UI.label(now, 18, UI.DIM)
		nl.custom_minimum_size = Vector2(130, 0)
		row.add_child(nl)
		if lvl < 3:
			var price: int = u.prices[lvl]
			var b := UI.button("STEP %d  ·  %s CR" % [lvl + 1, _money(price)], _upgrade.bind(part), 18, 230)
			b.disabled = Profile.credits < price
			row.add_child(b)
		else:
			row.add_child(UI.label("MAXED", 18, Color(0.5, 1.0, 0.5), true))
		box.add_child(row)


func _upgrade(part: String) -> void:
	if Profile.upgrade(_car().id, part):
		changed.emit()
		_rebuild()


static func _money(n: int) -> String:
	var t := str(absi(n))
	var out := ""
	while t.length() > 3:
		out = "," + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return t + out
