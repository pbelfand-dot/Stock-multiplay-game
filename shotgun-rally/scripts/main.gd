extends Node
## Boot: the menu, or straight into a stage when the command line says so.
## Holds the current Game (always named "Game", so RPCs line up) and swaps it
## for the next stage. Command line (after `--`):
##   --solo [--seed=N]                       drive alone, the AI co-driver calls
##   --host [--seat=driver|codriver]         host a crew (the other seat joins)
##   --host --mode=touge|cutup ... --street [--ghosts] [--min_racers=N]   host a street session (up to 8,
##                                           each in their own car; --ghosts: no collisions; tests:
##                                           --autostart waits for N racers, all loaded)
##   --join=IP                               join a host
##   --autostart --autopilot                 tests: start the countdown / drive by itself
##   --smoke=host|client                     2-player test: drive a stage, both check it
##   --aicheck                               solo test: the AI co-driver's calls come in time
##   --screenshot=out.png [--shot_seat=codriver --shot_s=300 --shot_read --shot_mud [--shot_wipe=N] --shot_nohud
##                         --shot_yaw=1.2 --shot_pitch=-0.3 (look around, rad) --shot_view=seat|chase|orbit
##                         --shot_steer=-1..1 --shot_handbrake --shot_loading (keep the loading screen up)
##                         --shot_drift (start it sliding sideways: the dirt flies)
##                         --shot_cam=x,y,z,tx,ty,tz (a free close-up camera, car-local: at xyz, looking at t; the car holds still, or drives with --autostart --autopilot)
##                         --shot_jump (at 120 km/h onto the stage's first (big) jump: the picture is taken mid-air)
##                         --shot_shift (with --autostart --autopilot: the picture is taken mid gear change)
##                         --shot_count=N (the start lights at N, 0 = GO) --shot_results [--shot_race] (the results panel)
##                         --shot_stray=M (a touge's stray car M up the road, coming the other way)]
##   --menu_shot=out.png [--menu_panel=maps|cars|online|settings --garage_tab=setup --shot_wait=6]   a picture of the home screen
##   --showcase=rally|touge|cutup [--autostart --autopilot --stray --shot_s=M]   film a mode for a showcase
##                                           video (run with --write-movie out.avi --fixed-fps 30): the
##                                           autopilot drives, scripts/game/showcase.gd cuts between cameras
##   --story=RALLY[,STAGE]                   (with --solo / --screenshot) a story stage
##   --surface=gravel|tarmac|mixed|any [--ice]   a quick stage's surface (else Settings')
##   --profile=PATH                          another save file (credits, garage, story)
##   --fit_debug                             the driver-fit overlay on from the start (F9 toggles it in a stage)
##   --mode=touge [--dir=up|down --rules=time|drift] | --mode=cutup [--difficulty=easy|normal|hard|insane]
##                                           (with --solo / --screenshot) a touge or a cut-up run (Modes)

const Game = preload("res://scripts/game.gd")
const Menu = preload("res://scripts/ui/main_menu.gd")
const LoadingScreen = preload("res://scripts/ui/loading_screen.gd")
const Profile = preload("res://scripts/game/profile.gd")
const Championship = preload("res://scripts/game/championship.gd")
const Modes = preload("res://scripts/game/modes.gd")

var game: Node
var menu: Control
var seed_value := 1
var stage_no := 1
## What kind of stage this is (load_stage carries it to both machines):
## {mode: "quick"} for PLAY NOW / online, or a story stage (Championship.stage_opts).
var opts := {"mode": "quick"}
var rally_times: Array = []                  # story: my total on each stage of this rally so far
var rally_lengths: Array = []
var _test_t := 0.0
var _smoke_done := false
var _smoke_ok := false
var _run_t := 0.0
var _traffic_counts: Array = []     # (online cut-up test) cars round us, once a second
var _loading := false
var _air_t := 0.0
var _shot_jumped := false                  # (--shot_s --autostart: jumped up the road at GO)
var _shift_gear := 0
var _shift_t := -1.0


