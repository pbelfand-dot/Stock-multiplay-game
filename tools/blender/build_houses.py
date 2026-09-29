"""BAGHOLDERS neighborhood kit — starter homes, their interiors and yard props (bpy).

Run:  python3 tools/blender/build_houses.py
Out:  assets/props/houses_kit.glb       every mesh below
      assets/props/houses_layout.json   what Godot needs to line things up with the
                                        meshes: colliders, door hinges, lights, the
                                        spawn point by each bed, room rects

Four modest house types after the owner's reference photos:
  ranch     single-story, picture window, white louvered shutters, brick stoop with
            a white rail, shingle side-gable roof, brick chimney
  shotgun   narrow front-gable shotgun with a screened porch, black iron corner
            brackets, red wooden steps + trim, a porch ceiling fan
  bungalow  craftsman bungalow: side-gable roof with wide eaves and rafter tails, a
            small white front-gable porch on square columns
  tin       narrow white shotgun raised on brick piers, rusty corrugated tin roof,
            a window AC unit, a shed porch on two posts

House_<type> is the exterior shell (siding tinted per house at runtime: kind
"Siding"; trim "Trim"; shingles "Roof"/"RoofZ"). Its windows are "Glass" (Godot
swaps in an opaque dark pane on filler houses). Int_<id> is a furnished interior
that fits exactly inside its type's shell (same origin). Door_* leaves are
separate so they can swing (origin = hinge, bottom; leaf along +x).

House-local coordinates (Godot): origin at the middle of the front wall's outer
face at ground level; the body spans x in [-W/2, W/2], z in [-D, 0]; porches and
steps stick out toward +z (the street); floor top at y = FH.
"""
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kit_common import (reset, rbox, box2, cyl, ell, rod, bar, lathe, extrude, extrude_x,  # noqa: E402
                        finish, export)

HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "..", "..", "assets", "props", "houses_kit.glb")
LAYOUT_OUT = os.path.join(HERE, "..", "..", "assets", "props", "houses_layout.json")
random.seed(7)

T = 0.15          # exterior wall thickness
LIN = 0.03        # interior lining on the inside of exterior walls
PT = 0.1          # partition wall thickness
CEIL = 2.5        # ceiling height above the floor

WHITE = (1.0, 1.0, 1.0)            # tinted kinds use white vertex color
TRIMW = (0.95, 0.95, 0.93)
CONC = (0.62, 0.61, 0.58)
CONC_D = (0.5, 0.49, 0.47)
BRICK = (0.56, 0.26, 0.19)
BRICK_D = (0.45, 0.2, 0.15)
DARK = (0.07, 0.07, 0.08)
VOID = (0.05, 0.05, 0.05)
IRON = (0.05, 0.05, 0.06)
RED = (0.66, 0.1, 0.08)
WOOD = (0.5, 0.33, 0.19)
WOOD_D = (0.34, 0.22, 0.12)
WOOD_L = (0.72, 0.56, 0.38)
GREY_DECK = (0.55, 0.55, 0.53)
PAPER = (0.96, 0.96, 0.94)
STEEL = (0.72, 0.73, 0.76)
BLACK = (0.06, 0.06, 0.07)

LAYOUT = {"types": {}, "interiors": {}, "props": {}}


def r3(v):
    return [round(float(c), 3) for c in v]


def coll(lst, a, b, rx=0.0):
    """Axis-aligned collider box between corners a, b (house space)."""
    c = [(a[i] + b[i]) / 2 for i in range(3)]
    s = [abs(b[i] - a[i]) for i in range(3)]
    d = {"c": r3(c), "s": r3(s)}
    if rx:
        d["rx"] = round(rx, 4)
    lst.append(d)


def steps_ramp(lst, x0, x1, z_top, y_top, run):
    """Invisible walkable ramp over a flight of steps that goes down toward +z."""
    L = math.hypot(run, y_top)
    ang = math.atan2(y_top, run)
    th = 0.12
    zc = z_top + run / 2
    yc = y_top / 2
    # sink the box so its top surface is the ramp line
    zc -= math.sin(ang) * th / 2
    yc -= math.cos(ang) * th / 2
    lst.append({"c": r3(((x0 + x1) / 2, yc, zc)), "s": r3((x1 - x0, th, L)), "rx": round(ang, 4)})


# ============================================================================ walls

def wbox(axis, fixed, tdir, ua, ub, ya, yb, d0, d1, col, kind="Paint"):
    """Box aligned to a wall plane. axis 'x': wall runs along x in the plane z=fixed;
    'z': along z in the plane x=fixed. d0..d1 = depth from the plane toward tdir."""
    if axis == "x":
        return box2((ua, ya, fixed + tdir * d0), (ub, yb, fixed + tdir * d1), col, kind)
    return box2((fixed + tdir * d0, ya, ua), (fixed + tdir * d1, yb, ub), col, kind)


def wcoll(lst, axis, fixed, tdir, ua, ub, ya, yb, d0, d1):
    if axis == "x":
        coll(lst, (ua, ya, fixed + tdir * d0), (ub, yb, fixed + tdir * d1))
    else:
        coll(lst, (fixed + tdir * d0, ya, ua), (fixed + tdir * d1, yb, ub))


def pieces(u0, u1, y0, y1, openings):
    """Split a wall rectangle into solid pieces around rectangular openings."""
    out = []
    ops = sorted([o for o in openings if o[1] > u0 + 1e-4 and o[0] < u1 - 1e-4])
    u = u0
    for a, b, va, vb in ops:
        a, b = max(a, u0), min(b, u1)
        if a > u + 1e-4:
            out.append((u, a, y0, y1))
        if va > y0 + 1e-4:
            out.append((a, b, y0, va))
        if vb < y1 - 1e-4:
            out.append((a, b, vb, y1))
        u = b
    if u < u1 - 1e-4:
        out.append((u, u1, y0, y1))
    return out


def wall(axis, fixed, tdir, u0, u1, y0, y1, openings, t, col, kind="Paint", colliders=None, doors_only=None):
    for ua, ub, ya, yb in pieces(u0, u1, y0, y1, openings):
        wbox(axis, fixed, tdir, ua, ub, ya, yb, 0.0, t, col, kind)
    if colliders is not None:
        for ua, ub, ya, yb in pieces(u0, u1, y0, y1, doors_only if doors_only is not None else openings):
            wcoll(colliders, axis, fixed, tdir, ua, ub, ya, yb, 0.0, t)


def window_ext(axis, fixed, tdir, o, shutters=False, grid=True, trim_w=0.1):
    """Exterior window dressing for an opening o=(ua,ub,va,vb) in a wall whose outer
    face is the plane `fixed` and whose inside is toward tdir."""
    ua, ub, va, vb = o
    out = -1
    # glass in the middle of the wall, jambs lining the reveal
    wbox(axis, fixed, tdir, ua, ub, va, vb, T * 0.45, T * 0.55, WHITE, "Glass")
    for u in (ua, ub - 0.04):
        wbox(axis, fixed, tdir, u, u + 0.04, va, vb, 0.0, T, WHITE, "Trim")
    wbox(axis, fixed, tdir, ua, ub, vb - 0.04, vb, 0.0, T, WHITE, "Trim")
    wbox(axis, fixed, tdir, ua, ub, va, va + 0.03, 0.0, T, WHITE, "Trim")
    # casing on the outside face
    wbox(axis, fixed, tdir, ua - trim_w, ua, va - 0.02, vb + trim_w, -0.03, 0.0, WHITE, "Trim")
    wbox(axis, fixed, tdir, ub, ub + trim_w, va - 0.02, vb + trim_w, -0.03, 0.0, WHITE, "Trim")
    wbox(axis, fixed, tdir, ua - trim_w - 0.03, ub + trim_w + 0.03, vb + trim_w, vb + trim_w + 0.05, -0.05, 0.0, WHITE, "Trim")
    wbox(axis, fixed, tdir, ua - trim_w, ub + trim_w, va - 0.07, va - 0.02, -0.07, 0.02, WHITE, "Trim")   # sill
    if grid:   # double-hung: meeting rail + one mullion
        mid = (va + vb) / 2
        wbox(axis, fixed, tdir, ua, ub, mid - 0.025, mid + 0.025, T * 0.3, T * 0.7, WHITE, "Trim")
        if ub - ua > 1.4:
            for k in (1, 2):
                u = ua + (ub - ua) * k / 3
                wbox(axis, fixed, tdir, u - 0.02, u + 0.02, va, vb, T * 0.35, T * 0.65, WHITE, "Trim")
    if shutters:   # white louvered shutters either side
        h = vb - va + 0.1
        for s, u in ((-1, ua - trim_w - 0.02), (1, ub + trim_w + 0.02)):
            w = min(0.45, (ub - ua) * 0.38)
            a, b = (u - w, u) if s < 0 else (u, u + w)
            wbox(axis, fixed, tdir, a, b, va - 0.05, va - 0.05 + h, -0.05, -0.02, WHITE, "Trim")
            n = int(h / 0.1)
            for k in range(n):
                y = va - 0.02 + k * (h - 0.06) / n
                wbox(axis, fixed, tdir, a + 0.04, b - 0.04, y, y + 0.03, -0.075, -0.05, (0.86, 0.86, 0.84), "Trim")


def door_ext(axis, fixed, tdir, o, trim_w=0.12):
    ua, ub, va, vb = o
    for u in (ua, ub - 0.04):
        wbox(axis, fixed, tdir, u, u + 0.04, va, vb, 0.0, T, WHITE, "Trim")
    wbox(axis, fixed, tdir, ua, ub, vb - 0.04, vb, 0.0, T, WHITE, "Trim")
    wbox(axis, fixed, tdir, ua - trim_w, ua, va, vb + trim_w, -0.03, 0.0, WHITE, "Trim")
    wbox(axis, fixed, tdir, ub, ub + trim_w, va, vb + trim_w, -0.03, 0.0, WHITE, "Trim")
    wbox(axis, fixed, tdir, ua - trim_w - 0.04, ub + trim_w + 0.04, vb + trim_w, vb + trim_w + 0.07, -0.06, 0.0, WHITE, "Trim")
    wbox(axis, fixed, tdir, ua - 0.02, ub + 0.02, va - 0.02, va + 0.02, -0.05, T, (0.45, 0.45, 0.45))    # threshold


# ============================================================================ roofs

def gable_roof_x(x0, x1, zf, zb, y_eave, pitch, over_side=0.3, kind="Roof", thick=0.12, fascia=True):
    """Side-gable roof: ridge along x. zf/zb = eave lines (front/back, with overhang)."""
    zr = (zf + zb) / 2
    run = (zf - zb) / 2
    rise = run * math.tan(pitch)
    L = run / math.cos(pitch)
    for s in (1, -1):   # front (s=1) then back slab
        zc = zr + s * run / 2
        yc = y_eave + rise / 2 + thick / 2
        rbox((x1 - x0 + 2 * over_side, thick, L + 0.04), (0.0 if abs(x0 + x1) < 1e-6 else (x0 + x1) / 2, yc, zc),
             WHITE, kind=kind, rot=[("x", s * pitch)])
    rbox((x1 - x0 + 2 * over_side + 0.02, 0.1, 0.3), ((x0 + x1) / 2, y_eave + rise + thick * 0.9, zr), (0.3, 0.3, 0.32))  # ridge cap
    if fascia:
        for s, z in ((1, zf), (-1, zb)):
            rbox((x1 - x0 + 2 * over_side, 0.2, 0.05), ((x0 + x1) / 2, y_eave - 0.02, z + s * 0.01), WHITE, kind="Trim")
    return y_eave + rise


def gable_roof_z(z0, z1, xl, xr, y_eave, pitch, over_end=0.3, kind="RoofZ", thick=0.12):
    """Front-gable roof: ridge along z at x=(xl+xr)/2, eaves at xl/xr (with overhang)."""
    xm = (xl + xr) / 2
    run = (xr - xl) / 2
    rise = run * math.tan(pitch)
    L = run / math.cos(pitch)
    for s in (1, -1):
        xc = xm + s * run / 2
        yc = y_eave + rise / 2 + thick / 2
        rbox((L + 0.04, thick, z1 - z0 + 2 * over_end), (xc, yc, (z0 + z1) / 2), WHITE, kind=kind, rot=[("z", -s * pitch)])
    rbox((0.3, 0.1, z1 - z0 + 2 * over_end + 0.02), (xm, y_eave + rise + thick * 0.9, (z0 + z1) / 2), (0.3, 0.3, 0.32))
    for s, x in ((1, xr), (-1, xl)):
        rbox((0.05, 0.2, z1 - z0 + 2 * over_end), (x + s * 0.01, y_eave - 0.02, (z0 + z1) / 2), WHITE, kind="Trim")
    return y_eave + rise


def gable_end_x(x_plane, tdir, z_front, z_back, y0, y_top, kind="Siding"):
    """Triangular gable wall (side-gable roof) in the plane x=x_plane, thickness T inward."""
    zm = (z_front + z_back) / 2
    prof = [(z_front, y0), (zm, y_top), (z_back, y0)]
    xa, xb = sorted((x_plane, x_plane + tdir * T))
    extrude(prof, xa, xb, WHITE, kind=kind)


def gable_end_z(z_plane, tdir, xl, xr, y0, y_top, kind="Siding", t=T):
    xm = (xl + xr) / 2
    prof = [(xl, y0), (xr, y0), (xm, y_top)]
    za, zb = sorted((z_plane, z_plane + tdir * t))
    extrude_x(prof, za, zb, WHITE, kind=kind)


def corner_boards(W, D, y0, y1, w=0.12):
    for x in (-W / 2, W / 2):
        for z in (0.0, -D):
            sx = 1 if x > 0 else -1
            sz = 1 if z > -D / 2 else -1
            box2((x - sx * (w - 0.03), y0, z + sz * 0.03), (x + sx * 0.03, y1, z - sz * (w - 0.03)), WHITE, "Trim")


def gutter_x(x0, x1, y, z, down=True):
    rbox((x1 - x0, 0.12, 0.12), ((x0 + x1) / 2, y, z), (0.9, 0.9, 0.88), r=0.02, seg=1)
    if down:
        for x in (x0 + 0.1, x1 - 0.1):
            rbox((0.07, y, 0.07), (x, y / 2, z - 0.05 * (1 if z < 0 else -1)), (0.9, 0.9, 0.88))


def foundation(W, D, FH, col=CONC):
    box2((-W / 2 - 0.03, -0.1, -D - 0.03), (W / 2 + 0.03, FH - 0.14, 0.03), col)


def piers(W, D, FH, z_front=0.0, spacing=2.2):
    """Raised on short brick piers: a dark crawlspace void with piers in front of it."""
    box2((-W / 2 + 0.25, -0.1, -D + 0.25), (W / 2 - 0.25, FH - 0.1, z_front - 0.25), VOID)
    zs = []
    z = z_front
    while z > -D - 0.01:
        zs.append(z)
        z -= spacing
    if abs(zs[-1] + D) > 0.4:
        zs.append(-D)
    for zz in zs:
        for x in (-W / 2 + 0.2, W / 2 - 0.2):
            box2((x - 0.2, -0.1, zz - 0.2 if zz < -0.01 else zz - 0.35), (x + 0.2, FH - 0.1, zz + 0.2 if zz < -0.01 else zz + 0.05), BRICK)
    box2((-W / 2 - 0.02, FH - 0.16, -D - 0.02), (W / 2 + 0.02, FH - 0.08, z_front + 0.02), WHITE, "Trim")   # skirt board


