"""BAGHOLDERS BEMZE kit — drivable parody-BMW cars + the BEMZE dealership, built in Blender (bpy).

Run:  python3 tools/blender/build_bemze.py                     (needs `pip install bpy==4.5.*`)
      BEMZE_REF_JSON=/tmp/bemze_ref.json python3 tools/blender/build_bemze.py   (+ reference points JSON)
      python3 tools/blender/build_bemze.py --only Bemze_M3,Bemze_M3_Wheel      (subset, for quick looks)
Out:  assets/props/bemze_kit.glb

Same conventions as build_props.py / build_watches.py (PropKit loads it the same way): each prop is ONE
mesh whose surfaces share a handful of materials, colors are baked as vertex colors holding sRGB values,
and coordinates are written in GODOT space (x right, y up, -z forward) and converted to Blender
(x, -z, y) on the way in.

  CarPaint  the body paint: WHITE vertex colors, the game tints it per car (material override /
            albedo_color). PropKit: glossy clear coat (roughness ~0.2, metallic ~0.35).
  Paint     matte (tires, plastics, leather)      Gloss  shiny black trim, piano black, lenses
  Metal     chrome, rims, brake discs             Glow   unshaded: head/tail lights, screens, LED rings
  Glass     see-through tinted windows (the interior is visible through them)

All brands are parodies (docs/BRANDS.md): BMW -> BEMZE. The roundel is a quartered ORANGE / WHITE disc in
a black ring (not the BMW roundel); "BEMZE" lettering where the real car has a badge.

CARS (real dimensions, metres; see SPECS). Every car is four props:
  Bemze_<M>             body shell + glass + lights + interior. Origin: ground, centred between the axles
                        in x and z; the car faces -Z (front at -z), driver on the LEFT (-x, left-hand drive).
                        NO wheels, NO steering wheel.
  Bemze_<M>_Wheel       one wheel (tire + rim + disc + caliper), origin = hub centre, axle along X, the rim
                        face at +X (right side). Mirror (scale.x = -1) for the left side.
  Bemze_SteeringWheel   shared M-style wheel, origin = hub, rim in the XY plane facing +Z (the driver);
                        tilt it with rotation.x = +column_tilt (REF) so it faces up/back along the column.
Reference points (wheel centres, eye, steering hub, lights, exhausts, collision box, door handle, plates)
are printed and written to $BEMZE_REF_JSON.

DEALERSHIP (origin on the floor, front = +Z): Dealer_Showroom, Dealer_Turntable, Dealer_Pylon,
Dealer_LotLight, Dealer_Flag, Dealer_Desk, Dealer_KeyBox.
"""
import json
import math
import os
import sys

import bpy  # noqa: I001  (bpy must be imported before bmesh/mathutils)
import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "props", "bemze_kit.glb")
TAU = 2 * math.pi

PARTS = []   # parts of the prop being built
STATS = {}   # triangle budget by section (printed with --stats)
TAG = ["-"]
KIT = []     # finished props
REF = {}     # prop name -> {point name: value}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ----------------------------------------------------------------------------- materials / emit

KINDS = ("CarPaint", "Paint", "Gloss", "Metal", "Glow", "Glass")
MATS = {}


def mat(kind):
    if kind not in MATS:
        m = bpy.data.materials.new(kind)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        vc = m.node_tree.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Col"
        m.node_tree.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
        if kind == "Glass":   # exported as a blended material; PropKit swaps in its own anyway
            bsdf.inputs["Alpha"].default_value = 0.15
            bsdf.inputs["Roughness"].default_value = 0.05
            m.surface_render_method = "BLENDED"
        if kind == "CarPaint":
            bsdf.inputs["Roughness"].default_value = 0.2
            bsdf.inputs["Metallic"].default_value = 0.35
        MATS[kind] = m
    return MATS[kind]


R3 = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))   # Godot (x, y, z) -> Blender (x, -z, y)
R4 = R3.to_4x4()


def V(*a):
    return Vector(a[0] if len(a) == 1 else a)


def T(pos=(0, 0, 0), rot=None, scale=None):
    """Godot-space transform: scale, then rotations [(axis, radians), ...] in order, then translate."""
    m = Matrix.Identity(4)
    if scale is not None:
        s = scale if isinstance(scale, (tuple, list)) else (scale, scale, scale)
        m = Matrix.Diagonal((s[0], s[1], s[2], 1.0))
    for ax, a in rot or []:
        m = Matrix.Rotation(a, 4, ax.upper()) @ m
    return Matrix.Translation(Vector(pos)) @ m


def _sharpen(bm, angle):
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0) > angle:
            e.smooth = False


def emit(bm, col, kind="Paint", M=None, smooth=True, sharp=0.6, recalc=True):
    """Finish a Godot-space bmesh into a part. col: rgb tuple, per-face list, or callable(center, normal)."""
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    if isinstance(col, list):
        cols = col
    elif callable(col):
        cols = [col(f.calc_center_median(), f.normal.copy()) for f in bm.faces]
    else:
        cols = None
    if M is not None:
        bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
        if M.to_3x3().determinant() < 0:
            bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bmesh.ops.transform(bm, matrix=R4, verts=bm.verts)
    bm.normal_update()
    if smooth:
        _sharpen(bm, sharp)
    me = bpy.data.meshes.new("part")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("part", me)
    bpy.context.scene.collection.objects.link(ob)
    if not smooth:
        for e in me.edges:
            e.use_edge_sharp = True
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    a = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    buf = [0.0] * (len(me.loops) * 4)
    for p in me.polygons:
        c = cols[p.index] if cols is not None else col
        for li in p.loop_indices:
            j = li * 4
            buf[j] = c[0]
            buf[j + 1] = c[1]
            buf[j + 2] = c[2]
            buf[j + 3] = 1.0
    a.data.foreach_set("color", buf)
    me.color_attributes.active_color = a
    me.materials.append(mat(kind))
    PARTS.append(ob)
    STATS[TAG[0]] = STATS.get(TAG[0], 0) + sum(len(p.vertices) - 2 for p in me.polygons)
    return ob


def xform_parts(n0, M):
    """Apply a Godot-space transform to every part emitted since PARTS had n0 entries."""
    Mb = R4 @ M @ R4.inverted()
    for ob in PARTS[n0:]:
        ob.data.transform(Mb)


def tag(t):
    TAG[0] = t


def finish(name):
    """Join the parts into one prop mesh with soft 'weighted' normals."""
    global PARTS
    obs = PARTS
    PARTS = []
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    ob.data.color_attributes.active_color = ob.data.color_attributes["Col"]
    wn = ob.modifiers.new("wn", "WEIGHTED_NORMAL")
    wn.mode = "FACE_AREA"
    wn.keep_sharp = True
    wn.weight = 50
    KIT.append(ob)
    return ob


# ----------------------------------------------------------------------------- palette-classed meshes

PAL = []      # class id -> (rgb, kind)
_PAL_IDX = {}


def cls(col, kind="Paint"):
    key = (tuple(round(c, 4) for c in col), kind)
    if key not in _PAL_IDX:
        _PAL_IDX[key] = len(PAL)
        PAL.append((tuple(col), kind))
    return _PAL_IDX[key]


class Mesher:
    """A bmesh built face by face (Godot space), each face tagged with a palette class. Vertices are
    shared by position, so rings that collapse onto a centre line close up cleanly."""

    def __init__(self):
        self.bm = bmesh.new()
        self.cache = {}
        self.layer = self.bm.faces.layers.int.new("cls")

    def v(self, p):
        key = (round(p[0], 5), round(p[1], 5), round(p[2], 5))
        vt = self.cache.get(key)
        if vt is None:
            vt = self.bm.verts.new(Vector(p))
            self.cache[key] = vt
        return vt

    def face(self, pts, c):
        vs = []
        for p in pts:
            vt = self.v(p)
            if vt not in vs:
                vs.append(vt)
        if len(vs) < 3:
            return None
        if len(vs) == 3:
            a, b, d = (x.co for x in vs)
            if (b - a).cross(d - a).length < 1e-9:
                return None
        try:
            f = self.bm.faces.new(vs)
        except ValueError:
            return None
        f[self.layer] = c
        return f

    def loft(self, rings, cfn, closed=True):
        """rings: list of equal-length point lists; cfn(k, i) -> class of the face between ring k/k+1 and
        points i/i+1. Face order (a_i, a_j, b_j, b_i): outward when rings advance along +z and each ring
        runs counter-clockwise seen from the front (x right, y up)."""
        n = len(rings[0])
        for k in range(len(rings) - 1):
            a, b = rings[k], rings[k + 1]
            for i in range(n if closed else n - 1):
                j = (i + 1) % n
                c = cfn(k, i)
                if c is None:
                    continue
                self.face((a[i], a[j], b[j], b[i]), c)

    def recolor(self, fn, kind="Gloss"):
        """Replace the CarPaint class by fn(face centre, face normal) -> rgb (a baked livery)."""
        self.bm.normal_update()
        for f in self.bm.faces:
            if PAL[f[self.layer]][1] == "CarPaint":
                f[self.layer] = cls(fn(f.calc_center_median(), f.normal), kind)

    def emit(self, smooth=True, sharp=0.6, M=None):
        """Split by material kind and emit one part per kind (colors from the palette classes)."""
        bm = self.bm
        kinds = {}
        for f in bm.faces:
            kinds.setdefault(PAL[f[self.layer]][1], True)
        out = []
        for kind in kinds:
            b2 = bm.copy()
            lay = b2.faces.layers.int.get("cls")
            dead = [f for f in b2.faces if PAL[f[lay]][1] != kind]
            if dead:
                bmesh.ops.delete(b2, geom=dead, context="FACES")
            cols = [PAL[f[lay]][0] for f in b2.faces]
            out.append(emit(b2, cols, kind, M=M, smooth=smooth, sharp=sharp, recalc=False))
        bm.free()
        return out


# ----------------------------------------------------------------------------- primitives (Godot space)

def box_bm(sx, sy, sz, r=0.0, seg=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz))
    if r > 0:
        r = min(r, 0.49 * min(sx, sy, sz))
        bmesh.ops.bevel(bm, geom=list(bm.verts) + list(bm.edges), offset=r, offset_type="OFFSET",
                        segments=seg, profile=0.5, affect="EDGES", clamp_overlap=True)
    return bm


def box(size, col, kind="Paint", pos=(0, 0, 0), rot=None, r=0.0, seg=2, M=None, smooth=True, sharp=0.6):
    Mx = (M if M is not None else Matrix.Identity(4)) @ T(pos, rot)
    return emit(box_bm(size[0], size[1], size[2], r, seg), col, kind, Mx, smooth, sharp)


def revolve_bm(profile, segs, closed=False, phase=0.0, arc=TAU):
    """Surface of revolution around Y. profile [(r, y), ...] with the outside on the RIGHT when walking it."""
    bm = bmesh.new()
    full = arc >= TAU - 1e-6
    n = segs if full else segs + 1
    rings = []
    for r, y in profile:
        if r < 1e-9:
            rings.append([bm.verts.new((0, y, 0))])
            continue
        rings.append([bm.verts.new((r * math.sin(arc * i / segs + phase), y, -r * math.cos(arc * i / segs + phase)))
                      for i in range(n)])
    pairs = list(range(len(rings) - 1))
    if closed:
        pairs.append(-1)
    for k in pairs:
        a, b = rings[k], rings[k + 1]
        if len(a) == 1 and len(b) == 1:
            continue
        for i in range(segs if full else n - 1):
            j = (i + 1) % n
            if len(a) == 1:
                bm.faces.new((a[0], b[i], b[j]))
            elif len(b) == 1:
                bm.faces.new((a[i], b[0], a[j]))
            else:
                bm.faces.new((a[i], b[i], b[j], a[j]))
    return bm


def revolve(profile, col, kind="Paint", segs=48, pos=(0, 0, 0), rot=None, closed=False, M=None,
            smooth=True, sharp=0.6, phase=0.0, arc=TAU, recalc=False):
    Mx = (M if M is not None else Matrix.Identity(4)) @ T(pos, rot)
    return emit(revolve_bm(profile, segs, closed, phase, arc), col, kind, Mx, smooth, sharp, recalc=recalc)


def cyl(r, h, col, kind="Paint", segs=24, pos=(0, 0, 0), rot=None, M=None, r2=None, bevel=0.0):
    """Cylinder along Y centred on pos (optional rounded top/bottom edges)."""
    r2 = r if r2 is None else r2
    y0, y1 = -h / 2, h / 2
    if bevel > 0:
        b = min(bevel, h / 2.2, r * 0.5)
        prof = [(0, y0), (r - b, y0), (r - b * 0.3, y0 + b * 0.3), (r, y0 + b), (r2, y1 - b),
                (r2 - b * 0.3, y1 - b * 0.3), (r2 - b, y1), (0, y1)]
    else:
        prof = [(0, y0), (r, y0), (r2, y1), (0, y1)]
    return revolve(prof, col, kind, segs, pos, rot, M=M)


def sphere(r, col, kind="Paint", pos=(0, 0, 0), segs=16, rings=10, scale=None, M=None, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    Mx = (M if M is not None else Matrix.Identity(4)) @ T(pos, rot, scale=scale)
    return emit(bm, col, kind, Mx)


def rod(a, b, r, col, kind="Paint", segs=10, M=None, r2=None):
    A, B = Vector(a), Vector(b)
    d = B - A
    r2 = r if r2 is None else r2
    bm = revolve_bm([(0, 0), (r, 0), (r2, d.length), (0, d.length)], segs)
    q = Vector((0, 1, 0)).rotation_difference(d.normalized())
    Mx = (M if M is not None else Matrix.Identity(4)) @ Matrix.Translation(A) @ q.to_matrix().to_4x4()
    return emit(bm, col, kind, Mx)


def torus(R, r, col, kind="Paint", segs=32, rsegs=10, pos=(0, 0, 0), rot=None, M=None, arc=TAU):
    prof = [(R + r * math.cos(TAU * j / rsegs), r * math.sin(TAU * j / rsegs)) for j in range(rsegs)]
    Mx = (M if M is not None else Matrix.Identity(4)) @ T(pos, rot)
    return emit(revolve_bm(prof, segs, closed=True, arc=arc), col, kind, Mx, recalc=False)


def _ccw(pts):
    """Counter-clockwise in the (a, b) plane."""
    s = 0.0
    for i in range(len(pts)):
        a0, b0 = pts[i]
        a1, b1 = pts[(i + 1) % len(pts)]
        s += a0 * b1 - a1 * b0
    return list(pts) if s > 0 else list(reversed(pts))


def prism_bm(poly, a0, a1, axis="z", bevel=0.0, seg=2):
    """2D outline extruded along a Godot axis from a0 to a1 (edges optionally rounded).
    axis "z": poly (x, y);  "x": poly (z, y);  "y": poly (x, z)."""
    def P(u, v, a):
        return {"x": (a, v, u), "z": (u, v, a), "y": (u, a, v)}[axis]
    pts = list(poly)
    bm = bmesh.new()
    lo = [bm.verts.new(P(u, v, a0)) for u, v in pts]
    hi = [bm.verts.new(P(u, v, a1)) for u, v in pts]
    bm.faces.new(lo)
    bm.faces.new(hi)
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.verts) + list(bm.edges), offset=bevel, offset_type="OFFSET",
                        segments=seg, profile=0.5, affect="EDGES", clamp_overlap=True)
    return bm


def prism(poly, a0, a1, col, kind="Paint", axis="z", bevel=0.0, seg=2, M=None, smooth=True, sharp=0.6):
    return emit(prism_bm(poly, a0, a1, axis, bevel, seg), col, kind, M, smooth, sharp)


def loft_bm(rings, cap0=True, cap1=True, closed=True):
    bm = bmesh.new()
    vr = [[bm.verts.new(p) for p in ring] for ring in rings]
    n = len(rings[0])
    for k in range(len(vr) - 1):
        a, b = vr[k], vr[k + 1]
        for i in range(n if closed else n - 1):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap0 and closed:
        bm.faces.new(list(reversed(vr[0])))
    if cap1 and closed:
        bm.faces.new(vr[-1])
    return bm


# ----------------------------------------------------------------------------- 2D outlines / curves

def lerp(a, b, t):
    return a + (b - a) * t


def smooth01(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def curve(pts):
    """Monotone cubic (PCHIP) through [(x, y), ...], clamped outside the range."""
    pts = sorted(pts)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    n = len(pts)
    if n == 1:
        return lambda x: ys[0]
    d = [(ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) for i in range(n - 1)]
    m = [0.0] * n
    m[0], m[-1] = d[0], d[-1]
    for i in range(1, n - 1):
        if d[i - 1] * d[i] <= 0:
            m[i] = 0.0
        else:
            w1 = 2 * (xs[i + 1] - xs[i]) + (xs[i] - xs[i - 1])
            w2 = (xs[i + 1] - xs[i]) + 2 * (xs[i] - xs[i - 1])
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])

    def f(x):
        if x <= xs[0]:
            return ys[0]
        if x >= xs[-1]:
            return ys[-1]
        lo, hi = 0, n - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if xs[mid] <= x:
                lo = mid
            else:
                hi = mid
        h = xs[hi] - xs[lo]
        t = (x - xs[lo]) / h
        h00 = 2 * t ** 3 - 3 * t ** 2 + 1
        h10 = t ** 3 - 2 * t ** 2 + t
        h01 = -2 * t ** 3 + 3 * t ** 2
        h11 = t ** 3 - t ** 2
        return h00 * ys[lo] + h10 * h * m[lo] + h01 * ys[hi] + h11 * h * m[hi]
    return f


def round_poly(pts, r, per=5):
    """Polygon with every corner replaced by a tangent arc of radius r (float or per-corner list)."""
    n = len(pts)
    rs = r if isinstance(r, (list, tuple)) else [r] * n
    out = []
    for i in range(n):
        p0 = Vector(pts[i - 1])
        p1 = Vector(pts[i])
        p2 = Vector(pts[(i + 1) % n])
        ri = rs[i]
        a = (p0 - p1)
        b = (p2 - p1)
        if ri <= 1e-6 or a.length < 1e-6 or b.length < 1e-6:
            out.append((p1.x, p1.y))
            continue
        a.normalize()
        b.normalize()
        ang = math.acos(max(-1.0, min(1.0, a.dot(b))))
        if ang < 1e-3 or ang > math.pi - 1e-3:
            out.append((p1.x, p1.y))
            continue
        d = ri / math.tan(ang / 2)
        d = min(d, 0.49 * (Vector(pts[i - 1]) - p1).length, 0.49 * (p2 - p1).length)
        ri = d * math.tan(ang / 2)
        s = p1 + a * d
        e = p1 + b * d
        bis = (a + b).normalized()
        c = p1 + bis * (ri / math.sin(ang / 2))
        a0 = math.atan2(s.y - c.y, s.x - c.x)
        a1 = math.atan2(e.y - c.y, e.x - c.x)
        da = a1 - a0
        while da > math.pi:
            da -= TAU
        while da < -math.pi:
            da += TAU
        for k in range(per + 1):
            t = a0 + da * k / per
            out.append((c.x + ri * math.cos(t), c.y + ri * math.sin(t)))
    return out


def resample(pts, step, closed=True):
    """Insert points so no edge is longer than `step`."""
    out = []
    n = len(pts)
    for i in range(n if closed else n - 1):
        a = Vector(pts[i])
        b = Vector(pts[(i + 1) % n])
        k = max(1, int(math.ceil((b - a).length / step)))
        for j in range(k):
            p = a.lerp(b, j / k)
            out.append((p.x, p.y))
    if not closed:
        out.append(tuple(pts[-1]))
    return out


def offset_poly(pts, d):
    """Offset a CCW polygon outward by d (negative = inward), mitred."""
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        e0 = (p1 - p0)
        e1 = (p2 - p1)
        if e0.length < 1e-9:
            e0 = e1
        if e1.length < 1e-9:
            e1 = e0
        n0 = Vector((e0.y, -e0.x)).normalized()
        n1 = Vector((e1.y, -e1.x)).normalized()
        m = (n0 + n1)
        if m.length < 1e-6:
            m = n0
        m.normalize()
        c = max(0.35, m.dot(n1))
        q = p1 + m * (d / c)
        out.append((q.x, q.y))
    return out


def ellipse(cx, cy, rx, ry, n=24, phase=0.0):
    return [(cx + rx * math.cos(phase + TAU * i / n), cy + ry * math.sin(phase + TAU * i / n)) for i in range(n)]


def poly_area(pts):
    s = 0.0
    for i in range(len(pts)):
        a0, b0 = pts[i]
        a1, b1 = pts[(i + 1) % len(pts)]
        s += a0 * b1 - a1 * b0
    return s / 2


def centroid(pts):
    ax = sum(p[0] for p in pts) / len(pts)
    ay = sum(p[1] for p in pts) / len(pts)
    return (ax, ay)


# ----------------------------------------------------------------------------- text

FONT_FILES = {
    "sans": "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "sansi": "/usr/share/fonts/truetype/liberation/LiberationSans-BoldItalic.ttf",
    "serif": "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf",
}
_FONTS = {}


def font(key):
    if key not in _FONTS:
        path = FONT_FILES.get(key)
        _FONTS[key] = bpy.data.fonts.load(path, check_existing=True) if path and os.path.exists(path) else None
    return _FONTS[key]


def text2d(s, size, fnt="sans", spacing=1.0, stretch=1.0, align="CENTER"):
    """Flat glyph triangles: (verts [(u, v)], faces [(i, j, k)]) in viewer coordinates (u right, v up)."""
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = s
    f = font(fnt)
    if f is not None:
        cu.font = f
    cu.size = size
    cu.space_character = spacing
    cu.align_x = align
    cu.align_y = "CENTER"
    cu.resolution_u = 2
    ob = bpy.data.objects.new("txt", cu)
    bpy.context.scene.collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    verts = [(v.co.x * stretch, v.co.y) for v in bm.verts]
    bm.verts.index_update()
    faces = []
    for fc in bm.faces:
        idx = [v.index for v in fc.verts]
        if fc.normal.z < 0:
            idx.reverse()
        faces.append(tuple(idx))
    bm.free()
    return verts, faces


# ----------------------------------------------------------------------------- surface projection (decals)

