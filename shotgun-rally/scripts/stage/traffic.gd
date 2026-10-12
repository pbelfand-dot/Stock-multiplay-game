extends Node3D
## CUTTING UP's traffic: the registry's traffic cars (VehicleRegistry.traffic_pool:
## the generic saloon, crossover and people mover often, the premium ones now and
## then) driving a highway StageGen's lanes. Kinematic: each car is an
## AnimatableBody3D moved along the road every physics tick (the player's car
## hits them as solid things and bounces off), not a simulated car.
##
## How they drive: the Intelligent Driver Model (Treiber et al. 2000) for speed:
## each wants its own speed (the slow lanes slower) and keeps a time gap to the
## car ahead in its lane, braking smoothly as it closes; the player counts as a
## car too. Lane changes: MOBIL (Kesting, Treiber, Helbing 2007): it moves over
## when the other lane lets it go faster than it can here (by a threshold, a little
## politeness for whoever it would cut up), never if the car behind there would
## have to brake hard; then it eases across over LANE_CHANGE_T s.
##
## Only the stretch round the player is populated (BEHIND m back to AHEAD m on):
## a car that drops out of it comes back somewhere else in it, in a gap.
##
## On the LAKESHORE LOOP (a LoopGen: its s goes on round and round, no end) there's
## more: on hard and insane the traffic comes in PACKS (a block of cars across all
## the lanes, close together, at nearly one speed: threading through one is the
## game), with open road between; ONCOMING traffic on the other carriageway (seen,
## not hit: the median barrier's between); cars JOIN from the on-ramps (down the
## ramp, along the acceleration lane, merging when there's a gap: lane -1 is that
## extra lane) and some LEAVE by the off-ramps.
##
## ONLINE (a street session's cut up): the host's traffic is everyone's, as Assetto
## Corsa's traffic servers run it. The host populates the road round every player
## (others_p), its cars mind every player's car, and it sends each machine the cars
## round that machine's player NET_HZ times a second (net_peers); with a lot of cars
## (several players' stretches) each car thinks every 4th tick. Everyone else's
## Traffic is a MIRROR: it drives nothing, it plays the host's cars back (eased to
## their latest positions, dead-reckoned in between) and tells the host which one
## its player hit (it stops for everyone). The other carriageway's traffic is each
## machine's own (it's only seen). Positions along a loop are compared round it
## (_ds), so players on different laps share the traffic.

const VehicleRegistry = preload("res://scripts/game/vehicle_registry.gd")
const CarLook = preload("res://scripts/render/car_look.gd")   # the lamps glow (traffic models: glow_model)
const CarLamps = preload("res://scripts/vehicle/car_lamps.gd")

const AHEAD := 650.0
const BEHIND := 160.0
const IDM_A := 1.4              # m/s^2: how hard they speed up
const IDM_B := 2.5              # m/s^2: how hard they like to brake
const IDM_T := 1.3              # s: the time gap they keep
const IDM_S0 := 3.0             # m: bumper to bumper, stopped
const MOBIL_P := 0.3            # politeness
const MOBIL_GAIN := 0.15        # m/s^2 better before it bothers
const B_SAFE := 3.5             # m/s^2: no change that makes the car behind brake harder than this
const LANE_CHANGE_T := 3.0      # s to cross a lane
const PLAYER_HALF_LEN := 2.3
## How each kind of car drives (its registry entry's traffic "type"): speed (x its lane's), its
## time gap (s, IDM's T), how much it wants the right-hand lane (MOBIL's keep-right bias), how
## eager it is to change lanes (how often it looks; how small a gain is worth it).
const TYPES := {
	"compact": {"speed": 0.96, "gap": 1.3, "keep_right": 0.3, "eager": 1.0},
	"sedan": {"speed": 1.0, "gap": 1.3, "keep_right": 0.25, "eager": 1.0},
	"crossover": {"speed": 0.98, "gap": 1.4, "keep_right": 0.3, "eager": 0.9},
	"minivan": {"speed": 0.93, "gap": 1.6, "keep_right": 0.45, "eager": 0.7},
	"suv": {"speed": 1.01, "gap": 1.3, "keep_right": 0.2, "eager": 1.0},
	"luxury": {"speed": 1.06, "gap": 1.05, "keep_right": 0.05, "eager": 1.4},
	"van": {"speed": 0.9, "gap": 1.7, "keep_right": 0.5, "eager": 0.6}}
## What each kind weighs (kg): a hit shares the speed between the two cars by weight (shove).
const TYPE_MASS := {"compact": 1250.0, "sedan": 1500.0, "crossover": 1700.0, "minivan": 1950.0, "suv": 2200.0,
	"luxury": 2000.0, "van": 2400.0}
const PUSH_K := 2.5             # 1/s²: a shoved car steering back into its lane (a soft spring) ...
const PUSH_C := 2.6             # 1/s: ... damped (it settles in ~2 s, no swerving back past it)

var st
var diff := {}
var lanes := 4
var lane_d: Array = []          # d of each lane: lane 0 the slow (right-hand) one
var cars: Array = []            # {id, body, wheels, s, lane, to, t, d, v, v0, half_len, half_w, crashed, think}
var running := false            # (frozen on the grid: they'd all have driven off by GO)
var player := {"s": 0.0, "d": 0.0, "v": 0.0}
var _pool: Array = []           # {scene, weight, paints, half_len, half_w}
var _rng := RandomNumberGenerator.new()
var _next_id := 0
var _target := 0
var looped := false             # a LoopGen: no end to the road, oncoming traffic, ramps
var oncoming: Array = []        # {body, wheels, s, d, v} on the other carriageway (going -s)
var ramp_cars: Array = []       # {body, wheels, path, k, v, mode ("join" / "exit"), r, m}
var _joined := {}               # on-ramp -> the player's lap it last fed (one car per pass)
# online (a street session's cut up)
const NET_HZ := 10.0            # the host's traffic sent to each machine, a second
const NET_FIELDS := 7           # floats a car: id, model (pool index), paint, s (round the loop), d, v, crashed
const STAGGER_OVER := 60        # more cars than this (several players' stretches): each thinks every 4th tick
const ONCOMING_MAX := 40        # the other carriageway's (only seen): no more than this round a player
## A busy road's cost (HARD and INSANE: 60-100 cars round the player, 2.7 ms a tick before): a car
## further than POSE_NEAR m from every player is put where it is every other tick and its wheels
## don't turn (nobody sees either from there); further than THINK_FAR m it thinks every 8th tick
## (when they're staggered at all), not every 4th.
const POSE_NEAR := 160.0
const THINK_FAR := 300.0
## Cars that leave the stretch are put away and used again for the next ones (a model's scene
## instantiated and painted is the costly part: a pack of 20 at once was a hitch), up to this many.
const SPARE_MAX := 60
var others_p: Array = []        # (host) the other players: [{s, d, v}]: the traffic fills in round them and minds them
var net_peers := {}             # (host) peer id -> {s, d, v}: their player; they're sent the cars round them
var mirror := false             # (not the host) play the host's traffic back, drive none here
var hits_sent := 0              # (mirror) hits reported to the host (tests)
var _net_acc := 0.0
var _mirror := {}               # (mirror) host car id -> its car here
var _tick := 0
var _spare := {}                 # "model/solid" -> bodies put away, to use again
var _spares := 0
var _by_lane := {}              # lane -> the cars in it (or changing into it), each tick: who's ahead of whom
var _toll := false              # (a loop with a toll plaza: LoopGen.toll) its lanes fan out, kept, closed, slowed


