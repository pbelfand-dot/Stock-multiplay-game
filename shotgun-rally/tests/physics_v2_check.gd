extends SceneTree
## Physics v2 in the lab course (scripts/physics_lab.gd), at 120 ticks a second.
## Phase 1, the chassis on its four suspension corners:
##   * static: it sits level at the ride height the springs and its weight give
##     (each corner squashed by its share of the weight / the spring rate)
##   * bounce: lifted 5 cm and let go, it bounces at about the ride frequency
##     (~1.5 Hz, a little less for the damping) and settles within ~2 s
##   * drop: from a metre up it lands on the bump stops without the body
##     hitting the ground, doesn't bounce back into the air, and settles
##   * bumps: rolling over full-width bumps pitches it; over bumps under the
##     left wheels only, it rolls; the forces act at the corners, nothing levels it
## Phase 2, the tyres grip sideways and the front wheels steer:
##   * skid pad: towed round at 15 m/s with the wheel held at 2, 4, 8 and 15
##     degrees: the cornering force grows with the steering (at first just what
##     the geometry asks: v^2 x angle / wheelbase) and tops out at the tyres'
##     grip (mu g), never past it; front and rear slip angles reported
##   * side slope: parked across a 10 degree slope with no brakes, the tyres hold
##     it (the carcass sticks like a spring at a standstill): no creep, no wobble
##   * straight: at 20 m/s with the wheel straight it runs straight
## Phase 3, the wheels spin and the brakes work:
##   * a drive torque below the grip: it accelerates by exactly what the torque
##     gives (minus rolling resistance, with the wheels' own inertia to spin
##     up), the tyres barely slipping; well above it: wheelspin, and only
##     what the tyres can take
##   * brakes below the lock: exactly the torque's deceleration, no locking;
##     full pedal from 100 km/h: the wheels lock (they lock only because the
##     brakes beat the grip) and it slides to a stop on what a locked tyre keeps
##   * coasting: rolling resistance slows it, slowly
##   * nose up the slope: the brakes hold it; let go, it rolls back down
## Phase 4, one patch of rubber for both jobs, and load:
##   * at the cornering limit, brakes on: it loses cornering grip (the ellipse)
##     and the two together never pass the tyres' grip
##   * the same corner entered braking (trail braking) rotates the car more than
##     coasting into it: the nose loads and bites, the tail goes light
##   * a tyre with twice the load grips less per newton (load sensitivity)
## (phases 1-4 run in neutral: the tyres and brakes alone)
## Phase 5, the engine, clutch, gearbox and diffs:
##   * full throttle from a standstill: the clutch slips it away at the launch
##     revs, the tyres spin and hook up, it changes up by itself, each change
##     drops the revs by the ratio, the limiter is never passed, 0-100 km/h in a
##     rally car's time
##   * lifting off in third: engine braking, several times coasting's
##   * one wheel on ice: with open diffs that wheel spins and the car hardly
##     moves; with the car's LSDs and locked centre it pulls away
##   * stopped, holding the brake: reverse, and it backs up
## Phase 6, surfaces (the lab's pads: asphalt, gravel, dirt, snow, ice, mud,
## grass), each run on each:
##   * cornering: the wheel wound to 15 degrees from 15 m/s, coasting: the most
##     cornering it can do, the surface's grip x gravel's; the loose surfaces let
##     go at a bigger slip angle
##   * braking from 40 km/h on full brakes: between what locked tyres keep and
##     the peak grip (plus rolling resistance), never past it
##     (no ABS yet: phase 8)
##   * pulling away to 40 km/h on full throttle: never quicker than the grip allows
##   * coasting: each surface's rolling resistance
##   * split surface: braking with the left wheels on ice and the right on
##     asphalt, the car turns toward the asphalt (with every wheel locked nothing
##     holds it straight: it goes on round unless the driver steers against it)
## Phase 7, the handbrake, anti-roll bars and two-stage dampers:
##   * a handbrake turn at 15 m/s turns the car far more than the same steering
##     without it; while it's pulled the rears lock and the fronts keep rolling
##   * rolling at 36 km/h, handbrake and full throttle: the rear axle's clutch
##     lets go, so the rears stay locked while the fronts drive; without that
##     clutch the engine turns the rears through the locked centre: they don't
##     lock, the handbrake only drags
##   * body roll per g in a steady corner: what the springs and bars predict
##     (~2.9 deg / g with the bars, ~5.4 without)
##   * a stiffer front bar makes the car push more at the limit; a stiffer rear
##     bar lets the tail work
##   * over sharp bumps the two-stage dampers kick the body less than plain ones
## (phases 1-7 run with the aero off, so their numbers stay about what they test)
## Phase 8, aero:
##   * coasting from 150 km/h: drag (and the downforce's extra rolling
##     resistance) slow it as predicted
##   * downforce: practically nothing at 30 km/h, ~600 N at 150, 45 % on the front
## Phase 8, the driver aids (each its own switch; all off for every other run):
##   * all of them on, inside the grip (a steady corner, gentle braking): the
##     same car as with them off
##   * ABS: full brakes from 100 km/h stop shorter than locked, no wheel locking;
##     braking and steering, the car turns (locked, it slides straight on)
##   * traction control: flat out off the line on gravel the tyres don't go up
##     in smoke and it's no slower to 100; on ice it pulls away quicker
##   * stability control: a snow flick, the tail swings out less
##   * speed-sensitive steering: full lock at 90 km/h, the fronts work near their
##     peak instead of ploughing at 20+ degrees, and it corners at least as hard
##   * smoothing eases a key press in; damping slows the wheel at speed
##   * countersteer help: a slide let go of (hands off), it catches the car
##   * the Settings panel has a switch for each aid; switched on there, a new car
##     comes with it on (through Config)
##   * telemetry recording: a second of driving makes a CSV with a row a tick
## Phase 9, the rally manoeuvres, each a scripted driver on gravel (none of them
## has its own code: they come from the tyres, the diffs and the weight moving):
##   * lift-off oversteer: lift mid-corner and the tail steps out, the car tightens
##   * power oversteer: full throttle mid-corner and the tail swings wide
##   * four-wheel drift: a driver holding a slide keeps all four tyres past their
##     peak, cornering at the limit, without spinning
##   * countersteer catch: after a handbrake flick, steering where it's going
##     straightens it in a couple of seconds; hands off, it spins
##   * Scandinavian flick: a flick away before turning in rotates the car more than
##     turning in plain
##   * pendulum: a driver steering slide to slide, left, right, left: the body
##     angle swings from one side to the other without spinning
## Run: godot --headless --fixed-fps 120 --path . -s tests/physics_v2_check.gd
## Prints [physics] lines; exits 1 on any FAIL.

const Lab = preload("res://scripts/physics_lab.gd")
const Suspension = preload("res://scripts/vehicle/physics/suspension.gd")
const TireModel = preload("res://scripts/vehicle/physics/tire_model.gd")
const Surfaces = preload("res://scripts/vehicle/physics/surfaces.gd")
const Aero = preload("res://scripts/vehicle/physics/aero.gd")
const AssistConfig = preload("res://scripts/vehicle/physics/config/assist_config.gd")
const AIDS := ["anti_lock", "traction_control", "stability_control", "steering_smoothing", "steering_damping",
	"countersteer_help", "speed_sensitive_steering", "drift_assist"]

var car: RigidBody3D
var fails := 0
var _phase := -1
var _t := 0.0
var _log: Array = []               # per tick: [t, y, pitch, roll, grounded, max comp, min body clearance]
var _y0 := 0.0
var _lift_t := 0.0
var _phases := ["static", "bounce", "drop", "bumps", "left bumps", "skid 2", "skid 4", "skid 8", "skid 15",
	"side slope", "straight", "drive gently", "wheelspin", "brake gently", "brake locked", "coast",
	"slope braked", "slope rolling", "brake in turn", "turn in coasting", "turn in braking", "load",
	"launch", "engine braking", "ice open diffs", "ice locked diffs", "reverse"]
const ENGINE_RUNS := ["launch", "engine braking", "ice open diffs", "ice locked diffs", "reverse"]
const SURFACE_KINDS := ["corner", "brake", "pull away", "coast"]
const PULL_TO := 40.0 / 3.6        # m/s: the pull-away runs' target, the braking runs' start
var _surf := {}                    # kind -> {surface: result}
var _p7 := {}                      # this phase 7 run's counts
var _p7r := {}                     # phase 7 results kept for the next run's comparison
var _cfg_full: Resource            # the car's config ...
var _cfg_no_aero: Resource         # ... and a copy with no aero (phases 1-7)
var _p8 := {}                      # results the aid runs compare with
var _p9 := {}                      # results the manoeuvre runs compare with
var _p9_prev_beta := 0.0
const MANOEUVRES := ["lift off oversteer", "power oversteer", "four wheel drift", "catch countersteer", "catch hands off",
	"plain turn in", "scandinavian flick", "pendulum"]
var _ice := {}
var _shifts: Array = []            # [t, from gear, to gear, rpm before, rpm after]
var _last_gear := 1
var _real_drivetrain: Resource
var _turn := {}                    # "coasting" / "braking" -> yaw gain
var _v0 := Vector3.ZERO
var _rpm_before := 0.0
var _shift_from := 0
var _drive_before := 0.0
var _shift_in := -1.0
var _skid := {}                    # steering deg -> {a: lateral accel m/s², front / rear slip deg}
var _yaw0 := 0.0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	for kind in SURFACE_KINDS:
		_surf[kind] = {}
		for n in Lab.SURFACES:
			_phases.append("%s on %s" % [kind, n])
	_phases.append("split braking")
	_phases.append_array(["turn no handbrake", "handbrake turn", "handbrake and throttle",
		"handbrake and throttle without the rear clutch", "roll with bars", "roll without bars",
		"balance stiff front bar", "balance stiff rear bar", "sharp bumps two stage", "sharp bumps linear",
		"aero coast", "aero downforce 30", "aero downforce 150",
		"all aids corner", "all aids braking", "abs stop", "brake and steer", "brake and steer with abs",
		"launch with tc", "ice pull away with tc", "snow flick", "snow flick with esc",
		"full lock at 90", "full lock at 90 speed sensitive", "steering step", "steering step smoothing",
		"steering at 108", "steering at 108 damping", "slide hands off", "slide countersteer help",
		"settings panel", "telemetry record",
		"lift off oversteer", "power oversteer", "four wheel drift", "catch countersteer", "catch hands off",
		"plain turn in", "scandinavian flick", "pendulum"])
	var course := Node3D.new()
	root.add_child(course)
	Lab.build_course(course)
	car = (load(Lab.CAR_SCENE) as PackedScene).instantiate()
	root.add_child(car)                              # (ready on the first frame: the runs start then)


func _process(_dt: float) -> bool:
	if car == null or not ("wheels" in car) or car.wheels.size() != 4:   # a script didn't load: say so, don't hang
		fails += _check(false, "the v2 car loaded with its four wheels")
		_phase = _phases.size()
		return _done()
	return false


