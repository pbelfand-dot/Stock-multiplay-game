extends RefCounted
## The highway between downtown and Magnolia Heights, described as DATA that
## the builder (meshes + collision), the traffic sim and a future driving mode
## all share. Nothing here makes nodes.
##
## MAINLINE: a smooth centerline (world x/z, y = 0) sampled every STEP metres.
## Positions on it are (s, d): s = station (metres along the centerline, 0 at
## the inside end of the west tunnel), d = lateral offset, + = right of the
## eastbound direction (south). Eastbound (dir +1) drives +s on the d > 0 side,
## westbound (dir -1) drives -s on the d < 0 side (right-hand traffic).
## Lanes are numbered from the median out: k = 0 fast lane, 1, 2 slow (right)
## lane, 3 = the auxiliary lane that exists only between an on-ramp and the
## next off-ramp (see `aux`). lane_d(dir, k) gives the lane's center offset.
##
## RAMPS / LOCAL ROADS: `paths` maps a name to a RoadPath (a 3D polyline with
## per-sample speed limits from curvature, resampled every PATH_STEP). They
## chain with `next`: "aux" means "join the mainline aux lane of this
## direction". Two interchanges, each: an at-grade exit on the north side, a
## flyover on-ramp that crosses OVER the highway, and a local road with a
## roundabout that turns exiting cars back onto the on-ramp:
##   downtown:  WB aux --dt_off--> dt_loop (connector + roundabout) --dt_on--> EB aux
##   hood:      EB aux --hood_off--> hood_loop (hood road + roundabout) --hood_on--> WB aux
## So the commute home -> office is: hood_on, westbound, dt_off, the connector
## (see route("home_to_office")). A third, simpler exit (dealer_off, a taper
## off the eastbound shoulder at station ~760) leads to an empty lot for a
## future car dealership (dealership_lot), linked to Levee Rd by dealer_road.
## Traffic never takes it.

const STEP := 3.0             # centerline sample spacing; lane dashes are 1 sample on, 3 off
const PATH_STEP := 2.0
const LANE_W := 3.7
const LANES := 3
const MEDIAN := 0.4           # half-width of the median barrier
const IN_SH := 1.2            # inner (median-side) shoulder
const OUT_SH := 3.0           # outer shoulder
const AUX_SH := 2.5           # outer shoulder beside the aux lane
const EDGE_IN := MEDIAN + IN_SH                 # 1.6: first lane line from the centerline
const EDGE_OUT := EDGE_IN + LANE_W * LANES      # 12.7: outer edge of lane 2
const TUNNEL := 60.0          # tunnel length at each end (cars spawn/recycle inside)

## Mainline control points (world x, z), west -> east. Catmull-Rom through these.
const CTRL := [Vector2(80, 385), Vector2(140, 385), Vector2(300, 383), Vector2(450, 376), Vector2(600, 367),
		Vector2(720, 364), Vector2(900, 366), Vector2(1040, 372), Vector2(1150, 380)]
## Flyover crossing stations of the two interchanges (see _interchange).
const SB_DOWNTOWN := 132.0
const SB_HOOD := 640.0
## Typical free-flow speed per lane (fast lane, middle, right lane), m/s. Each
## car's own desired speed is one of these +-10%; a lane also caps how fast
## you'll go in it (right lane slower), see Traffic._v0_of.
const LANE_SPEED := [35.0, 31.5, 28.0]
## Speed limits (m/s).
const V_RAMP := 20.0
const V_LOCAL := 11.0
const A_LAT := 3.2            # comfortable lateral acceleration on curves (m/s^2)

var cl := PackedVector3Array()      # centerline samples (every STEP)
var cl_t := PackedVector3Array()    # unit tangents
var length := 0.0
var s_portal_w := TUNNEL
var s_portal_e := 0.0
var paths := {}                     # name -> RoadPath
var aux := {}                       # dir -> {a, b, on, off}: aux lane k=3 exists for s in [a, b]
var junction_dt := Vector3.ZERO     # where the downtown ramps meet the connector
var junction_hood := Vector3.ZERO
var roundabout_dt := Vector3(82, 0, 241)
var roundabout_hood := Vector3.ZERO
var dealership_lot := Vector3.ZERO    # center of the empty dealership lot (y = its surface)
var dealership_rect := Rect2()        # its bounds on world x/z (60 x 40 m)
const DEALER_S := 760.0               # where the dealership exit leaves the eastbound shoulder
const RB_R := 13.5                  # roundabout outer radius (asphalt ring 6..13.5)
const RB_LANE_R := 9.8


