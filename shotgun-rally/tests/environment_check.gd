extends SceneTree
## The environment library and the biomes (scripts/stage/env_assets.gd, biomes.gd, the stage
## builder's trees, boulders, rock cuts and power poles).
## Run: godot --headless --fixed-fps 120 --path . -s tests/environment_check.gd [-- --only=assets|biomes|stages]
##   * every asset in data/environment_assets.json loads (each tree its three levels: LOD0, LOD1,
##     the far card), every biome's species is in the library
##   * each model as drawn: its entry's size, its one-sided faces wound the way their normals face,
##     nothing glowing or mirror-smooth, a tree's levels the same height and its far card upright
##   * a stage in each kind of land builds with the library's trees (MEDIUM), boulders where the
##     biome has them, rock cuts and a power line on a touge, the forest floor's ferns, grass,
##     stumps and logs where the biome has undergrowth
##   * nothing stands on the road: every tree, boulder, rock face, pole and fern is clear of every part
##     of the road (switchbacks too), and a car-sized box down both lanes touches nothing
##   * everything stands on the ground as drawn: nothing floats over it, no tree, pole or sign sunk
##   * the solid things (trunks, big boulders, poles) are the same at LOW and MEDIUM (every
##     machine in an online race agrees on them, whatever its graphics)
## Prints one [env] line per check; exits 1 on any FAIL.

var StageGen
var StageBuilder
var EnvAssets
var Biomes
var Graphics
var fails := 0


