extends RefCounted
## A race car's running state for Track Mode (RallyCar.race when its setup asks for "race_sim"):
## the tyres' heat, pressure and wear on their compound (data/tyre_compounds.json), the brake
## discs' heat and fade, the fuel and what it weighs, the pit limiter, the car's ABS and traction
## control settings. It sits on top of the car's physics without replacing any of it: every factor
## is 1 at the window (a tyre in its window, brakes warm, the right pressure), so the rally and
## street handling are untouched, and a race car out of the box drives as its tyre says.
##
##   grip(k)        corner k's grip x: temperature (cold below the window, greasy past it), hot
##                  pressure against the ideal, wear (a slow fade, then a cliff), flat spots
##   brake_mul(k)   its brake's bite x: a cold disc bites a little less, past ~700 C it fades
##   throttle(car, t)  the pit limiter holding the speed, an empty tank
##   tick(car, dt)  after the physics tick: heat in (the tyre's slip power, the carcass flexing,
##                  the brakes' work), heat out (the air, faster the faster it goes; the track),
##                  wear, fuel burnt, the car's mass
##   service(compound, litres)  a pit stop: new tyres (at the air's temperature: no warmers, as
##                  in SRO's GT3 series), fuel in
##
## Heat by power, not by fiat: a tyre's surface warms by what its slip and flexing put in less what
## the air takes off (W/K growing with speed), its core follows (a ~100 s lag: a lap or two to warm
## up), the hot pressure follows the core (the gas law on the absolute pressure from the cold
## setting: 1.4 bar gauge cold comes up to ~1.95 hot with the core at ~90 C, as a GT3 slick's does). The numbers are the
## game's, set so a GT3 on a 5 km lap brings mediums into their window over the out-lap and the
## first flying lap, and a stint lasts as long as a real one; data/tyre_compounds.json documents them.

const DATA := "res://data/tyre_compounds.json"
const C_SURFACE := 3000.0            # J/K: the tread's skin (the part the road heats and the air cools)
const C_CORE := 12000.0              # J/K: the carcass and the air inside
const K_SKIN := 120.0                # W/K between them
const FLEX := 0.012                  # W per N of load per m/s: the carcass flexing as it rolls (a race tyre's
                                     # rolling loss, ~1.2 % of the load x the speed, ends up as heat in it)
const K_ROAD := 0.0045               # W/K per N of load: the tread on the track's surface
const DISC_C := [4600.0, 4600.0, 3300.0, 3300.0]   # J/K: a front disc (~390 mm) and a rear (~355 mm)
const FUEL_KG_L := 0.745             # kg per litre of race fuel
const ATM := 1.013                   # bar: the pressures are gauge (over the air's)
const FULL_FUEL_LPS := 0.042         # l/s flat out: ~280 g/kWh at a GT3's ~405 kW
const IDLE_FUEL_LPS := 0.0008

static var _data := {}

var compound := "slick_medium"
var c: Dictionary = {}               # the compound's figures
var tyres: Array = []                # per corner: {surface, core, pressure, wear, flat}
var disc: Array = [0.0, 0.0, 0.0, 0.0]
var fuel_l := 60.0
var tank_l := 120.0
var fuel_used := 0.0
var base_mass := 0.0                 # the car without fuel (kg)
var limiter := false
var limiter_kmh := 60.0
var ambient := 22.0                  # the air (C)
var track := 30.0                    # the track's surface (C)
var wet := 0.0                       # 0 dry ... 1 standing water
var cold_bar := 1.4                  # the pressure set cold
var abs_level := 4                   # 0 off, 1 (least) ... 10 (most): the car's ABS map
var tc_level := 4                    # the same for traction control


static func data() -> Dictionary:
	if _data.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		_data = d if d is Dictionary else {"base": {}, "compounds": {"slick_medium": {"name": "MEDIUM", "grip": 1.0, "window": [82, 108]}}}
	return _data


static func compounds() -> Array:
	return (data().compounds as Dictionary).keys()


