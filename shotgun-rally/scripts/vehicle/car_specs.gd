extends RefCounted
## The cars with bodies of their own (assets/models/cars/<model>/: the GLB and
## parts.json that tools/import_car.py makes from a downloaded model) and numbers
## of their own, the real cars' (docs/cars.md: the sources). Each is the AWD
## rally car (data/cars/awd_rally.tres) made over (config):
##   * its wheels where the model's are, the model's tyre size (parts.json), so
##     the body sits on the physics wheels
##   * its weight and weight split (where the centre of mass sits between the
##     axles), its inertia scaled from the rally car's by weight and size
##   * its engine (torque curve, limiter, turbo or not), gearbox and final drive,
##     which wheels are driven, its diffs. Rear- and front-drive cars have no
##     rally handbrake clutch: pulling the handbrake dips the clutch instead
##   * springs, dampers and anti-roll bars scaled with its weight (the same ride
##     frequencies); its brakes with its weight and tyre size
##   * its collision boxes from the model's body; its aero (drag, frontal area,
##     downforce for the winged cars)

const BASE := "res://data/cars/awd_rally.tres"
const MODELS := "res://assets/models/cars/"
const DifferentialConfig = preload("res://scripts/vehicle/physics/config/differential_config.gd")
const VehicleRegistry = preload("res://scripts/game/vehicle_registry.gd")
const OPEN := 0
const LOCKED := 1
const LSD := 2

## Per model, from the vehicle registry (data/vehicles/<id>.json "physics": the real
## car's numbers and where they come from are in each entry's "specs"). mass: kg;
## front: the share of the weight on the front axle; torque: N m at the peak of the
## curve (rpm, x the peak); limiter, idle: rpm; turbo: the share of the torque
## that's boost (0: none), spooling from / to rpm; gears, final: the ratios; drive:
## "awd" (front_share: the share forward), "rwd", "fwd"; centre / front_diff / rear:
## diffs [kind, power lock, coast lock, preload N m]; cd, area (m²), down (m² of
## downforce, x the rally car's way of working it out); brake: x the rally car's
## brakes per kg.
static var SPECS: Dictionary = VehicleRegistry.physics()

## What kind of car it is underneath ("chassis" in a spec; the rally car's own when
## absent). travel: m; freq: the ride frequency, x the rally car's (springs x freq²);
## damp: the dampers on top of that (x freq x damp); arb: the anti-roll bars; mu: the
## tyres' grip, x the rally tyre's; peak: where their grip peaks (slip), x; loose: how
## much of their grip they keep off tarmac (slicks on gravel: little); steer: degrees
## of lock; com: the centre of mass, m below the rally car's.
## The road classes set their suspension outright instead, from the car's own weight
## (_road_suspension): ride: the ride frequency front / rear (Hz); roll: how far the body
## leans per g of cornering (deg; real cars: an SUV 3.5-5, a sports car 2-3, a GT3 ~1);
## roll_front: the front axle's share of the roll stiffness (55-65 % on road cars: they
## push before they slide); cog: the centre of mass's height above the road (m); zeta:
## the dampers' share of critical, bump / rebound; room: the travel above the car at rest
## before the bump stop (m); us: its understeer gradient to start from (deg of steering per g
## past the geometry: SIM street steering goes through it and learns the car's own as it's
## driven, DriverAssist._learn). An SUV leans and nods and settles in a bob or two; a sports
## car leans a little; a GT3 hardly at all.
const CHASSIS := {
	"rally": {},
	"road": {"travel": 0.17, "us": 0.7, "ride": [1.4, 1.5], "roll": 2.8, "roll_front": 0.62, "cog": 0.52, "zeta": [0.32, 0.62], "room": 0.09,
		"mu": 1.0, "peak": 0.95, "loose": 0.85, "steer": 34.0},
	"suv": {"travel": 0.2, "us": 1.0, "ride": [1.25, 1.35], "roll": 4.0, "roll_front": 0.66, "cog": 0.66, "zeta": [0.32, 0.62], "room": 0.1,
		"mu": 0.97, "peak": 1.0, "loose": 0.9, "steer": 36.0},
	# a performance SUV (X5 M, Trackhawk): stiffer and lower than a plain one, on wider tyres; still tall
	"sport_suv": {"travel": 0.18, "us": 0.8, "ride": [1.45, 1.55], "roll": 3.2, "roll_front": 0.63, "cog": 0.62, "zeta": [0.36, 0.68], "room": 0.09,
		"mu": 1.02, "peak": 0.96, "loose": 0.88, "steer": 35.0},
	# a tall, boxy one (the G-Class): soft, high, rolls and pitches more, on a ladder frame's steering
	"tall_suv": {"travel": 0.22, "us": 1.2, "ride": [1.2, 1.3], "roll": 4.8, "roll_front": 0.64, "cog": 0.74, "zeta": [0.3, 0.58], "room": 0.11,
		"mu": 0.96, "peak": 1.04, "loose": 0.95, "steer": 33.0},
	"sport": {"travel": 0.14, "us": 0.4, "ride": [1.65, 1.75], "roll": 2.1, "roll_front": 0.62, "cog": 0.46, "zeta": [0.36, 0.7], "room": 0.07,
		"mu": 1.06, "peak": 0.9, "loose": 0.8, "steer": 33.0},
	"track": {"travel": 0.09, "us": 0.3, "ride": [2.4, 2.6], "roll": 1.2, "roll_front": 0.52, "cog": 0.4, "zeta": [0.45, 0.8], "room": 0.04,
		"mu": 1.3, "peak": 0.8, "loose": 0.55, "steer": 27.0},
	"prototype": {"travel": 0.07, "us": 0.2, "ride": [2.9, 3.1], "roll": 0.8, "roll_front": 0.5, "cog": 0.34, "zeta": [0.5, 0.85], "room": 0.03,
		"mu": 1.4, "peak": 0.75, "loose": 0.45, "steer": 24.0},
}


