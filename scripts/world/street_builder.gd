extends RefCounted
## The street outside BAGHOLDER CAPITAL: a city block at ground level with a
## road, sidewalks, parked parody cars and a row of stores on each side that
## you can walk into and use. Built with the office builder's helpers (props,
## colliders, labels, interact metadata, NPCs), far from the office so neither
## is ever on screen from the other.
##
## Brands are the owner's parodies (docs/BRANDS.md).
##
## Local layout (x along the road, +z = south):
##   road z -5..5, sidewalks 5..9, storefronts at |z| = 9, shops 8 m deep.

const ORIGIN := Vector3(0, 0, 240)
const ROAD_HALF := 5.0
const WALK := 9.0
const SHOP_DEPTH := 8.0
const HALF_LEN := 36.0
const SIDEWALK_H := 0.12
const PropKit = preload("res://scripts/art/prop_kit.gd")
const Character = preload("res://scripts/art/character.gd")

## The two rows of stores. kind -> what E does inside:
##   lux:<store>  boutique counter (luxury catalog filtered to that store)
##   items        Tony's Deli (the item shop)
##   tailor       change your look (synced to everyone)
##   pawn         sell your flex back for cash
##   casino       slot machines
##   lobby        the BAGHOLDER CAPITAL lobby: elevator back up to floor 12
##   none         for lease
const NORTH := [
	{"x": -30.0, "prop": "Store_Guccero", "upper": "Upper_Dark", "name": "GUCCERO", "sub": "", "kind": "lux:guccero",
		"sign": Color(0.9, 0.75, 0.3), "floor": Color(0.12, 0.12, 0.13), "wall": Color(0.14, 0.14, 0.15)},
	{"x": -18.0, "prop": "Store_Valmont", "upper": "Upper_Stone", "name": "LOUIS VALMONT", "sub": "VM", "kind": "lux:valmont",
		"sign": Color(0.95, 0.8, 0.45), "floor": Color(0.42, 0.28, 0.16), "wall": Color(0.6, 0.45, 0.3)},
	{"x": -6.0, "prop": "Store_Lobby", "upper": "Upper_Glass", "name": "BAGHOLDER CAPITAL", "sub": "EST. 2025", "kind": "lobby",
		"sign": Color(0.95, 0.95, 0.97), "floor": Color(0.7, 0.7, 0.72), "wall": Color(0.62, 0.64, 0.68)},
	{"x": 6.0, "prop": "Store_Prava", "upper": "Upper_Dark", "name": "PRAVA", "sub": "MILANO", "kind": "lux:prava",
		"sign": Color(0.85, 0.87, 0.9), "floor": Color(0.1, 0.1, 0.11), "wall": Color(0.2, 0.2, 0.22)},
	{"x": 18.0, "prop": "Store_Crownwell", "upper": "Upper_Stone", "name": "CROWNWELL", "sub": "GENÈVE", "kind": "lux:crownwell",
		"sign": Color(1.0, 0.8, 0.3), "floor": Color(0.1, 0.25, 0.16), "wall": Color(0.88, 0.85, 0.78)},
	{"x": 30.0, "prop": "Store_Diorelle", "upper": "Upper_Stone", "name": "DIORÉLLE", "sub": "PARIS", "kind": "lux:diorelle",
		"sign": Color(0.25, 0.22, 0.2), "floor": Color(0.9, 0.88, 0.84), "wall": Color(0.96, 0.94, 0.9)},
]
const SOUTH := [
	{"x": -30.0, "prop": "Store_Pawn", "upper": "Upper_Brick", "name": "PAWN KING", "sub": "WE BUY FLEX", "kind": "pawn",
		"sign": Color(0.1, 0.1, 0.1), "floor": Color(0.45, 0.44, 0.42), "wall": Color(0.7, 0.68, 0.62)},
	{"x": -18.0, "prop": "Store_Deli", "upper": "Upper_Brick", "name": "TONY'S DELI", "sub": "ask about the specials", "kind": "items",
		"sign": Color(0.97, 0.95, 0.9), "floor": Color(0.85, 0.85, 0.8), "wall": Color(0.93, 0.9, 0.82)},
	{"x": -6.0, "prop": "Store_Tailor", "upper": "Upper_Stone", "name": "THE TAILOR", "sub": "BESPOKE · SINCE 1987", "kind": "tailor",
		"sign": Color(1.0, 0.85, 0.4), "floor": Color(0.4, 0.28, 0.18), "wall": Color(0.2, 0.25, 0.4)},
	{"x": 6.0, "prop": "Store_Casino", "upper": "Upper_Dark", "name": "DEGEN CASINO", "sub": "", "kind": "casino",
		"sign": Color(1.0, 0.8, 0.2), "floor": Color(0.35, 0.05, 0.1), "wall": Color(0.2, 0.06, 0.28)},
	{"x": 18.0, "prop": "Store_Chavel", "upper": "Upper_Dark", "name": "CHAVÉL", "sub": "", "kind": "lux:chavel",
		"sign": Color(0.05, 0.05, 0.05), "floor": Color(0.95, 0.95, 0.95), "wall": Color(0.1, 0.1, 0.1)},
	{"x": 30.0, "prop": "Store_Empty", "upper": "Upper_Brick", "name": "FOR LEASE", "sub": "coming soon: BENTLEE dealership", "kind": "none",
		"sign": Color(0.2, 0.2, 0.2), "floor": Color(0.5, 0.5, 0.5), "wall": Color(0.75, 0.73, 0.7)},
]

