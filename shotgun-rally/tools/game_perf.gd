extends SceneTree
## What a game costs the CPU each frame: plays a mode on the autopilot (the cockpit, the
## crew, the traffic, the AI co-driver all running) and prints the time the scripts and
## the physics took a frame: the mean, the 95th percentile, the worst. Headless, so the
## drawing isn't in it (tools/stage_perf.gd counts that).
##   godot --headless --fixed-fps 120 --path . -s tools/game_perf.gd -- --mode=cutup [--seconds=20] [--car=kaiser_4]
##   modes: rally | touge | cutup (the loop, traffic on hard)
## One "[perf]" summary line (JSON).

const Modes = preload("res://scripts/game/modes.gd")

var mode := "rally"
var seconds := 20.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"mode": mode = kv[1]
			"seconds": seconds = float(kv[1])
	_run.call_deferred()


func _run() -> void:
	await process_frame
	root.get_node("Net").solo()
	var g = load("res://scripts/game.gd").new()
	root.add_child(g)
	var o: Dictionary = {}
	match mode:
		"touge": o = Modes.touge_opts(3, "down")
		"cutup": o = Modes.cutup_opts(3, "hard")
	var t0 := Time.get_ticks_msec()
	await g.start(3, 1, o)
	var build_ms := Time.get_ticks_msec() - t0
	g.begin_countdown()
	g.use_autopilot = true
	var proc: Array = []
	var phys: Array = []
	var most := 0
	var t := 0.0
	var stuck := 0.0
	while t < seconds + 4.0:
		await physics_frame
		t += 1.0 / 120.0
		if t > 4.0:                                    # (after the countdown)
			proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		if g.traffic:
			most = maxi(most, g.traffic.count())
		stuck = stuck + 1.0 / 120.0 if g.state == "running" and g.car.kmh() < 5.0 else 0.0
		if stuck > 3.0:
			g.reset_car()
			stuck = 0.0
	print("[perf] " + JSON.stringify({"mode": mode, "build_ms": build_ms, "traffic": most,
		"process_ms": _stats(proc), "physics_ms": _stats(phys),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}))
	quit()


static func _stats(a: Array) -> Dictionary:
	if a.is_empty():
		return {}
	var s := a.duplicate()
	s.sort()
	var sum := 0.0
	for v in s:
		sum += v
	return {"mean": snappedf(sum / s.size(), 0.01), "p95": snappedf(s[int(s.size() * 0.95)], 0.01), "max": snappedf(s[-1], 0.01)}