func setup(stage, difficulty: Dictionary, seed_value: int, player_s: float) -> void:
	st = stage
	diff = difficulty
	_rng.seed = hash([seed_value, "traffic"])
	lanes = stage.HIGHWAY_LANES
	lane_d.clear()
	var edge: float = lanes * stage.LANE_W * 0.5
	for k in lanes:
		lane_d.append(edge - stage.LANE_W * (k + 0.5))       # lane 0 at the right edge
	var seen_only := OS.get_cmdline_user_args().has("--seen_cars_only")   # (screenshots: no no-AI cars)
	for e in VehicleRegistry.traffic_pool():
		var path := "res://assets/models/cars/%s/%s.glb" % [e.model, e.model]
		if not ResourceLoader.exists(path) or (seen_only and VehicleRegistry.no_ai(e.id)):
			continue
		var scene: PackedScene = load(path)
		var probe: Node3D = scene.instantiate()
		var box := _bounds(probe)
		probe.free()
		_pool.append({"id": e.id, "scene": scene, "weight": float(e.weight), "paints": e.paints,
			"half_len": box.size.z * 0.5, "half_w": box.size.x * 0.5, "height": box.size.y, "i": _pool.size(),
			"type": str(e.get("type", "sedan"))})
	_target = int(round(float(diff.get("density", 12.0)) * (AHEAD + BEHIND) / 1000.0))
	looped = stage.has_method("wrap_s")
	_toll = looped and "toll" in stage and not (stage.toll as Dictionary).is_empty()
	if _pool.is_empty():
		return
	_populate(player_s)


## The traffic for a player at player_s: packs (or a spread) ahead, the other
## carriageway's. Again (restart_at) after a jump up the road (a screenshot's).
func _populate(player_s: float) -> void:
	player.s = player_s
	if mirror:
		pass                                             # (the highway's cars are the host's: only the other carriageway here)
	elif _packs():
		# packs ahead, open road between (the first a little way up the road), and one coming up
		# from behind (its front row short of the player): it's rush hour from the start
		var s := player_s + 60.0
		while s < player_s + AHEAD:
			s = _spawn_pack(s) + _rng.randf_range(float(diff.pack_gap[0]), float(diff.pack_gap[1]))   # (the gap from its back)
		_spawn_pack(player_s - BEHIND - 20.0, player_s - 20.0)
	else:
		# the first lot: ahead of the start, spread out (none right beside the grid)
		for k in _target:
			var s: float = player_s + 70.0 + (AHEAD - 70.0) * (k + _rng.randf()) / _target
			_spawn(s)
	if looped:
		var n_on := mini(int(_target * 0.6), ONCOMING_MAX)
		for k in n_on:
			_spawn_oncoming(player_s - 150.0 + (AHEAD + 450.0) * (k + _rng.randf()) / maxf(n_on, 1))


## Does this difficulty bring its traffic in packs?
func _packs() -> bool:
	return looped and diff.has("pack")


## The d of a lane: 0 .. lanes-1, or -1 (a ramp's extra lane, right of lane 0).
func _ld(lane: int) -> float:
	return float(lane_d[0]) + st.LANE_W if lane < 0 else float(lane_d[lane])


## A lane's d where it is at s: at the toll plaza the lanes fan out (LoopGen.toll_d).
func _ldx(lane: int, s: float) -> float:
	return st.toll_d(_ld(lane), s) if _toll else _ld(lane)


## THE TOLL PLAZA (LoopGen.toll), for a car at s in a lane:
##   _toll_keep(s): no changing lanes from the approach on (the islands: a car mid-change
##     would straddle one)
##   _toll_shut(lane, s): its lane is closed at the booths (the mixed layout) and it's in the
##     stretch before them where it has to get out (from TOLL_LEAVE m before the approach)
##   _toll_wall(c): the closed gate ahead of a car still in a closed lane: {gap, v: 0} (it
##     stops short of it rather than drive through), else {gap: INF}
##   _toll_v0(c): the speed it wants there (the layout's through the booths, eased down over
##     the approach; its own elsewhere)
const TOLL_LEAVE := 500.0

func _toll_keep(s: float) -> bool:
	return _toll and st.toll_zone(s) >= 0


func _toll_ahead(s: float) -> float:
	return _ds(float(st.toll.s) - float(st.toll.half), s)   # m to the islands' start (negative: past it)


func _toll_shut(lane: int, s: float) -> bool:
	if not _toll or not st.toll_closed(lane):
		return false
	var a := _toll_ahead(s)
	return a > -float(st.toll.half) * 2.0 and a < float(st.toll.approach) + TOLL_LEAVE


func _toll_wall(c: Dictionary) -> Dictionary:
	var shut := _toll_shut(int(c.lane), float(c.s)) or _toll_shut(int(c.to), float(c.s))
	if not shut:
		return {"gap": INF, "v": 0.0}
	var a := _toll_ahead(float(c.s)) - 3.0 - float(c.half_len)
	return {"gap": maxf(a, 0.1), "v": 0.0} if a > -2.0 else {"gap": INF, "v": 0.0}


func _toll_v0(c: Dictionary) -> float:
	var v0 := float(c.v0)
	if not _toll or float(st.toll.speed) <= 0.0:
		return v0
	var a := _toll_ahead(float(c.s))
	var app := float(st.toll.approach)
	if a > app or a < -float(st.toll.half) * 2.0 - 10.0:
		return v0
	var k := clampf(1.0 - (a - 80.0) / (app - 80.0), 0.0, 1.0)   # (0 at the approach's start .. 1 from 80 m before the islands)
	return minf(v0, lerpf(v0, float(st.toll.speed), smoothstep(0.0, 1.0, k)))


## A pack at s: rows of cars across the lanes, close behind each other, at nearly one
## speed (the slowest lane's, give or take): a block to thread (no row at or past `stop`).
func _spawn_pack(s: float, stop := INF) -> float:
	var n := _rng.randi_range(int(diff.pack[0]), int(diff.pack[1]))
	var pack_v := lerpf(float(diff.speed[0]), float(diff.speed[1]), _rng.randf_range(0.15, 0.6)) / 3.6
	var row_s := s
	var placed := 0
	while placed < n and row_s < stop:
		var row: Array = _shuffled(lanes)
		var in_row := mini(_rng.randi_range(2, lanes), n - placed)
		for k in in_row:
			var c := _spawn_at(row_s + _rng.randf_range(-5.0, 5.0), int(row[k]))
			if not c.is_empty():
				c.v0 = pack_v * _rng.randf_range(0.97, 1.05) * (1.0 + 0.03 * (lanes - 1 - int(row[k])))
				c.v = c.v0 * 0.98
			placed += 1
		row_s += _rng.randf_range(11.0, 22.0)
	return row_s                                       # (where its back row is)


## Cars a km on this highway now (the tests check the density).
func count() -> int:
	return cars.size()


