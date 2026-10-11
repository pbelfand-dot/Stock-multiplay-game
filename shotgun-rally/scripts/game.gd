extends Node3D
## One stage, from the start line to the results (the node "Game" under Main;
## same path on both machines, so its RPCs and the car's line up).
##
##   GRID       both crew sit at the start line. The host presses ENTER (once
##              the co-driver has joined and loaded) to start the countdown.
##   COUNTDOWN  5 s. The start clocks (one each side of the road, and the
##              start lights on screen) count down; in solo the AI co-driver
##              counts you in. Moving off early is a
##              JUMP START: +10 s.
##   RUNNING    the stage clock runs until the car crosses the flying finish.
##              R puts the car back on the road (+5 s).
##   FINISHED   results; the host picks: next stage, retry, swap seats.
##
## The DRIVER's machine owns the car (simulates it, decides puddles, resets,
## jump start and the finish time); the host owns the stage (seed, countdown,
## what's next). Everything either player does that the other must see goes
## through an RPC on this node.

const StageGen = preload("res://scripts/stage/stage_gen.gd")
const LoopGen = preload("res://scripts/stage/loop_gen.gd")
const CircuitGen = preload("res://scripts/stage/circuit_gen.gd")
const CircuitBuilder = preload("res://scripts/stage/circuit_builder.gd")
const TrackSession = preload("res://scripts/game/track_session.gd")
const LoopBuilder = preload("res://scripts/stage/loop_builder.gd")
const StageBuilder = preload("res://scripts/stage/stage_builder.gd")
const Notes = preload("res://scripts/stage/pacenotes.gd")
const RallyCar = preload("res://scripts/vehicle/rally_car.gd")
const Cockpit = preload("res://scripts/vehicle/cockpit.gd")
const DriftFx = preload("res://scripts/vehicle/drift_fx.gd")
const SkidMarks = preload("res://scripts/vehicle/skid_marks.gd")
const SeatCam = preload("res://scripts/vehicle/seat_cam.gd")
const AICoDriver = preload("res://scripts/vehicle/ai_codriver.gd")
const Autopilot = preload("res://scripts/vehicle/autopilot.gd")
const EngineSound = preload("res://scripts/vehicle/engine_sound.gd")
const StartLights = preload("res://scripts/ui/start_lights.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")
const Catalog = preload("res://scripts/game/catalog.gd")
const Modes = preload("res://scripts/game/modes.gd")
const Profile = preload("res://scripts/game/profile.gd")
const Traffic = preload("res://scripts/stage/traffic.gd")
const CutupScore = preload("res://scripts/game/cutup_score.gd")
const Rivals = preload("res://scripts/game/rivals.gd")
const TougeRules = preload("res://scripts/game/touge_rules.gd")
const StrayCar = preload("res://scripts/game/stray_car.gd")
const CarLamps = preload("res://scripts/vehicle/car_lamps.gd")
const Ghost = preload("res://scripts/game/ghost.gd")
const FitDebug = preload("res://scripts/vehicle/fit_debug.gd")

signal progress(fraction: float, what: String)
signal stage_generated

const COUNTDOWN := 5.0
const CRASH_DV := 4.0                # m/s of speed lost at once: cut up counts it as a crash
const RESET_PENALTY := 5.0
const JUMP_START_PENALTY := 10.0

signal finished(result: Dictionary)

var st
var notes: Array = []
var calls: Array = []
var builder
var car
var cockpit
var cam
var ai
var autopilot
var seed_value := 1
var stage_no := 1
var state := "grid"
var countdown := 0.0
var stage_time := 0.0
var penalties := 0.0
var resets := 0
var jump_start := false
var car_s := 0.0
var _brake_eased := 0.0
var car_d := 0.0
var result := {}
var opts := {}
var _result_extra: Array = []       # credits, rally standings (Main fills them in)
var _next_text := "next stage"
var my_seat := "driver"
var use_autopilot := false
var all_loaded := false
var _loaded_peers := {}
var _hint := -1
var _start_pos := Vector3.ZERO
var _in_puddle := false
var _stuck := 0.0
var _mud_t := 0.0
var _said_wipers := false
var _chase := false                 # the driver picked the chase cam (C)
var view_override := ""              # (the showcase) the view it's filming: "seat", or "chase" for its own cameras
var built := false                  # start() has finished (it builds over several frames)
var _look_acc := 0.0
var _last_count := -1
var _hud: CanvasLayer
var _lights                         # StartLights: the countdown + stage clock on screen
var _hint_label: Label
var _big_label: Label
var _results: PanelContainer
var _results_head: Label             # the stage / mode (under the banner art)
var _results_label: Label
var _race_box: VBoxContainer         # a street race's finishers, badges on the podium
var _results_foot: Label             # Main's lines and what ENTER does
var _pause: PanelContainer
var _pause_settings: Button          # the pause menu's SETTINGS (the focus comes back to it)
var _settings: Control               # SETTINGS opened from the pause menu (null: shut)
var _t_alive := 0.0
var _sfx := {}
var _engine                        # EngineSound
var _gravel: AudioStreamPlayer3D
var _squeal: AudioStreamPlayer3D     # the tyres on the asphalt, sliding (off: TYRE_SQUEAL)
var _squeal_amt := 0.0
## The tyre squeal on asphalt: off for now (the owner: it sounds bad). The loop
## and its cue (car.grip_use) stay, to come back with a better recording.
const TYRE_SQUEAL := false
# the modes beyond rally stages (Modes): "" (a stage), "touge", "cutup", "track"
var mode := ""
var looped := false                  # the map's a loop (cut up's LAKESHORE LOOP, Track Mode's circuit): no finish
var circuit := false                 # Track Mode's circuit (CircuitGen)
var session                          # TrackSession (Track Mode)
var _track_box := 0                  # the pit box the car started from (Track Mode)
var traffic                          # Traffic (cut up)
var cutup                            # CutupScore
var rivals                           # Rivals (cut up on the loop: the highway battles)
var touge                            # TougeRules
var ghost                            # Ghost (touge time attack: your best run on this pass)
var stray                            # StrayCar (the touge: now and then a local on the pass)
var night := false                   # a night stage: the cars' lamps on (a touge: its street lamps lit)
var _beam_t := 0.0
var mode_result := {}                # the run's score / time / best, for the results
var _mode_label: Label               # top right: the score, the combo, the drift chain
var _flash_label: Label              # mid-screen: NEAR MISS +300, a split, CRASH
var _flash_t := 0.0
var fit_debug                        # FitDebug: the driver-fit overlay (F9, --fit_debug)
# a street session online (Net.street): everyone in their own car
var street_online := false
var others := {}                     # peer id -> RallyCar: the other drivers' cars, played from their streams
var standings: Array = []            # [[peer id, total s]], the touge race's finishers, quickest first
var _ready_peers: Array = []         # the machines whose stage is loaded (the car streams to them)
var _start_yaw := 0.0
var _waiting := false                # (joined mid-race on the touge: in the next one)
var _pos_t := 0.0
var _place := 0                      # the touge race: where you are (1 = leading), 0 = not racing
var _hints := {}                     # peer id -> its car's last road index (locating them)


