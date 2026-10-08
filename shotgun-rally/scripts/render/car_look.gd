extends Node3D
## How a car's own model looks in the world: its lamps glow, its glass and chrome shine,
## and (HIGH / ULTRA) a reflection probe rides above it so the paint shows the road and
## the trees, not only the sky.
##
##   CarLook.dress(car, model, info)   once the model is built (RallyCar._build_own_model):
##                                     adds a CarLook node to the car and returns it
##
## The lamps: the car models are game rips with every kind of material, so the head and
## tail lamps are found by their material's name (light, lamp, lens, glow, tail, brake,
## red glass ...; never a screen, a dial, an indicator, a reverse or fog lamp), by already
## glowing, and by where on the car they are (the front or the back quarter). They get
## emission masked by their own texture: dim running lights by day, the tail lamps bright
## when braking, both full at night (fading in at dusk: WorldMaterials.night_amount). A lamp
## material over both ends is split front / back so the tail lamps glow red. The real
## lights (the headlights' beams, red on the road behind) are CarLamps'
## (scripts/vehicle/car_lamps.gd): the game fits them at night, CarLook itself at dusk or
## when Settings says CAR LIGHTS ALWAYS; they go where the lamps were found (lamp_boxes()).
## The tyres matte rubber.
## MEDIUM and up, Forward+: a soft contact shadow under the car (the sky can't reach under it: ambient
## occlusion, faked by a darkening quad on the ground, gone when it flies). At night the
## street lamps' few real lights (StreetLamps) light the car as it passes them.
## LOW quality leaves the materials as they are (the lamps still glow).

const Graphics = preload("res://scripts/render/graphics.gd")
const WorldMaterials = preload("res://scripts/render/world_materials.gd")
const CAR_LAMPS := "res://scripts/vehicle/car_lamps.gd"

## the car's model meshes go on this render layer (as well as no other), so its own
## reflection probe doesn't see it from inside
const CAR_LAYER := 1 << 10

const TYRE_WORDS := ["tire", "tyre", "rubber", "pneumatic", "tread", "sidewall", "sidetyre"]

const LAMP_WORDS := ["light", "lamp", "lens", "glow", "led", "beam", "xenon", "drl", "luminus", "emis", "tail",
	"brakel", "brake l", "brake_l", "lcover", "redglass", "red_glass", "glassred", "glass_red", "red glass", "headl"]
const NOT_LAMP := ["interior", "int_", "dash", "gauge", "guage", "screen", "lcd", "display", "monitor", "button", "seat",
	"belt", "cockpit", "steer", "sw_", "plate", "licen", "matricula", "number", "logo", "badge", "emblem", "symbol",
	"rim", "tire", "tyre", "wheel", "disc", "disk", "rotor", "calip", "callip", "mirror", "skin", "console", "shift",
	"kers", "aux", "roof", "speak", "frame", "signal", "indicator", "turn", "amber", "orange", "fog", "reverse",
	"rev_", "marker", "side", "meter", "needle", "camera", "cristal", "decal", "sticker", "text", "white", "detail"]

var car: Node3D
var model: Node3D
var _box := AABB()                   # the body, model space (m)
var _head: Array = []                # glowing materials (copies): head lamps
var _tail: Array = []                # ... tail lamps
var _both: Array = []                # ... one material for both ends (an atlas)
var _head_at: Array = []             # [AABB] where they are (model space)
var _tail_at: Array = []
var _probe: ReflectionProbe
var _brake := 0.0
var _nt := 0.0                       # how dark it is (WorldMaterials.night_amount when last looked)
var _own_lamps: Node3D              # CarLamps fitted here (dusk, CAR LIGHTS ALWAYS), not by the game
var _mirror_done := false
var _mirror_tries := 0
var _blob: MeshInstance3D            # the contact shadow
var _blob_amount := 0.0


