extends CompositorEffect
## The speed blur's pass (SpeedBlur sets its numbers every frame): after the transparent
## objects and before the tonemapper, two compute passes: the frame copied aside, then each
## pixel averaged along a streak: its own motion (the motion vectors, as a 1/120 s exposure
## would smear it) plus, at speed, a pull toward the focus (where the camera is heading),
## stronger toward the edges. What moves with the camera (the car, the cockpit) has no
## motion, so it stays sharp and isn't dragged into the streaks. Forward+ only (compute
## shaders on the RenderingDevice). held: a picture of a still scene (no motion to go by):
## the pull everywhere past sharp_near metres instead. Not with MSAA: its depth and motion
## vectors read as empty here (resolved or not), so the quality levels that blur use TAA /
## FXAA instead (Graphics); with MSAA on anyway (a command line) the pass stands aside.

var amount := 0.0
var focus := Vector2(0.5, 0.45)
var taps := 10
var sharp_near := 9.0
var shutter := 0.5            # x the motion vectors (a 1/120 s exposure at 60 fps)
var per_60 := 1.0             # the frame's length in 60ths of a second, inverted (motion -> per 60 fps frame)
var held := false
var near := 0.05              # the camera's clip planes (m): the depth buffer back to metres
var far := 4000.0

var _rd: RenderingDevice
var _copy_shader: RID
var _copy_pipe: RID
var _blur_shader: RID
var _blur_pipe: RID
var _sampler: RID
var _nearest: RID             # (depth and motion vectors: a depth format can't be filtered everywhere)
var _size := Vector2i.ZERO
var _debug := "--look_blur_debug" in OS.get_cmdline_user_args()    # (the depth and motion drawn instead)


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true
	needs_motion_vectors = true
	_rd = RenderingServer.get_rendering_device()
	if _rd:
		RenderingServer.call_on_render_thread(_build)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd:
		for r in [_copy_pipe, _blur_pipe, _copy_shader, _blur_shader, _sampler, _nearest]:
			if r.is_valid():
				_rd.free_rid(r)


func _build() -> void:
	_copy_shader = _compile(COPY_GLSL)
	_blur_shader = _compile(BLUR_GLSL)
	if not _copy_shader.is_valid() or not _blur_shader.is_valid():
		return
	_copy_pipe = _rd.compute_pipeline_create(_copy_shader)
	_blur_pipe = _rd.compute_pipeline_create(_blur_shader)
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = _rd.sampler_create(ss)
	var sn := RDSamplerState.new()
	sn.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sn.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_nearest = _rd.sampler_create(sn)


func _compile(code: String) -> RID:
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = code
	var spirv := _rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		push_error("speed blur: " + spirv.compile_error_compute)
		return RID()
	return _rd.shader_create_from_spirv(spirv)


func _render_callback(_type: int, render_data: RenderData) -> void:
	if amount < 0.01 or not _blur_pipe.is_valid():
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	if size != _size or not buffers.has_texture("speed_blur", "copy"):
		_size = size
		buffers.create_texture("speed_blur", "copy", RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
			RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT, RenderingDevice.TEXTURE_SAMPLES_1,
			size, 1, 1, true, false)
	var groups := Vector2i((size.x - 1) / 8 + 1, (size.y - 1) / 8 + 1)
	if buffers.get_msaa_3d() != RenderingServer.VIEWPORT_MSAA_DISABLED:
		return                                     # (no depth or motion to go by: see above)
	var scene := render_data.get_render_scene_data()
	for view in buffers.get_view_count():
		var color := buffers.get_color_layer(view, false)
		var depth := buffers.get_depth_layer(view, false)
		var velocity := buffers.get_velocity_layer(view, false)
		var copy := buffers.get_texture_slice("speed_blur", "copy", view, 0, 1, 1)
		var pc := PackedFloat32Array([size.x, size.y, focus.x, focus.y, amount, float(taps), sharp_near, float(size.x) / size.y,
			near, far, 0.0, 0.0, shutter, per_60, 1.0 if held else 0.0, 1.0 if _debug else 0.0])
		var bytes := pc.to_byte_array()
		# 1: the frame aside
		var u_src := _image_uniform(0, color)
		var u_dst := _image_uniform(1, copy)
		var set_a := UniformSetCacheRD.get_cache(_copy_shader, 0, [u_src, u_dst])
		var cl := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(cl, _copy_pipe)
		_rd.compute_list_bind_uniform_set(cl, set_a, 0)
		_rd.compute_list_set_push_constant(cl, bytes, bytes.size())
		_rd.compute_list_dispatch(cl, groups.x, groups.y, 1)
		_rd.compute_list_end()
		# 2: blurred back into the frame
		var u_out := _image_uniform(0, color)
		var u_in := _sampled_uniform(1, copy)
		var u_depth := _sampled_uniform(2, depth, _nearest)
		var u_vel := _sampled_uniform(3, velocity, _nearest)
		var set_b := UniformSetCacheRD.get_cache(_blur_shader, 0, [u_out, u_in, u_depth, u_vel])
		cl = _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(cl, _blur_pipe)
		_rd.compute_list_bind_uniform_set(cl, set_b, 0)
		_rd.compute_list_set_push_constant(cl, bytes, bytes.size())
		_rd.compute_list_dispatch(cl, groups.x, groups.y, 1)
		_rd.compute_list_end()