# ============================================================================ house spec


class Spec:
    def __init__(self, name, W, D, FH, WH):
        self.name, self.W, self.D, self.FH, self.WH = name, W, D, FH, WH
        self.yp = FH + WH
        self.front, self.back, self.left, self.right = [], [], [], []   # windows (ua, ub, va, vb)
        self.door = None           # front door opening (ua, ub, va, vb) on the front wall
        self.shell_c = []          # colliders (buyable: walls with a door gap, floor, porch...)
        self.filler_c = []         # colliders for a filler house (one block + porch)
        self.porch_c = []          # shared porch/steps colliders
        self.lights = []
        self.extra = {}

    def walls(self, shutters_front=False, grid=True):
        W, D, FH, yp = self.W, self.D, self.FH, self.yp
        y0 = FH - 0.15
        dooro = [self.door] if self.door else []
        # front (z=0, inside -z), back (z=-D, inside +z), left (x=-W/2, inside +x), right
        wall("x", 0.0, -1, -W / 2, W / 2, y0, yp, self.front + dooro, T, WHITE, "Siding", self.shell_c, dooro)
        wall("x", -D, 1, -W / 2, W / 2, y0, yp, self.back, T, WHITE, "Siding", self.shell_c, [])
        wall("z", -W / 2, 1, -D + T, -T, y0, yp, self.left, T, WHITE, "Siding", self.shell_c, [])
        wall("z", W / 2, -1, -D + T, -T, y0, yp, self.right, T, WHITE, "Siding", self.shell_c, [])
        for o in self.front:
            window_ext("x", 0.0, -1, o, shutters=shutters_front, grid=grid)
        for o in self.back:
            window_ext("x", -D, 1, o, grid=grid)
        for o in self.left:
            window_ext("z", -W / 2, 1, (o[0], o[1], o[2], o[3]), grid=grid)
        for o in self.right:
            window_ext("z", W / 2, -1, o, grid=grid)
        if self.door:
            door_ext("x", 0.0, -1, self.door)
        corner_boards(W, D, y0, yp)
        # frieze board under the eaves
        for z, s in ((0.0, 1), (-D, -1)):
            box2((-W / 2 - 0.03, yp - 0.2, z + s * 0.035), (W / 2 + 0.03, yp, z - s * 0.0), WHITE, "Trim")
        # floor slab (walk surface inside) + the filler block
        coll(self.shell_c, (-W / 2, 0.0, -D), (W / 2, FH, 0.0))

    def door_hinge(self):
        ua, ub, va, vb = self.door
        return [round(ua + 0.02, 3), round(va, 3), round(-T + 0.03, 3)]

    def dump(self, roof_top, number_pos, entry, porch_front):
        self.filler_c.append({"c": r3((0, roof_top / 2, -self.D / 2)), "s": r3((self.W, roof_top, self.D))})
        LAYOUT["types"][self.name] = {
            "W": self.W, "D": self.D, "FH": self.FH, "roof_top": round(roof_top, 3),
            "door": {"hinge": self.door_hinge(), "w": round(self.door[1] - self.door[0] - 0.04, 3),
                     "h": round(self.door[3] - self.door[2] - 0.04, 3)},
            "shell_colliders": self.shell_c + self.porch_c,
            "filler_colliders": self.filler_c + self.porch_c,
            "number": r3(number_pos), "entry": r3(entry), "porch_front": round(porch_front, 3),
            "windows": {"front": [r3(o) for o in self.front], "back": [r3(o) for o in self.back],
                        "left": [r3(o) for o in self.left], "right": [r3(o) for o in self.right]},
            **self.extra,
        }


# ============================================================================ the four houses

def house_ranch():
    s = Spec("ranch", 12.4, 8.6, 0.55, 2.7)
    FH = s.FH
    s.front = [(-4.7, -1.7, FH + 0.75, FH + 2.2), (1.9, 3.1, FH + 0.95, FH + 2.2), (4.2, 5.4, FH + 0.95, FH + 2.2)]
    s.door = (-0.1, 0.84, FH, FH + 2.08)
    s.left = [(-7.2, -6.0, FH + 1.1, FH + 2.2), (-2.8, -1.6, FH + 0.95, FH + 2.2)]
    s.right = [(-2.9, -1.7, FH + 0.95, FH + 2.2)]
    s.back = [(-2.2, -1.0, FH + 1.1, FH + 2.2), (2.0, 2.6, FH + 1.55, FH + 2.2)]
    foundation(s.W, s.D, FH)
    s.walls(shutters_front=True)
    pitch = math.radians(22.6)
    top = gable_roof_x(-s.W / 2, s.W / 2, 0.5, -s.D - 0.5, s.yp - 0.5 * math.tan(pitch), pitch, over_side=0.3)
    ridge_wall = s.yp + (s.D / 2) * math.tan(pitch)
    gable_end_x(-s.W / 2, 1, 0.0, -s.D, s.yp, ridge_wall)
    gable_end_x(s.W / 2, -1, 0.0, -s.D, s.yp, ridge_wall)
    for x in (-s.W / 2, s.W / 2):   # gable vents
        rbox((0.06, 0.45, 0.6), (x + (0.02 if x > 0 else -0.02), s.yp + 0.8, -s.D / 2), (0.85, 0.85, 0.83), kind="Trim")
    # soffit under the eaves
    for z0, z1 in ((0.0, 0.5), (-s.D - 0.5, -s.D)):
        box2((-s.W / 2 - 0.3, s.yp - 0.28, z0), (s.W / 2 + 0.3, s.yp - 0.24, z1), (0.92, 0.92, 0.9))
    gutter_x(-s.W / 2 - 0.3, s.W / 2 + 0.3, s.yp - 0.3, 0.55)
    gutter_x(-s.W / 2 - 0.3, s.W / 2 + 0.3, s.yp - 0.3, -s.D - 0.55)
    # brick chimney on the left through the back slope
    box2((-4.45, 2.0, -6.25), (-3.55, top + 0.9, -5.35), BRICK)
    box2((-4.55, top + 0.9, -6.35), (-3.45, top + 1.0, -5.25), CONC_D)
    for k in range(int((top + 0.9 - 2.0) / 0.3)):
        y = 2.0 + k * 0.3
        box2((-4.46, y, -6.26), (-3.54, y + 0.02, -5.34), (0.62, 0.58, 0.54))
    # 3-step brick stoop + white metal railing
    x0, x1 = -0.55, 1.3
    box2((x0, -0.05, 0.0), (x1, FH, 1.2), BRICK)
    box2((x0 - 0.02, FH - 0.04, -0.02), (x1 + 0.02, FH + 0.01, 1.22), CONC)
    rise = FH / 3.0
    for k in range(2):
        zf = 1.2 + (k + 1) * 0.3
        box2((x0, -0.05, 1.2 + k * 0.3), (x1, FH - rise * (k + 1), zf), BRICK)
        box2((x0 - 0.02, FH - rise * (k + 1) - 0.03, 1.2 + k * 0.3), (x1 + 0.02, FH - rise * (k + 1) + 0.01, zf + 0.02), CONC)
    for x in (x0 + 0.05, x1 - 0.05):
        for z, ytop in ((0.1, FH + 0.9), (1.15, FH + 0.9), (1.8, FH * 0.33 + 0.9)):
            rod((x, FH * (0.33 if z > 1.5 else 1.0) if z < 1.5 else FH * 0.33, z), (x, ytop, z), 0.02, WHITE, kind="Metal", segs=6)
        rod((x, FH + 0.9, 0.1), (x, FH + 0.9, 1.15), 0.025, WHITE, kind="Metal", segs=6)
        rod((x, FH + 0.9, 1.15), (x, FH * 0.33 + 0.9, 1.8), 0.025, WHITE, kind="Metal", segs=6)
        for k in range(5):
            z = 0.25 + k * 0.2
            rod((x, FH + 0.05, z), (x, FH + 0.9, z), 0.008, WHITE, kind="Metal", segs=4)
        coll(s.porch_c, (x - 0.04, FH, 0.05), (x + 0.04, FH + 0.95, 1.2))
    coll(s.porch_c, (x0, 0.0, 0.0), (x1, FH, 1.2))
    steps_ramp(s.porch_c, x0 + 0.1, x1 - 0.1, 1.2, FH, 0.75)
    # porch light by the door, electric meter, a hose bib, an AC condenser at the side
    rbox((0.12, 0.22, 0.1), (1.05, FH + 1.95, 0.06), (0.1, 0.1, 0.1))
    rbox((0.08, 0.14, 0.06), (1.05, FH + 1.85, 0.12), (1.0, 0.9, 0.6), kind="Glow")
    box2((6.2, FH + 0.9, -6.2), (6.32, FH + 1.3, -5.9), (0.7, 0.7, 0.72))
    rbox((0.8, 0.75, 0.8), (6.75, 0.38, -4.0), (0.72, 0.73, 0.7), r=0.03, seg=1)
    cyl(0.3, 0.02, (6.75, 0.76, -4.0), (0.2, 0.2, 0.2), segs=12)
    coll(s.porch_c, (6.35, 0.0, -4.4), (7.15, 0.75, -3.6))
    s.extra["bushes"] = [[-5.8, 0.9], [-3.2, 0.9], [2.6, 0.85], [4.8, 0.85], [-6.6, -1.5], [6.6, -1.2]]
    s.dump(top, (1.6, FH + 1.9, 0.03), (0.35, FH + 0.1, 0.8), 2.0)
    finish("House_ranch")


def porch_bracket(x, y, z, sx, axis="x"):
    """Black iron scroll bracket in a porch corner (sx: which way it points along the beam)."""
    for k in range(3):
        a0 = k * 0.12
        rod((x, y - a0, z), (x + (sx * (0.35 - a0) if axis == "x" else 0), y - 0.02 - a0 * 0.2,
                             z + (sx * (0.35 - a0) if axis == "z" else 0)), 0.012, IRON, kind="Metal", segs=4)
    for k in range(6):
        a = math.pi * 0.5 * k / 5
        r = 0.22
        px = x + (sx * (r - r * math.cos(a)) if axis == "x" else 0)
        pz = z + (sx * (r - r * math.cos(a)) if axis == "z" else 0)
        py = y - r * math.sin(a)
        a2 = math.pi * 0.5 * (k + 1) / 5
        px2 = x + (sx * (r - r * math.cos(a2)) if axis == "x" else 0)
        pz2 = z + (sx * (r - r * math.cos(a2)) if axis == "z" else 0)
        rod((px, py, pz), (px2, y - r * math.sin(a2), pz2), 0.014, IRON, kind="Metal", segs=4)
    ell((0.035, 0.035, 0.035), (x + (sx * 0.1 if axis == "x" else 0), y - 0.08, z + (sx * 0.1 if axis == "z" else 0)),
        IRON, segs=6, rings=4, kind="Metal")


def house_shotgun():
    s = Spec("shotgun", 5.6, 15.0, 0.8, 3.0)
    FH, W, D = s.FH, s.W, s.D
    s.door = (0.55, 1.5, FH, FH + 2.2)
    s.front = [(-1.85, -0.9, FH + 0.55, FH + 2.6)]
    s.left = [(-3.0, -2.1, FH + 0.6, FH + 2.5), (-7.0, -6.1, FH + 0.6, FH + 2.5), (-11.0, -10.1, FH + 0.9, FH + 2.5),
              (-14.1, -13.5, FH + 1.5, FH + 2.4)]
    s.right = [(-6.9, -6.0, FH + 0.6, FH + 2.5), (-11.2, -10.3, FH + 0.9, FH + 2.5)]
    s.back = [(-0.6, 0.4, FH + 1.0, FH + 2.3)]
    PD = 2.6
    piers(W, D, FH, z_front=PD)
    s.walls()
    pitch = math.radians(40)
    xl, xr = -W / 2 - 0.3, W / 2 + 0.3
    y_eave = s.yp - 0.3 * math.tan(pitch)
    top = gable_roof_z(-D, PD, xl, xr, y_eave, pitch, over_end=0.3)
    gable_end_z(-D, 1, -W / 2, W / 2, s.yp, s.yp + (W / 2) * math.tan(pitch))
    # the front gable sits over the porch: siding triangle + red rake trim + vent
    gable_end_z(PD, -1, -W / 2, W / 2, s.yp, s.yp + (W / 2) * math.tan(pitch))
    box2((-W / 2 - 0.02, s.yp - 0.25, PD - 0.02), (W / 2 + 0.02, s.yp + 0.02, PD + 0.04), WHITE, "Trim")   # beam
    rbox((0.7, 0.45, 0.05), (0, s.yp + 1.0, PD + 0.02), (0.85, 0.85, 0.83), kind="Trim")
    # porch: floor, haint-blue ceiling, ceiling fan, screened walls with red frames
    box2((-W / 2, FH - 0.12, 0.0), (W / 2, FH, PD), GREY_DECK)
    box2((-W / 2 + 0.05, s.yp - 0.02, 0.0), (W / 2 - 0.05, s.yp + 0.02, PD - 0.05), (0.62, 0.8, 0.82))
    cyl(0.02, 0.35, (0, s.yp - 0.2, PD / 2), BLACK, segs=6, kind="Metal")
    cyl(0.12, 0.14, (0, s.yp - 0.42, PD / 2), BLACK, segs=10, kind="Metal")
    for k in range(4):
        a = k * math.pi / 2 + 0.3
        rbox((0.62, 0.015, 0.13), (math.cos(a) * 0.4, s.yp - 0.44, PD / 2 + math.sin(a) * 0.4), WOOD_D,
             rot=[("y", -a)])
    cyl(0.07, 0.08, (0, s.yp - 0.52, PD / 2), (1.0, 0.95, 0.8), segs=8, kind="Glow")
    # frame: corner posts, top plate, knee rail; screens between
    posts_x = [-W / 2 + 0.06, W / 2 - 0.06]
    for x in posts_x:
        box2((x - 0.06, FH, PD - 0.12), (x + 0.06, s.yp - 0.2, PD), WHITE, "Trim")
        box2((x - 0.06, FH, 0.0), (x + 0.06, s.yp - 0.2, 0.12), WHITE, "Trim")
    sd = (0.55, 1.5)   # screen door opening in the front screen (lined up with the house door)
    ytop = s.yp - 0.25
    # front screen wall: knee rail + screens, door gap
    for a, b in ((-W / 2 + 0.12, sd[0]), (sd[1], W / 2 - 0.12)):
        box2((a, FH, PD - 0.08), (b, FH + 0.45, PD - 0.02), WHITE, "Trim")         # kick board
        box2((a, FH + 0.45, PD - 0.08), (b, FH + 0.52, PD - 0.02), WHITE, "Trim")  # rail
        box2((a, FH + 0.52, PD - 0.06), (b, ytop, PD - 0.045), WHITE, "Screen")
        mid = (a + b) / 2
        box2((mid - 0.03, FH + 0.45, PD - 0.08), (mid + 0.03, ytop, PD - 0.02), WHITE, "Trim")
    for x in sd:
        box2((x - 0.04, FH, PD - 0.09), (x + 0.04, ytop, PD - 0.01), WHITE, "Trim")
    box2((sd[0], FH + 2.2, PD - 0.09), (sd[1], FH + 2.28, PD - 0.01), WHITE, "Trim")
    box2((sd[0], FH + 2.28, PD - 0.06), (sd[1], ytop, PD - 0.045), WHITE, "Screen")
    # side screens
    for x in (-W / 2 + 0.02, W / 2 - 0.02):
        xa, xb = (x, x + 0.06) if x < 0 else (x - 0.06, x)
        box2((xa, FH, 0.12), (xb, FH + 0.45, PD - 0.12), WHITE, "Trim")
        box2((xa, FH + 0.45, 0.12), (xb, FH + 0.52, PD - 0.12), WHITE, "Trim")
        box2((xa + 0.015, FH + 0.52, 0.12), (xb - 0.015, ytop, PD - 0.12), WHITE, "Screen")
        box2((xa, FH + 0.45, PD / 2 - 0.03), (xb, ytop, PD / 2 + 0.03), WHITE, "Trim")
        coll(s.porch_c, (xa, FH, 0.0), (xb, FH + 2.4, PD))
    for a, b in ((-W / 2, sd[0] - 0.04), (sd[1] + 0.04, W / 2)):
        coll(s.porch_c, (a, FH, PD - 0.1), (b, FH + 2.4, PD))
    coll(s.porch_c, (sd[0], FH + 2.2, PD - 0.1), (sd[1], FH + 2.9, PD))
    # black iron corner brackets at the top corners of every screen bay
    for x, sx in ((-W / 2 + 0.12, 1), (W / 2 - 0.12, -1)):
        porch_bracket(x, ytop, PD - 0.05, sx, "x")
        porch_bracket(x, ytop, PD - 0.14, -1, "z")
    # red wooden steps (4) down to the walk
    rise = FH / 4
    for k in range(4):
        z0 = PD + k * 0.28
        y = FH - rise * (k + 1)
        box2((sd[0] - 0.15, max(y - 0.05, -0.05), z0), (sd[1] + 0.15, y + 0.03, z0 + 0.3), RED)
        box2((sd[0] - 0.15, -0.05, z0 + 0.02), (sd[1] + 0.15, y, z0 + 0.06), (0.5, 0.08, 0.06))
    for x in (sd[0] - 0.18, sd[1] + 0.18):
        box2((x - 0.04, -0.05, PD), (x + 0.04, FH + 0.02, PD + 1.12), RED)
        rod((x, FH + 0.9, PD), (x, 0.9, PD + 1.12), 0.03, RED, segs=6)
        rod((x, 0.0, PD + 1.08), (x, 0.95, PD + 1.08), 0.035, RED, segs=6)
    coll(s.porch_c, (-W / 2, 0.0, 0.0), (W / 2, FH, PD))
    steps_ramp(s.porch_c, sd[0] - 0.1, sd[1] + 0.1, PD, FH, 1.12)
    # house number plaque over the porch, a mail slot
    box2((-0.45, s.yp + 0.2, PD + 0.02), (0.45, s.yp + 0.55, PD + 0.06), (0.1, 0.1, 0.1))
    s.extra["screen_door"] = {"hinge": [round(sd[0] + 0.02, 3), round(FH, 3), round(PD - 0.05, 3)],
                              "w": round(sd[1] - sd[0] - 0.04, 3)}
    s.extra["bushes"] = [[-2.2, PD + 0.6], [2.4, PD + 0.6], [-3.3, -2.0]]
    s.dump(top, (0.0, s.yp + 0.37, PD + 0.07), (1.0, FH + 0.1, 1.2), PD + 1.2)
    finish("House_shotgun")


