extends Node3D
## The inside of the car, low poly like the reference, stripped out like a real
## rally car: red shell and roll cage, a black flock dash (no glare in the
## screen) with the dials, shift lights and a switch panel, a sequential gear
## lever, carbon door cards with pull straps, a wide mirror and a sun strip, the
## co-driver's footrest, map lamp and trip meter, a spare wheel strapped down in
## the back, the red hood out front. Two crew: the DRIVER (left, red helmet) with hands that follow
## the wheel, and the CO-DRIVER (right, blue helmet) holding the map board.
## Also the windshield mud (cartoon splats from a puddle: one always right in
## front of the driver, with flicked droplets and drips that run down) and the two wipers that
## clear their arcs of it, a bit more each stroke; the corners stay dirty.
## A child of the car, so it moves with it. Car-local units: the car faces -Z,
## origin = chassis middle at wheel-mount height (the ground is ~0.56 below).
##
## The crew are the owner's racer (assets/models/driver.glb, codriver.glb:
## tools/import_crew.py; posed by crew_model.gd). The driver sees their own arms on the wheel (their
## model just has no head: the camera is in it); the co-driver doesn't see their
## own body at all (render layer 3), so nothing gets between them and the map.
## If a model is missing, the old box crew is built instead: each of their heads
## is on its own render layer (2 = driver, 3 = co-driver) so your own camera
## doesn't see the inside of your helmet.
##
## A car with an interior of its own (its model's: parts.json "cockpit",
## tools/import_car.py) keeps it: none of the above is built but the crew, the
## mud and the wipers. The crew sit where its seats are (the driver behind its
## steering wheel: on the right in a right-hand-drive car, the co-driver and the
## map board on the other side), the gloves grip and turn its own wheel, and the
## hand nearer the middle works its own gear lever and handbrake (driver_hands.gd
## use_model: an automatic shifts itself). The mud goes on its windshield.

const MapBoard = preload("res://scripts/vehicle/map_board.gd")
const CrewModel = preload("res://scripts/vehicle/crew_model.gd")
const DriverHands = preload("res://scripts/vehicle/driver_hands.gd")
const Harness = preload("res://scripts/vehicle/harness.gd")

const RED := Color(0.78, 0.12, 0.1)
const GREY := Color(0.46, 0.45, 0.43)
const DARK := Color(0.1, 0.1, 0.11)
const SEAT := Color(0.82, 0.55, 0.22)
const SKIN := Color(0.86, 0.67, 0.5)
const SUIT_D := Color(0.75, 0.13, 0.12)
const FLOCK := Color(0.12, 0.12, 0.13)                # the dash's black flock
const CARBON := Color(0.1, 0.1, 0.11)
const CARBON_HI := Color(0.16, 0.16, 0.17)
const STRAP := Color(0.8, 0.1, 0.08)
const ALU := Color(0.68, 0.68, 0.7)
const SUIT_C := Color(0.14, 0.24, 0.62)
const EYE_DRIVER := Vector3(-0.37, 0.6, 0.26)
const EYE_CODRIVER := Vector3(0.37, 0.6, 0.26)
const WHEEL_C := Vector3(-0.37, 0.26, -0.17)        # clear of the dash, the binnacle and its hood (rim top 4 cm off them)
const WHEEL_R := 0.16                         # the rim's centreline: a 350 mm wheel (Momo Mod.08 size)
const RIM_TUBE := 0.0155                      # ... a ~30 mm suede grip
const WHEEL_DISH := 0.088                     # the hub sits 88 mm in front of the rim (a deep-dish rally wheel)
const WHEEL_TILT := 0.42                      # rad back from vertical
const HARNESS_BAR := Vector2(0.5, 0.66)       # the harness bar behind the seats: height, back (m)
## The windshield: bottom edge (cowl) and top edge, car-local.
const WS_BOTTOM := Vector3(0.0, 0.32, -0.74)
const WS_TOP := Vector3(0.0, 0.92, -0.3)
const WS_W := 1.42
const WIPER_X := [-0.5, 0.18]                 # pivot positions along the bottom of the glass (m)
const WIPER_PARK := 4.0                       # deg: parked, lying along the bottom
const WIPER_SWEEP := 118.0                    # deg: how far up a stroke goes
const WIPER_REACH := 0.64                     # m: the blade wipes out to here
const SHIFT_AT := [0.66, 0.72, 0.78, 0.84, 0.9]          # rev-dial fraction each shift light comes on at (x8000 rpm)
const SHIFT_COL := [Color(0.1, 1.0, 0.2), Color(0.1, 1.0, 0.2), Color(1.0, 0.8, 0.05), Color(1.0, 0.8, 0.05), Color(1.0, 0.1, 0.05)]
const STREAKS := 0.5                          # mud left in a wiped arc after each stroke (about 2 to see well)

var car
var map_board                                 # MapBoard (draws into a SubViewport)
var mud := 0.0                                # 0..1: how thick the mud is on the glass
var swept := [0.0, 0.0]                       # deg each wiper has swept since the last splat
var residue := [1.0, 1.0]                     # mud left inside each wiper's arc (1 = untouched)
var mud_seed := 0.0
var _mud_age := 0.0                            # s since the splat (the drips run down)
var _splats := PackedVector4Array()            # [x, y (m on the glass from its bottom-centre), radius, seed]
var wipe_strokes := 0                          # strokes left to do
var _wiper_t := 0.0
var _wiper_pivots: Array = []
var _mud_mat: ShaderMaterial
var _steer_node: Node3D
var _arms := {}                                # name -> [upper MeshInstance3D, lower MeshInstance3D]
var _heads := {}                               # seat -> Node3D (helmet), box crew
var _models := {}                              # seat -> CrewModel (the real crew)
var hands                                      # DriverHands: gloves on the rim, shuffling, the handbrake
var _wheel_turn := 0.0                         # the steering wheel's turn (rad)
var _needles := {}                             # "rpm" / "kmh" -> needle pivot
var _gear_label: Label3D
var _dial_font: Font
var _mirror_vp: SubViewport
var _mirror_cam: Camera3D
var _mirror_t := 0.0
var _mirror_at := Vector3(0.0, 0.84, -0.25)    # where its camera looks back from (just in front of the glass)
var _shift_leds: Array = []                    # their materials, left to right
var _trip_label: Label3D
var _mats := {}
var own := {}                                  # the car's own interior (parts.json "cockpit"); {}: ours
var eye_driver := EYE_DRIVER                   # where the crew's eyes are, and the rest of the layout
var eye_codriver := EYE_CODRIVER
var wheel_c := WHEEL_C
var wheel_tilt := WHEEL_TILT
var wheel_r := WHEEL_R
var ws_bottom := WS_BOTTOM
var ws_top := WS_TOP
var ws_w := WS_W
var wiper_x: Array = WIPER_X
var _wheel_axis := Vector3(0.0, -sin(WHEEL_TILT), cos(WHEEL_TILT))   # toward the driver
const HIPS := Vector3(0.0, -0.72, 0.02)        # a crew member's hips from their eyes (the cartoon crew, x1.2)
const BOARD := Vector3(-0.01, -0.35, -0.26)    # the map board from the co-driver's eyes (on the right: x mirrors)
const SEAT_SLIDE := 0.32                       # m the driver may slide their seat forward to reach its wheel (the seat probe can land on a thin seat's back: some room past a real seat track)
const WHEEL_CLEAR := 0.46                      # m the wheel's centre stays from their eyes, at the closest
const OWN_SCALE := 1.0                         # in a car's own interior the crew are real size (it is): their
                                               # eyes 0.6 m over their hips, 0.69 over their thighs' joints, which
                                               # tools/import_car.py puts 8 cm over the cushion

signal wiper_stroke


