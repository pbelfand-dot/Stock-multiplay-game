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
const RaceControl = preload("res://scripts/game/race_control.gd")
const RaceField = preload("res://scripts/game/race_field.gd")
const TrackNet = preload("res://scripts/game/track_net.gd")
const RaceTower = preload("res://scripts/ui/race_tower.gd")
const RaceDriver = preload("res://scripts/vehicle/race_driver.gd")
const RaceLine = preload("res://scripts/game/race_line.gd")
const RaceHud = preload("res://scripts/ui/race_hud.gd")
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
const MusicPanel = preload("res://scripts/ui/music_panel.gd")
const MusicPlayer = preload("res://scripts/audio/music_player.gd")
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
const Graphics = preload("res://scripts/render/graphics.gd")
const Replay = preload("res://scripts/game/replay.gd")
const Weather = preload("res://scripts/render/weather.gd")
const PitPlan = preload("res://scripts/game/pit_plan.gd")
const TrackSeries = preload("res://scripts/game/track_series.gd")
const WorldMaterials = preload("res://scripts/render/world_materials.gd")

signal progress(fraction: float, what: String)
signal stage_generated

const COUNTDOWN := 5.0
const ENGINE_START_LATEST := 2.5     # s after the stage is built the engine starts whatever (no loading screen to wait for)
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
var _stuck_s := 0.0                   # (the race autopilot) where it last made progress round the lap
var _mud_t := 0.0
var _said_wipers := false
var _chase := false                 # the driver picked the chase cam (C)
var _tv := false                     # (Track Mode) ... or the broadcast's trackside TV camera (C again)
var _tv_on := false                  # (it's filming now)
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
var _settings: Control               # SETTINGS (or MUSIC) opened from the pause menu (null: shut)
var _pause_music: Button             # the pause menu's MUSIC
var _settings_from: Button           # the pause menu's button that opened it (the focus goes back to it)
var _t_alive := 0.0
var _sfx := {}
var _engine                        # EngineSound
var _engine_started := false        # the start-up's begun (the door, the starter: start_engine)
var _engine_asked := false
var _engine_wait := 0.0
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
var _race_hud                        # Track Mode's car panel (RaceHud)
var fuel_per_lap := 0.0              # the litres the last timed lap burnt (Track Mode)
var race_ctl                         # RaceControl (Track Mode's qualifying and races)
var field                            # RaceField: the AI cars
var weather                          # Weather: Track Mode's rain (WET), else null
var field_entries: Array = []        # Modes.track_field: who's in it
var grid_ids: Array = []             # the race's grid, pole first (your id among the AI's)
var race_rows: Array = []            # the classification at the end
var next_grid: Array = []            # (a weekend's qualifying) the race's grid, from its result
var _tower                           # RaceTower
var _my_driver                       # (--autopilot in a race or qualifying) a RaceDriver at your wheel
var _end_t := -1.0                   # s until the results after you've taken the flag
var _pit_stop := 0.0                 # s left of your pit stop (held in the box)
var _green_flash := false
var _fuel_at_line := -1.0
# Track Mode online (a street session on the circuit): the host's race control for everyone (TrackNet)
var net                              # TrackNet
var _ai_view                         # (a guest) the host's AI cars, drawn from its stream (RaceField.setup_view)
var _locked := false                 # the session's started: its grid (grid_ids) and pit boxes are set
var _boxes := {}                     # player id -> pit box (online)
var _from_pits := false              # (online) joined once the session was on: out of the pit box, not off the grid
var _board_rows: Array = []          # the timing board the tower's drawn from (Game._board; a guest: the host's)
var lights_seen: Array = []          # (tests) the start lights shown here, then "go"
var own_timing                       # (tests, a guest) TrackSession: our own laps timed here, to check the host's
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
var replay                           # Replay: the run recorded, played back from the results / the pause menu
var _pause_replay: Button            # the pause menu's REPLAY (the focus comes back to it)


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
	if Config.music:                                       # (the AUTO playlist: this mode's songs)
		Config.music.set_context(MusicPlayer.context_for(mode, street_online, str(o.get("class", ""))))
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
	WorldMaterials.wet = float(o.get("wet", 0.0))          # (Track Mode's WET weather: the roads built wet)
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
	_weather(o)
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
	replay = Replay.new()                         # (records every tick of the run; plays it back: replay.gd)
	add_child(replay)
	replay.setup(self)
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
	return _setup_for(Net.my_id(), true)


## A street session's other driver's car, as their machine runs it (drawn here, not simulated).
func _remote_setup(id: int) -> Dictionary:
	return _setup_for(id, false) if mode == "track" else Catalog.for_stage(Net.car_setup_for(id), st)


## Player id's car for this stage (mine: the one this machine drives, with its race state).
func _setup_for(id: int, mine: bool) -> Dictionary:
	var base: Dictionary = Net.car_setup_for(id) if street_online else Net.car_setup()
	if mode == "track":
		# (Track Mode: a car of the session's class: the driver's if it's one, else the class's own)
		var want := Modes.track_car(opts, str(base.get("car", "")))
		if want != str(base.get("car", "")) and want != "" and mine:
			var wt := str(base.get("wheel_type", "stock"))
			base = Profile.setup_for(want)
			if Config.flag("wheel_type"):              # (pictures: --wheel_type=X follows the car)
				base["wheel_type"] = wt
		elif want != str(base.get("car", "")) and want != "":
			# (another player's: the class's car in their garage car's colours and number)
			var paint := {"livery": base.get("livery", "plain"), "number": base.get("number", 7), "number_on": base.get("number_on", false)}
			if not (base.get("colours", []) as Array).is_empty():
				paint["colours"] = base.colours
			base = Catalog.setup(want, paint, {}, {})
	if mode == "track":
		# (every car at its homologated spec, as the AI's: the garage's paint and wheels, no upgrades)
		base = Catalog.setup(str(base.get("car", "")), {"colours": base.get("colours", []), "livery": base.get("livery", "plain"),
			"wheels": base.get("wheels", "silver"), "wheel_type": base.get("wheel_type", "stock"), "number": base.get("number", 7),
			"number_on": base.get("number_on", false)}, {},
			{"tyre": base.get("tyre", "auto"), "preset": base.get("preset", "auto")})
	var s := Catalog.for_stage(base, st)
	if mode == "track" and mine:
		# (a race car's state: its tyres warm from cold on a medium, practice's half tank, the
		# car's own ABS and TC; the air by the hour)
		s["race_sim"] = true
		s["race"] = Modes.race_opts(opts)
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
	# (not on a Track Mode car once it's going: its race state, the tyres' heat, the fuel, is live, and
	# someone joining or leaving would put it back to cold tyres at full speed)
	var applied: bool = car.apply_setup(setup) if not (mode == "track" and state != "grid") else false
	if (applied or moved) and state == "grid":     # another car (a new driver's), another slot: put it down again
		car.place(_start_pos, _start_yaw)
	cockpit.set_paint(setup.colours[0])
	car.set_simulating(driver_here)
	cam.attach(car, seat, cockpit.eye_for(seat))
	if seat == "driver" and not cockpit.hood:
		cam.aim_at_wheel(cockpit.wheel_c)
	elif cockpit.hood:
		cam.pitch = -0.03                            # (over the bonnet: level, the road ahead; no wheel to show)
	cockpit.set_my_seat(seat)
	ai.enabled = not street_online and Net.peer_in("codriver") == 0 and mode == ""
	if street_online:
		_sync_racers()
		if multiplayer.is_server():
			for id in _loaded_peers.keys():          # (someone left: stop streaming at them)
				if not Net.players.has(id):
					_loaded_peers.erase(id)
			_to_ready("set_ready_peers", [_loaded_peers.keys()])
			if net:
				_net_left()
		if field and not _locked and state == "grid":
			_field_to_grid()                         # (a racer more or less: the AI's places move)
	_update_hint()


