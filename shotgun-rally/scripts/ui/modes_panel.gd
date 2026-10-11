extends PanelContainer
## MODES: the touge (a Japanese mountain pass, up or down, against the clock or
## for drift points), CUT UP (the LAKESHORE LOOP full of traffic, four
## difficulties) and TRACK (CINDER RIDGE, a ~5 km circuit: a class, a session). ALONE, or HOST ONLINE for up to eight friends, each in their own
## car (they join from ONLINE with your IP; a touge is then a race to the bottom),
## with collisions between you or as ghosts. Each START picks a new pass; at the
## results, R runs the same one again. Night style (UI kit): each mode on a card
## with its key art behind it (assets/ui/key_touge, key_cutup: Higgsfield; key_track: an
## in-game picture of the circuit).

signal back
signal start(m: Dictionary)

const UI = preload("res://scripts/ui/ui_kit.gd")
const Modes = preload("res://scripts/game/modes.gd")
const Profile = preload("res://scripts/game/profile.gd")
const TrackSeries = preload("res://scripts/game/track_series.gd")

var _dir := "up"
var _rules := "time"
var _dir_btns := {}
var _toll := "open"                  # cut up: the toll plaza's layout (Modes.TOLL_LAYOUTS)
var _toll_btns := {}
var _rule_btns := {}
var _online := false
var _collide := true
var _play_btns := {}
var _collide_btn: Button
var _class := "gt"                   # track: the class (Modes.track_classes)
var _class_btns := {}
var _session := "practice"           # track: the session (Modes.TRACK_SESSIONS)
var _session_btns := {}
var _laps := 5                       # track: a race's laps (3, 5, 10 or any 1-99)
var _lap_btns := {}
var _laps_label: Label
var _opponents := 9                  # track: the AI field (0-15)
var _opp_label: Label
var _ai := "medium"                  # track: the AI's skill (Modes.TRACK_DIFFICULTY)
var _ai_btns := {}
var _start_type := ""                # track: "" (the class's own), "rolling", "standing"
var _start_btn: Button
var _minutes := 10                   # track: qualifying's length
var _min_btn: Button
var _grid := "middle"                # track: a quick race's place for you
var _grid_btn: Button
var _damage := true
var _damage_btn: Button
var _race_rows: Array = []           # the race options' rows (hidden for practice)
var _weather := "day"                # track: Modes.TRACK_WEATHER
var _weather_btns := {}
var _weather_row: Control
var _series_row: Control             # the CHAMPIONSHIP's season, NEW SEASON
var _series_label: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.panel_skin("night", 20))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	# the title, then alone or online
	var r0 := HBoxContainer.new()
	r0.add_theme_constant_override("separation", 10)
	v.add_child(r0)
	var title := UI.label("MODES", 36, UI.CREAM, true)
	title.custom_minimum_size = Vector2(130, 0)
	r0.add_child(title)
	for p in [[false, "ALONE"], [true, "HOST ONLINE  (UP TO 8)"]]:
		var pb := UI.button(p[1], _set_online.bind(p[0]), 20, 150 if not p[0] else 280, "night")
		_play_btns[p[0]] = pb
		r0.add_child(pb)
	r0.add_child(UI.gap(10))
	_collide_btn = UI.button("COLLISIONS: ON", func(): _set_collide(not _collide), 20, 230, "night")
	r0.add_child(_collide_btn)
	v.add_child(UI.label("Online: friends join from ONLINE > JOIN with your IP, each in their own car. A touge is a race to the bottom; on the track, CARS fills the grid with AI.", 15, UI.DIM))
	# the cards, scrolling (three don't fit the screen's height: the wheel, or a pad's focus moving
	# down, scrolls them)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	v.add_child(scroll)
	var cards := VBoxContainer.new()
	cards.add_theme_constant_override("separation", 8)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cards)
	# the touge
	var touge := _card(cards, "key_touge")
	touge.add_child(UI.label("TOUGE", 30, UI.YELLOW, true))
	touge.add_child(UI.label("A Japanese mountain pass at night: hairpins, guardrails, cedar forest, two lanes, no co-driver.", 17, UI.CREAM))
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 10)
	touge.add_child(r1)
	for d in [["up", "UPHILL"], ["down", "DOWNHILL"]]:
		var b := UI.button(d[1], _set_dir.bind(d[0]), 20, 150, "night")
		_dir_btns[d[0]] = b
		r1.add_child(b)
	r1.add_child(UI.gap(10))
	for r in [["time", "TIME ATTACK"], ["drift", "DRIFT"]]:
		var b2 := UI.button(r[1], _set_rules.bind(r[0]), 20, 170, "night")
		_rule_btns[r[0]] = b2
		r1.add_child(b2)
	touge.add_child(UI.label("Time attack: a split every kilometre against your best on that pass. Drift: angle x speed, chained.", 15, UI.DIM))
	var go := UI.button("START  ·  NEW PASS", func(): start.emit({"mode": "touge", "dir": _dir, "rules": _rules,
		"online": _online, "collide": _collide}), 22, 300, "night")
	go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	touge.add_child(go)
	# cut up
	var cut := _card(cards, "key_cutup")
	cut.add_child(UI.label("CUT UP", 30, UI.YELLOW, true))
	var what := UI.label("The LAKESHORE LOOP: 28 km of highway that never ends (the city, tunnels, three suspension bridges), packed with traffic. Near misses chain a combo; crash and it's gone.", 17, UI.CREAM)
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.custom_minimum_size = Vector2(860, 0)
	cut.add_child(what)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 10)
	cut.add_child(r2)
	for k in Modes.DIFFICULTIES:
		var best := Profile.mode_best("cutup/%s" % k)
		var text: String = Modes.DIFFICULTIES[k].name + ("  ·  %d" % int(best.value) if not best.is_empty() else "")
		r2.add_child(UI.button(text, func(): start.emit({"mode": "cutup", "difficulty": k, "toll": _toll, "online": _online, "collide": _collide}), 20, 150, "night"))
	var r3 := HBoxContainer.new()
	r3.add_theme_constant_override("separation", 10)
	cut.add_child(r3)
	r3.add_child(UI.label("TOLL PLAZA", 17, UI.DIM))
	for tk in Modes.TOLL_LAYOUTS:
		var tb := UI.button(Modes.TOLL_LAYOUTS[tk], _set_toll.bind(tk), 17, 150, "night")
		_toll_btns[tk] = tb
		r3.add_child(tb)
	_track_card(cards)
	v.add_child(UI.gap(2))
	var back_btn := UI.button("BACK", func(): back.emit(), 20, 140, "night")
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(back_btn)
	_set_dir(_dir)
	_set_rules(_rules)
	_set_toll(_toll)
	_set_online(_online)
	_set_class(_class)
	_set_session(_session)
	if Config.flag("modes_scroll"):                  # (pictures: --menu_panel=modes --modes_scroll=600)
		(func(): scroll.scroll_vertical = int(Config.arg("modes_scroll"))).call_deferred()
	(_play_btns[false] as Button).grab_focus.call_deferred()     # (keys and pads start on ALONE)


