extends SceneTree
## Cuts a Higgsfield car body (one textured mesh, its glass painted flat pale
## blue, its tyres black) into the parts the game draws, so the wheels can turn,
## spin and ride the suspension and the glass can be see-through:
##   * the wheels: found from the black tyre triangles in each corner; their
##     triangles are dropped (the game builds its own wheels, wheel_mesh.gd) and
##     their centres, radii and widths saved
##   * the glass: the pale-blue triangles, saved as their own mesh
##   * the body: everything else
## The model is turned to the game's model axes (x = back, y = up, z = left) and
## scaled so its wheelbase is the physics car's at the car's MODEL_SCALE.
## The body keeps the model's own paint (the garage's liveries are drawn for the
## hatchback's shape); `erase` rectangles (texture pixels) paint out stray marks
## the generator added, such as made-up badge lettering, with the paint round
## them, saved as <out>/paint.jpg (the game uses it in place of the model's
## texture). Saves <out>/body.res, glass.res and parts.json (with how many
## spokes its wheels get). Run once after replacing a body model:
##   godot --headless --path . -s tools/split_body.gd -- <res://model.glb> <res://out_dir/> <nose: +x | -x> [spokes] [erase=x0,y0,x1,y1;...]
## The coupé (assets/models/coupe):
##   ... -- res://assets/models/coupe/coupe.glb res://assets/models/coupe/parts/ +x 16 "erase=995,1279,1060,1302"

const MODEL_SCALE := 1.95          # model units -> m (rally_car.gd)
const WHEELBASE := 2.5             # m: the physics car's (data/cars/awd_rally.tres: rear_axle - front_axle)

