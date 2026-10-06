extends RigidBody3D
## The rally car (docs/physics_rebuild.md): a RigidBody3D chassis on four
## suspension corners, with nothing scripted. Built in nine phases, each tested
## (tests/physics_v2_check.gd):
##   * the chassis: the mass, centre of mass and inertia of a ~1,280 kg AWD rally
##     car (data/cars/awd_rally.tres, a CarConfig), on four corners
##     (rally_wheel.gd: a ShapeCast3D tyre each, spring + two-stage damper + bump
##     stop pushing at the contact patch, anti-roll bars across each axle).
##     Pitch and roll come from where the forces act
##   * the tyres (tire_model.gd): slip angle -> side force, slip ratio -> the
##     force along the wheel, one patch of rubber for both (the combined-slip
##     ellipse), load sensitivity, relaxation; each wheel spins on its own
##   * the engine, clutch, sequential gearbox and three diffs (drivetrain.gd),
##     solved with the wheels SUBSTEPS times a tick
##   * surfaces, each wheel on its own (surfaces.gd: the meta "surface" of what
##     it touches), and the road's grip across it on top (the clean wheel
##     tracks, the loose gravel: set_lanes)
##   * the handbrake (it also lets the rear axle's drive go, as a rally car's
##     hydraulic handbrake does), aero (drag, downforce), the steering (the
##     rack follows the input, Ackermann splits it)
##   * the driver aids (driver_assist.gd, an AssistConfig), each its own switch
##     in Settings (Config.aids): they only change what the pedals, brakes and
##     steering ask for, never the physics, except drift assist (an arcade aid:
##     a turning force on the body holds a drift at its angle)
##   * on extra grip (Settings > TYRE GRIP above REAL) the tip guard: the tyres
##     can corner harder than the car could without tipping, so a side lifting
##     in a corner is pushed back down (_tip_guard)
## Stopped, holding the brake selects reverse; then the brake drives it back.
## Runs at 120 physics ticks a second (project.godot: the wheels are stiff).
##
## The game around it: crashes (`hit`) and landings (`landed`) for the sound and
## camera, `slip` (how hard the tyres slide) for the sound and dust, puddles
## (`mud_mu`), the car from the garage (apply_setup: power, grip, brakes, the
## drive split, the paint, which body), the Higgsfield body model (seen from
## outside: set_outside) with its wheels, swinging mud flaps (the hatchback) or
## see-through glass and a kidney grille (the coupé).
## The machine of whoever is DRIVING simulates it (`simulate`) and streams its
## state ~30x a second; the co-driver's machine plays that stream back 100 ms
## behind, smoothly (snapshot interpolation), so the cabin never jitters.
##
## The scene (scenes/rally_car.tscn, the physics lab's): RallyCar (this) >
## CollisionShape3D x2, CarMesh, CenterOfMass, FL / FR / RL / RR _WheelPoint
## (rally_wheel.gd, each with a ShapeCast3D and a WheelMesh), Telemetry (F3
## numbers, F4 force arrows, F2 records a CSV). Made with RallyCar.new() instead
## (the game), it builds the same nodes itself.
## The car faces -Z; the origin is the middle of the chassis at mount height.

signal hit(impact: float)          # ran into something (m/s of speed lost)
signal landed(impact: float)       # came down onto its wheels (m/s downward)

const RallyWheel = preload("res://scripts/vehicle/physics/rally_wheel.gd")
const Drivetrain = preload("res://scripts/vehicle/physics/drivetrain.gd")
const Telemetry = preload("res://scripts/vehicle/physics/rally_telemetry.gd")
const Aero = preload("res://scripts/vehicle/physics/aero.gd")
const DriverAssist = preload("res://scripts/vehicle/physics/driver_assist.gd")
const AssistConfig = preload("res://scripts/vehicle/physics/config/assist_config.gd")
const Surfaces = preload("res://scripts/vehicle/physics/surfaces.gd")
const Livery = preload("res://scripts/vehicle/livery.gd")
const WheelMesh = preload("res://scripts/vehicle/wheel_mesh.gd")
const KidneyGrille = preload("res://scripts/vehicle/kidney_grille.gd")
const DEFAULT_CONFIG := "res://data/cars/awd_rally.tres"
const TICKS := 120                 # physics ticks per second (see the plan: the wheels are stiff)
const NAMES := ["FL", "FR", "RL", "RR"]
const SUBSTEPS := 8                # tyre / wheel-spin / drivetrain steps per tick
## The bodies (Catalog: a car's "body"): each a folder of parts cut from a
## Higgsfield model (tools/split_car.gd for the hatchback, tools/split_body.gd for
## the rest), with parts.json saying where its wheels are.
const BODIES := {"hatch": "res://assets/models/car_parts/", "coupe": "res://assets/models/coupe/parts/"}
const MODEL_SCALE := 1.95          # model units -> m
const MODEL_GROUND := 0.56         # m below its origin the hatchback's tyres touch, placed at y 0.205
const NET_HZ := 30.0
const NET_DELAY := 100.0           # ms behind the stream on the co-driver's machine

