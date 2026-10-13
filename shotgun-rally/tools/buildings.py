"""Buildings for the game (tools/import_environment.py's "building" mode): each building in the
owner's city packs made into a light model with one material, so a street of them is a handful
of draws rather than hundreds:

  * the building's meshes in world space, its stray bits (loose parts far off the building) cut,
    its origin at the middle of its foot
  * a light copy: flat areas dissolved, then collapsed to the spec's triangles ("tris"), its own
    materials and UVs kept through it, shaded from its own faces (every normal on the side its
    face is wound to)
  * that copy unwrapped (a UV map of its own: Smart UV Project, every face its own place at one
    scale) and its materials baked into one image by Cycles, face by face from the face itself
    (no camera): its colour (the diffuse colour pass), a little of its ambient occlusion
    multiplied in (the window reveals, the balconies' shade) and its glass in the alpha (the
    game lights some windows at night from it). Each face gets its own material's look: a
    balcony's underside, a window's reveal, a courtyard wall, a slanted or curved wall alike.
    (Until 2026-10 the faces were painted from five orthographic pictures, each face from the
    side it faced most: anything hidden from those cameras or oblique to them came out smeared
    or wrong, and the occlusion was strong enough to leave dark blotches: "distorted".)
  * one GLB per building: assets/environment_runtime/<out>/<name>.glb, its texture "tex" px (half
    that where it still gives 24 px a metre; "tex_big" where "tex" would give a big building
    under BIG_BELOW px a metre), exported as PNG and made WEBP by tools/glb_webp.py
  * its source's measurements (its bounds after the stray bits are cut, its triangles) in the
    report (REPORT, JSON): data/environment_assets.json's "src_size" / "src_tris", which
    tests/city_check.gd holds the game's mesh to

Spec: {"mode": "building", "srcs": [blend files, relative to assets/environment_work/],
"textures": the pack's texture folder (missing images found there), "names": {source file
stem or object name: part name}, "out": a folder, "tris", "tex", "tex_big", "ao_samples"}.
The source files are only read (opened with scripts off: blender -b -Y).
"""
import bpy, bmesh, json, math, os, re, shutil, subprocess, tempfile
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))

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
    # (vertices and edges that are no face's: never drawn or exported, but they counted in the
    # building's measured size - 1.6 m too deep on one)
    bm = bmesh.new()
    bm.from_mesh(me)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=[e for e in bm.edges if not e.link_faces], context="EDGES")
    bmesh.ops.delete(bm, geom=[v for v in loose if v.is_valid], context="VERTS")
    bm.to_mesh(me)
    bm.free()
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
    vertices; anything whose middle is more than pad m outside its box across, or below its
    foot, goes). Anything above it stays: a tower on its podium is a part of its own with fewer
    vertices than the podium (Building2024_18: its 200 m tower was cut, a podium left)."""
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
        if any(c[k] < lo[k] - pad or c[k] > hi[k] + pad for k in range(2)) or c[2] < lo[2] - pad:
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
        m.delimit = {"MATERIAL", "SEAM", "UV"}                  # (its UVs too: the bake reads its materials through them)
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


def _unwrap(low):
    """A UV map of the light copy's own ("bake", made the active and render one: the bake writes
    through it; the materials read their own by name, _pin_uvs): Smart UV Project, every face
    at one scale (texel density the same all over), the islands packed again a pixel apart at 2048."""
    me = low.data
    _pin_uvs(low, me.uv_layers.active.name if me.uv_layers.active else "")
    uv = me.uv_layers.new(name="bake")
    me.uv_layers.active = uv
    uv.active_render = True                 # (Cycles bakes through the render UV map; the materials read theirs by name now)
    for o in bpy.context.scene.objects:
        o.select_set(o == low)
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.003, area_weight=0.0,
        correct_aspect=True, scale_to_bounds=False)
    # (Smart UV Project's own packing left ~90 % of the image empty with a building's thousands of
    # islands: packed again, tightly, turned any way, a pixel apart at 2048: ~45 % of it used)
    bpy.context.scene.tool_settings.use_uv_select_sync = True    # (every selected face's UVs: headless there's no UV editor's selection)
    bpy.ops.uv.pack_islands(rotate=True, rotate_method="ANY", scale=True, margin_method="FRACTION",
        margin=0.0005, shape_method=PACK_SHAPE)
    bpy.ops.object.mode_set(mode="OBJECT")
    return uv


def _pin_uvs(low, name):
    """Every texture the materials read, read through the source's own UV map by name (an Image
    Texture with nothing in its Vector, a Normal Map's map unset: the render-active map, which
    becomes the bake's own)."""
    if not name:
        return
    for sl in low.material_slots:
        m = sl.material
        if m is None or not m.use_nodes:
            continue
        nt = m.node_tree
        for n in list(nt.nodes):
            if n.type == "TEX_IMAGE" and n.name != "_bake_target" and not n.inputs["Vector"].is_linked:
                u = nt.nodes.new("ShaderNodeUVMap")
                u.uv_map = name
                nt.links.new(u.outputs["UV"], n.inputs["Vector"])
            elif n.type == "NORMAL_MAP" and not n.uv_map:
                n.uv_map = name


