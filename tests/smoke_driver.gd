extends Node

const Rules = preload("res://scripts/sim/rules.gd")
## End-to-end multiplayer smoke test. Launch two headless instances:
##   godot --headless --path . -- --host --autostart --smoke=host [--pvp]
##   godot --headless --path . -- --join=127.0.0.1 --name=Bob --smoke=client
## Each prints SMOKE PASS / SMOKE FAIL and exits 0 / 1.

var role := ""
var m      # Match
var log_lines: PackedStringArray = []
var got := {}


func _ready() -> void:
	role = Config.cli.get("smoke", "")
	if role == "client":
		# a custom tailor look that the host must see
		Config.look = {"hair_style": "afro", "outfit": "hoodie", "suit": Color(0.8, 0.55, 0.1), "hat": "none"}
	_run.call_deferred()


func _say(s: String) -> void:
	print("[smoke:%s] %s" % [role, s])


func _fail(why: String) -> void:
	_say("SMOKE FAIL: " + why)
	Sfx.quit_game(1)


func _pass() -> void:
	_say("SMOKE PASS")
	Sfx.quit_game(0)


func _wait_for(cond: Callable, timeout: float, what: String) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > timeout:
			_fail("timeout waiting for " + what)
			return false
	return true


func _match():
	return get_node_or_null("/root/Main/World/Match")


func _run() -> void:
	get_tree().create_timer(90.0).timeout.connect(func(): _fail("global timeout"))
	if not await _wait_for(func(): return _match() != null, 15.0, "world"):
		return
	m = _match()
	for sig in ["news", "trade_closed", "trade_opened", "slot_result", "arrested", "raid_changed", "chat", "state_changed", "relieved"]:
		var s: String = sig
		m.connect(sig, func(_a = null, _b = null, _c = null, _d = null): got[s] = got.get(s, 0) + 1)
	if role == "host":
		await _host()
	else:
		await _client()


func _host() -> void:
	if not await _wait_for(func(): return Net.players.size() >= 2, 30.0, "client to join"):
		return
	_say("client joined: %s" % str(Net.players))
	if not await _wait_for(func(): return m.phase == "trading", 10.0, "trading phase"):
		return
	# wait for the client's trade + slot + chat
	if not await _wait_for(func(): return got.get("trade_closed", 0) >= 1 and got.get("slot_result", 0) >= 1 and got.get("chat", 0) >= 1, 40.0, "client actions"):
		return
	var bob := 0
	for id in Net.players:
		if id != 1:
			bob = id
	var pnode = get_node("/root/Main/World").player_node(bob)
	if pnode == null:
		_fail("no puppet for client")
		return
	_say("client puppet at %s" % str(pnode.global_position))
	if not await _wait_for(func(): return get_node("/root/Main/World").arrivals.has(bob), 10.0, "client's elevator arrival"):
		return
	_say("saw the client ride up and come out of the elevator")
	if Net.players[bob].get("look", {}).get("hair_style", "") != "afro" or pnode.look.get("outfit", "") != "hoodie":
		_fail("client's tailor look didn't sync: %s" % str(Net.players[bob].get("look", {})))
		return
	if not await _wait_for(func(): return pnode.seat == 0 and pnode.emote == 1, 30.0, "client sitting + finger emote"):
		return
	if not await _wait_for(func(): return pnode.model.pose == "dance", 10.0, "client dance to sync"):
		return
	_say("client's dance synced (anim %.1fs in)" % pnode.model.anim_t)
	if not await _wait_for(func(): return Net.players[bob].get("look", {}).get("hair_style", "") == "buzz" \
			and pnode.look.get("hat", "") == "cap", 10.0, "tailor look change to sync"):
		return
	_say("client's tailor change synced mid-game (buzz + cap)")
	_say("client's chair + emote synced (pose %s)" % pnode.model.pose)
	if not await _wait_for(func(): return got.get("chat", 0) >= 3, 30.0, "client ready for the raid"):
		return
	_say("client's tailor look synced (afro + hoodie)")
	if m.stats[bob].trades < 1:
		_fail("server didn't record client trade")
		return
	if m.lux_count(bob, "supreme") != 1 or get_node("/root/Main/World").builder.root.get_node_or_null("Trophies_%d" % (get_node("/root/Main/World").desk_of(bob))) == null:
		_fail("client's SUPREMO brick didn't show up on their desk")
		return
	_say("client's flex synced (SUPREMO brick on their desk)")
	# Crank the client's heat -> raid -> cops should catch them (they stand still).
	m._add_heat(bob, 200.0)
	if m.raid.is_empty():
		_fail("raid didn't start")
		return
	_say("raid started on %d, cops=%d" % [bob, get_node("/root/Main/World/Cops").get_child_count()])
	if not await _wait_for(func(): return m.is_jailed(bob), 25.0, "cops to catch client"):
		return
	_say("client arrested; stats=%s" % str(m.stats[bob]))
	await get_tree().create_timer(2.0).timeout
	if Net.mode == "coop":
		# READY-UP: the closing bell, then the host is ready but the day waits for the client
		m.ledger.get_acct(0).balance = 1_000_000.0
		m.time_left = 0.1
		if not await _wait_for(func(): return m.phase == "intermission", 10.0, "closing bell"):
			return
		m.request_start()
		await get_tree().create_timer(2.0).timeout
		if m.phase != "intermission" or not m.ready_up.has(1) or m.ready_count() != 1:
			_fail("day 2 didn't wait for the client (%s, ready %s)" % [m.phase, str(m.ready_up)])
			return
		_say("host READY, day 2 waits for the client (1/2)")
		if not await _wait_for(func(): return m.phase == "trading" and m.day == 2, 30.0, "client to ready up"):
			return
		_say("client READY too: day 2 rang")
	_pass()


