extends SceneTree
## The modes beyond rally stages: the touge and cut up.
## Run: godot --headless --fixed-fps 120 --path . -s tests/modes_check.gd [-- --only=battles]
##   * a touge: a narrow two-lane pass full of hairpins that climbs (or falls) all
##     the way, no steeper than its limit, the same pass from the same seed, never
##     back past or under itself; built with guardrails, curve mirrors and cedar
##     forest, nothing solid on the road
##   * a highway: four lanes, sweepers only, a few per cent at most; concrete
##     barriers both sides the whole way
##   * the traffic: the registry's traffic cars on it, about as many as the
##     difficulty asks; a minute of driving with the player weaving through: no
##     car runs into another, they keep to the lanes and their speeds, some change
##     lanes, the population holds
##   * the cut-up score: near misses (close and fast count, slow or far don't), the
##     combo, banking, a crash
##   * the touge rules: splits against a best, drift points and chains, a chain lost
##   * the LAKESHORE LOOP (cut up's map): it closes on itself, ~28 km, four lanes each
##     way, sweepers, grades of 4 % at most, three suspension bridges and three
##     tunnels, never near itself; built: the road solid underfoot all the way round
##     in every lane, the city's towers, the hills' trees; the city's far tier (the
##     31-building pack) on the ground, off the road, no building on another; traffic on it: packs on
##     insane (blocks of cars with open road between), the other carriageway's
##     traffic going the other way, cars joining from an on-ramp; s round the loop
##   * the highway battles (Rivals): a rival shows up in the traffic, flashing it from
##     close behind starts the race (3, 2, 1, GO, a gate 3 km on); it races through
##     the traffic (past cars, never through one); a fast player wins it, a slow one
##     loses it; a win pays into the score
##   * the touge's ghost: a run recorded, saved, loaded and played back at the same
##     clock (in between samples too), gone near the player, gone past its finish
##   * the game itself in each mode: loads, runs, ends with the mode's results; a
##     time attack's record leaves a ghost the next run races
## Prints one [modes] line per check; exits 1 on any FAIL.

var StageGen
var StageBuilder
var Traffic
var CutupScore
var TougeRules
var Modes
var VehicleRegistry
var fails := 0


func _initialize() -> void:
	StageGen = load("res://scripts/stage/stage_gen.gd")
	StageBuilder = load("res://scripts/stage/stage_builder.gd")
	Traffic = load("res://scripts/stage/traffic.gd")
	CutupScore = load("res://scripts/game/cutup_score.gd")
	TougeRules = load("res://scripts/game/touge_rules.gd")
	Modes = load("res://scripts/game/modes.gd")
	VehicleRegistry = load("res://scripts/game/vehicle_registry.gd")
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")         # (one part: touge (with the night and the stray car), highway, loop, battles, traffic, score, rules, ghost, game)
	if only in ["", "touge"]:
		_touge()
		await _touge_road()
		await _night_touge()
		await _stray()
	if only in ["", "highway"]: _highway()
	if only in ["", "loop"]: await _loop()
	if only in ["", "battles"]: await _battles()
	if only in ["", "traffic"]: await _traffic()
	if only in ["", "score"]: _score()
	if only in ["", "rules"]:
		_touge_rules()
		_time_of_day()
	if only in ["", "ghost"]: _ghost()
	if only in ["", "game"]:
		await process_frame                        # (the autoloads in the tree first: Net, Config)
		await _game("touge")
		await _ghost_game()
		await _game("cutup")
	print("[modes] %s" % ("MODES OK" if fails == 0 else "MODES FAIL"))
	quit(1 if fails else 0)


func check(ok: bool, what: String) -> void:
	print("[modes] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _stats(st) -> Dictionary:
	var steep := 0.0
	for i in range(1, st.pts.size()):
		steep = maxf(steep, absf(st.pts[i].y - st.pts[i - 1].y) / st.STEP)
	var hp := 0
	var tightest := INF
	for c in st.corners:
		tightest = minf(tightest, c.r_min)
		if c.r_min < 20.0:
			hp += 1
	var maxk := 0.0
	for k in st.curv:
		maxk = maxf(maxk, absf(k))
	return {"steep": steep, "hairpins": hp, "rise": st.pts[st.pts.size() - 1].y - st.pts[0].y, "tightest": tightest,
		"wmin": Array(st.widths).min(), "wmax": Array(st.widths).max(), "r_min": 1.0 / maxf(maxk, 1e-6)}


func _touge() -> void:
	for dir in ["up", "down"]:
		var st = StageGen.new()
		st.opts = {"kind": "touge", "dir": dir}
		st.generate(7, Modes.TOUGE_LENGTH)
		var x := _stats(st)
		check(st.length > 4500.0 and x.hairpins >= 8, "touge (%s): %.1f km, %d corners, %d hairpins (tighter than 20 m)" % [dir, st.length / 1000.0, st.corners.size(), x.hairpins])
		check(x.wmin >= 5.9 and x.wmax <= 6.9, "touge: two narrow lanes, %.1f-%.1f m wide" % [x.wmin, x.wmax])
		check(x.steep <= st.max_grade() + 0.001, "touge: no steeper than %.0f %% (steepest %.1f %%)" % [st.max_grade() * 100.0, x.steep * 100.0])
		var against := 0
		for i in range(1, st.pts.size()):
			var dy: float = st.pts[i].y - st.pts[i - 1].y
			if (dy > 0.001 and dir == "down") or (dy < -0.001 and dir == "up"):
				against += 1
		var climbs: bool = x.rise > 300.0 if dir == "up" else x.rise < -300.0
		check(climbs and against == 0, "touge %s: %+.0f m from start to finish (%.1f %% on average), %s all the way" % [
			"uphill" if dir == "up" else "downhill", x.rise, absf(x.rise) / st.length * 100.0,
			("climbing" if dir == "up" else "falling") if against == 0 else "NOT %s %d m of it" % ["climbing" if dir == "up" else "falling", int(against * st.STEP)]])
		check(st.crests.filter(func(c): return c.jump).is_empty() and st.bridges.is_empty() and st.villages.is_empty() and st.puddles.is_empty(),
			"touge: no jumps, bridges, villages or puddles; asphalt end to end (%s)" % st.describe())
	var a = StageGen.new()
	a.opts = {"kind": "touge", "dir": "up"}
	a.generate(11, 4000.0)
	var b = StageGen.new()
	b.opts = {"kind": "touge", "dir": "up"}
	b.generate(11, 4000.0)
	check(a.pts == b.pts and a.touge_name() == b.touge_name(), "touge: the same seed builds the same pass (%s) on every machine" % a.touge_name())
	# a long pass never comes back past or under itself (more than half of them did: with
	# no layout clear by chance the road is grown a stretch at a time)
	var clear := 0
	var shortest := INF
	for sd in range(1, 13):
		for dir in ["up", "down"]:
			var p = StageGen.new()
			p.opts = {"kind": "touge", "dir": dir}
			p.generate(sd, Modes.TOUGE_LENGTH)
			clear += 1 if p._clear_of_itself() else 0
			shortest = minf(shortest, p.length)
	check(clear == 24 and shortest > 4500.0, "touge: %d of 24 passes of 5 km keep %.0f m from every other part of themselves (the shortest %.1f km)" % [
		clear, StageGen.CLEARANCE, shortest / 1000.0])
	# built: guardrails, props, cedars
	var builder = StageBuilder.new()
	root.add_child(builder)
	builder.build(a)
	var rails: Node = builder.get_node_or_null("Armco")
	var props: Node = builder.get_node_or_null("TougeProps")
	var cedars := 0
	for n in builder.find_children("*", "MultiMeshInstance3D", true, false):
		if (n as MultiMeshInstance3D).multimesh and str(n.name).contains("cedar"):
			cedars += (n as MultiMeshInstance3D).multimesh.instance_count
	check(rails != null and props != null and builder.crowd_count == 0,
		"touge built: guardrail, curve mirrors / chevrons / km posts, no spectators (%d trees)" % builder.tree_count)
	builder.queue_free()


## Nothing solid on a touge's road: a car-sized box swept down the middle and both
## lanes touches nothing (seed 5 downhill once ran under its own hillside: cars
## stopped dead in the middle of the road).
func _touge_road() -> void:
	var st = StageGen.new()
	st.opts = {"kind": "touge", "dir": "down"}
	st.generate(5, Modes.TOUGE_LENGTH)
	var b = StageBuilder.new()
	root.add_child(b)
	b.build(st)
	for k in 3:
		await physics_frame
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 0.8, 1.6)
	q.shape = box
	var hits := 0
	var first := ""
	var s: float = st.START_S
	while s < st.finish_s:
		for d in [-1.8, 0.0, 1.8]:
			q.transform = Transform3D(Basis(Vector3.UP, st.heading_at(s)), st.world_at(s, d) + Vector3.UP * 0.9)
			var r: Array = space.intersect_shape(q, 1)
			if not r.is_empty():
				hits += 1
				if first == "":
					first = "%s at s %.0f" % [r[0].collider.name, s]
		s += 2.0
	check(hits == 0, "touge: nothing solid on the road, %.1f km of it swept in both lanes (%d hits%s)" % [
		(st.finish_s - st.START_S) / 1000.0, hits, (": " + first) if first != "" else ""])
	b.queue_free()


