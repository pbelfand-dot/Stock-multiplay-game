extends RefCounted
const VehicleRegistry = preload("res://scripts/game/vehicle_registry.gd")
## Everything the garage sells: the cars, their liveries, colours, wheels and
## upgrades, and what they cost (credits, earned by finishing stages: see
## Profile). The cars are look-alikes of real rally and road cars, with their
## own names and no badges (no real brands). The first four share one body (the
## Higgsfield car) with their own livery and how they drive; the rest ("model")
## have bodies of their own, realistic ones, and the real cars' numbers
## (CarSpecs: weight, engine, gearbox, which wheels drive).

## The cars, from the vehicle registry (data/vehicles/<id>.json, each with a
## "garage" block; scripts/game/vehicle_registry.gd), in the garage's order.
## power / grip / brakes: x the base car's (a car with its own model: x its own).
## engine: how it sounds (EngineSound.ENGINES: "wrc", "na4", "rotary", "five" ...).
## mass: kg, for the cars on the shared body: the real class's minimum weight (R4
## 1,300; a 1997-2010 World Rally Car 1,230; the 037's Group B class 960); the
## shared body's springs, dampers and brakes scale with it (CarSpecs.rally).
## drive_front: the share of the engine's torque to the front axle (0.5 =
## four-wheel drive, an even split like a modern rally car's; 0.15 = nearly all
## at the back: it slides; 0 = rear-drive, 1 = front-drive).
static var CARS: Array = VehicleRegistry.garage_cars()

## Liveries (patterns painted over the body: see livery.gd). Each car comes
## with its own; the others are bought once and fit any car.
const LIVERIES := [
	{"id": "kestrel", "name": "FACTORY", "price": 1000},
	{"id": "plain", "name": "PLAIN", "price": 0},
	{"id": "stripes", "name": "TWIN STRIPES", "price": 1500},
	{"id": "two_tone", "name": "TWO-TONE", "price": 1500},
	{"id": "comet", "name": "COMET", "price": 2500},
	{"id": "vortex", "name": "VORTEX", "price": 2500},
	{"id": "martello", "name": "MARTELLO", "price": 3500},
	{"id": "tricolore", "name": "TRICOLORE", "price": 3000},
	{"id": "charge", "name": "CHARGE", "price": 3000},
	{"id": "quattro", "name": "QUATTRO", "price": 3000},
	{"id": "goldline", "name": "GOLDLINE", "price": 2500},
]

## Paint: free, as many times as you like.
const COLOURS := [
	["RALLY RED", Color(0.78, 0.12, 0.1)], ["WHITE", Color(0.95, 0.95, 0.94)], ["BLACK", Color(0.07, 0.07, 0.08)],
	["WORLD BLUE", Color(0.07, 0.2, 0.6)], ["SKY", Color(0.3, 0.62, 0.9)], ["NAVY", Color(0.06, 0.13, 0.38)],
	["GOLD", Color(1.0, 0.8, 0.1)], ["ORANGE", Color(0.95, 0.42, 0.06)], ["LIME", Color(0.45, 0.8, 0.12)],
	["FOREST", Color(0.06, 0.32, 0.16)], ["PURPLE", Color(0.38, 0.12, 0.55)], ["SILVER", Color(0.66, 0.67, 0.7)],
]

const WHEELS := [
	{"id": "silver", "name": "SILVER", "colour": Color(0.72, 0.73, 0.75), "price": 0},
	{"id": "white", "name": "WHITE", "colour": Color(0.95, 0.95, 0.95), "price": 500},
	{"id": "gold", "name": "GOLD", "colour": Color(0.95, 0.72, 0.18), "price": 800},
	{"id": "black", "name": "BLACK", "colour": Color(0.08, 0.08, 0.09), "price": 500},
	{"id": "bronze", "name": "BRONZE", "colour": Color(0.62, 0.42, 0.2), "price": 800},
]

