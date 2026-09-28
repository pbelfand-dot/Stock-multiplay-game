extends RefCounted
## What cash looks like, sized by how much of it there is: the stack in your
## hand, the spread you lay out for the photo, the stacks in a money counter.
## $100 bills: 0.156 x 0.066 m; a strapped $10K brick (100 bills) is 0.011 m.
## Uses the kit's MoneyBrick / BillStack / BillFan / Bill props when they're
## there, plain boxes otherwise.

const PropKit = preload("res://scripts/art/prop_kit.gd")

const BILL := Vector2(0.156, 0.066)
const BRICK_H := 0.011
const BRICK := 10_000.0
const GREEN := Color(0.62, 0.72, 0.6)
const BAND := Color(0.9, 0.72, 0.25)

static var _mats := {}


static func _mat(c: Color) -> StandardMaterial3D:
	if not _mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		_mats[c] = m
	return _mats[c]


static func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = pos + Vector3(0, size.y / 2.0, 0)
	mi.rotation.y = rot_y
	parent.add_child(mi)
	return mi


## One strapped $10K brick, origin bottom center, long side along x.
static func brick(parent: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	if PropKit.has("MoneyBrick"):
		return PropKit.place("MoneyBrick", parent, pos, rot_y)
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rot_y
	parent.add_child(n)
	_box(n, Vector3(BILL.x, BRICK_H, BILL.y), Vector3.ZERO, GREEN)
	_box(n, Vector3(0.03, BRICK_H + 0.001, BILL.y + 0.002), Vector3(0, -0.0005, 0), BAND)
	return n


## A loose stack of bills `h` metres tall (no strap).
static func loose(parent: Node3D, pos: Vector3, h: float, rot_y := 0.0) -> Node3D:
	if PropKit.has("BillStack"):
		var s := PropKit.place("BillStack", parent, pos, rot_y)
		s.scale = Vector3(1, maxf(h, 0.0008) / 0.01, 1)
		return s
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rot_y
	parent.add_child(n)
	_box(n, Vector3(BILL.x, maxf(h, 0.0008), BILL.y), Vector3.ZERO, GREEN)
	return n


## One bill lying flat (for spreads and the counter's flicking bills).
static func bill(parent: Node3D, pos: Vector3, rot := Vector3.ZERO) -> Node3D:
	var n: Node3D
	if PropKit.has("Bill"):
		n = PropKit.place("Bill", parent, pos, rot.y)
	else:
		n = Node3D.new()
		n.position = pos
		parent.add_child(n)
		_box(n, Vector3(BILL.x, 0.0008, BILL.y), Vector3.ZERO, GREEN)
	n.rotation = rot
	return n


## The stack you hold: bigger with more cash (a band for small money, up to a
## tall tower of bricks). Returns the node; "Riffle" is the top bill that flicks.
static func hand_stack(amount: float) -> Node3D:
	var root := Node3D.new()
	root.name = "CashStack"
	var bricks := clampi(int(floor(amount / BRICK)), 0, 16)
	var rest := fmod(amount, BRICK) if bricks < 16 else 0.0
	var y := 0.0
	for k in bricks:
		brick(root, Vector3(randf_range(-0.003, 0.003), y, randf_range(-0.002, 0.002)), randf_range(-0.04, 0.04))
		y += BRICK_H
	if rest >= 100.0 or bricks == 0:
		var h := maxf(rest / BRICK * BRICK_H, 0.0015)
		loose(root, Vector3(0, y, 0), h)
		y += h
	# the top bill, hinged at the far end: the thumb riffles it
	var hinge := Node3D.new()
	hinge.name = "Riffle"
	hinge.position = Vector3(BILL.x / 2.0, y, 0)
	root.add_child(hinge)
	bill(hinge, Vector3(-BILL.x / 2.0, 0, 0))
	return root


## A fan of hundreds for the "money spread" pose.
static func fan() -> Node3D:
	if PropKit.has("BillFan"):
		return _kit_fan()
	var root := Node3D.new()
	for k in 9:                                       # bills pivot at the grip, fanned in the XY plane
		var piv := Node3D.new()
		piv.rotation.z = deg_to_rad(55.0 - k * 13.75)
		piv.position.z = k * 0.0007
		root.add_child(piv)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(BILL.y, BILL.x, 0.0008)
		mi.mesh = bm
		mi.material_override = _mat(GREEN.lerp(Color(0.72, 0.8, 0.68), (k % 3) * 0.3))
		mi.position = Vector3(0, BILL.x / 2.0 - 0.01, 0)
		piv.add_child(mi)
	return root


static func _kit_fan() -> Node3D:
	var holder := Node3D.new()
	PropKit.place("BillFan", holder)
	return holder


## Cash laid out on the floor / a table for the photo. Under $10K: loose
## bills fanned in a circle. Bricks: a neat grid, then a pyramid when it's a
## lot, with loose bills scattered around the edge.
static func spread(amount: float, seed_v: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var root := Node3D.new()
	root.name = "CashSpread"
	var bricks := clampi(int(floor(amount / BRICK)), 0, 200)
	if bricks == 0:
		var n := clampi(int(amount / 100.0), 3, 60)
		for k in n:
			var a := TAU * k / n + rng.randf_range(-0.05, 0.05)
			var r := 0.06 + (k % 3) * 0.05
			bill(root, Vector3(cos(a) * r, 0.0008 * k, sin(a) * r), Vector3(0, -a + PI / 2, rng.randf_range(-0.03, 0.03)))
		return root
	# grid footprint: up to 10 x 10 on the ground, then layers on top (smaller)
	var per_layer := mini(bricks, 100)
	var cols := ceili(sqrt(per_layer * 1.6))
	var rows := ceili(per_layer / float(cols))
	var left := bricks
	var layer := 0
	while left > 0 and layer < 8:
		var c := maxi(cols - layer, 1)
		var r := maxi(rows - layer, 1)
		for i in r:
			for j in c:
				if left <= 0:
					break
				var p := Vector3((j - (c - 1) / 2.0) * (BILL.x + 0.012), layer * BRICK_H,
						(i - (r - 1) / 2.0) * (BILL.y + 0.012))
				brick(root, p, rng.randf_range(-0.05, 0.05))
				left -= 1
		layer += 1
	# loose bills fanned around the edge
	var ring := clampi(bricks * 2, 8, 40)
	var rad_x := cols * (BILL.x + 0.012) / 2.0 + 0.09
	var rad_z := rows * (BILL.y + 0.012) / 2.0 + 0.09
	for k in ring:
		var a := TAU * k / ring
		bill(root, Vector3(cos(a) * rad_x, 0.0006 * (k % 4), sin(a) * rad_z),
				Vector3(0, -a + rng.randf_range(-0.4, 0.4), 0))
	return root