func _ready() -> void:
	Net.connected_ok.connect(_on_connected)
	Net.connection_failed.connect(func(r): to_menu("Couldn't connect: " + r))
	Net.server_gone.connect(func(): to_menu("The host left."))
	Net.wrong_version.connect(to_menu)
	multiplayer.peer_connected.connect(_on_peer_connected)
	seed_value = int(Config.arg("seed", randi() % 100000))
	if Config.flag("menu_shot"):
		show_menu("", Config.arg("menu_panel", ""))
	elif Config.flag("screenshot") or Config.flag("solo") or Config.flag("aicheck"):
		start_solo(seed_value)
	elif Config.flag("host") and Config.flag("street") and Config.flag("mode"):
		start_mode({"mode": Config.arg("mode"), "dir": Config.arg("dir", "up"), "rules": Config.arg("rules", "time"),
			"difficulty": Config.arg("difficulty", "normal"), "online": true, "collide": not Config.flag("ghosts"),
			"seed": int(Config.arg("seed", -1))})
	elif Config.flag("host"):
		host_game(Config.arg("seat", "driver"))
	elif Config.flag("join"):
		join_game(Config.arg("join", "127.0.0.1"))
	else:
		show_menu()


func show_menu(msg := "", panel := "") -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# on a CanvasLayer: a Control under a plain Node has no screen to fill
	var layer := CanvasLayer.new()
	layer.name = "MenuLayer"
	add_child(layer)
	menu = Menu.new()
	menu.start_panel = panel
	layer.add_child(menu)
	menu.status(msg)
	menu.solo.connect(func(): start_solo(randi() % 100000))
	menu.host.connect(host_game)
	menu.join.connect(join_game)
	menu.story.connect(start_story)
	if menu.has_signal("mode"):
		menu.mode.connect(start_mode)


func start_solo(s: int) -> void:
	Net.solo()
	if Config.flag("screenshot") and Config.arg("shot_seat") == "codriver":
		Net.players[1].seat = "codriver"
	if Config.flag("story"):                         # tests / pictures: --story=RALLY[,STAGE]
		var rs := Config.arg("story").split(",")
		load_stage(0, 1, Championship.stage_opts(int(rs[0]), int(rs[1]) if rs.size() > 1 else 0))
		return
	if Config.flag("mode"):                          # tests / pictures: --mode=touge|cutup
		var m := {"mode": Config.arg("mode"), "dir": Config.arg("dir", "up"), "rules": Config.arg("rules", "time"),
			"difficulty": Config.arg("difficulty", "normal")}
		load_stage(s, 1, mode_opts(s, m))
		return
	load_stage(s, 1, quick_opts(s))


## A touge or cut-up run's settings, like `like` (its mode, direction, rules, difficulty) on seed s.
func mode_opts(s: int, like: Dictionary) -> Dictionary:
	var o: Dictionary
	if like.get("mode") == "cutup":
		o = Modes.cutup_opts(s, str(like.get("difficulty", "normal")))
	else:
		o = Modes.touge_opts(s, str(like.get("dir", "up")), str(like.get("rules", "time")))
	if Config.flag("length") and like.get("mode") != "cutup":
		o["length"] = float(Config.arg("length"))      # (tests: a shorter pass)
	return Modes.with_time(o, Config.time_of_day)


## From the menu's MODES: a touge or a cut-up run, alone, or hosted online for up to
## eight friends (m.online: a street session, everyone in their own car; m.collide).
func start_mode(m: Dictionary) -> void:
	if m.get("online", false):
		if Net.host(Config.port, "racer", "street", bool(m.get("collide", true))) != OK:
			to_menu("Couldn't host on port %d (is another game running?)" % Config.port)
			return
	else:
		Net.solo()
	var s := randi() % 100000 if int(m.get("seed", -1)) < 0 else int(m.seed)
	load_stage(s, 1, mode_opts(s, m))


## A quick stage's settings (PLAY NOW, online): its surface from Settings (or
## --surface=gravel|tarmac|mixed, --ice); "any" lets the seed pick: mostly gravel,
## some tarmac, some mixed, a third of those with snow and ice on the asphalt.
## They ride along with load_stage, so both machines build the same stage.
func quick_opts(s: int) -> Dictionary:
	var surf: String = Config.arg("surface", Config.quick_surface)
	var ice := Config.flag("ice")
	if surf == "any":
		var x := absi(hash([s, "surface"])) % 100
		surf = "gravel" if x < 55 else ("tarmac" if x < 80 else "mixed")
		ice = ice or (surf != "gravel" and x % 3 == 0)
	var gen := {}
	if surf != "gravel":
		gen["surface"] = surf
	if ice:
		gen["ice"] = true
	return Modes.with_time({"mode": "quick", "gen": gen}, Config.time_of_day)


