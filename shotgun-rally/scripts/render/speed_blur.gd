extends Node
## Speed blur (the Assetto Corsa "No Hesi" clips' strongest look at 150-250 km/h): the
## road, the barriers and passing traffic smear (each along its own motion, plus a pull out
## from where the camera is heading, stronger toward the screen's edges) while the car and
## the cockpit, which move with the camera, stay sharp. A compositor pass on the world's
## environment (SpeedBlurEffect: two compute passes after the transparent objects); its
## strength follows the looking camera's speed: from ~90 km/h, all of it by ~220 km/h (the
## motion part is there at any speed, a short exposure's worth). MEDIUM (6 taps) and up,
## Forward+ only. While it's on, the screen has no MSAA (its depth and motion vectors read
## as empty to the pass): MEDIUM smooths the edges with FXAA instead, HIGH / ULTRA with
## their TAA; the menu's garage keeps its MSAA.
##   SpeedBlur.attach(parent, world_environment)   once per scene (WorldMaterials.setup does it)
## A --look_blur=<0..1> command line holds the pull at that strength (pictures of a still car);
## --look_blur_debug draws what the pass reads instead (red: depth, green: distance, blue: motion).

const Graphics = preload("res://scripts/render/graphics.gd")
const Effect = preload("res://scripts/render/speed_blur_effect.gd")
const FROM := 25.0                 # m/s (90 km/h): no pull below
const FULL := 61.0                 # m/s (220 km/h): all of it

var effect
var _last := Vector3.ZERO
var _cam: Camera3D
var _speed := 0.0
var _hold := -1.0


static func attach(parent: Node, we: WorldEnvironment) -> Node:
	if not Graphics.forward() or Graphics.headless() or we == null:
		return null
	var b: Node = (load("res://scripts/render/speed_blur.gd") as GDScript).new()
	b.name = "SpeedBlur"
	b.effect = Effect.new()
	var comp := Compositor.new()
	comp.compositor_effects = [b.effect]
	we.compositor = comp
	parent.add_child(b)
	return b


func _ready() -> void:
	add_to_group("graphics")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--look_blur="):
			_hold = float(a.trim_prefix("--look_blur="))
	_graphics_changed()


func _graphics_changed() -> void:
	var on := Graphics.level() != "low"
	effect.enabled = on
	effect.taps = 6 if Graphics.level() == "medium" else 10
	set_process(on)
	var vp := get_viewport()
	if on and vp and vp.msaa_3d != Viewport.MSAA_DISABLED:
		vp.msaa_3d = Viewport.MSAA_DISABLED
		if not vp.use_taa:
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA


func _exit_tree() -> void:
	Graphics.apply_viewport(get_viewport())                    # (back to the level's own AA: the menu)


func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		effect.amount = 0.0
		return
	var p := cam.global_position
	var v := (p - _last) / maxf(dt, 1e-4)
	if cam != _cam or v.length() > 150.0:
		v = Vector3.ZERO                                       # (another camera, a cut, a reset)
	_cam = cam
	_last = p
	_speed = lerpf(_speed, v.length(), clampf(dt * 6.0, 0.0, 1.0))
	var amount := smoothstep(FROM, FULL, _speed) * 0.85
	effect.held = _hold >= 0.0
	effect.sharp_near = 16.0 if effect.held else 9.0             # (held: sharp by distance: the whole car, the chase cam's 10 m to its nose)
	if effect.held:
		amount = _hold
	effect.amount = maxf(amount, 0.011) if _speed > 2.0 or effect.held else 0.0    # (the motion part: at any speed)
	effect.per_60 = (1.0 / 60.0) / maxf(dt, 1e-4)
	effect.shutter = 0.75
	effect.near = cam.near
	effect.far = cam.far
	# where the world streams out from: the direction of travel, as the camera sees it
	var heading := v.normalized() if v.length() > 1.0 else -cam.global_transform.basis.z
	var ahead := p + heading * 200.0
	var focus := Vector2(0.5, 0.45)
	if not cam.is_position_behind(ahead):
		focus = cam.unproject_position(ahead) / get_viewport().get_visible_rect().size
	effect.focus = focus.clamp(Vector2(0.1, 0.1), Vector2(0.9, 0.9))
