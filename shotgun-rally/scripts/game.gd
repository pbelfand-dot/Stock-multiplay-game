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
const StageBuilder = preload("res://scripts/stage/stage_builder.gd")
const Notes = preload("res://scripts/stage/pacenotes.gd")
const RallyCar = preload("res://scripts/vehicle/rally_car.gd")
const Cockpit = preload("res://scripts/vehicle/cockpit.gd")
const DriftFx = preload("res://scripts/vehicle/drift_fx.gd")
const SeatCam = preload("res://scripts/vehicle/seat_cam.gd")
const AICoDriver = preload("res://scripts/vehicle/ai_codriver.gd")
const Autopilot = preload("res://scripts/vehicle/autopilot.gd")
const EngineSound = preload("res://scripts/vehicle/engine_sound.gd")
const StartLights = preload("res://scripts/ui/start_lights.gd")
const Catalog = preload("res://scripts/game/catalog.gd")

signal progress(fraction: float, what: String)
signal stage_generated

const COUNTDOWN := 5.0
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
var built := false                  # start() has finished (it builds over several frames)
var _look_acc := 0.0
var _last_count := -1
var _hud: CanvasLayer
var _lights                         # StartLights: the countdown + stage clock on screen
var _hint_label: Label
var _big_label: Label
var _results: PanelContainer
var _results_label: Label
var _pause: PanelContainer
var _t_alive := 0.0
var _sfx := {}
var _engine                        # EngineSound
var _gravel: AudioStreamPlayer3D
var _squeal: AudioStreamPlayer3D     # the tyres on the asphalt, sliding
var _squeal_amt := 0.0


## Build the stage, a step a frame (await it): progress(fraction, what) feeds the
## loading screen; stage_generated fires once the road is known. o: the stage's
## settings (Main.opts): a story stage brings its length, light (mood), road
## character (gen) and titles.
func start(seed_in: int, stage_in: int, o := {}) -> void:
	seed_value = seed_in
	stage_no = stage_in
	opts = o
	use_autopilot = Config.flag("autopilot")
	progress.emit(0.02, "Reading the road book")
	await get_tree().process_frame
	if not is_inside_tree():
		return
	st = StageGen.new()
	st.opts = o.get("gen", {})
	st.generate(seed_value, float(o.get("length", Config.arg("length", 2600))))
	notes = Notes.build(st)
	calls = Notes.calls(notes)
	stage_generated.emit()
	builder = StageBuilder.new()
	builder.mood = o.get("mood", "day")
	add_child(builder)
	await builder.build_async(st, func(f: float, what: String): progress.emit(0.06 + f * 0.64, what))
	if not is_inside_tree():
		return
	progress.emit(0.72, "Building the car")
	await get_tree().process_frame
	if not is_inside_tree():
		return
	car = RallyCar.new()
	car.name = "Car"
	add_child(car)
	_start_pos = st.world_at(st.START_S - 3.0, 0.0)
	car.place(_start_pos, st.heading_at(st.START_S))
	car.hit.connect(_on_hit)
	car.landed.connect(_on_landed)
	var fx := DriftFx.new()                       # dirt + stones off the tyres when it slides
	fx.name = "DriftFx"
	fx.car = car
	car.add_child(fx)
	progress.emit(0.84, "Strapping in the crew")
	await get_tree().process_frame
	if not is_inside_tree():
		return
	cockpit = Cockpit.new()
	car.add_child(cockpit)
	cockpit.build(car, st)
	progress.emit(0.96, "Warming up the engine")
	cockpit.wiper_stroke.connect(func(): _play("wiper", -6.0))
	ai = AICoDriver.new()
	add_child(ai)
	ai.setup(calls)
	autopilot = Autopilot.new(st)
	cam = SeatCam.new()
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


