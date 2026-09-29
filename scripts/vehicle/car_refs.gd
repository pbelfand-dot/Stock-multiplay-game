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
const MODELS := {
	# the used TOROLA: the traffic kit's sedan (built nose to +z, shared Wheel_Car)
	"TCar_Sedan_Silver": {
		"wheelbase": 2.75, "wheel_r": 0.34, "flip": true, "wheel_prop": "Wheel_Car",
		"wheels": {"FL": Vector3(-0.8, 0.34, -1.375), "FR": Vector3(0.8, 0.34, -1.375), "RL": Vector3(-0.8, 0.34, 1.375), "RR": Vector3(0.8, 0.34, 1.375)},
		"eye": Vector3(-0.36, 1.2, 0.2), "wheel_hub": Vector3(-0.36, 0.95, -0.3), "column_tilt": deg_to_rad(22),
		"head": [Vector3(-0.6, 0.7, -2.33), Vector3(0.6, 0.7, -2.33)], "tail": [Vector3(-0.62, 0.85, 2.34), Vector3(0.62, 0.85, 2.34)],
		"box": Vector3(1.84, 1.45, 4.7), "box_center": Vector3(0, 0.78, 0), "door": Vector3(-0.92, 0.9, 0.1), "kit": true},
	"Bemze_M3": {
		"wheelbase": 2.857, "wheel_r": 0.3395,
		"wheels": {"FL": Vector3(-0.8085, 0.3395, -1.4285), "FR": Vector3(0.8085, 0.3395, -1.4285), "RL": Vector3(-0.8025, 0.3395, 1.4285), "RR": Vector3(0.8025, 0.3395, 1.4285)},
		"eye": Vector3(-0.37, 1.13, 0.08), "wheel_hub": Vector3(-0.37, 0.88, -0.6), "column_tilt": deg_to_rad(22),
		"head": [Vector3(-0.537, 0.69, -2.274), Vector3(0.537, 0.69, -2.274)], "tail": [Vector3(-0.638, 0.916, 2.477), Vector3(0.638, 0.916, 2.477)],
		"box": Vector3(1.903, 1.333, 4.794), "box_center": Vector3(0, 0.767, 0.109), "door": Vector3(-0.93, 0.87, 0.02), "kit": true},
	"Bemze_M5": {
		"wheelbase": 3.006, "wheel_r": 0.37,
		"wheels": {"FL": Vector3(-0.842, 0.37, -1.503), "FR": Vector3(0.842, 0.37, -1.503), "RL": Vector3(-0.83, 0.37, 1.503), "RR": Vector3(0.83, 0.37, 1.503)},
		"eye": Vector3(-0.37, 1.15, 0.1), "wheel_hub": Vector3(-0.37, 0.89, -0.58), "column_tilt": deg_to_rad(21),
		"head": [Vector3(-0.656, 0.774, -2.418), Vector3(0.656, 0.774, -2.418)], "tail": [Vector3(-0.69, 0.993, 2.62), Vector3(0.69, 0.993, 2.62)],
		"box": Vector3(1.97, 1.41, 5.096), "box_center": Vector3(0, 0.805, 0.105), "door": Vector3(-0.945, 0.9, 0.1), "kit": true},
	"Bemze_M4": {
		"wheelbase": 2.857, "wheel_r": 0.3395,
		"wheels": {"FL": Vector3(-0.8085, 0.3395, -1.4285), "FR": Vector3(0.8085, 0.3395, -1.4285), "RL": Vector3(-0.8025, 0.3395, 1.4285), "RR": Vector3(0.8025, 0.3395, 1.4285)},
		"eye": Vector3(-0.37, 1.1, 0.13), "wheel_hub": Vector3(-0.37, 0.87, -0.55), "column_tilt": deg_to_rad(22),
		"head": [Vector3(-0.537, 0.69, -2.274), Vector3(0.537, 0.69, -2.274)], "tail": [Vector3(-0.623, 0.924, 2.476), Vector3(0.623, 0.924, 2.476)],
		"box": Vector3(1.887, 1.293, 4.794), "box_center": Vector3(0, 0.747, 0.109), "door": Vector3(-0.92, 0.875, 0.42), "kit": true},
	"Bemze_M2": {
		"wheelbase": 2.747, "wheel_r": 0.3395,
		"wheels": {"FL": Vector3(-0.8085, 0.3395, -1.3735), "FR": Vector3(0.8085, 0.3395, -1.3735), "RL": Vector3(-0.795, 0.3395, 1.3735), "RR": Vector3(0.795, 0.3395, 1.3735)},
		"eye": Vector3(-0.37, 1.11, 0.12), "wheel_hub": Vector3(-0.37, 0.87, -0.56), "column_tilt": deg_to_rad(22),
		"head": [Vector3(-0.601, 0.694, -2.154), Vector3(0.601, 0.694, -2.154)], "tail": [Vector3(-0.686, 0.924, 2.397), Vector3(0.686, 0.924, 2.397)],
		"box": Vector3(1.887, 1.303, 4.58), "box_center": Vector3(0, 0.752, 0.127), "door": Vector3(-0.906, 0.87, 0.36), "kit": true},
	"Bemze_M8": {
		"wheelbase": 2.827, "wheel_r": 0.3525,
		"wheels": {"FL": Vector3(-0.8135, 0.3525, -1.4135), "FR": Vector3(0.8135, 0.3525, -1.4135), "RL": Vector3(-0.8155, 0.3525, 1.4135), "RR": Vector3(0.8155, 0.3525, 1.4135)},
		"eye": Vector3(-0.37, 1.06, 0.28), "wheel_hub": Vector3(-0.37, 0.85, -0.4), "column_tilt": deg_to_rad(23),
		"head": [Vector3(-0.616, 0.655, -2.325), Vector3(0.616, 0.655, -2.325)], "tail": [Vector3(-0.642, 0.921, 2.478), Vector3(0.642, 0.921, 2.478)],
		"box": Vector3(1.907, 1.262, 4.867), "box_center": Vector3(0, 0.731, 0.08), "door": Vector3(-0.924, 0.84, 0.4), "kit": true},
	"Bemze_540i": {
		"wheelbase": 2.995, "wheel_r": 0.3515,
		"wheels": {"FL": Vector3(-0.8125, 0.3515, -1.4975), "FR": Vector3(0.8125, 0.3515, -1.4975), "RL": Vector3(-0.8275, 0.3515, 1.4975), "RR": Vector3(0.8275, 0.3515, 1.4975)},
		"eye": Vector3(-0.37, 1.15, 0.1), "wheel_hub": Vector3(-0.37, 0.89, -0.58), "column_tilt": deg_to_rad(21),
		"head": [Vector3(-0.629, 0.774, -2.402), Vector3(0.629, 0.774, -2.402)], "tail": [Vector3(-0.673, 0.995, 2.599), Vector3(0.673, 0.995, 2.599)],
		"box": Vector3(1.9, 1.415, 5.06), "box_center": Vector3(0, 0.808, 0.103), "door": Vector3(-0.938, 0.9, 0.1), "kit": true},
	"Cop_Interceptor": {
		"wheelbase": 3.052, "wheel_r": 0.3635,
		"wheels": {"FL": Vector3(-0.805, 0.3635, -1.526), "FR": Vector3(0.805, 0.3635, -1.526), "RL": Vector3(-0.809, 0.3635, 1.526), "RR": Vector3(0.809, 0.3635, 1.526)},
		"eye": Vector3(-0.37, 1.17, 0.13), "wheel_hub": Vector3(-0.37, 0.9, -0.55), "column_tilt": deg_to_rad(21),
		"head": [Vector3(-0.727, 0.779, -2.426), Vector3(0.727, 0.779, -2.426)], "tail": [Vector3(-0.526, 0.912, 2.633), Vector3(0.526, 0.912, 2.633)],
		"box": Vector3(1.905, 1.381, 5.1), "box_center": Vector3(0, 0.791, 0.094), "door": Vector3(-0.935, 0.9, 0.1), "kit": true},
}


static func get_ref(model: String) -> Dictionary:
	var r: Dictionary = GENERIC.duplicate(true)
	for k in MODELS.get(model, {}):
		r[k] = MODELS[model][k]
	return r
