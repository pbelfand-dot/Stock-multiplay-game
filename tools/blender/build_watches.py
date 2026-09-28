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
  * upright (dial facing the viewer, +Z, 12 o'clock up): rotate +90 deg about X (rotation.x = PI / 2).
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
    if pav <= 0:     # the flat underside is never seen: drop it once the normals are settled
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bottom = [f for f in bm.faces if len(f.verts) == n and f.calc_center_median().y < 1e-9]
        cols = [c for f, c in zip(bm.faces, cols) if f not in bottom]
        bmesh.ops.delete(bm, geom=bottom, context="FACES_ONLY")
    Mx = (M if M is not None else Matrix.Identity(4)) @ Matrix.Translation(Vector(pos))
    if up is not None:
        q = Vector((0, 1, 0)).rotation_difference(Vector(up).normalized())
        Mx = Mx @ q.to_matrix().to_4x4()
    return emit(bm, cols, "Gloss", Mx, smooth=False, recalc=pav > 0)


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
                  logo_col=None, bead=0.0):
    """Winding crown on the +X side: tube + fluted/knurled crown (+ optional crown logo / cabochon)."""
    tr = tube_r if tube_r is not None else r * 0.5
    L = length
    prof = [(0, 0), (tr, 0), (tr, L * 0.28), (r * 0.9, L * 0.3), (r, L * 0.36), (r, L * 0.86),
            (r * 0.92, L * 0.95), (r * 0.7, L), (0, L)]

    def mod(th, rr, yy, k):
        if bead and k in (3, 4, 5, 6):
            return rr * (1.0 - bead * (0.5 - 0.5 * math.cos(th * ridges))), yy
        if k in (4, 5):
            return rr * (1.0 - 0.07 * (1 if (th * ridges / TAU) % 1.0 < 0.5 else 0)), yy
        return rr, yy
    M = T((x0, y, 0)) @ Matrix.Rotation(-math.pi / 2, 4, "Z")
    revolve(prof, col, kind, ridges * (4 if bead else 2) if ridges else 24, M=M, mod=mod if ridges else None)
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
            emit(slab_bm(prof, a, b, bevel, 1), col, kind, sharp=0.9)


# ============================================================================= shared watch parts

def brushed(polished, brushed_col, up=0.9):
    """Face color: brushed on the up-facing (local +y) flats, polished on chamfers and sides."""
    return lambda c, n: brushed_col if n.y > up else polished


def flat_ring(r_in, r_out, y, col, kind="Paint", segs=64, M=None, pos=(0, 0, 0)):
    return revolve([(r_out, y), (r_in, y)], col, kind, segs, pos=pos, M=M, smooth=False)


def flat_poly(pts, y, col, kind="Paint", M=None):
    """Single up-facing polygon [(x, z)] at height y (printing, strap holes)."""
    bm = bmesh.new()
    bm.faces.new([bm.verts.new((x, y, z)) for x, z in _ccw(list(pts))])
    return emit(bm, col, kind, M, smooth=False, recalc=False)


def quad_between(a, b, w, y, col, kind="Paint", M=None):
    """Flat printed stroke from 2D point a to b (x, z) of width w."""
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    L = math.hypot(dx, dz)
    nx, nz = -dz / L * w / 2, dx / L * w / 2
    return flat_poly([(ax + nx, az + nz), (bx + nx, bz + nz), (bx - nx, bz - nz), (ax - nx, az - nz)], y, col,
                     kind, M)


def face_up(bm):
    bm.normal_update()
    for f in bm.faces:
        if f.normal.y < 0:
            f.normal_flip()
    return bm


def offset_poly(pts, d):
    """Inset a simple polygon [(x, z)] by d (miter joins)."""
    pts = _ccw(list(pts))
    n = len(pts)
    P = [Vector((x, -z)) for x, z in pts]
    out = []
    for i in range(n):
        p0, p1, p2 = P[i - 1], P[i], P[(i + 1) % n]
        e1 = (p1 - p0).normalized()
        e2 = (p2 - p1).normalized()
        n1 = Vector((-e1.y, e1.x))
        n2 = Vector((-e2.y, e2.x))
        b = n1 + n2
        b = n1 if b.length < 1e-9 else b.normalized()
        q = p1 + b * (d / max(b.dot(n1), 0.3))
        out.append((q.x, -q.y))
    return out, pts


def outline_prism(poly, lw, y0, y1, col, kind="Metal", M=None):
    """Skeletonized outline of a polygon (open-worked hands, frames)."""
    inner, outer = offset_poly(poly, lw)
    bm = bmesh.new()
    n = len(outer)
    ob = [bm.verts.new((x, y0, z)) for x, z in outer]
    ot = [bm.verts.new((x, y1, z)) for x, z in outer]
    ib = [bm.verts.new((x, y0, z)) for x, z in inner]
    it = [bm.verts.new((x, y1, z)) for x, z in inner]
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((ot[i], ot[j], it[j], it[i]))
        bm.faces.new((ob[j], ob[i], ib[i], ib[j]))
        bm.faces.new((ob[i], ob[j], ot[j], ot[i]))
        bm.faces.new((ib[j], ib[i], it[i], it[j]))
    return emit(bm, col, kind, M, smooth=False)


def gear(r, teeth, y, h, pos, col, kind="Metal", spokes=4, jewel=True, M=None, rim=0.78):
    root = r - min(0.00035, r * 0.12)

    def mod(th, rr, yy, k):
        i = round(th / TAU * teeth * 2)
        return ((rr if i % 2 == 0 else root) if k in (1, 2) else rr), yy
    Mx = (M if M is not None else Matrix.Identity(4)) @ Matrix.Translation(Vector(pos))
    revolve([(r * rim, y), (r, y), (r, y + h), (r * rim, y + h)], col, kind, teeth * 2, M=Mx, mod=mod, closed=True,
            sharp=0.5)
    disc(r * 0.22, y, y + h * 1.3, col, kind, 12, M=Mx)
    for k in range(spokes):
        a = TAU * k / spokes + 0.3
        box((r * 0.12, h * 0.8, r * rim), col, kind, (0, y + h * 0.5, -r * rim / 2), M=Mx @ Ry(a), smooth=False)
    if jewel:
        sphere(r * 0.12 if r < 0.004 else 0.0004, (0.75, 0.03, 0.08), "Gloss", (0, y + h * 1.3, 0), segs=8, rings=4,
               M=Mx)


def ray_rect(th, hx, hz):
    """Point where the clock-angle ray th leaves the rectangle |x|<=hx, |z|<=hz."""
    dx, dz = math.sin(th), -math.cos(th)
    t = min(hx / abs(dx) if abs(dx) > 1e-9 else 1e9, hz / abs(dz) if abs(dz) > 1e-9 else 1e9)
    return dx * t, dz * t


def ray_outline(outline, th):
    return resample_polar(outline, 1, phase=th)[0]


# ----------------------------------------------------------------------------- straps

def strap_samples(s_a, s_b, scale, groove, rng=None):
    """Arc positions alternating scale / groove lengths (alligator scales, rubber ribs)."""
    ss = [s_a]
    kinds = []
    s = s_a
    flip = 1 if s_b > s_a else -1
    k = 0
    while (s_b - s) * flip > 1e-6:
        step = (scale * (rng.uniform(0.65, 1.35) if rng else 1.0)) if k % 2 == 0 else groove
        s = s + flip * step
        if (s - s_b) * flip > 0:
            s = s_b
        ss.append(s)
        kinds.append("scale" if k % 2 == 0 else "groove")
        k += 1
    return ss, kinds


def strap_section(w, t, cols=4, g=0.00032, er=0.0007):
    """Cross-section (x, y) + per-face kind: ('scale', col) / ('groove', col) / 'edge' / 'lining'."""
    er = min(er, t * 0.4)
    pts, kinds = [], []
    X0 = w / 2 - er
    wts = {1: [1.0], 3: [0.8, 1.4, 0.8], 4: [0.72, 1.28, 1.28, 0.72], 5: [0.62, 1.1, 1.56, 1.1, 0.62]}.get(
        cols, [1.0] * cols)
    edges = [X0]
    for wt in wts:
        edges.append(edges[-1] - 2 * X0 * wt / sum(wts))
    for c in range(cols):
        xa = edges[c]
        xb = edges[c + 1]
        pts.append((xa - (g / 2 if c > 0 else 0.0), t))
        kinds.append(("scale", c))
        pts.append((xb + (g / 2 if c < cols - 1 else 0.0), t))
        kinds.append(("groove", c) if c < cols - 1 else "edge")
    pts += [(-w / 2 + er * 0.3, t - er * 0.3), (-w / 2, t - er), (-w / 2, er * 0.6), (-w / 2 + er * 0.6, 0.0),
            (w / 2 - er * 0.6, 0.0), (w / 2, er * 0.6), (w / 2, t - er), (w / 2 - er * 0.3, t - er * 0.3)]
    kinds += ["edge", "edge", "edge", "lining", "edge", "edge", "edge", "edge"]
    return pts, kinds


def strap_piece(s_a, s_b, w_fn, t_fn, off_fn, base, lining, edge, kind="Paint", cols=4, scale=0.0023,
                groove=0.00032, tip=0.0, sink=0.00012, seed=1, var=0.16):
    """Leather / rubber strap piece following the loop. Groove rings sink a little so light catches the
    scales; faces are colored per scale (random tone), groove, edge and lining."""
    rng = random.Random(seed)
    ss, skinds = strap_samples(s_a, s_b, scale, groove, rng if var > 0.05 else None)
    n = len(ss) - 1
    total = abs(s_b - s_a)
    rings = []
    for i, s in enumerate(ss):
        f = abs(s - s_a) / total
        w, t = w_fn(f), t_fn(f)
        rest = abs(s_b - s)
        if tip > 0 and rest < tip:
            k = rest / tip
            w = w * max(math.sqrt(max(1 - (1 - k) ** 2, 0.0)), 0.2)
        pts, fkinds = strap_section(w, t, cols)
        # groove rings = the ring on either side of a groove segment -> sink the top a touch
        sunk = (i > 0 and skinds[i - 1] == "groove") or (i < n and skinds[i] == "groove")
        M = LOOP.frame(s, off_fn(f))
        rings.append([M @ Vector((x, y - (sink if (sunk and y >= t - 1e-9) else 0.0), 0.0)) for x, y in pts])
    bm = loft_bm(rings)
    tones = {}
    cols_out = []
    for i in range(n):
        for k, fk in enumerate(fkinds):
            if fk == "lining":
                c = lining
            elif fk == "edge":
                c = edge
            elif skinds[i] == "groove" or fk[0] == "groove":
                c = tuple(v * 0.55 for v in base)
            else:
                key = (i, fk[1])
                if key not in tones:
                    tones[key] = 1.0 + rng.uniform(-var, var)
                c = tuple(min(v * tones[key], 1.0) for v in base)
            cols_out.append(c)
    cols_out += [edge, edge]
    return emit(bm, cols_out, kind, recalc=True, sharp=0.9)


