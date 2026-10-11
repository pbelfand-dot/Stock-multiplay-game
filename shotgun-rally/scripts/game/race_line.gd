extends RefCounted
## A car's speed round a circuit on its racing line (CircuitGen.line, from tools/circuit_map.py):
## the fastest it can take each metre, as a lap-time simulation does. Track Mode's AI drives to
## it (RaceDriver), and its far-away cars move along it (RaceField's cheap mode). Pure logic: the
## tests build one without a car (params()).
##
##   * every corner's limit: v^2 |k| = mu (g + downforce / m), the downforce growing with v^2 and
##     the tyres' grip per newton falling a little as it loads them (their load sensitivity, as
##     the tyre model has it: TireModel.load_mu_factor); solved for v (a fast sweeper a GT3's
##     wings hold flat has no limit but its top speed);
##   * braking back from each one (backward pass): the tyres' grip and the downforce and drag
##     slow it, less what the corner's already using of the grip (the friction circle), and a
##     downhill run slows it less;
##   * accelerating out of each (forward pass): the engine's force at that speed in its best gear
##     (torque x ratios / tyre radius, through the driveline's losses), held to what the driven
##     tyres can put down, less drag, rolling resistance and the climb.
## Skill (pace) is how near the limit a driver takes it: its grip and braking x pace. Never more
## than the car has: a better driver doesn't get more grip or power, only uses more of it.

const RaceSim = preload("res://scripts/vehicle/physics/race_sim.gd")
const CarSpecs = preload("res://scripts/vehicle/car_specs.gd")
const G := 9.81
const RHO := 1.225
const ETA := 0.88                  # the driveline's efficiency (gearbox, diff, joints)
const ROLL := 0.012                # rolling resistance (a race tyre's), x the weight
const V_TOP := 95.0                # m/s: a cap where the gearing would let it go on (342 km/h)
const K_PHYS := 0.92               # the share of the tyres' grip a driver really uses lap after lap: the
                                   # physics car's peak needs its slip angle just so, and a corner's braking
                                   # and power share the grip less neatly than a friction circle (measured:
                                   # tests/race_ai_check.gd's AI lap on the physics against this line)

var n := 0                         # samples round the lap (the circuit's)
var step := 2.0                    # m along the centreline between them
var d := PackedFloat32Array()      # the line's offset from the centreline (+ right) at each
var k := PackedFloat32Array()      # the line's own curvature (1/m, + a right turn)
var ds := PackedFloat32Array()     # the line's own length from each sample to the next (m)
var grade := PackedFloat32Array()  # its rise over that length
var v_limit := PackedFloat32Array()  # each corner's own limit (m/s)
var v := PackedFloat32Array()      # the speed it can carry there, braking and accelerating included
var lap_time := 0.0
var p := {}                        # the car (params)
var pace := 1.0


## A car's numbers for the line from its config (a RallyCar): mass (with its fuel), its tyres' grip
## in g (SIM street's figure for its tyres, else its tyre's own), aero, engine and gears.
static func params(car) -> Dictionary:
	var cfg = car.config
	var mu := 1.2
	if car.street.size() > 0:
		mu = float(car.street[0])
	elif cfg.front_tire:
		mu = float(cfg.front_tire.lateral_mu) * 0.92
	var e = cfg.engine
	var dt = cfg.drivetrain
	var front := float(dt.front_share) if dt else 0.0
	return {"mass": float(car.mass), "mu": mu, "down": float(cfg.downforce_area), "cd_a": float(cfg.drag_coefficient) * float(cfg.frontal_area),
		"radius": float(cfg.tyre_radius), "torque": float(e.max_torque) if e else 300.0,
		"rpm_points": e.rpm_points if e else PackedFloat32Array([1000.0, 7000.0]),
		"torque_points": e.torque_points if e else PackedFloat32Array([1.0, 1.0]),
		"limiter": float(e.limiter_rpm) if e else 7000.0,
		"gears": dt.gear_ratios if dt else PackedFloat32Array([3.0, 2.0, 1.5, 1.2, 1.0]),
		"final": float(dt.final_drive) if dt else 4.0,
		# the driven axle's share of the weight (rear drive: the rear's; all-wheel: all of it)
		# (static_loads is per wheel, so a two-wheel-drive car's figure is half its driven axle's share:
		# kept so, as it matches what the AI's exits put down on the physics, the cornering sharing the
		# grip; tests/race_ai_check.gd's laps on the physics were measured against it)
		"driven": 1.0 if front > 0.05 and front < 0.95 else (cfg.static_loads(G)[1] / (float(cfg.mass) * G) if cfg.has_method("static_loads") else 0.55),
		"load_sens": float(cfg.front_tire.load_sensitivity) if cfg.front_tire else 0.15,
		# a tyre's share of the car's weight against the load it's rated at (its nominal: a Formula
		# slick's is far above its share of an 800 kg car, so downforce costs it little grip per newton)
		"load_r0": float(car.mass) * G * 0.25 / float(cfg.front_tire.nominal_load) if cfg.front_tire else 1.0,
		"ers": float(car.race.ers_kw) if car.get("race") != null else 0.0,
		# a car whose tyres are harder for a driver to hold at their peak (a Formula car's: sharper past
		# it, the car snappier): the share of the line's grip its drivers take ("ai_grip" in its physics)
		"ai_grip": float(CarSpecs.SPECS.get(str(car.setup.get("model", "")) if car.get("setup") is Dictionary else "", {}).get("ai_grip", 1.0))}


