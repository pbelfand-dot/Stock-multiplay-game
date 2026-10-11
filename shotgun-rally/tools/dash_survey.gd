extends SceneTree
## What a car's dashboard is made of, for writing its data/dash/<model>.json: every material
## with faces in front of the driver (a box from the steering wheel's centre, the model's axes:
## x right, y up, z back), its faces there, where they are (the box they fill, metres from the
## wheel's centre: the numbers a panel's "box" and a needle's "hub" take), which way they face,
## their UVs and texture, and whether they glow. Scripts only: no pictures, so it's safe on
## the no-AI cars too.
##   godot --headless --path . -s tools/dash_survey.gd -- --ids=gls,kasten [--box=x0,x1,y0,y1,z0,z1] [--min=20]
##   (the box: default -0.75,0.95,-0.35,0.40,-0.75,0.15; a right-hand-drive car's x is mirrored;
##   --min: the fewest faces to list a material)

var ids: Array = []
var box := [-0.75, 0.95, -0.35, 0.40, -0.75, 0.15]
var least := 20


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"ids": ids = Array(kv[1].split(",", false))
			"box": box = Array(kv[1].split(",")).map(func(x): return float(x))
			"min": least = int(kv[1])


func _process(_dt: float) -> bool:
	var Catalog = load("res://scripts/game/catalog.gd")
	var st = load("res://scripts/stage/stage_gen.gd").new()
	st.generate(4)
	for id in ids:
		var car = load("res://scripts/vehicle/rally_car.gd").new()
		car.setup = Catalog.setup(id)
		root.add_child(car)
		car.freeze = true
		car.set_physics_process(false)
		var cp = load("res://scripts/vehicle/cockpit.gd").new()
		car.add_child(cp)
		cp.build(car, st)
		_survey(id, car, cp)
		car.free()
	return true


func _survey(id: String, car, cp) -> void:
	var off: Vector3 = car.model_offset()
	var c: Vector3 = cp.wheel_c - off
	var eye: Vector3 = cp.eye_driver - off
	var rhd: bool = str(cp.own.get("side", "left")) == "right"
	var sx := -1.0 if rhd else 1.0
	print("== %s (%s)  wheel %s  eye from the wheel %s  %s" % [id, str(car.setup.get("model", "")), _v(c), _v(eye - c), "RHD" if rhd else "LHD"])
	var rows: Array = []
	for mi in car.body_model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not (m.mesh is ArrayMesh):
			continue
		var xf := _rel(car, m)
		for si in m.mesh.get_surface_count():
			var mat := m.get_active_material(si)
			var arr := m.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var uvs = arr[Mesh.ARRAY_TEX_UV]
			var idx = arr[Mesh.ARRAY_INDEX]
			var n: int = (idx.size() if idx != null and idx.size() > 0 else vs.size()) / 3
			var lo := Vector3.INF
			var hi := -Vector3.INF
			var uvlo := Vector2.INF
			var uvhi := -Vector2.INF
			var count := 0
			var area := 0.0
			var facing := 0.0
			for t in n:
				var k0: int = idx[t * 3] if idx != null and idx.size() > 0 else t * 3
				var k1: int = idx[t * 3 + 1] if idx != null and idx.size() > 0 else t * 3 + 1
				var k2: int = idx[t * 3 + 2] if idx != null and idx.size() > 0 else t * 3 + 2
				var a: Vector3 = xf * vs[k0] - c
				var b: Vector3 = xf * vs[k1] - c
				var d: Vector3 = xf * vs[k2] - c
				var mid := (a + b + d) / 3.0
				if mid.x * sx < box[0] or mid.x * sx > box[1] or mid.y < box[2] or mid.y > box[3] or mid.z < box[4] or mid.z > box[5]:
					continue
				count += 1
				for p in [a, b, d]:
					lo = lo.min(p)
					hi = hi.max(p)
				var f := (d - a).cross(b - a)
				var ar := f.length() * 0.5
				area += ar
				if ar > 1e-9:
					facing += f.normalized().dot((eye - c - mid).normalized()) * ar
				if uvs != null and uvs.size() > k0:
					for kk in [k0, k1, k2]:
						uvlo = uvlo.min(uvs[kk])
						uvhi = uvhi.max(uvs[kk])
			if count < least:
				continue
			var tex := ""
			var glow := false
			var col := ""
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				if bm.albedo_texture:
					tex = "%s %dx%d" % [bm.albedo_texture.resource_path.get_file() if bm.albedo_texture.resource_path != "" else "(embedded)",
						bm.albedo_texture.get_width(), bm.albedo_texture.get_height()]
				glow = bm.emission_enabled
				col = "#" + bm.albedo_color.to_html(false)
			rows.append([area, "  %-60s %6d f %6.3f m2 facing %+.2f  x %+.3f..%+.3f y %+.3f..%+.3f z %+.3f..%+.3f  uv %s..%s  %s %s%s  [%s]" % [
				(mat.resource_name if mat else "(none)").substr(0, 60), count, area, facing / maxf(area, 1e-9),
				lo.x, hi.x, lo.y, hi.y, lo.z, hi.z, _uv(uvlo), _uv(uvhi), col, tex, " GLOW" if glow else "", m.name]])
	rows.sort_custom(func(p, q): return p[0] > q[0])
	for r in rows:
		print(r[1])


func _rel(car, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p: Node = n
	while p and p != car.body_model:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


static func _v(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


static func _uv(v: Vector2) -> String:
	return "-" if v.x == INF else "(%.3f, %.3f)" % [v.x, v.y]
