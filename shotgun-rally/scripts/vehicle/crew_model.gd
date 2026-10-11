extends Node3D
## A crew member from a rigged model (assets/models/driver.glb / codriver.glb:
## the owner's racer, a Mixamo rig, made game-ready by tools/import_crew.py)
## sat in a seat. Every frame the skeleton is posed from scratch:
##   * sitting: thighs forward, shins down to the pedals / the footwell
##   * hands on targets (the steering wheel rim, the map board) with two-bone IK
##   * the head turned where that player is looking
## Works in the cockpit's space (the car faces -Z). Bones are aimed by
## direction (bone -> child), so it doesn't care how the rig's axes point.

const SCALE := 1.2              # the cartoon crew is small for the cabin
var scale_k := SCALE            # (a car's own interior is real size: 1, set before load_model)
var thigh_y := -0.2             # the thighs' slope seated (up +): a car's own seat tilts them level
var recline := 0.0              # 0 sat up (a saloon's seat) .. 1 lying back in a single-seater's tub: the back
                                # ~50 deg off the horizontal, the head up to look over the nose, the legs out flat
const FOREARM_SLIM := 0.6       # the driver's forearms, thinned to fit the gloves' gauntlets
const HAND_CUT := 0.035         # m up the forearm from the wrist: where the driver's sleeves end (under the gauntlets)

var suit_colour := Color(0.75, 0.13, 0.12)

var skel: Skeleton3D
var look := Vector2.ZERO        # yaw (+ = left), pitch (+ = up), rad
var _b := {}                    # bone name -> index
var _posed: Array = []          # bones we pose (reset to rest every frame)
var _fore_base := Vector3.ONE   # the forearms' scale (slimmed for the gloves: hide_hands); along them it stretches to reach
var stretch := [1.0, 1.0]       # how much each forearm is stretched this frame (left, right: 1 = not)
var _to_skel := Transform3D()   # cockpit space -> skeleton space
var _head_hidden := false
var _head_mesh: MeshInstance3D   # the helmet and the collar, cut out of the body (see _split_head)
const COLLAR_W := 0.3               # a vertex this much on the head and neck bones is collar (hidden with the helmet)
var own_layer := 2              # the render layer this seat's own camera leaves out (2 driver, 3 co-driver)
var _base_layers := 1
var _cap: MeshInstance3D        # closes the neck when the helmet's hidden (looking down)
var _body: MeshInstance3D       # the skinned body (without the helmet)
var _hand_mesh: MeshInstance3D  # the bare hands, cut out of the body (see hide_hands)


## Load the model; false if it's missing or isn't the rig we expect.
func load_model(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var scene: Node3D = load(path).instantiate()
	scene.rotation.y = PI                           # the model faces +Z, the car -Z
	scene.scale = Vector3.ONE * scale_k
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
## your helmet. The suit's collar round the neck goes with it (from the eye it was
## a white ring across the bottom of the view). Everything stays skinned to the
## same skeleton.
func _split_head(sk: Skeleton3D) -> void:
	var heads := []
	for n in ["Head", "head_end", "headfront"]:
		var i := sk.find_bone(n)
		if i >= 0:
			heads.append(i)
	var neck := sk.find_bone("neck")
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
			var wn := 0.0
			for j in per:
				if bones[v * per + j] in heads:
					w += weights[v * per + j]
				elif bones[v * per + j] == neck:
					wn += weights[v * per + j]
			is_head[v] = 1 if w > 0.5 or w + wn > COLLAR_W else 0
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
			pair[0].add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, copy, [], {}, _flags(src, surf))
			pair[0].surface_set_material(pair[0].get_surface_count() - 1, mat)
	body.mesh = keep
	_body = body
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
	var u := _unit(sk)                               # m -> skeleton units (a rig in cm has its armature at x0.01)
	cm.top_radius = 0.085 * u                         # (wide enough to close the collar's cut too)
	cm.bottom_radius = 0.095 * u
	cm.height = 0.03 * u
	cm.radial_segments = 10
	_cap.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = suit_colour
	cmat.roughness = 0.8
	_cap.material_override = cmat
	_cap.visible = false
	att.add_child(_cap)


