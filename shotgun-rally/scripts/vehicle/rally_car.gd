extends RigidBody3D
## The rally car: a rigid body on four raycast springs (not BAGHOLDERS' highway
## CharacterBody: a rally car has to jump, land, slide and roll).
##   * each corner casts a ray down; the spring + damper push the body up at
##     the contact point, an anti-roll bar shares the load across each axle.
##     The tyre forces act at the contact patches, so braking really loads the
##     nose and a hard left really loads the right side (weight transfer)
##   * each tyre's grip is mu x load, and mu drops a little as the load goes up
##     (load sensitivity): weight transfer changes which end grips. A loaded
##     nose bites (lift off / brake into a bend and the car turns in), a light
##     tail lets go
##   * sideways force from the slip angle on a Magic Formula curve: it builds
##     to a peak (later and softer on gravel than on tarmac) and then only fades
##     slowly, so a slide is something you drive, not something that happens.
##     Forward force (engine / brakes) and sideways share one friction circle:
##     too much throttle in a bend and the tyres that are driven let go
##   * four-wheel drive split 45 / 55 front / rear; the handbrake locks the
##     rears and declutches them (all the power to the front, like a Rally2
##     car): a locked tyre slides along its own velocity, so the tail comes
##     round (the hairpin flick)
##   * steering, at speed, asks the front tyres for a slip angle: full steering
##     is the most grip they have, wherever the car is pointing (on keys there's
##     no way to hold the wheel just short of the limit, so the car does it).
##     Opposite steering in a slide is the most countersteer. At parking speeds
##     it's plain wheel angle
##   * in the air the body turns gently toward the slope it's about to land on
##     (a driver's feel, a little assist), and the pedals pitch it like a real
##     car's: brake = the wheels stop and hand their spin to the body (nose
##     down), gas = the wheels spin up and the body pitches back (nose up)
## The machine of whoever is DRIVING simulates it (`simulate`) and streams its
## state ~30x a second; the co-driver's machine plays that stream back 100 ms
## behind, smoothly (snapshot interpolation), so the cabin never jitters.
##
## The car faces -Z. Origin = the middle of the chassis at wheel-mount height.

signal hit(impact: float)          # ran into something (m/s of speed lost)
signal landed(impact: float)       # came down from a jump (m/s downward)

const WHEELS := [                  # x, z, front
	[-0.76, -1.22, true], [0.76, -1.22, true], [-0.76, 1.18, false], [0.76, 1.18, false]]
const REST := 0.36                 # spring travel (m)
const RADIUS := 0.31               # tyre radius (m)
const SPRING := 26000.0            # N/m per corner
const DAMP := 3000.0               # N per m/s, the spring squashing (bump)
const DAMP_REBOUND := 4200.0       # ... and stretching back (rebound): stiffer, so it settles instead of bouncing
const BUMP_STOP := 0.24            # past this compression the (progressive, hydraulic) bump stop joins in
const BUMP_RATE := 1.1e6           # N per m^2 past it: soft at first, firm deep in (lands jumps without a slam)
const BUMP_DAMP := 5000.0          # N per m/s extra while on it, squashing (it soaks the landing up)
const DEEP_REBOUND := 2.0          # x more rebound damping deep in the travel (position-sensitive, like a
                                   # rally damper): a big landing settles instead of springing the car off
const BUMP_RETURN := 0.35          # ... and on the way back out it gives back only this much (hydraulic:
                                   # the landing is soaked up, not thrown back: one squash, no second hop)