## The touge at night: street lamps along the pass (before the tight bends, then no
## stretch without one for long), lit (StreetLamps: heads, pools, a few real lights
## that follow the car) only at night; by day the posts alone.
func _night_touge() -> void:
	var st = StageGen.new()
	st.opts = {"kind": "touge", "dir": "down"}
	st.generate(7, Modes.TOUGE_LENGTH)
	for mood in ["day", "night"]:
		var b = StageBuilder.new()
		b.mood = mood
		root.add_child(b)
		b.build(st)
		var gap := 0.0
		for i in range(1, b.lamps.size()):
			gap = maxf(gap, float(b.lamps[i].s) - float(b.lamps[i - 1].s))
		var tight := 0
		var lit_bends := 0
		for c in st.corners:
			if c.r_min <= 45.0 and c.s0 > st.START_S + 20.0 and c.s0 < st.finish_s - 10.0:
				tight += 1
				# (3-16 m before it, on its outside: the spot moves to clear ground behind the guardrail)
				var from: float = maxf(c.s0 - 16.0, st.START_S + 12.0) - 0.5
				if b.lamps.any(func(l): return float(l.s) >= from and float(l.s) <= c.s0 - 2.5 and float(l.side) == -float(c.dir)):
					lit_bends += 1
		var sl = b.street_lamps
		if mood == "night":
			var car := Node3D.new()
			root.add_child(car)
			car.global_position = b.lamps[3].head - Vector3.UP * 7.0
			sl.target = car
			for k in 3:
				await process_frame
			var on: Array = sl._lights.filter(func(o): return o.visible and o.light_energy > 0.5)
			check(sl != null and sl.lamps.size() == b.lamps.size() and not on.is_empty() and on.size() <= sl.REAL,
				"night touge: %d street lamps lit (%.1f per km), %d real lights on round the car under one" % [
				b.lamps.size(), b.lamps.size() / (st.length / 1000.0), on.size()])
			car.global_position = b.lamps[3].head + Vector3(400.0, 0.0, 400.0)
			for k in 16:
				await process_frame
			check(sl._lights.all(func(o): return not o.visible or o.light_energy < 0.05),
				"night touge: the real lights fade out away from the lamps (only the faked pools there)")
			car.queue_free()
		else:
			check(sl == null and b.lamps.size() > 20 and gap <= 135.0 and lit_bends == tight,
				"touge: lamp posts before all %d tight bends, never more than %.0f m apart (%d); unlit by day" % [tight, gap, b.lamps.size()])
		b.queue_free()
	var o: Dictionary = Modes.touge_opts(3)
	check(o.mood == "night" and Modes.with_time(o, 13.0).mood == "day", "touge: at night unless Settings' time of day says otherwise")


