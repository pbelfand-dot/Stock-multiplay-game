extends RefCounted
## The player's save (user://profile.cfg, or --profile=PATH for tests):
## credits, the cars and paint they own, how each car is set up (upgrades,
## tyres and setup), story
## progress and best stage times. One per copy of the game; everything is
## static (use it straight off the script: Profile.credits, Profile.buy_car()).
##
## Credits are earned by finishing stages (stage_credits: a base, more for a
## longer stage, a bonus for beating the pace and for a clean run, half as much
## again in story mode) and story rallies (Championship.reward). Both players
## in a crew earn. There's no real money anywhere.

const Catalog = preload("res://scripts/game/catalog.gd")

static var credits := 0
static var car := "kestrel"                 # the one you drive
static var owned := {"cars": ["kestrel"], "liveries": [], "wheels": ["silver"]}
static var paint := {}                      # car id -> {colours, livery, wheels, number}
static var levels := {}                     # car id -> {engine, tyres, brakes}: upgrade steps bought
static var tuning := {}                     # car id -> {tyre, preset}: "auto", "gravel" or "tarmac"
static var story := {}                      # rally id -> {done, best_pos, best_total}
static var bests := {}                      # "seed/length" -> best total (s)
static var _loaded := false


static func path() -> String:
	var p := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--profile="):
			p = a.trim_prefix("--profile=")
	return p if p != "" else "user://profile.cfg"


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(path()) != OK:
		return
	credits = int(cf.get_value("bank", "credits", credits))
	car = str(cf.get_value("garage", "car", car))
	owned = cf.get_value("garage", "owned", owned)
	paint = cf.get_value("garage", "paint", paint)
	levels = cf.get_value("garage", "levels", levels)
	tuning = cf.get_value("garage", "tuning", tuning)
	story = cf.get_value("story", "rallies", story)
	bests = cf.get_value("story", "bests", bests)
	for k in ["cars", "liveries", "wheels"]:              # an old or hand-edited file
		if not owned.has(k):
			owned[k] = []
	if not "kestrel" in owned.cars:
		owned.cars.append("kestrel")
	if not car in owned.cars:
		car = "kestrel"


static func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("bank", "credits", credits)
	cf.set_value("garage", "car", car)
	cf.set_value("garage", "owned", owned)
	cf.set_value("garage", "paint", paint)
	cf.set_value("garage", "levels", levels)
	cf.set_value("garage", "tuning", tuning)
	cf.set_value("story", "rallies", story)
	cf.set_value("story", "bests", bests)
	cf.save(path())


# ── money ─────────────────────────────────────────────────────────────────

static func earn(n: int) -> void:
	ensure_loaded()
	credits += maxi(n, 0)
	save()


## Pay n if there's enough; false (and nothing spent) if not.
static func spend(n: int) -> bool:
	ensure_loaded()
	if n > credits:
		return false
	credits -= n
	save()
	return true


## Credits for a finished stage: result {total, penalties}, the stage's length (m).
## The pace is ~60 km/h: every second quicker pays 8 more (up to 900).
static func stage_credits(result: Dictionary, length: float, story_mode := false) -> Dictionary:
	var base := 300 + int(length / 1000.0 * 100.0)
	var par := length / (60.0 / 3.6)
	var pace := clampi(int((par - float(result.total)) * 8.0), 0, 900)
	var clean := 200 if float(result.penalties) == 0.0 else 0
	var total := base + pace + clean
	if story_mode:
		total = int(total * 1.5)
	return {"base": base, "pace": pace, "clean": clean, "total": total, "story": story_mode}


# ── the garage ────────────────────────────────────────────────────────────

## Owned? (a car's own livery always is: for_car, else the car you drive)
static func owns(kind: String, id: String, for_car := "") -> bool:
	ensure_loaded()
	if kind == "liveries" and id == Catalog.car(for_car if for_car != "" else car).livery:
		return true                                       # every car comes in its own colours
	if kind == "liveries" and Catalog.livery(id).price == 0:
		return true
	if kind == "wheels" and Catalog.wheels(id).price == 0:
		return true
	return id in owned.get(kind, [])


## Buy something (cars / liveries / wheels): false if it's owned or too dear.
static func buy(kind: String, id: String, price: int) -> bool:
	ensure_loaded()
	if id in owned[kind] or not spend(price):
		return false
	owned[kind].append(id)
	save()
	return true


static func select_car(id: String) -> void:
	ensure_loaded()
	if id in owned.cars:
		car = id
		save()


static func paint_of(car_id: String) -> Dictionary:
	ensure_loaded()
	return paint.get(car_id, {})


static func set_paint(car_id: String, key: String, value) -> void:
	ensure_loaded()
	if not paint.has(car_id):
		paint[car_id] = {}
	paint[car_id][key] = value
	save()


static func level(car_id: String, part: String) -> int:
	ensure_loaded()
	return int(levels.get(car_id, {}).get(part, 0))


## Buy the next step of an upgrade for a car: false if maxed or too dear.
static func upgrade(car_id: String, part: String) -> bool:
	var lvl := level(car_id, part)
	if lvl >= 3 or not spend(Catalog.UPGRADES[part].prices[lvl]):
		return false
	if not levels.has(car_id):
		levels[car_id] = {}
	levels[car_id][part] = lvl + 1
	save()
	return true


## A car's tyres and setup: {tyre, preset}.
static func tuning_of(car_id: String) -> Dictionary:
	ensure_loaded()
	return tuning.get(car_id, {})


static func set_tuning(car_id: String, key: String, value: String) -> void:
	ensure_loaded()
	if not tuning.has(car_id):
		tuning[car_id] = {}
	tuning[car_id][key] = value
	save()


## The car you'll drive, as the game builds it (and sends to your crewmate).
static func setup() -> Dictionary:
	ensure_loaded()
	return Catalog.setup(car, paint_of(car), levels.get(car, {}), tuning_of(car))


static func setup_for(car_id: String) -> Dictionary:
	ensure_loaded()
	return Catalog.setup(car_id, paint_of(car_id), levels.get(car_id, {}), tuning_of(car_id))


# ── story ─────────────────────────────────────────────────────────────────

static func rally_record(id: String) -> Dictionary:
	ensure_loaded()
	return story.get(id, {})


## Rally i is open once the one before it has been finished (or once it, or a
## rally after it, has been driven: new rallies slot into the season without
## locking anyone out of what they'd already reached).
static func rally_open(i: int, rallies: Array) -> bool:
	if i == 0 or rally_record(rallies[i - 1].id).get("done", false):
		return true
	for k in range(i, rallies.size()):
		if not rally_record(rallies[k].id).is_empty():
			return true
	return false


static func finish_rally(id: String, pos: int, total: float) -> void:
	ensure_loaded()
	var r: Dictionary = story.get(id, {})
	r.done = true
	r.best_pos = mini(int(r.get("best_pos", 99)), pos)
	r.best_total = minf(float(r.get("best_total", INF)), total)
	story[id] = r
	save()


## A stage's best time (INF if never finished); true if this one beat it.
static func record_stage(seed_value: int, length: float, total: float) -> bool:
	ensure_loaded()
	var key := "%d/%d" % [seed_value, int(length)]
	var best: float = bests.get(key, INF)
	if total < best:
		bests[key] = total
		save()
		return true
	return false


## Forget everything (tests).
static func reset() -> void:
	credits = 0
	car = "kestrel"
	owned = {"cars": ["kestrel"], "liveries": [], "wheels": ["silver"]}
	paint = {}
	levels = {}
	tuning = {}
	story = {}
	bests = {}
	_loaded = true
