extends Node
## Films a mode for a showcase video (main.gd --showcase=rally|touge|cutup, run with
## Godot's --write-movie out.avi --fixed-fps 30): the autopilot drives, and this cuts
## between cameras like a broadcast: the chase cam, a camera by the road the car
## comes past, the driver's seat, a helicopter, low on a wheel, ahead looking back.
## On the touge a lamp is picked to film under and a local car is sent up the other
## lane; in cut up it weaves the car through the traffic (the autopilot holds the
## lane with the most room, never faster than the gap ahead allows).
## Prints "[showcase] rolling at frame N" when the first shot starts and "[showcase]
## cut at frame N" when it's done (then quits), for trimming the movie.

const SHOTS := {
	"rally": [["chase", 4.5], ["trackside", 4.5], ["seat", 4.5], ["heli", 3.5], ["wheel", 3.0], ["chase", 3.0]],
	"touge": [["chase", 4.0], ["lamp", 4.5], ["seat", 4.5], ["front", 3.5], ["heli", 3.5], ["chase", 3.0]],
	"cutup": [["chase", 4.5], ["side", 4.0], ["heli", 4.0], ["seat", 4.0], ["chase", 4.5]],
}
const WEAVE_CAP := 44.0         # m/s (158 km/h): cut up's pace through the traffic

var game
var kind := "rally"
var shots: Array = []
var _i := -1                    # the shot on now
var _shot_t := 0.0
var _t := -1.0
var _cam: Camera3D              # this one's own camera (the game's for chase and seat)
var _anchor := Vector3.ZERO     # where a roadside camera stands
var _smooth := Vector3.ZERO
var _weave_t := 0.0
var _s0 := 0.0


func setup(g, k: String) -> void:
	game = g
	kind = k if SHOTS.has(k) else "rally"
	shots = SHOTS[kind]
	name = "Showcase"
	_cam = Camera3D.new()
	_cam.near = 0.05
	_cam.far = 1200.0
	_cam.cull_mask = 0xFFFFF & ~(1 << 1)             # (not the driver's helmet: the camera can go in it)
	game.add_child(_cam)
	if float(Config.arg("showcase_pace", 1.0)) != 1.0:          # (a bolder autopilot for the cameras)
		game.autopilot = load("res://scripts/vehicle/autopilot.gd").new(game.st, float(Config.arg("showcase_pace", 1.0)))


func _process(dt: float) -> void:
	if game == null or not game.built or game.state != "running":
		return
	if _t < 0.0:
		_t = 0.0
		print("[showcase] rolling at frame %d" % Engine.get_process_frames())
		_s0 = game.car_s
		_next()
	_t += dt
	_shot_t += dt
	if OS.get_cmdline_user_args().has("--showcase_trace") and int(_t) != int(_t - dt):
		print("[showcase] t %2d s %.0f d %+.1f %3.0f km/h shot %s%s" % [int(_t), game.car_s, game.car_d, game.car.linear_velocity.length() * 3.6,
			shots[_i][0], (" stray at %.0f" % float(game.stray.car.s)) if game.stray and not game.stray.car.is_empty() else ""])
	if _shot_t >= float(shots[_i][1]):
		if _i + 1 >= shots.size():
			print("[showcase] cut at frame %d" % Engine.get_process_frames())
			var extra := ""
			if game.cutup:
				extra = ", %d near misses, %d crashes" % [game.cutup.near_misses, game.cutup.crashes]
			print("[showcase] %s: %.0f m in %.1f s (%.0f km/h on average)%s" % [kind, game.car_s - _s0, _t, (game.car_s - _s0) / maxf(_t, 0.1) * 3.6, extra])
			get_tree().quit(0)
			return
		_next()
	_film(dt)


func _physics_process(dt: float) -> void:
	if game == null or not game.built or game.autopilot == null:
		return
	if kind == "cutup" and game.traffic:
		_weave(dt)


