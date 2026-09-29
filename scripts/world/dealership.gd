extends RefCounted
## The BEMZE dealership on the lot off the highway (exit at station 760, or
## up Levee Rd from Magnolia Heights): a glass showroom with the flagship
## spinning on the turntable, two more cars inside, a row out front, the
## pylon, lot lights and flags. [E] at the sales desk opens the showroom menu.
## Kit pieces: tools/blender/build_bemze.py (Dealer_* + the cars).

const PropKit = preload("res://scripts/art/prop_kit.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const CarScript = preload("res://scripts/vehicle/car.gd")

const SHOWROOM := Vector2(30.0, 18.0)
const DRAW := 260.0                   # the display cars only draw this close (they're detailed)

var world
var b                                 # office builder (solid, add_interact, npc)
var root: Node3D
var turntable: Node3D
var center := Vector3.ZERO
var rot := -PI / 2                    # the showroom's glass front faces the lot entrance (-x)


func _init(w) -> void:
	world = w
	b = w.builder


func build(lot: Vector3) -> Node3D:
	root = Node3D.new()
	root.name = "Dealership"
	world.add_child(root)
	var kit := PropKit.has("Dealer_Showroom")
	# the showroom on the east side of the lot, its glass front to the entrances
	center = lot + Vector3(15.0, 0.0, 0.0)
	var basis := Basis(Vector3.UP, rot)
	var at := func(local: Vector3) -> Vector3:
		return center + basis * local
	if kit:
		PropKit.place("Dealer_Showroom", root, center, rot)
	else:
		b.box(Vector3(SHOWROOM.x, 0.1, SHOWROOM.y), center + Vector3(0, 0.05, 0), Color(0.85, 0.86, 0.88), false, root)
	# walls: back, left, right (a door for delivering cars), the glass front (the entrance), the roof
	for w in [[Vector3(0, 3.5, -8.85), Vector3(30, 7, 0.3)], [Vector3(-14.85, 3.5, 0), Vector3(0.3, 7, 18)],
			[Vector3(14.85, 3.5, -7.0), Vector3(0.3, 7, 4.0)], [Vector3(14.85, 3.5, 3.0), Vector3(0.3, 7, 12.0)],
			[Vector3(14.85, 5.4, -2.5), Vector3(0.3, 3.2, 5.0)],
			[Vector3(-8.5, 2.5, 8.94), Vector3(13.0, 5.0, 0.2)], [Vector3(8.5, 2.5, 8.94), Vector3(13.0, 5.0, 0.2)],
			[Vector3(0, 4.0, 8.94), Vector3(4.0, 2.0, 0.2)], [Vector3(0, 7.22, 1.0), Vector3(30.6, 0.45, 20.6)]]:
		b.solid(w[1], at.call(w[0]), root, rot)
		if not kit:
			b.box(w[1], at.call(w[0]), Color(0.3, 0.32, 0.36) if w[0].z < 8.0 else Color(0.6, 0.75, 0.85), false, root).rotation.y = rot
	var sign := Label3D.new()
	sign.visible = not kit                 # the kit's sign band has the lettering
	sign.text = "BEMZE"
	sign.font_size = 200
	sign.pixel_size = 0.012
	sign.outline_size = 0
	sign.modulate = Color(1, 1, 1)
	sign.position = at.call(Vector3(0, 6.0, 9.3))
	sign.rotation.y = rot
	root.add_child(sign)
	# the flagship spins on the turntable; two more on the floor
	var tt: Vector3 = at.call(Vector3(0, 0, -1.5))
	if PropKit.has("Dealer_Turntable"):
		PropKit.place("Dealer_Turntable", root, tt, rot)
	turntable = Node3D.new()
	turntable.position = tt + Vector3(0, 0.222, 0)
	root.add_child(turntable)
	_display("bz_m8", turntable, Vector3.ZERO, 0.6)
	b.solid(Vector3(5.0, 1.2, 5.0), tt + Vector3(0, 0.6, 0), root)
	_display("bz_m5", root, at.call(Vector3(-9.0, 0, -3.0)), rot + 0.5, true)
	_display("bz_m4", root, at.call(Vector3(9.0, 0, 4.0)), rot - 2.3, true)
	# the sales desk: [E] for the showroom menu
	var desk: Vector3 = at.call(Vector3(-8.0, 0, 5.0))
	if PropKit.has("Dealer_Desk"):
		PropKit.place("Dealer_Desk", root, desk, rot)
	var body: Node3D = b.solid(Vector3(2.2, 1.0, 0.9), desk + Vector3(0, 0.5, 0), root, rot)
	b.add_interact(body, "dealer", 0, "[E] Talk to sales: buy a BEMZE, pick your ride, respray")
	b.npc(at.call(Vector3(-8.0, 0, 4.0)), rot, "anchor", "", "idle")
	if PropKit.has("Dealer_KeyBox"):
		PropKit.place("Dealer_KeyBox", root, at.call(Vector3(-10.0, 1.4, -8.68)), rot)
	# the row out front, facing the road
	var row := ["bz_m3", "bz_m3t", "bz_m2", "bz_540i"]
	for k in row.size():
		var p: Vector3 = lot + Vector3(-18.0, 0, -15.0 + k * 10.0)
		_display(row[k], root, p, PI / 2 + 0.35, true)
	# pylon at the entrance, lights on the corners, flags along the road
	if PropKit.has("Dealer_Pylon"):
		PropKit.place("Dealer_Pylon", root, lot + Vector3(-26.0, 0, -17.0), 0.4)
		var pl := Label3D.new()
		pl.visible = false                 # the kit pylon carries the roundel + lettering
		pl.text = "BEMZE"
		pl.font_size = 64
		pl.pixel_size = 0.012
		pl.outline_size = 0
		pl.position = lot + Vector3(-26.0, 6.9, -17.0) + Basis(Vector3.UP, 0.4) * Vector3(0, 0, 0.31)
		pl.rotation.y = 0.4
		root.add_child(pl)
	for c in [Vector2(-28, -18), Vector2(28, -18), Vector2(-28, 18), Vector2(28, 18)]:
		if PropKit.has("Dealer_LotLight"):
			PropKit.place("Dealer_LotLight", root, lot + Vector3(c.x, 0, c.y), 0.0)
		b.solid(Vector3(0.3, 8.0, 0.3), lot + Vector3(c.x, 4.0, c.y), root)
	for k in 6:
		if PropKit.has("Dealer_Flag"):
			PropKit.place("Dealer_Flag", root, lot + Vector3(-24.0 + k * 7.0, 0, -19.0), randf_range(-0.4, 0.4))
	var lt := OmniLight3D.new()
	lt.position = at.call(Vector3(0, 6.0, 0))
	lt.omni_range = 20.0
	lt.light_energy = 1.2
	root.add_child(lt)
	return root


## A car on display: the real model (no physics), a solid box so you can't
## drive through it, and it only draws when you're near.
func _display(key: String, parent: Node3D, pos: Vector3, yaw: float, solid := false) -> void:
	var c = CarScript.new()
	c.preview = true
	c.setup(key, 0)
	c.position = pos
	c.rotation.y = yaw
	parent.add_child(c)
	for mi in c.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = DRAW
	if solid:
		b.solid(Vector3(1.95, 1.4, 4.9), pos + Vector3(0, 0.7, 0), root, yaw)


func tick(delta: float) -> void:
	if turntable:
		turntable.rotation.y += delta * 0.3