def house_bungalow():
    s = Spec("bungalow", 9.4, 11.5, 0.6, 2.75)
    FH, W, D = s.FH, s.W, s.D
    s.door = (-2.0, -1.08, FH, FH + 2.1)
    s.front = [(1.0, 2.9, FH + 0.8, FH + 2.3), (-4.2, -3.4, FH + 0.9, FH + 2.2)]
    s.left = [(-3.0, -2.0, FH + 0.9, FH + 2.2), (-8.2, -7.2, FH + 1.1, FH + 2.2)]
    s.right = [(-3.0, -2.1, FH + 0.9, FH + 2.2), (-6.9, -6.3, FH + 1.5, FH + 2.2), (-9.6, -8.7, FH + 0.9, FH + 2.2)]
    s.back = [(-3.0, -2.0, FH + 1.1, FH + 2.2)]
    foundation(s.W, s.D, FH, BRICK)
    s.walls()
    pitch = math.radians(26)
    ov = 0.7
    top = gable_roof_x(-W / 2, W / 2, ov, -D - ov, s.yp - ov * math.tan(pitch), pitch, over_side=0.55)
    ridge_wall = s.yp + (D / 2) * math.tan(pitch)
    gable_end_x(-W / 2, 1, 0.0, -D, s.yp, ridge_wall)
    gable_end_x(W / 2, -1, 0.0, -D, s.yp, ridge_wall)
    for x in (-W / 2, W / 2):   # knee braces under the gable overhangs + a louvered vent
        for z in (-2.0, -D + 2.0):
            rod((x + (-0.05 if x < 0 else 0.05), s.yp - 0.7, z), (x + (-0.5 if x < 0 else 0.5), s.yp + 0.15, z), 0.05, WHITE,
                kind="Trim", segs=4)
        rbox((0.06, 0.6, 0.9), (x + (0.02 if x > 0 else -0.02), s.yp + 1.1, -D / 2), (0.85, 0.85, 0.83), kind="Trim")
    for z0, z1 in ((0.0, ov), (-D - ov, -D)):   # soffits + rafter tails
        box2((-W / 2 - 0.55, s.yp - 0.36, z0), (W / 2 + 0.55, s.yp - 0.33, z1), (0.9, 0.9, 0.88))
    for k in range(int((W + 1.0) / 0.6)):
        x = -W / 2 - 0.4 + k * 0.6
        for z, sz in ((0.0, 1), (-D, -1)):
            rbox((0.08, 0.14, ov * 0.95), (x, s.yp - 0.25, z + sz * ov * 0.47), WHITE, kind="Trim", rot=[("x", sz * pitch)])
    # small front-gable porch roof on two square columns
    px0, px1, PD = -3.2, 0.1, 2.3
    pm = (px0 + px1) / 2
    box2((px0, -0.05, 0.0), (px1, FH, PD), CONC)
    ppitch = math.radians(38)
    ye = FH + 2.65
    ptop = gable_roof_z(0.0, PD + 0.1, px0 - 0.25, px1 + 0.25, ye, ppitch, over_end=0.15, kind="RoofZ", thick=0.1)
    gable_end_z(PD + 0.1, -1, px0, px1, ye + 0.02, ye + (px1 - px0) / 2 * math.tan(ppitch) - 0.05, kind="Trim", t=0.08)
    box2((px0 - 0.05, ye - 0.3, PD - 0.1), (px1 + 0.05, ye + 0.05, PD + 0.14), WHITE, "Trim")          # beam
    box2((px0 + 0.05, ye - 0.02, 0.0), (px1 - 0.05, ye + 0.02, PD), (0.93, 0.93, 0.9))                # porch ceiling
    rbox((0.6, 0.3, 0.04), (pm, ye + 0.55, PD + 0.16), (0.8, 0.8, 0.78), kind="Trim")                  # vent
    for x in (px0 + 0.2, px1 - 0.2):
        box2((x - 0.22, FH, PD - 0.45), (x + 0.22, FH + 0.9, PD - 0.01), BRICK)                        # brick base
        box2((x - 0.25, FH + 0.9, PD - 0.48), (x + 0.25, FH + 0.97, PD + 0.02), CONC)
        rbox((0.26, ye - 0.3 - FH - 0.97, 0.26), (x, (ye - 0.3 + FH + 0.97) / 2, PD - 0.23), WHITE, kind="Trim")
        coll(s.porch_c, (x - 0.25, FH, PD - 0.48), (x + 0.25, ye - 0.3, PD))
    coll(s.porch_c, (px0, 0.0, 0.0), (px1, FH, PD))
    for k in range(3):
        z0 = PD + k * 0.3
        y = FH - FH / 3 * (k + 1)
        box2((pm - 0.8, -0.05, z0), (pm + 0.8, y, z0 + 0.3), CONC)
    steps_ramp(s.porch_c, pm - 0.7, pm + 0.7, PD, FH, 0.9)
    rbox((0.1, 0.25, 0.1), (-0.8, FH + 1.9, 0.06), (0.15, 0.12, 0.1))
    rbox((0.07, 0.15, 0.06), (-0.8, FH + 1.8, 0.1), (1.0, 0.9, 0.6), kind="Glow")
    s.extra["bushes"] = [[2.0, 0.8], [3.6, 0.8], [-4.2, 0.8], [4.9, -3.0]]
    s.dump(max(top, ptop), (-0.45, FH + 1.75, 0.035), (pm, FH + 0.1, 1.0), PD + 0.9)
    finish("House_bungalow")


def tin_roof(z0, z1, xl, xr, y_eave, pitch, over_end=0.35):
    """Front-gable corrugated tin: rusty red sheets with raised ribs (vertex-color rust)."""
    xm = (xl + xr) / 2
    run = (xr - xl) / 2
    L = run / math.cos(pitch)
    zl, zr = z0 - over_end, z1 + over_end
    rise = run * math.tan(pitch)
    for s in (1, -1):
        xc = xm + s * run / 2
        yc = y_eave + rise / 2
        rbox((L + 0.04, 0.05, zr - zl), (xc, yc, (zl + zr) / 2), (0.52, 0.2, 0.12), rot=[("z", -s * pitch)])
        n = int((zr - zl) / 0.33)
        for k in range(n):
            z = zl + 0.15 + k * 0.33
            rust = random.uniform(0, 1)
            c = (0.58 - 0.18 * rust, 0.24 - 0.08 * rust, 0.13 - 0.03 * rust) if rust < 0.8 else (0.36, 0.3, 0.26)
            rbox((L + 0.04, 0.035, 0.05), (xc + 0.0, yc + 0.035, z), c, rot=[("z", -s * pitch)])
    rbox((0.3, 0.12, zr - zl), (xm, y_eave + rise + 0.05, (zl + zr) / 2), (0.4, 0.22, 0.16))
    return y_eave + rise


def house_tin():
    s = Spec("tin", 4.8, 12.5, 0.9, 2.9)
    FH, W, D = s.FH, s.W, s.D
    s.door = (0.55, 1.45, FH, FH + 2.1)
    s.front = [(-1.75, -0.85, FH + 0.6, FH + 2.45)]
    s.left = [(-3.0, -2.2, FH + 0.7, FH + 2.4), (-7.0, -6.2, FH + 0.7, FH + 2.4), (-11.0, -10.3, FH + 1.2, FH + 2.3)]
    s.right = [(-5.0, -4.2, FH + 0.7, FH + 2.4), (-10.5, -9.7, FH + 0.9, FH + 2.4)]
    s.back = [(-0.5, 0.3, FH + 1.0, FH + 2.3)]
    PD = 1.8
    piers(W, D, FH, z_front=PD)
    s.walls()
    pitch = math.radians(35)
    xl, xr = -W / 2 - 0.3, W / 2 + 0.3
    top = tin_roof(-D, PD, xl, xr, s.yp - 0.3 * math.tan(pitch), pitch)
    gable_end_z(-D, 1, -W / 2, W / 2, s.yp, s.yp + (W / 2) * math.tan(pitch))
    gable_end_z(PD, -1, -W / 2, W / 2, s.yp, s.yp + (W / 2) * math.tan(pitch))
    box2((-W / 2 - 0.05, s.yp - 0.22, PD - 0.08), (W / 2 + 0.05, s.yp + 0.02, PD + 0.05), WHITE, "Trim")
    for x in (-W / 2 - 0.3, W / 2 + 0.3):   # white fascia along the eaves
        box2((x - 0.03, s.yp - 0.38, -D - 0.35), (x + 0.03, s.yp - 0.2, PD + 0.35), WHITE, "Trim")
    rbox((0.5, 0.35, 0.04), (0, s.yp + 0.9, PD + 0.02), (0.8, 0.8, 0.78), kind="Trim")
    # porch: plank floor, two posts + a middle one, simple rail, steps on the right
    box2((-W / 2, FH - 0.1, 0.0), (W / 2, FH, PD), (0.6, 0.58, 0.54))
    for k in range(int(W / 0.14)):
        x = -W / 2 + 0.07 + k * 0.14
        box2((x - 0.004, FH, 0.0), (x + 0.004, FH + 0.004, PD), (0.45, 0.43, 0.4))
    box2((-W / 2 + 0.05, s.yp - 0.02, 0.0), (W / 2 - 0.05, s.yp + 0.01, PD - 0.05), (0.88, 0.88, 0.86))
    for x in (-W / 2 + 0.1, -0.2, W / 2 - 0.1):
        box2((x - 0.07, FH, PD - 0.17), (x + 0.07, s.yp - 0.2, PD - 0.03), WHITE, "Trim")
        coll(s.porch_c, (x - 0.08, FH, PD - 0.18), (x + 0.08, s.yp - 0.2, PD - 0.02))
    sx0, sx1 = 0.35, 1.65
    for a, b in ((-W / 2 + 0.17, -0.27), (-0.13, sx0), (sx1, W / 2 - 0.17)):
        box2((a, FH + 0.85, PD - 0.13), (b, FH + 0.92, PD - 0.07), WHITE, "Trim")
        for k in range(int((b - a) / 0.14)):
            x = a + 0.07 + k * 0.14
            box2((x - 0.02, FH, PD - 0.12), (x + 0.02, FH + 0.85, PD - 0.08), WHITE, "Trim")
        coll(s.porch_c, (a, FH, PD - 0.14), (b, FH + 0.92, PD - 0.06))
    for x in (-W / 2 + 0.03, W / 2 - 0.03):    # side rails
        box2((x - 0.03, FH + 0.85, 0.05), (x + 0.03, FH + 0.92, PD - 0.17), WHITE, "Trim")
        coll(s.porch_c, (x - 0.04, FH, 0.0), (x + 0.04, FH + 0.92, PD))
    rise = FH / 4
    for k in range(4):
        z0 = PD + k * 0.28
        y = FH - rise * (k + 1)
        box2((sx0, -0.05, z0), (sx1, y + 0.03, z0 + 0.3), (0.62, 0.6, 0.56))
    for x in (sx0 - 0.03, sx1 + 0.03):
        box2((x - 0.03, -0.05, PD), (x + 0.03, FH, PD + 1.12), (0.5, 0.48, 0.45))
    coll(s.porch_c, (-W / 2, 0.0, 0.0), (W / 2, FH, PD))
    steps_ramp(s.porch_c, sx0 + 0.05, sx1 - 0.05, PD, FH, 1.12)
    # window AC unit hanging out of the front window, drip stain under it
    ax = (-1.75 - 0.85) / 2
    rbox((0.66, 0.42, 0.55), (ax, FH + 1.3, 0.2), (0.86, 0.86, 0.82), r=0.02, seg=1)
    for k in range(6):
        box2((ax - 0.28, FH + 1.14 + k * 0.05, 0.47), (ax + 0.28, FH + 1.16 + k * 0.05, 0.48), (0.55, 0.55, 0.53))
    box2((ax - 0.34, FH + 1.08, -0.02), (ax + 0.34, FH + 1.1, 0.25), (0.8, 0.8, 0.78))
    box2((ax - 0.05, FH + 0.2, 0.003), (ax + 0.07, FH + 1.08, 0.006), (0.55, 0.5, 0.42))
    coll(s.porch_c, (ax - 0.34, FH + 1.08, -0.05), (ax + 0.34, FH + 1.52, 0.48))
    rbox((0.1, 0.2, 0.08), (1.75, FH + 2.0, 0.05), (0.1, 0.1, 0.1))
    s.extra["bushes"] = [[-1.8, PD + 0.5]]
    s.dump(top, (1.0, FH + 2.4, 0.03), (1.0, FH + 0.1, 0.8), PD + 1.2)
    finish("House_tin")


