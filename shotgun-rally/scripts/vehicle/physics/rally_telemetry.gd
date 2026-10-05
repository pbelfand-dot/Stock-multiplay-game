extends CanvasLayer
## The physics telemetry: F3 shows the numbers, F4 draws the forces.
##   * numbers: speed, lateral g, pitch / roll, the steering, the physics tick
##     rate, the engine (rpm, gear, throttle, boost, clutch, torque), and per wheel the compression (mm), how fast it's moving, the
##     tyre's load, its slip angle and side force, the wheel's own speed, its
##     slip ratio and drive / brake force, and what it's on (LOCKED: a wheel
##     stopped while the car moves)
##   * arrows (in the world): each tyre's load straight out of the ground at its
##     contact patch (1 m per 10 kN, green; red on the bump stop), its side
##     force (orange) and drive / brake force (violet) along the ground, the
##     suspension travel as a line from the
##     mount to the wheel, and the centre of mass as a yellow cross
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
	var lat_g: float = car.accel.dot(xf.basis.x) / 9.8
	var s := "PHYSICS V2   %d Hz   %5.1f km/h   lateral %+4.2f g   pitch %+5.1f   roll %+5.1f   tyres down %d\n" % [
		Engine.physics_ticks_per_second, car.linear_velocity.length() * 3.6, lat_g, pitch, roll, car.grounded]
	s += "steering %+5.1f deg (wheels %+5.1f / %+5.1f)\n" % [rad_to_deg(car.steer), rad_to_deg(car.wheel_angles[0]), rad_to_deg(car.wheel_angles[1])]
	var d = car.drivetrain
	if d:
		var g := "R" if d.gear < 0 else ("N" if d.gear == 0 else str(d.gear))
		s += "engine %5.0f rpm  gear %s  throttle %3.0f %%  boost %3.0f %%  clutch %3.0f %%  %4.0f N m  (clutch carries %4.0f)%s%s\n" % [
			d.rpm(), g, d.throttle * 100.0, d.boost * 100.0, d.clutch * 100.0, d.engine_torque, d.clutch_torque,
			"  SHIFT" if d.shifting() else "", "  LIMITER" if d.limiter else ""]
	s += "        comp mm   load kN   slip deg   side kN   wheel km/h   slip %   drive kN   on\n"
	for k in 4:
		var w = car.wheels[k]
		ground = w.surface.display_name if w.grounded else "air"
		var state := ""
		if w.compression > w.cfg.bump_stop_start:
			state += "  BUMP STOP"
		if absf(w.omega) < 0.01 and absf(w.v_long) > 0.5:
			state += "  LOCKED"
		s += "  %s    %6.0f   %7.2f   %+7.2f   %+6.2f   %9.1f   %+6.0f   %+7.2f   %s%s\n" % [car.NAMES[k], w.compression * 1000.0,
			w.load / 1000.0, w.slip_angle_deg(), w.lateral_force / 1000.0, w.wheel_speed() * 3.6, w.slip_long * 100.0,
			w.long_force / 1000.0, ground, state]
	return s


func _arrows() -> void:
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for w in car.wheels:
		var col := Color(1.0, 0.25, 0.2) if w.compression > w.cfg.bump_stop_start else Color(0.3, 1.0, 0.35)
		if w.grounded:
			_line(w.contact, w.contact + w.normal * (w.load / N_PER_M), col)
			var right: Vector3 = w.heading.cross(w.normal)
			_line(w.contact, w.contact + right * (w.lateral_force / N_PER_M), Color(1.0, 0.55, 0.1))
			_line(w.contact, w.contact + w.heading * (w.long_force / N_PER_M), Color(0.9, 0.3, 1.0))
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
