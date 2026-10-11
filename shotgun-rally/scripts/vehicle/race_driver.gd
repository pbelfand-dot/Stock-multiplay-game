extends RefCounted
## Track Mode's AI racing driver: one per AI car (RaceField runs them). It drives with the same
## inputs a player has (steering, throttle, brake: the car's own ABS and TC catch the rest), or,
## far from the player, moves its car along the same line at the same speeds without the physics
## (RaceField's cheap mode: far_step).
##
##   * the line: the circuit's racing line (CircuitGen.line, tools/circuit_map.py) and the speed
##     its car can carry along it at this driver's pace (RaceLine: grip x pace, never more grip
##     or power than the car has: a better driver only uses more of what's there);
##   * steering: the autopilot's (Autopilot.drive): the path's bend just ahead, back parallel to
##     it, onto it (a damped spring), the bicycle geometry and the front tyres' slip angle, the
##     tail's angle countersteered; the path is the line plus its racecraft offset (or the pit
##     lane's path in and out of its box);
##   * racecraft (plan, every tick, from where the cars round it are):
##       - a car ahead in its path that it's catching: a side with room (the inside of the next
##         corner first), committed to until it's past (no weaving); no room: it follows, a
##         car's length and a third of a second back;
##       - a car alongside: it keeps a car's width away from it (it never turns into it, the
##         player included), and backs out of a squeeze;
##       - a car behind, catching it before a braking zone: it moves to the inside, once a
##         straight (defending once: no second move);
##       - a blue flag (a leader lapping it): off the line, a lift on the straight; a yellow:
##         no passing (a stricken car excepted), a lift;
##       - a car stopped or crawling ahead: round it;
##       - its mistakes (a lower consistency: more): a corner run wide or braked too late, a
##         little pace lost or found from corner to corner;
##   * the start: held on the brakes at the line until the lights go out (its reaction time),
##     or in its place in the rolling start's double file;
##   * the pits: down the pit lane on the limiter, into its box, stopped while it's serviced
##     (tyres, fuel, repairs: RaceSim.service), back out along the lane and its taper.

const RaceLine = preload("res://scripts/game/race_line.gd")

const HOLD := 1.5                  # rad/s: how briskly it gets back onto its path ...
const HOLD_DAMP := 0.9             # ... damped
const PREVIEW := 0.3               # s: the bend it steers for is this far ahead
const CATCH := 1.0                 # how much of the tail's angle it countersteers
const CAR_L := 4.8                 # m: a GT3's length (4.6-4.75) and a little
const SIDE := 2.7                  # m between two cars' middles side by side (2.05 m wide each, a gap)
const EDGE := 1.15                 # m: the farthest its middle goes is the white line less this (wheels on the line)
const FAR_LAT := 3.0               # m/s: how quickly a far car moves across
const FAR_K := 0.985               # a far car's speed x its line's: the share of the line's pace a car on the physics, its tyres warm,
                                   # makes good lap after lap (measured: tests/race_ai_check.gd, driver vs far)

var st                             # CircuitGen
var line                           # RaceLine at this driver's pace
var id = 0
var driver_name := ""
var pace := 0.97                   # how near the car's limit it drives (0.85 .. 1.0)
var consistency := 0.9             # 1: the same every corner
var aggression := 0.5              # how readily it goes for a gap
var reaction := 0.25               # s from lights out to the throttle
var rng := RandomNumberGenerator.new()

