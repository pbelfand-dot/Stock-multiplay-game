"""CINDER RIDGE: Track Mode's permanent circuit (the same every time), designed here
and written as data for scripts/stage/circuit_gen.gd:

    python3 tools/circuit_map.py [--png out.png] [--profile out.png]

A real racing circuit, not a loop of sweepers: ~5.3 km clockwise, a long pit straight
into a heavy-braking hairpin (T1), a climbing technical section (the esses), fast
sweepers over the top of the ridge, a long descending back straight into a chicane,
a double-apex right and a fast final corner back onto the straight. Corner radii,
widths, kerbs, run-off and barriers follow FIA Grade 1 practice loosely: 12 m of
track (15 m on the pit straight), kerbs outside the white line, run-off sized by the
approach speed (asphalt where the braking is heaviest, gravel at the fast corners,
grass inside), tyre walls where a car would arrive fast, armco and concrete with
debris fencing elsewhere.

The centreline is a polygon's corners rounded off (exact closure), its curvature then
eased over ~16 m so no corner starts with a step in it (the residual gap, centimetres,
spread round the lap). Everything is in metres, every STEP m (sample i is s = i * STEP,
s = 0 the start/finish line, the lap's direction clockwise, d > 0 to the right).

Writes data/maps/cinder_ridge.json:
  name, length, step
  x, z, heading, curv  the centreline every STEP m (x east, z south: Godot's)
  y                    its height every STEP m (smoothed, grades limited, closing)
  bank                 cross-fall every STEP m (+: the right side down), the corners' camber
  half                 the track's half-width every STEP m (to the white lines)
  corners              [{n, name, dir, s0, s_apex, s1, r_min, angle, v_apex, v_entry}]
  kerbs                [{s0, s1, side (+1 right / -1 left), w, kind ("apex"/"exit"/"chicane")}]
  runoff_l, runoff_r   [{s0, s1, kind ("grass"/"gravel"/"asphalt"), w}] (from the track's edge)
  barrier_l, barrier_r [{s0, s1, kind ("armco"/"tyres"/"wall"), d}] (d: from the centreline)
  pit                  {side, s_in0, s_in1, s_lim0, s_box0, s_box1, s_lim1, s_out0, s_out1,
                        wall_d, lane_d0, lane_d1, fast_d, box_d, garage_d, limit_kmh, boxes}
  grid                 [{k, s, d}] the starting grid, pole first
  sectors              [s1, s2] (sector 1 ends at sectors[0], 2 at sectors[1]; 3 at the line)
  drs                  [{detect, s0, s1}] the activation zones and their detection points
  marshals             [{s, side}]
  boards               [{s, side, m}] distance boards (300 / 200 / 100) before the big stops
  stands               [{s0, s1, side, rows}] grandstands
  lights               [{s, side}] floodlight towers (night)
  hills                [{x, z, r, h}] the land's mounds round the circuit
  lap_estimate         a GT3's lap (s) on the racing line, from the speed profile below (a sanity check)
  line, line_curv      the racing line: its offset from the centreline (m, + right) and its curvature, every
                       STEP m (minimum curvature inside the white lines; the racing AI drives it)
"""
import json
import math
import os
import struct
import sys
import zlib

STEP = 2.0
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "data", "maps", "cinder_ridge.json")
NAME = "CINDER RIDGE"

# The polygon (m, x east, y north), each corner's radius (m) and name, clockwise. The start/finish
# line is on the first leg (the pit straight), heading east, START_FRAC of the way along.
LAYOUT = [
    # (x, y, r, name)
    (0.0, 0.0, 92.0, "THE HOOK"),
    (1180.0, 0.0, 24.0, "CINDER HAIRPIN"),
    (1180.0, -150.0, 24.0, None),           # (the hairpin's second half)
    (930.0, -150.0, 46.0, "QUARRY"),
    (880.0, -370.0, 40.0, "ESSES"),
    (690.0, -440.0, 55.0, None),
    (640.0, -660.0, 70.0, "CHAPEL"),
    (360.0, -840.0, 220.0, "RIDGE"),
    (-120.0, -870.0, 260.0, "SKYLINE"),
    (-470.0, -700.0, 120.0, "DESCENT"),
    (-470.0, -260.0, 300.0, None),           # (a kink on the back straight)
    (-560.0, 120.0, 60.0, "FALCON"),         # (the back straight ends: the turn back east)
    (-430.0, 300.0, 34.0, "CHICANE"),        # chicane: left
    (-360.0, 260.0, 34.0, None),             # ... right
    (-230.0, 330.0, 75.0, "MILLER"),          # double apex right
    (-90.0, 250.0, 75.0, None),
    (-40.0, 130.0, 160.0, "THE KINK"),       # (flat out: the run down to the hook)
]
START_FRAC = 0.55            # where on the pit straight the start/finish line is

