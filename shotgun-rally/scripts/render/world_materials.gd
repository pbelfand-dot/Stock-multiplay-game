extends RefCounted
## The world's materials and light, shared by every map (the stage builder, the highway
## loop, anything else). Static: `const WorldMaterials = preload("res://scripts/render/world_materials.gd")`
## (or load() it if it might not be there).
##
## MATERIALS: each returns a ready Material for the current graphics quality (Graphics):
##   asphalt(), road_paint(), concrete(), grass(), dirt(), gravel(), rock(), snow(), ice(),
##   water(), puddle(), steel(), glass_windows(), terrain(), buildings(), foliage(), props()
## They work on any mesh:
##   - no UVs needed: textures are projected in world space, in metres (top-down, and from
##     the sides too for rock, concrete, walls; everything on HIGH / ULTRA);
##   - or the mesh's own UVs, in metres: opts {"uv": true} (e.g. UV.x across a road, UV.y along it);
##   - vertex colours tint the texture (white, or no colours: the texture's own colour), or
##     with opts {"vertex": "colour"} they ARE the colour and the texture adds its detail
##     (the stage builder's way: its colours keep their meaning: wheel tracks, paint, snow).
##   terrain() picks grass / dirt / rock / snow by the vertex colour (green / brown / grey /
##   white), asphalt() in "colour" mode shows bright vertex colours as painted lines.
## opts (all optional): "uv" (bool), "vertex" ("tint" | "colour"), "tint" (Color),
##   "scale" (metres one repeat of the texture covers), "rough" (x roughness),
##   "normal" (x normal-map strength), "painted" (steel(): painted, not bare galvanised),
##   "streaks" (asphalt() with "uv": tyre-worn streaks along UV.y, default 0.18), "uv_along"
##   ("y" | "x": which UV runs along the road)
## LOW quality, or the textures missing (the web build): flat vertex colours, the old look.
## Materials are cached: the same call returns the same material (clear_cache() after a
## quality change; the stage builder builds fresh each stage).
##
## LIGHT:
##   setup(parent, mood, hour = -1, opts = {}) -> {env, sun, world_environment, mood, horizon, hour, night}:
##     adds a WorldEnvironment and the sun to parent for "day" | "golden" | "overcast" |
##     "night" (or the hour) and applies the quality to the screen (a --mood=... / --hour=...
##     command line overrides, for pictures)
##   environment(mood) -> Environment;  sun(mood) -> DirectionalLight3D (shadows set up)
##   horizon_colour(mood) -> Color: the sky at the horizon (for things that fade into it)
##   night: true while a dark mood is up; night_amount: 0 (day) .. 1 (night), fading
##     through dusk and dawn (the cars' lamps, street lights, lit windows read it)
## TIME OF DAY: setup(parent, mood, hour) with hour 0.0-24.0 lights the world for that
##   hour (the sun on its arc: up ~06:00, 60 degrees at 13:00, down ~19:30; the moon at
##   night), the mood then only saying "overcast" or not. state(mood, hour) -> the numbers;
##   environment_at(hour, overcast), sun_at(hour, overcast), sun_arc(hour) -> (elev, yaw).
## NIGHT (a touge, a highway, the LAKESHORE LOOP's viaducts and city, a town):
##   street_lights(parent, [{"head": Vector3, "ground": Vector3, "up"?, "radius"?, "s"?}, ...])
##     -> StreetLamps (scripts/stage/street_lamps.gd) or null by day: the lit heads, glare
##     halos and faked pools of light on the road, a few real lights following its `target`
##     (the player's car). street_lamp_head(): the head's material (lit by night_amount).
##   buildings(): some windows lit at night. Traffic / plain car models:
##     CarLook.glow_model(model) (scripts/render/car_look.gd) after painting: their lamps glow.
##   A car's beams and lamp glow at night: CarLamps (scripts/vehicle/car_lamps.gd).
## The speed blur (SpeedBlur) comes with setup(): MEDIUM+, Forward+.
## The skies are photographed (CC0, Poly Haven; tools/world_textures.py makes them), drawn
## by a sky shader that turns each so its sun is where the DirectionalLight is.

const Graphics = preload("res://scripts/render/graphics.gd")
const SpeedBlur = preload("res://scripts/render/speed_blur.gd")
const TEX_DIR := "res://assets/textures/world/"
const SKY_DIR := "res://assets/textures/sky/"

static var night := false
## The land's own ground and road (the stage builder sets them from its biome before it builds):
## ground "forest" lays the forest floor (Poly Haven Forest Ground 01) where the ground is green;
## asphalt "asphalt2" a fresher, finer asphalt (Poly Haven Asphalt 02). "" the defaults.
static var ground_style := ""
static var asphalt_style := ""
## How wet the roads are (0 dry .. 1 standing water; Track Mode's WET weather sets it before it builds,
## everything else leaves it at 0): the asphalt, its paint and concrete darker and glossy (a wet road
## mirrors the sky and the lights; HIGH and ULTRA's screen-space reflections show the cars in it).
const WET_SURFACES := ["asphalt", "road_paint", "concrete"]
static var wet := 0.0
static var _cache := {}
static var _shaders := {}
static var _tex_info := {}
static var _sky_info := {}
static var _textures := {}

## Each surface's texture and how it reflects: tex (assets/textures/world/<tex>_*),
## rough (x the texture's roughness), spec, normal (strength), tri (always triplanar:
## walls and banks), detail ("colour" mode: how much of the texture shows), photo
## ("colour" mode: how much of the hue comes from the photo), vc_sat / vc_gain (the
## vertex colours graded: the flat-colour scheme was brighter and more saturated than life).
const SURFACES := {
	"asphalt": {"tex": "asphalt", "rough": 1.05, "spec": 0.5, "normal": 0.9, "detail": 1.0, "photo": 0.3},
	"road_paint": {"tex": "asphalt", "rough": 0.75, "spec": 0.5, "normal": 0.35, "detail": 0.4},
	"concrete": {"tex": "concrete", "rough": 1.5, "spec": 0.45, "normal": 0.7, "detail": 0.8, "tri": true, "photo": 0.35},
	"grass": {"tex": "grass", "rough": 1.25, "spec": 0.3, "normal": 1.0, "detail": 1.0, "photo": 0.2, "vc_sat": 0.85, "vc_gain": 0.88},
	"dirt": {"tex": "dirt", "rough": 0.9, "spec": 0.4, "normal": 1.0, "detail": 1.0, "photo": 0.5},
	"gravel": {"tex": "gravel", "rough": 1.05, "spec": 0.4, "normal": 1.2, "detail": 1.0, "photo": 0.45},
	"rock": {"tex": "rock", "rough": 1.05, "spec": 0.4, "normal": 1.2, "detail": 1.0, "tri": true, "photo": 0.5},
	"snow": {"tex": "snow", "rough": 0.9, "spec": 0.5, "normal": 0.7, "detail": 0.6, "photo": 0.2},
	"ice": {"tex": "snow", "rough": 0.12, "spec": 0.7, "normal": 0.25, "detail": 0.25},
	"buildings": {"tex": "concrete", "rough": 1.4, "spec": 0.4, "normal": 0.5, "detail": 0.55, "tri": true, "vc_sat": 0.85, "vc_gain": 0.92},
	"foliage": {"tex": "grass", "rough": 1.3, "spec": 0.25, "normal": 0.8, "detail": 0.75, "tri": true, "scale": 1.2,
		"vc_sat": 0.82, "vc_gain": 0.62},
}

