extends Control
## The home screen. Behind it, the garage (MenuGarage: your car parked under a light
## box, a slow camera round it; --menu_stage brings back the old backdrop, MenuBackdrop:
## your car flat out on a stage, filmed like rally TV). Over it: the logo, your
## credits, and six ways in (the logo, icons and panels: Higgsfield art, assets/ui):
##   PLAY NOW   a random stage, straight in (the AI co-driver calls; not in a rally car: pick one first)
##   MODES      a touge (mountain pass: time attack or drift) or CUT UP (highway traffic) (ModesPanel);
##              START opens the CARS grid on the mode's column, its cars only (CarColumns)
##   MAPS       story mode: the championship (MapsPanel; a rally car picked first)
##   CARS       every car on a grid (CarGrid: STREET, GT3, F1, RALLY, HYPERCARS; all free), the car
##              picked on the spot; CUSTOMISE: its paint and parts (GaragePanel)
##   ONLINE     your name, host a crew (pick your seat) or join one by IP
##   SETTINGS   controls, sound, the co-driver's timing, driving aids (SettingsPanel)
## Top right, by your credits and name: MUSIC (what's playing): your own songs from the music
## folder on this computer, a playlist per folder (MusicPanel, MusicPlayer).
## ESC (or BACK) goes back to the home buttons. The build and updates are top
## right (see Updater).

signal solo
signal host(seat: String)
signal join(ip: String)
signal story(rally: int, seat: String)
signal mode(m: Dictionary)

const UI = preload("res://scripts/ui/ui_kit.gd")
const Backdrop = preload("res://scripts/ui/menu_backdrop.gd")
const Garage = preload("res://scripts/ui/menu_garage.gd")
const GaragePanel = preload("res://scripts/ui/garage_panel.gd")
const CarGrid = preload("res://scripts/ui/car_grid.gd")
const CarColumns = preload("res://scripts/game/car_columns.gd")
const MapsPanel = preload("res://scripts/ui/maps_panel.gd")
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")
const ModesPanel = preload("res://scripts/ui/modes_panel.gd")
const MusicPanel = preload("res://scripts/ui/music_panel.gd")
const Profile = preload("res://scripts/game/profile.gd")