## Build the stage, a step a frame (await it): progress(fraction, what) feeds the
## loading screen; stage_generated fires once the road is known. o: the stage's
## settings (Main.opts): a story stage brings its length, light (mood), road
## character (gen) and titles.
func start(seed_in: int, stage_in: int, o := {}) -> void:
	seed_value = seed_in
	stage_no = stage_in
	opts = o
	street_online = Net.online() and Net.street()
	use_autopilot = Config.flag("autopilot")
	progress.emit(0.02, "Reading the road book")
	await get_tree().process_frame
	if not is_inside_tree():
		return
	mode = str(o.get("mode", "")) if Modes.is_mode(o) else ""
	# cut up's map is the LAKESHORE LOOP: a loop, no finish (its s keeps growing lap after lap)
	circuit = str(o.get("gen", {}).get("kind", "")) == "circuit"
	looped = circuit or str(o.get("gen", {}).get("kind", "")) == "loop"
	st = CircuitGen.new() if circuit else (LoopGen.new() if looped else StageGen.new())
	st.opts = o.get("gen", {})
	st.generate(seed_value, float(o.get("length", Config.arg("length", 2600))))
	notes = Notes.build(st)
	calls = Notes.calls(notes)
	stage_generated.emit()
	builder = CircuitBuilder.new() if circuit else (LoopBuilder.new() if looped else StageBuilder.new())
	builder.mood = o.get("mood", "day")
	if "time_of_day" in builder:
		builder.time_of_day = float(o.get("time", -1.0))   # (the hour, -1: by the mood; the graphics work lights by it)
	add_child(builder)
	await builder.build_async(st, func(f: float, what: String): progress.emit(0.06 + f * 0.64, what))
	if not is_inside_tree():
		return
	progress.emit(0.72, "Building the car")
	await get_tree().process_frame
	if not is_inside_tree():
		return
	car = RallyCar.new()
	car.name = "Car_%d" % Net.my_id() if street_online else "Car"   # (the same path on every machine: its stream finds it)
	car.setup = _car_setup()                      # (built as the driver's car from the start: its own body and numbers)
	add_child(car)
	var spot := _grid_spot(Net.my_id())
	_start_pos = spot[0]
	_start_yaw = spot[1]
	car.place(_start_pos, _start_yaw)
	car.hit.connect(_on_hit)
	car.rub.connect(_on_rub)
	car.landed.connect(_on_landed)
	var fx := DriftFx.new()                       # dirt + stones off the tyres when it slides
	fx.name = "DriftFx"
	fx.car = car
	car.add_child(fx)
	var marks := SkidMarks.new()                  # black rubber on the asphalt where the tyres slid
	marks.name = "SkidMarks"
	marks.car = car
	marks.fx = fx
	add_child(marks)
	progress.emit(0.84, "Strapping in the crew")
	await get_tree().process_frame
	if not is_inside_tree():
		return
	cockpit = Cockpit.new()
	car.add_child(cockpit)
	cockpit.build(car, st)
	fit_debug = FitDebug.new()
	fit_debug.name = "FitDebug"
	car.add_child(fit_debug)
	fit_debug.setup(car, cockpit)
	fit_debug.visible = Config.flag("fit_debug")
	progress.emit(0.96, "Warming up the engine")
	cockpit.wiper_stroke.connect(func(): _play("wiper", -6.0))
	ai = AICoDriver.new()
	add_child(ai)
	ai.setup(calls if mode == "" else [])           # (a touge and a highway: no co-driver calling)
	_setup_mode(o)
	_night_lights()
	autopilot = Autopilot.new(st)
	if _at_station():
		autopilot.route = st.station_route(maxi(Net.racers().find(Net.my_id()), 0) if street_online else 0)   # (out of the gas station, up its ramp)
	if circuit:
		autopilot.route = _pit_out_route(_track_box)       # (out of the box, down the pit lane, onto the track)
		autopilot.route_v = 15.0
	cam = SeatCam.new()
	cam.chase_style = "street" if mode != "" else "rally"   # (cut up, the touge: low and close)
	add_child(cam)
	_audio()
	_build_hud()
	_apply_roster()
	Net.roster_changed.connect(_apply_roster)
	built = true
	if Net.online():
		loaded.rpc_id(1)
	else:
		set_all_loaded(true)
	if not Config.flag("headless_ui"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The driver's car from their garage set up for this stage (Catalog.for_stage); in
## the touge's DRIFT rules on SIM STREET, without its factory traction control.
func _car_setup() -> Dictionary:
	var base: Dictionary = Net.car_setup_for(Net.my_id()) if street_online else Net.car_setup()
	if mode == "track":
		# (Track Mode: a car of the session's class: the driver's if it's one, else the class's own)
		var want := Modes.track_car(opts, str(base.get("car", "")))
		if want != str(base.get("car", "")) and want != "":
			var wt := str(base.get("wheel_type", "stock"))
			base = Profile.setup_for(want)
			if Config.flag("wheel_type"):              # (pictures: --wheel_type=X follows the car)
				base["wheel_type"] = wt
	var s := Catalog.for_stage(base, st)
	if s.has("street") and mode == "touge" and opts.get("rules", "time") == "drift":
		s.street = s.street.duplicate()
		s.street[3] = false
	return s


## Seats decide who simulates the car, whose camera goes where, and whether
## the AI co-driver talks (only when nobody's in the passenger seat).
func _apply_roster() -> void:
	my_seat = Net.my_seat()
	var seat := "driver" if my_seat == "racer" else my_seat   # (a street session: everyone drives their own)
	var driver_here: bool = seat == "driver"
	var spot := _grid_spot(Net.my_id())
	var moved: bool = spot[0] != _start_pos
	if moved and autopilot and _at_station():
		autopilot.route = st.station_route(maxi(Net.racers().find(Net.my_id()), 0) if street_online else 0)
	_start_pos = spot[0]
	_start_yaw = spot[1]
	var setup := _car_setup()                    # the driver's car from their garage, its tyres for this stage
	if (car.apply_setup(setup) or moved) and state == "grid":     # another car (a new driver's), another slot: put it down again
		car.place(_start_pos, _start_yaw)
	cockpit.set_paint(setup.colours[0])
	car.set_simulating(driver_here)
	cam.attach(car, seat, cockpit.eye_for(seat))
	if seat == "driver":
		cam.aim_at_wheel(cockpit.wheel_c)
	cockpit.set_my_seat(seat)
	ai.enabled = not street_online and Net.peer_in("codriver") == 0 and mode == ""
	if street_online:
		_sync_racers()
		if multiplayer.is_server():
			for id in _loaded_peers.keys():          # (someone left: stop streaming at them)
				if not Net.players.has(id):
					_loaded_peers.erase(id)
			_to_ready("set_ready_peers", [_loaded_peers.keys()])
	_update_hint()


## A car's place on the grid (its driver's slot in a street session: two abreast on a
## touge, four on the highway, rows 9 m apart; cut up on the loop: at the gas station's
## pumps, LoopGen.station_spot): [position, heading].
func _grid_spot(id: int) -> Array:
	var k := maxi(Net.racers().find(id), 0) if street_online else 0
	if _at_station():
		return st.station_spot(k)
	if circuit:
		# (practice: everyone from their own box, the solo driver from the one by the line)
		_track_box = (8 + k) % int(st.pit.boxes)
		return st.box_spot(_track_box)
	var across: Array = [0.0]
	if mode == "cutup":
		across = [st.LANE_W * 0.5, -st.LANE_W * 0.5, st.LANE_W * 1.5, -st.LANE_W * 1.5]   # (in a lane, not astride two)
	elif street_online:
		across = [1.6, -1.6]
	var s: float = st.START_S - 3.0 - float(k / across.size()) * 9.0
	return [st.world_at(s, float(across[k % across.size()])), st.heading_at(s)]


## Does this run start at the gas station (cut up on the LAKESHORE LOOP; --highway_start: on the
## highway, as it used to)?
func _at_station() -> bool:
	return mode == "cutup" and "station" in st and not (st.station as Dictionary).is_empty() and not Config.flag("highway_start")


## Where the run starts along the road: the highway's s nearest the gas station (unwrapped
## near 0, as car_s will be), or the start line.
func _start_s() -> float:
	return st.unwrap(float(st.station.s), 0.0) if _at_station() else st.START_S


## The other drivers' cars (a street session): one per racer in the roster, played
## from their streams (not simulated here), solid or ghosts as the host set it, a name
## over each; dirt, smoke and tyre marks as your own.
func _sync_racers() -> void:
	var want: Array = Net.racers()
	for id in others.keys():
		if not id in want:
			(others[id] as Node).queue_free()
			others.erase(id)
			_hints.erase(id)
	for id in want:
		if id == Net.my_id():
			continue
		if others.has(id):
			others[id].apply_setup(Catalog.for_stage(Net.car_setup_for(id), st))   # (their garage car may have come since)
			_fit_lamps(others[id])
			continue
		var c = RallyCar.new()
		c.name = "Car_%d" % id
		c.setup = Catalog.for_stage(Net.car_setup_for(id), st)
		add_child(c)
		c.set_simulating(false)
		var spot := _grid_spot(id)
		c.place(spot[0], spot[1])
		c.set_outside(true)
		if not bool(Net.session.get("collide", true)):
			car.add_collision_exception_with(c)
			c.add_collision_exception_with(car)
		var fx := DriftFx.new()
		fx.car = c
		c.add_child(fx)
		var marks := SkidMarks.new()
		marks.car = c
		marks.fx = fx
		add_child(marks)
		var tag := Label3D.new()
		tag.name = "NameTag"
		tag.text = Net.player_name(id)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 56
		tag.pixel_size = 0.01
		tag.outline_size = 12
		tag.no_depth_test = false
		tag.position = Vector3(0.0, 2.1, 0.0)
		tag.visibility_range_end = 400.0
		c.add_child(tag)
		others[id] = c
		_fit_lamps(c)


# ── loading handshake (host) ──────────────────────────────────────────────

@rpc("any_peer", "call_local", "reliable")
func loaded() -> void:
	if not multiplayer.is_server():
		return
	var who := multiplayer.get_remote_sender_id()
	_loaded_peers[who] = true
	if Net.street():
		_to_ready("set_ready_peers", [_loaded_peers.keys()])
		if who != Net.my_id() and state != "grid":
			catch_up.rpc_id(who, state)                # (joined mid-run)
	if _loaded_peers.size() >= Net.players.size():
		set_all_loaded.rpc(true)


## (a street session) Call `method` here and on every other machine whose stage is
## loaded (the host knows them; everyone else, from set_ready_peers): a machine still
## loading has no Game for it to land in.
func _to_ready(method: String, args: Array) -> void:
	var ids: Array = _loaded_peers.keys() if multiplayer.is_server() else _ready_peers
	callv(method, args)
	for id in ids:
		if id != Net.my_id():
			callv("rpc_id", [id, method] + args)


## (a street session) The machines whose stage is loaded: the car streams to them.
@rpc("authority", "call_local", "reliable")
func set_ready_peers(ids: Array) -> void:
	_ready_peers = ids


## (a street session) Joined while the others are already going: on the highway you're
## straight in; on a touge you're in the next race (the grid, watching this one).
@rpc("authority", "reliable")
func catch_up(host_state: String) -> void:
	if looped and host_state in ["countdown", "running"]:
		state = "running"
		stage_time = 0.0
	else:
		_waiting = true
	_update_hint()


@rpc("authority", "call_local", "reliable")
func set_all_loaded(v: bool) -> void:
	all_loaded = v
	if v and ai and ai.enabled and state == "grid":
		ai.say(["ready"])                        # "co-driver ready": then the host starts the count
	_update_hint()


func crew_ready() -> bool:
	return all_loaded and (not Net.online() or Net.crew_full())


## (host) Has every player's stage loaded? (a street session: nobody still loading
## misses the countdown)
func _all_in() -> bool:
	if not street_online:
		return true
	for id in Net.players:
		if not _loaded_peers.has(id):
			return false
	return true


# ── the stage ─────────────────────────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func begin_countdown() -> void:
	if state != "grid" or not built:
		return
	state = "countdown"
	countdown = COUNTDOWN
	_last_count = -1
	car.place(_start_pos, _start_yaw)
	ai.hush()                                    # the count has to land on the second
	_update_hint()


@rpc("any_peer", "call_local", "reliable")
func stage_finished(time: float, pens: float, n_resets: int, jumped: bool) -> void:
	if state == "finished":
		return
	state = "finished"
	result = {"time": time, "penalties": pens, "total": time + pens, "resets": n_resets, "jump_start": jumped,
		"stage": stage_no, "seed": seed_value}
	_finish_mode()
	if ai.enabled:
		ai.say(["stage-complete"])
	_play("bell", -4.0)
	_show_results()
	finished.emit(result)


## (a street session, the touge) A driver crossed the line: the race's order, quickest
## first (time plus penalties), on every machine.
@rpc("any_peer", "call_local", "reliable")
func racer_finished(id: int, total: float) -> void:
	for e in standings:
		if int(e[0]) == id:
			return
	standings.append([id, total])
	# quickest first; a dead heat (identical times: it happens with identical cars) split
	# by grid slot, the same on every machine whatever order the finishes arrived in
	standings.sort_custom(func(a, b): return float(a[1]) < float(b[1]) or (float(a[1]) == float(b[1]) and int(a[0]) < int(b[0])))
	if state == "finished":
		_show_results()


@rpc("any_peer", "call_local", "reliable")
func set_penalties(pens: float, n_resets: int, jumped: bool) -> void:
	penalties = pens
	resets = n_resets
	jump_start = jumped


func _physics_process(dt: float) -> void:
	if not built:
		return
	_t_alive += dt
	var at: Dictionary = st.locate(car.global_position, _hint)
	_hint = at.i
	car_s = st.unwrap(at.s, car_s) if looped else at.s
	car_d = at.d
	car.set_lanes(st, car_s, car_d)
	cockpit.map_board.car_s = car_s
	car.stream_ok = crew_ready()          # nobody to send to (or they're still loading): don't
	if street_online:
		car.stream_peers = _ready_peers.filter(func(p): return p != Net.my_id())
		if car.stream_peers.is_empty():
			car.stream_ok = false
	match state:
		"grid":
			# (not ENTER while paused: in the pause menu and its settings, ENTER presses the button in focus)
			if Net.is_server() and crew_ready() and _all_in() and ((Input.is_action_just_pressed("ready") and not paused()) or
					(Config.flag("autostart") and (not street_online or Net.racers().size() >= int(Config.arg("min_racers", 1))))):
				if Net.online():
					begin_countdown.rpc()
				else:
					begin_countdown()
		"countdown":
			countdown -= dt
			var n := ceili(countdown)
			if n != _last_count and n >= 0:
				_last_count = n
				if n > 0:
					_play("tick", -2.0)
					if ai.enabled:
						ai.say([str(n)])
				else:
					_play("bell", -6.0)
					if ai.enabled:
						ai.say(["go"])
			if countdown <= 0.0:
				state = "running"
				stage_time = 0.0
				var crept := Vector2(car.global_position.x - _start_pos.x, car.global_position.z - _start_pos.z).length()
				if Config.flag("smoke") or Config.flag("aicheck"):
					print("[stage] GO: car %.2f m from its start spot" % crept)
				if car.simulate and crept > 1.0:
					jump_start = true
					penalties += JUMP_START_PENALTY
					_sync_penalties()
				_update_hint()
		"running":
			stage_time += dt
			if car.simulate and car_s >= st.finish_s:
				var args := [stage_time, penalties, resets, jump_start]
				if street_online:
					# (your own run ends; the others race on: the order comes in as they finish)
					stage_finished(args[0], args[1], args[2], args[3])
					_to_ready("racer_finished", [Net.my_id(), stage_time + penalties])
				elif Net.online():
					stage_finished.rpc(args[0], args[1], args[2], args[3])
				else:
					stage_finished(args[0], args[1], args[2], args[3])
	if mode != "":
		_mode_tick(dt)
	if night and street_online:
		_beam_t -= dt
		if _beam_t <= 0.0:
			_beam_t = 0.5
			_others_beams()
	if stray and state == "running":
		stray.enabled = not use_autopilot or Config.flag("stray")   # (the tests' autopilot doesn't steer round it)
		stray.tick(dt, car_s, car.global_position)
	if car.simulate:
		_drive_inputs()
		_puddles()
	# no human co-driver: the AI does the co-driver's jobs, wipers included
	# (it says "wipers" once per splat, then just keeps wiping while the view's blocked:
	# the pacenotes matter more than the commentary)
	if ai.enabled and cockpit.mud_level() > 0.45 and cockpit.wipe_strokes == 0:
		_mud_t += dt
		if _mud_t > 0.6:
			_mud_t = 0.0
			if not _said_wipers:
				_said_wipers = true
				ai.say(["wipers"])
			cockpit.wipe(3)
	else:
		_mud_t = 0.0
	if ai.enabled and state in ["countdown", "running"]:
		ai.update(car_s, car.linear_velocity.length(), dt)
	elif ai.enabled:
		ai.update(-1000.0, 0.0, dt)
	# tell the other player where we're looking (their view of our helmet)
	_look_acc += dt
	if Net.online() and not street_online and crew_ready() and _look_acc > 0.1:
		_look_acc = 0.0
		send_look.rpc(my_seat, cam.yaw if not cam.reading else 0.1, cam.pitch if not cam.reading else -0.9)


func _drive_inputs() -> void:
	if use_autopilot and state != "grid":
		car.inp = autopilot.drive(car, car_s, car_d)
		if state == "countdown":
			car.inp = {"steer": 0.0, "throttle": 0.0, "brake": 1.0, "handbrake": true}
		# beached or spun for 4 s: press R like a player would
		_stuck = _stuck + get_physics_process_delta_time() if state == "running" and car.linear_velocity.length() < 0.5 else 0.0
		if _stuck > 4.0:
			_stuck = 0.0
			reset_car()
		return
	var steer := Input.get_axis("steer_left", "steer_right")
	# the brake key comes on over ~0.25 s (a trigger is analog already): no ABS,
	# so a stab of full brake would lock the fronts at once
	var brake_in := Input.get_action_strength("brake")
	if Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) > 0.05:
		_brake_eased = brake_in
	else:
		var dt := get_physics_process_delta_time()
		_brake_eased = move_toward(_brake_eased, brake_in, dt * (4.0 if brake_in > _brake_eased else 10.0))
	var inp := {"steer": steer, "throttle": Input.get_action_strength("throttle"),
		"brake": _brake_eased, "handbrake": Input.is_action_pressed("handbrake"),
		"analog": absf(Input.get_joy_axis(0, JOY_AXIS_LEFT_X)) > Controls.STEER_DEADZONE}   # (a stick: the steering aids treat it as analog)
	if state == "grid":
		inp.handbrake = true                         # parked at the line until the countdown
		inp.brake = maxf(inp.brake, 0.6)
	if paused():
		inp = {"steer": 0.0, "throttle": 0.0, "brake": 0.4, "handbrake": false}
	if Config.flag("screenshot"):                    # pictures: hold a steering angle / the handbrake
		inp.steer = float(Config.arg("shot_steer", 0.0))
		inp.handbrake = Config.flag("shot_handbrake")
		if state == "grid" and not inp.handbrake:
			inp.brake = 0.0                          # (holding the brake at a standstill would reverse)
		if Config.flag("shot_jump"):                 # rolling, not parked on the line
			inp.brake = 0.0
			inp.throttle = 0.5
	car.inp = inp
	if Input.is_action_just_pressed("reset_car") and state == "running" and not paused():
		reset_car()


