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
const OPEN := 0
const LOCKED := 1
const LSD := 2

## Per model. mass: kg; front: the share of the weight on the front axle;
## torque: N m at the peak of the curve (rpm, x the peak); limiter, idle: rpm;
## turbo: the share of the torque that's boost (0: none), spooling from / to rpm;
## gears, final: the ratios; drive: "awd" (front: the share forward), "rwd", "fwd";
## centre / front / rear: diffs [kind, power lock, coast lock, preload N m];
## cd, area (m²), down (m² of downforce, x the rally car's way of working it out);
## brake: x the rally car's brakes per kg.
const SPECS := {
	# the Prodrive Group A rally car (1987): 1,050 kg; 280-300 hp at 8,400 rpm, 285 N m at 6,500;
	# the Getrag five-speed (road ratios; the rally final drive isn't published: a short one)
	"e30": {"mass": 1050.0, "front": 0.50, "torque": 285.0,
		"curve": [[1000, 0.5], [2000, 0.6], [3000, 0.7], [4000, 0.8], [5000, 0.9], [6000, 0.98], [6500, 1.0], [7500, 0.95], [8400, 0.86], [8800, 0.78]],
		"idle": 950.0, "limiter": 8800.0, "turbo": 0.0,
		"gears": [3.72, 2.40, 1.77, 1.26, 1.0], "final": 4.10, "drive": "rwd",
		"rear": [LSD, 0.45, 0.25, 40.0], "cd": 0.33, "area": 1.85, "down": 0.1, "brake": 1.0},
	# the Group B rally car (1984-85): 1,100 kg, 52/48; 450 hp at 7,500, 460 N m at 5,500 (a big
	# turbo: lag); five-speed 3.500/2.083/1.368/0.962/0.821; the centre diff locked, LSDs front and rear
	"sport_quattro": {"mass": 1100.0, "front": 0.52, "torque": 460.0,
		"curve": [[1000, 0.28], [2000, 0.36], [3000, 0.55], [4000, 0.8], [5000, 0.97], [5500, 1.0], [6500, 0.97], [7500, 0.93], [8000, 0.85]],
		"idle": 1000.0, "limiter": 8000.0, "turbo": 0.55, "spool": [3200.0, 4800.0], "spool_time": 0.6, "anti_lag": false,
		"gears": [3.5, 2.083, 1.368, 0.962, 0.821], "final": 4.857, "drive": "awd", "front_share": 0.5,
		"centre": [LOCKED, 0.0, 0.0, 0.0], "front_diff": [LSD, 0.25, 0.1, 25.0], "rear": [LSD, 0.45, 0.15, 30.0],
		"cd": 0.42, "area": 1.95, "down": 0.25, "brake": 1.0},
	# Rally1 (2022-24): 1,260 kg; ~380 hp, 420 N m from the engine, 500+ with the hybrid's boosts
	# (not modelled: a little more torque instead); a spool (fixed 50/50), LSDs front and rear;
	# a five-speed sequential (ratios not published)
	"puma_rally1": {"mass": 1260.0, "front": 0.55, "torque": 450.0,
		"curve": [[1000, 0.35], [2000, 0.62], [3000, 0.9], [4000, 1.0], [5000, 1.0], [6000, 1.0], [7000, 0.85], [7600, 0.75]],
		"idle": 1000.0, "limiter": 7600.0, "turbo": 0.35, "spool": [2200.0, 3600.0], "spool_time": 0.3, "anti_lag": true,
		"gears": [2.85, 2.0, 1.56, 1.26, 1.04], "final": 4.4, "drive": "awd", "front_share": 0.5,
		"centre": [LOCKED, 0.0, 0.0, 0.0], "front_diff": [LSD, 0.25, 0.1, 25.0], "rear": [LSD, 0.45, 0.12, 30.0],
		"cd": 0.42, "area": 2.15, "down": 0.75, "brake": 1.05},
	# Turbo II (13B-T), the 1989-91 JDM GT-X: 1,250 kg; 205 PS at 6,500, 270 N m at 3,500;
	# 3.483/2.015/1.391/1.000/0.762, final 4.100; an LSD
	"rx7_fc": {"mass": 1250.0, "front": 0.505, "torque": 270.0,
		"curve": [[1000, 0.45], [2000, 0.7], [3000, 0.95], [3500, 1.0], [4500, 0.97], [5500, 0.9], [6500, 0.82], [7000, 0.72]],
		"idle": 800.0, "limiter": 7000.0, "turbo": 0.4, "spool": [2000.0, 3200.0], "spool_time": 0.45, "anti_lag": false,
		"gears": [3.483, 2.015, 1.391, 1.0, 0.762], "final": 4.10, "drive": "rwd",
		"rear": [LSD, 0.35, 0.2, 30.0], "cd": 0.31, "area": 1.78, "down": 0.0, "brake": 0.85},
	# Type R (1992-95 JDM): 1,260 kg, 50/50; 255 PS at 6,500, 294 N m at 5,000 (sequential twin
	# turbos), 8,000 rpm; 3.483/2.015/1.391/1.000/0.719, final 4.100; a Torsen LSD
	"rx7_fd": {"mass": 1260.0, "front": 0.50, "torque": 294.0,
		"curve": [[1000, 0.45], [2000, 0.62], [3000, 0.83], [4000, 0.95], [5000, 1.0], [6000, 0.97], [6500, 0.94], [7200, 0.83], [8000, 0.7]],
		"idle": 800.0, "limiter": 8000.0, "turbo": 0.4, "spool": [1800.0, 4500.0], "spool_time": 0.4, "anti_lag": false,
		"gears": [3.483, 2.015, 1.391, 1.0, 0.719], "final": 4.10, "drive": "rwd",
		"rear": [LSD, 0.4, 0.2, 30.0], "cd": 0.31, "area": 1.75, "down": 0.05, "brake": 0.9},
	# SiR II (EG6, 1992 JDM): 1,050 kg; B16A, 170 PS at 7,800, 157 N m at 7,300, 8,200 rpm
	# (VTEC's cam change ~5,600); 3.230/2.105/1.458/1.107/0.848, final 4.400
	"civic_eg": {"mass": 1050.0, "front": 0.61, "torque": 157.0,
		"curve": [[1000, 0.6], [2000, 0.72], [3000, 0.8], [4000, 0.85], [5000, 0.87], [5600, 0.93], [6500, 0.98], [7300, 1.0], [8000, 0.95], [8200, 0.92]],
		"idle": 750.0, "limiter": 8200.0, "turbo": 0.0,
		"gears": [3.230, 2.105, 1.458, 1.107, 0.848], "final": 4.40, "drive": "fwd",
		"front_diff": [OPEN, 0.0, 0.0, 0.0], "cd": 0.32, "area": 1.85, "down": 0.0, "brake": 0.8},
}

## The rally car's size (body, cabin) the inertia scales from: length, width, height (m).
const BASE_SIZE := Vector3(3.9, 1.7, 1.35)

static var _cache := {}


## The CarConfig for this model (none, or one without a spec: the rally car).
static func config(model: String) -> Resource:
	var base: Resource = load(BASE)
	if not SPECS.has(model):
		return base
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