## A chassis class on a config made from the rally car (in place).
static func _chassis(c: Resource, kind: String) -> void:
	var k: Dictionary = CHASSIS.get(kind, {})
	if k.is_empty():
		return
	if k.has("ride"):
		_road_suspension(c, k)
	else:
		var f: float = k.freq
		for sus in [c.front_suspension, c.rear_suspension]:
			var stop_at: float = sus.bump_stop_start / sus.travel
			sus.travel = k.travel
			sus.bump_stop_start = k.travel * stop_at
			sus.spring_rate = sus.spring_rate * f * f
			for n in ["bump_damping", "rebound_damping", "high_speed_bump", "high_speed_rebound"]:
				sus.set(n, float(sus.get(n)) * f * k.damp)
			sus.anti_roll_rate = sus.anti_roll_rate * k.arb
			sus.max_force = maxf(sus.max_force, sus.spring_rate * k.travel * 3.0)
	for t in [c.front_tire, c.rear_tire]:
		t.lateral_mu = t.lateral_mu * k.mu
		t.longitudinal_mu = t.longitudinal_mu * k.mu
		t.lateral_peak_deg = t.lateral_peak_deg * k.peak
		t.longitudinal_peak = t.longitudinal_peak * k.peak
		t.loose_grip = t.loose_grip * k.loose
	if c.steering:
		c.steering.max_angle_deg = k.steer
	if k.has("cog"):                                  # (its height above the road, the car at rest on its springs)
		c.center_of_mass.y = float(k.cog) - _ride_height(c)
	else:
		c.center_of_mass.y -= float(k.get("com", 0.0))


## A road car's springs, dampers and bars from its own weight (a chassis class with "ride"):
## the springs for the ride frequency on each corner's share of the weight, the dampers a
## share of critical on them, room to roll and nod before the bump stops, and the bars
## for the roll gradient: the roll stiffness that leans it "roll" degrees a g with its
## centre of mass at "cog" (the tyres push at the road), the front taking "roll_front".
static func _road_suspension(c: Resource, k: Dictionary) -> void:
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var loads: Array = c.static_loads(g)
	var zeta: Array = k.get("zeta", [0.3, 0.55])
	var room: float = float(k.get("room", 0.08))
	var roll_k: float = c.mass * g * float(k.cog) / deg_to_rad(float(k.roll))
	for i in 2:
		var sus: Resource = c.front_suspension if i == 0 else c.rear_suspension
		var corner: float = loads[i] / g
		var w: float = TAU * float(k.ride[i])
		var fast_bump: float = sus.high_speed_bump / maxf(sus.bump_damping, 1.0)
		var fast_rebound: float = sus.high_speed_rebound / maxf(sus.rebound_damping, 1.0)
		sus.spring_rate = w * w * corner
		var crit := 2.0 * sqrt(sus.spring_rate * corner)
		sus.bump_damping = float(zeta[0]) * crit
		sus.rebound_damping = float(zeta[1]) * crit
		sus.high_speed_bump = sus.bump_damping * fast_bump
		sus.high_speed_rebound = sus.rebound_damping * fast_rebound
		var at_rest: float = loads[i] / sus.spring_rate
		sus.bump_stop_start = at_rest + room
		sus.travel = maxf(float(k.travel), sus.bump_stop_start + 0.04)
		var track: float = c.front_track if i == 0 else c.rear_track
		var share: float = float(k.roll_front) if i == 0 else 1.0 - float(k.roll_front)
		sus.anti_roll_rate = maxf(share * roll_k / (track * track) - sus.spring_rate * 0.5, 0.0)
		sus.max_force = maxf(sus.max_force, sus.spring_rate * sus.travel * 3.0)
	c.road_suspension = true
	c.understeer = float(k.get("us", 0.0))