## The touge's stray car: turns up ahead now and then, keeps to its lane (toward us:
## the right lane; with us: ours), slows for the hairpins, stops when it's hit, and
## is gone once the player's well past.
func _stray() -> void:
	var st = StageGen.new()
	st.opts = {"kind": "touge", "dir": "down"}
	st.generate(7, Modes.TOUGE_LENGTH)
	var Stray = load("res://scripts/game/stray_car.gd")
	var sc = Stray.new()
	root.add_child(sc)
	sc.setup(st, 7, false)
	var player_s: float = st.START_S + 200.0
	var t := 0.0
	while sc.spawned == 0 and t < 60.0:
		sc.tick(0.1, player_s, st.world_at(player_s, 0.0))
		t += 0.1
	check(sc.spawned == 1 and float(sc.car.s) - player_s >= sc.AHEAD[0] - 1.0, "stray car: one turns up %.0f m ahead after %.0f s (%s)" % [
		float(sc.car.get("s", 0.0)) - player_s, t, "coming the other way" if int(sc.car.get("dir", 0)) < 0 else "going our way"])
	# drive one toward us down the pass: in its lane all the way, slow in the hairpins
	sc._remove()
	sc.spawn_at(st.finish_s - 60.0, -1)
	var off := 0.0
	var v_tight := 0.0
	var v_open := 0.0
	var dt := 1.0 / 30.0
	for k in 30 * 60:
		sc.tick(dt, st.START_S, st.world_at(st.START_S, 0.0))
		if sc.car.is_empty():
			break
		off = maxf(off, absf(float(sc.car.d) - st.LANE_W * 0.5))    # (the body goes there at the physics step)
		var r: float = sc._radius(float(sc.car.s))
		if r < 18.0:
			v_tight = maxf(v_tight, float(sc.car.v))
		elif r > 150.0:
			v_open = maxf(v_open, float(sc.car.v))
	check(off < 0.3 and v_tight > 0.0 and v_tight < 8.5 and v_open > 11.0,
		"stray car: keeps to the right lane coming toward us (within %.2f m), hairpins at %.0f km/h, open road %.0f km/h" % [off, v_tight * 3.6, v_open * 3.6])
	if not sc.car.is_empty():
		sc._remove()
	sc.spawn_at(st.START_S + 600.0, 1)
	sc.bump((sc.car.body as Node3D).global_position + Vector3(1.0, 0.0, 0.0))
	var stop_s: float = sc.car.s
	for k in 30:
		sc.tick(dt, st.START_S + 500.0, st.world_at(st.START_S + 500.0, 0.0))
	check(sc.car.crashed and absf(float(sc.car.s) - stop_s) < 0.01 and sc.crashes == 1, "stray car: hit, it stops where it is")
	sc.tick(dt, stop_s + 200.0, st.world_at(stop_s + 200.0, 0.0))
	check(sc.car.is_empty(), "stray car: gone once you're well past (next in %.0f s)" % sc._wait)
	sc.queue_free()
	await process_frame


func _highway() -> void:
	var st = StageGen.new()
	st.opts = {"kind": "highway"}
	st.generate(5, Modes.HIGHWAY_LENGTH)
	var x := _stats(st)
	check(is_equal_approx(x.wmin, st.HIGHWAY_W) and is_equal_approx(x.wmax, st.HIGHWAY_W),
		"highway: %d lanes of %.1f m + shoulders = %.1f m" % [st.HIGHWAY_LANES, st.LANE_W, st.HIGHWAY_W])
	check(x.r_min > 800.0, "highway: sweepers only (tightest radius %.0f m)" % x.r_min)
	check(x.steep <= 0.041, "highway: grades of a few per cent (steepest %.1f %%)" % (x.steep * 100.0))
	check(st.crests.is_empty() and st.length > 7500.0, "highway: %.1f km, no crests or jumps" % (st.length / 1000.0))
	var builder = StageBuilder.new()
	root.add_child(builder)
	builder.build(st)
	var body: StaticBody3D = builder.get_node_or_null("Barriers")
	var pieces: int = int(body.get_meta("pieces", 0)) if body and body.get_child_count() > 0 else 0
	check(builder.get_node_or_null("ConcreteBarriers") != null and pieces > st.length / 8.0 * 2.0 * 0.9,
		"highway built: concrete barriers both sides the whole way (%d solid pieces), lamp posts, gantries" % pieces)
	builder.queue_free()


func _traffic() -> void:
	var st = StageGen.new()
	st.opts = {"kind": "highway"}
	st.generate(5, Modes.HIGHWAY_LENGTH)
	var tr = Traffic.new()
	root.add_child(tr)
	var diff: Dictionary = Modes.DIFFICULTIES.normal
	tr.setup(st, diff, 5, st.START_S)
	var models := {}
	for c in tr.cars:
		models[c.model] = true
	var want: float = float(diff.density) * (tr.AHEAD + tr.BEHIND) / 1000.0
	check(tr.count() >= int(want * 0.7), "traffic: %d cars round the player (normal asks %.0f), models %s" % [tr.count(), want, ", ".join(models.keys())])
	# every traffic car in the registry: its model there, car-sized, on four wheels of its own
	var bad: Array = []
	var pool_ids := {}
	for m in tr._pool:
		pool_ids[m.id] = true
		var len_m: float = m.half_len * 2.0
		var w_m: float = m.half_w * 2.0
		var probe: Node3D = m.scene.instantiate()
		var wheels := 0
		for k in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
			if probe.find_child(k, true, false) != null:
				wheels += 1
		probe.free()
		if len_m < 3.2 or len_m > 6.0 or w_m < 1.5 or w_m > 2.5 or m.height < 1.0 or m.height > 2.3 or wheels != 4:
			bad.append("%s %.1f x %.1f x %.1f m, %d wheels" % [m.id, len_m, w_m, m.height, wheels])
	for e in VehicleRegistry.traffic_pool():
		if not pool_ids.has(e.id):
			bad.append("%s: no model" % e.id)
	check(bad.is_empty() and tr._pool.size() == VehicleRegistry.traffic_pool().size(),
		"traffic: all %d traffic cars load, car-sized, on four wheels%s" % [tr._pool.size(), (" (" + "; ".join(bad) + ")") if not bad.is_empty() else ""])
	# a reset (R) puts the player in the lane with the most room, not on the centre line between
	# two lanes: with a car stopped across lanes 1 and 2 right there, lane 0 or 3
	var rs: float = st.START_S + 300.0
	var saved: Array = tr.cars
	tr.cars = [{"s": rs + 2.0, "d": float(tr.lane_d[1]), "half_len": 2.3}, {"s": rs - 3.0, "d": float(tr.lane_d[2]), "half_len": 2.3},
		{"s": rs + 30.0, "d": float(tr.lane_d[0]), "half_len": 2.3}]
	var rd: float = tr.clear_lane_d(rs)
	tr.cars = saved
	check(is_equal_approx(rd, float(tr.lane_d[3])), "traffic: a reset lands in the clearest lane (d %.1f; the lanes %s)" % [rd, tr.lane_d])
	# a minute: the player weaves up the highway at 150 km/h, changing lanes every few seconds
	tr.running = true
	var ps: float = st.START_S
	var pd := 1.8
	var worst_gap := INF
	var lane_moves := 0
	var max_v := 0.0
	var min_n := 999
	var max_n := 0
	var off_lane := 0
	var lanes_before := {}
	for c in tr.cars:
		lanes_before[c.id] = c.lane
	var dt := 1.0 / 60.0
	for k in 3600:
		ps += 150.0 / 3.6 * dt
		pd = [1.8, -1.8, -5.4, 5.4][int(k / 300) % 4]
		tr.player = {"s": ps, "d": pd, "v": 150.0 / 3.6}
		tr._physics_process(dt)
		for c in tr.cars:
			max_v = maxf(max_v, float(c.v))
			if int(c.to) == int(c.lane) and absf(float(c.d) - float(tr.lane_d[int(c.lane)])) > 0.05:
				off_lane += 1
			if lanes_before.has(c.id) and int(lanes_before[c.id]) != int(c.lane):
				lane_moves += 1
				lanes_before[c.id] = c.lane
			elif not lanes_before.has(c.id):
				lanes_before[c.id] = c.lane
		for i in tr.cars.size():
			for j in range(i + 1, tr.cars.size()):
				var p = tr.cars[i]
				var q = tr.cars[j]
				var share: bool = int(p.lane) == int(q.lane) or int(p.to) == int(q.to) or int(p.lane) == int(q.to) or int(p.to) == int(q.lane)
				if share and absf(float(p.d) - float(q.d)) < 1.9:
					var gap: float = absf(float(p.s) - float(q.s)) - float(p.half_len) - float(q.half_len)
					worst_gap = minf(worst_gap, gap)
		min_n = mini(min_n, tr.count())
		max_n = maxi(max_n, tr.count())
	check(worst_gap > 0.0, "traffic: in a minute nobody ran into anybody (closest bumper to bumper %.1f m)" % worst_gap)
	check(max_v <= float(diff.speed[1]) / 3.6 * 1.05, "traffic: no faster than the difficulty's %.0f km/h (fastest %.0f)" % [diff.speed[1], max_v * 3.6])
	check(lane_moves >= 3 and off_lane == 0, "traffic: %d lane changes (MOBIL), every car on a lane's centre between them" % lane_moves)
	check(min_n >= int(want * 0.5), "traffic: the population holds round the player (%d-%d cars)" % [min_n, max_n])
	tr.queue_free()
	await process_frame


