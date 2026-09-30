extends Node
## Runtime side of Magnolia Heights (built by NeighborhoodBuilder): the
## realtor's signs and panel, front doors and keys, mailbox name plates, taxi
## rides between downtown / the neighborhood / your house, interiors that only
## draw when you're close, and hiding the far-away office while you're out here.
##
## World calls interact() for any "hood_*" interactable and asks ui_open()
## (through the HUD) so the mouse is free while a panel is up.

const Rules = preload("res://scripts/sim/rules.gd")
const RealtorUI = preload("res://scripts/ui/realtor_ui.gd")
const UI = preload("res://scripts/ui/ui_theme.gd")
const Brands = preload("res://scripts/sim/brands.gd")
const LOOP_BRANDS := ["mercedez", "porsha", "audy"]    # ride destinations: the dealerships round the loop

const KNOCK := ["Nobody answers.", "A dog goes off inside. Nobody comes.", "\"WE DON'T WANT ANY!\"",
	"You hear a TV. Nobody gets up.", "A curtain moves. The door stays shut.", "\"If this is about the car's extended warranty...\""]

var world
var hood                    # NeighborhoodBuilder (data + nodes)
var m                       # Match
var ui
var riding := false
var _fade: ColorRect
var _sig := ""
var _t := 0.0
var _office: Array = []     # the office's merged batches (hidden while you're far away)
var _office_shown := true


func setup(w) -> void:
	world = w
	hood = w.builder.hood
	m = w.match_node
	ui = RealtorUI.new()
	w.hud.root.add_child(ui)
	ui.buy_pressed.connect(_on_buy)
	ui.ride_pressed.connect(func(dest: String): ride(dest))
	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.color = Color(0, 0, 0, 0)
	w.hud.root.add_child(_fade)
	m.state_changed.connect(refresh)
	Net.players_changed.connect(refresh)
	var block := Rect2(-56.0, 216.0, 112.0, 48.0)     # the downtown street block
	for c in w.builder.root.get_children():
		if c is MeshInstance3D and c.mesh != null:
			var ab: AABB = c.get_aabb()
			var center: Vector3 = c.global_transform * ab.get_center()
			if center.z < 100.0:
				_office.append(c)
	# the downtown block is thousands of little batches: past 330 m the neighborhood
	# builder's impostor stands in for it (visibility ranges: no per-frame work)
	for gi in w.builder.root.find_children("*", "GeometryInstance3D", true, false):
		if gi.is_ancestor_of(hood.root) or hood.root.is_ancestor_of(gi) or gi == hood.root:
			continue
		var g: GeometryInstance3D = gi
		if g.visibility_range_end > 0.0:
			continue
		var ctr: Vector3 = g.global_transform * g.get_aabb().get_center()
		if block.has_point(Vector2(ctr.x, ctr.z)) and ctr.y < 40.0:
			g.visibility_range_end = 350.0
			g.visibility_range_end_margin = 20.0
	refresh()


# ------------------------------------------------------------------ queries

func me() -> int:
	return Net.my_id()


func house(id: String) -> Dictionary:
	return hood.houses[hood.buyable[id]] if hood.buyable.has(id) else {}


func in_neighborhood(node: Node3D) -> bool:
	return node != null and hood.in_hood(node.global_position)


## Which for-sale house (id) this node is standing inside, or "".
func inside_house(node: Node3D) -> String:
	return inside_house_at(node.global_position) if node != null else ""


func inside_house_at(pos: Vector3) -> String:
	for id in hood.buyable:
		var h: Dictionary = house(id)
		var local: Vector3 = (h.xf as Transform3D).affine_inverse() * pos
		var T: Dictionary = hood.layout.types[h.type]
		if absf(local.x) < float(T.W) / 2.0 and local.z < 0.0 and local.z > -float(T.D) and local.y > float(T.FH) - 0.3:
			return id
	return ""


static func price_str(v: float) -> String:
	return RealtorUI.price_str(v)


# ------------------------------------------------------------------ state -> world

