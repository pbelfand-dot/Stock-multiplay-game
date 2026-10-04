extends Node3D
## The inside of the car, low poly like the reference: red shell and roll
## cage, grey dash, black wheel, a gear stick with a red knob, the red hood
## out front. Two crew: the DRIVER (left, red helmet) with hands that follow
## the wheel, and the CO-DRIVER (right, blue helmet) holding the roadbook roll.
## Also the windshield mud and the two wipers that clear it.
## A child of the car, so it moves with it. Car-local units: the car faces -Z,
## origin = chassis middle at wheel-mount height (the ground is ~0.56 below).
##
## Each crew member's head is on its own render layer (2 = driver, 3 =
## co-driver) so your own camera doesn't see the inside of your helmet.

const Roadbook = preload("res://scripts/vehicle/roadbook.gd")

const RED := Color(0.78, 0.12, 0.1)
const GREY := Color(0.46, 0.45, 0.43)
const DARK := Color(0.1, 0.1, 0.11)
const SEAT := Color(0.82, 0.55, 0.22)
const SKIN := Color(0.86, 0.67, 0.5)
const SUIT_D := Color(0.75, 0.13, 0.12)
const SUIT_C := Color(0.14, 0.24, 0.62)
const EYE_DRIVER := Vector3(-0.37, 0.6, 0.26)
const EYE_CODRIVER := Vector3(0.37, 0.6, 0.26)
const WHEEL_C := Vector3(-0.37, 0.26, -0.27)
const WHEEL_R := 0.18
const WHEEL_TILT := 0.42                      # rad back from vertical
## The windshield: bottom edge (cowl) and top edge, car-local.
const WS_BOTTOM := Vector3(0.0, 0.32, -0.74)
const WS_TOP := Vector3(0.0, 0.92, -0.3)
const WS_W := 1.42
const MUD_MAX := 16

var car
var roadbook                                  # Roadbook (draws into a SubViewport)
var mud: Array = []                           # [{u, v, r, a}] blobs in windshield UV (v: 0 top .. 1 bottom)
var wipe_strokes := 0                          # strokes left to do
var _wiper_t := 0.0
var _wiper_pivots: Array = []
var _mud_mat: ShaderMaterial
var _steer_node: Node3D
var _arms := {}                                # name -> [upper MeshInstance3D, lower MeshInstance3D]
var _heads := {}                               # seat -> Node3D (helmet)
var _mats := {}
var _rng := RandomNumberGenerator.new()

signal wiper_stroke


func build(the_car, stage_notes: Array, stage_len: float) -> void:
	car = the_car
	_shell()
	_dash()
	_seats()
	_wheel()
	_windshield()
	_crew()
	roadbook = Roadbook.new()
	add_child(roadbook)
	roadbook.setup(stage_notes, stage_len)
	roadbook.position = Vector3(0.36, 0.25, 0.0)
	roadbook.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(4.0), 0.0)


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
		# doors: inner panel below the window line, with a handle and a pull
		_box(Vector3(0.05, 0.62, 1.2), Vector3(0.8 * sx, 0.02, 0.2), RED)
		_box(Vector3(0.06, 0.14, 0.9), Vector3(0.77 * sx, 0.12, 0.25), GREY)
		_box(Vector3(0.04, 0.04, 0.16), Vector3(0.74 * sx, 0.2, -0.05), DARK)
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
	# floor and back
	_box(Vector3(1.5, 0.04, 2.0), Vector3(0.0, -0.32, 0.1), DARK)
	_box(Vector3(1.5, 0.5, 0.05), Vector3(0.0, 0.1, 1.5), GREY)
	# body sides, seen from outside (the other crew, the menu)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.05, 0.55, 3.5), Vector3(0.82 * sx, -0.08, 0.0), RED)
	_box(Vector3(1.62, 0.55, 0.12), Vector3(0.0, -0.05, 1.82), RED)          # tailgate


func _dash() -> void:
	_box(Vector3(1.44, 0.24, 0.34), Vector3(0.0, 0.2, -0.48), GREY)          # the dash
	_box(Vector3(1.44, 0.05, 0.4), Vector3(0.0, 0.33, -0.52), GREY * 0.85)   # its top
	_box(Vector3(0.42, 0.14, 0.04), Vector3(-0.37, 0.24, -0.31), DARK)        # instrument hood
	_box(Vector3(0.3, 0.05, 0.02), Vector3(0.0, 0.26, -0.3), DARK)            # vents
	_box(Vector3(0.3, 0.05, 0.02), Vector3(0.0, 0.18, -0.3), DARK)
	_box(Vector3(0.2, 0.06, 0.02), Vector3(0.0, 0.1, -0.3), Color(0.2, 0.2, 0.22))   # radio slot
	_box(Vector3(0.4, 0.04, 0.02), Vector3(0.38, 0.26, -0.3), DARK)
	_box(Vector3(0.22, 0.2, 0.3), Vector3(0.0, -0.18, -0.15), GREY * 0.8)     # tunnel
	# gear stick with the red knob, and the handbrake
	_tube(Vector3(0.0, -0.08, -0.1), Vector3(0.0, 0.12, -0.08), 0.012, DARK)
	var knob := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	sm.radial_segments = 8
	sm.rings = 4
	knob.mesh = sm
	knob.material_override = _mat(Color(0.85, 0.1, 0.1), 0.4)
	knob.position = Vector3(0.0, 0.14, -0.08)
	add_child(knob)
	_tube(Vector3(0.05, -0.06, 0.12), Vector3(0.05, 0.1, 0.02), 0.014, DARK)


