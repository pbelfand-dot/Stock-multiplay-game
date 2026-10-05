extends RefCounted
## The drivetrain: the engine, the clutch, the sequential gearbox and final
## drive, and the three differentials (centre, front, rear) of a four-wheel-
## drive car, with their state (the engine's spin, the boost, the gear, the
## clutch).
##
## Each substep the engine and the four wheels are solved together:
##   1. the engine spins up with its torque, down with its friction (more with
##      the throttle shut: engine braking); each wheel gets its spin from its
##      tyre alone (rally_wheel.gd), with an effective inertia that includes
##      the tyre's grip resisting a change of speed
##   2. the couplings, as friction-limited constraints, solved a few times
##      round (sequential impulses):
##        * the clutch: engine speed = gear ratio x the driveline's speed, as
##          long as the torque that takes is under the clutch's capacity;
##          otherwise it slips, carrying its capacity
##        * the centre diff splits the torque front / rear by front_share; the
##          front and rear diffs split each axle's equally. Open: nothing more,
##          so a light wheel spins up and the torque to its partner is only
##          what it takes to spin it. Locked: the two sides turn together. LSD:
##          they're held together by up to preload + lock x the torque through it
##        * the brakes and rolling resistance: friction holding each wheel still,
##          up to their torque
##        * pulling the handbrake lets the rear axle go (a clutch in the drive to
##          it, as on a Rally2 car): the gearbox then drives the fronts, and the
##          rears only through that clutch, slipping; let go, it bites again
##   So an open diff losing drive to a wheel in the air, a locked centre diff
##   pushing the car straight on, an LSD's power-on bite: none of it is
##   scripted, it's the couplings and the tyres.
## The automatic clutch (pulling away, changing gear) and auto-shift stand in
## for the driver's left foot and hand: control().

const EngineModel = preload("res://scripts/vehicle/physics/engine.gd")
const DifferentialConfig = preload("res://scripts/vehicle/physics/config/differential_config.gd")
const ITERATIONS := 8
const LAUNCH_GAIN := 0.5           # N m more through the slipping clutch per rpm over the launch revs

var cfg: Resource                  # DrivetrainConfig
var eng: Resource                  # EngineConfig

var omega_e := 0.0                 # the engine's spin (rad/s)
var gear := 1                      # -1 reverse, 0 neutral, 1..n
var boost := 0.0                   # the turbo's boost, 0..1
var clutch := 1.0                  # the clutch's engagement, 0 (out) .. 1 (in)
var throttle := 0.0                # the engine's actual throttle (after the shift cut, the limiter, idle control)
var engine_torque := 0.0           # N m the engine makes this substep
var clutch_torque := 0.0           # N m through the clutch (engine side, + = driving)
var limiter := false
var handbrake := 0.0               # the handbrake lever, 0..1 (the car sets it)
var rear_coupling := 1.0           # the rear axle's clutch: 0 (let go) .. 1 (in)

var _shift_t := 0.0
var _next_gear := 1
var _driveline := 0.0              # the gearbox output's speed (rad/s) from the wheels, last control()


func setup(drivetrain: Resource, engine: Resource) -> void:
	cfg = drivetrain
	eng = engine
	reset()


## Engine at idle, first gear, no boost.
func reset() -> void:
	omega_e = eng.idle_rpm / EngineModel.TO_RPM
	gear = 1
	boost = 0.0
	clutch = 0.0
	_shift_t = 0.0
	handbrake = 0.0
	rear_coupling = 1.0


func rpm() -> float:
	return omega_e * EngineModel.TO_RPM


func gears() -> int:
	return cfg.gear_ratios.size()


## The total ratio (engine turns per wheel turn) in gear g: reverse negative, neutral 0.
func ratio_for(g: int) -> float:
	if g > 0:
		return cfg.gear_ratios[g - 1] * cfg.final_drive
	if g < 0:
		return -cfg.reverse_ratio * cfg.final_drive
	return 0.0


func ratio() -> float:
	return ratio_for(gear)


func shifting() -> bool:
	return _shift_t > 0.0


## Change gear (sequential: the drive is cut for shift_time, then it's in).
func shift(to: int) -> void:
	to = clampi(to, -1, gears())
	if to == gear or shifting():
		return
	_next_gear = to
	_shift_t = cfg.shift_time


