extends Node3D
## Cartoony dirt and gravel off the tyres when the car slides, after real
## gravel rallies (WRC Sardinia / Finland footage): lumpy "cauliflower" dust
## clouds, warm on top and dark underneath, that swell to a couple of times the
## car's height, hang for seconds drifting downwind and break up into lumps as
## they go; a low dark ribbon of gravel roosting straight back off the tyres
## plus stones fanned out to the outside, bouncing once; a burst of dust when
## it lands a jump. Drift, handbrake or a big slide = lots (mostly off the rear
## and outside wheels); a light trail behind the rear wheels at speed.
##   * the colours follow the surface: tan gravel, brown dirt, dark mud (more
##     clods, less dust), green bits off the grass, white smoke on tarmac
##   * it reads only what BOTH machines know about the car (where it is and how
##     it moves, the springs, the handbrake, the surface), so the co-driver sees
##     the same spray as the driver
##   * two MultiMeshes and a few hundred points simulated here: cheap. Puffs use
##     alpha scissor (no see-through sorting trouble) and face the camera; the
##     cloud texture's alpha is a soft "how far inside" field, so lowering a
##     puff's alpha erodes it into shrinking lumps (the cartoon dissolve)
## Lives under the car but works in world space (top_level).

const RallyCar = preload("res://scripts/vehicle/rally_car.gd")

const MAX_PUFFS := 420
const MAX_STONES := 300
const PUFF_RATE := 24.0         # puffs a second per wheel, sliding hard
const STONE_RATE := 44.0        # stones a second per wheel, sliding hard
const FRONT := 0.6              # the front tyres throw less than the rears
const SLIDE_START := 1.2        # m/s of sideways slide at the tyre before anything flies
const SLIDE_FULL := 6.0         # ... and the slide for the full spray
const GRAVITY := 15.0           # a bit more than real: snappier, cartoony arcs
## per surface: dust colour, stone colours, how much dust, how many stones
const ROOST := Color(0.36, 0.33, 0.37)   # the low ribbon of gravel thrown straight back: dark, a bit wet
const SURF := {
	"gravel": [Color(0.9, 0.78, 0.62), [Color(0.58, 0.55, 0.5), Color(0.7, 0.62, 0.48), Color(0.46, 0.43, 0.41)], 1.0, 1.0],
	"dirt": [Color(0.8, 0.64, 0.45), [Color(0.46, 0.34, 0.22), Color(0.56, 0.43, 0.29)], 1.0, 0.85],
	"mud": [Color(0.52, 0.4, 0.27), [Color(0.33, 0.24, 0.15), Color(0.41, 0.31, 0.2)], 0.45, 1.4],
	"grass": [Color(0.78, 0.8, 0.56), [Color(0.33, 0.56, 0.2), Color(0.42, 0.62, 0.24), Color(0.46, 0.37, 0.23)], 0.55, 0.8],
	"tarmac": [Color(0.92, 0.92, 0.94), [], 0.8, 0.0],
}

static var _cloud: ImageTexture     # made once, shared by every stage's car

