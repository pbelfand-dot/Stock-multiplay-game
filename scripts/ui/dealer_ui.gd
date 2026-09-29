extends PanelContainer
## BEMZE dealership: every car on the lot with its numbers (top speed, 0-60,
## handling), a factory color, BUY. Cars you own: DRIVE THIS (it's the one
## waiting for you every morning) or respray it.

const UI = preload("res://scripts/ui/ui_theme.gd")
const Rules = preload("res://scripts/sim/rules.gd")

signal closed

const BEMZE_BLUE := Color(0.12, 0.45, 0.85)

var match_node
var list: VBoxContainer
var paint := {}                  # car key -> chosen PAINTS index (for the next BUY / respray)
var cash_lbl: Label


func setup(m) -> void:
	match_node = m
	m.state_changed.connect(_refresh)


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.panel_box(Color(0.07, 0.08, 0.1), BEMZE_BLUE, 16, 6))
	UI.center(self, Vector2(1100, 780))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UI.lbl("BEMZE", 44, Color(1, 1, 1), true)
	head.add_child(t)
	var sub := UI.lbl("   THE ULTIMATE CUT-UP MACHINE", 20, BEMZE_BLUE, true)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sub)
	cash_lbl = UI.lbl("", 22, UI.GOLD, true)
	head.add_child(cash_lbl)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1060, 640)
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


func _refresh() -> void:
	if list == null or match_node == null or not is_inside_tree():
		return
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
	for key in Rules.CAR_ORDER:
		var d: Dictionary = Rules.CARS[key]
		var own: bool = match_node.owns_car(me, key)
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UI.panel_box(Color(0.1, 0.12, 0.16) if key != driving else Color(0.08, 0.16, 0.26),
				BEMZE_BLUE if key == driving else Color(0.25, 0.28, 0.34), 8, 2))
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
		info.add_child(UI.lbl(title, 24, UI.TEXT, true))
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
				var dr := UI.btn("DRIVE THIS", BEMZE_BLUE.darkened(0.3), 20)
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
	fg.color = BEMZE_BLUE
	fg.size = Vector2(150 * clampf(k, 0.02, 1.0), 8)
	bg.add_child(fg)
	return v