# the lap's height: (fraction of the lap from the line, height m), smoothed round the lap
HEIGHTS = [(0.00, 0.0), (0.06, -0.5), (0.11, -2.0), (0.18, 5.0), (0.25, 16.0), (0.32, 28.0), (0.38, 38.0), (0.45, 43.0),
           (0.51, 40.0), (0.57, 27.0), (0.63, 13.0), (0.70, 3.0), (0.76, 2.0), (0.81, 8.0), (0.86, 6.0), (0.91, 1.0), (1.00, 0.0)]
MAX_GRADE = 0.075


def unit(v):
    l = math.hypot(*v)
    return (v[0] / l, v[1] / l)


def fillet(pts, radii):
    n = len(pts)
    info = []
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        din = unit((p1[0] - p0[0], p1[1] - p0[1]))
        dout = unit((p2[0] - p1[0], p2[1] - p1[1]))
        cross = din[0] * dout[1] - din[1] * dout[0]
        ang = math.atan2(cross, din[0] * dout[0] + din[1] * dout[1])   # + = left (counter-clockwise)
        r = radii[i]
        t = r * math.tan(abs(ang) / 2)
        info.append({"p": p1, "ang": ang, "r": r, "t": t})
    legs = []
    for i in range(n):
        a, b = info[i], info[(i + 1) % n]
        legs.append(math.hypot(b["p"][0] - a["p"][0], b["p"][1] - a["p"][1]) - a["t"] - b["t"])
    return info, legs


def build_pieces():
    pts = [(c[0], c[1]) for c in LAYOUT]
    radii = [c[2] for c in LAYOUT]
    info, legs = fillet(pts, radii)
    for i, l in enumerate(legs):
        if l < 20.0:
            raise SystemExit("leg %d (after corner %d) is %.0f m long: corners too close or radii too big" % (i, i, l))
    n = len(pts)
    pieces = [{"kind": "straight", "len": legs[0] * (1 - START_FRAC)}]
    for k in range(1, n + 1):
        c = info[k % n]
        pieces.append({"kind": "arc", "dir": -1 if c["ang"] > 0 else 1, "r": c["r"], "ang": abs(c["ang"]), "corner": k % n})
        if k < n:
            pieces.append({"kind": "straight", "len": legs[k]})
    pieces.append({"kind": "straight", "len": legs[0] * START_FRAC})
    return pieces, legs


def sample(pieces):
    """Curvature every STEP m (+: right), eased; heading and the centreline from it."""
    ks = []
    for pc in pieces:
        if pc["kind"] == "straight":
            ks.append([pc["len"], 0.0])
        else:
            ks.append([pc["r"] * pc["ang"], pc["dir"] / pc["r"]])
    total = sum(k[0] for k in ks)
    n = int(round(total / STEP))
    # the lap scaled the hair it takes to be a whole number of steps (closure is kept by scaling)
    sc = n * STEP / total
    ks = [[k[0] * sc, k[1] / sc] for k in ks]
    raw = []
    qi = 0
    left = ks[0][0]
    for i in range(n):
        need = STEP
        dh = 0.0
        while need > 1e-9 and qi < len(ks):
            take = min(need, left)
            dh += take * ks[qi][1]
            need -= take
            left -= take
            if left <= 1e-9:
                qi += 1
                if qi < len(ks):
                    left = ks[qi][0]
        raw.append(dh / STEP)
    # ease the curvature (a triangular window of +-8 samples, round the lap): no steps
    w = 8
    wts = [w + 1 - abs(j) for j in range(-w, w + 1)]
    sw = float(sum(wts))
    curv = [sum(raw[(i + j) % n] * wts[j + w] for j in range(-w, w + 1)) / sw for i in range(n)]
    # the heading and the line from it; the residual gap spread round the lap
    hs = [0.0] * (n + 1)
    xs = [0.0] * (n + 1)
    zs = [0.0] * (n + 1)
    for i in range(n):
        dh = curv[i] * STEP
        mid = hs[i] + dh * 0.5
        hs[i + 1] = hs[i] + dh
        xs[i + 1] = xs[i] + math.sin(mid) * STEP
        zs[i + 1] = zs[i] - math.cos(mid) * STEP
    gx, gz = xs[n] - xs[0], zs[n] - zs[0]
    turn = hs[n] / (2 * math.pi)
    for i in range(n + 1):
        xs[i] -= gx * i / n
        zs[i] -= gz * i / n
    return xs[:n], zs[:n], hs[:n], curv, math.hypot(gx, gz), turn, sc


# ── what the lap is like ─────────────────────────────────────────────────────