# ============================================================================ doors

def door_leaf(name, col, style="panel", w=0.9, h=2.04):
    """Origin = hinge side, bottom; leaf spans x 0..w; front (outside) = +z."""
    box2((0.0, 0.0, -0.025), (w, h, 0.025), col)
    if style == "panel":
        for y0, y1 in ((0.2, 0.85), (1.05, 1.85)):
            for x0, x1 in ((0.12, w / 2 - 0.05), (w / 2 + 0.05, w - 0.12)):
                box2((x0, y0, 0.025), (x1, y1, 0.04), [c * 0.92 for c in col])
                box2((x0, y0, -0.04), (x1, y1, -0.025), [c * 0.92 for c in col])
    elif style == "glass":
        box2((0.15, 1.2, -0.03), (w - 0.15, 1.85, 0.03), WHITE, "Glass")
        box2((0.15, 1.2, 0.025), (w - 0.15, 1.24, 0.04), [c * 0.9 for c in col])
        box2((0.15, 0.25, 0.025), (w - 0.15, 1.0, 0.04), [c * 0.92 for c in col])
    elif style == "screen":
        pass
    for z in (0.05, -0.05):
        cyl(0.03, 0.05, (w - 0.1, 0.98, z), (0.85, 0.72, 0.3), segs=8, kind="Metal", rot=[("x", math.pi / 2)])
    finish(name)


def screen_door():
    w, h = 0.87, 2.16
    for x in (0.0, w - 0.07):
        box2((x, 0.0, -0.02), (x + 0.07, h, 0.02), RED)
    for y in (0.0, 0.9, h - 0.08):
        box2((0.0, y, -0.02), (w, y + 0.08, 0.02), RED)
    box2((0.07, 0.08, -0.004), (w - 0.07, h - 0.08, 0.004), WHITE, "Screen")
    cyl(0.025, 0.05, (w - 0.1, 1.0, 0.04), (0.8, 0.7, 0.3), segs=8, kind="Metal", rot=[("x", math.pi / 2)])
    finish("Door_Screen")


# ============================================================================ interiors

class Pl:
    """Furniture placer: local frame (front = +z) at (x, y, z), yaw a multiple of 90 degrees."""

    def __init__(self, x, y, z, yaw=0.0, colliders=None):
        self.x, self.y, self.z, self.yaw = x, y, z, yaw
        self.c, self.s = math.cos(yaw), math.sin(yaw)
        self.colliders = colliders

    def P(self, p):
        lx, ly, lz = p
        return (self.x + lx * self.c + lz * self.s, self.y + ly, self.z - lx * self.s + lz * self.c)

    def box(self, size, p, col, kind="Paint", r=0.0):
        rbox(size, self.P(p), col, r=r, seg=1, kind=kind, rot=[("y", self.yaw)])

    def cyl(self, r, h, p, col, segs=12, kind="Paint", r2=None, rot=None):
        cyl(r, h, self.P(p), col, segs=segs, kind=kind, r2=r2, rot=(rot or []) + [("y", self.yaw)])

    def ell(self, radii, p, col, segs=10, rings=6, kind="Paint"):
        ell(radii, self.P(p), col, segs=segs, rings=rings, kind=kind, rot=[("y", self.yaw)])

    def solid(self, size, p):
        if self.colliders is None:
            return
        sx, sy, sz = size
        if abs(self.s) > 0.5:
            sx, sz = sz, sx
        c = self.P(p)
        self.colliders.append({"c": r3(c), "s": r3((sx, sy, sz))})


def couch(pl, col, w=2.1, pillows=None):
    d = [c * 0.85 for c in col]
    pl.box((w, 0.24, 0.88), (0, 0.2, 0), d)
    for k in range(3):
        x = -w / 2 + 0.22 + (w - 0.44) * (k + 0.5) / 3
        pl.box(((w - 0.44) / 3 - 0.02, 0.15, 0.64), (x, 0.39, 0.1), col, r=0.04)
        pl.box(((w - 0.44) / 3 - 0.03, 0.42, 0.16), (x, 0.67, -0.24), col, r=0.05)
    pl.box((w, 0.62, 0.2), (0, 0.51, -0.35), d)
    for sx in (-1, 1):
        pl.box((0.22, 0.62, 0.88), (sx * (w / 2 - 0.11), 0.39, 0), col, r=0.05)
        pl.box((0.05, 0.08, 0.05), (sx * (w / 2 - 0.08), 0.04, 0.38), WOOD_D)
    if pillows:
        for sx in (-1, 1):
            pl.box((0.4, 0.38, 0.12), (sx * (w / 2 - 0.45), 0.66, -0.12), pillows, r=0.06)
    pl.solid((w, 0.8, 0.88), (0, 0.4, 0))


def armchair(pl, col):
    d = [c * 0.85 for c in col]
    pl.box((0.85, 0.26, 0.82), (0, 0.2, 0), d)
    pl.box((0.5, 0.14, 0.6), (0, 0.4, 0.08), col, r=0.04)
    pl.box((0.85, 0.6, 0.2), (0, 0.55, -0.32), col, r=0.05)
    for sx in (-1, 1):
        pl.box((0.18, 0.55, 0.82), (sx * 0.34, 0.37, 0), col, r=0.05)
    pl.solid((0.85, 0.8, 0.82), (0, 0.4, 0))


def coffee_table(pl, col, w=1.1, d=0.6):
    pl.box((w, 0.05, d), (0, 0.42, 0), col, r=0.01)
    pl.box((w - 0.1, 0.03, d - 0.1), (0, 0.14, 0), [c * 0.85 for c in col])
    for sx in (-1, 1):
        for sz in (-1, 1):
            pl.box((0.05, 0.4, 0.05), (sx * (w / 2 - 0.06), 0.2, sz * (d / 2 - 0.06)), [c * 0.8 for c in col])
    pl.box((0.22, 0.03, 0.28), (0.2, 0.46, 0.05), (0.8, 0.2, 0.2))       # magazines
    pl.box((0.2, 0.02, 0.26), (0.22, 0.485, 0.06), (0.2, 0.4, 0.75))
    pl.cyl(0.04, 0.1, (-0.25, 0.5, -0.05), (0.95, 0.95, 0.93), segs=8)   # mug
    pl.box((0.05, 0.02, 0.16), (-0.05, 0.46, 0.1), BLACK)               # remote
    pl.solid((w, 0.45, d), (0, 0.225, 0))


def tv_unit(pl, wood, big=False):
    w = 1.8 if big else 1.5
    pl.box((w, 0.5, 0.45), (0, 0.25, 0), wood, r=0.01)
    for k in range(3):
        pl.box((w / 3 - 0.06, 0.34, 0.01), (-w / 3 + k * w / 3, 0.25, 0.228), [c * 0.8 for c in wood])
    tw, th = (1.45, 0.85) if big else (1.15, 0.68)
    pl.box((tw, th, 0.06), (0, 0.55 + th / 2 + 0.1, -0.05), BLACK, kind="Gloss")
    pl.box((tw - 0.06, th - 0.06, 0.01), (0, 0.55 + th / 2 + 0.1, -0.017), (0.1, 0.16, 0.24), kind="Glow")
    pl.box((0.3, 0.04, 0.2), (0, 0.52, -0.05), BLACK)
    pl.box((0.08, 0.1, 0.05), (0, 0.58, -0.05), BLACK)
    pl.box((0.35, 0.06, 0.25), (0.45, 0.53, 0.02), (0.12, 0.12, 0.13))     # game console
    pl.solid((w, 0.5, 0.45), (0, 0.25, 0))


def rug(pl, w, d, col, border=None):
    pl.box((w, 0.012, d), (0, 0.006, 0), col)
    if border:
        pl.box((w - 0.24, 0.014, d - 0.24), (0, 0.007, 0), border)
        pl.box((w - 0.36, 0.016, d - 0.36), (0, 0.008, 0), col)


def floor_lamp(pl):
    pl.cyl(0.14, 0.03, (0, 0.015, 0), BLACK, segs=10, kind="Metal")
    pl.cyl(0.015, 1.5, (0, 0.77, 0), BLACK, segs=6, kind="Metal")
    pl.cyl(0.2, 0.28, (0, 1.55, 0), (0.95, 0.9, 0.78), segs=12, r2=0.13)
    pl.cyl(0.12, 0.02, (0, 1.42, 0), (1.0, 0.95, 0.8), segs=10, kind="Glow")


def plant(pl, pot=(0.75, 0.42, 0.3), tall=1.0):
    pl.cyl(0.17, 0.32, (0, 0.16, 0), pot, segs=10, r2=0.2)
    pl.cyl(0.18, 0.02, (0, 0.33, 0), (0.25, 0.18, 0.12), segs=10)
    for k in range(6):
        a = k * 1.1
        pl.ell((0.16, 0.22 * tall, 0.1), (math.cos(a) * 0.12, 0.45 + 0.35 * tall * (k % 3) / 2, math.sin(a) * 0.12),
               (0.16 + 0.04 * (k % 2), 0.45, 0.18), segs=6, rings=4)
    pl.solid((0.38, 0.7, 0.38), (0, 0.35, 0))


def bookshelf(pl, wood, w=0.9, h=1.8):
    pl.box((w, h, 0.32), (0, h / 2, 0), wood)
    pl.box((w - 0.06, h - 0.06, 0.02), (0, h / 2, 0.15), [c * 0.6 for c in wood])
    cols = [(0.7, 0.15, 0.12), (0.15, 0.3, 0.6), (0.85, 0.75, 0.4), (0.2, 0.45, 0.25), (0.9, 0.9, 0.85), (0.4, 0.2, 0.4)]
    n = 4
    for k in range(n):
        y = 0.05 + k * (h - 0.1) / n
        pl.box((w - 0.06, 0.025, 0.28), (0, y + 0.02, 0.02), wood)
        x = -w / 2 + 0.06
        i = k
        while x < w / 2 - 0.12:
            bw = 0.04 + (i * 7 % 5) * 0.012
            bh = 0.22 + (i * 3 % 4) * 0.03
            pl.box((bw, bh, 0.2), (x + bw / 2, y + 0.035 + bh / 2, 0.03), cols[i % len(cols)])
            x += bw + 0.005
            i += 1
            if i % 7 == 0:
                x += 0.15
    pl.solid((w, h, 0.32), (0, h / 2, 0))


def wall_art(pl, w, h, col, frame=BLACK):
    """Framed picture flat on a wall: pl sits on the wall surface, facing into the room."""
    pl.box((w + 0.06, h + 0.06, 0.03), (0, 0, 0.015), frame)
    pl.box((w - 0.06, h - 0.06, 0.01), (0, 0, 0.033), (0.95, 0.94, 0.9))
    pl.box((w - 0.2, h - 0.2, 0.01), (0, 0, 0.038), col)
    pl.box((w * 0.35, h * 0.3, 0.01), (-w * 0.12, -h * 0.1, 0.043), [min(1.0, c * 1.4) for c in col])


def kitchen_run(pl, length, cab, top, uppers=True, sink_at=None, no_upper=None):
    """Base cabinets with a countertop along a wall (pl on the wall, facing the room)."""
    x0 = -length / 2
    pl.box((length, 0.1, 0.55), (0, 0.05, 0.3), (0.15, 0.13, 0.12))
    pl.box((length, 0.78, 0.58), (0, 0.49, 0.3), cab)
    pl.box((length + 0.02, 0.04, 0.63), (0, 0.9, 0.315), top)
    pl.box((length, 0.2, 0.02), (0, 1.02, 0.01), [min(1.0, c * 1.05) for c in top])        # backsplash
    n = max(1, int(length / 0.6))
    for k in range(n):
        x = x0 + (k + 0.5) * length / n
        pl.box((length / n - 0.03, 0.55, 0.01), (x, 0.42, 0.595), [c * 0.93 for c in cab])
        pl.box((length / n - 0.03, 0.14, 0.01), (x, 0.8, 0.595), [c * 0.93 for c in cab])
        pl.box((0.12, 0.02, 0.02), (x, 0.8, 0.61), STEEL, kind="Metal")
        if uppers and not (no_upper and no_upper[0] - 0.3 < x < no_upper[1] + 0.3):
            pl.box((length / n - 0.02, 0.7, 0.34), (x, 1.9, 0.17), cab)
            pl.box((length / n - 0.05, 0.64, 0.01), (x, 1.9, 0.345), [c * 0.93 for c in cab])
            pl.box((0.02, 0.1, 0.02), (x + length / n / 2 - 0.08, 1.65, 0.36), STEEL, kind="Metal")
    if sink_at is not None:
        pl.box((0.7, 0.03, 0.42), (sink_at, 0.915, 0.33), STEEL, kind="Metal")
        pl.box((0.6, 0.02, 0.34), (sink_at, 0.925, 0.33), (0.45, 0.46, 0.48), kind="Metal")
        pl.cyl(0.02, 0.3, (sink_at, 1.05, 0.08), STEEL, segs=6, kind="Metal")
        pl.box((0.03, 0.03, 0.2), (sink_at, 1.2, 0.17), STEEL, kind="Metal")
    pl.solid((length, 0.95, 0.62), (0, 0.47, 0.31))


def fridge(pl, col=(0.93, 0.93, 0.92), steel=False):
    c = STEEL if steel else col
    k = "Metal" if steel else "Gloss"
    pl.box((0.82, 1.82, 0.72), (0, 0.91, 0.36), c, kind=k, r=0.02)
    pl.box((0.8, 0.01, 0.01), (0, 1.25, 0.725), (0.3, 0.3, 0.3))
    pl.box((0.03, 0.4, 0.04), (0.33, 1.5, 0.74), (0.3, 0.3, 0.32), kind="Metal")
    pl.box((0.03, 0.5, 0.04), (0.33, 0.8, 0.74), (0.3, 0.3, 0.32), kind="Metal")
    for i, cc in enumerate(((0.9, 0.3, 0.2), (0.3, 0.6, 0.9), (1.0, 0.85, 0.2))):   # magnets + a kid drawing
        pl.box((0.05, 0.05, 0.01), (-0.2 + i * 0.12, 1.55, 0.725), cc)
    pl.box((0.22, 0.28, 0.005), (-0.1, 1.35, 0.724), PAPER)
    pl.solid((0.82, 1.82, 0.72), (0, 0.91, 0.36))


