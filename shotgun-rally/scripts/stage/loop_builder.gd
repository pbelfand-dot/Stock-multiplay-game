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
	# ground-ness, eased over ~60 m so the land doesn't step where the support changes
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		raw[i] = 1.0 if st.support_at(i * st.STEP) == "ground" else 0.0
	_ground_f = _ease(raw, 30)
	_extra_r = st.extra_r
	_extra_l = st.extra_l


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


func _road() -> void:
	var n: int = st._n
	var step: float = st.STEP
	var prev := PackedVector3Array()
	var prev_v := PackedFloat32Array()
	for i in n + 1:
		var s := i * step
		var e := _edges(i)
		var ds := PackedFloat32Array([e.x, st.ONCOMING_D - st.EDGE, st.MEDIAN_D - st.MEDIAN * 0.5, st.MEDIAN_D + st.MEDIAN * 0.5, st.EDGE, e.y])
		var row := PackedVector3Array()
		for d in ds:
			row.append(st.world_at(s, d))
		if i > 0:
			var cols := PackedColorArray()
			for k in ds.size():
				# the shoulders a touch lighter than the lanes (less traffic polish)
				var shoulder: bool = k == 0 or k == ds.size() - 1 or k == 2 or k == 3
				cols.append(Color(1.08, 1.08, 1.06) if shoulder else Color(1, 1, 1))
			_buf(i - 1, "asphalt").ribbon(prev, row, s - step, s, ds, Color.WHITE, false, cols, cols)
			_body(i - 1, "asphalt").ribbon(prev, row, s - step, s, ds, Color.WHITE, true)
			_markings(i - 1)
		prev = row
		prev_v = ds


## The lines painted between samples i and i+1: solid edge lines, dashed lane lines
## (8 m of paint, 12 m gap, as on a Japanese expressway), both carriageways; where a
## ramp's extra lane runs alongside, the edge line is a short, thick dashed one.
func _markings(i: int) -> void:
	var s0: float = i * st.STEP
	var s1: float = s0 + st.STEP
	var j := posmod(i, st._n)
	var lines := []   # [d, width, dashed]
	for side in [0.0, st.ONCOMING_D]:
		var mirror: float = 1.0 if side == 0.0 else -1.0
		var extra: float = _extra_r[j] if side == 0.0 else _extra_l[j]
		lines.append([side + mirror * st.EDGE, 0.2 if extra <= 0.0 else 0.45, 0.0 if extra <= 0.0 else 2.0])
		lines.append([side - mirror * st.EDGE, 0.15, 0.0])
		for k in [-1.0, 0.0, 1.0]:
			lines.append([side + k * st.LANE_W, 0.15, 1.0])
		if extra > 0.5:
			lines.append([side + mirror * (st.EDGE + extra + 0.1), 0.2, 0.0])
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
		var d1 := d
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
		if sup == "tunnel":
			continue
		var e := _edges(i)
		var e2 := _edges(i + 1)
		for side in [1.0, -1.0]:
			if _ramp_gap(s, side):
				continue
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


## Is the outer barrier open here (a ramp leaving or joining between its gore and its end)?
func _ramp_gap(s: float, side: float) -> bool:
	for r in st.ramps:
		if (r.side == "right") != (side > 0.0):
			continue
		var ds := _ds(s, r.s) * (1.0 if r.side == "right" else -1.0)
		if r.kind == "off" and ds > -4.0 and ds < 60.0:
			return true
		if r.kind == "on" and ds > -60.0 and ds < 4.0:
			return true
	return false


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
	_buf(i, key).ribbon(ra, rb, s0, s1, vs)
	_body(i, "concrete").ribbon(ra, rb, s0, s1, vs, Color.WHITE, true)


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
	_buf(i, "concrete").ribbon(ra, rb, s0, s1, vs)
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
	var h0 := 0.5
	var h1 := 0.82
	var q0 := b0 + Vector3.UP * h0
	var q1 := b1 + Vector3.UP * h0
	var q2 := b1 + Vector3.UP * h1
	var q3 := b0 + Vector3.UP * h1
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
		var e := _edges(i)
		var e2 := _edges(i + 1)
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


