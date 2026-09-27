extends Node3D
## Stylized cartoon character in the style of the Broke Street trailer:
## big egg head, bulging tired eyes with dark bags, orange nose, thick brows,
## slicked hair, pinstripe suit with white shirt V + tie, shirt cuffs, watch,
## chunky hands. Rigged with pivot nodes and animated procedurally.
##
## Faces -Z (Godot forward). Feet at y=0. ~1.85 m tall.
##
##   var c = Character.new(); c.build(Character.preset("cop")); add_child(c)
##   c.pose = "aim"; c.move_speed = 3.0  (drives the walk cycle)

const S = preload("res://scripts/art/shapes.gd")
const Batcher = preload("res://scripts/art/batcher.gd")

const SKIN := Color(0.88, 0.7, 0.58)

## Look presets. Anything missing falls back to DEFAULT.
const DEFAULT := {
	"skin": SKIN, "hair": Color(0.13, 0.12, 0.18), "hair_style": "slick",
	"outfit": "suit", "suit": Color(0.12, 0.115, 0.14), "pinstripe": true,
	"shirt": Color(0.96, 0.96, 0.97), "tie": Color(0.06, 0.06, 0.08),
	"pants": null, "shoes": Color(0.07, 0.07, 0.08),
	"beard": "none", "glasses": "none", "watch": "silver", "ring": true,
	"chain": false, "hat": "none", "eye_bags": true, "brows": null,
	"nose": Color(0.94, 0.56, 0.38), "long_tie": false,
}

const PRESETS := {
	"trader": {},
	"cop": {"outfit": "cop", "suit": Color(0.15, 0.16, 0.27), "pants": Color(0.11, 0.11, 0.19),
		"hat": "cop", "beard": "mustache", "hair": Color(0.2, 0.13, 0.08), "watch": "none", "ring": false},
	"dealer": {"suit": Color(0.1, 0.1, 0.12), "hair": Color(0.08, 0.08, 0.12), "watch": "gold"},
	"flex": {"suit": Color(0.33, 0.32, 0.36), "hair": Color(0.3, 0.18, 0.12), "hair_style": "swept",
		"glasses": "shades", "watch": "gold", "eye_bags": false},
	"beard": {"suit": Color(0.1, 0.1, 0.12), "beard": "goatee", "hair": Color(0.12, 0.1, 0.1), "pinstripe": false},
	"tramp": {"skin": Color(0.9, 0.7, 0.54), "hair": Color(0.86, 0.66, 0.14), "hair_style": "swoop",
		"suit": Color(0.1, 0.12, 0.25), "tie": Color(0.85, 0.08, 0.1), "long_tie": true, "pinstripe": false,
		"brows": Color(0.75, 0.56, 0.2)},
	"tjz": {"outfit": "hoodie", "suit": Color(0.12, 0.12, 0.13), "hat": "headset",
		"hair": Color(0.12, 0.08, 0.05), "hair_style": "short", "beard": "stubble", "watch": "gold"},
	"kimchee": {"outfit": "tee", "suit": Color(0.95, 0.95, 0.95), "pants": Color(0.2, 0.25, 0.4),
		"chain": true, "hair": Color(0.03, 0.03, 0.05), "hair_style": "messy", "glasses": "shades",
		"skin": Color(0.88, 0.72, 0.58), "watch": "gold"},
	"kitteh": {"outfit": "tee", "suit": Color(0.25, 0.32, 0.22), "pants": Color(0.25, 0.28, 0.35),
		"hat": "headband", "hair": Color(0.45, 0.28, 0.14), "hair_style": "messy", "beard": "stubble"},
	"crammer": {"outfit": "shirt", "suit": Color(0.95, 0.95, 0.96), "pants": Color(0.2, 0.2, 0.25),
		"tie": Color(0.8, 0.1, 0.12), "hair_style": "bald", "glasses": "specs", "eye_bags": true},
}