def _uv_area(me, uv):
    tot = 0.0
    me.calc_loop_triangles()
    d = uv.data
    for t in me.loop_triangles:
        a, b, c = (d[i].uv for i in t.loops)
        tot += abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) * 0.5
    return tot


def _targets(low, img):
    """Every material on the copy gets the image as its active Image Texture node (unlinked: the
    bake's target, not part of the shading)."""
    for sl in low.material_slots:
        m = sl.material
        if m is None:
            continue
        m.use_nodes = True
        nt = m.node_tree
        n = nt.nodes.get("_bake_target")
        if n is None:
            n = nt.nodes.new("ShaderNodeTexImage")
            n.name = "_bake_target"
        n.image = img
        n.select = True
        nt.nodes.active = n


def _bake(low, kind, img, samples, others):
    scene = bpy.context.scene
    scene.cycles.samples = samples
    _targets(low, img)
    for o in others:
        o.hide_render = True
    for o in bpy.context.scene.objects:
        o.select_set(o == low)
    bpy.context.view_layer.objects.active = low
    kw = {"type": kind, "margin": 16, "margin_type": "EXTEND", "use_clear": True, "target": "IMAGE_TEXTURES"}
    if kind == "DIFFUSE":
        kw["pass_filter"] = {"COLOR"}
    bpy.ops.object.bake(**kw)
    return _pixels(img).copy()


def _own_normals(low):
    """The light copy shaded from its own faces (smooth up to 30 degrees, sharp beyond), so
    every normal is on the side its face is wound to. (Its normals were copied from the full
    building's nearest face: where two faces lie back to back - a balcony slab, a sill, a panel
    modelled both sides - the copy took the wrong one's on up to 15 % of a building, lit those
    faces from behind and baked their occlusion from inside: dark blotches.)"""
    me = low.data
    if hasattr(me, "use_auto_smooth"):
        me.use_auto_smooth = True
        me.auto_smooth_angle = math.radians(30.0)
    if hasattr(me, "free_normals_split"):
        me.free_normals_split()
    if me.has_custom_normals:
        bpy.context.view_layer.objects.active = low
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    for p in me.polygons:
        p.use_smooth = True


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


