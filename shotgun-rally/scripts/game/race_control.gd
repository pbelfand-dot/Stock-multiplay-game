extends RefCounted
## Track Mode's race control: the start, the flags, the penalties and the classification, on top
## of TrackSession's timing. Pure logic, deterministic (the same inputs, the same calls: the host
## runs it online); the game feeds it every tick, the tests too.
##
## The start:
##   * STANDING (the Formula class): the grid's five red lights come on a second apart, stay lit
##     for a random 0.2-3 s, go out: the race is on. A car that moves more than a metre from its
##     grid box before they go out has jumped the start: +5 s.
##   * ROLLING (the GT class): the field rolls up in its double file at the pace speed (80 km/h)
##     out of the last corner; green as the leader nears the line. A car that crosses the line
##     ahead of a car that started in front of it has passed before the start: +5 s.
## The flags (at a game's level):
##   * GREEN at the start; CHEQUERED once the leader has done the laps: everyone finishes as they
##     next cross the line;
##   * YELLOW: a car stopped or crawling on the track puts a yellow out over the 250 m it's in and
##     the 250 m before; no passing there (a stricken car excepted): +5 s in a race, the lap
##     deleted in qualifying;
##   * BLUE: a car about to lap you (or, in qualifying, a car on a flying lap behind your out- or
##     in-lap): let it by;
##   * BLACK AND WHITE: the third track-limits warning; BLACK: disqualified (30 s of penalties);
##   * RED: three cars stopped at once (or red_flag()): everyone slows, no passing, and after
##     15 s the race restarts from the grid in the order it was in (standing), the laps run on.
## The penalties, escalating, never for harmless kerb use (TrackSession's track limits: all four
## wheels past the white line, a kerb or two wheels over is fine):
##   * TRACK LIMITS: a race lap off the track at speed (kept: an advantage): warnings 1-3, then +5 s
##     every time; CORNER CUTTING (off on the inside of a corner): one warning, then +5 s;
##   * PIT LANE SPEEDING (over the limit between the lines): +5 s each time in a race;
##   * PIT EXIT LINE (back onto the track before the end of the exit's taper): +5 s in a race;
##   * qualifying: track limits and a yellow delete the lap (TrackSession), the rest are warnings.
## DRS (the circuit's zones, CircuitGen.drs: each an activation zone and its detection point before
## it), as Formula 1 ran it: in a race it's enabled two laps after the start (or a restart); a car
## within a second of the car ahead of it on the road (lapped cars too) at a zone's detection point
## may open its flap in that zone; never under a yellow in the zone, never under a red. In practice and
## qualifying it's free in the zones. drs_state() says whether a car may open it now.

const LIGHTS_GAP := 1.0            # s between the red lights coming on
const PENALTY := 5.0               # s a time penalty adds
const DSQ_AT := 30.0               # s of penalties: black flag
const TL_WARNINGS := 3             # track-limits warnings before penalties
const MICRO := 250.0               # m: a yellow's stretch (a marshal post's)
const STRICKEN_V := 8.0            # m/s: under this on the track (not on the grid, not in the pits): stricken
const PACE_V := 22.2               # m/s: the rolling start's pace (80 km/h)
const RED_HOLD := 15.0             # s of slow running under a red flag before the restart
const MARK := 25.0                 # m between the timing marks the gaps are measured at
const START_GRACE := 12.0          # s after the lights go out (or a restart): a car slow off its grid box
                                   # throws no yellow, and the field sorting itself out round it isn't passing
                                   # under one (the start's own chaos, not an offence)
const DRS_GAP := 1.0               # s: within this of the car ahead at the detection point
const DRS_AFTER := 2               # laps after the start (or a restart) it's enabled

