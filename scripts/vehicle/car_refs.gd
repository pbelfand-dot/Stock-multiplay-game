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
		"head": [Vector3(-0.6867, 0.6037, -1.9887), Vector3(0.6867, 0.6037, -1.9887)], "tail": [Vector3(-0.5571, 0.8779, 2.2125), Vector3(0.5571, 0.8779, 2.2125)],
		"box": Vector3(1.903, 1.333, 4.794), "box_center": Vector3(0, 0.7665, 0.1085), "door": Vector3(-0.9216, 0.88, 0.19), "kit": true},
	"Bemze_M5": {
		"wheelbase": 3.006, "wheel_r": 0.37,
		"wheels": {"FL": Vector3(-0.842, 0.37, -1.503), "FR": Vector3(0.842, 0.37, -1.503), "RL": Vector3(-0.83, 0.37, 1.503), "RR": Vector3(0.83, 0.37, 1.503)},
		"eye": Vector3(-0.37, 1.15, 0.26), "wheel_hub": Vector3(-0.37, 0.89, -0.4), "column_tilt": deg_to_rad(21),
		"head": [Vector3(-0.675, 0.7408, -2.0403), Vector3(0.675, 0.7408, -2.0403)], "tail": [Vector3(-0.5623, 0.9738, 2.3241), Vector3(0.5623, 0.9738, 2.3241)],
		"box": Vector3(1.97, 1.41, 5.096), "box_center": Vector3(0, 0.805, 0.105), "door": Vector3(-0.9541, 0.9, 0.09), "kit": true},
	"Bemze_M4": {
		"wheelbase": 2.857, "wheel_r": 0.3395,
		"wheels": {"FL": Vector3(-0.8085, 0.3395, -1.4285), "FR": Vector3(0.8085, 0.3395, -1.4285), "RL": Vector3(-0.8025, 0.3395, 1.4285), "RR": Vector3(0.8025, 0.3395, 1.4285)},
		"eye": Vector3(-0.37, 1.1, 0.3), "wheel_hub": Vector3(-0.37, 0.87, -0.36), "column_tilt": deg_to_rad(22),
		"head": [Vector3(-0.6602, 0.6172, -2.0505), Vector3(0.6602, 0.6172, -2.0505)], "tail": [Vector3(-0.6028, 0.8573, 2.2702), Vector3(0.6028, 0.8573, 2.2702)],
		"box": Vector3(1.887, 1.293, 4.794), "box_center": Vector3(0, 0.7465, 0.1085), "door": Vector3(-0.9128, 0.85, 0.39), "kit": true},
	"Bemze_M2": {
		"wheelbase": 2.747, "wheel_r": 0.3395,
		"wheels": {"FL": Vector3(-0.8085, 0.3395, -1.3735), "FR": Vector3(0.8085, 0.3395, -1.3735), "RL": Vector3(-0.795, 0.3395, 1.3735), "RR": Vector3(0.795, 0.3395, 1.3735)},
		"eye": Vector3(-0.37, 1.11, 0.3), "wheel_hub": Vector3(-0.37, 0.87, -0.36), "column_tilt": deg_to_rad(22),
		"head": [Vector3(-0.6912, 0.6262, -1.8667), Vector3(0.6912, 0.6262, -1.8667)], "tail": [Vector3(-0.6892, 0.9142, 2.0752), Vector3(0.6892, 0.9142, 2.0752)],
		"box": Vector3(1.887, 1.303, 4.58), "box_center": Vector3(0, 0.7515, 0.1265), "door": Vector3(-0.9052, 0.86, 0.38), "kit": true},
	"Bemze_M8": {
		"wheelbase": 2.827, "wheel_r": 0.3525,
		"wheels": {"FL": Vector3(-0.8135, 0.3525, -1.4135), "FR": Vector3(0.8135, 0.3525, -1.4135), "RL": Vector3(-0.8155, 0.3525, 1.4135), "RR": Vector3(0.8155, 0.3525, 1.4135)},
		"eye": Vector3(-0.37, 1.06, 0.33), "wheel_hub": Vector3(-0.37, 0.85, -0.33), "column_tilt": deg_to_rad(23),
		"head": [Vector3(-0.6605, 0.6328, -1.9916), Vector3(0.6605, 0.6328, -1.9916)], "tail": [Vector3(-0.5729, 0.9089, 2.1677), Vector3(0.5729, 0.9089, 2.1677)],
		"box": Vector3(1.907, 1.262, 4.867), "box_center": Vector3(0, 0.731, 0.08), "door": Vector3(-0.924, 0.877, 0.43), "kit": true},
	"Bemze_540i": {
		"wheelbase": 2.975, "wheel_r": 0.339,
		"wheels": {"FL": Vector3(-0.8025, 0.339, -1.4875), "FR": Vector3(0.8025, 0.339, -1.4875), "RL": Vector3(-0.815, 0.339, 1.4875), "RR": Vector3(0.815, 0.339, 1.4875)},
		"eye": Vector3(-0.37, 1.15, 0.23), "wheel_hub": Vector3(-0.37, 0.89, -0.43), "column_tilt": deg_to_rad(21),
		"head": [Vector3(-0.6938, 0.6457, -2.1551), Vector3(0.6938, 0.6457, -2.1551)], "tail": [Vector3(-0.6309, 0.916, 2.4884), Vector3(0.6309, 0.916, 2.4884)],
		"box": Vector3(1.868, 1.366, 4.936), "box_center": Vector3(0, 0.783, 0.1355), "door": Vector3(-0.9082, 0.872, 0.097), "kit": true},
	"Cop_Interceptor": {
		"wheelbase": 3.052, "wheel_r": 0.3635,
		"wheels": {"FL": Vector3(-0.805, 0.3635, -1.526), "FR": Vector3(0.805, 0.3635, -1.526), "RL": Vector3(-0.809, 0.3635, 1.526), "RR": Vector3(0.809, 0.3635, 1.526)},
		"eye": Vector3(-0.37, 1.17, 0.13), "wheel_hub": Vector3(-0.37, 0.9, -0.55), "column_tilt": deg_to_rad(21),
		"head": [Vector3(-0.746, 0.779, -2.4247), Vector3(0.746, 0.779, -2.4247)], "tail": [Vector3(-0.533, 0.912, 2.6336), Vector3(0.533, 0.912, 2.6336)],
		"box": Vector3(1.905, 1.381, 5.1), "box_center": Vector3(0, 0.7905, 0.094), "door": Vector3(-0.9378, 0.9, 0.1), "kit": true},
	# ---- the owner's real models (tools/blender/build_realcars.py -> realcars_kit.glb; numbers from its report).
	# Own wheels (+ rear ones when staggered), front calipers that steer, the steering wheel cut from the
	# interior, tail lights that are the model's own (tail_mat: car.gd brightens that surface on the brakes).
	"RC_M4": {
		"wheelbase": 2.851, "wheel_r": 0.3483, "wheel_r_rear": 0.3487,
		"wheels": {"FL": Vector3(-0.7988, 0.3486, -1.4255), "FR": Vector3(0.7988, 0.3486, -1.4255), "RL": Vector3(-0.7907, 0.3489, 1.4255), "RR": Vector3(0.7907, 0.3489, 1.4255)},
		"eye": Vector3(-0.375, 1.1495, 0.2441), "wheel_hub": Vector3(-0.375, 0.8895, -0.2459), "column_tilt": -0.3542,
		"head": [Vector3(-0.6925, 0.6564, -1.9622), Vector3(0.6924, 0.6564, -1.9622)], "tail": [Vector3(-0.6872, 0.8444, 2.2381), Vector3(0.5922, 0.85, 2.2688)],
		"box": Vector3(1.883, 1.267, 4.793), "box_center": Vector3(-0.0, 0.7655, 0.105), "door": Vector3(-0.941, 0.86, 0.344),
		"wheel_prop": "RC_M4_Wheel", "wheel_prop_rear": "RC_M4_WheelR", "caliper_prop": "RC_M4_Caliper", "steer_prop": "RC_M4_Steer",
		"kit": true, "tail_mat": true},
	"RC_M2": {
		"wheelbase": 2.7481, "wheel_r": 0.3393,
		"wheels": {"FL": Vector3(-0.7927, 0.3393, -1.3741), "FR": Vector3(0.7927, 0.3393, -1.374), "RL": Vector3(-0.794, 0.3427, 1.374), "RR": Vector3(0.794, 0.3427, 1.3741)},
		"eye": Vector3(-0.375, 1.1392, 0.3291), "wheel_hub": Vector3(-0.375, 0.8792, -0.1909), "column_tilt": -0.3746,
		"head": [Vector3(-0.7272, 0.6553, -1.8798), Vector3(0.7272, 0.6553, -1.8798)], "tail": [Vector3(-0.6973, 0.7724, 2.1339), Vector3(0.6973, 0.7724, 2.134)],
		"box": Vector3(1.885, 1.294, 4.577), "box_center": Vector3(0.0, 0.7546, 0.0696), "door": Vector3(-0.943, 0.86, 0.429),
		"wheel_prop": "RC_M2_Wheel", "caliper_prop": "RC_M2_Caliper", "steer_prop": "RC_M2_Steer",
		"kit": true, "tail_mat": true},
	"RC_M5": {
		"wheelbase": 3.007, "wheel_r": 0.3691,
		"wheels": {"FL": Vector3(-0.8397, 0.3691, -1.5034), "FR": Vector3(0.8397, 0.3691, -1.5036), "RL": Vector3(-0.8246, 0.3736, 1.5035), "RR": Vector3(0.8246, 0.3736, 1.5035)},
		"eye": Vector3(-0.395, 1.2312, 0.2154), "wheel_hub": Vector3(-0.395, 0.9712, -0.2746), "column_tilt": -0.3903,
		"head": [Vector3(-0.7912, 0.7932, -2.0378), Vector3(0.7907, 0.7924, -2.0412)], "tail": [Vector3(-0.6516, 0.8975, 2.4045), Vector3(0.6516, 0.8975, 2.4045)],
		"box": Vector3(1.967, 1.394, 5.093), "box_center": Vector3(0.0, 0.8328, 0.1118), "door": Vector3(-0.984, 0.86, 0.315),
		"wheel_prop": "RC_M5_Wheel", "caliper_prop": "RC_M5_Caliper", "steer_prop": "RC_M5_Steer",
		"kit": true, "tail_mat": true},
}


static func get_ref(model: String) -> Dictionary:
	if model == "TCar_Taxi":
		model = "TCar_Sedan_Silver"          # the yellow cab is the same traffic-kit sedan
	var r: Dictionary = GENERIC.duplicate(true)
	for k in MODELS.get(model, {}):
		r[k] = MODELS[model][k]
	return r
