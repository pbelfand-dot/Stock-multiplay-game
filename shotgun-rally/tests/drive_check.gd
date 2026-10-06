extends SceneTree
## The car and the stage, together: the autopilot drives a whole stage.
## Run: godot --headless --fixed-fps 120 --path . -s tests/drive_check.gd -- --seed=3
##   [--surface=tarmac | mixed] [--ice]   an asphalt or mixed stage (snow and ice on the asphalt)
##   * it gets off the line (0-100 km/h in a sane time) and reaches the finish
##   * it stays on the road (few offs) and never falls through the world
##   * the springs hold the car at ride height, the handbrake flicks it
##   * the tyres feel the road's surface (gravel, asphalt, what's lying on it)
## Prints one [drive] line per check; exits 1 on any FAIL.

# loaded at run time, not preloaded: the game scripts use the autoloads (Net...),
# which only exist once the tree is up
var StageGen
var StageBuilder
var RallyCar
var Autopilot

var st
var car
var ap
var t := 0.0
var phase := "settle"
var fails := 0
var hint := -1
var offs := 0
var off_now := false
var t100 := -1.0
var max_kmh := 0.0
var lowest := INF
var ride := 0.0
var flick_yaw := 0.0
var stuck := 0.0
var resets := 0
var surf_seen := {}                 # what the tyres were on (car.on_surface), physics ticks


func _initialize() -> void:
	StageGen = load("res://scripts/stage/stage_gen.gd")
	StageBuilder = load("res://scripts/stage/stage_builder.gd")
	RallyCar = load("res://scripts/vehicle/rally_car.gd")
	Autopilot = load("res://scripts/vehicle/autopilot.gd")
	var seed_value := 3
	var gen := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.split("=")[1])
		if a.begins_with("--surface="):
			gen["surface"] = a.split("=")[1]
		if a == "--ice":
			gen["ice"] = true
	st = StageGen.new()
	st.opts = gen
	st.generate(seed_value)
	var b = StageBuilder.new()
	root.add_child(b)
	b.build(st)
	car = RallyCar.new()
	root.add_child(car)
	car.place(st.world_at(st.START_S - 4.0, 0.0), st.heading_at(st.START_S))
	ap = Autopilot.new(st)
	var secs: Array = st.sections.map(func(x): return "%s %.0f-%.0f" % [x.surface, x.s0, x.s1])
	print("[drive] stage seed %d: %.0f m, %d trees, %s, %d patches" % [seed_value, st.length, b.tree_count, ", ".join(secs), st.patches.size()])


