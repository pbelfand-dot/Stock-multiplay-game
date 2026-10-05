extends RefCounted
## The engine: pure functions of an EngineConfig (the drivetrain keeps the
## engine's spin and boost).

const TO_RPM := 60.0 / TAU         # rad/s -> rpm


## Torque at full throttle and full boost, as a share of max_torque, at these revs
## (straight lines between the points, flat past the ends).
static func curve(cfg: Resource, rpm: float) -> float:
	var r: PackedFloat32Array = cfg.rpm_points
	var t: PackedFloat32Array = cfg.torque_points
	if rpm <= r[0]:
		return t[0]
	for i in range(1, r.size()):
		if rpm <= r[i]:
			return lerpf(t[i - 1], t[i], (rpm - r[i - 1]) / (r[i] - r[i - 1]))
	return t[t.size() - 1]


## The torque it makes (N m) at these revs, throttle (0..1) and boost (0..1).
static func torque(cfg: Resource, rpm: float, throttle: float, boost: float) -> float:
	var f: float = (1.0 - cfg.turbo_share) + cfg.turbo_share * boost
	return throttle * cfg.max_torque * curve(cfg, rpm) * f


## What it loses to friction (N m, against its spin): more with the throttle shut.
static func friction(cfg: Resource, rpm: float, throttle: float) -> float:
	var r := maxf(rpm, 0.0)
	return cfg.friction + cfg.friction_per_rpm * r + (1.0 - throttle) * cfg.closed_throttle_per_rpm * r


## Where the boost is heading at these revs and throttle (0..1).
static func boost_target(cfg: Resource, rpm: float, throttle: float) -> float:
	var spool := clampf((rpm - cfg.spool_start_rpm) / maxf(cfg.spool_full_rpm - cfg.spool_start_rpm, 1.0), 0.0, 1.0)
	return spool * (maxf(throttle, 0.7) if cfg.anti_lag else throttle)


## Power (kW) at these revs, full throttle, full boost.
static func power_kw(cfg: Resource, rpm: float) -> float:
	return torque(cfg, rpm, 1.0, 1.0) * rpm / TO_RPM / 1000.0