## Where a reset puts the player at s: the middle of the lane with the most room there
## (its nearest car, ahead or behind, furthest away), not the road's centre line, which
## on a highway runs between two lanes, often through a car (a crashed one stays put).
func clear_lane_d(s: float) -> float:
	var best := 0.0
	var room := -1.0
	for k in lanes:
		var near := 1e9
		if _toll_shut(k, s):
			continue                                         # (not into a closed lane before the booths)
		for c in cars:
			if absf(float(c.d) - _ldx(k, s)) < st.LANE_W * 0.75:
				near = minf(near, absf(float(c.s) - s) - float(c.half_len))
		if near > room:
			room = near
			best = _ldx(k, s)
	return best


func _physics_process(dt: float) -> void:
	if st == null:
		return
	_tick += 1
	if mirror:
		_mirror_tick(dt)
		if looped:
			_oncoming_traffic(dt)
		return
	if not running:
		return
	_index_lanes()
	var stagger := cars.size() > STAGGER_OVER
	for c in cars:
		var every := 1
		if stagger:
			every = 8 if _nearest(float(c.s)) > THINK_FAR else 4
		if (_tick + int(c.id)) % every == 0:
			_think(c, dt * every)
	for c in cars:
		_move(c, dt)
	for c in cars:
		_place(c, dt)
	# out of every player's stretch: back in somewhere else
	for c in cars.duplicate():
		if c.has("rival"):
			continue                                          # (the rivals come and go as Rivals says)
		if not _wanted(float(c.s)) or (not looped and float(c.s) > st.length - 40.0):
			if _packs():
				_remove(c)
			else:
				_respawn(c)
	if _packs():
		for p in _everyone():
			_refill_packs(p)
	elif not others_p.is_empty():
		_top_up()
	if looped:
		_ramp_traffic(dt)
		_oncoming_traffic(dt)
	if not net_peers.is_empty():
		_send(dt)


## How far a is along the road past b (round the loop: the short way).
func _ds(a: float, b: float) -> float:
	var x := a - b
	return wrapf(x, -st.length * 0.5, st.length * 0.5) if looped else x


## Every player the traffic is for: this machine's, then the others' (the host's, online).
func _everyone() -> Array:
	return [player] + others_p


## Is a car at s in somebody's stretch (BEHIND back to AHEAD on, give or take)?
func _wanted(s: float) -> bool:
	for p in _everyone():
		var rel := _ds(s, float(p.s))
		if rel > -BEHIND - 40.0 and rel < AHEAD + 120.0:
			return true
	return false


## The cars in each lane (or changing into it), for who's ahead of whom this tick.
func _index_lanes() -> void:
	_by_lane.clear()
	for c in cars:
		var a: int = int(c.lane)
		var b: int = int(c.to)
		if not _by_lane.has(a):
			_by_lane[a] = []
		_by_lane[a].append(c)
		if b != a:
			if not _by_lane.has(b):
				_by_lane[b] = []
			_by_lane[b].append(c)


## The car ahead in a lane (and its gap, bumper to bumper), the player included.
func _leader(lane: int, s: float, half_len: float, me = null) -> Dictionary:
	var best := {"gap": INF, "v": 0.0}
	for o in _by_lane.get(lane, cars):
		if o == me:
			continue
		if int(o.lane) != lane and int(o.to) != lane:
			continue
		var ahead := _ds(float(o.s), s)
		var gap: float = ahead - float(o.half_len) - half_len
		if ahead > 0.0 and gap < float(best.gap):
			best = {"gap": gap, "v": float(o.v)}
	for p in _everyone():
		if _player_in(lane, p):
			var ahead := _ds(float(p.s), s)
			var pg: float = ahead - PLAYER_HALF_LEN - half_len
			if ahead > 0.0 and pg < float(best.gap):
				best = {"gap": pg, "v": float(p.v)}
	return best


## The car behind in a lane (for MOBIL): {gap, v, car}.
func _follower(lane: int, s: float, half_len: float, me) -> Dictionary:
	var best := {"gap": INF, "v": 0.0, "car": null}
	for o in _by_lane.get(lane, cars):
		if o == me or (int(o.lane) != lane and int(o.to) != lane):
			continue
		var behind := _ds(s, float(o.s))
		var gap: float = behind - float(o.half_len) - half_len
		if behind > 0.0 and gap < float(best.gap):
			best = {"gap": gap, "v": float(o.v), "car": o}
	return best


## Whether a player's car (this machine's if none said) overlaps a lane (straddling the line: both).
func _player_in(lane: int, p = null) -> bool:
	var q: Dictionary = p if p != null else player
	return absf(float(q.d) - _ldx(lane, float(q.s))) < st.LANE_W * 0.5 + 0.95


func _lane_of(d: float, slack := 0.0) -> int:
	var best := -1
	var bd := INF
	for k in lanes:
		var x: float = absf(d - float(lane_d[k]))
		if x < bd:
			bd = x
			best = k
	return best if bd < st.LANE_W * 0.5 + slack else -1


## IDM: the acceleration for speed v wanting v0, gap and closing speed to the car ahead.
static func idm(v: float, v0: float, gap: float, v_lead: float, t_gap := IDM_T) -> float:
	var free := 1.0 - pow(v / maxf(v0, 0.1), 4.0)
	if gap == INF:
		return IDM_A * free
	var s_star := IDM_S0 + maxf(0.0, v * t_gap + v * (v - v_lead) / (2.0 * sqrt(IDM_A * IDM_B)))
	return IDM_A * (free - pow(s_star / maxf(gap, 0.1), 2.0))


## A car's driving for h s: its speed (IDM, behind whoever's ahead), and what it
## does next (merge, take its exit, change lanes: MOBIL). Moving it: _move.
func _think(c: Dictionary, h: float) -> void:
	if (c.has("rival") and c.rival.racing and not c.crashed) or c.crashed:
		return
	var lead := _leader(int(c.to), float(c.s), float(c.half_len), c)
	if int(c.to) != int(c.lane):                             # mid-change: mind both lanes
		var other := _leader(int(c.lane), float(c.s), float(c.half_len), c)
		if float(other.gap) < float(lead.gap):
			lead = other
	if _toll:
		var wall := _toll_wall(c)
		if float(wall.gap) < float(lead.gap):
			lead = wall
	var a := idm(float(c.v), _toll_v0(c), float(lead.gap), float(lead.v), float(c.get("gap_t", IDM_T)))
	c.v = maxf(float(c.v) + maxf(a, -9.0) * h, 0.0)
	# the acceleration lane runs out: stop at its end rather than go through the barrier
	if int(c.lane) == -1 and int(c.to) == -1 and looped and st.extra_lane(float(c.s) + 25.0) < 1.5:
		c.v = maxf(float(c.v) - 6.0 * h, 0.0)
	if int(c.to) != int(c.lane):
		pass                                                 # (crossing: _move carries it over)
	elif int(c.lane) == -1 and not c.has("exit"):
		_merge(c)                                            # joining from a ramp: into lane 0 at the first gap
	elif c.has("exit"):
		_exit_lane(c)
	elif _toll_shut(int(c.lane), float(c.s)):
		_leave_closed(c)                                     # (its lane's booth is shut: over before the plaza)
	elif _toll_keep(float(c.s)):
		pass                                                 # (the plaza's approach: lanes kept)
	else:
		c.think = float(c.think) - h * float(diff.get("lane_changes", 0.7)) * float(TYPES.get(str(c.get("type", "sedan")), TYPES.sedan).eager)
		if float(c.think) <= 0.0:
			c.think = _rng.randf_range(1.0, 3.0)
			_mobil(c, a)


