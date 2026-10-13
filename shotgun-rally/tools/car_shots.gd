extends SceneTree
## Pictures of the cars as the game draws them (its lights and sky, the livery
## on the paint): four views of each in one picture (front three-quarter, rear
## three-quarter, the side for the rims, straight behind for the tail lights).
## For looking over the models (tools/model_audit.py checks them by numbers).
## Needs a display (xvfb-run):
##   xvfb-run -a -s "-screen 0 1280x800x24" godot --path . --resolution 1280x800 \
##     -s tools/car_shots.gd -- --out=/tmp/shots [--ids=gtr,elfer_r] [--wait=3]
## Each car: <out>/<registry id>.png. Garage cars are built as the garage builds
## them; traffic-only cars from their model, in their first paint.
const VehicleRegistry = preload("res://scripts/game/vehicle_registry.gd")

const VIEWS := [
	[Vector3(-4.3, 1.45, -5.2), "front 3/4"],
	[Vector3(4.3, 1.45, 5.2), "rear 3/4"],
	[Vector3(6.2, 0.75, 0.0), "side"],
	[Vector3(0.0, 1.05, 6.4), "behind"],
]

## "--set=wheels": each wheel close up from outside instead (FL, FR, RL, RR)
## "--steer=deg": the front wheels turned that far (right +): what turns with them and what doesn't
const WHEEL_VIEWS := [[-1, -1], [1, -1], [-1, 1], [1, 1]]

var out_dir := "user://car_shots"
var view_set := "car"
var wait := 3
var steer_deg := 0.0
var ids: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--ids="):
			ids = Array(a.trim_prefix("--ids=").split(",", false))
		elif a.begins_with("--set="):
			view_set = a.trim_prefix("--set=")
		elif a.begins_with("--wait="):
			wait = int(a.trim_prefix("--wait="))
		elif a.begins_with("--steer="):
			steer_deg = float(a.trim_prefix("--steer="))
	if ids.is_empty():
		for e in VehicleRegistry.all():
			if str(e.get("model", "")) != "":
				ids.append(str(e.id))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_world()
	_run.call_deferred()


func _world() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.55, 0.85)
	sm.sky_horizon_color = Color(0.72, 0.82, 0.9)
	sm.ground_horizon_color = Color(0.6, 0.7, 0.62)
	sm.ground_bottom_color = Color(0.25, 0.35, 0.22)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.5
	env.ambient_light_color = Color(0.62, 0.62, 0.6)
	env.ambient_light_energy = 0.64
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(35.0), 0.0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.8
	sun.directional_shadow_max_distance = 40.0
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.33, 0.33, 0.34)
	gm.roughness = 0.95
	pm.material = gm
	ground.mesh = pm
	root.add_child(ground)


func _car(id: String) -> Node3D:
	var e = VehicleRegistry.entry(id)
	if e.get("garage") is Dictionary:
		var Catalog = load("res://scripts/game/catalog.gd")
		var car = load("res://scripts/vehicle/rally_car.gd").new()
		car.setup = Catalog.setup(id, {}, {}, {"tyre": "tarmac", "preset": "tarmac"})
		root.add_child(car)
		car.park_still()                              # (its wheels at their standing squash, as the garage shows it)
		car.set_outside(true)
		car.place(Vector3.ZERO, 0.0)
		if steer_deg != 0.0:                          # (held: nothing simulated puts it back)
			car.steer = deg_to_rad(steer_deg)
			car._wheel_angles()
		return car
	var m := str(e.get("traffic", {}).get("model", e.model))
	var n: Node3D = (load("res://assets/models/cars/%s/%s.glb" % [m, m]) as PackedScene).instantiate()
	root.add_child(n)
	return n


## The car's outline (its meshes, in the world).
func _box(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).is_visible_in_tree():
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _run() -> void:
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.current = true
	for id in ids:
		var car := _car(id)
		for f in 4:
			await process_frame
		var shots: Array[Image] = []
		var views: Array = []
		if view_set == "wheels":
			var box := _box(car)
			for wv in WHEEL_VIEWS:
				var at := Vector3(wv[0] * box.size.x * 0.42, 0.35, wv[1] * box.size.z * 0.3)
				views.append([at + Vector3(wv[0] * 2.4, 0.25, wv[1] * -0.6), at])
		else:
			for v in VIEWS:
				views.append([v[0], Vector3(0, 0.62, 0)])
		for v in views:
			cam.look_at_from_position(v[0], v[1], Vector3.UP)
			for f in wait:
				await process_frame
			await RenderingServer.frame_post_draw
			shots.append(root.get_texture().get_image())
		var w := shots[0].get_width()
		var h := shots[0].get_height()
		var sheet := Image.create(w, h, false, shots[0].get_format())
		var hw := w / 2
		var hh := h / 2
		for k in 4:
			var s := shots[k]
			s.resize(hw, hh, Image.INTERPOLATE_BILINEAR)
			sheet.blit_rect(s, Rect2i(0, 0, hw, hh), Vector2i((k % 2) * hw, (k / 2) * hh))
		sheet.save_png(out_dir.path_join(id + ("_wheels" if view_set == "wheels" else "") + ("_steer" if steer_deg != 0.0 else "") + ".png"))
		print("[shots] %s" % id)
		car.queue_free()
		await process_frame
	quit(0)
