extends SceneTree
## Running into traffic in cut up (Traffic.shove, game.gd _on_hit): the two cars share the
## hit by weight, as two real cars do. A traffic car's body is kinematic, so the physics
## alone bounced the player off it as off a wall (the video study: clipping a car at 150 vs
## 100 km/h cost ~50 km/h with a ~6 g jolt, and the traffic car didn't move).
##   * a rear-ender at 150 into a car at 100 costs the player 15-32 km/h (its share by weight),
##     the jolt (the speed lost over the first 0.1 s, as a body feels it) under half a wall's
##   * the traffic car is pushed on (>= 12 km/h faster) and drives on
##   * a side swipe shoves it off its line, and it steers back into its lane
## Run: godot --headless --fixed-fps 120 --path . -s tests/traffic_hit_check.gd

var fails := 0
var Modes


func _initialize() -> void:
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	print("[traffic] %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		fails += 1


func _run() -> void:
	await process_frame
	Modes = load("res://scripts/game/modes.gd")
	root.get_node("Net").solo()
	var g = load("res://scripts/game.gd").new()
	root.add_child(g)
	var o: Dictionary = Modes.cutup_opts(3, "hard")
	await g.start(3, 1, o)
	g.begin_countdown()
	var t := 0.0
	while g.state != "running" and t < 30.0:
		await physics_frame
		t += 1.0 / 120.0
	_ok(g.state == "running" and g.traffic != null, "a cut-up run with traffic")
	await _rear_ender(g)
	await _side_swipe(g)
	g.queue_free()
	await process_frame
	print("[traffic] " + ("TRAFFIC OK" if fails == 0 else "TRAFFIC FAILED (%d)" % fails))
	quit(1 if fails else 0)


## Clears the traffic, then puts one car `lead` m ahead of the player (or beside it, `side`
## m to its right) in the player's lane at `v_car`, the player at `v_me` (km/h), coasting straight.
func _set_up(g, lead: float, side: float, v_me: float, v_car: float) -> Dictionary:
	var tr = g.traffic
	for c in tr.cars.duplicate():
		if c != tr.cars[0]:
			tr._remove(c)
	var c: Dictionary = tr.cars[0]
	var s0: float = g.car_s + 40.0
	var lane: int = 1
	var d: float = tr._ldx(lane, s0)
	c.s = s0 + lead
	c.lane = lane
	c.to = lane
	c.t = 0.0
	c.v = v_car / 3.6
	c.v0 = v_car / 3.6
	c.push_d = 0.0
	c.push_v = 0.0
	c.crashed = false
	c.think = 99.0
	tr._place(c, 0.0)
	var st = g.st
	var p: Vector3 = st.world_at(s0, d - side)
	var fwd: Vector3 = (st.world_at(s0 + 2.0, d - side) - p).normalized()
	g.car.place(p, 0.0)
	g.car.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), p + Vector3.UP * g.car.ride_height())
	g.car.set_speed(v_me / 3.6)
	g.car.linear_velocity = fwd * v_me / 3.6
	return c


func _rear_ender(g) -> void:
	var c := _set_up(g, 14.0, 0.0, 150.0, 100.0)
	await physics_frame
	await physics_frame
	var car_v_before: float = float(c.v) * 3.6
	# each tick's speed; the hit: the first tick it drops; then both cars' speeds just after
	# (settled at their shared speed), and the jolt: the speed lost over 0.1 s
	var v: Array = [g.car.linear_velocity.length() * 3.6]
	var hit := -1
	var car_after := car_v_before
	for i in 300:
		await physics_frame
		v.append(g.car.linear_velocity.length() * 3.6)
		if hit < 0 and v[v.size() - 2] - v[v.size() - 1] > 3.0:
			hit = v.size() - 2
		if hit >= 0 and v.size() - 1 == hit + 6:
			car_after = float(c.v) * 3.6             # (just after: a hit this hard is a crash, and it then pulls up)
		if hit >= 0 and v.size() - 1 >= hit + 6:
			break
	var touched := hit >= 0
	var v_before: float = float(v[hit]) if touched else 0.0
	var lost: float = v_before - float(v[mini(hit + 6, v.size() - 1)]) if touched else 0.0
	var jolt: float = (v_before - float(v[mini(hit + 12, v.size() - 1)])) / 3.6 / 0.1 / 9.8 if touched else 0.0
	var pushed: float = car_after - car_v_before
	print("[traffic] rear-ender at %.0f into %.0f km/h: the player lost %.1f km/h (jolt %.1f g over 0.1 s), the car pushed on %.1f km/h" % [v_before, car_v_before, lost, jolt, pushed])
	_ok(touched, "the player ran into the car ahead")
	_ok(lost >= 15.0 and lost <= 32.0, "the hit cost the player %.1f km/h (15-32: its share by weight, not ~50 as off a wall)" % lost)
	_ok(jolt <= 6.0, "the jolt %.1f g over 0.1 s (at most 6; off a wall ~14)" % jolt)
	_ok(c.crashed, "a hit that hard (%.0f km/h closing) is a crash: the car pulls up, hazards on" % (v_before - car_v_before))
	_ok(pushed >= 12.0, "the traffic car was pushed on %.1f km/h faster (at least 12)" % pushed)


func _side_swipe(g) -> void:
	var c := _set_up(g, 0.0, 2.2, 114.0, 112.0)
	# the player drifts into it from the next lane (sideways at 1.5 m/s, as a lane change does)
	var hit := false
	var widest := 0.0
	for i in 600:
		await physics_frame
		if not hit and i < 120:
			var b: Basis = g.car.global_transform.basis
			var fwd_v: float = g.car.linear_velocity.dot(-b.z)
			g.car.linear_velocity = -b.z * fwd_v + b.x * 1.5
		widest = maxf(widest, absf(float(c.get("push_d", 0.0))))
		if OS.get_cmdline_user_args().has("--trace") and i % 15 == 0:
			print("[traffic] trace i=%d my_d=%.2f car_d=%.2f ds=%.1f steer=%.2f" % [i, g.car_d, float(c.d), float(c.s) - g.car_s, g.car.steer])
		if absf(float(c.get("push_v", 0.0))) > 0.05:
			hit = true
	print("[traffic] side swipe: the car shoved %.2f m off its line, now %.2f m (and %s)" % [widest, absf(float(c.push_d)), "crashed" if c.crashed else "driving on"])
	_ok(hit and widest > 0.05, "a side swipe shoves the car off its line (%.2f m)" % widest)
	_ok(c.crashed or absf(float(c.push_d)) < 0.2, "and it steers back into its lane (%.2f m off after 5 s)" % absf(float(c.push_d)))
