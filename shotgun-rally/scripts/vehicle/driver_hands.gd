extends Node3D
## The driver's hands: gloves that wrap round the steering wheel rim (the
## rigged crew model has no finger bones, so its own hands are hidden and these
## take their place), hand-over-hand steering, and the handbrake.
##   * the gloves are a model (GLOVES: red racing gloves with white panels, padded knuckles
##     and a long gauntlet, as in the owner's Assetto Corsa clip; made with Higgsfield from a
##     generated photo, fitted to the rim by tools/fit_glove.py: the hand round the rim in glove
##     space, the gauntlet apart so it can follow the forearm; the left hand is the right one
##     mirrored). Without the file, the gloves below, built here:
##   * the built gloves are racing gloves: black, pre-curved fingers round the rim,
##     the thumb across its face, padded knuckles, a panel in the suit's colour
##     on the back, and a flared gauntlet with a strap that goes over the sleeve
##     (it turns to follow the forearm: aim_cuffs())
##   * a gripping hand stays where it took hold of the rim and turns with the
##     wheel. When it's carried past where an arm can comfortably go, it lets
##     go and takes a new grip further round (one hand at a time, the other
##     holds on), so the arms never twist. Back near the centre, an
##     out-of-place hand drifts back to 9 / 3 o'clock
##   * the handbrake: the right hand leaves the wheel, takes the tall hydraulic
##     lever beside the seat and yanks it back; let go and the hand goes back
##     to the wheel
##   * the gears: at each change the right hand flicks across to the sequential
##     lever, pulls it back (up a gear) or pushes it forward (down), and comes
##     back (about a third of a second). Not with the wheel wound round past
##     SHIFT_MAX_TURN or the handbrake up: then both stay where they are
##   * in a car with an interior of its own (use_model): its own levers. The
##     hand nearer the middle shifts (the left one in a right-hand-drive car);
##     an H-pattern lever goes through the gates (out of gear, across, into
##     the next) and stays in gear; an automatic shifts itself, the hand stays
##     on the wheel; the handbrake is pulled up from its pivot
## Works in the cockpit's space (the car faces -Z). The arms reach for
## `wrists` (the crew model's IK targets).

const LEFT := 0
const RIGHT := 1
const MOVE_TIME := 0.13         # s to let go and take a new grip
const LEVER_BASE := Vector3(-0.12, -0.1, -0.14)
const LEVER_LEN := 0.46          # tall, like a rally car's: the grip stands just right of the wheel's bottom
const LEVER_TILT := -0.25       # rad: leans forward, parked
const LEVER_PULL := 0.36        # rad back when pulled (still in view)
const GEAR_BASE := Vector3(-0.025, -0.08, -0.22)    # the sequential lever's pivot, in the tunnel
const GEAR_TOP := Vector3(-0.06, 0.19, -0.15)       # its knob, at rest: leaning back to the right hand
const GEAR_THROW := 0.16        # rad the lever moves at a change (back: up a gear, forward: down)
const SHIFT_REACH := 0.13       # s from the wheel to the knob
const SHIFT_FLICK := 0.08       # s with the lever over
const SHIFT_MAX_TURN := 1.2     # rad of wheel past which the hand stays on it
const H_TIME := 0.24            # s to take an H-pattern lever out of gear, across and into the next
const H_ROW := 0.2              # rad: an H-pattern lever forward (1st, 3rd, 5th) or back (2nd, 4th, 6th)
const H_COL := 0.14             # rad: ... and across, to the left gate (1st, 2nd) or the right (5th, 6th)
const ROAD_PULL := 0.42         # rad a road car's handbrake comes up
const RIM_R := 0.0155           # thickness of the rim / lever handle the fingers wrap (a ~30 mm grip)
const GRIP_ROLL := 0.55         # rad: the hand rolled round the rim toward the driver (you see the backs of your hands)
const WRIST := Vector3(0.0, 0.01, 0.085)    # glove space (before the roll): where the forearm meets the hand
const GLOVES := "res://assets/models/gloves/gloves.glb"   # the model: its "Glove" (the right hand) and "Cuff"
const MODEL_WRIST := Vector3(0.0121, 0.0059, 0.1029)     # its wrist (the right hand's; glove space, before the roll)
## The gauntlet's outline, from inside the glove out over the sleeve (the crew's suit
## sleeve ends ~8 cm up the forearm, where its own glove's cuff was: crew_model.gd
## cuts that out), long like a racing glove's, then a lip turning in to the
## sleeve so you can't see into it: [m along the forearm from the wrist, radius]
const CUFF := [[-0.03, 0.028], [0.0, 0.037], [0.02, 0.0455], [0.04, 0.05], [0.062, 0.0515], [0.093, 0.0525],
	[0.103, 0.0525], [0.107, 0.051], [0.108, 0.044]]

