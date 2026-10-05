extends Resource
## The steering: from the stick / keys to the front wheels' angles. The base
## physics is plain: input x lock, turned no faster than a driver's hands can
## turn the wheel, split between the two wheels by the geometry (Ackermann).
## Anything that helps (smoothing, less lock at speed, countersteer help) is a
## driver aid with its own switch, not in here. Edit it in the inspector.

## The front wheels' angle at full lock (a rally car turns ~30 deg for hairpins).
@export_range(5.0, 45.0, 0.5, "suffix:deg") var max_angle_deg := 30.0
## How fast the wheels can turn (deg/s at the road wheels): the driver's hands
## through the rack (~12:1, a quick rally rack).
@export_range(30.0, 600.0, 5.0, "suffix:deg/s") var rack_speed_deg := 180.0
## 0 = both wheels turn the same; 1 = full Ackermann (the inside wheel turns
## more, each rolling round the same centre). Rally cars run less than road cars.
@export_range(0.0, 1.0, 0.01) var ackermann := 0.4