## The line and the car's speed along it. st: the CircuitGen (its line); prm: params(); pace:
## the driver's (0.85 .. 1.0).
func build(st, prm: Dictionary, pace_k := 1.0) -> void:
	p = prm
	pace = pace_k
	step = st.STEP
	n = int(round(st.length / step))
	d.resize(n)
	k.resize(n)
	ds.resize(n)
	grade.resize(n)
	var pts := PackedVector3Array()
	pts.resize(n + 1)
	for i in n:
		d[i] = st.line[i] if st.line.size() > i else 0.0
		k[i] = st.line_curv[i] if st.line_curv.size() > i else st.curv[i]
	for i in n + 1:
		pts[i] = st.world_at(i * step, d[i % n])
	for i in n:
		var a := pts[i]
		var b := pts[i + 1]
		ds[i] = maxf(a.distance_to(b), 0.05)
		grade[i] = (b.y - a.y) / ds[i]
	p.erase("ers_f")
	_solve()
	if float(p.get("ers", 0.0)) > 0.0:
		# a hybrid deploys flat out above ~110 km/h, but only 4 MJ a lap: the share of that time it
		# lasts (the line again with its push x that share)
		var flat := 0.0
		for i in n:
			var j := (i + 1) % n
			if v[j] > v[i] + 0.01 and v[i] > RaceSim.ERS_BALANCED_V:
				flat += ds[i] / maxf((v[i] + v[j]) * 0.5, 1.0)
		var full: float = RaceSim.ERS_DEPLOY_LAP / (float(p.ers) * 1000.0)
		p["ers_f"] = clampf(full / maxf(flat, 0.1), 0.0, 1.0)
		_solve()


## The speeds: the corners' limits, then braking back from them and accelerating out of them.
func _solve() -> void:
	v_limit.resize(n)
	v.resize(n)
	for i in n:
		# (curvature averaged over the car's length: a sample's kink isn't a corner)
		var kk := absf((k[(i + n - 1) % n] + k[i] + k[(i + 1) % n]) / 3.0)
		v_limit[i] = _corner_v(kk)
		v[i] = v_limit[i]
	# from the slowest corner round, twice (a loop: the end leads into the start)
	var lo := 0
	for i in n:
		if v_limit[i] < v_limit[lo]:
			lo = i
	# braking: backward from each sample into the one before
	for q in 2 * n:
		var i1 := posmod(lo - q, n)
		var i0 := posmod(i1 - 1, n)
		var vb := sqrt(v[i1] * v[i1] + 2.0 * _decel(v[i1], i0) * ds[i0])
		if vb < v[i0]:
			v[i0] = vb
	# accelerating: forward from each sample into the next
	for q in 2 * n:
		var i0 := posmod(lo + q, n)
		var i1 := (i0 + 1) % n
		var va := sqrt(maxf(v[i0] * v[i0] + 2.0 * _accel(v[i0], i0) * ds[i0], 0.0))
		if va < v[i1]:
			v[i1] = va
	lap_time = 0.0
	for i in n:
		lap_time += ds[i] / maxf((v[i] + v[(i + 1) % n]) * 0.5, 1.0)


## The grip (m/s^2 of sideways or braking force) at speed vv: mu x pace x (g + the downforce),
## each tyre's grip per newton falling as its load passes the load it's rated at (load
## sensitivity, as TireModel.load_mu_factor has it).
func grip_at(vv: float) -> float:
	var a: float = 0.5 * RHO * float(p.down) * vv * vv / float(p.mass)
	var r: float = float(p.get("load_r0", 1.0)) * (1.0 + a / G)       # (each tyre's load / its rated load)
	var sens := clampf(1.0 - float(p.get("load_sens", 0.15)) * (r - 1.0), 0.5, 1.4)
	return float(p.mu) * pace * K_PHYS * float(p.get("ai_grip", 1.0)) * sens * (G + a)