var suit_colour := Color(0.75, 0.13, 0.12)   # the panel on the back, the strap (set before setup)

var wrists: Array = [Vector3.ZERO, Vector3.ZERO]   # where the arms reach (cockpit space)
var _plane: Node3D               # the wheel's plane (tilted, not turned)
var _gloves: Array = []
var _cuffs: Array = []
var _wrist: Array = [WRIST, WRIST]  # each hand's wrist in its glove's space (the model's, or the built gloves')
var model_gloves := false        # the model's gloves are on (not the built ones)
var _elbows: Array = []          # where the forearms come from (cockpit space; empty: a guess)
var _lever: Node3D               # the handbrake (pivots at its foot; +Y along it)
var _lever_base: Node3D
var _lever_pull := 0.0
var _lever_len := LEVER_LEN
var _lever_rest := Basis(Vector3.RIGHT, LEVER_TILT)
var _lever_throw := LEVER_PULL
var _gear: Node3D                # the gear lever (pivots at its foot; +Y along it)
var _gear_rest := Basis()
var _gear_len := 0.0
var shift_hand := RIGHT          # the hand that shifts and pulls the handbrake
var gear_kind := "seq"           # "seq" (ours), "h4" / "h5" / "h6" (an H-pattern), "seq_model", "auto" (no hand)
var _gear_model: Node3D          # the car's own gear lever / handbrake (null: ours)
var _brake_model: Node3D
var _has_brake := true
var _gate := Vector2.ZERO        # an H-pattern lever: where the knob is (x: -1 left .. 1 right; y: -1 forward .. 1 back)
var _gate_from := Vector2.ZERO
var _gate_to := Vector2.ZERO
var _gear_kick := 0.0            # -1 pushed .. 1 pulled
var _last_gear := 0
var _rim := 0.18
# per hand: {mode: "grip" | "move" | "brake" | "shift", g: grip angle on the wheel,
# from, to, t, src: where a move starts ("" the rim, "lever", "gear"), from_xf: the
# glove where a reach started, dir: the shift (+1 up, -1 down)}
var _hand := [{"mode": "grip", "g": PI, "from": PI, "to": PI, "t": 0.0, "src": "", "from_xf": Transform3D(), "dir": 0.0},
	{"mode": "grip", "g": 0.0, "from": 0.0, "to": 0.0, "t": 0.0, "src": "", "from_xf": Transform3D(), "dir": 0.0}]
var _last_w := 0.0


## The wheel: its centre, its tilt back (rad) and its rim's radius; or, a car's own
## wheel, the way its column points toward the driver (axis: its plane's +Z).
func setup(wheel_centre: Vector3, wheel_tilt: float, rim_radius: float, axis := Vector3.ZERO) -> void:
	_rim = rim_radius
	_plane = Node3D.new()
	_plane.position = wheel_centre
	_plane.rotation.x = wheel_tilt
	if axis != Vector3.ZERO:
		var z := axis.normalized()
		var y := (Vector3.UP - z * z.dot(Vector3.UP)).normalized()     # 12 o'clock
		_plane.basis = Basis(y.cross(z), y, z)
	add_child(_plane)
	var mats := {
		"glove": _mat(Color(0.075, 0.075, 0.08), 0.85),         # Nomex suede
		"panel": _mat(suit_colour, 0.7),
		"pad": _mat(Color(0.2, 0.2, 0.21), 0.55),            # rubbery knuckle pads
		"trim": _mat(Color(0.92, 0.92, 0.9), 0.7),
	}
	for k in 2:
		var g := MeshInstance3D.new()
		g.name = "Glove" + ("L" if k == LEFT else "R")
		g.mesh = _glove(1.0 if k == RIGHT else -1.0, mats)
		add_child(g)
		_gloves.append(g)
		var c := MeshInstance3D.new()
		c.name = "Gauntlet" + ("L" if k == LEFT else "R")
		c.mesh = _gauntlet(mats)
		add_child(c)
		_cuffs.append(c)
	_model_gloves()
	_build_lever()
	_build_gear()