func reset_car() -> void:
	var s := clampf(car_s, st.START_S, st.finish_s)
	if Config.flag("smoke") or Config.flag("aicheck"):
		print("[stage] reset at s=%.0f d=%.1f, %.0f km/h" % [car_s, car_d, car.kmh()])
	var d: float = traffic.clear_lane_d(s) if traffic else 0.0
	car.place(st.world_at(s, d), st.heading_at(s))
	if autopilot:
		autopilot.route = PackedVector3Array()           # (back on the highway: no way out of the gas station to follow)
	resets += 1
	penalties += RESET_PENALTY
	_sync_penalties()
	_play("thud", -6.0)
	if touge:
		touge.lose()


func _sync_penalties() -> void:
	if Net.online() and not street_online:            # (a crew shares one car's clock; a street session doesn't)
		set_penalties.rpc(penalties, resets, jump_start)


## Puddles: drive through one at speed and the windshield gets it.
func _puddles() -> void:
	var inside := false
	for p in st.puddles:
		if absf(p.s - car_s) < p.r * 1.3 + 0.8 and absf(p.d - car_d) < p.r * 0.8 + 0.8:
			inside = true
			break
	car.mud_mu = inside
	var spd: float = car.linear_velocity.length()
	if inside and not _in_puddle and spd > 6.0:
		var amount := clampf(spd / 22.0, 0.35, 1.0)
		var sd := randi()
		if Net.online() and not street_online:
			splat.rpc(amount, sd)
		else:
			splat(amount, sd)
	_in_puddle = inside


