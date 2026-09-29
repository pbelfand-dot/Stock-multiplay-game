extends Node3D
## Renders a character lineup for visual checks (needs a display / xvfb):
##   godot --path . -- --lineup=/tmp/out
## Hair close-ups (every style from the front, 3/4, side and back, plus hats):
##   godot --path . -- --lineup=/tmp/out --hair
## One portrait per haircut (portrait_<style>.png, 800x800):
##   godot --path . -- --lineup=/tmp/out --hairportraits
## Props kit review shots (three angles + one at game distance per prop):
##   godot --path . -- --lineup=/tmp/out --props=ATM,Gun_Rifle [--refs=/tmp/ref.json]
## BEMZE cars assembled (body + wheels + steering wheel at the REF points), several views each:
##   godot --path . -- --lineup=/tmp/out --cars=M3,M5 --refs=/tmp/bemze_ref.json [--carviews=side,top]
##   (--cars=lineup: all six side by side; refs from BEMZE_REF_JSON=... tools/blender/build_bemze.py)

const Character = preload("res://scripts/art/character.gd")
const PropKit = preload("res://scripts/art/prop_kit.gd")

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
	floor_mi.name = "Floor"
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.38, 0.45)
	floor_mi.material_override = fm
	add_child(floor_mi)
	if Config.cli.has("cars"):          # preview helper: BEMZE car review shots
		_carshots.call_deferred(env, floor_mi)
		return
	if Config.cli.has("props"):
		_propshots.call_deferred()
		return
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


# ------------------------------------------------------------------ prop review shots
## Each prop alone from three angles + one at game distance (1.2-3.5 m):
##   godot --path . -- --lineup=/tmp/out --props=ATM,Gun_Rifle [--refs=/tmp/ref.json]
## --refs (from PROPS_REF_JSON=/tmp/ref.json python3 tools/blender/build_props.py) marks each
## prop's reference points with magenta dots. --props=demo stages the reference points in use
## (bill stacks in a money counter, labels on the LCD / ATM screen, a gun with hand points).
func _propshots() -> void:
	var refs := {}
	if Config.cli.has("refs"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(str(Config.cli.refs)))
		if parsed is Dictionary:
			refs = parsed
	if str(Config.cli.props) == "demo":
		await _propdemo(refs)
		Sfx.quit_game()
		return
	for nm in str(Config.cli.props).split(","):
		var n := PropKit.place(nm, self)
		var box := _aabb(n)
		if box.position.y < 0.0:
			n.position.y = -box.position.y + 0.02
			box = _aabb(n)
		var wall := nm in ["GunWallRack", "TargetSheet"]
		var back: MeshInstance3D = null
		if wall:
			back = _box(Vector3(box.size.x + 3.0, box.size.y + 3.0, 0.02), Color(0.55, 0.52, 0.48))
			back.position = Vector3(0, box.get_center().y, -0.011)
		if refs.has(nm):
			var dr := clampf(box.size.length() * 0.012, 0.002, 0.012)
			for k in refs[nm]:
				var v = refs[nm][k]
				if v is Array and v.size() == 3 and not (k.ends_with("normal") or k.ends_with("size")):
					var dot := _dot(dr, Color(1, 0, 1))
					dot.reparent(n, false)
					dot.position = Vector3(v[0], v[1], v[2])
		var c := box.get_center()
		var r := box.size.length() * 0.5
		var dist := r / sin(deg_to_rad(20.0)) * 1.05
		var side := Vector3(-0.75, 0.3, 0.55) if wall else Vector3(-0.8, 0.35, -0.5)
		for v in [["a", Vector3(0.6, 0.45, 0.75)], ["b", side], ["c", Vector3(0, 0.12, 1)]]:
			await _snap(c + (v[1] as Vector3).normalized() * dist, c, 40, "%s_%s" % [nm, v[0]])
		var gd := clampf(r * 4.0, 1.2, 3.5)
		await _snap(c + Vector3(0.35, 0.5, 1.0).normalized() * gd, c, 70, "%s_game" % nm)
		n.queue_free()
		if back:
			back.queue_free()
	Sfx.quit_game()


