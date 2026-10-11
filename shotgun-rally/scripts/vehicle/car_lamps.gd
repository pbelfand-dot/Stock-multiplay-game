extends Node3D
## A car's lamps in the dark: the headlights' beam (real spot lights down the road, a
## touch low), a little red on the road behind, and the lamps' glow. Fitted to the car's
## body (any model: the player's, the other drivers', the touge's stray car).
##
## The light comes from the lamps themselves: the glow is the lamps' own lenses where CarLook
## found them (scripts/render/car_look.gd lights them: brake lights, dusk, the bloom does the
## rest), and each beam starts at its own headlamp's lens (CarLook's lamp_boxes: each side's
## lamp), the one casting shadows just in front of it. A body whose lamps are only painted
## into its texture (the shared rally body: its parts.json "lamp_boxes", "lens": true) gets a
## soft glow laid flat on each lamp, facing out. Where no lamp is known at all the beam starts
## at the front of the body and nothing floats in front of the car. Your own car, on Forward+
## MEDIUM and up: two beams (one casting shadows on HIGH / ULTRA); everyone else's one, between
## its lamps (a light the screen pays for: the game turns far ones off with set_beam).
##   CarLamps.fit(car, model, beam := true, tail := true) -> the CarLamps node (a child of
##     car; fitting again for the same model returns the one there; another model: fitted anew)
##     tail: the red light on the road behind (and the twin beams): yours
##   set_beam(on): the headlights' real light on or off (the glow stays)
##   hazards(on): the four corners blink amber (a car stopped on the road)
##   remove(): gone again
##   CarLamps.road_glow(model) -> MeshInstance3D or null: the traffic's way (dozens of cars, no
##     real lights to spare): at night, its headlights' light on the road ahead and the red
##     behind, faked (one additive mesh, one draw), as far as 200 m off; null by day
## Graphics CAR LIGHTS: AT NIGHT (the game fits them in the dark; CarLook at dusk), ALWAYS
## (CarLook fits your car's by day too), OFF (only your own beam at night, the rest glow).

const Graphics = preload("res://scripts/render/graphics.gd")
const WorldMaterials = preload("res://scripts/render/world_materials.gd")
const BEAM_COLOUR := Color(1.0, 0.95, 0.86)
const TAIL_COLOUR := Color(1.0, 0.08, 0.04)
const AMBER := Color(1.0, 0.55, 0.08)
const BEAM_ENERGY := 8.5
const CAR_LAYER := 1 << 10        # (CarLook's: the car's own meshes)

var model: Node3D
var own := false
var beam := true                # (asked for: a beam; Settings / no screen may have left it out)
var _car: Node3D
var _glows: Array = []          # [MeshInstance3D, base colour]
var _blinkers: Array = []       # (hazards on a car whose lamps glow by their material) MeshInstance3D
var _beams: Array = []          # SpotLight3D
var _tail: OmniLight3D
var _beam_on := true
var _hazard := false
var _t := 0.0
var _corners := {}              # "head" / "tail": [left, right] (car space)


static func fit(car: Node3D, body: Node3D, beam := true, tail := true) -> Node3D:
	var old = car.get_node_or_null("CarLamps")
	if old and is_instance_valid(old) and old.model == body and old.own == tail and old.beam == beam:
		return old
	if old:
		old.remove()
		old.name = "CarLampsOld"
	var lamps = load("res://scripts/vehicle/car_lamps.gd").new()
	lamps.name = "CarLamps"
	car.add_child(lamps)
	lamps._build(car, body, beam, tail)
	return lamps


