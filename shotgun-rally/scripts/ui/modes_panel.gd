extends PanelContainer
## MODES: the touge (a Japanese mountain pass, up or down, against the clock or
## for drift points) and CUT UP (the LAKESHORE LOOP full of traffic, four
## difficulties). ALONE, or HOST ONLINE for up to eight friends, each in their own
## car (they join from ONLINE with your IP; a touge is then a race to the bottom),
## with collisions between you or as ghosts. Each START picks a new pass; at the
## results, R runs the same one again.

signal back
signal start(m: Dictionary)

const UI = preload("res://scripts/ui/ui_kit.gd")
const Modes = preload("res://scripts/game/modes.gd")
const Profile = preload("res://scripts/game/profile.gd")

var _dir := "up"
var _rules := "time"
var _dir_btns := {}
var _rule_btns := {}
var _online := false
var _collide := true
var _play_btns := {}
var _collide_btn: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.box())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	v.add_child(UI.label("MODES", 44, UI.CREAM, true))
	# alone or online
	var r0 := HBoxContainer.new()
	r0.add_theme_constant_override("separation", 10)
	v.add_child(r0)
	for p in [[false, "ALONE"], [true, "HOST ONLINE  (UP TO 8)"]]:
		var pb := UI.button(p[1], _set_online.bind(p[0]), 20, 150 if not p[0] else 280)
		_play_btns[p[0]] = pb
		r0.add_child(pb)
	r0.add_child(UI.gap(10))
	_collide_btn = UI.button("COLLISIONS: ON", func(): _set_collide(not _collide), 20, 230)
	r0.add_child(_collide_btn)
	v.add_child(UI.label("Online: friends join from ONLINE > JOIN with your IP, each in their own car. A touge is a race to the bottom.", 15, UI.DIM))
	# the touge
	v.add_child(UI.label("TOUGE", 30, UI.YELLOW, true))
	v.add_child(UI.label("A Japanese mountain pass at night: hairpins, guardrails, cedar forest, two lanes, no co-driver.", 17, UI.DIM))
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 10)
	v.add_child(r1)
	for d in [["up", "UPHILL"], ["down", "DOWNHILL"]]:
		var b := UI.button(d[1], _set_dir.bind(d[0]), 20, 150)
		_dir_btns[d[0]] = b
		r1.add_child(b)
	r1.add_child(UI.gap(10))
	for r in [["time", "TIME ATTACK"], ["drift", "DRIFT"]]:
		var b2 := UI.button(r[1], _set_rules.bind(r[0]), 20, 170)
		_rule_btns[r[0]] = b2
		r1.add_child(b2)
	v.add_child(UI.label("Time attack: a split every kilometre against your best on that pass. Drift: angle x speed, chained.", 15, UI.DIM))
	var go := UI.button("START  ·  NEW PASS", func(): start.emit({"mode": "touge", "dir": _dir, "rules": _rules,
		"online": _online, "collide": _collide}), 22, 300)
	go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(go)
	v.add_child(UI.gap(2))
	# cut up
	v.add_child(UI.label("CUT UP", 30, UI.YELLOW, true))
	v.add_child(UI.label("The LAKESHORE LOOP: 28 km of highway that never ends (the city, tunnels, three suspension bridges), packed with traffic. Near misses chain a combo; crash and it's gone.", 17, UI.DIM))
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 10)
	v.add_child(r2)
	for k in Modes.DIFFICULTIES:
		var best := Profile.mode_best("cutup/%s" % k)
		var text: String = Modes.DIFFICULTIES[k].name + ("\n%d" % int(best.value) if not best.is_empty() else "")
		r2.add_child(UI.button(text, func(): start.emit({"mode": "cutup", "difficulty": k, "online": _online, "collide": _collide}), 20, 150))
	v.add_child(UI.gap(8))
	var back_btn := UI.button("BACK", func(): back.emit(), 20, 140)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(back_btn)
	_set_dir(_dir)
	_set_rules(_rules)
	_set_online(_online)


func _set_online(on: bool) -> void:
	_online = on
	for k in _play_btns:
		(_play_btns[k] as Button).modulate = Color.WHITE if k == on else Color(1, 1, 1, 0.45)
	_collide_btn.disabled = not on
	_collide_btn.modulate = Color.WHITE if on else Color(1, 1, 1, 0.3)


func _set_collide(on: bool) -> void:
	_collide = on
	_collide_btn.text = "COLLISIONS: ON" if on else "COLLISIONS: GHOSTS"


func _set_dir(d: String) -> void:
	_dir = d
	for k in _dir_btns:
		(_dir_btns[k] as Button).modulate = Color.WHITE if k == d else Color(1, 1, 1, 0.45)


func _set_rules(r: String) -> void:
	_rules = r
	for k in _rule_btns:
		(_rule_btns[k] as Button).modulate = Color.WHITE if k == r else Color(1, 1, 1, 0.45)
