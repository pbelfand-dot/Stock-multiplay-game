extends SceneTree
## Pictures of the LAKESHORE LOOP without the game: builds the map (LoopGen +
## LoopBuilder) and shoots it from the road and from the air.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 \
##     -s tools/loop_shots.gd -- --out=/tmp/loop [--at=1200,15000] [--air] [--mood=golden]
## --at: the s of each road-level shot (a car's eye view down the road, 1.3 m up in
## the second lane); default: one in each stretch and structure. --air: also views
## from above. Prints the build's time and size.
const LoopGen = preload("res://scripts/stage/loop_gen.gd")
const LoopBuilder = preload("res://scripts/stage/loop_builder.gd")

var out_dir := "user://loop_shots"
var at: Array = []
var air := false
var mood := "day"
var build_only := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--at="):
			for v in a.trim_prefix("--at=").split(",", false):
				at.append(float(v))
		elif a == "--build-only":
			build_only = true
		elif a == "--air":
			air = true
		elif a.begins_with("--mood="):
			mood = a.trim_prefix("--mood=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var st = LoopGen.new()
	st.generate(1)
	var b = LoopBuilder.new()
	b.mood = mood
	root.add_child(b)
	b.build(st)
	print("[loop] built in %.1f s: %d nodes" % [(Time.get_ticks_msec() - t0) / 1000.0, b.get_child_count()])
	if build_only:
		quit(0)
		return
	if at.is_empty():
		var picks := [300.0]
		for sp in st.spans:
			picks.append(float(sp.s0) - 250.0)
			picks.append((float(sp.towers[0]) + float(sp.towers[1])) * 0.5)
		for t in st.tunnels:
			picks.append(float(t.s0) - 120.0)
			picks.append((float(t.s0) + float(t.s1)) * 0.5)
		for z in st.zones:
			picks.append((float(z.s0) + float(z.s1)) * 0.5)
		for r in st.ramps.slice(0, 2):
			picks.append(float(r.s) - 150.0)
		at = picks
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 12000.0
	root.add_child(cam)
	cam.current = true
	var k := 0
	for s in at:
		var eye: Vector3 = st.world_at(s, 1.8) + Vector3.UP * 1.3
		var look: Vector3 = st.world_at(s + 60.0, 1.8) + Vector3.UP * 1.0
		cam.look_at_from_position(eye, look, Vector3.UP)
		await _shot("road_%02d_s%d" % [k, int(s)])
		k += 1
	if air:
		for s in [0.0, st.length * 0.25, st.length * 0.5, st.length * 0.7]:
			var p: Vector3 = st.world_at(s, 0.0)
			var r: Vector3 = st.right_at(s)
			cam.look_at_from_position(p + r * 600.0 + Vector3.UP * 350.0, p + st.forward_at(s) * 300.0, Vector3.UP)
			await _shot("air_s%d" % int(s))
	quit(0)


func _shot(name: String) -> void:
	for f in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("[loop] %s" % name)
