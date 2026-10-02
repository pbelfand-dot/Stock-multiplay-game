extends Node
## Drives the Car it's attached to (its parent) with the same controls a
## player has. PURSUE: aim where the target is going to be, match its speed
## then close in, don't hit walls, back out when stuck. The cops' brain.
## On the highway (given `traffic`) it cuts up: it reads the traffic's lanes,
## goes for the one that gets it furthest (the target's once it's close),
## never faster than it can stop behind whoever's in it or make the bend
## ahead; far behind it gets the catch-up boost (Rules.PURSUIT_BOOST).
## CUTUP: the same lane work with no target, flat out down the highway (the
## tests' stand-in for a player cutting up).

const Rules = preload("res://scripts/sim/rules.gd")
const Highway = preload("res://scripts/world/highway.gd")

var car
var target: Node3D               # the car we're chasing
var mode := "pursue"             # "pursue" a target / "path": drive along `path` / "cutup": down the highway
var path := PackedVector3Array() # "path" mode: the road to follow (points ~5-10 m apart)
var cruise := 30.0               # "path" / "cutup" mode: speed on the straights (m/s)
var _pi := 0                     # nearest path point so far
var done := false                # "path" mode: reached the end
var _stuck := 0.0
var _reverse := 0.0
var _rev_steer := 0.0
var _ray_l: RayCast3D
var _ray_c: RayCast3D
var _ray_r: RayCast3D
var _ray_ll: RayCast3D           # wide feelers: which way round an obstacle is open
var _ray_rr: RayCast3D
var _detour := 0.0               # > 0: committed to going round something
var _detour_side := 1.0          # -1 left, +1 right
var traffic                      # pursue / cutup: the highway traffic (traffic.gd), if any: drive its lanes
var boost_max := 0.0             # pursue: catch-up boost when far behind (Rules.PURSUIT_BOOST)
var debug := false               # print the highway decisions
var _lane := -1                  # highway: the lane we're going for
var _lane_t := 0.0               # ... seconds since we picked it
var hw_brake := 8.0              # highway: how hard we'd brake for a car in our lane (m/s^2)
var hw_margin := 6.0             # ... and how close behind it we'd end up (m)
var hw_swerve := 0.8             # ... a car we're swerving round must be this many s away (at the closing speed)
const HW_LOOK := 3.0             # ... lanes are picked by how far up the road they get us in this many s


func _ready() -> void:
	car = get_parent()
	car.ai = true
	_ray_c = _ray(Vector3(0, 0, -1))
	_ray_l = _ray(Vector3(-0.45, 0, -1).normalized())
	_ray_r = _ray(Vector3(0.45, 0, -1).normalized())
	_ray_ll = _ray(Vector3(-1.6, 0, -1).normalized())
	_ray_rr = _ray(Vector3(1.6, 0, -1).normalized())


func _ray(dir: Vector3) -> RayCast3D:
	var r := RayCast3D.new()
	r.position = Vector3(0, 0.7, -2.2)
	r.target_position = dir * 14.0
	r.add_exception(car)
	car.add_child.call_deferred(r)
	return r


