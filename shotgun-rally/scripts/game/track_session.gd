extends RefCounted
## A Track Mode session's timing and rules (Track Mode: Modes "track"; the circuit: CircuitGen):
## every car's laps and sectors from its s round the lap (unwrapped: it keeps growing lap after
## lap, as the game tracks it), out-laps and in-laps, track limits (all four wheels past the white
## line invalidates the lap: a kerb or two wheels over is fine), each car's best sectors and lap,
## the session's bests. Pure logic (no nodes): the game feeds it every tick, the tests too.
##
## Timing as at a real circuit: the line (s = 0) and the two sector lines (CircuitGen.sectors)
## are timing loops; a car leaving its box is on an out-lap (untimed) until it crosses the line
## on the track; crossing the line in the pit lane ends a timed lap there (an in-lap) and starts
## an out-lap. Crossing times are interpolated between ticks (to the millisecond at 120 Hz).

const CAR_HALF_W := 1.0              # m from a car's middle to its wheels' outer edges: past the line by more, all four are off

var st                               # the CircuitGen
var kind := "practice"               # "practice" | "qualifying" | "race"
var time := 0.0                      # s since the session started
var cars := {}                       # id -> state (add_car)
var order: Array = []                # ids in the order they were added
var events: Array = []               # [{id, kind: "sector" | "lap" | "invalid" | "out", ...}] since last read (the game clears it)
var session_best := INF
var session_best_id = null
var session_best_sectors := [INF, INF, INF]
var stopped := {}                    # id -> true: no longer timed (it's taken the flag: RaceControl)


func setup(stage, session_kind := "practice") -> void:
	st = stage
	kind = session_kind


## A car joins at s (unwrapped round the line: a box behind the line is a little below 0).
func add_car(id, car_name: String, s_start: float, in_pits := true) -> void:
	cars[id] = {"name": car_name, "laps": 0, "s_last": s_start, "s_max": s_start, "out_lap": true, "in_pits": in_pits,
		"lap_t0": -1.0, "sector": 0, "sector_t0": -1.0, "cur": [], "valid": true, "best": INF, "best_sectors": [INF, INF, INF],
		"last": INF, "last_valid": false, "history": [], "cuts": 0, "delta": INF}
	order.append(id)


## One tick: positions = {id: {s (unwrapped), d, pit (in the pit lane)}}.
func tick(dt: float, positions: Dictionary) -> void:
	time += dt
	for id in positions:
		if cars.has(id) and not stopped.has(id):
			_advance(id, cars[id], positions[id], dt)


func _advance(id, c: Dictionary, p: Dictionary, dt: float) -> void:
	var s := float(p.s)
	var d := float(p.d)
	var pit: bool = bool(p.get("pit", false))
	c.in_pits = pit
	# track limits: a timed lap with all four wheels off is gone (the pit lane isn't off)
	if not c.out_lap and c.valid and not pit and not st.on_track(s, d, CAR_HALF_W):
		c.valid = false
		c.cuts += 1
		events.append({"id": id, "kind": "invalid", "reason": "TRACK LIMITS", "s": s})
	# the timing loops crossed going forward past the furthest it's been (no counting a line twice)
	if s > c.s_max:
		var L: float = st.length
		var loops: Array = []
		var lap0 := floori(c.s_max / L)
		var lap1 := floori(s / L)
		for lap in range(lap0, lap1 + 1):
			for k in 3:
				var b := lap * L + (0.0 if k == 0 else float(st.sectors[k - 1]))
				if b > c.s_max and b <= s:
					loops.append([b, k])
		loops.sort_custom(func(a, b): return a[0] < b[0])
		var span: float = s - float(c.s_last)
		for lp in loops:
			var tc := time - (dt * (s - float(lp[0])) / span if span > 1e-6 else 0.0)
			if int(lp[1]) == 0:
				_line(id, c, tc, pit)
			else:
				_sector(id, c, int(lp[1]) - 1, tc)
		c.s_max = s
	c.s_last = s


## The line: a timed lap ends (and a new one starts, unless it's in the pit lane: an out-lap).
func _line(id, c: Dictionary, tc: float, pit: bool) -> void:
	if not c.out_lap and c.lap_t0 >= 0.0:
		var lap_t: float = tc - float(c.lap_t0)
		var secs: Array = (c.cur as Array).duplicate()
		secs.append(tc - float(c.sector_t0))
		var valid: bool = c.valid and secs.size() == 3
		c.laps += 1
		c.last = lap_t
		c.last_valid = valid
		c.history.append({"time": lap_t, "sectors": secs, "valid": valid, "in_lap": pit})
		var pb := false
		var sb := false
		if valid:
			if lap_t < float(c.best):
				c.best = lap_t
				pb = true
			if lap_t < session_best:
				session_best = lap_t
				session_best_id = id
				sb = true
			for k in 3:
				if float(secs[k]) < float(c.best_sectors[k]):
					c.best_sectors[k] = float(secs[k])
				if float(secs[k]) < float(session_best_sectors[k]):
					session_best_sectors[k] = float(secs[k])
		events.append({"id": id, "kind": "lap", "time": lap_t, "valid": valid, "pb": pb, "session_best": sb, "lap": c.laps,
			"sectors": secs})
	if pit:
		c.out_lap = true
		c.lap_t0 = -1.0
		events.append({"id": id, "kind": "out"})
	else:
		c.out_lap = false
		c.lap_t0 = tc
	c.sector_t0 = tc
	c.sector = 0
	c.cur = []
	c.valid = true


## A sector line (k: 0 the end of sector 1, 1 the end of sector 2).
func _sector(id, c: Dictionary, k: int, tc: float) -> void:
	if c.out_lap or c.lap_t0 < 0.0:
		return
	var t: float = tc - float(c.sector_t0)
	(c.cur as Array).append(t)
	c.sector = k + 1
	c.sector_t0 = tc
	var best_k := float(c.best_sectors[k])
	c.delta = t - best_k if best_k != INF else INF
	events.append({"id": id, "kind": "sector", "sector": k, "time": t, "delta": c.delta, "valid": c.valid,
		"purple": t < float(session_best_sectors[k])})


## (a red flag's restart) The car back in a grid box at s (unwrapped), with `laps` done: the line's
## next crossing starts its lap rather than counting one.
func reposition(id, s: float, laps: int) -> void:
	var c: Dictionary = cars[id]
	c.s_last = s
	c.s_max = s
	c.laps = laps
	c.lap_t0 = -1.0
	c.sector_t0 = -1.0
	c.out_lap = false
	c.cur = []
	c.valid = true


## The current lap's running time for a car (INF on an out-lap).
func lap_time(id) -> float:
	var c: Dictionary = cars[id]
	if c.out_lap or float(c.lap_t0) < 0.0:
		return INF
	return time - float(c.lap_t0)


## Cars by best lap (practice and qualifying's order): [[id, best]], the quickest first, those
## without a time after, in the order they joined.
func classification() -> Array:
	var rows: Array = []
	for id in order:
		rows.append([id, float(cars[id].best)])
	rows.sort_custom(func(a, b): return a[1] < b[1] if a[1] != b[1] else order.find(a[0]) < order.find(b[0]))
	return rows
