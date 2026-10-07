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
## when braking, both full at night. Real lights (two spot headlights, two small red tail
## lights) when it's dark (WorldMaterials.night) or Settings says CAR LIGHTS ON.
## LOW quality leaves the materials as they are (the lamps still glow).

const Graphics = preload("res://scripts/render/graphics.gd")
const WorldMaterials = preload("res://scripts/render/world_materials.gd")

## the car's model meshes go on this render layer (as well as no other), so its own
## reflection probe doesn't see it from inside
const CAR_LAYER := 1 << 10

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
var _lights: Array = []              # the real lights: [SpotLight3D x2, OmniLight3D x2]
var _probe: ReflectionProbe
var _brake := 0.0
var _night := false
var _real := false
var _mirror_done := false
var _mirror_tries := 0


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
	_graphics_changed()


## Every mesh of the model: the lamps found and lit, glass and chrome glossed, the layer set.
func _scan() -> void:
	var lamps_ok := not Graphics.headless()
	var gloss := Graphics.level() != "low"
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.mesh == null or _skip(m3):
			continue
		m3.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC         # (it moves: not part of SDFGI's world)
		m3.layers = CAR_LAYER
		var xf := _model_xf(m3)
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


static func _surface_box(mesh: Mesh, i: int) -> AABB:
	var v: PackedVector3Array = mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
	if v.is_empty():
		return AABB()
	var lo := v[0]
	var hi := v[0]
	for p in v:
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(lo, hi - lo)


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
## and the glowing copies shared by every car of that model. Call it after painting.
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
	var night := WorldMaterials.night
	var energy := {"head": 7.0 if night else 1.8, "tail": 3.0 if night else 0.8, "both": 4.0 if night else 1.1}
	for e in meshes:
		var m3: MeshInstance3D = e[0]
		var key := "%d|%s" % [m3.mesh.get_instance_id(), night]
		if not _model_lamps.has(key):
			var found := {}
			for i in m3.mesh.get_surface_count():
				var src := m3.mesh.surface_get_material(i)
				if not (src is BaseMaterial3D) or not _lamp_candidate(String(src.resource_name).to_lower(), src):
					continue
				var kind := _kind_in(box, (e[1] as Transform3D) * _surface_box(m3.mesh, i))
				if kind != "":
					var lm := _emissive(src, kind)
					lm.emission_energy_multiplier = energy[kind]
					found[i] = lm
			_model_lamps[key] = found
		for i in _model_lamps[key]:
			m3.set_surface_override_material(i, _model_lamps[key][i])


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
	_night = WorldMaterials.night
	var want_real := (Graphics.car_lights() == "on" or (Graphics.car_lights() == "auto" and _night)) and not Graphics.headless()
	if want_real != _real:
		_real = want_real
		_set_real_lights(want_real)
	var want_probe := bool(Graphics.get_value("probe")) and Graphics.forward() and not Graphics.headless()
	if want_probe and _probe == null:
		_add_probe()
	elif not want_probe and _probe:
		_probe.queue_free()
		_probe = null
	_glow(0.0)


func _process(dt: float) -> void:
	var want := 0.0
	if car and "inp" in car:
		want = clampf(float(car.inp.get("brake", 0.0)) * 1.5, 0.0, 1.0)
	_brake = move_toward(_brake, want, dt * 12.0)
	if WorldMaterials.night != _night:
		_graphics_changed()
	_glow(_brake)
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
	var head := 7.0 if _night else 2.2
	var tail := (3.0 if _night else 0.9) + brake * 7.0
	for m in _head:
		m.emission_energy_multiplier = head
	for m in _tail:
		m.emission_energy_multiplier = tail
	for m in _both:
		m.emission_energy_multiplier = 4.0 if _night else 1.2
	if _real:
		for l in _lights:
			if l is OmniLight3D:
				(l as OmniLight3D).light_energy = 0.25 + brake * 0.9


func _set_real_lights(on: bool) -> void:
	for l in _lights:
		l.queue_free()
	_lights.clear()
	if not on:
		return
	var off := model.position
	var hb := _merge(_head_at)
	var front_y := hb.get_center().y if hb.size != Vector3.ZERO else _box.position.y + 0.35 * _box.size.y
	var front_z := hb.position.z if hb.size != Vector3.ZERO else _box.position.z + 0.15
	var half := (hb.size.x * 0.5 if hb.size.x > 0.6 else _box.size.x * 0.5) * 0.72
	var shadows := Graphics.level() in ["high", "ultra"] and Graphics.forward()
	for side in [-1.0, 1.0]:
		var s := SpotLight3D.new()
		s.position = off + Vector3(hb.get_center().x + side * half if hb.size != Vector3.ZERO else side * half, front_y, front_z - 0.05)
		s.rotation = Vector3(deg_to_rad(-4.0), 0.0, 0.0)          # looking down the road (-z), a touch down
		s.spot_range = 75.0
		s.spot_angle = 30.0
		s.spot_angle_attenuation = 1.6
		s.spot_attenuation = 0.6
		s.light_energy = 9.0
		s.light_color = Color(1.0, 0.95, 0.86)
		s.light_specular = 0.6
		s.shadow_enabled = shadows and side > 0.0             # (one shadow: half the cost)
		add_child(s)
		_lights.append(s)
	var tb := _merge(_tail_at)
	var rear_z := tb.end.z if tb.size != Vector3.ZERO else _box.end.z - 0.1
	var rear_y := tb.get_center().y if tb.size != Vector3.ZERO else _box.position.y + 0.45 * _box.size.y
	for side in [-1.0, 1.0]:
		var o := OmniLight3D.new()
		o.position = off + Vector3(side * _box.size.x * 0.36, rear_y, rear_z + 0.25)
		o.omni_range = 2.2
		o.omni_attenuation = 1.5
		o.light_color = Color(1.0, 0.08, 0.04)
		o.light_energy = 0.25
		o.light_specular = 0.2
		add_child(o)
		_lights.append(o)


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
