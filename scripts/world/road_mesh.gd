extends RefCounted
## Tiny procedural mesh writer for roads, decks, walls and terrain: flat-shaded
## vertex-colored quads (one shared material, so everything batches) plus an
## optional list of collision triangles for a ConcavePolygonShape3D.

var st := SurfaceTool.new()
var faces := PackedVector3Array()     # collision triangles
var count := 0
var uvs := false                      # set before the first quad: every vertex gets a UV (quad_uv; plain quads get 0, 0)


func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


## Quad a-b-c-d (any winding); `up` says which side it faces. Adds collision if asked.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, up: Vector3, collide := false) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		n = (c - a).cross(d - a)
	# Godot's front faces wind clockwise: the geometric normal of a front face
	# (b-a)x(c-a) points away from the viewer.
	if n.dot(up) > 0.0:
		var t := b
		b = d
		d = t
	var nn := up.normalized()
	st.set_color(col)
	st.set_normal(nn)
	if uvs:
		st.set_uv(Vector2.ZERO)
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)
	count += 1
	if collide:
		faces.append_array(PackedVector3Array([a, b, c, a, c, d]))


## Textured quad (needs `uvs = true`): ua..ud are the corners' UVs.
func quad_uv(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2,
		col: Color, up: Vector3, collide := false) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(up) > 0.0:
		var t := b
		b = d
		d = t
		var tu := ub
		ub = ud
		ud = tu
	st.set_color(col)
	st.set_normal(up.normalized())
	var vs := [a, b, c, a, c, d]
	var us := [ua, ub, uc, ua, uc, ud]
	for i in 6:
		st.set_uv(us[i])
		st.add_vertex(vs[i])
	count += 1
	if collide:
		faces.append_array(PackedVector3Array([a, b, c, a, c, d]))


func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, up: Vector3, collide := false) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(up) > 0.0:
		var t := b
		b = c
		c = t
	st.set_color(col)
	st.set_normal(up.normalized())
	if uvs:
		st.set_uv(Vector2.ZERO)
	for v in [a, b, c]:
		st.add_vertex(v)
	if collide:
		faces.append_array(PackedVector3Array([a, b, c]))


## Axis-aligned box (all 6 faces).
func box(center: Vector3, size: Vector3, col: Color, collide := false, top_col = null) -> void:
	var h := size / 2.0
	var p := func(x: float, y: float, z: float) -> Vector3:
		return center + Vector3(x * h.x, y * h.y, z * h.z)
	var tc: Color = top_col if top_col != null else col
	quad(p.call(-1, 1, -1), p.call(1, 1, -1), p.call(1, 1, 1), p.call(-1, 1, 1), tc, Vector3.UP, collide)
	quad(p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, -1, 1), p.call(-1, -1, 1), col.darkened(0.3), Vector3.DOWN, collide)
	quad(p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1), col, Vector3.BACK, collide)
	quad(p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, 1, -1), p.call(-1, 1, -1), col, Vector3.FORWARD, collide)
	quad(p.call(1, -1, -1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(1, 1, -1), col, Vector3.RIGHT, collide)
	quad(p.call(-1, -1, -1), p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1), col, Vector3.LEFT, collide)


## An oriented box given its bottom-center, forward (length) axis and size.
func obox(base: Vector3, fwd: Vector3, size: Vector3, col: Color, collide := false) -> void:
	var f := Vector3(fwd.x, 0, fwd.z).normalized() * size.z / 2.0
	var r := f.cross(Vector3.UP).normalized() * size.x / 2.0
	var u := Vector3(0, size.y, 0)
	var c := [base - f - r, base + f - r, base + f + r, base - f + r]
	quad(c[0] + u, c[1] + u, c[2] + u, c[3] + u, col, Vector3.UP, collide)
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		var out := ((a + b) / 2.0 - base)
		out.y = 0
		quad(a, b, b + u, a + u, col, out, collide)


func commit(mat: Material) -> ArrayMesh:
	var m := st.commit()
	if m.get_surface_count() > 0:
		m.surface_set_material(0, mat)
	return m


func empty() -> bool:
	return count == 0


## A 4-sided bar from a to b (pipes, rails, arms, braces): `w` wide, `h` tall.
func bar(a: Vector3, b: Vector3, w: float, h: float, col: Color, collide := false) -> void:
	var f := (b - a).normalized()
	var side := f.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = Vector3.RIGHT
	side = side.normalized() * (w / 2.0)
	var up := side.cross(f).normalized() * (h / 2.0)
	if up.y < 0.0:
		up = -up
	var q := [side + up, -side + up, -side - up, side - up]
	for i in 4:
		var p0: Vector3 = q[i]
		var p1: Vector3 = q[(i + 1) % 4]
		quad(a + p0, b + p0, b + p1, a + p1, col if i != 2 else col.darkened(0.2), (p0 + p1).normalized(), collide)


## A MeshInstance3D (+ a static body from the collision faces, if any) under parent.
func instance(parent: Node3D, mat: Material, nm := "Road", vis_end := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = commit(mat)
	mi.material_override = mat
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
		mi.visibility_range_end_margin = vis_end * 0.1
	parent.add_child(mi)
	if not faces.is_empty():
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := ConcavePolygonShape3D.new()
		sh.backface_collision = true
		sh.set_faces(faces)
		cs.shape = sh
		sb.add_child(cs)
		parent.add_child(sb)
	return mi
