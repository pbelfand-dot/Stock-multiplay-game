extends RefCounted
## Paints the car's body model from a setup (Catalog.setup: livery, colours,
## wheels, number). The body is a Higgsfield model whose texture is a jumble of
## UV islands, so nothing can be drawn on the texture itself; instead a shader
## finds the texture's red paint and repaints it, choosing the colour from where
## on the body that point is (model units: x = back, from -0.95 at the nose; y =
## up, the window line at ~0.1, the sills at ~-0.22; z = left). Its shading
## (panel edges, grime) carries over. The race number sits in a white roundel on
## both doors. The wheels' silver rims take the wheel colour.
## The cars with models of their own (paint_model) get the same patterns and
## number, mapped from their own size onto those units, in a clear-coated paint.

const IDS := {"kestrel": 0, "plain": 1, "stripes": 2, "two_tone": 3, "comet": 4, "vortex": 5, "martello": 6,
	"tricolore": 7, "charge": 8, "quattro": 9, "goldline": 10}

static var _body_shader: Shader
static var _wheel_shader: Shader
static var _model_shader: Shader


## Paint body (MeshInstance3D) and wheels ([MeshInstance3D]) for this setup. The
## number is drawn by a little SubViewport made under `holder`.
static func paint(body: MeshInstance3D, wheels: Array, setup: Dictionary, holder: Node) -> void:
	var src: Material = body.mesh.surface_get_material(0)
	var tex: Texture2D = src.albedo_texture if src is BaseMaterial3D else null
	var m := ShaderMaterial.new()
	m.shader = _body()
	m.set_shader_parameter("tex", tex)
	var cols: Array = setup.get("colours", [])
	for i in 4:
		m.set_shader_parameter("c%d" % (i + 1), cols[i] if i < cols.size() else Color.WHITE)
	m.set_shader_parameter("livery", IDS.get(setup.get("livery", "kestrel"), 0))
	m.set_shader_parameter("number_tex", number_texture(holder, int(setup.get("number", 7))))
	body.material_override = m
	var wc: Color = setup.get("wheel_colour", Color(0.72, 0.73, 0.75))
	for w in wheels:
		var wsrc: Material = (w as MeshInstance3D).mesh.surface_get_material(0)
		var wm := ShaderMaterial.new()
		wm.shader = _wheel()
		wm.set_shader_parameter("tex", wsrc.albedo_texture if wsrc is BaseMaterial3D else null)
		wm.set_shader_parameter("rim", wc)
		(w as MeshInstance3D).material_override = wm


## The same for a car with a model of its own (tools/import_car.py): its
## "paint" surface (body, surface) gets the livery, mapped by the body's size
## (info: its parts.json: the length, the sills and the window line, the wheels),
## and the rims (materials "rim_..." on the wheels) the wheel colour. A paint part
## shaped by a normal map (a door handle: "paint_n..." surfaces) passes its map.
static func paint_model(body: MeshInstance3D, surface: int, wheels: Array, setup: Dictionary, holder: Node, info: Dictionary, normal_map: Texture2D = null) -> void:
	var m := ShaderMaterial.new()
	m.shader = _model()
	var cols: Array = setup.get("colours", [])
	for i in 4:
		m.set_shader_parameter("c%d" % (i + 1), cols[i] if i < cols.size() else Color.WHITE)
	m.set_shader_parameter("livery", IDS.get(setup.get("livery", "kestrel"), 0))
	m.set_shader_parameter("number_tex", number_texture(holder, int(setup.get("number", 7))))
	var lo: Array = info.body_min
	var hi: Array = info.body_max
	var sill: float = lo[1] if info.get("sill") == null else float(info.sill)
	var belt: float = sill + 0.45 if info.get("belt") == null else float(info.belt)
	var half_w: float = absf(info.wheels[0][0]) + info.width[0] * 0.5    # (the mirrors would make the body wider)
	m.set_shader_parameter("map_z", Vector2((lo[2] + hi[2]) * 0.5, 0.95 / maxf((hi[2] - lo[2]) * 0.5, 1.0)))
	m.set_shader_parameter("map_y", Vector2(sill, 0.32 / maxf(belt - sill, 0.15)))
	m.set_shader_parameter("map_x", 0.45 / half_w)
	var along: float = 0.95 / maxf((hi[2] - lo[2]) * 0.5, 1.0)
	m.set_shader_parameter("roundel_fix", (0.32 / maxf(belt - sill, 0.15)) / along)
	m.set_shader_parameter("metal", 0.12)
	if normal_map:                                   # (a paint part shaped by a map: a door handle)
		m.set_shader_parameter("normal_tex", normal_map)
		m.set_shader_parameter("normal_amt", 1.0)
	body.set_surface_override_material(surface, m)
	var rim := StandardMaterial3D.new()
	rim.albedo_color = setup.get("wheel_colour", Color(0.72, 0.73, 0.75))
	rim.metallic = 0.7
	rim.roughness = 0.3
	for w in wheels:
		var mi := w as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var sm := mi.mesh.surface_get_material(i)
			if sm and sm.resource_name.begins_with("rim_"):
				mi.set_surface_override_material(i, rim)