## Seats decide who simulates the car, whose camera goes where, and whether
## the AI co-driver talks (only when nobody's in the passenger seat).
func _apply_roster() -> void:
	my_seat = Net.my_seat()
	var driver_here: bool = my_seat == "driver"
	var setup := Catalog.for_stage(Net.car_setup(), st)   # the driver's car from their garage, its tyres for this stage
	car.apply_setup(setup)
	cockpit.set_paint(setup.colours[0])
	car.set_simulating(driver_here)
	cam.attach(car, my_seat, Cockpit.EYE_DRIVER if driver_here else Cockpit.EYE_CODRIVER)
	cockpit.set_my_seat(my_seat)
	ai.enabled = Net.peer_in("codriver") == 0
	_update_hint()


# ── loading handshake (host) ──────────────────────────────────────────────

@rpc("any_peer", "call_local", "reliable")
func loaded() -> void:
	if not multiplayer.is_server():
		return
	_loaded_peers[multiplayer.get_remote_sender_id()] = true
	if _loaded_peers.size() >= Net.players.size():
		set_all_loaded.rpc(true)


@rpc("authority", "call_local", "reliable")
func set_all_loaded(v: bool) -> void:
	all_loaded = v
	if v and ai and ai.enabled and state == "grid":
		ai.say(["ready"])                        # "co-driver ready": then the host starts the count
	_update_hint()


func crew_ready() -> bool:
	return all_loaded and (not Net.online() or Net.crew_full())


# ── the stage ─────────────────────────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func begin_countdown() -> void:
	if state != "grid" or not built:
		return
	state = "countdown"
	countdown = COUNTDOWN
	_last_count = -1
	car.place(_start_pos, st.heading_at(st.START_S))
	ai.hush()                                    # the count has to land on the second
	_update_hint()


@rpc("any_peer", "call_local", "reliable")
func stage_finished(time: float, pens: float, n_resets: int, jumped: bool) -> void:
	if state == "finished":
		return
	state = "finished"
	result = {"time": time, "penalties": pens, "total": time + pens, "resets": n_resets, "jump_start": jumped,
		"stage": stage_no, "seed": seed_value}
	if ai.enabled:
		ai.say(["stage-complete"])
	_play("bell", -4.0)
	_show_results()
	finished.emit(result)


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
	car_s = at.s
	car_d = at.d
	car.set_lanes(st, car_s, car_d)
	cockpit.map_board.car_s = car_s
	car.stream_ok = crew_ready()          # nobody to send to (or they're still loading): don't
	match state:
		"grid":
			if Net.is_server() and crew_ready() and (Input.is_action_just_pressed("ready") or Config.flag("autostart")):
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
				if Net.online():
					stage_finished.rpc(args[0], args[1], args[2], args[3])
				else:
					stage_finished(args[0], args[1], args[2], args[3])
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
	if Net.online() and crew_ready() and _look_acc > 0.1:
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
		"brake": _brake_eased, "handbrake": Input.is_action_pressed("handbrake")}
	if state == "grid":
		inp.handbrake = true                         # parked at the line until the countdown
		inp.brake = maxf(inp.brake, 0.6)
	if _pause.visible:
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
	if Input.is_action_just_pressed("reset_car") and state == "running":
		reset_car()


func reset_car() -> void:
	var s := clampf(car_s, st.START_S, st.finish_s)
	if Config.flag("smoke") or Config.flag("aicheck"):
		print("[stage] reset at s=%.0f d=%.1f, %.0f km/h" % [car_s, car_d, car.kmh()])
	car.place(st.world_at(s, 0.0), st.heading_at(s))
	resets += 1
	penalties += RESET_PENALTY
	_sync_penalties()
	_play("thud", -6.0)


func _sync_penalties() -> void:
	if Net.online():
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
		if Net.online():
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


func _process(dt: float) -> void:
	if not built:
		return
	# wipers: the co-driver's job (the driver's when alone)
	if Input.is_action_just_pressed("wipers") and (my_seat == "codriver" or Net.peer_in("codriver") == 0):
		if Net.online():
			wipe.rpc()
		else:
			wipe()
	if Input.is_action_just_pressed("pause"):
		_toggle_pause()
	if state == "finished" and Net.is_server() and not _pause.visible:
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
	if want != cam.view:
		cam.view = want
		car.set_outside(want != "seat")
		cockpit.visible = want == "seat"
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
	# on the asphalt a sliding tyre squeals
	var sq: float = car.slip * on_ground * clampf(spd / 8.0, 0.0, 1.0) if car.on_surface == "asphalt" else 0.0
	_squeal_amt = move_toward(_squeal_amt, sq, get_process_delta_time() * 6.0)
	_squeal.volume_db = linear_to_db(maxf(_squeal_amt, 0.001)) - 13.0
	_squeal.pitch_scale = 0.92 + _squeal_amt * 0.16