class Surface:
    """Ray-projects flat 2D artwork onto a Godot-space bmesh (the car body) — lights, grilles, badges,
    panel gaps and vents follow the curved panels exactly."""

    VIEWS = {   # (dir the ray travels, a-axis, b-axis) ; artwork coords (a, b) are car coordinates
        "front": ((0, 0, 1), (1, 0, 0), (0, 1, 0)),
        "rear": ((0, 0, -1), (1, 0, 0), (0, 1, 0)),
        "right": ((-1, 0, 0), (0, 0, 1), (0, 1, 0)),
        "left": ((1, 0, 0), (0, 0, 1), (0, 1, 0)),
        "top": ((0, -1, 0), (1, 0, 0), (0, 0, 1)),
        "bottom": ((0, 1, 0), (1, 0, 0), (0, 0, 1)),
    }

    def __init__(self, bms):
        verts, polys = [], []
        for bm in bms:
            off = len(verts)
            bm.verts.index_update()
            verts.extend(v.co.copy() for v in bm.verts)
            polys.extend([tuple(off + v.index for v in f.verts) for f in bm.faces])
        self.tree = BVHTree.FromPolygons(verts, polys)

    @staticmethod
    def view(v):
        if isinstance(v, str):
            d, a, b = Surface.VIEWS[v]
            return Vector(d), Vector(a), Vector(b)
        d = Vector(v[0]).normalized()
        a = Vector(v[1]).normalized()
        b = d.cross(a).normalized() * -1 if len(v) < 3 else Vector(v[2]).normalized()
        return d, a, b

    def hit(self, a, b, view, depth=0.0):
        d, A, B = self.view(view)
        o = A * a + B * b - d * 20.0
        loc, nor, _i, _dist = self.tree.ray_cast(o, d, 60.0)
        if loc is None:
            return None, None
        if nor.dot(d) > 0:
            nor = -nor
        return loc, nor

    def decal(self, poly, view, col, kind="Paint", lift=0.004, rings=4, step=0.03, skirt=True, mirror=False,
              center=None, base=-0.004, M_out=None, lift_fn=None):
        """Filled polygon (car-plane coords of the view) projected onto the surface and lifted by `lift`.
        lift_fn(ring_frac) -> extra lift (domes lenses / pillow shapes)."""
        pts = resample(_ccw(poly), step)
        c = Vector(center if center is not None else centroid(pts))
        ringsp = []
        fr = [1.0 - k / rings for k in range(rings)]
        for f in fr:
            ringsp.append([(c.x + (p[0] - c.x) * f, c.y + (p[1] - c.y) * f) for p in pts])
        verts2 = [p for r in ringsp for p in r] + [(c.x, c.y)]
        n = len(pts)
        faces = []
        for k in range(rings - 1):
            for i in range(n):
                j = (i + 1) % n
                faces.append((k * n + i, k * n + j, (k + 1) * n + j, (k + 1) * n + i))
        cidx = len(verts2) - 1
        for i in range(n):
            j = (i + 1) % n
            faces.append(((rings - 1) * n + i, (rings - 1) * n + j, cidx))
        lifts = [lift + (lift_fn(1 - f) if lift_fn else 0.0) for f in fr for _ in range(n)]
        lifts.append(lift + (lift_fn(1.0) if lift_fn else 0.0))
        return self.project(verts2, faces, view, col, kind, lifts, outline=list(range(n)) if skirt else None,
                            base=base, mirror=mirror)

    def frame(self, outer, inner, view, col, kind="Gloss", lift=0.01, base=-0.004, mirror=False, step=0.03):
        """A ring between two outlines with the same point count (grille surrounds, light bezels)."""
        o = _ccw(outer)
        i_ = _ccw(inner)
        n = len(o)
        verts2 = o + i_
        faces = []
        for i in range(n):
            j = (i + 1) % n
            faces.append((i, j, n + j, n + i))
        lifts = [lift] * (2 * n)
        return self.project(verts2, faces, view, col, kind, lifts, outline=list(range(n)),
                            inner_outline=list(range(n, 2 * n)), base=base, mirror=mirror)

    def line(self, pts, width, view, col, kind="Paint", lift=0.0025, step=0.03, mirror=False, closed=False):
        """A thin strip along a polyline (panel gaps, trim lines)."""
        P = resample(pts, step, closed=closed)
        n = len(P)
        L, R = [], []
        for i in range(n):
            p0 = Vector(P[i - 1] if (i > 0 or closed) else P[i])
            p1 = Vector(P[(i + 1) % n] if (i < n - 1 or closed) else P[i])
            t = (p1 - p0)
            if t.length < 1e-9:
                t = Vector((1, 0))
            t.normalize()
            nn = Vector((-t.y, t.x)) * (width / 2)
            L.append((P[i][0] + nn.x, P[i][1] + nn.y))
            R.append((P[i][0] - nn.x, P[i][1] - nn.y))
        verts2 = L + R
        faces = []
        for i in range(n if closed else n - 1):
            j = (i + 1) % n
            faces.append((i, j, n + j, n + i))
        return self.project(verts2, faces, view, col, kind, [lift] * (2 * n), outline=None, mirror=mirror)

    def text(self, s, size, view, center, col, kind="Metal", lift=0.003, fnt="sans", stretch=1.0, spacing=1.0,
             rot=0.0):
        """Lettering that reads correctly for someone looking along the view direction."""
        vs, fs = text2d(s, size, fnt, spacing, stretch)
        d, A, B = self.view(view)
        right = d.cross(B)          # viewer's right-hand direction in world space
        sgn = 1.0 if right.dot(A) > 0 else -1.0
        cr, sr = math.cos(rot), math.sin(rot)
        verts2 = []
        for u, v in vs:
            u2, v2 = u * cr - v * sr, u * sr + v * cr
            verts2.append((center[0] + sgn * u2, center[1] + v2))
        return self.project(verts2, fs, view, col, kind, [lift] * len(verts2), outline=None, orient_check=True)

    def project(self, verts2, faces, view, col, kind, lifts, outline=None, inner_outline=None, base=-0.004,
                mirror=False, orient_check=True, graze=0.28):
        d, A, B = self.view(view)
        top = []
        bot = []
        ok = []
        for (a, b), lf in zip(verts2, lifts):
            loc, nor = self.hit(a, b, view)
            if loc is not None and abs(nor.dot(d)) < graze:     # grazing hit: would smear along the panel
                loc = None
            if loc is None:
                ok.append(False)
                top.append(None)
                bot.append(None)
                continue
            ok.append(True)
            top.append(loc + nor * lf)
            bot.append(loc + nor * base)
        bm = bmesh.new()
        vt = [bm.verts.new(p) if p is not None else None for p in top]
        made = []
        for f in faces:
            if not all(ok[i] for i in f):
                continue
            try:
                made.append(bm.faces.new([vt[i] for i in f]))
            except ValueError:
                pass
        if not made:
            bm.free()
            return None
        bm.normal_update()
        # faces must look back at the viewer (-d)
        if orient_check:
            s = sum(f.normal.dot(-d) * f.calc_area() for f in made)
            if s < 0:
                bmesh.ops.reverse_faces(bm, faces=made)
                flip = True
            else:
                flip = False
        else:
            flip = False
        for ol, inner in ((outline, False), (inner_outline, True)):
            if not ol:
                continue
            vb = [bm.verts.new(bot[i]) if ok[i] else None for i in ol]
            m = len(ol)
            for k in range(m):
                j = (k + 1) % m
                i0, i1 = ol[k], ol[j]
                if not (ok[i0] and ok[i1]):
                    continue
                quad = [vb[k], vb[j], vt[i1], vt[i0]]
                if flip != inner:
                    quad.reverse()
                try:
                    bm.faces.new(quad)
                except ValueError:
                    pass
        bm2 = None
        if mirror:
            bm2 = bm.copy()
            bmesh.ops.transform(bm2, matrix=Matrix.Diagonal((-1, 1, 1, 1)), verts=bm2.verts)
            bmesh.ops.reverse_faces(bm2, faces=bm2.faces)
        emit(bm, col, kind, recalc=False, sharp=0.5)
        if bm2 is not None:
            emit(bm2, col, kind, recalc=False, sharp=0.5)
        return True


# ----------------------------------------------------------------------------- palette

WHITE = (1.0, 1.0, 1.0)               # CarPaint: tinted per car by the game
BLACK = (0.035, 0.035, 0.04)          # matte black plastic
PIANO = (0.03, 0.03, 0.035)           # gloss black trim (Shadowline)
DARK = (0.055, 0.055, 0.06)
WELL = (0.03, 0.03, 0.032)
CHROME = (0.8, 0.82, 0.85)
ALU = (0.62, 0.64, 0.67)
GUN = (0.22, 0.23, 0.25)              # gunmetal
GLASS = (0.16, 0.19, 0.22)
GLASS_IN = (0.3, 0.33, 0.36)
CARBON = (0.1, 0.105, 0.115)
HEADLINER = (0.24, 0.24, 0.25)
LAMP_W = (0.95, 0.97, 1.0)
LAMP_BLUE = (0.55, 0.75, 1.0)
TAIL = (0.42, 0.03, 0.04)             # dim red (brake glow = the game brightens it)
TAIL_HI = (0.85, 0.08, 0.08)
TAIL_DARK = (0.16, 0.02, 0.025)
ORANGE = (1.0, 0.45, 0.05)
PLATE = (0.93, 0.93, 0.9)


# ----------------------------------------------------------------------------- the car body engine
#
# A car is a lofted shell: cross-section rings along z (front -> rear). Each ring is the right half from the
# underbody centre up the side to the roof/hood centre, mirrored for the left. Wheel arches are notches in the
# rings (the side stops at the arch curve, a well ceiling runs in to the inner well wall), the cabin is an
# open tub (door cards, floor) so the interior is real, and the greenhouse (pillars, glass, roof) is a second
# loft of horizontal rings that sits on the beltline.

NB = 22   # points per body half-ring
# half-ring layout: 0 bottom centre, 1 inner-well bottom, 2 inner-well top, 3 rocker edge, 4 rocker round,
# 5..9 side, 10 shoulder crease, 11..12 upper side, 13 top edge (E), 14..20 top / tub, 21 top centre


class Car:
    def __init__(self, sp):
        self.sp = sp
        s = sp
        self.WB = s["WB"]
        self.aF, self.aR = -s["WB"] / 2, s["WB"] / 2
        self.zF = self.aF - s["ohf"]
        self.zR = self.aR + (s["L"] - s["WB"] - s["ohf"])
        self.Rt = s["tire_od"] / 2
        self.Ra = self.Rt + s.get("arch_gap", 0.028)
        self.f = {k: curve(s[k]) for k in ("bot", "ys", "ysh", "e", "top", "te")}
        self.front_off = curve(s["front"])      # (y, dz) nose profile: z = zF + dz
        self.rear_off = curve(s["rear"])        # (y, dz) tail profile: z = zR - dz
        self.nose_len = min(s.get("nose_len", 0.34), s["ohf"] - self.Ra - 0.03)
        self.tail_len = min(s.get("tail_len", 0.34), (self.zR - self.aR) - self.Ra - 0.03)
        self.cf = s.get("cabin_floor", 0.27)
        g = s["gh"]
        self.g = g
        self.z_tf = g["zc0"] + g["kf"] * 0.85 ** 2 + 0.03      # hood -> cabin tub (firewall)
        self.z_tr = g["zb0"] - g["krb"] * 0.85 ** 2 - 0.03     # cabin tub -> deck (rear bulkhead)
        self.Yc = curve(g["roof"])
        self.xr = curve(g["xr"])
        self.zC = curve(g["zC"])
        self.carbon_roof = s.get("carbon_roof", False)

    # ---- plan / side helpers
    def w(self, z):
        s = self.sp
        fl = s.get("flare", 0.02)
        w = s["W"] / 2 - fl
        for zc in (self.aF, self.aR):
            d = abs(z - zc) / (self.Ra * s.get("flare_len", 1.9))
            if d < 1:
                w += fl * (s.get("flare_f", 1.0) if zc < 0 else 1.0) * math.cos(d * math.pi / 2) ** 2
        tp = s.get("plan_taper", (0.03, 0.025))
        if z < self.aF:
            w -= tp[0] * ((self.aF - z) / (self.aF - self.zF)) ** 2
        elif z > self.aR:
            w -= tp[1] * ((z - self.aR) / (self.zR - self.aR)) ** 2
        return w

    def ya(self, z):
        """Bottom of the body side: the arch curve inside the wheel openings, else the sill line."""
        ys = self.f["ys"](z)
        p = self.sp.get("arch_p", 2.0)
        for zc in (self.aF, self.aR):
            dz = abs(z - zc)
            if dz <= self.Ra + 1e-6:
                u = min(1.0, dz / self.Ra)
                h = self.Rt + self.Ra * (1 - u ** p) ** (1 / p)
                return max(ys, h)
        return ys

    def low_y(self, z):
        lo = self.sp.get("low_line")
        if not lo:
            return self.f["ys"](z) + 0.25
        return lerp(lo[0], lo[1], min(1.0, max(0.0, (z - self.aF) / self.WB)))

    def side_x(self, y, z, w, ys, ysh, e, te):
        """Body side half-width at height y: rocker tuck, the lower door step (a crisp character line
        rising toward the rear), a slight concave door face, the shoulder crease at ysh, and the upper
        side leaning in to the beltline."""
        x = w
        hb = 0.12
        if y < ys + hb:
            x -= self.sp.get("tuck", 0.014) * (1 - (y - ys) / hb) ** 2
        lo = self.sp.get("low_line")
        yl = self.low_y(z)
        fz = smooth01((z - self.aF - self.Ra) / 0.25) * smooth01((self.aR - self.Ra - z) / 0.25)
        if lo and y > yl + 0.002:
            x -= lo[2] * fz
        if yl < y < ysh:          # slightly hollow door face between the two lines
            x -= self.sp.get("door_hollow", 0.006) * fz * math.sin(math.pi * (y - yl) / (ysh - yl))
        if y > ysh:
            x -= te * ((y - ysh) / max(e - ysh, 1e-3)) ** 1.25
        return x

    def mode(self, z):
        if z < self.z_tf:
            return "hood"
        if z > self.z_tr:
            return "deck"
        return "cabin"

    def dome_w(self, z):
        dm = self.sp.get("dome")
        if not dm:
            return None
        z0, z1, dw, dh = dm
        return dw * lerp(0.62, 1.0, min(1.0, max(0.0, (z - z0) / (z1 - z0))))

    def hood_y(self, x, z, mode=None):
        """Height of the hood / deck surface at (x, z): centre crown + a stepped power dome whose crisp
        edges converge toward the nose."""
        e = self.f["e"](z)
        top = self.f["top"](z)
        xE = self.w(z) - self.f["te"](z)
        u = min(1.0, abs(x) / max(xE, 1e-3))
        y = e + (top - e) * (1 - u ** 2.2)
        dm = self.sp.get("dome")
        if dm and (mode or self.mode(z)) == "hood":
            z0, z1, dw, dh = dm
            if z0 < z < z1:
                dw = self.dome_w(z)
                fz = smooth01((z - z0) / 0.3) * smooth01((z1 - z) / 0.1)
                ax = abs(x)
                fx = 1.0 if ax <= dw - 0.012 else (0.0 if ax >= dw + 0.03 else (dw + 0.03 - ax) / 0.042)
                y += dh * fz * fx
        return y

    def section(self, z, mode):
        s = self.sp
        bot = self.f["bot"](z)
        ys = self.f["ys"](z)
        ya = self.ya(z)
        ysh = self.f["ysh"](z)
        e = self.f["e"](z)
        te = self.f["te"](z)
        w = self.w(z)
        track = s["TF"] if z < 0 else s["TR"]
        x_in = min(track / 2 - s["tire_w"] / 2 - 0.05, w - 0.16)

        def sx(y):
            return self.side_x(y, z, w, ys, ysh, e, te)
        P = [(0.0, bot), (x_in, bot), (x_in, ya)]
        P.append((sx(ya) - 0.022, ya))
        y4 = ya + 0.01
        P.append((sx(y4) - 0.005, y4))
        yl = self.low_y(z)
        targets = [yl - 0.07, yl, yl + 0.012, lerp(yl, ysh, 0.55), ysh - 0.022]
        prev = y4
        for j, yt in enumerate(targets):          # indices 5..9 (6 / 7 = lower crease step)
            room = (ysh - 0.006) - prev
            y = max(yt, prev + min(0.008, room / (6 - j)))
            y = min(y, ysh - 0.006 * (5 - j))
            P.append((sx(y), y))
            prev = y
        P.append((w, ysh))                          # 10: shoulder crease
        for g in (0.4, 0.78):
            y = ysh + (e - ysh) * g
            P.append((sx(y), y))
        xE = w - te
        P.append((xE, e))                           # 13: top edge
        if mode == "cabin":
            cf = self.cf
            inner = [(xE - 0.045, e - 0.004), (xE - 0.065, e - 0.06), (xE - 0.075, e - 0.2),
                     (xE - 0.08, e - 0.4), (xE - 0.09, cf + 0.035), (xE - 0.13, cf), (0.18, cf), (0.0, cf)]
            out = []
            for k, (x, y) in enumerate(inner):
                if 2 <= k <= 5 and y < ya + 0.05 and ya > ys + 0.02:      # rear wheelhouse hump in the cabin
                    x = min(x, x_in - 0.03 - 0.01 * k)
                out.append((x, y))
            P.extend(out)
        else:
            dw = self.dome_w(z) if mode == "hood" else None
            if dw is None:
                dw = 0.38 * xE
            dw = min(dw, 0.55 * xE)
            xs = [xE - 0.018, xE - 0.055, xE * 0.8, xE * 0.62, dw + 0.03, dw - 0.012, dw * 0.5, 0.0]
            for k, x in enumerate(xs):
                y = self.hood_y(x, z, mode)
                if k == 0:
                    y = max(y, e + 0.006)
                P.append((x, y))
        assert len(P) == NB, len(P)
        return P

    # ---- stations
    def stations(self):
        """[(ring points [(x, y, z)], kind)] front to rear, including the collapsed nose/tail caps."""
        zF, zR = self.zF, self.zR
        nl, tl = self.nose_len, self.tail_len
        f0 = self.sp.get("nose_round", 0.8)
        r0 = self.sp.get("tail_round", 0.86)
        rings = []

        def warp_ring(zs, mode, u, front):
            sec = self.section(zs, mode)
            out = []
            if front:
                fac = f0 + (1 - f0) * math.sqrt(max(0.0, 1 - (1 - u) ** 2))
                z_end = zF + nl
                for x, y in sec:
                    zf = zF + self.front_off(y)
                    zz = zf + (zs - zF) * ((z_end - zf) / (z_end - zF))
                    out.append((x * fac, y, zz))
            else:
                fac = r0 + (1 - r0) * math.sqrt(max(0.0, 1 - (1 - u) ** 2))
                z_beg = zR - tl
                for x, y in sec:
                    zr = zR - self.rear_off(y)
                    zz = zr - (zR - zs) * ((zr - z_beg) / (zR - z_beg))
                    out.append((x * fac, y, zz))
            return out

        us = [0.0, 0.015, 0.05, 0.1, 0.17, 0.26, 0.37, 0.5, 0.65, 0.82, 1.0]
        tip = warp_ring(zF, "hood", 0.0, True)
        for sc in (0.0, 0.3, 0.55, 0.75, 0.9):
            rings.append(([(x * sc, y, z) for x, y, z in tip], "cap"))
        for u in us:
            rings.append((warp_ring(zF + nl * u, "hood", u, True), "hood"))
        zs = set()
        z = zF + nl
        while z < zR - tl:
            zs.add(round(z, 4))
            z += 0.085
        for zc in (self.aF, self.aR):
            for k in range(-10, 11):
                zs.add(round(zc + self.Ra * math.sin(k / 10 * math.pi / 2), 4))
            for d in (0.008, 0.04):
                zs.add(round(zc - self.Ra - d, 4))
                zs.add(round(zc + self.Ra + d, 4))
        for zt in (self.z_tf, self.z_tr):
            zs.add(round(zt - 0.001, 4))
            zs.add(round(zt + 0.001, 4))
        for zx in self.sp.get("extra_z", []):
            zs.add(round(zx, 4))
        body = sorted(z for z in zs if zF + nl + 0.005 < z < zR - tl - 0.005)
        for z in body:
            m = self.mode(z)
            rings.append(([(x, y, z) for x, y in self.section(z, m)], m))
        for u in reversed(us):
            rings.append((warp_ring(zR - tl * u, "deck", u, False), "deck"))
        tipr = rings[-1][0]
        for sc in (0.9, 0.75, 0.55, 0.3, 0.0):
            rings.append(([(x * sc, y, z) for x, y, z in tipr], "cap"))
        return rings

    # ---- the shell
    def build_shell(self):
        rings = self.stations()
        full = []
        for pts, m in rings:
            half = [Vector(p) for p in pts]
            mir = [Vector((-p.x, p.y, p.z)) for p in reversed(half[1:-1])]
            full.append((half + mir, m))
        self.rings_full = full
        paint = cls(WHITE, "CarPaint")
        under = cls(BLACK, "Paint")
        well = cls(WELL, "Paint")
        trim_in = cls(self.sp["int"]["trim"], "Paint")
        card = cls(self.sp["int"]["card"], "Paint")
        carpet = cls(self.sp["int"]["carpet"], "Paint")
        dark = cls(DARK, "Paint")
        me = Mesher()
        gz0 = self.g["zc0"] - 0.005
        gz1 = self.g["zb0"] + 0.005

        def cfn(k, i):
            h = i if i < NB - 1 else (2 * NB - 3) - i
            ma, mb = full[k][1], full[k + 1][1]
            za = full[k][0][NB - 1].z
            if ma == "cap" or mb == "cap":
                return under if h == 0 else paint
            if h == 0:
                return under
            if h in (1, 2):
                return well
            if h < 13:
                return paint
            if ma != mb:                       # firewall / rear bulkhead
                return dark
            if ma == "cabin":
                if h == 13:
                    return trim_in
                if h >= 18:
                    return carpet
                return card
            if ma == "hood" and za > gz0 and h >= 14:
                return dark                    # cowl under the windshield
            if ma == "deck" and za < gz1 and h >= 14:
                return dark                    # parcel shelf under the rear window
            return paint

        me.loft([r for r, _m in full], cfn)
        # crisp character lines: shoulder crease, lower door step, power-dome edges
        sharp = [10, 6, 7] + ([18, 19] if self.sp.get("dome") else [])
        n = len(full[0][0])
        for k in range(len(full) - 1):
            if full[k][1] == "cap" or full[k + 1][1] == "cap":
                continue
            for h in sharp:
                for i in (h, n - h):
                    va = me.cache.get(tuple(round(c, 5) for c in full[k][0][i]))
                    vb = me.cache.get(tuple(round(c, 5) for c in full[k + 1][0][i]))
                    if va is None or vb is None or va is vb:
                        continue
                    ed = me.bm.edges.get((va, vb))
                    if ed is not None:
                        ed.smooth = False
        self.shell = me
        return me

    # ---- greenhouse
    def gh_half(self, t):
        """Right half of the greenhouse ring at height fraction t (0 belt, 1 roof edge): front centre ->
        rear centre, with the DLO breakpoints (A, B0, B1, C, rear corner) at fixed indices."""
        g = self.g
        bow = math.sin(math.pi * min(t, 1.0))
        r = lerp(g.get("rb", 0.07), g.get("rt", 0.1), t)

        def xs(z):
            xb = self.w(z) - self.f["te"](z) - 0.012
            xb -= g.get("a_in", 0.0) * max(0.0, 1 - (z - g["zc0"]) / g.get("a_len", 0.9))
            return lerp(xb, self.xr(z), t) + g.get("bow_s", 0.025) * bow

        def y_side(z):
            return lerp(self.f["e"](z) - 0.004, self.Yc(z) - g["crown"], t)

        def roof_y(x, z):
            return self.Yc(z) - g["crown"] * min(1.0, (x / max(self.xr(z), 0.1)) ** 2)

        def front(x):
            z0 = g["zc0"] + g["kf"] * x * x
            z1 = g["zh"] + g.get("kh", 0.1) * x * x
            z = lerp(z0, z1, t) - g.get("bow_f", 0.03) * bow
            y = lerp(self.hood_y(x, z0, "hood") - 0.004, roof_y(x, z1), t) + g.get("bow_fy", 0.02) * bow
            return z, y

        def rear(x):
            z0 = g["zb0"] - g["krb"] * x * x
            z1 = g["zrr"] - g.get("krr", 0.1) * x * x
            z = lerp(z0, z1, t) + g.get("bow_r", 0.03) * bow
            y = lerp(self.hood_y(x, z0, "deck") - 0.004, roof_y(x, z1), t) + g.get("bow_ry", 0.02) * bow
            return z, y

        H = []
        zguess = g["zc0"] + (g["zh"] - g["zc0"]) * t
        x_end = xs(zguess) - r
        for k in range(7):
            x = x_end * k / 6
            z, y = front(x)
            H.append(Vector((x, y, z)))
        zfe, yfe = H[-1].z, H[-1].y
        zA = zfe + r
        yA = y_side(zA)
        xA = xs(zA)
        for k in range(1, 5):
            ph = (math.pi / 2) * k / 4
            x = (xA - r) + r * math.sin(ph)
            z = zfe + r - r * math.cos(ph)
            y = lerp(yfe, yA, 1 - math.cos(ph)) if k < 4 else yA
            H.append(Vector((x if k < 4 else xA, y, z)))
        zguess_r = g["zb0"] + (g["zrr"] - g["zb0"]) * t
        x_end_r = xs(zguess_r) - r
        zre, yre = rear(x_end_r)
        zRs = zre - r
        zc = min(self.zC(t), zRs - 0.05)
        if g.get("B"):
            b0 = lerp(g["B"][0], g["B"][2], t)
            b1 = lerp(g["B"][1], g["B"][3], t)
        else:
            b0 = lerp(zA, zc, g.get("b_frac", 0.62))
            b1 = b0 + 0.004
        for za, zb, cnt in ((zA, b0, 6), (b0, b1, 1), (b1, zc, 6), (zc, zRs, 3)):
            for k in range(1, cnt + 1):
                z = lerp(za, zb, k / cnt)
                H.append(Vector((xs(z), y_side(z), z)))
        yRs = H[-1].y
        xRs = H[-1].x
        for k in range(1, 5):
            ph = (math.pi / 2) * k / 4
            x = (xRs - r) + r * math.cos(ph)
            z = zRs + r * math.sin(ph)
            y = lerp(yRs, yre, 1 - math.cos(ph))
            H.append(Vector((x, y, z)) if k < 4 else Vector((x_end_r, yre, zre)))
        for k in range(5, -1, -1):
            x = x_end_r * k / 6
            z, y = rear(x)
            H.append(Vector((x, y, z)))
        assert len(H) == 37, len(H)
        return H

    def build_greenhouse(self):
        g = self.g
        ts = [0.0, 0.045, 0.1, 0.25, 0.45, 0.65, 0.82, 0.93, 0.96, 1.0]
        halves = [self.gh_half(t) for t in ts]
        edge = halves[-1]
        zmid = (g["zh"] + g["zrr"]) / 2
        for s in (0.93, 0.8, 0.6, 0.38, 0.16, 0.0):
            ring = []
            for p in edge:
                z = zmid + (p.z - zmid) * (1 - (1 - s) * g.get("roof_pz", 0.22))
                x = p.x * s
                y = self.Yc(z) - g["crown"] * min(1.0, (x / max(self.xr(z), 0.1)) ** 2)
                ring.append(Vector((x, y, z)))
            halves.append(ring)
        full = []
        for H in halves:
            L = [Vector((-p.x, p.y, p.z)) for p in H]
            full.append(L + list(reversed(H[1:-1])))
        self.gh_halves = halves
        paint = cls(WHITE, "CarPaint")
        roofc = cls(CARBON, "Gloss") if self.carbon_roof else paint
        glass = cls(GLASS, "Glass")
        tcol = g.get("trim", PIANO)
        trim = cls(tcol, "Gloss" if tcol == PIANO else "Metal")
        trim_top = cls(g.get("trim_top", PIANO), "Gloss" if g.get("trim_top", PIANO) == PIANO else "Metal")
        frit = cls(PIANO, "Gloss")
        nt = len(ts)
        cats = ["ws"] * 6 + ["A"] * 4 + ["gF"] * 6 + ["B"] + ["gR"] * 6 + ["C"] * 3 + ["Rc"] * 4 + ["bl"] * 6

        def cfn(k, i):
            h = i if i < 36 else 71 - i
            c = cats[h]
            if k >= nt - 1:
                return roofc if (self.carbon_roof and k >= nt) else paint
            if c in ("ws", "bl"):
                return frit if (k == 0 or k == nt - 2) else glass
            if c in ("gF", "gR"):
                return trim if k == 0 else (trim_top if k == nt - 2 else glass)
            if c == "B":
                if g.get("B"):
                    return frit
                return trim if k == 0 else (trim_top if k == nt - 2 else glass)
            if c == "A" and g.get("a_black"):
                return frit
            return paint

        me = Mesher()
        me.loft(full, cfn)
        # extra outer glass skins: tinted from outside (layers add up), clear from the seat (only the inner
        # skin faces the driver)
        me.bm.normal_update()
        nor = {}
        for v in me.bm.verts:
            nor[(round(v.co.x, 5), round(v.co.y, 5), round(v.co.z, 5))] = v.normal.copy()
        n = len(full[0])
        for off in g.get("glass_layers", (0.002, 0.004, 0.006)):
            def mv(p):
                nn = nor.get((round(p.x, 5), round(p.y, 5), round(p.z, 5)))
                return p + nn * off if nn is not None else p
            rings = [[mv(p) for p in r] for r in full]
            for k in range(len(rings) - 1):
                for i in range(n):
                    c = cfn(k, i)
                    if PAL[c][1] != "Glass":
                        continue
                    j = (i + 1) % n
                    me.face((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]), c)
        self.gh = me
        self.gh_cats = (full, cfn)
        return me

    def build_gh_inner(self):
        """Headliner / pillar trims / inner glass: the greenhouse again, 14 mm inside, facing in."""
        full, cfn = self.gh_cats
        glass_in = cls(GLASS_IN, "Glass")
        head = cls(self.sp["int"].get("headliner", HEADLINER), "Paint")
        me = Mesher()
        bm = self.gh.bm
        bm.normal_update()
        nor = {}
        for v in bm.verts:
            nor[(round(v.co.x, 5), round(v.co.y, 5), round(v.co.z, 5))] = v.normal.copy()

        def inset(p):
            nn = nor.get((round(p.x, 5), round(p.y, 5), round(p.z, 5)))
            return p - nn * 0.014 if nn is not None else p
        rings = [[inset(p) for p in r] for r in full]
        n = len(rings[0])
        for k in range(len(rings) - 1):
            a, b = rings[k], rings[k + 1]
            for i in range(n):
                j = (i + 1) % n
                c = cfn(k, i)
                c2 = glass_in if PAL[c][1] == "Glass" else head
                me.face((b[i], b[j], a[j], a[i]), c2)
        return me