func host_game(seat: String) -> void:
	if Net.host(Config.port, seat) != OK:
		to_menu("Couldn't host on port %d (is another game running?)" % Config.port)
		return
	var s := randi() % 100000 if not Config.flag("seed") else seed_value
	load_stage(s, 1, quick_opts(s))


## Story mode: rally i from its first stage, alone (seat "") or hosting a crew.
func start_story(i: int, seat := "") -> void:
	if seat == "":
		Net.solo()
	elif Net.host(Config.port, seat) != OK:
		to_menu("Couldn't host on port %d (is another game running?)" % Config.port)
		return
	load_stage(0, 1, Championship.stage_opts(i, 0))


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
	Net.set_car.rpc_id(1, Profile.setup())


## Host: someone joined: everyone (re)loads the stage and meets at the start line.
func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server() and Net.street():
		# a street session: the newcomer loads the stage that's on; the rest drive on
		await get_tree().create_timer(0.4).timeout
		if Net.players.has(id) and game:
			load_stage.rpc_id(id, seed_value, stage_no, opts)
		return
	if multiplayer.is_server():
		if game:
			game.all_loaded = false            # stop streaming at them: they have no Game yet
		await get_tree().create_timer(0.4).timeout
		if not Net.players.has(id):
			if game:
				game.all_loaded = true         # turned away (another build) or gone already
			return
		next_stage(seed_value, stage_no, opts)


func next_stage(s: int, n: int, o: Dictionary) -> void:
	if Net.online():
		# first everyone stops streaming the car, and the last packets land while the old
		# stage is still there; only then both rebuild (otherwise the driver's old car can
		# still be talking to a Game that's busy building and has no Car yet)
		pause_stream.rpc()
		await get_tree().create_timer(0.3).timeout
		load_stage.rpc(s, n, o)
	else:
		load_stage(s, n, o)


## Host, at the results: ENTER. Quick play: a new stage. Story: the rally's next
## stage, or after the last one back to the championship.
func continue_event() -> void:
	if Modes.is_mode(opts):                          # another pass / another highway, the same kind
		next_stage(seed_value + 1, stage_no + 1, mode_opts(seed_value + 1, opts))
		return
	if opts.get("mode") != "story":
		next_stage(seed_value + 1, stage_no + 1, quick_opts(seed_value + 1))
		return
	var i: int = opts.rally
	var j: int = opts.stage + 1
	if j < Championship.rally(i).stages.size():
		next_stage(0, stage_no + 1, Championship.stage_opts(i, j))
	elif Net.online():
		end_event.rpc()
	else:
		end_event()


## Host, at the results: R. The same stage again.
func retry_stage() -> void:
	next_stage(seed_value, stage_no, opts)


@rpc("authority", "call_local", "reliable")
func end_event() -> void:
	to_menu("", "maps")


@rpc("authority", "call_local", "reliable")
func pause_stream() -> void:
	if game:
		game.all_loaded = false                      # crew_ready() false: the car stops streaming


@rpc("authority", "call_local", "reliable")
func load_stage(s: int, n: int, o: Dictionary) -> void:
	while _loading:                                  # one stage at a time (a reload during a load waits)
		await get_tree().process_frame
	_loading = true
	if o.get("mode") == "story":
		s = int(o.seed)
		if int(o.stage) == 0:
			rally_times = []                         # a new rally (or its first stage again)
			rally_lengths = []
	seed_value = s
	stage_no = n
	opts = o
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
		var heading := "%s  ·  %s" % [o.title, o.stage_name] if o.get("mode") == "story" else ""
		if Modes.is_mode(o):
			heading = "TOUGE" if o.mode == "touge" else "CUT UP"
		screen.begin(n, heading, {"touge": "key_touge", "cutup": "key_cutup"}.get(str(o.get("mode", "")), "key_rally"), Modes.is_mode(o))
	game = Game.new()
	game.name = "Game"
	add_child(game)
	if screen:
		game.progress.connect(screen.progress)
		game.stage_generated.connect(func(): screen.set_stage(game.st.length, game.st.corners.size(), s, _stage_words(game.st),
			Modes.title(o, game.st).replace("\n", "  ·  ") if Modes.is_mode(o) else ""))
	await game.start(s, n, o)
	_loading = false
	game.finished.connect(_on_stage_finished)
	_test_setup()
	if screen and not Config.flag("shot_loading"):
		screen.finish()


