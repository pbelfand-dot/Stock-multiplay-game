extends Node
## REPLAY (docs/replay.md): the run recorded as it's driven, and played back with proper
## cameras, from the results (the REPLAY button, V / X) or the pause menu (REPLAY: an instant
## replay of the last 30 s, scrubbable back to the start). Every mode: rally stages, the
## touge, cut up, Track Mode.
##
## RECORDING (every physics tick while the run's on: the countdown and the stage): each car the
## game lists (Game.replay_targets(): yours, the other drivers' online, any RaceField's AI cars)
## is sampled RATE times a second into its own Track (keyed by its path under the Game, so any
## RallyCar can be added): where it is and how it's turned, its velocity, the steering, the revs
## and the gear, each spring's squash and each wheel's spin, the throttle, the brake, the
## handbrake, the slide and the surface (26 floats, 104 bytes a sample). Cut up's traffic, the
## touge's stray car and its ghost (props: where each is, how it's turned) every PROP_EVERY-th
## sample. Each track is a ring holding the last KEEP_S s (10 minutes); memory_bytes() measures
## it (docs/replay.md has the numbers).
##
## PLAYBACK holds the live game. Alone: the whole scene tree is paused (the physics, the traffic,
## the clock, the co-driver mid-sentence); the cars and the moving things are captured first,
## posed from the recording (RallyCar.replay_pose: the wheels roll, steer and ride their springs,
## the brake lights, the engine's sound, the dust), and put back exactly as they were when it
## ends (transform, velocities, wheel spin, springs, steering; the drivetrain and tyres are never
## touched), so the game carries on where it was: the results, or paused. Online it's local
## only: the session can't stop for you, so your car waits on the brake as in the pause menu,
## still simulated and streamed, the others' streams keep coming in; the poses are laid over the
## live scene each frame and taken off again before every physics tick (nothing posed is ever
## seen by the simulation or sent to anyone).
##
## CONTROLS (keyboard and mouse / controller; Controls registers them): play / pause, rewind and
## fast-forward (held) or a 5 s step (tapped), the speed (0.25x to 4x), the timeline (click or
## drag), the start and the end, the next / previous car, the camera (replay_cam.gd: chase,
## cockpit, hood, bumper, wheel, side, front, the FPV drone, the helicopter, trackside TV, free
## follow, the free cam, placed cameras and the director), place a camera, the bar on / off, out.

const ReplayCam = preload("res://scripts/vehicle/replay_cam.gd")
const ReplayBar = preload("res://scripts/ui/replay_bar.gd")
const SkidMarks = preload("res://scripts/vehicle/skid_marks.gd")
const DriftFx = preload("res://scripts/vehicle/drift_fx.gd")

signal tick_recorded(t: float)       # (tests) each tick recorded: its time on the recording's clock (s)
signal opened
signal closed

const RATE := 60.0                   # samples a second, each car (between them: interpolated)
const PROP_EVERY := 4                # the traffic, the stray car, the ghost: every 4th sample (15 a second)
const KEEP_S := 600.0                # the last 10 minutes are kept
const STRIDE := 26                   # floats a car sample
const PROP_STRIDE := 8               # floats a prop: its index, position, rotation (quaternion)
const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0]
const INSTANT_S := 30.0              # the pause menu's replay starts this far before you paused
const LEAD_IN := 2.0                 # s before GO the results' replay starts
const STEP_S := 5.0                  # a tap of rewind / fast-forward
const SHUTTLE := 6.0                 # x: held rewind / fast-forward
const TRIGGER_SHUTTLE := 8.0         # x: a trigger all the way
const HOLD_TAP := 0.3                # s: held longer than this, rewind / fast-forward runs
const SPIN_WRAP := TAU * 1000.0      # rad: a wheel's spin is kept modulo this (float precision)
# a car sample's fields
const I_POS := 0
const I_ROT := 3
const I_VEL := 7
const I_STEER := 10
const I_RPM := 11
const I_GEAR := 12
const I_COMP := 13
const I_SPIN := 17
const I_THR := 21
const I_BRK := 22
const I_STEER_IN := 23
const I_SLIP := 24
const I_FLAGS := 25                  # 1 handbrake, 2 hidden (not in the scene then), surface index x 4
const FLAG_HB := 1
const FLAG_HIDDEN := 2
const FLAG_SURF := 4
## What a replay's pose touches on a car (and so puts back): RallyCar's own state.
const CAR_VARS := ["speed", "steer", "wheel_angles", "rpm", "gear", "slip", "grip_use", "on_surface", "comp", "inp",
	"net_throttle", "_net_handbrake", "_flap_prev_v", "grounded"]
const WHEEL_VARS := ["compression", "grounded", "spin", "_drop"]


