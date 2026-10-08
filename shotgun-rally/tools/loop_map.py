"""The LAKESHORE LOOP: cut up's one map (the same every time), designed here and
written as data for scripts/stage/loop_gen.gd:

    python3 tools/loop_map.py [--png out.png] [--profile out.png]

A real highway, not a circle: an irregular loop of straights and big sweepers
(the corners of a polygon rounded off, 500-1,600 m: AASHTO's minimum at 110 km/h
is ~500 m), ~28 km, through four stretches:
  * CITY: an elevated expressway between towers, on- and off-ramps, overpasses
  * LAKESHORE: along the water, then over it on suspension bridges (a big one,
    1,100 m main span like the Golden Gate's 1,280, and two smaller, ~600 m like
    Tokyo's Rainbow Bridge's 570), deck 35-50 m above the water
  * HILLS: sweepers, grades up to 4 %, three tunnels through the hills
  * back to the CITY
A divided highway: four lanes each way (3.6 m), a concrete median barrier
between, the traffic the other way on the far carriageway.

Writes data/maps/lakeshore_loop.json:
  pieces       the centreline as StageGen pieces (straights and arcs), closing exactly
  y            the road's height every STEP m (smoothed, grades limited, closing)
  bank         its cross-fall every STEP m (+: the right side down), for the curves
  zones        [{s0, s1, kind}] the stretches ("city", "lake", "hills")
  support      [{s0, s1, kind}] what holds the road up: "ground" (embankment or cut),
               "viaduct" (pillars), "bridge" (a suspension bridge), "tunnel"
  bridges      [{s0, s1, towers: [s, s], deck, sag, name}]
  tunnels      [{s0, s1, name}]
  ramps        [{s, side, kind ("on"/"off"), len}]
  overpasses   [{s, angle}]
  gantries     [{s, text}]
  lakes        [{x, z, a, b, rot, depth}] (ellipses; the water is at y = 0)
  hills        [{x, z, r, h}] (bumps on the land, which is otherwise ~4 m up)
  city         [{x, z, r}] (where the towers stand)
The world's x is east, z south (Godot's: -z is the way the loop starts).
"""
import json
import math
import os
import struct
import sys
import zlib

STEP = 2.0
TARGET = 28000.0
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "data", "maps", "lakeshore_loop.json")

# The polygon (km, x east, y north) and each corner's radius (m), clockwise.
# The start is on the first leg (city), heading east.
CORNERS = [
    (0.0, 0.0, 900),     # 0  city, south
    (2.3, -0.35, 1100),  # 1
    (3.9, 0.45, 800),    # 2  an S through the city
    (5.5, 0.15, 1000),   # 3
    (7.1, 1.3, 900),     # 4  into the hills
    (7.6, 3.2, 1300),    # 5
    (6.8, 5.0, 1000),    # 6  out of the hills to the lake
    (5.0, 6.0, 900),     # 7  the big bridge's leg starts
    (2.2, 6.25, 900),    # 8  (big bridge between 7 and 8)
    (0.4, 5.3, 1200),    # 9  (second bridge between 8 and 9)
    (-1.1, 3.9, 1100),   # 10 (third bridge between 9 and 10)
    (-1.6, 2.0, 900),    # 11 lakeshore south to the city
    (-1.0, 0.45, 700),   # 12
]
START_LEG_FRAC = 0.35          # where on leg 0 (0 -> 1) the loop starts


def unit(v):
    l = math.hypot(*v)
    return (v[0] / l, v[1] / l)


def fillet(pts, radii):
    """The polygon's corners rounded off: [(kind, data)] around the loop, starting
    at the corner-0 fillet's end."""
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
        info.append({"p": p1, "din": din, "dout": dout, "ang": ang, "r": r, "t": t})
    legs = []
    for i in range(n):
        a, b = info[i], info[(i + 1) % n]
        l = math.hypot(b["p"][0] - a["p"][0], b["p"][1] - a["p"][1]) - a["t"] - b["t"]
        legs.append(l)
    return info, legs


