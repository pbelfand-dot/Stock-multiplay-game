extends Node3D
## Builds the LAKESHORE LOOP (LoopGen) into the world: both carriageways (asphalt,
## lane markings, the median barrier, guardrails or parapets and sound walls),
## the viaducts on their piers, the suspension bridges (towers, main cables,
## hangers, the deck's truss), the tunnels, overpasses, sign gantries and lamp
## posts, the ramps, the land along the road and out to the horizon, the lakes,
## the city's towers and the hills' trees.
##
## Real materials, not flat colours: every surface has UVs in metres and comes
## from scripts/render/world_materials.gd when there is one (the realistic look),
## else from the fallbacks here (textured from noise). Cut into 200 m chunks, each
## drawn only within a range of the camera; every surface the tyres touch says
## what it is (meta "surface").
##
## The light: WorldMaterials.setup (the sky, the sun, the quality's effects) for the mood
## or the hour (time_of_day, Settings' TIME OF DAY), with a thinner fog (a highway: the
## bridges kilometres off). At night (and dusk) the lamp posts on the viaducts, the
## bridges and through the city are lit (StreetLamps: street_lamps, the game points it at
## the player's car), the towers' windows light up, the traffic's lamps glow (Traffic).

const GeoBuf = preload("res://scripts/stage/geo_buf.gd")
const LoopGen = preload("res://scripts/stage/loop_gen.gd")
const EnvAssets = preload("res://scripts/stage/env_assets.gd")
const WM_PATH := "res://scripts/render/world_materials.gd"

const CH := 100                      # samples a chunk (200 m)
const ROAD_RANGE := 2600.0           # m: a chunk's road and barriers drawn this far off
const LAND_RANGE := 3600.0
const RIBBON := [0.0, 2.0, 5.0, 10.0, 18.0, 30.0, 45.0, 65.0, 90.0, 125.0, 170.0, 230.0, 300.0]
const PIER_EVERY := 32.0             # m between the viaduct's piers
const DECK_DEPTH := 2.2              # the viaduct's box girder under the road
const GUARD_POST := 4.0              # m between a guardrail's posts
## The tunnels' insides (and the lamps) are on their own render layer, which the sun
## doesn't light (its shadow map is too coarse to keep it out of a tube): they're lit
## by their own lamps and the sky's ambient. They still cast the sun's shadows.
const TUNNEL_LAYER := 1 << 13      # (not 1 << 1: the driver's seat camera leaves that layer out, his helmet's)

var mood := "day"
var time_of_day := -1.0              # the hour (0-24) to light it for, or -1: by its mood (Modes.with_time)
var st: LoopGen
var _wm = null                       # WorldMaterials (if there is one)
var _mats := {}
var _chunks := {}                    # chunk -> {material key: GeoBuf}
var _bodies := {}                    # chunk -> {surface: GeoBuf} (collision)
var _rng := RandomNumberGenerator.new()
var _road_grid := {}                 # 100 m cells -> [sample indices every 10 m]
var _ground_f := PackedFloat32Array()   # per sample: 1 on "ground" (embankment/cut), 0 elsewhere, eased
var _extra_r := PackedFloat32Array()    # per sample: the extra width of an acceleration/deceleration lane, right
var _extra_l := PackedFloat32Array()    # ... and on the other carriageway's
var start_clocks: Array = []         # (the rally stages' countdown boards: none here)
var street_lamps                     # StreetLamps (lit at night / dusk; else null): the game sets its target
var lamp_heads: Array = []           # the lamp posts' heads: [{s, head, ground}] (lit at night)
var tree_count := 0
var building_count := 0
var real_building_count := 0         # of them the library's (EnvAssets "building"), the rest drawn boxes
var _rib_y := [[], []]               # the land ribbons' rows as drawn (right, left), every 2nd sample: a height at each RIBBON distance
var _rib_d0 := [[], []]              # ... each row's first point's d
var _far := {}                       # the far land's grid as drawn {lo, cell, w, nx, nz, hs}
var _ramp_grid := {}                 # 50 m cells -> the ramps' road points there (nothing's built on them)


func build(stage) -> void:
	_prepare(stage)
	for step in STEPS:
		var t0 := Time.get_ticks_msec()
		call(step[0])
		if OS.is_debug_build() and Time.get_ticks_msec() - t0 > 300:
			print("[loop] %s: %.1f s" % [step[0], (Time.get_ticks_msec() - t0) / 1000.0])


func build_async(stage, report: Callable) -> void:
	_prepare(stage)
	for i in STEPS.size():
		report.call(float(i) / STEPS.size(), STEPS[i][1])
		await get_tree().process_frame
		if not is_inside_tree():
			return
		call(STEPS[i][0])
	report.call(1.0, "")


const STEPS := [["_environment", "Checking the weather"], ["_road", "Laying the highway"],
	["_barriers", "Pouring the barriers"], ["_viaducts", "Raising the viaducts"],
	["_bridges", "Spinning the bridge cables"], ["_tunnels", "Boring the tunnels"],
	["_roadside", "Putting up the signs and lights"], ["_toll_plaza", "Opening the toll booths"], ["_ramps", "Opening the ramps"],
	["_station", "Opening the gas station"],
	["_ribbon", "Shaping the land"], ["_far_land", "Shaping the hills"], ["_water", "Filling the lakes"],
	["_city", "Building the city"], ["_trees", "Planting the hills"], ["_finish", "Opening the highway"]]


## (the game calls this on a rally stage's start boards: nothing to show here)
func set_start_clock(_text: String, _col: Color) -> void:
	pass


func _prepare(stage) -> void:
	st = stage
	_rng.seed = hash([st.seed_used, "loop"])
	if ResourceLoader.exists(WM_PATH):
		_wm = load(WM_PATH)
		_wm.ground_style = ""                          # (a stage's forest floor and touge asphalt aren't the highway's)
		_wm.asphalt_style = ""
	var n: int = st._n
	for i in range(0, n, 5):
		var key := Vector2i(floori(st.pts[i].x / 100.0), floori(st.pts[i].z / 100.0))
		if not _road_grid.has(key):
			_road_grid[key] = []
		_road_grid[key].append(i)
	# ground-ness, eased over ~60 m so the land doesn't step where the support changes (a tunnel
	# counts: the cut up to its portal is the land's, not eased off into the air before it)
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		raw[i] = 1.0 if st.support_at(i * st.STEP) in ["ground", "tunnel"] else 0.0
	_ground_f = _ease(raw, 30)
	_extra_r = st.extra_r
	_extra_l = st.extra_l
	for r in st.ramps:
		for p in st.ramp_path(r).pts:
			var key := Vector2i(floori(p.x / 50.0), floori(p.z / 50.0))
			if not _ramp_grid.has(key):
				_ramp_grid[key] = []
			_ramp_grid[key].append(p)
	if not st.station.is_empty():
		# (the gas station's forecourt: nothing's built on it either, the towers and trees kept off)
		var H: Vector2 = st.STATION_HALF
		var a := -H.x
		while a <= H.x + 0.01:
			var b := -H.y
			while b <= H.y + 0.01:
				var p: Vector3 = st.station_at(a, b)
				var key := Vector2i(floori(p.x / 50.0), floori(p.z / 50.0))
				if not _ramp_grid.has(key):
					_ramp_grid[key] = []
				_ramp_grid[key].append(p)
				b += 4.0
			a += 4.0


## s - s0 round the loop, the nearest way (-L/2 .. L/2).
func _ds(s: float, s0: float) -> float:
	var L: float = st.length
	return fposmod(s - s0 + L * 0.5, L) - L * 0.5


func _ease(raw: PackedFloat32Array, w: int) -> PackedFloat32Array:
	var n := raw.size()
	var pre := PackedFloat32Array([0.0])
	for i in range(-w, n + w):
		pre.append(pre[-1] + raw[posmod(i, n)])
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = (pre[i + 2 * w + 1] - pre[i]) / (2 * w + 1)
	return out


# ── materials ─────────────────────────────────────────────────────────────

## WorldMaterials' material for each key (and its options for this map's meshes: UVs in
## metres, UV.x along the road); the rest (the towers' facades, the trees, signs, cables,
## the tunnels' self-lit walls) are this map's own.
const WM_FOR := {"asphalt": ["asphalt", {"uv": true, "uv_along": "x", "tint": Color(0.52, 0.54, 0.58)}], "paint": ["road_paint", {"vertex": "colour", "tint": Color(0.85, 0.85, 0.83)}],
	"concrete": ["concrete", {}], "steel": ["steel", {"tint": Color(0.62, 0.64, 0.67)}],
	"water": ["water", {"tint": Color(0.035, 0.085, 0.12)}], "terrain": ["terrain", {}],
	"post_lamp": ["street_lamp_head", {}]}


func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material = null
	if _wm and WM_FOR.has(key) and _wm.has_method(WM_FOR[key][0]):
		m = _wm.call(WM_FOR[key][0], WM_FOR[key][1])
	if m == null:
		m = _fallback(key)
	_mats[key] = m
	return m


func _noise_tex(freq: float, normal := false, seed_v := 1, size := 512, lo := 0.78) -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	nt.width = size
	nt.height = size
	nt.seamless = true
	nt.as_normal_map = normal
	if normal:
		nt.bump_strength = 4.0
	else:
		var g := Gradient.new()                     # (dark to light only lo..1: mottled, not speckled)
		g.set_color(0, Color(lo, lo, lo))
		g.set_color(1, Color(1, 1, 1))
		nt.color_ramp = g
	var fn := FastNoiseLite.new()
	fn.seed = seed_v
	fn.frequency = freq
	fn.fractal_octaves = 4
	nt.noise = fn
	return nt


## The materials used when there's no WorldMaterials: real-ish (textured, shaded),
## from noise made at load time (nothing to download).
func _fallback(key: String) -> Material:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	match key:
		"asphalt":
			m.albedo_color = Color(0.2, 0.2, 0.21)
			m.albedo_texture = _noise_tex(0.06, false, 3)
			m.normal_enabled = true
			m.normal_texture = _noise_tex(0.25, true, 4)
			m.normal_scale = 0.35
			m.roughness = 0.9
			m.uv1_scale = Vector3(0.25, 0.25, 1.0)
		"paint":
			m.albedo_color = Color(0.88, 0.88, 0.85)
			m.roughness = 0.6
		"concrete":
			m.albedo_color = Color(0.46, 0.46, 0.44)
			m.albedo_texture = _noise_tex(0.05, false, 5, 512, 0.88)
			m.roughness = 0.95
			m.metallic_specular = 0.2
			m.uv1_scale = Vector3(0.2, 0.2, 1.0)
		"soundwall":
			m.albedo_color = Color(0.62, 0.68, 0.66)
			m.roughness = 0.7
			m.metallic = 0.2
		"steel":
			m.albedo_color = Color(0.62, 0.64, 0.67)
			m.metallic = 0.7
			m.roughness = 0.4
		"steel_red":
			m.albedo_color = Color(0.72, 0.16, 0.08)       # (the Golden Gate's "international orange")
			m.metallic = 0.3
			m.roughness = 0.5
		"steel_white":
			m.albedo_color = Color(0.9, 0.9, 0.88)
			m.metallic = 0.2
			m.roughness = 0.45
		"cable":
			m.albedo_color = Color(0.5, 0.5, 0.52)
			m.metallic = 0.8
			m.roughness = 0.35
		"terrain":
			m.albedo_color = Color(1, 1, 1)
			m.albedo_texture = _noise_tex(0.02, false, 7)
			m.normal_enabled = true
			m.normal_texture = _noise_tex(0.08, true, 8)
			m.normal_scale = 0.5
			m.roughness = 1.0
			m.uv1_scale = Vector3(0.12, 0.12, 1.0)
		"water":
			m.vertex_color_use_as_albedo = false
			m.albedo_color = Color(0.07, 0.17, 0.24)
			m.metallic = 0.25
			m.roughness = 0.06
			m.normal_enabled = true
			m.normal_texture = _noise_tex(0.05, true, 9)
			m.normal_scale = 0.25
			m.uv1_scale = Vector3(0.02, 0.02, 1.0)
		"tunnel":
			# (lit by its own rows of lamps: faked with a little self-light, the sun kept out)
			m.albedo_color = Color(0.62, 0.61, 0.56)
			m.albedo_texture = _noise_tex(0.08, false, 10)
			m.roughness = 0.6
			m.emission_enabled = true
			m.emission = Color(0.42, 0.4, 0.34)
			m.emission_energy_multiplier = 0.6
			m.uv1_scale = Vector3(0.5, 0.5, 1.0)
		"lamp", "post_lamp":
			m.vertex_color_use_as_albedo = false
			m.albedo_color = Color(1.0, 0.93, 0.78)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.86, 0.62)
			m.emission_energy_multiplier = 2.5
		"beacon":
			# (the bridge towers' aircraft warning lights: red, brighter at night)
			m.vertex_color_use_as_albedo = false
			m.albedo_color = Color(0.5, 0.06, 0.04)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.1, 0.05)
			m.emission_energy_multiplier = 1.5 + 6.0 * (_wm.night_amount if _wm else 0.0)
		"sign":
			m.albedo_color = Color(0.04, 0.36, 0.17)
			m.roughness = 0.5
		"toll_paint":
			# (the toll plaza's painted steel and concrete: its colour from each box's)
			m.albedo_color = Color(1, 1, 1)
			m.roughness = 0.55
			m.metallic_specular = 0.4
		"toll_glass":
			# (the booths' windows: dark glass, lit from inside at night)
			m.vertex_color_use_as_albedo = false
			m.albedo_color = Color(0.1, 0.13, 0.16)
			m.metallic = 0.4
			m.roughness = 0.08
			m.emission_enabled = true
			m.emission = Color(1.0, 0.86, 0.62)
			m.emission_energy_multiplier = 0.05 + 1.6 * (_wm.night_amount if _wm else (1.0 if mood == "night" else 0.0))
		"station_screen":
			# (the pumps' screens: lit, day and night)
			m.vertex_color_use_as_albedo = false
			m.albedo_color = Color(0.1, 0.2, 0.3)
			m.emission_enabled = true
			m.emission = Color(0.35, 0.75, 1.0)
			m.emission_energy_multiplier = 1.2 + 1.5 * (_wm.night_amount if _wm else 0.0)
		"toll_green", "toll_red":
			# (the lane signals: lit, day and night)
			m.vertex_color_use_as_albedo = false
			var lit := Color(0.15, 1.0, 0.35) if key == "toll_green" else Color(1.0, 0.12, 0.08)
			m.albedo_color = lit * 0.6
			m.emission_enabled = true
			m.emission = lit
			m.emission_energy_multiplier = 2.2 + 2.0 * (_wm.night_amount if _wm else 0.0)
		"building":
			return _building_material()
		"bark":
			m.albedo_color = Color(0.3, 0.22, 0.15)
			m.roughness = 1.0
		"leaves":
			m.albedo_color = Color(0.2, 0.32, 0.14)
			m.albedo_texture = _noise_tex(0.2, false, 11, 256)
			m.roughness = 1.0
			m.uv1_scale = Vector3(0.5, 0.5, 1.0)
		_:
			m.albedo_color = Color(0.5, 0.5, 0.5)
	return m


## The towers' glass and concrete: floors 3.6 m apart, windows 2.4 m, some lit,
## from where on the building the pixel is (no texture to load).
func _building_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
// The towers' facades: floors and window bays in metres on each face (the box is
// scaled per tower: its scale is read back from the model matrix), a few windows lit.
uniform float night = 0.0;   // 0 day .. 1 night: more windows lit, and brighter
varying vec2 face;
varying float roof;
varying float seed;
void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	vec3 p = VERTEX + 0.5;
	roof = abs(NORMAL.y) > 0.5 ? 1.0 : 0.0;
	face = abs(NORMAL.x) > 0.5 ? vec2(p.z * sc.z, p.y * sc.y) : vec2(p.x * sc.x, p.y * sc.y);
	seed = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453);
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec3 tint = COLOR.rgb;
	if (roof > 0.5) {
		ALBEDO = tint * 0.6; ROUGHNESS = 0.9; METALLIC = 0.0;
	} else {
		vec2 bay = vec2(2.2 + seed * 1.4, 3.4 + seed * 0.5);
		vec2 cell = face / bay;
		vec2 f = fract(cell);
		float wide = 0.06 + 0.1 * fract(seed * 7.0);
		float frame = step(wide, f.x) * step(f.x, 1.0 - wide) * step(0.16, f.y) * step(f.y, 0.88);
		frame *= step(3.0, face.y);                               // (the ground floor: a plinth)
		float lit = step(0.9 - 0.17 * night, hash(floor(cell) + seed * 31.0));
		vec3 glass = mix(vec3(0.06, 0.09, 0.12), vec3(0.2, 0.27, 0.33), hash(floor(cell) * 1.7 + seed));
		ALBEDO = mix(tint, glass, frame);
		METALLIC = frame * 0.6;
		ROUGHNESS = mix(0.85, 0.1, frame);
		vec3 warm = mix(vec3(1.0, 0.7, 0.4), vec3(0.62, 0.74, 1.0), step(0.72, hash(floor(cell) * 3.1 + seed)));   // (some offices cold-white)
		EMISSION = frame * lit * warm * mix(0.12, 1.0, night) * (0.35 + 0.65 * hash(floor(cell) * 5.3 + seed));
	}
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("night", _wm.night_amount if _wm else (1.0 if mood == "night" else 0.0))
	return m


# ── chunks ────────────────────────────────────────────────────────────────

func _buf(i: int, key: String) -> GeoBuf:
	var c := int(posmod(i, st._n) / CH)
	if not _chunks.has(c):
		_chunks[c] = {}
	if not _chunks[c].has(key):
		_chunks[c][key] = GeoBuf.new()
	return _chunks[c][key]


