extends SceneTree
## Cuts the Higgsfield car (assets/models/rally_car.glb: one solid mesh) into a
## body, four wheels and four mud flaps, so the wheels can turn, spin and ride
## the suspension and the flaps can swing. Saves assets/models/car_parts/*.res
## and parts.json (pivots, model units: x = back, y = up, z = left).
##   * each wheel: the triangles inside a cylinder around its axle (found from
##     the dark tyre's extent near where the side view shows it), re-centred
##   * each flap: the red triangles in the thin strip just behind a wheel,
##     re-centred on the flap's top edge (its hinge)
## Run once after replacing the car model:
##   godot --headless --path . -s tools/split_car.gd

const SRC := "res://assets/models/rally_car.glb"
const OUT := "res://assets/models/car_parts/"
const GUESS := [Vector2(-0.60, -0.224), Vector2(0.594, -0.224)]   # front / rear axle (side view)

var img: Image


func _initialize() -> void:
	var scn: Node = load(SRC).instantiate()
	var mi: MeshInstance3D = scn.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh: ArrayMesh = mi.mesh
	var mat: Material = mesh.surface_get_material(0)
	img = (mat as StandardMaterial3D).albedo_texture.get_image()
	if img.is_compressed():
		img.decompress()
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]

	# the wheels: refine each guess from the dark (tyre) vertices around it
	var wheels: Array = []                    # [centre Vector3, radius, z_min, z_max]
	for g in GUESS:
		for side in [1.0, -1.0]:              # +z = the car's left
			var lo := Vector3(INF, INF, INF)
			var hi := -lo
			for i in v.size():
				var p := v[i]
				if signf(p.z) != side or absf(p.z) < 0.25:
					continue
				if Vector2(p.x, p.y).distance_to(g) > 0.2:
					continue
				if _col(uv[i]).get_luminance() < 0.2:
					lo = lo.min(p)
					hi = hi.max(p)
			var r := (hi.y - lo.y) * 0.5
			var c := Vector3((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, (lo.z + hi.z) * 0.5)
			wheels.append([c, r, lo.z, hi.z])
			print("wheel %s r %.3f z %.3f..%.3f" % [c, r, lo.z, hi.z])

	# sort triangles: wheel k, flap k, or body
	var body := []
	var wheel_tris: Array = [[], [], [], []]
	var flap_tris: Array = [[], [], [], []]
	for t in range(0, idx.size(), 3):
		var a := v[idx[t]]
		var b := v[idx[t + 1]]
		var c := v[idx[t + 2]]
		var m := (a + b + c) / 3.0
		var col := _col((uv[idx[t]] + uv[idx[t + 1]] + uv[idx[t + 2]]) / 3.0)
		var where := -1
		for k in 4:
			var w: Array = wheels[k]
			var wc: Vector3 = w[0]
			if signf(m.z) == signf(wc.z) and absf(m.z) >= minf(absf(w[2]), absf(w[3])) - 0.06 \
					and Vector2(m.x - wc.x, m.y - wc.y).length() < float(w[1]) * 1.08:
				where = k
				break
		if where >= 0:
			wheel_tris[where].append(t)
			continue
		for k in 4:
			var w: Array = wheels[k]
			var wc: Vector3 = w[0]
			var r: float = w[1]
			var behind := m.x - wc.x
			var red := col.r > 0.45 and col.g < 0.3 and col.b < 0.3
			if red and signf(m.z) == signf(wc.z) and absf(m.z) > 0.28 and behind > r * 1.05 and behind < r * 1.75 \
					and m.y < wc.y + r * 0.6 and m.y > wc.y - r * 1.15:
				where = k
				break
		if where >= 0:
			flap_tris[where].append(t)
		else:
			body.append(t)

	var info := {"wheels": [], "flaps": [], "radius": []}
	_save(OUT + "body.res", v, nrm, uv, idx, body, Vector3.ZERO, mat)
	var names := ["fl", "fr", "rl", "rr"]
	# order: wheels[] is front-left, front-right, rear-left, rear-right (left = +z)
	for k in 4:
		var wc: Vector3 = wheels[k][0]
		wc.z = (wheels[k][2] + wheels[k][3]) * 0.5
		_save(OUT + "wheel_%s.res" % names[k], v, nrm, uv, idx, wheel_tris[k], wc, mat)
		info.wheels.append([wc.x, wc.y, wc.z])
		info.radius.append(wheels[k][1])
		var hinge := Vector3(0, -INF, 0)
		var sum := Vector3.ZERO
		var n := 0
		for t in flap_tris[k]:
			for j in 3:
				var p := v[idx[t + j]]
				hinge.y = maxf(hinge.y, p.y)
				sum += p
				n += 1
		if n > 0:
			hinge.x = sum.x / n
			hinge.z = sum.z / n
		_save(OUT + "flap_%s.res" % names[k], v, nrm, uv, idx, flap_tris[k], hinge, mat)
		info.flaps.append([hinge.x, hinge.y, hinge.z])
		print("%s: wheel %d tris, flap %d tris, hinge %s" % [names[k], wheel_tris[k].size(), flap_tris[k].size(), hinge])
	print("body: %d tris" % body.size())
	var f := FileAccess.open(OUT + "parts.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "  "))
	f.close()
	quit()


func _col(t: Vector2) -> Color:
	var p := Vector2(t.x * img.get_width(), t.y * img.get_height())
	return img.get_pixelv(p.clamp(Vector2.ZERO, Vector2(img.get_width() - 1, img.get_height() - 1)))


## Save the triangles `tris` (start indices into idx) as a mesh, moved so `origin` is at 0.
func _save(path: String, v: PackedVector3Array, nrm: PackedVector3Array, uv: PackedVector2Array,
		idx: PackedInt32Array, tris: Array, origin: Vector3, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in tris:
		for j in 3:
			var i: int = idx[t + j]
			st.set_normal(nrm[i])
			st.set_uv(uv[i])
			st.add_vertex(v[i] - origin)
	st.index()
	var m := st.commit()
	if m.get_surface_count() > 0:
		m.surface_set_material(0, mat)
	ResourceSaver.save(m, path)
