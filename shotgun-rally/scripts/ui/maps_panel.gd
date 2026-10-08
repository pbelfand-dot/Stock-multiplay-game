extends PanelContainer
## MAPS: story mode, the Shotgun Series (Championship). Six rallies in a grid:
## the ones you've opened, how you finished them, the next one to beat. Pick
## one to see its three stages, the light, what's different about its roads and
## what it pays; start it alone (the AI co-driver) or host it for a friend.

signal back
signal start(rally: int, seat: String)

const UI = preload("res://scripts/ui/ui_kit.gd")
const Championship = preload("res://scripts/game/championship.gd")
const Profile = preload("res://scripts/game/profile.gd")

const MOODS := {"day": "DAYLIGHT", "golden": "GOLDEN HOUR", "overcast": "OVERCAST, FOG"}

var _sel := 0
var _body: VBoxContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.panel_skin("rally"))
	custom_minimum_size = Vector2(780, 0)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)
	# start on the first rally not yet finished
	for i in Championship.count():
		_sel = i
		if not Profile.rally_record(Championship.rally(i).id).get("done", false):
			break
	_rebuild()


func _rebuild() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_body.add_child(UI.label("THE SHOTGUN SERIES", 40, UI.CREAM, true))
	_body.add_child(UI.label("%d rallies, three stages each, five rival crews. Finish a rally to open the next." % Championship.count(), 18, UI.DIM))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	for i in Championship.count():
		grid.add_child(_card(i))
	_body.add_child(grid)
	_body.add_child(_detail(_sel))
	var back_btn := UI.button("BACK", func(): back.emit(), 20, 140)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_body.add_child(back_btn)


func _card(i: int) -> Button:
	var r := Championship.rally(i)
	var open := Profile.rally_open(i, Championship.RALLIES)
	var rec := Profile.rally_record(r.id)
	var state := "LOCKED"
	if rec.get("done", false):
		state = "WON  ★" if int(rec.best_pos) == 1 else "BEST  %s" % Championship.ordinal(int(rec.best_pos))
	elif open:
		state = "NEW"
	var b := UI.button("%d  %s\n%s" % [i + 1, r.name, state], func(): _sel = i; _rebuild(), 17, 248)
	b.custom_minimum_size = Vector2(248, 60)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = not open
	if i == _sel:
		UI.mark(b)
	return b


func _detail(i: int) -> Control:
	var r := Championship.rally(i)
	var p := UI.panel(Color(1, 1, 1, 0.06))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	v.add_child(UI.label(r.name, 30, UI.YELLOW, true))
	var blurb := UI.label(r.blurb, 18, UI.CREAM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(700, 0)
	v.add_child(blurb)
	var km := 0.0
	var stages: Array = []
	for j in r.stages.size():
		stages.append("SS%d %s  %.1f km" % [j + 1, r.stages[j][0], r.stages[j][2] / 1000.0])
		km += r.stages[j][2] / 1000.0
	v.add_child(UI.label("   ·   ".join(stages), 17, UI.DIM))
	var extra := [MOODS.get(r.mood, r.mood), "%.1f km of stages" % km]
	if r.gen.has("narrow"):
		extra.append("NARROW ROADS")
	if r.gen.has("puddles"):
		extra.append("PUDDLES EVERYWHERE")
	match str(r.gen.get("surface", "gravel")):
		"mixed": extra.append("GRAVEL + TARMAC")
		"tarmac": extra.append("MOUNTAIN TARMAC")
		_: extra.append("GRAVEL")
	if r.gen.get("ice", false):
		extra.append("SNOW AND ICE")
	v.add_child(UI.label("   ·   ".join(extra), 17, UI.DIM))
	v.add_child(UI.label("PRIZE  1st %s CR  ·  2nd %s  ·  3rd %s  ·  plus credits for every stage" % [
		_money(Championship.reward(i, 1)), _money(Championship.reward(i, 2)), _money(Championship.reward(i, 3))], 17, UI.CREAM))
	var rec := Profile.rally_record(r.id)
	if rec.get("done", false):
		v.add_child(UI.label("Your best: %s, %s" % [Championship.ordinal(int(rec.best_pos)), _fmt(float(rec.best_total))], 17, Color(0.5, 1.0, 0.5)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if Profile.rally_open(i, Championship.RALLIES):
		var go := UI.button("START  ·  SOLO", func(): start.emit(i, ""), 22, 230)
		row.add_child(go)
		row.add_child(UI.button("HOST · I DRIVE", func(): start.emit(i, "driver"), 18, 200))
		row.add_child(UI.button("HOST · I RIDE SHOTGUN", func(): start.emit(i, "codriver"), 18, 250))
		go.grab_focus.call_deferred()
	else:
		row.add_child(UI.label("Finish %s to open this one." % Championship.rally(i - 1).name, 18, UI.DIM))
	v.add_child(row)
	return p


static func _fmt(t: float) -> String:
	return "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]


static func _money(n: int) -> String:
	var t := str(absi(n))
	var out := ""
	while t.length() > 3:
		out = "," + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return t + out