func _next() -> void:
	if car.drivetrain and _real_drivetrain:
		car.drivetrain.cfg = _real_drivetrain        # (after the open-diff run)
	for k in 4:
		car.wheels[k].surface_mu = 1.0
		car.wheels[k].cfg = car.config.front_suspension if k < 2 else car.config.rear_suspension
	car.inp.handbrake = 0.0
	_p7 = {"n": 0, "locked": 0, "rolling": 0}
	if _cfg_full == null:
		_cfg_full = car.config
		_cfg_no_aero = car.config.duplicate()        # (shallow: the same suspensions, tyres, engine)
		_cfg_no_aero.drag_coefficient = 0.0
		_cfg_no_aero.downforce_area = 0.0
	_phase += 1
	if _phase < _phases.size():
		car.config = _cfg_full if _phases[_phase].begins_with("aero") else _cfg_no_aero
		_aids(_phases[_phase])
	_t = 0.0
	_log.clear()
	if _phase >= _phases.size():
		return
	match _phases[_phase]:
		"static":
			car.place(Lab.PAD, 0.0)
		"bounce":
			car.place(Lab.PAD, 0.0)
		"drop":
			car.place(Lab.PAD, 0.0)
			car.global_position.y += 1.0
		"bumps":
			Lab.launch(car, Vector3(0.0, 0.0, Lab.BUMPS_Z + 10.0), 12.0)
		"left bumps":
			Lab.launch(car, Vector3(Lab.BUMP_LANE_X, 0.0, Lab.BUMPS_Z + 10.0), 12.0)
		"skid 2", "skid 4", "skid 8", "skid 15":
			Lab.launch(car, Lab.SKID, 15.0)
			car.inp.steer = float(_phases[_phase].split(" ")[1]) / car.config.steering.max_angle_deg
		"side slope":
			Lab.park_on_slope(car)
		"straight":
			Lab.launch(car, Lab.SKID, 20.0)
			_yaw0 = car.global_rotation.y
		"drive gently", "wheelspin":
			car.place(Lab.SKID, 0.0)
		"brake gently":
			Lab.launch(car, Lab.SKID, 25.0)
		"brake locked":
			Lab.launch(car, Lab.SKID, 100.0 / 3.6)
		"coast":
			Lab.launch(car, Lab.SKID, 20.0)
		"slope braked", "slope rolling":
			Lab.park_on_slope(car, PI / 2.0)
		"brake in turn":
			Lab.launch(car, Lab.SKID, 15.0)
			car.inp.steer = 8.0 / car.config.steering.max_angle_deg
		"turn in coasting", "turn in braking":
			Lab.launch(car, Lab.SKID, 20.0)
			car.inp.steer = 2.5 / car.config.steering.max_angle_deg     # ~7 m/s²: under the limit
		"launch", "reverse":
			car.place(Lab.SKID, 0.0)
			_shifts.clear()
			_last_gear = 1
		"engine braking":
			Lab.launch(car, Lab.SKID, 22.0)
			car.drivetrain.gear = 3
			car.drivetrain.omega_e = car.wheels[0].omega * car.drivetrain.ratio()
		"ice open diffs", "ice locked diffs":
			car.place(Lab.SKID, 0.0)
			car.drivetrain.cfg = _ice_drivetrain(name_open(_phases[_phase]))
			car.wheels[3].surface_mu = 0.1           # the right rear on ice
		"split braking":
			car.inp.steer = 0.0
			Lab.launch(car, Lab.split_start(), 60.0 / 3.6)
			_yaw0 = car.global_rotation.y
		"turn no handbrake", "handbrake turn":
			Lab.launch(car, Lab.SKID, 15.0)
		"handbrake and throttle", "handbrake and throttle without the rear clutch":
			car.inp.steer = 0.0
			Lab.launch(car, Lab.SKID, 10.0)
			car.drivetrain.omega_e = car.wheels[0].omega * car.drivetrain.ratio()   # (in first, the clutch in)
			if _phases[_phase].ends_with("clutch"):
				if _real_drivetrain == null:
					_real_drivetrain = car.drivetrain.cfg
				var d: Resource = _real_drivetrain.duplicate()
				d.handbrake_disconnects_rear = false
				car.drivetrain.cfg = d
		"roll with bars", "roll without bars":
			Lab.launch(car, Lab.SKID, 15.0)
			car.inp.steer = 4.0 / car.config.steering.max_angle_deg
			if _phases[_phase].ends_with("without bars"):
				_suspensions(func(f, r): f.anti_roll_rate = 0.0; r.anti_roll_rate = 0.0)
		"balance stiff front bar", "balance stiff rear bar":
			Lab.launch(car, Lab.SKID, 15.0)
			car.inp.steer = 8.0 / car.config.steering.max_angle_deg
			if _phases[_phase].ends_with("front bar"):
				_suspensions(func(f, _r): f.anti_roll_rate *= 3.0)
			else:
				_suspensions(func(_f, r): r.anti_roll_rate *= 3.0)
		"all aids corner":
			Lab.launch(car, Lab.SKID, 15.0)
			car.inp.steer = 4.0 / car.config.steering.max_angle_deg
		"all aids braking":
			car.inp.steer = 0.0
			Lab.launch(car, Lab.SKID, 25.0)
		"abs stop":
			car.inp.steer = 0.0
			Lab.launch(car, Lab.SKID, 100.0 / 3.6)
		"brake and steer", "brake and steer with abs":
			car.inp.steer = 0.0
			Lab.launch(car, Lab.SKID, 80.0 / 3.6)
		"launch with tc":
			car.inp.steer = 0.0
			car.place(Lab.SKID, 0.0)
		"ice pull away with tc":
			car.inp.steer = 0.0
			car.place(Lab.surface_start("ice"), 0.0)
		"snow flick", "snow flick with esc":
			car.inp.steer = 0.0
			Lab.launch(car, Lab.surface_start("snow"), 20.0)
		"full lock at 90", "full lock at 90 speed sensitive":
			car.inp.steer = 0.0
			Lab.launch(car, Lab.SKID, 25.0)
		"steering step", "steering step smoothing":
			car.inp.steer = 0.0
			Lab.launch(car, Lab.SKID, 10.0)
		"steering at 108", "steering at 108 damping":
			car.inp.steer = 0.0
			Lab.launch(car, Lab.SKID, 30.0)
		"slide hands off", "slide countersteer help":
			car.inp.steer = 0.0
			Lab.launch(car, Lab.SKID, 18.0)
			car.drivetrain.gear = 2
			car.drivetrain.omega_e = car.wheels[0].omega * car.drivetrain.ratio()
		"lift off oversteer", "power oversteer", "four wheel drift", "catch countersteer", "catch hands off",\
				"plain turn in", "scandinavian flick", "pendulum":
			car.inp.steer = 0.0
			var v0: float = {"power oversteer": 13.0, "four wheel drift": 16.0, "catch countersteer": 16.0, "catch hands off": 16.0}.get(_phases[_phase], 20.0)
			Lab.launch(car, Lab.SKID, v0)
			car.drivetrain.gear = 1 if v0 < 15.0 else 2
			car.drivetrain.omega_e = car.wheels[0].omega * car.drivetrain.ratio()
			car.drivetrain.clutch = 1.0
			if _phases[_phase] == "four wheel drift":       # (a driver holds second through the slide)
				if _real_drivetrain == null:
					_real_drivetrain = car.drivetrain.cfg
				var held: Resource = _real_drivetrain.duplicate()
				held.auto_shift = false
				car.drivetrain.cfg = held
			_p9_prev_beta = 0.0
		"settings panel":
			car.place(Lab.PAD, 0.0)
			_p8["panel"] = (load("res://scripts/ui/settings_panel.gd") as GDScript).new()
			root.add_child(_p8.panel)
		"telemetry record":
			car.inp.steer = 0.0
			Lab.launch(car, Lab.SKID, 15.0)
			car.telemetry.start_recording()
		"aero coast":
			car.inp.steer = 0.0
			Lab.launch(car, Lab.SKID, 150.0 / 3.6)
		"aero downforce 30", "aero downforce 150":
			car.inp.steer = 0.0
			Lab.launch(car, Lab.SKID, float(_phases[_phase].split(" ")[2]) / 3.6)
		"sharp bumps two stage", "sharp bumps linear":
			car.inp.steer = 0.0
			Lab.launch(car, Vector3(0.0, 0.0, Lab.BUMPS_Z + 10.0), 15.0)
			if _phases[_phase].ends_with("linear"):
				_suspensions(func(f, r):
					for c in [f, r]:
						c.high_speed_bump = c.bump_damping
						c.high_speed_rebound = c.rebound_damping)
	var on: Array = _phases[_phase].split(" on ")
	if on.size() == 2:
		car.inp.steer = 0.0
		match on[0]:
			"corner":
				Lab.launch(car, Lab.surface_start(on[1]), 15.0)
			"brake":
				Lab.launch(car, Lab.surface_start(on[1]), PULL_TO)
			"pull away":
				car.place(Lab.surface_start(on[1]), 0.0)
			"coast":
				Lab.launch(car, Lab.surface_start(on[1]), 20.0)
	_v0 = car.global_position
	if car.drivetrain and not (_phases[_phase] in ENGINE_RUNS or _phases[_phase].begins_with("pull away")
			or _phases[_phase].begins_with("handbrake and throttle") or _phases[_phase].begins_with("slide ")
			or _phases[_phase] in MANOEUVRES
			or _phases[_phase] in ["launch with tc", "ice pull away with tc"]):
		car.drivetrain.gear = 0                      # the tyres and brakes alone
	_inputs(_phases[_phase])