var car: RallyCar
var intensity := [0.0, 0.0, 0.0, 0.0]    # how hard each tyre is spraying (0..1), for tests
var puffs_alive := 0
var stones_alive := 0
var puffs_made := 0                 # all-time counts (tests)
var stones_made := 0
var _puff_mm: MultiMesh
var _stone_mm: MultiMesh
var _puff_mi: MultiMeshInstance3D
var _stone_mi: MultiMeshInstance3D
# particles: parallel arrays, alive ones packed at the front
var _pp := PackedVector3Array()     # puff position
var _pv := PackedVector3Array()     # ... velocity
var _pt := PackedFloat32Array()     # ... age
var _pl := PackedFloat32Array()     # ... lifetime
var _ps := PackedFloat32Array()     # ... full size
var _pr := PackedFloat32Array()     # ... spin on screen
var _pc := PackedColorArray()
var _sp := PackedVector3Array()     # stone position
var _sv := PackedVector3Array()
var _st := PackedFloat32Array()
var _sl := PackedFloat32Array()
var _ss := PackedFloat32Array()     # size
var _sf := PackedFloat32Array()     # the ground's height where it was thrown up
var _sb := PackedInt32Array()       # bounces so far
var _sa := PackedVector3Array()     # tumble (axis x speed)
var _sc := PackedColorArray()
var _acc_p := [0.0, 0.0, 0.0, 0.0]
var _acc_s := [0.0, 0.0, 0.0, 0.0]
var _wind := Vector3.ZERO           # the dust drifts downwind (a new breeze each stage)
var _air := 0.0                     # s with no tyre on the ground
var _prev_basis := Basis()
var _w := Vector3.ZERO              # the car's spin (rad/s), from how it turned since last frame
var _started := false


func _ready() -> void:
	process_priority = 1000                       # draw after the camera has moved this frame (puffs face it)
	top_level = true
	var a := randf() * TAU
	_wind = Vector3(cos(a), 0.0, sin(a)) * randf_range(0.5, 1.1)
	global_transform = Transform3D.IDENTITY
	_pp.resize(MAX_PUFFS)
	_pv.resize(MAX_PUFFS)
	_pt.resize(MAX_PUFFS)
	_pl.resize(MAX_PUFFS)
	_ps.resize(MAX_PUFFS)
	_pr.resize(MAX_PUFFS)
	_pc.resize(MAX_PUFFS)
	_sp.resize(MAX_STONES)
	_sv.resize(MAX_STONES)
	_st.resize(MAX_STONES)
	_sl.resize(MAX_STONES)
	_ss.resize(MAX_STONES)
	_sf.resize(MAX_STONES)
	_sb.resize(MAX_STONES)
	_sa.resize(MAX_STONES)
	_sc.resize(MAX_STONES)
	# dust: a camera-facing quad with a cel-shaded cloud on it
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	pm.alpha_scissor_threshold = 0.5
	if _cloud == null:
		_cloud = _cloud_texture()
	pm.albedo_texture = _cloud
	pm.vertex_color_use_as_albedo = true
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	pm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	quad.material = pm
	_puff_mm = MultiMesh.new()
	_puff_mm.transform_format = MultiMesh.TRANSFORM_3D
	_puff_mm.use_colors = true
	_puff_mm.mesh = quad
	_puff_mm.instance_count = MAX_PUFFS
	_puff_mm.visible_instance_count = 0
	_puff_mi = MultiMeshInstance3D.new()
	_puff_mi.multimesh = _puff_mm
	_puff_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_puff_mi)
	# stones: chunky low-poly rocks, lit, flat colours
	var rock := SphereMesh.new()
	rock.radius = 0.5
	rock.height = 0.8
	rock.radial_segments = 5
	rock.rings = 2
	var sm := StandardMaterial3D.new()
	sm.vertex_color_use_as_albedo = true
	sm.roughness = 1.0
	rock.material = sm
	_stone_mm = MultiMesh.new()
	_stone_mm.transform_format = MultiMesh.TRANSFORM_3D
	_stone_mm.use_colors = true
	_stone_mm.mesh = rock
	_stone_mm.instance_count = MAX_STONES
	_stone_mm.visible_instance_count = 0
	_stone_mi = MultiMeshInstance3D.new()
	_stone_mi.multimesh = _stone_mm
	_stone_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_stone_mi)


