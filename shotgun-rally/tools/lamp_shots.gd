extends SceneTree
## Night pictures of the cars' lamps (scripts/vehicle/car_lamps.gd, scripts/render/car_look.gd), for
## a look by eye: a run driven by the autopilot a few seconds, your car from the chase cam and the
## driver's seat, then the world held still and each car looked at from outside (the nose close up,
## the front three-quarter, straight ahead, the side with its light on the road, from above
## behind): yours, another driver's (a RallyCar played from a stream, as online), the touge's stray
## car, a traffic car's model with its faked light on the road (--glow, set on this road), cut up's
## nearest traffic car ahead. Then the beams' cost: the same held view timed with
## every CarLamps beam on and off. Needs a display (xvfb), under the render lock (each run >2 GB):
##   xvfb-run -a -s "-screen 0 960x540x24" godot --path . --resolution 960x540 --fixed-fps 30 \
##       -s tools/lamp_shots.gd -- --out=DIR [--mode=touge|cutup|track] [--seed=N] [--secs=S] \
##       [--car=ID] [--other=ID] [--glow=ID] [--gfx=medium] [--views=mine,other,stray,glow,traffic] [--settle=N] \
##       [--before=DIR] --seen_cars_only
## --seen_cars_only keeps the no-AI cars out of the traffic and off the touge; --car (yours) and
## --other must be cars that aren't no-AI (it stops if either is). --before=DIR: DIR's copies of
## car_lamps.gd, car_look.gd, stray_car.gd and game.gd (any of them: say, git show HEAD~1:...)
## stand in for the project's for this run: before / after pictures from one checkout. Prints
## "[lampshots] saved PATH".

const VehicleRegistry = preload("res://scripts/game/vehicle_registry.gd")
const Profile = preload("res://scripts/game/profile.gd")

## the scripts --before can stand in (those of them in its DIR, by file name)
const BEFORE := ["vehicle/car_lamps.gd", "render/car_look.gd", "game/stray_car.gd", "game.gd"]

## camera [at, looking at] in the car's own space (-z forward, y up)
const VIEWS := {
	"nose": [Vector3(-1.5, 0.9, -4.4), Vector3(0.0, 0.55, -1.7)],
	"front34": [Vector3(-3.2, 1.3, -6.5), Vector3(0.2, 0.5, -1.0)],
	"front": [Vector3(0.0, 1.0, -9.5), Vector3(0.0, 0.5, 0.0)],
	"side": [Vector3(-6.0, 1.4, -4.5), Vector3(0.0, 0.2, -6.5)],
	"above": [Vector3(0.0, 4.2, 5.0), Vector3(0.0, 0.0, -11.0)],
}

var out := "user://lamp_shots"
var mode := "touge"
var seed_value := 3
var secs := 6.0
var other_id := "akatsuki"
var glow_id := "kaiser_8"            # (a traffic car's model, its faked light on the road: road_glow)
var settle := 12                     # frames for the game's own camera to settle (llvmpipe: each is slow)
var views: Array = ["mine", "other", "stray", "glow", "traffic"]
var _g
var _cam: Camera3D
var _t0 := 0