var b                      # office builder (helpers + interactables list)
var root: Node3D
var spawn := ORIGIN + Vector3(-6.0, 0.25, -7.0)      # in front of the lobby
var lobby_exit := spawn
var hotdog_pos := Vector3.ZERO
var slot_bodies: Array = []


func _init(builder) -> void:
	b = builder


func P(x: float, y: float, z: float) -> Vector3:
	return ORIGIN + Vector3(x, y, z)


func build() -> Node3D:
	root = Node3D.new()
	root.name = "Street"
	b.root.add_child(root)
	_ground()
	for s in NORTH:
		_store(s, -1)
	for s in SOUTH:
		_store(s, 1)
	_ends()
	_furniture()
	_cars()
	_skyline()
	_people()
	var o := OmniLight3D.new()   # soft fill so shaded fronts aren't black
	o.position = P(0, 8, 0)
	o.omni_range = 60.0
	o.light_energy = 0.35
	root.add_child(o)
	# the street is lit by the sun (layer 2), unlike the office
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1 | b.SKY_LAYER
	b = null   # the office builder keeps us; don't keep it back (RefCounted cycle leaks)
	return root


# ---------------------------------------------------------------- ground

func _ground() -> void:
	var asphalt := Color(0.2, 0.21, 0.23)
	b.box(Vector3(HALF_LEN * 2 + 8, 0.2, ROAD_HALF * 2), P(0, -0.1, 0), asphalt, true, root)
	# lane markings: dashed yellow center, white edge lines
	var x := -HALF_LEN
	while x < HALF_LEN:
		b.box(Vector3(2.0, 0.01, 0.14), P(x + 1.0, 0.005, 0), Color(0.95, 0.8, 0.15), false, root)
		x += 4.0
	for z in [-ROAD_HALF + 0.3, ROAD_HALF - 0.3]:
		b.box(Vector3(HALF_LEN * 2, 0.01, 0.12), P(0, 0.005, z), Color(0.9, 0.9, 0.9), false, root)
	# crosswalks
	for cx in [-12.0, 12.0]:
		for k in 8:
			b.box(Vector3(3.0, 0.012, 0.5), P(cx, 0.006, -3.5 + k * 1.0), Color(0.93, 0.93, 0.93), false, root)
	# sidewalks (raised, with a walkable ramp along the curb) + curbs
	for side in [-1, 1]:
		var zc: float = side * (ROAD_HALF + WALK) / 2.0
		b.box(Vector3(HALF_LEN * 2 + 8, SIDEWALK_H, WALK - ROAD_HALF), P(0, SIDEWALK_H / 2, zc), Color(0.62, 0.62, 0.6), true, root)
		b.box(Vector3(HALF_LEN * 2 + 8, SIDEWALK_H + 0.02, 0.16), P(0, (SIDEWALK_H + 0.02) / 2, side * (ROAD_HALF + 0.08)),
				Color(0.5, 0.5, 0.5), false, root)
		var ramp: Node3D = b.solid(Vector3(HALF_LEN * 2 + 8, 0.05, 0.6), P(0, SIDEWALK_H / 2 - 0.02, side * (ROAD_HALF - 0.2)), root)
		ramp.rotation.x = side * -0.2
		# slab joints
		var jx := -HALF_LEN
		while jx < HALF_LEN:
			b.box(Vector3(0.03, 0.005, WALK - ROAD_HALF), P(jx, SIDEWALK_H + 0.002, zc), Color(0.5, 0.5, 0.48), false, root)
			jx += 2.0