class RoadPath:
	extends RefCounted
	var name := ""
	var pts := PackedVector3Array()
	var tan := PackedVector3Array()
	var cum := PackedFloat32Array()
	var lim := PackedFloat32Array()
	var length := 0.0
	var next := ""                  # next path name, or "aux"
	var aux_dir := 0                # for next == "aux": which carriageway it merges into
	var v_max := 20.0

	func idx(s: float) -> int:
		# samples are (nearly) evenly spaced: guess, then fix up
		var n := cum.size()
		if n < 2:
			return 0
		var i := clampi(int(s / maxf(length, 0.001) * (n - 1)), 0, n - 2)
		while i > 0 and cum[i] > s:
			i -= 1
		while i < n - 2 and cum[i + 1] < s:
			i += 1
		return i

	func at(s: float) -> Vector3:
		var i := idx(s)
		var f := clampf((s - cum[i]) / maxf(cum[i + 1] - cum[i], 0.0001), 0.0, 1.0)
		return pts[i].lerp(pts[i + 1], f)

	func tangent(s: float) -> Vector3:
		var i := idx(s)
		var f := clampf((s - cum[i]) / maxf(cum[i + 1] - cum[i], 0.0001), 0.0, 1.0)
		return tan[i].lerp(tan[i + 1], f).normalized()

	## Lowest curve speed limit over [s, s + ahead].
	func limit_ahead(s: float, ahead: float) -> float:
		var i := idx(s)
		var j := idx(minf(s + ahead, length))
		var v := v_max
		for k in range(i, j + 2):
			if k < lim.size():
				v = minf(v, lim[k])
		return v


func _init() -> void:
	_centerline()
	s_portal_e = length - TUNNEL
	_interchange("dt", SB_DOWNTOWN, 1.0)
	_interchange("hood", SB_HOOD, -1.0)
	aux[1] = {"a": SB_DOWNTOWN + 165.0, "b": SB_HOOD - 150.0, "on": "dt_on", "off": "hood_off"}
	aux[-1] = {"a": SB_DOWNTOWN + 150.0, "b": SB_HOOD - 165.0, "on": "hood_on", "off": "dt_off"}
	_local_roads()


# ------------------------------------------------------------------ mainline

static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Dense Catmull-Rom through `pts` (ends extended), resampled every `step` metres.
static func smooth(pts: Array, step: float) -> PackedVector3Array:
	var dense: Array = []
	var n := pts.size()
	for i in n - 1:
		var p0: Vector3 = pts[maxi(i - 1, 0)] if i > 0 else pts[0] * 2.0 - pts[1]
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p3: Vector3 = pts[i + 2] if i + 2 < n else pts[n - 1] * 2.0 - pts[n - 2]
		var segs := maxi(int(p1.distance_to(p2) / 0.5), 2)
		for k in segs:
			dense.append(_catmull(p0, p1, p2, p3, float(k) / segs))
	dense.append(pts[n - 1])
	var out := PackedVector3Array([dense[0]])
	var acc := 0.0
	var want := step
	for i in range(1, dense.size()):
		var a: Vector3 = dense[i - 1]
		var b: Vector3 = dense[i]
		var seg := a.distance_to(b)
		while acc + seg >= want and seg > 0.0:
			out.append(a.lerp(b, (want - acc) / seg))
			want += step
		acc += seg
	if out[out.size() - 1].distance_to(dense[dense.size() - 1]) > step * 0.25:
		out.append(dense[dense.size() - 1])
	return out


