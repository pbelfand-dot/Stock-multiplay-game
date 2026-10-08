"""Buildings for the game (tools/import_environment.py's "building" mode): each building in the
owner's city packs made into a light model with one material, so a street of them is a handful
of draws rather than hundreds:

  * the building's meshes in world space, its stray bits (loose parts far off the building) cut,
    its origin at the middle of its foot
  * a light copy: flat areas dissolved, then collapsed to the spec's triangles ("tris")
  * that copy laid out as facades (each face onto the side it faces: +-X, +-Y, the roof, in one
    image at one scale) and painted from pictures of the full building from each side: its
    colour (the diffuse colour pass), its ambient occlusion (the window reveals, the balconies'
    shade) multiplied in, and its glass in the alpha (the game lights some windows at night
    from it). From outside a wall behind a railing gets what you see there: the railing.
  * one GLB per building: assets/environment_runtime/<out>/<name>.glb, its texture sized by
    its area (spec "tex": the most, px)

Spec: {"mode": "building", "srcs": [blend files, relative to assets/environment_work/],
"textures": the pack's texture folder (missing images found there), "names": {source file
stem or object name: part name}, "out": a folder, "tris", "tex", "ao_samples"}.
The source files are only read (opened with scripts off: blender -b -Y).
"""
import bpy, bmesh, math, os, re
import numpy as np

GLASS = re.compile(r"glass|window|vitre|verre|glas|fenetre|windows", re.I)


def _world_copy(o, name):
    """The object's evaluated mesh (modifiers applied) in world space, as a new object."""
    dg = bpy.context.evaluated_depsgraph_get()
    e = o.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(e, preserve_all_data_layers=True, depsgraph=dg)
    me.transform(o.matrix_world)
    me.name = name
    # (the packs were saved by a newer Blender: custom normals that don't survive the copy; a
    # building's faces are flat anyway)
    me.validate(verbose=False, clean_customdata=True)
    _flat(me)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def _flat(me):
    if getattr(me, "has_custom_normals", False):
        try:
            me.free_normals_split()
        except Exception:
            pass
        attr = me.attributes.get("custom_normal")
        if attr is not None:
            me.attributes.remove(attr)
    for p in me.polygons:
        p.use_smooth = False


def _clean_outliers(ob, pad=25.0):
    """Cuts loose parts well away from the building (the main part: the one with the most
    vertices; anything whose middle is more than pad m outside its box goes)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    seen = set()
    parts = []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack = [v]
        seen.add(v.index)
        comp = []
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y.index not in seen:
                    seen.add(y.index)
                    stack.append(y)
        parts.append(comp)
    main = max(parts, key=len)
    lo = [min(v.co[k] for v in main) for k in range(3)]
    hi = [max(v.co[k] for v in main) for k in range(3)]
    gone = []
    for comp in parts:
        c = [sum(v.co[k] for v in comp) / len(comp) for k in range(3)]
        if any(c[k] < lo[k] - pad or c[k] > hi[k] + pad for k in range(2)) or c[2] < lo[2] - pad or c[2] > hi[2] + pad:
            gone.extend(comp)
    if gone:
        bmesh.ops.delete(bm, geom=list(set(gone)), context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()
    return lo, hi, len(parts), len(set(gone))


def _base_origin(ob):
    """Origin at the middle of the building's foot (its lowest point)."""
    vs = [v.co for v in ob.data.vertices]
    x0, x1 = min(v.x for v in vs), max(v.x for v in vs)
    y0, y1 = min(v.y for v in vs), max(v.y for v in vs)
    z0 = min(v.z for v in vs)
    shift = (-(x0 + x1) * 0.5, -(y0 + y1) * 0.5, -z0)
    ob.data.transform(__import__("mathutils").Matrix.Translation(shift))
    return shift


def _tris(ob):
    ob.data.calc_loop_triangles()
    return len(ob.data.loop_triangles)


