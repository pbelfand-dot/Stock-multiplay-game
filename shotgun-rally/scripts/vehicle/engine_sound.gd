extends Node3D
## The car's engine, done the way markeasting/engine-audio does it (MIT,
## github.com/markeasting/engine-audio: its method, not its recordings): loops
## recorded at known revs, played on the throttle ("on-load") and off it
## ("off-load"), blended by equal-power crossfades on the revs and the throttle
## and pitched to the revs exactly; the limiter bouncing; the gearbox whining.
## The loops are real recordings of a Ford Fiesta WRC (assets/sfx/engine/, made by
## tools/engine_sound/build.py):
##   * idle / mid / high: ~2,915 / ~5,900 / ~7,350 rpm, pulling (on-load)
##   * off-load: the same loops through a low-pass and quieter (engine braking);
##     an anti-lag car's overrun crackle (~6,350 rpm) takes over up the revs
## plus one-shots: an upshift's cut and bang, anti-lag pops.
## Each car's engine type (Catalog "engine": ENGINES) gives it its character:
## how fast it fires for its revs (a five-cylinder 1.25 x a four's), a turbo's
## whistle and blow-off, pops on a lift, a supercharger's whine, how loud a
## straight-cut gearbox whines, the bang on a shift, its tone (an EQ on a bus of
## its own). Lives under the car; reads its rpm (0..1 idle..limiter), throttle,
## gear, speed and boost (on the co-driver's machine, the stream's).

const DIR := "res://assets/sfx/engine/"
const LOOPS := {"idle": 2915.0, "mid": 5900.0, "high": 7350.0}
const OVERRUN_RPM := 6350.0
const POPS := 4

## The engine types. fire: firing pulses per turn x a four-cylinder's (pitch);
## turbo / sc: how loud the turbo's whistle / a supercharger's whine (0: none);
## anti_lag: the overrun crackle off the throttle; pops: how often a lift pops;
## bov: a blow-off valve's hiss on a lift; whine: the gearbox (1: a straight-cut
## rally box, low: a road car's helical one); bang: a shift's cut and bang (a
## sequential); tone: its EQ (TONES).
const ENGINES := {
	"wrc": {"fire": 1.0, "turbo": 0.5, "sc": 0.0, "anti_lag": true, "pops": 1.0, "bov": false, "whine": 1.0, "bang": true, "tone": "rally"},
	"group_a": {"fire": 1.0, "turbo": 0.6, "sc": 0.0, "anti_lag": false, "pops": 0.5, "bov": false, "whine": 0.9, "bang": true, "tone": "rally"},
	"five": {"fire": 1.25, "turbo": 0.8, "sc": 0.0, "anti_lag": false, "pops": 0.8, "bov": false, "whine": 0.9, "bang": true, "tone": "five"},
	"sc4": {"fire": 1.0, "turbo": 0.0, "sc": 1.0, "anti_lag": false, "pops": 0.4, "bov": false, "whine": 0.9, "bang": true, "tone": "rally"},
	"na4_race": {"fire": 1.0, "turbo": 0.0, "sc": 0.0, "anti_lag": false, "pops": 0.25, "bov": false, "whine": 0.7, "bang": false, "tone": "race"},
	"na4": {"fire": 1.0, "turbo": 0.0, "sc": 0.0, "anti_lag": false, "pops": 0.0, "bov": false, "whine": 0.15, "bang": false, "tone": "road"},
	"turbo4": {"fire": 1.0, "turbo": 0.6, "sc": 0.0, "anti_lag": false, "pops": 0.0, "bov": true, "whine": 0.15, "bang": false, "tone": "road"},
	"rotary": {"fire": 1.0, "turbo": 0.5, "sc": 0.0, "anti_lag": false, "pops": 0.2, "bov": true, "whine": 0.15, "bang": false, "tone": "rotary"},
}
## Each tone's EQ (AudioEffectEQ6 bands 32, 100, 320, 1000, 3200, 10000 Hz, dB) and drive
## (an overdrive's: a rotary's rasp). Off-load the same through a low-pass.
const TONES := {
	"rally": {"eq": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "drive": 0.0},
	"road": {"eq": [0.0, 2.0, 1.0, 0.0, -3.0, -6.0], "drive": 0.0},
	"race": {"eq": [0.0, -1.0, 1.0, 2.0, 3.0, 0.0], "drive": 0.0},
	"five": {"eq": [0.0, 2.0, 3.0, -1.0, 0.0, 0.0], "drive": 0.0},
	"rotary": {"eq": [0.0, -2.0, 0.0, 3.0, 2.0, 0.0], "drive": 0.3},
}
const LIMIT_HZ := 11.0          # the limiter's bounce: cut, fire, cut ...