def buckle(s, w, y, col, kind="Metal", L=0.0085, rr=0.00055):
    """Tang buckle lying on the band at arc position s: rounded frame + prong."""
    M = LOOP.frame(s)
    hw = w / 2 + 0.0012
    cr = 0.0022
    path = []
    for cx, cz, a0 in ((hw - cr, L - cr, 0.0), (-hw + cr, L - cr, math.pi / 2), (-hw + cr, -0.0006 + cr, math.pi),
                       (hw - cr, -0.0006 + cr, 1.5 * math.pi)):
        for j in range(4):
            a = a0 + math.pi / 2 * j / 3
            path.append(Vector((cx + cr * math.cos(a), 0.0, cz + cr * math.sin(a))))
    rings = []
    m = len(path)
    for i in range(m + 1):
        p = path[i % m]
        tn = (path[(i + 1) % m] - path[(i - 1) % m]).normalized()
        nrm = Vector((tn.z, 0.0, -tn.x))
        rings.append([M @ (p + nrm * (rr * math.cos(TAU * j / 6)) + Vector((0, y + rr * math.sin(TAU * j / 6), 0)))
                      for j in range(6)])
    emit(loft_bm(rings, False, False), col, kind)
    rod((0, y + rr * 0.6, 0.0), (0, y - 0.0002, L + 0.0004), rr * 0.75, col, kind, 6, M=M)


def leather_strap(z_lug, w0, w1, t0, t1, base, lining, edge, metal, kind="Paint", cols=4, scale=0.0023,
                  groove=0.00032, tail=0.030, holes=True):
    """Two-piece strap closed with a tang buckle at the bottom of the loop (the long 6 o'clock piece runs
    out through the buckle and its tail lies over the 12 o'clock piece, held by two keepers)."""
    s6 = LOOP.s_for_z(z_lug) - 0.0022
    s12 = LOOP.L - s6
    sb = LOOP.L / 2 - 0.004
    span = sb - s6
    wf = lambda f: w0 + (w1 - w0) * f  # noqa: E731
    tf = lambda f: t0 + (t1 - t0) * f  # noqa: E731
    # 12 o'clock piece: lug -> buckle
    strap_piece(s12, sb, lambda f: wf(f * (s12 - sb) / span), lambda f: tf(f * (s12 - sb) / span), lambda f: 0.0,
                base, lining, edge, kind, cols, scale, groove, seed=2)
    # 6 o'clock piece: lug -> under the buckle -> tail over the 12 piece
    end = sb + tail
    L6 = end - s6

    def off(f):
        s = s6 + L6 * f
        k = min(max((s - (sb - 0.004)) / 0.006, 0.0), 1.0)
        return (t1 + 0.0001) * (k * k * (3 - 2 * k))
    strap_piece(s6, end, lambda f: max(wf((s6 + L6 * f - s6) / span), w1), lambda f: t1 * 0.92 + (t0 - t1) *
                max(0.0, 1 - (s6 + L6 * f - s6) / span) * 0.9, off, base, lining, edge, kind, cols, scale, groove,
                tip=0.007, seed=3)
    # folded end of the 12 piece around the buckle bar
    M = LOOP.frame(sb)
    box((w1 - 0.0004, 2 * t1 + 0.0009, 0.0024), base, kind, (0, t1 + 0.00045, -0.0006), r=0.0009, seg=2, M=M)
    buckle(sb, w1, 2 * t1 + 0.0006, metal)
    for k, ds in enumerate((0.0125, 0.0205)):     # keepers
        M = LOOP.frame(sb + ds)
        tt = 2 * t1 + 0.0004
        c = tuple(v * 0.9 for v in base)
        box((w1 + 0.0014, 0.0006, 0.0034), c, kind, (0, tt + 0.0003, 0), r=0.00025, seg=1, M=M)
        box((w1 + 0.0014, 0.0005, 0.0034), c, kind, (0, -0.00035, 0), r=0.0002, seg=1, M=M)
        for sx in (-1, 1):
            box((0.0006, tt + 0.0011, 0.0034), c, kind, (sx * (w1 / 2 + 0.0004), tt / 2, 0), r=0.00025, seg=1, M=M)
    if holes:
        for ds in (0.0100, 0.0165):
            s = sb + ds
            f = (s - s6) / L6
            M = LOOP.frame(s, off(f))
            flat_poly(circle_poly(0.0007, 8), t1 * 0.92 + 0.00002, (0.05, 0.03, 0.02), "Paint", M)
    return sb


# ============================================================================= CROWNWELL GENÈVE

def cw_clasp(s_mid, L, w, metal, metal_b, t=0.0034, engrave=(0.5, 0.36, 0.12)):
    """Oyster-style folding clasp: a curved blade following the loop bottom, crown + name on top."""
    band_sweep(s_mid - L / 2, s_mid + L / 2, lambda f: w + 0.0006, lambda f: t, metal_b, "Metal",
               step=0.0015, r=0.0009)
    band_sweep(s_mid - L * 0.38, s_mid + L * 0.38, lambda f: w * 0.62, lambda f: 0.00025, metal, "Metal", off=t,
               step=0.002, r=0.0001, nr=1)
    M = LOOP.frame(s_mid, t + 0.00025)
    crown_logo(0.0046, 0.0, metal, "Metal", M=M, pos=(0, 0, 0.0052), theta=math.pi, h=0.0003)
    text("CROWNWELL", 0.0012, engrave, "Paint", (0, 0.00003, -0.0035), theta=math.pi, M=M, spacing=1.15)
    for dz in (-L / 2 + 0.0012, L / 2 - 0.0012):
        box((w + 0.0004, 0.0005, 0.0007), metal, "Metal", (0, -0.0002, 0), M=LOOP.frame(s_mid + dz, t + 0.00025),
            r=0.0002, seg=1)


def jubilee_row(metal, metal_b, t=0.0026, gems=False):
    def row(M, w, p, i, side):
        ow = w * 0.3
        for sx in (-1, 1):
            x0, x1 = sorted((sx * w / 2, sx * (w / 2 - ow)))
            link(M, x0, x1, p * 0.94, t, 0.0011, metal_b, cap=0.0)
            if gems:
                for dz in (-0.25, 0.25):
                    gem(0.0008, ((x0 + x1) / 2, t - 0.0001, dz * p), M=M, n=6, pav=0)
        cw = (w - 2 * ow) / 3.0
        if gems:      # one pavé bar carrying three stones instead of three separate centre links
            link(M, -1.44 * cw, 1.44 * cw, p * 0.62, t * 1.1, 0.0009, metal, z=p * 0.5, cap=0.0, n=2)
            for k in (-1, 0, 1):
                gem(min(cw * 0.4, 0.00085), (k * cw, t * 1.1 - 0.0001, p * 0.5), M=M, n=6, pav=0)
            return
        for k in (-1, 0, 1):
            link(M, k * cw - cw * 0.44, k * cw + cw * 0.44, p * 0.62, t * 1.1, 0.0009, metal, z=p * 0.5,
                 cap=0.0, n=2)
    return row


def oyster_row(metal, metal_b, t=0.0031):
    def row(M, w, p, i, side):
        ow = w * 0.33
        for sx in (-1, 1):
            x0, x1 = sorted((sx * w / 2, sx * (w / 2 - ow)))
            link(M, x0 + 0.0001 * sx, x1, p * 0.95, t, 0.0011, brushed(metal, metal_b, 0.97), cap=0.00028)
        link(M, -(w / 2 - ow) + 0.00012, (w / 2 - ow) - 0.00012, p * 0.97, t * 1.03, 0.0007,
             brushed(metal, metal_b, 0.97), cap=0.0002, n=2)
    return row


def cw_lugs(metal, metal_b, z_tip=0.0238, t=0.0026, x_in=0.0099, x_out=0.0122, top0=0.0068):
    """Oyster lugs + solid end links, meeting the bracelet where the loop passes the lug tips."""
    yi = band_y(z_tip)
    lugs(x_in, x_out, 0.0125, z_tip, H0 + top0, yi + t + 0.0011, H0 + 0.0014, yi - 0.0001, metal)
    for sz in (1, -1):
        prof = [(0.0140, H0 + 0.0062), (0.0165, H0 + 0.0060), (0.0190, H0 + 0.0050), (0.0215, H0 + 0.0030),
                (z_tip + 0.0004, yi + t), (z_tip + 0.0004, yi + 0.0002), (0.0190, H0 + 0.0002),
                (0.0140, H0 + 0.0008)]
        prof = [(z * sz, y) for z, y in prof]
        emit(slab_bm(prof, -x_in + 0.00008, x_in - 0.00008, 0.0003, 1), metal, "Metal", sharp=0.9)


def cw_case(metal, metal_b, t=0.0026):
    """Crownwell Oyster-style 40 mm case (Datejust / Iced / Sub share it). Returns the dial height."""
    y0 = H0
    Yd = y0 + 0.0068
    revolve([(0, y0), (0.0125, y0), (0.0152, y0 + 0.0006), (0.0166, y0 + 0.0016), (0.0186, y0 + 0.0021),
             (0.0197, y0 + 0.0032), (0.0199, y0 + 0.0052), (0.0196, y0 + 0.0068), (0.0188, y0 + 0.0074),
             (0.0160, y0 + 0.0074), (0.0156, Yd - 0.0006), (0, Yd - 0.0006)], metal, "Metal", 56)
    revolve([(0, y0 - 0.0001), (0.011, y0 - 0.0001), (0.0118, y0 + 0.0002), (0, y0 + 0.0002)],
            metal_b, "Metal", 40)
    cw_lugs(metal, metal_b, t=t)
    return Yd


def cw_bezel_fluted(y0, col, flutes=54):
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
    revolve(prof, col, "Metal", flutes * 4, mod=mod, closed=True, sharp=0.5)


def cw_dial_common(Yd, dial_col, print_col, rehaut_col, date=True, dial_kind="Gloss", sunburst=True,
                   rehaut_kind="Metal"):
    rd = 0.0158

    def sun(c, n):
        a = math.atan2(c.x, -c.z)
        k = 0.93 + 0.1 * math.cos(2 * a + 0.8) if sunburst else 1.0
        return (min(dial_col[0] * k, 1), min(dial_col[1] * k, 1), min(dial_col[2] * k, 1))
    revolve([(0, Yd - 0.0004), (rd, Yd - 0.0004), (rd, Yd), (0.012, Yd), (0, Yd)], sun, dial_kind, 64)
    revolve([(0.0151, Yd - 0.0001), (0.0162, Yd - 0.0001), (0.0162, Yd + 0.0019), (0.0158, Yd + 0.0019),
             (0.0151, Yd + 0.0003)], rehaut_col, rehaut_kind, 64, closed=True)
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


