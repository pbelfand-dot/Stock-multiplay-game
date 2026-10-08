"""Trees for the game (tools/import_environment.py, a spec with "mode": "tree"): hero trees of a
million triangles and more made into three levels each, in one GLB per pack:

  <variant>_LOD0   near (the first ~50 m): the leaf cards thinned to a budget, the ones kept
                   grown to fill in (the outer ones kept first: the silhouette holds), the bark
                   decimated (it keeps its shape, the twigs go first)
  <variant>_LOD1   middle distance: the same, a few thousand triangles
  <variant>_BB     far: two crossed cards with the tree rendered on them (Cycles, from the side,
                   in even light: its colour and the shade inside the crown baked in)

The packs' materials become three shared ones (bark, leaf, leaf2: the leaf cards cut out by
their opacity, both sides drawn), so a pack's variants share their textures in the GLB. Leaf
textures with no alpha get it from the pack's opacity map; a pack with no leaf texture at all
(spec "leaf_texture": "procedural_robinia") gets a drawn one. Spec keys (beyond the converter's):
  srcs / src        the source file(s); objects (optional): which meshes are trees (each a variant)
  lod0, lod1        triangle budgets; leaf_scale_max: how much a kept card may grow (2.4)
  bark_like, leaf_like  texture/material name parts that say which is which ("trunk", "needle")
  bark_texture      (optional) the bark images to use instead ({"diffuse":, "normal":, "rough":})
  billboard         the far card's texture height (px; its width follows the tree)
"""
import bmesh, bpy, math, os, random
import mathutils
from mathutils import Vector

LEAF_SCALE_MAX = 2.4


def _images(mat):
    out = []
    if mat and mat.use_nodes:
        for n in mat.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image:
                out.append(n.image)
    return out


def _is_leaf(mat, spec):
    names = [mat.name.lower()] + [os.path.basename(i.filepath or i.name).lower() for i in _images(mat)]
    if any(any(k in n for k in spec.get("leaf_like", ["needle", "leaf", "foliage"])) for n in names):
        return True
    return False


def _find(images, *keys):
    for im in images:
        n = os.path.basename(im.filepath or im.name).lower()
        if all(k in n for k in keys):
            return im
    return None


def _load_image(path):
    if not path or not os.path.exists(path):
        return None
    return bpy.data.images.load(path, check_existing=True)


def _search(src_dir, name):
    """A texture the source names but didn't link: looked for next to it (any case, any subfolder)."""
    if not name:
        return None
    want = os.path.basename(name).lower()
    for root, _dirs, files in os.walk(src_dir):
        for f in files:
            if f.lower() == want:
                return os.path.join(root, f)
    return None


def _with_alpha(diffuse, opacity, name):
    """The leaf colour with the opacity map as its alpha (one RGBA image: the cut-out)."""
    import numpy as np
    w, h = diffuse.size
    px = np.array(diffuse.pixels[:], dtype=np.float32).reshape(h, w, 4)
    if opacity is not None:
        if tuple(opacity.size) != (w, h):
            opacity = opacity.copy()
            opacity.scale(w, h)
        op = np.array(opacity.pixels[:], dtype=np.float32).reshape(h, w, 4)
        px[:, :, 3] = op[:, :, 0]
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.pixels.foreach_set(px.ravel())
    img.pack()
    return img