## A car on along the road for dt at its speed, across the lanes if it's changing.
func _move(c: Dictionary, dt: float) -> void:
	if c.has("rival") and c.rival.racing and not c.crashed:
		_drive_racer(c, dt)
		return
	if c.crashed:
		c.v = maxf(float(c.v) - 7.0 * dt, 0.0)              # hit: it stops where it is (hazards on)
		c.s = float(c.s) + float(c.v) * dt
		return
	c.s = float(c.s) + float(c.v) * dt
	if int(c.to) != int(c.lane):
		c.t = float(c.t) + dt / float(c.get("lc_time", LANE_CHANGE_T))
		if float(c.t) >= 1.0:
			c.lane = c.to
			c.t = 0.0


func _mobil(c: Dictionary, a_here: float) -> void:
	var tp: Dictionary = TYPES.get(str(c.get("type", "sedan")), TYPES.sedan)
	var best_gain: float = MOBIL_GAIN / float(tp.eager)
	var best_lane := -1
	for to in [int(c.lane) - 1, int(c.lane) + 1]:
		if to < 0 or to >= lanes or _toll_shut(to, float(c.s)):
			continue
		var lead := _leader(to, float(c.s), float(c.half_len), c)
		var back := _follower(to, float(c.s), float(c.half_len), c)
		if float(lead.gap) < 4.0 or float(back.gap) < 4.0:
			continue                                         # no room
		var a_there := idm(float(c.v), float(c.v0), float(lead.gap), float(lead.v), float(c.get("gap_t", IDM_T)))
		var b_new := 0.0
		var b_old := 0.0
		if back.car != null:
			var bt: float = float(back.car.get("gap_t", IDM_T))
			b_old = idm(float(back.v), float(back.car.v0), INF if lead.gap == INF else float(lead.gap) + float(back.gap), float(lead.v), bt)
			b_new = idm(float(back.v), float(back.car.v0), float(back.gap), float(c.v), bt)
			if b_new < -B_SAFE:
				continue                                     # it'd make them brake hard
		var keep_right: float = float(tp.keep_right) if to < int(c.lane) else -0.1   # (keep right unless overtaking: some more than others)
		var gain: float = a_there - a_here + MOBIL_P * (b_new - b_old) + keep_right
		if gain > best_gain:
			best_gain = gain
			best_lane = to
	if best_lane >= 0:
		c.to = best_lane
		c.t = 0.0


func _place(c: Dictionary, dt: float, force := false) -> void:
	var u: float = smoothstep(0.0, 1.0, float(c.t))
	var push: float = float(c.get("push_d", 0.0))
	if push != 0.0 or float(c.get("push_v", 0.0)) != 0.0:
		# shoved sideways (shove): it slides off its line, then steers back into its lane
		# (a crashed one only slows)
		var pv: float = float(c.push_v)
		pv += ((0.0 if c.crashed else -PUSH_K * push) - PUSH_C * pv) * dt
		push += pv * dt
		if absf(push) < 0.01 and absf(pv) < 0.01 and not c.crashed:
			push = 0.0
			pv = 0.0
		c.push_d = push
		c.push_v = pv
	c.d = lerpf(_ldx(int(c.lane), float(c.s)), _ldx(int(c.to), float(c.s)), u) + push
	var near := _nearest(float(c.s)) < POSE_NEAR
	if near or force or (_tick + int(c.id)) % 2 == 0:
		_pose(c, dt, u, near)


## A car's body where it is (c.s, c.d), turned along the road (and toward the lane
## it's crossing to, u of the way), its wheels rolling.
func _pose(c: Dictionary, dt: float, u := 0.0, wheels := true) -> void:
	var s: float = float(c.s) if looped else clampf(float(c.s), 1.0, st.length - 1.0)
	var p: Vector3 = st.world_at(s, float(c.d))
	var d_ahead: float = c.d
	if _toll and st.toll_spread(s) != st.toll_spread(s + 2.0):
		d_ahead = lerpf(_ldx(int(c.lane), s + 2.0), _ldx(int(c.to), s + 2.0), u)   # (drifting out or in with the lanes)
	var ahead: Vector3 = st.world_at(s + 2.0 if looped else minf(s + 2.0, st.length - 0.5), d_ahead)
	var fwd: Vector3 = (ahead - p).normalized()
	if int(c.to) != int(c.lane):                             # (turned a little toward the lane it's going to)
		var r: Vector3 = st.right_at(s)
		var side := signf(_ld(int(c.to)) - _ld(int(c.lane)))
		fwd = (fwd + r * side * 0.06 * sin(u * PI)).normalized()
	var basis := Basis.looking_at(fwd, st.up_at(s) if looped else Vector3.UP)
	(c.body as AnimatableBody3D).global_transform = Transform3D(basis, p)
	if not wheels:
		return
	var spin := float(c.v) * dt / 0.33
	for w in c.wheels:
		(w as Node3D).rotate_object_local(Vector3.RIGHT, -spin)


## How far s is from the nearest player along the road (m, either way).
func _nearest(s: float) -> float:
	var best := absf(_ds(s, float(player.s)))
	for q in others_p:
		best = minf(best, absf(_ds(s, float(q.s))))
	return best


func _pick_model() -> Dictionary:
	var sum := 0.0
	for m in _pool:
		sum += float(m.weight)
	var x := _rng.randf() * sum
	for m in _pool:
		x -= float(m.weight)
		if x <= 0.0:
			return m
	return _pool[-1]


## A new car at s, in a lane with room (none: not spawned).
func _spawn(s: float) -> void:
	var m := _pick_model()
	var lane := _free_lane(s, float(m.half_len))
	if lane < 0:
		return
	_spawn_at(s, lane, m)


## A new car at s in a lane (m: its model, else one picked): the car, or {} if there's
## no room there.
func _spawn_at(s: float, lane: int, m := {}) -> Dictionary:
	if m.is_empty():
		m = _pick_model()
	if _toll and (_toll_shut(lane, s) or absf(_ds(s, float(st.toll.s))) < float(st.toll.half) + 25.0):
		return {}                                            # (none appear among the booths, or in a lane closed ahead)
	for o in cars:
		if (int(o.lane) == lane or int(o.to) == lane) and absf(_ds(float(o.s), s)) < float(o.half_len) + float(m.half_len) + 6.0:
			return {}
	var body := _body_for(m)
	var wheels: Array = body.get_meta("wheels")
	var tp: Dictionary = TYPES.get(str(m.get("type", "sedan")), TYPES.sedan)
	var v_cap: float = float(diff.get("speed", [80.0, 120.0])[1]) / 3.6 * 1.03
	var v0: float = minf(_lane_speed(maxi(lane, 0)) * float(tp.speed), v_cap)
	var c := {"id": _next_id, "model": m.id, "body": body, "wheels": wheels, "s": s, "lane": lane, "to": lane, "t": 0.0,
		"type": str(m.get("type", "sedan")), "gap_t": float(tp.gap) * float(diff.get("gap_k", 1.0)),
		"d": _ldx(lane, s), "v": v0 * _rng.randf_range(0.9, 1.0), "v0": v0, "half_len": float(m.half_len),
		"half_w": float(m.half_w), "crashed": false, "think": _rng.randf_range(0.5, 3.0), "m": m,
		"paint": int(body.get_meta("paint", 0))}
	_next_id += 1
	cars.append(c)
	_place(c, 0.0, true)
	body.reset_physics_interpolation()                     # (a body used again: not streaking in from where it was)
	return c