var img: Image


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var src: String = args[0]
	var out: String = args[1]
	var turn := args.size() > 2 and args[2] == "+x"     # its nose points +x: turn it round to -x
	var spokes := int(args[3]) if args.size() > 3 else 8
	var erase := []
	for a in args:
		if a.begins_with("erase="):
			for r in a.trim_prefix("erase=").split(";"):
				var n := r.split(",")
				erase.append(Rect2i(int(n[0]), int(n[1]), int(n[2]) - int(n[0]), int(n[3]) - int(n[1])))
	var scn: Node = load(src).instantiate()
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
	var xf := mi.transform
	if turn:
		xf = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * xf
	for i in v.size():
		v[i] = xf * v[i]
		nrm[i] = (xf.basis * nrm[i]).normalized()
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in v:
		lo = lo.min(p)
		hi = hi.max(p)
	var mid := (lo + hi) * 0.5

	# the wheels: the black tyre and gold rim low down in each corner, in the outer
	# slice of the car's width (deeper in are the black wheel-well liners)
	var tone := PackedByteArray()             # per vertex: 1 = black, 2 = gold, 0 = anything else
	tone.resize(v.size())
	for i in v.size():
		var c := _col(uv[i])
		tone[i] = 1 if c.get_luminance() < 0.18 else (2 if _gold(c) else 0)
	var wheels: Array = []                    # [centre, radius, |z| inner, |z| outer], FL FR RL RR
	for front in [true, false]:
		for left in [true, false]:
			var ids := []
			for i in v.size():
				var p := v[i]
				if (p.x < mid.x) != front or (p.z > mid.z) != left or tone[i] == 0:
					continue
				if absf(p.z - mid.z) < (hi.z - mid.z) * 0.8 or p.y > lo.y + (hi.y - lo.y) * 0.6:
					continue
				ids.append(i)
			wheels.append(_wheel(v, tone, ids, lo, hi, mid.z))
	# all four the same size, the largest found (a low arch hides the top of a tyre,
	# so it reads small), standing on the same ground as the lowest
	var big := 0.0
	var ground := INF
	for w in wheels:
		big = maxf(big, w[1])
		ground = minf(ground, w[0].y - w[1])
	for w in wheels:
		w[1] = big
		w[0].y = ground + big
	var wb := absf(wheels[2][0].x - wheels[0][0].x + wheels[3][0].x - wheels[1][0].x) * 0.5
	var s := WHEELBASE / MODEL_SCALE / wb
	var centre := Vector3((wheels[0][0].x + wheels[1][0].x + wheels[2][0].x + wheels[3][0].x) * 0.25, 0.0, mid.z)
	for i in v.size():
		v[i] = (v[i] - centre) * s
	for w in wheels:
		w[0] = (w[0] - centre) * s
		w[1] *= s
		w[2] *= s
		w[3] *= s

	# sort the triangles: a wheel's (dropped), the glass, or the body
	var body := []
	var glass := []
	var dropped := 0
	for t in range(0, idx.size(), 3):
		var m := (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0
		var col := _col((uv[idx[t]] + uv[idx[t + 1]] + uv[idx[t + 2]]) / 3.0)
		if _in_wheel(m, col, wheels):
			dropped += 1
		elif _blue(col):
			glass.append(t)
		else:
			body.append(t)

	_save(out + "body.res", v, nrm, uv, idx, body, mat)
	_save(out + "glass.res", v, nrm, uv, idx, glass, null)
	var info := {"wheels": [], "radius": [], "width": [], "flaps": [], "glass": true, "own_paint": true, "spokes": spokes}
	var depth := 0.0
	for w in wheels:
		info.wheels.append([w[0].x, w[0].y, w[0].z])
		info.radius.append(w[1])
		info.width.append(w[3] - w[2])
		depth = maxf(depth, -(w[0].y - w[1]) * MODEL_SCALE)
	info.tyre_depth = depth                   # m below the model's origin its tyres touch the ground
	var grille := _grille(v, tone, (hi - lo) * s)
	if not grille.is_empty():
		info.grille = grille                   # [front x, centre y, height] of the black grille band
		print("grille: front x %.3f  centre y %.3f  height %.3f" % grille)
	if not erase.is_empty():
		var paint: Image = img.duplicate()
		for r in erase:
			_erase(paint, r)
		paint.save_jpg(ProjectSettings.globalize_path(out + "paint.jpg"), 0.92)
		print("painted out %d marks -> %spaint.jpg" % [erase.size(), out])
	var f := FileAccess.open(out + "parts.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "  "))
	f.close()
	print("scale %.4f  wheelbase %.3f m  length %.2f m  width %.2f m  height %.2f m" % [s, wb * s * MODEL_SCALE,
		(hi.x - lo.x) * s * MODEL_SCALE, (hi.z - lo.z) * s * MODEL_SCALE, (hi.y - lo.y) * s * MODEL_SCALE])
	for k in 4:
		print("wheel %d: centre %s  r %.3f (%.2f m)  width %.3f" % [k, wheels[k][0], wheels[k][1],
			wheels[k][1] * MODEL_SCALE, wheels[k][3] - wheels[k][2]])
	print("body %d tris, glass %d tris, wheels %d tris dropped, tyre depth %.3f m" % [body.size(), glass.size(), dropped, depth])
	quit()


## A wheel from its black and gold vertices (`ids`, the outer slice of one
## corner): first roughly, where they are densest along x; then the tyre's
## outline, from the 2nd to 98th percentile of the ones near that (a stray sill
## or bumper lip doesn't stretch it), twice over; then how wide it is, from the
## tread on its lower half (the arch hides the upper).
func _wheel(v: PackedVector3Array, tone: PackedByteArray, ids: Array, lo: Vector3, hi: Vector3, mid_z: float) -> Array:
	const BINS := 120
	var hist := []
	hist.resize(BINS)
	hist.fill(0)
	for i in ids:
		hist[clampi(int((v[i].x - lo.x) / (hi.x - lo.x) * BINS), 0, BINS - 1)] += 1
	var peak := 0
	for b in BINS:
		if hist[b] > hist[peak]:
			peak = b
	var c := Vector2(lo.x + (hi.x - lo.x) * (peak + 0.5) / BINS, lo.y + (hi.y - lo.y) * 0.25)
	var r := (hi.y - lo.y) * 0.3                   # generous first: a tyre is ~half the car's height
	for _round in 3:
		var xs := []
		var ys := []
		for i in ids:
			if Vector2(v[i].x, v[i].y).distance_to(c) <= r * 1.15:
				xs.append(v[i].x)
				ys.append(v[i].y)
		xs.sort()
		ys.sort()
		var x0: float = xs[int(xs.size() * 0.02)]
		var x1: float = xs[int(xs.size() * 0.98)]
		var y0: float = ys[int(ys.size() * 0.02)]
		var y1: float = ys[int(ys.size() * 0.98)]
		r = maxf(x1 - x0, y1 - y0) * 0.5
		c = Vector2((x0 + x1) * 0.5, y0 + r)
	# its sides: the black tread at the bottom of the tyre, across its width
	var side := 1.0 if v[ids[0]].z > mid_z else -1.0
	var zs := []
	for i in v.size():
		var p := v[i]
		if tone[i] != 1 or signf(p.z - mid_z) != side or p.y > c.y:
			continue
		var d := Vector2(p.x, p.y).distance_to(c)
		if d > r * 0.85 and d < r * 1.02:
			zs.append(absf(p.z - mid_z))
	zs.sort()
	var z1: float = zs[int(zs.size() * 0.98)]
	var z0: float = maxf(zs[int(zs.size() * 0.05)], z1 - r * 0.9)   # no wider than a tyre can be
	return [Vector3(c.x, c.y, mid_z + side * (z0 + z1) * 0.5), r, z0, z1]


## The grille: the black band across the middle of the nose, between the
## headlights (above the bumper's intakes and the splitter). v is already turned
## and scaled (nose at -x); size is the model's.
func _grille(v: PackedVector3Array, tone: PackedByteArray, size: Vector3) -> Array:
	var nose := INF
	var floor_y := INF
	for p in v:
		nose = minf(nose, p.x)
		floor_y = minf(floor_y, p.y)
	var ys := []
	var xs := []
	for i in v.size():
		var p := v[i]
		if tone[i] != 1 or p.x > nose + size.x * 0.04 or absf(p.z) > size.z * 0.22:
			continue
		if p.y < floor_y + size.y * 0.33 or p.y > floor_y + size.y * 0.62:
			continue
		ys.append(p.y)
		xs.append(p.x)
	if ys.size() < 20:
		return []
	ys.sort()
	xs.sort()
	var y0: float = ys[int(ys.size() * 0.05)]
	var y1: float = ys[int(ys.size() * 0.95)]
	return [xs[int(xs.size() * 0.1)], (y0 + y1) * 0.5, y1 - y0]


## A wheel's triangle: inside its tyre's outline (from the inside face of the tyre
## out), or just outside it and black or gold (the tyre's shoulder, the rim), not
## the paint of the arch over it.
func _in_wheel(m: Vector3, col: Color, wheels: Array) -> bool:
	for w in wheels:
		var c: Vector3 = w[0]
		if signf(m.z) != signf(c.z) or absf(m.z) < float(w[2]) - float(w[1]) * 0.08:
			continue
		var d := Vector2(m.x - c.x, m.y - c.y).length()
		var r: float = w[1]
		if d <= r * 0.97:
			return true
		if d <= r * 1.08 and (col.get_luminance() < 0.18 or _gold(col)):
			return true
	return false


## Paint out a mark: every pixel in the rectangle that isn't the paint round
## it (the median colour there) is filled in from the paint just outside the
## rectangle's four sides, blended across (no flat patch where the paint shades).
func _erase(im: Image, r: Rect2i) -> void:
	var rs := []
	var gs := []
	var bs := []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := im.get_pixel(x, y)
			rs.append(c.r)
			gs.append(c.g)
			bs.append(c.b)
	rs.sort()
	gs.sort()
	bs.sort()
	var m := Color(rs[rs.size() / 2], gs[gs.size() / 2], bs[bs.size() / 2])
	var src: Image = im.duplicate()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := src.get_pixel(x, y)
			if absf(c.r - m.r) + absf(c.g - m.g) + absf(c.b - m.b) <= 0.05:
				continue
			var u := float(x - r.position.x) / maxf(r.size.x - 1, 1)
			var v := float(y - r.position.y) / maxf(r.size.y - 1, 1)
			var lr := _edge(src, r.position.x - 2, y, m).lerp(_edge(src, r.end.x + 1, y, m), u)
			var tb := _edge(src, x, r.position.y - 2, m).lerp(_edge(src, x, r.end.y + 1, m), v)
			im.set_pixel(x, y, lr.lerp(tb, 0.5))


## The paint just outside a mark: that pixel, unless it is itself a line or a
## mark (far from the paint's colour m), then m.
func _edge(im: Image, x: int, y: int, m: Color) -> Color:
	var c := im.get_pixel(clampi(x, 0, im.get_width() - 1), clampi(y, 0, im.get_height() - 1))
	return c if absf(c.r - m.r) + absf(c.g - m.g) + absf(c.b - m.b) < 0.2 else m


func _gold(col: Color) -> bool:
	return col.r > 0.45 and col.g > 0.3 and col.b < 0.3 and col.r - col.g < 0.3


func _blue(col: Color) -> bool:
	return col.b > 0.55 and col.b > col.r + 0.15 and col.g > 0.4


func _col(t: Vector2) -> Color:
	var p := Vector2(t.x * img.get_width(), t.y * img.get_height())
	return img.get_pixelv(p.clamp(Vector2.ZERO, Vector2(img.get_width() - 1, img.get_height() - 1)))


## Save the triangles `tris` (start indices into idx) as a mesh.
func _save(path: String, v: PackedVector3Array, nrm: PackedVector3Array, uv: PackedVector2Array,
		idx: PackedInt32Array, tris: Array, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in tris:
		for j in 3:
			var i: int = idx[t + j]
			st.set_normal(nrm[i])
			st.set_uv(uv[i])
			st.add_vertex(v[i])
	st.index()
	var m := st.commit()
	if m.get_surface_count() > 0 and mat:
		m.surface_set_material(0, mat)
	ResourceSaver.save(m, path)