## Player looks: the host is the classic trailer guy, others vary.
const PLAYER_LOOKS := [
	{},
	{"suit": Color(0.33, 0.32, 0.36), "hair": Color(0.3, 0.18, 0.12), "hair_style": "swept", "glasses": "shades", "watch": "gold"},
	{"suit": Color(0.12, 0.14, 0.28), "hair": Color(0.08, 0.06, 0.05), "beard": "goatee", "tie": Color(0.15, 0.3, 0.75)},
	{"suit": Color(0.4, 0.1, 0.12), "hair": Color(0.85, 0.65, 0.3), "hair_style": "swept", "skin": Color(0.9, 0.74, 0.63)},
	{"suit": Color(0.2, 0.3, 0.22), "hair": Color(0.05, 0.05, 0.05), "skin": Color(0.55, 0.38, 0.27), "hair_style": "short", "nose": Color(0.62, 0.36, 0.24)},
	{"suit": Color(0.48, 0.4, 0.3), "hair": Color(0.55, 0.2, 0.08), "hair_style": "messy", "beard": "full", "pinstripe": false},
]

var look := {}
var pose := "idle"        # idle | aim | sit | smoke | hold | dive | placard | cheer | cuffed
var move_speed := 0.0     # horizontal speed in m/s, drives the walk cycle
var talking := false
var eyes_open := 0.72     # 1 = wide, 0 = shut (trailer guys are ~0.7: tired)

var j := {}               # joint name -> Node3D
var _phase := 0.0
var _t := 0.0
var _blink := 0.0
var _next_blink := 2.0
var _rot := {}             # joint -> Euler we own (never read back from the node: gimbal flips)
var mouth: MeshInstance3D
var lids: Array = []
var prop_right: Node3D    # attach held props here (in the right hand)
var prop_left: Node3D


static func preset(name: String) -> Dictionary:
	return PRESETS.get(name, {})


static func player_look(index: int) -> Dictionary:
	return PLAYER_LOOKS[index % PLAYER_LOOKS.size()]


func _g(k: String):
	var v = look.get(k, DEFAULT.get(k))
	return v