## Signs, doors, mailboxes and prompts follow who owns what (m.owned).
func refresh() -> void:
	# people on foot count as (slow) vehicles for the traffic: cars stop for you
	if hood.traffic and world.players_node:
		for pn in world.players_node.get_children():
			hood.traffic.register_obstacle(pn, 0.8, 0.8)
	var sig := ""
	for id in hood.buyable:
		sig += "%s:%d;" % [id, m.house_owner(id)]
	sig += str(Net.players.keys())
	if sig == _sig:
		return
	_sig = sig
	for id in hood.buyable:
		var h: Dictionary = house(id)
		var owner: int = m.house_owner(id)
		var mine := owner != 0 and owner == me()
		var who := Net.player_name(owner).to_upper() if owner != 0 else ""
		for ls in h.sign_labels:
			(ls[0] as Label3D).text = "FOR SALE" if owner == 0 else "SOLD"
			(ls[1] as Label3D).text = price_str(h.price) if owner == 0 else "to %s" % who
			(ls[3] as Label3D).text = "OPEN HOUSE" if owner == 0 else ("YOURS" if mine else "SOLD")
		var sb: StaticBody3D = h.sign_body
		sb.set_meta("prompt", "[E] %s — %s" % [h.address, price_str(h.price) if owner == 0 else "SOLD to " + Net.player_name(owner)])
		if h.mailbox_label:
			(h.mailbox_label as Label3D).text = who
		var body: StaticBody3D = h.door.get_node("Body")
		if owner == 0:
			h.door_open = 1.62                         # open house: walk right in
			_clear_interact(body)
		elif mine:
			if h.get("was_owner", 0) != owner:
				h.door_open = 0.0                      # your house: locked until you use the key
			body.set_meta("interact", "hood_door")
			body.set_meta("interact_id", hood.buyable[id])
			body.set_meta("prompt", "[E] Home sweet home")
		else:
			h.door_open = 0.0
			body.set_meta("interact", "hood_knock")
			body.set_meta("interact_id", hood.buyable[id])
			body.set_meta("prompt", "[E] Knock (%s's place)" % Net.player_name(owner))
		h.was_owner = owner
		if h.screen:
			(h.screen as Node3D).rotation.y = _rot(h) - (1.7 if owner == 0 or mine else 0.0)
			var sbody: StaticBody3D = (h.screen as Node3D).get_node("Body")
			sbody.collision_layer = 1


func _clear_interact(sb: StaticBody3D) -> void:
	for k in ["interact", "interact_id", "prompt"]:
		if sb.has_meta(k):
			sb.remove_meta(k)


func _rot(h: Dictionary) -> float:
	return float(h.rot)


func _process(delta: float) -> void:
	# swing doors toward where they should be
	for id in hood.buyable:
		var h: Dictionary = house(id)
		var d: Node3D = h.door
		var want: float = _rot(h) + float(h.door_open)
		d.rotation.y = rotate_toward(d.rotation.y, want, delta * 2.4)
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.2
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	# interiors (and their lamps) only exist for you when you're close
	for id in hood.buyable:
		var h: Dictionary = house(id)
		var near: bool = cp.distance_to((h.xf as Transform3D).origin) < hood.INT_RANGE + 12.0
		if (h.interior as Node3D).visible != near:
			(h.interior as Node3D).visible = near
	# out here the office is 700 m away behind you: don't draw it
	var show_office := cp.z < 150.0
	if show_office != _office_shown:
		_office_shown = show_office
		for mi in _office:
			if is_instance_valid(mi):
				mi.visible = show_office
	# and in the office, the neighborhood doesn't exist
	(hood.root as Node3D).visible = cp.z > 120.0


# ------------------------------------------------------------------ interaction

func ui_open() -> bool:
	return ui != null and ui.is_open()


func close_ui() -> void:
	if ui:
		ui.close()


func interact(t: Dictionary) -> void:
	var type: String = t.get("type", "")
	var idx := int(t.get("id", 0))
	match type:
		"hood_sign":
			_open_listing(idx)
		"hood_taxi":
			open_taxi(idx)
		"hood_door":
			var h: Dictionary = hood.houses[idx]
			if m.house_owner(h.id) == me():
				h.door_open = 0.0 if float(h.door_open) > 0.5 else 1.62
				if float(h.door_open) > 0.5:
					world.hud.show_toast("Home sweet home. %s." % h.address, Color(0.6, 1.0, 0.7))
					Sfx.play("bell", -14.0, 2.2)
				_update_door_prompt(h)
		"hood_knock":
			var h2: Dictionary = hood.houses[idx]
			var owner: int = m.house_owner(h2.id) if h2.id != "" else 0
			if owner != 0:
				world.hud.show_toast("You knock. %s isn't home — probably at the office." % Net.player_name(owner))
			else:
				world.hud.show_toast(KNOCK[(idx + int(Time.get_ticks_msec() / 997)) % KNOCK.size()])


func _update_door_prompt(h: Dictionary) -> void:
	var body: StaticBody3D = h.door.get_node("Body")
	body.set_meta("prompt", "[E] Close the door" if float(h.door_open) > 0.5 else "[E] Home sweet home")


func _open_listing(idx: int) -> void:
	var h: Dictionary = hood.houses[idx]
	var def: Dictionary = Rules.HOUSES[h.id]
	var owner: int = m.house_owner(h.id)
	var a: Dictionary = m.my_acct()
	var bal: float = float(a.get("balance", 0.0))
	var mine_id: String = m.house_of(me())
	world.hud.close_modals()
	ui.open_listing({"id": h.id, "name": def.name, "address": h.address, "price": h.price, "desc": def.desc,
		"owner_name": Net.player_name(owner) if owner != 0 else "", "mine": owner == me() and owner != 0,
		"can_afford": bal >= h.price, "balance": bal,
		"my_other": house(mine_id).get("address", "") if mine_id != "" and mine_id != h.id else ""})


func _on_buy(id: String) -> void:
	m.request_buy_house(id)
	ui.close()