func _body(i: int, surface: String) -> GeoBuf:
	var c := int(posmod(i, st._n) / CH)
	if not _bodies.has(c):
		_bodies[c] = {}
	if not _bodies[c].has(surface):
		_bodies[c][surface] = GeoBuf.new()
	return _bodies[c][surface]


## Every chunk's geometry made into nodes (the last step: everything's in).
func _finish() -> void:
	var land_keys := ["terrain"]
	for c in _chunks:
		var node := Node3D.new()
		node.name = "Chunk%03d" % c
		add_child(node)
		for key in _chunks[c]:
			var gb: GeoBuf = _chunks[c][key]
			if gb.is_empty():
				continue
			var mi := MeshInstance3D.new()
			mi.name = key
			mi.mesh = gb.mesh()
			mi.material_override = _mat(key)
			mi.visibility_range_end = LAND_RANGE if key in land_keys else (9000.0 if key.begins_with("steel") or key == "cable" else ROAD_RANGE)
			mi.visibility_range_end_margin = 200.0
			if key in ["paint", "lamp", "post_lamp", "beacon", "toll_green", "toll_red"]:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if key in ["tunnel", "lamp"]:
				mi.layers = TUNNEL_LAYER
			elif key in ["asphalt", "paint"] and _wm:
				mi.layers = _wm.ROAD_LAYER                   # (lit at night by the street lamps' pools, not their real lights)
			node.add_child(mi)
	for c in _bodies:
		for surface in _bodies[c]:
			var gb: GeoBuf = _bodies[c][surface]
			if gb.faces.is_empty():
				continue
			var sb := StaticBody3D.new()
			sb.name = "Body%03d_%s" % [c, surface]
			sb.set_meta("surface", surface)
			var cs := CollisionShape3D.new()
			cs.shape = gb.shape()
			sb.add_child(cs)
			add_child(sb)
	_chunks.clear()
	_bodies.clear()


# ── the sky ───────────────────────────────────────────────────────────────

func _environment() -> void:
	if _wm and _wm.has_method("setup"):
		# (the sky, the sun, the quality's effects; a thinner fog: the bridges kilometres off)
		var w: Dictionary = _wm.setup(self, mood, time_of_day, {"fog": 0.16})
		mood = w.mood
		var ws: DirectionalLight3D = w.sun
		ws.light_cull_mask = 0xFFFFF & ~TUNNEL_LAYER
		ws.shadow_caster_mask = 0xFFFFFFFF
		return
	# (no WorldMaterials: a drawn sky, the old light)
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.3, 0.52, 0.84)
	sm.sky_horizon_color = Color(0.7, 0.8, 0.9)
	sm.ground_horizon_color = Color(0.62, 0.68, 0.7)
	sm.ground_bottom_color = Color(0.3, 0.33, 0.3)
	sm.sun_angle_max = 20.0
	if mood == "golden":
		sm.sky_top_color = Color(0.28, 0.4, 0.68)
		sm.sky_horizon_color = Color(1.0, 0.72, 0.45)
		sm.ground_horizon_color = Color(0.75, 0.6, 0.45)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = sm.sky_horizon_color
	env.fog_density = 0.00016                     # (a highway: you see the bridges kilometres off)
	env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(40.0), 0.0)
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.light_energy = 1.1
	if mood == "golden":
		sun.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(60.0), 0.0)
		sun.light_color = Color(1.0, 0.75, 0.5)
	sun.shadow_enabled = not OS.has_feature("web")
	sun.directional_shadow_max_distance = 120.0
	sun.light_cull_mask = 0xFFFFF & ~TUNNEL_LAYER
	sun.shadow_caster_mask = 0xFFFFFFFF
	add_child(sun)


# ── the road ──────────────────────────────────────────────────────────────

## The asphalt's edges at sample i: [left (the other carriageway's outer edge), right].
func _edges(i: int) -> Vector2:
	var j := posmod(i, st._n)
	return Vector2(st.ONCOMING_D - st.EDGE - st.SHOULDER_R - _extra_l[j], st.EDGE + st.SHOULDER_R + _extra_r[j])


## The asphalt's edges at the ends of the stretch from sample i to i+1: as _edges, but at a
## ramp's nose (where the widened edge it curves off on ends at once) both ends take the
## narrower, so the widened asphalt ends square across the road where the ramp's own starts.
func _seg_edges(i: int) -> Array:
	var a := _edges(i)
	var b := _edges(i + 1)
	if absf(a.x - b.x) > 1.0:
		a.x = maxf(a.x, b.x)
		b.x = a.x
	if absf(a.y - b.y) > 1.0:
		a.y = minf(a.y, b.y)
		b.y = a.y
	return [a, b]


func _road() -> void:
	var n: int = st._n
	var step: float = st.STEP
	for i in n:
		var s := i * step
		var se := _seg_edges(i)
		var rows := []
		var ds := PackedFloat32Array()
		for k in 2:
			var e: Vector2 = se[k]
			ds = PackedFloat32Array([e.x, st.ONCOMING_D - st.EDGE, st.MEDIAN_D - st.MEDIAN * 0.5, st.MEDIAN_D + st.MEDIAN * 0.5, st.EDGE, e.y])
			var row := PackedVector3Array()
			for d in ds:
				row.append(st.world_at(s + k * step, d))
			rows.append(row)
		var cols := PackedColorArray()
		for k in ds.size():
			# the shoulders a touch lighter than the lanes (less traffic polish)
			var shoulder: bool = k == 0 or k == ds.size() - 1 or k == 2 or k == 3
			cols.append(Color(1.08, 1.08, 1.06) if shoulder else Color(1, 1, 1))
		_buf(i, "asphalt").ribbon(rows[0], rows[1], s, s + step, ds, Color.WHITE, false, cols, cols)
		_body(i, "asphalt").ribbon(rows[0], rows[1], s, s + step, ds, Color.WHITE, true)
		_markings(i)


const RAMP_LINE := 1.85              # m: a ramp's edge lines either side of its middle (its lane between)

## The lines painted between samples i and i+1: solid edge lines, dashed lane lines
## (8 m of paint, 12 m gap, as on a Japanese expressway), both carriageways; where a
## ramp's extra lane runs alongside, the edge line is a short, thick dashed one; where the
## ramp's lane curves off the widened edge (from its gore to its nose) the edge line is solid
## and the ramp's lane has its own two (the gore opening between).
func _markings(i: int) -> void:
	var s0: float = i * st.STEP
	var s1: float = s0 + st.STEP
	var j := posmod(i, st._n)
	var lines := []   # [d, width, dashed (, d at s1)]
	for side in [0.0, st.ONCOMING_D]:
		var mirror: float = 1.0 if side == 0.0 else -1.0
		var extra: float = _extra_r[j] if side == 0.0 else _extra_l[j]
		var rm: PackedFloat32Array = st.ramp_r if side == 0.0 else st.ramp_l
		var ra: float = rm[j]
		var rb: float = rm[posmod(j + 1, st._n)]
		if ra != 0.0 and rb != 0.0:
			lines.append([side + mirror * st.EDGE, 0.2, 0.0])
			for e in [-1.0, 1.0]:
				lines.append([ra + e * RAMP_LINE, 0.15, 0.0, rb + e * RAMP_LINE])
		else:
			lines.append([side + mirror * st.EDGE, 0.2 if extra <= 0.0 else 0.45, 0.0 if extra <= 0.0 else 2.0])
			if extra > 0.5:
				lines.append([side + mirror * (st.EDGE + extra + 0.1), 0.2, 0.0])
		lines.append([side - mirror * st.EDGE, 0.15, 0.0])
		for k in [-1.0, 0.0, 1.0]:
			lines.append([side + k * st.LANE_W, 0.15, 1.0])
	var gb := _buf(i, "paint")
	# the toll plaza: the lines fan out with the lanes (st.toll_d), solid from 80 m before the
	# booths (no changing lanes there), none under the islands
	var toll_ds: float = INF if st.toll.is_empty() else absf(_ds(s0, float(st.toll.s)))
	var toll_half: float = float(st.toll.get("half", 0.0))
	var spread: bool = st.toll_spread(s0) != 1.0 or st.toll_spread(s1) != 1.0
	for l in lines:
		var d: float = l[0]
		var w: float = l[1]
		var a0 := s0
		var a1 := s1
		if l[2] == 1.0 and toll_ds < toll_half + 0.5:
			continue
		if l[2] == 1.0 and toll_ds > toll_half + 80.0:
			var ph := fposmod(s0, 20.0)
			if ph >= 8.0:
				continue
			a1 = minf(s1, s0 + 8.0 - ph)
		elif l[2] == 2.0:
			if fposmod(s0, 6.0) >= 3.0:
				continue
		var lift := Vector3.UP * 0.015
		var d0 := d
		var d1: float = l[3] if l.size() > 3 else d
		if spread:
			d0 = _toll_line_d(d, a0)
			d1 = _toll_line_d(d, a1)
		var p0 := st.world_at(a0, d0 - w * 0.5) + lift
		var p1 := st.world_at(a0, d0 + w * 0.5) + lift
		var p2 := st.world_at(a1, d1 + w * 0.5) + lift
		var p3 := st.world_at(a1, d1 - w * 0.5) + lift
		gb.quad(p0, p1, p2, p3, Vector2(a0, 0), Vector2(a0, w), Vector2(a1, w), Vector2(a1, 0))


## A painted line's d at the toll plaza: fanned out with the lanes, the edge lines by the
## median kept off its kerb.
func _toll_line_d(d: float, s: float) -> float:
	var x: float = st.toll_d(d, s)
	if d > st.MEDIAN_D:
		return maxf(x, st.MEDIAN_D + st.MEDIAN * 0.5 + 0.25) if d < 0.0 else x
	return minf(x, st.MEDIAN_D - st.MEDIAN * 0.5 - 0.25) if d > st.ONCOMING_D else x


# ── barriers ──────────────────────────────────────────────────────────────

func _barriers() -> void:
	var n: int = st._n
	var step: float = st.STEP
	for i in n:
		var s := i * step
		var sup: String = st.support_at(s)
		var zone: String = st.zone_at(s)
		# the median: concrete, single slope, both carriageways' (in a tunnel it's the wall between the tubes;
		# at the toll plaza the booths' middle island takes its place)
		if sup != "tunnel" and not _toll_island_at(s):
			_concrete_profile(i, st.MEDIAN_D, [[-0.3, 0.0], [-0.1, st.BARRIER_H], [0.1, st.BARRIER_H], [0.3, 0.0]], "concrete")
		var se := _seg_edges(i)
		var e: Vector2 = se[0]
		var e2: Vector2 = se[1]
		if sup == "tunnel":
			# (the floor paved out to the tubes' walls: it stopped 0.6 m short, a slot down to the land)
			_ledge(i, e, e2, e.y + 0.55, e2.y + 0.55, 1.0)
			_ledge(i, e, e2, e.x - 0.55, e2.x - 0.55, -1.0)
			continue
		# (where a ramp curves off the widened edge the barrier goes out along the ramp's outside,
		# to its nose, where the ramp's own barriers take over and ours comes back to the road's edge)
		for side in [1.0, -1.0]:
			var d0: float = (e.y + 0.4) if side > 0.0 else (e.x - 0.4)
			var d1: float = (e2.y + 0.4) if side > 0.0 else (e2.x - 0.4)
			if sup == "viaduct" or sup == "bridge":
				_parapet(i, d0, d1, side, zone == "city" and sup == "viaduct")
			else:
				_guardrail(i, d0, d1, side)
			_ledge(i, e, e2, d0, d1, side)


## The 0.4 m between the road's edge and its barrier, paved and solid (a little under the
## barrier too). It was a slot: a car pushed against the barrier dropped its outside
## wheels into it and hung on the road's edge, and steering couldn't pull it off.
func _ledge(i: int, e: Vector2, e2: Vector2, d0: float, d1: float, side: float) -> void:
	var s0: float = i * st.STEP
	var s1: float = s0 + st.STEP
	var a := PackedFloat32Array([e.y, d0 + 0.05]) if side > 0.0 else PackedFloat32Array([d0 - 0.05, e.x])
	var b := PackedFloat32Array([e2.y, d1 + 0.05]) if side > 0.0 else PackedFloat32Array([d1 - 0.05, e2.x])
	var ra := PackedVector3Array([st.world_at(s0, a[0]), st.world_at(s0, a[1])])
	var rb := PackedVector3Array([st.world_at(s1, b[0]), st.world_at(s1, b[1])])
	var cols := PackedColorArray([Color(1.08, 1.08, 1.06), Color(1.08, 1.08, 1.06)])   # (the shoulders' tone)
	_buf(i, "asphalt").ribbon(ra, rb, s0, s1, a, Color.WHITE, false, cols, cols)
	_body(i, "asphalt").ribbon(ra, rb, s0, s1, a, Color.WHITE, true)


## Is a ramp leaving or joining here, its lane on the widened edge (between its gore and its
## nose: the outer barrier's out along the ramp's outside)?
func _ramp_at(s: float, side: float) -> bool:
	var j := int(st.wrap_s(s) / st.STEP)
	return (st.ramp_r[j] if side > 0.0 else st.ramp_l[j]) != 0.0


## A concrete profile along the road between samples i and i+1: [[d offset, height]]
## about d (left to right), its own collision.
func _concrete_profile(i: int, d: float, prof: Array, key: String) -> void:
	var s0: float = i * st.STEP
	var s1: float = s0 + st.STEP
	var ra := PackedVector3Array()
	var rb := PackedVector3Array()
	var vs := PackedFloat32Array()
	var v := 0.0
	for k in prof.size():
		ra.append(st.world_at(s0, d + prof[k][0]) + Vector3.UP * prof[k][1])
		rb.append(st.world_at(s1, d + prof[k][0]) + Vector3.UP * prof[k][1])
		if k > 0:
			v += Vector2(prof[k][0] - prof[k - 1][0], prof[k][1] - prof[k - 1][1]).length()
		vs.append(v)
	_faces(_buf(i, key), ra, rb, s0, s1, vs)
	_body(i, "concrete").ribbon(ra, rb, s0, s1, vs, Color.WHITE, true)


## A ribbon drawn a face at a time: hard edges at the profile's corners (one ribbon averages
## the normals round them, and the concrete, textured by its normal, came out streaked like
## dry grass down the walls' faces).
func _faces(gb: GeoBuf, ra: PackedVector3Array, rb: PackedVector3Array, s0: float, s1: float, vs: PackedFloat32Array) -> void:
	for f in ra.size() - 1:
		gb.ribbon(ra.slice(f, f + 2), rb.slice(f, f + 2), s0, s1, vs.slice(f, f + 2))


## A viaduct's or bridge's parapet: a concrete wall 1.1 m over the road on the
## inside, down the deck's side outside; in the city a sound wall above it.
func _parapet(i: int, d0: float, d1: float, side: float, sound: bool) -> void:
	var s0: float = i * st.STEP
	var s1: float = s0 + st.STEP
	var w := 0.35 * side
	var pts0 := [Vector2(0.0, 0.0), Vector2(0.0, 1.1), Vector2(w, 1.1), Vector2(w, -DECK_DEPTH)]
	var ra := PackedVector3Array()
	var rb := PackedVector3Array()
	var vs := PackedFloat32Array()
	var v := 0.0
	var order := [0, 1, 2, 3] if side > 0.0 else [3, 2, 1, 0]
	for k in order:
		var p: Vector2 = pts0[k]
		ra.append(st.world_at(s0, d0 + p.x) + Vector3.UP * p.y)
		rb.append(st.world_at(s1, d1 + p.x) + Vector3.UP * p.y)
		vs.append(v)
		v += 1.0
	_faces(_buf(i, "concrete"), ra, rb, s0, s1, vs)
	_body(i, "concrete").ribbon(ra, rb, s0, s1, vs, Color.WHITE, true)
	if sound:
		# ribbed panels 3 m tall on posts, set on the parapet
		var h0 := 1.1
		var h1 := 4.1
		var a := st.world_at(s0, d0 + w * 0.5)
		var b := st.world_at(s1, d1 + w * 0.5)
		var q0 := a + Vector3.UP * h0
		var q1 := b + Vector3.UP * h0
		var q2 := b + Vector3.UP * h1
		var q3 := a + Vector3.UP * h1
		var gb := _buf(i, "soundwall")
		if side > 0.0:
			gb.quad(q0, q3, q2, q1, Vector2(s0, h0), Vector2(s0, h1), Vector2(s1, h1), Vector2(s1, h0))
			gb.quad(q0, q1, q2, q3, Vector2(s0, h0), Vector2(s1, h0), Vector2(s1, h1), Vector2(s0, h1))
		else:
			gb.quad(q0, q1, q2, q3, Vector2(s0, h0), Vector2(s1, h0), Vector2(s1, h1), Vector2(s0, h1))
			gb.quad(q0, q3, q2, q1, Vector2(s0, h0), Vector2(s0, h1), Vector2(s1, h1), Vector2(s1, h0))
		if fposmod(s0, 4.0) < st.STEP:
			_buf(i, "steel").box(a + Vector3.UP * (h0 + 1.5), Vector3(0.15, 3.0, 0.15), Basis(Vector3.UP, -st.heading_at(s0)))