## Upgrades, per car, three steps each: what each step adds (x the car's own) and costs.
const UPGRADES := {
	"engine": {"name": "ENGINE", "add": [0.04, 0.08, 0.12], "prices": [2000, 4500, 8000], "stat": "power"},
	"tyres": {"name": "TYRES", "add": [0.02, 0.04, 0.06], "prices": [1500, 3500, 6000], "stat": "grip"},
	"brakes": {"name": "BRAKES", "add": [0.06, 0.12, 0.18], "prices": [1200, 2800, 5000], "stat": "brakes"},
}


## The tyres and the setup, chosen per car in the garage's SETUP tab (free, as
## often as you like). AUTO picks for the stage: tarmac where it's asphalt most
## of the way, gravel otherwise (for_stage).
const TUNING := {
	"tyre": {"name": "TYRES", "choices": [
		["auto", "AUTO", "Tarmac tyres when the stage is mostly asphalt, gravel tyres otherwise."],
		["gravel", "GRAVEL", "Chunky blocks that dig in: the grip on gravel, snow and mud. On asphalt they squirm a little."],
		["tarmac", "TARMAC", "Smooth and stiff: 12 % more grip on asphalt and it bites sooner, a quarter less on gravel. On a mixed stage, a gamble."]]},
	"preset": {"name": "SETUP", "choices": [
		["auto", "AUTO", "The tarmac setup when the stage is mostly asphalt, the gravel one otherwise."],
		["gravel", "GRAVEL", "Soft and long-legged: soaks up the ruts and the jumps, rolls into corners, slides easily."],
		["tarmac", "TARMAC", "Springs, dampers and anti-roll bars stiffer, quicker steering: sharp and flat on smooth asphalt, skittish on bumps."]]},
}


static func car(id: String) -> Dictionary:
	for c in CARS:
		if c.id == id:
			return c
	return CARS[0]


static func livery(id: String) -> Dictionary:
	for l in LIVERIES:
		if l.id == id:
			return l
	return LIVERIES[1]


static func wheels(id: String) -> Dictionary:
	for w in WHEELS:
		if w.id == id:
			return w
	return WHEELS[0]


## Everything the game needs to build and paint a car: what the driver's machine
## drives and both machines draw. paint: {colours, livery, wheels, wheel_type, number}
## (missing keys: the car's own); levels: {engine, tyres, brakes} steps bought;
## tuning: {tyre, preset} ("auto" until the stage settles it: for_stage).
static func setup(car_id: String, paint := {}, levels := {}, tuning := {}) -> Dictionary:
	var c := car(car_id)
	var s := {"car": c.id, "name": c.name, "model": str(c.get("model", "")), "livery": paint.get("livery", c.livery),
		"colours": paint.get("colours", c.colours).duplicate(), "wheels": paint.get("wheels", c.wheels),
		"wheel_type": str(paint.get("wheel_type", "stock")),
		"number": int(paint.get("number", c.number)), "drive_front": c.drive_front, "mass": float(c.get("mass", 0.0)),
		"engine": str(c.get("engine", "wrc")),
		"tyre": str(tuning.get("tyre", "auto")), "preset": str(tuning.get("preset", "auto"))}
	s.wheel_colour = wheels(s.wheels).colour
	for k in UPGRADES:
		var u: Dictionary = UPGRADES[k]
		var lvl := clampi(int(levels.get(k, 0)), 0, 3)
		s[u.stat] = c[u.stat] * (1.0 + (u.add[lvl - 1] if lvl > 0 else 0.0))
	return s


