extends SceneTree
## Pictures of CINDER RIDGE without the game: builds the circuit (CircuitGen + CircuitBuilder) and
## shoots its pits and trackside from fixed spots (the pit crews' kit, the marshal posts, the noses
## of the pit lane, the paddock garages; a road-level view down the pit straight).
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 \
##     -s tools/circuit_shots.gd -- --out=/tmp/circuit [--mood=night] [--gfx=high]
const CircuitGen = preload("res://scripts/stage/circuit_gen.gd")
const CircuitBuilder = preload("res://scripts/stage/circuit_builder.gd")
const Modes = preload("res://scripts/game/modes.gd")

var out_dir := "user://circuit_shots"
var mood := "day"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--mood="):
			mood = a.trim_prefix("--mood=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var st = CircuitGen.new()
	st.opts = Modes.track_opts(1).gen
	st.generate(1)
	var b = CircuitBuilder.new()
	b.mood = mood
	root.add_child(b)
	b.build(st)
	print("[circuit] built in %.1f s: %d nodes, %d marshal posts" % [(Time.get_ticks_msec() - t0) / 1000.0, b.get_child_count(), b.marshal_count])
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 6000.0
	root.add_child(cam)
	cam.current = true
	var p: Dictionary = st.pit
	var box: Vector2 = st.box_sd(6)
	var span := (float(p.s_box1) - float(p.s_box0)) / float(p.boxes)
	var views := [
		["pits_boxes", st.world_at(box.x - 18.0, float(p.fast_d)) + Vector3.UP * 2.2, st.world_at(box.x + span, float(p.box_d) + 1.0) + Vector3.UP * 0.6],
		["pits_wall", st.world_at(box.x - 14.0, float(p.lane_d0) + 2.0) + Vector3.UP * 1.6, st.world_at(box.x + 4.0, float(p.wall_d)) + Vector3.UP * 0.8],
		["pits_high", st.world_at(box.x - 30.0, float(p.wall_d) - 6.0) + Vector3.UP * 14.0, st.world_at(box.x + 10.0, float(p.box_d)) + Vector3.UP * 0.5],
		["pit_entry_nose", st.world_at(float(p.s_in1) - 45.0, 2.0) + Vector3.UP * 1.4, st.world_at(float(p.s_in1), (st.half_at(float(p.s_in1)) + float(p.lane_d0)) * 0.5) + Vector3.UP * 0.5],
		["paddock", st.world_at(box.x - 40.0, float(p.garage_d) + 20.0) + Vector3.UP * 30.0, st.world_at(box.x + 20.0, float(p.garage_d) + 25.0)],
	]
	for m in st.marshals.slice(0, 2):
		var s := float(m.s)
		var side := int(m.side)
		views.append(["marshal_%d" % int(s), st.world_at(s - 25.0, -side * 2.0) + Vector3.UP * 1.4, st.world_at(s, side * (st.half_at(s) + 8.0)) + Vector3.UP * 1.5])
	for v in views:
		cam.look_at_from_position(v[1], v[2], Vector3.UP)
		await _shot("%s_%s" % [v[0], mood])
	quit(0)


func _shot(name: String) -> void:
	for f in 6:
		await process_frame
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	img.save_png(path)
	print("[circuit] saved %s" % path)