def build_pieces():
    pts = [(x * 1000.0, y * 1000.0) for x, y, _ in CORNERS]
    radii = [r for _, _, r in CORNERS]
    info, legs = fillet(pts, radii)
    for i, l in enumerate(legs):
        if l < 120.0:
            raise SystemExit("leg %d is %.0f m long: corners too close or radii too big" % (i, l))
    # the loop from the start (part way along leg 0): leg 0's rest, corner 1, leg 1, ... corner 0, leg 0's start
    n = len(pts)
    pieces = [{"kind": "straight", "len": legs[0] * (1 - START_LEG_FRAC)}]
    for k in range(1, n + 1):
        c = info[k % n]
        pieces.append({"kind": "arc", "dir": -1 if c["ang"] > 0 else 1, "r": c["r"], "ang": abs(c["ang"]), "r2": 0.0, "ang2": 0.0})
        if k < n:
            pieces.append({"kind": "straight", "len": legs[k]})
    pieces.append({"kind": "straight", "len": legs[0] * START_LEG_FRAC})
    total = sum(p["len"] if p["kind"] == "straight" else p["r"] * p["ang"] for p in pieces)
    # scaled to a whole number of steps near the target (scaling a closed loop keeps it closed)
    k = round(TARGET / STEP) * STEP / total
    for p in pieces:
        if p["kind"] == "straight":
            p["len"] *= k
        else:
            p["r"] *= k
    return pieces, k


def sample(pieces):
    """The centreline every STEP m, as StageGen._sample walks it: (x, z), heading."""
    ks = []
    for pc in pieces:
        if pc["kind"] == "straight":
            ks.append([pc["len"], 0.0])
        else:
            ks.append([pc["r"] * pc["ang"], pc["dir"] / pc["r"]])
    pts = [(0.0, 0.0)]
    hs = [0.0]
    curv = [0.0]
    x = z = h = 0.0
    qi = 0
    left = ks[0][0]
    while qi < len(ks):
        need = STEP
        dh = 0.0
        while need > 1e-6 and qi < len(ks):
            take = min(need, left)
            dh += take * ks[qi][1]
            need -= take
            left -= take
            if left <= 1e-6:
                qi += 1
                if qi < len(ks):
                    left = ks[qi][0]
        if need > 1e-6:
            break
        mid = h + dh * 0.5
        x += math.sin(mid) * STEP
        z -= math.cos(mid) * STEP
        h += dh
        pts.append((x, z))
        hs.append(h)
        curv.append(dh / STEP)
    return pts, hs, curv


# ── the stretches, the structures ───────────────────────────────────────────

def leg_ranges(pieces):
    """[(s0, s1)] of each straight piece, in order."""
    out = []
    s = 0.0
    for p in pieces:
        l = p["len"] if p["kind"] == "straight" else p["r"] * p["ang"]
        if p["kind"] == "straight":
            out.append((s, s + l))
        s += l
    return out