def speed_profile(curv):
    """A GT3's speed every STEP m (m/s): grip with downforce in the corners, power and
    drag on the straights, braking from ~1.6 g; returns (v, lap time)."""
    n = len(curv)
    vmax = []
    for c in curv:
        r = 1.0 / max(abs(c), 1e-6)
        # lateral grip grows with the square of speed (aero): solve v^2 / r = g (1.45 + 0.45 (v/70)^2)
        a = 1.0 / r - 9.81 * 0.45 / 4900.0
        v = math.sqrt(9.81 * 1.45 / a) if a > 0 else 80.0
        vmax.append(min(v, 80.0))
    v = vmax[:]
    # forward: power-limited acceleration (fades with speed), twice round to settle
    for _ in range(2):
        for i in range(n):
            j = (i + 1) % n
            acc = max(0.4, 7.5 * (1.0 - (v[i] / 82.0) ** 2))
            v[j] = min(vmax[j], math.sqrt(v[i] ** 2 + 2 * acc * STEP))
    for _ in range(2):
        for i in range(n - 1, -1, -1):
            j = i - 1
            dec = 13.5 + 4.0 * (v[i] / 80.0) ** 2
            v[j] = min(v[j], math.sqrt(v[i] ** 2 + 2 * dec * STEP))
    t = sum(STEP / max(x, 1.0) for x in v)
    return v, t


def racing_line(xs, zs, hs, half, kerbs, n):
    """The racing line: offsets d (m, + right) from the centreline every STEP m that bend the
    path as little as the track allows (minimum curvature: out wide, clip the apex, out wide
    again), the car's middle at least CAR_HALF + a margin inside the white lines (a little more
    on a corner's inside kerb, where a driver puts two wheels). Solved as bounded least squares:
    the path's second differences (its curvature) as small as the track's width allows. Returns
    (d, the line's curvature, its length per sample)."""
    import numpy as np
    C = np.stack([np.array(xs), np.array(zs)], 1)
    R = np.stack([np.cos(hs), np.sin(hs)], 1)                # right of the way round
    hw = np.array(half)
    lo = -(hw - 1.4)
    hi = hw - 1.4
    for kb in kerbs:                                         # (two wheels on an inside kerb: 0.6 m more room)
        if kb["kind"] not in ("apex", "chicane"):
            continue
        i0, i1 = int(kb["s0"] / STEP), int(kb["s1"] / STEP)
        idx = [(i0 + k) % n for k in range((i1 - i0) % n + 1)]
        if kb["side"] > 0:
            hi[idx] = hw[idx] - 0.8
        else:
            lo[idx] = -(hw[idx] - 0.8)
    # minimise the sum of the path's squared second differences (its curvature x STEP^2), the
    # offsets bounded: a sparse bounded least-squares problem (scipy), solved exactly
    import scipy.sparse as sp
    from scipy.optimize import lsq_linear
    rows, cols, vals = [], [], []
    bx = np.zeros(n)
    bz = np.zeros(n)
    for i in range(n):
        for j, w in ((i - 1, 1.0), (i, -2.0), (i + 1, 1.0)):
            jj = j % n
            rows += [i, n + i]
            cols += [jj, jj]
            vals += [w * R[jj, 0], w * R[jj, 1]]
            bx[i] += w * C[jj, 0]
            bz[i] += w * C[jj, 1]
    A = sp.csr_matrix((vals, (rows, cols)), shape=(2 * n, n))
    b = -np.concatenate([bx, bz])
    res = lsq_linear(A, b, bounds=(lo, hi), method="bvls" if n < 500 else "trf", lsmr_tol="auto", max_iter=5000, tol=1e-10)
    d = res.x
    P = C + R * d[:, None]
    # the line's curvature (signed: + right, as the centreline's)
    a = np.roll(P, -1, 0) - P
    b = P - np.roll(P, 1, 0)
    cross = b[:, 0] * a[:, 1] - b[:, 1] * a[:, 0]
    la = np.linalg.norm(a, axis=1)
    lb = np.linalg.norm(b, axis=1)
    ang = np.arcsin(np.clip(cross / np.maximum(la * lb, 1e-9), -1, 1))
    k = ang / np.maximum((la + lb) * 0.5, 1e-6)
    # (ease it: the sampled path's curvature is noisy)
    k = np.convolve(np.concatenate([k[-4:], k, k[:4]]), np.ones(9) / 9.0, mode="valid")
    seg = la                                                 # (the line's own length per sample: shorter on the inside)
    return [float(x) for x in d], [float(x) for x in k], [float(x) for x in seg]