func _score() -> void:
	var sc = CutupScore.new()
	sc.near = 1.2
	var car := {"id": 1, "s": 100.0, "d": 1.8, "v": 100.0 / 3.6, "half_len": 2.4, "half_w": 0.9}
	var me := {"s": 95.0, "d": -0.2, "v": 160.0 / 3.6}          # 0.15 m of gap side to side
	sc.update(0.1, me, [car])
	me.s = 103.0
	var got: Array = sc.update(0.1, me, [car])
	check(got.size() == 1 and sc.combo == 1, "score: passing 0.15 m away at 160 km/h is a near miss (+%d)" % (got[0].points if got.size() else 0))
	var sc2 = CutupScore.new()
	sc2.update(0.1, {"s": 95.0, "d": -2.5, "v": 44.0}, [car])
	var far: Array = sc2.update(0.1, {"s": 103.0, "d": -2.5, "v": 44.0}, [car])
	var sc3 = CutupScore.new()
	sc3.update(0.1, {"s": 95.0, "d": -0.2, "v": 15.0}, [car])
	var slow: Array = sc3.update(0.1, {"s": 103.0, "d": -0.2, "v": 15.0}, [car])
	check(far.is_empty() and slow.is_empty(), "score: 2.4 m away, or at 54 km/h, isn't a near miss")
	var car2 := {"id": 2, "s": 140.0, "d": 1.8, "v": 100.0 / 3.6, "half_len": 2.4, "half_w": 0.9}
	sc.update(0.1, {"s": 135.0, "d": -0.2, "v": 160.0 / 3.6}, [car, car2])
	var second: Array = sc.update(0.1, {"s": 143.0, "d": -0.2, "v": 160.0 / 3.6}, [car, car2])
	check(second.size() == 1 and sc.combo == 2 and second[0].points > got[0].points, "score: the next one's the combo x2 (+%d)" % (second[0].points if second.size() else 0))
	var pot: int = int(sc.pot)
	for k in 50:
		sc.update(0.1, {"s": 150.0 + k, "d": 0.2, "v": 30.0}, [])
	check(sc.combo == 0 and sc.score == pot, "score: %.0f s without one and the combo's banked (%d)" % [CutupScore.COMBO_TIME, sc.score])
	sc.update(0.1, {"s": 195.0, "d": -0.2, "v": 160.0 / 3.6}, [{"id": 3, "s": 200.0, "d": 1.8, "v": 25.0, "half_len": 2.4, "half_w": 0.9}])
	sc.update(0.1, {"s": 203.0, "d": -0.2, "v": 160.0 / 3.6}, [{"id": 3, "s": 200.0, "d": 1.8, "v": 25.0, "half_len": 2.4, "half_w": 0.9}])
	var before: int = sc.score
	sc.crash()
	check(sc.pot == 0.0 and sc.combo == 0 and sc.score == maxi(before - CutupScore.CRASH_PENALTY, 0),
		"score: a crash throws the unbanked combo away and costs %d" % CutupScore.CRASH_PENALTY)


func _touge_rules() -> void:
	var r = TougeRules.new()
	r.best_splits = [40.0, 82.0]
	r.split_check(900.0, 40.0, 30.0)
	var took: bool = r.split_check(1050.0, 40.0, 38.5)
	check(took and is_equal_approx(r.last_split_delta, -1.5), "touge: the 1 km split, 1.5 s up on the best")
	var d = TougeRules.new()
	var fwd := Vector3(0, 0, -1)
	var vel := Vector3(sin(deg_to_rad(30.0)), 0, -cos(deg_to_rad(30.0))) * (60.0 / 3.6)
	for k in 240:
		d.drift_update(1.0 / 120.0, vel, fwd, true)
	check(d.drifting and d.chain > 0.0 and d.multiplier() > 1.0, "touge drift: 30 deg at 60 km/h for 2 s: %d points in the chain, x%.1f" % [int(d.chain), d.multiplier()])
	for k in 200:
		d.drift_update(1.0 / 120.0, fwd * 16.0, fwd, true)
	check(d.chain == 0.0 and d.score > 0 and d.chains == 1, "touge drift: straight for %.1f s banks the chain (%d)" % [TougeRules.CHAIN_GAP, d.score])
	for k in 120:
		d.drift_update(1.0 / 120.0, vel, fwd, true)
	d.drift_update(1.0 / 120.0, vel, fwd, false)
	check(d.chain == 0.0 and d.lost == 1, "touge drift: a wheel off the road loses the chain")


