extends RefCounted
## The crew's six-point harnesses, fitted to their bodies as they sit: two
## shoulder straps from the harness bar behind the seats, through the seat's
## slots, over the shoulders (padded there) and down the chest; two lap belts
## from beside the hips over the tops of the thighs; two short crotch straps;
## all into a round cam-lock buckle low on the belly, with a steel adjuster on
## each strap. Black webbing, as most rally harnesses are (and it shows on a red
## or a blue suit).
## Each strap is laid on the posed body (crew_model.gd body_points()): pulled
## straight between its anchors, pushed out wherever the body is in the way,
## smoothed, and pushed out again, so it sits on the shoulders and the chest and
## bridges the hollows like a tight strap. Built once, after the first pose: the
## torso doesn't move, and the arms are left out of the fit.

const WEB := 0.046          # m: strap width (3" webbing at the crew's scale)
const WEB_T := 0.0035       # m: thickness
const PAD_W := 0.07         # shoulder pads
const PAD_T := 0.014
const GAP := 0.011          # m off the suit (the points are a thinned sample of it)
const REACH := 0.014        # m: how close to the strap's line a body point has to be to push it (the surface is sampled every cm)

const WEBBING := Color(0.07, 0.07, 0.075)
const PADDING := Color(0.12, 0.12, 0.13)
const STEEL := Color(0.74, 0.75, 0.77)


## Fit a harness to `model` (a posed CrewModel). bar_y / bar_z: the harness bar
## behind the seats. The mesh is drawn on `layers` (the model's own).
static func build(model, bar_y: float, bar_z: float, layers: int) -> MeshInstance3D:
	var hips: Vector3 = model.bone("Hips")
	var region := AABB(hips + Vector3(-0.32, -0.2, -0.35), Vector3(0.64, 0.95, 0.6))     # hips to shoulders, thighs
	var pts: PackedVector3Array = model.body_points(0.012, region)
	if pts.size() < 100:
		return null
	var chest: Vector3 = model.bone("Spine")
	var c := hips.x
	var fwd := Vector3(0.0, 0.22, -1.0).normalized()            # out of the chest (they sit leaning back a little)
	var parts := {"web": [], "pad": [], "steel": []}
	for k in parts:
		parts[k] = [PackedVector3Array(), PackedVector3Array(), PackedInt32Array()]
	# the buckle: low on the belly, on the centre line
	var buckle := _push(Vector3(c, hips.y + 0.11, hips.z), fwd, pts, true)
	for side in [-1.0, 1.0]:
		var sh: Vector3 = model.bone("LeftShoulder" if side < 0.0 else "RightShoulder")
		var xs: float = c + side * 0.1
		# shoulder strap: bar -> seat slot -> over the shoulder (under the rim of
		# the helmet, which comes down over it) -> down the chest to the buckle
		var top := Vector3(xs, sh.y + 0.07, chest.z)
		var centre := Vector3(xs, chest.y - 0.06, chest.z + 0.01)   # inside the shoulder: the strap wraps round it
		var bar := Vector3(c + side * 0.07, bar_y + 0.026, bar_z)
		var slot := Vector3(c + side * 0.085, top.y + 0.02, top.z + 0.17)
		var path: Array = [bar]
		_line(path, slot, 3)
		var first := path.size()
		_line(path, top + Vector3(0.0, 0.0, 0.05), 4)
		var s_top := _arc_at(path, path.size() - 1)
		_line(path, buckle + Vector3(side * 0.03, 0.035, 0.0), 24)
		var out_of := func(p: Vector3) -> Vector3:
			if p.y <= centre.y:
				return fwd
			var d := p - centre
			d.x = 0.0
			return d.normalized()
		var near := _near(pts, path, 0.08)
		var dirs := _lay(path, first, out_of, near)
		for i in first:
			dirs[i] = Vector3.UP
		_settle(path, dirs, first, WEB, near)
		_ribbon(parts.web, path, dirs, WEB, WEB_T, 0.0, 1e9)
		_ribbon(parts.pad, path, dirs, PAD_W, PAD_T, s_top - 0.06, s_top + 0.2)
		_adjuster(parts.steel, path, dirs, _arc_at(path, path.size() - 1) - 0.09)
		# lap belt: from the seat beside the hip, over the top of the thigh, into the buckle
		var lap_c := Vector3(c, hips.y - 0.1, hips.z + 0.02)
		var lap: Array = [Vector3(c + side * 0.215, hips.y - 0.06, hips.z + 0.09)]
		_line(lap, buckle + Vector3(side * 0.035, -0.012, 0.0), 16)
		var lap_near := _near(pts, lap, 0.08)
		var lap_dirs := _lay(lap, 1, func(p: Vector3) -> Vector3: return (p - lap_c).normalized(), lap_near)
		_settle(lap, lap_dirs, 1, WEB, lap_near)
		_ribbon(parts.web, lap, lap_dirs, WEB, WEB_T, 0.0, 1e9)
		_adjuster(parts.steel, lap, lap_dirs, _arc_at(lap, lap.size() - 1) * 0.55)
		# crotch strap: from the buckle down between the legs
		var sub: Array = [buckle + Vector3(side * 0.016, -0.02, 0.004)]
		_line(sub, Vector3(c + side * 0.04, hips.y - 0.09, hips.z - 0.1), 6)
		var sub_dirs: Array = []
		for p in sub:
			sub_dirs.append(fwd)
		_ribbon(parts.web, sub, sub_dirs, WEB * 0.9, WEB_T, 0.0, 1e9)
	# the cam-lock: a steel disc with a black turning dial
	_disc(parts.steel, buckle + fwd * 0.004, fwd, 0.036, 0.011)
	_disc(parts.pad, buckle + fwd * 0.013, fwd, 0.02, 0.008)
	var mesh := ArrayMesh.new()
	var mats := {"web": _mat(WEBBING, 0.95, 0.0), "pad": _mat(PADDING, 0.9, 0.0), "steel": _mat(STEEL, 0.3, 0.8)}
	for k in parts:
		var a: Array = parts[k]
		if a[2].is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = a[0]
		arr[Mesh.ARRAY_NORMAL] = a[1]
		arr[Mesh.ARRAY_INDEX] = a[2]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[k])
	var mi := MeshInstance3D.new()
	mi.name = "Harness"
	mi.mesh = mesh
	mi.layers = layers
	return mi