# where it is (both modes) and what it's doing
var s := 0.0                       # round the lap, unwrapped (keeps growing)
var d := 0.0                       # from the centreline (+ right)
var v := 0.0                       # speed (m/s)
var task := "hold"                 # "hold" (on the grid), "formation", "race", "pit", "cool" (finished), "out" (retired)
var offset := 0.0                  # from the line: racecraft's (smoothed)
var cap := INF                     # m/s: racecraft's speed limit (a car to follow)
var d_lo := -INF                   # the side-by-side limits on its d
var d_hi := INF
var yellow := false                # (RaceControl) a yellow where it is
var blue := false                  # (RaceControl) a leader lapping it
var blue_d := 0.0                  # (RaceControl) the d of the car lapping it
var no_passing := false            # (formation, a red flag: hold station)
var limit_v := INF                 # (race control) m/s: the formation's pace, a red flag's
var pace_mul := 1.0                # (qualifying) an out-lap's gentler pace
var slot := Vector2.ZERO           # (formation) [gap behind the car ahead of it in the order, d]
var follow_id = null               # (formation) the car ahead of it in the order
var hold_t := 0.0                  # (the start) s since the lights went out
var lights_out := false
var pit_lap := -1                  # the lap it pits at the end of (-1: no stop planned)
var pit_box := 0
var pit_phase := ""                # "in", "stop", "out"
var pit_service := {}              # what it gets: {tyres, fuel, repair}
var stop_t := 0.0                  # s left in its box
var laps := 0                      # (RaceField) laps done
var stuck_t := 0.0
var steer_look := 0.0              # (far mode) the wheels' angle, for the picture
var events: Array = []             # [kind, ...] for RaceField: "pit_in", "serviced", "pit_out", "mistake"

var _pass_id = null                # the car it's committed to passing
var _pass_side := 0
var _defend_c := -1                # the corner it last defended into
var _corner := -1                  # the corner it's in or coming to
var _mistake := 0.0                # this corner: + ran wide (m) / braked late
var _corner_k := 1.0               # this corner's pace jitter
var _corner_wide := 0.0            # how far wide of its path it's been in this corner (m)
var _adapt := {}                   # corner -> its pace x, learnt: down after a corner run wide, slowly back up


## st: the CircuitGen; prm: RaceLine.params(car); skill: {pace, consistency, aggression, reaction}.
func setup(stage, prm: Dictionary, skill: Dictionary, seed_value: int) -> void:
	st = stage
	pace = float(skill.get("pace", 0.97))
	consistency = float(skill.get("consistency", 0.9))
	aggression = float(skill.get("aggression", 0.5))
	reaction = float(skill.get("reaction", 0.25))
	rng.seed = seed_value
	line = RaceLine.new()
	line.build(st, prm, pace)


## The d it's steering for at s (the line plus racecraft's offset, inside the side-by-side limits
## and the track; or the pit lane's path).
func target_d(x: float) -> float:
	if task == "pit":
		return pit_d(x)
	var lim: float = st.half_at(x) - EDGE
	var want: float
	if task == "formation":
		want = slot.y
	else:
		want = line.d_at(x) + offset + _mistake * _outside(x)
	return clampf(clampf(want, d_lo, d_hi), -lim, lim)


## The speed it wants at x (m/s).
func want_v(x: float) -> float:
	match task:
		"hold", "out":
			return 0.0
		"pit":
			return pit_v(x)
		"cool":
			return minf(line.speed_at(x) * 0.8, cap)
	var w: float = line.speed_at(x) * _corner_k * pace_mul * float(_adapt.get(_corner, 1.0))
	if task == "formation":
		w = minf(line.speed_at(x), limit_v + 4.0)       # (catching up to its place in the double file)
	w = minf(w, limit_v) if follow_id == null or task != "formation" else w
	if _mistake < 0.0:
		w *= 1.0 - _mistake * 0.02                     # (a late brake: in too fast)
	if yellow:
		w *= 0.9
	if blue and line.speed_at(x) > 50.0:
		w *= 0.95                                      # (a lift on the straight to let the leader by)
	return minf(w, cap)


# ── racecraft ───────────────────────────────────────────────────────────────

