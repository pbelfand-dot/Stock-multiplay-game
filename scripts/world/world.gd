extends Node3D
## The in-game world: level, players, cops, match and UI.
## Same node path on every peer: /root/Main/World

const OfficeBuilder = preload("res://scripts/world/office_builder.gd")
const PlayerScript = preload("res://scripts/player/player.gd")
const CopScript = preload("res://scripts/player/cop.gd")
const MatchScript = preload("res://scripts/net/match.gd")
const HudScript = preload("res://scripts/ui/hud.gd")
const TvScript = preload("res://scripts/ui/tv_screen.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const BallScript = preload("res://scripts/world/ball.gd")
const PlayerLook = preload("res://scripts/art/character.gd")
const PropKit = preload("res://scripts/art/prop_kit.gd")
const HoodController = preload("res://scripts/world/hood_controller.gd")   # ---- neighborhood (houses) ----

var builder
var players_node: Node3D
var cops_node: Node3D
var match_node: Node
var hud
var tv
var local_player
var ball
var hood                        # ---- neighborhood (houses) ----: HoodController (taxis, realtor, doors)
var _bubble_t := {}
var _idle_t := 8.0
var _ticker_offset := 0.0
var _screen_acc := 0.0
var _marquee_t := {}
var counters: Array = []        # public money counters (desk ones live with the trophies)
const UI_RED := Color(1, 0.3, 0.3)
var _trophy_sig := {}           # desk id -> signature of what's on it
const CashArt = preload("res://scripts/art/cash_art.gd")
const GunArt = preload("res://scripts/art/gun_art.gd")
const MoneyCounter = preload("res://scripts/world/money_counter.gd")
const CarScript = preload("res://scripts/vehicle/car.gd")
const PursuitScript = preload("res://scripts/vehicle/pursuit.gd")
var pursuit
var cars := {}                  # peer -> their car (ours is simulated here, theirs follow the network)
var cars_node: Node3D
var _car_send := 0.0
var atms: Array = []            # ATM nodes (office by the elevator, street outside the bank)
var _spread_nodes := {}         # peer -> {node, sig}: cash laid out for the photo


func _ready() -> void:
	Graphics.changed.connect(_apply_graphics)
	Graphics.start_watch.call_deferred()
	builder = OfficeBuilder.new()
	builder.build(self)
	if Net.is_server():
		builder.bake_nav()
	players_node = Node3D.new()
	players_node.name = "Players"
	add_child(players_node)
	cops_node = Node3D.new()
	cops_node.name = "Cops"
	add_child(cops_node)
	match_node = MatchScript.new()
	match_node.name = "Match"
	add_child(match_node)
	tv = TvScript.new()
	tv.name = "TV"
	add_child(tv)
	tv.attach(builder.tv_screen, match_node)
	hud = HudScript.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(self, match_node)
	ball = BallScript.new()
	ball.setup(self)
	add_child(ball)
	Net.players_changed.connect(_sync_players)
	match_node.market_tick.connect(_on_market_tick)
	match_node.slot_result.connect(_on_slot_result)
	match_node.state_changed.connect(_on_state)
	match_node.state_changed.connect(_update_trophies)
	Net.players_changed.connect(_update_trophies)
	match_node.news.connect(_on_news)
	_build_atms()
	match_node.cash_moved.connect(_on_cash_moved)
	match_node.shot.connect(_on_shot)
	cars_node = Node3D.new()
	cars_node.name = "Cars"
	add_child(cars_node)
	pursuit = PursuitScript.new(self)
	pursuit.name = "Pursuit"
	add_child(pursuit)
	match_node.state_changed.connect(_sync_spreads)
	_sync_players()
	# ---- neighborhood (houses) ----
	hood = HoodController.new()
	hood.name = "HoodController"
	add_child(hood)
	hood.setup(self)
	# ---- /neighborhood (houses) ----


# ---------------------------------------------------------------- players

func _sync_players() -> void:
	var idx := 0
	for id in Net.players:
		if not players_node.has_node(str(id)):
			var p := PlayerScript.new()
			var info: Dictionary = Net.players[id]
			p.setup(id, info.name, Net.look_of(id, idx), id == Net.my_id(), self)
			players_node.add_child(p)
			p.teleport(spawn_point(idx))
			if p.is_local:
				local_player = p
				arrive.call_deferred()          # ride up and walk out of the elevator
		idx += 1
	for c in players_node.get_children():
		if not Net.players.has(int(str(c.name))):
			c.queue_free()
	# tailor changes: rebuild anyone whose look changed
	var slot := 0
	for id in Net.players:
		var p = players_node.get_node_or_null(str(id))
		if p:
			p.apply_look(Net.look_of(id, slot))
		slot += 1


func player_node(id: int) -> Node3D:
	return players_node.get_node_or_null(str(id))


func spawn_point(i: int) -> Vector3:
	return builder.spawn_points[i % builder.spawn_points.size()]


func ui_blocking() -> bool:
	return hud != null and (hud.is_modal_open() or hud.busy())


# ---------------------------------------------------------------- KWIK studio

func in_street(node: Node3D) -> bool:
	return node != null and node.global_position.distance_to(builder.street.ORIGIN) < 90.0


## Which shop interior a node is standing in ("lux", "casino", "pawn", ...), or "".
func street_zone(node: Node3D) -> String:
	if not in_street(node):
		return ""
	var at := Vector2(node.global_position.x, node.global_position.z)
	for z in builder.street.zones:
		if (z.rect as Rect2).has_point(at):
			return z.kind
	return ""


func go_to_street() -> void:
	if local_player and not match_node.is_jailed(Net.my_id()):
		Sfx.play("bell", -8.0, 1.6)
		local_player.teleport(builder.street.spawn)
		local_player.rotation.y = PI
		if not cars.has(Net.my_id()):         # your ride's parked at the curb out front
			var st = builder.street
			spawn_car(Net.my_id(), match_node.car_of(Net.my_id()), st.P(-12.0 + 6.0 * (Net.players.keys().find(Net.my_id()) % 4), 0.3, -1.7), -PI / 2)
		hud.show_toast("Ground floor. The street is yours — boutiques, Tony's Deli, the Tailor, Pawn King, the casino.",
				Color(0.95, 0.9, 0.6))


# ---------------------------------------------------------------- cars

## Put `peer`'s car (a Rules.CARS key) in the world. Ours we drive; theirs
## follow the network (and still block us).
func spawn_car(peer: int, key: String, pos: Vector3, yaw: float, paint = null):
	if cars.has(peer):
		cars[peer].queue_free()
	var c = CarScript.new()
	c.setup(key, peer, paint if paint is Color else match_node.paint_of(peer, key))
	c.name = "Car_%d" % peer
	c.position = pos
	c.rotation.y = yaw
	c.set_meta("interact", "car")
	c.set_meta("interact_id", peer)
	c.set_meta("prompt", "[E] Drive your %s" % Rules.CARS[key].name if peer == Net.my_id() else "%s's %s" % [Net.player_name(peer), Rules.CARS[key].name])
	cars_node.add_child(c)
	cars[peer] = c
	if peer == Net.my_id():
		send_car(c, true)
	return c


## Stream our car to everyone: 20 times a second while driving, once a
## second while it's parked (so late joiners see it too).
func send_car(c, now := false) -> void:
	if not now and _car_send > 0.0:
		return
	_car_send = 0.05 if local_player and local_player.driving == c else 1.0
	_car_tf.rpc(c.key, c.paint, c.global_position, c.quaternion, c.speed, c.steer, c.in_brake > 0.05)


@rpc("any_peer", "unreliable_ordered")
func _car_tf(key: String, paint: Color, pos: Vector3, rot: Quaternion, spd: float, st: float, brake: bool) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not Net.players.has(peer) or not Rules.CARS.has(key):
		return
	var c = cars.get(peer)
	if c == null or not is_instance_valid(c) or c.key != key or not c.paint.is_equal_approx(paint):
		c = spawn_car(peer, key, pos, 0.0, paint)
	c.net_state(pos, rot, spd, st, brake)


## Where a patrol car comes from to chase `target`: well behind it, on the
## ground (the highway hooks this up to a lane once it exists).
func pursuit_spawn(target) -> Transform3D:
	var back: Vector3 = target.global_basis.z
	back.y = 0.0
	back = back.normalized() if back.length() > 0.1 else Vector3.BACK
	for dist in [110.0, 70.0, 40.0]:
		var at: Vector3 = target.global_position + back * dist
		var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 30, 0), at + Vector3(0, -30, 0))
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and (hit.normal as Vector3).y > 0.8:
			return Transform3D(Basis(Vector3.UP, target.global_rotation.y), hit.position + Vector3(0, 0.3, 0))
	return Transform3D(Basis(Vector3.UP, target.global_rotation.y), target.global_position + back * 40.0 + Vector3(0, 0.3, 0))


