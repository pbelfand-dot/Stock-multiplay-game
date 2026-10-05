extends Control
## The title screen: your name, then DRIVE SOLO (the AI co-driver calls),
## HOST (pick your seat), or JOIN a host by IP. Controls at the bottom; the
## build and updates (see Updater) top right.

signal solo
signal host(seat: String)
signal join(ip: String)

var _status: Label
var _name: LineEdit
var _ip: LineEdit
var _build: Label
var _upd: Label
var _upd_btn: Button
var _upd_action := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # (plain set_anchors_preset keeps the old, zero size)
	var bold: Font = load("res://assets/fonts/Oswald-Bold.woff2")
	var med: Font = load("res://assets/fonts/Oswald-Medium.woff2")
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.16, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var stripe := ColorRect.new()                      # a rally stripe across the screen
	stripe.color = Color(0.78, 0.12, 0.1)
	stripe.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stripe.offset_top = 210
	stripe.offset_bottom = 226
	add_child(stripe)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var title := Label.new()
	title.text = "SHOTGUN RALLY"
	title.add_theme_font_override("font", bold)
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color(0.98, 0.95, 0.85))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "You drive. Your friend rides shotgun with the map."
	sub.add_theme_font_override("font", med)
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", Color(0.85, 0.82, 0.7))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(_gap(18))
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(name_row)
	name_row.add_child(_label("YOUR NAME", med))
	_name = LineEdit.new()
	_name.text = Config.player_name
	_name.custom_minimum_size = Vector2(260, 46)
	_name.add_theme_font_override("font", med)
	_name.add_theme_font_size_override("font_size", 22)
	_name.text_changed.connect(func(t): Config.player_name = t.strip_edges().substr(0, 20); Config.save())
	name_row.add_child(_name)
	box.add_child(_button("DRIVE SOLO  ·  AI CO-DRIVER", bold, func(): solo.emit()))
	box.add_child(_button("HOST  ·  I DRIVE", bold, func(): host.emit("driver")))
	box.add_child(_button("HOST  ·  I RIDE SHOTGUN", bold, func(): host.emit("codriver")))
	var join_row := HBoxContainer.new()
	join_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(join_row)
	_ip = LineEdit.new()
	_ip.text = Config.last_ip
	_ip.placeholder_text = "host's IP"
	_ip.custom_minimum_size = Vector2(250, 56)
	_ip.add_theme_font_override("font", med)
	_ip.add_theme_font_size_override("font_size", 22)
	join_row.add_child(_ip)
	var jb := _button("JOIN", bold, func(): join.emit(_ip.text.strip_edges()))
	jb.custom_minimum_size = Vector2(170, 56)
	join_row.add_child(jb)
	box.add_child(_button("QUIT", bold, func(): get_tree().quit()))
	_status = _label("", med)
	_status.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	var help := Label.new()
	help.text = ("DRIVER  WASD / arrows · SPACE handbrake · R reset      CO-DRIVER  hold RIGHT MOUSE / Q to look at the map · F wipers\n"
		+ "Controller: left stick · RT / LT · B handbrake · hold LT (co-driver) · A wipers      Same Wi-Fi: join the host's IP. Different houses: Tailscale (see README).")
	help.add_theme_font_override("font", med)
	help.add_theme_font_size_override("font_size", 16)
	help.add_theme_color_override("font_color", Color(0.7, 0.72, 0.65))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	help.offset_top = -70
	help.offset_left = -800
	help.offset_right = 800
	add_child(help)
	_update_corner(bold, med)


## Top right: this copy's build, what the updater is doing, and its button
## (RESTART TO UPDATE once a new build is downloaded, or the download page).
func _update_corner(bold: Font, med: Font) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.offset_left = -520
	box.offset_right = -28
	box.offset_top = 22
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_build = _label("BUILD %d" % Updater.current_build if Updater.current_build > 0 else "DEV BUILD", bold)
	_build.add_theme_color_override("font_color", Color(0.98, 0.95, 0.85))
	_build.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_build)
	_upd = _label("", med)
	_upd.add_theme_font_size_override("font_size", 17)
	_upd.add_theme_color_override("font_color", Color(0.75, 0.78, 0.7))
	_upd.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_upd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_upd)
	_upd_btn = _button("", bold, _on_update_button)
	_upd_btn.add_theme_font_size_override("font_size", 20)
	_upd_btn.custom_minimum_size = Vector2(300, 46)
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


func _button(text: String, font: Font, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 26)
	b.custom_minimum_size = Vector2(440, 56)
	b.pressed.connect(cb)
	return b


func _label(text: String, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", 22)
	return l


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