## The LAKESHORE LOOP: the map, built, and its traffic.
func _loop() -> void:
	var LoopGen = load("res://scripts/stage/loop_gen.gd")
	var LoopBuilder = load("res://scripts/stage/loop_builder.gd")
	var st = LoopGen.new()
	st.generate(3)
	var n: int = st._n
	var gap: float = Vector2(st.pts[n].x - st.pts[0].x, st.pts[n].z - st.pts[0].z).length()
	var start_gap: float = Vector2(st.pts[n - 1].x - st.pts[0].x, st.pts[n - 1].z - st.pts[0].z).length()
	var turn: float = (st.heading[n] - st.heading[0]) / TAU
	check(start_gap < st.STEP * 1.01 and absf(absf(turn) - 1.0) < 0.001 and st.length > 27000.0 and st.length < 30000.0,
		"loop: closes on itself (the last sample %.2f m from the first), turns once round, %.1f km" % [start_gap, st.length / 1000.0])
	var x := _stats(st)
	var r_min := INF
	for pc in st.pieces:
		if pc.kind == "arc":
			r_min = minf(r_min, float(pc.r))
	check(r_min >= 600.0 and x.steep <= 0.041, "loop: sweepers (tightest radius %.0f m), grades of 4 %% at most (steepest %.1f %%)" % [r_min, x.steep * 100.0])
	check(st.spans.size() == 3 and st.tunnels.size() == 3 and float(st.spans[0].main) >= 1000.0,
		"loop: %d suspension bridges (main spans %s m), %d tunnels" % [st.spans.size(), ", ".join(st.spans.map(func(b): return "%.0f" % float(b.main))), st.tunnels.size()])
	# never near itself (other than its neighbours along the road): 120 m clear
	var near := INF
	for i in range(0, n, 10):
		for j in range(0, n, 10):
			var along: int = mini(absi(i - j), n - absi(i - j))
			if along * st.STEP > 600.0:
				near = minf(near, Vector2(st.pts[i].x - st.pts[j].x, st.pts[i].z - st.pts[j].z).length())
	check(near > 120.0, "loop: never comes near itself (closest other part %.0f m off)" % near)
	# s round the loop: a point past the start, one lap on, is s + length
	var p: Vector3 = st.world_at(30.0, 1.8)
	var at: Dictionary = st.locate(p, -1)
	check(absf(st.unwrap(at.s, st.length - 10.0) - (st.length + 30.0)) < 1.0 and absf(st.world_at(st.length + 30.0, 1.8).distance_to(p)) < 0.01,
		"loop: s goes on round (a car %.0f m into its second lap is at s %.0f)" % [30.0, st.unwrap(at.s, st.length - 10.0)])
	var b = LoopBuilder.new()
	root.add_child(b)
	b.build(st)
	await physics_frame
	await physics_frame
	# every surface its colliders say they are is one the tyres know (not gravel by default)
	var metas := {}
	var stack: Array = [b]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is CollisionObject3D and nd.has_meta("surface"):
			metas[str(nd.get_meta("surface"))] = true
		stack.append_array(nd.get_children())
	var Surfaces = load("res://scripts/vehicle/physics/surfaces.gd")
	var unknown: Array = metas.keys().filter(func(m): return m != "gravel" and Surfaces.named(m) == Surfaces.named("gravel"))
	check(unknown.is_empty() and not metas.is_empty(), "loop: every collider's surface is a real one (%s)%s" % [", ".join(metas.keys()),
		"" if unknown.is_empty() else "; falling back to gravel: " + ", ".join(unknown)])
	# the road's there underfoot, every lane both ways, all the way round (bridges, tunnels, viaducts)
	var space: PhysicsDirectSpaceState3D = b.get_world_3d().direct_space_state
	var holes: Array = []
	var s := 15.0
	while s < st.length:
		for d in [5.4, -1.8, st.ONCOMING_D - 3.6]:
			var top: Vector3 = st.world_at(s, d) + Vector3.UP * 3.0
			var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 6.0)
			var hit := space.intersect_ray(q)
			if hit.is_empty() or str(hit.collider.get_meta("surface", "")) != "asphalt" or absf(hit.position.y - (top.y - 3.0)) > 0.1:
				holes.append("%.0f/%.1f" % [s, d])
		s += 97.0
	check(holes.is_empty(), "loop built: the road solid in every lane all the way round (%d spots tried)%s" % [int(st.length / 97.0) * 3,
		"" if holes.is_empty() else " HOLES at " + ", ".join(holes.slice(0, 8))])
	check(b.building_count > 300 and b.tree_count > 1000, "loop built: the city's towers (%d), the hills' trees (%d)" % [b.building_count, b.tree_count])
	_far_tier(b, st)
	# traffic on it, insane: packs
	var tr = Traffic.new()
	root.add_child(tr)
	var diff: Dictionary = Modes.DIFFICULTIES.insane
	var start := 0.0                                # (a few hundred metres before an on-ramp on our side)
	for r in st.ramps:
		if r.side == "right" and r.kind == "on":
			start = float(r.s) - 900.0
			break
	tr.setup(st, diff, 3, start)
	tr.running = true
	var ss: Array = tr.cars.map(func(c): return float(c.s))
	ss.sort()
	var packs := 0
	var in_pack := 1
	var biggest := 0
	for k in range(1, ss.size()):
		if float(ss[k]) - float(ss[k - 1]) > 50.0:
			packs += 1 if in_pack >= 5 else 0
			biggest = maxi(biggest, in_pack)
			in_pack = 1
		else:
			in_pack += 1
	packs += 1 if in_pack >= 5 else 0
	biggest = maxi(biggest, in_pack)
	check(packs >= 2 and biggest >= 8, "loop traffic, insane: packs (%d of 5+ cars, the biggest %d) with open road between" % [packs, biggest])
	# rush hour (the owner's "legit in traffic"): cars a km a lane round the player, against the
	# Highway Capacity Manual's levels of service for a freeway (LOS D 16-22, E 22-28 a km a lane)
	var per_lane := func(t) -> float: return float(t.count()) / ((t.AHEAD + t.BEHIND) / 1000.0) / float(t.lanes)
	var dens_i: float = per_lane.call(tr)
	var trh = Traffic.new()
	root.add_child(trh)
	trh.setup(st, Modes.DIFFICULTIES.hard, 3, start)
	var dens_h: float = per_lane.call(trh)
	trh.queue_free()
	check(dens_h >= 14.0 and dens_i >= 20.0 and dens_i > dens_h,
		"rush hour: HARD %.1f, INSANE %.1f cars a km a lane (LOS D from 16, E from 22; they were ~7.5 and ~11)" % [dens_h, dens_i])
	check(tr.oncoming.size() >= 6, "loop traffic: %d cars on the other carriageway" % tr.oncoming.size())
	var on0: float = tr.oncoming[0].s if not tr.oncoming.is_empty() else 0.0
	# drive the player up the road at 140 km/h for 40 s, past ramps: the oncoming go the other way,
	# a car joins from an on-ramp
	var ps: float = start
	var joined := false
	var moved_back := true
	for k in 40 * 120:
		ps += 39.0 / 120.0
		tr.player = {"s": ps, "d": 1.8, "v": 39.0}
		await physics_frame
		for c in tr.cars:
			if int(c.lane) == -1 or int(c.to) == -1:
				joined = true
	if not tr.oncoming.is_empty():
		moved_back = true
	check(joined or not tr.ramp_cars.is_empty(), "loop traffic: cars come in from the on-ramps (%d on a ramp now)" % tr.ramp_cars.size())
	check(tr.count() > 10, "loop traffic: still %d cars round the player after %.1f km (packs refilled)" % [tr.count(), (ps - start) / 1000.0])
	tr.queue_free()
	b.queue_free()
	await process_frame