var car
var kind := "wrc"               # the engine type (ENGINES)
var eng: Dictionary = ENGINES.wrc
var throttle := 0.0             # what the engine's being asked (0..1), smoothed
var shares := {}                # loop name -> how much of the sound it is now (tests)
var cut := 0.0                  # the limiter's cut now (0..1: tests)
var pops_fired := 0             # (tests)
var shifts_fired := 0
var bov_fired := 0
var whine_db := -80.0           # the gearbox's whine now (tests)
var whistle_db := -80.0         # the turbo's / supercharger's now (tests)
var _players := {}              # loop name -> AudioStreamPlayer3D ("on_idle", "off_mid", "overrun" ...)
var _whine: AudioStreamPlayer3D
var _whistle: AudioStreamPlayer3D
var _pops: Array = []
var _shift: AudioStream
var _gear := 1
var _recent := 0.0              # the most throttle lately (decays): a lift is from this
var _boost_recent := 0.0
var _lifted := false
var _pop_queue: Array = []      # seconds until each queued pop
var _phase := 0.0
var _rng := RandomNumberGenerator.new()
var _hiss: AudioStreamWAV


func _ready() -> void:
	_rng.randomize()
	if car and car.get("setup") is Dictionary:
		kind = str(car.setup.get("engine", "wrc"))
	eng = ENGINES.get(kind, ENGINES.wrc)
	var on_bus := tone_bus(eng.tone, false)
	var off_bus := tone_bus(eng.tone, true)
	for n in LOOPS:
		_players["on_" + n] = _loop(looped(DIR + "%s.wav" % n), on_bus)
		_players["off_" + n] = _loop(looped(DIR + "%s.wav" % n), off_bus)
	if eng.anti_lag:
		_players["overrun"] = _loop(looped(DIR + "overrun.wav"), on_bus)
	_whine = _loop(tone([1000.0, 2000.0, 3000.0], [1.0, 0.35, 0.15]), on_bus)
	if eng.turbo > 0.0 or eng.sc > 0.0:
		_whistle = _loop(tone([3000.0, 6000.0], [1.0, 0.3]), on_bus)
	for i in POPS:
		_pops.append(load(DIR + "pop%d.wav" % (i + 1)))
	_shift = load(DIR + "shift.wav")


