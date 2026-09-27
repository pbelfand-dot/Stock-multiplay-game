extends PanelContainer
## Tony "The Plug" (items, catalog "items") and the FLEX SHOP counter
## (luxury flex items, catalog "luxury").

const UI = preload("res://scripts/ui/ui_theme.gd")
const Rules = preload("res://scripts/sim/rules.gd")

signal closed

var match_node
var catalog := "items"
var list: VBoxContainer
var cash_lbl: Label


func setup(m, cat := "items") -> void:
	match_node = m
	catalog = cat
	m.state_changed.connect(_refresh)


func _ready() -> void:
	var lux := catalog == "luxury"
	add_theme_stylebox_override("panel", UI.panel_box(Color(0.05, 0.1, 0.07) if lux else Color(0.1, 0.07, 0.05), UI.GOLD, 18, 5))
	UI.center(self, Vector2(820, 640))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	v.add_child(UI.lbl("FLEX SHOP" if lux else "TONY \"THE PLUG\"", 48, UI.GOLD, true))
	v.add_child(UI.lbl("\"If you have to ask, you can't afford it.\"" if lux else "\"Whatever you need, boss. Cash only. I was never here.\"", 18, UI.DIM))
	cash_lbl = UI.lbl("", 22, UI.GREEN, true)
	v.add_child(cash_lbl)
	list = VBoxContainer.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	v.add_child(list)
	var foot := HBoxContainer.new()
	v.add_child(foot)
	foot.add_child(UI.lbl("Flex shows up on your desk and your wrist. Everyone sees it." if lux
			else "Use items with keys 1-6. Items add HEAT. 100 heat = cops.", 16, UI.DIM))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	var close := UI.btn("LEAVE [ESC]", UI.NAVY_2, 20)
	close.pressed.connect(func(): closed.emit())
	foot.add_child(close)
	_refresh()


func _refresh() -> void:
	if list == null or match_node == null:
		return
	for c in list.get_children():
		c.queue_free()
	var me := Net.my_id()
	var acct: Dictionary = match_node.my_acct()
	cash_lbl.text = "%s CASH: %s" % ["FUND" if Net.mode == "coop" else "YOUR", Rules.money(acct.get("balance", 0.0))]
	if catalog == "luxury":
		_refresh_luxury(me, acct)
		return
	var i := 0
	for key in Rules.ITEMS:
		i += 1
		var d: Dictionary = Rules.ITEMS[key]
		if d.get("pvp_only", false) and Net.mode != "pvp":
			continue
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UI.panel_box(Color(0.16, 0.12, 0.08), Color(0.4, 0.3, 0.15), 8, 2))
		list.add_child(row)
		var h := HBoxContainer.new()
		row.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		info.add_child(UI.lbl("[%d] %s   x%d owned" % [i, d.name, match_node.item_count(me, key)], 24, UI.TEXT, true))
		info.add_child(UI.lbl(d.desc, 16, UI.DIM))
		var heat_txt := "+%d HEAT" % int(d.heat) if d.heat > 0 else "no heat"
		h.add_child(UI.lbl(heat_txt, 18, UI.RED if d.heat > 0 else UI.DIM))
		var b := UI.btn("BUY %s" % Rules.money(d.price), UI.GREEN.darkened(0.3), 20)
		b.custom_minimum_size.x = 170
		b.disabled = acct.get("balance", 0.0) < d.price
		var k: String = key
		b.pressed.connect(func():
			Sfx.play("coin")
			match_node.request_buy(k))
		h.add_child(b)


func _refresh_luxury(me: int, acct: Dictionary) -> void:
	for key in Rules.LUXURY:
		var d: Dictionary = Rules.LUXURY[key]
		var have: int = match_node.lux_count(me, key)
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UI.panel_box(Color(0.08, 0.16, 0.11), Color(0.2, 0.45, 0.3), 8, 2))
		list.add_child(row)
		var h := HBoxContainer.new()
		row.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		info.add_child(UI.lbl("%s   %d/%d" % [d.name, have, int(d.max)], 24, UI.TEXT, true))
		info.add_child(UI.lbl(d.desc, 16, UI.DIM))
		var maxed := have >= int(d.max)
		var b := UI.btn("OWNED" if maxed else "BUY %s" % Rules.money(d.price), UI.GREEN.darkened(0.3), 20)
		b.custom_minimum_size.x = 170
		b.disabled = maxed or acct.get("balance", 0.0) < d.price
		var k: String = key
		b.pressed.connect(func():
			Sfx.play("coin")
			match_node.request_buy_lux(k))
		h.add_child(b)
