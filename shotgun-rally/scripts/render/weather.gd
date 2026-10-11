extends Node3D
## Rain for Track Mode's WET weather (Modes.TRACK_WEATHER): falling streaks round the camera, the
## spray thrown up behind every car at speed, and the rain's hiss. The road's wet look is
## WorldMaterials.wet's (set before the circuit is built); the tyres' grip on it is RaceSim's.
##
##   * rain: one MultiMesh of thin quads, every drop placed and moved by its shader (no work on the
##     CPU): each falls at ~9 m/s with the wind, wraps round a box that follows the camera, and is
##     drawn as a streak along its speed against the camera's (driving into it, the rain comes at
##     you); drops right by the camera (inside the car) and at the box's edge fade out;
##   * spray: a soft grey puff off each rear tyre at speed (none below ~30 km/h, the most past
##     ~200), rising and swelling behind the car into a cloud you drive through, for every car near
##     the camera (cars: a Callable returning the Node3Ds; their speed is worked out from where they
##     were, so it works for the field's far cars too);
##   * sound: a looping hiss (filtered noise made here, no recording).
## The drops and puffs scale with the graphics quality (Graphics.level).

const Graphics = preload("res://scripts/render/graphics.gd")
const WorldMaterials = preload("res://scripts/render/world_materials.gd")

const DROPS := {"low": 900, "medium": 1800, "high": 3000, "ultra": 4000}
const BOX := Vector3(40.0, 24.0, 40.0)   # m: the box of rain round the camera
const FALL := 9.0                        # m/s: a raindrop's terminal speed (~2 mm drops: 6.5-9 m/s)
const MAX_PUFFS := 700
const SPRAY_FROM := 8.0                  # m/s: no spray below this (~30 km/h) ...
const SPRAY_FULL := 55.0                 # ... the most past this
const SPRAY_RATE := 40.0                 # puffs a second off each rear tyre at the most
const SPRAY_NEAR := 160.0                # m: cars farther from the camera throw none

var amount := 1.0                        # how hard it rains / how wet (0..1)
var cars: Callable                       # -> Array of Node3D (every car in the session)
var wind := Vector3.ZERO
var drops := 0                           # (tests) how many drops there are
var puffs_alive := 0
var puffs_made := 0                      # (tests) all-time
var _rain_mi: MultiMeshInstance3D
var _rain_mat: ShaderMaterial
var _puff_mm: MultiMesh
var _puff_mi: MultiMeshInstance3D
var _pp := PackedVector3Array()          # puff position, velocity, age, lifetime, size
var _pv := PackedVector3Array()
var _pt := PackedFloat32Array()
var _pl := PackedFloat32Array()
var _ps := PackedFloat32Array()
var _acc := {}                           # car -> puffs owed (fractions)
var _last := {}                          # car -> [position, velocity]
var _cam_prev := Vector3.ZERO
var _cam_v := Vector3.ZERO
var _sound: AudioStreamPlayer


func setup(how_wet: float, seed_value := 0) -> void:
	amount = clampf(how_wet, 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7 + 11
	var a := rng.randf() * TAU
	wind = Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.8, 2.5)


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	process_priority = 1000                  # after the camera has moved this frame
	_build_rain()
	_build_spray()
	_build_sound()


## The rain: the drops' random places in the box (custom data), the shader does the rest.
func _build_rain() -> void:
	drops = int(DROPS.get(Graphics.level(), 1800) * lerpf(0.5, 1.0, amount))
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_rain_mat = ShaderMaterial.new()
	_rain_mat.shader = _rain_shader()
	_rain_mat.set_shader_parameter("box", BOX)
	quad.material = _rain_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = drops
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in drops:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	_rain_mi = MultiMeshInstance3D.new()
	_rain_mi.name = "Rain"
	_rain_mi.multimesh = mm
	_rain_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_mi.custom_aabb = AABB(Vector3(-1e5, -1e4, -1e5), Vector3(2e5, 2e4, 2e5))   # (it's always round the camera)
	_rain_mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_rain_mi)