const TYRE_GIVE := 0.035           # s: how quickly the tyre passes a step in the ground on to the spring
const ANTI_ROLL_F := 7000.0        # N per m of left/right difference (more at the back: a car that turns)
const ANTI_ROLL_R := 13000.0
const CAR_MASS := 1150.0
const ENGINE_FORCE := 8200.0       # at the wheels, low speed (N)
const POWER := 170000.0            # W (~230 hp): above ~20 m/s the force is POWER / speed
const V_MAX := 47.0                # rev limiter in 5th (m/s, 170 km/h)
const REVERSE_MAX := 8.0
const BRAKE_FORCE := 11500.0       # total (N)
const BRAKE_FRONT := 0.7           # of it on the front axle (the nose is loaded when braking)
const DRIVE_FRONT := 0.45          # AWD split (a Rally2 car is a locked 50 / 50; a bit more rear here)
const DRAG := 0.46                 # N per (m/s)^2
const ROLLING := 0.022             # rolling resistance, x the load
const STEER_LOCK := 0.58           # front wheels at full lock (rad, 33 deg): parking speeds
const STEER_RATE := 4.0            # how fast the front wheels can turn (rad/s, at the road)
const KEY_ON := 6.0                # keys: steering builds this fast (full in ~0.17 s) ...
const KEY_OFF := 8.0               # ... and comes back this fast
## Tyres. Peak slip angle (rad) per surface: on loose gravel the tyre plows a
## little bank of stones, so it peaks later and fades more gently than on tarmac.
const PEAK := {"gravel": 0.14, "dirt": 0.14, "grass": 0.17, "mud": 0.19, "tarmac": 0.1}
const SLIP_PEAK := 0.14            # gravel (the autopilot and the HUD use it)
const SHAPE_C := 1.35              # Magic Formula C: past the peak it fades slowly (94 % at 3x the peak, 85 % at most)
const GRIP := {"gravel": 1.1, "dirt": 1.05, "grass": 0.7, "mud": 0.55, "tarmac": 1.25}
const LOAD_SENS := 0.15            # mu drops 15 % per extra static load (a loaded tyre grips less per newton)
const RELAX := 0.4                 # m: a tyre rolls this far before its side force catches up with a new slip angle
const LOCKED_MU := 0.82            # a locked (handbraked) tyre slides at this much of its grip
const GEARS := [13.0, 21.0, 29.0, 37.0, 47.0]   # top speed in each gear (m/s)
## In the air. Four wheels at 110 km/h carry ~480 N m s of spin: stopping them
## (brakes) tips a 1800 kg m^2 body nose-down ~10 deg over a 1 s jump
const AIR_LEVEL := 1500.0          # N m per rad toward the ground below (was 2600 toward flat)
const AIR_DAMP := 320.0            # N m per rad/s
const AIR_BRAKE := 900.0           # N m nose-down, full brake
const AIR_GAS := 450.0             # N m nose-up, full gas
const PARTS := "res://assets/models/car_parts/"
const MODEL_SCALE := 1.95          # model units -> m
const STATIC_COMP := 0.11          # spring squash sitting still (m): where the model's wheels were modelled
const NET_HZ := 30.0
const NET_DELAY := 100.0           # ms behind the stream on the co-driver's machine

## Driver inputs: steer -1..1 (+ = right), throttle 0..1, brake 0..1, handbrake.
var inp := {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": false}
var analog_steer := false          # controller: no easing
var simulate := true
var stream_ok := true              # the game turns this off until both machines have loaded
var states_received := 0           # co-driver side: stream packets in (tests)
var steer := 0.0                   # front wheel angle (rad, + = right)
var speed := 0.0                   # along the car (m/s, + = forward)
var gear := 1
var rpm := 0.0                     # 0..1 through the current gear
var slip := 0.0                    # 0..1, how hard the tyres are sliding (audio)
var on_surface := "gravel"         # what most of the tyres are on
var grounded := 0                  # tyres touching
var comp := [0.0, 0.0, 0.0, 0.0]   # spring compression per corner (m)
var spin := [0.0, 0.0, 0.0, 0.0]   # wheel rotation (rad), for the visuals
var mud_mu := false                # set by the game while a tyre is in a puddle
var wheel_nodes: Array = []        # Node3D per corner (steer + spin pivots)
var body_model: Node3D             # the Higgsfield car (assets/models/car_parts/): seen from outside
var _model_wheels: Array = []      # [pivot, spinner, rest position] per corner (model units)
var _flaps: Array = []             # [hinge, angle, angular speed] per corner
var _flap_prev_v := Vector3.ZERO
var _net_handbrake := false

var _prev_v := Vector3.ZERO
var _u := 0.0                      # steering input after the key easing
var _fz0 := CAR_MASS * 9.8 / 4.0   # static load per tyre (N)
var _alpha := [0.0, 0.0, 0.0, 0.0] # slip angle each tyre is "at" (lags the real one by RELAX)
var _brake_held := 0.0
var _air_time := 0.0
var _net_acc := 0.0
var _buf: Array = []               # [{t, pos, rot, vel, steer, rpm, gear, comp, slip, surf}]
var _offset := INF                 # local ms - sender ms (latency + clock difference)


func _ready() -> void:
	mass = CAR_MASS
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.04, -0.12)   # engine up front, like a real hatchback
	inertia = Vector3(1800.0, 2100.0, 560.0)
	# REPLACE, not the default COMBINE: the project's default damping (0.1) would add a
	# ~v x 115 N drag on top of the real one and cap the car below 90 km/h
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.4
	collision_layer = 2
	collision_mask = 1
	contact_monitor = false
	can_sleep = false
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	pm.bounce = 0.05
	physics_material_override = pm
	_box(Vector3(1.62, 0.9, 3.7), Vector3(0.0, 0.32, 0.0))      # body
	_box(Vector3(1.36, 0.42, 1.9), Vector3(0.0, 0.98, 0.18))    # cabin (rollovers land on the roof)
	for k in 4:
		var pivot := Node3D.new()
		pivot.position = Vector3(WHEELS[k][0], -REST * 0.7, WHEELS[k][1])
		add_child(pivot)
		var tyre := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = RADIUS
		cyl.bottom_radius = RADIUS
		cyl.height = 0.22
		cyl.radial_segments = 10
		cyl.rings = 1
		tyre.mesh = cyl
		tyre.rotation.z = PI / 2.0
		tyre.material_override = _flat(Color(0.12, 0.12, 0.13))
		var spinner := Node3D.new()
		spinner.name = "Spin"
		pivot.add_child(spinner)
		spinner.add_child(tyre)
		var hub := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = RADIUS * 0.55
		hm.bottom_radius = RADIUS * 0.55
		hm.height = 0.23
		hm.radial_segments = 6
		hm.rings = 1
		hub.mesh = hm
		hub.rotation.z = PI / 2.0
		hub.material_override = _flat(Color(0.85, 0.85, 0.8))
		spinner.add_child(hub)
		wheel_nodes.append(pivot)
	_build_body_model()


