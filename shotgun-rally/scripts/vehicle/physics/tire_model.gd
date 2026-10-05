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
##
## Along the wheel: the same carcass model on the slip ratio, wound up by the
## difference between the tyre's surface speed (spin x radius) and the ground's:
##     d(slip)/dt = ((spin x radius - v_x) - |v_x| slip) / longitudinal_relaxation
## and it's solved together with the wheel's spin, implicitly:
##     inertia x d(spin)/dt = drivetrain - brakes / rolling resistance - force x radius
## The two are stiff together (a gravel tyre settles its slip in a few ms), so
## the car steps them several times a tick: spin_predict() (the tyre alone),
## then the drivetrain's and brakes' impulses (drivetrain.gd), then slip_after().
## The brakes (and rolling resistance) are friction: they slow the wheel, can
## hold it still, never turn it back. A wheel locks only when the brake beats
## what the tyre can take from the road.
##
## Both at once (combined): a tyre has one patch of rubber for both jobs. Each
## slip is measured against its own peak (slip ratio / peak, tan slip angle /
## peak) and the two make one combined slip; each force is its own curve at
## that combined slip, shared out in the direction of the slip. So at the limit
## the forces trace an ellipse (braking hard leaves little for turning, and the
## other way round), and with only one slip it's exactly that slip's curve.
## Load sensitivity scales mu: a heavily loaded tyre grips less per newton.

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


## Load sensitivity: the grip coefficient's factor at this load (1 at the nominal load).
static func load_mu_factor(cfg: Resource, load: float) -> float:
	return clampf(1.0 - cfg.load_sensitivity * (load / cfg.nominal_load - 1.0), 0.5, 1.4)


## Both forces from both slips (N): x along the wheel (slip ratio slip_x),
## y across (side slip state slip_y, + = force to the right).
static func combined(cfg: Resource, slip_x: float, slip_y: float, load: float, mu_x: float, mu_y: float) -> Vector2:
	var px: float = cfg.longitudinal_peak
	var py := tan(deg_to_rad(cfg.lateral_peak_deg))
	var sx := slip_x / px
	var sy := slip_y / py
	var s := sqrt(sx * sx + sy * sy)
	if s < 1e-9:
		return Vector2.ZERO
	return Vector2(mu_x * load * longitudinal_curve(cfg, s * px) * sx / s, mu_y * load * lateral_curve(cfg, s * py) * sy / s)


## The force along the wheel for a slip ratio, as a share of mu x load (-1..1).
static func longitudinal_curve(cfg: Resource, slip: float) -> float:
	var b := stiffness_b(cfg.longitudinal_shape, cfg.longitudinal_peak)
	return sin(cfg.longitudinal_shape * atan(b * slip))


## Its slope (per unit slip ratio): how fast the force grows with slip there.
static func longitudinal_slope(cfg: Resource, slip: float) -> float:
	var c: float = cfg.longitudinal_shape
	var b := stiffness_b(c, cfg.longitudinal_peak)
	var u := b * slip
	return c * b * cos(c * atan(u)) / (1.0 + u * u)


## The wheel's spin over one substep (h s) from its tyre alone (and any extra
## drive torque), solved implicitly: returns [spin, effective inertia]. The
## effective inertia is how heavy the wheel feels to the drivetrain and brakes
## this substep: its own plus the tyre's grip resisting a change of speed. The
## drivetrain's and brakes' impulses then change the spin by impulse / that,
## and slip_after() moves the slip on to match. (slip_y: the side slip, which
## shares the grip.)
static func spin_predict(cfg: Resource, spin: float, slip: float, slip_y: float, v_x: float, load: float, mu: float, mu_y: float,
		inertia: float, radius: float, t_drive: float, h: float) -> Array:
	var sigma: float = cfg.longitudinal_relaxation
	var a := 1.0 + h * absf(v_x) / sigma
	var f0 := combined(cfg, slip, slip_y, load, mu, mu_y).x
	var e := 1e-4                                    # the force's growth with slip (not past the peak)
	var k := maxf((combined(cfg, slip + e, slip_y, load, mu, mu_y).x - combined(cfg, slip - e, slip_y, load, mu, mu_y).x) / (2.0 * e), 0.0)
	var i_eff := inertia + h * h * radius * radius * k / (sigma * a)
	var n := inertia * spin + h * t_drive - h * radius * f0 - h * radius * k * (slip * (1.0 - a) - h * v_x / sigma) / a
	return [n / i_eff, i_eff]


## The slip ratio state after the substep, given the wheel's final spin.
static func slip_after(cfg: Resource, slip: float, spin: float, v_x: float, radius: float, h: float) -> float:
	var sigma: float = cfg.longitudinal_relaxation
	var a := 1.0 + h * absf(v_x) / sigma
	var s := (slip + h * (spin * radius - v_x) / sigma) / a
	if absf(v_x) < V_CRAWL:                          # crawling and spinning / sliding: capped where it lets go
		var limit := maxf(cfg.longitudinal_peak, absf(spin * radius - v_x) / V_CRAWL)
		s = clampf(s, -limit, limit)
	return s


## The force along the wheel (N, + = pushing the car forward) for the slips,
## with the carcass's damping when it's slow, never more than mu x load.
static func long_force(cfg: Resource, slip: float, slip_y: float, spin: float, v_x: float, load: float, mu: float, mu_y: float,
		radius: float) -> float:
	var f := combined(cfg, slip, slip_y, load, mu, mu_y).x
	# slow or stopped, the wound-up carcass is a spring along the wheel too: damp it
	# (a braked car on a slope would rock on its tyres otherwise)
	var still := 1.0 - clampf(absf(v_x) / 3.0, 0.0, 1.0)
	return clampf(f + cfg.standstill_damping * (spin * radius - v_x) * still, -mu * load, mu * load)


## The wheel in the air: only the drive and the friction torques act on it.
static func air_spin(spin: float, inertia: float, t_drive: float, t_resist: float, h: float) -> float:
	var n := inertia * spin + h * t_drive
	var stop := h * t_resist
	return 0.0 if absf(n) <= stop else (n - signf(n) * stop) / inertia


## The side force (N, + = toward the wheel's right) for the slips, the load and
## the grip, with the carcass's damping when it's slow, never more than mu x load.
static func lateral_force(cfg: Resource, slip_x: float, slip: float, load: float, mu_x: float, mu: float, v_x: float, v_y: float) -> float:
	var f := combined(cfg, slip_x, slip, load, mu_x, mu).y
	var still := 1.0 - clampf(absf(v_x) / 3.0, 0.0, 1.0)
	f -= cfg.standstill_damping * v_y * still
	return clampf(f, -mu * load, mu * load)
