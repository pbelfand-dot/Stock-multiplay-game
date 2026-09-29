extends Node
## The office TV: a live 3D "broadcast" rendered in its own little world
## (SubViewport) and put on the TV mesh. Each speaker gets a set, like the
## trailer's TRAMP-at-the-podium shot:
##   PRESIDENT  siding wall, doorway, windows, two flags, blue podium + seal
##   STREAMER   purple streaming room, LED bars, ring light, KWIK LIVE badge
##   TV         MAD MONIES studio (Jim Crammer)
##   FED        marble columns + wooden podium
##   BREAKING   newsroom desk + red BREAKING NEWS wall
## A 2D chyron ("LIVE | headline") is drawn on top.

const UI = preload("res://scripts/ui/ui_theme.gd")
const S = preload("res://scripts/art/shapes.gd")
const Character = preload("res://scripts/art/character.gd")

const SPEAKER_PRESET := {
	"TRAMP": "tramp", "TJZ": "tjz", "KIMCHEE": "kimchee", "ROARING KITTEH": "kitteh",
	"JIM CRAMMER": "crammer", "JEROME POWWW": "fed", "BREAKING": "anchor",
}

var vp: SubViewport
var studio: Node3D
var sets := {}
var anchor
var cam: Camera3D
var overlay: Control
var match_node
var ev := {}
var t := 0.0
var _talk_t := 0.0


func attach(screen: MeshInstance3D, m) -> void:
	match_node = m
	vp = SubViewport.new()
	vp.size = Vector2i(840, 460)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)
	_build_studio()
	overlay = Control.new()
	overlay.size = Vector2(840, 460)
	overlay.draw.connect(_draw_overlay)
	vp.add_child(overlay)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = vp.get_texture()
	screen.material_override = mat
	m.news.connect(_on_news)
	_show_set("")


func _on_news(e: Dictionary) -> void:
	ev = e
	_show_set(e.get("role", ""))
	var preset: String = SPEAKER_PRESET.get(e.get("speaker", ""), "anchor")
	anchor.build(Character.preset(preset) if Character.PRESETS.has(preset) else _extra_preset(preset))
	anchor.pose = "cheer" if preset in ["tramp", "crammer"] else "idle"
	_talk_t = 7.0


func _extra_preset(p: String) -> Dictionary:
	match p:
		"fed":
			return {"hair": Color(0.8, 0.8, 0.82), "hair_style": "swept", "suit": Color(0.16, 0.17, 0.22),
				"pinstripe": false, "tie": Color(0.2, 0.3, 0.6), "eye_bags": true}
		_:
			return {"hair": Color(0.3, 0.2, 0.12), "hair_style": "short", "suit": Color(0.15, 0.2, 0.4),
				"pinstripe": false, "tie": Color(0.75, 0.1, 0.12), "eye_bags": false}


func _process(delta: float) -> void:
	t += delta
	_talk_t = maxf(_talk_t - delta, 0.0)
	if anchor:
		anchor.talking = _talk_t > 0.0
	if cam:
		cam.position.x = sin(t * 0.3) * 0.05
	if overlay:
		overlay.queue_redraw()


# ------------------------------------------------------------------ studio