var start_panel := ""               # open on this panel ("maps" after a rally)
var backdrop
var _cover: ColorRect               # until the backdrop is built
var _home: VBoxContainer
var _area: Control                  # where a panel goes
var _open: Control
var _back_to := ""                  # where BACK goes from the panel open ("": home)
var _custom := ""                   # the car CUSTOMISE opened the garage on
var _pick := {}                     # the CARS grid opened for a mode: {mode, go (Callable), back}
var _credits: Label
var _sub: Label                     # the line under the title (hidden while a panel's open)
var _logo: TextureRect              # (smaller while a panel's open: room for it)
var _name_chip: Button
var _music_chip: Button             # MUSIC  ·  the playlist playing (opens MusicPanel)
var _status: Label
var _name: LineEdit
var _ip: LineEdit
var _build: Label
var _upd: Label
var _upd_btn: Button
var _upd_action := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # (plain set_anchors_preset keeps the old, zero size)
	Profile.ensure_loaded()
	backdrop = (Backdrop if Config.flag("menu_stage") else Garage).new()
	add_child(backdrop)
	backdrop.show_car(Profile.setup())
	backdrop.ready_to_show.connect(_on_backdrop_ready)
	_cover = ColorRect.new()
	_cover.color = Color(0.015, 0.015, 0.018)          # (the garage's dark: it fades up out of it)
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cover)
	# a dark wash on the left so the text reads over the scene
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.78))
	g.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_bottom = 1.0
	shade.anchor_right = 0.62
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_title()
	_top_right()
	_home = VBoxContainer.new()
	_home.position = Vector2(56, 244)
	_home.add_theme_constant_override("separation", 10)
	add_child(_home)
	_home.add_child(UI.menu_item("PLAY NOW", "A random stage, straight in. The AI calls the notes.", _play_now, true, "play"))
	_home.add_child(UI.menu_item("MODES", "Touge at night, cut up through traffic, lap a circuit. Online: up to 8.", _show.bind("modes"), false, "modes"))
	_home.add_child(UI.menu_item("MAPS", "The Shotgun Series: nine rallies, rival crews, prize money.", _show.bind("maps"), false, "maps"))
	_home.add_child(UI.menu_item("CARS", "Every car free: street, GT3, F1, rally, hypercars. Paint, upgrade.", _show.bind("cars"), false, "cars"))
	if OS.has_feature("web"):
		# a browser can't connect two machines the way the game does (UDP): online is the download's
		_home.add_child(UI.menu_item("ONLINE", "Needs the download (Windows, Mac, Linux, Chromebook with Linux).", func():
			_status.text = "Online play needs the download version: a browser can't connect two machines.\nGet it from the SHOTGUN RALLY download page (Chromebook: the .deb, with Linux turned on).", false, "online"))
	else:
		_home.add_child(UI.menu_item("ONLINE", "Ride with a friend, or join a friend's street session (up to 8).", _show.bind("online"), false, "online"))
	_home.add_child(UI.menu_item("SETTINGS", "Controls, sound, the co-driver's timing, driving aids, time of day.", _show.bind("settings"), false, "settings"))
	if not OS.has_feature("web"):                      # (a browser tab is closed, not quit)
		var quit := UI.button("QUIT", func(): get_tree().quit(), 20, 140)
		quit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_home.add_child(UI.gap(6))
		_home.add_child(quit)
	_area = Control.new()
	_area.position = Vector2(48, 204)
	_area.size = Vector2(800, 640)
	# (it lies over the home buttons, empty while they're up: a plain Control stops the
	# mouse, and it took every click and hover meant for them. The panels in it still get theirs.)
	_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_area)
	_status = UI.label("", 20, Color(1.0, 0.7, 0.4))
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_status.offset_top = -96
	_status.offset_left = -700
	_status.offset_right = 700
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_status.add_theme_constant_override("outline_size", 5)
	add_child(_status)
	var help := UI.label("DRIVER  WASD / arrows · SPACE handbrake · R reset      CO-DRIVER  hold RIGHT MOUSE / Q for the map · F wipers      "
		+ "PAD  left stick · RT / LT · B handbrake      MUSIC  N next song · B on / off", 15, Color(0.75, 0.77, 0.72))
	help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	help.offset_top = -40
	help.offset_left = -800
	help.offset_right = 800
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# (a dark edge: the garage floor's reflections of the lights pass behind it and washed it out)
	help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	help.add_theme_constant_override("outline_size", 4)
	add_child(help)
	_update_corner()
	if start_panel != "":
		_show(start_panel)
	else:
		(_home.get_child(0).get_meta("button") as Button).grab_focus.call_deferred()


func _on_backdrop_ready() -> void:
	var tw := create_tween()
	tw.tween_property(_cover, "modulate:a", 0.0, 0.9)
	tw.tween_callback(_cover.hide)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and _open != null:
		_back()
		get_viewport().set_input_as_handled()


func _title() -> void:
	var logo := UI.art("logo")
	if logo:
		_logo = TextureRect.new()
		_logo.texture = logo
		_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		_logo.position = Vector2(40, 12)
		_logo.size = _logo_size(400.0)
		_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_logo)
	else:
		var tl := UI.label("SHOTGUN RALLY", 92, UI.CREAM, true)
		tl.position = Vector2(60, 34)
		tl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
		tl.add_theme_constant_override("shadow_offset_x", 4)
		tl.add_theme_constant_override("shadow_offset_y", 4)
		add_child(tl)
	_sub = UI.label("You drive. Your friend rides shotgun with the map.", 22, Color(0.9, 0.88, 0.8))
	_sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_sub.add_theme_constant_override("shadow_offset_x", 2)
	_sub.add_theme_constant_override("shadow_offset_y", 2)
	_sub.position = Vector2(60, 196)
	add_child(_sub)


func _logo_size(w: float) -> Vector2:
	return Vector2(w, w * _logo.texture.get_height() / _logo.texture.get_width())


## The logo big on the home screen, small over a panel (the panel goes higher).
func _shrink_title(small: bool) -> void:
	_area.position.y = 150.0 if small and _logo else 204.0
	if _logo:
		var tw := _logo.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_logo, "size", _logo_size(270.0 if small else 400.0), 0.2)


