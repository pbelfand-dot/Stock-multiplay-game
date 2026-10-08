"""The city's far tier (tools/import_environment.py's "skyline" mode): the owner's 31-building
pack (FBX, geometry only: no materials, no UVs worth having, 60-530 k triangles each) made
into light silhouettes for the skyline, seen from 200 m to 4 km off. No textures: the game
draws their facades and windows with a shader from where on the building a pixel is
(scripts/stage/city_skyline.gd).

  * each file's meshes in metres (the FBX are in millimetres), Z up; a file holding two
    buildings side by side (its meshes in two clusters apart on the ground) gives two
  * a shell: the building voxel-remeshed (spec "voxel" m: the window reveals, balcony rails
    and sills closed up, what's left is what you see from far off: the tower, its set-backs,
    the roof's plant rooms and tanks; the masts are thinner than that and go), then
    simplified to the spec's triangles ("tris" per 100 m of height, between "tris_min" and
    "tris_max"); lighter copies for far off (its parts <name>_LOD1, _LOD2: spec "lods", each
    [a share of the one before, the triangles it keeps at least, its voxels]: shelled again,
    coarser, the loose pieces smaller than 3 / 6 m left out)
  * its walls' real floor and window spacing measured on the full model (the sills' and
    lintels' heights, the reveals' sides along each wall: the strongest repeat of each), and
    its main roof's height (the top of its walls: the pack's Roof_* meshes are the plant on
    it), for the shader's window grid
  * normals smooth over faces within 30 degrees, sharp at the corners (the shader's walls are
    planes), its origin at the middle of its foot, upright (Y up in the GLB)
  * all of them as parts of one GLB (spec "out"), no material, no UVs: the game sets its own
The source files are only read (opened with scripts off: blender -b -Y). Prints each
building's numbers as a JSON line ("skyline {...}") for data/environment_assets.json.
The pack's 31st file, Rooftop.FBX, is a kit of roof props (tanks, masts, a billboard), not a
building: not taken (too small for the far tier); its 01.FBX holds two buildings.
"""
import bpy, bmesh, json, math, os, time
import numpy as np
from mathutils import Vector, Matrix