def _procedural_robinia_leaf(size=512):
    """A black locust (Robinia) compound leaf: a rachis and nine to thirteen oval leaflets in pairs,
    drawn in greens on a transparent ground (the pack ships none)."""
    import numpy as np
    h = w = size
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    u = xs / w
    v = ys / h                                       # 0 at the top (Blender's pixels are bottom up: flipped below)
    alpha = np.zeros((h, w), np.float32)
    shade = np.zeros((h, w), np.float32)
    rng = random.Random(7)
    pairs = 6
    for k in range(pairs):
        t = 0.12 + k * 0.13                         # down the rachis
        for side in (-1, 1):
            cx = 0.5 + side * 0.17
            cy = t + 0.02
            rx, ry = 0.17, 0.085
            ang = side * 0.35
            dx = (u - cx) * math.cos(ang) + (v - cy) * math.sin(ang)
            dy = -(u - cx) * math.sin(ang) + (v - cy) * math.cos(ang)
            d = (dx / rx) ** 2 + (dy / ry) ** 2
            leaflet = np.clip((1.0 - d) * 6.0, 0.0, 1.0)
            alpha = np.maximum(alpha, leaflet)
            shade = np.maximum(shade, leaflet * (0.85 + 0.3 * rng.random()) * (1.0 - 0.35 * np.clip(np.abs(dy) / ry, 0, 1)))
    # the end leaflet and the rachis
    d = ((u - 0.5) / 0.07) ** 2 + ((v - 0.9) / 0.12) ** 2
    end = np.clip((1.0 - d) * 6.0, 0.0, 1.0)
    alpha = np.maximum(alpha, end)
    shade = np.maximum(shade, end * 0.95)
    rachis = np.clip(1.0 - np.abs(u - 0.5) / 0.008, 0, 1) * ((v > 0.04) & (v < 0.95))
    alpha = np.maximum(alpha, rachis)
    base = np.array([0.20, 0.36, 0.09], np.float32)
    light = np.array([0.36, 0.55, 0.16], np.float32)
    col = base[None, None, :] + (light - base)[None, None, :] * shade[:, :, None]
    col = np.where(rachis[:, :, None] > 0.5, np.array([0.33, 0.4, 0.16], np.float32), col)
    px = np.concatenate([col, alpha[:, :, None]], axis=2)[::-1]   # (bottom row first)
    img = bpy.data.images.new("robinia_leaf", w, h, alpha=True)
    img.pixels.foreach_set(px.astype(np.float32).ravel())
    img.pack()
    return img


