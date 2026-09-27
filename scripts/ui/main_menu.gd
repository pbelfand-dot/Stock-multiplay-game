extends Control
## Title screen: name, host co-op / host PvP / solo / join by IP.

const UI = preload("res://scripts/ui/ui_theme.gd")

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
	UI.center(box, Vector2(560, 700))
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var title := UI.lbl("BAGHOLDERS", 120, UI.GOLD, true)
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
	var quit := UI.btn("QUIT", UI.NAVY_2, 20)
	quit.pressed.connect(func(): Sfx.quit_game())
	box.add_child(quit)


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
	main.host_game(Config.port, game_mode)


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