## The car's own levers instead of ours (positions in the cockpit's space):
## {side: "left" / "right" (where the driver sits), gearbox: "h4", "h5", "h6", "seq",
## "auto", shifter: {pivot, knob, node}, handbrake: {pivot, grip, node}}. The
## nodes (the model's, each with its origin at its pivot) are turned to match.
func use_model(cfg: Dictionary) -> void:
	shift_hand = LEFT if str(cfg.get("side", "left")) == "right" else RIGHT
	gear_kind = str(cfg.get("gearbox", "h5"))
	if gear_kind == "seq":
		gear_kind = "seq_model"
	for n in [_lever, _gear, _lever_base]:
		for c in n.get_children():
			c.queue_free()
	_lever_base.queue_free()
	_lever_base = null
	if n_is(cfg.get("shifter")):
		var g: Dictionary = cfg.shifter
		_gear.position = g.pivot
		_gear_rest = _along(g.knob - g.pivot)
		_gear.basis = _gear_rest
		_gear_len = (g.knob - g.pivot).length()
		_gear_model = g.get("node")
	elif gear_kind != "auto":
		gear_kind = "auto"                               # nothing to shift with
	_gate = _h_gate(1)
	if n_is(cfg.get("handbrake")):
		var h: Dictionary = cfg.handbrake
		_lever.position = h.pivot
		_lever_rest = _along(h.grip - h.pivot)
		_lever_len = (h.grip - h.pivot).length()
		_lever_throw = ROAD_PULL
		_brake_model = h.get("node")
	else:
		_has_brake = false


static func n_is(v) -> bool:
	return v is Dictionary and not (v as Dictionary).is_empty()


## A basis whose +Y runs along d, its +X as near the car's right as it can be.
static func _along(d: Vector3) -> Basis:
	var y := d.normalized()
	var x := (Vector3.RIGHT - y * y.dot(Vector3.RIGHT)).normalized()
	return Basis(x, y, x.cross(y))


## Where an H-pattern lever's knob sits in gear g (1st top left ... 5th / 6th right;
## a four-speed: two gates, 1st-2nd left, 3rd-4th right).
func _h_gate(g: int) -> Vector2:
	if g < 1:
		return Vector2.ZERO
	var cols := 2 if gear_kind == "h4" else 3
	var col := clampi((g - 1) / 2, 0, cols - 1)
	return Vector2(col - (cols - 1) * 0.5, -1.0 if g % 2 == 1 else 1.0)


## Along the H from one gate to another (u 0..1): back to the middle row, across, into the gate.
static func _h_path(a: Vector2, b: Vector2, u: float) -> Vector2:
	if is_equal_approx(a.x, b.x):
		return a.lerp(b, u)
	if u < 0.3:
		return a.lerp(Vector2(a.x, 0.0), u / 0.3)
	if u < 0.7:
		return Vector2(lerpf(a.x, b.x, (u - 0.3) / 0.4), 0.0)
	return Vector2(b.x, 0.0).lerp(b, (u - 0.7) / 0.3)


