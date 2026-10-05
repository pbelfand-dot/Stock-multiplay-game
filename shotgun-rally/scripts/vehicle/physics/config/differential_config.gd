extends Resource
## A differential: open (each side gets the same torque, so the lighter-loaded
## wheel spins up and limits both), locked (both sides turn together), or a
## limited-slip diff (LSD: plates that lock it more the harder it's driven:
## lock torque = preload + lock x the torque going through it, with its own
## figure driving (power) and on the overrun (coast)). Edit it in the inspector.

enum Kind { OPEN, LOCKED, LSD }

@export var kind := Kind.LSD
## Driving: lock torque as a share of the torque going through it.
@export_range(0.0, 1.5, 0.01) var power_lock := 0.5
## Off the throttle (engine braking): the same.
@export_range(0.0, 1.5, 0.01) var coast_lock := 0.3
## Lock torque always there (N m): the plates' spring.
@export_range(0.0, 1000.0, 5.0, "suffix:N m") var preload_torque := 60.0
