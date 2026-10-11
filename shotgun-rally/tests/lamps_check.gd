extends SceneTree
## A touge's street lamps and its power line (scripts/stage/stage_builder.gd: _plan_touge_lamps,
## _touge_lamps, _poles; scripts/stage/street_lamps.gd), over many passes, uphill and down.
## Run: godot --headless --fixed-fps 120 --path . -s tests/lamps_check.gd [-- --seeds=1-12]
##   * off the road: every lamp post, and every power pole's footing (each vertex of its model
##     near the ground: an H-frame's legs once stood in the lane), past the road's edge and a
##     margin: from locate() where it stands (another leg of the road nearby counts) and against
##     every stretch of the road within reach
##   * behind a guardrail: a barrier between the road and every post, the post clear of it;
##     the post and arm through no tree, rock, rock face, pole or sign, and clear of the
##     touge's own roadside things (mirrors, chevrons, kilometre posts, the arches)
##   * on the ground: each post's foot just in the ground under it (never over it, at most a
##     few cm in where it slopes), not up a cut bank
##   * the arm: square to the road and reaching over it, the head over the road 6.5-7.5 m up,
##     the glass along the arm (not along the world's x) and hung right under it
##   * the pool: straight under the head, on the road (never under it, never far over it), hardly
##     any of its light out over the drop
##   * how many: one before every tight bend on its outside, no stretch longer than ~130 m
##     without one, no two whose pools overlap (the touge's pools multiply)
##   * the real lights, a car down the whole road: no lamp's light ever jumps (one hands over to
##     the next, however many lamps stand round a hairpin for StreetLamps' four lights)
##   * solid: a pole on every post; by day the same posts, unlit (no StreetLamps)
## Prints one [lamps] line per check; exits 1 on any FAIL.

const SEEDS := [2, 5, 9, 12]
const POST_CLEAR := 1.2         # m past the road's edge, a lamp post at the least
const POLE_CLEAR := 1.5         # m past it, any part of a power pole's footing

var StageGen
var StageBuilder
var StreetLamps
var Modes
var Graphics
var fails := 0
var _tris := {}                 # Mesh -> TriangleMesh
var _day_done := false