## The moods: the sky (assets/textures/sky/<sky>.webp, "" = drawn), its brightness, the sun
## (elevation in degrees: -1 = the sky photo's own; yaw; colour; energy), exposure, fog,
## the shadows' darkness, a colour grade, and the drawn sky's colours (linear) when there's
## no photo (the web build, night).
const MOODS := {
	"day": {"sky": "day", "sky_energy": 0.75, "sun_elev": -1.0, "sun_yaw": 35.0, "sun_color": Color(1.0, 0.96, 0.89),
		"sun_energy": 5.5, "exposure": 0.66, "fog": 0.0012, "shadow": 1.0, "scatter": 0.08,
		"zenith": Color(0.25, 0.42, 0.85), "horizon": Color(0.75, 0.85, 1.0), "grade": [0.0, 1.06, 1.08]},
	"golden": {"sky": "golden", "sky_energy": 0.85, "sun_elev": 14.0, "sun_yaw": 65.0, "sun_color": Color(1.0, 0.7, 0.42),
		"sun_energy": 3.0, "exposure": 1.0, "fog": 0.0021, "shadow": 1.0, "scatter": 0.3,
		"zenith": Color(0.2, 0.3, 0.6), "horizon": Color(1.2, 0.85, 0.6), "grade": [1.0, 1.05, 1.1]},
	"overcast": {"sky": "overcast", "sky_energy": 1.3, "sun_elev": 62.0, "sun_yaw": 20.0, "sun_color": Color(0.86, 0.89, 0.94),
		"sun_energy": 0.45, "exposure": 1.05, "fog": 0.011, "shadow": 0.55, "scatter": 0.0,
		"zenith": Color(0.95, 0.97, 1.0), "horizon": Color(0.6, 0.6, 0.6), "grade": [2.0, 1.03, 0.92]},
	"night": {"sky": "", "sky_energy": 1.0, "sun_elev": 38.0, "sun_yaw": 150.0, "sun_color": Color(0.55, 0.66, 0.95),
		"sun_energy": 0.07, "exposure": 1.6, "fog": 0.004, "shadow": 0.9, "scatter": 0.0,
		"zenith": Color(0.0015, 0.0025, 0.006), "horizon": Color(0.008, 0.01, 0.018), "grade": [3.0, 1.04, 0.9]},
}


# ── materials ─────────────────────────────────────────────────────────────

static func asphalt(opts := {}) -> Material:
	return _surface("asphalt", opts)


## Road markings on their own mesh: the asphalt's grain, white (or the tint / vertex colour), a touch shinier.
static func road_paint(opts := {}) -> Material:
	var o := opts.duplicate()
	if not o.has("tint") and o.get("vertex", "tint") == "tint":
		o["tint"] = Color(0.86, 0.86, 0.82)
	return _surface("road_paint", o)


static func concrete(opts := {}) -> Material:
	return _surface("concrete", opts)


static func grass(opts := {}) -> Material:
	return _surface("grass", opts)


static func dirt(opts := {}) -> Material:
	return _surface("dirt", opts)


static func gravel(opts := {}) -> Material:
	return _surface("gravel", opts)


static func rock(opts := {}) -> Material:
	return _surface("rock", opts)


static func snow(opts := {}) -> Material:
	return _surface("snow", opts)


static func ice(opts := {}) -> Material:
	return _surface("ice", opts)


## The ground: grass, dirt, rock or snow by the vertex colour (green / brown / grey / white),
## the colour itself from the vertex colour (the texture adds its detail).
static func terrain(opts := {}) -> Material:
	var key := _key("terrain", opts)
	if _cache.has(key):
		return _cache[key]
	var m: Material
	if not _can_texture(["grass", "dirt", "rock", "snow"]):
		m = _flat("grass", {"vertex": "colour"})
	else:
		var sm := ShaderMaterial.new()
		sm.shader = _shader(["TERRAIN", "VC_COLOUR"] + _quality_defs())
		for t in ["grass", "dirt", "rock", "snow"]:
			sm.set_shader_parameter(t + "_tex", _tex(_tex_for(t) + "_albedo"))
			sm.set_shader_parameter(t + "_nrm", _tex(_tex_for(t) + "_normal"))
			sm.set_shader_parameter(t + "_mean", _mean(_tex_for(t)))
		sm.set_shader_parameter("scales", Vector4(1.0 / _size(_tex_for("grass")), 1.0 / _size("dirt"), 1.0 / _size("rock"), 1.0 / _size("snow")))
		sm.set_shader_parameter("normal_strength", float(opts.get("normal", 1.0)))
		sm.set_shader_parameter("rough_scale", float(opts.get("rough", 1.15)))
		sm.set_shader_parameter("spec", 0.35)
		sm.set_shader_parameter("detail", 1.0)
		sm.set_shader_parameter("photo", 0.2)                # (the grass photo is full of dry leaves)
		sm.set_shader_parameter("vc_sat", 0.92)
		sm.set_shader_parameter("vc_gain", 0.88)
		m = sm
	_cache[key] = m
	return m


## The stage builder's houses and town buildings: plastered walls (the vertex colour, a
## concrete grain), roofs and shutters as coloured, the windows (dark blue-grey) glassy.
static func buildings(opts := {}) -> Material:
	var o := opts.duplicate()
	o["vertex"] = "colour"
	o["glass"] = true
	o["night"] = snappedf(night_amount, 0.05)       # (lit windows at night, fading in at dusk)
	return _surface("buildings", o)


## Water (a stream, a pond): dark, glassy, rippling. Opaque (so it gets screen-space reflections).
static func water(opts := {}) -> Material:
	return _liquid("water", opts.get("tint", Color(0.05, 0.085, 0.08)), 0.03, 1.0)


## A muddy puddle on the road: brown, still, glossy.
static func puddle(opts := {}) -> Material:
	return _liquid("puddle", opts.get("tint", Color(0.11, 0.08, 0.05)), 0.06, 0.35)


## Painted or galvanised steel (barriers, bridge cables, gantries, lamp posts): the vertex
## colour (or tint) as the paint / metal colour. opts.painted: paint (not bare metal).
static func steel(opts := {}) -> Material:
	var key := _key("steel", opts)
	if _cache.has(key):
		return _cache[key]
	var m := _flat_base(opts)
	if Graphics.level() != "low":
		var painted := bool(opts.get("painted", false))
		m.metallic = 0.05 if painted else 0.75
		m.roughness = 0.38 if painted else 0.42
		m.metallic_specular = 0.5
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	_cache[key] = m
	return m


## Buildings' windows on a mesh of their own: dark, smooth, the sky in them.
static func glass_windows(opts := {}) -> Material:
	var key := _key("glass_windows", opts)
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = opts.get("tint", Color(0.06, 0.07, 0.085))
	m.vertex_color_use_as_albedo = bool(opts.get("vertex", "") == "colour")
	m.vertex_color_is_srgb = true
	m.roughness = 0.04
	m.metallic = 0.0
	m.metallic_specular = 1.0
	_cache[key] = m
	return m


## The trees and undergrowth (vertex-coloured low-poly models): matte, the sun through the leaves.
static func foliage(opts := {}) -> Material:
	if _can_texture(["grass"]):
		var o := opts.duplicate()
		o["vertex"] = "colour"
		o["foliage"] = true
		return _surface("foliage", o)
	var key := _key("foliage", opts)
	if _cache.has(key):
		return _cache[key]
	var m := _flat_base(opts)
	if Graphics.level() != "low":
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		m.roughness = 0.88
		m.metallic_specular = 0.22
		m.backlight_enabled = true
		m.backlight = Color(0.16, 0.2, 0.07)
	_cache[key] = m
	return m


