extends Node3D
## Track Mode's AI field: the other cars of a qualifying session or a race, each a RallyCar with
## a RaceDriver at the wheel. Every car runs the same car physics as yours while it's near you;
## farther away it moves along its line at the speeds its car and driver would do, without the
## physics (RaceDriver.far_step), as racing games keep a big field affordable: a car's full physics
## costs ~1.4 ms a tick in this engine, so a grid of 16 would take twice the frame. Two numbers set
## it: up to NEAR_MAX cars (the quality setting can raise it) within NEAR_R m of you drive on the
## physics; beyond FAR_R they're moved. Each switch carries the car's place, heading and speed over
## (its wheels spinning, in the gear for that speed), so the change doesn't show.
##
## Every tick it hands each driver where the others are (racecraft: RaceDriver.plan), drives the
## near cars (their inputs) and moves the far ones (their pose, wheels and steering for the
## picture, their fuel and tyres: RaceSim.coast), and gives the game every car's road position for
## the timing (positions()).

const RaceDriver = preload("res://scripts/vehicle/race_driver.gd")
const RaceLine = preload("res://scripts/game/race_line.gd")
const RallyCar = preload("res://scripts/vehicle/rally_car.gd")
const Catalog = preload("res://scripts/game/catalog.gd")

const NEAR_R := 110.0              # m: within this of you a car runs on the physics (up to near_max) ...
const FAR_R := 150.0               # ... and past this it's moved
const LOD_EVERY := 0.25            # s between the near / far choices
const STUCK_T := 6.0               # s stopped off the line before it's put back on the track (as R does for you)
const RETIRE_T := 40.0             # s stuck before it retires
const AI_SUBSTEPS := 4             # an AI car's tyre / drivetrain steps a tick (yours: 8): the steps are most of a car's
                                   # physics cost, and an AI's steady inputs don't need the finest (tests/race_ai_check.gd laps it)

var st                             # CircuitGen
var drivers: Array = []            # RaceDriver
var cars := {}                     # id -> RallyCar
var near := {}                     # id -> true while on the physics
var near_max := 4
var collide := true
var race_opts := {}                # RaceSim's opts (Modes.race_opts)
var me := {"id": 0, "s": 0.0, "d": 0.0, "v": 0.0, "pos": Vector3.ZERO}   # the player's car (the game sets it)
var player_car                     # the player's RallyCar (collision exceptions)
var others_extra: Array = []       # more cars the drivers should mind (online players: P8)
var events: Array = []             # [id, kind, ...] from the drivers since last read (the game clears it)
var pin_near := false              # (tests) every car on the physics (up to near_max), wherever you are
var _lod_t := 0.0
var _hint := {}