## The land along the road, each side out to 300 m: flush with the shoulder, then
## an embankment or a cut into the land (1 in 2) where the road's on the ground;
## the land as it is under viaducts and bridges and over the tunnels.
func _ribbon() -> void:
	var n: int = st._n
	var step: float = st.STEP * 2.0
	for side in [1.0, -1.0]:
		var prev := PackedVector3Array()
		var prev_c := PackedColorArray()
		var vs := PackedFloat32Array()
		for d in RIBBON:
			vs.append(d)
		var i := 0
		while i <= n:
			var s := i * st.STEP
			var e := _edges(i)
			var d0: float = (e.y + 0.6) if side > 0.0 else (e.x - 0.6)
			var edge := st.world_at(s, d0)
			var road_y := edge.y - 0.25
			var g: float = _ground_f[posmod(i, n)]
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
			if not prev.is_empty():
				var ra := prev if side > 0.0 else _rev(prev)
				var rb := row if side > 0.0 else _rev(row)
				var ca := prev_c if side > 0.0 else _revc(prev_c)
				var cb := cols if side > 0.0 else _revc(cols)
				var v2 := vs if side > 0.0 else _revf(vs)
				_buf(i - 2, "terrain").ribbon(ra, rb, s - step, s, v2, Color.WHITE, false, ca, cb)
				# the near part can be driven on (off the road over a guardrail's end): collision out to 30 m
				var near := 6
				_body(i - 2, "grass").ribbon(_slice(ra, side, near), _slice(rb, side, near), s - step, s, _slicef(v2, side, near), Color.WHITE, true)
			prev = row
			prev_c = cols
			i += 2


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
## 3 km round it, in 1 km tiles; near the road it's kept under the ribbons.
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
			if dr < 300.0:
				h = minf(h, minf(near_y[k], h) - 8.0)
			elif dr < 340.0:
				h -= 8.0 * (340.0 - dr) / 40.0
			hs[k] = h
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
		# the anchorages: concrete blocks the cables run into
		for e in [[s0, anch0], [s1, anch1]]:
			var p: Vector3 = e[1]
			var ground := maxf(st.land_at(p.x, p.z), -3.0)
			var h: float = p.y + 4.0 - ground
			_buf(int(float(e[0]) / st.STEP), "concrete").box(Vector3(p.x, ground + h * 0.5, p.z), Vector3(16.0, h, 22.0),
				Basis(Vector3.UP, -st.heading_at(float(e[0]))))
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
			# the wall between the tubes
			var m0 := st.world_at(sa, st.MEDIAN_D)
			var m1 := st.world_at(sb, st.MEDIAN_D)
			_buf(i, "concrete").box((m0 + m1) * 0.5 + Vector3.UP * 3.8, Vector3(0.6, 7.6, st.STEP + 0.02), Basis(Vector3.UP, -st.heading_at(sa)))
			# the hill over the tubes (the land ribbons start at the road's edges)
			var ra2 := PackedVector3Array()
			var rb2 := PackedVector3Array()
			var vs2 := PackedFloat32Array()
			var cols := PackedColorArray()
			# (from the portals' tops at the ends, rising to the hill's own height 60 m in)
			var fa := clampf(minf(sa - s0, s1 - sa) / 60.0, 0.0, 1.0)
			var fb := clampf(minf(sb - s0, s1 - sb) / 60.0, 0.0, 1.0)
			for d in [wall_l - 1.0, (wall_l + wall_r) * 0.5, wall_r + 1.0]:
				var pa := st.world_at(sa, d)
				var pb := st.world_at(sb, d)
				pa.y = lerpf(pa.y + 10.5, maxf(st.land_at(pa.x, pa.z), pa.y + 10.5), fa)
				pb.y = lerpf(pb.y + 10.5, maxf(st.land_at(pb.x, pb.z), pb.y + 10.5), fb)
				ra2.append(pa)
				rb2.append(pb)
				vs2.append(d)
				cols.append(_land_col(pa, 0.2))
			_buf(i, "terrain").ribbon(ra2, rb2, sa, sb, vs2, Color.WHITE, false, cols, cols)
		# the portals: a concrete face round both tubes' mouths, at each end
		for e in [[s0, 1.0], [s1, -1.0]]:
			var ps: float = e[0]
			var i := int(ps / st.STEP)
			var bas := Basis(Vector3.UP, -st.heading_at(ps))
			var c := st.world_at(ps, (wall_l + wall_r) * 0.5)
			var wide := wall_r - wall_l + 16.0
			var top_y := c.y + 10.5
			# above the mouths
			_buf(i, "concrete").box(Vector3(c.x, (c.y + 7.8 + top_y) * 0.5, c.z), Vector3(wide, top_y - c.y - 7.8, 1.2), bas)
			# each side of the mouths
			for d in [wall_r + 4.0, wall_l - 4.0]:
				var p := st.world_at(ps, d)
				_buf(i, "concrete").box(Vector3(p.x, (p.y + top_y) * 0.5, p.z), Vector3(8.0, top_y - p.y, 1.2), bas)


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
				lamp_heads.append({"s": s, "head": head, "ground": g, "up": up, "radius": 25.0})   # (11 m up, 48 m apart: the pools meet)
		s += 48.0
	for c in per_chunk:
		_multimesh(post, per_chunk[c], "Lamps%03d" % c, ROAD_RANGE)
	lamp_heads.append_array(_toll_lamp_heads())          # (the toll plaza's canopy: a light over each lane)
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
		var b := st.world_at(s, st.OUTER_R + 0.8)
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
		# piers: just outside our barriers, in the median, outside theirs, and further out
		for d in [st.OUTER_R + 3.0, st.MEDIAN_D, st.OUTER_L - 3.0]:
			var p := st.world_at(s, d)
			var t := (p - c).dot(along)
			var q := c + along * t
			_buf(i, "concrete").box(Vector3(q.x, (p.y + deck_y - 0.7) * 0.5, q.z), Vector3(1.1 if d == st.MEDIAN_D else 1.6, deck_y - 0.7 - p.y, 8.0), bas)
		for u in [-60.0, 60.0]:
			var q: Vector3 = c + along * float(u)
			var g := maxf(st.land_at(q.x, q.z), road_y - 4.0)
			if deck_y - 0.7 - g > 1.0:
				_buf(i, "concrete").box(Vector3(q.x, (g + deck_y - 0.7) * 0.5, q.z), Vector3(1.6, deck_y - 0.7 - g, 8.0), bas)


