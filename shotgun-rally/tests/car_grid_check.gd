extends SceneTree
## The CARS grid (scripts/ui/car_grid.gd, scripts/game/car_columns.gd), without the 3D garage
## (a throwaway save):
##   * every garage car in one of the five columns (STREET, GT3, F1, RALLY, HYPERCARS), with its
##     tile's picture (tools/car_thumbs.gd); the traffic cars in none
##   * what each mode takes: the touge STREET cars, the track its class's (GT: GT3, FORMULA: F1),
##     a rally RALLY cars, cut up any
##   * every car free: owned from a new save, any one can be made the car you drive
##   * the grid: a tile per car in its column; opened for a mode, only the cars it takes can be
##     picked; a tile pressed picks it, pressed again (or DRIVE) drives it (saved); CUSTOMISE
##     asks for that car
## Run: godot --headless --path . -s tests/car_grid_check.gd -- --profile=/tmp/some.cfg
## Prints [grid] lines; exits 1 on any FAIL.

const Profile = preload("res://scripts/game/profile.gd")
const Catalog = preload("res://scripts/game/catalog.gd")
const CarColumns = preload("res://scripts/game/car_columns.gd")
const CarGrid = preload("res://scripts/ui/car_grid.gd")
const Modes = preload("res://scripts/game/modes.gd")

var fails := 0


func _initialize() -> void:
	Profile.reset()
	# the columns
	var counts := {}
	var none: Array = []
	var no_pic: Array = []
	for c in Catalog.CARS:
		var col := CarColumns.column_of(c)
		counts[col] = int(counts.get(col, 0)) + 1
		if not CarColumns.COLUMNS.any(func(x): return x[0] == col):
			none.append(c.id)
		if not FileAccess.file_exists("res://assets/ui/cars/%s.webp" % c.id):
			no_pic.append(c.id)
	fails += _check(none.is_empty() and counts.size() == 5, "every car in one of the five columns: %s%s" % [str(counts), "" if none.is_empty() else " (none: %s)" % str(none)])
	fails += _check(no_pic.is_empty(), "every car has its tile's picture (assets/ui/cars)%s" % ("" if no_pic.is_empty() else ": missing " + str(no_pic)))
	fails += _check(not Catalog.CARS.any(func(c): return str(c.get("category", "")) == "traffic"), "no traffic car in the grid")
	fails += _check(CarColumns.column_of(Catalog.car("toro")) == "f1" and CarColumns.column_of(Catalog.car("kestrel")) == "rally"
		and CarColumns.column_of(Catalog.car("affalter")) == "gt3" and CarColumns.column_of(Catalog.car("uno")) == "hyper"
		and CarColumns.column_of(Catalog.car("kaiser_3")) == "street", "a car in its column: F1, RALLY, GT3, HYPERCARS, STREET")
	# what each mode takes
	var touge := CarColumns.for_mode(Modes.touge_opts(1))
	fails += _check(touge.column == "street" and touge.ids == CarColumns.cars_in("street") and not "uno" in touge.ids and "kaiser_3" in touge.ids,
		"the touge takes the STREET cars (%d)" % touge.ids.size())
	var gt := CarColumns.for_mode(Modes.track_opts(1, "gt"))
	var gt_class: Array = Modes.track_classes().gt.cars
	fails += _check(gt.column == "gt3" and gt.ids.size() == gt_class.size() and gt.ids.all(func(id): return id in gt_class),
		"the track's GT class takes its GT3 cars (%d)" % gt.ids.size())
	var f1 := CarColumns.for_mode(Modes.track_opts(1, "formula"))
	fails += _check(f1.column == "f1" and f1.ids.size() == 3, "the FORMULA class takes the F1 cars")
	fails += _check(CarColumns.for_mode({"mode": "rally"}).ids == CarColumns.cars_in("rally"), "a rally takes the RALLY cars")
	var cut := CarColumns.for_mode(Modes.cutup_opts(1))
	fails += _check(cut.column == "" and cut.ids.size() == Catalog.CARS.size(), "cut up takes any car (%d)" % cut.ids.size())
	# every car free
	var unowned := Catalog.CARS.filter(func(c): return not Profile.owns("cars", c.id)).map(func(c): return c.id)
	fails += _check(unowned.is_empty(), "every car is free: a new save owns all %d%s" % [Catalog.CARS.size(), "" if unowned.is_empty() else " (not: %s)" % str(unowned)])
	Profile.select_car("uno")
	fails += _check(Profile.car == "uno" and Profile.credits == 0, "a hypercar driven with 0 CR: no buying")
	Profile.select_car("kestrel")


## The grid's own checks: on the first frame (a panel added before it isn't ready yet).
func _process(_dt: float) -> bool:
	# the grid
	var g = CarGrid.new()
	root.add_child(g)
	var tiles: int = g._tiles.size()
	fails += _check(tiles == Catalog.CARS.size() and g._columns.size() == 5, "the grid: %d tiles in 5 columns" % tiles)
	fails += _check(g._sel == "kestrel" and g._drive.disabled, "it opens on the car you drive (DRIVE greyed: it's yours already)")
	var drove := []
	g.drive.connect(func(id): drove.append(id))
	var asked := []
	g.customise.connect(func(id): asked.append(id))
	(g._tiles["kaiser_3"] as Button).pressed.emit()
	fails += _check(g._sel == "kaiser_3" and not g._drive.disabled and drove.is_empty(), "a tile pressed picks it (not driven yet)")
	(g._tiles["kaiser_3"] as Button).pressed.emit()
	fails += _check(drove == ["kaiser_3"] and Profile.car == "kaiser_3", "pressed again: it's the car you drive (%s)" % Profile.car)
	var cf := ConfigFile.new()
	cf.load(Profile.path())
	fails += _check(str(cf.get_value("garage", "car", "")) == "kaiser_3", "and it's saved")
	for b in g.find_children("*", "Button", true, false):
		if (b as Button).text == "CUSTOMISE":
			(b as Button).pressed.emit()
	fails += _check(asked == ["kaiser_3"], "CUSTOMISE asks for that car's paint and parts")
	g.free()
	# opened for the touge: only the STREET cars
	Profile.select_car("affalter")
	var t = CarGrid.new()
	t.mode = Modes.touge_opts(1)
	root.add_child(t)
	var shut := 0
	var open := 0
	for id in t._tiles:
		if (t._tiles[id] as Button).disabled:
			shut += 1
		else:
			open += 1
	fails += _check(open == CarColumns.cars_in("street").size() and shut == Catalog.CARS.size() - open,
		"opened for the touge: %d STREET cars to pick, %d dimmed" % [open, shut])
	fails += _check(t._sel in CarColumns.cars_in("street") and not t._drive.disabled, "your GT3 car isn't one: it starts on a street car (%s)" % t._sel)
	var started := []
	t.drive.connect(func(id): started.append(id))
	t._go()
	fails += _check(started.size() == 1 and Profile.car == started[0], "START IN THIS ONE: the mode starts in it (%s)" % Profile.car)
	t.free()
	print("[grid] %s" % ("GRID OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)
	return true


func _check(ok: bool, msg: String) -> int:
	print("[grid] %s %s" % ["ok  " if ok else "FAIL", msg])
	return 0 if ok else 1
