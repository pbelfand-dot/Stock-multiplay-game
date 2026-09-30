extends RefCounted
## The car makers with a dealership off the highway (docs/BRANDS.md: parody
## names only, never the real ones or their logos). A car's maker is its
## Rules.CARS "brand"; no brand = "bemze" (the BEMZE cars, and the used TOROLA
## that the BEMZE lot takes as a trade-in and sells on).
## Per brand:
##   name, tagline     the sign, the showroom menu's title, the billboards
##   motors            what the cabbie, the phone and the exit signs call the place
##   ui                the showroom menu's colour (its frame, bars, the turntable ring)
##   exit              the highway exit number
##   pick              the car on the menu's turntable when you walk in ("" = the flagship)
##   lineup            the display order on the lot (the rest: priciest first)
##   look              the building's colours (Dealership: the kit showroom, recoloured):
##       wall (the white panels), trim (the grey), band (the dark cladding, sign band,
##       pylon), floor, accent (the orange: LED rings, light strips), ink (lettering),
##       face (the pylon's lit face)
## BEMZE's look is empty: its kit pieces as they come.

const Rules = preload("res://scripts/sim/rules.gd")

const ORDER := ["bemze", "mercedez", "porsha", "audy"]
const BRANDS := {
	"bemze": {"name": "BEMZE", "motors": "BEMZE Motors", "tagline": "THE ULTIMATE CUT-UP MACHINE",
		"ui": Color(0.12, 0.45, 0.85), "exit": 6, "pick": "bz_m3",
		"lineup": ["bz_m8", "bz_m5", "bz_m4", "bz_m3", "bz_m3t", "bz_m2", "bz_540i"], "look": {}},
	"mercedez": {"name": "MERCEDEZ BANZ", "motors": "Mercedez Banz", "tagline": "THE BEST OR NOTHING. MOSTLY NOTHING.",
		"ui": Color(0.74, 0.77, 0.82), "exit": 7, "pick": "", "lineup": [],
		"look": {"wall": Color(0.36, 0.37, 0.4), "trim": Color(0.13, 0.135, 0.145), "band": Color(0.035, 0.035, 0.04),
			"floor": Color(0.42, 0.43, 0.45), "accent": Color(0.8, 0.84, 0.9), "ink": Color(0.9, 0.92, 0.95),
			"face": Color(0.07, 0.07, 0.08)}},
	"porsha": {"name": "PORSHA", "motors": "Porsha Centre", "tagline": "THERE IS NO SUBSTITUTE. THERE IS FINANCING.",
		"ui": Color(0.86, 0.68, 0.28), "exit": 8, "pick": "", "lineup": [],
		"look": {"wall": Color(0.95, 0.95, 0.94), "trim": Color(0.08, 0.08, 0.09), "band": Color(0.04, 0.04, 0.045),
			"floor": Color(0.86, 0.86, 0.85), "accent": Color(0.95, 0.74, 0.3), "ink": Color(0.95, 0.78, 0.36),
			"face": Color(0.04, 0.04, 0.045)}},
	"audy": {"name": "AUDY", "motors": "Audy", "tagline": "VORSPRUNG DURCH LEVERAGE",
		"ui": Color(0.86, 0.12, 0.15), "exit": 9, "pick": "", "lineup": [],
		"look": {"wall": Color(0.62, 0.64, 0.66), "trim": Color(0.3, 0.31, 0.33), "band": Color(0.13, 0.135, 0.145),
			"floor": Color(0.55, 0.56, 0.58), "accent": Color(0.9, 0.08, 0.12), "ink": Color(0.93, 0.94, 0.95),
			"face": Color(0.2, 0.21, 0.22)}},
}


## Who makes this car ("bemze" when the car has no brand).
static func of(key: String) -> String:
	if not Rules.CARS.has(key):
		return "bemze"
	return str(Rules.CARS[key].get("brand", "bemze"))


## Every car you can buy, in the showroom's order (Rules.SHOW_ORDER, then
## anything in CAR_ORDER that isn't listed there yet).
static func all_cars() -> Array:
	var out: Array = Rules.SHOW_ORDER.duplicate()
	for k in Rules.CAR_ORDER:
		if not out.has(k):
			out.append(k)
	return out.filter(func(k): return Rules.CARS.has(k))


## What this brand's showroom sells, in menu order (BEMZE: the used TOROLA first).
static func cars(brand: String) -> Array:
	return all_cars().filter(func(k): return of(k) == brand)


## The cars on show at the lot, flagship first: `lineup`, then the rest by
## price. No trade-ins on display. [] = new models arriving soon.
static func lineup(brand: String) -> Array:
	var own: Array = cars(brand).filter(func(k): return not str(Rules.CARS[k].model).begins_with("TCar_"))
	var out: Array = []
	for k in BRANDS[brand].get("lineup", []):
		if own.has(k):
			out.append(k)
	var rest: Array = own.filter(func(k): return not out.has(k))
	rest.sort_custom(func(a, b): return float(Rules.CARS[a].price) > float(Rules.CARS[b].price))
	out.append_array(rest)
	return out


static func name_of(brand: String) -> String:
	return str(BRANDS.get(brand, BRANDS.bemze).name)


static func index(brand: String) -> int:
	return maxi(ORDER.find(brand), 0)
