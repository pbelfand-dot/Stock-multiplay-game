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
		"eye": Vector3(-0.37, 1.13, 0.28), "wheel_hub": Vector3(-0.37, 0.88, -0.38), "column_tilt": deg_to_rad(22),
		"head": [Vector3(-0.6596, 0.6114, -1.9816), Vector3(0.6596, 0.6114, -1.9816)], "tail": [Vector3(-0.5571, 0.8779, 2.2172), Vector3(0.5571, 0.8779, 2.2172)],
		"box": Vector3(1.903, 1.333, 4.794), "box_center": Vector3(0, 0.7665, 0.1085), "door": Vector3(-0.9175, 0.88, 0.19), "kit": true},
	"Bemze_M5": {
		"wheelbase": 3.006, "wheel_r": 0.37,
		"wheels": {"FL": Vector3(-0.842, 0.37, -1.503), "FR": Vector3(0.842, 0.37, -1.503), "RL": Vector3(-0.83, 0.37, 1.503), "RR": Vector3(0.83, 0.37, 1.503)},
		"eye": Vector3(-0.37, 1.15, 0.26), "wheel_hub": Vector3(-0.37, 0.89, -0.4), "column_tilt": deg_to_rad(21),
		"head": [Vector3(-0.675, 0.7408, -2.0547), Vector3(0.675, 0.7408, -2.0547)], "tail": [Vector3(-0.5623, 0.9738, 2.3263), Vector3(0.5623, 0.9738, 2.3263)],
		"box": Vector3(1.97, 1.41, 5.096), "box_center": Vector3(0, 0.805, 0.105), "door": Vector3(-0.945, 0.9, 0.09), "kit": true},
	"Bemze_M4": {
		"wheelbase": 2.857, "wheel_r": 0.3395,
		"wheels": {"FL": Vector3(-0.8085, 0.3395, -1.4285), "FR": Vector3(0.8085, 0.3395, -1.4285), "RL": Vector3(-0.8025, 0.3395, 1.4285), "RR": Vector3(0.8025, 0.3395, 1.4285)},
		"eye": Vector3(-0.37, 1.1, 0.3), "wheel_hub": Vector3(-0.37, 0.87, -0.36), "column_tilt": deg_to_rad(22),
		"head": [Vector3(-0.6596, 0.6114, -1.9664), Vector3(0.6596, 0.6114, -1.9664)], "tail": [Vector3(-0.5679, 0.8667, 2.2352), Vector3(0.5679, 0.8667, 2.2352)],
		"box": Vector3(1.887, 1.293, 4.794), "box_center": Vector3(0, 0.7465, 0.1085), "door": Vector3(-0.9075, 0.85, 0.39), "kit": true},
	"Bemze_M2": {
		"wheelbase": 2.747, "wheel_r": 0.3395,
		"wheels": {"FL": Vector3(-0.8085, 0.3395, -1.3735), "FR": Vector3(0.8085, 0.3395, -1.3735), "RL": Vector3(-0.795, 0.3395, 1.3735), "RR": Vector3(0.795, 0.3395, 1.3735)},
		"eye": Vector3(-0.37, 1.11, 0.3), "wheel_hub": Vector3(-0.37, 0.87, -0.36), "column_tilt": deg_to_rad(22),
		"head": [Vector3(-0.6912, 0.6262, -1.8669), Vector3(0.6912, 0.6262, -1.8669)], "tail": [Vector3(-0.6892, 0.9142, 2.0755), Vector3(0.6892, 0.9142, 2.0755)],
		"box": Vector3(1.887, 1.303, 4.58), "box_center": Vector3(0, 0.7515, 0.1265), "door": Vector3(-0.9055, 0.86, 0.38), "kit": true},
	"Bemze_M8": {
		"wheelbase": 2.827, "wheel_r": 0.3525,
		"wheels": {"FL": Vector3(-0.8135, 0.3525, -1.4135), "FR": Vector3(0.8135, 0.3525, -1.4135), "RL": Vector3(-0.8155, 0.3525, 1.4135), "RR": Vector3(0.8155, 0.3525, 1.4135)},
		"eye": Vector3(-0.37, 1.06, 0.33), "wheel_hub": Vector3(-0.37, 0.85, -0.33), "column_tilt": deg_to_rad(23),
		"head": [Vector3(-0.6605, 0.6328, -1.9991), Vector3(0.6605, 0.6328, -1.9991)], "tail": [Vector3(-0.5729, 0.9089, 2.1681), Vector3(0.5729, 0.9089, 2.1681)],
		"box": Vector3(1.907, 1.262, 4.867), "box_center": Vector3(0, 0.731, 0.08), "door": Vector3(-0.9175, 0.877, 0.43), "kit": true},
	"Bemze_540i": {
		"wheelbase": 2.975, "wheel_r": 0.339,
		"wheels": {"FL": Vector3(-0.8025, 0.339, -1.4875), "FR": Vector3(0.8025, 0.339, -1.4875), "RL": Vector3(-0.815, 0.339, 1.4875), "RR": Vector3(0.815, 0.339, 1.4875)},
		"eye": Vector3(-0.37, 1.15, 0.23), "wheel_hub": Vector3(-0.37, 0.89, -0.43), "column_tilt": deg_to_rad(21),
		"head": [Vector3(-0.6909, 0.6694, -1.9451), Vector3(0.6909, 0.6694, -1.9451)], "tail": [Vector3(-0.5717, 0.9249, 2.4299), Vector3(0.5717, 0.9249, 2.4299)],
		"box": Vector3(1.868, 1.366, 4.936), "box_center": Vector3(0, 0.783, 0.1355), "door": Vector3(-0.916, 0.85, 0.163), "kit": true},
	"Cop_Interceptor": {
		"wheelbase": 3.052, "wheel_r": 0.3635,
		"wheels": {"FL": Vector3(-0.805, 0.3635, -1.526), "FR": Vector3(0.805, 0.3635, -1.526), "RL": Vector3(-0.809, 0.3635, 1.526), "RR": Vector3(0.809, 0.3635, 1.526)},
		"eye": Vector3(-0.37, 1.17, 0.13), "wheel_hub": Vector3(-0.37, 0.9, -0.55), "column_tilt": deg_to_rad(21),
		"head": [Vector3(-0.746, 0.779, -2.4232), Vector3(0.746, 0.779, -2.4232)], "tail": [Vector3(-0.533, 0.912, 2.6326), Vector3(0.533, 0.912, 2.6326)],
		"box": Vector3(1.905, 1.381, 5.1), "box_center": Vector3(0, 0.7905, 0.094), "door": Vector3(-0.9345, 0.9, 0.1), "kit": true},
}


static func get_ref(model: String) -> Dictionary:
	var r: Dictionary = GENERIC.duplicate(true)
	for k in MODELS.get(model, {}):
		r[k] = MODELS[model][k]
	return r
