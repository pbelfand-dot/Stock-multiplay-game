extends SceneTree
## Scraping a barrier, then steering away (the owner: "the steering wheel also locks").
## The car against each kind: the loop's guardrail and a viaduct's parapet, a touge's
## guardrail, a mountain stage's armco or wall. It's steered gently into the barrier at
## speed, then hard away from it:
##   * while it scrapes, the barrier-side wheels stay on the road: none stands on the
##     barrier's face or hangs in a slot beside it
##   * steered away, it leaves the barrier (at least 5 m off it in 2 s: before, 2.6 on the loop)
## Each wheel sweeps a sphere wider than its tyre: beside a barrier its side touched the
## barrier's face first and the wheel stood on the wall with no load and no grip; and the
## loop had a 0.4 m slot between the road and its barriers. The car stuck to the barrier
## and steering away did nothing.
## Run: godot --headless --fixed-fps 120 --path . -s tests/barrier_check.gd

var StageGen
var StageBuilder
var LoopGen
var LoopBuilder
var RallyCar
var Catalog
var fails := 0


func check(ok: bool, what: String) -> void:
	print("[barrier] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _initialize() -> void:
	StageGen = load("res://scripts/stage/stage_gen.gd")
	StageBuilder = load("res://scripts/stage/stage_builder.gd")
	LoopGen = load("res://scripts/stage/loop_gen.gd")
	LoopBuilder = load("res://scripts/stage/loop_builder.gd")
	RallyCar = load("res://scripts/vehicle/rally_car.gd")
	Catalog = load("res://scripts/game/catalog.gd")
	await process_frame
	await _loop()
	await _stage("touge", {"kind": "touge", "dir": "down", "surface": "tarmac"}, 4, 55.0)
	await _stage("mountain", {"surface": "tarmac"}, 21, 70.0)
	print("[barrier] %s" % ("BARRIER OK" if fails == 0 else "BARRIER FAIL"))
	quit(1 if fails else 0)


## The loop: its road and barriers only (the rest isn't needed), a guardrail on the
## ground and a viaduct's parapet, on the right of a straight bit clear of the ramps.
func _loop() -> void:
	var st = LoopGen.new()
	st.generate(3)
	var b = LoopBuilder.new()
	root.add_child(b)
	b._prepare(st)
	b._road()
	b._barriers()
	b._finish()
	for want in ["ground", "viaduct"]:
		var s := -1.0
		var x := 300.0
		while x < st.length - 300.0:
			var ok: bool = true
			for k in 9:
				var at: float = x - 40.0 + k * 20.0
				ok = ok and st.support_at(at) == want and absf(st.curv_at(at)) < 1.0 / 800.0 and not b._ramp_gap(at, 1.0) \
					and b._extra_r[posmod(int(at / st.STEP), st._n)] <= 0.0 and not b._toll_island_at(at)
			if ok:
				s = x
				break
			x += 50.0
		if s < 0.0:
			check(false, "loop %s: found a straight stretch with its barrier on the right" % want)
			continue
		var e: Vector2 = b._edges(int(s / st.STEP))
		await _scrape("loop %s" % ("guardrail" if want == "ground" else "parapet"), st, s, e.y + 0.4, 1.0, 100.0)
	b.queue_free()
	await process_frame


## A built stage (the touge, a mountain stage): its first run of barrier at least 40 m
## long on a gentle enough bit of road (the car scrapes it at v km/h).
func _stage(what: String, gen: Dictionary, seed_value: int, v: float) -> void:
	var st = StageGen.new()
	st.opts = gen
	st.generate(seed_value, 2600.0)
	var b = StageBuilder.new()
	root.add_child(b)
	await b.build_async(st, func(_f, _w): pass)
	for k in 3:
		await physics_frame
	var space: PhysicsDirectSpaceState3D = b.get_world_3d().direct_space_state
	var found := false
	for side in [1.0, -1.0]:
		var run := 0.0
		var s: float = st.START_S + 20.0
		while s < st.length - 60.0 and not found:
			var d: float = side * (st.width_at(s) * 0.5 + 0.6)
			var p: Vector3 = st.world_at(s, d - side * 1.5) + Vector3.UP * 0.4
			var q := PhysicsRayQueryParameters3D.create(p, st.world_at(s, d + side * 0.5) + Vector3.UP * 0.4)
			var hit := space.intersect_ray(q)
			var gentle: bool = absf(st.curv[clampi(int(s / st.STEP), 0, st.curv.size() - 1)]) < 1.0 / 90.0
			run = run + 2.0 if not hit.is_empty() and str((hit.collider as Node).name) == "Barriers" and gentle else 0.0
			if run >= 40.0:
				found = true
				await _scrape("%s %s" % [what, "on the right" if side > 0.0 else "on the left"], st, s - 30.0, d, side, v)
			s += 2.0
		if found:
			break
	if not found:
		check(false, "%s: found a 40 m run of barrier on a gentle bit of road" % what)
	b.queue_free()
	await process_frame


## The car beside the barrier (its d: bd, on `side`), at v km/h, steered gently into it
## for 1.2 s, then hard away for 2 s.
func _scrape(what: String, st, s: float, bd: float, side: float, v: float) -> void:
	var car = RallyCar.new()
	car.setup = Catalog.setup("kestrel", {}, {}, {"tyre": "tarmac", "preset": "tarmac"})
	root.add_child(car)
	var half: float = car.config.body_size.x * 0.5
	car.place(st.world_at(s, bd - side * (half + 0.25)), st.heading_at(s))
	for k in 6:
		await physics_frame
	car.set_speed(v / 3.6)
	var hint := -1
	var bad := 0
	var ticks := 0
	var off := 0.0
	var gap0 := 0.0
	var t := 0.0
	while t < 3.2:
		var at: Dictionary = st.locate(car.global_position, hint)
		hint = at.i
		var gap: float = absf(bd - float(at.d))         # from the car's middle to the barrier
		var into := t < 1.2
		car.inp = {"steer": side * (0.25 if into else -1.0), "throttle": clampf((v / 3.6 - car.speed) * 0.5, 0.0, 1.0),
			"brake": 0.0, "handbrake": false}
		await physics_frame
		t += 1.0 / 120.0
		if into and t > 0.4:
			# the barrier-side wheels: on the ground, not on the barrier's face, not hanging
			for k in [1, 3] if side > 0.0 else [0, 2]:
				var w = car.wheels[k]
				ticks += 1
				if not w.grounded or w.normal.dot(car.global_transform.basis.y) < 0.7:
					bad += 1
		if absf(t - 1.2) < 0.005:
			gap0 = gap
		if t > 1.2:
			off = maxf(off, gap - gap0)
	check(gap0 < half + 0.6 and bad <= ticks / 20,
		"%s: scraping it at %.0f km/h the barrier-side wheels stay on the road (%d of %d wheel-ticks off it or on its face; the car's middle %.2f m from it)" % [
		what, v, bad, ticks, gap0])
	check(off >= 5.0, "%s: steered away, it leaves the barrier (%.1f m off it in 2 s; at least 5)" % [what, off])
	car.queue_free()
	await process_frame