def cw_date(Yd, metal, frame_col=None, x=0.0116, disc_col=(0.97, 0.97, 0.95), num_col=PRINT, size=0.0026):
    box((0.0041, 0.00025, 0.0034), frame_col or metal, "Metal", (x, Yd + 0.000125, 0), r=0.0001, seg=1)
    box((0.0034, 0.0001, 0.0027), disc_col, "Paint", (x, Yd + 0.0003, 0), smooth=False)
    text("28", size, num_col, "Paint", (x + 0.00005, Yd + 0.00036, 0.0), fnt="sans")


def cw_cyclops(x=0.0116, y=H0 + 0.0107):
    box((0.0064, 0.0014, 0.0058), (0.9, 0.95, 1.0), "Glass", (x, y + 0.0007, 0), r=0.0011, seg=3)


def cw_print(Yd, col, model, model_col=None, lower=("CERTIFIED CHRONOMETER",)):
    text("CROWNWELL", 0.00125, col, "Paint", (0, Yd + EPS, -0.0056), spacing=1.15)
    text("PERPETUAL", 0.00062, col, "Paint", (0, Yd + EPS, -0.0044), fnt="sansr", spacing=1.2)
    text(model, 0.00085, model_col or col, "Paint", (0, Yd + EPS, -0.0034), fnt="serifi")
    for k, line in enumerate(lower):
        text(line, 0.00058, col, "Paint", (0, Yd + EPS, 0.0052 + k * 0.0009), fnt="sansr")
    text("GENÈVE", 0.00072, col, "Paint", (0, Yd + EPS, 0.0084), fnt="sans", spacing=1.2)


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
    cw_print(Yd, PRINT, "DATEWELL")
    cw_date(Yd, GOLD)
    cw_hands_baton(Yd, GOLD, PRINT)
    crystal(0.0162, Yd + 0.0019, H0 + 0.0107)
    cw_cyclops()
    crown_knurled(0.0194, H0 + 0.0045, 0.0034, 0.0046, GOLD, logo=True, ridges=18)
    bracelet(0.0238, jubilee_row(GOLD, GOLD_B), 0.0050, 0.0196, 0.0162, 0.030,
             lambda s, L, w: cw_clasp(s, L, w, GOLD, GOLD_B), filler=(GOLD_B, "Metal"))
    finish("Watch_Crownwell_Datejust")


def build_crownwell_iced():
    M_, MB = WGOLD, (0.8, 0.82, 0.86)
    Yd = cw_case(M_, MB)
    # bezel: polished ring set with 32 brilliant-cut stones
    revolve([(0.0157, H0 + 0.0072), (0.0199, H0 + 0.0072), (0.0201, H0 + 0.0080), (0.0199, H0 + 0.0090),
             (0.0190, H0 + 0.0094), (0.0168, H0 + 0.0094), (0.0161, H0 + 0.0092), (0.0157, H0 + 0.0088)],
            M_, "Metal", 64, closed=True)
    n = 32
    for k in range(n):
        th = TAU * (k + 0.5) / n
        gem(0.00158, clock(th, 0.01795, H0 + 0.0092), n=8, pav=0.7)
    # ice dial with diamond hour markers in white-gold cups
    cw_dial_common(Yd, (0.86, 0.92, 0.97), PRINT, WGOLD)
    for h in range(12):
        if h == 3:
            continue
        th = TAU * h / 12
        r = 0.0124
        big = h in (0, 6, 9)
        rr = 0.00125 if big else 0.001
        disc(rr + 0.00025, Yd, Yd + 0.0004, M_, "Metal", 12, pos=clock(th, r))
        gem(rr, clock(th, r, Yd + 0.0004), n=8, pav=0.6)
        if h == 0:
            for dx in (-1, 1):
                disc(0.00085, Yd, Yd + 0.0004, M_, "Metal", 12, pos=clock(th, r) + Vector((dx * 0.0024, 0, 0.0004)))
                gem(0.0006, clock(th, r, Yd + 0.0004) + Vector((dx * 0.0024, 0, 0.0004)), n=8, pav=0.6)
    crown_logo(0.0032, Yd, M_, "Metal", pos=(0, 0, -0.0079), h=0.0003)
    cw_print(Yd, PRINT, "DATEWELL", lower=("CERTIFIED CHRONOMETER",))
    cw_date(Yd, M_)
    cw_hands_baton(Yd, M_, PRINT)
    crystal(0.0162, Yd + 0.0019, H0 + 0.0102)
    cw_cyclops(y=H0 + 0.0102)
    crown_knurled(0.0194, H0 + 0.0045, 0.0034, 0.0046, M_, logo=True, ridges=18)
    for sx in (-1, 1):                       # pavé on the lug tops
        for sz in (-1, 1):
            for k in range(3):
                z = 0.0170 + k * 0.0022
                yi = band_y(0.0238)
                f = (z - 0.0125) / (0.0238 - 0.0125)
                e = f * f * (3 - 2 * f)
                ytop = H0 + 0.0068 + (yi + 0.0037 - H0 - 0.0068) * (0.35 * f + 0.65 * e)
                gem(0.00075, (sx * 0.01105, ytop - 0.00005, sz * z), n=6, pav=0.5)
    bracelet(0.0238, jubilee_row(M_, MB, gems=True), 0.0051, 0.0196, 0.0162, 0.030,
             lambda s, L, w: cw_clasp(s, L, w, M_, MB, engrave=(0.35, 0.36, 0.4)), filler=(MB, "Metal"))
    finish("Watch_Crownwell_Iced")


def sub_bezel(y0, insert_col, mark_col, metal):
    revolve([(0.0157, y0 + 0.0072), (0.0199, y0 + 0.0072), (0.0199, y0 + 0.0096), (0.0195, y0 + 0.0100),
             (0.0160, y0 + 0.0100), (0.0157, y0 + 0.0096)], metal, "Metal", 64, closed=True)
    teeth = 60

    def mod(th, r, y, k):
        f = (th * teeth / TAU) % 1.0
        return (r + (0.00028 if f < 0.5 else 0.0)), y
    revolve([(0.0199, y0 + 0.0074), (0.0199, y0 + 0.0094)], metal, "Metal", teeth * 4, mod=mod, sharp=0.5)
    Yi = y0 + 0.01004
    flat_ring(0.0161, 0.0195, Yi, insert_col, "Gloss", 64)
    Ym = Yi + EPS
    for m in range(60):
        th = TAU * m / 60
        if m == 0:
            flat_poly([(-0.0021, -0.0192), (0.0021, -0.0192), (0.0, -0.0170)], Ym, mark_col, "Metal")
            disc(0.00055, Ym, Ym + 0.00012, LUME, "Paint", 12, pos=clock(0, 0.01855))
            continue
        if m % 10 == 0:
            text(str(m), 0.0027, mark_col, "Metal", clock(th, 0.0178, Ym), th, fnt="sans")
        elif m % 5 == 0:
            quad_between(clock(th, 0.0167).xz, clock(th, 0.0190).xz, 0.0011, Ym, mark_col, "Metal")
        elif m < 15:
            quad_between(clock(th, 0.0184).xz, clock(th, 0.0192).xz, 0.00022, Ym, mark_col, "Metal")


def mercedes_hour(Yd, th, metal, lume):
    y = Yd + 0.0006
    M = Ry(th)
    hand([(-0.00045, 0.0016), (0.00045, 0.0016), (0.00045, -0.0046), (-0.00045, -0.0046)], y, th, metal)
    cz = -0.0062
    revolve([(0.0012, y), (0.00165, y), (0.00165, y + 0.00012), (0.0012, y + 0.00012)], metal, "Metal", 20,
            pos=(0, 0, cz), M=M, closed=True)
    disc(0.00122, y + 0.00001, y + 0.00009, lume, "Paint", 16, pos=(0, 0, cz), M=M)
    for a in (0.0, TAU / 3, 2 * TAU / 3):
        box((0.0002, 0.00012, 0.00125), metal, "Metal", (0, 0, -0.0006),
            M=M @ Matrix.Translation((0, y + 0.00006, cz)) @ Ry(a), smooth=False)
    hand([(-0.00095, -0.0077), (0.00095, -0.0077), (0.0, -0.0093)], y, th, metal)
    hand([(-0.00055, -0.0079), (0.00055, -0.0079), (0.0, -0.0089)], y + 0.00012, th, lume, "Paint", 0.00002)
    hand([(-0.00025, -0.0010), (0.00025, -0.0010), (0.00025, -0.0044), (-0.00025, -0.0044)], y + 0.00012, th,
         lume, "Paint", 0.00002)


