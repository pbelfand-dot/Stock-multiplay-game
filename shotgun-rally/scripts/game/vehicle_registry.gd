extends RefCounted
## Every vehicle in the game, from data/vehicles/<id>.json (one file each: see
## docs/vehicles.md and tools/vehicle_registry.py). The one list the garage
## (Catalog.CARS), the physics (CarSpecs.SPECS), traffic and the tests all read.
##   * garage_cars(): the cars you can drive, in the garage's order, shaped as the
##     garage has always had them (colours as Colors)
##   * physics(): each model's physics spec (CarSpecs), keyed by model id
##   * traffic_pool(): [{id, model, weight, paints}] for the traffic spawner
##   * entry(id): everything about one vehicle (null if there's none)

const DIR := "res://data/vehicles/"
const DIFFS := {"open": 0, "locked": 1, "lsd": 2}

static var _all: Array = []


## Every entry, sorted by "order" (then id).
static func all() -> Array:
	if _all.is_empty():
		_load()
	return _all


## Handled as no-AI (its licence says so, or it's treated that way): converted and
## checked by local scripts only; nobody looks at its renders. Screenshot tools
## leave these out (--seen_cars_only).
static func no_ai(id: String) -> bool:
	var e = entry(id)
	if e == null:
		return false
	var text := JSON.stringify(e)
	return text.contains("no AI") or text.contains("no-AI")


static func entry(id: String):
	for e in all():
		if e.id == id:
			return e
	return null


static func _load() -> void:
	var files := DirAccess.get_files_at(DIR)
	for f in files:
		if not f.ends_with(".json"):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
		if d is Dictionary and d.has("id"):
			_all.append(d)
		else:
			push_error("vehicle registry: can't read %s" % f)
	_all.sort_custom(func(a, b): return [float(a.get("order", 0)), str(a.id)] < [float(b.get("order", 0)), str(b.id)])


static func _colours(list) -> Array:
	var out := []
	for c in list:
		out.append(Color(float(c[0]), float(c[1]), float(c[2])))
	return out


## The garage's cars: each entry with a "garage" block, as a Catalog car.
static func garage_cars() -> Array:
	var out := []
	for e in all():
		var g = e.get("garage")
		if not g is Dictionary:
			continue
		var c := {"id": e.id, "name": e.name, "engine": str(g.get("engine_sound", "wrc")), "price": int(g.get("price", 0)),
			"livery": str(g.get("livery", "plain")), "number": int(g.get("number", 1)),
			"colours": _colours(g.get("colours", [[0.8, 0.1, 0.1], [0.95, 0.95, 0.94], [0.07, 0.07, 0.08], [0.95, 0.95, 0.94]])),
			"wheels": str(g.get("wheels", "silver")), "power": float(g.get("power", 1.0)), "grip": float(g.get("grip", 1.0)),
			"brakes": float(g.get("brakes", 1.0)), "drive_front": float(g.get("drive_front", 0.5)), "blurb": str(g.get("blurb", "")),
			"category": str(e.get("category", "")), "role": str(e.get("role", ""))}
		if str(e.get("model", "")) != "":
			c["model"] = str(e.model)
		if g.has("mass"):
			c["mass"] = float(g.mass)
		out.append(c)
	return out


## Each model's physics spec, as CarSpecs reads it (diff kinds as numbers).
static func physics() -> Dictionary:
	var out := {}
	for e in all():
		var m := str(e.get("model", ""))
		var p = e.get("physics")
		if m == "" or not p is Dictionary or out.has(m):
			continue
		var s: Dictionary = p.duplicate(true)
		for k in ["centre", "front_diff", "rear"]:
			if s.has(k) and s[k] is Array and s[k][0] is String:
				s[k][0] = DIFFS.get(s[k][0], 0)
		for k in ["mass", "front", "torque", "idle", "limiter", "turbo", "final", "cd", "area", "down", "brake"]:
			if s.has(k):
				s[k] = float(s[k])
		out[m] = s
	return out


## The traffic: every entry with a "traffic" block and a model of its own.
static func traffic_pool() -> Array:
	var out := []
	for e in all():
		var t = e.get("traffic")
		if t is Dictionary and str(e.get("model", "")) != "":
			out.append({"id": e.id, "model": str(t.get("model", e.model)), "weight": float(t.get("weight", 1.0)),
				"paints": _colours(t.get("paints", [[0.6, 0.6, 0.62]])), "role": str(e.get("role", "traffic"))})
	return out
