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
##
## On a surface (SurfaceConfig): the tyre's figures are for loose gravel, and
## on_surface() gives the same tyre on another surface: its grip, where the grip
## peaks and how much a sliding tyre keeps, scaled by the surface's.

## m/s: below this along the wheel, a sliding patch caps the wind-up (see above).
const V_CRAWL := 1.0

static var _on := {}


## The tyre on a surface: a copy of its figures with the surface's grip, peaks,
## slide grip and rolling resistance (made once per tyre and surface, then kept).
static func on_surface(cfg: Resource, surface: Resource) -> Resource:
	if surface == null:
		return cfg
	var key := [cfg.get_instance_id(), surface.get_instance_id()]
	if _on.has(key):
		return _on[key]
	var t: Resource = cfg.duplicate()
	var made: float = cfg.sealed_grip if surface.sealed else cfg.loose_grip    # (a tyre for this kind of surface, or not)
	t.lateral_mu = cfg.lateral_mu * surface.grip * made
	t.longitudinal_mu = cfg.longitudinal_mu * surface.grip * made
	t.lateral_peak_deg = clampf(cfg.lateral_peak_deg * surface.peak_scale * (cfg.sealed_peak if surface.sealed else 1.0), 0.5, 25.0)
	t.longitudinal_peak = clampf(cfg.longitudinal_peak * surface.peak_scale, 0.02, 0.5)
	t.lateral_shape = shape_keeping(kept(cfg.lateral_shape) * surface.slide_grip)
	t.longitudinal_shape = shape_keeping(kept(cfg.longitudinal_shape) * surface.slide_grip)
	t.rolling_resistance = cfg.rolling_resistance * surface.rolling_scale
	_on[key] = t
	return t


## A tarmac tyre made from a gravel one: a stiffer, slick-ish tread that bites
## sooner (its grip peaks at less slip) and grips ~12 % more on asphalt, but on
## gravel the smooth tread can't dig in: ~25 % less (gravel tyres on tarmac lose
## grip to their squirming blocks; tarmac tyres on gravel lose far more).
static func tarmac_tyre(gravel: Resource) -> Resource:
	var t: Resource = gravel.duplicate()
	t.lateral_peak_deg = gravel.lateral_peak_deg * 0.8
	t.longitudinal_peak = gravel.longitudinal_peak * 0.8
	t.rolling_resistance = gravel.rolling_resistance * 0.8
	t.relaxation_length = gravel.relaxation_length * 0.85
	t.sealed_grip = 1.12
	t.loose_grip = 0.75
	return t


## The same tyre with the game's EXTRA GRIP (Settings > TYRE GRIP; `a` 0 = the
## real tyre, 1 = GRIPPY, 1.5 = MORE, 2 = ARCADE: arcade()): on loose surfaces
## (gravel, dirt, snow, mud) up to 30 % more grip (x a), on sealed ones up to
## 12 %; a sliding or spinning tyre keeps more of it, and it bites a little
## sooner. Real gravel (0.9 g in a corner, 85 % kept in a slide) feels like ice
## to most players.
static func grippy(cfg: Resource, a: float, rear := false) -> Resource:
	if a <= 0.0:
		return cfg
	if a >= ARCADE:
		return arcade(cfg, rear)
	var t: Resource = cfg.duplicate()
	var k := clampf(a, 0.0, 1.0)
	t.loose_grip = cfg.loose_grip * (1.0 + 0.3 * a)
	t.sealed_grip = cfg.sealed_grip * (1.0 + 0.12 * a)
	t.lateral_shape = shape_keeping(lerpf(kept(cfg.lateral_shape), 0.97, 0.6 * k))
	t.longitudinal_shape = shape_keeping(lerpf(kept(cfg.longitudinal_shape), 0.93, 0.6 * k))
	t.lateral_peak_deg = cfg.lateral_peak_deg * (1.0 - 0.15 * k)
	return t


