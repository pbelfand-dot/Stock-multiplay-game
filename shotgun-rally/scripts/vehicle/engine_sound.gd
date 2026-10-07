extends Node3D
## The car's engine: markeasting/engine-audio's engine sounds and the way it
## plays them (github.com/markeasting/engine-audio, MIT code; the recordings
## came with it: see tools/engine_sound/README.md for the licence note). Each set
## is four loops, on the throttle ("on-load") and off it ("off-load"), low and
## high in the revs, plus a limiter loop. Equal-power crossfades blend low into
## high between 3,000 and 6,500 rpm and on into off with the throttle, and each
## loop is pitched 0.2 cents per rpm away from the revs it was recorded at (all
## markeasting's numbers). The limiter loop comes in over the last 8 % of the revs
## (and the engine cuts and fires against it, LIMIT_HZ). A gearbox whine, from
## its samples, rises with the revs and the gear, louder off the throttle.
## Sets (ENGINES: each car's engine type picks one):
##   * "four": a BAC Mono's racing four-cylinder (the four-cylinder cars)
##   * "six": a BMW M1 Procar's straight six (the five-cylinder quattro: the
##     nearest)
##   * "v8": a Ferrari 458's (the RX-7s' rotaries: a high-revving scream)
## On top, from the Fiesta WRC recordings (tools/engine_sound/): an anti-lag
## engine's overrun crackle and pops, a sequential's shift bang; made in code: a
## turbo's whistle, a supercharger's whine, a road turbo's blow-off; and for an
## electric car none of the sets but its motor's whine and inverter's tone. Each car's
## engine type (Catalog "engine": ENGINES) also sets its tone (an EQ on a bus of
## its own). Lives under the car; reads its rpm (0..1 idle..limiter), throttle,
## gear and boost (on the co-driver's machine, the stream's).

const DIR := "res://assets/sfx/engine/"
const OVERRUN_RPM := 6350.0
const POPS := 4
## Each set's loops: the revs each was recorded at (markeasting's configurations).
const SETS := {
	"four": {"dir": "bac", "on_low": 1000.0, "on_high": 1000.0, "off_low": 1000.0, "off_high": 1000.0, "limiter": "bac"},
	"six": {"dir": "procar", "on_low": 3200.0, "on_high": 8000.0, "off_low": 3400.0, "off_high": 8430.0, "limiter": "bac"},
	"v8": {"dir": "v8", "on_low": 5300.0, "on_high": 7700.0, "off_low": 6900.0, "off_high": 7900.0, "limiter": "v8"},
}
const LOW_HIGH := [3000.0, 6500.0]  # the revs the low loops hand over to the high ones
const CENTS_PER_RPM := 0.2

