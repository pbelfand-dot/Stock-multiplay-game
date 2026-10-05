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
##   --screenshot=out.png [--shot_seat=codriver --shot_s=300 --shot_read --shot_mud [--shot_wipe=N] --shot_nohud
##                         --shot_yaw=1.2 --shot_pitch=-0.3 (look around, rad) --shot_view=seat|chase|orbit
##                         --shot_steer=-1..1 --shot_handbrake --shot_loading (keep the loading screen up)
##                         --shot_drift (start it sliding sideways: the dirt flies)
##                         --shot_cam=x,y,z,tx,ty,tz (a free close-up camera, car-local: at xyz, looking at t; the car holds still, or drives with --autostart --autopilot)
##                         --shot_jump (at 120 km/h onto the stage's first (big) jump: the picture is taken mid-air)]

const Game = preload("res://scripts/game.gd")
const Menu = preload("res://scripts/ui/main_menu.gd")
const LoadingScreen = preload("res://scripts/ui/loading_screen.gd")

var game: Node
var menu: Control
var seed_value := 1
var stage_no := 1
var _test_t := 0.0
var _smoke_done := false
var _loading := false
var _air_t := 0.0


func _ready() -> void:
	Net.connected_ok.connect(_on_connected)
	Net.connection_failed.connect(func(r): to_menu("Couldn't connect: " + r))
	Net.server_gone.connect(func(): to_menu("The host left."))
	Net.wrong_version.connect(to_menu)
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
	# on a CanvasLayer: a Control under a plain Node has no screen to fill
	var layer := CanvasLayer.new()
	layer.name = "MenuLayer"
	add_child(layer)
	menu = Menu.new()
	layer.add_child(menu)
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
	Net.hello.rpc_id(1, Config.player_name, Updater.current_build)


## Host: someone joined: everyone (re)loads the stage and meets at the start line.
func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		if game:
			game.all_loaded = false            # stop streaming at them: they have no Game yet
		await get_tree().create_timer(0.4).timeout
		if not Net.players.has(id):
			if game:
				game.all_loaded = true         # turned away (another build) or gone already
			return
		next_stage(seed_value, stage_no)


func next_stage(s: int, n: int) -> void:
	if Net.online():
		# first everyone stops streaming the car, and the last packets land while the old
		# stage is still there; only then both rebuild (otherwise the driver's old car can
		# still be talking to a Game that's busy building and has no Car yet)
		pause_stream.rpc()
		await get_tree().create_timer(0.3).timeout
		load_stage.rpc(s, n)
	else:
		load_stage(s, n)


@rpc("authority", "call_local", "reliable")
func pause_stream() -> void:
	if game:
		game.all_loaded = false                      # crew_ready() false: the car stops streaming


@rpc("authority", "call_local", "reliable")
func load_stage(s: int, n: int) -> void:
	while _loading:                                  # one stage at a time (a reload during a load waits)
		await get_tree().process_frame
	_loading = true
	seed_value = s
	stage_no = n
	if menu:
		menu.get_parent().queue_free()
		menu = null
	if game:
		remove_child(game)
		game.queue_free()
	var screen = null
	if not Config.flag("screenshot") or Config.flag("shot_loading"):
		screen = LoadingScreen.new()
		add_child(screen)
		screen.begin(n)
	game = Game.new()
	game.name = "Game"
	add_child(game)
	if screen:
		game.progress.connect(screen.progress)
		game.stage_generated.connect(func(): screen.set_stage(game.st.length, game.st.corners.size(), s))
	await game.start(s, n)
	_loading = false
	game.finished.connect(_on_stage_finished)
	_test_setup()
	if screen and not Config.flag("shot_loading"):
		screen.finish()


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
		game.cam.yaw = float(Config.arg("shot_yaw", 0.0))
		game.cam.pitch = float(Config.arg("shot_pitch", -0.06))
		if Config.flag("shot_mud"):
			game.cockpit.splat(0.9, 7)
			game.ai.enabled = false                # keep the mud on for the picture
			if Config.flag("shot_wipe"):
				game.cockpit.wipe(int(Config.arg("shot_wipe", 1)))
		if Config.flag("shot_nohud"):
			game._hud.visible = false
		if Config.flag("shot_cam"):
			var v := Array(Config.arg("shot_cam").split(",")).map(func(t): return float(t))
			var cam := Camera3D.new()
			cam.fov = 50.0
			cam.near = 0.01
			cam.cull_mask = 0xFFFFF & ~(1 << 1)        # not the driver's helmet (the camera can go in it)
			game.car.add_child(cam)
			cam.position = Vector3(v[0], v[1], v[2])
			cam.look_at(game.car.to_global(Vector3(v[3], v[4], v[5])))
			cam.make_current()
			if not Config.flag("autopilot"):
				game.car.freeze = true                # hold still for the picture (or ride along)
		if Config.flag("shot_jump"):
			var jump: Dictionary = {}
			for c in game.st.crests:
				if c.jump and (jump.is_empty() or (c.get("big", false) and not jump.get("big", false))):
					jump = c
			if not jump.is_empty():
				var s0: float = jump.s - 40.0
				game.car.place(game.st.world_at(s0, 0.0), game.st.heading_at(s0))
				game.car.linear_velocity = game.st.forward_at(s0) * 34.0
		if Config.flag("shot_drift"):                # sliding sideways on the handbrake: the dirt flies
			var xf: Transform3D = game.car.global_transform
			game.car.linear_velocity = -xf.basis.z * 17.0 + xf.basis.x * 8.0
			game.car.angular_velocity = Vector3(0, 0.9, 0)


func _process(dt: float) -> void:
	if game == null:
		return
	_test_t += dt
	var shot_now: bool = _test_t > float(Config.arg("shot_wait", 2.0))
	if Config.flag("shot_jump") and game.built:      # mid-air (or give up after 8 s)
		var flying := true
		for k in 4:
			flying = flying and game.car.comp[k] < 0.01
		_air_t = _air_t + dt if flying else 0.0
		shot_now = _air_t > float(Config.arg("shot_air", 0.45)) or _test_t > 8.0
	if Config.flag("screenshot") and shot_now:
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


## Every call should come from where the car is: said before the car reaches
## its first corner with time to spare (at least ~1 s, and 15 m when slow), not
## so early it's useless (over 8 s / 300 m out), and the calls should cover
## (nearly) every corner.
func _ai_report(r: Dictionary) -> void:
	var said: Array = game.ai.said
	var late := 0
	var early := 0
	var secs: Array = []
	for e in said:
		var lead: float = e[1] - e[0]
		var t: float = lead / maxf(e[3], 1.0)
		secs.append(t)
		if lead < 15.0 or (e[3] > 8.0 and t < 1.0):
			late += 1
		if lead > 300.0 or (e[3] > 8.0 and t > 8.0):
			early += 1
	secs.sort()
	var ok: bool = said.size() >= game.calls.size() - 2 and late == 0 and early == 0
	print("[ai] %d of %d calls said (%d dropped), %d late, %d far too early, warning time min %.1f s / median %.1f s / max %.1f s" % [
		said.size(), game.calls.size(), game.ai.dropped, late, early, secs[0] if secs.size() > 0 else 0.0,
		secs[secs.size() / 2] if secs.size() > 0 else 0.0, secs[-1] if secs.size() > 0 else 0.0])
	print("[ai] %s (stage %s)" % ["AI OK" if ok else "AI FAIL", game.fmt_time(r.time)])
	get_tree().quit(0 if ok else 1)