def build_crownwell_sub():
    Yd = cw_case(STEEL, STEEL_B, t=0.0031)
    sub_bezel(H0, (0.02, 0.38, 0.17), (0.86, 0.88, 0.9), STEEL)
    cw_dial_common(Yd, (0.03, 0.03, 0.035), (0.92, 0.92, 0.9), (0.04, 0.04, 0.045), date=False, sunburst=False,
                   rehaut_kind="Gloss")
    for h in range(12):
        th = TAU * h / 12
        r = 0.0122
        if h == 0:
            prism([(-0.0021, -0.0140), (0.0021, -0.0140), (0.0, -0.0106)], Yd, Yd + 0.0005, WGOLD, "Metal",
                  bevel=0.00015)
            flat_poly([(-0.0014, -0.0137), (0.0014, -0.0137), (0.0, -0.01135)], Yd + 0.00051, LUME)
        elif h in (3, 6, 9):
            baton(th, 0.0104, 0.0140, 0.0019, Yd, 0.0005, WGOLD)
            flat_rect(0.00135, 0.0031, LUME, M=Matrix.Translation(clock(th, 0.0122, Yd + 0.00051)) @ Ry(th))
        else:
            disc(0.0013, Yd, Yd + 0.0005, WGOLD, "Metal", 16, pos=clock(th, r), bevel=0.00012)
            flat_ring(0.0, 0.00102, Yd + 0.00051, LUME, "Paint", 16, pos=clock(th, r))
    crown_logo(0.0028, Yd, WGOLD, "Metal", pos=(0, 0, -0.0086), h=0.0003)
    W = (0.93, 0.93, 0.9)
    text("CROWNWELL", 0.00115, W, "Paint", (0, Yd + EPS, -0.0062), spacing=1.15)
    text("OYSTERWELL PERPETUAL", 0.00055, W, "Paint", (0, Yd + EPS, -0.0050), fnt="sansr")
    text("SUBMERGER", 0.00088, (0.2, 0.75, 0.38), "Paint", (0, Yd + EPS, 0.0040), fnt="sans", spacing=1.1)
    text("300m = 1000ft", 0.0006, W, "Paint", (0, Yd + EPS, 0.0052), fnt="sansr")
    text("CERTIFIED CHRONOMETER", 0.00052, W, "Paint", (0, Yd + EPS, 0.0062), fnt="sansr")
    th_h = TAU * (10 + 10 / 60) / 12
    mercedes_hour(Yd, th_h, WGOLD, LUME)
    th_m = TAU * 10 / 60
    hand([(-0.00068, 0.0018), (0.00068, 0.0018), (0.0006, -0.0124), (0, -0.0138), (-0.0006, -0.0124)],
         Yd + 0.0009, th_m, WGOLD)
    hand([(-0.0003, -0.0015), (0.0003, -0.0015), (0.00026, -0.0121), (-0.00026, -0.0121)], Yd + 0.00102, th_m,
         LUME, "Paint", 0.00002)
    th_s = TAU * 38 / 60
    hand([(-0.00011, 0.0036), (0.00011, 0.0036), (0.00008, -0.0146), (-0.00008, -0.0146)], Yd + 0.0012, th_s,
         WGOLD)
    revolve([(0.00055, Yd + 0.0012), (0.0008, Yd + 0.0012), (0.0008, Yd + 0.00132), (0.00055, Yd + 0.00132)],
            WGOLD, "Metal", 16, M=Ry(th_s) @ T((0, 0, -0.0100)), closed=True)
    disc(0.00056, Yd + 0.00121, Yd + 0.0013, LUME, "Paint", 12, M=Ry(th_s) @ T((0, 0, -0.0100)))
    disc(0.0011, Yd + 0.0005, Yd + 0.0015, WGOLD, "Metal", 16)
    crystal(0.0162, Yd + 0.0019, H0 + 0.0104)
    # crown guards + big screw-down crown
    for sz in (-1, 1):
        prof = [(sz * 0.0028, H0 + 0.0018), (sz * 0.0062, H0 + 0.0022), (sz * 0.0064, H0 + 0.0066),
                (sz * 0.0028, H0 + 0.0070)]
        emit(slab_bm(prof, 0.0185, 0.0223, 0.0009, 2), STEEL, "Metal")
    crown_knurled(0.0194, H0 + 0.0044, 0.0038, 0.0052, STEEL, logo=True, ridges=30)
    bracelet(0.0238, oyster_row(STEEL, STEEL_B), 0.0071, 0.0198, 0.0165, 0.036,
             lambda s, L, w: cw_clasp(s, L, w, STEEL, STEEL_B, t=0.0037, engrave=(0.3, 0.31, 0.34)),
             filler=(STEEL_B, "Metal"), filler_t=0.0013)
    finish("Watch_Crownwell_Sub")


# ============================================================================= VALÈRE & FILS

def obus(th, r_in, r_out, w, y, h, col, kind="Metal", M=None):
    L = r_out - r_in
    Mx = (M if M is not None else Matrix.Identity(4)) @ Matrix.Translation(clock(th, (r_in + r_out) / 2, y)) @ Ry(th)
    prism([(-w / 2, -L / 2), (w / 2, -L / 2), (w / 2, L / 2 - w * 0.6), (0, L / 2), (-w / 2, L / 2 - w * 0.6)],
          0, h, col, kind, M=Mx, bevel=w * 0.42, seg=1, sharp=0.3)


def build_valere_calatrava():
    y0 = H0
    Yd = y0 + 0.0046
    M_, MB = ROSE, ROSE_B
    revolve([(0, y0), (0.0140, y0), (0.0165, y0 + 0.0004), (0.0182, y0 + 0.0013), (0.0189, y0 + 0.0026),
             (0.0188, y0 + 0.0038), (0.0184, y0 + 0.0044), (0.0160, y0 + 0.0044), (0.0156, Yd - 0.0005),
             (0, Yd - 0.0005)], M_, "Metal", 64)
    revolve([(0, y0 - 0.0001), (0.0128, y0 - 0.0001), (0.0134, y0 + 0.0002), (0, y0 + 0.0002)], MB, "Metal", 40)
    # Clous de Paris (hobnail) bezel: a checkerboard of raised points = a lattice of tiny pyramids
    segs = 100
    prof = [(0.0157, y0 + 0.0043), (0.0187, y0 + 0.0043), (0.0189, y0 + 0.0049), (0.0186, y0 + 0.0054),
            (0.01815, y0 + 0.0058), (0.0176, y0 + 0.0061), (0.01705, y0 + 0.0063), (0.0165, y0 + 0.0063),
            (0.0160, y0 + 0.0060), (0.0157, y0 + 0.0056)]

    def mod(th, r, y, k):
        if 2 <= k <= 7:
            i = round(th / TAU * segs)
            return r, y + (0.00026 if (i + k) % 2 == 0 else -0.00008)
        return r, y
    revolve(prof, M_, "Metal", segs, mod=mod, closed=True, sharp=0.35)
    # cream dial, railway track, applied obus indices, small seconds at 6
    dial = (0.95, 0.9, 0.77)
    disc(0.0158, Yd - 0.0004, Yd, dial, "Paint", 64)
    INK = (0.25, 0.2, 0.15)
    flat_ring(0.01465, 0.0148, Yd + EPS, INK, segs=64)
    flat_ring(0.0139, 0.01405, Yd + EPS, INK, segs=64)
    minute_track(0.01405, 0.01465, Yd + EPS, INK, w=0.0001)
    for h in range(12):
        th = TAU * h / 12
        if h == 6:
            continue
        if h == 0:
            for dx in (-0.0007, 0.0007):
                obus(th, 0.0105, 0.0135, 0.00085, Yd, 0.00045, M_, M=T((dx, 0, 0)))
            continue
        obus(th, 0.0108, 0.0135, 0.00095, Yd, 0.00045, M_)
    sc = Vector((0, 0, 0.0074))
    revolve([(0.0036, Yd + 0.00003), (0.0027, Yd + 0.00003), (0.0019, Yd + 0.00003), (0.0011, Yd + 0.00003),
             (0.0, Yd + 0.00003)], lambda c, n: (0.9, 0.84, 0.7) if int(math.hypot(c.x, c.z) / 0.0004) % 2 else
            (0.93, 0.87, 0.73), "Paint", 40, pos=sc, smooth=False)
    flat_ring(0.00355, 0.0037, Yd + 0.00005, INK, segs=40, pos=sc)
    for k in range(60):
        th = TAU * k / 60
        a = 0.0031 if k % 5 else 0.0028
        quad_between((sc + clock(th, a)).xz, (sc + clock(th, 0.00355)).xz, 0.00007 if k % 5 else 0.00012,
                     Yd + 0.00005, INK)
    for k, lab in ((0, "60"), (1, "15"), (2, "30"), (3, "45")):
        th = TAU * k / 4
        text(lab, 0.00072, INK, "Paint", sc + clock(th, 0.0021, Yd + 0.00005), fnt="serif")
    text("VALÈRE & FILS", 0.00112, INK, "Paint", (0, Yd + EPS, -0.0056), fnt="serif", spacing=1.05)
    text("GENÈVE", 0.00068, INK, "Paint", (0, Yd + EPS, -0.0043), fnt="sansr", spacing=1.35)
    th_h = TAU * (10 + 10 / 60) / 12
    th_m = TAU * 10 / 60
    hand(leaf_poly(0.0088, 0.00135, 0.0016), Yd + 0.0004, th_h, M_)
    hand(leaf_poly(0.0136, 0.00115, 0.0019), Yd + 0.00065, th_m, M_)
    disc(0.0007, Yd + 0.0003, Yd + 0.0009, M_, "Metal", 16)
    hand(leaf_poly(0.0032, 0.00045, 0.0008, 6), Yd + 0.0003, TAU * 38 / 60, M_, M=Matrix.Translation(sc))
    disc(0.0003, Yd + 0.0001, Yd + 0.0005, M_, "Metal", 10, pos=sc)
    crystal(0.0162, Yd + 0.0014, y0 + 0.0069)
    crown_knurled(0.0186, y0 + 0.0024, 0.0023, 0.0034, M_, ridges=20, tube_r=0.0009)
    yi = band_y(0.0232)
    lugs(0.0098, 0.0118, 0.0140, 0.0232, y0 + 0.0042, yi + 0.0034 + 0.0009, y0 + 0.0006, yi + 0.0001, M_,
         bevel=0.0006)
    leather_strap(0.0232, 0.0196, 0.0158, 0.0036, 0.0026, (0.34, 0.18, 0.08), (0.62, 0.46, 0.3), (0.2, 0.1, 0.05),
                  M_, kind="Gloss", cols=5, scale=0.0019)
    finish("Watch_Valere_Calatrava")


def naut_outline(R=0.0207, corner=0.0058):
    return rounded_poly(8, R, corner, phase=math.pi / 8, per=5)


def nautilus_row(metal, metal_b, t=0.0032):
    def row(M, w, p, i, side):
        ow = w * 0.37
        for sx in (-1, 1):
            x0, x1 = sorted((sx * w / 2, sx * (w / 2 - ow)))
            link(M, x0, x1, p * 0.93, t, 0.0013, brushed(metal, metal_b, 0.97), cap=0.0003)
        cw = w - 2 * ow
        link(M, -cw / 2 + 0.0002, cw / 2 - 0.0002, p * 0.5, t * 1.08, 0.0009, metal, z=p * 0.5, cap=0.0002, n=2)
        link(M, -cw / 2 + 0.0004, cw / 2 - 0.0004, p * 0.42, t * 0.9, 0.0006, metal_b, z=0.0, cap=0.0, n=1)
    return row


