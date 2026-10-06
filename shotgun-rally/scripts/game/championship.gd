extends RefCounted
## Story mode: the SHOTGUN SERIES, a season of nine rallies driven in order.
## Each rally is three stages (fixed seeds, so everyone drives the same roads)
## with its own character: the light (mood), how long, narrow roads, puddles,
## the surface (gravel, mixed, mountain tarmac, snow and ice).
## Finish a rally to unlock the next. You're timed against five rival crews;
## where you finish pays credits (Profile).

const RIVALS := [
	["K. LINDQVIST / M. AHO", 0.93], ["S. OKAFOR / P. DOYLE", 0.965], ["G. ROSSETTI / L. BRUNO", 1.0],
	["H. TANAKA / R. MORI", 1.04], ["A. FOURNIER / C. BLANC", 1.09],
]

## pace: the middle rival's average speed (km/h); seeds picked so each stage fits
## the rally (Lakeland and the final have big jumps, Highland is twisty, Costa
## Mixta's stages have three sections each, Isola Rossa's and the Riviera's are
## full of hairpins, villages and (the Riviera) ice).
const RALLIES := [
	{"id": "pine", "name": "PINE VALLEY RALLY", "blurb": "Gentle forest gravel to learn the calls on. Short stages, wide open.",
		"mood": "day", "pace": 52.0, "reward": 3000, "gen": {},
		"stages": [["KETTLE HILL", 1112, 2000], ["MILL RUN", 1120, 2000], ["OLD SAWYARD", 1122, 2000]]},
	{"id": "lakes", "name": "LAKELAND RALLY", "blurb": "Fast, flowing and blind over the crests. Big jumps: flat out and pray.",
		"mood": "day", "pace": 62.0, "reward": 4000, "gen": {},
		"stages": [["OUNINPOHJA RIDGE", 2217, 2600], ["SEVEN LAKES", 2223, 2600], ["THE FLYING FINN", 2241, 2600]]},
	{"id": "golden", "name": "GOLDEN HOUR RALLY", "blurb": "Evening stages, the sun low through the pines. Long shadows hide the ruts.",
		"mood": "golden", "pace": 58.0, "reward": 5000, "gen": {},
		"stages": [["AMBER WOODS", 3300, 2400], ["SUNDOWN PASS", 3301, 2400], ["LAST LIGHT", 3302, 2400]]},
	{"id": "mud", "name": "MUD & MIST RALLY", "blurb": "Grey skies, fog in the trees and puddles everywhere. Keep the wipers busy.",
		"mood": "overcast", "pace": 52.0, "reward": 6000, "gen": {"puddles": 2.5},
		"stages": [["BOGSIDE", 4400, 2400], ["WET FEET", 4401, 2400], ["THE SWAMP", 4402, 2400]]},
	{"id": "highland", "name": "HIGHLAND RALLY", "blurb": "Narrow, twisty mountain roads. Every metre of the road book counts.",
		"mood": "day", "pace": 50.0, "reward": 7000, "gen": {"narrow": 0.8},
		"stages": [["CORRIE BENDS", 5504, 2400], ["THE NEEDLE", 5518, 2400], ["DEVIL'S ELBOW", 5528, 2400]]},
	{"id": "costa", "name": "COSTA MIXTA RALLY", "blurb": "Gravel, then tarmac, then gravel again, in one stage. The grip changes under you at every join.",
		"mood": "day", "pace": 58.0, "reward": 7500, "gen": {"surface": "mixed"},
		"stages": [["LA SERRA", 7700, 2600], ["RIERA SECA", 7708, 2600], ["EL COLL", 7717, 2600]]},
	{"id": "isola", "name": "ISOLA ROSSA RALLY", "blurb": "Dry mountain tarmac, a thousand corners: hairpins up a hillside, villages, armco and a long drop.",
		"mood": "golden", "pace": 54.0, "reward": 8000, "gen": {"surface": "tarmac"},
		"stages": [["COL DE L'AIGLE", 8803, 2400], ["LES CORNICHES", 8814, 2400], ["MILLE VIRAGES", 8811, 2400]]},
	{"id": "riviera", "name": "RIVIERA ALPS RALLY", "blurb": "Winter in the Alps: snow on the verges, ice in the shade. The co-driver calls it; you believe it.",
		"mood": "day", "pace": 46.0, "reward": 9000, "gen": {"surface": "tarmac", "ice": true},
		"stages": [["COL DES GIVRES", 9900, 2400], ["NUIT BLANCHE", 9901, 2400], ["LA DESCENTE", 9904, 2400]]},
	{"id": "final", "name": "GRAND FINAL", "blurb": "Three long stages, big jumps, the season on the line.",
		"mood": "golden", "pace": 60.0, "reward": 10000, "gen": {},
		"stages": [["THE LONG ROAD", 6600, 3600], ["CHAMPION'S LEAP", 6608, 3600], ["FINAL CALL", 6623, 3600]]},
]


static func count() -> int:
	return RALLIES.size()


static func rally(i: int) -> Dictionary:
	return RALLIES[clampi(i, 0, RALLIES.size() - 1)]


## What both machines need to build stage j of rally i (it rides along with
## load_stage): its length, light, road character, and the titles.
static func stage_opts(i: int, j: int) -> Dictionary:
	var r := rally(i)
	var stg: Array = r.stages[j]
	return {"mode": "story", "rally": i, "stage": j, "seed": stg[1], "length": float(stg[2]), "mood": r.mood,
		"gen": r.gen, "title": r.name, "stage_name": "SS%d  %s" % [j + 1, stg[0]]}


## A rival crew's time on a stage (s), from its length: their pace with a little
## stage-to-stage variety (the same every time).
static func rival_time(i: int, j: int, k: int, length: float) -> float:
	var r := rally(i)
	var wobble := (absi(hash([r.id, j, k])) % 1000) / 1000.0 * 0.04 - 0.02
	return length / (r.pace / 3.6) * RIVALS[k][1] * (1.0 + wobble)


## The rally standings after the stages driven so far: my times (with penalties)
## and those stages' lengths. [{name, total, me}] fastest first.
static func standings(i: int, my_times: Array, lengths: Array, me := "YOUR CREW") -> Array:
	var rows := [{"name": me, "total": 0.0, "me": true}]
	for t in my_times:
		rows[0].total += t
	for k in RIVALS.size():
		var tot := 0.0
		for j in lengths.size():
			tot += rival_time(i, j, k, lengths[j])
		rows.append({"name": RIVALS[k][0], "total": tot, "me": false})
	rows.sort_custom(func(a, b): return a.total < b.total)
	return rows


static func position(rows: Array) -> int:
	for p in rows.size():
		if rows[p].me:
			return p + 1
	return rows.size()


## Credits for finishing rally i in this position.
static func reward(i: int, pos: int) -> int:
	var share := [1.0, 0.6, 0.4, 0.25, 0.2, 0.15]
	return int(rally(i).reward * share[clampi(pos - 1, 0, share.size() - 1)])


static func ordinal(n: int) -> String:
	var suffix := "TH"
	if n % 100 < 11 or n % 100 > 13:
		suffix = ["TH", "ST", "ND", "RD", "TH", "TH", "TH", "TH", "TH", "TH"][n % 10]
	return "%d%s" % [n, suffix]