## A car's place on the grid (its driver's slot in a street session: two abreast on a
## touge, four on the highway, rows 9 m apart; cut up on the loop: at the gas station's
## pumps, LoopGen.station_spot): [position, heading].
func _grid_spot(id: int) -> Array:
	var k := maxi(Net.racers().find(id), 0) if street_online else 0
	if _at_station():
		return st.station_spot(k)
	if circuit:
		# (practice: everyone from their own box, the solo driver from the one by the line; a race:
		# the grid, but online one who joined once it was on from their box)
		var box := _box_of(id)
		if id == Net.my_id():
			_track_box = box
		if str(opts.get("session", "practice")) == "race":
			_plan_field()
			if id in grid_ids and not (id == Net.my_id() and _from_pits):
				var sd := _start_sd(id)
				return [st.world_at(sd.x, sd.y) + Vector3.UP * 0.6, st.heading_at(sd.x)]
		return st.box_spot(box)
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
			others[id].apply_setup(_remote_setup(id))   # (their garage car may have come since)
			_fit_lamps(others[id])
			continue
		var c = RallyCar.new()
		c.name = "Car_%d" % id
		c.setup = _remote_setup(id)
		add_child(c)
		c.set_simulating(false)
		var spot := _grid_spot(id)
		c.place(spot[0], spot[1])
		c.set_outside(true)
		if not bool(Net.session.get("collide", true)):
			car.add_collision_exception_with(c)
			c.add_collision_exception_with(car)
		if field:
			field.ghost(c)                            # (online Track Mode: the AI pass through the players)
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


## The cars a replay records and can follow (replay.gd): yours, the other drivers' (online), and
## a RaceField's if one's on the track (Track Mode's AI cars: a "RaceField" node with a `cars`
## dict of RallyCars). Any RallyCar can join the list: the replay keeps a recording per car,
## keyed by its path under the Game.
func replay_targets() -> Array:
	var out: Array = []
	if is_instance_valid(car):
		out.append(car)
	for id in others:
		if is_instance_valid(others[id]):
			out.append(others[id])
	var field := get_node_or_null("RaceField")
	if field and "cars" in field:
		var cs = field.get("cars")
		var list: Array = (cs as Dictionary).values() if cs is Dictionary else (cs if cs is Array else [])
		for c in list:
			if is_instance_valid(c) and c is RigidBody3D and not c in out:
				out.append(c)
	return out


# ── loading handshake (host) ──────────────────────────────────────────────

@rpc("any_peer", "call_local", "reliable")
func loaded() -> void:
	if not multiplayer.is_server():
		return
	var who := multiplayer.get_remote_sender_id()
	_loaded_peers[who] = true
	if Net.street():
		_to_ready("set_ready_peers", [_loaded_peers.keys()])
		if who != Net.my_id() and net and _locked:
			catch_up.rpc_id(who, "running" if _net_joined(who) else "finished")   # (Track Mode: out of the pit lane, or the next one)
		elif who != Net.my_id() and state != "grid":
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
## straight in; on a touge you're in the next race (the grid, watching this one); on the circuit
## out of your pit box (TrackNet.joined_late said which) into the session that's on.
@rpc("authority", "reliable")
func catch_up(host_state: String) -> void:
	if looped and host_state in ["countdown", "running"]:
		state = "running"
		stage_time = 0.0
		if circuit and net and net.late_box >= 0:
			_from_pits = true
			_boxes[Net.my_id()] = net.late_box
			var spot := _grid_spot(Net.my_id())
			_start_pos = spot[0]
			_start_yaw = spot[1]
			car.place(_start_pos, _start_yaw)
			car_s = st.unwrap(float(st.box_sd(_track_box).x), 0.0)
			_hint = -1
			autopilot.route = _pit_out_route(_track_box)
			_flash("FROM THE PIT LANE", Color(1.0, 0.85, 0.3))
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
	if race_ctl and race_ctl.kind == "race":
		state = "running"                          # (the race's own start: the lights, or the rolling start)
		stage_time = 0.0
		race_ctl.begin()
		for drv in field.drivers if field else []:
			drv.task = "formation" if race_ctl.start_type == "rolling" else "hold"
		_update_hint()
		return
	if _no_count():
		state = "running"                          # (nothing to start: just drive)
		stage_time = 0.0
		_update_hint()
		return
	state = "countdown"
	countdown = COUNTDOWN
	_last_count = -1
	car.place(_start_pos, _start_yaw)
	ai.hush()                                    # the count has to land on the second
	_update_hint()


## Modes with nothing to start (the owner: "not every mode needs a timer"): cut up (free driving
## through the traffic) and Track Mode's practice and qualifying (out of your box whenever you like,
## as at a real circuit): no countdown, no start lights; cut up shows no clock either.
func _no_count() -> bool:
	if mode == "cutup":
		return true
	if mode == "track":
		return race_ctl == null or str(race_ctl.kind) in ["practice", "qualifying"]
	return false


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
					(Config.flag("autostart") and (not street_online or Net.racers().size() >= int(Config.arg("min_racers", 1)))) or
					(_no_count() and not Net.online())):         # (alone in cut up or a practice / qualifying: off you go)
				if Net.online():
					if net:
						_lock_grid()                     # (Track Mode: the grid set, everyone in race control)
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
	if net and net.host:
		net.stream_ai(dt)                            # (the AI cars to everyone, the grid included)
	if street_online or field != null:               # (CarLook lights the AI's lamps at dusk too)
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
	if weather and cockpit.wipe_strokes <= 1 and car.linear_velocity.length() > 2.0:
		cockpit.wipe(2)                              # (rain: the wipers keep going while it moves)
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
	if _pit_stop > 0.0:
		# (held in the box while the crew works: on the handbrake too, which never selects reverse, and out of
		# reverse if it was in it: the brake held at a standstill would otherwise pick reverse and drive it back)
		car.inp = {"steer": 0.0, "throttle": 0.0, "brake": 1.0, "handbrake": true}
		if car.drivetrain and int(car.drivetrain.gear) < 0:
			car.drivetrain.shift(1)
		return
	if use_autopilot and state != "grid" and race_ctl:
		if _my_driver == null:
			_my_driver = _make_my_driver()
		_my_driver.s = car_s
		_my_driver.d = car_d
		car.inp = _my_driver.drive(car, get_physics_process_delta_time())
		if car.race:
			car.race.limiter = st.in_pit_limit(car_s, car_d) or (_my_driver.task == "pit" and _my_driver.pit_phase == "in" and st.around_line(car_s) > float(st.pit.s_lim0) - 15.0)
		# beached, spun or lost in a gravel trap (not 20 m further round in 8 s): press R like a player would
		var racing: bool = state == "running" and _my_driver.task == "race" and race_ctl.phase in ["green", "chequered", "open"]
		_stuck = _stuck + get_physics_process_delta_time() if racing and car_s < _stuck_s + 20.0 else 0.0
		if not racing or car_s >= _stuck_s + 20.0:
			_stuck_s = car_s
		if _stuck > 8.0:
			_stuck = 0.0
			reset_car()
		return
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
	if not built or replay.active:
		return                                    # (a replay is on: its own keys, its own camera)
	if not _engine_started:
		_engine_wait += dt
		if (_engine_asked and not (ai and ai.busy())) or _engine_wait > ENGINE_START_LATEST:
			_start_engine_now()
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
	if Input.is_action_just_pressed("replay") and _settings == null and (_pause.visible or (state == "finished" and not paused())):
		replay.open("pause" if _pause.visible else "results")
	# the camera: circling the car before the countdown and after the finish; in the
	# seat for the stage (the driver can press C for the chase cam)
	if state == "running" and my_seat == "driver" and Input.is_action_just_pressed("camera"):
		if mode == "track":                       # (seat, chase, the broadcast's TV camera, seat ...)
			if _tv:
				_tv = false
			elif _chase:
				_chase = false
				_tv = true
			else:
				_chase = true
		else:
			_chase = not _chase
	var want := "seat"
	if state in ["grid", "finished"]:
		want = "orbit"
	elif state == "running" and (_chase or _tv) and my_seat == "driver":
		want = "chase"
	if Config.flag("screenshot"):
		want = Config.arg("shot_view", "seat")
		if want == "tv":                              # (the broadcast camera: the chase view's car under it)
			_tv = true
			want = "chase"
	if view_override != "" and state == "running":
		want = view_override
	if want != cam.view:
		cam.view = want
		car.set_outside(want != "seat")
		# a car's own interior has windows: the crew are seen from outside too (your own head with them)
		cockpit.visible = (want == "seat" and not cockpit.hood) or cockpit.own_interior()
		cockpit.set_my_seat(my_seat if want == "seat" else "")
	_tv_camera(dt, want == "chase" and _tv and state == "running" and view_override == "")
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
	_lights.since_go = stage_time if state == "running" and not _no_count() else 99.0   # (no start, no GO lights)
	_lights.time_text = clock if state in ["running", "finished"] and mode != "cutup" else ""   # (cut up: no clock)
	var pens: Array = []
	if jump_start:
		pens.append("JUMP START")
	if resets > 0:
		pens.append("%d RESET%s" % [resets, "" if resets == 1 else "S"])
	if mode == "cutup":                                # (scored on points, not the clock: no seconds to add)
		_lights.pen_text = " · ".join(pens)
	else:
		_lights.pen_text = "+%d s  %s" % [int(penalties), " · ".join(pens)] if penalties > 0.0 else ""
	if race_ctl and race_ctl.kind == "race" and state in ["running", "finished"]:
		# (a race: the five red lights, then the race's clock and your penalties)
		_lights.state = "race"
		_lights.race_lit = race_ctl.lights if race_ctl.phase == "lights" else 0
		_lights.since_go = race_ctl.race_t if race_ctl.phase in ["green", "chequered", "done"] else 99.0
		_lights.time_text = fmt_time(race_ctl.race_t) if race_ctl.race_t > 0.0 else ""
		var pt: float = race_ctl.penalty_time(Net.my_id())
		_lights.pen_text = "+%d s" % int(pt) if pt > 0.0 else ""
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
	_engine.engine_off()                             # (silent till the stage shows: start_engine)
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