func build(l: Dictionary) -> void:
	look = l
	for c in get_children():
		remove_child(c)
		c.queue_free()
	j.clear()
	lids.clear()
	_rot.clear()
	var skin: Color = _g("skin")
	var outfit: String = _g("outfit")
	var top_col: Color = _g("suit")
	var pants_col: Color = _g("pants") if _g("pants") != null else top_col.darkened(0.05)
	var cloth: Material = S.pinstripe(top_col) if (_g("pinstripe") and outfit == "suit") else S.mat(top_col)
	var pants_mat: Material = S.pinstripe(pants_col) if (_g("pinstripe") and outfit == "suit") else S.mat(pants_col)
	var skin_m := S.mat(skin)

	var root := S.joint(self, Vector3.ZERO, "Root")
	j.root = root
	var hips := S.joint(root, Vector3(0, 0.93, 0), "Hips")
	j.hips = hips
	var spine := S.joint(hips, Vector3.ZERO, "Spine")
	j.spine = spine

	# ---------------- torso ----------------
	match outfit:
		"suit", "cop", "shirt":
			S.part(spine, S.superellipsoid(0.235, 0.36, 0.14, 3.4, 0.9, 1.08), cloth, Vector3(0, 0.25, 0))
		"hoodie":
			S.part(spine, S.superellipsoid(0.24, 0.35, 0.15, 3.2, 0.92, 1.08), cloth, Vector3(0, 0.26, 0))
			S.part(spine, S.superellipsoid(0.17, 0.06, 0.12, 2.2), S.mat(top_col.lightened(0.08)), Vector3(0, 0.6, 0.06))
		"tee":
			S.part(spine, S.superellipsoid(0.23, 0.33, 0.14, 3.2, 0.92, 1.08), cloth, Vector3(0, 0.27, 0))
	var front_z := -0.138
	if outfit == "suit" or outfit == "shirt":
		# white shirt V + tie + lapels
		var shirt_m := S.mat(_g("shirt"), false)
		var vh := 0.24 if outfit == "suit" else 0.34
		S.part(spine, S.tri_plate(0.15 if outfit == "suit" else 0.2, vh, 0.012), shirt_m, Vector3(0, 0.62 - vh / 2, front_z - 0.004))
		var tie_m := S.mat(_g("tie"), false)
		var tie_len := 0.26 if _g("long_tie") else 0.19
		S.part(spine, S.superellipsoid(0.02, tie_len / 2, 0.008, 3.0, 1.6, 0.8), tie_m, Vector3(0, 0.6 - tie_len / 2, front_z - 0.02))
		S.part(spine, S.superellipsoid(0.022, 0.018, 0.012, 2.5), tie_m, Vector3(0, 0.6, front_z - 0.022))
		if outfit == "suit":
			var lap_m := S.mat(top_col.darkened(0.25), false)
			for sd in [-1, 1]:
				S.part(spine, S.superellipsoid(0.012, 0.14, 0.006, 3.0), lap_m,
					Vector3(sd * 0.045, 0.49, front_z - 0.012), Vector3(0, 0, sd * 0.33))
			for by in [0.26, 0.18]:
				S.part(spine, S.superellipsoid(0.012, 0.012, 0.006, 2.0), S.mat(Color(0.04, 0.04, 0.05), false), Vector3(0, by, front_z - 0.004))
			for sd in [-1, 1]:
				S.part(spine, S.superellipsoid(0.055, 0.008, 0.006, 4.0), lap_m, Vector3(sd * 0.13, 0.12, front_z + 0.01))
	elif outfit == "cop":
		var dark := S.mat(Color(0.05, 0.05, 0.06), false)
		S.part(spine, S.superellipsoid(0.25, 0.035, 0.155, 3.5), dark, Vector3(0, 0.03, 0))           # belt
		S.part(spine, S.superellipsoid(0.03, 0.022, 0.01, 4.0), S.mat(Color(0.8, 0.82, 0.86), false), Vector3(0, 0.03, -0.16))
		S.part(spine, S.superellipsoid(0.028, 0.034, 0.008, 2.5), S.mat(Color(1, 0.78, 0.2), false, 0.2), Vector3(0.1, 0.46, front_z - 0.004))
		for sd in [-1, 1]:  # pocket flaps
			S.part(spine, S.superellipsoid(0.05, 0.008, 0.006, 4.0), S.mat(top_col.darkened(0.3), false), Vector3(sd * 0.1, 0.4, front_z + 0.006))
		S.part(spine, S.superellipsoid(0.014, 0.19, 0.008, 3.0), S.mat(top_col.darkened(0.3), false), Vector3(0, 0.33, front_z - 0.003))
	elif outfit == "tee":
		S.part(spine, S.superellipsoid(0.07, 0.03, 0.02, 2.0), skin_m, Vector3(0, 0.58, front_z + 0.02))
	if _g("chain"):
		var gold := S.mat(Color(1, 0.8, 0.2), false, 0.3)
		var ch := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.1
		tm.outer_radius = 0.115
		ch.mesh = tm
		ch.material_override = gold
		ch.position = Vector3(0, 0.55, -0.07)
		ch.rotation.x = 1.15
		spine.add_child(ch)
		S.part(spine, S.superellipsoid(0.03, 0.03, 0.01, 2.0), gold, Vector3(0, 0.43, front_z - 0.01))

	# ---------------- neck + head ----------------
	S.part(spine, S.superellipsoid(0.065, 0.07, 0.065, 2.0), skin_m, Vector3(0, 0.65, 0.005))
	var neck := S.joint(spine, Vector3(0, 0.68, 0), "Neck")
	j.neck = neck
	var head := S.joint(neck, Vector3(0, 0.19, 0), "Head")
	j.head = head
	_build_head(head, skin)

	# ---------------- arms ----------------
	var sleeve_m: Material = cloth
	var short_sleeve: bool = outfit == "tee"
	for sd in [-1, 1]:
		var side := "L" if sd < 0 else "R"
		var sh := S.joint(spine, Vector3(sd * 0.225, 0.55, 0), "Shoulder" + side)
		j["shoulder" + side] = sh
		S.part(sh, S.superellipsoid(0.07, 0.06, 0.075, 2.8), sleeve_m, Vector3(-sd * 0.02, -0.005, 0))
		if short_sleeve:
			S.part(sh, S.superellipsoid(0.072, 0.1, 0.072, 3.0), sleeve_m, Vector3(0, -0.08, 0))
			S.part(sh, S.superellipsoid(0.056, 0.13, 0.056, 3.0), skin_m, Vector3(0, -0.2, 0))
		else:
			S.part(sh, S.superellipsoid(0.066, 0.18, 0.068, 3.2, 0.92, 1.0), sleeve_m, Vector3(0, -0.15, 0))
		var el := S.joint(sh, Vector3(0, -0.32, 0), "Elbow" + side)
		j["elbow" + side] = el
		if short_sleeve:
			S.part(el, S.superellipsoid(0.052, 0.16, 0.052, 3.0), skin_m, Vector3(0, -0.13, 0))
		else:
			S.part(el, S.superellipsoid(0.061, 0.16, 0.063, 3.2, 0.92, 1.0), sleeve_m, Vector3(0, -0.13, 0))
			if outfit != "hoodie":
				S.part(el, S.superellipsoid(0.058, 0.02, 0.058, 3.0), S.mat(_g("shirt") if outfit != "cop" else top_col.lightened(0.1)), Vector3(0, -0.28, 0))
		var wrist := S.joint(el, Vector3(0, -0.3, 0), "Wrist" + side)
		j["wrist" + side] = wrist
		# chunky mitten hand + thumb
		S.part(wrist, S.superellipsoid(0.05, 0.068, 0.062, 2.8), skin_m, Vector3(0, -0.065, -0.008))
		S.part(wrist, S.superellipsoid(0.02, 0.035, 0.02, 2.2), skin_m, Vector3(-sd * 0.035, -0.045, -0.035), Vector3(0.4, 0, -sd * 0.5))
		for k in 3:  # finger creases
			S.part(wrist, S.superellipsoid(0.046, 0.004, 0.004, 2.0), S.mat(skin.darkened(0.25), false), Vector3(0, -0.075 - k * 0.018, -0.058))
		if side == "L" and _g("watch") != "none":
			var wc: Color = Color(0.72, 0.8, 0.9) if _g("watch") == "silver" else Color(1, 0.78, 0.2)
			S.part(wrist, S.superellipsoid(0.058, 0.02, 0.062, 3.0), S.mat(wc), Vector3(0, 0.0, 0))
			S.part(wrist, S.superellipsoid(0.028, 0.028, 0.012, 2.2), S.mat(wc.lightened(0.3), false), Vector3(-0.05, 0.0, 0), Vector3(0, PI / 2, 0))
		if side == "R" and _g("ring"):
			S.part(wrist, S.superellipsoid(0.014, 0.01, 0.014, 2.0), S.mat(Color(1, 0.78, 0.15), false, 0.3), Vector3(0.03, -0.09, -0.045))
		var grip := S.joint(wrist, Vector3(0, -0.08, -0.03), "Grip" + side)
		if side == "R":
			prop_right = grip
		else:
			prop_left = grip

	# ---------------- legs ----------------
	for sd in [-1, 1]:
		var side := "L" if sd < 0 else "R"
		var hip := S.joint(hips, Vector3(sd * 0.11, 0.0, 0), "Hip" + side)
		j["hip" + side] = hip
		S.part(hip, S.superellipsoid(0.094, 0.26, 0.098, 3.3, 0.9, 1.0), pants_mat, Vector3(0, -0.21, 0))
		var knee := S.joint(hip, Vector3(0, -0.43, 0), "Knee" + side)
		j["knee" + side] = knee
		S.part(knee, S.superellipsoid(0.085, 0.24, 0.088, 3.3, 1.02, 0.95), pants_mat, Vector3(0, -0.2, 0))
		var ankle := S.joint(knee, Vector3(0, -0.43, 0), "Ankle" + side)
		j["ankle" + side] = ankle
		S.part(ankle, S.superellipsoid(0.07, 0.05, 0.14, 3.0, 1.0, 0.85), S.mat(_g("shoes")), Vector3(0, -0.02, -0.045))

	scale = Vector3.ONE * 0.93
	# collapse each joint's parts into one mesh per material (fewer draw calls)
	var joints: Array = []
	_gather_joints(self, joints)
	Batcher.merge_joints(joints)