def _material(name, diffuse, normal=None, rough=None, leaf=False, tint=None):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    if diffuse:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = diffuse
        if tint:
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs[0].default_value = 1.0
            nt.links.new(t.outputs["Color"], mix.inputs[6])
            mix.inputs[7].default_value = (tint[0], tint[1], tint[2], 1.0)
            nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        else:
            nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
        if leaf:
            nt.links.new(t.outputs["Alpha"], bsdf.inputs["Alpha"])
    if normal:
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = normal
        normal.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(n.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if rough:
        r = nt.nodes.new("ShaderNodeTexImage")
        r.image = rough
        rough.colorspace_settings.name = "Non-Color"
        nt.links.new(r.outputs["Color"], bsdf.inputs["Roughness"])
    else:
        bsdf.inputs["Roughness"].default_value = 0.85 if not leaf else 0.7
    bsdf.inputs["Specular IOR Level"].default_value = 0.25 if leaf else 0.2
    if leaf:
        m.blend_method = "CLIP"
        m.alpha_threshold = 0.4
        m.use_backface_culling = False
        m.show_transparent_back = False
    return m


def shared_materials(spec, src_dir, sample_mats):
    """The pack's bark and leaf materials (one each, two leaves if the pack has two needle sets)."""
    imgs = []
    for m in sample_mats:
        imgs += _images(m)
    # names the source points at but didn't find: looked for in the pack
    for im in list(imgs):
        if im.size[0] == 0:
            p = _search(src_dir, im.filepath)
            if p:
                im.filepath = p
                im.reload()
    imgs = [i for i in imgs if i.size[0] > 0]
    bt = spec.get("bark_texture")
    if bt:
        bark_d = _load_image(os.path.join(src_dir, bt["diffuse"]))
        bark_n = _load_image(os.path.join(src_dir, bt.get("normal", "")))
        bark_r = _load_image(os.path.join(src_dir, bt.get("rough", "")))
    else:
        bark_d = _find(imgs, "trunk", "diff") or _find(imgs, "bark", "diff")
        bark_n = _find(imgs, "trunk", "normal") or _find(imgs, "bark", "normal")
        bark_r = None
    mats = {"bark": _material("bark", bark_d, bark_n, bark_r)}       # (a tint is the game's: data/environment_assets.json)
    if spec.get("leaf_texture") == "procedural_robinia":
        mats["leaf"] = _material("leaf", _procedural_robinia_leaf(), leaf=True)
        return mats
    for key, tag in (("leaf", spec.get("leaf_sets", ["needle1", "leaf"])), ("leaf2", spec.get("leaf2_sets", ["needle2"]))):
        d = o = n = r = None
        for t in tag:
            d = d or _find(imgs, t, "diff")
            o = o or _find(imgs, t, "opac")
            n = n or _find(imgs, t, "normal")
            r = r or _find(imgs, t, "rough")
        if d is None:
            continue
        has_alpha = d.channels == 4 and d.alpha_mode != "NONE" and o is None
        leaf_img = d if has_alpha else _with_alpha(d, o, key + "_rgba")
        mats[key] = _material(key, leaf_img, n, r, leaf=True)
    return mats


def _uf_islands(me, face_mask):
    """Connected groups of the masked faces (by shared vertices): face index -> island id."""
    parent = list(range(len(me.vertices)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for p in me.polygons:
        if not face_mask[p.index]:
            continue
        vs = p.vertices
        r0 = find(vs[0])
        for v in vs[1:]:
            r1 = find(v)
            if r1 != r0:
                parent[r1] = r0
    isl = {}
    for p in me.polygons:
        if face_mask[p.index]:
            isl[p.index] = find(p.vertices[0])
    return isl


def leaf_islands(me, leaf_slots):
    """The tree's leaf cards: island -> its faces, island -> its centre (computed once a tree)."""
    leaf_mask = [p.material_index in leaf_slots for p in me.polygons]
    isl = _uf_islands(me, leaf_mask)
    groups = {}
    for fi, g in isl.items():
        groups.setdefault(g, []).append(fi)
    centres = {}
    for g, fs in groups.items():
        c = Vector()
        for fi in fs:
            c += me.polygons[fi].center
        centres[g] = c / len(fs)
    return groups, centres


def bark_pieces(me, bark_slots):
    """The bark's separate pieces: piece -> (its size: the longest side of its box, its faces, its triangles)."""
    mask = [p.material_index in bark_slots for p in me.polygons]
    isl = _uf_islands(me, mask)
    pieces = {}
    for fi, g in isl.items():
        pieces.setdefault(g, []).append(fi)
    out = {}
    for g, fs in pieces.items():
        mn = Vector((1e9, 1e9, 1e9))
        mx = Vector((-1e9, -1e9, -1e9))
        n = 0
        for fi in fs:
            p = me.polygons[fi]
            n += len(p.vertices) - 2
            for vi in p.vertices:
                co = me.vertices[vi].co
                mn = Vector((min(mn.x, co.x), min(mn.y, co.y), min(mn.z, co.z)))
                mx = Vector((max(mx.x, co.x), max(mx.y, co.y), max(mx.z, co.z)))
        out[g] = (max(mx - mn), fs, n, mn.z, mx.z)
    return out


def find_trunk(barks):
    """The trunk: of the bark pieces that reach the ground (the lowest ~0.6 m of the tree), the
    tallest (the biggest piece can be a long branch)."""
    if not barks:
        return None
    zmin = min(v[3] for v in barks.values())
    grounded = {g: v for g, v in barks.items() if v[3] < zmin + 0.6}
    pool = grounded or barks
    return max(pool.items(), key=lambda kv: kv[1][4] - kv[1][3])[0]


def trunk_profile(me, faces, step=0.6):
    """The trunk's line and girth: [(centre x, centre y, z, radius)] every `step` m up the trunk
    piece. Each slice: its points' middle (the median first, then the mean of the points within
    2.5x the typical distance: a branch stub in the slice doesn't drag it), the girth the 75th
    percentile out; then the line smoothed, the girth never growing going up."""
    vs = {}
    for fi in faces:
        for vi in me.polygons[fi].vertices:
            vs[vi] = me.vertices[vi].co
    if not vs:
        return []
    pts = list(vs.values())
    z0 = min(v.z for v in pts)
    z1 = max(v.z for v in pts)
    rings = []
    z = z0
    while z <= z1 + 1e-3:
        band = [v for v in pts if abs(v.z - z) <= step * 0.6]
        if len(band) >= 3:
            xs = sorted(v.x for v in band)
            ys = sorted(v.y for v in band)
            mx, my = xs[len(xs) // 2], ys[len(ys) // 2]
            ds = sorted(math.hypot(v.x - mx, v.y - my) for v in band)
            typical = max(ds[len(ds) // 2], 1e-3)
            inl = [v for v in band if math.hypot(v.x - mx, v.y - my) <= typical * 2.5]
            cx = sum(v.x for v in inl) / len(inl)
            cy = sum(v.y for v in inl) / len(inl)
            di = sorted(math.hypot(v.x - cx, v.y - cy) for v in inl)
            rings.append([cx, cy, z, min(1.2, max(0.04, di[int(len(di) * 0.75)]))])
        z += step
    if len(rings) >= 3:                              # the line smoothed (three slices)
        sm = []
        for i in range(len(rings)):
            a, b = max(0, i - 1), min(len(rings) - 1, i + 1)
            sm.append([sum(rings[k][0] for k in range(a, b + 1)) / (b - a + 1), sum(rings[k][1] for k in range(a, b + 1)) / (b - a + 1)])
        rads = [r[3] for r in rings]
        for i in range(len(rings)):
            a, b = max(0, i - 1), min(len(rings) - 1, i + 1)
            rings[i][0], rings[i][1] = sm[i]
            rings[i][3] = sorted(rads[a:b + 1])[(b - a) // 2]
    for i in range(1, len(rings)):
        rings[i][3] = min(rings[i][3], rings[i - 1][3])
    if rings:
        rings[0][3] *= 1.12
        rings[-1][3] = max(0.02, rings[-1][3] * 0.6)
    return rings


def add_tube(bm, rings, sides, mat_index, every=1, tag_layer=None):
    """A closed-bottomed tapered tube through the rings into the bmesh (the bark's UVs: once
    round, along in 2 m repeats)."""
    uv = bm.loops.layers.uv.verify()
    rows = []
    for k, (cx, cy, z, r) in enumerate(rings[::every] if rings[-1] in rings[::every] else rings[::every] + [rings[-1]]):
        row = []
        for s in range(sides):
            a = s / sides * math.tau
            row.append(bm.verts.new((cx + math.cos(a) * r, cy + math.sin(a) * r, z)))
        rows.append((row, z))
    for k in range(len(rows) - 1):
        (ra, za), (rb, zb) = rows[k], rows[k + 1]
        for s in range(sides):
            s2 = (s + 1) % sides
            f = bm.faces.new((ra[s], ra[s2], rb[s2], rb[s]))
            f.material_index = mat_index
            f.smooth = True
            if tag_layer is not None:
                f[tag_layer] = 2                     # (the tube: already light, left out of the decimation)
            for loop, (u, v) in zip(f.loops, ((s / sides, za / 2.0), ((s + 1) / sides, za / 2.0), ((s + 1) / sides, zb / 2.0), (s / sides, zb / 2.0))):
                loop[uv].uv = (u, v)


def make_lod(obj, name, leaf_slots, bark_slots, target, scale_max, seed, groups, centres, bark_groups=None, trunk_rings=None, tube_sides=8, branches=True):
    """A copy of the tree at `target` triangles: leaf islands thinned (outer kept first) and grown,
    the bark decimated."""
    me = obj.data.copy()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    leaf_tris = sum(len(p.vertices) - 2 for p in me.polygons if p.material_index in leaf_slots)
    bark_tris = sum(len(p.vertices) - 2 for p in me.polygons if p.material_index not in leaf_slots)
    leaf_budget = int(target * 0.7) if leaf_tris else 0
    bark_budget = target - leaf_budget
    keep_f = min(1.0, leaf_budget / max(leaf_tris, 1))
    rng = random.Random(seed)
    bark_groups = bark_groups or {}
    bark_groups_top = max((v[0] for v in bark_groups.values()), default=0.0)
    far = 1.0
    if centres:
        far = max(math.hypot(c.x, c.y) for c in centres.values()) or 1.0
    keep = set()
    drop_faces = set()
    for g, fs in groups.items():
        c = centres[g]
        out = math.hypot(c.x, c.y) / far           # 0 at the trunk, 1 at the edge of the crown
        w = keep_f * (0.55 + 0.9 * out)            # (the outer ones kept more)
        if rng.random() < w:
            keep.add(g)
        else:
            drop_faces.update(fs)
    grow = min(scale_max, max(1.0, (1.0 / max(keep_f, 1e-3)) ** 0.5 * 0.8))
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    bm.verts.ensure_lookup_table()
    # the trunk (the biggest bark piece) tagged: it's decimated apart from the branches below
    piece = bm.faces.layers.int.new("piece")
    if bark_groups:
        trunk_g = find_trunk(bark_groups)
        for fi in bark_groups[trunk_g][1]:
            bm.faces[fi][piece] = 1
    # grow the kept cards about their centres (each card's verts once)
    if grow > 1.01:
        done = set()
        for g in keep:
            c = centres[g]
            for fi in groups[g]:
                for v in bm.faces[fi].verts:
                    if v.index not in done:
                        done.add(v.index)
                        v.co = c + (v.co - c) * grow
    # the bark: its pieces (trunk, branches, twigs) biggest first, kept while they fit ~4x the
    # bark budget (the decimation below takes them the rest of the way); the twigs go
    if bark_tris > bark_budget > 0 and bark_groups:
        # (each branch kept must keep ~30 triangles after the decimation, or it's a flat plank:
        # so only the biggest bark_budget / 30 of them stay)
        most = max(8, int(bark_budget * 0.6 / 30)) if branches else 0
        room = bark_budget * 4
        kept_n = 0
        for g, (size, fs, n, _z0, _z1) in sorted(bark_groups.items(), key=lambda kv: -kv[1][0]):
            if (size >= bark_groups_top * 0.5 and trunk_rings is None) or (room > 0 and kept_n < most and size < bark_groups_top):
                room -= n
                kept_n += 1
            else:
                drop_faces.update(fs)
    if trunk_rings and bark_groups:
        drop_faces.update(bark_groups[find_trunk(bark_groups)][1])
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in drop_faces], context="FACES_KEEP_BOUNDARY")
    if trunk_rings:
        add_tube(bm, trunk_rings, tube_sides, min(bark_slots) if bark_slots else 0, every=1 if tube_sides >= 8 else 2, tag_layer=piece)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    # the bark's seams welded (an FBX splits its vertices along the UV seams: open edges the
    # decimation can't collapse across, which fold the trunk into flaps)
    bark_verts = list({v for f in bm.faces if f.material_index in bark_slots for v in f.verts})
    if bark_verts:
        bmesh.ops.remove_doubles(bm, verts=bark_verts, dist=0.0008)
    bm.to_mesh(me)
    bm.free()
    # the bark decimated, the trunk and the branches each to their own share (one pass would
    # starve the trunk: it went to a sliver at the foot); only their own vertices, the leaf
    # cards untouched
    tags = me.attributes.get("piece")
    trunk_v, branch_v = set(), set()
    trunk_t = branch_t = 0
    for p in me.polygons:
        if p.material_index in bark_slots:
            if tags is not None and tags.data[p.index].value == 2:
                continue                                 # (the tube)
            if tags is not None and tags.data[p.index].value == 1:
                trunk_v.update(p.vertices)
                trunk_t += len(p.vertices) - 2
            else:
                branch_v.update(p.vertices)
                branch_t += len(p.vertices) - 2
    tube_v = set()
    if tags is not None:
        for p in me.polygons:
            if tags.data[p.index].value == 2:
                tube_v.update(p.vertices)
    branch_v -= trunk_v
    branch_v -= tube_v
    trunk_v -= tube_v
    trunk_budget = max(900, int(bark_budget * 0.4))
    branch_budget = max(200, bark_budget - trunk_budget)
    for gname, verts, have, want in (("trunk", trunk_v, trunk_t, trunk_budget), ("branches", branch_v, branch_t, branch_budget)):
        if have <= want or not verts:
            continue
        vg = o.vertex_groups.new(name=gname)
        vg.add(list(verts), 1.0, "REPLACE")
        mod = o.modifiers.new("thin", "DECIMATE")
        mod.ratio = max(0.004, want / have)
        mod.vertex_group = gname
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.ops.object.modifier_apply(modifier="thin")
        o.vertex_groups.clear()
    if tags is not None:
        me.attributes.remove(me.attributes["piece"])
    crown_normals(o, leaf_slots)
    tri = sum(len(p.vertices) - 2 for p in o.data.polygons)
    return o, tri, len(keep), len(groups), grow


def crown_normals(o, leaf_slots, amount=0.8):
    """The leaf cards' normals turned out from the middle of the crown (a cone for a tall tree):
    the crown is lit as one soft mass, the cards facing away from the sun not left black."""
    me = o.data
    leaf_polys = [p for p in me.polygons if p.material_index in leaf_slots]
    if not leaf_polys:
        return
    pts = [me.vertices[v].co for p in leaf_polys for v in p.vertices]
    cx = sum(v.x for v in pts) / len(pts)
    cy = sum(v.y for v in pts) / len(pts)
    zmin = min(v.z for v in pts)
    zmax = max(v.z for v in pts)
    cz = (zmin + zmax) * 0.5
    if hasattr(me, "use_auto_smooth"):
        me.use_auto_smooth = True
    if hasattr(me, "calc_normals_split"):
        me.calc_normals_split()
        normals = [l.normal.copy() for l in me.loops]
    else:
        normals = [n.vector.copy() for n in me.corner_normals]
    for p in leaf_polys:
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            out = Vector((co.x - cx, co.y - cy, (co.z - cz) * 0.35))
            if out.length < 1e-4:
                out = Vector((0, 0, 1))
            out = out.normalized() + Vector((0, 0, 0.35))
            normals[li] = (normals[li] * (1.0 - amount) + out.normalized() * amount).normalized()
    me.normals_split_custom_set(normals)


def render_billboard(obj, name, height_px, out_dir):
    """The tree from the side in even light (its colour, the shade inside its crown) on a clear
    ground: the far card's image."""
    scene = bpy.context.scene
    xs = [v.co.x for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    x0, x1 = min(xs), max(xs)
    w_m = x1 - x0
    h_m = max(zs)
    aspect = w_m / max(h_m, 0.1)
    w_px = max(64, int(height_px * aspect / 8) * 8)
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.cycles.transparent_max_bounces = 48
    scene.cycles.max_bounces = 3
    scene.render.film_transparent = True
    scene.render.resolution_x = w_px * 2
    scene.render.resolution_y = height_px * 2
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    world = scene.world or bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    bg.inputs["Strength"].default_value = 0.85
    sun = bpy.data.lights.get("bb_sun") or bpy.data.lights.new("bb_sun", "SUN")
    sun.energy = 1.6
    sun_o = bpy.data.objects.get("bb_sun") or bpy.data.objects.new("bb_sun", sun)
    if sun_o.name not in scene.collection.objects:
        scene.collection.objects.link(sun_o)
    sun_o.rotation_euler = (math.radians(50), 0, math.radians(20))
    cam_d = bpy.data.cameras.get("bb_cam") or bpy.data.cameras.new("bb_cam")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = max(h_m, w_m)
    cam = bpy.data.objects.get("bb_cam") or bpy.data.objects.new("bb_cam", cam_d)
    if cam.name not in scene.collection.objects:
        scene.collection.objects.link(cam)
    cam.location = ((x0 + x1) * 0.5, -60.0, h_m * 0.5)
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.camera = cam
    # only this tree in the picture
    for o in scene.objects:
        if o.type == "MESH":
            o.hide_render = o != obj
    path = os.path.join(out_dir, name + ".png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    img.scale(w_px, height_px)
    img.pack()
    for o in scene.objects:
        if o.type == "MESH":
            o.hide_render = False
    return img, x0, x1, h_m


def billboard_mesh(name, img, x0, x1, h_m):
    """Two crossed cards with the render on them (each spanning the tree as it was framed: x0..x1
    from the foot), each card two faces back to back (one-sided: each side its own normals, which
    lean out from the tree and up: a rounded crown in the light, from either side)."""
    me = bpy.data.meshes.new(name)
    verts, faces, uvs, nrm = [], [], [], []
    mid = (x0 + x1) * 0.5
    for ax, ay in ((1, 0), (0, 1)):
        plane_n = Vector((-ay, ax, 0.0)) * -1.0            # (the first card faces -Y, the second +X... either way)
        for side in (1.0, -1.0):
            b = len(verts)
            quad = [(x0, 0.0), (x1, 0.0), (x1, h_m), (x0, h_m)]
            for (u, z) in quad:
                verts.append((u * ax, u * ay, z))
            if side > 0:
                faces.append((b, b + 1, b + 2, b + 3))
            else:
                faces.append((b + 3, b + 2, b + 1, b))
            for (u, z) in quad:
                radial = Vector((ax, ay, 0.0)) * ((u - mid) / max(x1 - x0, 0.1))
                n = plane_n * side * 0.55 + radial * 0.6 + Vector((0.0, 0.0, 0.75))
                nrm.append(n.normalized())
            uvs += [(0, 0), (1, 0), (1, 1), (0, 1)]
    me.from_pydata(verts, [], faces)
    uv = me.uv_layers.new(name="UVMap")
    loop_n = []
    for li, loop in enumerate(me.loops):
        uv.data[li].uv = uvs[loop.vertex_index]
        loop_n.append(nrm[loop.vertex_index])
    if hasattr(me, "use_auto_smooth"):
        me.use_auto_smooth = True
    me.normals_split_custom_set(loop_n)
    m = _material(name + "_mat", img, leaf=True)
    m.use_backface_culling = True
    me.materials.append(m)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def base_origin(o):
    """The origin at the foot of the trunk (the bark's lowest metre, its middle), z at the lowest point."""
    me = o.data
    zs = [v.co.z for v in me.vertices]
    zmin = min(zs)
    low = [v.co for v in me.vertices if v.co.z < zmin + 1.0] or [v.co for v in me.vertices]
    cx = sum(v.x for v in low) / len(low)
    cy = sum(v.y for v in low) / len(low)
    me.transform(mathutils.Matrix.Translation(Vector((-cx, -cy, -zmin))))
    o.location = (0, 0, 0)


def convert(spec, src_first, out):
    import import_environment as ie            # (load/flatten helpers)
    srcs = [ie.source_path(s) for s in spec.get("srcs", [spec.get("src")])]
    src_dir = os.path.dirname(srcs[0])
    bb_dir = os.path.join(ie.WORK, "_billboards", spec["id"])
    os.makedirs(bb_dir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    report = []
    mats = None
    done_objs = []
    for si, src in enumerate(srcs):
        before = set(bpy.data.objects)
        ext = os.path.splitext(src)[1].lower()
        if ext == ".fbx":
            bpy.ops.import_scene.fbx(filepath=src)
        elif ext == ".blend":
            with bpy.data.libraries.load(src, link=False) as (data_from, data_to):
                data_to.objects = [n for n in data_from.objects]
            for ob in data_to.objects:
                if ob is not None:
                    bpy.context.scene.collection.objects.link(ob)
        new = [ob for ob in bpy.data.objects if ob not in before]
        extras = [ob.name for ob in new if ob.type != "MESH"]
        trees = [ob for ob in new if ob.type == "MESH"]
        if spec.get("objects"):
            import fnmatch
            trees = [ob for ob in trees if any(fnmatch.fnmatch(ob.name, p) for p in spec["objects"])]
        ie.flatten(trees, float(spec.get("scale", 1.0)))
        if mats is None:
            mats = shared_materials(spec, src_dir, [s.material for t in trees for s in t.material_slots if s.material])
        for ti, tree in enumerate(sorted(trees, key=lambda t: t.name)):
            vname = spec.get("names", {}).get(tree.name) or ("%s_%02d" % (spec["id"], len(done_objs) // 3 + 1))
            # the tree's own slots: leaf or bark, then every slot given the shared material
            leaf_slots, bark_slots = set(), set()
            leaf2_names = [n.lower() for n in spec.get("leaf2_sets", ["needle2"])]
            for i, s in enumerate(tree.material_slots):
                leafy = s.material is not None and _is_leaf(s.material, spec)
                (leaf_slots if leafy else bark_slots).add(i)
                if leafy:
                    names = [os.path.basename(im.filepath or im.name).lower() for im in _images(s.material)]
                    two = "leaf2" in mats and any(any(k in n for k in leaf2_names) for n in names)
                    s.material = mats["leaf2" if two else "leaf"]
                else:
                    s.material = mats["bark"]
            # one slot per shared material (two bark slots made two draws)
            uniq = []
            remap = {}
            for i, s in enumerate(tree.material_slots):
                if s.material not in uniq:
                    uniq.append(s.material)
                remap[i] = uniq.index(s.material)
            if len(uniq) < len(tree.material_slots):
                idx = [remap[p.material_index] for p in tree.data.polygons]
                tree.data.materials.clear()
                for m in uniq:
                    tree.data.materials.append(m)
                tree.data.polygons.foreach_set("material_index", idx)
                leaf_slots = {i for i, m in enumerate(uniq) if m.name.startswith("leaf")}
                bark_slots = {i for i, m in enumerate(uniq) if not m.name.startswith("leaf")}
            base_origin(tree)
            src_tris = sum(len(p.vertices) - 2 for p in tree.data.polygons)
            groups, centres = leaf_islands(tree.data, leaf_slots)
            barks = bark_pieces(tree.data, bark_slots)
            rings = None
            if barks and spec.get("trunk_tube", True):
                rings = trunk_profile(tree.data, barks[find_trunk(barks)][1]) or None
            lods = []
            for li, (key, budget) in enumerate((("LOD0", spec.get("lod0", 20000)), ("LOD1", spec.get("lod1", 4000)))):
                o, tri, kept, total, grow = make_lod(tree, "%s_%s" % (vname, key), leaf_slots, bark_slots, budget,
                    spec.get("leaf_scale_max", LEAF_SCALE_MAX) * (1.0 if li == 0 else 1.35), hash((vname, key)) & 0xffff,
                    groups, centres, barks, rings, 8 if li == 0 else 6, li == 0)
                o.data.name = o.name
                lods.append(o)
                report.append("%s %s: %d -> %d tris (%d of %d leaf cards kept, grown x%.2f; %d bark pieces)" % (
                    vname, key, src_tris, tri, kept, total, grow, len(barks)))
            img, x0, x1, h_m = render_billboard(lods[0], vname + "_BB", int(spec.get("billboard", 512)), bb_dir)
            billboard_mesh(vname + "_BB", img, x0, x1, h_m)
            report.append("%s: %.1f m tall, %.1f m across" % (vname, h_m, x1 - x0))
            done_objs += lods
            bpy.data.objects.remove(tree, do_unlink=True)
        for n in extras:
            if n in bpy.data.objects:
                bpy.data.objects.remove(bpy.data.objects[n], do_unlink=True)
        for ob in [ob for ob in bpy.data.objects if ob.type == "MESH" and ob not in done_objs and not ob.name.endswith("_BB")]:
            bpy.data.objects.remove(ob, do_unlink=True)            # (meshes that weren't trees)
        try:
            bpy.data.orphans_purge(do_recursive=True)
        except Exception:
            pass
    # the textures at the spec's size (the billboards already are), then out
    mx = int(spec.get("max_tex", 1024))
    for img in bpy.data.images:
        if img.size[0] and max(img.size) > mx:
            f = mx / float(max(img.size))
            img.scale(max(1, int(img.size[0] * f)), max(1, int(img.size[1] * f)))
    for ob in list(bpy.context.scene.objects):
        if ob.type != "MESH":
            bpy.data.objects.remove(ob, do_unlink=True)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True, export_apply=True,
        export_materials="EXPORT", export_image_format=spec.get("tex_format", "webp").upper())
    print("\n".join(report))
    print("wrote %s (%.1f MB)" % (out, os.path.getsize(out) / 1e6))