static func dress(owner_car: Node3D, owner_model: Node3D, info: Dictionary) -> Node3D:
	var old := owner_car.get_node_or_null("CarLook")
	if old:                                          # (another body: the old one's lamps go with it)
		owner_car.remove_child(old)
		old.queue_free()
	var look: Node3D = (load("res://scripts/render/car_look.gd") as GDScript).new()
	look.name = "CarLook"
	look.car = owner_car
	look.model = owner_model
	var lo: Array = info.get("body_min", [-0.9, 0.1, -2.2])
	var hi: Array = info.get("body_max", [0.9, 1.3, 2.2])
	look._box = AABB(Vector3(lo[0], lo[1], lo[2]), Vector3(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]))
	look._scan()
	owner_car.add_child(look)
	return look


func _ready() -> void:
	add_to_group("graphics")
	_nt = WorldMaterials.night_amount
	_graphics_changed()


## Every mesh of the model: the lamps found and lit, glass and chrome glossed, the layer set.
func _scan() -> void:
	var lamps_ok := not Graphics.headless()
	var gloss := Graphics.level() != "low"
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.mesh == null:
			continue
		if _skip(m3):
			if gloss:
				_rubber(m3)
			continue
		m3.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC         # (it moves: not part of SDFGI's world)
		m3.layers = CAR_LAYER
		var xf := _model_xf(m3)
		if lamps_ok:
			_split_both(m3, xf, _box)
		for i in m3.mesh.get_surface_count():
			var src := m3.get_surface_override_material(i)
			if src == null:
				src = m3.mesh.surface_get_material(i)
			if not (src is BaseMaterial3D):
				continue
			var n := String(src.resource_name).to_lower()
			if lamps_ok and _lamp_candidate(n, src):
				var at := xf * _surface_box(m3.mesh, i)
				var kind := _lamp_kind(at, src)
				if kind != "":
					m3.set_surface_override_material(i, _lamp_material(src, kind, at))
					continue
			if gloss and n.begins_with("glass"):
				var g := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
				g.roughness = minf(g.roughness, 0.05)
				g.metallic_specular = maxf(g.metallic_specular, 0.65)
				m3.set_surface_override_material(i, g)
			elif gloss and "chrome" in n:
				var c := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
				c.metallic = 1.0
				c.roughness = minf(c.roughness, 0.12)
				if c.albedo_texture == null:
					c.albedo_color = Color(0.86, 0.86, 0.86)
				m3.set_surface_override_material(i, c)


## The tyres: matte rubber (the rips' tyres are often as shiny as the paint).
func _rubber(m3: MeshInstance3D) -> void:
	for i in m3.mesh.get_surface_count():
		var src := m3.get_surface_override_material(i)
		if src == null:
			src = m3.mesh.surface_get_material(i)
		if not (src is BaseMaterial3D):
			continue
		var n := String(src.resource_name).to_lower()
		var tyre := false
		for w in TYRE_WORDS:
			tyre = tyre or w in n
		if tyre:
			var r := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
			r.roughness = maxf(r.roughness, 0.86)
			r.metallic = 0.0
			r.metallic_specular = minf(r.metallic_specular, 0.3)
			r.clearcoat_enabled = false
			m3.set_surface_override_material(i, r)


## The wheels and the cockpit's moving parts aren't lamps.
func _skip(mi: Node) -> bool:
	var n: Node = mi
	while n and n != model:
		var s := String(n.name)
		if s.begins_with("Wheel_") or s.begins_with("Caliper_") or s in ["SteeringWheel", "Shifter", "Handbrake"]:
			return true
		n = n.get_parent()
	return false