## What a stage is, for the loading screen: "of gravel", "of mountain pass" ...
static func _stage_words(st) -> String:
	match str(st.kind):
		"touge":
			return "of mountain pass"
		"loop", "highway":
			return "of highway"
	var surfs := {}
	for sec in st.sections:
		surfs[str(sec.surface)] = true
	if surfs.size() > 1:
		return "of gravel and tarmac"
	return "of tarmac" if surfs.has("asphalt") else "of gravel"


func to_menu(msg := "", panel := "") -> void:
	Net.leave()
	if game:
		game.queue_free()
		game = null
	if menu == null:
		show_menu(msg, panel)
	else:
		menu.status(msg)
	if Config.flag("smoke"):
		if _smoke_ok:
			get_tree().quit(0)                         # (done and checked: the host's just gone first)
			return
		print("[smoke] %s: FAIL %s" % [Config.arg("smoke"), msg])
		get_tree().quit(1)


# ── tests ─────────────────────────────────────────────────────────────────

func _test_setup() -> void:
	if Config.flag("showcase"):                      # film it (with --write-movie): scripts/game/showcase.gd
		var sc = load("res://scripts/game/showcase.gd").new()
		game.add_child(sc)
		sc.setup(game, Config.arg("showcase", "rally"))
	if Config.flag("screenshot"):
		var s := float(Config.arg("shot_s", 0))
		if s > 0.0:
			game.car.place(game.st.world_at(s, game.st.LANE_W * 0.5 if game.traffic else 0.0), game.st.heading_at(s))
			game.car_s = s
			game._hint = int(s / game.st.STEP)            # (where to look for the car on the road now)
			if game.traffic:
				game.traffic.restart_at(s)               # (the traffic round the car, not back at the start)
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
		if Config.flag("shot_count"):              # the start lights at this count (0: GO)
			game._lights.hold = {"state": "countdown", "count": int(Config.arg("shot_count", 3))}
		if Config.flag("shot_stray") and game.stray:   # the touge's stray car this far up the road, coming at us
			game.stray.spawn_at(game.car_s + float(Config.arg("shot_stray", 30.0)), -1)
		if Config.flag("shot_results"):            # the results panel (made-up numbers; --shot_race: a podium)
			game.shot_results(Config.flag("shot_race"))
		if Config.flag("shot_cam"):
			var v := Array(Config.arg("shot_cam").split(",")).map(func(t): return float(t))
			var cam := Camera3D.new()
			cam.fov = 50.0
			cam.near = 0.01
			cam.far = 900.0                            # (as the game's cameras: not the whole forest to the horizon)
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
	if Config.flag("menu_shot") and menu:
		_test_t += dt
		if _test_t > float(Config.arg("shot_wait", 6.0)):
			get_viewport().get_texture().get_image().save_png(Config.arg("menu_shot"))
			print("[shot] saved ", Config.arg("menu_shot"))
			get_tree().quit(0)
		return
	if game == null:
		return
	_test_t += dt
	# an online cut-up test (no finish on the loop): check after --smoke_after s of driving
	if Config.flag("smoke") and not _smoke_done and game.built and game.street_online and game.looped and game.state == "running":
		_run_t += dt
		if _run_t > 8.0 and int(_run_t) != int(_run_t - dt):     # (the traffic round us, once a second: the check looks at the spread)
			_traffic_counts.append(game.traffic._mirror.size() if game.traffic.mirror else game.traffic.cars.size())
		if _run_t > float(Config.arg("smoke_after", 40.0)):
			_smoke_done = true
			_street_cutup_smoke(Config.arg("smoke"))
	# (--shot_s with --autostart: the countdown puts the car back on the grid, so the jump
	# up the road comes at GO, rolling at 100 km/h (or what the autopilot would be doing
	# there: not into a hairpin flat out), the traffic brought along)
	if (Config.flag("screenshot") or Config.flag("showcase")) and Config.flag("autostart") and float(Config.arg("shot_s", 0)) > 0.0 and not _shot_jumped \
			and game.built and game.state == "running":
		_shot_jumped = true
		var s := float(Config.arg("shot_s", 0))
		game.car.place(game.st.world_at(s, game.st.LANE_W * 0.5 if game.traffic else 0.0), game.st.heading_at(s))
		game.car.set_speed(minf(100.0 / 3.6, game.autopilot.want_at(s)) if game.autopilot else 100.0 / 3.6)
		game.car_s = s
		game._hint = int(s / game.st.STEP)            # (where to look for the car on the road now)
		if game.traffic:
			game.traffic.restart_at(s)
	var shot_now: bool = _test_t > float(Config.arg("shot_wait", 2.0))
	if Config.flag("shot_jump") and game.built:      # mid-air (or give up after 8 s)
		var flying := true
		for k in 4:
			flying = flying and game.car.comp[k] < 0.01
		_air_t = _air_t + dt if flying else 0.0
		shot_now = _air_t > float(Config.arg("shot_air", 0.45)) or _test_t > 8.0
	if Config.flag("shot_shift") and game.built:     # the driver's hand on the lever (or give up after 20 s)
		if _shift_gear > 0 and game.car.gear != _shift_gear and _shift_t < 0.0:
			_shift_t = 0.0
			Engine.time_scale = 0.1                  # slow motion: a software-rendered frame is longer than the whole reach
		_shift_gear = game.car.gear
		if _shift_t >= 0.0:
			_shift_t += dt
		shot_now = _shift_t > float(Config.arg("shot_after", 0.17)) or _test_t > 20.0
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
	_reward(r)
	if Config.flag("aicheck"):
		_ai_report(r)
	if not Config.flag("smoke") or _smoke_done:
		return
	_smoke_done = true
	var role := Config.arg("smoke")
	if game.street_online:
		_street_smoke(role)
		return
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
	# both machines must have built the same road surfaces (they only share the seed and settings)
	print("[smoke] %s: surfaces %s #%d" % [role, game.st.describe(), hash(str(game.st.sections) + str(game.st.patches))])
	var ok: bool = gap < 40.0 and (game.my_seat == "driver" or game.car.states_received > 100) \
		and r.penalties == 0.0
	print("[smoke] %s: %s" % [role, "OK" if ok else "FAIL"])
	await get_tree().create_timer(1.5).timeout
	get_tree().quit(0 if ok else 1)


