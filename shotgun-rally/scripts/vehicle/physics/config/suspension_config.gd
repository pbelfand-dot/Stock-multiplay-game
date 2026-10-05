extends Resource
## One axle's suspension (both its corners use it): a coil spring, a damper
## that resists stretching (rebound) more than squashing (bump), so the car
## soaks a hit up and settles instead of bouncing, and a progressive hydraulic
## bump stop at the end of the travel that catches big landings.
## Units: m, N, s. Edit it in the inspector (data/cars/*.tres).

@export_group("Spring")
## From full droop (wheel hanging) to full bump (wheel up against the stop).
@export_range(0.05, 0.6, 0.005, "suffix:m") var travel := 0.30
## Force per metre of squash. With the corner's share of the car's weight it
## sets the ride frequency: f = sqrt(k / m) / 2 pi (~1.5 Hz for a gravel car).
@export_range(5000.0, 150000.0, 100.0, "suffix:N/m") var spring_rate := 28000.0

@export_group("Damper")
## Resistance to squashing (N per m/s of compression speed).
@export_range(0.0, 20000.0, 50.0, "suffix:N/(m/s)") var bump_damping := 1900.0
## Resistance to stretching back out.
@export_range(0.0, 20000.0, 50.0, "suffix:N/(m/s)") var rebound_damping := 3300.0

@export_group("Bump stop")
## Compression where the bump stop starts to push.
@export_range(0.0, 0.6, 0.005, "suffix:m") var bump_stop_start := 0.22
## How hard it pushes: rate x (compression past the start)^2.
@export_range(0.0, 2.0e7, 1.0e4, "suffix:N/m²") var bump_stop_rate := 4.0e6
## Extra damping while on it, squashing only (it's hydraulic: it soaks the hit up).
@export_range(0.0, 50000.0, 100.0, "suffix:N/(m/s)") var bump_stop_damping := 9000.0
## The most the corner can ever push (N): a ceiling for a freak spike.
@export_range(1000.0, 300000.0, 1000.0, "suffix:N") var max_force := 90000.0