## The car's numbers (a CarConfig resource).
@export var config: Resource
## Show the telemetry HUD from the start (F3 toggles it).
@export var show_telemetry := false
## The driver aids (an AssistConfig; none: the game's Settings, or all off without them).
@export var assists: Resource

## Driver inputs: steer -1..1 (+ = right), throttle 0..1, brake 0..1, handbrake.
var inp := {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": false}
var simulate := true
var stream_ok := false             # quiet until the game says both machines have loaded (a car still being
                                   # built must not talk to a machine that has no Car yet)
var states_received := 0           # co-driver side: stream packets in (tests)
var speed := 0.0                   # along the car (m/s, + = forward)
var gear := 1                      # the gear (R = -1, N = 0)
var rpm := 0.0                     # 0..1 from idle to the limiter (the sound and the rev counter)
var steer := 0.0                   # front wheel angle (rad, + = right)
var slip := 0.0                    # 0..1, how hard the tyres are sliding (the sound, the dust)
var grounded := 0                  # tyres touching
var comp := [0.0, 0.0, 0.0, 0.0]   # spring compression per corner (m)
var wheel_angles := [0.0, 0.0]     # front left / right road-wheel angles (rad, + = right)
var accel := Vector3.ZERO          # the body's acceleration last tick (m/s², world)
var on_surface := "gravel"         # what most of the tyres are on
var lane_mu := [1.0, 1.0, 1.0, 1.0]   # grip from where each tyre is across the road (set_lanes)
var mud_mu := false                # set by the game while a tyre is in a puddle: all four on mud
var net_throttle := 0.0            # co-driver side: the driver's throttle, from the stream (the engine's sound)
var wheels: Array = []             # RallyWheel: FL, FR, RL, RR
var telemetry: CanvasLayer
var drivetrain                     # Drivetrain (null: no engine in the config, the wheels roll free)
var assist                        # DriverAssist
var aero_drag := 0.0               # N, last tick
var aero_down := Vector2.ZERO      # N on the front / rear axle, last tick
# the car from the garage (apply_setup): x the base car's power, grip, brakes; the drive split
var setup := {}
var power_mult := 1.0
var grip_mult := 1.0
var brake_mult := 1.0
var body_model: Node3D             # the Higgsfield car (BODIES): seen from outside
var body_id := ""                  # which body it is (BODIES)
var own_paint := false             # the body wears its own paint (the garage's livery and colours don't apply)
var see_through := false           # the body has clear glass: from outside you see the crew (Cockpit.show_crew_only)

var _air := 0.0
var _rack := 0.0                   # the steering rack: the "bicycle" front-wheel angle (rad, + = right)
var _prev_v := Vector3.ZERO
var _reverse_t := 0.0
var _own_config := false           # config is this car's own copy (the garage changes it)
var _base := {}                    # the config's numbers before the garage's multipliers
var tyre_kind := ""                # the tyres on it, "gravel" or "tarmac", and its setup (apply_setup: _tune)
var setup_kind := ""
var grip_assist := -1.0            # extra tyre grip (0 real .. 1.5, 2 arcade: TireModel.grippy); below 0: the game's Settings
var _tuned_grip := -1.0
var _base_parts := {}              # its own suspension, tyres and rack, before a setup changed them
var _mud: Resource
var _model_wheels: Array = []      # [pivot, spinner, rest position] per corner (model units)
var _flaps: Array = []             # [hinge, angle, angular speed] per corner
var _flap_prev_v := Vector3.ZERO
var _static_comp := [0.11, 0.11]   # front / rear compression standing still (m): the model's rest pose
var _net_acc := 0.0
var _net_handbrake := false
var _buf: Array = []               # [{t, pos, rot, vel, steer, rpm, gear, comp, slip, surf, hb}]
var _offset := INF                 # local ms - sender ms (latency + clock difference)


func _ready() -> void:
	_load_config()
	if assists == null:
		assists = AssistConfig.new()                 # all off: the base physics ...
		var settings := get_node_or_null("/root/Config")
		if settings and "aids" in settings:          # ... unless the game's Settings switch some on
			for key in settings.aids:
				if key in assists:
					assists.set(key, bool(settings.aids[key]))
	if grip_assist < 0.0:
		var settings := get_node_or_null("/root/Config")
		grip_assist = float(settings.grip_assist) if settings and "grip_assist" in settings else 0.0
	assist = DriverAssist.new()
	assist.setup(assists)
	_mud = Surfaces.named("mud")
	mass = config.mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = config.center_of_mass
	inertia = config.inertia
	# no invented drag on the body: REPLACE the project's default damping with none
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	collision_layer = 2
	collision_mask = 1
	can_sleep = false
	var pm := PhysicsMaterial.new()
	pm.friction = 0.4                                # the body sliding on its roof / side
	pm.bounce = 0.05
	physics_material_override = pm
	if find_children("*", "CollisionShape3D", false, false).is_empty():
		_box("Body", config.body_size, config.body_center)
		_box("Cabin", config.cabin_size, config.cabin_center)
	var com_marker := get_node_or_null("CenterOfMass") as Node3D
	if com_marker == null:
		com_marker = Marker3D.new()
		com_marker.name = "CenterOfMass"
		add_child(com_marker)
	com_marker.position = config.center_of_mass
	var mounts: Array = config.mounts()
	for k in 4:
		var w = get_node_or_null(NAMES[k] + "_WheelPoint")
		if w == null:
			w = RallyWheel.new()
			w.name = NAMES[k] + "_WheelPoint"
			add_child(w)
		w.position = mounts[k]
		w.front = k < 2
		w.setup(self, config.front_suspension if k < 2 else config.rear_suspension,
			config.front_tire if k < 2 else config.rear_tire, config.tyre_radius, config.tyre_width, config.wheel_inertia)
		wheels.append(w)
	if config.drivetrain and config.engine:
		drivetrain = Drivetrain.new()
		drivetrain.setup(config.drivetrain, config.engine)
	telemetry = get_node_or_null("Telemetry")
	if telemetry == null:
		telemetry = Telemetry.new()
		telemetry.name = "Telemetry"
		add_child(telemetry)
	telemetry.car = self
	telemetry.visible = show_telemetry
	var loads: Array = config.static_loads(_gravity())
	_static_comp = [RallyWheel.Suspension.static_compression(config.front_suspension, loads[0]),
		RallyWheel.Suspension.static_compression(config.rear_suspension, loads[1])]
	_build_body_model(str(setup.get("body", "hatch")))
	if not setup.is_empty():
		apply_setup(setup)


func _box(n: String, size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = n
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = at
	add_child(cs)


## The outside of the car, from a Higgsfield model cut into parts (BODIES): the
## body, four wheels (turn, spin, ride the springs) and, as the body has them,
## four mud flaps (swing), see-through glass and a kidney grille. Only drawn
## when a camera is outside the car (the cockpit is the inside). Built again
## when the garage picks a car with another body. Model units: x = back, y = up,
## z = left.
func _build_body_model(id := "hatch") -> void:
	var dir: String = BODIES.get(id, BODIES.hatch)
	if not ResourceLoader.exists(dir + "body.res") or get_node_or_null("CarMesh"):
		return
	var shown := body_model != null and body_model.visible
	if body_model:
		remove_child(body_model)
		body_model.queue_free()
	_model_wheels.clear()
	_flaps.clear()
	body_id = id
	var info = JSON.parse_string(FileAccess.get_file_as_string(dir + "parts.json"))
	body_model = Node3D.new()
	body_model.name = "BodyModel"
	body_model.rotation.y = -PI / 2.0                    # the model's nose points down -X
	body_model.scale = Vector3.ONE * MODEL_SCALE          # model units -> m
	# its tyres on the ground with the car standing still, centred between the axles
	var ground: float = (config.front_suspension.travel + config.rear_suspension.travel) * 0.5 \
		- (_static_comp[0] + _static_comp[1]) * 0.5 + config.tyre_radius - config.mount_height
	var depth: float = info.get("tyre_depth", 0.205 + MODEL_GROUND)
	body_model.position = Vector3(0.0, depth - ground, (config.front_axle + config.rear_axle) * 0.5)
	body_model.visible = shown
	add_child(body_model)
	var body := MeshInstance3D.new()
	body.mesh = load(dir + "body.res")
	body_model.add_child(body)
	own_paint = info.get("own_paint", false)
	if own_paint:
		var src: Material = body.mesh.surface_get_material(0)
		var tex: Texture2D = src.albedo_texture if src is BaseMaterial3D else null
		if ResourceLoader.exists(dir + "paint.jpg"):              # the texture with stray marks painted out
			tex = load(dir + "paint.jpg")
		body.set_surface_override_material(0, _own_paint(tex))
	see_through = info.get("glass", false)
	if see_through:
		var glass := MeshInstance3D.new()
		glass.mesh = load(dir + "glass.res")
		glass.material_override = _glass()
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body_model.add_child(glass)
	if info.has("grille"):
		var g: Array = info.grille                        # [front x, centre y, height]
		var grille := MeshInstance3D.new()
		grille.mesh = KidneyGrille.build(float(g[2]) * 1.1)
		grille.position = Vector3(float(g[0]) - 0.003, float(g[1]), 0.0)
		body_model.add_child(grille)
	var names := ["fl", "fr", "rl", "rr"]                 # the same order as the wheels
	for k in 4:
		var c: Array = info.wheels[k]
		var pivot := Node3D.new()                        # moves with the spring, turns with the steering
		pivot.position = Vector3(c[0], c[1], c[2])
		body_model.add_child(pivot)
		var spinner := Node3D.new()                      # rolls
		pivot.add_child(spinner)
		# the wheel: built in code (wheel_mesh.gd), the model's own size; its axle is the model's z
		var wm := MeshInstance3D.new()
		var r: float = info.radius[k] if info.has("radius") else 0.17
		var w: float = float(info.width[k]) * 0.9 if info.has("width") else r * 0.66
		wm.mesh = WheelMesh.build(r, w, "z", int(info.get("spokes", WheelMesh.SPOKES)))
		spinner.add_child(wm)
		_model_wheels.append([pivot, spinner, pivot.position])
		if k >= info.flaps.size():
			continue
		var h: Array = info.flaps[k]
		var hinge := Node3D.new()
		hinge.position = Vector3(h[0], h[1], h[2])
		body_model.add_child(hinge)
		var fm := MeshInstance3D.new()
		fm.mesh = load(dir + "flap_%s.res" % names[k])
		hinge.add_child(fm)
		_flaps.append([hinge, 0.0, 0.0])                 # node, angle, angular speed


## A body in its own paint: its texture as it is, a touch deeper in the reds,
## both sides drawn (through the glass you see into it), the inside dark.
func _own_paint(tex: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
void fragment() {
	vec3 c = texture(tex, UV).rgb;
	float red = smoothstep(0.2, 0.45, c.r - max(c.g, c.b)) * step(0.2, c.g);
	c.g *= 1.0 - 0.35 * red;                  // the model's orange-ish red -> rally red
	ALBEDO = FRONT_FACING ? c : vec3(0.06);
	ROUGHNESS = FRONT_FACING ? 0.45 : 0.9;
}
"""
	m.shader = sh
	m.set_shader_parameter("tex", tex)
	return m


## Window glass: clear, a faint blue-grey tint, glossy.
static func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.55, 0.66, 0.74, 0.22)
	m.roughness = 0.04
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## The car from the garage (Catalog.setup): how it drives (x the base car's power,
## grip and brakes; the share of the drive to the front) and how it looks outside
## (Livery: paint, number, wheels).
func apply_setup(s: Dictionary) -> void:
	setup = s
	power_mult = float(s.get("power", 1.0))
	grip_mult = float(s.get("grip", 1.0))
	brake_mult = float(s.get("brakes", 1.0))
	if config == null or not is_node_ready():
		return                                         # (_ready applies it)
	if not _own_config:
		# this car's own numbers from now on (the profile is shared by every car)
		config = config.duplicate(true)
		_own_config = true
		_base = {"torque": config.engine.max_torque if config.engine else 0.0, "brakes": config.brake_torque,
			"front": config.drivetrain.front_share if config.drivetrain else 0.5}
		if drivetrain:
			drivetrain.cfg = config.drivetrain
			drivetrain.eng = config.engine
	if config.engine:
		config.engine.max_torque = _base.torque * power_mult
	config.brake_torque = _base.brakes * brake_mult
	if config.drivetrain:
		config.drivetrain.front_share = float(s.get("drive_front", _base.front))
	_tune(str(s.get("tyre", "gravel")), str(s.get("preset", "gravel")))
	for k in 4:
		wheels[k].surface_mu = lane_mu[k] * grip_mult
	if str(s.get("body", "hatch")) != body_id:
		_build_body_model(str(s.get("body", "hatch")))
	if body_model:
		if not own_paint:
			Livery.paint(body_model.get_child(0), [], s, self)
		var rim := StandardMaterial3D.new()             # the rims take the wheel colour
		rim.albedo_color = s.get("wheel_colour", Color(0.72, 0.73, 0.75))
		rim.metallic = 0.5
		rim.roughness = 0.35
		rim.cull_mode = BaseMaterial3D.CULL_DISABLED
		for mw in _model_wheels:
			((mw[1] as Node3D).get_child(0) as MeshInstance3D).set_surface_override_material(1, rim)


## The tyres and the setup (the garage's SETUP tab; "auto" is settled by the game
## for the stage before it gets here). Tarmac tyres: TireModel.tarmac_tyre; both
## kinds get the game's extra grip (grip_assist, from Settings: TireModel.grippy).
## A tarmac setup: springs x1.5, dampers x1.3, anti-roll bars x1.5 (it rolls and
## pitches less, turns in sharper), a rack a quarter quicker; the travel is
## shortened by what the stiffer springs no longer squash, so it stands at the
## same height with the same room to the bump stops.
func _tune(tyre: String, kind: String) -> void:
	tyre = "tarmac" if tyre == "tarmac" else "gravel"
	kind = "tarmac" if kind == "tarmac" else "gravel"
	if tyre == tyre_kind and kind == setup_kind and grip_assist == _tuned_grip:
		return
	_tuned_grip = grip_assist
	if _base_parts.is_empty():
		_base_parts = {"front": config.front_suspension, "rear": config.rear_suspension, "ft": config.front_tire,
			"rt": config.rear_tire, "rack": config.steering.rack_speed_deg if config.steering else 0.0,
			"ft_tarmac": RallyWheel.TireModel.tarmac_tyre(config.front_tire),
			"rt_tarmac": RallyWheel.TireModel.tarmac_tyre(config.rear_tire)}
	tyre_kind = tyre
	setup_kind = kind
	var loads: Array = config.static_loads(_gravity())
	var sus: Array = []
	for k in 2:
		var base: Resource = _base_parts.front if k == 0 else _base_parts.rear
		var t: Resource = base
		if kind == "tarmac":
			t = base.duplicate()
			t.spring_rate = base.spring_rate * 1.5
			for f in ["bump_damping", "rebound_damping", "high_speed_bump", "high_speed_rebound"]:
				t.set(f, float(base.get(f)) * 1.3)
			t.anti_roll_rate = base.anti_roll_rate * 1.5
			var dc: float = RallyWheel.Suspension.static_compression(base, loads[k]) - RallyWheel.Suspension.static_compression(t, loads[k])
			t.travel = base.travel - dc
			t.bump_stop_start = base.bump_stop_start - dc
		sus.append(t)
	config.front_suspension = sus[0]
	config.rear_suspension = sus[1]
	var TM = RallyWheel.TireModel
	config.front_tire = TM.grippy(_base_parts.ft_tarmac if tyre == "tarmac" else _base_parts.ft, grip_assist)
	config.rear_tire = TM.grippy(_base_parts.rt_tarmac if tyre == "tarmac" else _base_parts.rt, grip_assist)
	if config.steering:
		config.steering.rack_speed_deg = _base_parts.rack * (1.25 if kind == "tarmac" else 1.0)
	for k in 4:
		wheels[k].setup(self, config.front_suspension if k < 2 else config.rear_suspension,
			config.front_tire if k < 2 else config.rear_tire, config.tyre_radius, config.tyre_width, config.wheel_inertia)
	_static_comp = [RallyWheel.Suspension.static_compression(config.front_suspension, loads[0]),
		RallyWheel.Suspension.static_compression(config.rear_suspension, loads[1])]


## Put the car down at (pos, yaw), still, sitting at its ride height above pos.
func place(pos: Vector3, yaw: float) -> void:
	global_transform = Transform3D(Basis(Vector3.UP, -yaw), pos + Vector3.UP * ride_height())
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_v = Vector3.ZERO
	_rack = 0.0                                      # wheels straight (a car put down doesn't keep its old lock)
	inp.steer = 0.0
	_steer(0.0)
	for w in wheels:
		w.reset()
	if drivetrain:
		drivetrain.reset()
	if assist:
		assist.reset()
	reset_physics_interpolation()


## Set it rolling straight ahead at v m/s, the wheels turning with it (a car
## launched with still wheels would skid them up to speed first).
func set_speed(v: float) -> void:
	linear_velocity = -global_transform.basis.z * v
	_prev_v = linear_velocity
	for w in wheels:
		w.omega = v / w.radius


## How high the mounts sit above flat ground with the car standing still (m),
## from the springs and the weight on them.
func ride_height() -> float:
	_load_config()
	var loads: Array = config.static_loads(_gravity())
	var Suspension = RallyWheel.Suspension
	var c: float = (Suspension.static_compression(config.front_suspension, loads[0])
		+ Suspension.static_compression(config.rear_suspension, loads[1])) * 0.5
	var travel: float = (config.front_suspension.travel + config.rear_suspension.travel) * 0.5
	return config.tyre_radius + travel - c - config.mount_height


## A camera outside the car: draw the body model (its own wheels), not the plain tyres.
func set_outside(on: bool) -> void:
	if body_model == null:
		return
	body_model.visible = on
	for w in wheels:
		w.mesh.visible = not on


func set_simulating(on: bool) -> void:
	simulate = on
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = not on


## Where each tyre is on the road (car at road position s, d) -> its grip: on
## gravel the clean wheel tracks or the loose stuff, on asphalt the same all
## across (stage_gen.lane_mu).
func set_lanes(stage, s: float, d: float) -> void:
	var right: Vector3 = stage.right_at(s)
	var fwd: Vector3 = stage.forward_at(s)
	for k in 4:
		var off: Vector3 = wheels[k].global_position - global_position
		lane_mu[k] = stage.lane_mu(s + off.dot(fwd), d + off.dot(right))
		var cut := 0.6 if _tuned_grip >= RallyWheel.TireModel.ARCADE else 0.4 * clampf(_tuned_grip, 0.0, 1.0)
		lane_mu[k] = 1.0 - (1.0 - lane_mu[k]) * (1.0 - cut)   # (extra grip: the loose stuff costs less)
		wheels[k].surface_mu = lane_mu[k] * grip_mult


## Is the handbrake on? (the driver's input; on the co-driver's machine, from the stream)
func handbrake_on() -> bool:
	return bool(inp.handbrake) if simulate else _net_handbrake


func kmh() -> float:
	return absf(speed) * 3.6


## Where tyre k touches the ground (world; in the air: where it would, at full droop).
func contact_point(k: int) -> Vector3:
	var w = wheels[k]
	return w.global_position - global_transform.basis.y * (w.cfg.travel - comp[k] + w.radius)


func _physics_process(dt: float) -> void:
	if simulate:
		_simulate(dt)
		_net_acc += dt
		if _net_acc >= 1.0 / NET_HZ and stream_ok and _online():
			_net_acc = 0.0
			net_state.rpc(Time.get_ticks_msec(), global_position, global_transform.basis.get_rotation_quaternion(),
				linear_velocity, steer, rpm, gear, PackedFloat32Array(comp), slip, on_surface, bool(inp.handbrake),
				clampf(float(inp.throttle), 0.0, 1.0))
	else:
		_play_stream(dt)
	_flaps_swing(dt)


# ── the simulation (driver's machine) ─────────────────────────────────────

func _simulate(dt: float) -> void:
	speed = linear_velocity.dot(-global_transform.basis.z)
	accel = (linear_velocity - _prev_v) / dt
	var v_before := _prev_v
	_prev_v = linear_velocity
	_steer(dt)
	var pedals := _pedals(dt)
	var foot := pedals.x
	pedals.x = assist.throttle(self, dt, pedals.x)
	_brakes(dt, pedals.y)
	var was := grounded
	grounded = 0
	for w in wheels:
		w.surface_override = _mud if mud_mu else null
		w.step(dt)
	_anti_roll()
	var count := {}
	for k in 4:
		var w = wheels[k]
		w.settle()
		comp[k] = w.compression
		if w.grounded:
			grounded += 1
			var n: String = w.surface.display_name
			count[n] = count.get(n, 0) + 1
	var most := 0
	for n in count:                                  # what most of the tyres are on
		if count[n] > most:
			most = count[n]
			on_surface = n
	if drivetrain:
		drivetrain.control(dt, pedals.x, wheels, foot)
	var spin_before: Array = []
	for w in wheels:
		spin_before.append(w.omega)
	var h := dt / SUBSTEPS
	for i in SUBSTEPS:
		for w in wheels:
			w.tyre_predict(h)
		if drivetrain:
			drivetrain.solve(h, wheels)
		else:
			_free_wheels(h)
		for w in wheels:
			w.tyre_finalize(h)
	for w in wheels:
		w.apply_forces(dt)
	# what the engine and brakes do to a wheel's spin, the body gets back the other way
	# round its axle (the tyre's own part is already in its force at the patch): brake
	# in the air and the wheels hand their spin to the body, so the nose dips
	var react := Vector3.ZERO
	for k in 4:
		var w = wheels[k]
		react += w.global_transform.basis.x * (w.inertia * (w.omega - spin_before[k]) / dt)
	apply_torque(react)
	apply_torque(global_transform.basis.y * assist.drift_torque(self))   # (drift assist: a slide held at its angle)
	_tip_guard()
	_aero()
	slip = _slip()
	if drivetrain:
		gear = drivetrain.gear
		var e: Resource = config.engine
		rpm = clampf((drivetrain.rpm() - e.idle_rpm) / (e.limiter_rpm - e.idle_rpm), 0.0, 1.0)
	if grounded == 0:
		_air += dt
	else:
		if was == 0 and _air > 0.25:
			landed.emit(maxf(-linear_velocity.y, 0.0))
		_air = 0.0
	# hits: a sudden loss of speed the tyres didn't do (240 m/s² and more, sideways
	# and along: a tree, a rail, a wall)
	var dv := v_before - linear_velocity
	dv.y = 0.0
	if dv.length() > 240.0 * dt and v_before.length() > 6.0:
		hit.emit(dv.length())


## How hard the tyres are sliding, 0..1 (the sound and the dust): each tyre past
## its grip's peak (forwards and sideways together, in "peaks"), and sideways speed.
func _slip() -> float:
	var acc := 0.0
	for w in wheels:
		if not w.grounded:
			continue
		var t: Resource = w.surface_tire
		var sx: float = absf(w.slip_long) / t.longitudinal_peak
		var sy: float = absf(w.slip_angle_deg()) / t.lateral_peak_deg
		acc += clampf((sqrt(sx * sx + sy * sy) - 0.8) / 1.2, 0.0, 1.0)
		acc += clampf(absf(w.v_lat) / 7.0, 0.0, 1.0) * 0.5
	return clampf(acc / 2.0, 0.0, 1.0)


## The pedals as (throttle, brake). Stopped and holding the brake (off the
## throttle) for a moment selects reverse; in reverse the brake pedal drives it
## backwards and the throttle brakes, until it's stopped and the throttle picks first.
func _pedals(dt: float) -> Vector2:
	var thr := clampf(float(inp.throttle), 0.0, 1.0)
	var brk := clampf(float(inp.brake), 0.0, 1.0)
	if drivetrain == null:
		return Vector2(thr, brk)
	if drivetrain.gear >= 0:
		var stopped_in_gear: bool = drivetrain.gear >= 1 and absf(speed) < 0.5   # (not from neutral)
		_reverse_t = _reverse_t + dt if brk > 0.5 and thr < 0.05 and stopped_in_gear and not bool(inp.handbrake) else 0.0
		if _reverse_t > 0.35:
			drivetrain.shift(-1)
			_reverse_t = 0.0
		return Vector2(thr, brk)
	if thr > 0.05 and speed > -0.5:
		drivetrain.shift(1)
		return Vector2(thr, 0.0)
	return Vector2(brk, thr)


## Without a drivetrain: just the brakes and rolling resistance on each wheel.
func _free_wheels(h: float) -> void:
	for w in wheels:
		var stop: float = h * w.resist_torque
		var n: float = w.omega * w.i_eff
		w.omega = 0.0 if absf(n) <= stop else (n - signf(n) * stop) / w.i_eff


## The pedal: the brakes' torque, split front / rear by the bias, left / right
## evenly; and the hydraulic handbrake on the rears (its lever also lets the rear
## axle's drive go, if the drivetrain has that clutch).
func _brakes(dt: float, pedal: float) -> void:
	var hb := clampf(float(inp.handbrake), 0.0, 1.0)
	var front: float = config.brake_torque * config.brake_bias * 0.5 * pedal
	var rear: float = config.brake_torque * (1.0 - config.brake_bias) * 0.5 * pedal
	var t: Array = assist.brakes(self, dt, [front, front, rear, rear])   # (ABS, stability control)
	for k in 4:
		wheels[k].brake_torque = t[k] + (config.handbrake_torque * 0.5 * hb if k >= 2 else 0.0)
	if drivetrain:
		drivetrain.handbrake = hb


## The air: drag against the motion (at the centre of mass), downforce at each axle.
func _aero() -> void:
	var drag := Aero.drag(config, linear_velocity)
	apply_central_force(drag)
	aero_drag = drag.length()
	aero_down = Aero.downforce(config, speed)
	var b := global_transform.basis
	var down := -b.y
	var h: float = config.center_of_mass.y
	apply_force(down * aero_down.x, b * Vector3(0.0, h, config.front_axle))
	apply_force(down * aero_down.y, b * Vector3(0.0, h, config.rear_axle))


## The tip guard (extra grip only, Settings > TYRE GRIP above REAL): the extra
## grip lets the tyres corner harder (up to ~1.9 g on tarmac tyres) than the
## car's track and centre of mass can take before it tips (~1.6 g), so a hard
## flick or catch rolled it. With a wheel off the ground and the body tipped
## more than TIP_FROM to the ground under it, a torque round its length puts it
## back down (and damps the tipping), as a lower-slung arcade car would stay
## down. In the air (no wheel down) it leaves alone: jumps land as they land.
const TIP_FROM := deg_to_rad(5.0)
const TIP_RATE := 30000.0          # N m per rad tipped past TIP_FROM
const TIP_DAMP := 6000.0           # N m per rad/s tipping further
const TIP_MAX := 14000.0           # N m at most

func _tip_guard() -> void:
	if _tuned_grip <= 0.0 or grounded == 0 or grounded == 4:
		return
	var n := Vector3.ZERO
	for w in wheels:
		if w.grounded:
			n += w.normal
	n = n.normalized()
	var b := global_transform.basis
	var tip := asin(clampf(b.x.dot(n), -1.0, 1.0))  # + = the right side up
	if absf(tip) < TIP_FROM:
		return
	var fwd := -b.z
	var rate := -angular_velocity.dot(fwd)            # rad/s the right side's rising
	var t := TIP_RATE * (absf(tip) - TIP_FROM) + TIP_DAMP * maxf(rate * signf(tip), 0.0)
	apply_torque(fwd * signf(tip) * minf(t, TIP_MAX))  # (+ round the nose: the right side down)


## The anti-roll bars: each axle's bar pushes its more squashed corner up and pulls
## the other down, by its rate x the difference in squash. With one wheel in the
## air the bar lifts that light wheel into its arch until its spring balances the
## bar, so the bar carries only what that spring can.
func _anti_roll() -> void:
	for pair in [[0, 1], [2, 3]]:
		var a = wheels[pair[0]]
		var b = wheels[pair[1]]
		var k: float = a.cfg.anti_roll_rate
		var f := 0.0
		if a.grounded and b.grounded:
			f = k * (a.compression - b.compression)
		elif a.grounded:
			f = k * a.compression * b.cfg.spring_rate / (b.cfg.spring_rate + k)
		elif b.grounded:
			f = -k * b.compression * a.cfg.spring_rate / (a.cfg.spring_rate + k)
		a.anti_roll = f
		b.anti_roll = -f


## The rack follows the input (no faster than rack_speed); each front wheel's
## angle from the geometry: with full Ackermann the inside wheel turns more, so
## both roll round the same centre (on the rear axle's line).
func _steer(dt: float) -> void:
	if wheels.size() != 4:                           # not set up yet (placed before it's in the tree)
		return
	var st: Resource = config.steering
	var want: Vector2 = assist.steering(self, dt, clampf(float(inp.steer), -1.0, 1.0))   # (input x lock, unless an aid helps)
	_rack = move_toward(_rack, want.x, deg_to_rad(st.rack_speed_deg) * want.y * dt)
	steer = _rack
	_wheel_angles()


func _wheel_angles() -> void:
	var a := absf(steer)
	var inner := a
	var outer := a
	if a > 1e-4:
		var base: float = config.rear_axle - config.front_axle
		var r := base / tan(a)                       # the turn's radius at the rear axle's middle
		var half: float = config.front_track * 0.5
		inner = lerpf(a, atan(base / (r - half)), config.steering.ackermann)
		outer = lerpf(a, atan(base / (r + half)), config.steering.ackermann)
	var s := signf(steer)
	# turning right (+), the right wheel (FR) is on the inside
	wheel_angles = [s * (outer if s > 0.0 else inner), s * (inner if s > 0.0 else outer)]
	for k in 2:
		wheels[k].rotation.y = -wheel_angles[k]      # + steer = right = clockwise from above


# ── the stream (co-driver's machine) ──────────────────────────────────────

@rpc("any_peer", "unreliable_ordered")
func net_state(t: int, pos: Vector3, rot: Quaternion, vel: Vector3, st: float, r: float, g: int,
		c: PackedFloat32Array, sl: float, surf: String, hb: bool, thr: float) -> void:
	if simulate:
		return
	states_received += 1
	var now := Time.get_ticks_msec()
	_offset = minf(_offset + 0.5, float(now - t))      # creep up slowly, snap down to the fastest packet
	_buf.append({"t": float(t), "pos": pos, "rot": rot, "vel": vel, "steer": st, "rpm": r, "gear": g,
		"comp": c, "slip": sl, "surf": surf, "hb": hb, "thr": thr})
	while _buf.size() > 40:
		_buf.pop_front()


func _play_stream(dt: float) -> void:
	if _buf.is_empty():
		return
	var render_t := Time.get_ticks_msec() - _offset - NET_DELAY
	var a: Dictionary = _buf[0]
	var b: Dictionary = _buf[_buf.size() - 1]
	for i in range(_buf.size() - 1):
		if _buf[i].t <= render_t and _buf[i + 1].t >= render_t:
			a = _buf[i]
			b = _buf[i + 1]
			break
	var pos: Vector3
	var rot: Quaternion
	if render_t >= b.t:                                # ran out: extrapolate a little
		var ahead := minf((render_t - b.t) / 1000.0, 0.15)
		pos = b.pos + b.vel * ahead
		rot = b.rot
		a = b
	else:
		var u := clampf((render_t - a.t) / maxf(b.t - a.t, 1.0), 0.0, 1.0)
		pos = a.pos.lerp(b.pos, u)
		rot = a.rot.slerp(b.rot, u)
	global_transform = Transform3D(Basis(rot), pos)
	linear_velocity = a.vel
	steer = a.steer
	rpm = a.rpm
	gear = a.gear
	slip = a.slip
	on_surface = a.surf
	_net_handbrake = a.hb
	net_throttle = a.thr
	speed = a.vel.dot(-global_transform.basis.z)
	_wheel_angles()
	for k in 4:
		comp[k] = a.comp[k] if a.comp.size() > k else comp[k]
		wheels[k].show_remote(comp[k], speed, dt)


func _online() -> bool:
	var net := get_node_or_null("/root/Net")
	return net != null and net.online()


# ── the look ──────────────────────────────────────────────────────────────

func _process(dt: float) -> void:
	for k in 4:
		wheels[k].update_visual(dt)
	if body_model == null or not body_model.visible:
		return
	# the model's wheels: up and down with the spring (it was modelled sitting at its
	# static squash), turned by the steering, rolling (its axle is the model's z)
	for k in 4:
		var mw: Array = _model_wheels[k]
		var rest_at: Vector3 = mw[2]
		mw[0].position.y = rest_at.y + (comp[k] - _static_comp[0 if k < 2 else 1]) / MODEL_SCALE
		mw[0].rotation.y = -wheel_angles[k] if k < 2 else 0.0
		mw[1].rotation.z = wheels[k].spin


## The mud flaps: hanging pendulums. Speed blows them back, braking swings them
## forward, acceleration back, bumps set them flapping.
func _flaps_swing(dt: float) -> void:
	if body_model == null or not body_model.visible:
		_flap_prev_v = linear_velocity
		return
	var acc := (linear_velocity - _flap_prev_v) / maxf(dt, 1e-4)
	_flap_prev_v = linear_velocity
	var local_acc: Vector3 = global_transform.basis.inverse() * acc
	var fwd_acc := -local_acc.z
	var blow := clampf(speed * speed * 0.00025, 0.0, 0.7)     # ~0.3 rad at 100 km/h
	for f in _flaps:
		var ang: float = f[1]
		var vel: float = f[2]
		vel += (-40.0 * (ang - blow) - 4.0 * vel + fwd_acc * 0.9 + randf_range(-1.0, 1.0) * absf(local_acc.y) * 0.6) * dt
		ang = clampf(ang + vel * dt, -0.7, 1.1)
		f[1] = ang
		f[2] = vel
		(f[0] as Node3D).rotation.z = ang


## The CarConfig, the default profile if none was given (place() can come before _ready).
func _load_config() -> void:
	if config == null:
		config = load(DEFAULT_CONFIG)


func _gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
