extends RefCounted
## The game modes beyond rally stages, as the options a stage is loaded with
## (Main.load_stage carries them to both machines; Game reads them):
##
##   TOUGE: a Japanese mountain pass (StageGen kind "touge"), uphill or downhill,
##     alone against the clock. TIME ATTACK: the clock, a split at every kilometre
##     against your best on that pass; DRIFT: points for sliding (TougeRules).
##   CUT UP: a highway (StageGen kind "highway") full of traffic (Traffic): weave
##     through it as fast and as close as you dare (CutupScore). Four difficulties.

const DIFFICULTIES := {
	# cars a km (all lanes), their speeds (km/h), how close a near miss is (m), how often they change lanes
	"easy": {"name": "EASY", "density": 7.0, "speed": [70.0, 110.0], "near": 1.6, "lane_changes": 0.4},
	"normal": {"name": "NORMAL", "density": 12.0, "speed": [80.0, 120.0], "near": 1.2, "lane_changes": 0.7},
	"hard": {"name": "HARD", "density": 18.0, "speed": [90.0, 130.0], "near": 0.9, "lane_changes": 1.0},
	"insane": {"name": "INSANE", "density": 26.0, "speed": [90.0, 140.0], "near": 0.7, "lane_changes": 1.4},
}
const TOUGE_LENGTH := 5000.0
const HIGHWAY_LENGTH := 8000.0


static func touge_opts(seed_value: int, dir := "up", rules := "time") -> Dictionary:
	var moods := ["day", "golden", "overcast"]
	return {"mode": "touge", "rules": rules, "dir": dir, "length": TOUGE_LENGTH,
		"mood": moods[absi(hash([seed_value, "touge_mood"])) % moods.size()],
		"gen": {"kind": "touge", "dir": dir}}


static func cutup_opts(seed_value: int, difficulty := "normal") -> Dictionary:
	return {"mode": "cutup", "difficulty": difficulty if DIFFICULTIES.has(difficulty) else "normal",
		"length": HIGHWAY_LENGTH, "mood": "golden" if absi(hash([seed_value, "hw_mood"])) % 3 == 0 else "day",
		"gen": {"kind": "highway"}}


static func difficulty(o: Dictionary) -> Dictionary:
	return DIFFICULTIES.get(str(o.get("difficulty", "normal")), DIFFICULTIES.normal)


## The title over the grid: "KAZEMAKI PASS · UPHILL · TIME ATTACK", "HIGHWAY · NORMAL".
static func title(o: Dictionary, st) -> String:
	match str(o.get("mode", "")):
		"touge":
			return "%s\n%s · %s" % [st.touge_name(), "UPHILL" if o.get("dir", "up") == "up" else "DOWNHILL",
				"DRIFT" if o.get("rules", "time") == "drift" else "TIME ATTACK"]
		"cutup":
			return "CUT UP\nHIGHWAY · %s · %.0f km" % [difficulty(o).name, st.length / 1000.0]
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