# ---------------------------------------------------------------- stores

## A storefront + 3 floors above + a walk-in shop behind it.
## side -1 = north row (faces +z), +1 = south row (faces -z).
func _store(s: Dictionary, side: int) -> void:
	var x: float = s.x
	var rot := 0.0 if side < 0 else PI
	var face_z: float = side * WALK                       # street-side face of the facade
	var back_z: float = side * (WALK + 0.4)               # facade origin (its back)
	b.prop(s.prop, P(x, 0, back_z), rot, root)
	for k in 3:
		b.prop(s.upper, P(x, 4.4 + k * 9.0, back_z), rot, root)
	# facade colliders (pillars + lintel), door gap in the middle
	b.solid(Vector3(3.9, 4.4, 0.4), P(x - 3.05, 2.2, side * (WALK + 0.2)), root)
	b.solid(Vector3(3.9, 4.4, 0.4), P(x + 3.05, 2.2, side * (WALK + 0.2)), root)
	b.solid(Vector3(2.2, 1.6, 0.4), P(x, 3.6, side * (WALK + 0.2)), root)
	# sign
	var sign: Label3D = b.label(s.name, P(x, 3.66 if s.sub == "" else 3.76, face_z - side * 0.16), 96 if s.name.length() < 12 else 70,
			s.sign, rot, root)
	sign.outline_size = 0
	sign.pixel_size = 0.006
	if s.sub != "":
		var sub: Label3D = b.label(s.sub, P(x, 3.36, face_z - side * 0.16), 30, s.sign, rot, root)
		sub.outline_size = 0
		sub.pixel_size = 0.006
	# the shop behind: floor, walls, ceiling, light
	var zin: float = side * (WALK + 0.4 + SHOP_DEPTH / 2)
	b.box(Vector3(10, 0.2, SHOP_DEPTH), P(x, -0.1 + SIDEWALK_H, zin), s.floor, true, root)
	b.box(Vector3(10, 0.2, SHOP_DEPTH), P(x, 4.3, zin), Color(0.9, 0.9, 0.9), false, root)
	b.box(Vector3(10, 4.4, 0.2), P(x, 2.2, side * (WALK + 0.4 + SHOP_DEPTH)), s.wall, true, root)
	for dx in [-5.0, 5.0]:
		b.box(Vector3(0.2, 4.4, SHOP_DEPTH), P(x + dx, 2.2, zin), s.wall, true, root)
	var lt := OmniLight3D.new()
	lt.position = P(x, 3.6, zin)
	lt.omni_range = 9.0
	lt.light_energy = 1.1
	lt.light_color = Color(1, 0.96, 0.9)
	root.add_child(lt)
	b.prop("CeilingLight", P(x, 4.2, zin), 0.0, root)
	var inner := func(dx: float, dz: float) -> Vector3:   # position inside, dz from the facade inward
		return P(x + dx, SIDEWALK_H, side * (WALK + 0.4 + dz))
	var facing := PI if side < 0 else 0.0              # props/NPCs inside face the door
	match str(s.kind).get_slice(":", 0):
		"lux":
			_boutique(s, inner, facing, side)
		"items":
			_counter_shop(inner, facing, side, "items", "[E] Tony's Deli", "trader")
			for k in 3:
				b.prop("ShopShelf", inner.call(-3.8, 1.5 + k * 2.2), facing + PI / 2 * side, root)
		"tailor":
			_counter_shop(inner, facing, side, "tailor", "[E] Get fitted (change your look)", "flex")
			for k in 2:
				b.prop("ClothesRack", inner.call(-3.2, 2.5 + k * 3.0), facing + PI / 2, root)
				b.prop("ClothesRack", inner.call(3.2, 2.5 + k * 3.0), facing + PI / 2, root)
			_mannequin(inner.call(3.2, 1.2), facing, {"suit": Color(0.4, 0.1, 0.12), "hair_style": "bald"})
			_mannequin(inner.call(-3.2, 1.2), facing, {"suit": Color(0.14, 0.16, 0.3), "hair_style": "bald", "tie": Color(0.9, 0.7, 0.1)})
		"pawn":
			_counter_shop(inner, facing, side, "pawn", "[E] Pawn your flex (50% back)", "beard")
			for k in 3:
				b.prop("ShopShelf", inner.call(3.8, 1.5 + k * 2.2), facing - PI / 2 * side, root)
		"casino":
			for k in 4:
				var sm := Node3D.new()
				sm.position = inner.call(-3.3 + k * 2.2, SHOP_DEPTH - 1.2)
				sm.rotation.y = facing + PI   # the machine model faces -z
				root.add_child(sm)
				b.prop("SlotMachine", Vector3.ZERO, 0.0, sm)
				var body: Node3D = b.solid(Vector3(1.1, 1.9, 0.9), Vector3(0, 0.95, 0), sm)
				b.add_interact(body, "slots", 10 + k, "[E] Play slots")
				slot_bodies.append(body)
		"lobby":
			b.prop("Elevator", inner.call(0, SHOP_DEPTH - 0.15), facing, root)
			var door: Node3D = b.solid(Vector3(2.3, 2.4, 0.3), inner.call(0, SHOP_DEPTH - 0.4) + Vector3(0, 1.2, 0), root)
			b.add_interact(door, "elevator_up", 0, "[E] Elevator to the 12th floor (trading floor)")
			var fl12: Label3D = b.label("12 ▲", inner.call(0, SHOP_DEPTH - 0.4) + Vector3(0, 2.5, 0), 40, Color(0.2, 1, 0.3), facing, root)
			fl12.outline_size = 0
			b.prop("Plant", inner.call(-4.0, 1.0), 0.0, root)
			b.prop("Plant", inner.call(4.0, 1.0), 0.0, root)
			b.prop("Couch", inner.call(-3.8, 4.0), facing + PI / 2 * side, root)
			b.npc(inner.call(3.0, 3.5), facing, "cop", "SECURITY", "idle")
			lobby_exit = P(x, 0.25, side * (WALK - 1.5))
			spawn = lobby_exit
		"none":
			b.prop("PaperBall", inner.call(1.0, 3.0), 0.0, root)