## entries: [{id, car (registry id), name, number, colours, livery, skill, s, d (its start), box}];
## opts: the session's options (collide, near_max); r_opts: RaceSim's.
func setup(stage, entries: Array, opts: Dictionary, r_opts: Dictionary, seed_value: int) -> void:
	st = stage
	race_opts = r_opts
	collide = bool(opts.get("collide", true))
	near_max = int(opts.get("near_max", near_max))
	for e in entries:
		var c = RallyCar.new()
		c.name = "AI_%s" % str(e.id)
		var paint := {"colours": e.get("colours", []), "livery": e.get("livery", "plain"), "number": int(e.get("number", 7))}
		if (paint.colours as Array).is_empty():
			paint.erase("colours")
		var s: Dictionary = Catalog.for_stage(Catalog.setup(str(e.car), paint, {}, {}), st)
		s["race_sim"] = true
		s["race"] = r_opts.duplicate()
		s["race"]["fuel"] = float(e.get("fuel", r_opts.get("fuel", 60.0)))
		if int(r_opts.get("abs", 4)) == 0 or int(r_opts.get("tc", 4)) == 0:
			# a class without ABS or traction control (FORMULA APEX): a racing driver feels for the edge of
			# the grip with their feet, as the aids do; the AI's pedals lean on the aids for that, so they
			# stand in for its feet (no more grip than the tyres have: they only keep it at their peak)
			s["race"]["abs"] = maxi(int(r_opts.get("abs", 4)), 6)
			s["race"]["tc"] = maxi(int(r_opts.get("tc", 4)), 6)
		c.setup = s
		c.substeps = AI_SUBSTEPS
		add_child(c)
		c.set_outside(true)
		c.hit.connect(func(imp: float): if c.race: c.race.hit(imp))
		if c.race:
			c.race.drs_auto = true                   # (the AI opens its DRS whenever it may, flat out)
		if int(c.cockpit_info().get("seats", 2)) == 1:
			_helmet(c, e)                            # (an open cockpit: its driver's helmet in the air)
		var tag := Label3D.new()
		tag.name = "NameTag"
		tag.text = "%d  %s" % [int(e.get("number", 0)), str(e.name)]
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 48
		tag.pixel_size = 0.01
		tag.outline_size = 10
		tag.position = Vector3(0.0, 1.9, 0.0)
		tag.visibility_range_end = 160.0
		c.add_child(tag)
		var drv = RaceDriver.new()
		drv.id = e.id
		drv.driver_name = str(e.name)
		drv.pit_box = int(e.get("box", 0))
		drv.setup(st, RaceLine.params(c), e.get("skill", {}), seed_value * 131 + drivers.size() * 17 + 3)
		drv.s = float(e.s)
		drv.d = float(e.d)
		drv.task = str(e.get("task", "hold"))
		drv.pit_lap = int(e.get("pit_lap", -1))
		drivers.append(drv)
		cars[e.id] = c
		_hint[e.id] = -1
		_go_far(drv)
		_pose(drv, 0.0)


## A single-seater's driver, seen from outside: their helmet up in the cockpit under the halo
## (where its eyes are: parts.json cockpit "eye"), in their colours, a dark visor across it. (The
## player's own car has the whole driver: Cockpit.)
func _helmet(c, e: Dictionary) -> void:
	var cols: Array = e.get("colours", [])
	var shell: Color = cols[1] if cols.size() > 1 else Color(0.95, 0.95, 0.94)
	var stripe: Color = cols[0] if cols.size() > 0 else Color(0.8, 0.1, 0.1)
	var eye: Array = c.cockpit_info().get("eye", [0.0, 0.8, 0.2])
	var h := Node3D.new()
	h.name = "Helmet"
	h.position = Vector3(float(eye[0]), float(eye[1]), float(eye[2])) + c.model_offset() + Vector3(0.0, -0.01, 0.07)
	c.add_child(h)
	var parts := [[Vector3(0.13, 0.135, 0.15), Vector3.ZERO, shell, 0.3],          # the shell
		[Vector3(0.122, 0.05, 0.12), Vector3(0.0, 0.0, -0.05), Color(0.04, 0.05, 0.07), 0.08],   # the visor
		[Vector3(0.135, 0.03, 0.155), Vector3(0.0, 0.07, 0.0), stripe, 0.35]]          # a band round the top
	for pt in parts:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 16
		sm.rings = 8
		mi.mesh = sm
		mi.scale = pt[0]
		mi.position = pt[1]
		var m := StandardMaterial3D.new()
		m.albedo_color = pt[2]
		m.roughness = pt[3]
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.add_child(mi)


func driver(id):
	for drv in drivers:
		if drv.id == id:
			return drv
	return null


## Every car's road position for the timing: {id: {s, d, v, pit}}.
func positions() -> Dictionary:
	var out := {}
	for drv in drivers:
		out[drv.id] = {"s": drv.s, "d": drv.d, "v": drv.v, "pit": st.in_pit_lane(drv.s, drv.d)}
	return out


