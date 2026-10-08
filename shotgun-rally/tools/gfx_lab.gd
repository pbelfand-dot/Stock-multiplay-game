extends SceneTree
## A test bench for the look (scripts/render/): a short piece of road, gravel, grass, a
## rock bank, a barrier, armco, a puddle, a few trees and a car, under a mood's sky, at a
## graphics level; pictures from fixed cameras. Quicker than a whole stage for tuning.
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 1600x900 --fixed-fps 30 \
##     -s tools/gfx_lab.gd -- --out=/tmp/lab --mood=day --gfx=high [--car=raiden] [--views=0,1,2] [--frames=40]
##     [--speed=60] (m/s: the camera and the car drive down the road together: the speed blur as in a game)
## Each view: <out>/lab_<mood>_<level>_<view>.png.
const WorldMaterials = preload("res://scripts/render/world_materials.gd")
const Graphics = preload("res://scripts/render/graphics.gd")
const MeshBuf = preload("res://scripts/stage/mesh_buf.gd")
const StageBuilder = preload("res://scripts/stage/stage_builder.gd")
const Catalog = preload("res://scripts/game/catalog.gd")
const Foliage = preload("res://scripts/render/foliage.gd")

## camera [position, look at] (world: the road runs along -Z, the car at the origin)
const VIEWS := [
	[Vector3(-2.6, 1.5, 6.5), Vector3(0.6, 0.6, -10.0)],      # behind, the road ahead
	[Vector3(3.6, 1.2, -5.5), Vector3(0.0, 0.6, 0.0)],         # the car's front three-quarter
	[Vector3(-7.0, 2.2, -14.0), Vector3(-2.0, 0.3, -2.0)],     # the gravel, the bank, the barrier
	[Vector3(0.0, 0.9, 5.0), Vector3(0.0, 0.7, 0.0)],          # straight behind: the tail lamps
]

