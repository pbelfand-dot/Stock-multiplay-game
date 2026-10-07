extends Node3D
## DRIVER FIT: where the crew is fitted to in this car, and a debug overlay that
## draws it (F9 in a stage, or --fit_debug from the start). Everything in the car's
## space (x right, y up, -z forward), from its own interior's parts.json or ours:
##   head      the driver's eyes (the seat camera) / the co-driver's
##   seat      the driver's hip point (under the eyes, slid with the seat)
##   hands     the grips on the rim at a quarter to three
##   wheel     the steering wheel: its centre, rim and column axis
##   shifter / handbrake   the lever's pivot and knob / grip (an automatic: none)
##   pedals    clutch, brake and throttle: under the wheel's column, on the floor
##             (estimated: no model has its pedals marked)
##   door      where the driver would get in and out: outside the driver's door
##   chase     the chase camera's anchor: behind and above the car
##   wheels    each wheel's centre and its suspension's travel
## The overlay adds the collision boxes and an arrow along the car's forward.

const COL := {"head": Color(1.0, 0.85, 0.1), "seat": Color(1.0, 0.5, 0.1), "hands": Color(0.2, 1.0, 0.3),
	"wheel": Color(0.2, 0.9, 1.0), "lever": Color(1.0, 0.55, 0.2), "pedals": Color(0.3, 0.5, 1.0),
	"door": Color(0.9, 0.3, 1.0), "chase": Color(1.0, 0.3, 0.8), "wheels": Color(1.0, 1.0, 1.0),
	"collision": Color(1.0, 0.25, 0.2), "forward": Color(0.2, 1.0, 0.9)}

var car
var cockpit
var anchors := {}
var _im: ImmediateMesh
var _mi: MeshInstance3D
var _labels := {}


## The fit, worked out from the car and its cockpit (both built).
static func fit(the_car, the_cockpit) -> Dictionary:
	var a := {}
	var eye: Vector3 = the_cockpit.eye_driver
	a.head = eye
	a.head_codriver = the_cockpit.eye_codriver
	a.seat = eye + Vector3(0.0, -0.68, 0.12)
	var wc: Vector3 = the_cockpit.wheel_c
	var z: Vector3 = the_cockpit._wheel_axis.normalized()
	var y := (Vector3.UP - z * z.dot(Vector3.UP)).normalized()
	var x := y.cross(z)
	a.wheel = wc
	a.wheel_axis = z
	a.wheel_r = float(the_cockpit.wheel_r)
	a.hand_l = wc - x * the_cockpit.wheel_r
	a.hand_r = wc + x * the_cockpit.wheel_r
	var floor_y := eye.y - 0.98                      # (the car's space: its origin's up at the centre of mass, not on the ground)
	var pz: float = wc.z - 0.52
	a.pedal_clutch = Vector3(wc.x - 0.16, floor_y + 0.1, pz)
	a.pedal_brake = Vector3(wc.x, floor_y + 0.1, pz)
	a.pedal_throttle = Vector3(wc.x + 0.14, floor_y + 0.08, pz + 0.02)
	var info: Dictionary = the_car._model_info if the_car.get("_model_info") is Dictionary else {}
	var half_w := 0.9
	if info.has("body_min") and info.has("body_max"):
		half_w = maxf(absf(float(info.body_min[0])), absf(float(info.body_max[0])))
	a.door = Vector3(signf(eye.x if eye.x != 0.0 else -1.0) * (half_w + 0.6), 0.0, eye.z + 0.1)
	a.chase = Vector3(0.0, 2.3, 6.5)
	var own: Dictionary = the_cockpit.own
	var off: Vector3 = the_car.model_offset()
	if own.has("shifter"):
		a.shifter_pivot = the_cockpit._v3(own.shifter.pivot) + off
		a.shifter_knob = the_cockpit._v3(own.shifter.knob) + off
	if own.has("handbrake"):
		a.handbrake_pivot = the_cockpit._v3(own.handbrake.pivot) + off
		a.handbrake_grip = the_cockpit._v3(own.handbrake.grip) + off
	return a


## Is the fit sane? [ok, why]: the head in the car (under its roof, inside its sides),
## the wheel in front of the eyes with room, the hands within arm's reach of the
## shoulders, the pedals ahead of the seat and below it, the door outside the body.
static func judge(a: Dictionary, the_car) -> Array:
	var bad: Array = []
	var info: Dictionary = the_car._model_info if the_car.get("_model_info") is Dictionary else {}
	if info.has("body_max"):
		var off: Vector3 = the_car.model_offset()
		var top: float = float(info.body_max[1]) + off.y
		if a.head.y > top - 0.08:
			bad.append("head %.2f m up, the roof at %.2f" % [a.head.y, top])
		if absf(a.door.x) <= maxf(absf(float(info.body_min[0])), absf(float(info.body_max[0]))):
			bad.append("the door point inside the body")
	var to_wheel: float = a.head.distance_to(a.wheel)
	if to_wheel < 0.35 or to_wheel > 0.9:
		bad.append("the wheel %.2f m from the eyes" % to_wheel)
	if a.wheel.z > a.head.z - 0.2:
		bad.append("the wheel not in front of the eyes")
	var shoulder: Vector3 = a.head + Vector3(0.0, -0.3, 0.12)
	for k in ["hand_l", "hand_r"]:
		var reach: float = (a[k] - (shoulder + Vector3(0.2 * (-1.0 if k == "hand_l" else 1.0), 0, 0))).length()
		if reach > 0.85:
			bad.append("%s %.2f m from the shoulder" % [k, reach])
	var ahead: float = a.seat.z - a.pedal_brake.z
	if ahead < 0.55 or ahead > 1.3:
		bad.append("the pedals %.2f m ahead of the seat" % ahead)
	if a.pedal_brake.y > a.seat.y:
		bad.append("the pedals above the seat")
	return [bad.is_empty(), "; ".join(bad)]