## Look round it (others: [{id, s, d, v, stricken}] every other car, the player's too, s unwrapped
## or not) and decide its offset, its speed cap and its side-by-side limits. dt: since last time.
func plan(others: Array, dt: float) -> void:
	var L: float = st.length
	cap = INF
	d_lo = -INF
	d_hi = INF
	if task in ["hold", "out"]:
		return
	_corner_check()
	var lim: float = st.half_at(s) - EDGE
	var my_line: float = line.d_at(s)
	var want_off := 0.0
	var ahead = null
	var ahead_gap := INF
	var behind = null
	var behind_gap := INF
	var reach := 25.0 + v * 1.6
	for o in others:
		var gap: float = fposmod(float(o.s) - s + L * 0.5, L) - L * 0.5     # + : it's ahead
		var od: float = o.d
		if absf(gap) < CAR_L + 0.5:
			# alongside: keep a car's width from it, whatever the line wants
			if absf(od - d) < SIDE + 0.6:
				if od >= d:
					d_hi = minf(d_hi, od - SIDE)
				else:
					d_lo = maxf(d_lo, od + SIDE)
			continue
		if gap > 0.0 and gap < reach:
			# in its path? (where it'll be when it gets there)
			var mine: float = line.d_at(float(o.s)) + offset
			if absf(od - mine) < SIDE - 0.3 or (_pass_id != null and o.id == _pass_id):
				if gap < ahead_gap:
					ahead_gap = gap
					ahead = o
		elif gap < 0.0 and -gap < 14.0 + v * 0.35:
			if -gap < behind_gap:
				behind_gap = -gap
				behind = o
	if task == "formation":
		_formation(others)
		offset = 0.0
		return
	if ahead != null:
		var closing: float = v - float(ahead.v)
		var stricken: bool = bool(ahead.get("stricken", false)) or float(ahead.v) < v * 0.5
		var faster: bool = line.speed_at(float(ahead.s)) * pace > float(ahead.v) + 0.8 or closing > 1.0
		var may_pass: bool = (not yellow and not no_passing) or stricken
		var side := 0
		if may_pass and faster:
			side = _pass_side if (_pass_id != null and ahead.id == _pass_id) else _pick_side(ahead, lim)
		if side != 0:
			_pass_id = ahead.id
			_pass_side = side
			want_off = (float(ahead.d) + side * SIDE) - my_line
		else:
			_pass_id = null
			# follow: a car's length and ~0.3 s back
			var keep := CAR_L + 1.5 + 0.3 * v
			cap = maxf(float(ahead.v) + (ahead_gap - keep) * 0.6, 0.0)
	else:
		_pass_id = null
	# defend once into a braking zone: the inside of the corner coming
	if behind != null and ahead == null and _pass_id == null and float(behind.v) > v - 0.5 and not no_passing:
		var c := _next_corner(s)
		if not c.is_empty() and int(c.n) != _defend_c:
			var to_brake: float = float(c.s0) - fposmod(s, L)
			if to_brake < 0.0:
				to_brake += L
			if to_brake < 260.0 and to_brake > 60.0:
				_defend_c = int(c.n)
		if _defend_c >= 0 and not c.is_empty() and int(c.n) == _defend_c:
			var inside := 1.0 if int(c.dir) > 0 else -1.0
			want_off = inside * (lim - 0.6) - my_line
			if absf(want_off) < 0.4:
				want_off = 0.0
	# a blue flag: off the line, the other side from the car lapping it
	if blue and _pass_id == null:
		var away := -1.0 if blue_d > d else 1.0
		want_off = away * (lim - 0.3) - my_line
	# back toward the line, never across the nose of a car it just passed (alongside limits hold it)
	var rate := 1.6 + 0.04 * v
	offset = move_toward(offset, want_off, rate * dt)
	offset = clampf(offset, -lim - my_line, lim - my_line)
	# squeezed between two cars: drop back out of it
	if d_lo > d_hi:
		cap = minf(cap, maxf(v - 3.0, 0.0))
		d_lo = -INF
		d_hi = INF