## One tick (the game's _physics_process, before the physics moves the cars).
func tick(dt: float) -> void:
	# where everyone is: the near cars from their bodies
	for drv in drivers:
		if near.has(drv.id):
			var c = cars[drv.id]
			var at: Dictionary = st.locate(c.global_position, int(_hint[drv.id]))
			_hint[drv.id] = at.i
			drv.s = st.unwrap(at.s, drv.s)
			drv.d = at.d
			drv.v = c.linear_velocity.length()
	_lod_t -= dt
	if _lod_t <= 0.0:
		_lod_t = LOD_EVERY
		_choose_lod()
	var all: Array = []
	all.append({"id": me.id, "s": me.s, "d": me.d, "v": me.v, "stricken": false})
	for o in others_extra:
		all.append(o)
	for drv in drivers:
		all.append({"id": drv.id, "s": drv.s, "d": drv.d, "v": drv.v, "stricken": drv.task == "out"})
	for drv in drivers:
		var mine: Array = []
		for o in all:
			if o.id != drv.id:
				mine.append(o)
		drv.plan(mine, dt)
		drv.pit_tick(dt)
		var c = cars[drv.id]
		if near.has(drv.id):
			c.set_lanes(st, drv.s, drv.d)
			c.inp = drv.drive(c, dt)
			if c.race:
				c.race.limiter = st.in_pit_limit(drv.s, drv.d) or (drv.task == "pit" and drv.pit_phase == "in" and st.around_line(drv.s) > float(st.pit.s_lim0) - 15.0)
				c.race.limiter_kmh = float(st.pit.limit_kmh)
				c.race.tow = _tow(drv, all)
			_unstick(drv, c, dt)
		else:
			drv.far_step(dt, _tow(drv, all), c.race != null and c.race.drs_avail)   # (a far car may use its DRS too)
			_pose(drv, dt)
			if c.race:
				c.race.coast(c, dt, drv.v, drv.task)
		_service(drv, c)
		for ev in drv.events:
			events.append([drv.id] + ev)
		drv.events.clear()


## Who's on the physics: the nearest few to you, inside NEAR_R (and staying on it out to FAR_R).
func _choose_lod() -> void:
	var by: Array = []
	for drv in drivers:
		var c = cars[drv.id]
		var dist: float = (c.global_position - Vector3(me.pos)).length() if near.has(drv.id) else (st.world_at(drv.s, drv.d) - Vector3(me.pos)).length()
		by.append([dist, drv])
	by.sort_custom(func(a, b): return a[0] < b[0])
	for k in by.size():
		var dist: float = by[k][0]
		var drv = by[k][1]
		var want: bool = k < near_max and (pin_near or dist < NEAR_R or (near.has(drv.id) and dist < FAR_R))
		if want and not near.has(drv.id):
			_go_near(drv)
		elif not want and near.has(drv.id):
			_go_far(drv)


## Onto the physics: the body where it was drawn, at its speed, wheels spinning, in gear.
func _go_near(drv) -> void:
	var c = cars[drv.id]
	near[drv.id] = true
	c.collision_layer = 2
	c.collision_mask = 1 | 2 if collide else 1
	var yaw: float = st.heading_at(drv.s) + atan((drv.target_d(drv.s + 2.0) - drv.target_d(drv.s - 2.0)) / 4.0)
	c.set_simulating(true)
	c.place(st.world_at(drv.s, drv.d), yaw)
	c.set_rolling(drv.v)
	_hint[drv.id] = -1
	if player_car and not collide:
		c.add_collision_exception_with(player_car)
		player_car.add_collision_exception_with(c)


## Off the physics: held, drawn where its driver moves it, touching nothing.
func _go_far(drv) -> void:
	var c = cars[drv.id]
	near.erase(drv.id)
	c.set_simulating(false)
	c.collision_layer = 0
	c.collision_mask = 0


