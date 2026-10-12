extends Node3D
## Tyre marks on sealed roads: black rubber left behind a tyre that slides, locks or
## spins up, and it stays (as on Assetto Corsa's cut-up servers, where a drift down
## the freeway leaves its lines for everyone behind). Strips of quads laid along
## each tyre's path while it's marking, a ring of MAX segments (the oldest go first);
## darker the harder the tyre works. How hard: the sideways slide DriftFx measures
## (both machines see it); on the driver's machine also the slip along the tyre (a
## lock-up, wheelspin). Lives in world space (top_level), beside DriftFx.

const MAX := 1600                    # segments kept (~400 m of four tyres sliding)
const WIDTH := 0.25                  # m, a mark's width (its edges soft: _profile)
const STEP := 0.3                    # m between a strip's joints
const START := 0.18                  # how hard a tyre has to work before it marks (0..1)
const SPIN_START := 0.22             # slip ratio (lock-up or spin) that starts a mark ...
const SPIN_FULL := 0.6               # ... and makes it as dark as it gets
const SEALED := ["asphalt", "tarmac", "wet asphalt"]

var car                              # RallyCar
var fx                               # DriftFx (its per-tyre slide intensity)
var made := 0                        # segments laid (all time: tests)
var _mm: MultiMesh
var _next := 0
var _last: Array = [null, null, null, null]   # each tyre's last joint while marking (or null)


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	var quad := PlaneMesh.new()                        # 1 x 1 on the ground, scaled per segment
	quad.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.albedo_texture = _profile()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = -1
	quad.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = quad
	_mm.instance_count = MAX
	for i in MAX:
		_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1e5, -1e4, -1e5), Vector3(2e5, 2e4, 2e5))   # (marks anywhere on the map)
	add_child(mi)


func _physics_process(_dt: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	var sealed: bool = str(car.on_surface) in SEALED
	for k in 4:
		var amount := strength(k) if sealed and car.comp[k] > 0.01 else 0.0
		if amount < START:
			_last[k] = null
			continue
		var p: Vector3 = car.contact_point(k)
		if _last[k] == null:
			_last[k] = p
			continue
		var a: Vector3 = _last[k]
		if a.distance_to(p) < STEP:
			continue
		if a.distance_to(p) > 3.0:                     # (moved: a reset, a jump)
			_last[k] = p
			continue
		_lay(a, p, car.global_transform.basis.y, amount)
		_last[k] = p


## A mark's profile across the tyre: soft edges (a hard-edged strip read as tape on the road) and
## the tread's lighter grooves. 64 x 1, built once.
static var _tex: ImageTexture

static func _profile() -> ImageTexture:
	if _tex:
		return _tex
	var img := Image.create(64, 1, false, Image.FORMAT_RGBA8)
	for x in 64:
		var u := (x + 0.5) / 64.0
		var a := smoothstep(0.0, 0.2, u) * smoothstep(1.0, 0.8, u)
		a *= 1.0 - 0.2 * smoothstep(0.5, 1.0, cos(u * TAU * 4.0 + 0.6))        # (the grooves, faintly)
		img.set_pixel(x, 0, Color(1, 1, 1, a))
	_tex = ImageTexture.create_from_image(img)
	return _tex


## How hard tyre k is working (0..1): its slide, or its lock-up / wheelspin.
func strength(k: int) -> float:
	var s: float = fx.intensity[k] / (0.6 if k < 2 else 1.0) if fx else 0.0   # (DriftFx scales the fronts down)
	if car.simulate and k < car.wheels.size():
		var sr: float = absf(car.wheels[k].slip_long)
		s = maxf(s, clampf((sr - SPIN_START) / (SPIN_FULL - SPIN_START), 0.0, 1.0))
	return clampf(s, 0.0, 1.0)


func _lay(a: Vector3, b: Vector3, up: Vector3, amount: float) -> void:
	var along := b - a
	var z := along.normalized()
	var x := z.cross(up).normalized()
	var y := x.cross(z).normalized()
	var basis := Basis(x * WIDTH, y, z * (along.length() + 0.015))     # (overlapping less: the joints showed as darker bands)
	_mm.set_instance_transform(_next, Transform3D(basis, (a + b) * 0.5 + up * 0.015))
	_mm.set_instance_color(_next, Color(0.03, 0.03, 0.03, 0.25 + 0.5 * amount))
	_next = (_next + 1) % MAX
	made += 1