@rpc("authority", "unreliable_ordered")
func _npc_car_tf(id: int, key: String, pos: Vector3, rot: Quaternion, spd: float, st: float) -> void:
	pursuit.net_car(id, key, pos, rot, spd, st)


@rpc("authority", "call_remote", "reliable")
func _npc_car_gone(id: int) -> void:
	pursuit._remove(id)


func _tick_cars(delta: float) -> void:
	_car_send = maxf(_car_send - delta, 0.0)
	var me := Net.my_id()
	var mine = cars.get(me)
	if mine and is_instance_valid(mine) and (local_player == null or local_player.driving != mine):
		# bought / picked / resprayed at the dealership: the new one's parked right where the old one was
		var want: String = match_node.car_of(me)
		if mine.key != want or not mine.paint.is_equal_approx(match_node.paint_of(me, want)):
			mine = spawn_car(me, want, mine.global_position + Vector3(0, 0.2, 0), mine.global_rotation.y)
		send_car(mine)                        # parked: the slow heartbeat
	for peer in cars.keys():                  # they left: their car goes with them
		if not Net.players.has(peer):
			cars[peer].queue_free()
			cars.erase(peer)


func leave_street() -> void:
	if local_player:
		arrive()                                # back up to 12: out of the elevator


# ---- neighborhood (houses) ----
## Magnolia Heights (scripts/world/hood_controller.gd does the work).
func in_neighborhood(node: Node3D) -> bool:
	return hood != null and hood.in_neighborhood(node)


