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
##   ers_torque(car, dt, brake)  a hybrid's motor (a Formula car's MGU-K: setup "ers" kW): its push
##                  at the crankshaft and the energy store it runs from and recharges
##   drs_rear()     the rear downforce x: the DRS flap open sheds some of it (and drag_mul the drag)
##
## The hybrid (FORMULA APEX's rules, from 2022-25 Formula 1's): a 120 kW MGU-K deploys at most 4 MJ a
## lap from the store and recovers at most 2 MJ a lap under braking; the turbo's MGU-H tops the store
## up at full throttle (unlimited by the rules: here ~30 kW). The store holds 4 MJ. The modes: OFF
## (recharge only), BALANCED (deploys flat out above ~110 km/h, where it's worth most), OVERTAKE
## (deploys whenever it's flat out). A "lap" is a lap's length driven (setup "lap_m").
## DRS: the car's flap opens only when race control says it may (drs_avail: in a zone, within a
## second at its detection point in a race), on the driver's press (or by itself for the AI: drs_auto),
## and shuts on the brakes or out of the zone.
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
var tow := 0.0                       # (RaceField) 0..1: how deep in another car's slipstream it is
var damage := {"aero": 0.0, "engine": 0.0, "susp": 0.0}   # 0..1 each
var damage_on := true                # (the session's DAMAGE option)
const TOW_DRAG := 0.3                # the drag a car loses right behind another (a GT3: ~25-35 % at a length or two)
const DRS_DRAG := 0.18               # the drag shed with the DRS flap open (the FIA's estimate: +10-12 km/h by a zone's end)
const DRS_REAR := 0.13               # the rear axle's downforce shed with it (the wing's top flap: ~7 % of the car's)
const ERS_STORE := 4.0e6             # J: the energy store's usable charge
const ERS_DEPLOY_LAP := 4.0e6        # J a lap: the most the MGU-K may deploy
const ERS_HARVEST_LAP := 2.0e6       # J a lap: the most it may recover under braking
const ERS_MGUH := 30000.0            # W: the turbo's MGU-H topping the store up at full throttle
const ERS_BALANCED_V := 30.0         # m/s: BALANCED deploys above this (108 km/h)
const ERS_MAX_NM := 220.0            # N m: its most at the crank (at low revs the power's capped by this)
const ERS_MODES := ["OFF", "BALANCED", "OVERTAKE"]

var ers_kw := 0.0                    # the hybrid motor's power (kW; 0: none)
var ers_mode := 1                    # 0 OFF, 1 BALANCED, 2 OVERTAKE
var ers_store := ERS_STORE           # J in the store
var ers_used := 0.0                  # J deployed this lap
var ers_got := 0.0                   # J recovered under braking this lap
var ers_on := false                  # deploying now
var lap_m := 5000.0                  # a lap's length (m): the per-lap limits reset each lap driven
var _lap_run := 0.0
var drs_avail := false               # race control: it may open now (set each tick)
var drs_open := false
var drs_auto := false                # the AI: open it whenever it may, flat out
var fuel_lps := FULL_FUEL_LPS        # l/s flat out (a Formula car's fuel flow is capped: 100 kg/h)
const DIRTY_DOWN := 0.15             # the downforce it loses there (the wake: a GT3's ~10-20 %)


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
	damage_on = bool(opts.get("damage", true))
	ers_kw = float(opts.get("ers", 0.0))
	lap_m = float(opts.get("lap_m", lap_m))
	fuel_lps = float(opts.get("fuel_lps", FULL_FUEL_LPS))
	ers_store = ERS_STORE
	ers_used = 0.0
	ers_got = 0.0
	_lap_run = 0.0
	drs_open = false
	repair()
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
	# the hot pressure against the ideal (a little either way doesn't matter), once it's warm: a cold
	# tyre's pressure is low because it's cold, and the compound's cold grip already counts that (both
	# together made a cold slick 25 % down, not the 15-20 % the compounds say)
	var dp := absf(float(t.pressure) - float(b.get("pressure_ideal_bar", 1.95)))
	var warm := smoothstep(float(win[0]) - 25.0, float(win[0]), temp)
	g *= 1.0 - float(b.get("pressure_loss_per_bar", 0.18)) * maxf(dp - 0.05, 0.0) * warm
	# wear: a slow fade to wear_soft_from, then the cliff to worn_grip at 1
	var w := float(t.wear)
	var w0 := float(b.get("wear_soft_from", 0.7))
	if w < w0:
		g *= 1.0 - 0.04 * w / w0
	else:
		g *= lerpf(0.96, float(b.get("worn_grip", 0.82)), clampf((w - w0) / (1.0 - w0), 0.0, 1.0))
	g *= 1.0 - minf(float(t.flat), 0.25) * 0.2                   # a flat spot: a little less, and it shakes
	g *= lerpf(1.0, float(c.get("wet", 0.5)), wet) if wet > 0.0 else 1.0
	g *= 1.0 - 0.12 * float(damage.susp)                          # (a bent arm, the alignment out)
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
	t *= 1.0 - 0.35 * float(damage.engine)                        # (a damaged engine: less power)
	if limiter:
		var lim := limiter_kmh / 3.6
		t = minf(t, clampf((lim - absf(float(car.speed))) * 0.9, 0.0, 1.0))
	return t


