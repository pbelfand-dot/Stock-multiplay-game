extends Resource
## One axle's suspension (both its corners use it): a coil spring, a damper
## that resists stretching (rebound) more than squashing (bump), so the car
## soaks a hit up and settles instead of bouncing, and a progressive hydraulic
## bump stop at the end of the travel that catches big landings. The damper has
## two stages, like a rally damper's low- and high-speed adjusters: slow
## movements (the body rolling, pitching, bouncing) are held firmly; fast ones
## (a wheel hitting a bump or dropping into a hole) get through more easily, so
## the wheel follows the road without kicking the body. And an anti-roll bar.
## Units: m, N, s. Edit it in the inspector (data/cars/*.tres).

@export_group("Spring")
## From full droop (wheel hanging) to full bump (wheel up against the stop).
@export_range(0.05, 0.6, 0.005, "suffix:m") var travel := 0.30
## Force per metre of squash. With the corner's share of the car's weight it
## sets the ride frequency: f = sqrt(k / m) / 2 pi (~1.5 Hz for a gravel car).
@export_range(5000.0, 150000.0, 100.0, "suffix:N/m") var spring_rate := 28000.0

@export_group("Damper")
## Resistance to squashing, slowly (N per m/s of compression speed, up to the knee).
@export_range(0.0, 20000.0, 50.0, "suffix:N/(m/s)") var bump_damping := 1900.0
## Resistance to stretching back out, slowly.
@export_range(0.0, 20000.0, 50.0, "suffix:N/(m/s)") var rebound_damping := 3300.0
## The damper speed where slow ends and fast begins (the body moves slower than
## this, a wheel hitting a bump faster).
@export_range(0.02, 2.0, 0.01, "suffix:m/s") var damper_knee := 0.25
## Squashing faster than the knee: N per m/s more (less than slowly: a sharp hit
## gets through instead of kicking the body; the bump stop catches the big ones).
@export_range(0.0, 20000.0, 50.0, "suffix:N/(m/s)") var high_speed_bump := 1100.0
## Stretching faster than the knee (less than slowly: the wheel drops back into a
## hole quickly and stays on the ground).
@export_range(0.0, 20000.0, 50.0, "suffix:N/(m/s)") var high_speed_rebound := 2500.0

@export_group("Anti-roll bar")
## How hard the bar resists one wheel squashing more than the other: N at each
## wheel per m of difference. It cuts the body's roll; the stiffer end of the car
## takes more of the weight shifted in a corner, so it grips less (stiffer front:
## more understeer; stiffer rear: more oversteer). 0: no bar.
@export_range(0.0, 100000.0, 100.0, "suffix:N/m") var anti_roll_rate := 0.0

@export_group("Bump stop")
## Compression where the bump stop starts to push.
@export_range(0.0, 0.6, 0.005, "suffix:m") var bump_stop_start := 0.22
## How hard it pushes: rate x (compression past the start)^2.
@export_range(0.0, 2.0e7, 1.0e4, "suffix:N/m²") var bump_stop_rate := 4.0e6
## Extra damping while on it, squashing only (it's hydraulic: it soaks the hit up).
@export_range(0.0, 50000.0, 100.0, "suffix:N/(m/s)") var bump_stop_damping := 9000.0
## The most the corner can ever push (N): a ceiling for a freak spike.
@export_range(1000.0, 300000.0, 1000.0, "suffix:N") var max_force := 90000.0
