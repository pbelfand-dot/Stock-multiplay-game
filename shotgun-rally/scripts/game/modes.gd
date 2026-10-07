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
	# cars a km (all lanes), their speeds (km/h), how close a near miss is (m), how often they change lanes
	"easy": {"name": "EASY", "density": 7.0, "speed": [70.0, 110.0], "near": 1.6, "lane_changes": 0.4},
	"normal": {"name": "NORMAL", "density": 12.0, "speed": [80.0, 120.0], "near": 1.2, "lane_changes": 0.7},
	"hard": {"name": "HARD", "density": 18.0, "speed": [90.0, 130.0], "near": 0.9, "lane_changes": 1.0,
		"pack": [5, 9], "pack_gap": [160.0, 300.0]},
	# insane: the traffic in packs of 8-16 cars across all four lanes, open road between (on the loop)
	"insane": {"name": "INSANE", "density": 30.0, "speed": [90.0, 140.0], "near": 0.7, "lane_changes": 1.4,
		"pack": [8, 16], "pack_gap": [170.0, 300.0]},
}
const TOUGE_LENGTH := 5000.0
const HIGHWAY_LENGTH := 8000.0


static func touge_opts(seed_value: int, dir := "up", rules := "time") -> Dictionary:
	# (a touge is run at night, mostly: the night look comes with the graphics work's
	# "night" mood; a world without it lights it as the day)
	var moods := ["night", "night", "night", "golden"]
	return {"mode": "touge", "rules": rules, "dir": dir, "length": TOUGE_LENGTH,
		"mood": moods[absi(hash([seed_value, "touge_mood"])) % moods.size()],
		"gen": {"kind": "touge", "dir": dir}}


static func cutup_opts(seed_value: int, difficulty := "normal") -> Dictionary:
	return {"mode": "cutup", "difficulty": difficulty if DIFFICULTIES.has(difficulty) else "normal",
		"length": HIGHWAY_LENGTH, "mood": "golden" if absi(hash([seed_value, "hw_mood"])) % 3 == 0 else "day",
		"gen": {"kind": "loop"}}


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