def _import(path):
    """The file's meshes, added to the scene (the buildings made so far stay)."""
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    new = [o for o in bpy.context.scene.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    for o in new:
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    for o in meshes:                                       # (in world space, metres: the transform applied)
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    return meshes


def _bounds(objs):
    vs = np.concatenate([_verts(o) for o in objs])
    return vs.min(axis=0), vs.max(axis=0)


def _verts(o):
    a = np.empty(len(o.data.vertices) * 3, dtype=np.float64)
    o.data.vertices.foreach_get("co", a)
    return a.reshape(-1, 3)


def _clusters(meshes, gap=1.5):
    """The meshes grouped into buildings: those whose footprints (boxes on the ground) overlap
    or come within gap m of each other, together. West to east (then south to north)."""
    boxes = [_bounds([o]) for o in meshes]
    group = list(range(len(meshes)))

    def root(i):
        while group[i] != i:
            i = group[i]
        return i
    for i in range(len(meshes)):
        for j in range(i + 1, len(meshes)):
            (a0, a1), (b0, b1) = boxes[i], boxes[j]
            if all(a0[k] - gap <= b1[k] and b0[k] - gap <= a1[k] for k in range(2)):
                group[root(j)] = root(i)
    out = {}
    for i in range(len(meshes)):
        out.setdefault(root(i), []).append(meshes[i])
    return sorted(out.values(), key=lambda g: tuple(np.round(_bounds(g)[0][:2], 1)))


def _period(values, weights, lo, hi, bin_w=0.05):
    """The strongest repeat (lo..hi m) in a set of positions (each with its weight: the faces'
    areas), from their histogram's autocorrelation. Returns (period, how clear 0..1)."""
    if len(values) < 8:
        return 0.0, 0.0
    v0, v1 = float(values.min()), float(values.max())
    n = int((v1 - v0) / bin_w) + 2
    if n < int(hi / bin_w) * 2:
        return 0.0, 0.0
    h = np.zeros(n)
    np.add.at(h, ((values - v0) / bin_w).astype(int), weights)
    h = np.convolve(h, np.ones(3) / 3.0, mode="same")
    # (only the repeat matters, not where the faces bunch: what varies slower than a metre or
    # so taken off)
    w = int(1.2 / bin_w) | 1
    h -= np.convolve(h, np.ones(w) / w, mode="same")
    ac = np.correlate(h, h, mode="full")[n - 1:]
    if ac[0] <= 0:
        return 0.0, 0.0
    ac /= ac[0]
    k0, k1 = int(lo / bin_w), int(hi / bin_w) + 1
    peaks = [k for k in range(max(k0, 1), min(k1, n - 1)) if ac[k] >= ac[k - 1] and ac[k] >= ac[k + 1] and ac[k] > 0.0]
    if not peaks:
        return 0.0, 0.0
    k = max(peaks, key=lambda q: ac[q])
    # (a period's double scores as well: take the shortest repeat that's nearly as strong)
    for q in sorted(peaks):
        if q < k and ac[q] > ac[k] * 0.8 and abs(k / q - round(k / q)) < 0.08:
            k = q
            break
    return k * bin_w, float(ac[k])


def _measure(objs, base_z):
    """The full model's floor height and window bay, from its faces: the horizontal faces
    (sills, lintels, slab edges) repeat up the walls a floor apart; the window reveals' sides
    repeat along each wall a bay apart."""
    zs, zw, along, aw = [], [], [], []
    for o in objs:
        me = o.data
        n = len(me.polygons)
        nr = np.empty(n * 3)
        me.polygons.foreach_get("normal", nr)
        nr = nr.reshape(-1, 3)
        ce = np.empty(n * 3)
        me.polygons.foreach_get("center", ce)
        ce = ce.reshape(-1, 3)
        ar = np.empty(n)
        me.polygons.foreach_get("area", ar)
        hor = np.abs(nr[:, 2]) > 0.95
        zs.append(ce[hor, 2])
        zw.append(np.minimum(ar[hor], 2.0))
        side = (np.abs(nr[:, 2]) < 0.1) & (ar > 0.01)
        for ax in (0, 1):                               # (faces facing +-X sit along walls running in X... their x repeats)
            m = side & (np.abs(nr[:, ax]) > 0.95)
            along.append(ce[m, ax])
            aw.append(np.minimum(ar[m], 1.0))
    z = np.concatenate(zs) - base_z
    w = np.concatenate(zw)
    keep = z > 4.0                                     # (above the shops)
    floor, f_q = _period(z[keep], w[keep], 2.7, 4.6)
    bay, b_q = _period(np.concatenate(along), np.concatenate(aw), 1.4, 4.5)
    return (floor if f_q > 0.12 else 2.8), (bay if b_q > 0.12 else 2.6), f_q, b_q   # (else the pack's usual: 2.8 m floors)


def _join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    copies = []
    for o in objs:
        c = o.copy()
        c.data = o.data.copy()
        bpy.context.scene.collection.objects.link(c)
        copies.append(c)
    for c in copies:
        c.select_set(True)
    bpy.context.view_layer.objects.active = copies[0]
    if len(copies) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def _tris(ob):
    ob.data.calc_loop_triangles()
    return len(ob.data.loop_triangles)


def _apply(ob, m):
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=m.name)


