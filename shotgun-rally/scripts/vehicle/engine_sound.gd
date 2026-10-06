extends Node3D
## The car's engine, from real recordings of a Ford Fiesta WRC (assets/sfx/engine/,
## made by tools/engine_sound/build.py): four loops, each at a known rpm, blended
## by the revs and pitched to match them exactly, the way racing games do it:
##   * idle: the car on a start line, its anti-lag idle (~2,915 rpm)
##   * mid / high: pulling through a gear flat out (~5,900 / ~7,350 rpm)
##   * overrun: off the throttle at high revs, the anti-lag crackle (~6,350 rpm)
## plus one-shots: an upshift (the cut and the bang as the revs drop) and
## anti-lag pops when you lift at high revs. Lives under the car; reads its rpm
## (0..1 idle..limiter), throttle and gear (on the co-driver's machine, the stream's).

const DIR := "res://assets/sfx/engine/"
const LOOPS := {"idle": 2915.0, "mid": 5900.0, "high": 7350.0, "overrun": 6350.0}
const POPS := 4

var car
var throttle := 0.0             # what the engine's being asked (0..1), smoothed
var shares := {}                # loop name -> how much of the sound it is now (tests)
var pops_fired := 0             # (tests)
var shifts_fired := 0
var _players := {}              # loop name -> AudioStreamPlayer3D
var _pops: Array = []
var _shift: AudioStream
var _gear := 1
var _recent := 0.0              # the most throttle lately (decays): a lift is from this
var _lifted := false
var _pop_queue: Array = []      # seconds until each queued pop
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for n in LOOPS:
		var p := AudioStreamPlayer3D.new()
		p.stream = _looped(DIR + "%s.wav" % n)
		p.unit_size = 6.0
		p.bus = "SFX"
		p.volume_db = -80.0
		add_child(p)
		p.play(_rng.randf() * 0.4)                  # (not all in step)
		_players[n] = p
	for i in POPS:
		_pops.append(load(DIR + "pop%d.wav" % (i + 1)))
	_shift = load(DIR + "shift.wav")


func _looped(path: String) -> AudioStream:
	var w: AudioStreamWAV = load(path).duplicate()
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = w.data.size() / (2 * (2 if w.stereo else 1))
	return w


## The engine's revs (rpm) from the car's 0..1.
func revs() -> float:
	var e: Resource = car.config.engine if car.config else null
	var idle: float = e.idle_rpm if e else 1000.0
	var top: float = e.limiter_rpm if e else 7600.0
	return idle + float(car.rpm) * (top - idle)


## How much of the sound each loop is at these revs and throttle (0..1 each).
static func mix(rpm: float, thr: float) -> Dictionary:
	# the on-throttle loops: each strongest at its own revs, faded into its neighbours
	var w_idle := clampf(1.0 - (rpm - LOOPS.idle) / (LOOPS.mid - LOOPS.idle), 0.0, 1.0)
	var w_high := clampf((rpm - LOOPS.mid) / (LOOPS.high - LOOPS.mid), 0.0, 1.0)
	var w_mid := maxf(1.0 - w_idle - w_high, 0.0)
	# off the throttle up the revs: the anti-lag crackle takes over
	var over := (1.0 - thr) * smoothstep(3800.0, 6000.0, rpm)
	var on := 1.0 - over * 0.85
	return {"idle": sqrt(w_idle) * on, "mid": sqrt(w_mid) * on, "high": sqrt(w_high) * on, "overrun": sqrt(over)}


func _process(dt: float) -> void:
	if car == null:
		return
	var rpm := revs()
	var want: float = float(car.inp.throttle) if car.simulate else float(car.net_throttle)
	throttle = move_toward(throttle, want, dt * 8.0)
	shares = mix(rpm, throttle)
	var loud := -9.0 + throttle * 4.0
	for n in LOOPS:
		var p: AudioStreamPlayer3D = _players[n]
		p.pitch_scale = clampf(rpm / LOOPS[n], 0.5, 2.0)
		var share: float = shares[n]
		p.volume_db = ((-10.0 if n == "overrun" else loud) + linear_to_db(share)) if share > 0.001 else -80.0
	# lifting off at high revs: a few anti-lag pops
	_recent = maxf(_recent - dt * 1.5, throttle)
	if throttle > 0.5:
		_lifted = false
	if not _lifted and _recent > 0.6 and throttle < 0.2 and rpm > 5000.0:
		_lifted = true
		for i in _rng.randi_range(1, 3):
			_pop_queue.append(0.03 + i * _rng.randf_range(0.06, 0.14))
	# an upshift: the cut and the bang as the revs drop (and sometimes a pop)
	var g: int = int(car.gear)
	if g > _gear and g >= 2:
		shifts_fired += 1
		_one_shot(_shift, -4.0, 1.0)
		if _rng.randf() < 0.6:
			_pop_queue.append(0.12)
	_gear = g
	for i in range(_pop_queue.size() - 1, -1, -1):
		_pop_queue[i] -= dt
		if _pop_queue[i] <= 0.0:
			_pop_queue.remove_at(i)
			pops_fired += 1
			_one_shot(_pops[_rng.randi() % _pops.size()], -6.0 + _rng.randf_range(-3.0, 1.0), _rng.randf_range(0.9, 1.1))


func _one_shot(s: AudioStream, db: float, pitch: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.unit_size = 6.0
	p.bus = "SFX"
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