func _client() -> void:
	if not await _wait_for(func(): return not m.m_assets.is_empty() and m.phase == "trading", 30.0, "trading phase on client"):
		return
	_say("market mirrored: %d assets, BTC=%f, candles=%d" % [m.m_assets.size(), m.price_of("BTC"), m.m_assets[0].candles.size()])
	if not await _wait_for(func(): return m.contracts.get(Net.my_id(), []).size() >= 3, 5.0, "Tony's contracts on the client"):
		return
	_say("got Tony's contracts: %s" % ", ".join(m.contracts[Net.my_id()].map(func(c): return c.text)))
	# we came up in the elevator: wait until we've walked out onto the floor
	var wl = get_node("/root/Main/World")
	var deepest := [-INF]          # how far into the car we were (the car is behind the wall at z > D/2)
	if not await _wait_for(func(): return wl.arrivals.has(Net.my_id()), 10.0, "elevator ride up"):
		return
	if not await _wait_for(func():
			if wl.local_player:
				deepest[0] = maxf(deepest[0], wl.local_player.global_position.z)
			return wl.local_player != null and not wl.local_player.arriving() and deepest[0] > -INF, 10.0, "elevator walk-out"):
		return
	var wall: float = wl.builder.D / 2
	if deepest[0] < wall + 0.5 or wl.local_player.global_position.z > wall - 1.0:
		_fail("elevator arrival wrong: started at z=%.2f (car is past %.1f), ended at z=%.2f" % [deepest[0], wall, wl.local_player.global_position.z])
		return
	_say("rode up in the car (z=%.2f) and walked out to z=%.2f" % [deepest[0], wl.local_player.global_position.z])
	var start_bal: float = m.my_acct().balance
	m.request_open("BTC", 1, 10_000.0, 100)
	if not await _wait_for(func(): return m.my_acct().get("positions", []).size() == 1, 5.0, "position open"):
		return
	_say("position open, cash %f -> %f" % [start_bal, m.my_acct().balance])
	m.request_buy("cigar")
	if not await _wait_for(func(): return m.item_count(Net.my_id(), "cigar") == 1, 5.0, "cigar bought"):
		return
	m.request_use("cigar")
	if not await _wait_for(func(): return m.effect_left(Net.my_id(), "cigar") > 0.0, 5.0, "cigar active"):
		return
	m.request_buy_lux("supreme")         # the one flex a fresh $25k desk can afford
	if not await _wait_for(func(): return m.lux_count(Net.my_id(), "supreme") == 1, 5.0, "supreme brick bought"):
		return
	m.request_slot(300.0)
	if not await _wait_for(func(): return got.get("slot_result", 0) >= 1, 5.0, "slot result"):
		return
	m.send_chat("OH MY GOD, TRADE!")
	if not await _wait_for(func(): return got.get("chat", 0) >= 1, 5.0, "chat echo"):
		return
	await get_tree().create_timer(1.0).timeout
	m.request_close_all()
	if not await _wait_for(func(): return got.get("trade_closed", 0) >= 1, 5.0, "trade closed"):
		return
	_say("closed; cash now %f; heat %s" % [m.my_acct().balance, str(m.heat)])
	# Basketball: walk up, grab, throw.
	var w = get_node("/root/Main/World")
	w.local_player.teleport(w.ball.global_position + Vector3(1.5, -0.9, 0))
	await get_tree().create_timer(0.5).timeout
	w.ball.request_grab()
	if not await _wait_for(func(): return w.ball.holder == Net.my_id(), 5.0, "ball grab"):
		return
	w.ball.request_throw(Vector3(-1, 0.6, 0))
	if not await _wait_for(func(): return w.ball.holder == 0, 5.0, "ball throw"):
		return
	_say("basketball grab + throw ok")
	# down to the street: hot dog (blood pressure), then back up
	w.go_to_street()
	await get_tree().create_timer(0.4).timeout
	if not w.in_street(w.local_player):
		_fail("elevator didn't take us to the street")
		return
	m.pressure[Net.my_id()] = 50.0
	m.request_hotdog()
	await get_tree().create_timer(1.0).timeout
	# the office FLEX SHOP counter lists every luxury item (it once filtered everything out)
	w.hud.open_interact({"type": "luxury", "id": 0})
	await get_tree().process_frame
	var rows: int = w.hud.lux_shop.list.get_child_count()
	w.hud.close_modals()
	if rows < Rules.LUXURY.size():
		_fail("office flex shop shows %d of %d items" % [rows, Rules.LUXURY.size()])
		return
	_say("street ok, hot dog eaten (pressure now %.1f)" % m.pressure_of(Net.my_id()))
	# soundtrack: walking into a boutique plays "Intoxicated"; getting liquidated cuts to "12 Stout Street"
	Music.clear_event()           # the flex bought earlier is still playing "Blue Bands"
	var shop: Rect2 = w.builder.street.zones[0].rect
	w.local_player.teleport(Vector3(shop.get_center().x, w.builder.street.ORIGIN.y + 0.25, shop.get_center().y))
	if not await _wait_for(func(): return Music.current == "intoxicated", 5.0, "boutique music (now %s, event %s %.0fs, zone %s)" % [Music.current, Music._event, Music._event_t, w.street_zone(w.local_player)]):
		return
	m.trade_closed.emit({"acct": m.acct_for(Net.my_id()), "trader": "x", "trader_id": Net.my_id(), "sym": "BTC",
			"side": 1, "pnl": -1000.0, "pct": -100.0, "liquidated": true, "lev": 100, "trigger": ""})
	await get_tree().create_timer(0.3).timeout
	if Music.current != "intoxicated":
		_fail("a liquidation changed the music (%s); 12 Stout Street is only for a losing day" % Music.current)
		return
	w.hud.music._on_day_ended({"passed": true, "players": {Net.my_id(): {"stats": {"pnl_day": -500.0}}}})
	if not await _wait_for(func(): return Music.current == "stout_street", 3.0, "losing-day music"):
		return
	Music.clear_event()
	_say("music ok (boutique -> Intoxicated, liquidation keeps it, losing day -> 12 Stout Street)")
	w.leave_street()
	await get_tree().create_timer(0.3).timeout
	if w.in_street(w.local_player):
		_fail("lobby elevator didn't bring us back up")
		return
	# the Tailor: change our look mid-game (buzz cut + cap); the host must see it
	var nl: Dictionary = Config.look.duplicate()
	nl["hair_style"] = "buzz"
	nl["hat"] = "cap"
	Config.look = nl
	Net.set_look(nl)
	# sit in a desk chair and flip the bird: the host must see both
	var lp = w.local_player
	lp.sit(0)
	lp.emote = 1
	lp._emote_t = 30.0
	m.send_chat("sitting + emote")
	await get_tree().create_timer(1.0).timeout
	lp.stand_up()
	lp.emote = 0
	# the rotoscoped dance, in first person: our own body plays it, the host sees it, walking ends it
	lp.emote = lp.EMOTES.find("dance")
	lp._emote_t = 30.0
	await get_tree().create_timer(2.5).timeout
	if lp.model.pose != "dance" or not lp.model.visible or not lp.model.fp:
		_fail("first-person dance didn't play on our body (pose %s)" % lp.model.pose)
		return
	var eye_y: float = lp.head.position.y
	Input.action_press("move_forward")
	await get_tree().create_timer(0.3).timeout
	Input.action_release("move_forward")
	if lp.emote != 0 or lp.model.pose == "dance":
		_fail("walking didn't end the dance")
		return
	_say("dance ok (first-person body, camera at the eyes y=%.2f, walking ends it)" % eye_y)
	# blood pressure: walk into the restroom and take care of it
	w.local_player.teleport(w.builder.toilet_pos + Vector3(1.1, 0.1, 0.4))
	await get_tree().create_timer(0.6).timeout
	m.request_relieve()
	if not await _wait_for(func(): return got.get("relieved", 0) >= 1, 5.0, "restroom relief"):
		return
	if not await _wait_for(func(): return m.pressure_of(Net.my_id()) < 5.0, 3.0, "pressure reset"):
		return
	_say("restroom relief ok (pressure %.1f)" % m.pressure_of(Net.my_id()))
	await get_tree().create_timer(4.0 + 0.2).timeout
	w.local_player.teleport(w.spawn_point(1))
	await get_tree().create_timer(0.5).timeout
	m.send_chat("ready for the cops")
	# Now just stand here and get arrested by the host-triggered raid.
	if not await _wait_for(func(): return got.get("arrested", 0) >= 1, 40.0, "arrest"):
		return
	var me = get_node("/root/Main/World").local_player
	_say("arrested, now at %s (jail)" % str(me.global_position))
	if me.global_position.z < 30.0:
		_fail("not teleported to jail")
		return
	if Net.mode == "coop":
		if not await _wait_for(func(): return m.phase == "intermission", 40.0, "closing bell"):
			return
		if not await _wait_for(func(): return m.ready_up.has(1), 10.0, "host to ready up"):
			return
		await get_tree().create_timer(4.0).timeout   # let the host see the day waiting on us
		if m.phase != "intermission":
			_fail("day 2 started before I was ready")
			return
		m.request_start()                    # ENTER: ready
		if not await _wait_for(func(): return m.phase == "trading" and m.day == 2, 10.0, "day 2 bell"):
			return
		_say("readied up after the host: day 2 is open")
	_pass()
