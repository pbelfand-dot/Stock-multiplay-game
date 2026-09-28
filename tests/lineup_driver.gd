extends Node3D
## Renders a character lineup for visual checks (needs a display / xvfb):
##   godot --path . -- --lineup=/tmp/out
## Hair close-ups (every style from the front, 3/4, side and back, plus hats):
##   godot --path . -- --lineup=/tmp/out --hair

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
	if Config.cli.has("hair"):
		_hair_lineup()
		return
	var specs := [
		["trader", "finger"], ["cop", "aim"], ["flex", "watch"], ["beard", "idle"],
		["tramp", "fistpump"], ["tjz", "sit"], ["kimchee", "point"], ["kitteh", "idle"], ["crammer", "dunk"],
	]
	var i := 0
	for sp in specs:
		var c := Character.new()
		c.build(Character.preset(sp[0]))
		c.pose = sp[1]
		c.position = Vector3(-4.0 + i * 1.0, 0, 0)
		c.rotation.y = PI  # face the camera (+Z)
		if sp[0] == "beard":
			c.move_speed = 4.5
		if sp[0] == "kitteh":
			c.move_speed = 7.5
		add_child(c)
		i += 1
	# second row: every hair style + beard + hat on the default trader
	var styles: Array = Character.OPTIONS.hair_style
	var beards := ["none", "mustache", "goatee", "full", "stubble", "none", "none", "none", "none"]
	var hats := ["none", "none", "none", "none", "none", "headset", "beanie", "cap", "headband"]
	for k in styles.size():
		var c2 := Character.new()
		c2.build({"hair_style": styles[k], "beard": beards[k], "hat": hats[k],
			"hair": Character.HAIR_COLORS[k % Character.HAIR_COLORS.size()],
			"skin": Character.SKIN_TONES[k % Character.SKIN_TONES.size()]})
		c2.position = Vector3(-4.0 + k * 1.0, 0, -4.0)
		c2.rotation.y = PI
		add_child(c2)
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
	await _snap(Vector3(-2.2, 1.3, 3.2), Vector3(-2.2, 1.0, 0), 50, "mid_left")
	await _snap(Vector3(2.0, 1.3, 3.2), Vector3(2.0, 1.0, 0), 50, "mid_right")
	await _snap(Vector3(-4.0, 1.62, 0.9), Vector3(-4.0, 1.6, 0), 40, "face_trader")
	await _snap(Vector3(-3.0, 1.62, 0.9), Vector3(-3.0, 1.6, 0), 40, "face_cop")
	await _snap(Vector3(-2.0, 1.62, 0.9), Vector3(-2.0, 1.6, 0), 40, "face_flex")
	await _snap(Vector3(0.0, 1.62, 0.9), Vector3(0.0, 1.6, 0), 40, "face_tramp")
	await _snap(Vector3(-3.6, 1.3, 2.3), Vector3(-3.5, 1.1, 0), 45, "trader_cop_mid")
	await _snap(Vector3(-5.5, 1.4, 1.2), Vector3(-4.0, 1.2, 0), 45, "trader_side")
	await _snap(Vector3(-2.5, 1.75, -1.2), Vector3(-2.5, 1.72, -4.0), 38, "hair_row_a")
	await _snap(Vector3(1.5, 1.75, -1.2), Vector3(1.5, 1.72, -4.0), 38, "hair_row_b")
	await _snap(Vector3(-4.6, 1.8, -3.0), Vector3(-4.0, 1.75, -4.0), 40, "hair_side")
	Sfx.quit_game()


# ------------------------------------------------------------------ hair close-ups

const HAIR_VIEWS := [0.0, -PI / 4.0, -PI / 2.0, PI]   # front, 3/4, side, back
const HAIR_TINT := Color(0.42, 0.27, 0.15)


func _head_row(z: float, looks: Array) -> void:
	for k in looks.size():
		var c := Character.new()
		c.build(looks[k])
		c.position = Vector3(-0.69 + k * 0.46, 0, z)
		c.rotation.y = PI + HAIR_VIEWS[k % HAIR_VIEWS.size()]
		add_child(c)


func _hair_lineup() -> void:
	var styles: Array = Character.OPTIONS.hair_style
	for i in styles.size():
		var look := {"hair_style": styles[i], "beard": "none", "hat": "none", "hair": HAIR_TINT}
		_head_row(-i * 6.0, [look, look, look, look])
	# hats over hair: the styles hats keep (short, buzz, bald), and big hair under a headband/headset
	var hat_rows := [
		[["short", "cap"], ["short", "beanie"], ["buzz", "bowler"], ["bald", "bucket"]],
		[["afro", "headband"], ["long", "headband"], ["messy", "headset"], ["swoop", "headset"]],
		[["slick", "cap"], ["short", "police"], ["short", "cop"], ["swept", "headband"]],
	]
	for r in hat_rows.size():
		var looks := []
		for hs in hat_rows[r]:
			looks.append({"hair_style": hs[0], "hat": hs[1], "beard": "none", "hair": HAIR_TINT})
		_head_row(-(styles.size() + r) * 6.0, looks)
	_run_hair.call_deferred(styles)


func _run_hair(styles: Array) -> void:
	for i in styles.size():
		await _snap_ortho(-i * 6.0, "hair_" + styles[i])
	for r in 3:
		await _snap_ortho(-(styles.size() + r) * 6.0, "hats_%d" % r)
	Sfx.quit_game()


func _snap_ortho(z: float, file: String) -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.95
	cam.far = 5.0
	cam.position = Vector3(0, 1.67, z + 3.0)
	cam.look_at(Vector3(0, 1.67, z))
	cam.current = true
	for k in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + file + ".png")
	print("lineup: ", file)
	cam.queue_free()
