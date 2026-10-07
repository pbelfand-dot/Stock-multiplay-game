extends SceneTree
## The sound: the engine (engine_sound.gd: markeasting/engine-audio's sounds,
## played its way, each car's engine type its own set and character) and the
## mix (Config's buses).
##   * the loops (the engine's, the gravel, the asphalt squeal) play their whole
##     length, end to end
##   * the blend: low loops below 3,000 rpm, high ones above 6,500, on-load on
##     the throttle and off-load off it, an anti-lag car's crackle up the revs off
##     it; equal power all the way (the shares' squares add up to 1); a loop's
##     pitch 0.2 cents per rpm from the revs it was recorded at
##   * driving (the KESTREL, a WRC-type engine): flat out on a pad it changes up (a
##     shift sound each time), lifting at high revs pops, every loop's pitch stays
##     in range
##   * each engine type, on a stand-in car: its own set (the fours a racing four,
##     the quattro a straight six, the rotaries the V8); the limiter bounces and its
##     loop comes in; a rally box whines and a road car's barely; a turbo whistles
##     with the boost and a supercharger with the revs; a road turbo hisses
##     (blow-off) on a lift and an anti-lag car pops while a road four doesn't
##   * the mix: an SFX and a Voice bus, and the SFX dips when the co-driver talks
##     (a compressor keyed by Voice); the engine plays into SFX (its tone's bus),
##     the co-driver on Voice
## Run: godot --headless --fixed-fps 120 --path . -s tests/sound_check.gd