## A setup for this stage: "auto" tyres / setup become tarmac where the stage is
## asphalt most of the way, gravel otherwise. On the road modes with SIM STREET
## handling on, "street": [g, tyre kind] (street_grip).
static func for_stage(setup: Dictionary, st) -> Dictionary:
	var s := setup.duplicate()
	var asphalt := 0.0
	for sec in st.sections:
		if sec.surface == "asphalt":
			asphalt += sec.s1 - sec.s0
	var pick := "tarmac" if asphalt > st.length * 0.5 else "gravel"
	for k in ["tyre", "preset"]:
		if str(s.get(k, "auto")) == "auto":
			s[k] = pick
	if street_sim(st):
		s.street = street_grip(str(s.get("car", "")))     # SIM STREET: its real road tyres (RallyCar._tune)
	return s


## SIM STREET (Settings > STREET HANDLING): each car's lateral grip on its own tyres
## on dry asphalt, as a steady skid-pad figure (g), and the kind of tyre
## (TireModel.STREET_KINDS: "street", "cup" for Cup 2 / R-compound road tyres,
## "slick" for race cars, whose wings add their downforce on top). Measured
## figures where magazines published them (Car and Driver / Motor Trend skid pads:
## GR Supra 1.07, GT-R 0.99-1.02, Hellcat 0.92-0.94, 911 GT3 RS 1.24); the rest
## estimated from cars of their kind, age and tyres (a 1970s car on its period
## tyres ~0.78, the 1980s ~0.82, the 1990s ~0.86-0.92, today's sports cars on
## performance tyres ~1.0, economy cars ~0.85-0.88). Not listed: by its role.
const STREET := {
	"akatsuki": [1.07, "street"], "raiden": [1.0, "street"], "hellhound": [0.95, "street"], "hellhound_s": [0.93, "street"],
	"brawler": [0.78, "street"], "hako": [0.78, "street"], "hachi": [0.8, "street"], "kitsune": [0.84, "street"],
	"rotora_fc": [0.84, "street"], "rotora_fd": [0.9, "street"], "nimbus": [0.84, "street"], "sylph": [0.9, "street"],
	"pleiad": [0.92, "street"], "lancer": [0.96, "street"], "kaiser_5": [0.85, "street"], "kaiser_2": [1.04, "street"],
	"kaiser_4": [1.02, "street"], "kaiser_8": [1.0, "street"], "kaiser_t": [1.0, "street"], "kombi": [0.97, "street"],
	"gls": [0.88, "street"], "mochi": [0.86, "street"],
	"traffic_sedan": [0.86, "street"], "traffic_crossover": [0.84, "street"], "traffic_minivan": [0.84, "street"],
	"elfer_rs": [1.24, "cup"], "uno": [1.22, "cup"], "ghost": [1.2, "cup"], "vento": [1.12, "cup"], "centuria": [1.12, "cup"],
	"elfer_r": [1.6, "slick"], "elfer_evo": [1.6, "slick"], "affalter": [1.6, "slick"], "biscione": [1.45, "slick"], "bolt16": [1.6, "slick"],
	"gtp963": [1.7, "slick"], "vsr": [1.7, "slick"],
	"haldane": [1.6, "slick"], "vespera": [1.6, "slick"], "valko": [1.6, "slick"], "stiletto": [1.6, "slick"],
	"kaiser4_gt3": [1.6, "slick"], "tempesta_gt3": [1.6, "slick"], "woking_gt3": [1.6, "slick"], "elfer_gt2cs": [1.6, "slick"],
	"affalter_dtm": [1.6, "slick"],
	# the street batch: today's performance tyres; the track-focused ones on cup tyres
	"tempesta_ursa": [0.98, "street"], "affalter_slr": [0.98, "street"], "vierrad_r7": [1.0, "street"], "affalter_a45": [1.0, "street"],
	"kaiser_5t": [1.0, "street"], "kaiser_5g": [1.0, "street"], "kaiser_3x": [0.95, "street"], "kaiser_235": [0.97, "street"],
	"kaiser_2c": [1.04, "street"], "affalter_s": [0.9, "street"],
	"woking_600": [1.1, "cup"], "affalter_gtb": [1.15, "cup"], "woking_800": [1.2, "cup"], "woking_one": [1.12, "cup"],
	# FORMULA APEX: 18 in slicks on an 800 kg car (~1.7 g before the wings: they add 2-3 x the weight at speed)
	"toro": [1.7, "formula"], "vee_f": [1.7, "formula"], "affalter_w17": [1.7, "formula"],
	# rally cars on tarmac rally tyres (near-slicks today, narrower then)
	"ocelot": [1.25, "cup"], "kestrel": [1.18, "cup"], "comet": [1.2, "cup"], "vortex": [1.2, "cup"],
	"kaiser": [1.1, "cup"], "martello": [1.08, "cup"], "sedici": [1.1, "cup"], "vierrad": [1.08, "cup"],
}
const STREET_ROLE := {"race_prototype": [1.7, "slick"], "track": [1.22, "cup"], "hypercar": [1.12, "cup"], "formula": [1.7, "formula"],
	"rally": [1.15, "cup"]}