## A street session's test (several machines racing a pass): once this one's over the
## line, wait for everyone's; each must have seen every other car's stream, and all of
## them must agree on the order.
func _street_smoke(role: String) -> void:
	var t := 0.0
	while game.standings.size() < Net.racers().size() and t < 90.0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	var names: Array = game.standings.map(func(e): return "%s %.3f" % [Net.player_name(int(e[0])), float(e[1])])
	var least := 1 << 30
	for id in game.others:
		least = mini(least, int(game.others[id].states_received))
	var gap: float = game.car.global_position.distance_to(game.st.world_at(game.st.finish_s, 0.0))
	print("[smoke] %s: street race, %d racers, %d other cars here, fewest updates from one %d, car %.0f m from the finish" % [
		role, Net.racers().size(), game.others.size(), least, gap])
	print("[smoke] %s: race order %s" % [role, " > ".join(names)])
	var ok: bool = game.standings.size() == Net.racers().size() and game.others.size() == Net.racers().size() - 1 \
		and least > 100 and gap < 40.0
	print("[smoke] %s: %s" % [role, "OK" if ok else "FAIL"])
	_smoke_ok = ok
	# (the host goes last: a guest still checking would take the host leaving for a failure)
	await get_tree().create_timer(4.0 if multiplayer.is_server() else 0.5).timeout
	get_tree().quit(0 if ok else 1)