## A stand-in car: just what EngineSound reads, set by the test.
class FakeCar extends Node3D:
	var config: Resource
	var rpm := 0.5
	var inp := {"throttle": 0.0}
	var simulate := true
	var net_throttle := 0.0
	var gear := 3
	var linear_velocity := Vector3.ZERO
	var setup := {}
	var drivetrain = null


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
	var m: Dictionary = EngineSound.mix(2500.0, 1.0)
	fails += _check(m.on_low > 0.99 and m.on_high < 0.01, "at 2,500 rpm on the throttle it's all the low on-load loop (%.2f)" % m.on_low)
	m = EngineSound.mix(7000.0, 1.0)
	fails += _check(m.on_high > 0.99 and m.on_low < 0.01, "at 7,000 rpm, all the high on-load loop (%.2f)" % m.on_high)
	m = EngineSound.mix(6500.0, 0.0)
	fails += _check(m.overrun > 0.95 and m.on_high < 0.05, "off the throttle at 6,500 rpm, the anti-lag crackle (%.2f, on-load %.2f)" % [m.overrun, m.on_high])
	m = EngineSound.mix(7000.0, 0.0, false)
	fails += _check(m.overrun == 0.0 and m.off_high > 0.99, "... without anti-lag, the high off-load loop (%.2f)" % m.off_high)
	var p1: float = EngineSound.pitch_at(1000.0, 1000.0)
	var p2: float = EngineSound.pitch_at(7000.0, 1000.0)
	fails += _check(absf(p1 - 1.0) < 0.001 and absf(p2 - 2.0) < 0.001, "a loop's pitch: as recorded at its own revs (%.2f), an octave up 6,000 rpm above (%.2f)" % [p1, p2])
	var worst := 0.0
	for r in [1500.0, 3500.0, 5000.0, 6500.0, 8000.0]:
		for th in [0.0, 0.3, 0.7, 1.0]:
			for al in [true, false]:
				var mm: Dictionary = EngineSound.mix(r, th, al)
				var e := 0.0
				for k in mm:
					e += mm[k] * mm[k]
				worst = maxf(worst, absf(e - 1.0))
	fails += _check(worst < 0.02, "equal power: the shares' squares add up to 1 everywhere (worst off by %.3f)" % worst)
	# every loop plays its whole length (a compressed import once looped just its first fifth)
	var whole := true
	var info := []
	for n in ["engine/bac/on_low", "engine/bac/on_high", "engine/bac/off_low", "engine/bac/off_high", "engine/procar/on_high",
			"engine/v8/on_high", "engine/gearbox/on", "engine/overrun", "gravel", "squeal"]:
		var w: AudioStreamWAV = EngineSound.looped("res://assets/sfx/%s.wav" % n)
		var samples := int(round(w.get_length() * w.mix_rate))
		whole = whole and w.loop_mode == AudioStreamWAV.LOOP_FORWARD and w.loop_begin == 0 and w.loop_end == samples and samples > 1000
		info.append("%s %.2f s" % [n.trim_prefix("engine/"), float(w.loop_end) / w.mix_rate])
	fails += _check(whole, "every loop plays end to end (%s)" % ", ".join(info))
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
	for p in snd._players.values():                  # (the engine's loops: not the whine's or the whistle's tone)
		peak_pitch = maxf(peak_pitch, p.pitch_scale)
		low_pitch = minf(low_pitch, p.pitch_scale)
	if t > 7.0:
		max_over = maxf(max_over, snd.shares.get("overrun", 0.0))
	if t > 8.5:
		fails += _check(snd.shifts_fired >= 2, "flat out from a standstill for 6.5 s: %d upshifts sounded (gear %d)" % [snd.shifts_fired, car.gear])
		fails += _check(snd.pops_fired >= 1, "lifting at high revs: %d anti-lag pops" % snd.pops_fired)
		fails += _check(max_over > 0.5, "off the throttle at high revs the crackle comes in (%.2f of the sound)" % max_over)
		fails += _check(low_pitch >= 0.5 and peak_pitch <= 2.5, "every loop's pitch stayed in range (%.2f .. %.2f)" % [low_pitch, peak_pitch])
		var sfx := AudioServer.get_bus_index("SFX")
		var voice := AudioServer.get_bus_index("Voice")
		var duck: AudioEffect = AudioServer.get_bus_effect(sfx, 0) if sfx >= 0 and AudioServer.get_bus_effect_count(sfx) > 0 else null
		fails += _check(sfx > 0 and voice > 0 and duck is AudioEffectCompressor and duck.sidechain == "Voice",
			"an SFX and a Voice bus; the SFX dips while the co-driver talks (compressor keyed by Voice)")
		var on_sfx := true
		for p in snd.get_children():
			if p is AudioStreamPlayer3D:
				on_sfx = on_sfx and _into_sfx(p.bus)
		var AiCodriver = load("res://scripts/vehicle/ai_codriver.gd")
		var ai = AiCodriver.new()
		root.add_child(ai)
		var voice_ok: bool = ai._player != null and ai._player.bus == "Voice"
		fails += _check(on_sfx and voice_ok, "the engine plays into SFX (its tone's bus), the co-driver on Voice")
		_types()
		print("[sound] %s" % ("SOUND OK" if fails == 0 else "SOUND FAIL"))
		quit(1 if fails > 0 else 0)
		return true
	return false


## A bus that ends up in SFX.
func _into_sfx(bus: String) -> bool:
	var n := bus
	for i in 4:
		if n == "SFX":
			return true
		var k := AudioServer.get_bus_index(n)
		if k < 0:
			return false
		n = AudioServer.get_bus_send(k)
	return false


## An engine type on a stand-in car: `frames` ticks of 1/60 s at these revs (0..1),
## throttle and speed, after `lift_after` ticks the throttle off.
func _drive(kind: String, rpm: float, thr: float, speed: float, frames: int, lift_after := -1) -> Dictionary:
	var fc := FakeCar.new()
	fc.config = load("res://scripts/vehicle/car_specs.gd").config("")
	fc.setup = {"engine": kind}
	fc.simulate = false
	fc.rpm = rpm
	fc.linear_velocity = Vector3(0, 0, -speed)
	root.add_child(fc)
	var s = EngineSound.new()
	s.car = fc
	fc.add_child(s)
	var out := {"cut_on": 0, "cut_off": 0, "whine": -80.0, "whistle": -80.0, "limiter": 0.0, "set": s.loops.dir, "motor": -80.0}
	for f in frames:
		var th := 0.0 if lift_after >= 0 and f >= lift_after else thr
		fc.net_throttle = th
		fc.inp.throttle = th
		s._process(1.0 / 60.0)
		if f > 30 and (lift_after < 0 or f < lift_after):
			if s.cut > 0.5:
				out.cut_on += 1
			else:
				out.cut_off += 1
			out.whine = maxf(out.whine, s.whine_db)
			out.whistle = maxf(out.whistle, s.whistle_db)
			out.limiter = maxf(out.limiter, s.limiter_share)
			out.motor = maxf(out.motor, s.motor_db)
	out.motor_pitch = s._motor.pitch_scale if s._motor else 0.0
	out.pops = s.pops_fired + s._pop_queue.size()
	out.bov = s.bov_fired
	out.overrun = s._players.has("overrun")
	fc.free()
	return out