def build_valere_nautilus():
    y0 = H0
    Yd = y0 + 0.0060
    case_o = naut_outline(0.0212, 0.0062)
    bez_o = naut_outline(0.0206, 0.0058)
    N = 96
    bm = solid_shape_bm(lambda n: resample_polar(case_o, n), [(0.0016, y0), (0.0004, y0 + 0.0008), (0.0, y0 + 0.0018),
                                                               (0.0, y0 + 0.0040), (0.0005, y0 + 0.0046)], N)
    emit(bm, brushed(STEEL, STEEL_B, 0.97), "Metal")
    revolve([(0, Yd - 0.0006), (0.0152, Yd - 0.0006), (0.0152, y0 + 0.0046), (0, y0 + 0.0046)], STEEL_B, "Metal", 48)
    for sx in (-1, 1):                                  # the "ears" (hinges) at 3 and 9
        box((0.0042, 0.0046, 0.0105), STEEL, "Metal", (sx * 0.0206, y0 + 0.0027, 0), r=0.0017, seg=3)
    prof = [("i", 0.0, y0 + 0.0044), ("o", 0.0, y0 + 0.0044), ("o", 0.0, y0 + 0.0070), ("o", 0.0006, y0 + 0.0080),
            ("i", 0.0014, y0 + 0.0080), ("i", 0.0, y0 + 0.0072)]
    emit(shaped_ring_bm(lambda n: resample_polar(bez_o, n), lambda n: [(0.0147 * math.sin(TAU * i / n),
                                                                        -0.0147 * math.cos(TAU * i / n))
                                                                       for i in range(n)], prof, N),
         brushed(STEEL, STEEL_B, 0.97), "Metal", sharp=0.5)
    # blue-black dial with horizontal embossed bands
    def grad(c, n):
        k = 1.0 - 0.55 * min(math.hypot(c.x, c.z) / 0.015, 1.0)
        return (0.03 + 0.08 * k, 0.05 + 0.12 * k, 0.1 + 0.22 * k)
    disc(0.0150, Yd - 0.0004, Yd, grad, "Gloss", 48)
    z = -0.0141
    while z < 0.0142:
        half = math.sqrt(max(0.0147 ** 2 - z * z, 0.0)) - 0.0002
        if half > 0.001:
            box((2 * half, 0.00012, 0.00052), grad(Vector((0, 0, z)), None), "Gloss", (0, Yd + 0.00006, z),
                smooth=False)
        z += 0.00105
    Yp = Yd + 0.00013
    for h in range(12):
        if h == 3:
            continue
        th = TAU * h / 12
        baton(th, 0.0098, 0.0133, 0.0016 if h else 0.0019, Yp, 0.0005, WGOLD, lume=LUME, bevel=0.0005)
    minute_track(0.0139, 0.0145, Yp + EPS, (0.85, 0.87, 0.9), w=0.0001, skip=(15,))
    text("VALÈRE & FILS", 0.00108, (0.92, 0.93, 0.95), "Paint", (0, Yp + EPS, -0.0062), fnt="serif")
    text("GENÈVE", 0.00064, (0.92, 0.93, 0.95), "Paint", (0, Yp + EPS, -0.0050), fnt="sansr", spacing=1.35)
    text("AUTOMATIC", 0.00062, (0.92, 0.93, 0.95), "Paint", (0, Yp + EPS, 0.0062), fnt="sansr", spacing=1.2)
    cw_date(Yp, WGOLD, x=0.0118, disc_col=(0.96, 0.96, 0.95), size=0.0019)
    cw_hands_baton(Yp, WGOLD, LUME)
    crystal(0.0150, y0 + 0.0072, y0 + 0.0086)
    crown_knurled(0.0226, y0 + 0.0027, 0.0027, 0.0038, STEEL, ridges=24, logo=False)
    # integrated end pieces: the bracelet grows out of the case
    zs = 0.0196
    yi = band_y(zs + 0.0014)
    for sz in (1, -1):
        prof = [(0.0150, y0 + 0.0044), (0.0180, y0 + 0.0043), (zs + 0.0014, yi + 0.0032), (zs + 0.0014, yi + 0.0002),
                (0.0185, y0 + 0.0002), (0.0150, y0 + 0.0008)]
        emit(slab_bm([(z * sz, y) for z, y in prof], -0.0108, 0.0108, 0.0006, 2), brushed(STEEL, STEEL_B, 0.97),
             "Metal", sharp=0.9)
    bracelet(zs + 0.0014, nautilus_row(STEEL, STEEL_B), 0.0066, 0.0216, 0.0176, 0.030,
             lambda s, L, w: cw_clasp_plain(s, L, w, STEEL, STEEL_B, "VALÈRE & FILS"), filler=(STEEL_B, "Metal"))
    finish("Watch_Valere_Nautilus")


def cw_clasp_plain(s_mid, L, w, metal, metal_b, name, t=0.0033, fnt="serif"):
    band_sweep(s_mid - L / 2, s_mid + L / 2, lambda f: w + 0.0004, lambda f: t, metal_b, "Metal",
               step=0.0016, r=0.0008)
    M = LOOP.frame(s_mid, t)
    text(name, 0.0013, tuple(v * 0.45 for v in metal_b), "Paint", (0, 0.00003, 0), theta=math.pi, M=M, fnt=fnt)
    for dz in (-L / 2 + 0.0012, L / 2 - 0.0012):
        box((w + 0.0002, 0.0005, 0.0006), metal, "Metal", (0, -0.0002, 0), M=LOOP.frame(s_mid + dz, t), r=0.0002,
            seg=1)


# ============================================================================= AUDEMONT ROYALE

def ro_row(metal, metal_b, t=0.0030):
    col = brushed(metal, metal_b, 0.97)

    def row(M, w, p, i, side):
        toward_case = -1 if side == 6 else 1         # local z toward the case
        ow = w * 0.40
        for sx in (-1, 1):
            xo, xi = sx * w / 2, sx * (w / 2 - ow)
            L = p * 0.9
            near = toward_case * L / 2
            # trapezoid: full width at the case end, narrower at the far end
            poly = [(xi, near), (xo, near), (xo - sx * ow * 0.14, -near), (xi, -near)]
            emit(prism_bm(poly, 0.0, t, 0.00055, 1), col, "Metal", M, sharp=0.5)
        cw = w - 2 * ow
        link(M, -cw / 2 + 0.00015, cw / 2 - 0.00015, p * 0.46, t * 0.96, 0.0005, metal, z=p * 0.5, cap=0.0, n=1)
    return row


def build_audemont_royaloak():
    y0 = H0
    Yd = y0 + 0.0064
    octa = rounded_poly(8, 0.0212, 0.0009, phase=math.pi / 8, per=2)
    case_o = superellipse(0.0199, 0.0226, 3.2, 96)
    N = 96
    emit(solid_shape_bm(lambda n: resample_polar(case_o, n), [(0.0015, y0), (0.0004, y0 + 0.0008), (0.0, y0 + 0.0016),
                                                               (0.0, y0 + 0.0044), (0.0008, y0 + 0.0052)], N),
         brushed(STEEL, STEEL_B, 0.97), "Metal", sharp=0.5)
    emit(solid_shape_bm(lambda n: resample_polar(octa, n), [(0.0010, y0 + 0.0050), (0.0010, y0 + 0.0058)], 64),
         (0.02, 0.02, 0.022), "Paint")                                                   # black gasket
    ring = lambda n: [(0.0150 * math.sin(TAU * i / n), -0.0150 * math.cos(TAU * i / n)) for i in range(n)]  # noqa
    prof = [("i", 0.0, y0 + 0.0057), ("o", 0.0003, y0 + 0.0057), ("o", 0.0, y0 + 0.0062), ("o", 0.0, y0 + 0.0072),
            ("o", 0.0011, y0 + 0.0085), ("i", 0.0011, y0 + 0.0085), ("i", 0.0, y0 + 0.0078)]
    emit(shaped_ring_bm(lambda n: resample_polar(octa, n), ring, prof, N), brushed(STEEL, STEEL_B, 0.97), "Metal",
         sharp=0.4)
    for k in range(8):                                   # hexagonal bezel screws
        th = math.pi / 8 + k * math.pi / 4
        p = clock(th, 0.0180)
        revolve([(0, y0 + 0.0084), (0.00112, y0 + 0.0084), (0.00112, y0 + 0.00872), (0.0009, y0 + 0.0089),
                 (0, y0 + 0.0089)], WGOLD, "Metal", 6, pos=p, phase=0.3 + k * 0.7, sharp=0.5)
    # "Grande Tapisserie" dial: a grid of little raised squares
    base = (0.035, 0.07, 0.17)
    disc(0.0152, Yd - 0.0004, Yd, base, "Gloss", 48)
    bm = bmesh.new()
    cols = []
    pitch, a, b, h = 0.00145, 0.00052, 0.00066, 0.00016
    n = int(0.0142 / pitch) + 1
    for i in range(-n, n + 1):
        for j in range(-n, n + 1):
            cx, cz = i * pitch, j * pitch
            if math.hypot(cx, cz) > 0.0137:
                continue
            top = [bm.verts.new((cx + x, Yd + h, cz + z)) for x, z in ((-a, a), (a, a), (a, -a), (-a, -a))]
            bot = [bm.verts.new((cx + x, Yd, cz + z)) for x, z in ((-b, b), (b, b), (b, -b), (-b, -b))]
            bm.faces.new(top)
            cols.append((0.12, 0.22, 0.44))
            for q in range(4):
                r_ = (q + 1) % 4
                bm.faces.new((bot[q], bot[r_], top[r_], top[q]))
                cols.append((0.07, 0.13, 0.28) if q % 2 else (0.09, 0.17, 0.34))
    emit(bm, cols, "Gloss", smooth=False, recalc=False)
    Yp = Yd + h
    flat_ring(0.0141, 0.0152, Yp + 0.00005, (0.05, 0.09, 0.2), "Gloss", 64)
    minute_track(0.0143, 0.0150, Yp + 0.00005 + EPS, (0.9, 0.92, 0.95), w=0.0001, skip=(15,))
    for hh in range(12):
        if hh == 3:
            continue
        th = TAU * hh / 12
        if hh == 0:
            for dx in (-0.0009, 0.0009):
                baton(th, 0.0098, 0.0134, 0.0012, Yp, 0.0005, WGOLD, lume=LUME, M=T((dx, 0, 0)), bevel=0.0002)
            continue
        baton(th, 0.0100, 0.0134, 0.0014, Yp, 0.0005, WGOLD, lume=LUME, bevel=0.0002)
    W = (0.93, 0.94, 0.96)
    text("AUDEMONT", 0.00125, WGOLD, "Metal", (0, Yp, -0.0063), extrude=0.00012, spacing=1.1)
    text("ROYALE", 0.00066, W, "Paint", (0, Yp + EPS, -0.0050), fnt="sansr", spacing=1.4)
    text("Automatic", 0.0009, W, "Paint", (0, Yp + EPS, 0.0060), fnt="serifi")
    cw_date(Yp, WGOLD, x=0.0114, size=0.0021)
    cw_hands_baton(Yp, WGOLD, LUME)
    crystal(0.0154, y0 + 0.0078, y0 + 0.0090)
    crown_knurled(0.0196, y0 + 0.0030, 0.0030, 0.0044, STEEL, ridges=12, tube_r=0.0012)
    # integrated "lugs": the case flows into a trapezoid first link
    zs = 0.0222
    yi = band_y(zs)
    for sz in (1, -1):
        prof = [(0.0170, y0 + 0.0052), (0.0205, y0 + 0.0046), (zs, yi + 0.0031), (zs, yi + 0.0002), (0.0195, y0),
                (0.0170, y0)]
        emit(slab_bm([(z * sz, y) for z, y in prof], -0.0128, 0.0128, 0.0006, 1), brushed(STEEL, STEEL_B, 0.97),
             "Metal", sharp=0.5)
    bracelet(zs, ro_row(STEEL, STEEL_B), 0.0070, 0.0250, 0.0172, 0.016,
             lambda s, L, w: cw_clasp_plain(s, L, w, STEEL, STEEL_B, "AUDEMONT", t=0.0031, fnt="sans"),
             filler=(STEEL_B, "Metal"))
    finish("Watch_Audemont_RoyalOak")


