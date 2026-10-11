extends RefCounted
## The garage's wheels, built in code to any size (the WheelPreset system: wheel_presets.gd):
## a tyre, a rim, a brake disc and a caliper, each its own mesh (the tyre, rim and disc spin; the
## caliper stays put on the upright). In metres, the wheel centred on the origin, its axle along
## x, its face (the side you see from outside the car) at +x: a left wheel is the same wheel
## mirrored (scale x -1), as a real one is mounted, so directional tread and the face stay right.
##
##   tyre(outer_r, width, rim_r, tread, seg)   tread: "street" (four grooves), "slick", "wet"
##                                             (grooves and sipes), "vintage" (tall, a whitewall)
##   rim(rim_r, width, style, seg)             style: {spokes, kind ("straight" / "split" / "mesh" /
##                                             "dish" / "y"), spoke_w (rad at the barrel), taper,
##                                             concave (m), lip (m), nut ("lugs" / "centre"), pcd}
##   disc(r, hat_r, x, seg)                    a ventilated disc and its bell, its middle at x
##   caliper(disc_r, x, pistons)               a fixed caliper over the disc's trailing edge
##   brake_x(width, style, pistons)            where the disc goes across the wheel: inboard of
##                                             the spokes' backs with the caliper's room
##
## Surfaces: the tyre 0 rubber (1 the whitewall); the rim 0 its paint (the garage's wheel colour
## replaces it), 1 the bright metal (nuts, the lip's polish), 2 the barrel's inside; the disc
## 0 iron, 1 the bell; the caliper 0 its paint. Meshes are cached by their numbers.

const SEG_HI := 64                   # around the wheel (LOD0)
const SEG_LO := 20                   # (LOD1: far away)
const CREASE := 0.6                  # rad: a profile corner sharper than this keeps hard normals

static var _cache := {}


# ── the tyre ──────────────────────────────────────────────────────────────

static func tyre(outer_r: float, width: float, rim_r: float, tread := "street", seg := SEG_HI) -> ArrayMesh:
	var key := "t_%.4f_%.4f_%.4f_%s_%d" % [outer_r, width, rim_r, tread, seg]
	if _cache.has(key):
		return _cache[key]
	var h := width * 0.5
	var side := outer_r - rim_r                          # the sidewall's height
	var sh := minf(side * 0.28, width * 0.12)            # the shoulder's radius
	if tread == "slick":
		sh = minf(side * 0.2, width * 0.07)
	# the cross-section (x, r), counter-clockwise round the rubber: bead, sidewall, shoulder, crown ...
	var p: Array = []
	p.append(Vector2(h * 0.86, rim_r - 0.004))
	p.append(Vector2(h * 0.94, rim_r + side * 0.12))
	p.append(Vector2(h * 1.0, rim_r + side * 0.45))      # the bulge
	p.append(Vector2(h * 0.985, rim_r + side * 0.72))
	for i in 5:                                           # the shoulder, rounded
		var a := PI * 0.5 * float(i) / 4.0
		p.append(Vector2(h - sh + sh * cos(a) * 0.98, outer_r - sh + sh * sin(a)))
	var crown := _crown(h - sh, outer_r, tread)
	for c in crown:
		p.append(c)
	var n := p.size()
	for i in range(n - 1, -1, -1):                        # the other side, mirrored
		var q: Vector2 = p[i]
		if absf(q.x) > 1e-5:
			p.append(Vector2(-q.x, q.y))
	var st := _st()
	_revolve(st, p, seg, Vector2(0.0, rim_r + side * 0.5), true)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	mesh.surface_set_material(0, _mat("rubber", Color(0.055, 0.055, 0.06), 0.0, 0.88 if tread != "slick" else 0.62))
	if tread == "vintage":                                # the whitewall: a ring on the face's sidewall
		var w := _st()
		var ww: Array = [Vector2(h * 1.002, rim_r + side * 0.3), Vector2(h * 1.012, rim_r + side * 0.45), Vector2(h * 1.0, rim_r + side * 0.62)]
		_revolve(w, ww, seg, Vector2(0.0, rim_r + side * 0.45), false)
		w.commit(mesh)
		mesh.surface_set_material(1, _mat("whitewall", Color(0.9, 0.89, 0.86), 0.0, 0.7))
	_cache[key] = mesh
	return mesh


