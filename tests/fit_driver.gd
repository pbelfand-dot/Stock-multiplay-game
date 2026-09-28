extends Node3D
## Close-up renders of clothing fit (shoulders, chain, accessories):
##   godot --path . -- --fit=/tmp/out

const Character = preload("res://scripts/art/character.gd")


func _ready() -> void:
	var out: String = Config.cli.get("fit", "user://fit")
	DirAccess.make_dir_recursive_absolute(out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.52, 0.58)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 0.97, 0.94)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 20, 0)
	sun.light_energy = 0.8
	add_child(sun)
	var looks := [
		{"outfit": "suit", "chain": true, "watch": "gold"},
		{"outfit": "tee", "chain": true, "suit": Color(0.95, 0.95, 0.95)},
		{"outfit": "hoodie", "chain": true, "suit": Color(0.8, 0.55, 0.1)},
		{"outfit": "shirt", "chain": true, "suit": Color(0.95, 0.95, 0.96)},
		{"outfit": "cop", "suit": Color(0.2, 0.36, 0.78), "hat": "police"},
	]
	for i in looks.size():
		var c := Character.new()
		c.build(looks[i])
		c.position = Vector3(-2.0 + i * 1.0, 0, 0)
		c.rotation.y = PI
		add_child(c)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	for f in 10:
		await get_tree().process_frame
	var shots := [["front", Vector3(0, 1.3, 3.2), Vector3(0, 1.25, 0), 34.0],
		["side", Vector3(3.4, 1.35, 1.2), Vector3(-0.2, 1.25, 0), 40.0],
		["close_suit", Vector3(-2.0, 1.4, 0.95), Vector3(-2.0, 1.35, 0), 40.0],
		["close_tee", Vector3(-1.0, 1.4, 0.95), Vector3(-1.0, 1.35, 0), 40.0],
		["close_hoodie", Vector3(0.0, 1.4, 0.95), Vector3(0.0, 1.35, 0), 40.0],
		["back", Vector3(0, 1.35, -3.2), Vector3(0, 1.25, 0), 34.0],
		["hoodie_waist", Vector3(0.3, 1.0, 1.1), Vector3(0.0, 0.95, 0), 40.0]]
	for s in shots:
		cam.position = s[1]
		cam.look_at(s[2])
		cam.fov = s[3]
		for f in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, s[0]])
		print("fit: ", s[0])
	get_tree().quit()
