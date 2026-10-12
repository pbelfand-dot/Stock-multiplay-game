extends SceneTree
## The replay (scripts/game/replay.gd, scripts/vehicle/replay_cam.gd, scripts/ui/replay_bar.gd),
## on real runs in the game, the autopilot driving:
##   * RECORDING: ~20 s of a rally stage, every car sampled 60 times a second into a ring; its
##     memory measured (a minute of one car, of cut up's traffic)
##   * POSE: at sampled times the car played back sits where it was recorded (to the mm at the
##     samples, within a cm between them: interpolated), its springs and wheels too
##   * CONTROLS: scrubbing back and forward (the API and the timeline clicked and dragged), the
##     speed (0.25x to 4x: the clock runs that much faster), rewind held, a tap steps 5 s, the
##     end stops it, the start
##   * CAMERAS: every mode a sane view (near the car where it should be, above the ground, the
##     car in view or the camera looking down the road with it); the free cam flies with its
##     keys and never goes below the ground; a placed camera turns onto the car; the director
##     cuts between placed cameras
##   * EXIT: the cars back exactly as they were live (transform, velocities, wheel spin, springs,
##     the drivetrain), the tree running again, the pause menu or the results back, the run
##     carrying on
##   * CUT UP: a replay with the traffic (posed where it was, put back exactly; the cars freed
##     since they passed played by look-alikes where they were)
##   * THE TOUGE, TRACK MODE: a replay opens, plays and closes in each
## Run: godot --headless --fixed-fps 120 --path . -s tests/replay_check.gd
## Prints [replay] lines; exits 1 on any FAIL.