## A surface's format flags to rebuild it with (8 bone weights, custom channels).
static func _flags(m: Mesh, surf: int) -> int:
	var f: int = m.surface_get_format(surf)
	var keep: int = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	for c in 4:
		keep |= Mesh.ARRAY_FORMAT_CUSTOM_MASK << (Mesh.ARRAY_FORMAT_CUSTOM_BASE + c * Mesh.ARRAY_FORMAT_CUSTOM_BITS)
	return f & keep


## Skeleton units per metre of the rig as it was made (100 for a rig in cm).
func _unit(sk: Skeleton3D) -> float:
	var s := 1.0                                      # the skeleton's scale under this node (the model's, its armature's)
	var n: Node = sk
	while n and n != self:
		if n is Node3D:
			s *= (n as Node3D).scale.x
		n = n.get_parent()
	return scale_k / s if s > 0.0 else 1.0


## Draw the body on this render layer only (a seat camera can then leave it out).
func set_layer(layer: int) -> void:
	_base_layers = 1 << (layer - 1)
	for mi in find_children("*", "MeshInstance3D", true, false):
		mi.layers = _base_layers


## The render layers it's drawn on (see set_layer).
func layer_mask() -> int:
	return _base_layers


## Put the hips at `hips` (cockpit space).
func seat_at(hips: Vector3) -> void:
	_update_to_skel()
	var at: Vector3 = _to_skel.affine_inverse() * skel.get_bone_global_pose(_b.Hips).origin
	position += hips - at
	_update_to_skel()


## After moving the model by hand (its position): the pose's frame follows.
func moved() -> void:
	_update_to_skel()


## Your own body: your arms stay on the wheel, but not your helmet (the camera's in
## it): it goes on render layer 2, which the driver's camera leaves out.
func hide_head(on: bool) -> void:
	_head_hidden = on
	if _head_mesh:
		_head_mesh.layers = (1 << (own_layer - 1)) if on else _base_layers
	if _cap:
		_cap.visible = on


## The driver's gloves are separate (driver_hands.gd: fingers round the rim): hide
## these. The hands (and the model's own glove cuffs) are cut out of the body
## into their own mesh: every triangle with a corner on the forearm or hand past
## HAND_CUT, so the sleeve ends in a clean ring under the glove's gauntlet
## (shrinking the hand bone instead pulled the half-weighted verts into spikes).
## The forearms are slimmed to fit inside the gauntlets (bones run along their
## +Y, so it doesn't move the wrist).
func hide_hands(on: bool) -> void:
	if skel == null:
		return
	if on and _hand_mesh == null and _body != null:
		_hand_mesh = _cut_hands(_body)
	if _hand_mesh:
		_hand_mesh.visible = not on
	_fore_base = Vector3(FOREARM_SLIM, 1.0, FOREARM_SLIM) if on else Vector3.ONE
	for arm in ["LeftForeArm", "RightForeArm"]:
		skel.set_bone_pose_scale(_b[arm], _fore_base)


## Where the elbows are this frame (cockpit space): [left, right].
func elbows() -> Array:
	return [_to_skel.affine_inverse() * _pos("LeftForeArm"), _to_skel.affine_inverse() * _pos("RightForeArm")]


## Where bone `name` is this frame (cockpit space).
func bone(name: String) -> Vector3:
	var i := skel.find_bone(name)
	return _to_skel.affine_inverse() * skel.get_bone_global_pose(i).origin