## The outside of the car, from the Higgsfield model cut into parts by
## tools/split_car.gd: the body, four wheels (turn, spin, ride the springs) and
## four mud flaps (swing). Only drawn when a camera is outside the car: the
## cockpit is the inside. Model units: x = back, y = up, z = left.
func _build_body_model() -> void:
	if not ResourceLoader.exists(PARTS + "body.res"):
		return
	var info = JSON.parse_string(FileAccess.get_file_as_string(PARTS + "parts.json"))
	body_model = Node3D.new()
	body_model.rotation.y = -PI / 2.0                    # the model's nose points down -X
	body_model.scale = Vector3.ONE * MODEL_SCALE          # its 1.9 units long -> 3.7 m, like the body box
	body_model.position = Vector3(0.0, 0.205, -0.02)     # its tyres on the ground, centred on the axles
	body_model.visible = false
	add_child(body_model)
	var body := MeshInstance3D.new()
	body.mesh = load(PARTS + "body.res")
	body_model.add_child(body)
	var names := ["fl", "fr", "rl", "rr"]                 # the same order as WHEELS
	for k in 4:
		var c: Array = info.wheels[k]
		var pivot := Node3D.new()                        # moves with the spring, turns with the steering
		pivot.position = Vector3(c[0], c[1], c[2])
		body_model.add_child(pivot)
		var spinner := Node3D.new()                      # rolls
		pivot.add_child(spinner)
		var wm := MeshInstance3D.new()
		wm.mesh = load(PARTS + "wheel_%s.res" % names[k])
		spinner.add_child(wm)
		var h: Array = info.flaps[k]
		var hinge := Node3D.new()
		hinge.position = Vector3(h[0], h[1], h[2])
		body_model.add_child(hinge)
		var fm := MeshInstance3D.new()
		fm.mesh = load(PARTS + "flap_%s.res" % names[k])
		hinge.add_child(fm)
		_model_wheels.append([pivot, spinner, pivot.position])
		_flaps.append([hinge, 0.0, 0.0])                 # node, angle, angular speed


func _box(size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = at
	add_child(cs)


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


## Put the car on the road at (pos, yaw), still.
func place(pos: Vector3, yaw: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, -yaw), pos + Vector3.UP * (RADIUS + REST * 0.75))
	global_transform = xf
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_v = Vector3.ZERO
	steer = 0.0
	_u = 0.0
	_alpha = [0.0, 0.0, 0.0, 0.0]
	reset_physics_interpolation()


## A camera outside the car: draw the body model (its own wheels), not the plain tyres.
func set_outside(on: bool) -> void:
	if body_model == null:
		return
	body_model.visible = on
	for w in wheel_nodes:
		w.visible = not on


func set_simulating(on: bool) -> void:
	simulate = on
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = not on


