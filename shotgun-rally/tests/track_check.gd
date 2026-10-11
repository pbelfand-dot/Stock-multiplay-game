extends SceneTree
## Track Mode: the circuit (CircuitGen: CINDER RIDGE from data/maps/cinder_ridge.json), the session's
## timing (TrackSession) and a practice lap in the game (the autopilot out of its pit box).
## Run: godot --headless --fixed-fps 120 --path . -s tests/track_check.gd [-- --only=circuit|session|game|weather|series]
##   circuit: closes on itself (position, heading, height), 4.5-6 km, 14-20 corners, no tighter than a
##     hairpin, grades and banking a real circuit's, never crosses itself (every bit of track clear of
##     every other by more than its run-off); the grid on the pit straight, behind the line, two by two;
##     the pit lane's lines in order, the lane right of the track behind the wall, the boxes in the lane;
##     the sectors in order and none tiny; the DRS zones on straights; kerbs at every corner; a barrier
##     the whole way round on both sides; each surface where it should be; locate() round the lap
##   session: a car driven round at a known speed: the out-lap untimed, the lap timed to the ms, the
##     sectors adding up to it; all four wheels over the line invalidates the lap (a kerb doesn't);
##     the pit lane ends a lap as an in-lap; bests and the classification
##   game: the circuit builds (track, kerbs, barriers, pits, garages, grid, gantry, stands), the car
##     starts in its box in the pit lane, the autopilot drives it out down the lane at the limit, onto
##     the track, round a whole timed lap (sectors and lap flashed) and the results show the best lap;
##     the race state (RaceSim) warms its tyres from cold and burns its fuel
##   weather: DAY / NIGHT / WET's settings (the light, the hour, the wet track, wets on, the title),
##     a slick against a wet tyre on the wet track, the AI's line slower in the wet, the roads' wet
##     look; a wet practice in the game: the rain and its hiss up, spray off the car at speed, the
##     wipers going, the roads dry again after it; the broadcast's TV camera (C in Track Mode) live
##   series: the championship (TrackSeries): four rounds in their weather, the same seed all season,
##     a round's settings through Main.mode_opts (a race weekend, its laps and weather, the title),
##     the FIA's points to the top ten (none for a DNF), the standings and a tie, the season saved
##     and over after the last round, a new one after it
## Prints one [track] line per check; exits 1 on any FAIL.

var CircuitGen
var TrackSession
var Modes
var fails := 0


