extends RefCounted
## A rally wheel, built in code: a gravel tyre (rounded sidewalls, two staggered
## rows of tread blocks standing proud of the carcass) on an 8-spoke rim with a
## dished centre and a lock nut. Two surfaces: 0 = rubber, 1 = the rim (its
## material takes the wheel colour). The axle runs along `axis` ("x" or "z"); the
## wheel is centred on the origin. Built once per size and kept.

const SEGMENTS := 48           # around the wheel
const BLOCKS := 24             # tread blocks per row
const SPOKES := 8

static var _cache := {}


## The wheel: radius and width in its own units (m for the plain tyres, model
## units for the body model's), the axle along "x" or "z", and how many spokes
## (more = thinner, like a multi-spoke rally wheel).
static func build(radius: float, width: float, axis := "x", spokes := SPOKES) -> ArrayMesh:
	var key := "%.4f_%.4f_%s_%d" % [radius, width, axis, spokes]
	if _cache.has(key):
		return _cache[key]
	var rubber := SurfaceTool.new()
	rubber.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := width * 0.5
	var tread_r := radius * 0.955          # the carcass under the blocks
	var block_h := radius - tread_r
	var bead_r := radius * 0.64            # where the tyre meets the rim
	# the carcass: a revolved profile (bead -> sidewall bulge -> shoulder -> crown)
	var prof := [Vector2(bead_r, half * 0.92), Vector2(radius * 0.78, half * 1.0), Vector2(radius * 0.9, half * 0.98),
		Vector2(tread_r * 0.995, half * 0.86), Vector2(tread_r, half * 0.6), Vector2(tread_r, 0.0)]
	var full: Array = prof.duplicate()
	for i in range(prof.size() - 2, -1, -1):
		full.append(Vector2(prof[i].x, -prof[i].y))
	_revolve(rubber, full, radius, axis)
	# the tread: two staggered rows of blocks on the crown
	for row in 2:
		var z0: float = (-half * 0.56 if row == 0 else half * 0.04)
		var z1: float = (-half * 0.04 if row == 0 else half * 0.56)
		for b in BLOCKS:
			var a0 := TAU * (b + (0.5 if row == 1 else 0.0)) / BLOCKS
			var a1 := a0 + TAU / BLOCKS * 0.62
			_block(rubber, a0, a1, tread_r * 0.999, tread_r + block_h, z0, z1, axis)
	# the rim: the barrel inside the bead, the dish, spokes, the hub and nut
	var barrel := [Vector2(bead_r, half * 0.92), Vector2(bead_r * 0.97, half * 0.7), Vector2(bead_r * 0.97, -half * 0.7),
		Vector2(bead_r, -half * 0.92)]
	_revolve(rim, barrel, radius, axis)
	var face := half * 0.45                 # the spoke face sits a little in from the outside
	_disc(rim, bead_r * 0.97, bead_r * 0.86, face, axis)           # the outer ring of the dish
	_disc(rim, bead_r * 0.30, 0.0, face + half * 0.08, axis)        # the hub
	var thin := sqrt(float(SPOKES) / spokes)
	for s in spokes:
		var a := TAU * s / spokes
		_spoke(rim, a, bead_r * 0.28, bead_r * 0.88, bead_r * 0.11 * thin, bead_r * 0.07 * thin, face, half * 0.08, axis)
	_nut(rim, bead_r * 0.12, face + half * 0.08, half * 0.1, axis)
	var mesh := ArrayMesh.new()
	rubber.generate_normals()
	rim.generate_normals()
	rubber.commit(mesh)
	rim.commit(mesh)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.07, 0.07, 0.075)
	rm.roughness = 0.95
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, rm)
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.72, 0.73, 0.75)
	mm.metallic = 0.5
	mm.roughness = 0.35
	mm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(1, mm)
	_cache[key] = mesh
	return mesh


## A point at angle a round the axle, radius r, w along it.
static func _p(a: float, r: float, w: float, axis: String) -> Vector3:
	var u := cos(a) * r
	var v := sin(a) * r
	return Vector3(w, u, v) if axis == "x" else Vector3(v, u, w)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