func shift_up() -> void:
	shift(gear + 1)


func shift_down() -> void:
	shift(gear - 1)


## The front axle's share of the drive: the centre diff's, or all of it while the
## handbrake has let the rear go.
func split() -> float:
	return 1.0 if rear_coupling < 1.0 else cfg.front_share


## The driveline's speed at the gearbox output (rad/s) from the wheels: the centre
## diff's split of the axles' average speeds.
func driveline_speed(wheels: Array) -> float:
	var b := split()
	return b * (wheels[0].omega + wheels[1].omega) * 0.5 + (1.0 - b) * (wheels[2].omega + wheels[3].omega) * 0.5


## Once a tick, before the substeps: the shift timer, the limiter, the throttle,
## the boost, the automatic clutch and gear changes. pedal: the throttle (after
## traction control); launch: the driver's own pedal, which sets the revs the
## clutch slips at pulling away (traction control cutting the throttle mustn't
## bog the launch); -1: the same as pedal.
func control(dt: float, pedal: float, wheels: Array, launch := -1.0) -> void:
	if _shift_t > 0.0:
		_shift_t -= dt
		if _shift_t <= 0.0:
			gear = _next_gear
	var r := rpm()
	if r > eng.limiter_rpm:
		limiter = true
	elif r < eng.limiter_rpm - 150.0:
		limiter = false
	throttle = 0.0 if shifting() or limiter else clampf(pedal, 0.0, 1.0)
	throttle = maxf(throttle, clampf((eng.idle_rpm + 100.0 - r) / 300.0, 0.0, 1.0) * 0.35)   # idle control
	if cfg.handbrake_disconnects_rear:                # a light pull already lets it go; it bites again smoothly
		var want := 1.0 - clampf(handbrake * 4.0, 0.0, 1.0)
		rear_coupling = move_toward(rear_coupling, want, dt / (0.02 if want < rear_coupling else cfg.rear_reengage_time))
	else:
		rear_coupling = 1.0
	var target := EngineModel.boost_target(eng, r, pedal)
	boost = move_toward(boost, target, dt / (eng.spool_time if target > boost else eng.spool_time * 0.6))
	# the automatic clutch: out while changing gear or in neutral; pulling away, it
	# slips at the revs the throttle asks for; rolling, it's in
	_driveline = driveline_speed(wheels)
	var drive_rpm := absf(_driveline * ratio()) * EngineModel.TO_RPM
	var foot := launch if launch >= 0.0 else pedal
	var hold := lerpf(eng.idle_rpm + 300.0, cfg.launch_rpm, foot)   # the revs it pulls away at
	if shifting() or gear == 0:
		clutch = 0.0
	elif foot < 0.05:
		clutch = 1.0 if drive_rpm >= eng.idle_rpm * 1.1 else 0.0   # rolling: in (engine braking); stopped: out (it idles)
	elif drive_rpm >= hold or (absi(gear) > 1 and drive_rpm >= eng.idle_rpm * 1.1):
		clutch = 1.0                                 # the car has caught up with the engine (or it's not pulling away)
	else:
		# pulling away (first or reverse) it slips, holding the engine at those revs
		# until the car catches up: it carries what the engine makes, more if the
		# revs rise past them, less if they fall. So however heavy the load the
		# engine pulls at those revs instead of bogging, and when traction control
		# cuts the throttle the clutch passes on the smaller torque instead of grabbing.
		var made: float = EngineModel.torque(eng, r, throttle, boost) - EngineModel.friction(eng, r, throttle)
		clutch = clampf((maxf(made, 0.0) + LAUNCH_GAIN * (r - hold)) / cfg.clutch_torque, 0.0, 1.0)
	if cfg.auto_shift and not shifting() and gear >= 1:
		if r > cfg.upshift_rpm and gear < gears():
			shift_up()
		elif gear > 1 and r < cfg.downshift_rpm:
			var lower := absf(_driveline * ratio_for(gear - 1)) * EngineModel.TO_RPM
			if lower < cfg.upshift_rpm - 500.0:
				shift_down()


