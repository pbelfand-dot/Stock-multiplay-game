extends SceneTree
## The modes beyond rally stages: the touge and cut up.
## Run: godot --headless --fixed-fps 120 --path . -s tests/modes_check.gd
##   * a touge: a narrow two-lane pass full of hairpins that climbs (or falls) all
##     the way, no steeper than its limit, the same pass from the same seed; built
##     with guardrails, curve mirrors and cedar forest
##   * a highway: four lanes, sweepers only, a few per cent at most; concrete
##     barriers both sides the whole way
##   * the traffic: the registry's traffic cars on it, about as many as the
##     difficulty asks; a minute of driving with the player weaving through: no
##     car runs into another, they keep to the lanes and their speeds, some change
##     lanes, the population holds
##   * the cut-up score: near misses (close and fast count, slow or far don't), the
##     combo, banking, a crash
##   * the touge rules: splits against a best, drift points and chains, a chain lost
##   * the game itself in each mode: loads, runs, ends with the mode's results
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
	_touge()
	_highway()
	await _traffic()
	_score()
	_touge_rules()
	await _game("touge")
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
		var climbs: bool = x.rise > 80.0 if dir == "up" else x.rise < -80.0
		check(climbs, "touge %s: %+.0f m from start to finish" % ["uphill" if dir == "up" else "downhill", x.rise])
		check(st.crests.filter(func(c): return c.jump).is_empty() and st.bridges.is_empty() and st.villages.is_empty() and st.puddles.is_empty(),
			"touge: no jumps, bridges, villages or puddles; asphalt end to end (%s)" % st.describe())
	var a = StageGen.new()
	a.opts = {"kind": "touge", "dir": "up"}
	a.generate(11, 4000.0)
	var b = StageGen.new()
	b.opts = {"kind": "touge", "dir": "up"}
	b.generate(11, 4000.0)
	check(a.pts == b.pts and a.touge_name() == b.touge_name(), "touge: the same seed builds the same pass (%s) on every machine" % a.touge_name())
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
	var pieces := body.get_child_count() if body else 0
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


## The game in a mode: it loads, the run goes, and it ends with the mode's own results.
func _game(m: String) -> void:
	root.get_node("Net").solo()
	var Game = load("res://scripts/game.gd")
	var g = Game.new()
	root.add_child(g)
	var o: Dictionary = Modes.touge_opts(3, "up", "drift") if m == "touge" else Modes.cutup_opts(3, "hard")
	o["length"] = 1400.0
	await g.start(3, 1, o)
	check(g.built and g.mode == m and (g.traffic != null) == (m == "cutup"), "game: a %s run loads (%s)" % [m, Modes.title(o, g.st).replace("\n", " · ")])
	g.begin_countdown()
	g.use_autopilot = true
	var t := 0.0
	var most := 0
	while g.state != "finished" and t < 160.0:
		await physics_frame
		t += 1.0 / 120.0
		if g.traffic:
			most = maxi(most, g.traffic.count())
	if m == "cutup":
		check(g.cutup != null and most > 0, "game: cut up's score and up to %d traffic cars running (score %d, %d near misses, %d crashes)" % [
			most, g.cutup.total(), g.cutup.near_misses, g.cutup.crashes])
	check(g.state == "finished" and not g.mode_result.get("lines", []).is_empty(),
		"game: the %s run ends with its results (%s)" % [m, " / ".join(g.mode_result.get("lines", []))])
	g.queue_free()
	await process_frame
