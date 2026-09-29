extends Node
## Drives the Car it's attached to (its parent) with the same controls a
## player has. PURSUE: aim where the target is going to be, match its speed
## then close in, don't hit walls, back out when stuck. The cops' brain.

var car
var target: Node3D               # the car we're chasing
var mode := "pursue"             # "pursue" a target / "path": drive along `path`
var path := PackedVector3Array() # "path" mode: the road to follow (points ~5-10 m apart)
var cruise := 30.0               # "path" mode: speed on the straights (m/s)
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
	# no straight line to them (a wall, a truck): aim past the edge of whatever's
	# in the way, on one side, until we can see them again
	var los := _line_of_sight()
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
	var want := their + clampf((dist - 9.0) * 0.55, -6.0, 22.0)
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
		car.in_brake = clampf((sp - want) / 8.0, 0.2, 1.0)
	else:
		car.in_throttle = 0.3
		car.in_brake = 0.0


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
