"""BAGHOLDERS character kit — built procedurally in Blender (bpy).

Run:  python3 tools/blender/build_characters.py   (needs `pip install bpy==4.5.*`)
Out:  assets/characters/character_kit.glb

What it builds (all skinned to ONE shared skeleton, so any combo can be worn):
  * a base "stick figure" skeleton (Hips, Spine, Chest, Neck, Head, Jaw, Lid_L/R,
    UpperArm/Forearm/Hand, Thigh/Shin/Foot)
  * Body: smooth mannequin grown around the skeleton (metaballs)
  * Head: the trailer face (egg head, bulging tired eyes, droopy lids, dark
    bags, orange nose, thick brows, thin mouth, ears) — same for everybody
  * Hands: chunky cartoon mitts with curled fingers + thumb
  * Clothing layers: suit jacket (lapels, pockets, buttons, collar), dress
    shirt V + cuffs, tie (normal/long), cop shirt + duty belt, hoodie, tee,
    dress shirt, slacks, dress shoes, sneakers
  * Hair: slick, swept, swoop, short, buzz, messy, afro, long, bald
  * Beards: mustache, goatee, full, stubble
  * Glasses: shades, specs.  Hats: cop, headset, headband, beanie, cap
  * Accessories: watch, ring, gold chain

Colors are NOT baked in: each mesh has a role material (Skin, Suit, Shirt, Tie,
Pants, Shoes, Hair, Hat, Metal, Gold, Fixed) and vertex colors that multiply
the role color (e.g. lapels 0.78x, nose orange-tinted skin). Godot picks the
actual colors per player, which is what makes the tailor menu possible.

Convention: character faces +Y in Blender (= -Z, Godot forward). Right = +X.
"""
import math
import os
import random

import bpy  # noqa: I001  (bpy must be imported before bmesh/mathutils)
import bmesh
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "characters", "character_kit.glb")
K = 0.565           # metaball: visible surface radius = K * element radius (stiffness 2, threshold .6)
RES = 0.011         # metaball polygonization size (m)
random.seed(7)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


# ----------------------------------------------------------------------------- skeleton

S = {}  # joint positions
def J(name, x, y, z):
    S[name] = Vector((x, y, z))

J("hips", 0, 0, 0.93)
J("spine", 0, 0, 1.06)
J("chest", 0, 0, 1.28)
J("neck", 0, -0.005, 1.5)
J("head", 0, 0.0, 1.62)
J("head_top", 0, 0.0, 2.0)
A_POSE = math.radians(20)   # arms angled out at rest -> clean skinning; the game lowers them
for sd, s in (("R", 1), ("L", -1)):
    _dir = Vector((s * math.sin(A_POSE), 0, -math.cos(A_POSE)))
    J("shoulder_" + sd, s * 0.19, -0.005, 1.465)
    S["elbow_" + sd] = S["shoulder_" + sd] + _dir * 0.29 + Vector((0, -0.01, 0))
    S["wrist_" + sd] = S["elbow_" + sd] + _dir * 0.27 + Vector((0, 0.01, 0))
    S["hand_end_" + sd] = S["wrist_" + sd] + _dir * 0.14 + Vector((0, 0.01, 0))
    J("hip_" + sd, s * 0.098, 0, 0.93)
    J("knee_" + sd, s * 0.1, 0.012, 0.5)
    J("ankle_" + sd, s * 0.1, 0, 0.085)
    J("toe_" + sd, s * 0.1, 0.14, 0.03)

BONES = [  # name, head, tail, parent
    ("Hips", "hips", "spine", None),
    ("Spine", "spine", "chest", "Hips"),
    ("Chest", "chest", "neck", "Spine"),
    ("Neck", "neck", "head", "Chest"),
    ("Head", "head", "head_top", "Neck"),
]
for sd in ("R", "L"):
    BONES += [
        ("UpperArm_" + sd, "shoulder_" + sd, "elbow_" + sd, "Chest"),
        ("Forearm_" + sd, "elbow_" + sd, "wrist_" + sd, "UpperArm_" + sd),
        ("Hand_" + sd, "wrist_" + sd, "hand_end_" + sd, "Forearm_" + sd),
        ("Thigh_" + sd, "hip_" + sd, "knee_" + sd, "Hips"),
        ("Shin_" + sd, "knee_" + sd, "ankle_" + sd, "Thigh_" + sd),
        ("Foot_" + sd, "ankle_" + sd, "toe_" + sd, "Shin_" + sd),
    ]
DEFORM_SEGS = {b[0]: (S[b[1]], S[b[2]]) for b in BONES}

# face features (filled after the head exists)
FACE = {}


# ----------------------------------------------------------------------------- mesh helpers

class Blob:
    """Metaball union → mesh. Elements blend smoothly, like clay."""

    def __init__(self, name, res=RES):
        self.mb = bpy.data.metaballs.new("MB_" + name)
        self.mb.resolution = res
        self.mb.render_resolution = res
        self.mb.threshold = 0.6
        self.ob = link(bpy.data.objects.new("MB_" + name, self.mb))
        self.name = name

    def ball(self, c, r, neg=False, stiff=2.0):
        e = self.mb.elements.new()
        e.type = "BALL"
        e.co = Vector(c)
        e.radius = r / K
        e.stiffness = stiff
        e.use_negative = neg
        return e

    def ellipsoid(self, c, radii, rot=None, neg=False, stiff=2.0):
        m = max(radii)
        e = self.mb.elements.new()
        e.type = "ELLIPSOID"
        e.co = Vector(c)
        e.radius = m / K
        e.size_x, e.size_y, e.size_z = radii[0] / m, radii[1] / m, radii[2] / m
        e.stiffness = stiff
        e.use_negative = neg
        if rot is not None:
            e.rotation = rot
        return e

    def capsule(self, a, b, r, neg=False, stiff=2.0):
        a, b = Vector(a), Vector(b)
        d = b - a
        e = self.mb.elements.new()
        e.type = "CAPSULE"
        e.co = (a + b) / 2
        e.radius = r / K
        e.size_x = max(d.length / 2, 1e-4)
        e.rotation = Vector((1, 0, 0)).rotation_difference(d.normalized())
        e.stiffness = stiff
        e.use_negative = neg
        return e

    def chain(self, pts, radii):
        for i in range(len(pts) - 1):
            self.capsule(pts[i], pts[i + 1], (radii[i] + radii[i + 1]) / 2)

    def to_object(self, name=None, decimate=1.0, smooth_iter=1):
        dg = bpy.context.evaluated_depsgraph_get()
        ev = self.ob.evaluated_get(dg)
        me = bpy.data.meshes.new_from_object(ev)
        bpy.data.objects.remove(self.ob)
        bpy.data.metaballs.remove(self.mb)
        ob = link(bpy.data.objects.new(name or self.name, me))
        if smooth_iter:
            add_mod(ob, "SMOOTH", factor=0.5, iterations=smooth_iter)
        if decimate < 1.0:
            add_mod(ob, "DECIMATE", ratio=decimate)
        apply_mods(ob)
        shade_smooth(ob)
        return ob


def add_mod(ob, kind, **kw):
    m = ob.modifiers.new(kind.lower(), kind)
    for k, v in kw.items():
        setattr(m, k, v)
    return m


def apply_mods(ob):
    if not ob.modifiers:
        return
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    bpy.data.meshes.remove(old)