## One car's recording: a ring of samples (STRIDE floats each), the global sample index of the
## first one written (origin), the oldest still kept (first) and the newest (last).
class Track:
	var key := ""
	var node_id := 0                 # the car's instance id (instance_from_id)
	var label := ""
	var stride := 26
	var cap := 0                     # samples kept
	var data := PackedFloat32Array()
	var origin := -1
	var first := -1
	var last := -1

	func _init(k: String, n: int, stride_in: int, cap_in: int) -> void:
		key = k
		stride = stride_in
		cap = cap_in

	func has(f: int) -> bool:
		return last >= 0 and f >= first and f <= last

	func _at(f: int) -> int:
		return ((f - origin) % cap) * stride

	## Sample f (a global index, in order); a gap since the last one (the car wasn't there) is
	## filled with its last sample, marked hidden.
	func write(f: int, v: PackedFloat32Array) -> void:
		if last < 0:
			origin = f
			first = f
			last = f - 1
		if f <= last:
			return
		if f - last > cap:                         # (away longer than it keeps: start afresh)
			origin = f
			first = f
			last = f - 1
		while last + 1 < f:
			var prev := sample(last)
			prev[25] = float(int(prev[25]) | 2)
			_put(last + 1, prev)
		_put(f, v)

	func _put(f: int, v: PackedFloat32Array) -> void:
		var i := (f - origin) % cap
		if data.size() < (i + 1) * stride:
			data.resize(mini(cap, maxi((i + 1) * 2, 600)) * stride)
		var o := i * stride
		for k in stride:
			data[o + k] = v[k]
		last = f
		first = maxi(first, last - cap + 1)

	func sample(f: int) -> PackedFloat32Array:
		var o := _at(f)
		return data.slice(o, o + stride)

	func bytes() -> int:
		return data.size() * 4


var game
var cam                              # ReplayCam
var bar                              # ReplayBar
var active := false                  # playing back
var from := ""                       # where it was opened: "results" or "pause"
var tracks := {}                     # key -> Track
var order: Array = []                # the keys, in the order they first turned up (yours first)
var surfaces: Array = ["gravel", "asphalt"]
var frame := -1                      # the newest sample (a global index)
var go_frame := -1                   # the sample at GO
var finish_frame := -1               # ... at the finish
var pause_frame := -1                # ... when the pause menu last came up
var pos_f := 0.0                     # the playhead (a global sample index, fractional)
var playing := true
var speed_i := 2                     # SPEEDS[speed_i]
var follow := ""                     # the key of the car the camera follows
var input_on := true                 # (tests) off: no keys read
var prop_frames: Array = []          # a ring of PackedFloat32Array: the props every PROP_EVERY samples
var prop_first := -1                 # (prop frame indices: the global sample / PROP_EVERY)
var prop_last := -1
var prop_ids: Array = []             # a prop's index -> its instance id
var _prop_index := {}                # instance id -> its index
var _rate := RATE                    # samples a second really (the physics ticks over the stride)
var _stride := 2                     # physics ticks a sample
var _tick := 0                       # physics ticks recorded
var _was_paused := false
var _live := false                   # online: the live game goes on under the replay
var _posed := false                  # (online) the poses are on: off again before the next tick
var _cars := {}                      # instance id -> the car's live state (put back when it ends)
var _props := {}                     # instance id -> a prop's live state
var _modes := {}                     # instance id -> [process mode, interpolation mode] before it began
var _synced := {}                    # instance id of a traffic body -> its sync_to_physics before it began
var _marks := {}                     # (online) skid marks' process modes before it began
var _fx := []                        # the cars' dust (DriftFx): held while the replay's paused
var _prop_prev := {}                 # instance id -> where the replay last put it (its wheels roll by it)
var _hud_was := true
var _mouse_was := Input.MOUSE_MODE_VISIBLE
var _opened_at := -1                 # the frame it opened (that frame's keys aren't the replay's)
var _hold_back := -1.0
var _hold_fwd := -1.0
var _shuttle := 0.0                  # x: rewind / fast-forward held (0: none)
var _scrub := false                  # the mouse is down on the timeline
var _dt_play := 0.0
var _pad_lb := false
var _pad_rb := false
var _early: Node


## Runs at the very start of every physics tick (before the cars and the game): online, the
## poses come off so the simulation only ever sees the live scene.
class EarlyTick extends Node:
	var replay

	func _physics_process(_dt: float) -> void:
		replay._tick_start()


