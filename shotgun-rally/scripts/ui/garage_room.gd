extends RefCounted
## The garage behind the home screen (MenuGarage builds it): the room, made in code from
## boxes, cylinders and a few turned shapes (tyres, wheels, helmets). No model files: it's
## laid out from the four Higgsfield views in assets/garage/reference/ (GENERATION_NOTES.md;
## a 3D model made from them was unusable). Each material's pieces are merged into one mesh,
## so the whole room is ~25 draw calls and builds in a few tens of milliseconds.
##
## In m, the room's own coordinates: x across (+ right, facing the roll-up door), y up,
## z along (the door at -z, the back wall at +z), the floor's middle at 0. (The references'
## plan has Y toward the door: Godot's z is minus that.)
##   the shell: 10 x 14, 4.8 to a black roof deck, no windows; polished charcoal concrete floor,
##     graphite walls
##   door wall (z -7): a sectional roll-up door 7.6 x 3.0, a groove every 0.6 m, framed by
##     6 cm LED strips (x +-3.89, to 3.12 m, and across the top); thin conduits at x +-4.55
##   ceiling: a soffit beam over the back (bottom 4.0 m), I-beams across at z -6, -3, 0, 3
##     (bottom 4.3), two trusses along at x +-3.3 (chords 3.7-3.8 and 4.4-4.5, a post every
##     2 m, diagonals alternating), spiral ducts (0.44 m) along both walls, ten 1.2 m LED
##     fixtures under the trusses, and over the car a suspended light box 4.4 x 5.0 (x +-2.2,
##     z -4..1, 3.6-4.3 m high): pale concrete sides, a glowing underside
##   left wall (x -5), back to front: a helmet shelf, a carbon bucket seat on a stand, two tyre
##     racks on casters (four tiers of upright tyres; two silver wheels in the first one's
##     bottom tier), a black cabinet run with a wood top, a backsplash and a battery charger
##   right wall (x +5), front to back: a two-post lift (its arms folded flat to the wall, red
##     pads, a silver cylinder), a rolling tool chest (amber bottles, a blue towel), a
##     detailing station (low cabinet, a shelf of seven amber bottles, a blue hose reel)
##   back wall (z +7): a workbench (wood top) under a pegboard of chrome tools and a shelf
##     with two helmets, all framed by an LED strip; a vent grille high up; a black-and-white
##     photograph of a mountain road; a black personnel door
## The car stands at SPOT, under the light box.
##
##   var room = GarageRoom.new(); add_child(room.build())
##   room.props       [{name, box}]: the furniture's bounding boxes (the camera keeps clear)
##   room.mats[key]   the materials ("led_door": the door's LED frame, MenuGarage tints it)

const LAYER := 1 << 19               # the room's meshes are on this render layer too: the room's reflection probe sees only them
const HALF_W := 5.0
const HALF_D := 7.0
const HEIGHT := 4.8
const SPOT := Vector3(0.0, 0.0, -1.5)
const LIGHT_BOX := AABB(Vector3(-2.2, 3.6, -4.0), Vector3(4.4, 0.7, 5.0))
const TEX := "res://assets/textures/world/concrete_%s.webp"   # (Poly Haven, CC0: docs/CREDITS_WORLD.md)
const LED := Color(1.0, 0.953, 0.937)          # ~6000 K
const BOX_GLOW := Color(1.0, 0.9, 0.8)         # ~4800 K

