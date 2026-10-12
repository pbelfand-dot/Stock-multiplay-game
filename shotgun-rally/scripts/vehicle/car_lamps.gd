extends Node3D
## A car's lamps in the dark: the headlights' beams (real spot lights down the road, a touch
## low), a little red on the road behind, and the lamps' glow. Fitted to the car's body (any
## model: the player's, the other drivers', Track Mode's AI, the touge's stray car).
##
## The light comes from the lamps themselves, not from anything in front of the car:
##   * the glow is the lamps' own lenses where CarLook found them (scripts/render/car_look.gd
##     lights them: brake lights, dusk, the bloom does the rest). A body whose lamps are only
##     painted into its texture (the shared rally body: its parts.json "lamp_boxes", "lens":
##     true) gets a soft glow laid flat on each painted lamp, facing out.
##   * each beam starts on its own headlamp's lens, BEAM_OUT (2 cm) out from it: CarLook's
##     lamp_boxes "head_l_at" / "head_r_at", each side's lamp's middle as seen from in front,
##     on its outermost face (the front of the lamp's box was up to 34 cm in front of the lens
##     on a lamp swept back round the wing: the light came from the air there). Where a model
##     has no "_at" (lamps painted on), the middle of each lamp's face; where no lamp is known
##     at all, the front of the body. Nothing glows in the air in front of the car.
##   * a beam doesn't light its own car (light_cull_mask and shadow_caster_mask leave the car's
##     layer out): a spot light a few cm from the car's own bumper, grille, bonnet and lens lit
##     them white-hot (worst with one beam in the middle of the nose, in the grille), the bloom
##     made a ball of it, and the beam seemed to come out of that ball. Your car's meshes are on
##     CarLook.CAR_LAYER; a car fitted here as someone else's is moved onto CarLook.OTHER_LAYER
##     (a plain model, the stray car, off the default layer onto it): your beams light the cars
##     ahead of you, theirs light yours.
## Two beams, one on each headlamp, on Forward+ MEDIUM and up (yours casting one shadow on HIGH /
## ULTRA); LOW and Compatibility: one, between the two lenses. Anyone else's beams are lights the
## screen pays for: the game leaves them on for the two nearest other drivers or Track Mode AI
## cars only (set_beam); the touge has one stray car at a time.
##   CarLamps.fit(car, model, beam := true, tail := true) -> the CarLamps node (a child of
##     car; fitting again for the same model returns the one there; another model: fitted anew)
##     tail: yours (the red light on the road behind, the shadow, your car's layer)
##   set_beam(on): the headlights' real light on or off (the glow stays)
##   hazards(on): the four corners blink amber, on the lamps (a car stopped on the road)
##   remove(): gone again
##   CarLamps.road_glow(model) -> MeshInstance3D or null: the traffic's way (dozens of cars, no
##     real lights to spare): at night, its headlights' light on the road ahead and the red
##     behind, faked (one additive mesh, one draw), as far as 200 m off; null by day. It starts
##     at the lamps (CarLook.glow_model's "head_l_at" ...): a lobe from each headlamp, brightest
##     just ahead of the car, gone by ROAD_REACH (14 m), never a pool out ahead on its own; the
##     red the same from the tail lamps, 2.4 m back.
## Graphics CAR LIGHTS: AT NIGHT (the game fits them in the dark; CarLook at dusk), ALWAYS
## (CarLook fits your car's by day too), OFF (only your own beam at night, the rest glow).

const Graphics = preload("res://scripts/render/graphics.gd")
const WorldMaterials = preload("res://scripts/render/world_materials.gd")
const BEAM_COLOUR := Color(1.0, 0.95, 0.86)
const TAIL_COLOUR := Color(1.0, 0.08, 0.04)
const AMBER := Color(1.0, 0.55, 0.08)
const BEAM_ENERGY := 8.5
const BEAM_OUT := 0.02            # m: a beam starts this far out from its lens
const CAR_LAYER := 1 << 10        # (CarLook's: your car's own meshes)
const OTHER_LAYER := 1 << 14      # (CarLook's: anyone else's car)
const ROAD_REACH := 14.0          # m: the traffic's light on the road, this far out from its headlamps
const TAIL_REACH := 2.4           # ... and the red behind it