var out_dir := "user://lab"
var mood := "day"
var car_id := "raiden"
var views := [0, 1, 2]
var frames := 40
var speed := 0.0
var _cam: Camera3D
var _car


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"out": out_dir = kv[1]
			"mood": mood = kv[1]
			"car": car_id = kv[1]
			"views": views = Array(kv[1].split(",")).map(func(x): return int(x))
			"frames": frames = int(kv[1])
			"speed": speed = float(kv[1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	var world := Node3D.new()
	root.add_child(world)
	WorldMaterials.setup(world, mood)
	_ground(world)
	_road(world)
	_props(world)
	_car = load("res://scripts/vehicle/rally_car.gd").new()
	_car.setup = Catalog.setup(car_id, {}, {}, {"tyre": "tarmac", "preset": "tarmac"})
	world.add_child(_car)
	_car.set_simulating(false)
	_car.set_outside(true)
	_car.place(Vector3(0.0, 0.0, 0.0), 0.0)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 900.0
	world.add_child(_cam)
	_cam.current = true
	_run.call_deferred()


func _run() -> void:
	for v in views:
		var vw: Array = VIEWS[v]
		_cam.global_position = vw[0]
		_cam.look_at(vw[1])
		var start: Vector3 = _car.global_position
		for i in frames:
			await process_frame
			if speed > 0.0:                         # (both down the road: the world streams past)
				var step := Vector3(0.0, 0.0, -speed / 30.0)     # (a frame: run with --fixed-fps 30)
				_cam.global_position += step
				_car.global_position += step
		_car.global_position = start
		var path := "%s/lab_%s_%s_%d.png" % [out_dir, mood, Graphics.level(), v]
		root.get_texture().get_image().save_png(path)
		print("[lab] ", path)
	quit()


## Grass all round (vertex colours as the stage paints them: green, a muddy dip, grey rock).
func _ground(parent: Node3D) -> void:
	var mb := MeshBuf.new()
	var noise := FastNoiseLite.new()
	noise.frequency = 0.04
	var n := 60
	var step := 4.0
	var pts := {}
	for iz in n + 1:
		for ix in n + 1:
			var x := (ix - n / 2) * step
			var z := (iz - n / 2) * step
			var h := 0.0 if absf(x) < 16.0 else noise.get_noise_2d(x, z) * 2.0 + (absf(x) - 16.0) * 0.08
			pts[Vector2i(ix, iz)] = Vector3(x, h - 0.04, z)
	for iz in n:
		for ix in n:
			var a: Vector3 = pts[Vector2i(ix, iz)]
			var col := Color(0.34, 0.54, 0.21).lerp(Color(0.28, 0.46, 0.19), clampf(absf(a.x) / 60.0, 0.0, 1.0))
			col = col * (0.92 + 0.12 * noise.get_noise_2d(a.z * 3.0, a.x * 3.0))
			if a.x > 18.0 and a.x < 30.0 and a.z < -20.0:
				col = col.lerp(Color(0.33, 0.27, 0.2), 0.8)              # a muddy patch
			col.a = 1.0
			mb.quad(a, pts[Vector2i(ix + 1, iz)], pts[Vector2i(ix + 1, iz + 1)], pts[Vector2i(ix, iz + 1)], col)
	_add(parent, mb, "Ground", WorldMaterials.terrain())
	# a cut rock bank on the left of the gravel
	var bank := MeshBuf.new()
	for k in 12:
		var z0 := -k * 6.0 + 30.0
		var z1 := z0 - 6.0
		var c := Color(0.52, 0.49, 0.45) * (0.9 + 0.1 * sin(k * 1.7))
		c.a = 1.0
		bank.quad(Vector3(-13.0, 0.0, z0), Vector3(-13.0, 0.0, z1), Vector3(-16.5, 4.5 + sin(k) * 0.6, z1), Vector3(-16.5, 4.5 + sin(k * 1.3) * 0.6, z0), c)
	_add(parent, bank, "Ground", WorldMaterials.terrain())


## Asphalt (edge lines, a yellow centre) under the car; gravel (two wheel tracks) beside it.
func _road(parent: Node3D) -> void:
	var asphalt := MeshBuf.new()
	var gravel := MeshBuf.new()
	var xs := [-3.8, -3.5, -3.36, -0.07, 0.07, 3.36, 3.5, 3.8]
	for k in 40:
		var z0 := 40.0 - k * 4.0
		var z1 := z0 - 4.0
		for i in xs.size() - 1:
			var col := Color(0.27, 0.27, 0.28)
			if i == 1 or i == 5:
				col = Color(0.9, 0.9, 0.86)
			elif i == 3:
				col = Color(0.95, 0.72, 0.1)
			elif i == 0 or i == 6:
				continue
			asphalt.quad(Vector3(xs[i], 0.0, z0), Vector3(xs[i + 1], 0.0, z0), Vector3(xs[i + 1], 0.0, z1), Vector3(xs[i], 0.0, z1), col)
		var gx := [-12.6, -12.3, -10.75, -10.05, -8.95, -8.25, -6.7, -6.4]
		var gc := [Color(0.5, 0.52, 0.3), Color(0.71, 0.6, 0.44), Color(0.6, 0.5, 0.36), Color(0.71, 0.6, 0.44), Color(0.6, 0.5, 0.36),
			Color(0.71, 0.6, 0.44), Color(0.5, 0.52, 0.3)]
		for i in gx.size() - 1:
			gravel.quad(Vector3(gx[i], 0.02, z0), Vector3(gx[i + 1], 0.02, z0), Vector3(gx[i + 1], 0.02, z1), Vector3(gx[i], 0.02, z1), gc[i])
	_add(parent, asphalt, "Road_asphalt", WorldMaterials.road("asphalt"))
	_add(parent, gravel, "Road", WorldMaterials.road("gravel"))


func _props(parent: Node3D) -> void:
	var sb := StageBuilder.new()
	# a concrete barrier and armco along the right edge
	var barrier := MeshBuf.new()
	var armco := MeshBuf.new()
	for k in 20:
		var z0 := 30.0 - k * 4.0
		var z1 := z0 - 4.0
		sb._box(barrier, Vector3(4.6, 0.14, z0), Vector3(4.6, 0.14, z1), Vector3.RIGHT, 0.62, 0.28, Color(0.68, 0.68, 0.66))
		sb._box(barrier, Vector3(4.6, 0.56, z0), Vector3(4.6, 0.56, z1), Vector3.RIGHT, 0.26, 0.56, Color(0.71, 0.71, 0.69))
		sb._box(armco, Vector3(-6.0, -0.3, z0), Vector3(-6.0, 0.72, z0), Vector3.FORWARD, 0.1, 0.12, Color(0.38, 0.39, 0.41))
		sb._box(armco, Vector3(-5.92, 0.58, z0), Vector3(-5.92, 0.58, z1), Vector3.RIGHT, 0.06, 0.32, Color(0.74, 0.76, 0.78))
	_add(parent, barrier, "ConcreteBarriers", WorldMaterials.concrete({"vertex": "colour"}))
	_add(parent, armco, "Armco", WorldMaterials.steel())
	# street lamps over the asphalt (lit at night)
	var posts := MeshBuf.new()
	var lamps: Array = []
	for k in 4:
		var z := 10.0 - k * 35.0
		sb._box(posts, Vector3(5.6, 0.0, z), Vector3(5.6, 9.0, z), Vector3.FORWARD, 0.18, 0.18, Color(0.55, 0.57, 0.6))
		sb._box(posts, Vector3(5.6, 9.0, z), Vector3(3.2, 9.0, z), Vector3.UP, 0.12, 0.12, Color(0.55, 0.57, 0.6))
		lamps.append({"head": Vector3(3.3, 8.85, z), "ground": Vector3(1.5, 0.0, z), "radius": 11.0})
	_add(parent, posts, "LampPosts", WorldMaterials.steel())
	WorldMaterials.street_lights(parent, lamps)
	# a puddle on the gravel, water in a ditch
	var pud := MeshBuf.new()
	var c := Vector3(-9.5, 0.05, -12.0)
	for k in 9:
		var a0 := TAU * k / 9.0
		var a1 := TAU * (k + 1) / 9.0
		pud.tri(c, c + Vector3(sin(a0) * 0.9, 0, cos(a0) * 1.6), c + Vector3(sin(a1) * 0.9, 0, cos(a1) * 1.6), Color(0.3, 0.22, 0.14))
	_add(parent, pud, "Puddles", WorldMaterials.puddle())
	var water := MeshBuf.new()
	water.quad(Vector3(20.0, -0.3, -10.0), Vector3(40.0, -0.3, -10.0), Vector3(40.0, -0.3, -60.0), Vector3(20.0, -0.3, -60.0), Color(0.13, 0.22, 0.22))
	_add(parent, water, "Stream", WorldMaterials.water())
	# trees beyond the gravel and the barrier
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for kind in ["pine", "round", "birch"]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Foliage.tree_mesh(kind) if Foliage.enabled() else sb._tree_mesh(kind)
		mm.instance_count = 30
		for i in 30:
			var side := -1.0 if i % 2 == 0 else 1.0
			var x := side * rng.randf_range(15.0, 60.0) if side < 0.0 else rng.randf_range(8.0, 18.0)
			var p := Vector3(x, 0.0, rng.randf_range(-120.0, 20.0))
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.5)), p))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = Foliage.material() if Foliage.enabled() else WorldMaterials.foliage()
		parent.add_child(mmi)
	sb.free()


func _add(parent: Node3D, mb, node_name: String, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mb.mesh(WorldMaterials.smooth(node_name))
	mi.material_override = mat
	parent.add_child(mi)