func go_to_neighborhood(instant := false) -> bool:
	return hood != null and hood.go_to_neighborhood(instant)


func go_home(instant := false) -> bool:
	return hood != null and hood.go_home(instant)
# ---- /neighborhood (houses) ----


func in_studio(node: Node3D) -> bool:
	return node != null and node.global_position.distance_to(builder.STUDIO) < 12.0


func go_to_studio() -> void:
	if not match_node.has_rank_for(Net.my_id(), "studio"):
		hud.show_toast("Studio access unlocks at ANALYST. Make some green days first.", UI_RED)
		return
	if local_player and not match_node.is_jailed(Net.my_id()):
		local_player.teleport(builder.studio_spawn)
		local_player.rotation.y = -PI / 2 - 0.3
		hud.show_toast("You pulled up to the KWIK LIVE studio. Chat is going crazy.", Color(0.8, 0.55, 1))


func leave_studio() -> void:
	if local_player:
		local_player.teleport(builder.studio_exit_to)


## Cops can't path into the studio: if they come for you there, the stream
## gets swatted and you're dumped back on the trading floor.
func _check_studio_raid() -> void:
	if local_player and not match_node.raid.is_empty() and match_node.raid.get("target", 0) == Net.my_id():
		if in_studio(local_player):
			leave_studio()
			hud.show_toast("SWATTED ON STREAM. The cops are on the trading floor. RUN.", UI_RED)
		elif in_street(local_player):
			leave_street()
			hud.show_toast("Cops grabbed you on the street and dragged you upstairs. RUN.", UI_RED)


## Server check for the restroom: is this player standing by the toilet?
func near_toilet(peer: int) -> bool:
	var pn := player_node(peer)
	return pn != null and pn.global_position.distance_to(builder.toilet_pos) < 2.2


# ---------------------------------------------------------------- per-frame

func _process(delta: float) -> void:
	_tick_cars(delta)
	if local_player and hud:
		hud.set_prompt(local_player.look_target() if not ui_blocking() else {})
	_tick_bubbles(delta)
	_tick_marquees(delta)
	_update_elevator(delta)
	_check_studio_raid()
	_ticker_offset += delta
	if builder.ticker_label:
		builder.ticker_label.position.x = fposmod(-_ticker_offset * 2.2, 36.0) - 18.0 + 9.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not ui_blocking() and local_player and local_player.seat >= 0 \
			and local_player.look_target().get("type", "") in ["", "chair"]:
		local_player.stand_up()
	elif event.is_action_pressed("interact") and not ui_blocking() and local_player:
		var t: Dictionary = local_player.look_target()
		if t.get("type", "") == "ball":
			ball.request_grab()
		elif t.get("type", "") == "relieve":
			match_node.request_relieve()
		elif t.get("type", "") == "studio_exit":
			leave_studio()
		elif t.get("type", "") == "elevator_down":
			go_to_street()
		elif t.get("type", "") == "elevator_up":
			leave_street()
		elif t.get("type", "") == "hotdog":
			match_node.request_hotdog()
			Sfx.play("coin")
		elif t.get("type", "") == "chair":
			local_player.sit(t.id)
		elif t.get("type", "") == "counter":
			_run_counter(t.id)
		elif t.get("type", "") == "car":
			if int(t.id) == Net.my_id():
				local_player.enter_car(cars[t.id])
			else:
				hud.show_toast("That's %s's car." % Net.player_name(int(t.id)), Color(1, 0.8, 0.4))
		elif str(t.get("type", "")).begins_with("hood_"):   # ---- neighborhood (houses) ----
			hood.interact(t)
			get_viewport().set_input_as_handled()
		elif not t.is_empty():
			hud.open_interact(t)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("start_day") and not ui_blocking():
		if match_node.phase == "gameover" and not Net.is_server():
			hud.show_toast("Waiting for the host to go back to the lobby.")
		elif match_node.phase != "trading":
			match_node.request_start()          # READY up (the bell rings when everyone is)
	elif not ui_blocking() and match_node:
		for i in 6:
			if event.is_action_pressed("item_%d" % (i + 1)):
				var key: String = Rules.ITEMS.keys()[i]
				if match_node.item_count(Net.my_id(), key) > 0:
					match_node.request_use(key)
				else:
					hud.show_toast("You don't have a %s. Visit Tony in the lounge." % Rules.ITEMS[key].name)


# ---------------------------------------------------------------- streamers

const IDLE_LINES := {
	"TJZ": ["Chat, we're so back.", "Liquidity grab incoming.", "Don't trade the open, bro.", "I'm not even mad. (I'm mad.)"],
	"KIMCHEE": ["Anyone got a new ticker?", "Rugs are part of the journey.", "Just woke up. Up 4 milli.", "NFA. Obviously."],
	"ROARING KITTEH": ["...", "*sips*", "I just like the stock."],
	"JIM CRAMMER": ["BOOYAH!", "I've never been wrong! (I'm always wrong)", "Buy the dip! Which dip? ALL of them!"],
}


