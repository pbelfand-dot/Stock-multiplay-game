extends RefCounted
## Trees made of cards: a tapered trunk and whorls of branches, each branch two crossed
## cards showing a photographed fir sprig (alpha-cut; CC0, the twig texture of Poly Haven's
## fir_tree_01, made by tools/world_textures.py). ~400 triangles a tree. On HIGH / ULTRA the
## forest near the road is these (the low-poly cones are left for the distance).
##   Foliage.enabled()         this quality draws them (and the texture is there)
##   Foliage.tree_mesh(kind)   "pine" (a fir), "cedar" (taller, narrower, darker), "round" /
##                             "birch" (a rounder crown on a taller bare trunk); origin at
##                             the foot of the trunk, like StageBuilder._tree_mesh
##   Foliage.material()        the cards' material (alpha scissor, both sides, the sun through them)

const Graphics = preload("res://scripts/render/graphics.gd")
const ATLAS := "res://assets/textures/foliage/fir_twig.webp"
## the sprigs in the atlas (u0, v0, u1, v1): the stem at v1 (the bottom), the tip at v0
const SPRIGS := [Rect2(0.305, 0.398, 0.34, 0.379), Rect2(0.633, 0.449, 0.324, 0.383), Rect2(0.652, 0.039, 0.286, 0.332),
	Rect2(0.188, 0.047, 0.242, 0.265)]
const BARK := Rect2(0.012, 0.02, 0.18, 0.96)          # the bark strip down the atlas' left side
const CARD_DRAW := 120.0                             # m: card trees out to here (x the view distance)
const LAYER := 1 << 12                               # their render layer (the cars' reflection probes leave them out: cost)

static var _meshes := {}
static var _material: Material


static func enabled() -> bool:
	return Graphics.level() in ["high", "ultra"] and Graphics.forward() and not Graphics.headless() \
		and ResourceLoader.exists(ATLAS)


static func tree_mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var m: ArrayMesh
	match kind:
		"cedar":
			m = _build(10.5, 1.55, 0.2, 0.22, 77, Color(0.78, 0.86, 0.8), false)
		"round":
			m = _build(8.0, 2.4, 0.24, 0.38, 13, Color(1.0, 1.08, 0.92), true)
		"birch":
			m = _build(8.5, 1.9, 0.17, 0.42, 29, Color(1.05, 1.12, 0.9), true)
		_:
			m = _build(8.6, 2.3, 0.22, 0.18, 5, Color(1.0, 1.0, 1.0), false)
	_meshes[kind] = m
	return m


static func material() -> Material:
	if _material:
		return _material
	var sh := Shader.new()
	sh.code = CARD_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("atlas", load(ATLAS))
	_material = m
	return m