## A traffic car's body: the model, painted, in a kinematic box the player hits.
func _body_for(m: Dictionary, solid := true, paint := -1) -> Node3D:
	var key := "%s/%d" % [m.id, int(solid)]
	if paint < 0 and not (_spare.get(key, []) as Array).is_empty():
		var again: Node3D = _spare[key].pop_back()
		_spares -= 1
		again.visible = true
		again.process_mode = Node.PROCESS_MODE_INHERIT
		return again
	var body: Node3D = AnimatableBody3D.new() if solid else Node3D.new()
	body.name = "Traffic%d" % _next_id
	if solid:
		(body as AnimatableBody3D).sync_to_physics = true
		body.set_meta("surface", "gravel")
		body.set_meta("traffic", true)
	var model: Node3D = m.scene.instantiate()
	body.add_child(model)
	if solid:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(m.half_w) * 2.0, float(m.height) * 0.85, float(m.half_len) * 2.0)
		cs.shape = box
		cs.position = Vector3(0, float(m.height) * 0.5, 0)
		body.add_child(cs)
	add_child(body)
	var pi: int = paint if paint >= 0 else _rng.randi() % m.paints.size()
	_paint(model, m.paints[pi % m.paints.size()])
	body.set_meta("paint", pi)
	body.set_meta("model_id", str(m.id))             # (the replay: what it looked like, to stand in for it once it's gone)
	CarLook.glow_model(model)                        # (its lamps: running lights by day, full at night)
	CarLamps.road_glow(model)                        # (at night: its headlights' light on the road, the red behind)
	var wheels: Array = []
	for n in model.find_children("Wheel_*", "Node3D", true, false):
		wheels.append(n)
	body.set_meta("wheels", wheels)
	return body


## A look-alike of a traffic car that's gone (freed: the ramps' cars, a rival once its challenge
## is over, online the host's cars leaving our stretch, the rest once SPARE_MAX are kept): the
## replay's stand-in for it, its model in its paint, out of the physics. Null if the model isn't
## in this road's pool.
func replay_body(model_id: String, paint: int) -> Node3D:
	for m in _pool:
		if str(m.id) == model_id:
			var b := _body_for(m, false, maxi(paint, 0))
			b.set_meta("replay_standin", true)
			return b
	return null


## Start again with the player at s: every car gone, new traffic round s.
func restart_at(s: float) -> void:
	for c in cars.duplicate():
		if not c.has("rival"):
			_remove(c)
	for o in oncoming:
		(o.body as Node).queue_free()
	oncoming.clear()
	for r in ramp_cars:
		(r.body as Node).queue_free()
	ramp_cars.clear()
	if not _pool.is_empty():
		_populate(s)


func _remove(c: Dictionary) -> void:
	cars.erase(c)
	_put_away(c.body, "%s/1" % c.model, not mirror and not c.has("rival"))


## A car's body off the road: hidden, out of the physics, kept to be used again (or freed: a
## rival's has its name tag; online mirrors' are the host's paint; enough are kept already).
func _put_away(body: Node, key: String, keep := true) -> void:
	if not is_instance_valid(body):
		return
	if not keep or _spares >= SPARE_MAX:
		body.queue_free()
		return
	(body as Node3D).visible = false
	body.process_mode = Node.PROCESS_MODE_DISABLED     # (a disabled body leaves the physics space)
	if not _spare.has(key):
		_spare[key] = []
	_spare[key].append(body)
	_spares += 1


func _respawn(c: Dictionary) -> void:
	_remove(c)
	# round whichever player it was nearest (online: anyone's stretch)
	var p: Dictionary = player
	for q in others_p:
		if absf(_ds(float(c.s), float(q.s))) < absf(_ds(float(c.s), float(p.s))):
			p = q
	# faster than the traffic: new cars appear ahead; slower: they come up from behind
	var ahead: bool = float(p.v) > float(diff.speed[0]) / 3.6 * 0.8
	var s: float = float(p.s) + (_rng.randf_range(AHEAD * 0.75, AHEAD) if ahead else -_rng.randf_range(BEHIND * 0.7, BEHIND))
	if looped or (s > st.START_S + 20.0 and s < st.length - 80.0):
		_spawn(s)