## The LAKESHORE LOOP's far tier (the 31-building pack behind the city's front rows:
## scripts/stage/city_skyline.gd): there, its three levels of detail, no shadows; every building
## on the ground as drawn (the land's triangles under its footprint: nowhere above them, at most
## 0.5 m into them at the lowest), 40 m and more from the road's centreline (and the ramps'),
## its footprint clear of every other building's (the far ones, the front rows, the drawn
## towers left).
func _far_tier(b, st) -> void:
	var EnvAssets = load("res://scripts/stage/env_assets.gd")
	var CitySkyline = load("res://scripts/stage/city_skyline.gd")
	var far: Node = b.get_node_or_null("CitySkyline")
	var feet: Array = []                            # [footprint, foot height, design]
	var lods := {}
	var shadows := 0
	var drawn := 0
	if far != null:
		for mmi in far.get_children():
			lods[int(mmi.get_meta("lod", 0))] = true
			shadows += 1 if mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else 0
			drawn += mmi.multimesh.instance_count if int(mmi.get_meta("lod", 0)) == 0 else 0
		# (where each stands: the node's record; a MultiMesh's transforms can't be read back headless)
		for e in far.get_meta("buildings", []):
			var sz: Array = EnvAssets.info(str(e[0])).get("size", [0.0, 0.0, 0.0])
			var xf: Transform3D = e[1]
			feet.append([_foot(xf, Vector3.ZERO, float(sz[0]), float(sz[2])), xf.origin.y, str(e[0])])
	var designs := {}
	for f in feet:
		designs[f[2]] = true
	check(feet.size() > 150 and drawn == feet.size() and designs.size() >= 12 and lods.size() == 3 and shadows == 0,
		"loop's far tier: %d buildings of the 31-building pack (%d designs; %d drawn), three levels of detail, no shadows" % [feet.size(), designs.size(), drawn])
	# the ground as drawn: the ribbons along the road (the chunks' "terrain") and the far land's tiles
	var faces := PackedVector3Array()
	for n in b.get_children():
		if n is MeshInstance3D and String(n.name).begins_with("Land"):
			faces.append_array((n as MeshInstance3D).mesh.get_faces())
		elif String(n.name).begins_with("Chunk") and n.get_node_or_null("terrain") != null:
			faces.append_array((n.get_node("terrain") as MeshInstance3D).mesh.get_faces())
	var land := TriangleMesh.new()
	land.create_from_faces(faces)
	var afloat: Array = []
	var sunk: Array = []
	var worst := 0.0
	for f in feet:
		var lo := INF
		for p in _foot_points(f[0]):
			var hit: Dictionary = land.intersect_ray(Vector3(p.x, 2000.0, p.y), Vector3.DOWN)
			lo = minf(lo, (hit.position as Vector3).y if not hit.is_empty() else -INF)
		worst = maxf(worst, absf(float(f[1]) - lo))
		if float(f[1]) > lo + 0.05:
			afloat.append("%s at %.0f, %.0f (%.2f m up)" % [f[2], f[0].c.x, f[0].c.y, float(f[1]) - lo])
		elif float(f[1]) < lo - 0.5:
			sunk.append("%s at %.0f, %.0f (%.2f m down)" % [f[2], f[0].c.x, f[0].c.y, lo - float(f[1])])
	check(not feet.is_empty() and afloat.is_empty() and sunk.is_empty(),
		"loop's far tier: every building on the ground (its foot within %.2f m of the lowest ground under it)%s" % [worst,
		"" if afloat.is_empty() and sunk.is_empty() else "; FLOATING " + ", ".join(afloat.slice(0, 4)) + " SUNK " + ", ".join(sunk.slice(0, 4))])
	# off the road: its footprint 40 m and more from every sample of the centreline and the ramps
	var grid := {}
	var road_pts: Array = []
	for i in st._n:
		road_pts.append(Vector2(st.pts[i].x, st.pts[i].z))
	for r in st.ramps:
		for q in st.ramp_path(r).pts:
			road_pts.append(Vector2(q.x, q.z))
	for q in road_pts:
		var key := Vector2i(floori(q.x / 100.0), floori(q.y / 100.0))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(q)
	var nearest := INF
	var near_road: Array = []
	for f in feet:
		var r: Dictionary = f[0]
		var key := Vector2i(floori(r.c.x / 100.0), floori(r.c.y / 100.0))
		var d := INF
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				for q in grid.get(key + Vector2i(dx, dz), []):
					var v: Vector2 = q - r.c
					var out := Vector2(maxf(absf(v.dot(r.ax)) - r.hx, 0.0), maxf(absf(v.dot(r.az)) - r.hz, 0.0))
					d = minf(d, out.length())
		nearest = minf(nearest, d)
		if d < 40.0:
			near_road.append("%s at %.0f, %.0f (%.0f m)" % [f[2], r.c.x, r.c.y, d])
	check(not feet.is_empty() and near_road.is_empty(), "loop's far tier: none near the road or a ramp (the nearest %.0f m from the centreline)%s" % [nearest,
		"" if near_road.is_empty() else "; TOO NEAR " + ", ".join(near_road.slice(0, 4))])
	# no two footprints overlapping: the far ones, the front rows, the drawn towers left
	var others: Array = []
	for n in b.get_children():
		if n is MeshInstance3D and String(n.name).begins_with("Building_"):
			var ab: AABB = (n as MeshInstance3D).mesh.get_aabb()
			others.append(_foot(n.transform, ab.get_center(), ab.size.x, ab.size.z))
		elif n is MultiMeshInstance3D and String(n.name).begins_with("Towers"):
			for k in n.multimesh.instance_count:
				var xf: Transform3D = n.multimesh.get_instance_transform(k)
				others.append(_foot(Transform3D(xf.basis.orthonormalized(), xf.origin), Vector3.ZERO, xf.basis.x.length(), xf.basis.z.length()))
	var clashes: Array = []
	var cells := {}
	for k in feet.size():
		var key := Vector2i(floori(feet[k][0].c.x / 100.0), floori(feet[k][0].c.y / 100.0))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(k)
	for k in feet.size():
		var r: Dictionary = feet[k][0]
		var key := Vector2i(floori(r.c.x / 100.0), floori(r.c.y / 100.0))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for j in cells.get(key + Vector2i(dx, dz), []):
					if j > k and CitySkyline.overlap(r, feet[j][0]):
						clashes.append("%s / %s at %.0f, %.0f" % [feet[k][2], feet[j][2], r.c.x, r.c.y])
		for o in others:
			if o.c.distance_to(r.c) < 260.0 and CitySkyline.overlap(r, o):
				clashes.append("%s / a front-row building at %.0f, %.0f" % [feet[k][2], r.c.x, r.c.y])
	check(not feet.is_empty() and clashes.is_empty(), "loop's far tier: no building on another (%d far, %d front-row and drawn ones round them)%s" % [feet.size(), others.size(),
		"" if clashes.is_empty() else "; CLASH " + ", ".join(clashes.slice(0, 4))])