## The number, black on a clear background, rendered once into a texture.
static func number_texture(holder: Node, number: int) -> Texture2D:
	var old := holder.get_node_or_null("NumberViewport")
	if old:
		holder.remove_child(old)
		old.queue_free()
	var vp := SubViewport.new()
	vp.name = "NumberViewport"
	vp.size = Vector2i(128, 128)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var l := Label.new()
	l.text = str(number)
	l.add_theme_font_override("font", load("res://assets/fonts/Oswald-Bold.woff2"))
	l.add_theme_font_size_override("font_size", 92 if number < 10 else 78)
	l.add_theme_color_override("font_color", Color(0.04, 0.04, 0.05))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(128, 128)
	l.position = Vector2(0, -4)
	vp.add_child(l)
	holder.add_child(vp)
	return vp.get_texture()


const _UNIFORMS := """uniform sampler2D number_tex : source_color, filter_linear;
uniform vec4 c1 : source_color = vec4(0.78, 0.12, 0.1, 1.0);
uniform vec4 c2 : source_color = vec4(1.0);
uniform vec4 c3 : source_color = vec4(0.08, 0.08, 0.09, 1.0);
uniform vec4 c4 : source_color = vec4(1.0);
uniform int livery = 0;
uniform vec2 roundel = vec2(-0.03, -0.07);      // on the doors (x, y)
uniform float roundel_r = 0.092;

"""
const _VARYINGS := """varying vec3 mp;
varying vec3 mn;

"""
const _PATTERN := """float band(float v, float a, float b) {
	return step(a, v) * step(v, b);
}

vec3 pattern(vec3 p, vec3 n) {
	float side = smoothstep(0.45, 0.7, abs(n.z));           // a side panel
	float az = abs(p.z);
	vec3 col = c1.rgb;
	if (livery == 2) {                                       // twin stripes, nose to tail over the top
		col = mix(col, c2.rgb, band(az, 0.035, 0.1) * (1.0 - side));
	} else if (livery == 3) {                                // two-tone, a pinstripe between
		float h = p.y - (-0.06 + p.x * 0.02);
		col = h < 0.0 ? c2.rgb : c1.rgb;
		col = mix(col, c3.rgb, step(abs(h), 0.011));
	} else if (livery == 4) {                                // comet: a gold band low on the sides,
		float h = p.y - (-0.165 + max(p.x - 0.25, 0.0) * 0.35);    // kicking up behind the doors
		col = mix(col, c2.rgb, band(h, 0.0, 0.05) * side);
		col = mix(col, c3.rgb, band(h, 0.05, 0.062) * side);
		col = mix(col, c2.rgb, band(az, 0.0, 0.03) * step(0.6, n.y) * step(p.x, -0.3));   // a stripe up the bonnet
	} else if (livery == 5) {                                // vortex: red below a rising line, black slashes
		float h = p.y - (-0.07 + (p.x + 0.95) * 0.04);
		if (h < 0.0) {
			col = c2.rgb;
			float slash = fract((p.x * 1.0 - p.y * 0.9) * 7.0);
			col = mix(col, c3.rgb, step(0.62, slash) * side * band(p.x, -0.35, 0.3));
		}
		col = mix(col, c3.rgb, band(az, 0.0, 0.07) * step(0.6, n.y) * step(p.x, -0.32));    // black bonnet
	} else if (livery == 6) {                                // martello: navy, sky, red along the sides
		float h = p.y;
		vec3 s = col;
		s = mix(s, c2.rgb, band(h, 0.02, 0.075));
		s = mix(s, c3.rgb, band(h, -0.025, 0.02));
		s = mix(s, c4.rgb, band(h, -0.045, -0.025));
		col = mix(col, s, side);
		vec3 t = col;                                         // ...and over the bonnet and roof
		t = mix(t, c2.rgb, band(az, 0.0, 0.06));
		t = mix(t, c3.rgb, band(az, 0.06, 0.1));
		t = mix(t, c4.rgb, band(az, 0.1, 0.12));
		col = mix(col, t, (1.0 - side) * step(0.5, n.y));
	} else if (livery == 7) {                                // tricolore: three slanted bands, low at the back, up the nose
		float h = p.y - (-0.2 + (0.95 - p.x) * 0.06);
		vec3 s = col;
		s = mix(s, c2.rgb, band(h, 0.0, 0.035));
		s = mix(s, c3.rgb, band(h, 0.035, 0.07));
		s = mix(s, c4.rgb, band(h, 0.07, 0.105));
		col = mix(col, s, max(side, step(0.5, -n.x)));
	} else if (livery == 8) {                                // charge: a gold sun on the back of the side, a red slash through it
		vec2 q = vec2(p.x - 0.5, p.y + 0.06);
		col = mix(col, c2.rgb, step(length(q), 0.19) * side);
		float slash = abs(p.y - (-0.06 - (p.x - 0.5) * 0.55));
		col = mix(col, c3.rgb, step(slash, 0.03) * band(p.x, 0.12, 0.9) * side);
		col = mix(col, c2.rgb, band(az, 0.0, 0.025) * step(0.6, n.y));             // a gold line over the top
	} else if (livery == 9) {                                // quattro: yellow skirts, a red line above them
		float h = p.y - (-0.12 + p.x * 0.015);
		col = h < 0.0 ? c2.rgb : col;
		col = mix(col, c3.rgb, band(h, 0.0, 0.018));
		col = mix(col, c2.rgb, band(az, 0.0, 0.05) * step(0.6, n.y) * step(p.x, -0.3));   // and up the bonnet
	} else if (livery == 10) {                               // goldline: dark paint, gold and red pinstripes
		col = mix(col, c2.rgb, band(p.y, 0.0, 0.014) * side);
		col = mix(col, c3.rgb, band(p.y, -0.03, -0.018) * side);
	}
	return col;
}

"""