func _on_news(ev: Dictionary) -> void:
	var sp: String = ev.get("speaker", "")
	if builder.npcs.has(sp):
		var line: String = ev.headline
		var colon := line.find(": ")
		_say(sp, line.substr(colon + 2) if colon >= 0 else line, 9.0)


func _say(speaker: String, text: String, secs: float) -> void:
	var n: Node3D = builder.npcs.get(speaker)
	if n == null:
		return
	var b: Label3D = n.get_node("Bubble")
	b.text = text
	_bubble_t[speaker] = secs
	n.get_node("Model").talking = true


func _tick_bubbles(delta: float) -> void:
	for sp in _bubble_t.keys():
		_bubble_t[sp] -= delta
		if _bubble_t[sp] <= 0.0:
			_bubble_t.erase(sp)
			var n: Node3D = builder.npcs.get(sp)
			if n:
				n.get_node("Bubble").text = ""
				n.get_node("Model").talking = false
	_idle_t -= delta
	if _idle_t <= 0.0:
		_idle_t = randf_range(12.0, 22.0)
		var sp: String = IDLE_LINES.keys().pick_random()
		if not _bubble_t.has(sp):
			_say(sp, IDLE_LINES[sp].pick_random(), 5.0)


func _on_market_tick() -> void:
	# the wall ticker shows 7 at a time and rolls to the next 7 every pass
	var parts: PackedStringArray = []
	var n: int = match_node.m_assets.size()
	var pages := maxi(ceili(n / 7.0), 1)
	var page := int(_ticker_offset * 2.2 / 36.0) % pages
	for i in range(page * 7, mini(page * 7 + 7, n)):
		var a: Dictionary = match_node.m_assets[i]
		var ch: float = (a.price / a.open_day - 1.0) * 100.0
		parts.append("%s %s %s%.2f%%" % [a.sym, Rules.price_str(a.price), "+" if ch >= 0 else "-", absf(ch)])
	if builder.ticker_label:
		builder.ticker_label.text = "     ".join(parts)
	_screen_acc += 1
	if int(_screen_acc) % 4 == 0:
		_update_desk_screens()


func _update_desk_screens() -> void:
	var assets: Array = match_node.m_assets
	if assets.is_empty():
		return
	for it in builder.interactables:
		if it.type != "terminal":
			continue
		var l: Label3D = it.node.get_node_or_null("ScreenText")
		if l:
			var a: Dictionary = assets[it.id % assets.size()]
			var ch: float = (a.price / a.open_day - 1.0) * 100.0
			l.text = "%s\n%s\n%s%.2f%%" % [a.sym, Rules.price_str(a.price), "+" if ch >= 0 else "", ch]
			l.modulate = Color(0.3, 1, 0.45) if ch >= 0 else Color(1, 0.35, 0.3)


func _on_slot_result(peer: int, reels: Array, payout: float, bet: float) -> void:
	# Every machine flashes the reels; the one this player stands at shows the
	# bet, the win on its marquee and pops coins + confetti.
	const LOOK := {"CHERRY": ["CHR", Color(0.9, 0.1, 0.15)], "CLOVER": ["CLV", Color(0.1, 0.65, 0.2)],
			"BELL": ["BEL", Color(0.95, 0.65, 0.05)], "DIAMOND": ["DIA", Color(0.1, 0.6, 0.95)],
			"SEVEN": ["7", Color(0.85, 0.1, 0.1)]}
	for body in builder.slot_machines:
		for k in reels.size():
			var l: Label3D = body.get_node_or_null("Reel%d" % k)
			if l:
				var look: Array = LOOK[Rules.SLOT_SYMBOLS[reels[k]]]
				l.text = look[0]
				l.modulate = look[1]
	var body: Node3D = _machine_near(peer)
	if body == null:
		return
	(body.get_node("Bet") as Label3D).text = Rules.money(bet)
	if payout > 0.0:
		var mq: Label3D = body.get_node("Marquee")
		mq.text = "+" + Rules.money(payout)
		mq.modulate = Color(1, 0.45, 0.75)
		_marquee_t[body] = 4.0
		for n in ["Jackpot/Coins", "Jackpot/Confetti"]:
			var p: CPUParticles3D = body.get_node(n)
			p.amount = 60 if payout >= bet * 10.0 else 30
			p.restart()


func _machine_near(peer: int) -> Node3D:
	var pn := player_node(peer)
	var best: Node3D = null
	var bd := 1e9
	for body in builder.slot_machines:
		var d: float = body.global_position.distance_to(pn.global_position) if pn else 0.0
		if d < bd:
			bd = d
			best = body
	return best


func _tick_marquees(delta: float) -> void:
	for body in _marquee_t.keys():
		_marquee_t[body] -= delta
		if _marquee_t[body] <= 0.0:
			_marquee_t.erase(body)
			var mq: Label3D = body.get_node("Marquee")
			mq.text = "DEGEN SLOTS"
			mq.modulate = Color(1, 0.88, 0.15)


# ---------------------------------------------------------------- flex trophies

## Every player owns a desk in the front row. Their luxury buys pile up on it:
## nameplate, cash counter, Crownwell boxes, SUPRÉMO bricks, boutique bags.
func desk_of(peer: int) -> int:
	var i := 0
	for id in Net.players:
		if id == peer:
			return builder.PLAYER_DESK0 + i
		i += 1
	return -1