# ----------------------------------------------------------------------------- wheels
#
# Built with the axle along local +Y (rim face at +Y), then turned so the axle is Godot +X (WHEEL_M).

WHEEL_M = Matrix.Rotation(-math.pi / 2, 4, "Z")      # local +Y -> +X
TIRE = (0.075, 0.075, 0.08)
TIRE_WALL = (0.11, 0.11, 0.115)


def _spoke(M, path, width, thick, y_of, col, kind, samples=7):
    """A spoke lofted along path(u) -> (r, theta) for u in 0..1 (hub -> lip); width(u) tangential,
    thick(u) axial; y_of(r) = axial position of the spoke's front face. Rounded 6-point section."""
    rings = []
    for k in range(samples):
        u = k / (samples - 1)
        r, th = path(u)
        w = width(u) * 1.4
        t = thick(u) * 1.15
        c = Vector((r * math.sin(th), 0, -r * math.cos(th)))
        tang = Vector((math.cos(th), 0, math.sin(th)))
        yf = y_of(r)
        sec = [(-0.5, -1.0), (0.5, -1.0), (0.5, -0.15), (0.32, 0.0), (-0.32, 0.0), (-0.5, -0.15)]
        ring = []
        for a, b in sec:
            p = c + tang * (a * w)
            ring.append(Vector((p.x, yf + b * t, p.z)))
        rings.append(ring)
    bm = loft_bm(rings)
    return emit(bm, col, kind, M, sharp=0.5)


def build_wheel(name, sp):
    od = sp["tire_od"]
    R = od / 2
    rr = sp["rim_in"] * 0.0254 / 2
    w = sp["tire_w"]
    wd = sp["wheel"]
    M = WHEEL_M
    sw = R - rr
    h = w / 2
    # tyre: sidewall bulge, rounded shoulders, three circumferential grooves
    prof = [(rr + 0.006, -h + 0.022), (rr + 0.02, -h + 0.004), (rr + sw * 0.45, -h - 0.008),
            (R - 0.035, -h + 0.002), (R - 0.012, -h + 0.014), (R - 0.002, -h + 0.03)]
    for gy in (-0.2, 0.2):
        yy = gy * w
        prof += [(R, yy - 0.012), (R - 0.009, yy - 0.009), (R - 0.009, yy + 0.009), (R, yy + 0.012)]
    prof += [(R - 0.002, h - 0.03), (R - 0.012, h - 0.014), (R - 0.035, h - 0.002), (rr + sw * 0.45, h + 0.008),
             (rr + 0.02, h - 0.004), (rr + 0.006, h - 0.022)]
    tread = [p for p in prof]
    bm = revolve_bm(tread, 40, closed=True)
    bm.normal_update()
    cols = []
    for f in bm.faces:
        c = f.calc_center_median()
        rad = math.hypot(c.x, c.z)
        cols.append(TIRE if rad > R - 0.015 else TIRE_WALL)
    emit(bm, cols, "Paint", M, sharp=0.9, recalc=False)
    # sidewall lettering ring (subtle) on the outer face
    torus(rr + sw * 0.62, 0.003, (0.2, 0.2, 0.21), "Paint", segs=40, rsegs=3, pos=(0, h + 0.004, 0), M=M)
    rim = wd["col"]
    rimk = wd.get("kind", "Metal")
    lip = wd.get("lip", rim)
    # rim lip + barrel (inside visible through the spokes)
    revolve([(rr - 0.01, h - 0.03), (rr + 0.013, h - 0.012), (rr + 0.014, h + 0.004), (rr + 0.004, h + 0.012),
             (rr - 0.012, h + 0.006), (rr - 0.018, h - 0.01)], lip, "Metal", 48, M=M, closed=True)
    revolve([(rr - 0.012, h - 0.012), (rr - 0.014, -h + 0.03), (rr - 0.03, -h + 0.03), (0.09, -h + 0.05)],
            (0.12, 0.12, 0.13), "Paint", 48, M=M)
    # spokes
    y_face = h + 0.004
    conc = wd.get("concave", 0.04)

    def y_of(r):
        return y_face - conc * (1 - (r - 0.07) / (rr - 0.07)) ** 1.5 - 0.004

    n = wd["n"]
    style = wd["style"]
    r0, r1 = 0.075, rr - 0.004
    for i in range(n):
        th0 = TAU * i / n
        if style == "steel":       # plain steel wheel: no spokes, see the dish below
            break
        if style == "double":
            for sgn in (-1, 1):
                _spoke(M, lambda u, s=sgn, t0=th0: (lerp(r0, r1, u), t0 + s * lerp(0.07, 0.15, u) + 0.0),
                       lambda u: lerp(0.024, 0.02, u), lambda u: 0.03, y_of, rim, rimk)
        elif style == "y":
            _spoke(M, lambda u, t0=th0: (lerp(r0, r0 + (r1 - r0) * 0.55, u), t0),
                   lambda u: lerp(0.042, 0.034, u), lambda u: 0.032, y_of, rim, rimk, samples=4)
            for sgn in (-1, 1):
                _spoke(M, lambda u, s=sgn, t0=th0: (lerp(r0 + (r1 - r0) * 0.5, r1, u), t0 + s * lerp(0.03, 0.17, u)),
                       lambda u: lerp(0.024, 0.022, u), lambda u: 0.028, y_of, rim, rimk, samples=5)
        elif style == "multi":
            _spoke(M, lambda u, t0=th0: (lerp(r0, r1, u), t0 + 0.12 * u * u), lambda u: lerp(0.03, 0.018, u),
                   lambda u: 0.03, y_of, rim, rimk)
        elif style == "vee":
            for sgn in (-1, 1):
                _spoke(M, lambda u, s=sgn, t0=th0: (lerp(r0, r1, u), t0 + s * lerp(0.0, 0.2, u ** 0.8)),
                       lambda u: lerp(0.03, 0.02, u), lambda u: 0.03, y_of, rim, rimk)
        elif style == "star":
            _spoke(M, lambda u, t0=th0: (lerp(r0, r1, u), t0), lambda u: lerp(0.05, 0.075, u),
                   lambda u: 0.03, y_of, rim, rimk)
            _spoke(M, lambda u, t0=th0: (lerp(r0 + 0.02, r1 - 0.02, u), t0), lambda u: 0.012,
                   lambda u: 0.01, lambda r: y_of(r) + 0.003, (0.06, 0.06, 0.065), "Paint")
    if style == "steel":          # pressed steel dish with round cooling holes (police spec)
        yf = y_face - 0.01
        revolve([(rr - 0.004, yf - 0.035), (rr - 0.03, yf - 0.02), (rr * 0.72, yf - 0.012), (rr * 0.55, yf - 0.04),
                 (0.1, yf - 0.05), (0.09, yf - 0.03), (0.0, yf - 0.03)], rim, rimk, 48, M=M)
        for k in range(6):
            a = TAU * k / 6
            rc = rr * 0.63
            cyl(0.026, 0.004, (0.02, 0.02, 0.022), "Paint", 14,
                pos=(rc * math.sin(a), yf - 0.009, -rc * math.cos(a)), M=M)
    # hub, lug bolts, centre cap roundel
    yh = y_of(0.07) if style != "steel" else y_face - 0.04
    revolve([(0.04, -h + 0.06), (0.085, yh - 0.03), (0.08, yh + 0.002), (0, yh + 0.004)], rim, rimk, 40, M=M)
    for k in range(5):
        a = TAU * k / 5 + TAU / 10
        cyl(0.011, 0.02, CHROME, "Metal", 8, pos=(0.058 * math.sin(a), yh + 0.006, -0.058 * math.cos(a)), M=M)
    if style == "steel":
        cyl(0.04, 0.02, CHROME, "Metal", 20, pos=(0, yh + 0.01, 0), bevel=0.008, M=M)
    else:
        roundel(0.028, yh + 0.009, M=M)
    # brake disc + caliper (inside the barrel)
    rd = min(sp.get("disc_r", 0.19), rr - 0.045)
    yd = y_face - conc - 0.075
    revolve([(0.1, yd - 0.016), (rd, yd - 0.016), (rd, yd + 0.016), (0.1, yd + 0.016)], (0.46, 0.47, 0.5), "Metal", 48,
            M=M, closed=True)
    revolve([(0.1, yd - 0.02), (0.1, yd + 0.03), (0.0, yd + 0.03)], (0.2, 0.2, 0.21), "Metal", 32, M=M)
    for k in range(12):     # cross-drill / slot marks
        a = TAU * k / 12
        box((0.005, 0.003, rd - 0.13), (0.1, 0.1, 0.11), "Paint",
            pos=((0.115 + rd) / 2 * math.sin(a), yd + 0.0165, -(0.115 + rd) / 2 * math.cos(a)), rot=[("y", -a + 0.3)],
            M=M)
    # caliper: annular sector at the top-rear (world), straddling the disc
    ccol = wd.get("caliper", (0.1, 0.25, 0.75))
    c_mid = math.atan2(-0.82, -0.57)      # local angle whose direction maps to world up-rear
    arc = 0.95
    ring_o, ring_i = [], []
    for k in range(9):
        a = c_mid - arc / 2 + arc * k / 8
        ring_o.append((( rd + 0.022) * math.sin(a), -(rd + 0.022) * math.cos(a)))
        ring_i.append(((rd - 0.055) * math.sin(a), -(rd - 0.055) * math.cos(a)))
    poly = ring_o + list(reversed(ring_i))
    bmc = prism_bm([(x, z) for x, z in poly], yd - 0.04, yd + 0.052, axis="y", bevel=0.008, seg=2)
    emit(bmc, ccol, "Gloss", M, sharp=0.6)
    ya_ = yd + 0.053
    am = (rd - 0.016)
    box((0.05, 0.004, 0.018), (0.95, 0.95, 0.95), "Paint",
        pos=(am * math.sin(c_mid), ya_, -am * math.cos(c_mid)), rot=[("y", -c_mid + math.pi / 2)], M=M)
    finish(name)


SW_M = Matrix.Rotation(math.pi / 2, 4, "X")     # local face +Y -> Godot +Z (toward the driver)
SW_R = 0.178                                    # rim centre-line radius (0.37 m wheel)


def sweep_loop(path, sec_fn, col_fn, kind="Paint", M=None):
    """Closed sweep: path [(x, z)] loop in the XZ plane; sec_fn(i) -> (radial half-size, axial half-size);
    col_fn(i) -> colour. Elliptic 12-point section."""
    n = len(path)
    rings = []
    for i in range(n):
        p = Vector((path[i][0], 0, path[i][1]))
        q0 = Vector((path[i - 1][0], 0, path[i - 1][1]))
        q1 = Vector((path[(i + 1) % n][0], 0, path[(i + 1) % n][1]))
        t = (q1 - q0).normalized()
        nr = Vector((t.z, 0, -t.x))            # in-plane normal
        if nr.dot(p) < 0:
            nr = -nr
        a, b = sec_fn(i)
        ring = []
        for k in range(12):
            ang = TAU * k / 12
            ring.append(p + nr * (a * math.cos(ang)) + Vector((0, b * math.sin(ang), 0)))
        rings.append(ring)
    me = Mesher()
    for i in range(n):
        A, B = rings[i], rings[(i + 1) % n]
        c = cls(col_fn(i), kind)
        for k in range(12):
            j = (k + 1) % 12
            me.face((A[k], A[j], B[j], B[k]), c)
    bmesh.ops.recalc_face_normals(me.bm, faces=me.bm.faces)
    return me.emit(M=M, sharp=1.2)


def build_steering_wheel():
    """M-style: thick flat-bottomed leather rim with thumb rests and a red 12 o'clock marker, three spokes
    (silver trim, button pads, red M1/M2 buttons), airbag hub with the roundel, paddles. Origin = hub,
    rim in the XY plane facing +Z."""
    M = SW_M
    LEATHER = (0.06, 0.06, 0.065)
    RED = (0.85, 0.08, 0.1)
    R = SW_R
    raw = []
    N = 64
    for i in range(N):
        th = TAU * i / N                      # clock angle from 12 o'clock
        x, z = R * math.sin(th), -R * math.cos(th)
        if z > R * 0.74:                      # flat bottom
            z = R * 0.74 + (z - R * 0.74) * 0.12
        raw.append((x, z))
    path = raw

    def sec(i):
        th = TAU * i / N
        thumb = math.exp(-((math.sin(th) ** 2 - 1) / 0.06) ** 2) * (1 if abs(math.cos(th)) < 0.5 else 0)
        return 0.017 + 0.004 * thumb, 0.021 + 0.003 * thumb

    def col(i):
        th = TAU * i / N
        return RED if (th < 0.07 or th > TAU - 0.07) else LEATHER

    sweep_loop(path, sec, col, "Paint", M)
    # spokes: 9 and 3 o'clock (wide, silver-trimmed), lower double spoke
    for sgn in (-1, 1):
        prism([(sgn * 0.05, -0.03), (sgn * 0.165, -0.022), (sgn * 0.165, 0.028), (sgn * 0.05, 0.045)],
              -0.012, 0.012, (0.1, 0.1, 0.11), "Gloss", axis="y", bevel=0.006, M=M)
        prism([(sgn * 0.06, 0.038), (sgn * 0.16, 0.024), (sgn * 0.16, 0.03), (sgn * 0.06, 0.045)],
              0.012, 0.016, (0.72, 0.73, 0.76), "Metal", axis="y", M=M)
        for k in range(3):     # button pad
            box((0.018, 0.006, 0.014), (0.03, 0.03, 0.035), "Gloss", pos=(sgn * (0.085 + k * 0.022), 0.014, 0.005), M=M)
        box((0.026, 0.008, 0.016), RED, "Gloss", pos=(sgn * 0.13, 0.016, -0.02), M=M)      # M1 / M2
        # paddle behind the rim
        prism([(sgn * 0.13, -0.06), (sgn * 0.2, -0.05), (sgn * 0.205, 0.0), (sgn * 0.14, 0.02)],
              -0.05, -0.044, (0.5, 0.52, 0.55), "Metal", axis="y", bevel=0.004, M=M)
    for sgn in (-1, 1):
        prism([(sgn * 0.02, 0.05), (sgn * 0.045, 0.05), (sgn * 0.075, R * 0.72), (sgn * 0.05, R * 0.74)],
              -0.01, 0.01, (0.62, 0.63, 0.66), "Metal", axis="y", bevel=0.004, M=M)
    # hub / airbag cover
    box((0.13, 0.04, 0.11), (0.07, 0.07, 0.075), "Paint", pos=(0, 0.0, 0.005), r=0.02, seg=3, M=M)
    box((0.1, 0.01, 0.08), (0.09, 0.09, 0.1), "Paint", pos=(0, 0.02, 0.005), r=0.012, M=M)
    roundel(0.016, 0.024, M=M, pos=(0, 0, -0.01))
    cyl(0.03, 0.06, (0.05, 0.05, 0.055), "Paint", 16, pos=(0, -0.045, 0), M=M)      # boss (into the column)
    finish("Bemze_SteeringWheel")


def roundel(r, y, M=None, pos=(0, 0, 0), rot=None, ring=None):
    """The BEMZE roundel lying in the XZ plane facing +Y: black ring, chrome rim, quartered orange/white
    disc with a thin cross (clearly not the real thing)."""
    Mx = (M if M is not None else Matrix.Identity(4)) @ T(pos, rot)
    revolve([(0, y - 0.003), (r, y - 0.003), (r, y + 0.002), (r * 0.94, y + 0.004), (0, y + 0.004)],
            (0.03, 0.03, 0.035), "Gloss", 32, M=Mx)
    revolve([(r * 0.93, y + 0.0035), (r * 0.99, y + 0.0035), (r * 0.99, y + 0.005), (r * 0.93, y + 0.005)],
            CHROME, "Metal", 32, M=Mx, closed=True)
    for q in range(4):
        col = ORANGE if q % 2 == 0 else (0.97, 0.97, 0.95)
        revolve([(r * 0.66, y + 0.0045), (0, y + 0.0045)], col, "Gloss", 6, M=Mx, phase=q * math.pi / 2,
                arc=math.pi / 2)
    # tiny "B" monogram band: a thin dark ring between the quarters and the lettering ring
    revolve([(r * 0.7, y + 0.0048), (r * 0.66, y + 0.0048)], (0.9, 0.9, 0.9), "Metal", 32, M=Mx)


# ----------------------------------------------------------------------------- exterior details

def span(poly, y, axis=1):
    """Min/max of the other coordinate where the line coord[axis] == y crosses the polygon."""
    xs = []
    n = len(poly)
    o = 1 - axis
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        if (a[axis] - y) * (b[axis] - y) <= 0 and a[axis] != b[axis]:
            t = (y - a[axis]) / (b[axis] - a[axis])
            xs.append(a[o] + (b[o] - a[o]) * t)
    if len(xs) < 2:
        return None
    return min(xs), max(xs)


def bbox2(poly):
    return (min(p[0] for p in poly), min(p[1] for p in poly), max(p[0] for p in poly), max(p[1] for p in poly))


def roundel_decal(S, c, r, view, lift=0.004):
    """BEMZE roundel projected onto a panel: black ring, chrome edge, quartered orange / white centre."""
    S.decal(ellipse(c[0], c[1], r, r, 28), view, (0.03, 0.03, 0.035), "Gloss", lift=lift, rings=2, step=0.01)
    S.frame(ellipse(c[0], c[1], r * 1.02, r * 1.02, 28), ellipse(c[0], c[1], r * 0.9, r * 0.9, 28), view, CHROME,
            "Metal", lift=lift + 0.0015, step=0.01)
    ri = r * 0.62
    for q in range(4):
        a0 = q * math.pi / 2
        pts = [(c[0], c[1])] + [(c[0] + ri * math.cos(a0 + k * math.pi / 12), c[1] + ri * math.sin(a0 + k * math.pi / 12))
                                for k in range(7)]
        S.decal(pts, view, ORANGE if q % 2 == 0 else (0.97, 0.97, 0.95), "Gloss", lift=lift + 0.0015, rings=1,
                step=0.01, center=(c[0] + ri * 0.4 * math.cos(a0 + math.pi / 4), c[1] + ri * 0.4 * math.sin(a0 + math.pi / 4)),
                skirt=False)
    # thin "B" script around the ring (just a hint: two small chrome letters)
    S.text("B", r * 0.42, view, (c[0], c[1] + r * 0.77), CHROME, "Metal", lift=lift + 0.0015, spacing=1.0)