var fails := 0
var Modes
var Replay


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print("[replay] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _run() -> void:
	await process_frame
	Modes = load("res://scripts/game/modes.gd")
	Replay = load("res://scripts/game/replay.gd")
	root.get_node("Net").solo()
	await _rally()
	await _cutup()
	if not OS.get_cmdline_user_args().has("--quick"):
		await _touge()
		await _track()
	print("[replay] " + ("REPLAY OK" if fails == 0 else "REPLAY FAILED (%d)" % fails))
	quit(1 if fails else 0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Everything about a car that has to come back exactly.
func _state(c) -> Dictionary:
	var w: Array = []
	for k in 4:
		var wh = c.wheels[k]
		w.append([wh.omega, wh.compression, wh.spin, wh.grounded, wh.compression_velocity, wh.slip_long, wh.slip_lat, wh.rotation])
	var dt = c.drivetrain
	return {"xf": c.global_transform, "lv": c.linear_velocity, "av": c.angular_velocity, "wheels": w,
		"dt": [dt.omega_e, dt.gear, dt.clutch, dt.boost, dt._shift_t] if dt else [],
		"car": [c.rpm, c.gear, c.steer, c.speed, c.slip, c.grounded, c.on_surface, str(c.comp), str(c.inp), c.visible, c.freeze]}


func _diff(a: Dictionary, b: Dictionary) -> String:
	for k in a:
		if str(a[k]) != str(b[k]):
			return "%s: %s -> %s" % [k, str(a[k]).left(160), str(b[k]).left(160)]
	return ""


## The camera's view of the car: [distance, angle off the middle of the view (deg), height over
## the ground (m), the camera's look along the car's way (dot)].
func _view(g) -> Array:
	var cam: Camera3D = g.replay.cam
	var c: Vector3 = g.car.global_position + Vector3.UP * 0.5
	var p := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var ang := rad_to_deg(fwd.angle_to(c - p)) if p.distance_to(c) > 0.01 else 0.0
	var car_fwd: Vector3 = -g.car.global_transform.basis.z
	return [p.distance_to(c), ang, p.y - g.replay.cam.ground_at(p), fwd.dot(car_fwd)]


# ── a rally stage ─────────────────────────────────────────────────────────

func _rally() -> void:
	var Game = load("res://scripts/game.gd")
	var g = Game.new()
	root.add_child(g)
	await g.start(11, 1, {"mode": "quick", "length": 2200.0})
	check(g.built and g.replay != null, "game: a rally stage loads with its replay recorder")
	g.begin_countdown()
	g.use_autopilot = true
	var truth: Array = []                 # [clock, position, rotation, comp FL, spin FL]
	g.replay.tick_recorded.connect(func(t: float): truth.append([t, g.car.global_position,
		g.car.global_transform.basis.get_rotation_quaternion(), float(g.car.comp[0]), float(g.car.wheels[0].spin)]))
	var t := 0.0
	while (g.state != "running" or g.stage_time < 20.0) and t < 60.0:
		await physics_frame
		t += 1.0 / 120.0
	var rp = g.replay
	var key: String = rp.order[0] if not rp.order.is_empty() else ""
	var tr = rp.tracks.get(key)
	check(tr != null and key == "Car" and rp.duration() > 24.0 and rp.duration() < 26.5 and tr.last - tr.first + 1 == int(round(rp.duration() * 60.0)) + 1,
		"recording: the countdown and 20 s of the stage, %.1f s, %d samples of your car (60 a second)" % [rp.duration(), tr.last - tr.first + 1 if tr else 0])
	var mem: Dictionary = rp.memory_bytes()
	print("[replay] info memory: %d cars, %.0f KB now; one car %.0f KB a minute (%.1f MB for the 10 minutes kept)" % [
		mem.cars_n, mem.total / 1024.0, mem.per_car_min / 1024.0, mem.per_car_min * 10.0 / 1048576.0])
	check(mem.per_car_min < 512 * 1024 and mem.cars < 4 * 1048576, "recording: a car's minute takes %.0f KB (under 512 KB)" % (mem.per_car_min / 1024.0))
	# the live state before: it has to come back exactly
	var live := _state(g.car)
	var live_s: float = g.car_s
	var live_t: float = g.stage_time
	var live_xf: Transform3D = g.car.global_transform
	# the pause menu, its REPLAY
	g._toggle_pause()
	check(g._pause_replay != null and g._pause_replay.visible, "the pause menu has REPLAY")
	g._pause_replay.pressed.emit()
	await process_frame
	check(rp.active and paused and not g._hud.visible and rp.cam.current and rp.bar.visible,
		"the pause menu's REPLAY opens it: the game held (the tree paused), its HUD away, the replay's camera and bar")
	check(absf(rp.time() - (rp.duration() - 30.0 if rp.duration() > 30.0 else 0.0)) < 1.0 or (rp.duration() < 30.0 and rp.time() < 1.0),
		"the pause menu's replay starts 30 s before the pause (or at the start): %.1f s of %.1f" % [rp.time(), rp.duration()])
	rp.input_on = false
	rp.cam.input_on = false
	rp.playing = false
	# the pose, against what the car really did, at samples and between them
	var worst := 0.0
	var worst_mid := 0.0
	var worst_rot := 0.0
	var worst_comp := 0.0
	var worst_spin := 0.0
	var n := 0
	var t0: float = rp.range_first() / 60.0
	for i in range(3, truth.size(), 41):
		var e: Array = truth[i]
		var at: float = float(e[0]) - t0
		if at < 0.0 or at > rp.duration():
			continue
		rp.seek(at)
		rp._frame(0.0)
		var err: float = g.car.global_position.distance_to(e[1])
		var on_sample: bool = i % 2 == 0
		if on_sample:
			worst = maxf(worst, err)
			var bq := Basis(e[2] as Quaternion)
			var bc: Basis = g.car.global_transform.basis
			worst_rot = maxf(worst_rot, rad_to_deg(maxf(bq.z.angle_to(bc.z), bq.y.angle_to(bc.y))))
			worst_comp = maxf(worst_comp, absf(float(g.car.comp[0]) - float(e[3])))
			worst_spin = maxf(worst_spin, absf(angle_difference(float(g.car.wheels[0].spin), float(e[4]))))
		else:
			worst_mid = maxf(worst_mid, err)
		n += 1
	check(n > 20 and worst < 0.002 and worst_rot < 0.01 and worst_comp < 0.0005 and worst_spin < 0.01,
		"pose: at %d sampled times the car played back sits where it was (%.2f mm, %.3f deg; springs %.2f mm, wheel spin %.4f rad)" % [n, worst * 1000.0, worst_rot, worst_comp * 1000.0, worst_spin])
	check(worst_mid < 0.01, "pose: between samples (the ticks in between) within a cm: %.2f mm" % (worst_mid * 1000.0))
	# the controls: scrub back and forward, the speed, rewind held, a tap, the end, the start
	rp.seek(5.0)
	rp._frame(0.0)
	var p5: Vector3 = g.car.global_position
	rp.seek(18.0)
	rp._frame(0.0)
	var p18: Vector3 = g.car.global_position
	rp.seek(5.0)
	rp._frame(0.0)
	check(absf(rp.time() - 5.0) < 0.01 and g.car.global_position.distance_to(p5) < 0.001 and p5.distance_to(p18) > 30.0,
		"controls: scrubbing back (18 s -> 5 s) and forward puts the car back where it was then (%.0f m apart)" % p5.distance_to(p18))
	await process_frame                                  # (the bar laid out)
	var tl: Control = rp.bar.timeline
	var w: float = tl.size.x
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(w * 0.75, tl.size.y * 0.5)
	tl._gui_input(ev)
	var t_click: float = rp.time()
	var mv := InputEventMouseMotion.new()
	mv.position = Vector2(w * 0.25, tl.size.y * 0.5)
	tl._gui_input(mv)
	var t_drag: float = rp.time()
	var held_clock: bool = rp._scrub
	ev = ev.duplicate()
	ev.pressed = false
	tl._gui_input(ev)
	check(w > 200.0 and absf(t_click - rp.duration() * 0.75) < 0.1 and absf(t_drag - rp.duration() * 0.25) < 0.1 and held_clock and not rp._scrub,
		"controls: the timeline clicked at 3/4 (%.1f s) and dragged back to 1/4 (%.1f s) of %.1f s" % [t_click, t_drag, rp.duration()])
	var rates := {}
	for si in [0, 2, 4]:
		rp.set_speed(si)
		rp.seek(4.0)
		rp.playing = true
		var a: float = rp.time()
		await _frames(120)
		rates[si] = (rp.time() - a) / (120.0 / 120.0)
		rp.playing = false
	check(absf(rates[0] - 0.25) < 0.03 and absf(rates[2] - 1.0) < 0.05 and absf(rates[4] - 4.0) < 0.15,
		"controls: the speed runs the replay's clock at %.2fx, %.2fx, %.2fx for 0.25x, 1x, 4x" % [rates[0], rates[2], rates[4]])
	rp.input_on = true
	rp.seek(15.0)
	Input.action_press("replay_back")
	await _frames(120)
	Input.action_release("replay_back")
	await _frames(2)
	var after_rew: float = rp.time()
	rp.seek(15.0)
	Input.action_press("replay_back")
	await _frames(4)
	Input.action_release("replay_back")
	await _frames(2)
	var after_tap: float = rp.time()
	rp.seek(rp.duration() - 1.0)
	rp.set_speed(4)
	rp.playing = true
	await _frames(120)
	var at_end: bool = not rp.playing and absf(rp.time() - rp.duration()) < 0.01
	Input.action_press("replay_start")
	await _frames(1)
	Input.action_release("replay_start")
	await _frames(1)
	var to_start: float = rp.time()
	rp.input_on = false
	rp.playing = false
	rp.set_speed(2)
	check(after_rew < 15.0 - 4.0 and after_rew > 15.0 - 7.0, "controls: rewind held 1 s runs it back %.1f s (6x)" % (15.0 - after_rew))
	check(absf(after_tap - 10.0) < 0.1, "controls: a tap of rewind steps 5 s back (%.1f s -> %.1f s)" % [15.0, after_tap])
	check(at_end and to_start < 0.01, "controls: playing on stops at the end; HOME / START goes back to the start")
	# the cameras
	rp.seek(10.0)
	rp.playing = true
	var limits := {"chase": 12.0, "cockpit": 2.5, "hood": 3.0, "bumper": 3.0, "wheel": 3.5, "side": 5.0, "front": 9.0,
		"drone": 16.0, "heli": 35.0, "orbit": 14.0, "tv": 260.0}
	var looks_at := ["chase", "front", "drone", "heli", "orbit", "tv"]
	var looks_along := ["cockpit", "hood", "bumper", "wheel", "side"]
	var bad: Array = []
	var seen := []
	for m in limits:
		rp.cam.set_mode(m)
		await _frames(90)
		var v := _view(g)
		var cam: Camera3D = rp.cam
		var ok: bool = float(v[0]) < float(limits[m]) and float(v[2]) > 0.05
		if m in looks_at:
			ok = ok and cam.is_position_in_frustum(g.car.global_position + Vector3.UP * 0.5)
		if m in looks_along:
			ok = ok and float(v[3]) > 0.7
		seen.append("%s %.1fm %.0fdeg" % [m, v[0], v[1]])
		if not ok:
			bad.append("%s (%.1f m, %.0f deg off, %.2f m up, along %.2f, fov %.0f)" % [m, v[0], v[1], v[2], v[3], cam.fov])
	check(bad.is_empty(), "cameras: every mode a sane view (%s)%s" % [", ".join(seen), "" if bad.is_empty() else " BAD: " + ", ".join(bad)])
	# the TV camera hands over as the car goes by
	rp.cam.set_mode("tv")
	await _frames(2)
	var first_tv: Vector3 = rp.cam.global_position
	rp.set_speed(4)
	await _frames(240)
	rp.set_speed(2)
	check(rp.cam.global_position.distance_to(first_tv) > 10.0, "cameras: the trackside TV camera hands over to the next one up the road (%.0f m on)" % rp.cam.global_position.distance_to(first_tv))
	# the free cam: flies with its keys, never below the ground
	rp.playing = false
	rp.cam.set_mode("free")
	rp.cam.input_on = true
	await _frames(1)
	var p0: Vector3 = rp.cam.global_position
	var fwd0: Vector3 = -rp.cam.global_transform.basis.z
	Input.action_press("replay_fly_forward")
	await _frames(60)
	Input.action_release("replay_fly_forward")
	var moved: Vector3 = rp.cam.global_position - p0
	Input.action_press("replay_fly_down")
	Input.action_press("replay_fly_fast")
	await _frames(360)
	Input.action_release("replay_fly_down")
	Input.action_release("replay_fly_fast")
	var low: Vector3 = rp.cam.global_position
	var floor_y: float = rp.cam.ground_at(low + Vector3.UP * 5.0, 1.0)
	check(moved.length() > 5.0 and moved.normalized().dot(fwd0) > 0.95, "cameras: the free cam flies forward on its key (%.1f m in 0.5 s)" % moved.length())
	check(low.y >= floor_y + 0.3 and low.y < floor_y + 1.0, "cameras: flown down hard for 3 s it stops above the ground (%.2f m over it)" % (low.y - floor_y))
	# placed cameras: one turns onto the car; the director cuts between two
	rp.cam.input_on = false
	var st = g.st
	rp.seek(4.0)
	rp._frame(0.0)
	var s_a: float = st.locate(g.car.global_position).s
	rp.seek(20.0)
	rp._frame(0.0)
	var s_b: float = st.locate(g.car.global_position).s
	rp.cam.placed.clear()
	for s in [s_a + 15.0, s_b + 15.0]:
		var at_road: Vector3 = st.world_at(s, st.width_at(s) * 0.5 + 4.0)
		rp.cam.free_pos = at_road + Vector3.UP * 3.0
		rp.cam._free_cam(0.0, Vector2.ZERO)
		rp.cam.place_here()
	rp.seek(12.0)
	rp.cam.set_mode("cam1")
	rp.playing = true
	await _frames(120)
	var v1 := _view(g)
	check(rp.cam.placed.size() == 2 and float(v1[1]) < 6.0 and rp.cam.global_position.distance_to(rp.cam.placed[0]) < 0.01,
		"cameras: a placed camera stays put and turns onto the car (%.1f deg off, %.0f m away, fov %.0f)" % [v1[1], v1[0], rp.cam.fov])
	rp.seek(3.0)
	rp.cam.set_mode("director")
	rp.playing = true
	rp.set_speed(1)
	await _frames(240)
	var shot_a: int = rp.cam.shot
	rp.seek(19.0)
	await _frames(400)
	var shot_b: int = rp.cam.shot
	check(shot_a == 0 and shot_b == 1, "cameras: the director cuts from the camera by the car early on (CAM %d) to the one by it later (CAM %d)" % [shot_a + 1, shot_b + 1])
	rp.set_speed(2)
	rp.playing = false
	# out: everything back exactly, the pause menu back, the run going on
	rp.close()
	var back := _state(g.car)                           # (straight away: the next tick drives on)
	var d := _diff(live, back)
	check(d == "", "exit: your car exactly as it was live (transform, velocities, wheel spin, springs, drivetrain)%s" % ("" if d == "" else ": " + d))
	check(not paused and g._hud.visible and g._pause.visible and g.paused() and not rp.cam.current and g.cam.current,
		"exit: the tree running again, the game's camera back, the pause menu up (paused, as it was)")
	check(g.car_s == live_s and g.stage_time == live_t, "exit: the stage clock and the car's place on the road untouched (%.1f s, %.0f m)" % [live_t, live_s])
	await process_frame
	g._toggle_pause()
	await physics_frame
	var jump: float = g.car.global_position.distance_to(live_xf.origin)
	var t1: float = g.stage_time
	var s1: float = g.car_s
	for i in 360:
		await physics_frame
	check(jump < 0.5 and g.stage_time > t1 + 2.9 and g.car_s > s1 + 20.0 and g.state == "running",
		"exit: the run carries on (%.2f m in the first tick, %.0f m more in 3 s)" % [jump, g.car_s - s1])
	# the results: REPLAY from there, back to the results
	g.stage_finished(g.stage_time, 0.0, 0, false)
	await process_frame
	var btn: Button = g._results.find_child("ReplayButton", true, false)
	check(btn != null and btn.visible and btn.focus_mode == Control.FOCUS_NONE, "the results have a REPLAY button (ENTER stays next)")
	btn.pressed.emit()
	await process_frame
	var from_go: float = rp.time()
	var go_t: float = (rp.go_frame - rp.range_first()) / 60.0
	check(rp.active and rp.from == "results" and absf(from_go - (go_t - 2.0)) < 0.2, "the results' REPLAY plays the run from just before GO (%.1f s, GO at %.1f s)" % [from_go, go_t])
	rp.input_on = true
	await _frames(30)
	Input.action_press("replay_exit")
	await _frames(2)
	Input.action_release("replay_exit")
	await _frames(1)
	check(not rp.active and g.state == "finished" and g._results.visible and g._hud.visible and not paused,
		"BACKSPACE (or ESC) leaves it: back on the results")
	Input.action_press("replay")
	await _frames(2)
	Input.action_release("replay")
	check(rp.active, "V (X on a pad) on the results opens it again")
	rp.close()
	g.queue_free()
	await process_frame


# ── cut up: the traffic ───────────────────────────────────────────────────

func _cutup() -> void:
	var Game = load("res://scripts/game.gd")
	var g = Game.new()
	root.add_child(g)
	var o: Dictionary = Modes.cutup_opts(3, "hard")
	await g.start(3, 1, o)
	g.begin_countdown()
	g.use_autopilot = true
	var rp = g.replay
	var truth := {}                       # prop frame -> {instance id: position}
	rp.tick_recorded.connect(func(_t: float):
		if rp.frame % Replay.PROP_EVERY == 0 and not truth.has(rp.frame / Replay.PROP_EVERY):
			var d := {}
			for n in rp._prop_candidates():
				if (n as Node3D).is_visible_in_tree():
					d[n.get_instance_id()] = (n as Node3D).global_position
			truth[rp.frame / Replay.PROP_EVERY] = d)
	var t := 0.0
	var stuck := 0.0
	while (g.state != "running" or g.stage_time < 12.0) and t < 60.0:
		await physics_frame
		t += 1.0 / 120.0
		stuck = stuck + 1.0 / 120.0 if g.state == "running" and g.car.kmh() < 5.0 else 0.0
		if stuck > 3.0:
			g.reset_car()
			stuck = 0.0
	# three cars freed the way the game frees them (Traffic._put_away without keeping: a rival
	# when its challenge is over, online mirrors leaving the stretch, the loop's oncoming cars past
	# the spares kept), then a moment more of the run
	var freed := 0
	for c in g.traffic.cars.duplicate():
		if freed >= 3 or c.has("rival"):
			continue
		g.traffic.cars.erase(c)
		g.traffic._put_away(c.body, "%s/1" % c.model, false)
		freed += 1
	for i in 60:
		await physics_frame
	var mem: Dictionary = rp.memory_bytes()
	print("[replay] info cut up memory: %.0f traffic cars a frame on average, %.0f KB a minute for them (%.1f MB for 10 minutes), %.0f KB a minute a car" % [
		mem.props_avg, mem.props_min / 1024.0, mem.props_min * 10.0 / 1048576.0, mem.per_car_min / 1024.0])
	check(mem.props_avg > 10.0 and mem.props_min < 4 * 1048576, "cut up: the traffic recorded (%.0f cars a frame, %.0f KB a minute)" % [mem.props_avg, mem.props_min / 1024.0])
	var before := {}
	for n in rp._prop_candidates():
		before[n.get_instance_id()] = [(n as Node3D).global_transform, (n as Node3D).visible]
	var car_before := _state(g.car)
	check(rp.open("results"), "cut up: the replay opens")
	rp.input_on = false
	rp.playing = false
	var worst := 0.0
	var count := 0
	var gone := 0                         # cars freed since they were recorded
	var gone_worst := 0.0
	var gone_missing := 0
	var t0: float = rp.range_first() / 60.0
	for pf in truth:
		if pf % 7 != 0:
			continue
		var at: float = pf * Replay.PROP_EVERY / 60.0 - t0
		if at < 0.5 or at > rp.duration():
			continue
		rp.seek(at)
		rp._frame(0.0)
		for id in truth[pf]:
			var nd := instance_from_id(id) as Node3D
			if nd == null:                    # (freed: a look-alike must play it, where it was)
				var sb: Node3D = rp._standins.get(int(rp._prop_index.get(id, -1)))
				gone += 1
				if sb == null or not sb.visible:
					gone_missing += 1
				else:
					gone_worst = maxf(gone_worst, sb.global_position.distance_to(truth[pf][id]))
				continue
			var e: float = nd.global_position.distance_to(truth[pf][id])
			if e > 0.01 and OS.get_cmdline_user_args().has("--debug"):
				print("[replay] debug pf %d id %d err %.2f in props %s visible %s posed %s truth %s idx %s" % [pf, id, e, rp._props.has(id), nd.visible, nd.global_position, truth[pf][id], rp._prop_index.get(id, -1)])
			worst = maxf(worst, e)
			count += 1
	check(count > 100 and worst < 0.01, "cut up: the traffic played back where it was (%d cars checked, worst %.2f mm)" % [count, worst * 1000.0])
	check(gone > 0 and gone_missing == 0 and gone_worst < 0.01,
		"cut up: every car that was there is in it, the ones freed since played by look-alikes where they were (%d checked, %d missing, worst %.2f mm)" % [gone, gone_missing, gone_worst * 1000.0])
	rp.cam.set_mode("drone")
	rp.playing = true
	await _frames(60)
	var v := _view(g)
	check(float(v[0]) < 16.0 and float(v[2]) > 0.05, "cut up: the drone films the car through the traffic (%.1f m, %.1f m up)" % [v[0], v[2]])
	rp.close()
	var moved := 0
	for id in before:
		var nd := instance_from_id(id) as Node3D
		if nd and (nd.global_transform != before[id][0] or nd.visible != before[id][1]):
			moved += 1
	var d := _diff(car_before, _state(g.car))
	await process_frame
	check(moved == 0 and d == "", "cut up: out of the replay every traffic car and yours exactly as they were (%d moved)%s" % [moved, "" if d == "" else ": " + d])
	var s1: float = g.car_s
	for i in 240:
		await physics_frame
	check(g.car_s > s1 + 10.0, "cut up: and the run carries on (%.0f m in 2 s)" % (g.car_s - s1))
	g.queue_free()
	await process_frame


# ── the touge and Track Mode: it opens, plays, closes ─────────────────────

func _short(g, what: String, secs: float) -> void:
	g.begin_countdown()
	g.use_autopilot = true
	var t := 0.0
	while (g.state != "running" or g.stage_time < secs) and t < 60.0:
		await physics_frame
		t += 1.0 / 120.0
	var rp = g.replay
	var before := _state(g.car)
	var opened: bool = rp.open("pause")
	rp.input_on = false
	var bad: Array = []
	for m in ["chase", "cockpit", "drone", "tv", "orbit"]:
		rp.cam.set_mode(m)
		await _frames(30)
		var v := _view(g)
		if float(v[2]) < 0.05 or float(v[0]) > 260.0:
			bad.append(m)
	rp.close()
	var d := _diff(before, _state(g.car))
	await process_frame
	check(opened and bad.is_empty() and d == "", "%s: a replay opens (%.1f s), films the car, closes with the car as it was%s%s" % [what, rp.duration(),
		"" if bad.is_empty() else " BAD cameras " + str(bad), "" if d == "" else ": " + d])


func _touge() -> void:
	var Game = load("res://scripts/game.gd")
	var g = Game.new()
	root.add_child(g)
	var o: Dictionary = Modes.touge_opts(4, "up", "time")
	o["length"] = 1400.0
	await g.start(4, 1, o)
	await _short(g, "touge", 8.0)
	g.queue_free()
	await process_frame


func _track() -> void:
	var Game = load("res://scripts/game.gd")
	var g = Game.new()
	root.add_child(g)
	await g.start(5, 1, Modes.track_opts(5, "gt", "practice", 5))
	await _short(g, "track mode", 8.0)
	g.queue_free()
	await process_frame