## A building's footprint on the ground: its middle (the transform's origin plus `mid`, in its
## own space), its sides' directions and half sizes (sx, sz: its size along its own x and z).
func _foot(xf: Transform3D, mid: Vector3, sx: float, sz: float) -> Dictionary:
	var c: Vector3 = xf * mid
	return {"c": Vector2(c.x, c.z), "ax": Vector2(xf.basis.x.x, xf.basis.x.z).normalized(),
		"az": Vector2(xf.basis.z.x, xf.basis.z.z).normalized(), "hx": sx * 0.5, "hz": sz * 0.5}


## Its middle, corners and sides' middles.
func _foot_points(r: Dictionary) -> Array:
	var out: Array = []
	for u in [-1.0, 0.0, 1.0]:
		for v in [-1.0, 0.0, 1.0]:
			out.append(r.c + r.ax * r.hx * u * 0.98 + r.az * r.hz * v * 0.98)
	return out


## The highway battles: a rival, a challenge, two races (one won, one lost).
func _battles() -> void:
	var LoopGen = load("res://scripts/stage/loop_gen.gd")
	var Rivals = load("res://scripts/game/rivals.gd")
	var st = LoopGen.new()
	st.generate(3)
	var tr = Traffic.new()
	root.add_child(tr)
	var start: float = st.spans[0].s0 - 6000.0         # (the hills: no ramps to muddle it)
	tr.setup(st, Modes.DIFFICULTIES.hard, 4, start)
	tr.running = true
	var rv = Rivals.new()
	root.add_child(rv)
	rv.setup(tr, st, 4)
	var results := []
	for race in 2:
		var ps: float = start + race * 8000.0
		var v := 26.0
		tr.player = {"s": ps, "d": 1.8, "v": v}
		rv._next = 0.0
		rv.state = "none"
		rv.pick_only = "hachi" if race == 0 else "ghost"   # (a level-1 rival, then a level-5 one: the result's the speed's, not the draw's)
		rv.tick(0.01, tr.player, false)
		var spawned: bool = rv.state == "cruise" and not rv.rival.is_empty()
		# catch it up (straight down its lane), flash it from close behind
		var t := 0.0
		while rv.state == "cruise" and t < 60.0:
			var gap: float = float(rv.rival.s) - ps
			v = 45.0 if gap > 30.0 else float(rv.rival.v)
			ps += v / 120.0
			tr.player = {"s": ps, "d": float(rv.rival.d), "v": v}
			await physics_frame
			rv.tick(1.0 / 120.0, tr.player, rv.can_challenge(tr.player))
			t += 1.0 / 120.0
		var flashed: bool = rv.state == "intro"
		# the race: the player at 300 km/h the first time, 110 the second (in a lane of its own:
		# the test's player is a point that goes through cars; the rival has to go round them)
		var pv := 300.0 / 3.6 if race == 0 else 110.0 / 3.6
		var overlaps := 0
		var passed := {}
		var gate := false
		t = 0.0
		while rv.state in ["intro", "race"] and t < 200.0:
			ps += (pv if rv.state == "race" else float(rv.rival.v)) / 120.0
			tr.player = {"s": ps, "d": -5.4, "v": pv}
			await physics_frame
			rv.tick(1.0 / 120.0, tr.player, false)
			t += 1.0 / 120.0
			gate = gate or rv._gate != null
			if rv.state == "race":
				var me: Dictionary = rv.rival
				for c in tr.cars:
					if c == me:
						continue
					var ds: float = absf(float(c.s) - float(me.s))
					if ds < float(c.half_len) + float(me.half_len) - 0.3 and absf(float(c.d) - float(me.d)) < float(c.half_w) + float(me.half_w) - 0.2:
						overlaps += 1
					if float(me.s) > float(c.s) + 10.0:
						passed[c.id] = true
		var ev: Array = rv.events.map(func(e): return e[0])
		results.append({"spawned": spawned, "flashed": flashed, "gate": gate, "overlaps": overlaps, "passed": passed.size(), "events": ev,
			"beaten": rv.beaten, "lost": rv.lost})
		rv.events.clear()
		rv._drop()
	var r0: Dictionary = results[0]
	var r1: Dictionary = results[1]
	check(r0.spawned and r0.flashed and r0.gate, "battles: a rival shows up in the traffic, flashing it from close behind starts the race (a gate 3 km on)")
	check(r0.beaten == 1 and r1.lost == 1, "battles: at 300 km/h the player wins it, at 110 the rival does (%s / %s)" % [
		" · ".join(r0.events.slice(-1)), " · ".join(r1.events.slice(-1))])
	check(r0.overlaps == 0 and r1.overlaps == 0 and r1.passed >= 5, "battles: the rival races through the traffic (past %d cars), never through one%s" % [r1.passed, "" if r0.overlaps + r1.overlaps == 0 else " (overlapping a car %d + %d ticks)" % [r0.overlaps, r1.overlaps]])
	rv.queue_free()
	tr.queue_free()
	await process_frame


## The game in a mode: it loads, the run goes, and it ends with the mode's own results.
## Settings' TIME OF DAY: AUTO leaves a run's light alone; an hour rides with the run
## (to every machine) with the mood nearest it.
func _time_of_day() -> void:
	var o: Dictionary = Modes.touge_opts(5, "down")
	var auto: Dictionary = Modes.with_time(o, -1.0)
	var noon: Dictionary = Modes.with_time(o, 13.0)
	var dusk: Dictionary = Modes.with_time(o, 18.5)
	var late: Dictionary = Modes.with_time(Modes.cutup_opts(5), 1.5)
	check(auto == o and float(noon.time) == 13.0 and noon.mood == "day" and dusk.mood == "golden" and late.mood == "night" and float(late.time) == 1.5,
		"time of day: AUTO keeps the run's light (%s); 13:00 day, 18:30 golden, 01:30 night ride with the run" % o.mood)


