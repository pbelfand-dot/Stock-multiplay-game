extends Node
## Global settings + input map (built in code so project.godot stays readable).

const SAVE_PATH := "user://settings.cfg"

var player_name := "Trader"
var last_ip := "127.0.0.1"
var port := 7777
var mouse_sensitivity := 0.0025
var music_volume := 0.6      # 0..1, the soundtrack slider (0 = off)
var suit_color := Color(0.35, 0.36, 0.4)
var look := {}            # character look from the tailor (empty = default for your slot)

## Command-line flags (after `--`), e.g. `-- --host --pvp --autostart`
var cli := {}


func _ready() -> void:
	_parse_cli()
	_setup_inputs()
	load_settings()


func _parse_cli() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			cli[kv[0]] = kv[1] if kv.size() > 1 else "true"


func _key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _setup_inputs() -> void:
	_key("move_forward", [KEY_W, KEY_UP])
	_key("move_back", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("jump", [KEY_SPACE])
	_key("sprint", [KEY_SHIFT])
	_key("interact", [KEY_E])
	_key("scoreboard", [KEY_TAB])
	_key("pause", [KEY_ESCAPE])
	_key("start_day", [KEY_ENTER, KEY_KP_ENTER])
	_key("chat", [KEY_T])
	_key("emote_finger", [KEY_F])
	_key("emote_fistpump", [KEY_V])
	_key("emote_watch", [KEY_Z])
	_key("emote_point", [KEY_X])
	_key("emote_dance", [KEY_H])
	_key("phone", [KEY_P])
	_key("phone_action", [KEY_G])
	_key("dive", [KEY_C, KEY_CTRL])
	for i in 6:
		_key("item_%d" % (i + 1), [KEY_1 + i])
	_mouse("fire", MOUSE_BUTTON_LEFT)


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		player_name = cf.get_value("player", "name", player_name)
		last_ip = cf.get_value("net", "ip", last_ip)
		port = cf.get_value("net", "port", port)
		mouse_sensitivity = cf.get_value("input", "sens", mouse_sensitivity)
		music_volume = cf.get_value("audio", "music", music_volume)
		suit_color = cf.get_value("player", "suit", suit_color)
		look = cf.get_value("player", "look", look)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("player", "name", player_name)
	cf.set_value("player", "suit", suit_color)
	cf.set_value("player", "look", look)
	cf.set_value("net", "ip", last_ip)
	cf.set_value("net", "port", port)
	cf.set_value("input", "sens", mouse_sensitivity)
	cf.set_value("audio", "music", music_volume)
	cf.save(SAVE_PATH)