# ============================================================================= RENAUD MILLEAUX

def tonneau(ax=0.0198, az=0.0242, p=3.6, N=128):
    out = []
    for x, z in superellipse(ax, az, p, N):
        out.append((x * (1 - 0.09 * (z / az) ** 2), z))
    return out


def carbon(c, n):
    """Forged / layered carbon look from the face position (TPT stripes)."""
    v = math.sin(c.y * 7000 + 2.5 * math.sin(c.x * 900 + c.z * 500) + c.z * 300)
    w = math.sin(c.x * 1300 - c.z * 1700 + c.y * 3000)
    k = 0.5 + 0.35 * v + 0.15 * w
    if k > 0.8:
        return (0.3, 0.3, 0.32)
    if k > 0.6:
        return (0.17, 0.17, 0.18)
    if k > 0.35:
        return (0.09, 0.09, 0.1)
    return (0.05, 0.05, 0.055)


def bend(bm, k):
    """Curve a flat tonneau case down at the ends so it hugs the wrist."""
    for v in bm.verts:
        v.co.y -= k * v.co.z * v.co.z
    return bm


def build_renaud_rm():
    y0 = H0
    TI = (0.55, 0.57, 0.6)
    CARB_K = 5.5
    out = tonneau()
    N = 112
    samp = lambda o: (lambda n: resample_polar(o, n))  # noqa: E731
    emit(bend(solid_shape_bm(samp(out), [(0.0024, y0 - 0.0002), (0.0015, y0 + 0.0008), (0.0014, y0 + 0.0016)], N),
              CARB_K), TI, "Metal")                                                 # titanium case back
    op = [(x, z) for x, z in inset(resample_polar(out, 160), 0.0043)]
    emit(bend(shaped_ring_bm(samp(out), samp(op), [("i", 0.0, y0 + 0.0014), ("o", 0.0013, y0 + 0.0014),
                                                    ("o", 0.0003, y0 + 0.0022), ("o", 0.0, y0 + 0.0034),
                                                    ("o", 0.0, y0 + 0.0066), ("o", 0.0005, y0 + 0.0074),
                                                    ("i", 0.0, y0 + 0.0074)], N), CARB_K * 0.7), carbon,
         "Gloss", sharp=0.5)                                                       # carbon caseband (hollow)
    prof = [("i", 0.0, y0 + 0.0072), ("o", 0.0004, y0 + 0.0072), ("o", 0.0, y0 + 0.0080), ("o", 0.0008, y0 + 0.0101),
            ("i", 0.0009, y0 + 0.0101), ("i", 0.0, y0 + 0.0092)]
    emit(bend(shaped_ring_bm(samp(out), samp(op), prof, N), CARB_K * 0.35), carbon, "Gloss", sharp=0.5)   # bezel
    # 12 exposed spline screws on the bezel
    for k in range(12):
        th = TAU * (k + 0.5) / 12
        x, z = ray_outline(inset(resample_polar(out, 160), 0.0022), th)
        yb = y0 + 0.0101 - CARB_K * 0.35 * z * z
        revolve([(0, yb - 0.0002), (0.00088, yb - 0.0002), (0.00088, yb + 0.0002), (0.0007, yb + 0.00032),
                 (0, yb + 0.00032)], TI, "Metal", 10, pos=(x, 0, z))
        flat_poly(circle_poly(0.00036, 5), yb + 0.00034, (0.03, 0.03, 0.03), "Paint", M=T((x, 0, z), [("y", k)]))
    # orange flange with minute track + numerals
    fl = [(x, z) for x, z in inset(resample_polar(out, 160), 0.0068)]
    Yf = y0 + 0.0086
    emit(shaped_ring_bm(samp(op), samp(fl), [("i", 0.0, Yf - 0.0012), ("o", 0.0002, Yf - 0.0012), ("o", 0.0002, Yf),
                                              ("i", 0.0, Yf)], N), ORANGE, "Gloss", sharp=0.5)
    for m in range(60):
        th = TAU * m / 60
        a = ray_outline(op, th)
        b = ray_outline(fl, th)
        f = 0.25 if m % 5 else 0.55
        quad_between((a[0] * 0.985, a[1] * 0.985), (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f),
                     0.00012 if m % 5 else 0.00024, Yf + EPS, (0.98, 0.97, 0.95))
    for lab, th in (("12", 0.0), ("3", TAU / 4), ("6", TAU / 2), ("9", 3 * TAU / 4)):
        a = ray_outline(op, th)
        b = ray_outline(fl, th)
        text(lab, 0.0015, (0.98, 0.97, 0.95), "Paint", ((a[0] + b[0]) / 2 * 0.99, Yf + EPS, (a[1] + b[1]) / 2 * 0.99),
             th, fnt="sans")
    # skeleton movement
    Ym = y0 + 0.0026
    emit(solid_shape_bm(samp(fl), [(0.0, Ym - 0.0006), (0.0, Ym)], 64), (0.06, 0.06, 0.065), "Paint")     # dark back
    inner = [(x, z) for x, z in inset(fl, 0.0016)]
    emit(shaped_ring_bm(samp(fl), samp(inner), [("i", 0.0, Ym), ("o", 0.0, Ym), ("o", 0.0, Ym + 0.0012),
                                                 ("i", 0.0, Ym + 0.0012)], 64), TI, "Metal")        # frame
    gear(0.0054, 40, Ym + 0.0002, 0.0007, (0.0, 0, -0.0098), (0.78, 0.7, 0.5), spokes=5)                  # barrel
    gear(0.0031, 30, Ym + 0.0004, 0.0004, (0.0052, 0, -0.0032), (0.95, 0.75, 0.35), spokes=4)
    gear(0.0027, 26, Ym + 0.0003, 0.0004, (-0.0056, 0, 0.0014), (0.95, 0.75, 0.35), spokes=4)
    gear(0.0019, 18, Ym + 0.0005, 0.0003, (0.0050, 0, 0.0064), (0.95, 0.75, 0.35), spokes=3)              # escape
    bc = Vector((-0.0018, 0, 0.0112))                                                                     # balance
    revolve([(0.0034, Ym + 0.0004), (0.0040, Ym + 0.0004), (0.0040, Ym + 0.0010), (0.0034, Ym + 0.0010)],
            (0.95, 0.78, 0.4), "Metal", 40, pos=bc, closed=True)
    for k in range(3):
        box((0.0003, 0.0003, 0.0035), (0.95, 0.78, 0.4), "Metal", (0, Ym + 0.0007, -0.00175),
            M=Matrix.Translation(bc) @ Ry(TAU * k / 3 + 0.4), smooth=False)
    bm = bmesh.new()                                                                                       # hairspring
    prev = None
    for i in range(90):
        t = i / 89
        rr = 0.0005 + 0.0023 * t
        a = 5 * TAU * t
        p_in = bc + clock(a, rr - 0.00005, Ym + 0.00115)
        p_out = bc + clock(a, rr + 0.00005, Ym + 0.00115)
        cur = (bm.verts.new(p_in), bm.verts.new(p_out))
        if prev:
            bm.faces.new((prev[0], prev[1], cur[1], cur[0]))
        prev = cur
    emit(face_up(bm), (0.2, 0.3, 0.75), "Gloss", smooth=False, recalc=False)
    # bridges: titanium skeleton bars + red accent bridges (a V over the balance, a bar across the barrel)
    Yb = Ym + 0.0013
    for (x0, z0), (x1, z1), col in (((-0.0150, -0.0040), (0.0150, -0.0040), TI), ((-0.0135, 0.0075), (0.0020, 0.0185), RED),
                                    ((0.0135, 0.0075), (-0.0040, 0.0185), RED), ((-0.012, -0.0165), (0.012, -0.0165), RED),
                                    ((0.0, -0.0040), (0.0, -0.0150), TI), ((0.0150, 0.0020), (0.0040, 0.0060), TI)):
        d = Vector((x1 - x0, 0, z1 - z0))
        L = d.length
        th = math.atan2(d.x, -d.z)
        Mx = Matrix.Translation(((x0 + x1) / 2, 0, (z0 + z1) / 2)) @ Ry(th)
        prism([(-0.0009, -L / 2), (0.0009, -L / 2), (0.0009, L / 2), (-0.0009, L / 2)], Yb, Yb + 0.0007, col,
              "Metal" if col == TI else "Gloss", M=Mx, bevel=0.00025, seg=1)
    for x, z in ((-0.0135, 0.0075), (0.0135, 0.0075), (-0.012, -0.0165), (0.012, -0.0165), (0.0, -0.0098),
                 (0.0052, -0.0032), (-0.0056, 0.0014), (0.0150, 0.0020), (-0.0150, -0.0040), (0.0150, -0.0040)):
        disc(0.0005, Yb + 0.0007, Yb + 0.0009, TI, "Metal", 8, pos=(x, 0, z))
        sphere(0.00028, (0.75, 0.03, 0.08), "Gloss", (x, Yb + 0.00095, z), segs=6, rings=3)
    # the brand bar across the dial
    prism([(-0.0118, -0.0011), (0.0118, -0.0011), (0.0118, 0.0011), (-0.0118, 0.0011)], Yb + 0.0010, Yb + 0.0015,
          (0.1, 0.1, 0.11), "Gloss", M=T((0, 0, 0.0026)), bevel=0.0003)
    text("RENAUD MILLEAUX", 0.00105, (0.97, 0.97, 0.97), "Paint", (0, Yb + 0.0015 + EPS, 0.0026), fnt="sans")
    # open-worked hands with lume tips
    Yh = Yb + 0.0020
    th_h = TAU * (10 + 10 / 60) / 12
    th_m = TAU * 10 / 60
    hp = [(-0.0011, 0.0012), (0.0011, 0.0012), (0.0009, -0.0085), (0.0, -0.0100), (-0.0009, -0.0085)]
    mp = [(-0.0009, 0.0014), (0.0009, 0.0014), (0.0007, -0.0142), (0.0, -0.0160), (-0.0007, -0.0142)]
    outline_prism(hp, 0.00032, Yh, Yh + 0.00018, WGOLD, M=Ry(th_h))
    hand([(-0.00055, -0.0083), (0.00055, -0.0083), (0.0, -0.0095)], Yh + 0.00018, th_h, ORANGE, "Paint", 0.00003)
    outline_prism(mp, 0.00028, Yh + 0.0003, Yh + 0.00048, WGOLD, M=Ry(th_m))
    hand([(-0.0004, -0.0140), (0.0004, -0.0140), (0.0, -0.0155)], Yh + 0.00048, th_m, ORANGE, "Paint", 0.00003)
    disc(0.0012, Yh - 0.0002, Yh + 0.0006, TI, "Metal", 16)
    disc(0.0005, Yh + 0.0006, Yh + 0.0008, RED, "Gloss", 12)
    emit(solid_shape_bm(samp(op), [(0.0, y0 + 0.0090), (0.0, y0 + 0.0098), (0.0006, y0 + 0.0103)], 64),
         (0.9, 0.95, 1.0), "Glass")
    # crown with a red collar
    xc = ray_outline(out, TAU / 4)[0]
    revolve([(0.0021, 0), (0.0026, 0), (0.0026, 0.0012), (0.0021, 0.0012)], RED, "Gloss", 20, closed=True,
            M=T((xc - 0.0004, y0 + 0.0048, 0)) @ Matrix.Rotation(-math.pi / 2, 4, "Z"))
    crown_knurled(xc + 0.0008, y0 + 0.0048, 0.0034, 0.0046, TI, ridges=10, tube_r=0.0014)
    # red rubber strap with ribs, titanium folding clasp
    s6 = LOOP.s_for_z(0.0225)
    s12 = LOOP.L - s6
    sm = LOOP.L / 2
    RUB = (0.8, 0.07, 0.05)
    for a, b in ((s6, sm), (s12, sm)):
        strap_piece(a, b, lambda f: 0.0232 - 0.005 * f, lambda f: 0.0042 - 0.001 * f, lambda f: 0.0,
                    RUB, (0.55, 0.04, 0.03), (0.62, 0.05, 0.04), "Gloss", cols=1, scale=0.0021, groove=0.0006,
                    sink=0.0003, var=0.03, seed=5)
    for sz in (1, -1):                       # carbon strap lugs closing the gap to the case
        yi = band_y(0.0222)
        prof = [(0.0195, y0 + 0.0060), (0.0235, yi + 0.0050), (0.0235, yi + 0.0004), (0.0195, y0 + 0.0002)]
        emit(slab_bm([(z * sz, y) for z, y in prof], -0.0128, 0.0128, 0.0007, 2), carbon, "Gloss")
    band_sweep(sm - 0.017, sm + 0.017, lambda f: 0.0192, lambda f: 0.0012, (0.5, 0.52, 0.55),
               "Metal", off=0.0032, step=0.0017, r=0.0005)
    M = LOOP.frame(sm, 0.0044)
    text("R.MILLEAUX", 0.0017, (0.25, 0.26, 0.28), "Paint", (0, 0.00003, 0), theta=math.pi, M=M, fnt="sans")
    finish("Watch_Renaud_RM")