func setup(g) -> void:
	game = g
	name = "Replay"
	process_mode = Node.PROCESS_MODE_ALWAYS          # (it plays back while the tree's paused)
	process_priority = -1000                         # (poses the cars before anything reads them in a frame)
	process_physics_priority = 1000                  # (records after every car has had its tick)
	var ticks := float(Engine.physics_ticks_per_second)
	_stride = maxi(1, int(round(ticks / RATE)))
	_rate = ticks / _stride
	_early = EarlyTick.new()
	_early.name = "EarlyTick"
	_early.replay = self
	_early.process_physics_priority = -1000
	add_child(_early)
	cam = ReplayCam.new()
	cam.name = "ReplayCam"
	add_child(cam)
	cam.setup(g)
	cam.message.connect(func(t: String): bar.flash(t))
	bar = ReplayBar.new()
	bar.name = "ReplayBar"
	add_child(bar)
	bar.visible = false
	bar.seek.connect(func(f: float): _seek_frac(f))
	bar.scrubbing.connect(func(on: bool): _scrub = on)


# ── recording ─────────────────────────────────────────────────────────────

func _physics_process(_dt: float) -> void:
	if game == null or not game.built or active:
		return
	var paused: bool = game.paused()
	if paused and not _was_paused:
		pause_frame = frame
	_was_paused = paused
	if not game.state in ["countdown", "running"]:
		if game.state == "finished" and finish_frame < 0 and frame >= 0:
			finish_frame = frame
		return
	if _tick % _stride == 0:
		_sample(_tick / _stride)
	tick_recorded.emit(float(_tick) / (_rate * _stride))
	_tick += 1


func _sample(f: int) -> void:
	frame = f
	for c in game.replay_targets():
		if not is_instance_valid(c) or not c is RigidBody3D:
			continue
		var key := str(game.get_path_to(c))
		var tr: Track = tracks.get(key)
		if tr == null:
			tr = Track.new(key, c.get_instance_id(), STRIDE, int(KEEP_S * _rate))
			tracks[key] = tr
			order.append(key)
		tr.node_id = c.get_instance_id()
		tr.label = _label(c)
		tr.write(f, _car_sample(c))
	if go_frame < 0 and game.state == "running":
		go_frame = f
	if f % PROP_EVERY == 0:
		_sample_props(f / PROP_EVERY)


func _car_sample(c) -> PackedFloat32Array:
	var v := PackedFloat32Array()
	v.resize(STRIDE)
	var xf: Transform3D = c.global_transform
	var q := xf.basis.get_rotation_quaternion()
	var lv: Vector3 = c.linear_velocity
	v[0] = xf.origin.x
	v[1] = xf.origin.y
	v[2] = xf.origin.z
	v[3] = q.x
	v[4] = q.y
	v[5] = q.z
	v[6] = q.w
	v[7] = lv.x
	v[8] = lv.y
	v[9] = lv.z
	v[I_STEER] = float(c.steer)
	v[I_RPM] = float(c.rpm)
	v[I_GEAR] = float(c.gear)
	for k in 4:
		v[I_COMP + k] = float(c.comp[k])
		v[I_SPIN + k] = fposmod(float(c.wheels[k].spin), SPIN_WRAP)
	var inp: Dictionary = c.inp
	v[I_THR] = float(inp.get("throttle", 0.0)) if c.simulate else float(c.net_throttle)
	v[I_BRK] = float(inp.get("brake", 0.0))
	v[I_STEER_IN] = float(inp.get("steer", 0.0))
	v[I_SLIP] = float(c.slip)
	var surf := str(c.on_surface)
	var si := surfaces.find(surf)
	if si < 0:
		surfaces.append(surf)
		si = surfaces.size() - 1
	v[I_FLAGS] = float((FLAG_HB if c.handbrake_on() else 0) + si * FLAG_SURF)
	return v


## The moving things that aren't cars the game drives: cut up's traffic (every car on the road,
## the other carriageway's, the ramps', a rival), the touge's stray car, its ghost.
func _prop_candidates() -> Array:
	var out: Array = []
	if game.traffic:
		for n in game.traffic.get_children():
			if n is Node3D and n.has_meta("wheels"):
				out.append(n)
	if game.stray:
		for n in game.stray.get_children():
			if n is Node3D:
				out.append(n)
	if game.ghost and game.ghost.get("_body") != null and is_instance_valid(game.ghost._body):
		out.append(game.ghost._body)
	return out


func _sample_props(pf: int) -> void:
	var nodes: Array = []
	for n in _prop_candidates():
		if (n as Node3D).is_visible_in_tree():
			nodes.append(n)
	var v := PackedFloat32Array()
	v.resize(nodes.size() * PROP_STRIDE)
	for i in nodes.size():
		var n: Node3D = nodes[i]
		var id := n.get_instance_id()
		if not _prop_index.has(id):
			_prop_index[id] = prop_ids.size()
			prop_ids.append(id)
		var xf := n.global_transform
		var q := xf.basis.get_rotation_quaternion()
		var o := i * PROP_STRIDE
		v[o] = float(_prop_index[id])
		v[o + 1] = xf.origin.x
		v[o + 2] = xf.origin.y
		v[o + 3] = xf.origin.z
		v[o + 4] = q.x
		v[o + 5] = q.y
		v[o + 6] = q.z
		v[o + 7] = q.w
	var cap := _prop_cap()
	if prop_frames.size() < cap:
		prop_frames.resize(cap)
	if prop_last >= 0 and pf <= prop_last:
		return
	if prop_first < 0:
		prop_first = pf
	while prop_last >= 0 and prop_last + 1 < pf:     # (a gap: the last frame again)
		prop_frames[(prop_last + 1) % cap] = prop_frames[prop_last % cap]
		prop_last += 1
	prop_frames[pf % cap] = v
	prop_last = pf
	prop_first = maxi(prop_first, prop_last - cap + 1)