@rpc("any_peer", "call_local", "reliable")
func splat(amount: float, sd: int) -> void:
	cockpit.splat(amount, sd)
	_said_wipers = false
	_play("splat", -2.0)


@rpc("any_peer", "call_local", "reliable")
func wipe() -> void:
	cockpit.wipe(3)


@rpc("any_peer", "unreliable_ordered")
func send_look(seat: String, yaw: float, pitch: float) -> void:
	cockpit.set_look(seat, yaw, pitch)


func _input(e: InputEvent) -> void:
	if built and e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_F9:
		fit_debug.visible = not fit_debug.visible        # the driver-fit overlay


func _process(dt: float) -> void:
	if not built:
		return
	# wipers: the co-driver's job (the driver's when alone)
	if Input.is_action_just_pressed("wipers") and (my_seat == "codriver" or Net.peer_in("codriver") == 0):
		if Net.online() and not street_online:
			wipe.rpc()
		else:
			wipe()
	if Input.is_action_just_pressed("pause"):
		if _settings:
			_close_settings()                        # (ESC in the settings: back to the pause menu, still paused)
		else:
			_toggle_pause()
	if cockpit.dash and not paused():
		if Input.is_action_just_pressed("dome_light"):
			cockpit.dash.toggle_dome()
		if Input.is_action_just_pressed("screen_page"):
			cockpit.dash.next_page()
	if state == "finished" and Net.is_server() and not paused():
		if Input.is_action_just_pressed("ready"):
			get_parent().continue_event()
		elif Input.is_action_just_pressed("reset_car"):
			get_parent().retry_stage()
		elif Input.is_key_pressed(KEY_TAB) and Net.online() and Net.crew_full():
			Net.swap_seats()
			get_parent().retry_stage()
	# the camera: circling the car before the countdown and after the finish; in the
	# seat for the stage (the driver can press C for the chase cam)
	if state == "running" and my_seat == "driver" and Input.is_action_just_pressed("camera"):
		_chase = not _chase
	var want := "seat"
	if state in ["grid", "finished"]:
		want = "orbit"
	elif state == "running" and _chase and my_seat == "driver":
		want = "chase"
	if Config.flag("screenshot"):
		want = Config.arg("shot_view", "seat")
	if view_override != "" and state == "running":
		want = view_override
	if want != cam.view:
		cam.view = want
		car.set_outside(want != "seat")
		# a car's own interior has windows: the crew are seen from outside too (your own head with them)
		cockpit.visible = want == "seat" or cockpit.own_interior()
		cockpit.set_my_seat(my_seat if want == "seat" else "")
	# the clocks
	var clock := ""
	var red := false
	var board := "--"
	var board_col := Color(1.0, 0.3, 0.2)
	match state:
		"grid":
			clock = "READY"
		"countdown":
			var n := ceili(countdown)
			clock = str(n) if n > 0 else "GO"
			red = n > 0
			board = clock
			board_col = Color(1.0, 0.3, 0.2) if n > 0 else Color(0.3, 1.0, 0.3)
			_lights.count = n
		"running":
			clock = fmt_time(stage_time)
			board = "GO"
			board_col = Color(0.3, 1.0, 0.3)
		"finished":
			clock = fmt_time(result.get("total", stage_time))
	builder.set_start_clock(board, board_col)
	cockpit.map_board.clock_text = clock
	cockpit.map_board.clock_red = red
	# on screen: the start lights, then the stage time
	_lights.state = state
	_lights.since_go = stage_time if state == "running" else 99.0
	_lights.time_text = clock if state in ["running", "finished"] else ""
	var pens: Array = []
	if jump_start:
		pens.append("JUMP START")
	if resets > 0:
		pens.append("%d RESET%s" % [resets, "" if resets == 1 else "S"])
	if mode == "cutup":                                # (scored on points, not the clock: no seconds to add)
		_lights.pen_text = " · ".join(pens)
	else:
		_lights.pen_text = "+%d s  %s" % [int(penalties), " · ".join(pens)] if penalties > 0.0 else ""
	_engine_audio()
	if _t_alive > 12.0 and _hint_label.text.begins_with("YOU"):
		_update_hint()


