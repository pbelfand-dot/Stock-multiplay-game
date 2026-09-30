extends Node
## Car handling on a flat test track, fast-forwarded (4x, still 60 physics
## steps per simulated second):
##   godot --headless --path . -- --drivecheck [--car=bz_m3]
## 0-60, top speed, 60-0 braking, cornering grip, a head-on crash into a wall
## (it has to slow you way down), a glancing scrape (keeps most of your
## speed), a handbrake slide.

const Car = preload("res://scripts/vehicle/car.gd")
const Rules = preload("res://scripts/sim/rules.gd")

var car
var fails: Array = []


func _ready() -> void:
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
	_ground()
	_run.call_deferred()


func _ground() -> void:
	var g := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(4000, 1, 4000)
	cs.shape = b
	cs.position.y = -0.5
	g.add_child(cs)
	add_child(g)


func _wall(pos: Vector3, size: Vector3, rot_y := 0.0) -> StaticBody3D:
	var w := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	w.add_child(cs)
	w.position = pos
	w.rotation.y = rot_y
	add_child(w)
	return w


func _spawn(key: String, pos: Vector3, yaw := 0.0) -> void:
	if car:
		car.queue_free()
		await get_tree().physics_frame
	car = (load(Config.cli.carscript) if Config.cli.has("carscript") else Car).new()   # (--carscript: A/B another car.gd)
	car.setup(key, 1)
	car.simulate = true
	car.position = pos
	car.rotation.y = yaw
	add_child(car)
	await _secs(0.3)