func _update_trophies() -> void:
	var i := 0
	for id in Net.players:
		var desk: int = builder.PLAYER_DESK0 + i
		i += 1
		if not builder.desks.has(desk):
			continue
		var own: Dictionary = match_node.owned.get(id, {}) if match_node else {}
		var sig := "%s|%s" % [Net.player_name(id), str(own)]
		if _trophy_sig.get(desk, "") == sig:
			continue
		_trophy_sig[desk] = sig
		_build_trophies(desk, Net.player_name(id), own)
	for desk in _trophy_sig.keys():
		if desk - builder.PLAYER_DESK0 >= Net.players.size():
			_trophy_sig.erase(desk)
			var old: Node = builder.root.get_node_or_null("Trophies_%d" % desk)
			if old:
				old.queue_free()


func _build_trophies(desk: int, who: String, own: Dictionary) -> void:
	var old: Node = builder.root.get_node_or_null("Trophies_%d" % desk)
	if old:
		builder.root.remove_child(old)
		old.queue_free()
	var p: Vector3 = builder.desks[desk]
	var t := Node3D.new()
	t.name = "Trophies_%d" % desk
	t.position = p
	builder.root.add_child(t)
	var plate := Label3D.new()
	plate.text = "%s'S DESK" % who.to_upper()
	plate.font_size = 40
	plate.pixel_size = 0.0035
	plate.modulate = Color(1, 0.84, 0.2)
	plate.outline_size = 8
	plate.position = Vector3(0, 1.4, -0.46)
	t.add_child(plate)
	var top := 0.78
	if own.get("counter", 0) > 0:
		var cc := MoneyCounter.new()
		cc.name = "CashCounter"
		cc.kit = "CashCounter"
		cc.display_at = Vector3(-0.23, 0, -0.04)
		cc.pile_at = Vector3(0.02, 0, 0.26)
		cc.position = Vector3(0.62, top, -0.2)
		cc.rotation.y = -0.3
		t.add_child(cc)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.3, 0.25, 0.3)
		cs.shape = sh
		cs.position = Vector3(0, 0.12, 0)
		sb.add_child(cs)
		sb.set_meta("interact", "counter")
		sb.set_meta("interact_id", desk)
		sb.set_meta("prompt", "[E] Count your cash")
		cc.add_child(sb)
	PropKit.place("PillBottle", t, Vector3(0.3, top, -0.3), 0.4)
	var boxes := 0
	for k in ["roflex", "roflex_iced"]:
		if own.get(k, 0) > 0:
			var bp := Vector3(-0.42, top, 0.16 - boxes * 0.26)
			var base := PropKit.place("WatchBoxBase", t, bp, 0.5)
			var lid := PropKit.place("WatchBoxLid", base, Vector3(0, 0.08, -0.1))
			lid.rotation.x = -1.9
			PropKit.place("WatchIced" if k == "roflex_iced" else "WatchGold", base, Vector3(0, 0.09, 0.01)).rotation.x = -0.4
			boxes += 1
	for n in int(own.get("supreme", 0)):
		var b := PropKit.place("SupremeBrick", t, Vector3(0.74, top + n * 0.061, 0.24), 0.2 + (n % 2) * 0.12)
		var sl := Label3D.new()
		sl.text = "SUPRÉMO"
		sl.font_size = 40
		sl.pixel_size = 0.0011
		sl.outline_size = 0
		sl.modulate = Color.WHITE
		sl.position = Vector3(0, 0.0625, 0)
		sl.rotation.x = -PI / 2
		b.add_child(sl)
	# handbags from the boutiques line up beside the desk
	var slot_i := 0
	for key in Rules.LUXURY:
		var bag: String = Rules.LUXURY[key].get("bag", "")
		if bag == "":
			continue
		for n in int(own.get(key, 0)):
			var bp := Vector3(1.25 + (slot_i % 5) * 0.4, 0, 0.15 + (slot_i / 5) * 0.45 + (slot_i % 2) * 0.08)
			var bag_node := PropKit.place(bag, t, bp, -0.2 + slot_i * 0.13)
			if key == "louie":   # the VM monogram on the Valmont keepall
				var ll := Label3D.new()
				ll.text = "VM"
				ll.font_size = 44
				ll.pixel_size = 0.0022
				ll.outline_size = 0
				ll.modulate = Color(0.35, 0.18, 0.05)
				ll.position = Vector3(0, 0.22, 0.072)
				bag_node.add_child(ll)
			slot_i += 1
	# office upgrades: they sit where they'd actually be used
	# (the Bloomberg gets its own stand beside the desk: the desk top is full)
	const UP_SPOTS := {"up_bloomberg": [Vector3(-1.34, 0, -0.05), 0.55], "up_scanner": [Vector3(-0.45, 0.78, -0.3), 0.25],
		"up_rolodex": [Vector3(0.36, 0.78, -0.04), -0.35], "up_intern": [Vector3(0.2, 0.78, 0.38), 0.8],
		"up_prime": [Vector3(-0.28, 0.78, 0.34), 0.15], "up_standing": [Vector3(0, 0, 0.95), 0.0]}
	for key in Rules.UPGRADES:
		if own.get(key, 0) > 0 and UP_SPOTS.has(key):
			PropKit.place(Rules.UPGRADES[key].prop, t, UP_SPOTS[key][0], UP_SPOTS[key][1])
	# PvP championship trophies stand on top of the cubicle wall for the whole floor to see
	# (either side of the nameplate: up to four)
	const CUP_X := [-0.62, 0.62, -0.84, 0.84]
	for n in mini(int(own.get("champ", 0)), CUP_X.size()):
		var tr := PropKit.place("ChampTrophy", t, Vector3(CUP_X[n], 1.31, -0.48), 0.0)
		if n == 0:
			var tl := Label3D.new()
			tl.text = "CHAMPION x%d" % int(own.champ)
			tl.font_size = 36
			tl.pixel_size = 0.0014
			tl.outline_size = 6
			tl.modulate = Color(1, 0.84, 0.2)
			tl.position = Vector3(0, 0.37, 0)
			tr.add_child(tl)