func _counter_shop(inner: Callable, facing: float, side: int, type: String, prompt: String, clerk: String) -> void:
	var at: Vector3 = inner.call(0, SHOP_DEPTH - 2.2)
	b.prop("ShopCounter", at, facing, root)
	var c: Node3D = b.solid(Vector3(2.4, 1.05, 0.6), at + Vector3(0, 0.52, 0), root, facing)
	b.add_interact(c, type, 0, prompt)
	b.npc(inner.call(0, SHOP_DEPTH - 1.2), facing, clerk, "", "idle")


func _boutique(s: Dictionary, inner: Callable, facing: float, side: int) -> void:
	var store: String = str(s.kind).get_slice(":", 1)
	var at: Vector3 = inner.call(0, SHOP_DEPTH - 2.0)
	b.prop("FlexCounter", at, facing, root)
	var c: Node3D = b.solid(Vector3(2.2, 1.0, 0.7), at + Vector3(0, 0.5, 0), root, facing)
	b.add_interact(c, "lux", ["guccero", "valmont", "prava", "crownwell", "diorelle", "chavel"].find(store),
			"[E] Shop %s" % s.name)
	b.npc(inner.call(0, SHOP_DEPTH - 1.0), facing, "fed" if store in ["prava", "chavel"] else "anchor", "", "idle")
	# display: mannequins in the window + racks along the walls
	var looks := {
		"guccero": {"suit": Color(0.1, 0.35, 0.2), "tie": Color(0.75, 0.08, 0.1)},
		"valmont": {"suit": Color(0.45, 0.3, 0.17), "tie": Color(0.95, 0.8, 0.45)},
		"prava": {"suit": Color(0.06, 0.06, 0.07), "tie": Color(0.06, 0.06, 0.07), "glasses": "shades"},
		"crownwell": {"suit": Color(0.05, 0.28, 0.16), "watch": "gold"},
		"diorelle": {"suit": Color(0.94, 0.91, 0.84), "tie": Color(0.2, 0.2, 0.25)},
		"chavel": {"suit": Color(0.95, 0.95, 0.95), "outfit": "shirt", "chain": true},
	}
	var lk: Dictionary = looks.get(store, {}).duplicate()
	lk["hair_style"] = "bald"
	_mannequin(inner.call(-3.0, 1.3), facing, lk)
	_mannequin(inner.call(3.0, 1.3), facing, lk)
	b.prop("ClothesRack", inner.call(-4.0, 4.5), facing + PI / 2, root)
	b.prop("ClothesRack", inner.call(4.0, 4.5), facing + PI / 2, root)


