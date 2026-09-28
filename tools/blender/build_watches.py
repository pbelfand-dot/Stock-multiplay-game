"""BAGHOLDERS watch kit — the luxury watches and the watch-store display pieces, built in Blender (bpy).

Run:  python3 tools/blender/build_watches.py                  (needs `pip install bpy==4.5.*`)
      python3 tools/blender/build_watches.py --preview DIR    (also renders Cycles previews into DIR)
      python3 tools/blender/build_watches.py --only Watch_Carrel_Tank,WatchPillow --preview DIR
Out:  assets/props/watches_kit.glb

Same conventions as build_props.py (so PropKit can load it the same way): each prop is ONE mesh whose
surfaces share a handful of materials, colors are baked as vertex colors holding sRGB values, and
coordinates are written in GODOT space (x right, y up, -z = 12 o'clock / back) and converted to
Blender (x, -z, y) on the way in.

  Paint  matte (leather, lacquer, velvet, printing)   Gloss  shiny (dials, ceramic, rubber, gems)
  Metal  cases / bracelets / applied indices          Glow   unshaded (LED strips)
  Glass  see-through (watch crystals, vitrine panes)  <- PropKit needs a transparent "Glass" kind

All brands are parodies (docs/BRANDS.md): Crownwell Genève, Valère & Fils, Audemont Royale,
Renaud Milleaux, Maison Carrel.

WATCHES (real scale, metres). Every watch is modelled "worn": the bracelet / strap closes into a loop
around a wrist-sized oval (the same oval for every watch, see LOOP_*), exactly like a watch buckled
around a display cushion.
  * origin = centre of that loop (= the wrist axis / the cushion axis), dial facing +Y (up),
    12 o'clock toward -Z, crown at +X (3 o'clock), band loop in the YZ plane (axis along X).
  * the case back sits at y = +LOOP_B (0.026); the dial top is ~0.034-0.036; the clasp bottom is at
    about y = -0.030.
  * upright (dial facing the viewer, +Z): rotate -90 deg about X.
  * on a WatchPillow / the WatchCase cushions: put the watch origin on the cushion's mount point.

DISPLAY PIECES (origin on the floor / wall, front = +Z):
  WatchPillow        velvet C-cushion; a watch placed at (0, PILLOW_MOUNT_Y, 0) wraps around it.
  WatchCase          jewellery vitrine counter with 6 cushions (mount points = WATCHCASE_SLOTS).
  WatchBox_Crownwell presentation box with open lid; watch mount at BOX_MOUNT.
  WatchWallShelf     lit wall panel with 4 glass shelves (shelf tops = SHELF_TOPS).
Mount points are also exported as empties parented to each display mesh (…_Slot1, …_Mount).
"""
import math
import os
import random
import sys

import bpy  # noqa: I001  (bpy must be imported before bmesh/mathutils)
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "props", "watches_kit.glb")
TAU = 2 * math.pi

PARTS = []   # parts of the prop being built
KIT = []     # finished props
MARKERS = {}  # prop name -> [(marker name, godot position)]


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ----------------------------------------------------------------------------- materials / emit

KINDS = ("Paint", "Gloss", "Metal", "Glow", "Glass")
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
        MATS[kind] = m
    return MATS[kind]


R3 = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))   # Godot (x, y, z) -> Blender (x, -z, y)
R4 = R3.to_4x4()


def G(v):
    return R3 @ Vector(v)


def T(pos=(0, 0, 0), rot=None, scale=None):
    """Godot-space transform: scale, then rotations [(axis, radians), ...] in order, then translate."""
    m = Matrix.Identity(4)
    if scale is not None:
        s = scale if isinstance(scale, (tuple, list)) else (scale, scale, scale)
        m = Matrix.Diagonal((s[0], s[1], s[2], 1.0))
    for ax, a in rot or []:
        m = Matrix.Rotation(a, 4, ax.upper()) @ m
    return Matrix.Translation(Vector(pos)) @ m


def Ry(theta):
    """Rotation that turns a part pointing at 12 o'clock (-Z) to clock angle theta (clockwise from 12)."""
    return Matrix.Rotation(-theta, 4, "Y")


def clock(theta, r, y=0.0):
    """Point on the dial at clock angle theta (0 = 12 o'clock, clockwise seen from above)."""
    return Vector((r * math.sin(theta), y, -r * math.cos(theta)))


def _sharpen(bm, angle):
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0) > angle:
            e.smooth = False


def emit(bm, col, kind="Paint", M=None, smooth=True, sharp=0.6, recalc=True):
    """Finish a Godot-space bmesh into a part. col: rgb tuple, per-face list, or callable(center, normal)
    evaluated in the part's LOCAL space (before M)."""
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
    me.polygons.foreach_set("use_smooth", [smooth] * len(me.polygons))
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
    return ob


def finish(name, markers=None):
    """Join the parts into one prop mesh with soft 'weighted' normals (+ optional marker empties)."""
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
    for mname, pos in markers or []:
        e = bpy.data.objects.new(mname, None)
        e.empty_display_type = "ARROWS"
        e.empty_display_size = 0.03
        e.location = G(pos)
        bpy.context.scene.collection.objects.link(e)
        e.parent = ob
    MARKERS[name] = markers or []
    KIT.append(ob)
    return ob


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


def revolve_bm(profile, segs, mod=None, closed=False, phase=0.0):
    """Surface of revolution around Y. profile [(r, y), ...]; with the outside on the RIGHT when walking
    the profile (e.g. bottom-centre -> out -> up -> top-centre). mod(theta, r, y, k) -> (r, y)."""
    bm = bmesh.new()
    rings = []
    for k, (r, y) in enumerate(profile):
        if r < 1e-9:
            rings.append([bm.verts.new((0, y, 0))])
            continue
        ring = []
        for i in range(segs):
            th = TAU * i / segs + phase
            rr, yy = mod(th, r, y, k) if mod else (r, y)
            ring.append(bm.verts.new((rr * math.sin(th), yy, -rr * math.cos(th))))
        rings.append(ring)
    pairs = list(range(len(rings) - 1))
    if closed:
        pairs.append(-1)
    for k in pairs:
        a, b = rings[k], rings[k + 1]
        if len(a) == 1 and len(b) == 1:
            continue
        for i in range(segs):
            j = (i + 1) % segs
            if len(a) == 1:
                bm.faces.new((a[0], b[i], b[j]))
            elif len(b) == 1:
                bm.faces.new((a[i], b[0], a[j]))
            else:
                bm.faces.new((a[i], b[i], b[j], a[j]))
    return bm


