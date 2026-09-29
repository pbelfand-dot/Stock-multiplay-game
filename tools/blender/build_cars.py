"""BAGHOLDERS traffic cars — placeholder vehicles for the highway (built in Blender, bpy).

Run:  python3 tools/blender/build_cars.py
Out:  assets/props/cars_kit.glb      bodies + wheels (wheels are separate props so they can spin)
      assets/props/cars_layout.json  per model: length, width, wheel prop, axle z's, track, radius

Clean, chunky, recognizable stand-ins (sedan, SUV, pickup, box truck, taxi, compact)
in a couple of colors each; the owner will drop real cars in later. Every body is
under 2.5K triangles. Origin = floor center, nose = +Z (Godot space), like the
props kit cars. Wheels: origin at the wheel center, axle along X.
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit_common import (reset, rbox, cyl, extrude, finish, export, tris_of, KIT)  # noqa: E402

HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "..", "..", "assets", "props", "cars_kit.glb")
LAYOUT = os.path.join(HERE, "..", "..", "assets", "props", "cars_layout.json")

GLASS = (0.1, 0.13, 0.17)
TRIM = (0.09, 0.09, 0.1)
CHROME = (0.78, 0.8, 0.84)
HEAD = (1.0, 0.98, 0.86)
TAIL = (0.95, 0.08, 0.06)
AMBER = (1.0, 0.6, 0.1)
PLATE = (0.92, 0.92, 0.88)
LAYOUTS = {}


def lower(z_rear, z_front, y_bot, wheels, R, wy):
    """Bottom edge of a side profile (z, y), rear -> front, with a wheel-arch notch
    of radius R centered (wz, wy) for every wheel in `wheels`."""
    pts = [(z_rear, y_bot)]
    for wz in sorted(wheels):
        pts.append((wz - R, y_bot))
        for k in range(0, 9):
            a = math.pi - math.pi * k / 8.0
            pts.append((wz + R * math.cos(a), wy + R * math.sin(a)))
        pts.append((wz + R, y_bot))
    pts.append((z_front, y_bot))
    return pts


def lights(W, y, z_front, z_rear, h=0.12, inset=0.28, head_w=0.38):
    for sx in (-1, 1):
        x = sx * (W / 2 - inset)
        rbox((head_w, h, 0.05), (x, y, z_front + 0.015), HEAD, kind="Glow")
        rbox((head_w, h, 0.05), (x, y, z_rear - 0.015), TAIL, kind="Glow")
        rbox((0.1, h * 0.7, 0.05), (sx * (W / 2 - 0.08), y, z_front + 0.01), AMBER, kind="Glow")


def plates(y, z_front, z_rear):
    rbox((0.5, 0.12, 0.02), (0, y, z_front + 0.03), PLATE)
    rbox((0.5, 0.12, 0.02), (0, y, z_rear - 0.03), PLATE)


def mirrors(W, y, z):
    for sx in (-1, 1):
        rbox((0.16, 0.12, 0.08), (sx * (W / 2 + 0.06), y, z), TRIM, r=0.02)


def car_body(name, body, kind="sedan", roof_sign=False):
    """Passenger cars: side-profile extrusions + a glass greenhouse + details."""
    if kind == "sedan":
        L, W, r, wb = 4.7, 1.84, 0.34, 2.75
        low = [(-2.35, 0.95), (-2.36, 0.62), (-2.3, 0.3), (2.3, 0.3), (2.37, 0.55), (2.3, 0.82), (1.2, 0.97), (-1.45, 1.0)]
        cab = [(-1.5, 0.96), (-0.95, 1.42), (0.3, 1.46), (1.15, 0.95)]
        roof_z = (-0.9, 0.25)
        belt = 0.97
    elif kind == "compact":
        L, W, r, wb = 4.1, 1.76, 0.32, 2.5
        low = [(-2.05, 1.0), (-2.07, 0.6), (-2.0, 0.3), (2.0, 0.3), (2.06, 0.55), (2.0, 0.8), (1.05, 0.95), (-1.9, 1.02)]
        cab = [(-2.0, 0.98), (-1.75, 1.46), (0.1, 1.5), (1.0, 0.93)]
        roof_z = (-1.7, 0.05)
        belt = 0.98
    elif kind == "coupe":   # the occasional nice car: low, wide, a lip spoiler
        L, W, r, wb = 4.5, 1.94, 0.34, 2.65
        low = [(-2.25, 0.8), (-2.28, 0.55), (-2.2, 0.28), (2.2, 0.28), (2.3, 0.42), (2.24, 0.6), (1.0, 0.78), (-1.1, 0.82)]
        cab = [(-1.35, 0.79), (-0.55, 1.18), (0.1, 1.2), (0.95, 0.76)]
        roof_z = (-0.5, 0.05)
        belt = 0.79
    elif kind == "suv":
        L, W, r, wb = 4.85, 1.95, 0.38, 2.85
        low = [(-2.42, 1.15), (-2.44, 0.7), (-2.36, 0.38), (2.36, 0.38), (2.44, 0.66), (2.38, 1.0), (1.45, 1.12), (-2.3, 1.16)]
        cab = [(-2.38, 1.12), (-2.2, 1.8), (0.75, 1.82), (1.4, 1.1)]
        roof_z = (-2.15, 0.7)
        belt = 1.13
    else:
        raise ValueError(kind)
    zf, zr = wb / 2 + 0.0, -wb / 2
    if kind == "compact":
        zf, zr = 1.28, -1.22
    ybot = 0.3 if kind != "suv" else 0.38
    body_pts = [low[0], low[1]] + lower(low[1][0], low[4][0], ybot, [zr, zf], r + 0.07, r) + [low[4], low[5], low[6], low[7]]
    extrude(body_pts, -W / 2, W / 2, body, kind="Gloss")
    # greenhouse (glass) + body-colored roof and pillars
    extrude(cab, -W / 2 + 0.1, W / 2 - 0.1, GLASS, kind="Gloss")
    rz0, rz1 = roof_z
    top = max(p[1] for p in cab)
    rbox((W - 0.16, 0.06, rz1 - rz0 + 0.1), (0, top + 0.01, (rz0 + rz1) / 2), body, r=0.03, kind="Gloss")
    rbox((W - 0.17, top - belt - 0.05, 0.1), (0, (top + belt) / 2, (rz0 + rz1) / 2 - 0.1), body, kind="Gloss")  # B-pillar
    # bumpers, grille, lights, plates, mirrors, rocker trim
    yb = 0.45 if kind != "suv" else 0.55
    rbox((W + 0.02, 0.2, 0.18), (0, yb, low[4][0] - 0.02), TRIM, r=0.05)
    rbox((W + 0.02, 0.2, 0.18), (0, yb, low[1][0] + 0.02), TRIM, r=0.05)
    rbox((W * 0.45, 0.16, 0.04), (0, yb + 0.2, low[4][0] + 0.03), TRIM)
    lights(W, (yb + belt) / 2 + 0.08, low[4][0] - 0.02, low[1][0] + 0.02)
    plates(yb, low[4][0] + 0.07, low[1][0] - 0.07)
    mirrors(W, belt + 0.12, rz1 + 0.35 if kind != "compact" else rz1 + 0.3)
    for sx in (-1, 1):
        rbox((0.03, 0.08, L - 1.9), (sx * (W / 2 + 0.005), 0.42 if kind != "suv" else 0.5, 0), TRIM)   # rocker
        rbox((0.02, 0.04, 0.2), (sx * (W / 2 + 0.01), belt - 0.12, 0.2), CHROME, kind="Metal")          # door handle
        rbox((0.02, 0.04, 0.2), (sx * (W / 2 + 0.01), belt - 0.12, -0.9), CHROME, kind="Metal")
    if kind == "suv":
        for sx in (-0.6, 0.6):
            rbox((0.05, 0.05, 1.8), (sx, 1.86, -0.6), TRIM)      # roof rails
    if kind == "coupe":
        rbox((W - 0.25, 0.04, 0.32), (0, 0.97, low[0][0] + 0.2), TRIM, r=0.015)
        for sx in (-0.55, 0.55):
            rbox((0.05, 0.14, 0.08), (sx, 0.88, low[0][0] + 0.22), TRIM)
        for sx in (-0.25, 0.25):
            cyl(0.05, 0.12, (sx, 0.36, low[1][0] - 0.02), CHROME, segs=8, kind="Metal", rot=[("x", math.pi / 2)])
    if roof_sign:
        rbox((0.8, 0.26, 0.28), (0, top + 0.17, -0.2), (1.0, 0.96, 0.7), r=0.05, kind="Glow")
        for sx in (-1, 1):   # checker band
            for k in range(8):
                c = TRIM if k % 2 == 0 else body
                rbox((0.02, 0.1, 0.22), (sx * (W / 2 + 0.006), belt - 0.3, -1.2 + k * 0.33), c)
    finish(name)
    LAYOUTS[name] = {"L": L, "W": W, "H": top + 0.05, "color": list(body), "wheel": "Wheel_Car" if kind != "suv" else "Wheel_SUV",
                     "axles": [zf, zr], "track": W / 2 - 0.12, "r": r, "kind": "nice" if kind == "coupe" else "car"}


def pickup(name, body):
    L, W, r = 5.5, 2.0, 0.4
    zf, zr = 1.75, -1.65
    front = [(-0.5, 1.2)] + lower(-0.5, 2.75, 0.42, [zf], r + 0.07, r) + [(2.78, 0.75), (2.72, 1.12), (1.2, 1.2)]
    extrude(front, -W / 2, W / 2, body, kind="Gloss")
    extrude([(-0.5, 1.18), (-0.45, 1.9), (0.6, 1.92), (1.15, 1.18)], -W / 2 + 0.08, W / 2 - 0.08, GLASS, kind="Gloss")
    rbox((W - 0.14, 0.06, 1.1), (0, 1.93, 0.08), body, r=0.03, kind="Gloss")
    # bed: floor + side walls + tailgate
    bed = [(-2.75, 1.15)] + lower(-2.75, -0.55, 0.42, [zr], r + 0.07, r) + [(-0.55, 1.15)]
    for sx in (-1, 1):
        x0 = sx * W / 2
        x1 = sx * (W / 2 - 0.1)
        extrude(bed, min(x0, x1), max(x0, x1), body, kind="Gloss")
    rbox((W - 0.2, 0.08, 2.2), (0, 0.72, -1.65), (0.2, 0.2, 0.22))
    rbox((W, 0.55, 0.08), (0, 0.9, -2.72), body, kind="Gloss")
    rbox((W + 0.04, 0.22, 0.2), (0, 0.55, 2.75), CHROME, r=0.05, kind="Metal")
    rbox((W + 0.04, 0.22, 0.2), (0, 0.55, -2.8), TRIM, r=0.05)
    rbox((W * 0.55, 0.3, 0.05), (0, 0.9, 2.77), CHROME, kind="Metal")
    lights(W, 0.95, 2.76, -2.78, h=0.16, inset=0.2, head_w=0.3)
    plates(0.55, 2.86, -2.92)
    mirrors(W, 1.3, 1.0)
    finish(name)
    LAYOUTS[name] = {"L": L, "W": W, "H": 1.95, "color": list(body), "wheel": "Wheel_SUV", "axles": [zf, zr], "track": W / 2 - 0.13, "r": r,
                     "kind": "car"}


def box_truck(name, cab, box_col, stripe):
    L, W, r = 7.6, 2.4, 0.5
    zf, zr = 2.6, -1.9
    # cab (front): a tall rounded block with a big windshield
    rbox((W - 0.1, 1.5, 1.9), (0, 1.35, 2.75), cab, r=0.12, kind="Gloss")
    extrude([(1.9, 2.1), (1.95, 2.85), (3.35, 2.8), (3.7, 2.1)], -W / 2 + 0.1, W / 2 - 0.1, GLASS, kind="Gloss")
    rbox((W - 0.12, 0.1, 1.45), (0, 2.88, 2.62), cab, r=0.04, kind="Gloss")
    rbox((W, 0.3, 0.22), (0, 0.72, 3.72), TRIM, r=0.05)
    rbox((W * 0.5, 0.45, 0.05), (0, 1.25, 3.71), TRIM)
    lights(W, 1.05, 3.71, -3.82, h=0.18, inset=0.25, head_w=0.32)
    plates(0.7, 3.8, -3.9)
    for sx in (-1, 1):
        rbox((0.08, 0.35, 0.1), (sx * (W / 2 + 0.12), 2.2, 2.2), TRIM)
    # chassis + the box
    rbox((1.1, 0.3, 6.2), (0, 0.75, -0.4), TRIM)
    rbox((W + 0.1, 2.6, 5.2), (0, 2.25, -1.25), box_col, r=0.05)
    for sx in (-1, 1):
        rbox((0.02, 0.5, 4.6), (sx * (W / 2 + 0.06), 2.2, -1.25), stripe)
    rbox((W + 0.02, 0.12, 0.05), (0, 1.0, -3.86), (0.9, 0.5, 0.1), kind="Glow")    # rear marker bar
    rbox((W - 0.3, 2.3, 0.04), (0, 2.3, -3.87), [c * 0.85 for c in box_col])       # roll-up door
    for k in range(6):
        rbox((W - 0.3, 0.03, 0.05), (0, 1.3 + k * 0.38, -3.88), [c * 0.7 for c in box_col])
    for sx in (-1, 1):    # fenders over the wheels
        rbox((0.3, 0.12, 1.1), (sx * (W / 2 - 0.1), 1.05, zf), TRIM)
        rbox((0.3, 0.12, 1.1), (sx * (W / 2 - 0.1), 1.05, zr), TRIM)
    finish(name)
    LAYOUTS[name] = {"L": L, "W": W, "H": 3.6, "color": list(box_col), "wheel": "Wheel_Truck", "axles": [zf, zr], "track": W / 2 - 0.2, "r": r,
                     "kind": "truck"}


def wheel(name, r, w):
    cyl(r, w, (0, 0, 0), (0.06, 0.06, 0.07), segs=16, rot=[("z", math.pi / 2)])
    cyl(r * 0.62, w + 0.02, (0, 0, 0), (0.72, 0.73, 0.76), segs=10, rot=[("z", math.pi / 2)], kind="Metal")
    for k in range(5):   # spokes so you can see it spin
        a = k * 2 * math.pi / 5
        rbox((w + 0.04, r * 0.5, r * 0.12), (0, math.cos(a) * r * 0.3, math.sin(a) * r * 0.3), (0.35, 0.36, 0.38),
             rot=[("x", a)])
    finish(name)


def main():
    reset()
    wheel("Wheel_Car", 0.34, 0.22)
    wheel("Wheel_SUV", 0.4, 0.26)
    wheel("Wheel_Truck", 0.5, 0.32)
    # everyday traffic in everyday colors: greys, silver, white, black, dull blue / red
    for nm, c in (("Sedan_Silver", (0.7, 0.72, 0.75)), ("Sedan_White", (0.9, 0.9, 0.88)), ("Sedan_Black", (0.08, 0.08, 0.09)),
                  ("Sedan_Grey", (0.42, 0.43, 0.45)), ("Sedan_Blue", (0.2, 0.26, 0.38)), ("Sedan_Red", (0.45, 0.1, 0.1))):
        car_body("TCar_" + nm, c, "sedan")
    for nm, c in (("Hatch_Grey", (0.5, 0.51, 0.53)), ("Hatch_Blue", (0.25, 0.32, 0.45)), ("Hatch_White", (0.88, 0.88, 0.86))):
        car_body("TCar_" + nm, c, "compact")
    for nm, c in (("SUV_Black", (0.07, 0.07, 0.08)), ("SUV_White", (0.88, 0.88, 0.86)), ("SUV_Silver", (0.66, 0.67, 0.7)),
                  ("SUV_Grey", (0.3, 0.31, 0.33))):
        car_body("TCar_" + nm, c, "suv")
    for nm, c in (("Pickup_White", (0.9, 0.9, 0.9)), ("Pickup_Grey", (0.38, 0.39, 0.41)), ("Pickup_Red", (0.42, 0.09, 0.08))):
        pickup("TCar_" + nm, c)
    # the occasional nice car (Traffic.nice_models can swap in other kits' cars)
    for nm, c in (("Coupe_Red", (0.78, 0.06, 0.05)), ("Coupe_Black", (0.05, 0.05, 0.06)), ("Coupe_Yellow", (0.95, 0.72, 0.05))):
        car_body("TCar_" + nm, c, "coupe")
    car_body("TCar_Taxi", (1.0, 0.78, 0.05), "sedan", roof_sign=True)
    box_truck("TCar_Truck_White", (0.9, 0.9, 0.9), (0.95, 0.95, 0.95), (0.1, 0.35, 0.75))
    box_truck("TCar_Truck_Red", (0.75, 0.1, 0.08), (0.93, 0.93, 0.9), (0.85, 0.1, 0.08))
    for o in KIT:
        if o.name.startswith("TCar_"):
            assert tris_of(o) <= 2500, (o.name, tris_of(o))
    with open(LAYOUT, "w") as f:
        json.dump(LAYOUTS, f, indent=1, sort_keys=True)
    export(OUT)


if __name__ == "__main__":
    main()
