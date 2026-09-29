extends PanelContainer
## A dealership's showroom (set_brand: BEMZE, MERCEDEZ BANZ, PORSHA, AUDY):
## every car that brand sells with its numbers (top speed, 0-60, handling), a
## factory color, BUY. Cars you own: DRIVE THIS (it's the one waiting for you
## every morning) or respray it. The used TOROLA is on the BEMZE lot. A brand
## with no cars yet: an empty turntable, "new models arriving soon".

const UI = preload("res://scripts/ui/ui_theme.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const Brands = preload("res://scripts/sim/brands.gd")
const CarScript = preload("res://scripts/vehicle/car.gd")

signal closed

const BEMZE_BLUE := Color(0.12, 0.45, 0.85)

var match_node
var brand := "bemze"
var col := BEMZE_BLUE            # the brand's colour: the frame, the bars, the turntable ring
var list: VBoxContainer
var paint := {}                  # car key -> chosen PAINTS index (for the next BUY / respray)
var cash_lbl: Label
var title_lbl: Label
var tag_lbl: Label
var selected := "bz_m3"          # the car on the turntable ("" = none: nothing on sale yet)
var stage: SubViewport
var turntable: Node3D
var ring_mat: StandardMaterial3D
var _shown := ""                 # key + paint currently on the turntable
var view_lbl: Label


func setup(m) -> void:
	match_node = m
	m.state_changed.connect(_refresh)


## Walk into this brand's showroom: its name, colours and cars (the turntable
## starts on its `pick`, else its flagship).
func set_brand(br: String) -> void:
	if not Brands.BRANDS.has(br):
		br = "bemze"
	var cars := Brands.cars(br)
	if br != brand or not cars.has(selected):
		var pick: String = Brands.BRANDS[br].get("pick", "")
		var shown := Brands.lineup(br)
		selected = pick if cars.has(pick) else (shown[0] if not shown.is_empty() else (cars[0] if not cars.is_empty() else ""))
	brand = br
	col = Brands.BRANDS[br].ui
	if title_lbl == null:
		return
	add_theme_stylebox_override("panel", UI.panel_box(Color(0.07, 0.08, 0.1), col, 16, 6))
	title_lbl.text = Brands.name_of(br)
	tag_lbl.text = "   " + str(Brands.BRANDS[br].tagline)
	tag_lbl.add_theme_color_override("font_color", col)
	ring_mat.albedo_color = col
	_refresh()


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.panel_box(Color(0.07, 0.08, 0.1), col, 16, 6))
	UI.center(self, Vector2(1100, 860))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	title_lbl = UI.lbl(Brands.name_of(brand), 44, Color(1, 1, 1), true)
	head.add_child(title_lbl)
	tag_lbl = UI.lbl("   " + str(Brands.BRANDS[brand].tagline), 20, col, true)
	tag_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag_lbl.clip_text = true
	head.add_child(tag_lbl)
	cash_lbl = UI.lbl("", 22, UI.GOLD, true)
	head.add_child(cash_lbl)
	# the turntable: the selected car, spinning, in its chosen color
	var sv := SubViewportContainer.new()
	sv.custom_minimum_size = Vector2(1060, 300)
	sv.stretch = true
	v.add_child(sv)
	stage = SubViewport.new()
	stage.own_world_3d = true
	stage.transparent_bg = false
	stage.msaa_3d = Viewport.MSAA_4X
	sv.add_child(stage)
	_build_stage()
	view_lbl = UI.lbl("", 20, UI.TEXT, true)
	view_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(view_lbl)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1060, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var bye := UI.btn("LEAVE THE SHOWROOM  [ESC]", Color(0.3, 0.1, 0.1), 18)
	bye.pressed.connect(func(): closed.emit())
	v.add_child(bye)
	_refresh()


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.07, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.7)
	e.ambient_light_energy = 0.6
	env.environment = e
	stage.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.8, 0.6, 0)
	key.light_energy = 1.3
	stage.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(-0.3, 2.8, 0)
	rim.light_energy = 0.7
	rim.light_color = Color(0.7, 0.8, 1.0)
	stage.add_child(rim)
	var floor := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.4
	cyl.bottom_radius = 3.5
	cyl.height = 0.12
	floor.mesh = cyl
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.13, 0.14, 0.17)
	fm.roughness = 0.25
	fm.metallic_specular = 0.9
	floor.material_override = fm
	floor.position.y = -0.06
	stage.add_child(floor)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.42
	tm.outer_radius = 3.5
	ring.mesh = tm
	ring_mat = StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = col
	ring.material_override = ring_mat
	stage.add_child(ring)
	turntable = Node3D.new()
	stage.add_child(turntable)
	var cam := Camera3D.new()
	cam.position = Vector3(4.6, 1.9, 5.2)
	cam.fov = 38
	stage.add_child(cam)
	cam.look_at(Vector3(0, 0.55, 0))
	cam.current = true


