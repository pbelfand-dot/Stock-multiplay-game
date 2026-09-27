extends RefCounted
## Hand props in the trailer's style: cigar, FLEX money gun, police pistol,
## phone, NYPD booking placard. Each returns a Node3D whose origin is the grip.

const S = preload("res://scripts/art/shapes.gd")


static func cigar() -> Node3D:
	var n := Node3D.new()
	n.name = "Cigar"
	S.part(n, S.superellipsoid(0.018, 0.018, 0.13, 2.2), S.mat(Color(0.45, 0.28, 0.13), false), Vector3(0, 0, -0.06))
	S.part(n, S.superellipsoid(0.0195, 0.0195, 0.018, 2.4), S.mat(Color(0.85, 0.7, 0.2), false), Vector3(0, 0, 0.02))  # band
	S.part(n, S.superellipsoid(0.017, 0.017, 0.012, 2.0), S.mat(Color(1, 0.45, 0.08), false, 3.0), Vector3(0, 0, -0.19))  # ember
	return n


static func flex_gun() -> Node3D:
	var n := Node3D.new()
	n.name = "FlexGun"
	var red := S.mat(Color(0.82, 0.08, 0.08), false)
	S.part(n, S.superellipsoid(0.045, 0.06, 0.14, 3.5), red, Vector3(0, 0.07, -0.06))
	S.part(n, S.superellipsoid(0.032, 0.07, 0.035, 3.0), red, Vector3(0, -0.01, 0.02), Vector3(0.25, 0, 0))
	S.part(n, S.superellipsoid(0.035, 0.012, 0.03, 3.0), S.mat(Color(0.95, 0.95, 0.9), false), Vector3(0, 0.08, -0.2))  # bill slot
	var l := Label3D.new()
	l.text = "FLEX"
	l.font_size = 40
	l.pixel_size = 0.0022
	l.modulate = Color.WHITE
	l.outline_size = 0
	l.position = Vector3(0.047, 0.07, -0.06)
	l.rotation.y = PI / 2
	n.add_child(l)
	var l2 := l.duplicate()
	l2.position.x = -0.047
	l2.rotation.y = -PI / 2
	n.add_child(l2)
	return n


static func pistol() -> Node3D:
	var n := Node3D.new()
	n.name = "Pistol"
	var blk := S.mat(Color(0.08, 0.08, 0.09), false)
	S.part(n, S.superellipsoid(0.02, 0.028, 0.1, 4.0), blk, Vector3(0, 0.035, -0.06))
	S.part(n, S.superellipsoid(0.018, 0.05, 0.025, 3.0), blk, Vector3(0, -0.01, 0.0), Vector3(0.2, 0, 0))
	return n


static func phone() -> Node3D:
	var n := Node3D.new()
	S.part(n, S.superellipsoid(0.035, 0.07, 0.006, 4.0), S.mat(Color(0.05, 0.05, 0.06), false), Vector3(0, 0.03, -0.02))
	S.part(n, S.superellipsoid(0.03, 0.062, 0.002, 4.0), S.mat(Color(0.3, 0.9, 0.5), false, 0.8), Vector3(0, 0.03, -0.028))
	return n


static func placard(number: int) -> Node3D:
	var n := Node3D.new()
	n.name = "Placard"
	S.part(n, S.superellipsoid(0.215, 0.125, 0.01, 6.0), S.mat(Color(0.55, 0.55, 0.58), false), Vector3(0, 0, 0.004))
	S.part(n, S.superellipsoid(0.2, 0.11, 0.012, 5.0), S.mat(Color(0.05, 0.05, 0.06), false), Vector3.ZERO)
	var t := Label3D.new()
	t.text = "NYPD\n%06d" % number
	t.font_size = 64
	t.pixel_size = 0.0022
	t.line_spacing = -8
	t.outline_size = 0
	t.modulate = Color(0.95, 0.95, 0.95)
	t.position = Vector3(0, 0, -0.014)
	t.rotation.y = PI
	var f = load("res://assets/fonts/Oswald-Bold.woff2")
	if f:
		t.font = f
	n.add_child(t)
	return n


## First-person arm for the local player: sleeve + cuff + chunky hand.
static func fp_arm(look: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = "FPArm"
	var suit: Color = look.get("suit", Color(0.12, 0.115, 0.14))
	var skin: Color = look.get("skin", Color(0.88, 0.7, 0.58))
	S.part(n, S.superellipsoid(0.065, 0.065, 0.3, 3.2), S.pinstripe(suit), Vector3(0.02, -0.02, 0.28))
	S.part(n, S.superellipsoid(0.058, 0.058, 0.022, 3.0), S.mat(Color(0.96, 0.96, 0.97), false), Vector3(0.02, -0.02, -0.02))
	var hand := S.part(n, S.superellipsoid(0.055, 0.062, 0.075, 2.8), S.mat(skin, false), Vector3(0.02, -0.01, -0.09))
	hand.name = "Hand"
	S.part(n, S.superellipsoid(0.02, 0.022, 0.04, 2.2), S.mat(skin, false), Vector3(-0.035, 0.03, -0.09), Vector3(0, 0.3, 0))
	for k in 3:
		S.part(n, S.superellipsoid(0.004, 0.05, 0.004, 2.0), S.mat(skin.darkened(0.25), false), Vector3(0.075, -0.01, -0.07 - k * 0.022))
	S.part(n, S.superellipsoid(0.014, 0.014, 0.01, 2.0), S.mat(Color(1, 0.78, 0.15), false, 0.3), Vector3(0.07, -0.03, -0.12))
	var grip := Node3D.new()
	grip.name = "Grip"
	grip.position = Vector3(0.0, 0.02, -0.12)
	n.add_child(grip)
	return n
