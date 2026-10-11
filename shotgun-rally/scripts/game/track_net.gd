extends Node
## Track Mode online (a street session on the circuit, the node "TrackNet" under the Game: the same
## path on every machine). The host's machine is race control for everyone: RaceControl and
## TrackSession run there only, on every car, the host's own, the other players' and the AI's.
##
##   * Each guest's machine runs its own car (as in the touge) and sends the host where it is on the
##     track (s, d, speed, in the pit lane) POS_HZ times a second, stamped with its own clock (its
##     physics time). The host plays those back DELAY s behind on its own clock (the stamps' offset
##     from it: the quickest of the last 3 s, eased into) for where the car is now: the order, the
##     gaps, the flags, the penalties. Its laps and sectors are timed on the stamps (TrackSession's
##     "t"), between the positions either side of each line: to the millisecond, as the guest's own
##     machine would time them, even when the host's physics falls behind (a busy machine's does).
##   * The AI (RaceField) are simulated on the host and streamed to everyone like a remote car
##     (RaceField.net_pack / feed).
##   * The host sends every machine the race's state 5 times a second (the phase and lights, the
##     clock, the yellows and blues, who may open their DRS, the timing board: the running order,
##     each car's laps, gaps, best and last laps, penalties, status), its news as it happens (the
##     lights, the flags, penalties and warnings, the guests' laps and sectors: the HUD's messages),
##     and the classification.
##   * A guest keeps a copy of race control and the timing (the Game's race_ctl and session, never
##     ticked there) for its HUD: the tower, the lights, the flags, its DRS, the results.
## The grid has an epoch: one more each time the host puts the cars in their places (the start, a
## red flag's restart). A guest's positions carry the epoch it has; older ones are dropped, so a
## car moved to its grid box isn't judged on where it was.

const POS_HZ := 20.0               # a guest's track position to the host, a second
const STATE_EVERY := 0.2           # s between the race's state going out
const AI_EVERY := 0.05             # s between the AI cars' stream
const DELAY := 0.12                # s behind a guest's newest position the host times its car at
const STALE := 20.0                # s without a guest's position (still connected): retired, so the race can't wait on it

var game                           # the Game
var host := false
var epoch := 0
var board: Array = []              # (a guest) the host's timing board, in its order (Game._board's rows)
var rows: Array = []               # (a guest) the host's classification (RaceControl.results)
var final := false                 # (a guest) rows is the last classification: everyone's done
var names := {}                    # id -> name: everyone's (the AI's, those who've left)
var late_box := -1                 # (a guest) joined once the session was on: the pit box it starts from
var _remote := {}                  # (the host) guest id -> {buf: [[t, s, d, v, pit]], off, mins, est, seen}
var _seq := 0                      # (the host) ticks of race control
var _news_seq := 0                 # (a guest) the newest news's tick: an older state doesn't undo it
var _state_t := 0.0
var _ai_t := 0.0
var _rows_t := 0.0
var _rows_sent := ""
var _final_sent := false
var _send_t := 0.0


func setup(g, is_host: bool) -> void:
	game = g
	host = is_host


# ── the host ────────────────────────────────────────────────────────────────

## The grid's set (the start): each guest's car timed from its start (s, d), every guest told.
## starts: id -> Vector2(s, d) for every car; boxes: player id -> pit box.
func locked(ids: Array, starts: Dictionary, boxes: Dictionary) -> void:
	epoch += 1
	for id in ids:
		if id != Net.my_id() and Net.players.has(id):
			_track(id, starts[id])
		names[id] = game._car_name(id, false)
	_to_guests("grid_set", [ids, boxes, epoch, names])


## A guest joined once the session was on: timed from its pit box, told the grid and where to start.
func joined(id: int, start: Vector2, box: int, ids: Array, boxes: Dictionary) -> void:
	names[id] = game._car_name(id, false)
	_track(id, start)
	joined_late.rpc_id(id, ids, boxes, epoch, names, box)


func _track(id: int, start: Vector2) -> void:
	var r: Dictionary = _remote.get(id, {"buf": [], "off": INF, "mins": []})
	r.buf = []
	r.est = {"s": start.x, "d": start.y, "v": 0.0, "pit": false}
	r.seen = float(game._t_alive)
	_remote[id] = r