func _physics_process(dt: float) -> void:
	if car == null or not car.simulate:
		return
	if mode == "path":
		_follow(dt)
		return
	if mode == "cutup":
		_cutup(dt)
		return
	if target == null or not is_instance_valid(target):
		return
	var sp: float = car.speed
	# stuck against something: back out, then have another go
	if _reverse > 0.0:
		_reverse -= dt
		car.in_throttle = 0.0
		car.in_brake = 1.0
		car.in_steer = _rev_steer
		car.in_handbrake = false
		return
	_stuck = _stuck + dt if absf(sp) < 1.0 and car.in_throttle > 0.5 else maxf(_stuck - dt, 0.0)
	if _stuck > 1.2:
		_stuck = 0.0
		_reverse = 1.1
		_rev_steer = -signf(car.in_steer) if absf(car.in_steer) > 0.1 else 1.0
		return
	# lead the target: where it'll be by the time we get there
	var tv: Vector3 = target.get("velocity") if target.get("velocity") != null else Vector3.ZERO
	var to: Vector3 = target.global_position - car.global_position
	var dist := to.length()
	var lead := clampf(dist / maxf(absf(sp), 12.0), 0.0, 1.4)
	var aim: Vector3 = target.global_position + Vector3(tv.x, 0, tv.z) * lead
	# far behind: the rubber band (more power, a higher top end), gone by the time we're on them
	car.boost = 1.0 + boost_max * clampf((dist - Rules.PURSUIT_BOOST_NEAR)
			/ (Rules.PURSUIT_BOOST_FAR - Rules.PURSUIT_BOOST_NEAR), 0.0, 1.0)
	_lane_t += dt
	var hwy := _highway(sp, aim, debug and Engine.get_physics_frames() % 15 == 0)
	if not hwy.is_empty():
		aim = hwy.aim
	# no straight line to them (a wall, a truck): aim past the edge of whatever's
	# in the way, on one side, until we can see them again (on the highway the lanes do that)
	var los := _line_of_sight() if hwy.is_empty() else {}
	if not los.is_empty():
		if _detour <= 0.0:
			_detour_side = -1.0 if _clear(_ray_l) + _clear(_ray_ll) > _clear(_ray_r) + _clear(_ray_rr) else 1.0
		_detour = 0.8
		var dir := to.normalized()
		var perp := dir.cross(Vector3.UP) * -_detour_side          # -side: left of the line, +: right
		aim = (los.position as Vector3) + perp * 9.0 - dir * 3.0
	var local: Vector3 = car.to_local(aim)
	var ang := atan2(-local.x, -local.z)            # + = the target is to our left
	var steer := clampf(-ang * 2.2, -1.0, 1.0)
	# something right in front of the bumper: turn away from it now
	var blocked := _ray_c.is_colliding() and _ray_c.get_collider() != target \
			and _ray_c.get_collision_point().distance_to(_ray_c.global_position) < minf(dist, 9.0)
	_detour = maxf(_detour - dt, 0.0)
	if blocked:
		var side := _detour_side if _detour > 0.0 else (-1.0 if _clear(_ray_l) > _clear(_ray_r) else 1.0)
		steer = side
	# speed: match theirs, plus a closing speed when behind, never overshoot
	var their := Vector3(tv.x, 0, tv.z).length()
	# (way back, and they're stuck behind someone: still come on as fast as the road allows)
	var want := their + clampf((dist - 9.0) * 0.55, -6.0, 22.0 + maxf(dist - 50.0, 0.0) * 0.5)
	if not hwy.is_empty():
		want = minf(want, hwy.cap)
	if absf(ang) > 1.2:
		want = minf(want, 14.0)                       # it's beside / behind us: turn, don't blast past
	if blocked:
		var hit := (_ray_c.get_collision_point() - _ray_c.global_position).length()
		want = minf(want, maxf(hit * 1.2, 6.0))
	if _detour > 0.0:
		want = minf(want, 11.0)
	car.in_steer = steer
	car.in_handbrake = false
	if sp < want - 0.5:
		car.in_throttle = 1.0
		car.in_brake = 0.0
	elif sp > want + 2.0:
		car.in_throttle = 0.0
		# (on the highway the cap already assumes hard braking: no easing into it)
		car.in_brake = clampf((sp - want) / (3.0 if not hwy.is_empty() else 8.0), 0.2, 1.0)
	else:
		car.in_throttle = 0.3
		car.in_brake = 0.0


## Where we are on the highway: [dir, station, lane] (lane 0-2), or [] when
## we're not on it or not pointing down it.
func _on_highway() -> Array:
	if traffic == null or not is_instance_valid(traffic) or not traffic.awake or traffic.remote:
		return []
	var hw = traffic.hw
	var me: Vector3 = car.global_position
	var loc: Vector2 = hw.locate(me)
	var ad := absf(loc.y)
	if ad < Highway.EDGE_IN - 1.0 or ad > Highway.EDGE_OUT + 1.5 or absf(me.y) > 2.5:
		return []
	var dir := 1 if loc.y > 0.0 else -1
	if hw.forward(dir, loc.x).dot(-car.global_basis.z) < 0.8:
		return []
	return [dir, loc.x, clampi(int((ad - Highway.EDGE_IN) / Highway.LANE_W), 0, Highway.LANES - 1)]