func _seats() -> void:
	for x in [-0.37, 0.37]:
		_box(Vector3(0.5, 0.14, 0.52), Vector3(x, -0.22, 0.3), SEAT)          # cushion
		_box(Vector3(0.5, 0.75, 0.14), Vector3(x, 0.2, 0.6), SEAT, Vector3(deg_to_rad(-12.0), 0, 0))
		_box(Vector3(0.12, 0.42, 0.4), Vector3(x - 0.24, -0.02, 0.38), SEAT * 0.9)   # bolsters
		_box(Vector3(0.12, 0.42, 0.4), Vector3(x + 0.24, -0.02, 0.38), SEAT * 0.9)


func _wheel() -> void:
	_tube(Vector3(-0.37, 0.12, -0.46), WHEEL_C, 0.025, DARK)                 # column
	_steer_node = Node3D.new()
	_steer_node.position = WHEEL_C
	_steer_node.rotation.x = WHEEL_TILT
	add_child(_steer_node)
	var seg := 12
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		_tube(Vector3(cos(a0), sin(a0), 0) * WHEEL_R, Vector3(cos(a1), sin(a1), 0) * WHEEL_R, 0.015, DARK, _steer_node)
	for a in [PI, 0.0, -PI / 2.0]:
		_tube(Vector3.ZERO, Vector3(cos(a), sin(a), 0) * WHEEL_R, 0.012, DARK, _steer_node)
	_box(Vector3(0.06, 0.06, 0.03), Vector3.ZERO, Color(0.85, 0.1, 0.1), Vector3.ZERO, _steer_node)


func _windshield() -> void:
	var up := (WS_TOP - WS_BOTTOM)
	var h := up.length()
	var y := up / h
	var n := Vector3.RIGHT.cross(y).normalized()               # points into the cabin
	var basis := Basis(Vector3.RIGHT, y, n)
	# the mud: one quad over the glass, the shader draws the blobs
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(WS_W, h)
	q.mesh = qm
	q.transform = Transform3D(basis, (WS_BOTTOM + WS_TOP) * 0.5 + n * 0.01)
	_mud_mat = ShaderMaterial.new()
	_mud_mat.shader = _mud_shader()
	q.material_override = _mud_mat
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(q)
	# two wipers, pivoting at the bottom of the glass, parked flat
	for px in [-0.5, 0.18]:
		var pivot := Node3D.new()
		pivot.transform = Transform3D(basis, WS_BOTTOM + Vector3(px, 0, 0) + y * 0.04 + n * 0.02)
		add_child(pivot)
		var arm := Node3D.new()
		pivot.add_child(arm)
		_box(Vector3(0.6, 0.012, 0.012), Vector3(0.3, 0.0, 0.0), DARK, Vector3.ZERO, arm)
		_box(Vector3(0.62, 0.02, 0.02), Vector3(0.33, 0.02, 0.0), Color(0.05, 0.05, 0.05), Vector3.ZERO, arm)
		arm.rotation.z = deg_to_rad(4.0)
		_wiper_pivots.append(arm)