def design(pieces, pts, length):
    legs = leg_ranges(pieces)
    # legs: 0 start (rest of leg 0), then legs 1..12, then the start's first part
    def leg(i):
        return legs[i]
    zones = []
    # city: the start to the middle of leg 3, and from the middle of leg 12 to the end
    zones.append({"s0": 0.0, "s1": sum(leg(3)) / 2, "kind": "city"})
    zones.append({"s0": sum(leg(3)) / 2, "s1": leg(6)[1], "kind": "hills"})
    zones.append({"s0": leg(6)[1], "s1": sum(leg(11)) / 2, "kind": "lake"})
    zones.append({"s0": sum(leg(11)) / 2, "s1": length, "kind": "city"})

    bridges = []
    def bridge(name, lg, main, side, deck):
        a, b = leg(lg)
        mid = (a + b) / 2
        s0, s1 = mid - main / 2 - side, mid + main / 2 + side
        if s0 < a - 1 or s1 > b + 1:
            raise SystemExit("%s doesn't fit its leg (%.0f m for %.0f m)" % (name, b - a, s1 - s0))
        bridges.append({"name": name, "s0": round(s0, 1), "s1": round(s1, 1), "towers": [round(mid - main / 2, 1), round(mid + main / 2, 1)],
                        "main": main, "deck": deck, "sag": round(main / 9.5, 1), "tower_h": round(main * 0.11 + 8, 1)})
    bridge("KAIGAN GRAND BRIDGE", 7, 1100.0, 330.0, 48.0)
    bridge("SHIRASAGI BRIDGE", 8, 620.0, 200.0, 36.0)
    bridge("MINATO BRIDGE", 9, 560.0, 180.0, 34.0)

    tunnels = []
    def tunnel(name, lg, f0, f1):
        a, b = leg(lg)
        tunnels.append({"name": name, "s0": round(a + (b - a) * f0, 1), "s1": round(a + (b - a) * f1, 1)})
    tunnel("HIGASHIYAMA TUNNEL", 4, 0.15, 0.62)
    tunnel("KITAMINE TUNNEL", 5, 0.25, 0.85)
    tunnel("TAKIZAWA TUNNEL", 6, 0.3, 0.6)

    ramps = []
    for lg, f in ((0, 0.45), (1, 0.55), (2, 0.5), (11, 0.62), (12, 0.45), (13, 0.5)):
        a, b = leg(lg)
        s = a + (b - a) * f
        ramps.append({"s": round(s - 260, 1), "side": "right", "kind": "off", "len": 230.0})
        ramps.append({"s": round(s + 260, 1), "side": "right", "kind": "on", "len": 380.0})
        ramps.append({"s": round(s + 200, 1), "side": "left", "kind": "off", "len": 230.0})
        ramps.append({"s": round(s - 300, 1), "side": "left", "kind": "on", "len": 380.0})
    overpasses = []
    for lg, f, ang in ((1, 0.2, 70), (2, 0.85, 95), (3, 0.3, 60), (5, 0.05, 80), (12, 0.8, 75), (13, 0.15, 100)):
        a, b = leg(lg)
        overpasses.append({"s": round(a + (b - a) * f, 1), "angle": ang})
    gantries = []
    exits = ["EXIT 1  MINAMI", "EXIT 2  CHUO", "EXIT 3  HIGASHI", "EXIT 4  SAKURA", "EXIT 5  NISHI", "EXIT 6  KOEN"]
    for i, r in enumerate([r for r in ramps if r["kind"] == "off" and r["side"] == "right"]):
        gantries.append({"s": round(r["s"] - 700, 1), "text": exits[i % len(exits)], "km": 1.0})
        gantries.append({"s": round(r["s"] - 150, 1), "text": exits[i % len(exits)], "km": 0.0})
    return zones, bridges, tunnels, ramps, overpasses, gantries


# ── the height of the road ──────────────────────────────────────────────────

CITY_GROUND = 4.0
VIADUCT = 11.0                 # the expressway's deck above the city's streets


def in_ranges(s, ranges, margin=0.0):
    for r in ranges:
        if r["s0"] - margin <= s <= r["s1"] + margin:
            return r
    return None


