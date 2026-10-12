extends Resource
## The car as a body: its mass and how it's spread (centre of mass, inertia),
## where the wheels are, the tyre size, the suspension and tyres on each axle,
## the steering and the collision shape. The car (rally_car.gd) reads it once, when it's added.
## Units: m, kg, N. Edit it in the inspector (data/cars/*.tres).
## Car space: the car faces -Z, +X is its right, +Y up; the origin is the
## middle of the chassis at the height of the suspension mounts.

@export_group("Body")
@export_range(500.0, 3000.0, 5.0, "suffix:kg") var mass := 1280.0
## Where the mass balances (car space). Forward of the middle = more weight on the
## front wheels; lower = less weight transfer and body roll.
@export var center_of_mass := Vector3(0.0, -0.05, -0.12)
## Moment of inertia about the car's own axes (kg m²): x pitch, y yaw, z roll.
@export var inertia := Vector3(1850.0, 2050.0, 520.0)
## A road car's own suspension (CarSpecs: worked out from its weight for a ride frequency and
## a roll gradient): never stiffened into the rally tarmac setup (RallyCar._tune).
@export var road_suspension := false
## How much more steering it needs per g of cornering than the turn's geometry (its
## understeer gradient, deg per g): SIM street steering asks for a share of the grip
## through it (DriverAssist.angle_for). 0: the rally car's (not used there).
@export var understeer := 0.0
## Its electronic top-speed limiter (km/h; 0: none): the throttle is cut within 0.3 m/s of it (a
## road car geared on its real ratios would otherwise run past its published top speed).
@export_range(0.0, 450.0, 1.0, "suffix:km/h") var vmax_kmh := 0.0

@export_group("Wheels")
## Front axle position along the car (car-space z, negative = forward).
@export_range(-3.0, 0.0, 0.01, "suffix:m") var front_axle := -1.24
## Rear axle position (car-space z).
@export_range(0.0, 3.0, 0.01, "suffix:m") var rear_axle := 1.26
@export_range(1.0, 2.2, 0.01, "suffix:m") var front_track := 1.54
@export_range(1.0, 2.2, 0.01, "suffix:m") var rear_track := 1.54
## The suspension mounts' height in car space (the top of the travel).
@export_range(-0.5, 0.5, 0.01, "suffix:m") var mount_height := 0.0
## Tyre radius (a 15" gravel tyre is ~0.32 m).
@export_range(0.2, 0.5, 0.005, "suffix:m") var tyre_radius := 0.32
@export_range(0.1, 0.4, 0.005, "suffix:m") var tyre_width := 0.2

## A wheel's spin inertia: the rim, tyre, brake disc and hub (the driveline's
## share joins in phase 5).
@export_range(0.2, 5.0, 0.05, "suffix:kg m²") var wheel_inertia := 1.1

@export_group("Brakes")
## The four brakes' torque together at full pedal (N m). More than the tyres can
## take: they lock if you stamp on it (no ABS: that's an aid, its own switch).
@export_range(500.0, 20000.0, 50.0, "suffix:N m") var brake_torque := 5000.0
## The front axle's share (the nose is loaded under braking: front-heavy so the
## fronts lock first and the car stays straight).
@export_range(0.3, 0.9, 0.01) var brake_bias := 0.7
## The hydraulic handbrake: its torque on the two rear wheels together at full
## pull (N m). Enough to lock them at any speed (it's for turning the car).
@export_range(0.0, 10000.0, 50.0, "suffix:N m") var handbrake_torque := 3000.0

@export_group("Aero")
## Drag coefficient (a rally hatchback with its wing and wide arches: ~0.4).
@export_range(0.1, 1.5, 0.01) var drag_coefficient := 0.4
## Frontal area (m²).
@export_range(0.5, 5.0, 0.05, "suffix:m²") var frontal_area := 2.15
## Downforce: its lift coefficient x area (m²). A Rally2 car's ~60 kg at 150 km/h is ~0.55.
@export_range(0.0, 5.0, 0.01, "suffix:m²") var downforce_area := 0.55
## The front axle's share of the downforce (a wing at the back: under half).
@export_range(0.0, 1.0, 0.01) var aero_balance := 0.45

@export_group("Suspension")
@export var front_suspension: Resource      ## SuspensionConfig
@export var rear_suspension: Resource       ## SuspensionConfig

@export_group("Tyres and steering")
@export var front_tire: Resource            ## TireConfig
@export var rear_tire: Resource             ## TireConfig
@export var steering: Resource              ## SteeringConfig

@export_group("Engine and drivetrain")
@export var engine: Resource                ## EngineConfig (none: no engine, the wheels roll free)
@export var drivetrain: Resource            ## DrivetrainConfig

@export_group("Collision")
## The body box (car space) and the cabin above it: what lands on the ground in a
## rollover, slides on its roof, hits trees. Kept clear of the ground at full bump.
@export var body_size := Vector3(1.7, 0.8, 3.9)
@export var body_center := Vector3(0.0, 0.22, 0.0)
@export var cabin_size := Vector3(1.4, 0.5, 2.0)
@export var cabin_center := Vector3(0.0, 0.85, 0.15)


## The mount positions (car space): FL, FR, RL, RR.
func mounts() -> Array:
	return [Vector3(-front_track * 0.5, mount_height, front_axle), Vector3(front_track * 0.5, mount_height, front_axle),
		Vector3(-rear_track * 0.5, mount_height, rear_axle), Vector3(rear_track * 0.5, mount_height, rear_axle)]


## Each corner's share of the car's weight standing still on flat ground (N):
## [front corner, rear corner], from where the centre of mass sits between the axles.
func static_loads(g := 9.81) -> Array:
	var front_share := (rear_axle - center_of_mass.z) / (rear_axle - front_axle)
	return [mass * g * front_share * 0.5, mass * g * (1.0 - front_share) * 0.5]
