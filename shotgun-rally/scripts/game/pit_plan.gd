extends RefCounted
## Your pit strategy in Track Mode (the pause menu's PIT rows): what the crew does at your next stop.
##
##   TYRES:   AUTO (the safe default: new ones if they're worn past 30 % or in qualifying; on a wet
##            track wets, on a dry one off wets onto mediums, else the same compound again),
##            SOFT, MEDIUM, HARD, WET (always a new set of that), or KEEP (no tyres: the quickest stop)
##   FUEL:    TO THE END (the laps left and one more, at what a lap's been burning), +5 LAPS, NONE
##   REPAIRS: ON (whatever damage there is: up to 30 s) or OFF
##
## service(ctx) turns the plan and the car's state into the crew's work: {tyres, compound, fuel,
## repair}, which RaceDriver.service_time() times and RaceSim.service() / repair() carry out.

const TYRES := ["auto", "slick_soft", "slick_medium", "slick_hard", "wet", "keep"]
const TYRE_NAMES := {"auto": "AUTO", "slick_soft": "SOFT", "slick_medium": "MEDIUM", "slick_hard": "HARD", "wet": "WET", "keep": "KEEP"}
const FUEL := ["finish", "plus5", "none"]
const FUEL_NAMES := {"finish": "TO THE END", "plus5": "+5 LAPS", "none": "NONE"}
const WORN := 0.3                     # AUTO changes tyres worn past this

var tyres := "auto"
var fuel := "finish"
var repair := true


func cycle_tyres() -> void:
	tyres = TYRES[(TYRES.find(tyres) + 1) % TYRES.size()]


func cycle_fuel() -> void:
	fuel = FUEL[(FUEL.find(fuel) + 1) % FUEL.size()]


func toggle_repair() -> void:
	repair = not repair


## The pause menu's lines.
func tyres_text() -> String:
	return "PIT TYRES: %s" % TYRE_NAMES.get(tyres, "AUTO")


func fuel_text() -> String:
	return "PIT FUEL: %s" % FUEL_NAMES.get(fuel, "TO THE END")


func repair_text() -> String:
	return "PIT REPAIRS: %s" % ("ON" if repair else "OFF")


## The crew's work. ctx: worn (the most worn tyre, 0..1), race (bool: a race, not practice or
## qualifying), compound (on the car now), wet (the track, 0..1), laps_left, per_lap (l), fuel (l in
## the tank), tank (l), damage (0..1).
func service(ctx: Dictionary) -> Dictionary:
	var now := str(ctx.get("compound", "slick_medium"))
	var wet_track := float(ctx.get("wet", 0.0)) >= 0.3
	var change := false
	var to := now
	match tyres:
		"auto":
			var wrong := (now == "wet") != wet_track             # wets on a dry track, slicks on a wet one
			change = wrong or float(ctx.get("worn", 0.0)) > WORN or not bool(ctx.get("race", true))
			if wrong:
				to = "wet" if wet_track else "slick_medium"
		"keep":
			change = false
		_:
			change = true
			to = tyres
	var per_lap := maxf(float(ctx.get("per_lap", 3.4)), 0.5)
	var room := maxf(float(ctx.get("tank", 120.0)) - float(ctx.get("fuel", 0.0)), 0.0)
	var litres := 0.0
	match fuel:
		"finish":
			litres = maxf((int(ctx.get("laps_left", 0)) + 1) * per_lap - float(ctx.get("fuel", 0.0)), 0.0)
		"plus5":
			litres = 5.0 * per_lap
	return {"tyres": change, "compound": to if change else "", "fuel": minf(litres, room),
		"repair": float(ctx.get("damage", 0.0)) if repair else 0.0}


## A stop's line on the screen: "SOFT · +18 L · REPAIRS".
static func describe(sv: Dictionary) -> String:
	var bits: Array = []
	if bool(sv.get("tyres", false)):
		bits.append(str(TYRE_NAMES.get(str(sv.get("compound", "")), "NEW TYRES")))
	if float(sv.get("fuel", 0.0)) >= 0.5:
		bits.append("+%d L" % roundi(float(sv.fuel)))
	if float(sv.get("repair", 0.0)) > 0.0:
		bits.append("REPAIRS")
	return " · ".join(bits) if not bits.is_empty() else "NOTHING TO DO"