## The engine types. set: its loops (SETS); turbo / sc: how loud the turbo's
## whistle / a supercharger's whine (0: none); anti_lag: the overrun crackle off
## the throttle; pops: how often a lift pops; bov: a blow-off valve's hiss on a
## lift; whine: the gearbox (1: a straight-cut rally box, low: a road car's
## helical one); bang: a shift's cut and bang (a sequential); tone: its EQ (TONES).
const ENGINES := {
	"wrc": {"set": "four", "turbo": 0.5, "sc": 0.0, "anti_lag": true, "pops": 1.0, "bov": false, "whine": 1.0, "bang": true, "tone": "rally"},
	"group_a": {"set": "four", "turbo": 0.6, "sc": 0.0, "anti_lag": false, "pops": 0.5, "bov": false, "whine": 0.9, "bang": true, "tone": "rally"},
	"five": {"set": "six", "turbo": 0.8, "sc": 0.0, "anti_lag": false, "pops": 0.8, "bov": false, "whine": 0.9, "bang": true, "tone": "five"},
	"sc4": {"set": "four", "turbo": 0.0, "sc": 1.0, "anti_lag": false, "pops": 0.4, "bov": false, "whine": 0.9, "bang": true, "tone": "rally"},
	"na4_race": {"set": "four", "turbo": 0.0, "sc": 0.0, "anti_lag": false, "pops": 0.25, "bov": false, "whine": 0.7, "bang": false, "tone": "race"},
	"na4": {"set": "four", "turbo": 0.0, "sc": 0.0, "anti_lag": false, "pops": 0.0, "bov": false, "whine": 0.15, "bang": false, "tone": "road"},
	"turbo4": {"set": "four", "turbo": 0.6, "sc": 0.0, "anti_lag": false, "pops": 0.0, "bov": true, "whine": 0.15, "bang": false, "tone": "road"},
	"rotary": {"set": "v8", "turbo": 0.5, "sc": 0.0, "anti_lag": false, "pops": 0.2, "bov": true, "whine": 0.15, "bang": false, "tone": "rotary"},
	# American V8s: the V8 loops pitched down to their low revs, the muscle tone's bass;
	# the supercharged one with its blower's whine on top
	"v8_sc": {"set": "v8", "turbo": 0.0, "sc": 1.0, "anti_lag": false, "pops": 0.3, "bov": false, "whine": 0.15, "bang": false, "tone": "muscle"},
	"v8": {"set": "v8", "turbo": 0.0, "sc": 0.0, "anti_lag": false, "pops": 0.25, "bov": false, "whine": 0.15, "bang": false, "tone": "muscle"},
	# straight sixes, on the Procar's six: a racing-bred twin-cam, a modern road turbo
	"i6_race": {"set": "six", "turbo": 0.0, "sc": 0.0, "anti_lag": false, "pops": 0.3, "bov": false, "whine": 0.3, "bang": false, "tone": "race"},
	"i6_turbo": {"set": "six", "turbo": 0.45, "sc": 0.0, "anti_lag": false, "pops": 0.15, "bov": true, "whine": 0.15, "bang": false, "tone": "road"},
	# a European twin-turbo V8 (RS 6, M5/M8, AMG): the V8 loops, a turbo's hush, a fuller road tone
	"v8_turbo": {"set": "v8", "turbo": 0.35, "sc": 0.0, "anti_lag": false, "pops": 0.3, "bov": false, "whine": 0.15, "bang": false, "tone": "v8_road"},
	# an F1-derived turbo-hybrid V6 (AMG ONE): the 458's high-revving loops, a turbo's whistle,
	# a racing gearbox's whine and the race tone
	"f1_hybrid": {"set": "v8", "turbo": 0.6, "sc": 0.0, "anti_lag": false, "pops": 0.2, "bov": false, "whine": 0.6, "bang": true, "tone": "race"},
	# an electric car (Honda e): no engine at all. Its motor's whine (made here: a few
	# harmonics, rising with its revs, louder pulling than coasting on the regen), the
	# inverter's faint high tone and the single-speed reduction gear's hum (the whine)
	"ev": {"set": "", "electric": true, "turbo": 0.0, "sc": 0.0, "anti_lag": false, "pops": 0.0, "bov": false, "whine": 0.35, "bang": false, "tone": "road"},
}
## Each tone's EQ (AudioEffectEQ6 bands 32, 100, 320, 1000, 3200, 10000 Hz, dB).
const TONES := {
	"rally": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	"road": [0.0, 2.0, 1.0, 0.0, -2.0, -4.0],
	"race": [0.0, -1.0, 1.0, 2.0, 2.0, 0.0],
	"five": [0.0, 2.0, 2.0, 0.0, 0.0, 0.0],
	"rotary": [0.0, -2.0, 0.0, 2.0, 2.0, 0.0],
	"muscle": [3.0, 4.0, 1.5, -1.0, -2.5, -4.0],
	"v8_road": [1.5, 3.0, 1.0, 0.0, -1.5, -3.0],
}
const LIMIT_HZ := 11.0          # the limiter's bounce: cut, fire, cut ...