## Cutting up: which lane to go for, and how fast it's safe to go. Lanes are
## picked by how far up the road they'll get us in the next HW_LOOK s (+ the
## `prefer` lane, -1 = none); in our own lane we only go as fast as we could
## still stop behind the car ahead, unless we're already moving over into a
## lane with room (then only what it takes not to hit it before we're out of
## its way). One lane at a time, never into a lane someone's beside us in.
## {go: the lane to steer for, lim: m/s}
func _lanes(sp: float, dir: int, s: float, k: int, prefer: int, skip: Array, dbg := false) -> Dictionary:
	var half: float = car.ref.box.z / 2.0
	var scan: Array = []
	var side_ok: Array = []
	for j in Highway.LANES:
		var sc: Array = traffic.lane_scan(dir, j, s, skip)
		scan.append(sc)
		side_ok.append(sc[0] > half + 2.5 and sc[2] > half + 2.5)
	if _lane < 0 or _lane >= Highway.LANES:
		_lane = k
		_lane_t = 0.0
	var best := _lane
	var best_score := -INF
	for j in Highway.LANES:
		var score: float = minf(scan[j][0] + scan[j][1] * HW_LOOK, sp * HW_LOOK + 60.0) - absf(j - k) * 15.0
		if j == prefer:
			score += 60.0
		if j == _lane:
			score += 15.0
		if score > best_score:
			best_score = score
			best = j
	if best != _lane and _lane_t > 0.6:
		_lane = best
		_lane_t = 0.0
	var go := k
	if _lane != k and side_ok[k + signi(_lane - k)]:
		go = k + signi(_lane - k)
	var lim: float = _stop_cap(scan[k], hw_brake, hw_margin)
	if go != k:
		var out_of_way: float = scan[k][1] + maxf(scan[k][0] - 3.0, 0.0) / hw_swerve
		lim = minf(maxf(lim, out_of_way), _stop_cap(scan[go], hw_brake, hw_margin))
	lim = minf(lim, _curve_cap(dir, s, sp))
	if dbg:
		var txt := ""
		for j in Highway.LANES:
			txt += "  L%d g%.0f v%.0f b%.0f%s" % [j, minf(scan[j][0], 999.0), scan[j][1], minf(scan[j][2], 999.0), "" if side_ok[j] else "X"]
		print("%s s %.0f sp %.1f k %d lane %d go %d prefer %d lim %.0f boost %.2f |%s" % [car.name, s, sp, k, _lane, go, prefer, lim, car.boost, txt])
	return {"go": go, "lim": maxf(lim, 8.0)}


## On the highway with the target up the road: {aim: where to steer, cap: top
## speed for the cars ahead}, or {} (off the highway, the wrong way round, or
## they're beside / behind us: the plain chase does that).
func _highway(sp: float, target_aim: Vector3, dbg := false) -> Dictionary:
	var at := _on_highway()
	if at.is_empty():
		return {}
	var hw = traffic.hw
	var dir: int = at[0]
	var tl: Vector2 = hw.locate(target.global_position)
	var ahead: float = hw.ds(at[1], tl.x) * dir           # how far up the road they are
	if ahead < 14.0 or signf(tl.y) != dir or absf(target.global_position.y) > 2.5:
		return {}
	var their := clampi(int((absf(tl.y) - Highway.EDGE_IN) / Highway.LANE_W), 0, Highway.LANES - 1)
	var r := _lanes(sp, dir, at[1], at[2], their if ahead < 160.0 else -1, [car, target], dbg)
	var aim: Vector3 = hw.lane_center(dir, r.go, at[1] + dir * clampf(sp * 0.9, 18.0, 70.0))
	if r.go == their and ahead < 70.0:
		aim = target_aim                                 # lined up behind them: go for them
	aim.y = car.global_position.y
	return {"aim": aim, "cap": r.lim}


## "cutup" mode: down the highway as fast as `cruise` and the traffic allow,
## lane to lane (a stand-in for a player cutting up: the tests run it from the cops).
func _cutup(dt: float) -> void:
	var sp: float = car.speed
	var at := _on_highway()
	car.in_handbrake = false
	if at.is_empty():
		car.in_throttle = 0.0
		car.in_brake = 1.0
		return
	_lane_t += dt
	var r := _lanes(sp, at[0], at[1], at[2], -1, [car], debug and Engine.get_physics_frames() % 15 == 0)
	var aim: Vector3 = traffic.hw.lane_center(at[0], r.go, at[1] + at[0] * clampf(sp * 0.9, 18.0, 70.0))
	var local: Vector3 = car.to_local(Vector3(aim.x, car.global_position.y, aim.z))
	car.in_steer = clampf(atan2(-local.x, -local.z) * -2.2, -1.0, 1.0)
	var want: float = minf(cruise, r.lim)
	if sp < want - 0.5:
		car.in_throttle = 1.0
		car.in_brake = 0.0
	elif sp > want + 2.0:
		car.in_throttle = 0.0
		car.in_brake = clampf((sp - want) / 3.0, 0.2, 1.0)
	else:
		car.in_throttle = 0.3
		car.in_brake = 0.0


