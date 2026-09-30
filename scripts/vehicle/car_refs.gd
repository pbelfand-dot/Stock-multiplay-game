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
	# the used TOROLA: the traffic kit's sedan (built nose to +z, shared Wheel_Car). Its cabin is the kit's
	# (glass + seat backs from PropKit._kit_car_windows) over a solid tub at the beltline (0.97): you sit a
	# little high so the wheel and your hands clear it
	"TCar_Sedan_Silver": {
		"wheelbase": 2.75, "wheel_r": 0.34, "flip": true, "wheel_prop": "Wheel_Car",
		"wheels": {"FL": Vector3(-0.8, 0.34, -1.375), "FR": Vector3(0.8, 0.34, -1.375), "RL": Vector3(-0.8, 0.34, 1.375), "RR": Vector3(0.8, 0.34, 1.375)},
		"eye": Vector3(-0.36, 1.27, 0.2), "wheel_hub": Vector3(-0.36, 1.03, -0.3), "column_tilt": deg_to_rad(22),
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
	"RC_M8": {
		"wheelbase": 2.8337, "wheel_r": 0.3514,
		"wheels": {"FL": Vector3(-0.8031, 0.3514, -1.419), "FR": Vector3(0.8031, 0.3526, -1.4148), "RL": Vector3(-0.8031, 0.3514, 1.419), "RR": Vector3(0.8031, 0.3526, 1.4148)},
		"eye": Vector3(-0.4044, 1.1437, 0.2962), "wheel_hub": Vector3(-0.4044, 0.8837, -0.1938), "column_tilt": -0.3651,
		"head": [Vector3(-0.7277, 0.6515, -2.0031), Vector3(0.7131, 0.6515, -2.0031)], "tail": [Vector3(-0.6405, 0.8407, 2.1671), Vector3(0.6809, 0.877, 2.151)],
		"box": Vector3(1.923, 1.23, 4.882), "box_center": Vector3(-0.0073, 0.7651, 0.0623), "door": Vector3(-0.961, 0.86, 0.396),
		"wheel_prop": "RC_M8_Wheel", "caliper_prop": "RC_M8_Caliper", "steer_prop": "RC_M8_Steer",
		"kit": true, "tail_mat": true},
	"RC_M3": {
		"wheelbase": 2.8485, "wheel_r": 0.3398,
		"wheels": {"FL": Vector3(-0.7893, 0.3398, -1.4242), "FR": Vector3(0.7893, 0.3398, -1.4242), "RL": Vector3(-0.7881, 0.3449, 1.4242), "RR": Vector3(0.7881, 0.3449, 1.4242)},
		"eye": Vector3(-0.3924, 1.1391, 0.2769), "wheel_hub": Vector3(-0.3924, 0.8791, -0.2731), "column_tilt": -0.3789,
		"head": [Vector3(-0.6785, 0.6452, -1.9778), Vector3(0.6785, 0.6452, -1.9778)], "tail": [Vector3(-0.6697, 0.8094, 2.2283), Vector3(0.6697, 0.8094, 2.2283)],
		"box": Vector3(1.883, 1.31, 4.793), "box_center": Vector3(0.0, 0.8, 0.1053), "door": Vector3(-0.942, 0.86, 0.377),
		"wheel_prop": "RC_M3_Wheel", "caliper_prop": "RC_M3_Caliper", "steer_prop": "RC_M3_Steer",
		"kit": true, "tail_mat": true},
	"RC_M3T": {
		"wheelbase": 2.87, "wheel_r": 0.3627,
		"wheels": {"FL": Vector3(-0.7886, 0.3627, -1.435), "FR": Vector3(0.7886, 0.3627, -1.435), "RL": Vector3(-0.7886, 0.3627, 1.435), "RR": Vector3(0.7886, 0.3627, 1.435)},
		"eye": Vector3(-0.374, 1.1699, 0.271), "wheel_hub": Vector3(-0.374, 0.9099, -0.239), "column_tilt": -0.3722,
		"head": [Vector3(-0.6341, 0.6203, -1.9813), Vector3(0.6379, 0.6203, -1.9813)], "tail": [Vector3(-0.554, 0.9179, 2.2211), Vector3(0.5578, 0.9179, 2.2211)],
		"box": Vector3(1.897, 1.342, 4.792), "box_center": Vector3(0.002, 0.81, 0.1054), "door": Vector3(-0.949, 0.86, 0.371),
		"wheel_prop": "RC_M3T_Wheel", "caliper_prop": "RC_M3T_Caliper", "steer_prop": "RC_M3T_Steer",
		"kit": true, "tail_mat": true},
	"RC_G63": {
		"wheelbase": 2.8567, "wheel_r": 0.3929,
		"wheels": {"FL": Vector3(-0.8285, 0.3929, -1.4284), "FR": Vector3(0.8285, 0.3929, -1.4284), "RL": Vector3(-0.8287, 0.3935, 1.4284), "RR": Vector3(0.8287, 0.3935, 1.4284)},
		"eye": Vector3(-0.3911, 1.5037, 0.1508), "wheel_hub": Vector3(-0.3911, 1.3037, -0.3192), "column_tilt": -0.3883,
		"head": [], "tail": [Vector3(-0.6192, 0.925, 2.1107), Vector3(0.6192, 0.925, 2.1107)],
		"box": Vector3(1.956, 1.773, 4.866), "box_center": Vector3(0.0, 1.0477, 0.0703), "door": Vector3(-0.978, 0.86, 0.251),
		"wheel_prop": "RC_G63_Wheel", "caliper_prop": "RC_G63_Caliper", "steer_prop": "RC_G63_Steer",
		"kit": true, "tail_mat": true},
	"RC_GT3RS": {
		"wheelbase": 2.4557, "wheel_r": 0.3879,
		"wheels": {"FL": Vector3(-0.7697, 0.3879, -1.2278), "FR": Vector3(0.7697, 0.3879, -1.2278), "RL": Vector3(-0.7697, 0.3879, 1.2278), "RR": Vector3(0.7697, 0.3879, 1.2278)},
		"eye": Vector3(-0.3435, 1.0455, 0.2449), "wheel_hub": Vector3(-0.3435, 0.8555, -0.2451), "column_tilt": -0.3314,
		"head": [Vector3(-0.6979, 0.7644, -1.6905), Vector3(0.6987, 0.7644, -1.6905)], "tail": [Vector3(-0.5058, 0.8332, 1.9965), Vector3(0.507, 0.8328, 1.9965)],
		"box": Vector3(1.899, 1.219, 4.571), "box_center": Vector3(0.0004, 0.7959, 0.0135), "door": Vector3(-0.95, 0.86, 0.345),
		"wheel_prop": "RC_GT3RS_Wheel", "caliper_prop": "RC_GT3RS_Caliper", "steer_prop": "RC_GT3RS_Steer",
		"kit": true, "tail_mat": true},
	"RC_GRONOS": {
		"wheelbase": 2.8412, "wheel_r": 0.4248,
		"wheels": {"FL": Vector3(-0.8795, 0.4248, -1.4206), "FR": Vector3(0.8795, 0.4248, -1.4206), "RL": Vector3(-0.8936, 0.4253, 1.4206), "RR": Vector3(0.8936, 0.4253, 1.4206)},
		"eye": Vector3(-0.3805, 1.619, 0.1155), "wheel_hub": Vector3(-0.3805, 1.419, -0.3445), "column_tilt": -0.4727,
		"head": [], "tail": [Vector3(-0.5575, 0.898, 2.1475), Vector3(0.2681, 1.5213, 2.0459)],
		"box": Vector3(2.099, 1.834, 4.579), "box_center": Vector3(-0.0, 1.2468, -0.0367), "door": Vector3(-1.049, 0.86, 0.216),
		"wheel_prop": "RC_GRONOS_Wheel", "caliper_prop": "RC_GRONOS_Caliper", "steer_prop": "RC_GRONOS_Steer",
		"kit": true, "tail_mat": true},
	"RC_911TS": {
		"wheelbase": 2.4423, "wheel_r": 0.3343, "wheel_r_rear": 0.3478,
		"wheels": {"FL": Vector3(-0.7602, 0.3353, -1.2212), "FR": Vector3(0.7567, 0.3353, -1.2212), "RL": Vector3(-0.7721, 0.3478, 1.2212), "RR": Vector3(0.7757, 0.3478, 1.2212)},
		"eye": Vector3(-0.3435, 1.1055, 0.1949), "wheel_hub": Vector3(-0.3435, 0.8555, -0.2451), "column_tilt": -0.3314,
		"head": [Vector3(-0.7043, 0.6679, -1.6398), Vector3(0.6991, 0.6679, -1.6398)], "tail": [Vector3(-0.5267, 0.7244, 1.9466), Vector3(0.5274, 0.7241, 1.9455)],
		"box": Vector3(1.913, 1.194, 4.532), "box_center": Vector3(0.0072, 0.7176, 0.0096), "door": Vector3(-0.956, 0.86, 0.295),
		"wheel_prop": "RC_911TS_Wheel", "wheel_prop_rear": "RC_911TS_WheelR", "caliper_prop": "RC_911TS_Caliper", "steer_prop": "RC_911TS_Steer",
		"kit": true, "tail_mat": true},
	"RC_RS6": {
		"wheelbase": 2.9285, "wheel_r": 0.3664,
		"wheels": {"FL": Vector3(-0.8234, 0.3664, -1.4643), "FR": Vector3(0.8234, 0.3664, -1.4642), "RL": Vector3(-0.8134, 0.3664, 1.4642), "RR": Vector3(0.8134, 0.3664, 1.4643)},
		"eye": Vector3(-0.38, 1.1727, 0.1282), "wheel_hub": Vector3(-0.38, 0.9127, -0.3918), "column_tilt": -0.3597,
		"head": [], "tail": [Vector3(-0.6171, 0.8635, 2.326), Vector3(0.6134, 0.8664, 2.3236)],
		"box": Vector3(1.949, 1.352, 4.993), "box_center": Vector3(0.0, 0.8196, 0.0744), "door": Vector3(-0.975, 0.86, 0.228),
		"wheel_prop": "RC_RS6_Wheel", "caliper_prop": "RC_RS6_Caliper", "steer_prop": "RC_RS6_Steer",
		"kit": true, "tail_mat": true},
	"RC_R8": {
		"wheelbase": 2.65, "wheel_r": 0.32, "wheel_r_rear": 0.33,
		"wheels": {"FL": Vector3(-0.816, 0.32, -1.325), "FR": Vector3(0.816, 0.32, -1.325), "RL": Vector3(-0.7965, 0.33, 1.325), "RR": Vector3(0.7965, 0.33, 1.325)},
		"eye": Vector3(-0.353, 1.0425, -0.0117), "wheel_hub": Vector3(-0.353, 0.7825, -0.4917), "column_tilt": -0.4014,
		"head": [Vector3(-0.6489, 0.5434, -1.942), Vector3(0.658, 0.5434, -1.9362)], "tail": [Vector3(-0.5701, 0.784, 1.7026), Vector3(0.5701, 0.784, 1.7026)],
		"box": Vector3(2.03, 1.143, 4.432), "box_center": Vector3(0.0, 0.6762, -0.1082), "door": Vector3(-1.015, 0.86, 0.088),
		"wheel_prop": "RC_R8_Wheel", "wheel_prop_rear": "RC_R8_WheelR", "caliper_prop": "RC_R8_Caliper", "steer_prop": "RC_R8_Steer",
		"kit": true, "tail_mat": true},
	"RC_ETRONGT": {
		"wheelbase": 2.9089, "wheel_r": 0.3565,
		"wheels": {"FL": Vector3(-0.8223, 0.3565, -1.4544), "FR": Vector3(0.8171, 0.3565, -1.4544), "RL": Vector3(-0.8223, 0.3565, 1.4544), "RR": Vector3(0.8276, 0.3565, 1.4544)},
		"eye": Vector3(-0.3652, 1.1345, 0.0728), "wheel_hub": Vector3(-0.3652, 0.8745, -0.3672), "column_tilt": -0.3711,
		"head": [Vector3(-0.7429, 0.7031, -2.059), Vector3(0.7498, 0.7031, -2.059)], "tail": [Vector3(-0.5094, 0.8996, 2.129), Vector3(0.5158, 0.8995, 2.1293)],
		"box": Vector3(1.974, 1.262, 4.989), "box_center": Vector3(0.0034, 0.7643, 0.0283), "door": Vector3(-0.987, 0.86, 0.173),
		"wheel_prop": "RC_ETRONGT_Wheel", "steer_prop": "RC_ETRONGT_Steer",
		"kit": true, "tail_mat": true},
}


static func get_ref(model: String) -> Dictionary:
	if model == "TCar_Taxi":
		model = "TCar_Sedan_Silver"          # the yellow cab is the same traffic-kit sedan
	var r: Dictionary = GENERIC.duplicate(true)
	for k in MODELS.get(model, {}):
		r[k] = MODELS[model][k]
	return r