func _mud_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform vec4 blobs[16];          // xy = centre (uv), z = radius, w = opacity
uniform int count = 0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	float a = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= count) break;
		vec4 b = blobs[i];
		vec2 d = (UV - b.xy) * vec2(1.6, 1.0);
		float ang = atan(d.y, d.x);
		float wobble = 0.86 + 0.1 * sin(ang * 5.0 + b.x * 40.0) + 0.05 * sin(ang * 11.0 + b.y * 30.0);
		float r = b.z * wobble;
		float k = 1.0 - smoothstep(r * 0.8, r, length(d));
		a = max(a, k * b.w);
	}
	float speck = step(0.985, hash(floor(UV * 90.0))) * 0.25 * float(count > 0);
	ALBEDO = vec3(0.3, 0.21, 0.12) * (0.85 + 0.3 * hash(floor(UV * 40.0)));
	ALPHA = clamp(max(a, speck * a), 0.0, 0.97);
}
"""
	return sh


# ── crew ──────────────────────────────────────────────────────────────────

func _crew() -> void:
	for seat in ["driver", "codriver"]:
		var x: float = EYE_DRIVER.x if seat == "driver" else EYE_CODRIVER.x
		var suit: Color = SUIT_D if seat == "driver" else SUIT_C
		_box(Vector3(0.4, 0.5, 0.24), Vector3(x, 0.1, 0.4), suit, Vector3(deg_to_rad(-10.0), 0, 0))     # torso
		_box(Vector3(0.36, 0.14, 0.42), Vector3(x, -0.12, 0.12), suit * 0.8)                        # lap
		var head := Node3D.new()
		head.position = (EYE_DRIVER if seat == "driver" else EYE_CODRIVER) + Vector3(0, 0.02, 0.06)
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
	# the steering wheel turns ~12x the front wheels (14:1 rack, capped at about 1.5 turns)
	var wheel_turn: float = clampf(car.steer * 13.0, -4.5, 4.5)
	_steer_node.rotation = Vector3(WHEEL_TILT, 0.0, 0.0)
	_steer_node.rotate_object_local(Vector3.BACK, -wheel_turn)
	# driver's hands stay on the rim at 9 and 3 while it turns (and let go past ~110 deg)
	var grip := clampf(wheel_turn, -1.9, 1.9)
	for side in ["l", "r"]:
		var base_ang := PI if side == "l" else 0.0
		var ang := base_ang - grip
		var hand: Vector3 = _steer_node.transform * (Vector3(cos(ang), sin(ang), 0.0) * WHEEL_R)
		var sh := Vector3(EYE_DRIVER.x + (-0.19 if side == "l" else 0.19), 0.28, 0.38)
		_arm("driver" + side, sh, hand, sh + Vector3(-0.3 if side == "l" else 0.3, -0.5, 0.0))
	# co-driver holds the roadbook by its sides
	if roadbook:
		for side in ["l", "r"]:
			var hand: Vector3 = roadbook.transform * Vector3(-0.15 if side == "l" else 0.15, -0.05, 0.02)
			var sh := Vector3(EYE_CODRIVER.x + (-0.19 if side == "l" else 0.19), 0.28, 0.38)
			_arm("codriver" + side, sh, hand, sh + Vector3(-0.3 if side == "l" else 0.3, -0.5, 0.1))
	_wipers(dt)
	var arr := PackedVector4Array()
	arr.resize(MUD_MAX)
	for i in mini(mud.size(), MUD_MAX):
		var b: Dictionary = mud[i]
		arr[i] = Vector4(b.u, b.v, b.r, b.a)
	_mud_mat.set_shader_parameter("blobs", arr)
	_mud_mat.set_shader_parameter("count", mini(mud.size(), MUD_MAX))


# ── mud + wipers ──────────────────────────────────────────────────────────

## A splat: `amount` 0..1 (a puddle at speed is ~0.6-1). Deterministic per seed.
func splat(amount: float, seed_value: int) -> void:
	_rng.seed = seed_value
	var n := 3 + int(amount * 7.0)
	for k in n:
		if mud.size() >= MUD_MAX:
			mud.pop_front()
		mud.append({"u": _rng.randf_range(0.08, 0.92), "v": _rng.randf_range(0.15, 0.95),
			"r": _rng.randf_range(0.07, 0.17) * (0.6 + amount * 0.6), "a": _rng.randf_range(0.75, 0.97)})


## 0..1: how much of the view is covered (for the AI co-driver to complain).
func mud_level() -> float:
	var t := 0.0
	for b in mud:
		t += b.a * b.r * b.r * 12.0
	return clampf(t, 0.0, 1.0)


func wipe(strokes := 3) -> void:
	wipe_strokes = maxi(wipe_strokes, strokes)


func _wipers(dt: float) -> void:
	if wipe_strokes <= 0 and _wiper_t <= 0.0:
		return
	var period := 0.85
	var prev := _wiper_t
	_wiper_t += dt
	var phase := fmod(_wiper_t, period) / period          # 0 -> 1: up and back
	var sweep := sin(phase * PI)                            # 0 parked .. 1 fully across
	for arm in _wiper_pivots:
		arm.rotation.z = deg_to_rad(4.0 + 118.0 * sweep)
	# clear the blobs the blades pass over (each pivot sweeps half the glass)
	var ang := 4.0 + 118.0 * sweep
	for b in mud:
		for px in [0.15, 0.62]:
			var du: float = b.u - px
			var dv: float = 1.0 - b.v
			var blob_ang := rad_to_deg(atan2(dv * 0.6, du * WS_W))
			if dv * 0.6 < 0.55 and absf(blob_ang - ang) < 12.0:
				b.a *= 0.5
	mud = mud.filter(func(b): return b.a > 0.06)
	if floor(prev / period) != floor(_wiper_t / period):
		wipe_strokes -= 1
		wiper_stroke.emit()
		if wipe_strokes <= 0:
			_wiper_t = 0.0
			for arm in _wiper_pivots:
				arm.rotation.z = deg_to_rad(4.0)
