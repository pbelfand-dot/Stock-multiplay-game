extends Node3D
## A car's lamps at night: the headlights' beam (one spot light down the road, a
## touch low), the headlamps' glow, the red tail lamps' glow and a little red on
## the road behind. Fitted to the car's body by its bounds (any model: the player's,
## the other drivers', the touge's stray car). Glow only (no beam) for a car far off
## is the caller's choice.
##   CarLamps.fit(car, model, beam := true, tail := true) -> the CarLamps node (a child of car)
##   set_beam(on): the headlights' real light on or off (the glow stays: a far car's
##   beam is a light the screen needn't pay for)
##   hazards(on): the four corners blink amber (a car stopped on the road)

const BEAM_COLOUR := Color(1.0, 0.95, 0.86)
const TAIL_COLOUR := Color(1.0, 0.08, 0.04)
const AMBER := Color(1.0, 0.55, 0.08)

var _glows: Array = []          # [MeshInstance3D, base colour]
var _beam: SpotLight3D
var _hazard := false
var _t := 0.0


static func fit(car: Node3D, model: Node3D, beam := true, tail := true) -> Node3D:
	var lamps = load("res://scripts/vehicle/car_lamps.gd").new()
	lamps.name = "CarLamps"
	car.add_child(lamps)
	lamps._build(car, model, beam, tail)
	return lamps


## The model's box in the car's own space (it must be in the tree).
static func bounds(car: Node3D, model: Node3D) -> AABB:
	var to_car := car.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = to_car * (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:                                        # (no meshes: a car-sized guess)
		box = AABB(Vector3(-0.9, 0.2, -2.2), Vector3(1.8, 1.3, 4.4))
	return box


func _build(car: Node3D, model: Node3D, beam: bool, tail_light: bool) -> void:
	var box := bounds(car, model)
	var front := box.position.z                      # (the cars face -Z)
	var back := box.end.z
	var lamp_y := box.position.y + box.size.y * 0.36
	var tail_y := box.position.y + box.size.y * 0.45
	var x := box.size.x * 0.5 - 0.28
	var cx := box.get_center().x
	if beam:
		var spot := SpotLight3D.new()
		spot.light_color = BEAM_COLOUR
		spot.light_energy = 8.0
		spot.spot_range = 70.0
		spot.spot_angle = 30.0
		spot.spot_attenuation = 0.6
		spot.spot_angle_attenuation = 0.8
		spot.shadow_enabled = false
		spot.position = Vector3(cx, lamp_y, front - 0.1)
		spot.rotation.x = deg_to_rad(-4.0)
		add_child(spot)
		_beam = spot
	if tail_light:
		var tail := OmniLight3D.new()
		tail.light_color = TAIL_COLOUR
		tail.light_energy = 0.12
		tail.omni_range = 2.6
		tail.shadow_enabled = false
		tail.position = Vector3(cx, tail_y, back + 0.6)
		add_child(tail)
	# (the glows go on the body model: hidden with it in the driver's seat, where the
	# bonnet would hide the lamps anyway)
	for side in [-1.0, 1.0]:
		_glow(car, model, Vector3(cx + side * x, lamp_y, front - 0.05), 0.55, BEAM_COLOUR * 1.3)
		_glow(car, model, Vector3(cx + side * x, tail_y, back + 0.05), 0.3, TAIL_COLOUR * 1.1)


func _glow(car: Node3D, model: Node3D, at: Vector3, size: float, col: Color) -> void:
	var q := QuadMesh.new()
	var k := model.global_transform.basis.get_scale().x
	q.size = Vector2(size, size) / maxf(k, 0.01)
	var mi := MeshInstance3D.new()
	mi.name = "LampGlow"
	mi.mesh = q
	mi.material_override = _glow_material(col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(mi)
	mi.global_position = car.to_global(at)
	_glows.append([mi, col])


static var _sprite: GradientTexture2D

static func _glow_material(col: Color) -> Material:
	if _sprite == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.25, Color(1, 1, 1, 0.45))
		_sprite = GradientTexture2D.new()
		_sprite.gradient = g
		_sprite.fill = GradientTexture2D.FILL_RADIAL
		_sprite.fill_from = Vector2(0.5, 0.5)
		_sprite.fill_to = Vector2(1.0, 0.5)
		_sprite.width = 64
		_sprite.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = _sprite
	m.albedo_color = col
	return m


func set_beam(on: bool) -> void:
	if _beam:
		_beam.visible = on


func hazards(on: bool) -> void:
	_hazard = on
	_t = 0.0
	if not on:
		for g in _glows:
			if is_instance_valid(g[0]):
				((g[0] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = g[1]


## Gone again (a car changed: fit it anew).
func remove() -> void:
	for g in _glows:
		if is_instance_valid(g[0]):
			(g[0] as Node).queue_free()
	queue_free()


func _process(dt: float) -> void:
	if not _hazard:
		return
	_t += dt
	var lit := fmod(_t, 0.8) < 0.4
	for g in _glows:
		if is_instance_valid(g[0]):
			((g[0] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = AMBER * 1.6 if lit else Color(0, 0, 0, 0)