func _image_uniform(binding: int, tex: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(tex)
	return u


func _sampled_uniform(binding: int, tex: RID, sampler := RID()) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = binding
	u.add_id(sampler if sampler.is_valid() else _sampler)
	u.add_id(tex)
	return u


const PARAMS := """
layout(push_constant, std430) uniform Params {
	vec2 size;
	vec2 focus;
	float amount;
	float taps;
	float sharp_near;
	float aspect;
	vec4 depth_k;      // x: the camera's near, y: its far (the depth buffer is reversed: 1 at near)
	float shutter;
	float per_60;
	float held;
	float pad;
} p;
"""

const COPY_GLSL := """#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D src;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D dst;
""" + PARAMS + """
void main() {
	ivec2 at = ivec2(gl_GlobalInvocationID.xy);
	if (at.x >= int(p.size.x) || at.y >= int(p.size.y)) {
		return;
	}
	imageStore(dst, at, imageLoad(src, at));
}
"""

const BLUR_GLSL := """#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform restrict writeonly image2D dst;
layout(set = 0, binding = 1) uniform sampler2D frame;
layout(set = 0, binding = 2) uniform sampler2D depth;
layout(set = 0, binding = 3) uniform sampler2D velocity;
""" + PARAMS + """
float depth_at(vec2 uv) {
	return textureLod(depth, uv, 0.0).r;
}

vec2 motion_at(vec2 uv) {
	return textureLod(velocity, uv, 0.0).xy;
}

float dist(vec2 uv) {
	float d = depth_at(uv);
	float n = p.depth_k.x;
	float f = p.depth_k.y;
	return n * f / (d * (f - n) + n);
}

// how much a pixel moves past the camera (0: it rides with it: the car, the cockpit)
float moving(vec2 uv) {
	if (p.held > 0.5) {
		return smoothstep(p.sharp_near, p.sharp_near * 2.5, dist(uv));
	}
	float m = length(motion_at(uv)) * p.per_60;
	return smoothstep(0.0015, 0.008, m);
}

void main() {
	ivec2 at = ivec2(gl_GlobalInvocationID.xy);
	if (at.x >= int(p.size.x) || at.y >= int(p.size.y)) {
		return;
	}
	vec2 uv = (vec2(at) + 0.5) / p.size;
	float mov = moving(uv);
	if (p.pad > 0.5) {
		imageStore(dst, at, vec4(clamp(depth_at(uv) * 50.0, 0.0, 1.0), clamp(dist(uv) / 100.0, 0.0, 1.0), clamp(length(motion_at(uv)) * 200.0, 0.0, 1.0), 1.0));
		return;
	}
	if (mov < 0.01) {
		return;                                    // (the frame as it is)
	}
	vec2 dir = uv - p.focus;
	float edge = smoothstep(0.06, 0.65, length(dir * vec2(p.aspect, 1.0)));
	vec2 streak = -dir * p.amount * edge * 0.09 * mov;
	if (p.held < 0.5) {
		streak += motion_at(uv) * p.per_60 * p.shutter * mov;
	}
	if (length(streak * p.size) < 0.75) {
		return;                                    // (under a pixel)
	}
	int n = int(p.taps);
	vec3 col = vec3(0.0);
	float wsum = 0.0;
	for (int i = 0; i < n; i++) {
		float t = float(i) / float(max(n - 1, 1));
		vec2 q = uv + streak * t;
		float w = (1.0 - t * 0.6) * (i == 0 ? 1.0 : moving(q));
		col += textureLod(frame, q, 0.0).rgb * w;
		wsum += w;
	}
	imageStore(dst, at, vec4(col / max(wsum, 0.001), 1.0));
}
"""