## A money counter by id: desk index for the desk counters, 1000+ for the
## public ones (by the office ATM).
func counter_node(id: int) -> Node:
	if id >= 1000:
		return counters[id - 1000] if id - 1000 < counters.size() else null
	var t: Node = builder.root.get_node_or_null("Trophies_%d" % id)
	return t.get_node_or_null("CashCounter") if t else null


## [E] on a counter: run the cash you're carrying through it (everyone sees
## the count). Nothing on you: it counts the house stack, $10K.
func _run_counter(id: int) -> void:
	var cc = counter_node(id)
	if cc == null or cc.counting:
		return
	var cash: float = match_node.cash_of(Net.my_id())
	if cash < 100.0:
		cash = 10_000.0
		hud.show_toast("Counting the house stack. Hit the ATM to run your own cash through it.", Color(1, 0.8, 0.4))
	local_player.show_cash_stack(0.8)
	_count_fx.rpc(id, cash)


@rpc("any_peer", "call_local", "reliable")
func _count_fx(id: int, amount: float) -> void:
	var cc = counter_node(id)
	if cc and not cc.counting:
		cc.count(clampf(amount, 100.0, 1e12))


func _on_state() -> void:
	var bell: Label3D = builder.root.find_child("BellLabel", true, false)
	if bell:
		match match_node.phase:
			"lobby":
				bell.text = "OPENING BELL\nhost: press ENTER"
			"gameover":
				bell.text = "RUN OVER\nhost: ENTER for lobby"
			_:
				bell.text = "DAY %d" % match_node.day


## Player transforms go through World (always present once connected) so a
## packet that beats the roster never hits a missing node.
@rpc("any_peer", "unreliable_ordered")
func _p_tf(pos: Vector3, yaw: float, pitch: float, flags: int) -> void:
	var p = player_node(multiplayer.get_remote_sender_id())
	if p and not p.is_local:
		p.net_tf(pos, yaw, pitch, flags)


# ---------------------------------------------------------------- police

func spawn_cops(target: int) -> void:
	despawn_cops()
	for i in 2:
		var c := CopScript.new()
		c.name = "Cop%d" % i
		c.setup(self, target)
		cops_node.add_child(c)
		c.global_position = builder.elevator_pos + Vector3(-0.6 + i * 1.2, 0, 0)


func despawn_cops() -> void:
	for c in cops_node.get_children():
		c.queue_free()


func broadcast_cops() -> void:
	var data: Array = []
	for c in cops_node.get_children():
		data.append([c.global_position, c.rotation.y])
	_s_cops.rpc(data)


@rpc("authority", "unreliable_ordered")
func _s_cops(data: Array) -> void:
	var existing := cops_node.get_children()
	for i in data.size():
		var c
		if i < existing.size():
			c = existing[i]
		else:
			c = CopScript.new()
			c.name = "Cop%d" % i
			c.setup(self, 0)
			cops_node.add_child(c)
			c.global_position = data[i][0]
		c.net_update(data[i][0], data[i][1])


# ---------------------------------------------------------------- jail

func on_arrested(peer: int) -> void:
	if local_player and peer == Net.my_id():
		local_player.exit_car(true)
		local_player.teleport(builder.jail_pos + Vector3(randf_range(-1, 1), 0.1, randf_range(-1, 1)))


func on_released(peer: int) -> void:
	if local_player and peer == Net.my_id():
		arrive()                                # out on bail: back up the elevator


# ---------------------------------------------------------------- elevator arrival

const CAR_POS := Vector3(0, 0.1, OfficeBuilder.D / 2 + 1.4)
const DOOR_OPEN_SECS := 3.6
var _elev_open_t := 0.0          # doors stay open while > 0 (every peer runs its own doors)


## You arrive on the trading floor: in the car, ding, the doors open, you walk
## out. Everyone in the office sees the doors open and you walk out.
func arrive() -> void:
	if local_player == null:
		return
	if Config.cli.has("clicktest") or Config.cli.has("shots") or Config.cli.has("savecheck") \
			or str(Config.cli.get("smoke", "")) == "host":
		return                                  # tests that need you standing still at a spawn point
	local_player.teleport(CAR_POS + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.2, 0.3)))
	local_player.rotation.y = 0.0
	local_player.begin_arrival()
	_p_arrive.rpc(Net.my_id())


