extends SceneTree
## The LAKESHORE LOOP's toll plaza (LoopGen.toll, LoopBuilder._toll_plaza, Traffic's rules there).
## Run: godot --headless --fixed-fps 120 --path . -s tests/toll_check.gd [-- --only=build|traffic]
##   * it's found where the road runs straight on the ground, clear of ramps, every layout
##   * the lanes fan out round the islands: a car-sized box down the middle of every lane, both
##     ways, through the booths touches nothing; the closed lane's gate (mixed) stops it
##   * the islands, booths and columns are solid; the boards say what each lane is; a light
##     over each lane; the median barrier gives way to the middle island
##   * the autopilot's line goes between the islands, never into one
##   * traffic through it (mixed): out of the closed lane before the booths, nobody changing
##     lanes among the islands or touching one, slowed to the layout's speed; the other
##     carriageway's cars clear of the islands too
## Prints one [toll] line per check; exits 1 on any FAIL.

var LoopGen
var LoopBuilder
var Traffic
var Modes
var fails := 0


func check(ok: bool, what: String) -> void:
	print("[toll] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _initialize() -> void:
	LoopGen = load("res://scripts/stage/loop_gen.gd")
	LoopBuilder = load("res://scripts/stage/loop_builder.gd")
	Traffic = load("res://scripts/stage/traffic.gd")
	Modes = load("res://scripts/game/modes.gd")
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	await process_frame
	if only in ["", "build"]:
		for layout in ["open", "mixed", "event"]:
			await _build(layout)
	if only in ["", "traffic"]:
		await _traffic()
	print("[toll] %s" % ("TOLL OK" if fails == 0 else "TOLL FAIL"))
	quit(1 if fails else 0)


func _stage(layout: String):
	var st = LoopGen.new()
	st.opts = {"toll": layout}
	st.generate(3)
	return st


## The islands' d at the booths (as the builder puts them).
func _islands(b) -> Array:
	return b._toll_islands()


## The plaza alone (its steps: the rest of the loop isn't needed to test it).
func _plaza(st):
	var b = LoopBuilder.new()
	root.add_child(b)
	b._prepare(st)
	b._toll_plaza()
	b._finish()
	return b


func _build(layout: String) -> void:
	var st = _stage(layout)
	var t: Dictionary = st.toll
	var s0: float = t.get("s", 0.0)
	var straight := 0.0
	var ground := true
	var x: float = s0 - float(t.get("approach", 0.0)) - 40.0
	while x < s0 + 60.0:
		straight = maxf(straight, absf(st.curv_at(x)))
		ground = ground and st.support_at(x) == "ground"
		x += 10.0
	check(not t.is_empty() and t.layout == layout and ground and straight < 1.0 / 1500.0,
		"%s: a plaza at s %.0f, on the ground and straight (radius %.0f m at the least) from the approach on; closed lanes %s, %s" % [
		layout, s0, 1.0 / maxf(straight, 1e-6), t.get("closed", []), "no slowing" if float(t.get("speed", 0.0)) <= 0.0 else "%.0f km/h through" % (float(t.speed) * 3.6)])
	var b = _plaza(st)
	for k in 3:
		await physics_frame
	var space: PhysicsDirectSpaceState3D = b.get_world_3d().direct_space_state
	# a car down the middle of each lane (fanned out) through the booths
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.95, 1.0, 4.6)
	q.shape = box
	var blocked: Array = []
	var clear_closed: Array = []
	for lane in 4:
		for dir in [1, -1]:
			var base: float = st.EDGE - st.LANE_W * (lane + 0.5)
			if dir == -1:
				base = st.ONCOMING_D - base
			var hit_any := false
			var s: float = s0 - float(t.half) - 60.0
			while s < s0 + float(t.half) + 60.0:
				var d: float = st.toll_d(base, s)
				q.transform = Transform3D(Basis(Vector3.UP, -st.heading_at(s)), st.world_at(s, d) + Vector3.UP * 0.75)
				if not space.intersect_shape(q, 1).is_empty():
					hit_any = true
				s += 0.5
			var closed: bool = st.toll_closed(lane)
			if hit_any and not closed:
				blocked.append("%s lane %d" % ["our" if dir == 1 else "their", lane])
			if closed and not hit_any:
				clear_closed.append("%s lane %d" % ["our" if dir == 1 else "their", lane])
	check(blocked.is_empty() and clear_closed.is_empty(),
		"%s: a car-sized box down the middle of every open lane, both ways, through the booths touches nothing%s%s" % [layout,
		"" if t.closed.is_empty() else "; the closed lanes' gates stop it",
		("; BLOCKED: " + ", ".join(blocked)) if not blocked.is_empty() else ("; closed but open: " + ", ".join(clear_closed)) if not clear_closed.is_empty() else ""])
	# the islands are solid (a ray down onto each finds its top), the lanes between them have room
	var missing: Array = []
	var narrow := INF
	var isl: Array = _islands(b)
	for k in isl.size():
		var top: Vector3 = st.world_at(s0 + 10.0, float(isl[k].d)) + Vector3.UP * 3.0
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 4.0))
		if hit.is_empty() or absf(hit.position.y - (top.y - 3.0 + 0.25)) > 0.05:
			missing.append("%.1f" % float(isl[k].d))
		if k > 0:
			narrow = minf(narrow, absf(float(isl[k].d) - float(isl[k - 1].d)) - (float(isl[k].w) + float(isl[k - 1].w)) * 0.5)
	check(missing.is_empty() and isl.size() == 9 and narrow > 3.4,
		"%s: %d islands, solid (kerb 0.25 m), each lane between them %.2f m clear at the least%s" % [layout, isl.size(), narrow,
		("; NOT SOLID at d " + ", ".join(missing)) if not missing.is_empty() else ""])
	# the boards, the lights, the median
	var texts: Array = []
	for n in b.get_children():
		if n is Label3D:
			texts.append(String((n as Label3D).text))
	var closed_boards := texts.filter(func(x): return x == "CLOSED").size()
	var go := texts.filter(func(x): return x == "GO").size()
	var etc := texts.filter(func(x): return x.begins_with("ETC")).size()
	var want_ok: bool = (closed_boards == 2 and etc == 6) if layout == "mixed" else ((go == 8) if layout == "event" else (etc == 8))
	check(want_ok and b._toll_lamp_heads().size() == 8 and b._toll_island_at(s0) and not b._toll_island_at(s0 + float(t.half) + 5.0),
		"%s: the lanes' boards (%d ETC, %d CLOSED, %d GO), a light over each of the 8 lanes, the median barrier making way for the middle island" % [
		layout, etc, closed_boards, go])
	var cones: Node = b.get_node_or_null("TollCones1")
	check((cones != null) == (layout == "mixed"), "%s: %s" % [layout, "cones closing the closed lane off before the booths" if layout == "mixed" else "no cones (every lane open)"])
	# the autopilot's line: between the islands (from the middle of the road, a lane line, a lane)
	var worst := INF
	for d in [0.0, 1.8, -1.8, 3.6, 5.4, -5.4, -3.6]:
		for s in [s0 - float(t.half), s0, s0 + float(t.half)]:
			var line: float = st.toll_lane_d(d, s)
			for i2 in isl:
				if absf(float(i2.d) - line) < 6.0:
					worst = minf(worst, absf(float(i2.d) - line) - float(i2.w) * 0.5)
	check(worst > 1.1, "%s: the autopilot's line goes between the islands (%.2f m from the nearest island's side at the least: a car's half and more)" % [layout, worst])
	b.free()
	await process_frame