## The next shot: which camera, set up where it needs to be.
func _next() -> void:
	_i += 1
	_shot_t = 0.0
	var type: String = shots[_i][0]
	var car: Node3D = game.car
	var st = game.st
	var s: float = game.car_s
	var v: float = maxf(car.linear_velocity.length(), 8.0)
	game._hud.visible = type in ["chase", "seat"]
	match type:
		"chase", "seat":
			game.view_override = type
			game.cam.make_current()
			return
		"trackside":
			# by the road ~2 s ahead, on the outside of what's coming, at a spectator's height
			var at: float = s + v * 2.2
			var k: float = st.curv[clampi(int(at / st.STEP), 0, st.curv.size() - 1)]
			var side := -1.0 if k > 0.0 else 1.0
			_anchor = st.world_at(at, side * (st.width_at(at) * 0.5 + 3.5)) + Vector3.UP * 1.3
		"lamp":
			# under the next street lamp ahead (the touge at night), looking back up the road
			var lamp_s: float = s + v * 2.0
			var lamps: Array = game.builder.get("lamps") if game.builder.get("lamps") != null else []
			for l in lamps:
				if float(l.s) > s + v * 1.6:
					lamp_s = float(l.s)
					break
			_anchor = st.world_at(lamp_s + 6.0, -(st.width_at(lamp_s) * 0.5 + 2.5)) + Vector3.UP * 1.6
	if kind == "touge" and type == "front" and game.stray:
		game.stray.spawn_at(s + v * 4.5 + 40.0, -1)  # (a local coming up the other lane, lamps lit)
	game.view_override = "chase"                       # (the car seen from outside, the cockpit hidden)
	_cam.make_current()
	_smooth = car.global_position
	_film(0.0)


## Where this shot's camera is this frame.
func _film(dt: float) -> void:
	var type: String = shots[_i][0]
	var car: Node3D = game.car
	var xf: Transform3D = car.get_global_transform_interpolated()
	var p: Vector3 = xf.origin
	var fwd: Vector3 = -xf.basis.z
	var right: Vector3 = xf.basis.x
	match type:
		"trackside", "lamp":
			_cam.global_position = _anchor
			_look(p + Vector3.UP * 0.7)
			var dist := _anchor.distance_to(p)
			_cam.fov = clampf(rad_to_deg(2.0 * atan(5.5 / maxf(dist, 1.0))), 16.0, 70.0)   # (zoomed to keep it framed)
		"heli":
			var want := p - fwd * 16.0 + right * 9.0 + Vector3.UP * 11.0
			_smooth = want if dt == 0.0 else _smooth.lerp(want, 1.0 - exp(-3.0 * dt))
			_cam.global_position = _smooth
			_look(p + fwd * 6.0)
			_cam.fov = 55.0
		"wheel":
			_cam.global_position = xf * Vector3(1.25, 0.32, 0.6)
			_look(xf * Vector3(0.6, 0.25, -12.0))
			_cam.fov = 68.0
		"side":
			_cam.global_position = xf * Vector3(-2.4, 0.75, 1.6)
			_look(xf * Vector3(-0.4, 0.55, -14.0))
			_cam.fov = 72.0
		"front":
			_cam.global_position = xf * Vector3(0.0, 1.05, -7.5)
			_look(xf * Vector3(0.0, 0.55, 0.0))
			_cam.fov = 58.0


func _look(at: Vector3) -> void:
	if _cam.global_position.distance_squared_to(at) > 0.01:
		_cam.look_at(at, Vector3.UP)


## Cut up: hold the lane with the most room ahead (one lane at a time), never faster
## than the gap to the car ahead in it allows.
func _weave(dt: float) -> void:
	var tr = game.traffic
	var ap = game.autopilot
	var s: float = game.car_s
	var d: float = game.car_d
	_weave_t -= dt
	var lanes: Array = tr.lane_d
	var mine := 0
	for k in lanes.size():
		if absf(float(lanes[k]) - d) < absf(float(lanes[mine]) - d):
			mine = k
	var gaps: Array = []
	for k in lanes.size():
		var gap := 400.0
		var gv := 99.0
		for c in tr.cars:
			var rel: float = tr._ds(float(c.s), s)
			if rel > 0.0 and rel < gap and absf(float(c.d) - float(lanes[k])) < 1.6:
				gap = rel
				gv = float(c.v)
		gaps.append([gap, gv])
	if _weave_t <= 0.0 or ap.lane == INF:
		_weave_t = 0.6
		var best := mine
		for k in [mine - 1, mine + 1]:
			if k < 0 or k >= lanes.size():
				continue
			# (and nothing alongside in that lane: the gap behind it as well)
			var alongside := false
			for c in tr.cars:
				var rel2: float = tr._ds(float(c.s), s)
				if rel2 > -9.0 and rel2 < 9.0 and absf(float(c.d) - float(lanes[k])) < 1.6:
					alongside = true
			if not alongside and float(gaps[k][0]) > float(gaps[best][0]) + 25.0:
				best = k
		ap.lane = float(lanes[best])
	var lead: Array = gaps[mine]
	ap.cap = minf(WEAVE_CAP, float(lead[1]) + maxf(float(lead[0]) - 14.0, 0.0) * 0.35)