def shade_smooth(ob):
    for p in ob.data.polygons:
        p.use_smooth = True


def bm_to_object(bm, name):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    shade_smooth(ob)
    return ob


def set_color(ob, rgb):
    me = ob.data
    if "Col" not in me.color_attributes:
        me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    attr = me.color_attributes["Col"]
    for i in range(len(me.vertices)):
        attr.data[i].color = (rgb[0], rgb[1], rgb[2], 1.0)
    me.color_attributes.active_color = attr


def join(obs, name):
    obs = [o for o in obs if o is not None]
    for o in obs:
        if "Col" not in o.data.color_attributes:
            set_color(o, (1, 1, 1))
    ctx = bpy.context
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in obs:
        o.select_set(True)
    ctx.view_layer.objects.active = obs[0]
    bpy.ops.object.join()
    ob = ctx.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    ob.data.color_attributes.active_color = ob.data.color_attributes["Col"]
    return ob


def uv_sphere(center, radii, segs=48, rings=32, name="sph"):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * radii[0], v.co.y * radii[1], v.co.z * radii[2])) + Vector(center)
    return bm_to_object(bm, name)


def shell_from_head(head, name, keep, offset, thickness, segs=64, rings=48, subsurf=1, center=None):
    """Clean shell hugging the head (hair caps, beards): a UV sphere shrink-
    wrapped onto the head, trimmed by keep(dir) → bool, then thickened."""
    c = Vector(center) if center else FACE["head_c"]
    ob = uv_sphere(c, (0.3, 0.3, 0.33), segs, rings, name)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    dead = [f for f in bm.faces if not keep((f.calc_center_median() - c).normalized())]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()
    add_mod(ob, "SHRINKWRAP", target=head, wrap_method="NEAREST_SURFACEPOINT", offset=offset)
    apply_mods(ob)
    add_mod(ob, "SMOOTH", factor=0.6, iterations=4)
    add_mod(ob, "SOLIDIFY", thickness=thickness, offset=1.0, use_even_offset=True, use_rim=True)
    if subsurf:
        add_mod(ob, "SUBSURF", levels=subsurf, render_levels=subsurf)
    apply_mods(ob)
    shade_smooth(ob)
    return ob


# ----------------------------------------------------------------------------- body

def build_body():
    b = Blob("Body")
    b.ellipsoid((0, -0.005, 0.95), (0.15, 0.105, 0.1))              # pelvis
    b.ellipsoid((0, 0, 1.1), (0.14, 0.095, 0.13))                   # waist
    b.ellipsoid((0, 0.005, 1.33), (0.175, 0.11, 0.15))              # chest
    for s in (1, -1):
        b.ball((s * 0.17, -0.005, 1.44), 0.065)                    # deltoid
        b.chain([S["shoulder_R" if s > 0 else "shoulder_L"], S["elbow_R" if s > 0 else "elbow_L"],
                 S["wrist_R" if s > 0 else "wrist_L"]], [0.05, 0.043, 0.036])
        sd = "R" if s > 0 else "L"
        b.chain([S["hip_" + sd] + Vector((0, 0, 0.02)), S["knee_" + sd], S["ankle_" + sd]], [0.078, 0.058, 0.045])
        b.ellipsoid(S["ankle_" + sd] + Vector((0, 0.05, -0.04)), (0.04, 0.09, 0.035))
    b.capsule((0, -0.01, 1.45), (0, -0.005, 1.66), 0.055)            # neck
    return b.to_object("Body", decimate=0.35)


# ----------------------------------------------------------------------------- head + face

def build_head():
    c = Vector((0, 0.0, 1.79))
    FACE["head_c"] = c
    h = Blob("Head", res=0.008)
    h.ellipsoid(c, (0.152, 0.158, 0.19))                              # skull/egg
    h.ellipsoid(c + Vector((0, 0.022, -0.1)), (0.122, 0.13, 0.1))     # jaw/cheeks
    h.ellipsoid(c + Vector((0, 0.035, 0.06)), (0.13, 0.12, 0.1))      # forehead
    for s in (1, -1):
        h.ellipsoid(c + Vector((s * 0.15, -0.005, 0.0)), (0.022, 0.034, 0.052))   # ears
        h.ellipsoid(c + Vector((s * 0.158, -0.004, 0.0)), (0.012, 0.022, 0.035), neg=True)
    h.capsule(c + Vector((0, -0.01, -0.2)), c + Vector((0, -0.01, -0.1)), 0.058)  # neck top
    head = h.to_object("Head_base", decimate=0.45)
    bvh = BVHTree.FromObject(head, bpy.context.evaluated_depsgraph_get())

    def surf(x, z, back=False):
        """Point on the face surface at (x, z), shooting from the front."""
        o = Vector((x, 1.0, z))
        hit = bvh.ray_cast(o, Vector((0, -1, 0)))
        return hit[0] if hit[0] else Vector((x, 0.15, z))

    FACE["surf"] = surf
    eye_z = c.z + 0.03
    ex = 0.058
    parts = [head]
    # nose (orange-tinted skin)
    n = Blob("Nose", res=0.004)
    np_ = surf(0, c.z - 0.025)
    n.ellipsoid(np_ + Vector((0, 0.012, 0.0)), (0.02, 0.028, 0.03))
    n.ellipsoid(np_ + Vector((0, 0.024, -0.018)), (0.017, 0.02, 0.016))
    nose = n.to_object("Nose")
    set_color(nose, (1.0, 0.72, 0.6))
    parts.append(nose)
    # dark bags around/below the eyes (the trailer's tired look)
    for s in (1, -1):
        bp = surf(s * ex, eye_z - 0.03)
        bg = Blob("Bag", res=0.004)
        bg.ellipsoid(bp + Vector((0, -0.006, 0.0)), (0.05, 0.014, 0.03))
        bag = bg.to_object("Bag")
        set_color(bag, (0.86, 0.72, 0.68))
        parts.append(bag)
    head = join(parts, "Skull")
    # eyes: big bulging whites + small pupils (fixed colors)
    face_parts = []
    FACE["eyes"] = []
    for s in (1, -1):
        ep = surf(s * ex, eye_z)
        ec = ep + Vector((0, -0.008, 0))
        FACE["eyes"].append(ec)
        w = uv_sphere(ec, (0.05, 0.036, 0.046), 24, 16, "EyeWhite")
        set_color(w, (0.97, 0.97, 0.95))
        p = uv_sphere(ec + Vector((-s * 0.006, 0.033, -0.004)), (0.015, 0.008, 0.016), 16, 10, "Pupil")
        set_color(p, (0.03, 0.03, 0.035))
        face_parts += [w, p]
    face = join(face_parts, "Eyes")
    # mouth (on the Jaw bone so it can open when talking)
    mp = surf(0, c.z - 0.105)
    FACE["mouth"] = mp
    m = uv_sphere(mp + Vector((0, 0.002, 0)), (0.032, 0.008, 0.0065), 20, 10, "Mouth")
    set_color(m, (0.18, 0.05, 0.05))
    # eyelids: upper half-shells over each eye (on Lid bones → blink/droop)
    lids = []
    for i, s in enumerate((1, -1)):
        ec = FACE["eyes"][i]
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=16, radius=1.0)
        dead = [f for f in bm.faces if f.calc_center_median().z < -0.05]
        bmesh.ops.delete(bm, geom=dead, context="FACES")
        for v in bm.verts:
            v.co = Vector((v.co.x * 0.056, v.co.y * 0.041, v.co.z * 0.051))
        # droop: tilt the shell forward so it covers the top ~third of the eye
        rot = Matrix.Rotation(math.radians(38), 3, "X")
        for v in bm.verts:
            v.co = rot @ v.co + ec
        lid = bm_to_object(bm, "Lid")
        add_mod(lid, "SOLIDIFY", thickness=0.004, offset=1.0)
        apply_mods(lid)
        set_color(lid, (0.93, 0.93, 0.93))
        lid["bone"] = "Lid_" + ("R" if s > 0 else "L")
        lids.append(lid)
    # brows (hair color)
    brows = []
    for s in (1, -1):
        bp = surf(s * 0.062, eye_z + 0.075)
        br = Blob("Brow", res=0.004)
        br.capsule(bp + Vector((-s * 0.03, 0.004, -0.004)), bp + Vector((s * 0.028, 0.0, 0.008)), 0.014)
        brows.append(br.to_object("Brow"))
    return head, face, m, lids, join(brows, "Brows")


