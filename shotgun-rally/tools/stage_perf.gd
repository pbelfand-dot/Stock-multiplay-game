extends SceneTree
## What a stage costs to draw: builds it at a graphics level and looks down the road from
## a driver's eye at a few places, printing what the renderer drew there (objects, draw
## calls, triangles), the memory used and how long the build took; a picture of each view.
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 1600x900 -s tools/stage_perf.gd -- \
##     --out=/abs/dir [--opts={"kind":"touge","dir":"down"}] [--seed=5] [--len=2400] [--gfx=medium]
##     [--loop] (the highway loop instead of a stage) [--at=300,900,1500] [--mood=day] [--frames=3]
##     [--no_skyline] (the loop's city without its far tier: scripts/stage/city_skyline.gd)
## One "[perf]" line a view (JSON), then a summary line. Under xvfb the GPU is the CPU
## (llvmpipe): the frame times aren't a real machine's, the counts are.

const Graphics = preload("res://scripts/render/graphics.gd")
const EnvAssets = preload("res://scripts/stage/env_assets.gd")

var out_dir := "/tmp/stage_perf"
var opts := {}
var seed_v := 5
var length := 2400.0
var gfx := "medium"
var loop := false
var at: Array = []
var mood := "day"
var frames := 3                      # frames to settle at each view, then as many measured (llvmpipe: each is slow)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"out": out_dir = kv[1]
			"opts": opts = JSON.parse_string(kv[1])
			"seed": seed_v = int(kv[1])
			"len": length = float(kv[1])
			"gfx": gfx = kv[1]
			"loop": loop = true
			"mood": mood = kv[1]
			"frames": frames = int(kv[1])
			"at":
				for v in kv[1].split(",", false):
					at.append(float(v))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _run() -> void:
	Graphics.set_level(gfx)
	EnvAssets.clear_cache()
	var t0 := Time.get_ticks_msec()
	var st
	var b
	if loop:
		st = load("res://scripts/stage/loop_gen.gd").new()
		st.opts = opts
		st.generate(seed_v)
		b = load("res://scripts/stage/loop_builder.gd").new()
	else:
		st = load("res://scripts/stage/stage_gen.gd").new()
		st.opts = opts
		st.generate(seed_v, length)
		b = load("res://scripts/stage/stage_builder.gd").new()
	b.mood = mood
	root.add_child(b)
	b.build(st)
	var build_ms := Time.get_ticks_msec() - t0
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.make_current()
	if at.is_empty():
		var end: float = st.length if loop else st.finish_s
		for k in 4:
			at.append(lerpf(st.START_S + 60.0, end - 80.0, (k + 0.5) / 4.0))
	var vp := root.get_viewport()
	var rid := vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var rows: Array = []
	for s in at:
		var d: float = 1.8 if loop else 0.0
		var p: Vector3 = st.world_at(s, d) + Vector3.UP * 1.3
		var ahead: Vector3 = st.world_at(s + 30.0, d) + Vector3.UP * 1.1
		cam.look_at_from_position(p, ahead, Vector3.UP)
		await _frames(frames)
		var cpu := 0.0
		var gpu := 0.0
		for k in frames:
			await process_frame
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		var row := {"s": int(s),
			"objects": vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
			"draw_calls": vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			"triangles": vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
			"shadow_draw_calls": vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			"shadow_triangles": vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
			"cpu_ms": snappedf(cpu / frames, 0.01), "gpu_ms": snappedf(gpu / frames, 0.01)}
		row["groups"] = _groups(b, cam.global_position)
		rows.append(row)
		print("[perf] ", JSON.stringify(row))
		vp.get_texture().get_image().save_png("%s/%s_%s_%d.png" % [out_dir, "loop" if loop else str(st.kind), gfx, int(s)])
	var sum := {"build_s": snappedf(build_ms / 1000.0, 0.01), "gfx": gfx,
		"video_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"texture_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"buffer_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / 1048576.0, 0.1),
		"static_mem_mb": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1),
		"nodes": b.get_child_count(),
		"max_triangles": rows.map(func(r): return r.triangles).max(),
		"max_draw_calls": rows.map(func(r): return r.draw_calls).max()}
	print("[perf] SUMMARY ", JSON.stringify(sum))
	quit(0)


## Which groups of instances are in range from here (their visibility ranges, from the
## middle of their box): counted by what they are (a tree group's LOD, the far cards, the
## rest), with their instances.
func _groups(b: Node, eye: Vector3) -> Dictionary:
	var out := {}
	for n in b.get_children():
		if not n is MultiMeshInstance3D:
			continue
		var mmi := n as MultiMeshInstance3D
		var aabb: AABB = mmi.get_aabb()
		var dist := eye.distance_to(mmi.global_transform * aabb.get_center())
		if dist < mmi.visibility_range_begin or (mmi.visibility_range_end > 0.0 and dist > mmi.visibility_range_end):
			continue
		var nm := String(mmi.name)
		var kind := "other"
		if nm.begins_with("TreesN_"):
			kind = "near_" + nm.substr(nm.length() - 1)
		elif nm.begins_with("TreesF_"):
			kind = "far_card"
		elif nm.begins_with("Trees_"):
			kind = "cone_trees"
		elif nm.begins_with("Boulders"):
			kind = "boulders"
		if not out.has(kind):
			out[kind] = [0, 0]
		out[kind][0] += 1
		out[kind][1] += mmi.multimesh.instance_count if mmi.multimesh else 0
	return out