func _prop_cap() -> int:
	return int(KEEP_S * _rate / PROP_EVERY)


func _label(c) -> String:
	var setup: Dictionary = c.setup if c.get("setup") is Dictionary else {}
	var car_name := str(setup.get("name", "")).to_upper()
	if c == game.car:
		return "YOU" + ("  ·  " + car_name if car_name != "" else "")
	var tag = c.get_node_or_null("NameTag")
	if tag is Label3D:
		return str((tag as Label3D).text).to_upper() + ("  ·  " + car_name if car_name != "" else "")
	return car_name if car_name != "" else str(c.name).to_upper()


# ── the recording, measured ───────────────────────────────────────────────

## The first and the newest sample there is to play (yours, or the earliest of them all).
func range_first() -> int:
	if not order.is_empty():
		var tr: Track = tracks[order[0]]
		if tr.last >= 0:
			return tr.first
	return frame


func range_last() -> int:
	return frame


## The replay's length (s).
func duration() -> float:
	return maxf(float(range_last() - range_first()), 0.0) / _rate


## The playhead (s from the start of what's kept).
func time() -> float:
	return (pos_f - float(range_first())) / _rate


func can_open() -> bool:
	return game != null and game.built and not active and frame >= 0 and duration() >= 1.0


## The memory the recording takes now: {cars, props, total} bytes, {samples}, {per_min}: the
## bytes a minute of it takes at the rate it's going (cars and props apart).
func memory_bytes() -> Dictionary:
	var cars := 0
	for k in tracks:
		cars += (tracks[k] as Track).bytes()
	var props := 0
	var floats := 0
	var n := 0
	for i in range(maxi(prop_first, 0), prop_last + 1):
		var fr = prop_frames[i % _prop_cap()]
		if fr is PackedFloat32Array:
			props += (fr as PackedFloat32Array).size() * 4 + 16
			floats += (fr as PackedFloat32Array).size()
			n += 1
	var per_car_min := STRIDE * 4 * _rate * 60.0
	var props_min := (float(floats) / maxf(n, 1) * 4.0 + 16.0) * (_rate / PROP_EVERY) * 60.0
	return {"cars": cars, "props": props, "total": cars + props, "per_car_min": per_car_min, "props_min": props_min,
		"cars_n": tracks.size(), "props_avg": float(floats) / maxf(n, 1) / PROP_STRIDE}


# ── open / close ──────────────────────────────────────────────────────────

## Play it back. where: "results" (from the start of the run) or "pause" (the last 30 s before
## the pause menu came up, an instant replay). False if there's nothing to play yet.
func open(where := "results") -> bool:
	if not can_open():
		return false
	from = where
	active = true
	_live = Net.online()
	_opened_at = Engine.get_process_frames()
	var a := range_first()
	var b := range_last()
	if where == "pause":
		var now := pause_frame if pause_frame >= a and pause_frame <= b else b
		pos_f = maxf(float(a), now - INSTANT_S * _rate)
	else:
		pos_f = float(a) if go_frame < 0 else maxf(float(a), go_frame - LEAD_IN * _rate)
	playing = true
	speed_i = 2
	_shuttle = 0.0
	_hold_back = -1.0
	_hold_fwd = -1.0
	_scrub = false
	# the cars: held (alone: the tree's paused, these go on drawing and sounding), captured
	_cars.clear()
	_modes.clear()
	_fx.clear()
	for key in order:
		var c = _node(key)
		if c == null:
			continue
		var id: int = c.get_instance_id()
		_modes[id] = [c.process_mode, c.physics_interpolation_mode]
		c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		if not _live:
			c.replay_held = true
			c.process_mode = Node.PROCESS_MODE_ALWAYS
		for ch in c.get_children():
			if ch.get_script() == DriftFx:
				_fx.append(ch)
		_cars[id] = capture_car(c)
	_props.clear()
	_prop_prev.clear()
	_synced.clear()
	for n in _prop_candidates():
		var id2: int = n.get_instance_id()
		_modes[id2] = [n.process_mode, n.physics_interpolation_mode]
		n.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_props[id2] = _capture_prop(n)
		if n is AnimatableBody3D:
			# (a body synced to the physics only moves at the next physics step, which a paused
			# tree doesn't take: posed, it's put straight where it goes)
			_synced[id2] = (n as AnimatableBody3D).sync_to_physics
			(n as AnimatableBody3D).sync_to_physics = false
	_marks.clear()
	if _live:
		for n in game.get_children():
			if n.get_script() == SkidMarks:              # (online the scene goes on: no tyre marks where the replay drives)
				_marks[n.get_instance_id()] = n.process_mode
				n.process_mode = Node.PROCESS_MODE_DISABLED
	_posed = false
	if not _live:
		get_tree().paused = true
	_hud_was = game._hud.visible
	game._hud.visible = false
	_mouse_was = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if follow == "" or not tracks.has(follow) or _node(follow) == null:
		follow = order[0] if not order.is_empty() else ""
	cam.set_target(_node(follow))
	cam.set_mode(cam.mode if cam.mode in cam.modes() else "chase")
	cam.make_current()
	bar.visible = true
	bar.set_hud(true)
	_frame(0.0)
	opened.emit()
	return true