var model: Node3D
var own := false
var beam := true                # (asked for: a beam; Settings / no screen may have left it out)
var layer := CAR_LAYER          # the car's own meshes' render layer (yours: CAR_LAYER): its beams leave it out
var _car: Node3D
var _glows: Array = []          # [MeshInstance3D, base colour]
var _blinkers: Array = []       # (hazards on a car whose lamps glow by their material) MeshInstance3D
var _beams: Array = []          # SpotLight3D
var _energy := BEAM_ENERGY      # each beam's, in the dark
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
		if found.has(kind + "_l_at") and found.has(kind + "_r_at"):     # (where each lamp's light comes out: on its lens)
			ends[kind] = [to_car * (found[kind + "_l_at"] as Vector3), to_car * (found[kind + "_r_at"] as Vector3)]
		else:                                        # (each lamp's face: its middle across and up, a headlamp's front, a tail lamp's back)
			ends[kind] = (lamps[kind] as Array).map(func(lb: AABB): return Vector3(lb.get_center().x, lb.get_center().y,
				lb.position.z + 0.01 if kind == "head" else lb.end.z - 0.01))
	_corners = ends
	layer = CAR_LAYER if own else OTHER_LAYER
	_own_layer(body, look == null)
	var lens: bool = bool(found.get("lens", false))   # (lamps only painted on: a glow laid on each)
	var no_beam := Graphics.car_lights() == "off" and not own      # (OFF: only your own beam)
	if with_beam and not no_beam and not Graphics.headless():
		var twin := Graphics.forward() and Graphics.level() != "low"
		var shadows := own and Graphics.forward() and Graphics.level() in ["high", "ultra"]
		var spots: Array = beam_origins(ends.head, twin)
		_energy = BEAM_ENERGY / spots.size() * 1.3 if twin else BEAM_ENERGY
		for k in spots.size():
			var spot := SpotLight3D.new()
			spot.light_color = BEAM_COLOUR
			spot.light_energy = _energy
			spot.spot_range = 75.0
			spot.spot_attenuation = 0.6
			spot.spot_angle = 34.0 if twin else 37.0
			spot.spot_angle_attenuation = 0.65                  # (a soft edge: brightest in the middle)
			spot.rotation.x = deg_to_rad(-4.0)
			spot.light_specular = 0.6
			spot.shadow_enabled = shadows and k == spots.size() - 1     # (one shadow: half the cost)
			spot.light_cull_mask = 0xFFFFF & ~layer              # (not its own car: no white-hot nose a few cm off)
			spot.shadow_caster_mask = 0xFFFFF & ~layer           # (nor shaded by it: its own lens)
			spot.position = spots[k]
			add_child(spot)
			_beams.append(spot)
	if tail_light and not Graphics.headless():
		_tail = OmniLight3D.new()
		_tail.light_color = TAIL_COLOUR
		_tail.light_energy = 0.14
		_tail.omni_range = 2.6
		_tail.omni_attenuation = 1.4
		_tail.shadow_enabled = false
		_tail.light_cull_mask = 0xFFFFF & ~layer              # (a red glow on the road, not on the car)
		_tail.position = (ends.tail[0] + ends.tail[1]) * 0.5 + Vector3(0, 0, 0.55)
		add_child(_tail)
	# (the glows go on the body model: hidden with it in the driver's seat, where the
	# bonnet would hide the lamps anyway)
	if lens:
		for kind in lamps:
			for side in 2:
				var lb: AABB = lamps[kind][side]
				_glow(car, body, ends[kind][side], Vector2(lb.size.x, lb.size.y), BEAM_COLOUR * 1.2 if kind == "head" else TAIL_COLOUR * 1.1, kind == "head")


## Where the beams start (car space) for the headlamps' lens points [left, right]: on each,
## BEAM_OUT out in front of it (twin), or one between them (at their height and depth).
static func beam_origins(heads: Array, twin: bool) -> Array:
	var out := Vector3(0, 0, -BEAM_OUT)
	return [heads[0] + out, heads[1] + out] if twin else [(heads[0] + heads[1]) * 0.5 + out]


