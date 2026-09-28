extends Control
## Hold B: a wheel of emotes. Each slot shows a live outline (a white
## silhouette of your trader doing it). Move the mouse or scroll to pick,
## release B (or click) to play it. The direct hotkeys still work.

const UI = preload("res://scripts/ui/ui_theme.gd")
const Character = preload("res://scripts/art/character.gd")

## [emote, label, what it does, hotkey]
const SLOTS := [
	["dance", "DANCE", "The full routine. Walk to stop.", "H"],
	["fistpump", "FIST PUMP", "Green candle energy.", "V"],
	["point", "POINT", "Call out the next 100x.", "X"],
	["watch", "CHECK WATCH", "Flex the Crownwell.", "Z"],
	["finger", "THE BIRD", "For the shorts.", "F"],
	["smoke_chill", "NONCHALANT", "Slow drag, blow it to the ceiling.", ""],
	["smoke_cough", "FIRST HIT", "Drag. Cough. Pretend it didn't happen.", ""],
]
const RADIUS := 275.0
const ICON := 150

var hud
var open := false
var sel := 0
var _aim := Vector2.ZERO           # accumulated mouse motion while open
var _slots: Array = []             # {panel, view, model, label}
var _title: Label
var _desc: Label


func _init(h) -> void:
	hud = h


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.35)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := Control.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_title = UI.lbl("", 40, UI.GOLD, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.position = Vector2(-200, -40)
	_title.size = Vector2(400, 50)
	center.add_child(_title)
	_desc = UI.lbl("", 20, UI.TEXT)
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc.position = Vector2(-200, 12)
	_desc.size = Vector2(400, 30)
	center.add_child(_desc)
	var hint := UI.lbl("move the mouse / scroll · release B to play", 16, UI.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(-220, 48)
	hint.size = Vector2(440, 24)
	center.add_child(hint)
	for i in SLOTS.size():
		var ang := -PI / 2 + TAU * i / SLOTS.size()
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(ICON, ICON + 34)
		panel.position = Vector2(cos(ang), sin(ang)) * RADIUS - Vector2(ICON, ICON + 34) / 2
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(panel)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		panel.add_child(v)
		var svc := SubViewportContainer.new()
		svc.custom_minimum_size = Vector2(ICON, ICON)
		svc.stretch = true
		v.add_child(svc)
		var vp := SubViewport.new()
		vp.transparent_bg = true
		vp.own_world_3d = true
		vp.size = Vector2i(ICON, ICON)
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		svc.add_child(vp)
		var model: Node3D = Character.new()
		model.build(Config.look if not Config.look.is_empty() else {})
		model.rotation.y = PI - 0.6          # three-quarter view: arm moves read clearly
		model.set_silhouette(Color(0.96, 0.96, 0.96))
		vp.add_child(model)
		var cam := Camera3D.new()
		cam.fov = 34
		vp.add_child(cam)
		cam.position = Vector3(0, 1.05, 3.7)
		cam.look_at(Vector3(0, 0.95, 0))
		var lbl := UI.lbl(SLOTS[i][1] + ("  [%s]" % SLOTS[i][3] if SLOTS[i][3] != "" else ""), 17, UI.TEXT, true)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(lbl)
		_slots.append({"panel": panel, "vp": vp, "model": model, "label": lbl})
	_show(false)


## Pose each outline (so the wheel shows what the emote actually does).
func _show(on: bool) -> void:
	open = on
	visible = on
	for i in _slots.size():
		var s: Dictionary = _slots[i]
		s.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
		s.model.pose = SLOTS[i][0] if on else "idle"
		s.model.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	_aim = Vector2.ZERO
	_refresh()


func _refresh() -> void:
	for i in _slots.size():
		var s: Dictionary = _slots[i]
		var picked := i == sel
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.1, 0.16, 0.92) if not picked else Color(0.2, 0.16, 0.05, 0.95)
		sb.border_color = UI.GOLD if picked else Color(0.3, 0.34, 0.45)
		sb.set_border_width_all(4 if picked else 2)
		sb.set_corner_radius_all(14)
		s.panel.add_theme_stylebox_override("panel", sb)
		s.panel.scale = Vector2.ONE * (1.12 if picked else 1.0)
		s.panel.pivot_offset = s.panel.size / 2
		s.label.add_theme_color_override("font_color", UI.GOLD if picked else UI.TEXT)
	_title.text = SLOTS[sel][1]
	_desc.text = SLOTS[sel][2]


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("emote_wheel") and not open and hud.world.local_player \
			and not hud.world.ui_blocking():
		_show(true)
		get_viewport().set_input_as_handled()
		return
	if not open:
		return
	if event.is_action_released("emote_wheel") or (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		_play()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:     # steer the pick; don't turn the camera
		_aim += event.relative
		if _aim.length() > 40.0:
			_aim = _aim.limit_length(120.0)
			var ang := fposmod(_aim.angle() + PI / 2, TAU)
			var i := int(round(ang / (TAU / SLOTS.size()))) % SLOTS.size()
			if i != sel:
				sel = i
				_refresh()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			sel = (sel + 1) % SLOTS.size()
			_refresh()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			sel = (sel + SLOTS.size() - 1) % SLOTS.size()
			_refresh()
		get_viewport().set_input_as_handled()


func _play() -> void:
	_show(false)
	var p = hud.world.local_player
	if p:
		p.play_emote(SLOTS[sel][0])