## Back to the game, everything as it was (the results, or paused).
func close() -> void:
	if not active:
		return
	if not _live or _posed:
		_restore_live()                              # (online with the poses already off: it's live as it is)
	_posed = false
	for key in order:
		var c = _node(key)
		if c == null:
			continue
		var m: Array = _modes.get(c.get_instance_id(), [])
		c.replay_held = false
		if not m.is_empty():
			c.process_mode = m[0]
			c.physics_interpolation_mode = m[1]
		c.reset_physics_interpolation()
	for id in _props:
		var n := instance_from_id(id) as Node3D
		if n == null:
			continue
		var m2: Array = _modes.get(id, [])
		if not m2.is_empty():
			n.physics_interpolation_mode = m2[1]
		if _synced.has(id) and n is AnimatableBody3D:
			(n as AnimatableBody3D).sync_to_physics = _synced[id]
		n.reset_physics_interpolation()
	_synced.clear()
	for fx in _fx:
		if is_instance_valid(fx):
			fx.set_physics_process(true)
	for id in _marks:
		var mk := instance_from_id(id) as Node
		if mk:
			mk.process_mode = _marks[id]
	_marks.clear()
	game._hud.visible = _hud_was
	Input.mouse_mode = _mouse_was
	if game.cam:
		game.cam.view = ""                           # (the game puts its view back together: the body, the cockpit)
		game.cam.make_current()
	cam.current = false
	bar.visible = false
	active = false
	if not _live:
		get_tree().paused = false
	if from == "pause" and game._pause.visible and game.get("_pause_replay") and is_instance_valid(game._pause_replay):
		game._pause_replay.grab_focus()
	closed.emit()


func _exit_tree() -> void:
	if active and not _live and is_inside_tree():
		get_tree().paused = false


# ── every frame while it plays ────────────────────────────────────────────

func _process(dt: float) -> void:
	if not active:
		return
	if input_on and Engine.get_process_frames() != _opened_at:
		_keys(dt)
	_advance(dt)
	_frame(dt)


## The playhead moves: playing at its speed, held rewind / fast-forward, a trigger's shuttle;
## it stops at the end.
func _advance(dt: float) -> void:
	var x := float(SPEEDS[speed_i]) if playing else 0.0
	_shuttle = 0.0
	if _hold_back > HOLD_TAP:
		_shuttle = -SHUTTLE
	elif _hold_fwd > HOLD_TAP:
		_shuttle = SHUTTLE
	elif input_on and not cam.mode in ["free", "orbit"]:
		var trig := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
		if absf(trig) > 0.1:
			_shuttle = trig * TRIGGER_SHUTTLE
	if _shuttle != 0.0:
		x = _shuttle
	if _scrub:
		x = 0.0
	var before := pos_f
	pos_f = clampf(pos_f + dt * _rate * x, float(range_first()), float(range_last()))
	if playing and x > 0.0 and pos_f >= float(range_last()):
		playing = false
	_dt_play += (pos_f - before) / _rate