## A steel guardrail (a W-beam on posts) between samples i and i+1.
func _guardrail(i: int, d0: float, d1: float, side: float) -> void:
	var s0: float = i * st.STEP
	var s1: float = s0 + st.STEP
	var gb := _buf(i, "steel")
	var b0 := st.world_at(s0, d0)
	var b1 := st.world_at(s1, d1)
	# the beam a W in section (two ridges 3 cm toward the road, a groove between): four strips, each
	# lit by its own tilt, both faces (it was one flat band, a grey slab)
	var prof := [[0.5, 0.0], [0.58, 0.03], [0.66, 0.0], [0.74, 0.03], [0.82, 0.0]]
	for k in 4:
		var h0: float = prof[k][0]
		var h1: float = prof[k + 1][0]
		var q0 := st.world_at(s0, d0 - side * float(prof[k][1])) + Vector3.UP * h0
		var q1 := st.world_at(s1, d1 - side * float(prof[k][1])) + Vector3.UP * h0
		var q2 := st.world_at(s1, d1 - side * float(prof[k + 1][1])) + Vector3.UP * h1
		var q3 := st.world_at(s0, d0 - side * float(prof[k + 1][1])) + Vector3.UP * h1
		gb.quad(q0, q1, q2, q3, Vector2(s0, h0), Vector2(s1, h0), Vector2(s1, h1), Vector2(s0, h1))
		gb.quad(q0, q3, q2, q1, Vector2(s0, h0), Vector2(s0, h1), Vector2(s1, h1), Vector2(s1, h0))
	if fposmod(s0, GUARD_POST) < st.STEP:
		gb.box(st.world_at(s0, d0 + side * 0.15) + Vector3.UP * 0.4, Vector3(0.12, 0.8, 0.12), Basis(Vector3.UP, -st.heading_at(s0)))
	# its collision: a wall to 0.85 m
	var c := _body(i, "barrier")
	c.quad(b0, b1, b1 + Vector3.UP * 0.85, b0 + Vector3.UP * 0.85, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color.WHITE, true)


# ── viaducts ──────────────────────────────────────────────────────────────

## Under a viaduct (and a bridge's approach spans): the box girder's underside
## and piers every PIER_EVERY m down to the ground: one under each carriageway,
## a column and a cap.
func _viaducts() -> void:
	var n: int = st._n
	var step: float = st.STEP
	for i in n:
		var s := i * step
		var sup: String = st.support_at(s)
		if sup != "viaduct" and sup != "bridge":
			continue
		var se := _seg_edges(i)
		var e: Vector2 = se[0]
		var e2: Vector2 = se[1]
		var down := Vector3.UP * -DECK_DEPTH
		var a0 := st.world_at(s, e.x - 0.05) + down
		var a1 := st.world_at(s, e.y + 0.05) + down
		var b0 := st.world_at(s + step, e2.x - 0.05) + down
		var b1 := st.world_at(s + step, e2.y + 0.05) + down
		_buf(i, "concrete").quad(a0, b0, b1, a1, Vector2(s, e.x), Vector2(s + step, e.x), Vector2(s + step, e.y), Vector2(s, e.y))
		if sup == "viaduct" and fposmod(s, PIER_EVERY) < step:
			for d in [0.0, st.ONCOMING_D]:
				var top := st.world_at(s, d) + down
				var p := Vector3(top.x, 0.0, top.z)
				var ground := maxf(st.land_at(p.x, p.z), -2.0)
				var h := top.y - ground
				if h < 1.0:
					continue
				var bas := Basis(Vector3.UP, -st.heading_at(s))
				_buf(i, "concrete").box(Vector3(p.x, ground + (h - 1.4) * 0.5, p.z), Vector3(2.6, h - 1.4, 2.2), bas)
				_buf(i, "concrete").box(Vector3(p.x, top.y - 0.7, p.z), Vector3(st.CARRIAGEWAY + 3.0, 1.4, 2.4), bas)


# ── the land ──────────────────────────────────────────────────────────────

## The land's colour (a tint on its texture): grass, rock where it's steep or high,
## sand at the water, the city's ground grey.
func _land_col(p: Vector3, slope: float) -> Color:
	var c := Color(0.27, 0.34, 0.16)
	if st.in_city(p.x, p.z):
		c = Color(0.36, 0.36, 0.35)
	elif p.y < 1.2:
		c = Color(0.46, 0.42, 0.33)
	if slope > 0.6:
		c = c.lerp(Color(0.36, 0.34, 0.31), clampf((slope - 0.6) * 2.0, 0.0, 1.0))
	return c


## The land along the road, each side out to 300 m: flush with the road's paved edge, then
## an embankment or a cut into the land (1 in 2) where the road's on the ground (up to a
## tunnel's portal; over the tubes the cut's floor is the hill's own edge, 10.5 m up); the
## land as it is under viaducts and bridges. Its outer edge has a 4 m skirt down into the far
## land (no crack between them where they don't quite meet). The rows as drawn are kept
## (_rib_y, _rib_d0: _drawn_y), and the land under the viaducts' decks drawn (_under_deck).
func _ribbon() -> void:
	var n: int = st._n
	var step: float = st.STEP * 2.0
	for side in [1.0, -1.0]:
		var prev := PackedVector3Array()
		var prev_c := PackedColorArray()
		var prev_s := 0.0
		var vs := PackedFloat32Array()
		for d in RIBBON:
			vs.append(d)
		vs.append(RIBBON[RIBBON.size() - 1] + 4.0)   # (the skirt)
		var i := 0
		while i <= n:
			var s := i * st.STEP
			# a tunnel's portal since the last row: the land steps up there to the hill over the
			# tubes (or down off it), at once, behind the portal's wing walls (_portal): a row
			# each side of the step, at the portal
			if not prev.is_empty():
				for t in st.tunnels:
					for e in [[float(t.s0), false], [float(t.s1), true]]:
						var ps: float = e[0]
						if ps > prev_s and ps <= s:
							var ip := int(ps / st.STEP)
							for hill in [e[1], not e[1]]:
								var pr: Array = _rib_row(ps, _edges(ip), _ground_f[posmod(ip, n)], side, hill)
								_rib_strip(prev, prev_c, pr[0], pr[1], prev_s, ps, vs, side, ip)
								prev = pr[0]
								prev_c = pr[1]
								prev_s = ps
			var rr: Array = _rib_row(s, _land_edges(i), _ground_f[posmod(i, n)], side, _in_tube(s))
			var row: PackedVector3Array = rr[0]
			var ys := PackedFloat32Array()
			for q in RIBBON.size():
				ys.append(row[q].y)
			_rib_y[0 if side > 0.0 else 1].append(ys)
			_rib_d0[0 if side > 0.0 else 1].append(rr[2])
			if not prev.is_empty():
				_rib_strip(prev, prev_c, row, rr[1], prev_s, s, vs, side, i - 2)
			prev = row
			prev_c = rr[1]
			prev_s = s
			i += 2
	_under_deck()


## Is s between a tunnel's portals (its first, not its last: st.tunnels', where the portals
## stand; its support starts and ends a metre or so off them)?
func _in_tube(s: float) -> bool:
	var w := st.wrap_s(s)
	for t in st.tunnels:
		if w >= float(t.s0) and w < float(t.s1):
			return true
	return false


## The asphalt's edges for the land ribbon's row at sample i: the narrowest from i-1 to i+1
## (a row stands for 4 m of road: where the road narrows at once, at a ramp's nose, the land
## starts at the narrow edge, tucked under the wide end, not short of the narrow one).
func _land_edges(i: int) -> Vector2:
	var e := _edges(i)
	for k in [i - 1, i + 1]:
		var o := _edges(k)
		e = Vector2(maxf(e.x, o.x), minf(e.y, o.y))
	return e


## A row of the land ribbon across the road at s, one side: [points out to 300 m and the skirt,
## their colours, the first point's d]. e: the asphalt's edges there; g: how much the road's on
## the ground (its cut or embankment); hill: over a tunnel's tubes.
func _rib_row(s: float, e: Vector2, g: float, side: float, hill: bool) -> Array:
	var d0: float = (e.y + 0.45) if side > 0.0 else (e.x - 0.45)   # (where the paved ledge ends)
	var edge := st.world_at(s, d0)
	var road_y := edge.y - 0.02
	if hill:
		road_y = _hill_y(s, d0)
		g = 1.0
	var right: Vector3 = st.right_at(s) * side
	var row := PackedVector3Array()
	var cols := PackedColorArray()
	for k in RIBBON.size():
		var dist: float = RIBBON[k]
		var p := edge + right * dist
		var land := st.land_at(p.x, p.z)
		var y := land
		if g > 0.0:
			var slope_len := maxf(10.0, absf(land - road_y) * 2.0)
			var t := smoothstep(2.0, 2.0 + slope_len, dist)
			y = lerpf(land, lerpf(road_y, land, t), g)
		p.y = y
		row.append(p)
		var sl := 0.0
		if k > 0:
			sl = absf(y - row[k - 1].y) / maxf(RIBBON[k] - RIBBON[k - 1], 0.1)
		cols.append(_land_col(p, sl))
	row.append(row[row.size() - 1] + Vector3.DOWN * 4.0)      # (the skirt)
	cols.append(cols[cols.size() - 1])
	return [row, cols, d0]


## The land ribbon between two rows (at sa, sb) one side, into chunk i's buffers.
func _rib_strip(prev: PackedVector3Array, prev_c: PackedColorArray, row: PackedVector3Array, cols: PackedColorArray,
		sa: float, sb: float, vs: PackedFloat32Array, side: float, i: int) -> void:
	var ra := prev if side > 0.0 else _rev(prev)
	var rb := row if side > 0.0 else _rev(row)
	var ca := prev_c if side > 0.0 else _revc(prev_c)
	var cb := cols if side > 0.0 else _revc(cols)
	var v2 := vs if side > 0.0 else _revf(vs)
	_buf(i, "terrain").ribbon(ra, rb, sa, sb, v2, Color.WHITE, false, ca, cb)
	# the near part can be driven on (off the road over a guardrail's end): collision out to 30 m
	var near := 6
	_body(i, "grass").ribbon(_slice(ra, side, near), _slice(rb, side, near), sa, sb, _slicef(v2, side, near), Color.WHITE, true)


## The land under a viaduct's or a bridge's deck, between the two land ribbons' first points
## (there was none: a strip of the water's plane showed under every viaduct, its piers standing
## in it), under the deck by 0.3 m at least.
func _under_deck() -> void:
	var n: int = st._n
	var R: Array = _rib_y[0]
	var L: Array = _rib_y[1]
	var prev := PackedVector3Array()
	for r in R.size():
		var i := r * 2
		var s := i * st.STEP
		var sup: String = st.support_at(s)
		var row := PackedVector3Array()
		if sup == "viaduct" or sup == "bridge" or (_ground_f[posmod(i, n)] < 0.999 and sup != "tunnel"):
			var dl: float = _rib_d0[1][r]
			var dr: float = _rib_d0[0][r]
			var deck := st.world_at(s, 0.0).y - DECK_DEPTH - 0.3
			for k in 9:
				var d := lerpf(dl, dr, k / 8.0)
				var p := st.world_at(s, d)
				var y := minf(st.land_at(p.x, p.z), deck)
				if k == 0:
					y = L[r][0]
				elif k == 8:
					y = R[r][0]
				p.y = y
				row.append(p)
		if not prev.is_empty() and not row.is_empty():
			var vs := PackedFloat32Array()
			var cols := PackedColorArray()
			for k in 9:
				vs.append(k * 5.0)
				cols.append(_land_col(row[k], 0.1))
			_buf(i - 2, "terrain").ribbon(prev, row, s - 2.0 * st.STEP, s, vs, Color.WHITE, false, cols, cols)
		prev = row


func _rev(a: PackedVector3Array) -> PackedVector3Array:
	var o := a.duplicate()
	o.reverse()
	return o


func _revc(a: PackedColorArray) -> PackedColorArray:
	var o := a.duplicate()
	o.reverse()
	return o


func _revf(a: PackedFloat32Array) -> PackedFloat32Array:
	var o := a.duplicate()
	o.reverse()
	return o


## The first `k` points from the road (rows run left to right: the right side's
## start at the road, the left side's end there).
func _slice(a: PackedVector3Array, side: float, k: int) -> PackedVector3Array:
	return a.slice(0, k) if side > 0.0 else a.slice(a.size() - k)


func _slicef(a: PackedFloat32Array, side: float, k: int) -> PackedFloat32Array:
	return a.slice(0, k) if side > 0.0 else a.slice(a.size() - k)


## The land beyond the ribbons, out to the horizon: a grid (40 m) over the map and
## 3 km round it, in 1 km tiles; near the road it's kept under the ribbons: 8 m under the
## road (and the land) within 170 m of it, easing up to 1.5 m under the land by 270 m and to
## the land by 340 m (past the ribbons' outer edge, ~300 m out, their skirt down into it: it
## was 8 m under out to 300 m, a crevasse along the ribbons' edge wherever it showed).
func _far_land() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in st.pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	lo -= Vector2(3000, 3000)
	hi += Vector2(3000, 3000)
	var cell := 40.0
	var tile := 25
	var nx := int((hi.x - lo.x) / cell) + 1
	var nz := int((hi.y - lo.y) / cell) + 1
	var w := nx + 1
	# how near the road each grid point is, and the road's height there: stamped from
	# the road (every 10 m) onto the grid round it
	var dist := PackedFloat32Array()
	dist.resize(w * (nz + 1))
	dist.fill(INF)
	var near_y := PackedFloat32Array()
	near_y.resize(w * (nz + 1))
	var reach := int(340.0 / cell) + 1
	for i in range(0, st._n, 5):
		var p: Vector3 = st.pts[i]
		var cx := int((p.x - lo.x) / cell)
		var cz := int((p.z - lo.y) / cell)
		for zi in range(maxi(0, cz - reach), mini(nz, cz + reach) + 1):
			for xi in range(maxi(0, cx - reach), mini(nx, cx + reach) + 1):
				var k := zi * w + xi
				var d := Vector2(lo.x + xi * cell - p.x, lo.y + zi * cell - p.z).length()
				if d < dist[k]:
					dist[k] = d
					near_y[k] = p.y
	var hs := PackedFloat32Array()
	hs.resize(w * (nz + 1))
	for zi in nz + 1:
		for xi in nx + 1:
			var k := zi * w + xi
			var x := lo.x + xi * cell
			var z := lo.y + zi * cell
			var h := st.land_at(x, z)
			var dr: float = dist[k]
			if dr < 270.0:
				var full := minf(h, minf(near_y[k], h) - 8.0)
				h = full if dr < 170.0 else lerpf(full, h - 1.5, (dr - 170.0) / 100.0)
			elif dr < 340.0:
				h -= 1.5 * (340.0 - dr) / 70.0
			hs[k] = h
	_far = {"lo": lo, "cell": cell, "w": w, "nx": nx, "nz": nz, "hs": hs}
	var mat := _mat("terrain")
	for tz in range(0, nz, tile):
		for tx in range(0, nx, tile):
			var gb := GeoBuf.new()
			for zi in range(tz, mini(tz + tile, nz)):
				for xi in range(tx, mini(tx + tile, nx)):
					var p := []
					for c in [[0, 0], [1, 0], [1, 1], [0, 1]]:
						var X: int = xi + c[0]
						var Z: int = zi + c[1]
						p.append(Vector3(lo.x + X * cell, hs[Z * w + X], lo.y + Z * cell))
					var cl := _land_col(p[0], absf(p[2].y - p[0].y) / cell)
					# (seen from above: x right, z down the screen: 0 -> 3 -> 2 -> 1 is counter-clockwise)
					gb.quad(p[0], p[3], p[2], p[1], Vector2(p[0].x, p[0].z), Vector2(p[3].x, p[3].z), Vector2(p[2].x, p[2].z), Vector2(p[1].x, p[1].z), cl)
			var mi := MeshInstance3D.new()
			mi.name = "Land%d_%d" % [tx, tz]
			mi.mesh = gb.mesh()
			mi.material_override = mat
			add_child(mi)


## The hill over a tunnel's tubes at (s, d) (as _tunnels draws it, and the land ribbons meet
## it): from the portals' tops (10.5 m over the road) rising to the hill's own height 60 m in.
func _hill_y(s: float, d: float) -> float:
	var t := st.tunnel_at(s)
	var p := st.world_at(s, d)
	if t.is_empty():
		return p.y + 10.5
	var fa := clampf(minf(s - float(t.s0), float(t.s1) - s) / 60.0, 0.0, 1.0)
	return lerpf(p.y + 10.5, maxf(st.land_at(p.x, p.z), p.y + 10.5), fa)


## The far land's height at (x, z) as drawn (its 40 m grid, its triangles).
func _far_y(x: float, z: float) -> float:
	if _far.is_empty():
		return st.land_at(x, z)
	var fx: float = (x - _far.lo.x) / _far.cell
	var fz: float = (z - _far.lo.y) / _far.cell
	var xi := clampi(int(floor(fx)), 0, int(_far.nx) - 1)
	var zi := clampi(int(floor(fz)), 0, int(_far.nz) - 1)
	var u := clampf(fx - xi, 0.0, 1.0)
	var v := clampf(fz - zi, 0.0, 1.0)
	var w: int = _far.w
	var hs: PackedFloat32Array = _far.hs
	var h00 := hs[zi * w + xi]
	var h10 := hs[zi * w + xi + 1]
	var h01 := hs[(zi + 1) * w + xi]
	var h11 := hs[(zi + 1) * w + xi + 1]
	if u <= v:
		return h00 + u * (h11 - h01) + v * (h01 - h00)
	return h00 + u * (h10 - h00) + v * (h11 - h10)


