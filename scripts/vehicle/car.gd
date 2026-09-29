extends CharacterBody3D
## A car you can drive: arcade highway handling (a cut-up game, not a sim).
##   * steering is a bicycle model (wheelbase + front wheel angle), with less
##     lock the faster you go
##   * the tires can only pull `grip` g sideways: ask for more and the car
##     slides; the handbrake lets the rear go (drift)
##   * hitting anything bleeds off speed (the harder / more head-on, the more)
##     and the controls go mushy for a moment
##   * wheels spin and steer, the steering wheel turns, the body rolls and
##     dives, brake lights come on
## The machine of whoever is driving simulates it (`simulate`) and streams the
## transform; everyone else just places it (it still blocks their car).

const Rules = preload("res://scripts/sim/rules.gd")
const PropKit = preload("res://scripts/art/prop_kit.gd")
const CarRefs = preload("res://scripts/vehicle/car_refs.gd")

signal crashed(impact: float)

const G := 9.8
const MPH := 2.23694
const CLEARANCE := 0.3        # the body rides this high: seams, curbs, ramp lips go under it

var key := "beater"
var owner_peer := 0
var paint := Color(0.5, 0.5, 0.52)
var simulate := false        # this machine drives it (physics); otherwise it follows the network
var preview := false         # showroom turntable: just the model (no sound, no collision)
# driver inputs, set every physics frame by whoever drives
var in_throttle := 0.0
var in_brake := 0.0
var in_steer := 0.0          # -1 left .. +1 right
var in_handbrake := false

var speed := 0.0             # m/s along the nose (-z); negative = reversing
var slip := 0.0              # m/s sideways (sliding / drifting)
var steer := 0.0             # front wheel angle, radians (+ = left)
var crash_t := 0.0           # > 0: just hit something
var ref: Dictionary
var model: Node3D            # body + wheels (tilts with the road, rolls, dives)
var body: Node3D
var wheels: Array = []       # [pivot, spinner, front, left]
var steering_wheel: Node3D
var brake_glow: Array = []   # lights that brighten on the brakes
var engine: AudioStreamPlayer3D
var screech: AudioStreamPlayer3D
var sparks: CPUParticles3D
var _spin := 0.0
var _long_acc := 0.0
var _lat_acc := 0.0
var _net_pos := Vector3.ZERO
var _net_rot := Quaternion.IDENTITY
var _has_net := false
var _last_hit := 0.0
var grounded := true
var debug_hits := false


func setup(car_key: String, peer: int, color = null) -> void:
	key = car_key if Rules.CARS.has(car_key) else "beater"
	owner_peer = peer
	paint = color if color is Color else Rules.CARS[key].paint