## The ramps off and onto the highway: each a lane of its own (with shoulders and
## barriers) curving away from the gore and down to the ground, where it ends at a
## closed gate (the game's world is the highway).
func _ramps() -> void:
	for r in st.ramps:
		_ramp(r)


func _ramp(r: Dictionary) -> void:
	var path := st.ramp_path(r)
	var pts: PackedVector3Array = path.pts
	var heads: PackedFloat32Array = path.heads
	var n := pts.size() - 1
	var gore: float = r.s
	var right_side: bool = r.side == "right"
	# the deck / road: 6 m of asphalt, a barrier each side, its collision
	var i := int(gore / st.STEP)
	for k in n:
		var a := pts[k]
		var b := pts[k + 1]
		var fa := Vector3(sin(heads[k]), 0, -cos(heads[k]))
		var fb := Vector3(sin(heads[k + 1]), 0, -cos(heads[k + 1]))
		var ra := fa.cross(Vector3.UP).normalized() * -1.0
		var rb := fb.cross(Vector3.UP).normalized() * -1.0
		var w := 3.2
		var row_a := PackedVector3Array([a - ra * w, a + ra * w])
		var row_b := PackedVector3Array([b - rb * w, b + rb * w])
		var vv := PackedFloat32Array([-w, w])
		# (alongside the highway, the ramp's lane is the highway's own extra lane: its own road
		# starts once it's clear of the highway's edge)
		var walk := (1.0 if right_side else -1.0) * (1.0 if r.kind == "off" else -1.0)   # (which way along the road it walks)
		var off_road: float = absf(st.locate(a, posmod(int(gore / st.STEP) + int(k * 2 * walk), st._n)).d - (0.0 if right_side else st.ONCOMING_D))
		if off_road < st.EDGE + st.SHOULDER_R + st.LANE_W + w + 0.3:
			continue
		_buf(i, "asphalt").ribbon(row_a, row_b, k * 4.0, (k + 1) * 4.0, vv)
		_body(i, "asphalt").ribbon(row_a, row_b, k * 4.0, (k + 1) * 4.0, vv, Color.WHITE, true)
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
			_buf(i, "concrete").ribbon(ta, tb, k * 4.0, (k + 1) * 4.0, vs)
			_body(i, "concrete").ribbon(ta, tb, k * 4.0, (k + 1) * 4.0, vs, Color.WHITE, true)
		# under it, while it's off the ground: a deck and piers
		var g := st.land_at(a.x, a.z)
		if a.y - g > 2.0:
			_buf(i, "concrete").quad(a - ra * w + Vector3.UP * -1.5, a + ra * w + Vector3.UP * -1.5, b + rb * w + Vector3.UP * -1.5, b - rb * w + Vector3.UP * -1.5,
				Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
			if k % 8 == 0:
				_buf(i, "concrete").box(Vector3(a.x, (g + a.y - 1.5) * 0.5, a.z), Vector3(1.6, a.y - 1.5 - g, 1.6))
	# the closed gate at its far end
	var e := pts[n]
	var fe := Vector3(sin(heads[n]), 0, -cos(heads[n]))
	_buf(i, "concrete").box(e + Vector3.UP * 0.6, Vector3(7.0, 1.2, 0.8), Basis(Vector3.UP, -heads[n]))
	_body(i, "concrete").box(e + Vector3.UP * 0.6, Vector3(7.0, 1.2, 0.8), Basis(Vector3.UP, -heads[n]), Color.WHITE, true)


## The city's towers, both sides of the expressway: blocks of offices and flats,
## lower near the road, taller back from it and in the middle of town; none on a
## road (this or another part of the loop) or in the water.
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
						real.append([id, Transform3D(rb, Vector3(q.x, gq - 0.3, q.z)), rad])
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
					var bas := Basis(Vector3.UP, -st.heading_at(s)).scaled(Vector3(w, hgt, dep))
					xfs.append(Transform3D(bas, Vector3(p.x, g + hgt * 0.5 - 0.5, p.z)))
					cols.append(palette[_rng.randi() % palette.size()])
			s += _rng.randf_range(40.0, 70.0)
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
## road's verges): pines and broadleaves, in clumps, out to ~400 m from the road.
func _trees() -> void:
	var pine := _tree_mesh(true)
	var broad := _tree_mesh(false)
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
					var p := st.world_at(s + _rng.randf_range(-6.0, 6.0), d)
					if noise.get_noise_2d(p.x, p.z) < -0.05:
						continue                              # (clumps: open ground between)
					var g := st.land_at(p.x, p.z)
					if g < 2.0 or st.in_city(p.x, p.z) or _road_dist(p.x, p.z) < 26.0:
						continue
					var sc := _rng.randf_range(0.75, 1.35)
					var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(sc, sc * _rng.randf_range(0.9, 1.2), sc)), Vector3(p.x, g - 0.2, p.z))
					var c := int(int(s / st.STEP) / CH)
					var key := Vector2i(c, 0 if zone == "hills" and _rng.randf() < 0.7 else 1)
					if not per_chunk.has(key):
						per_chunk[key] = []
					per_chunk[key].append(xf)
		s += 12.0
	for key in per_chunk:
		tree_count += per_chunk[key].size()
		_multimesh(pine if key.y == 0 else broad, per_chunk[key], "Trees%03d_%d" % [key.x, key.y], 1800.0)


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