## The stage is on screen (Main, when the loading screen's gone): the door shuts and the engine
## starts (EngineSound.start_up), once the co-driver's done saying he's ready.
func start_engine() -> void:
	_engine_asked = true


func _start_engine_now() -> void:
	_engine_started = true
	if _engine:
		_engine.start_up(true, cam != null and cam.view == "seat")


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
	if car.race and state == "running":
		car.race.hit(impact)                         # (Track Mode: damage, if the session has it on)
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
			var ses := str(o.get("session", "practice"))
			session.setup(st, ses)
			if ses == "practice" and not street_online:   # (online practice has race control: everyone's laps on one tower)
				var sd: Vector2 = st.box_sd(_track_box)
				session.add_car(Net.my_id(), str(car.setup.get("name", "YOU")), st.unwrap(sd.x, 0.0))
			else:
				_setup_race(o, ses)
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


## WET weather (Track Mode): the rain, the spray off every car, the rain's hiss (Weather), the
## wipers going; the roads were built wet (WorldMaterials.wet), the tyres know (RaceSim.wet).
func _weather(o: Dictionary) -> void:
	if float(o.get("wet", 0.0)) <= 0.0:
		return
	weather = Weather.new()
	weather.name = "Weather"
	weather.setup(float(o.wet), seed_value)
	weather.cars = replay_targets
	add_child(weather)


func _exit_tree() -> void:
	WorldMaterials.wet = 0.0                         # (the menu's garage and the next map: dry roads)


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
	if cockpit.hood:                                 # (no cabin: no dials to glow over the bonnet)
		return
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
	CarLamps.fit(c, c.body_model, true, c == car)      # (yours: a tail light, a shadow, your car's layer; a new body: fitted anew)


## In the dark the other drivers' and Track Mode's AI cars' headlight beams: only the two
## nearest you within 150 m have them (real lights, one on each headlamp; the rest just glow:
## the web build can only light so much at once).
func _others_beams() -> void:
	var near: Array = []
	var cars: Array = others.values()
	if field != null:
		cars.append_array(field.cars.values())
	for c in cars:
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
	if session and (state == "running" or (state == "finished" and race_ctl and race_ctl.phase != "done")):
		_track_tick(dt)
		if state == "finished" and race_ctl:
			_rows_t -= dt
			if _rows_t <= 0.0:
				_rows_t = 1.0
				race_rows = _track_rows()
				if race_ctl.kind == "qualifying" and bool(opts.get("weekend", false)):
					next_grid = race_rows.map(func(r): return r.id)   # (the others' laps after yours count for the race's grid too)
				_show_race()
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
		if race_ctl:
			race_rows = _track_rows()
			var me = Net.my_id()
			var pos := 0
			for r in race_rows:
				if r.id == me:
					pos = int(r.pos)
			var race: bool = race_ctl.kind == "race"
			var fl: Array = race_ctl.fastest_lap()
			lines.insert(0, "%s  P%d OF %d%s" % [str(race_ctl.kind).to_upper(), pos, race_rows.size(),
				("   +%d s penalties" % int(race_ctl.penalty_time(me))) if race_ctl.penalty_time(me) > 0.0 else ""])
			if fl[0] != null:
				lines.append("fastest lap  %s  %s" % [_car_name(fl[0]), fmt_lap(float(fl[1]))])
			var pk := key + ("/race" if race else "/qualifying")
			var best_pos: bool = pos > 0 and race_ctl.kind != "practice" and str(race_ctl.dnf.get(me, "")) == "" and Profile.record_mode(pk, float(pos), true)
			if best_pos:
				lines.append("YOUR BEST %s FINISH" % ("RACE" if race else "QUALIFYING"))
			if race_ctl.kind != "practice":
				Profile.record_track_result(pk, race_rows.map(func(r): return {"pos": r.pos, "name": "YOU" if r.id == me else _car_name(r.id),
					"total": r.total, "best": r.best, "status": r.status}))
			mode_result["pos"] = pos
			if race and opts.has("series") and not street_online:
				# a championship's round: its points onto the season, the standings under the result
				var season := TrackSeries.record(str(opts.get("class", "gt")), race_rows.map(func(r): return {"id": r.id,
					"name": _car_name(r.id), "pos": r.pos, "status": r.status}), me)
				var table: Array = TrackSeries.standings(season)
				lines.append("CHAMPIONSHIP after %s:" % TrackSeries.round_title(int(opts.series)))
				for k in mini(table.size(), 5):
					lines.append("%d. %s  %d pts" % [k + 1, str(table[k][1]), int(table[k][2])])
				var yours := TrackSeries.your_place(season)
				if yours > 5:
					lines.append("%d. YOU  %d pts" % [yours, int(table[yours - 1][2])])
				if TrackSeries.done(season) and not table.is_empty():
					lines.append("CHAMPION: %s" % str(table[0][1]))
				mode_result["series"] = season
			if not race and bool(opts.get("weekend", false)):
				next_grid = race_rows.map(func(r): return r.id)
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
	var rb := UI.button("REPLAY", func(): replay.open("results"), 24, 220, "night" if mode != "" else "rally")
	rb.name = "ReplayButton"
	rb.focus_mode = Control.FOCUS_NONE                 # (ENTER stays "next": V or this button for the replay)
	rb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rv.add_child(rb)
	_results.visible = false
	_pause = _panel()
	add_to_group(MusicPlayer.DIP_GROUP)                 # (music_dip: the music dips under the pause menu)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_pause.add_child(vb)
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var buttons := [["RESUME", _toggle_pause], ["REPLAY", func(): replay.open("pause")], ["SETTINGS", _open_settings],
		["MUSIC", _open_settings.bind(MusicPanel)]]
	if looped:
		buttons.append(["END RUN", _end_run])          # (a loop has no finish: the run ends when you say)
	if mode == "track":
		# your pit strategy: each press cycles its choice (PitPlan)
		buttons.append([pit_plan.tyres_text(), func(): pit_plan.cycle_tyres(); _pit_rows()])
		buttons.append([pit_plan.fuel_text(), func(): pit_plan.cycle_fuel(); _pit_rows()])
		buttons.append([pit_plan.repair_text(), func(): pit_plan.toggle_repair(); _pit_rows()])
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
		elif b[0] == "MUSIC":
			_pause_music = btn
		elif b[0] == "REPLAY":
			_pause_replay = btn
		elif str(b[0]).begins_with("PIT "):
			btn.add_theme_font_size_override("font_size", 20)
			btn.custom_minimum_size = Vector2(320, 40)
			_pit_btns.append(btn)
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