def build_hands():
    out = []
    for sd, s in (("R", 1), ("L", -1)):
        w = S["wrist_" + sd]
        R = Matrix.Rotation(-s * A_POSE, 3, "Y")

        def T(p):
            return w + R @ Vector(p)

        hb = Blob("Hand_" + sd, res=0.006)
        palm = Vector((s * 0.004, 0.006, -0.06))
        hb.ellipsoid(T(palm), (0.03, 0.048, 0.052), rot=R.to_quaternion())
        for dy in (-0.028, -0.009, 0.01, 0.028):
            L = 0.056 - abs(dy) * 0.4
            a = palm + Vector((s * 0.002, dy, -0.035))
            b = a + Vector((-s * 0.02, 0.004, -L))          # fingers curl in toward the thigh
            hb.capsule(T(a), T(b), 0.0145)
        t0 = Vector((-s * 0.012, 0.04, -0.035))
        hb.capsule(T(t0), T(t0 + Vector((-s * 0.02, 0.022, -0.04))), 0.015)   # thumb
        hand = hb.to_object("Hand_" + sd, decimate=0.5)
        out.append(hand)
    return join(out, "Hands")


# ----------------------------------------------------------------------------- clothes

def build_jacket():
    b = Blob("Jacket")
    b.ellipsoid((0, -0.005, 0.9), (0.18, 0.13, 0.12))               # skirt (hem ~0.79)
    b.ellipsoid((0, 0, 1.08), (0.17, 0.122, 0.16))
    b.ellipsoid((0, 0.004, 1.32), (0.2, 0.135, 0.17))                # chest
    for s in (1, -1):
        sd = "R" if s > 0 else "L"
        b.ellipsoid((s * 0.175, -0.005, 1.435), (0.085, 0.09, 0.065))  # squared shoulder pads
        e, wr = S["elbow_" + sd], S["wrist_" + sd]
        cuff = wr + (e - wr).normalized() * 0.035
        b.chain([S["shoulder_" + sd], e, cuff], [0.066, 0.058, 0.052])
    for a in range(-4, 5):                                           # collar hugging the back of the neck
        ang = math.radians(a * 22)
        b.ball((math.sin(ang) * 0.075, -math.cos(ang) * 0.06 - 0.005, 1.535), 0.032)
    jacket = b.to_object("Jacket_shell", decimate=0.4)
    bvh = BVHTree.FromObject(jacket, bpy.context.evaluated_depsgraph_get())

    def front(x, z):
        hit = bvh.ray_cast(Vector((x, 1.0, z)), Vector((0, -1, 0)))
        return hit[0] if hit[0] else Vector((x, 0.14, z))

    FACE["jacket_front"] = front
    parts = [jacket]
    # lapels: clean darker ribbons along the V, slightly raised
    for sd in (1, -1):
        bm = bmesh.new()
        rows = 14
        prev = None
        for r in range(rows + 1):
            t = r / rows
            inner = Vector((sd * 0.07, 0, 1.495)).lerp(Vector((0, 0, 1.19)), t)
            wdt = (0.045 if t > 0.14 else 0.03) * (1.0 - t) ** 0.7
            outer = inner + Vector((sd * wdt, 0, 0.012 * (1 - t)))
            a = front(inner.x, inner.z) + Vector((0, 0.005, 0))
            b_ = front(outer.x, outer.z) + Vector((0, 0.004, 0))
            va, vb = bm.verts.new(a), bm.verts.new(b_)
            if prev:
                f = (prev[0], prev[1], vb, va) if sd > 0 else (prev[1], prev[0], va, vb)
                bm.faces.new(f)
            prev = (va, vb)
        lap = bm_to_object(bm, "Lapel")
        add_mod(lap, "SOLIDIFY", thickness=0.005, offset=1.0)
        add_mod(lap, "SUBSURF", levels=1)
        apply_mods(lap)
        set_color(lap, (0.62, 0.62, 0.66))
        parts.append(lap)
        pk = Blob("Pocket", res=0.005)
        pp = front(sd * 0.11, 0.98)
        pk.ellipsoid(pp + Vector((0, 0.003, 0)), (0.055, 0.008, 0.012))
        pkt = pk.to_object("Pocket")
        set_color(pkt, (0.7, 0.7, 0.72))
        parts.append(pkt)
    for z in (1.16, 1.07):
        bp = front(0.0, z)
        bt = uv_sphere(bp + Vector((0, 0.004, 0)), (0.011, 0.006, 0.011), 12, 8, "Button")
        set_color(bt, (0.25, 0.25, 0.27))
        parts.append(bt)
    return join(parts, "Jacket")


def v_shirt(front, name, top_w=0.074, bottom_z=1.19):
    """White shirt V + collar points, following the garment surface."""
    bm = bmesh.new()
    rows = 10
    for r in range(rows + 1):
        t = r / rows
        z = 1.5 - (1.5 - bottom_z) * t
        half = top_w * (1 - t) + 0.002
        for x in (-half, 0.0, half):
            p = front(x, z)
            bm.verts.new(p + Vector((0, 0.0035, 0)))
    bm.verts.ensure_lookup_table()
    for r in range(rows):
        for c in range(2):
            a = r * 3 + c
            bm.faces.new((bm.verts[a], bm.verts[a + 1], bm.verts[a + 4], bm.verts[a + 3]))
    ob = bm_to_object(bm, name)
    add_mod(ob, "SOLIDIFY", thickness=0.004, offset=1.0)
    add_mod(ob, "SUBSURF", levels=1)
    apply_mods(ob)
    # collar points
    parts = [ob]
    for s in (1, -1):
        cp = Blob("Collar", res=0.004)
        p = front(s * 0.04, 1.49) + Vector((0, 0.01, 0))
        cp.ellipsoid(p, (0.028, 0.008, 0.022), rot=Quaternion((0, 1, 0), s * 0.5))
        parts.append(cp.to_object("CollarPt"))
    return join(parts, name)


def build_cuffs(name="Cuffs"):
    parts = []
    for sd in ("R", "L"):
        e, w = S["elbow_" + sd], S["wrist_" + sd]
        d = (w - e).normalized()
        cb = Blob("Cuff", res=0.005)
        cb.capsule(w - d * 0.045, w - d * 0.015, 0.042)
        parts.append(cb.to_object("Cuff"))
    return join(parts, name)