@rpc("any_peer", "call_local", "reliable")
func _p_arrive(peer: int) -> void:
	_elev_open_t = DOOR_OPEN_SECS
	var near: bool = local_player == null or local_player.global_position.distance_to(builder.elevator_pos) < 25.0
	if near:
		Sfx.play("bell", -8.0 if peer == Net.my_id() else -13.0, 1.6)
	arrivals[peer] = arrivals.get(peer, 0) + 1


var arrivals := {}               # peer -> how many times they came out of the elevator (tests)


func _update_elevator(delta: float) -> void:
	if builder == null or builder.elevator_doors.is_empty():
		return
	_elev_open_t = maxf(_elev_open_t - delta, 0.0)
	var opening := _elev_open_t > 0.0 and _elev_open_t < DOOR_OPEN_SECS - 0.35   # a beat after the ding
	for door in builder.elevator_doors:
		var cx: float = door.get_meta("closed_x")
		var want: float = cx + signf(cx) * 1.1 if opening else cx
		door.position.x = move_toward(door.position.x, want, delta * 1.6)
		var open_now: bool = absf(door.position.x - cx) > 0.3
		for sb in door.find_children("*", "StaticBody3D", true, false):
			(sb as StaticBody3D).collision_layer = 0 if open_now else 1


## Graphics preset changed (or first applied): street shadows, view distance
## and how far the small detailed props (watches) draw.
func _apply_graphics() -> void:
	var g: Dictionary = Graphics.cur
	var sun := builder.root.get_node_or_null("Sun") as DirectionalLight3D if builder else null
	if sun:
		sun.shadow_enabled = g.shadows
	if local_player and local_player.cam:
		local_player.cam.far = g.far
	if builder:
		for mi in builder.root.find_children("*", "MeshInstance3D", true, false):
			if mi.has_meta("no_batch"):
				mi.visibility_range_end = g.detail


# ---------------------------------------------------------------- ATMs + cash

## ATM kiosk (prop "ATM" from the kit, a stand-in box until it's there).
## Screen / header / dispenser points match build_props.py's ATM.
const ATM_HEADER := Vector3(0, 1.54, 0.224)     # kit ATM reference points
const ATM_SCREEN := Vector3(0, 1.21, 0.093)
const ATM_SLOT := Vector3(0, 0.79, 0.2275)


func _build_atms() -> void:
	var spots := [
		[Vector3(3.3, 0, OfficeBuilder.D / 2 - 0.36), PI],          # office, by the elevator
		[builder.street.P(-3.2, builder.street.SIDEWALK_H, -builder.street.WALK + 0.34), 0.0],   # outside the bank
	]
	for i in spots.size():
		var pos: Vector3 = spots[i][0]
		var rot: float = spots[i][1]
		var n: Node3D
		if PropKit.has("ATM"):
			n = PropKit.place("ATM", builder.root, pos, rot)
		else:
			n = Node3D.new()
			n.position = pos
			n.rotation.y = rot
			builder.root.add_child(n)
			CashArt._box(n, Vector3(0.75, 1.65, 0.6), Vector3.ZERO, Color(0.3, 0.32, 0.36))
			CashArt._box(n, Vector3(0.5, 0.36, 0.02), ATM_SCREEN + Vector3(0, -0.18, 0.02), Color(0.05, 0.25, 0.2))
		n.name = "ATM_%d" % i
		var head := Label3D.new()
		head.text = "BAGHOLDER BANK"
		head.font_size = 40
		head.pixel_size = 0.0016
		head.modulate = Color(1, 1, 1)
		head.outline_size = 0
		head.position = ATM_HEADER + Vector3(0, 0, 0.003)
		n.add_child(head)
		var scr := Label3D.new()
		scr.name = "Screen"
		scr.text = "WELCOME\n[E] CASH"
		scr.font_size = 32
		scr.pixel_size = 0.0014
		scr.modulate = Color(0.45, 1.0, 0.7)
		scr.outline_size = 0
		scr.position = ATM_SCREEN + Vector3(0, 0, 0.003)
		n.add_child(scr)
		var col: Node3D = builder.solid(Vector3(0.75, 1.65, 0.6), pos + Vector3(0, 0.825, 0), builder.root, rot)
		builder.add_interact(col, "atm", i, "[E] ATM: take out / put in cash")
		atms.append(n)
		if i == 0:          # a counter on a stand next to the office ATM: count what you just pulled
			var bs := Basis(Vector3.UP, rot)
			var at: Vector3 = pos + bs * Vector3(1.05, 0, 0.05)
			builder.box(Vector3(0.9, 0.95, 0.5), at + Vector3(0, 0.475, 0), Color(0.16, 0.16, 0.18), false, builder.root).rotation.y = rot
			var mc := MoneyCounter.new()
			mc.kit = "MoneyCounterPro"
			mc.display_at = Vector3(-0.21, 0, -0.06)
			mc.pile_at = Vector3(0.3, 0, 0.0)
			mc.position = at + bs * Vector3(-0.14, 0.95, 0)
			mc.rotation.y = rot
			builder.root.add_child(mc)
			var cb: Node3D = builder.solid(Vector3(0.9, 1.2, 0.5), at + Vector3(0, 0.6, 0), builder.root, rot)
			builder.add_interact(cb, "counter", 1000 + counters.size(), "[E] Count your cash")
			counters.append(mc)