static func _body() -> Shader:
	if _body_shader:
		return _body_shader
	_body_shader = Shader.new()
	_body_shader.code = "shader_type spatial;\nuniform sampler2D tex : source_color, filter_linear_mipmap;\n" \
		+ _UNIFORMS + _VARYINGS + """
void vertex() {
	mp = VERTEX;
	mn = NORMAL;
}

// the model's red paint (not the white stripes, the glass, the trim, the tyres)
float paint_mask(vec3 c) {
	float hi = max(c.r, max(c.g, c.b));
	float lo = min(c.r, min(c.g, c.b));
	float sat = (hi - lo) / max(hi, 0.001);
	return step(max(c.g, c.b) * 1.7, c.r) * smoothstep(0.35, 0.55, sat) * smoothstep(0.12, 0.25, hi);
}

""" + _PATTERN + """
void fragment() {
	vec3 o = texture(tex, UV).rgb;
	float m = paint_mask(o);
	float shade = clamp(o.r / 0.78, 0.35, 1.25);           // the paint's own light and shade
	vec3 col = pattern(mp, mn) * shade;
	vec3 albedo = mix(o, col, m);
	// the race number in its roundel, on both doors
	float side = smoothstep(0.6, 0.8, abs(mn.z));
	vec2 q = vec2(mp.x - roundel.x, mp.y - roundel.y);
	float r = length(q);
	if (side > 0.0 && r < roundel_r) {
		vec2 uv = vec2((mp.z > 0.0 ? q.x : -q.x) / (2.0 * roundel_r) + 0.5, 0.5 - q.y / (2.0 * roundel_r));
		vec3 disc = mix(vec3(0.95), vec3(0.04), smoothstep(roundel_r * 0.9, roundel_r * 0.94, r));
		disc = mix(disc, vec3(0.04), texture(number_tex, uv).a);
		albedo = mix(albedo, disc, side);
		m = max(m, side);
	}
	ALBEDO = albedo;
	ROUGHNESS = mix(0.85, 0.42, m);                          // paint shines a little, the rest doesn't
	SPECULAR = 0.5;
}
"""
	return _body_shader