## Everything else that's vertex-coloured (signs, tape, bridge timbers, posts): plain paint and wood.
static func props(opts := {}) -> Material:
	var key := _key("props", opts)
	if _cache.has(key):
		return _cache[key]
	var m := _flat_base(opts)
	if Graphics.level() != "low":
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		m.roughness = float(opts.get("roughness", 0.72))
		m.metallic_specular = 0.4
	_cache[key] = m
	return m


## A street lamp's head (the glass under it): sodium orange, lit at night.
static func street_lamp_head(opts := {}) -> Material:
	var lit := snappedf(night_amount, 0.05)
	var key := _key("lamp_head", opts) + str(lit)
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	var col: Color = opts.get("colour", SODIUM)
	m.albedo_color = Color(0.85, 0.82, 0.75)
	m.roughness = 0.3
	m.emission_enabled = lit > 0.0
	m.emission = col
	m.emission_energy_multiplier = 14.0 * lit
	_cache[key] = m
	return m


const SODIUM := Color(1.0, 0.58, 0.22)
## The road's meshes go on this render layer (as well as no other): the street lamps' few
## real lights leave the road to their faked pools (no light counted twice), the cars'
## headlights and the sun light it as everything else.
const ROAD_LAYER := 1 << 11

## Street lights at night (nothing by day): a StreetLamps node (scripts/stage/street_lamps.gd)
## added to parent for lamps [{"head": Vector3 (where its glass is), "ground": Vector3 (the
## road under it), "up": the road's normal there (default up), "radius": the pool of light's
## (m, default 9), "s"?: along the road}]: the lit heads, glare halos, pools of light on the
## road (faked: a multiplying disc on Forward+, an added one on Compatibility; hundreds cost
## next to nothing) and a few real lights round its `target` (the player's car: the game
## sets it). Returns it, or null by day; at dusk / dawn (night_amount between) it's dimmer.
static func street_lights(parent: Node3D, lamps: Array) -> Node3D:
	if night_amount < 0.05 or lamps.is_empty():
		return null
	var sl: Node3D = (load("res://scripts/stage/street_lamps.gd") as GDScript).new()
	parent.add_child(sl)
	sl.setup(lamps)
	return sl


## The material for a stage-builder part by its name (and the surface the tyres feel).
static func for_part(node_name: String, surface := "") -> Material:
	var n := node_name.rstrip("0123456789")
	match n:
		"Ground", "Mountainside", "Base":
			return terrain()
		"Houses", "TownBuildings":
			return buildings()
		"StoneWalls":
			return concrete({"vertex": "colour"})
		"ConcreteBarriers", "Pavements":
			return concrete({"vertex": "colour"})
		"TownSquares":
			return rock({"vertex": "colour", "scale": 1.2})
		"GullyFloor":
			return dirt({"vertex": "colour"})
		"Armco", "LampPosts", "Gantries":
			return steel()
		"Tape", "StartLine", "TougeProps":
			return props({"roughness": 0.55})
		"BridgeDeck", "BridgeFrame":
			return props({"roughness": 0.85})
	match surface:
		"gravel", "asphalt", "snow", "ice", "grass", "dirt", "mud":
			return road(surface)
	return props()


## A road surface's material ("gravel", "asphalt", "snow", "ice", "mud"), the vertex colours as the colour.
static func road(surf: String) -> Material:
	match surf:
		"asphalt":
			return asphalt({"vertex": "colour", "paint": true})
		"snow":
			return snow({"vertex": "colour"})
		"ice":
			return ice({"vertex": "colour"})
		"mud", "dirt":
			return dirt({"vertex": "colour"})
		"grass":
			return terrain()
	return gravel({"vertex": "colour"})


## Smooth shading for this stage-builder part (the ground and the road; MEDIUM and up).
static func smooth(node_name: String) -> bool:
	if not bool(Graphics.get_value("smooth")) or Graphics.headless():
		return false
	return node_name.begins_with("Road") or node_name in ["Ground", "Mountainside"]


static func clear_cache() -> void:
	_cache.clear()


# ── light ─────────────────────────────────────────────────────────────────

## The hours (time of day): [hour, sky photo ("" = the drawn night sky), sky energy, the
## sun's colour, its energy (the moon's at night), exposure, fog, sun scatter in the fog,
## colour grade (_grade_lut), night (0..1: the street lamps, the cars' lamps, lit windows)].
## Between two the light blends; the sun's place comes from its arc (sun_arc). 13.0 is the
## "day" mood's light, 18.3 the "golden" one's, 23.0 "night".
const HOURS := [
	[0.0, "", 1.0, Color(0.55, 0.66, 0.95), 0.07, 1.6, 0.004, 0.0, 3, 1.0],
	[4.8, "", 1.0, Color(0.55, 0.66, 0.95), 0.07, 1.6, 0.004, 0.0, 3, 1.0],
	[5.9, "golden", 0.14, Color(1.0, 0.5, 0.3), 0.0, 1.6, 0.0032, 0.15, 1, 0.75],
	[6.7, "golden", 0.5, Color(1.0, 0.56, 0.32), 2.2, 1.18, 0.0028, 0.35, 1, 0.0],
	[8.6, "day", 0.7, Color(1.0, 0.88, 0.74), 4.6, 0.74, 0.0016, 0.12, 0, 0.0],
	[13.0, "day", 0.75, Color(1.0, 0.96, 0.89), 5.5, 0.66, 0.0012, 0.08, 0, 0.0],
	[16.6, "day", 0.75, Color(1.0, 0.92, 0.8), 5.1, 0.68, 0.0014, 0.12, 0, 0.0],
	[18.3, "golden", 0.85, Color(1.0, 0.7, 0.42), 3.0, 1.0, 0.0021, 0.3, 1, 0.0],
	[19.4, "golden", 0.42, Color(1.0, 0.46, 0.22), 1.4, 1.3, 0.0026, 0.4, 1, 0.12],
	[20.2, "golden", 0.09, Color(0.9, 0.5, 0.35), 0.0, 1.6, 0.003, 0.1, 3, 0.75],
	[21.0, "", 1.0, Color(0.55, 0.66, 0.95), 0.07, 1.6, 0.004, 0.0, 3, 1.0],
	[24.0, "", 1.0, Color(0.55, 0.66, 0.95), 0.07, 1.6, 0.004, 0.0, 3, 1.0],
]
const MOOD_HOURS := {"day": 13.0, "golden": 18.3, "overcast": 13.0, "night": 23.0}
const MOON := Vector2(38.0, 150.0)       # the moon: elevation, yaw (degrees)

static var night_amount := 0.0           # 0 day .. 1 night: the night pieces fade with it


## A WorldEnvironment and the sun for the mood, or for an hour (0.0-24.0: the time of day;
## the mood then only says whether it's overcast), added to parent; the quality applied to
## the screen. opts: "fog" (x the fog: a highway's long views want less). A --mood=... or
## --hour=... command line overrides (pictures). Returns {env,
## sun, world_environment, mood (the nearest mood, for things built per mood: the far
## mountains' colours), horizon (Color), hour, night (0..1)}.
static func setup(parent: Node, mood := "day", hour := -1.0, opts := {}) -> Dictionary:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mood="):
			mood = a.trim_prefix("--mood=")
		elif a.begins_with("--hour="):
			hour = float(a.trim_prefix("--hour="))
	if not MOODS.has(mood):
		mood = "day"
	var s := state(mood, hour)
	s.fog = float(s.fog) * float(opts.get("fog", 1.0))
	night_amount = s.night
	night = s.night > 0.5
	var env := _environment(s)
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	parent.add_child(we)
	var light := _sun(s)
	light.name = "Sun"
	parent.add_child(light)
	_screen_setup.call_deferred(parent, we)
	return {"env": env, "sun": light, "world_environment": we, "mood": s.mood, "horizon": s.horizon_srgb, "hour": hour,
		"night": s.night}