static func fmt_time(t: float) -> String:
	return "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]


# ── sound ─────────────────────────────────────────────────────────────────

func _audio() -> void:
	_engine = EngineSound.new()                      # (real recordings: engine_sound.gd)
	_engine.name = "EngineSound"
	_engine.car = car
	car.add_child(_engine)
	_gravel = AudioStreamPlayer3D.new()
	_gravel.stream = EngineSound.looped("res://assets/sfx/gravel.wav")
	_gravel.unit_size = 6.0
	_gravel.volume_db = -40.0
	_gravel.bus = "SFX"
	car.add_child(_gravel)
	_gravel.play()
	if TYRE_SQUEAL:
		_squeal = AudioStreamPlayer3D.new()
		_squeal.stream = EngineSound.looped("res://assets/sfx/squeal.wav")
		_squeal.unit_size = 6.0
		_squeal.volume_db = -80.0
		_squeal.bus = "SFX"
		car.add_child(_squeal)
		_squeal.play()
	for n in ["tick", "bell", "splat", "wiper", "thud", "crash"]:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://assets/sfx/%s.wav" % n)
		p.bus = "SFX"
		add_child(p)
		_sfx[n] = p


func _play(n: String, db := 0.0) -> void:
	if _sfx.has(n):
		_sfx[n].volume_db = db
		_sfx[n].play()


func _engine_audio() -> void:
	# (the engine itself plays from EngineSound, under the car)
	var spd: float = car.linear_velocity.length()
	var on_ground := 1.0 if car.grounded > 0 or not car.simulate else 0.0
	var loud: float = clampf(spd / 25.0, 0.0, 1.0) * 0.7 + car.slip * 0.6
	# the gravel under the tyres: quieter on a bridge's planks or snow, just a little
	# road noise on asphalt and ice
	var gravel: float = {"wood": 0.25, "asphalt": 0.12, "ice": 0.12, "snow": 0.5}.get(car.on_surface, 1.0)
	_gravel.volume_db = linear_to_db(maxf(loud * on_ground * gravel, 0.001)) - 14.0   # (well under the voice)
	_gravel.pitch_scale = 0.8 + clampf(spd / 40.0, 0.0, 0.5)
	# on the asphalt the tyres squeal as they near their limit: quietly from ~70 %
	# of their grip, building to a howl in a slide (the warning before it goes)
	if _squeal == null:
		return
	var sq: float = car.grip_use * on_ground * clampf(spd / 8.0, 0.0, 1.0) if car.on_surface == "asphalt" else 0.0
	_squeal_amt = move_toward(_squeal_amt, sq, get_process_delta_time() * 6.0)
	_squeal.volume_db = linear_to_db(maxf(_squeal_amt, 0.001)) - 13.0
	_squeal.pitch_scale = 0.92 + _squeal_amt * 0.16


func _on_hit(impact: float) -> void:
	# a traffic car: the two share the hit by weight (Traffic.shove): it's shoved, the
	# player keeps its share of the speed (it had bounced off as off a wall)
	var hit_car := {}
	if traffic and state == "running":
		for c in traffic.cars:
			if absf(float(c.s) - car_s) < float(c.half_len) + 3.0 and absf(float(c.d) - car_d) < float(c.half_w) + 1.6:
				var r: Dictionary = traffic.shove(c.body, car.last_hit_dv, car.last_hit_v, float(car.mass), car.linear_velocity)
				if not r.is_empty():
					car.nudge(r.back)
					impact *= float(r.share)
					hit_car = c
				break
	_play("crash", clampf(-20.0 + impact, -18.0, 0.0))
	cam.bump(clampf(impact / 15.0, 0.2, 1.0))
	if state != "running":
		return
	if cutup and impact > CRASH_DV:
		cutup.crash()                                # (a traffic car, or the barrier: hard enough is a crash)
		if not hit_car.is_empty():
			traffic.hit(hit_car.body)                # the car that was hit hard stops (hazards on)
		_flash("CRASH  -%d" % CutupScore.CRASH_PENALTY, Color(1.0, 0.3, 0.25))
	if stray:
		stray.bump(car.global_position)
	if touge and touge.chain > 0.0:
		touge.lose()
		_flash("CHAIN LOST", Color(1.0, 0.3, 0.25))


## Leaning on a traffic car (too gently for a hit): the two share the push by weight too.
func _on_rub(body: Node) -> void:
	if traffic and state == "running":
		var r: Dictionary = traffic.shove(body, car.last_hit_dv, car.last_hit_v, float(car.mass), car.linear_velocity)
		if not r.is_empty():
			car.nudge(r.back)


func _on_landed(impact: float) -> void:
	_play("thud", clampf(-18.0 + impact * 2.0, -16.0, 0.0))
	cam.bump(clampf(impact / 10.0, 0.1, 0.7))


# ── the modes: cut up and touge ───────────────────────────────────────────

func _setup_mode(o: Dictionary) -> void:
	match mode:
		"cutup":
			traffic = Traffic.new()
			car.contact_monitor = true               # (what it's touching: a rub against a traffic car, _on_rub)
			car.max_contacts_reported = 4
			traffic.name = "Traffic"                # (the same path everywhere: the host's traffic finds it)
			traffic.mirror = street_online and not multiplayer.is_server()   # (online: the host's traffic, played back)
			add_child(traffic)
			var diff := Modes.difficulty(o)
			traffic.setup(st, diff, seed_value, _start_s())
			cutup = CutupScore.new()
			cutup.near = float(diff.near)
			if looped and not street_online:          # (online: your friends are the rivals)
				rivals = Rivals.new()
				rivals.name = "Rivals"
				add_child(rivals)
				rivals.setup(traffic, st, seed_value)
		"track":
			session = TrackSession.new()
			session.setup(st, str(o.get("session", "practice")))
			var sd: Vector2 = st.box_sd(_track_box)
			session.add_car(Net.my_id(), str(car.setup.get("name", "YOU")), st.unwrap(sd.x, 0.0))
		"touge":
			touge = TougeRules.new()
			var best := Profile.mode_best(Modes.best_key(o, seed_value))
			touge.best_splits = best.get("splits", [])
			if o.get("rules", "time") == "time" and not street_online:   # (online: a race, not your ghost)
				ghost = Ghost.new()
				ghost.name = "Ghost"
				add_child(ghost)
				ghost.setup(Modes.best_key(o, seed_value))
			stray = StrayCar.new()
			add_child(stray)
			stray.setup(st, seed_value, str(builder.get("mood")) == "night")


## A night stage (the touge by default, any stage at a night hour: the builder's mood is
## the hour's once it's lit): every car's lamps on (CarLamps; CarLook's own at dusk); the
## street lamps (a touge's, the loop's viaducts and city) light round your car whenever
## they're lit, dusk included.
func _night_lights() -> void:
	night = str(builder.get("mood")) == "night"
	if builder.get("street_lamps") != null:
		builder.street_lamps.target = car
	if cockpit.dash:
		cockpit.dash.night = night                   # (its backlit dials and buttons, lit)
	if not night:
		return
	_fit_lamps(car)
	# the dials' glow in the cabin: the wheel and your hands just there in the dark
	var dash := OmniLight3D.new()
	dash.name = "DashGlow"
	dash.light_color = Color(1.0, 0.72, 0.42)
	dash.light_energy = 0.4
	dash.omni_range = 1.2
	dash.shadow_enabled = false
	car.add_child(dash)
	dash.position = cockpit.eye_for(my_seat if my_seat != "" else "driver") + Vector3(0.0, -0.32, -0.5)


func _fit_lamps(c) -> void:
	if not night or c.body_model == null:
		return
	CarLamps.fit(c, c.body_model, true, c == car)      # (a tail light, twin beams on yours only; a new body: fitted anew)


