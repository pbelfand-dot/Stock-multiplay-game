# blender -b --python fit_glove.py -- in.glb out_dir
# Fits a generated racing glove (a right hand gripping a short bar) to SHOTGUN RALLY's glove
# space (driver_hands.gd): the rim along x through the origin, x toward the thumb, y out of the
# back of the hand, z toward the wrist; then GRIP_ROLL about x. Writes the hand
# (the hand, the bar cut away) and its gauntlet (in cuff space: x along the
# glove's x, y up the forearm from the wrist) in one gloves.glb (shared 1024 px textures), and glove.json
# (the wrist, in glove space: driver_hands.gd's MODEL_WRIST).
import bpy, bmesh, sys, math, json
from mathutils import Vector, Matrix
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
RIM_R = 0.0155
GRIP_ROLL = 0.55
HAND_W = 0.112        # m across the grip along the rim: a gloved hand ~9 cm over the knuckles, the thumb
                      # round the rim beside it (the generated bar is thinner than a wheel's rim for the
                      # hand round it, so scaling to the bar alone made a hand ~1.4x life size)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
ob = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
P = np.array([v.co[:] for v in ob.data.vertices])
cen = P.mean(axis=0)
print("[fit] verts", len(P))

# the bar: the direction whose two ends are both thin (a bar sticks out both sides of the fist;
# the other long direction ends in the gauntlet's wide opening)
def fib(n):
    out = []
    g = math.pi * (3.0 - math.sqrt(5.0))
    for i in range(n):
        y = 1 - (i / (n - 1)) * 2
        r = math.sqrt(1 - y * y)
        out.append((math.cos(g * i) * r, y, math.sin(g * i) * r))
    return [np.array(d) for d in out if d[1] >= 0 or True]
best = None
size = np.linalg.norm(P.max(0) - P.min(0))
for dvec in fib(1500):
    t = (P - cen) @ dvec
    tmax, tmin = t.max(), t.min()
    band = size * 0.04
    e1 = P[t > tmax - band]
    e2 = P[t < tmin + band]
    if len(e1) < 8 or len(e2) < 8:
        continue
    def spread(e):
        q = e - e.mean(0)
        q = q - np.outer(q @ dvec, dvec)
        return np.sqrt((q ** 2).sum(1)).max()
    sc = max(spread(e1), spread(e2))
    if best is None or sc < best[0]:
        best = (sc, dvec, e1.mean(0), e2.mean(0))
_, U, c1, c2 = best
axis_pt = (c1 + c2) * 0.5
U = (c1 - c2) / np.linalg.norm(c1 - c2)
# the bar's radius: its points near either end, their distance from the axis
def dist_axis(Q):
    q = Q - axis_pt
    return np.sqrt(((q - np.outer(q @ U, U)) ** 2).sum(1))
