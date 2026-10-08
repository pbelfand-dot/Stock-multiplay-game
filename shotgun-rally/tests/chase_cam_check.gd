extends SceneTree
## The chase camera (seat_cam.gd "chase"): it stays the same distance behind the car at
## any speed (it used to ease after the car's position, so it fell back further the
## faster you went), CHASE CAM HEIGHT (Config.chase_height) raises and lowers it, and a
## turn still swings it round after the car.
##   godot --headless --fixed-fps 120 --path . -s tests/chase_cam_check.gd

var SeatCam                                    # (loaded once the autoloads are up: it uses Config)

var fails := 0


class FakeCar extends Node3D:                   # (its interpolated transform: Node3D's own, the transform itself here)
	var linear_velocity := Vector3.ZERO
	var on_surface := "asphalt"


func _initialize() -> void:
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	print("[chase] %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		fails += 1


## Drives the fake car straight along -Z at kmh for secs; returns the camera's distance
## behind the car and its height above it at the end.
func _drive(style: String, kmh: float, secs: float, height := 0.0, turn := 0.0) -> Dictionary:
	var config = root.get_node("Config")
	config.chase_height = height
	var car := FakeCar.new()
	root.add_child(car)
	var cam = SeatCam.new()
	root.add_child(cam)
	cam.attach(car, "driver", Vector3(-0.4, 1.1, 0.2))
	cam.view = "chase"
	cam.chase_style = style
	var v := kmh / 3.6
	var dt := 1.0 / 60.0
	var lag_deg := 0.0
	for i in int(secs / dt):
		car.rotate_y(turn * dt)
		var fwd := -car.global_transform.basis.z
		car.linear_velocity = fwd * v
		car.global_position += car.linear_velocity * dt
		cam._process(dt)
	var rel: Vector3 = cam.global_position - car.global_position
	var fwd2 := -car.global_transform.basis.z
	var flat := Vector3(rel.x, 0.0, rel.z)
	lag_deg = rad_to_deg((-flat.normalized()).signed_angle_to(fwd2, Vector3.UP))
	var out := {"back": flat.length(), "up": rel.y, "lag": absf(lag_deg)}
	cam.queue_free()
	car.queue_free()
	await process_frame
	return out


func _run() -> void:
	await process_frame
	SeatCam = load("res://scripts/vehicle/seat_cam.gd")
	for style in ["street", "rally"]:
		var d := {}
		for kmh in [50.0, 150.0, 250.0]:
			d[kmh] = await _drive(style, kmh, 4.0)
			print("[chase] %s %d km/h: %.2f m behind, %.2f m up" % [style, kmh, d[kmh].back, d[kmh].up])
		_ok(absf(d[250.0].back - d[50.0].back) < 0.15, "%s: the same distance behind at 50, 150 and 250 km/h (%.2f / %.2f / %.2f m)" % [style, d[50.0].back, d[150.0].back, d[250.0].back])
		var lo = await _drive(style, 150.0, 3.0, -0.6)
		var hi = await _drive(style, 150.0, 3.0, 1.5)
		_ok(absf((hi.up - lo.up) - 2.1) < 0.05, "%s: CHASE CAM HEIGHT moves it %.2f m (low %.2f, high %.2f m above the car)" % [style, hi.up - lo.up, lo.up, hi.up])
		_ok(absf(hi.back - lo.back) < 0.05, "%s: and doesn't change the distance (%.2f / %.2f m)" % [style, lo.back, hi.back])
		# a steady turn (0.5 rad/s at 100 km/h, ~1.4 g): the camera swings round after the car, a few degrees behind
		var t = await _drive(style, 100.0, 4.0, 0.0, 0.5)
		_ok(t.lag > 1.0 and t.lag < 12.0 and absf(t.back - d[50.0].back) < 0.15, "%s: in a turn it swings round after the car (%.1f deg behind), still %.2f m back" % [style, t.lag, t.back])
	root.get_node("Config").chase_height = 0.0
	print("[chase] " + ("CHASE OK" if fails == 0 else "CHASE FAILED (%d)" % fails))
	quit(1 if fails else 0)
