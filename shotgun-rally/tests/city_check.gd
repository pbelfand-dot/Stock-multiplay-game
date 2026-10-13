extends SceneTree
## Cut up's city (the LAKESHORE LOOP): its buildings true to their sources, its streets and what's
## on them where they should be.
## Run: godot --headless --path . -s tests/city_check.gd [-- --only=models|loop]
##   * every library building (EnvAssets "building", tools/buildings.py) is its source's shape: its
##     mesh's bounds the entry's size (to 1 %) and the source model's measured size (src_size, to
##     2 %: nothing cut off, nothing stretched), its UVs inside the image, one surface with its
##     facade image, its triangles as the entry says, every face wound the way its normal faces
##   * on the loop every building stands as built: the front rows and the far tier turned and
##     placed, never scaled (an orthonormal basis: a building can't be squashed or stretched)
##   * the streets: a grid both sides (cross streets and long ones), none on the road or a ramp,
##     no building on one (the front rows, the drawn towers and the fill, the far tier), the
##     blocks' gaps filled with drawn buildings (none on another building), the lamps,
##     the trees and the parked cars on them (none in a building, none on the road), the parked
##     cars the shown traffic's only (no no-AI car), signs on roofs and billboards by the road
## Prints one [city] line per check; exits 1 on any FAIL.

var fails := 0
const EnvAssets = preload("res://scripts/stage/env_assets.gd")
const CitySkyline = preload("res://scripts/stage/city_skyline.gd")
const CityStreets = preload("res://scripts/stage/city_streets.gd")


