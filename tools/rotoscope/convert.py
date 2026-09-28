"""Pose-tracked video -> BAGHOLDERS rig angles (character.gd conventions).
Character space: +x right, +y up, faces -z. Shoulder euler (x,y,z), YXZ order,
acting on a straight-down arm; elbow bends about x (forward)."""
import json, sys, numpy as np
d = json.load(open(sys.argv[1])); OUT = sys.argv[2]
FPS_IN = d["fps"]; T_END = float(sys.argv[3]) if len(sys.argv) > 3 else 11.0; BLEND = 0.6; FPS_OUT = 15
W = np.array([f["w"] for f in d["frames"]])
P = W[:, :, :3] * np.array([-1, -1, 1]); VIS = W[:, :, 3]
# smooth landmarks in time (centered moving average, 5 frames)
k = 5; ker = np.ones(k) / k
Ps = np.stack([np.stack([np.convolve(np.pad(P[:, j, a], (k // 2, k // 2), mode="edge"), ker, "valid") for a in range(3)], -1)
               for j in range(33)], 1)
VISs = np.stack([np.convolve(np.pad(VIS[:, j], (k // 2, k // 2), mode="edge"), ker, "valid") for j in range(33)], 1)
N = int(T_END * FPS_IN)
ARM_IN = 0.29; APOSE = np.radians(20)

def Rx(a): c, s = np.cos(a), np.sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
def Ry(a): c, s = np.cos(a), np.sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
def Rz(a): c, s = np.cos(a), np.sin(a); return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
def E(v): return Ry(v[1]) @ Rx(v[0]) @ Rz(v[2])
DOWN = np.array([0, -1, 0.0])
def nrm(v): return v / (np.linalg.norm(v) + 1e-9)

def arm_fk(p, side):  # side +1 = right arm (+x), -1 = left
    a = Rz(side * APOSE) @ DOWN
    q = E([p[0], p[1], p[2] - side * ARM_IN])
    return q @ a, q @ Rx(p[3]) @ a

def cost_terms(p, side, Ut, Ft, prev):
    U, F = arm_fk(p, side)
    # prefer reaching forward (x) over swinging out sideways (z) + twisting (y),
    # and stay close to last frame so the motion is continuous
    pen = np.array([0.0, 0.9, 0.35 * (1.0 if side * p[2] > 0 else 0.15), 0.0]) * p
    return np.concatenate([U - Ut, F - Ft, pen, 0.25 * (p - prev)])

def fit_arm(Ut, Ft, side, prev, reg=None):
    best = None
    for p0 in [prev, np.array([1.4, 0, 0, 0.1]), np.array([0.5, 0, 0, 1.5]), np.array([0.1, 0, 0, 0.3]),
               np.array([0.9, 0, 0, 1.0])]:
        p = p0.copy()
        for _ in range(30):
            r = cost_terms(p, side, Ut, Ft, prev)
            J = np.zeros((len(r), 4))
            for i in range(4):
                dp = np.zeros(4); dp[i] = 1e-4
                J[:, i] = (cost_terms(p + dp, side, Ut, Ft, prev) - r) / 1e-4
            step = np.linalg.lstsq(J.T @ J + 1e-3 * np.eye(4), -J.T @ r, rcond=None)[0]
            p = p + step
            p[3] = np.clip(p[3], 0.0, 2.6)
            p[1] = np.clip(p[1], -0.8, 0.8)
            if np.linalg.norm(step) < 1e-5: break
        c = float(np.sum(cost_terms(p, side, Ut, Ft, prev) ** 2))
        if best is None or c < best[0]:
            best = (c, p)
    return best[1]

def yaw(v): return np.arctan2(-v[2], v[0])
out = {k: [] for k in ["hips_ry", "spine_ry", "spine_rx", "hips_rz", "shL", "shR", "elL", "elR", "hipL", "hipR", "knL", "knR", "bob"]}
pL = np.array([0.1, 0, -0.05, 0.3]); pR = np.array([0.1, 0, 0.05, 0.3])
yaw0 = None; tw0 = None
HIP_POSE = {1: np.array([-0.25, 0.0, 0.25, 1.6]), -1: np.array([-0.25, 0.0, -0.25, 1.6])}
LT = LS = 0.42 * 0.92
for f in range(N):
    J = Ps[f]
    hr = nrm(J[24] - J[23]); sr = nrm(J[12] - J[11])
    hy, sy = yaw(hr), yaw(sr)
    if yaw0 is None:   # zero = average facing over the front-facing opening
        yaw0 = np.mean([ (yaw(nrm(Ps[i][24]-Ps[i][23])) + yaw(nrm(Ps[i][12]-Ps[i][11]))) / 2 for i in range(int(3.5 * FPS_IN))])
        tw0 = np.mean([ yaw(nrm(Ps[i][12]-Ps[i][11])) - yaw(nrm(Ps[i][24]-Ps[i][23])) for i in range(int(3.5 * FPS_IN))])
    body_yaw = (hy + sy) / 2 - yaw0
    twist = (sy - hy) - tw0
    hipmid = (J[23] + J[24]) / 2; shmid = (J[11] + J[12]) / 2
    # hips frame (yaw only) and chest frame (full)
    Hb = Ry(hy - yaw0)
    up = nrm(shmid - hipmid)
    upl = Hb.T @ up
    lean = np.arctan2(upl[2], upl[1])                 # + = back
    side_lean = -np.arctan2(upl[0], upl[1])
    x = sr; u = nrm(up - np.dot(up, x) * x); z = np.cross(x, u)
    C = np.stack([x, u, z], 1)                        # chest basis (columns)
    res = {}
    for side, (s, e, w), key in [(1, (12, 14, 16), "R"), (-1, (11, 13, 15), "L")]:
        Ut = C.T @ nrm(J[e] - J[s]); Ft = C.T @ nrm(J[w] - J[e])
        p0 = pR if side > 0 else pL
        p = fit_arm(Ut, Ft, side, p0)
        v = min(VISs[f, e], VISs[f, w])
        a = np.clip((v - 0.2) / 0.4, 0, 1)
        p = a * p + (1 - a) * HIP_POSE[side]
        res[key] = p
        if side > 0: pR = p
        else: pL = p
    # legs, in the hips frame
    Hfull = Ry(hy - yaw0)
    drops = []
    for side, (h, kn, an), key in [(1, (24, 26, 28), "R"), (-1, (23, 25, 27), "L")]:
        T = Hfull.T @ nrm(J[kn] - J[h]); S = Hfull.T @ nrm(J[an] - J[kn])
        tx = np.arctan2(-T[2], -T[1])
        tz = np.arcsin(np.clip(T[0], -1, 1))
        bend = max(0.0, np.arccos(np.clip(np.dot(T, S), -1, 1)) - 0.3)
        out["hip" + key].append([float(tx), 0.0, float(tz) * 0.5])
        out["kn" + key].append([float(-bend), 0.0, 0.0])
        drops.append(LT + LS - (LT * np.cos(tx) + LS * np.cos(tx - bend)))
    out["bob"].append(float(-min(drops)))
    out["hips_ry"].append(float(body_yaw)); out["spine_ry"].append(float(twist * 0.5))
    out["spine_rx"].append(float(lean)); out["hips_rz"].append(float(side_lean * 0.5))
    out["shL"].append([float(v) for v in res["L"][:3]]); out["elL"].append([float(res["L"][3]), 0.0, 0.0])
    out["shR"].append([float(v) for v in res["R"][:3]]); out["elR"].append([float(res["R"][3]), 0.0, 0.0])
# ---- corrections the camera can't see (depth ambiguity) --------------------
for f in range(N):
    y = abs(out["hips_ry"][f])
    front = float(np.clip((0.9 - y) / 0.5, 0, 1))     # 1 facing the camera, 0 side-on
    for side, sh, el in [(1, "shR", "elR"), (-1, "shL", "elL")]:
        x, yy, z = out[sh][f]; e = out[el][f][0]
        # facing camera: forearms come up in FRONT of the chest (fists at chest), elbows tucked, no flaring
        z_out = side * z
        z_fix = side * (min(z_out, 0.12) * 0.35) if z_out > 0 else z
        e_fix = float(np.clip(0.7 + (e - 0.25) * 1.45, 0.7, 2.15))
        x_fix = x + 0.18
        out[sh][f] = [x * (1 - front) + x_fix * front, yy * (1 - front), z * (1 - front) + z_fix * front]
        out[el][f] = [e * (1 - front) + e_fix * front, 0.0, 0.0]
    # side-on punches: sit the hips back and lean into the punch (like the clip)
    reach = float(np.clip((out["shL"][f][0] - 0.3) / 0.9, 0, 1)) * (1 - front)
    sitback = (1 - front) * 0.5 + reach * 0.5
    out["spine_rx"][f] = out["spine_rx"][f] * 0.4 - 0.22 * sitback
    for leg in ("hipL", "hipR"):
        out[leg][f][0] += 0.32 * sitback
    for kn in ("knL", "knR"):
        out[kn][f][0] -= 0.3 * sitback
    # keep the feet on the floor with the new leg angles
    drops = []
    for leg, kn in (("hipL", "knL"), ("hipR", "knR")):
        tx = out[leg][f][0]; b = -out[kn][f][0]
        drops.append(LT + LS - (LT * np.cos(tx) + LS * np.cos(tx - b)))
    out["bob"][f] = float(-min(drops))

# resample to FPS_OUT and blend the tail back into frame 0 so it loops
t_in = np.arange(N) / FPS_IN
n_out = int(T_END * FPS_OUT)
t_out = np.arange(n_out) / FPS_OUT
nb = int(BLEND * FPS_OUT)
final = {}
for key, arr in out.items():
    a = np.array(arr, dtype=float)
    if key in ("hips_ry",):
        a = np.unwrap(a)
    if a.ndim == 1: a = a[:, None]
    r = np.stack([np.interp(t_out, t_in, a[:, c]) for c in range(a.shape[1])], 1)
    for i in range(nb):
        w = (i + 1) / (nb + 1); w = w * w * (3 - 2 * w)
        r = np.vstack([r, (1 - w) * r[n_out - 1] + w * r[0]]) if i == 0 else np.vstack([r, (1 - w) * r[n_out - 1] + w * r[0]])
    final[key] = [[round(float(v), 3) for v in row] for row in r] if r.shape[1] > 1 else [round(float(v), 3) for v in r[:, 0]]
L = len(final["bob"])
json.dump({"fps": FPS_OUT, "frames": L, "source": "rotoscoped from the owner's dance clip (MediaPipe pose)", "keys": final},
          open(OUT, "w"), separators=(",", ":"))
print("frames", L, "seconds", L / FPS_OUT)
for key in ["hips_ry", "spine_rx", "bob"]:
    v = np.array(final[key]); print(key, "min %.2f max %.2f" % (v.min(), v.max()))
for key in ["shL", "shR", "elL", "elR", "hipL", "knL"]:
    v = np.array(final[key]); print(key, "min", v.min(0).round(2), "max", v.max(0).round(2))
