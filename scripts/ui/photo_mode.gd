extends Control
## PHOTO MODE (K): step out of your head, frame a shot of yourself and your
## friends, pose, pick a filter, SNAP. Photos are saved on this computer only
## (Pictures/BAGHOLDERS), nothing is uploaded anywhere.
##
##   WASD fly the camera (stays near you) · Q/E down/up · hold right mouse to
##   look around · wheel zoom · SPACE snap · K / ESC leave

const UI = preload("res://scripts/ui/ui_theme.gd")
const Character = preload("res://scripts/art/character.gd")

const MAX_DIST := 10.0            # how far the camera may wander from you
const POSES := [["NONE", ""], ["DANCE", "dance"], ["FIST PUMP", "fistpump"], ["POINT", "point"],
	["THE FINGER", "finger"], ["WATCH CHECK", "watch"], ["NONCHALANT", "smoke_chill"], ["FIRST HIT", "smoke_cough"],
	["FLASH CASH", "flash"], ["MONEY SPREAD", "fan"], ["DRAW / SWAP GUN", "#gun"], ["AIM", "#aim"]]
const FILTERS := ["NONE", "B&W", "FILM", "COLD", "VHS"]

var hud
var active := false
var cam: Camera3D
var filter_rect: ColorRect
var panel: PanelContainer
var flash: ColorRect
var status: Label
var watermark: Label
var fov_slider: HSlider
var freeze_btn: CheckButton
var mark_btn: CheckButton
var names_btn: CheckButton
var open_btn: Button
var _yaw := 0.0
var _pitch := 0.0
var _looking := false
var _filter := 0
var _last_path := ""
var _flash_t := 0.0


func _init(h) -> void:
	hud = h


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	filter_rect = ColorRect.new()
	filter_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = _filter_shader()
	filter_rect.material = mat
	add_child(filter_rect)
	watermark = UI.lbl("", 26, Color(1, 1, 1, 0.85), true)
	watermark.anchor_left = 1.0
	watermark.anchor_right = 1.0
	watermark.anchor_top = 1.0
	watermark.anchor_bottom = 1.0
	watermark.offset_left = -560
	watermark.offset_right = -24
	watermark.offset_top = -64
	watermark.offset_bottom = -20
	watermark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	watermark.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	watermark.add_theme_constant_override("outline_size", 8)
	add_child(watermark)
	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(1, 1, 1, 0)
	add_child(flash)
	_build_panel()


