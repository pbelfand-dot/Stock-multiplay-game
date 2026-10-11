extends SceneTree
## Pictures of the replay's cameras (docs/replay.md), for a look by eye: a run driven by the
## autopilot, then the replay opened and a frame saved for each camera (the bar on), plus
## placed cameras and the director. Needs a display (xvfb):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 --fixed-fps 30 \
##       -s tools/replay_shots.gd -- --out=DIR [--mode=rally|cutup|touge|track] [--seed=N] [--secs=S] \
##       [--at=S] [--cams=chase,drone,...] [--car=ID] --seen_cars_only
## --seen_cars_only keeps the no-AI cars out of the traffic and off the touge; the car driven is
## the garage's (or --car=ID): pick one that isn't no-AI. Prints "[shots] saved PATH" per picture.

var out := "user://replay_shots"
var mode := "rally"
var seed_value := 11
var secs := 14.0
var at := -1.0
var frames := 24                     # frames played before each picture (the cameras settle)
var cams: Array = ["chase", "cockpit", "hood", "bumper", "wheel", "side", "front", "drone", "heli", "tv", "orbit", "free", "cam1", "director"]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		match kv[0]:
			"out":
				out = kv[1]
			"mode":
				mode = kv[1]
			"seed":
				seed_value = int(kv[1])
			"secs":
				secs = float(kv[1])
			"at":
				at = float(kv[1])
			"cams":
				cams = Array(kv[1].split(","))
			"frames":
				frames = int(kv[1])
	_run.call_deferred()


func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(out)
	var Modes = load("res://scripts/game/modes.gd")
	root.get_node("Net").solo()
	var o: Dictionary = {"mode": "quick", "length": 2600.0}
	match mode:
		"cutup":
			o = Modes.cutup_opts(seed_value, "normal")
		"touge":
			o = Modes.touge_opts(seed_value, "up", "time")
			o["length"] = 2000.0
		"track":
			o = Modes.track_opts(seed_value, "gt", "practice", 5)
	var g = load("res://scripts/game.gd").new()
	root.add_child(g)
	await g.start(seed_value, 1, o)
	print("[shots] %s on seed %d, the car: %s (%s)" % [mode, seed_value, str(g.car.setup.get("car", "?")), str(g.car.setup.get("name", "?"))])
	RenderingServer.render_loop_enabled = false            # (no drawing while it drives: quicker)
	g.begin_countdown()
	g.use_autopilot = true
	var t := 0.0
	var stuck := 0.0
	while (g.state != "running" or g.stage_time < secs) and t < 120.0:
		await physics_frame
		t += 1.0 / 120.0
		stuck = stuck + 1.0 / 120.0 if g.state == "running" and g.car.kmh() < 5.0 else 0.0
		if stuck > 3.0:
			g.reset_car()
			stuck = 0.0
	RenderingServer.render_loop_enabled = true
	var rp = g.replay
	rp.open("results")
	rp.input_on = false
	rp.cam.input_on = false
	var when: float = at if at >= 0.0 else rp.duration() - 6.0
	for m in cams:
		if m == "cam1" or m == "director":
			if rp.cam.placed.is_empty():
				_place_two(g)
		rp.seek(when)
		rp.playing = true
		rp.cam.set_mode(m)
		if m == "free":
			var c: Vector3 = g.car.global_position
			var fwd: Vector3 = -g.car.global_transform.basis.z
			rp.cam.free_pos = c - fwd * 10.0 + fwd.cross(Vector3.UP).normalized() * 7.0 + Vector3.UP * 6.0
			var d: Vector3 = (c + fwd * 10.0) - rp.cam.free_pos
			rp.cam.free_yaw = atan2(-d.x, -d.z)
			rp.cam.free_pitch = asin(clampf(d.normalized().y, -1.0, 1.0))
			rp.playing = true
		for i in frames:
			await process_frame
		var path := out.path_join("%s_%s.png" % [mode, m])
		root.get_viewport().get_texture().get_image().save_png(path)
		print("[shots] saved %s (%s)" % [path, rp.cam.title()])
	rp.close()
	quit(0)


## Two placed cameras by the road where the car is in the shots, one ahead of the other.
func _place_two(g) -> void:
	var rp = g.replay
	var st = g.st
	var when: float = at if at >= 0.0 else rp.duration() - 6.0
	rp.seek(when + 0.5)
	rp._frame(0.0)
	var s0: float = float(st.locate(g.car.global_position).s)
	for ds in [18.0, 70.0]:
		var s: float = s0 + ds
		var side := -1.0 if ds > 30.0 else 1.0
		var p: Vector3 = st.world_at(s, side * (float(st.width_at(s)) * 0.5 + 4.0)) + Vector3.UP * 2.5
		rp.cam.set_mode("free")
		rp.cam.free_pos = p
		rp.cam._free_cam(0.0, Vector2.ZERO)
		rp.cam.place_here()