def elevation(n, zones, bridges, tunnels):
    """The road's height every STEP m: targets by stretch and structure, then
    smoothed and its grade limited (4 %), closing on itself."""
    target = [None] * n
    weight = [0.0] * n
    for i in range(n):
        s = i * STEP
        z = in_ranges(s, zones)
        kind = z["kind"] if z else "city"
        # the stretch's own level
        if kind == "city":
            y = CITY_GROUND + VIADUCT + 2.0 * math.sin(s / 900.0)
        elif kind == "lake":
            y = 7.0 + 1.5 * math.sin(s / 700.0)
        else:
            y = 38.0 + 22.0 * math.sin((s - zones[1]["s0"]) / (zones[1]["s1"] - zones[1]["s0"]) * math.pi) + 6.0 * math.sin(s / 650.0)
        target[i] = y
        weight[i] = 0.2
        b = in_ranges(s, bridges)
        if b:
            # the deck: highest in the middle of the main span (a crown), down to its ends
            mid = (b["towers"][0] + b["towers"][1]) / 2
            half = (b["s1"] - b["s0"]) / 2
            u = (s - mid) / half
            target[i] = b["deck"] + 2.0 - 4.0 * u * u
            weight[i] = 5.0
        else:
            # the approaches: never lower than a 3.5 % climb to the nearest deck can make up
            # (between two bridges close together the road stays up, on a viaduct)
            for b2 in bridges:
                ds = min(abs(s - b2["s0"]), abs(s - b2["s1"]), abs(s + n * STEP - b2["s0"]), abs(s - n * STEP - b2["s1"]))
                need = b2["deck"] - 2.0 - 0.035 * ds
                if need > target[i]:
                    target[i] = need
                    weight[i] = max(weight[i], 1.0)
        t = in_ranges(s, tunnels)
        if t:
            weight[i] = max(weight[i], 0.3)
    # smoothing: weighted towards the targets, the neighbours pulling it level
    y = target[:]
    for it in range(400):
        ny = y[:]
        for i in range(n):
            a, b = y[i - 1], y[(i + 1) % n]
            w = weight[i]
            ny[i] = (a + b + w * target[i]) / (2.0 + w)
        y = ny
    # the grade limited to 4 % (in both directions round the loop), keeping the bridges' decks
    lim = 0.04 * STEP
    for it in range(60):
        changed = False
        for i in range(2 * n):
            j, k = i % n, (i + 1) % n
            if y[k] - y[j] > lim and weight[k] < 5.0:
                y[k] = y[j] + lim
                changed = True
            elif y[j] - y[k] > lim and weight[k] < 5.0:
                y[k] = y[j] - lim
                changed = True
        for i in range(2 * n, 0, -1):
            j, k = i % n, (i - 1) % n
            if y[k] - y[j] > lim and weight[k] < 5.0:
                y[k] = y[j] + lim
                changed = True
            elif y[j] - y[k] > lim and weight[k] < 5.0:
                y[k] = y[j] - lim
                changed = True
        if not changed:
            break
    # a final light smoothing so the grade changes are vertical curves, not kinks
    # long vertical curves (a moving average over ~200 m, twice: the decks too, so their
    # ends meet the approaches without a step): no kinks to launch a car at 200 km/h
    w = 50
    for it in range(2):
        pre = [0.0]
        for i in range(-w, n + w):
            pre.append(pre[-1] + y[i % n])
        y = [(pre[i + 2 * w + 1] - pre[i]) / (2 * w + 1) for i in range(n)]
    return y


def banking(curv):
    """Cross-fall every STEP m: up to 4 % in the curves, eased in over ~150 m."""
    n = len(curv)
    raw = [max(-0.04, min(0.04, c * 35.0)) for c in curv]       # (R 875 m: 4 %)
    out = raw[:]
    w = 75
    pre = [0.0]
    for i in range(-w, n + w):
        pre.append(pre[-1] + raw[i % n])
    for i in range(n):
        out[i] = (pre[i + 2 * w + 1] - pre[i]) / (2 * w + 1)
    return out


# ── the land: lakes, hills, the city ───────────────────────────────────────