## Every frame: the wheel's turn (rad, + = clockwise as the driver sees it),
## whether the handbrake is on, and the gear (0: no gearbox to follow).
func update(dt: float, wheel_turn: float, handbrake: bool, gear := 0) -> void:
	var w := wheel_turn
	var turning := signf(w - _last_w)
	_last_w = w
	if not _has_brake:
		handbrake = false                                # no lever to pull: the hand stays on the wheel
	_lever_pull = move_toward(_lever_pull, 1.0 if handbrake else 0.0, dt * (9.0 if handbrake else 6.0))
	var pulled := Basis(Vector3.RIGHT, _lever_throw * _ease(_lever_pull))
	_lever.basis = pulled * _lever_rest
	if _brake_model:
		_brake_model.basis = pulled
	# the shifting hand and the handbrake
	var rh: Dictionary = _hand[shift_hand]
	if handbrake and rh.mode != "brake":
		rh.mode = "brake"
		rh.t = 0.0
		rh.from_xf = (_gloves[shift_hand] as Node3D).transform
	elif not handbrake and rh.mode == "brake":
		rh.mode = "move"
		rh.t = 0.0
		rh.src = "lever"
		rh.to = _home(shift_hand) + w
	# the shifting hand and the gear lever (an automatic shifts itself)
	var h_box := gear_kind in ["h4", "h5", "h6"]
	if gear > 0 and _last_gear > 0 and gear != _last_gear and not handbrake and gear_kind != "auto":
		var dir := signf(gear - _last_gear)
		if rh.mode == "shift":
			rh.dir = dir                                 # another change: flick it again once there
			rh.t = minf(rh.t, SHIFT_REACH)
			if h_box:
				_gate_from = _gate
				_gate_to = _h_gate(gear)
		elif absf(w) < SHIFT_MAX_TURN and (rh.mode == "grip" or (rh.mode == "move" and rh.src != "")):
			rh.mode = "shift"
			rh.t = 0.0
			rh.dir = dir
			rh.from_xf = (_gloves[shift_hand] as Node3D).transform
			if h_box:
				_gate_from = _gate
				_gate_to = _h_gate(gear)
		elif h_box:
			_gate = _h_gate(gear)                        # the hand can't go: (it's in gear all the same)
	if gear > 0:
		_last_gear = gear
	for k in 2:
		var h: Dictionary = _hand[k]
		match h.mode:
			"grip":
				# how far round from home the wheel's carried it since it took hold: not wrapped
				# (carried most of a turn is too far for an arm, though the hand's back near
				# where it started; wrapped, a big jump of the wheel read as turning the other
				# way and both hands ended up bunched on one spot)
				var off: float = h.g - w - _home(k)
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
					_start_move(h, k, w, _clear_of(k, to_off, other.g - w))
				elif other.mode == "grip" and absf(w) < 0.6 and absf(off) > 0.7 and turning == 0.0:
					_start_move(h, k, w, _clear_of(k, 0.0, other.g - w))   # wheel's back near straight: hands home
			"move":
				h.t += dt / MOVE_TIME
				if h.t >= 1.0:
					h.mode = "grip"
					h.g = h.to
			"brake":
				h.t = minf(h.t + dt / MOVE_TIME, 1.0)
			"shift":
				h.t += dt
				if h.t >= SHIFT_REACH + (H_TIME if h_box else SHIFT_FLICK):
					h.mode = "move"
					h.t = 0.0
					h.src = "gear"
					h.to = _home(shift_hand) + w
					if h_box:
						_gate = _gate_to
	var moved: Basis
	if h_box:
		# an H-pattern: through the gates while the hand has it, then it stays in gear
		if rh.mode == "shift" and rh.t > SHIFT_REACH:
			_gate = _h_path(_gate_from, _gate_to, clampf((rh.t - SHIFT_REACH) / H_TIME, 0.0, 1.0))
		moved = Basis(Vector3.RIGHT, H_ROW * _gate.y) * Basis(Vector3.BACK, -H_COL * _gate.x)
	else:
		# a sequential: over while the hand flicks it, then it springs back to the middle
		var kick := 0.0
		if rh.mode == "shift" and rh.t > SHIFT_REACH:
			kick = rh.dir
		_gear_kick = move_toward(_gear_kick, kick, dt / (0.04 if kick != 0.0 else 0.07))
		moved = Basis(Vector3.RIGHT, GEAR_THROW * _gear_kick)
	_gear.basis = moved * _gear_rest
	if _gear_model:
		_gear_model.basis = moved
	for k in 2:
		_place(k, w)