## The model's box in the car's own space (it must be in the tree).
static func bounds(car: Node3D, body: Node3D) -> AABB:
	var to_car := car.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name) in ["LampGlow", "ContactShadow", "RoadGlow"]:
			continue
		var b: AABB = to_car * (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:                                        # (no meshes: a car-sized guess)
		box = AABB(Vector3(-0.9, 0.2, -2.2), Vector3(1.8, 1.3, 4.4))
	return box


func _build(car: Node3D, body: Node3D, with_beam: bool, tail_light: bool) -> void:
	_car = car
	model = body
	own = tail_light
	beam = with_beam
	var box := bounds(car, body)
	var look = car.get_node_or_null("CarLook")
	var found: Dictionary = look.lamp_boxes() if look and look.has_method("lamp_boxes") else body.get_meta("lamp_boxes", {})
	var to_car: Transform3D = car.global_transform.affine_inverse() * body.global_transform
	var front := box.position.z                      # (the cars face -Z)
	var back := box.end.z
	var cx := box.get_center().x
	var x := box.size.x * 0.5 - 0.28
	var ends := {"head": [Vector3(cx - x, box.position.y + box.size.y * 0.36, front), Vector3(cx + x, box.position.y + box.size.y * 0.36, front)],
		"tail": [Vector3(cx - x, box.position.y + box.size.y * 0.45, back), Vector3(cx + x, box.position.y + box.size.y * 0.45, back)]}
	var lamps := {}                                  # kind -> [left, right] lamp boxes (car space)
	for kind in ["head", "tail"]:
		var fb: AABB = found.get(kind, AABB())
		if fb.size == Vector3.ZERO:
			continue
		if found.has(kind + "_l") and found.has(kind + "_r"):     # (each side's lamp)
			lamps[kind] = [to_car * (found[kind + "_l"] as AABB), to_car * (found[kind + "_r"] as AABB)]
		else:                                        # (both in one box: each side's, near its outer end)
			var b: AABB = to_car * fb
			var w := minf(b.size.x * 0.25, 0.3)
			lamps[kind] = [AABB(Vector3(b.position.x, b.position.y, b.position.z), Vector3(w, b.size.y, b.size.z)),
				AABB(Vector3(b.end.x - w, b.position.y, b.position.z), Vector3(w, b.size.y, b.size.z))]
		# each lamp's lens: its middle across and up, at its face (a headlamp's front, a tail lamp's back)
		ends[kind] = (lamps[kind] as Array).map(func(lb: AABB): return Vector3(lb.get_center().x, lb.get_center().y,
			lb.position.z + 0.01 if kind == "head" else lb.end.z - 0.01))
	_corners = ends
	var lens: bool = bool(found.get("lens", false))   # (lamps only painted on: a glow laid on each)
	var no_beam := Graphics.car_lights() == "off" and not own      # (OFF: only your own beam)
	if with_beam and not no_beam and not Graphics.headless():
		var twin := own and Graphics.forward() and Graphics.level() != "low"
		var shadows := own and Graphics.forward() and Graphics.level() in ["high", "ultra"]
		var spots: Array = ends.head if twin else [(ends.head[0] + ends.head[1]) * 0.5]
		for k in spots.size():
			var spot := SpotLight3D.new()
			spot.light_color = BEAM_COLOUR
			spot.light_energy = BEAM_ENERGY / spots.size() * 1.3 if twin else BEAM_ENERGY
			spot.spot_range = 75.0
			spot.spot_angle = 34.0 if twin else 37.0
			spot.spot_attenuation = 0.6
			spot.spot_angle_attenuation = 0.65                  # (a soft edge: brightest in the middle)
			spot.light_specular = 0.6
			spot.shadow_enabled = shadows and k == spots.size() - 1     # (one shadow: half the cost)
			# (at the lens; the one casting shadows just in front of it, or the lens would shade it)
			spot.position = (spots[k] as Vector3) - Vector3(0, 0, 0.03 if spot.shadow_enabled else 0.0)
			spot.rotation.x = deg_to_rad(-4.0)
			add_child(spot)
			_beams.append(spot)
	if tail_light and not Graphics.headless():
		_tail = OmniLight3D.new()
		_tail.light_color = TAIL_COLOUR
		_tail.light_energy = 0.14
		_tail.omni_range = 2.6
		_tail.omni_attenuation = 1.4
		_tail.shadow_enabled = false
		_tail.light_cull_mask = 0xFFFFF & ~CAR_LAYER          # (a red glow on the road, not on the car)
		_tail.position = (ends.tail[0] + ends.tail[1]) * 0.5 + Vector3(0, 0, 0.55)
		add_child(_tail)
	# (the glows go on the body model: hidden with it in the driver's seat, where the
	# bonnet would hide the lamps anyway)
	if lens:
		for kind in lamps:
			for side in 2:
				var lb: AABB = lamps[kind][side]
				_glow(car, body, ends[kind][side], Vector2(lb.size.x, lb.size.y), BEAM_COLOUR * 1.2 if kind == "head" else TAIL_COLOUR * 1.1, kind == "head")


## A soft glow laid flat on a lamp (size: its width and height, m), facing out of the car
## (forward for a headlamp), just proud of it: a lamp only painted on, or a hazard light.
func _glow(car: Node3D, body: Node3D, at: Vector3, size: Vector2, col: Color, front := true) -> MeshInstance3D:
	var q := QuadMesh.new()
	var k := body.global_transform.basis.get_scale().x
	q.size = size.max(Vector2(0.06, 0.04)) / maxf(k, 0.01)
	var mi := MeshInstance3D.new()
	mi.name = "LampGlow"
	mi.mesh = q
	mi.material_override = _glow_material(col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	var out := Vector3(0, 0, -1.0 if front else 1.0)         # (car space: -z is forward)
	var g := car.global_transform
	mi.global_transform = Transform3D(Basis.looking_at(g.basis * -out, g.basis.y).scaled(Vector3.ONE * mi.global_transform.basis.get_scale().x),
		car.to_global(at + out * 0.004))
	_glows.append([mi, col])
	return mi


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
	m.albedo_texture = _sprite
	m.albedo_color = col
	return m


func set_beam(on: bool) -> void:
	_beam_on = on
	for b in _beams:
		(b as SpotLight3D).visible = on


func hazards(on: bool) -> void:
	_hazard = on
	_t = 0.0
	if on and _glows.is_empty() and _blinkers.is_empty() and model and is_instance_valid(model):
		for kind in ["head", "tail"]:                # (lamps lit by their material: blinkers of their own, on them)
			for side in 2:
				var g := _glow(_car, model, _corners[kind][side], Vector2(0.16, 0.1), Color(0, 0, 0, 0), kind == "head")
				_glows.pop_back()
				_blinkers.append(g)
	if not on:
		for g in _glows:
			if is_instance_valid(g[0]):
				((g[0] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = g[1]
		for b in _blinkers:
			if is_instance_valid(b):
				((b as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = Color(0, 0, 0, 0)


## Gone again (a car changed: fit it anew).
func remove() -> void:
	for g in _glows:
		if is_instance_valid(g[0]):
			(g[0] as Node).queue_free()
	for b in _blinkers:
		if is_instance_valid(b):
			(b as Node).queue_free()
	_glows.clear()
	_blinkers.clear()
	queue_free()


func _process(dt: float) -> void:
	# the beams by how dark it is (dusk: coming up), unless CAR LIGHTS says always
	var k := 1.0 if Graphics.car_lights() == "on" else clampf((WorldMaterials.night_amount - 0.2) / 0.5, 0.0, 1.0)
	for b in _beams:
		var s := b as SpotLight3D
		s.light_energy = (BEAM_ENERGY / _beams.size() * 1.3 if _beams.size() > 1 else BEAM_ENERGY) * k
	if _tail and _car and "inp" in _car:              # (brighter on the brakes)
		_tail.light_energy = (0.14 + clampf(float(_car.inp.get("brake", 0.0)) * 1.5, 0.0, 1.0) * 0.5) * maxf(k, 0.3)
	if not _hazard:
		return
	_t += dt
	var on := fmod(_t, 0.8) < 0.4
	for g in _glows:
		if is_instance_valid(g[0]):
			((g[0] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = AMBER * 1.6 if on else Color(0, 0, 0, 0)
	for b in _blinkers:
		if is_instance_valid(b):
			((b as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = AMBER * 1.6 if on else Color(0, 0, 0, 0)


## The traffic's lamps on the road at night, faked: a long pool of light ahead (where its
## headlamps are: CarLook.glow_model's "lamp_boxes", else its bounds) and a red one
## behind, in one additive mesh on the model (model space: -Z forward).
static var _road_material: ShaderMaterial

static func road_glow(model: Node3D) -> MeshInstance3D:
	if Graphics.headless() or WorldMaterials.night_amount < 0.3 or model == null:
		return null
	if not model.is_inside_tree():
		return null
	var box := AABB()
	var to_model := model.global_transform.affine_inverse()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = to_model * (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if box.size == Vector3.ZERO else box.merge(b)
	if box.size == Vector3.ZERO:
		return null
	var found: Dictionary = model.get_meta("lamp_boxes", {})
	var y := box.position.y + 0.04
	var cx := box.get_center().x
	var front := (found.head as AABB).position.z if found.has("head") else box.position.z
	var back := (found.tail as AABB).end.z if found.has("tail") else box.end.z
	var k := WorldMaterials.night_amount
	var head_col := Color(1.0, 0.9, 0.72) * 0.2 * k      # (dim: in a pack a dozen of them overlap)
	var tail_col := Color(1.0, 0.06, 0.03) * 0.25 * k
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for q in [[Vector3(cx, y, front - 9.0), Vector2(2.6, 9.5), head_col], [Vector3(cx, y, back + 1.3), Vector2(1.4, 1.5), tail_col]]:
		var c: Vector3 = q[0]
		var h: Vector2 = q[1]
		var corners := [Vector3(-h.x, 0, -h.y), Vector3(h.x, 0, -h.y), Vector3(h.x, 0, h.y), Vector3(-h.x, 0, h.y)]
		var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for t in [0, 1, 2, 0, 2, 3]:
			verts.append(c + corners[t])
			uvs.append(uv[t])
			cols.append(q[2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if _road_material == null:
		var sh := Shader.new()
		sh.code = ROAD_GLOW_SHADER
		_road_material = ShaderMaterial.new()
		_road_material.shader = sh
	var mi := MeshInstance3D.new()
	mi.name = "RoadGlow"
	mi.mesh = mesh
	mi.material_override = _road_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 200.0
	model.add_child(mi)
	return mi


const ROAD_GLOW_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// (the pool ahead brightest near the car, as a headlight's is: UV.y 0 is its far end)
	float f = pow(clamp(1.0 - length(p * vec2(1.0, 0.85)), 0.0, 1.0), 1.5) * mix(0.55, 1.0, UV.y);
	ALBEDO = COLOR.rgb * f;
}
"""
