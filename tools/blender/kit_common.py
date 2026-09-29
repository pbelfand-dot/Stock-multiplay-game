"""Shared Blender helpers for the neighborhood kits (build_houses.py, build_cars.py).

Same conventions as build_props.py (copied, so that file stays untouched):
coordinates are written in GODOT space (x right, y up, +z = the prop's front)
and converted to Blender (x, -z, y) on the way in; colors are baked as vertex
colors (sRGB numbers used as-is by Godot's Compatibility renderer); every
surface uses one of a few shared materials whose NAME is the "kind" that
scripts/art/prop_kit.gd maps to a Godot material:

  Paint  matte               Gloss  shiny (car paint, glass-like dark windows)
  Metal  brushed metal       Glow   unshaded, self-lit (lamps, head/tail lights)
  Glass  see-through pane    Siding lap-siding texture, tinted per house at runtime
  Trim   tinted per house    Roof   shingle texture (rows along x), tinted per house
  RoofZ  shingles, rows along z (front-gable roofs)   Screen porch screen (see-through)
"""
import math
import os

import bpy  # noqa: I001  (bpy must be imported before bmesh/mathutils)
import bmesh
from mathutils import Matrix, Vector

PARTS = []   # parts of the prop being built
KIT = []     # finished props
MATS = {}


def reset():
    global PARTS, KIT
    bpy.ops.wm.read_factory_settings(use_empty=True)
    PARTS = []
    KIT = []
    MATS.clear()


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
    for i in range(len(me.vertices)):
        a.data[i].color = (col[0], col[1], col[2], 1.0)
    me.color_attributes.active_color = a
    me.materials.append(mat(kind))
    PARTS.append(ob)
    return ob


def _sharpen(bm, angle=0.75):
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0) > angle:
            e.smooth = False


def rbox(size, pos, col, r=0.0, seg=2, kind="Paint", rot=None):
    """Box (optionally with rounded/beveled edges). size/pos in Godot space."""
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


def box2(a, b, col, kind="Paint"):
    """Axis-aligned box between two corners (Godot space)."""
    size = (abs(b[0] - a[0]), abs(b[1] - a[1]), abs(b[2] - a[2]))
    pos = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2)
    return rbox(size, pos, col, kind=kind)


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


def rod(a, b, r, col, segs=8, kind="Paint", r2=None):
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


def bar(a, b, w, h, col, kind="Paint"):
    """Square beam of cross-section w x h from a to b (Godot space), 'up' kept near +y."""
    A, B = Vector(a), Vector(b)
    d = B - A
    L = d.length
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * w, v.co.y * L, v.co.z * h))   # length along Blender y for now
    _sharpen(bm)
    # orientation in Godot space: local y(length) -> d, local z(h) -> up-ish
    fwd = d.normalized()
    up = Vector((0, 1, 0))
    if abs(fwd.dot(up)) > 0.95:
        up = Vector((1, 0, 0))
    side = fwd.cross(up).normalized()
    up2 = side.cross(fwd).normalized()
    # columns in Godot space, then convert to Blender basis
    gx, gy, gz = G(side), G(fwd), G(up2)
    M = Matrix(((gx.x, gy.x, gz.x, 0), (gx.y, gy.y, gz.y, 0), (gx.z, gy.z, gz.z, 0), (0, 0, 0, 1)))
    c = G(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2))
    M = Matrix.Translation(c) @ M
    return emit(bm, col, kind, matrix=M)


def lathe(profile, pos, col, segs=24, kind="Paint", rot=None, smooth=True):
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


def extrude(points_zy, x0, x1, col, kind="Paint", smooth=False):
    """Side profile (Godot z, y) extruded along X from x0 to x1 — car bodies, gables."""
    bm = bmesh.new()
    vs = [bm.verts.new(G((x0, y, z))) for z, y in points_zy]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    moved = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((x1 - x0, 0, 0)), verts=moved)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    _sharpen(bm, 0.3)
    return emit(bm, col, kind, smooth=smooth)


def extrude_x(points_xy, z0, z1, col, kind="Paint"):
    """Front profile (Godot x, y) extruded along Z from z0 to z1 — gable ends, shed roofs."""
    bm = bmesh.new()
    vs = [bm.verts.new(G((x, y, z0))) for x, y in points_xy]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    moved = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=G((0, 0, z1 - z0)), verts=moved)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    _sharpen(bm, 0.3)
    return emit(bm, col, kind, smooth=False)


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


def tris_of(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def export(out):
    keep = {o.name for o in KIT}
    for o in list(bpy.data.objects):
        if o.name not in keep:
            bpy.data.objects.remove(o)
    total = 0
    for o in KIT:
        t = tris_of(o)
        total += t
        print("  %-26s %6d tris" % (o.name, t))
    print("props:", len(KIT), " tris:", total)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_vertex_color="ACTIVE",
                              export_apply=True, export_yup=True, export_materials="EXPORT",
                              export_normals=True)
    print("wrote", os.path.abspath(out))
