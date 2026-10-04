extends Node
## Boot: the menu, or straight into a stage when the command line says so.
## Holds the current Game (always named "Game", so RPCs line up) and swaps it
## for the next stage. Command line (after `--`):
##   --solo [--seed=N]                       drive alone, the AI co-driver calls
##   --host [--seat=driver|codriver]         host a crew (the other seat joins)
##   --join=IP                               join a host
##   --autostart --autopilot                 tests: start the countdown / drive by itself
##   --smoke=host|client                     2-player test: drive a stage, both check it
##   --aicheck                               solo test: the AI co-driver's calls come in time
##   --screenshot=out.png [--shot_seat=codriver --shot_s=300 --shot_read --shot_mud --shot_nohud]

const Game = preload("res://scripts/game.gd")
const Menu = preload("res://scripts/ui/main_menu.gd")

var game: Node
var menu: Control
var seed_value := 1
var stage_no := 1
var _test_t := 0.0
var _smoke_done := false


func _ready() -> void:
	Net.connected_ok.connect(_on_connected)
	Net.connection_failed.connect(func(r): to_menu("Couldn't connect: " + r))
	Net.server_gone.connect(func(): to_menu("The host left."))
	multiplayer.peer_connected.connect(_on_peer_connected)
	seed_value = int(Config.arg("seed", randi() % 100000))
	if Config.flag("screenshot") or Config.flag("solo") or Config.flag("aicheck"):
		start_solo(seed_value)
	elif Config.flag("host"):
		host_game(Config.arg("seat", "driver"))
	elif Config.flag("join"):
		join_game(Config.arg("join", "127.0.0.1"))
	else:
		show_menu()


func show_menu(msg := "") -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu = Menu.new()
	add_child(menu)
	menu.status(msg)
	menu.solo.connect(func(): start_solo(randi() % 100000))
	menu.host.connect(host_game)
	menu.join.connect(join_game)


func start_solo(s: int) -> void:
	Net.solo()
	if Config.flag("screenshot") and Config.arg("shot_seat") == "codriver":
		Net.players[1].seat = "codriver"
	load_stage(s, 1)


func host_game(seat: String) -> void:
	if Net.host(Config.port, seat) != OK:
		to_menu("Couldn't host on port %d (is another game running?)" % Config.port)
		return
	load_stage(randi() % 100000 if not Config.flag("seed") else seed_value, 1)


func join_game(ip: String) -> void:
	Config.last_ip = ip
	Config.save()
	if Net.join(ip, Config.port) != OK:
		to_menu("Couldn't start the connection.")
		return
	if menu:
		menu.status("Connecting to %s..." % ip)


func _on_connected() -> void:
	Net.hello.rpc_id(1, Config.player_name)


## Host: someone joined: everyone (re)loads the stage and meets at the start line.
func _on_peer_connected(_id: int) -> void:
	if multiplayer.is_server():
		if game:
			game.all_loaded = false            # stop streaming at them: they have no Game yet
		await get_tree().create_timer(0.4).timeout
		next_stage(seed_value, stage_no)


func next_stage(s: int, n: int) -> void:
	if Net.online():
		load_stage.rpc(s, n)
	else:
		load_stage(s, n)


@rpc("authority", "call_local", "reliable")
func load_stage(s: int, n: int) -> void:
	seed_value = s
	stage_no = n
	if menu:
		menu.queue_free()
		menu = null
	if game:
		remove_child(game)
		game.queue_free()
	game = Game.new()
	game.name = "Game"
	add_child(game)
	game.start(s, n)
	game.finished.connect(_on_stage_finished)
	_test_setup()


func to_menu(msg := "") -> void:
	Net.leave()
	if game:
		game.queue_free()
		game = null
	if menu == null:
		show_menu(msg)
	else:
		menu.status(msg)
	if Config.flag("smoke"):
		print("[smoke] %s: FAIL %s" % [Config.arg("smoke"), msg])
		get_tree().quit(1)


# ── tests ─────────────────────────────────────────────────────────────────

func _test_setup() -> void:
	if Config.flag("screenshot"):
		var s := float(Config.arg("shot_s", 0))
		if s > 0.0:
			game.car.place(game.st.world_at(s, 0.0), game.st.heading_at(s))
		game.cam.force_read = Config.flag("shot_read")
		if Config.flag("shot_mud"):
			game.cockpit.splat(0.9, 7)
		if Config.flag("shot_nohud"):
			game._hud.visible = false


func _process(dt: float) -> void:
	if game == null:
		return
	_test_t += dt
	if Config.flag("screenshot") and _test_t > float(Config.arg("shot_wait", 2.0)):
		var path := Config.arg("screenshot")
		get_viewport().get_texture().get_image().save_png(path)
		print("[shot] saved ", path)
		get_tree().quit(0)
	var limit := float(Config.arg("timeout", 300))
	if (Config.flag("smoke") or Config.flag("aicheck")) and _test_t > limit and not _smoke_done:
		print("[smoke] %s: FAIL timed out in state %s at s=%.0f" % [Config.arg("smoke", "ai"), game.state, game.car_s])
		get_tree().quit(1)


func _on_stage_finished(r: Dictionary) -> void:
	if Config.flag("aicheck"):
		_ai_report(r)
	if not Config.flag("smoke") or _smoke_done:
		return
	_smoke_done = true
	var role := Config.arg("smoke")
	var gap: float = game.car.global_position.distance_to(game.st.world_at(game.st.finish_s, 0.0))
	if role == "host":
		print("[smoke] host: stage finished in %s (+%.0f s), seat %s, car %.0f m from the finish" % [
			game.fmt_time(r.time), r.penalties, game.my_seat, gap])
	else:
		print("[smoke] client: saw the finish (%s), seat %s, car %.0f m from the finish" % [
			game.fmt_time(r.time), game.my_seat, gap])
	# the co-driver's machine only knows where the car is from the driver's stream
	if game.my_seat == "codriver":
		print("[smoke] %s: %d car updates received" % [role, game.car.states_received])
	var ok: bool = gap < 40.0 and (game.my_seat == "driver" or game.car.states_received > 100) \
		and r.penalties == 0.0
	print("[smoke] %s: %s" % [role, "OK" if ok else "FAIL"])
	await get_tree().create_timer(1.5).timeout
	get_tree().quit(0 if ok else 1)


## Every call should be said before the car reaches its first corner, with
## time to spare, and the calls should cover every corner.
func _ai_report(r: Dictionary) -> void:
	var said: Array = game.ai.said
	var late := 0
	var leads: Array = []
	for e in said:
		var lead: float = e[1] - e[0]
		leads.append(lead)
		if lead < 20.0:
			late += 1
	leads.sort()
	var ok: bool = said.size() >= game.calls.size() - 1 and late == 0
	var early := 0
	for l in leads:
		if l > 400.0:
			early += 1                     # said so early it's useless
	ok = ok and early == 0
	print("[ai] %d of %d calls said, %d late, %d far too early, lead distance min %.0f m / median %.0f m / max %.0f m" % [
		said.size(), game.calls.size(), late, early, leads[0] if leads.size() > 0 else 0.0,
		leads[leads.size() / 2] if leads.size() > 0 else 0.0, leads[-1] if leads.size() > 0 else 0.0])
	print("[ai] %s (stage %s)" % ["AI OK" if ok else "AI FAIL", game.fmt_time(r.time)])
	get_tree().quit(0 if ok else 1)
