extends SceneTree
## A contact sheet of the wheel library: every preset built by WheelPresets (as on a 0.33 m
## radius, 0.25 m wide corner) and every converted CC0 wheel (assets/wheels/), three-quarter
## view of the face, labelled. Run under a display:
##   xvfb-run godot --path . --resolution 1600x900 -s tools/wheel_sheet.gd -- --out=sheet.png [--back]
## (--back: from inside the car: the brakes and the barrel)

const WheelPresets = preload("res://scripts/vehicle/wheel_presets.gd")


func _initialize() -> void:
	var out := "user://wheel_sheet.png"
	var back := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		if a == "--back":
			back = true
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.22, 0.25)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.57, 0.6)
	env.environment.ambient_light_energy = 0.7
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.9, 0.0)
	sun.light_energy = 1.3
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.3, -2.2, 0.0)
	fill.light_energy = 0.5
	world.add_child(fill)
	var parts := {"radius": [0.33, 0.33, 0.33, 0.33], "width": [0.25, 0.25, 0.25, 0.25],
		"wheels": [[0.8, 0.33, -1.2], [0.8, 0.33, -1.2], [0.8, 0.33, 1.2], [0.8, 0.33, 1.2]]}
	var items: Array = []
	for id in WheelPresets.ids():
		if id == "stock":
			continue
		items.append(["preset", id])
	var d := DirAccess.open("res://assets/wheels")
	for w in d.get_directories():
		items.append(["mesh", w])
	var cols := 6
	var gap := 0.95
	for i in items.size():
		var it: Array = items[i]
		var holder := Node3D.new()
		holder.position = Vector3((i % cols) * gap, -(i / cols) * gap, 0.0)
		world.add_child(holder)
		var label := Label3D.new()
		label.text = str(it[1])
		label.font_size = 40
		label.pixel_size = 0.0016
		label.position = Vector3(0, -0.42, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		holder.add_child(label)
		var spin := Node3D.new()
		spin.rotation.y = (-0.6 if not back else 2.5)          # (the face, +x, turned towards the camera)
		holder.add_child(spin)
		if it[0] == "preset":
			var f := WheelPresets.fit(str(it[1]), parts, 1)
			var asm := WheelPresets.assemble(str(it[1]), f)
			spin.add_child(asm.spin)
			spin.add_child(asm.fixed)
		else:
			var sc: PackedScene = load("res://assets/wheels/%s/%s.glb" % [it[1], it[1]])
			var info = JSON.parse_string(FileAccess.get_file_as_string("res://assets/wheels/%s/wheel.json" % it[1]))
			var n: Node3D = sc.instantiate()
			var s := 0.66 / float(info.diameter)
			n.scale = Vector3(s, s, s)
			spin.add_child(n)
	var cam := Camera3D.new()
	var rows := ceili(items.size() / float(cols))
	cam.position = Vector3((cols - 1) * gap * 0.5, -(rows - 1) * gap * 0.5, 5.6)
	cam.fov = 40.0
	world.add_child(cam)
	cam.make_current()
	for k in 8:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out)
	print("[sheet] saved ", out, " (", items.size(), " wheels)")
	quit(0)