## A guest has left: nothing more of it.
func drop(id) -> void:
	_remote.erase(id)


## The guests' cars where race control is to judge them now: {id: {s, d, v, pit}}. One silent for
## STALE s (still connected) is retired.
func positions(now: float) -> Dictionary:
	var out := {}
	for id in _remote.keys():
		var r: Dictionary = _remote[id]
		if now - float(r.seen) > STALE and game.race_ctl:
			game.race_ctl.retire(id, "DNF")
		out[id] = _estimate(r, now)
	return out


## A guest's car DELAY s behind its newest position on the host's clock: between the two positions
## either side, or past the newest at its speed (a little way only). With its own clock's time
## there ("t": never going back), on which its laps are timed (TrackSession).
func _estimate(r: Dictionary, now: float) -> Dictionary:
	var buf: Array = r.buf
	if buf.is_empty():
		return r.est
	var want: float = maxf(now - float(r.off) - DELAY, float(r.get("want", -INF)))
	r.want = want
	var a: Array = buf[0]
	var b: Array = buf[buf.size() - 1]
	if want >= float(b[0]):
		var ahead := minf(want - float(b[0]), 0.25)
		r.est = {"s": float(b[1]) + float(b[3]) * ahead, "d": float(b[2]), "v": float(b[3]), "pit": bool(b[4]), "t": float(b[0]) + ahead}
	elif want <= float(a[0]):
		r.est = {"s": float(a[1]), "d": float(a[2]), "v": float(a[3]), "pit": bool(a[4]), "t": float(a[0])}
	else:
		for i in range(buf.size() - 1, 0, -1):
			var p0: Array = buf[i - 1]
			if float(p0[0]) <= want:
				var p1: Array = buf[i]
				var u := clampf((want - float(p0[0])) / maxf(float(p1[0]) - float(p0[0]), 1e-6), 0.0, 1.0)
				r.est = {"s": lerpf(float(p0[1]), float(p1[1]), u), "d": lerpf(float(p0[2]), float(p1[2]), u),
					"v": lerpf(float(p0[3]), float(p1[3]), u), "pit": bool(p0[4]) if u < 0.5 else bool(p1[4]), "t": want}
				break
	return r.est


## (a guest's machine) Where its car is: t its clock (s), ep the grid's epoch it has.
@rpc("any_peer", "unreliable_ordered")
func pos_in(t: float, ep: int, s: float, d: float, v: float, pit: bool) -> void:
	if not host:
		return
	var id := multiplayer.get_remote_sender_id()
	var r: Dictionary = _remote.get(id, {})
	if r.is_empty() or ep != epoch:
		return
	var buf: Array = r.buf
	if not buf.is_empty() and t <= float(buf[buf.size() - 1][0]):
		return
	buf.append([t, s, d, v, pit])
	while buf.size() > 40:
		buf.pop_front()
	# its clock against ours: the least delay of the last 3 s (the quickest packet), eased into
	# (a steady offset: the laps are differences, so a steady one costs them nothing)
	var now := float(game._t_alive)
	var mins: Array = r.mins
	mins.append(now - t)
	while mins.size() > 60:
		mins.pop_front()
	var lo: float = mins.min()
	r.off = lo if float(r.off) == INF else lerpf(float(r.off), lo, 0.05)
	r.seen = now