func _start_move(h: Dictionary, k: int, w: float, to_off: float) -> void:
	h.mode = "move"
	h.src = ""
	h.t = 0.0
	h.from = h.g - w
	h.to = _home(k) + to_off + w


## Where hand k takes its new grip (from its home, rad): `to_off`, or if that's on top of
## the other hand (at plane angle other_a), its home or the other side: never both on one spot.
func _clear_of(k: int, to_off: float, other_a: float) -> float:
	var best := to_off
	var best_gap := -1.0
	for c in [to_off, 0.0, -to_off]:
		var gap := absf(wrapf(_home(k) + c - other_a, -PI, PI))
		if gap >= 0.9:
			return c
		if gap > best_gap:
			best_gap = gap
			best = c
	return best


func _home(k: int) -> float:
	return PI if k == LEFT else 0.0


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
			if h.src == "lever":
				xf = _lever_grip().interpolate_with(_rim_grip(to_a, 0.0), u)
			elif h.src == "gear":
				xf = _gear_grip().interpolate_with(_rim_grip(to_a, 0.0), u)
			else:
				var from_a: float = h.from
				var a := from_a + wrapf(to_a - from_a, -PI, PI) * u
				xf = _rim_grip(a, sin(u * PI) * 0.06)      # lifted off the rim on the way
		"brake":
			xf = (h.from_xf as Transform3D).interpolate_with(_lever_grip(), _ease(h.t))
		"shift":
			xf = (h.from_xf as Transform3D).interpolate_with(_gear_grip(), _ease(minf(h.t / SHIFT_REACH, 1.0)))
	(_gloves[k] as Node3D).transform = xf
	wrists[k] = xf * (Basis(Vector3.RIGHT, GRIP_ROLL) * (_wrist[k] as Vector3))
	_aim_cuff(k)


## The gauntlets point up the forearms: call after the arms are posed, with the
## elbows ([left, right], cockpit space).
func aim_cuffs(elbows: Array) -> void:
	_elbows = elbows
	for k in 2:
		_aim_cuff(k)


func _aim_cuff(k: int) -> void:
	var xf: Transform3D = (_gloves[k] as Node3D).transform
	var up: Vector3
	if _elbows.size() == 2:
		up = (_elbows[k] - wrists[k]).normalized()
	else:
		up = (xf.basis * Vector3(0.0, -0.3, 1.0)).normalized()  # no arm to follow: back toward the driver
	var side := xf.basis.x
	side = (side - up * side.dot(up)).normalized()
	(_cuffs[k] as Node3D).transform = Transform3D(Basis(side, up, side.cross(up)), wrists[k])


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
	var top: Vector3 = _lever.transform * Vector3(0.0, _lever_len, 0.0)
	var up := (_lever.transform.basis * Vector3.UP).normalized()
	var toward := Vector3(-0.85 * _side(), 0.0, 0.5).normalized()        # back toward the driver's shoulder
	toward = (toward - up * toward.dot(up)).normalized()
	var out := up.cross(toward).normalized()
	return Transform3D(Basis(up, out, toward), top - up * (0.04 if _brake_model == null else 0.0))


## +1 when the shifting hand is the right one (the levers are on the driver's right), -1 the left.
func _side() -> float:
	return 1.0 if shift_hand == RIGHT else -1.0


## The grip on the gear lever: fingers round the knob's front, palm to the driver.
func _gear_grip() -> Transform3D:
	var stem := _gear_len
	var up := (_gear.transform.basis * Vector3.UP).normalized()
	var top: Vector3 = _gear.transform * Vector3(0.0, stem - (0.02 if _gear_model == null else 0.0), 0.0)
	var toward := Vector3(-0.7 * _side(), 0.0, 0.72).normalized()          # back toward the driver's shoulder
	toward = (toward - up * toward.dot(up)).normalized()
	var out := up.cross(toward).normalized()
	return Transform3D(Basis(up, out, toward), top)


static func _ease(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)


# ── models ────────────────────────────────────────────────────────────────