## The body as it's posed now, as points (cockpit space): its skinned surface
## (the vertices, and points across the bigger triangles), leaving out the arms
## and anything that moves with the head (the helmet comes down over the
## shoulders; it and the hands are meshes of their own anyway), one per `cell`
## m cube, only the triangles that start in `region` (if it's given). For
## fitting things to it: the belts.
func body_points(cell := 0.012, region := AABB()) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _body == null:
		return out
	_update_to_skel()
	var skin := _body.skin
	var to_c := _to_skel.affine_inverse()
	var skip := []
	for n in ["LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand", "Head", "head_end", "headfront"]:
		skip.append(skel.find_bone(n))
	var xf: Array[Transform3D] = []                 # skin bind -> mesh to posed skeleton space
	var skipped := PackedByteArray()
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = skel.find_bone(skin.get_bind_name(b))
		xf.append(skel.get_bone_global_pose(bone) * skin.get_bind_pose(b) if bone >= 0 else Transform3D())
		skipped.append(1 if bone in skip or bone < 0 else 0)
	var seen := {}
	for surf in _body.mesh.get_surface_count():
		var arr: Array = _body.mesh.surface_get_arrays(surf)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bw = arr[Mesh.ARRAY_BONES]
		var weights = arr[Mesh.ARRAY_WEIGHTS]
		if bw == null or weights == null:
			continue
		var per := int(bw.size() / verts.size())
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var used := PackedByteArray()               # the arrays still hold the helmet's and hands' vertices
		used.resize(verts.size())
		for i in idx:
			used[i] = 1
		var posed := PackedVector3Array()
		posed.resize(verts.size())
		var keep := used.duplicate()                 # used, and not on an arm or the head
		for v in verts.size():
			if used[v] == 0:
				continue
			var p := Vector3.ZERO
			var sum := 0.0
			var off := 0.0
			for j in per:
				var w: float = weights[v * per + j]
				if w <= 0.0:
					continue
				var bi: int = bw[v * per + j]
				p += (xf[bi] * verts[v]) * w
				sum += w
				off += w * skipped[bi]
			if sum <= 0.0 or off > 0.3 * sum:
				keep[v] = 0
				continue
			posed[v] = to_c * (p / sum)
		for t in range(0, idx.size(), 3):
			if keep[idx[t]] == 0 or keep[idx[t + 1]] == 0 or keep[idx[t + 2]] == 0:
				continue
			var a := posed[idx[t]]
			if region.has_volume() and not region.has_point(a):
				continue
			var ab := posed[idx[t + 1]] - a
			var ac := posed[idx[t + 2]] - a
			var n := ceili(maxf(maxf(ab.length(), ac.length()), (ac - ab).length()) / cell)
			for i in n + 1:
				for j in n + 1 - i:
					var c := a + ab * (float(i) / n) + ac * (float(j) / n)
					var key := Vector3i((c / cell).floor())
					if not seen.has(key):
						seen[key] = true
						out.append(c)
	return out


## Move the bare hands out of `src` into their own mesh (same skin, same
## skeleton) and return it: see hide_hands.
func _cut_hands(src: MeshInstance3D) -> MeshInstance3D:
	_update_to_skel()
	var skin := src.skin
	var bind_bone := PackedInt32Array()             # skin bind -> bone
	var joint := {}                                 # bone -> its rest position in the mesh's space
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = skel.find_bone(skin.get_bind_name(b))
		bind_bone.append(bone)
		joint[bone] = skin.get_bind_pose(b).affine_inverse().origin
	var arms := []
	var to_m := 0.0                                  # mesh units -> m: the forearm's length both ways
	for side in ["Left", "Right"]:
		var hand: int = _b[side + "Hand"]
		var fore: int = _b[side + "ForeArm"]
		if not (joint.has(hand) and joint.has(fore)):
			return null
		var under := [hand, fore]                     # the hand, the forearm, and every finger bone under the hand
		for bi in skel.get_bone_count():
			var p := skel.get_bone_parent(bi)
			while p >= 0 and p != hand:
				p = skel.get_bone_parent(p)
			if p == hand:
				under.append(bi)
		arms.append([hand, fore, joint[hand], (joint[hand] - joint[fore]).normalized(), under])
		var rest := skel.get_bone_global_rest(hand).origin - skel.get_bone_global_rest(fore).origin
		to_m = (_to_skel.affine_inverse().basis * rest).length() / joint[hand].distance_to(joint[fore])
	var keep := ArrayMesh.new()
	var cut := ArrayMesh.new()
	for surf in src.mesh.get_surface_count():
		var arr: Array = src.mesh.surface_get_arrays(surf)
		var bw = arr[Mesh.ARRAY_BONES]
		var weights = arr[Mesh.ARRAY_WEIGHTS]
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if bw == null or weights == null or idx.is_empty():
			return null
		var per := int(bw.size() / verts.size())
		var past := PackedByteArray()                # on an arm, past the cut
		past.resize(verts.size())
		for v in verts.size():
			for arm in arms:
				var w := 0.0
				var fingers := 0.0
				for j in per:
					var bone := bind_bone[bw[v * per + j]] if bw[v * per + j] < bind_bone.size() else -1
					if bone in arm[4]:
						w += weights[v * per + j]
						if bone != arm[0] and bone != arm[1]:
							fingers += weights[v * per + j]
				if (w > 0.3 and (verts[v] - arm[2]).dot(arm[3]) * to_m > -HAND_CUT) or fingers > 0.3:
					past[v] = 1
		var a := PackedInt32Array()
		var b := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var dst := b if past[idx[t]] + past[idx[t + 1]] + past[idx[t + 2]] > 0 else a
			dst.append(idx[t])
			dst.append(idx[t + 1])
			dst.append(idx[t + 2])
		var mat := src.mesh.surface_get_material(surf)
		for pair in [[keep, a], [cut, b]]:
			if pair[1].is_empty():
				continue
			var copy := arr.duplicate()
			copy[Mesh.ARRAY_INDEX] = pair[1]
			pair[0].add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, copy, [], {}, _flags(src.mesh, surf))
			pair[0].surface_set_material(pair[0].get_surface_count() - 1, mat)
	src.mesh = keep
	var mi := MeshInstance3D.new()
	mi.name = "Hands"
	mi.mesh = cut
	mi.skin = skin
	mi.extra_cull_margin = 0.5
	mi.layers = src.layers
	skel.add_child(mi)
	mi.skeleton = mi.get_path_to(skel)
	return mi