## Is the handbrake on? (the driver's input; on the co-driver's machine, from the stream)
func handbrake_on() -> bool:
	return bool(inp.handbrake) if simulate else _net_handbrake


func kmh() -> float:
	return absf(speed) * 3.6


func _physics_process(dt: float) -> void:
	if simulate:
		_drive(dt)
		_net_acc += dt
		if _net_acc >= 1.0 / NET_HZ and Net.online() and stream_ok:
			_net_acc = 0.0
			net_state.rpc(Time.get_ticks_msec(), global_position, global_transform.basis.get_rotation_quaternion(),
				linear_velocity, steer, rpm, gear, PackedFloat32Array(comp), slip, on_surface, inp.handbrake)
	else:
		_play_stream()
	_wheel_visuals(dt)


# ── the simulation (driver's machine) ─────────────────────────────────────

func _drive(dt: float) -> void:
	var space := get_world_3d().direct_space_state
	var xf := global_transform
	var up := xf.basis.y
	var fwd := -xf.basis.z
	var v := linear_velocity
	speed = v.dot(fwd)
	var vabs := absf(speed)

	# steering (see the top): the stick / keys, eased on keys
	var u_target: float = clampf(inp.steer, -1.0, 1.0)
	if analog_steer:
		_u = lerpf(_u, u_target, clampf(dt * 20.0, 0.0, 1.0))
	else:
		var building := absf(u_target) > absf(_u) and signf(u_target) == signf(_u)
		_u = move_toward(_u, u_target, (KEY_ON if building or _u == 0.0 else KEY_OFF) * dt)
	steer = move_toward(steer, steer_target(_u, vabs, on_surface), STEER_RATE * dt)
	# what the driver asks for: drive force (+ forward / - reverse) and brake
	var throttle: float = inp.throttle
	var brake: float = inp.brake
	var drive := 0.0
	# reverse = keep holding the brake once stopped (not with the handbrake on: parked)
	if brake > 0.1 and throttle < 0.1 and speed < 1.0 and not inp.handbrake:
		_brake_held += dt
	else:
		_brake_held = 0.0
	if _brake_held > 0.35:
		drive = -brake * 3600.0 if speed > -REVERSE_MAX else 0.0     # reversing
		brake = 0.0
	elif throttle > 0.0 and speed < -1.0:
		brake = maxf(brake, throttle)                               # moving back + gas: brake first
		throttle = 0.0
	if throttle > 0.0 and speed < V_MAX:
		drive = throttle * minf(ENGINE_FORCE, POWER / maxf(vabs, 1.0))

	# rays
	var hits: Array = []
	var surf_count := {}
	grounded = 0
	for k in 4:
		var mount: Vector3 = xf * Vector3(WHEELS[k][0], 0.0, WHEELS[k][1])
		var q := PhysicsRayQueryParameters3D.create(mount, mount - up * (REST + RADIUS), 1, [get_rid()])
		var h := space.intersect_ray(q)
		if h.is_empty():
			hits.append({})
			comp[k] = move_toward(comp[k], 0.0, dt * 2.0)
			continue
		var raw: float = REST + RADIUS - mount.distance_to(h.position)
		# the tyre's own give: it soaks up the little kinks in the road surface (the
		# ground is flat panels; without this every joint is a jolt through the seat)
		var c: float = raw if comp[k] <= 0.0 else lerpf(comp[k], raw, clampf(dt / TYRE_GIVE, 0.0, 1.0))
		var surf: String = "gravel"
		if h.collider and h.collider.has_meta("surface"):
			surf = h.collider.get_meta("surface")
		if mud_mu:
			surf = "mud"
		surf_count[surf] = surf_count.get(surf, 0) + 1
		hits.append({"pos": h.position, "n": h.normal, "c": c, "cv": (c - comp[k]) / dt, "surf": surf})
		comp[k] = c
		grounded += 1
	if not surf_count.is_empty():
		var best := 0
		for s in surf_count:
			if surf_count[s] > best:
				best = surf_count[s]
				on_surface = s

	var slip_acc := 0.0
	for k in 4:
		var h: Dictionary = hits[k]
		if h.is_empty():
			continue
		var front: bool = WHEELS[k][2]
		var mate := k ^ 1                                           # the other wheel on this axle
		var rebound: float = DAMP_REBOUND * (1.0 + DEEP_REBOUND * smoothstep(0.16, 0.3, h.c))
		var fz: float = SPRING * h.c + (DAMP if h.cv > 0.0 else rebound) * h.cv
		if h.c > BUMP_STOP:
			var into: float = h.c - BUMP_STOP
			fz += BUMP_RATE * into * into * (1.0 if h.cv > 0.0 else BUMP_RETURN) + (BUMP_DAMP * h.cv if h.cv > 0.0 else 0.0)
		fz += (ANTI_ROLL_F if front else ANTI_ROLL_R) * (h.c - comp[mate]) if not hits[mate].is_empty() else 0.0
		fz = maxf(fz, 0.0)
		var n: Vector3 = h.n
		var wf: Vector3 = fwd.rotated(up, -steer) if front else fwd
		var f := (wf - n * wf.dot(n)).normalized()
		var side := f.cross(n).normalized()
		var r: Vector3 = h.pos - global_position
		var vp := v + angular_velocity.cross(r)
		var vlong := vp.dot(f)
		var vlat := vp.dot(side)
		# grip: mu x load, a little less per newton the more the tyre is loaded
		var mu: float = GRIP.get(h.surf, 0.9) * clampf(1.0 - LOAD_SENS * (fz / _fz0 - 1.0), 0.7, 1.15)
		var fmax := mu * fz
		var locked: bool = (not front) and inp.handbrake

		var flat := 0.0
		var flong := 0.0
		if locked and Vector2(vlong, vlat).length() > 0.6:
			# a locked tyre just slides: the force is against the way it's sliding
			var sv := Vector2(vlong, vlat).normalized() * (-LOCKED_MU * fmax)
			flong = sv.x
			flat = sv.y
		else:
			# sideways: slip angle -> Magic Formula (peak at the surface's peak slip angle)
			if Vector2(vlong, vlat).length() < 2.5:
				flat = clampf(-vlat * CAR_MASS * 2.0, -fmax, fmax)  # parked: no creeping
			else:
				_alpha[k] = lerpf(_alpha[k], atan2(vlat, absf(vlong)), clampf(absf(vlong) * dt / RELAX, 0.0, 1.0))
				flat = -fmax * tyre_curve(_alpha[k] / PEAK.get(h.surf, SLIP_PEAK))
			# forward: engine, brakes, rolling
			# the handbrake declutches the rear axle (like a real rally car): it all goes to the front
			var split: float = 1.0 if inp.handbrake else DRIVE_FRONT
			flong = drive * (split * 0.5 if front else (1.0 - split) * 0.5)
			var bf := brake * BRAKE_FORCE * (BRAKE_FRONT * 0.5 if front else (1.0 - BRAKE_FRONT) * 0.5)
			if locked:
				bf = maxf(bf, fmax)                                 # parked on the handbrake
			if absf(vlong) > 0.5:
				flong -= signf(vlong) * bf
			else:
				flong -= clampf(vlong * 4000.0, -bf, bf)
			flong -= signf(vlong) * ROLLING * fz

		# friction circle: what's left over is the tyre sliding (and the sound of it)
		var total := Vector2(flong, flat).length()
		if total > fmax and total > 0.0:
			slip_acc += (total - fmax) / maxf(fmax, 1.0)
			flong *= fmax / total
			flat *= fmax / total
		slip_acc += clampf(absf(vlat) / 7.0, 0.0, 1.0) * 0.5
		apply_force(n * fz + f * flong + side * flat, r)
		# visuals: spin with the ground (locked rears don't turn)
		spin[k] = spin[k] if locked else spin[k] + vlong / RADIUS * dt

	# air: drag, and in flight turn toward the ground below + pitch with the pedals
	apply_central_force(-v * v.length() * DRAG)
	if grounded == 0:
		_air_time += dt
		var below := _ground_normal(space, xf.origin + v * 0.3)
		var pedals: float = inp.throttle * AIR_GAS - inp.brake * AIR_BRAKE
		apply_torque(up.cross(below) * AIR_LEVEL - angular_velocity * AIR_DAMP + xf.basis.x * pedals)
	else:
		if _air_time > 0.35 and _prev_v.y < -3.0:
			landed.emit(-_prev_v.y)
		_air_time = 0.0
	slip = clampf(slip_acc / 2.0, 0.0, 1.0)

	# hits: a sudden loss of speed that the brakes didn't do
	var dv := (_prev_v - v)
	dv.y = 0.0
	if dv.length() > 4.0 * (60.0 * dt) and _prev_v.length() > 6.0:
		hit.emit(dv.length())
	_prev_v = v
	_gearbox(vabs, throttle)