## A side to pass a car on: room for its middle a car's width from the other's (inside the white
## lines), the inside of the next corner first. 0: none.
func _pick_side(o: Dictionary, lim: float) -> int:
	var od: float = o.d
	var room_r: bool = od + SIDE <= lim
	var room_l: bool = od - SIDE >= -lim
	if not room_r and not room_l:
		return 0
	if room_r and not room_l:
		return 1
	if room_l and not room_r:
		return -1
	var c := _next_corner(float(o.s))
	if not c.is_empty():
		return 1 if int(c.dir) > 0 else -1
	return 1 if od < 0.0 else -1


## The formation: its place in the double file, a car's length or two behind the car ahead of it.
func _formation(others: Array) -> void:
	if follow_id == null:
		return
	var L: float = st.length
	for o in others:
		if o.id == follow_id:
			var gap: float = fposmod(float(o.s) - s + L * 0.5, L) - L * 0.5
			cap = maxf(float(o.v) + (gap - slot.x) * 0.5, 0.0)
			return


## The next corner from x (CircuitGen.track_corners: {n, dir, s0, s_apex, s1, ...}) whose braking
## zone it's in or coming to; {} if none.
func _next_corner(x: float) -> Dictionary:
	var w: float = fposmod(x, st.length)
	var best := {}
	var best_ds := INF
	for c in st.track_corners:
		var ds: float = float(c.s1) - w
		if ds < 0.0:
			ds += st.length
		if ds < best_ds:
			best_ds = ds
			best = c
	return best


## Each new corner: this corner's pace (a little up or down: the less consistent, the more) and,
## now and then, a mistake: wide on the exit, or in too fast.
func _corner_check() -> void:
	var c := _next_corner(s)
	if c.is_empty() or int(c.n) == _corner:
		return
	if _corner >= 0:
		var a: float = float(_adapt.get(_corner, 1.0))
		if _corner_wide > 1.5:
			a = maxf(a - 0.02 * minf(_corner_wide - 1.0, 3.0), 0.85)
		elif _corner_wide < 0.6:
			a = minf(a + 0.004, 1.0)
		_adapt[_corner] = a
	_corner_wide = 0.0
	_corner = int(c.n)
	_corner_k = 1.0 + rng.randfn(0.0, (1.0 - consistency) * 0.025)
	_corner_k = clampf(_corner_k, 0.95, 1.02)
	_mistake = 0.0
	if task == "race" and rng.randf() < (1.0 - consistency) * 0.12:
		_mistake = rng.randf_range(0.8, 1.8) if rng.randf() < 0.6 else -rng.randf_range(0.5, 1.5)
		events.append(["mistake", _corner])


## +1 where the outside of the corner it's in is to the right, -1 left, 0 on a straight.
func _outside(x: float) -> float:
	if _mistake <= 0.0:
		return 0.0
	var k: float = line.k_at(x)
	return 0.0 if absf(k) < 1.0 / 400.0 else (-1.0 if k > 0.0 else 1.0)


# ── the pits ────────────────────────────────────────────────────────────────

## Its box's middle round the line (-length/2 .. length/2: the pit straight's s).
func box_x() -> float:
	return st.around_line(st.box_sd(pit_box).x)


