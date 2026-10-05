extends Node3D
## A crew member from a rigged model (assets/models/driver.glb / codriver.glb,
## made with Higgsfield: image -> Meshy image-to-3D, auto-rigged, standing in
## an A-pose) sat in a seat. Every frame the skeleton is posed from scratch:
##   * sitting: thighs forward, shins down to the pedals / the footwell
##   * hands on targets (the steering wheel rim, the map board) with two-bone IK
##   * the head turned where that player is looking
## Works in the cockpit's space (the car faces -Z). Bones are aimed by
## direction (bone -> child), so it doesn't care how the rig's axes point.

const SCALE := 1.2              # the cartoon crew is small for the cabin

var suit_colour := Color(0.75, 0.13, 0.12)

var skel: Skeleton3D
var look := Vector2.ZERO        # yaw (+ = left), pitch (+ = up), rad
var _b := {}                    # bone name -> index
var _posed: Array = []          # bones we pose (reset to rest every frame)
var _to_skel := Transform3D()   # cockpit space -> skeleton space
var _head_hidden := false
var _head_mesh: MeshInstance3D   # the helmet, cut out of the body (see _split_head)
var own_layer := 2              # the render layer this seat's own camera leaves out (2 driver, 3 co-driver)
var _base_layers := 1
var _cap: MeshInstance3D        # closes the neck when the helmet's hidden (looking down)
var _hands_hidden := false