var st                             # CircuitGen
var session                        # TrackSession
var kind := "race"                 # "practice", "qualifying", "race"
var laps_total := 5
var time_limit := 600.0            # s (qualifying)
var start_type := "standing"       # "standing" | "rolling"
var phase := "grid"                # race: "grid", "formation", "lights", "green", "chequered", "red", "done"; qualifying: "open", "chequered", "done"
var lights := 0                    # red lights lit (0 .. 5)
var lights_t := 0.0
var hold := 1.5                    # s all five stay lit
var race_t := 0.0                  # s since the start (green)
var red_t := 0.0
var restarts := 0
var grid_order: Array = []         # ids in grid order
var spots := {}                    # id -> Vector2(s, d): its grid box (unwrapped s)
var finished := {}                 # id -> race time at the finish
var finish_order: Array = []
var dnf := {}                      # id -> reason
var pens := {}                     # id -> {"time": s, "list": [[text, s]], "warn": {kind: n}, "dsq": bool}
var blue := {}                     # id -> the d of the car lapping it (only while it's blue)
var bw := {}                       # id -> true once it's had its last track-limits warning
var yellows := {}                  # micro-sector -> s left
var events: Array = []             # [{id, kind, text, ...}] since last read (the game clears it)
var leader_done := false
var rng := RandomNumberGenerator.new()

var _off := {}                     # id -> {t, v0, inside}: off the track now
var _speeding := {}                # id -> true: over the pit limit now
var _was_pit := {}                 # id -> in the pit lane last tick
var _exit_flagged := {}            # id -> true: this pit exit's line already judged
var _crossed := {}                 # id -> laps it had (its first crossing of the line after a rolling start)
var _order: Array = []             # last tick's running order
var _marks := {}                   # id -> {mark: session time}
var _stricken := {}                # id -> true
var _slow_t := {}                  # id -> s it's been crawling on the track
var _line_checked := {}            # id -> true: its first crossing after a rolling start judged
var _at_flag := {}                 # (qualifying) id -> [its laps, on an out-lap] when the flag fell
var drs_enabled := false           # (a race) DRS on: two laps after the start or a restart
var _drs_from := DRS_AFTER         # the leader's laps it's enabled from
var _drs_ok := {}                  # id -> the zone it may open in (within the gap at its detection)
var _drs_seen := {}                # zone -> {id: session time it last crossed the detection point}
var _prev_s := {}                  # id -> s last tick
var _since_go := 99.0              # s since the lights last went out


func setup(stage, timing, opts: Dictionary, seed_value: int) -> void:
	st = stage
	session = timing
	kind = str(opts.get("session", "race"))
	laps_total = int(opts.get("laps", 5))
	time_limit = float(opts.get("minutes", 10.0)) * 60.0
	start_type = str(opts.get("start", "standing"))
	rng.seed = seed_value
	hold = rng.randf_range(0.2, 3.0)
	phase = "open" if kind != "race" else "grid"


## A car on the grid (race): its box (s unwrapped near 0: just behind the line).
func add_car(id, spot_s: float, spot_d: float) -> void:
	grid_order.append(id)
	spots[id] = Vector2(spot_s, spot_d)
	pens[id] = {"time": 0.0, "list": [], "warn": {}, "dsq": false}


## Off we go: the lights (standing) or the formation's roll to the line (rolling).
func begin() -> void:
	if kind != "race":
		phase = "open"
		return
	phase = "formation" if start_type == "rolling" else "lights"
	lights = 0
	lights_t = 0.0


## One tick. cars: {id: {s (unwrapped), d, v, pit}}.
func tick(dt: float, cars: Dictionary) -> void:
	match phase:
		"lights":
			lights_t += dt
			var lit := mini(int(lights_t / LIGHTS_GAP) + 1, 5)
			if lit != lights:
				lights = lit
				events.append({"id": null, "kind": "light", "n": lights})
			if lights_t >= LIGHTS_GAP * 4.0 + hold:          # (the fifth comes on at 4 s, then the hold)
				_go()
			else:
				for id in cars:                          # (jumped the start: moved off its box)
					if spots.has(id) and not _has_pen(id, "jump"):
						var c: Dictionary = cars[id]
						var p: Vector2 = spots[id]
						var off: float = Vector2(float(c.s) - p.x, float(c.d) - p.y).length()
						if off > 1.0:
							_add_pen(id, "jump", "JUMP START", PENALTY)
		"formation":
			var lead = _leader(cars)
			if lead != null and float(cars[lead].s) >= -100.0:
				_go()
		"red":
			red_t += dt
			if red_t >= RED_HOLD:
				events.append({"id": null, "kind": "restart"})
				restarts += 1
				_regrid(cars)
				phase = "lights"
				lights = 0
				lights_t = 0.0
				hold = rng.randf_range(0.2, 3.0)
	if phase in ["green", "chequered"]:
		race_t += dt
		_since_go += dt
	if kind != "race":
		if phase == "open" and session.time >= time_limit:
			phase = "chequered"
			events.append({"id": null, "kind": "chequered"})
	_marks_tick(cars)
	_judge(dt, cars)
	_flags(dt, cars)
	_drs(cars)
	if kind == "race":
		_finishes(cars)
	elif phase == "chequered":
		_quali_flag(cars)