func _centerline() -> void:
	var pts: Array = []
	for c in CTRL:
		pts.append(Vector3(c.x, 0, c.y))
	cl = smooth(pts, STEP)
	length = (cl.size() - 1) * STEP
	cl_t.resize(cl.size())
	for i in cl.size():
		var a: Vector3 = cl[maxi(i - 1, 0)]
		var b: Vector3 = cl[mini(i + 1, cl.size() - 1)]
		cl_t[i] = (b - a).normalized()


func pos(s: float) -> Vector3:
	var f := clampf(s, 0.0, length) / STEP
	var i := mini(int(f), cl.size() - 2)
	return cl[i].lerp(cl[i + 1], f - i)


func tangent(s: float) -> Vector3:
	var f := clampf(s, 0.0, length) / STEP
	var i := mini(int(f), cl.size() - 2)
	return cl_t[i].lerp(cl_t[i + 1], f - i).normalized()


## Unit vector to the right of eastbound travel (+d).
func right(s: float) -> Vector3:
	return tangent(s).cross(Vector3.UP).normalized()


func point(s: float, d: float, y := 0.0) -> Vector3:
	return pos(s) + right(s) * d + Vector3(0, y, 0)


## Center offset of lane k (0 = fast lane by the median ... 2 = right lane, 3 = aux).
static func lane_d(dir: int, k: int) -> float:
	return dir * (EDGE_IN + LANE_W * (k + 0.5))


func has_aux(dir: int, s: float) -> bool:
	return aux.has(dir) and s >= aux[dir].a and s <= aux[dir].b


## Where on the mainline is this world point? Returns Vector2(s, d) (nearest sample).
func locate(p: Vector3) -> Vector2:
	var best := 0
	var bd := INF
	var i := 0
	while i < cl.size():
		var dd := Vector2(cl[i].x - p.x, cl[i].z - p.z).length_squared()
		if dd < bd:
			bd = dd
			best = i
		i += 4
	for k in range(maxi(best - 4, 0), mini(best + 5, cl.size())):
		var dd := Vector2(cl[k].x - p.x, cl[k].z - p.z).length_squared()
		if dd < bd:
			bd = dd
			best = k
	var s := best * STEP
	var rel := p - cl[best]
	s += rel.dot(cl_t[best])
	return Vector2(clampf(s, 0.0, length), rel.dot(right(s)))


# ------------------------------------------------------------------ ramps

## One interchange. Written for downtown (m = +1: junction north of the
## highway, the flyover lands on the south side and merges eastbound); the
## hood's is the same layout turned 180 degrees (m = -1). Template points are
## (u, v, y): station offset from the flyover, lateral offset, deck height.
func _interchange(tag: String, sb: float, m: float) -> void:
	var tp := func(u: float, v: float, y: float) -> Vector3:
		return point(sb + m * u, m * v, y)
	# the flyover on-ramp: from the junction, up over both carriageways, a long
	# descending left turn, then parallel into the aux lane
	var on_pts: Array = []
	for q in [Vector3(-0.8, -112, 0), Vector3(-0.8, -98, 0.6), Vector3(-0.5, -80, 2.3), Vector3(0, -58, 4.4),
			Vector3(0, -36, 6.3), Vector3(0, -20, 7.2), Vector3(0, 0, 7.4), Vector3(0, 20, 7.2), Vector3(3, 33, 6.6),
			Vector3(14, 46, 5.6), Vector3(34, 54, 4.4), Vector3(62, 52, 3.0), Vector3(92, 42, 1.6), Vector3(118, 28, 0.5),
			Vector3(140, 18.5, 0.05), Vector3(155, 15.2, 0.0), Vector3(165, 14.55, 0.0)]:
		on_pts.append(tp.call(q.x, q.y, q.z))
	var on := _make_path(tag + "_on", on_pts, V_RAMP)
	on.next = "aux"
	on.aux_dir = int(m)           # downtown's merges eastbound, the hood's westbound
	# the at-grade off-ramp: diverge from the aux lane, sweep out to the junction
	var off_pts: Array = []
	for q in [Vector3(150, -14.55, 0), Vector3(138, -15.4, 0), Vector3(120, -19, 0), Vector3(98, -28, 0),
			Vector3(74, -44, 0), Vector3(50, -64, 0), Vector3(30, -84, 0), Vector3(15, -100, 0), Vector3(2.8, -112, 0)]:
		off_pts.append(tp.call(q.x, q.y, q.z))
	var off := _make_path(tag + "_off", off_pts, V_RAMP)
	off.next = tag + "_loop"
	var j: Vector3 = tp.call(1.0, -112.0, 0.0)
	if tag == "dt":
		junction_dt = j
	else:
		junction_hood = j


