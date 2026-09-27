extends Node3D
## Renders a character lineup for visual checks (needs a display / xvfb):
##   godot --path . -- --lineup=/tmp/out

const Character = preload("res://scripts/art/character.gd")

var out := ""


func _ready() -> void:
	out = Config.cli.get("lineup", "user://lineup")
	DirAccess.make_dir_recursive_absolute(out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.52, 0.58)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 0.97, 0.94)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.38, 0.45)
	floor_mi.material_override = fm
	add_child(floor_mi)
	var specs := [
		["trader", "smoke"], ["cop", "aim"], ["flex", "hold"], ["beard", "idle"],
		["tramp", "cheer"], ["tjz", "idle"], ["kimchee", "idle"], ["kitteh", "idle"], ["crammer", "idle"],
	]
	var i := 0
	for sp in specs:
		var c := Character.new()
		c.build(Character.preset(sp[0]))
		c.pose = sp[1]
		c.position = Vector3(-4.0 + i * 1.0, 0, 0)
		c.rotation.y = PI  # face the camera (+Z)
		add_child(c)
		i += 1
	_run.call_deferred()


func _snap(cam_pos: Vector3, look: Vector3, fov: float, file: String) -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = cam_pos
	cam.fov = fov
	cam.look_at(look)
	cam.current = true
	for k in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + file + ".png")
	print("lineup: ", file)
	cam.queue_free()


func _run() -> void:
	await _snap(Vector3(0, 1.2, 6.0), Vector3(0, 0.95, 0), 60, "full")
	await _snap(Vector3(-4.0, 1.62, 0.9), Vector3(-4.0, 1.6, 0), 40, "face_trader")
	await _snap(Vector3(-3.0, 1.62, 0.9), Vector3(-3.0, 1.6, 0), 40, "face_cop")
	await _snap(Vector3(-2.0, 1.62, 0.9), Vector3(-2.0, 1.6, 0), 40, "face_flex")
	await _snap(Vector3(0.0, 1.62, 0.9), Vector3(0.0, 1.6, 0), 40, "face_tramp")
	await _snap(Vector3(-3.6, 1.3, 2.3), Vector3(-3.5, 1.1, 0), 45, "trader_cop_mid")
	await _snap(Vector3(-5.5, 1.4, 1.2), Vector3(-4.0, 1.2, 0), 45, "trader_side")
	Sfx.quit_game()