## Concrete for the floor, the walls and the light box: the photographed concrete's light and
## dark only (no colour), twice over at different sizes so it never tiles, round a colour;
## the roughness follows it (a polished floor has duller patches). glow: the light box's underside.
const CONCRETE := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 colour : source_color = vec3(0.17);
uniform float scale = 0.35;
uniform float contrast = 0.5;
uniform float rough = 0.2;
uniform float rough_var = 0.3;
uniform float bump = 0.2;
uniform vec3 glow : source_color = vec3(0.0);
uniform float glow_energy = 0.0;
void fragment() {
	vec2 uv = UV * scale;
	float a = dot(texture(tex, uv).rgb, vec3(0.299, 0.587, 0.114)) - 0.173;
	float b = dot(texture(tex, uv * 0.173 + vec2(0.31, 0.77)).rgb, vec3(0.299, 0.587, 0.114)) - 0.173;
	float v = a * contrast + b * contrast * 0.9;
	ALBEDO = colour * clamp(1.0 + v, 0.35, 2.0);
	ROUGHNESS = clamp(rough + v * rough_var, 0.05, 1.0);
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(nrm, uv).rgb, bump);
	EMISSION = glow * glow_energy * clamp(1.0 + v * 0.6, 0.6, 1.4);
}
"""

## The framed print on the back wall: a black-and-white night photograph of a mountain road
## winding up a valley, the cars' light trails on it (drawn here, no image file).
const PHOTO := """
shader_type spatial;
render_mode diffuse_burley;
void fragment() {
	vec2 p = vec2(UV.x, 1.0 - UV.y);
	float c = mix(0.08, 0.3, smoothstep(0.35, 1.0, p.y));
	float far = 0.66 + 0.08 * sin(p.x * 6.0 + 1.3) + 0.03 * sin(p.x * 17.0 + 0.2);
	float near = 0.5 + 0.09 * sin(p.x * 4.0 + 2.6) + 0.025 * sin(p.x * 23.0 + 1.0);
	c = p.y < far ? mix(0.1, 0.16, p.y) : c;
	c = p.y < near ? 0.045 : c;
	float k = clamp(p.y / 0.55, 0.0, 1.0);
	float rx = 0.5 + 0.3 * sin(k * 8.5 - 0.4) * (1.0 - k * 0.8);
	float w = mix(0.07, 0.006, k);
	float road = p.y < 0.55 ? smoothstep(w, w * 0.3, abs(p.x - rx)) : 0.0;
	c = mix(c, 0.92, road);
	float mat_w = 0.06;
	bool edge = p.x < mat_w || p.x > 1.0 - mat_w || p.y < mat_w * 1.4 || p.y > 1.0 - mat_w * 1.4;
	ALBEDO = vec3(edge ? 0.78 : c);
	ROUGHNESS = 0.4;
}
"""


## One material's share of the room: the vertices and triangles, merged into one surface.
class Part:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var uv := PackedVector2Array()
	var i := PackedInt32Array()


var props: Array = []
var mats := {}
var _parts := {}
var _prop := ""
var _prop_box := AABB()
var _prop_empty := true


## The room (a Node3D with a MeshInstance3D per material, the photograph's own).
func build() -> Node3D:
	_materials()
	_shell()
	_door_wall()
	_ceiling()
	_left_wall()
	_right_wall()
	_back_wall()
	var room := Node3D.new()
	room.name = "Room"
	for key in _parts:
		var p: Part = _parts[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = p.v
		arrays[Mesh.ARRAY_NORMAL] = p.n
		arrays[Mesh.ARRAY_TANGENT] = p.t
		arrays[Mesh.ARRAY_TEX_UV] = p.uv
		arrays[Mesh.ARRAY_INDEX] = p.i
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, mats[key])
		var mi := MeshInstance3D.new()
		mi.name = key.capitalize().replace(" ", "")
		mi.mesh = mesh
		mi.layers = 1 | LAYER
		# (the shell, the ceiling and the lights themselves throw no shadow the key light could show)
		if key in ["floor", "wall", "roof", "led", "led_door", "box_glow", "box_side", "duct"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		room.add_child(mi)
	var photo := MeshInstance3D.new()
	photo.name = "Photo"
	var q := QuadMesh.new()
	q.size = Vector2(1.1, 0.7)
	photo.mesh = q
	photo.material_override = mats.photo
	photo.position = Vector3(-3.3, 1.8, 6.948)
	photo.rotation.y = PI                          # (it faces the room: -z)
	photo.layers = 1 | LAYER
	photo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room.add_child(photo)
	return room


## How many triangles the room has (tests, the perf notes).
func triangles() -> int:
	var n := 0
	for key in _parts:
		n += (_parts[key] as Part).i.size() / 3
	return n


# ── materials ─────────────────────────────────────────────────────────────

func _materials() -> void:
	var tex: Texture2D = load(TEX % "albedo") if ResourceLoader.exists(TEX % "albedo") else null
	var nrm: Texture2D = load(TEX % "normal") if ResourceLoader.exists(TEX % "normal") else null
	var sh := Shader.new()
	sh.code = CONCRETE
	mats.floor = _concrete(sh, tex, nrm, Color("2b2b2d"), 0.35, 0.55, 0.2, 0.35, 0.15)
	mats.wall = _concrete(sh, tex, nrm, Color("1f2022"), 0.5, 0.35, 0.85, 0.1, 0.35)
	mats.box_side = _concrete(sh, tex, nrm, Color("8c8a86"), 0.6, 0.55, 0.9, 0.05, 0.3)
	mats.box_glow = _concrete(sh, tex, nrm, Color("b9b6b0"), 0.6, 0.45, 0.9, 0.0, 0.0)
	(mats.box_glow as ShaderMaterial).set_shader_parameter("glow", BOX_GLOW)
	(mats.box_glow as ShaderMaterial).set_shader_parameter("glow_energy", 2.2)
	mats.roof = _std(Color(0.012, 0.012, 0.013), 0.0, 0.9)
	mats.steel = _std(Color("121314"), 0.6, 0.45)
	mats.cabinet = _std(Color(0.055, 0.057, 0.06), 0.55, 0.32)
	mats.door = _std(Color("1b1c1e"), 0.4, 0.5)
	mats.duct = _std(Color(0.5, 0.51, 0.53), 0.9, 0.35)
	mats.wood = _std(Color(0.2, 0.115, 0.06), 0.0, 0.42)
	mats.rubber = _std(Color(0.022, 0.022, 0.024), 0.0, 0.85)
	mats.rim = _std(Color(0.8, 0.81, 0.83), 1.0, 0.25)
	mats.chrome = _std(Color(0.86, 0.86, 0.88), 1.0, 0.14)
	mats.red = _std(Color(0.42, 0.03, 0.03), 0.1, 0.45)
	mats.amber = _std(Color(0.62, 0.3, 0.05), 0.0, 0.12)
	(mats.amber as StandardMaterial3D).emission_enabled = true          # (lit through: they read as glass)
	(mats.amber as StandardMaterial3D).emission = Color(0.55, 0.22, 0.03)
	(mats.amber as StandardMaterial3D).emission_energy_multiplier = 0.25
	mats.blue = _std(Color(0.04, 0.17, 0.5), 0.0, 0.6)
	mats.helmet = _std(Color(0.86, 0.86, 0.87), 0.0, 0.12)
	(mats.helmet as StandardMaterial3D).clearcoat_enabled = true
	mats.visor = _std(Color(0.02, 0.02, 0.025), 0.4, 0.05)
	mats.carbon = _std(Color(0.035, 0.035, 0.04), 0.3, 0.28)
	(mats.carbon as StandardMaterial3D).clearcoat_enabled = true
	mats.peg = _std(Color(0.045, 0.046, 0.05), 0.2, 0.7)
	mats.led = _glow(LED, 5.0)
	mats.led_door = _glow(LED, 5.0)
	var ph := Shader.new()
	ph.code = PHOTO
	var pm := ShaderMaterial.new()
	pm.shader = ph
	mats.photo = pm


func _concrete(sh: Shader, tex: Texture2D, nrm: Texture2D, col: Color, scale: float, contrast: float, rough: float,
		rough_var: float, bump: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("nrm", nrm)
	m.set_shader_parameter("colour", col)
	m.set_shader_parameter("scale", scale)
	m.set_shader_parameter("contrast", contrast if tex else 0.0)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("rough_var", rough_var)
	m.set_shader_parameter("bump", bump if nrm else 0.0)
	return m


func _std(col: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	return m


## An LED strip: white, glowing (the bloom picks it up), lighting nothing by itself.
func _glow(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.roughness = 0.5
	return m


# ── the room ──────────────────────────────────────────────────────────────

func _shell() -> void:
	var w := HALF_W
	var d := HALF_D
	_quad("floor", Vector3(-w, 0, d), Vector3(w, 0, d), Vector3(w, 0, -d), Vector3(-w, 0, -d), Vector3.UP)
	_quad("roof", Vector3(-w, HEIGHT, -d), Vector3(w, HEIGHT, -d), Vector3(w, HEIGHT, d), Vector3(-w, HEIGHT, d), Vector3.DOWN)
	_quad("wall", Vector3(-w, 0, d), Vector3(-w, 0, -d), Vector3(-w, HEIGHT, -d), Vector3(-w, HEIGHT, d), Vector3.RIGHT)
	_quad("wall", Vector3(w, 0, -d), Vector3(w, 0, d), Vector3(w, HEIGHT, d), Vector3(w, HEIGHT, -d), Vector3.LEFT)
	_quad("wall", Vector3(-w, 0, -d), Vector3(w, 0, -d), Vector3(w, HEIGHT, -d), Vector3(-w, HEIGHT, -d), Vector3.BACK)
	_quad("wall", Vector3(w, 0, d), Vector3(-w, 0, d), Vector3(-w, HEIGHT, d), Vector3(w, HEIGHT, d), Vector3.FORWARD)
	for x in [-HALF_W, HALF_W]:                   # the corners' conduits, up to the ceiling
		for z in [-HALF_D + 0.03, HALF_D - 0.03]:
			_cyl("steel", Vector3(x * 0.91, 2.0, z), Vector3.UP, 0.02, 4.0, 8)


func _door_wall() -> void:
	_begin("door")
	var z := -HALF_D
	_box("steel", -3.8, 3.8, 0.0, 3.02, z, z + 0.035)             # behind the sections (seen in the grooves)
	for k in 5:                                                   # five sections, a groove between each
		_box("door", -3.8, 3.8, k * 0.6 + 0.007, (k + 1) * 0.6 - 0.007, z + 0.03, z + 0.07)
	_box("rubber", -3.8, 3.8, 0.0, 0.012, z + 0.03, z + 0.075)    # the bottom seal
	_box("steel", -3.86, 3.86, 3.0, 3.06, z, z + 0.08)            # the header
	_box("led_door", -3.92, -3.86, 0.0, 3.12, z, z + 0.05)        # the LED frame
	_box("led_door", 3.86, 3.92, 0.0, 3.12, z, z + 0.05)
	_box("led_door", -3.92, 3.92, 3.06, 3.12, z, z + 0.05)
	_box("steel", -3.94, 3.94, 3.12, 3.14, z, z + 0.055)          # (its aluminium channel's edge)
	_end()


func _ceiling() -> void:
	_box("steel", -HALF_W, HALF_W, 4.0, HEIGHT, 5.9, 6.4)        # the soffit over the back
	for z in [-6.0, -3.0, 0.0, 3.0]:                              # I-beams across: flanges and a web
		_box("steel", -HALF_W, HALF_W, 4.57, 4.6, z - 0.12, z + 0.12)
		_box("steel", -HALF_W, HALF_W, 4.3, 4.33, z - 0.12, z + 0.12)
		_box("steel", -HALF_W, HALF_W, 4.33, 4.57, z - 0.012, z + 0.012)
	_begin("ceiling")
	for sx in [-1.0, 1.0]:
		var x: float = sx * 3.3
		_box("steel", x - 0.05, x + 0.05, 3.7, 3.8, -HALF_D, HALF_D)           # the truss's chords
		_box("steel", x - 0.05, x + 0.05, 4.4, 4.5, -HALF_D, HALF_D)
		_box("steel", x - 0.03, x + 0.03, 4.5, HEIGHT, -0.03, 0.03)           # (hung from the roof)
		for k in 8:
			var z0: float = -HALF_D + k * 2.0
			_box("steel", x - 0.035, x + 0.035, 3.8, 4.4, z0 - 0.035 if k > 0 else z0, z0 + 0.035 if k < 7 else z0)
			if k < 7:
				var lo := Vector3(x, 3.8, z0 + (0.0 if k % 2 == 0 else 2.0))
				var hi := Vector3(x, 4.4, z0 + (2.0 if k % 2 == 0 else 0.0))
				_beam("steel", lo, hi, 0.05, 0.05)
		for z in [-5.0, -2.5, 0.0, 2.5, 5.0]:                                   # the LED fixtures under them
			_box("steel", x - 0.055, x + 0.055, 3.665, 3.7, z - 0.62, z + 0.62)
			_box("led", x - 0.035, x + 0.035, 3.655, 3.665, z - 0.6, z + 0.6)
		# the spiral duct along the wall, its seams, its hangers
		var dx: float = sx * 4.35
		_cyl("duct", Vector3(dx, 4.15, 0.0), Vector3.BACK, 0.22, HALF_D * 2.0, 18, false)
		var s := -HALF_D + 0.25
		while s < HALF_D:
			_cyl("duct", Vector3(dx, 4.15, s), Vector3.BACK, 0.228, 0.025, 18, false)
			s += 0.5
		for k in 7:
			_box("steel", dx - 0.012, dx + 0.012, 4.37, HEIGHT, -6.0 + k * 2.0 - 0.02, -6.0 + k * 2.0 + 0.02)
	_end()
	# the light box over the car: concrete sides, the underside glowing, four hangers
	_begin("light box")
	var b := LIGHT_BOX
	var lo3 := b.position
	var hi3 := b.end
	_quad("box_side", Vector3(lo3.x, lo3.y, hi3.z), Vector3(hi3.x, lo3.y, hi3.z), Vector3(hi3.x, hi3.y, hi3.z), Vector3(lo3.x, hi3.y, hi3.z), Vector3.BACK)
	_quad("box_side", Vector3(hi3.x, lo3.y, lo3.z), Vector3(lo3.x, lo3.y, lo3.z), Vector3(lo3.x, hi3.y, lo3.z), Vector3(hi3.x, hi3.y, lo3.z), Vector3.FORWARD)
	_quad("box_side", Vector3(lo3.x, lo3.y, lo3.z), Vector3(lo3.x, lo3.y, hi3.z), Vector3(lo3.x, hi3.y, hi3.z), Vector3(lo3.x, hi3.y, lo3.z), Vector3.LEFT)
	_quad("box_side", Vector3(hi3.x, lo3.y, hi3.z), Vector3(hi3.x, lo3.y, lo3.z), Vector3(hi3.x, hi3.y, lo3.z), Vector3(hi3.x, hi3.y, hi3.z), Vector3.RIGHT)
	_quad("box_side", Vector3(lo3.x, hi3.y, lo3.z), Vector3(lo3.x, hi3.y, hi3.z), Vector3(hi3.x, hi3.y, hi3.z), Vector3(hi3.x, hi3.y, lo3.z), Vector3.UP)
	_quad("box_side", Vector3(lo3.x, lo3.y, lo3.z), Vector3(lo3.x + 0.04, lo3.y, lo3.z), Vector3(lo3.x + 0.04, lo3.y, hi3.z), Vector3(lo3.x, lo3.y, hi3.z), Vector3.DOWN)
	_quad("box_side", Vector3(hi3.x - 0.04, lo3.y, lo3.z), Vector3(hi3.x, lo3.y, lo3.z), Vector3(hi3.x, lo3.y, hi3.z), Vector3(hi3.x - 0.04, lo3.y, hi3.z), Vector3.DOWN)
	_quad("box_side", Vector3(lo3.x + 0.04, lo3.y, lo3.z), Vector3(hi3.x - 0.04, lo3.y, lo3.z), Vector3(hi3.x - 0.04, lo3.y, lo3.z + 0.04), Vector3(lo3.x + 0.04, lo3.y, lo3.z + 0.04), Vector3.DOWN)
	_quad("box_side", Vector3(lo3.x + 0.04, lo3.y, hi3.z - 0.04), Vector3(hi3.x - 0.04, lo3.y, hi3.z - 0.04), Vector3(hi3.x - 0.04, lo3.y, hi3.z), Vector3(lo3.x + 0.04, lo3.y, hi3.z), Vector3.DOWN)
	_quad("box_glow", Vector3(lo3.x + 0.04, lo3.y + 0.005, lo3.z + 0.04), Vector3(hi3.x - 0.04, lo3.y + 0.005, lo3.z + 0.04),
		Vector3(hi3.x - 0.04, lo3.y + 0.005, hi3.z - 0.04), Vector3(lo3.x + 0.04, lo3.y + 0.005, hi3.z - 0.04), Vector3.DOWN)
	for cx in [lo3.x + 0.3, hi3.x - 0.3]:
		for cz in [lo3.z + 0.4, hi3.z - 0.4]:
			_cyl("steel", Vector3(cx, (hi3.y + HEIGHT) * 0.5, cz), Vector3.UP, 0.012, HEIGHT - hi3.y, 6, false)
	_end()


func _left_wall() -> void:
	var x := -HALF_W
	# the helmet shelf and two helmets, the bucket seat on its stand under them
	_begin("helmet shelf")
	_box("steel", x + 0.02, x + 0.4, 1.7, 1.74, 2.6, 4.4)
	for z in [2.8, 4.2]:
		_box("steel", x + 0.02, x + 0.05, 1.5, 1.7, z - 0.015, z + 0.015)
	for z in [3.1, 3.9]:
		_helmet(Vector3(x + 0.22, 1.74, z), Vector3.RIGHT)
	_end()
	_begin("seat")
	_box("steel", x + 0.1, x + 0.7, 0.0, 0.42, 3.15, 3.85)
	_box("steel", x + 0.08, x + 0.72, 0.42, 0.45, 3.13, 3.87)
	_seat(Vector3(x + 0.42, 0.45, 3.5))
	_end()
	# the tyre racks: four tiers of tyres standing upright (their axles along the wall);
	# in the first one's bottom tier, two silver wheels facing the room
	_begin("tyre rack A")
	_rack(-0.8, 0.3, true)
	_end()
	_begin("tyre rack B")
	_rack(-2.2, -1.1, false)
	_end()
	# the cabinet run: on casters, doors and a drawer stack, a dark wood top, the backsplash,
	# a battery charger near the door end
	_begin("cabinets")
	var z0 := -6.4
	var z1 := -3.0
	_box("cabinet", x + 0.02, x + 0.62, 0.1, 0.92, z0, z1)
	_box("wood", x, x + 0.65, 0.92, 0.96, z0 - 0.02, z1 + 0.02)
	_box("peg", x + 0.01, x + 0.05, 0.96, 2.25, z0 - 0.2, z1 + 0.1)
	var mods := [["doors", 0.85], ["doors", 0.85], ["drawers", 0.85], ["doors", 0.85]]
	var at := z1
	for m in mods:
		_fronts(Vector3(x + 0.62, 0.12, at), Vector3.RIGHT, Vector3.FORWARD, float(m[1]), 0.78, str(m[0]))
		at -= float(m[1])
	for z in [z0 + 0.06, z1 - 0.06]:
		_caster(Vector3(x + 0.1, 0.0, z))
		_caster(Vector3(x + 0.54, 0.0, z))
	_box("cabinet", x + 0.2, x + 0.5, 0.96, 1.14, -6.05, -5.7)                # the charger
	_box("chrome", x + 0.5, x + 0.505, 1.0, 1.1, -6.0, -5.75)
	_cyl("rubber", Vector3(x + 0.35, 1.16, -5.88), Vector3.BACK, 0.02, 0.28, 8)
	_end()


func _right_wall() -> void:
	var x := HALF_W
	# the two-post lift: its arms folded flat to the wall (so the camera can pass)
	_begin("lift")
	for z in [-4.7, -2.1]:
		_box("steel", x - 0.55, x - 0.2, 0.0, 2.9, z - 0.175, z + 0.175)      # the post
		_box("steel", x - 0.65, x - 0.1, 0.0, 0.02, z - 0.35, z + 0.35)        # its base plate
		_box("red", x - 0.565, x - 0.55, 0.9, 1.8, z - 0.05, z + 0.05)          # a red stripe
		_box("steel", x - 0.66, x - 0.55, 0.95, 1.25, z - 0.2, z + 0.2)         # the carriage
		for s in [-1.0, 1.0]:                                                   # its arms, folded
			var tip: float = z + s * 0.92
			_box("steel", x - 0.78, x - 0.66, 1.0, 1.08, minf(z, tip), maxf(z, tip))
			_cyl("red", Vector3(x - 0.73, 1.11, tip - s * 0.06), Vector3.UP, 0.065, 0.06, 12)
	_box("steel", x - 0.5, x - 0.25, 2.8, 2.95, -4.85, -1.95)                   # the crossbar
	_cyl("chrome", Vector3(x - 0.45, 1.3, -1.86), Vector3.UP, 0.06, 0.8, 14)     # the silver cylinder
	_cyl("chrome", Vector3(x - 0.45, 1.75, -1.86), Vector3.UP, 0.02, 0.1, 8)
	_end()
	# the rolling tool chest: five drawers, amber bottles and a blue towel on top
	_begin("tool chest")
	_box("cabinet", x - 0.62, x - 0.02, 0.1, 1.05, -1.4, -0.55)
	_fronts(Vector3(x - 0.62, 0.13, -1.4), Vector3.LEFT, Vector3.BACK, 0.85, 0.9, "drawers5")
	for z in [-1.34, -0.61]:
		_caster(Vector3(x - 0.54, 0.0, z))
		_caster(Vector3(x - 0.1, 0.0, z))
	for k in 4:
		_bottle(Vector3(x - 0.38 + (k % 2) * 0.05, 1.05, -0.62 - k * 0.12), 0.035, 0.16 + (k % 2) * 0.04)
	_box("blue", x - 0.55, x - 0.25, 1.05, 1.085, -1.35, -1.1)
	_box("blue", x - 0.53, x - 0.27, 1.085, 1.1, -1.3, -1.15)
	_end()
	# the detailing station: a low cabinet, a shelf of seven amber bottles, the hose reel
	_begin("detailing")
	_box("cabinet", x - 0.55, x - 0.02, 0.0, 0.85, 2.8, 4.2)
	_fronts(Vector3(x - 0.55, 0.04, 2.8), Vector3.LEFT, Vector3.BACK, 1.4, 0.77, "doors")
	for k in 3:
		_bottle(Vector3(x - 0.3, 0.85, 3.0 + k * 0.17), 0.035, 0.18)
	_box("steel", x - 0.3, x - 0.02, 1.45, 1.48, 2.8, 4.2)
	for z in [2.9, 4.1]:
		_box("steel", x - 0.05, x - 0.02, 1.3, 1.45, z - 0.012, z + 0.012)
	for k in 7:
		_bottle(Vector3(x - 0.16, 1.48, 4.1 - k * 0.19), 0.04, 0.2)
	_box("steel", x - 0.04, x - 0.01, 1.95, 2.25, 3.42, 3.58)                   # the reel's bracket
	_cyl("blue", Vector3(x - 0.07, 2.1, 3.5), Vector3.RIGHT, 0.28, 0.012, 22)    # its flanges
	_cyl("blue", Vector3(x - 0.19, 2.1, 3.5), Vector3.RIGHT, 0.28, 0.012, 22)
	_revolve("blue", Vector3(x - 0.13, 2.1, 3.5), Vector3.RIGHT, _ring_profile(0.17, 0.06, 0.11), 22)   # the coiled hose
	_cyl("steel", Vector3(x - 0.13, 2.1, 3.5), Vector3.RIGHT, 0.05, 0.14, 10)
	_cyl("blue", Vector3(x - 0.24, 1.75, 3.42), Vector3.UP, 0.012, 0.55, 6, false)  # the hose hanging down
	_end()


func _back_wall() -> void:
	var z := HALF_D
	# the workbench: on casters, doors and drawers, a dark wood top
	_begin("workbench")
	_box("cabinet", -1.8, 1.8, 0.08, 0.9, z - 0.63, z - 0.02)
	_box("wood", -1.85, 1.85, 0.9, 0.95, z - 0.7, z)
	var mods := [["doors", 0.72], ["doors", 0.72], ["drawers", 0.72], ["doors", 0.72], ["doors", 0.72]]
	var at := -1.8
	for m in mods:
		_fronts(Vector3(at, 0.1, z - 0.63), Vector3.FORWARD, Vector3.RIGHT, float(m[1]), 0.78, str(m[0]))
		at += float(m[1])
	for xc in [-1.72, 1.72]:
		_caster(Vector3(xc, 0.0, z - 0.1))
		_caster(Vector3(xc, 0.0, z - 0.55))
	# the pegboard of chrome tools, the helmet shelf above it
	_box("peg", -1.8, 1.8, 1.1, 2.3, z - 0.04, z)
	for k in 12:                                                  # spanners, longest first
		var len: float = 0.34 - k * 0.018
		var xc: float = -1.55 + k * 0.1
		_box("chrome", xc - 0.012, xc + 0.012, 2.12 - len, 2.12, z - 0.055, z - 0.045)
		_box("chrome", xc - 0.024, xc + 0.024, 2.08, 2.14, z - 0.055, z - 0.045)
	for k in 6:                                                   # screwdrivers
		var xc: float = 0.0 + k * 0.09
		_cyl("chrome", Vector3(xc, 1.83, z - 0.06), Vector3.UP, 0.006, 0.22, 6, false)
		_cyl("red" if k % 2 == 0 else "rubber", Vector3(xc, 2.0, z - 0.06), Vector3.UP, 0.018, 0.12, 8)
	for k in 5:                                                   # pliers and a hammer
		var xc: float = 0.75 + k * 0.17
		_box("chrome", xc - 0.02, xc + 0.02, 1.62, 1.9, z - 0.055, z - 0.045)
		_box("rubber", xc - 0.03, xc + 0.03, 1.45, 1.62, z - 0.06, z - 0.045)
	_box("chrome", -1.5, -0.6, 1.3, 1.34, z - 0.06, z - 0.045)    # a long breaker bar
	_box("chrome", -1.5, -1.1, 1.42, 1.45, z - 0.06, z - 0.045)
	_box("steel", -1.8, 1.8, 2.4, 2.44, z - 0.3, z)
	for xc in [-0.6, 0.6]:
		_helmet(Vector3(xc, 2.44, z - 0.16), Vector3.FORWARD)
	# the LED frame round the alcove
	_box("led", -1.98, -1.93, 0.0, 2.75, z - 0.04, z)
	_box("led", 1.93, 1.98, 0.0, 2.75, z - 0.04, z)
	_box("led", -1.98, 1.98, 2.7, 2.75, z - 0.04, z)
	_end()
	# the vent grille, high up
	_box("steel", -0.7, 0.7, 3.3, 3.8, z - 0.03, z)
	for k in 8:
		var y: float = 3.34 + k * 0.058
		_box("duct", -0.66, 0.66, y, y + 0.012, z - 0.05, z - 0.03)
	# the photograph's frame (the print is its own quad: build())
	_box("steel", -3.9, -2.7, 1.4, 2.2, z - 0.04, z)
	# the personnel door: black, a frame, a lever handle
	_begin("personnel door")
	_box("door", 3.5, 4.5, 0.0, 2.2, z - 0.06, z)
	_box("steel", 3.44, 3.5, 0.0, 2.26, z - 0.07, z)
	_box("steel", 4.5, 4.56, 0.0, 2.26, z - 0.07, z)
	_box("steel", 3.44, 4.56, 2.2, 2.26, z - 0.07, z)
	_box("chrome", 3.6, 3.76, 1.02, 1.045, z - 0.1, z - 0.08)
	_box("chrome", 3.6, 3.625, 0.99, 1.07, z - 0.08, z - 0.06)
	_end()


# ── furniture ─────────────────────────────────────────────────────────────

## A tyre rack against the left wall, z0..z1: posts, five shelves, casters, four tiers of
## four upright tyres (wheels: the bottom tier holds two silver wheels instead).
func _rack(z0: float, z1: float, wheels: bool) -> void:
	var x0 := -HALF_W + 0.05
	var x1 := -HALF_W + 0.6
	for xp in [x0, x1]:
		for zp in [z0, z1]:
			_box("steel", xp - 0.025, xp + 0.025, 0.1, 2.47, zp - 0.025, zp + 0.025)
			_caster(Vector3(xp, 0.0, zp))
	for t in 5:
		var y: float = 0.15 + t * 0.57
		_box("steel", x0, x1, y, y + 0.025, z0, z1)
		_box("steel", x1 - 0.02, x1 + 0.02, y + 0.025, y + 0.06, z0, z1)       # the front lip
	var w := 0.235
	var r := 0.26
	var xc := (x0 + x1) * 0.5
	for t in 4:
		var yc: float = 0.175 + t * 0.57 + r
		if t == 0 and wheels:
			for zc in [z0 + 0.3, z1 - 0.3]:
				_wheel(Vector3(x1 - 0.12, 0.175 + 0.235, zc), Vector3.RIGHT, 0.235)
			continue
		for k in 4:
			var zc: float = z0 + 0.08 + w * 0.5 + k * w
			_revolve("rubber", Vector3(xc, yc, zc), Vector3.BACK, _tyre_profile(r, w), 22)


## A tyre's cross-section: (radius, across), round the tread's shoulders, two grooves.
func _tyre_profile(r: float, w: float) -> Array:
	var h := w * 0.5
	var bead := r * 0.66
	return [Vector2(bead, -h * 0.9), Vector2(bead + 0.03, -h), Vector2(r - 0.05, -h), Vector2(r - 0.018, -h * 0.9),
		Vector2(r, -h * 0.65), Vector2(r, -h * 0.3), Vector2(r - 0.008, -h * 0.25), Vector2(r - 0.008, -h * 0.12), Vector2(r, -h * 0.07),
		Vector2(r, h * 0.07), Vector2(r - 0.008, h * 0.12), Vector2(r - 0.008, h * 0.25), Vector2(r, h * 0.3), Vector2(r, h * 0.65),
		Vector2(r - 0.018, h * 0.9), Vector2(r - 0.05, h), Vector2(bead + 0.03, h), Vector2(bead, h * 0.9)]


## A ring's cross-section (a coiled hose): round, at radius r, tube thickness t, width w.
func _ring_profile(r: float, t: float, w: float) -> Array:
	var h := w * 0.5
	return [Vector2(r - t * 0.5, -h), Vector2(r + t * 0.5, -h), Vector2(r + t * 0.6, 0.0), Vector2(r + t * 0.5, h),
		Vector2(r - t * 0.5, h), Vector2(r - t * 0.6, 0.0)]


## A silver multi-spoke wheel (no tyre), its face toward face_dir, radius r.
func _wheel(c: Vector3, face_dir: Vector3, r: float) -> void:
	var ax := face_dir.normalized()
	_cyl("rim", c - ax * 0.02, ax, r - 0.01, 0.18, 24, false)            # the barrel
	_cyl("rubber", c - ax * 0.1, ax, r - 0.012, 0.01, 24)                # (dark inside)
	_revolve("rim", c + ax * 0.07, ax, _ring_profile(r - 0.012, 0.024, 0.03), 24)   # the lip
	_cyl("rim", c + ax * 0.06, ax, 0.065, 0.05, 14)                       # the hub
	_cyl("rubber", c + ax * 0.087, ax, 0.035, 0.005, 10)                 # its cap
	var e1 := _perp(ax)
	var e2 := ax.cross(e1)
	for k in 10:                                                          # ten spokes
		var th := TAU * k / 10.0
		var d := e1 * cos(th) + e2 * sin(th)
		_beam("rim", c + ax * 0.065 + d * 0.06, c + ax * 0.05 + d * (r - 0.03), 0.028, 0.022)


## A gloss-white helmet sitting on y0, looking along face (a dark visor), a dark opening under it.
func _helmet(base: Vector3, face: Vector3) -> void:
	var c := base + Vector3.UP * 0.115
	var f := face.normalized()
	var xf := Transform3D(Basis(f, Vector3.UP, f.cross(Vector3.UP)), c)
	_ellipsoid("helmet", xf, Vector3(0.165, 0.15, 0.135), -0.85, PI * 0.5, 0.0, TAU, 18, 10)
	_ellipsoid("visor", xf, Vector3(0.169, 0.154, 0.139), -0.32, 0.3, -1.05, 1.05, 12, 4)
	_cyl("rubber", c - Vector3.UP * 0.112, Vector3.UP, 0.1, 0.01, 14)


## The carbon bucket seat, its cushion's middle at c, facing the room (+x).
func _seat(c: Vector3) -> void:
	_box("carbon", c.x - 0.25, c.x + 0.2, c.y, c.y + 0.12, c.z - 0.22, c.z + 0.22)          # the cushion
	for s in [-1.0, 1.0]:                                                                    # its side bolsters
		_box("carbon", c.x - 0.25, c.x + 0.22, c.y, c.y + 0.24, c.z + s * 0.22 - 0.04, c.z + s * 0.22 + 0.04)
	var back := Basis(Vector3.BACK, deg_to_rad(12.0))                                        # the back, leaning to the wall
	var bc := c + Vector3(-0.27, 0.45, 0.0)
	_obox("carbon", Transform3D(back, bc), Vector3(0.07, 0.82, 0.48))
	for s in [-1.0, 1.0]:
		_obox("carbon", Transform3D(back, bc + Vector3(0.06, -0.1, s * 0.25)), Vector3(0.18, 0.55, 0.06))
	_obox("carbon", Transform3D(back, bc + Vector3(0.05, 0.25, 0.0)), Vector3(0.05, 0.08, 0.5))   # the harness slots' bar


## Drawer and door fronts on a cabinet face: from corner o (bottom, at one end), out along
## n, running along `along` for len, h high. kind: "doors" (two), "drawers" (four), "drawers5".
func _fronts(o: Vector3, n: Vector3, along: Vector3, len: float, h: float, kind: String) -> void:
	var rows: Array = []
	match kind:
		"doors": rows = [[0.0, 1.0, 2]]
		"drawers": rows = [[0.0, 0.34, 1], [0.34, 0.56, 1], [0.56, 0.78, 1], [0.78, 1.0, 1]]
		"drawers5": rows = [[0.0, 0.3, 1], [0.3, 0.5, 1], [0.5, 0.67, 1], [0.67, 0.84, 1], [0.84, 1.0, 1]]
	var gap := 0.006
	for row in rows:
		var y0: float = o.y + float(row[0]) * h + gap
		var y1: float = o.y + float(row[1]) * h - gap
		var cols: int = row[2]
		for k in cols:
			var a: float = len * k / cols + gap
			var b: float = len * (k + 1) / cols - gap
			var p0 := o + along * a + Vector3.UP * (y0 - o.y)
			var p1 := o + along * b + Vector3.UP * (y1 - o.y) + n * 0.015
			_box("cabinet", minf(p0.x, p1.x), maxf(p0.x, p1.x), p0.y, p1.y, minf(p0.z, p1.z), maxf(p0.z, p1.z))
			# the handle: a bar across a drawer's top, upright by a door's middle edge
			var hc: Vector3
			var hs: Vector3
			if kind == "doors":
				var edge: float = b - 0.06 if k == 0 else a + 0.06
				hc = o + along * edge + Vector3.UP * (y1 - o.y - 0.18) + n * 0.03
				hs = along.abs() * 0.016 + Vector3.UP * 0.16 + n.abs() * 0.012
			else:
				hc = o + along * ((a + b) * 0.5) + Vector3.UP * (y1 - o.y - 0.035) + n * 0.03
				hs = along.abs() * minf(0.3, (b - a) * 0.6) + Vector3.UP * 0.014 + n.abs() * 0.012
			_box("chrome", hc.x - hs.x * 0.5, hc.x + hs.x * 0.5, hc.y - hs.y * 0.5, hc.y + hs.y * 0.5, hc.z - hs.z * 0.5, hc.z + hs.z * 0.5)


## A swivel caster under a cabinet corner (its top at 0.1 m).
func _caster(at: Vector3) -> void:
	_box("steel", at.x - 0.025, at.x + 0.025, 0.075, 0.1, at.z - 0.025, at.z + 0.025)
	_cyl("rubber", Vector3(at.x, 0.038, at.z), Vector3.RIGHT, 0.038, 0.025, 10)


## An amber detailing bottle standing on y0: its body, neck and black cap.
func _bottle(base: Vector3, r: float, h: float) -> void:
	_cyl("amber", base + Vector3.UP * h * 0.4, Vector3.UP, r, h * 0.8, 10)
	_cyl("amber", base + Vector3.UP * h * 0.87, Vector3.UP, r * 0.45, h * 0.14, 8)
	_cyl("rubber", base + Vector3.UP * h * 0.97, Vector3.UP, r * 0.5, h * 0.08, 8)


# ── geometry ──────────────────────────────────────────────────────────────

func _part(m: String) -> Part:
	if not _parts.has(m):
		_parts[m] = Part.new()
	return _parts[m]


## Furniture: what's built between _begin(name) and _end() is one prop (its box: props).
func _begin(name: String) -> void:
	_prop = name
	_prop_box = AABB()
	_prop_empty = true


func _end() -> void:
	props.append({"name": _prop, "box": _prop_box})
	_prop = ""


func _vert(p: Part, pos: Vector3, n: Vector3, tan: Vector3, uv: Vector2) -> int:
	if _prop != "":
		_prop_box = AABB(pos, Vector3.ZERO) if _prop_empty else _prop_box.expand(pos)
		_prop_empty = false
	p.v.append(pos)
	p.n.append(n)
	p.t.append_array([tan.x, tan.y, tan.z, 1.0])
	p.uv.append(uv)
	return p.v.size() - 1


## A triangle, wound so it faces the way its vertices' normals do (Godot: clockwise from the front).
func _tri(p: Part, a: int, b: int, c: int) -> void:
	var n := p.n[a] + p.n[b] + p.n[c]
	if (p.v[b] - p.v[a]).cross(p.v[c] - p.v[a]).dot(n) > 0.0:
		p.i.append_array([a, c, b])
	else:
		p.i.append_array([a, b, c])


## A flat quad, corners a b c d in order round it, facing n; its texture in metres.
func _quad(m: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	var p := _part(m)
	var tu := (b - a).normalized()
	var tv := n.cross(tu)
	var k := p.v.size()
	for q in [a, b, c, d]:
		_vert(p, q, n, tu, Vector2(q.dot(tu), -q.dot(tv)))
	_tri(p, k, k + 1, k + 2)
	_tri(p, k, k + 2, k + 3)


## A box, x0..x1, y0..y1, z0..z1 (the room's axes).
func _box(m: String, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> void:
	_obox(m, Transform3D(Basis(), Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)), Vector3(x1 - x0, y1 - y0, z1 - z0))


## A box of this size, placed and turned by xf.
func _obox(m: String, xf: Transform3D, size: Vector3) -> void:
	var h := size * 0.5
	for ax in 3:
		for s in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[ax] = s
			var u := Vector3.ZERO
			u[(ax + 1) % 3] = h[(ax + 1) % 3]
			var w := Vector3.ZERO
			w[(ax + 2) % 3] = h[(ax + 2) % 3]
			var c: Vector3 = n * h[ax]
			_quad(m, xf * (c - u - w), xf * (c + u - w), xf * (c + u + w), xf * (c - u + w), (xf.basis * n).normalized())


## A bar of w x h section from a to b.
func _beam(m: String, a: Vector3, b: Vector3, w: float, h: float) -> void:
	var z := (b - a).normalized()
	var x := (Vector3.UP if absf(z.y) < 0.9 else Vector3.RIGHT).cross(z).normalized()
	_obox(m, Transform3D(Basis(x, z.cross(x), z), (a + b) * 0.5), Vector3(w, h, a.distance_to(b)))


## A cylinder round axis ax (a unit vector) through c, radius r, length l; caps: ends closed.
func _cyl(m: String, c: Vector3, ax: Vector3, r: float, l: float, seg := 16, caps := true) -> void:
	var p := _part(m)
	var e1 := _perp(ax)
	var e2 := ax.cross(e1)
	var a := c - ax * l * 0.5
	var b := c + ax * l * 0.5
	var k := p.v.size()
	for j in seg + 1:
		var th := TAU * j / seg
		var d := e1 * cos(th) + e2 * sin(th)
		var tan := e2 * cos(th) - e1 * sin(th)
		_vert(p, a + d * r, d, tan, Vector2(th * r, 0.0))
		_vert(p, b + d * r, d, tan, Vector2(th * r, -l))
	for j in seg:
		var i := k + j * 2
		_tri(p, i, i + 2, i + 3)
		_tri(p, i, i + 3, i + 1)
	if not caps:
		return
	for end in [[a, -ax], [b, ax]]:
		var at: Vector3 = end[0]
		var n: Vector3 = end[1]
		var mid := _vert(p, at, n, e1, Vector2.ZERO)
		var first := p.v.size()
		for j in seg + 1:
			var th := TAU * j / seg
			var d := e1 * cos(th) + e2 * sin(th)
			_vert(p, at + d * r, n, e1, Vector2(d.dot(e1), d.dot(e2)) * r)
		for j in seg:
			_tri(p, mid, first + j, first + j + 1)


## A closed shape turned round axis ax through c: prof is its cross-section, (radius, along).
func _revolve(m: String, c: Vector3, ax: Vector3, prof: Array, seg: int) -> void:
	var p := _part(m)
	var e1 := _perp(ax)
	var e2 := ax.cross(e1)
	var cen := Vector2.ZERO
	for q in prof:
		cen += q
	cen /= prof.size()
	var cnt := prof.size()
	var k := p.v.size()
	for j in seg + 1:
		var th := TAU * j / seg
		var d := e1 * cos(th) + e2 * sin(th)
		var tan := e2 * cos(th) - e1 * sin(th)
		for i in cnt:
			var q: Vector2 = prof[i]
			var dir: Vector2 = prof[(i + 1) % cnt] - prof[(i - 1 + cnt) % cnt]
			var n2 := Vector2(dir.y, -dir.x).normalized()
			if n2.dot(q - cen) < 0.0:
				n2 = -n2
			_vert(p, c + ax * q.y + d * q.x, (d * n2.x + ax * n2.y).normalized(), tan, Vector2(th * q.x, -q.y))
	for j in seg:
		for i in cnt:
			var a0 := k + j * cnt + i
			var a1 := k + j * cnt + (i + 1) % cnt
			_tri(p, a0, a1, a1 + cnt)
			_tri(p, a0, a1 + cnt, a0 + cnt)


## Part of an ellipsoid (radii rad, placed by xf: its x forward), between the latitudes and
## longitudes given (radians; longitude 0 = forward).
func _ellipsoid(m: String, xf: Transform3D, rad: Vector3, lat0: float, lat1: float, lon0: float, lon1: float, seg: int, rings: int) -> void:
	var p := _part(m)
	var k := p.v.size()
	for r in rings + 1:
		var la := lerpf(lat0, lat1, float(r) / rings)
		for j in seg + 1:
			var lo := lerpf(lon0, lon1, float(j) / seg)
			var u := Vector3(cos(la) * cos(lo), sin(la), cos(la) * sin(lo))
			var pos := u * rad
			var n := Vector3(pos.x / (rad.x * rad.x), pos.y / (rad.y * rad.y), pos.z / (rad.z * rad.z)).normalized()
			_vert(p, xf * pos, (xf.basis * n).normalized(), xf.basis * Vector3(-sin(lo), 0.0, cos(lo)), Vector2(lo, la) * 0.15)
	for r in rings:
		for j in seg:
			var a := k + r * (seg + 1) + j
			var b := a + seg + 1
			_tri(p, a, a + 1, b + 1)
			_tri(p, a, b + 1, b)


## A unit vector square to ax.
static func _perp(ax: Vector3) -> Vector3:
	return (Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).cross(ax).normalized()