static func _rain_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
uniform vec3 cam_pos;
uniform vec3 cam_vel;                    // the camera's own speed (m/s): driving into the rain leans it at you
uniform vec3 box = vec3(40.0, 24.0, 40.0);
uniform vec3 wind = vec3(0.0);
uniform float fall = 9.0;
uniform float exposure = 0.04;           // s: how long a streak a drop leaves (a camera's shutter)
uniform float width = 0.02;              // m (wider than a drop: a streak reads on screen, ~2 px at 10 m)
uniform vec4 colour : source_color = vec4(0.85, 0.88, 0.95, 0.5);
varying float fade;

void vertex() {
	vec3 vw = vec3(wind.x, -fall, wind.z);
	float t = TIME * (0.85 + 0.3 * INSTANCE_CUSTOM.w);
	vec3 lo = cam_pos - box * 0.5;
	vec3 p = lo + mod(INSTANCE_CUSTOM.xyz * box + vw * t - lo, box);
	vec3 rel = vw * (0.85 + 0.3 * INSTANCE_CUSTOM.w) - cam_vel;
	float sp = max(length(rel), 0.01);
	vec3 axis = rel / sp;
	float len = clamp(sp * exposure, 0.25, 3.0);
	vec3 to_cam = cam_pos - p;
	float dist = length(to_cam);
	vec3 side = normalize(cross(axis, to_cam / max(dist, 0.01)) + vec3(1e-4, 0.0, 0.0));
	VERTEX = p + axis * VERTEX.y * len + side * VERTEX.x * width * (1.0 + dist * 0.05);
	vec3 q = abs(p - cam_pos) / (box * 0.5);
	fade = smoothstep(1.2, 2.6, dist) * (1.0 - smoothstep(0.75, 1.0, max(q.x, max(q.y, q.z))));
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	ALBEDO = colour.rgb;
	ALPHA = colour.a * fade * across * (0.4 + 0.6 * sin(UV.y * 3.14159));
}
"""
	return sh


## The spray's puffs: soft round camera-facing quads.
func _build_spray() -> void:
	_pp.resize(MAX_PUFFS)
	_pv.resize(MAX_PUFFS)
	_pt.resize(MAX_PUFFS)
	_pl.resize(MAX_PUFFS)
	_ps.resize(MAX_PUFFS)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	m.albedo_texture = gt
	quad.material = m
	_puff_mm = MultiMesh.new()
	_puff_mm.transform_format = MultiMesh.TRANSFORM_3D
	_puff_mm.use_colors = true
	_puff_mm.mesh = quad
	_puff_mm.instance_count = MAX_PUFFS
	_puff_mm.visible_instance_count = 0
	_puff_mi = MultiMeshInstance3D.new()
	_puff_mi.name = "Spray"
	_puff_mi.multimesh = _puff_mm
	_puff_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_puff_mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # (drawn each frame, facing the camera)
	add_child(_puff_mi)


## The rain's hiss: a couple of seconds of noise, filtered soft (pink-ish: more rumble than
## fizz), looping.
func _build_sound() -> void:
	var rate := 22050
	var n := rate * 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		b0 = 0.997 * b0 + 0.029 * w
		b1 = 0.985 * b1 + 0.032 * w
		b2 = 0.95 * b2 + 0.048 * w
		var x := (b0 + b1 + b2 + w * 0.06) * 0.9
		# (cross-fade the loop's ends so it doesn't click)
		var edge := minf(float(i), float(n - 1 - i)) / 2000.0
		x *= clampf(edge, 0.0, 1.0)
		data.encode_s16(i * 2, int(clampf(x, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	_sound = AudioStreamPlayer.new()
	_sound.name = "RainSound"
	_sound.stream = wav
	_sound.volume_db = linear_to_db(0.12 + 0.18 * amount)
	_sound.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(_sound)
	if not DisplayServer.get_name() == "headless":
		_sound.play()


func _physics_process(dt: float) -> void:
	if cars.is_valid():
		_spray(dt)
	_simulate(dt)


func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	if dt > 0.0:
		var v := (cp - _cam_prev) / dt
		_cam_v = _cam_v.lerp(v if v.length() < 120.0 else Vector3.ZERO, 0.2)   # (a camera cut: no lean)
	_cam_prev = cp
	_rain_mat.set_shader_parameter("cam_pos", cp)
	_rain_mat.set_shader_parameter("cam_vel", _cam_v)
	_rain_mat.set_shader_parameter("wind", wind)
	var lit := 1.0 - 0.65 * WorldMaterials.night_amount         # (unlit at night: the drops only catch the lights)
	_rain_mat.set_shader_parameter("colour", Color(0.85 * lit, 0.88 * lit, 0.95 * lit, 0.5 * lerpf(0.6, 1.0, amount)))
	_draw(cam)


## Puffs off the rear tyres of every car near the camera, by its speed.
func _spray(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var cp := cam.global_position if cam else Vector3.ZERO
	var seen := {}
	for c in cars.call():
		if not is_instance_valid(c) or not (c is Node3D) or not c.is_inside_tree() or not c.visible:
			continue
		var xf: Transform3D = c.global_transform
		var key: int = c.get_instance_id()
		seen[key] = true
		var prev: Array = _last.get(key, [xf.origin, Vector3.ZERO])
		var vel: Vector3 = (xf.origin - prev[0]) / maxf(dt, 1e-4)
		if vel.length() > 150.0:
			vel = prev[1]                       # (put somewhere else: not a speed)
		_last[key] = [xf.origin, vel]
		if xf.origin.distance_to(cp) > SPRAY_NEAR:
			continue
		var k := clampf((vel.length() - SPRAY_FROM) / (SPRAY_FULL - SPRAY_FROM), 0.0, 1.0)
		if k <= 0.0:
			continue
		var owed: float = _acc.get(key, 0.0) + SPRAY_RATE * 2.0 * k * amount * dt
		var back := xf.basis.z.normalized()     # (a car faces -Z)
		var right := xf.basis.x.normalized()
		var up := xf.basis.y.normalized()
		var flip := 0
		while owed >= 1.0:
			owed -= 1.0
			flip += 1
			var at := xf.origin + back * 1.9 + right * (0.8 if flip % 2 == 0 else -0.8) + up * 0.25
			_add_puff(at, vel, back, k)
		_acc[key] = owed
	for key in _last.keys():
		if not seen.has(key):
			_last.erase(key)
			_acc.erase(key)


func _add_puff(at: Vector3, vel: Vector3, back: Vector3, k: float) -> void:
	if puffs_alive >= MAX_PUFFS:
		return
	var i := puffs_alive
	puffs_alive += 1
	puffs_made += 1
	_pp[i] = at + Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2))
	# thrown up off the tread and left behind: it keeps a little of the car's speed, the air stops it
	_pv[i] = vel * randf_range(0.25, 0.45) + back * randf_range(1.0, 3.0) + Vector3.UP * randf_range(0.8, 2.2) \
		+ Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * 0.6
	_pt[i] = 0.0
	_pl[i] = randf_range(1.0, 1.8) * (0.7 + 0.3 * k)
	_ps[i] = randf_range(2.0, 3.4) * (0.6 + 0.4 * k)


func _simulate(dt: float) -> void:
	var i := 0
	var drag := exp(-2.2 * dt)
	while i < puffs_alive:
		_pt[i] += dt
		if _pt[i] >= _pl[i]:
			var last := puffs_alive - 1
			_pp[i] = _pp[last]
			_pv[i] = _pv[last]
			_pt[i] = _pt[last]
			_pl[i] = _pl[last]
			_ps[i] = _ps[last]
			puffs_alive -= 1
			continue
		_pv[i] = (_pv[i] - wind) * drag + wind + Vector3.DOWN * 0.6 * dt   # (the air stops it, the breeze takes it)
		_pp[i] += _pv[i] * dt
		i += 1


func _draw(cam: Camera3D) -> void:
	var face := cam.global_transform.basis
	var lit := 1.0 - 0.6 * WorldMaterials.night_amount
	for i in puffs_alive:
		var u := _pt[i] / _pl[i]
		var s := _ps[i] * (0.45 + 1.1 * u)
		_puff_mm.set_instance_transform(i, Transform3D(face.scaled_local(Vector3(s, s, s)), _pp[i]))
		_puff_mm.set_instance_color(i, Color(0.82 * lit, 0.84 * lit, 0.87 * lit, 0.5 * (1.0 - u) * (1.0 - u) * smoothstep(0.0, 0.08, u)))
	_puff_mm.visible_instance_count = puffs_alive
	_puff_mi.custom_aabb = AABB(cam.global_position - Vector3(200, 60, 200), Vector3(400, 120, 400))