func _model_xf(n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p and p != model:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## A surface's box (the vertices its triangles use: a split surface shares its vertex arrays).
static func _surface_box(mesh: Mesh, i: int) -> AABB:
	var arr := mesh.surface_get_arrays(i)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	if v.is_empty():
		return AABB()
	var idx = arr[Mesh.ARRAY_INDEX]
	var lo := Vector3.INF
	var hi := -Vector3.INF
	if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty():
		for k in idx:
			lo = lo.min(v[k])
			hi = hi.max(v[k])
	else:
		for p in v:
			lo = lo.min(p)
			hi = hi.max(p)
	return AABB(lo, hi - lo)


## One lamp material over both ends of the car (the head and the tail lamps in one: some
## rips): that surface split in two, front and back, so the tail lamps can glow red (and
## brighten on the brakes) and the headlamps white. The split mesh is shared by every car
## of the model (the same vertex arrays, two index lists); the material overrides kept.
static var _split_cache := {}

static func _split_both(m3: MeshInstance3D, xf: Transform3D, box: AABB) -> void:
	var mesh := m3.mesh
	if not (mesh is ArrayMesh) or (mesh as ArrayMesh).get_blend_shape_count() > 0:
		return
	var key := "%d|%s|%s" % [mesh.get_instance_id(), str(xf), str(box)]
	if not _split_cache.has(key):
		var both: Array = []
		for i in mesh.get_surface_count():
			var src := m3.get_surface_override_material(i)
			if src == null:
				src = mesh.surface_get_material(i)
			if src is BaseMaterial3D and mesh.surface_get_primitive_type(i) == Mesh.PRIMITIVE_TRIANGLES \
					and _lamp_candidate(String(src.resource_name).to_lower(), src) and _kind_in(box, xf * _surface_box(mesh, i)) == "both":
				both.append(i)
		_split_cache[key] = _split_mesh(mesh as ArrayMesh, xf, both, box) if not both.is_empty() else null
	var out: ArrayMesh = _split_cache[key]
	if out == null:
		return
	var keep := []
	for i in mesh.get_surface_count():
		keep.append(m3.get_surface_override_material(i))
	m3.mesh = out
	for i in keep.size():
		m3.set_surface_override_material(i, keep[i])


## The mesh again, each of the surfaces `both` split by where its triangles are: the front
## half's in its place, the back half's added at the end (the other surfaces' places kept).
static func _split_mesh(mesh: ArrayMesh, xf: Transform3D, both: Array, box: AABB):
	var out := ArrayMesh.new()
	var backs: Array = []
	var mid := box.get_center().z
	for j in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(j)
		var mat := mesh.surface_get_material(j)
		var flags := 0                                     # (the custom channels' formats, if any)
		for k in 4:
			flags |= mesh.surface_get_format(j) & (Mesh.ARRAY_FORMAT_CUSTOM_MASK << (Mesh.ARRAY_FORMAT_CUSTOM_BASE + k * Mesh.ARRAY_FORMAT_CUSTOM_BITS))
		if j in both:
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
			var front := PackedInt32Array()
			var rear := PackedInt32Array()
			for t in range(0, idx.size() - 2, 3):
				var cz := (xf * ((v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0)).z
				if cz < mid:
					front.append_array([idx[t], idx[t + 1], idx[t + 2]])
				else:
					rear.append_array([idx[t], idx[t + 1], idx[t + 2]])
			if not front.is_empty() and not rear.is_empty():
				var b := arr.duplicate()
				b[Mesh.ARRAY_INDEX] = rear
				backs.append([b, mat, flags])
				arr[Mesh.ARRAY_INDEX] = front
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(j), arr, [], {}, flags)
		out.surface_set_material(out.get_surface_count() - 1, mat)
		out.surface_set_name(out.get_surface_count() - 1, mesh.surface_get_name(j))
	for e in backs:
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, e[0], [], {}, e[2])
		out.surface_set_material(out.get_surface_count() - 1, e[1])
	return out


## A lamp by its name, or glowing already, and not anything that only sounds like one.
static func _lamp_candidate(n: String, m: BaseMaterial3D) -> bool:
	for w in NOT_LAMP:
		if w in n:
			return false
	if n.begins_with("glass") and not ("light" in n or "lamp" in n or "lens" in n):
		return false                               # (the windows)
	for w in LAMP_WORDS:
		if w in n:
			return true
	return m.emission_enabled and m.emission.get_luminance() * m.emission_energy_multiplier > 0.05