## The model's gloves in place of the built ones (if it's there): the right hand's as it is, the
## left's mirrored; each gauntlet from the wrist up the forearm.
func _model_gloves() -> void:
	if not ResourceLoader.exists(GLOVES):
		return
	var scene: Node = (load(GLOVES) as PackedScene).instantiate()
	var glove: Mesh = null
	var cuff: Mesh = null
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		if str(mi.name).begins_with("Glove"):
			glove = (mi as MeshInstance3D).mesh
		elif str(mi.name).begins_with("Cuff"):
			cuff = (mi as MeshInstance3D).mesh
	scene.free()
	if glove == null or cuff == null:
		return
	model_gloves = true
	for k in 2:
		var right := k == RIGHT
		(_gloves[k] as MeshInstance3D).mesh = glove if right else _mirror_x(glove)
		(_cuffs[k] as MeshInstance3D).mesh = cuff if right else _mirror_x(cuff)
		_wrist[k] = Vector3(MODEL_WRIST.x * (1.0 if right else -1.0), MODEL_WRIST.y, MODEL_WRIST.z)


## The same mesh mirrored left to right (x -> -x), its faces turned back outward: the left
## hand's glove from the right's (the textures shared).
static func _mirror_x(src: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var arr := src.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in v.size():
			v[i].x = -v[i].x
		arr[Mesh.ARRAY_VERTEX] = v
		if arr[Mesh.ARRAY_NORMAL] != null:
			var nm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in nm.size():
				nm[i].x = -nm[i].x
			arr[Mesh.ARRAY_NORMAL] = nm
		if arr[Mesh.ARRAY_TANGENT] != null:
			var tg: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
			for i in range(0, tg.size(), 4):
				tg[i] = -tg[i]
				tg[i + 3] = -tg[i + 3]                   # (mirrored: the bitangent's side flips too)
			arr[Mesh.ARRAY_TANGENT] = tg
		if arr[Mesh.ARRAY_INDEX] != null:
			var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for i in range(0, ix.size() - 2, 3):
				var t := ix[i + 1]
				ix[i + 1] = ix[i + 2]
				ix[i + 2] = t
			arr[Mesh.ARRAY_INDEX] = ix
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(si, src.surface_get_material(si))
	return out


func _mat(c: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


## A racing glove gripping a bar along its x axis (the rim): the palm on the +z
## side (toward the wrist), the back of the hand outward (+y), four fingers
## curling over the outside, round the front and back in underneath, the thumb
## across the face of the bar on the inside. ts: which way the thumb is along x
## (+1 right hand, -1 left: the index finger is on top either way). All the parts
## are baked into one mesh, a surface per material.
func _glove(ts: float, mats: Dictionary) -> ArrayMesh:
	var parts := {}
	var roll := Transform3D(Basis(Vector3.RIGHT, GRIP_ROLL))
	var add := func(key: String, mesh: Mesh, xf: Transform3D) -> void: _add(parts, key, mesh, roll * xf)
	var x := Vector3.RIGHT
	# the back of the hand: from the wrist to the knuckle line, which stands proud
	# on the outside of the rim
	var knuckle_a := deg_to_rad(72.0)
	var kr := RIM_R + 0.021
	var knuckle := Vector3(0.0, kr * sin(knuckle_a), kr * cos(knuckle_a))
	var w := WRIST + Vector3(0.0, 0.004, -0.008)
	var d := (knuckle - w).normalized()                      # along the back of the hand
	var n := x.cross(d).normalized()                          # out of the back of the hand
	if n.dot(knuckle + w) < 0.0:
		n = -n
	var mid := (knuckle + w) * 0.5
	var half := knuckle.distance_to(w) * 0.5
	add.call("glove", _ball(), Transform3D(Basis(x * 0.046, d * (half + 0.014), n * 0.0165), mid))
	add.call("panel", _ball(), Transform3D(Basis(x * 0.035, d * (half * 0.82), n * 0.0135), mid + n * 0.0048 - d * 0.004))
	# the heel of the hand and the thumb's mound, filling under toward the rim
	add.call("glove", _ball(), Transform3D(Basis(x * 0.04, d * 0.024, n * 0.016), w + d * 0.016 - n * 0.006))
	add.call("glove", _ball(), Transform3D(Basis(x * 0.02, d * 0.026, n * 0.016), Vector3(ts * 0.03, 0.012, 0.054)))
	# fingers: index, middle, ring, little (x from the thumb side)
	var fx := [0.031, 0.0105, -0.0105, -0.0295]
	var fr := [0.0102, 0.0106, 0.0101, 0.0091]
	var tip := [238.0, 248.0, 240.0, 226.0]
	for i in 4:
		var r: float = fr[i]
		var rf: float = RIM_R + r * 0.92
		var fxi: float = ts * fx[i]
		var base := Vector3(fxi, knuckle.y, knuckle.z)
		var pts := [base]
		for deg in [130.0, 185.0, tip[i]]:
			var a := deg_to_rad(deg)
			pts.append(Vector3(fxi * (1.0 - 0.06 * (deg - 72.0) / 180.0), rf * sin(a), rf * cos(a)))
		for j in 3:
			add.call("glove", _capsule_mesh(r + 0.0007 - j * 0.0007, pts[j].distance_to(pts[j + 1])), _seg_xf(pts[j], pts[j + 1]))
		# the knuckle and its pad
		add.call("glove", _ball(), Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (r + 0.0016)), base))
		add.call("pad", _ball(), Transform3D(Basis(x * (r * 0.95), d * 0.009, n * 0.006), base + n * (r * 0.62) - d * 0.003))
	# the thumb: from the mound across the face of the rim, round its inside
	var tp := [Vector3(ts * 0.034, 0.008, 0.058), Vector3(ts * 0.041, -0.006, 0.036),
		Vector3(ts * 0.036, -0.022, 0.022), Vector3(ts * 0.026, -0.031, 0.009)]
	var tr := [0.0125, 0.0112, 0.0102]
	for j in 3:
		add.call("glove", _capsule_mesh(tr[j], tp[j].distance_to(tp[j + 1])), _seg_xf(tp[j], tp[j + 1]))
	return _bake(parts, mats)


