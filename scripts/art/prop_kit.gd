extends RefCounted
## Office props modeled in Blender (tools/blender/build_props.py -> props_kit.glb):
## desks, CRTs, chairs, slots, elevator, windows, skyline towers...
## Each prop is split into single-surface meshes that share a handful of
## materials (Paint/Gloss/Metal/Glow), so Batcher.merge_static collapses the
## whole office into a few draw calls.

const KIT_PATH := "res://assets/props/props_kit.glb"
## Every kit loaded into the same prop table (names are unique across kits).
const KITS := [KIT_PATH, "res://assets/props/watches_kit.glb",   # watches: tools/blender/build_watches.py
	"res://assets/props/houses_kit.glb", "res://assets/props/cars_kit.glb",   # ---- neighborhood (houses): build_houses.py / build_cars.py ----
	"res://assets/props/bemze_kit.glb",                               # cars + dealership: tools/blender/build_bemze.py
	"res://assets/props/realcars_kit.glb"]                            # the owner's real BEMZE models: build_realcars.py

const HAZE_COLOR := Color(0.64, 0.78, 0.94)   # the sky; far towers fade into it

static var _parts := {}   # prop name -> Array of [ArrayMesh, Material]
static var _hazed := {}   # "prop@haze" -> same, with vertex colors pushed toward the sky
static var _mats := {}


static func material(kind: String) -> StandardMaterial3D:
	if _mats.has(kind):
		return _mats[kind]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true   # colors are baked (sRGB values, used as-is)
	m.roughness = 0.85
	m.metallic_specular = 0.35
	match kind:
		"Gloss":
			m.roughness = 0.3
			m.metallic_specular = 0.7
		"Metal":   # mostly specular: full metallic goes black with no sky to reflect
			m.metallic = 0.2
			m.roughness = 0.35
			m.metallic_specular = 0.8
		"Glow":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"CarPaint":   # car body: white vertex colors, tint with albedo_color on a duplicate
			m.roughness = 0.2
			m.metallic = 0.35
			m.metallic_specular = 0.9
		"Glass":   # watch crystals, vitrine panes: see-through with a glint
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(1, 1, 1, 0.14)
			m.roughness = 0.05
			m.metallic_specular = 1.0
		"CarGlass":   # the traffic kit's windows (see _kit_car_windows): a light smoky tint, like RC_Glass
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.vertex_color_use_as_albedo = false
			m.albedo_color = Color(0.14, 0.17, 0.21, 0.32)
			m.roughness = 0.05
			m.metallic_specular = 1.0
	_mats[kind] = m
	return m


## A real-car material (build_realcars.py): the imported textures (atlas: albedo, metal/rough, emission),
## times the vertex colours (sRGB) that tint the plain parts. RC_Glass: see-through, both sides.
## RC_<car>_Tail is the brake-light surface (car.gd brightens a copy of it on the brakes).
static func real_material(src: Material) -> Material:
	var key := src.resource_name.get_slice(".", 0)
	if _mats.has(key):
		return _mats[key]
	var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(1, 1, 1, 1)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if key == "RC_Glass":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.metallic = 0.0
		m.roughness = 0.05
		m.metallic_specular = 1.0
	else:
		m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		m.metallic_specular = 0.5
		if m.emission_enabled:
			m.emission_energy_multiplier = 0.6 if key.ends_with("_Tail") else 1.6
	m.resource_name = key
	_mats[key] = m
	return m


static func _load() -> void:
	for path in KITS:
		_load_kit(path)


static func _load_kit(path: String) -> void:
	var scene: PackedScene = load(path)
	if scene == null:
		return
	var inst: Node = scene.instantiate()
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var list: Array = []
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var st := SurfaceTool.new()
			st.append_from(mesh, s, mi.transform)
			var src := mesh.surface_get_material(s)
			var kind := src.resource_name.get_slice(".", 0) if src else "Paint"
			list.append([st.commit(), real_material(src) if kind.begins_with("RC_") else material(kind)])
		if path.ends_with("cars_kit.glb") and str(mi.name).begins_with("TCar_"):
			list = _kit_car_windows(list)
		_parts[str(mi.name)] = list
	inst.free()


