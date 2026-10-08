extends RefCounted
## The converted environment library (assets/environment_runtime/, made by
## tools/import_environment.py from the owner's packs and the CC0 sets), for the stage builders.
## Static: `const EnvAssets = preload("res://scripts/stage/env_assets.gd")`.
##
##   EnvAssets.available() -> bool: the library is in the build (a missing file: the builders fall
##     back to their procedural trees, rocks and props)
##   EnvAssets.info(id) -> Dictionary: an asset's entry in data/environment_assets.json (glb, part,
##     kind, height, radius, trunk, tags...)
##   EnvAssets.ids(kind, tag = "") -> Array: the assets of a kind ("tree", "rock", "cliff", "prop",
##     "building", "skyline": the city's far tier, scripts/stage/city_skyline.gd), with the tag if given
##   EnvAssets.building(material, night) -> Material: a building's (its facade, lit windows at night)
##   EnvAssets.mesh(id, lod = "", tint = white) -> Mesh: an asset's mesh ("" its only one; a tree's
##     "LOD0", "LOD1" or "BB"; a far-tier building's "LOD1"), the materials made right for the game (leaves: cut out, both sides,
##     the sun through them, times the tint: a season's colour; see foliage()); cached
## Meshes come out of the GLBs by part name (a node of each part in the GLB, made by the
## converter); each GLB is loaded once.

const DATA := "res://data/environment_assets.json"

static var _data: Dictionary = {}
static var _scenes: Dictionary = {}          # glb path -> {part name: Mesh}
static var _meshes: Dictionary = {}          # "id/lod" -> Mesh (materials set)
static var _mats: Dictionary = {}            # source material -> the game's


static func _load() -> void:
	if not _data.is_empty():
		return
	var f := FileAccess.open(DATA, FileAccess.READ)
	if f == null:
		_data = {"assets": {}}
		return
	var d = JSON.parse_string(f.get_as_text())
	_data = d if d is Dictionary else {"assets": {}}


static func available() -> bool:
	_load()
	return not (_data.get("assets", {}) as Dictionary).is_empty()


static func info(id: String) -> Dictionary:
	_load()
	return _data.get("assets", {}).get(id, {})


static func ids(kind: String, tag := "") -> Array:
	_load()
	var out: Array = []
	var all: Dictionary = _data.get("assets", {})
	for id in all:
		var a: Dictionary = all[id]
		if str(a.get("kind", "")) == kind and (tag == "" or tag in a.get("tags", [])):
			out.append(id)
	out.sort()
	return out


static func _parts(glb: String) -> Dictionary:
	if _scenes.has(glb):
		return _scenes[glb]
	var parts := {}
	if ResourceLoader.exists(glb):
		var ps = load(glb)
		if ps is PackedScene:
			var root: Node = (ps as PackedScene).instantiate()
			for n in root.find_children("*", "MeshInstance3D", true, false):
				parts[String(n.name)] = (n as MeshInstance3D).mesh
			root.free()
	_scenes[glb] = parts
	return parts