def kidneys(car, S, st):
    """The kidney grille: raised frame (+ optional light-up contour), dark inner, slats."""
    k = st["kidney"]
    poly = round_poly(k["pts"], k["r"], per=5)
    poly = _ccw(poly)
    fw = k.get("frame_w", 0.02)
    inner = offset_poly(poly, -fw)
    lift = k.get("lift", 0.03)
    mirror = not k.get("single", False)
    S.decal(poly, "front", (0.02, 0.02, 0.025), "Paint", lift=lift - 0.014, rings=3, step=0.025, mirror=mirror)
    fcol = k.get("frame", PIANO)
    S.frame(poly, inner, "front", fcol, "Metal" if fcol == CHROME else "Gloss", lift=lift, mirror=mirror)
    if k.get("glow"):     # "Iconic Glow" contour
        S.frame(offset_poly(poly, -0.002), offset_poly(poly, -0.008), "front", LAMP_W, "Glow", lift=lift + 0.002,
                mirror=mirror)
    x0, y0, x1, y1 = bbox2(inner)
    slat = k.get("slats", "h")
    scol = k.get("slat_col", PIANO)
    skind = "Metal" if scol in (CHROME, ALU) else "Gloss"
    if slat in ("h", "hh"):
        pitch = k.get("pitch", 0.04)
        y = y0 + pitch * 0.6
        while y < y1 - pitch * 0.3:
            for dy in ((0.0,) if slat == "h" else (-0.007, 0.007)):
                sp_ = span(inner, y + dy)
                if sp_:
                    a, b = sp_[0] + 0.004, sp_[1] - 0.004
                    t = k.get("slat_t", 0.012)
                    S.decal([(a, y + dy - t / 2), (b, y + dy - t / 2), (b, y + dy + t / 2), (a, y + dy + t / 2)], "front",
                            scol, skind, lift=lift - 0.006, rings=1, step=0.07, mirror=mirror)
            y += pitch
    elif slat in ("v", "vv"):
        pitch = k.get("pitch", 0.035)
        x = x0 + pitch * 0.6
        while x < x1 - pitch * 0.3:
            for dx in ((0.0,) if slat == "v" else (-0.006, 0.006)):
                sp_ = span(inner, x + dx, axis=0)
                if sp_:
                    a, b = sp_[0] + 0.004, sp_[1] - 0.004
                    t = k.get("slat_t", 0.01)
                    S.decal([(x + dx - t / 2, a), (x + dx + t / 2, a), (x + dx + t / 2, b), (x + dx - t / 2, b)], "front",
                            scol, skind, lift=lift - 0.006, rings=1, step=0.07, mirror=mirror)
            x += pitch
    if k.get("divider"):     # single-frame grille with a centre bar (M8)
        S.decal([(-0.012, y0 - 0.01), (0.012, y0 - 0.01), (0.012, y1 + 0.01), (-0.012, y1 + 0.01)], "front", fcol,
                "Gloss", lift=lift, rings=1)


def oblique(car, end, alpha):
    """A projection from the front-right / rear-right quarter: it lands on both the end face and the
    corner, so wrap-around lamps come out whole. Returns (view, conv) where conv maps end-view (x, y) to it."""
    ca, sa = math.cos(alpha), math.sin(alpha)
    if end == "rear":
        z0 = car.zR
        return ((-sa, 0, -ca), (ca, 0, -sa), (0, 1, 0)), (lambda x, y: (x * ca - z0 * sa, y))
    z0 = car.zF
    return ((-sa, 0, ca), (ca, 0, sa), (0, 1, 0)), (lambda x, y: (x * ca + z0 * sa, y))


def _cv(conv, pts):
    return [conv(x, y) for x, y in pts]


def headlights(car, S, st):
    h = st["head"]
    V, cv = oblique(car, "front", h.get("alpha", 0.55))
    poly = round_poly(h["pts"], h.get("r", 0.012), per=3)
    S.decal(_cv(cv, offset_poly(_ccw(poly), 0.006)), V, h.get("bezel", (0.1, 0.1, 0.11)), "Paint", lift=0.005, rings=2,
            step=0.03, mirror=True)
    S.decal(_cv(cv, poly), V, (0.035, 0.037, 0.042), "Gloss", lift=0.008, rings=2, step=0.03, mirror=True)
    for shp in h.get("drl", []):
        pts = round_poly(shp, 0.004, per=2) if len(shp) > 2 else shp
        S.decal(_cv(cv, pts), V, LAMP_W, "Glow", lift=0.011, rings=1, step=0.015, mirror=True)
    for (x, y, r) in h.get("lens", []):
        S.decal(_cv(cv, ellipse(x, y, r, r, 14)), V, (0.55, 0.57, 0.6), "Metal", lift=0.01, rings=1, step=0.01,
                mirror=True)
        S.decal(_cv(cv, ellipse(x, y, r * 0.55, r * 0.55, 10)), V, (0.85, 0.9, 1.0), "Glow", lift=0.012, rings=1,
                step=0.01, mirror=True)
    for shp in h.get("blue", []):
        S.decal(_cv(cv, shp), V, LAMP_BLUE, "Glow", lift=0.011, rings=1, step=0.015, mirror=True)
    c = centroid(h["pts"])
    loc, _n = S.hit(*cv(c[0], c[1]), V)
    return loc


def taillights(car, S, st):
    t = st["tail"]
    V, cv = oblique(car, "rear", t.get("alpha", 0.6))
    poly = round_poly(t["pts"], t.get("r", 0.012), per=3)
    S.decal(_cv(cv, offset_poly(_ccw(poly), 0.006)), V, (0.05, 0.015, 0.018), "Paint", lift=0.005, rings=2, step=0.03,
            mirror=True)
    S.decal(_cv(cv, poly), V, t.get("base", (0.26, 0.015, 0.02)), t.get("base_kind", "Glow"), lift=0.008, rings=2,
            step=0.025, mirror=True)
    for shp in t.get("glow", []):
        S.decal(_cv(cv, round_poly(shp, 0.004, per=2)), V, TAIL, "Glow", lift=0.011, rings=1, step=0.015, mirror=True)
    for shp in t.get("hi", []):
        S.decal(_cv(cv, shp), V, TAIL_HI, "Glow", lift=0.013, rings=1, step=0.012, mirror=True)
    c = centroid(t["pts"])
    loc, _n = S.hit(*cv(c[0], c[1]), V)
    return loc


def exhausts(car, S, st):
    tips = []
    for (x, y, r, shape) in st["exhaust"]:
        for sx in (-1, 1):
            loc, _n = S.hit(sx * x, y, "rear")
            if loc is None:
                continue
            z1 = loc.z + st.get("tip_out", 0.025)
            M = T((sx * x, y, z1 - 0.07), [("x", math.pi / 2)])
            if shape == "round":
                revolve([(r * 0.8, -0.1), (r, -0.02), (r, 0.07), (r * 0.9, 0.075), (r * 0.82, 0.07), (r * 0.82, -0.1)],
                        st.get("tip_col", (0.1, 0.1, 0.11)), st.get("tip_kind", "Metal"), 20, M=M)
                revolve([(r * 0.83, 0.06), (0.0, 0.06)], (0.01, 0.01, 0.01), "Paint", 16, M=M)
            else:       # trapezoid / oval tip
                sc = T((sx * x, y, z1 - 0.07), [("x", math.pi / 2)], scale=(1.35, 1.0, 0.8))
                revolve([(r * 0.8, -0.1), (r, -0.02), (r, 0.07), (r * 0.9, 0.075), (r * 0.82, 0.07), (r * 0.82, -0.1)],
                        st.get("tip_col", (0.1, 0.1, 0.11)), st.get("tip_kind", "Metal"), 20, M=sc)
                revolve([(r * 0.83, 0.06), (0.0, 0.06)], (0.01, 0.01, 0.01), "Paint", 16, M=sc)
            tips.append(_r3((sx * x, y, z1)))
    return tips


def _r3(v):
    return tuple(round(float(c), 4) for c in v)


def mirrors(car, st):
    """Door mirrors on both sides (M-style twin stalks, body-colour housing, carbon or paint cap)."""
    m = st["mirror"]
    z0, y0 = m["z"], m["y"]
    xE = car.w(z0) - car.f["te"](z0)
    L = m.get("len", 0.23)
    cap = m.get("cap", "paint")
    sc = m.get("scale", 0.86)
    for sx in (-1, 1):
        n0 = len(PARTS)
        rings = []
        prof = [(0.0, 0.028, 0.03), (0.03, 0.05, 0.045), (0.07, 0.062, 0.058), (0.13, 0.066, 0.064),
                (0.18, 0.064, 0.062), (0.21, 0.055, 0.054), (0.228, 0.04, 0.04), (0.236, 0.018, 0.02)]
        for xo, dz, dy in prof:
            ring = []
            for k in range(16):
                a = TAU * k / 16
                zz = -dz * math.cos(a)
                yy = dy * math.sin(a)
                if zz > dz * 0.45:        # flat glass face toward the rear
                    zz = dz * 0.45 + (zz - dz * 0.45) * 0.15
                ring.append(Vector((sx * (xE + 0.04 + xo * L / 0.236), y0 + 0.03 + yy + xo * 0.08, z0 + zz)))
            rings.append(ring if sx > 0 else list(reversed(ring)))
        bm = loft_bm(rings, cap0=True, cap1=True)
        bm.normal_update()
        cols = []
        kinds_carbon = cap == "carbon"
        for f in bm.faces:
            cols.append(WHITE)
        hc, hk = m.get("housing", (WHITE, "CarPaint"))
        emit(bm, hc, hk, sharp=1.0)
        if kinds_carbon:        # carbon cap: the front half of the housing, slightly proud
            rings2 = []
            for xo, dz, dy in prof[1:-1]:
                ring = []
                for k in range(9):
                    a = math.pi / 2 + math.pi * k / 8
                    zz = -(dz + 0.003) * math.cos(a) - 0.0
                    yy = (dy + 0.003) * math.sin(a)
                    ring.append(Vector((sx * (xE + 0.04 + xo * L / 0.236), y0 + 0.03 + yy + xo * 0.08, z0 + min(zz, -0.004))))
                rings2.append(ring if sx > 0 else list(reversed(ring)))
            emit(loft_bm(rings2, cap0=False, cap1=False, closed=False), CARBON, "Gloss", sharp=1.0)
        # glass (flat, facing +z)
        gz = z0 + 0.45 * 0.062 + 0.002
        gpts = [Vector((sx * (xE + 0.04 + (0.03 + 0.18 * (0.5 + 0.5 * math.cos(TAU * k / 16))) * L / 0.236),
                        y0 + 0.03 + 0.05 * math.sin(TAU * k / 16) + 0.08 * 0.1, gz)) for k in range(16)]
        bmg = bmesh.new()
        vs = [bmg.verts.new(p) for p in gpts]
        f = bmg.faces.new(vs)
        bmg.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
        emit(bmg, (0.55, 0.6, 0.66), "Metal", recalc=False)
        # twin stalks
        for dz in (-0.02, 0.012):
            box((0.07, 0.022, 0.016), BLACK, "Gloss", pos=(sx * (xE + 0.02), y0 - 0.005, z0 + dz), r=0.006)
        # side indicator strip under the housing
        box((0.09, 0.006, 0.02), (1.0, 0.55, 0.1), "Glow", pos=(sx * (xE + 0.17), y0 - 0.02, z0 - 0.02), r=0.002)
        anchor = Vector((sx * (xE + 0.01), y0, z0))
        xform_parts(n0, Matrix.Translation(anchor) @ Matrix.Diagonal((sc, sc, sc, 1)) @ Matrix.Translation(-anchor))


def shut_lines(car, S):
    """Hood and boot-lid gaps seen from above (subtle dark grooves)."""
    g = car.g
    gap = (0.02, 0.02, 0.022)
    zs = [car.zF + car.nose_len * 0.55 + k * (g["zc0"] - 0.06 - car.zF - car.nose_len * 0.55) / 10 for k in range(11)]
    pts = [(car.w(z) - car.f["te"](z) - 0.045, z) for z in zs]
    S.line(pts, 0.005, "top", gap, "Paint", lift=0.0025, mirror=True, step=0.08)
    z0 = g["zb0"] + 0.07
    z1 = car.zR - car.tail_len * 0.6
    xs = car.w(z0) - car.f["te"](z0) - 0.07
    S.line([(-xs, z0), (xs, z0)], 0.005, "top", gap, "Paint", lift=0.0025, step=0.08)
    zz = [z0 + (z1 - z0) * k / 6 for k in range(7)]
    S.line([(car.w(z) - car.f["te"](z) - 0.07, z) for z in zz], 0.005, "top", gap, "Paint", lift=0.0025, mirror=True,
           step=0.08)


def side_details(car, S, st):
    shut_lines(car, S)
    sd = st["side"]
    for pl in sd.get("gaps", []):
        S.line(pl, 0.005, "right", (0.02, 0.02, 0.022), "Paint", lift=0.0025, mirror=True, step=0.05)
    for (z, y, L_) in sd.get("handles", []):
        poly = round_poly([(z - L_ / 2, y - 0.016), (z + L_ / 2, y - 0.016), (z + L_ / 2, y + 0.016), (z - L_ / 2, y + 0.016)],
                          0.014, per=3)
        S.decal(offset_poly(_ccw(poly), 0.008), "right", (0.03, 0.03, 0.035), "Paint", lift=0.002, rings=2, mirror=True)
        S.decal(poly, "right", sd.get("handle_col", WHITE), sd.get("handle_kind", "CarPaint"), lift=0.014, rings=2,
                mirror=True, lift_fn=lambda f: 0.004 * f)
    g = sd.get("gill")
    if g:
        poly = round_poly(g["pts"], 0.01, per=3)
        S.decal(poly, "right", g.get("col", PIANO), "Gloss", lift=0.005, rings=2, mirror=True)
        for sl in g.get("slats", []):
            S.decal(sl, "right", (0.01, 0.01, 0.012), "Paint", lift=0.007, rings=1, mirror=True)
        if g.get("badge"):
            bz, by = g["badge_at"]
            S.text(g["badge"], 0.028, "right", (bz, by), CHROME, "Metal", lift=0.008, fnt="sansi")
            S.text(g["badge"], 0.028, "left", (bz, by), CHROME, "Metal", lift=0.008, fnt="sansi")
    sk = sd.get("skirt")
    if sk:
        S.decal(sk, "right", sd.get("skirt_col", PIANO), "Gloss", lift=0.006, rings=2, mirror=True, step=0.05)
    fd = sd.get("fuel")
    if fd:
        z, y = fd
        S.line(round_poly([(z - 0.07, y - 0.065), (z + 0.07, y - 0.065), (z + 0.07, y + 0.065), (z - 0.07, y + 0.065)], 0.03,
                          per=3), 0.004, "right", (0.02, 0.02, 0.022), "Paint", lift=0.0025, closed=True)
    for trim in sd.get("trims", []):
        S.decal(trim[0], "right", trim[1], trim[2], lift=0.006, rings=2, mirror=True)


def front_details(car, S, st):
    tag("f.kidney")
    kidneys(car, S, st)
    tag("f.head")
    hl = headlights(car, S, st)
    tag("f.bumper")
    fr = st["front"]
    for poly in fr.get("intakes", []):
        pts = round_poly(poly, 0.02, per=3)
        S.decal(pts, "front", (0.03, 0.03, 0.035), "Paint", lift=0.004, rings=2, mirror=True, step=0.04)
        S.frame(pts, offset_poly(_ccw(pts), -0.012), "front", PIANO, "Gloss", lift=0.008, mirror=True)
        x0, y0, x1, y1 = bbox2(pts)
        y = y0 + 0.03
        while y < y1 - 0.02:
            sp_ = span(offset_poly(_ccw(pts), -0.015), y)
            if sp_:
                S.decal([(sp_[0], y - 0.005), (sp_[1], y - 0.005), (sp_[1], y + 0.005), (sp_[0], y + 0.005)], "front",
                        (0.07, 0.07, 0.075), "Gloss", lift=0.007, rings=1, mirror=True, step=0.07)
            y += 0.035
    for poly in fr.get("center", []):
        pts = round_poly(poly, 0.02, per=3)
        S.decal(pts, "front", (0.03, 0.03, 0.035), "Paint", lift=0.004, rings=2, step=0.04)
        S.frame(pts, offset_poly(_ccw(pts), -0.012), "front", PIANO, "Gloss", lift=0.008)
    for poly, col, kind in fr.get("trims", []):
        S.decal(poly, "front", col, kind, lift=0.006, rings=2, mirror=True)
    for poly in st.get("hood_vents", []):
        S.decal(round_poly(poly, 0.015, per=2), "top", (0.03, 0.03, 0.035), "Gloss", lift=0.004, rings=2, mirror=True)
        x0, z0, x1, z1 = bbox2(poly)
        for k in range(4):
            zz = z0 + (z1 - z0) * (k + 0.6) / 4.2
            S.decal([(x0 + 0.02, zz - 0.006), (x1 - 0.02, zz - 0.006), (x1 - 0.02, zz + 0.006), (x0 + 0.02, zz + 0.006)],
                    "top", (0.08, 0.08, 0.09), "Gloss", lift=0.007, rings=1, mirror=True, step=0.08)
    for poly, col, kind in fr.get("trims_c", []):
        S.decal(poly, "front", col, kind, lift=0.006, rings=2)
    # plate
    px, py = fr["plate"]
    pl = [(-0.26, py - 0.056), (0.26, py - 0.056), (0.26, py + 0.056), (-0.26, py + 0.056)]
    S.decal(round_poly(pl, 0.008, per=2), "front", PLATE, "Paint", lift=fr.get("plate_lift", 0.012), rings=2)
    S.decal([(-0.255, py - 0.051), (-0.215, py - 0.051), (-0.215, py + 0.051), (-0.255, py + 0.051)], "front",
            (0.1, 0.2, 0.7), "Paint", lift=fr.get("plate_lift", 0.012) + 0.001, rings=1)
    S.text(st.get("plate_text", "BEMZE"), 0.05, "front", (0.02, py), (0.05, 0.05, 0.06), "Paint",
           lift=fr.get("plate_lift", 0.012) + 0.001)
    ploc, _ = S.hit(0, py, "front")
    tag("f.roundel")
    # roundel on the hood nose
    rv = ((0, -0.55, 0.835), (1, 0, 0), (0, 0.835, 0.55))
    if st.get("roundel_front"):
        ry, rz = st["roundel_front"]
        roundel_decal(S, (0.0, ry * 0.835 + rz * 0.55), 0.04, rv, lift=0.004)
    return hl, ploc


def rear_details(car, S, st):
    tl = taillights(car, S, st)
    rr = st["rear"]
    for poly, col, kind in rr.get("trims", []):
        S.decal(poly, "rear", col, kind, lift=0.006, rings=2, mirror=True)
    for poly, col, kind in rr.get("trims_c", []):
        S.decal(poly, "rear", col, kind, lift=0.006, rings=2)
    d = rr.get("diffuser")
    if d:
        yb = car.f["bot"](car.zR) + 0.015
        d = [(x, max(y, yb)) for x, y in d]
        S.decal(round_poly(d, 0.02, per=3), "rear", (0.03, 0.03, 0.035), "Paint", lift=0.006, rings=3, step=0.04)
        for fx in rr.get("fins", []):
            sp_ = span(d, fx, axis=0)
            if sp_:
                S.decal([(fx - 0.006, sp_[0] + 0.01), (fx + 0.006, sp_[0] + 0.01), (fx + 0.006, sp_[1] - 0.005),
                         (fx - 0.006, sp_[1] - 0.005)], "rear", PIANO, "Gloss", lift=0.028, rings=1)
    for (x, y, w_, h_) in rr.get("reflectors", []):
        S.decal(round_poly([(x - w_ / 2, y - h_ / 2), (x + w_ / 2, y - h_ / 2), (x + w_ / 2, y + h_ / 2), (x - w_ / 2, y + h_ / 2)],
                           min(w_, h_) * 0.45, per=2), "rear", TAIL, "Glow", lift=0.007, rings=1, mirror=True)
    px, py = rr["plate"]
    pl = [(-0.26, py - 0.056), (0.26, py - 0.056), (0.26, py + 0.056), (-0.26, py + 0.056)]
    S.decal(offset_poly(_ccw(pl), 0.02), "rear", (0.04, 0.04, 0.045), "Paint", lift=0.003, rings=2)
    S.decal(round_poly(pl, 0.008, per=2), "rear", PLATE, "Paint", lift=0.008, rings=2)
    S.decal([(-0.255, py - 0.051), (-0.215, py - 0.051), (-0.215, py + 0.051), (-0.255, py + 0.051)], "rear",
            (0.1, 0.2, 0.7), "Paint", lift=0.009, rings=1)
    S.text(st.get("plate_text", "BEMZE"), 0.05, "rear", (0.02, py), (0.05, 0.05, 0.06), "Paint", lift=0.009)
    ploc, _ = S.hit(0, py, "rear")
    # badges
    if rr.get("roundel"):
        roundel_decal(S, rr["roundel"], 0.037, "rear", lift=0.004)
    S.text(st["badge"], 0.045, "rear", rr["badge_at"], CHROME, "Metal", lift=0.004, fnt="sansi")
    if rr.get("script_at"):
        S.text("BEMZE", 0.03, "rear", rr["script_at"], CHROME, "Metal", lift=0.004, spacing=1.15)
    lip = rr.get("lip")
    if lip:
        S.decal(lip, "top", lip_col(car), "CarPaint" if not car.sp.get("carbon_lip") else "Gloss", lift=0.018, rings=2,
                step=0.04, lift_fn=lambda f: 0.0)
    tips = exhausts(car, S, st)
    return tl, ploc, tips


def lip_col(car):
    return CARBON if car.sp.get("carbon_lip") else WHITE


def antenna(car, st):
    """Shark-fin on the roof, above the rear window."""
    z1 = car.g["zrr"] - 0.04
    y1 = car.Yc(z1) - 0.004
    prof = [(z1 - 0.2, 0.0), (z1, 0.0), (z1 - 0.025, 0.045), (z1 - 0.075, 0.066), (z1 - 0.15, 0.028)]
    bm = prism_bm([(zz, yy + y1) for zz, yy in prof], -0.022, 0.022, axis="x", bevel=0.012, seg=3)
    for v in bm.verts:     # taper toward the top
        f = (v.co.y - y1) / 0.066
        v.co.x *= (1 - 0.6 * f)
    emit(bm, car.sp.get("fin_col", WHITE), "CarPaint" if car.sp.get("fin_col", WHITE) == WHITE else "Gloss", sharp=1.0)


# ----------------------------------------------------------------------------- interior