## Lay a strap on the body like a tight strap: pull it straight (smooth it),
## push it back out of the body along out_of(point), and again, the ends (and
## everything before `first`) held. Returns each point's out-of-the-body direction.
static func _lay(path: Array, first: int, out_of: Callable, pts: PackedVector3Array, rounds := 5) -> Array:
	for r in rounds:
		if r > 0:
			_smooth(path, first, 1)
		for i in range(first, path.size() - 1):
			path[i] = _push(path[i], out_of.call(path[i]), pts, false)
	var dirs: Array = []
	for p in path:
		dirs.append(out_of.call(p))
	return dirs


## Lie each bit of strap flat on the body across its width: find the body under
## both its edges, turn it to match that slope (dirs: out of the body), and lift
## it if an edge would still be in the suit.
static func _settle(path: Array, dirs: Array, first: int, w: float, pts: PackedVector3Array) -> void:
	for i in range(first, path.size() - 1):
		var p: Vector3 = path[i]
		var tan: Vector3 = ((path[i + 1] as Vector3) - path[i - 1]).normalized()
		var out: Vector3 = dirs[i]
		var side := tan.cross(out).normalized()
		var l := _push(p - side * w * 0.5, out, pts, true)
		var r := _push(p + side * w * 0.5, out, pts, true)
		var new_side := (r - l).normalized()
		var new_out := new_side.cross(tan).normalized()
		if new_out.dot(out) < 0.5:
			continue                                 # the body's too uneven under it: leave it square
		dirs[i] = new_out
		var lift := maxf((l - (p - new_side * w * 0.5)).dot(new_out), (r - (p + new_side * w * 0.5)).dot(new_out))
		if lift > 0.0:
			path[i] = p + new_out * lift


## The body points within `margin` of the box round `path` (fewer to test).
static func _near(pts: PackedVector3Array, path: Array, margin: float) -> PackedVector3Array:
	var box := AABB(path[0], Vector3.ZERO)
	for p in path:
		box = box.expand(p)
	box = box.grow(margin)
	var out := PackedVector3Array()
	for q in pts:
		if box.has_point(q):
			out.append(q)
	return out


## Points from the last one in `path` to `to`, `n` steps (to included).
static func _line(path: Array, to: Vector3, n: int) -> void:
	var from: Vector3 = path[path.size() - 1] if not path.is_empty() else to
	for i in range(1, n + 1):
		path.append(from.lerp(to, float(i) / n))


## Move p along dir until it's clear of the body (every point within REACH of
## that line), GAP off it. pull: also move it in onto the body if it's floating.
static func _push(p: Vector3, dir: Vector3, pts: PackedVector3Array, pull: bool) -> Vector3:
	var best := -INF
	var r2 := REACH * REACH
	for q in pts:
		var d := q - p
		var t := d.dot(dir)
		if t > best and d.length_squared() - t * t < r2:
			best = t
	if best == -INF:
		return p
	var move := best + GAP
	if move < 0.0 and not pull:
		return p
	return p + dir * move


static func _smooth(path: Array, from: int, passes: int) -> void:
	for n in passes:
		var prev: Array = path.duplicate()
		for i in range(maxi(from, 1), path.size() - 1):
			path[i] = (prev[i - 1] + prev[i] * 2.0 + prev[i + 1]) * 0.25