func _initialize() -> void:
	_t0 = Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"out": out = kv[1]
			"mode": mode = kv[1]
			"seed": seed_value = int(kv[1])
			"secs": secs = float(kv[1])
			"other": other_id = kv[1]
			"glow": glow_id = kv[1]
			"settle": settle = int(kv[1])
			"views": views = Array(kv[1].split(",", false))
			"before":                                   # (before anything loads them: the old scripts in their place)
				for f in BEFORE:
					if FileAccess.file_exists(kv[1].path_join(f.get_file())):
						var old: Script = load(kv[1].path_join(f.get_file()))
						old.take_over_path("res://scripts/" + f)
						print("[lampshots] %s from %s" % [f, kv[1]])
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _say(what: String) -> void:
	print("[lampshots] %5.0f s  %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, what])


func _save(name: String) -> void:
	var path := out.path_join("%s_%s.png" % [mode, name])
	root.get_viewport().get_texture().get_image().save_png(path)
	_say("saved " + path)


func _run() -> void:
	await process_frame
	if not OS.get_cmdline_user_args().has("--seen_cars_only"):
		push_error("[lampshots] needs --seen_cars_only (no pictures of the no-AI cars)")
		quit(1)
		return
	var mine := str(Profile.setup().get("car", ""))
	if VehicleRegistry.no_ai(mine) or VehicleRegistry.no_ai(other_id) or VehicleRegistry.no_ai(glow_id):
		push_error("[lampshots] --car / --other / --glow: a no-AI car (%s, %s, %s): pick another" % [mine, other_id, glow_id])
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	root.get_node("Net").solo()
	var Modes = load("res://scripts/game/modes.gd")
	var o: Dictionary = {}
	match mode:
		"touge":
			o = Modes.touge_opts(seed_value, "up", "time")
		"cutup":
			o = Modes.cutup_opts(seed_value, "normal")
			o["mood"] = "night"
			o["time"] = 22.0
		"track":
			o = Modes.track_opts(seed_value, "gt", "practice", 5, "cinder_ridge", {"weather": "night"})
	_g = load("res://scripts/game.gd").new()
	root.add_child(_g)
	await _g.start(seed_value, 1, o)
	_say("%s, seed %d, your car %s: built" % [mode, seed_value, mine])
	RenderingServer.render_loop_enabled = false            # (no drawing while it drives: quicker)
	_g.begin_countdown()
	_g.use_autopilot = true
	var t := 0.0
	while (_g.state != "running" or _g.stage_time < secs) and t < 90.0:
		await physics_frame
		t += 1.0 / 120.0
	RenderingServer.render_loop_enabled = true
	_say("driven %.1f s" % t)
	if _g._hud:
		_g._hud.visible = false
	if "mine" in views:
		_g._chase = true
		await _frames(settle)
		_save("mine_chase")
		_g._chase = false
		await _frames(settle)
		_save("mine_seat")
		_g._chase = true
		await _frames(settle)
	# the others round you: another driver's car coming the other way, the stray car further up
	var st = _g.st
	var s: float = _g.car_s
	var lane: float = float(st.LANE_W) * 0.5
	var other
	if "other" in views:
		other = load("res://scripts/vehicle/rally_car.gd").new()
		other.name = "Car_77"
		other.setup = Profile.setup_for(other_id)
		_g.add_child(other)
		other.set_simulating(false)
		other.place(st.world_at(s + 28.0, -lane), float(st.heading_at(s + 28.0)) + PI)
		other.set_outside(true)
		_g._fit_lamps(other)
	if "stray" in views and _g.stray:
		_g.stray.spawn_at(s + 70.0, -1)
	var glow_car: Node3D
	if "glow" in views:                                # (a traffic car as cut up has them, on this road: its light on the road faked)
		for e in VehicleRegistry.traffic_pool():
			if e.id == glow_id:
				var model: Node3D = (load("res://assets/models/cars/%s/%s.glb" % [e.model, e.model]) as PackedScene).instantiate()
				glow_car = Node3D.new()
				glow_car.name = "GlowCar"
				glow_car.add_child(model)
				_g.add_child(glow_car)
				var at: Vector3 = st.world_at(s + 45.0, lane)
				var toward: Vector3 = st.world_at(s + 44.0, lane) - st.world_at(s + 46.0, lane)
				glow_car.global_transform = Transform3D(Basis.looking_at(Vector3(toward.x, 0.0, toward.z).normalized(), Vector3.UP), at)
				load("res://scripts/render/car_look.gd").glow_model(model)
				load("res://scripts/vehicle/car_lamps.gd").road_glow(model)
	await _frames(3)
	if "mine" in views:
		_save("mine_chase_others")
	paused = true                                      # (all held still: the pictures from outside)
	var blur = root.find_child("SpeedBlur", true, false)
	if blur and blur.effect:                           # (held at the car's speed while paused: it would smear the still views)
		blur.effect.enabled = false
	await _frames(1)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 900.0
	root.add_child(_cam)
	_cam.current = true
	if "mine" in views:
		await _round(_g.car, "mine")
	if other:
		await _round(other, "other")
	if "stray" in views and _g.stray and not _g.stray.car.is_empty():
		_say("the stray car: %s" % str(_g.stray.car.model.scene_file_path))
		await _round(_g.stray.car.body, "stray")
	if glow_car:
		await _round(glow_car, "glow")
	if "traffic" in views and _g.traffic:
		var best = null
		var bd := 1e9
		for c in _g.traffic.cars:
			var b: Node3D = c.body
			if VehicleRegistry.no_ai(str(b.get_meta("model_id", ""))):
				continue
			var ahead: float = float(c.s) - s
			if ahead > 8.0 and ahead < bd:
				bd = ahead
				best = b
		if best:
			_say("the traffic car: %s, %.0f m ahead" % [best.get_meta("model_id", ""), bd])
			await _round(best, "traffic")
	await _perf()
	paused = false
	quit(0)


## Each view round a car (its own space).
func _round(car: Node3D, tag: String) -> void:
	for v in VIEWS:
		_cam.global_position = car.global_transform * (VIEWS[v][0] as Vector3)
		_cam.look_at(car.global_transform * (VIEWS[v][1] as Vector3), Vector3.UP)
		await _frames(2)
		_save("%s_%s" % [tag, v])


## What the cars' beams cost to draw: the same held view from behind your car (the others up the
## road), frames timed with every CarLamps beam on, then off, twice. Under xvfb the GPU is the CPU
## (llvmpipe): not a real machine's times, but the two side by side are.
func _perf() -> void:
	var lamps: Array = root.find_children("CarLamps", "Node3D", true, false)
	var spots := 0
	for l in lamps:
		spots += (l._beams as Array).size()
	_cam.global_position = _g.car.global_transform * Vector3(0.0, 1.7, 6.0)
	_cam.look_at(_g.car.global_transform * Vector3(0.0, 0.6, -20.0), Vector3.UP)
	var vp := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var res := {"on": [], "off": []}
	for on in [true, false, true, false]:
		for l in lamps:
			l.set_beam(on)
		await _frames(3)
		var n := 8
		var gpu := 0.0
		var t0 := Time.get_ticks_usec()
		for i in n:
			await process_frame
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp) + RenderingServer.viewport_get_measured_render_time_cpu(vp)
		var wall := (Time.get_ticks_usec() - t0) / 1000.0 / n
		res["on" if on else "off"].append([snappedf(wall, 0.1), snappedf(gpu / n, 0.1)])
	for l in lamps:
		l.set_beam(true)
	_say("perf: %d CarLamps, %d beams; frame ms [wall, render] beams on %s, off %s" % [lamps.size(), spots, str(res.on), str(res.off)])