func _ghost() -> void:
	var Ghost = load("res://scripts/game/ghost.gd")
	var k := "test/ghost/%d" % Time.get_ticks_usec()
	var g = Ghost.new()
	root.add_child(g)
	g.setup(k)
	check(g.best.is_empty(), "ghost: none for a pass never driven")
	var t := 0.0
	while t <= 10.0:                                    # 10 s at 10 m/s along x, turning slowly
		g.tick(t, Transform3D(Basis(Vector3.UP, t * 0.1), Vector3(t * 10.0, 0.0, 0.0)))
		t += 1.0 / 120.0
	g.save_record("hachi")
	g.queue_free()
	var g2 = Ghost.new()
	root.add_child(g2)
	g2.setup(k)
	var at = Ghost.sample(g2.best, 5.05)
	check(not g2.best.is_empty() and g2.best_model == "hachi" and g2._body != null and at != null
		and absf((at as Transform3D).origin.x - 50.5) < 0.05 and absf((at as Transform3D).basis.get_euler().y - 0.505) < 0.01,
		"ghost: saved, loaded (%d samples, %s) and played back between samples (x %.2f m at 5.05 s, want 50.50)" % [
		g2.best.size() / Ghost.STRIDE, g2.best_model, (at as Transform3D).origin.x if at != null else -1.0])
	g2.tick(5.0, Transform3D(Basis(), Vector3(50.0, 30.0, 0.0)))
	var seen: bool = g2._body.visible
	g2.tick(5.0, Transform3D(Basis(), Vector3(50.5, 0.5, 0.0)))
	var near_hidden: bool = not g2._body.visible
	check(seen and near_hidden and Ghost.sample(g2.best, 10.5) == null,
		"ghost: shown away from the player, gone right where the player is (the start: not in the cockpit), gone past its finish")
	DirAccess.remove_absolute(Ghost.file_for(k))
	g2.queue_free()


## A touge time attack: the record leaves a ghost, and the next run on the pass races it.
func _ghost_game() -> void:
	var Ghost = load("res://scripts/game/ghost.gd")
	root.get_node("Net").solo()
	var o: Dictionary = Modes.touge_opts(4, "up", "time")
	o["length"] = 1200.0
	var file: String = Ghost.file_for(Modes.best_key(o, 4))
	DirAccess.remove_absolute(file)
	var Profile = load("res://scripts/game/profile.gd")
	Profile.ensure_loaded()
	Profile.mode_bests.erase(Modes.best_key(o, 4))
	var Game = load("res://scripts/game.gd")
	var ghosts := []
	for run in 2:
		var g = Game.new()
		root.add_child(g)
		await g.start(4, 1, o)
		ghosts.append(g.ghost.best.size() / Ghost.STRIDE)
		g.begin_countdown()
		g.use_autopilot = true
		var t := 0.0
		var gap := 0.0                                  # (the same autopilot drives both: the ghost runs with it)
		while g.state != "finished" and t < 160.0:
			await physics_frame
			t += 1.0 / 120.0
			if run == 1 and g.state == "running":
				var at = Ghost.sample(g.ghost.best, g.stage_time)
				if at != null:
					gap = maxf(gap, (at as Transform3D).origin.distance_to(g.car.global_position))
		if run == 1:
			check(g.ghost._body != null and gap > 0.0 and gap < 40.0,
				"game: the second time attack on the pass races the first one's ghost (%d samples; it ran within %.1f m of the same autopilot)" % [ghosts[1], gap])
		g.queue_free()
		await process_frame
	check(ghosts[0] == 0 and ghosts[1] > 50 and FileAccess.file_exists(file),
		"game: the first time attack leaves a ghost (none before it, %d samples after)" % ghosts[1])
	DirAccess.remove_absolute(file)


func _game(m: String) -> void:
	root.get_node("Net").solo()
	var Game = load("res://scripts/game.gd")
	var g = Game.new()
	root.add_child(g)
	var o: Dictionary = Modes.touge_opts(3, "up", "drift") if m == "touge" else Modes.cutup_opts(3, "hard")
	o["length"] = 1400.0
	await g.start(3, 1, o)
	check(g.built and g.mode == m and (g.traffic != null) == (m == "cutup"), "game: a %s run loads (%s)" % [m, Modes.title(o, g.st).replace("\n", " · ")])
	if m == "cutup":
		# (the owner: cut up needs no start: no ENTER, no ding-ding countdown, no clock at the top)
		for i in 30:
			await physics_frame
		var shown: String = g._lights.time_text
		check(g.state == "running" and shown == "" and float(g._lights.since_go) >= 99.0,
			"game: cut up starts by itself as it loads (%s in 0.25 s), no countdown, no start lights, no clock at the top ('%s')" % [g.state, shown])
	g.begin_countdown()
	g.use_autopilot = true
	var t := 0.0
	var most := 0
	var stuck := 0.0
	while g.state != "finished" and t < (60.0 if g.looped else 160.0):
		await physics_frame
		t += 1.0 / 120.0
		if g.traffic:
			most = maxi(most, g.traffic.count())
		# (the autopilot doesn't steer round traffic: stuck in a pack, it presses R as a player would)
		stuck = stuck + 1.0 / 120.0 if g.state == "running" and g.car.kmh() < 5.0 else 0.0
		if stuck > 3.0:
			g.reset_car()
			stuck = 0.0
	if g.looped:
		# (cut up starts at the gas station off the highway: its way out first, then on round)
		var s0: float = g._start_s()
		check(g.car_s > s0 + 300.0, "game: on the loop the run goes on (%.0f m in a minute from %s, %d resets; no finish)" % [
			g.car_s - s0, "the gas station" if g._at_station() else "the start line", g.resets])
		g._end_run()                                   # (no finish on a loop: the player ends the run)
	if m == "cutup":
		check(g.cutup != null and most > 0, "game: cut up's score and up to %d traffic cars running (score %d, %d near misses, %d crashes)" % [
			most, g.cutup.total(), g.cutup.near_misses, g.cutup.crashes])
	check(g.state == "finished" and not g.mode_result.get("lines", []).is_empty(),
		"game: the %s run ends with its results (%s)" % [m, " / ".join(g.mode_result.get("lines", []))])
	g.queue_free()
	await process_frame