def convert_building(o, name, out_path, target, tex_max, samples, tex_big=0):
    src = _world_copy(o, name + "_src")
    lo, hi, n_parts, n_gone = _clean_outliers(src)
    shift = _base_origin(src)
    sd = src.dimensions
    src_size = [round(sd.x, 2), round(sd.z, 2), round(sd.y, 2)]           # (as the game's: x, up, depth)
    low = src.copy()
    low.data = src.data.copy()
    low.name = name
    low.data.name = name
    bpy.context.scene.collection.objects.link(low)
    src_tris = _tris(src)
    t = _decimate(low, target)
    _own_normals(low)
    area = _area(low)
    uv = _unwrap(low)
    uv_area = max(_uv_area(low.data, uv), 1e-6)
    # the image: the smaller one if it still gives 24 px a metre, the bigger (tex_big) for a big
    # building that would get under BIG_BELOW px a metre
    px = tex_max
    if tex_max >= 2048 and (tex_max // 2) * math.sqrt(uv_area / area) >= 24.0:
        px = tex_max // 2
    elif tex_big > tex_max and tex_max * math.sqrt(uv_area / area) < BIG_BELOW:
        px = tex_big
    s = px * math.sqrt(uv_area / area)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.use_denoising = False
    scene.render.bake.use_selected_to_active = False
    world = scene.world or bpy.data.worlds.new("w")
    scene.world = world
    world.light_settings.distance = 1.2                     # (the occlusion's reach: window reveals, balconies)
    others = [ob for ob in scene.objects if ob != low and ob.type == "MESH" and not ob.hide_render]
    imgs = {k: bpy.data.images.new("%s_%s" % (name, k), px, px, alpha=True, float_buffer=False) for k in ("col", "ao", "glass")}
    col = _bake(low, "DIFFUSE", imgs["col"], 4, others)
    ao = _bake(low, "AO", imgs["ao"], samples, others)
    saved, n_glass_mats = _glass_materials(low)
    glass = _bake(low, "EMIT", imgs["glass"], 1, others)
    for i, sl in enumerate(low.material_slots):
        sl.material = saved[i]
    for ob in others:
        ob.hide_render = False
    final = np.zeros((px, px, 4), dtype=np.float32)
    final[..., :3] = np.clip(col[..., :3] * (0.8 + 0.2 * ao[..., :1]), 0.0, 1.0)
    final[..., 3] = np.clip(glass[..., 0], 0.0, 1.0)
    n_glass = int((final[..., 3] > 0.5).sum())
    # only its own UV map left, and one material: the baked image
    me = low.data
    for l in [l for l in me.uv_layers if l.name != "bake"]:
        me.uv_layers.remove(l)
    me.uv_layers["bake"].name = "UVMap"
    low.data.materials.clear()
    mat = bpy.data.materials.new(name + "_mat")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    low.data.materials.append(mat)
    # (the image through a PNG on disk, exported as PNG and made WEBP after, tools/glb_webp.py:
    # Blender 4.0's exporter wrote this one as WEBP in rows of smeared colour)
    gen = bpy.data.images.new(name + "_albedo_gen", px, px, alpha=True)
    gen.pixels.foreach_set(final.ravel())
    tmp = os.path.join(tempfile.mkdtemp(prefix="bld_"), name + "_albedo.png")
    gen.filepath_raw = tmp
    gen.file_format = "PNG"
    gen.save()
    bpy.data.images.remove(gen)
    out_img = bpy.data.images.load(tmp)
    out_img.name = name + "_albedo"
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
        export_apply=True, export_materials="EXPORT", export_image_format="AUTO")
    r = subprocess.run(["python3", "-I", os.path.join(HERE, "glb_webp.py"), out_path], capture_output=True, text=True)
    print((r.stdout + r.stderr).strip())
    shutil.rmtree(os.path.dirname(tmp), ignore_errors=True)
    d = low.dimensions
    print("building %-10s %7d -> %6d tris, %d px at %.1f px/m (UVs %.0f %% of the image), %d loose parts (%d verts cut), %d glass px (%d glass materials), %.1f x %.1f x %.1f m (source %.1f x %.1f x %.1f) -> %s (%.1f MB)" % (
        name, src_tris, t, px, s, uv_area * 100.0, n_parts, n_gone, n_glass, n_glass_mats, d.x, d.y, d.z, sd.x, sd.y, sd.z, os.path.basename(out_path), os.path.getsize(out_path) / 1e6))
    bpy.data.objects.remove(src, do_unlink=True)
    low.hide_render = True
    low.hide_set(True)
    for img in imgs.values():
        bpy.data.images.remove(img)
    row = {"name": name, "tris": t, "size": [round(d.x, 1), round(d.z, 1), round(d.y, 1)], "px": px, "px_per_m": round(s, 1),
        "src_size": src_size, "src_tris": src_tris}
    if REPORT:
        rows = json.load(open(REPORT)) if os.path.exists(REPORT) else {}
        rows[name] = row
        json.dump(rows, open(REPORT, "w"), indent=1)
    return row


REPORT = os.environ.get("BUILDINGS_REPORT", "")
PACK_SHAPE = os.environ.get("BUILDINGS_PACK", "CONCAVE")
BIG_BELOW = 6.5                                               # px a metre: under this at "tex", "tex_big" instead      # (the UV islands' packing: CONCAVE, CONVEX or AABB)


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
            int(spec.get("tris", 15000)), int(spec.get("tex", 2048)), int(spec.get("ao_samples", 16)), int(spec.get("tex_big", 0))))
    print("missing images after the search: %d %s" % (len(missing), missing[:6]))
    return out