func check(ok: bool, what: String) -> void:
	print("[env] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _initialize() -> void:
	StageGen = load("res://scripts/stage/stage_gen.gd")
	StageBuilder = load("res://scripts/stage/stage_builder.gd")
	EnvAssets = load("res://scripts/stage/env_assets.gd")
	Biomes = load("res://scripts/stage/biomes.gd")
	Graphics = load("res://scripts/render/graphics.gd")
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	await process_frame
	if only in ["", "assets"]:
		_assets()
		_models()
	if only in ["", "biomes"]:
		_biomes()
	if only in ["", "stages"]:
		await _stages()
	print("[env] %s" % ("ENVIRONMENT OK" if fails == 0 else "ENVIRONMENT FAIL"))
	quit(1 if fails else 0)


func _assets() -> void:
	var trees: Array = EnvAssets.ids("tree")
	var missing: Array = []
	var tris := {}
	for id in trees:
		for lod in ["LOD0", "LOD1", "BB"]:
			var m: Mesh = EnvAssets.mesh(id, lod)
			if m == null:
				missing.append("%s %s" % [id, lod])
			elif lod != "BB":
				var n := 0
				for si in m.get_surface_count():
					n += m.surface_get_array_index_len(si) / 3 if m.surface_get_array_index_len(si) > 0 else m.surface_get_array_len(si) / 3
				tris[id + lod] = n
	check(trees.size() >= 15 and missing.is_empty(), "trees: %d species, each with LOD0, LOD1 and a far card%s" % [
		trees.size(), (" (missing: %s)" % ", ".join(missing.slice(0, 6))) if not missing.is_empty() else ""])
	var worst0 := 0
	var worst1 := 0
	for id in trees:
		worst0 = maxi(worst0, int(tris.get(id + "LOD0", 0)))
		worst1 = maxi(worst1, int(tris.get(id + "LOD1", 0)))
	check(worst0 > 0 and worst0 <= 30000 and worst1 <= 6000, "trees within budget: LOD0 at most %d triangles, LOD1 at most %d" % [worst0, worst1])
	var others: Array = EnvAssets.ids("rock") + EnvAssets.ids("cliff") + EnvAssets.ids("prop") + EnvAssets.ids("ground")
	var bad: Array = []
	for id in others:
		if EnvAssets.mesh(id) == null:
			bad.append(id)
	check(others.size() >= 25 and EnvAssets.ids("ground").size() >= 20 and bad.is_empty(), "rocks, rock faces, props and the forest floor (%d ferns, grass, branches, roots, stumps, logs): %d load%s" % [
		EnvAssets.ids("ground").size(), others.size(), (" (missing: %s)" % ", ".join(bad)) if not bad.is_empty() else ""])


## The library's models as the game draws them (tools/world_audit.gd prints the same for every
## model; the buildings: tests/city_check.gd): each its entry's size (squashed or stretched on
## import), its one-sided faces wound the way their normals face (else drawn from inside or not
## at all), no surface glowing or mirror-smooth that shouldn't, a tree's levels the same height
## (no pop where they swap) and its far card upright and two-faced.
func _models() -> void:
	var box := ArrayMesh.new()
	box.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().get_mesh_arrays())
	var sgn := 1.0 if _against(box, 1.0) < 0.5 else -1.0
	var f := FileAccess.open("res://data/environment_assets.json", FileAccess.READ)
	var all: Dictionary = JSON.parse_string(f.get_as_text()).assets
	var sized: Array = []
	var wound: Array = []
	var shiny: Array = []
	var pops: Array = []
	var n := 0
	for id in all:
		var e: Dictionary = all[id]
		var kind := str(e.get("kind", ""))
		if kind in ["building", "skyline"]:
			continue
		var lods: Array = ["LOD0", "LOD1", "BB"] if kind == "tree" else [""]
		var h := {}
		for lod in lods:
			var m: Mesh = EnvAssets.mesh(id, lod)
			if m == null:
				continue
			n += 1
			var ab := m.get_aabb()
			h[lod] = ab.size.y
			var sz = e.get("size", null)
			if sz is Array:
				var got := [ab.size.x, ab.size.y, ab.size.z]
				for k in 3:
					if absf(float(got[k]) - float(sz[k])) > maxf(float(sz[k]) * 0.03, 0.06):
						sized.append("%s %.2f x %.2f x %.2f against %s" % [id, ab.size.x, ab.size.y, ab.size.z, str(sz)])
						break
			var share := _against(m, sgn)
			if share > 0.02:
				wound.append("%s%s %.0f %%" % [id, "/" + lod if lod != "" else "", share * 100.0])
			for si in m.get_surface_count():
				var mat := m.surface_get_material(si)
				if mat is BaseMaterial3D:
					var bm := mat as BaseMaterial3D
					if bm.emission_enabled and bm.emission.get_luminance() * bm.emission_energy_multiplier > 0.01:
						shiny.append("%s glows" % id)
					if bm.roughness < 0.05 and bm.roughness_texture == null and bm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
						shiny.append("%s mirror-smooth (%.2f)" % [id, bm.roughness])
			if lod == "BB" and ab.size.y < maxf(ab.size.x, ab.size.z) * 0.5:
				pops.append("%s far card lying down" % id)
		if kind == "tree" and h.has("LOD0"):
			for lod in ["LOD1", "BB"]:
				if h.has(lod) and absf(float(h[lod]) / maxf(float(h.LOD0), 0.01) - 1.0) > 0.08:
					pops.append("%s %s %.1f m against LOD0's %.1f" % [id, lod, float(h[lod]), float(h.LOD0)])
	check(n > 100 and sized.is_empty(), "the library's models (%d, at each level): each its entry's size%s" % [n, "" if sized.is_empty() else "; OFF " + ", ".join(sized.slice(0, 4))])
	check(n > 100 and wound.is_empty(), "each one's one-sided faces wound the way their normals face%s" % ("" if wound.is_empty() else "; AGAINST " + ", ".join(wound.slice(0, 6))))
	check(n > 100 and shiny.is_empty(), "none glows or is mirror-smooth%s" % ("" if shiny.is_empty() else ": " + ", ".join(shiny.slice(0, 6))))
	check(n > 100 and pops.is_empty(), "each tree's levels the same height (no pop where they swap), its far card upright%s" % ("" if pops.is_empty() else "; " + ", ".join(pops.slice(0, 6))))