def seat(x, hy, hz, it, bucket=True, recline=0.36):
    """M bucket seat, H-point at (x, hy, hz), facing -z: sculpted cushion with thigh bolsters, a backrest
    silhouette with shoulders, a narrow neck and the integrated headrest (M-carbon 'hole' + lit badge),
    side wings, coloured inserts."""
    base = it["seat"]
    acc = it["seat2"]
    dark = (0.05, 0.05, 0.055)
    # cushion: side profile (z, y) extruded across
    prof = [(hz + 0.03, hy - 0.15), (hz - 0.5, hy - 0.13), (hz - 0.53, hy - 0.06), (hz - 0.49, hy - 0.025),
            (hz - 0.1, hy - 0.07), (hz + 0.03, hy - 0.09)]
    prism(prof, x - 0.2, x + 0.2, base, "Paint", axis="x", bevel=0.02, seg=2)
    ins = [(hz - 0.1, hy - 0.058), (hz - 0.47, hy - 0.018), (hz - 0.47, hy - 0.03), (hz - 0.1, hy - 0.07)]
    prism(ins, x - 0.12, x + 0.12, acc, "Paint", axis="x")
    for sgn in (-1, 1):       # thigh bolsters
        bol = [(hz + 0.02, hy - 0.12), (hz - 0.5, hy - 0.1), (hz - 0.5, hy + 0.0), (hz - 0.35, hy + 0.02),
               (hz - 0.08, hy - 0.02), (hz + 0.02, hy - 0.05)]
        prism(bol, x + sgn * 0.15, x + sgn * 0.235, base, "Paint", axis="x", bevel=0.02, seg=2)
    box((0.38, 0.14, 0.44), dark, "Paint", pos=(x, hy - 0.2, hz - 0.22), r=0.015)       # base / rails
    # backrest, reclined about the H-point (local: x across, y up the back, z = thickness, front at -z)
    M = T((x, hy, hz + 0.02), [("x", recline)])
    out = [(-0.24, 0.0), (0.24, 0.0), (0.26, 0.36), (0.22, 0.46), (0.14, 0.5), (0.135, 0.56), (0.15, 0.6),
           (0.15, 0.72), (0.12, 0.76), (-0.12, 0.76), (-0.15, 0.72), (-0.15, 0.6), (-0.135, 0.56), (-0.14, 0.5),
           (-0.22, 0.46), (-0.26, 0.36)]
    prism(out, -0.04, 0.07, base, "Paint", axis="z", bevel=0.022, seg=2, M=M)
    prism([(-0.12, 0.04), (0.12, 0.04), (0.13, 0.4), (0.09, 0.45), (-0.09, 0.45), (-0.13, 0.4)], -0.048, -0.04,
          acc, "Paint", axis="z", M=M)
    prism([(-0.1, 0.61), (0.1, 0.61), (0.1, 0.7), (-0.1, 0.7)], -0.046, -0.04, acc, "Paint", axis="z", M=M)
    for sgn in (-1, 1):       # side wings
        wing = [(sgn * 0.2, 0.03), (sgn * 0.27, 0.05), (sgn * 0.27, 0.38), (sgn * 0.2, 0.44)]
        prism(wing, -0.13, 0.0, base, "Paint", axis="z", bevel=0.02, seg=2, M=M)
    if bucket:
        box((0.1, 0.05, 0.13), (0.015, 0.015, 0.017), "Paint", M=M, pos=(0, 0.535, 0.015), r=0.018)  # the hole
        box((0.06, 0.018, 0.004), (0.95, 0.95, 0.95), "Glow", M=M, pos=(0, 0.655, -0.047))          # lit badge


def interior(car, st):
    sp = car.sp
    it = sp["int"]
    g = car.g
    iz = st["interior"]
    hz = iz["hip_z"]
    hy = car.cf + iz.get("hip_h", 0.24)
    xd = -iz.get("hip_x", 0.37)
    z_fw = car.z_tf
    xin = car.w(0) - car.f["te"](0) - 0.09
    dash = it["dash"]
    # dashboard: side profile (z, y) extruded across the cabin
    y_cowl = car.hood_y(0, g["zc0"], "hood")
    hub = Vector((xd, hy + iz.get("hub_h", 0.37), hz - iz.get("hub_fwd", 0.5)))
    car.hub = hub
    dz = max(0.25, hub.z - iz.get("dash_gap", 0.13) - z_fw)
    prof = [(z_fw - 0.02, car.cf), (z_fw - 0.02, y_cowl - 0.02), (z_fw + 0.1, y_cowl + 0.0),
            (z_fw + dz * 0.75, y_cowl - 0.03), (z_fw + dz, y_cowl - 0.07), (z_fw + dz + 0.03, y_cowl - 0.14),
            (z_fw + dz - 0.02, y_cowl - 0.3), (z_fw + dz - 0.12, car.cf + 0.32), (z_fw + 0.2, car.cf + 0.1)]
    prism(prof, -xin, xin, dash, "Paint", axis="x", bevel=0.015, seg=2)
    # soft-touch upper pad + trim strip + ambient light line
    zt = z_fw + dz + 0.012
    box((2 * xin - 0.04, 0.025, 0.03), it["accent"], "Metal", pos=(0, y_cowl - 0.1, zt))
    box((2 * xin - 0.1, 0.004, 0.006), (0.4, 0.7, 1.0), "Glow", pos=(0, y_cowl - 0.12, zt + 0.012))
    # vents
    for vx in (-0.62, -0.13, 0.13, 0.62):
        box((0.14 if abs(vx) < 0.3 else 0.1, 0.045, 0.02), (0.02, 0.02, 0.022), "Gloss",
            pos=(vx, y_cowl - 0.155, z_fw + dz - 0.003))
    # BMW-style curved display: cluster behind the wheel + central screen, one glass slab angled to the driver
    sy = y_cowl + 0.06
    szz = z_fw + dz - 0.1
    for (x0, x1, yaw) in ((xd - 0.2, xd + 0.2, 0.0), (xd + 0.2, 0.12, -0.28)):
        cx = (x0 + x1) / 2
        wdt = abs(x1 - x0)
        M = T((cx, sy, szz - 0.02 + (0.03 if yaw else 0.0)), [("x", -0.2), ("y", yaw)])
        box((wdt + 0.01, 0.13, 0.025), (0.03, 0.03, 0.035), "Gloss", M=M, r=0.008)
        box((wdt - 0.02, 0.11, 0.004), (0.02, 0.035, 0.07), "Glow", M=M, pos=(0, 0, 0.0135))
        if yaw == 0.0:      # cluster: tacho arc + speed + shift lights
            for k in range(14):
                a = -2.3 + 4.6 * k / 13
                col = (1.0, 0.35, 0.1) if k > 10 else (0.9, 0.9, 0.95)
                box((0.006, 0.02, 0.003), col, "Glow", M=M, pos=(0.09 * math.sin(a) - 0.06, 0.012 + 0.045 * math.cos(a), 0.016),
                    rot=[("z", -a)])
            box((0.07, 0.03, 0.003), (0.95, 0.95, 1.0), "Glow", M=M, pos=(0.08, 0.0, 0.016))
            box((0.12, 0.006, 0.003), (1.0, 0.45, 0.1), "Glow", M=M, pos=(0.0, 0.05, 0.016))
        else:               # infotainment: map-ish tiles
            for k, (tx, ty, tw, th, tc) in enumerate(((-0.06, 0.0, 0.12, 0.09, (0.12, 0.3, 0.2)),
                                                      (0.06, 0.02, 0.1, 0.05, (0.2, 0.35, 0.6)),
                                                      (0.06, -0.03, 0.1, 0.03, (0.8, 0.5, 0.2)))):
                box((tw, th, 0.003), tc, "Glow", M=M, pos=(tx, ty, 0.016))
    # centre console with shifter, iDrive knob, armrest
    cz0 = z_fw + dz - 0.1
    cz1 = hz + 0.25
    prism([(cz0, car.cf), (cz0, y_cowl - 0.32), (cz0 + 0.25, car.cf + 0.34), (cz1, car.cf + 0.34), (cz1, car.cf)],
          -0.1, 0.1, dash, "Paint", axis="x", bevel=0.02)
    box((0.16, 0.012, cz1 - cz0 - 0.4), (0.03, 0.03, 0.035), "Gloss", pos=(0, car.cf + 0.345, (cz0 + cz1) / 2 + 0.1))
    box((0.18, 0.06, 0.3), it["seat"], "Paint", pos=(0, car.cf + 0.37, cz1 - 0.15), r=0.02, seg=2)      # armrest
    rod((0, car.cf + 0.35, cz0 + 0.4), (0, car.cf + 0.44, cz0 + 0.42), 0.022, (0.05, 0.05, 0.055), "Gloss")
    sphere(0.028, (0.05, 0.05, 0.055), "Gloss", pos=(0, car.cf + 0.45, cz0 + 0.42), scale=(0.9, 0.7, 1.3))
    cyl(0.025, 0.02, ALU, "Metal", 20, pos=(0, car.cf + 0.355, cz0 + 0.55), bevel=0.004)
    # seats
    for sx in (-1, 1):
        seat(sx * abs(xd), hy, hz, it, bucket=iz.get("bucket", True))
    # rear bench
    rz = iz.get("rear_z", hz + 0.85)
    if rz is not None:
        rhy = car.cf + iz.get("rear_h", 0.22)
        rw = min(xin - 0.06, 0.62)
        box((2 * rw, 0.12, 0.48), it["seat"], "Paint", pos=(0, rhy - 0.08, rz - 0.18), r=0.04, seg=2, rot=[("x", 0.08)])
        for sx in (-1, 1):
            box((rw - 0.12, 0.03, 0.38), it["seat2"], "Paint", pos=(sx * rw * 0.48, rhy - 0.02, rz - 0.18), r=0.01,
                rot=[("x", 0.08)])
        M = T((0, rhy, rz + 0.02), [("x", iz.get("rear_recline", 0.42))])
        out = [(-rw, 0.0), (rw, 0.0), (rw, 0.5), (rw - 0.08, 0.56), (-rw + 0.08, 0.56), (-rw, 0.5)]
        prism(out, -0.04, 0.08, it["seat"], "Paint", axis="z", bevel=0.03, seg=2, M=M)
        for sx in (-1, 1):
            prism([(sx * rw * 0.2, 0.06), (sx * rw * 0.8, 0.06), (sx * rw * 0.8, 0.46), (sx * rw * 0.2, 0.46)], -0.048,
                  -0.04, it["seat2"], "Paint", axis="z", M=M)
            box((0.24, 0.15, 0.08), it["seat"], "Paint", M=M, pos=(sx * rw * 0.5, 0.63, 0.04), r=0.03, seg=2)
        # parcel shelf between the seat back and the rear window
        ztop = rz + 0.02 + 0.62 * math.sin(iz.get("rear_recline", 0.42))
        if car.z_tr - ztop > 0.05:
            zc_ = (ztop + car.z_tr) / 2
            box((2 * (car.w(zc_) - car.f["te"](zc_) - 0.1), 0.03, car.z_tr - ztop + 0.04), (0.05, 0.05, 0.055),
                "Paint", pos=(0, car.f["e"](car.z_tr) - 0.04, zc_))
    # door cards: armrest, pull, speaker, ambient line, handle (both sides)
    for sx in (-1, 1):
        for (z0, z1) in iz.get("doors", ((z_fw + 0.2, hz + 0.3), (hz + 0.45, hz + 1.0))):
            if z1 <= z0:
                continue
            zc = (z0 + z1) / 2
            xw = sx * (car.w(zc) - car.f["te"](zc) - 0.1)
            e = car.f["e"](zc)
            box((0.06, 0.04, z1 - z0 - 0.1), it["seat"], "Paint", pos=(xw, e - 0.3, zc), r=0.015)
            box((0.012, 0.004, z1 - z0 - 0.15), (0.4, 0.7, 1.0), "Glow", pos=(xw - sx * 0.012, e - 0.12, zc))
            box((0.02, 0.1, 0.1), (0.1, 0.1, 0.11), "Paint", pos=(xw + sx * 0.012, e - 0.47, zc + 0.05), r=0.02)
            box((0.03, 0.025, 0.07), it["accent"], "Metal", pos=(xw - sx * 0.01, e - 0.16, z0 + 0.12), r=0.008)
    # pedals + footrest
    for k, px in enumerate((0.05, -0.1, -0.2)):
        box((0.05 if k else 0.09, 0.09, 0.012), ALU, "Metal", pos=(xd + px + 0.08, car.cf + 0.12, z_fw + 0.12),
            rot=[("x", -0.5)], r=0.004)
    # steering column (the wheel itself is a separate prop at car.hub)
    tilt = math.radians(iz.get("tilt", 22.0))
    car.tilt = tilt
    axis = Vector((0, math.sin(tilt), -math.cos(tilt)))
    rod(hub + axis * 0.06, hub + axis * 0.3, 0.045, (0.05, 0.05, 0.055), "Paint", segs=14, r2=0.06)
    # rear-view mirror at the windshield header
    zh = g["zh"] + 0.06
    yh = car.Yc(zh) - 0.075
    box((0.26, 0.065, 0.02), (0.04, 0.04, 0.045), "Gloss", pos=(0, yh - 0.03, zh + 0.03), r=0.01, rot=[("x", 0.2)])
    box((0.24, 0.05, 0.003), (0.5, 0.55, 0.6), "Metal", pos=(0, yh - 0.03, zh + 0.041), rot=[("x", 0.2)])
    rod((0, yh + 0.03, zh - 0.02), (0, yh - 0.02, zh + 0.02), 0.01, (0.04, 0.04, 0.045), "Gloss")
    # sun visors
    for sx in (-1, 1):
        box((0.36, 0.015, 0.16), it.get("headliner", HEADLINER), "Paint", pos=(sx * 0.33, yh + 0.035, zh + 0.1),
            r=0.006, rot=[("x", 0.12)])
    eye = Vector((xd, hy + iz.get("eye_h", 0.62), hz + iz.get("eye_back", 0.18)))
    car.eye = eye
    car.hip = Vector((xd, hy, hz))


# ----------------------------------------------------------------------------- car specs

INT_BLACK = {"trim": (0.06, 0.06, 0.065), "card": (0.09, 0.09, 0.1), "carpet": (0.05, 0.05, 0.055),
             "seat": (0.08, 0.08, 0.085), "seat2": (0.9, 0.42, 0.1), "dash": (0.07, 0.07, 0.075),
             "accent": (0.55, 0.56, 0.6)}



def body_profile(zF, zR, aF, aR, zc, zb, k):
    """Side-profile curves from a handful of heights (see spec_*):
    nose = hood leading edge (centre), cowl = hood at the windshield base, belt_f / belt_r = beltline at the
    A / C pillar, deck / tail = boot lid at the rear window / at the tail, sh_f / sh_r = shoulder crease,
    clear = ground clearance, sill = rocker bottom, rear_bot = rear bumper bottom, te_* = edge inset."""
    nose, cowl = k["nose"], k["cowl"]
    top, e = [], []
    cr1 = max(0.012, cowl - k["belt_f"])
    for f in (0.0, 0.08, 0.22, 0.42, 0.65, 0.85, 1.0):
        z = zF + (zc - zF) * f
        y = nose + (cowl - nose) * (1 - (1 - f) ** k.get("hood_pow", 1.35))
        top.append((z, y))
        e.append((z, y - lerp(k.get("hood_crown", 0.045), cr1, smooth01(f))))
    mid = (zc + zb) / 2
    e += [(zc + 0.3, lerp(k["belt_f"], k["belt_r"], 0.2)), (mid, lerp(k["belt_f"], k["belt_r"], 0.55)),
          (zb - 0.15, k["belt_r"])]
    top += [(mid, cowl + 0.02), (zb, k["deck"] - 0.005)]
    deck, tail = k["deck"], k["tail"]
    top += [(zb + (zR - zb) * 0.5, lerp(deck, tail, 0.45) + 0.005), (zR - 0.2, tail + 0.012), (zR, tail - 0.01)]
    e += [(zb + 0.05, min(k["belt_r"] + 0.008, deck - 0.02)), (zR - 0.22, tail - k.get("deck_crown", 0.03)),
          (zR, tail - k.get("deck_crown", 0.03) - 0.03)]
    clear, sill = k["clear"], k["sill"]
    bot = [(zF, clear + 0.05), (zF + 0.3, clear + 0.012), (aF, clear), (aR, clear), (aR + 0.5, clear + 0.06),
           (zR, k["rear_bot"])]
    ys = [(zF, sill + 0.005), (zF + 0.45, sill + 0.005), (aF, sill), (0, sill - 0.005), (aR, sill + 0.015),
          (aR + 0.6, k["rear_bot"] - 0.05), (zR, k["rear_bot"])]
    ysh = [(zF, k["sh_f"] - 0.13), (zF + 0.3, k["sh_f"] - 0.07), (aF, k["sh_f"]), (aR, k["sh_r"]), (zR, k["sh_r"] + 0.0)]
    tc = k["te_cab"]
    te = [(zF, k.get("te_nose", 0.05)), (aF, k.get("te_nose", 0.05) + 0.02), (zc, tc - 0.025), (0, tc), (aR, tc),
          (zR, tc - 0.035)]
    return dict(top=sorted(top), e=sorted(e), bot=bot, ys=ys, ysh=ysh, te=te)


def _axes(WB, L, ohf):
    aF, aR = -WB / 2, WB / 2
    return aF, aR, aF - ohf, aR + (L - WB - ohf)


def _gaps_sedan(fr, b, rr, y0=0.295, belt=1.0):
    """Door cut lines (side view, right side): front door leading edge, B-pillar, rear door around the arch,
    sill line."""
    return [[(fr, y0), (fr, 0.72), (fr + 0.03, 0.87), (fr + 0.07, belt - 0.045)],
            [(b + 0.02, y0 - 0.005), (b, belt)],
            [(rr, y0 - 0.015), (rr + 0.01, 0.55), (rr + 0.08, 0.7), (rr + 0.17, 0.8), (rr + 0.21, belt)],
            [(fr, y0), (rr + 0.01, y0)]]


def _gaps_coupe(fr, rr, y0=0.295, belt=1.0):
    return [[(fr, y0), (fr, 0.72), (fr + 0.03, 0.87), (fr + 0.07, belt - 0.045)],
            [(rr + 0.02, y0 - 0.005), (rr + 0.0, 0.6), (rr - 0.02, belt)],
            [(fr, y0), (rr + 0.02, y0)]]


M3_FRONT = dict(
    kidney=dict(pts=[(0.03, 0.748), (0.255, 0.738), (0.262, 0.42), (0.2, 0.33), (0.07, 0.325), (0.035, 0.36)],
                r=[0.02, 0.04, 0.05, 0.05, 0.03, 0.02], frame_w=0.018, slats="hh", pitch=0.045, lift=0.035),
    head=dict(pts=[(0.29, 0.705), (0.33, 0.748), (0.6, 0.738), (0.77, 0.724), (0.835, 0.705), (0.83, 0.66),
                   (0.63, 0.66), (0.5, 0.655), (0.37, 0.645), (0.3, 0.66)],
              drl=[[(0.66, 0.672), (0.672, 0.672), (0.672, 0.702), (0.8, 0.705), (0.8, 0.716), (0.66, 0.714)],
                   [(0.46, 0.667), (0.472, 0.667), (0.472, 0.71), (0.62, 0.713), (0.62, 0.724), (0.46, 0.722)]],
              lens=[(0.73, 0.687, 0.014), (0.54, 0.688, 0.015)],
              blue=[[(0.36, 0.655), (0.44, 0.662), (0.44, 0.668), (0.36, 0.661)]]),
    front=dict(intakes=[[(0.4, 0.25), (0.69, 0.25), (0.73, 0.33), (0.72, 0.57), (0.64, 0.6), (0.42, 0.44)]],
               center=[[(-0.36, 0.215), (0.36, 0.215), (0.3, 0.34), (-0.3, 0.34)]],
               trims_c=[([(-0.74, 0.195), (0.74, 0.195), (0.78, 0.232), (-0.78, 0.232)], PIANO, "Gloss")],
               plate=(0, 0.285)),
)


def spec_m3():
    """BMW M3 Competition (G80) saloon: 4794 x 1903 x 1433, wheelbase 2857, track 1617 / 1605,
    275/35 R19 front, 285/30 R20 rear (modelled as one 20" wheel, 0.679 m tyre)."""
    WB, L, ohf = 2.857, 4.794, 0.86
    aF, aR, zF, zR = _axes(WB, L, ohf)
    zc, zb = -1.0, 1.66
    d = dict(
        name="M3", L=L, W=1.903, H=1.433, WB=WB, TF=1.617, TR=1.605, ohf=ohf,
        tire_od=0.679, rim_in=20, tire_w=0.275, flare=0.022, low_line=(0.42, 0.52, 0.008),
        front=[(0.17, 0.02), (0.24, 0.0), (0.45, 0.0), (0.65, 0.008), (0.72, 0.022), (0.765, 0.05),
               (0.8, 0.12), (0.9, 0.4)],
        rear=[(0.28, 0.1), (0.4, 0.03), (0.55, 0.0), (0.75, 0.008), (0.95, 0.035), (1.02, 0.06), (1.07, 0.1)],
        dome=(zF + 0.45, zc, 0.3, 0.018),
        gh=dict(zc0=zc, kf=0.14, zh=-0.12, kh=0.12, zb0=zb, krb=0.16, zrr=1.0, krr=0.12, a_in=0.05,
                roof=[(-0.15, 1.375), (0.1, 1.418), (0.4, 1.433), (0.72, 1.418), (1.0, 1.372)],
                crown=0.045, xr=[(0.0, 0.665), (0.9, 0.645)], B=(0.15, 0.23, 0.11, 0.19),
                zC=[(0.0, 1.24), (0.2, 1.34), (1.0, 0.9)]),
        int=dict(INT_BLACK, seat=(0.8, 0.36, 0.08), seat2=(0.07, 0.07, 0.075), card=(0.1, 0.1, 0.11)),
        paint=(0.09, 0.36, 0.25), paint_name="Isle of Man Green",
        wheel=dict(style="y", n=5, col=(0.3, 0.31, 0.33), caliper=(0.1, 0.25, 0.75), concave=0.045),
        style=dict(M3_FRONT,
                   badge="M3", roundel_front=(0.787, zF + 0.16),
                   tail=dict(pts=[(0.38, 0.955), (0.6, 0.985), (0.84, 0.985), (0.885, 0.965), (0.89, 0.86), (0.8, 0.835),
                                  (0.62, 0.845), (0.5, 0.9), (0.4, 0.915)],
                             glow=[[(0.6, 0.868), (0.85, 0.862), (0.862, 0.968), (0.838, 0.968), (0.832, 0.89), (0.6, 0.894)],
                                   [(0.42, 0.925), (0.6, 0.945), (0.6, 0.965), (0.42, 0.942)]],
                             hi=[[(0.61, 0.878), (0.83, 0.873), (0.83, 0.879), (0.61, 0.884)]]),
                   rear=dict(diffuser=[(-0.7, 0.19), (0.7, 0.19), (0.74, 0.42), (0.5, 0.45), (-0.5, 0.45), (-0.74, 0.42)],
                             fins=[-0.28, -0.14, 0.0, 0.14, 0.28],
                             reflectors=[(0.8, 0.5, 0.03, 0.12)], plate=(0, 0.62), roundel=(0, 0.97),
                             badge_at=(0.42, 0.85),
                             lip=[(-0.62, zR - 0.21), (0.62, zR - 0.21), (0.6, zR - 0.1), (-0.6, zR - 0.1)]),
                   exhaust=[(0.44, 0.3, 0.048, "round"), (0.57, 0.3, 0.048, "round")],
                   mirror=dict(z=-0.76, y=0.94, cap="carbon"),
                   side=dict(gaps=_gaps_sedan(-0.99, 0.21, 0.99),
                             handles=[(0.02, 0.87, 0.17), (0.92, 0.89, 0.16)],
                             gill=dict(pts=[(-1.12, 0.7), (-0.97, 0.71), (-0.97, 0.775), (-1.1, 0.77)],
                                       slats=[[(-1.1, 0.722), (-0.99, 0.726), (-0.99, 0.732), (-1.1, 0.728)]],
                                       badge="M3", badge_at=(-1.035, 0.752)),
                             skirt=[(-1.0, 0.18), (1.02, 0.18), (1.02, 0.225), (-1.0, 0.225)],
                             fuel=(1.62, 0.86)),
                   interior=dict(hip_z=-0.1, hip_h=0.24, rear_z=0.8, tilt=22.0),
                   ),
    )
    d.update(body_profile(zF, zR, aF, aR, zc, zb, dict(
        nose=0.775, cowl=0.965, belt_f=0.940, belt_r=0.998, deck=1.055, tail=1.045, sh_f=0.8, sh_r=0.88,
        clear=0.13, sill=0.185, rear_bot=0.3, te_nose=0.04, te_cab=0.068)))
    return d