## The two local roads with their roundabouts, and the U-turn loops cars take
## on them (right lane out, around the circle counter-clockwise, back).
func _local_roads() -> void:
	# downtown connector: junction -> roundabout by the east end of the street
	var n_dt: Vector3 = (point(SB_DOWNTOWN + 1.0, -125.0) - junction_dt).normalized()
	var road_dt: Array = [junction_dt, junction_dt + n_dt * 10.0, Vector3(200, 0, 253), Vector3(166, 0, 248),
		Vector3(128, 0, 244), roundabout_dt + Vector3(RB_R + 4.0, 0, 0)]
	paths["dt_road"] = _make_path("dt_road", road_dt, V_LOCAL)            # centerline (for meshes)
	# the hood road: junction -> roundabout at the Magnolia Heights entrance
	roundabout_hood = point(SB_HOOD - 2.0, 150.0)
	roundabout_hood.y = 0.0
	var n_h: Vector3 = (roundabout_hood - junction_hood).normalized()
	var road_h: Array = [junction_hood, junction_hood + n_h * 8.0, roundabout_hood - n_h * (RB_R + 3.0)]
	paths["hood_road"] = _make_path("hood_road", road_h, V_LOCAL)
	_loop("dt", paths["dt_road"], roundabout_dt)
	_loop("hood", paths["hood_road"], roundabout_hood)
	_dealership()


## An at-grade taper exit off the eastbound shoulder to a flat 60 x 40 m lot,
## and a short road from the lot down to the north end of Levee Rd.
func _dealership() -> void:
	var off_pts: Array = []
	for q in [Vector2(0, 14.55), Vector2(22, 15.8), Vector2(40, 19.5), Vector2(55, 26.0), Vector2(65, 34.0),
			Vector2(69, 44.0), Vector2(70, 55.0)]:
		off_pts.append(point(DEALER_S + q.x, q.y))
	var off := _make_path("dealer_off", off_pts, V_RAMP)
	off.next = ""
	dealership_lot = point(DEALER_S + 70.0, 75.0)
	dealership_lot.y = 0.0
	dealership_rect = Rect2(dealership_lot.x - 30.0, dealership_lot.z - 20.0, 60.0, 40.0)
	var xe := roundabout_hood.x + 140.0            # Levee Rd (see NeighborhoodBuilder._neighborhood)
	var zn := roundabout_hood.z - 4.0              # its north end at Magnolia St
	var corner := Vector3(dealership_rect.position.x + 6.0, 0, dealership_rect.end.y)
	var road := _make_path("dealer_road", [corner, corner + Vector3(-6, 0, 10), Vector3(xe + 6.0, 0, zn - 22.0),
			Vector3(xe, 0, zn - 10.0), Vector3(xe, 0, zn)], V_LOCAL)
	road.next = ""


# ------------------------------------------------------------------ helpers for a driving mode

## World position of lane k's center at station s (dir +1 eastbound, -1 westbound).
func lane_center(dir: int, k: int, s: float) -> Vector3:
	return point(s, lane_d(dir, k))


## Unit direction of travel for `dir` at station s.
func forward(dir: int, s: float) -> Vector3:
	return tangent(s) * float(dir)


## Typical speed of a lane (m/s); ramps/local roads: RoadPath.v_max / limit_ahead.
static func speed_limit(k: int) -> float:
	return LANE_SPEED[clampi(k, 0, LANES - 1)]


func _path_points(p, s0: float, s1: float, out: Array, step := 5.0) -> void:
	var s := s0
	while s < s1:
		out.append(p.at(s))
		s += step
	out.append(p.at(s1))