## The ABS / traction control settings onto the car's assist config (Track Mode's GT cars run
## the car's own aids, by level, whatever Settings says for the rally): level 1 lets the tyre
## slip furthest, 10 cuts in earliest; 0 off. Traction control aims the driven tyres' spin at
## their peak slip x 1.4 (level 1) .. x 0.75 (10): the middle levels hold it about at the peak,
## the most drive with the grip sideways kept (it used to let it run a band of up to 0.3 past
## the peak before cutting, and a GT3 on cold slicks spun on a tap of steering).
func apply_aids(cfg: Resource) -> void:
	cfg.anti_lock = abs_level > 0
	cfg.traction_control = tc_level > 0
	if abs_level > 0:
		cfg.abs_band = lerpf(0.18, 0.06, (abs_level - 1) / 9.0)
	if tc_level > 0:
		var k := (tc_level - 1) / 9.0
		cfg.tc_target = lerpf(1.4, 0.75, k)
		cfg.tc_band = lerpf(0.2, 0.06, k)


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
			p_in = p_slip * float(c.get("heat", 1.0)) + FLEX * float(c.get("flex", 1.0)) * w.load * v + K_ROAD * w.load * (track - float(t.surface))
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
	var burn := (IDLE_FUEL_LPS + fuel_lps * thr * (0.35 + 0.65 * float(car.rpm))) * dt
	fuel_l = maxf(0.0, fuel_l - burn)
	fuel_used += burn
	car.mass = base_mass + fuel_l * FUEL_KG_L


## The drag x: the slipstream (less behind another car), a damaged nose (more).
func drag_mul() -> float:
	return (1.0 - TOW_DRAG * tow) * (1.0 + 0.1 * float(damage.aero)) * (1.0 - DRS_DRAG if drs_open else 1.0)


## The rear axle's downforce x: the DRS flap open.
func drs_rear() -> float:
	return 1.0 - DRS_REAR if drs_open else 1.0


## The driver's DRS button: open it if it may (it shuts by itself).
func drs_press() -> void:
	if drs_avail:
		drs_open = true


## The ERS mode button: OFF -> BALANCED -> OVERTAKE -> OFF.
func ers_cycle() -> void:
	ers_mode = (ers_mode + 1) % ERS_MODES.size()


## Before the physics tick (the pedals as the driver has them, after the limiter): the DRS flap
## shut on the brakes or out of its zone (or opened by the AI); the hybrid's push at the crankshaft
## (N m: the drivetrain adds it to the engine's) and the energy that takes from the store; what
## braking puts back. 0 for a car without one.
func ers_torque(car, dt: float, throttle: float, brake: float) -> float:
	if not drs_avail or brake > 0.05:
		drs_open = false
	elif drs_auto and throttle > 0.9:
		drs_open = true
	if ers_kw <= 0.0:
		ers_on = false
		return 0.0
	var v: float = absf(float(car.speed))
	_lap_run += v * dt
	if _lap_run >= lap_m:                                          # (a lap driven: the limits start again)
		_lap_run -= lap_m
		ers_used = 0.0
		ers_got = 0.0
	var dtr = car.drivetrain
	var cap := ers_kw * 1000.0
	# recovery: the MGU-K on the brakes (up to 2 MJ a lap), the MGU-H flat out (as much as it likes)
	if brake > 0.1 and v > 8.0 and ers_got < ERS_HARVEST_LAP:
		var e := minf(cap * clampf(brake * 1.5, 0.0, 1.0) * dt, ERS_HARVEST_LAP - ers_got)
		ers_got += e
		ers_store = minf(ERS_STORE, ers_store + e)
	if throttle > 0.9:
		ers_store = minf(ERS_STORE, ers_store + ERS_MGUH * dt)
	# deployment
	ers_on = false
	if dtr == null or dtr.shifting() or dtr.gear < 1 or throttle < 0.95 or ers_mode == 0:
		return 0.0
	if ers_mode == 1 and v < ERS_BALANCED_V:
		return 0.0
	var left := minf(ers_store, ERS_DEPLOY_LAP - ers_used)
	if left <= 0.0:
		return 0.0
	var omega: float = maxf(float(dtr.rpm()) * TAU / 60.0, 100.0)
	var tq := minf(cap / omega, ERS_MAX_NM)
	var e := minf(tq * omega * dt, left)
	ers_used += e
	ers_store -= e
	ers_on = true
	return e / (omega * dt)


