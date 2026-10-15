extends PanelContainer
## CARS: every car on one grid (the owner's sketch, 2026-10-11): a column for each kind
## (CarColumns: STREET, GT3, F1, RALLY, HYPERCARS), each car a tile with its picture (taken from
## its own 3D model: tools/car_thumbs.gd) and its name. The car picked is the one big and live on
## the garage's spot behind (MenuGarage), its real numbers over the grid. Every car is free (the
## owner's ask): DRIVE THIS ONE makes it the one you drive; CUSTOMISE opens its paint, livery,
## wheels, upgrades and setup (GaragePanel, on that car). Opened for a mode ("mode": the mode's
## options, CarColumns.for_mode), only the cars it takes can be picked (the rest dimmed, its
## column lit) and DRIVE starts it. Keys and pads move from tile to tile; a picked tile pressed
## again drives; a pad's LB / RB jump a column.

signal back
signal changed                      # the car you drive changed: the menu redraws its chips
signal drive(id: String)            # DRIVE: the car to drive (a mode: start it in this one)
signal customise(id: String)        # CUSTOMISE: its paint and parts (GaragePanel)

const UI = preload("res://scripts/ui/ui_kit.gd")
const Catalog = preload("res://scripts/game/catalog.gd")
const Profile = preload("res://scripts/game/profile.gd")
const CarColumns = preload("res://scripts/game/car_columns.gd")
const VehicleRegistry = preload("res://scripts/game/vehicle_registry.gd")

const TILE := Vector2(140, 79)      # a tile's picture (its file is 320 x 180)

var backdrop                        # MenuGarage: the car picked shown live on its spot
var mode := {}                      # opened for a mode: its options ({}: the garage's grid)
var _take := {}                     # CarColumns.for_mode: the column lit, the cars it takes
var _sel := ""
var _tiles := {}                    # car id -> its tile (Button)
var _columns: Array = []            # each column's tiles, left to right
var _name: Label
var _info: Label
var _drive: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.panel_skin("rally", 18))
	custom_minimum_size = Vector2(800, 620)
	_take = CarColumns.for_mode(mode)
	var allowed: Array = _take.ids
	_sel = Profile.car if Profile.car in allowed else (str(allowed[0]) if not allowed.is_empty() else Profile.car)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	# the head: CARS (or what the mode wants), the car picked and its numbers
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	var want := "CARS" if mode.is_empty() else ("PICK A CAR  ·  %s" % _column_title(str(_take.column)) if str(_take.column) != "" else "PICK A CAR")
	head.add_child(UI.label(want, 34, UI.CREAM, true))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_name = UI.label("", 26, UI.YELLOW, true)
	head.add_child(_name)
	v.add_child(head)
	_info = UI.label("", 15, UI.DIM)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_info)
	# the columns
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 6)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for cdef in CarColumns.COLUMNS:
		var ids: Array = CarColumns.cars_in(str(cdef[0]))
		var lit: bool = str(_take.column) == "" or str(_take.column) == str(cdef[0])
		var colv := VBoxContainer.new()
		colv.add_theme_constant_override("separation", 4)
		colv.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var title := UI.label("%s  %d" % [cdef[1], ids.size()], 16, UI.YELLOW if lit else UI.DIM, true)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		colv.add_child(title)
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(TILE.x + 18, 0)
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.follow_focus = true
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 5)
		var tiles: Array = []
		for id in ids:
			var b := _tile(str(id), id in allowed)
			list.add_child(b)
			tiles.append(b)
		_columns.append(tiles)
		sc.add_child(list)
		colv.add_child(sc)
		cols.add_child(colv)
	v.add_child(cols)
	# the actions
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 12)
	_drive = UI.button("DRIVE THIS ONE", _go, 22, 280)
	act.add_child(_drive)
	act.add_child(UI.button("CUSTOMISE", func(): customise.emit(_sel), 20, 190))
	act.add_child(UI.button("BACK", func(): back.emit(), 20, 130))
	v.add_child(act)
	_pick(_sel)
	_first_focus.call_deferred()


func _column_title(col: String) -> String:
	for c in CarColumns.COLUMNS:
		if c[0] == col:
			return str(c[1])
	return ""


## Keys or a pad: start on the car picked.
func _first_focus() -> void:
	if not is_inside_tree():
		return
	var t: Button = _tiles.get(_sel)
	if t and not t.disabled:
		t.grab_focus()
	else:
		_drive.grab_focus()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventJoypadButton and e.pressed:
		match (e as InputEventJoypadButton).button_index:
			JOY_BUTTON_LEFT_SHOULDER:
				_jump(-1)
				get_viewport().set_input_as_handled()
			JOY_BUTTON_RIGHT_SHOULDER:
				_jump(1)
				get_viewport().set_input_as_handled()