## The ground as drawn at road coordinates (s, d) off the road: the land ribbon there (its
## rows as drawn, _rib_y), or the far land (whichever is on top). What's stood on the land
## stands on this: the land the ribbons are shaped from (st.land_at) isn't what's drawn by
## the road (its cuts and embankments, the far land kept under the ribbons, the triangles).
func _drawn_y(s: float, d: float) -> float:
	var p := st.world_at(s, d)
	var far := _far_y(p.x, p.z)
	var side := 0 if d > 0.0 else 1
	var rows: Array = _rib_y[side]
	if rows.size() < 2:
		return far
	var fi := st.wrap_s(s) / (2.0 * st.STEP)
	var r0 := mini(int(floor(fi)), rows.size() - 2)
	var t := clampf(fi - r0, 0.0, 1.0)
	var d0: float = _rib_d0[side][r0]
	var dist := (d - d0) * (1.0 if side == 0 else -1.0)
	if dist < 0.0 or dist > RIBBON[RIBBON.size() - 1]:
		return far
	var k := 0
	while k < RIBBON.size() - 2 and RIBBON[k + 1] < dist:
		k += 1
	var u: float = (dist - RIBBON[k]) / (RIBBON[k + 1] - RIBBON[k])
	var a: PackedFloat32Array = rows[r0]
	var b: PackedFloat32Array = rows[r0 + 1]
	return maxf(lerpf(lerpf(a[k], a[k + 1], u), lerpf(b[k], b[k + 1], u), t), far)


## How far (flat) (x, z) is from the road's centreline (up to ~400 m; INF further).
func _road_dist(x: float, z: float) -> float:
	var key := Vector2i(floori(x / 100.0), floori(z / 100.0))
	var best := INF
	for dx in range(-4, 5):
		for dz in range(-4, 5):
			for i in _road_grid.get(key + Vector2i(dx, dz), []):
				var p: Vector3 = st.pts[i]
				best = minf(best, Vector2(p.x - x, p.z - z).length())
	return best


## Is s within m of a tunnel's portal?
func _near_portal(s: float, m: float) -> bool:
	for t in st.tunnels:
		if absf(_ds(s, float(t.s0))) < m or absf(_ds(s, float(t.s1))) < m:
			return true
	return false


## How far (flat) (x, z) is from the nearest ramp's road (its middle; up to ~100 m, INF further).
func _ramp_dist(x: float, z: float) -> float:
	var key := Vector2i(floori(x / 50.0), floori(z / 50.0))
	var best := INF
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for p in _ramp_grid.get(key + Vector2i(dx, dz), []):
				best = minf(best, Vector2(p.x - x, p.z - z).length())
	return best


## The road's height near (x, z) (the nearest sample's).
func _near_road_y(x: float, z: float) -> float:
	var key := Vector2i(floori(x / 100.0), floori(z / 100.0))
	var best := INF
	var y := 0.0
	for dx in range(-4, 5):
		for dz in range(-4, 5):
			for i in _road_grid.get(key + Vector2i(dx, dz), []):
				var p: Vector3 = st.pts[i]
				var d := Vector2(p.x - x, p.z - z).length_squared()
				if d < best:
					best = d
					y = minf(p.y, st.land_at(x, z))
	return y


func _water() -> void:
	var c := Vector3.ZERO
	for p in st.pts:
		c += p
	c /= st.pts.size()
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	var pm := PlaneMesh.new()
	pm.size = Vector2(40000, 40000)
	pm.subdivide_width = 0
	pm.subdivide_depth = 0
	mi.mesh = pm
	mi.material_override = _mat("water")
	mi.position = Vector3(c.x, 0.0, c.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ── (filled in below) ─────────────────────────────────────────────────────

func _bridges() -> void:
	for b in st.spans:
		_suspension_bridge(b)


## A suspension bridge: two towers (legs each side of the deck, cross beams), the
## main cables (a parabola between the tower tops over the main span, down to
## the anchorages over the side spans), hangers every 15 m, the deck's fairing
## under the road and the anchorages at the ends. The big one is painted red
## (like the Golden Gate), the others white (like Tokyo's Rainbow Bridge).
func _suspension_bridge(b: Dictionary) -> void:
	var big: bool = float(b.main) > 900.0
	var paint := "steel_red" if big else "steel_white"
	var t0: float = b.towers[0]
	var t1: float = b.towers[1]
	var s0: float = b.s0
	var s1: float = b.s1
	var dr: float = st.OUTER_R + 1.6
	var dl: float = st.OUTER_L - 1.6
	var mid := (t0 + t1) * 0.5
	var i_mid := int(mid / st.STEP)
	var top_h: float = float(b.tower_h)
	var deck_t0: float = st.world_at(t0, 0.0).y
	var deck_t1: float = st.world_at(t1, 0.0).y
	var top0 := deck_t0 + top_h
	var top1 := deck_t1 + top_h
	var low := maxf(deck_t0, deck_t1) + 9.0          # the cables' lowest, mid-span
	# the towers
	for t in [[t0, top0], [t1, top1]]:
		var ts: float = t[0]
		var top: float = t[1]
		var i := int(ts / st.STEP)
		var bas := Basis(Vector3.UP, -st.heading_at(ts))
		var legs := []
		for d in [dl, dr]:
			var base := st.world_at(ts, d)
			var foot := minf(st.land_at(base.x, base.z), 0.0) - 2.0
			var h := top - foot
			# a leg: wider at the foot, in three stacked pieces
			for k in 3:
				var y0 := foot + h * k / 3.0
				var y1 := foot + h * (k + 1) / 3.0
				var wsc := 1.0 - 0.18 * k
				_buf(i, paint).box(Vector3(base.x, (y0 + y1) * 0.5, base.z), Vector3(5.0 * wsc, y1 - y0, 7.0 * wsc), bas)
			legs.append(Vector3(base.x, 0.0, base.z))
		# cross beams: under the deck, part way up, at the top
		var c: Vector3 = (legs[0] + legs[1]) * 0.5
		var span_w: float = legs[0].distance_to(legs[1])
		var deck_y: float = st.world_at(ts, 0.0).y
		for y in [deck_y - 6.0, deck_y + (top - deck_y) * 0.55, top - 4.0]:
			_buf(i, paint).box(Vector3(c.x, y, c.z), Vector3(span_w, 5.0, 4.0), bas)
		# an aircraft warning light on top
		_buf(i, "beacon").box(Vector3(legs[0].x, top + 1.0, legs[0].z), Vector3(1.2, 1.2, 1.2))
		_buf(i, "beacon").box(Vector3(legs[1].x, top + 1.0, legs[1].z), Vector3(1.2, 1.2, 1.2))
	# the cables, each side: anchorage -> tower -> (main span) -> tower -> anchorage
	for d in [dl, dr]:
		var path := PackedVector3Array()
		var hang := []                                # [s, cable point]
		var anch0 := st.world_at(s0, d) + Vector3.UP * 3.0
		var anch1 := st.world_at(s1, d) + Vector3.UP * 3.0
		var tw0 := st.world_at(t0, d)
		tw0.y = top0
		var tw1 := st.world_at(t1, d)
		tw1.y = top1
		var n_side := 24
		for k in n_side + 1:                          # the side span: a shallow curve
			var u := float(k) / n_side
			var s := lerpf(s0, t0, u)
			var p := st.world_at(s, d)
			p.y = lerpf(anch0.y, tw0.y, u) - (t0 - s0) / 40.0 * 4.0 * u * (1.0 - u)
			path.append(p)
			hang.append([s, p])
		var n_main := 80
		for k in range(1, n_main + 1):                # the main span: the parabola
			var u := float(k) / n_main
			var s := lerpf(t0, t1, u)
			var p := st.world_at(s, d)
			var chord := lerpf(top0, top1, u)
			p.y = chord - (chord - low) * (1.0 - pow(2.0 * u - 1.0, 2.0))
			path.append(p)
			hang.append([s, p])
		for k in range(1, n_side + 1):
			var u := float(k) / n_side
			var s := lerpf(t1, s1, u)
			var p := st.world_at(s, d)
			p.y = lerpf(tw1.y, anch1.y, u) - (s1 - t1) / 40.0 * 4.0 * u * (1.0 - u)
			path.append(p)
			hang.append([s, p])
		var gb := _buf(i_mid, "cable")
		gb.tube(path, 0.55 if big else 0.45, 8)
		# hangers every 15 m: from the cable straight down to the deck's edge
		var s := s0 + 15.0
		var hk := 0
		while s < s1 - 10.0:
			while hk < hang.size() - 2 and hang[hk + 1][0] < s:
				hk += 1
			var a: Array = hang[hk]
			var c2: Array = hang[mini(hk + 1, hang.size() - 1)]
			var f := clampf((s - float(a[0])) / maxf(float(c2[0]) - float(a[0]), 0.01), 0.0, 1.0)
			var top: Vector3 = (a[1] as Vector3).lerp(c2[1], f)
			var foot := st.world_at(s, d) + Vector3.UP * 0.8
			if top.y - foot.y > 1.5 and absf(s - t0) > 4.0 and absf(s - t1) > 4.0:
				_buf(int(s / st.STEP), "cable").box((top + foot) * 0.5, Vector3(0.14, top.y - foot.y, 0.14))
			s += 15.0
		# the anchorages: concrete blocks the cables run into, beside the deck (their inner face
		# just clear of the parapet: centred on the cable they stood on the outer lanes), solid
		for e in [[s0, anch0], [s1, anch1]]:
			var p: Vector3 = e[1] + st.right_at(float(e[0])) * (7.3 if d > 0.0 else -7.3)
			var ground := maxf(st.land_at(p.x, p.z), -3.0)
			var h: float = p.y + 4.0 - ground
			var ai := int(float(e[0]) / st.STEP)
			var ab := Basis(Vector3.UP, -st.heading_at(float(e[0])))
			_buf(ai, "concrete").box(Vector3(p.x, ground + h * 0.5, p.z), Vector3(16.0, h, 22.0), ab)
			_body(ai, "concrete").box(Vector3(p.x, ground + h * 0.5, p.z), Vector3(16.0, h, 22.0), ab, Color.WHITE, true)
	# the deck's fairing: a streamlined box under the road, its sides sloping in
	var i0 := int(s0 / st.STEP)
	var i1 := int(s1 / st.STEP)
	for i in range(i0, i1):
		var sa := i * st.STEP
		var sb := sa + st.STEP
		for side in [1.0, -1.0]:
			var d_out: float = (st.OUTER_R + 2.2) if side > 0.0 else (st.OUTER_L - 2.2)
			var d_in: float = (st.OUTER_R - 1.5) if side > 0.0 else (st.OUTER_L + 1.5)
			var a0 := st.world_at(sa, d_out) + Vector3.UP * -1.2
			var a1 := st.world_at(sa, d_in) + Vector3.UP * -4.5
			var b0 := st.world_at(sb, d_out) + Vector3.UP * -1.2
			var b1 := st.world_at(sb, d_in) + Vector3.UP * -4.5
			var top_a := st.world_at(sa, d_out) + Vector3.UP * 0.2
			var top_b := st.world_at(sb, d_out) + Vector3.UP * 0.2
			var gb := _buf(i, paint)
			if side > 0.0:
				gb.quad(top_a, top_b, b0, a0, Vector2(sa, 0), Vector2(sb, 0), Vector2(sb, 1.4), Vector2(sa, 1.4))
				gb.quad(a0, b0, b1, a1, Vector2(sa, 0), Vector2(sb, 0), Vector2(sb, 3.8), Vector2(sa, 3.8))
			else:
				gb.quad(top_a, a0, b0, top_b, Vector2(sa, 0), Vector2(sa, 1.4), Vector2(sb, 1.4), Vector2(sb, 0))
				gb.quad(a0, a1, b1, b0, Vector2(sa, 0), Vector2(sa, 3.8), Vector2(sb, 3.8), Vector2(sb, 0))
			# the deck between the fairing and the parapet (the walkway the cables stand on)
			var w0 := st.world_at(sa, (st.OUTER_R + 0.35) if side > 0.0 else (st.OUTER_L - 0.35))
			var w1 := st.world_at(sb, (st.OUTER_R + 0.35) if side > 0.0 else (st.OUTER_L - 0.35))
			if side > 0.0:
				_buf(i, "concrete").quad(w0, w1, top_b, top_a, Vector2(sa, 0), Vector2(sb, 0), Vector2(sb, 2), Vector2(sa, 2))
			else:
				_buf(i, "concrete").quad(w0, top_a, top_b, w1, Vector2(sa, 0), Vector2(sa, 2), Vector2(sb, 2), Vector2(sb, 0))
		# the underside
		var u0 := st.world_at(sa, st.OUTER_L + 1.5) + Vector3.UP * -4.5
		var u1 := st.world_at(sa, st.OUTER_R - 1.5) + Vector3.UP * -4.5
		var v0 := st.world_at(sb, st.OUTER_L + 1.5) + Vector3.UP * -4.5
		var v1 := st.world_at(sb, st.OUTER_R - 1.5) + Vector3.UP * -4.5
		_buf(i, paint).quad(u0, v0, v1, u1, Vector2(sa, 0), Vector2(sb, 0), Vector2(sb, 30), Vector2(sa, 30))


## The tunnels: twin tubes (ours and the other carriageway's, a wall between),
## tiled walls and an arched ceiling, a continuous row of lights each side of it
## (no flicker at any speed), concrete portals at both ends, the hill over them.
func _tunnels() -> void:
	for t in st.tunnels:
		var s0: float = t.s0
		var s1: float = t.s1
		var i0 := int(s0 / st.STEP)
		var i1 := int(s1 / st.STEP)
		var wall_r: float = st.EDGE + st.SHOULDER_R + 0.6
		var wall_l: float = st.ONCOMING_D - st.EDGE - st.SHOULDER_R - 0.6
		for i in range(i0, i1):
			var sa := i * st.STEP
			var sb := sa + st.STEP
			for tube in [[st.MEDIAN_D + 0.3, wall_r], [wall_l, st.MEDIAN_D - 0.3]]:
				var dl: float = tube[0]
				var drr: float = tube[1]
				var w := drr - dl
				# the inside, left wall bottom round to the right wall bottom: seen from inside
				var prof := [Vector2(0.0, 0.0), Vector2(0.0, 5.0)]
				for k in range(1, 8):
					var a := PI * k / 8.0
					prof.append(Vector2(w * 0.5 - cos(a) * w * 0.5, 5.0 + sin(a) * 2.6))
				prof.append(Vector2(w, 5.0))
				prof.append(Vector2(w, 0.0))
				var ra := PackedVector3Array()
				var rb := PackedVector3Array()
				var vs := PackedFloat32Array()
				var v := 0.0
				for k in prof.size():
					var p: Vector2 = prof[k]
					ra.append(st.world_at(sa, dl + p.x) + Vector3.UP * p.y)
					rb.append(st.world_at(sb, dl + p.x) + Vector3.UP * p.y)
					if k > 0:
						v += (p - prof[k - 1]).length()
					vs.append(v)
				# (a ribbon faces "up" for rows left to right; the inside of the tube faces in: rows reversed)
				ra.reverse()
				rb.reverse()
				var vr := vs.duplicate()
				vr.reverse()
				_buf(i, "tunnel").ribbon(ra, rb, sa, sb, vr)
				# the walls' collision: the low part
				var wl0 := st.world_at(sa, dl)
				var wl1 := st.world_at(sb, dl)
				var wr0 := st.world_at(sa, drr)
				var wr1 := st.world_at(sb, drr)
				var c := _body(i, "concrete")
				c.quad(wl0, wl1, wl1 + Vector3.UP * 4.0, wl0 + Vector3.UP * 4.0, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color.WHITE, true)
				c.quad(wr0, wr0 + Vector3.UP * 4.0, wr1 + Vector3.UP * 4.0, wr1, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color.WHITE, true)
				# the lights: two continuous rows under the ceiling
				for f in [0.3, 0.7]:
					var l0 := st.world_at(sa, dl + w * f) + Vector3.UP * (5.0 + 2.6 * sin(PI * f) - 0.25)
					var l1 := st.world_at(sb, dl + w * f) + Vector3.UP * (5.0 + 2.6 * sin(PI * f) - 0.25)
					var side := st.right_at(sa) * 0.25
					_buf(i, "lamp").quad(l0 - side, l1 - side, l1 + side, l0 + side, Vector2(sa, 0), Vector2(sb, 0), Vector2(sb, 1), Vector2(sa, 1))
			# the wall between the tubes (5 cm behind their walls: it was flush with them, flickering)
			var m0 := st.world_at(sa, st.MEDIAN_D)
			var m1 := st.world_at(sb, st.MEDIAN_D)
			_buf(i, "concrete").box((m0 + m1) * 0.5 + Vector3.UP * 3.8, Vector3(0.5, 7.6, st.STEP + 0.02), Basis(Vector3.UP, -st.heading_at(sa)))
			# the hill over the tubes, out to where the land ribbons start (the same points, the
			# same heights: _hill_y; it fell short of them, gaps of 4-11 m over the tubes' ends)
			var ra2 := PackedVector3Array()
			var rb2 := PackedVector3Array()
			var vs2 := PackedFloat32Array()
			var cols := PackedColorArray()
			var ea := _edges(i)
			for d in [ea.x - 0.45, (wall_l + wall_r) * 0.5, ea.y + 0.45]:
				var pa := st.world_at(sa, d)
				var pb := st.world_at(sb, d)
				pa.y = _hill_y(sa, d)
				pb.y = _hill_y(sb, d)
				ra2.append(pa)
				rb2.append(pb)
				vs2.append(d)
				cols.append(_land_col(pa, 0.2))
			_buf(i, "terrain").ribbon(ra2, rb2, sa, sb, vs2, Color.WHITE, false, cols, cols)
		for e in [[s0, 1.0], [s1, -1.0]]:
			_portal(float(e[0]), float(e[1]), wall_l, wall_r)


const PORTAL_T := 1.2                # m: a portal's (and its wing walls') thickness

## A tunnel's portal at ps (into: which way along the road the tubes go in from it): a
## concrete face 1.2 m thick round both tubes' arched mouths, up to the hill over them (and a
## coping 0.4 m over it), and its wing walls out each side across the cut, holding the hill
## back: the land steps up 10.5 m at the portal (the cut's floor at the road, the hill's over
## the tubes, _ribbon), and a wall stands in front of the step wherever there is one, its top
## along the hill's side of it, sinking into the cut's slope where the step runs out.
func _portal(ps: float, into: float, wall_l: float, wall_r: float) -> void:
	var i := int(ps / st.STEP)
	var fwd := st.forward_at(ps)
	var front := fwd * (-into * PORTAL_T * 0.5)          # (the face toward the open cut)
	var facing := fwd * -into
	var gb := _buf(i, "concrete")
	# over the mouths: from the arches' crowns (7.6 m) up to the coping
	var over: Array = []
	for d in [wall_l, st.MEDIAN_D, wall_r]:
		over.append([d, st.world_at(ps, d).y + 7.6, _hill_y(ps, d) + 0.4])
	_wall_slab(gb, null, ps, front, facing, over, true)
	# round each tube's arch, up to 7.6 m; the pier between the tubes
	for tube in [[st.MEDIAN_D + 0.3, wall_r], [wall_l, st.MEDIAN_D - 0.3]]:
		var dl: float = tube[0]
		var w: float = tube[1] - dl
		var arch: Array = []
		for k in 9:
			var a := PI * k / 8.0
			var d := dl + w * 0.5 - cos(a) * w * 0.5
			var y0 := st.world_at(ps, d).y
			arch.append([d, y0 + 5.0 + sin(a) * 2.6, y0 + 7.6])
		_wall_slab(gb, null, ps, front, facing, arch, false)
	_wall_slab(gb, null, ps, front, facing, [[st.MEDIAN_D - 0.3, st.world_at(ps, st.MEDIAN_D - 0.3).y, st.world_at(ps, st.MEDIAN_D - 0.3).y + 7.6],
		[st.MEDIAN_D + 0.3, st.world_at(ps, st.MEDIAN_D + 0.3).y, st.world_at(ps, st.MEDIAN_D + 0.3).y + 7.6]], false)
	# the wing walls: the land's rows each side of the step (the cut's, the hill's), as _ribbon
	# draws them at the portal; the wall from the tube's outer wall out along them
	var e := _edges(i)
	for side in [1.0, -1.0]:
		var cut: Array = _rib_row(ps, e, _ground_f[posmod(i, st._n)], side, false)
		var hill: Array = _rib_row(ps, e, 1.0, side, true)
		var d0: float = cut[2]
		var start: float = absf((wall_r if side > 0.0 else wall_l) - d0)
		var pts: Array = []
		for k in range(1, RIBBON.size()):
			if RIBBON[k] <= start and k < RIBBON.size() - 1:
				continue
			var lo: float = RIBBON[k - 1]
			var hi: float = RIBBON[k]
			for dist in ([start, hi] if pts.is_empty() else [hi]):
				var u := clampf((dist - lo) / (hi - lo), 0.0, 1.0)
				var a: float = lerpf(cut[0][k - 1].y, cut[0][k].y, u)
				var b: float = lerpf(hill[0][k - 1].y, hill[0][k].y, u)
				var step := maxf(b - a, 0.0)
				pts.append([d0 + side * dist, a - 0.5, a + step + 0.4 * clampf(step, 0.0, 1.0)])
			if (hill[0][k].y - cut[0][k].y) < 0.05:
				break
		if side < 0.0:
			pts.reverse()
		_wall_slab(gb, _body(i, "concrete"), ps, front, facing, pts, true, [side < 0.0, side > 0.0])


## A slab of wall across the road at ps, 1.2 m thick: pts [[d, bottom y, top y]] (d rising),
## its face (toward `facing`, `front` off ps) and, if `full`, its back and its top; its ends
## where asked (ends: [the first point's, the last's]); collision for its face if `body`.
func _wall_slab(gb: GeoBuf, body, ps: float, front: Vector3, facing: Vector3, pts: Array, full: bool, ends := [false, false]) -> void:
	var at := func(k: int, y: float, f: float) -> Vector3:
		var p := st.world_at(ps, float(pts[k][0]))
		return Vector3(p.x, y, p.z) + front * f
	for k in pts.size() - 1:
		var d0: float = pts[k][0]
		var d1: float = pts[k + 1][0]
		var faces := [[1.0, facing]]
		if full:
			faces.append([-1.0, -facing])
		for fc in faces:
			var a: Vector3 = at.call(k, pts[k][1], fc[0])
			var b: Vector3 = at.call(k + 1, pts[k + 1][1], fc[0])
			var c: Vector3 = at.call(k + 1, pts[k + 1][2], fc[0])
			var d: Vector3 = at.call(k, pts[k][2], fc[0])
			_quad_to(gb, a, b, c, d, fc[1], Vector2(d0, a.y), Vector2(d1, b.y), Vector2(d1, c.y), Vector2(d0, d.y))
			if body != null and fc[0] > 0.0:
				_quad_to(body, a, b, c, d, fc[1], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, true)
		if full:
			# its top
			var t0: Vector3 = at.call(k, pts[k][2], 1.0)
			var t1: Vector3 = at.call(k + 1, pts[k + 1][2], 1.0)
			var t2: Vector3 = at.call(k + 1, pts[k + 1][2], -1.0)
			var t3: Vector3 = at.call(k, pts[k][2], -1.0)
			_quad_to(gb, t0, t1, t2, t3, Vector3.UP, Vector2(d0, 0.0), Vector2(d1, 0.0), Vector2(d1, PORTAL_T), Vector2(d0, PORTAL_T))
	for k in [0, pts.size() - 1]:
		if ends[0 if k == 0 else 1]:
			var a: Vector3 = at.call(k, pts[k][1], 1.0)
			var b: Vector3 = at.call(k, pts[k][1], -1.0)
			var c: Vector3 = at.call(k, pts[k][2], -1.0)
			var d: Vector3 = at.call(k, pts[k][2], 1.0)
			var p0: Vector3 = at.call(k, 0.0, 0.0)
			var p1: Vector3 = at.call(1 if k == 0 else k - 1, 0.0, 0.0)
			var out := (p0 - p1).normalized()
			_quad_to(gb, a, b, c, d, out, Vector2(0.0, a.y), Vector2(PORTAL_T, b.y), Vector2(PORTAL_T, c.y), Vector2(0.0, d.y))


## A quad, its corners turned so that it faces `facing` (GeoBuf.quad: counter-clockwise seen
## from the front).
func _quad_to(gb: GeoBuf, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3, ua: Vector2, ub: Vector2,
		uc: Vector2, ud: Vector2, collide := false) -> void:
	if (c - a).cross(d - b).dot(facing) >= 0.0:                # (its diagonals: a corner can be a point)
		gb.quad(a, b, c, d, ua, ub, uc, ud, Color.WHITE, collide)
	else:
		gb.quad(a, d, c, b, ua, ud, uc, ub, Color.WHITE, collide)


func _roadside() -> void:
	_lamp_posts()
	_gantries()
	_overpasses()


## Lamp posts on the median every 48 m where the road's up off the ground (the city's
## viaduct, the bridges) and through the city: a pole, an arm over each carriageway.
func _lamp_posts() -> void:
	var lit: bool = _wm != null and _wm.night_amount >= 0.05
	var post := _post_mesh(not lit)
	var per_chunk := {}
	lamp_heads.clear()
	var s := 10.0
	while s < st.length:
		var sup := st.support_at(s)
		if (sup == "viaduct" or sup == "bridge" or st.zone_at(s) == "city") and sup != "tunnel":
			var p := st.world_at(s, st.MEDIAN_D)
			var xf := Transform3D(Basis(Vector3.UP, -st.heading_at(s)), p)
			var c := int(int(s / st.STEP) / CH)
			if not per_chunk.has(c):
				per_chunk[c] = []
			per_chunk[c].append(xf)
			for side in [1.0, -1.0]:                     # (an arm over each carriageway)
				var head: Vector3 = xf * Vector3(side * 5.0, 10.76, 0.0)
				# the road under it, and its slope there (the pool lies on it, not buried by the cross-fall)
				var d: float = st.MEDIAN_D + 5.0
				if st.world_at(s, st.MEDIAN_D - 5.0).distance_to(head) < st.world_at(s, d).distance_to(head):
					d = st.MEDIAN_D - 5.0
				var g := st.world_at(s, d)
				var up := (st.world_at(s, d + 1.0) - st.world_at(s, d - 1.0)).cross(st.world_at(s + 1.0, d) - g).normalized()
				if up.y < 0.0:
					up = -up
				lamp_heads.append({"s": s, "head": head, "ground": g, "up": up, "radius": 25.0, "arm": xf.basis.x * side})   # (11 m up, 48 m apart: the pools meet; the glass along its arm)
		s += 48.0
	for c in per_chunk:
		_multimesh(post, per_chunk[c], "Lamps%03d" % c, ROAD_RANGE)
	lamp_heads.append_array(_toll_lamp_heads())          # (the toll plaza's canopy: a light over each lane)
	lamp_heads.append_array(_station_lamp_heads())       # (the gas station's canopy and its car park)
	if lit:
		street_lamps = _wm.street_lights(self, lamp_heads)


## A lamp post's mesh (its origin at its foot on the median): an 11 m pole, two arms
## reaching 5 m over each carriageway, a lamp head at each end (unlit; lit, StreetLamps
## draws the glowing glass under it).
func _post_mesh(heads := true) -> ArrayMesh:
	var steel := GeoBuf.new()
	var lamp := GeoBuf.new()
	steel.box(Vector3(0, 5.6, 0), Vector3(0.22, 11.2, 0.22))
	for side in [1.0, -1.0]:
		steel.box(Vector3(side * 2.6, 11.0, 0), Vector3(5.2, 0.14, 0.14))
		if heads:
			lamp.box(Vector3(side * 5.0, 10.85, 0), Vector3(0.9, 0.18, 0.35))
		else:
			steel.box(Vector3(side * 5.0, 10.95, 0), Vector3(0.9, 0.12, 0.35))   # (the housing over the glass)
	return _mesh2(steel, "steel", lamp, "post_lamp")


func _mesh2(a: GeoBuf, ka: String, b: GeoBuf, kb: String) -> ArrayMesh:
	var m := ArrayMesh.new()
	for e in [[a, ka], [b, kb]]:
		var gb: GeoBuf = e[0]
		if gb.is_empty():
			continue
		var am := gb.mesh()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, am.surface_get_arrays(0))
		m.surface_set_material(m.get_surface_count() - 1, _mat(e[1]))
	return m