## (Track Mode) The broadcast's trackside TV camera on your car: the replay's own (ReplayCam "tv": a
## tower past the run-off up the road, on the outside of the next bend, panning and zooming after
## you, the next one set up once you've gone by), filming live. The chase view's car underneath it.
func _tv_camera(dt: float, on: bool) -> void:
	var rc = replay.cam if replay else null
	if rc == null or replay.active:
		return
	if on != _tv_on:
		_tv_on = on
		for c in replay_targets():                    # (no names floating over the cars: through its long lens they'd fill the shot)
			var tag = c.get_node_or_null("NameTag")
			if tag:
				tag.visible = not on
	if not on:
		if rc.current:
			cam.make_current()
		return
	rc.set_target(car)
	if rc.mode != "tv":
		rc.set_mode("tv")
	rc.target_vel = car.linear_velocity
	rc.update(dt, dt)
	if not rc.current:
		rc.make_current()


## The pause menu's PIT rows say what's set.
func _pit_rows() -> void:
	var texts := [pit_plan.tyres_text(), pit_plan.fuel_text(), pit_plan.repair_text()]
	for k in mini(_pit_btns.size(), texts.size()):
		_pit_btns[k].text = texts[k]


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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _pause.visible or state == "finished" else Input.MOUSE_MODE_CAPTURED
	if _pause_replay:
		_pause_replay.disabled = replay == null or not replay.can_open()     # (nothing recorded yet: the grid)


## Paused: the pause menu is up, or the settings opened from it, or a replay's playing (the
## car held on the brake, the mouse free). (The stage itself goes on: online, the others still drive.)
func paused() -> bool:
	return _pause.visible or _settings != null or (replay != null and replay.active)


## The music dips under the pause menu and the settings over it (MusicPlayer.DIP_GROUP), not
## under MUSIC (you're listening to it there).
func music_dip() -> bool:
	return _pause.visible or (_settings != null and _settings_from != _pause_music)


## SETTINGS from the pause menu: the main menu's own panel (graphics, sound, the aids ...)
## over the stage, still paused. What changes at once from the main menu (the graphics,
## the sound, the mouse) changes here at once too. BACK or ESC: back to the pause menu.
## MUSIC opens the same way (MusicPanel: your playlists, what's playing).
func _open_settings(panel = SettingsPanel) -> void:
	if _settings != null:
		return
	_settings_from = _pause_music if panel == MusicPanel else _pause_settings
	_pause.visible = false
	_settings = ColorRect.new()                      # a shade over the stage, the panel in the middle
	_settings.name = "PauseSettings"
	_settings.color = Color(0, 0, 0, 0.35)
	_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.add_child(_settings)
	var p = panel.new()
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
	(_settings_from if _settings_from else _pause_settings).grab_focus()


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
		if Config.music.song_count() > 0:              # (your own songs in the music folder: their keys)
			alone += " · N next song · B music"
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
	if race_ctl and not race_rows.is_empty():
		_race_box.visible = true
		_track_table()
		return
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


## A Track Mode session's classification under the results: place, number, name, laps, time (a
## race: the winner's and the gaps, penalties added; qualifying: best laps), its status.
func _track_table() -> void:
	var race: bool = race_ctl.kind == "race"
	var win := float(race_rows[0].total) if not race_rows.is_empty() else INF
	for r in race_rows.slice(0, 16):
		var t := ""
		if str(r.status) in ["DNF", "DSQ"]:
			t = str(r.status)
		elif race:
			if float(r.total) == INF:
				t = "RUNNING"
			elif int(r.pos) == 1:
				t = fmt_lap(float(r.total))
			else:
				var lapped := int(race_rows[0].laps) - int(r.laps)
				t = ("+%d LAP%s" % [lapped, "" if lapped == 1 else "S"]) if lapped > 0 else "+%.3f" % (float(r.total) - win)
		else:
			t = fmt_lap(float(r.best)) if float(r.best) != INF else "NO TIME"
		var me: bool = r.id == Net.my_id()
		var txt := "%2d.  #%-2d  %-12s  %s%s" % [int(r.pos), _car_number(r.id), "YOU" if me else _car_name(r.id), t,
			("   +%d s" % int(r.pens)) if float(r.pens) > 0.0 else ""]
		var l := UI.label(txt, 19, UI.YELLOW if me else UI.CREAM, me)
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
	if not Config.flag("headless_ui") and not paused():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE    # (its REPLAY button)
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
		foot.append("ENTER  %s     R  retry this one" % _next_text + ("     TAB  swap seats" if Net.online() and Net.crew_full() else "") + "     V  replay")
	else:
		foot.append("Waiting for the host...     V  replay")
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
	if car.race:
		if Input.is_action_just_pressed("pit_limiter") and my_seat == "driver":
			car.race.limiter = not car.race.limiter
			_flash("PIT LIMITER %s" % ("ON" if car.race.limiter else "OFF"), Color(1.0, 0.85, 0.2))
		if use_autopilot and race_ctl == null:         # (the autopilot drives the lane on the limiter, as a driver would)
			car.race.limiter = st.in_pit_limit(car_s, car_d) or (pit and st.around_line(car_s) < float(st.pit.s_lim0) + 20.0 and st.around_line(car_s) > float(st.pit.s_in1))
		car.race.limiter_kmh = float(st.pit.limit_kmh)
		# DRS: race control says when it may open (practice: anywhere in a zone); the driver opens it
		car.race.drs_avail = race_ctl.drs_state(Net.my_id(), car_s) if race_ctl else st.drs_zone(fposmod(car_s, st.length)) >= 0
		car.race.drs_auto = use_autopilot
		if use_autopilot and (car.race.abs_level == 0 or car.race.tc_level == 0):
			car.race.abs_level = 6                       # (the autopilot's feet: the aids stand in for them, as the AI's: RaceField)
			car.race.tc_level = 6
			car._set_aids()
		if my_seat == "driver" and Input.is_action_just_pressed("drs"):
			car.race.drs_press()
		if my_seat == "driver" and car.race.ers_kw > 0.0 and Input.is_action_just_pressed("ers_mode"):
			car.race.ers_cycle()
			_flash("ERS  %s" % car.race.ERS_MODES[car.race.ers_mode], Color(0.4, 0.85, 1.0))
		if _race_hud == null and _hud:                  # (the car's panel: once the HUD is up)
			_race_hud = RaceHud.new()
			_hud.add_child(_race_hud)
		if _race_hud:
			_race_hud.show_state(car.race.readout(), car.race, fuel_per_lap)
	var me = Net.my_id()
	var pos := {me: {"s": car_s, "d": car_d, "v": car.linear_velocity.length(), "pit": pit}}
	if net and not net.host:
		# (online, a guest: the host's race control judges everyone; its copy here for the HUD, and
		# its news as if it were our own)
		net.guest_tick(dt, pos[me])
		if Config.flag("smoke"):
			# (the tests: our own laps timed here too, on this machine's clock, against the host's timing)
			if own_timing == null:
				own_timing = TrackSession.new()
				own_timing.setup(st, race_ctl.kind)
				own_timing.add_car(me, "", car_s)
			own_timing.tick(dt, pos)
		_last_pos = _guest_positions(pos)
		_drivers_rules()
		_race_events()
		_board_rows = net.board
		_update_tower()
		_my_pit(dt, pit)
		_end_tick(dt)
	else:
		if field:
			field.me = {"id": me, "s": car_s, "d": car_d, "v": car.linear_velocity.length(), "pos": car.global_position}
			if net:
				field.others_extra = _net_others(_last_pos)   # (the other players, as race control has them)
			_drivers_rules()
			field.tick(dt)
			pos.merge(field.positions())
			_field_events()
		var live := pos
		if net:
			# (online: every car judged at the same moment, a little back: the other players' from what
			# their machines send, ours and the AI's from a moment ago, TrackNet.judged)
			pos = net.judged(_t_alive, live)
		session.tick(dt, pos)
		if race_ctl:
			race_ctl.tick(dt, pos)
			_last_pos = pos
			if net:
				_near_pos = pos.merged(live, true)       # (racecraft: the cars here as they are now)
			if field:
				for id in field.cars:                    # (the AI's DRS: each opens it when it may, flat out)
					var fc = field.cars[id]
					if fc.race and live.has(id):
						fc.race.drs_avail = race_ctl.drs_state(id, float(live[id].s))
			_board_rows = _board(pos)
			if net:
				net.host_tick(dt, _board_rows)           # (its news out to everyone before it's read here)
			_race_events()
			_update_tower()
			_my_pit(dt, pit)
			_end_tick(dt)
	for ev in session.events:
		if ev.id != Net.my_id():
			continue
		match str(ev.kind):
			"sector":
				var dl := float(ev.delta)
				_flash("S%d   %s%s" % [int(ev.sector) + 1, fmt_lap(float(ev.time)), "" if dl == INF else "   %+.3f" % dl],
					Color(0.75, 0.4, 1.0) if ev.purple else (Color(0.4, 1.0, 0.45) if dl < 0.0 else (Color(1.0, 0.85, 0.3) if dl != INF else Color.WHITE)))
			"lap":
				if car.race:
					if _fuel_at_line >= 0.0 and not ev.get("in_lap", false):
						fuel_per_lap = _fuel_at_line - float(car.race.fuel_l)
					_fuel_at_line = float(car.race.fuel_l)
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
var _last_pos := {}                  # every car's position as race control last judged it
var _near_pos := {}                  # (online, the host) the same with ours and the AI's as they are now (racecraft)
var _rows_t := 0.0
var _bw_t := 0.0
var _pit_done := true                # (the car starts in its box or on the grid: a stop only counts once it's left the pit lane)
var _my_service := {}
var pit_plan = PitPlan.new()         # your pit strategy (the pause menu's PIT rows)
var _pit_btns: Array = []