def spec_m4():
    """BMW M4 Competition (G82) coupe: 4794 x 1887 x 1393, wheelbase 2857, track 1617 / 1605, 19"/20"
    (one 20" wheel, 0.679 m tyre). Same nose as the M3, frameless coupe glass, carbon roof."""
    WB, L, ohf = 2.857, 4.794, 0.86
    aF, aR, zF, zR = _axes(WB, L, ohf)
    zc, zb = -0.98, 1.74
    d = dict(
        name="M4", L=L, W=1.887, H=1.393, WB=WB, TF=1.617, TR=1.605, ohf=ohf,
        tire_od=0.679, rim_in=20, tire_w=0.275, flare=0.024, low_line=(0.42, 0.55, 0.009), carbon_roof=True,
        carbon_lip=True,
        front=[(0.17, 0.02), (0.24, 0.0), (0.45, 0.0), (0.65, 0.008), (0.72, 0.022), (0.765, 0.05),
               (0.8, 0.12), (0.9, 0.4)],
        rear=[(0.28, 0.1), (0.4, 0.03), (0.55, 0.0), (0.75, 0.008), (0.95, 0.035), (1.02, 0.06), (1.07, 0.1)],
        dome=(zF + 0.45, zc, 0.3, 0.02),
        gh=dict(zc0=zc, kf=0.14, zh=-0.06, kh=0.12, zb0=zb, krb=0.2, zrr=0.93, krr=0.14, a_in=0.05,
                roof=[(-0.08, 1.335), (0.18, 1.382), (0.42, 1.393), (0.68, 1.372), (0.93, 1.322)],
                crown=0.045, xr=[(0.0, 0.655), (0.9, 0.625)], B=(0.54, 0.57, 0.46, 0.48),
                zC=[(0.0, 1.16), (0.25, 1.25), (1.0, 0.78)], rb=0.08),
        int=dict(INT_BLACK, seat=(0.1, 0.1, 0.11), seat2=(0.75, 0.1, 0.08)),
        paint=(0.95, 0.74, 0.06), paint_name="Sao Paulo Yellow",
        wheel=dict(style="double", n=5, col=(0.07, 0.07, 0.08), kind="Gloss", caliper=(0.8, 0.07, 0.07),
                   concave=0.05),
        style=dict(M3_FRONT,
                   badge="M4", roundel_front=(0.787, zF + 0.16),
                   tail=dict(pts=[(0.36, 0.96), (0.58, 0.99), (0.84, 0.99), (0.885, 0.97), (0.89, 0.87), (0.78, 0.845),
                                  (0.6, 0.86), (0.48, 0.91), (0.38, 0.925)],
                             base=(0.14, 0.01, 0.015),
                             glow=[[(0.58, 0.885), (0.855, 0.872), (0.866, 0.972), (0.842, 0.972), (0.836, 0.897),
                                    (0.58, 0.91)]],
                             hi=[[(0.4, 0.935), (0.58, 0.955), (0.58, 0.962), (0.4, 0.942)],
                                 [(0.6, 0.93), (0.8, 0.935), (0.8, 0.94), (0.6, 0.935)]]),
                   rear=dict(diffuser=[(-0.72, 0.19), (0.72, 0.19), (0.76, 0.43), (0.52, 0.46), (-0.52, 0.46),
                                       (-0.76, 0.43)],
                             fins=[-0.3, -0.15, 0.0, 0.15, 0.3],
                             reflectors=[(0.8, 0.5, 0.03, 0.13)], plate=(0, 0.62), roundel=(0, 0.975),
                             badge_at=(0.42, 0.86),
                             lip=[(-0.64, zR - 0.22), (0.64, zR - 0.22), (0.62, zR - 0.1), (-0.62, zR - 0.1)]),
                   exhaust=[(0.45, 0.3, 0.05, "round"), (0.58, 0.3, 0.05, "round")],
                   mirror=dict(z=-0.74, y=0.94, cap="carbon"),
                   side=dict(gaps=_gaps_coupe(-0.99, 0.62),
                             handles=[(0.42, 0.875, 0.17)],
                             gill=dict(pts=[(-1.12, 0.7), (-0.97, 0.71), (-0.97, 0.775), (-1.1, 0.77)],
                                       slats=[[(-1.1, 0.722), (-0.99, 0.726), (-0.99, 0.732), (-1.1, 0.728)]],
                                       badge="M4", badge_at=(-1.035, 0.752)),
                             skirt=[(-1.0, 0.18), (1.02, 0.18), (1.02, 0.225), (-1.0, 0.225)],
                             fuel=(1.62, 0.87)),
                   interior=dict(hip_z=-0.05, hip_h=0.23, eye_h=0.6, rear_z=0.8, rear_h=0.2, tilt=22.0,
                                 doors=((-0.72, 0.55),)),
                   ),
    )
    d.update(body_profile(zF, zR, aF, aR, zc, zb, dict(
        nose=0.775, cowl=0.96, belt_f=0.935, belt_r=1.008, deck=1.05, tail=1.04, sh_f=0.8, sh_r=0.885,
        clear=0.125, sill=0.18, rear_bot=0.3, te_nose=0.04, te_cab=0.068)))
    return d


def spec_m2():
    """BMW M2 (G87) coupe: 4580 x 1887 x 1403, wheelbase 2747, track 1617 / 1590, 275/35 R19 f,
    285/30 R20 r (one 20" wheel, 0.679 m tyre). Short, boxy, squared-off wide arches."""
    WB, L, ohf = 2.747, 4.58, 0.79
    aF, aR, zF, zR = _axes(WB, L, ohf)
    zc, zb = -0.93, 1.56
    d = dict(
        name="M2", L=L, W=1.887, H=1.403, WB=WB, TF=1.617, TR=1.59, ohf=ohf,
        tire_od=0.679, rim_in=20, tire_w=0.275, flare=0.038, flare_len=1.55, arch_p=2.8, low_line=(0.44, 0.5, 0.01),
        crease_dip=0.015, nose_round=0.8, tail_round=0.88, plan_taper=(0.02, 0.02), nose_len=0.4,
        front=[(0.17, 0.018), (0.24, 0.0), (0.45, 0.0), (0.68, 0.008), (0.76, 0.024), (0.8, 0.055), (0.85, 0.13),
               (0.95, 0.4)],
        rear=[(0.28, 0.08), (0.4, 0.02), (0.55, 0.0), (0.8, 0.005), (0.95, 0.025), (1.02, 0.05), (1.06, 0.09)],
        dome=(zF + 0.4, zc, 0.32, 0.016),
        gh=dict(zc0=zc, kf=0.12, zh=-0.1, kh=0.1, zb0=zb, krb=0.16, zrr=0.86, krr=0.12, a_in=0.05,
                roof=[(-0.12, 1.355), (0.12, 1.395), (0.38, 1.403), (0.62, 1.385), (0.86, 1.342)],
                crown=0.045, xr=[(0.0, 0.655), (0.9, 0.635)], B=(0.48, 0.51, 0.42, 0.44),
                zC=[(0.0, 1.08), (0.25, 1.16), (1.0, 0.72)], rb=0.08),
        int=dict(INT_BLACK, seat=(0.09, 0.09, 0.1), seat2=(0.12, 0.35, 0.8)),
        paint=(0.16, 0.45, 0.82), paint_name="Zandvoort Blue",
        wheel=dict(style="vee", n=5, col=(0.2, 0.21, 0.23), caliper=(0.8, 0.07, 0.07), concave=0.04),
        style=dict(
            badge="M2", roundel_front=(0.81, zF + 0.17),
            kidney=dict(pts=[(0.03, 0.665), (0.3, 0.665), (0.315, 0.475), (0.04, 0.475)], r=[0.03, 0.035, 0.035, 0.03],
                        frame_w=0.01, slats="h", pitch=0.034, slat_t=0.012, lift=0.022),
            head=dict(pts=[(0.34, 0.74), (0.7, 0.75), (0.8, 0.735), (0.8, 0.66), (0.62, 0.625), (0.38, 0.655)],
                      r=0.02,
                      drl=[[(0.6, 0.64), (0.616, 0.64), (0.64, 0.735), (0.624, 0.735)],
                           [(0.47, 0.652), (0.486, 0.652), (0.51, 0.735), (0.494, 0.735)],
                           [(0.52, 0.728), (0.73, 0.735), (0.73, 0.742), (0.52, 0.735)]],
                      lens=[(0.7, 0.69, 0.018), (0.55, 0.69, 0.016)]),
            front=dict(intakes=[[(0.46, 0.25), (0.74, 0.25), (0.79, 0.31), (0.77, 0.58), (0.66, 0.56), (0.47, 0.44)]],
                       center=[[(-0.38, 0.22), (0.38, 0.22), (0.4, 0.43), (-0.4, 0.43)]],
                       trims_c=[([(-0.74, 0.195), (0.74, 0.195), (0.78, 0.23), (-0.78, 0.23)], PIANO, "Gloss")],
                       plate=(0, 0.33), plate_lift=0.02),
            tail=dict(pts=[(0.44, 0.97), (0.84, 0.975), (0.88, 0.95), (0.88, 0.87), (0.7, 0.86), (0.46, 0.92)],
                      glow=[[(0.62, 0.885), (0.86, 0.885), (0.865, 0.96), (0.845, 0.96), (0.842, 0.905), (0.62, 0.905)],
                            [(0.47, 0.93), (0.6, 0.945), (0.6, 0.96), (0.47, 0.945)]],
                      hi=[[(0.63, 0.925), (0.83, 0.925), (0.83, 0.93), (0.63, 0.93)]]),
            rear=dict(diffuser=[(-0.7, 0.19), (0.7, 0.19), (0.72, 0.4), (-0.72, 0.4)], fins=[-0.24, -0.08, 0.08, 0.24],
                      reflectors=[(0.8, 0.52, 0.03, 0.14), (0.74, 0.52, 0.012, 0.12)], plate=(0, 0.6),
                      roundel=(0, 0.985), badge_at=(0.44, 0.86),
                      lip=[(-0.6, zR - 0.2), (0.6, zR - 0.2), (0.58, zR - 0.1), (-0.58, zR - 0.1)]),
            exhaust=[(0.44, 0.29, 0.046, "round"), (0.56, 0.29, 0.046, "round")],
            mirror=dict(z=-0.68, y=0.94, cap="carbon"),
            side=dict(gaps=_gaps_coupe(-0.94, 0.56),
                      handles=[(0.36, 0.87, 0.17)],
                      skirt=[(-0.95, 0.18), (0.96, 0.18), (0.96, 0.23), (-0.95, 0.23)],
                      fuel=(1.52, 0.86)),
            hood_vents=[[(0.2, zF + 0.3), (0.33, zF + 0.3), (0.35, zF + 0.42), (0.22, zF + 0.42)]],
            interior=dict(hip_z=-0.06, hip_h=0.23, eye_h=0.61, rear_z=0.72, rear_h=0.2, tilt=22.0,
                          doors=((-0.66, 0.5),)),
        ),
    )
    d.update(body_profile(zF, zR, aF, aR, zc, zb, dict(
        nose=0.805, cowl=0.965, belt_f=0.940, belt_r=0.978, deck=1.04, tail=1.035, sh_f=0.81, sh_r=0.87,
        clear=0.125, sill=0.19, rear_bot=0.3, te_nose=0.038, te_cab=0.066, hood_pow=1.25)))
    return d


def spec_m5():
    """BMW M5 (G90) saloon: 5096 x 1970 x 1510, wheelbase 3006, track 1684 / 1660, 285/40 R20 f,
    295/35 R21 r (one 21" wheel, 0.74 m tyre). Big, flared arches, glowing kidney contour."""
    WB, L, ohf = 3.006, 5.096, 0.94
    aF, aR, zF, zR = _axes(WB, L, ohf)
    zc, zb = -1.05, 1.82
    d = dict(
        name="M5", L=L, W=1.97, H=1.51, WB=WB, TF=1.684, TR=1.66, ohf=ohf,
        tire_od=0.74, rim_in=21, tire_w=0.295, flare=0.04, flare_len=2.0, low_line=(0.46, 0.56, 0.008),
        nose_round=0.8,
        front=[(0.18, 0.018), (0.26, 0.0), (0.45, 0.0), (0.68, 0.008), (0.77, 0.024), (0.82, 0.055), (0.86, 0.12),
               (0.95, 0.38)],
        rear=[(0.3, 0.1), (0.42, 0.03), (0.6, 0.0), (0.8, 0.006), (0.98, 0.03), (1.06, 0.06), (1.1, 0.1)],
        dome=(zF + 0.5, zc, 0.34, 0.012),
        gh=dict(zc0=zc, kf=0.13, zh=-0.1, kh=0.12, zb0=zb, krb=0.16, zrr=1.15, krr=0.12, a_in=0.06,
                roof=[(-0.12, 1.45), (0.2, 1.497), (0.55, 1.51), (0.9, 1.493), (1.17, 1.447)],
                crown=0.045, xr=[(0.0, 0.685), (1.0, 0.665)], B=(0.2, 0.29, 0.16, 0.25),
                zC=[(0.0, 1.38), (0.2, 1.48), (1.0, 1.02)]),
        int=dict(INT_BLACK, seat=(0.55, 0.07, 0.07), seat2=(0.08, 0.08, 0.085)),
        paint=(0.08, 0.28, 0.66), paint_name="Marina Bay Blue",
        wheel=dict(style="multi", n=10, col=(0.16, 0.16, 0.18), caliper=(0.1, 0.25, 0.75), concave=0.05),
        style=dict(
            badge="M5", roundel_front=(0.845, zF + 0.19),
            kidney=dict(pts=[(0.03, 0.8), (0.33, 0.79), (0.37, 0.67), (0.34, 0.575), (0.06, 0.575), (0.03, 0.62)],
                        r=[0.03, 0.04, 0.03, 0.04, 0.03, 0.03], frame_w=0.016, slats="hh", pitch=0.05, lift=0.03,
                        glow=True),
            head=dict(pts=[(0.4, 0.81), (0.8, 0.8), (0.88, 0.78), (0.87, 0.745), (0.64, 0.745), (0.44, 0.765)],
                      drl=[[(0.55, 0.752), (0.565, 0.752), (0.58, 0.8), (0.565, 0.8)],
                           [(0.72, 0.75), (0.735, 0.75), (0.75, 0.796), (0.735, 0.796)],
                           [(0.45, 0.8), (0.84, 0.792), (0.84, 0.798), (0.45, 0.806)]],
                      lens=[(0.65, 0.772, 0.014), (0.8, 0.768, 0.013)]),
            front=dict(intakes=[[(0.5, 0.26), (0.78, 0.26), (0.81, 0.35), (0.79, 0.6), (0.7, 0.63), (0.52, 0.45)]],
                       center=[[(-0.44, 0.22), (0.44, 0.22), (0.4, 0.44), (-0.4, 0.44)]],
                       trims_c=[([(-0.8, 0.2), (0.8, 0.2), (0.84, 0.235), (-0.84, 0.235)], PIANO, "Gloss")],
                       plate=(0, 0.33), plate_lift=0.016),
            tail=dict(pts=[(0.42, 1.035), (0.9, 1.03), (0.94, 1.0), (0.935, 0.945), (0.64, 0.955), (0.44, 0.99)],
                      glow=[[(0.64, 0.965), (0.91, 0.957), (0.915, 1.02), (0.895, 1.02), (0.892, 0.975), (0.64, 0.98)],
                            [(0.45, 1.0), (0.62, 1.012), (0.62, 1.022), (0.45, 1.01)]],
                      hi=[[(0.65, 1.0), (0.88, 0.995), (0.88, 1.0), (0.65, 1.005)]]),
            rear=dict(diffuser=[(-0.72, 0.2), (0.72, 0.2), (0.76, 0.44), (-0.76, 0.44)], fins=[-0.26, -0.13, 0.0, 0.13, 0.26],
                      reflectors=[(0.84, 0.52, 0.03, 0.14)], plate=(0, 0.64), roundel=(0, 1.06), badge_at=(0.46, 0.9),
                      lip=[(-0.64, zR - 0.22), (0.64, zR - 0.22), (0.62, zR - 0.1), (-0.62, zR - 0.1)]),
            exhaust=[(0.5, 0.32, 0.05, "round"), (0.63, 0.32, 0.05, "round")],
            mirror=dict(z=-0.8, y=0.99, cap="carbon"),
            side=dict(gaps=_gaps_sedan(-1.08, 0.28, 1.06, belt=1.04),
                      handles=[(0.1, 0.9, 0.2), (1.0, 0.92, 0.19)], handle_col=CHROME, handle_kind="Metal",
                      gill=dict(pts=[(-1.2, 0.74), (-1.08, 0.745), (-1.08, 0.78), (-1.19, 0.776)],
                                slats=[], badge="M5", badge_at=(-1.14, 0.76)),
                      skirt=[(-1.08, 0.2), (1.08, 0.2), (1.08, 0.24), (-1.08, 0.24)],
                      fuel=(1.78, 0.91)),
            interior=dict(hip_z=-0.08, hip_h=0.25, eye_h=0.63, rear_z=0.9, tilt=21.0),
        ),
    )
    d.update(body_profile(zF, zR, aF, aR, zc, zb, dict(
        nose=0.84, cowl=1.02, belt_f=0.985, belt_r=1.043, deck=1.09, tail=1.08, sh_f=0.84, sh_r=0.93,
        clear=0.13, sill=0.2, rear_bot=0.32, te_nose=0.04, te_cab=0.075)))
    return d


def spec_540i():
    """BMW 540i (G60) saloon: 5060 x 1900 x 1515, wheelbase 2995, track 1625 / 1655, 245/45 R19 f,
    275/40 R19 r (one 19" wheel, 0.703 m tyre). The smooth executive car: chrome trim, vertical slats."""
    WB, L, ohf = 2.995, 5.06, 0.93
    aF, aR, zF, zR = _axes(WB, L, ohf)
    zc, zb = -1.05, 1.82
    d = dict(
        name="540i", L=L, W=1.9, H=1.515, WB=WB, TF=1.625, TR=1.655, ohf=ohf,
        tire_od=0.703, rim_in=19, tire_w=0.255, flare=0.012, low_line=(0.46, 0.56, 0.006), nose_round=0.8,
        front=[(0.18, 0.018), (0.26, 0.0), (0.45, 0.0), (0.68, 0.008), (0.77, 0.024), (0.82, 0.055), (0.86, 0.12),
               (0.95, 0.38)],
        rear=[(0.3, 0.1), (0.42, 0.03), (0.6, 0.0), (0.8, 0.006), (0.98, 0.03), (1.06, 0.06), (1.1, 0.1)],
        dome=(zF + 0.5, zc, 0.34, 0.008),
        gh=dict(zc0=zc, kf=0.13, zh=-0.1, kh=0.12, zb0=zb, krb=0.16, zrr=1.15, krr=0.12, a_in=0.06,
                roof=[(-0.12, 1.455), (0.2, 1.502), (0.55, 1.515), (0.9, 1.498), (1.17, 1.452)],
                crown=0.045, xr=[(0.0, 0.665), (1.0, 0.645)], B=(0.2, 0.29, 0.16, 0.25),
                zC=[(0.0, 1.38), (0.2, 1.48), (1.0, 1.02)], trim=CHROME, trim_top=CHROME),
        int=dict(INT_BLACK, seat=(0.5, 0.25, 0.11), seat2=(0.44, 0.21, 0.09), card=(0.3, 0.16, 0.08),
                 accent=(0.7, 0.71, 0.74)),
        paint=(0.12, 0.2, 0.42), paint_name="Phytonic Blue",
        wheel=dict(style="double", n=5, col=(0.74, 0.75, 0.77), caliper=(0.24, 0.24, 0.26), concave=0.025),
        style=dict(
            badge="540i", roundel_front=(0.845, zF + 0.19),
            kidney=dict(pts=[(0.03, 0.805), (0.27, 0.8), (0.29, 0.62), (0.25, 0.55), (0.05, 0.55), (0.03, 0.6)],
                        r=[0.03, 0.04, 0.04, 0.04, 0.03, 0.03], frame_w=0.016, slats="v", pitch=0.032, lift=0.028,
                        frame=CHROME, slat_col=CHROME, glow=True),
            head=dict(pts=[(0.36, 0.81), (0.78, 0.8), (0.86, 0.78), (0.85, 0.745), (0.62, 0.742), (0.4, 0.765)],
                      drl=[[(0.52, 0.752), (0.535, 0.752), (0.55, 0.8), (0.535, 0.8)],
                           [(0.7, 0.75), (0.715, 0.75), (0.73, 0.795), (0.715, 0.795)],
                           [(0.41, 0.8), (0.82, 0.792), (0.82, 0.798), (0.41, 0.806)]],
                      lens=[(0.62, 0.772, 0.014), (0.78, 0.768, 0.013)], bezel=(0.5, 0.52, 0.55)),
            front=dict(intakes=[[(0.56, 0.27), (0.8, 0.27), (0.83, 0.33), (0.78, 0.46), (0.6, 0.43)]],
                       center=[[(-0.42, 0.22), (0.42, 0.22), (0.38, 0.4), (-0.38, 0.4)]],
                       trims=[([(0.56, 0.47), (0.8, 0.49), (0.8, 0.5), (0.56, 0.48)], CHROME, "Metal")],
                       plate=(0, 0.32), plate_lift=0.016),
            tail=dict(pts=[(0.4, 1.035), (0.88, 1.03), (0.93, 1.0), (0.925, 0.955), (0.62, 0.96), (0.42, 0.99)],
                      glow=[[(0.62, 0.968), (0.9, 0.962), (0.905, 1.02), (0.885, 1.02), (0.882, 0.978), (0.62, 0.982)],
                            [(0.43, 1.0), (0.6, 1.012), (0.6, 1.022), (0.43, 1.01)]]),
            rear=dict(trims_c=[([(-0.62, 0.36), (0.62, 0.36), (0.62, 0.37), (-0.62, 0.37)], CHROME, "Metal")],
                      diffuser=[(-0.66, 0.22), (0.66, 0.22), (0.68, 0.34), (-0.68, 0.34)], fins=[],
                      reflectors=[(0.82, 0.5, 0.025, 0.12)], plate=(0, 0.64), roundel=(0, 1.06), badge_at=(0.5, 0.92),
                      script_at=(-0.5, 0.92)),
            exhaust=[(0.46, 0.24, 0.035, "round")], tip_out=-0.02,
            mirror=dict(z=-0.8, y=0.99, cap="paint"),
            side=dict(gaps=_gaps_sedan(-1.08, 0.28, 1.06, belt=1.04),
                      handles=[(0.1, 0.9, 0.2), (1.0, 0.92, 0.19)], handle_col=CHROME, handle_kind="Metal",
                      trims=[([(-0.95, 0.3), (0.95, 0.3), (0.95, 0.31), (-0.95, 0.31)], CHROME, "Metal")],
                      fuel=(1.78, 0.91)),
            interior=dict(hip_z=-0.08, hip_h=0.25, eye_h=0.63, rear_z=0.9, tilt=21.0, bucket=False),
        ),
    )
    d.update(body_profile(zF, zR, aF, aR, zc, zb, dict(
        nose=0.84, cowl=1.02, belt_f=0.985, belt_r=1.043, deck=1.09, tail=1.08, sh_f=0.84, sh_r=0.93,
        clear=0.14, sill=0.21, rear_bot=0.33, te_nose=0.04, te_cab=0.07)))
    return d


