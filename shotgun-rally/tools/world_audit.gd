extends SceneTree
## The world's models (everything but the cars) checked from their data, as the game loads them:
## every entry in data/environment_assets.json at each of its levels of detail (EnvAssets.mesh).
##   godot --headless --path . -s tools/world_audit.gd [-- --json=out.json]
## For each model and level:
##   * size: its mesh's bounds against its entry's ("size", or a tree's "height") - a model
##     squashed or stretched on import
##   * faces: triangles wound against their own normals (drawn from the wrong side: one-sided
##     faces vanish from outside), by share of the model's area
##   * textures: a surface with no image where its material expects one (plain white), an image
##     that's mostly magenta (a missing texture's colour), a tiny image
##   * material: metal or mirror-smooth where a world model shouldn't be, or glowing
##   * levels: a tree's LOD1 and far card the same height as its LOD0 (a pop where they swap)
##   * the far card: two faces back to back, upright (a card lying down or facing one way)
## Prints one line per model with its flags (FLAG ...) and a summary; exits 0 (a report, not a test).

const EnvAssets = preload("res://scripts/stage/env_assets.gd")

var rows: Array = []


func _initialize() -> void:
	var json_out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--json="):
			json_out = a.trim_prefix("--json=")
	var winding := _front_sign()
	var f := FileAccess.open("res://data/environment_assets.json", FileAccess.READ)
	var all: Dictionary = JSON.parse_string(f.get_as_text()).assets
	var ids: Array = all.keys()
	ids.sort()
	var flagged := 0
	for id in ids:
		var e: Dictionary = all[id]
		var kind := str(e.get("kind", ""))
		var lods: Array = ["LOD0", "LOD1", "BB"] if kind == "tree" else [""]
		if kind == "skyline":
			lods = ["", "LOD1", "LOD2"]
		var heights := {}
		for lod in lods:
			var m: Mesh = EnvAssets.mesh(id, lod)
			var name: String = id + ("/" + lod if lod != "" else "")
			if m == null:
				_row(name, kind, ["FLAG missing mesh"])
				flagged += 1
				continue
			var flags: Array = []
			var ab := m.get_aabb()
			heights[lod] = ab.size.y
			var sz = e.get("size", null)
			if sz is Array and lod in ["", "LOD0"]:
				for k in 3:
					var got: float = [ab.size.x, ab.size.y, ab.size.z][k]
					if absf(got - float(sz[k])) > maxf(float(sz[k]) * 0.03, 0.06):
						flags.append("FLAG size %.1f x %.1f x %.1f against the entry's %s" % [ab.size.x, ab.size.y, ab.size.z, str(sz)])
						break
			if kind == "tree" and lod == "LOD0" and e.has("height") and absf(ab.size.y / float(e.height) - 1.0) > 0.05:
				flags.append("FLAG height %.1f against the entry's %.1f" % [ab.size.y, float(e.height)])
			var st := _faces(m, winding, kind in ["building", "skyline"])
			if st.back_share > 0.02:
				flags.append("FLAG %.0f %% of its area wound against its normals" % (st.back_share * 100.0))
			var textured := false
			for si in m.get_surface_count():
				var tm := m.surface_get_material(si)
				textured = textured or (tm is BaseMaterial3D and (tm as BaseMaterial3D).albedo_texture != null)
			if not textured and kind not in ["building", "skyline"]:
				flags.append("note untextured (flat colours from its pack)")
			for si in m.get_surface_count():
				var mat := m.surface_get_material(si)
				if kind == "building" or kind == "skyline":
					continue                                    # (the game draws these with its own shaders)
				if mat is BaseMaterial3D:
					var bm := mat as BaseMaterial3D
					var tex := bm.albedo_texture
					if textured and tex == null and bm.albedo_color.v > 0.95 and bm.albedo_color.s < 0.05:
						flags.append("FLAG surface %d plain white (no image, where its others have one)" % si)
					if tex != null:
						var img := tex.get_image()
						if img != null:
							if img.get_width() < 16:
								flags.append("FLAG surface %d image %d px" % [si, img.get_width()])
							if img.is_compressed():
								img = img.duplicate()
								img.decompress()
							var mag := _magenta(img)
							if mag > 0.3:
								flags.append("FLAG surface %d image %.0f %% magenta" % [si, mag * 100.0])
					if bm.metallic > 0.6 and bm.metallic_texture == null:
						flags.append("note surface %d metallic %.2f" % [si, bm.metallic])
					if bm.roughness < 0.2 and bm.roughness_texture == null:
						if bm.resource_name.to_lower().contains("glass"):
							flags.append("note surface %d glass (roughness %.2f)" % [si, bm.roughness])
						else:
							flags.append("FLAG surface %d mirror-smooth (roughness %.2f)" % [si, bm.roughness])
					if bm.emission_enabled:
						flags.append("note surface %d glows (%s x %.1f)" % [si, bm.emission.to_html(false), bm.emission_energy_multiplier])
			if lod == "BB":
				var up := ab.size.y > maxf(ab.size.x, ab.size.z) * 0.5
				if not up or st.back_share > 0.02 and st.tris > 0:
					flags.append("FLAG far card lying down or one-faced")
			_row(name, kind, flags, st)
			if flags.any(func(x): return str(x).begins_with("FLAG")):
				flagged += 1
		if kind == "tree" and heights.has("LOD0"):
			for lod in ["LOD1", "BB"]:
				if heights.has(lod) and absf(float(heights[lod]) / maxf(float(heights.LOD0), 0.01) - 1.0) > 0.08:
					_row(id + "/" + lod, kind, ["FLAG %.1f m tall against LOD0's %.1f (a pop where they swap)" % [float(heights[lod]), float(heights.LOD0)]])
					flagged += 1
	print("[audit] %d models and levels, %d flagged" % [rows.size(), flagged])
	if json_out != "":
		var fo := FileAccess.open(json_out, FileAccess.WRITE)
		fo.store_string(JSON.stringify(rows, " "))
	quit(0)