## TRACK: the circuit, a class (those not ready yet greyed), a session (PRACTICE, QUALIFYING,
## QUICK RACE, RACE WEEKEND), its options (laps, the AI field, the start, qualifying's length, your
## grid place, damage), the weather (DAY, NIGHT, WET), START: alone, or hosted online (the friends who join race too, each in a car
## of the class; CARS is then the AI filling the grid round them, up to 12, 0 for friends only).
func _track_card(v: Control) -> void:
	var trk := _card(v, "key_track")
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	trk.add_child(head)
	head.add_child(UI.label("TRACK", 30, UI.YELLOW, true))
	var cid: String = Modes.CIRCUITS.keys()[0]
	head.add_child(UI.label("%s  ·  %.1f KM  ·  %d CORNERS" % [Modes.CIRCUITS[cid], Modes.circuit_info(cid).length / 1000.0,
		Modes.circuit_info(cid).corners], 20, UI.CREAM, true))
	var what := UI.label("A permanent circuit in the hills: pit lane and garages, kerbs, gravel traps, tyre walls, grandstands. Out of your box, then laps against the clock: three sectors, track limits.", 16, UI.CREAM)
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.custom_minimum_size = Vector2(860, 0)
	trk.add_child(what)
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	trk.add_child(r)
	var classes := Modes.track_classes()
	for ck in classes:
		var c: Dictionary = classes[ck]
		var cb := UI.button(str(c.get("name", ck)).to_upper(), _set_class.bind(ck), 20, 150, "night")
		if not bool(c.get("available", false)):
			cb.disabled = true
			cb.tooltip_text = "Coming soon"
		_class_btns[ck] = cb
		r.add_child(cb)
	r.add_child(UI.gap(10))
	for sk in Modes.TRACK_SESSIONS:
		var sb := UI.button(Modes.TRACK_SESSIONS[sk], _set_session.bind(sk), 20, 170, "night")
		_session_btns[sk] = sb
		r.add_child(sb)
	r.add_child(UI.gap(10))
	var go := UI.button("START", _start_track, 22, 160, "night")
	r.add_child(go)
	# a race's options: laps, the field, its start, qualifying's length, your grid place, damage
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 8)
	trk.add_child(r2)
	r2.add_child(UI.label("LAPS", 18, UI.DIM, true))
	for n in Modes.TRACK_LAPS:
		var lb := UI.button(str(n), _set_laps.bind(n), 18, 56, "night")
		_lap_btns[n] = lb
		r2.add_child(lb)
	r2.add_child(UI.button("-", func(): _set_laps(_laps - 1), 18, 40, "night"))
	_laps_label = UI.label("", 18, UI.CREAM, true)
	_laps_label.custom_minimum_size = Vector2(36, 0)
	_laps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r2.add_child(_laps_label)
	r2.add_child(UI.button("+", func(): _set_laps(_laps + 1), 18, 40, "night"))
	r2.add_child(UI.gap(14))
	r2.add_child(UI.label("CARS", 18, UI.DIM, true))
	r2.add_child(UI.button("-", func(): _set_opponents(_opponents - 1), 18, 40, "night"))
	_opp_label = UI.label("", 18, UI.CREAM, true)
	_opp_label.custom_minimum_size = Vector2(36, 0)
	_opp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r2.add_child(_opp_label)
	r2.add_child(UI.button("+", func(): _set_opponents(_opponents + 1), 18, 40, "night"))
	r2.add_child(UI.gap(14))
	r2.add_child(UI.label("AI", 18, UI.DIM, true))
	for ak in Modes.TRACK_DIFFICULTY:
		var ab := UI.button(str(Modes.TRACK_DIFFICULTY[ak].name), _set_ai.bind(ak), 18, 92, "night")
		_ai_btns[ak] = ab
		r2.add_child(ab)
	var r3 := HBoxContainer.new()
	r3.add_theme_constant_override("separation", 8)
	trk.add_child(r3)
	_start_btn = UI.button("", _cycle_start, 18, 210, "night")
	r3.add_child(_start_btn)
	_min_btn = UI.button("", _cycle_minutes, 18, 230, "night")
	r3.add_child(_min_btn)
	_grid_btn = UI.button("", _cycle_grid, 18, 200, "night")
	r3.add_child(_grid_btn)
	_damage_btn = UI.button("", func(): _damage = not _damage; _refresh_race(), 18, 170, "night")
	r3.add_child(_damage_btn)
	_race_rows = [r2, r3]
	# the weather, every session: a dry day, a night under the floodlights, a wet track in the rain
	var r4 := HBoxContainer.new()
	r4.add_theme_constant_override("separation", 8)
	trk.add_child(r4)
	r4.add_child(UI.label("WEATHER", 18, UI.DIM, true))
	for wk in Modes.TRACK_WEATHER:
		var wb := UI.button(Modes.TRACK_WEATHER[wk], _set_weather.bind(wk), 18, 110, "night")
		_weather_btns[wk] = wb
		r4.add_child(wb)
	_set_weather(_weather)
	_weather_row = r4
	# the championship: where the season stands (its rounds set their own laps and weather), NEW SEASON
	var r5 := HBoxContainer.new()
	r5.add_theme_constant_override("separation", 10)
	trk.add_child(r5)
	_series_label = UI.label("", 16, UI.CREAM)
	_series_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_series_label.custom_minimum_size = Vector2(680, 0)
	r5.add_child(_series_label)
	r5.add_child(UI.button("NEW SEASON", _new_season, 16, 160, "night"))
	_series_row = r5
	_set_laps(_laps)
	_set_opponents(_opponents)
	_set_ai(_ai)
	var best := Profile.mode_best("track/%s/%s/%s" % [Modes.CIRCUITS.keys()[0], _class, Modes.track_car({"class": _class}, _garage_car())])
	var note := "Practice: as many laps as you like (END RUN in the pause menu). Qualifying: the clock, the field on track, your best lap sets your place. Quick race: the grid, the lights or the rolling start, flags and penalties. Race weekend: qualifying, then the race from where you qualified. Championship: four race weekends (day, night, rain, a long finale), points to the top ten."
	if not best.is_empty():
		note = "Your best: %s.   " % _fmt_lap(float(best.value)) + note
	var nl := UI.label(note, 15, UI.DIM)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size = Vector2(860, 0)
	trk.add_child(nl)
	_refresh_race()