## The share of a mesh's one-sided area (a material that culls its back faces) wound against its
## normals (sgn: the sign of (b - a) x (c - a) . n on Godot's front faces).
func _against(m: Mesh, sgn: float) -> float:
	var back := 0.0
	var total := 0.0
	for si in m.get_surface_count():
		var mat := m.surface_get_material(si)
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).cull_mode != BaseMaterial3D.CULL_BACK:
			continue
		var arr := m.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nn = arr[Mesh.ARRAY_NORMAL]
		if nn == null or (nn as PackedVector3Array).size() != v.size():
			continue
		var idx = arr[Mesh.ARRAY_INDEX]
		var count: int = (idx as PackedInt32Array).size() if idx != null else v.size()
		var k := 0
		while k + 2 < count:
			var i0: int = idx[k] if idx != null else k
			var i1: int = idx[k + 1] if idx != null else k + 1
			var i2: int = idx[k + 2] if idx != null else k + 2
			var c := (v[i1] - v[i0]).cross(v[i2] - v[i0])
			total += c.length()
			if c.dot(nn[i0] + nn[i1] + nn[i2]) * sgn < 0.0:
				back += c.length()
			k += 3
	return back / maxf(total, 1e-9)


func _biomes() -> void:
	var ids: Array = Biomes.ids()
	var unknown: Array = []
	var f := FileAccess.open("res://data/biomes.json", FileAccess.READ)
	var all: Dictionary = JSON.parse_string(f.get_as_text()).biomes
	for b in ids:
		for key in ["trees", "broad"]:
			for e in all[b].get(key, []):
				if EnvAssets.info(str(e[0])).is_empty():
					unknown.append("%s: %s" % [b, e[0]])
		for r in all[b].get("rocks", {}).get("ids", []) + all[b].get("undergrowth", {}).get("edge", []) + all[b].get("undergrowth", {}).get("floor", []):
			if EnvAssets.info(str(r)).is_empty():
				unknown.append("%s: %s" % [b, r])
	check(ids.size() >= 8 and unknown.is_empty(), "biomes: %d (%s), every species and rock in the library%s" % [
		ids.size(), ", ".join(ids), (" (unknown: %s)" % ", ".join(unknown.slice(0, 6))) if not unknown.is_empty() else ""])
	# a stage picks the right land
	var cases := [[{"kind": "touge", "dir": "down"}, "japan_cedar"], [{"surface": "tarmac", "ice": true}, "winter_mountain"],
		[{"surface": "tarmac"}, "alpine_rock"], [{"surface": "mixed"}, "temperate_broadleaf"], [{"puddles": 2.5}, "wet_forest"],
		[{}, "conifer_rally"], [{"biome": "temperate_broadleaf", "season": "autumn"}, "temperate_broadleaf"]]
	var wrong: Array = []
	for c in cases:
		var st = StageGen.new()
		st.opts = c[0]
		st.kind = str(c[0].get("kind", "rally"))
		var b: Dictionary = Biomes.for_stage(st)
		if b.id != c[1]:
			wrong.append("%s -> %s" % [c[0], b.id])
	check(wrong.is_empty(), "each stage in its land (touge: cedar mountain, ice: winter, tarmac: alpine, mixed: broadleaf, puddles: wet forest, gravel: conifer forest, a rally's own pick)%s" % (
		(": " + ", ".join(wrong)) if not wrong.is_empty() else ""))
	var st2 = StageGen.new()
	st2.opts = {"biome": "temperate_broadleaf", "season": "autumn"}
	var au: Dictionary = Biomes.for_stage(st2)
	check(au.season == "autumn" and Biomes.colour(au.get("broad_tint")).r > 1.2, "a season changes the land's colours (autumn: the broadleaf turns, tint %s)" % [au.get("broad_tint")])