func _physics_process(dt: float) -> bool:
	if car == null:
		print("[drive] FAIL setup")
		quit(1)
		return true
	t += dt
	var at: Dictionary = st.locate(car.global_position, hint)
	hint = at.i
	car.set_lanes(st, at.s, at.d)                    # the clean wheel tracks grip, the loose gravel doesn't
	lowest = minf(lowest, car.global_position.y - st.point_at(at.s).y)
	match phase:
		"settle":
			car.inp = {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": false}
			if t > 1.5:
				ride = car.global_position.y - st.point_at(at.s).y
				var ok: bool = ride > 0.4 and ride < 0.75 and car.grounded == 4
				fails += _check(ok, "ride height %.2f m on %d tyres" % [ride, car.grounded])
				phase = "run"
				t = 0.0
		"run":
			car.inp = ap.drive(car, at.s, at.d)
			var kmh: float = car.kmh()
			if OS.get_cmdline_user_args().has("--trace") and int(t * 60.0) % 30 == 0:
				var road_yaw: float = st.heading_at(at.s)
				var car_yaw: float = -car.global_rotation.y
				var vlat: float = car.linear_velocity.dot(car.global_transform.basis.x)
				print("[drive]   t %5.1f s %6.0f d %5.1f %4.0f km/h steer %+.2f thr %.2f brk %.2f tyres %d %s yaw-road %+5.1f deg vlat %+.1f k %+.4f" % [
					t, at.s, at.d, kmh, car.inp.steer, car.inp.throttle, car.inp.brake, car.grounded, car.on_surface,
					rad_to_deg(wrapf(car_yaw - road_yaw, -PI, PI)), vlat, st.curv[at.i]])
			max_kmh = maxf(max_kmh, kmh)
			surf_seen[car.on_surface] = int(surf_seen.get(car.on_surface, 0)) + 1
			if t100 < 0.0 and kmh >= 100.0:
				t100 = t
			var off: bool = absf(at.d) > st.width_at(at.s) * 0.5 + 1.4
			if off and not off_now:
				offs += 1
			off_now = off
			if at.s >= st.finish_s:
				fails += _check(true, "finished in %.1f s (avg %.0f km/h), top %.0f km/h, %d offs, %d resets" % [
					t, (st.finish_s - st.START_S) / t * 3.6, max_kmh, offs, resets])
				fails += _check(offs <= 5, "%d offs (<= 5: the autopilot is a careful test driver, not a racer)" % offs)
				fails += _check(lowest > -1.0, "never fell through (lowest %.2f m)" % lowest)
				# the tyres felt the road's surfaces (each the road body's own meta)
				var total := 0.0
				for k in surf_seen:
					total += surf_seen[k]
				var share := func(k): return float(surf_seen.get(k, 0)) / maxf(total, 1.0)
				var want: String = st.opts.get("surface", "gravel")
				var felt: bool = (share.call("gravel") > 0.85 if want == "gravel" else (share.call("asphalt") > 0.75 if want == "tarmac"
					else share.call("asphalt") > 0.15 and share.call("gravel") > 0.15))
				if st.opts.get("ice", false):
					felt = felt and share.call("ice") + share.call("snow") > 0.0
				var parts: Array = surf_seen.keys().map(func(k): return "%s %.0f%%" % [k, share.call(k) * 100.0])
				fails += _check(felt, "the tyres felt the road: %s" % ", ".join(parts))
				phase = "accel"
				t = 0.0
				t100 = -1.0
				var pad := StaticBody3D.new()
				pad.set_meta("surface", "gravel")
				var cs := CollisionShape3D.new()
				var bx := BoxShape3D.new()
				bx.size = Vector3(600, 2, 600)
				cs.shape = bx
				pad.add_child(cs)
				pad.position = Vector3(0, -501, 0) + Vector3(5000, 0, 5000)
				root.add_child(pad)
				car.place(Vector3(5000, -500, 5250), 0.0)
			elif t > 400.0:
				fails += _check(false, "out of time at s=%.0f d=%.1f" % [at.s, at.d])
				return _finish()
			# stuck for 4 s (spun, beached): put it back on the road like the R key does
			stuck = stuck + dt if car.linear_velocity.length() < 0.5 and t > 3.0 else 0.0
			if stuck > 4.0:
				resets += 1
				print("[drive]   reset %d at s=%.0f d=%.1f" % [resets, at.s, at.d])
				stuck = 0.0
				car.place(st.world_at(at.s + 5.0, 0.0), st.heading_at(at.s + 5.0))
				if resets > 2:
					fails += _check(false, "needed more than 2 resets")
					return _finish()
		"accel":
			# flat out from a standstill on gravel, then brake to 50 km/h
			if t100 < 0.0:
				car.inp = {"steer": 0.0, "throttle": 1.0, "brake": 0.0, "handbrake": false}
				if car.kmh() >= 100.0:
					t100 = t
					fails += _check(t100 < 8.0, "0-100 km/h in %.1f s on gravel" % t100)
				elif t > 15.0:
					fails += _check(false, "0-100 km/h: only %.0f km/h after 15 s" % car.kmh())
					return _finish()
			else:
				car.inp = {"steer": 0.0, "throttle": 0.0, "brake": 1.0, "handbrake": false}
				if car.kmh() <= 50.0:
					fails += _check(absf(car.global_rotation.y) < 0.15, "braked straight (%.0f deg off)" % rad_to_deg(car.global_rotation.y))
					phase = "flick"
					t = 0.0
					flick_yaw = car.global_rotation.y
		"flick":
			# handbrake + full lock at 50 km/h: the tail must come round (a hairpin flick).
			# The rears lock at once; the body takes a moment to start turning (~55 deg in
			# 1.2 s, ~85 in 1.5 s, ~120 in 2 s)
			if t < 1.5:
				car.inp = {"steer": 1.0, "throttle": 0.0, "brake": 0.0, "handbrake": true}
			else:
				var turned := absf(wrapf(car.global_rotation.y - flick_yaw, -PI, PI))
				fails += _check(turned > deg_to_rad(60.0), "handbrake flick at 50 km/h turned %.0f deg in 1.5 s" % rad_to_deg(turned))
				return _finish()
	return false


func _check(ok: bool, msg: String) -> int:
	print("[drive] %s %s" % ["ok  " if ok else "FAIL", msg])
	return 0 if ok else 1


func _finish() -> bool:
	print("[drive] %s" % ("DRIVE OK" if fails == 0 else "DRIVE FAIL"))
	quit(1 if fails > 0 else 0)
	return true