## START on the TRACK card: the class, the session and the race's options.
func _start_track() -> void:
	start.emit({"mode": "track", "class": _class, "session": _session, "laps": _laps, "opponents": _opponents,
		"track_difficulty": _ai, "start": _start_type, "minutes": float(_minutes), "grid": _grid, "damage": _damage, "weather": _weather,
		"online": _online, "collide": _collide})


func _set_laps(n: int) -> void:
	_laps = clampi(n, 1, 99)
	for k in _lap_btns:
		(_lap_btns[k] as Button).modulate = Color.WHITE if k == _laps else Color(1, 1, 1, 0.45)
	if _laps_label:
		_laps_label.text = str(_laps)


func _set_opponents(n: int) -> void:
	_opponents = clampi(n, 0, 15)
	if _opp_label:
		_opp_label.text = str(_opponents)


func _set_ai(k: String) -> void:
	_ai = k
	for a in _ai_btns:
		(_ai_btns[a] as Button).modulate = Color.WHITE if a == k else Color(1, 1, 1, 0.45)


func _set_weather(k: String) -> void:
	_weather = k
	for w in _weather_btns:
		(_weather_btns[w] as Button).modulate = Color.WHITE if w == k else Color(1, 1, 1, 0.45)


func _cycle_start() -> void:
	_start_type = {"": "rolling", "rolling": "standing", "standing": ""}[_start_type]
	_refresh_race()


