extends Node3D
## The driver's hands: gloves that wrap round the steering wheel rim (the
## rigged crew model has no finger bones, so its own hands are hidden and these
## take their place), hand-over-hand steering, and the handbrake.
##   * a gripping hand stays where it took hold of the rim and turns with the
##     wheel. When it's carried past where an arm can comfortably go, it lets
##     go and takes a new grip further round (one hand at a time, the other
##     holds on), so the arms never twist. Back near the centre, an
##     out-of-place hand drifts back to 9 / 3 o'clock
##   * the handbrake: the right hand leaves the wheel, takes the tall hydraulic
##     lever beside the seat and yanks it back; let go and the hand goes back
##     to the wheel
## Works in the cockpit's space (the car faces -Z). The arms reach for
## `wrists` (the crew model's IK targets).

const LEFT := 0
const RIGHT := 1
const MOVE_TIME := 0.13         # s to let go and take a new grip
const LEVER_BASE := Vector3(-0.12, -0.1, -0.14)
const LEVER_LEN := 0.46          # tall, like a rally car's: the grip stands just right of the wheel's bottom
const LEVER_TILT := -0.25       # rad: leans forward, parked
const LEVER_PULL := 0.36        # rad back when pulled (still in view)
const RIM_R := 0.018            # thickness of the rim / lever handle the fingers wrap

var wrists: Array = [Vector3.ZERO, Vector3.ZERO]   # where the arms reach (cockpit space)
var _plane: Node3D               # the wheel's plane (tilted, not turned)
var _gloves: Array = []
var _lever: Node3D
var _lever_pull := 0.0
var _rim := 0.18
# per hand: {mode: "grip" | "move" | "brake", g: grip angle on the wheel, from, to, t}
var _hand := [{"mode": "grip", "g": PI, "from": PI, "to": PI, "t": 0.0},
	{"mode": "grip", "g": 0.0, "from": 0.0, "to": 0.0, "t": 0.0}]
var _last_w := 0.0


func setup(wheel_centre: Vector3, wheel_tilt: float, rim_radius: float) -> void:
	_rim = rim_radius
	_plane = Node3D.new()
	_plane.position = wheel_centre
	_plane.rotation.x = wheel_tilt
	add_child(_plane)
	for k in 2:
		var g := _glove()
		add_child(g)
		_gloves.append(g)
	_build_lever()


## Every frame: the wheel's turn (rad, + = clockwise as the driver sees it) and
## whether the handbrake is on.
func update(dt: float, wheel_turn: float, handbrake: bool) -> void:
	var w := wheel_turn
	var turning := signf(w - _last_w)
	_last_w = w
	_lever_pull = move_toward(_lever_pull, 1.0 if handbrake else 0.0, dt * (9.0 if handbrake else 6.0))
	_lever.rotation.x = LEVER_TILT + LEVER_PULL * _ease(_lever_pull)
	# the right hand and the handbrake
	var rh: Dictionary = _hand[RIGHT]
	if handbrake and rh.mode != "brake":
		rh.mode = "brake"
		rh.t = 0.0
		rh.from = _plane_angle(RIGHT, w)
	elif not handbrake and rh.mode == "brake":
		rh.mode = "move"
		rh.t = 0.0
		rh.from = -1000.0                            # from the lever: see _target()
		rh.to = _home(RIGHT) + w
	for k in 2:
		var h: Dictionary = _hand[k]
		match h.mode:
			"grip":
				var off := _offset(k, h.g - w)
				var other: Dictionary = _hand[1 - k]
				var lo := -1.4 if k == RIGHT else -1.75     # how far round an arm goes (rad from home)
				var hi := 1.75 if k == RIGHT else 1.4
				if other.mode == "grip" and (off < lo - 0.12 or off > hi + 0.12):
					# carried too far: let go and take hold further round, ready to keep turning
					var to_off: float
					if k == RIGHT:
						to_off = 1.1 if off < 0.0 else -0.9
					else:
						to_off = -1.1 if off > 0.0 else 0.9
					_start_move(h, k, w, to_off)
				elif other.mode == "grip" and absf(w) < 0.6 and absf(off) > 0.7 and turning == 0.0:
					_start_move(h, k, w, 0.0)                # wheel's back near straight: hands home
			"move":
				h.t += dt / MOVE_TIME
				if h.t >= 1.0:
					h.mode = "grip"
					h.g = h.to
			"brake":
				h.t = minf(h.t + dt / MOVE_TIME, 1.0)
	for k in 2:
		_place(k, w)


func _start_move(h: Dictionary, k: int, w: float, to_off: float) -> void:
	h.mode = "move"
	h.t = 0.0
	h.from = h.g - w
	h.to = _home(k) + to_off + w


func _home(k: int) -> float:
	return PI if k == LEFT else 0.0


## How far a hand is from its home (rad), wrapped to -PI..PI.
func _offset(k: int, plane_angle: float) -> float:
	return wrapf(plane_angle - _home(k), -PI, PI)


func _plane_angle(k: int, w: float) -> float:
	return _hand[k].g - w