## The pedals and the test torque for this run (set again every tick).
func _inputs(name: String) -> void:
	for w in car.wheels:
		w.drive_torque = {"drive gently": 400.0, "wheelspin": 2500.0}.get(name, 0.0)
	car.inp.brake = {"brake gently": 0.3, "brake locked": 1.0, "slope braked": 1.0, "turn in braking": 0.25, "reverse": 1.0,
		"split braking": 1.0}.get(name, 0.0)
	car.inp.throttle = 1.0 if name in ["launch", "ice open diffs", "ice locked diffs"] else 0.0
	if name.begins_with("brake on"):
		car.inp.brake = 1.0
	elif name.begins_with("pull away"):
		car.inp.throttle = 1.0
	elif name.begins_with("corner on"):
		car.inp.steer = minf(_t / 1.5, 1.0) * 15.0 / car.config.steering.max_angle_deg   # wound on over 1.5 s
	elif name == "split braking":
		car.inp.steer = 0.0
	elif name in ["turn no handbrake", "handbrake turn"]:
		car.inp.steer = clampf(_t / 0.25, 0.0, 1.0) * 0.6
		car.inp.handbrake = 1.0 if name == "handbrake turn" and _t < 0.8 else 0.0
	elif name.begins_with("handbrake and throttle"):
		car.inp.throttle = 1.0
		car.inp.handbrake = 1.0
	elif name in MANOEUVRES:
		_manoeuvre(name)
	elif name == "all aids braking":
		car.inp.brake = 0.3
	elif name == "abs stop":
		car.inp.brake = 1.0
	elif name.begins_with("brake and steer"):
		car.inp.brake = 1.0
		car.inp.steer = 0.5
	elif name in ["launch with tc", "ice pull away with tc"]:
		car.inp.throttle = 1.0
	elif name.begins_with("snow flick"):
		car.inp.steer = 0.5 if _t < 0.6 else (-0.6 if _t < 1.4 else 0.0)
	elif name.begins_with("full lock at 90") or name.begins_with("steering step") or name.begins_with("steering at 108"):
		car.inp.steer = 1.0
	elif name.begins_with("slide "):
		car.inp.steer = clampf(_t / 0.25, 0.0, 1.0) * 0.6 if _t < 0.8 else 0.0
		car.inp.handbrake = 1.0 if _t < 0.8 else 0.0
		car.inp.throttle = 0.0 if _t < 0.8 else 0.5     # let go of the wheel, power on
	if name == "brake in turn":
		car.inp.brake = 0.4 if _t >= 4.0 else 0.0


func _physics_process(dt: float) -> bool:
	if _phase < 0:
		_next()
		return false
	if _phase >= _phases.size():
		return _done()
	_t += dt
	var name: String = _phases[_phase]
	if name.begins_with("skid") or (name == "brake in turn" and _t < 4.0):
		Lab.tow(car, 15.0)
	elif name == "straight":
		Lab.tow(car, 20.0)
	_inputs(name)
	if name.begins_with("roll ") or name.begins_with("balance ") or name == "all aids corner":
		Lab.tow(car, 15.0)
	elif name.begins_with("full lock at 90"):
		Lab.tow(car, 25.0)
	elif name.begins_with("aero downforce"):
		Lab.tow(car, float(name.split(" ")[2]) / 3.6)
		if _t > 1.0:                                 # settled: the tyres' loads, front and rear
			var lf: float = car.wheels[0].load + car.wheels[1].load
			var lr: float = car.wheels[2].load + car.wheels[3].load
			_p7.n += 1
			_p7.front = _p7.get("front", 0.0) + lf
			_p7.rear = _p7.get("rear", 0.0) + lr
	var rears_locked: bool = absf(car.wheels[2].omega) < 0.5 and absf(car.wheels[3].omega) < 0.5
	if (name == "handbrake turn" and _t > 0.3 and _t < 0.75) or (name.begins_with("handbrake and throttle") and _t > 0.3):
		_p7.n += 1
		_p7.locked += 1 if rears_locked else 0
		var front_rim: float = (car.wheels[0].omega + car.wheels[1].omega) * 0.5 * car.config.tyre_radius
		_p7.rolling += 1 if front_rim > 0.5 * car.speed else 0
		_p7.driving = _p7.get("driving", 0) + (1 if front_rim > car.speed else 0)
	if name == "bounce" and _t > 2.0 and _y0 == 0.0:
		_y0 = car.global_position.y                  # settled: lift it 5 cm and let go
		_lift_t = _t
		car.global_position.y += 0.05
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		_log.clear()
	var xf := car.global_transform
	var fwd := -xf.basis.z
	var max_c := 0.0
	for w in car.wheels:
		max_c = maxf(max_c, w.compression)
	var w: Array = car.wheels
	_log.append([_t, car.global_position.y, rad_to_deg(asin(clampf(fwd.y, -1, 1))), rad_to_deg(asin(clampf(xf.basis.x.y, -1, 1))),
		car.grounded, max_c, _clearance(),
		car.linear_velocity.length(), rad_to_deg(car.angular_velocity.y),                       # 7, 8
		(w[0].slip_angle_deg() + w[1].slip_angle_deg()) * 0.5, (w[2].slip_angle_deg() + w[3].slip_angle_deg()) * 0.5,  # 9, 10
		car.global_position, car.linear_velocity.dot(xf.basis.x),                                 # 11, 12
		car.linear_velocity.dot(fwd), _max_slip(), _all_locked(), car.accel, car.linear_velocity,  # 13-17
		(car.wheel_angles[0] + car.wheel_angles[1]) * 0.5,                                          # 18
		car.drivetrain.rpm() if car.drivetrain else 0.0,                                            # 19
		car.drivetrain.clutch_torque if car.drivetrain else 0.0,                                    # 20
		_any_locked(), _beta(), _least_slip()])                                                     # 21, 22, 23
	var length := {"static": 3.0, "bounce": 5.5, "drop": 4.5, "bumps": 4.0, "left bumps": 4.0,
		"skid 2": 5.0, "skid 4": 5.0, "skid 8": 5.0, "skid 15": 5.0, "side slope": 5.0, "straight": 3.0,
		"drive gently": 3.0, "wheelspin": 2.0, "brake gently": 2.0, "brake locked": 6.0, "coast": 3.0,
		"slope braked": 4.0, "slope rolling": 2.0, "brake in turn": 5.5, "turn in coasting": 1.4, "turn in braking": 1.4,
		"load": 0.1, "launch": 9.0, "engine braking": 1.5, "ice open diffs": 2.0, "ice locked diffs": 2.0, "reverse": 2.5}
	if name == "launch":
		if car.drivetrain.shifting() and _shift_from == 0:
			_shift_from = car.gear                   # the cut starts: the revs before, and the wheels' speed
			_rpm_before = car.drivetrain.rpm()
			_drive_before = car.drivetrain.driveline_speed(car.wheels)
		elif not car.drivetrain.shifting() and _shift_from != 0 and car.gear != _shift_from:
			if _shift_in < 0.0:
				_shift_in = _t
			elif _t - _shift_in > 0.15:              # in gear and the clutch has matched the revs
				_shifts.append([_shift_in, _shift_from, car.gear, _rpm_before, car.drivetrain.rpm(),
					_drive_before, car.drivetrain.driveline_speed(car.wheels)])
				_shift_from = 0
				_shift_in = -1.0
	var on: Array = name.split(" on ")
	if on.size() == 2:
		var stop := false
		match on[0]:
			"corner":
				stop = _t >= 3.0
			"brake":
				stop = (_t > 0.5 and car.speed < 0.2) or _t >= 16.0
			"pull away":
				stop = car.speed >= PULL_TO or _t >= 16.0
			"coast":
				stop = _t >= 3.0
		if stop:
			_judge_surface(on[0], on[1])
			_next()
		return false
	if name == "split braking":
		length[name] = 0.75
	if (name == "abs stop" and (car.speed < 0.3 and _t > 0.5 or _t > 8.0)) or (name == "ice pull away with tc" and (car.speed >= PULL_TO or _t > 16.0)):
		length[name] = _t                            # (these end when stopped / at 40 km/h)
	elif name in ["abs stop", "ice pull away with tc"]:
		length[name] = INF
	for run in [["turn no handbrake", 2.0], ["handbrake turn", 2.0], ["handbrake and throttle", 1.5],
			["handbrake and throttle without the rear clutch", 1.5], ["roll with bars", 4.0], ["roll without bars", 4.0],
			["balance stiff front bar", 5.0], ["balance stiff rear bar", 5.0], ["sharp bumps two stage", 3.0],
			["sharp bumps linear", 3.0], ["aero coast", 2.5], ["aero downforce 30", 2.5], ["aero downforce 150", 2.5],
			["all aids corner", 5.0], ["all aids braking", 2.0], ["brake and steer", 2.0], ["brake and steer with abs", 2.0],
			["launch with tc", 9.0], ["snow flick", 3.0], ["snow flick with esc", 3.0], ["full lock at 90", 3.0],
			["full lock at 90 speed sensitive", 3.0], ["steering step", 1.0], ["steering step smoothing", 1.0],
			["steering at 108", 1.0], ["steering at 108 damping", 1.0], ["slide hands off", 3.0], ["slide countersteer help", 3.0],
			["settings panel", 0.2], ["telemetry record", 1.0], ["lift off oversteer", 3.5], ["power oversteer", 3.0],
			["four wheel drift", 4.0], ["catch countersteer", 3.5], ["catch hands off", 3.5], ["plain turn in", 2.5],
			["scandinavian flick", 2.5], ["pendulum", 5.0]]:
		length[run[0]] = run[1]
	if name.begins_with("skid") and _t >= length[name]:
		_judge_skid(int(name.split(" ")[1]))
		_next()
	elif _t >= length[name]:
		call(StringName("_judge_" + name.replace(" ", "_")))
		_next()
	return false


## How far the lowest corner of the body box is above the ground (y = 0) (m).
func _clearance() -> float:
	var cfg = car.config
	var lo := INF
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var p: Vector3 = car.global_transform * (cfg.body_center + cfg.body_size * 0.5 * Vector3(sx, sy, sz))
				lo = minf(lo, p.y)
	return lo


func _judge_static() -> void:
	var cfg = car.config
	var loads: Array = cfg.static_loads(9.8)
	var want_f: float = Suspension.static_compression(cfg.front_suspension, loads[0])
	var want_r: float = Suspension.static_compression(cfg.rear_suspension, loads[1])
	var c: Array = car.comp
	var err := maxf(maxf(absf(c[0] - want_f), absf(c[1] - want_f)), maxf(absf(c[2] - want_r), absf(c[3] - want_r)))
	var last: Array = _log[_log.size() - 1]
	var height_err: float = absf(last[1] - car.ride_height())
	fails += _check(err < 0.004, "static: each corner squashed by its share of the weight (front %.1f / rear %.1f mm, want %.1f / %.1f, off by %.1f mm at most)" % [
		(c[0] + c[1]) * 500.0, (c[2] + c[3]) * 500.0, want_f * 1000.0, want_r * 1000.0, err * 1000.0])
	fails += _check(height_err < 0.005, "static: at its ride height (%.3f m, want %.3f)" % [last[1], car.ride_height()])
	fails += _check(absf(last[2]) < 0.3 and absf(last[3]) < 0.1, "static: level (pitch %+.2f, roll %+.2f deg)" % [last[2], last[3]])
	fails += _check(car.linear_velocity.length() < 0.01 and car.grounded == 4, "static: still, on all four (%.3f m/s)" % car.linear_velocity.length())