## "head", "tail", "both" (one material at both ends) or "" (somewhere else: not a lamp).
func _lamp_kind(at: AABB, _m: BaseMaterial3D) -> String:
	return _kind_in(_box, at)


## "head", "tail", "both" or "" for a surface's box `at` on a body `box` (model space, -z forward).
static func _kind_in(box: AABB, at: AABB) -> String:
	var length := box.size.z
	if length <= 0.0 or at.size == Vector3.ZERO:
		return ""
	var front := box.position.z
	if at.size.z > length * 0.6:
		return "both"
	var c := at.get_center()
	var zf := (c.z - front) / length                  # 0 the nose, 1 the tail (the model looks down -z)
	if c.y < box.position.y + 0.12 or c.y > box.end.y - 0.05:
		return ""                                      # (under the car, on the roof)
	if zf < 0.24:
		return "head"
	if zf > 0.76:
		return "tail"
	return ""


## A lamp's material: a copy of its own, glowing (masked by its texture), white or red.
static func _emissive(src: BaseMaterial3D, kind: String) -> BaseMaterial3D:
	var m := src.duplicate() as BaseMaterial3D
	m.emission_enabled = true
	var col := Color(1.0, 0.95, 0.86)
	if kind == "tail":
		var a := m.albedo_color
		col = Color(1.0, 0.07, 0.03) if not (a.r > 0.4 and a.r > a.g * 2.0) else Color(1.0, a.g / a.r * 0.5, a.b / a.r * 0.5)
	if m.albedo_texture:
		m.emission_texture = m.albedo_texture
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	elif m.emission_texture == null:
		m.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
	m.emission = col
	return m


## Traffic and other plain car models (not a RallyCar): their lamps glow, running lights by
## day, full at night (no brake lights, no real lights). The lamps are found once per mesh
## and the glowing copies shared by every car of that model. Call it after painting. Where
## they are goes on root's meta "lamp_boxes" ({"head"/"tail": AABB, root's space}: CarLamps
## puts its beams there and leaves out its glow sprites).
static var _model_lamps := {}


static func glow_model(root: Node3D) -> void:
	if Graphics.headless() or root == null:
		return
	var box := AABB()
	var meshes: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.mesh == null or String(m3.name).begins_with("Wheel") or String(m3.get_parent().name).begins_with("Wheel"):
			continue
		var xf := _xf_in(m3, root)
		var b := xf * m3.mesh.get_aabb()
		box = b if box.size == Vector3.ZERO else box.merge(b)
		meshes.append([m3, xf])
	var nt := snappedf(WorldMaterials.night_amount, 0.1)
	var energy := {"head": lerpf(1.8, 7.0, nt), "tail": lerpf(0.8, 3.0, nt), "both": lerpf(1.1, 4.0, nt)}
	var boxes := {}
	for e in meshes:
		var m3: MeshInstance3D = e[0]
		_split_both(m3, e[1], box)
		var key := "%d|%s" % [m3.mesh.get_instance_id(), nt]
		if not _model_lamps.has(key):
			var found := {}
			for i in m3.mesh.get_surface_count():
				var src := m3.mesh.surface_get_material(i)
				if not (src is BaseMaterial3D) or not _lamp_candidate(String(src.resource_name).to_lower(), src):
					continue
				var at := (e[1] as Transform3D) * _surface_box(m3.mesh, i)
				var kind := _kind_in(box, at)
				if kind != "":
					var lm := _emissive(src, kind)
					lm.emission_energy_multiplier = energy[kind]
					lm.set_meta("at", at)
					lm.set_meta("kind", kind)
					found[i] = lm
			_model_lamps[key] = found
		for i in _model_lamps[key]:
			var lm: BaseMaterial3D = _model_lamps[key][i]
			m3.set_surface_override_material(i, lm)
			var kind: String = lm.get_meta("kind")
			var at: AABB = lm.get_meta("at")
			if kind != "both":
				boxes[kind] = at if not boxes.has(kind) else (boxes[kind] as AABB).merge(at)
	root.set_meta("lamp_boxes", boxes)