## The quality on the screen, the speed blur: once parent is in the tree (a frame later, if need be).
static func _screen_setup(parent, we) -> void:
	if is_instance_valid(parent) and is_instance_valid(we) and parent.is_inside_tree():
		Graphics.apply_viewport(parent.get_viewport())
		SpeedBlur.attach(parent, we)


## The light for a mood (hour < 0) or an hour of the day, as numbers (environment / sun build from it).
static func state(mood := "day", hour := -1.0) -> Dictionary:
	if hour < 0.0:
		return _mood_state(mood)
	return _hour_state(fposmod(hour, 24.0), mood == "overcast")


static func environment(mood := "day") -> Environment:
	return _environment(state(mood))


static func sun(mood := "day") -> DirectionalLight3D:
	return _sun(state(mood))


## The same for an hour (0.0-24.0), clear or overcast.
static func environment_at(hour: float, overcast := false) -> Environment:
	return _environment(state("overcast" if overcast else "day", hour))


static func sun_at(hour: float, overcast := false) -> DirectionalLight3D:
	return _sun(state("overcast" if overcast else "day", hour))


## The sky at the horizon (sRGB, as the scene draws it before the exposure): the far
## mountains and the fog fade into it.
static func horizon_colour(mood := "day", hour := -1.0) -> Color:
	return state(mood, hour).horizon_srgb


## The sun's place at an hour: Vector2(elevation, yaw) in degrees: up at about 06:00, 60
## degrees at 13:00, down at about 19:30; below the horizon at night.
static func sun_arc(hour: float) -> Vector2:
	var h := fposmod(hour, 24.0)
	var el := -12.0
	if h >= 6.0 and h <= 13.0:
		el = 60.0 * sin(PI * 0.5 * (h - 6.0) / 7.0)
	elif h > 13.0 and h <= 19.5:
		el = 60.0 * sin(PI * 0.5 * (19.5 - h) / 6.5)
	elif h > 19.5 and h < 21.0:
		el = -8.0 * (h - 19.5) / 1.5
	elif h > 5.0 and h < 6.0:
		el = -8.0 * (6.0 - h)
	return Vector2(el, lerpf(-75.0, 105.0, clampf((h - 6.0) / 13.5, 0.0, 1.0)))


static func _mood_state(mood: String) -> Dictionary:
	var md: Dictionary = _mood(mood)
	var s := {"mood": mood, "sky_a": md.sky, "sky_b": "", "mix": 0.0, "energy": float(md.sky_energy),
		"elev": _sun_elevation(mood), "yaw": float(md.sun_yaw), "sun_color": md.sun_color, "sun_energy": float(md.sun_energy),
		"exposure": float(md.exposure), "fog": float(md.fog), "scatter": float(md.scatter), "shadow": float(md.shadow),
		"grade": md.grade, "night": 1.0 if mood == "night" else 0.0, "sun_disc": 0.0 if mood == "overcast" else 60.0,
		"zenith": md.zenith, "horizon": md.horizon}
	s.horizon_srgb = _horizon_of(s)
	return s


static func _hour_state(h: float, overcast: bool) -> Dictionary:
	var i := 0
	while i < HOURS.size() - 2 and float(HOURS[i + 1][0]) <= h:
		i += 1
	var a: Array = HOURS[i]
	var b: Array = HOURS[i + 1]
	var t := clampf((h - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-4), 0.0, 1.0)
	var arc := sun_arc(h)
	var sun_up := arc.x > -1.5
	var nt := lerpf(float(a[9]), float(b[9]), t)
	var s := {"sky_a": a[1], "sky_b": b[1], "mix": t, "energy": lerpf(float(a[2]), float(b[2]), t),
		"elev": maxf(arc.x, 0.5) if sun_up else MOON.x, "yaw": arc.y if sun_up else MOON.y,
		"sun_color": (a[3] as Color).lerp(b[3], t), "sun_energy": lerpf(float(a[4]), float(b[4]), t),
		"exposure": lerpf(float(a[5]), float(b[5]), t), "fog": lerpf(float(a[6]), float(b[6]), t),
		"scatter": lerpf(float(a[7]), float(b[7]), t), "shadow": 1.0, "night": nt,
		"grade": MOODS.day.grade if (a[8] if t < 0.5 else b[8]) == 0 else (MOODS.golden.grade if (a[8] if t < 0.5 else b[8]) == 1 else MOODS.night.grade),
		"sun_disc": 60.0 if sun_up else 14.0, "zenith": MOODS.night.zenith, "horizon": MOODS.night.horizon,
		"sky_yaw": arc.y}
	if sun_up:
		s.sun_energy *= smoothstep(-1.5, 3.0, arc.x)          # (the sun's light fades as it sets)
	else:
		s.sun_energy = 0.07 * nt                               # (the moon)
		s.sun_color = MOODS.night.sun_color
	s.mood = "night" if nt > 0.5 else ("golden" if arc.x < 22.0 else "day")
	if overcast:
		var day := 1.0 - nt
		for k in ["sky_a", "sky_b"]:
			if s[k] != "":
				s[k] = "overcast"
		s.energy *= 1.3 / 0.75
		s.sun_energy *= lerpf(1.0, 0.09, day) if sun_up else 1.0
		s.fog = lerpf(s.fog, 0.011, day)
		s.exposure = lerpf(s.exposure, 1.05, day * 0.8)
		s.shadow = 0.55
		s.sun_disc = 0.0
		s.scatter = 0.0
		if day > 0.5:
			s.grade = MOODS.overcast.grade
			s.mood = "overcast"
	s.horizon_srgb = _horizon_of(s)
	return s


## A sky slot's horizon colour (linear): its photo's, or the drawn sky's.
static func _slot_horizon(sky_name: String, s: Dictionary) -> Color:
	var info := _sky(sky_name)
	if not info.is_empty():
		var h: Array = info.horizon_linear
		return Color(h[0], h[1], h[2])
	return s.horizon if sky_name == "" else MOODS.day.horizon


static func _horizon_of(s: Dictionary) -> Color:
	var lin := _slot_horizon(s.sky_a, s).lerp(_slot_horizon(s.sky_b, s), float(s.mix)) * float(s.energy)
	return Color(lin.r, lin.g, lin.b).linear_to_srgb()


static func _environment(s: Dictionary) -> Environment:
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = _sky_material(s)
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	for a in OS.get_cmdline_user_args():
		if a == "--look_aces":
			env.tonemap_mode = Environment.TONE_MAPPER_ACES
			env.tonemap_white = 6.0
		elif a == "--look_filmic":
			env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			env.tonemap_white = 6.0
	env.tonemap_exposure = s.exposure
	env.tonemap_agx_white = 12.0
	env.tonemap_agx_contrast = 1.22
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = s.fog
	env.fog_light_color = s.horizon_srgb
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = s.scatter
	env.fog_sky_affect = 0.0
	var g: Array = s.grade
	env.adjustment_enabled = true
	env.adjustment_contrast = g[1]
	env.adjustment_saturation = g[2]
	env.adjustment_color_correction = _grade_lut(int(g[0]))
	for a in OS.get_cmdline_user_args():
		if a == "--look_noadjust":
			env.adjustment_enabled = false
		elif a == "--look_noglow":
			env.glow_enabled = false
	env.set_meta("night", float(s.night))               # (Graphics: Compatibility's glow at night only)
	Graphics.apply_environment(env)
	return env


