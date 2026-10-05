extends CanvasLayer
## The physics telemetry: F3 shows the numbers, F4 draws the forces.
##   * numbers: speed, ride height, pitch / roll, the physics tick rate, and per
##     wheel the compression (mm), how fast it's moving, the strut force, the
##     tyre's load, and what it's on
##   * arrows (in the world): each tyre's load straight out of the ground at its
##     contact patch (1 m per 10 kN, green; red on the bump stop), the
##     suspension travel as a line from the mount to the wheel, and the centre
##     of mass as a yellow cross
## More columns join as the phases add them (slip, tyre forces, drivetrain).

const N_PER_M := 10000.0           # arrow scale: 10 kN = 1 m

var car: RigidBody3D
var vectors := false

var _label: Label
var _draw: MeshInstance3D
var _mesh: ImmediateMesh


func _ready() -> void:
	layer = 50
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.62)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(12, 12)
	add_child(panel)
	_label = Label.new()
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Menlo", "Consolas", "monospace"])
	_label.add_theme_font_override("font", mono)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	panel.add_child(_label)
	_mesh = ImmediateMesh.new()
	_draw = MeshInstance3D.new()
	_draw.mesh = _mesh
	_draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true                           # seen through the body
	_draw.material_override = m
	add_child(_draw)                                 # world space: a CanvasLayer isn't a Node3D


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_F3:
			visible = not visible
		elif e.keycode == KEY_F4:
			vectors = not vectors


func _process(_dt: float) -> void:
	if car == null:
		return
	if visible:
		_label.text = text()
	_mesh.clear_surfaces()
	_draw.visible = vectors
	if vectors:
		_arrows()


## The numbers, as text (also what the tests print).
func text() -> String:
	var xf: Transform3D = car.global_transform
	var fwd := -xf.basis.z
	var pitch := rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
	var roll := rad_to_deg(asin(clampf(xf.basis.x.y, -1.0, 1.0)))
	var ground := ""
	var s := "PHYSICS V2   %d Hz   %5.1f km/h   pitch %+5.1f   roll %+5.1f   tyres down %d\n" % [
		Engine.physics_ticks_per_second, car.linear_velocity.length() * 3.6, pitch, roll, car.grounded]
	s += "        comp mm   m/s     strut kN   load kN   on\n"
	for k in 4:
		var w = car.wheels[k]
		ground = String(w.collider.get_meta("surface")) if w.grounded and w.collider and w.collider.has_meta("surface") else ("ground" if w.grounded else "air")
		s += "  %s    %6.0f   %+6.2f   %7.2f   %7.2f   %s%s\n" % [car.NAMES[k], w.compression * 1000.0,
			w.compression_velocity, w.strut_force / 1000.0, w.load / 1000.0, ground,
			"  BUMP STOP" if w.compression > w.cfg.bump_stop_start else ""]
	return s


func _arrows() -> void:
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for w in car.wheels:
		var col := Color(1.0, 0.25, 0.2) if w.compression > w.cfg.bump_stop_start else Color(0.3, 1.0, 0.35)
		if w.grounded:
			_line(w.contact, w.contact + w.normal * (w.load / N_PER_M), col)
		_line(w.global_position, w.wheel_center, Color(0.4, 0.7, 1.0))
	var com: Vector3 = car.global_transform * car.center_of_mass
	var c := Color(1.0, 0.85, 0.1)
	for a in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_line(com - a * 0.15, com + a * 0.15, c)
	_mesh.surface_end()


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(b)