## Traffic through the mixed layout: the player at 30 m/s from 1.2 km before the plaza to
## 600 m past it, insane traffic (packs) about.
func _traffic() -> void:
	var st = _stage("mixed")
	var t: Dictionary = st.toll
	var s0: float = t.s
	var b = _plaza(st)
	var tr = Traffic.new()
	root.add_child(tr)
	tr.setup(st, Modes.DIFFICULTIES.insane, 5, s0 - 1200.0)
	tr.running = true
	var isl: Array = b._toll_islands()
	var through := {}
	var in_closed: Array = []
	var changing: Array = []
	var touching: Array = []
	var fast: Array = []
	var onc_touch: Array = []
	var onc_seen := 0
	var ps: float = s0 - 1200.0
	for k in 60 * 120:
		ps += 30.0 / 120.0
		tr.player = {"s": ps, "d": st.toll_lane_d(-1.8, ps), "v": 30.0}
		await physics_frame
		if k % 4 != 0:
			continue
		for c in tr.cars:
			var ds: float = tr._ds(float(c.s), s0)
			if absf(ds) > float(t.half) + 2.0:
				continue
			through[int(c.id)] = true
			if st.toll_closed(int(c.lane)) or st.toll_closed(int(c.to)):
				in_closed.append(int(c.id))
			if int(c.to) != int(c.lane):
				changing.append(int(c.id))
			for i2 in isl:
				if absf(float(i2.d) - float(c.d)) < float(i2.w) * 0.5 + float(c.half_w):
					touching.append(int(c.id))
			if float(c.v) > float(t.speed) + 1.5:
				fast.append("%d at %.0f km/h" % [int(c.id), float(c.v) * 3.6])
		for o in tr.oncoming:
			var ds2: float = tr._ds(float(o.s), s0)
			if absf(ds2) > float(t.half) + 2.0:
				continue
			onc_seen += 1
			var od: float = st.toll_d(float(o.d), float(o.s))
			for i2 in isl:
				if absf(float(i2.d) - od) < float(i2.w) * 0.5 + 0.95:
					onc_touch.append("%.1f" % od)
			if st.toll_closed(int(o.lane)):
				onc_touch.append("closed lane %d" % int(o.lane))
	check(through.size() >= 8, "traffic: %d cars went through the plaza" % through.size())
	check(in_closed.is_empty(), "traffic: none in the closed lane at the booths (out of it beforehand)%s" % ("" if in_closed.is_empty() else ": %d seen" % in_closed.size()))
	check(changing.is_empty() and touching.is_empty(), "traffic: nobody changing lanes among the islands, nobody touching one%s" % (
		"" if changing.is_empty() and touching.is_empty() else ": %d changing, %d touching" % [changing.size(), touching.size()]))
	check(fast.is_empty(), "traffic: slowed to %.0f km/h through the booths%s" % [float(t.speed) * 3.6, "" if fast.is_empty() else ": " + ", ".join(fast.slice(0, 4))])
	check(onc_touch.is_empty(), "traffic: the other carriageway's cars through it in their fanned-out lanes, none in the closed one (%d seen there)%s" % [onc_seen,
		"" if onc_touch.is_empty() else ": " + ", ".join(onc_touch.slice(0, 4))])
	tr.queue_free()
	b.queue_free()
	await process_frame
