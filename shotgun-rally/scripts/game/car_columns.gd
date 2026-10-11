extends RefCounted
## The CARS grid's columns (scripts/ui/car_grid.gd), and which cars a mode takes: the owner's
## sketch (2026-10-11). STREET (the road cars: the touge's), GT3 (the race cars: the track's GT
## class), F1 (the Formula cars), RALLY, HYPERCARS. A touge takes STREET cars; the track its
## class's (GT: from GT3, FORMULA: F1); a rally (the Shotgun Series, PLAY NOW) a RALLY car; cut up
## and the rest any car.

const Catalog = preload("res://scripts/game/catalog.gd")
const Modes = preload("res://scripts/game/modes.gd")

const COLUMNS := [["street", "STREET"], ["gt3", "GT3"], ["f1", "F1"], ["rally", "RALLY"], ["hyper", "HYPERCARS"]]


## A car's column (a Catalog.CARS entry): by what the registry says it is.
static func column_of(c: Dictionary) -> String:
	var cat := str(c.get("category", ""))
	var role := str(c.get("role", ""))
	if role == "formula":
		return "f1"
	if cat == "rally" or role == "rally":
		return "rally"
	if cat == "hyper":
		return "hyper"
	if cat == "race":
		return "gt3"
	return "street"


## The cars in a column ("": every car), in the garage's order.
static func cars_in(col: String) -> Array:
	var out := []
	for c in Catalog.CARS:
		if col == "" or column_of(c) == col:
			out.append(str(c.id))
	return out


## What a mode takes: {column ("": any), ids (the cars it allows, in the garage's order)}.
static func for_mode(m: Dictionary) -> Dictionary:
	match str(m.get("mode", "")):
		"touge":
			return {"column": "street", "ids": cars_in("street")}
		"track":
			var cls := str(m.get("class", "gt"))
			var col := "f1" if cls == "formula" else "gt3"
			var cars: Array = Modes.track_classes().get(cls, {}).get("cars", [])
			return {"column": col, "ids": cars_in(col).filter(func(id): return id in cars)}
		"rally":
			return {"column": "rally", "ids": cars_in("rally")}
	return {"column": "", "ids": cars_in("")}


## Can this car be driven in that mode?
static func allows(m: Dictionary, id: String) -> bool:
	return id in for_mode(m).ids


## A car's tile picture (tools/car_thumbs.gd), or null when it has none yet.
static func thumb(id: String) -> Texture2D:
	var path := "res://assets/ui/cars/%s.webp" % id
	return load(path) if ResourceLoader.exists(path) else null