## The fastest it can take a curvature kk (1/m): where v^2 kk meets its grip at v (bisection: the
## grip grows with v, the need faster).
func _corner_v(kk: float) -> float:
	if kk < 1e-6 or grip_at(V_TOP) >= V_TOP * V_TOP * kk:
		return V_TOP
	var lo := 0.0
	var hi := V_TOP
	for q in 30:
		var mid := (lo + hi) * 0.5
		if grip_at(mid) >= mid * mid * kk:
			lo = mid
		else:
			hi = mid
	return lo


## How hard it can slow at speed vv on sample i (m/s^2): the brakes up to the grip left over from
## cornering, plus drag, plus the climb (minus a descent).
func _decel(vv: float, i: int) -> float:
	var m: float = p.mass
	var grip := grip_at(vv)
	var lat := vv * vv * absf(k[i])
	var left := sqrt(maxf(1.0 - (lat / maxf(grip, 0.1)) * (lat / maxf(grip, 0.1)), 0.0))
	var drag := 0.5 * RHO * float(p.cd_a) * vv * vv / m
	return maxf(grip * left + drag + ROLL * G + G * grade[i], 1.0)


## How hard it can speed up at vv on sample i (m/s^2): the engine's force in its best gear at that
## speed, up to what the driven tyres can put down beside the cornering, less drag, rolling, climb.
func _accel(vv: float, i: int) -> float:
	var m: float = p.mass
	var f := drive_force(vv)
	var grip := grip_at(vv)
	var lat := vv * vv * absf(k[i])
	var left := sqrt(maxf(1.0 - (lat / maxf(grip, 0.1)) * (lat / maxf(grip, 0.1)), 0.0))
	f = minf(f, grip * m * float(p.driven) * left)
	var drag := 0.5 * RHO * float(p.cd_a) * vv * vv
	return (f - drag) / m - ROLL * G - G * grade[i]


## The engine's force at the tyres at speed vv (N), in the gear that gives the most (and a hybrid's
## motor on top: its power over the speed, above ~110 km/h, x the share of the lap it lasts).
func drive_force(vv: float) -> float:
	var r: float = p.radius
	var best := 0.0
	if float(p.get("ers_f", 0.0)) > 0.0 and vv > RaceSim.ERS_BALANCED_V:
		best = float(p.ers) * 1000.0 * ETA * float(p.ers_f) / vv
	var gears: PackedFloat32Array = p.gears
	var eng := 0.0
	for g in gears:
		var ratio: float = g * float(p.final)
		var rpm := maxf(vv, 0.5) / r * ratio * 60.0 / TAU
		if rpm > float(p.limiter):
			continue
		rpm = maxf(rpm, 2500.0)                          # (a launch: the clutch slips at revs)
		eng = maxf(eng, float(p.torque) * _curve(rpm) * ratio * ETA / r)
	return best + eng


func _curve(rpm: float) -> float:
	var rp: PackedFloat32Array = p.rpm_points
	var tp: PackedFloat32Array = p.torque_points
	if rpm <= rp[0]:
		return tp[0]
	for i in range(1, rp.size()):
		if rpm <= rp[i]:
			return lerpf(tp[i - 1], tp[i], (rpm - rp[i - 1]) / (rp[i] - rp[i - 1]))
	return tp[tp.size() - 1]


## The sample for s (any lap).
func index(s: float) -> int:
	return posmod(int(floor(s / step)), n)


## The speed it can carry at s (m/s), between samples.
func speed_at(s: float) -> float:
	var f := fposmod(s, n * step) / step
	var i := mini(int(f), n - 1)
	return lerpf(v[i], v[(i + 1) % n], f - i)


## The line's offset at s (m, + right).
func d_at(s: float) -> float:
	var f := fposmod(s, n * step) / step
	var i := mini(int(f), n - 1)
	return lerpf(d[i], d[(i + 1) % n], f - i)


## The line's curvature at s.
func k_at(s: float) -> float:
	return k[index(s)]


## The lowest speed it should be doing anywhere over the next `reach` m from s at most `decel`
## m/s^2 of braking (the speed to brake to now: for a slower car ahead, a corner): v at s.
func braking_speed(s: float, reach: float) -> float:
	var want := V_TOP
	var i0 := index(s)
	var dist := 0.0
	for q in int(reach / step):
		var i := (i0 + q) % n
		want = minf(want, sqrt(v[i] * v[i] + 2.0 * _decel(v[i], i) * dist))
		dist += ds[i]
	return want


## The distance along the line from s0 to s1 (s1 ahead), in the line's own metres.
func line_dist(s0: float, s1: float) -> float:
	return (s1 - s0) * (lap_length() / (n * step))


## The line's length round the lap (m).
func lap_length() -> float:
	var t := 0.0
	for i in n:
		t += ds[i]
	return t