const KIT_GLASS := Color(0.1, 0.13, 0.17)       # tools/blender/build_cars.py GLASS: the greenhouse's colour


## The traffic kit's cars (build_cars.py: the beater, the cabs, all the
## traffic) were built with a solid dark greenhouse. Split those faces out of
## the Gloss surface as see-through tinted glass, and put what you'd see
## through it behind: seat backs and headrests (front row, a rear bench when
## the cabin's long enough) and the top of the dash. One more surface per car
## (the glass); the interior joins the Paint one.
static func _kit_car_windows(list: Array) -> Array:
	var gi := -1
	for i in list.size():
		if list[i][1] == material("Gloss"):
			gi = i
	if gi < 0:
		return list
	var arr := (list[gi][0] as ArrayMesh).surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var col: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
	if col.size() != v.size():
		return list
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := AABB()
	var n_glass := 0
	var is_glass := func(c: Color) -> bool:
		return absf(c.r - KIT_GLASS.r) + absf(c.g - KIT_GLASS.g) + absf(c.b - KIT_GLASS.b) < 0.03
	var tri_glass: Array = []
	for t in range(0, idx.size() - 2, 3):
		var g: bool = is_glass.call(col[idx[t]]) and is_glass.call(col[idx[t + 1]]) and is_glass.call(col[idx[t + 2]])
		tri_glass.append(g)
		if g:
			for k in 3:
				box = AABB(v[idx[t + k]], Vector3.ZERO) if n_glass == 0 else box.expand(v[idx[t + k]])
				n_glass += 1
	if n_glass == 0:
		return list
	for t in range(0, idx.size() - 2, 3):
		var g: bool = tri_glass[t / 3]
		if not g:
			# the B-pillar is a body-coloured slab right across the cabin: keep its ends (the
			# pillars), drop its front and back faces so you can see through the car
			var across := true
			for k in 3:
				var q := v[idx[t + k]]
				if absf(nrm[idx[t + k]].z) < 0.9 or q.y < box.position.y + 0.005 or q.y > box.end.y - 0.005 \
						or q.z < box.position.z or q.z > box.end.z:
					across = false
			if across:
				continue
		var st := glass if g else body
		for k in 3:
			var i := idx[t + k]
			st.set_normal(nrm[i])
			st.set_color(col[i])
			st.add_vertex(v[i])
	var out := list.duplicate()
	out[gi] = [body.commit(), material("Gloss")]
	out.append([glass.commit(), material("CarGlass")])
	# the cabin behind the glass (the kit's nose is +z): seats, headrests, dash (into the Paint surface)
	var pi := -1
	for i in out.size():
		if out[i][1] == material("Paint"):
			pi = i
	var inside := SurfaceTool.new()
	inside.begin(Mesh.PRIMITIVE_TRIANGLES)
	if pi >= 0:
		_tris_into(inside, out[pi][0])
	var belt := box.position.y
	var z0 := box.position.z
	var z1 := box.end.z
	var lg := box.size.z
	var xw := box.size.x / 2.0 - 0.06
	var roof := box.end.y - 0.08
	var seat := Color(0.13, 0.13, 0.14)
	var dash := Color(0.08, 0.08, 0.09)
	var zf := z1 - 0.62 * lg
	for sx in [-1.0, 1.0]:
		_kit_box(inside, Vector3(sx * xw * 0.5, belt + 0.1, zf), Vector3(xw * 0.78, 0.5, 0.12), seat)
		_kit_box(inside, Vector3(sx * xw * 0.5, minf(belt + 0.45, roof - 0.09), zf - 0.02), Vector3(0.26, 0.17, 0.1), seat)
	if lg > 2.2:
		var zr := z0 + 0.32
		_kit_box(inside, Vector3(0, belt + 0.06, zr), Vector3(xw * 1.8, 0.42, 0.14), seat)
		for sx in [-1.0, 1.0]:
			_kit_box(inside, Vector3(sx * xw * 0.5, minf(belt + 0.36, roof - 0.08), zr - 0.02), Vector3(0.24, 0.14, 0.1), seat)
	_kit_box(inside, Vector3(0, belt + 0.02, z1 - 0.42), Vector3(xw * 1.95, 0.12, 0.32), dash)
	if pi >= 0:
		out[pi] = [inside.commit(), material("Paint")]
	else:
		out.append([inside.commit(), material("Paint")])
	return out


