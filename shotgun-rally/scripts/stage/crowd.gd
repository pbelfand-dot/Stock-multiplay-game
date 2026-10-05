extends Node3D
## A group of spectators on the bank beside the road (StageBuilder makes them):
## low-poly people in bright jackets and hats, some waving flags, behind a
## red-and-white tape. They stand and fidget; when the car (the camera) comes
## near they jump and cheer, and they keep cheering a moment after it's gone.
## Bodies, heads, hats, flag poles and flags are one MultiMesh each: only the
## nearby groups move, the rest cost nothing.

const NEAR := 75.0              # m: closer than this they move at all
const CHEER := 30.0             # m: closer than this they jump and cheer

var people: Array = []          # [{xf: Transform3D (stood on the ground, facing the road), phase, flag: bool, hat: bool}]
var _mm := {}                   # part -> MultiMesh
var _cheer := 0.0               # 0..1, how excited they are (rises fast, settles slowly)
var _t := 0.0


## Build the meshes for `people` (set them first).
func build(jackets: Array, skins: Array, hats: Array, flags: Array, rng: RandomNumberGenerator) -> void:
	var parts := {
		"body": _capsule(0.2, 1.15),
		"head": _sphere(0.13, 0.26),
		"hat": _sphere(0.15, 0.12),
		"pole": _cylinder(0.015, 1.5),
		"flag": _flag_mesh(),
	}
	for part in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = parts[part]
		var n := 0
		for p in people:
			if part == "hat" and not p.hat:
				continue
			if (part == "pole" or part == "flag") and not p.flag:
				continue
			n += 1
		mm.instance_count = n
		var mi := MultiMeshInstance3D.new()
		mi.name = part.capitalize()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if part in ["hat", "pole", "flag"] else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visibility_range_end = 400.0
		add_child(mi)
		_mm[part] = mm
	# colours, once
	var idx := {"body": 0, "head": 0, "hat": 0, "pole": 0, "flag": 0}
	for p in people:
		p.cols = {"body": jackets[rng.randi() % jackets.size()], "head": skins[rng.randi() % skins.size()],
			"hat": hats[rng.randi() % hats.size()], "pole": Color(0.85, 0.85, 0.85), "flag": flags[rng.randi() % flags.size()]}
		p.idx = {}
		for part in idx:
			if part == "hat" and not p.hat:
				continue
			if (part == "pole" or part == "flag") and not p.flag:
				continue
			p.idx[part] = idx[part]
			_mm[part].set_instance_color(idx[part], p.cols[part])
			idx[part] += 1
	_pose(0.0)


func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var dist := cam.global_position.distance_to(global_position)
	if dist > NEAR and _cheer < 0.01:
		return
	_t += dt
	_cheer = move_toward(_cheer, 1.0 if dist < CHEER else 0.0, dt * (3.0 if dist < CHEER else 0.35))
	_pose(_t)


## Everyone's pose at time t: a little fidget, and jumping / waving when cheering.
func _pose(t: float) -> void:
	for p in people:
		var ph: float = p.phase
		var hop := maxf(sin(t * 9.0 + ph * 6.0), 0.0) * 0.28 * _cheer
		var sway := sin(t * 1.3 + ph * 4.0) * 0.04 + sin(t * 7.0 + ph * 3.0) * 0.12 * _cheer
		var base: Transform3D = p.xf
		var b := base.basis * Basis(Vector3.FORWARD, sway)
		var o := base.origin + Vector3.UP * hop
		_place_part(p, "body", Transform3D(b, o + b * Vector3(0, 0.58, 0)))
		_place_part(p, "head", Transform3D(b, o + b * Vector3(0, 1.3, 0)))
		if p.hat:
			_place_part(p, "hat", Transform3D(b, o + b * Vector3(0, 1.42, 0)))
		if p.flag:
			# held up in one hand, waved harder when cheering
			var wave := sin(t * 5.0 + ph * 5.0) * (0.15 + 0.45 * _cheer)
			var fb := b * Basis(Vector3.FORWARD, wave)
			var hand := o + b * Vector3(0.24, 0.95, -0.05)
			_place_part(p, "pole", Transform3D(fb, hand + fb * Vector3(0, 0.75, 0)))
			var flutter := Basis(Vector3.UP, sin(t * 11.0 + ph * 7.0) * 0.35)
			_place_part(p, "flag", Transform3D(fb * flutter, hand + fb * Vector3(0, 1.32, 0)))


func _place_part(p: Dictionary, part: String, xf: Transform3D) -> void:
	_mm[part].set_instance_transform(p.idx[part], xf)


static func _mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	return m


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 6
	m.rings = 1
	m.material = _mat()
	return m


static func _sphere(r: float, h: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 6
	m.rings = 3
	m.is_hemisphere = h < r * 1.5
	m.material = _mat()
	return m


static func _cylinder(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 4
	m.material = _mat()
	return m


## A flag hanging off the pole's top, to one side (both faces drawn).
static func _flag_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.8, 0.5)
	q.center_offset = Vector3(0.4, -0.25, 0.0)
	var m := _mat()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED       # bright in the shade too: flags pop
	q.material = m
	return q