def build_tie(front, long_tie=False):
    tb = Blob("Tie", res=0.005)
    knot = front(0, 1.475) + Vector((0, 0.022, 0))
    tb.ellipsoid(knot, (0.022, 0.014, 0.02))
    end_z = 1.08 if long_tie else 1.2
    n = 26
    for i in range(n + 1):
        t = i / n
        z = 1.455 - (1.455 - end_z) * t
        p = front(0, z) + Vector((0, 0.016, 0))
        w = 0.012 + 0.022 * t
        tb.ellipsoid(p, (w, 0.006, 0.024))
    tip = front(0, end_z - 0.02) + Vector((0, 0.016, 0))
    tb.ellipsoid(tip, (0.018, 0.006, 0.018))
    return tb.to_object("Tie_long" if long_tie else "Tie")


def build_shirt_top(name, sleeve="long", hem=0.93, bulk=1.0):
    """Tucked shirt / cop shirt / tee / hoodie body."""
    b = Blob(name)
    b.ellipsoid((0, -0.005, hem + 0.06), (0.16 * bulk, 0.115 * bulk, 0.1))
    b.ellipsoid((0, 0, 1.1), (0.152 * bulk, 0.108 * bulk, 0.15))
    b.ellipsoid((0, 0.004, 1.33), (0.188 * bulk, 0.124 * bulk, 0.16))
    for s in (1, -1):
        sd = "R" if s > 0 else "L"
        b.ball((s * 0.172, -0.005, 1.44), 0.075 * bulk)
        e, wr = S["elbow_" + sd], S["wrist_" + sd]
        if sleeve == "long":
            end = wr + (e - wr).normalized() * 0.03
            b.chain([S["shoulder_" + sd], e, end], [0.06 * bulk, 0.052 * bulk, 0.046 * bulk])
        else:
            mid = S["shoulder_" + sd].lerp(e, 0.55)
            b.capsule(S["shoulder_" + sd], mid, 0.062)
    return b.to_object(name, decimate=0.4)


def build_cop():
    shirt = build_shirt_top("CopShirt_shell")
    bvh = BVHTree.FromObject(shirt, bpy.context.evaluated_depsgraph_get())

    def front(x, z):
        hit = bvh.ray_cast(Vector((x, 1.0, z)), Vector((0, -1, 0)))
        return hit[0] if hit[0] else Vector((x, 0.13, z))

    parts = [shirt]
    for s in (1, -1):
        fl = Blob("Flap", res=0.005)
        fl.ellipsoid(front(s * 0.085, 1.35) + Vector((0, 0.003, 0)), (0.045, 0.008, 0.02))
        f = fl.to_object("Flap")
        set_color(f, (0.72, 0.72, 0.76))
        parts.append(f)
        ep = Blob("Epaulette", res=0.005)
        ep.capsule((s * 0.08, -0.005, 1.5), (s * 0.19, -0.005, 1.49), 0.018)
        e = ep.to_object("Epaulette")
        set_color(e, (0.72, 0.72, 0.76))
        parts.append(e)
    pl = Blob("Placket", res=0.005)
    pl.capsule(front(0, 1.47) + Vector((0, 0.002, 0)), front(0, 1.0) + Vector((0, 0.002, 0)), 0.012)
    p = pl.to_object("Placket")
    set_color(p, (0.8, 0.8, 0.84))
    parts.append(p)
    shirt = join(parts, "Top_cop")
    shirt_front = front
    # duty belt + badge (fixed colors)
    gear = []
    bb = Blob("Belt", res=0.006)
    for a in range(24):
        ang = a / 24 * math.tau
        bb.ellipsoid((math.sin(ang) * 0.158, math.cos(ang) * 0.118 - 0.005, 0.965), (0.03, 0.03, 0.028))
    belt = bb.to_object("Belt")
    set_color(belt, (0.06, 0.06, 0.07))
    gear.append(belt)
    bk = uv_sphere(shirt_front(0, 0.965) + Vector((0, 0.018, 0)), (0.028, 0.008, 0.02), 12, 8, "Buckle")
    set_color(bk, (0.75, 0.77, 0.8))
    gear.append(bk)
    bpt = shirt_front(0.085, 1.4) + Vector((0, 0.006, 0))
    badge = uv_sphere(bpt, (0.024, 0.006, 0.03), 20, 12, "Badge")   # shield
    set_color(badge, (1.0, 0.78, 0.22))
    gear.append(badge)
    hol = uv_sphere((0.19, -0.02, 0.9), (0.03, 0.05, 0.07), 12, 8, "Holster")
    set_color(hol, (0.06, 0.06, 0.07))
    gear.append(hol)
    return shirt, join(gear, "Gear_cop")


def build_hoodie():
    h = build_shirt_top("Hoodie_shell", "long", hem=0.86, bulk=1.12)
    parts = [h]
    hb = Blob("Hood", res=0.008)
    for a in range(-5, 6):
        ang = math.radians(a * 16)
        hb.ball((math.sin(ang) * 0.12, -math.cos(ang) * 0.08 - 0.03, 1.53 + abs(a) * -0.004), 0.055)
    hood = hb.to_object("Hood")
    set_color(hood, (0.9, 0.9, 0.9))
    parts.append(hood)
    pk = Blob("Kanga", res=0.006)
    pk.ellipsoid((0, 0.135, 1.03), (0.12, 0.012, 0.07))
    kp = pk.to_object("Kanga")
    set_color(kp, (0.85, 0.85, 0.85))
    parts.append(kp)
    for s in (1, -1):
        st = uv_sphere((s * 0.035, 0.13, 1.36), (0.005, 0.005, 0.07), 8, 8, "String")
        set_color(st, (0.95, 0.95, 0.95))
        parts.append(st)
    return join(parts, "Top_hoodie")


def build_tee():
    t = build_shirt_top("Tee_shell", "short")
    cb = Blob("TeeCollar", res=0.005)
    for a in range(20):
        ang = a / 20 * math.tau
        cb.ball((math.sin(ang) * 0.07, math.cos(ang) * 0.06 + 0.005, 1.5 + max(0, math.cos(ang)) * -0.02), 0.014)
    col = cb.to_object("TeeCollar")
    set_color(col, (0.8, 0.8, 0.82))
    return join([t, col], "Top_tee")


def build_dress_shirt():
    t = build_shirt_top("DressShirt_shell", "long")
    bvh = BVHTree.FromObject(t, bpy.context.evaluated_depsgraph_get())

    def front(x, z):
        hit = bvh.ray_cast(Vector((x, 1.0, z)), Vector((0, -1, 0)))
        return hit[0] if hit[0] else Vector((x, 0.13, z))

    parts = [t]
    for s in (1, -1):
        cp = Blob("Collar", res=0.004)
        cp.ellipsoid(front(s * 0.035, 1.49) + Vector((0, 0.012, 0)), (0.03, 0.008, 0.022), rot=Quaternion((0, 1, 0), s * 0.5))
        parts.append(cp.to_object("CollarPt"))
    pl = Blob("Placket", res=0.005)
    pl.capsule(front(0, 1.45) + Vector((0, 0.002, 0)), front(0, 0.98) + Vector((0, 0.002, 0)), 0.01)
    p = pl.to_object("Placket")
    set_color(p, (0.9, 0.9, 0.9))
    parts.append(p)
    FACE["shirt_front"] = front
    return join(parts, "Top_shirt")