## The downforce x: the wake behind another car, a damaged splitter or wing.
func down_mul() -> float:
	return (1.0 - DIRTY_DOWN * tow) * (1.0 - 0.35 * float(damage.aero))


## A hit (m/s of speed lost against a wall or a car): bodywork past 4 m/s, the suspension past 7,
## the engine past 14 (the session's DAMAGE option off: nothing).
func hit(impact: float) -> void:
	if not damage_on:
		return
	damage.aero = clampf(float(damage.aero) + maxf(impact - 4.0, 0.0) * 0.035, 0.0, 1.0)
	damage.susp = clampf(float(damage.susp) + maxf(impact - 7.0, 0.0) * 0.03, 0.0, 1.0)
	damage.engine = clampf(float(damage.engine) + maxf(impact - 14.0, 0.0) * 0.03, 0.0, 1.0)


## The damage's worst part (0..1).
func damage_level() -> float:
	return maxf(float(damage.aero), maxf(float(damage.engine), float(damage.susp)))


## The pit crew's repairs: all of it.
func repair() -> void:
	damage = {"aero": 0.0, "engine": 0.0, "susp": 0.0}


## Off the physics (RaceField's far car): the fuel by an average lap's throttle, the tyres at a
## racing temperature and wearing at an average lap's rate, the brakes at theirs.
func coast(car, dt: float, v: float, task: String) -> void:
	var racing := task == "race" and v > 10.0
	var thr := 0.62 if racing else (0.25 if v > 1.0 else 0.0)
	var burn := (IDLE_FUEL_LPS + fuel_lps * thr * 0.85) * dt
	fuel_l = maxf(0.0, fuel_l - burn)
	fuel_used += burn
	var win: Array = c.get("window", [82, 108])
	var run := lerpf(float(win[0]), float(win[1]), 0.45) if racing else ambient + 20.0
	for k in 4:
		var t: Dictionary = tyres[k]
		t.surface = move_toward(float(t.surface), run + (4.0 if k < 2 else 0.0), dt * 0.6)
		t.core = move_toward(float(t.core), run - 6.0, dt * 0.25)
		t.pressure = (cold_bar + ATM) * (float(t.core) + 273.15) / (ambient + 273.15) - ATM
		# a medium's ~3 % a racing lap of ~5 km (the physics' own rate at race pace)
		t.wear = minf(1.0, float(t.wear) + (6.0e-6 * float(c.get("wear", 1.0)) * v * dt if racing else 0.0))
		disc[k] = move_toward(float(disc[k]), 420.0 if racing else ambient + 40.0, dt * 8.0)
	if car:
		car.mass = base_mass + fuel_l * FUEL_KG_L


## The numbers for the HUD and the telemetry.
func readout() -> Dictionary:
	var out := {"compound": compound, "short": str(c.get("short", "?")), "fuel": fuel_l, "tank": tank_l, "limiter": limiter,
		"abs": abs_level, "tc": tc_level, "tyres": [], "discs": disc.duplicate(), "damage": damage.duplicate(), "tow": tow,
		"ers": ers_kw > 0.0, "ers_store": ers_store / ERS_STORE, "ers_left": maxf(ERS_DEPLOY_LAP - ers_used, 0.0) / ERS_DEPLOY_LAP,
		"ers_mode": ERS_MODES[ers_mode], "ers_on": ers_on, "drs_avail": drs_avail, "drs_open": drs_open}
	for k in 4:
		var t: Dictionary = tyres[k]
		out.tyres.append({"surface": float(t.surface), "core": float(t.core), "pressure": float(t.pressure), "wear": float(t.wear),
			"flat": float(t.flat), "grip": grip(k)})
	return out


## Where a tyre temperature sits against the compound's window: -1 cold, 0 in it, 1 hot.
func band(temp: float) -> int:
	var win: Array = c.get("window", [82, 108])
	return -1 if temp < float(win[0]) else (1 if temp > float(win[1]) else 0)