## The pit lane's path at x: over to the right, down the taper into the fast lane, into its box,
## and out: back to the fast lane, along the exit's taper, onto the track.
func pit_d(x: float) -> float:
	var p: Dictionary = st.pit
	var a: float = st.around_line(x)
	var h: float = st.half_at(x)
	var bx := box_x()
	var fast := float(p.fast_d)
	if pit_phase == "in":
		if a < float(p.s_in0) - 200.0 or a > bx + 2.0:
			return clampf(line.d_at(x), -h + EDGE, h - EDGE) if a < float(p.s_in0) - 200.0 else float(p.box_d)
		if a < float(p.s_in0):
			return lerpf(clampf(line.d_at(x), -h + EDGE, h - EDGE), h - EDGE, smoothstep(float(p.s_in0) - 200.0, float(p.s_in0) - 60.0, a))
		if a < float(p.s_in1):
			return st.pit_inner_d(x) + 2.0
		return lerpf(fast, float(p.box_d), smoothstep(bx - 20.0, bx - 5.0, a))
	if pit_phase == "stop":
		return float(p.box_d)
	# out
	if a < bx - 2.0:
		return float(p.box_d)
	if a < float(p.s_out0):
		return lerpf(float(p.box_d), fast, smoothstep(bx, bx + 14.0, a))
	var so1 := float(p.s_out1)
	if a < so1 - 10.0:
		return st.pit_inner_d(x) + 2.0
	# off the end of the lane onto the track, across its line only once the line's ended
	var lane_end: float = st.pit_inner_d(st.wrap_s(so1 - 10.0)) + 2.0
	if a < so1 + 50.0:
		return lerpf(lane_end, h - EDGE, smoothstep(so1 - 10.0, so1 + 50.0, a))
	return lerpf(h - EDGE, clampf(line.d_at(x), -h + EDGE, h - EDGE), smoothstep(so1 + 50.0, so1 + 200.0, a))


## The speed down the pit lane at x: braked to the limit by its line, the limit, stopping in the box.
func pit_v(x: float) -> float:
	var p: Dictionary = st.pit
	var a: float = st.around_line(x)
	var lim := float(p.limit_kmh) / 3.6 - 0.4
	var bx := box_x()
	if pit_phase == "in":
		var w: float = line.speed_at(x)
		if a < float(p.s_lim0):
			w = minf(w, sqrt(lim * lim + 2.0 * 7.0 * maxf(float(p.s_lim0) - 8.0 - a, 0.0)))
		if a > float(p.s_in0):
			w = minf(w, maxf(lim, sqrt(lim * lim + 2.0 * 7.0 * maxf(float(p.s_lim0) - 8.0 - a, 0.0))))
		if a > float(p.s_lim0) - 8.0:
			w = minf(w, lim)
		w = minf(w, sqrt(2.0 * 3.0 * maxf(bx - a, 0.0)) + 0.5)
		return w
	if pit_phase == "stop":
		return 0.0
	if a < float(p.s_lim1):
		return lim
	return line.speed_at(x)


## Each tick: the pit stop's steps (lap: the laps it's done). Returns true while it's in the pits.
func pit_tick(dt: float) -> bool:
	var p: Dictionary = st.pit
	var a: float = st.around_line(s)
	if task == "race" and pit_lap >= 0 and laps >= pit_lap and a > float(p.s_in0) - 400.0 and a < float(p.s_in0) - 200.0:
		task = "pit"
		pit_phase = "in"
		events.append(["pit_in"])
	if task != "pit":
		return false
	match pit_phase:
		"in":
			if a > box_x() - 2.5 and v < 0.8:
				if bool(pit_service.get("park", false)):
					task = "out"                         # (qualifying's done: parked in its box)
					pit_phase = ""
					pit_lap = -1
					events.append(["parked"])
					return true
				pit_phase = "stop"
				stop_t = service_time(pit_service)
				events.append(["stopped", stop_t])
		"stop":
			stop_t -= dt
			if stop_t <= 0.0:
				pit_phase = "out"
				pit_lap = -1
				events.append(["serviced", pit_service])
		"out":
			if a > float(p.s_out1) + 200.0:
				task = "race"
				pit_phase = ""
				events.append(["pit_out"])
	return true


## How long a stop takes (s): new tyres ~12 s (two mechanics, four wheels), fuel at ~2 l/s (not
## while the tyres are changed, as most GT series), repairs up to 30 s.
static func service_time(sv: Dictionary) -> float:
	var t := 3.0
	if bool(sv.get("tyres", false)):
		t += 12.0
	t += float(sv.get("fuel", 0.0)) / 2.0
	t += clampf(float(sv.get("repair", 0.0)) * 40.0, 0.0, 30.0)
	return t


