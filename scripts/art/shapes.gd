extends RefCounted
## Procedural smooth meshes + cartoon materials used by the characters.
##
## superellipsoid(rx, ry, rz, n): n=2 → ellipsoid, n≈3 → soft rounded box,
## n=4+ → boxy. Optional taper scales X/Z from bottom (y=-ry) to top (y=+ry).
## Meshes and materials are cached, so building many characters is cheap.

static var _mesh_cache := {}
static var _mat_cache := {}
static var _outline: StandardMaterial3D
static var _stripe_tex := {}


static func _spow(v: float, e: float) -> float:
	return signf(v) * pow(absf(v), e)


static func superellipsoid(rx: float, ry: float, rz: float, n: float = 2.0,
		taper_bottom: float = 1.0, taper_top: float = 1.0, lat: int = 14, lon: int = 20) -> ArrayMesh:
	var key := "se_%.3f_%.3f_%.3f_%.2f_%.2f_%.2f_%d_%d" % [rx, ry, rz, n, taper_bottom, taper_top, lat, lon]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var e := 2.0 / n
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in lat + 1:
		var th := -PI / 2 + PI * float(i) / lat
		var ct := cos(th)
		var st := sin(th)
		var yf := _spow(st, e)
		var taper := lerpf(taper_bottom, taper_top, (yf + 1.0) * 0.5)
		for j in lon + 1:
			var ph := -PI + TAU * float(j) / lon
			var cp := cos(ph)
			var sp := sin(ph)
			var x := rx * _spow(ct, e) * _spow(cp, e) * taper
			var y := ry * yf
			var z := rz * _spow(ct, e) * _spow(sp, e) * taper
			verts.append(Vector3(x, y, z))
			var nx := _spow(ct, 2.0 - e) * _spow(cp, 2.0 - e) / rx
			var ny := _spow(st, 2.0 - e) / ry
			var nz := _spow(ct, 2.0 - e) * _spow(sp, 2.0 - e) / rz
			var nv := Vector3(nx, ny, nz)
			norms.append(nv.normalized() if nv.length() > 0.00001 else Vector3(0, signf(st), 0))
			uvs.append(Vector2(float(j) / lon, 1.0 - float(i) / lat))
	for i in lat:
		for j in lon:
			var a := i * (lon + 1) + j
			var b := a + lon + 1
			idx.append_array([a, a + 1, b, a + 1, b + 1, b])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mesh_cache[key] = m
	return m


## Flat triangle plate (for the shirt V / lapels), pointing down, in XY plane.
static func tri_plate(w: float, h: float, depth: float = 0.01) -> ArrayMesh:
	var key := "tri_%.3f_%.3f_%.3f" % [w, h, depth]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-w / 2, h / 2, 0)
	var b := Vector3(w / 2, h / 2, 0)
	var c := Vector3(0, -h / 2, 0)
	var off := Vector3(0, 0, depth)
	st.set_normal(Vector3(0, 0, -1))
	for v in [a, c, b]:
		st.add_vertex(v)
	st.set_normal(Vector3(0, 0, 1))
	for v in [a + off, b + off, c + off]:
		st.add_vertex(v)
	var m := st.commit()
	_mesh_cache[key] = m
	return m


static func outline_mat() -> StandardMaterial3D:
	if _outline == null:
		_outline = StandardMaterial3D.new()
		_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline.albedo_color = Color(0.08, 0.07, 0.09)
		_outline.cull_mode = BaseMaterial3D.CULL_FRONT
		_outline.grow = true
		_outline.grow_amount = 0.0045
	return _outline


## Matte cartoon material. outline=true adds an inverted-hull outline pass.
## Outlines are off by default: the trailer's look is soft cel shading
## without ink lines. Flip OUTLINES to true for a comic look.
const OUTLINES := false


static func mat(c: Color, outline := true, emissive := 0.0) -> StandardMaterial3D:
	outline = outline and OUTLINES
	var key := "%s_%s_%s" % [c.to_html(), outline, emissive]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	m.metallic_specular = 0.25
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	if outline:
		m.next_pass = outline_mat()
	_mat_cache[key] = m
	return m


## Pinstripe fabric: base color with thin light vertical stripes.
static func pinstripe(c: Color, stripes: float = 22.0) -> StandardMaterial3D:
	var key := "pin_%s_%.1f" % [c.to_html(), stripes]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var img := Image.create(64, 8, false, Image.FORMAT_RGB8)
	img.fill(c)
	var line := c.lightened(0.16)
	for y in 8:
		img.set_pixel(0, y, line)
	var tex := ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.uv1_scale = Vector3(stripes, 1, 1)
	m.roughness = 0.9
	m.metallic_specular = 0.25
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if OUTLINES:
		m.next_pass = outline_mat()
	_mat_cache[key] = m
	return m


static func part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO,
		rot: Vector3 = Vector3.ZERO, part_name: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	if part_name != "":
		mi.name = part_name
	parent.add_child(mi)
	return mi


static func joint(parent: Node3D, pos: Vector3, joint_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = joint_name
	n.position = pos
	parent.add_child(n)
	return n
