extends PanelContainer
## Small modal panel for Magnolia Heights: the realtor's listing (address,
## price, BUY) and the taxi / rideshare destinations. The HoodController owns
## it and does the actions; HUD treats it as a modal (mouse visible, input off).

const UI = preload("res://scripts/ui/ui_theme.gd")

signal buy_pressed(house_id: String)
signal ride_pressed(dest: String)
signal closed

var body: VBoxContainer
var mode := ""                  # "realtor" | "taxi" | ""


func _init() -> void:
	name = "RealtorUI"
	UI.center(self, Vector2(600, 330))
	add_theme_stylebox_override("panel", UI.panel_box(Color(0.06, 0.1, 0.17, 0.97), UI.GOLD, 12, 3))
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	add_child(body)
	visible = false


func is_open() -> bool:
	return visible


func close() -> void:
	if visible:
		visible = false
		mode = ""
		closed.emit()


func _clear() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()


func _title(text: String, sub: String) -> void:
	var t := UI.lbl(text, 34, UI.GOLD, true)
	body.add_child(t)
	if sub != "":
		var s := UI.lbl(sub, 17, UI.DIM)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD
		body.add_child(s)


## info: {id, name, address, price, desc, owner_name, mine, can_afford, balance, my_other}
func open_listing(info: Dictionary) -> void:
	_clear()
	mode = "realtor"
	_title("MAXED OUT REALTY", "\"We sell homes to bagholders.\"")
	body.add_child(UI.lbl("%s  —  %s" % [info.address, info.name], 24, UI.TEXT, true))
	var d := UI.lbl(info.desc, 18, UI.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.add_child(d)
	var price := UI.lbl("ASKING  " + price_str(info.price), 30, UI.GREEN, true)
	body.add_child(price)
	var note := UI.lbl("", 18, UI.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	var buy := UI.btn("BUY", UI.GREEN.darkened(0.35), 26)
	buy.custom_minimum_size = Vector2(180, 48)
	buy.name = "Buy"
	row.add_child(buy)
	var close_b := UI.btn("CLOSE", UI.NAVY_2, 22)
	close_b.custom_minimum_size = Vector2(140, 48)
	close_b.pressed.connect(close)
	row.add_child(close_b)
	if info.mine:
		note.text = "It's yours. The key's in your pocket: [E] on the front door. Taxi → MY HOUSE to wake up here."
		note.add_theme_color_override("font_color", UI.GREEN)
		buy.disabled = true
		buy.text = "OWNED"
	elif info.owner_name != "":
		note.text = "SOLD to %s. Sorry — one owner per house. Plenty of other listings on the block." % info.owner_name
		note.add_theme_color_override("font_color", UI.RED)
		buy.disabled = true
		buy.text = "SOLD"
	elif info.my_other != "":
		note.text = "You already own %s. One house at a time, tycoon." % info.my_other
		buy.disabled = true
	elif not info.can_afford:
		note.text = "The fund has %s. The bank says come back richer. (Open house: walk right in and look around.)" % price_str(info.balance)
		buy.disabled = true
	else:
		note.text = "Paid from your account (%s). Saved with your career: it's still yours next time." % price_str(info.balance)
		buy.pressed.connect(func(): buy_pressed.emit(str(info.id)))
	visible = true


## options: [[dest, label], ...]
func open_taxi(here: String, options: Array) -> void:
	_clear()
	mode = "taxi"
	_title("TAXI · RIDESHARE", "You're at: %s. Where to? (Cars come later — for now the driver takes it.)" % here)
	for o in options:
		var bt := UI.btn(o[1], UI.NAVY_2, 22)
		bt.custom_minimum_size = Vector2(0, 46)
		bt.name = "Dest_" + str(o[0])
		var dest: String = o[0]
		bt.pressed.connect(func(): ride_pressed.emit(dest))
		body.add_child(bt)
	var close_b := UI.btn("CLOSE", UI.NAVY_2, 20)
	close_b.pressed.connect(close)
	body.add_child(close_b)
	visible = true


static func price_str(v: float) -> String:
	var n := int(round(v))
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + "$" + s + out