## Every triangle of a (vertex-coloured) mesh's first surface into a SurfaceTool, unindexed.
static func _tris_into(st: SurfaceTool, m: ArrayMesh) -> void:
	var arr := m.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var col: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
	for i in idx:
		st.set_normal(nrm[i])
		st.set_color(col[i] if i < col.size() else Color.WHITE)
		st.add_vertex(v[i])


## An axis-aligned box (center c, size sz) of one colour into a SurfaceTool.
static func _kit_box(st: SurfaceTool, c: Vector3, sz: Vector3, color: Color) -> void:
	var h := sz / 2.0
	for f in [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
			[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
			[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]:
		var n: Vector3 = f[0]
		var a: Vector3 = f[1]
		var b: Vector3 = f[2]
		var o := c + n * h
		var ea := a * h
		var eb := b * h
		var q := [o - ea - eb, o + ea - eb, o + ea + eb, o - ea + eb]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n)
			st.set_color(color)
			st.add_vertex(q[k])


## The first surface mesh of a prop (e.g. for particle meshes).
static func mesh(prop: String) -> Mesh:
	if _parts.is_empty():
		_load()
	var parts: Array = _parts.get(prop, [])
	return parts[0][0] if not parts.is_empty() else null


## A prop's surfaces as loaded: [[ArrayMesh, Material], ...] (to derive a variant from; don't edit them).
static func parts(prop: String) -> Array:
	if _parts.is_empty():
		_load()
	return _parts.get(prop, [])


static func has(prop: String) -> bool:
	if _parts.is_empty():
		_load()
	return _parts.has(prop)


static func _parts_for(prop: String, haze: float) -> Array:
	haze = snappedf(clampf(haze, 0.0, 0.9), 0.1)
	if haze <= 0.0:
		return _parts.get(prop, [])
	var key := "%s@%.1f" % [prop, haze]
	if not _hazed.has(key):
		var sky := HAZE_COLOR
		var list: Array = []
		for part in _parts.get(prop, []):
			var arr: Array = part[0].surface_get_arrays(0)
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			for i in cols.size():
				cols[i] = cols[i].lerp(sky, haze)
			arr[Mesh.ARRAY_COLOR] = cols
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			list.append([am, part[1]])
		_hazed[key] = list
	return _hazed[key]


## Instance a prop under `parent`. Its origin/front conventions are documented
## per prop in build_props.py (front = +Z). `haze` (0..0.9) fades it toward the
## sky color — aerial perspective for the skyline without renderer fog.
static func place(prop: String, parent: Node, pos := Vector3.ZERO, rot_y := 0.0, scl := 1.0, haze := 0.0) -> Node3D:
	if _parts.is_empty():
		_load()
	var n := Node3D.new()
	n.name = prop
	n.position = pos
	n.rotation.y = rot_y
	n.scale = Vector3.ONE * scl
	for part in _parts_for(prop, haze):
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.material_override = part[1]
		n.add_child(mi)
	if not _parts.has(prop):
		push_error("props kit has no '%s'" % prop)
	parent.add_child(n)
	return n


## A small, dense prop (a watch): kept out of the static batch and only drawn
## within `near` metres, so a store full of them costs nothing from the street.
static func place_detail(prop: String, parent: Node, pos := Vector3.ZERO, rot := Vector3.ZERO, near := -1.0) -> Node3D:
	if near < 0.0:
		near = Graphics.cur.detail      # the graphics preset decides how far detail draws
	var n := place(prop, parent, pos, rot.y)
	n.rotation = rot
	for mi in n.get_children():
		if mi is MeshInstance3D:
			mi.set_meta("no_batch", true)
			mi.visibility_range_end = near
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n
