extends RefCounted
## Which surface a tyre is on: the meta "surface" of what it touches, either a
## name, looked up in data/surfaces/<name>.tres (spaces as underscores: "wet
## asphalt" is wet_asphalt.tres; loaded once, then kept), or a SurfaceConfig
## itself. Nothing said, or a name with no file: gravel.

const SurfaceConfig = preload("res://scripts/vehicle/physics/config/surface_config.gd")
const DIR := "res://data/surfaces/"
const DEFAULT := "gravel"
## Other names for the same surfaces (the current car's names, plain words).
const ALIASES := {"tarmac": "asphalt", "road": "asphalt", "dirt road": "dirt"}

static var _named := {}


## The surface called `n`.
static func named(n: String) -> Resource:
	n = ALIASES.get(n, n)
	if _named.has(n):
		return _named[n]
	var path := DIR + n.replace(" ", "_") + ".tres"
	var s: Resource = load(path) if ResourceLoader.exists(path) else null
	if s == null:
		if n != DEFAULT:
			push_warning("surfaces: no %s, using %s" % [path, DEFAULT])
			s = named(DEFAULT)
		else:
			s = SurfaceConfig.new()                  # (the defaults are gravel)
	_named[n] = s
	return s


## The surface of a collider (what a tyre touches).
static func of(collider: Object) -> Resource:
	if collider == null or not collider.has_meta("surface"):
		return named(DEFAULT)
	var m: Variant = collider.get_meta("surface")
	if m is Resource:
		return m
	return named(String(m))