func _v3(a) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _propdemo(refs: Dictionary) -> void:
	# money counters with stacks in the hopper (tilted, scaled up) and the stacker, digits on the LCD
	var x := -0.5
	for nm in ["MoneyCounter", "MoneyCounterPro", "CashCounter"]:
		var mc := PropKit.place(nm, self, Vector3(x, 0, 0))
		var r: Dictionary = refs.get(nm, {})
		if r.is_empty():
			break
		var hop := PropKit.place("BillStack", mc, _v3(r.hopper))
		hop.rotation.x = deg_to_rad(float(r.hopper_tilt_deg))
		hop.scale = Vector3(1, 3.5, 1)
		var out := PropKit.place("BillStack", mc, _v3(r.stacker))
		out.scale = Vector3(1, 2.0, 1)
		var lab := Label3D.new()
		lab.text = "10000"
		lab.font_size = 48
		lab.pixel_size = 0.0006
		lab.outline_size = 0
		lab.modulate = Color(0.85, 0.95, 1.0)
		lab.position = _v3(r.lcd_center) + _v3(r.lcd_normal) * 0.001
		lab.rotation.x = -deg_to_rad(45.0)
		mc.add_child(lab)
		x += 0.45
	var cd := PropKit.place("CounterDisplay", self, Vector3(0.85, 0, 0.05))
	if refs.has("CounterDisplay"):
		var led := Label3D.new()
		led.text = "$10,000"
		led.font_size = 40
		led.pixel_size = 0.0005
		led.outline_size = 0
		led.modulate = Color(1, 0.15, 0.1)
		led.position = _v3(refs.CounterDisplay.led_center) + Vector3(0, 0, 0.001)
		cd.add_child(led)
	PropKit.place("MoneyBrick", self, Vector3(1.05, 0, 0.05))
	var fan := PropKit.place("BillFan", self, Vector3(-0.95, 0.05, 0.05))
	fan.rotation.z = 0.0
	await _snap(Vector3(0.05, 0.55, 0.95), Vector3(0.05, 0.1, 0), 45, "demo_counters")
	await _snap(Vector3(-0.5, 0.42, 0.3), Vector3(-0.5, 0.15, 0.03), 45, "demo_counter_close")
	for c in get_children():
		if c is Node3D and not (c is Camera3D or c is DirectionalLight3D or c is WorldEnvironment) and c.name != "Floor":
			c.queue_free()
	await get_tree().process_frame
	# ATM with UI text on the screen + header and a bill at the dispenser
	var atm := PropKit.place("ATM", self)
	if refs.has("ATM"):
		var a: Dictionary = refs.ATM
		for spec in [[a.screen_center, "BALANCE\n$1,337,420.69", Color(0.6, 1, 0.8), 0.0012],
				[a.header_center, "BAGHOLDER BANK", Color(1, 1, 1), 0.0022]]:
			var l := Label3D.new()
			l.text = spec[1]
			l.font_size = 64
			l.pixel_size = spec[3]
			l.outline_size = 0
			l.modulate = spec[2]
			l.position = _v3(spec[0]) + Vector3(0, 0, 0.002)
			atm.add_child(l)
		var bill := PropKit.place("BillStack", atm, _v3(a.dispenser) + Vector3(0, -0.005, 0.03))
		bill.scale = Vector3(1, 0.4, 1)
	await _snap(Vector3(0.9, 1.5, 2.2), Vector3(0, 0.95, 0), 45, "demo_atm")
	atm.queue_free()
	# guns with the grip / tip / support points marked
	var gx := -1.2
	for nm in ["Gun_Pistol", "Gun_Deagle", "Gun_SMG", "Gun_Shotgun", "Gun_Rifle", "Gun_RifleGold"]:
		var g := PropKit.place(nm, self, Vector3(gx, 0.3, 0), -PI / 2)
		for k in ["grip", "barrel_tip", "support_hand"]:
			if refs.has(nm) and refs[nm].has(k):
				var d := _dot(0.008, Color(1, 0, 1) if k != "grip" else Color(0, 1, 1))
				d.reparent(g, false)
				d.position = _v3(refs[nm][k])
		gx += 0.45 if nm != "Gun_Shotgun" else 0.75
	await _snap(Vector3(0.3, 0.45, 2.3), Vector3(0.3, 0.3, 0), 45, "demo_guns")