## A tree h m tall: branches up to reach m long, a trunk r m thick at the foot, the crown
## starting at `bare` of the height; seed: its shape; tint: x the colour; round: an ovoid
## crown (a broadleaf's outline) instead of a cone.
static func _build(h: float, reach: float, r: float, bare: float, seed: int, tint: Color, round: bool) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var centre := Vector3(0.0, h * 0.55, 0.0)
	# the trunk: six sides, tapering to a point
	var seg := 6
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var b0 := Vector3(cos(a0), 0.0, sin(a0))
		var b1 := Vector3(cos(a1), 0.0, sin(a1))
		var top := h * (0.75 if round else 0.97)
		var p := [b0 * r, b1 * r, b1 * 0.03 + Vector3.UP * top, b0 * 0.03 + Vector3.UP * top]
		var u0 := BARK.position.x + BARK.size.x * float(k) / seg
		var u1 := BARK.position.x + BARK.size.x * float(k + 1) / seg
		var uv := [Vector2(u0, BARK.end.y), Vector2(u1, BARK.end.y), Vector2(u1, BARK.position.y), Vector2(u0, BARK.position.y)]
		var n := [b0, b1, b1, b0]
		for i in [0, 1, 2, 0, 2, 3]:
			verts.append(p[i])
			norms.append(n[i])
			uvs.append(uv[i])
			cols.append(Color(0.75, 0.75, 0.75))
	# the branches: whorls up the trunk
	var y0 := h * bare
	var y := y0
	var whorl := 0
	while y < h - 0.35:
		var t := (y - y0) / (h - y0)
		var length: float
		if round:
			length = reach * sqrt(maxf(1.0 - pow(t * 2.0 - 0.85, 2.0), 0.05)) + 0.3
		else:
			length = reach * pow(1.0 - t, 0.85) + 0.35
		var count := 6 if t < 0.55 else (5 if t < 0.8 else 4)
		var turn := whorl * 2.39996                      # (the golden angle: no two whorls line up)
		for b in count:
			var az := turn + TAU * b / count + rng.randf_range(-0.3, 0.3)
			var d := Vector3(cos(az), 0.0, sin(az))
			var droop := (0.12 if round else 0.32) * rng.randf_range(0.7, 1.3)
			var base := d * r * (1.0 - t) + Vector3.UP * y
			var tip := base + (d + Vector3.DOWN * droop).normalized() * length
			var side := Vector3.UP.cross(d).normalized()
			var w := length * 0.95
			var sprig: Rect2 = SPRIGS[rng.randi() % (SPRIGS.size() if t > 0.6 else 2)]
			var lift := Vector3.UP * length * 0.12
			# the flat card (seen from above and below) and the upright one across it (seen from the side)
			_card(verts, norms, uvs, cols, base, tip + lift, side * w * 0.5, sprig, centre, tint)
			var up := (tip - base).cross(side).normalized()
			_card(verts, norms, uvs, cols, base, tip, up * w * 0.38, sprig, centre, tint)
		y += rng.randf_range(0.36, 0.5) if not round else rng.randf_range(0.45, 0.62)
		whorl += 1
	# a tuft at the top
	if not round:
		var tb := Vector3.UP * (h - 0.9)
		_card(verts, norms, uvs, cols, tb, Vector3.UP * (h + 0.3), Vector3.RIGHT * 0.45, SPRIGS[0], centre, tint)
		_card(verts, norms, uvs, cols, tb, Vector3.UP * (h + 0.3), Vector3.BACK * 0.45, SPRIGS[1], centre, tint)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## One card from the stem (at base) to the tip, `half` wide each side. Its normals point
## out of the crown (soft, round lighting, the same both sides), darker near the trunk.
static func _card(verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array, cols: PackedColorArray,
		base: Vector3, tip: Vector3, half: Vector3, sprig: Rect2, centre: Vector3, tint: Color) -> void:
	var p := [base - half * 0.45, base + half * 0.45, tip + half, tip - half]
	var uv := [Vector2(sprig.position.x, sprig.end.y), Vector2(sprig.end.x, sprig.end.y), Vector2(sprig.end.x, sprig.position.y),
		Vector2(sprig.position.x, sprig.position.y)]
	var card_n := (tip - base).cross(half).normalized()
	for i in [0, 1, 2, 0, 2, 3]:
		var q: Vector3 = p[i]
		var out := (q - centre) * Vector3(1.0, 0.6, 1.0)
		var n := (out.normalized() * 0.75 + card_n * 0.25 * signf(card_n.dot(out))).normalized()
		n = (n + Vector3.UP * 0.25).normalized()
		verts.append(q)
		norms.append(n)
		uvs.append(uv[i])
		var inner := 0.55 if i < 2 else 1.0           # (the stem end, by the trunk: in shade)
		cols.append(Color(tint.r * inner, tint.g * inner, tint.b * inner))


const CARD_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cut = 0.42;
uniform vec3 backlight_col = vec3(0.14, 0.18, 0.06);

varying vec3 vnormal;

void vertex() {
	vnormal = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec4 t = texture(atlas, UV);
	ALBEDO = t.rgb * COLOR.rgb;
	// the sprigs' needles thin out in the smaller mipmaps: hold their coverage up
	vec2 px = UV * 1024.0;
	float lod = max(log2(max(length(dFdx(px)), length(dFdy(px)))), 0.0);
	ALPHA = t.a * (1.0 + lod * 0.3);
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	NORMAL = normalize(vnormal);          // the same on both faces: a soft, round crown
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	BACKLIGHT = backlight_col;
}
"""
