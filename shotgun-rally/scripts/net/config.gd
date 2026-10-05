extends Node
## Settings that stick between runs (autoload "Config"), saved to
## user://settings.cfg. Command-line flags (after `--`) override them for one
## run: --name=Bob --port=7777 --seed=12.

const PATH := "user://settings.cfg"

var player_name := "Driver"
var last_ip := "127.0.0.1"
var port := 7777
var mouse_sens := 0.0022       # radians per pixel
var invert_y := false
var call_early := 0.0          # AI co-driver: -1 (late) .. +1 (early)
var volume := 0.8
## The driver aids for the new car physics (physics v2), each its own switch: all
## off is the base physics. Keys as in AssistConfig.
var aids := {"anti_lock": false, "traction_control": false, "stability_control": false, "steering_smoothing": false,
	"steering_damping": false, "countersteer_help": false, "speed_sensitive_steering": false}
var args := {}                 # --key=value / --flag from the command line


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		player_name = cf.get_value("player", "name", player_name)
		last_ip = cf.get_value("net", "last_ip", last_ip)
		port = cf.get_value("net", "port", port)
		mouse_sens = cf.get_value("controls", "mouse_sens", mouse_sens)
		invert_y = cf.get_value("controls", "invert_y", invert_y)
		call_early = cf.get_value("codriver", "call_early", call_early)
		volume = cf.get_value("audio", "volume", volume)
		for key in aids:
			aids[key] = cf.get_value("aids", key, aids[key])
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("name"):
		player_name = args.name
	if args.has("port"):
		port = int(args.port)
	AudioServer.set_bus_volume_db(0, linear_to_db(volume))


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("player", "name", player_name)
	cf.set_value("net", "last_ip", last_ip)
	cf.set_value("net", "port", port)
	cf.set_value("controls", "mouse_sens", mouse_sens)
	cf.set_value("controls", "invert_y", invert_y)
	cf.set_value("codriver", "call_early", call_early)
	cf.set_value("audio", "volume", volume)
	for key in aids:
		cf.set_value("aids", key, aids[key])
	cf.save(PATH)


func flag(key: String) -> bool:
	return args.has(key)


func arg(key: String, default = "") -> String:
	return args.get(key, str(default))