func _main_points(dir: int, k: int, s0: float, s1: float, out: Array, step := 5.0) -> void:
	var n := maxi(int(absf(s1 - s0) / step), 1)
	for i in n + 1:
		out.append(lane_center(dir, k, lerpf(s0, s1, float(i) / n)))


func _line(a: Vector3, b: Vector3, out: Array, step := 5.0) -> void:
	var n := maxi(int(a.distance_to(b) / step), 1)
	for i in range(1, n + 1):
		out.append(a.lerp(b, float(i) / n))


func _circle(c: Vector3, a0: float, a1: float, out: Array) -> void:
	var n := maxi(int(absf(a1 - a0) * RB_LANE_R / 4.0), 2)
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		out.append(c + Vector3(cos(a) * RB_LANE_R, 0, -sin(a) * RB_LANE_R))


## Where a loop path goes round its circle: (s entering, s leaving).
func loop_circle(tag: String) -> Vector2:
	var p: RoadPath = paths[tag + "_loop"]
	var c := roundabout_dt if tag == "dt" else roundabout_hood
	var s_in := -1.0
	var s_out := 0.0
	var s := 0.0
	while s <= p.length:
		var q := p.at(s)
		if Vector2(q.x - c.x, q.z - c.z).length() < RB_LANE_R + 1.0:
			if s_in < 0.0:
				s_in = s
			s_out = s
		s += 1.0
	return Vector2(s_in, s_out)


## A drivable route as data: {"segments": [...], "points": PackedVector3Array}
## (points every ~5 m along lane centers). "home_to_office": the Magnolia
## Heights roundabout -> hood road -> flyover on-ramp -> westbound (aux lane) ->
## downtown exit -> connector -> downtown roundabout -> the street to the
## BAGHOLDER CAPITAL lobby. "office_to_home" is the trip back.
func route(which: String) -> Dictionary:
	var pts: Array = []
	var seg: Array = []
	var hl: RoadPath = paths["hood_loop"]
	var dl: RoadPath = paths["dt_loop"]
	var hc := loop_circle("hood")
	var dc := loop_circle("dt")
	var lobby := Vector3(-6.0, 0.0, 238.2)
	if which == "home_to_office":
		seg = [{"path": "hood_loop", "from": hc.y, "to": hl.length}, {"path": "hood_on"},
			{"mainline": -1, "lane": 3, "from": aux[-1].b, "to": aux[-1].a}, {"path": "dt_off"},
			{"path": "dt_loop", "from": 0.0, "to": dc.x}, {"roundabout": "dt", "exit": "west"},
			{"street": "downtown", "to": lobby}]
		_path_points(hl, hc.y, hl.length, pts)
		_path_points(paths["hood_on"], 0.0, paths["hood_on"].length, pts)
		_main_points(-1, 3, aux[-1].b, aux[-1].a, pts)
		_path_points(paths["dt_off"], 0.0, paths["dt_off"].length, pts)
		_path_points(dl, 0.0, dc.x, pts)
		var e: Vector3 = dl.at(dc.x) - roundabout_dt
		_circle(roundabout_dt, atan2(-e.z, e.x), PI - 0.2, pts)
		_line(pts[pts.size() - 1], Vector3(roundabout_dt.x - RB_R - 2.0, 0.0, 238.2), pts)
		_line(pts[pts.size() - 1], lobby, pts)
	elif which == "office_to_home":
		seg = [{"street": "downtown", "from": lobby}, {"roundabout": "dt", "exit": "east"},
			{"path": "dt_loop", "from": dc.y, "to": dl.length}, {"path": "dt_on"},
			{"mainline": 1, "lane": 3, "from": aux[1].a, "to": aux[1].b}, {"path": "hood_off"},
			{"path": "hood_loop", "from": 0.0, "to": hc.x}, {"roundabout": "hood", "exit": "east (Magnolia St)"}]
		pts.append(Vector3(lobby.x, 0.0, 241.8))
		_line(pts[0], Vector3(roundabout_dt.x - RB_R - 2.0, 0.0, 241.8), pts)
		var e2: Vector3 = dl.at(dc.y) - roundabout_dt
		_circle(roundabout_dt, PI + 0.2, TAU + atan2(-e2.z, e2.x), pts)
		_path_points(dl, dc.y, dl.length, pts)
		_path_points(paths["dt_on"], 0.0, paths["dt_on"].length, pts)
		_main_points(1, 3, aux[1].a, aux[1].b, pts)
		_path_points(paths["hood_off"], 0.0, paths["hood_off"].length, pts)
		_path_points(hl, 0.0, hc.x, pts)
		var e3: Vector3 = hl.at(hc.x) - roundabout_hood
		_circle(roundabout_hood, atan2(-e3.z, e3.x), atan2(-e3.z, e3.x) + PI * 0.5, pts)
		_line(pts[pts.size() - 1], roundabout_hood + Vector3(RB_R + 20.0, 0, 1.8), pts)
	return {"segments": seg, "points": PackedVector3Array(pts)}