## 0..n-1 in a random order, from the traffic's own seeded dice (Array.shuffle() uses
## the global ones: the same seed wouldn't give the same traffic).
func _shuffled(n: int) -> Array:
	var a: Array = range(n)
	for i in range(n - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
	return a


func _free_lane(s: float, half_len: float) -> int:
	var order: Array = _shuffled(lanes)
	for lane in order:
		var ok := not _toll_shut(lane, s)
		for o in cars:
			if (int(o.lane) == lane or int(o.to) == lane) and absf(_ds(float(o.s), s)) < float(o.half_len) + half_len + 12.0:
				ok = false
				break
		for p in _everyone():
			if ok and absf(_ds(float(p.s), s)) < 30.0 and _player_in(lane, p):
				ok = false
		if ok:
			return lane
	return -1


func _lane_speed(lane: int) -> float:
	var sp: Array = diff.get("speed", [80.0, 120.0])
	return lerpf(float(sp[0]), float(sp[1]), (lane + _rng.randf()) / lanes) / 3.6   # (lane 0, the right-hand one, slowest)


## The player ran into this car: the two share the hit by weight, as two real cars do.
## The physics bounced the player off the car as off a wall (its body is kinematic),
## sometimes over two ticks, so the hit is worked out again here as a crash between the
## two weights: along the push (the way the wall bounced the player: dv_wall, its velocity
## after - before), both end at their shared speed (a crash, not a bounce), from the
## player's velocity before it (v_player) and the car's. The car gets its side of it (along
## the road: its speed; across: a shove off its line that it steers back from); "back" is
## what to hand the player back, "share" the part of the wall's hit the player really took.
## On a guest's machine the host's car takes it (net_shove).
func shove(body: Node, dv_wall: Vector3, v_player: Vector3, m_player: float, v_now: Vector3) -> Dictionary:
	if dv_wall.length() < 0.01:
		return {}
	for c in cars:
		if c.body != body:
			continue
		var m_car: float = float(TYPE_MASS.get(str(c.get("type", "sedan")), 1500.0))
		var s: float = float(c.s) if looped else clampf(float(c.s), 1.0, st.length - 1.0)
		var fwd: Vector3 = st.forward_at(s)
		var right: Vector3 = st.right_at(s)
		var v_car: Vector3 = fwd * float(c.v) + right * float(c.get("push_v", 0.0))
		var n: Vector3 = dv_wall.normalized()               # (the push: from the car toward the player)
		var shared: float = (m_player * v_player.dot(n) + m_car * v_car.dot(n)) / (m_player + m_car)
		var dv_car: Vector3 = n * (shared - v_car.dot(n))
		_push(c, dv_car.dot(fwd), dv_car.dot(right))
		if mirror and multiplayer.has_multiplayer_peer():
			net_shove.rpc_id(1, int(c.id), dv_car.dot(fwd), dv_car.dot(right))
		var took: float = absf(shared - v_player.dot(n))    # (the player's real speed change)
		return {"car": c, "back": n * (shared - v_now.dot(n)), "share": clampf(took / dv_wall.length(), 0.0, 1.0)}
	return {}


func _push(c: Dictionary, along: float, across: float) -> void:
	c.v = maxf(float(c.v) + along, 0.0)
	c.push_v = float(c.get("push_v", 0.0)) + across
	c.push_d = float(c.get("push_d", 0.0))


## (host) A machine's player shoved one of our cars.
@rpc("any_peer", "reliable")
func net_shove(id: int, along: float, across: float) -> void:
	if mirror:
		return
	for c in cars:
		if int(c.id) == id:
			_push(c, along, across)
			return


## The player hit this car hard (a crash): it stops (and the score knows).
func hit(body: Node) -> Dictionary:
	for c in cars:
		if c.body == body:
			c.crashed = true
			if mirror and multiplayer.has_multiplayer_peer():
				net_hit.rpc_id(1, int(c.id))             # (the host's car: it stops for everyone)
				hits_sent += 1
			return c
	return {}


# ── online: the host's traffic for everyone ───────────────────────────────

## (host) Each machine its player's stretch of the traffic, NET_HZ times a second:
## [id, model, paint, s round the loop, d, v, crashed] a car.
func _send(dt: float) -> void:
	_net_acc += dt
	if _net_acc < 1.0 / NET_HZ:
		return
	_net_acc = 0.0
	for peer in net_peers:
		var p: Dictionary = net_peers[peer]
		var data := PackedFloat32Array()
		for c in cars:
			if c.has("rival"):
				continue
			var rel := _ds(float(c.s), float(p.s))
			if rel < -BEHIND - 80.0 or rel > AHEAD + 160.0:
				continue
			data.append_array([float(c.id), float(c.m.get("i", 0)), float(c.get("paint", 0)),
				fposmod(float(c.s), st.length) if looped else float(c.s), float(c.d), float(c.v), 1.0 if c.crashed else 0.0])
		net_traffic.rpc_id(int(peer), data)


## (mirror) The host's cars round our player: new ones built, known ones eased
## toward where they are, the ones that left our stretch gone.
@rpc("authority", "unreliable_ordered")
func net_traffic(data: PackedFloat32Array) -> void:
	if not mirror or _pool.is_empty():
		return
	var seen := {}
	for i in range(0, data.size() - NET_FIELDS + 1, NET_FIELDS):
		var id := int(data[i])
		seen[id] = true
		var s: float = float(player.s) + _ds(data[i + 3], float(player.s))    # (into our own count of laps)
		var c: Dictionary = _mirror.get(id, {})
		if c.is_empty():
			var m: Dictionary = _pool[clampi(int(data[i + 1]), 0, _pool.size() - 1)]
			var body := _body_for(m, true, int(data[i + 2]))
			c = {"id": id, "model": m.id, "body": body, "wheels": body.get_meta("wheels"), "s": s, "d": data[i + 4],
				"v": data[i + 5], "lane": 0, "to": 0, "t": 0.0, "half_len": float(m.half_len), "half_w": float(m.half_w),
				"crashed": false, "m": m, "ts": s, "td": data[i + 4]}
			_mirror[id] = c
			cars.append(c)
		c.ts = s
		c.td = data[i + 4]
		c.v = data[i + 5]
		if data[i + 6] > 0.5:
			c.crashed = true
	for id in _mirror.keys():
		if not seen.has(id):
			var gone: Dictionary = _mirror[id]
			_mirror.erase(id)
			_remove(gone)


## (mirror) Between the host's packets: each car on at its speed, eased onto where the
## host last had it (also carried on at its speed), then posed on the road.
func _mirror_tick(dt: float) -> void:
	var k := 1.0 - exp(-dt * 6.0)
	for c in cars:
		if not c.has("ts"):
			continue
		c.ts = float(c.ts) + float(c.v) * dt
		c.s = lerpf(float(c.s) + float(c.v) * dt, float(c.ts), k)
		c.d = lerpf(float(c.d), float(c.td), k)
		_pose(c, dt)


## (host) A machine's player hit one of our cars: it stops, for everyone.
@rpc("any_peer", "reliable")
func net_hit(id: int) -> void:
	if mirror:
		return
	for c in cars:
		if int(c.id) == id:
			c.crashed = true
			return


## What the score needs: [{id, s, d, v, half_len, half_w}].
func snapshot() -> Array:
	var out: Array = []
	for c in cars:
		out.append({"id": c.id, "s": c.s, "d": c.d, "v": c.v, "half_len": c.half_len, "half_w": c.half_w})
	return out


func _paint(model: Node, paint) -> void:
	var col: Color = paint if paint is Color else Color(float(paint[0]), float(paint[1]), float(paint[2]))
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if mat and mat.resource_name == "paint" and mat is StandardMaterial3D:
				var m2: StandardMaterial3D = mat.duplicate()
				m2.albedo_color = col
				(mi as MeshInstance3D).set_surface_override_material(i, m2)


static func _bounds(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		var xf: Transform3D = (mi as Node3D).transform
		var p: Node = mi.get_parent()
		while p != null and p is Node3D:                    # (up to and including the model's root: its scale too)
			xf = (p as Node3D).transform * xf
			if p == n:
				break
			p = p.get_parent()
		b = xf * b
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


# ── the loop's packs, ramps and oncoming traffic ─────────────────────────

## Packs: a new one up the road once the last one's well inside the stretch (or
## behind, for a player slower than the traffic), while there's room for one.
func _refill_packs(p: Dictionary) -> void:
	var far := -INF
	var near := INF
	var n := 0
	for c in cars:
		var rel := _ds(float(c.s), float(p.s))
		if rel < -BEHIND - 40.0 or rel > AHEAD + 120.0:
			continue                                         # (someone else's stretch)
		n += 1
		far = maxf(far, rel)
		near = minf(near, rel)
	if n + int(diff.pack[0]) > int(_target * 1.3):
		return
	var gap := _rng.randf_range(float(diff.pack_gap[0]), float(diff.pack_gap[1]))
	if n == 0:
		far = 140.0 - gap                                    # (a stretch with nobody's traffic yet: a pack a little way on)
	if far < AHEAD - gap:
		_spawn_pack(float(p.s) + maxf(far + gap, AHEAD * 0.7 if n > 0 else 140.0))
	elif float(p.v) < float(diff.speed[0]) / 3.6 * 0.8 and near > -BEHIND + gap:
		_spawn_pack(float(p.s) - BEHIND)


## (online, not in packs) Each other player's stretch filled to the difficulty's count:
## one car a tick into a gap up the road.
func _top_up() -> void:
	for p in others_p:
		var n := 0
		for c in cars:
			var rel := _ds(float(c.s), float(p.s))
			if rel > -BEHIND and rel < AHEAD:
				n += 1
		if n < _target:
			_spawn(float(p.s) + _rng.randf_range(80.0, AHEAD))


## Out of a lane closed at the toll plaza: into the next one over at the first gap (smaller
## gaps as the gate gets nearer: it has to go; _toll_wall stops it short of the gate if not).
func _leave_closed(c: Dictionary) -> void:
	var near := clampf(_toll_ahead(float(c.s)) / (float(st.toll.approach) + TOLL_LEAVE), 0.0, 1.0)
	for to in [int(c.lane) + 1, int(c.lane) - 1]:
		if to < 0 or to >= lanes or st.toll_closed(to):
			continue
		var lead := _leader(to, float(c.s), float(c.half_len), c)
		var back := _follower(to, float(c.s), float(c.half_len), c)
		if float(lead.gap) > lerpf(3.0, 8.0, near) and float(back.gap) > lerpf(3.0, 10.0, near):
			c.to = to
			c.t = 0.0
			return


## Joining from a ramp's acceleration lane: into lane 0 when there's a gap (a smaller
## one than a lane change would take: it has to go before the lane ends).
func _merge(c: Dictionary) -> void:
	var lead := _leader(0, float(c.s), float(c.half_len), c)
	var back := _follower(0, float(c.s), float(c.half_len), c)
	if float(lead.gap) > 5.0 and float(back.gap) > 6.0:
		c.to = 0
		c.t = 0.0


## A car taking the next exit: over into the deceleration lane when it's there and
## there's room; at the gore it leaves the highway down the ramp.
func _exit_lane(c: Dictionary) -> void:
	var r: Dictionary = c.exit
	var ds: float = st.gore_ds(float(c.s), float(r.s))
	if int(c.lane) == 0 and ds > -float(r.len) + 50.0 and ds < -15.0:
		var back := _follower(-1, float(c.s), float(c.half_len), c)
		if float(back.gap) > 5.0:
			c.to = -1
			c.t = 0.0
	elif ds > 30.0:
		c.erase("exit")                                       # (missed it: carries on)


func _ramp_traffic(dt: float) -> void:
	var lap := floori(float(player.s) / st.length)
	for r in st.ramps:
		if r.side != "right":
			continue
		var ahead: float = st.gore_ds(float(r.s), float(player.s))
		if r.kind == "on" and ahead > 200.0 and ahead < 700.0 and _joined.get(r.s, -1) != lap:
			# a car coming down the ramp, timed to reach the gore about when the player does
			_joined[r.s] = lap
			var m := _pick_model()
			var path: Dictionary = st.ramp_path(r)
			var v := _rng.randf_range(19.0, 25.0)
			var k := minf(float(path.len), v * ahead / maxf(float(player.v), 15.0))
			var body := _body_for(m)
			ramp_cars.append({"body": body, "wheels": body.get_meta("wheels"), "path": path, "k": k, "v": v, "mode": "join", "r": r, "m": m})
		elif r.kind == "off" and ahead > 150.0 and ahead < 500.0:
			# now and then a car in the slow lane takes this exit
			for c in cars:
				if int(c.lane) == 0 and not c.has("exit") and not c.crashed and _rng.randf() < 0.001:
					var ds: float = st.gore_ds(float(c.s), float(r.s))
					if ds > -float(r.len) - 200.0 and ds < -float(r.len) + 40.0:
						c.exit = r
	# cars on a ramp's own road: along its path
	for rc in ramp_cars.duplicate():
		var path: Dictionary = rc.path
		if rc.mode == "join":
			rc.k = float(rc.k) - float(rc.v) * dt
			if float(rc.k) <= 0.0:
				# at the gore: on the highway now, in the acceleration lane
				ramp_cars.erase(rc)
				var c := {"id": _next_id, "model": rc.m.id, "body": rc.body, "wheels": rc.wheels, "s": float(player.s) + st.gore_ds(float(rc.r.s), float(player.s)),
					"lane": -1, "to": -1, "t": 0.0, "d": _ld(-1), "v": float(rc.v), "v0": _lane_speed(0) * 1.05,
					"half_len": float(rc.m.half_len), "half_w": float(rc.m.half_w), "crashed": false, "think": 1.0, "m": rc.m}
				_next_id += 1
				cars.append(c)
				continue
		else:
			rc.k = float(rc.k) + float(rc.v) * dt
			rc.v = maxf(float(rc.v) - 2.0 * dt, 14.0)
			if float(rc.k) >= float(path.len) - 8.0:
				ramp_cars.erase(rc)
				(rc.body as Node).queue_free()
				continue
		_place_on_path(rc, dt)
	# cars that reached the gore of their exit go onto its ramp
	for c in cars.duplicate():
		if c.has("exit") and int(c.lane) == -1 and st.gore_ds(float(c.s), float(c.exit.s)) >= 0.0:
			cars.erase(c)
			ramp_cars.append({"body": c.body, "wheels": c.wheels, "path": st.ramp_path(c.exit), "k": 0.0, "v": float(c.v), "mode": "exit", "r": c.exit, "m": c.m})


func _place_on_path(rc: Dictionary, dt: float) -> void:
	var path: Dictionary = rc.path
	var pts: PackedVector3Array = path.pts
	var f := clampf(float(rc.k) / 4.0, 0.0, pts.size() - 1.001)
	var i := int(f)
	var p := pts[i].lerp(pts[i + 1], f - i)
	var dir := (pts[i + 1] - pts[i]).normalized()
	if rc.mode == "join":
		dir = -dir                                            # (it drives the path backwards, towards the gore)
	(rc.body as Node3D).global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), p)
	var spin := float(rc.v) * dt / 0.33
	for w in rc.wheels:
		(w as Node3D).rotate_object_local(Vector3.RIGHT, -spin)