## ARCADE: the tyre driving like a GTA V / FiveM rally car (their handling.meta:
## a sliding tyre keeps ~82-90 % of its grip, fTractionCurveMin / Max, and off
## tarmac it loses only ~0.4 of what it would, fTractionLossMult 0.375-0.4 on the
## rally-ish cars): loose surfaces x1.65, so gravel grips nearly as well as
## asphalt (and the loose lanes cost 0.4 of what they do: RallyCar.set_lanes).
## Sealed x1.1 only: at x1.3 tarmac tyres cornered at 1.9 g (more than the car
## can take without tipping) and a sliding rear gripped straight back up, so a
## drift died at 10-20 deg even flat out on a rear-drive car. A front tyre
## sliding keeps 95 % sideways (the countersteer bites), a rear 85 %, and a
## spinning rear 85 % along (the throttle holds a drift's angle); on sealed
## surfaces the grip peaks 40 % later (ARC_SEALED_PEAK), so it comes on and
## goes off progressively instead of on, off. Snow, mud and ice are still
## slippery, just less (x1.65 too).
const ARCADE := 2.0
const ARC_LOOSE := 1.65
const ARC_SEALED := 1.1
const ARC_KEEP_FRONT := 0.95
const ARC_KEEP_REAR := 0.85
const ARC_SPIN_FRONT := 0.93
const ARC_SPIN_REAR := 0.85
const ARC_SEALED_PEAK := 1.4
static func arcade(cfg: Resource, rear := false) -> Resource:
	var t: Resource = cfg.duplicate()
	t.loose_grip = cfg.loose_grip * ARC_LOOSE
	t.sealed_grip = cfg.sealed_grip * ARC_SEALED
	t.lateral_shape = shape_keeping(ARC_KEEP_REAR if rear else ARC_KEEP_FRONT)
	t.longitudinal_shape = shape_keeping(ARC_SPIN_REAR if rear else ARC_SPIN_FRONT)
	t.sealed_peak = cfg.sealed_peak * ARC_SEALED_PEAK
	return t


## SIM STREET (Settings > STREET HANDLING: cut up and the touge): a road car on the
## road tyres it really has, made from its tarmac tyre: on asphalt, the peak grip that
## gives the car's real skid-pad figure (g, 0.85-1.25 for road cars; STREET_CAL
## covers what the load transfer takes off the tyres' own peak), braking a little
## harder than that (brake: x the cornering, as magazine tests show), the grip
## peaking at a road tyre's slip angle (6-10 deg for production tyres, Milliken;
## slicks ~4) and falling off past it to what a sliding one keeps (Assetto Corsa's
## street tyres keep ~85 %), the slip ratio peaking at 10-15 %, and a road tyre's
## load sensitivity (Milliken: twice the load, ~12 % less grip per newton). On
## gravel or grass a road tyre is poor (x0.7).
## kind: "street", "cup" (Cup 2 / R-compound road tyres), "slick", "formula" (a single-seater's).
## STREET_CAL: tests/sim_check.gd's skid pad on the cars it measures, measured / real, ~1.00 on
## average (at 1.08 it was 0.95: every road car ~5 % short of its real grip).
const STREET_CAL := 1.13
const STREET_KINDS := {
	"street": {"peak_deg": 7.5, "keep": 0.85, "long_peak": 0.12, "keep_long": 0.8, "load": 0.12, "brake": 1.1},
	"cup": {"peak_deg": 6.0, "keep": 0.82, "long_peak": 0.1, "keep_long": 0.78, "load": 0.15, "brake": 1.05},
	"slick": {"peak_deg": 4.5, "keep": 0.78, "long_peak": 0.09, "keep_long": 0.75, "load": 0.2, "brake": 1.0},
	# a Formula car's slick: peaking earlier still, sharper past it, and built for the downforce's loads
	# (rated at 4 kN a tyre by its chassis class: its grip per newton falls only slowly as the wings load it)
	"formula": {"peak_deg": 4.0, "keep": 0.74, "long_peak": 0.08, "keep_long": 0.72, "load": 0.1, "brake": 1.0},
}
static func street(cfg: Resource, g: float, kind := "street") -> Resource:
	var asphalt: Resource = load("res://scripts/vehicle/physics/surfaces.gd").named("asphalt")
	var spec: Dictionary = STREET_KINDS.get(kind, STREET_KINDS.street)
	var t: Resource = cfg.duplicate()
	var lat := g * STREET_CAL                                 # the peak friction it needs on asphalt
	t.sealed_grip = lat / (cfg.lateral_mu * asphalt.grip)
	t.longitudinal_mu = float(spec.brake) * lat / (asphalt.grip * t.sealed_grip)
	t.sealed_peak = float(spec.peak_deg) / (cfg.lateral_peak_deg * asphalt.peak_scale)
	t.lateral_shape = shape_keeping(float(spec.keep) / asphalt.slide_grip)
	t.longitudinal_shape = shape_keeping(float(spec.keep_long) / asphalt.slide_grip)
	t.longitudinal_peak = float(spec.long_peak) / asphalt.peak_scale
	t.load_sensitivity = float(spec.load)
	t.loose_grip = 0.7
	return t


## The share of its peak grip a Magic Formula curve of shape C keeps far past the peak.
static func kept(shape: float) -> float:
	return sin(shape * PI / 2.0)


## The shape C that keeps this share of the peak far past it (0.3..0.98).
static func shape_keeping(share: float) -> float:
	return 2.0 - 2.0 * asin(clampf(share, 0.3, 0.98)) / PI


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