func check(ok: bool, what: String) -> void:
	print("[track] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _initialize() -> void:
	CircuitGen = load("res://scripts/stage/circuit_gen.gd")
	TrackSession = load("res://scripts/game/track_session.gd")
	Modes = load("res://scripts/game/modes.gd")
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	await process_frame
	if only in ["", "circuit"]:
		_circuit()
	if only in ["", "session"]:
		_session()
	if only in ["", "game"]:
		await _game()
	if only in ["", "weather"]:
		await _weather()
	if only in ["", "series"]:
		_series()
	print("[track] %s" % ("TRACK OK" if fails == 0 else "TRACK FAIL"))
	quit(1 if fails else 0)


func _stage():
	var st = CircuitGen.new()
	st.opts = Modes.track_opts(1).gen
	st.generate(1)
	return st


# ── the circuit ───────────────────────────────────────────────────────────

func _circuit() -> void:
	var st = _stage()
	var st2 = _stage()
	var n: int = st.pts.size() - 1
	# the same every time
	check(st2.pts.size() == st.pts.size() and st2.pts[n / 2] == st.pts[n / 2] and st2.length == st.length,
		"circuit: the same every time (%d samples)" % n)
	# closed: the last sample one STEP on from the first, heading a full turn on, the same height
	var gap: float = (st.pts[n - 1] + (st.pts[n - 1] - st.pts[n - 2])).distance_to(st.pts[0])
	var turn: float = st.heading[n] - st.heading[0]
	check(gap < 1.0 and absf(absf(turn) - TAU) < 0.02,
		"circuit: closes on itself (%.2f m at the join, the heading %.1f deg round)" % [gap, rad_to_deg(turn)])
	var worst_step := 0.0
	for i in n:
		worst_step = maxf(worst_step, absf(st.pts[i + 1].distance_to(st.pts[i]) - st.STEP))
	check(worst_step < 0.1, "circuit: evenly sampled every %.0f m (worst off by %.3f m)" % [st.STEP, worst_step])
	check(st.length >= 4500.0 and st.length <= 6000.0, "circuit: %.3f km long (4.5 to 6)" % (st.length / 1000.0))
	var nc: int = st.track_corners.size()
	check(nc >= 14 and nc <= 20, "circuit: %d corners (14 to 20)" % nc)
	var r_min := INF
	var names := {}
	for c in st.track_corners:
		r_min = minf(r_min, float(c.r_min))
		names[str(c.name)] = true
	check(r_min >= 14.0, "circuit: no corner tighter than a hairpin (tightest radius %.0f m)" % r_min)
	var steepest := 0.0
	var max_bank := 0.0
	var y0 := INF
	var y1 := -INF
	for i in n:
		steepest = maxf(steepest, absf(st.pts[i + 1].y - st.pts[i].y) / st.STEP)
		max_bank = maxf(max_bank, absf(st.bank[i]))
		y0 = minf(y0, st.pts[i].y)
		y1 = maxf(y1, st.pts[i].y)
	check(steepest <= 0.085 and max_bank <= 0.06, "circuit: grades up to %.1f%%, banking up to %.1f%%, %.0f m from its lowest to its highest" % [
		steepest * 100.0, max_bank * 100.0, y1 - y0])
	# never crosses itself: every bit of track clear of every bit further round by more than both
	# sides' run-off (the pit straight's pit lane included)
	var close := INF
	var where := 0.0
	for i in range(0, n, 3):
		for j in range(i + 60, n, 3):
			if j > n - 60 + i:
				continue
			var dd: float = Vector2(st.pts[i].x - st.pts[j].x, st.pts[i].z - st.pts[j].z).length()
			if dd < close:
				close = dd
				where = i * st.STEP
	check(close > 45.0, "circuit: never comes back near itself (the closest two bits of track %.0f m apart, at %.0f m)" % [close, where])
	# the grid: on the pit straight, behind the line, staggered two by two, inside the white lines
	var g_ok := true
	var g_last := 1.0
	for g in st.grid:
		var s: float = float(g.s) - st.length
		if s >= 0.0 or s < -260.0 or not st.on_track(float(g.s), float(g.d), -1.0) or s > g_last + 0.01:
			g_ok = false
		g_last = s
	check(st.grid.size() == 20 and g_ok, "circuit: %d grid places behind the line, pole to last over %.0f m, each inside the white lines" % [
		st.grid.size(), -(float(st.grid[-1].s) - st.length)])
	# the pits: in order, right of the track behind the wall, the boxes in the lane
	var p: Dictionary = st.pit
	var seq := [p.s_in0, p.s_in1, p.s_lim0, p.s_box0, p.s_box1, p.s_lim1, p.s_out0, p.s_out1]
	var ordered := true
	for k in seq.size() - 1:
		ordered = ordered and float(seq[k]) < float(seq[k + 1])
	check(ordered and float(p.s_box0) < 0.0 and float(p.s_box1) > 0.0, "circuit: the pit lane's lines in order (in %d, limiter %d, boxes %d to %d, limiter %d, out %d m round the line)" % [
		int(p.s_in0), int(p.s_lim0), int(p.s_box0), int(p.s_box1), int(p.s_lim1), int(p.s_out1)])
	var lane_ok := true
	var s_l := float(p.s_lim0)
	while s_l < float(p.s_lim1):
		var inner: float = st.pit_inner_d(s_l)
		if inner < st.half_at(s_l) + 2.0 or not st.in_pit_lane(s_l, inner + 1.0) or st.in_pit_lane(s_l, 0.0):
			lane_ok = false
		s_l += 5.0
	var boxes_ok := true
	for k in int(p.boxes):
		var sd: Vector2 = st.box_sd(k)
		boxes_ok = boxes_ok and st.in_pit_lane(sd.x, sd.y) and st.in_pit_limit(sd.x, sd.y)
	check(lane_ok and boxes_ok, "circuit: the pit lane runs right of the track behind the wall (%.1f m out), its %d boxes in the lane under the %d km/h limit" % [
		float(p.lane_d0), int(p.boxes), int(p.limit_kmh)])
	# sectors
	var s1 := float(st.sectors[0])
	var s2 := float(st.sectors[1])
	var shortest := minf(s1, minf(s2 - s1, st.length - s2))
	check(0.0 < s1 and s1 < s2 and s2 < st.length and shortest > st.length * 0.2,
		"circuit: three sectors (%.2f / %.2f / %.2f km)" % [s1 / 1000.0, (s2 - s1) / 1000.0, (st.length - s2) / 1000.0])
	# DRS: on straights (nothing tighter than 250 m in a zone)
	var drs_ok: bool = st.drs.size() >= 1 and st.drs.size() <= 3
	for z in st.drs:
		var zl := posmod(float(z.s1) - float(z.s0), st.length)
		var s := float(z.s0)
		drs_ok = drs_ok and zl > 300.0 and st.drs_zone(s + 5.0) >= 0
		for q in int(zl / 10.0):
			drs_ok = drs_ok and absf(st.curv_at(s + q * 10.0)) < 1.0 / 250.0
	check(drs_ok, "circuit: %d DRS zones, each on a straight" % st.drs.size())
	# kerbs at every corner (at its apex, on its inside)
	var no_kerb := []
	for c in st.track_corners:
		var side := int(c.dir)
		var sa := float(c.s_apex)
		if st.kerb_at(sa, side * (st.half_at(sa) + 0.4)).is_empty():
			no_kerb.append("%d %s" % [int(c.n), c.name])
	check(no_kerb.is_empty() and st.kerbs.size() >= nc, "circuit: %d kerbs, one on the inside of every corner's apex%s" % [
		st.kerbs.size(), "" if no_kerb.is_empty() else " (none at %s)" % ", ".join(no_kerb)])
	# a barrier the whole way round on both sides, past the run-off
	var bare := 0
	var kinds := {}
	var s_b := 0.0
	while s_b < st.length:
		for side in [-1, 1]:
			var b: Dictionary = st.barrier_at(s_b, side)
			if b.is_empty() or absf(float(b.d)) < st.half_at(s_b) + 1.5:
				bare += 1
			else:
				kinds[str(b.kind)] = true
		s_b += 10.0
	check(bare == 0 and kinds.size() >= 2, "circuit: a barrier the whole way round both sides, clear of the track (%s)" % ", ".join(kinds.keys()))
	# surfaces: the track's asphalt, a kerb, the run-off (gravel traps, grass), the pit lane
	var c0: Dictionary = st.track_corners[0]
	var sa0 := float(c0.s_apex)
	var side0 := int(c0.dir)
	var surf := {}
	var s_s := 0.0
	while s_s < st.length:
		for d in [-14.0, -9.0, -6.5, 0.0, 6.5, 9.0, 14.0]:
			surf[st.surface_at_d(s_s, d)] = true
		s_s += 7.0
	var on_mid: String = st.surface_at_d(sa0, 0.0)
	var on_kerb: String = st.surface_at_d(sa0, side0 * (st.half_at(sa0) + 0.3))
	check(on_mid == "asphalt" and on_kerb == "kerb" and surf.has("gravel") and surf.has("grass"),
		"circuit: the surfaces where they belong (the track %s, %s's kerb %s; round the lap: %s)" % [on_mid, c0.name, on_kerb, ", ".join(surf.keys())])
	var kerb_cfg = load("res://data/surfaces/kerb.tres")
	check(kerb_cfg != null and float(kerb_cfg.grip) > 0.9 and float(kerb_cfg.peak_scale) < 1.0, "circuit: a kerb is a surface of its own (grip %.2f, rougher)" % float(kerb_cfg.grip))
	# locate round the lap
	var worst := 0.0
	var hint := -1
	var worst_d := 0.0
	var s_q := 3.0
	while s_q < st.length * 2.0:
		var pnt: Vector3 = st.world_at(s_q, 2.5)
		var got: Dictionary = st.locate(pnt, hint)
		worst = maxf(worst, absf(st.unwrap(float(got.s), s_q) - s_q))
		worst_d = maxf(worst_d, absf(float(got.d) - 2.5))
		hint = int(got.i)
		s_q += 37.0
	check(worst < 0.5 and worst_d < 0.2, "circuit: locate() finds a point's s and d two laps round (worst %.2f m, %.2f m out)" % [worst, worst_d])
	check(st.describe().begins_with("CIRCUIT") and st.touge_name() == "CINDER RIDGE", "circuit: %s, %s" % [st.touge_name(), st.describe()])


# ── the session's timing ──────────────────────────────────────────────────

## Drives a car round: from s0 to s1 at v m/s, d from dfun(s), pit from pfun(s); 120 ticks a second.
func _drive(ses, id, s0: float, s1: float, v: float, dfun: Callable, pfun: Callable) -> void:
	var s := s0
	while s < s1:
		var dt := minf(1.0 / 120.0, (s1 - s) / v)       # (the last tick short: exactly v all the way)
		s = minf(s + v * dt, s1)
		ses.tick(dt, {id: {"s": s, "d": dfun.call(s), "pit": pfun.call(s)}})


func _session() -> void:
	var st = _stage()
	var L: float = st.length
	var ses = TrackSession.new()
	ses.setup(st, "practice")
	var box: Vector2 = st.box_sd(8)
	var s_box: float = st.unwrap(box.x, 0.0)
	ses.add_car(1, "A", s_box)
	ses.add_car(2, "B", s_box)
	var mid := func(_s): return 0.0
	var no_pit := func(_s): return false
	var lane := func(s): return st.in_pit_lane(s, st.pit_inner_d(s) + 1.0) if st.pit_inner_d(s) != INF else false
	# out of the box: an out-lap, untimed (down the lane, across the line in the pit lane)
	_drive(ses, 1, s_box, float(st.pit.s_out1) + 10.0, 16.0, func(s): return st.pit_inner_d(s) + 1.0 if st.pit_inner_d(s) != INF else 0.0, lane)
	var c: Dictionary = ses.cars[1]
	check(c.out_lap and ses.lap_time(1) == INF and c.laps == 0, "session: out of the box it's an out-lap (untimed)")
	# round to the line and a full lap at 50 m/s
	ses.events.clear()
	_drive(ses, 1, float(st.pit.s_out1) + 10.0, L, 50.0, mid, no_pit)
	check(not c.out_lap and float(c.lap_t0) > 0.0, "session: crossing the line on the track starts the timed lap")
	var t_start: float = ses.time
	_drive(ses, 1, L, 2.0 * L, 50.0, mid, no_pit)
	var want := L / 50.0
	var laps: Array = ses.events.filter(func(e): return e.kind == "lap")
	var secs: Array = ses.events.filter(func(e): return e.kind == "sector")
	var lap_t: float = float(laps[0].time) if laps.size() == 1 else -1.0
	var sum := 0.0
	for x in laps[0].sectors if laps.size() == 1 else []:
		sum += float(x)
	check(laps.size() == 1 and absf(lap_t - want) < 0.002 and secs.size() == 2 and absf(sum - lap_t) < 0.0005 and laps[0].valid,
		"session: a lap at 50 m/s timed %s (%.3f s exactly: %.4f off), its sectors %s add up to it" % [
		load("res://scripts/game.gd").fmt_lap(lap_t), want, absf(lap_t - want),
		" + ".join((laps[0].sectors as Array).map(func(x): return "%.3f" % x)) if laps.size() == 1 else "?"])
	check(float(c.best) == lap_t and ses.session_best == lap_t and laps[0].pb, "session: it's the car's best and the session's (personal best flashed)")
	check(absf(ses.time - t_start - want) < 0.01, "session: (the clock ran %.3f s for it)" % (ses.time - t_start))
	# a kerb's fine (one side's wheels over the line, inside the margin); all four off invalidates
	ses.events.clear()
	var c0: Dictionary = st.track_corners[3]
	var sa := float(c0.s_apex) + 2.0 * L
	var hw: float = st.half_at(sa)
	var side := float(c0.dir)
	_drive(ses, 1, 2.0 * L, sa, 50.0, mid, no_pit)
	_drive(ses, 1, sa, sa + 20.0, 50.0, func(_s): return side * (hw + 0.6), no_pit)
	check(c.valid and ses.events.filter(func(e): return e.kind == "invalid").is_empty(), "session: two wheels over the line on a kerb keeps the lap")
	_drive(ses, 1, sa + 20.0, sa + 40.0, 50.0, func(_s): return side * (hw + 1.6), no_pit)
	var inv: Array = ses.events.filter(func(e): return e.kind == "invalid")
	check(not c.valid and inv.size() == 1 and c.cuts == 1, "session: all four wheels over the white line invalidates the lap (%s, once)" % (inv[0].reason if inv.size() > 0 else "?"))
	_drive(ses, 1, sa + 40.0, 3.0 * L, 50.0, mid, no_pit)
	var laps2: Array = ses.events.filter(func(e): return e.kind == "lap")
	check(laps2.size() == 1 and not laps2[0].valid and float(c.best) == lap_t and int(c.laps) == 2, "session: the cut lap counts but isn't timed as a best (lap %d, %s)" % [
		int(c.laps), "INVALID" if laps2.size() == 1 and not laps2[0].valid else "?"])
	# a quicker clean lap, then into the pits: an in-lap, then an out-lap
	ses.events.clear()
	_drive(ses, 1, 3.0 * L, 4.0 * L + float(st.pit.s_in0) - 10.0, 55.0, mid, no_pit)
	_drive(ses, 1, 4.0 * L + float(st.pit.s_in0) - 10.0, 4.0 * L + 20.0, 20.0, func(s): return st.pit_inner_d(s) + 1.0 if st.pit_inner_d(s) != INF else 0.0, lane)
	var laps3: Array = ses.events.filter(func(e): return e.kind == "lap")
	var outs: Array = ses.events.filter(func(e): return e.kind == "out")
	check(laps3.size() == 1 and (c.history[-1] as Dictionary).in_lap and outs.size() == 1 and c.out_lap,
		"session: crossing the line in the pit lane ends an in-lap (%.3f s) and starts an out-lap" % (float(laps3[0].time) if laps3.size() == 1 else -1.0))
	# car B: one slower lap; the classification
	_drive(ses, 2, s_box, L, 40.0, mid, no_pit)
	_drive(ses, 2, L, 2.0 * L, 45.0, mid, no_pit)
	var cl: Array = ses.classification()
	check(cl.size() == 2 and cl[0][0] == 1 and float(cl[1][1]) > float(cl[0][1]), "session: the classification by best lap (A %.3f, B %.3f)" % [float(cl[0][1]), float(cl[1][1])])


# ── a practice lap in the game ────────────────────────────────────────────

func _game() -> void:
	root.get_node("Net").solo()
	var Game = load("res://scripts/game.gd")
	var g = Game.new()
	root.add_child(g)
	var o: Dictionary = Modes.track_opts(5, "gt", "practice", 5)
	var t0 := Time.get_ticks_msec()
	await g.start(5, 1, o)
	var b = g.builder
	var parts := {}
	for k in ["start_lights", "_garage_n", "_stands_n"]:
		if k in b:
			parts[k] = b.get(k)
	check(g.built and g.circuit and g.session != null and g.mode == "track", "game: CINDER RIDGE builds and practice loads (%.0f s; %s)" % [
		(Time.get_ticks_msec() - t0) / 1000.0, Modes.title(o, g.st).replace("\n", " · ")])
	check(b.start_lights != null, "game: the start gantry's lights are up")
	var st = g.st
	var setup: Dictionary = g.car.setup
	check(str(setup.get("car", "")) in (Modes.track_classes().gt.cars as Array), "game: the car's a GT (%s)" % setup.get("name", "?"))
	var pos: Vector3 = g.car.global_position
	var here: Dictionary = st.locate(pos)
	var s_here := float(here.s)
	var dd := float(here.d)
	check(st.in_pit_lane(s_here, dd), "game: the car starts in its pit box (%.0f m round the line, %.1f m right of the track's middle)" % [st.around_line(s_here), dd])
	g.begin_countdown()
	g.use_autopilot = true
	var t := 0.0
	var top_lane := 0.0
	var left_lane := false
	var on_track := false
	var off := 0.0
	var dt := 1.0 / 120.0
	var me = root.get_node("Net").my_id()
	var sc: Dictionary = g.session.cars[me]
	var t_wall := Time.get_ticks_msec()
	# (the game reads and clears the session's events every tick: the car's record shows what happened)
	while t < 420.0 and (sc.history as Array).is_empty():
		await physics_frame
		t += dt
		if g.state != "running":
			continue
		var pit: bool = st.in_pit_lane(g.car_s, g.car_d)
		if st.in_pit_limit(g.car_s, g.car_d) and t > 1.0:
			top_lane = maxf(top_lane, g.car.kmh())
		if not pit and not left_lane and st.around_line(g.car_s) > float(st.pit.s_out1):
			left_lane = true
		if left_lane and st.on_track(g.car_s, g.car_d):
			on_track = true
		if left_lane and not sc.out_lap and not st.on_track(g.car_s, g.car_d, 1.0):
			off += dt
		if int(t / 10.0) != int((t - dt) / 10.0) and OS.get_cmdline_user_args().has("--verbose"):
			print("[track] info t %.0f s %.0f d %.1f %.0f km/h out_lap %s sector %d" % [t, g.car_s, g.car_d, g.car.kmh(), sc.out_lap, int(sc.sector)])
	check(left_lane and on_track, "game: the autopilot drives out of the box, down the pit lane and onto the track")
	check(top_lane > 20.0 and top_lane < float(st.pit.limit_kmh) + 5.0, "game: down the pit lane under the limit (top %.0f km/h, the limit %d)" % [top_lane, int(st.pit.limit_kmh)])
	var lap: Dictionary = (sc.history as Array)[0] if not (sc.history as Array).is_empty() else {}
	var lt := float(lap.get("time", INF))
	var secs: Array = lap.get("sectors", [])
	var sum := 0.0
	for x in secs:
		sum += float(x)
	check(not lap.is_empty() and secs.size() == 3 and absf(sum - lt) < 0.01 and lt > 90.0 and lt < 240.0,
		"game: a whole timed lap %s (sectors %s; %s, %.1f s with all four wheels off; %.0f s of game time in %.0f s)" % [g.fmt_lap(lt),
		" / ".join(secs.map(func(x): return "%.2f" % x)), "valid" if lap.get("valid", false) else "invalid", off, t,
		(Time.get_ticks_msec() - t_wall) / 1000.0])
	check(float(sc.best) == lt if lap.get("valid", false) else true, "game: (a valid lap is the session's best: %s)" % g.fmt_lap(float(sc.best)))
	# the race state: the tyres up from cold over the out-lap and the lap, the fuel burnt, the panel up
	var race = g.car.race
	if race:
		var temps: Array = race.tyres.map(func(x): return float(x.surface) * 0.6 + float(x.core) * 0.4)
		var used: float = 60.0 - float(race.fuel_l)
		# (the autopilot laps ~30 % off race pace: far less slip heat, so the slicks warm but stay
		# under their window, as real ones driven gently do; at pace they come in)
		check(temps.min() > race.ambient + 10.0 and temps.max() < float(race.c.window[1]) and g._race_hud != null,
			"game: the race state: mediums from %.0f C to %s C over the out-lap and a gentle lap (the window %s), the panel showing them" % [
			race.ambient, "/".join(temps.map(func(x): return "%.0f" % x)), str(race.c.window)])
		check(used > 2.0 and used < 9.0, "game: %.1f l burnt over the out-lap and the lap (a GT3 on 5 km: ~2.5-3 l a lap)" % used)
	else:
		check(false, "game: the race state is on the Track Mode car")
	g._end_run()
	var lines: Array = g.mode_result.get("lines", [])
	check(g.state == "finished" and not lines.is_empty() and str(lines[0]).begins_with("BEST LAP"), "game: END RUN shows the results (%s)" % " / ".join(lines))
	g.queue_free()
	await process_frame


# ── the weather ───────────────────────────────────────────────────────────

func _weather() -> void:
	var RaceSim = load("res://scripts/vehicle/physics/race_sim.gd")
	var RaceLine = load("res://scripts/game/race_line.gd")
	var WM = load("res://scripts/render/world_materials.gd")
	var day: Dictionary = Modes.track_opts(5, "gt", "race", 5)
	var night: Dictionary = Modes.track_opts(5, "gt", "race", 5, "cinder_ridge", {"weather": "night"})
	var wet: Dictionary = Modes.track_opts(5, "gt", "race", 5, "cinder_ridge", {"weather": "wet"})
	var odd: Dictionary = Modes.track_opts(5, "gt", "race", 5, "cinder_ridge", {"weather": "snow"})
	check(day.weather == "day" and day.mood == "day" and float(day.get("wet", 0.0)) == 0.0 and odd.weather == "day",
		"weather: DAY is the default (an unknown weather too): daylight, a dry track")
	check(night.mood == "night" and float(night.time) == 21.5 and Modes.with_time(night, 14.0).mood == "night",
		"weather: NIGHT is 21:30 under the floodlights, and keeps its hour over Settings' TIME OF DAY")
	var wd: Dictionary = Modes.with_time(wet, 14.0)
	check(wet.mood == "overcast" and float(wet.wet) == Modes.WET_TRACK and wd.mood == "overcast" and float(wd.time) == 14.0
		and Modes.with_time(wet, 22.0).mood == "night", "weather: WET is a grey sky and a wet track (%.1f), at Settings' hour too (a night hour: dark)" % float(wet.wet))
	var rd: Dictionary = Modes.race_opts(day)
	var rw: Dictionary = Modes.race_opts(wet)
	check(rd.compound == "slick_medium" and rw.compound == "wet" and float(rw.wet) == Modes.WET_TRACK and float(rw.track) < float(rd.track) - 8.0,
		"weather: dry: mediums; wet: wets on, the track %.0f C against the dry one's %.0f C (no sun on it)" % [float(rw.track), float(rd.track)])
	var title: String = Modes.title(wet, _stage())
	check(title.contains("WET") and not Modes.title(day, _stage()).contains("DAY"), "weather: the title says it (%s)" % title.replace("\n", " · "))
	# a slick against a wet tyre on the wet track, each at the temperature it runs at there
	var slick = RaceSim.new()
	slick.setup(null, {"compound": "slick_medium", "wet": Modes.WET_TRACK, "ambient": 15.0})
	var wt = RaceSim.new()
	wt.setup(null, {"compound": "wet", "wet": Modes.WET_TRACK, "ambient": 15.0})
	for k in 4:
		slick.tyres[k].surface = 40.0
		slick.tyres[k].core = 40.0
		wt.tyres[k].surface = 50.0
		wt.tyres[k].core = 48.0
	var dry_slick = RaceSim.new()
	dry_slick.setup(null, {"compound": "slick_medium", "ambient": 22.0})
	for k in 4:
		dry_slick.tyres[k].surface = 95.0
		dry_slick.tyres[k].core = 90.0
		dry_slick.tyres[k].pressure = 1.95
		wt.tyres[k].pressure = 1.95
		slick.tyres[k].pressure = 1.95
	var gs: float = slick.grip(0)
	var gw: float = wt.grip(0)
	var gd: float = dry_slick.grip(0)
	check(gw > gs * 1.3 and gw < gd * 0.9 and gw > gd * 0.7, "weather: on the wet track a wet tyre grips x%.2f, a slick x%.2f (cold and aquaplaning); a warm slick on a dry one x%.2f" % [gw, gs, gd])
	# the roads' look: darker and glossy when wet, the dry material untouched
	WM.wet = 0.0
	var a_dry = WM.asphalt({})
	WM.wet = Modes.WET_TRACK
	var a_wet = WM.asphalt({})
	WM.wet = 0.0
	var r_dry := float(a_dry.get_shader_parameter("rough_scale")) if a_dry is ShaderMaterial else float(a_dry.roughness)
	var r_wet := float(a_wet.get_shader_parameter("rough_scale")) if a_wet is ShaderMaterial else float(a_wet.roughness)
	check(a_wet != a_dry and r_wet < r_dry * 0.5 and WM.asphalt({}) == a_dry, "weather: a wet road is glossy (roughness x%.2f against %.2f dry) and a dry one is still the dry material" % [r_wet, r_dry])
	# a wet practice in the game
	root.get_node("Net").solo()
	var Game = load("res://scripts/game.gd")
	var g = Game.new()
	root.add_child(g)
	var o: Dictionary = Modes.track_opts(5, "gt", "practice", 5, "cinder_ridge", {"weather": "wet"})
	await g.start(5, 1, o)
	var race = g.car.race
	check(g.built and g.weather != null and int(g.weather.drops) > 0 and g.weather.get_node_or_null("RainSound") != null and WM.wet == Modes.WET_TRACK,
		"weather: a wet practice builds with the rain up (%d drops) and its hiss, the roads wet" % (int(g.weather.drops) if g.weather else 0))
	check(race != null and race.compound == "wet" and float(race.wet) == Modes.WET_TRACK, "weather: the car's on wets on the wet track")
	g.begin_countdown()
	g.use_autopilot = true
	var t := 0.0
	var top := 0.0
	var wiped := false
	var tv_ok := 0
	var tv_seen := 0
	var tv_far := 0.0
	while t < 60.0:
		await physics_frame
		t += 1.0 / 120.0
		top = maxf(top, g.car.kmh())
		wiped = wiped or int(g.cockpit.wipe_strokes) > 0
		g._tv = t > 45.0                          # (the last 15 s on the broadcast's TV camera)
		if t > 46.0:
			var rc = g.replay.cam
			tv_seen += 1
			var to_car: Vector3 = g.car.global_position - rc.global_position
			var aim: float = (-rc.global_transform.basis.z).dot(to_car.normalized())
			var here: Dictionary = g.st.locate(rc.global_position)
			tv_far = maxf(tv_far, to_car.length())
			if rc.current and aim > 0.95 and absf(float(here.d)) > float(g.st.half_at(float(here.s))) + 3.0:
				tv_ok += 1
	check(int(g.weather.puffs_made) > 20, "weather: spray off the car at speed (%d puffs; up to %.0f km/h)" % [int(g.weather.puffs_made), top])
	check(wiped, "weather: the wipers keep going in the rain")
	check(tv_seen > 0 and tv_ok > tv_seen * 0.9, "TV: the broadcast camera films you live from beside the track, on the car (%d of %d frames; up to %.0f m away)" % [tv_ok, tv_seen, tv_far])
	g.queue_free()
	await process_frame
	await process_frame
	check(WM.wet == 0.0, "weather: after it the roads are dry again (the menu, the next map)")


# ── the championship ──────────────────────────────────────────────────────

func _series() -> void:
	var TrackSeries = load("res://scripts/game/track_series.gd")
	var Profile = load("res://scripts/game/profile.gd")
	var Main = load("res://scripts/main.gd")
	Profile.reset()
	check(TrackSeries.current("gt").is_empty() and TrackSeries.done({}), "series: none running at first")
	var s: Dictionary = TrackSeries.begin("gt", 4242, "hard", 7, 5.0)
	var like: Dictionary = TrackSeries.round_like(s)
	var m = Main.new()
	var o: Dictionary = m.mode_opts(int(like.seed), like)
	m.free()
	check(o.mode == "track" and o.session == "qualifying" and bool(o.weekend) and int(o.laps) == 5 and o.weather == "day"
		and int(o.series) == 0 and int(o.opponents) == 7 and o.difficulty == "hard" and float(o.minutes) == 5.0 and int(like.seed) == 4242,
		"series: round 1 is a race weekend (qualifying first), 5 laps, DAY, the season's field and AI (%s)" % Modes.title(o, _stage()).replace("\n", " · "))
	check(Modes.title(o, _stage()).contains("CHAMPIONSHIP R1"), "series: the title says which round")
	var weathers: Array = TrackSeries.ROUNDS.map(func(r): return r.weather)
	check(weathers == ["day", "night", "wet", "day"], "series: the rounds' weather: %s" % ", ".join(weathers))
	# round 1: you win; the AI 1001 second; 1002 out
	var me := 1
	var rows := [{"id": me, "name": "YOU", "pos": 1, "status": ""}, {"id": 1001, "name": "NOVAK", "pos": 2, "status": ""},
		{"id": 1003, "name": "DELORME", "pos": 3, "status": "RUNNING"}, {"id": 1002, "name": "KOSTIC", "pos": 4, "status": "DNF"}]
	s = TrackSeries.record("gt", rows, me)
	var t: Array = TrackSeries.standings(s)
	check(int(s.round) == 1 and t[0][0] == "you" and int(t[0][2]) == 25 and int(t[1][2]) == 18 and int(t[2][2]) == 15 and int(t[3][2]) == 0,
		"series: round 1's points: 25, 18, 15 (still out at the close: classified), a DNF none (%s)" % str(t.map(func(r): return "%s %d" % [r[1], r[2]])))
	var like2: Dictionary = TrackSeries.round_like(TrackSeries.current("gt"))
	check(like2.weather == "night" and int(like2.laps) == 6 and int(like2.series) == 1 and int(like2.seed) == 4242,
		"series: round 2 under the lights, 6 laps, the same seed (the same field)")
	# round 2: NOVAK wins, you second: 43 each; you've a win and so has he: the last result splits them
	rows = [{"id": 1001, "name": "NOVAK", "pos": 1, "status": ""}, {"id": me, "name": "YOU", "pos": 2, "status": ""},
		{"id": 1002, "name": "KOSTIC", "pos": 3, "status": ""}, {"id": 1003, "name": "DELORME", "pos": 4, "status": ""}]
	s = TrackSeries.record("gt", rows, me)
	t = TrackSeries.standings(s)
	check(int(t[0][2]) == 43 and int(t[1][2]) == 43 and t[0][0] == "1001" and TrackSeries.your_place(s) == 2,
		"series: a tie on points and wins goes to the better last result (NOVAK 43, YOU 43: P%d)" % TrackSeries.your_place(s))
	for k in 2:
		s = TrackSeries.record("gt", rows, me)
	var saved: Dictionary = Profile.track_series.get("gt", {})
	check(TrackSeries.done(s) and int(saved.get("round", 0)) == 4 and TrackSeries.summary(s).begins_with("Championship over"),
		"series: over after round 4, kept in the profile (%s)" % TrackSeries.summary(s))
	# a save from before the ORION and ZEPHYR were taken out: both bought, the ORION driven
	var cf := ConfigFile.new()
	cf.set_value("bank", "credits", 1000)
	cf.set_value("garage", "car", "orion")
	cf.set_value("garage", "owned", {"cars": ["kestrel", "stromer", "orion", "zephyr"], "liveries": [], "wheels": ["silver"], "wheel_types": ["stock"]})
	cf.set_value("garage", "paint", {"orion": {"livery": "plain"}})
	cf.save(Profile.path())
	Profile._loaded = false
	Profile.ensure_loaded()
	check(Profile.credits == 1000 + 240000 + 250000 and not "orion" in Profile.owned.cars and not "zephyr" in Profile.owned.cars
		and Profile.car == "kestrel" and not Profile.paint.has("orion") and not "orion" in Modes.track_classes().formula.cars
		and Modes.track_car({"class": "formula"}, "orion") == "toro",
		"series: (the retired ORION / ZEPHYR) a save that bought them gets %d credits back and drives the KESTREL; FORMULA is the owner's three (%s)" % [
		Profile.credits - 1000, ", ".join(Modes.track_classes().formula.cars)])
	var s2: Dictionary = TrackSeries.begin("gt", 99, "medium", 9, 10.0)
	check(int(s2.round) == 0 and (s2.points as Dictionary).is_empty() and TrackSeries.current("formula").is_empty(),
		"series: a new season starts clean; each class has its own")
	Profile.reset()