## The crown from the shoulder at +x across to x = 0 (the profile goes on mirrored): grooves cut
## round it for a road or wet tyre, smooth for a slick.
static func _crown(x0: float, r: float, tread: String) -> Array:
	var out: Array = []
	var grooves: Array = []
	match tread:
		"street":
			grooves = [0.62, 0.22]                        # (of x0: two grooves each side of the middle)
		"wet":
			grooves = [0.78, 0.48, 0.16]
		"vintage":
			grooves = [0.7, 0.35]
	var gw := 0.0075                                      # half a groove's width
	var depth := 0.007
	var x := x0
	for g in grooves:
		var gx: float = x0 * float(g)
		out.append(Vector2(gx + gw, r))
		out.append(Vector2(gx + gw * 0.6, r - depth))
		out.append(Vector2(gx - gw * 0.6, r - depth))
		out.append(Vector2(gx - gw, r))
		x = gx
	out.append(Vector2(0.0, r))
	return out


# ── the rim ───────────────────────────────────────────────────────────────

static func rim(rim_r: float, width: float, style: Dictionary, seg := SEG_HI) -> ArrayMesh:
	var key := "r_%.4f_%.4f_%s_%d" % [rim_r, width, JSON.stringify(style), seg]
	if _cache.has(key):
		return _cache[key]
	var h := width * 0.5
	var lip := float(style.get("lip", 0.012))            # the outer lip's depth (a deep dish: more)
	var face := h - lip - 0.004                           # where the spokes meet the rim's face
	var concave := float(style.get("concave", 0.02))
	var barrel_r := rim_r - 0.012                         # the inside of the barrel
	var paint := _st()
	var metal := _st()
	var inner := _st()
	# the barrel: lip, the bead seats, the drop centre (the tyre's inside covers most of it)
	var prof: Array = [Vector2(h + 0.002, rim_r + 0.012), Vector2(h - 0.004, rim_r + 0.014), Vector2(h - lip, rim_r - 0.002),
		Vector2(h - lip - 0.006, barrel_r)]
	_revolve(metal if lip > 0.03 else paint, prof, seg, Vector2(h - lip * 0.5, rim_r - 0.01), false)
	var back: Array = [Vector2(h - lip - 0.006, barrel_r), Vector2(-h * 0.2, drop_r(rim_r)), Vector2(-h + 0.006, barrel_r),
		Vector2(-h - 0.002, rim_r + 0.012)]
	_revolve(inner, back, seg, Vector2(0.0, 0.0), false)
	# the face ring the spokes run into, and the hub
	var r1 := barrel_r - 0.008                            # the spokes' outer ends
	var hub_r := rim_r * float(style.get("hub", 0.3))
	_annulus(paint, barrel_r, r1 - 0.004, face, seg)
	_annulus(paint, hub_r, 0.0, face - concave, seg)
	_revolve(paint, [Vector2(face - concave, hub_r), Vector2(face - concave - 0.03, hub_r * 1.02)], seg, Vector2(-1.0, 0.0), false)
	# spokes
	var n := int(style.get("spokes", 5))
	var kind := str(style.get("kind", "straight"))
	var sw := float(style.get("spoke_w", 0.22))           # angular width at the barrel (rad)
	var taper := float(style.get("taper", 1.6))           # x wider (angularly) at the hub
	var t := float(style.get("thick", 0.028))
	match kind:
		"split":
			for i in n:
				var a := TAU * i / n
				_spoke(paint, a - sw * 0.55, a - sw * 0.1, hub_r, r1, sw * 0.4, taper * 0.6, face, concave, t, 0.0)
				_spoke(paint, a + sw * 0.55, a + sw * 0.1, hub_r, r1, sw * 0.4, taper * 0.6, face, concave, t, 0.0)
		"mesh":
			for i in n:
				var a := TAU * i / n
				_spoke(paint, a, a + 0.32, hub_r, r1, sw, 1.0, face, concave, t * 0.8, 0.0)
				_spoke(paint, a, a - 0.32, hub_r, r1, sw, 1.0, face, concave, t * 0.8, 0.004)
		"y":
			for i in n:
				var a := TAU * i / n
				_spoke(paint, a, a, hub_r, lerpf(hub_r, r1, 0.45), sw * 1.2, taper, face, concave, t, 0.0)
				_spoke(paint, a - sw * 0.6, a, lerpf(hub_r, r1, 0.4), r1, sw * 0.5, 1.4, face, concave * 0.55, t, 0.0)
				_spoke(paint, a + sw * 0.6, a, lerpf(hub_r, r1, 0.4), r1, sw * 0.5, 1.4, face, concave * 0.55, t, 0.0)
		_:
			for i in n:
				var a := TAU * i / n
				_spoke(paint, a, a, hub_r, r1, sw, taper, face, concave, t, 0.0)
	# the nuts: five lugs on the pitch circle, or one big centre-lock nut
	var hub_x := face - concave
	if str(style.get("nut", "lugs")) == "centre":
		_prism(metal, Vector3(hub_x + 0.022, 0.0, 0.0), hub_r * 0.62, 0.03, 6, 0.0)
		_prism(metal, Vector3(hub_x + 0.04, 0.0, 0.0), hub_r * 0.25, 0.02, 12, 0.0)
	else:
		var pcd := float(style.get("pcd", 0.057))
		for i in 5:
			var a := TAU * i / 5.0 + PI * 0.5
			_prism(metal, Vector3(hub_x + 0.009, pcd * cos(a), pcd * sin(a)), 0.0105, 0.018, 6, a)
		_prism(metal, Vector3(hub_x + 0.006, 0.0, 0.0), hub_r * 0.42, 0.012, 24, 0.0)    # the centre cap
	var mesh := ArrayMesh.new()
	paint.commit(mesh)
	metal.commit(mesh)
	inner.commit(mesh)
	mesh.surface_set_material(0, _mat("rim_paint", Color(0.72, 0.73, 0.75), 0.75, 0.3))
	mesh.surface_set_material(1, _mat("rim_metal", Color(0.86, 0.87, 0.88), 1.0, 0.18))
	mesh.surface_set_material(2, _mat("rim_inner", Color(0.42, 0.43, 0.45), 0.7, 0.5))
	_cache[key] = mesh
	return mesh