## This frame: the poses on (the live scene captured first, online), the camera, the bar.
func _frame(dt: float) -> void:
	if _live and not _posed:
		_capture_live()
	var dtp := _dt_play
	_dt_play = 0.0
	_pose(dtp)
	_posed = true
	var still := dtp == 0.0
	for fx in _fx:
		if is_instance_valid(fx):
			fx.set_physics_process(not still)          # (no dust off a car standing in a paused frame)
	var t = _node(follow)
	if t == null:
		_next_car(1)
		t = _node(follow)
	if t != null:
		cam.set_target(t)
		var f := sample_at(tracks[follow], pos_f)
		cam.target_vel = f.get("vel", Vector3.ZERO)
	if not cam.current:
		cam.make_current()                           # (something took the screen: online, someone joining)
	cam.update(dt, dtp)
	if is_instance_valid(game.car) and game.has_method("_engine_audio"):
		game._engine_audio()                         # (the gravel under your tyres, from the replay)
	var total := float(range_last() - range_first())
	var marks: Array = []
	for m in [[go_frame, Color(0.35, 1.0, 0.4)], [finish_frame, Color.WHITE], [pause_frame if from == "pause" else -1, UI_RED]]:
		if int(m[0]) >= range_first() and total > 0.0:
			marks.append([(float(m[0]) - range_first()) / total, m[1]])
	var mouse := Input.MOUSE_MODE_CAPTURED if Input.is_action_pressed("replay_look") and cam.mode in ["free", "orbit", "cockpit"] and input_on else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != mouse and not (mouse == Input.MOUSE_MODE_VISIBLE and Input.mouse_mode == Input.MOUSE_MODE_CONFINED):
		Input.mouse_mode = mouse
	bar.show_info({"t": time(), "total": duration(), "frac": (pos_f - range_first()) / maxf(total, 1.0), "playing": playing,
		"speed": SPEEDS[speed_i], "shuttle": _shuttle, "cam": cam.title(), "car": tracks[follow].label if tracks.has(follow) else "",
		"marks": marks, "pad": Controls.has_pad(), "mode": cam.mode})

const UI_RED := Color(0.86, 0.14, 0.1)


## The keys and buttons.
func _keys(dt: float) -> void:
	if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("replay_exit"):
		close.call_deferred()                        # (at the frame's end: the game doesn't see this ESC as its own)
		return
	if Input.is_action_just_pressed("replay_play"):
		if not playing and pos_f >= float(range_last()):
			pos_f = float(range_first())
		playing = not playing
	for d in [-1, 1]:
		var act := "replay_back" if d < 0 else "replay_fwd"
		var held: float = _hold_back if d < 0 else _hold_fwd
		if Input.is_action_just_pressed(act):
			held = 0.0
		elif Input.is_action_pressed(act) and held >= 0.0:
			held += dt
		elif held >= 0.0:
			if held <= HOLD_TAP:
				step(d * STEP_S)
			held = -1.0
		if d < 0:
			_hold_back = held
		else:
			_hold_fwd = held
	if Input.is_action_just_pressed("replay_faster"):
		set_speed(speed_i + 1)
	if Input.is_action_just_pressed("replay_slower"):
		set_speed(speed_i - 1)
	if Input.is_action_just_pressed("replay_start"):
		pos_f = float(range_last()) if pos_f <= range_first() + _rate else float(range_first())
		_dt_play = 0.0
	if Input.is_action_just_pressed("replay_end"):
		pos_f = float(range_last())
		playing = false
	var free: bool = cam.mode in ["free", "orbit"]      # (their shoulders move the camera)
	var lb := Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER)
	var rb := Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)
	if Input.is_action_just_pressed("replay_car_next") or (rb and not _pad_rb and not free):
		_next_car(1)
	if Input.is_action_just_pressed("replay_car_prev") or (lb and not _pad_lb and not free):
		_next_car(-1)
	_pad_lb = lb
	_pad_rb = rb
	if Input.is_action_just_pressed("replay_cam_next"):
		cam.cycle(1)
		bar.flash(cam.title())
	if Input.is_action_just_pressed("replay_cam_prev"):
		cam.cycle(-1)
		bar.flash(cam.title())
	if Input.is_action_just_pressed("replay_hud"):
		bar.set_hud(not bar.hud_on())
	if Input.is_action_just_pressed("replay_place"):
		cam.place_here()
	if Input.is_action_just_pressed("replay_director"):
		if cam.placed.is_empty():
			bar.flash("PLACE A CAMERA FIRST (P)")
		else:
			cam.set_mode("director")
			bar.flash(cam.title())
	if Input.is_action_just_pressed("replay_clear") and not cam.placed.is_empty():
		cam.clear_placed()


## 1-9 and 0 pick a camera straight away (the list's first ten).
func _unhandled_key_input(e: InputEvent) -> void:
	if not active or not input_on or not e is InputEventKey or not (e as InputEventKey).pressed or (e as InputEventKey).echo:
		return
	var k := (e as InputEventKey).physical_keycode
	if k >= KEY_0 and k <= KEY_9:
		var i := 9 if k == KEY_0 else int(k - KEY_1)
		var list: Array = cam.modes()
		if i < list.size():
			cam.set_mode(list[i])
			bar.flash(cam.title())
			get_viewport().set_input_as_handled()


# ── playback controls (the keys use these; so do the tests) ───────────────

func set_speed(i: int) -> void:
	speed_i = clampi(i, 0, SPEEDS.size() - 1)


## Jump by s seconds (back if less than zero).
func step(s: float) -> void:
	seek(time() + s)


## The playhead to t s from the start of what's kept.
func seek(t: float) -> void:
	pos_f = clampf(float(range_first()) + t * _rate, float(range_first()), float(range_last()))


