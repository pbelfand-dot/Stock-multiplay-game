extends Node3D
## Renders a character lineup for visual checks (needs a display / xvfb):
##   godot --path . -- --lineup=/tmp/out
## Hair close-ups (every style from the front, 3/4, side and back, plus hats):
##   godot --path . -- --lineup=/tmp/out --hair
## One portrait per haircut (portrait_<style>.png, 800x800):
##   godot --path . -- --lineup=/tmp/out --hairportraits

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
	if Config.cli.has("hairportraits"):
		_hairportraits(env)
		return
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
	if Config.cli.has("hairgif"):
		_hairgif()
		return
	if Config.cli.has("hairmotion"):
		_hairmotion()
		return
	if Config.cli.has("hairturn"):
		_hairturn_lineup()
		return
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
	if DisplayServer.get_name() == "headless":      # the hair motion check also runs headless (no pictures)
		for k in 2:
			await get_tree().process_frame
		return
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


# ------------------------------------------------------------------ long hair vs. head turns
## Long hair with the head turned / tilted: the ends must stay off the
## shoulders (they ride the chest, the top rides the head).
##   godot --path . -- --lineup=/tmp/out --hairturn
const TURNS := [Vector3(0, 0.85, 0), Vector3(0, -0.85, 0), Vector3(0.55, 0, 0), Vector3(-0.35, 0.6, 0)]


func _hairturn_lineup() -> void:
	var chars: Array = []
	for row in 2:                                  # row 0 seen from the front, row 1 from behind
		for k in TURNS.size():
			var c := Character.new()
			c.build({"hair_style": "long", "beard": "none", "hat": "none", "hair": HAIR_TINT})
			c.position = Vector3(-0.69 + k * 0.46, 0, -row * 6.0)
			c.rotation.y = PI if row == 0 else 0.0
			add_child(c)
			chars.append(c)
	_run_hairturn.call_deferred(chars)


func _run_hairturn(chars: Array) -> void:
	for k in 10:
		await get_tree().process_frame
	for i in chars.size():
		var c = chars[i]
		c.set_process(false)                       # hold the pose
		c._pose_bone("Head", TURNS[i % TURNS.size()], 1.0)
	await _snap_ortho(0.0, "hairturn_front")
	await _snap_ortho(-6.0, "hairturn_back")
	Sfx.quit_game()


# ------------------------------------------------------------------ hair motion (spring bones)
## Stand still, then snap-turn 70 degrees and walk: long hair must swing
## (lag + overshoot) and settle back; big hair bobs a little.
##   godot --path . -- --lineup=/tmp/out --hairmotion
func _hairmotion() -> void:
	var chars: Array = []
	for k in 4:
		var c := Character.new()
		c.build({"hair_style": ["long", "afro", "messy", "swoop"][k], "beard": "none", "hat": "none", "hair": HAIR_TINT})
		c.position = Vector3(-0.69 + k * 0.46, 0, 0)
		c.rotation.y = PI / 2.0 + PI            # side-on to the camera: swing reads best from the side
		add_child(c)
		chars.append(c)
	_run_hairmotion.call_deferred(chars)


func _sway_angle(c) -> float:
	var i: int = c._bi.get("HairSway" if c.look.get("hair_style", "") == "long" else "HairBounce", -1)
	if i < 0:
		return -1.0
	return c._rest_q[i].angle_to(c.skel.get_bone_pose_rotation(i))


func _run_hairmotion(chars: Array) -> void:
	for k in 60:
		await get_tree().process_frame
	var still := []
	for c in chars:
		still.append(_sway_angle(c))
	await _snap_ortho(0.0, "hairmotion_0_still")
	# snap turn + walk off
	var peak := [0.0, 0.0, 0.0, 0.0]
	var frames := 0
	var t := 0.0
	while t < 0.6:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		frames += 1
		for k in chars.size():
			var c = chars[k]
			c.rotation.y += (1.2 * dt / 0.15) if t < 0.15 else 0.0
			var running := t < 0.45
			c.move_speed = 5.0 if running else 0.0
			if running:                             # really run (the hair lags), then stop dead
				c.position += -c.global_transform.basis.z * 5.0 * dt
			peak[k] = maxf(peak[k], _sway_angle(c))
		if frames == 6:
			await _snap_ortho(0.0, "hairmotion_1_turning")
	for c in chars:                                 # bring them back in frame (keeps the hair state)
		c.position.z = 0.0
	await _snap_ortho(0.0, "hairmotion_2_stopping")
	for k in 150:
		await get_tree().process_frame
	var settled := []
	for c in chars:
		settled.append(_sway_angle(c))
	await _snap_ortho(0.0, "hairmotion_3_settled")
	print("hairmotion: still %s  peak %s  settled %s" % [str(still), str(peak), str(settled)])
	var ok: bool = peak[0] > 0.1 and settled[0] < peak[0] * 0.5 and peak[1] > 0.02
	print("hairmotion: %s" % ("OK" if ok else "FAIL"))
	Sfx.quit_game(0 if ok else 1)