static func mesh(id: String, lod := "", tint := Color.WHITE) -> Mesh:
	var key := id + "/" + lod + ("" if tint == Color.WHITE else "/" + tint.to_html())
	if _meshes.has(key):
		return _meshes[key]
	var a := info(id)
	if a.is_empty():
		return null
	var part: String = str(a.get("part", id)) + ("_" + lod if lod != "" else "")
	var src: Mesh = _parts(str(a.get("glb", ""))).get(part)
	if src == null:
		_meshes[key] = null
		return null
	var m: Mesh = src
	if str(a.get("kind", "")) in ["rock", "cliff", "prop"] and tint != Color.WHITE:
		m = src.duplicate()
		for i in m.get_surface_count():
			var sm := m.surface_get_material(i)
			if sm is BaseMaterial3D:
				var tm: BaseMaterial3D = sm.duplicate()
				tm.albedo_color = tm.albedo_color * tint
				m.surface_set_material(i, tm)
	if str(a.get("kind", "")) == "tree":
		m = src.duplicate()
		for i in m.get_surface_count():
			var sm := m.surface_get_material(i)
			if sm is BaseMaterial3D:
				m.surface_set_material(i, foliage(sm, lod == "BB", tint, float(a.get("leaf_cut", 0.42)))
					if (sm as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					else bark(sm, _col(a.get("bark_tint"))))
	_meshes[key] = m
	return m


## A tree's leaves: its texture cut out (alpha scissor), both sides drawn, light wrapping round
## and coming through the leaves (backlight: the shaded side of a crown isn't black), the
## normal map softened (thousands of overlapping cards: noise otherwise). The far card (bb) has
## its shade baked in: lit more evenly. cut: the alpha kept (a species with thin needles, whose
## texture's smaller mipmaps fade to almost nothing, has a lower one: "leaf_cut" in its entry).
static func foliage(src: BaseMaterial3D, bb := false, tint := Color.WHITE, cut := 0.42) -> Material:
	var key := str(src.get_instance_id()) + ("bb" if bb else "") + tint.to_html() + str(cut)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = src.albedo_texture
	m.albedo_color = (Color(1.12, 1.15, 1.08) if not bb else Color(1.0, 1.0, 1.0)) * tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = cut if not bb else 0.42
	m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED if not bb else BaseMaterial3D.CULL_BACK   # (the far card: two faces back to back)
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.roughness = 0.85
	m.metallic_specular = 0.2
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if not bb and src.normal_enabled and src.normal_texture:
		m.normal_enabled = true
		m.normal_texture = src.normal_texture
		m.normal_scale = 0.35
	m.backlight_enabled = true
	m.backlight = Color(0.42, 0.5, 0.24) if not bb else Color(0.25, 0.3, 0.15)
	_mats[key] = m
	return m


static func _col(v) -> Color:
	return Color(float(v[0]), float(v[1]), float(v[2])) if v is Array and v.size() >= 3 else Color.WHITE


## A tree's bark: matte, its normal map kept (times the species' tint: one bark texture serves two species).
static func bark(src: BaseMaterial3D, tint := Color.WHITE) -> Material:
	var key := str(src.get_instance_id()) + tint.to_html()
	if _mats.has(key):
		return _mats[key]
	var m: StandardMaterial3D = (src as StandardMaterial3D).duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
	m.albedo_color = m.albedo_color * tint
	m.roughness = 0.92
	m.metallic = 0.0
	m.metallic_specular = 0.25
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	_mats[key] = m
	return m


## A building's material (tools/buildings.py: one facade image, its alpha the glass): the
## facade, the glass a little glossy, and at night (night 0..1: WorldMaterials.night_amount)
## some of the windows lit, warm or cold-white, per window-sized cell of the wall.
static var _bld_shader: Shader = null

static func building(src: Material, night := 0.0) -> Material:
	var tex: Texture2D = (src as BaseMaterial3D).albedo_texture if src is BaseMaterial3D else null
	var key := "bld" + str(tex.get_instance_id() if tex else 0) + str(snappedf(night, 0.05))
	if _mats.has(key):
		return _mats[key]
	if _bld_shader == null:
		_bld_shader = Shader.new()
		_bld_shader.code = """
shader_type spatial;
// A building from the owner's city pack: its facade image (the glass in the alpha); at night
// some windows lit, per cell of the wall (about a window: 2.6 m across, a 3.2 m storey).
uniform sampler2D facade : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float night = 0.0;
varying vec3 wpos;
varying vec3 wnrm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec4 c = texture(facade, UV);
	float glass = c.a;
	ALBEDO = c.rgb;
	ROUGHNESS = mix(0.86, 0.18, glass);
	METALLIC = glass * 0.25;
	SPECULAR = 0.4;
	// the wall's own coordinates (along it, up it): a cell per window
	float along = abs(wnrm.x) > abs(wnrm.z) ? wpos.z : wpos.x;
	vec2 cell = floor(vec2(along / 2.6, wpos.y / 3.2));
	vec2 seed = cell + floor(MODEL_MATRIX[3].xz * 0.1);
	float lit = step(0.78 - 0.3 * night, hash(seed));
	vec3 warm = mix(vec3(1.0, 0.72, 0.42), vec3(0.66, 0.76, 1.0), step(0.74, hash(seed * 1.7)));
	EMISSION = glass * lit * warm * night * (0.45 + 0.9 * hash(seed * 3.1));
}
"""
	var m := ShaderMaterial.new()
	m.shader = _bld_shader
	m.set_shader_parameter("facade", tex)
	m.set_shader_parameter("night", night)
	_mats[key] = m
	return m


## Drops the cache (after a graphics-quality change: the materials are rebuilt).
static func clear_cache() -> void:
	_meshes.clear()
	_mats.clear()