func _types() -> void:
	var sets := []
	var right := true
	for k in [["wrc", "bac"], ["na4", "bac"], ["five", "procar"], ["rotary", "v8"]]:
		var d := _drive(k[0], 0.5, 0.5, 10.0, 2)
		sets.append("%s %s" % [k[0], d.set])
		right = right and d.set == k[1]
	fails += _check(right, "each engine type its own set: %s" % ", ".join(sets))
	var lim := _drive("wrc", 1.0, 1.0, 30.0, 120)
	fails += _check(lim.cut_on > 10 and lim.cut_off > 10 and lim.limiter > 0.9,
		"flat out on the limiter it bounces (cut %d ticks, firing %d of 89) and the limiter loop is in (%.2f)" % [lim.cut_on, lim.cut_off, lim.limiter])
	var road := _drive("na4", 0.6, 1.0, 30.0, 60)
	fails += _check(lim.whine > -30.0 and road.whine < lim.whine - 12.0,
		"at 108 km/h a rally box whines (%.0f dB) and a road car's helical box barely (%.0f dB)" % [lim.whine, road.whine])
	var turbo := _drive("wrc", 0.8, 1.0, 20.0, 60)
	var sc := _drive("sc4", 0.8, 1.0, 20.0, 60)
	var na := _drive("na4", 0.8, 1.0, 20.0, 60)
	fails += _check(turbo.whistle > -45.0 and sc.whistle > -45.0 and na.whistle <= -80.0,
		"the turbo whistles on boost (%.0f dB), the 037's supercharger with the revs (%.0f dB), a road four neither" % [turbo.whistle, sc.whistle])
	var bov := _drive("turbo4", 0.9, 1.0, 25.0, 140, 90)
	var als := _drive("wrc", 0.9, 1.0, 25.0, 140, 90)
	var quiet := _drive("na4", 0.9, 1.0, 25.0, 140, 90)
	fails += _check(bov.bov == 1 and als.pops >= 1 and quiet.pops == 0 and quiet.bov == 0 and not quiet.overrun,
		"a lift at high revs: the S15's blow-off hisses (%d), an anti-lag car pops (%d), the road four does neither (%d pops) and has no crackle" % [bov.bov, als.pops, quiet.pops])
	var ev_lo := _drive("ev", 0.2, 1.0, 8.0, 60)
	var ev_hi := _drive("ev", 1.0, 1.0, 40.0, 120)
	var ev_coast := _drive("ev", 0.6, 0.0, 25.0, 60)
	fails += _check(ev_hi.set == "ev" and ev_hi.cut_on == 0 and ev_hi.limiter == 0.0 and ev_hi.pops == 0
		and ev_hi.motor_pitch > ev_lo.motor_pitch * 2.0 and ev_hi.motor > -30.0 and ev_coast.motor < ev_hi.motor - 6.0,
		"an electric car: no engine, no limiter (%.2f), no pops; its motor whines up with its revs (pitch x%.2f to x%.2f, %.0f dB), quieter coasting (%.0f dB)" % [
		ev_hi.limiter, ev_lo.motor_pitch, ev_hi.motor_pitch, ev_hi.motor, ev_coast.motor])


func _check(ok: bool, msg: String) -> int:
	print("[sound] %s %s" % ["ok  " if ok else "FAIL", msg])
	return 0 if ok else 1