func _seek_frac(f: float) -> void:
	seek(f * duration())


## The next car to follow (or the one before), one that's there now.
func _next_car(d: int) -> void:
	if order.is_empty():
		return
	var i := order.find(follow)
	for n in order.size():
		i = posmod(i + d, order.size())
		var key: String = order[i]
		if _node(key) != null and _cars.has((_node(key) as Node).get_instance_id()):
			follow = key
			cam.set_target(_node(key))
			bar.flash((tracks[key] as Track).label)
			return


## Follow this car (its key, the path under the Game: "Car", "Car_2", "RaceField/...").
func follow_car(key: String) -> void:
	if tracks.has(key):
		follow = key
		if active:
			cam.set_target(_node(key))


func _node(key: String):
	if not tracks.has(key):
		return null
	var o := instance_from_id((tracks[key] as Track).node_id)
	if o == null or not is_instance_valid(o) or not (o is Node) or not (o as Node).is_inside_tree():
		return null
	return o


# ── posing ────────────────────────────────────────────────────────────────

## Track tr at the fractional sample ff, interpolated: the pose replay_pose takes, {} where the
## car wasn't in the scene.
func sample_at(tr: Track, ff: float) -> Dictionary:
	if tr.last < 0 or ff < tr.first - 0.001 or ff > tr.last + 0.001:
		return {}
	var f0 := clampi(floori(ff), tr.first, tr.last)
	var f1 := mini(f0 + 1, tr.last)
	var u := clampf(ff - f0, 0.0, 1.0) if f1 != f0 else 0.0
	var a := tr.sample(f0)
	var b := tr.sample(f1)
	if int(a[I_FLAGS]) & FLAG_HIDDEN:
		return {}
	var pa := Vector3(a[0], a[1], a[2])
	var pb := Vector3(b[0], b[1], b[2])
	var qa := Quaternion(a[3], a[4], a[5], a[6]).normalized()
	var qb := Quaternion(b[3], b[4], b[5], b[6]).normalized()
	var comp: Array = []
	var spin: Array = []
	for k in 4:
		comp.append(lerpf(a[I_COMP + k], b[I_COMP + k], u))
		var sa: float = a[I_SPIN + k]
		var sb: float = b[I_SPIN + k]
		if absf(sb - sa) > SPIN_WRAP * 0.5:             # (wrapped round between the two)
			sb += SPIN_WRAP if sb < sa else -SPIN_WRAP
		spin.append(lerpf(sa, sb, u))
	var fl := int(a[I_FLAGS] if u < 0.5 else b[I_FLAGS])
	var si := fl / FLAG_SURF
	return {"xf": Transform3D(Basis(qa.slerp(qb, u)), pa.lerp(pb, u)),
		"vel": Vector3(a[7], a[8], a[9]).lerp(Vector3(b[7], b[8], b[9]), u),
		"steer": lerpf(a[I_STEER], b[I_STEER], u), "rpm": lerpf(a[I_RPM], b[I_RPM], u),
		"gear": int(a[I_GEAR] if u < 0.5 else b[I_GEAR]), "comp": comp, "spin": spin,
		"throttle": lerpf(a[I_THR], b[I_THR], u), "brake": lerpf(a[I_BRK], b[I_BRK], u),
		"steer_in": lerpf(a[I_STEER_IN], b[I_STEER_IN], u), "slip": lerpf(a[I_SLIP], b[I_SLIP], u),
		"handbrake": (fl & FLAG_HB) != 0, "surface": surfaces[si] if si < surfaces.size() else "gravel"}


## The pose of the car with this key at t s into the replay (tests), or {}.
func pose_at(key: String, t: float) -> Dictionary:
	if not tracks.has(key):
		return {}
	return sample_at(tracks[key], float(range_first()) + t * _rate)


func _pose(dtp: float) -> void:
	for key in order:
		var c = _node(key)
		if c == null or not _cars.has((c as Node).get_instance_id()):
			continue                                     # (gone, or new since it opened: left live)
		var f := sample_at(tracks[key], pos_f)
		if f.is_empty():
			(c as Node3D).visible = false
			continue
		(c as Node3D).visible = true
		c.replay_pose(f, absf(dtp))
	_pose_props(dtp)


