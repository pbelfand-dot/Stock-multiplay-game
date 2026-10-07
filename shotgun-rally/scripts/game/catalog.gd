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
## drives and both machines draw. paint: {colours, livery, wheels, number}
## (missing keys: the car's own); levels: {engine, tyres, brakes} steps bought;
## tuning: {tyre, preset} ("auto" until the stage settles it: for_stage).
static func setup(car_id: String, paint := {}, levels := {}, tuning := {}) -> Dictionary:
	var c := car(car_id)
	var s := {"car": c.id, "name": c.name, "model": str(c.get("model", "")), "livery": paint.get("livery", c.livery),
		"colours": paint.get("colours", c.colours).duplicate(), "wheels": paint.get("wheels", c.wheels),
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
## asphalt most of the way, gravel otherwise.
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
	return s


## The car everyone starts with, as it comes.
static func default_setup() -> Dictionary:
	return setup("kestrel")