def stove(pl, col=(0.94, 0.94, 0.92)):
    pl.box((0.76, 0.9, 0.64), (0, 0.45, 0.32), col, kind="Gloss")
    pl.box((0.76, 0.02, 0.62), (0, 0.91, 0.32), BLACK, kind="Gloss")
    for sx in (-0.18, 0.18):
        for sz in (0.18, 0.44):
            pl.cyl(0.1, 0.012, (sx, 0.925, sz), (0.2, 0.2, 0.2), segs=10, kind="Metal")
    pl.box((0.6, 0.35, 0.01), (0, 0.45, 0.645), (0.1, 0.1, 0.12), kind="Gloss")
    pl.box((0.5, 0.03, 0.04), (0, 0.7, 0.66), STEEL, kind="Metal")
    pl.box((0.76, 0.18, 0.06), (0, 1.0, 0.03), col, kind="Gloss")
    for k in range(4):
        pl.cyl(0.02, 0.03, (-0.25 + k * 0.166, 1.0, 0.07), BLACK, segs=6, rot=[("x", math.pi / 2)])
    pl.box((0.78, 0.18, 0.5), (0, 1.72, 0.25), STEEL, kind="Metal")    # range hood
    pl.solid((0.76, 0.95, 0.64), (0, 0.47, 0.32))


def dining(pl, wood, chair_col, w=1.3, d=0.85, chairs=4):
    pl.box((w, 0.05, d), (0, 0.75, 0), wood, r=0.01)
    for sx in (-1, 1):
        for sz in (-1, 1):
            pl.box((0.06, 0.73, 0.06), (sx * (w / 2 - 0.08), 0.365, sz * (d / 2 - 0.08)), [c * 0.85 for c in wood])
    spots = [(-w / 4, d / 2 + 0.25, math.pi), (w / 4, d / 2 + 0.25, math.pi), (-w / 4, -d / 2 - 0.25, 0.0),
             (w / 4, -d / 2 - 0.25, 0.0)][:chairs]
    for x, z, yaw in spots:
        c = Pl(*pl.P((x, 0, z)), yaw=pl.yaw + yaw)
        c.box((0.44, 0.04, 0.42), (0, 0.46, 0), chair_col)
        for sx in (-1, 1):
            for sz in (-1, 1):
                c.box((0.035, 0.46, 0.035), (sx * 0.19, 0.23, sz * 0.18), [cc * 0.85 for cc in chair_col])
        c.box((0.42, 0.42, 0.035), (0, 0.7, -0.19), chair_col)
    pl.cyl(0.1, 0.12, (0, 0.84, 0), (0.95, 0.95, 0.93), segs=10)          # fruit bowl
    for k in range(3):
        pl.ell((0.04, 0.04, 0.04), (-0.03 + k * 0.035, 0.92, 0.01 * k), ((0.9, 0.2, 0.1), (1.0, 0.7, 0.1), (0.4, 0.7, 0.2))[k],
               segs=6, rings=4)
    pl.solid((w, 0.78, d), (0, 0.39, 0))


def bed(pl, frame, blanket, sheet=(0.95, 0.95, 0.93), w=1.6, L=2.05):
    pl.box((w + 0.1, 0.28, L + 0.05), (0, 0.2, 0), frame)
    pl.box((w, 0.24, L - 0.05), (0, 0.46, 0.0), sheet, r=0.04)
    pl.box((w + 0.06, 0.1, L * 0.66), (0, 0.6, L * 0.17 + 0.02), blanket, r=0.03)
    pl.box((w + 0.07, 0.35, 0.05), (0, 0.4, L * 0.17 + 0.02 + L * 0.33), blanket)
    for sx in (-1, 1):
        pl.box((w + 0.07 if sx == 0 else 0.04, 0.35, L * 0.66), (sx * (w / 2 + 0.035), 0.42, L * 0.17 + 0.02), blanket)
        pl.box((w / 2 - 0.14, 0.13, 0.36), (sx * (w / 4), 0.64, -L / 2 + 0.28), (0.97, 0.97, 0.95), r=0.05)
    pl.box((w + 0.16, 1.05, 0.07), (0, 0.55, -L / 2 - 0.02), frame, r=0.02)
    pl.box((w + 0.06, 0.04, 0.3), (0, 0.66, L / 2 - 0.2), [c * 0.8 for c in blanket])   # folded throw
    pl.solid((w + 0.16, 0.65, L + 0.08), (0, 0.325, 0))


def nightstand(pl, wood, clock=False, lamp=True):
    pl.box((0.5, 0.56, 0.42), (0, 0.28, 0), wood)
    pl.box((0.44, 0.18, 0.01), (0, 0.4, 0.21), [c * 0.85 for c in wood])
    pl.box((0.08, 0.02, 0.02), (0, 0.4, 0.22), STEEL, kind="Metal")
    if clock:   # the alarm clock: black, red digits (you're late)
        pl.box((0.2, 0.1, 0.09), (0.1, 0.61, 0.05), BLACK, r=0.01)
        pl.box((0.15, 0.05, 0.005), (0.1, 0.615, 0.097), (1.0, 0.08, 0.05), kind="Glow")
    if lamp:
        pl.cyl(0.07, 0.03, (-0.1, 0.575, -0.02), (0.85, 0.8, 0.7), segs=10)
        pl.cyl(0.02, 0.28, (-0.1, 0.72, -0.02), (0.85, 0.8, 0.7), segs=6)
        pl.cyl(0.14, 0.2, (-0.1, 0.92, -0.02), (0.97, 0.93, 0.82), segs=12, r2=0.1)
    pl.solid((0.5, 0.6, 0.42), (0, 0.3, 0))


def dresser(pl, wood, mirror=True):
    pl.box((1.2, 0.85, 0.5), (0, 0.43, 0), wood)
    for k in range(3):
        for sx in (-0.29, 0.29):
            pl.box((0.54, 0.22, 0.01), (sx, 0.18 + k * 0.25, 0.255), [c * 0.88 for c in wood])
            pl.box((0.1, 0.02, 0.02), (sx, 0.18 + k * 0.25, 0.265), STEEL, kind="Metal")
    if mirror:
        pl.box((0.8, 0.9, 0.04), (0, 1.4, -0.22), wood)
        pl.box((0.7, 0.8, 0.01), (0, 1.4, -0.195), (0.75, 0.82, 0.88), kind="Gloss")
    pl.box((0.25, 0.08, 0.15), (0.35, 0.89, 0.05), (0.9, 0.7, 0.7))     # jewelry box
    pl.solid((1.2, 0.9, 0.5), (0, 0.45, 0))


def closet_doors(pl, w, col):
    """Bi-fold closet doors flat on a wall."""
    pl.box((w, 2.05, 0.04), (0, 1.03, 0.02), col)
    n = 4
    for k in range(n):
        x = -w / 2 + (k + 0.5) * w / n
        pl.box((w / n - 0.03, 1.95, 0.01), (x, 1.03, 0.045), [c * 0.93 for c in col])
        for j in range(8):
            pl.box((w / n - 0.1, 0.02, 0.01), (x, 1.15 + j * 0.1, 0.052), [c * 0.85 for c in col])
    pl.box((0.02, 0.1, 0.03), (0.03, 1.0, 0.06), STEEL, kind="Metal")


def toilet(pl):
    pl.cyl(0.19, 0.38, (0, 0.19, 0.12), (0.97, 0.97, 0.96), segs=12, r2=0.16, kind="Gloss")
    pl.box((0.4, 0.05, 0.48), (0, 0.4, 0.14), (0.97, 0.97, 0.96), kind="Gloss", r=0.02)
    pl.box((0.46, 0.4, 0.2), (0, 0.6, -0.14), (0.97, 0.97, 0.96), kind="Gloss", r=0.02)
    pl.box((0.48, 0.04, 0.22), (0, 0.82, -0.14), (0.97, 0.97, 0.96), kind="Gloss")
    pl.box((0.06, 0.02, 0.03), (-0.15, 0.76, -0.03), STEEL, kind="Metal")
    pl.cyl(0.06, 0.1, (0.35, 0.75, -0.2), PAPER, segs=8, rot=[("z", math.pi / 2)])   # the roll
    pl.solid((0.48, 0.85, 0.7), (0, 0.42, 0.05))


def vanity(pl, cab, w=0.9):
    pl.box((w, 0.82, 0.5), (0, 0.41, 0.25), cab)
    pl.box((w + 0.02, 0.04, 0.53), (0, 0.84, 0.265), (0.92, 0.92, 0.9))
    pl.box((0.42, 0.02, 0.32), (0, 0.855, 0.28), (0.97, 0.97, 0.96), kind="Gloss")
    pl.cyl(0.015, 0.2, (0, 0.95, 0.08), STEEL, segs=6, kind="Metal")
    pl.box((0.02, 0.02, 0.12), (0, 1.04, 0.13), STEEL, kind="Metal")
    pl.box((w - 0.1, 0.8, 0.03), (0, 1.55, 0.015), (0.72, 0.8, 0.86), kind="Gloss")
    pl.box((w - 0.04, 0.84, 0.02), (0, 1.55, 0.005), (0.85, 0.85, 0.83))
    for sx in (-w / 4, w / 4):
        pl.box((w / 2 - 0.05, 0.6, 0.01), (sx, 0.42, 0.505), [c * 0.92 for c in cab])
    pl.cyl(0.035, 0.18, (w / 2 - 0.12, 0.95, 0.35), (0.3, 0.6, 0.85), segs=8)       # soap
    pl.solid((w, 0.86, 0.52), (0, 0.43, 0.26))


def bathtub(pl, curtain):
    L, d, h = 1.6, 0.76, 0.56
    pl.box((L, h, d), (0, h / 2, 0), (0.97, 0.97, 0.96), kind="Gloss")
    pl.box((L - 0.16, 0.02, d - 0.16), (0, h - 0.18, 0.0), (0.82, 0.88, 0.92), kind="Gloss")
    pl.cyl(0.02, 0.2, (-L / 2 + 0.12, h + 0.2, -d / 2 + 0.08), STEEL, segs=6, kind="Metal")
    pl.cyl(0.08, 0.02, (-L / 2 + 0.12, 1.85, -d / 2 + 0.2), STEEL, segs=10, kind="Metal", rot=[("x", 0.5)])
    pl.cyl(0.012, L, (0, 2.0, d / 2 - 0.04), STEEL, segs=6, kind="Metal", rot=[("z", math.pi / 2)])
    for k in range(9):   # a gathered shower curtain
        x = -L / 2 + 0.25 + k * 0.08
        pl.box((0.08, 1.4, 0.02), (x, 1.3, d / 2 - 0.04 + (0.03 if k % 2 else -0.03)), curtain)
    pl.solid((L, h, d), (0, h / 2, 0))


def washer_dryer(pl):
    for sx in (-0.35, 0.35):
        pl.box((0.66, 0.9, 0.64), (sx, 0.45, 0.32), (0.95, 0.95, 0.94), kind="Gloss", r=0.02)
        pl.cyl(0.2, 0.02, (sx, 0.45, 0.645), (0.25, 0.3, 0.35), segs=14, kind="Gloss", rot=[("x", math.pi / 2)])
        pl.box((0.6, 0.1, 0.02), (sx, 0.82, 0.645), (0.8, 0.8, 0.82))
    pl.box((0.5, 0.35, 0.35), (0.35, 1.08, 0.3), (0.3, 0.45, 0.8))       # laundry basket
    pl.solid((1.36, 0.95, 0.66), (0, 0.47, 0.33))