func _judge_bounce() -> void:
	var cfg = car.config
	var loads: Array = cfg.static_loads(9.8)
	var f_front: float = Suspension.ride_frequency(cfg.front_suspension, loads[0] / 9.8)
	var f_rear: float = Suspension.ride_frequency(cfg.rear_suspension, loads[1] / 9.8)
	# swings through the settled height (counted once it's more than 1.5 mm past it
	# the other way: not the last sub-millimetre wobble), and what's left later
	var crossings: Array = []
	var side := 0.0
	for e in _log:
		var dy: float = e[1] - _y0
		if absf(dy) > 0.0015 and signf(dy) != side:
			if side != 0.0:
				crossings.append(e[0])
			side = signf(dy)
	var hz := 0.0
	if crossings.size() >= 2:
		hz = (crossings.size() - 1) / 2.0 / (crossings[crossings.size() - 1] - crossings[0])
	var after2 := 0.0
	var after3 := 0.0
	for e in _log:
		if e[0] - _lift_t > 2.0:
			after2 = maxf(after2, absf(e[1] - _y0))
		if e[0] - _lift_t > 3.0:
			after3 = maxf(after3, absf(e[1] - _y0))
	fails += _check(hz > 1.0 and hz < 1.8, "bounce: %.2f Hz (springs alone: front %.2f, rear %.2f Hz; damping slows it a little; %d swings)" % [
		hz, f_front, f_rear, crossings.size()])
	fails += _check(after2 < 0.006 and after3 < 0.002, "bounce: settles (from 50 mm: %.1f mm after 2 s, %.1f mm after 3 s)" % [after2 * 1000.0, after3 * 1000.0])


func _judge_drop() -> void:
	var landed := -1.0
	var unsettled := 0.0                             # the last time it was more than 5 mm off its ride height
	var hops := 0.0                                  # time with no wheel down after first touching
	var min_clear := INF
	var max_c := 0.0
	var dt := 1.0 / 120.0
	for e in _log:
		if landed < 0.0 and e[4] > 0:
			landed = e[0]
		if landed >= 0.0:
			if e[4] == 0:
				hops += dt
			min_clear = minf(min_clear, e[6])
			max_c = maxf(max_c, e[5])
			if absf(e[1] - car.ride_height()) > 0.005:
				unsettled = e[0]
	var last: Array = _log[_log.size() - 1]
	var travel: float = car.config.front_suspension.travel
	fails += _check(min_clear > 0.03, "drop 1 m: the body never touches the ground (lowest %.0f mm above it; deepest squash %.0f of %.0f mm travel)" % [
		min_clear * 1000.0, max_c * 1000.0, travel * 1000.0])
	fails += _check(hops < 0.05, "drop 1 m: no bounce back into the air (%.2f s with no wheel down after landing)" % hops)
	fails += _check(absf(last[1] - car.ride_height()) < 0.01 and car.linear_velocity.length() < 0.02,
		"drop 1 m: settled at its ride height (within 5 mm %.1f s after landing)" % (unsettled - landed))


func _judge_bumps() -> void:
	var pitch := 0.0
	var roll := 0.0
	for e in _log:
		pitch = maxf(pitch, absf(e[2]))
		roll = maxf(roll, absf(e[3]))
	fails += _check(pitch > 0.4 and roll < 0.3, "bumps: they pitch it (up to %.1f deg) without rolling it (%.2f deg)" % [pitch, roll])
	fails += _check(car.global_transform.basis.y.y > 0.99 and _log[_log.size() - 1][4] == 4, "bumps: still upright, all four down after")


func _judge_left_bumps() -> void:
	var roll := 0.0
	for e in _log:
		roll = maxf(roll, absf(e[3]))
	fails += _check(roll > 0.4, "left-side bumps: they roll it (up to %.1f deg)" % roll)
	fails += _check(car.global_transform.basis.y.y > 0.99, "left-side bumps: still upright")


## Steady state on the skid pad (the last 1.5 s): cornering force, slip angles, how steady.
func _judge_skid(deg: int) -> void:
	var a := 0.0
	var sf := 0.0
	var sr := 0.0
	var n := 0
	var yaw: Array = []
	for e in _log:
		if e[0] > _log[_log.size() - 1][0] - 1.5:
			a += e[7] * deg_to_rad(absf(e[8]))      # v x yaw rate: the cornering acceleration
			sf += absf(e[9])
			sr += absf(e[10])
			yaw.append(absf(e[8]))
			n += 1
	a /= n
	sf /= n
	sr /= n
	var spread: float = yaw.max() - yaw.min()
	_skid[deg] = {"a": a, "front": sf, "rear": sr}
	var base: float = car.config.rear_axle - car.config.front_axle
	var geo := 15.0 * 15.0 * deg_to_rad(deg) / base     # what the geometry alone would give (no slip)
	var mu_g: float = car.config.front_tire.lateral_mu * 9.8
	print("[physics]      skid pad, wheel at %2d deg: %.2f m/s² (%.2f g; geometry alone %.1f), slip front %.2f / rear %.2f deg, yaw rate steady within %.2f deg/s" % [
		deg, a, a / 9.8, geo, sf, sr, spread])
	if deg <= 4:
		fails += _check(spread < 0.2 and car.grounded == 4, "skid pad %d deg: a steady circle" % deg)
	else:                                            # at the limit it hunts, like a real car: it must hold on
		fails += _check(yaw.max() < 60.0 and car.grounded == 4 and car.global_transform.basis.y.y > 0.95,
			"skid pad %d deg: at the limit it holds on (no spin, no lift: yaw rate %.0f-%.0f deg/s)" % [deg, yaw.min(), yaw.max()])
	if deg <= 4:
		fails += _check(absf(a - minf(geo, mu_g)) < geo * 0.15, "skid pad %d deg: below the limit the car goes where it's steered (%.2f vs %.2f m/s²)" % [deg, a, geo])
	if deg == 15:
		# rises with the steering to the limit; past the fronts' peak slip it tops out (and
		# fades a little: steering past the peak scrubs)
		var order: bool = _skid[2].a < _skid[4].a and _skid[4].a < _skid[8].a and _skid[15].a > 0.85 * _skid[8].a
		fails += _check(order, "skid pad: more steering, more cornering force, until it tops out (%.1f, %.1f, %.1f, %.1f m/s²)" % [
			_skid[2].a, _skid[4].a, _skid[8].a, _skid[15].a])
		fails += _check(a > 0.75 * mu_g and a < 1.05 * mu_g, "skid pad 15 deg: at the tyres' grip and never past it (%.2f m/s², mu g = %.2f)" % [a, mu_g])


func _judge_side_slope() -> void:
	var start: Vector3 = Vector3.ZERO
	for e in _log:
		if e[0] >= 2.5:                              # settled on its springs (the body leans downhill first)
			start = e[11]
			break
	var last: Array = _log[_log.size() - 1]
	var across: Vector3 = car.global_transform.basis.x     # down the slope (phase 2 has no brakes: along the car it could roll)
	var drift: float = absf(((last[11] as Vector3) - start).dot(across))
	fails += _check(drift < 0.003 and absf(last[12]) < 0.001,
		"side slope %.0f deg, no brakes: the tyres hold it (%.1f mm in 2.5 s, %.2f mm/s at the end)" % [Lab.SLOPE_DEG, drift * 1000.0, absf(last[12]) * 1000.0])
	fails += _check(car.grounded == 4 and car.global_transform.basis.y.dot(Vector3.UP) > 0.95, "side slope: on all four, upright")


func _judge_straight() -> void:
	var yaw := 0.0
	var lat := 0.0
	for e in _log:
		if e[0] > 0.5:
			yaw = maxf(yaw, absf(e[8]))
			lat = maxf(lat, absf(e[12]))
	var turned := rad_to_deg(absf(wrapf(car.global_rotation.y - _yaw0, -PI, PI)))
	fails += _check(yaw < 0.5 and lat < 0.05 and turned < 0.5,
		"straight at 20 m/s: runs straight (yaw rate %.2f deg/s at most, %.3f m/s sideways, %.2f deg off its heading)" % [yaw, lat, turned])


func _max_slip() -> float:
	var m := 0.0
	for w in car.wheels:
		m = m if absf(m) > absf(w.slip_long) else w.slip_long
	return m


## The body's slip angle (deg): the angle between where the car points and where it's
## going (+ = going to the right of its nose: the tail out to the left, as in a left-hand slide).
func _beta() -> float:
	var xf := car.global_transform
	var v := car.linear_velocity
	return rad_to_deg(atan2(v.dot(xf.basis.x), maxf(absf(v.dot(-xf.basis.z)), 0.5)))


## The smallest slip angle of the four tyres (deg, its size): all four past
## their peak when this is.
func _least_slip() -> float:
	var m := INF
	for w in car.wheels:
		m = minf(m, absf(w.slip_angle_deg()))
	return m


## The scripted drivers for the phase 9 manoeuvres (gravel, the car's own set-up, no aids).
func _manoeuvre(name: String) -> void:
	var b := _beta()
	var lock: float = car.config.steering.max_angle_deg
	match name:
		"lift off oversteer":                        # a left-hander near the limit on the throttle, then lift
			car.inp.steer = -0.3
			car.inp.throttle = 0.55 if _t < 2.5 else 0.0
		"power oversteer":                           # a left-hander on a whiff of throttle, then flat out
			car.inp.steer = -0.4
			car.inp.throttle = 0.25 if _t < 2.0 else 1.0
		"four wheel drift":                          # in with a flick and the handbrake, then hold the slide
			var rate := (b - _p9_prev_beta) * 120.0
			_p9_prev_beta = b
			if _t < 0.4:
				car.inp.steer = 0.4
			elif _t < 0.9:
				car.inp.steer = -1.0
				car.inp.handbrake = 1.0 if _t < 0.7 else 0.0
				car.inp.throttle = 0.6
			else:                                    # wheels toward where it's going, more lock if it slides too far, damped
				car.inp.handbrake = 0.0
				car.inp.steer = clampf((b + 1.0 * (b - 20.0) + 0.3 * rate) / lock, -1.0, 1.0)
				car.inp.throttle = 0.8
		"catch countersteer", "catch hands off":     # a handbrake flick into a left-hander, then: catch it, or let go
			if _t < 0.8:
				car.inp.steer = -0.6 * clampf(_t / 0.25, 0.0, 1.0)
				car.inp.handbrake = 1.0 if _t < 0.7 else 0.0
			else:
				car.inp.handbrake = 0.0
				car.inp.steer = clampf(b / lock, -1.0, 1.0) if name == "catch countersteer" else 0.0
				car.inp.throttle = 0.5
		"plain turn in", "scandinavian flick":       # lift, (flick right,) turn in left with a dab of brake, then power
			if _t < 0.5:
				car.inp.steer = 0.3 if name == "scandinavian flick" else 0.0
				car.inp.throttle = 0.0
			elif _t < 0.85:
				car.inp.steer = -0.6
				car.inp.brake = 0.35
				car.inp.throttle = 0.0
			else:
				car.inp.steer = -0.6
				car.inp.brake = 0.0
				car.inp.throttle = 0.5
		"pendulum":                                  # a driver steering slide to slide: left, right, left, 1.5 s each
			var target := 20.0 if fmod(_t, 3.0) < 1.5 else -20.0
			var swing := (b - _p9_prev_beta) * 120.0
			_p9_prev_beta = b
			car.inp.steer = clampf((b + (b - target) + 0.3 * swing) / lock, -1.0, 1.0)
			car.inp.throttle = 0.7


