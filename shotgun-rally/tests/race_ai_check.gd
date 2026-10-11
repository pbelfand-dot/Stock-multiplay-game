extends SceneTree
## Track Mode's races: the speed along the racing line (RaceLine), the AI driver (RaceDriver) on the
## physics and moved far from you (RaceField), race control's start, flags and penalties
## (RaceControl), qualifying, a pit stop, and a whole race in the game.
## Run: godot --headless --fixed-fps 120 --path . -s tests/race_ai_check.gd [-- --only=line|rules|drs|quali|driver|formula|far|pit|race|weekend|class]
##   [--class=formula] [--car=<registry id>] (the driving and race tests in that class / car; --only=class: just those)
##   [--weather=wet] (the driving tests on a wet track, on wet tyres)
##   line: the AFFALTER GT3's lap along CINDER RIDGE's line: a GT3's lap time and top speed, the
##     hairpin's speed, never faster than a corner's limit, braking within the grip; a slower driver
##     slower by about its pace
##   rules: (a stand-in field, no physics) the five lights a second apart, out after the hold; a jump
##     start; track-limits warnings then a penalty, a corner cut, a harmless kerb untouched; pit lane
##     speeding; the pit exit line; a stopped car's yellow and passing under it; a blue flag for a
##     lapped car; three stopped cars: red flag, the restart's grid in order with the laps kept; the
##     chequered flag and the finish order with the penalties added; disqualification; the rolling
##     start's pass before the line
##   quali: the clock runs out, a car on a flying lap finishes it, an invalidated lap doesn't count,
##     the order by best lap
##   driver: an AI car on the physics laps the circuit from a rolling start: near the line's time,
##     on the track the whole way
##   far: the same driver moved far from you laps in the line's time; the switch between the two
##     carries its place and speed over
##   pit: an AI car's stop: down the lane under the limit, stopped in its box, new tyres and fuel,
##     back out across no line
##   weekend: a race weekend's qualifying in the game (4 cars, 4 minutes, your car driven by an AI):
##     the AI out of their boxes one by one, timed laps, the flag, everyone back, the order by best
##     lap, the race's grid from it
##   race: a race in the game (6 cars, 2 laps, standing start, your car driven by an AI too): the
##     lights, every car finishing, places changing, the classification and the results
## Prints one [raceai] line per check; exits 1 on any FAIL.

var CircuitGen
var TrackSession
var RaceControl
var RaceLine
var RaceDriver
var Modes
var fails := 0
var near_lap := INF