func build(the_car, stage) -> void:
	car = the_car
	own = car.cockpit_info() if car.has_method("cockpit_info") else {}
	if own.is_empty():
		_shell()
		_dash()
		_seats()
		_wheel()
		_details()
	else:
		_own_layout()
		_own_mirror()
	_windshield()
	_crew()
	if not own.is_empty():
		_reach_wheel()
	hands = DriverHands.new()
	hands.suit_colour = SUIT_D
	add_child(hands)
	hands.setup(wheel_c, wheel_tilt, wheel_r, Vector3.ZERO if own.is_empty() else _wheel_axis)
	if not own.is_empty():
		hands.use_model(_own_levers())
	if _models.has("driver"):
		_models.driver.hide_hands(true)
	map_board = MapBoard.new()
	add_child(map_board)
	map_board.setup(stage, the_car)
	var sx := signf(eye_codriver.x)
	map_board.position = eye_codriver + Vector3(BOARD.x * sx, BOARD.y, BOARD.z) * _crew_k()
	map_board.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(4.0) * sx, 0.0)
	_bake_static()
	_harnesses()


## The crew's size against ours (x1.2 cartoon): 1 in our cockpit.
func _crew_k() -> float:
	return 1.0 if own.is_empty() else OWN_SCALE / CrewModel.SCALE


## Whether it's the car's own interior (the crew are seen from outside too: it has windows).
func own_interior() -> bool:
	return not own.is_empty()


## Your eyes in your seat.
func eye_for(seat: String) -> Vector3:
	return eye_driver if seat == "driver" else eye_codriver


## The car's own interior: the layout from its parts.json, in the car's space.
func _own_layout() -> void:
	var off: Vector3 = car.model_offset()
	var w: Dictionary = own.wheel
	wheel_c = _v3(w.centre) + off
	_wheel_axis = _v3(w.axis).normalized()
	wheel_tilt = atan2(-_wheel_axis.y, _wheel_axis.z)
	wheel_r = float(w.radius)
	eye_driver = _v3(own.eye) + off
	eye_codriver = Vector3(-eye_driver.x, eye_driver.y, eye_driver.z)
	if own.has("windshield"):
		ws_bottom = _v3(own.windshield.bottom) + off
		ws_top = _v3(own.windshield.top) + off
		ws_w = float(own.windshield.width)
	var k := ws_w / WS_W
	wiper_x = [WIPER_X[0] * k, WIPER_X[1] * k]


## Its own rear-view mirror shows the road behind (our mirror's camera, on its glass).
func _own_mirror() -> void:
	if not own.has("mirror"):
		return
	var m: Dictionary = own.mirror
	var n := _v3(m.normal).normalized()              # toward the driver
	var y := (Vector3.UP - n * n.dot(Vector3.UP)).normalized()
	var mirror := Node3D.new()
	mirror.transform = Transform3D(Basis(y.cross(n), y, n), _v3(m.centre) + car.model_offset())
	add_child(mirror)
	_mirror_glass(mirror, Vector2(float(m.size[0]), float(m.size[1])) * 0.96, 0.002)
	_mirror_at = mirror.position + n * 0.03


## The driver slides their seat forward until their hands reach the wheel at a
## quarter to three with their arms nearly straight (a rally driver sits close; the
## crew's arms are short for their size), up to SEAT_SLIDE, but not so close the
## wheel is in their face. What's still out of reach the forearms stretch to
## (crew_model.gd): the gloves never come off the sleeves.
func _reach_wheel() -> void:
	var m = _models.get("driver")
	if m == null:
		return
	var z := _wheel_axis
	var y := (Vector3.UP - z * z.dot(Vector3.UP)).normalized()
	var x := y.cross(z)
	var need := 0.0
	for side in ["Left", "Right"]:
		var sh: Vector3 = m.bone(side + "Arm")
		var reach: float = sh.distance_to(m.bone(side + "ForeArm")) + m.bone(side + "ForeArm").distance_to(m.bone(side + "Hand"))
		var grip: Vector3 = wheel_c + x * wheel_r * (-1.0 if side == "Left" else 1.0)
		var v := grip - sh
		var r2 := pow(reach * 0.95, 2.0) - v.x * v.x - v.y * v.y
		if r2 > 0.0:
			need = maxf(need, -v.z - sqrt(r2))
		else:
			need = SEAT_SLIDE
	var room := Vector2(eye_driver.y - wheel_c.y, eye_driver.z - wheel_c.z).length() - WHEEL_CLEAR
	var f := clampf(need, 0.0, minf(SEAT_SLIDE, maxf(room, 0.0)))
	eye_driver.z -= f
	m.position.z -= f


## Its own gear lever and handbrake for the hands (driver_hands.gd use_model).
func _own_levers() -> Dictionary:
	var off: Vector3 = car.model_offset()
	var cfg := {"side": str(own.get("side", "left")), "gearbox": str(own.get("gearbox", "h5"))}
	if own.has("shifter") and car.cockpit_nodes.has("shifter"):
		cfg.shifter = {"pivot": _v3(own.shifter.pivot) + off, "knob": _v3(own.shifter.knob) + off,
			"node": car.cockpit_nodes.shifter}
	if own.has("handbrake") and car.cockpit_nodes.has("handbrake"):
		cfg.handbrake = {"pivot": _v3(own.handbrake.pivot) + off, "grip": _v3(own.handbrake.grip) + off,
			"node": car.cockpit_nodes.handbrake}
	return cfg


static func _v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## The mirror works: a little camera just in front of it looks back down the car
## (the crew's helmets, the cage, the rear window, the road behind) into a
## low-resolution texture on the glass, flipped like a mirror. It renders about
## 30 times a second, and not at all when nobody's in the cockpit view (the chase cam).
func _mirror_glass(mirror: Node3D, size := Vector2(0.266, 0.052), lift := 0.0095) -> void:
	_mirror_vp = SubViewport.new()
	_mirror_vp.name = "MirrorView"
	_mirror_vp.size = Vector2i(400, maxi(32, roundi(400.0 * size.y / size.x)))
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_mirror_vp)
	_mirror_cam = Camera3D.new()
	_mirror_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_mirror_cam.fov = 52.0
	_mirror_cam.near = 0.05
	_mirror_cam.far = 220.0
	_mirror_cam.cull_mask = 0xFFFFF & ~(1 << 1)        # not the driver's own helmet
	_mirror_vp.add_child(_mirror_cam)
	var glass := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	glass.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _mirror_vp.get_texture()
	m.albedo_color = Color(0.92, 0.94, 0.97)            # a slight tint, like real mirror glass
	m.uv1_scale = Vector3(-1.0, 1.0, 1.0)              # left and right swapped: a mirror
	m.uv1_offset = Vector3(1.0, 0.0, 0.0)
	glass.material_override = m
	glass.position = Vector3(0, 0, lift)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mirror.add_child(glass)


func _mirror(dt: float) -> void:
	if _mirror_vp == null:
		return
	if not is_visible_in_tree():
		_mirror_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_mirror_t += dt
	if _mirror_t < 1.0 / 30.0:
		return
	_mirror_t = 0.0
	# just in front of the glass (so it doesn't see its own back), looking back and a touch down
	_mirror_cam.global_transform = global_transform * Transform3D(
		Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, deg_to_rad(-4.0)), _mirror_at)
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## Paint the shell and the cage the car's colour (a white car is white inside, a
## blue one blue): every material made in RED takes it.
func set_paint(c: Color) -> void:
	for m in _mats.values():
		if not m.has_meta("paint") and (m as StandardMaterial3D).albedo_color.is_equal_approx(RED):
			m.set_meta("paint", true)
		if m.has_meta("paint"):
			(m as StandardMaterial3D).albedo_color = c


## Every part of the cockpit that never moves (boxes, tubes, the dials' faces and
## ticks, the switches...) is baked into one mesh per material: a few hundred
## little parts would be a few hundred draw calls, and more again for the
## shadows. Tiny ones (< 3 cm) cast no shadow. What moves stays as it is: the
## wheel, the hands, the needles, the wipers, the crew, the map board, the shift
## lights (their own materials), the glb models.
func _bake_static() -> void:
	var keep_out := [_steer_node, hands, map_board]
	keep_out.append_array(_wiper_pivots)
	keep_out.append_array(_needles.values())
	keep_out.append_array(_models.values())
	keep_out.append_array(_heads.values())
	for pair in _arms.values():
		keep_out.append_array(pair)
	var shared := _mats.values()
	var parts := {}                                   # "<material id>:<shadow>" -> mesh arrays
	var mats := {}
	for mi in find_children("*", "MeshInstance3D", true, false):
		if not (mi.mesh is PrimitiveMesh) or not shared.has(mi.material_override):
			continue
		var xf: Transform3D = mi.transform
		var n: Node = mi.get_parent()
		var moving := keep_out.has(mi)
		while n != self and not moving:
			moving = keep_out.has(n)
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		if moving:
			continue
		var size: Vector3 = mi.mesh.get_aabb().size * xf.basis.get_scale()
		var shadow: bool = mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and maxf(size.x, maxf(size.y, size.z)) > 0.03
		var key := "%d:%s" % [mi.material_override.get_instance_id(), shadow]
		mats[key] = mi.material_override
		DriverHands._add(parts, key, mi.mesh, xf)
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	for shadow in [true, false]:
		var group := {}
		for key in parts:
			if key.ends_with(str(shadow)):
				group[key] = parts[key]
		if group.is_empty():
			continue
		var baked := MeshInstance3D.new()
		baked.name = "Static" + ("" if shadow else "NoShadow")
		baked.mesh = DriverHands._bake(group, mats)
		baked.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(baked)