## Qualifying's flag: a lap started before it counts; each car's done as it next crosses the line
## (an out-lap's crossing starts no lap), or once it's in the pits. Done when every car is.
func _quali_flag(cars: Dictionary) -> void:
	var running := false
	for id in cars:
		if not session.cars.has(id) or finished.has(id) or dnf.has(id):
			continue
		var c: Dictionary = session.cars[id]
		if not _at_flag.has(id):
			_at_flag[id] = [int(c.laps), bool(c.out_lap)]
		var f: Array = _at_flag[id]
		var crossed: bool = int(c.laps) > int(f[0]) or (bool(f[1]) and not bool(c.out_lap))
		var in_pits: bool = bool(cars[id].get("pit", false)) and bool(c.out_lap)
		if crossed or in_pits:
			finished[id] = session.time
			finish_order.append(id)
			session.stopped[id] = true
			events.append({"id": id, "kind": "finish", "time": session.time, "pos": finish_order.size()})
		else:
			running = true
	if not running:
		phase = "done"


func _go() -> void:
	phase = "green"
	lights = 0
	_since_go = 0.0
	events.append({"id": null, "kind": "green"})
	_drs_from = DRS_AFTER + (maxi(floori(float(_lead_s) / st.length), 0) if restarts > 0 else 0)
	if drs_enabled:
		drs_enabled = false
		events.append({"id": null, "kind": "drs", "on": false, "text": "DRS DISABLED"})


## The car leading the race (the furthest round, finished cars first).
func _leader(cars: Dictionary):
	var best = null
	var bs := -INF
	for id in cars:
		if dnf.has(id):
			continue
		if float(cars[id].s) > bs:
			bs = float(cars[id].s)
			best = id
	return best


## The running order: finished cars by their finish, then the rest by how far round they are,
## retired cars last (latest retirement first).
func order(cars: Dictionary) -> Array:
	var run: Array = []
	for id in cars:
		if not finished.has(id) and not dnf.has(id):
			run.append(id)
	run.sort_custom(func(a, b): return float(cars[a].s) > float(cars[b].s))
	var out: Array = finish_order.filter(func(x): return not dnf.has(x))
	out.append_array(run)
	for id in dnf:
		if not id in out:
			out.append(id)
	return out


## Its position (1 = leading).
func position(id, cars: Dictionary) -> int:
	return order(cars).find(id) + 1


# ── the finish ──────────────────────────────────────────────────────────────

func _finishes(cars: Dictionary) -> void:
	if not phase in ["green", "chequered"]:
		return
	var crossing := []                               # [race time at the line, id]: this tick's finishers
	for id in cars:
		if finished.has(id) or dnf.has(id) or not session.cars.has(id):
			continue
		var laps: int = session.cars[id].laps
		if not leader_done and laps >= laps_total:
			leader_done = true
			phase = "chequered"
			events.append({"id": null, "kind": "chequered"})
		if leader_done and laps > int(_crossed.get(id, -1)) and _crossed.has(id):
			# the moment it crossed (the session's, between two ticks), not the tick's: two cars over the
			# line in the same tick (1/120 s) don't share a time, and finish in the order they crossed
			var line_t := float(session.cars[id].get("line_t", -1.0))
			crossing.append([race_t - (clampf(session.time - line_t, 0.0, 1.0) if line_t >= 0.0 else 0.0), id])
		_crossed[id] = laps
	crossing.sort_custom(func(a, b): return a[0] < b[0])
	for f in crossing:
		finished[f[1]] = f[0]
		finish_order.append(f[1])
		session.stopped[f[1]] = true
		events.append({"id": f[1], "kind": "finish", "time": f[0], "pos": finish_order.size()})
	if leader_done:
		var left := false
		for id in cars:
			if not finished.has(id) and not dnf.has(id):
				left = true
		if not left:
			phase = "done"
	# (the rolling start: crossing the line ahead of a car that started in front of it)
	if start_type == "rolling" and restarts == 0:
		for id in cars:
			if not session.cars.has(id) or _has_pen(id, "formation"):
				continue
			var c: Dictionary = session.cars[id]
			if c.laps == 0 and not c.out_lap and not _line_checked.has(id):
				_line_checked[id] = true
				var k := grid_order.find(id)
				for j in range(0, maxi(k, 0)):
					var ahead = grid_order[j]
					if session.cars.has(ahead) and session.cars[ahead].out_lap and not dnf.has(ahead) and not _stricken.has(ahead):
						_add_pen(id, "formation", "OVERTAKING BEFORE THE START", PENALTY)
						break


