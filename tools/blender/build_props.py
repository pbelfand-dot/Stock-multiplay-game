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


KINDS = ("Paint", "Gloss", "Metal", "Glow")
MATS = {}


def mat(kind):
    if kind not in MATS:
        m = bpy.data.materials.new(kind)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        vc = m.node_tree.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Col"
        m.node_tree.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
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
    """Elevator bay, 2.8 wide, face +z. Origin at the wall face, floor."""
    FRAME = (0.3, 0.31, 0.35)
    DOOR = (0.74, 0.76, 0.8)
    rbox((0.22, 2.55, 0.16), (-1.25, 1.275, 0.08), FRAME, r=0.02)
    rbox((0.22, 2.55, 0.16), (1.25, 1.275, 0.08), FRAME, r=0.02)
    rbox((2.72, 0.3, 0.16), (0, 2.45, 0.08), FRAME, r=0.02)
    for x in (-0.56, 0.56):
        rbox((1.1, 2.28, 0.05), (x, 1.14, 0.03), DOOR, r=0.01, kind="Metal")
        rbox((0.02, 2.2, 0.004), (x - 0.35 * (1 if x > 0 else -1) * 0, 1.14, 0.057), (0.66, 0.68, 0.72), kind="Metal")
    rbox((0.012, 2.28, 0.06), (0, 1.14, 0.035), (0.35, 0.36, 0.4))
    rbox((2.3, 0.02, 0.1), (0, 0.01, 0.1), (0.8, 0.82, 0.86), kind="Metal")         # threshold
    rbox((0.62, 0.22, 0.05), (0, 2.46, 0.17), (0.05, 0.05, 0.06), r=0.015)             # floor display
    # call panel on the right
    rbox((0.14, 0.3, 0.02), (1.6, 1.2, 0.01), (0.7, 0.72, 0.76), r=0.01, kind="Metal")
    for y, c in ((1.26, (1.0, 0.95, 0.6)), (1.14, (0.9, 0.9, 0.9))):
        cyl(0.03, 0.02, (1.6, y, 0.025), c, rot=[("x", math.pi / 2)], kind="Glow" if y > 1.2 else "Gloss", segs=16)
    finish("Elevator")


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
    # cash-counting machine (origin bottom), bills fed at the top, stack in the tray
    rbox((0.28, 0.16, 0.24), (0, 0.08, 0), (0.78, 0.78, 0.8), r=0.03, seg=3)
    rbox((0.24, 0.06, 0.08), (0, 0.18, -0.07), (0.7, 0.7, 0.72), r=0.02)
    rbox((0.16, 0.035, 0.065), (0, 0.215, -0.07), (0.45, 0.68, 0.38), r=0.004)       # bills on top
    rbox((0.18, 0.06, 0.02), (0, 0.11, 0.121), (0.1, 0.1, 0.12), r=0.01)            # display bezel
    rbox((0.07, 0.03, 0.005), (-0.04, 0.115, 0.132), (0.3, 1.0, 0.45), kind="Glow")
    for k in range(6):
        rbox((0.014, 0.012, 0.006), (0.03 + (k % 3) * 0.02, 0.105 + (k // 3) * 0.018, 0.132), (0.85, 0.85, 0.88))
    rbox((0.2, 0.05, 0.08), (0, 0.035, 0.13), (0.6, 0.6, 0.62), r=0.01)             # front tray
    rbox((0.16, 0.035, 0.065), (0, 0.075, 0.13), (0.45, 0.68, 0.38), r=0.004)
    finish("CashCounter")


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
    if style == "bars":             # pawn: security bars on the windows
        for side in (-1, 1):
            for k in range(9):
                cyl(0.02, 2.0, (side * 3.05 + (k - 4) * 0.36, 1.65, D + 0.12), (0.2, 0.2, 0.22), segs=6, kind="Metal")
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

def main():
    reset()
    for fn in (build_desk, build_divider, build_crt, build_keyboard, build_mouse, build_lamp, build_chair,
               build_clutter, build_filing_cabinet, build_water_cooler, build_clock,
               build_couch, build_armchair, build_beanbag, build_coffee_table, build_plant, build_vending,
               build_slot, build_arcade, build_bell_podium, build_hoop, build_certificate, build_whiteboard,
               build_tv, build_elevator, build_ceiling_light, build_window_bay, build_cell,
               build_stream_desk, build_gaming_chair, build_ring_light, build_neon_board, build_skyline,
               build_bulletin_board, build_door, build_restroom, build_floor_mess, build_coin,
               build_luxury, build_flex_counter, build_street_props):
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
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_vertex_color="ACTIVE",
                              export_apply=True, export_yup=True, export_materials="EXPORT",
                              export_normals=True)
    print("wrote", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