func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, emissive := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = S.mat(c, false, emissive)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _label(parent: Node3D, text: String, pos: Vector3, size: int, c: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = c
	l.outline_size = 0
	l.position = pos
	l.font = UI.bold()
	parent.add_child(l)
	return l


static var _flag_tex: ImageTexture
static var _flag_shader: Shader


## A proper US flag (Executive Order 10834 proportions): 13 stripes,
## canton over the top 7 stripes at 0.76 hoist x 0.4 fly, 50 stars in 9 rows
## alternating 6 and 5. Official colors: Old Glory Red / Old Glory Blue.
static func us_flag_texture() -> ImageTexture:
	if _flag_tex:
		return _flag_tex
	var H := 260
	var W := int(H * 1.9)
	var red := Color8(0xB2, 0x22, 0x34)
	var blue := Color8(0x3C, 0x3B, 0x6E)
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var stripe_h := float(H) / 13.0
	for y in H:
		var stripe := int(y / stripe_h)
		img.fill_rect(Rect2i(0, y, W, 1), red if stripe % 2 == 0 else Color.WHITE)
	var cw := int(W * 0.4)
	var ch := int(round(stripe_h * 7))
	img.fill_rect(Rect2i(0, 0, cw, ch), blue)
	# stars: diameter 0.0616 of the hoist; 9 rows, spacing cw/12 by ch/10
	var r_out := 0.0616 * H / 2.0
	var r_in := r_out * 0.382
	var star := PackedVector2Array()
	for k in 10:
		var ang := -PI / 2 + k * PI / 5
		var rr := r_out if k % 2 == 0 else r_in
		star.append(Vector2(cos(ang), sin(ang)) * rr)
	for row in 9:
		var cy := (row + 1) * ch / 10.0
		var count := 6 if row % 2 == 0 else 5
		for k in count:
			var cx := ((2 * k + 1) if row % 2 == 0 else (2 * k + 2)) * cw / 12.0
			for py in range(int(cy - r_out) - 1, int(cy + r_out) + 2):
				for px in range(int(cx - r_out) - 1, int(cx + r_out) + 2):
					if px < 0 or py < 0 or px >= W or py >= H:
						continue
					if Geometry2D.is_point_in_polygon(Vector2(px + 0.5 - cx, py + 0.5 - cy), star):
						img.set_pixel(px, py, Color.WHITE)
	img.generate_mipmaps()
	_flag_tex = ImageTexture.create_from_image(img)
	return _flag_tex


static func flag_material(mirror: bool) -> ShaderMaterial:
	if _flag_shader == null:
		_flag_shader = Shader.new()
		_flag_shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D flag_tex : source_color, filter_linear_mipmap;
uniform float mirror = 0.0;
void vertex() {
	// ripple grows from the pole (u=0) to the free end (u=1)
	float u = UV.x;
	VERTEX.z += sin(u * 9.0 - TIME * 3.2) * 0.035 * u + sin(u * 4.0 - TIME * 1.7) * 0.02 * u;
	VERTEX.y -= u * u * 0.04;
}
void fragment() {
	vec2 uv = UV;
	if (mirror > 0.5) { uv.x = 1.0 - uv.x; }
	vec3 c = texture(flag_tex, uv).rgb;
	// fold shading from the ripple
	float fold = 0.88 + 0.12 * sin(UV.x * 9.0 - TIME * 3.2 + 1.2);
	ALBEDO = c * fold;
	ROUGHNESS = 0.9;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _flag_shader
	m.set_shader_parameter("flag_tex", us_flag_texture())
	m.set_shader_parameter("mirror", 1.0 if mirror else 0.0)
	return m


## Flag on a pole. dir = +1 flies to the right of the pole, -1 to the left
## (the canton always sits at the hoist, next to the pole).
func _flag(parent: Node3D, pos: Vector3, dir: int = 1) -> void:
	var f := Node3D.new()
	f.position = pos
	parent.add_child(f)
	_box(f, Vector3(0.03, 2.3, 0.03), Vector3(0, 1.15, 0), Color(0.35, 0.25, 0.15))
	S.part(f, S.superellipsoid(0.035, 0.06, 0.035, 2.0), S.mat(Color(0.9, 0.72, 0.3), false), Vector3(0, 2.34, 0))
	_box(f, Vector3(0.28, 0.04, 0.28), Vector3(0, 0.02, 0), Color(0.25, 0.18, 0.1))
	var cloth := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.orientation = PlaneMesh.FACE_Z
	pm.size = Vector2(0.72, 0.38)
	pm.subdivide_width = 24
	pm.subdivide_depth = 8
	cloth.mesh = pm
	cloth.material_override = flag_material(false)
	# PlaneMesh UV.x runs left->right; flip the mesh for flags flying left so
	# u=0 stays at the pole (the ripple is pinned there)
	cloth.position = Vector3(dir * 0.375, 2.0, 0.0)
	if dir < 0:
		cloth.scale.x = -1.0
	f.add_child(cloth)


func _build_studio() -> void:
	studio = Node3D.new()
	vp.add_child(studio)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.22, 0.28)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 0.97, 0.94)
	env.ambient_light_energy = 0.45
	var we := WorldEnvironment.new()
	we.environment = env
	studio.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, -25, 0)
	key.light_energy = 0.75
	studio.add_child(key)
	cam = Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.position = Vector3(0, 1.55, 2.1)
	cam.fov = 38
	studio.add_child(cam)
	cam.look_at(Vector3(0, 1.5, 0))
	cam.current = true

	anchor = Character.new()
	anchor.rotation.y = PI    # face the camera (+Z)
	studio.add_child(anchor)
	anchor.build(Character.preset("tramp"))

	# PRESIDENT — the trailer's White-House-ish porch
	var pres := Node3D.new()
	studio.add_child(pres)
	sets["PRESIDENT"] = pres
	_box(pres, Vector3(8, 4, 0.1), Vector3(0, 2, -1.2), Color(0.6, 0.62, 0.68))
	for i in 16:
		_box(pres, Vector3(8, 0.02, 0.02), Vector3(0, 0.2 + i * 0.22, -1.14), Color(0.48, 0.5, 0.56))
	_box(pres, Vector3(1.1, 2.3, 0.06), Vector3(0, 1.35, -1.12), Color(0.45, 0.3, 0.18))
	_box(pres, Vector3(0.9, 2.1, 0.07), Vector3(0, 1.3, -1.1), Color(0.75, 0.77, 0.8))
	for x in [-1.7, 1.7]:
		_box(pres, Vector3(0.7, 0.9, 0.06), Vector3(x, 1.9, -1.12), Color(0.2, 0.6, 0.62))
		_box(pres, Vector3(0.04, 0.9, 0.07), Vector3(x, 1.9, -1.1), Color(0.5, 0.5, 0.55))
	_flag(pres, Vector3(-1.05, 0, -0.6), 1)
	_flag(pres, Vector3(1.05, 0, -0.6), -1)
	var podium := _box(pres, Vector3(0.9, 1.15, 0.45), Vector3(0, 0.58, 0.45), Color(0.12, 0.2, 0.55))
	S.part(podium, S.superellipsoid(0.17, 0.17, 0.02, 2.0), S.mat(Color(0.9, 0.75, 0.3), false), Vector3(0, 0.15, 0.23))
	_box(pres, Vector3(0.95, 0.05, 0.5), Vector3(0, 1.17, 0.45), Color(0.3, 0.22, 0.14))
	for x in [-0.08, 0.08]:
		_box(pres, Vector3(0.015, 0.3, 0.015), Vector3(x, 1.3, 0.3), Color(0.1, 0.1, 0.1))

	# STREAMER — purple room
	var st := Node3D.new()
	studio.add_child(st)
	sets["STREAMER"] = st
	_box(st, Vector3(8, 4, 0.1), Vector3(0, 2, -1.2), Color(0.18, 0.08, 0.3))
	for i in 5:
		_box(st, Vector3(0.08, 1.8, 0.05), Vector3(-1.6 + i * 0.8, 1.8, -1.12), Color(0.7, 0.3, 1.0), 2.0)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.35
	tm.outer_radius = 0.4
	ring.mesh = tm
	ring.material_override = S.mat(Color(1, 1, 1), false, 2.0)
	ring.position = Vector3(0, 1.55, -0.9)
	ring.rotation.x = PI / 2
	st.add_child(ring)
	_box(st, Vector3(1.6, 0.06, 0.6), Vector3(0, 0.95, 0.55), Color(0.08, 0.08, 0.09))
	_box(st, Vector3(0.5, 0.3, 0.03), Vector3(-0.6, 1.2, 0.35), Color(0.1, 0.4, 0.2), 0.6)

	# TV — MAD MONIES
	var tv := Node3D.new()
	studio.add_child(tv)
	sets["TV"] = tv
	_box(tv, Vector3(8, 4, 0.1), Vector3(0, 2, -1.2), Color(0.05, 0.2, 0.38))
	_label(tv, "MAD MONIES", Vector3(-0.9, 2.2, -1.1), 110, Color(1, 0.82, 0.1))
	for i in 6:
		_box(tv, Vector3(0.3, 0.3 + i * 0.12, 0.05), Vector3(0.6 + i * 0.35, 1.2 + i * 0.06, -1.1), Color(0.2, 0.8, 0.35), 0.8)

	# FED — columns
	var fed := Node3D.new()
	studio.add_child(fed)
	sets["FED"] = fed
	_box(fed, Vector3(8, 4, 0.1), Vector3(0, 2, -1.2), Color(0.55, 0.52, 0.45))
	for x in [-1.8, -0.9, 0.9, 1.8]:
		_box(fed, Vector3(0.35, 3.5, 0.35), Vector3(x, 1.75, -0.9), Color(0.85, 0.83, 0.76))
	_box(fed, Vector3(0.9, 1.15, 0.45), Vector3(0, 0.58, 0.45), Color(0.4, 0.26, 0.15))
	_label(fed, "FEDERAL RESERVE", Vector3(0, 2.9, -1.1), 60, Color(0.25, 0.22, 0.18))

	# BREAKING — newsroom
	var br := Node3D.new()
	studio.add_child(br)
	sets["BREAKING"] = br
	_box(br, Vector3(8, 4, 0.1), Vector3(0, 2, -1.2), Color(0.45, 0.04, 0.05))
	_label(br, "BREAKING\nNEWS", Vector3(-1.0, 1.9, -1.1), 120, Color(1, 1, 1))
	_box(br, Vector3(1.8, 0.8, 0.6), Vector3(0, 0.4, 0.5), Color(0.1, 0.12, 0.2))

	# default — network idle card
	var idle := Node3D.new()
	studio.add_child(idle)
	sets[""] = idle
	_box(idle, Vector3(8, 4, 0.1), Vector3(0, 2, -1.2), Color(0.05, 0.08, 0.15))
	_label(idle, "BAGHOLDER NEWS NETWORK", Vector3(0, 1.6, -1.1), 70, UI.GOLD)