## Revolve a profile (Vector2(radius, along the axle)) round the axle.
static func _revolve(st: SurfaceTool, prof: Array, _r: float, axis: String) -> void:
	for i in SEGMENTS:
		var a0 := TAU * i / SEGMENTS
		var a1 := TAU * (i + 1) / SEGMENTS
		for k in prof.size() - 1:
			var p: Vector2 = prof[k]
			var q: Vector2 = prof[k + 1]
			_quad(st, _p(a0, p.x, p.y, axis), _p(a1, p.x, p.y, axis), _p(a1, q.x, q.y, axis), _p(a0, q.x, q.y, axis))


## A flat ring (or disc, r1 = 0) facing outward at w along the axle.
static func _disc(st: SurfaceTool, r0: float, r1: float, w: float, axis: String) -> void:
	for side in [1.0, -1.0]:
		for i in SEGMENTS:
			var a0 := TAU * i / SEGMENTS
			var a1 := TAU * (i + 1) / SEGMENTS
			var ww: float = w * side
			if side > 0.0:
				_quad(st, _p(a0, r0, ww, axis), _p(a0, r1, ww, axis), _p(a1, r1, ww, axis), _p(a1, r0, ww, axis))
			else:
				_quad(st, _p(a0, r0, ww, axis), _p(a1, r0, ww, axis), _p(a1, r1, ww, axis), _p(a0, r1, ww, axis))


## A tread block: from angle a0 to a1, radius r0 (carcass) to r1, z0..z1 across.
static func _block(st: SurfaceTool, a0: float, a1: float, r0: float, r1: float, z0: float, z1: float, axis: String) -> void:
	var c := [_p(a0, r1, z0, axis), _p(a1, r1, z0, axis), _p(a1, r1, z1, axis), _p(a0, r1, z1, axis)]
	var f := [_p(a0, r0, z0, axis), _p(a1, r0, z0, axis), _p(a1, r0, z1, axis), _p(a0, r0, z1, axis)]
	_quad(st, c[0], c[1], c[2], c[3])                        # the top
	_quad(st, f[0], f[1], c[1], c[0])                        # the sides
	_quad(st, f[1], f[2], c[2], c[1])
	_quad(st, f[2], f[3], c[3], c[2])
	_quad(st, f[3], f[0], c[0], c[3])


## A spoke: a tapered bar from the hub (r0) to the barrel (r1), w0 / w1 wide, at
## the face, `deep` thick toward the car.
static func _spoke(st: SurfaceTool, a: float, r0: float, r1: float, w0: float, w1: float, face: float, deep: float,
		axis: String) -> void:
	var d0 := w0 / r0 * 0.5
	var d1 := w1 / r1 * 0.5
	for side in [1.0, -1.0]:
		var f: float = face * side
		var b: float = (face - deep) * side
		var o := [_p(a - d0, r0, f, axis), _p(a + d0, r0, f, axis), _p(a + d1, r1, f, axis), _p(a - d1, r1, f, axis)]
		var i := [_p(a - d0, r0, b, axis), _p(a + d0, r0, b, axis), _p(a + d1, r1, b, axis), _p(a - d1, r1, b, axis)]
		if side > 0.0:
			_quad(st, o[0], o[3], o[2], o[1])
		else:
			_quad(st, o[0], o[1], o[2], o[3])
		_quad(st, i[0], o[0], o[1], i[1])
		_quad(st, i[1], o[1], o[2], i[2])
		_quad(st, i[2], o[2], o[3], i[3])
		_quad(st, i[3], o[3], o[0], i[0])


## The lock nut: a hexagonal boss on the hub.
static func _nut(st: SurfaceTool, r: float, w: float, h: float, axis: String) -> void:
	for side in [1.0, -1.0]:
		var w0: float = w * side
		var w1: float = (w + h) * side
		for i in 6:
			var a0 := TAU * i / 6.0
			var a1 := TAU * (i + 1) / 6.0
			_quad(st, _p(a0, r, w0, axis), _p(a1, r, w0, axis), _p(a1, r, w1, axis), _p(a0, r, w1, axis))
			if side > 0.0:
				_tri(st, _p(0.0, 0.0, w1, axis), _p(a1, r, w1, axis), _p(a0, r, w1, axis))
			else:
				_tri(st, _p(0.0, 0.0, w1, axis), _p(a0, r, w1, axis), _p(a1, r, w1, axis))
