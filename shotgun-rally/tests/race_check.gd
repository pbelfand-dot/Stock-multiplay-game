extends SceneTree
## Track Mode's race car physics (scripts/vehicle/physics/race_sim.gd, RallyCar.race): tyre heat,
## pressure, wear and compounds; brake heat and fade; fuel and its weight; the pit limiter; the
## car's own ABS / TC levels; nothing changed for a car without it.
## Run: godot --headless --fixed-fps 120 --path . -s tests/race_check.gd
##   sim: (a stand-in car) a cold tyre grips less, one in its window fully, an overheated one less;
##     the hot pressure from the cold setting by the gas law (1.4 bar cold -> ~1.95 at ~90 C);
##     sliding wears it, a soft faster than a hard, a worn one loses grip at the cliff; a locked
##     wheel at speed grinds a flat spot; the brakes' work heats the disc and the air cools it,
##     a cold or cooked disc bites less; fuel burns by throttle and revs, the car gets lighter;
##     a pit stop's new tyres and fuel
##   car: (the ELFER R in the physics lab) the race state on the car and its grip on each wheel;
##     the pit limiter holds 60 km/h flat out; a stop from 200 km/h heats the front discs more
##     than the rears; a minute of cornering brings the tyres up from cold; the aids from the
##     car's levels; a car without it untouched
##   plan: your pit strategy (PitPlan): AUTO's safe default (worn tyres changed, the same compound;
##     wets onto a wet track, off them onto a dry one; fresh ones in qualifying), a chosen compound,
##     KEEP, the fuel to the end / +5 laps / none (never more than the tank holds), repairs off
## Prints one [race] line per check; exits 1 on any FAIL.