## At night the other drivers' headlight beams: the two nearest you within 150 m (a
## real light each; the rest just glow: the web build can only light so much at once).
func _others_beams() -> void:
	var near: Array = []
	for id in others:
		var c = others[id]
		if is_instance_valid(c) and c.get_node_or_null("CarLamps"):
			near.append([c.global_position.distance_to(car.global_position), c])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for k in near.size():
		near[k][1].get_node("CarLamps").set_beam(k < 2 and near[k][0] < 150.0)


## (host, online cut up) The other players for the traffic: where each one's car is on
## the road (from its stream), so the traffic fills in round them and minds them, and
## which machines get which cars.
func _traffic_for_everyone() -> void:
	var ps: Array = []
	var peers := {}
	for id in others:
		var c = others[id]
		if not is_instance_valid(c):
			continue
		var at: Dictionary = st.locate(c.global_position, int(_hints.get(id, -1)))
		_hints[id] = at.i
		var s: float = car_s + (wrapf(float(at.s) - car_s, -st.length * 0.5, st.length * 0.5) if looped else float(at.s) - car_s)
		var p := {"s": s, "d": float(at.d), "v": c.linear_velocity.dot(st.forward_at(s))}
		ps.append(p)
		if id in _ready_peers or _loaded_peers.has(id):
			peers[id] = p
	traffic.others_p = ps
	traffic.net_peers = peers


## (a street session, the touge) Where you are in the race: 1 + those already over the
## line + those further down the road than you.
func _race_place() -> int:
	var ahead := standings.size()
	for id in others:
		var c = others[id]
		if not is_instance_valid(c) or standings.any(func(e): return int(e[0]) == id):
			continue
		var at: Dictionary = st.locate(c.global_position, int(_hints.get(id, -1)))
		_hints[id] = at.i
		if float(at.s) > car_s:
			ahead += 1
	return ahead + 1


## Every physics tick in a mode: the traffic, the score, the splits, the drift.
func _mode_tick(dt: float) -> void:
	var v_along: float = car.linear_velocity.dot(st.forward_at(car_s))
	if traffic:
		traffic.player = {"s": car_s, "d": car_d, "v": v_along}
		traffic.running = state != "grid"
		if street_online and multiplayer.is_server():
			_traffic_for_everyone()
	if session and state == "running":
		_track_tick(dt)
	if state == "running":
		if cutup:
			for nm in cutup.update(dt, {"s": car_s, "d": car_d, "v": v_along}, traffic.snapshot()):
				_flash("NEAR MISS  +%d%s" % [nm.points, "   x%d" % cutup.combo if cutup.combo > 1 else ""], Color(1.0, 0.85, 0.2))
		if rivals:
			rivals.tick(dt, {"s": car_s, "d": car_d, "v": v_along}, car.simulate and Input.is_action_just_pressed("flash"))
			for ev in rivals.events:
				_flash(ev[0], ev[1])
				if int(ev[2]) > 0:
					cutup.bonus(int(ev[2]))
			rivals.events.clear()
		if ghost:
			ghost.tick(stage_time, car.global_transform.translated_local(Vector3(0.0, -car._ground(), 0.0)))
		if street_online and touge:
			_pos_t -= dt
			if _pos_t <= 0.0:
				_pos_t = 0.25
				_place = _race_place()
		if touge:
			if touge.split_check(car_s, st.START_S, stage_time):
				var dl: float = touge.last_split_delta
				_flash("%d km   %s%s" % [touge.splits.size(), fmt_time(stage_time),
					"" if dl == INF else ("   %+.1f" % dl)], Color(0.4, 1.0, 0.45) if dl < 0.0 else (Color(1.0, 0.4, 0.3) if dl != INF else Color.WHITE))
			if opts.get("rules", "time") == "drift":
				var on_road: bool = absf(car_d) < st.width_at(car_s) * 0.5 + 0.6
				var was: float = touge.chain
				touge.drift_update(dt, car.linear_velocity, -car.global_transform.basis.z, on_road)
				if was > 0.0 and touge.chain == 0.0 and not on_road:
					_flash("OFF THE ROAD: CHAIN LOST", Color(1.0, 0.3, 0.25))
	if _mode_label:
		_mode_label.text = _mode_text()
		_flash_t -= dt
		_flash_label.modulate.a = clampf(_flash_t / 0.5, 0.0, 1.0)


func _mode_text() -> String:
	if session:
		return _track_text()
	if cutup:
		var t := "SCORE  %d" % cutup.total()
		if rivals:
			var b: String = rivals.hud_text({"s": car_s, "d": car_d, "v": car.linear_velocity.dot(st.forward_at(car_s))})
			if b != "":
				t = b + "\n" + t
		if cutup.combo > 0:
			t += "\nCOMBO  x%d   %.0f s" % [cutup.combo, maxf(CutupScore.COMBO_TIME - cutup.since_near, 0.0)]
		return t + "\n%.0f km/h" % car.kmh()
	if touge:
		# (the chase cam has no dash board: the clock and the speed are here too)
		if opts.get("rules", "time") == "drift":
			var t2 := "DRIFT  %d" % touge.total()
			if touge.chain > 0.0:
				t2 += "\nCHAIN  +%d   x%.1f" % [int(touge.chain), touge.multiplier()]
			return t2 + ("\n%.0f deg" % touge.angle if touge.drifting else "") + "\n%.0f km/h" % car.kmh()
		var best := Profile.mode_best(Modes.best_key(opts, seed_value))
		var t3 := "TIME  %s" % fmt_time(stage_time if state != "grid" else 0.0)
		if street_online and _place > 0 and state == "running":
			t3 = "POS  %d / %d\n" % [_place, others.size() + 1] + t3
		if touge.last_split_delta != INF and stage_time - touge.last_split_at < 8.0:
			t3 += "   %+.1f" % touge.last_split_delta
		return t3 + "\nBEST  %s" % (fmt_time(float(best.value)) if not best.is_empty() else "--") + "\n%.0f km/h" % car.kmh()
	return ""


func _flash(text: String, col: Color) -> void:
	if _flash_label == null:
		return
	_flash_label.text = text
	_flash_label.add_theme_color_override("font_color", col)
	_flash_t = 2.0


## The run's over: the mode's own result and best (the results panel shows the lines).
func _finish_mode() -> void:
	mode_result = {}
	if mode == "":
		return
	var key := Modes.best_key(opts, seed_value)
	var lines: Array = []
	if session:
		var c: Dictionary = session.cars.get(Net.my_id(), {})
		var best_lap := float(c.get("best", INF))
		var k2 := key + "/" + str(car.setup.get("car", ""))
		var old := Profile.mode_best(k2)
		var rec := best_lap != INF and Profile.record_mode(k2, best_lap, true)
		lines = ["BEST LAP  %s%s" % [fmt_lap(best_lap) if best_lap != INF else "--", "   NEW RECORD" if rec else
			("   (record %s)" % fmt_lap(float(old.value)) if not old.is_empty() else "")],
			"%d laps · %d invalidated" % [int(c.get("laps", 0)), int(c.get("cuts", 0))]]
		mode_result = {"time": best_lap, "best": rec}
	elif cutup:
		var sc: int = cutup.finish()
		var best := sc > 0 and Profile.record_mode(key, float(sc), false)
		lines = ["SCORE  %d%s" % [sc, "   NEW BEST" if best else ""],
			"%d near misses · best combo x%d · %d crash%s" % [cutup.near_misses, cutup.best_combo, cutup.crashes, "" if cutup.crashes == 1 else "es"]]
		if rivals and rivals.beaten + rivals.lost > 0:
			lines.append("rivals beaten %d · lost %d" % [rivals.beaten, rivals.lost])
		mode_result = {"score": sc, "best": best}
	elif touge and opts.get("rules", "time") == "drift":
		var sc2: int = touge.finish()
		var best2 := sc2 > 0 and Profile.record_mode(key, float(sc2), false)
		lines = ["DRIFT POINTS  %d%s" % [sc2, "   NEW BEST" if best2 else ""],
			"%d chains · best %d · %d lost" % [touge.chains, touge.best_chain, touge.lost]]
		mode_result = {"score": sc2, "best": best2}
	elif touge:
		var total: float = result.time + result.penalties
		var old := Profile.mode_best(key)
		var best3 := Profile.record_mode(key, total, true, touge.splits)
		if best3 and ghost and result.penalties <= 0.0:
			ghost.save_record(str(car.setup.get("model", "")))   # (the next run races it; a run with resets doesn't make a ghost)
		lines = ["PASS RECORD  %s%s" % [fmt_time(total) if best3 else fmt_time(float(old.value)),
			"   NEW RECORD" if best3 else "   (%+.1f s)" % (total - float(old.value))]]
		mode_result = {"time": total, "best": best3}
	mode_result["lines"] = lines


