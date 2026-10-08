extends SceneTree
## Each car's interior from the driver's eye, as the game draws it (the crew, the live
## instruments: dash_live.gd). For checking interiors, the crew's fit and the screens.
## No-AI cars are left out (nobody looks at pictures of them).
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 \
##     -s tools/dash_shots.gd -- --out=/abs/dir --ids=kaiser_4,stromer [--night] [--fake]
##     [--set=kmh:120,rpm:4000] [--page=1] [--look=x,y,z,fov] [--frames=8] [--tag=_a] [--steer=0.5]
##   --fake: made-up readings (124 km/h, near the limiter, 3rd); --set: readings of your own;
##   --page: flip the centre screen n times; --look: look at this point (m from the steering
##   wheel's centre) with this field of view (a close-up), else down the road over the wheel;
##   --steer: the steering turned (-1..1: the wheel and the gloves with it)
## Each car: <out>/dash_<id><_night><tag>.png

const VehicleRegistry = preload("res://scripts/game/vehicle_registry.gd")

var ids: Array = []
var out := "/tmp"
var night := false
var fake := false
var page := 0
var frames := 8
var look := ""
var tag := ""
var steer := 0.0
var sets: Array = []
var _i := -1
var _t := 0
var car
var cp
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"out": out = kv[1]
			"ids": ids = Array(kv[1].split(",", false))
			"night": night = true
			"fake": fake = true
			"page": page = int(kv[1])
			"look": look = kv[1]
			"frames": frames = int(kv[1])
			"tag": tag = kv[1]
			"steer": steer = float(kv[1])
			"set": sets = Array(kv[1].split(",", false))
	DirAccess.make_dir_recursive_absolute(out)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.03, 0.05) if night else Color(0.6, 0.7, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.05, 0.05, 0.07) if night else Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.3 if night else 0.9
	env.environment = e
	root.add_child(env)
	if not night:
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
		sun.light_energy = 1.2
		root.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.02
	cam.cull_mask = 0xFFFFF & ~(1 << 1)              # (not the driver's own helmet: the eye is in it)
	root.add_child(cam)
	cam.current = true


func _process(_dt: float) -> bool:
	if _t > 0:
		_t -= 1
		if car and steer != 0.0:
			car.steer = steer
		if _t == 0:
			var img := root.get_viewport().get_texture().get_image()
			img.save_png("%s/dash_%s%s%s.png" % [out, ids[_i], "_night" if night else "", tag])
			print("[dash] saved ", ids[_i])
			car.queue_free()
			car = null
		return false
	_i += 1
	while _i < ids.size() and VehicleRegistry.no_ai(str(ids[_i])):
		print("[dash] skipped (no-AI): ", ids[_i])
		_i += 1
	if _i >= ids.size():
		return true
	var Catalog = load("res://scripts/game/catalog.gd")
	var st = load("res://scripts/stage/stage_gen.gd").new()
	st.generate(4)
	car = load("res://scripts/vehicle/rally_car.gd").new()
	car.setup = Catalog.setup(ids[_i])
	root.add_child(car)
	car.freeze = true
	car.set_physics_process(false)
	cp = load("res://scripts/vehicle/cockpit.gd").new()
	car.add_child(cp)
	cp.build(car, st)
	cp.set_my_seat("driver")
	if cp.dash:
		cp.dash.night = night
		if fake:
			cp.dash.fake = {"kmh": 124.0, "rpm01": 0.9, "rpm": 6900.0, "gear": 3, "state": "running", "g": Vector2(0.45, -0.3), "time": 83.4, "car_s": 900.0}
		for s in sets:
			var kvp: PackedStringArray = s.split(":")
			cp.dash.fake[kvp[0]] = float(kvp[1])
		for k in page:
			cp.dash.next_page()
		print("[dash] ", ids[_i], " missing: ", cp.dash.missing, " panels: ", cp.dash.panels.size(),
			" needles: ", cp.dash.needle_parts.size(), " pages: ", cp.dash.pages.size())
	if night and "lamps_on" in car:
		car.lamps_on = true
	var eye: Vector3 = car.global_transform * (cp.transform * cp.eye_driver)
	var wheel: Vector3 = car.global_transform * (cp.transform * cp.wheel_c)
	if look != "":
		var p: Array = Array(look.split(",")).map(func(x): return float(x))
		var tgt: Vector3 = car.global_transform * (cp.transform * (cp.wheel_c + Vector3(p[0], p[1], p[2])))
		cam.fov = p[3] if p.size() > 3 else 26.0
		cam.global_transform = Transform3D(Basis(), eye).looking_at(tgt, Vector3.UP)
	else:
		cam.fov = 62.0
		var at := wheel + Vector3(0, 0.06, 0) + (wheel - eye).normalized() * 0.3
		cam.global_transform = Transform3D(Basis(), eye).looking_at(at, Vector3.UP)
	_t = frames
	return false