func _process(delta: float) -> void:
	if visible and turntable:
		turntable.rotation.y += delta * 0.35


func _show_car() -> void:
	if selected == "" or not Rules.CARS.has(selected):
		view_lbl.text = "The new %s lineup lands soon. The turntable's waiting." % Brands.name_of(brand)
		if _shown != "":
			_shown = ""
			for c in turntable.get_children():
				c.queue_free()
		return
	var me := Net.my_id()
	var pi: int = paint.get(selected, -1)
	var pc: Color = Rules.PAINTS[pi][1] if pi >= 0 else match_node.paint_of(me, selected)
	var sig := "%s|%s" % [selected, pc.to_html()]
	var d: Dictionary = Rules.CARS[selected]
	view_lbl.text = "%s   ·   %d MPH   ·   0-60 %.1f s   ·   %s" % [d.name, int(d.top * 2.237), d.zero60,
			Rules.PAINTS[pi][0] if pi >= 0 else ("your color" if match_node.owns_car(me, selected) else "pick a color")]
	if sig == _shown:
		return
	_shown = sig
	for c in turntable.get_children():
		c.queue_free()
	var car = CarScript.new()
	car.preview = true
	car.setup(selected, me, pc)
	turntable.add_child(car)


func _refresh() -> void:
	if list == null or match_node == null or not is_inside_tree():
		return
	_show_car()
	for c in list.get_children():
		c.queue_free()
	var me := Net.my_id()
	var a: Dictionary = match_node.my_acct()
	var money: float = float(a.get("balance", 0.0)) + match_node.cash_of(me)
	cash_lbl.text = "YOU HAVE %s" % Rules.money(money)
	var driving: String = match_node.car_of(me)
	var fastest := 0.0
	for k in Rules.CARS:
		fastest = maxf(fastest, Rules.CARS[k].top)
	var cars := Brands.cars(brand)
	if cars.is_empty():
		var soon := PanelContainer.new()
		soon.add_theme_stylebox_override("panel", UI.panel_box(Color(0.1, 0.12, 0.16), col.darkened(0.2), 8, 2))
		list.add_child(soon)
		var sv := VBoxContainer.new()
		soon.add_child(sv)
		var hl := UI.lbl("NEW MODELS ARRIVING SOON", 30, col.lightened(0.2), true)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sv.add_child(hl)
		var sl := UI.lbl("The %s trucks are on the way. Come back with cash." % Brands.name_of(brand), 17, UI.DIM)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sv.add_child(sl)
	for key in cars:
		var d: Dictionary = Rules.CARS[key]
		var own: bool = match_node.owns_car(me, key)
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UI.panel_box(Color(0.1, 0.12, 0.16) if key != driving else Color(0.08, 0.16, 0.26),
				col if key == driving else Color(0.25, 0.28, 0.34), 8, 2))
		list.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		row.add_child(h)
		# the swatch of its (chosen) color
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(46, 46)
		var pi: int = paint.get(key, -1)
		sw.color = Rules.PAINTS[pi][1] if pi >= 0 else match_node.paint_of(me, key)
		h.add_child(sw)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var title := "%s%s" % [d.name, "   · YOU DRIVE THIS" if key == driving else ("   · OWNED" if own else "")]
		var tb := Button.new()
		tb.flat = true
		tb.text = title
		tb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tb.add_theme_font_size_override("font_size", 24)
		tb.add_theme_color_override("font_color", col.lightened(0.4) if key == selected else UI.TEXT)
		var kk: String = key
		tb.pressed.connect(func():
			selected = kk
			Sfx.play("click")
			_refresh())
		info.add_child(tb)
		info.add_child(UI.lbl(d.desc, 15, UI.DIM))
		var stats := HBoxContainer.new()
		stats.add_theme_constant_override("separation", 16)
		info.add_child(stats)
		stats.add_child(_bar("TOP %d MPH" % int(d.top * 2.237), d.top / fastest))
		stats.add_child(_bar("0-60  %.1f s" % d.zero60, clampf(3.0 / d.zero60, 0.0, 1.0)))
		stats.add_child(_bar("HANDLING", clampf(d.grip / 1.05, 0.0, 1.0)))
		if key != "beater":
			var colors := HBoxContainer.new()
			colors.add_theme_constant_override("separation", 3)
			info.add_child(colors)
			for i in Rules.PAINTS.size():
				var cb := Button.new()
				cb.custom_minimum_size = Vector2(26, 20)
				cb.tooltip_text = Rules.PAINTS[i][0]
				var st := StyleBoxFlat.new()
				st.bg_color = Rules.PAINTS[i][1]
				st.set_border_width_all(2 if pi == i else 0)
				st.border_color = Color.WHITE
				cb.add_theme_stylebox_override("normal", st)
				cb.add_theme_stylebox_override("hover", st)
				var k: String = key
				var idx := i
				cb.pressed.connect(func():
					paint[k] = idx
					selected = k
					Sfx.play("click")
					_refresh())
				colors.add_child(cb)
		var btns := VBoxContainer.new()
		h.add_child(btns)
		var k2: String = key
		if not own:
			var b := UI.btn("BUY  %s" % Rules.money(d.price), UI.GREEN.darkened(0.3), 20)
			b.custom_minimum_size.x = 220
			b.disabled = money < d.price
			b.pressed.connect(func():
				Sfx.play("cash")
				match_node.request_buy_car(k2, int(paint.get(k2, 0))))
			btns.add_child(b)
		else:
			if key != driving:
				var dr := UI.btn("DRIVE THIS", col.darkened(0.3), 20)
				dr.custom_minimum_size.x = 220
				dr.pressed.connect(func():
					Sfx.play("click")
					match_node.request_pick_car(k2))
				btns.add_child(dr)
			if key != "beater" and paint.has(key):
				var rp := UI.btn("RESPRAY  %s" % Rules.money(Rules.RESPRAY), UI.NAVY_2, 16)
				rp.custom_minimum_size.x = 220
				rp.pressed.connect(func():
					Sfx.play("click")
					match_node.request_respray(k2, int(paint[k2]))
					paint.erase(k2))
				btns.add_child(rp)


func _bar(label: String, k: float) -> Control:
	var v := VBoxContainer.new()
	v.add_child(UI.lbl(label, 13, UI.DIM, true))
	var bg := ColorRect.new()
	bg.custom_minimum_size = Vector2(150, 8)
	bg.color = Color(0.2, 0.22, 0.26)
	v.add_child(bg)
	var fg := ColorRect.new()
	fg.color = col
	fg.size = Vector2(150 * clampf(k, 0.02, 1.0), 8)
	bg.add_child(fg)
	return v