## Top right: your credits and your name (click it: ONLINE, where you change it).
func _top_right() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.offset_top = 26
	row.offset_right = -28
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	var chip := UI.panel(Color(0.04, 0.05, 0.06, 0.8))
	chip.add_theme_stylebox_override("panel", UI.box(Color(0.04, 0.05, 0.06, 0.8), 22, 12))
	_credits = UI.label("", 26, UI.YELLOW, true)
	chip.add_child(_credits)
	row.add_child(chip)
	_music_chip = UI.button("MUSIC", _show.bind("music"), 20)
	_music_chip.name = "MusicChip"
	row.add_child(_music_chip)
	_name_chip = UI.button("", _show.bind("online"), 20)
	row.add_child(_name_chip)
	Config.music.changed.connect(refresh)
	refresh()


## Credits / name changed (a purchase, a new name): redraw the chips.
func refresh() -> void:
	_credits.text = "%s CR" % _money(Profile.credits)
	_name_chip.text = "DRIVER  ·  %s" % Config.player_name.to_upper()
	var m = Config.music
	if not m.on:
		_music_chip.text = "MUSIC  ·  OFF"
	elif m.song_count() == 0:
		_music_chip.text = "MUSIC  ·  ADD SONGS"
	else:
		_music_chip.text = "MUSIC  ·  %s" % str(m.picked().get("name", ""))


func _show(which: String) -> void:
	_back(false)
	_back_to = ""
	_home.visible = false
	_sub.visible = false
	_shrink_title(true)
	if backdrop.has_method("set_mood"):
		backdrop.set_mood(which)                        # (the garage's door frame takes the panel's colour)
	match which:
		"maps":
			var m := MapsPanel.new()
			m.start.connect(func(i: int, seat: String):
				if seat == "codriver":                   # (riding with a friend: their car)
					story.emit(i, seat)
				else:
					_pick_car({"mode": "rally"}, func(): story.emit(i, seat), "maps"))
			_open = m
		"cars", "pick":
			var g := CarGrid.new()
			g.backdrop = backdrop
			g.changed.connect(refresh)
			if which == "pick":                         # (for a mode: its cars, DRIVE starts it)
				g.mode = _pick.mode
				var go: Callable = _pick.go
				g.drive.connect(func(_id: String): go.call())
				_back_to = str(_pick.back)
			else:
				g.customise.connect(func(id: String):
					_custom = id
					_show("garage"))
			_open = g
			backdrop.set_showroom(true)
		"garage":
			var gp := GaragePanel.new()
			gp.backdrop = backdrop
			gp.start = _custom
			gp.changed.connect(refresh)
			_back_to = "cars"
			_open = gp
			backdrop.set_showroom(true)
		"online":
			_open = _online_panel()
		"settings":
			_open = SettingsPanel.new()
		"music":
			_open = MusicPanel.new()
		"modes":
			var mp := ModesPanel.new()
			mp.start.connect(func(m: Dictionary): _pick_car(m, func(): mode.emit(m), "modes"))
			_open = mp
	_area.add_child(_open)
	if _open.has_signal("back"):
		_open.connect("back", _back)
	_open.modulate.a = 0.0
	_open.position.x = -30.0
	var tw := _open.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_open, "modulate:a", 1.0, 0.22)
	tw.tween_property(_open, "position:x", 0.0, 0.22)


## A mode's START (and a rally's): the CARS grid opens on the mode's column, only the cars it takes
## (CarColumns.for_mode: the touge STREET, the track its class, a rally RALLY, cut up any); DRIVE
## starts it in the car picked. BACK goes to `back` (the panel it came from, "": home).
func _pick_car(m: Dictionary, go: Callable, back := "") -> void:
	_pick = {"mode": m, "go": go, "back": back}
	_show("pick")


## PLAY NOW: a rally stage, straight in when you drive a rally car; else pick one first.
func _play_now() -> void:
	if CarColumns.allows({"mode": "rally"}, Profile.car):
		solo.emit()
	else:
		_pick_car({"mode": "rally"}, func(): solo.emit())