## The fastest we can be going and still make the bends coming up (the loop's
## ends are 400 m radius: ~70 m/s for the patrol car), braking at hw_brake.
func _curve_cap(dir: int, s: float, sp: float) -> float:
	var hw = traffic.hw
	var a_lat: float = float(car.stats().grip) * 9.8 * 0.9
	var best := INF
	var reach := sp * sp / (2.0 * hw_brake) + 40.0
	var d := 0.0
	var t0: Vector3 = hw.tangent(s)
	while d <= reach:
		var t1: Vector3 = hw.tangent(s + dir * (d + 20.0))
		var kappa := t0.angle_to(t1) / 20.0                  # 1 / radius
		if kappa > 1e-4:
			best = minf(best, sqrt(a_lat / kappa + 2.0 * hw_brake * d))
		t0 = t1
		d += 20.0
	return best


## The fastest we can be going with the next car in a lane `scan[0]` m ahead at
## `scan[1]` m/s and still stop `margin` m behind it braking at `b`.
static func _stop_cap(scan: Array, b: float, margin: float) -> float:
	return scan[1] + sqrt(2.0 * b * maxf(scan[0] - margin, 0.0))


func _clear(r: RayCast3D) -> float:
	return r.get_collision_point().distance_to(r.global_position) if r.is_colliding() else 20.0


## Where the straight line to the target is cut (empty = we can see them).
func _line_of_sight() -> Dictionary:
	var from: Vector3 = car.global_position + Vector3(0, 0.8, 0)
	var to: Vector3 = target.global_position + Vector3(0, 0.8, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [car.get_rid(), (target as CollisionObject3D).get_rid()] if target is CollisionObject3D else [car.get_rid()]
	return car.get_world_3d().direct_space_state.intersect_ray(q)


## Pure pursuit down `path`: steer at a point a speed-scaled distance ahead on
## the road, slow for the bends coming up (sharper = slower), same stuck
## recovery as the chase.
func _follow(dt: float) -> void:
	if path.size() < 2 or done:
		car.in_throttle = 0.0
		car.in_brake = 1.0
		return
	var pos: Vector3 = car.global_position
	var sp: float = car.speed
	if _reverse > 0.0:
		_reverse -= dt
		car.in_throttle = 0.0
		car.in_brake = 1.0
		car.in_steer = _rev_steer
		return
	_stuck = _stuck + dt if absf(sp) < 1.0 and car.in_throttle > 0.5 else maxf(_stuck - dt, 0.0)
	if _stuck > 1.5:
		_stuck = 0.0
		_reverse = 1.2
		_rev_steer = -signf(car.in_steer) if absf(car.in_steer) > 0.1 else 1.0
		return
	# nearest point (only ever forward, within a window)
	var best := _pi
	var bd := INF
	for i in range(_pi, mini(_pi + 40, path.size())):
		var d := _flat(path[i] - pos).length()
		if d < bd:
			bd = d
			best = i
	_pi = best
	if _pi >= path.size() - 2 and bd < 8.0:
		done = true
		return
	# the lookahead point
	var look := clampf(absf(sp) * 0.75, 7.0, 30.0)
	var aim: Vector3 = path[path.size() - 1]
	var acc := 0.0
	for i in range(_pi, path.size() - 1):
		acc += _flat(path[i + 1] - path[i]).length()
		if acc >= look:
			aim = path[i + 1]
			break
	var local: Vector3 = car.to_local(Vector3(aim.x, pos.y, aim.z))
	var ang := atan2(-local.x, -local.z)
	var steer := clampf(-ang * 1.8, -1.0, 1.0)
	# how hard does the road turn in the next ~45 m?
	var turn := 0.0
	acc = 0.0
	var prev := _flat(path[mini(_pi + 1, path.size() - 1)] - path[_pi])
	for i in range(_pi + 1, path.size() - 1):
		var seg := _flat(path[i + 1] - path[i])
		if seg.length() < 0.01:
			continue
		if prev.length() > 0.01:
			turn = maxf(turn, absf(prev.signed_angle_to(seg, Vector3.UP)) / maxf(seg.length(), 1.0))   # rad per metre
		prev = seg
		acc += seg.length()
		if acc > 45.0:
			break
	var grip: float = car.stats().grip
	var want := cruise
	if turn > 0.0005:
		want = minf(want, sqrt(grip * 9.8 * 0.8 / turn))    # v = sqrt(a / curvature)
	want = maxf(want, 6.0)
	if _ray_c.is_colliding():
		var hit := (_ray_c.get_collision_point() - _ray_c.global_position).length()
		want = minf(want, maxf(hit * 1.2, 4.0))
	car.in_steer = steer
	car.in_handbrake = false
	if sp < want - 0.5:
		car.in_throttle = 1.0
		car.in_brake = 0.0
	elif sp > want + 1.5:
		car.in_throttle = 0.0
		car.in_brake = clampf((sp - want) / 6.0, 0.2, 1.0)
	else:
		car.in_throttle = 0.35
		car.in_brake = 0.0


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
