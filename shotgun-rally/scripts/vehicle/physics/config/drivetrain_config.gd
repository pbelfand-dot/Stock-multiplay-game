extends Resource
## From the engine to the wheels: the clutch, the sequential gearbox and final
## drive, and the three differentials of a four-wheel-drive car. Edit it in the
## inspector (data/cars/*.tres).

@export_group("Gearbox")
## Each gear's ratio, first to top (engine turns per gearbox output turn).
@export var gear_ratios := PackedFloat32Array([2.92, 2.05, 1.60, 1.29, 1.06])
@export_range(1.0, 10.0, 0.01) var final_drive := 4.7
## Reverse's ratio (it turns the wheels backwards).
@export_range(1.0, 6.0, 0.01) var reverse_ratio := 3.0
## A sequential dog box shifts with an ignition cut, no clutch: the drive is off this long.
@export_range(0.01, 0.5, 0.005, "suffix:s") var shift_time := 0.06

@export_group("Clutch")
## The most torque the clutch can carry fully in (N m), well over the engine's.
@export_range(100.0, 3000.0, 10.0, "suffix:N m") var clutch_torque := 600.0
## Pulling away flat out the clutch slips holding the engine near this many rpm
## (less throttle, lower), like a driver's (or launch control's) left foot.
@export_range(1200.0, 6000.0, 50.0, "suffix:rpm") var launch_rpm := 4000.0

@export_group("Four-wheel drive")
## The torque's share to the front axle through the centre diff (1 = front-wheel drive, 0 = rear).
@export_range(0.0, 1.0, 0.01) var front_share := 0.5
@export var center_diff: Resource           ## DifferentialConfig
@export var front_diff: Resource            ## DifferentialConfig
@export var rear_diff: Resource             ## DifferentialConfig

@export_group("Handbrake")
## Pulling the handbrake lets the rear axle's drive go (a clutch in the drive to
## the rear, as on a Rally2 car), so the rears lock on the handbrake while the
## fronts keep driving. Without it the engine fights the handbrake.
@export var handbrake_disconnects_rear := true
## That clutch's grip when it's in (N m at the rear axle): more than the rear tyres can take.
@export_range(500.0, 20000.0, 100.0, "suffix:N m") var rear_clutch_torque := 6000.0
## How long it takes to bite again after the handbrake is let go.
@export_range(0.02, 1.0, 0.01, "suffix:s") var rear_reengage_time := 0.25

@export_group("Shifting for you")
## Change gear by itself (for keyboards: an aid, it'll be its own Settings switch).
@export var auto_shift := true
@export_range(3000.0, 12000.0, 50.0, "suffix:rpm") var upshift_rpm := 7200.0
@export_range(1000.0, 8000.0, 50.0, "suffix:rpm") var downshift_rpm := 3300.0
