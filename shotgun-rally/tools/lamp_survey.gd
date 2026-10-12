extends SceneTree
## Which lamps the game finds on each car model (CarLook's own rules: a lamp by its material's
## name, or glowing already, at the front or the back of the body): the headlamps and tail
## lamps, their materials, where they are (model space: x right, y up, -z forward), whether
## both sides were found and where each side's light comes out (its lens: CarLamps' beams start
## there). Scripts only (no pictures: safe on the no-AI cars).
##   godot --headless --path . -s tools/lamp_survey.gd [-- --ids=kaiser_3,gls] [--missing]
##   (--missing: only the cars with a headlamp or tail lamp not found on both sides, or a side's
##   lamp box too big to be only the lamp;
##   --mats: every material at the nose and the tail, lamp or not, for picking a car's lamps)

const CarLook = preload("res://scripts/render/car_look.gd")
const SKIP := ["Wheel_", "Caliper_", "SteeringWheel", "Shifter", "Handbrake"]

var ids: Array = []
var only_missing := false
var list_mats := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"ids": ids = Array(kv[1].split(",", false))
			"missing": only_missing = true
			"mats": list_mats = true


func _process(_dt: float) -> bool:
	var seen := {}
	for f in DirAccess.get_files_at("res://data/vehicles"):
		if not f.ends_with(".json"):
			continue
		var e: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/vehicles/" + f))
		var id := str(e.get("id", ""))
		var model := str(e.get("model", ""))
		if model == "" or (not ids.is_empty() and not id in ids) or seen.has(model):
			continue
		seen[model] = true
		_survey(id, model, str(e.get("role", "")) == "formula")
	return true


func _survey(id: String, model: String, formula := false) -> void:
	var dir := "res://assets/models/cars/%s/" % model
	var parts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "parts.json")) if FileAccess.file_exists(dir + "parts.json") else {}
	var lo: Array = parts.get("body_min", [-0.9, 0.1, -2.2])
	var hi: Array = parts.get("body_max", [0.9, 1.3, 2.2])
	var box := AABB(Vector3(lo[0], lo[1], lo[2]), Vector3(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]))
	var scene: PackedScene = load(dir + model + ".glb")
	if scene == null:
		print("== %s (%s): no model" % [id, model])
		return
	var root: Node3D = scene.instantiate()
	var found := {"head": [], "tail": [], "both": []}
	var surfs := {"head": [], "tail": []}          # (the lamps' surfaces: each side's lamp found in them, the game's way)
	var hints: Array = parts.get("lamps", [])
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.mesh == null or _skip(m3, root):
			continue
		var xf := _xf(m3, root)
		if list_mats:
			for i in m3.mesh.get_surface_count():
				var sm := m3.mesh.surface_get_material(i)
				if sm is BaseMaterial3D:
					_ends(m3.mesh, i, xf, box, String(sm.resource_name), CarLook._lamp_candidate(String(sm.resource_name).to_lower(), sm), (sm as BaseMaterial3D).emission_enabled)
		CarLook._split_lamps(m3, xf, box, hints)            # (the game's own: split by zones, the hints)
		var kinds: Dictionary = m3.mesh.get_meta("lamp_kinds", {})
		for i in m3.mesh.get_surface_count():
			var src := m3.mesh.surface_get_material(i)
			if not (src is BaseMaterial3D):
				continue
			var n := String(src.resource_name).to_lower()
			var at: AABB = xf * CarLook._surface_box(m3.mesh, i)
			var kind := ""
			if kinds.has(i):
				kind = str(kinds[i]) if str(kinds[i]) != "none" else ""
			elif CarLook._lamp_candidate(n, src):
				kind = CarLook._kind_in(box, at)
			if kind != "":
				found[kind].append([String(src.resource_name) + (" (split)" if kinds.has(i) else ""), at])
				if kind in ["head", "tail"]:
					surfs[kind].append([m3.mesh, i, xf])
	var sides := {"head": CarLook._lamp_sides(surfs.head, box.get_center().x), "tail": CarLook._lamp_sides(surfs.tail, box.get_center().x)}
	var lens := {"head": CarLook._lamp_lenses(surfs.head, box.get_center().x, "head"), "tail": CarLook._lamp_lenses(surfs.tail, box.get_center().x, "tail")}
	root.free()
	var cx := box.get_center().x
	var lines: Array = []
	var bad := false
	for kind in ["head", "tail"]:
		var l := false
		var r := false
		var names: Array = []
		var merged := AABB()
		for e in found[kind]:
			var at: AABB = e[1]
			l = l or at.position.x < cx - 0.15
			r = r or at.end.x > cx + 0.15
			if not e[0] in names:
				names.append(e[0])
			merged = at if merged.size == Vector3.ZERO else merged.merge(at)
		var ok := l and r
		if kind == "head" and formula and not (l or r):
			lines.append("  head: none (a Formula car has no headlamps)")
			continue
		bad = bad or not ok
		lines.append("  %s: %s%s  %s" % [kind, "both sides" if ok else ("ONE SIDE" if (l or r) else "NOT FOUND"),
			("  x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f" % [merged.position.x, merged.end.x, merged.position.y, merged.end.y, merged.position.z, merged.end.z]) if merged.size != Vector3.ZERO else "",
			", ".join(names.slice(0, 6))])
		for k in 2:                                  # (each side's lamp: where its beam / glow starts)
			var sb: AABB = sides[kind][k]
			if sb.size != Vector3.ZERO:
				var odd := sb.size.y > 0.45            # (a deep lamp is fine: the beam starts at its front)
				bad = bad or odd
				var at: Vector3 = lens[kind][k]               # (where its light comes out: the beam starts 2 cm out from it)
				lines.append("    %s_%s: x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f  lens (%.2f, %.2f, %.2f)%s" % [kind, "lr"[k], sb.position.x, sb.end.x,
					sb.position.y, sb.end.y, sb.position.z, sb.end.z, at.x, at.y, at.z, "  <- TOO BIG (more than the lamp?)" if odd else ""])
	if not found.both.is_empty():
		lines.append("  both ends (split by the game): " + ", ".join(found.both.map(func(e): return e[0]).slice(0, 4)))
	if bad or not only_missing:
		print("== %s (%s)%s" % [id, model, "" if not bad else "  <- MISSING"])
		for s in lines:
			print(s)