## The car's own meshes onto its layer (yours: CAR_LAYER; anyone else's: OTHER_LAYER), so its
## beams leave them out and everyone else's light them. A RallyCar's are on one of the two
## already (CarLook); a plain model's (plain: the stray car) on the default layer.
func _own_layer(body: Node3D, plain: bool) -> void:
	for n in body.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if plain and gi.layers == 1:
			gi.layers = layer
		elif gi.layers & (CAR_LAYER | OTHER_LAYER) != 0:
			gi.layers = (gi.layers & ~(CAR_LAYER | OTHER_LAYER)) | layer


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
		s.light_energy = _energy * k
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


## The traffic's lamps on the road at night, faked: its headlamps' light on the road ahead
## and a little red behind, in one additive mesh on the model (model space: -Z forward), flat
## just over its wheels' bottom. Each starts at its lamps (CarLook.glow_model's lamp_boxes:
## each side's lens, "head_l_at" ...; else the lamps' box; else the body's ends): a lobe out
## of each lamp, widening, brightest just ahead of the car and gone by ROAD_REACH (on a
## crest or round a bend its far end, the part that would float or leave the road, is dark).
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
	var mesh := road_mesh(model.get_meta("lamp_boxes", {}), box, WorldMaterials.night_amount)
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


## road_glow's mesh (model space) for a model's lamp_boxes (found) and its box, k: how dark it is.
static func road_mesh(found: Dictionary, box: AABB, k: float) -> ArrayMesh:
	var y := box.position.y + 0.04
	var head_col := Color(1.0, 0.9, 0.72) * 0.2 * k      # (dim: in a pack a dozen of them overlap)
	var tail_col := Color(1.0, 0.06, 0.03) * 0.25 * k
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	for q in [["head", ROAD_REACH, -1.0, head_col], ["tail", TAIL_REACH, 1.0, tail_col]]:
		var at := lamp_pair(found, q[0], box)            # (the middle between the lamps' x, half their spacing, their z)
		var reach: float = q[1]
		var dir: float = q[2]                            # (-1: ahead, -z)
		var hw := at.y + reach * 0.25                    # (half its width at the far end: as the shader's)
		var corners := [Vector2(-hw, 0.0), Vector2(hw, 0.0), Vector2(hw, reach), Vector2(-hw, reach)]
		for t in [0, 1, 2, 0, 2, 3]:
			var c: Vector2 = corners[t]
			verts.append(Vector3(at.x + c.x, y, at.z + dir * c.y))
			uvs.append(c)                                # (m across from the middle, m out from the lamps)
			uv2s.append(Vector2(at.y, reach))
			cols.append(q[3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## A kind's two lamps (model space) for road_glow: Vector3(the middle between them across,
## half their spacing, their depth): each side's lens if found, else the lamps' box (its outer
## quarters), else the body's end.
static func lamp_pair(found: Dictionary, kind: String, box: AABB) -> Vector3:
	if found.has(kind + "_l_at") and found.has(kind + "_r_at"):
		var l: Vector3 = found[kind + "_l_at"]
		var r: Vector3 = found[kind + "_r_at"]
		return Vector3((l.x + r.x) * 0.5, absf(r.x - l.x) * 0.5, (l.z + r.z) * 0.5)
	if found.has(kind):
		var b: AABB = found[kind]
		return Vector3(b.get_center().x, maxf(b.size.x * 0.5 - 0.15, 0.3), b.position.z if kind == "head" else b.end.z)
	return Vector3(box.get_center().x, maxf(box.size.x * 0.5 - 0.3, 0.3), box.position.z if kind == "head" else box.end.z)


const ROAD_GLOW_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// UV: (m across from the middle between the lamps, m out from them); UV2: (half the lamps' spacing, the reach)
void fragment() {
	float hs = UV2.x;
	float reach = UV2.y;
	float d = max(UV.y, 0.0);
	float w = 0.2 + d * 0.3;                         // (each lamp's light, wider the further out)
	float a = exp(-pow((UV.x - hs) / w, 2.0)) + exp(-pow((UV.x + hs) / w, 2.0));
	float along = smoothstep(0.0, 1.0, d) * pow(clamp(1.0 - d / reach, 0.0, 1.0), 1.6);
	float edge = 1.0 - smoothstep(0.7, 1.0, abs(UV.x) / (hs + reach * 0.25));
	ALBEDO = COLOR.rgb * min(a, 1.25) * along * edge;
}
"""
