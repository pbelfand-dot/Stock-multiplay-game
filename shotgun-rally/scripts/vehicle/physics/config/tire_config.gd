extends Resource
## A tyre: how its grip builds with slip and fades past the peak, and how it
## behaves rolling slowly or standing still. Grip = mu x load x the curve; the
## surface (phase 6) scales mu. Units: m, N, s, rad.
## Edit it in the inspector (data/cars/*.tres).

@export_group("Sideways (slip angle)")
## Friction coefficient at the peak, on the reference surface.
@export_range(0.1, 2.0, 0.01) var lateral_mu := 1.0
## The slip angle where the side force peaks (a gravel tyre peaks late, ~7 deg).
@export_range(0.5, 25.0, 0.1, "suffix:deg") var lateral_peak_deg := 7.0
## Magic Formula shape C: how much grip is left well past the peak:
## sin(C pi / 2) of it (1.35 keeps ~85 %, so a slide is something you drive).
@export_range(1.0, 1.9, 0.01) var lateral_shape := 1.35

@export_group("Rolling slowly")
## How far the tyre rolls before its force catches up with a new slip
## (the carcass winding up). Also what makes it hold, like a spring, at a standstill.
@export_range(0.05, 1.5, 0.01, "suffix:m") var relaxation_length := 0.35
## At a standstill the wound-up carcass is a spring; this damps it (N per m/s),
## fading out by 3 m/s. Without it a parked car would wobble on its tyres.
@export_range(0.0, 30000.0, 100.0, "suffix:N/(m/s)") var standstill_damping := 8000.0