## A display mannequin: a character in the store's clothes, frozen in place.
func _mannequin(pos: Vector3, facing: float, look: Dictionary) -> void:
	var m = Character.new()
	m.name = "Model"
	look["skin"] = Color(0.92, 0.92, 0.9)
	look["watch"] = look.get("watch", "none")
	m.build(look)
	m.position = pos
	m.rotation.y = facing + PI
	m.eyes_open = 0.0
	root.add_child(m)
	b.box(Vector3(0.6, 0.08, 0.6), pos + Vector3(0, 0.04, 0), Color(0.2, 0.2, 0.22), false, root)


# ---------------------------------------------------------------- the rest of the block

func _ends() -> void:
	# end-of-block buildings close the street off (you can see the city beyond)
	for sx in [-1, 1]:
		var ex: float = sx * (HALF_LEN + 4.2)
		b.box(Vector3(0.4, 30, 40), P(ex, 15, 0), Color(0.55, 0.3, 0.22), true, root)
		for k in 8:
			b.box(Vector3(0.05, 1.8, 1.4), P(ex - sx * 0.22, 6.0 + (k / 4) * 6.0, -9 + (k % 4) * 6.0), Color(0.55, 0.7, 0.85), false, root)
	b.solid(Vector3(HALF_LEN * 2, 6, 0.4), P(0, 3, -(WALK + SHOP_DEPTH + 1)), root)
	b.solid(Vector3(HALF_LEN * 2, 6, 0.4), P(0, 3, WALK + SHOP_DEPTH + 1), root)