var car
var kind := "wrc"               # the engine type (ENGINES)
var eng: Dictionary = ENGINES.wrc
var loops: Dictionary = SETS.four
var throttle := 0.0             # what the engine's being asked (0..1), smoothed
var shares := {}                # loop name -> how much of the sound it is now (tests)
var cut := 0.0                  # the limiter's cut now (0..1: tests)
var limiter_share := 0.0        # the limiter loop now (tests)
var pops_fired := 0             # (tests)
var shifts_fired := 0
var bov_fired := 0
var whine_db := -80.0           # the gearbox's whine now (tests)
var whistle_db := -80.0         # the turbo's / supercharger's now (tests)
var motor_db := -80.0           # an electric car's motor whine now (tests)
var _players := {}              # loop name -> AudioStreamPlayer3D ("on_low", "off_high", "overrun")
var _limiter: AudioStreamPlayer3D
var _gear_on: AudioStreamPlayer3D
var _gear_off: AudioStreamPlayer3D
var _whistle: AudioStreamPlayer3D
var _motor: AudioStreamPlayer3D        # (an electric car's: its motor and its inverter)
var _inverter: AudioStreamPlayer3D
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
	loops = SETS.get(eng.set, {"dir": "ev"})
	var bus := tone_bus(eng.tone)
	_gear_on = _loop(looped(DIR + "gearbox/on.wav"), bus)
	_gear_off = _loop(looped(DIR + "gearbox/off.wav"), bus)
	if eng.get("electric", false):
		_motor = _loop(tone([300.0, 600.0, 900.0, 1500.0], [1.0, 0.55, 0.3, 0.15]), bus)
		_inverter = _loop(tone([4800.0], [1.0]), bus)
		return
	for n in ["on_low", "on_high", "off_low", "off_high"]:
		_players[n] = _loop(looped(DIR + "%s/%s.wav" % [loops.dir, n]), bus)
	if eng.anti_lag:
		_players["overrun"] = _loop(looped(DIR + "overrun.wav"), bus)
	_limiter = _loop(looped(DIR + "%s/limiter.wav" % loops.limiter), bus)
	if eng.turbo > 0.0 or eng.sc > 0.0:
		_whistle = _loop(tone([3000.0, 6000.0], [1.0, 0.3]), bus)
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


## The bus a tone plays on (made the first time: its EQ), sending into SFX
## (which ducks for the co-driver).
static func tone_bus(t: String) -> String:
	var name := "Engine " + t
	if AudioServer.get_bus_index(name) >= 0:
		return name
	AudioServer.add_bus()                              # (at the end: a bus sends to ones before it)
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master")
	var eq := AudioEffectEQ6.new()
	var gains: Array = TONES.get(t, TONES.rally)
	for k in 6:
		eq.set_band_gain_db(k, float(gains[k]))
	AudioServer.add_bus_effect(i, eq)
	return name


## The engine's revs (rpm) from the car's 0..1.
func revs() -> float:
	var e: Resource = car.config.engine if car.config else null
	var idle: float = e.idle_rpm if e else 1000.0
	var top: float = e.limiter_rpm if e else 7600.0
	return idle + float(car.rpm) * (top - idle)


## How much of the sound each loop is at these revs and throttle (0..1 each):
## markeasting's equal-power crossfades, low into high between LOW_HIGH and on-
## into off-load with the throttle; off the throttle up the revs an anti-lag
## engine's crackle takes over from the plain off-load loops.
static func mix(rpm: float, thr: float, anti_lag := true) -> Dictionary:
	var x := clampf((rpm - LOW_HIGH[0]) / (LOW_HIGH[1] - LOW_HIGH[0]), 0.0, 1.0)
	var high := sin(x * PI * 0.5)
	var low := cos(x * PI * 0.5)
	var t := clampf(thr, 0.0, 1.0)
	var on := sin(t * PI * 0.5)
	var off := cos(t * PI * 0.5)
	var crackle := off * smoothstep(3800.0, 6000.0, rpm) if anti_lag else 0.0
	var plain := sqrt(maxf(off * off - crackle * crackle, 0.0))
	return {"on_low": on * low, "on_high": on * high, "off_low": plain * low, "off_high": plain * high, "overrun": crackle}


## A loop's pitch at these revs: 0.2 cents per rpm away from the revs it was
## recorded at (markeasting's detune).
static func pitch_at(rpm: float, recorded: float) -> float:
	return clampf(pow(2.0, (rpm - recorded) * CENTS_PER_RPM / 1200.0), 0.5, 2.5)


