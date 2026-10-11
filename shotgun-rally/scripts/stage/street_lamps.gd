extends Node3D
## Street lamps at night (a touge's, the LAKESHORE LOOP's viaducts and city, a highway
## stage's): out there the only light. Each lamp gets its sodium head lit, a glare round
## it, and a pool of light on the road under it, faked (a disc over the road, no real
## light: hundreds of them cost next to nothing, all batched in three MultiMeshes). On
## Forward+ with the lamps apart (a touge) the pool multiplies what's under it, so the
## asphalt brightens as much as its colour lets it and a white line more, as under a real
## lamp (plus a little added: a black road has nothing to multiply); pools that overlap (a
## highway's) and Compatibility (the web, Chromebooks: its screen can't brighten past white
## by multiplying) add the light. The few lamps nearest the player's car get real lights as
## well, so the car, the guardrails and the trees light up as they go past and fade out
## again behind, one handing over to the next without a pop however many there are round a
## hairpin (where the pools multiply, not the road: it's on WorldMaterials.ROAD_LAYER, lit
## by its pool; multiplied twice over it would blow out; where they add, the road too: the
## lines show up under the lamps). At dusk and dawn (WorldMaterials.night_amount between 0
## and 1) all of it dimmer.
##   setup(lamps): [{head: Vector3 (the glass), ground: Vector3 (the road under it: the
##     pool's middle), up?: the road's normal there (the pool lies tilted on a grade, not
##     half buried in it), radius?: the pool's (m, default 9), s?: along the road, arm?:
##     Vector3, the way the lamp's arm reaches (the glass hangs with its long side along it,
##     not along the world's x), clip?: Vector2 (m from the pool's middle: how far its light
##     reaches out, away from the road, and in, across it: it stops where the ground falls
##     away, not hanging in the air over the drop)}]
##   head_xform(lamp), pool_xform(lamp): where the glass and the pool are (the tests read them)
##   target: the node whose nearest lamps get the real lights (the player's car)
## WorldMaterials.street_lights(parent, lamps) makes one (none by day).

const WorldMaterials = preload("res://scripts/render/world_materials.gd")
const Graphics = preload("res://scripts/render/graphics.gd")
const SODIUM := WorldMaterials.SODIUM
const REAL := 4                 # lamps with a real light (the nearest the car)
const REAL_RANGE := 26.0        # m the real light reaches
const REAL_ENERGY := 12.0
const FADE := [32.0, 52.0]      # m from the car: a real light full, gone (no pop when it moves on)
const POOL_R := 9.0             # m: the faked pool's radius (a lamp's own "radius" if it says)
const POOL_COLOUR := Color(1.0, 0.7, 0.42)   # (the light on the road: less saturated than the lamp's glass)

var lamps: Array = []
var target: Node3D
var lit := 1.0                  # how dark it was when lit (WorldMaterials.night_amount)
var overlapping := false        # (the pools overlap: added only, see _pool_material)
var _lights: Array = []         # OmniLight3D
var _near: Array = []           # the lamps within reach of the target (refreshed a few times a second)
var _pools: MultiMeshInstance3D
var _t := 0.0


func setup(lamp_list: Array) -> void:
	lamps = lamp_list
	name = "StreetLamps"
	add_to_group("street_lights")
	lit = clampf(WorldMaterials.night_amount, 0.0, 1.0)
	if lamps.is_empty():
		return
	overlapping = _overlap(lamps)
	var heads := _instances(_head_mesh(), WorldMaterials.street_lamp_head())
	var glare := _instances(_glare_mesh(), _glare_material())
	_pools = _instances(_pool_mesh(), _pool_material(), false, true)
	for i in lamps.size():
		var l: Dictionary = lamps[i]
		var head: Vector3 = l.head
		heads.multimesh.set_instance_transform(i, head_xform(l))
		glare.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 2.7), head - Vector3.UP * 0.14))
		_pools.multimesh.set_instance_transform(i, pool_xform(l))
		_pools.multimesh.set_instance_custom_data(i, pool_clip(l))
	for k in REAL:
		var o := OmniLight3D.new()
		o.light_color = SODIUM
		o.omni_range = REAL_RANGE
		o.omni_attenuation = 1.0
		o.light_energy = 0.0
		o.light_specular = 0.7
		if Graphics.forward() and not overlapping:
			o.light_cull_mask = 0xFFFFF & ~WorldMaterials.ROAD_LAYER   # (the road: the multiplying pool's, not twice over)
		o.shadow_enabled = false
		o.visible = false
		add_child(o)
		_lights.append(o)