# ============================================================================= MAISON CARREL

def build_carrel_tank():
    y0 = H0
    M_, MB = GOLD, GOLD_B
    hxd, hzd = 0.0100, 0.0130
    Yd = y0 + 0.0040
    # brancards: rounded gold bars along the long sides that run on past the dial to form the horns
    for sx in (-1, 1):
        rings = []
        for i in range(25):
            z = -0.0205 + 0.041 * i / 24
            drop = 12 * max(abs(z) - 0.011, 0.0) ** 2
            sec = []
            for j in range(9):
                a = math.pi * j / 8
                sec.append((0.0114 + 0.00135 * math.cos(a), 0.0057 * math.sin(a)))
            sec += [(0.01005, 0.0), (0.01275, 0.0)]
            end = abs(z) > 0.0198
            shrink = 0.55 if end else 1.0
            rings.append([Vector((sx * (0.0114 + (x - 0.0114) * shrink), y0 - drop + y * shrink * (0.95 if end else 1),
                                  z)) for x, y in reversed(sec)] if sx < 0 else
                         [Vector((sx * (0.0114 + (x - 0.0114) * shrink), y0 - drop + y * shrink * (0.95 if end else 1),
                                  z)) for x, y in sec])
        emit(loft_bm(rings), M_, "Metal", sharp=0.9)
    for sz in (-1, 1):                                   # top / bottom rails
        box((0.0204, 0.0045, 0.0026), M_, "Metal", (0, y0 + 0.00245, sz * (hzd + 0.0012)), r=0.0008, seg=2)
    box((0.0232, 0.0030, 0.0290), MB, "Metal", (0, y0 + 0.0015, 0), r=0.0008, seg=2)                 # case back
    box((2 * hxd, 0.0006, 2 * hzd), (0.97, 0.96, 0.93), "Paint", (0, Yd - 0.0003, 0), smooth=False)   # dial
    INK = (0.05, 0.05, 0.06)
    numerals = ["XII", "I", "II", "III", "IIII", "V", "VI", "VII", "VIII", "IX", "X", "XI"]
    for h, lab in enumerate(numerals):
        th = TAU * h / 12
        x, z = ray_rect(th, hxd - 0.0021, hzd - 0.0024)
        text(lab, 0.0034, INK, "Paint", (x, Yd + EPS, z), th, fnt="serif", stretch=0.62)
    # railway minute track inside the numerals
    for (ax_, az_) in ((hxd - 0.0045, hzd - 0.0050), (hxd - 0.0053, hzd - 0.0058)):
        for sx in (-1, 1):
            flat_rect(0.00008, 2 * az_, INK, M=T((sx * ax_, Yd + EPS, 0)))
            flat_rect(2 * ax_ + 0.00008, 0.00008, INK, M=T((0, Yd + EPS, sx * az_)))
    for m in range(60):
        th = TAU * m / 60
        a = ray_rect(th, hxd - 0.0045, hzd - 0.0050)
        b = ray_rect(th, hxd - 0.0053, hzd - 0.0058)
        quad_between(a, b, 0.00008 if m % 5 else 0.00016, Yd + EPS, INK)
    text("MAISON CARREL", 0.00095, INK, "Paint", (0, Yd + EPS, -0.0040), fnt="serif", spacing=1.1)
    text("PARIS", 0.0006, INK, "Paint", (0, Yd + EPS, 0.0048), fnt="serif", spacing=1.3)
    # blued sword hands
    th_h = TAU * (10 + 10 / 60) / 12
    th_m = TAU * 10 / 60
    hand([(-0.00055, 0.0012), (0.00055, 0.0012), (0.00045, -0.0048), (0.00075, -0.0052), (0.0, -0.0068),
          (-0.00075, -0.0052), (-0.00045, -0.0048)], Yd + 0.0003, th_h, BLUED, "Gloss")
    hand([(-0.00045, 0.0014), (0.00045, 0.0014), (0.00035, -0.0082), (0.00062, -0.0086), (0.0, -0.0104),
          (-0.00062, -0.0086), (-0.00035, -0.0082)], Yd + 0.00055, th_m, BLUED, "Gloss")
    disc(0.0007, Yd, Yd + 0.0008, BLUED, "Gloss", 12)
    box((2 * hxd + 0.0004, 0.0009, 2 * hzd + 0.0004), (0.9, 0.95, 1.0), "Glass", (0, y0 + 0.0048, 0), r=0.0003,
        seg=1)
    # beaded crown with a blue cabochon, on the right brancard
    crown_knurled(0.0126, y0 + 0.0030, 0.0021, 0.0030, M_, ridges=8, tube_r=0.0009,
                  cab=(0.12, 0.22, 0.78), bead=0.16)
    leather_strap(0.0190, 0.0198, 0.0158, 0.0034, 0.0026, (0.075, 0.068, 0.062), (0.45, 0.33, 0.22),
                  (0.03, 0.03, 0.03), M_, kind="Gloss", cols=5, scale=0.0019)
    finish("Watch_Carrel_Tank")


# ============================================================================= display pieces

PILLOW_MOUNT_Y = 0.031     # loop centre above the surface a watch-on-pillow stands on


def pillow(pos, col, M=None, length=0.042):
    """Velvet C-cushion around the X axis, shaped to the wrist loop so a watch wraps it snugly: slightly
    narrower than the loop where the band sits, bulging out past it at both ends."""
    def scf(a):
        a = abs(a)
        if a <= 0.3:
            return 0.985
        if a <= 0.78:
            return 0.985 + 0.065 * math.sin(math.pi / 2 * (a - 0.3) / 0.48)
        return 1.05 * math.sqrt(max(1 - ((a - 0.78) / 0.22) ** 2, 0.0))
    fxs = [-1.0, -0.995, -0.98, -0.95, -0.91, -0.86, -0.8, -0.7, -0.6, -0.5, -0.4, -0.3]
    fxs = fxs + [-f for f in reversed(fxs)]
    prof = [(fx, scf(fx)) for fx in fxs]
    NS = 40
    sec = [(LOOP.point(LOOP.L * i / NS).y, LOOP.point(LOOP.L * i / NS).z) for i in range(NS)]
    rings = []
    for fx, sc in prof:
        x = fx * length
        if sc < 1e-6:
            rings.append([Vector((x, 0.0, 0.0))] * 1)
        else:
            rings.append([Vector((x, y * sc * 0.995, z * sc * 0.995)) for y, z in sec])
    bm = bmesh.new()
    vr = []
    for r in rings:
        vr.append([bm.verts.new(p) for p in r])
    for k in range(len(vr) - 1):
        a, b = vr[k], vr[k + 1]
        n = NS
        for i in range(n):
            j = (i + 1) % n
            if len(a) == 1:
                bm.faces.new((a[0], b[j], b[i]))
            elif len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))

    def velvet(c, n):
        k = 0.78 + 0.3 * max(n.y, 0.0) + 0.08 * abs(n.x)
        return tuple(min(v * k, 1.0) for v in col)
    Mx = (M if M is not None else Matrix.Identity(4)) @ Matrix.Translation(Vector(pos))
    return emit(bm, velvet, "Paint", Mx)


def build_watch_pillow():
    pillow((0, PILLOW_MOUNT_Y, 0), (0.16, 0.15, 0.17))
    finish("WatchPillow", [("WatchPillow_Mount", (0.0, PILLOW_MOUNT_Y, 0.0))])


WATCHCASE_FLOOR = 0.817
WATCHCASE_SLOTS = [(x, WATCHCASE_FLOOR + PILLOW_MOUNT_Y, z) for z in (-0.12, 0.11) for x in (-0.38, 0.0, 0.38)]