func _back(home := true) -> void:
	if home and _back_to != "":                     # (a panel opened from another: back to that one)
		var to := _back_to
		_back_to = ""
		_show(to)
		return
	if _open:
		_open.queue_free()
		_open = null
	backdrop.set_showroom(false)
	backdrop.show_car(Profile.setup())
	if home and backdrop.has_method("set_mood"):
		backdrop.set_mood("")
	if home:
		_home.visible = true
		_sub.visible = true
		_shrink_title(false)
		(_home.get_child(0).get_meta("button") as Button).grab_focus()
	refresh()


func _online_panel() -> Control:
	var p := UI.art_panel("night")
	p.add_user_signal("back")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	v.add_child(UI.label("ONLINE", 44, UI.CREAM, true))
	v.add_child(UI.label("Two machines, one car: the driver's machine drives it, the co-driver gets the map.", 18, UI.DIM))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	name_row.add_child(UI.label("YOUR NAME", 22, UI.CREAM))
	_name = LineEdit.new()
	_name.text = Config.player_name
	_name.custom_minimum_size = Vector2(300, 46)
	_name.add_theme_font_override("font", UI.med())
	_name.add_theme_font_size_override("font_size", 22)
	_name.text_changed.connect(func(t): Config.player_name = t.strip_edges().substr(0, 20); Config.save(); refresh())
	name_row.add_child(_name)
	v.add_child(name_row)
	v.add_child(UI.button("HOST  ·  I DRIVE", func(): host.emit("driver"), 24, 460, "night"))
	v.add_child(UI.button("HOST  ·  I RIDE SHOTGUN", func(): host.emit("codriver"), 24, 460, "night"))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 12)
	_ip = LineEdit.new()
	_ip.text = Config.last_ip
	_ip.placeholder_text = "host's IP"
	_ip.custom_minimum_size = Vector2(300, 52)
	_ip.add_theme_font_override("font", UI.med())
	_ip.add_theme_font_size_override("font_size", 22)
	join_row.add_child(_ip)
	join_row.add_child(UI.button("JOIN", func(): join.emit(_ip.text.strip_edges()), 24, 148, "night"))
	v.add_child(join_row)
	v.add_child(UI.label("Same Wi-Fi: join the host's IP (it's on their screen). Different houses: Tailscale (see the README).\n"
		+ "The driver's car from their garage is the car on the stage.", 16, UI.DIM))
	var back := UI.button("BACK", func(): p.emit_signal("back"), 20, 140, "night")
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(back)
	return p


## Top right, under the chips: this copy's build, what the updater is doing, and
## its button (RESTART TO UPDATE once a new build is downloaded, or the download page).
func _update_corner() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.offset_left = -520
	box.offset_right = -28
	box.offset_top = 90
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_build = UI.label("BUILD %d" % Updater.current_build if Updater.current_build > 0 else "DEV BUILD", 18, UI.CREAM, true)
	_build.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_build)
	_upd = UI.label("", 16, Color(0.75, 0.78, 0.7))
	_upd.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_upd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_upd)
	_upd_btn = UI.button("", _on_update_button, 20, 300)
	_upd_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_upd_btn.visible = false
	box.add_child(_upd_btn)
	Updater.status_changed.connect(_on_update_status)
	Updater.boot_ok()                                  # made it to the menu: this build starts fine
	Updater.check()


func _on_update_status(text: String, act: String) -> void:
	_upd.text = text
	_upd_action = act
	_build.text = "BUILD %d" % Updater.current_build if Updater.current_build > 0 else "DEV BUILD"
	match act:
		"restart":
			_upd_btn.text = "RESTART TO UPDATE"
			_upd_btn.visible = true
			_upd.add_theme_color_override("font_color", Color(0.55, 1.0, 0.5))
		"download_page":
			_upd_btn.text = "OPEN DOWNLOAD PAGE"
			_upd_btn.visible = true
			_upd.add_theme_color_override("font_color", Color(0.75, 0.78, 0.7))
		_:
			_upd_btn.visible = false
			_upd.add_theme_color_override("font_color", Color(0.75, 0.78, 0.7))


func _on_update_button() -> void:
	match _upd_action:
		"restart":
			Updater.restart()
		"download_page":
			Updater.open_download_page()


func status(msg: String) -> void:
	if _status:
		_status.text = msg


static func _money(n: int) -> String:
	var t := str(absi(n))
	var out := ""
	while t.length() > 3:
		out = "," + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return t + out
