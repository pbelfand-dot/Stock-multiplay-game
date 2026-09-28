extends RefCounted
## Office props modeled in Blender (tools/blender/build_props.py -> props_kit.glb):
## desks, CRTs, chairs, slots, elevator, windows, skyline towers...
## Each prop is split into single-surface meshes that share a handful of
## materials (Paint/Gloss/Metal/Glow), so Batcher.merge_static collapses the
## whole office into a few draw calls.

const KIT_PATH := "res://assets/props/props_kit.glb"
## Every kit loaded into the same prop table (names are unique across kits).
const KITS := [KIT_PATH, "res://assets/props/watches_kit.glb"]   # watches: tools/blender/build_watches.py

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
		"Glass":   # watch crystals, vitrine panes: see-through with a glint
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(1, 1, 1, 0.14)
			m.roughness = 0.05
			m.metallic_specular = 1.0
	_mats[kind] = m
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
			list.append([st.commit(), material(kind)])
		_parts[str(mi.name)] = list
	inst.free()


## The first surface mesh of a prop (e.g. for particle meshes).
static func mesh(prop: String) -> Mesh:
	if _parts.is_empty():
		_load()
	var parts: Array = _parts.get(prop, [])
	return parts[0][0] if not parts.is_empty() else null


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
static func place_detail(prop: String, parent: Node, pos := Vector3.ZERO, rot := Vector3.ZERO, near := 9.0) -> Node3D:
	var n := place(prop, parent, pos, rot.y)
	n.rotation = rot
	for mi in n.get_children():
		if mi is MeshInstance3D:
			mi.set_meta("no_batch", true)
			mi.visibility_range_end = near
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n
