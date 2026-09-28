"""Upper-body emote clip: pose track -> rig keys (arms, spine, head) + fx flags.
Legs are left to the game (so it plays standing or sitting).

  python3 convert_upper.py track.json out.json T0 T1 KIND
KIND: smoke_cough | smoke_chill | watch | finger
Flags baked per frame: mouth (0..1 open), puff (1 = smoke out), cough (1 = cough),
at_mouth (1 = cigarette at the lips)."""
import json, sys, numpy as np

d = json.load(open(sys.argv[1])); OUT = sys.argv[2]
T0, T1 = float(sys.argv[3]), float(sys.argv[4]); KIND = sys.argv[5]
FPS_IN = d["fps"]; FPS_OUT = 15; BLEND = 0.5
frames = d["frames"][int(T0 * FPS_IN): int(T1 * FPS_IN)]
W = np.array([f["w"] for f in frames]); P = W[:, :, :3] * np.array([-1, -1, 1]); VIS = W[:, :, 3]
k = 5; ker = np.ones(k) / k
sm = lambda a: np.convolve(np.pad(a, (k // 2, k // 2), mode="edge"), ker, "valid")
P = np.stack([np.stack([sm(P[:, j, a]) for a in range(3)], -1) for j in range(33)], 1)
VIS = np.stack([sm(VIS[:, j]) for j in range(33)], 1)
N = len(P)
ARM_IN = 0.29; APOSE = np.radians(20)

def Rx(a): c, s = np.cos(a), np.sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
def Ry(a): c, s = np.cos(a), np.sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
def Rz(a): c, s = np.cos(a), np.sin(a); return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
def E(v): return Ry(v[1]) @ Rx(v[0]) @ Rz(v[2])
DOWN = np.array([0, -1, 0.0])
def nrm(v): return v / (np.linalg.norm(v) + 1e-9)
def arm_fk(p, side):
    a = Rz(side * APOSE) @ DOWN
    q = E([p[0], p[1], p[2] - side * ARM_IN])
    return q @ a, q @ Rx(p[3]) @ a
def cost(p, side, Ut, Ft, prev):
    U, F = arm_fk(p, side)
    pen = np.array([0.0, 0.5, 0.3 * (1.0 if side * p[2] > 0 else 0.15), 0.0]) * p
    return np.concatenate([U - Ut, F - Ft, pen, 0.25 * (p - prev)])
def fit_arm(Ut, Ft, side, prev):
    best = None
    for p0 in [prev, np.array([1.4, 0, 0, 0.1]), np.array([0.5, 0, 0, 1.5]), np.array([0.1, 0, 0, 0.3]),
               np.array([0.9, 0.4 * side, 0, 2.0]), np.array([1.0, -0.5 * side, 0.1 * side, 1.4])]:
        p = p0.copy()
        for _ in range(30):
            r = cost(p, side, Ut, Ft, prev)
            J = np.zeros((len(r), 4))
            for i in range(4):
                dp = np.zeros(4); dp[i] = 1e-4
                J[:, i] = (cost(p + dp, side, Ut, Ft, prev) - r) / 1e-4
            step = np.linalg.lstsq(J.T @ J + 1e-3 * np.eye(4), -J.T @ r, rcond=None)[0]
            p = p + step; p[3] = np.clip(p[3], 0.0, 2.6); p[1] = np.clip(p[1], -1.0, 1.0)
            if np.linalg.norm(step) < 1e-5: break
        c = float(np.sum(cost(p, side, Ut, Ft, prev) ** 2))
        if best is None or c < best[0]: best = (c, p)
    return best[1]

# arm poses when the hand is out of shot (below the frame)
REST = {"smoke_cough": {1: [0.2, 0.15, 0.05, 1.0], -1: [0.05, 0, -0.05, 0.35]},
        "smoke_chill": {1: [0.2, 0.15, 0.05, 1.0], -1: [0.05, 0, -0.05, 0.35]},
        "watch": {1: [0.05, 0, 0.05, 0.3], -1: [0.05, 0, -0.05, 0.3]},
        "finger": {1: [0.05, 0, 0.05, 0.3], -1: [0.05, 0, -0.05, 0.3]}}[KIND]

def chest(J):
    x = nrm(J[12] - J[11]); hipmid = (J[23] + J[24]) / 2; shmid = (J[11] + J[12]) / 2
    up = nrm(shmid - hipmid) if VIS[0, 23] > 0.3 else np.array([0, 1.0, 0])
    u = nrm(up - np.dot(up, x) * x); z = np.cross(x, u)
    return np.stack([x, u, z], 1), shmid

# Key poses on the rig (shoulder euler x,y,z + elbow), checked with --dancecheck.
# The video drives WHEN and HOW FAR (hand-to-mouth distance, wrist height), the
# pose drives WHERE on our rig: close-up, camera-facing arms are too ambiguous
# to fit joint-by-joint.
POSES = {   # [shoulder x, y, z, elbow bend, elbow swing]
    "smoke": {"rest": {1: [0.2, 0.15, 0.05, 1.0, 0.0], -1: [0.05, 0, -0.05, 0.35, 0.0]},
              "up": {1: [0.8, 0.45, 0.1, 2.55, 1.2]}},                       # cigarette at the lips
    "watch": {"rest": {1: [0.05, 0, 0.05, 0.3, 0.0], -1: [0.05, 0, -0.05, 0.3, 0.0]},
              "up": {-1: [0.5, 0.0, -0.55, 1.7, -1.4]}},                     # forearm flat across the chest
    "finger": {"rest": {1: [0.05, 0, 0.05, 0.3, 0.0], -1: [0.05, 0, -0.05, 0.3, 0.0]},
               "up": {-1: [1.2, -0.7, 0.0, 1.75, 0.0]}},                     # bird in front of the face
}["smoke" if KIND.startswith("smoke") else KIND]

heads = []
for f in range(N):
    C, shmid = chest(P[f])
    v = C.T @ (P[f][0] - shmid)          # nose from the shoulders, in the chest frame
    heads.append([np.arctan2(-v[2], v[1]), np.arctan2(-v[0], -v[2])])
heads = np.array(heads)
h0 = np.median(heads, 0) if KIND.startswith("smoke") else heads[:8].mean(0)   # arm-down start = neutral
keys = {k: [] for k in ["shL", "shR", "elL", "elR", "spine_rx", "spine_ry", "head_rx", "head_ry", "mouth", "puff", "cough", "at_mouth"]}
for f in range(N):
    J = P[f]
    C, shmid = chest(J)
    mouth = (J[9] + J[10]) / 2
    if KIND.startswith("smoke"):
        raise_ = float(np.clip((0.3 - np.linalg.norm(J[20] - mouth)) / 0.2, 0, 1))     # right index to lips
    else:
        wy = (J[15] - shmid)[1]
        top = -0.07 if KIND == "finger" else -0.17
        raise_ = float(np.clip((wy + 0.46) / (0.46 + top), 0, 1))                      # left wrist height
    raise_ = raise_ * raise_ * (3 - 2 * raise_)
    for side, key in [(1, "R"), (-1, "L")]:
        a = np.array(POSES["rest"][side]); b = np.array(POSES["up"].get(side, POSES["rest"][side]))
        p = a + (b - a) * raise_
        keys["sh" + key].append([round(float(x), 3) for x in p[:3]])
        keys["el" + key].append([round(float(p[3]), 3), round(float(p[4]), 3), 0.0])
    hx = (heads[f, 0] - h0[0]) * 1.6          # + = head down/forward
    hy = (heads[f, 1] - h0[1]) * 1.2          # + = turn to its left
    keys["head_rx"].append(round(float(np.clip(hx, -0.6, 0.7)), 3))
    keys["head_ry"].append(round(float(np.clip(hy, -0.7, 0.7)), 3))
    at_mouth = raise_ if KIND.startswith("smoke") else 0.0
    keys["at_mouth"].append(round(at_mouth, 2))
    cough = 1.0 if (KIND == "smoke_cough" and hx > 0.18) else 0.0
    exhale = 1.0 if (KIND.startswith("smoke") and hx < -0.08 and at_mouth < 0.2) else 0.0
    keys["cough"].append(cough)
    keys["puff"].append(max(exhale, cough))
    keys["mouth"].append(round(max(exhale * 0.8, cough), 2))
    # the body: a cough folds you forward; the chill take leans back a touch
    lean = -0.3 * cough + (0.06 if KIND == "smoke_chill" else 0.0)
    keys["spine_rx"].append(round(lean, 3))
    keys["spine_ry"].append(round(float(np.clip(hy * 0.25, -0.2, 0.2)), 3))

# resample + loop blend
t_in = np.arange(N) / FPS_IN; n_out = int((T1 - T0) * FPS_OUT); t_out = np.arange(n_out) / FPS_OUT
nb = int(BLEND * FPS_OUT); final = {}
for key, arr in keys.items():
    a = np.array(arr, dtype=float)
    if a.ndim == 1: a = a[:, None]
    r = np.stack([np.interp(t_out, t_in, a[:, c]) for c in range(a.shape[1])], 1)
    tail = []
    for i in range(nb):
        w = (i + 1) / (nb + 1); w = w * w * (3 - 2 * w)
        tail.append((1 - w) * r[-1] + w * r[0])
    r = np.vstack([r] + tail)
    if key in ("puff", "cough"): r = np.round(r)
    final[key] = [[round(float(x), 3) for x in row] for row in r] if r.shape[1] > 1 else [round(float(x), 3) for x in r[:, 0]]
json.dump({"fps": FPS_OUT, "frames": len(final["mouth"]), "source": "rotoscoped from the owner's clip (%s)" % KIND,
           "upper_only": True, "keys": final}, open(OUT, "w"), separators=(",", ":"))
print(KIND, "frames", len(final["mouth"]), "puffs", int(sum(final["puff"])), "coughs", int(sum(final["cough"])))
for kk in ["shL", "shR", "elL", "elR"]:
    v = np.array(final[kk]); print(" ", kk, "min", v.min(0).round(2), "max", v.max(0).round(2))
v = np.array(final["head_rx"]); print("  head_rx", v.min().round(2), v.max().round(2))