def build_pants():
    b = Blob("Pants")
    b.ellipsoid((0, -0.005, 0.96), (0.168, 0.122, 0.11))
    for sd in ("R", "L"):
        b.chain([S["hip_" + sd] + Vector((0, 0, 0.02)), S["knee_" + sd], S["ankle_" + sd] + Vector((0, 0, 0.015))],
                [0.1, 0.078, 0.068])
    return b.to_object("Pants", decimate=0.4)


def build_shoes(kind):
    out = []
    for sd in ("R", "L"):
        a = S["ankle_" + sd]
        b = Blob("Shoe", res=0.006)
        if kind == "dress":
            b.ellipsoid(a + Vector((0, 0.045, -0.045)), (0.05, 0.12, 0.04))
            b.ellipsoid(a + Vector((0, -0.01, -0.035)), (0.045, 0.06, 0.05))
            b.ellipsoid(a + Vector((0, 0.12, -0.055)), (0.042, 0.05, 0.03))
        else:
            b.ellipsoid(a + Vector((0, 0.045, -0.04)), (0.058, 0.125, 0.05))
            b.ellipsoid(a + Vector((0, -0.01, -0.02)), (0.05, 0.065, 0.065))
        shoe = b.to_object("Shoe")
        parts = [shoe]
        sole = Blob("Sole", res=0.006)
        sole.ellipsoid(a + Vector((0, 0.045, -0.078)), (0.056 if kind == "dress" else 0.064, 0.14, 0.012))
        so = sole.to_object("Sole")
        if kind == "dress":
            set_color(so, (0.35, 0.35, 0.35))
            parts.append(so)
        else:
            set_color(so, (0.95, 0.95, 0.93))
            SOLES.append(so)
        out.append(join(parts, "Shoe_" + sd))
    return join(out, "Shoes_" + kind)


SOLES = []


# ----------------------------------------------------------------------------- hair

def _az(d):
    """azimuth around the head: 0 = front (+Y), ±pi = back."""
    return math.atan2(d.x, d.y)


def hairline(d, front=0.82, side=0.2, back=-0.6):
    """Is direction d (unit vector from the head center) inside the hair area?"""
    return hair_margin(d, front, side, back) > 0.0


def hair_margin(d, front=0.82, side=0.2, back=-0.6):
    """How far (in unit-direction z) d is inside the hairline; <0 = outside."""
    a = abs(_az(d))
    t = a / math.pi                       # 0 front -> 1 back
    if t < 0.5:
        lim = front + (side - front) * (t / 0.5) ** 0.8
    else:
        lim = side + (back - side) * ((t - 0.5) / 0.5) ** 1.3
    if 0.36 < t < 0.64 and d.z < 0.3:     # leave the ears uncovered
        lim = max(lim, 0.3)
    return d.z - lim


def skull_points(head, keep, step=1):
    """Surface points + normals of the skull inside a region."""
    me = head.data
    c = FACE["head_c"]
    pts = []
    for i, v in enumerate(me.vertices):
        if i % step:
            continue
        p = head.matrix_world @ v.co
        d = (p - c).normalized()
        if keep(d) and v.normal.length > 0.5:
            pts.append((p, (head.matrix_world.to_3x3() @ v.normal).normalized()))
    return pts


OVERLAP = 0.009   # measured: overlapping balls thicken the mass by ~1 cm


def hair_mass(b, head, keep, thick, r=0.022, step=2, lift=None, line=(0.82, 0.2, -0.6), edge=True):
    """Metaball balls along the skull surface -> a smooth hair mass whose
    outer surface sits ~`thick` above the skin (lift(d) can add volume).
    Fuller on top, tight on the sides, feathered at the hairline."""
    for p, n in skull_points(head, keep, step):
        d = (p - FACE["head_c"]).normalized()
        taper = 0.3 + 0.7 * max(0.0, min(1.0, d.z * 1.25))
        if edge:
            taper *= max(0.25, min(1.0, hair_margin(d, *line) / 0.14))
        t = thick * taper + (lift(d) if lift else 0.0)
        b.ball(p + n * (t - r - OVERLAP), r)


def build_hair(head, style):
    c = FACE["head_c"]
    b = Blob("Hair_" + style, res=0.0065)
    if style == "bald":
        hair_mass(b, head, lambda d: hairline(d) and d.z < 0.35 and abs(_az(d)) > 1.1, 0.01, 0.016, edge=False)
        return b.to_object("Hair_bald", smooth_iter=2)
    if style == "buzz":
        hair_mass(b, head, lambda d: hairline(d, front=0.84), 0.013, 0.016, step=1, line=(0.84, 0.2, -0.6), edge=False)
        return b.to_object("Hair_buzz", smooth_iter=2)
    if style == "short":
        hair_mass(b, head, lambda d: hairline(d, front=0.83), 0.018, 0.02, line=(0.83, 0.2, -0.6),
                  lift=lambda d: 0.008 * max(0.0, d.z))
        return b.to_object("Hair_short", smooth_iter=2)
    if style == "slick":
        # slicked back with a pompadour ridge along the front hairline
        hair_mass(b, head, hairline, 0.02, 0.022,
                  lift=lambda d: 0.03 * max(0.0, d.y) * max(0.0, d.z - 0.3) * 3.0)
        b.ellipsoid(c + Vector((0, 0.1, 0.165)), (0.1, 0.06, 0.05), rot=Quaternion((1, 0, 0), -0.5))
        for sd in (1, -1):
            b.capsule(c + Vector((sd * 0.148, 0.03, 0.06)), c + Vector((sd * 0.15, 0.045, 0.0)), 0.012)
        return b.to_object("Hair_slick", smooth_iter=2)
    if style == "swept":
        hair_mass(b, head, hairline, 0.02, 0.022,
                  lift=lambda d: 0.03 * max(0.0, d.y + 0.2) * max(0.0, d.z - 0.3) * (1.4 + d.x))
        b.ellipsoid(c + Vector((0.03, 0.1, 0.16)), (0.11, 0.06, 0.045), rot=Quaternion((0, 1, 0), -0.3) @ Quaternion((1, 0, 0), -0.4))
        return b.to_object("Hair_swept", smooth_iter=2)
    if style == "swoop":
        # the TRAMP: big combed-over swoop
        hair_mass(b, head, lambda d: hairline(d, front=0.78, side=0.1), 0.034, 0.026, line=(0.78, 0.1, -0.6),
                  lift=lambda d: 0.02 * max(0.0, d.z))
        b.ellipsoid(c + Vector((-0.015, 0.13, 0.16)), (0.17, 0.085, 0.065), rot=Quaternion((1, 0, 0), -0.6) @ Quaternion((0, 1, 0), 0.15))
        b.ellipsoid(c + Vector((0.05, 0.06, 0.215)), (0.13, 0.13, 0.05))
        b.ellipsoid(c + Vector((-0.12, 0.1, 0.12)), (0.06, 0.07, 0.05))
        for sd in (1, -1):
            b.ellipsoid(c + Vector((sd * 0.155, 0.0, 0.07)), (0.03, 0.08, 0.06))
        return b.to_object("Hair_swoop", smooth_iter=2)
    if style == "messy":
        hair_mass(b, head, hairline, 0.022, 0.022)
        for i in range(26):
            th = random.uniform(0, math.tau)
            ph = random.uniform(0.0, 0.95)
            d = Vector((math.cos(th) * math.sin(ph), math.sin(th) * math.sin(ph), math.cos(ph)))
            if hairline(d):
                b.ball(c + Vector((d.x * 0.16, d.y * 0.165, d.z * 0.2)) + d * 0.02, random.uniform(0.028, 0.04))
        return b.to_object("Hair_messy", smooth_iter=2)
    if style == "afro":
        b.mb.resolution = 0.009
        hair_mass(b, head, lambda d: hairline(d, front=0.66), 0.03, 0.03, line=(0.66, 0.2, -0.6))
        b.ellipsoid(c + Vector((0, -0.03, 0.08)), (0.215, 0.205, 0.2))
        for i in range(18):
            th = i / 18 * math.tau
            for ph in (0.55, 1.05):
                d = Vector((math.cos(th) * math.sin(ph), math.sin(th) * math.sin(ph), math.cos(ph)))
                if d.y > 0.45 and d.z < 0.75:
                    continue
                b.ball(c + Vector((d.x * 0.2, d.y * 0.19 - 0.03, d.z * 0.19 + 0.08)), 0.055)
        b.ellipsoid(c + Vector((0, 0.2, -0.03)), (0.17, 0.09, 0.2), neg=True)   # keep the face open
        return b.to_object("Hair_afro", smooth_iter=2)
    if style == "long":
        hair_mass(b, head, lambda d: hairline(d, front=0.66), 0.024, 0.022, line=(0.66, 0.2, -0.6))
        b.ellipsoid(c + Vector((0, -0.1, -0.11)), (0.15, 0.07, 0.19))
        for sd in (1, -1):
            b.ellipsoid(c + Vector((sd * 0.155, -0.04, -0.1)), (0.035, 0.08, 0.18))
        return b.to_object("Hair_long", smooth_iter=2)
    return None