# ── driving: the physics car ────────────────────────────────────────────────

## Inputs for its car (near: the physics drives it), s / d where the car is now.
func drive(car, dt: float) -> Dictionary:
	var spd: float = car.linear_velocity.length()
	v = spd
	if task in ["hold", "out"] or (task == "pit" and pit_phase == "stop"):
		if task == "hold" and lights_out:
			hold_t += dt
			if hold_t >= reaction:
				task = "race"
		if task in ["hold", "out"] or pit_phase == "stop":
			return {"steer": 0.0, "throttle": 0.55 if task == "hold" else 0.0, "brake": 1.0, "handbrake": task != "hold", "analog": true}
	var xf: Transform3D = car.global_transform
	var fwd: Vector3 = -xf.basis.z
	var base: float = car.config.rear_axle - car.config.front_axle
	var lock: float = deg_to_rad(car.config.steering.max_angle_deg)
	var front: Vector3 = car.global_position + fwd * -car.config.front_axle
	var fs: float = s + fwd.dot(st.forward_at(s)) * -car.config.front_axle
	var fd: float = (front - st.point_at(fs)).dot(st.right_at(fs))
	# the path's bend just ahead (its own curvature: the road's at its offset, plus its own turns)
	var reach := maxf(spd * PREVIEW, 2.0)
	var k := 0.0
	var cnt := 0
	var x := fs
	while x <= fs + reach:
		k += _path_k(x)
		cnt += 1
		x += 1.0
	k /= maxf(cnt, 1)
	# the way the rear axle is going: the tail's angle
	var right: Vector3 = xf.basis.x
	var rear_v: Vector3 = car.linear_velocity + car.angular_velocity.cross(xf.basis * Vector3(0.0, 0.0, car.config.rear_axle))
	var tail := 0.0
	var dir := fwd
	if spd > 4.0:
		tail = atan2(rear_v.dot(right), maxf(rear_v.dot(fwd), 0.5))
		dir = (rear_v - xf.basis.y * rear_v.dot(xf.basis.y)).normalized()
	# back parallel to the path (the road's heading turned by the path's slope across it) ...
	var slope := (target_d(fs + 2.0) - target_d(fs - 2.0)) / 4.0
	var path_yaw: float = st.heading_at(fs) + atan(slope)
	var yaw: float = atan2(dir.x, -dir.z)
	var vv := maxf(spd, 4.0)
	k += 2.0 * HOLD_DAMP * HOLD * wrapf(path_yaw - yaw, -PI, PI) / vv
	# ... and onto it
	k += HOLD * HOLD * (target_d(fs) - fd) / (vv * vv)
	# the front tyres' slip angle for that much side force (a share of their grip, the downforce's
	# included), and never more lock than the most they can turn it by: past their peak, more lock
	# only scrubs (the car understeers wider)
	var tyre: Resource = car.wheels[0].surface_tire
	var a_max: float = tyre.lateral_mu * (9.8 + 0.5 * 1.225 * car.config.downforce_area * spd * spd / maxf(car.mass, 1.0))
	var share := clampf(spd * spd * absf(k) / a_max, 0.0, 1.0)
	var peak := deg_to_rad(tyre.lateral_peak_deg)
	var slip := peak * (1.0 - sqrt(1.0 - share)) * signf(k)
	var k_max := a_max / maxf(spd * spd, 1.0)
	var geo := clampf(atan(base * k), -atan(base * k_max), atan(base * k_max))
	var steer_cmd := clampf((geo + slip + CATCH * tail) / lock, -1.0, 1.0)
	var want := want_v(fs + spd * 0.32)
	# running wide of its path in a corner: it can't make it at this speed: slower, and a little
	# slower here next lap (each corner's pace learnt as it goes: _adapt)
	var wide: float = (fd - target_d(fs)) * signf(-k) if absf(k) > 1.0 / 400.0 else 0.0     # + : out wide of the path
	if wide > 0.6:
		want *= clampf(1.0 - (wide - 0.6) * 0.05, 0.85, 1.0)
	if wide > _corner_wide:
		_corner_wide = wide
	var thr := 0.0
	var brk := 0.0
	if spd < want - 0.3 and want_v(fs + spd * 0.8) > want + 0.3:
		thr = 1.0                                      # (its speed still rising ahead: flat out, the TC catches the wheelspin)
	elif spd < want + 0.3:
		thr = clampf(0.45 + (want - spd) * 0.6, 0.0, 1.0)   # (holding a corner's speed)
	elif spd > want + 0.6:
		brk = clampf((spd - want) / 2.5, 0.08, 1.0)
	if thr > 0.0:
		# power out of a corner as the grip allows: less while the tyres are still cornering hard, off
		# while the tail's stepping out, half while it's running wide of its path
		var lat_use: float = spd * spd * absf(k) / maxf(line.grip_at(spd), 1.0)
		if lat_use > 0.8:
			thr = minf(thr, clampf((1.05 - lat_use) * 4.0, 0.25, 1.0))
		if absf(tail) > 0.07:
			thr *= clampf(1.0 - (absf(tail) - 0.07) * 9.0, 0.0, 1.0)
		if wide > 1.0:
			thr *= 0.5
	if task == "pit" and pit_phase == "in" and st.around_line(s) > box_x() - 1.0:
		brk = 1.0                                      # (at its marks)
		thr = 0.0
	var press: float = car.assist.input_for(car, steer_cmd, dt)
	return {"steer": press, "throttle": thr, "brake": brk, "handbrake": false, "analog": true}