## Where this car's lamps are ({"head"/"tail": AABB in the model's space}; a kind left out
## where none was found): CarLamps puts its beams there.
func lamp_boxes() -> Dictionary:
	var out := {}
	if not _head_at.is_empty():
		out["head"] = _merge(_head_at)
	if not _tail_at.is_empty():
		out["tail"] = _merge(_tail_at)
	return out


static func _xf_in(n: Node3D, root: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func _lamp_material(src: BaseMaterial3D, kind: String, at: AABB) -> BaseMaterial3D:
	var m := _emissive(src, kind)
	match kind:
		"head":
			_head.append(m)
			_head_at.append(at)
		"tail":
			_tail.append(m)
			_tail_at.append(at)
		_:
			_both.append(m)
	return m


func _graphics_changed() -> void:
	_nt = WorldMaterials.night_amount
	_car_lamps.call_deferred()
	# (the contact shadow multiplies the ground: Forward+ only, Compatibility's tonemapped
	# multiply darkens the whole quad: a dark box under the car)
	var fancy := Graphics.level() != "low" and not Graphics.headless() and Graphics.forward()
	if fancy and _blob == null:
		_add_blob()
	elif not fancy and _blob:
		_blob.queue_free()
		_blob = null
	var want_probe := bool(Graphics.get_value("probe")) and Graphics.forward() and not Graphics.headless()
	if want_probe and _probe == null:
		_add_probe()
	elif not want_probe and _probe:
		_probe.queue_free()
		_probe = null
	_glow(0.0)


## The real lights (CarLamps) at dusk, or always if Settings says so; the game's own (at
## night) left as they are. (Deferred: the car may be busy taking its children in.)
func _car_lamps() -> void:
	if not is_inside_tree() or car == null:
		return
	var want := (Graphics.car_lights() == "on" or (Graphics.car_lights() == "auto" and _nt > 0.3)) and not Graphics.headless()
	var fitted = car.get_node_or_null("CarLamps")
	if want and (fitted == null or fitted.model != model):
		var yours: bool = car.get("simulate") == true           # (the player's car: twin beams, the red on the road)
		_own_lamps = load(CAR_LAMPS).fit(car, model, true, yours)
	elif not want and _own_lamps and is_instance_valid(_own_lamps) and fitted == _own_lamps:
		_own_lamps.remove()
		_own_lamps.name = "CarLampsOld"
		_own_lamps = null


func _process(dt: float) -> void:
	var want := 0.0
	if car and "inp" in car:
		want = clampf(float(car.inp.get("brake", 0.0)) * 1.5, 0.0, 1.0)
	_brake = move_toward(_brake, want, dt * 12.0)
	if not is_equal_approx(WorldMaterials.night_amount, _nt):
		_graphics_changed()
	_glow(_brake)
	if _blob:
		_place_blob(dt)
	if not _mirror_done and Engine.get_process_frames() % 15 == 0:
		_mirror_tries += 1
		_mirror_done = _mirror_tries > 20                 # (no cockpit mirror: the menu's car)
		_light_mirror()


## The rear-view mirror's little camera (the cockpit's, made after the car): the world's
## light without the costly screen-space effects and GI (a second SDFGI for a 400 px mirror).
func _light_mirror() -> void:
	var vp := car.find_child("MirrorView", true, false) as SubViewport
	var world := car.get_world_3d()
	if vp == null or world == null or world.environment == null:
		return
	_mirror_done = true
	var env := world.environment.duplicate() as Environment
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.ssr_enabled = false
	env.sdfgi_enabled = false
	env.glow_enabled = false
	for c in vp.get_children():
		if c is Camera3D:
			(c as Camera3D).environment = env


## The lamps' glow: running lights by day, full at night; the tail lamps brighter as the brake goes on.
func _glow(brake: float) -> void:
	var head := lerpf(2.2, 7.0, _nt)
	var tail := lerpf(0.9, 3.0, _nt) + brake * 7.0
	for m in _head:
		m.emission_energy_multiplier = head
	for m in _tail:
		m.emission_energy_multiplier = tail
	for m in _both:
		m.emission_energy_multiplier = lerpf(1.2, 4.0, _nt)


## The contact shadow: a quad the car's footprint (a little more), darkening the ground
## under it most in the middle (blend_mul); top_level, laid on the plane of the tyres'
## contacts each frame.
func _add_blob() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.orientation = PlaneMesh.FACE_Y
	var sh := Shader.new()
	sh.code = BLOB_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("aspect", _box.size.z / maxf(_box.size.x, 0.5))
	_blob = MeshInstance3D.new()
	_blob.name = "ContactShadow"
	_blob.mesh = q
	_blob.material_override = m
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blob.top_level = true
	_blob.visible = false
	add_child(_blob)


func _place_blob(dt: float) -> void:
	var ws: Array = car.get("wheels") if car and "wheels" in car else []
	var n := 0
	var at := Vector3.ZERO
	var up := Vector3.ZERO
	for w in ws:
		if w and w.grounded:
			n += 1
			at += w.contact
			up += w.normal
	var want := 1.0 if n >= 2 else 0.0
	_blob_amount = move_toward(_blob_amount, want, dt * (6.0 if want > _blob_amount else 4.0))
	_blob.visible = _blob_amount > 0.01
	if n < 2 or not _blob.visible:
		return
	at /= n
	up = up.normalized()
	var xf := model.global_transform
	var fwd := -xf.basis.z
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var right := fwd.cross(up).normalized()
	var c := xf * _box.get_center()
	c = c - up * (c - at).dot(up)                          # (the body's middle, on the ground's plane)
	var w := _box.size.x * 1.25
	var l := _box.size.z * 1.12
	_blob.global_transform = Transform3D(Basis(right * w, up, -fwd * l), c + up * 0.03)
	(_blob.material_override as ShaderMaterial).set_shader_parameter("amount", _blob_amount * (0.62 if Graphics.forward() else 0.5))


const BLOB_SHADER := """
shader_type spatial;
render_mode blend_mul, unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform float amount = 0.6;
uniform float aspect = 2.4;
void fragment() {
	vec2 p = abs(UV * 2.0 - 1.0);
	// a rounded rectangle, soft all round, darkest in the middle
	vec2 q = max(p - vec2(0.55, 0.7), 0.0) / vec2(0.45, 0.3);
	float d = length(q);
	float f = (1.0 - smoothstep(0.0, 1.0, d)) * (1.0 - 0.35 * max(p.x, p.y * 0.6));
	ALBEDO = vec3(1.0 - amount * f);
}
"""


static func _merge(boxes: Array) -> AABB:
	var out := AABB()
	for b in boxes:
		out = b if out.size == Vector3.ZERO else out.merge(b)
	return out


## The probe: just above the roof (so it doesn't look out from inside the car), its box
## round the whole car, updated every frame, out to 60 m.
func _add_probe() -> void:
	_probe = ReflectionProbe.new()
	_probe.name = "Reflections"
	var top := _box.end.y + 0.35
	_probe.position = model.position + Vector3(_box.get_center().x, top, _box.get_center().z)
	_probe.size = Vector3(_box.size.x + 1.2, (top + 0.3) * 2.0, _box.size.z + 1.2)
	_probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	_probe.max_distance = 60.0
	_probe.intensity = 1.0
	_probe.blend_distance = 0.4
	_probe.cull_mask = 0xFFFFF & ~CAR_LAYER & ~(1 << 1) & ~(1 << 2) & ~(1 << 12)    # not the car itself, the crew's helmets, the card trees (cost)
	_probe.mesh_lod_threshold = 4.0
	add_child(_probe)