func _furniture() -> void:
	for side in [-1, 1]:
		var z: float = side * (ROAD_HALF + 0.7)
		var x := -33.0
		while x <= 33.0:
			b.prop("StreetLamp", P(x, SIDEWALK_H, z), 0.0 if side > 0 else PI, root)
			b.solid(Vector3(0.2, 5.0, 0.2), P(x, 2.5, z), root)
			x += 12.0
		for tx in [-24.0, 0.0, 24.0]:
			b.prop("Tree", P(tx, SIDEWALK_H, z), 0.0, root)
			b.solid(Vector3(1.2, 0.5, 1.2), P(tx, 0.3, z), root)
		b.prop("Bench", P(-12.0 + side * 3.0, SIDEWALK_H, side * (WALK - 1.0)), 0.0 if side > 0 else PI, root)
		b.prop("Hydrant", P(9.0 * side, SIDEWALK_H, z), 0.0, root)
		b.prop("Trash", P(-3.0 * side, SIDEWALK_H, z), 0.0, root)
	for cx in [-12.0, 12.0]:
		for side in [-1, 1]:
			b.prop("TrafficLight", P(cx + side * 2.2, SIDEWALK_H, side * (ROAD_HALF + 0.5)), 0.0 if side > 0 else PI, root)
	# hot dog cart: cheap snack, calms your blood pressure
	hotdog_pos = P(2.0, SIDEWALK_H, -(ROAD_HALF + 1.6))
	b.prop("HotDogCart", hotdog_pos, 0.0, root)
	var cart: Node3D = b.solid(Vector3(1.6, 1.3, 0.8), hotdog_pos + Vector3(0, 0.65, 0), root)
	b.add_interact(cart, "hotdog", 0, "[E] Hot dog $20 (calms your blood pressure)")
	var hl: Label3D = b.label("HOT DOGS $20", hotdog_pos + Vector3(0, 0.8, 0.43), 40, Color(0.8, 0.1, 0.1), 0.0, root)
	hl.outline_size = 0
	hl.pixel_size = 0.004
	b.npc(hotdog_pos + Vector3(0.0, 0, -0.9), 0.0, "beard", "", "idle")


func _cars() -> void:
	# parked along both curbs, badges from the owner's parody car makers
	var parked := [["Car_Torola", "TOROLA"], ["Car_Lambargamber", "LAMBARGAMBER"], ["Car_Bemze", "BEMZE"],
		["Car_Taxi", "TAXI"], ["Car_Mercedez", "MERCEDEZ BANZ"], ["Car_Ferrazi", "FERRAZI"],
		["Car_Bentlee", "BENTLEE"], ["Car_Porsha", "PORSHA"]]
	var i := 0
	for side in [-1, 1]:
		for k in 4:
			var cx := -27.0 + k * 16.0 + (6.0 if side > 0 else 0.0)
			var c: Array = parked[i % parked.size()]
			i += 1
			var rot: float = PI / 2 if side > 0 else -PI / 2
			var pos := P(cx, 0, side * (ROAD_HALF - 1.4))
			b.prop(c[0], pos, rot, root)
			b.solid(Vector3(4.6, 1.4, 1.9), pos + Vector3(0, 0.7, 0), root, rot + PI / 2)
			var badge: Label3D = b.label(c[1], pos + Vector3(-sin(rot) * -2.33, 0.75, -cos(rot) * -2.33), 40,
					Color(0.95, 0.95, 0.97), rot, root)
			badge.pixel_size = 0.0035
			badge.outline_size = 4


func _skyline() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var kinds := ["TowerA", "TowerB", "TowerC", "TowerD"]
	for i in 26:
		var sx := r.randf_range(-110, 110)
		var sz := (r.randf_range(35, 90)) * (1 if r.randf() < 0.5 else -1)
		if absf(sx) < 45 and absf(sz) < 30:
			continue
		var pos := P(sx, 0, sz)
		PropKit.place(kinds[r.randi() % kinds.size()], root, pos, (r.randi() % 4) * PI / 2, r.randf_range(0.8, 1.4),
				clampf((Vector2(sx, sz).length() - 30.0) / 110.0, 0.0, 0.7))


## A few pedestrians hanging around the sidewalks.
func _people() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for k in 6:
		var side := -1 if k % 2 == 0 else 1
		var pos := P(-28.0 + k * 11.0, SIDEWALK_H, side * (ROAD_HALF + 2.5))
		var m = Character.new()
		m.name = "Model"
		m.build(Character.random_look(r))
		m.position = pos
		m.rotation.y = r.randf_range(-PI, PI)
		m.pose = ["idle", "hold", "smoke", "idle"][k % 4]
		root.add_child(m)