## The model cars' paint: the same patterns and number, mapped from the body's
## own metres (map_*: see paint_model) onto the Higgsfield body's units; no
## texture under it, a clear coat over it.
static func _model() -> Shader:
	if _model_shader:
		return _model_shader
	_model_shader = Shader.new()
	_model_shader.code = """shader_type spatial;
uniform vec2 map_z = vec2(0.0, 0.43);            // the body's middle along it (m), and m -> units
uniform vec2 map_y = vec2(0.3, 0.7);             // its sills' height (m), and m -> units
uniform float map_x = 0.5;                       // m -> units across
uniform float metal = 0.1;
uniform float roundel_fix = 1.0;                 // m -> units up over along: the number disc round in metres
uniform sampler2D normal_tex : hint_normal;
uniform float normal_amt = 0.0;                  // 1: the part's normal map (a door handle) shapes it
""" + _UNIFORMS + _VARYINGS + """
void vertex() {
	// the model: x right, y up, -z forward (m); the Higgsfield body: x back, y up, z left
	mp = vec3((VERTEX.z - map_z.x) * map_z.y, -0.22 + (VERTEX.y - map_y.x) * map_y.y, -VERTEX.x * map_x);
	mn = vec3(NORMAL.z, NORMAL.y, -NORMAL.x);
}
""" + _PATTERN + """
void fragment() {
	vec3 albedo = pattern(mp, mn);
	float side = smoothstep(0.6, 0.8, abs(mn.z));
	vec2 q = vec2(mp.x - roundel.x, (mp.y - roundel.y) / roundel_fix);
	float r = length(q);
	if (side > 0.0 && r < roundel_r) {
		vec2 uv = vec2((mp.z > 0.0 ? q.x : -q.x) / (2.0 * roundel_r) + 0.5, 0.5 - q.y / (2.0 * roundel_r));
		vec3 disc = mix(vec3(0.95), vec3(0.04), smoothstep(roundel_r * 0.9, roundel_r * 0.94, r));
		disc = mix(disc, vec3(0.04), texture(number_tex, uv).a);
		albedo = mix(albedo, disc, side);
	}
	ALBEDO = albedo;
	if (normal_amt > 0.0) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_amt;
	}
	METALLIC = metal;
	ROUGHNESS = 0.32;
	SPECULAR = 0.5;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.05;
}
"""
	return _model_shader


static func _wheel() -> Shader:
	if _wheel_shader:
		return _wheel_shader
	_wheel_shader = Shader.new()
	_wheel_shader.code = """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 rim : source_color = vec4(0.72, 0.73, 0.75, 1.0);

void fragment() {
	vec3 o = texture(tex, UV).rgb;
	float hi = max(o.r, max(o.g, o.b));
	float lo = min(o.r, min(o.g, o.b));
	float m = step(hi - lo, 0.12) * smoothstep(0.42, 0.6, hi);     // the light grey rim
	ALBEDO = mix(o, rim.rgb * clamp(hi / 0.82, 0.5, 1.2), m);
	ROUGHNESS = mix(0.9, 0.35, m);
	METALLIC = m * 0.3;
}
"""
	return _wheel_shader