# ── Track Mode's qualifying and races ──────────────────────────────────────

const ROLL_BACK := 350.0             # m behind the grid the rolling start's double file sets off from

## The race's field and grid, worked out once (before your car's put on its grid box). Online: the
## host's AI (opts.field), and the grid from the roster as it stands until the session starts.
func _plan_field() -> void:
	if not _planned:
		_planned = true
		var num := int(car.setup.get("number", 0)) if car and car.setup else 0
		field_entries = opts.field if opts.has("field") else Modes.track_field(opts, seed_value, num)
		if not street_online:
			grid_ids = Modes.track_grid(opts, field_entries, Net.my_id(), seed_value)
	if street_online and not _locked:
		grid_ids = Modes.online_grid(opts, field_entries, Net.racers())


var _planned := false


## Where a car starts a race (s unwrapped, d): its grid box, or (a rolling start) the double file
## ROLL_BACK m further back.
func _start_sd(id) -> Vector2:
	var k := maxi(grid_ids.find(id), 0)
	var g: Dictionary = st.grid[mini(k, st.grid.size() - 1)]
	var s := float(g.s)
	if s > st.length * 0.5:
		s -= st.length
	if str(opts.get("start", "rolling")) == "rolling":
		s -= ROLL_BACK
	return Vector2(s, float(g.d))


## A qualifying session or a race: the AI field (RaceField) and race control (RaceControl); everyone
## timed from where they start (a race: the grid; qualifying: the pit boxes).
func _setup_race(o: Dictionary, ses: String) -> void:
	_plan_field()
	race_ctl = RaceControl.new()
	race_ctl.setup(st, session, o, seed_value)
	if ses == "practice":
		race_ctl.time_limit = INF                     # (online practice: no clock; END RUN ends your own run)
	if street_online:
		net = TrackNet.new()
		net.name = "TrackNet"
		add_child(net)
		net.setup(self, multiplayer.is_server())
		if not net.host:
			# (a guest: race control's a copy the host keeps up to date, the AI cars are the host's,
			# drawn from its stream; nothing's judged or driven here)
			if not field_entries.is_empty():
				_ai_view = RaceField.new()
				_ai_view.name = "RaceField"
				add_child(_ai_view)
				var view: Array = []
				for e in field_entries:
					var sd := _start_sd(e.id) if ses == "race" else _box_sd(int(e.box))
					view.append(e.merged({"s": sd.x, "d": sd.y}))
				_ai_view.setup_view(st, view)
			return
	var me = Net.my_id()
	var entries: Array = []
	for e in field_entries:
		var en: Dictionary = e.duplicate()
		var sd := _start_sd(e.id) if ses == "race" else _box_sd(int(e.box))
		en["s"] = sd.x
		en["d"] = sd.y
		en["task"] = "hold"
		entries.append(en)
	field = RaceField.new()
	field.name = "RaceField"
	add_child(field)
	field.player_car = car
	field.setup(st, entries, {"collide": bool(o.get("collide", true)), "near_max": _near_max()}, Modes.race_opts(o), seed_value)
	if street_online:
		# (the host: every car goes into race control and the timing as the session starts, _lock_grid;
		# online every car's a ghost to the others, the AI's too: the other players' are only drawn here)
		field.ghost(car)
		return
	var order: Array = grid_ids if ses == "race" else [me] + field_entries.map(func(e): return e.id)
	for id in order:
		var sd: Vector2 = _start_sd(id) if ses == "race" else (_box_sd(_track_box) if id == me else _box_sd(int(field.driver(id).pit_box)))
		session.add_car(id, "YOU" if id == me else str(field.driver(id).driver_name), sd.x, ses != "race")
		race_ctl.add_car(id, sd.x, sd.y)
	if ses != "race":
		race_ctl.begin()                              # (qualifying's clock runs from the start)


## How many AI cars near you run the full physics (RaceField.near_max): by the graphics level, as
## the frame has room (LOW 2, MEDIUM 3, HIGH 4, ULTRA 6); --near_max=N says outright.
func _near_max() -> int:
	if Config.flag("near_max"):
		return int(Config.arg("near_max"))
	return {"low": 2, "medium": 3, "high": 4, "ultra": 6}.get(Graphics.level(), 3)


func _box_sd(k: int) -> Vector2:
	var b: Vector2 = st.box_sd(k)
	return Vector2(st.unwrap(b.x, 0.0), b.y)


