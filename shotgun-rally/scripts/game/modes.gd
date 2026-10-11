extends RefCounted
## The game modes beyond rally stages, as the options a stage is loaded with
## (Main.load_stage carries them to both machines; Game reads them):
##
##   TOUGE: a Japanese mountain pass (StageGen kind "touge"), uphill or downhill,
##     alone against the clock. TIME ATTACK: the clock, a split at every kilometre
##     against your best on that pass; DRIFT: points for sliding (TougeRules).
##   CUT UP: the LAKESHORE LOOP (LoopGen: one fixed ~28 km loop of highway: the city,
##     the bridges over the lakes, the hills' tunnels) full of traffic (Traffic): weave
##     through it as fast and as close as you dare (CutupScore), as long as you like
##     (END RUN in the pause menu). Four difficulties.
##   TRACK: a permanent circuit (CircuitGen: CINDER RIDGE, ~5 km), its pits and its grid, in a
##     class (data/track_classes.json: GT, FORMULA): PRACTICE (laps, sectors, track limits, your
##     bests: TrackSession), QUALIFYING and RACE weekends on top.

const VehicleRegistry = preload("res://scripts/game/vehicle_registry.gd")
const DIFFICULTIES := {
	# cars a km (all lanes), their speeds (km/h), how close a near miss is (m), how often they change lanes,
	# gap_k: their time gap x (a busy road's drivers sit closer).
	# HARD and INSANE are a real highway's rush hour (the owner: "legit in traffic"), by the Highway
	# Capacity Manual's levels of service for a basic freeway segment (cars a km a lane: C up to 16,
	# D up to 22, E up to 28, its capacity): HARD ~LOS D (70 a km over the four lanes, every lane busy,
	# ~1.1 s gaps), INSANE ~LOS E (100 a km, at capacity: waves of 14-26 cars across all four lanes
	# bumper to bumper, 40-90 m between them, ~1 s gaps). They were 30 and 45 (No Hesi's servers).
	"easy": {"name": "EASY", "density": 7.0, "speed": [70.0, 110.0], "near": 1.6, "lane_changes": 0.4},
	"normal": {"name": "NORMAL", "density": 15.0, "speed": [80.0, 120.0], "near": 1.2, "lane_changes": 0.7},
	"hard": {"name": "HARD", "density": 70.0, "speed": [85.0, 130.0], "near": 0.9, "lane_changes": 1.0, "gap_k": 0.85},
	"insane": {"name": "INSANE", "density": 100.0, "speed": [90.0, 140.0], "near": 0.7, "lane_changes": 1.4,
		"pack": [14, 26], "pack_gap": [40.0, 90.0], "gap_k": 0.75},
}
const TOUGE_LENGTH := 5000.0
const CIRCUITS := {"cinder_ridge": "CINDER RIDGE"}
const TRACK_SESSIONS := {"practice": "PRACTICE", "qualifying": "QUALIFYING", "race": "QUICK RACE", "weekend": "RACE WEEKEND"}
## The AI field's skill (RaceDriver): pace (a share of its car's limit: never more grip or power
## than the car has), its spread across the field, consistency (fewer mistakes), aggression.
const TRACK_DIFFICULTY := {
	"easy": {"name": "EASY", "pace": 0.88, "spread": 0.025, "consistency": 0.8, "aggression": 0.3},
	"medium": {"name": "MEDIUM", "pace": 0.93, "spread": 0.02, "consistency": 0.87, "aggression": 0.5},
	"hard": {"name": "HARD", "pace": 0.965, "spread": 0.015, "consistency": 0.93, "aggression": 0.65},
	"pro": {"name": "PRO", "pace": 0.99, "spread": 0.01, "consistency": 0.97, "aggression": 0.8},
}
const TRACK_LAPS := [3, 5, 10]
const DRIVERS_PATH := "res://data/track_drivers.json"
const CLASSES_PATH := "res://data/track_classes.json"
static var _classes := {}
static var _circuit_info := {}


## A circuit's headline numbers from its map (data/maps/<id>.json): {length (m), corners}.
static func circuit_info(circuit: String) -> Dictionary:
	if not _circuit_info.has(circuit):
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % circuit))
		_circuit_info[circuit] = {"length": float(d.length), "corners": (d.corners as Array).size()} if d is Dictionary else {"length": 0.0, "corners": 0}
	return _circuit_info[circuit]