## A car's out of the race (a retirement, a quit).
func retire(id, reason := "DNF") -> void:
	if finished.has(id) or dnf.has(id):
		return
	dnf[id] = reason
	events.append({"id": id, "kind": "dnf", "text": reason})


# ── the penalties ───────────────────────────────────────────────────────────

func _judge(dt: float, cars: Dictionary) -> void:
	var racing: bool = phase in ["green", "chequered"] or kind != "race"
	for id in cars:
		if dnf.has(id) or finished.has(id):
			continue
		var c: Dictionary = cars[id]
		var s := float(c.s)
		var d := float(c.d)
		var v := float(c.v)
		var pit: bool = bool(c.get("pit", false))
		# track limits: an excursion that kept its speed
		var off: bool = not pit and not st.on_track(s, d, session.CAR_HALF_W) and not _pit_side(s, d)
		if racing and off and not _off.has(id):
			_off[id] = {"t": 0.0, "v0": v, "inside": _inside(s, d)}
		elif _off.has(id):
			var o: Dictionary = _off[id]
			o.t = float(o.t) + dt
			if not off:
				_off.erase(id)
				if float(o.t) > 0.2 and float(o.t) < 8.0 and v > float(o.v0) * 0.7 and v > 15.0 and kind == "race" and racing:
					if bool(o.inside):
						_escalate(id, "cut", "CORNER CUTTING", 1)
					else:
						_escalate(id, "tl", "TRACK LIMITS", TL_WARNINGS)
		# the pit lane's limit
		var over: bool = st.in_pit_limit(s, d) and v * 3.6 > float(st.pit.limit_kmh) + 2.0
		if over and not _speeding.has(id):
			_speeding[id] = true
			if kind == "race" and racing:
				_add_pen(id, "pit_speed", "PIT LANE SPEEDING", PENALTY)
			else:
				_warn(id, "pit_speed", "PIT LANE SPEEDING")
		elif not over and _speeding.has(id) and not st.in_pit_limit(s, d):
			_speeding.erase(id)
		# the pit exit's line: still in the lane's taper, onto the track
		var a: float = st.around_line(s)
		var was: bool = bool(_was_pit.get(id, false))
		if was and not pit and a > float(st.pit.s_out0) and a < float(st.pit.s_out1) - 5.0 and not _exit_flagged.has(id):
			_exit_flagged[id] = true
			if kind == "race" and racing:
				_add_pen(id, "pit_exit", "CROSSING THE PIT EXIT LINE", PENALTY)
			else:
				_warn(id, "pit_exit", "CROSSING THE PIT EXIT LINE")
		if pit and a < float(st.pit.s_out0):
			_exit_flagged.erase(id)
		_was_pit[id] = pit


## Off the track on the pit side of the pit lane's tapers (the way in and out): not track limits.
func _pit_side(s: float, d: float) -> bool:
	if d <= 0.0:
		return false
	var a: float = st.around_line(s)
	var p: Dictionary = st.pit
	return (a > float(p.s_in0) - 10.0 and a < float(p.s_in1)) or (a > float(p.s_out0) and a < float(p.s_out1) + 10.0)


## Off on the inside of a corner (cutting it), not out wide.
func _inside(s: float, d: float) -> bool:
	var w: float = fposmod(s, st.length)
	for c in st.track_corners:
		if w >= float(c.s0) and w <= float(c.s1):
			return signf(d) == signf(float(c.dir))
	return false