## Pose for this frame. hands: [left, right] targets in cockpit space; elbow_out: the
## direction the elbows point (cockpit space); feet_fwd: how far forward the feet go.
func pose(hands: Array, elbow_out: Vector3, legs_fwd := 1.0) -> void:
	if skel == null:
		return
	for i in _posed:
		skel.set_bone_pose_rotation(i, skel.get_bone_rest(i).basis.get_rotation_quaternion())
	for arm in ["LeftForeArm", "RightForeArm"]:
		skel.set_bone_pose_scale(_b[arm], _fore_base)
	# lean the back a little forward toward the wheel (or lying back in a single-seater: the
	# lower back along the seat, the chest a little more upright, the neck bent so the
	# head's up looking over the nose)
	if recline > 0.0:
		_aim("Spine02", "Spine01", Vector3(0.0, 1.0, -0.12).lerp(Vector3(0.0, 0.62, 0.78), recline))
		_aim("Spine01", "neck", Vector3(0.0, 1.0, 0.0).lerp(Vector3(0.0, 0.8, 0.6), recline))
		_aim("neck", "Head", Vector3(0.0, 1.0, 0.0).lerp(Vector3(0.0, 1.0, -0.05), recline))
	else:
		_aim("Spine02", "Spine01", Vector3(0.0, 1.0, -0.12))
	# sitting (lying back: the thighs rising a little to the knees, the shins out flat to the
	# pedals in the nose, the toes up on them)
	for side in ["Left", "Right"]:
		var out := -1.0 if side == "Left" else 1.0
		_aim(side + "UpLeg", side + "Leg", Vector3(out * 0.1, lerpf(thigh_y, 0.24, recline), -1.0))
		_aim(side + "Leg", side + "Foot", Vector3(out * 0.02, lerpf(-0.75, -0.14, recline), lerpf(-0.55 * legs_fwd, -1.0, recline)))
		_aim(side + "Foot", side + "ToeBase", Vector3(0.0, -0.25, -1.0).lerp(Vector3(0.0, 0.55, -0.8), recline))
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
	# out of reach: the forearm stretches the rest of the way along itself, so the sleeve
	# always ends in the glove's gauntlet (the glove stays where it holds on)
	var want := a.distance_to(t)
	var k := 0 if lower.begins_with("Left") else 1
	stretch[k] = 1.0
	if want > (l1 + l2) * 0.999:
		stretch[k] = minf((want - l1) / l2, 2.5)
		skel.set_bone_pose_scale(_b[lower], Vector3(_fore_base.x, _fore_base.y * stretch[k], _fore_base.z))