## Every tick of race control on the host, before the Game reads its news: the news to the guests,
## the race's state, the classification when it changes (and the last one when everyone's done).
func host_tick(dt: float, board_rows: Array) -> void:
	_seq += 1
	var rc = game.race_ctl
	var rc_ev: Array = []
	for ev in rc.events:
		if str(ev.kind) == "regrid":
			# (a red flag's restart: everyone into a grid box; positions from before don't count)
			epoch += 1
			ev["epoch"] = epoch
			for id in _remote:
				if (ev.spots as Dictionary).has(id):
					var sp: Vector2 = ev.spots[id]
					_remote[id].buf = []
					_remote[id].est = {"s": sp.x, "d": sp.y, "v": 0.0, "pit": false}
		rc_ev.append(ev)
	var ses_ev: Array = game.session.events.filter(func(ev): return _remote.has(ev.id))   # (the guests' laps and sectors)
	if not rc_ev.is_empty() or not ses_ev.is_empty():
		_to_guests("news", [_seq, rc_ev, ses_ev])
	# (once everyone's done race control stops: the last state and classification go out then)
	var done: bool = rc.phase == "done"
	var last: bool = done and not _final_sent
	_state_t -= dt
	if _state_t <= 0.0 or last:
		_state_t = STATE_EVERY
		_to_guests("state_in", [_seq, _snapshot(board_rows)])
	_rows_t -= dt
	if _rows_t <= 0.0 or last:
		_rows_t = 1.0
		var res: Array = rc.results(game._last_pos)
		var key := str(res) + str(done)
		if key != _rows_sent:
			_rows_sent = key
			_final_sent = done
			_to_guests("results_in", [res, done])


## The race's state for the guests (the board packed: its ids, then BOARD_N numbers a car).
func _snapshot(board_rows: Array) -> Dictionary:
	var rc = game.race_ctl
	var ses = game.session
	var ids := PackedInt64Array()
	var nums := PackedFloat32Array()
	for r in board_rows:
		ids.append(int(r.id))
		nums.append_array([r.laps, 1.0 if r.out else 0.0, r.t0, 1.0 if r.ok else 0.0, r.best, r.last, 1.0 if r.pit else 0.0,
			r.pens, float(STATUS.find(str(r.st))), r.gap, r.down, r.intv, r.fin, 1.0 if r.jump else 0.0])
	return {"phase": rc.phase, "lights": rc.lights, "race_t": rc.race_t, "time": ses.time, "restarts": rc.restarts,
		"drs": rc.drs_enabled, "yel": rc.yellows.keys(), "blue": rc.blue, "drsok": rc._drs_ok,
		"fl": [ses.session_best_id, ses.session_best], "ids": ids, "nums": nums}


const STATUS := ["", "DNF", "DSQ"]
const BOARD_N := 14


## The board back out of a state: Game._board's rows.
static func _unpack_board(snap: Dictionary) -> Array:
	var ids: PackedInt64Array = snap.ids
	var n: PackedFloat32Array = snap.nums
	var out: Array = []
	for i in ids.size():
		var k := i * BOARD_N
		out.append({"id": ids[i], "laps": int(n[k]), "out": n[k + 1] > 0.5, "t0": n[k + 2], "ok": n[k + 3] > 0.5, "best": n[k + 4],
			"last": n[k + 5], "pit": n[k + 6] > 0.5, "pens": n[k + 7], "st": STATUS[clampi(int(n[k + 8]), 0, 2)], "gap": n[k + 9],
			"down": int(n[k + 10]), "intv": n[k + 11], "fin": n[k + 12], "jump": n[k + 13] > 0.5})
	return out


## The AI cars to the guests, AI_EVERY s (any time: on the grid too).
func stream_ai(dt: float) -> void:
	if game.field == null or game.field.cars.is_empty():
		return
	_ai_t -= dt
	if _ai_t > 0.0:
		return
	_ai_t = AI_EVERY
	_to_guests("ai_in", [Time.get_ticks_msec(), game.field.net_pack()])


## Call `method` on every guest whose stage is loaded (a machine still loading has no TrackNet).
func _to_guests(method: String, args: Array) -> void:
	var peers := multiplayer.get_peers()
	for id in game._loaded_peers:
		if id != Net.my_id() and id in peers:
			callv("rpc_id", [id, method] + args)


# ── a guest ─────────────────────────────────────────────────────────────────

@rpc("authority", "reliable")
func grid_set(ids: Array, boxes: Dictionary, ep: int, nm: Dictionary) -> void:
	names.merge(nm, true)
	epoch = ep
	game.net_grid(ids, boxes)


@rpc("authority", "reliable")
func joined_late(ids: Array, boxes: Dictionary, ep: int, nm: Dictionary, box: int) -> void:
	late_box = box
	grid_set(ids, boxes, ep, nm)