def shelves(pl, w, wood):
    for k in range(4):
        pl.box((w, 0.03, 0.4), (0, 0.4 + k * 0.45, 0.2), wood)
    for sx in (-1, 1):
        pl.box((0.03, 1.8, 0.4), (sx * w / 2, 0.9, 0.2), wood)
    cols = [(0.8, 0.3, 0.2), (0.3, 0.5, 0.7), (0.95, 0.9, 0.6), (0.4, 0.4, 0.42)]
    for k in range(7):
        pl.box((0.3, 0.25, 0.3), (-w / 2 + 0.3 + (k % 3) * (w - 0.6) / 2, 0.55 + (k // 3) * 0.45, 0.2), cols[k % 4])
    pl.solid((w, 1.9, 0.42), (0, 0.95, 0.2))


def curtains(pl, w, h, col):
    for sx in (-1, 1):
        pl.box((0.32, h, 0.05), (sx * (w / 2 + 0.1), 0, 0.06), col)
    pl.cyl(0.015, w + 0.7, (0, h / 2 + 0.08, 0.08), (0.3, 0.25, 0.2), segs=6, rot=[("z", math.pi / 2)])


def ceiling_lamp(x, y, z, glass=(1.0, 0.96, 0.85)):
    cyl(0.08, 0.04, (x, y - 0.02, z), (0.9, 0.9, 0.88), segs=10)
    cyl(0.2, 0.1, (x, y - 0.09, z), glass, segs=14, r2=0.12, kind="Glow")


# ----------------------------------------------------------------- room shell builder

def interior_shell(spec, rooms, doors, lining_openings, colliders):
    """Walls/floors/ceilings per room. rooms: name -> dict(rect=(x0,z0,x1,z1), floor, wall);
    doors: list of (axis, fixed, ua, ub, h) partition openings (axis 'x': wall along x at z=fixed).
    lining_openings: exterior openings per side name ('front','back','left','right')."""
    FH, W, D = spec.FH, spec.W, spec.D
    xin0, xin1 = -W / 2 + T, W / 2 - T
    zin_f, zin_b = -T, -D + T
    top = FH + CEIL
    for name, r in rooms.items():
        x0, z0, x1, z1 = r["rect"]
        # floor + ceiling (floor slightly under partitions too)
        box2((x0 - 0.05, FH - 0.04, z0 - 0.05), (x1 + 0.05, FH, z1 + 0.05), r["floor"])
        if r.get("planks"):
            n = int((x1 - x0) / 0.16)
            for k in range(1, n):
                x = x0 + k * (x1 - x0) / n
                box2((x - 0.004, FH, z0), (x + 0.004, FH + 0.002, z1), [c * 0.82 for c in r["floor"]])
        if r.get("tiles"):
            step = 0.3
            x = x0 + step
            while x < x1:
                box2((x - 0.006, FH, z0), (x + 0.006, FH + 0.002, z1), [c * 0.8 for c in r["floor"]])
                x += step
            z = z0 + step
            while z < z1:
                box2((x0, FH, z - 0.006), (x1, FH + 0.002, z + 0.006), [c * 0.8 for c in r["floor"]])
                z += step
        box2((x0 - 0.05, top, z0 - 0.05), (x1 + 0.05, top + 0.04, z1 + 0.05), r.get("ceil", (0.95, 0.95, 0.94)))
        wc = r["wall"]
        # each side: lining (on an exterior wall) or half a partition
        sides = [("x", z1, -1, x0, x1, "front" if abs(z1 - (zin_f - LIN)) < 0.02 else None),
                 ("x", z0, 1, x0, x1, "back" if abs(z0 - (zin_b + LIN)) < 0.02 else None),
                 ("z", x0, 1, z0, z1, "left" if abs(x0 - (xin0 + LIN)) < 0.02 else None),
                 ("z", x1, -1, z0, z1, "right" if abs(x1 - (xin1 - LIN)) < 0.02 else None)]
        for axis, fixed, tdir, ua, ub, ext in sides:
            # the wall face is at `fixed`; its body extends away from the room (-tdir)
            ops = []
            if ext:
                for o in lining_openings.get(ext, []):
                    ops.append(o)
                if ext == "front" and spec.door:
                    ops.append(spec.door)
                t = LIN
            else:
                t = PT / 2
                for ax2, fx2, a, b, h in doors:
                    if ax2 == axis and abs(fx2 - (fixed - tdir * PT / 2)) < 0.03:
                        ops.append((a, b, FH, FH + h))
            ua_e, ub_e = (ua - (0 if ext else PT / 2), ub + (0 if ext else PT / 2))
            if ext:
                ua_e, ub_e = ua - LIN, ub + LIN
            for pa, pb, ya, yb in pieces(ua_e, ub_e, FH - 0.04, top, ops):
                wbox(axis, fixed, -tdir, pa, pb, ya, yb, 0.0, t, wc)
            if not ext:
                for pa, pb, ya, yb in pieces(ua_e, ub_e, FH, top, ops):
                    wcoll(colliders, axis, fixed, -tdir, pa, pb, ya, yb, 0.0, t)
            # baseboard (skipping door gaps), casing around openings
            base = r.get("base", (0.97, 0.97, 0.95))
            for pa, pb, ya, yb in pieces(ua, ub, FH, FH + 0.1, [o for o in ops if o[2] <= FH + 0.05]):
                wbox(axis, fixed, tdir, pa, pb, FH, FH + 0.1, 0.0, 0.015, base)
            for o in ops:
                a, b, va, vb = o
                trimc = (0.97, 0.97, 0.95)
                wbox(axis, fixed, tdir, a - 0.07, a, va, vb + 0.07, 0.0, 0.015, trimc)
                wbox(axis, fixed, tdir, b, b + 0.07, va, vb + 0.07, 0.0, 0.015, trimc)
                wbox(axis, fixed, tdir, a - 0.07, b + 0.07, vb, vb + 0.07, 0.0, 0.015, trimc)
                if va > FH + 0.05:
                    wbox(axis, fixed, tdir, a - 0.09, b + 0.09, va - 0.05, va, 0.0, 0.05, trimc)   # stool
                    # jamb liners through the lining
                    wbox(axis, fixed, -tdir, a, a + 0.02, va, vb, 0.0, t, trimc)
                    wbox(axis, fixed, -tdir, b - 0.02, b, va, vb, 0.0, t, trimc)
                    wbox(axis, fixed, -tdir, a, b, vb - 0.02, vb, 0.0, t, trimc)
                else:
                    # doorway: jambs + head through the partition, threshold strip
                    wbox(axis, fixed, -tdir, a, a + 0.02, va, vb, 0.0, t, trimc)
                    wbox(axis, fixed, -tdir, b - 0.02, b, va, vb, 0.0, t, trimc)
                    wbox(axis, fixed, -tdir, a, b, vb - 0.02, vb, 0.0, t, trimc)
                    wbox(axis, fixed, -tdir, a, b, FH - 0.03, FH + 0.004, 0.0, t, (0.6, 0.5, 0.38))
        ceiling_lamp((x0 + x1) / 2, top, (z0 + z1) / 2)


def rooms_rect(name, x0, z0, x1, z1, floor, wall, **kw):
    d = {"rect": (x0, z0, x1, z1), "floor": floor, "wall": wall}
    d.update(kw)
    return name, d


def spec_of(name):
    return SPECS[name]


def build_interior(iid, tname, rooms, doors, furnish, price_tier):
    spec = spec_of(tname)
    colliders, lights = [], []
    lining = {"front": spec.front, "back": spec.back, "left": spec.left, "right": spec.right}
    interior_shell(spec, rooms, doors, lining, colliders)
    extra = furnish(spec, rooms, colliders)
    FH = spec.FH
    for name, r in rooms.items():
        x0, z0, x1, z1 = r["rect"]
        diag = math.hypot(x1 - x0, z1 - z0)
        lights.append([round((x0 + x1) / 2, 3), round(FH + CEIL - 0.35, 3), round((z0 + z1) / 2, 3),
                       round(max(3.2, diag * 0.75), 2), 0.9 if name != "closet" else 0.5])
    finish("Int_" + iid)
    LAYOUT["interiors"][iid] = {"type": tname, "colliders": colliders, "lights": lights,
                                "rooms": [[n, *r3(r["rect"])] for n, r in rooms.items()], "tier": price_tier, **extra}


# palettes for the variants
PAL = {
    "cozy": {"couch": (0.36, 0.45, 0.32), "pillow": (0.85, 0.65, 0.3), "wood": (0.5, 0.33, 0.2), "rug": (0.62, 0.3, 0.22),
             "rug2": (0.85, 0.75, 0.55), "blanket": (0.25, 0.35, 0.55), "cab": (0.9, 0.88, 0.8), "top": (0.55, 0.5, 0.45),
             "chair": (0.5, 0.33, 0.2), "curtain": (0.75, 0.65, 0.45), "art": (0.3, 0.5, 0.65), "tub": (0.55, 0.75, 0.8)},
    "modern": {"couch": (0.32, 0.33, 0.36), "pillow": (0.9, 0.45, 0.2), "wood": (0.2, 0.18, 0.17), "rug": (0.85, 0.85, 0.82),
               "rug2": (0.35, 0.36, 0.4), "blanket": (0.85, 0.85, 0.83), "cab": (0.2, 0.25, 0.3), "top": (0.93, 0.93, 0.92),
               "chair": (0.12, 0.12, 0.13), "curtain": (0.55, 0.57, 0.6), "art": (0.85, 0.35, 0.2), "tub": (0.9, 0.9, 0.9)},
    "retro": {"couch": (0.65, 0.4, 0.2), "pillow": (0.3, 0.55, 0.5), "wood": (0.55, 0.38, 0.22), "rug": (0.45, 0.55, 0.3),
              "rug2": (0.9, 0.8, 0.5), "blanket": (0.75, 0.3, 0.25), "cab": (0.65, 0.8, 0.7), "top": (0.95, 0.92, 0.85),
              "chair": (0.8, 0.25, 0.2), "curtain": (0.9, 0.8, 0.5), "art": (0.9, 0.6, 0.2), "tub": (0.95, 0.75, 0.8)},
    "worn": {"couch": (0.5, 0.42, 0.35), "pillow": (0.7, 0.2, 0.2), "wood": (0.42, 0.3, 0.2), "rug": (0.4, 0.3, 0.3),
             "rug2": (0.6, 0.55, 0.45), "blanket": (0.45, 0.5, 0.35), "cab": (0.85, 0.82, 0.72), "top": (0.7, 0.62, 0.5),
             "chair": (0.45, 0.35, 0.25), "curtain": (0.8, 0.8, 0.75), "art": (0.4, 0.55, 0.35), "tub": (0.9, 0.9, 0.88)},
}


def front_curtains(spec, pal):
    """Curtains on every front/side window (interior side)."""
    FH = spec.FH
    W, D = spec.W, spec.D
    for o in spec.front:
        pl = Pl((o[0] + o[1]) / 2, (o[2] + o[3]) / 2, -T - LIN, math.pi)
        curtains(pl, o[1] - o[0], o[3] - o[2] + 0.3, pal["curtain"])
    for o in spec.left:
        pl = Pl(-W / 2 + T + LIN, (o[2] + o[3]) / 2, (o[0] + o[1]) / 2, math.pi / 2)
        curtains(pl, o[1] - o[0], o[3] - o[2] + 0.3, pal["curtain"])
    for o in spec.right:
        pl = Pl(W / 2 - T - LIN, (o[2] + o[3]) / 2, (o[0] + o[1]) / 2, -math.pi / 2)
        curtains(pl, o[1] - o[0], o[3] - o[2] + 0.3, pal["curtain"])


def bedroom_set(spec, r, col, pal, bed_wall, bed_u, colliders, big=False):
    """Bed against a wall + nightstands (the one on the spawn side has the alarm clock).
    bed_wall: 'back' (head at z0), 'right' (head at x1), 'left', 'front'. Returns spawn info."""
    FH = spec.FH
    x0, z0, x1, z1 = r["rect"]
    w, L = (1.8, 2.1) if big else (1.5, 2.0)
    if bed_wall == "back":
        yaw, cx, cz = 0.0, bed_u, z0 + L / 2 + 0.05
        side = (1, 0)
    elif bed_wall == "front":
        yaw, cx, cz = math.pi, bed_u, z1 - L / 2 - 0.05
        side = (-1, 0)
    elif bed_wall == "right":
        yaw, cx, cz = -math.pi / 2, x1 - L / 2 - 0.05, bed_u
        side = (0, -1)
    else:
        yaw, cx, cz = math.pi / 2, x0 + L / 2 + 0.05, bed_u
        side = (0, 1)
    b = Pl(cx, FH, cz, yaw, colliders)
    bed(b, pal["wood"], pal["blanket"], w=w, L=L)
    # nightstands at the head, either side
    head = b.P((0, 0, -L / 2 + 0.24))
    ns = []
    for sx in (-1, 1):
        p = Pl(*b.P((sx * (w / 2 + 0.33), 0, -L / 2 + 0.24)), yaw=yaw, colliders=colliders)
        nightstand(p, pal["wood"], clock=(sx == 1), lamp=True)
        ns.append(p)
    # spawn: standing beside the bed on the clock side, facing the bed's foot direction
    sp = b.P((w / 2 + 0.45, 0.0, 0.25))
    clock = ns[1].P((0.1, 0.61, 0.05))
    rug(Pl(*b.P((0, 0, 0.3)), yaw=yaw), w + 1.2, L * 0.8, pal["rug2"])
    return {"spawn": [round(sp[0], 3), round(FH + 0.15, 3), round(sp[2], 3), round(yaw + math.pi, 4)],
            "bed": r3(b.P((0, 0.6, 0))), "clock": r3(clock)}


def living_set(spec, r, pal, tv_wall, colliders, big=False):
    FH = spec.FH
    x0, z0, x1, z1 = r["rect"]
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    if tv_wall == "left":        # TV against the left wall, couch facing it
        tv = Pl(x0 + 0.25, FH, cz, math.pi / 2, colliders)
        c = Pl(min(x1 - 0.6, x0 + 3.6), FH, cz, -math.pi / 2, colliders)
        ct = Pl((x0 + 0.25 + min(x1 - 0.6, x0 + 3.6)) / 2 + 0.2, FH, cz, math.pi / 2, colliders)
        rg = Pl((x0 + min(x1, x0 + 3.9)) / 2 + 0.2, FH, cz, math.pi / 2)
    elif tv_wall == "back":
        tv = Pl(cx, FH, z0 + 0.25, 0.0, colliders)
        c = Pl(cx, FH, min(z1 - 0.6, z0 + 3.5), math.pi, colliders)
        ct = Pl(cx, FH, (z0 + min(z1 - 0.6, z0 + 3.5)) / 2 + 0.3, 0.0, colliders)
        rg = Pl(cx, FH, (z0 + min(z1, z0 + 3.9)) / 2 + 0.3, 0.0)
    else:   # right
        tv = Pl(x1 - 0.25, FH, cz, -math.pi / 2, colliders)
        c = Pl(max(x0 + 0.6, x1 - 3.6), FH, cz, math.pi / 2, colliders)
        ct = Pl((x1 - 0.25 + max(x0 + 0.6, x1 - 3.6)) / 2 - 0.2, FH, cz, -math.pi / 2, colliders)
        rg = Pl((x1 + max(x0, x1 - 3.9)) / 2 - 0.2, FH, cz, -math.pi / 2)
    rug(rg, 2.6, 2.0, pal["rug"], border=pal["rug2"])
    tv_unit(tv, pal["wood"], big)
    couch(c, pal["couch"], w=2.2 if big else 2.0, pillows=pal["pillow"])
    coffee_table(ct, pal["wood"])
    return c


def furnish_ranch(pal, variant):
    def f(spec, rooms, cl):
        FH = spec.FH
        front_curtains(spec, pal)
        lv = rooms["living"]
        x0, z0, x1, z1 = lv["rect"]
        living_set(spec, lv, pal, "left", cl, big=(variant == "b"))
        plant(Pl(x0 + 0.35, FH, z1 - 0.4, 0, cl))
        floor_lamp(Pl(x0 + 0.35, FH, z0 + 0.4))
        bookshelf(Pl(x1 - 0.95, FH, z0 + 0.18, 0.0, cl), pal["wood"])
        armchair(Pl(x0 + 2.0, FH, z1 - 0.7, math.pi, cl), pal["couch"] if variant == "a" else (0.6, 0.35, 0.2))
        wall_art(Pl(-0.9, FH + 1.6, z1 - 0.01, math.pi), 0.8, 0.6, pal["art"])
        # kitchen: counters on the back wall + left wall, fridge, stove, table
        k = rooms["kitchen"]
        x0, z0, x1, z1 = k["rect"]
        fridge(Pl(-5.58, FH, z0 + 0.02, 0.0, cl), steel=(variant == "b"))
        kitchen_run(Pl(-4.6, FH, z0, 0.0, cl), 1.1, pal["cab"], pal["top"])
        stove(Pl(-3.66, FH, z0 + 0.02, 0.0, cl))
        kitchen_run(Pl(-2.08, FH, z0, 0.0, cl), 2.36, pal["cab"], pal["top"], sink_at=0.48, no_upper=(-0.12, 1.08))
        dining(Pl(-4.3, FH, -6.4, math.pi / 2, cl), pal["wood"], pal["chair"])
        rug(Pl(-4.3, FH, -6.4), 2.0, 2.3, pal["rug2"])
        wall_art(Pl(x1 - 0.01, FH + 1.5, -6.4, -math.pi / 2), 0.6, 0.8, pal["art"])
        # bedroom (front right): bed against the right wall
        bd = rooms["bedroom"]
        x0, z0, x1, z1 = bd["rect"]
        info = bedroom_set(spec, bd, None, pal, "right", (z0 + z1) / 2 - 0.2, cl, big=(variant == "b"))
        dresser(Pl((x0 + x1) / 2 - 0.4, FH, z0 + 0.27, 0.0, cl), pal["wood"])
        wall_art(Pl(x1 - 0.01, FH + 1.55, (z0 + z1) / 2 - 0.2, -math.pi / 2), 1.0, 0.6, pal["art"])
        # bathroom: tub on the back wall, toilet, vanity
        b = rooms["bath"]
        x0, z0, x1, z1 = b["rect"]
        bathtub(Pl(x0 + 0.82, FH, z0 + 0.4, 0.0, cl), pal["tub"])
        toilet(Pl(x1 - 0.35, FH, z0 + 1.35, -math.pi / 2, cl))
        vanity(Pl(x0, FH, z1 - 0.9, math.pi / 2, cl), pal["cab"])
        rug(Pl((x0 + x1) / 2, FH, z1 - 1.0), 0.9, 0.55, pal["tub"])
        c = rooms["closet"]
        x0, z0, x1, z1 = c["rect"]
        washer_dryer(Pl((x0 + x1) / 2, FH, z0 + 0.02, 0.0, cl))
        shelves(Pl(x1 - 0.02, FH, (z0 + z1) / 2 + 0.3, -math.pi / 2, cl), 1.2, pal["wood"])
        return info
    return f


def furnish_shotgun(pal):
    def f(spec, rooms, cl):
        FH = spec.FH
        front_curtains(spec, pal)
        lv = rooms["living"]
        x0, z0, x1, z1 = lv["rect"]
        living_set(spec, lv, pal, "left", cl)
        plant(Pl(x1 - 0.35, FH, z1 - 0.4, 0, cl))
        floor_lamp(Pl(x0 + 0.35, FH, z1 - 0.4))
        wall_art(Pl((x0 + x1) / 2 - 0.4, FH + 1.6, z0 + 0.01, 0.0), 0.9, 0.6, pal["art"])
        bd = rooms["bedroom"]
        x0, z0, x1, z1 = bd["rect"]
        info = bedroom_set(spec, bd, None, pal, "left", (z0 + z1) / 2, cl)
        dresser(Pl(x1 - 0.27, FH, (z0 + z1) / 2 - 1.3, -math.pi / 2, cl), pal["wood"], mirror=False)
        k = rooms["kitchen"]
        x0, z0, x1, z1 = k["rect"]
        kitchen_run(Pl(x0, FH, (z0 + z1) / 2 + 0.2, math.pi / 2, cl), 2.4, pal["cab"], pal["top"], sink_at=0.25,
                    no_upper=(-0.2, 0.7))
        fridge(Pl(x0 + 0.02 + 0.41, FH, z0 + 0.05, 0.0, cl))
        stove(Pl(x1 - 0.02, FH, z0 + 0.5, -math.pi / 2, cl))
        dining(Pl(-0.6, FH, (z0 + z1) / 2 + 0.6, math.pi / 2, cl), pal["wood"], pal["chair"], w=1.0, d=0.75, chairs=2)
        b = rooms["bath"]
        x0, z0, x1, z1 = b["rect"]
        bathtub(Pl(x0 + 0.82, FH, z0 + 0.4, 0.0, cl), pal["tub"])
        toilet(Pl(x1 - 0.35, FH, z0 + 0.6, -math.pi / 2, cl))
        vanity(Pl(x0 + 0.45, FH, z1 - 0.02, math.pi, cl), pal["cab"], w=0.7)
        return info
    return f


def furnish_bungalow(pal, variant):
    def f(spec, rooms, cl):
        FH = spec.FH
        front_curtains(spec, pal)
        lv = rooms["living"]
        x0, z0, x1, z1 = lv["rect"]
        living_set(spec, lv, pal, "left", cl, big=(variant == "b"))
        bookshelf(Pl(x1 - 0.2, FH, z0 + 1.0, -math.pi / 2, cl), pal["wood"])
        plant(Pl(x0 + 0.35, FH, z1 - 0.4, 0, cl), tall=1.4)
        floor_lamp(Pl(x1 - 0.35, FH, z1 - 0.5))
        wall_art(Pl(x0 + 2.2, FH + 1.6, z0 + 0.01, 0.0), 1.2, 0.8, pal["art"])
        bd = rooms["bedroom"]
        x0, z0, x1, z1 = bd["rect"]
        info = bedroom_set(spec, bd, None, pal, "right", (z0 + z1) / 2 - 0.3, cl, big=(variant == "b"))
        dresser(Pl(3.7, FH, z1 - 0.27, math.pi, cl), pal["wood"])
        closet_doors(Pl((x0 + x1) / 2 + 0.6, FH, z0 + 0.0, 0.0), 1.4, (0.95, 0.95, 0.93))
        k = rooms["kitchen"]
        x0, z0, x1, z1 = k["rect"]
        kitchen_run(Pl(-1.9, FH, z0, 0.0, cl), 2.4, pal["cab"], pal["top"], sink_at=-0.6, no_upper=(-1.1, -0.1))
        fridge(Pl(x0 + 0.05 + 0.41, FH, z0 + 0.05, 0.0, cl), steel=(variant == "b"))
        stove(Pl(x0 + 0.03, FH, z0 + 1.6, math.pi / 2, cl))
        if variant == "b":   # an island in the renovated one
            kitchen_run(Pl((x0 + x1) / 2 + 0.3, FH, z0 + 2.0, 0.0, cl), 1.8, pal["cab"], pal["top"], uppers=False)
        dining(Pl((x0 + x1) / 2 + 0.2, FH, z1 - 1.3, 0.0, cl), pal["wood"], pal["chair"])
        b = rooms["bath"]
        x0, z0, x1, z1 = b["rect"]
        bathtub(Pl(x1 - 0.82, FH, (z0 + z1) / 2, math.pi, cl), pal["tub"]) if (z1 - z0) > 1.6 else None
        toilet(Pl(x0 + 0.35, FH, z0 + 0.5, math.pi / 2, cl))
        vanity(Pl(x0 + 1.2, FH, z0 + 0.02, 0.0, cl), pal["cab"], w=0.8)
        c = rooms["laundry"]
        x0, z0, x1, z1 = c["rect"]
        washer_dryer(Pl((x0 + x1) / 2, FH, z0 + 0.02, 0.0, cl))
        shelves(Pl(x1 - 0.02, FH, z0 + 0.8, -math.pi / 2, cl), 1.2, pal["wood"])
        return info
    return f


def furnish_tin(pal):
    def f(spec, rooms, cl):
        FH = spec.FH
        front_curtains(spec, pal)
        lv = rooms["living"]
        x0, z0, x1, z1 = lv["rect"]
        living_set(spec, lv, pal, "left", cl)
        plant(Pl(x1 - 0.35, FH, z0 + 0.4, 0, cl))
        wall_art(Pl((x0 + x1) / 2, FH + 1.6, z0 + 0.01, 0.0), 0.8, 0.55, pal["art"])
        bd = rooms["bedroom"]
        x0, z0, x1, z1 = bd["rect"]
        info = bedroom_set(spec, bd, None, pal, "left", (z0 + z1) / 2 + 0.3, cl)
        dresser(Pl(x1 - 0.27, FH, z0 + 0.9, -math.pi / 2, cl), pal["wood"], mirror=False)
        k = rooms["kitchen"]
        x0, z0, x1, z1 = k["rect"]
        kitchen_run(Pl(x0, FH, (z0 + z1) / 2, math.pi / 2, cl), 2.0, pal["cab"], pal["top"], sink_at=0.2,
                    no_upper=(-0.03, 0.67))
        fridge(Pl(x0 + 0.4, FH, z0 + 0.05, 0.0, cl))
        stove(Pl(x1 - 0.02, FH, z0 + 0.5, -math.pi / 2, cl))
        b = rooms["bath"]
        x0, z0, x1, z1 = b["rect"]
        toilet(Pl(x1 - 0.35, FH, z0 + 0.6, -math.pi / 2, cl))
        vanity(Pl(x0 + 0.05, FH, z0 + 1.6, math.pi / 2, cl), pal["cab"], w=0.6)
        box2((x0 + 0.05, FH, z0 + 0.05), (x0 + 0.95, FH + 0.12, z0 + 0.95), (0.9, 0.9, 0.9))   # shower pan
        box2((x0 + 0.95, FH, z0 + 0.05), (x0 + 0.98, FH + 2.0, z0 + 0.95), (0.8, 0.85, 0.9), "Glass")
        return info
    return f


def interiors():
    # ---- ranch (two variants)
    s = SPECS["ranch"]
    FH = s.FH
    xi0, xi1 = -s.W / 2 + T + LIN, s.W / 2 - T - LIN
    zf, zb = -T - LIN, -s.D + T + LIN
    for iid, pal, variant, walls in (("ranch_a", PAL["cozy"], "a", ((0.88, 0.83, 0.72), (0.95, 0.9, 0.7), (0.72, 0.8, 0.72))),
                                     ("ranch_b", PAL["modern"], "b", ((0.9, 0.9, 0.88), (0.86, 0.87, 0.88), (0.62, 0.66, 0.72)))):
        wood = (0.62, 0.45, 0.28) if variant == "a" else (0.55, 0.5, 0.45)
        rooms = dict([
            rooms_rect("living", xi0, -4.4, 0.9, zf, wood, walls[0], planks=True),
            rooms_rect("kitchen", xi0, zb, 0.9, -4.5, (0.82, 0.8, 0.74), walls[1], tiles=True),
            rooms_rect("bedroom", 1.0, -4.4, xi1, zf, (0.6, 0.55, 0.5) if variant == "a" else (0.7, 0.7, 0.72), walls[2]),
            rooms_rect("bath", 1.0, zb, 3.5, -4.5, (0.92, 0.92, 0.9), (0.72, 0.84, 0.88), tiles=True),
            rooms_rect("closet", 3.6, zb, xi1, -4.5, (0.75, 0.73, 0.7), (0.93, 0.93, 0.9)),
        ])
        doors = [("x", -4.45, -4.8, -1.8, 2.25), ("z", 0.95, -3.6, -2.7, 2.05),
                 ("x", -4.45, 1.6, 2.4, 2.05), ("x", -4.45, 4.4, 5.2, 2.05)]
        build_interior(iid, "ranch", rooms, doors, furnish_ranch(pal, variant), variant)
    # ---- shotgun
    s = SPECS["shotgun"]
    xi0, xi1 = -s.W / 2 + T + LIN, s.W / 2 - T - LIN
    zf, zb = -T - LIN, -s.D + T + LIN
    rooms = dict([
        rooms_rect("living", xi0, -4.35, xi1, zf, (0.58, 0.4, 0.25), (0.85, 0.72, 0.6), planks=True),
        rooms_rect("bedroom", xi0, -8.55, xi1, -4.45, (0.58, 0.4, 0.25), (0.7, 0.78, 0.7), planks=True),
        rooms_rect("kitchen", xi0, -12.35, xi1, -8.65, (0.85, 0.82, 0.7), (0.95, 0.88, 0.62), tiles=True),
        rooms_rect("bath", xi0, zb, xi1, -12.45, (0.9, 0.9, 0.88), (0.95, 0.8, 0.82), tiles=True),
    ])
    doors = [("x", -4.4, 0.7, 1.6, 2.1), ("x", -8.6, 0.7, 1.6, 2.1), ("x", -12.4, 0.7, 1.6, 2.1)]
    build_interior("shotgun_a", "shotgun", rooms, doors, furnish_shotgun(PAL["retro"]), "a")
    # ---- bungalow (two variants)
    s = SPECS["bungalow"]
    xi0, xi1 = -s.W / 2 + T + LIN, s.W / 2 - T - LIN
    zf, zb = -T - LIN, -s.D + T + LIN
    for iid, pal, variant in (("bungalow_a", PAL["worn"], "a"), ("bungalow_b", PAL["modern"], "b")):
        wood = (0.55, 0.36, 0.2) if variant == "a" else (0.72, 0.6, 0.45)
        rooms = dict([
            rooms_rect("living", xi0, -5.35, 0.85, zf, wood, (0.84, 0.8, 0.66) if variant == "a" else (0.92, 0.92, 0.9), planks=True),
            rooms_rect("bedroom", 0.95, -5.35, xi1, zf, wood, (0.66, 0.74, 0.82) if variant == "a" else (0.55, 0.62, 0.58), planks=True),
            rooms_rect("kitchen", xi0, zb, 0.85, -5.45, (0.8, 0.8, 0.78), (0.9, 0.9, 0.78) if variant == "a" else (0.88, 0.9, 0.9), tiles=True),
            rooms_rect("bath", 0.95, -8.0, xi1, -5.45, (0.92, 0.92, 0.9), (0.7, 0.82, 0.8), tiles=True),
            rooms_rect("laundry", 0.95, zb, xi1, -8.1, (0.75, 0.73, 0.7), (0.93, 0.93, 0.9)),
        ])
        doors = [("x", -5.4, -3.8, -0.9, 2.25), ("z", 0.9, -3.2, -2.3, 2.05), ("x", -5.4, 1.5, 2.3, 2.05),
                 ("z", 0.9, -9.8, -8.9, 2.05)]
        build_interior(iid, "bungalow", rooms, doors, furnish_bungalow(pal, variant), variant)
    # ---- tin shotgun
    s = SPECS["tin"]
    xi0, xi1 = -s.W / 2 + T + LIN, s.W / 2 - T - LIN
    zf, zb = -T - LIN, -s.D + T + LIN
    rooms = dict([
        rooms_rect("living", xi0, -4.15, xi1, zf, (0.5, 0.36, 0.24), (0.85, 0.8, 0.7), planks=True),
        rooms_rect("bedroom", xi0, -8.25, xi1, -4.25, (0.5, 0.36, 0.24), (0.62, 0.72, 0.78), planks=True),
        rooms_rect("kitchen", xi0, zb, 0.35, -8.35, (0.8, 0.78, 0.7), (0.92, 0.88, 0.7), tiles=True),
        rooms_rect("bath", 0.45, zb, xi1, -8.35, (0.9, 0.9, 0.88), (0.85, 0.9, 0.92), tiles=True),
    ])
    doors = [("x", -4.2, 0.6, 1.5, 2.05), ("x", -8.3, -1.55, -0.75, 2.05), ("x", -8.3, 0.85, 1.65, 2.05)]
    build_interior("tin_a", "tin", rooms, doors, furnish_tin(PAL["worn"]), "a")


# ============================================================================ yard + street props

def yard_props():
    # mailbox on a wooden post (door toward +z = the street), red flag
    box2((-0.05, 0.0, -0.05), (0.05, 1.0, 0.05), (0.42, 0.3, 0.2))
    box2((-0.12, 0.98, -0.3), (0.12, 1.02, 0.25), (0.42, 0.3, 0.2))
    rbox((0.22, 0.2, 0.5), (0, 1.12, -0.02), (0.1, 0.1, 0.11), r=0.09, seg=3, kind="Metal")
    box2((-0.1, 1.03, 0.23), (0.1, 1.2, 0.235), (0.14, 0.14, 0.15))
    box2((0.12, 1.1, -0.15), (0.13, 1.3, -0.12), (0.85, 0.1, 0.08))
    box2((0.12, 1.25, -0.15), (0.13, 1.3, -0.02), (0.85, 0.1, 0.08))
    finish("Mailbox")
    # wheeled trash bins
    for name, col in (("TrashBin_Green", (0.15, 0.4, 0.2)), ("TrashBin_Blue", (0.12, 0.3, 0.6)),
                      ("TrashBin_Black", (0.12, 0.12, 0.13))):
        rbox((0.58, 0.95, 0.68), (0, 0.55, 0), col, r=0.04, seg=1)
        rbox((0.64, 0.06, 0.76), (0, 1.05, 0.02), [c * 0.85 for c in col], r=0.02, seg=1)
        box2((-0.26, 0.95, -0.4), (0.26, 1.0, -0.36), [c * 0.7 for c in col])
        for sx in (-0.27, 0.27):
            cyl(0.1, 0.05, (sx, 0.1, -0.3), BLACK, segs=10, rot=[("z", math.pi / 2)])
        finish(name)
    # fences: 2.4 m segments along x, centered, front = +z
    for k in range(2):
        box2((-1.2 + k * 2.4 - 0.05, 0.0, -0.05), (-1.2 + k * 2.4 + 0.05, 1.85, 0.05), (0.42, 0.31, 0.2))
    for y in (0.35, 1.5):
        box2((-1.2, y, -0.06), (1.2, y + 0.09, -0.02), (0.45, 0.33, 0.21))
    for k in range(16):
        x = -1.2 + (k + 0.5) * 0.15
        c = (0.55 + (k * 13 % 5) * 0.015, 0.4 + (k * 7 % 4) * 0.012, 0.26)
        box2((x - 0.07, 0.03, -0.02), (x + 0.07, 1.8, 0.0), c)
    finish("FenceWood")
    for k in range(2):
        box2((-1.2 + k * 2.4 - 0.045, 0.0, -0.045), (-1.2 + k * 2.4 + 0.045, 1.05, 0.045), (0.95, 0.95, 0.93))
    for y in (0.25, 0.75):
        box2((-1.2, y, -0.05), (1.2, y + 0.07, -0.02), (0.93, 0.93, 0.91))
    for k in range(12):
        x = -1.2 + (k + 0.5) * 0.2
        box2((x - 0.04, 0.05, -0.02), (x + 0.04, 0.9, 0.0), (0.96, 0.96, 0.94))
        rbox((0.056, 0.056, 0.02), (x, 0.9, -0.01), (0.96, 0.96, 0.94), rot=[("z", math.pi / 4)])
    finish("FencePicket")
    # low wire field fence (posts + 3 wires)
    for k in range(2):
        cyl(0.05, 1.2, (-1.2 + k * 2.4, 0.6, 0), (0.45, 0.35, 0.25), segs=6)
    for y in (0.4, 0.75, 1.1):
        rod((-1.2, y, 0.03), (1.2, y - 0.02, 0.03), 0.006, (0.5, 0.5, 0.52), segs=3, kind="Metal")
    finish("FenceWire")
    # utility pole (wood, crossarm with insulators) and one with a transformer + a street light
    for name, tx, light in (("UtilityPole", False, False), ("UtilityPoleTx", True, False), ("UtilityPoleLight", False, True)):
        cyl(0.14, 10.0, (0, 5.0, 0), (0.36, 0.3, 0.24), segs=8, r2=0.11)
        box2((-1.25, 9.1, -0.06), (1.25, 9.24, 0.06), (0.38, 0.3, 0.22))
        rod((-0.9, 8.4, 0), (-0.05, 9.12, 0), 0.025, (0.3, 0.3, 0.3), segs=4)
        rod((0.9, 8.4, 0), (0.05, 9.12, 0), 0.025, (0.3, 0.3, 0.3), segs=4)
        for x in (-1.1, 0.0, 1.1):
            cyl(0.04, 0.16, (x if x else 0.3, 9.33, 0), (0.55, 0.62, 0.55), segs=6)
        box2((-0.2, 6.45, -0.05), (0.2, 6.52, 0.05), (0.2, 0.2, 0.2))
        if tx:
            cyl(0.28, 0.9, (0, 7.6, 0.4), (0.55, 0.57, 0.58), segs=12, kind="Metal")
            box2((-0.05, 7.4, 0.05), (0.05, 7.5, 0.15), (0.3, 0.3, 0.3))
        if light:
            rod((0.1, 7.8, 0), (1.8, 8.2, 0), 0.04, (0.6, 0.62, 0.65), kind="Metal", segs=6)
            rbox((0.6, 0.14, 0.3), (2.0, 8.2, 0), (0.6, 0.62, 0.65), r=0.05, kind="Metal")
            box2((1.8, 8.11, -0.11), (2.2, 8.13, 0.11), (1.0, 0.95, 0.8), "Glow")
        box2((-0.1, 2.0, 0.12), (0.1, 2.35, 0.14), (0.9, 0.85, 0.3))    # pole tag
        finish(name)
    LAYOUT["props"]["pole_wires"] = [[-1.1, 9.43, 0.0], [0.3, 9.43, 0.0], [1.1, 9.43, 0.0], [0.0, 6.55, 0.0]]
    # trees
    random.seed(21)
    cyl(0.28, 3.4, (0, 1.7, 0), (0.38, 0.28, 0.2), segs=8, r2=0.2)
    rod((0, 2.8, 0), (1.0, 4.2, 0.3), 0.12, (0.38, 0.28, 0.2), segs=6)
    rod((0, 3.0, 0), (-0.9, 4.4, -0.4), 0.11, (0.38, 0.28, 0.2), segs=6)
    for k in range(11):
        a = k * 2.2
        r = 1.6 if k < 7 else 0.8
        y = 4.3 + (k % 3) * 0.7 + (0.9 if k >= 7 else 0)
        c = (0.2 + random.uniform(0, 0.08), 0.38 + random.uniform(0, 0.12), 0.14 + random.uniform(0, 0.05))
        ell((1.5, 1.15, 1.5), (math.cos(a) * r, y, math.sin(a) * r), c, segs=10, rings=6)
    finish("TreeOak")
    cyl(0.25, 2.0, (0, 1.0, 0), (0.35, 0.25, 0.18), segs=8)
    for k in range(5):
        y = 1.6 + k * 1.7
        rr = 3.0 - k * 0.55
        c = (0.1 + 0.02 * k, 0.28 + 0.03 * k, 0.16)
        cyl(rr, 2.6, (0, y + 1.1, 0), c, segs=12, r2=0.15)
    finish("TreePine")
    cyl(0.14, 2.2, (0, 1.1, 0), (0.42, 0.32, 0.22), segs=6)
    for k in range(6):
        a = k * 1.9
        ell((0.95, 0.85, 0.95), (math.cos(a) * 0.6, 2.6 + (k % 2) * 0.5, math.sin(a) * 0.6),
            (0.3 + 0.03 * (k % 3), 0.5 + 0.04 * (k % 2), 0.18), segs=8, rings=5)
    finish("TreeSmall")
    for name, base in (("Bush", (0.18, 0.4, 0.16)), ("BushDark", (0.12, 0.3, 0.14)), ("BushFlower", (0.22, 0.42, 0.18))):
        for k in range(4):
            a = k * 1.7
            ell((0.5, 0.42, 0.5), (math.cos(a) * 0.3, 0.38 + (k % 2) * 0.12, math.sin(a) * 0.22),
                [c + 0.03 * (k % 2) for c in base], segs=8, rings=5)
        if name == "BushFlower":
            for k in range(10):
                a = k * 0.9
                ell((0.07, 0.07, 0.07), (math.cos(a) * 0.45, 0.55 + (k % 3) * 0.12, math.sin(a) * 0.3),
                    (0.95, 0.4 + (k % 2) * 0.4, 0.6 if k % 3 else 0.2), segs=5, rings=3)
        finish(name)
    # FOR SALE yard sign (hanging board, faces +z)
    box2((-0.55, 0.0, -0.04), (-0.47, 1.6, 0.04), (0.95, 0.95, 0.93))
    box2((-0.55, 1.5, -0.04), (0.55, 1.58, 0.04), (0.95, 0.95, 0.93))
    for x in (-0.35, 0.35):
        rod((x, 1.5, 0), (x, 1.36, 0), 0.008, (0.4, 0.4, 0.42), segs=4, kind="Metal")
    box2((-0.46, 0.8, -0.02), (0.46, 1.36, 0.02), (0.97, 0.97, 0.95))
    box2((-0.46, 1.26, -0.025), (0.46, 1.36, 0.025), (0.78, 0.08, 0.1))
    box2((-0.46, 0.8, -0.025), (0.46, 0.86, 0.025), (0.78, 0.08, 0.1))
    box2((-0.3, 1.6, -0.02), (0.3, 1.8, 0.02), (0.78, 0.08, 0.1))      # rider on top
    finish("ForSaleSign")
    # taxi / rideshare stand: a small shelter, bench, and a sign pole
    for x in (-1.5, 1.5):
        box2((x - 0.05, 0.0, -0.75), (x + 0.05, 2.5, -0.65), (0.25, 0.27, 0.3), "Metal")
    box2((-1.7, 2.5, -1.0), (1.7, 2.62, 0.4), (0.22, 0.24, 0.27), "Metal")
    box2((-1.6, 2.44, -0.95), (1.6, 2.5, 0.35), (1.0, 0.85, 0.2), "Glow")
    box2((-1.45, 0.4, -0.72), (1.45, 2.4, -0.68), (0.7, 0.8, 0.85), "Glass")
    box2((-1.3, 0.45, -0.6), (1.3, 0.5, -0.25), (0.55, 0.4, 0.25))
    for x in (-1.1, 1.1):
        box2((x - 0.04, 0.0, -0.5), (x + 0.04, 0.45, -0.4), (0.25, 0.27, 0.3), "Metal")
    cyl(0.05, 3.0, (1.9, 1.5, 0.2), (0.25, 0.27, 0.3), segs=8, kind="Metal")
    box2((1.6, 2.6, 0.17), (2.2, 3.05, 0.23), (1.0, 0.8, 0.05), "Glow")
    finish("TaxiStand")
    # stop sign + street-name sign post
    cyl(0.035, 2.6, (0, 1.3, 0), (0.6, 0.62, 0.65), segs=6, kind="Metal")
    cyl(0.38, 0.03, (0, 2.3, 0.04), (0.95, 0.95, 0.95), segs=8, rot=[("x", math.pi / 2), ("z", math.pi / 8)])
    cyl(0.34, 0.035, (0, 2.3, 0.045), (0.78, 0.06, 0.06), segs=8, rot=[("x", math.pi / 2), ("z", math.pi / 8)])
    finish("StopSign")
    cyl(0.035, 3.0, (0, 1.5, 0), (0.6, 0.62, 0.65), segs=6, kind="Metal")
    box2((-0.6, 2.75, -0.02), (0.6, 2.95, 0.02), (0.1, 0.42, 0.22))
    box2((-0.02, 2.5, -0.6), (0.02, 2.7, 0.6), (0.1, 0.42, 0.22))
    finish("StreetSign")
    # backyard stuff: a kettle grill, lawn chairs, AC condenser, a doghouse, kid's bike
    ell((0.3, 0.25, 0.3), (0, 0.85, 0), BLACK, segs=10, rings=6, kind="Gloss")
    for k in range(3):
        a = k * 2.1
        rod((0, 0.7, 0), (math.cos(a) * 0.3, 0.0, math.sin(a) * 0.3), 0.015, (0.4, 0.4, 0.4), segs=4, kind="Metal")
    finish("Grill")
    box2((-0.3, 0.35, -0.3), (0.3, 0.4, 0.25), (0.95, 0.95, 0.93))
    box2((-0.3, 0.4, -0.32), (0.3, 0.95, -0.27), (0.95, 0.95, 0.93))
    for sx in (-0.27, 0.27):
        for sz in (-0.27, 0.22):
            box2((sx - 0.02, 0.0, sz - 0.02), (sx + 0.02, 0.36, sz + 0.02), (0.9, 0.9, 0.88))
    finish("LawnChair")
    box2((-0.45, 0.0, -0.55), (0.45, 0.65, 0.45), (0.65, 0.35, 0.2))
    extrude_x([(-0.55, 0.65), (0.55, 0.65), (0.0, 1.05)], -0.6, 0.55, (0.55, 0.2, 0.15))
    box2((-0.2, 0.05, 0.44), (0.2, 0.45, 0.46), VOID)
    finish("Doghouse")
    for z in (-0.5, 0.5):
        cyl(0.3, 0.04, (0, 0.3, z), BLACK, segs=12, rot=[("z", math.pi / 2)])
    rod((0, 0.3, -0.5), (0, 0.6, 0.0), 0.02, (0.85, 0.15, 0.2), segs=4)
    rod((0, 0.6, 0.0), (0, 0.3, 0.5), 0.02, (0.85, 0.15, 0.2), segs=4)
    rod((0, 0.6, 0.0), (0, 0.8, 0.45), 0.02, (0.85, 0.15, 0.2), segs=4)
    box2((-0.25, 0.8, 0.43), (0.25, 0.83, 0.47), BLACK)
    finish("KidBike")
    # highway: double-arm light pole (arms along x), sits on the median barrier
    cyl(0.18, 12.0, (0, 6.0, 0), (0.6, 0.62, 0.65), segs=8, r2=0.12, kind="Metal")
    for s in (-1, 1):
        rod((0, 11.6, 0), (s * 3.2, 12.2, 0), 0.07, (0.6, 0.62, 0.65), kind="Metal", segs=6)
        rbox((0.8, 0.18, 0.35), (s * 3.5, 12.15, 0), (0.55, 0.57, 0.6), r=0.05, kind="Metal")
        box2((s * 3.5 - 0.3, 12.04, -0.12), (s * 3.5 + 0.3, 12.06, 0.12), (1.0, 0.94, 0.78), "Glow")
    finish("HwyLight")
    # brick entrance monument for the neighborhood (text by Godot)
    box2((-2.4, 0.0, -0.35), (2.4, 1.3, 0.35), BRICK)
    box2((-2.5, 1.3, -0.42), (2.5, 1.42, 0.42), CONC)
    box2((-1.9, 0.35, 0.35), (1.9, 1.05, 0.38), (0.92, 0.9, 0.84))
    for x in (-2.6, 2.6):
        box2((x - 0.3, 0.0, -0.4), (x + 0.3, 1.7, 0.4), BRICK)
        box2((x - 0.36, 1.7, -0.46), (x + 0.36, 1.8, 0.46), CONC)
        ell((0.18, 0.18, 0.18), (x, 1.95, 0), CONC, segs=8, rings=5)
    finish("HoodMonument")


# ============================================================================ main

SPECS = {}


def main():
    reset()
    for fn in (house_ranch, house_shotgun, house_bungalow, house_tin):
        fn()
    # the Spec objects are needed by the interiors: rebuild them quietly (data only)
    door_leaf("Door_White", (0.95, 0.95, 0.93), "panel")
    door_leaf("Door_Red", (0.62, 0.1, 0.08), "panel")
    door_leaf("Door_Wood", (0.52, 0.34, 0.2), "glass")
    door_leaf("Door_Blue", (0.18, 0.28, 0.45), "glass")
    screen_door()
    interiors()
    yard_props()
    with open(LAYOUT_OUT, "w") as f:
        json.dump(LAYOUT, f, indent=1, sort_keys=True)
    export(OUT)


_orig_dump = Spec.dump


def _dump_and_keep(self, *a, **k):
    SPECS[self.name] = self
    return _orig_dump(self, *a, **k)


Spec.dump = _dump_and_keep

if __name__ == "__main__":
    main()