## SIM STREET's factory ABS (as Assetto Corsa's "factory" aids): on for the cars
## that have it as standard (today's road cars, GT3 race cars), off for these: the
## classics (1970s-80s, and early-90s cars where it was an option), the prototypes,
## and the rally cars (role "rally"; their rules ban it). Settings' ANTI-LOCK
## switch still turns it on for every car.
const NO_ABS := ["brawler", "hako", "hachi", "kitsune", "rotora_fc", "nimbus", "biscione", "gtp963", "vsr", "toro", "vee_f",
	"affalter_w17", "affalter_dtm"]
## ... and factory traction control: today's road cars (2010s on), the hypercars, the
## GT3 cars and the prototypes have it; the classics, the 1990s cars and the rally
## cars don't. Off in the touge's DRIFT rules (drifters switch it off); Settings'
## TRACTION CONTROL still turns it on for every car.
const FACTORY_TC := ["akatsuki", "raiden", "hellhound", "hellhound_s", "kaiser_2", "kaiser_4", "kaiser_8", "kaiser_t",
	"kombi", "gls", "mochi", "traffic_sedan", "traffic_crossover", "traffic_minivan", "elfer_rs", "uno", "ghost",
	"centuria", "vento", "bolt16", "elfer_r", "elfer_evo", "affalter", "gtp963", "vsr", "haldane", "vespera", "valko", "stiletto",
	"kaiser4_gt3", "tempesta_gt3", "woking_gt3", "elfer_gt2cs",
	"stromer", "warhawk", "pueblo", "kaiser_5x", "kaiser_7x", "kasten",
	"tempesta_ursa", "woking_600", "affalter_slr", "affalter_gtb", "vierrad_r7", "affalter_a45", "kaiser_5t", "kaiser_5g",
	"kaiser_3x", "kaiser_235", "kaiser_2c", "affalter_s", "woking_800", "woking_one"]


## [g, tyre kind, factory ABS, factory TC] for this car in SIM STREET (STREET, else
## by its role, else a modern road car's 0.95 on road tyres).
static func street_grip(id: String) -> Array:
	var e = VehicleRegistry.entry(id)
	var role := str(e.get("role", "")) if e != null else ""
	var out: Array = (STREET[id] if STREET.has(id) else STREET_ROLE.get(role, [0.95, "street"])).duplicate()
	out.append(not (id in NO_ABS or role == "rally"))
	out.append(id in FACTORY_TC)
	return out


## Is SIM STREET handling on for this stage? The road kinds (the loop, a highway,
## the touge) when Settings > STREET HANDLING says SIM (Config.street_handling).
static func street_sim(st) -> bool:
	if not str(st.get("kind")) in ["loop", "highway", "touge", "circuit"]:
		return false
	var cfg = Engine.get_main_loop().root.get_node_or_null("Config") if Engine.get_main_loop() is SceneTree else null
	return cfg == null or str(cfg.get("street_handling")) != "arcade"


## The car everyone starts with, as it comes.
static func default_setup() -> Dictionary:
	return setup("kestrel")