## One substep (h s): the engine and the four wheels together (see the top).
## Each wheel brings its predicted spin (omega), its effective inertia (i_eff)
## and the friction torque holding it (resist_torque).
func solve(h: float, wheels: Array) -> void:
	var r := rpm()
	engine_torque = EngineModel.torque(eng, r, throttle, boost)
	var n_e: float = eng.inertia * omega_e + h * engine_torque
	var stop := h * EngineModel.friction(eng, r, throttle)
	omega_e = 0.0 if absf(n_e) <= stop else (n_e - signf(n_e) * stop) / eng.inertia
	var g := ratio()
	var cap: float = clutch * cfg.clutch_torque * h
	var b := split()
	var free_rear := rear_coupling < 1.0
	var jc := [-g * b * 0.5, -g * b * 0.5, -g * (1.0 - b) * 0.5, -g * (1.0 - b) * 0.5]
	var lam_c := 0.0
	var lam_cd := 0.0
	var lam_f := 0.0
	var lam_r := 0.0
	var lam_b := [0.0, 0.0, 0.0, 0.0]
	for it in ITERATIONS:
		if cap > 0.0 and g != 0.0:
			var c := omega_e
			var denom: float = 1.0 / eng.inertia
			for k in 4:
				c += jc[k] * wheels[k].omega
				denom += jc[k] * jc[k] / wheels[k].i_eff
			var acc := clampf(lam_c - c / denom, -cap, cap)
			var d := acc - lam_c
			lam_c = acc
			omega_e += d / eng.inertia
			for k in 4:
				wheels[k].omega += jc[k] * d / wheels[k].i_eff
		# the torque into the centre diff (N m): + the engine driving (either way), - engine braking.
		# (The clutch's impulse is - when the engine pushes the wheels on: it slows the engine.)
		var t_in := -lam_c / h * absf(g)
		if free_rear:                                # the rear axle's clutch, slipping
			lam_cd = _row([0.5, 0.5, -0.5, -0.5], wheels, lam_cd, rear_coupling * cfg.rear_clutch_torque * h)
		elif b > 0.0 and b < 1.0:
			lam_cd = _diff(cfg.center_diff, [0.5, 0.5, -0.5, -0.5], wheels, lam_cd, h, t_in)
		lam_f = _diff(cfg.front_diff, [1.0, -1.0, 0.0, 0.0], wheels, lam_f, h, t_in * b)
		lam_r = _diff(cfg.rear_diff, [0.0, 0.0, 1.0, -1.0], wheels, lam_r, h, t_in * (1.0 - b))
		for k in 4:                                  # the brakes and rolling resistance
			var capb: float = h * wheels[k].resist_torque
			if capb <= 0.0:
				continue
			var acc := clampf(lam_b[k] - wheels[k].omega * wheels[k].i_eff, -capb, capb)
			wheels[k].omega += (acc - lam_b[k]) / wheels[k].i_eff
			lam_b[k] = acc
	clutch_torque = -lam_c / h


## One differential's coupling between its two sides (j: +1 / -1 on the two
## wheels, or the axles' halves for the centre); returns its impulse so far.
func _diff(dc: Resource, j: Array, wheels: Array, lam: float, h: float, t_in: float) -> float:
	if dc == null or dc.kind == DifferentialConfig.Kind.OPEN:
		return 0.0
	var cap := INF
	if dc.kind == DifferentialConfig.Kind.LSD:
		cap = (dc.preload_torque + (dc.power_lock if t_in >= 0.0 else dc.coast_lock) * absf(t_in)) * h
	return _row(j, wheels, lam, cap)


## A friction-limited coupling between wheels (j: each wheel's share of the speed
## it holds at zero), its impulse kept within cap; returns its impulse so far.
func _row(j: Array, wheels: Array, lam: float, cap: float) -> float:
	var c := 0.0
	var denom := 0.0
	for k in 4:
		c += j[k] * wheels[k].omega
		denom += j[k] * j[k] / wheels[k].i_eff
	if denom <= 0.0:
		return lam
	var acc := clampf(lam - c / denom, -cap, cap)
	var d := acc - lam
	for k in 4:
		wheels[k].omega += j[k] * d / wheels[k].i_eff
	return acc