func check(ok: bool, what: String) -> void:
	print("[lamps] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _initialize() -> void:
	StageGen = load("res://scripts/stage/stage_gen.gd")
	StageBuilder = load("res://scripts/stage/stage_builder.gd")
	StreetLamps = load("res://scripts/stage/street_lamps.gd")
	Modes = load("res://scripts/game/modes.gd")
	Graphics = load("res://scripts/render/graphics.gd")
	var seeds: Array = SEEDS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			var v: String = a.trim_prefix("--seeds=")
			seeds = []
			if v.contains("-"):
				for k in range(int(v.get_slice("-", 0)), int(v.get_slice("-", 1)) + 1):
					seeds.append(k)
			else:
				for x in v.split(","):
					seeds.append(int(x))
	Graphics.set_level("medium")                     # (the library's trees, rocks and poles)
	await process_frame
	var tot := {}
	for sd in seeds:
		for dir in ["up", "down"]:
			var r: Dictionary = await _pass(int(sd), dir)
			for k in r:
				if k.begins_with("min_"):
					tot[k] = minf(float(tot.get(k, INF)), float(r[k]))
				elif k.begins_with("max_"):
					tot[k] = maxf(float(tot.get(k, -INF)), float(r[k]))
				else:
					tot[k] = int(tot.get(k, 0)) + int(r[k])
	var where := "%d passes (seeds %s, up and down)" % [seeds.size() * 2, str(seeds)]
	check(tot.n_post_road == 0 and tot.n_pole_road == 0,
		"off the road, %s: %d lamp posts, the nearest %.2f m past the road's edge (any stretch of it, %d nearer than %.1f m); %d power poles, the nearest footing %.2f m past it (%d nearer than %.1f m)" % [
		where, tot.lamps, tot.min_post_edge, tot.n_post_road, POST_CLEAR, tot.poles, tot.min_pole_edge, tot.n_pole_road, POLE_CLEAR])
	check(tot.n_unrailed == 0 and tot.n_clash == 0 and tot.n_props == 0,
		"behind a guardrail: %d of %d posts with none between them and the road, %d through the barrier, a tree, rock, pole or sign%s, %d by a mirror, chevron, km post or arch" % [
		tot.n_unrailed, tot.lamps, tot.n_clash, (" (" + str(tot.get("first_clash", "")) + ")") if tot.n_clash > 0 else "", tot.n_props])
	check(tot.max_float <= 0.005 and tot.max_sunk <= 0.35 and tot.max_rise <= 0.6,
		"on the ground: each post's foot in the ground under it (at most %.3f m over its lowest, %.2f m under its highest), the ground there at most %.2f m over the road's edge" % [
		tot.max_float, tot.max_sunk, tot.max_rise])
	check(tot.n_arm == 0 and tot.min_head_h >= 6.5 and tot.max_head_h <= 7.5 and tot.max_skew < 2.0 and tot.max_hang <= 0.02,
		"the arm: square to the road and over it (%d not), the head %.2f-%.2f m over the road, the glass along the arm (%.1f deg off at most) and hung under it (%.3f m below it at most)" % [
		tot.n_arm, tot.min_head_h, tot.max_head_h, tot.max_skew, tot.max_hang])
	check(tot.max_pool_off <= 0.2 and tot.max_pool_under <= 0.005 and tot.max_pool_over <= 0.3 and tot.max_pool_air <= 0.03,
		"the pool: %.2f m from under the head at most, never under the road (%.3f m), at most %.2f m over it, %.1f %% of its light out over the drop at most" % [
		tot.max_pool_off, tot.max_pool_under, tot.max_pool_over, tot.max_pool_air * 100.0])
	check(tot.n_unlit_bends == 0 and tot.max_gap <= 130.0 and tot.n_overlap == 0,
		"how many: before each of %d tight bends on its outside (%d without), never more than %.0f m apart, %d passes whose pools overlap" % [
		tot.bends, tot.n_unlit_bends, tot.max_gap, tot.n_overlap])
	check(tot.max_jump <= 0.12,
		"the real lights, the whole road at 20 m/s: up to %d lamps within %.0f m for %d lights, a lamp's light changing at most %.0f %% of it in a metre (a pop: all of it)" % [
		tot.max_near, StreetLamps.FADE[1], StreetLamps.REAL, tot.max_jump * 100.0])
	check(tot.n_soft == 0 and tot.n_day == 0, "solid: a pole on every post (%d without); by day the same posts, unlit (%d passes otherwise)" % [tot.n_soft, tot.n_day])
	print("[lamps] %s" % ("LAMPS OK" if fails == 0 else "LAMPS FAIL"))
	quit(1 if fails else 0)


## m past the road's edge at p: from locate() (the nearest stretch) and against every stretch
## within 40 m (a hairpin's other leg); the smaller.
func _past_edge(st, grid: Dictionary, p: Vector3, hint := -1) -> float:
	var lc: Dictionary = st.locate(p, hint)
	var best: float = absf(float(lc.d)) - st.width_at(float(lc.s)) * 0.5
	var c := Vector2i(floori(p.x / 20.0), floori(p.z / 20.0))
	var q := Vector2(p.x, p.z)
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for i in grid.get(c + Vector2i(dx, dz), []):
				if i >= st.pts.size() - 1:
					continue
				var a := Vector2(st.pts[i].x, st.pts[i].z)
				var ab := Vector2(st.pts[i + 1].x, st.pts[i + 1].z) - a
				var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
				best = minf(best, (q - (a + ab * t)).length() - lerpf(st.widths[i], st.widths[i + 1], t) * 0.5)
	return best


## The ground (the ground's and the mountainside's bodies, the road's) under p: its height, or -INF.
func _ground_y(space: PhysicsDirectSpaceState3D, p: Vector3, ground: Array) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 30.0, p - Vector3.UP * 60.0)
	var ex: Array = []
	for k in 12:
		q.exclude = ex
		var h: Dictionary = space.intersect_ray(q)
		if h.is_empty():
			return -INF
		if h.rid in ground:
			return (h.position as Vector3).y
		ex.append(h.rid)
	return -INF


func _road_y(st, s: float, d: float) -> float:
	return st.point_at(s).y + StageBuilder._road_height(d, st.width_at(s) * 0.5)