# ── HUD: hints, results, pause (no HUD while driving: the map board is the HUD) ─

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)
	_lights = StartLights.new()
	_hud.add_child(_lights)
	var font: Font = load("res://assets/fonts/Oswald-Medium.woff2")
	_hint_label = Label.new()
	_hint_label.add_theme_font_override("font", font)
	_hint_label.add_theme_font_size_override("font_size", 22)
	_hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint_label.add_theme_constant_override("outline_size", 6)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.offset_top = -120
	_hint_label.offset_left = -600
	_hint_label.offset_right = 600
	_hud.add_child(_hint_label)
	_big_label = Label.new()
	_big_label.add_theme_font_override("font", load("res://assets/fonts/Oswald-Bold.woff2"))
	_big_label.add_theme_font_size_override("font_size", 48)
	_big_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_big_label.add_theme_constant_override("outline_size", 10)
	_big_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_big_label.offset_top = 390                # under the start lights
	_big_label.offset_left = -500
	_big_label.offset_right = 500
	_big_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_big_label)
	# the results: the banner art (rally: STAGE COMPLETE; the modes: RESULTS), the
	# stage, its numbers, a street race's podium, then what next
	_results = _panel()
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	_results.add_child(rv)
	var banner := UI.art("banner_results" if mode != "" else "banner_stage")
	if banner:
		var bt := TextureRect.new()
		bt.texture = banner
		bt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		bt.custom_minimum_size = Vector2(560, 560.0 * banner.get_height() / banner.get_width())
		rv.add_child(bt)
	_results_head = UI.label("", 30, UI.YELLOW, true)
	_results_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(_results_head)
	_results_label = Label.new()
	_results_label.add_theme_font_override("font", font)
	_results_label.add_theme_font_size_override("font_size", 28)
	_results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(_results_label)
	_race_box = VBoxContainer.new()
	_race_box.add_theme_constant_override("separation", 2)
	rv.add_child(_race_box)
	_results_foot = UI.label("", 22, UI.CREAM)
	_results_foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(_results_foot)
	_results.visible = false
	_pause = _panel()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_pause.add_child(vb)
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var buttons := [["RESUME", _toggle_pause], ["SETTINGS", _open_settings]]
	if looped:
		buttons.append(["END RUN", _end_run])          # (a loop has no finish: the run ends when you say)
	buttons.append(["QUIT TO MENU", func(): get_parent().to_menu()])
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.add_theme_font_override("font", font)
		btn.add_theme_font_size_override("font_size", 26)
		btn.custom_minimum_size = Vector2(320, 56)
		btn.pressed.connect(b[1])
		vb.add_child(btn)
		if b[0] == "SETTINGS":
			_pause_settings = btn
	_pause.visible = false
	# the modes' numbers: top right, and a flash in the middle for the moments
	_mode_label = Label.new()
	_mode_label.add_theme_font_override("font", load("res://assets/fonts/Oswald-Bold.woff2"))
	_mode_label.add_theme_font_size_override("font_size", 34)
	_mode_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_mode_label.add_theme_constant_override("outline_size", 8)
	_mode_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_mode_label.offset_left = -520
	_mode_label.offset_right = -30
	_mode_label.offset_top = 24
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_child(_mode_label)
	_flash_label = Label.new()
	_flash_label.add_theme_font_override("font", load("res://assets/fonts/Oswald-Bold.woff2"))
	_flash_label.add_theme_font_size_override("font_size", 52)
	_flash_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_flash_label.add_theme_constant_override("outline_size", 10)
	_flash_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_flash_label.offset_top = 210
	_flash_label.offset_left = -500
	_flash_label.offset_right = 500
	_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_flash_label)


## A panel in the middle of the screen, in the art's style: the modes' night,
## or the rally's carbon.
func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel_skin("night" if mode != "" else "rally", 28))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	_hud.add_child(p)
	return p


## On a loop (no finish): the run ends here, with its results.
func _end_run() -> void:
	if _pause.visible:
		_toggle_pause()
	if state != "running":
		return
	var args := [stage_time, penalties, resets, jump_start]
	if Net.online() and not street_online:
		stage_finished.rpc(args[0], args[1], args[2], args[3])
	else:
		stage_finished(args[0], args[1], args[2], args[3])     # (a street session: your own run ends, not theirs)


func _toggle_pause() -> void:
	_pause.visible = not _pause.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _pause.visible else Input.MOUSE_MODE_CAPTURED


## Paused: the pause menu is up, or the settings opened from it (the car held on the
## brake, the mouse free). (The stage itself goes on: online, the others still drive.)
func paused() -> bool:
	return _pause.visible or _settings != null


## SETTINGS from the pause menu: the main menu's own panel (graphics, sound, the aids ...)
## over the stage, still paused. What changes at once from the main menu (the graphics,
## the sound, the mouse) changes here at once too. BACK or ESC: back to the pause menu.
func _open_settings() -> void:
	if _settings != null:
		return
	_pause.visible = false
	_settings = ColorRect.new()                      # a shade over the stage, the panel in the middle
	_settings.name = "PauseSettings"
	_settings.color = Color(0, 0, 0, 0.35)
	_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.add_child(_settings)
	var p := SettingsPanel.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.back.connect(_close_settings)
	_settings.add_child(p)


func _close_settings() -> void:
	if _settings == null:
		return
	_settings.queue_free()
	_settings = null
	_pause.visible = true
	_pause_settings.grab_focus()


func _update_hint() -> void:
	if _hint_label == null:
		return
	var t := ""
	var pad: bool = Controls.has_pad()
	match state:
		"grid":
			if _waiting:
				t = "A race is on: you're in the next one (watch this one)"
			elif street_online and others.is_empty() and Net.is_server():
				t = "Waiting for friends to join (port %d, your IPs: %s)... or press %s to go now" % [
					Config.port, ", ".join(_my_ips()), "START" if pad else "ENTER"]
			elif Net.online() and not Net.crew_full():
				t = "Waiting for your crew to join...  (port %d, your IPs: %s)" % [Config.port, ", ".join(_my_ips())]
			elif not all_loaded:
				t = "Loading the stage..."
			elif Net.is_server():
				t = "Press %s to start the countdown" % ("START" if pad else "ENTER")
			else:
				t = "Waiting for the host to start the countdown"
			if _t_alive < 12.0:
				t = _seat_help(pad) + "\n" + t
		"countdown":
			t = "Count your driver in!" if my_seat == "codriver" else ""
		"running", "finished":
			t = ""
	_hint_label.text = t
	var title: String = "%s\n%s" % [opts.title, opts.stage_name] if opts.get("mode") == "story" else "STAGE %d\n%s" % [stage_no, st.describe()]
	if mode != "":
		title = Modes.title(opts, st)
	_big_label.text = title if state == "grid" else ""


func _seat_help(pad: bool) -> String:
	if my_seat == "driver":
		var alone := " · F wipers" if Net.peer_in("codriver") == 0 else ""
		return ("YOU DRIVE: left stick steer · RT gas · LT brake · B handbrake · Y reset · R3 chase cam" + (" · LB flash a rival" if rivals else "") if pad
			else "YOU DRIVE: WASD / arrows · SPACE handbrake · R reset%s · C chase cam%s" % ["" if mode == "cutup" else " (+5 s)",
				" · H flash a rival" if rivals else ""] + alone)
	return ("YOU RIDE SHOTGUN: hold LT to look at the map and call the road · A wipers · right stick look" if pad
		else "YOU RIDE SHOTGUN: hold RIGHT MOUSE (or Q) to look at the map and call the road · F wipers · mouse to look")


