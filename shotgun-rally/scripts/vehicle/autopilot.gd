extends RefCounted
## Drives the car down the stage with the same inputs a player has: the
## tests' stand-in driver (and a way to try the co-driver seat alone later).
##   * steering (the car's steering is a wheel angle: input x lock): it picks
##     the curve to drive (1/m): the road's bend just ahead, plus turning back
##     parallel to the road, plus closing the gap to its line (a damped spring:
##     gentle at speed, where a little steering turns the car a lot), measured
##     at the front axle; then the wheel angle for that curve: the bicycle
##     geometry (atan(wheelbase x curvature)), plus the slip angle the front
##     tyres need for that much side force, measured from the way the REAR axle
##     is going (when the tail steps out, that's countersteer, as a driver
##     would). The line drifts to the inside of the next corner
##   * speed: the fastest the next 150 m allows: sqrt(mu g R) at every
##     corner (mu from the surface on its line: StageGen.grip_at), braked down to
##     in time (v^2 = vc^2 + 2 a d)

const MU := 0.45                 # how hard it dares to corner (fraction of g): under half the car's grip, a margin for the loose gravel off the clean line
const DECEL := 5.5               # how hard it plans to brake (m/s^2)
const HOLD := 1.6                # rad/s: how briskly it gets back onto its line (the spring) ...
const HOLD_DAMP := 0.9           # ... damped (1 = no overshoot)
const PREVIEW := 0.35            # s: the bend it steers for is this far ahead (the steering takes a moment)
const CATCH := 1.0               # how much of the tail's angle it countersteers

var st                           # StageGen
var _vmax := PackedFloat32Array()  # corner speed limit per centerline sample


func _init(stage) -> void:
	st = stage
	_vmax.resize(st.pts.size())
	for i in st.pts.size():
		# the tightest radius around this sample (curvature averaged over ~8 m)
		var k := 0.0
		for j in range(maxi(0, i - 2), mini(st.curv.size(), i + 3)):
			k = maxf(k, absf(st.curv[j]))
		# a narrow road leaves less room to straighten the bend: slower; and the surface
		# along its line (toward the inside): the asphalt grips more, ice and snow far less
		var mu: float = MU * clampf(0.86 + 0.14 * (st.widths[i] - 4.6), 0.86, 1.0)
		var g: float = st.grip_at(i * st.STEP, clampf(st.curv[i] * 30.0, -0.6, 0.6))
		mu *= g
		_vmax[i] = 60.0 if k < 1e-4 else minf(60.0, sqrt(mu * 9.8 / k))
		if g < 0.5:
			_vmax[i] = minf(_vmax[i], 24.0)              # ice or snow under it: lift, even on a straight
	# brows in a bend: lift so the tyres stay loaded (over a brow the car gets light
	# at v^2 / R = g; light while turning, it slides wide)
	for i in range(2, st.pts.size() - 2):
		var kv: float = (st.pts[i + 2].y - 2.0 * st.pts[i].y + st.pts[i - 2].y) / (4.0 * st.STEP * st.STEP)
		var bend := 0.0
		for j in range(maxi(0, i - 6), mini(st.curv.size(), i + 7)):
			bend = maxf(bend, absf(st.curv[j]))
		if kv < -1e-3 and bend > 1.0 / 600.0:
			_vmax[i] = minf(_vmax[i], sqrt(0.9 * 9.8 / -kv))
		# crests: lift so it doesn't fly into the next corner
	for c in st.crests:
		var i := int(c.s / st.STEP)
		for j in range(maxi(0, i - 8), mini(_vmax.size(), i + 4)):
			_vmax[j] = minf(_vmax[j], 26.0 if c.jump else 30.0)


