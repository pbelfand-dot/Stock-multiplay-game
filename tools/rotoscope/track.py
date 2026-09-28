import json, sys, cv2, mediapipe as mp
from mediapipe.tasks import python as mpt
from mediapipe.tasks.python import vision
V = sys.argv[1]; OUT = sys.argv[2]
opts = vision.PoseLandmarkerOptions(base_options=mpt.BaseOptions(model_asset_path=sys.argv[3] if len(sys.argv) > 3 else "pose_landmarker_heavy.task"),
    running_mode=vision.RunningMode.VIDEO, num_poses=1, min_pose_detection_confidence=0.5, min_tracking_confidence=0.5)
cap = cv2.VideoCapture(V)
fps = cap.get(cv2.CAP_PROP_FPS)
frames = []
with vision.PoseLandmarker.create_from_options(opts) as lm:
    i = 0
    while True:
        ok, img = cap.read()
        if not ok: break
        rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        res = lm.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), int(i * 1000 / fps))
        if res.pose_world_landmarks:
            w = [[p.x, p.y, p.z, p.visibility] for p in res.pose_world_landmarks[0]]
            n = [[p.x, p.y, p.z] for p in res.pose_landmarks[0]]
            frames.append({"t": i / fps, "w": w, "n": n})
        else:
            frames.append({"t": i / fps, "w": None, "n": None})
        i += 1
json.dump({"fps": fps, "frames": frames}, open(OUT, "w"))
print("frames", len(frames), "detected", sum(1 for f in frames if f["w"]), "fps", fps)
