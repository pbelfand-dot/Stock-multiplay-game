extends RefCounted
## The graphics quality: LOW / MEDIUM / HIGH / ULTRA (Settings -> GRAPHICS), what each
## turns on, and applying it to the screen (Viewport), the sky and effects (Environment)
## and the sun's shadows. Static: `const Graphics = preload("res://scripts/render/graphics.gd")`.
##
##   Graphics.level()           "low" | "medium" | "high" | "ultra" (saved; --gfx=... overrides)
##   Graphics.get_value(key)    the current level's setting (PRESETS below)
##   Graphics.forward()         true on Forward+ / Mobile (the RenderingDevice renderers);
##                              false on Compatibility (web, Chromebooks, old PCs): what it
##                              can't do (SSIL, SSR, SDFGI, TAA, soft PCSS shadows) is left off
##   Graphics.textured()        the world's materials use their textures (MEDIUM and up)
##   Graphics.view_distance()   x how far trees and scenery are drawn
##   Graphics.apply_viewport(vp), apply_environment(env), apply_sun(sun)
##   Graphics.set_level(l) / set_render_scale(x) / set_car_lights(m) / set_renderer(r): save
##                              and apply at once (textures: from the next stage)
##
## Saved in user://graphics.cfg. The renderer choice goes to user://renderer.cfg, which the
## engine itself reads at start (project.godot: application/config/project_settings_override),
## so it takes effect after a restart.
## Nodes that want the change live join the group "graphics" and get _graphics_changed().

const PATH := "user://graphics.cfg"
const RENDERER_PATH := "user://renderer.cfg"
const LEVELS := ["low", "medium", "high", "ultra"]
const SCALES := [0.0, 1.0, 0.85, 0.7, 0.5]     # 0: the level's own (AUTO)

## Per level. msaa: Viewport.MSAA_*; taa: temporal AA (Forward+); shadow_*: the sun's
## (size: the atlas, splits 2 or 4, distance m, soft: RenderingServer.SHADOW_QUALITY_*,
## pcss: the sun's angular size in degrees, Forward+); ssao / ssil / ssr / sdfgi / glow;
## textures: 0 flat colours, 1 one projection, 2 triplanar + anti-tiling; smooth: smooth
## normals on the ground; view: x draw distances; aniso: Viewport.ANISOTROPY_*; probe: the
## car's own reflection probe; scale: the 3D resolution (RENDER SCALE AUTO).
const PRESETS := {
	"low": {"msaa": Viewport.MSAA_2X, "taa": false, "shadow_size": 2048, "shadow_splits": 2, "shadow_distance": 60.0,
		"soft": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "pcss": 0.0, "ssao": false, "ssil": false, "ssr": false,
		"sdfgi": false, "glow": false, "textures": 0, "smooth": false, "view": 0.8, "aniso": Viewport.ANISOTROPY_2X,
		"probe": false, "scale": 1.0, "fog_sky": 0.0},
	"medium": {"msaa": Viewport.MSAA_2X, "taa": false, "shadow_size": 4096, "shadow_splits": 4, "shadow_distance": 110.0,
		"soft": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, "pcss": 0.0, "ssao": true, "ssil": false, "ssr": false,
		"sdfgi": false, "glow": true, "textures": 1, "smooth": true, "view": 1.0, "aniso": Viewport.ANISOTROPY_4X,
		"probe": false, "scale": 1.0, "fog_sky": 0.6},
	"high": {"msaa": Viewport.MSAA_2X, "taa": true, "shadow_size": 4096, "shadow_splits": 4, "shadow_distance": 150.0,
		"soft": RenderingServer.SHADOW_QUALITY_SOFT_HIGH, "pcss": 0.0, "ssao": true, "ssil": true, "ssr": true,
		"sdfgi": false, "glow": true, "textures": 2, "smooth": true, "view": 1.15, "aniso": Viewport.ANISOTROPY_8X,
		"probe": true, "scale": 1.0, "fog_sky": 0.8},
	"ultra": {"msaa": Viewport.MSAA_4X, "taa": true, "shadow_size": 8192, "shadow_splits": 4, "shadow_distance": 220.0,
		"soft": RenderingServer.SHADOW_QUALITY_SOFT_ULTRA, "pcss": 0.4, "ssao": true, "ssil": true, "ssr": true,
		"sdfgi": true, "glow": true, "textures": 2, "smooth": true, "view": 1.3, "aniso": Viewport.ANISOTROPY_16X,
		"probe": true, "scale": 1.0, "fog_sky": 0.85},
}

