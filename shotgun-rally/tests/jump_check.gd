extends SceneTree
## Jumps (stage_gen's Finland-style kickers), driven for real on a built stage:
## the car is put on the run-up at a speed, holds it (flat out over the brow, the
## way drivers do), and this measures the flight and the landing:
##   * air time and how high it gets: none to a hop when slow, ~1 s flying fast
##   * the landing: the body's angle to the slope it lands on (four wheels
##     together, not nose-first), the hardest jolt, no second bounce, still on
##     the road, upright
##   * braking in the air tips the nose down (the wheels hand their spin to the body)
##   * a BIG jump ("caution, jump") flies longer, and still lands clean
## Run: godot --headless --fixed-fps 60 --path . -s tests/jump_check.gd [-- --report]
## Prints one [jump] line per run and check; exits 1 on any FAIL.

const MAX_JOLT := 95.0          # m/s^2, same limit as the ride check
const MAX_JOLT_BIG := 125.0     # a big jump (1.1 s in the air onto a 15 % slope) is meant to land hard

var StageGen
var StageBuilder
var RallyCar
var Autopilot
var ap
var st                          # the stage with the normal jump ...
var st_big                      # ... and the one with a big jump
var car
var jump: Dictionary
var jumps := {}                 # "normal" / "big" -> {st, jump, builder}
var fails := 0
var _runs := [
	{"kmh": 80.0, "air_brake": false, "jump": "normal"},
	{"kmh": 100.0, "air_brake": false, "jump": "normal"},
	{"kmh": 120.0, "air_brake": false, "jump": "normal"},
	{"kmh": 120.0, "air_brake": true, "jump": "normal"},
	{"kmh": 120.0, "air_brake": false, "jump": "big"},
]
var _run := -1
var _t := 0.0
var _hint := -1
var _m := {}
var _prev_vy := 0.0


func _initialize() -> void:
	StageGen = load("res://scripts/stage/stage_gen.gd")
	StageBuilder = load("res://scripts/stage/stage_builder.gd")
	RallyCar = load("res://scripts/vehicle/rally_car.gd")
	Autopilot = load("res://scripts/vehicle/autopilot.gd")
	# the first stage (by seed) with a normal jump, and the first with a big one
	for seed_value in range(1, 120):
		var g = StageGen.new()
		g.generate(seed_value)
		for c in g.crests:
			var kind := "big" if c.get("big", false) else "normal"
			if c.jump and not jumps.has(kind):
				jumps[kind] = {"st": g, "jump": c}
				print("[jump] seed %d: %s jump at %.0f m (run-up %+.1f %%, landing %+.1f %%)" % [
					seed_value, kind, c.s, c.up * 100.0, -c.down * 100.0])
		if jumps.size() == 2:
			break
	if jumps.size() < 2:
		print("[jump] FAIL no stage with a normal and a big jump in seeds 1-119")
		quit(1)
		return
	car = RallyCar.new()
	root.add_child(car)
	_next()


## Build the stage a run needs (only one at a time in the world).
func _use(kind: String) -> void:
	if jumps[kind].has("builder"):
		return
	for k in jumps:
		if jumps[k].has("builder"):
			jumps[k].builder.queue_free()
			jumps[k].erase("builder")
	var b = StageBuilder.new()
	root.add_child(b)
	b.build(jumps[kind].st)
	jumps[kind].builder = b
	st = jumps[kind].st
	jump = jumps[kind].jump
	ap = Autopilot.new(st)                           # steers; the speed is this test's


func _next() -> void:
	_run += 1
	_t = 0.0
	_hint = -1
	if _run >= _runs.size():
		return
	_use(_runs[_run].jump)
	# on the jump's straight (launched at speed: no run-up needed), never in the corner before it
	var s0: float = jump.s - 110.0
	for run in st._straight_runs(40.0):
		if jump.s > run.x and jump.s < run.y:
			s0 = maxf(run.x + 4.0, s0)
	car.place(st.world_at(s0, 0.0), st.heading_at(s0))
	car.linear_velocity = st.forward_at(s0) * _runs[_run].kmh / 3.6
	_prev_vy = 0.0
	_m = {"phase": "approach", "air": 0.0, "air_frames": 0, "top": -INF, "base": 0.0, "pitch": 0.0,
		"land_kmh": 0.0, "jolt": 0.0, "since_land": 0.0, "bounce": 0.0, "bounce_now": 0.0, "max_d": 0.0}