## The rally car (the shared body) at a weight of its own (kg; 0: the rally car's
## 1,280): its inertia, springs, dampers, bars, tyre loads and brakes scaled with
## the weight, as for the cars above (the same ride frequencies).
static func rally(mass: float) -> Resource:
	var base: Resource = load(BASE)
	if mass <= 0.0 or absf(mass - base.mass) < 0.5:
		return base
	var key := "rally %d" % roundi(mass)
	if _cache.has(key):
		return _cache[key]
	var c: Resource = base.duplicate(true)
	var k: float = mass / base.mass
	c.mass = mass
	c.inertia = base.inertia * k
	for sus in [c.front_suspension, c.rear_suspension]:
		for f in ["spring_rate", "bump_damping", "rebound_damping", "high_speed_bump", "high_speed_rebound", "anti_roll_rate"]:
			sus.set(f, float(sus.get(f)) * k)
	for t in [c.front_tire, c.rear_tire]:
		t.nominal_load = float(t.nominal_load) * k
	c.brake_torque = base.brake_torque * k
	c.handbrake_torque = base.handbrake_torque * k
	_cache[key] = c
	return c


## The rally car's size (body, cabin) the inertia scales from: length, width, height (m).
const BASE_SIZE := Vector3(3.9, 1.7, 1.35)

static var _cache := {}