func _loop(s: AudioStream, bus: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.unit_size = 6.0
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	p.play(_rng.randf() * 0.4)                       # (not all in step)
	return p


## A sound file made to loop end to end (its whole length; the game's gravel and
## squeal loops too). The loops are imported uncompressed: they're short, and a
## loop point lands exactly where it's put.
static func looped(path: String) -> AudioStreamWAV:
	var w: AudioStreamWAV = load(path).duplicate()
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = int(round(w.get_length() * w.mix_rate))   # (in samples: data.size() isn't, once it's compressed)
	return w


## A steady tone, made here (a gearbox's whine, a turbo's whistle): these
## frequencies (multiples of 10 Hz: a 0.1 s loop holds whole cycles of each) at
## these strengths, looping.
static func tone(freqs: Array, amps: Array) -> AudioStreamWAV:
	var sr := 44100
	var n := sr / 10
	var total := 0.0
	for a in amps:
		total += float(a)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := 0.0
		for k in freqs.size():
			v += float(amps[k]) * sin(TAU * float(freqs[k]) * float(i) / sr)
		data.encode_s16(i * 2, int(clampf(v / total * 0.7, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


## A blow-off valve's hiss: a burst of high noise dying away (made here).
static func hiss() -> AudioStreamWAV:
	var sr := 44100
	var n := int(sr * 0.45)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var data := PackedByteArray()
	data.resize(n * 2)
	var last := 0.0
	var lp := 0.0
	for i in n:
		var x := rng.randf_range(-1.0, 1.0)
		var hp := x - last                            # (high-passed: the hiss, not a rumble)
		last = x
		lp += (hp - lp) * 0.55
		var t := float(i) / sr
		var env := minf(t / 0.01, 1.0) * exp(-t / 0.12)
		data.encode_s16(i * 2, int(clampf(lp * env * 0.6, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.data = data
	return w


## The bus a tone plays on (made the first time: its EQ, its drive; off-load a
## low-pass after: muffled), sending into SFX (which ducks for the co-driver).
static func tone_bus(t: String, off: bool) -> String:
	var name := "Engine %s%s" % [t, " off" if off else ""]
	if AudioServer.get_bus_index(name) >= 0:
		return name
	var into := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	if off:
		into = tone_bus(t, false)
	AudioServer.add_bus()                              # (at the end: a bus sends to ones before it)
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, into)
	if off:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 1800.0
		AudioServer.add_bus_effect(i, lp)
		return name
	var spec: Dictionary = TONES.get(t, TONES.rally)
	if float(spec.drive) > 0.0:
		var d := AudioEffectDistortion.new()
		d.mode = AudioEffectDistortion.MODE_OVERDRIVE
		d.drive = float(spec.drive)
		d.post_gain = -3.0
		AudioServer.add_bus_effect(i, d)
	var eq := AudioEffectEQ6.new()
	for b in 6:
		eq.set_band_gain_db(b, float(spec.eq[b]))
	AudioServer.add_bus_effect(i, eq)
	return name


## The engine's revs (rpm) from the car's 0..1.
func revs() -> float:
	var e: Resource = car.config.engine if car.config else null
	var idle: float = e.idle_rpm if e else 1000.0
	var top: float = e.limiter_rpm if e else 7600.0
	return idle + float(car.rpm) * (top - idle)


## How much of the sound each loop is at these revs and throttle (0..1 each),
## equal-power crossfades (markeasting's): between neighbouring loops by the revs,
## between on- and off-load by the throttle; off the throttle up the revs an
## anti-lag engine's crackle takes over from the plain engine braking.
static func mix(rpm: float, thr: float, anti_lag := true) -> Dictionary:
	var g := {"idle": 0.0, "mid": 0.0, "high": 0.0}
	if rpm <= LOOPS.mid:
		var x := clampf((rpm - LOOPS.idle) / (LOOPS.mid - LOOPS.idle), 0.0, 1.0)
		g.idle = cos(x * PI * 0.5)
		g.mid = sin(x * PI * 0.5)
	else:
		var y := clampf((rpm - LOOPS.mid) / (LOOPS.high - LOOPS.mid), 0.0, 1.0)
		g.mid = cos(y * PI * 0.5)
		g.high = sin(y * PI * 0.5)
	var t := clampf(thr, 0.0, 1.0)
	var on := sin(t * PI * 0.5)
	var off := cos(t * PI * 0.5)
	var crackle := off * smoothstep(3800.0, 6000.0, rpm) if anti_lag else 0.0
	var plain := sqrt(maxf(off * off - crackle * crackle, 0.0))
	var m := {"overrun": crackle}
	for n in g:
		m["on_" + n] = g[n] * on
		m["off_" + n] = g[n] * plain
	return m


func _process(dt: float) -> void:
	if car == null:
		return
	var rpm := revs()
	var want: float = float(car.inp.throttle) if car.simulate else float(car.net_throttle)
	throttle = move_toward(throttle, want, dt * 8.0)
	# the limiter: flat out against it the engine cuts and fires, LIMIT_HZ a second
	_phase = fmod(_phase + dt * LIMIT_HZ, 1.0)
	var at_limit := smoothstep(0.97, 0.995, float(car.rpm)) * smoothstep(0.4, 0.7, throttle)
	cut = at_limit * (1.0 if _phase > 0.55 else 0.0)
	var heard := rpm * (1.0 - 0.02 * cut)
	shares = mix(heard, throttle * (1.0 - 0.9 * cut), eng.anti_lag)
	var loud := -9.0 + throttle * 4.0
	for n in _players:
		var p: AudioStreamPlayer3D = _players[n]
		var at: float = OVERRUN_RPM if n == "overrun" else LOOPS[n.substr(n.find("_") + 1)]
		p.pitch_scale = clampf(heard * float(eng.fire) / at, 0.5, 2.0)
		var share: float = shares[n]
		var base := -10.0 if n == "overrun" else (loud if n.begins_with("on_") else -13.0)
		p.volume_db = (base + linear_to_db(share)) if share > 0.001 else -80.0
	_drivetrain_sounds(dt, rpm)
	_lifts(rpm)
	# an upshift: on a sequential the cut and the bang as the revs drop (and sometimes a pop)
	var gr: int = int(car.gear)
	if gr > _gear and gr >= 2:
		shifts_fired += 1
		if eng.bang:
			_one_shot(_shift, -4.0, 1.0)
			if _rng.randf() < 0.6 * float(eng.pops):
				_pop_queue.append(0.12)
	_gear = gr
	for i in range(_pop_queue.size() - 1, -1, -1):
		_pop_queue[i] -= dt
		if _pop_queue[i] <= 0.0:
			_pop_queue.remove_at(i)
			pops_fired += 1
			_one_shot(_pops[_rng.randi() % _pops.size()], -6.0 + _rng.randf_range(-3.0, 1.0), _rng.randf_range(0.9, 1.1))


## The gearbox's whine (its pitch with the road speed: a straight-cut box sings,
## louder off the throttle), the turbo's whistle (with the boost) or a
## supercharger's (with the revs).
func _drivetrain_sounds(_dt: float, rpm: float) -> void:
	var v: float = car.linear_velocity.length()
	var w: float = float(eng.whine) * smoothstep(3.0, 12.0, v) * lerpf(0.75, 1.0, 1.0 - throttle)
	whine_db = (-24.0 + linear_to_db(w)) if w > 0.002 else -80.0
	_whine.volume_db = whine_db
	_whine.pitch_scale = clampf(v * 0.045, 0.1, 3.0)
	if _whistle == null:
		return
	var boost := _boost()
	if float(eng.sc) > 0.0:
		var s: float = float(eng.sc) * (0.35 + 0.65 * throttle) * smoothstep(1500.0, 3500.0, rpm)
		whistle_db = (-30.0 + linear_to_db(s)) if s > 0.002 else -80.0
		_whistle.pitch_scale = clampf(rpm * 0.35 / 3000.0, 0.2, 3.0)
	else:
		var b: float = float(eng.turbo) * boost * boost
		whistle_db = (-30.0 + linear_to_db(b)) if b > 0.002 else -80.0
		_whistle.pitch_scale = 0.7 + 0.8 * boost
	_whistle.volume_db = whistle_db


## The turbo's boost (0..1): the drivetrain's (the driver's machine), else the
## throttle up the revs (the co-driver's, from the stream).
func _boost() -> float:
	if car.simulate and car.get("drivetrain") and car.drivetrain:
		return float(car.drivetrain.boost)
	return throttle * smoothstep(0.3, 0.7, float(car.rpm))


## Lifting off at high revs: an anti-lag car pops (others, as often as their
## engine does); a road turbo's blow-off valve hisses.
func _lifts(rpm: float) -> void:
	_recent = maxf(_recent - get_process_delta_time() * 1.5, throttle)
	_boost_recent = maxf(_boost_recent - get_process_delta_time() * 1.5, _boost())
	if throttle > 0.5:
		_lifted = false
	if _lifted or _recent <= 0.6 or throttle >= 0.2:
		return
	_lifted = true
	if eng.bov and _boost_recent > 0.4:
		bov_fired += 1
		if _hiss == null:
			_hiss = hiss()
		_one_shot(_hiss, -10.0, _rng.randf_range(0.95, 1.08))
	if rpm > 5000.0 and _rng.randf() < float(eng.pops):
		for i in _rng.randi_range(1, maxi(1, int(ceil(3.0 * float(eng.pops))))):
			_pop_queue.append(0.03 + i * _rng.randf_range(0.06, 0.14))


func _one_shot(s: AudioStream, db: float, pitch: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.unit_size = 6.0
	p.bus = tone_bus(eng.tone, false)
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