## Put glove k where its hand is, and the wrist target behind it.
func _place(k: int, w: float) -> void:
	var h: Dictionary = _hand[k]
	var xf: Transform3D
	match h.mode:
		"grip":
			xf = _rim_grip(h.g - w, 0.0)
		"move":
			var u := _ease(h.t)
			var to_a: float = h.to - w
			if h.from < -999.0:
				# coming back from the lever
				xf = _lever_grip().interpolate_with(_rim_grip(to_a, 0.0), u)
			else:
				var from_a: float = h.from
				var a := from_a + wrapf(to_a - from_a, -PI, PI) * u
				xf = _rim_grip(a, sin(u * PI) * 0.06)      # lifted off the rim on the way
		"brake":
			xf = _rim_grip(h.from, 0.0).interpolate_with(_lever_grip(), _ease(h.t))
	(_gloves[k] as Node3D).transform = xf
	wrists[k] = xf * Vector3(0.0, 0.0, 0.075)


## A grip on the rim at plane angle a (0 = 3 o'clock, PI = 9), lifted `lift` toward the driver.
## Glove frame: x along the rim, y outward, z toward the driver.
func _rim_grip(a: float, lift: float) -> Transform3D:
	var p := Vector3(cos(a), sin(a), 0.0) * _rim
	var t := Vector3(-sin(a), cos(a), 0.0)
	var r := Vector3(cos(a), sin(a), 0.0)
	var local := Transform3D(Basis(t, r, Vector3(0, 0, 1)), p + Vector3(0, 0, lift))
	return _plane.transform * local


## The grip on the handbrake handle: fingers round the far side, palm toward the driver.
func _lever_grip() -> Transform3D:
	var top: Vector3 = _lever.transform * Vector3(0.0, LEVER_LEN, 0.0)
	var up := (_lever.transform.basis * Vector3.UP).normalized()
	var toward := Vector3(-0.85, 0.0, 0.5).normalized()        # back toward the driver's shoulder
	toward = (toward - up * toward.dot(up)).normalized()
	var out := up.cross(toward).normalized()
	return Transform3D(Basis(up, out, toward), top - up * 0.04)


static func _ease(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)


# ── models ────────────────────────────────────────────────────────────────

func _mat(c: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


## A gloved hand gripping a bar along its x axis: palm on the +z side (toward
## the wrist), four fingers curling over +y round to the front, the thumb under.
func _glove() -> Node3D:
	var g := Node3D.new()
	var black := _mat(Color(0.07, 0.07, 0.08), 0.7)
	var grey := _mat(Color(0.2, 0.2, 0.22), 0.6)
	var palm := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.08, 0.055, 0.035)
	palm.mesh = pb
	palm.material_override = black
	palm.position = Vector3(0.0, 0.004, RIM_R + 0.02)
	g.add_child(palm)
	var cuff := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.034
	cm.bottom_radius = 0.03
	cm.height = 0.05
	cm.radial_segments = 8
	cuff.mesh = cm
	cuff.material_override = grey
	cuff.rotation.x = PI / 2.0
	cuff.position = Vector3(0.0, 0.0, 0.065)
	g.add_child(cuff)
	var rf := RIM_R + 0.011
	for i in 4:
		var x := -0.03 + i * 0.02
		var prev := Vector3(x, rf * sin(deg_to_rad(5.0)), rf * cos(deg_to_rad(5.0)))
		for deg in [70.0, 130.0, 175.0]:
			var a := deg_to_rad(deg)
			var p := Vector3(x, rf * sin(a), rf * cos(a))
			g.add_child(_seg(prev, p, 0.0085 if i in [1, 2] else 0.0078, black))
			prev = p
	var tprev := Vector3(0.035, -0.012, RIM_R + 0.014)
	for deg in [-60.0, -120.0]:
		var a := deg_to_rad(deg)
		var p := Vector3(0.028, rf * sin(a), rf * cos(a))
		g.add_child(_seg(tprev, p, 0.0095, black))
		tprev = p
	return g


func _seg(a: Vector3, b: Vector3, r: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = r
	cap.height = a.distance_to(b) + r * 2.0
	cap.radial_segments = 6
	cap.rings = 1
	mi.mesh = cap
	mi.material_override = m
	var d := (b - a).normalized()
	var up := d
	var side := Vector3.RIGHT if absf(d.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := side.cross(up).normalized()
	var z := x.cross(up).normalized()
	mi.transform = Transform3D(Basis(x, up, z), (a + b) * 0.5)
	return mi


## The tall hydraulic handbrake beside the driver's seat: black lever, red grip.
func _build_lever() -> void:
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.06, 0.12)
	base.mesh = bm
	base.material_override = _mat(Color(0.12, 0.12, 0.13), 0.5)
	base.position = LEVER_BASE + Vector3(0.0, 0.0, 0.01)
	add_child(base)
	_lever = Node3D.new()
	_lever.position = LEVER_BASE
	_lever.rotation.x = LEVER_TILT
	add_child(_lever)
	var rod := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.011
	rm.bottom_radius = 0.014
	rm.height = LEVER_LEN
	rm.radial_segments = 8
	rod.mesh = rm
	rod.material_override = _mat(Color(0.05, 0.05, 0.06), 0.35)
	rod.position = Vector3(0.0, LEVER_LEN * 0.5, 0.0)
	_lever.add_child(rod)
	var grip := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = RIM_R
	gm.bottom_radius = RIM_R
	gm.height = 0.1
	gm.radial_segments = 8
	grip.mesh = gm
	grip.material_override = _mat(Color(0.8, 0.08, 0.06), 0.5)
	grip.position = Vector3(0.0, LEVER_LEN - 0.05, 0.0)
	_lever.add_child(grip)