static var _loaded := false
static var _level := ""
static var _scale := 0.0                       # RENDER SCALE: 0 = the level's
static var _car_lights := "auto"               # "auto" (on in the dark) | "on" | "off"
static var _renderer := "auto"                 # "auto" (Forward+ on desktops) | "compatibility"


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		_level = str(cf.get_value("graphics", "quality", ""))
		_scale = float(cf.get_value("graphics", "render_scale", 0.0))
		_car_lights = str(cf.get_value("graphics", "car_lights", "auto"))
	var rf := ConfigFile.new()
	if rf.load(RENDERER_PATH) == OK and str(rf.get_value("rendering", "renderer/rendering_method", "")) == "gl_compatibility":
		_renderer = "compatibility"
	elif _chromebook() and not FileAccess.file_exists(RENDERER_PATH):
		set_renderer("compatibility")          # (its launcher asks for it already; this holds for any other start too)
	if not _level in LEVELS:
		_level = _first_level()
	for a in OS.get_cmdline_user_args():                  # tests / pictures: --gfx=ultra
		if a.begins_with("--gfx="):
			var l := a.trim_prefix("--gfx=")
			if l in LEVELS:
				_level = l


## Linux on a Chromebook (Crostini): its container has these.
static func _chromebook() -> bool:
	return OS.get_name() == "Linux" and (FileAccess.file_exists("/dev/.cros_milestone")
		or DirAccess.dir_exists_absolute("/opt/google/cros-containers"))


## Out of the box: from the graphics card. Compatibility (web, Chromebooks) or a software
## renderer: LOW; integrated graphics: MEDIUM; a graphics card of its own: HIGH.
static func _first_level() -> String:
	if not forward():
		return "low"
	match RenderingServer.get_video_adapter_type():
		RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
			return "high"
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
			return "medium"
	return "low"


static func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("graphics", "quality", _level)
	cf.set_value("graphics", "render_scale", _scale)
	cf.set_value("graphics", "car_lights", _car_lights)
	cf.save(PATH)


static func level() -> String:
	_load()
	return _level


static func get_value(key: String) -> Variant:
	return PRESETS[level()][key]


## The renderer actually running (a command line or a missing Vulkan can differ from the setting).
static func forward() -> bool:
	var m := RenderingServer.get_current_rendering_method()
	return m == "forward_plus" or m == "mobile"


## No screen (the tests): nothing to draw, skip the costly setup.
static func headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func textured() -> bool:
	return int(get_value("textures")) > 0 and not headless()


static func view_distance() -> float:
	return float(get_value("view"))


static func render_scale() -> float:
	_load()
	return _scale if _scale > 0.0 else float(get_value("scale"))


static func render_scale_setting() -> float:
	_load()
	return _scale


static func car_lights() -> String:
	_load()
	return _car_lights


static func renderer() -> String:
	_load()
	return _renderer


static func set_level(l: String) -> void:
	_load()
	if l in LEVELS:
		_level = l
		save()
		apply_all()


static func set_render_scale(x: float) -> void:
	_load()
	_scale = x
	save()
	apply_all()


static func set_car_lights(m: String) -> void:
	_load()
	_car_lights = m
	save()
	apply_all()


## "auto" or "compatibility": written where the engine reads it at start (a restart).
static func set_renderer(r: String) -> void:
	_load()
	_renderer = r
	if r == "compatibility":
		var cf := ConfigFile.new()
		cf.set_value("rendering", "renderer/rendering_method", "gl_compatibility")
		cf.set_value("rendering", "renderer/rendering_method.mobile", "gl_compatibility")
		cf.save(RENDERER_PATH)
	elif FileAccess.file_exists(RENDERER_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RENDERER_PATH))