## A player's pit box: from 8 on, in the roster's order (online: set as the session starts, then kept).
func _box_of(id) -> int:
	if _boxes.has(id):
		return int(_boxes[id])
	var k := maxi(Net.racers().find(id), 0) if street_online else 0
	return (Modes.PLAYER_BOX + k) % int(st.pit.boxes)


# ── Track Mode online (TrackNet) ─────────────────────────────────────────────

## (the host) The session starts: who's in it is set (the players here, their stages loaded), their
## pit boxes and the grid (a race: the roster's order or qualifying's, the AI behind); every car into
## race control and the timing from its grid box or pit box, the AI put there, every guest told.
func _lock_grid() -> void:
	var ses := str(opts.get("session", "practice"))
	var racers: Array = Net.racers().filter(func(id): return id == Net.my_id() or _loaded_peers.has(id))
	_boxes = {}
	for k in racers.size():
		_boxes[racers[k]] = (Modes.PLAYER_BOX + k) % int(st.pit.boxes)
	var ids: Array = Modes.online_grid(opts, field_entries, racers) if ses == "race" else racers + field_entries.map(func(e): return e.id)
	grid_ids = ids
	_locked = true
	var starts := {}
	for id in ids:
		var sd := _start_of(id)
		starts[id] = sd
		if field.driver(id):
			field.place(id, sd.x, sd.y, "hold")
		session.add_car(id, _car_name(id, false), sd.x, ses != "race")
		race_ctl.add_car(id, sd.x, sd.y)
	if ses != "race":
		race_ctl.begin()
	var spot := _grid_spot(Net.my_id())
	_start_pos = spot[0]
	_start_yaw = spot[1]
	car.place(_start_pos, _start_yaw)
	net.locked(ids, starts, _boxes)


## (the host, before the start) The AI to their places on the grid as it stands (a racer joining or
## leaving moves them back or up).
func _field_to_grid() -> void:
	if not street_online or str(opts.get("session", "practice")) != "race":
		return
	_plan_field()
	for e in field_entries:
		var sd := _start_sd(e.id)
		field.place(e.id, sd.x, sd.y, "hold")


## (the host) A player who's left is out (DNF), so nothing waits on them.
func _net_left() -> void:
	if session == null:
		return
	for id in session.cars.keys():
		if not Net.players.has(id) and not _is_ai(id):
			if _locked:
				race_ctl.retire(id, "DNF")
			net.drop(id)


## (the host) A player whose stage loaded once the session was on: into it out of a free pit box (not
## once the chequered flag's out: they're in the next one). True if they're in.
func _net_joined(who: int) -> bool:
	if race_ctl == null or race_ctl.phase in ["chequered", "done"]:
		return false
	var box := Modes.PLAYER_BOX
	while box in _boxes.values():
		box += 1
	box = box % int(st.pit.boxes)
	_boxes[who] = box
	var sd := _box_sd(box)
	if not session.cars.has(who):
		session.add_car(who, _car_name(who, false), sd.x, true)
	race_ctl.add_late(who)
	net.joined(who, sd, box, grid_ids, _boxes)
	return true


func _is_ai(id) -> bool:
	return field_entries.any(func(e): return e.id == id)


## Where a car starts the session (s unwrapped, d): a race, its grid box; else (or joined late), its pit box.
func _start_of(id) -> Vector2:
	if str(opts.get("session", "practice")) == "race" and id in grid_ids:
		return _start_sd(id)
	for e in field_entries:
		if e.id == id:
			return _box_sd(int(e.box))
	return _box_sd(_box_of(id))


## (a guest) The host's grid: who's in the session, in what order, from which pit boxes; our car to
## its place, every car into the copy of race control and the timing.
func net_grid(ids: Array, boxes: Dictionary) -> void:
	grid_ids = ids
	_boxes = boxes
	_locked = true
	var race := str(opts.get("session", "practice")) == "race"
	race_ctl.grid_order = ids.duplicate()
	var me = Net.my_id()
	for id in ids + ([me] if not me in ids else []):
		var sd := _start_of(id)
		if race and id in ids:
			race_ctl.spots[id] = sd
		if not session.cars.has(id):
			session.add_car(id, _car_name(id, false), sd.x, not race or not id in ids)
		if not race_ctl.pens.has(id):
			race_ctl.pens[id] = {"time": 0.0, "list": [], "warn": {}, "dsq": false}
	if state == "grid":
		var spot := _grid_spot(me)
		_start_pos = spot[0]
		_start_yaw = spot[1]
		car.place(_start_pos, _start_yaw)
		autopilot.route = _pit_out_route(_track_box)


## (a guest) The host's classification came in.
func net_results() -> void:
	if state == "finished" and race_ctl:
		race_rows = _track_rows()
		_show_race()


## The classification: race control's (online, on a guest's machine: the host's).
func _track_rows() -> Array:
	if net and not net.host:
		return net.rows
	return race_ctl.results(_last_pos)


## (the host) The other players' cars for the AI to mind, and to run on the physics near.
func _net_others(pos: Dictionary) -> Array:
	var out: Array = []
	for id in others:
		if pos.has(id) and is_instance_valid(others[id]):
			var p: Dictionary = pos[id]
			out.append({"id": id, "s": float(p.s), "d": float(p.d), "v": float(p.v), "stricken": race_ctl.dnf.has(id),
				"pos": others[id].global_position})
	return out


## (a guest) Where every car is, from the cars on this machine (the others' streams, the host's AI),
## for your autopilot's racecraft: {id: {s (round the lap), d, v, pit}}, yours as it is.
func _guest_positions(pos: Dictionary) -> Dictionary:
	var out := pos.duplicate()
	var cs := others.duplicate()
	if _ai_view:
		cs.merge(_ai_view.cars)
	for id in cs:
		var c = cs[id]
		if not is_instance_valid(c):
			continue
		var at: Dictionary = st.locate(c.global_position, int(_hints.get(id, -1)))
		_hints[id] = at.i
		out[id] = {"s": float(at.s), "d": float(at.d), "v": c.linear_velocity.length(), "pit": st.in_pit_lane(float(at.s), float(at.d))}
	return out


## The timing board, in race control's running order (practice and qualifying: by best lap): each
## car's laps, its lap's start, its best and last laps, in the pits, penalties, status (DNF, DSQ),
## its gap to the leader (or laps down) and to the car ahead, its finish. The tower's drawn from it,
## online on every machine (the host sends it: TrackNet).
func _board(pos: Dictionary) -> Array:
	var race: bool = race_ctl.kind == "race"
	var ord: Array = race_ctl.order(pos) if race else session.classification().map(func(r): return r[0])
	var lead = ord[0] if not ord.is_empty() else null
	var out: Array = []
	for i in ord.size():
		var id = ord[i]
		var c: Dictionary = session.cars.get(id, {})
		var down := 0
		var gap := INF
		var intv := INF
		if race and i > 0 and pos.has(id) and pos.has(lead):
			down = floori((float(pos[lead].s) - float(pos[id].s)) / st.length)
			gap = race_ctl.gap(lead, id, pos)
			intv = race_ctl.gap(ord[i - 1], id, pos)
		out.append({"id": id, "laps": int(c.get("laps", 0)), "out": bool(c.get("out_lap", true)), "t0": float(c.get("lap_t0", -1.0)),
			"ok": bool(c.get("valid", true)), "best": float(c.get("best", INF)), "last": float(c.get("last", INF)),
			"pit": pos.has(id) and bool(pos[id].get("pit", false)), "pens": race_ctl.penalty_time(id), "st": str(race_ctl.dnf.get(id, "")),
			"gap": gap, "down": down, "intv": intv, "fin": float(race_ctl.finished.get(id, -1.0)), "jump": race_ctl._has_pen(id, "jump")})
	return out