func _process(dt: float) -> void:
	if car == null:
		return
	var rpm := revs()
	var want: float = float(car.inp.throttle) if car.simulate else float(car.net_throttle)
	throttle = move_toward(throttle, want, dt * 8.0)
	if _motor:
		_electric(dt, rpm)
		return
	# the limiter: flat out against it the engine cuts and fires, LIMIT_HZ a second,
	# and its loop comes in over the last 8 % of the revs
	_phase = fmod(_phase + dt * LIMIT_HZ, 1.0)
	var at_limit := smoothstep(0.97, 0.995, float(car.rpm)) * smoothstep(0.4, 0.7, throttle)
	cut = at_limit * (1.0 if _phase > 0.55 else 0.0)
	shares = mix(rpm, throttle * (1.0 - 0.9 * cut), eng.anti_lag)
	var loud := -9.0 + throttle * 4.0
	for n in _players:
		var p: AudioStreamPlayer3D = _players[n]
		p.pitch_scale = clampf(rpm / OVERRUN_RPM, 0.5, 2.0) if n == "overrun" else pitch_at(rpm, float(loops[n]))
		var share: float = shares[n]
		var base := -10.0 if n == "overrun" else (loud if n.begins_with("on_") else -12.0)
		p.volume_db = (base + linear_to_db(share)) if share > 0.001 else -80.0
	var e: Resource = car.config.engine if car.config else null
	var top: float = e.limiter_rpm if e else 7600.0
	limiter_share = clampf((rpm - top * 0.92) / (top * 0.08), 0.0, 1.0) * smoothstep(0.3, 0.6, throttle)
	_limiter.volume_db = (-12.0 + linear_to_db(limiter_share)) if limiter_share > 0.001 else -80.0
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


## An electric car: the motor's whine up with its revs (silent standing still, a
## quarter as loud coasting as pulling), the inverter's tone faintly over it, and
## the reduction gear's whine. No limiter, no shifts, no pops.
func _electric(dt: float, rpm: float) -> void:
	var x := clampf(float(car.rpm), 0.0, 1.0)
	var m := (0.25 + 0.75 * throttle) * smoothstep(0.0, 0.08, x)
	_motor.pitch_scale = 0.25 + 2.0 * x
	motor_db = (-20.0 + linear_to_db(m)) if m > 0.002 else -80.0
	_motor.volume_db = motor_db
	_inverter.pitch_scale = 0.9 + 0.2 * x
	_inverter.volume_db = (-40.0 + 6.0 * throttle) if m > 0.002 else -80.0
	_drivetrain_sounds(dt, rpm)


## The gearbox's whine (markeasting's: its pitch up with the revs and the gear's
## ratio, on- and off-load samples; a straight-cut rally box loud, a road car's
## helical one barely), the turbo's whistle (with the boost) or a supercharger's
## (with the revs).
func _drivetrain_sounds(_dt: float, rpm: float) -> void:
	var g: int = int(car.gear)
	var ratio := 0.0
	var d: Resource = car.config.drivetrain if car.config else null
	if d and g >= 1 and g <= d.gear_ratios.size():
		ratio = float(d.gear_ratios[g - 1])
	var on := sin(throttle * PI * 0.5)
	var off := cos(throttle * PI * 0.5)
	var moving := smoothstep(1.0, 4.0, car.linear_velocity.length())
	var w_on: float = float(eng.whine) * on * moving * (1.0 if ratio > 0.0 else 0.0)
	var w_off: float = float(eng.whine) * off * moving * (1.0 if ratio > 0.0 else 0.0)
	_gear_on.pitch_scale = clampf(pow(2.0, (rpm * ratio * 0.05 - 100.0) / 1200.0), 0.3, 3.0)
	_gear_off.pitch_scale = clampf(pow(2.0, (rpm * ratio * 0.035 - 800.0) / 1200.0), 0.3, 3.0)
	_gear_on.volume_db = (-17.0 + linear_to_db(w_on)) if w_on > 0.002 else -80.0
	_gear_off.volume_db = (-15.0 + linear_to_db(w_off)) if w_off > 0.002 else -80.0
	whine_db = maxf(_gear_on.volume_db, _gear_off.volume_db)
	if _whistle == null:
		return
	var boost := _boost()
	if float(eng.sc) > 0.0:
		var sc: float = float(eng.sc) * (0.35 + 0.65 * throttle) * smoothstep(1500.0, 3500.0, rpm)
		whistle_db = (-30.0 + linear_to_db(sc)) if sc > 0.002 else -80.0
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
	p.bus = tone_bus(eng.tone)
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
