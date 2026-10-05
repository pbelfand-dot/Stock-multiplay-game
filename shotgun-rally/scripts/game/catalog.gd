extends RefCounted
## Everything the garage sells: the cars, their liveries, colours, wheels and
## upgrades, and what they cost (credits, earned by finishing stages: see
## Profile). The cars are look-alikes of real rally cars, with their own names
## and badges (no real brands). For now they share one body; each has its own
## livery and how it drives.

## power / grip / brakes: x the base car's. drive_front: the share of the
## engine's torque to the front axle (0.45 = four-wheel drive, a bit rearward;
## 0.1 = nearly all at the back: it slides).
const CARS := [
	{"id": "kestrel", "name": "KESTREL R4", "price": 0, "livery": "kestrel", "number": 7,
		"colours": [Color(0.78, 0.12, 0.1), Color(0.95, 0.95, 0.93), Color(0.08, 0.08, 0.09), Color(0.95, 0.95, 0.93)],
		"wheels": "silver", "power": 1.0, "grip": 1.0, "brakes": 1.0, "drive_front": 0.45,
		"blurb": "The club car everyone starts in. Four-wheel drive, forgiving, quick enough to learn on."},
	{"id": "comet", "name": "BLUE COMET WRC", "price": 12000, "livery": "comet", "number": 5,
		"colours": [Color(0.07, 0.2, 0.6), Color(1.0, 0.8, 0.1), Color(0.95, 0.95, 0.95), Color(1.0, 0.8, 0.1)],
		"wheels": "gold", "power": 1.08, "grip": 1.05, "brakes": 1.05, "drive_front": 0.48,
		"blurb": "Blue and gold, gold wheels, a boxer burble. Planted and precise: the 90s world champion's look."},
	{"id": "vortex", "name": "VORTEX EVO", "price": 18000, "livery": "vortex", "number": 3,
		"colours": [Color(0.95, 0.95, 0.94), Color(0.82, 0.08, 0.07), Color(0.07, 0.07, 0.08), Color(0.82, 0.08, 0.07)],
		"wheels": "white", "power": 1.13, "grip": 1.02, "brakes": 1.08, "drive_front": 0.45,
		"blurb": "White with red and black slashes. A turbo that kicks hard out of every hairpin."},
	{"id": "martello", "name": "MARTELLO 037", "price": 26000, "livery": "martello", "number": 1,
		"colours": [Color(0.96, 0.96, 0.94), Color(0.06, 0.13, 0.38), Color(0.3, 0.62, 0.9), Color(0.85, 0.1, 0.08)],
		"wheels": "white", "power": 1.2, "grip": 0.97, "brakes": 1.05, "drive_front": 0.1,
		"blurb": "The last great rear-drive rally car, in white with navy, sky blue and red stripes. Wild."},
]

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
## (missing keys: the car's own); levels: {engine, tyres, brakes} steps bought.
static func setup(car_id: String, paint := {}, levels := {}) -> Dictionary:
	var c := car(car_id)
	var s := {"car": c.id, "name": c.name, "livery": paint.get("livery", c.livery),
		"colours": paint.get("colours", c.colours).duplicate(), "wheels": paint.get("wheels", c.wheels),
		"number": int(paint.get("number", c.number)), "drive_front": c.drive_front}
	s.wheel_colour = wheels(s.wheels).colour
	for k in UPGRADES:
		var u: Dictionary = UPGRADES[k]
		var lvl := clampi(int(levels.get(k, 0)), 0, 3)
		s[u.stat] = c[u.stat] * (1.0 + (u.add[lvl - 1] if lvl > 0 else 0.0))
	return s


## The car everyone starts with, as it comes.
static func default_setup() -> Dictionary:
	return setup("kestrel")
