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

var builder
var players_node: Node3D
var cops_node: Node3D
var match_node: Node
var hud
var tv
var local_player
var ball
var _bubble_t := {}
var _idle_t := 8.0
var _ticker_offset := 0.0
var _screen_acc := 0.0


func _ready() -> void:
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
	match_node.news.connect(_on_news)
	_sync_players()


# ---------------------------------------------------------------- players

func _sync_players() -> void:
	var idx := 0
	for id in Net.players:
		if not players_node.has_node(str(id)):
			var p := PlayerScript.new()
			var info: Dictionary = Net.players[id]
			p.setup(id, info.name, PlayerLook.player_look(idx), id == Net.my_id(), self)
			players_node.add_child(p)
			p.teleport(spawn_point(idx))
			if p.is_local:
				local_player = p
		idx += 1
	for c in players_node.get_children():
		if not Net.players.has(int(str(c.name))):
			c.queue_free()


func player_node(id: int) -> Node3D:
	return players_node.get_node_or_null(str(id))


func spawn_point(i: int) -> Vector3:
	return builder.spawn_points[i % builder.spawn_points.size()]


func ui_blocking() -> bool:
	return hud != null and hud.is_modal_open()


# ---------------------------------------------------------------- per-frame

func _process(delta: float) -> void:
	if local_player and hud:
		hud.set_prompt(local_player.look_target() if not ui_blocking() else {})
	_tick_bubbles(delta)
	_ticker_offset += delta
	if builder.ticker_label:
		builder.ticker_label.position.x = fposmod(-_ticker_offset * 2.2, 36.0) - 18.0 + 9.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not ui_blocking() and local_player:
		var t: Dictionary = local_player.look_target()
		if t.get("type", "") == "ball":
			ball.request_grab()
		elif not t.is_empty():
			hud.open_interact(t)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("start_day") and not ui_blocking():
		if Net.is_server():
			match_node.request_start()
		elif match_node.phase == "lobby":
			hud.show_toast("Only the host can ring the opening bell.")
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
	var parts: PackedStringArray = []
	for i in match_node.m_assets.size():
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


func _on_slot_result(_peer: int, reels: Array, _payout: float, _bet: float) -> void:
	# Flash every machine's reel window with the result (cheap spectacle).
	var names := {"CHERRY": "CHR", "CLOVER": "CLV", "BELL": "BEL", "DIAMOND": "DIA", "SEVEN": "7"}
	for body in builder.slot_machines:
		var l: Label3D = body.get_node_or_null("ReelText")
		if l:
			l.text = " ".join(reels.map(func(r): return names[Rules.SLOT_SYMBOLS[r]]))


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
		local_player.teleport(builder.jail_pos + Vector3(randf_range(-1, 1), 0.1, randf_range(-1, 1)))


func on_released(peer: int) -> void:
	if local_player and peer == Net.my_id():
		local_player.teleport(builder.elevator_pos)