func _ready() -> void:
	ref = CarRefs.get_ref(Rules.CARS[key].model)
	if preview:
		model = Node3D.new()
		model.name = "Model"
		add_child(model)
		_build_body()
		_build_wheels()
		return
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(40.0)
	floor_constant_speed = true
	wall_min_slide_angle = deg_to_rad(5.0)
	# the body: a middle block riding CLEARANCE up, the bumpers higher still
	# (so a pitch over a crest can't dig a corner into the road)
	var top: float = ref.box_center.y + ref.box.y / 2.0
	var L: float = ref.box.z
	for part in [[0.0, 0.6, CLEARANCE], [-0.4, 0.2, CLEARANCE + 0.2], [0.4, 0.2, CLEARANCE + 0.2]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(ref.box.x, top - part[2], L * part[1])
		cs.shape = bs
		cs.position = Vector3(ref.box_center.x, (top + part[2]) / 2.0, ref.box_center.z + L * part[0])
		add_child(cs)
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	_build_body()
	_build_wheels()
	_build_engine()


func stats() -> Dictionary:
	return Rules.CARS[key]


func mph() -> float:
	return absf(speed) * MPH


# ---------------------------------------------------------------- model

func _build_body() -> void:
	var name_: String = Rules.CARS[key].model
	body = Node3D.new()
	model.add_child(body)
	if name_ != "" and PropKit.has(name_):
		var shell := PropKit.place(name_, body)
		if ref.get("flip", false):
			shell.rotation.y = PI                  # a kit built nose-to-+z
		_tint(body)
	else:
		_stand_in_body()
	var sw := Node3D.new()
	sw.position = ref.wheel_hub
	sw.rotation.x = ref.column_tilt
	body.add_child(sw)
	steering_wheel = Node3D.new()
	sw.add_child(steering_wheel)
	if PropKit.has("Bemze_SteeringWheel"):
		PropKit.place("Bemze_SteeringWheel", steering_wheel)
	else:
		var t := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.16
		tm.outer_radius = 0.19
		t.mesh = tm
		t.rotation.x = PI / 2
		t.material_override = _mat(Color(0.05, 0.05, 0.05))
		steering_wheel.add_child(t)
	for p in ref.tail:
		var q := _glow_quad(Vector2(0.22, 0.07), Color(0.6, 0.02, 0.02))
		q.position = p + Vector3(0, 0, 0.012)
		body.add_child(q)
		brake_glow.append(q)


## The kit body's paint surface is white vertex colors: tint it per car.
func _tint(n: Node) -> void:
	var car_paint := PropKit.material("CarPaint")
	var pm := car_paint.duplicate() as StandardMaterial3D
	pm.albedo_color = paint
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_override == car_paint:
			(mi as MeshInstance3D).material_override = pm


func _stand_in_body() -> void:
	var b: Vector3 = ref.box
	_part(body, Vector3(b.x, 0.62, b.z), Vector3(0, 0.3 + 0.31, 0), paint, 0.25)
	_part(body, Vector3(b.x * 0.86, 0.5, b.z * 0.5), Vector3(0, 0.92 + 0.25, 0.25), paint.darkened(0.1), 0.25)
	_part(body, Vector3(b.x * 0.8, 0.44, 0.04), Vector3(0, 1.17, -0.02), Color(0.2, 0.25, 0.3), 0.05)   # windshield
	for p in ref.head:
		var h := _glow_quad(Vector2(0.28, 0.1), Color(1, 1, 0.9))
		h.position = p - Vector3(0, 0, 0.012)
		h.rotation.y = PI
		body.add_child(h)


func _build_wheels() -> void:
	var r: float = ref.wheel_r
	for w in [["FL", true, true], ["FR", true, false], ["RL", false, true], ["RR", false, false]]:
		var pivot := Node3D.new()
		pivot.position = ref.wheels[w[0]]
		model.add_child(pivot)
		var side := Node3D.new()           # the kit wheel's rim faces +x: turn the left ones around
		side.rotation.y = PI if w[2] else 0.0
		pivot.add_child(side)
		var spinner := Node3D.new()
		side.add_child(spinner)
		var wname: String = ref.get("wheel_prop", Rules.CARS[key].model + "_Wheel")
		if Rules.CARS[key].model != "" and PropKit.has(wname):
			PropKit.place(wname, spinner)
		else:
			var t := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = r
			cm.bottom_radius = r
			cm.height = 0.24
			t.mesh = cm
			t.rotation.z = PI / 2
			t.material_override = _mat(Color(0.06, 0.06, 0.06))
			spinner.add_child(t)
			var hub := MeshInstance3D.new()
			var hm := CylinderMesh.new()
			hm.top_radius = r * 0.62
			hm.bottom_radius = r * 0.62
			hm.height = 0.02
			hub.mesh = hm
			hub.rotation.z = PI / 2
			hub.position.x = 0.12
			hub.material_override = _mat(Color(0.7, 0.72, 0.75))
			spinner.add_child(hub)
		wheels.append([pivot, spinner, w[1], w[2]])


func _build_engine() -> void:
	engine = AudioStreamPlayer3D.new()
	engine.stream = Sfx.looped("engine")
	engine.unit_size = 8.0
	engine.max_distance = 120.0
	engine.volume_db = -10.0
	add_child(engine)
	if engine.stream:
		engine.play()
	screech = AudioStreamPlayer3D.new()
	screech.stream = Sfx.looped("screech")
	screech.unit_size = 10.0
	screech.max_distance = 120.0
	screech.volume_db = -80.0
	add_child(screech)
	if screech.stream:
		screech.play()
	sparks = CPUParticles3D.new()
	sparks.emitting = false
	sparks.one_shot = true
	sparks.amount = 40
	sparks.lifetime = 0.45
	sparks.explosiveness = 0.9
	var sm := QuadMesh.new()
	sm.size = Vector2(0.05, 0.05)
	sparks.mesh = sm
	var spm := StandardMaterial3D.new()
	spm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spm.albedo_color = Color(1.0, 0.75, 0.3)
	spm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sparks.material_override = spm
	sparks.direction = Vector3(0, 1, 0)
	sparks.spread = 70.0
	sparks.initial_velocity_min = 3.0
	sparks.initial_velocity_max = 8.0
	sparks.gravity = Vector3(0, -12, 0)
	add_child(sparks)


func _part(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rough: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := _mat(c)
	m.roughness = rough
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _glow_quad(size: Vector2, c: Color) -> MeshInstance3D:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	q.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	q.material_override = m
	return q


# ---------------------------------------------------------------- driving

func _physics_process(dt: float) -> void:
	if preview:
		return
	if simulate:
		_drive(dt)
	elif _has_net:
		global_position = global_position.lerp(_net_pos, clampf(dt * 12.0, 0.0, 1.0))
		if global_position.distance_to(_net_pos) > 8.0:
			global_position = _net_pos
		quaternion = quaternion.slerp(_net_rot, clampf(dt * 12.0, 0.0, 1.0))
	_visuals(dt)


func _drive(dt: float) -> void:
	var d: Dictionary = Rules.CARS[key]
	var top: float = d.top
	var grip: float = d.grip
	var mushy := crash_t > 0.0
	crash_t = maxf(crash_t - dt, 0.0)
	var ctrl := 0.3 if mushy else 1.0
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var before := speed
	# ---- steering: fast hands at low speed, a light touch at 150 mph
	var sp := flat.length()
	var lock := lerpf(0.6, 0.06, pow(clampf(sp / top, 0.0, 1.0), 0.55))
	var target := -in_steer * lock * (0.5 if mushy else 1.0)
	steer = move_toward(steer, target, (2.2 if absf(target) > absf(steer) else 3.5) * dt)
	var wb: float = ref.wheelbase
	var want := speed / wb * tan(steer)
	var lim: float = grip * G / maxf(sp, 2.0)             # the yaw rate the tires can hold
	var yaw := clampf(want, -lim * 1.12, lim * 1.12)
	if in_handbrake and sp > 6.0:
		yaw = want * 1.35                                  # rear lets go: it rotates more than it turns
	rotate_y(yaw * dt)
	var fwd := -global_basis.z
	# ---- the tires pull the velocity round to where the nose points (no free
	# speed, no lost speed) as hard as the grip allows; past that it slides
	var hold := grip * G * (0.22 if in_handbrake else (0.45 if mushy else 1.25))
	if sp > 0.05:
		var dir := flat / sp
		var aim := fwd if dir.dot(fwd) >= 0.0 else -fwd          # reversing: pull toward the tail
		var ang := dir.signed_angle_to(aim, Vector3.UP)
		var turn := clampf(ang, -hold * dt / sp, hold * dt / sp)
		flat = flat.rotated(Vector3.UP, turn)
	var f := flat.dot(fwd)
	var l := flat.dot(global_basis.x)
	# ---- along the nose: throttle, brakes, reverse, coasting, drag, scrubbing
	var acc := 26.8 / float(d.zero60)                     # 0-60 mph
	if in_throttle > 0.01:
		if f < -0.3:
			f = move_toward(f, 0.0, 14.0 * in_throttle * dt)
		else:
			var fall := clampf(1.0 - pow(maxf(f, 0.0) / top, 2.2), 0.0, 1.0)
			f += acc * 1.1 * in_throttle * fall * ctrl * dt
	if in_brake > 0.01:
		if f > 0.3:
			f = move_toward(f, 0.0, (8.5 + 3.0 * grip) * in_brake * dt)
		else:
			f = move_toward(f, -10.0, 5.0 * in_brake * dt)
	if in_throttle <= 0.01 and in_brake <= 0.01:
		f = move_toward(f, 0.0, (0.7 + 0.0004 * f * f) * dt)
	if in_handbrake:
		f = move_toward(f, 0.0, 5.0 * dt)
	l = move_toward(l, 0.0, (2.0 + absf(l) * 0.8) * dt)     # sideways sliding scrubs itself off
	speed = f
	slip = l
	var v := fwd * f + global_basis.x * l
	# ---- up and down: suspension springs to the road under the axles, tilts
	# up ramps; off the edge of something you fall
	var g := _ground()
	grounded = not g.is_empty() and global_position.y <= g.y + 0.45 and velocity.y < 3.0
	if grounded:
		v.y = clampf((g.y - global_position.y) * 14.0, -12.0, 12.0)
		rotation.x = lerp_angle(rotation.x, g.pitch, clampf(dt * 10.0, 0.0, 1.0))
		rotation.z = lerp_angle(rotation.z, 0.0, clampf(dt * 10.0, 0.0, 1.0))
	else:
		v.y = velocity.y - G * 1.6 * dt
	velocity = v
	var pre := velocity
	move_and_slide()
	# ---- crashes: a hit bleeds off speed (once per hit), a wall steers you along it
	var worst := 0.0
	var worst_n := Vector3.ZERO
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if n.y > 0.65:                                     # that's the road
			continue
		var hn := Vector3(n.x, 0.0, n.z).normalized()
		var impact := maxf(-pre.dot(hn), 0.0)
		if debug_hits:
			print("   hit %s (%s) n=%s at %s impact %.1f" % [c.get_collider().name, c.get_collider().get_parent().name, n, c.get_position(), impact])
		if impact > 1.2 and sparks:
			sparks.global_position = c.get_position()
		if impact > worst:
			worst = impact
			worst_n = hn
	var pv := Vector3(pre.x, 0.0, pre.z)
	# a hard hit can come back as "un-stuck, velocity gone" with no contact
	# reported: judge it by how much velocity the move actually lost
	var rv := get_real_velocity()
	var lost := pv - Vector3(rv.x, 0.0, rv.z)
	if lost.length() > 4.0 and lost.length() > worst * 1.3:
		var n2 := -lost.normalized()
		if absf(n2.y) < 0.5 and not (is_on_floor() and get_slide_collision_count() == 0 and lost.length() < 6.0):
			worst = lost.length()
			worst_n = Vector3(n2.x, 0.0, n2.z).normalized()
	if worst > 1.2 and pv.length() > 0.5:
		var head_on := clampf(worst / pv.length(), 0.0, 1.0)   # 1 = straight in, 0.1 = a scrape
		if not mushy or worst > _last_hit * 1.5:
			var keep := clampf(1.0 - head_on * 0.9 - worst * 0.01, 0.04, 0.95)
			speed *= keep
			crash_t = clampf(worst / 9.0, 0.25, 1.6)
			_last_hit = worst
			crashed.emit(worst)
			_crash_fx(worst)
		else:
			speed *= 1.0 - 0.6 * dt                        # grinding along it
		if head_on < 0.6:                                  # glancing: the wall turns your nose along it
			var along := (pv - worst_n * pv.dot(worst_n)).normalized()
			if along.length() > 0.1:
				var ang := (-global_basis.z).signed_angle_to(along if along.dot(-global_basis.z) > 0.0 else -along, Vector3.UP)
				rotate_y(ang * 0.5)
		else:
			speed = minf(speed, 2.0)                       # a real stop
	# what actually happened along the nose
	var real_v := Vector3(velocity.x, 0.0, velocity.z)
	var real_f := real_v.dot(-global_basis.z)
	if worst > 1.2:
		velocity = -global_basis.z * speed + Vector3(0, velocity.y, 0)
	elif absf(real_f) < absf(speed) - 0.5:
		speed = real_f
	_long_acc = lerpf(_long_acc, (speed - before) / maxf(dt, 0.001), 0.2)
	_lat_acc = lerpf(_lat_acc, speed * yaw, 0.2)


## The road under the car: height under its middle and the pitch from the
## front and rear axles (other cars' roofs don't count as road).
func _ground() -> Dictionary:
	var yb := Basis(Vector3.UP, rotation.y)
	var fy := _axle_y(yb, -ref.wheelbase / 2.0)
	var ry := _axle_y(yb, ref.wheelbase / 2.0)
	if is_nan(fy) and is_nan(ry):
		return {}
	if is_nan(fy):
		fy = ry
	if is_nan(ry):
		ry = fy
	# a sudden drop under one axle is a seam / gap, not a cliff: bridge it
	if absf(fy - ry) > 0.2 + 0.25 * ref.wheelbase:
		fy = maxf(fy, ry)
		ry = fy
	return {"y": (fy + ry) / 2.0, "pitch": clampf(atan2(fy - ry, ref.wheelbase), -0.3, 0.3)}


## Road height under an axle: the highest of three rays across it (so one
## ray down a crack between road pieces doesn't count).
func _axle_y(yb: Basis, z: float) -> float:
	var best := NAN
	for dz in [-0.35, 0.0, 0.35]:
		var h := _ray_down(global_position + yb * Vector3(0, 0, z + dz))
		if not h.is_empty() and (is_nan(best) or h.position.y > best):
			best = h.position.y
	return best


func _ray_down(at: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var ex: Array = [get_rid()]
	for k in 3:
		var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 1.4, 0), at + Vector3(0, -2.5, 0))
		q.exclude = ex
		var h := space.intersect_ray(q)
		if h.is_empty():
			return {}
		if h.collider is CharacterBody3D or h.collider is AnimatableBody3D or h.collider is RigidBody3D:
			ex.append(h.rid)                          # another car: look past it
			continue
		return h
	return {}


func _crash_fx(impact: float) -> void:
	if sparks:
		sparks.amount = clampi(int(impact * 3.0), 10, 60)
		sparks.restart()
	Sfx.play("crash", clampf(-16.0 + impact, -14.0, 0.0), randf_range(0.9, 1.1))


## Remote cars: where the driver's machine says it is.
func net_state(pos: Vector3, rot: Quaternion, spd: float, st: float, brake: bool) -> void:
	_net_pos = pos
	_net_rot = rot
	speed = spd
	steer = st
	in_brake = 1.0 if brake else 0.0
	if not _has_net:
		global_position = pos
		quaternion = rot
	_has_net = true


# ---------------------------------------------------------------- looks

func _visuals(dt: float) -> void:
	var r: float = ref.wheel_r
	_spin = fmod(_spin + speed / r * dt, TAU)
	for w in wheels:
		var pivot: Node3D = w[0]
		var spinner: Node3D = w[1]
		pivot.rotation.y = steer if w[2] else 0.0
		spinner.rotation.x = _spin if w[3] else -_spin
	if steering_wheel:
		steering_wheel.rotation.z = steer * 7.0
	# body: roll away from the turn, dive under braking, squat on the gas
	body.rotation.z = lerpf(body.rotation.z, clampf(_lat_acc * 0.006, -0.05, 0.05), dt * 6.0)
	body.rotation.x = lerpf(body.rotation.x, clampf(-_long_acc * 0.004, -0.035, 0.035), dt * 6.0)
	var braking := in_brake > 0.05 and speed > 0.5
	for q in brake_glow:
		((q as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = Color(1, 0.08, 0.05) if braking else Color(0.45, 0.02, 0.02)
	if screech and screech.stream:                 # tires howl when you slide
		var sl := clampf((absf(slip) - 2.5) / 8.0, 0.0, 1.0) if absf(speed) > 4.0 else 0.0
		screech.volume_db = lerpf(screech.volume_db, -40.0 + sl * 38.0 if sl > 0.0 else -80.0, clampf(dt * 10.0, 0.0, 1.0))
		screech.pitch_scale = 0.9 + sl * 0.2
	if engine and engine.stream:
		var rev := _rpm()
		engine.pitch_scale = 0.55 + rev * 1.35
		engine.volume_db = -14.0 + rev * 6.0 + (4.0 if in_throttle > 0.1 else 0.0)


## 0..1 engine revs through six gears (the shift dips it back down).
func _rpm() -> float:
	var top: float = Rules.CARS[key].top
	var x := clampf(absf(speed) / top, 0.0, 1.0) * 6.0
	var gear := minf(floor(x), 5.0)
	var in_gear := x - gear
	return clampf(0.18 + in_gear * 0.7 + gear * 0.02, 0.15, 1.0) if speed > 0.5 else 0.15 + in_throttle * 0.2