func _show_set(role: String) -> void:
	for k in sets:
		sets[k].visible = k == role
	if not sets.has(role):
		sets[""].visible = true
	if anchor:
		anchor.visible = role != ""


# ------------------------------------------------------------------ 2D overlay

func _draw_overlay() -> void:
	var c := overlay
	var W := 840.0
	var H := 460.0
	var f := UI.bold()
	if ev.get("role", "") == "STREAMER":
		c.draw_rect(Rect2(16, 16, 150, 40), Color(0.55, 0.2, 0.95))
		c.draw_string(f, Vector2(28, 48), "KWIK LIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
		c.draw_string(f, Vector2(W - 220, 48), "%dK watching" % (40 + int(t) % 60), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
	c.draw_rect(Rect2(0, H - 80, W, 80), Color(0.03, 0.03, 0.04))
	c.draw_rect(Rect2(0, H - 80, 120, 80), Color(0.85, 0.05, 0.08))
	c.draw_string(f, Vector2(14, H - 24), "LIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 50, Color.WHITE)
	var text: String = ev.get("headline", "STAY TUNED")
	var fs := 34
	while fs > 16 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > W - 140:
		fs -= 2
	c.draw_string(f, Vector2(132, H - 28), text, HORIZONTAL_ALIGNMENT_LEFT, W - 140, fs, Color.WHITE)
