extends RefCounted
## Where a cab drives: the lane-by-lane path between the places you can call
## one to / from, found on a little road graph:
##   downtown  the BAGHOLDER CAPITAL end of the block (the taxi stand / the lobby)
##   hood      Magnolia St by the Magnolia Heights taxi stand
##   home      the street in front of your house (`home` = World.home_of())
##   dealer    the BEMZE lot
##   mercedez, porsha, audy   the dealerships round the loop (Highway.dealers)
## Nodes are the intersections (Magnolia / Levee, Levee / Pecan, Pecan / Delta),
## the Magnolia Heights roundabout, downtown and the lots; edges are the streets
## (centerlines, driven 2 m right of them: right-hand traffic), the BEMZE road,
## and the highway both ways (Highway.route(): already lane by lane). The loop
## lots are eastbound only: downtown -> any of them, each on to the ones after
## it, and on round through the tunnel to Magnolia Heights. Going through the
## roundabout is an arc round it, counter-clockwise seen from above.
## The cab starts facing the way it's going, so it never has to turn round.

const Highway = preload("res://scripts/world/highway.gd")

const LANE := 2.0
const CORNER_R := 7.0
const STEP := 3.0
const DT_STAND_X := 40.0         # downtown pickup: just past the cab parked at the stand
const HOOD_STAND_X := 22.0       # the Magnolia Heights stand, from the roundabout's center


## The cab's path from `from` to `to` ([] = no road between them / same place).
static func plan(hw, from: String, to: String, home: Dictionary) -> PackedVector3Array:
	if from == to or ((from == "home" or to == "home") and home.is_empty()):
		return PackedVector3Array()
	var g := _graph(hw, home)
	var route := _dijkstra(g, "stand" if from == "hood" else from, "stand" if to == "hood" else to)
	if route.size() < 2:
		return PackedVector3Array()
	# stitch the edges together; a street is its lane, the roundabout an arc
	var r2: Vector3 = hw.roundabout_hood
	var out: Array = []
	var pending_ring := false
	for i in route.size() - 1:
		var e: Dictionary = g.edges[_ek(route[i], route[i + 1])]
		var pts: Array = _lane(e.cl) if e.kind == "street" else Array(e.pts)
		if pending_ring and not out.is_empty():
			out.append_array(_roundabout(r2, out[out.size() - 1], pts[0]))
		out.append_array(pts)
		pending_ring = route[i + 1] == "ring"
	return _finish(out)


static func _ek(a: String, b: String) -> String:
	return a + ">" + b


## {edges: {"a>b": {kind, cl | pts, len}}, adj: {node: [next nodes]}}
static func _graph(hw, home: Dictionary) -> Dictionary:
	var r2: Vector3 = hw.roundabout_hood
	var zm := r2.z
	var zp := r2.z + 70.0
	var xe := r2.x + 140.0
	var rb := Highway.RB_R + 1.0
	var g := {"edges": {}, "adj": {}}
	var street := func(a: String, b: String, cl: Array) -> void:
		var rev := cl.duplicate()
		rev.reverse()
		_add(g, a, b, {"kind": "street", "cl": cl})
		_add(g, b, a, {"kind": "street", "cl": rev})
	# Magnolia St, split at the stand (and at home if it's on Magnolia)
	var mag: Array = [["ring", r2.x + rb], ["stand", r2.x + HOOD_STAND_X], ["ml", xe]]
	var pec: Array = [["pd", r2.x], ["pl", xe]]
	if not home.is_empty():
		var on_pecan: bool = absf(home.drive.z - zp) < absf(home.drive.z - zm)
		var row: Array = pec if on_pecan else mag
		row.append(["home", clampf(home.drive.x, row[0][1] + 8.0, xe - 8.0)])
		row.sort_custom(func(p, q): return p[1] < q[1])
	for row_z in [[mag, zm], [pec, zp]]:
		var row: Array = row_z[0]
		for i in row.size() - 1:
			street.call(row[i][0], row[i + 1][0], [Vector3(row[i][1], 0, row_z[1]), Vector3(row[i + 1][1], 0, row_z[1])])
	street.call("ml", "pl", [Vector3(xe, 0, zm), Vector3(xe, 0, zp)])                 # Levee Rd
	street.call("pd", "ring", [Vector3(r2.x, 0, zp), Vector3(r2.x, 0, zm + rb)])      # Delta Ave
	var dr: Array = Array(hw.paths["dealer_road"].pts)                                # lot corner -> the east end of Magnolia St
	var lot := [Vector3(dr[0].x + 2.0, 0, dr[0].z - 16.0)]
	var to_lot: Array = [Vector3(xe, 0, zm)]
	var rev := dr.duplicate()
	rev.reverse()
	to_lot.append_array(rev)
	to_lot.append_array(lot)
	street.call("ml", "dealer", to_lot)
	# the highway: into the roundabout from the hood road / out of it up the hood road
	var o2h: PackedVector3Array = hw.route("office_to_home").points
	var h2o: PackedVector3Array = hw.route("home_to_office").points
	var cut := 0
	while cut < o2h.size() - 1 and Vector2(o2h[cut].x - r2.x, o2h[cut].z - r2.z).length() > Highway.RB_R + 2.0:
		cut += 1
	var i0 := 0
	while i0 < cut - 1 and o2h[i0].x < DT_STAND_X:
		i0 += 1
	_add(g, "downtown", "ring", {"kind": "lane", "pts": o2h.slice(i0, cut)})
	_add(g, "ring", "downtown", {"kind": "lane", "pts": h2o})
	# the loop dealerships: out of downtown eastbound, one to the next, on round to the hood
	var loop: Array = hw.loop_dealers()
	for i in loop.size():
		var br: String = loop[i].brand
		var dt: PackedVector3Array = hw.route("office_to_" + br).points
		var j0 := 0
		while j0 < dt.size() - 1 and dt[j0].x < DT_STAND_X:
			j0 += 1
		_add(g, "downtown", br, {"kind": "lane", "pts": dt.slice(j0)})
		var back: PackedVector3Array = hw.route(br + "_to_home").points
		var k := 0
		while k < back.size() - 1 and Vector2(back[k].x - r2.x, back[k].z - r2.z).length() > Highway.RB_R + 2.0:
			k += 1
		_add(g, br, "ring", {"kind": "lane", "pts": back.slice(0, k)})
		for j in range(i + 1, loop.size()):
			_add(g, br, loop[j].brand, {"kind": "lane", "pts": hw.route("%s_to_%s" % [br, loop[j].brand]).points})
	return g