def _shell(ob, voxel, target, lo, hi, specks=0.0):
    """The far-off silhouette: voxel-remeshed (the facade's small relief closed), collapsed to
    six times the target, its near-flat faces dissolved into the walls' planes (the remesh's
    steps would shade as a speckle), collapsed to the target, triangulated. The models have
    no floor: a slab just above the foot closes them first (otherwise the remesh can't tell
    inside from out and wraps each wall in a skin of its own). Its normals smooth across
    faces within 30 degrees of each other, sharp at the corners."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    z = lo[2] + 0.15
    bm.faces.new([bm.verts.new((x, y, z)) for x, y in ((lo[0] - 0.2, lo[1] - 0.2), (hi[0] + 0.2, lo[1] - 0.2),
        (hi[0] + 0.2, hi[1] + 0.2), (lo[0] - 0.2, hi[1] + 0.2))])
    bm.to_mesh(ob.data)
    bm.free()
    m = ob.modifiers.new("remesh", "REMESH")
    m.mode = "VOXEL"
    m.voxel_size = voxel
    m.adaptivity = 0.0
    m.use_remove_disconnected = False
    _apply(ob, m)
    _drop_inner(ob, 40, specks)
    # (the collapse first: a planar dissolve straight on the remesh takes minutes on a tower)
    for k, aim in enumerate((target * 6, target)):
        t = _tris(ob)
        if t > aim:
            m = ob.modifiers.new("collapse", "DECIMATE")
            m.decimate_type = "COLLAPSE"
            m.ratio = max(0.002, aim / float(t))
            m.use_collapse_triangulate = True
            _apply(ob, m)
        if k == 0:
            m = ob.modifiers.new("dissolve", "DECIMATE")
            m.decimate_type = "DISSOLVE"
            m.angle_limit = math.radians(4.0)
            _apply(ob, m)
            m = ob.modifiers.new("tri", "TRIANGULATE")
            _apply(ob, m)
    return _finish(ob)


def _finish(ob):
    """Triangulated, checked, its normals smooth across faces within 30 degrees of each other."""
    m = ob.modifiers.new("tri", "TRIANGULATE")
    _apply(ob, m)
    me = ob.data
    me.validate(verbose=False, clean_customdata=True)
    for p in me.polygons:
        p.use_smooth = True
    if hasattr(me, "use_auto_smooth"):                       # (Blender 4.0; 4.1+ would take a "smooth by angle" modifier)
        me.use_auto_smooth = True
        me.auto_smooth_angle = math.radians(30.0)
    return _tris(ob)


def _components(me):
    """Each vertex's connected piece (a label per vertex: the piece's smallest vertex): each
    edge joining two pieces hooks the larger one's label under the smaller's, the labels then
    pointed straight at their piece's, until no edge joins two."""
    n = len(me.vertices)
    e = np.empty(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", e)
    e = e.reshape(-1, 2)
    lab = np.arange(n)
    while True:
        lu, lv = lab[e[:, 0]], lab[e[:, 1]]
        apart = lu != lv
        if not apart.any():
            return lab
        np.minimum.at(lab, np.maximum(lu[apart], lv[apart]), np.minimum(lu[apart], lv[apart]))
        while True:
            nxt = lab[lab]
            if (nxt == lab).all():
                break
            lab = nxt


def _drop_inner(ob, min_verts=40, min_size=0.0):
    """What the remesh leaves that isn't the outside: the pieces wholly inside the biggest
    piece's box (an inner skin, sealed rooms) and the flecks (a few voxels: a mast's tip) go;
    for a far copy, also the pieces smaller than min_size m (a loose balcony slab, a roof tank:
    the collapse can't take a closed piece below a few triangles, and they're specks there)."""
    me = ob.data
    co = _verts(ob)
    lab = _components(me)
    ids, inv, counts = np.unique(lab, return_inverse=True, return_counts=True)
    lo = np.full((len(ids), 3), np.inf)
    hi = np.full((len(ids), 3), -np.inf)
    np.minimum.at(lo, inv, co)
    np.maximum.at(hi, inv, co)
    big = int(np.argmax(counts))
    inner = (lo > lo[big] + 0.05).all(axis=1) & (hi < hi[big] - 0.05).all(axis=1)
    gone_part = inner | (counts < min_verts) | ((hi - lo).max(axis=1) < min_size)
    gone_part[big] = False
    gone = np.nonzero(gone_part[inv])[0]
    if len(gone):
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.verts[i] for i in gone], context="VERTS")
        bm.to_mesh(me)
        bm.free()
    return len(ids), int(gone_part.sum())