## An online cut-up test: the host's traffic round every player, mirrored on each
## guest's machine; every other car seen.
func _street_cutup_smoke(role: String) -> void:
	var tr = game.traffic
	var least := 1 << 30
	for id in game.others:
		least = mini(least, int(game.others[id].states_received))
	var ok: bool = game.others.size() == Net.racers().size() - 1 and least > 100
	# the traffic's size swings by a whole pack as one leaves behind and the next comes in
	# ahead: judged on its average over the run, its low noted
	var lo := 0
	var mean := 0.0
	if not _traffic_counts.is_empty():
		lo = int(_traffic_counts.min())
		mean = float(_traffic_counts.reduce(func(a, b): return a + b, 0)) / _traffic_counts.size()
	var spread := "(over %d s: %d-%d, %.0f on average)" % [_traffic_counts.size(), lo, int(_traffic_counts.max()) if not _traffic_counts.is_empty() else 0, mean]
	if multiplayer.is_server():
		print("[smoke] %s: the traffic: %d cars round %d players (the others' %d), sending to %d machines %s" % [
			role, tr.cars.size(), tr.others_p.size() + 1, tr.others_p.size(), tr.net_peers.size(), spread])
		ok = ok and not tr.mirror and tr.others_p.size() == Net.racers().size() - 1 and tr.net_peers.size() == tr.others_p.size() \
			and mean > 20.0
	else:
		print("[smoke] %s: the host's traffic mirrored here: %d of its cars round me, %d hits reported %s" % [
			role, tr._mirror.size(), tr.hits_sent, spread])
		ok = ok and tr.mirror and mean >= 8.0
	print("[smoke] %s: %d other cars, fewest updates from one %d, %.0f km driven" % [role, game.others.size(), least, (game.car_s - game.st.START_S) / 1000.0])
	print("[smoke] %s: %s" % [role, "OK" if ok else "FAIL"])
	_smoke_ok = ok
	await get_tree().create_timer(6.0 if multiplayer.is_server() else 0.5).timeout
	get_tree().quit(0 if ok else 1)


## Credits for the stage (both players earn), the best time, and in story mode
## the rally standings; at the end of a rally, where you finished and what it
## pays. Shown under the results.
func _reward(r: Dictionary) -> void:
	var story: bool = opts.get("mode") == "story"
	var length: float = game.st.length
	var pay := Profile.stage_credits(r, length, story)
	Profile.earn(pay.total)
	var lines := ["+%s CR   (stage %d · pace %d · clean run %d%s)" % [money(pay.total), pay.base, pay.pace, pay.clean,
		" · story x1.5" if story else ""]]
	if Profile.record_stage(seed_value, length, r.total):
		lines.append("NEW BEST ON THIS STAGE")
	var next := "next stage"
	if story:
		var i: int = opts.rally
		var j: int = opts.stage
		var rally := Championship.rally(i)
		while rally_times.size() < j:              # joined mid-rally: the stages you missed at the middle pace
			rally_lengths.append(rally_lengths[-1] if rally_lengths.size() > 0 else length)
			rally_times.append(Championship.rival_time(i, rally_times.size(), 2, rally_lengths[-1]))
		rally_times.resize(j + 1)
		rally_lengths.resize(j + 1)
		rally_times[j] = float(r.total)
		rally_lengths[j] = length
		var rows := Championship.standings(i, rally_times, rally_lengths)
		var pos := Championship.position(rows)
		var last: bool = j + 1 >= rally.stages.size()
		if not last:
			var gap := "+%.1f s to %s" % [rows[pos - 1].total - rows[0].total, rows[0].name] if pos > 1 \
				else "leading by %.1f s" % (rows[1].total - rows[0].total)
			lines.append("%s after SS%d:  %s of %d  (%s)" % [rally.name, j + 1, Championship.ordinal(pos), rows.size(), gap])
			next = "SS%d %s" % [j + 2, rally.stages[j + 1][0]]
		else:
			var prize := Championship.reward(i, pos)
			Profile.earn(prize)
			Profile.finish_rally(rally.id, pos, rows[pos - 1].total)
			lines.append("%s FINISHED:  %s!   +%s CR" % [rally.name, Championship.ordinal(pos), money(prize)])
			for p in mini(rows.size(), 6):
				lines.append("%d.  %s   %s" % [p + 1, rows[p].name, game.fmt_time(rows[p].total)])
			next = "back to the championship"
	game.set_result_extra(lines, next)


static func money(n: int) -> String:
	var t := str(absi(n))
	var out := ""
	while t.length() > 3:
		out = "," + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return ("-" if n < 0 else "") + t + out


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