func _on_hit(impact: float) -> void:
	_play("crash", clampf(-20.0 + impact, -18.0, 0.0))
	cam.bump(clampf(impact / 15.0, 0.2, 1.0))


func _on_landed(impact: float) -> void:
	_play("thud", clampf(-18.0 + impact * 2.0, -16.0, 0.0))
	cam.bump(clampf(impact / 10.0, 0.1, 0.7))


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
	_results = _panel()
	_results_label = Label.new()
	_results_label.add_theme_font_override("font", font)
	_results_label.add_theme_font_size_override("font_size", 28)
	_results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results.add_child(_results_label)
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
	for b in [["RESUME", _toggle_pause], ["QUIT TO MENU", func(): get_parent().to_menu()]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.add_theme_font_override("font", font)
		btn.add_theme_font_size_override("font_size", 26)
		btn.custom_minimum_size = Vector2(320, 56)
		btn.pressed.connect(b[1])
		vb.add_child(btn)
	_pause.visible = false


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.07, 0.88)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(28)
	p.add_theme_stylebox_override("panel", sb)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	_hud.add_child(p)
	return p


func _toggle_pause() -> void:
	_pause.visible = not _pause.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _pause.visible else Input.MOUSE_MODE_CAPTURED


func _update_hint() -> void:
	if _hint_label == null:
		return
	var t := ""
	var pad: bool = Controls.has_pad()
	match state:
		"grid":
			if Net.online() and not Net.crew_full():
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
	_big_label.text = title if state == "grid" else ""


func _seat_help(pad: bool) -> String:
	if my_seat == "driver":
		var alone := " · F wipers" if Net.peer_in("codriver") == 0 else ""
		return ("YOU DRIVE: left stick steer · RT gas · LT brake · B handbrake · Y reset · R3 chase cam" if pad
			else "YOU DRIVE: WASD / arrows · SPACE handbrake · R reset (+5 s) · C chase cam" + alone)
	return ("YOU RIDE SHOTGUN: hold LT to look at the map and call the road · A wipers · right stick look" if pad
		else "YOU RIDE SHOTGUN: hold RIGHT MOUSE (or Q) to look at the map and call the road · F wipers · mouse to look")


func _my_ips() -> Array:
	var out: Array = []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254"):
			out.append(ip)
	return out.slice(0, 3)


## Main's lines under the results (credits, rally standings) and what ENTER does.
func set_result_extra(lines: Array, next_text: String) -> void:
	_result_extra = lines
	_next_text = next_text
	if state == "finished":
		_show_results()


func _show_results() -> void:
	_results.visible = true
	var r := result
	var head: String = opts.stage_name + "  COMPLETE" if opts.get("mode") == "story" else "STAGE %d COMPLETE" % r.stage
	var lines := [head, "", "Time  %s" % fmt_time(r.time)]
	_results_label.add_theme_font_size_override("font_size", 22 if _result_extra.size() > 3 else 28)
	if r.penalties > 0.0:
		var why: Array = []
		if r.jump_start:
			why.append("jump start")
		if r.resets > 0:
			why.append("%d reset%s" % [r.resets, "s" if r.resets > 1 else ""])
		lines.append("Penalties  +%.0f s  (%s)" % [r.penalties, ", ".join(why)])
	lines.append("TOTAL  %s" % fmt_time(r.total))
	if not _result_extra.is_empty():
		lines.append("")
		lines.append_array(_result_extra)
	lines.append("")
	if Net.is_server():
		lines.append("ENTER  %s     R  retry this one" % _next_text + ("     TAB  swap seats" if Net.online() and Net.crew_full() else ""))
	else:
		lines.append("Waiting for the host...")
	_results_label.text = "\n".join(lines)
	_update_hint()