## The other carriageway: cars the other way round the loop, steady speeds, keeping to
## their lanes (seen across the barrier); back in up the road once they've passed.
func _spawn_oncoming(s: float) -> void:
	var m := _pick_model()
	var lane := _rng.randi() % lanes
	if _toll and st.toll_closed(lane):
		# (their closed lane's booth: a car that'd drive through the plaza takes the next lane)
		var toll_rel := _ds(float(st.toll.s), float(player.s))
		var spawn_rel := _ds(s, float(player.s))
		if toll_rel > -220.0 and toll_rel < spawn_rel + float(st.toll.half):
			lane = (lane + 1) % lanes
	for o in oncoming:
		if int(o.lane) == lane and absf(float(o.s) - s) < 26.0:
			return
	var body := _body_for(m, false)
	var sp: Array = diff.get("speed", [80.0, 120.0])
	var v := lerpf(float(sp[0]), float(sp[1]), (lane + _rng.randf()) / lanes) / 3.6
	# their lane 0, the slow one, is on their right: our far left
	var d: float = st.ONCOMING_D - (st.EDGE - st.LANE_W * (lane + 0.5))
	var o := {"body": body, "wheels": body.get_meta("wheels"), "s": s, "d": d, "v": v, "lane": lane, "model": m.id}
	oncoming.append(o)
	_pose_oncoming(o)
	body.reset_physics_interpolation()


func _oncoming_traffic(dt: float) -> void:
	for o in oncoming.duplicate():
		o.s = float(o.s) - float(o.v) * dt
		if float(o.s) < float(player.s) - 220.0:
			oncoming.erase(o)
			_put_away(o.body, "%s/0" % o.get("model", ""), o.has("model"))
			_spawn_oncoming(float(player.s) + AHEAD + _rng.randf_range(0.0, 350.0))
			continue
		var s: float = o.s
		var near := absf(_ds(s, float(player.s))) < POSE_NEAR
		if not near and (_tick + int(o.lane)) % 2 != 0:
			continue                                         # (far off: every other tick, as the highway's)
		_pose_oncoming(o)
		if not near:
			continue
		var spin := float(o.v) * dt / 0.33
		for w in o.wheels:
			(w as Node3D).rotate_object_local(Vector3.RIGHT, -spin)