## Which way the ground faces under p (straight up if there's nothing within 40 m).
func _ground_normal(space: PhysicsDirectSpaceState3D, p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p, p - Vector3.UP * 40.0, 1, [get_rid()])
	var h := space.intersect_ray(q)
	return h.normal if not h.is_empty() else Vector3.UP


## Front wheel angle (rad, + = right) for steering input u (-1..1) at a speed.
## At speed: the angle the front axle is already travelling at, plus u x the
## tyres' peak slip angle, so full steering = the most grip, never past it.
## Blends to plain wheel angle (u x full lock) below ~30 km/h.
func steer_target(u: float, vabs: float, surface := "gravel") -> float:
	var geo := u * STEER_LOCK
	var xf := global_transform
	var vf := linear_velocity + angular_velocity.cross(xf.basis * Vector3(0.0, 0.0, WHEELS[0][1]))
	var along := vf.dot(-xf.basis.z)
	if along < 1.0:
		return geo                                               # rolling back / sideways: plain steering
	var travel := atan2(vf.dot(xf.basis.x), along)
	var grip: float = clampf(travel, -0.45, 0.45) + u * PEAK.get(surface, SLIP_PEAK)
	var w := smoothstep(5.0, 10.0, vabs)
	return clampf(lerpf(geo, grip, w), -STEER_LOCK, STEER_LOCK)


