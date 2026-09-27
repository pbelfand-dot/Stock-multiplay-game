extends Control
## The trading terminal seen "through" the desk CRT, like the clips: a chunky
## beige plastic bezel with a darker inner lip, curved dark glass with
## scanlines, a vignette and a soft glare, plus a green power LED.
## HUD layers it as: terminal -> glass (reads the screen) -> bezel on top.

## Screen hole in 0..1 of the viewport (terminal is anchored to the same rect).
const HOLE := Rect2(0.06, 0.055, 0.88, 0.855)
const RADIUS := 0.035          # hole corner radius, fraction of height

var glass: ColorRect
var bezel: ColorRect
var _t := 0.0
var clock: Label
var follower: Control          # the terminal: scaled along with the bezel on pop-in


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bb := BackBufferCopy.new()
	bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(bb)
	glass = _layer(GLASS)
	bezel = _layer(BEZEL)
	# the day clock sits on the bezel above the glass, like the clips
	clock = Label.new()
	clock.add_theme_font_size_override("font_size", 30)
	var f = load("res://assets/fonts/Oswald-Bold.woff2")
	if f:
		clock.add_theme_font_override("font", f)
	clock.add_theme_color_override("font_color", Color(0.97, 0.97, 0.95))
	clock.add_theme_color_override("font_outline_color", Color(0.25, 0.22, 0.16))
	clock.add_theme_constant_override("outline_size", 8)
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock.anchor_left = 0.5
	clock.anchor_right = 0.5
	clock.offset_left = -80
	clock.offset_right = 80
	clock.offset_top = 2
	add_child(clock)


func _layer(code: String) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("hole", Vector4(HOLE.position.x, HOLE.position.y, HOLE.end.x, HOLE.end.y))
	m.set_shader_parameter("radius", RADIUS)
	r.material = m
	add_child(r)
	return r


## "Lean in" when the terminal opens.
func set_time(secs: float, urgent: bool) -> void:
	secs = maxf(secs, 0.0)
	clock.text = "%02d:%02d" % [int(secs) / 60, int(secs) % 60]
	clock.add_theme_color_override("font_color", Color(1, 0.35, 0.3) if urgent else Color(0.97, 0.97, 0.95))


func pop_in() -> void:
	_t = 0.0


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / 0.22, 0.0, 1.0)
	var s := lerpf(1.08, 1.0, 1.0 - pow(1.0 - k, 3.0))
	pivot_offset = size * 0.5
	scale = Vector2(s, s)
	if follower:
		follower.pivot_offset = size * 0.5 - follower.position
		follower.scale = scale
	var asp := size.x / maxf(size.y, 1.0)
	for r in [glass, bezel]:
		(r.material as ShaderMaterial).set_shader_parameter("aspect", asp)
		(r.material as ShaderMaterial).set_shader_parameter("time", _t)


const COMMON := """
uniform vec4 hole;      // x0, y0, x1, y1 in UV
uniform float radius;
uniform float aspect = 1.777;
uniform float time = 0.0;

// signed distance to the rounded screen hole, in "height" units
float hole_sd(vec2 uv) {
	vec2 c = (hole.xy + hole.zw) * 0.5;
	vec2 h = (hole.zw - hole.xy) * 0.5;
	vec2 p = (uv - c) * vec2(aspect, 1.0);
	vec2 hh = h * vec2(aspect, 1.0) - vec2(radius);
	vec2 q = abs(p) - hh;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}
"""

const GLASS := "shader_type canvas_item;\nuniform sampler2D screen_tex : hint_screen_texture, filter_linear;\n" + COMMON + """
void fragment() {
	vec2 uv = SCREEN_UV;
	float d = hole_sd(uv);
	if (d > 0.0) { COLOR = vec4(0.0); }
	else {
		// gentle CRT bulge: pull the image toward the middle near the edges
		vec2 c = (hole.xy + hole.zw) * 0.5;
		vec2 h = (hole.zw - hole.xy) * 0.5;
		vec2 n = (uv - c) / h;
		vec2 bent = c + h * n * (1.0 - 0.018 * dot(n, n));
		vec3 col = texture(screen_tex, bent).rgb;
		// scanlines + faint aperture grille
		float scan = 0.9 + 0.1 * sin(FRAGCOORD.y * 3.14159);
		float grille = 0.97 + 0.03 * sin(FRAGCOORD.x * 2.094);
		col *= scan * grille;
		// vignette toward the rounded corners + a soft diagonal glare
		float vig = smoothstep(-0.02, -0.16, d);
		col *= mix(0.55, 1.0, vig);
		float glare = smoothstep(0.35, 0.0, length((uv - hole.xy) * vec2(aspect, 1.0) - vec2(0.35, 0.12))) * 0.07;
		col += vec3(glare);
		// slow rolling refresh band
		col += vec3(0.025) * smoothstep(0.04, 0.0, abs(fract(uv.y * 0.6 - time * 0.12) - 0.5));
		COLOR = vec4(col, 1.0);
	}
}
"""

const BEZEL := "shader_type canvas_item;\n" + COMMON + """
void fragment() {
	vec2 uv = UV;
	float d = hole_sd(uv);
	if (d <= 0.0) { COLOR = vec4(0.0); }
	else {
		vec3 beige = vec3(0.87, 0.82, 0.69);
		// plastic: lighter at the top, darker at the bottom; subtle speckle
		vec3 col = beige * mix(1.06, 0.86, uv.y);
		col *= 0.985 + 0.015 * fract(sin(dot(floor(uv * 900.0), vec2(12.9898, 78.233))) * 43758.5453);
		// inner lip: a darker recessed ring around the glass, then a highlight bevel
		float lip = smoothstep(0.0, 0.022, d);
		col = mix(beige * 0.58, col, lip);
		col += vec3(0.07) * smoothstep(0.03, 0.022, d) * smoothstep(0.016, 0.022, d);
		// outer edge falls off into darkness (we're leaning into the monitor)
		vec2 e = min(uv, 1.0 - uv) * vec2(aspect, 1.0);
		col *= mix(0.45, 1.0, smoothstep(0.0, 0.06, min(e.x, e.y)));
		// power LED + badge on the chin
		vec2 led = (uv - vec2(hole.z - 0.03, hole.w + 0.06)) * vec2(aspect, 1.0);
		float l = smoothstep(0.009, 0.006, length(led));
		col = mix(col, vec3(0.25, 1.0, 0.35), l);
		col += vec3(0.1, 0.5, 0.15) * smoothstep(0.03, 0.0, length(led)) * 0.5;
		vec2 badge = abs((uv - vec2(0.5, hole.w + 0.06)) * vec2(aspect, 1.0)) - vec2(0.09, 0.012);
		float b = smoothstep(0.003, 0.0, max(badge.x, badge.y));
		col = mix(col, beige * 0.7, b);
		COLOR = vec4(col, 1.0);
	}
}
"""