## A spoke from the hub (r0, at angle a0) to the rim's face ring (r1, at angle a1): its angular
## width w at r1 (taper x at r0, as an arc), its front face concave (recessed `concave` at the
## hub), `t` thick behind it; dz nudges it back (a mesh wheel's crossing spokes).
static func _spoke(st: SurfaceTool, a1: float, a0: float, r0: float, r1: float, w: float, taper: float, face: float,
		concave: float, t: float, dz: float) -> void:
	var steps := 5
	var front: Array = []
	var backs: Array = []
	for i in steps + 1:
		var f := float(i) / steps
		var r := lerpf(r0, r1, f)
		var a := lerpf(a0, a1, f)
		var hw := lerpf(w * taper, w, f) * 0.5               # (angular: the spoke widens out to the barrel)
		var x := face - concave * (1.0 - f) * (1.0 - f * 0.4) - dz
		front.append([_p(x, r, a - hw), _p(x, r, a + hw)])
		backs.append([_p(x - t, r * 0.995, a - hw * 0.9), _p(x - t, r * 0.995, a + hw * 0.9)])
	for i in steps:
		_quad(st, front[i][0], front[i][1], front[i + 1][1], front[i + 1][0], Vector3(1, 0, 0))
		_quad(st, backs[i][1], backs[i][0], backs[i + 1][0], backs[i + 1][1], Vector3(-1, 0, 0))
		for s in 2:
			var out: Vector3 = (front[i][s] - front[i][1 - s]).normalized()
			_quad(st, front[i][s], front[i + 1][s], backs[i + 1][s], backs[i][s], out)


# ── the brakes ────────────────────────────────────────────────────────────

## A ventilated disc (two plates, the vanes' gap dark between them) and its bell to the hub.
static func disc(r: float, hat_r: float, x: float, seg := SEG_HI) -> ArrayMesh:
	var key := "d_%.4f_%.4f_%.4f_%d" % [r, hat_r, x, seg]
	if _cache.has(key):
		return _cache[key]
	var th := 0.032 if r > 0.17 else 0.026
	var iron := _st()
	var bell := _st()
	var inner_r := hat_r + 0.012
	var prof: Array = [Vector2(x + th * 0.5, inner_r), Vector2(x + th * 0.5, r), Vector2(x + th * 0.28, r), Vector2(x + th * 0.22, r - 0.004),
		Vector2(x - th * 0.22, r - 0.004), Vector2(x - th * 0.28, r), Vector2(x - th * 0.5, r), Vector2(x - th * 0.5, inner_r)]
	_revolve(iron, prof, seg, Vector2(x, (r + inner_r) * 0.5), true)
	var hp: Array = [Vector2(x - th * 0.5, hat_r), Vector2(x + th * 0.5 + 0.035, hat_r), Vector2(x + th * 0.5 + 0.04, hat_r - 0.01)]
	_revolve(bell, hp, seg, Vector2(x, 0.0), false)
	_annulus(bell, hat_r - 0.01, 0.03, x + th * 0.5 + 0.04, seg)
	var mesh := ArrayMesh.new()
	iron.commit(mesh)
	bell.commit(mesh)
	mesh.surface_set_material(0, _mat("disc", Color(0.36, 0.35, 0.34), 0.85, 0.42))
	mesh.surface_set_material(1, _mat("bell", Color(0.22, 0.22, 0.23), 0.6, 0.5))
	_cache[key] = mesh
	return mesh


