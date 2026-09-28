extends Control
## Title screen: name, host co-op / host PvP / solo / join by IP.

const UI = preload("res://scripts/ui/ui_theme.gd")
const SaveGame = preload("res://scripts/net/save_game.gd")

var main
var name_edit: LineEdit
var ip_edit: LineEdit
var port_edit: LineEdit
var status_lbl: Label
var _t := 0.0
var _line: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	var p := 0.5
	for i in 200:
		p = clampf(p + randf_range(-0.03, 0.032), 0.1, 0.9)
		_line.append(p)
	var box := VBoxContainer.new()
	UI.center(box, Vector2(560, 760))
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var title := UI.lbl("BAGHOLDERS", 100, UI.GOLD, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 18)
	title.add_theme_color_override("font_outline_color", Color(0.3, 0.05, 0.05))
	box.add_child(title)
	var sub := UI.lbl("EVERYONE SHARES THE BAG.", 26, UI.TEXT, true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(UI.lbl("Your name", 18, UI.DIM))
	name_edit = LineEdit.new()
	name_edit.text = Config.player_name
	name_edit.max_length = 16
	box.add_child(name_edit)
	var tailor := UI.btn("THE TAILOR  (customize your trader)", UI.GOLD.darkened(0.45), 24)
	tailor.pressed.connect(_open_tailor)
	box.add_child(tailor)
	# CONTINUE the newest run that isn't over; LOAD any save
	var save_row := HBoxContainer.new()
	box.add_child(save_row)
	var last := SaveGame.latest_open(Config.player_name)
	if not last.is_empty():
		var cont := UI.btn("CONTINUE  ·  %s" % SaveGame.describe(last), UI.GOLD.darkened(0.3), 20)
		cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cont.clip_text = true
		cont.pressed.connect(func(): _load(last))
		save_row.add_child(cont)
	var load_btn := UI.btn("LOAD GAME" if last.is_empty() else "LOAD", UI.NAVY_2, 20)
	load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL if last.is_empty() else Control.SIZE_FILL
	load_btn.pressed.connect(_open_saves)
	save_row.add_child(load_btn)
	var host_row := HBoxContainer.new()
	box.add_child(host_row)
	var coop := UI.btn("HOST CO-OP", UI.GREEN.darkened(0.3), 28)
	coop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coop.pressed.connect(func(): _host("coop"))
	host_row.add_child(coop)
	var pvp := UI.btn("HOST PVP", UI.RED.darkened(0.3), 28)
	pvp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pvp.pressed.connect(func(): _host("pvp"))
	host_row.add_child(pvp)
	var solo := UI.btn("PLAY SOLO", UI.NAVY_2, 24)
	solo.pressed.connect(func(): _host("coop"))
	box.add_child(solo)
	box.add_child(UI.lbl("Join a friend (their IP)", 18, UI.DIM))
	var join_row := HBoxContainer.new()
	box.add_child(join_row)
	ip_edit = LineEdit.new()
	ip_edit.text = Config.last_ip
	ip_edit.placeholder_text = "e.g. 100.101.102.103"
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(ip_edit)
	port_edit = LineEdit.new()
	port_edit.text = str(Config.port)
	port_edit.custom_minimum_size.x = 90
	join_row.add_child(port_edit)
	var join := UI.btn("JOIN", Color(0.15, 0.3, 0.7), 26)
	join.pressed.connect(_join)
	join_row.add_child(join)
	status_lbl = UI.lbl("", 20, UI.GOLD, true)
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(status_lbl)
	var help := UI.lbl("Host shares their IP. Same Wi-Fi: use their local IP.\nDifferent houses: all install Tailscale (free) and use the host's Tailscale IP.", 16, UI.DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(help)
	box.add_child(Music.volume_row(UI.lbl("Music", 18, UI.DIM)))
	var gfx := UI.btn("GRAPHICS  (auto: %s)" % Graphics.detected.to_upper(), UI.NAVY_2, 18)
	gfx.pressed.connect(func(): Graphics.popup(UI, self))
	box.add_child(gfx)
	var quit := UI.btn("QUIT", UI.NAVY_2, 20)
	quit.pressed.connect(func(): Sfx.quit_game())
	box.add_child(quit)


func _open_tailor() -> void:
	_save()
	var t = load("res://scripts/ui/tailor.gd").new()
	add_child(t)
	for c in get_children():
		if c != t and c is Control:
			c.visible = false
	t.done.connect(func():
		t.queue_free()
		for c in get_children():
			if c is Control:
				c.visible = true)


func set_status(msg: String) -> void:
	if status_lbl:
		status_lbl.text = msg


func _save() -> void:
	Config.player_name = name_edit.text.strip_edges().substr(0, 16)
	if Config.player_name.is_empty():
		Config.player_name = "Trader"
	Config.last_ip = ip_edit.text.strip_edges()
	Config.port = int(port_edit.text) if port_edit.text.is_valid_int() else 7777
	Config.save_settings()


func _host(game_mode: String) -> void:
	_save()
	Config.load_slot = ""                  # a brand-new run
	main.host_game(Config.port, game_mode)


## Host a saved run: same mode as it was played in; friends rejoin and get
## their things back by name.
func _load(s: Dictionary) -> void:
	_save()
	if not SaveGame.owned_by(s, Config.player_name):
		set_status("Only %s can load that save (they started it)." % s.get("owner", "the host"))
		return
	Config.load_slot = str(s.slot)
	main.host_game(Config.port, str(s.get("mode", "coop")))


## Every save: LOAD / DELETE, where they live, and the iCloud Drive toggle.
func _open_saves() -> void:
	var p := PanelContainer.new()
	UI.center(p, Vector2(760, 560))
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(UI.lbl("SAVED GAMES", 36, UI.GOLD, true))
	var where := UI.lbl("", 15, UI.DIM)
	where.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(where)
	if SaveGame.icloud_dir() != "":
		var cloud := CheckBox.new()
		cloud.text = "Keep saves in iCloud Drive (continue on any of your Macs)"
		cloud.button_pressed = Config.cloud_saves
		cloud.toggled.connect(func(on: bool):
			Config.cloud_saves = on
			Config.save_settings()
			p.queue_free()
			_open_saves())
		v.add_child(cloud)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var saves := SaveGame.list()
	where.text = "%d save%s in %s. The host keeps the save; everyone else just rejoins." % [
			saves.size(), "" if saves.size() == 1 else "s", "iCloud Drive" if SaveGame.in_cloud() else ProjectSettings.globalize_path(SaveGame.dir())]
	if saves.is_empty():
		list.add_child(UI.lbl("No saves yet. A run saves itself at every closing bell.", 18, UI.DIM))
	for s in saves:
		var row := HBoxContainer.new()
		list.add_child(row)
		var over: bool = s.get("over", false)
		var mine := SaveGame.owned_by(s, name_edit.text if name_edit.text.strip_edges() != "" else Config.player_name)
		var l := UI.lbl(("BUSTED · " if over else "") + SaveGame.describe(s) + ("" if mine else "  · started by %s" % s.owner),
				17, UI.DIM if over or not mine else UI.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		if not over and not mine:
			var lk := UI.btn("LOCKED", UI.NAVY_2, 16)
			lk.disabled = true
			lk.tooltip_text = "Only %s can load this run." % s.owner
			row.add_child(lk)
		elif not over:
			var lb := UI.btn("LOAD", UI.GREEN.darkened(0.3), 16)
			lb.pressed.connect(func(): _load(s))
			row.add_child(lb)
		var del := UI.btn("DELETE", UI.RED.darkened(0.35), 16)
		var slot: String = str(s.slot)
		del.pressed.connect(func():
			SaveGame.remove(slot)
			p.queue_free()
			_open_saves())
		row.add_child(del)
	var close := UI.btn("CLOSE", UI.NAVY_2, 20)
	close.pressed.connect(p.queue_free)
	v.add_child(close)


func _join() -> void:
	_save()
	if Config.last_ip.is_empty():
		set_status("Type the host's IP first.")
		return
	main.join_game(Config.last_ip, Config.port)


func _process(delta: float) -> void:
	_t += delta
	if int(_t * 8) != int((_t - delta) * 8):
		_line.remove_at(0)
		_line.append(clampf(_line[-1] + randf_range(-0.03, 0.032), 0.1, 0.9))
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.03, 0.05))
	for i in 30:
		draw_line(Vector2(0, i * 40), Vector2(size.x, i * 40), Color(1, 1, 1, 0.03))
	var cw := size.x / _line.size()
	for i in range(1, _line.size()):
		var up := _line[i] >= _line[i - 1]
		var x := i * cw
		var y0 := size.y * (1.0 - _line[i - 1])
		var y1 := size.y * (1.0 - _line[i])
		draw_rect(Rect2(x - cw * 0.35, minf(y0, y1), cw * 0.7, maxf(absf(y1 - y0), 2)), Color(0.2, 0.9, 0.35, 0.18) if up else Color(1, 0.3, 0.3, 0.18))