def revolve(profile, col, kind="Paint", segs=48, pos=(0, 0, 0), rot=None, mod=None, closed=False, M=None,
            smooth=True, sharp=0.6, phase=0.0, recalc=False):
    Mx = (M if M is not None else Matrix.Identity(4)) @ T(pos, rot)
    return emit(revolve_bm(profile, segs, mod, closed, phase), col, kind, Mx, smooth, sharp, recalc=recalc)


def disc(r, y0, y1, col, kind="Paint", segs=32, pos=(0, 0, 0), rot=None, M=None, bevel=0.0, smooth=True):
    """Flat cylinder (dial, coin, date disc) from y0 to y1, optional top bevel."""
    if bevel > 0:
        prof = [(0, y0), (r, y0), (r, y1 - bevel), (r - bevel * 0.3, y1 - bevel * 0.3), (r - bevel, y1), (0, y1)]
    else:
        prof = [(0, y0), (r, y0), (r, y1), (0, y1)]
    return revolve(prof, col, kind, segs, pos, rot, M=M, smooth=smooth)


def _ccw(pts):
    a = 0.0
    for i in range(len(pts)):
        x0, z0 = pts[i]
        x1, z1 = pts[(i + 1) % len(pts)]
        a += x0 * (-z1) - x1 * (-z0)
    return pts if a > 0 else list(reversed(pts))


def prism_bm(poly, y0, y1, bevel=0.0, seg=1):
    """Polygon [(x, z), ...] in the XZ plane extruded from y0 to y1 (top edges optionally beveled)."""
    pts = _ccw(list(poly))
    bm = bmesh.new()
    bot = [bm.verts.new((x, y0, z)) for x, z in pts]
    top = [bm.verts.new((x, y1, z)) for x, z in pts]
    n = len(pts)
    ftop = bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(ftop.edges), offset=bevel, offset_type="OFFSET", segments=seg,
                        profile=0.5, affect="EDGES", clamp_overlap=True)
    return bm


def prism(poly, y0, y1, col, kind="Paint", M=None, bevel=0.0, seg=1, smooth=True, sharp=0.6):
    return emit(prism_bm(poly, y0, y1, bevel, seg), col, kind, M, smooth, sharp)


def loft_bm(rings, cap0=True, cap1=True, closed=True):
    """Skin consecutive rings (equal-length lists of Vector) — cases, sweeps, straps."""
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


def slab_bm(poly_zy, x0, x1, bevel=0.0, seg=2):
    """Side profile [(z, y), ...] extruded along X from x0 to x1 (lugs, brancards), both caps beveled."""
    bm = bmesh.new()
    a = [bm.verts.new((x0, y, z)) for z, y in poly_zy]
    b = [bm.verts.new((x1, y, z)) for z, y in poly_zy]
    n = len(poly_zy)
    f0 = bm.faces.new(a)
    f1 = bm.faces.new(list(reversed(b)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], b[i], b[j], a[j]))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(f0.edges) + list(f1.edges), offset=bevel, offset_type="OFFSET",
                        segments=seg, profile=0.5, affect="EDGES", clamp_overlap=True)
    return bm