def land(pts, length, zones, bridges, tunnels, y):
    lakes = []
    for b in bridges:
        i0, i1 = int(b["s0"] / STEP), int(b["s1"] / STEP)
        a, c = pts[i0], pts[i1]
        mx, mz = (a[0] + c[0]) / 2, (a[1] + c[1]) / 2
        ang = math.atan2(c[1] - a[1], c[0] - a[0])
        span = math.hypot(c[0] - a[0], c[1] - a[1])
        # the water: across the bridge's whole length (the shores under its side spans), and
        # far out each side of it
        lakes.append({"x": round(mx, 1), "z": round(mz, 1), "a": round(span * 0.5 - 60, 1), "b": round(span * 0.9 + 900, 1),
                      "rot": round(ang, 4), "depth": 22.0})
    # one big lake inside the loop, its shore along the road between the bridges
    n = len(pts)
    cx = sum(p[0] for p in pts) / n
    cz = sum(p[1] for p in pts) / n
    lz = zones[2]
    mids = [pts[int((b["s0"] + b["s1"]) / 2 / STEP)] for b in bridges]
    mx = sum(m[0] for m in mids) / len(mids)
    mz = sum(m[1] for m in mids) / len(mids)
    dx, dz = cx - mx, cz - mz
    dl = math.hypot(dx, dz)
    big = {"x": mx + dx / dl * 1500.0, "z": mz + dz / dl * 1500.0, "a": 1500.0, "b": 1100.0, "rot": math.atan2(dz, dx), "depth": 18.0}
    # shrunk until it keeps 140 m from the road everywhere but the bridges
    for it in range(40):
        near = min(math.hypot(pts[i][0] - big["x"], pts[i][1] - big["z"]) - max(big["a"], big["b"]) for i in range(0, n, 10)
                   if not in_ranges(i * STEP, bridges, 50.0))
        if near > 140.0:
            break
        big["a"] *= 0.95
        big["b"] *= 0.95
    lakes.append({k: round(v, 4 if k == "rot" else 1) for k, v in big.items()})
    hills = []
    # the hills carry the road: a ridge of broad mounds just under it all through the stretch
    hz = zones[1]
    s = hz["s0"]
    while s <= hz["s1"]:
        i = int(s / STEP) % n
        hills.append({"x": round(pts[i][0], 1), "z": round(pts[i][1], 1), "r": 520.0, "h": round(y[i] - 2.0, 1)})
        s += 250.0
    for t in tunnels:
        i0, i1 = int(t["s0"] / STEP), int(t["s1"] / STEP)
        for f in (0.25, 0.5, 0.75):
            i = int(i0 + (i1 - i0) * f)
            r = max(240.0, (t["s1"] - t["s0"]) * 0.38)
            hills.append({"x": round(pts[i][0], 1), "z": round(pts[i][1], 1), "r": round(r, 1), "h": round(y[i] + 34.0, 1)})
    city = []
    for zz in zones:
        if zz["kind"] != "city":
            continue
        s = zz["s0"] + 150
        while s < zz["s1"] - 150:
            i = int(s / STEP) % len(pts)
            city.append({"x": round(pts[i][0], 1), "z": round(pts[i][1], 1), "r": 650.0})
            s += 500
    return lakes, hills, city


def hills_wild(zones, pts, length):
    """More hills round the hills stretch, back from the road (it goes round them)."""
    out = []
    z = zones[1]
    s = z["s0"] + 300
    k = 0
    while s < z["s1"] - 300:
        i = int(s / STEP)
        x, zz = pts[i]
        h0 = pts[max(0, i - 1)]
        dx, dz = x - h0[0], zz - h0[1]
        l = math.hypot(dx, dz) or 1.0
        rx, rz = -dz / l, dx / l
        for side in (-1, 1):
            off = 650 + 250 * ((k * 7919) % 5) / 4
            out.append({"x": round(x + rx * off * side, 1), "z": round(zz + rz * off * side, 1), "r": 420.0 + 60 * (k % 3), "h": 70.0 + 25 * ((k * 31) % 4)})
        s += 700
        k += 1
    return out


# ── pictures ────────────────────────────────────────────────────────────────