## The renderer setting and the one running differ: a restart is due.
static func restart_needed() -> bool:
	return (renderer() == "compatibility") == forward() and not OS.has_feature("web")


## Everything at once: the screen, and every environment and sun in the tree.
static func apply_all() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	apply_viewport(tree.root)
	for we in tree.root.find_children("*", "WorldEnvironment", true, false):
		if (we as WorldEnvironment).environment:
			apply_environment((we as WorldEnvironment).environment)
	for sun in tree.root.find_children("*", "DirectionalLight3D", true, false):
		apply_sun(sun)
	tree.call_group("graphics", "_graphics_changed")


## Anti-aliasing, the 3D resolution, texture filtering, the sun's shadow map.
static func apply_viewport(vp: Viewport) -> void:
	if vp == null or headless():
		return
	var f := forward()
	vp.msaa_3d = Viewport.MSAA_DISABLED if "--look_nomsaa" in OS.get_cmdline_user_args() else get_value("msaa")
	vp.use_taa = f and bool(get_value("taa"))
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	var s := render_scale()
	vp.scaling_3d_scale = s
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if f and s < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.anisotropic_filtering_level = get_value("aniso")
	if f:
		vp.use_debanding = level() != "low"
	RenderingServer.directional_shadow_atlas_set_size(int(get_value("shadow_size")), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(get_value("soft"))
	RenderingServer.positional_soft_shadow_filter_set_quality(get_value("soft"))


## The effects: SSAO (MEDIUM up), SSIL and SSR (HIGH up), SDFGI (ULTRA), glow (MEDIUM up),
## the fog's colour from the sky. Forward+-only effects stay off on Compatibility.
static func apply_environment(env: Environment) -> void:
	if env == null:
		return
	var f := forward()
	var l := level()
	env.ssao_enabled = bool(get_value("ssao")) and f
	env.ssao_radius = 1.1
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.1
	env.ssil_enabled = bool(get_value("ssil")) and f
	env.ssil_radius = 3.0
	env.ssil_intensity = 0.7
	env.ssr_enabled = bool(get_value("ssr")) and f
	env.ssr_max_steps = 64 if l == "ultra" else 40
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3
	env.sdfgi_enabled = bool(get_value("sdfgi")) and f
	if env.sdfgi_enabled:
		env.sdfgi_use_occlusion = false
		env.sdfgi_read_sky_light = true
		env.sdfgi_bounce_feedback = 0.35
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = 0.4
		env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
		env.sdfgi_energy = 0.9
	env.glow_enabled = bool(get_value("glow")) and f            # (Compatibility's glow blooms the road lines)
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_aerial_perspective = float(get_value("fog_sky")) if f else 0.0
	if f and not headless():
		var hq := l == "ultra"
		RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH if hq else RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
			not hq, 0.5, 2, 50.0, 300.0)
		RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_MEDIUM if hq else RenderingServer.ENV_SSIL_QUALITY_LOW,
			true, 0.5, 4, 50.0, 300.0)
		RenderingServer.environment_set_ssr_half_size(not hq)
		RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_32 if hq else RenderingServer.ENV_SDFGI_RAY_COUNT_16)
		RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_10_FRAMES)


## The sun's shadows for the level: cascades for driving (a sharp first one round the
## car, the far ones out to the shadow distance), soft on HIGH, PCSS on ULTRA.
static func apply_sun(sun: DirectionalLight3D) -> void:
	if sun == null or not sun.shadow_enabled:
		return
	var d := float(get_value("shadow_distance"))
	sun.directional_shadow_max_distance = d
	if int(get_value("shadow_splits")) == 2:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_split_1 = 0.25
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_split_1 = 12.0 / d             # ~12 m: the car and the road round it
		sun.directional_shadow_split_2 = 0.22
		sun.directional_shadow_split_3 = 0.5
	sun.directional_shadow_blend_splits = level() in ["high", "ultra"]
	sun.directional_shadow_fade_start = 0.85
	sun.light_angular_distance = float(get_value("pcss")) if forward() else 0.0