def build_beard(head, style):
    c = FACE["head_c"]
    mp = FACE["mouth"]
    mz = (mp - c).z

    def jaw(d):
        return d.z < (mz / 0.19) + 0.12 and d.y > -0.3 and abs(_az(d)) < math.pi * 0.55

    b = Blob("Beard_" + style, res=0.005)
    if style in ("mustache", "goatee", "full"):
        for i in range(-4, 5):
            b.ball(mp + Vector((i * 0.0105, 0.011, 0.027 - abs(i) * 0.0035)), 0.016 if style != "mustache" else 0.018)
    if style == "goatee":
        b.ellipsoid(mp + Vector((0, 0.0, -0.05)), (0.04, 0.028, 0.035))
        for sd in (1, -1):
            b.capsule(mp + Vector((sd * 0.035, 0.004, 0.02)), mp + Vector((sd * 0.028, -0.004, -0.035)), 0.01)
    if style == "full":
        hair_mass(b, head, jaw, 0.02, 0.018, step=2, edge=False)
        b.ellipsoid(mp + Vector((0, -0.003, -0.012)), (0.036, 0.03, 0.012), neg=True)   # keep the mouth open
    if style == "stubble":
        hair_mass(b, head, jaw, 0.012, 0.01, step=1, edge=False)
    return b.to_object("Beard_" + style, smooth_iter=2)


# ----------------------------------------------------------------------------- glasses / hats / accessories

def build_glasses(kind):
    e0, e1 = FACE["eyes"]
    parts = []
    if kind == "shades":
        for e in (e0, e1):
            ln = Blob("Lens", res=0.004)
            ln.ellipsoid(e + Vector((0, 0.05, 0.002)), (0.056, 0.01, 0.04), stiff=3)
            parts.append(ln.to_object("Lens"))
        br = Blob("Bridge", res=0.004)
        br.capsule(e0 + Vector((-0.02, 0.05, 0.02)), e1 + Vector((0.02, 0.05, 0.02)), 0.008)
        for e, s in ((e0, 1), (e1, -1)):
            br.capsule(e + Vector((s * 0.05, 0.045, 0.015)), Vector((s * 0.158, -0.02, e.z + 0.02)), 0.006)
        parts.append(br.to_object("Frame"))
        ob = join(parts, "Glasses_shades")
        set_color(ob, (0.03, 0.03, 0.04))
        return ob
    for e in (e0, e1):
        bm = bmesh.new()
        bmesh.ops.create_circle(bm, cap_ends=False, segments=24, radius=0.047)
        for v in bm.verts:
            v.co = Vector((v.co.x, 0, v.co.y)) + e + Vector((0, 0.045, 0))
        rim = bm_to_object(bm, "Rim")
        add_mod(rim, "SKIN")
        for sv in rim.data.skin_vertices[0].data:
            sv.radius = (0.004, 0.004)
        add_mod(rim, "SUBSURF", levels=1)
        apply_mods(rim)
        parts.append(rim)
    br = Blob("Bridge", res=0.004)
    br.capsule(e0 + Vector((-0.045, 0.05, 0.01)), e1 + Vector((0.045, 0.05, 0.01)), 0.006)
    for e, s in ((e0, 1), (e1, -1)):
        br.capsule(e + Vector((s * 0.047, 0.045, 0.01)), Vector((s * 0.158, -0.02, e.z + 0.015)), 0.005)
    parts.append(br.to_object("Frame"))
    ob = join(parts, "Glasses_specs")
    set_color(ob, (0.08, 0.08, 0.1))
    return ob


def build_hat(head, kind):
    c = FACE["head_c"]
    top = c + Vector((0, 0, 0.19))
    if kind == "cop":
        parts = []
        b = Blob("Crown", res=0.007)
        b.ellipsoid(top + Vector((0, 0.01, 0.03)), (0.19, 0.2, 0.06), stiff=3)
        crown = b.to_object("Crown")
        set_color(crown, (0.12, 0.13, 0.25))
        parts.append(crown)
        band = uv_sphere(top + Vector((0, 0, -0.03)), (0.168, 0.175, 0.035), 32, 12, "Band")
        set_color(band, (0.04, 0.04, 0.05))
        parts.append(band)
        vb = Blob("Visor", res=0.005)
        vb.ellipsoid(top + Vector((0, 0.16, -0.06)), (0.12, 0.08, 0.012), rot=Quaternion((1, 0, 0), 0.3))
        vis = vb.to_object("Visor")
        set_color(vis, (0.03, 0.03, 0.04))
        parts.append(vis)
        bd = uv_sphere(top + Vector((0, 0.185, 0.02)), (0.028, 0.01, 0.032), 12, 8, "HatBadge")
        set_color(bd, (1.0, 0.78, 0.22))
        parts.append(bd)
        return join(parts, "Hat_cop")
    if kind == "headset":
        b = Blob("Headset", res=0.005)
        pts = [c + Vector((math.sin(a) * 0.17, -0.005, math.cos(a) * 0.215)) for a in [i * math.pi / 10 - math.pi / 2 for i in range(11)]]
        b.chain(pts, [0.014] * len(pts))
        for s in (1, -1):
            b.ellipsoid(c + Vector((s * 0.165, 0, -0.005)), (0.03, 0.055, 0.06))
        b.capsule(c + Vector((0.16, 0.03, -0.05)), c + Vector((0.07, 0.16, -0.11)), 0.008)
        b.ball(c + Vector((0.065, 0.165, -0.113)), 0.016)
        ob = b.to_object("Hat_headset")
        set_color(ob, (0.08, 0.08, 0.09))
        return ob
    if kind == "headband":
        return shell_from_head(head, "Hat_headband", lambda d: 0.28 < d.z < 0.45, 0.02, 0.02)
    if kind == "beanie":
        ob = shell_from_head(head, "Hat_beanie", lambda d: d.z > 0.28 - (0.0 if abs(_az(d)) < 2.3 else 0.1), 0.028, 0.03)
        b = Blob("Pom", res=0.006)
        b.ball(top + Vector((0, -0.01, 0.045)), 0.026)
        return join([ob, b.to_object("Pom")], "Hat_beanie")
    if kind == "cap":
        ob = shell_from_head(head, "capdome", lambda d: d.z > 0.3, 0.025, 0.02)
        b = Blob("Bill", res=0.005)
        b.ellipsoid(top + Vector((0, 0.19, -0.1)), (0.11, 0.1, 0.012), rot=Quaternion((1, 0, 0), 0.12))
        b.ball(top + Vector((0, 0.0, 0.035)), 0.018)
        return join([ob, b.to_object("Bill")], "Hat_cap")
    return None