def convert(spec, src_path, out_objs):
    """One source file's building(s), added to the scene as parts (out_objs). Returns their
    numbers ({name, tris, size, floor, bay, src_tris})."""
    stem = os.path.splitext(os.path.basename(src_path))[0]
    meshes = _import(src_path)
    groups = _clusters(meshes)
    names = spec.get("names", {})
    rows = []
    for k, g in enumerate(groups):
        t0 = time.time()
        base = names.get(stem, "bld31_" + stem)
        name = base if len(groups) == 1 else base + "abcdefgh"[k]
        lo, hi = _bounds(g)
        src_tris = 0
        for o in g:
            o.data.calc_loop_triangles()
            src_tris += len(o.data.loop_triangles)
        height = float(hi[2] - lo[2])
        floor, bay, f_q, b_q = _measure(g, lo[2])
        target = int(min(spec.get("tris_max", 8000), max(spec.get("tris_min", 2000), spec.get("tris", 4000) * height / 100.0)))
        low = _join(g, name)
        src = low.copy()                                     # (the far copies are shelled from it too)
        src.data = low.data.copy()
        bpy.context.scene.collection.objects.link(src)
        t = _shell(low, float(spec.get("voxel", 0.4)), target, lo, hi)
        # the main roof: the top of its walls (the pack's Roof_* meshes are the plant on it)
        walls = [o for o in g if not o.name.lower().startswith("roof")] or g
        roof = float(_bounds(walls)[1][2] - lo[2])
        # the origin at the middle of its foot
        foot = Vector(((lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5, lo[2]))
        low.data.transform(Matrix.Translation(-foot))
        d = low.dimensions
        # the far ones (LOD1, LOD2: drawn from 650 m and 1.8 km or so): each shelled again from
        # the full model with coarser voxels (that closes the gaps behind balconies and between
        # the plant on the roof: a collapse can't take those holes away, and stalls), to a share
        # of the one before
        lods = [low]
        for k, (share, least, voxel) in enumerate(spec.get("lods", [[0.2, 250, 1.0], [0.35, 120, 2.0]])):
            far = src.copy()
            far.data = src.data.copy()
            far.name = far.data.name = "%s_LOD%d" % (name, k + 1)
            bpy.context.scene.collection.objects.link(far)
            _shell(far, float(voxel), max(int(least), int(_tris(lods[-1]) * float(share))), lo, hi, 3.0 * (k + 1))
            far.data.transform(Matrix.Translation(-foot))
            lods.append(far)
        bpy.data.objects.remove(src, do_unlink=True)
        row = {"name": name, "src": os.path.basename(src_path), "src_tris": src_tris, "tris": t, "tris_lods": [_tris(o) for o in lods[1:]],
            "size": [round(d.x, 1), round(d.z, 1), round(d.y, 1)], "floor": round(floor, 2), "bay": round(bay, 2),
            "roof": round(min(roof, d.z), 1), "floor_q": round(f_q, 2), "bay_q": round(b_q, 2), "secs": round(time.time() - t0, 1)}
        print("skyline " + json.dumps(row))
        rows.append(row)
        out_objs += lods
    for o in meshes:
        bpy.data.objects.remove(o, do_unlink=True)
    return rows


def export(objs, out_path):
    """The parts into one GLB (Y up), no material, no UVs: each part a node of its own."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", export_yup=True, use_selection=True,
        export_apply=True, export_materials="NONE", export_texcoords=False, export_normals=True,
        export_colors=False, export_attributes=False)
    print("wrote %s (%.2f MB)" % (out_path, os.path.getsize(out_path) / 1e6))
