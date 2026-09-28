"""BAGHOLDERS props kit — every non-living thing in the office, built in Blender (bpy).

Run:  python3 tools/blender/build_props.py   (needs `pip install bpy==4.5.*`)
Out:  assets/props/props_kit.glb

Style: the trailer's soft, chunky, slightly toy-like office — rounded (beveled)
edges on everything, flat saturated colors, beige CRTs, blue task chairs, red
carpet, grey drop ceiling. Colors are baked as vertex colors (sRGB values). Each prop is ONE mesh whose surfaces use a handful of shared
materials, so Godot batches the whole office into a few draw calls:

  Paint  matte (most things)      Gloss  shiny plastic / screens
  Metal  brushed metal            Glow   unshaded, self-lit (lamps, screens, LEDs)

Coordinates are written in GODOT space (x right, y up, +z = the prop's front,
toward the viewer) and converted to Blender (x, -z, y) on the way in. Origin is
where the prop touches the floor (or the desk / wall) unless noted.
"""
import math
import os
import random

import bpy  # noqa: I001  (bpy must be imported before bmesh/mathutils)
import bmesh
from mathutils import Matrix, Vector

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "props", "props_kit.glb")
random.seed(11)

PARTS = []   # parts of the prop being built
KIT = []     # finished props


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ----------------------------------------------------------------------------- basics

def lin(c):
    """Vertex colors are stored as the sRGB numbers written here, NOT linearized:
    Godot's Compatibility renderer multiplies COLOR in as-is, so this is what
    makes a prop's (0.74, 0.76, 0.8) render like an albedo_color of the same value."""
    return (c[0], c[1], c[2])


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
        if kind == "Glass":   # vitrine panes (as in watches_kit); PropKit swaps in its see-through material
            bsdf.inputs["Alpha"].default_value = 0.15
            bsdf.inputs["Roughness"].default_value = 0.05
            m.surface_render_method = "BLENDED"
        MATS[kind] = m
    return MATS[kind]


def G(v):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return Vector((v[0], -v[2], v[1]))


AX = {"x": Vector((1, 0, 0)), "y": Vector((0, 0, 1)), "z": Vector((0, -1, 0))}


def rmat(rot):
    """rot: [(axis, radians), ...] in Godot axes, applied first to last."""
    m = Matrix.Identity(4)
    for ax, a in rot or []:
        m = Matrix.Rotation(a, 4, AX[ax]) @ m
    return m


def emit(bm, col, kind="Paint", pos=(0, 0, 0), rot=None, smooth=True, matrix=None):
    M = matrix if matrix is not None else Matrix.Translation(G(pos)) @ rmat(rot)
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    me = bpy.data.meshes.new("part")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("part", me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = smooth
    a = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    c = lin(col)
    for i in range(len(me.vertices)):
        a.data[i].color = (c[0], c[1], c[2], 1.0)
    me.color_attributes.active_color = a
    me.materials.append(mat(kind))
    PARTS.append(ob)
    return ob


def _sharpen(bm, angle=0.75):
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0) > angle:
            e.smooth = False


def rbox(size, pos, col, r=0.0, seg=2, kind="Paint", rot=None):
    """Box with rounded (beveled) edges. size/pos in Godot space."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    s = Vector((size[0], size[2], size[1]))
    for v in bm.verts:
        v.co = Vector((v.co.x * s.x, v.co.y * s.y, v.co.z * s.z))
    if r > 0:
        r = min(r, 0.49 * min(size))
        bmesh.ops.bevel(bm, geom=list(bm.verts) + list(bm.edges), offset=r, offset_type="OFFSET",
                        segments=seg, profile=0.5, affect="EDGES", clamp_overlap=True)
    _sharpen(bm)
    return emit(bm, col, kind, pos, rot)


def cyl(r, h, pos, col, segs=24, kind="Paint", rot=None, r2=None, caps=True):
    """Cylinder / cone along Godot Y, centered on pos."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segs, radius1=r,
                          radius2=r if r2 is None else r2, depth=h)
    _sharpen(bm)
    return emit(bm, col, kind, pos, rot)


def ell(radii, pos, col, segs=20, rings=12, kind="Paint", rot=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * radii[0], v.co.y * radii[2], v.co.z * radii[1]))
    return emit(bm, col, kind, pos, rot)