func _my_ips() -> Array:
	var out: Array = []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254"):
			out.append(ip)
	return out.slice(0, 3)


## (screenshots) The results panel with made-up numbers; race: a street touge's
## podium too (made-up names).
func shot_results(race: bool) -> void:
	state = "finished"
	result = {"time": 214.37, "penalties": 0.0, "total": 214.37, "resets": 0, "jump_start": false, "stage": stage_no, "seed": seed_value}
	mode_result = {"lines": ["PASS RECORD  3:31.90   (+2.5 s)"]} if touge else {}
	if race:
		street_online = true
		var names := ["MIKA", "SAMI", "JO"]
		for k in names.size():
			Net.players[k + 2] = {"name": names[k], "seat": "racer"}
		standings = [[3, 211.02], [Net.my_id(), 214.37], [2, 219.8], [4, 230.15]]
	_show_results()


## A street touge's finishers so far, in order: the podium with its badges
## (assets/ui/badge_1..3), and who's still on the way down.
func _show_race() -> void:
	for c in _race_box.get_children():
		c.queue_free()
	_race_box.visible = street_online and touge
	if not _race_box.visible:
		return
	var title := UI.label("THE RACE", 26, UI.YELLOW, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_race_box.add_child(title)
	for k in standings.size():
		var id := int(standings[k][0])
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		var badge := UI.art("badge_%d" % (k + 1)) if k < 3 else null
		if badge:
			var b := TextureRect.new()
			b.texture = badge
			b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			b.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			b.custom_minimum_size = Vector2(36, 40)
			row.add_child(b)
		else:
			row.add_child(UI.label("%d." % (k + 1), 24, UI.CREAM, true))
		row.add_child(UI.label("%s   %s" % ["YOU" if id == Net.my_id() else Net.player_name(id), fmt_time(float(standings[k][1]))],
			24, UI.YELLOW if id == Net.my_id() else UI.CREAM, k == 0))
		_race_box.add_child(row)
	var still: Array = []
	for id in others:
		if not standings.any(func(e): return int(e[0]) == id):
			still.append(Net.player_name(id))
	if not still.is_empty():
		var l := UI.label("still racing: " + ", ".join(still), 18, UI.DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_race_box.add_child(l)


## Main's lines under the results (credits, rally standings) and what ENTER does.
func set_result_extra(lines: Array, next_text: String) -> void:
	_result_extra = lines
	_next_text = next_text
	if state == "finished":
		_show_results()


func _show_results() -> void:
	_results.visible = true
	var r := result
	var head: String = opts.stage_name if opts.get("mode") == "story" else "STAGE %d" % r.stage
	if mode != "":
		head = Modes.title(opts, st).replace("\n", "  ·  ")
	if UI.art("banner_results" if mode != "" else "banner_stage") == null:
		head += "  COMPLETE"                           # (no banner art to say it)
	_results_head.text = head
	var lines := ["Time  %s" % fmt_time(r.time)]
	lines.append_array(mode_result.get("lines", []))
	_results_label.add_theme_font_size_override("font_size", 22 if _result_extra.size() > 3 else 28)
	if r.penalties > 0.0:
		var why: Array = []
		if r.jump_start:
			why.append("jump start")
		if r.resets > 0:
			why.append("%d reset%s" % [r.resets, "s" if r.resets > 1 else ""])
		lines.append("Penalties  +%.0f s  (%s)" % [r.penalties, ", ".join(why)])
	lines.append("TOTAL  %s" % fmt_time(r.total))
	_results_label.text = "\n".join(lines)
	_show_race()
	var foot: Array = []
	if not _result_extra.is_empty():
		foot.append_array(_result_extra)
		foot.append("")
	if Net.is_server():
		foot.append("ENTER  %s     R  retry this one" % _next_text + ("     TAB  swap seats" if Net.online() and Net.crew_full() else ""))
	else:
		foot.append("Waiting for the host...")
	_results_foot.text = "\n".join(foot)
	_update_hint()


# ── Track Mode ───────────────────────────────────────────────────────────────

## The route out of pit box k: away from the box into the fast lane, down it to the end of
## the lane, along the taper back onto the track (the autopilot follows it, then the racing line).
func _pit_out_route(k: int) -> PackedVector3Array:
	var r := PackedVector3Array()
	var sd: Vector2 = st.box_sd(k)
	var p: Dictionary = st.pit
	var s0: float = st.unwrap(sd.x, 0.0)
	var fast := float(p.fast_d)
	r.append(st.world_at(s0 + 6.0, sd.y - 1.0))
	r.append(st.world_at(s0 + 14.0, fast))
	var s := s0 + 24.0
	while s < float(p.s_out0):
		r.append(st.world_at(s, fast))
		s += 10.0
	s = float(p.s_out0)
	while s < float(p.s_out1):
		r.append(st.world_at(s, st.pit_inner_d(s) + 2.0))
		s += 10.0
	r.append(st.world_at(float(p.s_out1) + 30.0, st.half_at(float(p.s_out1)) - 3.0))
	r.append(st.world_at(float(p.s_out1) + 70.0, st.half_at(float(p.s_out1)) - 4.0))
	return r


## Every running tick in Track Mode: the session's timing (your car), its news as flashes.
func _track_tick(dt: float) -> void:
	var pit: bool = st.in_pit_lane(car_s, car_d)
	session.tick(dt, {Net.my_id(): {"s": car_s, "d": car_d, "pit": pit}})
	for ev in session.events:
		if ev.id != Net.my_id():
			continue
		match str(ev.kind):
			"sector":
				var dl := float(ev.delta)
				_flash("S%d   %s%s" % [int(ev.sector) + 1, fmt_lap(float(ev.time)), "" if dl == INF else "   %+.3f" % dl],
					Color(0.75, 0.4, 1.0) if ev.purple else (Color(0.4, 1.0, 0.45) if dl < 0.0 else (Color(1.0, 0.85, 0.3) if dl != INF else Color.WHITE)))
			"lap":
				var tag := ""
				if not ev.valid:
					tag = "   INVALID"
				elif ev.session_best or ev.pb:
					tag = "   PERSONAL BEST"
				_flash("LAP %d   %s%s" % [int(ev.lap), fmt_lap(float(ev.time)), tag],
					Color(1.0, 0.35, 0.3) if not ev.valid else (Color(0.75, 0.4, 1.0) if ev.pb else Color.WHITE))
			"invalid":
				_flash("LAP INVALID: %s" % ev.reason, Color(1.0, 0.35, 0.3))
			"out":
				_flash("OUT LAP", Color(0.9, 0.9, 0.9))
	session.events.clear()
	if st.in_pit_limit(car_s, car_d) and car.kmh() > float(st.pit.limit_kmh) + 2.0:
		_pit_warn_t -= dt
		if _pit_warn_t <= 0.0:
			_pit_warn_t = 2.0
			_flash("PIT LIMIT %d KM/H" % int(st.pit.limit_kmh), Color(1.0, 0.85, 0.2))


var _pit_warn_t := 0.0


func _track_text() -> String:
	var c: Dictionary = session.cars.get(Net.my_id(), {})
	if c.is_empty():
		return ""
	var t: float = session.lap_time(Net.my_id())
	var lines := []
	lines.append("%s   %s" % ["OUT LAP" if t == INF else "LAP %d" % (int(c.laps) + 1), "" if t == INF else fmt_lap(t)])
	if not c.valid and t != INF:
		lines[0] += "   INVALID"
	lines.append("LAST  %s" % (fmt_lap(float(c.last)) if float(c.last) != INF else "--"))
	lines.append("BEST  %s" % (fmt_lap(float(c.best)) if float(c.best) != INF else "--"))
	if st.in_pit_lane(car_s, car_d):
		lines.append("PIT LANE  %d KM/H" % int(st.pit.limit_kmh))
	return "\n".join(lines) + "\n%.0f km/h" % car.kmh()


## A lap time: 1:47.312.
static func fmt_lap(t: float) -> String:
	if t == INF or t < 0.0:
		return "--"
	var m := int(t / 60.0)
	return "%d:%06.3f" % [m, t - m * 60.0]
