extends RefCounted
## Drives the car down the stage with the same inputs a player has: the
## tests' stand-in driver (and a way to try the co-driver seat alone later).
##   * steering: aim at a point down the road (further at speed), on a line
##     that drifts to the inside of the next corner
##   * speed: the fastest the next 150 m allows: sqrt(mu g R) at every
##     corner, braked down to in time (v^2 = vc^2 + 2 a d)

const MU := 0.45                 # how hard it dares to corner (fraction of g): under half the car's grip, a margin for the loose gravel off the clean line
const DECEL := 5.5               # how hard it plans to brake (m/s^2)

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
		# a narrow road leaves less room to straighten the bend: slower
		var mu: float = MU * clampf(0.86 + 0.14 * (st.widths[i] - 4.6), 0.86, 1.0)
		_vmax[i] = 60.0 if k < 1e-4 else minf(60.0, sqrt(mu * 9.8 / k))
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
	# where to aim: ahead on the road, toward the inside of what's coming
	var look := 6.0 + spd * 0.45
	var ahead_i := clampi(int((s + look) / st.STEP), 0, st.curv.size() - 1)
	var bend: float = st.curv[ahead_i]
	var line_d := clampf(bend * 30.0, -0.6, 0.6)         # + curvature = a right turn, whose inside is d > 0
	var aim: Vector3 = st.world_at(s + look, line_d)
	var to: Vector3 = aim - car.global_position
	var fwd: Vector3 = -car.global_transform.basis.z
	var right: Vector3 = car.global_transform.basis.x
	var ang := atan2(to.dot(right), to.dot(fwd))
	# steering asks the front tyres for grip (full = their peak), so it's just how far off
	# the aim point the nose is
	var steer_cmd := clampf(ang * 2.6, -1.0, 1.0)
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
	return {"steer": steer_cmd, "throttle": thr, "brake": brk, "handbrake": false}