## The sun (or the moon, at night): its place, colour, energy and shadows for the quality.
static func _sun(s: Dictionary) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-float(s.elev)), deg_to_rad(float(s.yaw)), 0.0)
	light.light_color = s.sun_color
	light.light_energy = s.sun_energy
	# (no shadows from the moon: too faint to see, and the shadow map's passes saved at night)
	light.shadow_enabled = not (OS.has_feature("web") and Graphics.level() == "low") and float(s.night) < 0.9
	light.shadow_opacity = s.shadow if Graphics.level() != "low" else minf(s.shadow, 0.85)
	light.shadow_bias = 0.03
	light.shadow_normal_bias = 1.4
	light.shadow_blur = 1.2
	Graphics.apply_sun(light)
	return light


## A mood's settings; a command line --look_<key>=<number> overrides one (for tuning).
static func _mood(mood: String) -> Dictionary:
	var md: Dictionary = (MOODS.get(mood, MOODS.day) as Dictionary).duplicate()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--look_"):
			var kv := a.trim_prefix("--look_").split("=", true, 1)
			if kv.size() == 2 and md.has(kv[0]) and typeof(md[kv[0]]) == TYPE_FLOAT:
				md[kv[0]] = float(kv[1])
	return md


static func _sun_elevation(mood: String) -> float:
	var md: Dictionary = _mood(mood)
	if float(md.sun_elev) >= 0.0:
		return md.sun_elev
	var info := _sky(md.sky)
	return float(info.get("sun_elevation", 50.0))


static func _sky(sky_name: String) -> Dictionary:
	if sky_name == "":
		return {}
	if _sky_info.is_empty() and FileAccess.file_exists(SKY_DIR + "sky.json"):
		_sky_info = JSON.parse_string(FileAccess.get_file_as_string(SKY_DIR + "sky.json"))
	if not _sky_info.has(sky_name) or not ResourceLoader.exists(SKY_DIR + sky_name + ".webp"):
		return {}
	return _sky_info[sky_name]


