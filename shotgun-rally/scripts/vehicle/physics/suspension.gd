extends RefCounted
## The suspension's force: pure functions of a SuspensionConfig, how far the
## corner is squashed and how fast. No state, so it's easy to test.


## How hard the corner pushes the body up (N, along the strut). compression:
## m from full droop; velocity: m/s, + = squashing. Never negative: the tyre
## can push on the ground but not pull on it, so if the damper would pull
## harder than the spring pushes, the wheel is simply going light.
static func force(cfg: Resource, compression: float, velocity: float) -> float:
	var f: float = cfg.spring_rate * compression
	f += velocity * (cfg.bump_damping if velocity > 0.0 else cfg.rebound_damping)
	var past: float = compression - cfg.bump_stop_start
	if past > 0.0:
		f += cfg.bump_stop_rate * past * past
		if velocity > 0.0:
			f += cfg.bump_stop_damping * velocity
	return clampf(f, 0.0, cfg.max_force)


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