## The glass's place: at the head, its long side along the lamp's arm (a lamp that doesn't
## say which way its arm reaches: along the world's x, as it always was).
static func head_xform(l: Dictionary) -> Transform3D:
	var arm: Vector3 = l.get("arm", Vector3.ZERO)
	var b := Basis()
	arm.y = 0.0
	if arm.length_squared() > 1e-6:
		var x := arm.normalized()
		b = Basis(x, Vector3.UP, x.cross(Vector3.UP))
	return Transform3D(b, l.head)


## The pool's place: a disc `radius` across lying on the road at `ground`, tilted with it
## (`up`), a little over it; its x points out, away from the road (against the arm: the way
## `clip` cuts it off). PlaneMesh 1 x 1, so the basis carries the size.
static func pool_xform(l: Dictionary) -> Transform3D:
	var head: Vector3 = l.head
	var ground: Vector3 = l.get("ground", head - Vector3.UP * 8.0)
	var up: Vector3 = (l.get("up", Vector3.UP) as Vector3).normalized()
	var r := float(l.get("radius", POOL_R))
	var out: Vector3 = -(l.get("arm", Vector3.ZERO) as Vector3)
	out -= up * out.dot(up)
	var x: Vector3
	if out.length_squared() > 1e-6:
		x = out.normalized()
	else:
		x = up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(up).normalized()
	return Transform3D(Basis(x * r * 2.0, up, z * r * 2.0), ground + up * 0.07)


## How far the pool's light reaches out and in (its custom data, in its radii: 2 = all of it).
static func pool_clip(l: Dictionary) -> Color:
	var r := float(l.get("radius", POOL_R))
	var c: Vector2 = l.get("clip", Vector2(2.0, 2.0) * r)
	return Color(c.x / r, c.y / r, 0.0, 0.0)


func _instances(mesh: Mesh, mat: Material, colours := false, custom := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colours
	mm.use_custom_data = custom
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
	if _t <= 0.0:                                    # (the lamps near enough to matter: a few times a second)
		_t = 0.2
		_near.clear()
		for i in lamps.size():
			if at.distance_squared_to(lamps[i].head) < FADE[1] * FADE[1] * 4.0:
				_near.append(i)
	# each near lamp by how far it is from the car (full to FADE[0], none past FADE[1]); the REAL
	# brightest get the lights, each less the first one left out: a lamp handing its light over to
	# the next fades out as the other fades in, never a pop, however many stand round a hairpin
	var by: Array = []                               # [how much, lamp]
	for i in _near:
		var f := 1.0 - clampf((at.distance_to(lamps[i].head) - FADE[0]) / (FADE[1] - FADE[0]), 0.0, 1.0)
		if f > 0.0:
			by.append([f, i])
	by.sort_custom(func(a, b): return a[0] > b[0])
	var spare: float = by[REAL][0] if by.size() > REAL else 0.0
	var want := {}                                   # lamp -> how much of a light
	for k in mini(REAL, by.size()):
		want[by[k][1]] = float(by[k][0]) - spare
	# a light stays with its lamp while that's still one of them; a free one goes to a new one
	var held := {}
	var free: Array = []
	for o in _lights:
		var i: int = o.get_meta("lamp", -1)
		if want.has(i) and not held.has(i):
			held[i] = o
		else:
			free.append(o)
	for i in want:
		if not held.has(i) and not free.is_empty():
			var o: OmniLight3D = free.pop_back()
			o.set_meta("lamp", i)
			o.global_position = (lamps[i].head as Vector3) - Vector3.UP * 0.4
			held[i] = o
	for o in free:
		o.set_meta("lamp", -1)
		o.light_energy = 0.0
		o.visible = false
	for i in held:
		var o: OmniLight3D = held[i]
		o.light_energy = REAL_ENERGY * lit * float(want[i])
		o.visible = float(want[i]) > 0.01


static func _head_mesh() -> Mesh:
	var b := BoxMesh.new()
	b.size = Vector3(0.62, 0.07, 0.31)
	return b


static func _glare_mesh() -> Mesh:
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	return q


static var _sprite: GradientTexture2D

func _glare_material() -> Material:
	if _sprite == null:
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.76, 0.46, 0.92))
		g.set_color(1, Color(1.0, 0.5, 0.15, 0.0))
		g.add_point(0.19, Color(1.0, 0.62, 0.29, 0.35))
		_sprite = GradientTexture2D.new()
		_sprite.gradient = g
		_sprite.fill = GradientTexture2D.FILL_RADIAL
		_sprite.fill_from = Vector2(0.5, 0.5)
		_sprite.fill_to = Vector2(1.0, 0.5)
		_sprite.width = 128
		_sprite.height = 128
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = _sprite
	m.albedo_color = Color(1.5, 1.5, 1.5) * lit
	return m