func _aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _box(size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mi.material_override = m
	add_child(mi)
	return mi


func _dot(r: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	mi.material_override = m
	add_child(mi)
	return mi


# ------------------------------------------------------------------ BEMZE car review shots (preview helper)
const CAR_MODELS := ["M3", "M5", "M4", "M2", "M8", "540i"]


func _car_prop(nm: String) -> String:
	return nm if nm.begins_with("Cop_") else "Bemze_" + nm


func _car(nm: String, refs: Dictionary, pos: Vector3) -> Node3D:
	var body := PropKit.place(_car_prop(nm), self, pos)
	var r: Dictionary = refs.get(_car_prop(nm), {})
	if r.is_empty():
		return body
	var paint := PropKit.material("CarPaint")
	for mi in body.get_children():
		if mi is MeshInstance3D and mi.material_override == paint:
			var m: StandardMaterial3D = paint.duplicate()
			var c: Array = r.get("paint", [1, 1, 1])
			m.albedo_color = Color(c[0], c[1], c[2])
			mi.material_override = m
	for k in ["wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR"]:
		if not r.has(k):
			continue
		var w := PropKit.place(str(r.wheel), body, _v3(r[k]))
		if k.ends_with("L"):
			w.scale = Vector3(-1, 1, 1)
	if r.has("steering_hub"):
		var sw := PropKit.place("Bemze_SteeringWheel", body, _v3(r.steering_hub))
		sw.rotation.x = deg_to_rad(float(r.column_tilt_deg))
	if r.has("lightbar_mount"):
		for lb in r.lightbar_props:
			PropKit.place(str(lb), body, _v3(r.lightbar_mount))
	return body


func _carsnap(vp: SubViewport, cam: Camera3D, pos: Vector3, look: Vector3, fov: float, file: String,
		ortho := 0.0) -> void:
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL if ortho > 0.0 else Camera3D.PROJECTION_PERSPECTIVE
	cam.size = maxf(ortho, 0.1)
	cam.fov = fov
	cam.near = 0.02
	cam.position = pos
	var up := Vector3.UP if absf((look - pos).normalized().y) < 0.99 else Vector3(0, 0, -1)
	cam.look_at(look, up)
	for k in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out + "/" + file + ".png")
	print("lineup: ", file)


func _carshots(env: Environment, floor_mi: MeshInstance3D) -> void:
	var refs := {}
	if Config.cli.has("refs"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(str(Config.cli.refs)))
		if parsed is Dictionary:
			refs = parsed
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.36, 0.55, 0.85)
	psm.sky_horizon_color = Color(0.75, 0.8, 0.88)
	psm.ground_horizon_color = Color(0.6, 0.6, 0.62)
	psm.ground_bottom_color = Color(0.25, 0.25, 0.27)
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	(floor_mi.mesh as PlaneMesh).size = Vector2(120, 120)
	(floor_mi.material_override as StandardMaterial3D).albedo_color = Color(0.42, 0.43, 0.45)
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 900)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	var list: Array = []
	var arg := str(Config.cli.cars)
	if arg == "lineup":
		for i in CAR_MODELS.size():
			_car(CAR_MODELS[i], refs, Vector3((i - 2.5) * 2.7, 0, 0))
		await _carsnap(vp, cam, Vector3(-9.5, 3.2, -12.5), Vector3(-0.8, 0.5, 0), 38, "lineup_front34")
		await _carsnap(vp, cam, Vector3(0, 0.8, -30), Vector3(0, 0.75, 0), 20, "lineup_front")
		await _carsnap(vp, cam, Vector3(9.5, 3.2, 12.5), Vector3(0.8, 0.5, 0), 38, "lineup_rear34")
		Sfx.quit_game()
		return
	var views := ["front34", "rear34", "side", "front", "rear", "top", "interior", "wheel", "nose", "tail",
			"side34low", "cockpit"]
	if Config.cli.has("carviews"):
		views = str(Config.cli.carviews).split(",")
	for nm in arg.split(","):
		var car := _car(nm, refs, Vector3.ZERO)
		var r: Dictionary = refs.get(_car_prop(nm), {})
		var box := _aabb(car)
		var c := box.get_center()
		for v in views:
			var f := "car_%s_%s" % [nm, v]
			match v:
				"front34":
					await _carsnap(vp, cam, Vector3(-4.3, 1.45, -5.2), Vector3(0, 0.6, -0.2), 40, f)
				"rear34":
					await _carsnap(vp, cam, Vector3(4.3, 1.55, 5.4), Vector3(0, 0.6, 0.2), 40, f)
				"side":
					await _carsnap(vp, cam, Vector3(20, c.y, c.z), Vector3(0, c.y, c.z), 30, f, 3.3)
				"front":
					await _carsnap(vp, cam, Vector3(0, 0.75, -20), Vector3(0, 0.75, 0), 30, f, 1.75)
				"rear":
					await _carsnap(vp, cam, Vector3(0, 0.75, 20), Vector3(0, 0.75, 0), 30, f, 1.75)
				"top":
					await _carsnap(vp, cam, Vector3(c.x, 20, c.z), Vector3(c.x, 0, c.z), 30, f, 5.4)
				"side34low":
					await _carsnap(vp, cam, Vector3(-5.6, 0.55, -2.2), Vector3(0, 0.62, 0.1), 42, f)
				"nose":
					await _carsnap(vp, cam, Vector3(-1.4, 1.1, box.position.z - 1.6), Vector3(0, 0.62, box.position.z + 0.3), 42, f)
				"tail":
					await _carsnap(vp, cam, Vector3(1.4, 1.2, box.end.z + 1.7), Vector3(0, 0.75, box.end.z - 0.3), 42, f)
				"wheel":
					if r.has("wheel_FL"):
						var wp := _v3(r.wheel_FL)
						await _carsnap(vp, cam, wp + Vector3(-1.6, 0.25, -0.5), wp, 40, f)
				"interior":
					if r.has("eye"):
						var e := _v3(r.eye)
						await _carsnap(vp, cam, e, e + Vector3(0, -0.12, -1), 72, f)
				"cockpit":
					if r.has("eye"):
						var e2 := _v3(r.eye)
						await _carsnap(vp, cam, e2 + Vector3(0.55, 0.12, 0.55), e2 + Vector3(-0.1, -0.35, -0.9), 70, f)
		car.queue_free()
		await get_tree().process_frame
	Sfx.quit_game()
