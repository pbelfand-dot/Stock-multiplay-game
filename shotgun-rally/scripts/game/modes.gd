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
	return ""


## The key a mode's best is kept under (Profile.mode_best).
static func best_key(o: Dictionary, seed_value: int) -> String:
	match str(o.get("mode", "")):
		"touge":
			return "touge/%d/%s/%s" % [seed_value, o.get("dir", "up"), o.get("rules", "time")]
		"cutup":
			return "cutup/%s" % o.get("difficulty", "normal")
	return ""


static func is_mode(o: Dictionary) -> bool:
	return str(o.get("mode", "")) in ["touge", "cutup"]