func _physics_process(dt: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	var xf := car.global_transform
	if _started:
		# how the car turned since last tick (the co-driver's copy has no physics spin)
		var q := (xf.basis.orthonormalized() * _prev_basis.inverse()).get_rotation_quaternion()
		var ang := q.get_angle()
		var w := q.get_axis() * (wrapf(ang, -PI, PI) / dt) if ang > 1e-5 else Vector3.ZERO
		_w = _w.lerp(w, 0.5)
	_prev_basis = xf.basis.orthonormalized()
	_started = true
	_spawn(xf, dt)
	_simulate(dt)


func _process(_dt: float) -> void:
	_draw_particles()


## Each tyre: how fast it slides over the ground -> dust and stones.
func _spawn(xf: Transform3D, dt: float) -> void:
	var up := xf.basis.y
	var fwd := -xf.basis.z
	var v: Vector3 = car.linear_velocity
	var surf: Array = SURF.get(car.on_surface, SURF.gravel)
	var loose := car.on_surface in ["gravel", "dirt"]
	var hb: bool = car.handbrake_on()
	var fast := clampf((absf(car.speed) - 12.0) / 25.0, 0.0, 1.0)
	# landing a jump: a burst of dust and stones round every tyre
	var touching := 0
	for k in 4:
		if car.comp[k] > 0.01:
			touching += 1
	if touching == 0:
		_air += dt
	elif _air > 0.0:
		if _air > 0.35 and car.on_surface != "tarmac":
			_land_burst(xf, v, surf, clampf((_air - 0.35) / 0.6, 0.3, 1.0))
		_air = 0.0
	for k in 4:
		var front: bool = RallyCar.WHEELS[k][2]
		var c: float = car.comp[k]
		if c <= 0.01:                                     # in the air
			intensity[k] = 0.0
			continue
		var mount: Vector3 = xf * Vector3(RallyCar.WHEELS[k][0], 0.0, RallyCar.WHEELS[k][1])
		var contact := mount - up * (RallyCar.REST - c + RallyCar.RADIUS)
		var vc := v + _w.cross(contact - xf.origin)
		if vc.length() < 2.0:
			intensity[k] = 0.0
			continue
		var wf := fwd.rotated(up, -car.steer) if front else fwd
		var side := wf.cross(up)                          # the tyre's right
		var lat := vc.dot(side)
		var slide := absf(lat)
		if hb and not front:
			slide = maxf(slide, absf(vc.dot(wf)) * 0.8)   # locked: it slides the way it's going
		var drift := clampf((slide - SLIDE_START) / (SLIDE_FULL - SLIDE_START), 0.0, 1.0)
		var trail := fast * 0.16 if (loose and not front) else 0.0
		if front:
			drift *= FRONT
		var amount := maxf(drift, trail)
		intensity[k] = amount
		_acc_p[k] += PUFF_RATE * amount * float(surf[2]) * dt
		_acc_s[k] += STONE_RATE * drift * float(surf[3]) * dt
		var out_dir := side * signf(lat) if slide > 0.5 else Vector3.ZERO   # thrown to the outside of the slide
		while _acc_p[k] >= 1.0:
			_acc_p[k] -= 1.0
			_add_puff(contact, up, vc, out_dir, amount, surf[0])
		while _acc_s[k] >= 1.0:
			_acc_s[k] -= 1.0
			_add_stone(contact, up, wf, vc, out_dir, surf[1])


func _land_burst(xf: Transform3D, v: Vector3, surf: Array, power: float) -> void:
	for k in 4:
		var contact: Vector3 = xf * Vector3(RallyCar.WHEELS[k][0], -RallyCar.REST - RallyCar.RADIUS + 0.1, RallyCar.WHEELS[k][1])
		var out := (contact - xf.origin)
		out.y = 0.0
		out = out.normalized()
		for i in int(3 + 4 * power):
			_add_puff(contact, Vector3.UP, out * 4.0 + v * 0.3, out, power, surf[0])
		for i in int(4 + 8 * power):
			_add_stone(contact, Vector3.UP, -xf.basis.z, out * 3.0 + v * 0.5, out, surf[1])


func _add_puff(at: Vector3, up: Vector3, vc: Vector3, out_dir: Vector3, amount: float, col: Color) -> void:
	if puffs_alive >= MAX_PUFFS:
		return
	var i := puffs_alive
	puffs_alive += 1
	puffs_made += 1
	var jitter := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * 0.25
	_pp[i] = at + up * 0.2 + jitter
	_pv[i] = out_dir * absf(vc.dot(out_dir)) * randf_range(0.1, 0.22) + vc * 0.06 \
		+ Vector3.UP * randf_range(0.6, 1.3) + Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * 0.4
	_pt[i] = 0.0
	_pl[i] = randf_range(2.0, 3.4) * (0.6 + 0.4 * amount)
	_ps[i] = randf_range(1.7, 3.0) * (0.5 + 0.5 * amount)
	_pr[i] = randf_range(-PI, PI)
	var shade := randf_range(0.9, 1.06)
	_pc[i] = Color(col.r * shade, col.g * shade, col.b * shade)


func _add_stone(at: Vector3, up: Vector3, wf: Vector3, vc: Vector3, out_dir: Vector3, cols: Array) -> void:
	if stones_alive >= MAX_STONES or cols.is_empty():
		return
	var i := stones_alive
	stones_alive += 1
	stones_made += 1
	_sp[i] = at + up * 0.08 + Vector3(randf_range(-0.12, 0.12), 0.0, randf_range(-0.12, 0.12))
	var back := -wf * signf(vc.dot(wf)) if absf(vc.dot(wf)) > 0.5 else -wf    # the tyre roosts them backwards
	var roost := randf() < 0.45
	if roost:
		# the low ribbon: straight back, fast, below the bumper
		_sv[i] = back * randf_range(5.0, 9.0) + vc * 0.15 + Vector3.UP * randf_range(0.6, 1.8) \
			+ Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * 0.5
	else:
		# the fan: up and out to the outside of the slide
		_sv[i] = back * randf_range(1.0, 3.5) + out_dir * absf(vc.dot(out_dir)) * randf_range(0.3, 0.7) \
			+ vc * 0.25 + Vector3.UP * randf_range(2.0, 4.6) \
			+ Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)) * 0.8
	_st[i] = 0.0
	_sl[i] = randf_range(0.8, 1.3)
	_ss[i] = randf_range(0.08, 0.16)
	_sf[i] = at.y
	_sb[i] = 0
	_sa[i] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(6.0, 16.0)
	_sc[i] = ROOST if roost and cols.size() >= 3 else cols[randi() % cols.size()]


