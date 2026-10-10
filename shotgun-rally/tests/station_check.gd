extends SceneTree
## Cut up's start: the gas station (LoopGen.station, LoopBuilder._station, game.gd _grid_spot).
## Run: godot --headless --fixed-fps 120 --path . -s tests/station_check.gd
##   * there's one, where one of our side's junctions' two ramps end, on flat ground clear of the
##     highway; the eight pumps' places are on its forecourt, a car's length apart
##   * the forecourt is solid at every place (a ray down hits it at its plane), the shop, the
##     islands and the planter wall too; the wall's open where each ramp comes in (a ray along
##     the ramp's last stretch into the forecourt hits nothing)
##   * the land under it is flat (the ground's own height eased to just under it)
##   * a cut-up run starts at the pumps (car and countdown), its traffic round the station's
##     stretch of highway, and the autopilot drives out: across the forecourt, up the ramp, onto
##     the highway (in its lanes) within 45 s, without a crash
## Prints one [station] line per check; exits 1 on any FAIL.

var fails := 0
var LoopGen
var LoopBuilder


func check(ok: bool, what: String) -> void:
	print("[station] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	LoopGen = load("res://scripts/stage/loop_gen.gd")
	LoopBuilder = load("res://scripts/stage/loop_builder.gd")
	await _layout()
	await _drive_out()
	print("[station] %s" % ("STATION OK" if fails == 0 else "STATION FAIL"))
	quit(1 if fails else 0)


func _layout() -> void:
	var st = LoopGen.new()
	st.generate(3)
	var S: Dictionary = st.station
	check(not S.is_empty(), "a gas station on the loop")
	if S.is_empty():
		return
	check(S.off.side == "right" and S.on.side == "right" and S.off.kind == "off" and S.on.kind == "on",
		"where our side's junction ends up (exit at %.0f, entry at %.0f)" % [S.off.s, S.on.s])
	check(float(S.flat) < 1.0 and absf(float(S.gy)) < 0.03, "on flat ground (the land within %.2f m of it, %.1f %% across)" % [S.flat, S.gy * 100.0])
	var near_road := INF
	for a in [-1.0, 0.0, 1.0]:
		for b in [-1.0, 0.0, 1.0]:
			var p: Vector3 = st.station_at(a * st.STATION_HALF.x, b * st.STATION_HALF.y)
			var at: Dictionary = st.locate(p)
			near_road = minf(near_road, absf(float(at.d)))
	check(near_road > st.EDGE + 25.0, "clear of the highway (its nearest corner %.0f m from the road's middle)" % near_road)
	var spots_ok := true
	var min_gap := INF
	for k in 8:
		var sp: Array = st.station_spot(k)
		spots_ok = spots_ok and st.on_station(sp[0].x, sp[0].z, -3.0)
		for j in k:
			min_gap = minf(min_gap, (sp[0] as Vector3).distance_to(st.station_spot(j)[0]))
	check(spots_ok and min_gap >= 5.5, "the eight pumps' places on the forecourt, %.1f m apart at least" % min_gap)
	var flat_land := 0.0
	for a in range(-30, 31, 6):
		for b in range(-20, 21, 5):
			var p: Vector3 = st.station_at(float(a), float(b))
			flat_land = maxf(flat_land, absf(st.land_at(p.x, p.z) - (p.y - st.STATION_SINK)))
	check(flat_land < 0.02, "the land flat under it (%.3f m off)" % flat_land)
	# built: solid where it should be
	var b = LoopBuilder.new()
	b.mood = "day"
	root.add_child(b)
	await b.build_async(st, func(_f, _w): pass)
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = b.get_world_3d().direct_space_state
	var solid := 0
	for k in 8:
		var sp: Vector3 = st.station_spot(k)[0]
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(sp + Vector3.UP * 3.0, sp + Vector3.DOWN * 3.0))
		if not hit.is_empty() and absf(float(hit.position.y) - sp.y) < 0.08:
			solid += 1
	check(solid == 8, "the forecourt solid under every pump's place (%d of 8)" % solid)
	# rays across each, from outside it (a, b from, b to, height)
	var hits: Array = []
	for q in [["the shop", 0.0, 11.0, 17.0, 1.0], ["an island", 0.0, -6.5, -11.5, 0.1], ["a column", -5.7, -0.8, -5.2, 2.0],
			["the wall", 30.0, 21.0, 27.0, 0.4]]:
		var p0: Vector3 = st.station_at(q[1], q[2], q[4])
		var p1: Vector3 = st.station_at(q[1], q[3], q[4])
		hits.append("%s %s" % [q[0], "yes" if not space.intersect_ray(PhysicsRayQueryParameters3D.create(p0, p1)).is_empty() else "NO"])
	check(not ", ".join(hits).contains("NO"), "solid: " + ", ".join(hits))
	var open := 0
	for rmp in [S.off, S.on]:
		var pts: PackedVector3Array = st.ramp_path(rmp).pts
		var k := pts.size() - 1
		while k > 0 and st.on_station(pts[k].x, pts[k].z, 2.0):
			k -= 1
		var from: Vector3 = pts[maxi(k - 3, 0)] + Vector3.UP * 0.6
		var to: Vector3 = pts[pts.size() - 1] + Vector3.UP * 0.6
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to)).is_empty():
			open += 1
	check(open == 2, "the wall open where both ramps come in (%d of 2)" % open)
	b.queue_free()
	await process_frame


func _drive_out() -> void:
	var Modes = load("res://scripts/game/modes.gd")
	root.get_node("Net").solo()
	var g = load("res://scripts/game.gd").new()
	root.add_child(g)
	var o: Dictionary = Modes.cutup_opts(3, "easy")
	await g.start(3, 1, o)
	var at_pumps: bool = g.st.on_station(g.car.global_position.x, g.car.global_position.z, -2.0)
	check(g._at_station() and at_pumps, "a cut-up run starts at the pumps (the car at %s)" % g.car.global_position)
	var s0: float = g._start_s()
	var near := 0
	for c in g.traffic.cars:
		if absf(g.traffic._ds(float(c.s), s0)) < 900.0:
			near += 1
	check(near > 0 and near == g.traffic.cars.size(), "its traffic round the station's stretch of highway (%d cars)" % near)
	g.begin_countdown()
	g.use_autopilot = true
	var t := 0.0
	var out := -1.0
	while t < 60.0:
		await physics_frame
		t += 1.0 / 120.0
		if g.state == "running" and out < 0.0 and absf(g.car_d) < g.st.EDGE:
			out = t
			break
	check(out > 0.0 and out < 45.0, "the autopilot drives out of it onto the highway, in its lanes (%.1f s)" % out)
	check(g.cutup.crashes == 0 and g.resets == 0, "without a crash or a reset (%d crashes, %d resets)" % [g.cutup.crashes, g.resets])
	g.queue_free()
	await process_frame