func _pose_props(dtp: float) -> void:
	if prop_last < 0 or _props.is_empty():
		return
	var cap := _prop_cap()
	var pf := pos_f / PROP_EVERY
	var a := clampi(floori(pf), prop_first, prop_last)
	var b := mini(a + 1, prop_last)
	var u := clampf(pf - a, 0.0, 1.0) if b != a else 0.0
	var fa: PackedFloat32Array = prop_frames[a % cap]
	var fb: PackedFloat32Array = prop_frames[b % cap]
	var in_b := {}
	for i in range(0, fb.size(), PROP_STRIDE):
		in_b[int(fb[i])] = i
	var shown := {}
	for i in range(0, fa.size(), PROP_STRIDE):
		var idx := int(fa[i])
		var id: int = prop_ids[idx]
		if not _props.has(id):
			continue
		var n := instance_from_id(id) as Node3D
		if n == null:
			continue
		var p := Vector3(fa[i + 1], fa[i + 2], fa[i + 3])
		var q := Quaternion(fa[i + 4], fa[i + 5], fa[i + 6], fa[i + 7]).normalized()
		if in_b.has(idx):
			var j: int = in_b[idx]
			p = p.lerp(Vector3(fb[j + 1], fb[j + 2], fb[j + 3]), u)
			q = q.slerp(Quaternion(fb[j + 4], fb[j + 5], fb[j + 6], fb[j + 7]).normalized(), u)
		var xf := Transform3D(Basis(q), p)
		if not _live and _prop_prev.has(id) and n.has_meta("wheels"):   # (its wheels roll the way it moved)
			var dp: Vector3 = p - (_prop_prev[id] as Vector3)
			if dp.length() < 20.0:
				var turn := dp.dot(-xf.basis.z) / 0.33
				for w in n.get_meta("wheels"):
					if is_instance_valid(w):
						(w as Node3D).rotate_object_local(Vector3.RIGHT, -turn)
		_prop_prev[id] = p
		n.global_transform = xf
		n.visible = true
		shown[id] = true
	for id in _props:
		if not shown.has(id):
			var n2 := instance_from_id(id) as Node3D
			if n2:
				n2.visible = false


# ── the live state, captured and put back ─────────────────────────────────

func _tick_start() -> void:
	if active and _live and _posed:
		_restore_live()
		_posed = false


func _capture_live() -> void:
	for id in _cars.keys():
		var c = instance_from_id(id)
		if c == null:
			_cars.erase(id)
			continue
		_cars[id] = capture_car(c)
	for id in _props.keys():
		var n := instance_from_id(id) as Node3D
		if n == null:
			_props.erase(id)
			continue
		_props[id] = _capture_prop(n)


func _restore_live() -> void:
	for id in _cars:
		var c = instance_from_id(id)
		if c != null:
			apply_car(c, _cars[id])
	for id in _props:
		var n := instance_from_id(id) as Node3D
		if n != null:
			_apply_prop(n, _props[id])


## Everything a replay's pose touches on a car, to put back exactly.
static func capture_car(c) -> Dictionary:
	var s := {"xf": c.global_transform, "lv": c.linear_velocity, "av": c.angular_velocity, "visible": c.visible,
		"vars": {}, "wheels": [], "flaps": []}
	for v in CAR_VARS:
		if v in c:
			var x = c.get(v)
			s.vars[v] = x.duplicate(true) if (x is Array or x is Dictionary) else x
	for w in c.wheels:
		var ws := {"rot": w.rotation}
		for v in WHEEL_VARS:
			ws[v] = w.get(v)
		s.wheels.append(ws)
	if "_flaps" in c:
		for f in c._flaps:
			s.flaps.append([f[1], f[2], (f[0] as Node3D).rotation.z])
	return s


static func apply_car(c, s: Dictionary) -> void:
	c.global_transform = s.xf
	c.linear_velocity = s.lv
	c.angular_velocity = s.av
	c.visible = s.visible
	for v in s.vars:
		var x = s.vars[v]
		c.set(v, x.duplicate(true) if (x is Array or x is Dictionary) else x)
	for k in mini(c.wheels.size(), s.wheels.size()):
		var w = c.wheels[k]
		var ws: Dictionary = s.wheels[k]
		w.rotation = ws.rot
		for v in WHEEL_VARS:
			w.set(v, ws[v])
	if "_flaps" in c:
		for k in mini(c._flaps.size(), s.flaps.size()):
			c._flaps[k][1] = s.flaps[k][0]
			c._flaps[k][2] = s.flaps[k][1]
			(c._flaps[k][0] as Node3D).rotation.z = s.flaps[k][2]


func _capture_prop(n: Node3D) -> Dictionary:
	var s := {"xf": n.global_transform, "visible": n.visible, "wheels": []}
	if not _live and n.has_meta("wheels"):
		for w in n.get_meta("wheels"):
			s.wheels.append((w as Node3D).transform if is_instance_valid(w) else Transform3D())
	return s


func _apply_prop(n: Node3D, s: Dictionary) -> void:
	n.global_transform = s.xf
	n.visible = s.visible
	if not (s.wheels as Array).is_empty() and n.has_meta("wheels"):
		var ws: Array = n.get_meta("wheels")
		for k in mini(ws.size(), (s.wheels as Array).size()):
			if is_instance_valid(ws[k]):
				(ws[k] as Node3D).transform = s.wheels[k]