## The gauntlet: a flared cuff along +Y (up the forearm) from the wrist, with a
## strap in the suit's colour round it and a white edge at the open end.
func _gauntlet(mats: Dictionary) -> ArrayMesh:
	var parts := {}
	_add(parts, "glove", _lathe(CUFF, 16), Transform3D.IDENTITY)
	var strap := []
	for u in [0.024, 0.028, 0.046, 0.05]:
		strap.append([u, _cuff_r(u) + (0.0035 if u > 0.026 and u < 0.048 else 0.0)])
	_add(parts, "panel", _lathe(strap, 16), Transform3D.IDENTITY)
	_add(parts, "panel", _ball(), Transform3D(Basis(Vector3.RIGHT * 0.012, Vector3.UP * 0.013, Vector3.BACK * 0.006),
		Vector3(0.0, 0.037, -(_cuff_r(0.037) + 0.003))))   # the velcro tab, on the back of the wrist
	var edge := []
	for u in [0.093, 0.095, 0.103, 0.105]:
		edge.append([u, _cuff_r(u) + (0.0018 if u > 0.094 and u < 0.104 else 0.0)])
	_add(parts, "trim", _lathe(edge, 16), Transform3D.IDENTITY)
	return _bake(parts, mats)


static func _cuff_r(u: float) -> float:
	for i in CUFF.size() - 1:
		if u <= CUFF[i + 1][0]:
			return lerpf(CUFF[i][1], CUFF[i + 1][1], inverse_lerp(CUFF[i][0], CUFF[i + 1][0], u))
	return CUFF[-1][1]