## The average of a logged column between two times.
func _avg(col: int, t0: float, t1: float) -> float:
	var sum := 0.0
	var n := 0
	for e in _log:
		if e[0] >= t0 and e[0] <= t1:
			sum += e[col]
			n += 1
	return sum / maxf(n, 1)


## The biggest size of a logged column between two times.
func _peak_in(col: int, t0: float, t1: float) -> float:
	var m := 0.0
	for e in _log:
		if e[0] >= t0 and e[0] <= t1:
			m = maxf(m, absf(e[col]))
	return m


func _judge_lift_off_oversteer() -> void:
	var rear0 := _avg(10, 1.8, 2.5)
	var rear1 := _peak_in(10, 2.6, 3.5)
	var yaw0 := _avg(8, 1.8, 2.5)
	var yaw1 := _peak_in(8, 2.6, 3.5)
	fails += _check(rear1 > 1.5 * rear0 and yaw1 > 1.15 * yaw0 and _peak(22) < 45.0,
		"lift-off oversteer: lifting mid-corner at 75 km/h, the rear slip goes %.1f -> %.1f deg and the car tightens, %.0f -> %.0f deg/s, without spinning" % [
			rear0, rear1, yaw0, yaw1])


func _judge_power_oversteer() -> void:
	var b0 := _avg(22, 1.5, 2.0)
	var b1 := _avg(22, 2.9, 3.0)
	fails += _check(b0 < 3.0 and b1 > 10.0,
		"power oversteer: flat out mid-corner, the tail swings wide: body slip %.0f -> %.0f deg in a second (rear tyres %.0f -> %.0f deg)" % [
			b0, b1, _avg(10, 1.5, 2.0), _avg(10, 2.9, 3.0)])


func _judge_four_wheel_drift() -> void:
	var held := 0.0
	var best := 0.0
	for e in _log:
		if e[0] > 1.5 and e[23] > 7.0:
			held += 1.0 / 120.0
			best = maxf(best, held)
		elif e[0] > 1.5:
			held = 0.0
	fails += _check(best >= 1.5 and _peak_in(22, 0.9, 4.0) < 45.0,
		"four-wheel drift: a driver holding the slide keeps all four tyres past their peak for %.1f s (front %.0f / rear %.0f deg, body %.0f deg, %.0f km/h), without spinning" % [
			best, _avg(9, 2.5, 4.0), _avg(10, 2.5, 4.0), _avg(22, 2.5, 4.0), _avg(7, 2.5, 4.0) * 3.6])


## When the car was straight again after the driver let go at 0.8 s (s; INF: never).
func _straight_again() -> float:
	for e in _log:
		if e[0] > 1.0 and absf(e[8]) < 10.0 and absf(e[22]) < 5.0:
			return e[0] - 0.8
	return INF


func _judge_catch_countersteer() -> void:
	_p9["catch"] = {"t": _straight_again(), "yaw": _turned()}


func _judge_catch_hands_off() -> void:
	var c: Dictionary = _p9.catch
	var yaw := _turned()
	fails += _check(c.t < 2.0 and c.yaw < 100.0 and yaw > 150.0,
		"countersteer catch: after a handbrake flick at 58 km/h, steering where it's going straightens it %.1f s after letting go (turned %.0f deg); hands off it spins (%.0f deg)" % [
			c.t, c.yaw, yaw])


func _judge_plain_turn_in() -> void:
	_p9["plain"] = {"yaw": _turned(), "rear": _peak_in(10, 0.5, 2.5)}


func _judge_scandinavian_flick() -> void:
	var p: Dictionary = _p9.plain
	var yaw := _turned()
	var rear := _peak_in(10, 0.5, 2.5)
	fails += _check(yaw > p.yaw and rear > 2.0 * p.rear,
		"Scandinavian flick at 72 km/h: a flick away first rotates it %.0f deg in 2.5 s with the tail out to %.0f deg (turning in plain: %.0f deg, %.0f deg)" % [
			yaw, rear, p.yaw, p.rear])


func _judge_pendulum() -> void:
	var swings := 0
	var side := 0.0
	var lo := 0.0
	var hi := 0.0
	for e in _log:
		var b: float = e[22]
		lo = minf(lo, b)
		hi = maxf(hi, b)
		if absf(b) > 6.0 and signf(b) != side:
			if side != 0.0:
				swings += 1
			side = signf(b)
	fails += _check(swings >= 2 and maxf(-lo, hi) < 45.0,
		"pendulum: slide to slide, left, right, left at 72 km/h: %d swings, the body angle from %+.0f to %+.0f deg, never spinning" % [swings, lo, hi])


## Any wheel locked while the car's moving.
func _any_locked() -> bool:
	if absf(car.speed) < 2.0:
		return false
	for w in car.wheels:
		if absf(w.omega) < 1.0:
			return true
	return false


func _all_locked() -> bool:
	for w in car.wheels:
		if absf(w.omega) > 0.01:
			return false
	return true


## The car's mass with the four wheels' spin added (the drive spins them up too).
func _m_eff() -> float:
	var r: float = car.config.tyre_radius
	return car.mass + 4.0 * car.config.wheel_inertia / (r * r)


## Mean acceleration along the car between t0 and t1 (from the logged speed).
func _accel(t0: float, t1: float) -> float:
	var a: Array = []
	var b: Array = []
	for e in _log:
		if a.is_empty() and e[0] >= t0:
			a = e
		if e[0] <= t1:
			b = e
	return (b[13] - a[13]) / (b[0] - a[0])


func _judge_drive_gently() -> void:
	var r: float = car.config.tyre_radius
	var rr: float = car.config.front_tire.rolling_resistance
	var want: float = (4.0 * 400.0 / r - rr * car.mass * 9.8) / _m_eff()
	var got := _accel(0.5, 3.0)
	var slip := 0.0
	for e in _log:
		slip = maxf(slip, absf(e[14]))
	fails += _check(absf(got - want) < want * 0.05 and slip < 0.06,
		"400 N m on each wheel: %.2f m/s² (torque / mass with the wheels' inertia, minus rolling resistance: %.2f), slip ratio %.1f %% at most" % [got, want, slip * 100.0])


func _judge_wheelspin() -> void:
	var got := _accel(0.5, 2.0)
	var last: Array = _log[_log.size() - 1]
	var mu_g: float = car.config.front_tire.longitudinal_mu * 9.8
	fails += _check(last[14] > 0.3 and got > 0.6 * mu_g and got < 1.0 * mu_g,
		"2,500 N m on each wheel (more than the grip): wheelspin (slip ratio %.0f %%), %.2f m/s² (what the tyres can take: under mu g = %.1f)" % [last[14] * 100.0, got, mu_g])


func _judge_brake_gently() -> void:
	var r: float = car.config.tyre_radius
	var rr: float = car.config.front_tire.rolling_resistance
	var want: float = -(car.config.brake_torque * 0.3 / r + rr * car.mass * 9.8) / _m_eff()
	var got := _accel(0.3, 2.0)
	var slip := 0.0
	for e in _log:
		slip = maxf(slip, absf(e[14]))
	_p8["brake gently"] = got
	fails += _check(absf(got - want) < absf(want) * 0.07 and slip < 0.1,
		"brakes at 30 %%: %.2f m/s² (the brakes' torque / mass with the wheels: %.2f), no locking (slip %.1f %% at most)" % [got, want, slip * 100.0])


func _judge_brake_locked() -> void:
	var stop_t := -1.0
	var locked := 0
	var moving := 0
	for e in _log:
		if e[13] > 2.0:
			moving += 1
			if e[15]:
				locked += 1
		if stop_t < 0.0 and e[13] < 0.05:
			stop_t = e[0]
	var dist: float = (car.global_position - _v0).length()
	var v0 := 100.0 / 3.6
	var mean_decel := v0 / stop_t if stop_t > 0.0 else 0.0
	var mu_g: float = car.config.front_tire.longitudinal_mu * 9.8
	# (each wheel locks once its brake has beaten its grip and stopped its spin: the
	# rears, whose brakes only just beat their grip, take a moment longer)
	_p8["locked stop"] = dist
	fails += _check(stop_t > 0.0 and locked > moving * 0.75,
		"full brakes from 100 km/h: all four wheels lock (for %d %% of the stop) and it stops, %.1f m in %.1f s" % [100 * locked / maxi(moving, 1), dist, stop_t])
	var kept := -TireModel.longitudinal_curve(car.config.front_tire, -1.0)   # a locked tyre's share of its grip
	fails += _check(mean_decel > (kept - 0.08) * mu_g and mean_decel < (kept + 0.06) * mu_g,
		"full brakes: it slides on locked tyres, %.2f m/s² (%.2f g; a locked tyre keeps %.0f %% of its grip)" % [
			mean_decel, mean_decel / 9.8, kept * 100.0])


func _judge_coast() -> void:
	var rr: float = car.config.front_tire.rolling_resistance
	var want: float = -rr * car.mass * 9.8 / _m_eff()
	var got := _accel(0.5, 3.0)
	fails += _check(absf(got - want) < absf(want) * 0.15, "coasting at 20 m/s: rolling resistance slows it %.3f m/s² (want %.3f)" % [got, want])


func _judge_slope_braked() -> void:
	var start: Vector3 = Vector3.ZERO
	for e in _log:
		if e[0] >= 1.5:
			start = e[11]
			break
	var moved: float = (car.global_position - start).length()
	fails += _check(moved < 0.003 and absf(car.linear_velocity.length()) < 0.002,
		"nose up a %.0f deg slope, brakes on: it holds (%.1f mm in 2.5 s)" % [Lab.SLOPE_DEG, moved * 1000.0])


func _judge_slope_rolling() -> void:
	var rr: float = car.config.front_tire.rolling_resistance
	var th := deg_to_rad(Lab.SLOPE_DEG)
	var want: float = -(car.mass * 9.8 * (sin(th) - rr * cos(th))) / _m_eff()
	var got := _accel(0.3, 1.8)
	fails += _check(absf(got - want) < absf(want) * 0.1, "brakes off: it rolls back down, %.2f m/s² (gravity minus rolling resistance: %.2f)" % [got, want])


## Acceleration across and along the car's path (m/s², horizontal) from a log row.
func _lat_long(e: Array) -> Vector2:
	var a: Vector3 = e[16]
	var v: Vector3 = e[17]
	a.y = 0.0
	v.y = 0.0
	var d := v.normalized()
	var along := a.dot(d)
	return Vector2((a - d * along).length(), along)