## An oncoming car's body where it is (on the other carriageway, heading back down the road).
func _pose_oncoming(o: Dictionary) -> void:
	var s: float = o.s
	var od: float = o.d
	var p: Vector3 = st.world_at(s, st.toll_d(od, s) if _toll else od)
	var back: Vector3 = st.world_at(s - 2.0, st.toll_d(od, s - 2.0) if _toll else od)
	(o.body as Node3D).global_transform = Transform3D(Basis.looking_at((back - p).normalized(), st.up_at(s)), p)


# ── rivals (Rivals: the highway battles) ──────────────────────────────────

## A rival in the traffic at s in a lane: a garage car (entry: its registry entry),
## cruising with the traffic until a race; level 1..5 (how fast, how bold).
## Returns its car (with .rival), or {} if there's no room there.
func add_rival(s: float, lane: int, entry: Dictionary, level: int, nick: String) -> Dictionary:
	var path := "res://assets/models/cars/%s/%s.glb" % [entry.model, entry.model]
	if not ResourceLoader.exists(path):
		return {}
	var scene: PackedScene = load(path)
	var probe: Node3D = scene.instantiate()
	var box := _bounds(probe)
	probe.free()
	var cols: Array = entry.get("garage", {}).get("colours", [[0.8, 0.1, 0.1]])
	var m := {"id": entry.id, "scene": scene, "weight": 0.0, "paints": [cols[0]],
		"half_len": box.size.z * 0.5, "half_w": box.size.x * 0.5, "height": box.size.y}
	var c := _spawn_at(s, lane, m)
	if c.is_empty():
		return {}
	var specs: Dictionary = entry.get("specs", {})
	var hp := float(specs.get("power_hp", 400.0))
	var kg := float(specs.get("weight_kg", entry.get("physics", {}).get("mass", 1500.0)))
	var top := minf(float(specs.get("top_speed_kmh", 280.0)), 330.0) * (0.84 + 0.04 * level) / 3.6
	var pw := hp * 745.7 / maxf(kg, 600.0)                 # W/kg
	c.rival = {"name": entry.name, "nick": nick, "level": level, "racing": false, "pw": pw, "top_v": top,
		"drag": pw / pow(top, 3.0), "think": 0.0}           # (top speed where power meets drag)
	c.v0 = _rng.randf_range(112.0, 128.0) / 3.6              # cruising: a little under the player's pace
	c.v = c.v0
	c.lc_time = 1.0
	var tag := Label3D.new()
	tag.name = "RivalTag"
	tag.text = "%s\n%s" % [nick, entry.name]
	tag.font_size = 64
	tag.pixel_size = 0.01
	tag.outline_size = 12
	tag.modulate = Color(1.0, 0.82, 0.2)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.position = Vector3(0, float(m.height) + 1.4, 0)
	tag.visibility_range_end = 420.0
	(c.body as Node3D).add_child(tag)
	return c


func remove_rival(c: Dictionary) -> void:
	if cars.has(c):
		_remove(c)


## A rival racing: flat out up to what its car can do (power against drag), close
## behind whatever's ahead (a short time gap), and through the traffic: when it's held
## up it looks at the lanes either side and takes the one with the most open road, if
## there's room beside it, fast (a second to cross).
func _drive_racer(c: Dictionary, dt: float) -> void:
	var r: Dictionary = c.rival
	var v: float = c.v
	var a_max: float = minf(6.0, float(r.pw) / maxf(v, 6.0)) - float(r.drag) * v * v
	var lead := _leader(int(c.to), float(c.s), float(c.half_len), c)
	if int(c.to) != int(c.lane):
		var other := _leader(int(c.lane), float(c.s), float(c.half_len), c)
		if float(other.gap) < float(lead.gap):
			lead = other
	if _toll:
		var wall := _toll_wall(c)
		if float(wall.gap) < float(lead.gap):
			lead = wall
	var a := a_max
	if float(lead.gap) < INF:
		var s_star := 2.5 + maxf(0.0, v * 0.45 + v * (v - float(lead.v)) / (2.0 * sqrt(5.0 * 8.0)))
		a = minf(a, 5.0 * (1.0 - pow(s_star / maxf(float(lead.gap), 0.1), 2.0)))
	c.v = clampf(v + clampf(a, -10.0, 6.0) * dt, 0.0, float(r.top_v))
	c.s = float(c.s) + float(c.v) * dt
	if int(c.to) != int(c.lane):
		c.t = float(c.t) + dt / float(c.get("lc_time", 1.0))
		if float(c.t) >= 1.0:
			c.lane = c.to
			c.t = 0.0
		return
	r.think = float(r.think) - dt
	if _toll_keep(float(c.s)) and not _toll_shut(int(c.lane), float(c.s)):
		return                                               # (the plaza's approach: in its lane through the booths)
	if _toll_shut(int(c.lane), float(c.s)):
		_leave_closed(c)
		return
	# held up: the car ahead is slower than it wants to go (not slower than it's going:
	# once it's matched that car's speed it would never look for a way past again)
	if r.think > 0.0 or float(lead.gap) > 140.0 or float(lead.v) > float(r.top_v) - 3.0:
		return
	r.think = maxf(0.12, 0.45 - 0.06 * int(r.level))       # (the better ones see a gap sooner)
	var here := _lane_room(lead)
	var best := -1
	var best_free := here + 6.0
	for to in [int(c.lane) - 1, int(c.lane) + 1]:
		if not _racer_can_enter(c, to):
			continue
		var free := _lane_room(_leader(to, float(c.s), float(c.half_len), c))
		# (a lane is worth crossing for the open one beyond it, too)
		var far: int = to + (to - int(c.lane))
		if far >= 0 and far < lanes:
			free = maxf(free, _lane_room(_leader(far, float(c.s), float(c.half_len), c)) - 15.0)
		if free > best_free:
			best_free = free
			best = to
	if best >= 0:
		c.to = best
		c.t = 0.0


## How much a lane's leader lets a racer get on: the gap to it, plus what its speed
## opens (or closes) over the next few seconds.
func _lane_room(lead: Dictionary) -> float:
	if float(lead.gap) >= INF:
		return 1000.0
	return float(lead.gap) + float(lead.v) * 3.0


## A racer can move into lane `to` now: room ahead (enough to brake for a slower car there)
## and behind, nothing closing fast from behind, the player not alongside.
func _racer_can_enter(c: Dictionary, to: int) -> bool:
	if to < 0 or to >= lanes or _toll_shut(to, float(c.s)):
		return false
	var ahead := _leader(to, float(c.s), float(c.half_len), c)
	var back := _follower(to, float(c.s), float(c.half_len), c)
	# (room ahead to stop in if it's slower there: the closing speed's braking distance at 8 m/s^2)
	var closing := maxf(float(c.v) - float(ahead.v), 0.0) if float(ahead.gap) < INF else 0.0
	if float(back.gap) < 3.0 or float(ahead.gap) < maxf(6.0, closing * closing / 16.0 + 4.0):
		return false
	if back.car != null and float(back.v) - float(c.v) > 6.0 and float(back.gap) < 25.0:
		return false
	if _player_in(to) and absf(float(player.s) - float(c.s)) < PLAYER_HALF_LEN + float(c.half_len) + 2.0:
		return false                                         # (the player's alongside there)
	return true