## A surface of revolution round +Y through [[y, radius], ...], smooth shaded.
static func _lathe(profile: Array, seg: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var nm := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in profile.size():
		var p: Array = profile[i]
		var a: Array = profile[maxi(i - 1, 0)]
		var b: Array = profile[mini(i + 1, profile.size() - 1)]
		var slope: float = (b[1] - a[1]) / maxf(b[0] - a[0], 1e-5)    # dr/dy
		for k in seg + 1:
			var t := TAU * k / seg
			var radial := Vector3(sin(t), 0.0, cos(t))
			v.append(radial * float(p[1]) + Vector3.UP * float(p[0]))
			nm.append((radial - Vector3.UP * slope).normalized())
	for i in profile.size() - 1:
		for k in seg:
			var a0 := i * (seg + 1) + k
			var b0 := a0 + seg + 1
			idx.append_array([a0, b0, a0 + 1, a0 + 1, b0, b0 + 1])      # clockwise seen from outside: Godot's front
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nm
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _ball() -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 14
	m.rings = 7
	return m


static func _capsule_mesh(r: float, length: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = length + r * 2.0
	m.radial_segments = 10
	m.rings = 2
	return m


## The transform that lays a mesh built along +Y between points a and b.
static func _seg_xf(a: Vector3, b: Vector3) -> Transform3D:
	var up := (b - a).normalized()
	var side := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := side.cross(up).normalized()
	return Transform3D(Basis(x, up, x.cross(up).normalized()), (a + b) * 0.5)


## Add a mesh (its first surface, moved by xf) to the parts for material `key`.
static func _add(parts: Dictionary, key: String, mesh: Mesh, xf: Transform3D) -> void:
	if not parts.has(key):
		parts[key] = [PackedVector3Array(), PackedVector3Array(), PackedInt32Array()]
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = parts[key][0]
	var nm: PackedVector3Array = parts[key][1]
	var idx: PackedInt32Array = parts[key][2]
	var base := v.size()
	var nb := xf.basis.inverse().transposed()      # normals through a squashed ball stay right
	for p in arr[Mesh.ARRAY_VERTEX]:
		v.append(xf * p)
	for q in arr[Mesh.ARRAY_NORMAL]:
		nm.append((nb * q).normalized())
	for i in arr[Mesh.ARRAY_INDEX]:
		idx.append(base + i)
	parts[key] = [v, nm, idx]


static func _bake(parts: Dictionary, mats: Dictionary) -> ArrayMesh:
	var m := ArrayMesh.new()
	for key in parts:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = parts[key][0]
		arr[Mesh.ARRAY_NORMAL] = parts[key][1]
		arr[Mesh.ARRAY_INDEX] = parts[key][2]
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(m.get_surface_count() - 1, mats[key])
	return m


## The tall hydraulic handbrake beside the driver's seat: black lever, red grip.
func _build_lever() -> void:
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.06, 0.12)
	base.mesh = bm
	base.material_override = _mat(Color(0.12, 0.12, 0.13), 0.5)
	base.position = LEVER_BASE + Vector3(0.0, 0.0, 0.01)
	add_child(base)
	_lever_base = base
	_lever = Node3D.new()
	_lever.position = LEVER_BASE
	_lever.basis = _lever_rest
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


## The sequential gear lever, out of the tunnel (the cockpit has its boot): a
## silver rod, a black grip and a red knob on top.
func _build_gear() -> void:
	var stem := GEAR_BASE.distance_to(GEAR_TOP)
	var up := (GEAR_TOP - GEAR_BASE).normalized()
	var x := (Vector3.RIGHT - up * up.dot(Vector3.RIGHT)).normalized()
	_gear_rest = Basis(x, up, x.cross(up))
	_gear_len = stem
	_gear = Node3D.new()
	_gear.name = "GearLever"
	_gear.position = GEAR_BASE
	_gear.basis = _gear_rest
	add_child(_gear)
	for part in [[0.009, 0.009, stem, stem * 0.5, Color(0.62, 0.62, 0.65), 0.3],        # rod
			[0.016, 0.016, 0.08, stem - 0.01, Color(0.06, 0.06, 0.06), 0.7]]:         # grip
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = part[0]
		cm.bottom_radius = part[1]
		cm.height = part[2]
		cm.radial_segments = 10
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = _mat(part[4], part[5])
		mi.position = Vector3(0.0, part[3], 0.0)
		_gear.add_child(mi)
	var cap := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.019
	sm.height = 0.024
	sm.radial_segments = 10
	sm.rings = 4
	cap.mesh = sm
	cap.material_override = _mat(Color(0.85, 0.1, 0.1), 0.4)
	cap.position = Vector3(0.0, stem + 0.035, 0.0)
	_gear.add_child(cap)