## Track Mode's classes: {id: {name, series, blurb, cars, default, start, available}}.
static func track_classes() -> Dictionary:
	if _classes.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(CLASSES_PATH))
		if d is Dictionary:
			for k in d:
				if not str(k).begins_with("_"):
					_classes[k] = d[k]
	return _classes


## A Track Mode session's settings: its circuit (every machine builds it from the same data),
## class, session and lap count; daylight unless Settings' TIME OF DAY says otherwise. extra: the
## race's options: opponents (0-15), difficulty, start ("rolling" | "standing": the class's own by
## default), minutes (qualifying), grid ("front" | "middle" | "back" | "random": a quick race's
## place for you), damage, weekend (qualifying sets the race's grid), grid_order (the weekend's race).
static func track_opts(seed_value: int, cls := "gt", session := "practice", laps := 5, circuit := "cinder_ridge", extra := {}) -> Dictionary:
	var c: String = cls if track_classes().has(cls) else "gt"
	var ses: String = session if TRACK_SESSIONS.has(session) else "practice"
	var weekend := ses == "weekend" or bool(extra.get("weekend", false))
	if ses == "weekend":
		ses = "qualifying"
	var o := {"mode": "track", "class": c, "session": ses, "weekend": weekend,
		"laps": clampi(laps, 1, 99), "circuit": circuit, "length": 0.0, "mood": "day",
		"opponents": clampi(int(extra.get("opponents", 9)), 0, 15), "difficulty": str(extra.get("difficulty", "medium")),
		"start": str(extra.get("start", track_classes().get(c, {}).get("start", "rolling"))),
		"minutes": float(extra.get("minutes", 10.0)), "grid": str(extra.get("grid", "middle")),
		"damage": bool(extra.get("damage", true)),
		"gen": {"kind": "circuit", "circuit": circuit, "biome": "temperate_broadleaf"}}
	if extra.has("grid_order"):
		o["grid_order"] = extra.grid_order
	return o


static var _drivers: Array = []