## The disc's middle across the wheel (x from its middle): a little inboard of the middle, and
## further in when a deep lip or thick spokes bring the spokes' backs in, so the caliper (wx
## each side of the disc) clears them by 6 mm.
static func brake_x(width: float, style: Dictionary, pistons: int) -> float:
	var face := width * 0.5 - float(style.get("lip", 0.012)) - 0.004
	var back := face - float(style.get("thick", 0.028)) - 0.006
	return minf(-width * 0.12, back - caliper_wx(pistons))


## How far the caliper reaches each side of the disc (m).
static func caliper_wx(pistons: int) -> float:
	return 0.05 if pistons <= 2 else 0.062


## A caliper over the disc's trailing edge, a little above the axle (in the wheel's frame: the
## wheel turns, the caliper doesn't, so it hangs on the upright, not the spinner).
static func caliper(disc_r: float, x: float, pistons := 4) -> ArrayMesh:
	var key := "c_%.4f_%.4f_%d" % [disc_r, x, pistons]
	if _cache.has(key):
		return _cache[key]
	var st := _st()
	var span := 0.5 if pistons <= 2 else (0.68 if pistons <= 4 else 0.82)     # rad round the disc
	var r0 := disc_r - (0.05 if pistons <= 2 else 0.062)
	var r1 := disc_r + 0.022
	var wx := caliper_wx(pistons)                                             # each side of the disc
	var mid := 0.3                                                            # rad above the horizontal, trailing
	var steps := 6
	var rows: Array = []
	for i in steps + 1:
		var a := mid - span * 0.5 + span * float(i) / steps
		rows.append([_pc(x + wx, r0, a), _pc(x + wx, r1, a), _pc(x - wx, r1, a), _pc(x - wx, r0, a)])
	for i in steps:
		for s in 4:
			var a: Vector3 = rows[i][s]
			var b: Vector3 = rows[i][(s + 1) % 4]
			var c: Vector3 = rows[i + 1][(s + 1) % 4]
			var d: Vector3 = rows[i + 1][s]
			var out := ((a + b) * 0.5 - Vector3(x, 0.0, 0.0) - ((a + b) * 0.5 - Vector3(x, 0.0, 0.0)).project(Vector3.RIGHT)).normalized()
			if s == 0:
				out = Vector3.RIGHT
			elif s == 2:
				out = Vector3.LEFT
			elif s == 3:
				out = -out
			_quad(st, a, b, c, d, out)
	for e in [0, steps]:                                                      # the ends
		var r: Array = rows[e]
		var tang: Vector3 = (rows[mini(e + 1, steps)][0] - rows[maxi(e - 1, 0)][0]).normalized() * (-1.0 if e == 0 else 1.0)
		_quad(st, r[0], r[1], r[2], r[3], tang)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	mesh.surface_set_material(0, _mat("caliper", Color(0.75, 0.08, 0.06), 0.2, 0.32))
	_cache[key] = mesh
	return mesh


## The caliper's outer radius over a disc of radius disc_r: for the fit checks.
static func caliper_reach(disc_r: float) -> float:
	return disc_r + 0.022


## The barrel's narrowest radius (its drop centre) on a rim of radius rim_r: what a caliper must clear.
static func drop_r(rim_r: float) -> float:
	return rim_r - 0.024


# ── geometry helpers ─────────────────────────────────────────────────────

## A point at radius r, angle a round the axle (x), x across: a = 0 straight up, + towards -z (forward).
static func _p(x: float, r: float, a: float) -> Vector3:
	return Vector3(x, r * cos(a), -r * sin(a))


## The caliper's points: a = 0 is horizontal towards +z (behind the axle), + up.
static func _pc(x: float, r: float, a: float) -> Vector3:
	return Vector3(x, r * sin(a), r * cos(a))


