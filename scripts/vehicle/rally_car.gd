extends RigidBody3D
## The rally car: a rigid body on four raycast springs (not BAGHOLDERS' highway
## CharacterBody: a rally car has to jump, land, slide and roll).
##   * each corner casts a ray down; the spring + damper push the body up at
##     the contact point, an anti-roll bar shares the load across each axle
##   * each tyre makes a sideways force from its slip angle (peaks at
##     SLIP_PEAK, falls off past it: that's the slide) and a forward force
##     from the engine / brakes, both inside one friction circle (mu x load);
##     mu depends on what the tyre is on: gravel, grass, mud
##   * four-wheel drive (42 / 58 front / rear), the handbrake locks the rears
##     and halves their side grip (the hairpin flick)
##   * steering lock shrinks with speed; keyboard steering eases on / off
##   * in the air the body gently levels itself (arcade landings)
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
const DAMP := 2400.0               # N per m/s
const BUMP_STOP := 0.29            # past this compression the bump stop takes over
const ANTI_ROLL_F := 13000.0       # N per m of left/right difference (front stiffer: stable at speed)
const ANTI_ROLL_R := 5000.0
const CAR_MASS := 1150.0
const ENGINE_FORCE := 7400.0       # at the wheels, low speed (N)
const POWER := 150000.0            # W: above ~20 m/s the force is POWER / speed
const V_MAX := 47.0                # rev limiter in 5th (m/s, 170 km/h)
const REVERSE_MAX := 8.0
const BRAKE_FORCE := 13000.0       # total (N), 68 % front
const DRAG := 0.46                 # N per (m/s)^2
const ROLLING := 170.0             # N
const STEER_LOCK := 0.58           # front wheels at full lock, parked (rad)
const STEER_FAST := 0.13           # ... at top speed (the rest is added at low speed, see steer_lock)
const SLIP_PEAK := 0.10            # rad
const GRIP := {"gravel": 0.92, "dirt": 0.9, "grass": 0.62, "mud": 0.55, "tarmac": 1.1}
const GEARS := [13.0, 21.0, 29.0, 37.0, 47.0]   # top speed in each gear (m/s)
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

var _prev_v := Vector3.ZERO
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
	reset_physics_interpolation()


func set_simulating(on: bool) -> void:
	simulate = on
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = not on


func kmh() -> float:
	return absf(speed) * 3.6


func _physics_process(dt: float) -> void:
	if simulate:
		_drive(dt)
		_net_acc += dt
		if _net_acc >= 1.0 / NET_HZ and Net.online() and stream_ok:
			_net_acc = 0.0
			net_state.rpc(Time.get_ticks_msec(), global_position, global_transform.basis.get_rotation_quaternion(),
				linear_velocity, steer, rpm, gear, PackedFloat32Array(comp), slip, on_surface)
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

	# steering: lock shrinks with speed so full lock is about what the front tyres can
	# use (peak slip + the bend's own angle), plus however far the car is sideways,
	# so a slide can always be caught; keys ease on and come back faster
	var lock := steer_lock(vabs, atan2(v.dot(xf.basis.x), maxf(vabs, 3.0)))
	var target: float = clampf(inp.steer, -1.0, 1.0) * lock
	if analog_steer:
		steer = lerpf(steer, target, clampf(dt * 14.0, 0.0, 1.0))
	else:
		var rate := 1.9 if absf(target) > absf(steer) and signf(target) == signf(steer) else 3.2
		steer = move_toward(steer, target, rate * dt)

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
		var c: float = REST + RADIUS - mount.distance_to(h.position)
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
		var fz: float = SPRING * h.c + DAMP * h.cv
		if h.c > BUMP_STOP:
			fz += (h.c - BUMP_STOP) * SPRING * 8.0
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
		var mu: float = GRIP.get(h.surf, 0.9)
		var fmax := mu * fz
		var locked: bool = (not front) and inp.handbrake

		# sideways: slip angle -> force, falling off past the peak
		var flat: float
		if Vector2(vlong, vlat).length() < 2.5:
			flat = clampf(-vlat * CAR_MASS * 2.0, -fmax, fmax)      # parked: no creeping
		else:
			# the rears peak a little later and let go more gently: braking into a bend
			# shouldn't spin you, the handbrake should
			var peak: float = SLIP_PEAK if front else SLIP_PEAK * 1.25
			var drop: float = 0.2 if front else 0.12
			var x := atan2(vlat, absf(vlong)) / peak
			var shape := x if absf(x) <= 1.0 else signf(x) * (1.0 - drop * clampf(absf(x) - 1.0, 0.0, 1.0))
			flat = -fmax * shape
		if locked:
			flat *= 0.25

		# forward: engine, brakes, handbrake, rolling
		var flong := drive * (0.21 if front else 0.29)
		var bf := brake * BRAKE_FORCE * (0.34 if front else 0.16)
		if absf(vlong) > 0.5:
			flong -= signf(vlong) * bf
		else:
			flong -= clampf(vlong * 4000.0, -bf, bf)
		if locked:
			flong -= signf(vlong) * fmax * 0.75 if absf(vlong) > 0.3 else vlong * 2000.0
		flong -= signf(vlong) * ROLLING * 0.25

		# friction circle
		var total := Vector2(flong, flat).length()
		if total > fmax and total > 0.0:
			slip_acc += (total - fmax) / maxf(fmax, 1.0)
			flong *= fmax / total
			flat *= fmax / total
		slip_acc += clampf(absf(vlat) / 7.0, 0.0, 1.0) * 0.5
		apply_force(n * fz + f * flong + side * flat, r)
		# visuals: spin with the ground (locked rears don't turn)
		spin[k] = spin[k] if locked else spin[k] + vlong / RADIUS * dt

	# air: drag, and level the body a little while flying
	apply_central_force(-v * v.length() * DRAG)
	if grounded == 0:
		_air_time += dt
		var level := up.cross(Vector3.UP)
		apply_torque(level * 2600.0 - angular_velocity * 350.0)
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


## Front wheel angle at full lock (rad) at a speed, with the body `slide` angle (rad).
func steer_lock(vabs: float, slide := 0.0) -> float:
	return minf(STEER_LOCK, STEER_FAST + 16.0 / maxf(vabs * vabs, 1.0) + absf(slide))


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
		c: PackedFloat32Array, sl: float, surf: String) -> void:
	if simulate:
		return
	states_received += 1
	var now := Time.get_ticks_msec()
	_offset = minf(_offset + 0.5, float(now - t))      # creep up slowly, snap down to the fastest packet
	_buf.append({"t": float(t), "pos": pos, "rot": rot, "vel": vel, "steer": st, "rpm": r, "gear": g,
		"comp": c, "slip": sl, "surf": surf})
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
	speed = a.vel.dot(-global_transform.basis.z)
	for k in 4:
		comp[k] = a.comp[k] if a.comp.size() > k else comp[k]
		spin[k] += speed / RADIUS * get_physics_process_delta_time()


func _wheel_visuals(_dt: float) -> void:
	for k in 4:
		var pivot: Node3D = wheel_nodes[k]
		pivot.position.y = -(REST - comp[k]) + 0.0
		pivot.rotation.y = -steer if WHEELS[k][2] else 0.0
		(pivot.get_node("Spin") as Node3D).rotation.x = -spin[k]