func _simulate(dt: float) -> void:
	var i := 0
	while i < puffs_alive:
		_pt[i] += dt
		if _pt[i] >= _pl[i]:
			_kill_puff(i)
			continue
		# dust loses its kick fast and settles to rising slowly, drifting downwind
		var v := _pv[i].lerp(_wind + Vector3.UP * 0.4, 1.0 - exp(-1.5 * dt))
		_pv[i] = v
		_pp[i] += v * dt
		i += 1
	i = 0
	while i < stones_alive:
		_st[i] += dt
		if _st[i] >= _sl[i]:
			_kill_stone(i)
			continue
		var v := _sv[i]
		v.y -= GRAVITY * dt
		var p := _sp[i] + v * dt
		if p.y < _sf[i] and v.y < 0.0:
			if _sb[i] == 0 and v.y < -2.0:                # one little bounce, then it lies there
				_sb[i] = 1
				v = Vector3(v.x * 0.55, -v.y * 0.3, v.z * 0.55)
			else:
				v = Vector3.ZERO
				_sa[i] = Vector3.ZERO
			p.y = _sf[i]
		_sv[i] = v
		_sp[i] = p
		i += 1


func _kill_puff(i: int) -> void:
	var last := puffs_alive - 1
	_pp[i] = _pp[last]
	_pv[i] = _pv[last]
	_pt[i] = _pt[last]
	_pl[i] = _pl[last]
	_ps[i] = _ps[last]
	_pr[i] = _pr[last]
	_pc[i] = _pc[last]
	puffs_alive = last