## Load the model; false if it's missing or isn't the rig we expect.
func load_model(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var scene: Node3D = load(path).instantiate()
	scene.rotation.y = PI                           # the model faces +Z, the car -Z
	scene.scale = Vector3.ONE * SCALE
	add_child(scene)
	for ap in scene.find_children("*", "AnimationPlayer", true, false):
		ap.queue_free()                              # its idle clip would fight the pose
	var found := scene.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return false
	skel = found[0]
	for n in ["Hips", "Spine02", "Spine01", "neck", "Head", "LeftArm", "LeftForeArm", "LeftHand",
			"RightArm", "RightForeArm", "RightHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
			"RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]:
		var i := skel.find_bone(n)
		if i < 0:
			return false
		_b[n] = i
		if n != "Hips":
			_posed.append(i)
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		mi.extra_cull_margin = 0.5                  # posed far from the rest pose's bounds
	_split_head(found[0])
	return true


## Cut the helmet (the triangles that move with the head bones) into its own
## mesh, so a seat camera can leave just that out: your own camera sits inside
## your helmet. Everything stays skinned to the same skeleton.
func _split_head(sk: Skeleton3D) -> void:
	var heads := []
	for n in ["Head", "head_end", "headfront", "neck"]:
		var i := sk.find_bone(n)
		if i >= 0 and n != "neck":
			heads.append(i)
	var body: MeshInstance3D = null
	for mi in sk.find_children("*", "MeshInstance3D", false, false):
		body = mi
	if body == null or heads.is_empty():
		return
	var src: ArrayMesh = body.mesh
	var keep := ArrayMesh.new()
	var head := ArrayMesh.new()
	for surf in src.get_surface_count():
		var arr := src.surface_get_arrays(surf)
		var bones = arr[Mesh.ARRAY_BONES]
		var weights = arr[Mesh.ARRAY_WEIGHTS]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if bones == null or weights == null or idx.is_empty():
			return
		var per := int(bones.size() / arr[Mesh.ARRAY_VERTEX].size())     # influences per vertex (4 or 8)
		var is_head := PackedByteArray()
		is_head.resize(arr[Mesh.ARRAY_VERTEX].size())
		for v in is_head.size():
			var w := 0.0
			for j in per:
				if bones[v * per + j] in heads:
					w += weights[v * per + j]
			is_head[v] = 1 if w > 0.5 else 0
		var a := PackedInt32Array()
		var b := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var hcount: int = is_head[idx[t]] + is_head[idx[t + 1]] + is_head[idx[t + 2]]
			var dst := b if hcount >= 2 else a
			dst.append(idx[t])
			dst.append(idx[t + 1])
			dst.append(idx[t + 2])
		var mat := src.surface_get_material(surf)
		for pair in [[keep, a], [head, b]]:
			if pair[1].is_empty():
				continue
			var copy := arr.duplicate()
			copy[Mesh.ARRAY_INDEX] = pair[1]
			pair[0].add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, copy)
			pair[0].surface_set_material(pair[0].get_surface_count() - 1, mat)
	body.mesh = keep
	_head_mesh = MeshInstance3D.new()
	_head_mesh.name = "Helmet"
	_head_mesh.mesh = head
	_head_mesh.skin = body.skin
	_head_mesh.extra_cull_margin = 0.5
	sk.add_child(_head_mesh)
	_head_mesh.skeleton = _head_mesh.get_path_to(sk)
	# a collar that closes the neck, seen only by the seat's own camera (looking down)
	var att := BoneAttachment3D.new()
	att.bone_name = "neck"
	sk.add_child(att)
	_cap = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 6.5                              # skeleton units are cm (the armature is x0.01)
	cm.bottom_radius = 7.5
	cm.height = 3.0
	cm.radial_segments = 10
	_cap.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = suit_colour
	cmat.roughness = 0.8
	_cap.material_override = cmat
	_cap.visible = false
	att.add_child(_cap)


## Draw the body on this render layer only (a seat camera can then leave it out).
func set_layer(layer: int) -> void:
	_base_layers = 1 << (layer - 1)
	for mi in find_children("*", "MeshInstance3D", true, false):
		mi.layers = _base_layers


## Put the hips at `hips` (cockpit space).
func seat_at(hips: Vector3) -> void:
	_update_to_skel()
	var at: Vector3 = _to_skel.affine_inverse() * skel.get_bone_global_pose(_b.Hips).origin
	position += hips - at
	_update_to_skel()


## Your own body: your arms stay on the wheel, but not your helmet (the camera's in
## it): it goes on render layer 2, which the driver's camera leaves out.
func hide_head(on: bool) -> void:
	_head_hidden = on
	if _head_mesh:
		_head_mesh.layers = (1 << (own_layer - 1)) if on else _base_layers
	if _cap:
		_cap.visible = on


## The driver's gloves are separate (driver_hands.gd: fingers round the rim): hide these.
func hide_hands(on: bool) -> void:
	_hands_hidden = on


## Pose for this frame. hands: [left, right] targets in cockpit space; elbow_out: the
## direction the elbows point (cockpit space); feet_fwd: how far forward the feet go.
func pose(hands: Array, elbow_out: Vector3, legs_fwd := 1.0) -> void:
	if skel == null:
		return
	for i in _posed:
		skel.set_bone_pose_rotation(i, skel.get_bone_rest(i).basis.get_rotation_quaternion())
	# lean the back a little forward toward the wheel
	_aim("Spine02", "Spine01", Vector3(0.0, 1.0, -0.12))
	# sitting
	for side in ["Left", "Right"]:
		var out := -1.0 if side == "Left" else 1.0
		_aim(side + "UpLeg", side + "Leg", Vector3(out * 0.1, -0.2, -1.0))
		_aim(side + "Leg", side + "Foot", Vector3(out * 0.02, -0.75, -0.55 * legs_fwd))
		_aim(side + "Foot", side + "ToeBase", Vector3(0.0, -0.25, -1.0))
	# hands
	_ik("LeftArm", "LeftForeArm", "LeftHand", hands[0], hands[0] + Vector3(-elbow_out.x, elbow_out.y, elbow_out.z))
	_ik("RightArm", "RightForeArm", "RightHand", hands[1], hands[1] + elbow_out)
	# head: turn (yaw about up) and nod (pitch about the car's right)
	var head: int = _b.Head
	var g := skel.get_bone_global_pose(head)
	var up := (_to_skel.basis * Vector3.UP).normalized()
	var right := (_to_skel.basis * Vector3.RIGHT).normalized()
	var turned := Basis(up, look.x) * Basis(right, look.y) * g.basis
	_set_global_basis(head, turned)
	# (your own head stays: the camera sits inside the helmet, and from inside a closed
	# mesh every face points away and isn't drawn. Shrinking it left a hole in the neck)
	for hand in ["LeftHand", "RightHand"]:
		skel.set_bone_pose_scale(_b[hand], Vector3.ONE * (0.05 if _hands_hidden else 1.0))


# ── helpers ───────────────────────────────────────────────────────────────

func _update_to_skel() -> void:
	var xf := Transform3D()
	var n: Node = skel
	while n != get_parent() and n != null:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	_to_skel = xf.affine_inverse()


func _pos(name: String) -> Vector3:
	return skel.get_bone_global_pose(_b[name]).origin


## Point bone `name` (its line to `child`) along `dir_c` (cockpit space).
func _aim(name: String, child: String, dir_c: Vector3) -> void:
	_aim_skel(name, child, _to_skel.basis * dir_c)


func _aim_skel(name: String, child: String, want: Vector3) -> void:
	var i: int = _b[name]
	var cur := _pos(child) - _pos(name)
	if cur.length() < 1e-5 or want.length() < 1e-5:
		return
	var q := Quaternion(cur.normalized(), want.normalized())
	_set_global_basis(i, Basis(q) * skel.get_bone_global_pose(i).basis)


func _set_global_basis(i: int, b: Basis) -> void:
	var parent := skel.get_bone_parent(i)
	var pb: Basis = skel.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	skel.set_bone_pose_rotation(i, (pb.inverse() * b).get_rotation_quaternion())


## Two-bone IK: upper -> lower -> end reaching for `target_c`, the elbow toward `pole_c`.
func _ik(upper: String, lower: String, end: String, target_c: Vector3, pole_c: Vector3) -> void:
	var t := _to_skel * target_c
	var pole := _to_skel * pole_c
	var a := _pos(upper)
	var l1 := a.distance_to(_pos(lower))
	var l2 := _pos(lower).distance_to(_pos(end))
	var d := clampf(a.distance_to(t), 0.01, (l1 + l2) * 0.999)
	var dir := (t - a).normalized()
	var x := (l1 * l1 + d * d - l2 * l2) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - x * x, 0.0))
	var side := pole - a
	side = (side - dir * side.dot(dir)).normalized()
	var elbow := a + dir * x + side * h
	_aim_skel(upper, lower, elbow - a)
	_aim_skel(lower, end, (a + dir * d) - _pos(lower))
