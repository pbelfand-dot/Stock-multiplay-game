extends RefCounted
## BIG IRON's guns in your hands: the kit's Gun_* models (grip at the origin,
## barrel down -z, top up +y) or a plain boxy stand-in until the kit has them,
## plus the muzzle flash and the holes the rounds leave.

const PropKit = preload("res://scripts/art/prop_kit.gd")
const Rules = preload("res://scripts/sim/rules.gd")

const HOLE_MAX := 60
static var _holes: Array = []
static var _hole_mat: StandardMaterial3D
static var _flash_mat: StandardMaterial3D


## The gun `key` (a Rules.LUXURY gun) as a node; "Muzzle" marks the barrel tip.
static func make(key: String) -> Node3D:
	var d: Dictionary = Rules.LUXURY[key]
	var root := Node3D.new()
	root.name = "Gun"
	if PropKit.has(d.gun):
		PropKit.place(d.gun, root)
	else:
		_stand_in(root, key)
	var tip := Node3D.new()
	tip.name = "Muzzle"
	tip.position = _tip(root)
	root.add_child(tip)
	return root


## Where the barrel ends: the far -z end of the model, up at the bore.
static func _tip(root: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var xf: Transform3D = root.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform \
				if root.is_inside_tree() else _local_xf(root, mi)
		var bb: AABB = xf * (mi as MeshInstance3D).get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if first:
		return Vector3(0, 0.07, -0.2)
	return Vector3(0, box.end.y - minf(box.size.y * 0.25, 0.03), box.position.z)


static func _local_xf(root: Node3D, n: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func _stand_in(root: Node3D, key: String) -> void:
	var d: Dictionary = Rules.LUXURY[key]
	var col := Color(0.8, 0.62, 0.2) if key in ["deagle", "ak_gold"] else Color(0.07, 0.07, 0.08)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.6 if key in ["deagle", "ak_gold"] else 0.2
	m.roughness = 0.4
	var length := 0.85 if d.rifle else (0.26 if d.big else 0.19)
	_part(root, Vector3(0.03, 0.045, length), Vector3(0, 0.065, -length * 0.4), m)            # receiver + barrel
	_part(root, Vector3(0.028, 0.1, 0.045), Vector3(0, 0.0, 0.0), m, -0.3)                     # grip
	if d.rifle:
		_part(root, Vector3(0.035, 0.07, 0.26), Vector3(0, 0.05, 0.16), m)                      # stock
		_part(root, Vector3(0.025, 0.12, 0.04), Vector3(0, -0.01, -0.12), m, 0.25)               # magazine


static func _part(root: Node3D, size: Vector3, pos: Vector3, m: Material, rx := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation.x = rx
	root.add_child(mi)


## A flash at the muzzle: a light and a hot star for a couple of frames.
static func flash(gun: Node3D, big: bool) -> void:
	var tip: Node3D = gun.get_node_or_null("Muzzle")
	if tip == null:
		return
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.albedo_color = Color(1.0, 0.8, 0.35)
		_flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var f := Node3D.new()
	tip.add_child(f)
	var s := (0.16 if big else 0.1) * randf_range(0.8, 1.2)
	for k in 2:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(s, s * 0.35)
		q.mesh = qm
		q.material_override = _flash_mat
		q.rotation.z = randf() * PI + k * PI / 2
		f.add_child(q)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.4)
	l.light_energy = 3.0 if big else 2.0
	l.omni_range = 4.0
	f.add_child(l)
	f.get_tree().create_timer(0.06).timeout.connect(f.queue_free)


## A hole where a round landed (the oldest ones go when there are too many).
static func hole(parent: Node3D, at: Vector3, normal: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _hole_mat == null:
		_hole_mat = StandardMaterial3D.new()
		_hole_mat.albedo_color = Color(0.04, 0.04, 0.04)
		_hole_mat.roughness = 1.0
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	var r := randf_range(0.014, 0.02)
	qm.size = Vector2(r, r)
	mi.mesh = qm
	mi.material_override = _hole_mat
	parent.add_child(mi)
	var n := normal.normalized() if normal.length() > 0.1 else Vector3.UP
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	mi.global_transform = Transform3D(Basis.looking_at(-n, up), at + n * 0.006)
	mi.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	_holes.append(mi)
	while _holes.size() > HOLE_MAX:
		var old = _holes.pop_front()
		if is_instance_valid(old):
			old.queue_free()