func _cycle_minutes() -> void:
	var opts := [5, 10, 15, 20]
	_minutes = opts[(opts.find(_minutes) + 1) % opts.size()]
	_refresh_race()


func _cycle_grid() -> void:
	var opts := ["front", "middle", "back", "random"]
	_grid = opts[(opts.find(_grid) + 1) % opts.size()]
	_refresh_race()


## The race options' buttons say what's set; practice hides them, and each session shows its own.
func _refresh_race() -> void:
	if _start_btn == null:
		return
	var own := str(Modes.track_classes().get(_class, {}).get("start", "rolling"))
	_start_btn.text = "START: %s" % (("%s (CLASS)" % own.to_upper()) if _start_type == "" else _start_type.to_upper())
	_min_btn.text = "QUALIFYING: %d MIN" % _minutes
	_grid_btn.text = "GRID: %s" % _grid.to_upper()
	_damage_btn.text = "DAMAGE: %s" % ("ON" if _damage else "OFF")
	for row in _race_rows:
		(row as Control).visible = _session != "practice"
	_min_btn.visible = _session in ["qualifying", "weekend", "series"]
	_grid_btn.visible = _session == "race"
	_start_btn.visible = _session in ["race", "weekend"]
	if _series_row:
		_series_row.visible = _session == "series"
		_weather_row.visible = _session != "series"      # (each round has its own)
		_series_label.text = TrackSeries.summary(TrackSeries.current(_class))


## NEW SEASON: the running championship dropped (START then begins a new one).
func _new_season() -> void:
	Profile.ensure_loaded()
	Profile.track_series.erase(_class)
	Profile.save()
	_refresh_race()


static func _garage_car() -> String:
	Profile.ensure_loaded()
	return str(Profile.car)


static func _fmt_lap(t: float) -> String:
	var m := int(t / 60.0)
	return "%d:%06.3f" % [m, t - m * 60.0]


func _set_class(c: String) -> void:
	_class = c
	for k in _class_btns:
		var b: Button = _class_btns[k]
		b.modulate = Color.WHITE if k == c else Color(1, 1, 1, 0.45 if not b.disabled else 0.25)
	_refresh_race()                                   # (the class's own championship)


func _set_session(sk: String) -> void:
	_session = sk
	for k in _session_btns:
		(_session_btns[k] as Button).modulate = Color.WHITE if k == sk else Color(1, 1, 1, 0.45)
	_refresh_race()


## A mode's card: its key art behind (covering the card, darkened on the left
## where the words are, the picture showing through on the right). Returns the
## box the card's rows go in.
func _card(parent: Control, art_name: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.05, 0.9)
	sb.border_color = Color(1.0, 0.62, 0.15, 0.55)
	sb.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", sb)
	parent.add_child(card)
	var t := UI.art(art_name)
	if t:
		var pic := TextureRect.new()
		pic.texture = t
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(pic)
		var g := Gradient.new()
		g.set_color(0, Color(0.01, 0.015, 0.03, 0.9))
		g.set_color(1, Color(0.01, 0.015, 0.03, 0.25))
		g.add_point(0.55, Color(0.01, 0.015, 0.03, 0.72))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.width = 256
		gt.height = 4
		var shade := TextureRect.new()
		shade.texture = gt
		shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shade.stretch_mode = TextureRect.STRETCH_SCALE
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(shade)
	var pad := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	card.add_child(pad)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	pad.add_child(rows)
	return rows


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


func _set_toll(t: String) -> void:
	_toll = t
	for k in _toll_btns:
		(_toll_btns[k] as Button).modulate = Color.WHITE if k == t else Color(1, 1, 1, 0.45)


func _set_rules(r: String) -> void:
	_rules = r
	for k in _rule_btns:
		(_rule_btns[k] as Button).modulate = Color.WHITE if k == r else Color(1, 1, 1, 0.45)