## Your place on the board (0: not on it yet).
func _my_place() -> int:
	for i in _board_rows.size():
		if _board_rows[i].id == Net.my_id():
			return i + 1
	return 0


## The results once you've taken the flag (or retired): a few seconds on.
func _end_tick(dt: float) -> void:
	if _end_t > 0.0:
		_end_t -= dt
		if _end_t <= 0.0:
			_end_race()


## The rules onto the AI drivers (and yours, driven by the tests' autopilot): their laps, the flags
## where they are, the formation, qualifying's runs (out of the box one by one, three flying laps,
## back to the box).
func _drivers_rules() -> void:
	var red: bool = race_ctl.phase == "red"
	var form: bool = race_ctl.phase == "formation"
	var quali: bool = race_ctl.kind != "race"
	var all: Array = field.drivers.duplicate() if field else []
	if _my_driver:
		all.append(_my_driver)
	var k := 0
	for drv in all:
		var c: Dictionary = session.cars.get(drv.id, {})
		drv.laps = int(c.get("laps", 0))
		drv.yellow = race_ctl.in_yellow(drv.s)
		drv.blue = race_ctl.blue.has(drv.id)
		drv.blue_d = float(race_ctl.blue.get(drv.id, 0.0))
		drv.no_passing = form or red
		drv.limit_v = RaceControl.PACE_V if (form or red) else INF
		if race_ctl.spots.has(drv.id):
			var gi: int = race_ctl.grid_order.find(drv.id)
			drv.follow_id = race_ctl.grid_order[gi - 1] if gi > 0 else null
			drv.slot = Vector2(8.0, float(race_ctl.spots[drv.id].y))
		if quali:
			drv.pace_mul = 0.86 if bool(c.get("out_lap", true)) else 1.0
			if drv.task == "hold" and session.time >= 3.0 + k * 7.0 and race_ctl.phase == "open":
				drv.task = "pit"
				drv.pit_phase = "out"
			var done: bool = race_ctl.finished.has(drv.id) or drv.laps >= 3
			if drv.task == "race" and done and drv.pit_lap < 0:
				drv.pit_lap = drv.laps
				drv.pit_service = {"park": true}
		elif race_ctl.finished.has(drv.id) and drv.task == "race":
			drv.task = "cool"
		k += 1
	if _my_driver:
		var others: Array = []
		var near: Dictionary = _near_pos if not _near_pos.is_empty() else _last_pos
		for id in near:
			if id != _my_driver.id:
				var p: Dictionary = near[id]
				others.append({"id": id, "s": p.s, "d": p.d, "v": p.v, "stricken": race_ctl.dnf.has(id)})
		_my_driver.plan(others, get_physics_process_delta_time())
		_my_driver.pit_tick(get_physics_process_delta_time())


## The field's news: retirements, pit stops.
func _field_events() -> void:
	for ev in field.events:
		match str(ev[1]):
			"retired":
				race_ctl.retire(ev[0], "DNF")
	field.events.clear()


## Race control's news: the lights, the flags, penalties, the finish.
func _race_events() -> void:
	var me = Net.my_id()
	for ev in race_ctl.events:
		match str(ev.kind):
			"light":
				if builder.has_method("set_lights"):
					builder.set_lights(int(ev.n))
				_play("tick", -2.0)
				lights_seen.append(int(ev.n))
			"green":
				if builder.has_method("set_lights"):
					builder.set_lights(0)
				_play("bell", -6.0)                    # (the gantry says GO, the tower's banner GREEN FLAG)
				lights_seen.append("go")
				var drivers: Array = field.drivers.duplicate() if field else []
				if _my_driver:
					drivers.append(_my_driver)
				for drv in drivers:
					drv.lights_out = true
					if drv.task == "formation":
						drv.task = "race"
			"chequered":
				_flash("CHEQUERED FLAG", Color.WHITE)
			"red":
				_flash("RED FLAG", Color(1.0, 0.25, 0.2))
			"regrid":
				_regrid(ev)
			"finish":
				if ev.id == me:
					var place: int = int(ev.get("pos", 0)) if net and not net.host else race_ctl.position(me, _last_pos)   # (a guest's positions are only its own view)
					_flash("FINISHED  P%d" % place if race_ctl.kind == "race" else "SESSION OVER", Color(1.0, 0.85, 0.3))
					_end_t = 4.0
			"penalty", "warning":
				if ev.id == me:
					_flash(str(ev.text), Color(1.0, 0.65, 0.2))
			"flag":
				if ev.id == me and str(ev.flag) == "bw":
					_bw_t = 6.0
			"dnf":
				if ev.id == me:
					_flash("DISQUALIFIED" if str(ev.text) == "DSQ" else "RETIRED", Color(1.0, 0.3, 0.25))
					_end_t = 3.0
				elif field and field.driver(ev.id):
					field.driver(ev.id).task = "out"
	race_ctl.events.clear()
	if race_ctl.phase == "done" and _end_t < 0.0 and state == "running":
		_end_t = 2.0


## A red flag's restart: everyone into their grid box in the order the race was in.
func _regrid(ev: Dictionary) -> void:
	var spots: Dictionary = ev.spots
	if net and ev.has("epoch"):
		net.epoch = int(ev.epoch)                    # (online: our positions count again from these boxes)
	for id in spots:
		var sp: Vector2 = spots[id]
		if id == Net.my_id():
			car.place(st.world_at(sp.x, sp.y) + Vector3.UP * 0.6, st.heading_at(sp.x))
			car_s = sp.x
			car_d = sp.y
			_hint = -1
			if _my_driver:
				_my_driver.s = sp.x
				_my_driver.task = "hold"
				_my_driver.lights_out = false
				_my_driver.hold_t = 0.0
		elif field:
			field.place(id, sp.x, sp.y, "hold")


## The end of your session: the results (a race: once you've taken the flag; the others race on).
func _end_race() -> void:
	_end_t = -1.0
	if state != "running":
		return
	var me = Net.my_id()
	var t: float = float(race_ctl.finished.get(me, race_ctl.race_t if race_ctl.kind == "race" else session.time))
	stage_finished(t, race_ctl.penalty_time(me), 0, race_ctl._has_pen(me, "jump"))


## Your pit stop: stopped in your box in the pit lane, the crew's work as your pit strategy says
## (PitPlan: by default new tyres if they're worn, wets on a wet track, repairs, the fuel to
## finish), held there till it's done.
func _my_pit(dt: float, pit: bool) -> void:
	if not pit:
		_pit_done = false
	if _pit_stop > 0.0:
		_pit_stop -= dt
		if _pit_stop <= 0.0:
			var sv := _my_service
			car.race.service(car, str(sv.get("compound", "")) if bool(sv.get("tyres", false)) else "", float(sv.get("fuel", 0.0)))
			if float(sv.get("repair", 0.0)) > 0.0:
				car.race.repair()
			_flash("GO GO GO", Color(0.3, 1.0, 0.4))
		return
	if use_autopilot or _pit_done or not pit or car.race == null or car.linear_velocity.length() > 0.6:
		return
	var b: Vector2 = st.box_sd(_track_box)
	if absf(st.around_line(car_s) - st.around_line(b.x)) > 3.5 or absf(car_d - b.y) > 2.5:
		return
	var worn := 0.0
	for t in car.race.tyres:
		worn = maxf(worn, float(t.wear))
	var laps_left: int = race_ctl.laps_total - int(session.cars.get(Net.my_id(), {}).get("laps", 0)) if race_ctl.kind == "race" else 0
	_my_service = pit_plan.service({"worn": worn, "race": race_ctl.kind == "race", "compound": str(car.race.compound),
		"wet": float(car.race.wet), "laps_left": laps_left, "per_lap": maxf(fuel_per_lap, 3.4), "fuel": float(car.race.fuel_l),
		"tank": float(car.race.tank_l), "damage": car.race.damage_level()})
	_pit_stop = RaceDriver.service_time(_my_service)
	_pit_done = true
	_flash("PIT STOP  %.1f s\n%s" % [_pit_stop, PitPlan.describe(_my_service)], Color(1.0, 0.85, 0.3))