def spec_m8():
    """BMW M8 Competition Coupe (F92): 4867 x 1907 x 1362, wheelbase 2827, track 1627 / 1631,
    275/35 R20 f, 285/35 R20 r (one 20" wheel, 0.705 m tyre). Long low GT, single-frame kidney."""
    WB, L, ohf = 2.827, 4.867, 0.94
    aF, aR, zF, zR = _axes(WB, L, ohf)
    zc, zb = -0.86, 1.72
    d = dict(
        name="M8", L=L, W=1.907, H=1.362, WB=WB, TF=1.627, TR=1.631, ohf=ohf,
        tire_od=0.705, rim_in=20, tire_w=0.285, flare=0.03, flare_len=2.0, low_line=(0.4, 0.52, 0.01),
        carbon_roof=True, nose_round=0.78, tail_round=0.86,
        front=[(0.16, 0.02), (0.24, 0.0), (0.42, 0.0), (0.58, 0.01), (0.66, 0.03), (0.71, 0.065), (0.75, 0.13),
               (0.85, 0.42)],
        rear=[(0.28, 0.1), (0.4, 0.03), (0.55, 0.0), (0.75, 0.008), (0.92, 0.035), (0.97, 0.06), (1.01, 0.1)],
        dome=(zF + 0.5, zc, 0.3, 0.016),
        gh=dict(zc0=zc, kf=0.16, zh=0.02, kh=0.12, zb0=zb, krb=0.22, zrr=0.86, krr=0.14, a_in=0.05,
                roof=[(0.0, 1.31), (0.25, 1.352), (0.48, 1.362), (0.7, 1.34), (0.88, 1.29)],
                crown=0.045, xr=[(0.0, 0.645), (0.9, 0.615)], B=(0.54, 0.57, 0.46, 0.48),
                zC=[(0.0, 1.12), (0.28, 1.2), (1.0, 0.72)], rb=0.08),
        int=dict(INT_BLACK, seat=(0.75, 0.74, 0.72), seat2=(0.08, 0.08, 0.085), card=(0.12, 0.12, 0.13)),
        paint=(0.5, 0.03, 0.05), paint_name="Motegi Red",
        wheel=dict(style="vee", n=5, col=(0.17, 0.17, 0.19), caliper=(0.86, 0.62, 0.12), concave=0.05),
        style=dict(
            badge="M8", roundel_front=(0.745, zF + 0.17),
            kidney=dict(pts=[(-0.3, 0.63), (0.3, 0.63), (0.37, 0.47), (0.33, 0.43), (-0.33, 0.43), (-0.37, 0.47)],
                        r=[0.03, 0.03, 0.03, 0.04, 0.04, 0.03], frame_w=0.016, slats="hh", pitch=0.04, lift=0.03,
                        single=True, divider=True),
            head=dict(pts=[(0.38, 0.625), (0.44, 0.66), (0.78, 0.7), (0.84, 0.69), (0.83, 0.655), (0.7, 0.64),
                           (0.46, 0.615)],
                      drl=[[(0.5, 0.628), (0.513, 0.628), (0.513, 0.655), (0.62, 0.667), (0.62, 0.676), (0.5, 0.664)],
                           [(0.65, 0.645), (0.663, 0.645), (0.663, 0.672), (0.78, 0.686), (0.78, 0.694), (0.65, 0.681)]],
                      lens=[(0.57, 0.64, 0.011), (0.72, 0.66, 0.011)],
                      blue=[[(0.43, 0.623), (0.48, 0.626), (0.48, 0.632), (0.43, 0.629)]]),
            front=dict(intakes=[[(0.44, 0.2), (0.72, 0.2), (0.75, 0.3), (0.73, 0.54), (0.66, 0.58), (0.47, 0.41)]],
                       center=[[(-0.36, 0.2), (0.36, 0.2), (0.33, 0.39), (-0.33, 0.39)]],
                       trims_c=[([(-0.74, 0.18), (0.74, 0.18), (0.78, 0.215), (-0.78, 0.215)], PIANO, "Gloss")],
                       plate=(0, 0.3), plate_lift=0.016),
            tail=dict(pts=[(0.34, 0.955), (0.84, 0.955), (0.9, 0.93), (0.895, 0.875), (0.64, 0.885), (0.38, 0.925)],
                      glow=[[(0.6, 0.895), (0.87, 0.888), (0.875, 0.945), (0.855, 0.945), (0.852, 0.905), (0.6, 0.91)],
                            [(0.36, 0.935), (0.58, 0.94), (0.58, 0.948), (0.36, 0.943)]],
                      hi=[[(0.61, 0.925), (0.85, 0.922), (0.85, 0.927), (0.61, 0.93)]]),
            rear=dict(diffuser=[(-0.72, 0.19), (0.72, 0.19), (0.76, 0.42), (0.5, 0.44), (-0.5, 0.44), (-0.76, 0.42)],
                      fins=[-0.3, -0.15, 0.0, 0.15, 0.3],
                      reflectors=[(0.8, 0.5, 0.03, 0.12)], plate=(0, 0.6), roundel=(0, 0.96), badge_at=(0.44, 0.85),
                      lip=[(-0.66, zR - 0.2), (0.66, zR - 0.2), (0.62, zR - 0.09), (-0.62, zR - 0.09)]),
            exhaust=[(0.47, 0.3, 0.048, "round"), (0.6, 0.3, 0.048, "round")],
            mirror=dict(z=-0.62, y=0.9, cap="carbon"),
            side=dict(gaps=_gaps_coupe(-0.98, 0.62, belt=0.97),
                      handles=[(0.4, 0.84, 0.17)], handle_col=CHROME, handle_kind="Metal",
                      gill=dict(pts=[(-1.1, 0.64), (-0.95, 0.66), (-0.94, 0.72), (-1.08, 0.71)],
                                slats=[[(-1.08, 0.668), (-0.96, 0.678), (-0.96, 0.684), (-1.08, 0.674)],
                                       [(-1.08, 0.688), (-0.96, 0.698), (-0.96, 0.704), (-1.08, 0.694)]],
                                badge="M8", badge_at=(-1.02, 0.70)),
                      skirt=[(-0.98, 0.17), (1.0, 0.17), (1.0, 0.215), (-0.98, 0.215)],
                      fuel=(1.62, 0.85)),
            interior=dict(hip_z=0.1, hip_h=0.21, eye_h=0.58, rear_z=0.85, rear_h=0.18, tilt=23.0,
                          doors=((-0.6, 0.55),)),
        ),
    )
    d.update(body_profile(zF, zR, aF, aR, zc, zb, dict(
        nose=0.745, cowl=0.935, belt_f=0.905, belt_r=0.968, deck=1.0, tail=0.99, sh_f=0.77, sh_r=0.86,
        clear=0.12, sill=0.175, rear_bot=0.29, te_nose=0.04, te_cab=0.07, hood_pow=1.25)))
    return d


COP_BLACK = (0.035, 0.035, 0.04)
COP_WHITE = (0.93, 0.93, 0.94)


def spec_cop():
    """Highway-patrol pursuit sedan, a parody of the Dodge Charger Pursuit (LD): 5100 x 1905 x 1481,
    wheelbase 3052, track 1610 / 1618, 245/55 R18 on black steel wheels (0.727 m tyre). Baked black-and-
    white livery (black nose / hood / roof / boot, white doors), NOT CarPaint."""
    WB, L, ohf = 3.052, 5.1, 0.93
    aF, aR, zF, zR = _axes(WB, L, ohf)
    zc, zb = -0.98, 1.78

    def livery(c, n):
        if abs(n.x) > 0.5 and -1.05 < c.z < 1.16 and 0.26 < c.y < 1.0:
            return COP_WHITE
        return COP_BLACK

    d = dict(
        name="Interceptor", prop="Cop_Interceptor", L=L, W=1.905, H=1.481, WB=WB, TF=1.61, TR=1.618, ohf=ohf,
        tire_od=0.727, rim_in=18, tire_w=0.245, flare=0.018, low_line=(0.5, 0.6, 0.012), crease_dip=0.012,
        nose_round=0.8, tail_round=0.9, plan_taper=(0.02, 0.02), livery=livery, fin_col=COP_BLACK,
        front=[(0.2, 0.03), (0.3, 0.004), (0.5, 0.0), (0.7, 0.01), (0.8, 0.035), (0.84, 0.07), (0.88, 0.15),
               (0.98, 0.42)],
        rear=[(0.32, 0.08), (0.42, 0.02), (0.6, 0.0), (0.85, 0.005), (1.0, 0.025), (1.08, 0.05), (1.12, 0.09)],
        dome=(zF + 0.5, zc, 0.36, 0.012),
        gh=dict(zc0=zc, kf=0.13, zh=-0.1, kh=0.12, zb0=zb, krb=0.18, zrr=1.12, krr=0.12, a_in=0.06,
                roof=[(-0.1, 1.44), (0.3, 1.477), (0.6, 1.481), (0.9, 1.466), (1.15, 1.43)],
                crown=0.045, xr=[(0.0, 0.645), (1.0, 0.625)], B=(0.22, 0.3, 0.18, 0.26),
                zC=[(0.0, 1.3), (0.25, 1.34), (1.0, 0.98)]),
        int=dict(INT_BLACK, seat=(0.1, 0.1, 0.11), seat2=(0.14, 0.14, 0.15), card=(0.1, 0.1, 0.11),
                 accent=(0.4, 0.41, 0.44)),
        paint=COP_BLACK, paint_name="black-and-white livery (baked)",
        wheel=dict(style="steel", n=1, col=(0.05, 0.05, 0.055), kind="Gloss", caliper=(0.2, 0.2, 0.22), concave=0.0),
        style=dict(
            badge="PURSUIT", plate_text="POLICE", roundel_front=None, police=True,
            kidney=dict(pts=[(-0.5, 0.8), (0.5, 0.8), (0.53, 0.66), (0.5, 0.63), (-0.5, 0.63), (-0.53, 0.66)],
                        r=[0.02, 0.02, 0.02, 0.02, 0.02, 0.02], frame_w=0.018, slats="h", pitch=0.026, slat_t=0.009,
                        lift=0.02, single=True, divider=True),
            head=dict(pts=[(0.56, 0.82), (0.84, 0.81), (0.88, 0.78), (0.87, 0.74), (0.58, 0.745)], r=0.01,
                      drl=[[(0.6, 0.8), (0.83, 0.795), (0.83, 0.803), (0.6, 0.808)],
                           [(0.6, 0.755), (0.612, 0.755), (0.612, 0.8), (0.6, 0.8)]],
                      lens=[(0.7, 0.777, 0.02), (0.79, 0.775, 0.018)]),
            front=dict(intakes=[],
                       center=[[(-0.62, 0.26), (0.62, 0.26), (0.58, 0.5), (-0.58, 0.5)]],
                       trims_c=[([(-0.8, 0.22), (0.8, 0.22), (0.83, 0.255), (-0.83, 0.255)], PIANO, "Gloss")],
                       plate=(0, 0.38), plate_lift=0.02),
            tail=dict(pts=[(0.0, 0.955), (0.86, 0.955), (0.905, 0.93), (0.9, 0.86), (0.0, 0.86)], r=0.015,
                      base=(0.2, 0.012, 0.016),
                      glow=[[(0.02, 0.93), (0.85, 0.93), (0.85, 0.942), (0.02, 0.942)],
                            [(0.02, 0.872), (0.85, 0.872), (0.85, 0.884), (0.02, 0.884)],
                            [(0.84, 0.872), (0.874, 0.872), (0.874, 0.942), (0.84, 0.942)]]),
            rear=dict(diffuser=[(-0.7, 0.3), (0.7, 0.3), (0.72, 0.38), (-0.72, 0.38)], fins=[],
                      reflectors=[(0.84, 0.5, 0.025, 0.1)], plate=(0, 0.66), roundel=None, badge_at=(0.5, 0.8),
                      script_at=None),
            exhaust=[(0.55, 0.32, 0.045, "round")],
            mirror=dict(z=-0.72, y=1.03, cap="paint", housing=(COP_BLACK, "Gloss")),
            side=dict(gaps=_gaps_sedan(-1.05, 0.28, 1.1, belt=1.06),
                      handles=[(0.1, 0.9, 0.18), (1.02, 0.92, 0.17)], handle_col=COP_BLACK, handle_kind="Gloss",
                      skirt=None, fuel=(1.8, 0.92)),
            interior=dict(hip_z=-0.05, hip_h=0.26, eye_h=0.64, rear_z=0.95, tilt=21.0, bucket=False),
        ),
    )
    d.update(body_profile(zF, zR, aF, aR, zc, zb, dict(
        nose=0.85, cowl=1.03, belt_f=1.005, belt_r=1.063, deck=1.1, tail=1.09, sh_f=0.86, sh_r=0.95,
        clear=0.15, sill=0.22, rear_bot=0.34, te_nose=0.04, te_cab=0.07, hood_pow=1.2)))
    return d


def police_extras(car, st):
    """Push bumper, A-pillar spotlight, antennas, a laptop on the console and the prisoner partition."""
    sp = car.sp
    zF = car.zF
    zb = zF - 0.11
    PB = (0.05, 0.05, 0.055)
    for sx in (-1, 1):
        box((0.07, 0.62, 0.06), PB, "Metal", pos=(sx * 0.34, 0.55, zb), r=0.01)
        box((0.09, 0.5, 0.03), (0.02, 0.02, 0.022), "Paint", pos=(sx * 0.34, 0.56, zb - 0.04), r=0.008)   # push pad
        box((0.05, 0.05, 0.3), PB, "Metal", pos=(sx * 0.3, 0.34, zb + 0.14))                                 # mount
        box((0.05, 0.05, 0.22), PB, "Metal", pos=(sx * 0.34, 0.66, zb + 0.1))
    for y in (0.84, 0.62, 0.4):
        box((0.76, 0.05, 0.05), PB, "Metal", pos=(0, y, zb), r=0.01)
    for sx in (-1, 1):       # grille-mounted flashers (static, dim)
        box((0.12, 0.03, 0.012), (0.9, 0.1, 0.1) if sx < 0 else (0.15, 0.3, 1.0), "Glow", pos=(sx * 0.16, 0.84, zb - 0.03))
    # spotlight on the driver's A-pillar
    g = car.g
    za = g["zc0"] + g["kf"] * 0.8 ** 2 + 0.1
    xe = car.w(za) - car.f["te"](za)
    ye = car.f["e"](za)
    x0 = -(xe + 0.06)
    rod((-(xe - 0.01), ye + 0.02, za + 0.02), (x0, ye + 0.12, za), 0.012, CHROME, "Metal", 8)
    Ms = T((x0, ye + 0.15, za - 0.02), [("x", math.pi / 2)])
    revolve([(0.0, -0.08), (0.05, -0.08), (0.065, -0.02), (0.07, 0.08), (0.0, 0.08)], CHROME, "Metal", 20, M=Ms)
    revolve([(0.062, -0.081), (0.0, -0.081)], LAMP_W, "Glow", 20, M=Ms)
    car.spot = Vector((x0, ye + 0.15, za - 0.1))
    # antennas on the roof and the boot
    zr = g["zrr"] - 0.12
    for sx, h_ in ((-0.25, 0.55), (0.25, 0.38)):
        y0 = car.Yc(zr) - 0.02
        rod((sx, y0, zr), (sx, y0 + h_, zr + 0.02), 0.004, (0.02, 0.02, 0.02), "Paint", 6)
        cyl(0.02, 0.02, (0.02, 0.02, 0.02), "Paint", 10, pos=(sx, y0 + 0.01, zr))
    zt = car.zR - 0.35
    yt = car.hood_y(0.3, zt, "deck")
    rod((0.3, yt, zt), (0.3, yt + 0.7, zt + 0.03), 0.004, (0.02, 0.02, 0.02), "Paint", 6)
    cyl(0.02, 0.02, (0.02, 0.02, 0.02), "Paint", 10, pos=(0.3, yt + 0.01, zt))
    # laptop on a pole mount at the console (screen toward the driver)
    iz = st["interior"]
    hz = iz["hip_z"]
    hy = car.cf + iz.get("hip_h", 0.24)
    base = Vector((0.02, hy + 0.12, hz - 0.45))
    rod((0.02, car.cf + 0.36, hz - 0.35), base, 0.015, (0.1, 0.1, 0.11), "Metal", 8)
    Ml = T(tuple(base), [("y", 0.35)])
    box((0.34, 0.02, 0.24), (0.12, 0.12, 0.13), "Gloss", M=Ml, pos=(0, 0.01, 0), r=0.006)
    Mscr = Ml @ T((0, 0.13, 0.12), [("x", -0.25)])
    box((0.34, 0.24, 0.015), (0.12, 0.12, 0.13), "Gloss", M=Mscr, r=0.006)
    box((0.31, 0.2, 0.003), (0.15, 0.4, 0.3), "Glow", M=Mscr, pos=(0, 0, 0.009))
    box((0.2, 0.03, 0.002), (0.9, 0.9, 0.95), "Glow", M=Mscr, pos=(-0.04, 0.06, 0.011))
    # prisoner partition behind the front seats
    zp = hz + 0.36
    xw = car.w(zp) - car.f["te"](zp) - 0.1
    ytop = car.Yc(zp) - 0.1
    box((2 * xw, 0.05, 0.04), PB, "Metal", pos=(0, ytop, zp))
    box((2 * xw, 0.05, 0.04), PB, "Metal", pos=(0, car.cf + 0.55, zp))
    for k in range(9):
        x = -xw + 0.08 + k * (2 * xw - 0.16) / 8
        box((0.02, car.cf + 0.55 - car.cf, 0.02), PB, "Metal", pos=(x, car.cf + 0.275, zp))
    box((2 * xw - 0.04, ytop - car.cf - 0.58, 0.012), (0.35, 0.4, 0.45), "Glass", pos=(0, (ytop + car.cf + 0.55) / 2, zp))
    car.lightbar = Vector((0.0, car.Yc(0.25) - 0.004, 0.25))


def build_lightbar():
    """Roof light bar: Cop_LightBar (housing, clear lens, white take-down lights), Cop_LightBar_Red (driver /
    left half) and Cop_LightBar_Blue (right half) as separate Glow props so the game can flash them. All three
    share one origin: the centre of the bar's base (put it on REF Cop_Interceptor.lightbar_mount)."""
    L, D = 1.22, 0.28
    PB = (0.05, 0.05, 0.055)
    for sx in (-1, 1):
        for sz in (-1, 1):
            box((0.06, 0.03, 0.05), PB, "Paint", pos=(sx * 0.45, 0.015, sz * 0.08), r=0.008)
    box((L, 0.035, D), PB, "Gloss", pos=(0, 0.045, 0), r=0.01)
    for sx in (-1, 1):
        box((0.05, 0.075, D), PB, "Gloss", pos=(sx * (L / 2 - 0.02), 0.095, 0), r=0.015)
    box((0.12, 0.065, D - 0.04), (0.9, 0.9, 0.92), "Glow", pos=(0, 0.095, 0), r=0.01)            # take-down
    box((L - 0.08, 0.085, D + 0.01), (0.7, 0.72, 0.75), "Glass", pos=(0, 0.1, 0), r=0.02)        # lens
    box((L - 0.02, 0.012, D + 0.02), PB, "Gloss", pos=(0, 0.147, 0), r=0.005)
    finish("Cop_LightBar")
    for nm, sx, col in (("Cop_LightBar_Red", -1, (1.0, 0.08, 0.06)), ("Cop_LightBar_Blue", 1, (0.12, 0.3, 1.0))):
        for k in range(4):
            x = sx * (0.1 + k * 0.125)
            for sz in (-1, 1):
                box((0.1, 0.055, 0.07), col, "Glow", pos=(x, 0.095, sz * 0.07), r=0.01)
        finish(nm)
    REF["Cop_LightBar"] = {"size": (L, 0.155, D), "origin": "base centre", "red_half": "-x (driver side)",
                           "blue_half": "+x"}


SPECS = [spec_m3, spec_m5, spec_m4, spec_m2, spec_m8, spec_540i]
COPS = [spec_cop]


# ----------------------------------------------------------------------------- car assembly

def build_car(sp):
    car = Car(sp)
    name = sp.get("prop", "Bemze_" + sp["name"])
    st = sp["style"]
    shell = car.build_shell()
    gh = car.build_greenhouse()
    inner = car.build_gh_inner()
    S = Surface([shell.bm, gh.bm])
    car.surf = S
    tag("shell")
    liv = sp.get("livery")
    if liv:                        # baked two-tone livery instead of the tintable CarPaint
        shell.recolor(liv)
        gh.recolor(liv)
    shell.emit(sharp=0.7)
    tag("greenhouse")
    gh.emit(sharp=0.7)
    inner.emit(sharp=0.7)
    tag("front")
    hl, pf = front_details(car, S, st)
    tag("rear")
    tl, pr, tips = rear_details(car, S, st)
    tag("side")
    side_details(car, S, st)
    mirrors(car, st)
    antenna(car, st)
    tag("interior")
    interior(car, st)
    if st.get("police"):
        tag("police")
        police_extras(car, st)
    if "--stats" in sys.argv:
        print("STATS", name, {k: v for k, v in STATS.items()})
    STATS.clear()
    ob = finish(name)
    car_refs(car, name, ob, hl, tl, pf, pr, tips)
    if st.get("police"):
        REF[name].update(police_refs(car, st))
    return car


def police_refs(car, st):
    fz = (st["side"]["gaps"][0][0][0] + st["side"]["gaps"][1][1][0]) / 2
    rz = (st["side"]["gaps"][1][1][0] + st["side"]["gaps"][2][0][0]) / 2 + 0.05
    out = {"lightbar_mount": _r3(car.lightbar), "lightbar_props": ["Cop_LightBar", "Cop_LightBar_Red", "Cop_LightBar_Blue"],
           "spotlight": _r3(car.spot), "livery": "baked vertex colours (no CarPaint surface)"}
    for side, sx in (("L", -1), ("R", 1)):
        for door, z in (("front", fz), ("rear", rz)):
            out["door_panel_%s_%s" % (door, side)] = {"center": _r3((sx * (car.w(z) - 0.004), 0.66, z)),
                                                      "normal": (sx * 1.0, 0.0, 0.0)}
    out["trunk_panel"] = {"center": _r3((0.0, 0.8, car.zR - 0.01)), "normal": (0.0, 0.0, 1.0)}
    return out


