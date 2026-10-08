extends RefCounted
## The world's biomes (data/biomes.json): what grows by a road, what lies about, how it's lit
## and dressed, by season. Static: `const Biomes = preload("res://scripts/stage/biomes.gd")`.
##
##   Biomes.for_stage(st) -> Dictionary: the biome a stage is in (its own "biome" in the stage's
##     opts: a story rally names one; else from what the stage is: a touge, snow and ice, mountain
##     tarmac, mixed, puddles, plain gravel), with its season ("season" in the opts, or the
##     biome's own) merged in: {id, name, trees: [[asset, weight]...], broad: [...], tree_scale,
##     rocks: {...}, cliffs, ground_tint, foliage_tint, broad_tint, fog, season}
##   Biomes.pick(list, rng) -> String: a weighted pick ([[id, weight], ...]), from the stage's own
##     dice (the same on every machine)
##   Biomes.ids() -> Array: every biome's id

const DATA := "res://data/biomes.json"

static var _data: Dictionary = {}


static func _load() -> void:
	if not _data.is_empty():
		return
	var f := FileAccess.open(DATA, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	_data = d if d is Dictionary else {"biomes": {}}


static func ids() -> Array:
	_load()
	var out: Array = (_data.get("biomes", {}) as Dictionary).keys()
	out.sort()
	return out


static func id_for(st) -> String:
	var o: Dictionary = st.opts
	if o.has("biome"):
		return str(o.biome)
	match str(st.kind):
		"touge":
			return "japan_cedar"
		"highway", "loop":
			return "suburban_verge"
	if o.get("ice", false):
		return "winter_mountain"
	if str(o.get("surface", "gravel")) == "tarmac":
		return "alpine_rock"
	if str(o.get("surface", "gravel")) == "mixed":
		return "temperate_broadleaf"
	if float(o.get("puddles", 1.0)) > 1.5:
		return "wet_forest"
	return "conifer_rally"


static func for_stage(st) -> Dictionary:
	_load()
	var all: Dictionary = _data.get("biomes", {})
	var id := id_for(st)
	if not all.has(id):
		id = "conifer_rally"
	var b: Dictionary = (all.get(id, {}) as Dictionary).duplicate(true)
	b["id"] = id
	var season := str(st.opts.get("season", b.get("season", "summer")))
	b["season"] = season
	var s: Dictionary = b.get("seasons", {}).get(season, {})
	for k in s:
		b[k] = s[k]
	return b


static func pick(list: Array, rng: RandomNumberGenerator) -> String:
	if list.is_empty():
		return ""
	var total := 0.0
	for e in list:
		total += float(e[1])
	var x := rng.randf() * total
	for e in list:
		x -= float(e[1])
		if x <= 0.0:
			return str(e[0])
	return str(list[list.size() - 1][0])


## A colour from the data ([r, g, b] or [r, g, b, a]); white if missing.
static func colour(v, fallback := Color.WHITE) -> Color:
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
	return fallback
