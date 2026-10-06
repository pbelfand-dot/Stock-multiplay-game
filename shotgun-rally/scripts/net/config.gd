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
var volume := 0.8              # everything
var sfx_volume := 0.45         # the engine, the gravel, crashes ... (the "SFX" bus)
var voice_volume := 1.0        # the co-driver's voice (the "Voice" bus)
var quick_surface := "any"     # PLAY NOW / online stages: "gravel", "tarmac", "mixed" or "any" (Main.quick_opts)
## The driver aids, each its own switch (keys as in AssistConfig): all off is the
## base physics. Out of the box the steering helps are on: a key can't hold part
## of the lock, so at speed it asks for all of it (smoothing eases it in, speed-
## sensitive steering keeps it to what the tyres can use), and countersteer help
## catches the tail (without it, holding the speed at the limit at 110 km/h spins
## it: tests/handling_check.gd), and drift assist holds a drift at its angle
## instead of letting it swing round into a spin (tests/drift_check.gd). The rest
## are off (a rally car has no ABS).
const AIDS_DEFAULT := {"anti_lock": false, "traction_control": false, "stability_control": false,
	"steering_smoothing": true, "steering_damping": false, "countersteer_help": true, "speed_sensitive_steering": true,
	"drift_assist": true}
const AIDS_VERSION := 2         # settings saved before this (the old car) take the new defaults once
var aids := AIDS_DEFAULT.duplicate()
## Extra tyre grip on top of the real tyres (TireModel.grippy): 0 = REAL, 1 = GRIPPY,
## 1.5 = MORE, 2 = ARCADE (out of the box: grip like a GTA / FiveM rally car, gravel
## nearly as grippy as asphalt; real gravel feels like ice to most players).
var grip_assist := 2.0
const GRIP_VERSION := 2         # saved before this, GRIPPY (the old out of the box) takes ARCADE once
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
		sfx_volume = cf.get_value("audio", "effects", sfx_volume)
		voice_volume = cf.get_value("audio", "voice", voice_volume)
		quick_surface = cf.get_value("stage", "surface", quick_surface)
		var saved_grip := float(cf.get_value("aids", "grip", grip_assist))
		if int(cf.get_value("aids", "grip_version", 1)) >= GRIP_VERSION or saved_grip != 1.0:
			grip_assist = saved_grip
		if int(cf.get_value("aids", "version", 1)) >= AIDS_VERSION:
			for key in aids:
				aids[key] = cf.get_value("aids", key, aids[key])
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("name"):
		player_name = args.name
	if args.has("port"):
		port = int(args.port)
	_buses()


## Two buses into the master: "SFX" (the car, the gravel, crashes, the countdown)
## and "Voice" (the co-driver). The co-driver must always be heard, so while the
## co-driver talks the SFX bus dips (a compressor keyed by the Voice bus), like a rally
## car's intercom over the engine.
func _buses() -> void:
	for n in ["SFX", "Voice"]:                   # (Voice last: buses mix from the last one down,
		if AudioServer.get_bus_index(n) == -1:   # so it's ready when SFX's compressor listens to it)
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, n)
			AudioServer.set_bus_send(i, "Master")
	var sfx := AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var duck := AudioEffectCompressor.new()
		duck.sidechain = "Voice"
		duck.threshold = -32.0                    # any speech ...
		duck.ratio = 4.0                          # ... dips the rest ~10 dB
		duck.attack_us = 8000.0
		duck.release_ms = 400.0                   # and it comes back up gently
		AudioServer.add_bus_effect(sfx, duck)
	apply_volumes()


func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(sfx_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Voice"), linear_to_db(maxf(voice_volume, 0.0001)))


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("player", "name", player_name)
	cf.set_value("net", "last_ip", last_ip)
	cf.set_value("net", "port", port)
	cf.set_value("controls", "mouse_sens", mouse_sens)
	cf.set_value("controls", "invert_y", invert_y)
	cf.set_value("codriver", "call_early", call_early)
	cf.set_value("audio", "volume", volume)
	cf.set_value("audio", "effects", sfx_volume)
	cf.set_value("audio", "voice", voice_volume)
	cf.set_value("stage", "surface", quick_surface)
	for key in aids:
		cf.set_value("aids", key, aids[key])
	cf.set_value("aids", "version", AIDS_VERSION)
	cf.set_value("aids", "grip", grip_assist)
	cf.set_value("aids", "grip_version", GRIP_VERSION)
	cf.save(PATH)


func flag(key: String) -> bool:
	return args.has(key)


func arg(key: String, default = "") -> String:
	return args.get(key, str(default))