## Frames for a little clip: long hair + afro run, stop dead, settle (camera follows).
func _hairgif() -> void:
	var chars: Array = []
	for k in 2:
		var c := Character.new()
		c.build({"hair_style": ["long", "afro"][k], "beard": "none", "hat": "none", "hair": HAIR_TINT})
		c.position = Vector3(k * 1.1, 0, -k * 0.6)   # long hair in front, the afro a step ahead and behind
		c.rotation.y = -PI / 2.0                  # facing +x: we watch from the side
		add_child(c)
		chars.append(c)
	_run_hairgif.call_deferred(chars)


func _run_hairgif(chars: Array) -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 38.0
	cam.current = true
	var t := 0.0
	var n := 0
	var x := 0.0
	var v := 0.0
	while t < 3.0:
		await get_tree().process_frame
		var dt := 1.0 / 30.0                       # fixed step: the clip plays at 30 fps whatever the render speed
		t += dt
		var running := t > 0.6 and t < 1.5
		v = move_toward(v, 4.5 if running else 0.0, dt * (25.0 if running else 60.0))   # stop dead
		x += v * dt
		for k in chars.size():
			var c = chars[k]
			c.position.x = x + k * 1.1
			c.move_speed = v
			c._process(dt)
			c.set_process(false)
		cam.position = Vector3(x + 0.55, 1.62, 2.6)
		cam.look_at(Vector3(x + 0.55, 1.5, -0.3))
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/f_%03d.png" % [out, n])
		n += 1
	print("lineup: hairgif %d frames" % n)
	Sfx.quit_game()


# ------------------------------------------------------------------ haircut portraits
## One clean "photo" per haircut on the default trader: front 3/4 view, head and
## shoulders, perspective camera, a soft three-point light, 800x800.
##   godot --path . -- --lineup=/tmp/out --hairportraits
const PORTRAIT_SIZE := 800
const PORTRAIT_HAIR := Color(0.36, 0.22, 0.12)   # a mid brown: the cut reads better than in near-black


func _hairportraits(env: Environment) -> void:
	env.background_color = Color(0.3, 0.33, 0.39)
	env.ambient_light_color = Color(0.95, 0.96, 1.0)
	env.ambient_light_energy = 0.34
	var key := DirectionalLight3D.new()                # warm key from above, on the camera's side
	key.rotation_degrees = Vector3(-42, 70, 0)
	key.light_energy = 0.62
	key.light_color = Color(1.0, 0.96, 0.9)
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 4.0
	add_child(key)
	var fill := DirectionalLight3D.new()               # cool fill from the other side
	fill.rotation_degrees = Vector3(-10, -40, 0)
	fill.light_energy = 0.28
	fill.light_color = Color(0.85, 0.9, 1.0)
	add_child(fill)
	var rim := DirectionalLight3D.new()                # rim from behind: outlines the hair
	rim.rotation_degrees = Vector3(-25, 160, 0)
	rim.light_energy = 0.7
	add_child(rim)
	var styles: Array = Character.OPTIONS.hair_style
	var chars := []
	for i in styles.size():
		var look: Dictionary = Character.preset("trader").duplicate()
		look["hair_style"] = styles[i]
		look["hair"] = PORTRAIT_HAIR
		var c := Character.new()
		c.build(look)
		c.position = Vector3(i * 4.0, 0, 0)
		c.rotation.y = PI                          # face the camera (+Z)
		c.visible = false
		add_child(c)
		chars.append(c)
	_run_hairportraits.call_deferred(styles, chars)


func _run_hairportraits(styles: Array, chars: Array) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(PORTRAIT_SIZE, PORTRAIT_SIZE)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	cam.current = true
	for i in styles.size():
		for c in chars:
			c.visible = false
		var ch = chars[i]
		ch.visible = true
		ch._next_blink = 1000.0                    # eyes open for the photo
		var target := Vector3(ch.position.x, 1.6, 0.07)
		# front 3/4 (the bald fringe sits behind the ear: swing further round for that one)
		var a := deg_to_rad(62.0 if styles[i] == "bald" else 45.0)
		cam.position = target + Vector3(sin(a), 0.12, cos(a)) * 1.72
		cam.look_at(target + Vector3(0, 0.02, 0))
		for k in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png("%s/portrait_%s.png" % [out, styles[i]])
		print("lineup: portrait_", styles[i])
	Sfx.quit_game()
