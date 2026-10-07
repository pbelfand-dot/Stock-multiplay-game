extends RefCounted
## Everything the garage sells: the cars, their liveries, colours, wheels and
## upgrades, and what they cost (credits, earned by finishing stages: see
## Profile). The cars are look-alikes of real rally and road cars, with their
## own names and no badges (no real brands). The first four share one body (the
## Higgsfield car) with their own livery and how they drive; the rest ("model")
## have bodies of their own, realistic ones, and the real cars' numbers
## (CarSpecs: weight, engine, gearbox, which wheels drive).

## power / grip / brakes: x the base car's (a car with its own model: x its own).
## engine: how it sounds (EngineSound.ENGINES: "wrc", "na4", "rotary", "five" ...).
## mass: kg, for the cars on the shared body: the real class's minimum weight (R4
## 1,300; a 1997-2010 World Rally Car 1,230; the 037's Group B class 960); the
## shared body's springs, dampers and brakes scale with it (CarSpecs.rally).
## drive_front: the share of the engine's torque to the front axle (0.5 =
## four-wheel drive, an even split like a modern rally car's; 0.15 = nearly all
## at the back: it slides; 0 = rear-drive, 1 = front-drive).
const CARS := [
	{"id": "kestrel", "name": "KESTREL R4", "engine": "wrc", "price": 0, "livery": "kestrel", "number": 7, "mass": 1300.0,
		"colours": [Color(0.78, 0.12, 0.1), Color(0.95, 0.95, 0.93), Color(0.08, 0.08, 0.09), Color(0.95, 0.95, 0.93)],
		"wheels": "silver", "power": 1.0, "grip": 1.0, "brakes": 1.0, "drive_front": 0.5,
		"blurb": "The club car everyone starts in. Four-wheel drive, forgiving, quick enough to learn on."},
	{"id": "comet", "name": "BLUE COMET WRC", "engine": "wrc", "price": 12000, "livery": "comet", "number": 5, "mass": 1230.0,
		"colours": [Color(0.07, 0.2, 0.6), Color(1.0, 0.8, 0.1), Color(0.95, 0.95, 0.95), Color(1.0, 0.8, 0.1)],
		"wheels": "gold", "power": 1.08, "grip": 1.05, "brakes": 1.05, "drive_front": 0.53,
		"blurb": "Blue and gold, gold wheels, a boxer burble. Planted and precise: the 90s world champion's look."},
	{"id": "vortex", "name": "VORTEX EVO", "engine": "wrc", "price": 18000, "livery": "vortex", "number": 3, "mass": 1230.0,
		"colours": [Color(0.95, 0.95, 0.94), Color(0.82, 0.08, 0.07), Color(0.07, 0.07, 0.08), Color(0.82, 0.08, 0.07)],
		"wheels": "white", "power": 1.13, "grip": 1.02, "brakes": 1.08, "drive_front": 0.5,
		"blurb": "White with red and black slashes. A turbo that kicks hard out of every hairpin."},
	{"id": "martello", "name": "MARTELLO 037", "engine": "sc4", "price": 26000, "livery": "martello", "number": 1, "mass": 960.0,
		"colours": [Color(0.96, 0.96, 0.94), Color(0.06, 0.13, 0.38), Color(0.3, 0.62, 0.9), Color(0.85, 0.1, 0.08)],
		"wheels": "white", "power": 1.2, "grip": 0.97, "brakes": 1.05, "drive_front": 0.15,
		"blurb": "The last great rear-drive rally car, in white with navy, sky blue and red stripes. Wild."},
	{"id": "nimbus", "name": "NIMBUS EG", "engine": "na4", "price": 5000, "livery": "plain", "number": 16, "model": "civic_eg",
		"colours": [Color(0.72, 0.08, 0.08), Color(0.95, 0.95, 0.94), Color(0.07, 0.07, 0.08), Color(0.95, 0.95, 0.94)],
		"wheels": "silver", "power": 1.0, "grip": 1.0, "brakes": 1.0, "drive_front": 1.0,
		"blurb": "A light early-90s hatch with a twin-cam that sings to 8,000 rpm. Front-drive, cheap, quick: it pulls you out of every hairpin."},
	{"id": "rotora_fc", "name": "ROTORA FC", "engine": "rotary", "price": 8000, "livery": "plain", "number": 13, "model": "rx7_fc",
		"colours": [Color(0.93, 0.93, 0.92), Color(0.07, 0.07, 0.08), Color(0.78, 0.1, 0.08), Color(0.93, 0.93, 0.92)],
		"wheels": "silver", "power": 1.0, "grip": 1.0, "brakes": 1.0, "drive_front": 0.0,
		"blurb": "The 80s rotary coupe: a turbo two-rotor, rear-drive, balanced near 50/50. The mountain-pass drifter's first love."},
	{"id": "hachi", "name": "HACHI 86", "engine": "na4", "price": 4000, "livery": "plain", "number": 86, "model": "ae86",
		"colours": [Color(0.95, 0.95, 0.94), Color(0.07, 0.07, 0.08), Color(0.78, 0.1, 0.08), Color(0.95, 0.95, 0.94)],
		"wheels": "silver", "power": 1.0, "grip": 1.0, "brakes": 1.0, "drive_front": 0.0,
		"blurb": "The little 80s rear-drive coupe the mountain passes made famous: light, a twin-cam that loves the top end, white over black."},
	{"id": "sylph", "name": "SYLPH S15", "engine": "turbo4", "price": 11000, "livery": "plain", "number": 15, "model": "s15",
		"colours": [Color(0.12, 0.32, 0.72), Color(0.95, 0.95, 0.94), Color(0.07, 0.07, 0.08), Color(0.95, 0.95, 0.94)],
		"wheels": "silver", "power": 1.0, "grip": 1.0, "brakes": 1.0, "drive_front": 0.0,
		"blurb": "The last of the turbo drift coupes, here on a widebody kit: rear-drive, a six-speed, a turbo four that pulls from the middle."},
	{"id": "kaiser", "name": "KAISER 30", "engine": "na4_race", "price": 14000, "livery": "plain", "number": 30, "model": "e30",
		"colours": [Color(0.93, 0.93, 0.92), Color(0.08, 0.2, 0.55), Color(0.78, 0.1, 0.08), Color(0.3, 0.62, 0.9)],
		"wheels": "silver", "power": 1.0, "grip": 1.0, "brakes": 1.0, "drive_front": 0.0,
		"blurb": "A boxy 80s touring-car hero with a screaming four-cylinder. Rear-drive, light, sharp on tarmac and a handful on gravel."},
	{"id": "rotora_fd", "name": "ROTORA FD", "engine": "rotary", "price": 16000, "livery": "plain", "number": 7, "model": "rx7_fd",
		"colours": [Color(1.0, 0.76, 0.06), Color(0.07, 0.07, 0.08), Color(0.95, 0.95, 0.94), Color(1.0, 0.76, 0.06)],
		"wheels": "silver", "power": 1.0, "grip": 1.0, "brakes": 1.0, "drive_front": 0.0,
		"blurb": "The 90s rotary legend: twin turbos, perfect balance, sharp as a knife. Rear-drive, and it revs to eight thousand."},
	{"id": "sedici", "name": "MARTELLO SEDICI", "engine": "group_a", "price": 28000, "livery": "martello", "number": 4, "model": "delta_evo2",
		"colours": [Color(0.96, 0.96, 0.94), Color(0.06, 0.13, 0.38), Color(0.3, 0.62, 0.9), Color(0.85, 0.1, 0.08)],
		"wheels": "white", "power": 1.0, "grip": 1.0, "brakes": 1.0, "drive_front": 0.45,
		"blurb": "The boxy four-wheel-drive hatch that won everything in Group A: a turbo four, wide arches, a light pod. The Martello's stripes."},
	{"id": "vierrad", "name": "VIERRAD S1", "engine": "five", "price": 30000, "livery": "quattro", "number": 2, "model": "sport_quattro",
		"colours": [Color(0.95, 0.95, 0.94), Color(1.0, 0.78, 0.1), Color(0.8, 0.1, 0.08), Color(0.95, 0.95, 0.94)],
		"wheels": "white", "power": 1.0, "grip": 1.0, "brakes": 1.0, "drive_front": 0.5,
		"blurb": "The short, brutal four-wheel-drive monster of the Group B years: a five-cylinder turbo with huge lag, then everything at once, and a locked centre diff that wants to go straight."},
	{"id": "ocelot", "name": "OCELOT R1", "engine": "wrc", "price": 40000, "livery": "two_tone", "number": 8, "model": "puma_rally1",
		"colours": [Color(0.05, 0.16, 0.45), Color(0.95, 0.95, 0.94), Color(0.95, 0.42, 0.06), Color(0.95, 0.95, 0.94)],
		"wheels": "white", "power": 1.0, "grip": 1.0, "brakes": 1.0, "drive_front": 0.5,
		"blurb": "Today's top-class rally car: a turbo, a huge wing, long travel and real downforce. The fastest thing in the garage."},
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