func _judge_brake_in_turn() -> void:
	var before := 0.0
	var nb := 0
	var during := 0.0
	var nd := 0
	var most := 0.0
	for e in _log:
		var al := _lat_long(e)
		if e[0] > 3.0 and e[0] < 4.0:
			before += al.x
			nb += 1
		if e[0] > 4.3 and e[0] < 5.3:
			during += al.x
			nd += 1
		if e[0] > 3.0:
			most = maxf(most, al.length())
	before /= nb
	during /= nd
	var mu_g: float = car.config.front_tire.lateral_mu * 9.8
	fails += _check(during < 0.85 * before, "braking at the cornering limit: it loses cornering grip (%.1f m/s² across before, %.1f braking)" % [before, during])
	fails += _check(most < 1.05 * mu_g, "braking at the limit: braking and cornering together never pass the grip (%.1f m/s² at most, mu g = %.1f)" % [most, mu_g])


## How much the car rotates for its steering, entering a 2.5 degree turn at 20 m/s:
## yaw rate / the yaw rate the geometry would give at that speed (1 = neutral).
func _yaw_gain() -> float:
	var base: float = car.config.rear_axle - car.config.front_axle
	var g := 0.0
	var n := 0
	for e in _log:
		if e[0] > 0.5 and e[0] < 1.3 and absf(e[18]) > 0.01:
			g += deg_to_rad(absf(e[8])) / (e[13] * absf(e[18]) / base)
			n += 1
	return g / maxi(n, 1)


func _judge_turn_in_coasting() -> void:
	_turn["coasting"] = _yaw_gain()
	var rear := 0.0
	for e in _log:
		rear = maxf(rear, absf(e[10]))
	print("[physics]      turning in, coasting: yaw for the steering %.2f, rear slip %.1f deg at most" % [_turn.coasting, rear])


func _judge_turn_in_braking() -> void:
	var g := _yaw_gain()
	var rear := 0.0
	var front := 0.0
	for e in _log:
		rear = maxf(rear, absf(e[10]))
		front = maxf(front, absf(e[9]))
	fails += _check(g > _turn.coasting * 1.05, "trail braking: entering the turn on the brakes rotates the car more (yaw for the steering %.2f vs %.2f coasting)" % [
		g, _turn.coasting])
	fails += _check(rear < 12.0, "trail braking: the tail steps out, it doesn't spin (rear slip %.1f deg at most, front %.1f)" % [rear, front])


func _judge_load() -> void:
	var t: Resource = car.config.front_tire
	var nominal: float = t.nominal_load
	var py := tan(deg_to_rad(t.lateral_peak_deg))
	var per_n_1: float = TireModel.combined(t, 0.0, py, nominal, 1.0, TireModel.load_mu_factor(t, nominal)).y / nominal
	var per_n_2: float = TireModel.combined(t, 0.0, py, 2.0 * nominal, 1.0, TireModel.load_mu_factor(t, 2.0 * nominal)).y / (2.0 * nominal)
	fails += _check(per_n_2 < per_n_1 and absf(per_n_2 / per_n_1 - (1.0 - t.load_sensitivity)) < 0.01,
		"load sensitivity: a tyre with twice the load grips %.0f %% less per newton (%.3f vs %.3f)" % [(1.0 - per_n_2 / per_n_1) * 100.0, per_n_2, per_n_1])


func name_open(n: String) -> bool:
	return n == "ice open diffs"


## The car's drivetrain for the ice runs: held in first (as a driver would:
## an auto box would change up on the spinning wheel's revs), and with all
## three diffs open for the open run.
func _ice_drivetrain(open_diffs: bool) -> Resource:
	if _real_drivetrain == null:
		_real_drivetrain = car.drivetrain.cfg
	var d: Resource = _real_drivetrain.duplicate()
	d.auto_shift = false
	if open_diffs:
		for slot in ["center_diff", "front_diff", "rear_diff"]:
			var open: Resource = (d.get(slot) as Resource).duplicate()
			open.kind = 0                            # OPEN
			d.set(slot, open)
	return d


func _judge_launch() -> void:
	var t100 := -1.0
	var spin := 0.0
	var hooked := -1.0
	var max_rpm := 0.0
	for e in _log:
		if t100 < 0.0 and e[13] >= 100.0 / 3.6:
			t100 = e[0]
		if e[0] < 1.5:
			spin = maxf(spin, e[14])
		if hooked < 0.0 and e[13] >= 50.0 / 3.6:
			hooked = e[14]                           # the slip as it passes 50 km/h
	var e_cfg: Resource = car.config.engine
	_p8["launch"] = {"t100": t100, "spin": _rolling_spin()}
	fails += _check(t100 > 3.5 and t100 < 7.0, "full throttle from a standstill: 0-100 km/h in %.2f s (a Rally2 car on gravel: ~4-5 s)" % t100)
	fails += _check(spin > 0.08 and hooked >= 0.0 and hooked < 0.4,
		"pulling away flat out: the tyres spin (slip ratio up to %.0f %% at walking pace) and hook up as it gathers speed (%.0f %% by 50 km/h); a driver feathers the throttle, traction control (phase 8) will" % [
			spin * 100.0, hooked * 100.0])
	# in each gear the engine turns at exactly the gear's ratio x the wheels' speed
	# (clutch in, nothing slipping), so a change drops the revs by the ratio
	var ok := _shifts.size() >= 2
	var lines := ""
	var to_rpm := 60.0 / TAU
	for sh in _shifts:
		var g0: float = car.drivetrain.ratio_for(sh[1])
		var g1: float = car.drivetrain.ratio_for(sh[2])
		var err0: float = absf(sh[3] / (g0 * sh[5] * to_rpm) - 1.0)
		var err1: float = absf(sh[4] / (g1 * sh[6] * to_rpm) - 1.0)
		lines += " %d->%d at %.1f s, %.0f->%.0f rpm (ratio x%.2f);" % [sh[1], sh[2], sh[0], sh[3], sh[4], g1 / g0]
		ok = ok and err0 < 0.03 and err1 < 0.03
	fails += _check(ok, "it changes up by itself, the engine turning at each gear's ratio x the wheels' speed:" + lines)
	for e in _log:
		max_rpm = maxf(max_rpm, e[19])
	fails += _check(max_rpm < e_cfg.limiter_rpm + 150.0, "the limiter holds it (%.0f rpm at most, limiter %.0f)" % [max_rpm, e_cfg.limiter_rpm])
	# the clutch's torque reads + driving (the LSDs pick their power or coast lock by it)
	fails += _check(_mean(20, 0.5, 2.5) > 50.0, "pulling away the clutch carries the engine's drive: %+.0f N m on average (+ = driving)" % _mean(20, 0.5, 2.5))


func _judge_engine_braking() -> void:
	var rr: float = car.config.front_tire.rolling_resistance
	var coast := rr * car.mass * 9.8 / _m_eff()
	var got := -_accel(0.3, 1.5)
	fails += _check(got > 3.0 * coast and got < 2.5, "lifting off in third at 80 km/h: engine braking, %.2f m/s² (coasting: %.2f)" % [got, coast])
	fails += _check(_mean(20, 0.3, 1.5) < -20.0, "and the clutch carries it the other way: %+.0f N m (- = the wheels turning the engine)" % _mean(20, 0.3, 1.5))


func _judge_ice_open_diffs() -> void:
	_ice["open"] = _accel(0.7, 2.0)
	_ice["open_spin"] = car.wheels[3].wheel_speed()
	_ice["open_ground"] = car.speed


func _judge_ice_locked_diffs() -> void:
	var locked := _accel(0.7, 2.0)
	fails += _check(_ice.open < 0.4 * locked and _ice.open_spin > 3.0 * maxf(_ice.open_ground, 0.5),
		"one wheel on ice: open diffs lose the drive to it (%.2f m/s², that wheel at %.0f km/h, the car at %.0f); the car's LSDs and locked centre pull away (%.2f m/s²)" % [
			_ice.open, _ice.open_spin * 3.6, _ice.open_ground * 3.6, locked])


## The car's tyre on surface `n` (the fronts and rears are the same tyre).
func _tyre_on(n: String) -> Resource:
	return TireModel.on_surface(car.config.front_tire, Surfaces.named(n))


## A run on a surface pad: measure it, and once every surface has had this run,
## compare them.
func _judge_surface(kind: String, n: String) -> void:
	var t := _tyre_on(n)
	var g := 9.8
	var mu: float = t.longitudinal_mu
	var rr: float = t.rolling_resistance
	match kind:
		"corner":
			# the most cornering it holds for a quarter of a second (its acceleration
			# across its path), and the front slip angle then
			var best := 0.0
			var slip := 0.0
			var win: Array = []
			for e in _log:
				var a_h := Vector3(e[16].x, 0.0, e[16].z)
				var v_h := Vector3(e[17].x, 0.0, e[17].z).normalized()
				win.append((a_h - v_h * a_h.dot(v_h)).length())
				if win.size() > 30:
					win.pop_front()
				var a: float = win.reduce(func(x, y): return x + y, 0.0) / win.size()
				if win.size() == 30 and a > best:
					best = a
					slip = absf(e[9])
			_surf.corner[n] = {"a": best, "slip": slip}
			print("[physics]      cornering on %-7s %5.2f m/s² (%.2f g), the fronts at %4.1f deg slip then" % [n + ":", best, best / g, slip])
		"brake":
			var t10 := -1.0
			var t2 := -1.0
			for e in _log:
				if t10 < 0.0 and e[13] <= 10.0:
					t10 = e[0]
				if t2 < 0.0 and e[13] <= 2.0:
					t2 = e[0]
			var decel := 8.0 / maxf(t2 - t10, 0.01)
			var dist := (car.global_position - _v0).length()
			var locked := mu * absf(TireModel.longitudinal_curve(t, -1.0)) * g   # (a locked tyre slides: it isn't rolling)
			var peak := (mu + rr) * g
			_surf.brake[n] = {"a": decel, "d": dist}
			fails += _check(t2 > 0.0 and decel > locked * 0.85 and decel < peak * 1.08,
				"braking on %s from 40 km/h: %.2f m/s², stopped in %.1f m (locked tyres there: %.2f, the peak grip: %.2f)" % [n, decel, dist, locked, peak])
		"pull away":
			var t40: float = _t if car.speed >= PULL_TO else INF
			var floor_t := PULL_TO / maxf(mu * g, 0.01)
			_surf["pull away"][n] = t40
			fails += _check(t40 < 16.0 and t40 > floor_t * 0.95,
				"pulling away on %s: 0-40 km/h in %.2f s (the grip allows %.2f s at best)" % [n, t40, floor_t])
		"coast":
			var want := rr * car.mass * g / _m_eff()
			var got := -_accel(0.5, 2.5)
			_surf.coast[n] = got
			fails += _check(absf(got - want) < want * 0.06,
				"coasting on %s at 20 m/s: %.3f m/s² (its rolling resistance, %.3f: %.3f)" % [n, got, rr, want])
	if n != Lab.SURFACES[Lab.SURFACES.size() - 1]:
		return
	var r: Dictionary = _surf[kind]
	match kind:
		"corner":
			var ok := true
			var lines := ""
			for s in Lab.SURFACES:
				var want: float = r.gravel.a * Surfaces.named(s).grip
				ok = ok and absf(r[s].a / want - 1.0) < 0.15
				lines += " %s %.1f (%.1f)," % [s, r[s].a, want]
			fails += _check(ok, "cornering: each surface holds its grip x gravel's (m/s², want):" + lines)
			fails += _check(r.asphalt.slip < r.gravel.slip and r.gravel.slip < minf(r.snow.slip, r.mud.slip),
				"the looser the surface, the bigger the slip angle it lets go at (asphalt %.1f, gravel %.1f, snow %.1f, mud %.1f deg)" % [
					r.asphalt.slip, r.gravel.slip, r.snow.slip, r.mud.slip])
		"brake":
			fails += _check(r.asphalt.a > r.gravel.a and r.gravel.a > r.grass.a and r.grass.a > maxf(r.snow.a, r.mud.a)
				and minf(r.snow.a, r.mud.a) > r.ice.a,
				"braking: asphalt stops shortest, then gravel, grass, snow and mud, and ice by far the longest (%.0f / %.0f / %.0f / %.0f / %.0f / %.0f m)" % [
					r.asphalt.d, r.gravel.d, r.grass.d, r.snow.d, r.mud.d, r.ice.d])
		"pull away":
			fails += _check(r.asphalt < r.gravel * 1.05 and r.gravel < r.snow and r.gravel < r.mud and r.ice > maxf(r.snow, r.mud),
				"pulling away: asphalt and gravel quickest, snow and mud slower, ice slowest (%.1f / %.1f / %.1f / %.1f / %.1f / %.1f s, grass %.1f)" % [
					r.asphalt, r.gravel, r.dirt, r.snow, r.mud, r.ice, r.grass])
		"coast":
			fails += _check(r.mud > r.grass and r.grass > r.snow and r.snow > r.gravel and r.gravel > r.asphalt,
				"coasting: mud drags most, then grass, snow, gravel, asphalt (%.2f / %.2f / %.2f / %.2f / %.2f m/s²)" % [
					r.mud, r.grass, r.snow, r.gravel, r.asphalt])