## out along the road's right lane, counter-clockwise around the circle, back.
func _loop(tag: String, road: RoadPath, c: Vector3) -> void:
	var lane := 1.8
	var out_pts: Array = []
	var back_pts: Array = []
	var s := 0.0
	while s <= road.length - 0.5:
		var p := road.at(s)
		var t := road.tangent(s)
		var r := t.cross(Vector3.UP).normalized()
		out_pts.append(p + r * lane)
		back_pts.push_front(p - r * lane)
		s += 6.0
	# the circle: enter where the road arrives, go round (counter-clockwise seen
	# from above, north up = -z), leave back down the road
	var arrive: Vector3 = road.at(road.length) - c
	var a_in := atan2(-arrive.z, arrive.x)          # math angle, north = +90 deg
	var pts: Array = out_pts
	var n := 28
	for k in range(1, n):
		var a := a_in + 0.35 + (TAU - 0.7) * float(k) / n
		pts.append(c + Vector3(cos(a) * RB_LANE_R, 0, -sin(a) * RB_LANE_R))
	pts.append_array(back_pts)
	var lp := _make_path(tag + "_loop", pts, V_LOCAL)
	lp.next = tag + "_on"


func _make_path(pname: String, pts: Array, vmax: float) -> RoadPath:
	var p := RoadPath.new()
	p.name = pname
	p.v_max = vmax
	p.pts = smooth(pts, PATH_STEP)
	var n := p.pts.size()
	p.cum.resize(n)
	p.tan.resize(n)
	p.lim.resize(n)
	var acc := 0.0
	for i in n:
		if i > 0:
			acc += p.pts[i - 1].distance_to(p.pts[i])
		p.cum[i] = acc
		var a: Vector3 = p.pts[maxi(i - 1, 0)]
		var b: Vector3 = p.pts[mini(i + 1, n - 1)]
		p.tan[i] = (b - a).normalized()
	p.length = acc
	for i in n:   # curvature -> speed: v = sqrt(a_lat * R), over +-3 samples
		var i0 := maxi(i - 3, 0)
		var i1 := mini(i + 3, n - 1)
		var t0: Vector3 = p.tan[i0]
		var t1: Vector3 = p.tan[i1]
		var ang := Vector2(t0.x, t0.z).angle_to(Vector2(t1.x, t1.z))
		var arc := maxf(p.cum[i1] - p.cum[i0], 0.1)
		var k := absf(ang) / arc
		p.lim[i] = clampf(sqrt(A_LAT / maxf(k, 0.0001)), 6.0, vmax)
	paths[pname] = p
	return p


## Everything a driving mode needs to know, as plain data (for docs/tests).
func describe() -> Dictionary:
	var lanes := []
	for dir in [1, -1]:
		for k in LANES:
			lanes.append({"dir": dir, "lane": k, "d": lane_d(dir, k)})
	var ps := {}
	for n in paths:
		ps[n] = {"length": paths[n].length, "next": paths[n].next}
	return {"length": length, "step": STEP, "lanes": lanes, "aux": aux, "paths": ps,
		"portals": [s_portal_w, s_portal_e], "lane_speed": LANE_SPEED, "dealership_lot": dealership_lot}