static func _add(g: Dictionary, a: String, b: String, e: Dictionary) -> void:
	var pts: Array = e.cl if e.kind == "street" else Array(e.pts)
	var L := 0.0
	for i in pts.size() - 1:
		L += (pts[i] as Vector3).distance_to(pts[i + 1])
	e["len"] = L
	g.edges[_ek(a, b)] = e
	var adj: Array = g.adj.get(a, [])
	adj.append(b)
	g.adj[a] = adj


static func _dijkstra(g: Dictionary, from: String, to: String) -> Array:
	var dist := {from: 0.0}
	var prev := {}
	var open := [from]
	while not open.is_empty():
		open.sort_custom(func(p, q): return dist[p] < dist[q])
		var n: String = open.pop_front()
		if n == to:
			break
		for m in g.adj.get(n, []):
			var d: float = dist[n] + g.edges[_ek(n, m)].len
			if d < dist.get(m, INF):
				dist[m] = d
				prev[m] = n
				if not open.has(m):
					open.append(m)
	if not dist.has(to):
		return []
	var route := [to]
	while route[0] != from:
		route.push_front(prev[route[0]])
	return route


## Centerline waypoints -> the right-hand lane, corners rounded.
static func _lane(cl: Array) -> Array:
	if cl.size() < 2:
		return cl.duplicate()
	var off: Array = []
	for i in cl.size():
		var p: Vector3 = cl[i]
		var t_in: Vector3 = _flat(p - (cl[i - 1] as Vector3)).normalized() if i > 0 else _flat((cl[1] as Vector3) - p).normalized()
		var t_out: Vector3 = _flat((cl[i + 1] as Vector3) - p).normalized() if i < cl.size() - 1 else t_in
		var r_in := t_in.cross(Vector3.UP)
		var r_out := t_out.cross(Vector3.UP)
		var n := r_in + r_out
		if n.length() < 0.01:
			n = r_in
		else:
			n = n.normalized() / maxf(n.normalized().dot(r_in), 0.4)       # keep the lane width round the corner
		off.append(p + n * LANE)
	return _round(off)


static func _round(pts: Array) -> Array:
	var out: Array = [pts[0]]
	for i in range(1, pts.size() - 1):
		var p: Vector3 = pts[i]
		var da: Vector3 = (pts[i - 1] as Vector3) - p
		var db: Vector3 = (pts[i + 1] as Vector3) - p
		if da.length() < 0.01 or db.length() < 0.01 or da.normalized().dot(db.normalized()) < -0.99:
			out.append(p)                 # (nearly) straight on
			continue
		var r := minf(CORNER_R, minf(da.length(), db.length()) * 0.45)
		var p0 := p + da.normalized() * r
		var p1 := p + db.normalized() * r
		for k in 7:
			var t := k / 6.0
			out.append(p0.lerp(p, t).lerp(p.lerp(p1, t), t))   # a quadratic Bezier round the corner
	out.append(pts[pts.size() - 1])
	return out


## Round the roundabout counter-clockwise (seen from above) from where we come
## in to where we leave, on its lane.
static func _roundabout(c: Vector3, from: Vector3, to: Vector3) -> Array:
	var a0 := atan2(-(from.z - c.z), from.x - c.x)
	var a1 := atan2(-(to.z - c.z), to.x - c.x)
	while a1 <= a0 + 0.35:
		a1 += TAU
	var out: Array = []
	var n := maxi(int((a1 - a0) * Highway.RB_LANE_R / STEP), 3)
	for i in range(0, n + 1):
		var a := lerpf(a0 + 0.2, a1 - 0.2, float(i) / n)
		out.append(c + Vector3(cos(a) * Highway.RB_LANE_R, 0, -sin(a) * Highway.RB_LANE_R))
	return out


## Even spacing (the AI's lookahead / curve reading likes it), flat on the road.
static func _finish(pts: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	if pts.is_empty():
		return out
	out.append(_flat(pts[0]))
	var carry := 0.0
	for i in range(1, pts.size()):
		var a: Vector3 = _flat(pts[i - 1])
		var b: Vector3 = _flat(pts[i])
		var seg := a.distance_to(b)
		if seg < 0.001:
			continue
		var d := STEP - carry
		while d <= seg:
			out.append(a.lerp(b, d / seg))
			d += STEP
		carry = seg - (d - STEP)
	if out[out.size() - 1].distance_to(_flat(pts[pts.size() - 1])) > 0.5:
		out.append(_flat(pts[pts.size() - 1]))
	return out


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