func _pass(seed_value: int, dir: String) -> Dictionary:
	var st = StageGen.new()
	st.opts = {"kind": "touge", "dir": dir}
	st.generate(seed_value, Modes.TOUGE_LENGTH)
	var b = StageBuilder.new()
	b.mood = "night"
	root.add_child(b)
	b.build(st)
	for k in 3:
		await physics_frame
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var ground: Array = []
	for n in b.get_children():
		if n is StaticBody3D and (String(n.name) in ["GroundBody", "MountainsideBody"] or String(n.name).begins_with("Road")):
			ground.append((n as StaticBody3D).get_rid())
	var grid := {}
	for i in st.pts.size():
		var key := Vector2i(floori(st.pts[i].x / 20.0), floori(st.pts[i].z / 20.0))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)
	var placed: Array = []                           # the library's things: [name, Transform3D, Mesh]
	for n in b.get_children():
		if n is MultiMeshInstance3D and n.has_meta("xforms"):
			for xf in n.get_meta("xforms"):
				placed.append([String(n.name), xf, (n as MultiMeshInstance3D).multimesh.mesh])
	var props: Array = b._touge_prop_spots()
	var posts: Node = b.get_node_or_null("LampPosts")
	var r := {"lamps": b.lamps.size(), "poles": 0, "bends": 0, "min_post_edge": INF, "min_pole_edge": INF, "n_post_road": 0,
		"n_pole_road": 0, "n_unrailed": 0, "n_clash": 0, "n_props": 0, "max_float": -INF, "max_sunk": -INF, "max_rise": -INF,
		"n_arm": 0, "min_head_h": INF, "max_head_h": -INF, "max_skew": 0.0, "max_hang": -INF, "max_pool_off": 0.0,
		"max_pool_under": 0.0, "max_pool_over": 0.0, "max_pool_air": 0.0, "n_unlit_bends": 0, "max_gap": 0.0, "n_overlap": 0,
		"max_near": 0, "max_jump": 0.0, "n_soft": 0, "n_day": 0}
	for l in b.lamps:
		var ls: float = l.s
		var sd: float = l.side
		var base: Vector3 = l.base
		var top: float = l.top
		var head: Vector3 = l.head
		var arm: Vector3 = l.arm
		var half: float = st.width_at(ls) * 0.5
		var f: Vector3 = st.forward_at(ls)
		var rv: Vector3 = st.right_at(ls)
		# off the road
		var edge := _past_edge(st, grid, base)
		r.min_post_edge = minf(r.min_post_edge, edge)
		if edge < POST_CLEAR:
			r.n_post_road += 1
			print("[lamps] info  seed %d %s: the post at s %.0f is %.2f m past the road's edge" % [seed_value, dir, ls, edge])
		# a guardrail between it and the road
		var rq := PhysicsRayQueryParameters3D.create(st.world_at(ls, sd * (half - 0.3)) + Vector3.UP * 0.5,
			Vector3(base.x, st.point_at(ls).y + 0.5, base.z))
		var rh: Dictionary = space.intersect_ray(rq)
		if rh.is_empty() or String(rh.collider.name) != "Barriers":
			r.n_unrailed += 1
		# nothing solid in the post (the barrier, trunks, rocks, poles), the library's meshes not through it
		var qs := PhysicsShapeQueryParameters3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(0.3, top - base.y - 0.4, 0.3)
		qs.shape = bx
		qs.transform = Transform3D(Basis(), Vector3(base.x, (base.y + top) * 0.5 + 0.2, base.z))
		for h in space.intersect_shape(qs, 16):
			if not h.rid in ground and String(h.collider.name) != "LampPosts":
				r.n_clash += 1
				r["first_clash"] = "%s at s %.0f" % [h.collider.name, ls]
		var segs: Array = []
		for c in [(f + rv) * 0.075, (f - rv) * 0.075, (rv - f) * 0.075, -(f + rv) * 0.075]:
			segs.append([base + c, Vector3(base.x, top, base.z) + c])
		segs.append([Vector3(base.x, top - 0.15, base.z), Vector3(base.x, top - 0.15, base.z) + arm * StageBuilder.LAMP_ARM])
		for e in placed:
			var xf: Transform3D = e[1]
			if Vector2(xf.origin.x - base.x, xf.origin.z - base.z).length() > 16.0:
				continue
			var tm: TriangleMesh = _tri(e[2])
			var inv := xf.affine_inverse()
			for sg in segs:
				if tm != null and not tm.intersect_segment(inv * (sg[0] as Vector3), inv * (sg[1] as Vector3)).is_empty():
					r.n_clash += 1
					r["first_clash"] = "%s at s %.0f" % [e[0], ls]
					break
		for q in props:
			if Vector2(base.x - q.x, base.z - q.z).length() < 1.5:
				r.n_props += 1
		# on the ground
		var lo := INF
		var hi := -INF
		for c in [Vector3.ZERO, (f + rv) * 0.075, (f - rv) * 0.075, (rv - f) * 0.075, -(f + rv) * 0.075]:
			var gy := _ground_y(space, base + c, ground)
			lo = minf(lo, gy)
			hi = maxf(hi, gy)
		r.max_float = maxf(r.max_float, base.y - lo)
		r.max_sunk = maxf(r.max_sunk, hi - base.y)
		r.max_rise = maxf(r.max_rise, hi - st.point_at(ls).y)
		# the arm and the head
		var hl: Dictionary = st.locate(head)
		var bl: Dictionary = st.locate(base)
		if absf(float(hl.d)) > st.width_at(float(hl.s)) * 0.5 - 0.05 or absf(float(hl.d)) >= absf(float(bl.d)) or absf(arm.dot(f)) > 0.05:
			r.n_arm += 1
		var hh: float = head.y - _road_y(st, float(hl.s), float(hl.d))
		r.min_head_h = minf(r.min_head_h, hh)
		r.max_head_h = maxf(r.max_head_h, hh)
		var hx: Transform3D = StreetLamps.head_xform(l)
		r.max_skew = maxf(r.max_skew, rad_to_deg(acos(clampf(absf(hx.basis.x.normalized().dot(arm.normalized())), 0.0, 1.0))))
		r.max_hang = maxf(r.max_hang, (top - 0.15 - 0.045) - (hx.origin.y + 0.035))    # (the arm's underside, the glass's top)
		# the pool
		var pool := _pool(st, space, ground, l)
		for k in pool:
			r[k] = maxf(float(r[k]), float(pool[k]))
		# solid
		var solid := false
		if posts:
			for cs in posts.get_children():
				var at: Vector3 = (cs as CollisionShape3D).global_position
				if Vector2(at.x - base.x, at.z - base.z).length() < 0.1 and (cs as CollisionShape3D).shape is CylinderShape3D:
					solid = true
		if not solid:
			r.n_soft += 1
	# the power poles' footings
	for e in placed:
		if e[0] != "PowerPoles":
			continue
		r.poles += 1
		var xf: Transform3D = e[1]
		var mesh: Mesh = e[2]
		var hint: int = st.locate(xf.origin).i
		var worst := INF
		for v in _low(mesh):
			worst = minf(worst, _past_edge(st, grid, xf * v, hint))
		r.min_pole_edge = minf(r.min_pole_edge, worst)
		if worst < POLE_CLEAR:
			r.n_pole_road += 1
			print("[lamps] info  seed %d %s: a power pole at %s, its footing %.2f m past the road's edge" % [seed_value, dir, xf.origin, worst])
	# how many: the tight bends, the gaps, overlaps, how many near the car
	for c in st.corners:
		if c.r_min <= 45.0 and c.s0 > st.START_S + 20.0 and c.s0 < st.finish_s - 10.0:
			r.bends += 1
			var from: float = maxf(c.s0 - 16.0, st.START_S + 12.0) - 0.5
			if not b.lamps.any(func(l): return float(l.s) >= from and float(l.s) <= c.s0 - 2.5 and float(l.side) == -float(c.dir)):
				r.n_unlit_bends += 1
				print("[lamps] info  seed %d %s: the bend at s %.0f has no lamp before it" % [seed_value, dir, c.s0])
	for i in range(1, b.lamps.size()):
		r.max_gap = maxf(r.max_gap, float(b.lamps[i].s) - float(b.lamps[i - 1].s))
	var sl = b.street_lamps
	if sl == null or sl.overlapping:
		r.n_overlap += 1
	# the real lights down the whole road at 20 m/s (a metre a step): how much any lamp's light
	# changes from one step to the next (a pop: all of it at once)
	var car := Node3D.new()
	root.add_child(car)
	if sl:
		sl.target = car
		var last := {}
		var first := true
		var s: float = st.START_S
		while s < st.finish_s:
			var p: Vector3 = st.world_at(s, -1.6) + Vector3.UP * 0.8
			car.global_position = p
			sl._process(0.05)
			var now := {}
			for o in sl._lights:
				if (o as OmniLight3D).visible:
					now[int(o.get_meta("lamp", -1))] = float(now.get(int(o.get_meta("lamp", -1)), 0.0)) + (o as OmniLight3D).light_energy
			if not first:                            # (the first step: the lights come on where the car starts)
				for i in now.keys() + last.keys():
					r.max_jump = maxf(r.max_jump, absf(float(now.get(i, 0.0)) - float(last.get(i, 0.0))) / StreetLamps.REAL_ENERGY)
			first = false
			last = now
			r.max_near = maxi(r.max_near, b.lamps.filter(func(l): return p.distance_to(l.head) < StreetLamps.FADE[1]).size())
			s += 1.0
	car.queue_free()
	var night_bases: Array = b.lamps.map(func(l): return l.base)
	b.queue_free()
	await process_frame
	# by day: the same posts, unlit (the first pass)
	if not _day_done:
		_day_done = true
		var d = StageBuilder.new()
		d.mood = "day"
		root.add_child(d)
		d.build(st)
		if d.street_lamps != null or d.lamps.map(func(l): return l.base) != night_bases:
			r.n_day += 1
		d.queue_free()
		await process_frame
	print("[lamps] info  seed %d %s: %d lamps, %d poles; nearest post %.2f m past the edge, footing %.2f m; pool over the drop %.1f %%" % [
		seed_value, dir, r.lamps, r.poles, r.min_post_edge, r.min_pole_edge, r.max_pool_air * 100.0])
	return r


