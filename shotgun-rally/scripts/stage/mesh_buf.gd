extends RefCounted
## A flat-shaded, vertex-coloured triangle soup (the low-poly look: every face
## its own normal), plus the triangles for a ConcavePolygonShape3D if asked.

const SOFT_SATURATION := 0.88        # x the colours' saturation
const SOFT_LIFT := 0.03               # their brightness, this much of the way to white

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var faces := PackedVector3Array()     # collision triangles


func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, collide := false) -> void:
	col = soft(col)
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if n.y < 0.0 and absf(n.y) > 0.2:   # ground faces always face up
		var t := b
		b = c
		c = t
		n = -n
	# Godot's front faces wind clockwise seen from the front
	verts.append_array([a, c, b])
	norms.append_array([n, n, n])
	cols.append_array([col, col, col])
	if collide:
		faces.append_array([a, c, b])


## Quad a-b-c-d (in order round the edge).
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, collide := false) -> void:
	tri(a, b, c, col, collide)
	tri(a, c, d, col, collide)


## A triangle that keeps the winding it's given (for upright things: trunks, banners).
func tri_raw(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	col = soft(col)
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = -n.normalized()
	verts.append_array([a, b, c])
	norms.append_array([n, n, n])
	cols.append_array([col, col, col])


func is_empty() -> bool:
	return verts.is_empty()


## The mesh; smooth: the normals averaged where faces meet (the realistic look's ground
## and road: no facets), except across a fold sharper than ~50 degrees.
func mesh(smooth := false) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = smooth_normals() if smooth else norms
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	if not verts.is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Each corner's normal: the faces meeting at that point (the very same Vector3: the
## builders reuse a row's points) within ~50 degrees of this face, weighted by their area.
func smooth_normals() -> PackedVector3Array:
	var acc := {}                                     # point -> [face index, ...]
	var weight := PackedFloat32Array()
	weight.resize(verts.size() / 3)
	for i in range(0, verts.size(), 3):
		weight[i / 3] = (verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i]).length()
		for k in 3:
			var v: Vector3 = verts[i + k]
			if not acc.has(v):
				acc[v] = []
			acc[v].append(i)
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in verts.size():
		var fn: Vector3 = norms[i]
		var s := Vector3.ZERO
		for f in acc[verts[i]]:
			if norms[f].dot(fn) > 0.64:
				s += norms[f] * weight[f / 3]
		out[i] = s.normalized() if s.length_squared() > 1e-12 else fn
	return out


func shape() -> ConcavePolygonShape3D:
	var s := ConcavePolygonShape3D.new()
	s.set_faces(faces)
	s.backface_collision = true
	return s


## The world's colours, softened: a little less saturated, a little lighter
## (the flat-colour cartoon look; the cars stay realistic).
static func soft(c: Color) -> Color:
	var s := Color.from_hsv(c.h, c.s * SOFT_SATURATION, lerpf(c.v, 1.0, SOFT_LIFT), c.a)
	return s


## A shared vertex-colour material: matte, lit, shadows; soft light (the diffuse
## wraps round, no highlights): the flat-colour cartoon look.
static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true        # the colours are written as sRGB, like albedo_color
	m.roughness = 1.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m