## Inputs for the car at road position (s, d) going at speed (m/s).
func drive(car, s: float, d: float) -> Dictionary:
	var spd: float = car.linear_velocity.length()
	var xf: Transform3D = car.global_transform
	var fwd: Vector3 = -xf.basis.z
	var base: float = car.config.rear_axle - car.config.front_axle
	var lock: float = deg_to_rad(car.config.steering.max_angle_deg)
	# its line: toward the inside of what's coming
	var look := 6.0 + spd * 0.45
	var ahead_i := clampi(int((s + look) / st.STEP), 0, st.curv.size() - 1)
	var bend: float = st.curv[ahead_i]
	var line_d := clampf(bend * 30.0, -0.6, 0.6)         # + curvature = a right turn, whose inside is d > 0
	# where the front axle is on the road
	var front: Vector3 = car.global_position + fwd * -car.config.front_axle
	var fs: float = s + fwd.dot(st.forward_at(s)) * -car.config.front_axle
	var fd: float = (front - st.point_at(fs)).dot(st.right_at(fs))
	# the bend just ahead (averaged: the road is sampled every STEP m)
	var k := 0.0
	var n := 0
	var reach := maxf(spd * PREVIEW, st.STEP)
	var x := fs
	while x <= fs + reach:
		k += st.curv[clampi(int(x / st.STEP), 0, st.curv.size() - 1)]
		n += 1
		x += st.STEP * 0.5
	k /= maxf(n, 1)
	# the way the rear axle is going (once it's moving): how far the tail is out (+ = to the right) ...
	var right: Vector3 = xf.basis.x
	var rear_v: Vector3 = car.linear_velocity + car.angular_velocity.cross(xf.basis * Vector3(0.0, 0.0, car.config.rear_axle))
	var tail := 0.0
	var dir := fwd
	if spd > 4.0:
		tail = atan2(rear_v.dot(right), maxf(rear_v.dot(fwd), 0.5))
		dir = (rear_v - xf.basis.y * rear_v.dot(xf.basis.y)).normalized()
	# ... back parallel to the road ...
	var road_yaw: float = st.heading_at(fs)
	var yaw: float = atan2(dir.x, -dir.z)                      # (the same convention as the road's heading)
	var v := maxf(spd, 4.0)
	k += 2.0 * HOLD_DAMP * HOLD * wrapf(road_yaw - yaw, -PI, PI) / v
	# ... and onto its line
	k += HOLD * HOLD * (line_d - fd) / (v * v)
	# the front tyres' slip angle for that much side force (a share of their grip)
	var tyre: Resource = car.wheels[0].surface_tire
	var share := clampf(spd * spd * absf(k) / (tyre.lateral_mu * 9.8), 0.0, 1.0)
	var slip := deg_to_rad(tyre.lateral_peak_deg) * (1.0 - sqrt(1.0 - share)) * signf(k)
	var steer_cmd := clampf((atan(base * k) + slip + CATCH * tail) / lock, -1.0, 1.0)
	# speed: the lowest braking-allowed speed over the next 150 m
	var want := 60.0
	var i0 := int(s / st.STEP)
	for j in range(i0, mini(_vmax.size(), i0 + int(150.0 / st.STEP))):
		var dist: float = (j - i0) * st.STEP
		want = minf(want, sqrt(_vmax[j] * _vmax[j] + 2.0 * DECEL * dist))
	if s > st.finish_s + 5.0:
		want = 0.0                                       # through the finish: stop
	var thr := 0.0
	var brk := 0.0
	if spd < want - 1.0:
		thr = clampf((want - spd) / 4.0, 0.25, 1.0)
	elif spd > want + 1.5:
		# threshold braking, like a driver: never quite all of it (no ABS: full brake locks
		# the fronts), and less while it's turning (a locked front doesn't steer)
		brk = clampf((spd - want) / 5.0, 0.2, 0.85) * (1.0 - 0.45 * absf(steer_cmd))
		brk *= clampf(1.0 - absf(tail) / 0.15, 0.3, 1.0)   # the tail's stepping out: ease off, like a driver
	# (pressed so that it gets there through the steering smoothing aid, if that's on)
	var press: float = car.assist.input_for(steer_cmd, 1.0 / Engine.physics_ticks_per_second)
	return {"steer": press, "throttle": thr, "brake": brk, "handbrake": false}