def build_watch_case():
    """Jewellery vitrine counter, 1.2 x 1.0 x 0.6: lacquered walnut cabinet with brass trim, a glass box
    on top, charcoal velvet floor and six watch cushions. Origin = floor centre, customers at +Z."""
    WAL = (0.24, 0.13, 0.07)
    WAL_D = (0.14, 0.075, 0.04)
    BR = (0.93, 0.74, 0.38)
    box((1.14, 0.08, 0.54), (0.03, 0.03, 0.03), "Paint", (0, 0.04, 0), r=0.004)                    # plinth
    box((1.2, 0.72, 0.6), WAL, "Gloss", (0, 0.44, 0), r=0.012, seg=3)                               # cabinet
    for x in (-0.3, 0.3):                                                                             # front panels
        box((0.54, 0.56, 0.02), WAL_D, "Gloss", (x, 0.44, 0.3), r=0.008)
        box((0.5, 0.52, 0.012), WAL, "Gloss", (x, 0.44, 0.308), r=0.004)
    box((1.204, 0.018, 0.604), BR, "Metal", (0, 0.806, 0), r=0.004)                                 # brass cap
    box((1.18, 0.012, 0.012), BR, "Metal", (0, 0.09, 0.3), r=0.003)
    box((1.17, 0.012, 0.572), (0.13, 0.13, 0.14), "Paint", (0, WATCHCASE_FLOOR - 0.006, 0))          # velvet floor
    top = 1.0
    for sx in (-1, 1):                                                                                # brass frame
        for sz in (-1, 1):
            box((0.014, top - 0.812, 0.014), BR, "Metal", (sx * 0.593, (top + 0.812) / 2, sz * 0.293), r=0.003)
    for sz in (-1, 1):
        box((1.2, 0.014, 0.014), BR, "Metal", (0, top - 0.007, sz * 0.293), r=0.003)
    for sx in (-1, 1):
        box((0.014, 0.014, 0.6), BR, "Metal", (sx * 0.593, top - 0.007, 0), r=0.003)
    G_ = (0.85, 0.93, 0.95)
    box((1.17, 0.006, 0.572), G_, "Glass", (0, top - 0.003, 0))
    for sz in (-1, 1):
        box((1.17, top - 0.815, 0.006), G_, "Glass", (0, (top + 0.815) / 2, sz * 0.29))
    for sx in (-1, 1):
        box((0.006, top - 0.815, 0.572), G_, "Glass", (sx * 0.59, (top + 0.815) / 2, 0))
    box((1.1, 0.006, 0.01), (1.0, 0.95, 0.85), "Glow", (0, top - 0.018, -0.28))                     # LED strip
    for x, y, z in WATCHCASE_SLOTS:
        pillow((x, y, z), (0.2, 0.19, 0.21))
    # brass nameplate on the front
    box((0.24, 0.035, 0.006), BR, "Metal", (0, 0.76, 0.302), r=0.002)
    text("FINE WATCHES", 0.016, (0.12, 0.08, 0.04), "Paint", (0, 0, 0), fnt="serif", spacing=1.15,
         M=T((0, 0.76, 0.3052), [("x", math.pi / 2)]))
    finish("WatchCase", [("WatchCase_Slot%d" % (i + 1), p) for i, p in enumerate(WATCHCASE_SLOTS)])


BOX_FLOOR = 0.014
BOX_MOUNT = (0.0, BOX_FLOOR + PILLOW_MOUNT_Y, 0.008)


def build_watch_box():
    """Crownwell presentation box: green leather-look shell, cream suede lining, open lid with a gold crown.
    Origin = bottom centre, front +Z; the lid hinges at the back and stands open ~100 degrees."""
    GRN = (0.03, 0.34, 0.16)
    GRN_D = (0.02, 0.24, 0.11)
    CRM = (0.93, 0.88, 0.76)
    W, H, D = 0.15, 0.078, 0.14
    rng = random.Random(9)
    leather = lambda c, n: tuple(v * (0.93 + rng.random() * 0.1) for v in GRN)  # noqa: E731
    # base shell (open top): floor + four walls, lined inside
    box((W, 0.012, D), leather, "Gloss", (0, 0.006, 0), r=0.004, seg=2)
    for sx in (-1, 1):
        box((0.008, H, D), leather, "Gloss", (sx * (W / 2 - 0.004), H / 2, 0), r=0.003, seg=2)
    for sz in (-1, 1):
        box((W, H, 0.008), leather, "Gloss", (0, H / 2, sz * (D / 2 - 0.004)), r=0.003, seg=2)
    box((W - 0.016, 0.004, D - 0.016), CRM, "Paint", (0, BOX_FLOOR - 0.002, 0))
    for sx in (-1, 1):                                                                              # gold piping
        box((0.0012, 0.003, D + 0.0004), (0.95, 0.76, 0.36), "Metal", (sx * (W / 2 + 0.0002), H - 0.008, 0))
    for sz in (-1, 1):
        box((W + 0.0028, 0.003, 0.0012), (0.95, 0.76, 0.36), "Metal", (0, H - 0.008, sz * (D / 2 + 0.0002)))
    for sx in (-1, 1):
        box((0.002, H - 0.016, D - 0.018), CRM, "Paint", (sx * (W / 2 - 0.009), H / 2 + 0.004, 0))
    for sz in (-1, 1):
        box((W - 0.018, H - 0.016, 0.002), CRM, "Paint", (0, H / 2 + 0.004, sz * (D / 2 - 0.009)))
    pillow((BOX_MOUNT[0], BOX_MOUNT[1], BOX_MOUNT[2]), CRM, length=0.04)
    # lid, built closed around the hinge then swung open
    Lh = 0.034
    hinge = Matrix.Translation((0, H, -D / 2)) @ Matrix.Rotation(-math.radians(100), 4, "X")
    box((W, 0.008, D), leather, "Gloss", (0, Lh - 0.004, D / 2), r=0.004, seg=2, M=hinge)
    for sx in (-1, 1):
        box((0.008, Lh, D), leather, "Gloss", (sx * (W / 2 - 0.004), Lh / 2, D / 2), r=0.003, seg=2, M=hinge)
    for sz in (0, 1):
        box((W, Lh, 0.008), leather, "Gloss", (0, Lh / 2, 0.004 + sz * (D - 0.008)), r=0.003, seg=2, M=hinge)
    # satin lining inside the lid with the gold crown and name
    Mi = hinge @ T((0, Lh - 0.0085, D / 2), [("x", math.pi)])
    box((W - 0.016, 0.002, D - 0.016), CRM, "Paint", (0, -0.001, 0), M=Mi)
    crown_logo(0.026, 0.0, (0.96, 0.76, 0.3), "Metal", M=Mi, pos=(0, 0, -0.012), h=0.0008)
    text("CROWNWELL", 0.011, (0.8, 0.6, 0.22), "Metal", (0, 0.0001, 0.014), M=Mi, spacing=1.2)
    text("GENÈVE", 0.006, (0.8, 0.6, 0.22), "Paint", (0, 0.0001, 0.025), M=Mi, spacing=1.3)
    Mo = hinge @ T((0, Lh, D / 2))
    crown_logo(0.03, 0.0, (0.96, 0.76, 0.3), "Metal", M=Mo, pos=(0, 0, 0.0), h=0.001)
    box((0.03, 0.006, 0.006), (0.95, 0.76, 0.36), "Metal", (0, H + 0.001, -D / 2 - 0.001), r=0.002)   # hinge
    box((0.02, 0.012, 0.003), (0.95, 0.76, 0.36), "Metal", (0, H - 0.012, D / 2 + 0.0005), r=0.001)  # clasp
    finish("WatchBox_Crownwell", [("WatchBox_Crownwell_Mount", BOX_MOUNT)])


SHELF_TOPS = [0.78, 1.08, 1.38, 1.68]
SHELF_SLOTS = [(x, y, 0.17) for y in SHELF_TOPS for x in (-0.45, 0.0, 0.45)]


def build_wall_shelf():
    """Lit wall display, 1.5 wide x 2.0 tall, back on the wall (z = 0), front +Z. Walnut frame, a charcoal
    suede back panel washed by LED strips, four glass shelves on brass rails; WatchPillows stand on the
    shelves (SHELF_SLOTS). Origin = floor, centre of the wall face."""
    WAL = (0.2, 0.11, 0.06)
    BR = (0.93, 0.74, 0.38)
    SUEDE = (0.17, 0.17, 0.18)
    LED = (1.0, 0.95, 0.84)
    D = 0.32
    box((1.5, 2.0, 0.03), WAL, "Gloss", (0, 1.0, 0.015), r=0.006)                                # back board
    box((1.36, 1.3, 0.01), SUEDE, "Paint", (0, 1.2, 0.035))                                     # suede panel
    for sx in (-1, 1):                                                                           # cheeks
        box((0.07, 1.46, D), WAL, "Gloss", (sx * 0.715, 1.23, D / 2), r=0.01, seg=2)
        box((0.012, 1.3, 0.012), LED, "Glow", (sx * 0.677, 1.2, 0.08))
        box((0.004, 1.3, 0.02), BR, "Metal", (sx * 0.681, 1.2, D - 0.03))
    box((1.5, 0.14, D + 0.02), WAL, "Gloss", (0, 1.93, (D + 0.02) / 2), r=0.012, seg=2)             # canopy
    for x in (-0.45, 0.0, 0.45):
        disc(0.035, -0.004, 0.0, LED, "Glow", 20, pos=(x, 1.86, D * 0.55))
    box((0.5, 0.05, 0.006), BR, "Metal", (0, 1.93, D + 0.021), r=0.003)
    text("FINE WATCHES", 0.03, (0.12, 0.08, 0.04), "Paint", (0, 0.0, 0.0), fnt="serif", spacing=1.2,
         M=T((0, 1.93, D + 0.0245), [("x", math.pi / 2)]))
    box((1.5, 0.55, D + 0.04), WAL, "Gloss", (0, 0.275, (D + 0.04) / 2), r=0.012, seg=2)            # base cabinet
    box((1.5, 0.018, 0.008), BR, "Metal", (0, 0.545, D + 0.043), r=0.003)
    box((1.36, 0.08, 0.02), (0.03, 0.03, 0.03), "Paint", (0, 0.04, D + 0.03))                      # toe kick
    for y in SHELF_TOPS:
        box((1.36, 0.012, D - 0.04), (0.85, 0.93, 0.95), "Glass", (0, y - 0.006, (D - 0.04) / 2 + 0.03))
        box((1.36, 0.016, 0.008), BR, "Metal", (0, y - 0.004, D - 0.006), r=0.002)
        box((1.3, 0.006, 0.012), LED, "Glow", (0, y - 0.02, 0.06))
        for sx in (-1, 1):
            box((0.02, 0.03, D - 0.05), BR, "Metal", (sx * 0.67, y - 0.027, (D - 0.05) / 2 + 0.03), r=0.004)
    finish("WatchWallShelf", [("WatchWallShelf_Slot%d" % (i + 1), p) for i, p in enumerate(SHELF_SLOTS)])


# ============================================================================= main / preview

BUILDERS = [
    ("Watch_Crownwell_Datejust", build_crownwell_datejust),
    ("Watch_Crownwell_Iced", build_crownwell_iced),
    ("Watch_Crownwell_Sub", build_crownwell_sub),
    ("Watch_Valere_Calatrava", build_valere_calatrava),
    ("Watch_Valere_Nautilus", build_valere_nautilus),
    ("Watch_Audemont_RoyalOak", build_audemont_royaloak),
    ("Watch_Renaud_RM", build_renaud_rm),
    ("Watch_Carrel_Tank", build_carrel_tank),
    ("WatchCase", build_watch_case),
    ("WatchPillow", build_watch_pillow),
    ("WatchBox_Crownwell", build_watch_box),
    ("WatchWallShelf", build_wall_shelf),
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