## The pool against the road under it: how far its middle is from under the head, how far under
## the road it goes and over it (where its light shows: f > 0.1, as the shader cuts it), and the
## share of its light over nothing (the ground 0.5 m+ under it, past the road).
func _pool(st, space: PhysicsDirectSpaceState3D, ground: Array, l: Dictionary) -> Dictionary:
	var xf: Transform3D = StreetLamps.pool_xform(l)
	var clip: Color = StreetLamps.pool_clip(l)
	var head: Vector3 = l.head
	var out := {"max_pool_off": Vector2(xf.origin.x - head.x, xf.origin.z - head.z).length(), "max_pool_under": 0.0,
		"max_pool_over": 0.0, "max_pool_air": 0.0}
	var lit := 0.0
	var air := 0.0
	for iu in range(-10, 11):
		for iv in range(-10, 11):
			var u := iu / 20.0
			var v := iv / 20.0
			var rr := Vector2(u, v).length() * 2.0
			if rr > 1.0:
				continue
			var fall := (1.0 - smoothstep(0.45, 1.0, rr)) * (1.0 - 0.5 * minf(rr, 1.0))
			fall *= (1.0 - smoothstep(clip.r - 0.08, clip.r, u * 2.0)) * (1.0 - smoothstep(clip.g - 0.08, clip.g, -u * 2.0))
			if fall < 0.1:
				continue
			var p: Vector3 = xf * Vector3(u, 0.0, v)
			var lc: Dictionary = st.locate(p, int(float(l.s) / st.STEP))
			lit += fall
			if absf(float(lc.d)) <= st.width_at(float(lc.s)) * 0.5:
				var ry := _road_y(st, float(lc.s), float(lc.d))
				out.max_pool_under = maxf(out.max_pool_under, ry - p.y)
				out.max_pool_over = maxf(out.max_pool_over, p.y - ry)
			elif p.y - _ground_y(space, p, ground) > 0.5:
				air += fall
	out.max_pool_air = air / maxf(lit, 1e-6)
	return out


func _tri(mesh: Mesh) -> TriangleMesh:
	if mesh == null:
		return null
	if not _tris.has(mesh):
		_tris[mesh] = mesh.generate_triangle_mesh()
	return _tris[mesh]


## A model's vertices in the lowest tenth of it (a power pole's: its foot, the first metre), each
## once (in its own units: the scale is in its transform).
func _low(mesh: Mesh) -> Array:
	if mesh.has_meta("low"):
		return mesh.get_meta("low")
	var aabb := mesh.get_aabb()
	var seen := {}
	for si in mesh.get_surface_count():
		for v in (mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if v.y < aabb.position.y + aabb.size.y * 0.1:
				seen[v.snapped(Vector3.ONE * 0.001)] = true
	var low: Array = seen.keys()
	mesh.set_meta("low", low)
	return low