## Give the wheels copies of the car's suspensions, changed by change(front, rear)
## (the next run puts the car's own back).
func _suspensions(change: Callable) -> void:
	var f: Resource = car.config.front_suspension.duplicate()
	var r: Resource = car.config.rear_suspension.duplicate()
	change.call(f, r)
	for k in 4:
		car.wheels[k].cfg = f if k < 2 else r


## How far the car has turned this run (deg, from the logged yaw rate).
func _turned() -> float:
	var yaw := 0.0
	for e in _log:
		yaw += e[8] / 120.0
	return absf(yaw)


## The biggest logged value of a column (its size), from t0 on.
func _peak(col: int, t0 := 0.0) -> float:
	var m := 0.0
	for e in _log:
		if e[0] >= t0:
			m = maxf(m, absf(e[col]))
	return m


func _judge_turn_no_handbrake() -> void:
	_p7r["turn"] = {"yaw": _turned(), "rear": _peak(10)}


func _judge_handbrake_turn() -> void:
	var yaw := _turned()
	var rear := _peak(10)
	var plain: Dictionary = _p7r.turn
	fails += _check(yaw > 1.4 * plain.yaw and rear > 12.0,
		"handbrake turn at 15 m/s: it turns %.0f deg in 2 s (the same steering without it: %.0f), the tail out to %.0f deg of slip (%.0f without)" % [
			yaw, plain.yaw, rear, plain.rear])
	fails += _check(_p7.locked > 0.9 * _p7.n and _p7.rolling > 0.9 * _p7.n,
		"with the handbrake pulled the rears lock (%.0f %% of the time) and the fronts keep rolling (%.0f %%)" % [
			100.0 * _p7.locked / maxf(_p7.n, 1), 100.0 * _p7.rolling / maxf(_p7.n, 1)])


func _judge_handbrake_and_throttle() -> void:
	var locked: float = float(_p7.locked) / maxf(_p7.n, 1)
	var driving: float = float(_p7.get("driving", 0)) / maxf(_p7.n, 1)
	_p7r["go"] = car.speed
	fails += _check(locked > 0.9 and driving > 0.9,
		"rolling at 36 km/h, handbrake and full throttle: the rear axle's clutch lets go, the rears stay locked (%.0f %% of the time) while the fronts drive (%.0f %%); %.0f km/h after 1.5 s" % [
			locked * 100.0, driving * 100.0, car.speed * 3.6])


func _judge_handbrake_and_throttle_without_the_rear_clutch() -> void:
	var locked: float = float(_p7.locked) / maxf(_p7.n, 1)
	fails += _check(locked < 0.2,
		"without that clutch the engine turns the rears through the locked centre: they lock %.0f %% of the time, the handbrake only drags (%.0f km/h after 1.5 s, with the clutch %.0f)" % [
			locked * 100.0, car.speed * 3.6, _p7r.go * 3.6])


## Body roll per g of cornering (deg / g) over the run's last 1.5 s, and what the
## springs and bars predict: the CoM's height x the cornering force over the roll
## stiffness (less what the CoM's sideways lean adds back).
func _roll_per_g() -> Vector2:
	var roll := 0.0
	var a := 0.0
	for e in _log:
		if e[0] > _log[_log.size() - 1][0] - 1.5:
			roll += absf(e[3])
			a += e[7] * deg_to_rad(absf(e[8]))
	var cfg = car.config
	var k: float = Suspension.roll_stiffness(car.wheels[0].cfg, cfg.front_track) + Suspension.roll_stiffness(car.wheels[2].cfg, cfg.rear_track)
	var mgh: float = car.mass * 9.8 * (car.ride_height() + cfg.center_of_mass.y)
	return Vector2(roll / a * 9.8, rad_to_deg(mgh / (k - mgh)))


func _judge_roll_with_bars() -> void:
	var r := _roll_per_g()
	_p7r["roll"] = r.x
	fails += _check(absf(r.x / r.y - 1.0) < 0.15 and r.x > 2.0 and r.x < 3.5,
		"in a steady corner (0.57 g) it rolls %.2f deg per g (the springs and bars predict %.2f)" % [r.x, r.y])


func _judge_roll_without_bars() -> void:
	var r := _roll_per_g()
	fails += _check(absf(r.x / r.y - 1.0) < 0.15 and _p7r.roll < 0.65 * r.x,
		"without the anti-roll bars: %.2f deg per g (predicted %.2f): the bars take %.0f %% of the roll out" % [
			r.x, r.y, (1.0 - _p7r.roll / r.x) * 100.0])


## The front and rear slip angles and the cornering over the run's last 1.5 s.
func _balance() -> Dictionary:
	var sf := 0.0
	var sr := 0.0
	var a := 0.0
	var n := 0
	for e in _log:
		if e[0] > _log[_log.size() - 1][0] - 1.5:
			sf += absf(e[9])
			sr += absf(e[10])
			a += e[7] * deg_to_rad(absf(e[8]))
			n += 1
	return {"front": sf / n, "rear": sr / n, "a": a / n}


func _judge_balance_stiff_front_bar() -> void:
	_p7r["stiff front"] = _balance()


func _judge_balance_stiff_rear_bar() -> void:
	var f: Dictionary = _p7r["stiff front"]
	var r := _balance()
	fails += _check(f.front - f.rear > r.front - r.rear + 0.3,
		"at the limit a stiffer front bar makes it push more: front slip %.1f / rear %.1f deg (%.2f m/s²); a stiffer rear bar lets the tail work: %.1f / %.1f (%.2f m/s²)" % [
			f.front, f.rear, f.a, r.front, r.rear, r.a])


## The body's hardest vertical jolt this run (m/s², averaged over 3 ticks).
func _peak_jolt() -> float:
	var m := 0.0
	for i in range(2, _log.size()):
		var ay: float = (_log[i][16].y + _log[i - 1][16].y + _log[i - 2][16].y) / 3.0
		m = maxf(m, absf(ay))
	return m


func _judge_sharp_bumps_two_stage() -> void:
	_p7r["bumps"] = _peak_jolt()


func _judge_sharp_bumps_linear() -> void:
	var two: float = _p7r.bumps
	var lin := _peak_jolt()
	fails += _check(two < 0.9 * lin,
		"over sharp bumps at 15 m/s the two-stage dampers let the wheels move: the body's hardest jolt %.1f m/s² (plain dampers: %.1f)" % [two, lin])


func _judge_aero_coast() -> void:
	# the mean deceleration and the mean of v² over 0.5-2.0 s
	var v2 := 0.0
	var n := 0
	for e in _log:
		if e[0] >= 0.5 and e[0] <= 2.0:
			v2 += e[13] * e[13]
			n += 1
	v2 /= n
	var cfg = car.config
	var rr: float = cfg.front_tire.rolling_resistance
	var q := 0.5 * Aero.AIR_DENSITY * v2
	var want: float = (q * cfg.drag_coefficient * cfg.frontal_area + rr * (car.mass * 9.8 + q * cfg.downforce_area)) / _m_eff()
	var got := -_accel(0.5, 2.0)
	fails += _check(absf(got / want - 1.0) < 0.05,
		"coasting from 150 km/h: %.2f m/s² (drag %.2f + rolling resistance with the downforce %.2f: %.2f); at 20 m/s the drag alone would be %.2f" % [
			got, q * cfg.drag_coefficient * cfg.frontal_area / _m_eff(), rr * (car.mass * 9.8 + q * cfg.downforce_area) / _m_eff(), want,
			0.5 * Aero.AIR_DENSITY * 400.0 * cfg.drag_coefficient * cfg.frontal_area / _m_eff()])


## The measured downforce on the front and rear axles (N): the tyres' loads less the
## car's weight on each (from the static run's split).
func _downforce_measured() -> Vector2:
	var loads: Array = car.config.static_loads(9.8)
	var w := Vector2(loads[0] * 2.0, loads[1] * 2.0)
	return Vector2(_p7.front / _p7.n, _p7.rear / _p7.n) - w


func _judge_aero_downforce_30() -> void:
	var d := _downforce_measured()
	var want: Vector2 = Aero.downforce(car.config, 30.0 / 3.6)
	_p7r["df30"] = d.x + d.y
	fails += _check(absf(d.x + d.y) < 80.0,
		"at 30 km/h the downforce is practically nothing: %+.0f N measured (%.0f N predicted, the car weighs %.0f)" % [d.x + d.y, want.x + want.y, car.mass * 9.8])