static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## A surface of revolution round the axle from a profile [(x, r)]: smooth across the profile
## except at corners sharper than CREASE. Normals point away from `core` (x, r), or along the
## profile's left-hand side when core.x < -0.5 (open profiles that face a known way).
static func _revolve(st: SurfaceTool, prof: Array, seg: int, core: Vector2, closed: bool) -> void:
	var m := prof.size()
	var segs := m if closed else m - 1
	# each profile segment's outward normal in (x, r)
	var sn: Array = []
	for i in segs:
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[(i + 1) % m]
		var d := (b - a).normalized()
		var nn := Vector2(d.y, -d.x)
		var mid := (a + b) * 0.5
		if core.x > -0.5 and nn.dot(mid - core) < 0.0:
			nn = -nn
		sn.append(nn)
	for i in segs:
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[(i + 1) % m]
		var na: Vector2 = sn[i]
		var nb: Vector2 = sn[i]
		var ip := i - 1 if i > 0 else (segs - 1 if closed else -1)
		var inx := (i + 1) % segs if (closed or i + 1 < segs) else -1
		if ip >= 0 and (sn[ip] as Vector2).angle_to(sn[i]) < CREASE and (sn[ip] as Vector2).angle_to(sn[i]) > -CREASE:
			na = ((sn[ip] as Vector2) + sn[i]).normalized()
		if inx >= 0 and (sn[inx] as Vector2).angle_to(sn[i]) < CREASE and (sn[inx] as Vector2).angle_to(sn[i]) > -CREASE:
			nb = ((sn[inx] as Vector2) + sn[i]).normalized()
		for k in seg:
			var t0 := TAU * k / seg
			var t1 := TAU * (k + 1) / seg
			var p00 := _p(a.x, a.y, t0)
			var p01 := _p(a.x, a.y, t1)
			var p10 := _p(b.x, b.y, t0)
			var p11 := _p(b.x, b.y, t1)
			var n00 := _rn(na, t0)
			var n01 := _rn(na, t1)
			var n10 := _rn(nb, t0)
			var n11 := _rn(nb, t1)
			_tri(st, p00, p10, p11, n00, n10, n11)
			_tri(st, p00, p11, p01, n00, n11, n01)


static func _rn(n: Vector2, a: float) -> Vector3:
	return Vector3(n.x, n.y * cos(a), -n.y * sin(a)).normalized()


## A flat ring facing +x at x, from r_out to r_in (r_in 0: a disc).
static func _annulus(st: SurfaceTool, r_out: float, r_in: float, x: float, seg: int) -> void:
	for k in seg:
		var t0 := TAU * k / seg
		var t1 := TAU * (k + 1) / seg
		var a := _p(x, r_out, t0)
		var b := _p(x, r_out, t1)
		var c := _p(x, r_in, t1)
		var d := _p(x, r_in, t0)
		_tri(st, a, b, c, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT)
		if r_in > 0.0:
			_tri(st, a, c, d, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT)


## An n-sided prism along x (a nut, a cap): its middle at `at`, radius r, length l (its front at
## at.x + l / 2), turned by a round the axle.
static func _prism(st: SurfaceTool, at: Vector3, r: float, l: float, n: int, a: float) -> void:
	var f: Array = []
	var b: Array = []
	for i in n:
		var t := a + TAU * i / n
		var off := Vector3(0.0, r * cos(t), -r * sin(t))
		f.append(at + off + Vector3(l * 0.5, 0, 0))
		b.append(at + off * 1.02 - Vector3(l * 0.5, 0, 0))
	var front := at + Vector3(l * 0.5, 0, 0)
	for i in n:
		var j := (i + 1) % n
		_tri(st, front, f[i], f[j], Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT)
		var out: Vector3 = (((f[i] + f[j]) * 0.5) - front).normalized()
		_quad(st, f[i], f[j], b[j], b[i], out)


## A quad a b c d, facing `n` (flat).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	var fn := n.normalized()
	_tri(st, a, b, c, fn, fn, fn)
	_tri(st, a, c, d, fn, fn, fn)


## One triangle, wound so it faces the way its normals do (Godot's front faces are clockwise).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	var fn := (c - a).cross(b - a)
	if fn.length_squared() < 1e-14:
		return
	if fn.dot(na + nb + nc) < 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)


static var _mats := {}


static func _mat(name: String, col: Color, metal: float, rough: float) -> StandardMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	m.resource_name = name
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	_mats[name] = m
	return m
