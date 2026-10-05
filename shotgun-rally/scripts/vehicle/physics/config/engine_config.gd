extends Resource
## The engine: a 1.6 litre turbo four like a Rally2 car's. Its torque at full
## throttle and full boost against the revs (points in between are joined
## straight), how heavy it is to spin up, what it loses to friction (and more
## with the throttle shut: engine braking), the rev limiter, and the turbo.
## Edit it in the inspector (data/cars/*.tres).

@export_group("Torque")
## The revs the torque points are at.
@export var rpm_points := PackedFloat32Array([1000.0, 2000.0, 3000.0, 4000.0, 5000.0, 6000.0, 7000.0, 7500.0])
## Torque at each of those revs, as a share of max_torque (full throttle, full boost).
@export var torque_points := PackedFloat32Array([0.40, 0.62, 0.88, 1.0, 0.98, 0.90, 0.78, 0.70])
## The most torque it makes (N m at the crank).
@export_range(50.0, 1500.0, 5.0, "suffix:N m") var max_torque := 400.0

@export_group("Revs")
@export_range(500.0, 2000.0, 10.0, "suffix:rpm") var idle_rpm := 1000.0
## The rev limiter cuts in here (and lets go 150 rpm below).
@export_range(3000.0, 12000.0, 50.0, "suffix:rpm") var limiter_rpm := 7600.0
## The engine, flywheel and clutch's spin inertia (kg m²): how fast it revs.
@export_range(0.02, 1.0, 0.005, "suffix:kg m²") var inertia := 0.15

@export_group("Friction (engine braking)")
## Friction torque always there: this much ...
@export_range(0.0, 100.0, 0.5, "suffix:N m") var friction := 15.0
## ... plus this much per rpm ...
@export_range(0.0, 0.05, 0.0005) var friction_per_rpm := 0.004
## ... plus, with the throttle shut, this much per rpm more (pumping: engine braking).
@export_range(0.0, 0.05, 0.0005) var closed_throttle_per_rpm := 0.006

@export_group("Turbo")
## The share of max_torque the boost gives (the rest it makes without boost).
@export_range(0.0, 0.8, 0.01) var turbo_share := 0.35
## The boost starts building at these revs and is full by ...
@export_range(500.0, 8000.0, 50.0, "suffix:rpm") var spool_start_rpm := 2200.0
## ... these.
@export_range(500.0, 9000.0, 50.0, "suffix:rpm") var spool_full_rpm := 3800.0
## Seconds for the boost to build (it drops a little faster).
@export_range(0.02, 2.0, 0.01, "suffix:s") var spool_time := 0.35
## Anti-lag: off the throttle the boost is held up (rally cars bang and pop to
## keep the turbo spinning, so the power is there the instant you're back on).
@export var anti_lag := true
