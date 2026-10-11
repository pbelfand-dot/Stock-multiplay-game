extends SceneTree
## The CARS grid's tiles (scripts/ui/car_grid.gd): each player car's own 3D model, in its own
## colours, photographed three-quarters from the front in a plain studio (a soft sky, a floor
## that takes its shadow), framed by its own size. One small picture a car:
## assets/ui/cars/<id>.webp (320 x 180). Run it again after a car's model changes.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 640x360 \
##     -s tools/car_thumbs.gd -- [--ids=kaiser_3,gls] [--out=res://assets/ui/cars]
## (The no-AI cars get their tiles too: nobody looks at them; the pictures are the game's.)

const VehicleRegistry = preload("res://scripts/game/vehicle_registry.gd")
const SIZE := Vector2i(320, 180)

var ids: Array = []
var out := "res://assets/ui/cars"
var _i := -1
var _t := 0
var car
var cam: Camera3D
var floor_mi: MeshInstance3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"ids": ids = Array(kv[1].split(",", false))
			"out": out = kv[1]
	if ids.is_empty():
		var Catalog = load("res://scripts/game/catalog.gd")
		for c in Catalog.CARS:
			ids.append(str(c.id))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.21, 0.23)        # (the floor's colour: no horizon line)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.75, 0.8)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var key := DirectionalLight3D.new()                 # (the key light, high and to the left: a shadow under it)
	key.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-35), 0)
	key.light_energy = 1.25
	key.shadow_enabled = true
	root.add_child(key)
	var fill := DirectionalLight3D.new()                # (a soft fill from the other side, no shadow)
	fill.rotation = Vector3(deg_to_rad(-20), deg_to_rad(140), 0)
	fill.light_energy = 0.45
	root.add_child(fill)
	floor_mi = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.2, 0.21, 0.23)
	fm.roughness = 0.85
	floor_mi.material_override = fm
	root.add_child(floor_mi)
	cam = Camera3D.new()
	cam.fov = 30.0
	cam.near = 0.05
	root.add_child(cam)
	cam.current = true
	root.size = SIZE * 2                                # (drawn twice the size, then shrunk: smooth edges)


func _process(_dt: float) -> bool:
	if _t > 0:
		_t -= 1
		if _t == 0:
			var img := root.get_viewport().get_texture().get_image()
			if img.get_size() != SIZE:
				img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
			var path := ProjectSettings.globalize_path("%s/%s.webp" % [out, ids[_i]])
			img.save_webp(path, true, 0.82)
			print("[thumbs] saved ", ids[_i])
			car.queue_free()
			car = null
		return false
	_i += 1
	if _i >= ids.size():
		return true
	var Catalog = load("res://scripts/game/catalog.gd")
	car = load("res://scripts/vehicle/rally_car.gd").new()
	car.setup = Catalog.setup(ids[_i])
	root.add_child(car)
	car.freeze = true
	car.set_physics_process(false)
	car.set_outside(true)                               # (seen from outside: its body, not the cockpit's)
	# its size: every mesh of it, the car's own space
	var box := AABB()
	var first := true
	for mi in car.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.mesh == null or not m3.is_visible_in_tree():
			continue
		var b: AABB = m3.global_transform * m3.get_aabb()
		box = b if first else box.merge(b)
		first = false
	floor_mi.position.y = box.position.y + 0.002
	# three-quarters from the front (the nose is -z), a little above: framed by the box's size
	var c := box.get_center()
	var dir := Vector3(-0.78, 0.36, -1.0).normalized()
	var r := box.size.length() * 0.5
	var dist := r / sin(deg_to_rad(cam.fov * 0.5)) * 0.7
	cam.global_transform = Transform3D(Basis(), c + dir * dist).looking_at(c + Vector3(0, -box.size.y * 0.08, 0), Vector3.UP)
	_t = 6
	return false