func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.panel_box(Color(0.03, 0.04, 0.07, 0.82), UI.GOLD, 12, 2))
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -316
	panel.offset_right = -16
	panel.offset_top = 16
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(UI.lbl("PHOTO MODE", 30, UI.GOLD, true))
	var hint := UI.lbl("WASD fly · Q/E down/up · hold right mouse to look · wheel zoom", 13, UI.DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.custom_minimum_size.x = 270
	v.add_child(hint)
	v.add_child(UI.lbl("POSE", 18, UI.TEXT, true))
	var grid := GridContainer.new()
	grid.columns = 2
	v.add_child(grid)
	for p in POSES:
		var b := UI.btn(p[0], UI.NAVY_2, 15)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var e: String = p[1]
		b.pressed.connect(func(): _pose(e))
		grid.add_child(b)
	freeze_btn = CheckButton.new()
	freeze_btn.text = "Freeze pose"
	freeze_btn.toggled.connect(_freeze)
	v.add_child(freeze_btn)
	v.add_child(UI.lbl("FILTER", 18, UI.TEXT, true))
	var fr := HBoxContainer.new()
	v.add_child(fr)
	for i in FILTERS.size():
		var fb := UI.btn(FILTERS[i], UI.NAVY_2, 13)
		var k := i
		fb.pressed.connect(func(): _set_filter(k))
		fr.add_child(fb)
	v.add_child(UI.lbl("ZOOM", 18, UI.TEXT, true))
	fov_slider = HSlider.new()
	fov_slider.min_value = 20
	fov_slider.max_value = 95
	fov_slider.value = 60
	fov_slider.value_changed.connect(func(x): if cam: cam.fov = x)
	v.add_child(fov_slider)
	names_btn = CheckButton.new()
	names_btn.text = "Show name tags"
	names_btn.toggled.connect(_show_names)
	v.add_child(names_btn)
	mark_btn = CheckButton.new()
	mark_btn.text = "BAGHOLDERS watermark"
	mark_btn.button_pressed = true
	mark_btn.toggled.connect(func(on): watermark.visible = on)
	v.add_child(mark_btn)
	var snap := UI.btn("SNAP  [SPACE]", UI.GREEN.darkened(0.25), 26)
	snap.pressed.connect(snap_photo)
	v.add_child(snap)
	status = UI.lbl("Photos stay on this computer.", 14, UI.DIM)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	status.custom_minimum_size.x = 260
	v.add_child(status)
	open_btn = UI.btn("OPEN PHOTOS FOLDER", UI.NAVY_2, 16)
	open_btn.pressed.connect(func(): OS.shell_open(ProjectSettings.globalize_path(photo_dir())))
	v.add_child(open_btn)
	var leave := UI.btn("LEAVE PHOTO MODE  [K]", UI.RED.darkened(0.35), 18)
	leave.pressed.connect(toggle)
	v.add_child(leave)


# ---------------------------------------------------------------- on / off

func toggle() -> void:
	if active:
		_exit()
	else:
		_enter()


func _enter() -> void:
	var p = hud.world.local_player
	if p == null or p.cam == null:
		return
	active = true
	visible = true
	hud.root.visible = false                    # the whole game HUD (photo mode lives on its own layer)
	cam = Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF         # flown in _process
	cam.fov = fov_slider.value
	cam.near = 0.03
	cam.far = p.cam.far
	hud.world.add_child(cam)
	# start just in front of you, looking back at you
	var fwd: Vector3 = -p.global_transform.basis.z
	cam.global_position = p.global_position + fwd * 2.4 + Vector3(0, 1.6, 0)
	cam.look_at(p.global_position + Vector3(0, 1.45, 0))
	_yaw = cam.rotation.y
	_pitch = cam.rotation.x
	cam.current = true
	p.model.set_first_person(false)             # your head shows in the shot
	_show_names(names_btn.button_pressed)
	watermark.visible = mark_btn.button_pressed
	_update_watermark()
	Sfx.play("click")


func _exit() -> void:
	active = false
	visible = false
	_freeze(false)
	freeze_btn.set_pressed_no_signal(false)
	hud.root.visible = true
	_show_names(true)
	var p = hud.world.local_player
	if p:
		p.photo_aim = false
		p.model.set_first_person(true)
		p.name_tag.visible = false                 # ours is never shown to us
		if p.cam:
			p.cam.current = true
	if cam:
		cam.queue_free()
		cam = null
	_looking = false


# ---------------------------------------------------------------- controls

func _process(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t = maxf(_flash_t - delta * 3.0, 0.0)
		flash.color.a = _flash_t
	if not active or cam == null:
		return
	var p = hud.world.local_player
	if p == null:
		_exit()
		return
	var mv := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		mv.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		mv.z += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		mv.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		mv.x += 1.0
	if Input.is_physical_key_pressed(KEY_E):
		mv.y += 1.0
	if Input.is_physical_key_pressed(KEY_Q):
		mv.y -= 1.0
	var speed := 3.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.2
	cam.rotation = Vector3(_pitch, _yaw, 0.0)
	var pos: Vector3 = cam.global_position + cam.global_transform.basis * Vector3(mv.x, 0, mv.z) * speed * delta
	pos.y += mv.y * speed * delta
	# keep the camera near you and above the floor you're standing on
	var anchor: Vector3 = p.global_position + Vector3(0, 1.2, 0)
	var off := pos - anchor
	if off.length() > MAX_DIST:
		pos = anchor + off.normalized() * MAX_DIST
	pos.y = maxf(pos.y, p.global_position.y + 0.15)
	# no flying through walls (you'd see the void outside the building)
	var q := PhysicsRayQueryParameters3D.create(anchor, pos, 1)
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		pos = (hit.position as Vector3) + (hit.normal as Vector3) * 0.2
	cam.global_position = pos
	_update_watermark()


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_looking = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			fov_slider.value -= 3.0
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			fov_slider.value += 3.0
	elif event is InputEventMouseMotion and _looking:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.004
		_pitch = clampf(_pitch - mm.relative.y * 0.004, -1.4, 1.4)
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_SPACE:
				snap_photo()
				get_viewport().set_input_as_handled()
			KEY_K, KEY_ESCAPE:
				toggle()
				get_viewport().set_input_as_handled()


func _pose(e: String) -> void:
	var p = hud.world.local_player
	if p == null:
		return
	_freeze(false)
	freeze_btn.set_pressed_no_signal(false)
	if e == "#gun":                              # BIG IRON: out / next / away
		p.photo_aim = false
		p.cycle_gun()
		return
	if e == "#aim":
		p.photo_aim = not p.photo_aim
		p.emote = 0
		p._emote_t = 0.0
		return
	if e == "":
		p.emote = 0
		p._emote_t = 0.0
		p.photo_aim = false
	else:
		p.emote = 0                              # restart it even if it was playing
		p.play_emote(e)


## Hold the character exactly as it is (animation + hair stop) for a crisp shot.
func _freeze(on: bool) -> void:
	var p = hud.world.local_player if hud and hud.world else null
	if p and p.model:
		p.model.set_process(not on)


## Floating name tags over everyone's heads: off by default for a clean shot.
func _show_names(on: bool) -> void:
	for pl in hud.world.players_node.get_children():
		if pl.get("name_tag") and pl != hud.world.local_player:
			pl.name_tag.visible = on


func _set_filter(i: int) -> void:
	_filter = i
	(filter_rect.material as ShaderMaterial).set_shader_parameter("mode", i)
	Sfx.play("click")


func _update_watermark() -> void:
	var t := Time.get_datetime_dict_from_system()
	var names: Array = []
	for id in Net.players:
		names.append(Net.player_name(id))
	watermark.text = "BAGHOLDERS  ·  %s  ·  %02d/%02d/%d" % [" × ".join(names), t.month, t.day, t.year]


# ---------------------------------------------------------------- the shot

static var dir_override := ""      # tests


static func photo_dir() -> String:
	if dir_override != "":
		return dir_override
	var pics := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if pics != "" and DirAccess.dir_exists_absolute(pics):
		return pics.path_join("BAGHOLDERS")
	return "user://photos"


## Take the picture: the side panel is hidden for the frame, the filter and
## watermark are kept. Returns the file path ("" if it couldn't save).
func snap_photo() -> String:
	if not active:
		return ""
	panel.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	panel.visible = true
	_flash_t = 0.9
	Sfx.play("flash")
	if img == null or img.is_empty():
		status.text = "Couldn't grab the frame."
		return ""
	var dir := photo_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var t := Time.get_datetime_dict_from_system()
	var stem := dir.path_join("Bagholders_%04d%02d%02d_%02d%02d%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second])
	var path := stem + ".png"
	var n := 2
	while FileAccess.file_exists(path):          # two snaps in the same second
		path = "%s_%d.png" % [stem, n]
		n += 1
	if img.save_png(path) != OK:
		status.text = "Couldn't save the photo."
		return ""
	_last_path = path
	status.text = "Saved: %s" % ProjectSettings.globalize_path(path)
	return path


func _filter_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
uniform int mode = 0;
uniform sampler2D screen : hint_screen_texture, filter_linear;
float rnd(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec4 c = texture(screen, SCREEN_UV);
	vec2 d = SCREEN_UV - 0.5;
	float vig = 1.0 - dot(d, d) * 1.1;
	if (mode == 0) { COLOR = vec4(0.0); }
	else {
		vec3 col = c.rgb;
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		if (mode == 1) { col = vec3(smoothstep(0.02, 0.98, l)); col *= vig; }
		else if (mode == 2) {
			col = mix(col, vec3(l), 0.25) * vec3(1.08, 1.0, 0.86) + vec3(0.03, 0.015, 0.0);
			col += (rnd(SCREEN_UV * 900.0 + TIME) - 0.5) * 0.06;
			col *= vig;
		}
		else if (mode == 3) { col = mix(col, vec3(l), 0.2) * vec3(0.88, 0.98, 1.12); col *= vig; }
		else if (mode == 4) {
			float off = 0.003;
			col.r = texture(screen, SCREEN_UV + vec2(off, 0.0)).r;
			col.b = texture(screen, SCREEN_UV - vec2(off, 0.0)).b;
			col *= 0.9 + 0.1 * sin(SCREEN_UV.y * 900.0);
			col += (rnd(vec2(SCREEN_UV.y * 300.0, TIME)) - 0.5) * 0.05;
		}
		COLOR = vec4(col, 1.0);
	}
}
"""
	return s