t = (P - axis_pt) @ U
ends = P[(np.abs(t) > np.abs(t).max() * 0.82)]
bar_r = np.median(dist_axis(ends))
print("[fit] bar axis", np.round(U, 3), "bar radius (model units)", round(float(bar_r), 4))
# the hand along the bar: the glove's points that aren't the bar
da = dist_axis(P)
glove_pts = P[da > bar_r * 1.25]
tg = (glove_pts - axis_pt) @ U
mid_t = 0.5 * (tg.max() + tg.min())
origin = axis_pt + U * mid_t                    # the middle of the grip, on the bar
# toward the wrist: from the bar to the far end of the gauntlet (perpendicular to the bar)
q = glove_pts - origin
q_perp = q - np.outer(q @ U, U)
far = q_perp[np.argsort(np.sqrt((q_perp ** 2).sum(1)))[-max(50, len(q_perp) // 50):]].mean(0)
B = far / np.linalg.norm(far)
R = np.cross(B, U)                              # (U, R, B) per the frame below: R ⟂ both
R /= np.linalg.norm(R)
# which way is the back of the hand: the hand's bulk (near the bar, not the gauntlet) sits out
# that side of the bar
near = q[(np.sqrt((q_perp ** 2).sum(1)) < bar_r * 6.0)]
if (near @ R).mean() < 0.0:
    R = -R
# which way is the thumb: under the bar (the palm side, -R) on the wrist's side (+B)
thumb = q[((q @ R) < -bar_r * 1.2) & ((q @ B) > bar_r * 0.6) & ((q @ B) < bar_r * 5.0)]
if len(thumb) > 0 and (thumb @ U).mean() < 0.0:
    U = -U
print("[fit] thumb points", len(thumb))
scale = RIM_R / bar_r
# glove space: x = U (thumb), y = R (back of the hand), z = B (wrist); a mirror of the model's
# own axes when (U, R, B) is left-handed: the faces are turned to keep them outward
M = np.array([U, R, B]) * scale
det = np.linalg.det(np.array([U, R, B]))
print("[fit] frame det", round(float(det), 3), "scale", round(float(scale), 4))
roll = np.array([[1, 0, 0], [0, math.cos(GRIP_ROLL), -math.sin(GRIP_ROLL)], [0, math.sin(GRIP_ROLL), math.cos(GRIP_ROLL)]])

def to_glove(p):
    return roll @ (M @ (np.array(p) - origin))

Gpre = (M @ (P - origin).T).T                    # (before the roll)
# life size: the hand's width along the rim to HAND_W, shrunk toward the rim's surface (not its
# middle: the fingers stay round a rim of RIM_R) and along it, the same factor both ways
near_bar = Gpre[(np.sqrt(Gpre[:, 1] ** 2 + Gpre[:, 2] ** 2) > RIM_R * 1.3) & (Gpre[:, 2] < 0.04)][:, 0]
K = min(1.0, HAND_W / float(near_bar.max() - near_bar.min()))
print("[fit] hand width", round(float(near_bar.max() - near_bar.min()), 4), "-> life size x", round(K, 3))

def shrink(Q):
    """Points in glove space (either side of the roll: it's about x) shrunk K toward the rim."""
    Q = np.array(Q, dtype=float).copy()
    Q[:, 0] *= K
    r = np.sqrt(Q[:, 1] ** 2 + Q[:, 2] ** 2)
    f = np.where(r > RIM_R, (RIM_R + (r - RIM_R) * K) / np.maximum(r, 1e-9), 1.0)
    Q[:, 1] *= f
    Q[:, 2] *= f
    return Q

Gpre = shrink(Gpre)
# the wrist: along B, the narrowest cross-section between the hand and the gauntlet's flare
dag = np.sqrt(Gpre[:, 0] ** 0 * 0 + Gpre[:, 1] ** 2 + Gpre[:, 2] ** 2)
offbar = np.sqrt(Gpre[:, 1] ** 2 + Gpre[:, 2] ** 2) > RIM_R * 1.3
Gg = Gpre[offbar]
zs = np.linspace(0.04, Gg[:, 2].max() - 0.03, 50)
rad = []
for z in zs:
    sl = Gg[np.abs(Gg[:, 2] - z) < 0.004]
    if len(sl) < 40:
        rad.append(9.0)
        continue
    c = sl.mean(0)
    rad.append(float(np.median(np.sqrt(((sl[:, :2] - c[:2]) ** 2).sum(1)))))
print("[fit] radius profile", [(round(float(z), 3), round(r, 4)) for z, r in zip(zs, rad)][::3])
# the wrist: the narrowest past the hand's widest (the knuckles and thumb), before the flare
iw = int(np.argmin(rad[len(rad) // 5:])) + len(rad) // 5
wz = float(zs[iw])
sl = Gpre[np.abs(Gpre[:, 2] - wz) < 0.004]
wrist_pre = sl.mean(0)
hand_w = Gg[(Gg[:, 2] < 0.04)][:, 0]
print("[fit] wrist (pre-roll)", np.round(wrist_pre, 4), "radius there", round(rad[iw], 4), "hand width", round(float(hand_w.max() - hand_w.min()), 4) if len(hand_w) else None)
print("[fit] length wrist->cuff end", round(float(Gpre[:, 2].max() - wz), 4))

# apply to the mesh: glove-space coordinates (Godot axes) -> Blender (x, -z, y) for the export
mat_g2b = np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]])
A = mat_g2b @ roll @ M
Mx = Matrix(((A[0, 0], A[0, 1], A[0, 2], 0), (A[1, 0], A[1, 1], A[1, 2], 0), (A[2, 0], A[2, 1], A[2, 2], 0), (0, 0, 0, 1)))
ob.matrix_world = Mx @ Matrix.Translation(Vector(-origin))
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
# (Blender's (x, -z, y) of glove space: the same distance from the x axis, so the same shrink)
V = np.array([v.co[:] for v in ob.data.vertices])
V = shrink(V)
for v, c in zip(ob.data.vertices, V):
    v.co = Vector(c)
if np.linalg.det(A) < 0:
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.flip_normals()
    bpy.ops.object.mode_set(mode="OBJECT")

def gb(v):            # a Blender coordinate back to glove space
    return np.array([v[0], v[2], -v[1]])

wrist_g = roll @ wrist_pre
# up the forearm: the gauntlet's own axis, from the wrist to the middle of its open end (the
# source's wrist may be bent a little: the cuff follows the real forearm in the game)
zmax = float(Gg[:, 2].max())
end_c = Gg[Gg[:, 2] > zmax - 0.02].mean(0)
fore_pre = (end_c - wrist_pre) / np.linalg.norm(end_c - wrist_pre)
print("[fit] gauntlet axis (pre-roll)", np.round(fore_pre, 3))
fore_g = roll @ fore_pre

def split(keep_hand: bool, name: str):
    """A copy of the glove: its hand (the bar cut away) or its gauntlet (past the wrist)."""
    o = ob.copy()
    o.data = ob.data.copy()
    bpy.context.scene.collection.objects.link(o)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    kill = []
    for v in bm.verts:
        g = gb(v.co)
        pre = roll.T @ g
        on_bar = math.sqrt(pre[1] ** 2 + pre[2] ** 2) < RIM_R * 1.06
        # (they overlap 14 mm at the wrist, the cuff's edge over the hand's: no gap however the
        # forearm turns the cuff)
        if keep_hand and (pre[2] > wz + 0.006 or on_bar):
            kill.append(v)
        if not keep_hand and pre[2] < wz - 0.008:
            kill.append(v)
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    o.name = name
    return o

hand = split(True, "Glove")
cuff = split(False, "Cuff")
# the gauntlet in cuff space: origin at the wrist, y up the forearm, x along the glove's x
X = np.array([1.0, 0.0, 0.0])
Y = fore_g / np.linalg.norm(fore_g)
Xc = X - Y * X.dot(Y)
Xc /= np.linalg.norm(Xc)
Z = np.cross(Xc, Y)
Cm = np.array([Xc, Y, Z])                        # glove -> cuff (right-handed)
# Blender coords -> glove (gb) -> cuff -> Blender (g2b)
gbm = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]])
C = mat_g2b @ Cm @ gbm
wb = mat_g2b @ wrist_g
cuff.matrix_world = Matrix(((C[0, 0], C[0, 1], C[0, 2], 0), (C[1, 0], C[1, 1], C[1, 2], 0), (C[2, 0], C[2, 1], C[2, 2], 0), (0, 0, 0, 1))) @ Matrix.Translation(Vector(-wb))
bpy.context.view_layer.objects.active = cuff
for o in bpy.context.scene.objects:
    o.select_set(o == cuff)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