## The sky: one photo (a mood), or two blended (an hour between two), or the drawn sky (night,
## or no photos: the web build); each photo turned so its sun is where the light comes from.
static func _sky_material(s: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _sky_shader()
	# (turned by the sun's own azimuth, even below the horizon: the moon's would swing the sunset round)
	var sky_yaw := float(s.get("sky_yaw", s.yaw))
	var to_light := Basis.from_euler(Vector3(deg_to_rad(-float(s.elev)), deg_to_rad(sky_yaw), 0.0)) * Vector3(0, 0, 1)
	var phi_light := atan2(to_light.x, -to_light.z)
	for slot in [["sky_a", ""], ["sky_b", "_b"]]:
		var nm: String = s[slot[0]]
		var info := _sky(nm)
		var sfx: String = slot[1]
		m.set_shader_parameter("has_tex" + sfx, not info.is_empty())
		var zen: Color = s.zenith if nm == "" else MOODS.day.zenith
		var hor: Color = s.horizon if nm == "" else MOODS.day.horizon
		if not info.is_empty():
			m.set_shader_parameter("sky_tex" + sfx, load(SKY_DIR + nm + ".webp"))
			m.set_shader_parameter("lo", float(info.lo))
			m.set_shader_parameter("hi", float(info.hi))
			m.set_shader_parameter("v_max", (90.0 + float(info.below_deg)) / 180.0)
			# the light's azimuth (as the shader measures it: atan(x, -z)) against the photo's sun
			m.set_shader_parameter("yaw" + sfx, (float(info.sun_u) - 0.5) * TAU - phi_light)
			var h: Array = info.horizon_linear
			hor = Color(h[0], h[1], h[2])
		m.set_shader_parameter("zenith_lin" + sfx, Vector3(zen.r, zen.g, zen.b))
		m.set_shader_parameter("horizon_lin" + sfx, Vector3(hor.r, hor.g, hor.b))
	m.set_shader_parameter("mix_b", float(s.mix) if s.sky_b != s.sky_a else 0.0)
	m.set_shader_parameter("energy", float(s.energy))
	var ground := Color(0.07, 0.075, 0.055) * lerpf(1.0, 0.02, float(s.night))
	m.set_shader_parameter("ground_lin", Vector3(ground.r, ground.g, ground.b))
	m.set_shader_parameter("sun_disc", float(s.sun_disc))
	m.set_shader_parameter("stars", float(s.night))
	return m


## A 3D colour-grading table (applied after the tonemapper): a gentle S-curve, and a tint
## split between the shadows and the highlights. kind: 0 day (warm light, cool shade),
## 1 golden (warmer), 2 overcast (cool, a little flat), 3 night (blue).
static func _grade_lut(kind: int) -> ImageTexture3D:
	var key := "lut%d" % kind
	if _cache.has(key):
		return _cache[key]
	var shadows: Vector3 = [Vector3(-0.012, 0.0, 0.014), Vector3(0.0, -0.004, 0.012), Vector3(-0.004, 0.0, 0.01), Vector3(-0.01, 0.0, 0.03)][kind]
	var highs: Vector3 = [Vector3(0.014, 0.006, -0.014), Vector3(0.03, 0.01, -0.025), Vector3(-0.004, 0.0, 0.006), Vector3(-0.01, 0.0, 0.02)][kind]
	var n := 17
	var images: Array[Image] = []
	for bi in n:
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		for gi in n:
			for ri in n:
				var c := Vector3(ri, gi, bi) / float(n - 1)
				var l := c.dot(Vector3(0.2126, 0.7152, 0.0722))
				var curve := Vector3(smoothstep(0.0, 1.0, c.x), smoothstep(0.0, 1.0, c.y), smoothstep(0.0, 1.0, c.z))
				c = c.lerp(curve, 0.12)
				c += shadows * (1.0 - l) * (1.0 - l) + highs * l * l
				img.set_pixel(ri, gi, Color(clampf(c.x, 0.0, 1.0), clampf(c.y, 0.0, 1.0), clampf(c.z, 0.0, 1.0)))
		images.append(img)
	var t := ImageTexture3D.new()
	t.create(Image.FORMAT_RGB8, n, n, n, false, images)
	_cache[key] = t
	return t


# ── the material machinery ────────────────────────────────────────────────

static func _key(n: String, opts: Dictionary) -> String:
	return "%s|%s|%s|%s|%s|%s|%.2f" % [n, str(opts), Graphics.level(), Graphics.forward(), ground_style, asphalt_style,
		wet if n in WET_SURFACES else 0.0]


## The texture a surface uses: its own, or the land's (asphalt_style, ground_style) when that's there.
static func _tex_for(t: String) -> String:
	if t == "asphalt" and asphalt_style != "" and _can_texture([asphalt_style]):
		return asphalt_style
	if t == "grass" and ground_style != "" and _can_texture([ground_style]):
		return ground_style
	return t


static func _surface(n: String, opts: Dictionary) -> Material:
	var key := _key(n, opts)
	if _cache.has(key):
		return _cache[key]
	var sd: Dictionary = SURFACES[n]
	var m: Material
	if not _can_texture([sd.tex]):
		m = _flat(n, opts)
	else:
		var defs := _quality_defs()
		if sd.get("tri", false) and not "TRIPLANAR" in defs:
			defs.append("TRIPLANAR")
		if opts.get("uv", false):
			defs.append("UV_MODE")
		var colour_mode: bool = opts.get("vertex", "tint") == "colour"
		if colour_mode:
			defs.append("VC_COLOUR")
		if opts.get("paint", false) and colour_mode:
			defs.append("PAINT")
		if opts.get("glass", false):
			defs.append("GLASS")
		if opts.get("foliage", false):
			defs.append("FOLIAGE")
		var sm := ShaderMaterial.new()
		sm.shader = _shader(defs)
		var tx: String = _tex_for(sd.tex) if sd.tex == "asphalt" else str(sd.tex)
		sm.set_shader_parameter("albedo_tex", _tex(tx + "_albedo"))
		sm.set_shader_parameter("normal_tex", _tex(tx + "_normal"))
		sm.set_shader_parameter("tex_mean", _mean(tx))
		sm.set_shader_parameter("tex_scale", 1.0 / float(opts.get("scale", sd.get("scale", _size(tx)))))
		sm.set_shader_parameter("normal_strength", float(sd.normal) * float(opts.get("normal", 1.0)))
		sm.set_shader_parameter("rough_scale", float(sd.rough) * float(opts.get("rough", 1.0)))
		sm.set_shader_parameter("spec", float(sd.spec))
		sm.set_shader_parameter("detail", float(sd.detail))
		sm.set_shader_parameter("photo", float(sd.get("photo", 0.0)))
		sm.set_shader_parameter("vc_sat", float(sd.get("vc_sat", 1.0)))
		sm.set_shader_parameter("vc_gain", float(sd.get("vc_gain", 1.0)))
		sm.set_shader_parameter("tint", opts.get("tint", Color.WHITE))
		if opts.get("foliage", false):
			sm.set_shader_parameter("backlight", Vector3(0.12, 0.16, 0.05))
		if opts.get("glass", false):
			sm.set_shader_parameter("night_lit", 2.5 * float(opts.get("night", 0.0)))
		if n == "asphalt" and opts.get("uv", false):
			sm.set_shader_parameter("streaks", float(opts.get("streaks", 0.18)))
			sm.set_shader_parameter("along_x", str(opts.get("uv_along", "y")) == "x")
		if wet > 0.0 and n in WET_SURFACES:
			# wet: water in the texture's pores darkens it, the film on top is smooth (a wet road's
			# roughness ~0.1-0.2 against a dry one's ~0.8-0.9) and shines more
			sm.set_shader_parameter("rough_scale", float(sd.rough) * float(opts.get("rough", 1.0)) * lerpf(1.0, 0.22, wet))
			sm.set_shader_parameter("tint", (opts.get("tint", Color.WHITE) as Color).darkened(0.5 * wet))
			sm.set_shader_parameter("spec", lerpf(float(sd.spec), 0.55, wet))
		m = sm
	_cache[key] = m
	return m


## Shader variants for the quality: MEDIUM one projection, HIGH / ULTRA triplanar with the
## texture mixed against itself at another scale (no visible tiling).
static func _quality_defs() -> Array:
	if int(Graphics.get_value("textures")) >= 2:
		return ["TRIPLANAR", "ANTI_TILE"]
	return []


## LOW (or no textures): flat vertex colours, lit the old way (soft wrap-round light, no
## shine), ice and puddles still glossy; in "tint" mode the texture's mean colour x the tint.
static func _flat(n: String, opts: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	var tint: Color = opts.get("tint", Color.WHITE)
	if opts.get("vertex", "tint") == "tint" and SURFACES.has(n):
		var mean := _mean(SURFACES[n].tex)
		tint = Color(mean.x, mean.y, mean.z).linear_to_srgb() * tint
	m.albedo_color = tint
	m.roughness = 1.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if n == "ice":
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		m.roughness = 0.12
		m.metallic_specular = 0.9
	elif n == "asphalt":
		m.roughness = 0.85
	if wet > 0.0 and n in WET_SURFACES:
		m.albedo_color = m.albedo_color.darkened(0.5 * wet)
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		m.roughness = lerpf(m.roughness, 0.18, wet)
	return m


## A vertex-coloured StandardMaterial3D (the old flat look on LOW), tinted.
static func _flat_base(opts: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = opts.get("tint", Color.WHITE)
	m.roughness = 1.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


static func _liquid(n: String, col: Color, rough: float, ripple: float) -> Material:
	var key := _key(n, {})
	if _cache.has(key):
		return _cache[key]
	var m: Material
	if Graphics.level() == "low" or Graphics.headless():
		var s := StandardMaterial3D.new()
		s.albedo_color = col
		s.roughness = maxf(rough, 0.12)
		s.metallic_specular = 0.8
		m = s
	else:
		var sm := ShaderMaterial.new()
		sm.shader = _water_shader()
		sm.set_shader_parameter("colour", col)
		sm.set_shader_parameter("rough", rough)
		sm.set_shader_parameter("ripple", ripple)
		sm.set_shader_parameter("waves", _wave_texture())
		m = sm
	_cache[key] = m
	return m


static func _wave_texture() -> NoiseTexture2D:
	if _textures.has("waves"):
		return _textures.waves
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = 4.0
	t.noise = noise
	_textures["waves"] = t
	return t


## Textures are there and the quality wants them.
static func _can_texture(names: Array) -> bool:
	if not Graphics.textured():
		return false
	for n in names:
		if not ResourceLoader.exists(TEX_DIR + n + "_albedo.webp") or not ResourceLoader.exists(TEX_DIR + n + "_normal.webp"):
			return false
	return true


static func _tex(n: String) -> Texture2D:
	if not _textures.has(n):
		_textures[n] = load(TEX_DIR + n + ".webp")
	return _textures[n]


static func _info(n: String) -> Dictionary:
	if _tex_info.is_empty() and FileAccess.file_exists(TEX_DIR + "textures.json"):
		_tex_info = JSON.parse_string(FileAccess.get_file_as_string(TEX_DIR + "textures.json"))
	return _tex_info.get(n, {})


static func _mean(n: String) -> Vector3:
	var m: Array = _info(n).get("mean_linear", [0.2, 0.2, 0.2])
	return Vector3(m[0], m[1], m[2])


static func _size(n: String) -> float:
	return float(_info(n).get("size_m", 2.0))


static func _shader(defs: Array) -> Shader:
	var d := defs.duplicate()
	d.sort()
	var key := ",".join(d)
	if _shaders.has(key):
		return _shaders[key]
	var code := "shader_type spatial;\n"
	for x in d:
		code += "#define %s\n" % x
	code += SURFACE_SHADER
	var sh := Shader.new()
	sh.code = code
	_shaders[key] = sh
	return sh


static func _sky_shader() -> Shader:
	if not _shaders.has("sky"):
		var sh := Shader.new()
		sh.code = SKY_SHADER
		_shaders["sky"] = sh
	return _shaders.sky


static func _water_shader() -> Shader:
	if not _shaders.has("water"):
		var sh := Shader.new()
		sh.code = WATER_SHADER
		_shaders["water"] = sh
	return _shaders.water


## One shader for every textured surface (variants by #define: TRIPLANAR, ANTI_TILE,
## UV_MODE, VC_COLOUR, PAINT, GLASS, TERRAIN).
const SURFACE_SHADER := """
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tex_mean = vec3(0.2);
uniform vec4 tint : source_color = vec4(1.0);
uniform float tex_scale = 0.5;          // repeats a metre
uniform float normal_strength = 1.0;
uniform float rough_scale = 1.0;
uniform float spec = 0.5;
uniform float metal = 0.0;
uniform float detail = 1.0;             // VC_COLOUR: how much of the texture's own variation shows
uniform float detail_far = 0.55;        // ... far away (no tiling to see out there)
uniform float photo = 0.0;              // VC_COLOUR: this much of the colour from the photo itself (its hue,
                                        // the vertex colour's brightness): natural colours, the scheme kept
uniform float vc_sat = 1.0;             // the vertex colours' saturation, x
uniform float vc_gain = 1.0;            // ... and brightness, x
uniform vec3 backlight = vec3(0.0);     // FOLIAGE: the sun through the leaves
uniform float night_lit = 0.0;          // GLASS: at night, some windows lit (this bright)
uniform float streaks = 0.0;            // UV_MODE: darker tyre-worn streaks along the road (UV.y) ...
uniform bool along_x = false;           // ... or UV.x
#ifdef TERRAIN
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 grass_mean = vec3(0.2);
uniform vec3 dirt_mean = vec3(0.2);
uniform vec3 rock_mean = vec3(0.2);
uniform vec3 snow_mean = vec3(0.4);
uniform vec4 scales = vec4(0.5);        // grass, dirt, rock, snow: repeats a metre
#endif

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// the vertex colour, linear, graded (vc_sat, vc_gain)
vec3 vertex_linear(vec3 c) {
	vec3 l = to_linear(c);
	return mix(vec3(dot(l, LUMA)), l, vc_sat) * vc_gain;
}

// a normal map texel -> tangent-space normal, its bumps x ns (z rebuilt: works whatever the import kept)
vec3 unpack(vec4 t, float ns) {
	vec2 xy = t.xy * 2.0 - 1.0;
	return vec3(xy * ns, sqrt(clamp(1.0 - dot(xy, xy), 0.0, 1.0)));
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

// A texture pair at world point p (normal n, both world space): albedo + roughness (a),
// and the normal map turned into a world-space normal (wn). tri: from three sides (the
// whiteout blend), else from above.
void project(sampler2D at, sampler2D nt, vec3 p, vec3 n, float sc, float ns, bool tri, out vec4 a, out vec3 wn) {
	if (tri) {
		vec3 w = pow(abs(n), vec3(4.0));
		w /= (w.x + w.y + w.z);
		vec2 ux = p.zy * sc;
		vec2 uy = p.xz * sc;
		vec2 uz = p.xy * sc;
		a = texture(at, ux) * w.x + texture(at, uy) * w.y + texture(at, uz) * w.z;
		vec3 tx = unpack(texture(nt, ux), ns);
		vec3 ty = unpack(texture(nt, uy), ns);
		vec3 tz = unpack(texture(nt, uz), ns);
		tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
		ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
		tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
		wn = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
	} else {
		vec2 uy = p.xz * sc;
		a = texture(at, uy);
		vec3 ty = unpack(texture(nt, uy), ns);
		ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
		wn = normalize(ty.xzy);
	}
}

// project(), and on HIGH / ULTRA mixed with itself turned 90 degrees at another scale
// where a slow noise says so: the repeats don't line up any more.
void sample_set(sampler2D at, sampler2D nt, vec3 p, vec3 n, float sc, float ns, bool tri, out vec4 a, out vec3 wn) {
	project(at, nt, p, n, sc, ns, tri, a, wn);
#ifdef ANTI_TILE
	float m = smoothstep(0.3, 0.7, vnoise(p.xz * 0.09 + vec2(17.0, 3.0)));
	vec4 a2;
	vec3 n2;
	project(at, nt, vec3(p.z + 7.3, p.y, -p.x + 3.1), vec3(n.z, n.y, -n.x), sc * 0.79, ns, tri, a2, n2);
	n2 = vec3(-n2.z, n2.y, n2.x);
	a = mix(a, a2, m);
	wn = normalize(mix(wn, n2, m));
#endif
}

#ifdef UV_MODE
// The mesh's own UVs (in metres): the normal map through a frame worked out from the
// screen-space derivatives (no tangents needed).
void sample_uv(vec2 uv, vec3 p, vec3 n, out vec4 a, out vec3 wn) {
	vec2 st = uv * tex_scale;
	a = texture(albedo_tex, st);
	vec3 t = unpack(texture(normal_tex, st), normal_strength);
	vec3 dp1 = dFdx(p);
	vec3 dp2 = dFdy(p);
	vec2 duv1 = dFdx(st);
	vec2 duv2 = dFdy(st);
	vec3 dp2perp = cross(dp2, n);
	vec3 dp1perp = cross(n, dp1);
	vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
	float k = inversesqrt(max(max(dot(T, T), dot(B, B)), 1e-12));
	wn = normalize(T * k * t.x - B * k * t.y + n * t.z);
}
#endif

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 vc = COLOR.rgb;
	float dist = length(VERTEX);
	float det = detail * mix(1.0, detail_far, smoothstep(30.0, 170.0, dist));
	vec4 a;
	vec3 wn;
	vec3 albedo;
	float rough;
	float sp = spec;
#ifdef TERRAIN
	// what the vertex colour says the ground is: green grass, brown earth, grey rock, white snow
	float mx = max(vc.r, max(vc.g, vc.b));
	float mn = min(vc.r, min(vc.g, vc.b));
	float sat = (mx - mn) / max(mx, 0.001);
	float w_snow = smoothstep(0.68, 0.84, mn);
	float w_grass = smoothstep(0.01, 0.09, vc.g - vc.r) * (1.0 - w_snow);
	float w_rock = (1.0 - smoothstep(0.17, 0.3, sat)) * (1.0 - w_grass) * (1.0 - w_snow);
	float w_dirt = max(1.0 - w_grass - w_rock - w_snow, 0.0);
	vec3 ratio = vec3(0.0);
	vec3 phsum = vec3(0.0);
	vec3 nsum = vec3(0.0);
	rough = 0.0;
	if (w_grass > 0.01) {
		sample_set(grass_tex, grass_nrm, wpos, n, scales.x, normal_strength, false, a, wn);
		ratio += w_grass * a.rgb / grass_mean;
		phsum += w_grass * mix(grass_mean, a.rgb, det) / dot(grass_mean, LUMA);
		nsum += w_grass * wn;
		rough += w_grass * a.a;
	}
	if (w_dirt > 0.01) {
		sample_set(dirt_tex, dirt_nrm, wpos, n, scales.y, normal_strength, false, a, wn);
		ratio += w_dirt * a.rgb / dirt_mean;
		phsum += w_dirt * mix(dirt_mean, a.rgb, det) / dot(dirt_mean, LUMA);
		nsum += w_dirt * wn;
		rough += w_dirt * a.a;
	}
	if (w_rock > 0.01) {
		sample_set(rock_tex, rock_nrm, wpos, n, scales.z, normal_strength * 1.2, true, a, wn);
		ratio += w_rock * a.rgb / rock_mean;
		phsum += w_rock * mix(rock_mean, a.rgb, det) / dot(rock_mean, LUMA);
		nsum += w_rock * wn;
		rough += w_rock * a.a;
	}
	if (w_snow > 0.01) {
		sample_set(snow_tex, snow_nrm, wpos, n, scales.w, normal_strength * 0.7, false, a, wn);
		ratio += w_snow * a.rgb / snow_mean;
		phsum += w_snow * mix(snow_mean, a.rgb, det) / dot(snow_mean, LUMA);
		nsum += w_snow * wn;
		rough += w_snow * a.a;
	}
	float wsum = max(w_grass * step(0.01, w_grass) + w_dirt * step(0.01, w_dirt) + w_rock * step(0.01, w_rock) + w_snow * step(0.01, w_snow), 0.001);
	ratio /= wsum;
	phsum /= wsum;
	rough /= wsum;
	wn = normalize(nsum + n * 0.001);
	vec3 vlin = vertex_linear(vc);
	albedo = mix(vlin * clamp(mix(vec3(1.0), ratio, det), 0.0, 3.0), dot(vlin, LUMA) * phsum, photo);
#else
  #ifdef UV_MODE
	sample_uv(UV, wpos, n, a, wn);
	vec2 ruv = along_x ? UV.yx : UV;
	a.rgb *= 1.0 - streaks * smoothstep(0.35, 0.8, vnoise(vec2(ruv.x * 1.7, ruv.y * 0.035)));
  #else
    #ifdef TRIPLANAR
	sample_set(albedo_tex, normal_tex, wpos, n, tex_scale, normal_strength, true, a, wn);
    #else
	sample_set(albedo_tex, normal_tex, wpos, n, tex_scale, normal_strength, false, a, wn);
    #endif
  #endif
	rough = a.a;
	float ph_amt = photo;
  #ifdef PAINT
	// bright vertex colours on asphalt are painted lines: smoother, less of the grain
	float paint = smoothstep(0.42, 0.62, max(vc.r, max(vc.g, vc.b)));
	ph_amt *= 1.0 - paint;
	det = mix(det, det * 0.35, paint);
	rough = mix(rough, 0.55, paint);
	wn = normalize(mix(wn, n, paint * 0.6));
  #endif
  #ifdef GLASS
	// the windows (dark blue-grey): glass
	float glass = (1.0 - smoothstep(0.2, 0.3, max(vc.r, max(vc.g, vc.b)))) * step(vc.r + 0.02, vc.b);
	det *= 1.0 - glass;
	ph_amt *= 1.0 - glass;
	vec3 cell = floor(wpos * vec3(0.8, 0.4, 0.8));
	float lit = step(0.58, hash2(cell.xz + cell.y * 7.13)) * glass * night_lit;
	rough = mix(rough, 0.05 / max(rough_scale, 0.01), glass);
	wn = normalize(mix(wn, n, glass));
	sp = mix(sp, 1.0, glass);
  #endif
  #ifdef VC_COLOUR
	vec3 vlin = vertex_linear(vc);
	albedo = vlin * clamp(mix(vec3(1.0), a.rgb / tex_mean, det), 0.0, 3.0);
	albedo = mix(albedo, dot(vlin, LUMA) * mix(tex_mean, a.rgb, det) / dot(tex_mean, LUMA), ph_amt);
  #else
	albedo = a.rgb * to_linear(vc);
  #endif
#endif
	ALBEDO = albedo * tint.rgb;
	ROUGHNESS = clamp(rough * rough_scale, 0.03, 1.0);
	METALLIC = metal;
	SPECULAR = sp;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
#ifdef FOLIAGE
	BACKLIGHT = backlight;
#endif
#ifdef GLASS
  #ifndef TERRAIN
	EMISSION = vec3(1.0, 0.7, 0.38) * lit;
  #endif
#endif
}
"""

## The sky: a photographed panorama (log-encoded: tools/world_textures.py), turned by yaw
## so its sun is the light's, faded under the horizon into the ground's colour (no blue
## light from below), the sun's disc drawn where the DirectionalLight is; without a photo
## (the web build, night) a drawn gradient, and stars at night.
const SKY_SHADER := """
shader_type sky;
render_mode use_debanding;

uniform sampler2D sky_tex : filter_linear_mipmap, repeat_enable, hint_default_black;
uniform sampler2D sky_tex_b : filter_linear_mipmap, repeat_enable, hint_default_black;
uniform bool has_tex = false;
uniform bool has_tex_b = false;
uniform float lo = 0.04;
uniform float hi = 48.0;
uniform float v_max = 0.5556;
uniform float yaw = 0.0;
uniform float yaw_b = 0.0;
uniform float mix_b = 0.0;
uniform float energy = 1.0;
uniform vec3 zenith_lin = vec3(0.25, 0.42, 0.85);
uniform vec3 horizon_lin = vec3(0.75, 0.85, 1.0);
uniform vec3 zenith_lin_b = vec3(0.25, 0.42, 0.85);
uniform vec3 horizon_lin_b = vec3(0.75, 0.85, 1.0);
uniform vec3 ground_lin = vec3(0.07, 0.075, 0.055);
uniform float sun_disc = 60.0;
uniform float stars = 0.0;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

vec3 photo(sampler2D t, float yw, vec3 d, float lod) {
	float u = fract(atan(d.x, -d.z) / TAU + 0.5 + yw / TAU);
	float v = acos(clamp(d.y, -1.0, 1.0)) / PI;
	vec3 e = textureLod(t, vec2(u, min(v / v_max, 0.995)), lod).rgb;
	return lo * exp2(e * log2(hi / lo));
}

vec3 drawn(vec3 zen, vec3 hor, vec3 d) {
	vec3 col = mix(hor, zen, pow(clamp(d.y, 0.0, 1.0), 0.45));
	if (stars > 0.0 && d.y > 0.0) {
		vec3 cell = floor(d * 300.0);
		float s = step(0.9985, hash3(cell));
		col += vec3(s * hash3(cell + 3.1) * 0.08 * stars) * smoothstep(0.0, 0.25, d.y);
	}
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float lod = AT_CUBEMAP_PASS ? 1.5 : 0.0;
	vec3 col = has_tex ? photo(sky_tex, yaw, d, lod) : drawn(zenith_lin, horizon_lin, d);
	vec3 hor = horizon_lin;
	if (mix_b > 0.0) {
		vec3 b = has_tex_b ? photo(sky_tex_b, yaw_b, d, lod) : drawn(zenith_lin_b, horizon_lin_b, d);
		col = mix(col, b, mix_b);
		hor = mix(horizon_lin, horizon_lin_b, mix_b);
	}
	float below = smoothstep(0.0, -0.06, d.y);
	col = mix(col, mix(hor, ground_lin, smoothstep(-0.02, -0.3, d.y)), below);
	col *= energy;
	if (LIGHT0_ENABLED && sun_disc > 0.0) {
		float c = dot(d, LIGHT0_DIRECTION);
		float disc = smoothstep(0.999986, 0.999993, c);
		float glow = pow(max(c, 0.0), 900.0) * 0.6;
		col += LIGHT0_COLOR * LIGHT0_ENERGY * (disc * sun_disc + glow) * (1.0 - below);
	}
	COLOR = col;
}
"""

## Water: flat, the colour given, two layers of ripples drifting across (a noise normal map).
const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 colour : source_color = vec4(0.05, 0.085, 0.08, 1.0);
uniform float rough = 0.03;
uniform float ripple = 1.0;
uniform sampler2D waves : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 a = texture(waves, p * 0.11 + vec2(TIME * 0.013, TIME * 0.007)).xyz * 2.0 - 1.0;
	vec3 b = texture(waves, p * 0.27 - vec2(TIME * 0.009, -TIME * 0.011)).xyz * 2.0 - 1.0;
	vec2 t = (a.xy + b.xy) * 0.25 * ripple;
	vec3 wn = normalize(vec3(t.x, 1.0, t.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ALBEDO = colour.rgb;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
"""