## A far car's pose: on the track's surface at (s, d), along its path, banked with the track, its
## wheels rolling and steering for the picture.
func _pose(drv, dt: float) -> void:
	var c = cars[drv.id]
	var slope: float = (drv.target_d(drv.s + 2.0) - drv.target_d(drv.s - 2.0)) / 4.0
	var yaw: float = st.heading_at(drv.s) + atan(slope)
	var up: Vector3 = st.up_at(drv.s)
	var fwd := Vector3(sin(yaw), 0.0, -cos(yaw))
	var ahead: Vector3 = st.world_at(drv.s + 2.0, drv.target_d(drv.s + 2.0))
	var here: Vector3 = st.world_at(drv.s, drv.d)
	fwd.y = (ahead.y - here.y) / 2.0
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var right := fwd.cross(up).normalized()
	var b := Basis(right, up, -fwd)
	c.puppet(Transform3D(b, here + up * c.ride_height()), fwd * drv.v, drv.steer_look, dt)


## The slipstream: a car a few lengths ahead, nearly in line (0..1).
func _tow(drv, all: Array) -> float:
	var L: float = st.length
	var best := 0.0
	for o in all:
		if o.id == drv.id:
			continue
		var gap: float = fposmod(float(o.s) - drv.s + L * 0.5, L) - L * 0.5
		if gap > 4.0 and gap < 40.0 and absf(float(o.d) - drv.d) < 1.6:
			best = maxf(best, 1.0 - (gap - 4.0) / 36.0)
	return best


## A near car stopped off its line (spun, beached, in the wall) for a while: back on the track at
## the edge facing the right way, once nothing's coming (the player's R); stuck for good: retired.
func _unstick(drv, c, dt: float) -> void:
	if drv.task in ["hold", "out"] or (drv.task == "pit" and drv.pit_phase == "stop"):
		drv.stuck_t = 0.0
		return
	var fwd: Vector3 = -c.global_transform.basis.z
	var wrong: bool = fwd.dot(st.forward_at(drv.s)) < 0.2
	drv.stuck_t = drv.stuck_t + dt if (drv.v < 1.0 or (wrong and drv.v < 6.0)) else 0.0
	if drv.stuck_t > RETIRE_T:
		drv.task = "out"
		drv.events.append(["retired"])
		return
	if drv.stuck_t > STUCK_T and _clear_behind(drv):
		drv.stuck_t = 0.0
		var side := signf(drv.d) if absf(drv.d) > 0.5 else 1.0
		var d: float = side * (st.half_at(drv.s) - 1.5)
		c.place(st.world_at(drv.s, d), st.heading_at(drv.s))
		drv.d = d
		drv.events.append(["reset"])


func _clear_behind(drv) -> bool:
	var L: float = st.length
	var check: Array = [me]
	for o in drivers:
		if o != drv:
			check.append({"id": o.id, "s": o.s, "d": o.d})
	for o in check:
		var gap: float = fposmod(drv.s - float(o.s) + L * 0.5, L) - L * 0.5
		if gap > 0.0 and gap < 80.0:
			return false
	return true


## The pit stop's work once the car's stopped in its box: tyres, fuel, repairs.
func _service(drv, c) -> void:
	for ev in drv.events:
		if str(ev[0]) == "serviced" and c.race:
			var sv: Dictionary = ev[1]
			c.race.service(c, str(sv.get("compound", "")) if bool(sv.get("tyres", false)) else "", float(sv.get("fuel", 0.0)))
			if bool(sv.get("repair", false)) or float(sv.get("repair", 0.0)) > 0.0:
				c.race.repair()


## Put a car on its start (a grid box or a pit box) still: the restart's grid, a session's start.
func place(id, s: float, d: float, task := "hold") -> void:
	var drv = driver(id)
	if drv == null:
		return
	drv.s = s
	drv.d = d
	drv.v = 0.0
	drv.task = task
	drv.lights_out = false
	drv.hold_t = 0.0
	var c = cars[id]
	if near.has(id):
		c.place(st.world_at(s, d), st.heading_at(s))
	else:
		_pose(drv, 0.0)