## Tyre sideways force vs slip, as a fraction of the most it can do: x = slip /
## peak slip. The Magic Formula sin(C atan(B x)) with B set so the peak is at 1.
static func tyre_curve(x: float) -> float:
	const B := 2.3183                                            # tan(PI / (2 C)) for C = 1.35
	return sin(SHAPE_C * atan(B * x))


## An automatic 5-speed: just for the engine note.
func _gearbox(vabs: float, throttle: float) -> void:
	while gear < GEARS.size() and vabs > GEARS[gear - 1] * 0.94:
		gear += 1
	while gear > 1 and vabs < GEARS[gear - 2] * 0.6:
		gear -= 1
	var lo: float = 0.0 if gear == 1 else GEARS[gear - 2] * 0.55
	var r := clampf((vabs - lo) / (GEARS[gear - 1] - lo), 0.0, 1.0)
	if vabs < 3.0:
		r = maxf(r, throttle * 0.55)                     # revving at a standstill
	rpm = lerpf(rpm, r, 0.25)


# ── the stream (co-driver's machine) ──────────────────────────────────────

@rpc("any_peer", "unreliable_ordered")
func net_state(t: int, pos: Vector3, rot: Quaternion, vel: Vector3, st: float, r: float, g: int,
		c: PackedFloat32Array, sl: float, surf: String, hb: bool) -> void:
	if simulate:
		return
	states_received += 1
	var now := Time.get_ticks_msec()
	_offset = minf(_offset + 0.5, float(now - t))      # creep up slowly, snap down to the fastest packet
	_buf.append({"t": float(t), "pos": pos, "rot": rot, "vel": vel, "steer": st, "rpm": r, "gear": g,
		"comp": c, "slip": sl, "surf": surf, "hb": hb})
	while _buf.size() > 40:
		_buf.pop_front()


func _play_stream() -> void:
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
	speed = a.vel.dot(-global_transform.basis.z)
	for k in 4:
		comp[k] = a.comp[k] if a.comp.size() > k else comp[k]
		spin[k] += speed / RADIUS * get_physics_process_delta_time()


func _wheel_visuals(dt: float) -> void:
	for k in 4:
		var pivot: Node3D = wheel_nodes[k]
		pivot.position.y = -(REST - comp[k]) + 0.0
		pivot.rotation.y = -steer if WHEELS[k][2] else 0.0
		(pivot.get_node("Spin") as Node3D).rotation.x = -spin[k]
	if body_model == null or not body_model.visible:
		_flap_prev_v = linear_velocity
		return
	# the model's wheels: up and down with the spring (it was modelled sitting at its
	# static squash), turned by the steering, rolling (its axle is the model's z)
	for k in 4:
		var mw: Array = _model_wheels[k]
		var rest_at: Vector3 = mw[2]
		mw[0].position.y = rest_at.y + (comp[k] - STATIC_COMP) / MODEL_SCALE
		mw[0].rotation.y = -steer if WHEELS[k][2] else 0.0
		mw[1].rotation.z = spin[k]
	# the mud flaps: hanging pendulums. Speed blows them back, braking swings them
	# forward, acceleration back, bumps set them flapping
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