## The timing tower (drawn from the board: race control's order and gaps, the same on every machine
## online) and the flag shown to you.
func _update_tower() -> void:
	if _tower == null and _hud:
		_tower = RaceTower.new()
		_hud.add_child(_tower)
	if _tower == null:
		return
	var me = Net.my_id()
	var race: bool = race_ctl.kind == "race"
	var bd: Array = _board_rows
	var n := bd.size()
	var mine := _my_place()
	var c: Dictionary = bd[mine - 1] if mine > 0 else {"laps": 0, "out": true}
	if race:
		_tower.head = "P%d / %d   LAP %d / %d" % [mine, n, clampi(int(c.laps) + (0 if bool(c.out) else 1), 1, race_ctl.laps_total), race_ctl.laps_total]
	elif race_ctl.time_limit == INF:
		_tower.head = "P%d / %d" % [mine, n]
	else:
		var left := maxf(race_ctl.time_limit - session.time, 0.0)
		_tower.head = "P%d / %d   %d:%02d" % [mine, n, int(left) / 60, int(left) % 60]
	_tower.sub = "%s  ·  %s" % [str(Modes.track_classes().get(str(opts.get("class", "gt")), {}).get("series", "GT")),
		str(race_ctl.kind).to_upper()]
	var show: Array = []
	if n <= RaceTower.ROWS:
		show = range(n)
	else:
		show = [0, 1, 2]
		var a := clampi(mine - 1 - 4, 3, n - (RaceTower.ROWS - 3))
		for i in range(a, a + RaceTower.ROWS - 3):
			show.append(i)
	var rows: Array = []
	for i in show:
		var r: Dictionary = bd[i]
		var id = r.id
		var txt := ""
		if race:
			if str(r.st) != "":
				txt = str(r.st)
			elif i == 0:
				txt = "LEADER"
			elif int(r.down) >= 1:
				txt = "+%d LAP%s" % [int(r.down), "" if int(r.down) == 1 else "S"]
			else:
				txt = "+%.3f" % float(r.gap) if float(r.gap) != INF else ""
		else:
			txt = fmt_lap(float(r.best)) if float(r.best) != INF else "NO TIME"
		rows.append({"pos": i + 1, "number": _car_number(id), "name": "YOU" if id == me else _car_name(id), "text": txt, "you": id == me,
			"pit": bool(r.pit), "pens": float(r.pens), "out": str(r.st) != ""})
	_tower.rows = rows
	_tower.ahead = ""
	_tower.behind = ""
	if race and mine > 1:
		var g := float(c.intv)
		_tower.ahead = "AHEAD  %s  %s" % [("+%.1f" % g) if g != INF else "", _car_name(bd[mine - 2].id)]
	if race and mine > 0 and mine < n:
		var g2 := float(bd[mine].intv)
		_tower.behind = "BEHIND  %s  %s" % [("-%.1f" % g2) if g2 != INF else "", _car_name(bd[mine].id)]
	_bw_t -= get_physics_process_delta_time()
	_tower.set_flag(_player_flag())


func _player_flag() -> String:
	var me = Net.my_id()
	if str(race_ctl.dnf.get(me, "")) == "DSQ":
		return "black"
	if race_ctl.phase == "red":
		return "red"
	if race_ctl.phase in ["chequered", "done"]:
		return "chequered"
	if race_ctl.in_yellow(car_s) or race_ctl.in_yellow(car_s + 200.0):
		return "yellow"
	if race_ctl.blue.has(me):
		return "blue"
	if _bw_t > 0.0:
		return "bw"
	if race_ctl.phase == "green" and race_ctl.race_t > 1.7 and race_ctl.race_t < 5.5:
		return "green"                                   # (once the gantry's GO has gone: not over it)
	return ""


## A car's name: YOU (you: false, your own name), an AI driver's, a player's (online, those who've left too).
func _car_name(id, you := true) -> String:
	if id == Net.my_id():
		return "YOU" if you else Net.player_name(id)
	var drv = field.driver(id) if field else null
	if drv:
		return str(drv.driver_name)
	for e in field_entries:
		if e.id == id:
			return str(e.name)
	if street_online and Net.players.has(id):
		return Net.player_name(id)
	if net and net.names.has(id):
		return str(net.names[id])
	return str(id)


func _car_number(id) -> int:
	if id == Net.my_id():
		return int(car.setup.get("number", 0))
	for e in field_entries:
		if e.id == id:
			return int(e.number)
	if others.has(id) and is_instance_valid(others[id]):
		return int(others[id].setup.get("number", 0))
	return 0


## (the tests, --autopilot) A RaceDriver at your wheel in a race or qualifying.
func _make_my_driver():
	var drv = RaceDriver.new()
	drv.id = Net.my_id()
	drv.driver_name = "YOU"
	drv.pit_box = _track_box
	drv.setup(st, RaceLine.params(car), {"pace": float(Config.arg("my_pace", 0.95)), "consistency": 0.95, "aggression": 0.5, "reaction": 0.2},
		seed_value * 977 + 1)
	drv.s = car_s
	drv.d = car_d
	if _from_pits:
		drv.task = "pit"                             # (online, joined once it was on: out of the pit box)
		drv.pit_phase = "out"
		drv.lights_out = true
	elif race_ctl.kind == "race":
		drv.task = "formation" if race_ctl.start_type == "rolling" and race_ctl.phase == "formation" else ("race" if race_ctl.phase in ["green", "chequered"] else "hold")
		drv.lights_out = race_ctl.phase in ["green", "chequered"]
	else:
		drv.task = "pit"
		drv.pit_phase = "out"
	return drv


func _track_text() -> String:
	var c: Dictionary = session.cars.get(Net.my_id(), {})
	if c.is_empty():
		return ""
	if race_ctl and race_ctl.kind == "race":
		# (a race: the tower has the place and the lap; here the lap times and the speed)
		var rl := ["LAST  %s" % (fmt_lap(float(c.last)) if float(c.last) != INF else "--"),
			"BEST  %s" % (fmt_lap(float(c.best)) if float(c.best) != INF else "--")]
		if st.in_pit_lane(car_s, car_d):
			rl.append("PIT LANE  %d KM/H" % int(st.pit.limit_kmh))
		return "\n".join(rl) + "\n%.0f km/h" % car.kmh()
	var t: float = running_lap()
	var lines := []
	lines.append("%s   %s" % ["OUT LAP" if t == INF else "LAP %d" % (int(c.laps) + 1), "" if t == INF else fmt_lap(t)])
	if not c.valid and t != INF:
		lines[0] += "   INVALID"
	lines.append("LAST  %s" % (fmt_lap(float(c.last)) if float(c.last) != INF else "--"))
	lines.append("BEST  %s" % (fmt_lap(float(c.best)) if float(c.best) != INF else "--"))
	if st.in_pit_lane(car_s, car_d):
		lines.append("PIT LANE  %d KM/H" % int(st.pit.limit_kmh))
	return "\n".join(lines) + "\n%.0f km/h" % car.kmh()


## Your lap so far (INF on an out-lap): online, a guest's laps are timed on its own clock.
func running_lap() -> float:
	if session == null or not session.cars.has(Net.my_id()):
		return INF
	return session.lap_time(Net.my_id(), _t_alive if net and not net.host else -1.0)


## A lap time: 1:47.312.
static func fmt_lap(t: float) -> String:
	if t == INF or t < 0.0:
		return "--"
	var m := int(t / 60.0)
	return "%d:%06.3f" % [m, t - m * 60.0]