func check(ok: bool, what: String) -> void:
	print("[city] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _initialize() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	await process_frame
	if only in ["", "models"]:
		_models()
	if only in ["", "loop"]:
		await _loop()
	print("[city] %s" % ("CITY OK" if fails == 0 else "CITY FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func _models() -> void:
	var ids: Array = EnvAssets.ids("building")
	var bad_size: Array = []
	var bad_src: Array = []
	var bad_uv: Array = []
	var bad_mat: Array = []
	var no_src: Array = []
	for id in ids:
		var e: Dictionary = EnvAssets.info(id)
		var m: Mesh = EnvAssets.mesh(id)
		if m == null:
			bad_mat.append("%s (no mesh)" % id)
			continue
		var ab := m.get_aabb()
		var got := [ab.size.x, ab.size.y, ab.size.z]
		var sz: Array = e.get("size", [0, 0, 0])
		var src: Array = e.get("src_size", [])
		for k in 3:
			if absf(float(got[k]) - float(sz[k])) > maxf(float(sz[k]) * 0.01, 0.1):
				bad_size.append("%s %s against %s" % [id, _v(got), _v(sz)])
				break
		if src.is_empty():
			no_src.append(id)
		else:
			for k in 3:
				if absf(float(got[k]) / maxf(float(src[k]), 0.01) - 1.0) > 0.02:
					bad_src.append("%s %s against the source's %s" % [id, _v(got), _v(src)])
					break
		var arr := m.surface_get_arrays(0)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for t in arr[Mesh.ARRAY_TEX_UV]:
			lo = lo.min(t)
			hi = hi.max(t)
		if lo.x < -0.001 or lo.y < -0.001 or hi.x > 1.001 or hi.y > 1.001:
			bad_uv.append("%s %s..%s" % [id, str(lo), str(hi)])
		var mat := m.surface_get_material(0)
		var tex: Texture2D = (mat as BaseMaterial3D).albedo_texture if mat is BaseMaterial3D else null
		var tris: int = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if arr[Mesh.ARRAY_INDEX] != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		if m.get_surface_count() != 1 or tex == null or absi(tris - int(e.get("tris", tris))) > maxi(int(e.get("tris", 0)) / 100, 2):
			bad_mat.append("%s (%d surfaces, %s, %d triangles against %d)" % [id, m.get_surface_count(), "its image" if tex else "NO IMAGE", tris, int(e.get("tris", 0))])
	check(ids.size() >= 20 and bad_size.is_empty(), "the library's %d buildings: each mesh its entry's size (to 1 %%)%s" % [ids.size(),
		"" if bad_size.is_empty() else "; OFF " + ", ".join(bad_size.slice(0, 4))])
	check(not ids.is_empty() and no_src.is_empty() and bad_src.is_empty(), "each the shape of its source model (its size to 2 %%: nothing cut off or stretched)%s%s" % [
		"" if no_src.is_empty() else "; NO SOURCE SIZE " + ", ".join(no_src.slice(0, 6)), "" if bad_src.is_empty() else "; OFF " + ", ".join(bad_src.slice(0, 4))])
	check(not ids.is_empty() and bad_uv.is_empty(), "each one's UVs inside its image (0..1: the bake's own map)%s" % ("" if bad_uv.is_empty() else "; OUT " + ", ".join(bad_uv.slice(0, 4))))
	check(not ids.is_empty() and bad_mat.is_empty(), "each one surface, its facade image, its triangles as listed%s" % ("" if bad_mat.is_empty() else "; " + ", ".join(bad_mat.slice(0, 4))))
	# every face lit from the side it's drawn from (the game's facade shader culls back faces: a
	# normal against its winding is a face lit from behind; they were 0.4-15 % of a building)
	var box := ArrayMesh.new()
	box.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().get_mesh_arrays())
	var sgn := 1.0 if _against(box, 1.0) < 0.5 else -1.0
	var worst := 0.0
	var against: Array = []
	for id in ids:
		var m: Mesh = EnvAssets.mesh(id)
		if m == null:
			continue
		var share := _against(m, sgn)
		worst = maxf(worst, share)
		if share > 0.01:
			against.append("%s %.1f %%" % [id, share * 100.0])
	check(not ids.is_empty() and against.is_empty(), "each one's faces wound the way its normals face (the worst %.2f %% of a building's area)%s" % [worst * 100.0,
		"" if against.is_empty() else "; AGAINST " + ", ".join(against.slice(0, 6))])


## The share of a mesh's area whose triangles are wound against their normals (sgn: Godot's front
## face's sign of (b - a) x (c - a) . n).
func _against(m: Mesh, sgn: float) -> float:
	var back := 0.0
	var total := 0.0
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx = arr[Mesh.ARRAY_INDEX]
		var count: int = (idx as PackedInt32Array).size() if idx != null else v.size()
		var k := 0
		while k + 2 < count:
			var i0: int = idx[k] if idx != null else k
			var i1: int = idx[k + 1] if idx != null else k + 1
			var i2: int = idx[k + 2] if idx != null else k + 2
			var c := (v[i1] - v[i0]).cross(v[i2] - v[i0])
			total += c.length()
			if c.dot(n[i0] + n[i1] + n[i2]) * sgn < 0.0:
				back += c.length()
			k += 3
	return back / maxf(total, 1e-9)


func _v(a: Array) -> String:
	return "%.1f x %.1f x %.1f" % [float(a[0]), float(a[1]), float(a[2])]


func _loop() -> void:
	var st = load("res://scripts/stage/loop_gen.gd").new()
	st.generate(3)
	var b = load("res://scripts/stage/loop_builder.gd").new()
	root.add_child(b)
	b.build(st)
	await process_frame
	# placed, never scaled
	var feet: Array = []                            # [footprint, what]
	var skewed: Array = []
	for n in b.get_children():
		if n is MeshInstance3D and String(n.name).begins_with("Building_"):
			var xf: Transform3D = n.transform
			if not _rigid(xf.basis):
				skewed.append("%s (%s)" % [n.name, _scales(xf.basis)])
			var ab: AABB = (n as MeshInstance3D).mesh.get_aabb()
			feet.append([_foot(xf, ab.get_center(), ab.size.x, ab.size.z), "front row " + String(n.name)])
		elif n is MultiMeshInstance3D and String(n.name).begins_with("Towers"):
			var xfs: Array = n.get_meta("xfs", [])           # (a MultiMesh's transforms can't be read back headless)
			check(xfs.size() == n.multimesh.instance_count, "loop: %s keeps its towers' transforms (%d)" % [n.name, xfs.size()]) if xfs.size() != n.multimesh.instance_count else null
			for k in xfs.size():
				var xf: Transform3D = xfs[k]
				feet.append([_foot(Transform3D(xf.basis.orthonormalized(), xf.origin), Vector3.ZERO, xf.basis.x.length(), xf.basis.z.length()),
					"%s %d" % [n.name, k]])
	var far: Node = b.get_node_or_null(CitySkyline.NAME)
	var n_far := 0
	if far != null:
		for e in far.get_meta("buildings", []):
			var xf: Transform3D = e[1]
			n_far += 1
			if not _rigid(xf.basis):
				skewed.append("far %s (%s)" % [e[0], _scales(xf.basis)])
			var sz: Array = EnvAssets.info(str(e[0])).get("size", [0.0, 0.0, 0.0])
			feet.append([_foot(xf, Vector3.ZERO, float(sz[0]), float(sz[2])), "far " + str(e[0])])
	check(b.real_building_count > 50 and n_far > 150 and skewed.is_empty(),
		"loop: the front rows (%d of the library's) and the far tier (%d) placed and turned, never scaled%s" % [b.real_building_count, n_far,
		"" if skewed.is_empty() else "; SCALED " + ", ".join(skewed.slice(0, 4))])
	var cs: Node = b.get_node_or_null(CityStreets.NAME)
	check(cs != null, "loop: the city's streets built")
	if cs == null:
		return
	var streets: Array = cs.get_meta("streets", [])
	var runs: int = cs.get_meta("runs", 0)
	# none on the road: every street's corners, and the things on them, outside both carriageways
	# and their barriers (in road coordinates) and off the ramps
	var road_hits: Array = []
	for r in streets:
		for p in _corners(r):
			if _on_road(b, st, p, 1.0):
				road_hits.append("a street at %.0f, %.0f" % [p.x, p.y])
				break
	var lamps: Array = cs.get_meta("lamps", [])
	var trees: Array = cs.get_meta("trees", [])
	var cars: Array = cs.get_meta("cars", [])
	var boards: Array = cs.get_meta("boards", [])
	for e in [[lamps, "a lamp"], [trees, "a tree"]]:
		for p in e[0]:
			if _on_road(b, st, Vector2(p.x, p.z), 2.0):
				road_hits.append("%s at %.0f, %.0f" % [e[1], p.x, p.z])
	for c in cars + boards:
		for p in _corners(c):
			if _on_road(b, st, p, 1.0):
				road_hits.append("a parked car or billboard at %.0f, %.0f" % [p.x, p.y])
				break
	check(runs > 100 and streets.size() > 300 and road_hits.is_empty(),
		"loop: %d streets (%d pieces) both sides, none on the road or a ramp, nor anything on them%s" % [runs, streets.size(),
		"" if road_hits.is_empty() else "; ON THE ROAD " + ", ".join(road_hits.slice(0, 4))])
	# no building on a street; nothing on a street inside a building
	var cells := {}
	for k in feet.size():
		var key := Vector2i(floori(feet[k][0].c.x / 100.0), floori(feet[k][0].c.y / 100.0))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(k)
	var on_street: Array = []
	for r in streets:
		var key := Vector2i(floori(r.c.x / 100.0), floori(r.c.y / 100.0))
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				for k in cells.get(key + Vector2i(dx, dz), []):
					if CitySkyline.overlap(r, feet[k][0]):
						on_street.append("%s at %.0f, %.0f" % [feet[k][1], feet[k][0].c.x, feet[k][0].c.y])
	check(not feet.is_empty() and on_street.is_empty(), "loop: no building on a street (%d buildings: front rows, drawn towers, the fill, the far tier)%s" % [feet.size(),
		"" if on_street.is_empty() else "; ON A STREET " + ", ".join(on_street.slice(0, 4))])
	# the fill on no other building (the front rows, the drawn towers, the far tier, each other)
	var overlaps: Array = []
	var n_fill := 0
	for k in feet.size():
		if not String(feet[k][1]).begins_with("TowersFill"):
			continue
		n_fill += 1
		var key := Vector2i(floori(feet[k][0].c.x / 100.0), floori(feet[k][0].c.y / 100.0))
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				for j in cells.get(key + Vector2i(dx, dz), []):
					if j != k and CitySkyline.overlap(feet[k][0], feet[j][0]):
						overlaps.append("%s / %s" % [feet[k][1], feet[j][1]])
	check(n_fill > 500 and overlaps.is_empty(), "loop: the blocks' gaps filled (%d drawn buildings), none on another building%s" % [n_fill,
		"" if overlaps.is_empty() else "; ON " + ", ".join(overlaps.slice(0, 4))])
	var inside: Array = []
	var things: Array = []
	for p in lamps:
		things.append([{"c": Vector2(p.x, p.z), "ax": Vector2.RIGHT, "az": Vector2.UP, "hx": 0.1, "hz": 0.1}, "a lamp"])
	for p in trees:
		things.append([{"c": Vector2(p.x, p.z), "ax": Vector2.RIGHT, "az": Vector2.UP, "hx": 0.2, "hz": 0.2}, "a tree"])
	for c in cars:
		things.append([c, "a parked car"])
	for t in things:
		var key := Vector2i(floori(t[0].c.x / 100.0), floori(t[0].c.y / 100.0))
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				for k in cells.get(key + Vector2i(dx, dz), []):
					if CitySkyline.overlap(t[0], feet[k][0]):
						inside.append("%s in %s" % [t[1], feet[k][1]])
	check(lamps.size() > 500 and trees.size() > 1000 and cars.size() > 1000 and inside.is_empty(),
		"loop: on the streets %d lamps, %d trees, %d parked cars, none in a building%s" % [lamps.size(), trees.size(), cars.size(),
		"" if inside.is_empty() else "; " + ", ".join(inside.slice(0, 4))])
	var VehicleRegistry = load("res://scripts/game/vehicle_registry.gd")
	var pool: Array = CityStreets._car_pool()
	var hidden: Array = pool.filter(func(e): return VehicleRegistry.no_ai(str(e.id))).map(func(e): return str(e.id))
	check(not pool.is_empty() and hidden.is_empty(), "loop: the parked cars from the shown traffic only (%s)%s" % [", ".join(pool.map(func(e): return str(e.id))),
		"" if hidden.is_empty() else "; NO-AI " + ", ".join(hidden)])
	check(int(cs.get_meta("signs", 0)) > 50 and boards.size() > 10, "loop: %d signs on roofs, %d billboards by the expressway" % [int(cs.get_meta("signs", 0)), boards.size()])
	b.queue_free()
	await process_frame


## A basis that only turns (no scale, no shear).
func _rigid(bs: Basis) -> bool:
	for v in [bs.x, bs.y, bs.z]:
		if absf(v.length() - 1.0) > 0.002:
			return false
	return absf(bs.x.dot(bs.y)) < 0.002 and absf(bs.x.dot(bs.z)) < 0.002 and absf(bs.y.dot(bs.z)) < 0.002


func _scales(bs: Basis) -> String:
	return "%.3f %.3f %.3f" % [bs.x.length(), bs.y.length(), bs.z.length()]


func _foot(xf: Transform3D, mid: Vector3, sx: float, sz: float) -> Dictionary:
	var c: Vector3 = xf * mid
	return {"c": Vector2(c.x, c.z), "ax": Vector2(xf.basis.x.x, xf.basis.x.z).normalized(),
		"az": Vector2(xf.basis.z.x, xf.basis.z.z).normalized(), "hx": sx * 0.5, "hz": sz * 0.5}


func _corners(r: Dictionary) -> Array:
	var out: Array = []
	for u in [-1.0, 1.0]:
		for v in [-1.0, 1.0]:
			out.append(r.c + r.ax * r.hx * u + r.az * r.hz * v)
	return out


## Is (x, z) on the road: between the carriageways' outer barriers (and margin m past them), or
## within a ramp's road?
func _on_road(b, st, p: Vector2, m: float) -> bool:
	if b._ramp_dist(p.x, p.y) < st.RAMP_W + m:
		return true
	var hint: int = CityStreets._hint(b, p)
	if hint < 0:
		return false
	var loc: Dictionary = st.locate(Vector3(p.x, 0.0, p.y), hint)
	var d: float = loc.d
	var q: Vector3 = st.world_at(float(loc.s), d)
	if Vector2(q.x - p.x, q.z - p.y).length() > 3.0:
		return false                                # (off the end of the road's frame: not beside it)
	return d < st.OUTER_R + m and d > st.OUTER_L - m
