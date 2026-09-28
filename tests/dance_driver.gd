extends Node3D
## Renders the rotoscoped dance at given times, to compare with the source clip:
##   godot --path . -- --dancecheck=/tmp/out [--times=0.5,1.2,...]

const Character = preload("res://scripts/art/character.gd")

var c
var hold := 0.0


func _ready() -> void:
	var out: String = Config.cli.get("dancecheck", "user://dance")
	DirAccess.make_dir_recursive_absolute(out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.82, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 0.97, 0.94)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 20, 0)
	sun.light_energy = 0.8
	add_child(sun)
	c = Character.new()
	c.build({"outfit": "tee", "suit": Color(0.08, 0.08, 0.09), "pants": Color(0.75, 0.75, 0.73), "hair_style": "messy",
			"hair": Color(0.12, 0.08, 0.06), "glasses": "specs"})
	c.rotation.y = PI            # face the camera, like the phone in the clip
	c.pose = "dance"
	add_child(c)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.position = Vector3(0, 1.0, 4.6)
	cam.look_at(Vector3(0, 0.95, 0))
	cam.current = true
	var times := []
	for s in str(Config.cli.get("times", "0.4,1.2,2.0,2.8,4.4,4.8,5.2,5.6,6.0,8.8,9.2,10.8")).split(","):
		times.append(float(s))
	for tt in times:
		hold = tt
		for i in 30:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/dance_%05.2f.png" % [out, tt])
	get_tree().quit()


func _process(delta: float) -> void:
	if c:
		c.anim_t = hold - delta     # freeze the clip at `hold`