def _decimate(ob, target):
    bpy.context.view_layer.objects.active = ob
    if _tris(ob) > target:
        m = ob.modifiers.new("dissolve", "DECIMATE")
        m.decimate_type = "DISSOLVE"
        m.angle_limit = math.radians(0.6)
        m.delimit = {"MATERIAL", "SEAM"}
        bpy.ops.object.modifier_apply(modifier=m.name)
    t = _tris(ob)
    if t > target:
        m = ob.modifiers.new("collapse", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = max(0.01, target / float(t))
        bpy.ops.object.modifier_apply(modifier=m.name)
    # (triangulated: the bake's and the game's faces the same)
    m = ob.modifiers.new("tri", "TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier=m.name)
    ob.data.validate(verbose=False, clean_customdata=True)
    _flat(ob.data)
    return _tris(ob)


def _shelf(rects, s, size):
    """Shelf-packs rects ([w, h] m) at s px a metre into a size x size image, PAD px apart:
    [x, y] px each, or None if they don't fit."""
    order = sorted(range(len(rects)), key=lambda i: -rects[i][1])
    out = [None] * len(rects)
    x = y = PAD
    shelf = 0
    for i in order:
        w = int(math.ceil(rects[i][0] * s)) + PAD
        h = int(math.ceil(rects[i][1] * s)) + PAD
        if x + w > size:
            x = PAD
            y += shelf
            shelf = 0
        if y + h > size or w > size:
            return None
        out[i] = [x, y]
        x += w
        shelf = max(shelf, h)
    return out


PAD = 8
DUMP = 0.9                            # m: the cell for the faces seen from below (soffits): a little square
SIDES = [(0, 1), (0, -1), (1, 1), (1, -1), (2, 1)]   # +X, -X, +Y, -Y, the roof
UVAX = {0: (1, 2), 1: (0, 2), 2: (0, 1)}


def _layout(ob, size):
    """The facade image's layout: a cell for each side (+-X, +-Y) and the roof, the building's
    size there in metres, packed at one scale into size x size. {lo, hi, s, pos}."""
    from mathutils import Vector
    vs = [v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    ext = hi - lo
    cells = [[ext[UVAX[a][0]], ext[UVAX[a][1]]] for a, sg in SIDES] + [[DUMP, DUMP]]
    s_lo, s_hi = 1.0, 200.0
    for _ in range(30):
        mid = (s_lo + s_hi) * 0.5
        if _shelf(cells, mid, size) is None:
            s_hi = mid
        else:
            s_lo = mid
    return {"lo": lo, "hi": hi, "ext": ext, "s": s_lo, "pos": _shelf(cells, s_lo, size), "cells": cells, "size": size}


def _side_uv(co, side, L):
    """Where a point lands in a side's cell, in m from its corner (as its camera sees it: not mirrored)."""
    a, sg = SIDES[side]
    ua, va = UVAX[a]
    lo, hi = L["lo"], L["hi"]
    u = (co[ua] - lo[ua]) if (sg > 0) != (a == 1) else (hi[ua] - co[ua])
    return u, co[va] - lo[va]


def _cube_uv(ob, L):
    """Each face onto the side it faces (the roof for the tops, a small cell for the undersides)."""
    me = ob.data
    for uvl in list(me.uv_layers):
        me.uv_layers.remove(uvl)
    uv = me.uv_layers.new(name="UVMap")
    size, s, pos = L["size"], L["s"], L["pos"]
    under = 0
    for p in me.polygons:
        n = p.normal
        a = max(range(3), key=lambda k: abs(n[k]))
        sg = 1 if n[a] > 0 else -1
        side = SIDES.index((a, sg)) if (a, sg) in SIDES else -1
        under += 1 if side < 0 else 0
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if side >= 0:
                u, v = _side_uv(co, side, L)
                x, y = pos[side][0] + u * s, pos[side][1] + v * s
            else:
                ua, va = UVAX[2]
                x = pos[5][0] + (co[ua] - L["lo"][ua]) / max(L["ext"][ua], 0.01) * DUMP * s
                y = pos[5][1] + (co[va] - L["lo"][va]) / max(L["ext"][va], 0.01) * DUMP * s
            uv.data[li].uv = (x / size, y / size)
    return under


def _render_sides(src, L, tmp, samples):
    """Pictures of the full building from each side (orthographic, from outside): its colour
    (the diffuse colour pass), its ambient occlusion and its glass (a second picture, the
    glass glowing white and the rest black), into the layout: a size x size x 4 array (RGB:
    colour x occlusion, A: the glass)."""
    import mathutils
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 2
    scene.render.film_transparent = True
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    world = scene.world or bpy.data.worlds.new("w")
    scene.world = world
    world.light_settings.distance = 1.2                     # (the occlusion's reach: window reveals, balconies)
    vl = scene.view_layers[0]
    vl.use_pass_diffuse_color = True
    vl.use_pass_ambient_occlusion = True
    for o in scene.objects:
        if o.type == "MESH":
            o.hide_render = o != src
        if o.type == "LIGHT":
            o.hide_render = True
    scene.use_nodes = True
    nt = scene.node_tree
    nt.nodes.clear()
    rl = nt.nodes.new("CompositorNodeRLayers")
    fo = nt.nodes.new("CompositorNodeOutputFile")
    fo.base_path = tmp
    fo.format.file_format = "PNG"
    fo.format.color_mode = "RGBA"
    fo.file_slots.clear()
    for slot in ("col", "ao", "img"):
        fo.file_slots.new(slot)
    nt.links.new(rl.outputs["DiffCol"], fo.inputs["col"])
    nt.links.new(rl.outputs["AO"], fo.inputs["ao"])
    nt.links.new(rl.outputs["Image"], fo.inputs["img"])
    cam_d = bpy.data.cameras.new("side_cam")
    cam_d.type = "ORTHO"
    cam_d.clip_end = 2000.0
    cam = bpy.data.objects.new("side_cam", cam_d)
    scene.collection.objects.link(cam)
    scene.camera = cam
    size, s, pos = L["size"], L["s"], L["pos"]
    lo, hi, ext = L["lo"], L["hi"], L["ext"]
    mid = (lo + hi) * 0.5
    atlas = np.zeros((size, size, 4), dtype=np.float32)
    saved = [sl.material for sl in src.material_slots]
    for k, (a, sg) in enumerate(SIDES):
        w_m, h_m = L["cells"][k]
        w_px, h_px = max(4, int(round(w_m * s))), max(4, int(round(h_m * s)))
        scene.render.resolution_x = w_px
        scene.render.resolution_y = h_px
        cam_d.ortho_scale = max(w_m, h_m)
        d = mathutils.Vector((0.0, 0.0, 0.0))
        d[a] = sg
        cam.location = mid + d * (ext[a] * 0.5 + 60.0)
        if a == 2:
            cam.rotation_euler = (0.0, 0.0, 0.0)
        else:
            cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        layers = {}
        for pass_no, mode in enumerate(("colour", "glass")):
            if mode == "glass":
                _glass_materials(src)
                scene.cycles.samples = 1
            else:
                for i, sl in enumerate(src.material_slots):
                    sl.material = saved[i]
                scene.cycles.samples = samples
            for f in os.listdir(tmp):
                os.remove(os.path.join(tmp, f))
            bpy.ops.render.render(write_still=False)
            for slot in ("col", "ao", "img"):
                fn = [f for f in os.listdir(tmp) if f.startswith(slot)]
                if fn:
                    im = bpy.data.images.load(os.path.join(tmp, fn[0]))
                    layers[mode + slot] = _pixels(im).copy()
                    bpy.data.images.remove(im)
        for i, sl in enumerate(src.material_slots):
            sl.material = saved[i]
        col = layers["colourcol"]
        ao = layers["colourao"]
        glass = layers["glassimg"]
        cell = np.zeros((h_px, w_px, 4), dtype=np.float32)
        cell[..., :3] = np.clip(col[..., :3] * (0.35 + 0.65 * ao[..., :1]), 0.0, 1.0)
        cell[..., 3] = (col[..., 3] > 0.5).astype(np.float32)    # (the building's silhouette: filled outward below)
        cell = _dilate(cell, 24)
        x0, y0 = pos[k]
        atlas[y0:y0 + h_px, x0:x0 + w_px, :3] = cell[..., :3]
        atlas[y0:y0 + h_px, x0:x0 + w_px, 3] = np.clip(glass[..., 0], 0.0, 1.0)
    # the undersides' cell: the walls' average colour
    x0, y0 = pos[5]
    dn = int(DUMP * s) + 1
    filled = atlas[..., :3][atlas[..., :3].sum(axis=2) > 0.01]
    atlas[y0:y0 + dn, x0:x0 + dn, :3] = filled.mean(axis=0) * 0.6 if len(filled) else 0.4
    bpy.data.objects.remove(cam, do_unlink=True)
    return atlas


def _dilate(cell, n):
    """Pushes the colour out past the silhouette's edge n px (no dark seams where the faces
    meet it); the alpha stays the silhouette."""
    rgb = cell[..., :3].copy()
    known = cell[..., 3] > 0.5
    for _ in range(n):
        if known.all():
            break
        acc = np.zeros_like(rgb)
        cnt = np.zeros(known.shape, dtype=np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            k = np.roll(known, (dy, dx), axis=(0, 1))
            acc += np.roll(rgb, (dy, dx), axis=(0, 1)) * k[..., None]
            cnt += k
        grow = (~known) & (cnt > 0)
        rgb[grow] = acc[grow] / cnt[grow][:, None]
        known = known | grow
    out = cell.copy()
    out[..., :3] = rgb
    return out


def _transfer_normals(low, src):
    """The light copy's normals from the full building's flat faces (its walls are shaded as
    flat walls even where the collapse left a triangle a little off their plane)."""
    me = low.data
    if hasattr(me, "use_auto_smooth"):
        me.use_auto_smooth = True
        me.auto_smooth_angle = math.radians(180.0)
    for p in me.polygons:
        p.use_smooth = True
    m = low.modifiers.new("normals", "DATA_TRANSFER")
    m.object = src
    m.use_loop_data = True
    m.data_types_loops = {"CUSTOM_NORMAL"}
    m.loop_mapping = "POLYINTERP_NEAREST"
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.modifier_apply(modifier=m.name)


def _area(ob):
    return sum(p.area for p in ob.data.polygons)


def _pixels(img):
    a = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(img.size[1], img.size[0], 4)


def _glass_materials(src):
    """Swaps the full building's materials for the window mask's bake (glass emits white, the
    rest black): returns the originals to put back."""
    saved = [s.material for s in src.material_slots]
    white = bpy.data.materials.new("mask_glass")
    black = bpy.data.materials.new("mask_wall")
    for m, c in ((white, 1.0), (black, 0.0)):
        m.use_nodes = True
        nt = m.node_tree
        nt.nodes.clear()
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs["Color"].default_value = (c, c, c, 1.0)
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(em.outputs[0], out.inputs[0])
    n_glass = 0
    for i, s in enumerate(src.material_slots):
        m = saved[i]
        glass = m is not None and (GLASS.search(m.name) is not None or _is_glass(m))
        n_glass += 1 if glass else 0
        s.material = white if glass else black
    return saved, n_glass


def _is_glass(m):
    if not m.use_nodes:
        return False
    for n in m.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            tr = n.inputs.get("Transmission Weight") or n.inputs.get("Transmission")
            if tr is not None and not tr.is_linked and tr.default_value > 0.5:
                return True
            al = n.inputs.get("Alpha")
            if al is not None and not al.is_linked and al.default_value < 0.7:
                return True
        if n.type == "BSDF_GLASS":
            return True
    return False


def convert_building(o, name, out_path, target, tex_max, samples):
    src = _world_copy(o, name + "_src")
    lo, hi, n_parts, n_gone = _clean_outliers(src)
    shift = _base_origin(src)
    low = src.copy()
    low.data = src.data.copy()
    low.name = name
    low.data.name = name
    bpy.context.scene.collection.objects.link(low)
    src_tris = _tris(src)
    t = _decimate(low, target)
    _transfer_normals(low, src)
    area = _area(low)
    # the image: the smaller one if it still gives 24 px a metre
    px = tex_max
    L = _layout(low, px)
    if tex_max >= 2048 and L["s"] * 0.5 >= 24.0:
        px = tex_max // 2
        L = _layout(low, px)
    s = L["s"]
    hidden = _cube_uv(low, L)
    tmp = os.path.join(bpy.app.tempdir or "/tmp", "bld_" + name)
    os.makedirs(tmp, exist_ok=True)
    final = _render_sides(src, L, tmp, samples)
    n_glass = int((final[..., 3] > 0.5).sum())
    # its one material: the facade image
    low.data.materials.clear()
    mat = bpy.data.materials.new(name + "_mat")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    low.data.materials.append(mat)
    out_img = bpy.data.images.new(name + "_albedo", px, px, alpha=True)
    out_img.pixels.foreach_set(final.ravel())
    out_img.pack()
    tex.image = out_img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.82
    if bsdf.inputs.get("Specular IOR Level"):
        bsdf.inputs["Specular IOR Level"].default_value = 0.35
    mat.blend_method = "OPAQUE"
    # export this building alone
    for ob in bpy.context.scene.objects:
        ob.select_set(ob == low)
    bpy.context.view_layer.objects.active = low
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", export_yup=True, use_selection=True,
        export_apply=True, export_materials="EXPORT", export_image_format="WEBP")
    d = low.dimensions
    print("building %-10s %7d -> %6d tris, %d px at %.1f px/m (%d faces underneath), %d loose parts (%d verts cut), %d glass px, %.1f x %.1f x %.1f m -> %s (%.1f MB)" % (
        name, src_tris, t, px, s, hidden, n_parts, n_gone, n_glass, d.x, d.y, d.z, os.path.basename(out_path), os.path.getsize(out_path) / 1e6))
    bpy.data.objects.remove(src, do_unlink=True)
    low.hide_render = True
    low.hide_set(True)
    return {"name": name, "tris": t, "size": [d.x, d.z, d.y], "px": px}


def convert(spec, src_path, work, runtime):
    """One source file's buildings (each mesh object a building)."""
    bpy.ops.wm.open_mainfile(filepath=src_path, load_ui=False, use_scripts=False)
    tdir = os.path.join(work, spec["textures"])
    try:
        bpy.ops.file.find_missing_files(directory=tdir)
    except Exception as e:
        print("find_missing_files: %s" % e)
    missing = [i.name for i in bpy.data.images if i.source == "FILE" and not os.path.exists(bpy.path.abspath(i.filepath))]
    stem = os.path.splitext(os.path.basename(src_path))[0]
    meshes = sorted([o for o in bpy.context.scene.objects if o.type == "MESH"], key=lambda o: o.name)
    names = spec.get("names", {})
    out = []
    for k, o in enumerate(meshes):
        name = names.get(o.name) or names.get(stem + ":" + o.name) or (names.get(stem, stem) + ("" if len(meshes) == 1 else "abcdefgh"[k]))
        out.append(convert_building(o, name, os.path.join(runtime, spec["out"], name + ".glb"),
            int(spec.get("tris", 15000)), int(spec.get("tex", 2048)), int(spec.get("ao_samples", 16))))
    print("missing images after the search: %d %s" % (len(missing), missing[:6]))
    return out
