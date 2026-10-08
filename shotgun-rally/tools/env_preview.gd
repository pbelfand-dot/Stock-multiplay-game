extends SceneTree
## A picture of an environment GLB's parts side by side in the game's light (for checking a
## conversion): godot --path . -s tools/env_preview.gd -- --glb=res://path.glb --out=/abs/out.png
##   [--filter=TEXT] (only parts whose name has it) [--gap=M] [--mood=day|golden|night]
##   [--dist=M] (camera distance; default fits) [--height=M] (camera height)
##   [--cut=A] (the leaves' alpha cut, as a species' "leaf_cut")
## Run under xvfb (a real renderer), not --headless.

var _frames := 0
var _out := ""


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	_out = args.get("out", "/tmp/env_preview.png")
	var WorldMaterials = load("res://scripts/render/world_materials.gd")
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	WorldMaterials.setup(root3d, args.get("mood", "day"))
	var scene: Node = (load(args.get("glb", "")) as PackedScene).instantiate()
	var parts: Array = []
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		if args.get("filter", "") == "" or String(n.name).contains(args.get("filter", "")):
			parts.append(n)
	parts.sort_custom(func(a, b): return String(a.name) < String(b.name))
	var gap := float(args.get("gap", "0"))
	var x := 0.0
	var tallest := 1.0
	var EnvAssets = load("res://scripts/stage/env_assets.gd")
	for n in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = (n as MeshInstance3D).mesh
		if args.get("foliage", "1") == "1" and (String(n.name).contains("_LOD") or String(n.name).ends_with("_BB")):
			mi.mesh = mi.mesh.duplicate()
			for i in mi.mesh.get_surface_count():
				var sm = mi.mesh.surface_get_material(i)
				if sm is BaseMaterial3D:
					mi.mesh.surface_set_material(i, EnvAssets.foliage(sm, String(n.name).ends_with("_BB"), Color.WHITE, float(args.get("cut", "0.42")))
						if (sm as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else EnvAssets.bark(sm))
		var aabb := mi.mesh.get_aabb()
		var w := maxf(aabb.size.x, aabb.size.z)
		var step := gap if gap > 0.0 else w * 1.15
		mi.position = Vector3(x + step * 0.5, 0, 0)
		x += step
		tallest = maxf(tallest, aabb.size.y)
		root3d.add_child(mi)
		print("[preview] %s: %d surfaces, %.1f x %.1f x %.1f m" % [n.name, mi.mesh.get_surface_count(), aabb.size.x, aabb.size.y, aabb.size.z])
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(x + 200.0, 200.0)
	ground.mesh = pm
	ground.material_override = WorldMaterials.grass()
	ground.position = Vector3(x * 0.5, 0, 0)
	root3d.add_child(ground)
	var cam := Camera3D.new()
	root3d.add_child(cam)
	var span := maxf(x, tallest * 1.6)
	var dist := float(args.get("dist", str(span * 0.95 + 4.0)))
	if args.get("side", "") == "back":
		dist = -dist
	cam.look_at_from_position(Vector3(x * 0.5, float(args.get("height", str(tallest * 0.45))), dist),
		Vector3(x * 0.5, tallest * 0.42, 0), Vector3.UP)
	cam.fov = 55.0
	cam.far = 4000.0
	cam.make_current()


func _process(_dt: float) -> bool:
	_frames += 1
	if _frames == 12:
		get_root().get_viewport().get_texture().get_image().save_png(_out)
		print("[preview] saved %s" % _out)
		quit(0)
	return false