## Race control's news (rc_ev) and this session's laps and sectors (ses_ev): into the copy, and on
## to the Game's HUD as its own would be.
@rpc("authority", "reliable")
func news(seq: int, rc_ev: Array, ses_ev: Array) -> void:
	if host:
		return
	_news_seq = seq
	var rc = game.race_ctl
	for ev in rc_ev:
		match str(ev.kind):
			"light":
				rc.phase = "lights"
				rc.lights = int(ev.n)
			"green":
				rc.phase = "green"
				rc.lights = 0
			"chequered":
				rc.phase = "chequered"
			"red":
				rc.phase = "red"
			"restart":
				rc.phase = "lights"
				rc.lights = 0
				rc.restarts += 1
			"regrid":
				rc.grid_order = ev.order
				rc.spots = ev.spots
			"drs":
				rc.drs_enabled = bool(ev.on)
			"yellow":
				rc.yellows[int(ev.sector)] = 5.0
			"yellow_clear":
				rc.yellows.erase(int(ev.sector))
			"finish":
				rc.finished[ev.id] = float(ev.time)
				if not ev.id in rc.finish_order:
					rc.finish_order.append(ev.id)
			"dnf":
				rc.dnf[ev.id] = str(ev.text)
	rc.events.append_array(rc_ev)
	game.session.events.append_array(ses_ev)


## The race's state into the copy.
@rpc("authority", "unreliable_ordered")
func state_in(seq: int, snap: Dictionary) -> void:
	if host:
		return
	var rc = game.race_ctl
	var ses = game.session
	if seq >= _news_seq:                               # (not older than the news: the lights stay as it said)
		rc.phase = str(snap.phase)
		rc.lights = int(snap.lights)
		rc.restarts = int(snap.restarts)
		rc.drs_enabled = bool(snap.drs)
		rc.yellows = {}
		for q in snap.yel:
			rc.yellows[int(q)] = 5.0
	rc.race_t = float(snap.race_t)
	ses.time = float(snap.time)
	rc.blue = snap.blue
	rc._drs_ok = snap.drsok
	ses.session_best_id = snap.fl[0]
	ses.session_best = float(snap.fl[1])
	var bd := _unpack_board(snap)
	for r in bd:
		var id = r.id
		if not ses.cars.has(id):
			ses.add_car(id, str(names.get(id, id)), 0.0)
		var c: Dictionary = ses.cars[id]
		c.laps = int(r.laps)
		c.out_lap = bool(r.out)
		c.lap_t0 = float(r.t0)
		c.valid = bool(r.ok)
		c.best = float(r.best)
		c.last = float(r.last)
		rc.pens[id] = {"time": float(r.pens), "list": [["JUMP START", game.RaceControl.PENALTY, "jump"]] if bool(r.jump) else [], "warn": {}, "dsq": str(r.st) == "DSQ"}
		if str(r.st) != "":
			rc.dnf[id] = str(r.st)
		else:
			rc.dnf.erase(id)
		if float(r.fin) >= 0.0:
			rc.finished[id] = float(r.fin)
			if not id in rc.finish_order:
				rc.finish_order.append(id)
	board = bd


@rpc("authority", "reliable")
func results_in(res: Array, is_final: bool) -> void:
	rows = res
	final = is_final
	for r in res:
		names[r.id] = str(r.name)
	if is_final:
		game.race_ctl.phase = "done"                   # (the session's over: race control said so with it)
	game.net_results()


@rpc("authority", "unreliable_ordered")
func ai_in(t: int, data: PackedFloat32Array) -> void:
	if game._ai_view:
		game._ai_view.feed(t, data)


## Every tick on a guest's machine: the copy's clocks run on between the host's states, and where its
## car is goes to the host. mine: {s, d, v, pit}.
func guest_tick(dt: float, mine: Dictionary) -> void:
	var rc = game.race_ctl
	if rc.phase in ["green", "chequered"]:
		rc.race_t += dt
	game.session.time += dt
	_send_t -= dt
	if _send_t <= 0.0 and game.crew_ready():
		_send_t = 1.0 / POS_HZ
		pos_in.rpc_id(1, float(game._t_alive), epoch, float(mine.s), float(mine.d), float(mine.v), bool(mine.pit))