func check(ok: bool, what: String) -> void:
	print("[raceai] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _initialize() -> void:
	CircuitGen = load("res://scripts/stage/circuit_gen.gd")
	TrackSession = load("res://scripts/game/track_session.gd")
	RaceControl = load("res://scripts/game/race_control.gd")
	RaceLine = load("res://scripts/game/race_line.gd")
	RaceDriver = load("res://scripts/vehicle/race_driver.gd")
	Modes = load("res://scripts/game/modes.gd")
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--class="):
			cls = a.trim_prefix("--class=")
		elif a.begins_with("--weather="):
			weather = a.trim_prefix("--weather=")
		elif a.begins_with("--car="):
			car_id = a.trim_prefix("--car=")
	await process_frame
	var st = _stage()
	if only in ["", "line"]:
		_line(st)
	if only in ["", "rules"]:
		_rules(st)
	if only in ["", "rules", "drs"]:
		_drs_rules(st)
	if only in ["", "quali"]:
		_quali(st)
	if only in ["", "driver", "far", "pit", "formula"]:
		await _driving(st, only)
	if only == "class":                       # (the class's own tests: run_all.sh's --class=formula pass)
		await _driving(st, "")
		await _race()
	if only in ["", "weekend"]:
		await _weekend()
	if only in ["", "race"]:
		await _race()
	print("[raceai] %s" % ("RACE AI OK" if fails == 0 else "RACE AI FAIL"))
	quit(1 if fails else 0)


func _stage():
	var st = CircuitGen.new()
	st.opts = Modes.track_opts(1).gen
	st.generate(1)
	return st


## The AFFALTER GT3's numbers, as RaceLine.params reads them off its car (without building one).
func _gt3() -> Dictionary:
	return {"mass": 1285.0 + 60.0 * 0.745, "mu": 1.6, "down": 2.4, "cd_a": 0.45 * 2.0, "radius": 0.355, "torque": 620.0,
		"rpm_points": PackedFloat32Array([2000.0, 3500.0, 5000.0, 6500.0, 7500.0]),
		"torque_points": PackedFloat32Array([0.7, 0.92, 1.0, 0.93, 0.8]), "limiter": 7500.0,
		"gears": PackedFloat32Array([2.6, 2.0, 1.6, 1.3, 1.07, 0.89]), "final": 4.0, "driven": 0.53, "load_sens": 0.2}


# ── the line ────────────────────────────────────────────────────────────────

func _line(st) -> void:
	var ln = RaceLine.new()
	ln.build(st, _gt3(), 1.0)
	var top := 0.0
	var slow := INF
	var over := 0
	for i in ln.n:
		top = maxf(top, ln.v[i])
		if ln.v[i] > ln.v_limit[i] + 0.01:
			over += 1
	for c in st.track_corners:
		if int(c.n) == 1:
			for i in range(int(float(c.s0) / ln.step), int(float(c.s1) / ln.step)):
				slow = minf(slow, ln.v[i])
	var avg: float = ln.lap_length() / ln.lap_time * 3.6
	check(avg > 150.0 and avg < 200.0, "line: the AFFALTER GT3 laps CINDER RIDGE (5.03 km, its sweepers fast) in %s on its line: %.0f km/h (GT3 laps average ~150 km/h at a tight circuit to ~195 at Monza)" % [
		_fmt(ln.lap_time), avg])
	check(top * 3.6 > 235.0 and top * 3.6 < 290.0, "line: %.0f km/h at the end of the pit straight (a GT3: ~250-280 on a 1 km straight)" % (top * 3.6))
	check(slow * 3.6 > 55.0 and slow * 3.6 < 95.0, "line: %.0f km/h through the CINDER HAIRPIN (r 24 m)" % (slow * 3.6))
	check(over == 0, "line: never faster than a corner allows (%d samples over)" % over)
	# braking: the deceleration along the line never more than the grip and the air allow
	var worst := 0.0
	for i in ln.n:
		var j: int = (i + 1) % ln.n
		if ln.v[j] < ln.v[i]:
			var a: float = (ln.v[i] * ln.v[i] - ln.v[j] * ln.v[j]) / (2.0 * ln.ds[i])
			worst = maxf(worst, a / ln._decel(ln.v[j], i))
	check(worst <= 1.02, "line: braking within the grip (the hardest stop %.0f %% of what the tyres, air and slope allow)" % (worst * 100.0))
	var ln2 = RaceLine.new()
	ln2.build(st, _gt3(), 0.92)
	var slower: float = ln2.lap_time / ln.lap_time - 1.0
	check(slower > 0.02 and slower < 0.07, "line: a driver at 92 %% of the limit laps %.1f %% slower (%s)" % [slower * 100.0, _fmt(ln2.lap_time)])
	var h1 := -INF
	for i in ln.n:
		h1 = maxf(h1, absf(ln.d[i]) - st.half[i])
	check(h1 < -0.5, "line: inside the white lines the whole way (closest %.1f m in)" % -h1)


# ── race control (no physics) ───────────────────────────────────────────────

## A stand-in field: cars at (s, d, v), moved by hand.
func _rc(st, opts: Dictionary, n: int):
	var ses = TrackSession.new()
	ses.setup(st, str(opts.get("session", "race")))
	var rc = RaceControl.new()
	rc.setup(st, ses, opts, 7)
	var cars := {}
	for k in n:
		var g: Dictionary = st.grid[k]
		var s0: float = float(g.s) - st.length
		ses.add_car(k, "CAR %d" % k, s0, false)
		rc.add_car(k, s0, float(g.d))
		cars[k] = {"s": s0, "d": float(g.d), "v": 0.0, "pit": false}
	return [ses, rc, cars]


func _step(ses, rc, cars: Dictionary, dt: float) -> void:
	ses.tick(dt, cars)
	rc.tick(dt, cars)


func _rules(st) -> void:
	var L: float = st.length
	var dt := 1.0 / 120.0
	# the lights
	var f: Array = _rc(st, {"session": "race", "laps": 2, "start": "standing"}, 4)
	var ses = f[0]
	var rc = f[1]
	var cars: Dictionary = f[2]
	rc.begin()
	var lit_at := {}
	var t := 0.0
	var green_t := -1.0
	while t < 10.0 and green_t < 0.0:
		_step(ses, rc, cars, dt)
		t += dt
		for ev in rc.events:
			if ev.kind == "light":
				lit_at[int(ev.n)] = t
			if ev.kind == "green":
				green_t = t
		rc.events.clear()
	var gaps_ok: bool = lit_at.size() == 5
	for k in range(2, 6):
		gaps_ok = gaps_ok and lit_at.has(k) and absf(float(lit_at[k]) - float(lit_at[k - 1]) - 1.0) < 0.02
	check(gaps_ok, "rules: the five red lights come on a second apart (%s)" % str(lit_at.values().map(func(x): return snappedf(x, 0.01))))
	var hold: float = green_t - float(lit_at.get(5, 0.0))
	check(green_t > 0.0 and hold >= 0.19 and hold <= 3.01, "rules: all five lit for %.2f s (random, 0.2-3 s), then out: green" % hold)
	# a jump start
	f = _rc(st, {"session": "race", "laps": 2, "start": "standing"}, 4)
	ses = f[0]
	rc = f[1]
	cars = f[2]
	rc.begin()
	for q in 240:
		if q == 200:
			cars[2].s = float(cars[2].s) + 1.5          # car 2 creeps off its box before the lights go out
		_step(ses, rc, cars, dt)
	check(rc.penalty_time(2) == 5.0 and rc.penalty_time(1) == 0.0, "rules: a car that creeps 1.5 m before the lights go out: +5 s JUMP START (%s); the others none" % str(rc.pens[2].list))
	# track limits, corner cutting, a kerb, pit speeding, the pit exit line
	f = _rc(st, {"session": "race", "laps": 9, "start": "standing"}, 2)
	ses = f[0]
	rc = f[1]
	cars = f[2]
	rc.phase = "green"
	var s_str := 2000.0                                  # (a straight's s on the far side)
	for c in st.track_corners:
		if int(c.n) == 10:
			s_str = float(c.s0) + 20.0
	var h: float = st.half_at(s_str)
	cars[0].s = s_str
	cars[1].s = s_str + 400.0
	cars[0].v = 60.0
	cars[1].v = 60.0
	var warn := 0
	var tl_pens := 0
	for k in 4:
		for q in 60:                                     # all four wheels off for 0.5 s, keeping its speed
			cars[0].d = h + 1.6
			cars[0].s = float(cars[0].s) + 0.5
			cars[1].s = float(cars[1].s) + 0.5
			_step(ses, rc, cars, dt)
		for q in 40:
			cars[0].d = h - 2.0
			cars[0].s = float(cars[0].s) + 0.5
			cars[1].s = float(cars[1].s) + 0.5
			_step(ses, rc, cars, dt)
		for ev in rc.events:
			if ev.id == 0 and ev.kind == "warning":
				warn += 1
			if ev.id == 0 and ev.kind == "penalty":
				tl_pens += 1
		rc.events.clear()
	check(warn == 3 and tl_pens == 1 and rc.bw.has(0), "rules: track limits: three warnings (the black and white flag on the third), the fourth +5 s (%d warnings, %d penalties)" % [warn, tl_pens])
	# a kerb (two wheels over, the others in) is nothing
	var before: float = rc.penalty_time(1)
	var warn_before: int = int(rc.pens[1].warn.get("tl", 0))
	for q in 120:
		cars[1].d = h + 0.6                               # its middle 0.6 m past the line: the left wheels still in
		cars[1].s = float(cars[1].s) + 0.5
		_step(ses, rc, cars, dt)
	cars[1].d = 0.0
	for q in 10:
		_step(ses, rc, cars, dt)
	check(rc.penalty_time(1) == before and int(rc.pens[1].warn.get("tl", 0)) == warn_before, "rules: two wheels over the line (the car's middle 0.6 m past it) for a second: nothing")
	rc.events.clear()
	# cutting a corner (off on the inside, kept its speed): one warning, then +5 s
	var cc: Dictionary = st.track_corners[2]
	var inside := float(cc.dir)
	var cuts := []
	for k in 2:
		var sc := float(cc.s0) + 10.0 + L * (k + 1)
		cars[1].s = sc
		for q in 50:
			cars[1].d = inside * (st.half_at(sc) + 1.5)
			cars[1].s = float(cars[1].s) + 0.4
			_step(ses, rc, cars, dt)
		for q in 20:
			cars[1].d = 0.0
			cars[1].s = float(cars[1].s) + 0.4
			_step(ses, rc, cars, dt)
		for ev in rc.events:
			if ev.id == 1 and ev.kind in ["warning", "penalty"]:
				cuts.append(ev.text)
		rc.events.clear()
	check(cuts.size() == 2 and str(cuts[0]).contains("WARNING") and str(cuts[1]).begins_with("+5"), "rules: cutting a corner on the inside: a warning, then +5 s (%s)" % " / ".join(cuts))
	# pit lane speeding
	var p: Dictionary = st.pit
	var lane_s: float = float(p.s_box0) + 20.0 + L * 3.0
	var pen0: float = rc.penalty_time(1)
	cars[1].s = lane_s
	cars[1].d = float(p.fast_d)
	cars[1].pit = true
	cars[1].v = 80.0 / 3.6
	for q in 30:
		cars[1].s = float(cars[1].s) + cars[1].v * dt
		_step(ses, rc, cars, dt)
	check(rc.penalty_time(1) - pen0 == 5.0, "rules: 80 km/h in the pit lane's 60: +5 s PIT LANE SPEEDING (once for the one time)")
	# the pit exit line: out of the lane onto the track before the taper ends
	pen0 = rc.penalty_time(1)
	cars[1].s = float(p.s_out0) + 10.0 + L * 3.0
	cars[1].v = 16.0
	for q in 20:
		cars[1].s = float(cars[1].s) + 0.15
		cars[1].d = st.pit_inner_d(float(cars[1].s)) + 2.0
		cars[1].pit = true
		_step(ses, rc, cars, dt)
	for q in 20:
		cars[1].s = float(cars[1].s) + 0.15
		cars[1].d = st.half_at(float(cars[1].s)) - 2.5     # across the line onto the track
		cars[1].pit = false
		_step(ses, rc, cars, dt)
	check(rc.penalty_time(1) - pen0 == 5.0, "rules: across the pit exit's line before its end: +5 s")
	# a stopped car's yellow, passing under it
	f = _rc(st, {"session": "race", "laps": 9, "start": "standing"}, 3)
	ses = f[0]
	rc = f[1]
	cars = f[2]
	rc.phase = "green"
	cars[0].s = s_str + 200.0
	cars[0].d = 3.0
	cars[0].v = 0.0                                      # stopped on the track
	cars[1].s = s_str + 60.0
	cars[1].d = -2.0
	cars[1].v = 40.0
	cars[2].s = s_str + 50.0
	cars[2].d = 2.0
	cars[2].v = 40.0
	for q in 400:
		_step(ses, rc, cars, dt)
		cars[1].s = float(cars[1].s) + 30.0 * dt
		cars[2].s = float(cars[2].s) + 30.0 * dt + (0.05 if q > 330 else 0.0)
	check(rc.in_yellow(float(cars[0].s)) and rc.in_yellow(float(cars[0].s) - 200.0), "rules: a car stopped on the track: a yellow over its stretch and the one before")
	cars[2].s = float(cars[1].s) + 3.0                    # car 2 jumps past car 1 under the yellow
	_step(ses, rc, cars, dt)
	check(rc.penalty_time(2) == 5.0 and rc.penalty_time(1) == 0.0, "rules: passing a racing car under the yellow: +5 s (%s)" % str(rc.pens[2].list))
	# a blue flag
	f = _rc(st, {"session": "race", "laps": 9, "start": "standing"}, 2)
	ses = f[0]
	rc = f[1]
	cars = f[2]
	rc.phase = "green"
	cars[0].s = s_str + L + 40.0
	cars[0].v = 55.0
	cars[1].s = s_str + 60.0
	cars[1].v = 45.0
	_step(ses, rc, cars, dt)
	check(rc.blue.has(1) and not rc.blue.has(0), "rules: a car a lap down with the leader 20 m behind: blue flag")
	# three stopped: red flag; the restart's grid in order, laps kept
	f = _rc(st, {"session": "race", "laps": 9, "start": "standing"}, 5)
	ses = f[0]
	rc = f[1]
	cars = f[2]
	rc.phase = "green"
	var spots := [L * 2.0 + 900.0, L * 2.0 + 700.0, L + 4000.0, L + 600.0, 300.0]   # car 3 is a lap down, car 4 two
	for k in 5:
		cars[k].s = float(spots[k])
		ses.cars[k].s_last = float(spots[k])
		ses.cars[k].s_max = float(spots[k])
		ses.cars[k].laps = floori(float(spots[k]) / L)
		ses.cars[k].out_lap = false
		cars[k].v = 0.0 if k < 3 else 40.0
	for q in 400:
		_step(ses, rc, cars, dt)
	check(rc.phase == "red", "rules: three cars stopped on the track at once: red flag")
	for k in 5:
		cars[k].v = 20.0
	var regrid := {}
	for q in int(RaceControl.RED_HOLD * 120) + 10:
		_step(ses, rc, cars, dt)
		for ev in rc.events:
			if ev.kind == "regrid":
				regrid = ev
		rc.events.clear()
	var laps_after: Array = []
	for k in 5:
		laps_after.append(ses.cars[k].laps)
	check(rc.phase == "lights" and not regrid.is_empty() and regrid.order == [0, 1, 2, 3, 4] and laps_after == [2, 2, 2, 1, 0],
		"rules: the restart: the grid in the order (%s), the laps kept (%s: the lead lap, a lap down, two down), the lights again" % [str(regrid.get("order")), str(laps_after)])
	# the finish: chequered for the leader, the rest on their next crossing; penalties added
	f = _rc(st, {"session": "race", "laps": 1, "start": "standing"}, 3)
	ses = f[0]
	rc = f[1]
	cars = f[2]
	rc.phase = "green"
	rc._add_pen(0, "x", "TEST", 5.0)
	var speeds := [50.0, 49.0, 48.0]
	var t_end := 0.0
	while rc.phase != "done" and t_end < 300.0:
		for k in 3:
			cars[k].v = speeds[k]
			cars[k].s = float(cars[k].s) + float(speeds[k]) * dt
		_step(ses, rc, cars, dt)
		t_end += dt
	var res: Array = rc.results(cars)
	var names: Array = res.map(func(r): return r.id)
	check(rc.phase == "done" and rc.finish_order == [0, 1, 2], "rules: the chequered flag after the laps, every car finishing as it next crosses the line (%s)" % str(rc.finish_order))
	var gap01: float = float(res[1].total) - float(res[0].total) if res.size() > 1 else 0.0
	check(names[0] == 1 or (names[0] == 0 and gap01 > 0.0), "rules: the classification adds the penalties (the winner on the road +5 s: %s, %s)" % [
		str(names), str(res.map(func(r): return snappedf(float(r.total), 0.001)))])
	# disqualification at 30 s of penalties
	for k in 6:
		rc._add_pen(2, "x", "TEST", 5.0)
	check(rc.dnf.get(2, "") == "DSQ", "rules: 30 s of penalties: black flag, disqualified")
	# the rolling start: passing before the line
	f = _rc(st, {"session": "race", "laps": 3, "start": "rolling"}, 3)
	ses = f[0]
	rc = f[1]
	cars = f[2]
	rc.begin()
	for k in 3:
		cars[k].s = -300.0 - k * 8.0
		cars[k].v = 22.0
	for q in 1800:
		for k in 3:
			var v: float = 22.0 if k != 2 else 26.0           # car 2 (third on the grid) goes early
			cars[k].s = float(cars[k].s) + v * dt
		_step(ses, rc, cars, dt)
	check(rc.penalty_time(2) == 5.0 and rc.penalty_time(0) == 0.0, "rules: the rolling start: a car over the line ahead of the cars that started in front of it +5 s")


# ── qualifying ──────────────────────────────────────────────────────────────

## DRS (no physics): three cars round at 60 m/s, the second 0.6 s behind the first, the third 1.6 s
## behind the second. Not before the leader's third lap; then the second may open it in the zone, the
## others not; never under a yellow there or a red; in practice anyone may, in a zone.
func _drs_rules(st) -> void:
	var L: float = st.length
	var dt := 1.0 / 120.0
	var z: Dictionary = st.drs[0]
	var f: Array = _rc(st, {"session": "race", "laps": 9, "start": "standing"}, 3)
	var ses = f[0]
	var rc = f[1]
	var cars: Dictionary = f[2]
	rc.begin()
	var t := 0.0
	while rc.phase != "green" and t < 10.0:
		_step(ses, rc, cars, dt)
		t += dt
	var v := 60.0
	cars[0].s = -5.0
	cars[1].s = -5.0 - v * 0.6
	cars[2].s = -5.0 - v * 0.6 - v * 1.6
	for id in cars:
		cars[id].d = 0.0
		cars[id].v = v
	var zone_s: float = float(z.s0) + 30.0                  # (well inside the zone, past its start)
	var lap1 := false
	var lap2 := {}
	var enabled_at := -1.0
	var any_early := false
	while float(cars[2].s) < 2.0 * L + zone_s + 5.0 and t < 400.0:
		for id in cars:
			cars[id].s = float(cars[id].s) + v * dt
		_step(ses, rc, cars, dt)
		t += dt
		for ev in rc.events:
			if ev.kind == "drs" and bool(ev.on) and enabled_at < 0.0:
				enabled_at = float(cars[0].s) / L
		rc.events.clear()
		for id in cars:
			var sp := float(cars[id].s)
			if enabled_at < 0.0 and rc.drs_state(id, sp):
				any_early = true                         # (before it's enabled: never)
			if not lap1 and id == 1 and sp >= L + zone_s:
				lap1 = true
			if sp >= 2.0 * L + zone_s and not lap2.has(id):
				lap2[id] = rc.drs_state(id, sp)
	check(not any_early and enabled_at >= 2.0 and enabled_at < 2.01, "drs: not before the leader starts its third lap (enabled at %.3f laps)" % enabled_at)
	check(lap2.get(1, false) and not lap2.get(0, true) and not lap2.get(2, true), "drs: in the zone, the car 0.6 s behind at the detection point may open it; the leader and the car 1.6 s back may not (%s)" % str(lap2))
	var s1 := float(cars[1].s)
	var micro := floori(fposmod(s1, L) / RaceControl.MICRO)
	rc.yellows[micro] = 5.0
	check(not rc.drs_state(1, s1), "drs: not under a yellow in the zone")
	rc.yellows.erase(micro)
	check(rc.drs_state(1, s1) and not rc.drs_state(1, s1 + 900.0), "drs: back on once the yellow's gone; never out of a zone")
	rc.red_flag("TEST")
	check(not rc.drs_state(1, s1), "drs: not under a red flag")
	# practice: anyone, in a zone
	f = _rc(st, {"session": "practice"}, 1)
	check(f[1].drs_state(0, zone_s) and not f[1].drs_state(0, zone_s + 900.0), "drs: in practice free in the zones, nowhere else")


func _quali(st) -> void:
	var L: float = st.length
	var dt := 1.0 / 30.0
	var ses = TrackSession.new()
	ses.setup(st, "qualifying")
	var rc = RaceControl.new()
	rc.setup(st, ses, {"session": "qualifying", "minutes": 4.0}, 3)
	var cars := {}
	var v := [55.0, 50.0]
	for k in 2:
		ses.add_car(k, "Q%d" % k, -50.0 - k * 300.0, false)
		cars[k] = {"s": -50.0 - k * 300.0, "d": 0.0, "v": v[k], "pit": false}
	rc.begin()
	var t := 0.0
	var off_once := false
	while rc.phase != "done" and t < 600.0:
		for k in 2:
			cars[k].s = float(cars[k].s) + float(v[k]) * dt
			# car 1's second lap: all four wheels off once (deleted)
			cars[k].d = 0.0
			if k == 1 and ses.cars[1].laps == 1 and not off_once and fposmod(float(cars[1].s), L) > 2000.0:
				cars[k].d = st.half_at(float(cars[1].s)) + 2.0
				off_once = true
		_step(ses, rc, cars, dt)
		t += dt
	var q: Array = rc.results(cars)
	check(rc.phase == "done" and t > 240.0, "quali: the 4 minutes run out and the session ends once the flying laps are done (%.0f s)" % t)
	var c1: Dictionary = ses.cars[1]
	var inval: int = (c1.history as Array).filter(func(h): return not h.valid).size()
	check(inval == 1 and float(c1.best) != INF, "quali: an invalidated lap doesn't count (car 1: %d laps, %d invalid, best %s)" % [c1.laps, inval, _fmt(float(c1.best))])
	check(q.size() == 2 and q[0].id == 0, "quali: the order by best lap (%s)" % str(q.map(func(r): return [r.id, snappedf(float(r.best), 0.01)])))
	# a lap started before the flag counts
	var last_end := 0.0
	for h in ses.cars[0].history:
		last_end += float(h.time)
	check(ses.cars[0].laps >= 2, "quali: the car on its flying lap at the flag finished it (%d laps)" % ses.cars[0].laps)


# ── driving (the physics, the far mode, a pit stop) ─────────────────────────

var cls := "gt"                    # --class=formula: the driving tests in a Formula car
var car_id := ""                   # --car=<registry id>: the driving tests' car (else the AFFALTER GT3, or the ORION FA1)
var weather := "day"               # --weather=wet: the driving tests on a wet track


func _driving(st_unused, only: String) -> void:
	root.get_node("Net").solo()
	var Game = load("res://scripts/game.gd")
	var g = Game.new()
	root.add_child(g)
	# a qualifying session with one AI car (it leaves its box at once): its car, its driver
	var o: Dictionary = Modes.track_opts(5, cls, "qualifying", 3, "cinder_ridge", {"opponents": 1, "difficulty": "pro", "minutes": 30.0, "weather": weather})
	o["field_cars"] = [car_id if car_id != "" else ("orion" if cls == "formula" else "affalter")]
	await g.start(5, 1, o)
	var st = g.st
	var field = g.field
	check(field != null and field.drivers.size() == 1, "driver: qualifying builds its AI field (%s)" % ("%d car" % field.drivers.size() if field else "none"))
	if field == null or field.drivers.is_empty():
		return
	g.begin_countdown()
	while g.state != "running":
		await physics_frame
	var drv = field.drivers[0]
	var c = field.cars[drv.id]
	print("[raceai] info the driving tests' car: %s (%s), its line %s at pace %.2f" % [str(c.setup.get("car", "?")), cls, _fmt(drv.line.lap_time), drv.line.pace])
	print("[raceai] info params %s" % str(drv.line.p))
	var ses = g.session
	var dt := 1.0 / 120.0
	var L: float = st.length
	if only in ["", "driver", "pit", "formula"]:
		# near: keep it on the physics (the player's car rides along with it, out of the way)
		field.near_max = 1
		field.pin_near = true
		drv.task = "race"
		drv.pit_phase = ""
		var s0: float = -900.0
		drv.s = s0
		drv.d = drv.line.d_at(s0)
		drv.v = drv.line.speed_at(s0)
		field._go_near(drv)
		g.car.freeze = true
		var t := 0.0
		var off_t := 0.0
		var last_off := -9.0
		var worst_d := 0.0
		var lap_t0 := -1.0
		var lap_t := INF
		var t_wall := Time.get_ticks_msec()
		var crossed := 0
		var last_s: float = drv.s
		var lap2 := INF
		while t < 360.0 and lap2 == INF:
			await physics_frame
			t += dt
			if not field.near.has(drv.id):
				continue
			var over: float = absf(drv.d) - st.half_at(drv.s)
			worst_d = maxf(worst_d, over)
			if over > 1.0:
				if off_t <= 0.0 or t - last_off > 1.0:
					print("[raceai] info off at s %.0f (lap %d): %.0f km/h, its line's %.0f, d %.1f, %.1f m past the line" % [fposmod(drv.s, L), floori(drv.s / L), drv.v * 3.6,
						drv.line.speed_at(drv.s) * 3.6, drv.d, over])
				off_t += dt
				last_off = t
			if floori(drv.s / L) > floori(last_s / L):
				crossed += 1
				if crossed == 1:
					lap_t0 = t
				elif crossed == 2:
					lap_t = t - lap_t0
					lap_t0 = t
				elif crossed == 3:
					lap2 = t - lap_t0
			last_s = drv.s
		var want: float = drv.line.lap_time / RaceDriver.FAR_K
		near_lap = lap2
		if c.race:
			print("[raceai] info its tyres after the laps (%s): %s" % [c.race.compound, ", ".join(c.race.tyres.map(func(ty): return "%.0f/%.0f C" % [ty.surface, ty.core]))
				+ "; grip x " + ", ".join(range(4).map(func(k): return "%.2f" % c.race.grip(k)))])
		check(lap_t != INF and lap2 != INF and absf(lap2 / want - 1.0) < 0.025, "driver: on the physics, two flying laps in %s and %s (its line at its pace, as the far cars run it: %s, %+.1f %%; %.0f s game in %.0f s)" % [
			_fmt(lap_t), _fmt(lap2), _fmt(want), (lap2 / want - 1.0) * 100.0 if lap2 != INF else 0.0, t, (Time.get_ticks_msec() - t_wall) / 1000.0])
		check(off_t < 0.5, "driver: on the track the whole way (%.1f s with all four wheels off, the widest %.1f m past the line)" % [off_t, worst_d])
	if only in ["", "far"]:
		# far: moved along the line, timed the same way
		field.near_max = 0
		field.pin_near = false
		field._go_far(drv)
		drv.task = "race"
		drv.s = -900.0
		drv.d = drv.line.d_at(-900.0)
		drv.v = drv.line.speed_at(-900.0)
		var t := 0.0
		var lap_t0 := -1.0
		var lap_t := INF
		var crossed := 0
		var last_s: float = drv.s
		while t < 240.0 and lap_t == INF:
			await physics_frame
			t += dt
			if floori(drv.s / L) > floori(last_s / L):
				crossed += 1
				if crossed == 1:
					lap_t0 = t
				elif crossed == 2:
					lap_t = t - lap_t0
			last_s = drv.s
		var want: float = drv.line.lap_time / RaceDriver.FAR_K
		check(lap_t != INF and absf(lap_t / want - 1.0) < 0.015, "far: moved along its line, a lap in %s (its line at the near car's measured share: %s%s)" % [_fmt(lap_t), _fmt(want),
			"; on the physics %s" % _fmt(near_lap) if near_lap != INF else ""])
		check(not field.near.has(drv.id) and c.freeze and c.collision_layer == 0, "far: off the physics while it's far (held, touching nothing)")
		# the switch: onto the physics at speed where it's drawn, and back
		var p0: Vector3 = c.global_position
		var v0: float = drv.v
		field.near_max = 1
		field.pin_near = true
		field._choose_lod()
		await physics_frame
		var jump: float = (c.global_position - p0).length()
		check(field.near.has(drv.id) and jump < v0 * dt * 3.0 + 0.6 and absf(c.linear_velocity.length() - v0) < 2.0,
			"far: onto the physics at %.0f km/h where it was drawn (moved %.2f m in the tick, %.0f km/h after)" % [v0 * 3.6, jump, c.linear_velocity.length() * 3.6])
		var gear_ok: bool = c.drivetrain.gear >= 2 if v0 > 30.0 else true
		check(gear_ok, "far: in a gear for its speed (gear %d at %.0f km/h)" % [c.drivetrain.gear, v0 * 3.6])
	if only in ["", "pit"]:
		# a pit stop: in, the box, tyres and fuel, out
		field.near_max = 1
		field._go_near(drv)
		drv.task = "race"
		var s1: float = float(st.pit.s_in0) - 900.0 + L * 3.0
		drv.s = s1
		drv.d = drv.line.d_at(s1)
		drv.v = drv.line.speed_at(s1)
		c.place(st.world_at(s1, drv.d), st.heading_at(s1))
		c.set_rolling(drv.v)
		drv.laps = 3
		drv.pit_lap = 3
		drv.pit_service = {"tyres": true, "compound": "slick_soft", "fuel": 20.0}
		var fuel0: float = c.race.fuel_l
		c.race.tyres[0].wear = 0.5
		var t := 0.0
		var top_lane := 0.0
		var stop_at := INF
		var stop_t := 0.0
		var out := false
		var pens0: float = g.race_ctl.penalty_time(drv.id)
		while t < 200.0 and not out:
			await physics_frame
			t += dt
			if st.in_pit_limit(drv.s, drv.d):
				top_lane = maxf(top_lane, c.linear_velocity.length() * 3.6)
			if drv.pit_phase == "stop":
				stop_t += dt
				if stop_at == INF:
					stop_at = st.around_line(drv.s) - drv.box_x()
			if drv.task == "race" and stop_t > 0.0:
				out = true
		check(top_lane > 40.0 and top_lane < float(st.pit.limit_kmh) + 2.0, "pit: down the pit lane at the limit (top %.0f km/h, the limit %d)" % [top_lane, int(st.pit.limit_kmh)])
		check(stop_at != INF and absf(stop_at) < 2.5, "pit: stopped in its box (%.1f m from its middle)" % stop_at)
		check(c.race.compound == "slick_soft" and float(c.race.tyres[0].wear) < 0.01 and c.race.fuel_l > fuel0 + 15.0, "pit: new softs and 20 l (%.0f s stopped)" % stop_t)
		check(out and g.race_ctl.penalty_time(drv.id) == pens0, "pit: back out onto the track, no line crossed, under the limit (penalties %+.0f s)" % (g.race_ctl.penalty_time(drv.id) - pens0))
	# (last: its laps flat out down the pit straight leave the car rounds ahead of the far and pit tests' places)
	if cls == "formula" and only in ["", "driver", "formula"]:
		# DRS and the hybrid on the physics: down the pit straight from the HOOK's exit to the end of
		# DRS zone 1 twice, first with both off, then the flap open and the MGU-K deploying
		field.near_max = 1
		field.pin_near = true
		var tops: Array = []
		var used := 0.0
		for run in 2:
			drv.task = "race"
			drv.pit_phase = ""
			var s0: float = 4470.0 + L * (4 + run)
			drv.s = s0
			drv.d = drv.line.d_at(s0)
			drv.v = drv.line.speed_at(s0)
			field._go_near(drv)
			c.place(st.world_at(s0, drv.d), st.heading_at(s0))
			c.set_rolling(drv.v)
			c.race.drs_auto = false
			c.race.ers_mode = 0 if run == 0 else 1
			c.race.ers_store = c.race.ERS_STORE
			c.race.ers_used = 0.0
			var top := 0.0
			var t := 0.0
			while drv.s < s0 + 880.0 and t < 30.0:
				c.race.drs_open = run == 1 and c.race.drs_avail
				await physics_frame
				t += dt
				top = maxf(top, absf(c.speed))
			tops.append(top)
			if run == 1:
				used = c.race.ers_used
		var gain: float = (tops[1] - tops[0]) * 3.6
		check(gain > 8.0 and gain < 40.0, "formula: down the pit straight %.0f km/h with DRS shut and the hybrid off, %.0f with the flap open and the MGU-K deploying (+%.0f km/h: DRS's +10-12 km/h, the FIA's figure, and 120 kW more)" % [tops[0] * 3.6, tops[1] * 3.6, gain])
		check(used > 0.4e6 and used <= c.race.ERS_DEPLOY_LAP, "formula: the MGU-K deployed %.2f MJ down it (never more than 4 MJ a lap)" % (used / 1.0e6))
	g.queue_free()
	await process_frame


# ── a weekend's qualifying in the game ─────────────────────────────────────

func _weekend() -> void:
	root.get_node("Net").solo()
	var Game = load("res://scripts/game.gd")
	var g = Game.new()
	root.add_child(g)
	var o: Dictionary = Modes.track_opts(11, "gt", "weekend", 3, "cinder_ridge", {"opponents": 3, "difficulty": "hard", "minutes": 4.0})
	await g.start(11, 1, o)
	check(g.race_ctl != null and g.race_ctl.kind == "qualifying" and bool(g.opts.get("weekend", false)), "weekend: a race weekend opens with qualifying (%s)" % Modes.title(o, g.st).replace("\n", " · "))
	g.use_autopilot = true
	g.begin_countdown()
	var dt := 1.0 / 120.0
	var t := 0.0
	var left_box := {}
	var t_wall := Time.get_ticks_msec()
	while t < 600.0 and g.state != "finished":
		await physics_frame
		t += dt
		for drv in g.field.drivers:
			if not left_box.has(drv.id) and drv.task in ["pit", "race"] and drv.v > 3.0:
				left_box[drv.id] = g.session.time
	var times: Array = left_box.values()
	times.sort()
	var staggered := times.size() == 3
	for k in range(1, times.size()):
		staggered = staggered and float(times[k]) - float(times[k - 1]) > 4.0
	check(staggered, "weekend: the AI leave their boxes one by one (%s s)" % str(times.map(func(x): return snappedf(x, 0.1))))
	var timed := 0
	for id in g.session.cars:
		if float(g.session.cars[id].best) != INF:
			timed += 1
	check(g.state == "finished" and timed >= 3, "weekend: the flag after 4 minutes, %d of 4 cars with a timed lap (%.0f s of game in %.0f s)" % [timed, t, (Time.get_ticks_msec() - t_wall) / 1000.0])
	var rows: Array = g.race_rows
	var ordered := true
	for k in range(1, rows.size()):
		if float(rows[k].best) < float(rows[k - 1].best):
			ordered = false
	check(rows.size() == 4 and ordered, "weekend: qualifying's order by best lap (%s)" % str(rows.map(func(r): return "%s %s" % [r.name, _fmt(float(r.best))])))
	check(g.next_grid == rows.map(func(r): return r.id), "weekend: the race's grid is qualifying's order")
	# the race it leads to: the same field on that grid
	var o2: Dictionary = Modes.track_opts(11, "gt", "race", 3, "cinder_ridge", {"opponents": 3, "difficulty": "hard", "weekend": true, "grid_order": g.next_grid})
	var f1: Array = Modes.track_field(o, 11).map(func(e): return [e.id, e.name, e.car])
	var f2: Array = Modes.track_field(o2, 11).map(func(e): return [e.id, e.name, e.car])
	var grid2: Array = Modes.track_grid(o2, Modes.track_field(o2, 11), root.get_node("Net").my_id(), 11)
	check(f1 == f2 and grid2 == g.next_grid, "weekend: the race has the same drivers and cars, on qualifying's grid (%s)" % str(grid2))
	g.queue_free()
	await process_frame


# ── a race in the game ──────────────────────────────────────────────────────

func _race() -> void:
	root.get_node("Net").solo()
	root.get_node("Config").set("street_handling", "sim")
	var Game = load("res://scripts/game.gd")
	var g = Game.new()
	root.add_child(g)
	# (a Formula race: 3 laps, DRS enabled from the third)
	# (as a championship's first round: its points go onto the season at the flag)
	load("res://scripts/game/track_series.gd").begin(cls, 9, "medium", 5, 10.0)
	var o: Dictionary = Modes.track_opts(9, cls, "race", 3 if cls == "formula" else 2, "cinder_ridge", {"opponents": 5, "difficulty": "medium", "start": "standing", "grid": "back", "series": 0})
	var t0 := Time.get_ticks_msec()
	await g.start(9, 1, o)
	var st = g.st
	check(g.race_ctl != null and g.field != null and g.field.drivers.size() == 5, "race: a race of 6 builds (%.0f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var me = root.get_node("Net").my_id()
	var spot: Vector2 = g.race_ctl.spots.get(me, Vector2.ZERO)
	check(g.grid_ids.size() == 6 and g.grid_ids[5] == me, "race: you start from the back of the grid (%s)" % str(g.grid_ids))
	var here: Dictionary = st.locate(g.car.global_position)
	check(absf(st.around_line(float(here.s)) - st.around_line(spot.x)) < 1.5 and absf(float(here.d) - spot.y) < 1.0, "race: your car in its grid box")
	g.use_autopilot = true
	g.begin_countdown()
	var dt := 1.0 / 120.0
	var t := 0.0
	var lights: Array = []
	var green := -1.0
	var orders: Array = []
	var t_wall := Time.get_ticks_msec()
	var hits := 0
	var drs_on := false
	var drs_open := {}
	var ers_max := 0.0
	for id in g.field.cars:
		g.field.cars[id].hit.connect(func(imp: float): hits += 1 if imp > 6.0 else 0)
	while t < 900.0 and g.state == "running":
		await physics_frame
		t += dt
		var rc = g.race_ctl
		if rc.phase == "lights" and rc.lights > 0 and (lights.is_empty() or lights[-1] != rc.lights):
			lights.append(rc.lights)
		if green < 0.0 and rc.phase == "green":
			green = t
		if int(t * 2.0) != int((t - dt) * 2.0) and rc.phase == "green":
			var ord: Array = rc.order(g._last_pos)
			if orders.is_empty() or orders[-1] != ord:
				orders.append(ord)
		if rc.drs_enabled:
			drs_on = true
		for id in g.field.cars:
			var fc = g.field.cars[id]
			if fc.race:
				if fc.race.drs_open or (fc.race.drs_avail and not g.field.near.has(id)):
					drs_open[id] = true
				ers_max = maxf(ers_max, float(fc.race.ers_used))
	var rc = g.race_ctl
	check(lights == [1, 2, 3, 4, 5] and green > 4.0 and green < 8.0, "race: the lights (%s), out at %.1f s" % [str(lights), green])
	check(rc._has_pen(me, "jump") == false and g.field.drivers.all(func(d): return not rc._has_pen(d.id, "jump")), "race: nobody jumped the start")
	var finishers: int = rc.finish_order.size()
	check(g.state == "finished" and rc.finished.has(me), "race: you took the chequered flag (%s, %.0f s of game in %.0f s)" % [g.state, t, (Time.get_ticks_msec() - t_wall) / 1000.0])
	# the others race on to the flag after you
	var t2 := 0.0
	while t2 < 300.0 and rc.phase != "done":
		await physics_frame
		t2 += dt
	check(rc.phase == "done" and rc.finish_order.size() + rc.dnf.size() == 6, "race: every car finished or retired (%d finished, %s)" % [rc.finish_order.size(), str(rc.dnf)])
	var changes := orders.size() - 1
	check(changes >= 2, "race: the places changed %d times (overtakes: the slower cars started in front)" % changes)
	var res: Array = rc.results(g._last_pos)
	var mono := true
	for k in range(1, res.size()):
		if res[k].status == "" and res[k - 1].status == "" and int(res[k].laps) == int(res[k - 1].laps) and float(res[k].total) < float(res[k - 1].total):
			mono = false
	check(mono and res.size() == 6, "race: the classification in order of laps and time (%s)" % str(res.map(func(r): return "%s %s" % [r.name, _fmt(float(r.total))])))
	check(hits <= 6, "race: %d hard hits between the AI cars and anything (racing, not crashing)" % hits)
	if cls == "formula":
		check(drs_on, "race: DRS enabled from the third lap")
		print("[raceai] info race: %d of 5 AI cars used DRS (within a second of another at a detection point)" % drs_open.size())
		check(ers_max > 0.5e6 and ers_max <= 4.0e6, "race: the AI deploy their hybrids (up to %.2f MJ in a lap; never past 4)" % (ers_max / 1.0e6))
	check(not g.race_rows.is_empty() and g._results.visible and str(g._results_label.text).contains("RACE  P"), "race: the results show your place and the classification (%s)" % str(g._results_label.text).split("\n")[0])
	var season: Dictionary = g.mode_result.get("series", {})
	var pts := 0
	for v in (season.get("points", {}) as Dictionary).values():
		pts += int(v)
	check(int(season.get("round", 0)) == 1 and pts == 25 + 18 + 15 + 12 + 10 + 8 - _dnf_points(season, g) and str(g._results_label.text).contains("CHAMPIONSHIP"),
		"race: as a championship round its points go onto the season (%d between 6 cars) and the standings show" % pts)
	g.queue_free()
	await process_frame


static func _fmt(t: float) -> String:
	if t == INF:
		return "--"
	var m := int(t / 60.0)
	return "%d:%06.3f" % [m, t - m * 60.0]


## The points the DNFs and DSQs of a championship round would have scored (they score none).
func _dnf_points(season: Dictionary, g) -> int:
	var lost := 0
	var pts := [25, 18, 15, 12, 10, 8]
	for r in g.race_rows:
		if not str(r.status) in ["", "RUNNING"] and int(r.pos) <= pts.size():
			lost += int(pts[int(r.pos) - 1])
	return lost