## The CarConfig for this model (none, or one without a spec: the rally car, at
## `mass` kg if given: rally()).
static func config(model: String, mass := 0.0) -> Resource:
	var base: Resource = load(BASE)
	if not SPECS.has(model):
		return rally(mass)
	if _cache.has(model):
		return _cache[model]
	var s: Dictionary = SPECS[model]
	var info := parts(model)
	var c: Resource = base.duplicate(true)
	# the wheels where the model's are
	var w: Array = info.wheels
	c.front_axle = (float(w[0][2]) + float(w[1][2])) * 0.5
	c.rear_axle = (float(w[2][2]) + float(w[3][2])) * 0.5
	c.front_track = absf(float(w[1][0]) - float(w[0][0]))
	c.rear_track = absf(float(w[3][0]) - float(w[2][0]))
	c.tyre_radius = float(info.radius[0])
	c.tyre_width = clampf(float(info.width[0]), 0.18, 0.3)
	c.wheel_inertia = base.wheel_inertia * pow(c.tyre_radius / base.tyre_radius, 2.0)
	# weight, where it sits, how it turns
	var m: float = s.mass
	var k: float = m / base.mass
	c.mass = m
	var wb: float = c.rear_axle - c.front_axle
	c.center_of_mass = Vector3(0.0, base.center_of_mass.y, c.rear_axle - float(s.front) * wb)
	var lo: Array = info.body_min
	var hi: Array = info.body_max
	var half_w: float = absf(float(w[0][0])) + float(info.width[0]) * 0.5
	var size := Vector3(float(hi[2]) - float(lo[2]), half_w * 2.0, float(hi[1]))
	var b := BASE_SIZE
	c.inertia = Vector3(base.inertia.x * k * (size.x * size.x + size.z * size.z) / (b.x * b.x + b.z * b.z),
		base.inertia.y * k * (size.x * size.x + size.y * size.y) / (b.x * b.x + b.y * b.y),
		base.inertia.z * k * (size.y * size.y + size.z * size.z) / (b.y * b.y + b.z * b.z))
	# springs, dampers, bars: the same frequencies on its weight
	for sus in [c.front_suspension, c.rear_suspension]:
		for f in ["spring_rate", "bump_damping", "rebound_damping", "high_speed_bump", "high_speed_rebound", "anti_roll_rate"]:
			sus.set(f, float(sus.get(f)) * k)
	for t in [c.front_tire, c.rear_tire]:
		t.nominal_load = base.front_tire.nominal_load * k
	c.brake_torque = base.brake_torque * k * (c.tyre_radius / base.tyre_radius) * float(s.get("brake", 1.0))
	c.handbrake_torque = base.handbrake_torque * k
	# the engine
	var e: Resource = c.engine
	var rpm := PackedFloat32Array()
	var tq := PackedFloat32Array()
	for p in s.curve:
		rpm.append(float(p[0]))
		tq.append(float(p[1]))
	e.rpm_points = rpm
	e.torque_points = tq
	e.max_torque = s.torque
	e.idle_rpm = s.idle
	e.limiter_rpm = s.limiter
	e.turbo_share = s.turbo
	if s.turbo > 0.0:
		e.spool_start_rpm = s.spool[0]
		e.spool_full_rpm = s.spool[1]
		e.spool_time = s.get("spool_time", base.engine.spool_time)
	e.anti_lag = bool(s.get("anti_lag", false))
	if s.has("regen"):                              # (an electric car: no pumping losses, its motor's regen instead)
		e.regen_torque = float(s.regen)
		e.closed_throttle_per_rpm = 0.0
		e.friction_per_rpm = float(s.get("motor_loss", 0.001))
	# the gearbox and the diffs
	var d: Resource = c.drivetrain
	d.gear_ratios = PackedFloat32Array(s.gears)
	d.final_drive = s.final
	d.upshift_rpm = float(s.limiter) - 350.0
	d.downshift_rpm = float(s.limiter) * 0.45
	d.launch_rpm = clampf(float(s.limiter) * 0.5, 3000.0, 4500.0)
	d.clutch_torque = maxf(base.drivetrain.clutch_torque, float(s.torque) * 1.4)
	match str(s.drive):
		"rwd":
			d.front_share = 0.0
			d.handbrake_disconnects_rear = false
		"fwd":
			d.front_share = 1.0
			d.handbrake_disconnects_rear = false
		_:
			d.front_share = float(s.get("front_share", 0.5))
	for key in ["centre", "front_diff", "rear"]:
		if s.has(key):
			var dc: Resource = {"centre": d.center_diff, "front_diff": d.front_diff, "rear": d.rear_diff}[key]
			dc.kind = int(s[key][0])
			dc.power_lock = float(s[key][1])
			dc.coast_lock = float(s[key][2])
			dc.preload_torque = float(s[key][3])
	# aero
	c.drag_coefficient = s.cd
	c.frontal_area = s.area
	c.downforce_area = s.down
	_chassis(c, str(s.get("chassis", "rally")))      # (before the collision: the ride height depends on it)
	# collision: the body up to the window line, the cabin above it (the car's frame:
	# the ground ride_height below its origin)
	var ground := -_ride_height(c)
	var sill: float = maxf(float(info.get("sill", 0.25)), 0.26)
	var belt: float = float(info.belt) if info.get("belt") != null else sill + 0.5
	var length: float = float(hi[2]) - float(lo[2])
	c.body_size = Vector3(half_w * 2.0 - 0.06, belt - sill, length - 0.1)
	c.body_center = Vector3(0.0, ground + (sill + belt) * 0.5, (float(lo[2]) + float(hi[2])) * 0.5)
	var roof: float = float(hi[1])
	c.cabin_size = Vector3(half_w * 2.0 * 0.78, maxf(roof - belt - 0.04, 0.2), length * 0.42)
	c.cabin_center = Vector3(0.0, ground + (belt + roof - 0.04) * 0.5, (float(lo[2]) + float(hi[2])) * 0.5 + length * 0.04)
	_cache[model] = c
	return c


## The engine's peak power (PS), x the garage's power (an upgraded engine): the
## most torque x revs along its curve, on full boost.
static func power_ps(c: Resource, mult := 1.0) -> float:
	var e: Resource = c.engine
	if e == null:
		return 0.0
	var best := 0.0
	for k in e.rpm_points.size():
		best = maxf(best, e.max_torque * mult * e.torque_points[k] * e.rpm_points[k] / 9549.3)
	return best / 0.7355


## The model's parts.json: where its wheels are, how big, its body's extent, its sills and window line.
static func parts(model: String) -> Dictionary:
	var path := MODELS + model + "/parts.json"
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


static func _ride_height(c: Resource) -> float:
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var loads: Array = c.static_loads(g)
	var Suspension = load("res://scripts/vehicle/physics/suspension.gd")
	var comp: float = (Suspension.static_compression(c.front_suspension, loads[0]) + Suspension.static_compression(c.rear_suspension, loads[1])) * 0.5
	return c.tyre_radius + (c.front_suspension.travel + c.rear_suspension.travel) * 0.5 - comp - c.mount_height