static func _arc_at(path: Array, i: int) -> float:
	var s := 0.0
	for k in range(1, i + 1):
		s += (path[k] as Vector3).distance_to(path[k - 1])
	return s


## A strap along `path` (its inner face on the path, `dirs` pointing out of the
## body), between arc lengths s0 and s1: a flat box section, so it has edges.
static func _ribbon(part: Array, path: Array, dirs: Array, w: float, t: float, s0: float, s1: float) -> void:
	var rings: Array = []
	var s := 0.0
	for i in path.size():
		if i > 0:
			s += (path[i] as Vector3).distance_to(path[i - 1])
		if s < s0 or s > s1:
			continue
		var tan: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var out: Vector3 = dirs[i]
		var side := tan.cross(out).normalized()
		out = side.cross(tan).normalized()
		rings.append([path[i] as Vector3, side, out])
	if rings.size() < 2:
		return
	# four faces: out, in, and the two edges (each its own vertices: hard edges)
	var faces := [[1.0, 0.0], [-1.0, 0.0], [0.0, 1.0], [0.0, -1.0]]
	for f in faces:
		var base: int = part[0].size()
		for rg in rings:
			var p: Vector3 = rg[0]
			var sd: Vector3 = rg[1]
			var ot: Vector3 = rg[2]
			var mid := p + ot * (t * 0.5)
			var n: Vector3 = ot * f[0] + sd * f[1]
			var a: Vector3
			var b: Vector3
			if f[1] == 0.0:                     # out / in face: across the width
				a = mid + ot * (t * 0.5 * f[0]) - sd * (w * 0.5)
				b = mid + ot * (t * 0.5 * f[0]) + sd * (w * 0.5)
			else:                               # an edge: across the thickness
				a = mid + sd * (w * 0.5 * f[1]) - ot * (t * 0.5)
				b = mid + sd * (w * 0.5 * f[1]) + ot * (t * 0.5)
			part[0].append(a)
			part[0].append(b)
			part[1].append(n)
			part[1].append(n)
		for i in rings.size() - 1:
			var i0: int = base + i * 2
			var flip: bool = (f[0] > 0.0) or (f[1] < 0.0)     # Godot: front faces wind clockwise
			if flip:
				part[2].append_array([i0, i0 + 2, i0 + 1, i0 + 1, i0 + 2, i0 + 3])
			else:
				part[2].append_array([i0, i0 + 1, i0 + 2, i0 + 1, i0 + 3, i0 + 2])


## A steel adjuster on a strap at arc length s: a band round it.
static func _adjuster(part: Array, path: Array, dirs: Array, s: float) -> void:
	var sub: Array = []
	var sub_dirs: Array = []
	var acc := 0.0
	for i in range(1, path.size()):
		var seg: float = (path[i] as Vector3).distance_to(path[i - 1])
		if acc + seg >= s:
			var p: Vector3 = (path[i - 1] as Vector3).lerp(path[i], (s - acc) / maxf(seg, 1e-5))
			var tan: Vector3 = ((path[i] as Vector3) - path[i - 1]).normalized()
			var d: Vector3 = dirs[i]
			sub = [p - tan * 0.011 - d * 0.002, p + tan * 0.011 - d * 0.002]
			sub_dirs = [d, d]
			break
		acc += seg
	if sub.size() == 2:
		_ribbon(part, sub, sub_dirs, WEB + 0.009, WEB_T + 0.005, 0.0, 1e9)


## A disc (a short cylinder) at p facing `n`.
static func _disc(part: Array, p: Vector3, n: Vector3, r: float, h: float) -> void:
	var u := n.cross(Vector3.RIGHT).normalized()
	if u.length() < 0.5:
		u = n.cross(Vector3.UP).normalized()
	var v := n.cross(u)
	var seg := 20
	var base: int = part[0].size()
	# the face
	part[0].append(p + n * h * 0.5)
	part[1].append(n)
	for i in seg:
		var a := TAU * i / seg
		part[0].append(p + n * h * 0.5 + (u * cos(a) + v * sin(a)) * r)
		part[1].append(n)
	for i in seg:
		part[2].append_array([base, base + 1 + (i + 1) % seg, base + 1 + i])
	# the rim
	var rb: int = part[0].size()
	for i in seg:
		var a := TAU * i / seg
		var o := u * cos(a) + v * sin(a)
		part[0].append(p + n * h * 0.5 + o * r)
		part[0].append(p - n * h * 0.5 + o * r)
		part[1].append(o)
		part[1].append(o)
	for i in seg:
		var a0: int = rb + i * 2
		var a1: int = rb + ((i + 1) % seg) * 2
		part[2].append_array([a0, a1, a0 + 1, a1, a1 + 1, a0 + 1])


static func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m