func _multimesh(mesh: Mesh, xfs: Array, nm: String, range_end: float, colors := []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
		if mm.use_colors:
			mm.set_instance_color(k, colors[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.visibility_range_end = range_end
	mmi.visibility_range_end_margin = 150.0
	add_child(mmi)
	return mmi


## Sign gantries over our carriageway before each exit: a steel beam on two posts,
## a green board with the exit's name and how far.
func _gantries() -> void:
	for g in st.gantries:
		var s: float = g.s
		if st.tunnel_at(s, 30.0).size() > 0:
			continue
		var i := int(s / st.STEP)
		var bas := Basis(Vector3.UP, -st.heading_at(s))
		var a := st.world_at(s, st.MEDIAN_D + 0.6)
		# the outer post past the road's edge where it is (an extra lane's: it stood in the lane),
		# on a viaduct on its parapet (it stood in the air beside the deck)
		var on_deck: bool = st.support_at(s) in ["viaduct", "bridge"]
		var b := st.world_at(s, _edges(i).y + (0.575 if on_deck else 1.2))
		for p in [a, b]:
			_buf(i, "steel").box(p + Vector3.UP * 3.6, Vector3(0.4, 7.2, 0.4), bas)
		var mid := (a + b) * 0.5 + Vector3.UP * 7.0
		_buf(i, "steel").box(mid, Vector3(a.distance_to(b), 0.6, 0.8), bas)
		var board := st.world_at(s, st.LANE_W) + Vector3.UP * 6.2
		board.y = mid.y - 1.1
		_buf(i, "sign").box(board, Vector3(9.0, 2.6, 0.2), bas)
		var lbl := Label3D.new()
		lbl.text = "%s\n%s" % [g.text, "%d km" % int(g.km) if float(g.km) > 0.0 else "EXIT"]
		lbl.font_size = 96
		lbl.pixel_size = 0.0085                         # (two lines inside the 2.6 m board)
		lbl.outline_size = 0
		lbl.modulate = Color(0.95, 0.95, 0.92)
		lbl.double_sided = false
		# facing the drivers coming up to it (back along the road: a Label3D reads from its +Z,
		# which the road's basis turns backward)
		lbl.transform = Transform3D(bas, board + st.forward_at(s) * -0.12)
		lbl.visibility_range_end = 900.0
		add_child(lbl)


# ── the toll plaza ────────────────────────────────────────────────────────

## Is s within the plaza's islands (the median barrier gives way to the middle island)?
func _toll_island_at(s: float) -> bool:
	return not st.toll.is_empty() and absf(_ds(s, float(st.toll.s))) < float(st.toll.half) + 0.5


## The road's frame at (s, d): x across (to the right), y its up (banking, grade), -z along.
func _frame(s: float, d: float) -> Basis:
	var f := (st.world_at(s + 1.0, d) - st.world_at(s - 1.0, d)).normalized()
	var r := f.cross(st.up_at(s)).normalized()
	return Basis(r, r.cross(f).normalized(), -f)


## A box standing on the road at (s, d) (lift: its bottom that far up): size = across, up,
## along; in material `key` (a colour: the toll's painted materials take it), solid if asked.
func _road_box(s: float, d: float, size: Vector3, key: String, col := Color.WHITE, solid := false, lift := 0.0, turn := 0.0) -> void:
	var bas := _frame(s, d)
	var at := st.world_at(s, d) + bas.y * (size.y * 0.5 + lift)
	if turn != 0.0:
		bas = bas * Basis(Vector3.BACK, turn)                 # (turned about the road's line: a sign's X, a raised arm)
	var i := int(st.wrap_s(s) / st.STEP)
	_buf(i, key).box(at, size, bas, col)
	if solid:
		_body(i, "concrete").box(at, size, bas, Color.WHITE, true)


## The plaza's islands across both carriageways: [{d, w, ours (a booth for our lane to its
## right), theirs (for theirs, to its left as we look)}]. They stand on the fanned-out lane
## lines (LoopGen.toll_d), the outer ones on the shoulders, the middle one on the median.
func _toll_islands() -> Array:
	var L: float = st.LANE_W * st.TOLL_SPREAD
	var o: float = st.ONCOMING_D
	var w: float = st.TOLL_ISLAND_W
	return [{"d": 2.0 * L, "w": w, "ours": false, "theirs": false},
		{"d": L, "w": w, "ours": true, "theirs": false}, {"d": 0.0, "w": w, "ours": true, "theirs": false},
		{"d": -L, "w": w, "ours": true, "theirs": false},
		{"d": st.MEDIAN_D, "w": 1.3, "ours": true, "theirs": true},
		{"d": o + L, "w": w, "ours": false, "theirs": true}, {"d": o, "w": w, "ours": false, "theirs": true},
		{"d": o - L, "w": w, "ours": false, "theirs": true}, {"d": o - 2.0 * L, "w": w, "ours": false, "theirs": false}]


## Each lane's middle at the booths: [{d, lane (0: the slow, right-hand one of its carriageway), dir}].
func _toll_lanes() -> Array:
	var out: Array = []
	var s0: float = st.toll.s
	for k in 4:
		var base: float = st.EDGE - st.LANE_W * (k + 0.5)
		out.append({"d": st.toll_d(base, s0), "base": base, "lane": k, "dir": 1})
		out.append({"d": st.toll_d(st.ONCOMING_D - base, s0), "base": st.ONCOMING_D - base, "lane": k, "dir": -1})
	return out


## The canopy's lights (StreetLamps' pools at night): one over each lane, both carriageways.
func _toll_lamp_heads() -> Array:
	var out: Array = []
	if st.toll.is_empty():
		return out
	var s0: float = st.toll.s
	for ln in _toll_lanes():
		var g := st.world_at(s0, float(ln.d))
		out.append({"s": s0, "head": g + st.up_at(s0) * TOLL_CANOPY_H, "ground": g, "up": st.up_at(s0), "radius": 11.0})
	return out


const TOLL_CANOPY_H := 5.6           # m: the canopy's underside over the road (the trucks' 4.1 m and some)
const TOLL_CANOPY_L := 15.0          # m along the road
const TOLL_COLS := {"white": Color(0.9, 0.9, 0.88), "grey": Color(0.55, 0.56, 0.58), "dark": Color(0.08, 0.08, 0.09),
	"yellow": Color(1.0, 0.78, 0.05), "red": Color(0.8, 0.08, 0.06), "green": Color(0.1, 0.55, 0.3),
	"purple": Color(0.36, 0.2, 0.55), "kerb": Color(0.78, 0.78, 0.75)}

## THE TOLL PLAZA (LoopGen.toll): islands on the fanned-out lane lines (solid concrete, a
## yellow crash cushion at each nose the traffic comes at), a booth on each lane's driver's
## side (lit windows at night), a canopy over both carriageways on columns, over each lane a
## signal (a green arrow open, a red X closed) and its board (ETC / CASH / CLOSED, or the
## event's), cameras and readers on the canopy, barrier arms past the booths (up when open;
## down and solid on a closed lane, a line of cones closing it off before), signs before it
## both ways, and lights under the canopy. The layouts: "open" (every lane open, the gates
## up: full speed through), "mixed" (each carriageway's right-hand lane closed, the traffic
## out of it beforehand and slowed through; Traffic minds it), "event" (all open, the
## boards and the canopy the race's).
func _toll_plaza() -> void:
	if st.toll.is_empty():
		return
	var s0: float = st.toll.s
	var H: float = st.toll.half
	var layout: String = st.toll.layout
	var C := TOLL_COLS
	# the islands: a kerbed concrete slab following the road, its ends tapered; a crash cushion
	# (yellow and black) at the nose the traffic comes at
	for isl in _toll_islands():
		var d: float = isl.d
		var w: float = isl.w
		var s := s0 - H
		while s < s0 + H - 0.01:
			_road_box(s + 2.0, d, Vector3(w, 0.25, 4.02), "toll_paint", C.kerb, true)
			s += 4.0
		for e in [-1.0, 1.0]:
			_road_box(s0 + e * (H + 0.6), d, Vector3(w * 0.65, 0.22, 1.2), "toll_paint", C.kerb, true)
		var noses: Array = []
		if isl.ours or (d > st.MEDIAN_D and d > 0.0):
			noses.append(-1.0)
		if isl.theirs or d < st.ONCOMING_D - 1.0:
			noses.append(1.0)
		for e in noses:
			for k in 6:                                      # (striped: 0.5 m bands)
				var u: float = H + 1.25 + k * 0.5
				_road_box(s0 + e * u, d, Vector3(minf(w, 0.9) - 0.05, 0.9, 0.5), "toll_paint", C.yellow if k % 2 == 0 else C.dark, true)
	# the booths: a cabin on each lane's driver's side (left of the lane, for each carriageway's
	# way), its windows lit at night; before the barrier arm
	for isl in _toll_islands():
		for side in [1, -1]:
			if (side == 1 and not isl.ours) or (side == -1 and not isl.theirs):
				continue
			var bs: float = s0 - 3.0 * side
			_road_box(bs, isl.d, Vector3(0.82, 1.05, 2.2), "toll_paint", C.white, false, 0.25)
			_road_box(bs, isl.d, Vector3(0.84, 1.0, 2.0), "toll_glass", Color.WHITE, false, 1.3)
			_road_box(bs, isl.d, Vector3(0.82, 0.25, 2.2), "toll_paint", C.white, false, 2.3)
			_road_box(bs, isl.d, Vector3(1.1, 0.12, 2.6), "toll_paint", C.grey, false, 2.55)
			_body(int(st.wrap_s(bs) / st.STEP), "concrete").box(st.world_at(bs, isl.d) + _frame(bs, isl.d).y * 1.55,
				Vector3(0.82, 2.6, 2.2), _frame(bs, isl.d), Color.WHITE, true)
	# the canopy on its columns (two on each island), its fascia over each approach
	var d_l: float = st.ONCOMING_D - 2.0 * st.LANE_W * st.TOLL_SPREAD - 1.0
	var d_r: float = 2.0 * st.LANE_W * st.TOLL_SPREAD + 1.0
	var d_mid := (d_l + d_r) * 0.5
	var span := d_r - d_l
	for isl in _toll_islands():
		for e in [-1.0, 1.0]:
			_road_box(s0 + e * (TOLL_CANOPY_L * 0.5 - 1.2), isl.d, Vector3(0.4, TOLL_CANOPY_H + 0.2, 0.4), "steel", Color.WHITE, true, 0.25)
	var base_y := TOLL_CANOPY_H + 0.25
	_road_box(s0, d_mid, Vector3(span, 0.9, TOLL_CANOPY_L), "toll_paint", C.white, false, base_y)
	for e in [-1.0, 1.0]:
		_road_box(s0 + e * (TOLL_CANOPY_L * 0.5 - 0.15), d_mid, Vector3(span + 0.2, 1.7, 0.3), "toll_paint", C.white, false, base_y - 0.5)
		_road_box(s0 + e * (TOLL_CANOPY_L * 0.5 - 0.1), d_mid, Vector3(span + 0.22, 0.32, 0.3),
			"toll_paint", C.purple if layout != "event" else C.red, false, base_y - 0.45)
	# its lights: a strip over each lane
	for ln in _toll_lanes():
		_road_box(s0, float(ln.d), Vector3(0.5, 0.06, TOLL_CANOPY_L - 3.0), "post_lamp", Color.WHITE, false, base_y - 0.07)
	# over each lane, on the fascia it's driven at: the signal, the board, a camera; under the
	# canopy, the reader; past the booth, the barrier arm
	for ln in _toll_lanes():
		var dir: int = ln.dir
		var d: float = ln.d
		var closed: bool = st.toll_closed(int(ln.lane))
		var face: float = s0 - dir * (TOLL_CANOPY_L * 0.5 + 0.05)
		# the signal: a green arrow pointing down (open), a red X (closed)
		_road_box(face, d + 0.75 * dir, Vector3(0.9, 0.9, 0.12), "toll_paint", C.dark, false, base_y - 0.4)
		if closed:
			for a in [PI / 4.0, -PI / 4.0]:
				_road_box(face - dir * 0.08, d + 0.75 * dir, Vector3(0.75, 0.14, 0.05), "toll_red", Color.WHITE, false, base_y - 0.02, a)
		else:
			_road_box(face - dir * 0.08, d + 0.75 * dir, Vector3(0.14, 0.42, 0.05), "toll_green", Color.WHITE, false, base_y - 0.15)
			for a in [PI / 4.0, -PI / 4.0]:
				_road_box(face - dir * 0.08, d + 0.75 * dir + (0.09 if a > 0.0 else -0.09) * dir, Vector3(0.36, 0.12, 0.05), "toll_green", Color.WHITE, false, base_y - 0.14, a * dir)
		# the board: what the lane is
		var text := "ETC"
		if layout == "event":
			text = "GO"
		elif closed:
			text = "CLOSED"
		elif layout == "mixed":
			text = "ETC · 60"
		var bcol: Color = C.purple if text.begins_with("ETC") else (C.green if layout == "event" else C.red)
		_road_box(face, d - 0.55 * dir, Vector3(1.5, 0.75, 0.12), "toll_paint", bcol, false, base_y + 0.1)
		_toll_label(text, face - dir * 0.09, d - 0.55 * dir, base_y + 0.47, dir, minf(0.0055, 1.35 / (text.length() * 0.58 * 96.0)))
		# a camera on the fascia, a reader under the canopy
		_road_box(face - dir * 0.3, d + 1.5 * dir, Vector3(0.25, 0.22, 0.45), "toll_paint", C.dark, false, base_y - 0.72)
		_road_box(s0 - dir * 4.5, d, Vector3(0.8, 0.5, 0.08), "toll_paint", C.grey, false, base_y - 0.5)
		# the barrier arm: on the booth's island (to the lane's driver's side), past the booth
		var gs: float = s0 + dir * 3.5
		var post_d: float = d - dir * (st.LANE_W * st.TOLL_SPREAD * 0.5)
		_road_box(gs, post_d, Vector3(0.32, 1.0, 0.32), "toll_paint", C.yellow, true, 0.25)
		if closed:
			# down across the lane, solid (and a line of cones closing the lane off before it)
			for k in 6:
				_road_box(gs, post_d + dir * (0.35 + 0.5 * k), Vector3(0.5, 0.1, 0.1), "toll_paint", C.red if k % 2 == 0 else C.white, false, 1.0)
			var gb := _frame(gs, d)                          # (the arm and its posts, solid: a wall across the lane)
			_body(int(st.wrap_s(gs) / st.STEP), "concrete").box(st.world_at(gs, d) + gb.y * 0.6,
				Vector3(st.LANE_W * st.TOLL_SPREAD - st.TOLL_ISLAND_W - 0.1, 1.2, 0.3), gb, Color.WHITE, true)
			_toll_cones(float(ln.base), dir)
		else:
			for k in 6:
				_road_box(gs, post_d, Vector3(0.1, 0.5, 0.1), "toll_paint", C.red if k % 2 == 0 else C.white, false, 1.25 + 0.5 * k)
	# the signs before it, both ways
	_toll_signs()
	# the canopy's name over each carriageway
	var title := "TOLL" if layout != "event" else "SHOTGUN RALLY"
	for dir in [1, -1]:
		var face: float = s0 - dir * (TOLL_CANOPY_L * 0.5 + 0.05)
		var dc: float = 0.0 if dir == 1 else st.ONCOMING_D
		_road_box(face, dc, Vector3(10.5, 1.3, 0.25), "toll_paint", C.purple if layout != "event" else C.red, false, base_y + 1.0)
		_toll_label(title, face - dir * 0.14, dc, base_y + 1.65, dir, 0.009 if title.length() < 6 else 0.0065)


## Text on the plaza facing the traffic going `dir`, at (s, d), h up.
func _toll_label(text: String, s: float, d: float, h: float, dir: int, px: float) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 96
	lbl.pixel_size = px
	lbl.outline_size = 0
	lbl.modulate = Color(0.97, 0.97, 0.95)
	lbl.double_sided = false
	var bas := _frame(s, d)                                  # (the road's, as its board's: up with the grade)
	# (as the gantries' boards: turned to the drivers coming at it; +Z is its readable side)
	lbl.transform = Transform3D(bas if dir == 1 else bas * Basis(Vector3.UP, PI), st.world_at(s, d) + bas.y * h)
	lbl.visibility_range_end = 700.0
	add_child(lbl)


## A closed lane's cones (base: its d on the open road): a taper across it from 150 m before
## the booths, then a line down its middle to the gate (Kenney's cone, if the library's in;
## else a little orange post).
func _toll_cones(base: float, dir: int) -> void:
	var s0: float = st.toll.s
	var H: float = st.toll.half
	var xfs: Array = []
	var u := H + 150.0
	while u > H + 0.5:
		var s: float = s0 - dir * u
		var t := clampf((H + 150.0 - u) / 60.0, 0.0, 1.0)  # (0 at the taper's start, at the lane's edge; 1 across)
		var dd: float = lerpf(st.toll_d(base + dir * st.LANE_W * 0.5, s), st.toll_d(base, s), t)   # (from its right edge in to its middle)
		var bas := _frame(s, dd)
		xfs.append(Transform3D(bas, st.world_at(s, dd)))
		u -= 6.0 if t < 1.0 else 9.0
	var mesh: Mesh = null
	var sc := 1.0
	if EnvAssets.available():
		mesh = EnvAssets.mesh("construction_cone")
		sc = float(EnvAssets.info("construction_cone").get("scale", 1.0))
	if mesh == null:
		var gb := GeoBuf.new()
		gb.box(Vector3(0, 0.36, 0), Vector3(0.3, 0.72, 0.3), Basis(), TOLL_COLS.yellow)
		mesh = gb.mesh()
		mesh.surface_set_material(0, _mat("toll_paint"))
		sc = 1.0
	for k in xfs.size():
		xfs[k] = xfs[k].scaled_local(Vector3.ONE * sc)
	_multimesh(mesh, xfs, "TollCones%d" % (1 if dir == 1 else 0), 900.0)


## The signs before the plaza, each way: at 1 km and 400 m, a gantry's board (as the exits'):
## how far, and in the mixed layout which lane's closed and the speed.
func _toll_signs() -> void:
	var s0: float = st.toll.s
	var H: float = st.toll.half
	var layout: String = st.toll.layout
	for dir in [1, -1]:
		for far in [1000.0, 400.0]:
			var s: float = s0 - dir * (H + far)
			# (not on top of an exit's gantry: moved toward the plaza)
			for k in 6:
				var clash := false
				for g in st.gantries:
					if absf(_ds(s, float(g.s))) < 45.0:
						clash = true
				if not clash:
					break
				s += dir * 30.0
			var lines := "TOLL PLAZA\n%s" % ("1 km" if far > 500.0 else "400 m")
			if layout == "mixed" and far < 500.0:
				lines = "TOLL · 60 km/h\nRIGHT LANE CLOSED"
			elif layout == "event":
				lines = "SHOTGUN RALLY\nTOLL OPEN · %s" % ("1 km" if far > 500.0 else "400 m")
			_sign_gantry(s, dir, lines)


## A sign gantry over one carriageway (dir 1 ours, -1 theirs): two posts, a beam, a green board.
func _sign_gantry(s: float, dir: int, text: String) -> void:
	var i := int(st.wrap_s(s) / st.STEP)
	var bas := Basis(Vector3.UP, -st.heading_at(s))
	var a := st.world_at(s, st.MEDIAN_D + 0.6 * dir)
	var b := st.world_at(s, (st.OUTER_R + 0.8) if dir == 1 else (st.OUTER_L - 0.8))
	for p in [a, b]:
		_buf(i, "steel").box(p + Vector3.UP * 3.6, Vector3(0.4, 7.2, 0.4), bas)
		_body(i, "concrete").box(p + Vector3.UP * 3.6, Vector3(0.4, 7.2, 0.4), bas, Color.WHITE, true)
	var mid := (a + b) * 0.5 + Vector3.UP * 7.0
	_buf(i, "steel").box(mid, Vector3(a.distance_to(b), 0.6, 0.8), bas)
	var board := st.world_at(s, st.LANE_W if dir == 1 else st.ONCOMING_D - st.LANE_W)
	board.y = mid.y - 1.1
	_buf(i, "sign").box(board, Vector3(9.0, 2.6, 0.2), bas)
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 96
	lbl.pixel_size = 0.0085
	lbl.outline_size = 0
	lbl.modulate = Color(0.95, 0.95, 0.92)
	lbl.double_sided = false
	lbl.transform = Transform3D(bas if dir == 1 else bas * Basis(Vector3.UP, PI), board + st.forward_at(s) * (-0.12 * dir))
	lbl.visibility_range_end = 900.0
	add_child(lbl)


## Roads crossing over the highway: a deck on piers (outside the barriers and in the
## median), at an angle, across both carriageways and on beyond.
func _overpasses() -> void:
	for o in st.overpasses:
		var s: float = o.s
		var i := int(s / st.STEP)
		var ang := deg_to_rad(float(o.angle))
		var c := st.world_at(s, (st.OUTER_L + st.OUTER_R) * 0.5)
		var road_y := c.y
		var deck_y := road_y + 7.2
		var h := st.heading_at(s) + ang
		var along := Vector3(sin(h), 0.0, -cos(h))
		var across := Vector3(cos(h), 0.0, sin(h))
		var bas := Basis(along.cross(Vector3.UP).normalized() * -1.0, Vector3.UP, -along) if false else Basis(Vector3.UP, -h)
		var length := 150.0
		var n := 10
		for k in n:
			var u0 := -length * 0.5 + length * k / n
			var u1 := u0 + length / n
			var p0 := c + along * u0
			var p1 := c + along * u1
			var mid := (p0 + p1) * 0.5
			mid.y = deck_y
			_buf(i, "concrete").box(mid, Vector3(13.0, 1.4, length / n + 0.05), bas)
			for side in [1.0, -1.0]:
				_buf(i, "concrete").box(mid + across * side * 6.3 + Vector3.UP * 1.2, Vector3(0.4, 1.0, length / n + 0.05), bas)
		# piers: 3 m outside our barriers (past an extra lane's), in the median, outside theirs,
		# under the deck where it crosses there, each a wall along the highway (they ran along
		# the deck: across the road, into the lanes, and the outer ones fell short of the
		# barriers on the skewed decks); beside a viaduct they (and the further ones, at each
		# end) stand on the ground (they hung in the air beside it)
		var wide := _edges(i)
		for k in range(i - 6, i + 7):
			var ek := _edges(k)
			wide = Vector2(minf(wide.x, ek.x), maxf(wide.y, ek.y))
		var lat: float = along.dot(st.right_at(s))         # (the deck's line: across the road this much a metre)
		var up_in_air: bool = st.support_at(s) in ["viaduct", "bridge"]
		for d in [wide.y + 3.4, st.MEDIAN_D, wide.x - 3.4]:
			var q: Vector3 = c + along * ((float(d) - (st.OUTER_L + st.OUTER_R) * 0.5) / lat)
			var qs: float = st.locate(q, i).s
			var foot: float = st.world_at(qs, d).y
			if d != st.MEDIAN_D:
				foot = maxf(st.land_at(q.x, q.z), -2.0) if up_in_air else foot - 0.5   # (into the embankment's top)
			_buf(i, "concrete").box(Vector3(q.x, (foot + deck_y - 0.7) * 0.5, q.z), Vector3(1.1 if d == st.MEDIAN_D else 1.6, deck_y - 0.7 - foot, 8.0),
				Basis(Vector3.UP, -st.heading_at(qs)))
		for u in [-60.0, 60.0]:
			var q: Vector3 = c + along * float(u)
			# (on the ground the land by the road is its cut or embankment: standing down to the
			# land or the road, whichever's lower, it's in the ground either way)
			var g := maxf(st.land_at(q.x, q.z), -2.0) if up_in_air else minf(st.land_at(q.x, q.z), road_y) - 0.5
			if deck_y - 0.7 - g > 1.0:
				_buf(i, "concrete").box(Vector3(q.x, (g + deck_y - 0.7) * 0.5, q.z), Vector3(1.6, deck_y - 0.7 - g, 8.0), bas)


## The ramps off and onto the highway: each a lane of its own (with shoulders, its edge
## lines and barriers) curving away from the gore and down to the ground, where it ends at
## a closed gate (the game's world is the highway). From the gore to its nose the ramp's lane
## is the highway's own widened edge (LoopGen._extra_lanes; its lines: _markings; the outer
## barrier out along it): its own road starts at the nose, square across the road where the
## widened asphalt ends (it was skipped until it was 17 m out: ~60 m with no road under it).
func _ramps() -> void:
	for r in st.ramps:
		_ramp(r)


func _ramp(r: Dictionary) -> void:
	var path := st.ramp_path(r)
	var pts: PackedVector3Array = path.pts
	var heads: PackedFloat32Array = path.heads
	var n := pts.size() - 1
	var w: float = st.RAMP_W
	var i := int(float(r.s) / st.STEP)
	# its rows across, each a middle and a vector to its right (a point at offset o: c + rv * o):
	# the first on the highway's line across at the nose (banked as the road is there), then the
	# path's points past it (flat across)
	var nose_s: float = path.nose_s
	var k0: int = int(path.nose) + 1
	var u := signf(Vector3(sin(heads[k0]), 0, -cos(heads[k0])).cross(Vector3.UP).dot(st.right_at(nose_s)))   # (its right: the road's, or its left)
	var cs: Array = [st.world_at(nose_s, float(path.nose_d))]
	var rvs: Array = [st.right_at(nose_s) * u + Vector3.UP * (-u * st.bank_at(nose_s))]
	for k in range(k0, n + 1):
		cs.append(pts[k])
		rvs.append(Vector3(sin(heads[k]), 0, -cos(heads[k])).cross(Vector3.UP).normalized())
	# the deck / road: 6.4 m of asphalt, its edge lines, a barrier each side, its collision
	# (a ramp that ends at the gas station: none of it on the forecourt, which takes over)
	var to_station: bool = not st.station.is_empty() and (r == st.station.off or r == st.station.on)
	var along := 0.0
	for j in cs.size() - 1:
		var a: Vector3 = cs[j]
		var b: Vector3 = cs[j + 1]
		var ra: Vector3 = rvs[j]
		var rb: Vector3 = rvs[j + 1]
		var u0 := along
		along += a.distance_to(b)
		if to_station and st.on_station(a.x, a.z, -1.0) and st.on_station(b.x, b.z, -1.0):
			continue
		var row_a := PackedVector3Array([a - ra * w, a + ra * w])
		var row_b := PackedVector3Array([b - rb * w, b + rb * w])
		var vv := PackedFloat32Array([-w, w])
		_buf(i, "asphalt").ribbon(row_a, row_b, u0, along, vv)
		_body(i, "asphalt").ribbon(row_a, row_b, u0, along, vv, Color.WHITE, true)
		for o in [-RAMP_LINE, RAMP_LINE]:
			var lift := Vector3.UP * 0.015
			_buf(i, "paint").quad(a + ra * (o - 0.075) + lift, a + ra * (o + 0.075) + lift, b + rb * (o + 0.075) + lift, b + rb * (o - 0.075) + lift,
				Vector2(u0, 0), Vector2(u0, 0.15), Vector2(along, 0.15), Vector2(along, 0))
		for sd in [-1.0, 1.0]:
			var e0: Vector3 = a + ra * sd * (w + 0.2)
			var e1: Vector3 = b + rb * sd * (w + 0.2)
			var prof := [[-0.25, 0.0], [-0.08, 0.95], [0.08, 0.95], [0.25, 0.0]]
			var ta := PackedVector3Array()
			var tb := PackedVector3Array()
			var vs := PackedFloat32Array()
			for q in prof:
				ta.append(e0 + ra * q[0] + Vector3.UP * q[1])
				tb.append(e1 + rb * q[0] + Vector3.UP * q[1])
				vs.append(q[0])
			_faces(_buf(i, "concrete"), ta, tb, u0, along, vs)
			_body(i, "concrete").ribbon(ta, tb, u0, along, vs, Color.WHITE, true)
		# under it, while it's off the ground: a deck (its sides down from the barriers' feet,
		# its underside) and piers
		var g := st.land_at(a.x, a.z)
		if a.y - g > 2.0:
			var down := Vector3.UP * -1.5
			_buf(i, "concrete").quad(a + ra * w + down, a - ra * w + down, b - rb * w + down, b + rb * w + down,
				Vector2(u0, w), Vector2(u0, -w), Vector2(along, -w), Vector2(along, w))
			for sd in [-1.0, 1.0]:
				var f0: Vector3 = a + ra * sd * (w + 0.45)
				var f1: Vector3 = b + rb * sd * (w + 0.45)
				var g0: Vector3 = a + ra * sd * w + down
				var g1: Vector3 = b + rb * sd * w + down
				_quad_to(_buf(i, "concrete"), f0, f1, g1, g0, ra * sd, Vector2(u0, 0), Vector2(along, 0), Vector2(along, 1.5), Vector2(u0, 1.5))
			if j % 8 == 1:
				_buf(i, "concrete").box(Vector3(a.x, (g + a.y - 1.5) * 0.5, a.z), Vector3(1.6, a.y - 1.5 - g, 1.6))
	# an exit's nose: a crash cushion (yellow and black) in the gore, before the barriers' ends
	if r.kind == "off":
		var right_side: bool = r.side == "right"
		var walk := (1.0 if right_side else -1.0)
		var hw: float = (st.EDGE + st.SHOULDER_R + 0.4) if right_side else (st.ONCOMING_D - st.EDGE - st.SHOULDER_R - 0.4)
		var rw: float = float(path.nose_d) + (-(w + 0.2) if right_side else (w + 0.2))
		for k in 6:
			_road_box(nose_s - walk * (0.25 + 0.5 * k), (hw + rw) * 0.5, Vector3(absf(rw - hw) + 0.5, 0.9, 0.5), "toll_paint",
				TOLL_COLS.yellow if k % 2 == 0 else TOLL_COLS.dark, true)
	# the closed gate at its far end (none where it runs into the gas station)
	if to_station:
		return
	var e := pts[n]
	_buf(i, "concrete").box(e + Vector3.UP * 0.6, Vector3(7.0, 1.2, 0.8), Basis(Vector3.UP, -heads[n]))
	_body(i, "concrete").box(e + Vector3.UP * 0.6, Vector3(7.0, 1.2, 0.8), Basis(Vector3.UP, -heads[n]), Color.WHITE, true)


## THE GAS STATION (LoopGen.station): cut up starts at its pumps. A forecourt joining a
## junction's two ramps' ends (asphalt on the plane they're on, solid, its sides down into the
## land), a canopy on six columns over three pump islands (two pumps each, lit screens, a red
## band round the canopy, lights under it), the shop at the back (glass front lit at night, its
## sign), parking bays at the shop, a price pylon towards the highway, and a planter wall round
## it (solid: open where the two ramps come in). No brands: SHOTGUN FUEL. In the forecourt's own
## frame: a across (u, from the exit's end to the entry's), b out (w, away from the highway).
const STATION_COLS := {"white": Color(0.92, 0.92, 0.9), "red": Color(0.82, 0.1, 0.07), "grey": Color(0.42, 0.43, 0.45),
	"dark": Color(0.1, 0.1, 0.11), "kerb": Color(0.78, 0.78, 0.75), "yellow": Color(1.0, 0.78, 0.05),
	"wall": Color(0.8, 0.78, 0.73), "hedge": Color(0.18, 0.34, 0.14)}
const STATION_CANOPY_H := 5.4        # m: its underside over the forecourt
const STATION_CANOPY := Rect2(-9.0, -15.5, 18.0, 25.0)   # its roof (a, b, along a, along b)
const STATION_ISLANDS := [-9.0, -3.0, 3.0]               # b of each pump island (the lanes between)
const STATION_SHOP := Rect2(-14.0, 15.0, 28.0, 8.0)      # the shop's walls (a, b, sizes)

func _station() -> void:
	var S: Dictionary = st.station
	if S.is_empty():
		return
	var i := int(st.wrap_s(float(S.s)) / st.STEP)
	var u: Vector3 = S.u
	var B := Basis(u, Vector3.UP, u.cross(Vector3.UP))      # (boxes square to the forecourt)
	var H: Vector2 = st.STATION_HALF
	var C := STATION_COLS
	# the forecourt: 4 m squares of asphalt (solid), its sides down 1.5 m into the land
	var a := -H.x
	while a < H.x - 0.01:
		var b := -H.y
		while b < H.y - 0.01:
			var c0: Vector3 = st.station_at(a, b)
			var c1: Vector3 = st.station_at(a, b + 4.0)
			var c2: Vector3 = st.station_at(a + 4.0, b + 4.0)
			var c3: Vector3 = st.station_at(a + 4.0, b)
			var uv := [Vector2(c0.x, c0.z), Vector2(c1.x, c1.z), Vector2(c2.x, c2.z), Vector2(c3.x, c3.z)]
			_quad_to(_buf(i, "asphalt"), c0, c1, c2, c3, Vector3.UP, uv[0], uv[1], uv[2], uv[3])
			_quad_to(_body(i, "asphalt"), c0, c1, c2, c3, Vector3.UP, uv[0], uv[1], uv[2], uv[3], true)
			b += 4.0
		a += 4.0
	for e in [[-H.x, -H.y, H.x, -H.y], [H.x, -H.y, H.x, H.y], [H.x, H.y, -H.x, H.y], [-H.x, H.y, -H.x, -H.y]]:
		var t0: Vector3 = st.station_at(e[0], e[1])
		var t1: Vector3 = st.station_at(e[2], e[3])
		var out: Vector3 = (t1 - t0).cross(Vector3.UP).normalized()
		if out.dot(t0 - (S.c as Vector3)) < 0.0:
			out = -out
		_quad_to(_buf(i, "concrete"), t0, t1, t1 + Vector3.DOWN * 1.5, t0 + Vector3.DOWN * 1.5, out,
			Vector2(0, 0), Vector2(t0.distance_to(t1), 0), Vector2(t0.distance_to(t1), 1.5), Vector2(0, 1.5))
	# the way through: the lanes past the pumps, arrows, the bays at the shop
	for b in [-15.0, 9.0]:
		_station_line(i, -26.0, b, 26.0, b, 0.12)
	var x := -13.0
	while x <= 13.01:
		_station_line(i, x, 10.4, x, 14.6, 0.12)
		x += 2.6
	# the islands: kerbed, bollards at the ends; two pumps on each
	for ib in STATION_ISLANDS:
		_sbox(i, B, "toll_paint", 0.0, ib, 0.0, Vector3(12.0, 0.22, 1.5), C.kerb, true)
		for ea in [-6.3, 6.3]:
			_sbox(i, B, "toll_paint", ea, ib, 0.0, Vector3(0.22, 1.0, 0.22), C.yellow, true)
		for pa in [-2.4, 2.4]:
			_sbox(i, B, "toll_paint", pa, ib, 0.22, Vector3(1.0, 0.12, 0.75), C.grey, true)
			_sbox(i, B, "toll_paint", pa, ib, 0.34, Vector3(0.82, 1.55, 0.58), C.white, true)
			_sbox(i, B, "toll_paint", pa, ib, 1.89, Vector3(0.86, 0.32, 0.62), C.red)
			for side in [-1.0, 1.0]:
				_sbox(i, B, "station_screen", pa, ib + side * 0.3, 1.25, Vector3(0.46, 0.34, 0.02), Color.WHITE)
				_sbox(i, B, "toll_paint", pa + 0.3, ib + side * 0.32, 0.55, Vector3(0.06, 0.9, 0.06), C.dark)   # (the hose)
	# the canopy: columns at the islands' ends, the roof, its red band, lights under it
	var R := STATION_CANOPY
	for ib in STATION_ISLANDS:
		for ca in [-5.7, 5.7]:
			_sbox(i, B, "toll_paint", ca, ib, 0.22, Vector3(0.45, STATION_CANOPY_H - 0.22, 0.45), C.white, true)
	var cm := R.get_center()
	_sbox(i, B, "toll_paint", cm.x, cm.y, STATION_CANOPY_H, Vector3(R.size.x, 0.9, R.size.y), C.white)
	for sd in [-1.0, 1.0]:
		_sbox(i, B, "toll_paint", cm.x + sd * (R.size.x * 0.5 + 0.02), cm.y, STATION_CANOPY_H + 0.25, Vector3(0.06, 0.36, R.size.y + 0.1), C.red)
		_sbox(i, B, "toll_paint", cm.x, cm.y + sd * (R.size.y * 0.5 + 0.02), STATION_CANOPY_H + 0.25, Vector3(R.size.x + 0.1, 0.36, 0.06), C.red)
	for la in [-4.5, 0.0, 4.5]:
		for lb in [-12.0, -6.0, 0.0, 6.0]:
			_sbox(i, B, "lamp", la, lb, STATION_CANOPY_H - 0.04, Vector3(1.6, 0.05, 0.6), Color.WHITE)
	# the shop: walls, a glass front (lit at night), a door, its roof's red band and sign
	var sh := STATION_SHOP
	var sc := sh.get_center()
	_sbox(i, B, "toll_paint", sc.x, sc.y, 0.0, Vector3(sh.size.x, 4.2, sh.size.y), C.wall, true)
	_sbox(i, B, "toll_glass", sc.x, sh.position.y - 0.03, 0.4, Vector3(sh.size.x - 4.0, 2.6, 0.06), Color.WHITE)
	_sbox(i, B, "toll_paint", sc.x + 6.0, sh.position.y - 0.06, 0.0, Vector3(2.2, 2.5, 0.08), C.dark)
	_sbox(i, B, "toll_paint", sc.x, sc.y, 4.2, Vector3(sh.size.x + 0.4, 0.8, sh.size.y + 0.4), C.red)
	_sbox(i, B, "toll_paint", sc.x, sh.position.y - 0.4, 0.0, Vector3(sh.size.x, 0.18, 0.8), C.kerb, true)   # (its step)
	_station_label(st.station_at(sc.x, sh.position.y - 0.24, 4.6), B, "SHOTGUN FUEL", 0.011)
	_station_label(st.station_at(sc.x - 9.0, sh.position.y - 0.08, 3.25), B, "24/7", 0.006)
	# the price pylon, between the ramps' ends, its face to the highway
	var pa := 0.0
	var pb := -H.y + 2.5
	_sbox(i, B, "toll_paint", pa, pb, 0.0, Vector3(1.4, 0.6, 1.4), C.grey, true)
	_sbox(i, B, "toll_paint", pa, pb, 0.6, Vector3(0.5, 7.4, 0.5), C.grey, true)
	_sbox(i, B, "toll_paint", pa, pb, 8.0, Vector3(3.4, 4.6, 0.5), C.white)
	_sbox(i, B, "toll_paint", pa, pb, 11.4, Vector3(3.5, 1.3, 0.56), C.red)
	_station_label(st.station_at(pa, pb - 0.3, 11.7), B, "FUEL", 0.012)
	var prices := ["REG   3.49", "PLUS  3.79", "PREM  4.09"]
	for k in prices.size():
		_station_label(st.station_at(pa, pb - 0.27, 10.3 - k * 1.05), B, prices[k], 0.006, Color(0.08, 0.08, 0.09))
	# the planter wall round it (open where the ramps come in): a low wall, a hedge on it
	var openings: Array = []
	for rmp in [S.off, S.on]:
		var path := st.ramp_path(rmp)
		var pts: PackedVector3Array = path.pts
		for k in range(pts.size() - 1, -1, -1):
			if not st.on_station(pts[k].x, pts[k].z, 3.0):
				break
			openings.append(pts[k])
	for e in [[-H.x, -H.y, H.x, -H.y], [H.x, -H.y, H.x, H.y], [H.x, H.y, -H.x, H.y], [-H.x, H.y, -H.x, -H.y]]:
		var elen := Vector2(e[2] - e[0], e[3] - e[1]).length()
		var n := int(elen / 2.0)
		for k in n:
			var t := (k + 0.5) / n
			var wa: float = lerpf(e[0], e[2], t)
			var wb: float = lerpf(e[1], e[3], t)
			var wp: Vector3 = st.station_at(wa, wb)
			var gap := false
			for o in openings:
				if Vector2(o.x - wp.x, o.z - wp.z).length() < st.RAMP_W + 2.2:
					gap = true
					break
			if gap:
				continue
			var along_a := absf(e[2] - e[0]) > 0.1
			var piece := elen / n + 0.02
			_sbox(i, B, "toll_paint", wa, wb, 0.0, Vector3(piece, 0.75, 0.6) if along_a else Vector3(0.6, 0.75, piece), C.wall, true)
			_sbox(i, B, "toll_paint", wa, wb, 0.75, Vector3(piece, 0.6, 0.42) if along_a else Vector3(0.42, 0.6, piece), C.hedge)


## A box on the forecourt (chunk i, square to it: B): its foot at (a, b) h up, its size along
## a, up, along b; solid: a car hits it.
func _sbox(i: int, B: Basis, key: String, a: float, b: float, h: float, size: Vector3, col: Color, solid := false) -> void:
	var at: Vector3 = st.station_at(a, b, h + size.y * 0.5)
	_buf(i, key).box(at, size, B, col)
	if solid:
		_body(i, "concrete").box(at, size, B, Color.WHITE, true)


## A painted line on the forecourt from (a0, b0) to (a1, b1), w wide.
func _station_line(i: int, a0: float, b0: float, a1: float, b1: float, w: float) -> void:
	var p0: Vector3 = st.station_at(a0, b0, 0.015)
	var p1: Vector3 = st.station_at(a1, b1, 0.015)
	var side: Vector3 = (p1 - p0).cross(Vector3.UP).normalized() * w * 0.5
	var L := p0.distance_to(p1)
	_quad_to(_buf(i, "paint"), p0 - side, p1 - side, p1 + side, p0 + side, Vector3.UP, Vector2(0, 0), Vector2(L, 0), Vector2(L, w), Vector2(0, w))


## Text on the gas station at p, square to the forecourt, facing the highway's side (-w: the
## shop's front looks at the pumps that way, the pylon at the highway).
func _station_label(p: Vector3, B: Basis, text: String, px: float, col := Color(0.97, 0.97, 0.95)) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 96
	lbl.pixel_size = px
	lbl.outline_size = 0
	lbl.modulate = col
	lbl.double_sided = false
	# (a Label3D reads from its +Z: B's z is u x up, which is +w or -w)
	var face: Vector3 = -(st.station.w as Vector3)
	var bas := B if B.z.dot(face) > 0.0 else B * Basis(Vector3.UP, PI)
	lbl.transform = Transform3D(bas, p)
	lbl.visibility_range_end = 700.0
	add_child(lbl)


## The gas station's lights (StreetLamps' pools at night): under the canopy, over its lanes.
func _station_lamp_heads() -> Array:
	var out: Array = []
	if st.station.is_empty():
		return out
	for lb in [-12.0, -6.0, 0.0, 6.0]:
		var g: Vector3 = st.station_at(0.0, lb)
		out.append({"s": float(st.station.s), "head": g + Vector3.UP * (STATION_CANOPY_H - 0.1), "ground": g, "up": Vector3.UP, "radius": 9.0})
	return out


## The city's towers, both sides of the expressway: blocks of offices and flats,
## lower near the road, taller back from it and in the middle of town; none on a
## road (this or another part of the loop, or a ramp) or in the water; each on the lowest
## ground drawn under it.
const CITY_FRONT := 190.0            # m from the road's middle: the library's buildings (EnvAssets "building") this near, the drawn towers beyond
const CITY_REAL_DRAW := 1800.0       # m: a real building drawn this far (its LODs: Godot's, per building)

func _city() -> void:
	var occupied := {}
	var xfs := []
	var cols := []
	var box := _building_mesh()
	var lib: Array = EnvAssets.ids("building") if EnvAssets.available() else []
	var real: Array = []                                     # [[id, Transform3D, radius]]
	var night: float = _wm.night_amount if _wm else (1.0 if mood == "night" else 0.0)
	var palette := [Color(0.5, 0.5, 0.48), Color(0.56, 0.53, 0.47), Color(0.44, 0.46, 0.5), Color(0.6, 0.59, 0.56),
		Color(0.38, 0.4, 0.42), Color(0.53, 0.48, 0.42), Color(0.46, 0.5, 0.53)]
	for z in st.zones:
		if z.kind != "city":
			continue
		var z0: float = z.s0
		var z1: float = z.s1
		var s := z0 + 20.0
		while s < z1 - 20.0:
			var centre := 1.0 - absf((s - z0) / maxf(z1 - z0, 1.0) - 0.5) * 2.0   # (taller in the middle of town)
			for side in [1.0, -1.0]:
				var d: float = (st.OUTER_R + 28.0) if side > 0.0 else (st.OUTER_L - 28.0)
				while absf(d) < 420.0:
					var w := _rng.randf_range(18.0, 42.0)
					var dep := _rng.randf_range(18.0, 38.0)
					var off: float = d + side * dep * 0.5
					var p := st.world_at(s, off)
					var far := absf(off) / 420.0
					var hgt := _rng.randf_range(14.0, 34.0) + far * _rng.randf_range(10.0, 90.0) * (0.4 + centre)
					if _rng.randf() < 0.07:
						hgt *= 2.0
					d += side * (dep + _rng.randf_range(10.0, 24.0))
					var g := st.land_at(p.x, p.z)
					# the front rows: one of the library's buildings, its long side to the road (its own
					# footprint: the next slot further out by its depth)
					if not lib.is_empty() and absf(off) < CITY_FRONT:
						var id: String = lib[_rng.randi() % lib.size()]
						var sz: Array = EnvAssets.info(id).get("size", [30.0, 30.0, 30.0])
						var along: bool = float(sz[0]) >= float(sz[2])          # (its x the longer: along the road)
						var across: float = float(sz[2]) if along else float(sz[0])
						var rad: float = Vector2(float(sz[0]), float(sz[2])).length() * 0.5
						var q := st.world_at(s, off - side * dep * 0.5 + side * (across * 0.5 + 2.0))   # (from the slot's road side out)
						var gq := st.land_at(q.x, q.z)
						d += side * (across - dep + 2.0)
						if gq < 1.5 or _road_dist(q.x, q.z) < 30.0 + rad or rad > 75.0:
							continue
						var clash := false
						for r in real:
							if (r[1] as Transform3D).origin.distance_to(Vector3(q.x, gq, q.z)) < float(r[2]) + rad - 4.0:
								clash = true
								break
						if clash:
							continue
						var rb := Basis(Vector3.UP, -st.heading_at(s) + (PI * 0.5 if along else 0.0) + (PI if _rng.randf() < 0.5 else 0.0))
						# none on a ramp (they ran through 23 of the 24): one there keeps its plot (the
						# rest of the town where it was) but isn't built
						var on_ramp := _ramp_dist(q.x, q.z) < rad + st.RAMP_W + 4.0
						# on the lowest ground drawn under it (a 3 x 3 grid over its footprint: the land
						# under its middle left gaps under its sides, over the cuts and the far land)
						var g_lo := gq
						for ca in ([] if on_ramp else [-0.5, 0.0, 0.5]):
							for cb in [-0.5, 0.0, 0.5]:
								var cp: Vector3 = Vector3(q.x, 0, q.z) + rb * Vector3(float(sz[0]) * ca, 0.0, float(sz[2]) * cb)
								var cl: Dictionary = st.locate(cp, int(st.wrap_s(s) / st.STEP))
								g_lo = minf(g_lo, _drawn_y(float(cl.s), float(cl.d)))
						real.append([id, Transform3D(rb, Vector3(q.x, g_lo - 0.3, q.z)), rad, on_ramp])
						occupied[Vector2i(floori(q.x / 30.0), floori(q.z / 30.0))] = true
						continue
					if g < 1.5 or _road_dist(p.x, p.z) < 34.0 + maxf(w, dep) * 0.5:
						continue
					var clash2 := false
					for r in real:
						if (r[1] as Transform3D).origin.distance_to(Vector3(p.x, g, p.z)) < float(r[2]) + maxf(w, dep) * 0.5:
							clash2 = true
							break
					if clash2:
						continue
					var key := Vector2i(floori(p.x / 30.0), floori(p.z / 30.0))
					if occupied.has(key):
						continue
					occupied[key] = true
					# (turned, then scaled in its own axes: scaled after turning, the box was sheared)
					var bas := Basis(Vector3.UP, -st.heading_at(s)) * Basis.from_scale(Vector3(w, hgt, dep))
					var col: Color = palette[_rng.randi() % palette.size()]
					if _ramp_dist(p.x, p.z) < Vector2(w, dep).length() * 0.5 + st.RAMP_W + 4.0:
						continue
					# on the lowest ground drawn under its corners (its x across the road, z along it)
					var g_lo := g
					for ca in [-0.5, 0.5]:
						for cb in [-0.5, 0.5]:
							g_lo = minf(g_lo, _drawn_y(s + dep * cb, off + w * ca))
					xfs.append(Transform3D(bas, Vector3(p.x, g_lo + hgt * 0.5 - 0.5, p.z)))
					cols.append(col)
			s += _rng.randf_range(40.0, 70.0)
	real = real.filter(func(r): return not r[3])
	# the far tier: the 31-building pack behind the front rows, out to the city's edge (the drawn
	# towers out there give way to it): scripts/stage/city_skyline.gd
	var far: int = preload("res://scripts/stage/city_skyline.gd").build(self, xfs, cols, real, night)
	building_count = xfs.size() + real.size() + far
	real_building_count = real.size()
	# the library's buildings: each its own node (Godot picks each one's level of detail by its
	# distance), its facade material (lit windows at night)
	var mats := {}
	for r in real:
		var m: Mesh = EnvAssets.mesh(str(r[0]))
		if m == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Building_%s_%d" % [r[0], get_child_count()]
		mi.mesh = m
		if not mats.has(r[0]):
			mats[r[0]] = EnvAssets.building(m.surface_get_material(0), night)
		mi.material_override = mats[r[0]]
		mi.transform = r[1]
		mi.visibility_range_end = CITY_REAL_DRAW
		mi.visibility_range_end_margin = 100.0
		add_child(mi)
	# in a few big batches (each drawn within a range)
	var batch := 400
	for k in range(0, xfs.size(), batch):
		_multimesh(box, xfs.slice(k, k + batch), "Towers%d" % (k / batch), 4500.0, cols.slice(k, k + batch))


## A unit box (the towers' shape: MultiMesh scales it), its UVs 0..1 on each face.
func _building_mesh() -> ArrayMesh:
	var gb := GeoBuf.new()
	var h := 0.5
	var c := [Vector3(-h, -h, -h), Vector3(h, -h, -h), Vector3(h, h, -h), Vector3(-h, h, -h),
		Vector3(-h, -h, h), Vector3(h, -h, h), Vector3(h, h, h), Vector3(-h, h, h)]
	for f in [[4, 5, 6, 7], [1, 0, 3, 2], [0, 4, 7, 3], [5, 1, 2, 6], [7, 6, 2, 3]]:
		gb.quad(c[f[0]], c[f[1]], c[f[2]], c[f[3]], Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	var m := gb.mesh()
	m.surface_set_material(0, _mat("building"))
	return m


## Trees on the hills and the lakeshore (not in the city, not in the water, not on the
## road's verges or a ramp, not on the step at a tunnel's portal): pines and broadleaves, in
## clumps, out to ~400 m from the road, each on the ground as drawn (_drawn_y: on the land
## the ground's shaped from, 1 in 7 floated over the road's cuts and the far land, up to 60 m).
func _trees() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 21
	noise.frequency = 1.0 / 180.0
	var per_chunk := {}
	var s := 0.0
	while s < st.length:
		var zone := st.zone_at(s)
		if zone != "city":
			for side in [1.0, -1.0]:
				for k in 6:
					var d: float = (st.OUTER_R + _rng.randf_range(14.0, 380.0)) if side > 0.0 else (st.OUTER_L - _rng.randf_range(14.0, 380.0))
					var ts := s + _rng.randf_range(-6.0, 6.0)
					var p := st.world_at(ts, d)
					if noise.get_noise_2d(p.x, p.z) < -0.05:
						continue                              # (clumps: open ground between)
					var g := st.land_at(p.x, p.z)
					if g < 2.0 or st.in_city(p.x, p.z) or _road_dist(p.x, p.z) < 26.0:
						continue
					var rd := _road_dist(p.x, p.z)
					g = _drawn_y(ts, d)
					var sc := _rng.randf_range(0.75, 1.35)
					var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(sc, sc * _rng.randf_range(0.9, 1.2), sc)), Vector3(p.x, g - 0.2, p.z))
					var c := int(int(s / st.STEP) / CH)
					var key := Vector2i(c, 0 if zone == "hills" and _rng.randf() < 0.7 else 1)
					# (by a portal the land steps 10.5 m between two of its kept rows: _drawn_y can't say which side)
					if _near_portal(ts, 5.0) or _ramp_dist(p.x, p.z) < st.RAMP_W + 6.0:
						continue
					if not per_chunk.has(key):
						per_chunk[key] = []
					per_chunk[key].append([xf, rd])
		s += 12.0
	if _lib_trees_ok():
		_library_trees(per_chunk)
		return
	var pine := _tree_mesh(true)
	var broad := _tree_mesh(false)
	for key in per_chunk:
		tree_count += per_chunk[key].size()
		_multimesh(pine if key.y == 0 else broad, per_chunk[key].map(func(e): return e[0]), "Trees%03d_%d" % [key.x, key.y], 1800.0)


## MEDIUM and up, the library in the build: the hills' trees are the library's (the biome's species,
## as the stages and the circuit draw them), not the drawn cones. (The cones were the last of the
## old flat-colour look on cut up's open stretches.)
func _lib_trees_ok() -> bool:
	var gfx = load("res://scripts/render/graphics.gd")
	return gfx.level() != "low" and EnvAssets.available() and not gfx.headless()


const LIB_NEAR := 70.0               # m off the road: the trees nearer than this get their real (LOD1) mesh near the camera
const LIB_LOD1_DRAW := 240.0         # ... within this of their group's middle; the far card beyond, and always for the rest

## The library's trees for the groups _trees laid out ({Vector2i(chunk, 0 pine / 1 broadleaf): [[xf, m off
## the road]]}): two tall cedars for the hills' sugi forest (the touge's biome, japan_cedar) and two of the
## highway verge's broadleaves (suburban_verge), picked by the loop's seed (each species is a draw per
## group); which one by each tree's spot (the same on every machine and at every level), sized from the
## biome's scale (the broadleaves larger: grown trees, not the verge's saplings). The near ones (LIB_NEAR)
## LOD1 near the camera (casting shadows on HIGH and ULTRA), the far card beyond; the rest only ever the card.
func _library_trees(per_chunk: Dictionary) -> void:
	var biomes = load("res://scripts/stage/biomes.gd")
	var cedar: Dictionary = biomes.for_stage({"opts": {"biome": "japan_cedar"}, "kind": "loop"})
	var verge: Dictionary = biomes.for_stage(st)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([st.seed_used, "loop species"])
	var pick := func(pool: Array, n: int) -> Array:
		var left := pool.duplicate()
		var out: Array = []
		while not left.is_empty() and out.size() < n:
			var id: String = biomes.pick(left, rng)
			out.append(id)
			left = left.filter(func(e): return str(e[0]) != id)
		return out
	var kinds := [pick.call(cedar.get("trees", []), 2), pick.call(verge.get("broad", []), 2)]
	if kinds[0].is_empty() and kinds[1].is_empty():
		return
	for k in 2:
		if kinds[k].is_empty():
			kinds[k] = kinds[1 - k]
	var scales := [cedar.get("tree_scale", [0.72, 1.0]), [1.0, 1.45]]
	var shadows: bool = load("res://scripts/render/graphics.gd").level() in ["high", "ultra"]     # (as the stages: MEDIUM's trees cast none)
	var groups := {}                 # "chunk|near|species" -> [Transform3D]
	for key in per_chunk:
		var list: Array = kinds[key.y]
		for e in per_chunk[key]:
			var xf: Transform3D = e[0]
			var o := xf.origin
			var sp: String = list[absi(hash([int(o.x * 4.0), int(o.z * 4.0), "loop tree"])) % list.size()]
			var sc := xf.basis.get_scale().x
			var ts: Array = scales[key.y]
			var msc := lerpf(float(ts[0]), float(ts[1]), clampf((sc - 0.75) / 0.6, 0.0, 1.0))
			var gk := "%d|%d|%s" % [key.x, 1 if float(e[1]) < LIB_NEAR else 0, sp]
			if not groups.has(gk):
				groups[gk] = []
			groups[gk].append(Transform3D(Basis(Vector3.UP, atan2(-xf.basis.x.z, xf.basis.x.x)).scaled(Vector3.ONE * msc), o))
			tree_count += 1
	for gk in groups:
		var parts: PackedStringArray = gk.split("|")
		var near := parts[1] == "1"
		var sp := parts[2]
		var list: Array = groups[gk]
		var lods := [["LOD1", 0.0, LIB_LOD1_DRAW], ["BB", LIB_LOD1_DRAW, 1800.0]] if near else [["BB", 0.0, 1800.0]]
		for lv in lods:
			var m: Mesh = EnvAssets.mesh(sp, lv[0])
			if m == null:
				continue
			var mmi := _multimesh(m, list, "Trees%s_%s_%s_%s" % [parts[0], parts[1], sp, lv[0]], lv[2])
			mmi.visibility_range_begin = lv[1]
			mmi.visibility_range_begin_margin = 10.0 if lv[1] > 0.0 else 0.0
			mmi.visibility_range_end_margin = 10.0 if lv[0] == "LOD1" else 150.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lv[0] == "LOD1" and shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A tree (origin at its foot): a trunk and a crown, low-poly but in real colours.
func _tree_mesh(pine: bool) -> ArrayMesh:
	var bark := GeoBuf.new()
	var leaves := GeoBuf.new()
	bark.tube(PackedVector3Array([Vector3.ZERO, Vector3(0, 4.0 if pine else 3.0, 0)]), 0.28, 6)
	if pine:
		for k in 4:
			var y0 := 2.5 + k * 2.6
			var r := 3.0 - k * 0.65
			_cone(leaves, Vector3(0, y0, 0), r, 4.2, 8)
	else:
		_blob(leaves, Vector3(0, 5.2, 0), Vector3(3.6, 3.2, 3.6))
	return _mesh2(bark, "bark", leaves, "leaves")


func _cone(gb: GeoBuf, base: Vector3, r: float, h: float, seg: int) -> void:
	var top := base + Vector3(0, h, 0)
	for j in seg:
		var a0 := TAU * j / seg
		var a1 := TAU * (j + 1) / seg
		var p0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		gb.tri(p0, top, p1, Vector2(0, 0), Vector2(0.5, 1), Vector2(1, 0))
		gb.tri(p1, base, p0, Vector2(1, 0), Vector2(0.5, 0.5), Vector2(0, 0))


func _blob(gb: GeoBuf, c: Vector3, sz: Vector3) -> void:
	var rings := 4
	var seg := 8
	var prev := []
	for k in rings + 1:
		var t := PI * k / rings
		var ring := []
		for j in seg:
			var a := TAU * j / seg
			ring.append(c + Vector3(cos(a) * sin(t) * sz.x, cos(t) * sz.y, sin(a) * sin(t) * sz.z))
		if k > 0:
			for j in seg:
				var j1 := (j + 1) % seg
				gb.quad(prev[j], ring[j], ring[j1], prev[j1], Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
		prev = ring