func _row(name: String, kind: String, flags: Array, st := {}) -> void:
	rows.append({"model": name, "kind": kind, "flags": flags, "tris": st.get("tris", 0)})
	print("[audit] %-24s %-8s %6d tris  %s" % [name, kind, int(st.get("tris", 0)), "; ".join(flags) if not flags.is_empty() else "ok"])


## Which way Godot's front faces wind: the sign of (b - a) x (c - a) . normal on a box it made.
func _front_sign() -> float:
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().get_mesh_arrays())
	var st := _faces(am, 1.0)
	return 1.0 if st.back_share < 0.5 else -1.0


## A mesh's triangles against their normals: {tris, back_share (of the area)}, over the surfaces
## drawn one-sided (a two-sided material shows either way; culled: the game's own shader for a
## building, a material that culls its back faces).
func _faces(m: Mesh, sign: float, culled := false) -> Dictionary:
	var tris := 0
	var back := 0.0
	var total := 0.0
	for si in m.get_surface_count():
		if m.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var mat := m.surface_get_material(si)
		var one_sided := culled or mat == null or (mat is BaseMaterial3D and (mat as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_BACK)
		if not one_sided:
			continue
		var arr := m.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n = arr[Mesh.ARRAY_NORMAL]
		var idx = arr[Mesh.ARRAY_INDEX]
		var count: int = (idx as PackedInt32Array).size() if idx != null else v.size()
		var k := 0
		while k + 2 < count:
			var i0: int = idx[k] if idx != null else k
			var i1: int = idx[k + 1] if idx != null else k + 1
			var i2: int = idx[k + 2] if idx != null else k + 2
			var c := (v[i1] - v[i0]).cross(v[i2] - v[i0])
			var area := c.length() * 0.5
			total += area
			tris += 1
			if n != null and (n as PackedVector3Array).size() == v.size():
				var nn: Vector3 = n[i0] + n[i1] + n[i2]
				if c.dot(nn) * sign < 0.0:
					back += area
			k += 3
	return {"tris": tris, "back_share": back / maxf(total, 1e-9)}


## The share of an image's pixels (a sample of them) that's magenta (a missing texture).
func _magenta(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var hit := 0
	var n := 0
	for y in range(0, h, maxi(h / 32, 1)):
		for x in range(0, w, maxi(w / 32, 1)):
			var c := img.get_pixel(x, y)
			n += 1
			if c.r > 0.8 and c.b > 0.8 and c.g < 0.25:
				hit += 1
	return float(hit) / maxf(n, 1)