## A warning, or past the allowance a time penalty (n: the warnings first).
func _escalate(id, key: String, text: String, n: int) -> void:
	var p: Dictionary = pens[id]
	var w: int = int(p.warn.get(key, 0)) + 1
	p.warn[key] = w
	if w <= n:
		events.append({"id": id, "kind": "warning", "text": "%s: WARNING %d/%d" % [text, w, n], "n": w})
		if key == "tl" and w == n:
			bw[id] = true
			events.append({"id": id, "kind": "flag", "flag": "bw"})
	else:
		_add_pen(id, key, text, PENALTY)


func _warn(id, key: String, text: String) -> void:
	var p: Dictionary = pens.get(id, {})
	if p.is_empty():
		pens[id] = {"time": 0.0, "list": [], "warn": {}, "dsq": false}
		p = pens[id]
	p.warn[key] = int(p.warn.get(key, 0)) + 1
	events.append({"id": id, "kind": "warning", "text": "%s: WARNING" % text})


func _add_pen(id, key: String, text: String, secs: float) -> void:
	if not pens.has(id):
		pens[id] = {"time": 0.0, "list": [], "warn": {}, "dsq": false}
	var p: Dictionary = pens[id]
	p.time = float(p.time) + secs
	(p.list as Array).append([text, secs, key])
	events.append({"id": id, "kind": "penalty", "text": "+%d S: %s" % [int(secs), text], "secs": secs})
	if float(p.time) >= DSQ_AT and not bool(p.dsq):
		p.dsq = true
		events.append({"id": id, "kind": "flag", "flag": "black"})
		dnf[id] = "DSQ"                                  # (even after the flag: out of the results)
		events.append({"id": id, "kind": "dnf", "text": "DSQ"})


func _has_pen(id, key: String) -> bool:
	for e in pens.get(id, {}).get("list", []):
		if str(e[2]) == key:
			return true
	return false


## Its time penalties (s).
func penalty_time(id) -> float:
	return float(pens.get(id, {}).get("time", 0.0))


# ── the flags ───────────────────────────────────────────────────────────────

func _flags(dt: float, cars: Dictionary) -> void:
	var L: float = st.length
	# stricken cars: yellows over their stretch and the one before
	var n_stricken := 0
	var running: bool = phase in ["green", "chequered", "open"]
	for id in cars:
		var c: Dictionary = cars[id]
		var slow: bool = running and not bool(c.get("pit", false)) and float(c.v) < STRICKEN_V and not finished.has(id) and not dnf.has(id) \
			and not st.in_pit_lane(float(c.s), float(c.d)) and not _leaving_grid(id, c)
		_slow_t[id] = float(_slow_t.get(id, 0.0)) + dt if slow else 0.0
		if float(_slow_t[id]) > 2.5:                   # (crawling for a while: not a car pulling away)
			_stricken[id] = true
			n_stricken += 1
			var m := floori(fposmod(float(c.s), L) / MICRO)
			var nm := ceili(L / MICRO)
			for q in [m, posmod(m - 1, nm)]:
				if not yellows.has(q):
					events.append({"id": null, "kind": "yellow", "sector": q})
				yellows[q] = 5.0
		else:
			_stricken.erase(id)
	for q in yellows.keys():
		yellows[q] = float(yellows[q]) - dt
		if float(yellows[q]) <= 0.0:
			yellows.erase(q)
			events.append({"id": null, "kind": "yellow_clear", "sector": q})
	if kind == "race" and phase in ["green"] and n_stricken >= 3:
		red_flag("THREE CARS STOPPED")
	# passing under a yellow: the order changed between two cars both in a yellow's stretch
	var now := order(cars)
	if phase in ["green", "chequered", "open"] and kind == "race" and not _order.is_empty() and _since_go >= START_GRACE:
		for k in range(1, now.size()):
			var a = now[k - 1]
			var b = now[k]
			if _order.find(a) > _order.find(b) and _order.find(a) >= 0 and cars.has(a) and cars.has(b) and not finished.has(a):
				if in_yellow(float(cars[a].s)) and in_yellow(float(cars[b].s)) and not _stricken.has(b):
					_add_pen(a, "yellow", "OVERTAKING UNDER YELLOW", PENALTY)
	_order = now
	# blue flags: a car a lap up within ~1.2 s behind (qualifying: a flying lap behind an out-lap)
	blue.clear()
	for id in cars:
		if dnf.has(id) or finished.has(id):
			continue
		var c: Dictionary = cars[id]
		for jd in cars:
			if jd == id or dnf.has(jd):
				continue
			var o: Dictionary = cars[jd]
			var gap: float = fposmod(float(c.s) - float(o.s) + L * 0.5, L) - L * 0.5    # + : it's behind us
			var near: bool = gap > 0.0 and gap < maxf(float(o.v) * 1.2, 25.0)
			if not near:
				continue
			var lapping: bool = false
			if kind == "race":
				lapping = float(o.s) - float(c.s) > L * 0.5
			elif session.cars.has(id) and session.cars.has(jd):
				lapping = session.cars[id].out_lap and not session.cars[jd].out_lap and float(o.v) > float(c.v) + 2.0
			if lapping:
				blue[id] = float(o.d)