const RaceSim = preload("res://scripts/vehicle/physics/race_sim.gd")
const Lab = preload("res://scripts/physics_lab.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	print("[race] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


class FakeWheel:
	var grounded := true
	var omega := 0.0
	var radius := 0.34
	var v_long := 0.0
	var long_force := 0.0
	var lateral_force := 0.0
	var v_lat := 0.0
	var load := 3500.0
	var slip_long := 0.0
	var brake_torque := 0.0


class FakeConfig:
	var mass := 1250.0


class FakeCar:
	var speed := 0.0
	var wheels: Array = []
	var inp := {"throttle": 0.0}
	var rpm := 0.0
	var config := FakeConfig.new()
	var mass := 1250.0
	func _init() -> void:
		for k in 4:
			wheels.append(FakeWheel.new())


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	await process_frame
	_sim()
	_plan()
	await _car()
	print("[race] %s" % ("RACE OK" if fails == 0 else "RACE FAIL"))
	quit(1 if fails else 0)


# ── your pit strategy ─────────────────────────────────────────────────────

func _plan() -> void:
	var PitPlan = load("res://scripts/game/pit_plan.gd")
	var p = PitPlan.new()
	var ctx := {"worn": 0.1, "race": true, "compound": "slick_medium", "wet": 0.0, "laps_left": 4, "per_lap": 3.4, "fuel": 6.0,
		"tank": 120.0, "damage": 0.2}
	var sv: Dictionary = p.service(ctx)
	check(not sv.tyres and absf(float(sv.fuel) - (5 * 3.4 - 6.0)) < 0.01 and float(sv.repair) == 0.2,
		"plan: AUTO in a race on fresh tyres: no tyres, fuel to the end and a lap (%.1f l), the repairs (%s)" % [float(sv.fuel), PitPlan.describe(sv)])
	ctx.worn = 0.45
	sv = p.service(ctx)
	check(sv.tyres and sv.compound == "slick_medium", "plan: AUTO on worn tyres: a new set of the same (%s)" % PitPlan.describe(sv))
	ctx.worn = 0.1
	ctx.wet = 0.7
	var on_wet: Dictionary = p.service(ctx)
	ctx.compound = "wet"
	ctx.wet = 0.0
	var off_wet: Dictionary = p.service(ctx)
	ctx.compound = "slick_medium"
	ctx.race = false
	var quali: Dictionary = p.service(ctx)
	check(on_wet.compound == "wet" and off_wet.compound == "slick_medium" and quali.tyres,
		"plan: AUTO puts wets on for a wet track (%s), slicks back on a dry one (%s), fresh tyres in qualifying" % [PitPlan.describe(on_wet), PitPlan.describe(off_wet)])
	ctx.race = true
	p.cycle_tyres()                              # SOFT
	var soft: Dictionary = p.service(ctx)
	for k in 4:
		p.cycle_tyres()                          # MEDIUM, HARD, WET, KEEP
	var keep: Dictionary = p.service(ctx)
	ctx.worn = 0.9
	var keep_worn: Dictionary = p.service(ctx)
	check(soft.tyres and soft.compound == "slick_soft" and not keep.tyres and not keep_worn.tyres and p.tyres_text() == "PIT TYRES: KEEP",
		"plan: a chosen compound always fits a set (%s); KEEP never does, worn or not" % PitPlan.describe(soft))
	p.cycle_fuel()                               # +5 LAPS
	var plus5: Dictionary = p.service(ctx)
	ctx.fuel = 110.0
	var full: Dictionary = p.service(ctx)
	p.cycle_fuel()                               # NONE
	var none: Dictionary = p.service(ctx)
	p.toggle_repair()
	var no_fix: Dictionary = p.service(ctx)
	check(absf(float(plus5.fuel) - 17.0) < 0.01 and absf(float(full.fuel) - 10.0) < 0.01 and float(none.fuel) == 0.0 and float(no_fix.repair) == 0.0,
		"plan: +5 LAPS is %.0f l (no more than the tank takes: %.0f l into 110), NONE is none, REPAIRS OFF skips them" % [float(plus5.fuel), float(full.fuel)])


# ── the sim on a stand-in ─────────────────────────────────────────────────

func _sim() -> void:
	var car := FakeCar.new()
	var r = RaceSim.new()
	r.setup(car, {"compound": "slick_medium", "fuel": 60.0, "ambient": 22.0})
	var cold: float = r.grip(0)
	for k in 4:
		r.tyres[k].surface = 95.0
		r.tyres[k].core = 90.0
		r.tyres[k].pressure = 1.95
	var warm: float = r.grip(0)
	r.tyres[0].surface = 150.0
	r.tyres[0].core = 140.0
	var hot: float = r.grip(0)
	check(cold < 0.9 and absf(warm - 1.0) < 0.01 and hot < warm - 0.04, "sim: a cold medium grips %.2f, in its window %.2f, cooked %.2f" % [cold, warm, hot])
	# pressure by the gas law, from the cold setting (gauge)
	r.setup(car, {"compound": "slick_medium", "ambient": 22.0})
	var dt := 1.0 / 120.0
	car.speed = 40.0
	for w in car.wheels:
		w.v_lat = 1.2
		w.lateral_force = 4000.0
	var t := 0.0
	while t < 240.0:
		r.tick(car, dt)
		t += dt
	var tt: Dictionary = r.tyres[0]
	var want_p: float = (1.4 + 1.013) * (float(tt.core) + 273.15) / (22.0 + 273.15) - 1.013
	check(float(tt.core) > 55.0 and absf(float(tt.pressure) - want_p) < 0.005 and float(tt.pressure) > 1.65,
		"sim: four minutes of steady cornering heat the tyre (surface %.0f C, core %.0f C), its pressure up from 1.40 to %.2f bar (the gas law)" % [tt.surface, tt.core, tt.pressure])
	# wear: soft vs hard, the cliff
	var wears := {}
	for comp in ["slick_soft", "slick_hard"]:
		r.setup(car, {"compound": comp, "ambient": 22.0})
		for k in 600 * 120 / 60:
			r.tick(car, dt)
		wears[comp] = float(r.tyres[0].wear)
	check(wears.slick_soft > wears.slick_hard * 2.0 and wears.slick_hard > 0.0, "sim: sliding wears the tyre, a soft %.1f times as fast as a hard (%.4f / %.4f in 10 s)" % [
		wears.slick_soft / maxf(wears.slick_hard, 1e-9), wears.slick_soft, wears.slick_hard])
	r.setup(car, {"compound": "slick_medium", "ambient": 22.0})
	for k in 4:
		r.tyres[k].surface = 95.0
		r.tyres[k].core = 90.0
		r.tyres[k].pressure = 1.95
	var g_new: float = r.grip(0)
	r.tyres[0].wear = 0.5
	var g_half: float = r.grip(0)
	r.tyres[0].wear = 1.0
	var g_gone: float = r.grip(0)
	check(g_new - g_half < 0.04 and g_half - g_gone > 0.1, "sim: wear fades slowly (half worn %.3f) then falls off the cliff (worn out %.3f)" % [g_half, g_gone])
	# a flat spot
	r.tyres[0].wear = 0.0
	car.wheels[0].slip_long = -1.0
	for k in 60:
		r.tick(car, dt)
	car.wheels[0].slip_long = 0.0
	check(float(r.tyres[0].flat) > 0.05 and float(r.tyres[1].flat) == 0.0, "sim: a wheel locked at speed for half a second grinds a flat spot (%.2f), the others don't" % float(r.tyres[0].flat))
	# brakes
	r.setup(car, {"compound": "slick_medium", "ambient": 22.0})
	car.speed = 50.0
	var d0: float = r.disc[0]
	for w in car.wheels:
		w.omega = 50.0 / 0.34
		w.brake_torque = 2400.0
		w.v_lat = 0.0
		w.lateral_force = 0.0
	for k in 3 * 120:
		r.tick(car, dt)
	var d_hot: float = r.disc[0]
	for w in car.wheels:
		w.brake_torque = 0.0
	for k in 20 * 120:
		r.tick(car, dt)
	var d_cool: float = r.disc[0]
	check(d_hot > d0 + 150.0 and d_cool < d_hot - 100.0, "sim: three seconds of hard braking take a disc from %.0f to %.0f C, twenty at speed cool it to %.0f" % [d0, d_hot, d_cool])
	r.disc[0] = 40.0
	var m_cold: float = r.brake_mul(0)
	r.disc[0] = 450.0
	var m_ok: float = r.brake_mul(0)
	r.disc[0] = 950.0
	var m_fade: float = r.brake_mul(0)
	check(m_cold < 1.0 and m_ok == 1.0 and m_fade < 0.75, "sim: a cold disc bites %.2f, a warm one %.2f, one at 950 C fades to %.2f" % [m_cold, m_ok, m_fade])
	# fuel
	r.setup(car, {"fuel": 60.0, "ambient": 22.0})
	var m0: float = car.mass
	car.inp.throttle = 1.0
	car.rpm = 1.0
	for k in 60 * 120:
		r.tick(car, dt)
	var used: float = 60.0 - r.fuel_l
	check(used > 2.0 and used < 3.0 and car.mass < m0 - 1.5, "sim: a minute flat out burns %.2f l (a GT3 at ~405 kW: ~2.5), the car %.1f kg lighter" % [used, m0 - car.mass])
	car.inp.throttle = 0.0
	r.tyres[0].wear = 0.6
	r.service(car, "slick_soft", 40.0)
	check(r.compound == "slick_soft" and float(r.tyres[0].wear) == 0.0 and absf(r.fuel_l - (60.0 - used + 40.0)) < 0.01 and float(r.tyres[0].core) < 30.0,
		"sim: a pit stop: four new softs (at the air's temperature: no warmers), 40 l in (%.1f l)" % r.fuel_l)


# ── on a car in the lab ───────────────────────────────────────────────────

func _car() -> void:
	var course := Node3D.new()
	root.add_child(course)
	Lab.build_course(course)
	var Catalog = load("res://scripts/game/catalog.gd")
	var car = (load(Lab.CAR_SCENE) as PackedScene).instantiate()
	root.add_child(car)
	await physics_frame
	var s: Dictionary = Catalog.setup("elfer_r")
	s["tyre"] = "tarmac"
	s["preset"] = "tarmac"
	s["race_sim"] = true
	s["race"] = {"compound": "slick_medium", "fuel": 60.0, "ambient": 22.0, "abs": 6, "tc": 3}
	car.apply_setup(s)
	car.place(Lab.SKID, 0.0)
	await physics_frame
	await physics_frame
	var race = car.race
	check(race != null and absf(car.wheels[0].race_mu - race.grip(0)) < 1e-4 and car.mass > float(car.config.mass) + 40.0,
		"car: the ELFER R carries the race state (grip x%.3f on each wheel from cold, %.0f kg with 60 l of fuel)" % [race.grip(0) if race else 0.0, car.mass])
	check(car.assist.cfg.anti_lock and car.assist.cfg.traction_control and absf(car.assist.cfg.abs_band - lerpf(0.18, 0.06, 5.0 / 9.0)) < 1e-4,
		"car: its own ABS (level 6) and traction control (level 3) on, whatever Settings says")
	# the pit limiter: flat out with it on
	race.limiter = true
	car.inp.throttle = 1.0
	var top := 0.0
	for k in 15 * 120:
		await physics_frame
		if k > 8 * 120:
			top = maxf(top, car.kmh())
	var held: float = car.kmh()
	check(held > 56.0 and held < 62.0 and top < 63.0, "car: the pit limiter holds %.1f km/h flat out (top %.1f; the limit 60)" % [held, top])
	race.limiter = false
	# a stop from 200 km/h
	Lab.launch(car, Lab.SKID, 200.0 / 3.6)
	car.inp.throttle = 0.0
	await physics_frame
	var f0: float = race.disc[0]
	var r0: float = race.disc[2]
	car.inp.brake = 1.0
	while car.kmh() > 50.0:
		await physics_frame
	car.inp.brake = 0.0
	var df: float = race.disc[0] - f0
	var dr: float = race.disc[2] - r0
	check(df > 100.0 and df > dr, "car: a stop from 200 to 50 km/h heats the front discs %.0f C, the rears %.0f" % [df, dr])
	# a minute of cornering from cold
	race.service(car, "slick_medium", 0.0)
	Lab.launch(car, Lab.SKID, 22.0)
	var s0: float = race.tyres[0].surface
	car.inp.steer = 0.35
	car.inp.throttle = 0.45
	for k in 60 * 120:
		await physics_frame
	car.inp.steer = 0.0
	car.inp.throttle = 0.0
	var temps: Array = race.tyres.map(func(x): return float(x.surface))
	check(temps.max() > s0 + 15.0, "car: a minute of cornering brings the tyres up from %.0f C (%s)" % [s0, ", ".join(temps.map(func(x): return "%.0f" % x))])
	# without it
	var s2: Dictionary = Catalog.setup("elfer_r")
	s2["tyre"] = "tarmac"
	s2["preset"] = "tarmac"
	car.apply_setup(s2)
	await physics_frame
	check(car.race == null and car.wheels[0].race_mu == 1.0 and absf(car.mass - float(car.config.mass)) < 0.01, "car: without race_sim the car is untouched (no race state, grip x1, its own mass)")
	car.queue_free()
	await process_frame