# ── geometry helpers ──────────────────────────────────────────────────────

func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var key := c.to_html() + str(rough)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		_mats[key] = m
	return _mats[key]


func _box(size: Vector3, at: Vector3, c: Color, rot := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = at
	mi.rotation = rot
	(parent if parent else self).add_child(mi)
	return mi


## A tube from a to b (roll cage, pillars, arms).
func _tube(a: Vector3, b: Vector3, r: float, c: Color, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 1.0
	cm.radial_segments = 6
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _mat(c)
	(parent if parent else self).add_child(mi)
	_place_tube(mi, a, b)
	return mi


func _place_tube(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 1e-4:
		return
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y * l, z), (a + b) * 0.5)


# ── the car ───────────────────────────────────────────────────────────────

func _shell() -> void:
	# hood: from the cowl down to the nose (what you see out of the windshield)
	var hood := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(1.56, 0.06, 1.2)
	hood.mesh = hm
	hood.material_override = _mat(RED, 0.55)
	hood.position = Vector3(0.0, 0.25, -1.36)
	hood.rotation.x = deg_to_rad(5.0)
	add_child(hood)
	_box(Vector3(1.62, 0.5, 0.3), Vector3(0.0, -0.05, -1.92), RED)          # nose
	_box(Vector3(1.5, 0.1, 0.12), Vector3(0.0, 0.3, -0.76), DARK)           # cowl / wiper well
	# roof and its edges
	_box(Vector3(1.46, 0.05, 1.65), Vector3(0.0, 0.96, 0.52), RED)
	_box(Vector3(1.5, 0.08, 0.08), Vector3(0.0, 0.93, -0.3), RED)           # windshield header
	# A-pillars (the red bars either side of the windshield)
	for sx in [-1.0, 1.0]:
		_tube(Vector3(0.74 * sx, 0.3, -0.76), Vector3(0.72 * sx, 0.93, -0.3), 0.04, RED)
		_tube(Vector3(0.72 * sx, 0.93, -0.3), Vector3(0.72 * sx, 0.93, 1.32), 0.04, RED)   # roof rails
		_tube(Vector3(0.74 * sx, 0.93, 1.32), Vector3(0.78 * sx, 0.1, 1.55), 0.06, RED)    # C-pillar
		# doors: flat carbon cards below the window line (stripped: no trim), a
		# red fabric pull strap and the release
		_box(Vector3(0.05, 0.62, 1.2), Vector3(0.8 * sx, 0.02, 0.2), CARBON)
		_box(Vector3(0.012, 0.5, 1.0), Vector3(0.772 * sx, 0.0, 0.22), CARBON_HI)
		for dz in [-0.12, 0.2]:
			_box(Vector3(0.022, 0.012, 0.02), Vector3(0.758 * sx, 0.2, dz), DARK)
		_box(Vector3(0.008, 0.028, 0.34), Vector3(0.75 * sx, 0.17, 0.04), STRAP)
		_box(Vector3(0.018, 0.02, 0.06), Vector3(0.762 * sx, 0.24, -0.25), Color(0.3, 0.3, 0.32))
		# mirrors
		_box(Vector3(0.05, 0.05, 0.12), Vector3(0.83 * sx, 0.36, -0.62), RED)
		_box(Vector3(0.14, 0.1, 0.05), Vector3(0.92 * sx, 0.38, -0.66), RED)
		_box(Vector3(0.12, 0.08, 0.01), Vector3(0.92 * sx, 0.38, -0.63), Color(0.7, 0.8, 0.85), Vector3.ZERO)
		# roll cage: main hoop behind the seats, a door bar, a tube up the pillar
		_tube(Vector3(0.66 * sx, -0.3, 0.62), Vector3(0.62 * sx, 0.9, 0.62), 0.03, RED)
		_tube(Vector3(0.68 * sx, -0.1, 0.6), Vector3(0.7 * sx, 0.18, -0.55), 0.028, RED)
		_tube(Vector3(0.66 * sx, 0.9, 0.62), Vector3(0.66 * sx, 0.88, -0.28), 0.028, RED)
	_tube(Vector3(-0.62, 0.9, 0.62), Vector3(0.62, 0.9, 0.62), 0.03, RED)
	_tube(Vector3(-0.62, 0.9, 0.62), Vector3(0.62, -0.25, 0.62), 0.026, RED)   # the diagonal
	# floor (bare painted metal) and back
	_box(Vector3(1.5, 0.04, 2.0), Vector3(0.0, -0.32, 0.1), Color(0.3, 0.3, 0.31))
	_box(Vector3(1.5, 0.5, 0.05), Vector3(0.0, 0.1, 1.5), GREY)
	# body sides, seen from outside (the other crew, the menu)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.05, 0.55, 3.5), Vector3(0.82 * sx, -0.08, 0.0), RED)
	_box(Vector3(1.62, 0.55, 0.12), Vector3(0.0, -0.05, 1.82), RED)          # tailgate


func _dash() -> void:
	var dash := _box(Vector3(1.44, 0.24, 0.34), Vector3(0.0, 0.2, -0.48), FLOCK)    # the dash, black flock
	dash.material_override = _mat(FLOCK, 1.0)
	_box(Vector3(1.44, 0.05, 0.4), Vector3(0.0, 0.33, -0.52), Color(0.09, 0.09, 0.1)).material_override = _mat(Color(0.09, 0.09, 0.1), 1.0)
	_box(Vector3(0.42, 0.14, 0.04), Vector3(-0.37, 0.24, -0.31), DARK)        # instrument hood
	_box(Vector3(0.36, 0.02, 0.02), Vector3(0.38, 0.27, -0.3), CARBON_HI)     # a ledge in front of the co-driver
	_box(Vector3(0.22, 0.2, 0.3), Vector3(0.0, -0.18, -0.15), Color(0.26, 0.26, 0.27))   # tunnel (bare, painted)
	_switch_panel()
	# the sequential gear lever's rubber boot (the lever moves: driver_hands.gd)
	var lever_base: Vector3 = DriverHands.GEAR_BASE
	var boot := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.045
	bm.height = 0.05
	bm.radial_segments = 10
	bm.rings = 4
	boot.mesh = bm
	boot.material_override = _mat(Color(0.05, 0.05, 0.05), 0.95)
	boot.position = lever_base + Vector3(0.0, 0.012, 0.0)
	add_child(boot)


## The switch panel in the middle of the dash, turned a little to the driver: two
## rows of toggle switches with their labels, the ignition under a red flip
## guard, the START and FIRE (extinguisher) buttons, and the warning lights.
func _switch_panel() -> void:
	var panel := Node3D.new()
	panel.position = Vector3(-0.03, 0.2, -0.305)
	panel.rotation.y = deg_to_rad(14.0)
	add_child(panel)
	_box(Vector3(0.3, 0.17, 0.008), Vector3.ZERO, Color(0.17, 0.17, 0.18), Vector3.ZERO, panel).material_override = _mat(Color(0.17, 0.17, 0.18), 0.35)
	var names := ["IGN", "FUEL", "FAN", "WIPE", "WASH", "LIGHTS", "SPOTS", "DEMIST", "HORN", "RAIN"]
	for i in names.size():
		var p := Vector3(-0.115 + (i % 5) * 0.046, 0.04 - (i / 5) * 0.062, 0.004)
		_box(Vector3(0.013, 0.013, 0.005), p, Color(0.7, 0.7, 0.72), Vector3.ZERO, panel)          # the nut
		_tube(p + Vector3(0, 0, 0.002), p + Vector3(0, 0.009, 0.018), 0.0026, Color(0.85, 0.85, 0.88), panel)   # the bat, up = on
		var l := _dial_text(names[i], 24, Color(0.92, 0.92, 0.9))
		l.position = p + Vector3(0.0, -0.017, 0.0015)
		panel.add_child(l)
	# the red flip guard over the ignition switch, lifted
	_box(Vector3(0.02, 0.028, 0.006), Vector3(-0.115, 0.06, 0.016), Color(0.85, 0.08, 0.06), Vector3(deg_to_rad(-55.0), 0, 0), panel)
	# START (green) and FIRE (red, the white extinguisher "E" on it) buttons
	for b in [[0.122, 0.04, Color(0.1, 0.65, 0.2), "START"], [0.122, -0.022, Color(0.85, 0.08, 0.06), "FIRE"]]:
		var btn := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.012
		cyl.bottom_radius = 0.014
		cyl.height = 0.01
		cyl.radial_segments = 12
		btn.mesh = cyl
		btn.material_override = _mat(b[2], 0.4)
		btn.rotation.x = PI / 2.0
		btn.position = Vector3(b[0], b[1], 0.008)
		panel.add_child(btn)
		var l := _dial_text(b[3], 22, Color(0.92, 0.92, 0.9))
		l.position = Vector3(b[0], b[1] - 0.021, 0.0015)
		panel.add_child(l)
	var e := _dial_text("E", 36, Color(1, 1, 1))
	e.position = Vector3(0.122, -0.022, 0.0135)
	panel.add_child(e)
	# warning lights along the top: oil, water, fuel (dark until something's wrong)
	for i in 3:
		var w := MeshInstance3D.new()
		var wm := SphereMesh.new()
		wm.radius = 0.0045
		wm.height = 0.005
		wm.radial_segments = 8
		wm.rings = 3
		w.mesh = wm
		w.material_override = _mat([Color(0.5, 0.06, 0.04), Color(0.5, 0.35, 0.03), Color(0.45, 0.4, 0.05)][i], 0.3)
		w.position = Vector3(0.09 + i * 0.016, 0.07, 0.005)
		panel.add_child(w)


## Small black print on a dial's face (Label3D, flat on it).
func _dial_text(text: String, size: int, c: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = _dial_font
	l.font_size = size
	l.pixel_size = 0.0002
	l.modulate = c
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return l


## The bits that make it a rally car: dials with needles, the gear, the co-driver's
## trip meter, an extinguisher between the seats, padding on the cage, mats.
func _details() -> void:
	_dial_font = load("res://assets/fonts/Oswald-Medium.woff2")
	# instrument cluster above the wheel's hub, seen through its top: rev counter
	# (left) and speedo in a binnacle, needles move
	_box(Vector3(0.3, 0.13, 0.08), Vector3(-0.36, 0.385, -0.37), Color(0.07, 0.07, 0.08), Vector3(deg_to_rad(-25.0), 0, 0))
	_box(Vector3(0.32, 0.015, 0.11), Vector3(-0.36, 0.455, -0.35), Color(0.07, 0.07, 0.08), Vector3(deg_to_rad(-10.0), 0, 0))
	var face := _mat(Color(0.93, 0.93, 0.9), 0.6)
	var tilt := Vector3(deg_to_rad(-70.0), 0, 0)
	for d in [[-0.45, "rpm"], [-0.29, "kmh"]]:
		var dial := Node3D.new()
		dial.position = Vector3(d[0] + 0.01, 0.385, -0.33)
		dial.rotation.x = deg_to_rad(-25.0)
		add_child(dial)
		var bezel := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.05
		bm.bottom_radius = 0.05
		bm.height = 0.012
		bm.radial_segments = 16
		bezel.mesh = bm
		bezel.material_override = _mat(Color(0.05, 0.05, 0.05), 0.4)
		bezel.rotation.x = PI / 2.0
		dial.add_child(bezel)
		var f := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = 0.042
		fm.bottom_radius = 0.042
		fm.height = 0.004
		fm.radial_segments = 16
		f.mesh = fm
		f.material_override = face
		f.rotation.x = PI / 2.0
		f.position.z = 0.006
		dial.add_child(f)
		for i in 17:                                  # tick marks round the dial: long ones numbered, short between
			var a := deg_to_rad(-135.0 + 270.0 * i / 16.0)
			var major := i % 2 == 0
			var red: bool = d[1] == "rpm" and i >= 14
			var tk := _box(Vector3(0.0028 if major else 0.0018, 0.008 if major else 0.0045, 0.002),
				Vector3(sin(a), cos(a), 0.0) * (0.035 if major else 0.0368) + Vector3(0, 0, 0.009),
				Color(0.85, 0.1, 0.1) if red else Color(0.1, 0.1, 0.1), Vector3(0, 0, -a), dial)
			tk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# the numbers: revs x1000 on every long tick, km/h on every other one
			var label := ""
			if major and d[1] == "rpm":
				label = str(i / 2)
			elif i % 4 == 0 and d[1] == "kmh":
				label = str(i * 25 / 2)
			if label != "":
				var num := _dial_text(label, 40 if label.length() < 3 else 34, Color(0.75, 0.06, 0.04) if red else Color(0.08, 0.08, 0.09))
				num.position = Vector3(sin(a), cos(a), 0.0) * (0.0245 if label.length() < 3 else 0.0225) + Vector3(0, 0, 0.0085)
				dial.add_child(num)
		if d[1] == "rpm":                             # the red line: an arc from 7 to 8
			for j in 6:
				var a := deg_to_rad(-135.0 + 270.0 * (7.0 + (j + 0.5) / 6.0) / 8.0)
				_box(Vector3(0.0046, 0.0026, 0.0015), Vector3(sin(a), cos(a), 0.0) * 0.0392 + Vector3(0, 0, 0.0088),
					Color(0.85, 0.1, 0.1), Vector3(0, 0, -a), dial).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cap := _dial_text("x1000 RPM" if d[1] == "rpm" else "KM/H", 22, Color(0.3, 0.3, 0.32))
		cap.position = Vector3(0.0, -0.017, 0.0085)
		dial.add_child(cap)
		var needle := Node3D.new()
		needle.position.z = 0.011
		dial.add_child(needle)
		_box(Vector3(0.003, 0.036, 0.002), Vector3(0, 0.016, 0), Color(0.9, 0.15, 0.05), Vector3.ZERO, needle)
		var hub := MeshInstance3D.new()                # the cap over the needle's pivot
		var hm := CylinderMesh.new()
		hm.top_radius = 0.0055
		hm.bottom_radius = 0.0055
		hm.height = 0.004
		hm.radial_segments = 10
		hub.mesh = hm
		hub.material_override = _mat(Color(0.06, 0.06, 0.06), 0.4)
		hub.rotation.x = PI / 2.0
		hub.position.z = 0.0125
		dial.add_child(hub)
		_needles[d[1]] = needle
	# shift lights along the front of the binnacle's hood: green, yellow, red as the
	# revs climb to the red line, all flashing on the limiter
	for i in SHIFT_AT.size():
		var led := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.0065
		lm.height = 0.009
		lm.radial_segments = 10
		lm.rings = 4
		led.mesh = lm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = SHIFT_COL[i] * 0.25
		mat.emission_enabled = true
		mat.emission = SHIFT_COL[i]
		mat.emission_energy_multiplier = 0.0
		mat.roughness = 0.3
		led.material_override = mat
		led.rotation.x = deg_to_rad(80.0)
		led.position = Vector3(-0.36 + (i - (SHIFT_AT.size() - 1) * 0.5) * 0.019, 0.448, -0.29)
		led.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(led)
		_shift_leds.append(mat)
	_box(Vector3(0.13, 0.016, 0.012), Vector3(-0.36, 0.448, -0.298), Color(0.05, 0.05, 0.05))
	# the gear, a green digit in a little display on the binnacle between the dials
	var gear_box := Node3D.new()
	gear_box.position = Vector3(-0.37, 0.372, -0.318)
	gear_box.rotation.x = deg_to_rad(-25.0)
	add_child(gear_box)
	_box(Vector3(0.036, 0.04, 0.006), Vector3.ZERO, Color(0.02, 0.03, 0.025), Vector3.ZERO, gear_box)
	_gear_label = Label3D.new()
	_gear_label.text = "1"
	_gear_label.font = _dial_font
	_gear_label.font_size = 64
	_gear_label.pixel_size = 0.0005
	_gear_label.modulate = Color(0.3, 1.0, 0.4)
	_gear_label.outline_size = 0
	_gear_label.shaded = false
	_gear_label.position = Vector3(0.0, 0.0, 0.0035)
	gear_box.add_child(_gear_label)
	# the co-driver's trip meter on top of the dash: stage distance, in green
	_box(Vector3(0.16, 0.06, 0.06), Vector3(0.38, 0.385, -0.42), Color(0.06, 0.06, 0.07), Vector3(deg_to_rad(-20.0), 0, 0))
	_trip_label = Label3D.new()
	_trip_label.text = "0.00"
	_trip_label.font_size = 64
	_trip_label.pixel_size = 0.0008
	_trip_label.modulate = Color(0.35, 1.0, 0.45)
	_trip_label.outline_size = 0
	_trip_label.position = Vector3(0.38, 0.39, -0.387)
	_trip_label.rotation.x = deg_to_rad(-20.0)
	add_child(_trip_label)
	# fire extinguisher between the seats
	var ext := MeshInstance3D.new()
	var em := CylinderMesh.new()
	em.top_radius = 0.045
	em.bottom_radius = 0.045
	em.height = 0.34
	em.radial_segments = 10
	ext.mesh = em
	ext.material_override = _mat(Color(0.8, 0.06, 0.05), 0.35)
	ext.rotation.x = PI / 2.0
	ext.position = Vector3(0.0, -0.24, 0.42)
	add_child(ext)
	_box(Vector3(0.05, 0.03, 0.05), Vector3(0.0, -0.24, 0.24), Color(0.15, 0.15, 0.15))
	# black foam padding on the cage where heads could hit it, a rubber mat for the
	# driver, a ribbed aluminium footrest for the co-driver to brace on
	for sx in [-1.0, 1.0]:
		_tube(Vector3(0.66 * sx, 0.9, 0.45), Vector3(0.66 * sx, 0.89, 0.0), 0.042, Color(0.07, 0.07, 0.08))
		_tube(Vector3(0.69 * sx, -0.04, 0.45), Vector3(0.7 * sx, 0.12, -0.3), 0.04, Color(0.07, 0.07, 0.08))
	_box(Vector3(0.5, 0.012, 0.5), Vector3(-0.37, -0.295, -0.2), Color(0.16, 0.16, 0.17))
	var rest := Node3D.new()
	rest.position = Vector3(0.37, -0.2, -0.52)
	rest.rotation.x = deg_to_rad(48.0)
	add_child(rest)
	_box(Vector3(0.38, 0.006, 0.3), Vector3.ZERO, ALU, Vector3.ZERO, rest).material_override = _mat(ALU, 0.35)
	for i in 7:
		_box(Vector3(0.36, 0.008, 0.008), Vector3(0.0, 0.006, -0.12 + i * 0.04), ALU * Color(0.85, 0.85, 0.85), Vector3.ZERO, rest)
	# cage: a bar across the roof and the harness bar behind the seats (the
	# harnesses come off it: harness.gd)
	_tube(Vector3(-0.66, 0.9, 0.1), Vector3(0.66, 0.9, 0.1), 0.026, RED)
	_tube(Vector3(-0.64, HARNESS_BAR.x, HARNESS_BAR.y), Vector3(0.64, HARNESS_BAR.x, HARNESS_BAR.y), 0.024, RED)
	# the wide rear-view mirror at the top of the screen, on a stalk from the header
	_tube(Vector3(0.0, 0.912, -0.285), Vector3(0.0, 0.858, -0.272), 0.008, DARK)
	var mirror := Node3D.new()
	mirror.position = Vector3(0.0, 0.84, -0.265)                  # 8 cm clear of the glass and the sun strip
	mirror.rotation = Vector3(deg_to_rad(-8.0), deg_to_rad(-10.0), 0.0)     # angled at the driver
	add_child(mirror)
	_box(Vector3(0.28, 0.065, 0.018), Vector3.ZERO, Color(0.05, 0.05, 0.05), Vector3.ZERO, mirror)
	_mirror_glass(mirror)
	# the sun strip across the top of the screen: dark vinyl, its print back to front from in here
	var up := (WS_TOP - WS_BOTTOM).normalized()
	var n := Vector3.RIGHT.cross(up).normalized()
	var strip := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(WS_W, 0.075)
	strip.mesh = sq
	strip.material_override = _mat(Color(0.05, 0.06, 0.09), 0.9)
	strip.transform = Transform3D(Basis(Vector3.RIGHT, up, n), WS_TOP - up * 0.0375 + n * 0.014)
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(strip)
	var print_ := Label3D.new()
	print_.text = "SHOTGUN RALLY"
	print_.font = load("res://assets/fonts/Oswald-Bold.woff2")
	print_.font_size = 96
	print_.pixel_size = 0.00045
	print_.modulate = Color(0.85, 0.85, 0.88, 0.45)
	print_.outline_size = 0
	print_.shaded = false
	print_.transform = Transform3D(Basis(-Vector3.RIGHT, up, n), WS_TOP - up * 0.0375 + n * 0.016)
	print_.double_sided = true
	add_child(print_)
	# the co-driver's map lamp: a goose neck off the dash top, bent over the map
	var neck := [Vector3(0.56, 0.355, -0.4), Vector3(0.555, 0.41, -0.375), Vector3(0.54, 0.445, -0.33), Vector3(0.52, 0.455, -0.29)]
	for i in 3:
		_tube(neck[i], neck[i + 1], 0.005, Color(0.08, 0.08, 0.08))
	var lamp := _tube(neck[3], neck[3] + Vector3(-0.012, -0.02, 0.018), 0.012, Color(0.08, 0.08, 0.08))
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the spare wheel, flat on the floor behind the seats, strapped down
	var tyre := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.3
	tm.bottom_radius = 0.3
	tm.height = 0.2
	tm.radial_segments = 16
	tyre.mesh = tm
	tyre.material_override = _mat(Color(0.07, 0.07, 0.07), 0.9)
	tyre.position = Vector3(0.0, -0.2, 1.08)
	add_child(tyre)
	var rim := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.19
	rm.bottom_radius = 0.19
	rm.height = 0.205
	rm.radial_segments = 16
	rim.mesh = rm
	rim.material_override = _mat(Color(0.85, 0.85, 0.87), 0.4)
	rim.position = Vector3(0.0, -0.2, 1.08)
	add_child(rim)
	for a in [0.6, -0.6]:
		_box(Vector3(0.05, 0.006, 0.66), Vector3(0.0, -0.096, 1.08), STRAP, Vector3(0.0, a, 0.0))


func _seats() -> void:
	# Higgsfield bucket seats (assets/models/seat.glb); the box seats if it's missing
	const SEAT_MODEL := "res://assets/models/seat.glb"
	for x in [-0.37, 0.37]:
		if ResourceLoader.exists(SEAT_MODEL):
			var seat: Node3D = load(SEAT_MODEL).instantiate()
			seat.scale = Vector3.ONE * 0.52                  # 1.9 units tall -> ~1 m, rails to headrest
			seat.rotation.y = PI                             # it faces +z; the car faces -z
			seat.position = Vector3(x, -0.30 + 0.952 * 0.52, 0.36)
			add_child(seat)
			continue
		_box(Vector3(0.5, 0.14, 0.52), Vector3(x, -0.22, 0.3), SEAT)          # cushion
		_box(Vector3(0.5, 0.75, 0.14), Vector3(x, 0.2, 0.6), SEAT, Vector3(deg_to_rad(-12.0), 0, 0))
		_box(Vector3(0.12, 0.42, 0.4), Vector3(x - 0.24, -0.02, 0.38), SEAT * 0.9)   # bolsters
		_box(Vector3(0.12, 0.42, 0.4), Vector3(x + 0.24, -0.02, 0.38), SEAT * 0.9)


## The steering wheel: a deep-dish rally wheel like a Momo Mod.08 (350 mm,
## 88 mm of dish, a ~30 mm black suede rim with a yellow marker at the top,
## three black aluminium spokes with slots machined out, a horn button and six
## bolts on the hub plate) on a quick-release boss with a silver collar, on the
## column. The rim's plane is where the gloves grip (driver_hands.gd); the hub is
## WHEEL_DISH in front of it. One mesh, a surface per material.
func _wheel() -> void:
	var axis := Vector3(0.0, sin(WHEEL_TILT), cos(WHEEL_TILT))        # toward the driver
	var boss_back := WHEEL_C - axis * (WHEEL_DISH + 0.06)
	_tube(Vector3(-0.37, 0.12, -0.46), boss_back, 0.025, DARK)        # column
	_steer_node = Node3D.new()
	_steer_node.position = WHEEL_C
	_steer_node.rotation.x = WHEEL_TILT
	add_child(_steer_node)
	var parts := {}
	var mats := {
		"suede": _mat(Color(0.055, 0.055, 0.06), 1.0),
		"marker": _mat(Color(1.0, 0.78, 0.1), 0.7),
		"alu": _mat(Color(0.07, 0.07, 0.075), 0.32),
		"silver": _mat(Color(0.72, 0.73, 0.75), 0.25),
		"red": _mat(Color(0.85, 0.1, 0.08), 0.4),
	}
	var flat := Basis(Vector3.RIGHT, PI / 2.0)                         # a Y-axis mesh turned to face the driver (+z)
	# the rim, and its yellow 12 o'clock marker sitting just proud of the suede
	var rim := TorusMesh.new()
	rim.inner_radius = WHEEL_R - RIM_TUBE
	rim.outer_radius = WHEEL_R + RIM_TUBE
	rim.rings = 64
	rim.ring_segments = 14
	DriverHands._add(parts, "suede", rim, Transform3D(flat))
	DriverHands._add(parts, "marker", _arc_tube(WHEEL_R, RIM_TUBE + 0.0007, deg_to_rad(84.0), deg_to_rad(96.0), 6), Transform3D.IDENTITY)
	# three spokes: from the hub plate out and back to the rim, each two rails
	# with bridges between them (the machined slots)
	var hub_z := -WHEEL_DISH
	for a in [0.0, PI, -PI / 2.0]:
		var dir := Vector3(cos(a), sin(a), 0.0)
		var tang := Vector3(-sin(a), cos(a), 0.0)
		var p0 := dir * 0.045 + Vector3(0, 0, hub_z + 0.004)
		var p1 := dir * (WHEEL_R - RIM_TUBE * 0.6) + Vector3(0, 0, -0.006)
		var along := (p1 - p0).normalized()
		var length := p0.distance_to(p1)
		var normal := along.cross(tang).normalized()
		for side in [-1.0, 1.0]:
			var off: Vector3 = tang * side * 0.0125
			DriverHands._add(parts, "alu", _box_mesh(Vector3(0.012, length, 0.0045)),
				Transform3D(Basis(tang, along, normal), (p0 + p1) * 0.5 + off))
		for b in [0.03, 0.5, 0.96]:                                    # the bridges: two long slots between them
			DriverHands._add(parts, "alu", _box_mesh(Vector3(0.037, 0.016, 0.0045)),
				Transform3D(Basis(tang, along, normal), p0.lerp(p1, b)))
	# the hub plate, its six bolts, the horn button (a red ring on black)
	var plate := CylinderMesh.new()
	plate.top_radius = 0.052
	plate.bottom_radius = 0.052
	plate.height = 0.008
	plate.radial_segments = 24
	DriverHands._add(parts, "alu", plate, Transform3D(flat, Vector3(0, 0, hub_z)))
	for i in 6:
		var ang := TAU * i / 6.0 + PI / 6.0
		var bolt := CylinderMesh.new()
		bolt.top_radius = 0.0045
		bolt.bottom_radius = 0.0045
		bolt.height = 0.006
		bolt.radial_segments = 6
		DriverHands._add(parts, "silver", bolt, Transform3D(flat, Vector3(cos(ang), sin(ang), 0) * 0.043 + Vector3(0, 0, hub_z + 0.006)))
	var button := CylinderMesh.new()
	button.top_radius = 0.032
	button.bottom_radius = 0.034
	button.height = 0.012
	button.radial_segments = 24
	DriverHands._add(parts, "alu", button, Transform3D(flat, Vector3(0, 0, hub_z + 0.01)))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.016
	ring.outer_radius = 0.021
	ring.rings = 24
	ring.ring_segments = 6
	DriverHands._add(parts, "red", ring, Transform3D(flat.scaled(Vector3(1.0, 1.0, 0.25)), Vector3(0, 0, hub_z + 0.0165)))
	# the quick-release boss and its collar, behind the plate
	var boss := CylinderMesh.new()
	boss.top_radius = 0.026
	boss.bottom_radius = 0.03
	boss.height = 0.06
	boss.radial_segments = 16
	DriverHands._add(parts, "alu", boss, Transform3D(flat, Vector3(0, 0, hub_z - 0.034)))
	var collar := CylinderMesh.new()
	collar.top_radius = 0.032
	collar.bottom_radius = 0.032
	collar.height = 0.014
	collar.radial_segments = 20
	DriverHands._add(parts, "silver", collar, Transform3D(flat, Vector3(0, 0, hub_z - 0.03)))
	var w := MeshInstance3D.new()
	w.name = "SteeringWheel"
	w.mesh = DriverHands._bake(parts, mats)
	_steer_node.add_child(w)


static func _box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## A tube of radius r along an arc of radius R in the XY plane, from angle a0 to a1.
static func _arc_tube(R: float, r: float, a0: float, a1: float, seg: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var nm := PackedVector3Array()
	var idx := PackedInt32Array()
	var ring := 10
	for i in seg + 1:
		var a := lerpf(a0, a1, float(i) / seg)
		var out := Vector3(cos(a), sin(a), 0.0)
		for j in ring + 1:
			var b := TAU * j / ring
			var n := out * cos(b) + Vector3.BACK * sin(b)
			v.append(out * R + n * r)
			nm.append(n)
	for i in seg:
		for j in ring:
			var q := i * (ring + 1) + j
			idx.append_array([q, q + ring + 1, q + 1, q + 1, q + ring + 1, q + ring + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nm
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _windshield() -> void:
	var up := (ws_top - ws_bottom)
	var h := up.length()
	var y := up / h
	var n := Vector3.RIGHT.cross(y).normalized()               # points into the cabin
	var basis := Basis(Vector3.RIGHT, y, n)
	var side := 1.0 if own.is_empty() else -1.0               # a car's own glass: the mud and the wipers go outside it
	# the mud: one quad over the glass; the shader covers it and cuts out the wiped arcs
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(ws_w, h)
	q.mesh = qm
	q.transform = Transform3D(basis, (ws_bottom + ws_top) * 0.5 + n * (0.01 if own.is_empty() else -0.012))
	_mud_mat = ShaderMaterial.new()
	_mud_mat.shader = _mud_shader()
	q.material_override = _mud_mat
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(q)
	_mud_mat.set_shader_parameter("size_m", Vector2(ws_w, h))
	_mud_mat.set_shader_parameter("pivots", PackedVector2Array([Vector2(wiper_x[0], 0.04), Vector2(wiper_x[1], 0.04)]))
	_mud_mat.set_shader_parameter("reach", WIPER_REACH * ws_w / WS_W)
	_mud_mat.set_shader_parameter("park", deg_to_rad(WIPER_PARK))
	# two wipers, pivoting at the bottom of the glass, parked flat
	for px in wiper_x:
		var pivot := Node3D.new()
		pivot.transform = Transform3D(basis, ws_bottom + Vector3(px, 0, 0) + y * 0.04 + n * 0.02 * side * (1.0 if side > 0.0 else 1.5))
		add_child(pivot)
		var arm := Node3D.new()
		pivot.add_child(arm)
		var k := WIPER_REACH / 0.64 * ws_w / WS_W
		_box(Vector3(0.6 * k, 0.012, 0.012), Vector3(0.3 * k, 0.0, 0.0), DARK, Vector3.ZERO, arm)
		_box(Vector3(0.62 * k, 0.02, 0.02), Vector3(0.33 * k, 0.02, 0.0), Color(0.05, 0.05, 0.05), Vector3.ZERO, arm)
		arm.rotation.z = deg_to_rad(WIPER_PARK)
		arm.visible = own.is_empty()                       # its own wipers are parked there: ours only show wiping
		_wiper_pivots.append(arm)


func _mud_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform float mud = 0.0;             // 0..1: 1 = fresh; lower thins the splats down to their middles
uniform vec2 size_m;                 // the glass, metres
uniform vec4 splats[8];              // x, y (m from the bottom-centre), radius, seed
uniform int count = 0;
uniform float age = 0.0;             // s since the splat: the drips run down
uniform vec2 pivots[2];              // wiper pivots, metres from the bottom-centre
uniform float swept[2];              // radians each wiper has swept (from park)
uniform float residue[2];            // mud left inside each wiped arc
uniform float reach = 0.64;
uniform float park = 0.07;
uniform float seed = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
// how far inside one splat p is, in its radii (> 0 inside): a lumpy blob with
// spikes, droplets flicked out around it, and drips running down from it
float splat(vec2 p, vec4 s) {
	vec2 d = p - s.xy;
	float R = s.z;
	float sd = s.w;
	float ang = atan(d.y, d.x);
	float edge = R * (0.78 + 0.11 * sin(ang * 3.0 + sd) + 0.07 * sin(ang * 5.0 + sd * 2.1) + 0.05 * sin(ang * 11.0 + sd * 3.7));
	edge += pow(max(sin(ang * 7.0 + sd * 1.3), 0.0), 14.0) * R * 0.5;
	float f = (edge - length(d)) / R;
	for (int k = 0; k < 7; k++) {
		float a = hash(vec2(sd, float(k))) * 6.2832;
		float dist = R * (1.12 + hash(vec2(float(k), sd)) * 0.75);
		float rr = R * (0.04 + 0.08 * hash(vec2(sd * 1.7, float(k) * 3.1)));
		f = max(f, (rr - length(p - s.xy - vec2(cos(a), sin(a)) * dist)) / R);
	}
	for (int k = 0; k < 3; k++) {
		float hx = hash(vec2(sd * 2.3, float(k) * 7.0));
		if (hx < 0.3) { continue; }
		float x = s.x + (hash(vec2(float(k) * 1.3, sd)) - 0.5) * 1.1 * R;
		float y0 = s.y - 0.5 * R;
		float len = min(R * (0.5 + hx), age * (0.02 + 0.05 * hx));
		float w = R * (0.045 + 0.035 * hx);
		f = max(f, (w - length(p - vec2(x, clamp(p.y, y0 - len, y0)))) / R);
		f = max(f, (w * 1.6 - length(p - vec2(x, y0 - len))) / R);
	}
	return f;
}
void fragment() {
	vec2 p = vec2((UV.x - 0.5) * size_m.x, (1.0 - UV.y) * size_m.y);
	float n = vnoise(p * 9.0 + seed) * 0.6 + vnoise(p * 23.0 - seed) * 0.4;
	float f = -1.0;
	for (int i = 0; i < count; i++) {
		f = max(f, splat(p, splats[i]));
	}
	float th = (1.0 - mud) * 0.4;                      // thinning: only the thick middles stay
	float a = smoothstep(th, th + max(fwidth(f), 0.004), f);
	for (int i = 0; i < 2; i++) {
		vec2 dd = p - pivots[i];
		float r = length(dd);
		float ang = atan(dd.y, dd.x);
		// a ragged edge where the blade stopped; inside, smeared streaks
		float stop = park + swept[i] + (n - 0.5) * 0.08;
		if (r > 0.05 && r < reach + (n - 0.5) * 0.03 && ang > park - 0.05 && ang < stop) {
			a *= residue[i] * (0.4 + 0.6 * smoothstep(0.78, 0.9, fract(r * 30.0 + n * 1.5)));
		}
	}
	// cartoon colour: a darker rim, the mud, a glossy wet highlight in the thick parts
	vec3 mud_col = mix(vec3(0.36, 0.25, 0.13), vec3(0.45, 0.33, 0.18), n);
	vec3 rim_col = vec3(0.2, 0.13, 0.07);
	float rim = 1.0 - smoothstep(th + 0.02, th + 0.14, f);
	vec3 col = mix(mud_col, rim_col, rim * 0.85);
	float shine = step(0.4, f) * step(0.72, vnoise(p * 6.0 + seed * 1.7 + vec2(0.0, 0.6)));
	col = mix(col, vec3(0.7, 0.58, 0.42), shine * 0.6);
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 0.97);
}
"""
	return sh


# ── crew ──────────────────────────────────────────────────────────────────

func _crew() -> void:
	var ok := true
	for seat in ["driver", "codriver"]:
		var m := CrewModel.new()
		m.scale_k = CrewModel.SCALE * _crew_k()
		if not own.is_empty():
			m.thigh_y = 0.04                         # (on its seat's cushion, not through it)
		m.own_layer = 2 if seat == "driver" else 3
		m.suit_colour = SUIT_D if seat == "driver" else SUIT_C
		add_child(m)
		if m.load_model("res://assets/models/%s.glb" % seat):
			m.seat_at(eye_for(seat) + HIPS * _crew_k())
			# the co-driver never sees their own body: it would sit between their eyes and
			# the map board in their lap (the co-driver's camera leaves layer 3 out)
			if seat == "codriver":
				m.set_layer(3)
			_models[seat] = m
		else:
			ok = false
	if ok:
		return
	for m in _models.values():
		m.queue_free()
	_models.clear()
	_box_crew()


## Belt the crew in: pose them once as they'll sit (the driver's hands on the
## wheel, the co-driver's on the map board), then fit each a harness (harness.gd).
func _harnesses() -> void:
	if _models.is_empty():
		return
	hands.update(0.0, 0.0, false)
	if _models.has("driver"):
		_models.driver.pose(hands.wrists, Vector3(0.35, -0.6, 0.15))
	if _models.has("codriver") and map_board:
		var board: Array = [map_board.transform * Vector3(-0.15, -0.05, 0.02), map_board.transform * Vector3(0.15, -0.05, 0.02)]
		_models.codriver.pose(board, Vector3(0.3, -0.6, 0.25), 0.9)
	if not own.is_empty():
		return                                       # a road car's interior: no harness bar to belt them to
	for seat in _models:
		var h := Harness.build(_models[seat], HARNESS_BAR.x, HARNESS_BAR.y, _models[seat].layer_mask())
		if h:
			h.name = "Harness" + seat.capitalize()
			add_child(h)


## Which seat is yours: your own model loses its head (your camera is in it).
func set_my_seat(seat: String) -> void:
	for s in _models:
		_models[s].hide_head(s == seat)


func _box_crew() -> void:
	for seat in ["driver", "codriver"]:
		var e := eye_for(seat)
		var suit: Color = SUIT_D if seat == "driver" else SUIT_C
		_box(Vector3(0.4, 0.5, 0.24), e + Vector3(0.0, -0.5, 0.14), suit, Vector3(deg_to_rad(-10.0), 0, 0))     # torso
		_box(Vector3(0.36, 0.14, 0.42), e + Vector3(0.0, -0.72, -0.14), suit * 0.8)                        # lap
		var head := Node3D.new()
		head.position = e + Vector3(0, 0.02, 0.06)
		add_child(head)
		var helm := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.15
		sm.height = 0.3
		sm.radial_segments = 10
		sm.rings = 6
		helm.mesh = sm
		helm.material_override = _mat(suit, 0.35)
		head.add_child(helm)
		var visor := _box(Vector3(0.2, 0.08, 0.08), Vector3(0, 0.0, -0.12), Color(0.08, 0.1, 0.14), Vector3.ZERO, head)
		visor.material_override = _mat(Color(0.08, 0.1, 0.14), 0.15)
		var layer := 2 if seat == "driver" else 3
		helm.layers = 1 << (layer - 1)
		visor.layers = 1 << (layer - 1)
		_heads[seat] = head
		for side in ["l", "r"]:
			var up := _tube(Vector3.ZERO, Vector3(0, 0.1, 0), 0.045, suit)
			var lo := _tube(Vector3.ZERO, Vector3(0, 0.1, 0), 0.036, SKIN)
			var fist := _box(Vector3(0.06, 0.06, 0.07), Vector3.ZERO, SKIN)
			_arms[seat + side] = [up, lo, fist]


## Turn a crew member's head (for the other player to see where they look).
func set_look(seat: String, yaw: float, pitch: float) -> void:
	if _models.has(seat):
		_models[seat].look = Vector2(yaw * 0.9, pitch * 0.8)
	if _heads.has(seat):
		_heads[seat].rotation = Vector3(pitch * 0.8, yaw * 0.9, 0.0)


## Two-bone arm from shoulder to hand, elbow pushed toward `pole`.
func _arm(key: String, shoulder: Vector3, hand: Vector3, pole: Vector3) -> void:
	var l1 := 0.29
	var l2 := 0.29
	var d := hand - shoulder
	var dist := clampf(d.length(), 0.05, l1 + l2 - 0.001)
	var dir := d.normalized()
	var a := (l1 * l1 + dist * dist - l2 * l2) / (2.0 * dist)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var side := (pole - shoulder - dir * (pole - shoulder).dot(dir)).normalized()
	var elbow := shoulder + dir * a + side * h
	var hand_at := shoulder + dir * dist
	_place_tube(_arms[key][0], shoulder, elbow)
	_place_tube(_arms[key][1], elbow, hand_at)
	_arms[key][2].position = hand_at


# ── every frame ───────────────────────────────────────────────────────────

func _process(dt: float) -> void:
	if car == null:
		return
	# the steering wheel turns ~13x the front wheels (capped at about 1.5 turns), no faster
	# than hands can turn it (~690 deg/s)
	_wheel_turn = move_toward(_wheel_turn, clampf(car.steer * 13.0, -4.5, 4.5), 12.0 * dt)
	var wheel_turn: float = _wheel_turn
	if _steer_node:
		_steer_node.rotation = Vector3(WHEEL_TILT, 0.0, 0.0)
		_steer_node.rotate_object_local(Vector3.BACK, -wheel_turn)
	elif car.cockpit_nodes.has("wheel"):
		(car.cockpit_nodes.wheel as Node3D).basis = Basis(_wheel_axis, -wheel_turn)
	# driver's hands: gloves round the rim, hand over hand when it turns a lot, the
	# right one on the handbrake when it's pulled (driver_hands.gd)
	hands.update(dt, wheel_turn, car.handbrake_on(), car.gear)
	var wheel_hands: Array = hands.wrists
	if _models.is_empty():
		for k in 2:
			var side := "l" if k == 0 else "r"
			var sh := eye_driver + Vector3(-0.19 if side == "l" else 0.19, -0.32, 0.12)
			_arm("driver" + side, sh, wheel_hands[k], sh + Vector3(-0.3 if side == "l" else 0.3, -0.5, 0.0))
	# co-driver holds the map board by its sides
	var board_hands: Array = []
	if map_board:
		for side in ["l", "r"]:
			var hand: Vector3 = map_board.transform * Vector3(-0.15 if side == "l" else 0.15, -0.05, 0.02)
			board_hands.append(hand)
			if _models.is_empty():
				var sh := eye_codriver + Vector3(-0.19 if side == "l" else 0.19, -0.32, 0.12)
				_arm("codriver" + side, sh, hand, sh + Vector3(-0.3 if side == "l" else 0.3, -0.5, 0.1))
	if _models.has("driver"):
		_models.driver.pose(wheel_hands, Vector3(0.35, -0.6, 0.15))
		hands.aim_cuffs(_models.driver.elbows())
	if _models.has("codriver") and board_hands.size() == 2:
		_models.codriver.pose(board_hands, Vector3(0.3, -0.6, 0.25), 0.9)
	# the dials: revs through the gears (red line at the top) and road speed (0-200)
	if _needles.has("rpm"):
		var rev: float = clampf(0.18 + car.rpm * 0.82, 0.0, 1.0)
		_needles.rpm.rotation.z = -deg_to_rad(-135.0 + 270.0 * rev)
		_needles.kmh.rotation.z = -deg_to_rad(-135.0 + 270.0 * clampf(car.kmh() / 200.0, 0.0, 1.0))
		# the gear selected (rolling back in first still says 1): R when it's reversing
		var reversing: bool = car.speed < -0.5 and (not car.simulate or float(car.inp.brake) > 0.05)
		_gear_label.text = "R" if reversing else str(car.gear)
		var limiter := rev > 0.95
		var blink := fmod(Time.get_ticks_msec() / 1000.0, 0.16) < 0.08
		for i in _shift_leds.size():
			var lit: bool = (rev > SHIFT_AT[i] and not limiter) or (limiter and blink)
			_shift_leds[i].emission_energy_multiplier = 2.2 if lit else 0.0
		if map_board:
			_trip_label.text = "%.2f" % (maxf(map_board.car_s - 40.0, 0.0) / 1000.0)
	_wipers(dt)
	_mirror(dt)
	_mud_mat.set_shader_parameter("mud", mud)
	_mud_mat.set_shader_parameter("swept", PackedFloat32Array([deg_to_rad(swept[0]), deg_to_rad(swept[1])]))
	_mud_mat.set_shader_parameter("residue", PackedFloat32Array(residue))
	_mud_mat.set_shader_parameter("seed", mud_seed)
	_mud_age += dt
	_mud_mat.set_shader_parameter("age", _mud_age)


# ── mud + wipers ──────────────────────────────────────────────────────────

## A splat from a puddle: a big cartoon splat right in front of the driver, a
## few more across the glass (more the harder the hit), droplets and drips.
## Same seed -> the same splats on both machines.
func splat(amount: float, seed_value: int) -> void:
	mud = 1.0
	swept = [0.0, 0.0]
	residue = [1.0, 1.0]
	mud_seed = float(seed_value % 1000) * 0.37
	_mud_age = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var h := (ws_top - ws_bottom).length()
	_splats = PackedVector4Array()
	# the one that matters: where the driver looks at the road
	_splats.append(Vector4(eye_driver.x + rng.randf_range(-0.1, 0.1), h * rng.randf_range(0.36, 0.5),
		rng.randf_range(0.27, 0.34), rng.randf() * 100.0))
	var n := 3 + int(clampf(amount, 0.0, 1.0) * 4.0)
	for k in n:
		_splats.append(Vector4(rng.randf_range(-ws_w * 0.45, ws_w * 0.45), h * rng.randf_range(0.15, 0.85),
			rng.randf_range(0.09, 0.22), rng.randf() * 100.0))
	_mud_mat.set_shader_parameter("splats", _splats)
	_mud_mat.set_shader_parameter("count", _splats.size())


## 0..1: how much of the view is still blocked (the AI co-driver reacts to it).
func mud_level() -> float:
	# the two arcs are most of the driver's view; the corners matter less
	var arcs := 0.0
	for k in 2:
		arcs += (residue[k] if swept[k] > 60.0 else 1.0) * 0.5
	return mud * clampf(0.25 + arcs * 0.75, 0.0, 1.0)


func wipe(strokes := 3) -> void:
	wipe_strokes = maxi(wipe_strokes, strokes)


func _wipers(dt: float) -> void:
	if wipe_strokes <= 0 and _wiper_t <= 0.0:
		return
	var period := 0.85
	var prev := _wiper_t
	_wiper_t += dt
	for arm in _wiper_pivots:
		arm.visible = true
	var phase := fmod(_wiper_t, period) / period          # 0 -> 1: up and back
	var up := sin(phase * PI)                               # 0 parked .. 1 fully across
	var ang := WIPER_PARK + WIPER_SWEEP * up
	for arm in _wiper_pivots:
		arm.rotation.z = deg_to_rad(ang)
	for k in 2:
		swept[k] = maxf(swept[k], ang - WIPER_PARK)
	if floor(prev / period) != floor(_wiper_t / period):   # a stroke finished
		for k in 2:
			residue[k] *= STREAKS
		wipe_strokes -= 1
		wiper_stroke.emit()
		if wipe_strokes <= 0:
			mud *= 0.85                                     # washer fluid thins what's left in the corners a little
			_wiper_t = 0.0
			for arm in _wiper_pivots:
				arm.rotation.z = deg_to_rad(WIPER_PARK)
				arm.visible = own.is_empty()
