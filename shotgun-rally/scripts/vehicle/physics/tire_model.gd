extends RefCounted
## The tyre: slip in, force out (pure functions of a TireConfig, no state of
## their own: the wheel keeps the slip state).
##
## Sideways: the slip is the tyre's "tan of the slip angle", kept as a state
## that winds up over the relaxation length (the carcass deflecting):
##     d(slip)/dt = (-v_y - |v_x| slip) / relaxation_length
## At speed it settles at -v_y / |v_x| (the textbook slip angle, lagging by the
## time the tyre takes to roll its relaxation length). Slowly or standing
## still, -v_y keeps winding it up: the patch sticks and the carcass is a
## spring, so a parked car holds on a slope (no creep) instead of the slip
## angle dividing by a speed of zero. Crawling and sliding, the patch slips, so
## the wind-up can't pass where the tyre lets go. Stepped implicitly: stable at
## any speed.
## The force is mu x load x the Magic Formula curve sin(C atan(B slip)): it
## builds, peaks at the tyre's peak slip angle, and fades only gently past it.

## m/s: below this along the wheel, a sliding patch caps the wind-up (see above).
const V_CRAWL := 1.0


## Magic Formula B for shape C peaking at slip x_peak (tan of the peak angle).
static func stiffness_b(shape: float, x_peak: float) -> float:
	return tan(PI / (2.0 * shape)) / x_peak


## The side force for a slip, as a share of mu x load (-1..1).
static func lateral_curve(cfg: Resource, slip: float) -> float:
	var b := stiffness_b(cfg.lateral_shape, tan(deg_to_rad(cfg.lateral_peak_deg)))
	return sin(cfg.lateral_shape * atan(b * slip))


## The cornering stiffness: side force per unit of slip near zero, per newton of
## load and per unit of mu (so x mu x load = N per rad).
static func cornering_stiffness(cfg: Resource) -> float:
	return stiffness_b(cfg.lateral_shape, tan(deg_to_rad(cfg.lateral_peak_deg))) * cfg.lateral_shape


## The sideways slip state one tick on (v_x, v_y: the contact patch's speed
## along and across the wheel, m/s).
static func lateral_slip(cfg: Resource, slip: float, v_x: float, v_y: float, dt: float) -> float:
	var sigma: float = cfg.relaxation_length
	var s := (slip - dt * v_y / sigma) / (1.0 + dt * absf(v_x) / sigma)
	if absf(v_x) < V_CRAWL:
		var limit := maxf(tan(deg_to_rad(cfg.lateral_peak_deg)), absf(v_y) / V_CRAWL)
		s = clampf(s, -limit, limit)
	return s


## The side force (N, + = toward the wheel's right) for that slip, the load and
## the grip, with the carcass's damping when it's slow, never more than mu x load.
static func lateral_force(cfg: Resource, slip: float, load: float, mu: float, v_x: float, v_y: float) -> float:
	var f := mu * load * lateral_curve(cfg, slip)
	var still := 1.0 - clampf(absf(v_x) / 3.0, 0.0, 1.0)
	f -= cfg.standstill_damping * v_y * still
	return clampf(f, -mu * load, mu * load)
