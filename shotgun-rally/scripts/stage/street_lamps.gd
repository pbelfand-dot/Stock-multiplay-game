extends Node3D
## A touge's street lamps at night: the only light out there. Each lamp (the posts
## are the stage builder's) gets its sodium head lit, a glare round it, and a pool
## of light on the road under it, faked (a disc that brightens what's beneath, no
## real light: a whole pass of them costs next to nothing). The few lamps nearest
## the player's car get real lights as well, so the car, the guardrails and the
## cedars light up as they go past, and fade out again behind.
##   setup(lamps): [{head: Vector3 (the glass), ground: Vector3 (the road under it)}]
##   target: the node whose nearest lamps get the real lights (the player's car)

const SODIUM := Color(1.0, 0.6, 0.26)
const REAL := 4                 # lamps with a real light (the nearest the car)
const REAL_RANGE := 24.0        # m the real light reaches
const REAL_ENERGY := 9.0
const FADE := [32.0, 52.0]      # m from the car: a real light full, gone (no pop when it moves on)
const POOL_R := 9.0             # m: the faked pool's radius

var lamps: Array = []
var target: Node3D
var _lights: Array = []         # OmniLight3D
var _pools: MultiMeshInstance3D
var _pool_fade := PackedFloat32Array()   # each lamp's pool: 1 shown, 0 (a real light there instead)
var _t := 0.0


func setup(lamp_list: Array) -> void:
	lamps = lamp_list
	name = "StreetLamps"
	add_to_group("street_lights")
	if lamps.is_empty():
		return
	var heads := _instances(_head_mesh(), _head_material())
	var glare := _instances(_glare_mesh(), _glare_material())
	_pools = _instances(_pool_mesh(), _pool_material(), true)
	_pool_fade.resize(lamps.size())
	for i in lamps.size():
		var l: Dictionary = lamps[i]
		var head: Vector3 = l.head
		heads.multimesh.set_instance_transform(i, Transform3D(Basis(), head))
		glare.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 2.8), head - Vector3.UP * 0.15))
		_pools.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(POOL_R * 2.0, 1.0, POOL_R * 2.0)),
			(l.ground as Vector3) + Vector3.UP * 0.06))
		_pools.multimesh.set_instance_color(i, Color(1, 1, 1, 1))
		_pool_fade[i] = 1.0
	for k in REAL:
		var o := OmniLight3D.new()
		o.light_color = SODIUM
		o.omni_range = REAL_RANGE
		o.omni_attenuation = 1.0
		o.light_energy = 0.0
		o.shadow_enabled = false
		o.visible = false
		add_child(o)
		_lights.append(o)


func _instances(mesh: Mesh, mat: Material, colours := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colours
	mm.mesh = mesh
	mm.instance_count = lamps.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func _process(dt: float) -> void:
	if target == null or not is_instance_valid(target) or lamps.is_empty():
		return
	_t -= dt
	var at: Vector3 = target.global_position
	if _t <= 0.0:                                    # (which lamps are nearest: a few times a second)
		_t = 0.2
		var near: Array = []
		for i in lamps.size():
			near.append([at.distance_squared_to(lamps[i].head), i])
		near.sort_custom(func(a, b): return a[0] < b[0])
		for k in REAL:
			var o: OmniLight3D = _lights[k]
			var i: int = near[k][1] if k < near.size() else -1
			o.set_meta("lamp", i)
			if i >= 0:
				o.global_position = (lamps[i].head as Vector3) - Vector3.UP * 0.4
	# each real light by how far its lamp is from the car; the faked pool the other way
	var want := PackedFloat32Array()
	want.resize(lamps.size())
	want.fill(1.0)
	for o in _lights:
		var i: int = o.get_meta("lamp", -1)
		if i < 0:
			o.visible = false
			continue
		var f := 1.0 - clampf((at.distance_to(lamps[i].head) - FADE[0]) / (FADE[1] - FADE[0]), 0.0, 1.0)
		o.light_energy = REAL_ENERGY * f
		o.visible = f > 0.01
		want[i] = 1.0 - f * 0.75                     # (a touch of pool stays: the hot spot under it)
	for i in lamps.size():
		if absf(want[i] - _pool_fade[i]) > 0.01:
			_pool_fade[i] = move_toward(_pool_fade[i], want[i], dt * 3.0)
			_pools.multimesh.set_instance_color(i, Color(1, 1, 1, _pool_fade[i]))


static func _head_mesh() -> Mesh:
	var b := BoxMesh.new()
	b.size = Vector3(0.62, 0.08, 0.32)
	return b


static func _head_material() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.85, 0.75)
	m.emission_enabled = true
	m.emission = SODIUM
	m.emission_energy_multiplier = 6.0
	return m


static func _glare_mesh() -> Mesh:
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	return q


static func _glare_material() -> Material:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.78, 0.5, 0.95))
	g.set_color(1, Color(1.0, 0.5, 0.15, 0.0))
	g.add_point(0.2, Color(1.0, 0.62, 0.3, 0.35))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = t
	m.albedo_color = Color(1.4, 1.4, 1.4)
	return m


static func _pool_mesh() -> Mesh:
	var p := PlaneMesh.new()
	p.size = Vector2(1.0, 1.0)
	return p


## The pool: sodium light added to the road under the lamp, strongest in the middle
## (added, not multiplied: the web / Compatibility screen can't brighten past white
## by multiplying); COLOR.a fades it (a real light there instead).
static func _pool_material() -> Material:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform vec4 colour : source_color = vec4(1.0, 0.6, 0.26, 1.0);
uniform float gain = 0.32;
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float f = pow(clamp(1.0 - r, 0.0, 1.0), 1.6) * COLOR.a;
	ALBEDO = colour.rgb * gain * f;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("colour", SODIUM)
	return m