## Set up on a car: opts {compound, fuel (l), tank (l), ambient, track, wet, abs, tc}.
func setup(car, opts := {}) -> void:
	var d := data()
	compound = str(opts.get("compound", compound))
	if not d.compounds.has(compound):
		compound = "slick_medium"
	c = d.compounds[compound]
	ambient = float(opts.get("ambient", ambient))
	track = float(opts.get("track", ambient + 8.0))
	wet = float(opts.get("wet", 0.0))
	tank_l = float(opts.get("tank", tank_l))
	fuel_l = clampf(float(opts.get("fuel", fuel_l)), 0.0, tank_l)
	cold_bar = float(d.base.get("pressure_cold_bar", 1.4))
	abs_level = int(opts.get("abs", abs_level))
	tc_level = int(opts.get("tc", tc_level))
	base_mass = float(car.config.mass) if car and car.config else 1300.0
	_fresh_tyres()
	disc = [ambient + 10.0, ambient + 10.0, ambient + 10.0, ambient + 10.0]
	if car:
		car.mass = base_mass + fuel_l * FUEL_KG_L


func _fresh_tyres() -> void:
	tyres.clear()
	for k in 4:
		tyres.append({"surface": ambient + 4.0, "core": ambient + 4.0, "pressure": cold_bar, "wear": 0.0, "flat": 0.0, "lock_t": 0.0})


## A pit stop: four new tyres of `new_compound` (at the air's temperature) and `litres` more fuel.
func service(car, new_compound := "", litres := 0.0) -> void:
	if new_compound != "" and data().compounds.has(new_compound):
		compound = new_compound
		c = data().compounds[compound]
		_fresh_tyres()
	fuel_l = clampf(fuel_l + litres, 0.0, tank_l)
	if car:
		car.mass = base_mass + fuel_l * FUEL_KG_L


# ── what the physics reads ────────────────────────────────────────────────

## Corner k's grip x.
func grip(k: int) -> float:
	var t: Dictionary = tyres[k]
	var b: Dictionary = data().base
	var temp := float(t.surface) * 0.6 + float(t.core) * 0.4
	var win: Array = c.get("window", [82, 108])
	var g := 1.0
	if temp < float(win[0]):
		g = lerpf(float(c.get("cold", 0.82)), 1.0, smoothstep(20.0, float(win[0]), temp))
	elif temp > float(win[1]):
		g = maxf(0.7, 1.0 - float(c.get("hot", 0.02)) * (temp - float(win[1])) / 10.0)
	# the hot pressure against the ideal (a little either way doesn't matter)
	var dp := absf(float(t.pressure) - float(b.get("pressure_ideal_bar", 1.95)))
	g *= 1.0 - float(b.get("pressure_loss_per_bar", 0.18)) * maxf(dp - 0.05, 0.0)
	# wear: a slow fade to wear_soft_from, then the cliff to worn_grip at 1
	var w := float(t.wear)
	var w0 := float(b.get("wear_soft_from", 0.7))
	if w < w0:
		g *= 1.0 - 0.04 * w / w0
	else:
		g *= lerpf(0.96, float(b.get("worn_grip", 0.82)), clampf((w - w0) / (1.0 - w0), 0.0, 1.0))
	g *= 1.0 - minf(float(t.flat), 0.25) * 0.2                   # a flat spot: a little less, and it shakes
	g *= lerpf(1.0, float(c.get("wet", 0.5)), wet) if wet > 0.0 else 1.0
	return g * float(c.get("grip", 1.0))


## Corner k's brake bite x.
func brake_mul(k: int) -> float:
	var t: float = disc[k]
	if t < 100.0:
		return lerpf(0.9, 1.0, clampf((t - ambient) / maxf(100.0 - ambient, 1.0), 0.0, 1.0))
	if t > 700.0:
		return lerpf(1.0, 0.65, clampf((t - 700.0) / 300.0, 0.0, 1.0))
	return 1.0


## The throttle after the pit limiter (holding limiter_kmh) and the tank.
func throttle(car, t: float) -> float:
	if fuel_l <= 0.0:
		return 0.0
	if limiter:
		var lim := limiter_kmh / 3.6
		t = minf(t, clampf((lim - absf(float(car.speed))) * 0.9, 0.0, 1.0))
	return t