## The path's curvature at x (1/m, + right): the line's own, or the road's at the path's d plus
## its turns across the road.
func _path_k(x: float) -> float:
	if task in ["race", "cool"] and absf(offset) < 0.5 and _mistake == 0.0 and d_lo == -INF and d_hi == INF:
		return line.k_at(x)
	var kr: float = st.curv_at(x)
	var dd := target_d(x)
	var k0 := kr / maxf(1.0 - kr * dd, 0.2)
	var d2 := (target_d(x + 3.0) - 2.0 * dd + target_d(x - 3.0)) / 9.0
	return k0 + d2


# ── moving the far car ──────────────────────────────────────────────────────

## Far from the player: along its path at the speed it would do (accelerating and braking as hard
## as its car can, as the line works out), no physics. tow: (0..1) the slipstream of a car ahead.
func far_step(dt: float, tow := 0.0, drs := false) -> void:
	if task == "hold":
		if lights_out:
			hold_t += dt
			if hold_t >= reaction:
				task = "race"
		v = 0.0
		return
	if task == "out" or (task == "pit" and pit_phase == "stop"):
		v = maxf(v - 8.0 * dt, 0.0)
		return
	var i: int = line.index(s)
	var want := want_v(s + v * 0.2) * FAR_K
	if drs and line.braking_speed(s, 120.0) >= v:
		# DRS open (race control lets it, nothing to brake for just ahead): its flap sheds ~18 % of the drag,
		# so it runs on past the line's speed (~4 %: the FIA's +10-12 km/h by a zone's end)
		want *= 1.04
		tow = maxf(tow, 0.6)
	if v < want:
		var a: float = line._accel(v, i) + tow * 0.004 * v * v
		v = minf(want, v + maxf(a, 0.5) * dt)
	else:
		v = maxf(want, v - line._decel(v, i) * dt)
	# along the centreline: the line's metre is a little more or less than the road's
	var ds_road: float = v * dt * line.step / line.ds[i] if task != "pit" else v * dt
	s += ds_road
	var td := target_d(s + 3.0)
	var nd := move_toward(d, td, (FAR_LAT + 0.05 * v) * dt)
	steer_look = clampf(atan2(nd - d, maxf(ds_road, 0.01)) * 0.5 + line.k_at(s) * 2.6, -0.5, 0.5)
	d = nd