def car_refs(car, name, ob, hl, tl, pf, pr, tips):
    sp = car.sp
    st = sp["style"]
    Rt = car.Rt
    pts = [R3.transposed() @ v.co for v in ob.data.vertices]
    lo = [min(p[i] for p in pts) for i in range(3)]
    hi = [max(p[i] for p in pts) for i in range(3)]
    # collision box: the body without mirrors, from the sill line to the roof
    bx = sp["W"]
    by0 = 0.1
    by1 = sp["H"]
    bz0, bz1 = car.zF, car.zR
    hz, hy = st["side"]["handles"][0][0], st["side"]["handles"][0][1]
    xh = -(car.w(hz) - 0.0)
    REF[name] = {
        "wheel_FL": _r3((-sp["TF"] / 2, Rt, car.aF)), "wheel_FR": _r3((sp["TF"] / 2, Rt, car.aF)),
        "wheel_RL": _r3((-sp["TR"] / 2, Rt, car.aR)), "wheel_RR": _r3((sp["TR"] / 2, Rt, car.aR)),
        "wheel_radius": round(Rt, 4), "wheel": name + "_Wheel",
        "eye": _r3(car.eye), "hip": _r3(car.hip),
        "steering_hub": _r3(car.hub), "column_tilt_deg": round(math.degrees(car.tilt), 1),
        "headlight_L": _r3((-hl.x, hl.y, hl.z)), "headlight_R": _r3(hl),
        "taillight_L": _r3((-tl.x, tl.y, tl.z)), "taillight_R": _r3(tl),
        "exhaust_tips": [list(t) for t in tips],
        "collision_size": _r3((bx, by1 - by0, bz1 - bz0)),
        "collision_center": _r3((0, (by0 + by1) / 2, (bz0 + bz1) / 2)),
        "door_handle_driver": _r3((xh, hy, hz)),
        "plate_front": _r3(pf), "plate_rear": _r3(pr),
        "bbox_min": _r3(lo), "bbox_max": _r3(hi),
        "paint": sp["paint"], "paint_name": sp.get("paint_name", ""),
        "tris": len([1 for p in ob.data.polygons for _ in range(len(p.vertices) - 2)]),
        "dims": {"length": sp["L"], "width": sp["W"], "height": sp["H"], "wheelbase": sp["WB"],
                 "track_f": sp["TF"], "track_r": sp["TR"], "tire_od": sp["tire_od"], "rim_in": sp["rim_in"]},
    }


# ----------------------------------------------------------------------------- dealership

D_WHITE = (0.9, 0.91, 0.92)
D_GREY = (0.2, 0.21, 0.23)
D_DARK = (0.1, 0.105, 0.115)
D_FLOOR = (0.78, 0.79, 0.8)
D_CONC = (0.55, 0.55, 0.53)
MULLION = (0.16, 0.17, 0.19)


def text_plane(s, size, col, kind="Glow", M=None, fnt="sans", spacing=1.0, stretch=1.0):
    """Flat lettering in the local XY plane facing +Z (then placed with M)."""
    vs, fs = text2d(s, size, fnt, spacing, stretch)
    bm = bmesh.new()
    vv = [bm.verts.new((u, v, 0.0)) for u, v in vs]
    for f in fs:
        try:
            bm.faces.new([vv[i] for i in f])
        except ValueError:
            pass
    return emit(bm, col, kind, M=M, smooth=False, recalc=False)


FACE_Z = Matrix.Rotation(math.pi / 2, 4, "X")     # a prop built facing +Y -> facing +Z


def build_showroom():
    """BEMZE showroom, 30 x 18 m footprint, 7 m tall. Origin = floor centre (floor top y = 0), the glass
    facade faces +Z. Walls are plain slabs (0.3 m) so the game can add box colliders; see REF."""
    W, D, H = 30.0, 18.0, 7.0
    t = 0.3
    hx, hz = W / 2, D / 2
    # floor slab: polished interior + a concrete plinth edge
    box((W + 1.0, 0.3, D + 1.0), D_CONC, "Paint", pos=(0, -0.16, 0))
    box((W - 0.2, 0.02, D - 0.2), D_FLOOR, "Gloss", pos=(0, -0.0, 0))
    for k in range(1, 6):          # floor tile joints
        box((0.012, 0.004, D - 0.3), (0.66, 0.67, 0.69), "Gloss", pos=(-hx + k * W / 6, 0.012, 0))
    for k in range(1, 4):
        box((W - 0.3, 0.004, 0.012), (0.66, 0.67, 0.69), "Gloss", pos=(0, 0.012, -hz + k * D / 4))
    # back wall (dark grey panels) and side walls (white panels with dark reveals)
    box((W, H, t), D_GREY, "Paint", pos=(0, H / 2, -hz + t / 2))
    for k in range(1, 10):
        box((0.03, H - 0.4, 0.02), D_DARK, "Paint", pos=(-hx + k * W / 10, H / 2, -hz + t + 0.01))
    door_w, door_h = 5.0, 3.6          # vehicle delivery door in the right (+x) wall
    dz0 = -2.5
    for sx in (-1, 1):
        x = sx * (hx - t / 2)
        if sx < 0:
            box((t, H, D), D_WHITE, "Paint", pos=(x, H / 2, 0))
        else:
            z_a, z_b = dz0 - door_w / 2, dz0 + door_w / 2
            box((t, H, z_a + hz), D_WHITE, "Paint", pos=(x, H / 2, (-hz + z_a) / 2))
            box((t, H, hz - z_b), D_WHITE, "Paint", pos=(x, H / 2, (z_b + hz) / 2))
            box((t, H - door_h, door_w), D_WHITE, "Paint", pos=(x, (H + door_h) / 2, dz0))
            box((0.08, 0.5, door_w), D_GREY, "Metal", pos=(x + 0.18, door_h + 0.25, dz0))       # roll-up drum
            box((0.4, 0.1, door_w + 0.2), D_GREY, "Metal", pos=(x, door_h + 0.05, dz0))
        for k in range(1, 6):
            box((0.02, H - 0.3, 0.03), D_GREY, "Paint", pos=(x + sx * (t / 2 + 0.005), H / 2, -hz + k * D / 6))
    # roof slab with a front canopy
    box((W + 0.6, 0.45, D + 2.6), D_WHITE, "Paint", pos=(0, H + 0.22, 1.0))
    box((W + 0.64, 0.12, D + 2.64), D_GREY, "Paint", pos=(0, H + 0.5, 1.0))
    # front facade: glass between mullions, a transom, the sign band above, entrance doors in the middle
    fz = hz - 0.06
    ent_w, ent_h = 4.0, 3.0
    transom = 4.6
    band_y0 = 5.0
    n = 12
    for k in range(n + 1):
        x = -hx + k * W / n
        box((0.12, band_y0, 0.2), MULLION, "Metal", pos=(x, band_y0 / 2, fz))
    box((W, 0.14, 0.22), MULLION, "Metal", pos=(0, transom, fz))
    box((W, 0.12, 0.22), MULLION, "Metal", pos=(0, 0.06, fz))
    bm = bmesh.new()
    for k in range(n):
        x0 = -hx + k * W / n + 0.06
        x1 = -hx + (k + 1) * W / n - 0.06
        for (y0, y1) in ((0.12, transom - 0.07), (transom + 0.07, band_y0)):
            if y0 < ent_h and x1 > -ent_w / 2 and x0 < ent_w / 2:
                # entrance bay: glass only above the door head
                y0 = ent_h + 0.1
                if x0 < -ent_w / 2:
                    x1b = -ent_w / 2 - 0.08
                    for (a0, a1) in ((x0, x1b),):
                        vs = [bm.verts.new(p) for p in ((a0, 0.12, fz), (a1, 0.12, fz), (a1, ent_h + 0.1, fz), (a0, ent_h + 0.1, fz))]
                        bm.faces.new(vs)
                if x1 > ent_w / 2:
                    x0b = ent_w / 2 + 0.08
                    vs = [bm.verts.new(p) for p in ((x0b, 0.12, fz), (x1, 0.12, fz), (x1, ent_h + 0.1, fz), (x0b, ent_h + 0.1, fz))]
                    bm.faces.new(vs)
            vs = [bm.verts.new(p) for p in ((x0, y0, fz), (x1, y0, fz), (x1, y1, fz), (x0, y1, fz))]
            bm.faces.new(vs)
    bm2 = bm.copy()                       # both sides visible (outside in, inside out)
    bmesh.ops.reverse_faces(bm2, faces=bm2.faces)
    emit(bm, (0.3, 0.38, 0.45), "Glass", recalc=False, smooth=False)
    emit(bm2, (0.3, 0.38, 0.45), "Glass", recalc=False, smooth=False)
    # entrance: frame + two glass leaves slid open
    for sx in (-1, 1):
        box((0.1, ent_h + 0.1, 0.24), D_DARK, "Metal", pos=(sx * (ent_w / 2 + 0.04), (ent_h + 0.1) / 2, fz))
        box((1.9, ent_h - 0.1, 0.03), (0.3, 0.38, 0.45), "Glass", pos=(sx * (ent_w / 2 + 0.9), ent_h / 2, fz - 0.22))
        box((0.05, ent_h - 0.1, 0.05), D_DARK, "Metal", pos=(sx * (ent_w / 2 + 0.02), ent_h / 2, fz - 0.22))
        box((0.04, 0.9, 0.04), CHROME, "Metal", pos=(sx * (ent_w / 2 + 0.12), 1.1, fz - 0.26))
    box((ent_w + 0.2, 0.12, 0.24), D_DARK, "Metal", pos=(0, ent_h + 0.1, fz))
    box((ent_w, 0.02, 1.4), (0.08, 0.08, 0.09), "Paint", pos=(0, 0.01, fz + 0.9))            # door mat
    # sign band: dark cladding, lit BEMZE letters and the roundel
    box((W + 0.2, H - band_y0 + 0.05, 0.4), D_DARK, "Gloss", pos=(0, (H + band_y0) / 2, hz + 0.05))
    box((W + 0.2, 0.06, 0.42), (0.85, 0.86, 0.9), "Glow", pos=(0, band_y0 + 0.03, hz + 0.05))
    text_plane("BEMZE", 1.35, (0.97, 0.97, 1.0), "Glow", M=T((1.5, (H + band_y0) / 2 + 0.05, hz + 0.26)), spacing=1.25)
    roundel(0.78, 0.0, M=T((-4.2, (H + band_y0) / 2 + 0.03, hz + 0.25)) @ FACE_Z)
    # interior: ceiling light panels
    for i in range(4):
        for j in range(3):
            box((4.0, 0.05, 0.9), (0.97, 0.97, 0.94), "Glow", pos=(-10.5 + i * 7.0, H - 0.03, -5.5 + j * 5.5))
    # back wall: brand graphic
    box((8.0, 2.2, 0.04), D_DARK, "Gloss", pos=(0, 3.4, -hz + t + 0.03))
    text_plane("BEMZE", 0.6, (0.95, 0.95, 0.97), "Glow", M=T((0.9, 3.4, -hz + t + 0.06)), spacing=1.2)
    roundel(0.45, 0.0, M=T((-2.6, 3.4, -hz + t + 0.06)) @ FACE_Z)
    box((8.0, 0.05, 0.05), ORANGE, "Glow", pos=(0, 2.25, -hz + t + 0.06))
    finish("Dealer_Showroom")
    REF["Dealer_Showroom"] = {
        "footprint": (W, D), "height": H, "wall_thickness": t,
        "interior_floor_size": _r3((W - 2 * t, D - 2 * t, 0.0))[:2], "floor_top_y": 0.0,
        "entrance_center": _r3((0, ent_h / 2, hz)), "entrance_size": (ent_w, ent_h),
        "delivery_door_center": _r3((hx, door_h / 2, dz0)), "delivery_door_size": (door_w, door_h),
        "sign_band_center": _r3((0, (H + band_y0) / 2, hz + 0.25)),
        "walls": {"back": {"center": _r3((0, H / 2, -hz + t / 2)), "size": (W, H, t)},
                  "left": {"center": _r3((-(hx - t / 2), H / 2, 0)), "size": (t, H, D)},
                  "right": {"center": _r3((hx - t / 2, H / 2, 0)), "size": (t, H, D), "opening": "delivery_door"},
                  "front_glass": {"center": _r3((0, band_y0 / 2, fz)), "size": (W, band_y0, 0.2), "opening": "entrance"},
                  "roof": {"center": _r3((0, H + 0.22, 1.0)), "size": (W + 0.6, 0.45, D + 2.6)}},
    }


def build_turntable():
    """Round display podium, 5 m across, 0.22 m high, LED ring; origin = floor centre, top at REF top_y."""
    R = 2.5
    revolve([(0, 0), (R, 0), (R, 0.16), (R - 0.03, 0.2), (R - 0.08, 0.22), (0, 0.22)], (0.16, 0.16, 0.18), "Gloss", 72)
    revolve([(R - 0.1, 0.221), (0, 0.221)], (0.62, 0.63, 0.66), "Gloss", 72)            # turning plate
    torus(R - 0.14, 0.012, (0.1, 0.1, 0.11), "Paint", segs=72, rsegs=5, pos=(0, 0.222, 0))   # plate gap
    revolve([(R + 0.004, 0.06), (R + 0.004, 0.11)], (1.0, 0.55, 0.15), "Glow", 72)            # LED ring
    revolve([(R + 0.002, 0.11), (R + 0.002, 0.16)], (0.2, 0.2, 0.22), "Gloss", 72)
    roundel(0.3, 0.221, pos=(0, 0.0, R - 0.55))
    finish("Dealer_Turntable")
    REF["Dealer_Turntable"] = {"radius": R, "top_y": 0.222}


def build_pylon():
    """Roadside brand pylon, 9 m: plinth, dark slab, white faces with the roundel and BEMZE (both sides)."""
    box((2.2, 0.4, 1.0), D_CONC, "Paint", pos=(0, 0.2, 0), r=0.03)
    box((1.8, 8.6, 0.55), D_DARK, "Gloss", pos=(0, 0.4 + 4.3, 0), r=0.04)
    for sz in (1, -1):
        M = T((0, 0, 0), [("y", 0 if sz > 0 else math.pi)])
        box((1.5, 3.2, 0.02), D_WHITE, "Glow", pos=(0, 6.9, 0.28), M=M)
        roundel(0.58, 0.0, M=M @ T((0, 7.55, 0.3)) @ FACE_Z)
        text_plane("BEMZE", 0.36, (0.06, 0.06, 0.08), "Paint", M=M @ T((0.05, 6.05, 0.3)), spacing=1.1)
        box((1.5, 0.05, 0.02), ORANGE, "Glow", pos=(0, 5.6, 0.29), M=M)
        for k, lbl in enumerate(("NEW", "M CARS", "SERVICE")):
            box((1.3, 0.34, 0.02), (0.16, 0.17, 0.19), "Gloss", pos=(0, 4.6 - k * 0.5, 0.28), M=M)
            text_plane(lbl, 0.18, (0.95, 0.95, 0.97), "Glow", M=M @ T((0.02, 4.6 - k * 0.5, 0.3)))
    box((1.84, 0.1, 0.6), D_GREY, "Metal", pos=(0, 9.0, 0))
    finish("Dealer_Pylon")
    REF["Dealer_Pylon"] = {"height": 9.05, "face_center_front": (0, 6.9, 0.29), "face_size": (1.5, 3.2)}


def build_lot_light():
    """Parking lot light: 8 m pole on a concrete footing, twin LED heads (lit faces down)."""
    cyl(0.28, 0.6, D_CONC, "Paint", 20, pos=(0, 0.3, 0), bevel=0.03)
    cyl(0.09, 7.6, D_GREY, "Metal", 14, pos=(0, 0.6 + 3.8, 0), r2=0.06)
    for sx in (-1, 1):
        rod((0, 7.9, 0), (sx * 0.9, 8.05, 0), 0.04, D_GREY, "Metal", 8)
        box((0.7, 0.08, 0.36), D_GREY, "Metal", pos=(sx * 1.15, 8.05, 0), r=0.02)
        box((0.62, 0.012, 0.28), (1.0, 0.98, 0.9), "Glow", pos=(sx * 1.15, 8.005, 0))
    finish("Dealer_LotLight")
    REF["Dealer_LotLight"] = {"light_L": (-1.15, 8.0, 0), "light_R": (1.15, 8.0, 0), "height": 8.1}


def build_flag():
    """Feather flag: bent pole on a cross base, orange / white banner with BEMZE on both sides."""
    for a in (0, math.pi / 2):
        box((0.9, 0.05, 0.08), D_GREY, "Metal", pos=(0, 0.025, 0), rot=[("y", a)])
    pts = []
    for k in range(12):
        u = k / 11
        pts.append(Vector((0.35 * u ** 2.2, 0.05 + 4.2 * u, 0)))
    for k in range(11):
        rod(pts[k], pts[k + 1], 0.018, (0.8, 0.81, 0.83), "Metal", 8)
    # banner: feather outline (x, y) as a thin slab
    out = [(0.02, 0.9), (0.62, 1.0), (0.78, 2.4), (0.72, 3.6), (0.4, 4.15), (0.05, 4.2)]
    prism(out, -0.006, 0.006, D_WHITE, "Paint", axis="z")
    prism([(0.02, 0.9), (0.62, 1.0), (0.66, 1.5), (0.02, 1.45)], -0.008, 0.008, ORANGE, "Paint", axis="z")
    prism([(0.02, 3.95), (0.52, 3.98), (0.4, 4.15), (0.05, 4.2)], -0.008, 0.008, (0.08, 0.08, 0.1), "Paint", axis="z")
    for sz in (1, -1):
        M = T((0.36, 2.55, 0.009 * sz), [("z", math.pi / 2 * (1 if sz > 0 else -1)), ("y", 0 if sz > 0 else math.pi)])
        M = T((0.36, 2.55, 0.009 * sz)) @ Matrix.Rotation(0 if sz > 0 else math.pi, 4, "Y") @ Matrix.Rotation(
            math.pi / 2 * sz, 4, "Z")
        text_plane("BEMZE", 0.3, (0.07, 0.07, 0.09), "Paint", M=M, spacing=1.1)
    finish("Dealer_Flag")
    REF["Dealer_Flag"] = {"height": 4.25}


def build_desk():
    """Sales desk (1.8 x 0.75, 0.76 high) with a monitor, keyboard and the roundel on the front; the
    customer side is +Z, the salesman sits at -Z."""
    box((1.8, 0.05, 0.75), D_WHITE, "Gloss", pos=(0, 0.745, 0), r=0.012)
    prism([(-0.9, 0.0), (0.9, 0.0), (0.9, 0.72), (-0.9, 0.72)], 0.3, 0.36, D_DARK, "Gloss", axis="z", bevel=0.01)
    for sx in (-1, 1):
        box((0.05, 0.72, 0.7), D_DARK, "Gloss", pos=(sx * 0.85, 0.36, 0.0), r=0.01)
    box((1.7, 0.03, 0.05), ORANGE, "Glow", pos=(0, 0.06, 0.37))
    roundel(0.1, 0.0, M=T((0, 0.46, 0.365)) @ FACE_Z)
    # monitor facing the salesman (-z)
    box((0.22, 0.015, 0.16), D_GREY, "Metal", pos=(0.35, 0.778, -0.12), r=0.005)
    box((0.04, 0.26, 0.03), D_GREY, "Metal", pos=(0.35, 0.9, -0.1))
    Mm = T((0.35, 1.08, -0.1), [("y", math.pi), ("x", -0.08)])
    box((0.58, 0.36, 0.03), (0.04, 0.04, 0.045), "Gloss", M=Mm, r=0.008)
    box((0.54, 0.32, 0.004), (0.12, 0.2, 0.35), "Glow", M=Mm, pos=(0, 0, 0.016))
    box((0.4, 0.05, 0.004), (0.9, 0.5, 0.15), "Glow", M=Mm, pos=(-0.04, 0.1, 0.019))
    box((0.4, 0.012, 0.14), (0.12, 0.12, 0.13), "Gloss", pos=(0.3, 0.776, -0.25), r=0.004)
    # brochures + key fob
    box((0.22, 0.012, 0.3), (0.95, 0.95, 0.95), "Paint", pos=(-0.45, 0.776, 0.1), rot=[("y", 0.2)])
    box((0.2, 0.004, 0.26), ORANGE, "Paint", pos=(-0.45, 0.784, 0.1), rot=[("y", 0.2)])
    box((0.035, 0.012, 0.06), (0.05, 0.05, 0.06), "Gloss", pos=(-0.1, 0.776, 0.05), r=0.006)
    finish("Dealer_Desk")
    REF["Dealer_Desk"] = {"top_y": 0.77, "salesman_side": "-z", "monitor_center": (0.35, 1.08, -0.1)}


def build_keybox():
    """Wall key cabinet: origin = centre of its back on the wall, front +Z. 0.7 x 0.9 x 0.14, glass door,
    3 x 4 hooks with keys and tags."""
    w, h, d = 0.7, 0.9, 0.14
    box((w, h, 0.02), D_GREY, "Paint", pos=(0, 0, 0.01))
    for sx in (-1, 1):
        box((0.03, h, d), D_DARK, "Gloss", pos=(sx * (w / 2 - 0.015), 0, d / 2))
    for sy in (-1, 1):
        box((w, 0.03, d), D_DARK, "Gloss", pos=(0, sy * (h / 2 - 0.015), d / 2))
    box((w - 0.06, h - 0.06, 0.004), (0.3, 0.38, 0.45), "Glass", pos=(0, 0, d - 0.006))
    box((0.02, 0.12, 0.02), CHROME, "Metal", pos=(w / 2 - 0.06, 0, d + 0.01))
    text_plane("BEMZE", 0.045, (0.9, 0.9, 0.92), "Metal", M=T((0, h / 2 - 0.1, 0.025)))
    cols = [ORANGE, (0.2, 0.45, 0.9), (0.85, 0.12, 0.12), (0.2, 0.7, 0.3)]
    for r_ in range(4):
        for c in range(3):
            x = -0.2 + c * 0.2
            y = 0.25 - r_ * 0.17
            cyl(0.006, 0.05, CHROME, "Metal", 8, pos=(x, y, 0.045), rot=[("x", math.pi / 2)])
            if (r_ * 3 + c) % 5 != 3:          # a couple of empty hooks
                box((0.03, 0.055, 0.012), (0.05, 0.05, 0.06), "Gloss", pos=(x, y - 0.045, 0.06), r=0.006)
                box((0.035, 0.05, 0.003), cols[(r_ + c) % 4], "Paint", pos=(x, y - 0.1, 0.062))
    finish("Dealer_KeyBox")
    REF["Dealer_KeyBox"] = {"size": (w, h, d), "origin": "back centre on the wall, front +Z"}


def build_dealership():
    tag("dealer")
    build_showroom()
    build_turntable()
    build_pylon()
    build_lot_light()
    build_flag()
    build_desk()
    build_keybox()


# ----------------------------------------------------------------------------- main / export

def export():
    keep = {o.name for o in KIT}
    for o in list(bpy.data.objects):
        if o.name not in keep:
            bpy.data.objects.remove(o)
    total = 0
    for o in KIT:
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        total += tris
        pts = [R3.transposed() @ v.co for v in o.data.vertices]
        lo = [min(p[i] for p in pts) for i in range(3)]
        hi = [max(p[i] for p in pts) for i in range(3)]
        print("  %-24s %6d tris   x[%.3f,%.3f] y[%.3f,%.3f] z[%.3f,%.3f]" % (
            o.name, tris, lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
    print("props:", len(KIT), " tris:", total)
    for name, ref in REF.items():
        for k, v in ref.items():
            print("REF %-18s %-22s %s" % (name, k, v))
    if os.environ.get("BEMZE_REF_JSON"):
        with open(os.environ["BEMZE_REF_JSON"], "w") as fh:
            json.dump(REF, fh, indent=1)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_vertex_color="ACTIVE",
                              export_apply=True, export_yup=True, export_materials="EXPORT",
                              export_normals=True)
    print("wrote", os.path.abspath(OUT), os.path.getsize(OUT) // 1024, "KB")


def main():
    argv = sys.argv[1:]
    only = None
    if "--only" in argv:
        only = set(argv[argv.index("--only") + 1].split(","))
    reset()
    for sf in SPECS + COPS:
        sp = sf()
        prop = sp.get("prop", "Bemze_" + sp["name"])
        if only and not any(n.startswith(prop) for n in only):
            continue
        build_car(sp)
        build_wheel(prop + "_Wheel", sp)
        if sp.get("style", {}).get("police"):
            build_lightbar()
    if not only or "Bemze_SteeringWheel" in only:
        build_steering_wheel()
    if not only or any(n.startswith("Dealer") for n in only):
        build_dealership()
    export()


if __name__ == "__main__":
    main()