## A car just after the start still on (or by) its grid box: slow away, not stricken.
func _leaving_grid(id, c: Dictionary) -> bool:
	if kind != "race" or _since_go >= START_GRACE or not spots.has(id):
		return false
	var p: Vector2 = spots[id]
	return absf(float(c.s) - p.x) < 15.0


## Is there a yellow over s?
func in_yellow(s: float) -> bool:
	return yellows.has(floori(fposmod(s, st.length) / MICRO))


# ── DRS ─────────────────────────────────────────────────────────────────────

var _lead_s := 0.0                 # the leader's s (unwrapped) last tick


## The detection points: a car crossing one is timed against the car that crossed it last before it
## (the car ahead on the road, lapped or not); within DRS_GAP it may open in that zone this lap. DRS
## is enabled (a race) from the leader's lap DRS_AFTER after the start, disabled under a red flag.
func _drs(cars: Dictionary) -> void:
	var zones: Array = st.drs if st and "drs" in st else []
	var lead = _leader(cars)
	if lead != null:
		_lead_s = float(cars[lead].s)
	if kind == "race":
		var on := phase in ["green", "chequered"] and lead != null and floori(_lead_s / st.length) >= _drs_from
		if on != drs_enabled:
			drs_enabled = on
			events.append({"id": null, "kind": "drs", "on": on, "text": "DRS ENABLED" if on else "DRS DISABLED"})
	for id in cars:
		var c: Dictionary = cars[id]
		var s := float(c.s)
		var was := float(_prev_s.get(id, s))
		_prev_s[id] = s
		if kind != "race" or bool(c.get("pit", false)) or dnf.has(id):
			continue
		for k in zones.size():
			var det := float(zones[k].detect)
			if floori((s - det) / st.length) <= floori((was - det) / st.length):
				continue
			# crossed zone k's detection point: against the car through it last
			if not _drs_seen.has(k):
				_drs_seen[k] = {}
			var seen: Dictionary = _drs_seen[k]
			var ahead := INF
			for o in seen:
				if o != id:
					ahead = minf(ahead, session.time - float(seen[o]))
			seen[id] = session.time
			if ahead <= DRS_GAP:
				_drs_ok[id] = k
			elif int(_drs_ok.get(id, -1)) == k:
				_drs_ok.erase(id)


## Whether car id may open its DRS now (at s): in a zone; in a race, DRS enabled, within the gap at
## that zone's detection point; never under a yellow there or a red.
func drs_state(id, s: float) -> bool:
	if st == null or not ("drs" in st):
		return false
	var k: int = st.drs_zone(fposmod(s, st.length))
	if k < 0 or in_yellow(s) or phase == "red":
		return false
	if kind != "race":
		return true
	return drs_enabled and int(_drs_ok.get(id, -1)) == k


## A red flag: everyone slows, no passing, a standing restart from the order it's in.
func red_flag(reason := "") -> void:
	if phase != "green":
		return
	phase = "red"
	red_t = 0.0
	events.append({"id": null, "kind": "red", "text": reason})