def find_corners(curv, v, pieces):
    """The corners: runs of curvature above 1/700 m, the same-handed ones within 40 m of
    each other one corner (a double apex), with the layout's names."""
    n = len(curv)
    on = [abs(c) > 1.0 / 700.0 for c in curv]
    runs = []
    i0 = next(i for i in range(n) if not on[i])
    i = i0 + 1
    cur = None
    for k in range(n):
        j = (i0 + 1 + k) % n
        if on[j]:
            sgn = 1 if curv[j] > 0 else -1
            if cur and cur["dir"] == sgn and (j - cur["i1"]) % n <= 1:
                cur["i1"] = j
            else:
                cur = {"i0": j, "i1": j, "dir": sgn}
                runs.append(cur)
        else:
            cur = None
    merged = []
    for r in runs:
        if merged and merged[-1]["dir"] == r["dir"] and (r["i0"] - merged[-1]["i1"]) % n * STEP < 40.0:
            merged[-1]["i1"] = r["i1"]
        else:
            merged.append(dict(r))
    if len(merged) > 1 and merged[0]["dir"] == merged[-1]["dir"] and (merged[0]["i0"] - merged[-1]["i1"]) % n * STEP < 40.0:
        merged[0]["i0"] = merged[-1]["i0"]
        merged.pop()
    out = []
    for r in merged:
        idx = [(r["i0"] + k) % n for k in range((r["i1"] - r["i0"]) % n + 1)]
        # the apex: the tightest bit's middle (an arc's curvature plateaus: its middle), where
        # the inside kerb is clipped; the corner's speed is its slowest
        k_max = max(abs(curv[q]) for q in idx)
        tight = [k for k, q in enumerate(idx) if abs(curv[q]) >= k_max * 0.97]
        apex = idx[(tight[0] + tight[-1]) // 2]
        slow = min(idx, key=lambda q: v[q])
        ang = sum(curv[q] for q in idx) * STEP
        out.append({"dir": r["dir"], "s0": r["i0"] * STEP, "s1": ((r["i1"] + 1) % n) * STEP, "s_apex": apex * STEP,
                    "r_min": round(1.0 / max(abs(curv[q]) for q in idx), 1), "angle": round(math.degrees(abs(ang)), 1),
                    "v_apex": round(v[slow] * 3.6), "v_entry": round(max(v[(r["i0"] - k) % n] for k in range(0, 60)) * 3.6),
                    "_idx": idx})
    out.sort(key=lambda c: c["s0"])
    return out


def name_corners(corners, pieces):
    """Names from the layout: each arc piece's s, matched to the corner holding it."""
    s = 0.0
    named = []
    for pc in pieces:
        l = pc["len"] if pc["kind"] == "straight" else pc["r"] * pc["ang"]
        if pc["kind"] == "arc":
            nm = LAYOUT[pc["corner"]][3]
            if nm:
                named.append((s + l / 2, nm))
        s += l
    total = s
    for k, c in enumerate(corners):
        c["n"] = k + 1
        c["name"] = ""
        for sm, nm in named:
            sm2 = sm * (len(c["_idx"]) and 1.0)
            if c["s0"] <= sm2 <= c["s1"] or (c["s1"] < c["s0"] and (sm2 >= c["s0"] or sm2 <= c["s1"])):
                c["name"] = nm
                break
    return corners


def ranges_merge(items):
    out = []
    for it in items:
        if out and out[-1]["kind"] == it["kind"] and abs(out[-1]["s1"] - it["s0"]) < 1e-6 and abs(out[-1].get("w", 0) - it.get("w", 0)) < 1e-6 \
                and abs(out[-1].get("d", 0) - it.get("d", 0)) < 1e-6:
            out[-1]["s1"] = it["s1"]
        else:
            out.append(dict(it))
    return out


def design(n, curv, v, corners, half, length):
    """Kerbs, run-off, barriers, the pits, the grid, sectors, DRS, marshals, boards, stands, lights."""
    kerbs = []
    for c in corners:
        idx = c["_idx"]
        m = len(idx)
        side = c["dir"]                      # the inside (a right-hander's inside is its right: d > 0)
        chic = c["name"] == "CHICANE" or c["r_min"] < 40.0 and c["angle"] < 70.0
        kind = "chicane" if chic else "apex"
        a, b = idx[int(m * 0.25)], idx[min(m - 1, int(m * 0.8))]
        kerbs.append({"s0": a * STEP, "s1": b * STEP, "side": side, "w": 1.3 if not chic else 1.8, "kind": kind})
        # the exit kerb on the outside, from the apex to 20 m past the corner
        e0 = idx[int(m * 0.55)]
        e1 = (idx[-1] + 10) % n
        kerbs.append({"s0": e0 * STEP, "s1": e1 * STEP, "side": -side, "w": 1.5, "kind": "exit"})
        if c["v_entry"] - c["v_apex"] > 60:  # the outside on the way in too, where it's braked hard
            b0 = (idx[0] - 20) % n
            kerbs.append({"s0": b0 * STEP, "s1": idx[int(m * 0.2)] * STEP, "side": -side, "w": 1.2, "kind": "entry"})
    # run-off and barriers, sample by sample, then merged into ranges
    out_kind = [["grass"] * n, ["grass"] * n]        # [left, right]
    out_w = [[10.0] * n, [10.0] * n]
    bar_kind = [["armco"] * n, ["armco"] * n]
    for c in corners:
        idx = c["_idx"]
        outside = 0 if c["dir"] > 0 else 1           # a right-hander's outside is its left (index 0)
        vin = c["v_entry"]
        w = max(14.0, min(58.0, 14.0 + (vin - 90.0) * 0.30))
        kind = "asphalt" if vin - c["v_apex"] > 140 else ("gravel" if c["v_apex"] > 95 else "asphalt")
        # from 40 m before the corner to 60 m after it
        span = [(idx[0] - 20 + k) % n for k in range(len(idx) + 50)]
        for q in span:
            out_kind[outside][q] = kind
            out_w[outside][q] = max(out_w[outside][q], w)
            bar_kind[outside][q] = "tyres" if vin > 130 else "armco"
        for q in idx:                                 # the inside: grass, narrower
            out_w[1 - outside][q] = max(out_w[1 - outside][q], 8.0)
    # ease the widths (no steps), keep them at least 10 m
    for side in (0, 1):
        raw = out_w[side][:]
        w = 15
        out_w[side] = [max(10.0, max(raw[(i + j) % n] for j in range(-w, w + 1))) for i in range(n)]
    # the pits: on the inside (right) of the pit straight
    s_line = 0.0
    pit = {"side": 1, "s_in0": -470.0, "s_in1": -330.0, "s_lim0": -320.0, "s_box0": -205.0, "s_box1": 75.0,
           "s_lim1": 120.0, "s_out0": 130.0, "s_out1": 300.0, "limit_kmh": 60.0, "boxes": 20}
    hw = 7.5                                          # the pit straight's half-width
    pit.update({"wall_d": hw + 2.0, "lane_d0": hw + 3.0, "fast_d": hw + 6.0, "box_d": hw + 11.5, "lane_d1": hw + 14.0,
                "garage_d": hw + 14.0})
    # the straight's own surroundings: the pit wall and the stands' wall
    for i in range(n):
        s = i * STEP
        ss = s if s < length / 2 else s - length
        if pit["s_in0"] <= ss <= pit["s_out1"]:
            # (the pit side: the pits' own ground from the entry's taper to the exit's end, where the
            # builder puts the pit wall; past the exit the lane runs onto the track, so the
            # straight's usual run-off and barrier start there, clear of the lane's end)
            out_kind[1][i] = "pit"
            out_w[1][i] = 2.0
            bar_kind[1][i] = "wall"
        if pit["s_in0"] - 40 <= ss <= pit["s_out1"] + 40:
            out_kind[0][i] = "grass"
            out_w[0][i] = 12.0
            bar_kind[0][i] = "wall"
    runoff = []
    barriers = []
    for side in (0, 1):
        rr = [{"s0": i * STEP, "s1": (i + 1) * STEP, "kind": out_kind[side][i], "w": round(out_w[side][i], 1)} for i in range(n)]
        runoff.append(ranges_merge(rr))
        sign = -1 if side == 0 else 1
        bb = [{"s0": i * STEP, "s1": (i + 1) * STEP, "kind": bar_kind[side][i],
               "d": round(sign * (half[i] + out_w[side][i] + (0.0 if bar_kind[side][i] != "wall" else 0.0)), 1)} for i in range(n)]
        barriers.append(ranges_merge(bb))
    # the grid: 20 places, 8 m apart along, staggered 6.4 m across; pole on the left (T1 is a right-hander: the line's left)
    grid = [{"k": k, "s": round(length - 14.0 - k * 8.0, 1), "d": -3.2 if k % 2 == 0 else 3.2} for k in range(20)]
    # sectors: the ends of S1 and S2 on straight bits near a third and two thirds round
    def straight_near(s_target):
        best = None
        for i in range(n):
            if abs(curv[i]) < 1 / 1500.0:
                s = i * STEP
                if best is None or abs(s - s_target) < abs(best - s_target):
                    best = s
        return best
    sectors = [straight_near(length * 0.33), straight_near(length * 0.67)]
    # DRS: the pit straight (detection before THE HOOK) and the back straight
    straightish = [abs(curv[j]) < 1 / 250.0 for j in range(n)]
    first_bend = next(j for j in range(n) if not straightish[j])
    long_runs = []
    start = None
    for k in range(n + 1):
        j = (first_bend + k) % n
        if straightish[j] and start is None:
            start = first_bend + k
        elif not straightish[j] and start is not None:
            long_runs.append((start * STEP, (first_bend + k) * STEP))
            start = None
    def stop_after(b):
        # the braking into the corner the run ends at (km/h shed): DRS goes where it makes a pass
        nxt = min(corners, key=lambda c: (c["s1"] - b) % length)          # (the corner the run ends in)
        return nxt["v_entry"] - nxt["v_apex"]
    long_runs = [(a, b) for a, b in long_runs if b - a > 500.0 and stop_after(b % length) > 100]
    long_runs = sorted(long_runs, key=lambda r: r[0] - r[1])[:3]          # (the three longest of those)
    drs = []
    for a, b in long_runs:
        drs.append({"detect": round((a - 180.0) % length, 1), "s0": round((a + 60.0) % length, 1), "s1": round((b - 120.0) % length, 1)})
    # marshal posts: every ~300 m, the side away from the corners' outsides, and one at each corner's exit
    marshals = []
    s = 60.0
    side = -1
    while s < length:
        marshals.append({"s": round(s, 1), "side": side})
        s += 300.0
        side = -side
    for c in corners:
        marshals.append({"s": round(c["s1"] + 30.0, 1) % length, "side": -c["dir"]})
    # distance boards before the big stops (the outside of the run in)
    boards = []
    for c in corners:
        if c["v_entry"] - c["v_apex"] > 70:
            for m in (300, 200, 100):
                boards.append({"s": round((c["s0"] - m) % length, 1), "side": -c["dir"], "m": m})
    # grandstands: along the pit straight (opposite the pits), at the hairpin, the chicane and the final corner
    stands = [{"s0": round(length - 300.0, 1), "s1": 160.0, "side": -1, "rows": 14}]
    for c in corners:
        if c["name"] in ("CINDER HAIRPIN", "CHICANE", "THE HOOK"):
            stands.append({"s0": round((c["s0"] - 30.0) % length, 1), "s1": round((c["s1"] + 40.0) % length, 1), "side": -c["dir"], "rows": 10})
    # floodlights: every 120 m, outside the barriers, alternating
    lights = []
    s = 0.0
    side = 1
    while s < length:
        lights.append({"s": round(s, 1), "side": side})
        s += 120.0
        side = -side
    return kerbs, runoff, barriers, pit, grid, sectors, drs, marshals, boards, stands, lights


def elevation(n, curv):
    """The lap's height from HEIGHTS (smooth, periodic), grades limited, the pit straight flat."""
    y = []
    for i in range(n):
        f = i / n
        for k in range(len(HEIGHTS) - 1):
            a, b = HEIGHTS[k], HEIGHTS[k + 1]
            if a[0] <= f <= b[0]:
                u = (f - a[0]) / (b[0] - a[0])
                u = u * u * (3 - 2 * u)
                y.append(a[1] + (b[1] - a[1]) * u)
                break
    # smooth (+-40 m), then the grade limit, forward and back, round the lap
    for _ in range(3):
        w = 20
        y = [sum(y[(i + j) % n] for j in range(-w, w + 1)) / (2 * w + 1) for i in range(n)]
    for _ in range(4):
        for i in range(n):
            j = (i + 1) % n
            d = y[j] - y[i]
            lim = MAX_GRADE * STEP
            if abs(d) > lim:
                y[j] = y[i] + math.copysign(lim, d)
    return y


def banking(curv):
    """Camber: a corner's inside low, up to 3 % (the right side down: +), eased; 1 % crossfall
    on the straights isn't modelled (the road's drained by its camber)."""
    n = len(curv)
    raw = [max(-0.03, min(0.03, c * 3.0)) for c in curv]
    w = 15
    return [sum(raw[(i + j) % n] for j in range(-w, w + 1)) / (2 * w + 1) for i in range(n)]


def widths(n, length):
    """The half-width every STEP m: 6 m (a 12 m track), 7.5 m on the pit straight."""
    out = []
    for i in range(n):
        s = i * STEP
        ss = s if s < length / 2 else s - length
        if -650.0 <= ss <= 420.0:
            f = 1.0
            if ss < -560.0:
                f = (ss + 650.0) / 90.0
            elif ss > 330.0:
                f = (420.0 - ss) / 90.0
            f = max(0.0, min(1.0, f))
            out.append(6.0 + 1.5 * (f * f * (3 - 2 * f)))
        else:
            out.append(6.0)
    return out


def clearance(xs, zs, n):
    """The closest two parts of the track more than 300 m apart round the lap come (m)."""
    cell = 250.0
    grid = {}
    for i in range(0, n, 2):
        grid.setdefault((int(xs[i] // cell), int(zs[i] // cell)), []).append(i)
    best = 1e9
    where = None
    for i in range(0, n, 2):
        cx, cz = int(xs[i] // cell), int(zs[i] // cell)
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for j in grid.get((cx + dx, cz + dz), []):
                    sep = min((i - j) % n, (j - i) % n) * STEP
                    if sep < 300.0:
                        continue
                    d = math.hypot(xs[i] - xs[j], zs[i] - zs[j])
                    if d < best:
                        best = d
                        where = (i * STEP, j * STEP)
    return best, where


def hills(xs, zs, n):
    """A few mounds round the circuit (the ridge it's named for), clear of the track."""
    cx = sum(xs) / n
    cz = sum(zs) / n
    out = []
    for k, (ang, dist, r, h) in enumerate([(0.3, 1500, 600, 60), (1.4, 1700, 700, 85), (2.6, 1400, 500, 45),
                                           (3.7, 1800, 800, 110), (4.8, 1500, 550, 55), (5.6, 1900, 700, 90)]):
        out.append({"x": round(cx + math.cos(ang) * dist, 1), "z": round(cz + math.sin(ang) * dist, 1), "r": r, "h": h})
    return out


# ── pictures ───────────────────────────────────────────────────────────────

def png(path, w, h, px):
    raw = b"".join(b"\x00" + bytes(px[y * w * 3:(y + 1) * w * 3]) for y in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def picture(path, data):
    W = H = 1000
    xs, zs = data["x"], data["z"]
    n = len(xs)
    pad = 250
    x0, x1, z0, z1 = min(xs) - pad, max(xs) + pad, min(zs) - pad, max(zs) + pad
    sc = min(W / (x1 - x0), H / (z1 - z0))
    px = bytearray([110, 150, 90] * W * H)

    def put(x, z, c, r=1):
        u = int((x - x0) * sc)
        v = int((z - z0) * sc)
        for du in range(-r + 1, r):
            for dv in range(-r + 1, r):
                if 0 <= u + du < W and 0 <= v + dv < H:
                    k = ((v + dv) * W + u + du) * 3
                    px[k:k + 3] = bytes(c)

    def at(i, d):
        h = data["heading"][i]
        rx, rz = math.cos(h), math.sin(h)          # (right of the heading: x east, z south)
        return xs[i] + rx * d, zs[i] + rz * d

    def side_ranges(lst, s):
        for r in lst:
            a, b = r["s0"], r["s1"]
            if (a <= s < b) or (b < a and (s >= a or s < b)):
                return r
        return None

    cols = {"grass": (90, 140, 70), "gravel": (215, 200, 150), "asphalt": (120, 120, 125), "pit": (90, 90, 95)}
    for i in range(n):
        s = i * STEP
        for side, key in ((-1, "runoff_l"), (1, "runoff_r")):
            r = side_ranges(data[key], s)
            if r:
                for k in range(0, int(r["w"]), 2):
                    put(*at(i, side * (data["half"][i] + k)), cols[r["kind"]], 1)
        for side, key in ((-1, "barrier_l"), (1, "barrier_r")):
            r = side_ranges(data[key], s)
            if r:
                put(*at(i, r["d"]), {"armco": (230, 230, 230), "tyres": (20, 20, 20), "wall": (180, 180, 180)}[r["kind"]], 2)
    for i in range(n):
        g = (data["y"][i] + 5) / 40.0
        c = (int(60 + 120 * g), int(60 + 60 * g), int(60))
        for d in range(-int(data["half"][i]), int(data["half"][i]) + 1, 2):
            put(*at(i, d), c, 1)
    for kb in data["kerbs"]:
        i0, i1 = int(kb["s0"] / STEP), int(kb["s1"] / STEP)
        for i in range(i0, i1 if i1 > i0 else i1 + n):
            j = i % n
            put(*at(j, kb["side"] * (data["half"][j] + 0.6)), (230, 30, 30) if (j // 3) % 2 else (250, 250, 250), 2)
    p = data["pit"]
    for s in range(int(p["s_in0"]), int(p["s_out1"]), 2):
        j = int((s % data["length"]) / STEP)
        put(*at(j, p["fast_d"]), (60, 60, 200), 2)
    for g in data["grid"]:
        j = int(g["s"] / STEP)
        put(*at(j, g["d"]), (255, 255, 0), 3)
    for sct in data["sectors"]:
        j = int(sct / STEP)
        for d in range(-8, 9):
            put(*at(j, d), (255, 0, 255), 1)
    for z in data["drs"]:
        for s in range(int(z["s0"]), int(z["s1"] if z["s1"] > z["s0"] else z["s1"] + data["length"]), 8):
            j = int((s % data["length"]) / STEP)
            put(*at(j, 0), (0, 255, 255), 2)
    for d in range(-8, 9):
        put(*at(0, d), (255, 255, 255), 2)
    png(path, W, H, px)


def profile(path, data):
    W, H = 1400, 300
    px = bytearray([245, 245, 245] * W * H)
    y = data["y"]
    n = len(y)
    lo, hi = min(y) - 2, max(y) + 2
    for u in range(W):
        i = int(u / W * n)
        v = int((1 - (y[i] - lo) / (hi - lo)) * (H - 1))
        for vv in range(v, H):
            k = (vv * W + u) * 3
            px[k:k + 3] = bytes((150, 170, 140))
    png(path, W, H, px)


def main():
    pieces, legs = build_pieces()
    xs, zs, hs, curv, gap, turn, sc = sample(pieces)
    n = len(xs)
    length = n * STEP
    print("length %.0f m (scale %.5f), closed within %.3f m (spread round the lap), turns %.4f times" % (length, sc, gap, turn))
    if gap > 8.0 or abs(abs(turn) - 1.0) > 1e-6:
        raise SystemExit("the lap doesn't close")
    if not (4500.0 <= length <= 6000.0):
        raise SystemExit("the lap is %.0f m: Track Mode wants 4.5-6 km" % length)
    v, lap = speed_profile(curv)
    corners = name_corners(find_corners(curv, v, pieces), pieces)
    print("%d corners; a GT3 lap ~%d:%04.1f; top speed %.0f km/h" % (len(corners), int(lap // 60), lap % 60, max(v) * 3.6))
    for c in corners:
        print("  T%-2d %-16s %s R%4.0f %5.1f deg  %3d -> %3d km/h  s %.0f-%.0f" % (c["n"], c["name"], "R" if c["dir"] > 0 else "L",
              c["r_min"], c["angle"], c["v_entry"], c["v_apex"], c["s0"], c["s1"]))
    cl, where = clearance(xs, zs, n)
    print("closest approach of two parts of the lap: %.0f m (s %s)" % (cl, where))
    if cl < 70.0:
        raise SystemExit("two parts of the lap pass within %.0f m" % cl)
    half = widths(n, length)
    y = elevation(n, curv)
    g = max(abs(y[(i + 1) % n] - y[i]) / STEP for i in range(n))
    print("height %.1f to %.1f m, steepest grade %.1f %%" % (min(y), max(y), 100 * g))
    bank = banking(curv)
    kerbs, runoff, barriers, pit, grid, sectors, drs, marshals, boards, stands, lights = design(n, curv, v, corners, half, length)
    line_d, line_k, line_seg = racing_line(xs, zs, hs, half, kerbs, n)
    lv, _ = speed_profile(line_k)
    line_lap = sum(sg / max(x, 1.0) for sg, x in zip(line_seg, lv))
    print("racing line: offsets %.1f to %.1f m, a GT3 lap on it ~%d:%04.1f (the centreline's %d:%04.1f)" % (
        min(line_d), max(line_d), int(line_lap // 60), line_lap % 60, int(lap // 60), lap % 60))
    for c in corners:
        del c["_idx"]
    data = {"name": NAME, "length": length, "step": STEP,
            "x": [round(a, 3) for a in xs], "z": [round(a, 3) for a in zs],
            "heading": [round(a, 5) for a in hs], "curv": [round(a, 6) for a in curv],
            "y": [round(a, 2) for a in y], "bank": [round(a, 4) for a in bank], "half": [round(a, 2) for a in half],
            "corners": corners, "kerbs": [{k: (round(v2, 1) if isinstance(v2, float) else v2) for k, v2 in kb.items()} for kb in kerbs],
            "runoff_l": runoff[0], "runoff_r": runoff[1], "barrier_l": barriers[0], "barrier_r": barriers[1],
            "pit": pit, "grid": grid, "sectors": sectors, "drs": drs, "marshals": marshals, "boards": boards,
            "stands": stands, "lights": lights, "hills": hills(xs, zs, n), "lap_estimate": round(line_lap, 1),
            "line": [round(a, 2) for a in line_d], "line_curv": [round(a, 6) for a in line_k],
            "description": "A 5 km permanent circuit on a wooded ridge: a long pit straight into the CINDER HAIRPIN, the climbing ESSES, "
                           "fast sweepers over the SKYLINE, a plunging back straight to the CHICANE, the MILLER double-apex and THE HOOK onto the straight."}
    print("sectors at %.0f / %.0f m; DRS zones %s" % (sectors[0], sectors[1], [(z["s0"], z["s1"]) for z in drs]))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(data, open(OUT, "w"), separators=(",", ":"))
    print("wrote %s (%d KB)" % (os.path.normpath(OUT), os.path.getsize(OUT) // 1024))
    args = sys.argv[1:]
    if "--png" in args:
        picture(args[args.index("--png") + 1], data)
    if "--profile" in args:
        profile(args[args.index("--profile") + 1], data)


if __name__ == "__main__":
    main()
