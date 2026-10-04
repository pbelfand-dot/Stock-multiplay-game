extends RefCounted
## Drives the car down the stage with the same inputs a player has: the
## tests' stand-in driver (and a way to try the co-driver seat alone later).
##   * steering: aim at a point down the road (further at speed), on a line
##     that drifts to the inside of the next corner
##   * speed: the fastest the next 150 m allows: sqrt(mu g R) at every
##     corner, braked down to in time (v^2 = vc^2 + 2 a d)

const MU := 0.5                  # how hard it dares to corner (fraction of g): ~2/3 of the car's grip
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
		_vmax[i] = 60.0 if k < 1e-4 else minf(60.0, sqrt(MU * 9.8 / k))
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
	var lock: float = car.steer_lock(spd)
	# never ask the front tyres for much more than their peak slip (plus the corner's own
	# geometry): past that they let go and the car runs wide
	var useful: float = car.SLIP_PEAK * 1.4 + 2.4 * absf(st.curv[clampi(int(s / st.STEP), 0, st.curv.size() - 1)])
	var steer_cmd := clampf(ang * 1.3, -useful, useful) / lock
	steer_cmd = clampf(steer_cmd, -1.0, 1.0)
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
		brk = clampf((spd - want) / 5.0, 0.2, 1.0)
	return {"steer": steer_cmd, "throttle": thr, "brake": brk, "handbrake": false}
