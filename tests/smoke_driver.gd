extends Node
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
	for sig in ["news", "trade_closed", "trade_opened", "slot_result", "arrested", "raid_changed", "chat", "state_changed"]:
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
	if not await _wait_for(func(): return got.get("trade_closed", 0) >= 1 and got.get("slot_result", 0) >= 1 and got.get("chat", 0) >= 2, 40.0, "client actions"):
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
	if Net.players[bob].get("look", {}).get("hair_style", "") != "afro" or pnode.look.get("outfit", "") != "hoodie":
		_fail("client's tailor look didn't sync: %s" % str(Net.players[bob].get("look", {})))
		return
	_say("client's tailor look synced (afro + hoodie)")
	if m.stats[bob].trades < 1:
		_fail("server didn't record client trade")
		return
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
	_pass()


func _client() -> void:
	if not await _wait_for(func(): return not m.m_assets.is_empty() and m.phase == "trading", 30.0, "trading phase on client"):
		return
	_say("market mirrored: %d assets, BTC=%f, candles=%d" % [m.m_assets.size(), m.price_of("BTC"), m.m_assets[0].candles.size()])
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
	_pass()