func _judge_aero_downforce_150() -> void:
	var d := _downforce_measured()
	var cfg = car.config
	var want: Vector2 = Aero.downforce(cfg, 150.0 / 3.6)
	var total := d.x + d.y
	# the tow pulls at the centre of mass against the tyres' rolling resistance at the
	# ground: that couple moves some load onto the front, which isn't downforce
	var couple: float = cfg.front_tire.rolling_resistance * (car.mass * 9.8 + total) * (car.ride_height() + cfg.center_of_mass.y) / (cfg.rear_axle - cfg.front_axle)
	var front := (d.x - couple) / total
	fails += _check(absf(total / (want.x + want.y) - 1.0) < 0.12 and absf(front - cfg.aero_balance) < 0.05,
		"at 150 km/h: %.0f N (%.0f kg) of downforce measured on the tyres (%.0f predicted), %.0f %% of it on the front (%.0f %%; less the %.0f N the tow's pull moves forward)" % [
			total, total / 9.8, want.x + want.y, front * 100.0, cfg.aero_balance * 100.0, couple])


## This run's driver aids: the ones its name asks for, all of them for "aids on",
## none otherwise (the base physics).
func _aids(name: String) -> void:
	var a: Resource = AssistConfig.new()
	if name.begins_with("all aids "):
		for k in AIDS:
			a.set(k, true)
	if name == "abs stop" or name.ends_with("with abs"):
		a.anti_lock = true
	if name.ends_with("with tc"):
		a.traction_control = true
	if name.ends_with("with esc"):
		a.stability_control = true
	if name.ends_with("speed sensitive"):
		a.speed_sensitive_steering = true
	if name.ends_with("smoothing"):
		a.steering_smoothing = true
	if name.ends_with("damping"):
		a.steering_damping = true
	if name.ends_with("countersteer help"):
		a.countersteer_help = true
	car.assists = a
	car.assist.setup(a)


## The biggest slip ratio once it's rolling (over 3 m/s).
func _rolling_spin() -> float:
	var m := 0.0
	for e in _log:
		if e[13] > 3.0:
			m = maxf(m, e[14])
	return m


## When the front wheels first reach this angle (s; INF: never).
func _time_to_angle(deg: float) -> float:
	for e in _log:
		if absf(e[18]) >= deg_to_rad(deg):
			return e[0]
	return INF


func _judge_all_aids_corner() -> void:
	var b := _balance()
	var base: Dictionary = _skid[4]
	fails += _check(absf(b.a / base.a - 1.0) < 0.015 and absf(b.front - base.front) < 0.05 and absf(b.rear - base.rear) < 0.05,
		"all eight aids on, a steady corner inside the grip: %.2f m/s², slip front %.2f / rear %.2f deg (all off: %.2f, %.2f / %.2f): the same car" % [
			b.a, b.front, b.rear, base.a, base.front, base.rear])


func _judge_all_aids_braking() -> void:
	var got := _accel(0.3, 2.0)
	var base: float = _p8["brake gently"]
	fails += _check(absf(got / base - 1.0) < 0.01,
		"all eight aids on, braking at 30 %%: %.3f m/s² (all off: %.3f): the same car" % [got, base])


func _judge_abs_stop() -> void:
	var moving := 0
	var locked := 0
	for e in _log:
		if e[13] > 3.0:
			moving += 1
			locked += 1 if e[21] else 0
	var dist := (car.global_position - _v0).length()
	var base: float = _p8["locked stop"]
	fails += _check(dist < base and locked < moving * 0.05,
		"ABS, full brakes from 100 km/h: %.1f m (locked: %.1f m), a wheel locked %.0f %% of the time" % [dist, base, 100.0 * locked / maxi(moving, 1)])


func _judge_brake_and_steer() -> void:
	_p8["brake steer"] = _turned()


func _judge_brake_and_steer_with_abs() -> void:
	var yaw := _turned()
	var base: float = _p8["brake steer"]
	fails += _check(yaw > 2.0 * base + 5.0,
		"full brakes from 80 km/h with the wheel at 15 degrees: with ABS it turns %.0f deg in 2 s; locked it slides on, %.0f deg" % [yaw, base])


func _judge_launch_with_tc() -> void:
	var t100 := INF
	for e in _log:
		if e[13] >= 100.0 / 3.6:
			t100 = e[0]
			break
	var spin := _rolling_spin()
	var base: Dictionary = _p8.launch
	fails += _check(spin < 0.5 and spin < 0.5 * base.spin and t100 < base.t100 * 1.05,
		"traction control, flat out off the line: the tyres spin up to %.0f %% once rolling (without it: %.0f %%), 0-100 km/h in %.2f s (without: %.2f)" % [
			spin * 100.0, base.spin * 100.0, t100, base.t100])


func _judge_ice_pull_away_with_tc() -> void:
	var base: float = _surf["pull away"].ice
	fails += _check(car.speed >= PULL_TO and _t < base,
		"traction control on ice: 0-40 km/h in %.1f s (without it: %.1f)" % [_t, base])


func _judge_snow_flick() -> void:
	_p8["flick"] = {"rear": _peak(10, 0.3), "yaw": _turned()}


func _judge_snow_flick_with_esc() -> void:
	var rear := _peak(10, 0.3)
	var base: Dictionary = _p8.flick
	fails += _check(rear < 0.8 * base.rear,
		"stability control, a snow flick at 72 km/h: the tail out to %.0f deg of slip (without it: %.0f)" % [rear, base.rear])


func _judge_full_lock_at_90() -> void:
	_p8["lock"] = _balance()


func _judge_full_lock_at_90_speed_sensitive() -> void:
	var b := _balance()
	var base: Dictionary = _p8.lock
	fails += _check(b.front < 0.5 * base.front and base.front > 15.0 and b.a > 0.97 * base.a,
		"full lock at 90 km/h: with speed-sensitive steering the fronts work at %.1f deg of slip (without: %.1f, ploughing), cornering %.2f m/s² (without: %.2f)" % [
			b.front, base.front, b.a, base.a])


func _judge_steering_step() -> void:
	_p8["step"] = {"t": _time_to_angle(25.0), "end": absf(_log[_log.size() - 1][18])}


func _judge_steering_step_smoothing() -> void:
	var t := _time_to_angle(25.0)
	var end := absf(_log[_log.size() - 1][18])
	var base: Dictionary = _p8.step
	fails += _check(t > 1.8 * base.t and absf(end - base.end) < 0.01,
		"steering smoothing: a key press turns the wheels to 25 deg in %.2f s (without: %.2f), to the same lock (%.1f deg)" % [t, base.t, rad_to_deg(end)])


func _judge_steering_at_108() -> void:
	_p8["108"] = _time_to_angle(10.0)


func _judge_steering_at_108_damping() -> void:
	var t := _time_to_angle(10.0)
	var base: float = _p8["108"]
	fails += _check(t > 2.0 * base,
		"steering damping: at 108 km/h the wheels take %.2f s to turn 10 deg (without: %.2f)" % [t, base])


## The yaw rate at the end of the run (deg/s, its size).
func _end_yaw_rate() -> float:
	return absf(_log[_log.size() - 1][8])


## How far it turned after the driver let go (deg, from 0.8 s), and how fast it
## was still rotating at the end (deg/s).
func _after_letting_go() -> Vector2:
	var yaw := 0.0
	for e in _log:
		if e[0] > 0.8:
			yaw += e[8] / 120.0
	return Vector2(absf(yaw), _end_yaw_rate())


func _judge_slide_hands_off() -> void:
	_p8["slide"] = _after_letting_go()
	print("[physics]      a handbrake slide let go of at 65 km/h, power on, hands off: %.0f deg more in 2.2 s, %.0f deg/s at the end, rear slip %.0f deg at the end" % [
		_p8.slide.x, _p8.slide.y, absf(_log[_log.size() - 1][10])])


func _judge_slide_countersteer_help() -> void:
	var r := _after_letting_go()
	var base: Vector2 = _p8.slide
	fails += _check(r.x < base.x - 10.0 and r.y < 0.5 * maxf(base.y, 10.0),
		"countersteer help: a handbrake slide let go of (power on, hands off) turns %.0f deg more and ends rotating at %.0f deg/s (rear slip %.0f deg); without it %.0f deg, %.0f deg/s" % [
			r.x, r.y, absf(_log[_log.size() - 1][10]), base.x, base.y])


## Every Button under a node.
func _buttons(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_buttons(c))
	return out


func _judge_settings_panel() -> void:
	var panel: Node = _p8.panel
	var config := root.get_node_or_null("Config")
	var toggles := _buttons(panel).filter(func(b): return b.toggle_mode)
	var ok: bool = config != null and toggles.size() == AIDS.size() + 1      # (+ invert mouse Y)
	var abs_on := false
	if ok:
		var saved: Dictionary = config.aids.duplicate()
		var was_invert: bool = config.invert_y
		toggles[1].button_pressed = true                 # the first aid: ABS (after invert Y)
		var other: RigidBody3D = (load(Lab.CAR_SCENE) as PackedScene).instantiate()
		root.add_child(other)
		abs_on = config.aids.anti_lock and other.assists.anti_lock
		other.queue_free()
		config.aids = saved                              # (put the settings back)
		config.invert_y = was_invert
		config.save()
	panel.queue_free()
	fails += _check(ok and abs_on,
		"the Settings panel: %d switches (the %d aids and invert mouse Y); ABS switched on there, a new car comes with ABS on" % [toggles.size(), AIDS.size()])


func _judge_telemetry_record() -> void:
	var path: String = car.telemetry.stop_recording()
	var text := FileAccess.get_file_as_string(path)
	var lines := text.strip_edges().split("\n")
	var header := lines[0].split(",")
	var row := lines[lines.size() - 1].split(",")
	fails += _check(lines.size() > 110 and lines.size() < 130 and header.size() == row.size() and "fl_surface" in header,
		"telemetry recording: a second of driving, %d rows of %d columns in %s" % [lines.size() - 1, header.size(), path])
	DirAccess.remove_absolute(path)


func _judge_split_braking() -> void:
	var yaw := rad_to_deg(wrapf(car.global_rotation.y - _yaw0, -PI, PI))
	fails += _check(yaw < -5.0, "braking with the left wheels on ice, the right on asphalt: it turns toward the asphalt (%.0f deg to the right in 0.75 s)" % -yaw)


func _judge_reverse() -> void:
	fails += _check(car.gear == -1 and car.speed < -1.0, "stopped, holding the brake: reverse, and it backs up (gear %d, %.1f m/s)" % [car.gear, car.speed])


## The average of a logged column between two times (s).
func _mean(col: int, t0: float, t1: float) -> float:
	var sum := 0.0
	var n := 0
	for e in _log:
		if e[0] >= t0 and e[0] <= t1:
			sum += e[col]
			n += 1
	return sum / maxf(n, 1)


func _check(ok: bool, msg: String) -> int:
	print("[physics] %s %s" % ["ok  " if ok else "FAIL", msg])
	return 0 if ok else 1


func _done() -> bool:
	fails += _check(Engine.physics_ticks_per_second == 120, "running at %d ticks a second" % Engine.physics_ticks_per_second)
	print("[physics] %s" % ("PHYSICS V2 OK" if fails == 0 else "PHYSICS V2 FAIL"))
	quit(1 if fails > 0 else 0)
	return true
