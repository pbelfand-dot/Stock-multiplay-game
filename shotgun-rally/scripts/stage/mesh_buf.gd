extends RefCounted
## A flat-shaded, vertex-coloured triangle soup (the low-poly look: every face
## its own normal), plus the triangles for a ConcavePolygonShape3D if asked.

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var faces := PackedVector3Array()     # collision triangles


func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, collide := false) -> void:
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
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = -n.normalized()
	verts.append_array([a, b, c])
	norms.append_array([n, n, n])
	cols.append_array([col, col, col])


func is_empty() -> bool:
	return verts.is_empty()


func mesh() -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
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


## A shared vertex-colour material: matte, lit, shadows.
static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true        # the colours are written as sRGB, like albedo_color
	m.roughness = 1.0
	m.metallic_specular = 0.2
	return m