## Builds a stage at a quality: [builder, stage].
func _build(opts: Dictionary, seed_value: int, length: float, gfx: String) -> Array:
	Graphics.set_level(gfx)
	EnvAssets.clear_cache()
	var st = StageGen.new()
	st.opts = opts
	st.generate(seed_value, length)
	var b = StageBuilder.new()
	if st.kind == "touge":
		b.mood = "day"
	root.add_child(b)
	b.build(st)
	for k in 3:
		await physics_frame
	return [b, st]


## Every placed transform of the builder's library things: [[name, Transform3D]].
func _placed(b) -> Array:
	var out: Array = []
	for n in b.get_children():
		if n is MultiMeshInstance3D and (String(n.name).begins_with("TreesN_") or String(n.name).begins_with("TreesF_")
				or String(n.name).begins_with("Boulders_") or String(n.name).begins_with("RockCut_") or n.name == "PowerPoles"
				or String(n.name).begins_with("Warn") or String(n.name).begins_with("Ground_")):
			# (the builder's own list: a headless run's MultiMesh keeps no instance transforms)
			for xf in n.get_meta("xforms", []):
				out.append([String(n.name), xf])
	return out


## The nearest distance (flat) from p to the road's centre line, any part of the road.
func _road_dist(st, p: Vector3) -> Array:
	var best := INF
	var best_i := 0
	for i in range(0, st.pts.size(), 1):
		var q: Vector3 = st.pts[i]
		var d := Vector2(p.x - q.x, p.z - q.z).length()
		if d < best:
			best = d
			best_i = i
	return [best, best_i]