func _secs(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().physics_frame
		t += 1.0 / 60.0


func _inputs(th: float, br: float, st: float, hb := false) -> void:
	car.in_throttle = th
	car.in_brake = br
	car.in_steer = st
	car.in_handbrake = hb


func _check(ok: bool, msg: String) -> void:
	print("[drive] %s %s" % ["ok  " if ok else "FAIL", msg])
	if not ok:
		fails.append(msg)


func _run() -> void:
	var key: String = Config.cli.get("car", "bz_m3")
	var d: Dictionary = Rules.CARS[key]
	if Config.cli.has("lanechange"):
		for mph in [60.0, 100.0, 150.0]:
			await _lane_change(key, mph)
		Engine.time_scale = 1.0
		Sfx.quit_game(0)
		return
	if Config.cli.has("handling"):
		await _handling(key)
		Engine.time_scale = 1.0
		Sfx.quit_game(0)
		return
	await _spawn(key, Vector3(0, 0.1, 0))
	# 0-60
	_inputs(1, 0, 0)
	var t := 0.0
	while car.mph() < 60.0 and t < 30.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	_check(absf(t - d.zero60) < d.zero60 * 0.35, "0-60 mph in %.1f s (spec %.1f)" % [t, d.zero60])
	# top speed
	await _secs(30.0)
	_check(car.speed > d.top * 0.9 and car.speed < d.top * 1.05, "top speed %.0f mph (spec %.0f)" % [car.mph(), d.top * 2.237])
	# 60-0
	await _spawn(key, Vector3(0, 0.1, 0))
	car.speed = 26.8
	car.velocity = -car.global_basis.z * 26.8
	var from: Vector3 = car.global_position
	_inputs(0, 1, 0)
	t = 0.0
	while car.speed > 0.2 and t < 10.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	var dist: float = car.global_position.distance_to(from)
	_check(dist > 25.0 and dist < 55.0, "60-0 in %.0f m / %.1f s" % [dist, t])
	# cornering at 25 m/s, full lock: turns, and the sideways pull stays near the grip limit
	await _spawn(key, Vector3(0, 0.1, 0))
	car.speed = 25.0
	car.velocity = -car.global_basis.z * 25.0
	_inputs(0.35, 0, 1.0)
	var yaw0: float = car.rotation.y
	await _secs(1.5)
	var turned := absf(angle_difference(yaw0, car.rotation.y))
	var lat_g: float = car.speed * car.speed * 0.0 + absf(car._lat_acc) / 9.8
	_check(turned > 0.4 and lat_g < d.grip * 1.3, "full lock at 56 mph: turned %.0f deg, %.2f g sideways (grip %.2f)" % [rad_to_deg(turned), lat_g, d.grip])
	_check(car.rotation.y < yaw0, "steering right turns right")
	# head-on into a wall at 25 m/s
	await _spawn(key, Vector3(0, 0.1, 0))
	_wall(Vector3(0, 1, -40), Vector3(20, 2, 1))
	var hits: Array = []
	car.crashed.connect(func(i): hits.append(i))
	car.speed = 25.0
	car.velocity = -car.global_basis.z * 25.0
	_inputs(1, 0, 0)
	for k in 22:
		await _secs(0.1)
		if Config.cli.has("verbose"):
			print("  z %.2f speed %.1f" % [car.global_position.z, car.speed])
	_check(not hits.is_empty() and car.global_position.z > -40.0, "head-on: crashed (impact %.0f m/s), didn't go through the wall" % (hits.max() if not hits.is_empty() else 0.0))
	_check(absf(car.speed) < 6.0, "head-on: speed down to %.1f m/s" % car.speed)
	# glancing scrape along a wall at 10 degrees: keeps most of its speed
	await _spawn(key, Vector3(500, 0.1, 0), 0.0)
	_wall(Vector3(496, 1, -60), Vector3(1, 2, 200))
	car.rotation.y = deg_to_rad(10.0)                      # nose drifting left toward the wall
	car.speed = 30.0
	car.velocity = -car.global_basis.z * 30.0
	_inputs(0.6, 0, 0)
	hits.clear()
	car.crashed.connect(func(i): hits.append(i))
	await _secs(2.0)
	_check(not hits.is_empty() and car.speed > 30.0 * 0.55 and car.global_position.x > 496.0,
			"scrape at 10 deg: hit the wall (%d), kept %.0f of 30 m/s, slid along it" % [hits.size(), car.speed])
	# handbrake at speed: the rear lets go
	await _spawn(key, Vector3(200, 0.1, 0))
	car.speed = 22.0
	car.velocity = -car.global_basis.z * 22.0
	_inputs(0, 0, 0.8, true)
	await _secs(0.8)
	_check(absf(car.slip) > 2.0, "handbrake slide: %.1f m/s sideways" % car.slip)
	if key == "bz_m3":
		await _pursuit()
	print("[drive] %s" % ("DRIVE PASS" if fails.is_empty() else "DRIVE FAIL: " + ", ".join(fails)))
	Engine.time_scale = 1.0
	Sfx.quit_game(0 if fails.is_empty() else 1)


## How it feels, in numbers (--handling, not part of the suite): a quick tap
## of the key at highway speed (how far it moves over, how hard it yaws), a
## light held turn (proportional?), how fast full lock builds at 30 m/s.
func _handling(key: String) -> void:
	var d: Dictionary = Rules.CARS[key]
	var v: float = minf(65.0, d.top * 0.95)
	# a 0.15 s tap of full right at speed, then hands off for 1.5 s
	await _spawn(key, Vector3(0, 0.1, 0))
	car.speed = v
	car.velocity = -car.global_basis.z * v
	_inputs(0.4, 0, 1.0)
	var peak_yaw := 0.0
	var peak_g := 0.0
	var yaw0: float = car.rotation.y
	var t := 0.0
	var last_yaw: float = car.rotation.y
	while t < 1.65:
		if t >= 0.15:
			_inputs(0.4, 0, 0.0)
		await get_tree().physics_frame
		t += 1.0 / 60.0
		peak_yaw = maxf(peak_yaw, absf(angle_difference(last_yaw, car.rotation.y)) * 60.0)
		last_yaw = car.rotation.y
		peak_g = maxf(peak_g, absf(car._lat_acc) / 9.8)
	var side: float = car.global_position.x
	print("[handling] %s tap at %.0f mph: peak yaw %.1f deg/s, peak %.2f g, heading %+.1f deg, %.2f m over after 1.5 s" % [key,
			v * 2.237, rad_to_deg(peak_yaw), peak_g, rad_to_deg(angle_difference(yaw0, car.rotation.y)), side])
	# a light held turn (30% right) at speed, and at 30 m/s: lateral g, steady?
	for vv in [v, 30.0]:
		for amt in [0.3, 1.0]:
			await _spawn(key, Vector3(0, 0.1, 0))
			car.speed = vv
			car.velocity = -car.global_basis.z * vv
			_inputs(0.5 if vv > 40.0 else 0.35, 0, amt)
			var t90 := -1.0
			t = 0.0
			var gs: Array = []
			while t < 2.0:
				await get_tree().physics_frame
				t += 1.0 / 60.0
				gs.append(absf(car._lat_acc) / 9.8)
			var g_end: float = gs[gs.size() - 1]
			for i in gs.size():
				if gs[i] >= g_end * 0.9:
					t90 = i / 60.0
					break
			print("[handling] %s %d%% right at %.0f mph: %.2f g sideways (reached 90%% in %.2f s), slip %.1f m/s" % [key, int(amt * 100),
					vv * 2.237, g_end, t90, car.slip])


## One lane over (3.7 m to the right) at `mph` on the keyboard (--lanechange,
## not part of the suite). The driver taps: the key is held for a share of
## every 0.1 s that grows with how far he still wants to go (where he is +
## where he's heading `lead` s from now, short of the lane), the other key to
## straighten up. He tries a few leads / how hard he taps (a driver who knows
## the car) and the best run is printed: how long until settled in the next
## lane (within 0.3 m, drifting < 0.6 m/s), the peak sideways g (from the
## velocity itself), the most front wheel / steering wheel it used, the
## speed it cost.
func _lane_change(key: String, mph: float) -> void:
	var d: Dictionary = Rules.CARS[key]
	var v0 := mph / 2.237
	if v0 > d.top * 0.98:
		print("[lane] %s %3.0f mph: n/a (top speed %.0f mph)" % [key, mph, d.top * 2.237])
		return
	# how quick it answers: the key held from straight ahead, how long until
	# it pulls 0.5 g and until it's 1 m over
	await _spawn(key, Vector3(0, 0.1, 0))
	car.speed = v0
	car.velocity = -car.global_basis.z * v0
	await _secs(0.2)
	car.speed = v0
	car.velocity = -car.global_basis.z * v0
	var x0: float = car.global_position.x
	var t := 0.0
	var t_g := -1.0
	var t_m := -1.0
	var pv: Vector3 = car.velocity
	var acc := 0.0
	while t < 2.0 and (t_g < 0.0 or t_m < 0.0):
		_inputs(0.3, 0, 1.0)
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var hv := Vector3(car.velocity.x, 0, car.velocity.z)
		acc = lerpf(acc, absf(((hv - Vector3(pv.x, 0, pv.z)) * 60.0).dot(hv.normalized().cross(Vector3.UP))), 0.35)
		pv = car.velocity
		if t_g < 0.0 and acc > 0.5 * 9.8:
			t_g = t
		if t_m < 0.0 and car.global_position.x - x0 > 1.0:
			t_m = t
	print("[lane] %s %3.0f mph: key held: 0.5 g after %.2f s, 1 m over after %.2f s" % [key, mph, t_g, t_m])
	var best: Dictionary = {}
	for lead in [0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.1] if not Config.cli.has("lead") else [float(Config.cli.lead)]:
		for gain in [0.6, 0.9, 1.2, 2.5] if not Config.cli.has("gain") else [float(Config.cli.gain)]:
			var r: Dictionary = await _lane_try(key, v0, lead, gain)
			if Config.cli.has("verbose"):
				print("   lead %.1f taps x%.1f: %.2f s  %s" % [lead, gain, r.t, r.trace])
			if best.is_empty() or r.t < best.t:
				best = r
	print("[lane] %s %3.0f mph: %s, peak %.2f g, front wheels %.1f deg, steering wheel %.0f deg, -%.1f mph   (lead %.1f s, taps x%.1f)" % [
			key, mph, ("one lane in %.2f s" % best.t) if best.t < 99.0 else "NOT SETTLED", best.g, best.rw, best.sw, best.lost,
			best.lead, best.gain])
	if Config.cli.has("verbose"):
		print("   ", best.trace)


func _lane_try(key: String, v0: float, lead: float, gain: float) -> Dictionary:
	await _spawn(key, Vector3(0, 0.1, 0))
	car.speed = v0
	car.velocity = -car.global_basis.z * v0
	await _secs(0.2)
	car.speed = v0
	car.velocity = -car.global_basis.z * v0
	var x0: float = car.global_position.x
	var t := 0.0
	var done := -1.0
	var calm := 0.0
	var r := {"t": 99.0, "g": 0.0, "rw": 0.0, "sw": 0.0, "lost": 0.0, "lead": lead, "gain": gain, "trace": ""}
	var prev_v: Vector3 = car.velocity
	var acc_s := 0.0
	var frame := 0
	var trace: Array = []
	while t < 6.0:
		var x: float = car.global_position.x - x0
		var u := clampf((3.7 - (x + car.velocity.x * lead)) * gain, -1.0, 1.0)
		var on := frame % 6 < int(round(absf(u) * 6.0))
		var key_in := signf(u) if on else 0.0
		_inputs(clampf((v0 - car.speed) * 0.4, 0.0, 1.0), 0, key_in)
		await get_tree().physics_frame
		frame += 1
		t += 1.0 / 60.0
		var vv: Vector3 = car.velocity
		var hv := Vector3(vv.x, 0, vv.z)
		var a := (hv - Vector3(prev_v.x, 0, prev_v.z)) * 60.0
		prev_v = vv
		var lat := absf(a.dot(hv.normalized().cross(Vector3.UP))) if hv.length() > 1.0 else 0.0
		acc_s = lerpf(acc_s, lat, 0.35)           # (a few frames' average: the peak, not one tick's noise)
		r.g = maxf(r.g, acc_s / 9.8)
		r.rw = maxf(r.rw, rad_to_deg(absf(car.steer)))
		r.sw = maxf(r.sw, rad_to_deg(absf(car.wheel_turn)))
		x = car.global_position.x - x0
		if frame % 6 == 0:
			trace.append("%.1f:%.2f" % [t, x])
		if absf(x - 3.7) < 0.3 and absf(car.velocity.x) < 0.6:
			calm += 1.0 / 60.0
			if done < 0.0:
				done = t
			if calm > 0.6:
				break
		else:
			calm = 0.0
			done = -1.0
	if done >= 0.0 and calm > 0.6:
		r.t = done
	r.lost = (v0 - car.speed) * 2.237
	r.trace = " ".join(trace)
	return r


## A patrol car chases a car doing big lazy S-bends at 30 m/s from 80 m back
## (it has to catch up); then a wall between them (it has to get round it).
func _pursuit() -> void:
	var AI = load("res://scripts/vehicle/ai_driver.gd")
	await _spawn("bz_m3", Vector3(1000, 0.1, 0))
	var runner = car
	car = null
	var cop = Car.new()
	cop.setup("cop", 99)
	cop.simulate = true
	cop.position = Vector3(1000, 0.1, 80)
	add_child(cop)
	var ai = AI.new()
	ai.target = runner
	cop.add_child(ai)
	runner.speed = 30.0
	runner.velocity = -runner.global_basis.z * 30.0
	var closest := 999.0
	var t := 0.0
	while t < 20.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		runner.in_throttle = 0.6 if runner.speed < 30.0 else 0.0
		runner.in_steer = sin(t * 0.6) * 0.35
		closest = minf(closest, cop.global_position.distance_to(runner.global_position))
	_check(closest < 12.0, "patrol car caught up from 80 m back (closest %.1f m)" % closest)
	# the target stops behind a wall: the cop has to go round
	runner.speed = 0.0
	runner.velocity = Vector3.ZERO
	runner.in_throttle = 0.0
	runner.in_brake = 1.0
	runner.in_steer = 0.0
	var rp: Vector3 = runner.global_position
	cop.global_position = rp + Vector3(0, 0.05, 45)
	cop.rotation.y = 0.0
	cop.speed = 0.0
	cop.velocity = Vector3.ZERO
	_wall(rp + Vector3(0, 1, 22), Vector3(14, 2, 1))
	var got := 999.0
	t = 0.0
	while t < 20.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		got = minf(got, cop.global_position.distance_to(runner.global_position))
	_check(got < 9.0 and runner.global_position.z > cop.global_position.z - 30.0,
			"patrol car got round a wall to a stopped car (closest %.1f m)" % got)
	cop.queue_free()
	runner.queue_free()