def png(path, w, h, px):
    raw = b"".join(b"\x00" + bytes(px[y * w * 3:(y + 1) * w * 3]) for y in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def picture(path, data, pts):
    W = H = 1000
    xs = [p[0] for p in pts]
    zs = [p[1] for p in pts]
    pad = 1500
    x0, x1, z0, z1 = min(xs) - pad, max(xs) + pad, min(zs) - pad, max(zs) + pad
    sc = min(W / (x1 - x0), H / (z1 - z0))
    px = bytearray([200, 214, 170] * W * H)

    def put(x, z, c, r=1):
        u = int((x - x0) * sc)
        v = int((z - z0) * sc)
        for du in range(-r + 1, r):
            for dv in range(-r + 1, r):
                if 0 <= u + du < W and 0 <= v + dv < H:
                    k = ((v + dv) * W + u + du) * 3
                    px[k:k + 3] = bytes(c)

    # the land's height and water, coarse
    for v in range(0, H, 2):
        for u in range(0, W, 2):
            x = x0 + u / sc
            z = z0 + v / sc
            hgt = height(data, x, z)
            if hgt < 0:
                c = (70, 120, 170)
            elif in_city(data, x, z):
                c = (175, 172, 168)
            else:
                g = max(0, min(1, hgt / 140.0))
                c = (int(150 - 60 * g), int(185 - 50 * g), int(120 - 50 * g))
            for du in (0, 1):
                for dv in (0, 1):
                    if u + du < W and v + dv < H:
                        k = ((v + dv) * W + u + du) * 3
                        px[k:k + 3] = bytes(c)
    n = len(pts)
    for i in range(n):
        s = i * STEP
        c = (40, 40, 40)
        if in_ranges(s, data["bridges"]):
            c = (220, 40, 40)
        elif in_ranges(s, data["tunnels"]):
            c = (250, 210, 40)
        put(pts[i][0], pts[i][1], c, 2)
    for r in data["ramps"]:
        i = int(r["s"] / STEP) % n
        put(pts[i][0], pts[i][1], (255, 255, 255) if r["side"] == "right" else (0, 0, 255), 4)
    put(pts[0][0], pts[0][1], (0, 200, 0), 7)
    png(path, W, H, px)


def profile(path, y, data):
    W, H = 1400, 300
    px = bytearray([245, 245, 245] * W * H)
    n = len(y)
    for u in range(W):
        i = int(u / W * n)
        s = i * STEP
        top = int(H - 20 - y[i] * 2.5)
        c = (60, 60, 60)
        if in_ranges(s, data["bridges"]):
            c = (220, 40, 40)
        elif in_ranges(s, data["tunnels"]):
            c = (220, 170, 20)
        for v in range(max(0, top - 2), min(H, top + 2)):
            k = (v * W + u) * 3
            px[k:k + 3] = bytes(c)
        v = H - 20
        k = (v * W + u) * 3
        px[k:k + 3] = bytes((70, 120, 170))
    png(path, W, H, px)


LAND = 4.0


def mound(hl, x, z):
    """A hill's height at x, z: a round top falling away smoothly to the land at 2 r."""
    d2 = ((x - hl["x"]) ** 2 + (z - hl["z"]) ** 2) / (hl["r"] ** 2)
    if d2 >= 4.0:
        return LAND
    t = 1.0 - d2 / 4.0
    return LAND + (hl["h"] - LAND) * t * t * (3.0 - 2.0 * t)


def height(data, x, z):
    """The land's height (no small bumps: loop_gen.gd adds those): the highest of the
    hills there (a hill on a hill doesn't add up), the lakes carved out of it."""
    h = LAND
    for hl in data["hills"]:
        h = max(h, mound(hl, x, z))
    for lk in data["lakes"]:
        c, s = math.cos(-lk["rot"]), math.sin(-lk["rot"])
        dx, dz = x - lk["x"], z - lk["z"]
        u = (dx * c - dz * s) / lk["a"]
        v = (dx * s + dz * c) / lk["b"]
        e = u * u + v * v
        if e < 1.6:
            sh = min(1.0, max(0.0, (1.3 - e) / 0.3))       # shore band
            h = h * (1 - sh) + (-lk["depth"]) * sh
    return h


def in_city(data, x, z):
    for c in data["city"]:
        if (x - c["x"]) ** 2 + (z - c["z"]) ** 2 < c["r"] ** 2:
            return True
    return False


def main():
    pieces, k = build_pieces()
    pts, hs, curv = sample(pieces)
    n = len(pts) - 1
    length = n * STEP
    gap = math.hypot(pts[-1][0] - pts[0][0], pts[-1][1] - pts[0][1])
    turn = (hs[-1] - hs[0]) / (2 * math.pi)
    print("length %.0f m (scale %.3f), closes within %.3f m, turns %.4f times" % (length, k, gap, turn))
    if gap > 0.5 or abs(abs(turn) - 1.0) > 1e-3:
        raise SystemExit("the loop doesn't close")
    rmin = min(p["r"] for p in pieces if p["kind"] == "arc")
    print("tightest corner R %.0f m; %d pieces" % (rmin, len(pieces)))
    pts = pts[:n]
    zones, bridges, tunnels, ramps, overpasses, gantries = design(pieces, pts, length)
    y = elevation(n, zones, bridges, tunnels)
    bank = banking(curv[:n])
    lakes, hills, city = land(pts, length, zones, bridges, tunnels, y)
    hills += hills_wild(zones, pts, length)
    data = {"name": "LAKESHORE LOOP", "length": length, "step": STEP, "pieces": pieces,
            "y": [round(v, 2) for v in y], "bank": [round(v, 4) for v in bank],
            "zones": [{k2: (round(v, 1) if isinstance(v, float) else v) for k2, v in z.items()} for z in zones],
            "bridges": bridges, "tunnels": tunnels, "ramps": ramps, "overpasses": overpasses, "gantries": gantries,
            "lakes": lakes, "hills": hills, "city": city, "city_ground": CITY_GROUND}
    # what holds the road up, sample by sample, from the land under it
    support = []
    cur = None
    for i in range(n):
        s = i * STEP
        if in_ranges(s, bridges):
            kind = "bridge"
        elif in_ranges(s, tunnels):
            kind = "tunnel"
        else:
            g = height(data, pts[i][0], pts[i][1])
            kind = "viaduct" if y[i] - max(g, 0.0) > 5.0 else "ground"
        if cur and cur["kind"] == kind:
            cur["s1"] = s + STEP
        else:
            cur = {"s0": s, "s1": s + STEP, "kind": kind}
            support.append(cur)
    # (short bits of one kind between two of another are the other: no 20 m of embankment mid-viaduct)
    merged = []
    for sp in support:
        if merged and sp["s1"] - sp["s0"] < 60.0 and sp["kind"] in ("ground", "viaduct"):
            merged[-1]["s1"] = sp["s1"]
        elif merged and merged[-1]["kind"] == sp["kind"]:
            merged[-1]["s1"] = sp["s1"]
        else:
            merged.append(dict(sp))
    data["support"] = merged
    # checks: the grade, the bridges' decks over the water, the tunnels under the hills
    g = max(abs(y[(i + 1) % n] - y[i]) / STEP for i in range(n))
    print("steepest grade %.1f %%" % (100 * g))
    for b in bridges:
        i = int((b["towers"][0] + b["towers"][1]) / 2 / STEP)
        print("%s: %.0f m long, main span %.0f m, deck %.0f m over the water there (land %.0f)" % (
            b["name"], b["s1"] - b["s0"], b["main"], y[i], height(data, *pts[i])))
    for t in tunnels:
        i = int((t["s0"] + t["s1"]) / 2 / STEP)
        print("%s: %.0f m, %.0f m of hill over the road in the middle" % (t["name"], t["s1"] - t["s0"], height(data, *pts[i]) - y[i]))
    print("support: %s" % ", ".join("%s %.1f km" % (k2, sum(s["s1"] - s["s0"] for s in merged if s["kind"] == k2) / 1000)
                                    for k2 in ("ground", "viaduct", "bridge", "tunnel")))
    json.dump(data, open(OUT, "w"), separators=(",", ":"))
    print("wrote %s (%d KB)" % (os.path.normpath(OUT), os.path.getsize(OUT) // 1024))
    args = sys.argv[1:]
    if "--png" in args:
        picture(args[args.index("--png") + 1], data, pts)
    if "--profile" in args:
        profile(args[args.index("--profile") + 1], y, data)


if __name__ == "__main__":
    main()