func open_taxi(stand: int) -> void:
	var opts: Array = []
	if stand != 0:
		opts.append(["downtown", "DOWNTOWN — BAGHOLDER CAPITAL (the office)"])
	if stand != 1:
		opts.append(["hood", "MAGNOLIA HEIGHTS — the neighborhood"])
	var mine: String = m.house_of(me())
	if mine != "":
		opts.append(["home", "MY HOUSE — %s" % house(mine).address])
	opts.append(["dealer", "BEMZE MOTORS — the dealership off the highway"])
	for br in LOOP_BRANDS:
		opts.append([br, "%s — round the loop, exit %d" % [str(Brands.BRANDS[br].motors).to_upper(), int(Brands.BRANDS[br].exit)]])
	world.hud.close_modals()
	ui.open_taxi(hood.taxi[stand].name, opts)


# ------------------------------------------------------------------ rides

## Fade out, "riding...", teleport, fade in. instant = no fade (tests).
func ride(dest: String, instant := false) -> bool:
	var p = world.local_player
	if p == null or riding:
		return false
	if m.is_jailed(me()):
		world.hud.show_toast("The cops aren't letting you call a ride.", Color(1, 0.3, 0.3))
		return false
	var rush: bool = m.phase == "morning" or m.is_late(me())
	if rush and m.car_of(me()) != "":
		world.hud.show_toast("Rush hour: no cabs for you. Your car's in the driveway. DRIVE.", Color(1, 0.6, 0.3))
		return false
	# a real cab: it pulls up here and drives you there (CabRide); instant = the old fade (tests)
	if not instant and world.cab != null and p.driving == null and world.cab.plan(dest).size() >= 4:
		if rush:
			m.request_cab()      # no car: the meter runs (and rush hour's slow)
		close_ui()
		return world.cab.start(dest, rush)
	if rush:                     # no car: the cab crawls through rush hour and the meter runs
		m.request_cab()
		world.hud.blackout(Rules.CAB_RIDE_S, "In a cab. Bumper to bumper.\nThe meter says $%d." % int(Rules.CAB_FARE))
		instant = true
	var where := _dest(dest)
	if where.is_empty():
		world.hud.show_toast("You don't own a house yet. Magnolia Heights has listings.", Color(1, 0.8, 0.4))
		return false
	close_ui()
	if instant:
		_arrive(p, where)
		return true
	riding = true
	world.hud.show_toast("Riding to %s..." % where.name, Color(1.0, 0.85, 0.3))
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.35)
	tw.tween_callback(func(): _arrive(p, where))
	tw.tween_interval(0.55)
	tw.tween_property(_fade, "color:a", 0.0, 0.45)
	tw.tween_callback(func(): riding = false)
	return true


func _dest(dest: String) -> Dictionary:
	match dest:
		"downtown":
			return {"pos": hood.taxi[0].pos, "yaw": hood.taxi[0].yaw, "name": "downtown"}
		"hood":
			return {"pos": hood.taxi[1].pos, "yaw": hood.taxi[1].yaw, "name": "Magnolia Heights"}
		"dealer":
			var dr: PackedVector3Array = hood.hw.paths["dealer_road"].pts
			return {"pos": dr[0] + Vector3(-2.0, 0.3, -8.0), "yaw": 0.0, "name": "BEMZE Motors"}
		"home":
			var id: String = m.house_of(me())
			if id == "":
				return {}
			var h: Dictionary = house(id)
			return {"pos": h.spawn, "yaw": h.spawn_yaw, "name": h.address, "home": id}
	if dest in LOOP_BRANDS and hood.hw.dealers.has(dest):
		# by the showroom door, facing it
		var stop: Vector3 = hood.hw.dealers[dest].stop
		return {"pos": stop + Vector3(3.0, 0.3, -2.0), "yaw": 0.0, "name": str(Brands.BRANDS[dest].motors), "brand": dest}
	return {}


func _arrive(p, where: Dictionary) -> void:
	if p.seat >= 0:
		p.stand_up()
	p.teleport(where.pos)
	p.rotation.y = where.yaw
	p.pitch = 0.0
	if p.head:
		p.head.rotation.x = 0.0
	if where.has("home"):
		world.hud.show_toast("You wake up at home. The alarm clock says you're LATE.", Color(1.0, 0.5, 0.4))
	elif where.name == "downtown":
		world.hud.show_toast("Downtown. The BAGHOLDER CAPITAL lobby is up the block.", Color(0.95, 0.9, 0.6))
	elif where.name == "BEMZE Motors":
		world.hud.show_toast("BEMZE Motors. Sales is inside, at the desk.", Color(0.5, 0.75, 1.0))
	elif where.has("brand"):
		world.hud.show_toast("%s. Sales is inside, at the desk." % where.name, Brands.BRANDS[where.brand].ui)
	else:
		world.hud.show_toast("Magnolia Heights. Starter homes, cheap-ish. Look for the FOR SALE signs.", Color(0.7, 1.0, 0.7))


func go_to_neighborhood(instant := false) -> bool:
	return ride("hood", instant)


func go_home(instant := false) -> bool:
	return ride("home", instant)


func go_downtown(instant := false) -> bool:
	return ride("downtown", instant)