def build_accessories():
    out = {}
    # watch on the left wrist
    w = S["wrist_L"]
    e = S["elbow_L"]
    d = (w - e).normalized()
    b = Blob("Watch", res=0.004)
    b.capsule(w - d * 0.012, w - d * 0.028, 0.042)
    band = b.to_object("Band")
    face = uv_sphere(w - d * 0.02 + Matrix.Rotation(A_POSE, 3, "Y") @ Vector((-0.043, 0, 0)), (0.008, 0.024, 0.024), 16, 10, "Face")
    set_color(face, (1.0, 1.0, 1.0))
    out["Acc_watch"] = join([band, face], "Acc_watch")
    # ring on the right hand
    h = S["wrist_R"]
    R = Matrix.Rotation(-A_POSE, 3, "Y")
    r = uv_sphere(h + R @ Vector((-0.012, 0.03, -0.1)), (0.018, 0.012, 0.01), 12, 8, "Acc_ring")
    out["Acc_ring"] = r
    # gold chain
    cb = Blob("Chain", res=0.005)
    for a in range(28):
        ang = a / 28 * math.tau
        y = math.cos(ang) * 0.085
        cb.ball((math.sin(ang) * 0.09, y + 0.01, 1.47 - max(0, y) * 0.9), 0.012)
    cb.ellipsoid((0, 0.125, 1.36), (0.025, 0.01, 0.03))
    out["Acc_chain"] = cb.to_object("Acc_chain")
    return out


# ----------------------------------------------------------------------------- skinning

LIMB = {
    "UpperArm_R": ["Chest", "UpperArm_R", "Forearm_R"], "Forearm_R": ["UpperArm_R", "Forearm_R", "Hand_R"],
    "Hand_R": ["Forearm_R", "Hand_R"], "UpperArm_L": ["Chest", "UpperArm_L", "Forearm_L"],
    "Forearm_L": ["UpperArm_L", "Forearm_L", "Hand_L"], "Hand_L": ["Forearm_L", "Hand_L"],
    "Thigh_R": ["Hips", "Thigh_R", "Shin_R"], "Shin_R": ["Thigh_R", "Shin_R", "Foot_R"], "Foot_R": ["Shin_R", "Foot_R"],
    "Thigh_L": ["Hips", "Thigh_L", "Shin_L"], "Shin_L": ["Thigh_L", "Shin_L", "Foot_L"], "Foot_L": ["Shin_L", "Foot_L"],
    "Hips": ["Hips", "Spine", "Thigh_R", "Thigh_L"], "Spine": ["Hips", "Spine", "Chest"],
    "Chest": ["Spine", "Chest", "Neck", "UpperArm_R", "UpperArm_L"], "Neck": ["Chest", "Neck", "Head"],
    "Head": ["Neck", "Head"],
}


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length, t


def skin_auto(ob):
    """Fallback: distance-to-bone weights (neighbour bones only)."""
    groups = {n: ob.vertex_groups.new(name=n) for n in DEFORM_SEGS}
    for v in ob.data.vertices:
        p = ob.matrix_world @ v.co
        d = {n: seg_dist(p, a, b)[0] for n, (a, b) in DEFORM_SEGS.items()}
        near = min(d, key=d.get)
        ws = {n: 1.0 / max(d[n], 0.01) ** 6 for n in LIMB[near]}
        best = sorted(ws.items(), key=lambda kv: -kv[1])[:3]
        tot = sum(w for _, w in best)
        for n, w in best:
            if w / tot > 0.01:
                groups[n].add([v.index], w / tot, "REPLACE")


def skin_heat(body, rig):
    """Blender's bone-heat automatic weights on the base body."""
    for b in rig.data.bones:
        b.use_deform = b.name in DEFORM_SEGS
    for o in bpy.context.scene.objects:
        o.select_set(False)
    body.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for b in rig.data.bones:
        b.use_deform = True
    ok = len(body.vertex_groups) > 5 and any(len([1 for g in v.groups if g.weight > 0]) for v in body.data.vertices)
    if not ok:
        print("heat weighting failed; falling back to distance weights")
        body.vertex_groups.clear()
        skin_auto(body)
    # parent_set already added modifier+parent; remove so attach() is uniform
    body.modifiers.clear()
    body.parent = None
    return ok


def skin_transfer(ob, body):
    """Clothing copies the weights of the nearest body surface point, so it
    deforms exactly like the skin underneath (no poke-through)."""
    bvh = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
    bme = body.data
    names = [g.name for g in body.vertex_groups]
    vw = []
    for v in bme.vertices:
        vw.append({names[g.group]: g.weight for g in v.groups if g.weight > 0.0})
    groups = {n: ob.vertex_groups.new(name=n) for n in names}
    for v in ob.data.vertices:
        p = ob.matrix_world @ v.co
        loc, nrm, fi, dist = bvh.find_nearest(p)
        if fi is None:
            continue
        poly = bme.polygons[fi]
        acc = {}
        vs = [bme.vertices[i].co for i in poly.vertices]
        wsum = 0.0
        for k, vi in enumerate(poly.vertices):
            wgt = 1.0 / max((vs[k] - loc).length, 1e-5)
            wsum += wgt
            for n, w in vw[vi].items():
                acc[n] = acc.get(n, 0.0) + w * wgt
        tot = sum(acc.values()) or 1.0
        for n, w in acc.items():
            if w / tot > 0.005:
                groups[n].add([v.index], w / tot, "REPLACE")


def skin_rigid(ob, bone):
    g = ob.vertex_groups.new(name=bone)
    g.add([v.index for v in ob.data.vertices], 1.0, "REPLACE")


def skin_split_by_side(ob, bone_r, bone_l):
    gr = ob.vertex_groups.new(name=bone_r)
    gl = ob.vertex_groups.new(name=bone_l)
    for v in ob.data.vertices:
        (gr if (ob.matrix_world @ v.co).x > 0 else gl).add([v.index], 1.0, "REPLACE")


