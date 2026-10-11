extends RefCounted
## Track Mode's championship (the TRACK card's CHAMPIONSHIP): four race weekends at CINDER RIDGE,
## each in its own weather, against the same field all season (the series' seed: the same drivers
## in the same cars and colours), points to the top ten finishers by the FIA's scale (25, 18, 15,
## 12, 10, 8, 6, 4, 2, 1; a retirement scores nothing). One running per class, kept in the profile
## (Profile.track_series): START plays its next round; after the last, START begins a new one.
##
##   begin(cls, seed, difficulty, opponents, minutes) -> a new season (saved)
##   current(cls) -> the season running (or {})
##   round_like(s) -> the next round's settings for Main.mode_opts (a race weekend: qualifying, the race)
##   record(cls, rows, me) -> the race's points onto the season, its round done (saved)
##   standings(s) -> [[key, name, points, wins]] best first;  summary(s) -> one line for the menu

const Profile = preload("res://scripts/game/profile.gd")

const ROUNDS := [
	{"name": "OPENING SPRINT", "weather": "day", "laps": 5},
	{"name": "UNDER THE LIGHTS", "weather": "night", "laps": 6},
	{"name": "RAIN", "weather": "wet", "laps": 5},
	{"name": "THE FINALE", "weather": "day", "laps": 8},
]
const POINTS := [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
const YOU := "you"


static func current(cls: String) -> Dictionary:
	Profile.ensure_loaded()
	return Profile.track_series.get(cls, {})


static func begin(cls: String, seed_value: int, difficulty := "medium", opponents := 9, minutes := 10.0) -> Dictionary:
	Profile.ensure_loaded()
	var s := {"class": cls, "seed": seed_value, "round": 0, "difficulty": difficulty, "opponents": opponents,
		"minutes": minutes, "points": {}, "wins": {}, "names": {YOU: "YOU"}, "results": []}
	Profile.track_series[cls] = s
	Profile.save()
	return s


static func done(s: Dictionary) -> bool:
	return s.is_empty() or int(s.get("round", 0)) >= ROUNDS.size()


## The next round's settings (Main.mode_opts' "like"): a race weekend in its weather, its laps.
static func round_like(s: Dictionary) -> Dictionary:
	var r: Dictionary = ROUNDS[clampi(int(s.get("round", 0)), 0, ROUNDS.size() - 1)]
	return {"mode": "track", "class": str(s.get("class", "gt")), "session": "weekend", "laps": int(r.laps),
		"weather": str(r.weather), "opponents": int(s.get("opponents", 9)), "track_difficulty": str(s.get("difficulty", "medium")),
		"minutes": float(s.get("minutes", 10.0)), "series": int(s.get("round", 0)), "seed": int(s.get("seed", 1))}


## A round's title: "ROUND 2 OF 4 · UNDER THE LIGHTS".
static func round_title(k: int) -> String:
	var r: Dictionary = ROUNDS[clampi(k, 0, ROUNDS.size() - 1)]
	return "ROUND %d OF %d · %s" % [k + 1, ROUNDS.size(), str(r.name)]


## The race's classification onto the season: rows [{id, name, pos, status}] (status "" for a
## finisher, "RUNNING" for one still out when the race closed: classified; "DNF", "DSQ": nothing),
## me: your id. The round is done; the season saved.
static func record(cls: String, rows: Array, me) -> Dictionary:
	var s := current(cls)
	if done(s):
		return s
	var pts: Dictionary = s.points
	var wins: Dictionary = s.get("wins", {})
	var names: Dictionary = s.names
	var order: Array = []
	for r in rows:
		var key: String = YOU if r.id == me else str(r.id)
		if key != YOU:
			names[key] = str(r.get("name", key))
		var pos := int(r.get("pos", 99))
		var scores := str(r.get("status", "")) in ["", "RUNNING"] and pos >= 1 and pos <= POINTS.size()   # (classified: home, or still out when it closed)
		pts[key] = int(pts.get(key, 0)) + (POINTS[pos - 1] if scores else 0)
		if scores and pos == 1:
			wins[key] = int(wins.get(key, 0)) + 1
		order.append(key)
	s.wins = wins
	(s.results as Array).append(order)
	s.round = int(s.round) + 1
	Profile.track_series[cls] = s
	Profile.save()
	return s


## [[key, name, points, wins]], the most points first (a tie: the more wins, then the better last result).
static func standings(s: Dictionary) -> Array:
	var out: Array = []
	var pts: Dictionary = s.get("points", {})
	var names: Dictionary = s.get("names", {})
	var wins: Dictionary = s.get("wins", {})
	for key in pts:
		out.append([key, str(names.get(key, key)), int(pts[key]), int(wins.get(key, 0))])
	var last: Array = (s.get("results", []) as Array).back() if not (s.get("results", []) as Array).is_empty() else []
	out.sort_custom(func(a, b):
		if a[2] != b[2]:
			return a[2] > b[2]
		if a[3] != b[3]:
			return a[3] > b[3]
		return last.find(a[0]) < last.find(b[0]))
	return out


## Your place in it (1 = leading; 0: not scored yet).
static func your_place(s: Dictionary) -> int:
	var st := standings(s)
	for i in st.size():
		if st[i][0] == YOU:
			return i + 1
	return 0


## One line for the menu: where the season stands.
static func summary(s: Dictionary) -> String:
	if s.is_empty():
		return "A new championship: %d race weekends (%s), the same field all season, points to the top ten." % [ROUNDS.size(),
			", ".join(ROUNDS.map(func(r): return str(r.name).to_lower()))]
	var st := standings(s)
	var mine := 0
	for row in st:
		if row[0] == YOU:
			mine = int(row[2])
	if done(s):
		return "Championship over: you finished P%d with %d points (%s %d). START begins a new one." % [your_place(s), mine,
			str(st[0][1]) if not st.is_empty() else "-", int(st[0][2]) if not st.is_empty() else 0]
	if int(s.round) == 0:
		return "Next: %s. START to race it." % round_title(0)
	return "Next: %s. You're P%d with %d points (the leader %s, %d)." % [round_title(int(s.round)), your_place(s), mine,
		str(st[0][1]), int(st[0][2])]
