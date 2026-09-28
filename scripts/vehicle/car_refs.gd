extends RefCounted
## Where things are on each car model (prop-local, metres, the car faces -z,
## origin on the ground between the axles): wheel centres, the driver's eye,
## the steering wheel hub, lights, the collision box. Numbers come from the
## Blender kit's report (tools/blender/build_bemze.py prints them); anything
## a model doesn't list falls back to a generic mid-size sedan.

const GENERIC := {
	"wheelbase": 2.85, "wheel_r": 0.34,
	"wheels": {"FL": Vector3(-0.8, 0.34, -1.425), "FR": Vector3(0.8, 0.34, -1.425),
		"RL": Vector3(-0.8, 0.34, 1.425), "RR": Vector3(0.8, 0.34, 1.425)},
	"eye": Vector3(-0.37, 1.13, 0.12), "wheel_hub": Vector3(-0.37, 0.93, -0.28), "column_tilt": -0.35,
	"head": [Vector3(-0.62, 0.72, -2.3), Vector3(0.62, 0.72, -2.3)],
	"tail": [Vector3(-0.65, 0.88, 2.33), Vector3(0.65, 0.88, 2.33)],
	"box": Vector3(1.86, 1.3, 4.7), "box_center": Vector3(0, 0.7, 0),
	"door": Vector3(-0.95, 0.9, 0.0),
}
const MODELS := {}


static func get_ref(model: String) -> Dictionary:
	var r: Dictionary = GENERIC.duplicate(true)
	for k in MODELS.get(model, {}):
		r[k] = MODELS[model][k]
	return r