func _gather_joints(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Node3D and not c is MeshInstance3D and not c is Label3D:
			out.append(c)
			_gather_joints(c, out)


func _build_head(head: Node3D, skin: Color) -> void:
	var skin_m := S.mat(skin)
	var hair_c: Color = _g("hair")
	var hair_m := S.mat(hair_c)
	var brow_c: Color = _g("brows") if _g("brows") != null else hair_c.darkened(0.2)
	# egg-shaped head: wider forehead, narrower jaw
	S.part(head, S.superellipsoid(0.165, 0.205, 0.17, 2.5, 0.8, 1.05, 18, 24), skin_m, Vector3(0, 0, 0))
	# ears
	for sd in [-1, 1]:
		S.part(head, S.superellipsoid(0.028, 0.052, 0.036, 2.2), skin_m, Vector3(sd * 0.168, 0.0, 0.01))
	# eyes: dark bags, white bulb, pupil, eyelid
	var bag_m := S.mat(skin.darkened(0.28).lerp(Color(0.72, 0.42, 0.28), 0.5), false)
	var white_m := S.mat(Color(0.98, 0.98, 0.97), false)
	var pupil_m := S.mat(Color(0.03, 0.03, 0.04), false)
	for sd in [-1, 1]:
		var eye := S.joint(head, Vector3(sd * 0.062, 0.03, -0.14), "Eye" + ("L" if sd < 0 else "R"))
		if _g("eye_bags"):
			S.part(eye, S.superellipsoid(0.064, 0.06, 0.02, 2.0), bag_m, Vector3(0, -0.012, 0.012))
		S.part(eye, S.superellipsoid(0.052, 0.047, 0.032, 2.0), white_m, Vector3.ZERO)
		S.part(eye, S.superellipsoid(0.015, 0.016, 0.008, 2.0), pupil_m, Vector3(-sd * 0.006, -0.006, -0.031))
		# eyelid: skin cap that rotates down over the eye (blink / tired)
		var lid_pivot := S.joint(eye, Vector3.ZERO, "Lid")
		S.part(lid_pivot, S.superellipsoid(0.056, 0.05, 0.036, 2.0, 1.0, 1.0, 8, 16), S.mat(skin.darkened(0.06), false), Vector3(0, 0.02, 0.036))
		lids.append(lid_pivot)
	# brows
	for sd in [-1, 1]:
		S.part(head, S.superellipsoid(0.05, 0.015, 0.016, 3.2), S.mat(brow_c, false),
			Vector3(sd * 0.064, 0.1, -0.155), Vector3(0, 0, -sd * 0.1))
	# nose
	S.part(head, S.superellipsoid(0.017, 0.027, 0.024, 2.2, 1.3, 0.7), S.mat(_g("nose")), Vector3(0, -0.03, -0.176))
	# mouth
	mouth = S.part(head, S.superellipsoid(0.03, 0.006, 0.006, 3.0), S.mat(Color(0.12, 0.04, 0.04), false), Vector3(0, -0.098, -0.157))
	mouth.set_meta("no_batch", true)
	# facial hair
	match _g("beard"):
		"mustache":
			S.part(head, S.superellipsoid(0.058, 0.02, 0.02, 2.4, 1.1, 0.8), hair_m, Vector3(0, -0.065, -0.166))
		"goatee":
			S.part(head, S.superellipsoid(0.05, 0.016, 0.018, 2.4), hair_m, Vector3(0, -0.07, -0.163))
			S.part(head, S.superellipsoid(0.07, 0.05, 0.05, 2.5), hair_m, Vector3(0, -0.15, -0.115))
		"full":
			S.part(head, S.superellipsoid(0.165, 0.11, 0.15, 2.4, 0.7, 1.0), hair_m, Vector3(0, -0.12, -0.03))
			S.part(head, S.superellipsoid(0.055, 0.017, 0.02, 2.4), hair_m, Vector3(0, -0.07, -0.165))
		"stubble":
			S.part(head, S.superellipsoid(0.15, 0.085, 0.14, 2.4, 0.65, 1.0), S.mat(skin.lerp(hair_c, 0.35), false), Vector3(0, -0.105, -0.025))
	# hair
	match _g("hair_style"):
		"slick":
			S.part(head, S.superellipsoid(0.176, 0.13, 0.18, 2.6, 1.0, 0.88), hair_m, Vector3(0, 0.12, 0.035))
			S.part(head, S.superellipsoid(0.15, 0.065, 0.08, 2.6), hair_m, Vector3(0.01, 0.2, -0.095), Vector3(0.3, 0, -0.05))
			for sd in [-1, 1]:
				S.part(head, S.superellipsoid(0.02, 0.05, 0.03, 2.4), hair_m, Vector3(sd * 0.163, 0.04, -0.02))
		"swept":
			S.part(head, S.superellipsoid(0.176, 0.13, 0.18, 2.6, 1.0, 0.88), hair_m, Vector3(0, 0.12, 0.035))
			S.part(head, S.superellipsoid(0.16, 0.075, 0.1, 2.4), hair_m, Vector3(0.02, 0.2, -0.08), Vector3(0.1, 0.3, -0.12))
		"swoop":
			S.part(head, S.superellipsoid(0.185, 0.13, 0.2, 2.4, 1.0, 0.9), hair_m, Vector3(0, 0.12, 0.02))
			S.part(head, S.superellipsoid(0.18, 0.08, 0.13, 2.2), hair_m, Vector3(-0.02, 0.19, -0.08), Vector3(0.35, 0, 0.2))
			for sd in [-1, 1]:
				S.part(head, S.superellipsoid(0.03, 0.08, 0.06, 2.2), hair_m, Vector3(sd * 0.168, 0.05, 0.03))
		"short":
			S.part(head, S.superellipsoid(0.172, 0.12, 0.178, 2.8, 1.0, 0.92), hair_m, Vector3(0, 0.12, 0.03))
		"messy":
			S.part(head, S.superellipsoid(0.18, 0.12, 0.19, 2.4), hair_m, Vector3(0, 0.12, 0.01))
			for k in 5:
				var a := k * 1.25
				S.part(head, S.superellipsoid(0.05, 0.05, 0.05, 2.0), hair_m, Vector3(cos(a) * 0.1, 0.22, sin(a) * 0.1 - 0.02))
		"bald":
			for sd in [-1, 1]:
				S.part(head, S.superellipsoid(0.03, 0.05, 0.08, 2.4), hair_m, Vector3(sd * 0.158, 0.02, 0.05))
	# accessories
	match _g("glasses"):
		"shades":
			var g := S.mat(Color(0.03, 0.03, 0.04))
			for sd in [-1, 1]:
				S.part(head, S.superellipsoid(0.058, 0.04, 0.012, 3.2), g, Vector3(sd * 0.066, 0.035, -0.178))
			S.part(head, S.superellipsoid(0.03, 0.008, 0.008, 3.0), g, Vector3(0, 0.05, -0.18))
			for sd in [-1, 1]:
				S.part(head, S.superellipsoid(0.006, 0.008, 0.08, 3.0), g, Vector3(sd * 0.165, 0.045, -0.1))
		"specs":
			var g2 := S.mat(Color(0.1, 0.1, 0.12), false)
			for sd in [-1, 1]:
				var ring := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 0.042
				tm.outer_radius = 0.05
				ring.mesh = tm
				ring.material_override = g2
				ring.position = Vector3(sd * 0.066, 0.035, -0.178)
				ring.rotation.x = PI / 2
				head.add_child(ring)
	match _g("hat"):
		"cop":
			var navy := S.mat(Color(0.1, 0.13, 0.28))
			S.part(head, S.superellipsoid(0.2, 0.075, 0.2, 3.2, 0.9, 1.1), navy, Vector3(0, 0.21, 0.0))
			S.part(head, S.superellipsoid(0.182, 0.03, 0.182, 4.0), S.mat(Color(0.04, 0.04, 0.05)), Vector3(0, 0.15, 0))
			S.part(head, S.superellipsoid(0.13, 0.012, 0.08, 2.2), S.mat(Color(0.03, 0.03, 0.04)), Vector3(0, 0.13, -0.16), Vector3(-0.25, 0, 0))
			S.part(head, S.superellipsoid(0.032, 0.036, 0.01, 2.4), S.mat(Color(1, 0.78, 0.2), false, 0.3), Vector3(0, 0.22, -0.188))
		"headset":
			var dk := S.mat(Color(0.08, 0.08, 0.09))
			S.part(head, S.superellipsoid(0.19, 0.025, 0.03, 2.5), dk, Vector3(0, 0.2, 0.0), Vector3(0, 0, 0))
			for sd in [-1, 1]:
				S.part(head, S.superellipsoid(0.03, 0.06, 0.06, 2.2), dk, Vector3(sd * 0.185, 0.0, 0.0))
			S.part(head, S.superellipsoid(0.008, 0.008, 0.07, 2.5), dk, Vector3(0.14, -0.06, -0.1), Vector3(0, 0.5, 0))
		"headband":
			S.part(head, S.superellipsoid(0.182, 0.024, 0.19, 2.6), S.mat(Color(0.9, 0.1, 0.12)), Vector3(0, 0.1, 0.0))


# ------------------------------------------------------------------ animation

func _process(delta: float) -> void:
	if j.is_empty():
		return
	_t += delta
	var sp := clampf(move_speed, 0.0, 9.0)
	_phase += delta * (4.0 + sp * 1.25) * (1.0 if sp > 0.2 else 0.0)
	var walk := clampf(sp / 4.5, 0.0, 1.6)
	var s := sin(_phase)
	var c := cos(_phase)
	var breathe := sin(_t * 2.0) * 0.01

	# defaults (idle / walk)
	var target := {
		"root_y": 0.0, "root_rx": 0.0, "spine_rx": -0.03 + breathe - walk * 0.06, "neck_rx": 0.0,
		"shL": Vector3(s * 0.55 * walk, 0, -0.08), "shR": Vector3(-s * 0.55 * walk, 0, 0.08),
		"elL": Vector3(0.18 + 0.25 * walk, 0, 0), "elR": Vector3(0.18 + 0.25 * walk, 0, 0),
		"hipL": Vector3(-s * 0.6 * walk, 0, 0), "hipR": Vector3(s * 0.6 * walk, 0, 0),
		"knL": Vector3(-maxf(0.0, c) * 0.9 * walk, 0, 0), "knR": Vector3(-maxf(0.0, -c) * 0.9 * walk, 0, 0),
		"bob": absf(s) * 0.035 * walk,
	}
	match pose:
		"aim":
			target.shL = Vector3(1.45, -0.38, 0)
			target.shR = Vector3(1.45, 0.38, 0)
			target.elL = Vector3(0.1, 0, 0)
			target.elR = Vector3(0.1, 0, 0)
			target.spine_rx = 0.02
		"sit":
			target.root_y = -0.43
			target.hipL = Vector3(1.5, 0, 0.05)
			target.hipR = Vector3(1.5, 0, -0.05)
			target.knL = Vector3(-1.5, 0, 0)
			target.knR = Vector3(-1.5, 0, 0)
			target.shL = Vector3(0.35, 0, -0.1)
			target.shR = Vector3(0.35, 0, 0.1)
			target.elL = Vector3(0.9, 0, 0)
			target.elR = Vector3(0.9, 0, 0)
		"smoke":
			var puff := (sin(_t * 0.9) + 1.0) * 0.5
			target.shR = Vector3(0.55 + puff * 0.35, 0.45, 0.1)
			target.elR = Vector3(2.0 + puff * 0.3, 0, 0)
		"hold":
			target.shR = Vector3(1.3, -0.1, 0.1)
			target.elR = Vector3(0.2, 0, 0)
		"cheer":
			target.shL = Vector3(0.8, -0.3, -0.15)
			target.shR = Vector3(0.8, 0.3, 0.15)
			target.elL = Vector3(1.4 + sin(_t * 6.0) * 0.3, 0, 0)
			target.elR = Vector3(1.4 - sin(_t * 6.0) * 0.3, 0, 0)
		"placard":
			target.shL = Vector3(0.75, -0.45, 0)
			target.shR = Vector3(0.75, 0.45, 0)
			target.elL = Vector3(0.75, 0, 0)
			target.elR = Vector3(0.75, 0, 0)
		"cuffed":
			target.shL = Vector3(-0.35, 0, -0.2)
			target.shR = Vector3(-0.35, 0, 0.2)
			target.elL = Vector3(0.9, 0, 0)
			target.elR = Vector3(0.9, 0, 0)
		"dive":
			target.root_rx = -1.25
			target.root_y = -0.55
			target.shL = Vector3(2.8, -0.15, 0)
			target.shR = Vector3(2.8, 0.15, 0)
			target.elL = Vector3(0.1, 0, 0)
			target.elR = Vector3(0.1, 0, 0)
			target.hipL = Vector3(-0.2, 0, 0)
			target.hipR = Vector3(-0.35, 0, 0)
			target.knL = Vector3(-0.5, 0, 0)
			target.knR = Vector3(-0.3, 0, 0)
		"type_stand":
			target.shL = Vector3(0.75, -0.2, 0)
			target.shR = Vector3(0.75, 0.2, 0)
			target.elL = Vector3(0.8 + sin(_t * 18.0) * 0.08, 0, 0)
			target.elR = Vector3(0.8 + cos(_t * 17.0) * 0.08, 0, 0)
			target.spine_rx = 0.12
		"type":
			target.shL = Vector3(0.9, -0.2, 0)
			target.shR = Vector3(0.9, 0.2, 0)
			target.elL = Vector3(0.9 + sin(_t * 18.0) * 0.08, 0, 0)
			target.elR = Vector3(0.9 + cos(_t * 17.0) * 0.08, 0, 0)
			target.root_y = -0.43
			target.hipL = Vector3(1.5, 0, 0.05)
			target.hipR = Vector3(1.5, 0, -0.05)
			target.knL = Vector3(-1.5, 0, 0)
			target.knR = Vector3(-1.5, 0, 0)
	var k := clampf(delta * 12.0, 0.0, 1.0)
	j.root.position.y = lerpf(j.root.position.y, target.root_y + target.bob, k)
	j.root.rotation.x = lerpf(j.root.rotation.x, target.root_rx, k)
	j.spine.rotation.x = lerpf(j.spine.rotation.x, target.spine_rx, k)
	_lerp_rot(j.shoulderL, target.shL, k)
	_lerp_rot(j.shoulderR, target.shR, k)
	_lerp_rot(j.elbowL, target.elL, k)
	_lerp_rot(j.elbowR, target.elR, k)
	_lerp_rot(j.hipL, target.hipL, k)
	_lerp_rot(j.hipR, target.hipR, k)
	_lerp_rot(j.kneeL, target.knL, k)
	_lerp_rot(j.kneeR, target.knR, k)
	j.head.rotation.y = sin(_t * 0.37) * 0.08

	# blink + tired lids
	_next_blink -= delta
	if _next_blink <= 0.0:
		_blink = 0.14
		_next_blink = randf_range(2.0, 5.0)
	_blink = maxf(_blink - delta, 0.0)
	var open := 0.0 if _blink > 0.0 else eyes_open
	for lid in lids:
		# rotating the cap forward/down covers more of the eye
		lid.rotation.x = lerpf(lid.rotation.x, lerpf(-2.4, -0.35, open), clampf(delta * 25.0, 0, 1))
	# talking mouth
	if mouth:
		var m_open := (0.5 + 0.5 * sin(_t * 14.0)) * 3.5 + 1.0 if talking else 1.0
		mouth.scale.y = lerpf(mouth.scale.y, m_open, clampf(delta * 20.0, 0, 1))
		mouth.scale.x = 0.8 if talking else 1.0


func _lerp_rot(n: Node3D, v: Vector3, k: float) -> void:
	var cur: Vector3 = _rot.get(n, Vector3.ZERO)
	cur = cur.lerp(v, k)
	_rot[n] = cur
	n.rotation = cur


## Look at a world point with the head (small range).
func look_pitch(p: float) -> void:
	if j.has("neck"):
		j.neck.rotation.x = clampf(p, -0.6, 0.6) * 0.6