## Track Mode's AI field for a session (RaceField's entries), the same for the same seed (a weekend's
## qualifying and race: the same drivers): its drivers (data/track_drivers.json), each in one of the
## class's cars, in its own colours and number, with a skill round the difficulty's; their pit boxes
## (yours is 8, as in practice). Each entry: {id, car, name, first, number, colours, livery, skill, box}.
## Ids are 1000 + k (the players' are their network ids).
static func track_field(o: Dictionary, seed_value: int, my_number := 0) -> Array:
	if _drivers.is_empty():
		var dd = JSON.parse_string(FileAccess.get_file_as_string(DRIVERS_PATH))
		_drivers = dd.drivers if dd is Dictionary else []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("track_field") + seed_value * 7919
	var cars: Array = (track_classes().get(str(o.get("class", "gt")), {}).get("cars", []) as Array).duplicate()
	if o.has("field_cars"):                                                   # (tests: the cars they want)
		cars = (o.field_cars as Array).duplicate()
	if OS.get_cmdline_user_args().has("--seen_cars_only"):                  # (screenshots: no no-AI cars)
		cars = cars.filter(func(c): return not VehicleRegistry.no_ai(str(c)))
	if cars.is_empty() or _drivers.is_empty():
		return []
	var names: Array = _drivers.duplicate()
	for i in range(names.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = names[i]
		names[i] = names[j]
		names[j] = tmp
	var diff: Dictionary = TRACK_DIFFICULTY.get(str(o.get("difficulty", "medium")), TRACK_DIFFICULTY.medium)
	var colours := [Color(0.78, 0.12, 0.1), Color(0.95, 0.95, 0.94), Color(0.07, 0.07, 0.08), Color(0.07, 0.2, 0.6),
		Color(0.3, 0.62, 0.9), Color(1.0, 0.8, 0.1), Color(0.95, 0.42, 0.06), Color(0.45, 0.8, 0.12), Color(0.06, 0.32, 0.16),
		Color(0.38, 0.12, 0.55), Color(0.66, 0.67, 0.7), Color(0.85, 0.2, 0.45)]
	var liveries := ["plain", "stripes", "two_tone", "comet", "vortex", "charge", "goldline", "tricolore"]
	var used := {my_number: true}
	var out: Array = []
	var n := int(o.get("opponents", 9))
	var box := 0
	for k in n:
		var num := rng.randi_range(2, 99)
		while used.has(num):
			num = rng.randi_range(2, 99)
		used[num] = true
		if box == 8:
			box += 1                                      # (yours)
		var nm: Array = names[k % names.size()]
		var pace: float = clampf(float(diff.pace) + rng.randfn(0.0, float(diff.spread)), 0.82, 1.0)
		out.append({"id": 1000 + k, "car": str(cars[rng.randi_range(0, cars.size() - 1)]),
			"name": str(nm[1]).to_upper(), "first": str(nm[0]), "number": num,
			"colours": [colours[rng.randi_range(0, colours.size() - 1)], colours[rng.randi_range(0, colours.size() - 1)]],
			"livery": liveries[rng.randi_range(0, liveries.size() - 1)],
			"skill": {"pace": pace, "consistency": clampf(float(diff.consistency) + rng.randfn(0.0, 0.03), 0.6, 0.995),
				"aggression": clampf(float(diff.aggression) + rng.randfn(0.0, 0.1), 0.0, 1.0), "reaction": rng.randf_range(0.18, 0.4)},
			"box": box % 20})
		box += 1
	return out


## The race's grid: ids in order, from pole. A weekend: qualifying's order (o.grid_order); a quick
## race: the field by pace (the quickest on pole) with you put where o.grid says.
static func track_grid(o: Dictionary, field: Array, me, seed_value: int) -> Array:
	if o.has("grid_order"):
		var g: Array = (o.grid_order as Array).duplicate()
		for e in field:
			if not e.id in g:
				g.append(e.id)
		if not me in g:
			g.append(me)
		return g.filter(func(x): return x == me or field.any(func(e): return e.id == x))
	var by := field.duplicate()
	by.sort_custom(func(a, b): return float(a.skill.pace) > float(b.skill.pace))
	var ids: Array = by.map(func(e): return e.id)
	var at := ids.size() / 2
	match str(o.get("grid", "middle")):
		"front":
			at = 0
		"back":
			at = ids.size()
		"random":
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value * 31 + 5
			at = rng.randi_range(0, ids.size())
	ids.insert(at, me)
	return ids


## The fuel a race needs (l): its laps at the line's burn and a lap and a half more.
static func race_fuel(laps: int, lap_l: float, tank: float) -> float:
	return minf(tank, (laps + 1.5) * lap_l)


## A Track Mode car's race state (RaceSim.setup's opts): mediums from cold, practice on half a
## tank (a race: enough for its laps, P5), the car's own ABS and TC at their middle maps, the air
## by the hour (cooler at night) and the track a little warmer in the sun.
static func race_opts(o: Dictionary) -> Dictionary:
	var hour := float(o.get("time", 13.0))
	var day := clampf(1.0 - absf(hour - 14.0) / 9.0, 0.0, 1.0)
	var air := lerpf(14.0, 24.0, day)
	var fuel := float(o.get("fuel", 60.0))
	# a Formula car: no ABS or traction control (FORMULA APEX's rules), its fuel flow capped (100 kg/h:
	# ~0.037 l/s flat out), a 145 l tank (110 kg, the most a race may start with), ~2.4 l a lap here
	var formula := str(o.get("class", "gt")) == "formula"
	var per_lap := 2.4 if formula else 3.4
	var tank := 145.0 if formula else 120.0
	match str(o.get("session", "practice")):
		"qualifying":
			fuel = 20.0 if formula else 30.0              # (light: a few flying laps)
		"race":
			fuel = race_fuel(int(o.get("laps", 5)), per_lap, tank)   # (a GT3: ~3.4 l a lap here: tools' estimate, tests check it)
	return {"compound": str(o.get("compound", "slick_medium")), "fuel": fuel, "tank": tank,
		"ambient": air, "track": air + 14.0 * day, "wet": float(o.get("wet", 0.0)), "abs": 0 if formula else 4, "tc": 0 if formula else 4,
		"damage": bool(o.get("damage", true)), "fuel_lps": 0.037 if formula else 0.042,
		"lap_m": circuit_info(str(o.get("circuit", "cinder_ridge"))).length}


## The car a class runs a driver in: theirs if it's one of the class's, else the class's own.
static func track_car(o: Dictionary, garage_car: String) -> String:
	var c: Dictionary = track_classes().get(str(o.get("class", "gt")), {})
	var cars: Array = c.get("cars", [])
	if garage_car in cars:
		return garage_car
	return str(c.get("default", garage_car))

const HIGHWAY_LENGTH := 8000.0


static func touge_opts(seed_value: int, dir := "up", rules := "time") -> Dictionary:
	# (a touge is run at night: the street lamps the only light, the cars' lamps on;
	# Settings' TIME OF DAY can still make it any hour)
	return {"mode": "touge", "rules": rules, "dir": dir, "length": TOUGE_LENGTH, "mood": "night",
		"gen": {"kind": "touge", "dir": dir}}


## toll: the loop's toll plaza (LoopGen.toll): "open" (every lane open, full speed through),
## "mixed" (each way's right-hand lane closed, the traffic slowed to 60), "event" (all open, the
## race's boards). In "gen": every machine builds the same plaza.
const TOLL_LAYOUTS := {"open": "ALL OPEN", "mixed": "MIXED LANES", "event": "EVENT"}

static func cutup_opts(seed_value: int, difficulty := "normal", toll := "open") -> Dictionary:
	var tl: String = toll if TOLL_LAYOUTS.has(toll) else "open"
	return {"mode": "cutup", "difficulty": difficulty if DIFFICULTIES.has(difficulty) else "normal", "toll": tl,
		"length": HIGHWAY_LENGTH, "mood": "golden" if absi(hash([seed_value, "hw_mood"])) % 3 == 0 else "day",
		"gen": {"kind": "loop", "toll": tl}}


## The light for an hour (0-24): the nearest of the world's moods ("night", "golden"
## for dawn and evening, "day"), for the stage while it's lit by mood.
static func mood_for_hour(h: float) -> String:
	h = fposmod(h, 24.0)
	if h < 5.5 or h >= 20.0:
		return "night"
	if h < 8.0 or h >= 17.0:
		return "golden"
	return "day"


## A run's settings with Settings' TIME OF DAY on them (AUTO, below 0: as they are):
## "time" (the hour) and the mood nearest it. They go to every machine with the stage.
static func with_time(o: Dictionary, hour: float) -> Dictionary:
	if hour < 0.0:
		return o
	var t := o.duplicate()
	t["time"] = fposmod(hour, 24.0)
	t["mood"] = mood_for_hour(hour)
	return t


static func difficulty(o: Dictionary) -> Dictionary:
	return DIFFICULTIES.get(str(o.get("difficulty", "normal")), DIFFICULTIES.normal)


## The title over the grid: "KAZEMAKI PASS · UPHILL · TIME ATTACK", "HIGHWAY · NORMAL".
static func title(o: Dictionary, st) -> String:
	match str(o.get("mode", "")):
		"touge":
			return "%s\n%s · %s" % [st.touge_name(), "UPHILL" if o.get("dir", "up") == "up" else "DOWNHILL",
				"DRIFT" if o.get("rules", "time") == "drift" else "TIME ATTACK"]
		"cutup":
			return "CUT UP\n%s · %s · %.0f km" % [st.touge_name() if st.has_method("wrap_s") else "HIGHWAY", difficulty(o).name, st.length / 1000.0]
		"track":
			var c: Dictionary = track_classes().get(str(o.get("class", "gt")), {})
			var ses := str(o.get("session", "practice"))
			var what: String = TRACK_SESSIONS.get(ses, "PRACTICE")
			if ses == "race":
				what = "%s · %d LAPS" % ["RACE" if bool(o.get("weekend", false)) else "QUICK RACE", int(o.get("laps", 5))]
			elif ses == "qualifying":
				what = "QUALIFYING · %d MIN" % int(o.get("minutes", 10.0))
			return "%s\n%s · %s" % [st.touge_name(), str(c.get("series", "GT")), what]
	return ""


## The key a mode's best is kept under (Profile.mode_best).
static func best_key(o: Dictionary, seed_value: int) -> String:
	match str(o.get("mode", "")):
		"touge":
			return "touge/%d/%s/%s" % [seed_value, o.get("dir", "up"), o.get("rules", "time")]
		"cutup":
			return "cutup/%s" % o.get("difficulty", "normal")
		"track":
			return "track/%s/%s" % [o.get("circuit", "cinder_ridge"), o.get("class", "gt")]
	return ""


static func is_mode(o: Dictionary) -> bool:
	return str(o.get("mode", "")) in ["touge", "cutup", "track"]