## The ABS / traction control settings onto the car's assist config (Track Mode's GT cars run
## the car's own aids, by level, whatever Settings says for the rally): level 1 lets the tyre
## slip furthest, 10 cuts in earliest; 0 off.
func apply_aids(cfg: Resource) -> void:
	cfg.anti_lock = abs_level > 0
	cfg.traction_control = tc_level > 0
	if abs_level > 0:
		cfg.abs_band = lerpf(0.18, 0.06, (abs_level - 1) / 9.0)
	if tc_level > 0:
		cfg.tc_band = lerpf(0.3, 0.08, (tc_level - 1) / 9.0)


# ── after each tick ───────────────────────────────────────────────────────

func tick(car, dt: float) -> void:
	var v: float = absf(float(car.speed))
	var b: Dictionary = data().base
	var h_air := 20.0 + 2.2 * v                                    # W/K off the tread at speed (~1.3 m² of rubber)
	for k in 4:
		var w = car.wheels[k]
		var t: Dictionary = tyres[k]
		var p_slip := 0.0
		var p_in := 0.0
		if w.grounded:
			var slide_long: float = w.omega * w.radius - w.v_long
			p_slip = absf(w.long_force * slide_long) + absf(w.lateral_force * w.v_lat)
			p_in = p_slip * float(c.get("heat", 1.0)) + FLEX * w.load * v + K_ROAD * w.load * (track - float(t.surface))
			# a locked wheel at speed grinds a flat spot
			if w.slip_long < -0.85 and v > 12.0:
				t.lock_t += dt
				if t.lock_t > float(b.get("flat_spot_from", 0.18)):
					t.flat = minf(1.0, float(t.flat) + dt * 0.6)
			else:
				t.lock_t = 0.0
		var surf := float(t.surface)
		var core := float(t.core)
		var cool := h_air * (surf - ambient) * (1.0 + wet * 2.0)  # (a wet track cools it hard)
		surf += dt * (p_in - cool - K_SKIN * (surf - core)) / C_SURFACE
		core += dt * (K_SKIN * (surf - core) - 6.0 * (core - ambient)) / C_CORE
		t.surface = surf
		t.core = core
		t.pressure = (cold_bar + ATM) * (core + 273.15) / (ambient + 273.15) - ATM   # (gauge: the gas law on absolute)
		var over := maxf(surf - float((c.get("window", [82, 108]) as Array)[1]), 0.0)
		var wear_k := float(b.get("wear_per_mj", 0.022)) * 1e-6 * float(c.get("wear", 1.0)) * (1.0 + 0.04 * over)
		if wet < 0.3 and compound == "wet":
			wear_k *= float(c.get("dry_wear", 1.0))
		t.wear = minf(1.0, float(t.wear) + wear_k * p_slip * dt)
		# the disc: the brake's work in, the air out (ducted: much more at speed)
		var work: float = absf(w.brake_torque * w.omega) if w.brake_torque > 0.0 else 0.0
		disc[k] += dt * (work - (25.0 + 4.0 * v) * (float(disc[k]) - ambient)) / DISC_C[k]
	# fuel: by the throttle and the revs
	var thr: float = clampf(float(car.inp.throttle) if car.inp else 0.0, 0.0, 1.0)
	var burn := (IDLE_FUEL_LPS + FULL_FUEL_LPS * thr * (0.35 + 0.65 * float(car.rpm))) * dt
	fuel_l = maxf(0.0, fuel_l - burn)
	fuel_used += burn
	car.mass = base_mass + fuel_l * FUEL_KG_L


## The numbers for the HUD and the telemetry.
func readout() -> Dictionary:
	var out := {"compound": compound, "short": str(c.get("short", "?")), "fuel": fuel_l, "tank": tank_l, "limiter": limiter,
		"abs": abs_level, "tc": tc_level, "tyres": [], "discs": disc.duplicate()}
	for k in 4:
		var t: Dictionary = tyres[k]
		out.tyres.append({"surface": float(t.surface), "core": float(t.core), "pressure": float(t.pressure), "wear": float(t.wear),
			"flat": float(t.flat), "grip": grip(k)})
	return out


## Where a tyre temperature sits against the compound's window: -1 cold, 0 in it, 1 hot.
func band(temp: float) -> int:
	var win: Array = c.get("window", [82, 108])
	return -1 if temp < float(win[0]) else (1 if temp > float(win[1]) else 0)