## (--mats) A surface's triangles in the nose (the front 20 % of the body, above the bottom
## 12 cm) and the tail (the back 20 %): how many, the box they fill.
func _ends(mesh: Mesh, i: int, xf: Transform3D, box: AABB, name: String, lamp: bool, glows: bool) -> void:
	var arr := mesh.surface_get_arrays(i)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx = arr[Mesh.ARRAY_INDEX]
	if idx == null or idx.size() == 0:
		idx = PackedInt32Array(range(v.size()))
	var ends := {"FRONT": [0, AABB()], "BACK ": [0, AABB()]}
	var total: int = idx.size() / 3
	for t in range(0, idx.size() - 2, 3):
		var a: Vector3 = xf * v[idx[t]]
		var b: Vector3 = xf * v[idx[t + 1]]
		var c: Vector3 = xf * v[idx[t + 2]]
		var m := (a + b + c) / 3.0
		var zf := (m.z - box.position.z) / maxf(box.size.z, 0.01)
		if m.y < box.position.y + 0.12:
			continue
		var k := "FRONT" if zf < 0.2 else ("BACK " if zf > 0.8 else "")
		if k == "":
			continue
		var tb := AABB(a, Vector3.ZERO).expand(b).expand(c)
		ends[k][0] += 1
		ends[k][1] = tb if ends[k][0] == 1 else (ends[k][1] as AABB).merge(tb)
	for k in ends:
		if ends[k][0] >= 8:
			var bb: AABB = ends[k][1]
			print("    mat %-46s %s %5d of %6d tris  x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f%s%s" % [name.substr(0, 46), k, ends[k][0], total,
				bb.position.x, bb.end.x, bb.position.y, bb.end.y, bb.position.z, bb.end.z, "  LAMP?" if lamp else "", "  GLOWS" if glows else ""])


func _skip(n: Node, root: Node) -> bool:
	while n and n != root:
		for s in SKIP:
			if String(n.name).begins_with(s):
				return true
		n = n.get_parent()
	return false


func _xf(n: Node3D, root: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
