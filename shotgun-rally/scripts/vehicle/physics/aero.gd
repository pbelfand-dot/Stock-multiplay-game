extends RefCounted
## The air: drag against the car's motion and downforce pressing it down, both
## growing with the square of the speed (pure functions of a CarConfig). At
## 30 km/h they're nothing; at 150 km/h a Rally2 car's wings and splitter press
## it down with ~60 kg and the drag is the biggest force holding it back.

const AIR_DENSITY := 1.225         # kg/m³, sea level, 15 °C


## Dynamic pressure at this airspeed (Pa).
static func pressure(speed: float) -> float:
	return 0.5 * AIR_DENSITY * speed * speed


## The drag force (N), against the car's motion through the air.
static func drag(cfg: Resource, velocity: Vector3) -> Vector3:
	return -velocity * velocity.length() * 0.5 * AIR_DENSITY * cfg.drag_coefficient * cfg.frontal_area


## The downforce (N) at this forward speed (m/s): [front axle, rear axle].
static func downforce(cfg: Resource, forward_speed: float) -> Vector2:
	var f: float = pressure(forward_speed) * cfg.downforce_area
	return Vector2(f * cfg.aero_balance, f * (1.0 - cfg.aero_balance))
