extends RefCounted
## Geometry for one material: triangles with normals, UVs in metres (a texture
## repeats every metre of it: the materials scale it), a colour per vertex (a tint
## the materials can use) and, if asked, the triangles for a collision shape.
## Unlike MeshBuf (the rally stages' flat-shaded cartoon look) it shades
## smoothly where it's given normals, for real materials (scripts/render/).

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var uvs := PackedVector2Array()
var cols := PackedColorArray()
var faces := PackedVector3Array()     # collision triangles


func is_empty() -> bool:
	return verts.is_empty()


## A triangle, its normal from its winding (counter-clockwise seen from the front).
func tri(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, col := Color.WHITE, collide := false) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	_add(a, c, b, n, n, n, ua, uc, ub, col, col, col)
	if collide:
		faces.append_array([a, c, b])


## A quad a-b-c-d counter-clockwise seen from the front, flat.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2,
		col := Color.WHITE, collide := false) -> void:
	tri(a, b, c, ua, ub, uc, col, collide)
	tri(a, c, d, ua, uc, ud, col, collide)


## A quad with its own normals at the corners (smooth shading across a strip).
func quad_n(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, col := Color.WHITE, collide := false, col2 = null) -> void:
	var cb: Color = col2 if col2 != null else col
	_add(a, c, b, na, nc, nb, ua, uc, ub, col, cb, cb)
	_add(a, d, c, na, nd, nc, ua, ud, uc, col, col, cb)
	if collide:
		faces.append_array([a, c, b, a, d, c])


## A ribbon between two rows of points (row a, then row b further along), each a
## cross-section left to right; normals are each face's, averaged at the points.
## u along (given per row), v across (each point's own, in m). Faces up/out for
## rows running forward with points left to right.
func ribbon(ra: PackedVector3Array, rb: PackedVector3Array, ua: float, ub: float, va: PackedFloat32Array,
		col := Color.WHITE, collide := false, cols_a := PackedColorArray(), cols_b := PackedColorArray()) -> void:
	var m := ra.size()
	var na := PackedVector3Array()
	var nb := PackedVector3Array()
	na.resize(m)
	nb.resize(m)
	for k in m - 1:
		var n := (ra[k + 1] - ra[k]).cross(rb[k] - ra[k])      # (right x forward: up)
		if n.length_squared() < 1e-14:
			n = Vector3.UP
		n = n.normalized()
		na[k] += n
		na[k + 1] += n
		nb[k] += n
		nb[k + 1] += n
	for k in m:
		na[k] = na[k].normalized() if na[k].length_squared() > 1e-12 else Vector3.UP
		nb[k] = nb[k].normalized() if nb[k].length_squared() > 1e-12 else Vector3.UP
	for k in m - 1:
		var c0 := cols_a[k] if not cols_a.is_empty() else col
		var c1 := cols_a[k + 1] if not cols_a.is_empty() else col
		var c2 := cols_b[k + 1] if not cols_b.is_empty() else col
		var c3 := cols_b[k] if not cols_b.is_empty() else col
		# a = ra[k], b = ra[k+1], c = rb[k+1], d = rb[k]: seen from above, counter-clockwise
		_add(ra[k], rb[k + 1], ra[k + 1], na[k], nb[k + 1], na[k + 1],
			Vector2(ua, va[k]), Vector2(ub, va[k + 1]), Vector2(ua, va[k + 1]), c0, c2, c1)
		_add(ra[k], rb[k], rb[k + 1], na[k], nb[k], nb[k + 1],
			Vector2(ua, va[k]), Vector2(ub, va[k]), Vector2(ub, va[k + 1]), c0, c3, c2)
		if collide:
			faces.append_array([ra[k], rb[k + 1], ra[k + 1], ra[k], rb[k], rb[k + 1]])


## A box (an axis-aligned one, turned by `basis`, its middle at `at`), flat faces;
## UVs in metres on each face.
func box(at: Vector3, size: Vector3, basis := Basis(), col := Color.WHITE, collide := false) -> void:
	var h := size * 0.5
	var c := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var p := []
	for v in c:
		p.append(at + basis * v)
	var fs := [[4, 5, 6, 7, size.x, size.y], [1, 0, 3, 2, size.x, size.y], [0, 4, 7, 3, size.z, size.y],
		[5, 1, 2, 6, size.z, size.y], [7, 6, 2, 3, size.x, size.z], [0, 1, 5, 4, size.x, size.z]]
	for f in fs:
		quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], Vector2(0, 0), Vector2(f[4], 0), Vector2(f[4], f[5]), Vector2(0, f[5]), col, collide)


## A tube (a cable, a pole) along the points, `sides` sided, radius r.
func tube(path: PackedVector3Array, r: float, sides := 6, col := Color.WHITE) -> void:
	var u := 0.0
	for k in path.size() - 1:
		var a := path[k]
		var b := path[k + 1]
		var ax := (b - a).normalized()
		var side := ax.cross(Vector3.UP)
		if side.length_squared() < 1e-6:
			side = ax.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(ax).normalized()
		var l := a.distance_to(b)
		for j in sides:
			var t0 := TAU * j / sides
			var t1 := TAU * (j + 1) / sides
			var o0 := (side * cos(t0) + up * sin(t0))
			var o1 := (side * cos(t1) + up * sin(t1))
			quad_n(a + o0 * r, b + o0 * r, b + o1 * r, a + o1 * r, o0, o0, o1, o1,
				Vector2(u, 0), Vector2(u + l, 0), Vector2(u + l, 1), Vector2(u, 1), col)
		u += l


func _add(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ca: Color, cb: Color, cc: Color) -> void:
	verts.append_array([a, b, c])
	norms.append_array([na, nb, nc])
	uvs.append_array([ua, ub, uc])
	cols.append_array([ca, cb, cc])


func mesh() -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	if not verts.is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func shape() -> ConcavePolygonShape3D:
	var s := ConcavePolygonShape3D.new()
	s.set_faces(faces)
	s.backface_collision = true
	return s