func _near_atm(node: Node3D) -> Node3D:
	for a in atms:
		if a.global_position.distance_to(node.global_position) < 3.0:
			return a
	return null


## Cash in or out of an ATM: bills fly out of (or into) the slot for everyone
## watching, the brrt of the counter inside.
func _on_cash_moved(peer: int, withdrawn: float, _total: float) -> void:
	var p := player_node(peer)
	if p == null:
		return
	var a := _near_atm(p)
	if a == null:
		return
	var out := withdrawn > 0.0
	var n := clampi(int(log(maxf(absf(withdrawn), 1000.0) / 1000.0 + 1.0) * 4.0) + 3, 3, 16)
	for k in n:
		var b := CashArt.bill(a, ATM_SLOT, Vector3(0, randf_range(-0.2, 0.2), 0))
		b.visible = false
		var tw := create_tween()
		tw.tween_interval(k * 0.07)
		tw.tween_callback(func(): b.visible = true)
		var dst := ATM_SLOT + Vector3(randf_range(-0.12, 0.12), randf_range(-0.35, -0.15), randf_range(0.25, 0.45))
		if out:
			tw.tween_property(b, "position", dst, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(b, "rotation", Vector3(randf_range(-0.6, 0.6), randf_range(-1, 1), randf_range(-0.5, 0.5)), 0.35)
		else:
			b.position = dst
			tw.tween_property(b, "position", ATM_SLOT, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_interval(0.25 if out else 0.0)
		tw.tween_callback(b.queue_free)
	var scr: Label3D = a.get_node_or_null("Screen")
	if scr:
		scr.text = ("TAKE YOUR CASH\n%s" if out else "DEPOSITED\n%s") % Rules.money(absf(withdrawn))
		get_tree().create_timer(2.5).timeout.connect(func():
			if is_instance_valid(scr):
				scr.text = "WELCOME\n[E] CASH")
	if peer == Net.my_id():
		local_player.show_cash_stack(2.2 if out else 0.0)


## A round from `from` along `dir`: returns the hit (empty if it flew off)
## and leaves a hole in whatever wall / desk / target it hit (not in people).
func shoot_ray(from: Vector3, dir: Vector3, shooter: Node) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 80.0)
	if shooter is CollisionObject3D:
		q.exclude = [(shooter as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and not (hit.collider is CharacterBody3D):
		GunArt.hole(self, hit.position, hit.normal)
	return hit


## Someone else fired (our own shots already played when we pulled the trigger).
func _on_shot(peer: int, hit: Vector3) -> void:
	if peer == Net.my_id():
		return
	var p = player_node(peer)
	if p:
		p.remote_fire(hit)


## N: lay your cash out on the table / floor you're looking at (everyone sees
## it; it's still yours). N again picks it up.
func toggle_spread() -> void:
	if local_player == null:
		return
	var me := Net.my_id()
	if match_node.spreads.has(me):
		match_node.request_spread(Vector3.ZERO, 0.0, true)
		Sfx.play("cash", -6.0)
		return
	if match_node.cash_of(me) < 100.0:
		hud.show_toast("No cash on you to spread. Hit an ATM first.", Color(1, 0.6, 0.3))
		return
	var cam: Camera3D = local_player.cam
	var from := cam.global_position
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * 3.0, 1))
	var pos: Vector3
	if not hit.is_empty() and (hit.normal as Vector3).y > 0.7:
		pos = hit.position                                   # a desk, a table, a bed, the floor
	else:
		var ahead: Vector3 = local_player.global_position - local_player.global_basis.z * 1.1 + Vector3(0, 1.0, 0)
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3.DOWN * 3.0, 1))
		pos = down.position if not down.is_empty() else local_player.global_position - local_player.global_basis.z * 1.1
	match_node.request_spread(pos + Vector3(0, 0.002, 0), local_player.rotation.y, false)
	Sfx.play("brrt", -6.0)


## Build / move / remove everyone's spreads from the match state.
func _sync_spreads() -> void:
	for peer in _spread_nodes.keys():
		if not match_node.spreads.has(peer):
			(_spread_nodes[peer].node as Node).queue_free()
			_spread_nodes.erase(peer)
	for peer in match_node.spreads:
		var sp: Dictionary = match_node.spreads[peer]
		var sig := "%s|%s|%d" % [str(sp.pos), str(sp.yaw), int(float(sp.amount) / 1000.0)]
		if _spread_nodes.has(peer) and _spread_nodes[peer].sig == sig:
			continue
		if _spread_nodes.has(peer):
			(_spread_nodes[peer].node as Node).queue_free()
		var n := CashArt.spread(float(sp.amount), int(peer) + int(float(sp.amount)))
		n.position = sp.pos
		n.rotation.y = float(sp.yaw)
		add_child(n)
		_spread_nodes[peer] = {"node": n, "sig": sig}