## LB / RB: the next column with a car that can be picked, its first such tile focused.
func _jump(d: int) -> void:
	var at := 0
	var f := get_viewport().gui_get_focus_owner()
	for k in _columns.size():
		if f in _columns[k]:
			at = k
	for step in range(1, _columns.size()):
		var k := posmod(at + d * step, _columns.size())
		for t in _columns[k]:
			if not (t as Button).disabled:
				(t as Button).grab_focus()
				return


## A car's tile: its picture over its name; dimmed when the mode doesn't take it.
func _tile(id: String, ok: bool) -> Button:
	var c := Catalog.car(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(TILE.x + 8, TILE.y + 30)
	if not (OS.get_cmdline_user_args().has("--seen_cars_only") and VehicleRegistry.no_ai(id)):
		b.icon = CarColumns.thumb(id)               # (screenshots, --seen_cars_only: no no-AI car's picture)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.text = str(c.get("name", id))
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.clip_text = true
	b.add_theme_font_override("font", UI.bold())
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", UI.CREAM)
	b.add_theme_color_override("font_hover_color", UI.YELLOW)
	b.add_theme_color_override("font_focus_color", UI.YELLOW)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.45))
	b.add_theme_stylebox_override("normal", _box(Color(0.1, 0.11, 0.12, 0.92), Color(0, 0, 0, 0)))
	b.add_theme_stylebox_override("hover", _box(Color(0.14, 0.15, 0.16, 0.95), UI.YELLOW))
	b.add_theme_stylebox_override("focus", _box(Color(0.14, 0.15, 0.16, 0.95), UI.YELLOW))
	b.add_theme_stylebox_override("pressed", _box(Color(0.18, 0.18, 0.18, 0.95), UI.YELLOW))
	b.add_theme_stylebox_override("disabled", _box(Color(0.06, 0.06, 0.07, 0.8), Color(0, 0, 0, 0)))
	if not ok:
		b.disabled = true
		b.modulate = Color(1, 1, 1, 0.45)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(_press.bind(id))
	b.set_meta("car", id)
	_tiles[id] = b
	return b


static func _box(bg: Color, edge: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(6)
	s.set_border_width_all(2)
	s.border_color = edge
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


func _press(id: String) -> void:
	if id == _sel:
		_go()
	else:
		_pick(id)


## The car looked at: on the garage's spot, its name and numbers up top, its tile marked red.
func _pick(id: String) -> void:
	if _tiles.has(_sel):
		(_tiles[_sel] as Button).add_theme_stylebox_override("normal", _box(Color(0.1, 0.11, 0.12, 0.92), Color(0, 0, 0, 0)))
	_sel = id
	if _tiles.has(id):
		(_tiles[id] as Button).add_theme_stylebox_override("normal", _box(Color(0.16, 0.08, 0.07, 0.95), UI.RED))
	var c := Catalog.car(id)
	_name.text = str(c.get("name", id))
	_info.text = _numbers(id)
	if backdrop:
		backdrop.show_car(Profile.setup_for(id))
	if mode.is_empty() and Profile.car == id:
		_drive.text = "✓  THE CAR YOU DRIVE"
		_drive.disabled = true
	else:
		_drive.text = "DRIVE THIS ONE" if mode.is_empty() else "START IN THIS ONE"
		_drive.disabled = not (id in _take.ids)


## The real car's numbers (the registry's researched specs).
static func _numbers(id: String) -> String:
	var e = VehicleRegistry.entry(id)
	var sp: Dictionary = e.get("specs", {}) if e else {}
	if not sp.has("power_hp"):
		return ""
	var bits := ["%d hp" % roundi(float(sp.power_hp)), "%d kg" % int(sp.get("weight_kg", 0)), str(sp.get("drivetrain", ""))]
	if sp.get("transmission"):
		bits.append(str(sp.transmission).split(" (")[0])
	return "  ·  ".join(bits)


## DRIVE THIS ONE: every car is free, so it's simply yours to drive.
func _go() -> void:
	if not (_sel in _take.ids):
		return
	if Profile.car != _sel:
		Profile.select_car(_sel)
		changed.emit()
	drive.emit(_sel)
	if mode.is_empty():
		_pick(_sel)
		if backdrop and backdrop.has_method("start_engine"):
			backdrop.start_engine()                  # (the door shuts, its engine starts)