def build_armature():
    arm = bpy.data.armatures.new("Rig")
    ob = link(bpy.data.objects.new("Rig", arm))
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for name, h, t, parent in BONES:
        b = arm.edit_bones.new(name)
        b.head = S[h]
        b.tail = S[t]
        b.roll = 0.0
        if parent:
            b.parent = eb[parent]
            b.use_connect = False
        eb[name] = b
    for i, s in enumerate(("R", "L")):
        ec = FACE["eyes"][i]
        b = arm.edit_bones.new("Lid_" + s)
        b.head = ec
        b.tail = ec + Vector((0, 0, 0.05))
        b.parent = eb["Head"]
        b.use_deform = True
    j = arm.edit_bones.new("Jaw")
    j.head = FACE["mouth"]
    j.tail = FACE["mouth"] + Vector((0, 0, 0.04))
    j.parent = eb["Head"]
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def attach(ob, rig):
    ob.parent = rig
    m = ob.modifiers.new("Armature", "ARMATURE")
    m.object = rig


# ----------------------------------------------------------------------------- materials

ROLES = ["Skin", "Fixed", "Hair", "Suit", "Shirt", "Tie", "Pants", "Shoes", "Hat", "Metal", "Gold"]
MATS = {}


def mat(role):
    if role not in MATS:
        m = bpy.data.materials.new(role)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        vc = m.node_tree.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Col"
        m.node_tree.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
        MATS[role] = m
    return MATS[role]


def assign(ob, role):
    ob.data.materials.clear()
    ob.data.materials.append(mat(role))
    ob["role"] = role


# ----------------------------------------------------------------------------- main

BUDGET = {
    "Body": 3500, "Skull": 5500, "Brows": 500, "Hands": 1800, "Jacket": 5500, "Shirt_cuffs": 700,
    "Tie": 700, "Tie_long": 800, "Top_cop": 4500, "Gear_cop": 5000, "Top_hoodie": 5000, "Top_tee": 4000,
    "Top_shirt": 4000, "Pants": 3500, "Shoes_dress": 1800, "Shoes_sneaker": 1800, "Soles_sneaker": 700,
    "_hair": 4500, "Hair_afro": 5500, "Hair_long": 5500, "Hair_bald": 1500, "Beard_mustache": 900,
    "Beard_goatee": 1400, "Beard_full": 2500, "Beard_stubble": 1000, "Glasses_shades": 1200,
    "Glasses_specs": 1400, "Hat_cop": 3000, "Hat_headset": 2000, "Hat_headband": 1200, "Hat_beanie": 2500,
    "Hat_cap": 2500, "Acc_watch": 700, "Acc_chain": 1000,
}


def main():
    reset()
    kit = []   # (object, role, skinning)
    body = build_body()
    kit.append((body, "Skin", "auto"))
    head, eyes, mouth, lids, brows = build_head()
    kit += [(head, "Skin", "Head"), (eyes, "Fixed", "Head"), (mouth, "Fixed", "Jaw"), (brows, "Hair", "Head")]
    kit.append((join(lids, "Lids"), "Skin", "lids"))
    kit.append((build_hands(), "Skin", "hands"))

    jacket = build_jacket()
    front = FACE["jacket_front"]
    kit.append((jacket, "Suit", "auto"))
    kit.append((v_shirt(front, "Shirt_v"), "Shirt", "auto"))
    kit.append((build_cuffs("Shirt_cuffs"), "Shirt", "auto"))
    kit.append((build_tie(front), "Tie", "auto"))
    kit.append((build_tie(front, long_tie=True), "Tie", "auto"))
    cop, gear = build_cop()
    kit += [(cop, "Suit", "auto"), (gear, "Fixed", "auto")]
    kit.append((build_hoodie(), "Suit", "auto"))
    kit.append((build_tee(), "Suit", "auto"))
    kit.append((build_dress_shirt(), "Suit", "auto"))
    kit.append((build_pants(), "Pants", "auto"))
    kit.append((build_shoes("dress"), "Shoes", "feet"))
    kit.append((build_shoes("sneaker"), "Shoes", "feet"))
    kit.append((join(SOLES, "Soles_sneaker"), "Fixed", "feet"))
    for st in ("slick", "swept", "swoop", "short", "buzz", "messy", "afro", "long", "bald"):
        kit.append((build_hair(head, st), "Hair", "Head"))
    for st in ("mustache", "goatee", "full", "stubble"):
        kit.append((build_beard(head, st), "Hair", "Head"))
    kit.append((build_glasses("shades"), "Fixed", "Head"))
    kit.append((build_glasses("specs"), "Fixed", "Head"))
    kit.append((build_hat(head, "cop"), "Fixed", "Head"))
    kit.append((build_hat(head, "headset"), "Fixed", "Head"))
    for h in ("headband", "beanie", "cap"):
        kit.append((build_hat(head, h), "Hat", "Head"))
    acc = build_accessories()
    kit.append((acc["Acc_watch"], "Metal", "Forearm_L"))
    kit.append((acc["Acc_ring"], "Gold", "Hand_R"))
    kit.append((acc["Acc_chain"], "Gold", "Chest"))

    # polygon budget per piece (a dressed character lands around 30k tris)
    for ob, role, sk in kit:
        target = BUDGET.get(ob.name, BUDGET["_hair"] if ob.name.startswith("Hair_") else 1500)
        n = len(ob.data.polygons)
        if n > target:
            add_mod(ob, "DECIMATE", ratio=target / n, use_collapse_triangulate=True)
            apply_mods(ob)
            shade_smooth(ob)
    # trailer proportions: a bigger head that sits low on the collar
    HEAD_GROUP = ("Skull", "Eyes", "Mouth", "Lids", "Brows", "Hair_", "Beard_", "Glasses_", "Hat_")
    pivot = Vector((0, 0, 1.6))
    M = Matrix.Translation(Vector((0, 0, -0.035))) @ Matrix.Translation(pivot) @ Matrix.Scale(1.1, 4) @ Matrix.Translation(-pivot)
    for ob, role, sk in kit:
        if ob.name.startswith(HEAD_GROUP):
            ob.data.transform(M)
            ob.data.update()
    FACE["eyes"] = [M @ e for e in FACE["eyes"]]
    FACE["mouth"] = M @ FACE["mouth"]
    rig = build_armature()
    skin_heat(body, rig)
    for ob, role, sk in kit:
        if ob is body:
            pass
        elif sk == "auto":
            skin_transfer(ob, body)
        elif sk == "hands":
            skin_split_by_side(ob, "Hand_R", "Hand_L")
        elif sk == "feet":
            skin_split_by_side(ob, "Foot_R", "Foot_L")
        elif sk == "lids":
            skin_split_by_side(ob, "Lid_R", "Lid_L")
        else:
            skin_rigid(ob, sk)
        assign(ob, role)
        attach(ob, rig)
    # clean stray helper objects
    keep = {k[0].name for k in kit} | {"Rig"}
    for o in list(bpy.data.objects):
        if o.name not in keep:
            bpy.data.objects.remove(o)
    tris = sum(len(o.data.polygons) for o, _, _ in kit)
    print("kit meshes:", len(kit), " faces:", tris)
    for o, r, _ in kit:
        print("  %-18s %-6s %6d faces" % (o.name, r, len(o.data.polygons)))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_skins=True, export_animations=False,
                              export_vertex_color="ACTIVE", export_apply=False, export_yup=True,
                              export_materials="EXPORT")
    print("wrote", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