static func _pool_mesh() -> Mesh:
	var p := PlaneMesh.new()
	p.size = Vector2(1.0, 1.0)
	return p


## The pool. Forward+, lamps apart (a touge's): it multiplies what's under it by 1 + the
## light (a white line brightens more than the asphalt, the headlights' patch with it) and
## adds some (a black road has nothing to multiply). Pools that overlap (a highway's lamps,
## every 48 m, both carriageways) only add: multiplied twice over they'd blow the road out
## to white. Compatibility adds (its screen can't brighten past white by multiplying).
func _pool_material() -> Material:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	if Graphics.forward() and not overlapping:
		sh.code = POOL_SHADER
		m.set_shader_parameter("gain", 8.0 * lit)
		var add := ShaderMaterial.new()
		var sh2 := Shader.new()
		sh2.code = POOL_SHADER.replace("blend_mul", "blend_add").replace("vec3 lit = 1.0 + colour.rgb * gain * f;",
			"vec3 lit = colour.rgb * gain * f;")
		add.shader = sh2
		add.set_shader_parameter("colour", POOL_COLOUR)
		add.set_shader_parameter("gain", 0.11 * lit)
		m.next_pass = add
	else:
		sh.code = POOL_SHADER.replace("blend_mul", "blend_add").replace("vec3 lit = 1.0 + colour.rgb * gain * f;",
			"vec3 lit = colour.rgb * gain * f;")
		m.set_shader_parameter("gain", (0.1 if Graphics.forward() else 0.32) * lit)
	m.shader = sh
	m.set_shader_parameter("colour", POOL_COLOUR)
	return m


## Do any two pools overlap (their discs' edges within each other)? (Grid-bucketed: a
## loop's ~700 lamps.)
static func _overlap(list: Array) -> bool:
	var grid := {}
	for i in list.size():
		var g: Vector3 = list[i].get("ground", list[i].head)
		var key := Vector2i(floori(g.x / 40.0), floori(g.z / 40.0))
		var r := float(list[i].get("radius", POOL_R))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for j in grid.get(key + Vector2i(dx, dz), []):
					var h: Vector3 = list[j].get("ground", list[j].head)
					if g.distance_to(h) < (r + float(list[j].get("radius", POOL_R))) * 0.9:
						return true
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)
	return false


const POOL_SHADER := """
shader_type spatial;
render_mode blend_mul, unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform vec4 colour : source_color = vec4(1.0, 0.58, 0.22, 1.0);
uniform float gain = 40.0;
varying vec2 clip;
varying float across;
void vertex() {
	// (how far out and in the light reaches, in radii: the lamp's clip; x points out)
	clip = INSTANCE_CUSTOM.xy;
	across = VERTEX.x * 2.0;
}
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	// (even under the lamp, then falling away: neighbouring lamps' pools meet, as real ones do)
	float f = (1.0 - smoothstep(0.45, 1.0, r)) * (1.0 - 0.5 * min(r, 1.0));
	// (none past where the ground falls away: a disc out there would hang in the air)
	f *= (1.0 - smoothstep(clip.x - 0.08, clip.x, across)) * (1.0 - smoothstep(clip.y - 0.08, clip.y, -across));
	vec3 lit = 1.0 + colour.rgb * gain * f;
	ALBEDO = lit;
}
"""