def export(o, path, mirror_x=False):
    for x in bpy.context.scene.objects:
        x.select_set(x == o)
    bpy.context.view_layer.objects.active = o
    if mirror_x:
        o.matrix_world = Matrix.Scale(-1.0, 4, Vector((1, 0, 0))) @ o.matrix_world
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.flip_normals()
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_image_format="JPEG", export_jpeg_quality=88)
    if mirror_x:      # back again
        o.matrix_world = Matrix.Scale(-1.0, 4, Vector((1, 0, 0))) @ o.matrix_world
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.flip_normals()
        bpy.ops.object.mode_set(mode="OBJECT")
    print("[fit] wrote", path, len(o.data.polygons), "faces")

for o, nm in [(hand, "glove"), (cuff, "cuff")]:
    dc = o.modifiers.new("dec", "DECIMATE")
    dc.ratio = min(1.0, (9000.0 if nm == "glove" else 2500.0) / max(len(o.data.polygons), 1))
    for x in bpy.context.scene.objects:
        x.select_set(x == o)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="dec")
ob.hide_set(True)
# one file, both pieces, one material; its textures down to what a glove fills on screen
for img in bpy.data.images:
    if img.size[0] > 0:
        side = 512 if "metal" in img.name.lower() or "rough" in img.name.lower() else 1024
        if img.size[0] > side:
            img.scale(side, side)
        print("[fit] texture", img.name, tuple(img.size))
for x in bpy.context.scene.objects:
    x.select_set(x in (hand, cuff))
bpy.context.view_layer.objects.active = hand
bpy.ops.export_scene.gltf(filepath=OUT + "/gloves.glb", export_format="GLB", use_selection=True, export_apply=True,
                          export_yup=True, export_image_format="JPEG", export_jpeg_quality=85)
print("[fit] wrote", OUT + "/gloves.glb")
json.dump({"wrist": [float(x) for x in wrist_g], "wrist_pre_roll": [float(x) for x in wrist_pre],
           "forearm": [float(x) for x in fore_g], "scale": float(scale), "life_size": K, "bar_radius_model": float(bar_r)},
          open(OUT + "/glove.json", "w"), indent=1)
print("[fit] done")
