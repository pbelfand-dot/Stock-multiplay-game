extends SceneTree
## The sound: the engine (engine_sound.gd: four loops from real recordings,
## blended by the revs) and the mix (Config's buses).
##   * the blend: at each loop's own revs it's all that loop; off the throttle at
##     high revs the anti-lag crackle takes over
##   * driving: flat out on a pad it changes up (a shift sound each time), lifting
##     at high revs pops, every loop's pitch stays in range
##   * the mix: an SFX and a Voice bus, and the SFX dips when the co-driver talks
##     (a compressor on SFX keyed by Voice); the engine plays on SFX, the
##     co-driver on Voice
## Run: godot --headless --fixed-fps 120 --path . -s tests/sound_check.gd

var RallyCar
var EngineSound
var car
var snd
var t := 0.0
var fails := 0
var peak_pitch := 0.0
var low_pitch := INF
var max_over := 0.0


func _initialize() -> void:
	RallyCar = load("res://scripts/vehicle/rally_car.gd")
	EngineSound = load("res://scripts/vehicle/engine_sound.gd")
	var m: Dictionary = EngineSound.mix(2915.0, 1.0)
	fails += _check(m.idle > 0.99 and m.mid < 0.01, "at 2,915 rpm on the throttle it's all the idle loop (%.2f)" % m.idle)
	m = EngineSound.mix(5900.0, 1.0)
	fails += _check(m.mid > 0.99 and m.idle < 0.01 and m.high < 0.01, "at 5,900 rpm, all the mid loop (%.2f)" % m.mid)
	m = EngineSound.mix(7350.0, 1.0)
	fails += _check(m.high > 0.99, "at 7,350 rpm, all the high loop (%.2f)" % m.high)
	m = EngineSound.mix(6500.0, 0.0)
	fails += _check(m.overrun > 0.95 and m.high < 0.4, "off the throttle at 6,500 rpm, the anti-lag crackle (%.2f, high %.2f)" % [m.overrun, m.high])
	var pad := StaticBody3D.new()
	pad.set_meta("surface", "gravel")
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(800, 2, 3000)
	cs.shape = bx
	pad.add_child(cs)
	pad.position = Vector3(0, -1, 0)
	root.add_child(pad)
	car = RallyCar.new()
	root.add_child(car)
	car.place(Vector3(0, 0, 1400), 0.0)
	snd = EngineSound.new()
	snd.car = car
	car.add_child(snd)


func _physics_process(dt: float) -> bool:
	t += dt
	car.inp = {"steer": 0.0, "throttle": 1.0 if t > 0.5 and t < 7.0 else 0.0, "brake": 0.0, "handbrake": false}
	if snd.shares.is_empty():
		return false
	for p in snd.get_children():
		if p is AudioStreamPlayer3D and p.stream is AudioStreamWAV and p.stream.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			peak_pitch = maxf(peak_pitch, p.pitch_scale)
			low_pitch = minf(low_pitch, p.pitch_scale)
	if t > 7.0:
		max_over = maxf(max_over, snd.shares.overrun)
	if t > 8.5:
		fails += _check(snd.shifts_fired >= 2, "flat out from a standstill for 6.5 s: %d upshifts sounded (gear %d)" % [snd.shifts_fired, car.gear])
		fails += _check(snd.pops_fired >= 1, "lifting at high revs: %d anti-lag pops" % snd.pops_fired)
		fails += _check(max_over > 0.5, "off the throttle at high revs the crackle comes in (%.2f of the sound)" % max_over)
		fails += _check(low_pitch >= 0.5 and peak_pitch <= 2.0, "every loop's pitch stayed in range (%.2f .. %.2f)" % [low_pitch, peak_pitch])
		var sfx := AudioServer.get_bus_index("SFX")
		var voice := AudioServer.get_bus_index("Voice")
		var duck: AudioEffect = AudioServer.get_bus_effect(sfx, 0) if sfx >= 0 and AudioServer.get_bus_effect_count(sfx) > 0 else null
		fails += _check(sfx > 0 and voice > 0 and duck is AudioEffectCompressor and duck.sidechain == "Voice",
			"an SFX and a Voice bus; the SFX dips while the co-driver talks (compressor keyed by Voice)")
		var on_sfx := true
		for p in snd.get_children():
			if p is AudioStreamPlayer3D:
				on_sfx = on_sfx and p.bus == "SFX"
		var AiCodriver = load("res://scripts/vehicle/ai_codriver.gd")
		var ai = AiCodriver.new()
		root.add_child(ai)
		var voice_ok: bool = ai._player != null and ai._player.bus == "Voice"
		fails += _check(on_sfx and voice_ok, "the engine plays on SFX, the co-driver on Voice")
		print("[sound] %s" % ("SOUND OK" if fails == 0 else "SOUND FAIL"))
		quit(1 if fails > 0 else 0)
		return true
	return false


func _check(ok: bool, msg: String) -> int:
	print("[sound] %s %s" % ["ok  " if ok else "FAIL", msg])
	return 0 if ok else 1