func _kill_stone(i: int) -> void:
	var last := stones_alive - 1
	_sp[i] = _sp[last]
	_sv[i] = _sv[last]
	_st[i] = _st[last]
	_sl[i] = _sl[last]
	_ss[i] = _ss[last]
	_sf[i] = _sf[last]
	_sb[i] = _sb[last]
	_sa[i] = _sa[last]
	_sc[i] = _sc[last]
	stones_alive = last


func _draw_particles() -> void:
	var cam := get_viewport().get_camera_3d()
	var face := cam.global_transform.basis if cam else Basis()
	for i in puffs_alive:
		var u := _pt[i] / _pl[i]
		# pops up fast and keeps swelling; from halfway it erodes into lumps that
		# shrink away (alpha x the texture's field against the 0.5 cut-off)
		var grow := minf(u / 0.12, 1.0)
		var s := _ps[i] * (0.3 + 0.55 * (1.0 - (1.0 - grow) * (1.0 - grow)) + 0.15 * u)
		var b := face * Basis(Vector3.BACK, _pr[i] + u * 0.5)
		_puff_mm.set_instance_transform(i, Transform3D(b.scaled_local(Vector3(s, s, s)), _pp[i]))
		var c := _pc[i]
		c.a = lerpf(1.0, 0.5, smoothstep(0.45, 1.0, u))
		_puff_mm.set_instance_color(i, c)
	_puff_mm.visible_instance_count = puffs_alive
	for i in stones_alive:
		var u := _st[i] / _sl[i]
		var s := _ss[i] * (1.0 - smoothstep(0.75, 1.0, u))
		var a := _sa[i]
		var b := Basis.IDENTITY if a.length() < 0.01 else Basis(a.normalized(), a.length() * _st[i])
		_stone_mm.set_instance_transform(i, Transform3D(b.scaled_local(Vector3(s, s * 0.8, s)), _sp[i]))
		_stone_mm.set_instance_color(i, _sc[i])
	_stone_mm.visible_instance_count = stones_alive
	if car and is_instance_valid(car):
		var box := AABB(car.global_position - Vector3(40, 15, 40), Vector3(80, 30, 80))
		_puff_mi.custom_aabb = box
		_stone_mi.custom_aabb = box


## A white cartoon cloud: round lumps like a cauliflower, lit from the top
## left (two tones with a hard edge) and dark underneath. Alpha isn't just
## in / out: it's how far inside the cloud a pixel is (0.5 at the edge, 1 at a
## lump's heart, a little lumpy noise), so a puff with less alpha shows only
## the lumps' hearts: that's how they break up.
static func _cloud_texture() -> ImageTexture:
	const N := 128
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var lumps := [[0.5, 0.6, 0.28], [0.28, 0.6, 0.19], [0.72, 0.57, 0.21], [0.42, 0.38, 0.21],
		[0.62, 0.36, 0.18], [0.5, 0.2, 0.13], [0.36, 0.78, 0.15], [0.66, 0.78, 0.15]]
	for y in N:
		for x in N:
			var p := Vector2((x + 0.5) / N, (y + 0.5) / N)
			var field := 0.0
			var lit := false
			for l in lumps:
				var c := Vector2(l[0], l[1])
				var r: float = l[2]
				var d := p.distance_to(c) / r
				field = maxf(field, 1.0 - 0.5 * d * d)
				if d < 1.0 and p.distance_to(c + Vector2(-0.32, -0.36) * r) < r * 0.8:
					lit = true
			field += (sin(p.x * 41.0) * sin(p.y * 37.0) + sin((p.x + p.y) * 23.0)) * 0.025
			var v := 1.0 if lit else 0.8
			v *= lerpf(1.0, 0.72, smoothstep(0.55, 0.85, p.y))     # the dark underside
			img.set_pixel(x, y, Color(v, v, v, clampf(field, 0.0, 1.0)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