def torus(R, r, pos, col, segs=28, rsegs=8, kind="Paint", rot=None, arc=2 * math.pi):
    """Ring lying flat in the Godot XZ plane (axis = Y)."""
    bm = bmesh.new()
    full = arc >= 2 * math.pi - 1e-4
    n = segs if full else segs + 1
    rings = []
    for i in range(n):
        a = arc * i / segs
        ring = []
        for j in range(rsegs):
            b = 2 * math.pi * j / rsegs
            d = R + r * math.cos(b)
            ring.append(bm.verts.new(G((d * math.cos(a), r * math.sin(b), d * math.sin(a)))))
        rings.append(ring)
    for i in range(segs if full else n - 1):
        r0, r1 = rings[i], rings[(i + 1) % n]
        for j in range(rsegs):
            bm.faces.new((r0[j], r0[(j + 1) % rsegs], r1[(j + 1) % rsegs], r1[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return emit(bm, col, kind, pos, rot)


def rod(a, b, r, col, segs=10, kind="Paint", r2=None):
    """Cylinder from point a to point b (Godot space)."""
    A, B = G(a), G(b)
    d = B - A
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r,
                          radius2=r if r2 is None else r2, depth=d.length)
    _sharpen(bm)
    q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    M = Matrix.Translation((A + B) / 2) @ q.to_matrix().to_4x4()
    return emit(bm, col, kind, matrix=M)


def lathe(profile, pos, col, segs=28, kind="Paint", rot=None, smooth=True):
    """Surface of revolution around Godot Y. profile: [(radius, y), ...] bottom->top."""
    bm = bmesh.new()
    rings = []
    for r, y in profile:
        if r < 1e-5:
            rings.append([bm.verts.new(G((0, y, 0)))])
        else:
            rings.append([bm.verts.new(G((r * math.cos(2 * math.pi * i / segs), y,
                                          r * math.sin(2 * math.pi * i / segs)))) for i in range(segs)])
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        if len(a) == 1 and len(b) == 1:
            continue
        for i in range(segs):
            if len(a) == 1:
                bm.faces.new((a[0], b[(i + 1) % segs], b[i]))
            elif len(b) == 1:
                bm.faces.new((a[i], a[(i + 1) % segs], b[0]))
            else:
                bm.faces.new((a[i], a[(i + 1) % segs], b[(i + 1) % segs], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _sharpen(bm, 0.9)
    return emit(bm, col, kind, pos, rot, smooth=smooth)


def extrude(points_zy, x0, x1, col, kind="Paint"):
    """Side profile (Godot z, y) extruded along X from x0 to x1 — cabinets, lecterns."""
    bm = bmesh.new()
    vs = [bm.verts.new(G((x0, y, z))) for z, y in points_zy]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    moved = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((x1 - x0, 0, 0)), verts=moved)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _sharpen(bm, 0.3)
    return emit(bm, col, kind)


def prism(pts, axis, a0, a1, col, r=0.0, seg=2, kind="Paint"):
    """2D outline extruded along a Godot axis from a0 to a1, optionally with rounded edges.
    axis "x": pts are (z, y);  "z": pts are (x, y);  "y": pts are (x, z)."""
    def P(u, v, a):
        return {"x": (a, v, u), "z": (u, v, a), "y": (u, a, v)}[axis]
    bm = bmesh.new()
    lo = [bm.verts.new(G(P(u, v, a0))) for u, v in pts]
    hi = [bm.verts.new(G(P(u, v, a1))) for u, v in pts]
    bm.faces.new(lo)
    bm.faces.new(hi)
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if r > 0:
        bmesh.ops.bevel(bm, geom=list(bm.verts) + list(bm.edges), offset=r, offset_type="OFFSET",
                        segments=seg, profile=0.5, affect="EDGES", clamp_overlap=True)
    _sharpen(bm)
    return emit(bm, col, kind)


def xform_since(n0, pos=(0, 0, 0), rot=None):
    """Move/rotate (Godot space) every part emitted since PARTS had n0 entries — reuses a
    sub-assembly (a gun) inside a bigger prop (a wall rack)."""
    M = Matrix.Translation(G(pos)) @ rmat(rot)
    for ob in PARTS[n0:]:
        ob.data.transform(M)
    return M


def GI(v):
    """Blender (x, y, z) -> Godot (x, y, z)."""
    return Vector((v[0], v[2], -v[1]))


def bbox_since(n0):
    """Godot-space (min, max) corners of the parts emitted since PARTS had n0 entries."""
    pts = [GI(v.co) for ob in PARTS[n0:] for v in ob.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


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
    wn.weight = 100
    KIT.append(ob)
    return ob


# ----------------------------------------------------------------------------- palette

WHITE_TOP = (0.94, 0.94, 0.92)
DESK_EDGE = (0.62, 0.63, 0.66)
STEEL = (0.62, 0.64, 0.68)
DARK_STEEL = (0.32, 0.33, 0.36)
BLACK = (0.08, 0.08, 0.09)
BEIGE = (0.88, 0.83, 0.71)
BEIGE_D = (0.76, 0.7, 0.58)
BEIGE_L = (0.95, 0.92, 0.84)
CHAIR_BLUE = (0.16, 0.6, 0.7)     # the newer clips' teal task chairs
FABRIC = (0.84, 0.81, 0.76)
PANEL_FRAME = (0.6, 0.6, 0.62)
PAPER = (0.97, 0.97, 0.95)
GOLD = (1.0, 0.76, 0.2)
PURPLE = (0.36, 0.12, 0.62)
PURPLE_D = (0.2, 0.06, 0.36)
WOOD = (0.47, 0.28, 0.15)
WOOD_D = (0.3, 0.17, 0.09)
GREEN = (0.22, 0.55, 0.25)


# ----------------------------------------------------------------------------- bullpen

def build_desk():
    """1.9 x 0.9 white-top desk: left leg frame, right drawer pedestal (drawers face +z)."""
    rbox((1.9, 0.045, 0.9), (0, 0.757, 0), WHITE_TOP, r=0.012)
    rbox((1.9, 0.012, 0.9), (0, 0.73, 0), DESK_EDGE, r=0.004)          # underside edge band
    x = -0.86
    for z in (-0.36, 0.36):
        rbox((0.045, 0.71, 0.045), (x, 0.365, z), STEEL, r=0.01, kind="Metal")
    rbox((0.05, 0.03, 0.84), (x, 0.015, 0), STEEL, r=0.01, kind="Metal")
    rbox((0.04, 0.04, 0.78), (x, 0.69, 0), STEEL, r=0.01, kind="Metal")
    rbox((1.3, 0.34, 0.015), (-0.2, 0.52, -0.4), (0.72, 0.73, 0.76), r=0.005)  # modesty panel
    # drawer pedestal
    px = 0.63
    rbox((0.44, 0.69, 0.78), (px, 0.365, -0.02), (0.8, 0.81, 0.83), r=0.012)
    for k, (y, h) in enumerate(((0.58, 0.16), (0.4, 0.16), (0.16, 0.28))):
        rbox((0.4, h - 0.02, 0.02), (px, y, 0.375), (0.86, 0.87, 0.89), r=0.006)
        rbox((0.14, 0.018, 0.022), (px, y + h / 2 - 0.045, 0.39), DARK_STEEL, r=0.006, kind="Metal")
    finish("Desk")


def build_divider():
    """Fabric cubicle panel with a grey frame, 1.9 x 1.3, plane at z=0."""
    rbox((1.84, 1.22, 0.05), (0, 0.66, 0), FABRIC, r=0.012)
    rbox((1.92, 0.045, 0.075), (0, 1.285, 0), PANEL_FRAME, r=0.018)
    for x in (-0.94, 0.94):
        rbox((0.045, 1.3, 0.075), (x, 0.65, 0), PANEL_FRAME, r=0.015)
        rbox((0.07, 0.03, 0.32), (x * 0.9, 0.015, 0), DARK_STEEL, r=0.01)
    rbox((1.84, 0.06, 0.07), (0, 0.04, 0), PANEL_FRAME, r=0.01)
    # stuff pinned on the sitter's side (+z): sticky notes, a chart printout, a memo
    rbox((0.3, 0.22, 0.004), (0.55, 1.0, 0.027), PAPER)
    for k in range(5):  # candle chart on the printout
        h = random.uniform(0.03, 0.09)
        rbox((0.02, h, 0.002), (0.44 + k * 0.05, 0.96 + k * 0.012, 0.03), (0.2, 0.7, 0.3) if k % 2 == 0 else (0.85, 0.2, 0.2))
    rbox((0.1, 0.1, 0.004), (0.17, 1.08, 0.027), (1.0, 0.92, 0.35))
    rbox((0.1, 0.1, 0.004), (0.24, 0.96, 0.027), (1.0, 0.6, 0.75), rot=[("z", 0.12)])
    rbox((0.2, 0.26, 0.004), (-0.6, 0.98, 0.027), PAPER, rot=[("z", -0.05)])
    for k in range(5):
        rbox((0.14, 0.008, 0.002), (-0.6, 1.06 - k * 0.035, 0.03), (0.55, 0.55, 0.6), rot=[("z", -0.05)])
    finish("Divider")


def build_crt():
    """Beige CRT on a swivel foot. Origin: desk surface under the tube.
    Screen glass center (0, 0.31, 0.275); a label at z=0.29+ sits on it."""
    cyl(0.13, 0.02, (0, 0.01, -0.02), BEIGE_D, segs=28)
    rbox((0.17, 0.05, 0.17), (0, 0.045, -0.02), BEIGE_D, r=0.02)
    rbox((0.56, 0.47, 0.13), (0, 0.305, 0.195), BEIGE, r=0.04, seg=3)            # front bezel
    rbox((0.5, 0.42, 0.16), (0, 0.3, 0.07), BEIGE, r=0.06, seg=3)               # shoulders
    rbox((0.38, 0.32, 0.16), (0, 0.29, -0.07), BEIGE_D, r=0.07, seg=3)           # tube housing
    rbox((0.26, 0.22, 0.1), (0, 0.28, -0.18), BEIGE_D, r=0.05, seg=3)            # neck
    for k in range(5):                                                            # vents
        rbox((0.22, 0.008, 0.02), (0, 0.45, 0.1 - k * 0.04), (0.55, 0.5, 0.42))
    rbox((0.47, 0.37, 0.02), (0, 0.315, 0.257), (0.7, 0.65, 0.54), r=0.03, seg=3)  # inner lip
    rbox((0.42, 0.32, 0.03), (0, 0.315, 0.262), (0.035, 0.07, 0.07), r=0.035, seg=3, kind="Gloss")   # glass
    cyl(0.012, 0.01, (0.22, 0.1, 0.262), (0.55, 0.5, 0.42), rot=[("x", math.pi / 2)])  # power button
    ell((0.006, 0.006, 0.004), (0.19, 0.1, 0.262), (0.2, 1.0, 0.3), kind="Glow", segs=8, rings=4)
    rbox((0.1, 0.02, 0.004), (0, 0.105, 0.261), (0.62, 0.58, 0.48))                # badge
    finish("CRT")


def build_keyboard():
    rbox((0.46, 0.028, 0.165), (0, 0.014, 0), BEIGE, r=0.008)
    for row in range(5):
        cols = 15
        for c in range(cols):
            if row == 4 and 4 <= c <= 10:
                continue
            x = -0.2 + c * 0.0285
            rbox((0.023, 0.012, 0.022), (x, 0.032, -0.056 + row * 0.028), BEIGE_L if row else BEIGE_D)
    rbox((0.19, 0.012, 0.022), (-0.2 + 7 * 0.0285, 0.032, -0.056 + 4 * 0.028), BEIGE_L)  # spacebar
    finish("Keyboard")


def build_mouse():
    rbox((0.2, 0.004, 0.17), (0, 0.002, 0), (0.12, 0.2, 0.42), r=0.002)      # mouse pad
    ell((0.03, 0.02, 0.05), (0, 0.016, 0), BEIGE, segs=16, rings=10)
    rbox((0.002, 0.004, 0.03), (0, 0.035, -0.022), BEIGE_D)
    finish("Mouse")


def build_lamp():
    """Black articulated desk lamp (like the CRT close-up). Shade looks toward +z."""
    cyl(0.075, 0.022, (0, 0.011, 0), BLACK, kind="Gloss", segs=24)
    base, elbow, head = Vector((0, 0.02, -0.02)), Vector((0, 0.3, -0.1)), Vector((0, 0.42, 0.08))
    rod(base, elbow, 0.011, BLACK, kind="Gloss")
    rod(elbow, head, 0.01, BLACK, kind="Gloss")
    ell((0.02, 0.02, 0.02), elbow, (0.2, 0.2, 0.22), kind="Metal", segs=10, rings=6)
    ell((0.018, 0.018, 0.018), head, (0.2, 0.2, 0.22), kind="Metal", segs=10, rings=6)
    # cone shade aimed down-forward; the wide cap glows warm
    tilt = [("x", math.radians(125))]
    c = head + Vector((0, -0.03, 0.05))
    cyl(0.03, 0.13, c, BLACK, r2=0.095, kind="Gloss", rot=tilt, segs=24, caps=False)
    d = Vector((0, math.cos(math.radians(125)), math.sin(math.radians(125))))
    cyl(0.092, 0.004, c + d * 0.062, (1.0, 0.93, 0.7), kind="Glow", rot=tilt, segs=24)
    cyl(0.03, 0.004, c - d * 0.063, BLACK, kind="Gloss", rot=tilt, segs=16)
    finish("Lamp")


def build_chair():
    """Blue task chair, front +z. Seat top ~0.52."""
    for i in range(5):
        a = i * 2 * math.pi / 5
        dx, dz = math.sin(a), math.cos(a)
        rbox((0.05, 0.035, 0.3), (dx * 0.15, 0.07, dz * 0.15), BLACK, r=0.012, rot=[("y", a)], kind="Gloss")
        ell((0.022, 0.028, 0.03), (dx * 0.29, 0.03, dz * 0.29), (0.15, 0.15, 0.16), segs=10, rings=6)
    cyl(0.055, 0.06, (0, 0.08, 0), BLACK, kind="Gloss")
    cyl(0.034, 0.2, (0, 0.18, 0), BLACK, kind="Gloss")
    cyl(0.022, 0.18, (0, 0.34, 0), STEEL, kind="Metal")
    rbox((0.3, 0.04, 0.3), (0, 0.43, 0), BLACK, r=0.01)
    rbox((0.5, 0.09, 0.48), (0, 0.48, 0.01), CHAIR_BLUE, r=0.04, seg=3)
    rbox((0.07, 0.34, 0.035), (0, 0.6, -0.25), BLACK, r=0.012, kind="Gloss")
    rbox((0.46, 0.5, 0.085), (0, 0.93, -0.28), CHAIR_BLUE, r=0.04, seg=3, rot=[("x", -0.1)])
    for sx in (-1, 1):
        rbox((0.03, 0.2, 0.04), (sx * 0.265, 0.6, -0.02), BLACK, r=0.01, kind="Gloss")
        rbox((0.06, 0.03, 0.24), (sx * 0.265, 0.705, 0.01), BLACK, r=0.012)
    finish("Chair")


def build_clutter():
    # coffee mug
    lathe([(0.0, 0.0), (0.036, 0.0), (0.04, 0.005), (0.04, 0.095), (0.035, 0.095), (0.035, 0.012), (0.0, 0.012)],
          (0, 0, 0), (0.92, 0.22, 0.18), segs=20)
    torus(0.025, 0.007, (0.046, 0.05, 0), (0.92, 0.22, 0.18), segs=12, rsegs=6, rot=[("x", math.pi / 2)])
    cyl(0.034, 0.004, (0, 0.08, 0), (0.25, 0.14, 0.07), segs=16)
    finish("Mug")
    # paper stack
    for k in range(6):
        rbox((0.21, 0.004, 0.29), (random.uniform(-0.01, 0.01), 0.002 + k * 0.005, random.uniform(-0.01, 0.01)),
             PAPER if k % 3 else (0.93, 0.93, 0.9), rot=[("y", random.uniform(-0.08, 0.08))])
    finish("Papers")
    # cash bricks with a paper band
    for k, (x, z, y) in enumerate(((0, 0, 0), (0.17, 0.01, 0), (0.08, 0.0, 1))):
        rbox((0.16, 0.035, 0.07), (x, 0.018 + y * 0.036, z), (0.45, 0.68, 0.38), r=0.004)
        rbox((0.03, 0.037, 0.072), (x, 0.018 + y * 0.036, z), (0.95, 0.9, 0.6))
    finish("Cash")
    # ashtray + cigar
    lathe([(0.0, 0.0), (0.06, 0.0), (0.065, 0.025), (0.052, 0.025), (0.045, 0.012), (0.0, 0.012)],
          (0, 0, 0), (0.55, 0.62, 0.66), kind="Gloss", segs=20)
    rod((-0.02, 0.03, 0.0), (0.1, 0.034, 0.02), 0.011, (0.45, 0.28, 0.13), segs=10)
    ell((0.011, 0.011, 0.006), (-0.022, 0.03, 0), (1.0, 0.45, 0.08), kind="Glow", segs=8, rings=4)
    finish("Ashtray")
    # prescription pill bottle (the clips have one next to the money counter)
    lathe([(0.0, 0.0), (0.028, 0.0), (0.03, 0.004), (0.03, 0.078), (0.0, 0.078)], (0, 0, 0), (0.96, 0.55, 0.12), kind="Gloss", segs=18)
    lathe([(0.0, 0.076), (0.032, 0.076), (0.033, 0.1), (0.0, 0.1)], (0, 0, 0), (0.97, 0.97, 0.96), segs=18)
    cyl(0.0305, 0.04, (0, 0.04, 0), (0.97, 0.97, 0.95), segs=18, caps=False)   # label
    finish("PillBottle")
    # desk phone
    rbox((0.2, 0.05, 0.18), (0, 0.025, 0), (0.25, 0.26, 0.28), r=0.02, rot=[("x", 0.12)])
    rbox((0.19, 0.035, 0.05), (0, 0.065, -0.05), (0.18, 0.18, 0.2), r=0.017)
    for k in range(12):
        rbox((0.018, 0.006, 0.014), (-0.025 + (k % 3) * 0.025, 0.056, 0.0 + (k // 3) * 0.021), (0.85, 0.85, 0.85))
    finish("DeskPhone")
    # trash can
    lathe([(0.0, 0.0), (0.12, 0.0), (0.15, 0.35), (0.14, 0.35), (0.11, 0.015), (0.0, 0.015)],
          (0, 0, 0), (0.4, 0.42, 0.45), segs=24)
    ell((0.05, 0.04, 0.05), (0.02, 0.32, 0.03), PAPER, segs=10, rings=6)
    finish("Trash")


def build_filing_cabinet():
    rbox((0.46, 1.32, 0.62), (0, 0.66, 0), (0.62, 0.63, 0.67), r=0.015)
    for k in range(4):
        y = 0.18 + k * 0.315
        rbox((0.42, 0.29, 0.02), (0, y, 0.315), (0.68, 0.69, 0.73), r=0.008)
        rbox((0.16, 0.025, 0.03), (0, y + 0.05, 0.33), DARK_STEEL, r=0.01, kind="Metal")
        rbox((0.08, 0.04, 0.005), (0, y + 0.1, 0.327), PAPER)
    finish("FilingCabinet")


def build_water_cooler():
    rbox((0.34, 0.96, 0.34), (0, 0.48, 0), (0.93, 0.93, 0.95), r=0.03, seg=3)
    rbox((0.24, 0.22, 0.02), (0, 0.78, 0.17), (0.75, 0.76, 0.8), r=0.01)
    for x, c in ((-0.05, (0.2, 0.4, 0.95)), (0.05, (0.9, 0.15, 0.12))):
        rbox((0.035, 0.05, 0.04), (x, 0.8, 0.195), c, r=0.01, kind="Gloss")
    rbox((0.2, 0.02, 0.06), (0, 0.68, 0.19), (0.7, 0.7, 0.72))
    lathe([(0.0, 0.96), (0.07, 0.96), (0.07, 1.0), (0.14, 1.04), (0.145, 1.36), (0.1, 1.41), (0.0, 1.42)],
          (0, 0, 0), (0.45, 0.72, 0.98), kind="Gloss", segs=24)
    for y in (1.1, 1.26):
        torus(0.146, 0.006, (0, y, 0), (0.35, 0.62, 0.95), kind="Gloss", segs=24, rsegs=5)
    finish("WaterCooler")


def build_clock():
    """Wall clock, face toward +z. Origin at the center of the back."""
    cyl(0.2, 0.05, (0, 0, 0.025), BLACK, rot=[("x", math.pi / 2)], segs=32, kind="Gloss")
    cyl(0.18, 0.01, (0, 0, 0.052), PAPER, rot=[("x", math.pi / 2)], segs=32)
    for k in range(12):
        a = k * math.pi / 6
        L = 0.03 if k % 3 == 0 else 0.015
        rbox((0.008, L, 0.004), (math.sin(a) * 0.15, math.cos(a) * 0.15, 0.058), BLACK, rot=[("z", -a)])
    rbox((0.012, 0.09, 0.004), (0.03, 0.035, 0.062), BLACK, rot=[("z", -0.9)])
    rbox((0.008, 0.13, 0.004), (-0.04, -0.045, 0.066), BLACK, rot=[("z", -2.4)])
    rbox((0.003, 0.14, 0.003), (0.05, -0.04, 0.069), (0.9, 0.1, 0.1), rot=[("z", -3.9)])
    finish("Clock")


# ----------------------------------------------------------------------------- lounge

def build_couch():
    GREY = (0.55, 0.57, 0.62)
    GREY_L = (0.63, 0.65, 0.7)
    for x in (-1.05, 1.05):
        for z in (-0.33, 0.33):
            cyl(0.03, 0.08, (x, 0.04, z), WOOD_D, segs=10)
    rbox((2.3, 0.22, 0.85), (0, 0.19, 0), GREY, r=0.04, seg=3)
    for k in range(3):
        rbox((0.68, 0.14, 0.62), (-0.7 + k * 0.7, 0.36, 0.08), GREY_L, r=0.05, seg=3)
        rbox((0.68, 0.46, 0.2), (-0.7 + k * 0.7, 0.66, -0.29), GREY_L, r=0.06, seg=3, rot=[("x", -0.12)])
    rbox((2.3, 0.62, 0.18), (0, 0.51, -0.36), GREY, r=0.06, seg=3)
    for x in (-1.08, 1.08):
        rbox((0.2, 0.5, 0.85), (x, 0.4, 0), GREY, r=0.08, seg=3)
    finish("Couch")


def build_armchair():
    GREY = (0.6, 0.62, 0.66)
    for x in (-0.3, 0.3):
        for z in (-0.28, 0.28):
            rod((x, 0.0, z), (x * 0.9, 0.14, z * 0.9), 0.018, WOOD, segs=8)
    rbox((0.78, 0.16, 0.72), (0, 0.22, 0), GREY, r=0.05, seg=3)
    rbox((0.6, 0.12, 0.56), (0, 0.34, 0.06), (0.68, 0.7, 0.74), r=0.05, seg=3)
    rbox((0.78, 0.5, 0.16), (0, 0.52, -0.3), GREY, r=0.07, seg=3, rot=[("x", -0.15)])
    for x in (-0.35, 0.35):
        rbox((0.12, 0.26, 0.66), (x, 0.4, 0.01), GREY, r=0.05, seg=3)
    finish("Armchair")


def build_beanbag():
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=18, radius=1.0)
    for v in bm.verts:
        x, y, z = v.co.x, -v.co.y, v.co.z        # godot-ish: z up here is Blender z
        up = z
        r = 1.0 + 0.05 * math.sin(5 * math.atan2(y, x) + up * 3) * (1 - abs(up))
        bulge = 1.0 + 0.12 * (1 - up * up)          # fat middle, like a stuffed pouf
        px, pz = x * r * 0.44 * bulge, y * r * 0.44 * bulge
        h = up * 0.46
        if h < -0.24:
            h = -0.24 - (h + 0.24) * 0.1
        dent = 0.1 * math.exp(-((px + 0.04) ** 2 + (pz + 0.08) ** 2) / 0.04) if up > 0 else 0.0
        v.co = Vector((px, -pz, h - dent + 0.25))
    ob = emit(bm, (0.98, 0.78, 0.2))
    # baked shading: darker toward the floor so the blob reads as round
    col = ob.data.color_attributes["Col"]
    for i, v in enumerate(ob.data.vertices):
        k = 0.62 + 0.38 * min(1.0, v.co.z / 0.62)
        c = lin((0.98 * k, 0.78 * k, 0.2 * k))
        col.data[i].color = (c[0], c[1], c[2], 1.0)
    finish("Beanbag")


def build_coffee_table():
    CREAM = (0.93, 0.88, 0.76)
    cyl(0.6, 0.04, (0, 0.43, 0), CREAM, segs=40)
    torus(0.6, 0.022, (0, 0.43, 0), CREAM, segs=40, rsegs=8)
    cyl(0.07, 0.38, (0, 0.22, 0), CREAM, segs=16)
    cyl(0.32, 0.03, (0, 0.015, 0), CREAM, r2=0.28, segs=32)
    finish("CoffeeTable")


def build_plant():
    lathe([(0.0, 0.0), (0.16, 0.0), (0.21, 0.36), (0.225, 0.37), (0.225, 0.4), (0.19, 0.4), (0.18, 0.34), (0.0, 0.34)],
          (0, 0, 0), (0.93, 0.93, 0.92), segs=24)
    cyl(0.185, 0.02, (0, 0.35, 0), (0.28, 0.18, 0.1), segs=20)
    for k in range(16):
        yaw = k * 2.39996
        tilt = 0.2 + 0.9 * (k / 16)
        L = random.uniform(0.3, 0.46)
        d = Vector((math.sin(tilt) * math.sin(yaw), math.cos(tilt), math.sin(tilt) * math.cos(yaw)))
        c = Vector((0, 0.36, 0)) + d * L * 0.5
        col = (0.16 + random.uniform(0, 0.12), 0.48 + random.uniform(0, 0.15), 0.2)
        ell((0.045, L * 0.5, 0.01), c, col, segs=10, rings=8, rot=[("x", tilt), ("y", yaw)])
    finish("Plant")


def build_vending():
    """MONSTAR vending machine, front +z, 1.0 x 2.0 x 0.8. Header band at y 1.72-1.94."""
    NAVY = (0.05, 0.15, 0.5)
    rbox((1.0, 2.0, 0.8), (0, 1.0, 0), NAVY, r=0.03, seg=2)
    rbox((0.96, 0.24, 0.02), (0, 1.83, 0.405), (0.03, 0.03, 0.05), r=0.01)
    rbox((0.64, 1.4, 0.02), (-0.13, 1.0, 0.402), (0.72, 0.86, 1.0), kind="Glow")       # lit window
    rbox((0.66, 1.42, 0.02), (-0.13, 1.0, 0.398), (0.55, 0.57, 0.62), r=0.008, kind="Metal")
    can_cols = [(0.05, 0.05, 0.06), (0.2, 0.85, 0.3), (0.25, 0.5, 1.0), (0.95, 0.95, 0.95), (1.0, 0.55, 0.1)]
    for row in range(5):
        y = 0.42 + row * 0.27
        rbox((0.62, 0.012, 0.05), (-0.13, y - 0.02, 0.43), (0.8, 0.82, 0.86), kind="Metal")
        for c in range(6):
            col = can_cols[(row * 2 + c) % len(can_cols)] if c % 3 else can_cols[0]
            cyl(0.033, 0.12, (-0.4 + c * 0.108, y + 0.045, 0.435), col, segs=12, kind="Gloss")
            cyl(0.02, 0.005, (-0.4 + c * 0.108, y + 0.1, 0.435), (0.1, 0.9, 0.3), segs=8, kind="Glow") if c % 3 == 0 else None
    # control strip
    rbox((0.22, 1.1, 0.02), (0.36, 1.15, 0.405), (0.08, 0.08, 0.1), r=0.01)
    for k in range(12):
        rbox((0.035, 0.03, 0.012), (0.32 + (k % 3) * 0.04, 1.3 + (k // 3) * 0.04, 0.418), (0.8, 0.8, 0.82), r=0.004)
    rbox((0.12, 0.05, 0.012), (0.36, 1.55, 0.418), (0.2, 1.0, 0.4), kind="Glow")
    rbox((0.1, 0.03, 0.015), (0.36, 1.1, 0.418), (0.6, 0.6, 0.65), kind="Metal")
    rbox((0.04, 0.08, 0.015), (0.36, 0.98, 0.418), (0.6, 0.6, 0.65), kind="Metal")
    rbox((0.7, 0.2, 0.03), (-0.08, 0.18, 0.4), (0.03, 0.03, 0.04), r=0.01)            # pickup bin
    rbox((0.66, 0.16, 0.01), (-0.08, 0.18, 0.418), (0.14, 0.14, 0.16), r=0.006, rot=[("x", 0.15)])
    finish("Vending")


# ----------------------------------------------------------------------------- fun corner

def build_slot():
    """DEGEN SLOTS v2 (newer clips): charcoal cabinet, purple reel frame, red side
    panels, gold bulb marquee, -/+ bet buttons, gold lever with a blue knob.
    Front +z. Reel centers (x -0.29/0/0.29, y 1.16), marquee display center
    (0, 1.8, 0.2), bet readout (0, 0.86, 0.48)."""
    CHAR = (0.17, 0.18, 0.21)
    CHAR_L = (0.24, 0.25, 0.29)
    RED = (0.86, 0.1, 0.12)
    rbox((1.02, 0.8, 0.84), (0, 0.4, 0), CHAR, r=0.04, seg=3)
    rbox((1.06, 0.06, 0.88), (0, 0.03, 0), (0.1, 0.1, 0.12), r=0.02)
    rbox((0.56, 0.12, 0.14), (0, 0.6, 0.44), GOLD, r=0.03, kind="Metal")               # coin tray
    rbox((0.46, 0.06, 0.1), (0, 0.63, 0.46), (0.08, 0.06, 0.04), r=0.02)
    rbox((0.8, 0.26, 0.02), (0, 0.32, 0.425), CHAR_L, r=0.02)                           # belly panel
    # bet deck: red minus, readout, green plus on the front edge
    rbox((1.02, 0.16, 0.2), (0, 0.86, 0.38), CHAR_L, r=0.03)
    rbox((0.16, 0.1, 0.05), (-0.33, 0.86, 0.49), RED, r=0.02, kind="Gloss")
    rbox((0.07, 0.018, 0.01), (-0.33, 0.86, 0.518), PAPER)
    rbox((0.36, 0.09, 0.02), (0, 0.86, 0.485), (0.04, 0.05, 0.06), r=0.015)
    rbox((0.16, 0.1, 0.05), (0.33, 0.86, 0.49), (0.18, 0.8, 0.25), r=0.02, kind="Gloss")
    rbox((0.07, 0.018, 0.01), (0.33, 0.86, 0.518), PAPER)
    rbox((0.018, 0.06, 0.01), (0.33, 0.86, 0.519), PAPER)
    # reel section
    rbox((1.02, 0.74, 0.64), (0, 1.25, -0.08), CHAR, r=0.04, seg=3)
    rbox((0.9, 0.5, 0.02), (0, 1.16, 0.245), (0.05, 0.03, 0.08))
    for k in range(3):
        cyl(0.2, 0.24, (-0.29 + k * 0.29, 1.16, 0.23), (0.97, 0.95, 0.88), segs=24, rot=[("z", math.pi / 2)])
    for x in (-0.145, 0.145):
        rbox((0.04, 0.5, 0.06), (x, 1.16, 0.44), PURPLE, r=0.01)
    # purple frame + white light strips + red side panels
    for sx, sy, x, y in ((1.0, 0.07, 0, 1.445), (1.0, 0.07, 0, 0.875), (0.07, 0.64, -0.475, 1.16), (0.07, 0.64, 0.475, 1.16)):
        rbox((sx, sy, 0.07), (x, y, 0.44), (0.44, 0.16, 0.78), r=0.02, kind="Gloss")
    for x in (-0.425, 0.425):
        rbox((0.025, 0.5, 0.02), (x, 1.16, 0.46), (1.0, 1.0, 0.95), kind="Glow")
    for x in (-0.535, 0.535):
        rbox((0.06, 0.8, 0.3), (x, 1.2, 0.3), RED, r=0.02, kind="Gloss")
    # gold marquee with a dark display and bulbs all around
    rbox((1.14, 0.44, 0.2), (0, 1.8, 0.08), GOLD, r=0.05, seg=3, kind="Metal")
    rbox((1.2, 0.46, 0.4), (0, 1.8, -0.18), CHAR, r=0.05)
    rbox((0.96, 0.28, 0.02), (0, 1.8, 0.185), (0.05, 0.03, 0.09), r=0.02)
    for k in range(9):
        x = -0.5 + k * 0.125
        ell((0.024, 0.024, 0.024), (x, 1.99, 0.18), (1.0, 0.98, 0.9), kind="Glow", segs=8, rings=5)
        ell((0.024, 0.024, 0.024), (x, 1.61, 0.18), (1.0, 0.98, 0.9), kind="Glow", segs=8, rings=5)
    for x in (-0.535, 0.535):
        for y in (1.73, 1.87):
            ell((0.024, 0.024, 0.024), (x, y, 0.18), (1.0, 0.98, 0.9), kind="Glow", segs=8, rings=5)
    # lever: gold housing, gold arm, blue ball
    rbox((0.1, 0.18, 0.16), (0.58, 1.1, 0.0), GOLD, r=0.035, kind="Metal")
    rod((0.62, 1.1, 0.0), (0.66, 1.56, 0.03), 0.02, GOLD, kind="Metal")
    ell((0.065, 0.065, 0.065), (0.665, 1.61, 0.03), (0.15, 0.32, 0.95), kind="Gloss")
    finish("SlotMachine")


def build_coin():
    """Gold coin for the jackpot burst."""
    cyl(0.03, 0.006, (0, 0, 0), GOLD, segs=14, kind="Metal", rot=[("x", math.pi / 2)])
    finish("Coin")


def build_arcade():
    """Arcade cabinet, front +z, ~0.9 wide x 1.9 tall."""
    ORANGE = (0.96, 0.52, 0.08)
    prof = [(-0.4, 0.0), (0.32, 0.0), (0.32, 0.82), (0.44, 0.9), (0.44, 0.98), (0.2, 1.02),
            (0.16, 1.52), (0.3, 1.6), (0.3, 1.9), (-0.4, 1.9)]
    extrude(prof, -0.45, -0.41, ORANGE)
    extrude(prof, 0.41, 0.45, ORANGE)
    inner = [(z - 0.01 if z > 0 else z, y) for z, y in prof]
    extrude(inner, -0.41, 0.41, (0.08, 0.08, 0.1))
    rbox((0.82, 0.24, 0.02), (0, 1.75, 0.31), (1.0, 0.85, 0.3), kind="Glow")        # marquee
    # screen on the slanted face
    ang = math.atan2(0.04, 0.5)
    rbox((0.66, 0.46, 0.02), (0, 1.27, 0.19), (0.2, 0.25, 0.55), kind="Glow", rot=[("x", -ang)])
    rbox((0.74, 0.54, 0.015), (0, 1.27, 0.182), BLACK, rot=[("x", -ang)])
    # control panel
    rod((-0.18, 0.96, 0.33), (-0.18, 1.06, 0.33), 0.01, BLACK)
    ell((0.03, 0.03, 0.03), (-0.18, 1.07, 0.33), (0.9, 0.1, 0.1), kind="Gloss")
    for k in range(4):
        cyl(0.022, 0.02, (0.02 + (k % 2) * 0.08, 0.965, 0.3 + (k // 2) * 0.06), [(0.2, 0.5, 1), (1, 0.85, 0.1), (0.2, 0.8, 0.3), (1, 0.3, 0.6)][k], kind="Gloss")
    rbox((0.1, 0.1, 0.01), (0, 0.5, 0.325), (0.2, 0.2, 0.22), kind="Metal")           # coin door
    rbox((0.02, 0.05, 0.012), (0, 0.52, 0.33), (1.0, 0.3, 0.15), kind="Glow")
    finish("Arcade")


def build_bell_podium():
    """Wooden podium with a brass opening bell; front +z. Top at ~1.12."""
    rbox((0.95, 0.08, 0.66), (0, 0.04, 0), WOOD_D, r=0.02)
    prof = [(-0.26, 0.08), (0.26, 0.08), (0.26, 0.98), (0.3, 1.04), (-0.3, 1.1)]
    extrude(prof, -0.42, 0.42, WOOD)
    rbox((0.9, 0.04, 0.68), (0, 1.07, 0.0), WOOD_D, r=0.015, rot=[("x", 0.1)])
    rbox((0.86, 0.03, 0.02), (0, 0.9, 0.27), GOLD, kind="Metal")
    rbox((0.86, 0.03, 0.02), (0, 0.18, 0.27), GOLD, kind="Metal")
    cyl(0.12, 0.015, (0, 0.55, 0.265), GOLD, rot=[("x", math.pi / 2)], kind="Metal", segs=28)   # seal
    cyl(0.09, 0.02, (0, 0.55, 0.27), (0.1, 0.25, 0.55), rot=[("x", math.pi / 2)], segs=28)
    # bell on a little stand
    rbox((0.2, 0.04, 0.2), (0, 1.12, 0), WOOD_D, r=0.012)
    lathe([(0.0, 1.14), (0.15, 1.14), (0.14, 1.16), (0.11, 1.2), (0.09, 1.27), (0.06, 1.31), (0.02, 1.33), (0.0, 1.33)],
          (0, 0, 0), GOLD, kind="Metal", segs=32)
    ell((0.022, 0.022, 0.022), (0, 1.35, 0), GOLD, kind="Metal", segs=10, rings=6)
    finish("BellPodium")


def build_hoop():
    """Backboard (origin at its center, face +z), rim 0.3 out and 0.4 down."""
    rbox((1.5, 1.0, 0.05), (0, 0, 0), (0.97, 0.97, 0.98), r=0.02, kind="Gloss")
    for sx, sy, x, y in ((0.6, 0.04, 0, 0.1), (0.6, 0.04, 0, -0.33), (0.04, 0.47, -0.28, -0.115), (0.04, 0.47, 0.28, -0.115)):
        rbox((sx, sy, 0.01), (x, y, 0.03), (0.9, 0.15, 0.1))
    for sx, sy, x, y in ((1.5, 0.04, 0, 0.48), (1.5, 0.04, 0, -0.48), (0.04, 1.0, -0.73, 0), (0.04, 1.0, 0.73, 0)):
        rbox((sx, sy, 0.012), (x, y, 0.03), (0.9, 0.15, 0.1))
    rbox((0.16, 0.08, 0.14), (0, -0.4, 0.07), (0.9, 0.3, 0.1), r=0.01, kind="Metal")
    torus(0.225, 0.016, (0, -0.4, 0.3), (0.95, 0.35, 0.08), segs=32, rsegs=8, kind="Metal")
    top, bot = [], []
    for k in range(12):
        a = k * math.pi / 6
        top.append(Vector((math.cos(a) * 0.22, -0.41, 0.3 + math.sin(a) * 0.22)))
        bot.append(Vector((math.cos(a + 0.26) * 0.13, -0.8, 0.3 + math.sin(a + 0.26) * 0.13)))
    for k in range(12):
        rod(top[k], bot[k], 0.005, PAPER, segs=5)
        rod(top[k], bot[(k + 1) % 12], 0.005, PAPER, segs=5)
    torus(0.13, 0.005, (0, -0.8, 0.3), PAPER, segs=16, rsegs=4)
    torus(0.175, 0.005, (0, -0.6, 0.3), PAPER, segs=20, rsegs=4)
    finish("Hoop")


def build_certificate():
    rbox((0.4, 0.3, 0.03), (0, 0, 0.015), WOOD_D, r=0.008)
    rbox((0.34, 0.24, 0.004), (0, 0, 0.032), (0.97, 0.94, 0.86))
    rbox((0.2, 0.02, 0.002), (0, 0.07, 0.035), (0.3, 0.3, 0.35))
    for k in range(3):
        rbox((0.24, 0.008, 0.002), (0, 0.02 - k * 0.03, 0.035), (0.6, 0.6, 0.62))
    cyl(0.025, 0.004, (0.1, -0.07, 0.035), GOLD, rot=[("x", math.pi / 2)], segs=16, kind="Metal")
    finish("Certificate")


def build_whiteboard():
    """3.6 x 1.6 whiteboard, origin center, face +z."""
    rbox((3.6, 1.6, 0.03), (0, 0, 0.015), (0.98, 0.98, 0.98), kind="Gloss")
    for sx, sy, x, y in ((3.66, 0.035, 0, 0.81), (3.66, 0.035, 0, -0.81), (0.035, 1.66, -1.815, 0), (0.035, 1.66, 1.815, 0)):
        rbox((sx, sy, 0.045), (x, y, 0.022), (0.76, 0.78, 0.8), r=0.012, kind="Metal")
    rbox((1.4, 0.025, 0.09), (0, -0.84, 0.06), (0.76, 0.78, 0.8), r=0.008, kind="Metal")
    for k, c in enumerate(((0.9, 0.12, 0.1), (0.12, 0.3, 0.85), (0.08, 0.08, 0.09))):
        rod((-0.4 + k * 0.14, -0.815, 0.07), (-0.27 + k * 0.14, -0.815, 0.07), 0.01, c, segs=8, kind="Gloss")
    rbox((0.14, 0.04, 0.05), (0.35, -0.81, 0.07), (0.2, 0.2, 0.22), r=0.01)
    finish("Whiteboard")


def build_tv():
    """Big wall TV bezel 4.4 x 2.5 (screen quad sits at z 0.07 in Godot)."""
    rbox((4.4, 2.5, 0.1), (0, 0, 0), BLACK, r=0.03, kind="Gloss")
    rbox((0.3, 0.05, 0.012), (0, -1.2, 0.052), (0.35, 0.35, 0.38), kind="Metal")
    ell((0.012, 0.012, 0.005), (1.9, -1.2, 0.052), (1.0, 0.2, 0.2), kind="Glow", segs=8, rings=4)
    rbox((1.2, 0.7, 0.1), (0, 0, -0.1), (0.2, 0.2, 0.22))   # wall mount
    finish("TV")


def build_elevator():
    """Elevator bay, 2.8 wide, face +z. Origin at the wall face, floor.
    "Elevator" has its doors baked shut (the street lobby); "ElevatorFrame" is
    the same bay without doors, for the office where real doors slide open."""
    FRAME = (0.3, 0.31, 0.35)
    DOOR = (0.74, 0.76, 0.8)

    def bay():
        rbox((0.22, 2.55, 0.16), (-1.25, 1.275, 0.08), FRAME, r=0.02)
        rbox((0.22, 2.55, 0.16), (1.25, 1.275, 0.08), FRAME, r=0.02)
        rbox((2.72, 0.3, 0.16), (0, 2.45, 0.08), FRAME, r=0.02)
        rbox((2.3, 0.02, 0.1), (0, 0.01, 0.1), (0.8, 0.82, 0.86), kind="Metal")         # threshold
        rbox((0.62, 0.22, 0.05), (0, 2.46, 0.17), (0.05, 0.05, 0.06), r=0.015)             # floor display
        # call panel on the right
        rbox((0.14, 0.3, 0.02), (1.6, 1.2, 0.01), (0.7, 0.72, 0.76), r=0.01, kind="Metal")
        for y, c in ((1.26, (1.0, 0.95, 0.6)), (1.14, (0.9, 0.9, 0.9))):
            cyl(0.03, 0.02, (1.6, y, 0.025), c, rot=[("x", math.pi / 2)], kind="Glow" if y > 1.2 else "Gloss", segs=16)

    bay()
    for x in (-0.56, 0.56):
        rbox((1.1, 2.28, 0.05), (x, 1.14, 0.03), DOOR, r=0.01, kind="Metal")
        rbox((0.02, 2.2, 0.004), (x - 0.35 * (1 if x > 0 else -1) * 0, 1.14, 0.057), (0.66, 0.68, 0.72), kind="Metal")
    rbox((0.012, 2.28, 0.06), (0, 1.14, 0.035), (0.35, 0.36, 0.4))
    finish("Elevator")
    bay()
    finish("ElevatorFrame")
    # one sliding door leaf (the office animates two of these)
    rbox((1.12, 2.28, 0.05), (0, 1.14, 0), DOOR, r=0.01, kind="Metal")
    rbox((0.9, 0.012, 0.052), (0, 1.9, 0), (0.62, 0.64, 0.68), kind="Metal")
    rbox((0.9, 0.012, 0.052), (0, 0.4, 0), (0.62, 0.64, 0.68), kind="Metal")
    finish("ElevatorDoor")
    # the car: floor, wood-panel walls, brass rails, a light panel. Open at +z.
    WOOD_P = (0.42, 0.27, 0.16)
    rbox((2.4, 0.06, 2.3), (0, 0.03, -1.15), (0.2, 0.2, 0.22))                          # floor
    rbox((2.4, 2.5, 0.06), (0, 1.25, -2.3), WOOD_P)                                       # back
    for sx in (-1, 1):
        rbox((0.06, 2.5, 2.3), (sx * 1.2, 1.25, -1.15), WOOD_P)
        rbox((0.04, 0.04, 2.0), (sx * 1.12, 0.95, -1.2), GOLD, kind="Metal")             # rail
    rbox((2.2, 0.04, 0.04), (0, 0.95, -2.2), GOLD, kind="Metal")
    rbox((2.0, 0.9, 0.02), (0, 1.55, -2.26), (0.75, 0.82, 0.88), kind="Gloss")           # mirror
    rbox((2.4, 0.06, 2.3), (0, 2.5, -1.15), (0.85, 0.85, 0.86))                          # ceiling
    rbox((1.4, 0.02, 1.2), (0, 2.46, -1.15), (1.0, 0.96, 0.85), kind="Glow")             # light
    rbox((0.18, 0.36, 0.02), (1.16, 1.25, -0.4), (0.7, 0.72, 0.76), kind="Metal", rot=[("y", -math.pi / 2)])
    finish("ElevatorCar")


# ----------------------------------------------------------------------------- building

def build_ceiling_light():
    """Recessed 1.2 x 0.6 troffer. Origin: ceiling plane; hangs below it."""
    rbox((1.22, 0.035, 0.62), (0, -0.0175, 0), (0.86, 0.87, 0.9), r=0.006)
    rbox((1.14, 0.012, 0.54), (0, -0.041, 0), (1.0, 1.0, 0.98), kind="Glow")
    rbox((0.02, 0.016, 0.54), (0, -0.043, 0), (0.85, 0.86, 0.88))
    finish("CeilingLight")


def build_window_bay():
    """4 m window module for the north wall (face +z into the room).
    Wall below 0.9 and above 3.0 are separate boxes; this is sill, mullions, transom, blinds."""
    FR = (0.56, 0.58, 0.62)
    rbox((4.0, 0.06, 0.32), (0, 0.93, 0.04), (0.9, 0.9, 0.9), r=0.015)
    rbox((4.0, 0.1, 0.12), (0, 2.98, 0), FR, r=0.01, kind="Metal")
    for x in (-1.93, 1.93):
        rbox((0.14, 2.1, 0.16), (x, 1.95, 0), FR, r=0.02, kind="Metal")
    rbox((0.06, 2.1, 0.1), (0, 1.95, 0), FR, r=0.01, kind="Metal")
    rbox((4.0, 0.06, 0.1), (0, 2.45, 0), FR, r=0.01, kind="Metal")
    # half-raised blinds hanging at the top
    rbox((3.72, 0.05, 0.07), (0, 2.9, 0.1), (0.92, 0.92, 0.9), r=0.01)
    for k in range(7):
        rbox((3.7, 0.012, 0.06), (0, 2.85 - k * 0.035, 0.1), (0.95, 0.95, 0.93), rot=[("x", 0.4)])
    rod((1.75, 2.9, 0.14), (1.75, 2.55, 0.14), 0.004, (0.9, 0.9, 0.9), segs=4)
    finish("WindowBay")


def build_cell():
    """Holding-cell bars 6 m wide x 3 m (plane z=0), bench and a steel toilet."""
    BAR = (0.3, 0.32, 0.36)
    rbox((6.0, 0.1, 0.1), (0, 2.95, 0), BAR, kind="Metal")
    rbox((6.0, 0.08, 0.1), (0, 0.04, 0), BAR, kind="Metal")
    rbox((6.0, 0.06, 0.06), (0, 1.1, 0), BAR, kind="Metal")
    rbox((6.0, 0.06, 0.06), (0, 2.2, 0), BAR, kind="Metal")
    for k in range(13):
        cyl(0.025, 2.9, (-2.76 + k * 0.46, 1.48, 0), BAR, segs=10, kind="Metal")
    rbox((0.16, 0.24, 0.12), (1.2, 1.15, 0.06), (0.22, 0.23, 0.26), r=0.02, kind="Metal")    # lock box
    finish("CellBars")
    # bench against the back wall (+z = room side)
    rbox((4.0, 0.08, 0.6), (0, 0.45, 0), (0.55, 0.57, 0.6), r=0.015, kind="Metal")
    for x in (-1.7, 0, 1.7):
        rbox((0.06, 0.41, 0.5), (x, 0.205, -0.02), (0.4, 0.42, 0.45), kind="Metal")
    finish("CellBench")
    lathe([(0.0, 0.0), (0.16, 0.0), (0.2, 0.3), (0.24, 0.42), (0.2, 0.44), (0.16, 0.36), (0.0, 0.36)],
          (0, 0, 0.1), (0.7, 0.72, 0.76), kind="Metal", segs=24)
    rbox((0.4, 0.4, 0.14), (0, 0.4, -0.18), (0.62, 0.64, 0.68), r=0.03, kind="Metal")
    finish("CellToilet")


# ----------------------------------------------------------------------------- streamer corner

def build_stream_desk():
    """TJZ's battle station, 2.2 x 0.9, front +z. Three monitors, LED strip, mic arm."""
    rbox((2.2, 0.05, 0.9), (0, 0.755, 0), (0.1, 0.1, 0.11), r=0.015, kind="Gloss")
    rbox((2.2, 0.012, 0.012), (0, 0.73, 0.448), (0.6, 0.25, 1.0), kind="Glow")
    for x in (-1.02, 1.02):
        rbox((0.08, 0.72, 0.7), (x, 0.36, 0), (0.12, 0.12, 0.13), r=0.01)
        rbox((0.086, 0.012, 0.6), (x, 0.36, 0), (0.6, 0.25, 1.0), kind="Glow")
    for k in range(3):
        x = -0.66 + k * 0.66
        a = (k - 1) * 0.3
        c = Vector((x, 1.12, -0.22 + abs(k - 1) * 0.08))
        rbox((0.62, 0.38, 0.03), c, BLACK, r=0.01, kind="Gloss", rot=[("y", -a)])
        rbox((0.58, 0.34, 0.01), c + Vector((math.sin(-a) * 0.02, 0, math.cos(a) * 0.02)), (0.04, 0.12, 0.08), kind="Glow", rot=[("y", -a)])
        rod((x, 0.78, -0.3), (x, 1.0, -0.26), 0.015, (0.2, 0.2, 0.22), kind="Metal")
        rbox((0.2, 0.012, 0.14), (x, 0.786, -0.3), (0.2, 0.2, 0.22), r=0.004, kind="Metal")
        # a green candle chart on each screen
        for j in range(8):
            h = random.uniform(0.03, 0.12)
            up = j % 3 != 1
            off = Vector((-0.22 + j * 0.06, -0.08 + j * 0.02 + h / 2, 0))
            M = Matrix.Rotation(-a, 3, "Y")
            p = c + Vector((math.sin(-a) * 0.028, 0, math.cos(a) * 0.028)) + M @ off
            rbox((0.02, h, 0.004), p, (0.2, 1.0, 0.4) if up else (1.0, 0.25, 0.25), kind="Glow", rot=[("y", -a)])
    # RGB keyboard + mouse
    rbox((0.44, 0.025, 0.14), (0, 0.79, 0.18), (0.08, 0.08, 0.09), r=0.008)
    rbox((0.42, 0.006, 0.12), (0, 0.804, 0.18), (0.4, 0.2, 0.95), kind="Glow")
    ell((0.028, 0.018, 0.045), (0.36, 0.795, 0.2), BLACK, kind="Gloss", segs=12, rings=8)
    # boom mic
    rod((0.62, 0.78, -0.35), (0.62, 1.1, -0.3), 0.012, BLACK, kind="Gloss")
    rod((0.62, 1.1, -0.3), (0.38, 1.12, 0.05), 0.01, BLACK, kind="Gloss")
    cyl(0.035, 0.12, (0.36, 1.1, 0.08), (0.18, 0.18, 0.2), kind="Metal", rot=[("x", 0.9)])
    # energy can + cash
    cyl(0.033, 0.12, (-0.55, 0.84, 0.15), (0.06, 0.06, 0.07), segs=12, kind="Gloss")
    cyl(0.034, 0.03, (-0.55, 0.83, 0.15), (0.2, 0.9, 0.3), segs=12, kind="Glow")
    finish("StreamDesk")


def build_gaming_chair():
    """Black/purple racing chair, front +z."""
    PUR = (0.45, 0.18, 0.85)
    for i in range(5):
        a = i * 2 * math.pi / 5
        rbox((0.055, 0.04, 0.32), (math.sin(a) * 0.16, 0.07, math.cos(a) * 0.16), BLACK, r=0.015, rot=[("y", a)], kind="Gloss")
        ell((0.024, 0.03, 0.032), (math.sin(a) * 0.3, 0.03, math.cos(a) * 0.3), (0.15, 0.15, 0.16), segs=10, rings=6)
    cyl(0.03, 0.34, (0, 0.26, 0), STEEL, kind="Metal")
    rbox((0.54, 0.1, 0.52), (0, 0.48, 0.02), BLACK, r=0.045, seg=3)
    for x in (-0.25, 0.25):
        rbox((0.07, 0.1, 0.5), (x, 0.53, 0.02), PUR, r=0.03, seg=3)
    rbox((0.52, 0.86, 0.1), (0, 1.02, -0.29), BLACK, r=0.05, seg=3, rot=[("x", -0.12)])
    for x in (-0.23, 0.23):
        rbox((0.08, 0.8, 0.12), (x, 1.02, -0.27), PUR, r=0.035, seg=3, rot=[("x", -0.12)])
    rbox((0.26, 0.14, 0.06), (0, 1.3, -0.29), (0.9, 0.9, 0.95), r=0.03, rot=[("x", -0.12)])  # headrest pillow
    for sx in (-1, 1):
        rbox((0.035, 0.22, 0.04), (sx * 0.3, 0.62, -0.02), BLACK, r=0.01)
        rbox((0.07, 0.035, 0.26), (sx * 0.3, 0.735, 0.0), BLACK, r=0.014)
    finish("GamingChair")


def build_ring_light():
    for i in range(3):
        a = i * 2 * math.pi / 3
        rod((0, 0.5, 0), (math.sin(a) * 0.32, 0.0, math.cos(a) * 0.32), 0.012, BLACK, segs=6)
    rod((0, 0.5, 0), (0, 1.3, 0), 0.015, (0.2, 0.2, 0.22), kind="Metal", segs=8)
    torus(0.28, 0.035, (0, 1.58, 0), (1.0, 1.0, 1.0), rot=[("x", math.pi / 2)], kind="Glow", segs=36, rsegs=8)
    torus(0.28, 0.04, (0, 1.58, -0.01), (0.12, 0.12, 0.13), rot=[("x", math.pi / 2)], kind="Gloss", segs=36, rsegs=8)
    ell((0.05, 0.1, 0.012), (0, 1.58, 0), (0.1, 0.1, 0.1), kind="Gloss", segs=10, rings=6)   # phone holder
    finish("RingLight")


def build_neon_board():
    """Backing board for the KWIK LIVE sign, 2.6 x 0.7, face +z."""
    rbox((2.6, 0.7, 0.05), (0, 0, 0), (0.07, 0.05, 0.1), r=0.02)
    for sx, sy, x, y in ((2.5, 0.025, 0, 0.31), (2.5, 0.025, 0, -0.31), (0.025, 0.64, -1.24, 0), (0.025, 0.64, 1.24, 0)):
        rbox((sx, sy, 0.02), (x, y, 0.03), (0.65, 0.3, 1.0), kind="Glow")
    finish("NeonBoard")


# ----------------------------------------------------------------------------- skyline

SKY = (0.72, 0.77, 0.86)
SKY_D = (0.63, 0.68, 0.78)
WIN = (0.82, 0.88, 0.96)


def _banded(w, d, y0, y1, body, band_every=3.0, band_h=1.4, win=WIN, x=0.0, z=0.0):
    """Tower block w x d from y0..y1 with horizontal window bands on every face."""
    rbox((w, y1 - y0, d), (x, (y0 + y1) / 2, z), body)
    y = y0 + 2.0
    while y + band_h < y1 - 0.5:
        rbox((w + 0.08, band_h, d + 0.08), (x, y + band_h / 2, z), win)
        y += band_every


def _ribbed(w, d, y0, y1, body, x=0.0, z=0.0):
    """Tower with vertical window strips (art-deco look)."""
    rbox((w, y1 - y0, d), (x, (y0 + y1) / 2, z), body)
    n = max(2, int(w / 1.6))
    for k in range(n):
        o = -w / 2 + (k + 0.5) * w / n
        rbox((w / n * 0.45, y1 - y0 - 2.0, 0.1), (x + o, (y0 + y1) / 2, z + d / 2 + 0.02), WIN)
        rbox((w / n * 0.45, y1 - y0 - 2.0, 0.1), (x + o, (y0 + y1) / 2, z - d / 2 - 0.02), WIN)
        rbox((0.1, y1 - y0 - 2.0, w / n * 0.45), (x + d / 2 + 0.02, (y0 + y1) / 2, z + o * d / w), WIN)
        rbox((0.1, y1 - y0 - 2.0, w / n * 0.45), (x - d / 2 - 0.02, (y0 + y1) / 2, z + o * d / w), WIN)


def build_skyline():
    # A: plain banded slab
    _banded(8, 8, 0, 42, SKY)
    rbox((3, 2.5, 3), (1, 43.2, -1), SKY_D)
    finish("TowerA")
    # B: art-deco setbacks with vertical ribs + antenna
    _ribbed(10, 10, 0, 30, SKY)
    _ribbed(7.5, 7.5, 30, 42, SKY)
    _ribbed(5, 5, 42, 50, SKY)
    cyl(0.25, 8, (0, 54, 0), SKY_D, segs=8)
    finish("TowerB")
    # C: slim tower with a pyramid cap
    _banded(6, 6, 0, 58, SKY_D, band_every=2.5, band_h=1.1)
    cyl(4.24, 7, (0, 61.5, 0), SKY, r2=0.2, segs=4, rot=[("y", math.pi / 4)])
    finish("TowerC")
    # D: wide low block
    _banded(16, 10, 0, 20, (0.7, 0.74, 0.8), band_every=2.8, band_h=1.2)
    finish("TowerD")
    # E: the Empire State–style spire from the trailer
    _ribbed(14, 14, 0, 36, SKY)
    _ribbed(10, 10, 36, 58, SKY)
    _ribbed(7, 7, 58, 70, SKY)
    rbox((4.5, 5, 4.5), (0, 72.5, 0), SKY)
    cyl(1.6, 6, (0, 78, 0), SKY, r2=1.1, segs=12)
    cyl(1.1, 5, (0, 83.5, 0), SKY_D, r2=0.3, segs=12)
    cyl(0.18, 9, (0, 90.5, 0), SKY_D, segs=6)
    finish("EmpireState")


# ----------------------------------------------------------------------------- newer-clip decor

def build_bulletin_board():
    """Green cork board with pinned notes, 1.4 x 0.9, origin center, face +z."""
    rbox((1.4, 0.9, 0.04), (0, 0, 0.02), WOOD, r=0.012)
    rbox((1.32, 0.82, 0.01), (0, 0, 0.045), (0.3, 0.62, 0.3))
    notes = [(-0.45, 0.22, (1.0, 0.92, 0.35)), (-0.15, 0.25, PAPER), (0.2, 0.2, (1.0, 0.62, 0.75)),
             (0.45, 0.24, (0.55, 0.8, 1.0)), (-0.4, -0.15, PAPER), (-0.05, -0.2, (1.0, 0.92, 0.35)),
             (0.3, -0.18, PAPER), (0.52, -0.25, (1.0, 0.7, 0.3))]
    for x, y, c in notes:
        w, h = (0.2, 0.26) if c == PAPER else (0.13, 0.13)
        rbox((w, h, 0.004), (x, y, 0.053), c, rot=[("z", random.uniform(-0.12, 0.12))])
        ell((0.012, 0.012, 0.008), (x, y + h / 2 - 0.025, 0.058), (0.9, 0.15, 0.15), kind="Gloss", segs=8, rings=4)
        if c == PAPER:
            for k in range(4):
                rbox((w * 0.7, 0.008, 0.002), (x, y + 0.06 - k * 0.035, 0.056), (0.5, 0.5, 0.55))
    finish("BulletinBoard")


def build_door():
    """Restroom door. DoorFrame: origin floor center of the 1.0 m opening, face +z.
    DoorLeaf: origin at the hinge (left edge), leaf runs along +x, so it can swing."""
    FR = (0.36, 0.39, 0.46)
    rbox((0.1, 2.25, 0.18), (-0.55, 1.125, 0), FR, r=0.015)
    rbox((0.1, 2.25, 0.18), (0.55, 1.125, 0), FR, r=0.015)
    rbox((1.2, 0.1, 0.18), (0, 2.2, 0), FR, r=0.015)
    rbox((0.24, 0.24, 0.01), (0.8, 1.6, 0.0), PAPER, r=0.02)          # sign plate beside it
    finish("DoorFrame")
    rbox((0.98, 2.13, 0.05), (0.49, 1.075, 0), (0.2, 0.24, 0.34), r=0.01)
    for z in (0.03, -0.03):
        rbox((0.06, 0.2, 0.012), (0.86, 1.0, z), STEEL, r=0.005, kind="Metal")
        rod((0.86, 1.02, z * 1.6), (0.74, 1.02, z * 2.4), 0.012, STEEL, kind="Metal")
    finish("DoorLeaf")


def build_restroom():
    """Toilet + sink + mirror set, for the little restroom off the office."""
    PORC = (0.96, 0.96, 0.97)
    lathe([(0.0, 0.0), (0.13, 0.0), (0.16, 0.3), (0.2, 0.4), (0.17, 0.42), (0.13, 0.36), (0.0, 0.36)],
          (0, 0, 0.12), PORC, kind="Gloss", segs=24)
    rbox((0.4, 0.34, 0.16), (0, 0.6, -0.12), PORC, r=0.03, kind="Gloss")
    rbox((0.36, 0.03, 0.4), (0, 0.44, 0.1), PORC, r=0.015, kind="Gloss")
    rbox((0.06, 0.02, 0.03), (0.15, 0.79, -0.08), STEEL, kind="Metal")
    finish("Toilet")
    rbox((0.5, 0.14, 0.4), (0, 0.8, 0), PORC, r=0.04, kind="Gloss")
    rbox((0.36, 0.06, 0.26), (0, 0.85, 0.02), (0.8, 0.84, 0.88), r=0.03, kind="Gloss")
    rbox((0.1, 0.72, 0.1), (0, 0.36, -0.08), PORC, r=0.03, kind="Gloss")
    rod((0, 0.87, -0.15), (0, 0.97, -0.09), 0.012, STEEL, kind="Metal")
    rbox((0.5, 0.7, 0.02), (0, 1.45, -0.19), (0.75, 0.85, 0.92), kind="Gloss")      # mirror
    rbox((0.54, 0.74, 0.015), (0, 1.45, -0.2), STEEL, kind="Metal")
    finish("Sink")


def build_floor_mess():
    """Loose clutter for the floor: a dollar bill, a crumpled paper ball, a cigar butt."""
    rbox((0.16, 0.003, 0.07), (0, 0.0015, 0), (0.55, 0.75, 0.45), rot=[("x", 0.05), ("z", 0.04)])
    rbox((0.13, 0.004, 0.05), (0, 0.004, 0), (0.42, 0.62, 0.36))
    finish("Bill")
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.045)
    for v in bm.verts:
        v.co *= random.uniform(0.75, 1.15)
    emit(bm, PAPER, pos=(0, 0.04, 0), smooth=False)
    finish("PaperBall")
    rod((-0.03, 0.009, 0), (0.03, 0.009, 0.01), 0.009, (0.45, 0.28, 0.13), segs=8)
    ell((0.0095, 0.0095, 0.006), (-0.032, 0.009, 0), (0.35, 0.33, 0.32), segs=8, rings=4)
    finish("CigarButt")


# ----------------------------------------------------------------------------- luxury flex items

def build_luxury():
    GREEN_BOX = (0.06, 0.45, 0.22)
    CREAM = (0.93, 0.88, 0.74)
    # ROFLEX presentation box: base (origin bottom center) + lid (origin at the back hinge)
    rbox((0.2, 0.08, 0.2), (0, 0.04, 0), GREEN_BOX, r=0.015, kind="Gloss")
    rbox((0.17, 0.02, 0.17), (0, 0.075, 0), CREAM, r=0.01)
    rbox((0.06, 0.03, 0.09), (0, 0.095, 0.01), CREAM, r=0.012)          # pillow
    finish("WatchBoxBase")
    rbox((0.2, 0.05, 0.2), (0, 0.025, 0.1), GREEN_BOX, r=0.015, kind="Gloss")
    rbox((0.17, 0.004, 0.17), (0, -0.001, 0.1), CREAM)
    ell((0.012, 0.004, 0.009), (0, 0.051, 0.1), GOLD, kind="Metal", segs=10, rings=4)   # crown logo
    finish("WatchBoxLid")
    for name, metal, face in (("WatchGold", GOLD, (0.96, 0.93, 0.8)), ("WatchIced", (0.82, 0.9, 1.0), (0.85, 0.92, 1.0))):
        torus(0.03, 0.009, (0, 0.03, 0), metal, segs=20, rsegs=6, kind="Metal", rot=[("z", math.pi / 2)])
        cyl(0.026, 0.012, (0, 0.062, 0), metal, segs=24, kind="Metal")
        cyl(0.021, 0.004, (0, 0.069, 0), face, segs=24, kind="Gloss")
        rbox((0.002, 0.003, 0.016), (0, 0.072, 0.005), BLACK)
        rbox((0.012, 0.003, 0.002), (0.005, 0.072, 0), BLACK)
        if name == "WatchIced":
            for k in range(12):
                a = k * math.pi / 6
                ell((0.004, 0.004, 0.004), (math.cos(a) * 0.024, 0.07, math.sin(a) * 0.024), (1, 1, 1), kind="Glow", segs=6, rings=3)
        finish(name)
    # LOUIE BATON shopping bag (origin floor), front +z
    rbox((0.34, 0.4, 0.14), (0, 0.2, 0), (0.96, 0.55, 0.12), r=0.01)
    rbox((0.34, 0.03, 0.14), (0, 0.4, 0), (0.9, 0.48, 0.08))
    for z in (-0.03, 0.03):
        rod((-0.07, 0.4, z), (-0.04, 0.5, z), 0.006, (0.4, 0.22, 0.07), segs=5)
        rod((-0.04, 0.5, z), (0.04, 0.5, z), 0.006, (0.4, 0.22, 0.07), segs=5)
        rod((0.04, 0.5, z), (0.07, 0.4, z), 0.006, (0.4, 0.22, 0.07), segs=5)
    finish("LouieBag")
    # Supreme brick (red, origin bottom)
    rbox((0.2, 0.06, 0.09), (0, 0.03, 0), (0.82, 0.08, 0.1), r=0.006)
    rbox((0.13, 0.002, 0.04), (0, 0.061, 0), (0.97, 0.97, 0.97))
    finish("SupremeBrick")
    # desk cash-counting machine: the black MoneyCounter (same geometry + reference points,
    # see build_money_counter; LCD center = REF["CashCounter"]["lcd_center"])
    build_money_counter("CashCounter", MC_BLACK)


def build_desk_upgrades():
    """Office upgrades that sit on / by your desk, and the PvP champion trophy.
    All origin bottom center, front +z (toward the trader)."""
    ORANGE = (1.0, 0.55, 0.08)
    # PvP championship trophy: gold cup with handles on a black plinth + gold plate
    rbox((0.16, 0.06, 0.16), (0, 0.03, 0), BLACK, r=0.008, kind="Gloss")
    rbox((0.12, 0.04, 0.12), (0, 0.08, 0), BLACK, r=0.006, kind="Gloss")
    rbox((0.08, 0.022, 0.004), (0, 0.04, 0.081), GOLD, kind="Metal")
    lathe([(0.0, 0.1), (0.035, 0.1), (0.028, 0.115), (0.012, 0.13), (0.01, 0.17), (0.02, 0.19),
           (0.05, 0.215), (0.07, 0.26), (0.074, 0.3), (0.066, 0.3), (0.0, 0.3)], (0, 0, 0), GOLD, kind="Metal")
    for sx in (-1, 1):
        torus(0.028, 0.007, (sx * 0.076, 0.255, 0), GOLD, segs=16, rsegs=6, kind="Metal",
              rot=[("x", math.pi / 2)], arc=math.pi * 1.2)
    ell((0.02, 0.02, 0.02), (0, 0.31, 0), GOLD, kind="Metal", segs=12, rings=6)
    finish("ChampTrophy")

    # Bloomberg station: its own little side stand next to the desk, two slim
    # monitors on an arm + the yellow/orange keyboard. Origin floor.
    Y = 0.76
    rbox((0.62, 0.035, 0.5), (0, Y - 0.018, 0), (0.2, 0.2, 0.22), r=0.01)
    for sx in (-1, 1):
        for sz in (-1, 1):
            rbox((0.035, Y - 0.035, 0.035), (sx * 0.27, (Y - 0.035) / 2, sz * 0.21), DARK_STEEL, r=0.008, kind="Metal")
    rbox((0.56, 0.02, 0.44), (0, 0.12, 0), DARK_STEEL, r=0.006, kind="Metal")          # lower shelf
    rbox((0.3, 0.05, 0.22), (0.05, 0.155, 0.02), PAPER, r=0.004)                        # printouts on it
    for sx in (-1, 1):
        rbox((0.3, 0.2, 0.022), (sx * 0.16, Y + 0.3, -0.1 + 0.03 * 1), BLACK, r=0.008, kind="Gloss",
             rot=[("y", -sx * 0.2)])
        rbox((0.27, 0.17, 0.004), (sx * 0.16, Y + 0.3, -0.057), (0.08, 0.12, 0.2), kind="Glow",
             rot=[("y", -sx * 0.2)])
        for k in range(5):     # green/orange rows of quotes on the screens
            rbox((0.22, 0.01, 0.002), (sx * 0.16, Y + 0.36 - k * 0.028, -0.054),
                 ORANGE if k % 2 else (0.3, 1.0, 0.45), kind="Glow", rot=[("y", -sx * 0.2)])
    rbox((0.04, 0.2, 0.035), (0, Y + 0.1, -0.13), DARK_STEEL, r=0.01, kind="Metal")
    rbox((0.24, 0.012, 0.12), (0, Y + 0.006, -0.13), DARK_STEEL, r=0.01, kind="Metal")
    rbox((0.42, 0.022, 0.14), (0, Y + 0.011, 0.12), BLACK, r=0.008)
    for row in range(4):
        for col in range(12):
            c = ORANGE if col < 2 else ((1.0, 0.85, 0.15) if col > 9 else (0.2, 0.2, 0.22))
            rbox((0.026, 0.008, 0.022), (-0.18 + col * 0.0327, Y + 0.026, 0.075 + row * 0.028), c)
    finish("BloombergTerminal")

    # police scanner: black radio, antenna, green LCD, orange knob
    rbox((0.2, 0.08, 0.13), (0, 0.04, 0), (0.12, 0.12, 0.13), r=0.012)
    rbox((0.11, 0.03, 0.004), (-0.03, 0.05, 0.066), (0.35, 1.0, 0.45), kind="Glow")
    cyl(0.014, 0.02, (0.065, 0.05, 0.07), ORANGE, segs=12, rot=[("x", math.pi / 2)])
    cyl(0.01, 0.02, (0.065, 0.02, 0.07), (0.5, 0.5, 0.52), segs=10, rot=[("x", math.pi / 2)])
    rod((0.07, 0.08, -0.04), (0.09, 0.32, -0.05), 0.004, BLACK, segs=6)
    ell((0.007, 0.007, 0.007), (0.09, 0.325, -0.05), (0.9, 0.1, 0.1), kind="Glow", segs=8, rings=4)
    for k in range(4):
        rbox((0.004, 0.035, 0.002), (-0.08 + k * 0.012, 0.045, 0.066), (0.3, 0.3, 0.32))
    finish("PoliceScanner")

    # Tony's Rolodex: two end plates, an axle and a fan of cards, on a base
    rbox((0.16, 0.02, 0.1), (0, 0.01, 0), DARK_STEEL, r=0.006, kind="Metal")
    for sx in (-1, 1):
        cyl(0.055, 0.008, (sx * 0.07, 0.07, 0), BLACK, segs=20, rot=[("z", math.pi / 2)])
    cyl(0.006, 0.15, (0, 0.07, 0), STEEL, segs=8, rot=[("z", math.pi / 2)], kind="Metal")
    for k in range(9):
        a = -0.9 + k * 0.22
        rbox((0.12, 0.004, 0.07), (0, 0.07 + math.sin(a) * 0.04, math.cos(a) * 0.04), PAPER, rot=[("x", a + math.pi / 2)])
    finish("Rolodex")

    # anti-fatigue standing mat (floor, in front of the desk)
    rbox((0.9, 0.018, 0.55), (0, 0.009, 0), (0.12, 0.12, 0.13), r=0.03, seg=3)
    for k in range(6):
        rbox((0.8, 0.004, 0.02), (0, 0.019, -0.2 + k * 0.08), (0.18, 0.18, 0.19))
    ell((0.035, 0.035, 0.035), (0.34, 0.04, 0.18), (0.95, 0.2, 0.2), segs=12, rings=8)   # stress ball
    finish("StandingMat")

    # prime broker card on a little acrylic stand
    rbox((0.1, 0.012, 0.05), (0, 0.006, 0), (0.85, 0.9, 0.95), r=0.004, kind="Gloss")
    rbox((0.086, 0.054, 0.003), (0, 0.04, 0), (0.06, 0.06, 0.07), r=0.004, kind="Metal", rot=[("x", -0.25)])
    rbox((0.014, 0.011, 0.002), (-0.025, 0.045, 0.004), GOLD, kind="Metal", rot=[("x", -0.25)])
    rbox((0.05, 0.004, 0.002), (0.005, 0.028, 0.006), (0.75, 0.75, 0.78), kind="Metal", rot=[("x", -0.25)])
    finish("PrimeCard")


def build_flex_counter():
    """FLEX SHOP display counter, 2.2 x 1.0, front +z (customer side): the merch
    sits out on green felt; gold trim and a lit kick strip."""
    rbox((2.2, 0.86, 0.7), (0, 0.43, 0), (0.12, 0.12, 0.14), r=0.02, kind="Gloss")
    rbox((2.24, 0.04, 0.74), (0, 0.88, 0), GOLD, r=0.012, kind="Metal")
    rbox((2.14, 0.012, 0.66), (0, 0.905, 0), (0.1, 0.38, 0.22))                        # green felt
    for x in (-0.7, 0.0, 0.7):                                                         # gold front panels
        rbox((0.6, 0.5, 0.012), (x, 0.45, 0.352), (0.2, 0.2, 0.23), r=0.01)
        rbox((0.56, 0.02, 0.014), (x, 0.66, 0.356), GOLD, kind="Metal")
    for k in range(3):                                                                  # watch stands
        x = -0.85 + k * 0.2
        rbox((0.08, 0.06, 0.08), (x, 0.94, 0.05), (0.93, 0.88, 0.74), r=0.01)
        torus(0.028, 0.008, (x, 1.0, 0.05), GOLD if k != 1 else (0.82, 0.9, 1.0), segs=16, rsegs=5,
              kind="Metal", rot=[("z", math.pi / 2)])
        cyl(0.024, 0.01, (x, 1.03, 0.05), GOLD if k != 1 else (0.82, 0.9, 1.0), segs=16, kind="Metal")
    rbox((0.3, 0.36, 0.13), (0.35, 1.09, -0.05), (0.96, 0.55, 0.12), r=0.01)           # LOUIE bag
    for z in (-0.02, 0.02):
        rod((0.29, 1.27, z - 0.05), (0.41, 1.27, z - 0.05), 0.006, (0.4, 0.22, 0.07), segs=5)
    for k in range(3):                                                                  # brick pyramid
        rbox((0.2, 0.06, 0.09), (0.8 + (k % 2) * 0.1 - 0.05, 0.94 + (k // 2) * 0.061, 0.08), (0.82, 0.08, 0.1), r=0.006)
    rbox((0.2, 0.2, 0.2), (-0.3, 1.0, 0.0), (0.06, 0.45, 0.22), r=0.015, kind="Gloss")  # ROFLEX box
    rbox((2.2, 0.04, 0.04), (0, 0.06, 0.34), (0.95, 0.85, 0.3), kind="Glow")            # LED kick strip
    finish("FlexCounter")


# ----------------------------------------------------------------------------- street (outside)

def storefront(name, wall, trim, sign_bg, style=""):
    """Ground-floor shop facade, 10 m wide x 4.4 m tall, front face at z=0.4
    (origin at the back-bottom-center). Door opening 2.2 x 2.8 in the middle;
    display windows either side; a sign band (Godot writes the brand on it)."""
    D = 0.4
    for x0, x1 in ((-5.0, -1.1), (1.1, 5.0)):
        cx, w = (x0 + x1) / 2, x1 - x0
        rbox((w, 4.4, D), (cx, 2.2, D / 2), wall)
        # display window: dark glass set into the pillar + a trim frame
        rbox((w - 1.0, 2.0, 0.06), (cx, 1.65, D + 0.01), (0.55, 0.7, 0.82), kind="Gloss")
        for sx, sy, px, py in ((w - 0.84, 0.08, cx, 2.69), (w - 0.84, 0.1, cx, 0.6), (0.08, 2.14, cx - (w - 0.92) / 2, 1.65),
                               (0.08, 2.14, cx + (w - 0.92) / 2, 1.65)):
            rbox((sx, sy, 0.1), (px, py, D + 0.03), trim, kind="Metal")
    rbox((2.2, 1.6, D), (0, 3.6, D / 2), wall)                                  # lintel over the door
    for x in (-1.12, 1.12):
        rbox((0.12, 2.9, 0.12), (x, 1.45, D + 0.04), trim, kind="Metal")         # door frame
    rbox((2.36, 0.12, 0.12), (0, 2.86, D + 0.04), trim, kind="Metal")
    rbox((9.6, 0.9, 0.12), (0, 3.62, D + 0.07), sign_bg, r=0.02)                 # sign band
    rbox((10.0, 0.14, 0.3), (0, 4.36, D + 0.1), trim, kind="Metal")              # cornice
    rbox((10.0, 0.25, 0.1), (0, 0.12, D + 0.05), [c * 0.7 for c in wall])        # base plinth
    if style == "stripes":          # GUCCERO: green-red-green web stripe under the sign
        for i, c in enumerate(((0.05, 0.4, 0.2), (0.75, 0.08, 0.1), (0.05, 0.4, 0.2))):
            rbox((9.6, 0.07, 0.04), (0, 3.08 - i * 0.07, D + 0.14), c)
    if style == "marble":           # black marble veins
        for k in range(14):
            x = random.uniform(-4.8, 4.8)
            if abs(x) < 1.3:
                continue
            rbox((0.02, random.uniform(0.6, 1.8), 0.01), (x, random.uniform(0.6, 3.0), D + 0.005), (0.35, 0.35, 0.38),
                 rot=[("z", random.uniform(-0.6, 0.6))])
    if style == "quilted":          # CHAVÉL quilted diamonds
        for x0 in (-4.9, 1.2):
            for i in range(13):
                for j in range(9):
                    x = x0 + 0.15 + i * 0.28
                    y = 0.3 + j * 0.46
                    if 0.55 < y < 2.75 and abs(x - (x0 + 1.95)) < 1.4:
                        continue
                    rbox((0.16, 0.16, 0.02), (x, y, D + 0.01), [min(1.0, c * 1.15) for c in wall], rot=[("z", math.pi / 4)])
    if style == "awning":           # deli: striped awning over the windows
        for side in (-1, 1):
            for k in range(8):
                rbox((0.44, 0.04, 1.1), (side * 3.05 + (k - 3.5) * 0.46, 2.95, D + 0.5),
                     (0.1, 0.45, 0.2) if k % 2 == 0 else (0.95, 0.95, 0.9), rot=[("x", 0.35)])
    if style == "cream_awning":     # tailor / dior: plain scalloped awning
        for side in (-1, 1):
            rbox((3.6, 0.05, 1.0), (side * 3.05, 2.95, D + 0.45), (0.94, 0.9, 0.8), rot=[("x", 0.35)])
    if style in ("bars", "iron"):   # pawn / gun store: security bars on the windows
        for side in (-1, 1):
            for k in range(9):
                cyl(0.02, 2.0, (side * 3.05 + (k - 4) * 0.36, 1.65, D + 0.12), (0.2, 0.2, 0.22), segs=6, kind="Metal")
    if style == "iron":             # gun store: roll-up shutter boxes, riveted plates, hazard-striped plinth
        for x0, x1 in ((-5.0, -1.1), (1.1, 5.0)):
            cx, w = (x0 + x1) / 2, x1 - x0
            rbox((w - 0.7, 0.34, 0.26), (cx, 2.93, D + 0.13), (0.2, 0.21, 0.23), r=0.03, kind="Metal")
            for k in range(3):
                rbox((w - 0.8, 0.014, 0.012), (cx, 2.84 + k * 0.09, D + 0.265), (0.12, 0.12, 0.13), kind="Metal")
            for sx in (-1, 1):          # riveted steel plate on each pillar side of the window
                px = cx + sx * (w / 2 - 0.25)
                rbox((0.34, 2.3, 0.03), (px, 1.55, D + 0.015), (0.16, 0.17, 0.18), r=0.01, kind="Metal")
                for j in range(6):
                    ell((0.018, 0.018, 0.012), (px, 0.55 + j * 0.4, D + 0.03), (0.3, 0.31, 0.33), segs=8, rings=4, kind="Metal")
            rbox((w - 0.1, 0.18, 0.02), (cx, 0.13, D + 0.105), (0.05, 0.05, 0.055))
            x = x0 + 0.1
            while x + 0.3 < x1 - 0.05:
                prism([(x, 0.04), (x + 0.12, 0.04), (x + 0.26, 0.22), (x + 0.14, 0.22)], "z", D + 0.115, D + 0.12,
                      (0.98, 0.62, 0.08))
                x += 0.26
        rbox((2.3, 0.08, 0.14), (0, 3.02, D + 0.12), trim, kind="Metal")       # heavy door header
    if style == "bulbs":            # casino: marquee bulbs around the sign
        for k in range(24):
            ell((0.05, 0.05, 0.05), (-4.7 + k * 0.41, 4.14, D + 0.16), (1.0, 0.95, 0.7), kind="Glow", segs=8, rings=4)
            ell((0.05, 0.05, 0.05), (-4.7 + k * 0.41, 3.1, D + 0.16), (1.0, 0.95, 0.7), kind="Glow", segs=8, rings=4)
    if style == "monogram":         # LOUIS VALMONT: little VM-ish diamonds on the leather
        for i in range(20):
            for j in range(9):
                x = -4.8 + i * 0.5
                y = 0.35 + j * 0.46
                if abs(x) < 1.3 or (0.5 < y < 2.8 and 1.3 < abs(x) < 4.6):
                    continue
                rbox((0.1, 0.1, 0.01), (x, y, D + 0.005), (0.85, 0.7, 0.4), rot=[("z", math.pi / 4)])
    finish(name)


def build_street_props():
    # storefronts in the owner's parody brand styles (docs/BRANDS.md)
    storefront("Store_Guccero", (0.1, 0.1, 0.11), GOLD, (0.05, 0.05, 0.06), "stripes")
    storefront("Store_Guccero2", (0.1, 0.1, 0.11), GOLD, (0.05, 0.05, 0.06), "marble")
    storefront("Store_Valmont", (0.45, 0.3, 0.17), GOLD, (0.3, 0.18, 0.09), "monogram")
    storefront("Store_Prava", (0.07, 0.07, 0.08), (0.8, 0.82, 0.86), (0.04, 0.04, 0.05))
    storefront("Store_Diorelle", (0.94, 0.91, 0.84), GOLD, (0.97, 0.95, 0.9), "cream_awning")
    storefront("Store_Chavel", (0.1, 0.1, 0.1), GOLD, (0.97, 0.97, 0.97), "quilted")
    storefront("Store_Crownwell", (0.05, 0.28, 0.16), GOLD, (0.03, 0.18, 0.1))
    storefront("Store_Deli", (0.55, 0.22, 0.16), (0.2, 0.2, 0.2), (0.08, 0.3, 0.14), "awning")
    storefront("Store_Tailor", (0.12, 0.16, 0.3), GOLD, (0.08, 0.1, 0.2), "cream_awning")
    storefront("Store_Pawn", (0.5, 0.5, 0.52), (0.25, 0.25, 0.27), (0.95, 0.78, 0.1), "bars")
    storefront("Store_Casino", (0.25, 0.08, 0.35), GOLD, (0.12, 0.03, 0.18), "bulbs")
    storefront("Store_Lobby", (0.6, 0.62, 0.66), (0.8, 0.82, 0.86), (0.15, 0.17, 0.2))
    storefront("Store_Empty", (0.62, 0.58, 0.52), (0.4, 0.4, 0.42), (0.9, 0.9, 0.9))

    # upper floors: 10 m wide, 3 floors (9 m), windows + cornice. origin back-bottom-center
    for name, wall, win in (("Upper_Brick", (0.55, 0.28, 0.2), (0.6, 0.72, 0.85)),
                            ("Upper_Stone", (0.78, 0.74, 0.66), (0.55, 0.68, 0.82)),
                            ("Upper_Dark", (0.22, 0.24, 0.28), (0.5, 0.65, 0.8)),
                            ("Upper_Glass", (0.45, 0.55, 0.65), (0.62, 0.78, 0.92))):
        rbox((10.0, 9.0, 0.4), (0, 4.5, 0.2), wall)
        for f in range(3):
            for k in range(4):
                x = -3.75 + k * 2.5
                y = 1.1 + f * 3.0
                rbox((1.4, 1.8, 0.05), (x, y + 0.9, 0.42), win, kind="Gloss")
                rbox((1.6, 0.12, 0.14), (x, y - 0.05, 0.45), [c * 0.8 for c in wall])     # sill
        rbox((10.2, 0.3, 0.5), (0, 8.9, 0.25), [c * 0.7 for c in wall])                    # cornice
        finish(name)

    # road furniture
    cyl(0.07, 5.0, (0, 2.5, 0), (0.18, 0.2, 0.22), segs=10, kind="Metal")
    rod((0, 4.9, 0), (0, 5.1, 0.9), 0.05, (0.18, 0.2, 0.22), kind="Metal")
    rbox((0.35, 0.12, 0.5), (0, 5.05, 1.0), (0.18, 0.2, 0.22), r=0.03, kind="Metal")
    rbox((0.3, 0.04, 0.42), (0, 4.98, 1.0), (1.0, 0.95, 0.8), kind="Glow")
    cyl(0.14, 0.3, (0, 0.15, 0), (0.18, 0.2, 0.22), segs=12, kind="Metal")
    finish("StreetLamp")
    lathe([(0.0, 0.0), (0.12, 0.0), (0.12, 0.08), (0.09, 0.1), (0.09, 0.5), (0.1, 0.55), (0.06, 0.62), (0.0, 0.64)],
          (0, 0, 0), (0.85, 0.12, 0.1), kind="Gloss", segs=16)
    for sx in (-1, 1):
        cyl(0.045, 0.08, (sx * 0.1, 0.4, 0), (0.85, 0.12, 0.1), segs=10, rot=[("z", math.pi / 2)], kind="Gloss")
    finish("Hydrant")
    for x in (-0.8, 0.8):
        rbox((0.08, 0.45, 0.5), (x, 0.225, 0), (0.15, 0.15, 0.17), kind="Metal")
    for k in range(4):
        rbox((1.8, 0.04, 0.1), (0, 0.45, -0.18 + k * 0.12), WOOD, r=0.01)
    for k in range(3):
        rbox((1.8, 0.1, 0.04), (0, 0.6 + k * 0.13, -0.26), WOOD, r=0.01, rot=[("x", -0.2)])
    finish("Bench")
    rbox((1.2, 0.5, 1.2), (0, 0.25, 0), (0.55, 0.53, 0.5), r=0.03)
    rbox((1.1, 0.05, 1.1), (0, 0.5, 0), (0.25, 0.17, 0.1))
    cyl(0.08, 2.2, (0, 1.6, 0), (0.35, 0.24, 0.14), segs=10)
    for k in range(9):
        a = k * 2.39
        ell((0.75, 0.6, 0.75), (math.cos(a) * 0.4, 2.8 + (k % 3) * 0.35, math.sin(a) * 0.4),
            (0.2 + random.uniform(0, 0.08), 0.45 + random.uniform(0, 0.12), 0.18), segs=12, rings=8)
    finish("Tree")
    cyl(0.07, 3.2, (0, 1.6, 0), (0.2, 0.2, 0.22), segs=10, kind="Metal")
    rbox((0.36, 1.0, 0.3), (0, 3.4, 0.05), (0.12, 0.12, 0.13), r=0.04)
    for k, c in enumerate(((0.9, 0.1, 0.1), (1.0, 0.75, 0.1), (0.1, 0.9, 0.3))):
        cyl(0.1, 0.03, (0, 3.72 - k * 0.3, 0.21), c, rot=[("x", math.pi / 2)], kind="Glow" if k == 2 else "Gloss", segs=14)
    finish("TrafficLight")

    # cars (Blender body, Godot writes the parody badge): origin floor center, nose +z
    def car(name, body, sporty=False, taxi=False):
        L, Wd = (4.3, 1.95) if sporty else (4.6, 1.85)
        h = 0.7 if sporty else 0.85
        rbox((Wd, h, L), (0, 0.25 + h / 2, 0), body, r=0.18, seg=3, kind="Gloss")
        cab_h, cab_l = (0.42, 1.7) if sporty else (0.6, 2.3)
        rbox((Wd - 0.25, cab_h, cab_l), (0, 0.25 + h + cab_h / 2 - 0.04, -0.2 if sporty else -0.1),
             (0.12, 0.16, 0.2), r=0.15, seg=3, kind="Gloss")
        for x in (-Wd / 2 + 0.02, Wd / 2 - 0.02):
            for z in (-L / 2 + 0.8, L / 2 - 0.8):
                cyl(0.36 if not sporty else 0.38, 0.28, (x, 0.36, z), (0.06, 0.06, 0.07), segs=18, rot=[("z", math.pi / 2)])
                cyl(0.22, 0.3, (x, 0.36, z), (0.75, 0.76, 0.8), segs=12, rot=[("z", math.pi / 2)], kind="Metal")
        for x in (-Wd / 2 + 0.3, Wd / 2 - 0.3):
            rbox((0.4, 0.12, 0.05), (x, 0.25 + h * 0.7, L / 2 + 0.01), (1.0, 1.0, 0.9), kind="Glow")
            rbox((0.4, 0.1, 0.05), (x, 0.25 + h * 0.7, -L / 2 - 0.01), (0.9, 0.1, 0.1), kind="Glow")
        if taxi:
            rbox((0.7, 0.18, 0.3), (0, 0.25 + h + cab_h + 0.06, -0.1), (1.0, 0.95, 0.6), r=0.04, kind="Glow")
            for side in (-1, 1):
                for k in range(8):
                    rbox((0.02, 0.1, 0.18), (side * (Wd / 2 + 0.005), 0.25 + h * 0.45, -1.2 + k * 0.36),
                         (0.08, 0.08, 0.08) if k % 2 == 0 else body)
        finish(name)
    car("Car_Torola", (0.72, 0.74, 0.78))
    car("Car_Bemze", (0.1, 0.18, 0.42))
    car("Car_Mercedez", (0.08, 0.08, 0.09))
    car("Car_Bentlee", (0.2, 0.3, 0.22))
    car("Car_Lambargamber", (1.0, 0.72, 0.05), sporty=True)
    car("Car_Ferrazi", (0.85, 0.05, 0.05), sporty=True)
    car("Car_Porsha", (0.95, 0.95, 0.95), sporty=True)
    car("Car_Taxi", (1.0, 0.8, 0.05), taxi=True)

    # hot dog cart with an umbrella (front +z)
    rbox((1.6, 0.9, 0.8), (0, 0.75, 0), (0.85, 0.85, 0.88), r=0.04, kind="Metal")
    rbox((1.62, 0.1, 0.82), (0, 1.25, 0), (0.95, 0.95, 0.97), r=0.02, kind="Metal")
    for x in (-0.65, 0.65):
        cyl(0.28, 0.08, (x, 0.28, 0.42), (0.1, 0.1, 0.11), segs=16, rot=[("x", math.pi / 2)])
    rbox((1.4, 0.4, 0.02), (0, 0.8, 0.41), (0.95, 0.75, 0.1))
    cyl(0.025, 1.4, (0.5, 1.95, -0.2), (0.7, 0.7, 0.72), segs=8, kind="Metal")
    for k in range(8):
        a0 = k * math.pi / 4
        lathe([(0.0, 2.9), (1.1, 2.55)], (0.5, 0, -0.2), (0.9, 0.12, 0.1) if k % 2 == 0 else (0.97, 0.9, 0.2), segs=8, smooth=False) if k == 0 else None
    for k in range(3):
        rod((-0.45 + k * 0.2, 1.33, 0.1), (-0.3 + k * 0.2, 1.33, 0.1), 0.03, (0.8, 0.45, 0.25), segs=8)
    finish("HotDogCart")

    # shop fittings
    for x in (-0.9, 0.9):
        cyl(0.02, 1.6, (x, 0.8, 0), (0.75, 0.76, 0.8), segs=8, kind="Metal")
    rod((-0.9, 1.6, 0), (0.9, 1.6, 0), 0.02, (0.75, 0.76, 0.8), kind="Metal")
    rbox((1.9, 0.04, 0.5), (0, 0.02, 0), (0.75, 0.76, 0.8), kind="Metal")
    cols = [(0.1, 0.1, 0.12), (0.9, 0.88, 0.8), (0.4, 0.1, 0.12), (0.12, 0.2, 0.4), (0.35, 0.36, 0.4), (0.55, 0.4, 0.25)]
    for k in range(8):
        x = -0.75 + k * 0.21
        rbox((0.08, 0.9, 0.5), (x, 1.12, 0), cols[k % len(cols)], r=0.03)
        rod((x, 1.6, 0), (x, 1.57, 0), 0.01, (0.75, 0.76, 0.8), segs=5, kind="Metal")
    finish("ClothesRack")
    rbox((2.0, 2.2, 0.45), (0, 1.1, 0), (0.93, 0.92, 0.9), r=0.02)
    for k in range(4):
        rbox((1.9, 0.04, 0.4), (0, 0.4 + k * 0.5, 0.03), (0.8, 0.8, 0.82), kind="Metal")
        for j in range(5):
            if random.random() < 0.8:
                rbox((0.22, 0.25, 0.22), (-0.75 + j * 0.37, 0.55 + k * 0.5, 0.05),
                     random.choice([(0.9, 0.2, 0.2), (0.2, 0.5, 0.9), (0.95, 0.8, 0.2), (0.3, 0.7, 0.3), (0.95, 0.95, 0.95)]), r=0.02)
    finish("ShopShelf")
    rbox((2.4, 1.0, 0.6), (0, 0.5, 0), (0.25, 0.18, 0.12), r=0.02)
    rbox((2.44, 0.05, 0.64), (0, 1.02, 0), (0.85, 0.85, 0.86), kind="Gloss")
    rbox((0.3, 0.3, 0.3), (0.8, 1.2, 0), (0.15, 0.15, 0.17), r=0.03)                  # register
    rbox((0.24, 0.1, 0.02), (0.8, 1.3, 0.16), (0.3, 1.0, 0.4), kind="Glow")
    finish("ShopCounter")

    # handbag variants for the new boutiques (origin floor, front +z)
    for name, body, trim in (("Bag_Guccero", (0.1, 0.1, 0.11), (0.1, 0.45, 0.2)),
                             ("Bag_Prava", (0.08, 0.08, 0.09), (0.8, 0.82, 0.86)),
                             ("Bag_Diorelle", (0.92, 0.88, 0.8), GOLD),
                             ("Bag_Chavel", (0.07, 0.07, 0.08), GOLD)):
        rbox((0.3, 0.2, 0.1), (0, 0.1, 0), body, r=0.03, seg=3)
        rbox((0.3, 0.04, 0.102), (0, 0.16, 0), trim)
        rbox((0.06, 0.04, 0.02), (0, 0.13, 0.055), GOLD, kind="Metal")
        torus(0.1, 0.008, (0, 0.2, 0), trim, segs=16, rsegs=5, rot=[("x", math.pi / 2)], arc=math.pi, kind="Metal")
        finish(name)


# ----------------------------------------------------------------------------- main

def _open_shelf(w, h, d, frame, n, back=None):
    """Open shelving carcass: back panel, sides, top/bottom and n shelf boards.
    Returns the shelf-board top heights (origin floor, front +z)."""
    back = back or frame
    rbox((w, h, 0.03), (0, h / 2, -d / 2 + 0.015), back)
    for sx in (-1, 1):
        rbox((0.04, h, d), (sx * (w / 2 - 0.02), h / 2, 0), frame, r=0.01)
    rbox((w, 0.05, d), (0, h - 0.025, 0), frame, r=0.01)
    rbox((w, 0.1, d), (0, 0.05, 0), frame, r=0.01)
    tops = []
    for k in range(n):
        y = 0.1 + (h - 0.2) * k / n
        rbox((w - 0.08, 0.03, d - 0.03), (0, y + 0.015, 0.0), frame)
        tops.append(y + 0.03)
    return tops


def _folded(x, y, z, col, n=4, w=0.3, d=0.26):
    """A stack of folded shirts/sweaters."""
    for i in range(n):
        c = [min(1.0, v * (0.92 + 0.08 * (i % 2))) for v in col]
        rbox((w, 0.045, d), (x + random.uniform(-0.01, 0.01), y + 0.0225 + i * 0.048, z), c, r=0.015)


def _shoe(x, y, z, col, sole=(0.95, 0.95, 0.95), rot=0.0):
    rbox((0.1, 0.06, 0.27), (x, y + 0.035, z), sole, r=0.02, rot=[("y", rot)])
    rbox((0.095, 0.08, 0.2), (x, y + 0.1, z - 0.03), col, r=0.035, rot=[("y", rot)])
    ell((0.047, 0.04, 0.06), (x, y + 0.075, z + 0.085), col)


def build_store_props():
    """Store fittings: boutique displays, a stocked deli, the pawn shop's junk."""
    random.seed(23)
    LAC = (0.12, 0.11, 0.1)          # dark lacquer
    OAK = (0.62, 0.47, 0.3)
    CREAM = (0.93, 0.9, 0.84)
    tones = [(0.08, 0.08, 0.09), (0.93, 0.92, 0.88), (0.55, 0.12, 0.14), (0.12, 0.2, 0.42), (0.42, 0.43, 0.46),
             (0.62, 0.48, 0.3), (0.16, 0.34, 0.2), (0.85, 0.72, 0.5)]

    # --- boutique: wall of cubbies with folded clothes, shoes and bags on top
    w, h, d = 2.8, 2.6, 0.45
    rbox((w, h, 0.03), (0, h / 2, -d / 2 + 0.015), LAC)
    for c in range(5):
        rbox((0.035, h - 0.1, d), (-w / 2 + c * w / 4, h / 2 + 0.05, 0), CREAM)
    for r in range(5):
        rbox((w, 0.035, d), (0, 0.1 + r * 0.6, 0), CREAM)
    rbox((w, 0.1, d), (0, 0.05, 0), LAC)
    for c in range(4):
        cx = -w / 2 + (c + 0.5) * w / 4
        for r in range(3):
            _folded(cx, 0.12 + r * 0.6, 0.02, tones[(c * 3 + r) % len(tones)], n=random.randint(3, 6), w=0.4)
        _shoe(cx - 0.12, 1.92, 0.03, tones[(c + 2) % len(tones)], rot=0.2)
        _shoe(cx + 0.12, 1.92, 0.03, tones[(c + 2) % len(tones)], rot=-0.2)
    for c in range(4):   # lit strip under the top board
        rbox((0.6, 0.02, 0.03), (-w / 2 + (c + 0.5) * w / 4, 2.48, 0.19), (1.0, 0.95, 0.85), kind="Glow")
    finish("ClothesCubbies")

    # --- boutique: low display table with folded stacks and a card
    rbox((1.8, 0.08, 0.9), (0, 0.72, 0), LAC, r=0.02)
    for x in (-0.78, 0.78):
        for z in (-0.36, 0.36):
            rbox((0.08, 0.7, 0.08), (x, 0.35, z), LAC, r=0.01)
    rbox((1.6, 0.03, 0.7), (0, 0.25, 0), LAC)
    for i, x in enumerate((-0.55, -0.1, 0.35)):
        _folded(x, 0.76, -0.15, tones[i + 1], n=4, w=0.34)
        _folded(x + 0.1, 0.76, 0.2, tones[i + 4], n=3, w=0.34)
    rbox((0.16, 0.1, 0.01), (0.7, 0.81, 0.3), CREAM, rot=[("x", -0.3)])
    _folded(-0.4, 0.28, 0.0, tones[0], n=3, w=0.34)
    _folded(0.3, 0.28, 0.0, tones[3], n=3, w=0.34)
    finish("DisplayTable")

    # --- boutique: plinth for a bag (the bag prop goes on top at y=1.0)
    cyl(0.28, 0.06, (0, 0.03, 0), LAC, segs=32)
    cyl(0.22, 0.9, (0, 0.5, 0), CREAM, segs=32)
    cyl(0.26, 0.05, (0, 0.975, 0), GOLD, segs=32, kind="Metal")
    finish("BagPlinth")

    # --- boutique: shoe wall (floating shelves)
    rbox((2.0, 2.4, 0.04), (0, 1.2, -0.1), (0.2, 0.19, 0.18))
    for r in range(5):
        y = 0.35 + r * 0.42
        rbox((1.9, 0.03, 0.3), (0, y, 0.05), (0.85, 0.85, 0.86), kind="Gloss")
        rbox((1.9, 0.015, 0.02), (0, y - 0.02, 0.19), (1.0, 0.95, 0.85), kind="Glow")
        for k in range(3):
            col = tones[(r * 3 + k) % len(tones)]
            _shoe(-0.6 + k * 0.6 - 0.06, y + 0.015, 0.05, col, rot=0.35)
            _shoe(-0.6 + k * 0.6 + 0.08, y + 0.015, 0.05, col, rot=0.35)
    finish("ShoeWall")

    # --- ottoman, full-length mirror, spotlight track, round rug
    cyl(0.42, 0.42, (0, 0.21, 0), (0.55, 0.12, 0.14), segs=32)
    cyl(0.4, 0.06, (0, 0.44, 0), (0.6, 0.14, 0.16), segs=32)
    for k in range(8):
        a = k * math.pi / 4
        ell((0.02, 0.02, 0.02), (math.cos(a) * 0.2, 0.47, math.sin(a) * 0.2), GOLD, segs=8, rings=6, kind="Metal")
    finish("Ottoman")
    rbox((0.72, 1.9, 0.06), (0, 1.0, 0), GOLD, r=0.02, kind="Metal")
    rbox((0.62, 1.8, 0.02), (0, 1.0, 0.025), (0.78, 0.84, 0.9), kind="Gloss")
    rbox((0.5, 0.05, 0.4), (0, 0.025, -0.1), LAC)
    rod((0, 0.4, -0.02), (0, 0.05, -0.28), 0.02, LAC)
    finish("FullMirror")
    rbox((3.0, 0.05, 0.06), (0, -0.03, 0), (0.1, 0.1, 0.1), kind="Metal")
    for k in range(5):
        x = -1.2 + k * 0.6
        rod((x, -0.05, 0), (x, -0.13, 0), 0.01, (0.1, 0.1, 0.1), segs=6, kind="Metal")
        cyl(0.05, 0.14, (x, -0.2, 0.02), (0.1, 0.1, 0.1), segs=14, kind="Metal", rot=[("x", 0.35)])
        cyl(0.04, 0.01, (x, -0.26, 0.045), (1.0, 0.95, 0.8), segs=14, kind="Glow", rot=[("x", 0.35)])
    finish("SpotTrack")      # origin = ceiling mount
    cyl(1.6, 0.012, (0, 0.006, 0), (0.85, 0.8, 0.72), segs=40)
    torus(1.5, 0.02, (0, 0.012, 0), (0.7, 0.62, 0.45), segs=40, rsegs=4)
    finish("RugRound")

    # --- deli: stocked shelving
    tops = _open_shelf(2.0, 1.9, 0.45, (0.85, 0.85, 0.86), 4, back=(0.72, 0.74, 0.76))
    goods = [(0.85, 0.15, 0.12), (0.95, 0.75, 0.15), (0.2, 0.45, 0.85), (0.25, 0.65, 0.3), (0.95, 0.5, 0.15), (0.6, 0.2, 0.55)]
    for r, y in enumerate(tops):
        x = -0.88
        while x < 0.85:
            kind = (r + int((x + 1) * 3)) % 4
            col = random.choice(goods)
            if kind == 0:      # cans
                for zz in (-0.1, 0.06):
                    cyl(0.04, 0.12, (x, y + 0.06, zz), col, segs=12)
                    cyl(0.041, 0.02, (x, y + 0.1, zz), (0.85, 0.85, 0.86), segs=12, kind="Metal")
                x += 0.1
            elif kind == 1:    # cereal box
                rbox((0.18, 0.3, 0.07), (x + 0.05, y + 0.15, 0.05), col, r=0.005)
                rbox((0.12, 0.08, 0.002), (x + 0.05, y + 0.2, 0.086), (0.97, 0.95, 0.9))
                x += 0.21
            elif kind == 2:    # bottles
                cyl(0.04, 0.2, (x, y + 0.1, 0.02), col, segs=12, kind="Gloss")
                cyl(0.018, 0.07, (x, y + 0.235, 0.02), col, segs=10, kind="Gloss")
                cyl(0.02, 0.02, (x, y + 0.28, 0.02), (0.95, 0.95, 0.95), segs=10)
                x += 0.1
            else:              # chip bag
                ell((0.09, 0.13, 0.04), (x + 0.03, y + 0.13, 0.05), col, segs=12, rings=8)
                x += 0.19
    finish("DeliShelf")
    rbox((1.2, 2.0, 0.7), (0, 1.0, 0), (0.9, 0.9, 0.92), r=0.02)
    rbox((1.1, 1.75, 0.02), (0, 1.05, 0.35), (0.7, 0.85, 0.95), kind="Gloss")
    rbox((1.12, 0.2, 0.03), (0, 1.9, 0.35), (0.1, 0.35, 0.8))
    for r in range(4):
        y = 0.35 + r * 0.42
        rbox((1.06, 0.02, 0.6), (0, y, 0), (0.95, 0.95, 0.97), kind="Glow")
        for k in range(7):
            cyl(0.035, 0.2, (-0.45 + k * 0.15, y + 0.11, 0.1), goods[(r + k) % len(goods)], segs=10, kind="Gloss")
    rbox((0.04, 0.5, 0.04), (0.48, 1.05, 0.38), (0.8, 0.8, 0.82), kind="Metal")
    finish("DeliFridge")

    # --- pawn shop: shelving full of other people's bad decisions
    tops = _open_shelf(2.2, 2.0, 0.5, (0.35, 0.28, 0.2), 4, back=(0.3, 0.3, 0.32))
    for r, y in enumerate(tops):
        if r == 0:     # old TVs
            for k in range(3):
                x = -0.65 + k * 0.65
                rbox((0.5, 0.38, 0.38), (x, y + 0.19, 0), (0.2, 0.2, 0.22), r=0.03)
                rbox((0.38, 0.28, 0.01), (x - 0.03, y + 0.2, 0.19), (0.25, 0.32, 0.35), kind="Gloss")
        elif r == 1:   # boomboxes + a camera
            for k in range(2):
                x = -0.55 + k * 0.7
                rbox((0.55, 0.26, 0.16), (x, y + 0.13, 0), (0.15, 0.15, 0.16), r=0.02)
                for sx in (-1, 1):
                    cyl(0.08, 0.02, (x + sx * 0.16, y + 0.12, 0.08), (0.3, 0.3, 0.32), segs=16, rot=[("x", math.pi / 2)], kind="Metal")
                rod((x - 0.2, y + 0.26, 0), (x + 0.2, y + 0.26, 0), 0.012, (0.6, 0.6, 0.62), kind="Metal")
            rbox((0.16, 0.1, 0.08), (0.8, y + 0.05, 0), (0.1, 0.1, 0.1), r=0.01)
            cyl(0.035, 0.06, (0.8, y + 0.05, 0.07), (0.2, 0.2, 0.22), segs=12, rot=[("x", math.pi / 2)], kind="Gloss")
        elif r == 2:   # gold: chains on a bust, trophies, a "diamond" ring box
            ell((0.1, 0.16, 0.08), (-0.7, y + 0.16, 0), (0.1, 0.1, 0.1))
            for k in range(3):
                torus(0.09 - k * 0.01, 0.008, (-0.7, y + 0.2 - k * 0.04, 0.02), GOLD, segs=20, rsegs=5,
                      rot=[("x", 1.2)], kind="Metal")
            for k in range(2):
                x = -0.1 + k * 0.35
                cyl(0.06, 0.04, (x, y + 0.02, 0), (0.15, 0.1, 0.05), segs=12)
                cyl(0.015, 0.12, (x, y + 0.1, 0), GOLD, segs=8, kind="Metal")
                lathe([(0.0, 0.0), (0.07, 0.02), (0.08, 0.12), (0.0, 0.12)], (x, y + 0.16, 0), GOLD, segs=16, kind="Metal")
            rbox((0.1, 0.08, 0.1), (0.75, y + 0.04, 0), (0.1, 0.1, 0.35), r=0.015)
            ell((0.025, 0.025, 0.025), (0.75, y + 0.1, 0.01), (0.9, 0.95, 1.0), segs=8, rings=6, kind="Gloss")
        else:          # boxed sneakers + a stack of DVDs
            for k in range(3):
                rbox((0.34, 0.14, 0.24), (-0.7 + k * 0.38, y + 0.07, 0), [(0.9, 0.4, 0.1), (0.15, 0.15, 0.15), (0.85, 0.85, 0.85)][k], r=0.01)
            for k in range(8):
                rbox((0.14, 0.02, 0.2), (0.62, y + 0.01 + k * 0.022, 0), random.choice(goods), r=0.002)
    finish("PawnShelf")
    rbox((2.0, 2.2, 0.03), (0, 1.2, -0.02), (0.3, 0.3, 0.32))
    for k in range(4):
        x = -0.72 + k * 0.48
        col = [(0.75, 0.35, 0.12), (0.1, 0.1, 0.1), (0.8, 0.1, 0.1), (0.9, 0.85, 0.7)][k]
        ell((0.17, 0.2, 0.05), (x, 0.9, 0.06), col)                   # body
        ell((0.13, 0.15, 0.05), (x, 1.2, 0.06), col)
        cyl(0.05, 0.01, (x, 1.02, 0.11), (0.05, 0.05, 0.05), segs=16, rot=[("x", math.pi / 2)])
        rbox((0.05, 0.6, 0.025), (x, 1.62, 0.07), (0.3, 0.2, 0.12))  # neck
        rbox((0.08, 0.14, 0.03), (x, 1.98, 0.07), (0.2, 0.14, 0.08))
        rod((x, 2.1, 0.02), (x, 2.05, 0.08), 0.01, (0.7, 0.7, 0.72), segs=6, kind="Metal")
    rbox((0.5, 0.14, 0.02), (0.72, 0.4, 0.0), (0.95, 0.78, 0.1))
    finish("GuitarWall")


# ----------------------------------------------------------------------------- money, bank & gun store
#
# Gameplay code is written against the reference points below (prop-local Godot axes, meters).
# They are computed from the same numbers that build the geometry and stored in REF[prop];
# `main()` prints them after every build so the contract can be checked at a glance.
#
#   MoneyCounter / MoneyCounterPro / CashCounter  origin bottom center, front +z, 0.30 x 0.24 x 0.28
#       hopper   base center of the input stack; the stack sits on a tray tilted 20 deg
#                (rotate a BillStack by rotation.x = +20 deg so its +y matches the tray normal)
#       stacker  base center of the output stack (flat pocket floor), long side along x
#       lcd      center + normal of the flat blue LCD (sloped 45 deg; a Label3D there needs rotation.x = -45 deg)
#   CounterDisplay   origin bottom center; red LED panel faces +z
#   BillStack / MoneyBrick   0.156 (x) x 0.066 (z), origin bottom center; height 0.010 / 0.011
#   BillFan    origin = grip pivot; 9 bills fanned in the XY plane, facing +z, 110 deg spread about +y
#   ATM        origin floor center, front +z: screen / dispenser / header panel points in REF
#   Gun_*      origin = grip center (where the right hand closes), barrel -z, up +y:
#              REF has the barrel tip and the support-hand point (left hand on the handguard / pump)
#   GunWallRack  origin bottom center, back at z=0, front +z;  GunCase origin floor center, front +z
#   TargetSheet  origin at its center, back on z=0, front +z;  AmmoShelf origin floor center, front +z

REF = {}


def _r3(v):
    return tuple(round(float(c), 4) for c in v)


# --- money counter ------------------------------------------------------------------

MC_BLACK = {"body": (0.16, 0.16, 0.17), "base": (0.06, 0.06, 0.065), "panel": (0.045, 0.045, 0.05),
            "tray": (0.27, 0.28, 0.31),
            "bezel": (0.2, 0.21, 0.23), "wing": (0.3, 0.32, 0.36), "floor": (0.2, 0.2, 0.22),
            "vent": (0.05, 0.05, 0.055), "btn": (0.55, 0.57, 0.6), "inner": (0.035, 0.035, 0.04)}
MC_PRO = {"body": (0.9, 0.9, 0.91), "base": (0.62, 0.63, 0.66), "panel": (0.07, 0.07, 0.08),
          "tray": (0.66, 0.68, 0.72),
          "bezel": (0.32, 0.33, 0.36), "wing": (0.76, 0.82, 0.88), "floor": (0.74, 0.75, 0.78),
          "vent": (0.6, 0.61, 0.64), "btn": (0.84, 0.85, 0.88), "inner": (0.16, 0.16, 0.18)}
LCD_BLUE = (0.08, 0.2, 0.62)

MC_TRAY_TILT = math.radians(20)       # hopper tray: rises toward the back, normal leans forward
MC_TRAY_LOW = (0.048, 0.1775)         # (z, y) front/low end of the tray, against the feed gate
MC_FACE_E = Vector((0, 0.12, 0.14))   # bottom edge of the 45-degree control face
MC_FACE_A = math.radians(45)


def build_money_counter(name, pal):
    """Front-loading bill counter, 0.30 w x 0.24 h x 0.28 d, origin bottom center, front +z.
    Bills go in the sloped hopper on top (between two guide wings), come out in the stacker
    pocket at the front-bottom; blue LCD on the 45-degree face (Godot draws the count)."""
    W = 0.30
    tz, ty = MC_TRAY_LOW
    tan = math.tan(MC_TRAY_TILT)
    z_back = tz - (0.24 - ty) / tan                     # tray reaches the 0.24 top here
    shell = [(-0.14, 0.014), (0.045, 0.014), (0.045, 0.097), (0.14, 0.101), (0.14, 0.12),
             (0.06, 0.2), (tz, ty), (z_back, 0.24), (-0.14, 0.24)]
    prism(shell, "x", -W / 2, W / 2, pal["body"], r=0.008, seg=2, kind="Gloss")
    rbox((W, 0.02, 0.28), (0, 0.01, 0), pal["base"], r=0.006)                               # base / feet band
    # stacker pocket: dark back wall, plastic floor, side cheeks, front lip, two fingers
    rbox((0.26, 0.082, 0.004), (0, 0.056, 0.047), pal["inner"])
    rbox((0.25, 0.003, 0.09), (0, 0.0215, 0.092), pal["floor"])
    for sx in (-1, 1):
        rbox((0.02, 0.09, 0.098), (sx * 0.14, 0.058, 0.091), pal["body"], r=0.006, kind="Gloss")
        rbox((0.014, 0.036, 0.004), (sx * 0.05, 0.043, 0.133), pal["wing"], r=0.002, kind="Gloss", rot=[("x", -0.3)])
    rbox((0.25, 0.008, 0.008), (0, 0.025, 0.135), pal["base"], r=0.002)
    stacker = Vector((0, 0.023, 0.09))
    # hopper: feed gap at the gate, two guide wings following the 20-degree tray
    rbox((0.17, 0.004, 0.004), (0, ty + 0.001, tz - 0.001), pal["inner"])
    for sx in (-1, 1):
        wing = [(0.054, ty - 0.004), (0.054, ty + 0.03), (-0.07, ty + 0.03 + 0.124 * tan),
                (-0.07, ty - 0.004 + 0.118 * tan)]
        prism(wing, "x", sx * 0.086, sx * 0.093, pal["wing"], r=0.0025, seg=1, kind="Gloss")
    u = Vector((0, math.sin(MC_TRAY_TILT), -math.cos(MC_TRAY_TILT)))    # up the tray, toward the back
    nt = Vector((0, math.cos(MC_TRAY_TILT), math.sin(MC_TRAY_TILT)))    # tray normal
    T0 = Vector((0, ty, tz))
    trot = [("x", MC_TRAY_TILT)]
    rbox((0.168, 0.003, 0.15), T0 + u * 0.079 + nt * 0.0005, pal["tray"], r=0.001, kind="Gloss", rot=trot)
    for sx in (-1, 1):                                                  # rubber feed rollers
        rbox((0.03, 0.003, 0.014), T0 + Vector((sx * 0.035, 0, 0)) + u * 0.014 + nt * 0.0006, pal["inner"], rot=trot)
    hopper = T0 + u * 0.036 + nt * 0.002                                # stack (0.066 deep) against the gate
    # side vents + back switch/socket
    for k in range(4):
        rbox((W + 0.002, 0.004, 0.09), (0, 0.05 + k * 0.014, -0.06), pal["vent"])
    rbox((0.022, 0.014, 0.004), (0.09, 0.06, -0.141), pal["inner"])
    rbox((0.03, 0.022, 0.004), (-0.08, 0.06, -0.141), pal["inner"])
    # control face: dark panel, bezel, LCD, buttons
    E, a = MC_FACE_E, MC_FACE_A
    s = Vector((0, math.sin(a), -math.cos(a)))
    n = Vector((0, math.cos(a), math.sin(a)))
    rot = [("x", a)]

    def fp(x, sd, h):
        return Vector((x, 0, 0)) + E + s * sd + n * h
    rbox((0.272, 0.006, 0.09), fp(0, 0.058, 0.002), pal["panel"], r=0.004, kind="Gloss", rot=rot)
    lcd_x, lcd_s, lcd_w, lcd_h = -0.03, 0.066, 0.12, 0.036
    rbox((lcd_w + 0.012, 0.002, lcd_h + 0.012), fp(lcd_x, lcd_s, 0.0045), pal["bezel"], r=0.001, rot=rot)
    rbox((lcd_w, 0.002, lcd_h), fp(lcd_x, lcd_s, 0.0055), LCD_BLUE, kind="Glow", rot=rot)
    lcd = fp(lcd_x, lcd_s, 0.0065)
    for i, (bx, bs) in enumerate(((0.074, 0.052), (0.108, 0.052), (0.074, 0.08), (0.108, 0.08))):
        col = (0.2, 0.45, 0.95) if i == 3 else ((0.95, 0.55, 0.12) if i == 2 else pal["btn"])
        rbox((0.026, 0.005, 0.018), fp(bx, bs, 0.006), col, r=0.002, seg=1, kind="Gloss", rot=rot)
    for k in range(4):
        rbox((0.018, 0.004, 0.011), fp(-0.078 + k * 0.032, 0.025, 0.006), pal["btn"], r=0.002, seg=1, kind="Gloss", rot=rot)
    rbox((0.006, 0.003, 0.006), fp(0.12, 0.022, 0.006), (0.3, 1.0, 0.4), kind="Glow", rot=rot)   # power LED
    finish(name)
    REF[name] = {"hopper": _r3(hopper), "hopper_tilt_deg": 20.0,
                 "hopper_normal": _r3((0, math.cos(MC_TRAY_TILT), math.sin(MC_TRAY_TILT))),
                 "stacker": _r3(stacker), "lcd_center": _r3(lcd), "lcd_normal": _r3(n),
                 "lcd_size": (lcd_w, lcd_h)}


def build_counter_display():
    """Customer display for the money counter: a black box on a little stand, red LED window at +z."""
    K = (0.07, 0.07, 0.075)
    rbox((0.064, 0.008, 0.046), (0, 0.004, 0), K, r=0.004, kind="Gloss")
    rbox((0.018, 0.024, 0.012), (0, 0.018, -0.003), K, r=0.003, kind="Gloss")
    rbox((0.1, 0.044, 0.026), (0, 0.048, 0), K, r=0.008, seg=2, kind="Gloss")
    rbox((0.084, 0.03, 0.002), (0, 0.049, 0.0128), (0.02, 0.02, 0.022), r=0.003)
    rbox((0.078, 0.024, 0.002), (0, 0.049, 0.0135), (0.3, 0.025, 0.02), kind="Glow")
    rod((0, 0.01, -0.02), (0.02, 0.004, -0.045), 0.0025, K, segs=6)
    finish("CounterDisplay")
    REF["CounterDisplay"] = {"led_center": (0.0, 0.049, 0.0145), "led_normal": (0, 0, 1), "led_size": (0.078, 0.024)}


# --- bills ------------------------------------------------------------------------------

BILL_W, BILL_D = 0.156, 0.066
BILL_EDGE = ((0.52, 0.62, 0.46), (0.58, 0.68, 0.51))
BILL_LINE = (0.33, 0.41, 0.3)
BILL_TOP = (0.64, 0.73, 0.58)
BILL_INK = (0.24, 0.34, 0.24)
BILL_RIBBON = (0.25, 0.45, 0.85)


def _paper_layers(x0, x1, y0, y1, layers):
    """Stacked paper slabs with thin darker lines between them (many bills seen edge-on)."""
    line = 0.0003
    h = (y1 - y0 - (layers - 1) * line) / layers
    y = y0
    for k in range(layers):
        rbox((x1 - x0, h, BILL_D), ((x0 + x1) / 2, y + h / 2, 0), BILL_EDGE[k % 2])
        y += h
        if k < layers - 1:
            rbox((x1 - x0, line, BILL_D), ((x0 + x1) / 2, y + line / 2, 0), BILL_LINE)
            y += line


def build_bills():
    # BillStack: loose $100s, exactly 0.156 x 0.010 x 0.066 (the game scales it in Y)
    _paper_layers(-BILL_W / 2, BILL_W / 2, 0.0, 0.0093, 6)
    rbox((BILL_W, 0.0004, BILL_D), (0, 0.0095, 0), BILL_TOP)                           # top bill
    T = 0.0097                                                                          # top bill surface
    ell((0.013, 0.0003, 0.017), (-0.012, T, 0), BILL_INK, segs=12, rings=4)          # portrait oval
    rbox((0.004, 0.0003, BILL_D), (0.022, T + 0.00015, 0), BILL_RIBBON)                # security ribbon
    for sx in (-1, 1):
        for sz in (-1, 1):
            rbox((0.014, 0.0003, 0.007), (sx * 0.064, T + 0.00015, sz * 0.025), BILL_INK)   # corner "100"s
    rbox((0.02, 0.0003, 0.01), (0.052, T + 0.00015, 0.017), (0.75, 0.6, 0.3))          # big copper 100
    finish("BillStack")
    REF["BillStack"] = {"size": (BILL_W, 0.01, BILL_D)}

    # MoneyBrick: strapped $10K (100 bills), 0.156 x 0.011 x 0.066, mustard bank strap around the middle
    B = 0.016
    for x0, x1 in ((-BILL_W / 2, -B), (B, BILL_W / 2)):
        _paper_layers(x0, x1, 0.0, 0.0101, 7)
        rbox((x1 - x0, 0.0003, BILL_D), ((x0 + x1) / 2, 0.01025, 0), BILL_TOP)
    for sx in (-1, 1):
        for sz in (-1, 1):
            rbox((0.014, 0.0002, 0.007), (sx * 0.064, 0.0105, sz * 0.025), BILL_INK)
    rbox((2 * B, 0.0108, BILL_D), (0, 0.0054, 0), (0.86, 0.68, 0.16))                   # strap
    rbox((0.022, 0.0002, 0.03), (0, 0.0109, 0), (0.5, 0.36, 0.08))                      # "$10,000" print
    finish("MoneyBrick")
    REF["MoneyBrick"] = {"size": (BILL_W, 0.011, BILL_D), "strap_width": 2 * B}

    # BillFan: 9 hundreds fanned like a hand of cards, pivot at the grip, facing +z
    n, spread = 9, math.radians(110)
    for i in range(n):
        ang = spread / 2 - i * spread / (n - 1)          # leftmost bill first, at the back
        n0 = len(PARTS)
        rbox((BILL_D, BILL_W, 0.0006), (0, 0.068, 0), BILL_TOP if i == n - 1 else BILL_EDGE[1])
        f = 0.0006
        ell((0.012, 0.016, 0.0003), (0, 0.062, f), BILL_INK, segs=10, rings=4)
        rbox((BILL_D, 0.004, 0.0003), (0, 0.092, f), BILL_RIBBON)
        for sy in (-1, 1):
            rbox((0.008, 0.013, 0.0003), (0.023, 0.068 + sy * 0.064, f), BILL_INK)
        rbox((BILL_D - 0.006, 0.001, 0.0002), (0, 0.068 - 0.074, f), BILL_LINE)
        rbox((BILL_D - 0.006, 0.001, 0.0002), (0, 0.068 + 0.074, f), BILL_LINE)
        xform_since(n0, (0, 0, 0.0004 + i * 0.0012), [("z", ang)])
    finish("BillFan")
    REF["BillFan"] = {"pivot": (0, 0, 0), "spread_deg": 110, "bills": n,
                      "bill_center_radius": 0.068}


# --- ATM --------------------------------------------------------------------------------

def build_atm():
    """Free-standing bank ATM, 0.75 w x 1.65 h x 0.6 d, origin floor center, front +z."""
    BODY = (0.17, 0.21, 0.3)
    FASCIA = (0.07, 0.07, 0.08)
    SILVER = (0.72, 0.74, 0.78)
    GREEN = (0.16, 0.62, 0.32)
    rbox((0.73, 0.06, 0.48), (0, 0.03, -0.05), (0.04, 0.04, 0.045), r=0.01)                       # plinth
    rbox((0.75, 0.9, 0.5), (0, 0.5, -0.05), BODY, r=0.02, seg=1, kind="Gloss")                      # lower body
    rbox((0.75, 0.48, 0.38), (0, 1.2, -0.11), FASCIA, r=0.02, seg=1, kind="Gloss")                  # upper fascia
    rbox((0.75, 0.22, 0.52), (0, 1.54, -0.04), BODY, r=0.02, seg=2, kind="Gloss")                   # header box
    for sx in (-1, 1):                                                                              # screen hood
        rbox((0.06, 0.47, 0.15), (sx * 0.345, 1.2, 0.145), BODY, r=0.015, kind="Gloss")
        rbox((0.018, 0.9, 0.02), (sx * 0.366, 0.5, 0.2), SILVER, r=0.006, kind="Metal")           # corner trim
    rbox((0.63, 0.012, 0.13), (0, 1.425, 0.15), FASCIA, kind="Gloss")                              # hood top liner
    # header: lit panel (Godot writes the bank name on it)
    hdr_c, hdr_w, hdr_h = Vector((0, 1.54, 0.224)), 0.68, 0.15
    rbox((hdr_w + 0.016, hdr_h + 0.016, 0.004), hdr_c - Vector((0, 0, 0.0025)), SILVER, kind="Metal")
    rbox((hdr_w, hdr_h, 0.004), hdr_c - Vector((0, 0, 0.002)), (0.1, 0.32, 0.72), kind="Glow")
    # screen in its hood
    scr_c, scr_w, scr_h = Vector((0, 1.21, 0.093)), 0.40, 0.30
    rbox((0.46, 0.36, 0.012), (0, 1.21, 0.085), (0.03, 0.03, 0.035), r=0.008, kind="Gloss")
    rbox((scr_w, scr_h, 0.004), scr_c - Vector((0, 0, 0.002)), (0.04, 0.1, 0.18), kind="Glow")
    for k in range(4):                                                                             # side soft keys
        for sx in (-1, 1):
            rbox((0.026, 0.02, 0.012), (sx * 0.232, 1.1 + k * 0.07, 0.088), SILVER, kind="Metal")
    # card reader (right of screen, lower) with green lead-in light; receipt slot above it
    rbox((0.075, 0.07, 0.035), (0.272, 1.1, 0.1), (0.12, 0.12, 0.13), r=0.008, kind="Gloss")
    rbox((0.055, 0.007, 0.004), (0.272, 1.105, 0.118), (0.01, 0.01, 0.01))
    rbox((0.055, 0.006, 0.003), (0.272, 1.088, 0.118), (0.2, 1.0, 0.45), kind="Glow")
    rbox((0.075, 0.035, 0.025), (0.272, 1.33, 0.095), (0.12, 0.12, 0.13), r=0.006, kind="Gloss")
    rbox((0.058, 0.005, 0.004), (0.272, 1.33, 0.108), (0.01, 0.01, 0.01))
    for k in range(4):                                                                             # speaker grille
        rbox((0.05, 0.005, 0.003), (-0.272, 1.29 + k * 0.014, 0.081), (0.2, 0.2, 0.22))
    ell((0.008, 0.008, 0.004), (0, 1.395, 0.08), (0.02, 0.02, 0.03), segs=10, rings=4, kind="Gloss")  # camera
    # keypad console: sloped shelf that juts out to z = 0.30
    prism([(0.18, 0.86), (0.3, 0.895), (0.3, 0.95), (0.075, 1.02), (0.075, 0.9)], "x", -0.375, 0.375,
          FASCIA, r=0.012, seg=2, kind="Gloss")
    a = math.atan2(0.07, 0.225)
    s = Vector((0, math.sin(a), -math.cos(a)))
    nk = Vector((0, math.cos(a), math.sin(a)))
    P0 = Vector((0, 0.95, 0.3))

    def kp(x, sd, h):
        return Vector((x, 0, 0)) + P0 + s * sd + nk * h
    rot = [("x", a)]
    rbox((0.2, 0.006, 0.16), kp(-0.06, 0.115, 0.002), (0.2, 0.21, 0.23), r=0.006, kind="Metal", rot=rot)
    for row in range(4):
        for col in range(3):
            rbox((0.036, 0.008, 0.028), kp(-0.12 + col * 0.045, 0.06 + row * 0.036, 0.006), SILVER, kind="Metal", rot=rot)
    for row, c in enumerate(((0.2, 0.75, 0.3), (0.95, 0.8, 0.15), (0.9, 0.18, 0.15), SILVER)):
        rbox((0.05, 0.008, 0.028), kp(0.01, 0.06 + row * 0.036, 0.006), c, kind="Gloss", rot=rot)
    rbox((0.12, 0.004, 0.06), kp(0.2, 0.12, 0.002), (0.25, 0.25, 0.27), kind="Gloss", rot=rot)   # privacy label
    # cash dispenser: metal lip + wide dark slot + green "take cash" lights
    rbox((0.37, 0.08, 0.03), (0, 0.79, 0.21), SILVER, r=0.01, kind="Metal")
    rbox((0.3, 0.022, 0.012), (0, 0.79, 0.2215), (0.01, 0.01, 0.012))
    rbox((0.32, 0.01, 0.04), (0, 0.772, 0.228), SILVER, r=0.004, kind="Metal")
    rbox((0.1, 0.006, 0.004), (0, 0.818, 0.2255), (0.2, 1.0, 0.45), kind="Glow")
    dispenser = Vector((0, 0.79, 0.2275))
    # lower body: green brand stripe, service door with a lock, receipt-ish deposit slot
    rbox((0.75, 0.035, 0.008), (0, 0.7, 0.2), GREEN, kind="Gloss")
    rbox((0.6, 0.5, 0.008), (0, 0.38, 0.2), (0.14, 0.17, 0.25), r=0.004, kind="Gloss")
    cyl(0.014, 0.012, (0.24, 0.52, 0.206), SILVER, segs=12, kind="Metal", rot=[("x", math.pi / 2)])
    rbox((0.02, 0.002, 0.002), (0.24, 0.52, 0.2125), (0.05, 0.05, 0.05))
    rbox((0.2, 0.03, 0.02), (-0.2, 0.62, 0.205), SILVER, r=0.005, kind="Metal")                      # deposit slot
    rbox((0.16, 0.006, 0.004), (-0.2, 0.62, 0.2155), (0.01, 0.01, 0.01))
    finish("ATM")
    REF["ATM"] = {"screen_center": _r3(scr_c), "screen_normal": (0, 0, 1), "screen_size": (scr_w, scr_h),
                  "dispenser": _r3(dispenser), "dispenser_slot_size": (0.3, 0.022),
                  "header_center": _r3(hdr_c), "header_normal": (0, 0, 1), "header_size": (hdr_w, hdr_h)}


# --- guns -------------------------------------------------------------------------------
# Each _gun_* emits parts in its own design coordinates, then moves them so the grip center is
# the origin; returns the reference points in the final (grip-origin) coordinates.  GUN_LOD
# drops bevels, tiny details and cylinder segments for the copies baked into the rack / case.

GUN_LOD = False
GUN_BLACK = (0.25, 0.25, 0.27)     # blued steel ("Metal")
GUN_POLY = (0.1, 0.1, 0.105)
GUN_DARK = (0.03, 0.03, 0.035)
GUN_WOOD = (0.55, 0.3, 0.13)
GUN_WOOD_D = (0.36, 0.19, 0.08)
GOLD_D = (0.82, 0.58, 0.13)


def gbox(size, pos, col, r=0.0, kind="Metal", rot=None, seg=1, detail=False):
    if detail and GUN_LOD:
        return
    rbox(size, pos, col, r=0.0 if GUN_LOD else r, seg=seg, kind=kind, rot=rot)


def gcyl(r, h, pos, col, segs=12, kind="Metal", rot=None, detail=False):
    if detail and GUN_LOD:
        return
    cyl(r, h, pos, col, segs=max(6, segs // 2) if GUN_LOD else segs, kind=kind, rot=rot)


def grod(a, b, r, col, segs=12, kind="Metal", detail=False):
    if detail and GUN_LOD:
        return
    rod(a, b, r, col, segs=max(6, segs // 2) if GUN_LOD else segs, kind=kind)


def gprism(pts, axis, a0, a1, col, r=0.0, kind="Gloss", seg=1):
    prism(pts, axis, a0, a1, col, r=0.0 if GUN_LOD else r, seg=seg, kind=kind)


ZR = [("x", math.pi / 2)]   # cylinder along z


def _to_grip(n0, grip, pts):
    g = Vector(grip)
    xform_since(n0, -g)
    return {k: _r3(Vector(v) - g) for k, v in pts.items()}


def _gun_pistol():
    """Compact polymer pistol (Glock-like), 0.186 long."""
    n0 = len(PARTS)
    SL, PO, DK = GUN_BLACK, GUN_POLY, GUN_DARK
    gbox((0.026, 0.032, 0.186), (0, 0.07, -0.05), SL, r=0.004)                           # slide
    for k in range(7):
        gbox((0.0275, 0.022, 0.0022), (0, 0.068, 0.012 + k * 0.0045), DK, detail=True)    # serrations
    gbox((0.011, 0.004, 0.034), (0.004, 0.0865, -0.03), (0.3, 0.3, 0.31), kind="Metal", detail=True)  # port
    gbox((0.02, 0.007, 0.007), (0, 0.0885, 0.036), DK)                                     # rear sight
    gbox((0.004, 0.006, 0.005), (0, 0.0885, -0.136), DK)                                   # front sight
    gcyl(0.0055, 0.003, (0, 0.07, -0.1425), DK, segs=10, rot=ZR)                           # bore
    gbox((0.024, 0.021, 0.125), (0, 0.045, -0.072), PO, r=0.004, kind="Paint")             # frame / dust cover
    gbox((0.026, 0.022, 0.05), (0, 0.045, 0.018), PO, r=0.005, kind="Paint")               # beavertail
    for k in range(2):
        gbox((0.0245, 0.004, 0.004), (0, 0.035, -0.11 + k * 0.014), DK, detail=True)       # rail slots
    gbox((0.012, 0.006, 0.052), (0, 0.011, -0.038), PO, r=0.002, kind="Paint")             # trigger guard
    gbox((0.012, 0.03, 0.007), (0, 0.024, -0.064), PO, r=0.002, kind="Paint", rot=[("x", 0.15)])
    gbox((0.006, 0.02, 0.006), (0, 0.026, -0.033), DK, rot=[("x", 0.35)])                 # trigger
    GA = [("x", -0.33)]
    grip = Vector((0, -0.01, 0.0034))
    d = Vector((0, math.cos(-0.33), math.sin(-0.33)))
    gbox((0.03, 0.105, 0.05), grip, PO, r=0.008, kind="Paint", rot=GA)                     # grip
    gbox((0.031, 0.06, 0.034), grip + d * -0.004, (0.055, 0.055, 0.06), kind="Paint", rot=GA, detail=True)  # stipple
    gbox((0.032, 0.009, 0.054), grip + d * -0.056, PO, r=0.003, kind="Paint", rot=GA)      # mag base
    return _to_grip(n0, grip, {"barrel_tip": (0, 0.07, -0.144), "support_hand": grip + Vector((-0.03, -0.012, -0.004))})


def _gun_deagle():
    """Big heavy .50 pistol (Desert-Eagle-like), 0.27 long, all gold."""
    n0 = len(PARTS)
    GD, G2, K = GOLD, GOLD_D, "Metal"
    gprism([(-0.015, 0.108), (0.015, 0.108), (0.016, 0.09), (0.009, 0.064), (-0.009, 0.064), (-0.016, 0.09)],
           "z", -0.2, -0.055, GD, r=0.003, kind=K)                                        # triangular barrel
    gbox((0.01, 0.006, 0.145), (0, 0.111, -0.128), G2, kind=K)                             # top rib
    gbox((0.032, 0.044, 0.13), (0, 0.084, 0.005), GD, r=0.004, kind=K)                     # slide
    for k in range(8):
        gbox((0.0335, 0.03, 0.0025), (0, 0.082, 0.02 + k * 0.0055), G2, kind=K, detail=True)
    gbox((0.028, 0.026, 0.19), (0, 0.05, -0.075), GD, r=0.004, kind=K)                     # frame
    gbox((0.03, 0.028, 0.055), (0, 0.05, 0.045), GD, r=0.005, kind=K)
    gbox((0.01, 0.018, 0.012), (0, 0.104, 0.074), G2, kind=K, rot=[("x", 0.5)])            # hammer
    gbox((0.022, 0.008, 0.008), (0, 0.109, 0.06), G2, kind=K)                              # rear sight
    gbox((0.005, 0.01, 0.008), (0, 0.115, -0.19), G2, kind=K)                              # front sight
    gcyl(0.0065, 0.003, (0, 0.093, -0.2005), GUN_DARK, segs=12, rot=ZR)                    # bore
    gbox((0.004, 0.01, 0.022), (-0.017, 0.086, 0.05), G2, kind=K, detail=True)             # safety
    gbox((0.012, 0.007, 0.07), (0, 0.012, -0.046), GD, r=0.002, kind=K)                    # trigger guard
    gbox((0.012, 0.034, 0.008), (0, 0.027, -0.08), GD, r=0.002, kind=K, rot=[("x", 0.12)])
    gbox((0.007, 0.022, 0.007), (0, 0.028, -0.043), G2, kind=K, rot=[("x", 0.35)])         # trigger
    GA = [("x", -0.28)]
    grip = Vector((0, -0.012, 0.012))
    d = Vector((0, math.cos(-0.28), math.sin(-0.28)))
    gbox((0.034, 0.112, 0.058), grip, GD, r=0.01, kind=K, rot=GA)
    gbox((0.036, 0.075, 0.042), grip + d * -0.004, G2, kind=K, rot=GA, detail=True)       # grip panels
    gbox((0.036, 0.01, 0.062), grip + d * -0.06, G2, r=0.003, kind=K, rot=GA)              # mag base
    return _to_grip(n0, grip, {"barrel_tip": (0, 0.093, -0.202), "support_hand": grip + Vector((-0.032, -0.012, -0.004))})


def _gun_smg():
    """Compact SMG (Uzi-like) with the stick magazine in the pistol grip, stock folded."""
    n0 = len(PARTS)
    BK, PO, DK = GUN_BLACK, GUN_POLY, GUN_DARK
    gbox((0.044, 0.058, 0.26), (0, 0.07, -0.05), BK, r=0.006)                              # receiver
    for sx in (-1, 1):
        gbox((0.004, 0.004, 0.2), (sx * 0.012, 0.1005, -0.05), BK, detail=True)            # top ribs
    gcyl(0.008, 0.014, (0, 0.104, -0.07), DK, segs=10)                                     # cocking knob
    gbox((0.024, 0.016, 0.01), (0, 0.105, 0.066), BK)                                      # rear sight
    for sx in (-1, 1):
        gbox((0.005, 0.02, 0.014), (sx * 0.009, 0.106, -0.165), BK)                        # front sight ears
    gbox((0.003, 0.014, 0.004), (0, 0.104, -0.165), DK, detail=True)
    gcyl(0.017, 0.022, (0, 0.07, -0.191), BK, segs=14, rot=ZR)                             # barrel nut
    gcyl(0.009, 0.035, (0, 0.07, -0.2185), BK, segs=10, rot=ZR)                            # barrel
    gcyl(0.005, 0.002, (0, 0.07, -0.2365), DK, segs=8, rot=ZR)                             # bore
    gbox((0.04, 0.03, 0.14), (0, 0.032, -0.11), PO, r=0.006, kind="Paint")                 # front grip frame
    GA = [("x", -0.1)]
    grip = Vector((0, -0.01, 0.004))
    d = Vector((0, math.cos(-0.1), math.sin(-0.1)))
    gbox((0.034, 0.11, 0.046), grip, PO, r=0.008, kind="Paint", rot=GA)                    # pistol grip
    gbox((0.026, 0.1, 0.034), grip + d * -0.09, BK, r=0.003, rot=GA)                       # stick magazine
    gbox((0.03, 0.008, 0.038), grip + d * -0.142, BK, r=0.002, rot=GA)                     # mag base
    gbox((0.018, 0.055, 0.008), (0, 0.005, 0.03), BK, rot=GA)                              # grip safety
    gbox((0.012, 0.006, 0.055), (0, 0.006, -0.045), PO, r=0.002, kind="Paint")             # trigger guard
    gbox((0.012, 0.032, 0.007), (0, 0.021, -0.071), PO, r=0.002, kind="Paint")
    gbox((0.006, 0.02, 0.006), (0, 0.025, -0.04), DK, rot=[("x", 0.3)])                   # trigger
    for sx in (-1, 1):                                                                      # folded stock
        grod((sx * 0.026, 0.05, 0.085), (sx * 0.026, 0.05, -0.13), 0.0035, BK, segs=6)
    gbox((0.058, 0.03, 0.022), (0, 0.06, 0.09), BK, r=0.004)                               # stock hinge
    gbox((0.062, 0.035, 0.01), (0, 0.045, -0.136), BK, r=0.003)                            # butt plate
    return _to_grip(n0, grip, {"barrel_tip": (0, 0.07, -0.237), "support_hand": (0, 0.032, -0.11)})


def _gun_shotgun():
    """Pump shotgun (870-like): black steel, wood stock + pump, 1.06 long."""
    n0 = len(PARTS)
    ST, WD, WD2, DK = GUN_BLACK, GUN_WOOD, GUN_WOOD_D, GUN_DARK
    gbox((0.034, 0.056, 0.2), (0, 0.052, -0.09), ST, r=0.006)                              # receiver
    gbox((0.002, 0.02, 0.065), (0.0172, 0.062, -0.1), DK, detail=True)                     # ejection port
    gbox((0.026, 0.02, 0.1), (0, 0.018, -0.05), ST, r=0.004)                               # trigger plate
    gbox((0.012, 0.006, 0.06), (0, -0.004, -0.045), ST, r=0.002)                           # trigger guard
    gbox((0.012, 0.026, 0.007), (0, 0.008, -0.074), ST, r=0.002)
    gbox((0.006, 0.02, 0.006), (0, 0.008, -0.045), DK, rot=[("x", 0.3)])
    grod((0, 0.058, -0.19), (0, 0.058, -0.69), 0.0115, ST, segs=12)                        # barrel
    gbox((0.008, 0.005, 0.49), (0, 0.0715, -0.44), ST, detail=True)                        # vent rib
    gbox((0.005, 0.005, 0.005), (0, 0.076, -0.683), (0.95, 0.93, 0.85), kind="Metal")      # bead
    gcyl(0.0085, 0.002, (0, 0.058, -0.6905), DK, segs=10, rot=ZR)                          # bore
    grod((0, 0.03, -0.19), (0, 0.03, -0.615), 0.0115, ST, segs=12)                         # magazine tube
    gcyl(0.013, 0.02, (0, 0.03, -0.62), ST, segs=12, rot=ZR)                               # mag cap
    gbox((0.018, 0.045, 0.012), (0, 0.045, -0.6), ST)                                      # barrel clamp
    for sx in (-1, 1):
        gbox((0.004, 0.008, 0.07), (sx * 0.014, 0.035, -0.21), ST, detail=True)            # action bars
    gbox((0.044, 0.044, 0.19), (0, 0.032, -0.33), WD, r=0.014, seg=2, kind="Gloss")        # pump
    for k in range(6):
        gbox((0.0455, 0.0455, 0.005), (0, 0.032, -0.268 - k * 0.025), WD2, r=0.014, kind="Gloss", detail=True)
    stock = [(0.0, 0.074), (0.07, 0.056), (0.14, 0.062), (0.345, 0.056), (0.355, 0.05), (0.355, -0.085),
             (0.33, -0.088), (0.1, -0.02), (0.045, 0.006), (0.01, 0.015), (0.0, 0.03)]
    gprism(stock, "x", -0.019, 0.019, WD, r=0.006, seg=2)
    gbox((0.04, 0.142, 0.016), (0, -0.0175, 0.362), (0.06, 0.06, 0.065), r=0.005, kind="Paint")  # butt pad
    return _to_grip(n0, (0, 0.034, 0.045), {"barrel_tip": (0, 0.058, -0.692), "support_hand": (0, 0.032, -0.33)})


def _gun_rifle(steel=GUN_BLACK, steel_kind="Metal", furn=GUN_WOOD, furn_kind="Gloss"):
    """AK-style rifle: wood (or black) furniture, curved magazine, 0.89 long. Grip at the origin."""
    n0 = len(PARTS)
    ST, SK, FU, FK, DK = steel, steel_kind, furn, furn_kind, GUN_DARK
    gbox((0.032, 0.05, 0.25), (0, 0.065, -0.03), ST, r=0.005, kind=SK)                     # receiver
    gbox((0.03, 0.02, 0.23), (0, 0.092, -0.02), ST, r=0.009, kind=SK)                      # dust cover
    gbox((0.034, 0.05, 0.03), (0, 0.068, -0.165), ST, r=0.004, kind=SK)                    # trunnion
    gbox((0.026, 0.024, 0.055), (0, 0.098, -0.19), ST, r=0.004, kind=SK)                   # rear sight block
    gbox((0.02, 0.006, 0.05), (0, 0.112, -0.18), ST, kind=SK, detail=True)                 # sight leaf
    grod((0, 0.078, -0.16), (0, 0.078, -0.505), 0.008, ST, segs=12, kind=SK)               # barrel
    gcyl(0.0105, 0.03, (0, 0.078, -0.52), ST, segs=12, kind=SK, rot=ZR)                    # muzzle nut
    gcyl(0.005, 0.002, (0, 0.078, -0.5355), DK, segs=8, rot=ZR)                            # bore
    gbox((0.02, 0.02, 0.03), (0, 0.08, -0.47), ST, kind=SK)                                # front sight block
    gbox((0.016, 0.036, 0.012), (0, 0.1, -0.475), ST, kind=SK)                             # front sight post
    gbox((0.022, 0.045, 0.028), (0, 0.092, -0.405), ST, r=0.003, kind=SK)                  # gas block
    grod((0, 0.06, -0.4), (0, 0.06, -0.52), 0.003, ST, segs=6, kind=SK, detail=True)       # cleaning rod
    gbox((0.03, 0.024, 0.17), (0, 0.109, -0.305), FU, r=0.009, kind=FK)                    # upper handguard
    gbox((0.044, 0.05, 0.2), (0, 0.068, -0.29), FU, r=0.012, seg=2, kind=FK)               # lower handguard
    gbox((0.046, 0.054, 0.01), (0, 0.068, -0.186), ST, kind=SK)                            # retainer
    gbox((0.014, 0.012, 0.022), (0.022, 0.082, -0.07), ST, r=0.003, kind=SK)               # charging handle
    gbox((0.004, 0.014, 0.075), (0.0175, 0.072, -0.03), ST, kind=SK, rot=[("x", 0.05)], detail=True)  # selector
    gbox((0.012, 0.005, 0.075), (0, 0.013, -0.066), ST, r=0.002, kind=SK)                  # trigger guard
    gbox((0.012, 0.03, 0.006), (0, 0.027, -0.101), ST, kind=SK)
    gbox((0.006, 0.022, 0.006), (0, 0.03, -0.06), DK, rot=[("x", 0.3)])                   # trigger
    gbox((0.03, 0.1, 0.038), (0, 0, 0), FU, r=0.008, kind=FK, rot=[("x", -0.35)])          # pistol grip
    # curved magazine: centerline swept forward along an arc
    L, n, ph0, ph1 = 0.215, 6, 0.12, 0.78
    p = Vector((-0.137, 0.05))    # (z, y)
    back, front = [], []
    for k in range(n + 1):
        ph = ph0 + (ph1 - ph0) * k / n
        w = 0.052 - 0.008 * k / n
        nrm = Vector((-math.cos(ph), math.sin(ph)))      # toward the front
        back.append(tuple(p - nrm * w / 2))
        front.append(tuple(p + nrm * w / 2))
        p = p + Vector((-math.sin(ph), -math.cos(ph))) * (L / n)
    gprism(back + front[::-1], "x", -0.013, 0.013, ST, r=0.004, kind=SK)
    stock = [(0.085, 0.092), (0.2, 0.074), (0.345, 0.064), (0.345, -0.068), (0.3, -0.058), (0.19, -0.005),
             (0.12, 0.03), (0.085, 0.045)]
    gprism(stock, "x", -0.018, 0.018, FU, r=0.006, seg=2, kind=FK)
    gbox((0.038, 0.136, 0.01), (0, -0.002, 0.35), ST, r=0.003, kind=SK)                    # butt plate
    return _to_grip(n0, (0, 0, 0), {"barrel_tip": (0, 0.078, -0.536), "support_hand": (0, 0.068, -0.29)})


GUNS = (("Gun_Pistol", _gun_pistol), ("Gun_Deagle", _gun_deagle), ("Gun_SMG", _gun_smg),
        ("Gun_Shotgun", _gun_shotgun), ("Gun_Rifle", _gun_rifle),
        ("Gun_RifleGold", lambda: _gun_rifle(GOLD, "Metal", (0.07, 0.07, 0.075), "Paint")))


def build_guns():
    for name, fn in GUNS:
        REF[name] = fn()
        REF[name]["grip"] = (0.0, 0.0, 0.0)
        finish(name)


def _place_gun(fn, rot, center=None, rest_y=None, zmin=None, lod=True):
    """Bake a (low-detail) gun into the prop being built: rotate it, then move it so its bounding
    box center sits at `center` (x, y, z; None = leave that axis), its bottom at `rest_y`, or its
    back at `zmin`. Returns the Godot-space transform (a function) for local gun points."""
    global GUN_LOD
    GUN_LOD = lod
    n0 = len(PARTS)
    fn()
    GUN_LOD = False
    M1 = xform_since(n0, (0, 0, 0), rot)
    lo, hi = bbox_since(n0)
    c = (lo + hi) / 2
    t = Vector((0, 0, 0))
    if center is not None:
        for i in range(3):
            if center[i] is not None:
                t[i] = center[i] - c[i]
    if rest_y is not None:
        t.y = rest_y - lo.y
    if zmin is not None:
        t.z = zmin - lo.z
    M2 = xform_since(n0, t)
    return lambda p: GI(M2 @ M1 @ G(p))


# --- gun store fittings ------------------------------------------------------------------

def _tag(x, y, z, price_col=(0.85, 0.15, 0.12), rot=None):
    rbox((0.07, 0.04, 0.003), (x, y, z), PAPER, rot=rot)
    rbox((0.05, 0.009, 0.002), (x, y + 0.006, z + 0.002), price_col, rot=rot)


def build_gun_wall_rack():
    """Slat-wall gun display, 2.4 w x 1.6 h, origin bottom center, back at z=0, front +z.
    Long guns hang on pegs barrel-right, pistols hang by the trigger guard."""
    W, H = 2.4, 1.6
    BOARD = (0.5, 0.5, 0.52)
    FRAME = (0.08, 0.08, 0.09)
    ORANGE = (0.95, 0.5, 0.08)
    rbox((W, H, 0.03), (0, H / 2, 0.015), BOARD, r=0.004)
    for k in range(14):
        rbox((W - 0.1, 0.012, 0.004), (0, 0.16 + k * 0.1, 0.031), (0.3, 0.3, 0.32))        # slat grooves
    for y in (0.03, H - 0.03):
        rbox((W, 0.06, 0.05), (0, y, 0.025), FRAME, r=0.01)
    for sx in (-1, 1):
        rbox((0.05, H, 0.05), (sx * (W / 2 - 0.025), H / 2, 0.025), FRAME, r=0.01)
    rbox((W - 0.1, 0.012, 0.012), (0, H - 0.066, 0.045), ORANGE, kind="Metal")              # accent strip
    rbox((W - 0.2, 0.012, 0.02), (0, H - 0.08, 0.06), (1.0, 0.93, 0.78), kind="Glow")       # light bar
    peg = (0.55, 0.56, 0.6)
    BARREL_RIGHT = [("y", -math.pi / 2)]            # gun's right side faces +z, muzzle to +x

    rows = []
    # row 1: two AKs;  row 2: shotgun + two SMGs;  row 3: pistols
    for fn, xc, y, pegs in ((_gun_rifle, -0.58, 1.30, ((0, 0.032, 0.06), (0, 0.035, -0.3))),
                            (GUNS[5][1], 0.58, 1.30, ((0, 0.032, 0.06), (0, 0.035, -0.3))),
                            (_gun_shotgun, -0.52, 0.93, ((0, -0.02, -0.16), (0, -0.026, -0.5))),
                            (_gun_smg, 0.32, 0.93, ((0, 0.01, 0.075), (0, 0.012, -0.15))),
                            (_gun_smg, 0.86, 0.93, ((0, 0.01, 0.075), (0, 0.012, -0.15)))):
        n0 = len(PARTS)
        f = _place_gun(fn, BARREL_RIGHT, center=(xc, None, None), zmin=0.05)
        t = Vector((0, y, 0)) - Vector((0, f((0, 0, 0)).y, 0))
        xform_since(n0, t)
        rows.append((f, t, pegs, bbox_since(n0)))
    pistols = [_gun_pistol, _gun_deagle] * 4
    for k in range(7):
        n0 = len(PARTS)
        xc = -0.93 + k * 0.31
        f = _place_gun(pistols[k], BARREL_RIGHT, center=(xc, None, None), zmin=0.05)
        t = Vector((0, 0.5, 0)) - Vector((0, f((0, 0, 0)).y, 0))
        xform_since(n0, t)
        rows.append((f, t, ((0, 0.022 + 0.01 * (k % 2), -0.045),), bbox_since(n0)))
    for f, t, pegs, (lo, hi) in rows:
        for p in pegs:
            w = f(p) + t
            rod((w.x, w.y, 0.03), (w.x, w.y, hi.z + 0.004), 0.006, peg, segs=6, kind="Metal")
        _tag((lo.x + hi.x) / 2, lo.y - 0.035, 0.034)
    rbox((W - 0.12, 0.025, 0.16), (0, 0.2, 0.08), FRAME, r=0.006)                          # bottom ledge
    rng = random.Random(5)
    cols = [(0.15, 0.45, 0.2), (0.85, 0.65, 0.1), (0.7, 0.12, 0.1), (0.1, 0.25, 0.55)]
    x = -1.08
    while x < 1.05:
        c = rng.choice(cols)
        rbox((0.1, 0.06, 0.13), (x, 0.2125 + 0.03, 0.085), c)
        rbox((0.07, 0.025, 0.002), (x, 0.245, 0.151), (0.95, 0.95, 0.92))
        x += 0.13 + rng.choice((0.0, 0.0, 0.05))
    finish("GunWallRack")
    REF["GunWallRack"] = {"size": (W, H), "back_z": 0.0}


GUNCASE_FLOOR = 0.817


def build_gun_case():
    """Glass-top gun counter, 1.8 w x 1.0 h x 0.7 d, origin floor center, customers at +z.
    Pistols lie on red felt under glass (Glass panes like the WatchCase)."""
    BODY = (0.09, 0.09, 0.1)
    PANEL = (0.14, 0.14, 0.15)
    STEEL = (0.62, 0.64, 0.68)
    ORANGE = (0.95, 0.5, 0.08)
    FELT = (0.45, 0.07, 0.09)
    rbox((1.74, 0.08, 0.64), (0, 0.04, 0), (0.03, 0.03, 0.03), r=0.004)                     # plinth
    rbox((1.8, 0.72, 0.7), (0, 0.44, 0), BODY, r=0.012, seg=2, kind="Gloss")                # cabinet
    for x in (-0.59, 0.0, 0.59):
        rbox((0.54, 0.52, 0.012), (x, 0.44, 0.354), PANEL, r=0.008, kind="Gloss")
    rbox((1.78, 0.014, 0.012), (0, 0.1, 0.35), ORANGE, kind="Metal")                        # kick stripe
    rbox((1.804, 0.018, 0.704), (0, 0.806, 0), STEEL, r=0.004, kind="Metal")                # cap
    rbox((1.77, 0.012, 0.672), (0, GUNCASE_FLOOR - 0.006, 0), FELT)                         # felt floor
    top = 1.0
    for sx in (-1, 1):                                                                      # steel frame
        for sz in (-1, 1):
            rbox((0.016, top - 0.812, 0.016), (sx * 0.892, (top + 0.812) / 2, sz * 0.342), STEEL, r=0.003, kind="Metal")
    for sz in (-1, 1):
        rbox((1.8, 0.016, 0.016), (0, top - 0.008, sz * 0.342), STEEL, r=0.003, kind="Metal")
    for sx in (-1, 1):
        rbox((0.016, 0.016, 0.7), (sx * 0.892, top - 0.008, 0), STEEL, r=0.003, kind="Metal")
    rbox((0.016, top - 0.812, 0.016), (0, (top + 0.812) / 2, 0.342), STEEL, r=0.003, kind="Metal")
    G_ = (0.85, 0.93, 0.95)
    rbox((1.77, 0.006, 0.672), (0, top - 0.003, 0), G_, kind="Glass")
    for sz in (-1, 1):
        rbox((1.77, top - 0.815, 0.006), (0, (top + 0.815) / 2, sz * 0.338), G_, kind="Glass")
    for sx in (-1, 1):
        rbox((0.006, top - 0.815, 0.672), (sx * 0.888, (top + 0.815) / 2, 0), G_, kind="Glass")
    rbox((1.7, 0.006, 0.01), (0, top - 0.02, -0.33), (1.0, 0.95, 0.85), kind="Glow")        # LED strip
    LIE = [("z", math.pi / 2), ("y", math.pi / 2)]        # right side up, top toward +z, muzzle -x
    guns = [_gun_pistol, _gun_deagle, _gun_pistol, _gun_deagle, _gun_smg, _gun_pistol]
    for i, fn in enumerate(guns):
        x = -0.58 + (i % 3) * 0.58
        z = 0.14 if i < 3 else -0.14
        _place_gun(fn, LIE, center=(x, None, z), rest_y=GUNCASE_FLOOR + 0.002)
        _tag(x + 0.19, GUNCASE_FLOOR + 0.02, z + 0.06, rot=[("x", -1.0)])
    finish("GunCase")
    REF["GunCase"] = {"felt_top_y": GUNCASE_FLOOR, "glass_top_y": top}


def build_target_sheet():
    """Paper shooting target, 0.45 x 0.6, back on z=0, origin at its center, front +z."""
    PAPER_T = (0.95, 0.93, 0.86)
    INK = (0.1, 0.1, 0.12)
    W_ = (0.95, 0.95, 0.93)
    rbox((0.45, 0.6, 0.002), (0, 0, 0.001), PAPER_T)
    torso = [(-0.19, -0.27), (0.19, -0.27), (0.19, 0.0), (0.16, 0.06), (0.1, 0.095), (0.035, 0.105),
             (-0.035, 0.105), (-0.1, 0.095), (-0.16, 0.06), (-0.19, 0.0)]
    prism(torso, "z", 0.002, 0.0028, INK)
    rbox((0.07, 0.05, 0.0008), (0, 0.125, 0.0024), INK)                                    # neck
    cyl(0.058, 0.0008, (0, 0.18, 0.0024), INK, segs=24, rot=ZR)                             # head
    for R in (0.035, 0.07, 0.105, 0.14):
        torus(R, 0.0022, (0, -0.07, 0.0028), W_, segs=24, rsegs=4, rot=ZR)
    torus(0.03, 0.002, (0, 0.18, 0.0028), W_, segs=16, rsegs=4, rot=ZR)
    cyl(0.013, 0.0008, (0, -0.07, 0.003), (0.9, 0.15, 0.1), segs=16, rot=ZR)               # bullseye
    for hx, hy, on_ink in ((0.02, -0.05, 1), (-0.045, -0.1, 1), (0.06, 0.0, 1), (0.012, 0.19, 1),
                           (0.11, -0.2, 1), (-0.17, 0.22, 0), (0.17, -0.285, 0)):
        cyl(0.0055, 0.0008, (hx, hy, 0.0034), (0.8, 0.78, 0.72) if on_ink else (0.15, 0.15, 0.15), segs=8, rot=ZR)
    for k in range(3):                                                                      # printed footer
        rbox((0.12 - k * 0.03, 0.006, 0.0006), (-0.14 + k * 0.01, -0.283 + k * 0.0, 0.0022), (0.3, 0.3, 0.32))
    for sx in (-1, 1):                                                                      # staples
        rbox((0.014, 0.003, 0.0012), (sx * 0.19, 0.28, 0.0025), (0.7, 0.72, 0.75), kind="Metal")
    finish("TargetSheet")
    REF["TargetSheet"] = {"size": (0.45, 0.6), "center": (0, 0, 0), "bullseye": (0, -0.07, 0.0034),
                          "head": (0, 0.18, 0.0034)}


def build_ammo_shelf():
    """Steel shelf of ammo boxes, 1.2 w x 1.8 h x 0.4 d, origin floor center, front +z."""
    rng = random.Random(7)
    tops = _open_shelf(1.2, 1.8, 0.4, (0.22, 0.23, 0.25), 4, back=(0.13, 0.14, 0.15))
    ORANGE = (0.95, 0.5, 0.08)
    boxes = [(0.15, 0.42, 0.2), (0.88, 0.66, 0.1), (0.72, 0.12, 0.1), (0.1, 0.26, 0.58), (0.92, 0.92, 0.9),
             (0.18, 0.18, 0.19)]
    for r, y in enumerate(tops):
        rbox((1.12, 0.03, 0.006), (0, y - 0.018, 0.2), ORANGE, kind="Metal")                # price rail
        if r == 0:        # olive ammo cans
            for k in range(3):
                x = -0.37 + k * 0.37
                rbox((0.3, 0.19, 0.16), (x, y + 0.095, 0.02), (0.3, 0.34, 0.18), r=0.01, kind="Gloss")
                rbox((0.31, 0.03, 0.17), (x, y + 0.175, 0.02), (0.26, 0.3, 0.15), r=0.006, kind="Gloss")
                rod((x - 0.06, y + 0.2, 0.02), (x + 0.06, y + 0.2, 0.02), 0.008, (0.2, 0.22, 0.12), segs=6)
                rbox((0.14, 0.03, 0.002), (x, y + 0.1, 0.101), (0.9, 0.8, 0.3))
            continue
        x = -0.5
        while x < 0.5:
            wide = rng.random() < 0.25
            bw, bh = (0.14, 0.07) if wide else (0.095, 0.052)
            c = boxes[rng.randrange(len(boxes))]
            label = (0.95, 0.95, 0.92) if c != boxes[4] else (0.72, 0.12, 0.1)
            for j in range(rng.randint(2, 5 if r < 3 else 4)):
                yy = y + bh / 2 + j * (bh + 0.001)
                rbox((bw, bh, 0.14), (x + bw / 2, yy, 0.09), c)
                rbox((bw - 0.02, bh * 0.4, 0.002), (x + bw / 2, yy, 0.161), label)
            x += bw + 0.012
    rbox((0.5, 0.1, 0.02), (0, 1.735, 0.205), (0.08, 0.08, 0.09), r=0.01)                    # header sign
    rbox((0.44, 0.064, 0.004), (0, 1.735, 0.216), ORANGE, kind="Glow")
    finish("AmmoShelf")
    REF["AmmoShelf"] = {"shelf_tops_y": [round(y, 3) for y in tops]}


def build_money_and_guns():
    build_money_counter("MoneyCounter", MC_BLACK)
    build_money_counter("MoneyCounterPro", MC_PRO)
    build_counter_display()
    build_bills()
    build_atm()
    build_guns()
    build_gun_wall_rack()
    build_gun_case()
    build_target_sheet()
    build_ammo_shelf()
    storefront("Store_Guns", (0.09, 0.15, 0.1), (0.95, 0.5, 0.08), (0.04, 0.04, 0.045), "iron")
    REF["Store_Guns"] = {"sign_band_center": (0, 3.62, 0.53), "sign_band_size": (9.6, 0.9)}


def main():
    reset()
    for fn in (build_desk, build_divider, build_crt, build_keyboard, build_mouse, build_lamp, build_chair,
               build_clutter, build_filing_cabinet, build_water_cooler, build_clock,
               build_couch, build_armchair, build_beanbag, build_coffee_table, build_plant, build_vending,
               build_slot, build_arcade, build_bell_podium, build_hoop, build_certificate, build_whiteboard,
               build_tv, build_elevator, build_ceiling_light, build_window_bay, build_cell,
               build_stream_desk, build_gaming_chair, build_ring_light, build_neon_board, build_skyline,
               build_bulletin_board, build_door, build_restroom, build_floor_mess, build_coin,
               build_luxury, build_desk_upgrades, build_flex_counter, build_street_props, build_store_props,
               build_money_and_guns):
        fn()
    keep = {o.name for o in KIT}
    for o in list(bpy.data.objects):
        if o.name not in keep:
            bpy.data.objects.remove(o)
    total = 0
    for o in KIT:
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        total += tris
        print("  %-14s %6d tris" % (o.name, tris))
    print("props:", len(KIT), " tris:", total)
    for name, ref in REF.items():   # the reference-point contract for gameplay code
        ob = bpy.data.objects[name]
        pts = [GI(v.co) for v in ob.data.vertices]
        lo = [min(p[i] for p in pts) for i in range(3)]
        hi = [max(p[i] for p in pts) for i in range(3)]
        print("REF %-16s bbox min %s max %s" % (name, _r3(lo), _r3(hi)))
        for k, v in ref.items():
            print("REF %-16s   %-20s %s" % (name, k, v))
    if os.environ.get("PROPS_REF_JSON"):      # review renders (tests/lineup_driver.gd --props) mark these
        import json
        with open(os.environ["PROPS_REF_JSON"], "w") as fh:
            json.dump(REF, fh, indent=1)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_vertex_color="ACTIVE",
                              export_apply=True, export_yup=True, export_materials="EXPORT",
                              export_normals=True)
    print("wrote", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