func _physics_process(dt: float) -> bool:
	if _run >= _runs.size():
		return _finish()
	_t += dt
	var r: Dictionary = _runs[_run]
	var at: Dictionary = st.locate(car.global_position, _hint)
	_hint = at.i
	car.set_lanes(st, at.s, at.d)                    # the clean wheel tracks grip, the loose gravel doesn't
	var s: float = at.s
	var d: float = at.d
	# the autopilot's line, this run's speed: flat out over the brow like a driver,
	# then braking once it's down (the next corner)
	var want: float = r.kmh / 3.6
	var fwd: Vector3 = -car.global_transform.basis.z
	var steer: float = ap.drive(car, s, d).steer
	var spd: float = car.linear_velocity.length()
	var thr := clampf((want - spd) * 0.5 + 0.35, 0.0, 1.0)
	var brk := 0.0
	if r.air_brake and _m.phase == "air":
		thr = 0.0
		brk = 1.0
	if _m.phase == "after" and _m.since_land > 0.4:
		thr = 0.0
		brk = 0.5
	car.inp = {"steer": steer, "throttle": thr, "brake": brk, "handbrake": false}
	_m.max_d = maxf(_m.max_d, absf(d)) if s > jump.s - 20.0 else _m.max_d
	var vy: float = car.linear_velocity.y
	var acc_y := (vy - _prev_vy) / dt
	_prev_vy = vy
	var above: float = car.global_position.y - st.point_at(s).y
	# off the ground = no tyre pressing: every spring (nearly) unloaded
	var off := true
	for k in 4:
		off = off and car.comp[k] < 0.03
	if OS.get_cmdline_user_args().has("--trace") and _run == 4 and s > jump.s - 4.0 and _m.since_land < 1.7:
		print("[trace] t %.2f s %.1f d %+.2f above %.2f grounded %d vy %+.2f comp %s phase %s steer %+.2f kmh %.0f" % [
			_t, s - jump.s, d, above, car.grounded, vy, car.comp, _m.phase, steer, car.kmh()])
	match _m.phase:
		"approach":
			if s > jump.s - 6.0:
				_m.base = above
			if off and s > jump.s - 5.0:
				_m.air_frames += 1
				if _m.air_frames >= 3:
					_m.phase = "air"
					_m.air = 3.0 * dt
			else:
				_m.air_frames = 0
			if s > jump.s + 25.0 and _m.phase == "approach":
				_m.phase = "after"                   # never left the ground
				_m.since_land = 0.0
		"air":
			_m.air += dt
			_m.top = maxf(_m.top, above - _m.base)
			if not off:
				_m.phase = "after"
				_m.since_land = 0.0
				_m.land_kmh = car.kmh()
				# the body's angle to the slope it lands on (+ = nose up)
				var grade: float = (st.point_at(s + 1.5).y - st.point_at(s - 1.5).y) / 3.0
				_m.pitch = rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)) - atan(grade))
		"after":
			_m.since_land += dt
			if _m.since_land < 0.6:
				_m.jolt = maxf(_m.jolt, acc_y)
			if _m.since_land > 0.1 and _m.since_land < 1.6:
				_m.bounce_now = _m.bounce_now + dt if off else 0.0
				_m.bounce = maxf(_m.bounce, _m.bounce_now)
			if _m.since_land > 1.8:
				r["result"] = _m.duplicate()
				r.result["upright"] = car.global_transform.basis.y.y > 0.7
				r.result["d"] = d
				print("[jump]   %s jump, %3.0f km/h%s: %.2f s in the air, %.2f m higher, lands %+5.1f deg to the slope, jolt %3.0f m/s^2, bounce %.2f s, %.1f m off the middle" % [
					r.jump, r.kmh, " braking in the air" if r.air_brake else "", _m.air, maxf(_m.top, 0.0), _m.pitch,
					_m.jolt, _m.bounce, _m.max_d])
				_next()
	if _t > 14.0:
		print("[jump] FAIL run %d stuck in phase %s" % [_run, _m.phase])
		fails += 1
		_next()
	return false


func _check(ok: bool, msg: String) -> int:
	print("[jump] %s %s" % ["ok  " if ok else "FAIL", msg])
	return 0 if ok else 1


func _finish() -> bool:
	var by := {}
	for r in _runs:
		if r.has("result"):
			by["%d%s%s" % [r.kmh, "b" if r.air_brake else "", "big" if r.jump == "big" else ""]] = r.result
	var slow: Dictionary = by.get("80", {})
	var mid: Dictionary = by.get("100", {})
	var fast: Dictionary = by.get("120", {})
	var brake: Dictionary = by.get("120b", {})
	var big: Dictionary = by.get("120big", {})
	if slow.is_empty() or mid.is_empty() or fast.is_empty() or brake.is_empty() or big.is_empty():
		return _done(_check(false, "not every run finished"))
	fails += _check(slow.air < 0.75, "80 km/h: a hop at most (%.2f s)" % slow.air)
	fails += _check(mid.air > 0.5 and mid.air < 1.3, "100 km/h: %.2f s in the air (0.5 .. 1.3)" % mid.air)
	fails += _check(fast.air > 0.75 and fast.air < 1.6 and fast.air > mid.air, "120 km/h: %.2f s in the air, longer than at 100 (0.75 .. 1.6)" % fast.air)
	fails += _check(fast.top > 0.4 and fast.top < 2.5, "120 km/h: %.1f m higher than on the road (0.4 .. 2.5)" % fast.top)
	fails += _check(big.air > fast.air + 0.1 and big.air < 1.8, "big jump at 120 km/h: %.2f s in the air, longer than the normal one (%.2f s)" % [big.air, fast.air])
	for k in ["100", "120", "120big"]:
		var m: Dictionary = by[k]
		fails += _check(absf(m.pitch) < 12.0, "%s km/h: lands %+.1f deg to the slope: four wheels together (within 12)" % [k, m.pitch])
		var limit := MAX_JOLT_BIG if k.ends_with("big") else MAX_JOLT
		fails += _check(m.jolt < limit, "%s km/h: hardest jolt %.0f m/s^2 (< %.0f)" % [k, m.jolt, limit])
		fails += _check(m.bounce < 0.15, "%s km/h: no second bounce (%.2f s off again)" % [k, m.bounce])
		fails += _check(m.max_d < 2.6 and m.upright, "%s km/h: stays on the road, upright (%.1f m off the middle)" % [k, m.max_d])
	fails += _check(brake.pitch < fast.pitch - 3.0, "braking in the air tips the nose down: %+.1f deg vs %+.1f" % [brake.pitch, fast.pitch])
	return _done(0)


func _done(extra: int) -> bool:
	fails += extra
	print("[jump] %s" % ("JUMPS OK" if fails == 0 else "JUMPS FAIL"))
	quit(1 if fails > 0 else 0)
	return true
