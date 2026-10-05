extends RefCounted
## The suspension's force: pure functions of a SuspensionConfig, how far the
## corner is squashed and how fast. No state, so it's easy to test.


## How hard the corner pushes the body up (N, along the strut). compression:
## m from full droop; velocity: m/s, + = squashing; extra: the anti-roll bar's
## push on this corner. Never negative: the tyre can push on the ground but not
## pull on it, so if the damper would pull harder than the spring pushes, the
## wheel is simply going light.
static func force(cfg: Resource, compression: float, velocity: float, extra := 0.0) -> float:
	var f: float = cfg.spring_rate * compression + damping(cfg, velocity) + extra
	var past: float = compression - cfg.bump_stop_start
	if past > 0.0:
		f += cfg.bump_stop_rate * past * past
		if velocity > 0.0:
			f += cfg.bump_stop_damping * velocity
	return clampf(f, 0.0, cfg.max_force)


## The damper's force (N, + = resisting squashing): firm up to the knee, then the
## high-speed rate on top.
static func damping(cfg: Resource, velocity: float) -> float:
	var slow: float = cfg.bump_damping if velocity > 0.0 else cfg.rebound_damping
	var fast: float = cfg.high_speed_bump if velocity > 0.0 else cfg.high_speed_rebound
	var v := absf(velocity)
	return signf(velocity) * (slow * minf(v, cfg.damper_knee) + fast * maxf(v - cfg.damper_knee, 0.0))


## How stiff the axle is against the body rolling (N m per radian): its springs
## and its anti-roll bar, at this track width.
static func roll_stiffness(cfg: Resource, track: float) -> float:
	return (cfg.spring_rate * 0.5 + cfg.anti_roll_rate) * track * track


## Where a corner settles under a load (N), standing still: the spring alone
## (and the bump stop, if it's that heavy).
static func static_compression(cfg: Resource, load: float) -> float:
	var c: float = load / cfg.spring_rate
	if c <= cfg.bump_stop_start:
		return c
	for i in 30:                                     # into the bump stop: solve k c + r (c - s)^2 = load
		var past: float = c - cfg.bump_stop_start
		var f: float = cfg.spring_rate * c + cfg.bump_stop_rate * past * past - load
		var df: float = cfg.spring_rate + 2.0 * cfg.bump_stop_rate * past
		c -= f / df
	return c


## The body's natural bounce on this spring with `mass` (kg) on the corner (Hz).
static func ride_frequency(cfg: Resource, mass: float) -> float:
	return sqrt(cfg.spring_rate / mass) / TAU


## How damped that bounce is, squashing and stretching (1 = critically: no overshoot).
static func damping_ratios(cfg: Resource, mass: float) -> Vector2:
	var critical := 2.0 * sqrt(cfg.spring_rate * mass)
	return Vector2(cfg.bump_damping / critical, cfg.rebound_damping / critical)