func _stages() -> void:
	var lands := [["touge (cedar mountain)", {"kind": "touge", "dir": "down"}, 5, 2400.0],
		["gravel (conifer forest)", {}, 3, 2000.0],
		["mountain tarmac (alpine)", {"surface": "tarmac"}, 8803, 2000.0],
		["winter (snow and ice)", {"surface": "tarmac", "ice": true}, 9900, 2000.0],
		["wet forest", {"puddles": 2.5, "biome": "wet_forest"}, 4400, 2000.0]]
	for land in lands:
		var r: Array = await _build(land[1], land[2], land[3], "medium")
		var b = r[0]
		var st = r[1]
		var placed := _placed(b)
		var trees := placed.filter(func(e): return e[0].begins_with("Trees"))
		var rocks := placed.filter(func(e): return e[0].begins_with("Boulders"))
		var cuts := placed.filter(func(e): return e[0].begins_with("RockCut"))
		var poles := placed.filter(func(e): return e[0] == "PowerPoles")
		var signs := placed.filter(func(e): return e[0].begins_with("Warn"))
		var ground := placed.filter(func(e): return e[0].begins_with("Ground_"))
		var on_road: Array = []
		for e in placed:
			var xf: Transform3D = e[1]
			var rd: Array = _road_dist(st, xf.origin)
			var half: float = st.widths[mini(int(rd[1]), st.widths.size() - 1)] * 0.5
			# (a tree's or pole's foot clear of the road's edge; a rock face's middle stands back further)
			if rd[0] < half + 1.0:
				on_road.append("%s at s %.0f (%.1f m from the middle)" % [e[0], rd[1] * st.STEP, rd[0]])
		var want_cuts: bool = b.biome.get("cliffs", false) and st.mountain
		check(b.mesh_tree_count > 200 and (rocks.size() > 0 or float(b.biome.get("rocks", {}).get("chance", 0.0)) == 0.0)
			and (cuts.size() > 0 or not want_cuts) and (poles.size() > 3 or st.kind != "touge") and signs.size() > 0
			and (ground.size() > 50 or b.biome.get("undergrowth", {}).is_empty()),
			"%s: %s; %d real trees (%d placed), %d boulders, %d rock cuts, %d power poles, %d warning signs, %d on the forest floor" % [land[0], b.biome.id,
			b.mesh_tree_count, trees.size(), rocks.size(), cuts.size(), poles.size(), signs.size(), ground.size()])
		check(on_road.is_empty(), "%s: nothing on the road (%d things checked against every part of it)%s" % [land[0], placed.size(),
			(": " + "; ".join(on_road.slice(0, 4))) if not on_road.is_empty() else ""])
		# on the ground as drawn: none floating over it, the trees, poles and signs not sunk in it
		var faces := PackedVector3Array()
		for nm in ["Ground", "Mountainside"]:
			var gmi = b.get_node_or_null(nm)
			if gmi is MeshInstance3D:
				faces.append_array((gmi as MeshInstance3D).mesh.get_faces())
		var land_tm := TriangleMesh.new()
		land_tm.create_from_faces(faces)
		var floating: Array = []
		var sunk: Array = []
		var worst_up := 0.0
		for e in placed:
			var o: Vector3 = (e[1] as Transform3D).origin
			var hit: Dictionary = land_tm.intersect_ray(o + Vector3.UP * 60.0, Vector3.DOWN)
			if hit.is_empty():
				continue
			var up: float = o.y - (hit.position as Vector3).y
			worst_up = maxf(worst_up, up)
			if up > 0.25:
				floating.append("%s %.2f m up at %.0f, %.0f" % [e[0], up, o.x, o.z])
			elif (up < -1.0 and (e[0].begins_with("Trees") or e[0].begins_with("Warn"))) or (up < -2.0 and e[0] == "PowerPoles"):   # (a pole on the lowest ground under its foot: into a steep bank)
				sunk.append("%s %.2f m down at %.0f, %.0f" % [e[0], -up, o.x, o.z])
		check(floating.is_empty() and sunk.is_empty(), "%s: everything on the ground as drawn (the highest foot %.2f m over it), the trees, poles and signs not sunk%s" % [land[0], worst_up,
			"" if floating.is_empty() and sunk.is_empty() else ": " + "; ".join((floating + sunk).slice(0, 4))])
		# a car-sized box down both lanes touches nothing
		var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
		var q := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.6, 0.8, 1.6)
		q.shape = box
		var hits := 0
		var first := ""
		var ours := ["Trunks", "Boulders", "Poles"]    # (the library's solid things; the road's own barriers and rails aren't this test's)
		var s: float = st.START_S
		while s < st.finish_s:
			for d in [-1.6, 0.0, 1.6]:
				q.transform = Transform3D(Basis(Vector3.UP, st.heading_at(s)), st.world_at(s, d) + Vector3.UP * 0.9)
				for hit in space.intersect_shape(q, 8):
					if String(hit.collider.name) in ours:
						hits += 1
						if first == "":
							first = "%s at s %.0f" % [hit.collider.name, s]
			s += 2.0
		check(hits == 0, "%s: a car-sized box down the road touches nothing (%d hits%s)" % [land[0], hits, (": " + first) if first != "" else ""])
		b.queue_free()
		await process_frame
	# the solid things the same at LOW and MEDIUM
	var solids := []
	for gfx in ["low", "medium"]:
		var r2: Array = await _build({"kind": "touge", "dir": "down"}, 5, 2400.0, gfx)
		var b2 = r2[0]
		var list: Array = []
		for body_name in ["Trunks", "Boulders", "Poles"]:
			var body: Node = b2.get_node_or_null(body_name)
			if body:
				for cs in body.get_children():
					var sh: Shape3D = (cs as CollisionShape3D).shape
					var size := 0.0
					if sh is CylinderShape3D:
						size = (sh as CylinderShape3D).radius
					elif sh is BoxShape3D:
						size = (sh as BoxShape3D).size.x
					list.append("%s %.2f %.2f %.2f %.3f" % [body_name, cs.global_position.x, cs.global_position.y, cs.global_position.z, size])
		solids.append(list)
		b2.queue_free()
		await process_frame
	check(solids[0].size() > 100 and solids[0] == solids[1], "the solid trunks, boulders and poles the same at LOW and MEDIUM (%d of them): every machine agrees" % solids[0].size())
	Graphics.set_level("medium")
