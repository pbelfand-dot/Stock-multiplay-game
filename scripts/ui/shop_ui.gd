extends PanelContainer
## Tony "The Plug" (items, catalog "items") and the FLEX SHOP counter
## (luxury flex items, catalog "luxury").

const UI = preload("res://scripts/ui/ui_theme.gd")
const Rules = preload("res://scripts/sim/rules.gd")

signal closed

var match_node
var catalog := "items"
var store_tag := ""
var title_lbl: Label
var quote_lbl: Label
var list: VBoxContainer
var cash_lbl: Label


func setup(m, cat := "items") -> void:
	match_node = m
	catalog = cat
	m.state_changed.connect(_refresh)


func _ready() -> void:
	var lux := catalog.begins_with("luxury") or catalog == "pawn"
	add_theme_stylebox_override("panel", UI.panel_box(Color(0.05, 0.1, 0.07) if lux else Color(0.1, 0.07, 0.05), UI.GOLD, 18, 5))
	UI.center(self, Vector2(860, 700))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	title_lbl = UI.lbl(_title(), 48, UI.GOLD, true)
	v.add_child(title_lbl)
	quote_lbl = UI.lbl("", 18, UI.DIM)
	v.add_child(quote_lbl)
	cash_lbl = UI.lbl("", 22, UI.GREEN, true)
	v.add_child(cash_lbl)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
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
	if title_lbl:
		title_lbl.text = _title()
		quote_lbl.text = _quote()
	if catalog == "pawn":
		_refresh_pawn(me)
		return
	if catalog.begins_with("luxury"):
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


func _title() -> String:
	if catalog == "pawn":
		return "PAWN KING"
	if catalog == "items":
		return "TONY'S DELI" if store_tag == "deli" else "TONY \"THE PLUG\""
	var st := catalog.get_slice(":", 1) if catalog.contains(":") else ""
	return Rules.BOUTIQUE_NAMES.get(st if st != "" else "flex", "FLEX SHOP")


func _quote() -> String:
	match catalog:
		"pawn":
			return "\"Half what you paid. Take it or leave it, Wolf.\""
		"items":
			return "\"Whatever you need, boss. Cash only. I was never here.\""
	return "\"If you have to ask, you can't afford it.\""


## Change what this panel sells: "items", "luxury", "luxury:<store>", "pawn".
func set_catalog(cat: String, tag := "") -> void:
	catalog = cat
	store_tag = tag
	_refresh()


func _refresh_pawn(me: int) -> void:
	var any := false
	for key in Rules.LUXURY:
		var have: int = match_node.lux_count(me, key)
		if have <= 0:
			continue
		any = true
		var d: Dictionary = Rules.LUXURY[key]
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UI.panel_box(Color(0.16, 0.15, 0.08), Color(0.5, 0.45, 0.15), 8, 2))
		list.add_child(row)
		var h := HBoxContainer.new()
		row.add_child(h)
		var info := UI.lbl("%s   x%d" % [d.name, have], 24, UI.TEXT, true)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var b := UI.btn("SELL %s" % Rules.money(d.price * Rules.PAWN_RATE), UI.GOLD.darkened(0.4), 20)
		b.custom_minimum_size.x = 190
		var k: String = key
		b.pressed.connect(func():
			Sfx.play("cash")
			match_node.request_pawn(k))
		h.add_child(b)
	if not any:
		list.add_child(UI.lbl("You don't own anything worth pawning. Go buy some flex first.", 20, UI.DIM))


func _refresh_luxury(me: int, acct: Dictionary) -> void:
	var only := catalog.get_slice(":", 1) if catalog.contains(":") else ""   # "luxury" = the office counter: everything
	if only == "":
		_refresh_upgrades(me, acct)
		list.add_child(UI.lbl("FLEX", 26, UI.GOLD, true))
	for key in Rules.LUXURY:
		var d: Dictionary = Rules.LUXURY[key]
		if only != "" and d.get("store", "") != only:
			continue
		if only == "" and d.get("store", "") == "iron":     # guns only at BIG IRON
			continue
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
		if d.get("perk_txt", "") != "":
			info.add_child(UI.lbl("PERK: " + d.perk_txt, 16, Color(0.55, 1.0, 0.65)))
		var maxed := have >= int(d.max)
		var price: float = match_node.lux_price(key)
		var b := UI.btn("OWNED" if maxed else ("BUY %s" % Rules.money(price)) + (" (-%d%%)" % int(round((1.0 - price / d.price) * 100.0)) if price < d.price else ""),
				UI.GREEN.darkened(0.3), 20)
		b.custom_minimum_size.x = 170
		b.disabled = maxed or acct.get("balance", 0.0) < price
		var k: String = key
		b.pressed.connect(func():
			Sfx.play("coin")
			match_node.request_buy_lux(k))
		h.add_child(b)


## Office upgrades (only at the office counter): bought once, kept forever.
func _refresh_upgrades(me: int, acct: Dictionary) -> void:
	list.add_child(UI.lbl("OFFICE UPGRADES  ·  yours for good, they change how you play", 26, UI.GOLD, true))
	for key in Rules.UPGRADES:
		var d: Dictionary = Rules.UPGRADES[key]
		var have: bool = match_node.lux_count(me, key) > 0
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UI.panel_box(Color(0.07, 0.1, 0.18), Color(0.25, 0.4, 0.7), 8, 2))
		list.add_child(row)
		var h := HBoxContainer.new()
		row.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		info.add_child(UI.lbl(d.name, 24, UI.TEXT, true))
		info.add_child(UI.lbl(d.desc, 16, Color(0.55, 1.0, 0.65)))
		var b := UI.btn("INSTALLED" if have else "BUY %s" % Rules.money(d.price), UI.NAVY_2.lightened(0.15), 20)
		b.custom_minimum_size.x = 170
		b.disabled = have or acct.get("balance", 0.0) < d.price
		var k: String = key
		b.pressed.connect(func():
			Sfx.play("coin")
			match_node.request_buy_upgrade(k))
		h.add_child(b)