func setup(the_car, the_cockpit) -> void:
	car = the_car
	cockpit = the_cockpit
	anchors = fit(car, cockpit)
	_im = ImmediateMesh.new()
	_mi = MeshInstance3D.new()
	_mi.mesh = _im
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true                         # (seen through the body: it's a debug view)
	mat.render_priority = 10
	_mi.material_override = mat
	add_child(_mi)
	for k in ["head", "seat", "hand_l", "pedal_brake", "door", "chase", "shifter_knob", "handbrake_grip"]:
		if anchors.has(k):
			var l := Label3D.new()
			l.text = k.replace("_", " ")
			l.font_size = 28
			l.pixel_size = 0.0025
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.modulate = Color.WHITE
			l.position = anchors[k] + Vector3(0, 0.06, 0)
			add_child(l)
			_labels[k] = l


func _process(_dt: float) -> void:
	if car == null or not visible:
		return
	_im.clear_surfaces()
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	var a := anchors
	_star(a.head, 0.05, COL.head)
	_star(a.head_codriver, 0.04, COL.head)
	_star(a.seat, 0.06, COL.seat)
	_line(a.seat, a.head, COL.seat)
	_ring(a.wheel, a.wheel_axis, a.wheel_r, COL.wheel)
	_line(a.wheel, a.wheel - a.wheel_axis * 0.3, COL.wheel)       # the column, toward the dash
	_star(a.hand_l, 0.035, COL.hands)
	_star(a.hand_r, 0.035, COL.hands)
	for k in ["pedal_clutch", "pedal_brake", "pedal_throttle"]:
		_box(a[k], Vector3(0.07, 0.02, 0.1), COL.pedals)
	if a.has("shifter_knob"):
		_line(a.shifter_pivot, a.shifter_knob, COL.lever)
		_star(a.shifter_knob, 0.03, COL.lever)
	if a.has("handbrake_grip"):
		_line(a.handbrake_pivot, a.handbrake_grip, COL.lever)
		_star(a.handbrake_grip, 0.03, COL.lever)
	_star(a.door, 0.08, COL.door)
	_star(a.chase, 0.1, COL.chase)
	_line(a.chase, Vector3(0, 0.8, 0), COL.chase)
	# the wheels: centre and suspension travel (where it is now, and full droop / bump)
	for w in car.wheels:
		var c: Vector3 = car.to_local(w.wheel_center)
		_star(c, 0.08, COL.wheels)
		var travel := 0.18
		if w.cfg and w.cfg.get("travel") != null:
			travel = float(w.cfg.travel)
		_line(c + Vector3.UP * (travel - float(w.compression)), c - Vector3.UP * float(w.compression), COL.wheels)
	# the collision boxes, and forward
	for cs in car.find_children("*", "CollisionShape3D", false, false):
		if (cs as CollisionShape3D).shape is BoxShape3D:
			_obb((cs as CollisionShape3D).transform, ((cs as CollisionShape3D).shape as BoxShape3D).size, COL.collision)
	_line(Vector3(0, 0.6, 0), Vector3(0, 0.6, -3.0), COL.forward)
	_line(Vector3(0, 0.6, -3.0), Vector3(0.25, 0.6, -2.6), COL.forward)
	_line(Vector3(0, 0.6, -3.0), Vector3(-0.25, 0.6, -2.6), COL.forward)
	_im.surface_end()


func _line(p: Vector3, q: Vector3, c: Color) -> void:
	_im.surface_set_color(c)
	_im.surface_add_vertex(p)
	_im.surface_set_color(c)
	_im.surface_add_vertex(q)


func _star(p: Vector3, r: float, c: Color) -> void:
	for ax in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_line(p - ax * r, p + ax * r, c)


func _ring(c: Vector3, axis: Vector3, r: float, col: Color) -> void:
	var y := (Vector3.UP - axis * axis.dot(Vector3.UP)).normalized()
	var x := y.cross(axis)
	var prev := c + x * r
	for k in range(1, 25):
		var t := TAU * k / 24.0
		var p := c + (x * cos(t) + y * sin(t)) * r
		_line(prev, p, col)
		prev = p


func _box(c: Vector3, h: Vector3, col: Color) -> void:
	_obb(Transform3D(Basis(), c), h * 2.0, col)


func _obb(xf: Transform3D, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var corners: Array = []
	for i in 8:
		corners.append(xf * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	for e in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		_line(corners[e[0]], corners[e[1]], col)