def sphere(r, col, kind="Paint", pos=(0, 0, 0), segs=10, rings=6, scale=None, M=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    Mx = (M if M is not None else Matrix.Identity(4)) @ T(pos, scale=scale)
    return emit(bm, col, kind, Mx)


def rod(a, b, r, col, kind="Paint", segs=8, M=None):
    A, B = Vector(a), Vector(b)
    d = B - A
    bm = revolve_bm([(0, 0), (r, 0), (r, d.length), (0, d.length)], segs)
    q = Vector((0, 1, 0)).rotation_difference(d.normalized())
    Mx = (M if M is not None else Matrix.Identity(4)) @ Matrix.Translation(A) @ q.to_matrix().to_4x4()
    return emit(bm, col, kind, Mx)


def torus_bm(R, r, segs=24, rsegs=8, arc=TAU):
    """Ring lying flat in XZ (axis Y)."""
    prof = [(R + r * math.cos(TAU * j / rsegs), r * math.sin(TAU * j / rsegs)) for j in range(rsegs)]
    return revolve_bm(prof, segs, closed=True)


# ----------------------------------------------------------------------------- outlines

def rounded_poly(n, R, corner, phase=0.0, per=4):
    """Regular n-gon of circumradius R, corners rounded with radius `corner` -> [(x, z)] (CCW-ish)."""
    pts = []
    apo = R * math.cos(math.pi / n)
    for k in range(n):
        a = TAU * k / n + phase
        # corner centre sits on the vertex ray, inset so the arc is tangent to both sides
        c_d = (apo - corner) / math.cos(math.pi / n)
        cx, cz = c_d * math.sin(a), -c_d * math.cos(a)
        for j in range(per + 1):
            t = a - math.pi / n + (TAU / n) * j / per
            pts.append((cx + corner * math.sin(t), cz - corner * math.cos(t)))
    return pts


def superellipse(ax, az, p, N=64):
    out = []
    for i in range(N):
        t = TAU * i / N
        s, c = math.sin(t), math.cos(t)
        out.append((ax * math.copysign(abs(s) ** (2 / p), s), -az * math.copysign(abs(c) ** (2 / p), c)))
    return out


def resample_polar(outline, N, phase=0.0):
    """Cast N rays (clock angles) from the origin against a convex outline -> N points (x, z)."""
    out = []
    m = len(outline)
    for i in range(N):
        th = TAU * i / N + phase
        dx, dz = math.sin(th), -math.cos(th)
        best = None
        for k in range(m):
            x0, z0 = outline[k]
            x1, z1 = outline[(k + 1) % m]
            ex, ez = x1 - x0, z1 - z0
            den = dx * ez - dz * ex
            if abs(den) < 1e-15:
                continue
            t = (x0 * ez - z0 * ex) / den
            u = (x0 * dz - z0 * dx) / den
            if t > 0 and -1e-9 <= u <= 1 + 1e-9 and (best is None or t < best):
                best = t
        out.append((dx * best, dz * best))
    return out


def inset(pts, d):
    """Scale-free inset of a star-shaped outline along the rays (good enough for convex case shapes)."""
    out = []
    for x, z in pts:
        L = math.hypot(x, z)
        f = max(L - d, 1e-6) / L
        out.append((x * f, z * f))
    return out


def shaped_ring_bm(outer_fn, inner_fn, profile, N):
    """Closed ring lofted through profile [(which, d, y)]: which='o' offsets the outer outline inward by d,
    which='i' offsets the inner outline outward by d. Outlines are ray-sampled with N rays."""
    rings = []
    O = outer_fn(N)
    I = inner_fn(N)
    for which, d, y in profile:
        src = O if which == "o" else I
        pts = inset(src, d) if which == "o" else inset(src, -d)
        rings.append([Vector((x, y, z)) for x, z in pts])
    bm = bmesh.new()
    vr = [[bm.verts.new(p) for p in r] for r in rings]
    for k in range(len(vr)):
        a, b = vr[k], vr[(k + 1) % len(vr)]
        for i in range(N):
            j = (i + 1) % N
            bm.faces.new((a[i], a[j], b[j], b[i]))
    return bm


def solid_shape_bm(outline_fn, profile, N):
    """Solid lofted through profile [(inset, y)] bottom -> top, capped (cases, dials of any outline)."""
    O = outline_fn(N)
    rings = [[Vector((x, y, z)) for x, z in inset(O, d)] for d, y in profile]
    return loft_bm(rings)


# ----------------------------------------------------------------------------- text / logos

FONT_FILES = {
    "sans": "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "sansr": "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    "serif": "/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf",
    "serifb": "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf",
    "serifi": "/usr/share/fonts/truetype/liberation/LiberationSerif-Italic.ttf",
}
_FONTS = {}


def font(key):
    if key not in _FONTS:
        path = FONT_FILES.get(key)
        _FONTS[key] = bpy.data.fonts.load(path, check_existing=True) if path and os.path.exists(path) else None
    return _FONTS[key]


def text_bm(s, size, fnt="sans", extrude=0.0, spacing=1.0, align="CENTER", res=2, stretch=1.0):
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = s
    f = font(fnt)
    if f is not None:
        cu.font = f
    cu.size = size
    cu.space_character = spacing
    cu.align_x = align
    cu.align_y = "CENTER"
    cu.resolution_u = res
    cu.extrude = extrude
    ob = bpy.data.objects.new("txt", cu)
    bpy.context.scene.collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    for v in bm.verts:    # Blender text plane (x, y, z) -> Godot (x, z, -y); text "up" = toward 12
        x, y, z = v.co
        v.co = Vector((x * stretch, z + extrude, -y))
    return bm


def text(s, size, col, kind="Paint", pos=(0, 0, 0), theta=0.0, fnt="sans", extrude=0.0, spacing=1.0,
         align="CENTER", M=None, stretch=1.0):
    """Flat (or slightly raised) lettering lying on an up-facing surface, reading with its top toward
    clock angle theta (0 = 12 o'clock)."""
    Mx = (M if M is not None else Matrix.Identity(4)) @ Matrix.Translation(Vector(pos)) @ Ry(theta)
    bm = text_bm(s, size, fnt, extrude, spacing, align, res=1 if size < 0.0011 else 2, stretch=stretch)
    return emit(bm, col, kind, Mx, smooth=False, recalc=extrude > 0)


def arc_text(s, size, r, center_theta, y, col, kind="Paint", fnt="sans", step=None, outward=True, M=None):
    """Letters around a circle (bezel / chapter-ring lettering), centred on center_theta."""
    step = step if step is not None else size * 0.75 / r
    n = len(s)
    for i, ch in enumerate(s):
        if ch == " ":
            continue
        th = center_theta + (i - (n - 1) / 2) * step * (1 if outward else -1)
        text(ch, size, col, kind, clock(th, r, y), th if outward else th + math.pi, fnt, M=M)


CROWN_POLY = [(-0.42, 0.34), (0.42, 0.34), (0.42, 0.16), (0.52, -0.3), (0.33, 0.02), (0.25, -0.44),
              (0.11, 0.0), (0.0, -0.5), (-0.11, 0.0), (-0.25, -0.44), (-0.33, 0.02), (-0.52, -0.3),
              (-0.42, 0.16)]
CROWN_TIPS = [(0.52, -0.3), (0.25, -0.44), (0.0, -0.5), (-0.25, -0.44), (-0.52, -0.3)]


def crown_logo(width, y, col, kind="Metal", M=None, h=None, pos=(0, 0, 0), theta=0.0):
    """Crownwell's five-point coronet (points toward 12), lying on an up-facing surface at height y."""
    h = h if h is not None else width * 0.12
    Mx = (M if M is not None else Matrix.Identity(4)) @ Matrix.Translation(Vector(pos)) @ Ry(theta)
    poly = [(x * width, z * width) for x, z in CROWN_POLY]
    prism(poly, y, y + h, col, kind, M=Mx, smooth=False)
    for x, z in CROWN_TIPS:
        sphere(width * 0.085, col, kind, (x * width, y + h * 0.6, z * width - width * 0.03), segs=8, rings=4,
               M=Mx)


# ----------------------------------------------------------------------------- gems

def gem_bm(r, n=8, crown=0.32, table=0.56, pav=0.9):
    bm = bmesh.new()
    g = [bm.verts.new((r * math.sin(TAU * k / n), 0.0, -r * math.cos(TAU * k / n))) for k in range(n)]
    t = [bm.verts.new((table * r * math.sin(TAU * (k + 0.5) / n), crown * r,
                       -table * r * math.cos(TAU * (k + 0.5) / n))) for k in range(n)]
    bm.faces.new(t)
    for k in range(n):
        k1 = (k + 1) % n
        bm.faces.new((g[k], g[k1], t[k]))
        bm.faces.new((t[k], g[k1], t[k1]))
    if pav > 0:
        p = bm.verts.new((0, -pav * r, 0))
        for k in range(n):
            bm.faces.new((g[(k + 1) % n], g[k], p))
    else:
        bm.faces.new(list(reversed(g)))
    return bm


GEM_TONES = [(1.0, 1.0, 1.0), (0.92, 0.96, 1.0), (0.62, 0.68, 0.8), (0.98, 0.98, 0.94), (0.38, 0.42, 0.52),
             (0.8, 0.88, 1.0), (1.0, 0.97, 0.9), (0.52, 0.6, 0.74)]
_gem_rng = random.Random(3)


def gem(r, pos, M=None, n=8, pav=0.9, up=None):
    """Brilliant-ish cut stone. Facets get contrasting white/ice/steel tones so it reads as a diamond."""
    bm = gem_bm(r, n, pav=pav)
    cols = []
    for f in bm.faces:
        if len(f.verts) == n:
            cols.append((1.0, 1.0, 1.0))
        else:
            cols.append(_gem_rng.choice(GEM_TONES))
    Mx = (M if M is not None else Matrix.Identity(4)) @ Matrix.Translation(Vector(pos))
    if up is not None:
        q = Vector((0, 1, 0)).rotation_difference(Vector(up).normalized())
        Mx = Mx @ q.to_matrix().to_4x4()
    return emit(bm, cols, "Gloss", Mx, smooth=False)


# ----------------------------------------------------------------------------- the wrist loop

LOOP_A = 0.033     # half width of the wrist oval (along Z)
LOOP_B = 0.026     # half height (along Y) -> the case back sits at y = LOOP_B
LOOP_P = 3.0       # superellipse exponent (flatter top & bottom than an ellipse)


class Loop:
    def __init__(self, a=LOOP_A, b=LOOP_B, p=LOOP_P, N=3000):
        self.pts = []
        for i in range(N + 1):
            t = TAU * i / N
            s, c = math.sin(t), math.cos(t)
            self.pts.append((b * math.copysign(abs(c) ** (2 / p), c), a * math.copysign(abs(s) ** (2 / p), s)))
        self.cum = [0.0]
        for i in range(1, len(self.pts)):
            (y0, z0), (y1, z1) = self.pts[i - 1], self.pts[i]
            self.cum.append(self.cum[-1] + math.hypot(y1 - y0, z1 - z0))
        self.L = self.cum[-1]

    def point(self, s):
        s %= self.L
        lo, hi = 0, len(self.cum) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if self.cum[mid] <= s:
                lo = mid
            else:
                hi = mid
        f = (s - self.cum[lo]) / max(self.cum[hi] - self.cum[lo], 1e-12)
        (y0, z0), (y1, z1) = self.pts[lo], self.pts[hi]
        return Vector((0.0, y0 + (y1 - y0) * f, z0 + (z1 - z0) * f))

    def frame(self, s, off=0.0):
        """Matrix whose local x = across the band, y = outward (away from the wrist), z = along the band."""
        h = 0.0004
        Tn = (self.point(s + h) - self.point(s - h)).normalized()
        N = Vector((0.0, Tn.z, -Tn.y))
        P = self.point(s) + N * off
        return Matrix(((1, 0, 0, P.x), (0, N.y, Tn.y, P.y), (0, N.z, Tn.z, P.z), (0, 0, 0, 1)))

    def s_for_z(self, z):
        """Arc position on the 6 o'clock half-top where the band reaches z (>0)."""
        lo, hi = 0.0, self.L / 4
        for _ in range(60):
            mid = (lo + hi) / 2
            if self.point(mid).z < z:
                lo = mid
            else:
                hi = mid
        return (lo + hi) / 2


LOOP = Loop()
H0 = LOOP_B


def band_rows(s_a, s_b, pitch):
    n = max(1, round((s_b - s_a) / pitch))
    p = (s_b - s_a) / n
    return [s_a + (i + 0.5) * p for i in range(n)], p


def bracelet(z_lug, row_fn, pitch, w0, w1, clasp_len, clasp_fn, gap=0.0002, filler=None, filler_t=0.0011):
    """Rigid-link bracelet from both lug ends to a clasp centred at the bottom of the loop.
    row_fn(M, w, p, i, side) builds one row in band-local space (x across, y out, z along).
    filler=(col, kind): a thin continuous band under the links so no daylight shows between rows."""
    s6 = LOOP.s_for_z(z_lug) + gap
    s_mid = LOOP.L / 2
    s12 = LOOP.L - s6
    span = s_mid - clasp_len / 2 - s6
    rows6, p = band_rows(s6, s_mid - clasp_len / 2, pitch)
    rows12, _ = band_rows(s_mid + clasp_len / 2, s12, pitch)
    for i, s in enumerate(rows6):
        f = (s - s6) / span
        row_fn(LOOP.frame(s), w0 + (w1 - w0) * f, p, i, 6)
    for i, s in enumerate(reversed(rows12)):
        f = (s12 - s) / span
        row_fn(LOOP.frame(s), w0 + (w1 - w0) * f, p, i, 12)
    if filler:
        for a, b in ((s6, s_mid - clasp_len / 2 + 0.002), (s_mid + clasp_len / 2 - 0.002, s12)):
            flip = a > s_mid
            band_sweep(a, b, (lambda f, fl=flip: (w1 + (w0 - w1) * f if fl else w0 + (w1 - w0) * f) * 0.9),
                       lambda f: filler_t, filler[0], filler[1], step=0.004, r=0.0002, nr=0)
    clasp_fn(s_mid, clasp_len, w1)
    return s6, s12


def band_y(z):
    """Inner (wrist-side) height of the loop where it passes z on the upper half."""
    return LOOP.point(LOOP.s_for_z(z)).y


def pill_profile(L, t, r, n=3, r_bot=0.00015):
    """Link side profile (z, y): flat underside, rounded top corners. Centered on z=0, y from 0 to t."""
    r = min(r, t * 0.95, L * 0.48)
    pts = [(-L / 2 + r_bot, 0.0), (L / 2 - r_bot, 0.0)]
    for j in range(n + 1):
        a = math.pi / 2 * j / n
        pts.append((L / 2 - r + r * math.cos(a), t - r + r * math.sin(a)))
    for j in range(n + 1):
        a = math.pi / 2 + math.pi / 2 * j / n
        pts.append((-L / 2 + r + r * math.cos(a), t - r + r * math.sin(a)))
    return pts


def link(M, x0, x1, L, t, r, col, kind="Metal", z=0.0, y=0.0, cap=0.00022, n=3):
    prof = [(zz + z, yy + y) for zz, yy in pill_profile(L, t, r, n)]
    return emit(slab_bm(prof, x0, x1, cap, 1 if cap > 0 else 0), col, kind, M)


def band_section(w, t, r, nr=2):
    """Rounded-rectangle cross-section (x across, y outward from 0 to t)."""
    pts = []
    corners = [(w / 2 - r, t - r, 0.0), (-w / 2 + r, t - r, math.pi / 2), (-w / 2 + r, r, math.pi),
               (w / 2 - r, r, 1.5 * math.pi)]
    for cx, cy, a0 in corners:
        for j in range(nr + 1):
            a = a0 + (math.pi / 2) * j / max(nr, 1) + (math.pi / 4 if nr == 0 else 0.0)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def band_sweep(s_a, s_b, w_fn, t_fn, col, kind="Paint", off=0.0, step=0.0012, r=0.0006, nr=2,
               tip=0.0, section=None):
    """Flexible band (leather / rubber / clasp blade) following the loop from s_a to s_b.
    w_fn(f), t_fn(f) give width & thickness along it (f = 0..1). tip>0 rounds the s_b end to a point.
    col: tuple or callable(f, k_section_face, ring_index) -> rgb (faces are built ring by ring)."""
    n = max(2, int(abs(s_b - s_a) / step))
    rings = []
    for i in range(n + 1):
        f = i / n
        s = s_a + (s_b - s_a) * f
        w, t = w_fn(f), t_fn(f)
        if tip > 0 and (s_b - s) < tip:
            k = (s_b - s) / tip
            w = w * max(math.sqrt(max(1 - (1 - k) ** 2, 0.0)), 0.18)
        sec = section(f, w, t) if section else band_section(w, t, min(r, t * 0.45, w * 0.45), nr)
        M = LOOP.frame(s, off)
        rings.append([M @ Vector((x, y, 0.0)) for x, y in sec])
    bm = loft_bm(rings)
    if callable(col):
        m = len(rings[0])
        cols = []
        for i in range(n):
            for k in range(m):
                cols.append(col(i / n, k, i))
        cols += [col(0.0, 0, 0), col(1.0, 0, n)]
        return emit(bm, cols, kind, smooth=True, recalc=True)
    return emit(bm, col, kind, smooth=True)


# ----------------------------------------------------------------------------- palette

GOLD = (1.0, 0.8, 0.38)          # polished yellow gold
GOLD_B = (0.9, 0.7, 0.32)        # brushed yellow gold
ROSE = (0.98, 0.7, 0.56)
ROSE_B = (0.88, 0.6, 0.48)
STEEL = (0.84, 0.86, 0.89)
STEEL_B = (0.7, 0.72, 0.75)
WGOLD = (0.9, 0.91, 0.94)        # white gold / platinum
BLACK = (0.035, 0.035, 0.04)
PRINT = (0.06, 0.06, 0.07)
LUME = (0.93, 0.95, 0.86)
CREAM = (0.95, 0.9, 0.77)
CW_GREEN = (0.02, 0.36, 0.17)    # Crownwell green
RED = (0.82, 0.08, 0.05)
ORANGE = (1.0, 0.42, 0.06)
BLUED = (0.07, 0.12, 0.46)

EPS = 0.00004   # printing sits this far above the surface under it


def hand(poly, y, theta, col, kind="Metal", thick=0.00012, M=None):
    Mx = (M if M is not None else Matrix.Identity(4)) @ Ry(theta)
    return prism(poly, y, y + thick, col, kind, M=Mx, smooth=False)


def leaf_poly(L, w, tail=0.0018, n=10):
    """Feuille / leaf hand: pointed lens shape."""
    pts = []
    for i in range(n + 1):
        t = i / n
        z = tail - (L + tail) * t
        x = w / 2 * math.sin(math.pi * t) ** 0.8
        pts.append((x, z))
    for i in range(n - 1, 0, -1):
        t = i / n
        z = tail - (L + tail) * t
        x = w / 2 * math.sin(math.pi * t) ** 0.8
        pts.append((-x, z))
    return pts


def circle_poly(r, n=16, cx=0.0, cz=0.0):
    return [(cx + r * math.sin(TAU * i / n), cz - r * math.cos(TAU * i / n)) for i in range(n)]


def flat_rect(w, L, col, kind="Paint", M=None, pos=(0, 0, 0)):
    """Single up-facing quad (printing)."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, 0.0, z)) for x, z in ((-w / 2, L / 2), (w / 2, L / 2), (w / 2, -L / 2), (-w / 2, -L / 2))]
    bm.faces.new(vs)
    Mx = (M if M is not None else Matrix.Identity(4)) @ Matrix.Translation(Vector(pos))
    return emit(bm, col, kind, Mx, smooth=False, recalc=False)


def minute_track(r0, r1, y, col, n=60, w=0.00012, major=5, r_major=None, M=None, skip=()):
    for k in range(n):
        if k in skip:
            continue
        th = TAU * k / n
        big = k % major == 0
        a = r_major if (big and r_major) else r0
        L = r1 - a
        c = (a + r1) / 2
        flat_rect(w * (1.8 if big else 1.0), L, col, M=(M if M is not None else Matrix.Identity(4))
                  @ Matrix.Translation(clock(th, c, y)) @ Ry(th))


def baton(theta, r_in, r_out, w, y, h, col, kind="Metal", lume=None, M=None, bevel=None):
    L = r_out - r_in
    Mx = (M if M is not None else Matrix.Identity(4)) @ Matrix.Translation(clock(theta, (r_in + r_out) / 2, y)) @ Ry(theta)
    box((w, h, L), col, kind, (0, h / 2, 0), r=bevel if bevel is not None else min(w, h) * 0.3, seg=1, M=Mx)
    if lume:
        box((w * 0.45, 0.00004, L * 0.8), lume, "Paint", (0, h + 0.00002, 0), M=Mx, smooth=False)


def crown_knurled(x0, y, r, length, col, kind="Metal", ridges=24, tube_r=None, logo=False, cab=None,
                  logo_col=None):
    """Winding crown on the +X side: tube + fluted/knurled crown (+ optional crown logo / cabochon)."""
    tr = tube_r if tube_r is not None else r * 0.5
    L = length
    prof = [(0, 0), (tr, 0), (tr, L * 0.28), (r * 0.9, L * 0.3), (r, L * 0.36), (r, L * 0.86),
            (r * 0.92, L * 0.95), (r * 0.7, L), (0, L)]

    def mod(th, rr, yy, k):
        if k in (4, 5):
            return rr * (1.0 - 0.07 * (1 if (th * ridges / TAU) % 1.0 < 0.5 else 0)), yy
        return rr, yy
    M = T((x0, y, 0)) @ Matrix.Rotation(-math.pi / 2, 4, "Z")
    revolve(prof, col, kind, ridges * 2 if ridges else 24, M=M, mod=mod if ridges else None)
    if logo:
        crown_logo(r * 0.95, L, logo_col or col, kind, M=M @ T(rot=[("y", 0)]))
    if cab:
        sphere(r * 0.62, cab, "Gloss", (0, L + r * 0.05, 0), segs=12, rings=6, scale=(1, 0.75, 1), M=M)


def lug_profile(z0, z1, top0, top1, bot0, bot1, n=6):
    """Side profile (z, y) of a lug from the case (z0) to its tip (z1) with an eased top line."""
    pts = []
    for i in range(n + 1):
        t = i / n
        e = t * t * (3 - 2 * t)
        pts.append((z0 + (z1 - z0) * t, top0 + (top1 - top0) * (0.35 * t + 0.65 * e)))
    tipr = (pts[-1][1] - (bot1)) / 2
    for i in range(1, 4):
        a = math.pi / 2 - math.pi * i / 4
        pts.append((z1 + tipr * 0.35 * math.cos(a), bot1 + tipr + tipr * math.sin(a)))
    for i in range(n, -1, -1):
        t = i / n
        pts.append((z0 + (z1 - z0) * t, bot0 + (bot1 - bot0) * t * t))
    return pts


def lugs(x_in, x_out, z0, z1, top0, top1, bot0, bot1, col, kind="Metal", bevel=0.0005):
    for sz in (1, -1):
        prof = [(z * sz, y) for z, y in lug_profile(z0, z1, top0, top1, bot0, bot1)]
        if sz < 0:
            prof = list(reversed(prof))
        for sx in (1, -1):
            a, b = sorted((sx * x_in, sx * x_out))
            emit(slab_bm(prof, a, b, bevel, 2), col, kind)


# ============================================================================= CROWNWELL

def cw_case(metal, metal_b, bezel="fluted", H=None):
    """Crownwell Oyster-style 40 mm case (Datejust / Iced share it). Returns key heights."""
    y0 = H0
    Yd = y0 + 0.0068                   # dial top
    revolve([(0, y0), (0.0125, y0), (0.0152, y0 + 0.0006), (0.0166, y0 + 0.0016), (0.0186, y0 + 0.0021),
             (0.0197, y0 + 0.0032), (0.0199, y0 + 0.0052), (0.0196, y0 + 0.0068), (0.0188, y0 + 0.0074),
             (0.0160, y0 + 0.0074), (0.0156, Yd - 0.0006), (0, Yd - 0.0006)], metal, "Metal", 56)
    revolve([(0, y0 - 0.0001), (0.011, y0 - 0.0001), (0.0118, y0 + 0.0002), (0, y0 + 0.0002)],
            metal_b, "Metal", 48)                                                           # case-back boss
    cw_lugs(metal, metal_b)
    return Yd


def cw_bezel_fluted(y0, col, flutes=62):
    prof = [(0.0157, y0 + 0.0072), (0.0198, y0 + 0.0072), (0.0200, y0 + 0.0082), (0.0192, y0 + 0.0096),
            (0.0176, y0 + 0.0104), (0.0162, y0 + 0.0103), (0.0157, y0 + 0.0097)]

    def mod(th, r, y, k):
        if k in (2, 3, 4):
            f = (th * flutes / TAU) % 1.0
            v = 2 * abs(2 * f - 1) - 1           # ridge .. valley
            depth = (0.00022, 0.0004, 0.00022)[k - 2]
            if k == 2:
                return r + v * 0.0001, y + v * 0.0001
            return r, y + v * depth
        return r, y
    revolve(prof, col, "Metal", flutes * 4, mod=mod, closed=True, sharp=0.35, phase=0.0)


def cw_dial_common(Yd, dial_col, print_col, index_col, date=True, iced=False, dial_kind="Gloss",
                   sunburst=True):
    rd = 0.0158

    def sun(c, n):
        a = math.atan2(c.x, -c.z)
        k = 0.93 + 0.1 * math.cos(2 * a + 0.8) if sunburst else 1.0
        return (min(dial_col[0] * k, 1), min(dial_col[1] * k, 1), min(dial_col[2] * k, 1))
    revolve([(0, Yd - 0.0004), (rd, Yd - 0.0004), (rd, Yd), (0.012, Yd), (0, Yd)], sun, dial_kind, 72)
    # rehaut (inner flange) with engraved-look ring
    revolve([(0.0151, Yd - 0.0001), (0.0162, Yd - 0.0001), (0.0162, Yd + 0.0019), (0.0158, Yd + 0.0019),
             (0.0151, Yd + 0.0003)], index_col if not iced else WGOLD, "Metal", 72, closed=True)
    minute_track(0.0142, 0.0149, Yd + EPS, print_col, r_major=0.0140, skip=(15,) if date else ())
    return rd


def cw_hands_baton(Yd, metal, lume, sec_col=None):
    th_h = TAU * (10 + 10 / 60) / 12
    th_m = TAU * 10 / 60
    th_s = TAU * 38 / 60
    hour = [(-0.00072, 0.0016), (0.00072, 0.0016), (0.00072, -0.0074), (0, -0.0084), (-0.00072, -0.0074)]
    minute = [(-0.00062, 0.0018), (0.00062, 0.0018), (0.00062, -0.0122), (0, -0.0131), (-0.00062, -0.0122)]
    hand(hour, Yd + 0.0006, th_h, metal)
    hand([(-0.0003, -0.0012), (0.0003, -0.0012), (0.0003, -0.0071), (-0.0003, -0.0071)], Yd + 0.00073, th_h, lume,
         "Paint", thick=0.00002)
    hand(minute, Yd + 0.0009, th_m, metal)
    hand([(-0.00026, -0.0014), (0.00026, -0.0014), (0.00026, -0.0118), (-0.00026, -0.0118)], Yd + 0.00103, th_m,
         lume, "Paint", thick=0.00002)
    sc = sec_col or metal
    hand([(-0.00012, 0.0038), (0.00012, 0.0038), (0.00008, -0.0145), (-0.00008, -0.0145)], Yd + 0.0012, th_s, sc)
    hand(circle_poly(0.00055, 12, 0, 0.0030), Yd + 0.0012, th_s, sc)
    disc(0.0011, Yd + 0.0005, Yd + 0.0015, metal, "Metal", 16)
    disc(0.00045, Yd + 0.0015, Yd + 0.0017, metal, "Metal", 12)


def crystal(r, y0, y1, M=None, pos=(0, 0, 0)):
    disc(r, y0, y1, (0.9, 0.95, 1.0), "Glass", 48, pos=pos, M=M, bevel=min(0.0005, (y1 - y0) * 0.8))


def cw_date(Yd, metal, frame_col=None):
    x = 0.0116
    box((0.0041, 0.00025, 0.0034), frame_col or metal, "Metal", (x, Yd + 0.000125, 0), r=0.0001, seg=1)
    box((0.0034, 0.0001, 0.0027), (0.97, 0.97, 0.95), "Paint", (x, Yd + 0.0003, 0), smooth=False)
    text("28", 0.0026, PRINT, "Paint", (x + 0.00005, Yd + 0.00036, 0.0), fnt="sans")


def cw_clasp(s_mid, L, w, metal, metal_b, text_col=None):
    """Oyster-style folding clasp: a curved blade following the loop bottom, crown on top."""
    band_sweep(s_mid - L / 2, s_mid + L / 2, lambda f: w + 0.0006, lambda f: 0.0037, metal_b, "Metal",
               step=0.0015, r=0.0009)
    M = LOOP.frame(s_mid, 0.0037)
    crown_logo(0.0052, 0.0, metal, "Metal", M=M, pos=(0, 0, 0.0045), theta=math.pi)
    text("CROWNWELL", 0.0017, text_col or metal_b, "Paint", (0, 0.00002, -0.004), theta=math.pi,
         M=M, spacing=1.1) if False else None
    box((w + 0.0003, 0.0004, 0.0006), metal, "Metal", (0, 0.0002, -0.0105), M=M, r=0.00015, seg=1)
    box((w + 0.0003, 0.0004, 0.0006), metal, "Metal", (0, 0.0002, 0.0115), M=M, r=0.00015, seg=1)


def jubilee_row(metal, metal_b, t=0.0026, gems=False):
    def row(M, w, p, i, side):
        ow = w * 0.3
        for sx in (-1, 1):
            x0, x1 = sorted((sx * w / 2, sx * (w / 2 - ow)))
            link(M, x0, x1, p * 0.94, t, 0.0011, metal_b, cap=0.0003)
            if gems:
                for dz in (-0.25, 0.25):
                    gem(0.00075, ((x0 + x1) / 2, t - 0.00012, dz * p), M=M, n=6, pav=0)
        cw = (w - 2 * ow) / 3.0
        for k in (-1, 0, 1):
            link(M, k * cw - cw * 0.44, k * cw + cw * 0.44, p * 0.62, t * 1.1, 0.0009, metal, z=p * 0.5,
                 cap=0.0, n=2)
            if gems:
                gem(min(cw * 0.36, 0.00075), (k * cw, t * 1.1 - 0.0001, p * 0.5), M=M, n=6, pav=0)
    return row


def cw_lugs(metal, metal_b, z_tip=0.0238, t=0.0026, x_in=0.0099, x_out=0.0122):
    """Oyster lugs + solid end links, meeting the bracelet where the loop passes the lug tips."""
    yi = band_y(z_tip)
    lugs(x_in, x_out, 0.0125, z_tip, H0 + 0.0071, yi + t + 0.0011, H0 + 0.0014, yi - 0.0001, metal)
    for sz in (1, -1):
        prof = [(0.0145, H0 + 0.0060), (0.0185, H0 + 0.0047), (z_tip + 0.0004, yi + t),
                (z_tip + 0.0004, yi + 0.0002), (0.0190, H0 + 0.0002), (0.0145, H0 + 0.0008)]
        prof = [(z * sz, y) for z, y in prof]
        emit(slab_bm(prof, -x_in + 0.00005, x_in - 0.00005, 0.0003, 1), metal_b, "Metal")


def build_crownwell_datejust():
    Yd = cw_case(GOLD, GOLD_B)
    cw_bezel_fluted(H0, GOLD)
    cw_dial_common(Yd, (0.93, 0.8, 0.55), PRINT, GOLD)
    for h in range(12):
        th = TAU * h / 12
        if h == 3:
            continue
        if h == 0:
            for dx in (-0.00085, 0.00085):
                baton(th, 0.0104, 0.0139, 0.0011, Yd, 0.00055, GOLD, M=T((dx, 0, 0)), lume=PRINT)
            continue
        baton(th, 0.0106 if h % 3 else 0.0102, 0.0139, 0.0013 if h % 3 else 0.0016, Yd, 0.00055, GOLD, lume=PRINT)
    crown_logo(0.0034, Yd, GOLD, "Metal", pos=(0, 0, -0.0078), h=0.0003)
    text("CROWNWELL", 0.00125, PRINT, "Paint", (0, Yd + EPS, -0.0056), spacing=1.15)
    text("PERPETUAL", 0.00062, PRINT, "Paint", (0, Yd + EPS, -0.0044), fnt="sansr", spacing=1.2)
    text("DATEWELL", 0.00085, PRINT, "Paint", (0, Yd + EPS, -0.0034), fnt="serifi")
    text("CERTIFIED CHRONOMETER", 0.00058, PRINT, "Paint", (0, Yd + EPS, 0.0056), fnt="sansr")
    text("GENÈVE", 0.00072, PRINT, "Paint", (0, Yd + EPS, 0.0082), fnt="sans", spacing=1.2)
    cw_date(Yd, GOLD)
    cw_hands_baton(Yd, GOLD, PRINT)
    crystal(0.0162, Yd + 0.0019, H0 + 0.0107)
    box((0.0064, 0.0014, 0.0058), (0.9, 0.95, 1.0), "Glass", (0.0116, H0 + 0.0107 + 0.0007, 0), r=0.0011, seg=3)
    crown_knurled(0.0194, H0 + 0.0045, 0.0034, 0.0046, GOLD, logo=True)
    bracelet(0.0238, jubilee_row(GOLD, GOLD_B), 0.0047, 0.0196, 0.0162, 0.030,
             lambda s, L, w: cw_clasp(s, L, w, GOLD, GOLD_B), filler=(GOLD_B, "Metal"))
    finish("Watch_Crownwell_Datejust")


# ============================================================================= main / preview

BUILDERS = [
    ("Watch_Crownwell_Datejust", build_crownwell_datejust),
]


def export():
    keep = {o.name for o in KIT}
    for ob in KIT:
        keep.update(c.name for c in ob.children)
    for o in list(bpy.data.objects):
        if o.name not in keep:
            bpy.data.objects.remove(o)
    total = 0
    for o in KIT:
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        total += tris
        dims = [o.bound_box[i] for i in range(8)]
        xs = [c[0] for c in dims]
        ys = [c[1] for c in dims]
        zs = [c[2] for c in dims]
        # report in Godot axes: x, y(up)=blender z, z = -blender y
        print("  %-26s %6d tris   x[%.4f,%.4f] y[%.4f,%.4f] z[%.4f,%.4f]" % (
            o.name, tris, min(xs), max(xs), min(zs), max(zs), -max(ys), -min(ys)))
    print("props:", len(KIT), " tris:", total)
    for name, mk in MARKERS.items():
        for mname, pos in mk:
            print("  marker %-28s (%.4f, %.4f, %.4f)" % (mname, pos[0], pos[1], pos[2]))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_vertex_color="ACTIVE",
                              export_apply=True, export_yup=True, export_materials="EXPORT",
                              export_normals=True)
    print("wrote", os.path.abspath(OUT))


def preview(outdir, only=None):
    """Cycles renders of every prop (3/4 view + close-up) with materials tuned like PropKit's."""
    os.makedirs(outdir, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = int(os.environ.get("SAMPLES", "20"))
    sc.cycles.use_denoising = True
    sc.render.resolution_x = sc.render.resolution_y = int(os.environ.get("RES", "640"))
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    for kind, m in MATS.items():
        b = m.node_tree.nodes.get("Principled BSDF")
        vc = [n for n in m.node_tree.nodes if n.type == "VERTEX_COLOR"][0]
        gm = m.node_tree.nodes.new("ShaderNodeGamma")      # vertex colors hold sRGB values
        gm.inputs[1].default_value = 2.2
        m.node_tree.links.new(vc.outputs["Color"], gm.inputs[0])
        m.node_tree.links.new(gm.outputs[0], b.inputs["Base Color"])
        rough, metal, spec = {"Paint": (0.85, 0.0, 0.35), "Gloss": (0.25, 0.0, 0.7), "Metal": (0.3, 0.55, 0.8),
                              "Glow": (1, 0, 0), "Glass": (0.03, 0.0, 1.0)}[kind]
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = metal
        b.inputs["Specular IOR Level"].default_value = spec
        if kind == "Glow":
            m.node_tree.links.new(gm.outputs[0], b.inputs["Emission Color"])
            b.inputs["Emission Strength"].default_value = 1.0
        if kind == "Glass":
            b.inputs["Alpha"].default_value = 0.07
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes["Background"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(tc.outputs["Normal"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs[0])
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (0.05, 0.05, 0.06, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (0.9, 0.92, 1.0, 1)
    nt.links.new(ramp.outputs[0], bg.inputs[0])
    bg.inputs[1].default_value = 0.45
    cam_d = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    lights = []
    for loc, e, size in (((0.6, -0.8, 1.0), 60, 0.6), ((-1.0, -0.3, 0.5), 25, 0.8), ((0.0, 1.0, 0.7), 35, 0.5)):
        ld = bpy.data.lights.new("l", "AREA")
        ld.energy = e
        ld.size = size
        lo = bpy.data.objects.new("l", ld)
        lo.location = loc
        lo.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(lo)
        lights.append(lo)
    obs = [o for o in KIT if not only or o.name in only]
    for o in KIT:
        o.hide_render = True
    for o in obs:
        o.hide_render = False
        bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
        lo = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
        hi = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
        c = (lo + hi) / 2
        rad = (hi - lo).length / 2
        is_watch = o.name.startswith("Watch_")
        views = [("a", Vector((0.55, -0.75, 0.55)), c, rad * 2.9)]
        if is_watch:
            top = Vector((0, 0, hi.z - 0.004))
            views.append(("b", Vector((0.12, -0.35, 1.0)), top, 0.085))
            views.append(("c", Vector((1.0, -0.25, 0.25)), c, rad * 2.8))
        else:
            views.append(("b", Vector((-0.4, -0.9, 0.35)), c, rad * 2.6))
        s = rad / 0.05
        for lo_ in lights:
            lo_.location = Vector(lo_.location).normalized() * max(rad * 12, 0.5) + c
            lo_.rotation_euler = (c - lo_.location).to_track_quat("-Z", "Y").to_euler()
            lo_.data.size = max(rad * 5, 0.08)
            lo_.data.energy = {0: 14, 1: 5, 2: 8}[lights.index(lo_)] * (max(rad * 12, 0.5) ** 2)
        cam_d.lens = 70
        cam_d.clip_start = rad * 0.02
        cam_d.clip_end = rad * 100
        for tag, d, tgt, dist in views:
            cam.location = tgt + d.normalized() * dist
            cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
            sc.render.filepath = os.path.join(outdir, "%s_%s.png" % (o.name, tag))
            bpy.ops.render.render(write_still=True)
            print("rendered", sc.render.filepath)
        o.hide_render = True
        _ = s


def main():
    argv = sys.argv[1:]
    prev = None
    only = None
    if "--preview" in argv:
        prev = argv[argv.index("--preview") + 1]
    if "--only" in argv:
        only = set(argv[argv.index("--only") + 1].split(","))
    reset()
    for name, fn in BUILDERS:
        if only and name not in only:
            continue
        fn()
    export()
    if prev:
        preview(prev)


if __name__ == "__main__":
    main()