## The restart's grid: the running order now, into the grid's boxes. Every car on the lead lap
## restarts on the leader's lap (a car a lap or more down stays that many down), its partial lap
## run again (TrackSession.reposition: the crossing at the restart starts a lap, it doesn't count
## one). The game and RaceField put the cars in their boxes ("regrid": spots).
func _regrid(cars: Dictionary) -> void:
	var now := order(cars)
	grid_order = []
	for id in now:
		if not dnf.has(id) and not finished.has(id) and cars.has(id):
			grid_order.append(id)
	if grid_order.is_empty():
		return
	var L: float = st.length
	var lead = grid_order[0]
	var lead_s := float(cars[lead].s)
	var lead_laps: int = session.cars[lead].laps if session.cars.has(lead) else 0
	for k in grid_order.size():
		var id = grid_order[k]
		var g: Dictionary = st.grid[mini(k, st.grid.size() - 1)]
		var down := floori((lead_s - float(cars[id].s)) / L)
		var lp := maxi(lead_laps - down, 0)
		var gs := float(g.s)
		if gs > L * 0.5:
			gs -= L                                      # (just behind the line)
		var s_new := lp * L + gs
		spots[id] = Vector2(s_new, float(g.d))
		if session.cars.has(id):
			session.reposition(id, s_new, lp)
	events.append({"id": null, "kind": "regrid", "order": grid_order.duplicate(), "spots": spots.duplicate()})


# ── the gaps ────────────────────────────────────────────────────────────────

## Each car's time at each timing mark it passes (every MARK m), for the gaps.
func _marks_tick(cars: Dictionary) -> void:
	for id in cars:
		if not _marks.has(id):
			_marks[id] = {}
		var m := floori(float(cars[id].s) / MARK)
		var mk: Dictionary = _marks[id]
		if not mk.has(m):
			mk[m] = session.time
			var old := m - int(2.0 * st.length / MARK)
			if mk.has(old):
				mk.erase(old)


## The gap (s) from car a ahead to car b behind on the road: when a passed where b is now.
## INF if not known (a lap or more apart, or not passed there yet).
func gap(a, b, cars: Dictionary) -> float:
	if not _marks.has(a) or not _marks.has(b) or not cars.has(b):
		return INF
	var m := floori(float(cars[b].s) / MARK)
	var ta = _marks[a].get(m)
	var tb = _marks[b].get(m)
	if ta == null or tb == null:
		return INF
	return float(tb) - float(ta)


# ── the results ─────────────────────────────────────────────────────────────

## The classification: [{pos, id, name, laps, time, total, best, pens, status}] (a race: by laps
## and time with its penalties added; qualifying and practice: by best lap).
func results(cars: Dictionary) -> Array:
	var rows: Array = []
	if kind != "race":
		var cl: Array = session.classification()
		for k in cl.size():
			var id = cl[k][0]
			var c: Dictionary = session.cars[id]
			rows.append({"pos": k + 1, "id": id, "name": c.name, "laps": c.laps, "best": float(c.best), "time": float(c.best),
				"total": float(c.best), "pens": penalty_time(id), "status": "DNF" if dnf.has(id) else ""})
		return rows
	var fin: Array = []
	for id in finish_order:
		if not dnf.has(id):
			fin.append([id, float(finished[id]) + penalty_time(id), int(session.cars[id].laps) if session.cars.has(id) else 0])
	# (the penalties can reorder the finishers on the same lap)
	fin.sort_custom(func(x, y): return x[2] > y[2] or (x[2] == y[2] and x[1] < y[1]))
	var ord: Array = []
	for f in fin:
		ord.append(f[0])
	for id in order(cars):
		if not id in ord:
			ord.append(id)
	for k in ord.size():
		var id = ord[k]
		var c: Dictionary = session.cars.get(id, {"name": str(id), "laps": 0, "best": INF})
		var status := ""
		if dnf.has(id):
			status = str(dnf[id])
		elif not finished.has(id):
			status = "RUNNING"
		var t: float = float(finished.get(id, INF))
		rows.append({"pos": k + 1, "id": id, "name": c.name, "laps": int(c.laps), "best": float(c.best), "time": t,
			"total": t + penalty_time(id) if t != INF else INF, "pens": penalty_time(id), "status": status})
	return rows


## The race's fastest lap: [id, time] ([null, INF] if none yet).
func fastest_lap() -> Array:
	return [session.session_best_id, session.session_best]
