"""Turns a car model (GLB/glTF, FBX, OBJ, Collada .dae, USD/USDZ or .blend) into a game car: one GLB with a Body,
four wheels and their calipers, plus parts.json (where the wheels are, how big,
where the paint and the windows are). Run with headless Blender, its scripts
off (a .blend can carry Python):

    blender -b -Y --python tools/import_car.py -- tools/cars/<id>.json <model> [texture dir ...]

The spec (tools/cars/<id>.json) says what's what in the model:
  * "pre_scale": the model's units to m before anything else (an FBX in cm: 100)
  * "turn": degrees about the up axis to turn a model saved at an angle (applied first)
  * "rotate": [x, y, z] degrees: a model saved lying down (its up not the file's), stood up
  * "rename": [[pattern, name]]: materials named in another language given English names (the
    game finds the lamps by words like "light", "tail", "brake")
  * "front": which way its nose points after loading ("+X", "-X", "+Y", "-Y";
    Blender's axes, Z up)
  * "wheelbase": the real car's (m): the model is scaled to it
  * "wheel": name patterns of the parts that spin with a wheel (tyre, rim, hub,
    disc); "caliper": the parts that stay on the hub without spinning. A part
    holding more than one wheel is cut up, each face going to the corner it's in. "straighten": false leaves
    the front wheels as they are (they're found turned by more than 2 deg)
  * "wheel_islands": {"tyre_mats": [patterns], "margin": m}: a model all in one piece whose
    wheels share the body's materials: the tyres say where the wheels are, and the loose pieces
    inside each tyre's drum join it (spinning; off the axle and not round: a caliper)
  * "wheel_mats" / "caliper_mats": a model all in one piece: the material
    patterns of its wheels' (calipers') faces, made parts of their own;
    "split_mats": {"name": [patterns]}: more parts of their own ("<part>_name":
    an interior, to thin harder with "decimate_parts")
  * "turn_wheels": [corners]: wheels modelled facing the wrong way (one wheel copied to all
    four, the outer face inward on one side): turned half round on the spot
  * "unmix": true: a game-mod model whose colours are images times vertex colours (a Mix
    node the glTF export drops): the images wired straight to the colour
  * "wheel_trim": true: a wheel material the body uses too (a splitter, a vent): faces far
    from the rest of their corner's wheel stay with the body
  * "mirror": name patterns of parts the model only has on one side (a missing
    tyre): copied, mirrored, to the other
  * "shift": [[name pattern, [dx, dy, dz]]]: parts moved as they're loaded (the model's
    frame and units: children an FBX left off by their parent's offset)
  * "drop": name patterns of parts to leave out (badges); "drop_mats": material
    name patterns whose faces go (logos and nameplates: the cars have no real brands);
    "drop_boxes": [{"box": [x0, x1, y0, y1, z0, z1], "mats": [patterns]}]: faces in a
    box in the car's frame (m: x right, y forward, z up from the ground), lettering
    and badges modelled into the body ("whole": true: only the loose pieces wholly
    inside, so what they sit on stays); "retexture": [[file name pattern, file]]: a
    texture swapped for a cleaned copy (a logo painted out); "lift": [[image name pattern,
    floor]]: its darkest colours raised to that floor (0-1: pure-black palettes); "remat_boxes": [{"box",
    "mats", "to": material, "facing": [x, y, z]}]: those faces given another of the
    model's materials (chrome trim round the inside of a windshield, body paint on a
    dash top), only the ones facing the point (the driver's eyes) if it's given
  * "paint": material name patterns of the body paint: all become one material,
    "paint" (the game paints it from the garage); "paint_normal": paint parts
    shaped by a normal map (a door handle, a fuel cap): painted too, each its
    own material "paint_n<i>" that keeps the map; "glass": the windows' (their
    lowest point along the sides is the window line, for the livery)
  * "materials": [[pattern, {color, metal, rough, alpha, emit, texture}], ...]:
    how a material looks, for models whose materials didn't come with them; or
    one of the usual looks by name (LOOKS: "glass", "chrome", "red_lens" ...), or
    {"look": name, ...changes}. "finish": [[pattern, {"metal", "rough"}]]: just the
    shine put right, the textures kept (an FBX's materials can come in half metal
    and mirror smooth). "rims": the wheel material patterns the game
    colours from the garage (renamed "rim")
  * "glb_patch": material fixes made to the GLB after it's written (tools/glb_patch.py:
    a colour texture taken from the glow map, a glow, a colour, an alpha mode)
  * "glow": [[pattern, strength]]: lamps that glow in their own colour (the emission
    is the material's colour or texture: a white glow mask over a whole light cluster
    turned its red tail lights white); 0: no glow
  * "lamps": [{"kind": "head"/"tail", "mat": pattern, "box": [x0, x1, y0, y1, z0, z1]}]:
    the lamps the material names don't give away (a lens in the glass, a lamp named
    like a wheel): copied to parts.json, where the game cuts the faces of those
    materials inside the box (the game's model space) out as that lamp
  * "view": "hood": a model with no cabin at all (tinted glass over nothing): copied to
    parts.json; the game drives it from a camera low over its bonnet, no cockpit made up
  * "sidewall": {"mats": [patterns], "from": 0.7}: a wheel modelled with its
    tyre's sidewalls in the rim's material: those faces past "from" x the tyre's
    radius become rubber
  * "decimate_parts": [[name pattern, ratio]]: parts thinned to their own ratio
    (1: left whole), and then left alone by the body's budget: an interior
  * "cockpit": the car's interior, kept (the game seats the crew in it):
    {"wheel": {"parts": [name patterns]} or {"box": [x0, x1, y0, y1, z0, z1]}
    (the loose pieces wholly inside it; "cut": true, every face whose middle
    is) or {"mats": [material patterns], "box": ...} (those faces, in the box),
    + "axis": [x, y, z] its column, toward the driver, where its shape misleads,
    "radius": m its rim's (where the hands hold it), where the cut caught more than the wheel,
    "shifter": the same (+ "below": m its pivot is below its foot,
    0.08), or, for an interior modelled without one, {"add": {"at": [x, y],
    "height": m, "lean": degrees}}: a lever made for it (rod, knob, leather
    boot) standing on the tunnel there, its knob that high, leaning back that
    far (10), "handbrake": the same (+ "pivot": "rear", "front" or "bottom"),
    "gearbox": "h4" / "h5" / "h6" (an H-pattern), "seq", "auto"; a single-seater's wheel
    modelled without one: "wheel": {"add": {"at": [x, y, z], "width": m, "tilt": degrees}} (a race
    wheel made for it: a carbon yoke with two grips and a screen, its top leaning back toward the
    driver that far), "seats": 1 (no co-driver), "pose": "formula" (the driver lies back, legs out
    flat in front: the game poses them so), "eye": [x, y, z]
    (else from its seat: rays onto its cushion and its back), "mirror": {"mats",
    "box"}: the rear-view mirror's glass (the game shows the road behind in it)}. Each is cut out
    as SteeringWheel / Shifter / Handbrake, its origin at its pivot, and
    parts.json "cockpit" says where (the wheel's centre, axis toward the
    driver and rim radius; the levers' pivots, knob and grip; the eyes; the
    windshield; "side": the driver's)
  * "wheel_faces" / "body_faces": the most triangles a wheel / the body keeps
    ("caliper_faces": a caliper, for brakes modelled bolt by bolt)
    (decimated: the download stays small). The paint and the glass are never
    thinned (thinning them dents the panels): only the rest, down to 35 % at
    most ("body_least": a lower floor for a very dense model; "paint_faces": the paint and glass
    thinned too, to that many, for a model whose panels are subdivided far past what they need). Whatever is thinned gets its shading back from the part as it was
    (its normals copied over), so it isn't left lumpy
Then every part's transform and modifiers are applied, a front wheel saved
turned is straightened (its axle found from the shape: the tyre's thinnest
way), the car is turned nose to +Y (in the GLB: -Z, the game's forward), scaled
to the wheelbase, its tyres on the ground (z 0) and the middle between the axles
at the origin. Each corner becomes Wheel_FL / FR / RL / RR (and Caliper_..),
its origin at the wheel's centre; the rest is one Body. Images are shrunk to
512 px ("tex_max"; "tex_sizes": [[material pattern, px]] for parts barely seen;
"tex_format": "webp" to store them smaller). Materials marked blended that aren't
see-through come out opaque, or cut out (tools/glb_alpha.py). "--survey" after the paths prints every material (where, how big,
its colour) in the car's own frame instead of exporting; "--out DIR" writes
somewhere else than assets/models/cars/<id> (to try a spec out). A conversion that
looks wrong (wheels that don't match side to side, the body through the ground,
the eyes outside the car) prints WARNING lines.
"""
import bpy, bmesh, sys, json, re, math, os
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
survey = "--survey" in argv
survey_parts = "--parts" in argv
argv = [a for a in argv if a not in ("--survey", "--parts")]
snapshot = None
if "--snapshot" in argv:
    k = argv.index("--snapshot")
    snapshot = os.path.abspath(argv[k + 1])
    argv = argv[:k] + argv[k + 2:]
out_arg = None
if "--out" in argv:
    k = argv.index("--out")
    out_arg = argv[k + 1]
    argv = argv[:k] + argv[k + 2:]
spec_path, src = argv[0], argv[1]
tex_dirs = [os.path.dirname(os.path.abspath(src))] + [os.path.abspath(d) for d in argv[2:]]
spec = json.load(open(spec_path))
out_dir = os.path.abspath(out_arg) if out_arg else \
    os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(spec_path)), "..", "..", "assets", "models", "cars", spec["id"]))
CORNERS = ["FL", "FR", "RL", "RR"]


def matches(name, patterns):
    return any(re.search(p, name, re.I) for p in patterns)


def strip_loose(bm):
    """Vertices and edges no face uses go (some models carry them: they'd stretch a part's bounds)."""
    bmesh.ops.delete(bm, geom=[e for e in bm.edges if not e.link_faces], context='EDGES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')


def store_normals(o):
    """Its normals as they are now, kept in a corner attribute ("keep_n"), from
    when it's loaded to the export: Blender keeps custom normals relative to the
    faces round each vertex, so cutting faces away next to a part (the trim off
    the paint) or joining parts spoils them; restore_normals puts these back."""
    me = o.data
    if hasattr(me, "calc_normals_split"):
        me.calc_normals_split()
    n = np.zeros(len(me.loops) * 3, dtype=np.float32)
    me.loops.foreach_get("normal", n)
    a = me.attributes.get("keep_n") or me.attributes.new("keep_n", 'FLOAT_VECTOR', 'CORNER')
    a.data.foreach_set("vector", n)


def restore_normals(o):
    me = o.data
    a = me.attributes.get("keep_n")
    if a is None:
        return
    n = np.zeros(len(me.loops) * 3, dtype=np.float32)
    a.data.foreach_get("vector", n)
    me.attributes.remove(a)
    n = n.reshape(-1, 3)
    for p in me.polygons:
        p.use_smooth = True
    if hasattr(me, "use_auto_smooth"):
        me.use_auto_smooth = True
        me.auto_smooth_angle = math.pi
    # sharp exactly where the kept normals break across an edge (Blender averages
    # the custom normals of the corners it smooths together: a crease would go soft)
    vi = np.zeros(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", vi)
    ei = np.zeros(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("edge_index", ei)
    first = {}
    sharp = np.zeros(len(me.edges), dtype=bool)
    for p in me.polygons:
        ls = p.loop_indices
        for k, li in enumerate(ls):
            nx = ls[(k + 1) % len(ls)]
            e = ei[li]
            for corner in (li, nx):
                key = (e, vi[corner])
                f = first.get(key)
                if f is None:
                    first[key] = corner
                elif np.dot(n[f], n[corner]) < 0.9998:
                    sharp[e] = True
    me.edges.foreach_set("use_edge_sharp", sharp.tolist())
    me.normals_split_custom_set(n.tolist())


def xform(o, M):
    """o.data.transform(M), its kept normals (keep_n) turned with it."""
    o.data.transform(M)
    a = o.data.attributes.get("keep_n")
    if a is not None:
        n = np.zeros(len(o.data.loops) * 3, dtype=np.float32)
        a.data.foreach_get("vector", n)
        R = np.array(M.to_3x3().inverted().transposed())
        n = n.reshape(-1, 3) @ R.T
        n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-12
        a.data.foreach_set("vector", n.astype(np.float32).ravel())


# ── load: real meshes, modifiers and transforms applied ──────────────────
if src.lower().endswith(".blend"):
    bpy.ops.wm.open_mainfile(filepath=src, load_ui=False)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ext = os.path.splitext(src)[1].lower()
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=src)
    elif ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=src)
    elif ext == ".dae":
        bpy.ops.wm.collada_import(filepath=src)
    elif ext in (".usd", ".usdz", ".usda", ".usdc"):
        bpy.ops.wm.usd_import(filepath=src)
    else:
        bpy.ops.wm.obj_import(filepath=src)
# parts taken from another file of the same model ("graft": {"file", "parts"}: its high-detail
# interior into a lighter exterior, say), in place of the same-named parts here
if spec.get("graft"):
    gr = spec["graft"]
    gpath = gr["file"] if os.path.isabs(gr["file"]) else os.path.join(os.path.dirname(os.path.abspath(src)), gr["file"])
    before = set(bpy.data.objects)
    gext = os.path.splitext(gpath)[1].lower()
    {".fbx": lambda: bpy.ops.import_scene.fbx(filepath=gpath), ".glb": lambda: bpy.ops.import_scene.gltf(filepath=gpath),
     ".gltf": lambda: bpy.ops.import_scene.gltf(filepath=gpath), ".obj": lambda: bpy.ops.wm.obj_import(filepath=gpath)}[gext]()
    base = lambda n: re.sub(r"\.\d{3}$", "", n)
    for o in list(set(bpy.data.objects) - before):
        if o.type == 'MESH' and matches(base(o.name), gr["parts"]):
            continue
        if o.type in ('MESH', 'EMPTY'):          # (an empty may parent the kept parts: kept until parents clear)
            if o.type == 'MESH':
                bpy.data.objects.remove(o, do_unlink=True)
    for o in list(before):
        if o.type == 'MESH' and matches(o.name, gr["parts"]):
            bpy.data.objects.remove(o, do_unlink=True)
    grafted = [o for o in set(bpy.data.objects) - before if o.type == 'MESH']
    for o in grafted:
        o.name = base(o.name)
    print("graft: %s from %s" % (", ".join(sorted(o.name for o in grafted)), os.path.basename(gpath)))
vl = bpy.context.view_layer
for o in vl.objects:
    o.hide_set(False)
    o.hide_viewport = False
    o.hide_select = False
bpy.ops.object.select_all(action='DESELECT')
for o in vl.objects:
    if o.instance_type == 'COLLECTION' and o.instance_collection:
        o.select_set(True)
if bpy.context.selected_objects:
    vl.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.duplicates_make_real()
# every part on its own, where it is (before any parent goes: an FBX's empties carry its scale)
bpy.ops.object.select_all(action='SELECT')
vl.objects.active = vl.objects[0]
bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
for o in list(bpy.data.objects):                  # not in the scene, or not rendered: not part of the car
    if o.name not in vl.objects or o.hide_render:
        bpy.data.objects.remove(o, do_unlink=True)
# the glTF importer's bone shapes (its "glTF_not_exported" collection) aren't parts of the car
for c in bpy.data.collections:
    if c.name.startswith("glTF_not_exported"):
        for o in list(c.objects):
            bpy.data.objects.remove(o, do_unlink=True)
    c.hide_viewport = False
    c.hide_select = False
# (parts hidden in the viewport or locked against selection can't be converted: shown, unlocked)
def _show(lc):
    lc.hide_viewport = False
    for c in lc.children:
        _show(c)
_show(vl.layer_collection)
for o in vl.objects:
    o.hide_viewport = False
    o.hide_select = False
    o.hide_set(False)
bpy.ops.object.select_all(action='DESELECT')
shapes = [o for o in vl.objects if o.type in ('MESH', 'CURVE', 'SURFACE', 'FONT', 'META')]
for o in shapes:
    o.select_set(True)
vl.objects.active = shapes[0]
bpy.ops.object.convert(target='MESH')             # modifiers (mirror, subdivision ...) applied
for o in list(bpy.data.objects):
    if o.type != 'MESH':
        bpy.data.objects.remove(o, do_unlink=True)
meshes = list(bpy.data.objects)
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
vl.objects.active = meshes[0]
bpy.ops.object.make_single_user(object=True, obdata=True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in bpy.data.objects:
    if o.type == 'MESH':
        bm = bmesh.new()
        bm.from_mesh(o.data)
        strip_loose(bm)
        bm.to_mesh(o.data)
        bm.free()
        store_normals(o)
        o.data.validate()          # (bad bits gone now, the kept normals with them)
# parts moved as they were loaded ("shift": [[name pattern, [dx, dy, dz]]], the model's own
# frame and units): an FBX whose parent was moved with its own vertices held in place, leaving
# its children off by its offset
for pat, d in spec.get("shift", []):
    for o in bpy.data.objects:
        if o.type == 'MESH' and matches(o.name, [pat]):
            o.data.transform(Matrix.Translation(Vector(d)))
for o in list(bpy.data.objects):
    if matches(o.name, spec.get("drop", [])) or len(o.data.polygons) == 0:
        bpy.data.objects.remove(o, do_unlink=True)
meshes = list(bpy.data.objects)
# a model whose parts each carry their own uniquely named UV maps (a game mod's: 131 names
# here) would come out of the join with all of them on every vertex: each part keeps just the
# map it renders with, under one shared name
uv_names = {uv.name for o in meshes for uv in o.data.uv_layers}
if len(uv_names) > 8:
    for o in meshes:
        uvs = o.data.uv_layers
        if not len(uvs):
            continue
        keep = next((uv for uv in uvs if uv.active_render), uvs[0]).name
        for name in [uv.name for uv in uvs if uv.name != keep]:
            uvs.remove(uvs[name])                         # (by name: a layer's reference goes stale once one is removed)
        uvs[0].name = "UVMap"
    print("UV maps: %d names across the parts, one kept on each" % len(uv_names))
# materials named in another language: "rename": [[pattern, name]] (the game finds lamps by English
# words: "Feux_stop" -> "brakelight"), before anything else reads the names
for pat, new in spec.get("rename", []):
    for mat in list(bpy.data.materials):
        if re.search(pat, mat.name, re.I):
            was = mat.name
            mat.name = re.sub(pat, new, mat.name, flags=re.I)       # (the match replaced: a prefix, or all of it)
            print("renamed %s -> %s" % (was, mat.name))
if spec.get("pre_scale", 1.0) != 1.0:
    for o in meshes:
        xform(o, Matrix.Scale(spec["pre_scale"], 4))
# a model saved lying down (an OBJ whose up isn't the file's Y): "rotate": [x, y, z] degrees, first
if spec.get("rotate"):
    rx, ry, rz = (math.radians(float(v)) for v in spec["rotate"])
    R = Matrix.Rotation(rz, 4, 'Z') @ Matrix.Rotation(ry, 4, 'Y') @ Matrix.Rotation(rx, 4, 'X')
    for o in meshes:
        xform(o, R)

# the faces of logo materials go
drop_mats = spec.get("drop_mats", [])
if drop_mats:
    for o in list(meshes):
        bad = {i for i, s in enumerate(o.material_slots) if s.material and matches(s.material.name, drop_mats)}
        if not bad:
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index in bad], context='FACES')
        strip_loose(bm)
        bm.to_mesh(o.data)
        bm.free()
        if len(o.data.polygons) == 0:
            meshes.remove(o)
            bpy.data.objects.remove(o, do_unlink=True)

# ("unmix": a game-mod material whose colour is its image times the mesh's vertex colours,
# through a Mix node the glTF export can't carry: the image wired straight to the colour (and
# its alpha to the alpha), else the material exports with no texture at all)
if spec.get("unmix"):
    n_unmixed = 0
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        nt = mat.node_tree
        b = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if b is None or not b.inputs["Base Color"].links:
            continue
        mix = b.inputs["Base Color"].links[0].from_node
        if mix.type not in ('MIX', 'MIX_RGB'):
            continue
        img = None
        for inp in mix.inputs:
            for l in inp.links:
                if l.from_node.type == 'TEX_IMAGE' and l.from_node.image:
                    img = l.from_node
        if img is None:
            continue
        nt.links.new(img.outputs["Color"], b.inputs["Base Color"])
        # its alpha: opaque unless the image really has see-through pixels (then cut out, not
        # blended: a blended body panel sorts wrong against the rest and comes out patchy)
        im = img.image
        px = np.empty(im.size[0] * im.size[1] * im.channels, dtype=np.float32)
        im.pixels.foreach_get(px)
        see_through = im.channels == 4 and float(px.reshape(-1, 4)[:, 3].min()) < 0.5
        for l in list(b.inputs["Alpha"].links):
            nt.links.remove(l)
        if see_through:
            nt.links.new(img.outputs["Alpha"], b.inputs["Alpha"])
            mat.blend_method = 'CLIP'
        else:
            mat.blend_method = 'OPAQUE'
        n_unmixed += 1
    print("unmix: %d materials' images wired straight to their colour" % n_unmixed)

# images the model was saved with under another name (Sketchfab renames them): found by name
def _key(n):
    n = os.path.splitext(os.path.basename(n))[0].lower()
    n = re.sub(r"\(\d+\)", "", n)
    return re.sub(r"[^a-z0-9]", "", n)

found = {}
missing_images = []
for d in tex_dirs:
    for root, _, files in os.walk(d):
        for f in files:
            if f.lower().endswith((".png", ".jpg", ".jpeg", ".tga", ".bmp", ".tif", ".tiff", ".webp")):
                found.setdefault(_key(f), os.path.join(root, f))
for img in list(bpy.data.images):
    # (an image the importer couldn't load is left a placeholder, "generated", but keeps its path)
    if img.packed_file or img.source not in ('FILE', 'GENERATED') or (img.source == 'GENERATED' and not img.filepath):
        continue
    p = bpy.path.abspath(img.filepath)
    if img.source == 'GENERATED' or not os.path.exists(p):
        for k in (_key(img.filepath), _key(img.name)):
            # (or the file whose name starts with it: a texture saved as "x_(Personalizado).png" for
            # a model that asks for "x.png"; or whose name it starts with: one saved cut short,
            # "x_B.png" for "x_BaseColor.png")
            hit = k if k in found else None
            if hit is None and len(k) >= 6:
                longer = [f for f in found if f.startswith(k)]
                hit = min(longer, key=len) if longer else None
            if hit is None:
                shorter = [f for f in found if len(f) >= 12 and k.startswith(f)]
                hit = max(shorter, key=len) if shorter else None
            if hit:
                fresh = bpy.data.images.load(found[hit], check_existing=True)     # (a reloaded placeholder stays empty)
                fresh.colorspace_settings.name = img.colorspace_settings.name
                if fresh != img:
                    img.user_remap(fresh)
                break
        else:
            # (one the spec swaps for a file of its own isn't missing: "retexture" wires it below)
            if any(re.search(pat, os.path.basename(p) or img.name, re.I) for pat, _ in spec.get("retexture", [])):
                continue
            print("missing image:", img.name, img.filepath)
            missing_images.append(img)

# an image found nowhere is taken off its materials (they keep their colour): left on, it would
# export as a texture with no image, and Godot refuses the whole file
for img in missing_images:
    for mat in bpy.data.materials:
        if mat.use_nodes:
            for nd in [n for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image == img]:
                mat.node_tree.nodes.remove(nd)



# an OBJ whose .mtl points its textures somewhere else (an absolute path on its maker's machine,
# "C:/Dif.png"): the importer leaves those out; each is found by its file name in the texture
# folders and wired to its material (map_Kd colour, map_d alpha, map_Bump / norm normal)
if src.lower().endswith(".obj"):
    mtl_path = os.path.splitext(src)[0] + ".mtl"
    if os.path.exists(mtl_path):
        mtls, cur = {}, None
        for line in open(mtl_path, encoding="utf-8", errors="replace"):
            t = line.strip().split(None, 1)
            if len(t) < 2:
                continue
            if t[0] == "newmtl":
                cur = mtls.setdefault(t[1].strip(), {})
            elif cur is not None and t[0] in ("map_Kd", "map_d", "map_Bump", "map_bump", "bump", "norm"):
                cur[t[0].lower().replace("map_", "")] = os.path.basename(t[1].strip().split()[-1].replace("\\", "/"))
        def find_tex(name):
            for d in tex_dirs:
                for root, _, files in os.walk(d):
                    for f in files:
                        if f.lower() == name.lower():
                            return os.path.join(root, f)
            return None
        for mat in bpy.data.materials:
            st = mtls.get(mat.name)
            if not st or not mat.use_nodes:
                continue
            nt = mat.node_tree
            bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
            if bsdf is None or any(n.type == 'TEX_IMAGE' and n.image for n in nt.nodes):
                continue
            kd = find_tex(st["kd"]) if st.get("kd") else None
            if kd:
                n = nt.nodes.new("ShaderNodeTexImage")
                n.image = bpy.data.images.load(kd, check_existing=True)
                nt.links.new(n.outputs["Color"], bsdf.inputs["Base Color"])
                if st.get("d") == st.get("kd"):
                    nt.links.new(n.outputs["Alpha"], bsdf.inputs["Alpha"])
                    mat.blend_method = 'BLEND'
            nm = next((find_tex(st[k]) for k in ("bump", "norm") if st.get(k)), None)
            if nm:
                n = nt.nodes.new("ShaderNodeTexImage")
                n.image = bpy.data.images.load(nm, check_existing=True)
                n.image.colorspace_settings.name = 'Non-Color'
                m = nt.nodes.new("ShaderNodeNormalMap")
                nt.links.new(n.outputs["Color"], m.inputs["Color"])
                nt.links.new(m.outputs["Normal"], bsdf.inputs["Normal"])
            if kd or nm:
                print("mtl texture: %s <- %s" % (mat.name, ", ".join(os.path.basename(p) for p in (kd, nm) if p)))

# PBR texture sets beside the model, named after their materials ("pbr_sets": true; Sketchfab's
# "<material>_albedo.jpg", "_normal", "_roughness", "_metallic", "_emissive", "_opacity"; BeamNG's
# "_diff", "_nrm", "_opac" too): each
# material that has a set gets it (an opacity map that isn't all white becomes its alpha: glass
# in an atlas; an all-black emissive map is left out)
if spec.get("pbr_sets"):
    sets = {}
    for d in tex_dirs:
        for f in (os.listdir(d) if os.path.isdir(d) else []):
            m = re.match(r"(.+?)_(albedo|basecolor|base_color|diffuse|diff|normal|nrm|roughness|metallic|metalness|metalic|emissive|opacity|opac)\.(png|jpe?g|tga|dds)$", f, re.I)
            if m:
                key = {"diff": "diffuse", "nrm": "normal", "opac": "opacity", "metalness": "metallic", "metalic": "metallic"}.get(m.group(2).lower(), m.group(2).lower())
                name = re.sub(r"^t_", "", m.group(1).lower())       # (Unreal-style "T_<material>_BaseColor" too)
                sets.setdefault(name, {})[key] = os.path.join(d, f)
    def _flat(path):
        """The image's lowest and highest brightness (sampled)."""
        im = bpy.data.images.load(path, check_existing=True)
        px = np.array(im.pixels[:], dtype=np.float32).reshape(-1, 4)[::97, :3]
        return float(px.min()), float(px.max()), im
    for mat in list(bpy.data.materials):
        st = sets.get(mat.name.lower())
        if not st:
            continue
        mat.use_nodes = True
        nt = mat.node_tree
        for n in list(nt.nodes):
            nt.nodes.remove(n)
        out_n = nt.nodes.new("ShaderNodeOutputMaterial")
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(bsdf.outputs["BSDF"], out_n.inputs["Surface"])
        def tex_node(path, colour):
            n = nt.nodes.new("ShaderNodeTexImage")
            n.image = bpy.data.images.load(path, check_existing=True)
            n.image.colorspace_settings.name = 'sRGB' if colour else 'Non-Color'
            return n
        base = st.get("albedo") or st.get("basecolor") or st.get("base_color") or st.get("diffuse")
        if base:
            nt.links.new(tex_node(base, True).outputs["Color"], bsdf.inputs["Base Color"])
        if st.get("normal"):
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(tex_node(st["normal"], False).outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        for key, inp in (("roughness", "Roughness"), ("metallic", "Metallic")):
            if st.get(key):
                nt.links.new(tex_node(st[key], False).outputs["Color"], bsdf.inputs[inp])
        if st.get("emissive") and _flat(st["emissive"])[1] > 0.02:
            nt.links.new(tex_node(st["emissive"], True).outputs["Color"], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = 1.0
        if st.get("opacity") and _flat(st["opacity"])[0] < 0.98:
            nt.links.new(tex_node(st["opacity"], False).outputs["Color"], bsdf.inputs["Alpha"])
            mat.blend_method = 'BLEND'
        print("pbr set: %s (%s)" % (mat.name, ", ".join(sorted(st))))

# textures swapped for cleaned copies (a logo painted out): by the image's file name
for pat, f in spec.get("retexture", []):
    path = next((os.path.join(d, f) for d in tex_dirs if os.path.exists(os.path.join(d, f))), f)
    new = None
    for img in list(bpy.data.images):
        if re.search(pat, os.path.basename(bpy.path.abspath(img.filepath)) or img.name, re.I):
            if new is None:
                new = bpy.data.images.load(path)
                new.colorspace_settings.name = img.colorspace_settings.name    # (a normal map stays non-colour)
            for m in bpy.data.materials:
                if m.use_nodes:
                    for n in m.node_tree.nodes:
                        if n.type == 'TEX_IMAGE' and n.image == img:
                            n.image = new
            print("retextured %s -> %s" % (img.name, f))

# a texture's darkest colours lifted to a floor ("lift": [[image name pattern, floor]], 0-1 as
# stored): a game rip's palette whose blacks are pure 0 (a whole cabin went black in the shade)
for pat, floor in spec.get("lift", []):
    for img in list(bpy.data.images):
        if img.size[0] and re.search(pat, os.path.basename(bpy.path.abspath(img.filepath)) or img.name, re.I):
            px = np.empty(img.size[0] * img.size[1] * img.channels, dtype=np.float32)
            img.pixels.foreach_get(px)
            px = px.reshape(-1, img.channels)
            px[:, :3] = np.maximum(px[:, :3], float(floor))
            img.pixels.foreach_set(px.ravel())
            img.update()
            img.pack()
            print("lifted %s to %.2f" % (img.name, float(floor)))


def verts(o):
    return np.array([v.co[:] for v in o.data.vertices], dtype=float)


def centre(objs):
    pts = np.vstack([v for v in (verts(o) for o in objs) if len(v)])     # (a split can leave a part empty)
    return Vector(((pts.min(0) + pts.max(0)) * 0.5).tolist()), pts


# a model saved turned on the ground ("turn": degrees about the up axis that bring its nose
# round to "front"; the P1 GTR's file has it at 45 degrees)
if spec.get("turn"):
    R = Matrix.Rotation(math.radians(float(spec["turn"])), 4, 'Z')
    for o in meshes:
        xform(o, R)

# ── the corners ──────────────────────────────────────────────────────────
fwd = {"+X": Vector((1, 0, 0)), "-X": Vector((-1, 0, 0)), "+Y": Vector((0, 1, 0)), "-Y": Vector((0, -1, 0))}[spec["front"]]
right = fwd.cross(Vector((0, 0, 1)))
# a model all in one piece: its wheels' (and calipers') faces, by material, made parts of their own
splits = [(spec.get("wheel_mats", []), "_wheelpart"), (spec.get("caliper_mats", []), "_caliperpart")]
splits += [(pats, "_" + name) for name, pats in spec.get("split_mats", {}).items()]
suffixes = tuple(sfx for _, sfx in splits)
for pats, suffix in splits:
    if not pats:
        continue
    for o in list(meshes):
        idx = {i for i, sl in enumerate(o.material_slots) if sl.material and matches(sl.material.name, pats)}
        if not idx or o.name.endswith(suffixes):
            continue
        n = o.copy()
        n.data = o.data.copy()
        bpy.context.collection.objects.link(n)
        for ob, keep in ((o, False), (n, True)):
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            bmesh.ops.delete(bm, geom=[f for f in bm.faces if (f.material_index in idx) != keep], context='FACES')
            strip_loose(bm)
            bm.to_mesh(ob.data)
            bm.free()
        n.name = o.name[:63 - len(suffix)] + suffix   # (Blender keeps 63 characters: a long name lost its tag)
        meshes.append(n)
        print("%s: %d faces by material" % (n.name, len(n.data.polygons)))


def islands(o, faces, eps=1e-4):
    """o's faces (of `faces`) in loose pieces: touching by a shared corner, or corners within
    eps of each other (a part saved in slices whose seams don't quite meet): [[face index]]."""
    from mathutils.kdtree import KDTree
    me = o.data
    used = sorted({v for fi in faces for v in me.polygons[fi].vertices})
    parent = {v: v for v in used}
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
    kd = KDTree(len(used))
    for v in used:
        kd.insert(me.vertices[v].co, v)
    kd.balance()
    for v in used:
        for _, w, _ in kd.find_range(me.vertices[v].co, eps):
            union(v, w)
    for fi in faces:
        vs = me.polygons[fi].vertices
        for v in vs[1:]:
            union(vs[0], v)
    groups = {}
    for fi in faces:
        groups.setdefault(find(me.polygons[fi].vertices[0]), []).append(fi)
    return list(groups.values())


# a model all in one piece whose wheels share the body's materials (a game rip: one texture
# atlas): "wheel_islands": {"tyre_mats": [patterns], "margin": m}: the tyres (a material of
# their own) say where the four wheels are (the middle, the radius, the axle: the tyre's
# thinnest way); every loose piece wholly inside a tyre's drum (within its radius, between its
# faces give or take "margin") joins that wheel: it spins with it, or, its middle off the axle
# and not round (a caliper), it stays on the hub
wi = spec.get("wheel_islands")
if wi:
    allpts = np.vstack([verts(o) for o in meshes if len(o.data.vertices)])
    size = float(np.linalg.norm(allpts.max(0) - allpts.min(0)))          # (the model's size: its units may not be metres)
    eps = size * 2e-5
    tyres = []                                      # [centre, axis (0..2), radius, half width]
    for o in meshes:
        idx = [i for i, p in enumerate(o.data.polygons) if p.material_index < len(o.material_slots)
               and o.material_slots[p.material_index].material and matches(o.material_slots[p.material_index].material.name, wi["tyre_mats"])]
        co = verts(o)
        for g in islands(o, idx, eps):
            pts = co[sorted({v for fi in g for v in o.data.polygons[fi].vertices})]
            lo, hi = pts.min(0), pts.max(0)
            ext = hi - lo
            ax = int(np.argmin(ext))
            e = np.delete(ext, ax)
            r = float(e.max()) * 0.5
            # a tyre (or one of its skins): big enough (not a valve, lettering, a disc in the tyres'
            # material), round, its axle level
            if r < size * 0.035 or abs(float(e[0] - e[1])) > 0.12 * float(e.max()) or ax == 2:
                continue
            c = (lo + hi) * 0.5
            for t in tyres:                         # (its other skins: the same middle)
                if np.linalg.norm(c - t[0]) < max(r, t[2]):
                    t[2], t[3] = max(t[2], r), max(t[3], float(ext[ax]) * 0.5)
                    break
            else:
                tyres.append([c, ax, r, float(ext[ax]) * 0.5])
    if os.environ.get("IMPORT_DEBUG"):
        for t in tyres:
            print("tyre", np.round(t[0], 3), "axis", t[1], "r %.3f hw %.3f" % (t[2], t[3]))
    tyres.sort(key=lambda t: t[0][2])               # (the four on the road: a spare on the tailgate is higher up)
    tyres = tyres[:4]
    if len(tyres) != 4:
        raise SystemExit("wheel_islands: %d tyres found (4 wanted)" % len(tyres))
    margin = float(wi.get("margin", 0.03)) * size / 5.0
    moved = 0
    for o in list(meshes):
        if o.name.endswith(suffixes):
            continue
        co = np.array([v.co[:] for v in o.data.vertices], dtype=float)
        tyre_idx = {i for i, sl in enumerate(o.material_slots) if sl.material and matches(sl.material.name, wi["tyre_mats"])}
        spin_f, cal_f = [], []
        for g in islands(o, range(len(o.data.polygons)), eps):
            pts = co[sorted({v for fi in g for v in o.data.polygons[fi].vertices})]
            for c, ax, r, hw in tyres:
                rest = [k for k in range(3) if k != ax]
                d = np.linalg.norm(pts[:, rest] - c[rest], axis=1)
                a = pts[:, ax] - c[ax]
                if d.max() > r * 1.03 or a.min() < -hw - margin or a.max() > hw + margin:
                    continue
                lo, hi = pts[:, rest].min(0), pts[:, rest].max(0)
                off = np.linalg.norm((lo + hi) * 0.5 - c[rest])
                # a caliper: off the axle, not round, inside the rim (not lettering on the tyre)
                caliper = off > 0.2 * r and float((hi - lo).max()) < 1.2 * r and d.max() < 0.8 * r \
                    and not any(o.data.polygons[fi].material_index in tyre_idx for fi in g)
                (cal_f if caliper else spin_f).extend(g)
                break
        for faces, suffix in ((spin_f, "_wheelpart"), (cal_f, "_caliperpart")):
            if not faces:
                continue
            keep = set(faces)
            n = o.copy()
            n.data = o.data.copy()
            bpy.context.collection.objects.link(n)
            bm = bmesh.new()
            bm.from_mesh(n.data)
            bm.faces.ensure_lookup_table()
            bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context='FACES')
            strip_loose(bm)
            bm.to_mesh(n.data)
            bm.free()
            n.name = o.name[:40] + suffix               # (Blender cuts names at 63 characters: keep the suffix)
            meshes.append(n)
            moved += len(faces)
        gone = set(spin_f) | set(cal_f)
        if gone:
            bm = bmesh.new()
            bm.from_mesh(o.data)
            bm.faces.ensure_lookup_table()
            bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index in gone], context='FACES')
            strip_loose(bm)
            bm.to_mesh(o.data)
            bm.free()
    print("wheel_islands: 4 tyres (radius %s), %d faces moved to the wheels and calipers" % (
        ", ".join("%.3f" % t[2] for t in tyres), moved))
spec["wheel"] = spec.get("wheel", []) + (["_wheelpart$"] if spec.get("wheel_mats") or wi else [])
spec["caliper"] = spec.get("caliper", []) + (["_caliperpart$"] if spec.get("caliper_mats") or wi else [])
spin = [o for o in meshes if matches(o.name, spec["wheel"])]
if not spin:
    raise SystemExit("no wheel parts: check the spec's \"wheel\" patterns")
wc, _ = centre(spin)
mid_lon, mid_lat = wc.dot(fwd), wc.dot(right)

# a part the model only has on one side: a mirrored copy on the other
for o in [o for o in meshes if matches(o.name, spec.get("mirror", []))]:
    n = o.copy()
    n.data = o.data.copy()
    bpy.context.collection.objects.link(n)
    a = right
    m = Matrix.Translation(a * mid_lat) @ (Matrix.Identity(4) - 2.0 * Matrix([[a.x * a.x, a.x * a.y, a.x * a.z, 0], [a.y * a.x, a.y * a.y, a.y * a.z, 0], [a.z * a.x, a.z * a.y, a.z * a.z, 0], [0, 0, 0, 0]])) @ Matrix.Translation(-a * mid_lat)
    xform(n, m)
    bm = bmesh.new()                              # (a mirror turns the faces inside out)
    bm.from_mesh(n.data)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    strip_loose(bm)
    bm.to_mesh(n.data)
    bm.free()
    n.name = o.name + "_mirrored"
    meshes.append(n)
spin = [o for o in meshes if matches(o.name, spec["wheel"])]
cal = [o for o in meshes if matches(o.name, spec.get("caliper", [])) and o not in spin]


def corner_of(p):
    return ("F" if p.dot(fwd) > mid_lon else "R") + ("R" if p.dot(right) > mid_lat else "L")


def split_corners(o):
    """[(corner, object)]: a part holding wheels at more than one corner is cut up."""
    keys = [corner_of(p.center) for p in o.data.polygons]
    have = sorted(set(keys))
    if len(have) == 1:
        return [(have[0], o)]
    out = []
    for k in have:
        n = o.copy()
        n.data = o.data.copy()
        bpy.context.collection.objects.link(n)
        bm = bmesh.new()
        bm.from_mesh(n.data)
        bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[f for f, kk in zip(bm.faces, keys) if kk != k], context='FACES')
        strip_loose(bm)
        bm.to_mesh(n.data)
        bm.free()
        n.name = "%s_%s" % (o.name, k)
        out.append((k, n))
    meshes.remove(o)
    bpy.data.objects.remove(o, do_unlink=True)
    meshes.extend(n for _, n in out)
    return out


corner = {k: {"spin": [], "cal": []} for k in CORNERS}
for kind, objs in (("spin", spin), ("cal", cal)):
    for o in list(objs):
        for k, part in split_corners(o):
            corner[k][kind].append(part)
for k in CORNERS:
    if not corner[k]["spin"]:
        raise SystemExit("no wheel parts at %s" % k)

# ("wheel_trim": a wheel material also used on the body (a splitter, a vent): faces far from
# the rest of their corner's wheel, side on, stay with the body: they'd spin, and skew the axle)
if spec.get("wheel_trim"):
    for k in CORNERS:
        objs = corner[k]["spin"]
        cen = np.vstack([np.array([p.center[:] for p in o.data.polygons]) for o in objs])
        side = lambda q: np.stack([q @ np.array(fwd[:]), q[:, 2]], axis=1)
        med = np.median(side(cen), axis=0)
        reach = 2.0 * float(np.median(np.linalg.norm(side(cen) - med, axis=1)))
        lat = np.median(cen @ np.array(right[:]))         # (and in from the wheel: a wheel is narrower than it is tall)
        for o in list(objs):
            c = np.array([p.center[:] for p in o.data.polygons])
            far = np.linalg.norm(side(c) - med, axis=1) > reach
            # (in from the wheel by any corner of the face: a long strip's middle can sit in the wheel)
            vlat = np.array([v.co[:] for v in o.data.vertices]) @ np.array(right[:]) - lat
            far |= np.array([float(np.abs(vlat[list(p.vertices)]).max()) > 0.6 * reach for p in o.data.polygons])
            if not far.any():
                continue
            rest = o.copy()
            rest.data = o.data.copy()
            bpy.context.collection.objects.link(rest)
            for obj, drop in ((o, far), (rest, ~far)):
                bm = bmesh.new()
                bm.from_mesh(obj.data)
                bm.faces.ensure_lookup_table()
                bmesh.ops.delete(bm, geom=[f for f, d in zip(bm.faces, drop) if d], context='FACES')
                strip_loose(bm)
                bm.to_mesh(obj.data)
                bm.free()
            rest.name = o.name + "_body"
            meshes.append(rest)
            print("wheel_trim: %d faces of %s left with the body" % (int(far.sum()), o.name))

# (a split or the trim can leave a part with nothing in it: gone)
for k in CORNERS:
    for kind in ("spin", "cal"):
        for o in [o for o in corner[k][kind] if len(o.data.polygons) == 0]:
            corner[k][kind].remove(o)
            if o in meshes:
                meshes.remove(o)
            bpy.data.objects.remove(o, do_unlink=True)

# straighten a front wheel saved turned: its axle is the tyre's thinnest way
# (from the tyre's outer ring only: a deep hub would skew it)
for k in CORNERS:
    c, pts = centre(corner[k]["spin"])
    if k[0] == "F" and spec.get("straighten", True):
        r = np.linalg.norm(pts - np.array(c[:]), axis=1)
        ring = pts[r > r.max() * 0.85]
        d = ring - ring.mean(0)
        w, v = np.linalg.eigh(d.T @ d)
        axle = Vector(v[:, 0].tolist())
        axle.z = 0.0
        if axle.length > 1e-6:
            axle.normalize()
            if axle.dot(right) < 0.0:
                axle = -axle
            ang = math.atan2(axle.cross(right).z, axle.dot(right))   # turn it by this round Z
            if abs(ang) > math.radians(2.0):
                m = Matrix.Translation(c) @ Matrix.Rotation(ang, 4, 'Z') @ Matrix.Translation(-c)
                for o in corner[k]["spin"] + corner[k]["cal"]:
                    xform(o, m)
                print("straightened %s by %.1f deg" % (k, math.degrees(ang)))
    corner[k]["c"] = centre(corner[k]["spin"])[0]

# ("turn_wheels": [corners]: a model that copied one wheel to all four corners, its outer face
# the same way on both sides: those corners' wheels turned half round on the spot)
for k in spec.get("turn_wheels", []):
    c = corner[k]["c"]
    m = Matrix.Translation(c) @ Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Translation(-c)
    for o in corner[k]["spin"] + corner[k]["cal"]:
        xform(o, m)
    print("turned the %s wheel half round" % k)

# tyre sidewalls modelled in the rim's material: past "from" x the tyre's radius, rubber
sw = spec.get("sidewall")
if sw:
    rubber = bpy.data.materials.new("tyre_sidewall")
    for k in CORNERS:
        c = corner[k]["c"]
        objs = corner[k]["spin"]
        pts = np.vstack([verts(o) for o in objs]) - np.array(c[:])
        ax = np.array(right[:])
        radial = lambda q: np.linalg.norm(q - np.outer(q @ ax, ax), axis=1)
        R = radial(pts).max()
        for o in objs:
            idx = [i for i, sl in enumerate(o.material_slots) if sl.material and matches(sl.material.name, sw["mats"])]
            if not idx:
                continue
            if rubber.name not in [sl.material.name for sl in o.material_slots if sl.material]:
                o.data.materials.append(rubber)
            ri = [sl.material for sl in o.material_slots].index(rubber)
            cen = np.array([p.center[:] for p in o.data.polygons]) - np.array(c[:])
            far = radial(cen) > R * sw["from"]
            for p, f in zip(o.data.polygons, far):
                if f and p.material_index in idx:
                    p.material_index = ri

for k in CORNERS:
    c = corner[k]["c"]
    print("corner %s at (%.3f, %.3f, %.3f), %d parts" % (k, c.x, c.y, c.z, len(corner[k]["spin"])))

# the car's own frame: nose to +Y, the wheelbase the real one, tyres on z 0
front = (corner["FL"]["c"] + corner["FR"]["c"]) * 0.5
rear = (corner["RL"]["c"] + corner["RR"]["c"]) * 0.5
base = (front - rear).dot(fwd)
s = spec["wheelbase"] / base
ground = min(float(verts(o)[:, 2].min()) for k in CORNERS for o in corner[k]["spin"])
origin = (front + rear) * 0.5
origin.z = ground
turn = Matrix.Rotation(math.atan2(fwd.x, fwd.y), 4, 'Z')    # fwd -> +Y
M = Matrix.Scale(s, 4) @ turn @ Matrix.Translation(-origin)
for o in meshes:
    xform(o, M)
for k in CORNERS:
    corner[k]["c"] = M @ corner[k]["c"]
print("scaled x%.4f (model wheelbase %.3f -> %.3f m)" % (s, base, spec["wheelbase"]))
# every tyre on the ground: a wheel the model left floating (smaller front tyres modelled at
# the rear ones' axle height, a raked stance) let down onto it, the body staying where it is
for k in CORNERS:
    lift = min(float(verts(o)[:, 2].min()) for o in corner[k]["spin"])
    if lift > 0.003:
        down = Matrix.Translation((0.0, 0.0, -lift))
        for o in corner[k]["spin"] + corner[k]["cal"]:
            xform(o, down)
        corner[k]["c"] = down @ corner[k]["c"]
        print("%s wheel let down %.0f mm onto the ground" % (k, lift * 1000))

def loose_in(o, box, cut=False):
    """The faces of o's loose pieces that lie wholly inside box ([x0, x1, y0, y1,
    z0, z1], the car's frame): a lever and its knob, not the console it stands
    in. cut: every face whose middle is inside (a lever modelled joined on)."""
    x0, x1, y0, y1, z0, z1 = box
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.faces.ensure_lookup_table()
    inb = lambda c: x0 <= c.x <= x1 and y0 <= c.y <= y1 and z0 <= c.z <= z1
    if cut:
        sel = {f.index for f in bm.faces if inb(f.calc_center_median())}
        bm.free()
        return sel
    cand = {f.index for f in bm.faces if all(inb(v.co) for v in f.verts)}
    sel, seen = set(), set()
    for i in cand:
        if i in seen:
            continue
        seen.add(i)
        stack, piece, attached = [bm.faces[i]], [], False
        while stack:
            f = stack.pop()
            piece.append(f.index)
            for v in f.verts:
                for g in v.link_faces:
                    if g.index not in cand:
                        attached = True
                    elif g.index not in seen:
                        seen.add(g.index)
                        stack.append(g)
        if not attached:
            sel.update(piece)
    bm.free()
    return sel


# badges and lettering modelled into the body: the faces inside a box (the car's frame,
# m: x right, y forward, z up) of the given materials go
for b in spec.get("drop_boxes", []):
    x0, x1, y0, y1, z0, z1 = b["box"]
    gone = 0
    for o in [o for o in meshes if all(o not in corner[k]["spin"] + corner[k]["cal"] for k in CORNERS)]:
        idx = {i for i, sl in enumerate(o.material_slots) if sl.material and matches(sl.material.name, b.get("mats", [".*"]))}
        bm = bmesh.new()
        bm.from_mesh(o.data)
        if b.get("whole"):          # only loose pieces wholly inside (a badge, not the grille around it)
            whole = loose_in(o, b["box"])
            bm.faces.ensure_lookup_table()
            dead = [bm.faces[i] for i in whole if bm.faces[i].material_index in idx]
        else:
            dead = [f for f in bm.faces if f.material_index in idx and x0 <= f.calc_center_median().x <= x1
                and y0 <= f.calc_center_median().y <= y1 and z0 <= f.calc_center_median().z <= z1]
        gone += len(dead)
        bmesh.ops.delete(bm, geom=dead, context='FACES')
        strip_loose(bm)
        bm.to_mesh(o.data)
        bm.free()
    print("dropped %d faces in %s" % (gone, b["box"]))

# a material used where the real car has another (chrome trim round the inside of the
# windshield, the body paint on the dash top): the faces inside a box (the car's frame) of
# the given materials ("facing": [x, y, z]: only those facing that point, the driver's eyes)
# given the material "to"
for b in spec.get("remat_boxes", []):
    x0, x1, y0, y1, z0, z1 = b["box"]
    to = bpy.data.materials.get(b["to"])
    if to is None and b.get("copy_of"):
        src_mat = bpy.data.materials.get(b["copy_of"])
        if src_mat:
            to = src_mat.copy()                      # (its texture kept: "glb_patch" tints it)
            to.name = b["to"]
    if to is None and b.get("new"):
        to = bpy.data.materials.new(b["to"])         # (its look from "materials")
    if to is None:
        raise SystemExit("remat_boxes: no material %s" % b["to"])
    eye = Vector(b["facing"]) if b.get("facing") else None
    moved = 0
    for o in [o for o in meshes if all(o not in corner[k]["spin"] + corner[k]["cal"] for k in CORNERS)]:
        idx = {i for i, sl in enumerate(o.material_slots) if sl.material and matches(sl.material.name, b.get("mats", [".*"]))}
        if not idx:
            continue
        hit = [p for p in o.data.polygons if p.material_index in idx and x0 <= p.center.x <= x1
            and y0 <= p.center.y <= y1 and z0 <= p.center.z <= z1 and (eye is None or (eye - p.center).dot(p.normal) > 0.0)]
        if not hit:
            continue
        names = [sl.material.name if sl.material else "" for sl in o.material_slots]
        if to.name not in names:
            o.data.materials.append(to)
            names.append(to.name)
        ti = names.index(to.name)
        for p in hit:
            p.material_index = ti
        moved += len(hit)
    print("remat: %d faces in %s -> %s" % (moved, b["box"], b["to"]))

# ── the cockpit: the steering wheel, the gear lever and the handbrake cut out as
# parts of their own (the game turns, moves and pulls them), and where the
# driver's eyes are ────────────────────────────────────────────────────────

def split_out(name, what):
    """The parts named by what ({"parts": [name patterns], "box": [...], "cut":
    bool}) made one object, `name`; out of the parts they were in."""
    pieces = []
    for o in [o for o in meshes if all(o not in corner[k]["spin"] + corner[k]["cal"] for k in CORNERS)]:
        if matches(o.name, what.get("parts", [])):
            pieces.append(o)
            continue
        if "mats" in what:
            # faces of these materials (in the box, if it's given)
            mi = {i for i, sl in enumerate(o.material_slots) if sl.material and matches(sl.material.name, what["mats"])}
            x0, x1, y0, y1, z0, z1 = what.get("box", [-9, 9, -9, 9, -9, 9])
            idx = {p.index for p in o.data.polygons if p.material_index in mi
                and x0 <= p.center.x <= x1 and y0 <= p.center.y <= y1 and z0 <= p.center.z <= z1}
        elif "box" in what:
            idx = loose_in(o, what["box"], what.get("cut", False))
        else:
            continue
        if not idx:
            continue
        d = o.copy()
        d.data = o.data.copy()
        bpy.context.collection.objects.link(d)
        for ob, keep in ((d, True), (o, False)):
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            bmesh.ops.delete(bm, geom=[f for f in bm.faces if (f.index in idx) != keep], context='FACES')
            strip_loose(bm)
            bm.to_mesh(ob.data)
            bm.free()
        meshes.append(d)
        pieces.append(d)
    for o in list(meshes):
        if len(o.data.polygons) == 0:
            meshes.remove(o)
            bpy.data.objects.remove(o, do_unlink=True)
    pieces = [o for o in pieces if o in meshes]
    if not pieces:
        raise SystemExit("cockpit: nothing found for %s (%s)" % (name, what))
    bpy.ops.object.select_all(action='DESELECT')
    for o in pieces:
        o.select_set(True)
    vl.objects.active = pieces[0]
    for o in pieces[1:]:
        meshes.remove(o)
    if len(pieces) > 1:
        bpy.ops.object.join()
    j = vl.objects.active
    j.name = name
    j.data.name = name
    return j


def add_formula_wheel(what):
    """A single-seater's steering wheel for a cockpit modelled without one ({"at": [x, y, z]
    its centre, "width": m across the grips, "tilt": degrees its top leans back toward the
    driver}): a flat carbon yoke, rounded, a grip down each side, a screen in the middle and
    a stub of column (the SteeringWheel part). Returns the part, its axis (toward the driver)
    and the grips' radius (the hands' quarter to three)."""
    at = Vector(what["at"])
    half = float(what.get("width", 0.27)) * 0.5
    tilt = math.radians(float(what.get("tilt", 15.0)))
    n = Vector((0.0, -math.cos(tilt), math.sin(tilt)))         # toward the driver
    up = Vector((0.0, math.sin(tilt), math.cos(tilt)))         # up the wheel's face
    right = Vector((1.0, 0.0, 0.0))
    frame = Matrix((right, up, n)).transposed().to_4x4()      # (local x right, y up its face, z toward the driver)
    frame.translation = at
    mats = {}
    for name, p in (("steer_carbon", {"color": [0.03, 0.03, 0.035], "metal": 0.1, "rough": 0.4}),
            ("steer_grip", {"color": [0.02, 0.02, 0.02], "rough": 0.9}),
            ("steer_screen", {"color": [0.02, 0.05, 0.07], "rough": 0.15, "emit": [0.05, 0.25, 0.35]}),
            ("steer_button", {"color": [0.8, 0.12, 0.05], "rough": 0.5})):
        mats[name] = bpy.data.materials.new(name)
        spec.setdefault("materials", []).insert(0, ["^%s$" % name, p])
    bm = bmesh.new()
    def box(c, size, mi, rot=None):
        m = frame @ Matrix.Translation(Vector(c)) @ (rot or Matrix.Identity(4)) @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
        r = bmesh.ops.create_cube(bm, size=1.0, matrix=m)
        for f in {f for v in r["verts"] for f in v.link_faces}:
            f.material_index = mi
    # the yoke: a wide plate, its lower corners cut back (a few boxes give the shape)
    box((0.0, 0.0, 0.0), (half * 1.55, 0.11, 0.028), 0)
    box((0.0, 0.035, 0.0), (half * 1.2, 0.07, 0.03), 0)
    box((0.0, -0.06, -0.004), (half * 0.9, 0.04, 0.026), 0)
    # the grips: down each side, a little toed in at the bottom
    for sx in (-1.0, 1.0):
        rot = Matrix.Rotation(sx * math.radians(-8.0), 4, 'Z')
        bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.021, radius2=0.021, depth=0.125,
            matrix=frame @ Matrix.Translation(Vector((sx * half, -0.005, 0.004))) @ rot @ Matrix.Rotation(math.radians(90.0), 4, 'X'))
        for f in bm.faces:
            if f.material_index == 0 and not f.tag and all((frame.inverted() @ v.co).x * sx > half - 0.024 for v in f.verts):
                f.material_index = 1
                f.tag = True
    # the screen and the buttons (on the driver's face of it)
    box((0.0, 0.012, 0.017), (0.1, 0.05, 0.006), 2)
    for bx, by in ((-0.07, 0.03), (0.07, 0.03), (-0.07, -0.02), (0.07, -0.02)):
        box((bx, by, 0.017), (0.016, 0.016, 0.008), 3)
    # the column's stub (the quick release) behind it
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.028, radius2=0.022, depth=0.07,
        matrix=frame @ Matrix.Translation(Vector((0.0, 0.0, -0.045))))
    me = bpy.data.meshes.new("SteeringWheel")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("SteeringWheel", me)
    bpy.context.collection.objects.link(o)
    for mn in ("steer_carbon", "steer_grip", "steer_screen", "steer_button"):
        o.data.materials.append(mats[mn])
    s = o.data.attributes.new("solo", 'INT', 'FACE')        # (the body's budget leaves it whole)
    s.data.foreach_set("value", [1] * len(o.data.polygons))
    meshes.append(o)
    print("cockpit: a race wheel added at %s, %.0f mm across, tilted %.0f deg" % (tuple(round(c, 3) for c in at), half * 2000, math.degrees(tilt)))
    return o, n, half


def add_shifter(what, top):
    """A gear lever for an interior modelled without one ({"at": [x, y], "height": m,
    "lean": degrees}): a rod and a knob (the Shifter part) standing on what's under
    "at" (the tunnel, found by a ray down from `top`, below the dash), leaning back
    toward the driver, the knob "height" above the tunnel; in a leather boot (left in
    the body: it doesn't move, it's wide enough for the rod to swing in). Returns the
    part, its pivot (below the boot, as a modelled lever's) and its knob."""
    trees = [BVHTree.FromPolygons([v.co for v in o.data.vertices], [p.vertices for p in o.data.polygons])
        for o in meshes if len(o.data.polygons)]
    def floor(px, py):
        hits = [h[0].z for h in (t.ray_cast(Vector((px, py, top)), Vector((0, 0, -1))) for t in trees) if h[0] is not None]
        return max(hits) if hits else None
    x, y = what["at"]
    z = floor(x, y)
    if z is None:
        raise SystemExit("cockpit: no tunnel under the gear lever at %s" % what["at"])
    foot = Vector((x, y, z))
    lean = math.radians(what.get("lean", 10.0))
    up = Vector((0.0, -math.sin(lean), math.cos(lean)))
    knob = foot + up * (what.get("height", 0.18) / math.cos(lean))
    rot = Vector((0, 0, 1)).rotation_difference(up).to_matrix().to_4x4()
    mats = {}
    for name, p in (("shift_rod", {"color": [0.03, 0.03, 0.03], "metal": 0.6, "rough": 0.35}),
            ("shift_knob", {"color": [0.022, 0.022, 0.022], "rough": 0.5}),
            ("shift_boot", {"color": [0.028, 0.026, 0.025], "rough": 0.85})):
        mats[name] = bpy.data.materials.new(name)
        spec.setdefault("materials", []).insert(0, ["^%s$" % name, p])
    def mesh_obj(name, bm, mat_names):
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        for f in me.polygons:
            f.use_smooth = True
        o = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(o)
        for mn in mat_names:
            o.data.materials.append(mats[mn])
        meshes.append(o)
        return o
    # the rod (from just under the tunnel's top) and the knob, a ball a little taller than wide
    bm = bmesh.new()
    a = foot - up * 0.01
    ln = (knob - a).length
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.0065, radius2=0.0065, depth=ln,
        matrix=Matrix.Translation((a + knob) * 0.5) @ rot)
    n_rod = len(bm.faces)
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=0.021,
        matrix=Matrix.Translation(knob + up * 0.008) @ rot @ Matrix.Diagonal((1.0, 1.0, 1.2, 1.0)))
    bm.faces.ensure_lookup_table()
    for f in bm.faces[n_rod:]:
        f.material_index = 1
    g = mesh_obj("Shifter", bm, ["shift_rod", "shift_knob"])
    # the boot: three rings round the rod's foot (the lowest on the tunnel, each point
    # dropped onto it), its wall doubled inside (the open top shows no hole through it)
    bm = bmesh.new()
    seg = 16
    rings = []
    for k, (r, dz) in enumerate(((0.068, -0.004), (0.052, 0.024), (0.03, 0.046))):
        ring = []
        for i in range(seg):
            t = 2.0 * math.pi * i / seg
            px, py = x + r * math.cos(t), y + r * math.sin(t)
            pz = (floor(px, py) or z) + dz if k == 0 else z + dz
            ring.append(bm.verts.new((px, py, pz)))
        rings.append(ring)
    inner = [[bm.verts.new(foot + (v.co - foot) * Vector((0.9, 0.9, 1.0))) for v in ring] for ring in rings]
    for k in range(len(rings) - 1):
        for i in range(seg):
            j = (i + 1) % seg
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
            bm.faces.new((inner[k][j], inner[k][i], inner[k + 1][i], inner[k + 1][j]))
    for i in range(seg):
        j = (i + 1) % seg
        bm.faces.new((rings[-1][i], rings[-1][j], inner[-1][j], inner[-1][i]))
    boot = mesh_obj("ShifterBoot", bm, ["shift_boot"])
    s = boot.data.attributes.new("solo", 'INT', 'FACE')    # (the body's budget leaves it whole)
    s.data.foreach_set("value", [1] * len(boot.data.polygons))
    print("cockpit: a gear lever added on the tunnel at %s, its knob at %s" % (
        tuple(round(c, 3) for c in foot), tuple(round(c, 3) for c in knob)))
    return g, foot - up * 0.08, knob


def pca(v):
    c = v.mean(axis=0)
    w, e = np.linalg.eigh(np.cov((v - c).T))
    return c, [Vector(e[:, k]) for k in range(3)]     # smallest spread first


def game(v):
    return [float(v[0]), float(v[2]), float(-v[1])]      # the game's axes: y up, -z forward


def gdir(d):
    return [float(d[0]), float(d[2]), float(-d[1])]


cockpit = spec.get("cockpit")
cock_parts = {}                    # name -> (object, pivot in the car's frame)
if cockpit:
    cock = {"gearbox": cockpit.get("gearbox", "h5")}
    if "seats" in cockpit:
        cock["seats"] = int(cockpit["seats"])         # (1: a single-seater, no co-driver)
    if "pose" in cockpit:
        cock["pose"] = str(cockpit["pose"])           # ("formula": the driver lies back)
    # the steering wheel: its axis is the way it's thinnest (toward the driver); the rim
    # is its outer ring: the plane and the radius the gloves grip
    if "add" in cockpit["wheel"]:
        w, n_add, r_add = add_formula_wheel(cockpit["wheel"]["add"])
        cockpit["wheel"]["axis"] = list(n_add)
        cockpit["wheel"]["radius"] = r_add
    else:
        w = split_out("SteeringWheel", cockpit["wheel"])
    v = verts(w)
    c0, ax = pca(v)
    n = ax[0] if ax[0].y < 0 else -ax[0]              # toward the driver: back (and up)
    u, t = ax[1], ax[2]
    if "axis" in cockpit["wheel"]:
        # (given: a wheel whose shape misleads, its thinnest way not its column: a squat
        # rectangular race wheel on a deep hub)
        n = Vector(cockpit["wheel"]["axis"]).normalized()
        u = n.cross(Vector((1.0, 0.0, 0.0))).normalized()
        t = n.cross(u).normalized()
    d = v - np.array(c0)
    along = d @ np.array(n)
    flat = d - np.outer(along, np.array(n))
    r = np.linalg.norm(flat, axis=1)
    rmax = np.percentile(r, 98)                       # (a stray bit further out doesn't make the rim)
    rim = (r > rmax * 0.8) & (r < rmax * 1.1)
    pu, pt = flat[rim] @ np.array(u), flat[rim] @ np.array(t)
    centre = Vector(c0) + u * float((pu.max() + pu.min()) * 0.5) + t * float((pt.max() + pt.min()) * 0.5) \
        + n * float(along[rim].mean())
    rr = np.linalg.norm((v[rim] - np.array(centre)) - np.outer((v[rim] - np.array(centre)) @ np.array(n), np.array(n)), axis=1)
    rim_r = float(cockpit["wheel"].get("radius", rr.mean()))     # (given: a cut that caught the stalks too)
    cock["wheel"] = {"centre": game(centre), "axis": gdir(n), "radius": rim_r}
    cock_parts["SteeringWheel"] = (w, centre)
    # the gear lever: it pivots below its boot, on the line from the knob down through its foot
    if "shifter" in cockpit and "add" in cockpit["shifter"]:
        g, pivot, knob = add_shifter(cockpit["shifter"]["add"], centre.z)
        cock["shifter"] = {"pivot": game(pivot), "knob": game(knob)}
        cock_parts["Shifter"] = (g, pivot)
    elif "shifter" in cockpit:
        g = split_out("Shifter", cockpit["shifter"])
        v = verts(g)
        z = v[:, 2]
        foot = Vector(v[z < z.min() + 0.012].mean(axis=0))
        knob = Vector(v[z > z.max() - 0.03].mean(axis=0))
        pivot = foot + (foot - knob).normalized() * cockpit["shifter"].get("below", 0.08)
        cock["shifter"] = {"pivot": game(pivot), "knob": game(knob)}
        cock_parts["Shifter"] = (g, pivot)
    # the handbrake: a lever along its length, pivoting at one end ("pivot": "rear", the
    # usual one between the seats; "bottom", a rally car's tall hydraulic one)
    if "handbrake" in cockpit:
        h = split_out("Handbrake", cockpit["handbrake"])
        v = verts(h)
        c, ax = pca(v)
        a = ax[2]
        proj = (v - np.array(c)) @ np.array(a)
        e1, e2 = Vector(c) + a * float(proj.min()), Vector(c) + a * float(proj.max())
        how = cockpit["handbrake"].get("pivot", "rear")
        if (how == "rear" and e2.y < e1.y) or (how == "bottom" and e2.z < e1.z) or (how == "front" and e2.y > e1.y):
            e1, e2 = e2, e1
        cock["handbrake"] = {"pivot": game(e1), "grip": game(e1.lerp(e2, 0.82))}
        cock_parts["Handbrake"] = (h, e1)
    # the driver's eyes, unless the spec says: from the seat behind the wheel (rays: down
    # onto its cushion, back onto its back), the hips on it, the eyes above them (the crew
    # are near real size in here: cockpit.gd OWN_SCALE) and their helmet clear of the roof
    if "eye" in cockpit:
        eye = Vector(cockpit["eye"])
    else:
        trees = [BVHTree.FromPolygons([v.co for v in o.data.vertices], [p.vertices for p in o.data.polygons])
            for o in meshes if o is not w and len(o.data.polygons)]
        def hit(p, d):
            hits = [h for h in (t.ray_cast(Vector(p), Vector(d)) for t in trees) if h[0] is not None]
            return min(hits, key=lambda h: h[3]) if hits else None
        def cast(p, d):
            h = hit(p, d)
            return h[0] if h else None
        sx = centre.x
        # the cushion: rays down behind the wheel; of what they land on that's flat (not the
        # back, the bolsters), the highest (not the floor in front of the seat, beside it)
        flat = [h[0].z for h in (hit((sx + dx, centre.y - dy, centre.z + 0.3), (0, 0, -1))
            for dx in (-0.06, 0.0, 0.06) for dy in (0.3, 0.38, 0.46, 0.54, 0.62))
            if h and h[0].z < centre.z - 0.12 and abs(h[1].z) > 0.75]
        top = max(flat) if flat else None
        seat_z = float(np.median([z for z in flat if z > top - 0.04])) if flat else centre.z - 0.3
        eye = Vector((sx, 0.0, seat_z + 0.08 + 0.69))     # their thighs' joints 8 cm up, their eyes 0.69 above
        # the back at waist, chest and shoulder height (a headrest on posts lets rays through
        # higher up), followed on up to the eyes (it leans back), the head in front of it
        pts = [(seat_z + dz, h.y) for dz in (0.25, 0.35, 0.45) for dx in (-0.05, 0.0, 0.05)
            for h in [cast((sx + dx, centre.y, seat_z + dz), (0, -1, 0))] if h and centre.y - 1.2 < h.y < centre.y - 0.3]
        if len(pts) >= 2 and len({round(p[0], 3) for p in pts}) >= 2:
            a = np.polyfit([p[0] for p in pts], [p[1] for p in pts], 1)
            back_y = float(np.clip(np.polyval(a, eye.z), np.median([p[1] for p in pts]) - 0.2, np.median([p[1] for p in pts])))
        else:
            back_y = float(np.median([p[1] for p in pts])) if pts else centre.y - 0.75
        eye.y = float(np.clip(back_y + 0.16, centre.y - 0.75, centre.y - 0.48))
        # the roof over the head (the highest of a few rays: not a cage tube)
        ups = [h.z for h in (cast(eye + Vector((dx, dy, 0.0)), (0, 0, 1)) for dx in (-0.08, 0.08) for dy in (-0.08, 0.08)) if h]
        roof = Vector((eye.x, eye.y, max(ups))) if ups else None
        if roof and roof.z - eye.z < 0.13:
            eye.z = roof.z - 0.13
        print("cockpit: seat at %.3f, its back at %.3f, the roof %s" % (seat_z, back_y, roof and round(roof.z, 3)))
    cock["eye"] = game(eye)
    cock["side"] = "right" if centre.x > 0 else "left"
    # the windshield (the mud and the wipers go on it): the glass in front of the
    # driver that faces forward, from its bottom edge to its top
    gl = [m for m in bpy.data.materials if matches(m.name, spec.get("glass", []))]
    pts = []
    for o in meshes:
        idx = {i for i, sl in enumerate(o.material_slots) if sl.material in gl}
        for p in o.data.polygons:
            if p.material_index in idx and p.normal.y > 0.35 and p.center.y > centre.y and p.center.z > centre.z:
                pts.extend(o.data.vertices[k].co.copy() for k in p.vertices)
    if pts:
        pv = np.array([q[:] for q in pts])
        lo, hi = pv[pv[:, 2] < pv[:, 2].min() + 0.03], pv[pv[:, 2] > pv[:, 2].max() - 0.03]
        cock["windshield"] = {"bottom": game((0.0, float(lo[:, 1].mean()), float(pv[:, 2].min()))),
            "top": game((0.0, float(hi[:, 1].mean()), float(pv[:, 2].max()))),
            "width": float(pv[:, 0].max() - pv[:, 0].min())}
    # the rear-view mirror's glass (the game shows the road behind in it): those faces turned to the driver
    if "mirror" in cockpit:
        what = cockpit["mirror"]
        x0, x1, y0, y1, z0, z1 = what.get("box", [-9, 9, -9, 9, -9, 9])
        mnrm, mpts = Vector((0.0, 0.0, 0.0)), []
        for o in meshes:
            mi = {i for i, sl in enumerate(o.material_slots) if sl.material and matches(sl.material.name, what.get("mats", [".*"]))}
            for p in o.data.polygons:
                c = p.center
                if p.material_index in mi and x0 <= c.x <= x1 and y0 <= c.y <= y1 and z0 <= c.z <= z1 and p.normal.dot(eye - c) > 0.0:
                    mnrm += p.normal * p.area
                    mpts.extend(o.data.vertices[k].co.copy() for k in p.vertices)
        if mpts and mnrm.length > 0.0:
            mn = mnrm.normalized()
            mc0 = sum(mpts, Vector((0.0, 0.0, 0.0))) / len(mpts)
            mu = Vector((0.0, 0.0, 1.0)).cross(mn).normalized()       # across the glass
            mv = mn.cross(mu)                                           # up it
            pu, pv = [(q - mc0).dot(mu) for q in mpts], [(q - mc0).dot(mv) for q in mpts]
            mc = mc0 + mu * ((max(pu) + min(pu)) * 0.5) + mv * ((max(pv) + min(pv)) * 0.5)
            cock["mirror"] = {"centre": game(mc), "normal": gdir(mn), "size": [max(pu) - min(pu), max(pv) - min(pv)]}
            print("cockpit: the mirror at %s, %.0f x %.0f mm" % (tuple(round(x, 3) for x in mc), (max(pu) - min(pu)) * 1000, (max(pv) - min(pv)) * 1000))
    spec["_cock"] = cock
    print("cockpit: wheel at %s r %.3f axis %s, %s-hand drive, eyes %s" % (tuple(round(x, 3) for x in centre), rr.mean(),
        tuple(round(x, 2) for x in n), cock["side"], tuple(round(x, 3) for x in eye)))
if snapshot:
    bpy.ops.wm.save_as_mainfile(filepath=snapshot, compress=True)
if survey_parts:
    print("PARTS (x right, y forward, z up; m)")
    for o in sorted(meshes, key=lambda o: o.name):
        v = verts(o)
        if len(v) == 0:
            continue
        mats = sorted({sl.material.name for sl in o.material_slots if sl.material})
        print("  %-30s %6d tris  x %5.2f..%5.2f y %5.2f..%5.2f z %5.2f..%5.2f  %s" % (o.name[:30], sum(len(p.vertices) - 2 for p in o.data.polygons),
            v[:, 0].min(), v[:, 0].max(), v[:, 1].min(), v[:, 1].max(), v[:, 2].min(), v[:, 2].max(), ",".join(mats)[:70]))
    raise SystemExit(0)
if survey:
    rows = {}
    for o in meshes:
        for p in o.data.polygons:
            sl = o.material_slots[p.material_index] if p.material_index < len(o.material_slots) else None
            name = sl.material.name if sl and sl.material else "<none>"
            r = rows.setdefault(name, {"area": 0.0, "lo": [9e9] * 3, "hi": [-9e9] * 3, "objs": set(), "n": 0})
            r["area"] += p.area
            r["n"] += 1
            r["objs"].add(o.name)
            for i in range(3):
                r["lo"][i] = min(r["lo"][i], p.center[i])
                r["hi"][i] = max(r["hi"][i], p.center[i])
    print("SURVEY (x right, y forward, z up; m)")
    for name in sorted(rows, key=lambda n: -rows[n]["area"]):
        r = rows[name]
        m = bpy.data.materials.get(name)
        col = ""
        if m:
            b = next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None) if m.use_nodes else None
            c = b.inputs["Base Color"].default_value if b else m.diffuse_color
            tex = [n.image.name for n in m.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image] if m.use_nodes else []
            col = "col %.2f %.2f %.2f a %.2f %s" % (c[0], c[1], c[2], b.inputs["Alpha"].default_value if b else 1.0, ",".join(tex))
        print("  %-26s %6d f %6.3f m2  x %5.2f..%5.2f y %5.2f..%5.2f z %5.2f..%5.2f  %s | %s" % (name[:26], r["n"], r["area"],
            r["lo"][0], r["hi"][0], r["lo"][1], r["hi"][1], r["lo"][2], r["hi"][2], col, ",".join(sorted(r["objs"]))[:60]))
    raise SystemExit(0)


# ── materials ────────────────────────────────────────────────────────────
def look(mat, p):
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    col = p.get("color", [0.5, 0.5, 0.5])
    bsdf.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
    bsdf.inputs["Metallic"].default_value = p.get("metal", 0.0)
    bsdf.inputs["Roughness"].default_value = p.get("rough", 0.5)
    if p.get("alpha", 1.0) < 1.0:
        bsdf.inputs["Alpha"].default_value = p["alpha"]
        mat.blend_method = 'BLEND'
    if p.get("emit"):
        e = p["emit"]
        bsdf.inputs["Emission Color"].default_value = (e[0], e[1], e[2], 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.0
    if p.get("texture"):
        path = p["texture"]
        for d in tex_dirs:
            hit = next((os.path.join(r, f) for r, _, fs in os.walk(d) for f in fs if f.lower() == os.path.basename(path).lower()), None)
            if os.path.exists(os.path.join(d, path)) or hit:
                path = os.path.join(d, path) if os.path.exists(os.path.join(d, path)) else hit
                break
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(path)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if p.get("alpha_from_texture"):
            nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
            mat.blend_method = 'BLEND'

# the usual looks, by name ("materials": [[pattern, "glass"], ...])
LOOKS = {
    "glass": {"color": [0.02, 0.025, 0.03], "rough": 0.03, "alpha": 0.4},
    "black": {"color": [0.02, 0.02, 0.02], "rough": 0.6},
    "gloss_black": {"color": [0.015, 0.015, 0.015], "rough": 0.15},
    "carbon": {"color": [0.03, 0.03, 0.035], "rough": 0.35},
    "rubber": {"color": [0.025, 0.025, 0.025], "rough": 0.9},
    "interior": {"color": [0.05, 0.05, 0.055], "rough": 0.8},
    "chrome": {"color": [0.9, 0.9, 0.9], "metal": 1.0, "rough": 0.08},
    "silver": {"color": [0.75, 0.75, 0.77], "metal": 1.0, "rough": 0.3},
    "dark_metal": {"color": [0.25, 0.25, 0.26], "metal": 1.0, "rough": 0.45},
    "red_lens": {"color": [0.55, 0.02, 0.02], "rough": 0.1, "emit": [0.08, 0.0, 0.0]},
    "amber_lens": {"color": [0.9, 0.42, 0.03], "rough": 0.1, "emit": [0.06, 0.03, 0.0]},
    "clear_lens": {"color": [0.85, 0.86, 0.88], "metal": 0.6, "rough": 0.05},
    "white": {"color": [0.85, 0.85, 0.85], "rough": 0.5},
    "rim": {"color": [0.72, 0.73, 0.75], "metal": 0.6, "rough": 0.35},
}
if bpy.data.materials.get("tyre_sidewall"):
    look(bpy.data.materials["tyre_sidewall"], LOOKS["rubber"])
for mat in list(bpy.data.materials):
    for pat, p in spec.get("materials", []):
        if re.search(pat, mat.name, re.I):
            if isinstance(p, str):
                p = LOOKS[p]
            elif "look" in p:
                p = dict(LOOKS[p["look"]], **p)
            look(mat, p)
            break
# a material's shine put right, its textures kept ("finish": [[pattern, {"metal", "rough"}]]):
# an FBX's materials can come in half metal and mirror smooth
for mat in bpy.data.materials:
    for pat, p in spec.get("finish", []):
        if re.search(pat, mat.name, re.I) and mat.use_nodes:
            for b in [n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED']:
                for key, inp in (("metal", "Metallic"), ("rough", "Roughness")):
                    if key in p and not b.inputs[inp].is_linked:
                        b.inputs[inp].default_value = p[key]
            break
# lamps that glow in their own colours ("glow": [[pattern, strength]]): the emission is the
# material's own colour (its texture), so a game rip's white glow mask over the whole light
# cluster doesn't turn red tail lights white; strength 0 puts the glow out
for mat in bpy.data.materials:
    for pat, k in spec.get("glow", []):
        if re.search(pat, mat.name, re.I) and mat.use_nodes:
            nt = mat.node_tree
            for b in [n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED']:
                for l in list(b.inputs["Emission Color"].links):
                    nt.links.remove(l)
                bc = b.inputs["Base Color"]
                if bc.is_linked:
                    nt.links.new(bc.links[0].from_socket, b.inputs["Emission Color"])
                else:
                    b.inputs["Emission Color"].default_value = bc.default_value
                b.inputs["Emission Strength"].default_value = k
            break
# paint parts shaped by a normal map: painted, each keeping its map
paint_n = []
for mat in [m for m in bpy.data.materials if matches(m.name, spec.get("paint_normal", []))]:
    img = next((n.image for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image), None) if mat.use_nodes else None
    look(mat, {"color": [0.8, 0.1, 0.1], "metal": 0.0, "rough": 0.3})
    if img:
        img.colorspace_settings.name = 'Non-Color'
        nt = mat.node_tree
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(tex.outputs["Color"], nm.inputs["Color"])
        bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    mat.name = "paint_n%d" % len(paint_n)
    paint_n.append(mat)
paint = None
for mat in list(bpy.data.materials):
    if matches(mat.name, spec.get("paint", [])) and paint is None:
        paint = mat
        look(paint, {"color": [0.8, 0.1, 0.1], "metal": 0.0, "rough": 0.3})
        paint.name = "paint"
for o in meshes:
    for slot in o.material_slots:
        if slot.material and slot.material is not paint and matches(slot.material.name, spec.get("paint", [])):
            slot.material = paint
glass = [m for m in bpy.data.materials if matches(m.name, spec.get("glass", []))]
for m in glass:
    if not m.name.startswith("glass_"):          # (a model converted before, imported again: named already)
        m.name = "glass_" + m.name
for m in bpy.data.materials:
    if matches(m.name, spec.get("rims", [])) and not m.name.startswith("rim_"):
        m.name = "rim_" + m.name

# ── join: four wheels (origin at their centres), four calipers, one body ──
def join(objs, name, at):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    vl.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    j = vl.objects.active
    j.name = name
    j.data.name = name
    j.data.transform(Matrix.Translation(-at))
    j.location = at
    return j


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def thin(o, ratio):
    """Decimate o to ratio x its triangles, then copy the normals of the part as
    it was back onto it: the shading stays the original's (a thinned part's own
    normals come out lumpy)."""
    restore_normals(o)
    was = o.copy()
    was.data = o.data.copy()
    bpy.context.collection.objects.link(was)
    m = o.modifiers.new("dec", 'DECIMATE')
    m.ratio = ratio
    vl.objects.active = o
    bpy.ops.object.modifier_apply(modifier=m.name)
    for p in o.data.polygons:
        p.use_smooth = True
    if hasattr(o.data, "use_auto_smooth"):
        o.data.use_auto_smooth = True            # (custom normals need it, Blender < 4.1)
        o.data.auto_smooth_angle = math.pi
    t = o.modifiers.new("normals", 'DATA_TRANSFER')
    t.object = was
    t.use_loop_data = True
    t.data_types_loops = {'CUSTOM_NORMAL'}
    t.loop_mapping = 'POLYINTERP_NEAREST'
    bpy.ops.object.modifier_apply(modifier=t.name)
    bpy.data.objects.remove(was, do_unlink=True)
    store_normals(o)


def decimate(o, most, keep=(), least=0.0, keep_most=0):
    """At most `most` triangles; faces in the materials `keep` (the paint, the
    glass) untouched: only the rest is thinned, to `least` x its triangles at most.
    keep_most: those kept faces thinned too, to that many (a model whose panels are
    subdivided far past what they need), their shading copied back as for the rest."""
    n = tris(o)
    if not most or n <= most:
        return
    idx = {i for i, sl in enumerate(o.material_slots) if sl.material in keep}
    kept = None
    solo = o.data.attributes.get("solo")
    if idx or solo:
        kept = o.copy()
        kept.data = o.data.copy()
        bpy.context.collection.objects.link(kept)
        for ob, inside in ((o, False), (kept, True)):
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            lay = bm.faces.layers.int.get("solo")
            bmesh.ops.delete(bm, geom=[f for f in bm.faces if (f.material_index in idx or (lay is not None and f[lay] == 1)) != inside],
                context='FACES')
            strip_loose(bm)
            bm.to_mesh(ob.data)
            bm.free()
    if kept and keep_most and tris(kept) > keep_most:
        thin(kept, keep_most / tris(kept))
    k = tris(kept) if kept else 0
    rest = tris(o)
    ratio = min(max((most - k) / max(rest, 1), least), 1.0)
    if ratio < 1.0 and rest > 0:
        thin(o, ratio)
    if kept:
        bpy.ops.object.select_all(action='DESELECT')
        kept.select_set(True)
        o.select_set(True)
        vl.objects.active = o
        bpy.ops.object.join()
    print("%s: %d -> %d triangles (%d kept whole)" % (o.name, n, tris(o), k))


# parts that only show through the windows (an interior): thinned harder before the body's budget
for pat, ratio in spec.get("decimate_parts", []):
    for o in meshes:
        if re.search(pat, o.name, re.I) and all(o not in corner[k]["spin"] + corner[k]["cal"] for k in CORNERS):
            n = tris(o)
            if ratio < 1.0:
                thin(o, ratio)
            # thinned to its own ratio (1: kept as it is): the body's budget leaves it alone
            a = o.data.attributes.get("solo") or o.data.attributes.new("solo", 'INT', 'FACE')
            a.data.foreach_set("value", [1] * len(o.data.polygons))
            print("%s: %d -> %d triangles (its own ratio)" % (o.name, n, tris(o)))

for o in meshes:
    if o.data.attributes.get("keep_n") is None:
        store_normals(o)
parts = {"wheels": [], "radius": [], "width": []}
rest = set(meshes) - {o for o, _ in cock_parts.values()}
for name, (o, at) in cock_parts.items():
    join([o], name, at)
for k in CORNERS:
    c = corner[k]["c"]
    w = join(corner[k]["spin"], "Wheel_" + k, c)
    rest -= set(corner[k]["spin"])
    decimate(w, spec.get("wheel_faces"))
    pts = verts(w)
    parts["radius"].append(float((pts[:, 2].max() - pts[:, 2].min()) * 0.5))
    parts["width"].append(float(pts[:, 0].max() - pts[:, 0].min()))
    parts["wheels"].append(game(c))
    if corner[k]["cal"]:
        cal = join(corner[k]["cal"], "Caliper_" + k, c)
        rest -= set(corner[k]["cal"])
        decimate(cal, spec.get("caliper_faces"))
body = join(list(rest), "Body", Vector((0, 0, 0)))
decimate(body, spec.get("body_faces"), [paint] + glass + paint_n, spec.get("body_least", 0.35),   # ("body_least": how far the rest may be thinned)
         spec.get("paint_faces", 0))                                               # ("paint_faces": the paint and glass thinned to that many)
bb = verts(body)
parts["body_min"] = [float(bb[:, 0].min()), float(bb[:, 2].min()), float(-bb[:, 1].max())]
parts["body_max"] = [float(bb[:, 0].max()), float(bb[:, 2].max()), float(-bb[:, 1].min())]
parts["wheelbase"] = spec["wheelbase"]
# the livery's guides: the sills (the paint's lowest point between the axles) and the
# window line (the side glass's lowest point that shows: a window modelled on down
# inside the door doesn't count, a ray from the side meets the door first)
def lowest(mats, seen=False):
    idx = {i for i, sl in enumerate(body.material_slots) if sl.material in mats}
    polys = [p for p in body.data.polygons if p.material_index in idx and abs(p.center.y) < spec["wheelbase"] * 0.25]
    if seen:
        tree = BVHTree.FromPolygons([v.co for v in body.data.vertices], [p.vertices for p in body.data.polygons])
        side = []
        for p in polys:
            for d in (1.0, -1.0):
                hit = tree.ray_cast(Vector((d * 5.0, p.center.y, p.center.z)), Vector((-d, 0.0, 0.0)))
                if hit[2] == p.index:
                    side.append(p)
                    break
        polys = side or polys
    zs = [p.center.z for p in polys]
    return float(min(zs)) if zs else None
parts["sill"] = lowest([paint]) if paint else float(bb[:, 2].min())
parts["belt"] = lowest(glass, True)
if cockpit:
    parts["cockpit"] = spec["_cock"]
if spec.get("lamps"):
    parts["lamps"] = spec["lamps"]  # (the lamps the material names don't give away: CarLook's hints)
if spec.get("view"):
    parts["view"] = spec["view"]    # ("hood": no cabin in the model: driven from over its bonnet)
for o in bpy.data.objects:
    if o.type == 'MESH':
        o.data.validate()          # (the glTF export validates too: then its normals would scramble)
        restore_normals(o)
most = spec.get("tex_max", 512)
# smaller for the parts barely seen ("tex_sizes": [[material pattern, px]]: the images those use)
cap = {}
for pat, px in spec.get("tex_sizes", []):
    for mat in bpy.data.materials:
        if re.search(pat, mat.name, re.I) and mat.use_nodes:
            for nd in mat.node_tree.nodes:
                if nd.type == 'TEX_IMAGE' and nd.image:
                    cap[nd.image.name] = min(cap.get(nd.image.name, most), px)
for img in bpy.data.images:
    most = cap.get(img.name, spec.get("tex_max", 512))
    # an image all one colour (a plain metal or roughness map, a flat tint) needs no more than 4 px
    if img.size[0] > 4 and img.size[1] > 4 and img.channels > 0:
        px = np.empty(img.size[0] * img.size[1] * img.channels, dtype=np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(-1, img.channels)
        if float((px.max(axis=0) - px.min(axis=0)).max()) < 2.0 / 255.0:
            print("%s: one colour, %dx%d -> 4x4" % (img.name, img.size[0], img.size[1]))
            most = 4
    if img.size[0] > most or img.size[1] > most:
        f = float(most) / max(img.size[0], img.size[1])
        img.scale(max(1, int(img.size[0] * f)), max(1, int(img.size[1] * f)))
# WebP holds 8-bit RGB(A) only: a grayscale or a 16-bit / float image (Blender fails to save
# one, and the texture exports with no image) made 8-bit RGBA first
if spec.get("tex_format", "").lower() == "webp":
    for img in list(bpy.data.images):
        if img.users and img.depth not in (24, 32) and img.size[0] > 0 and img.size[1] > 0:
            rgba = bpy.data.images.new(img.name + "_rgba", img.size[0], img.size[1], alpha=True)
            px = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
            img.pixels.foreach_get(px)
            if img.is_float and img.colorspace_settings.name == 'sRGB':
                # (a float image's pixels are linear; an 8-bit sRGB one's are encoded)
                c = px.reshape(-1, 4)
                c[:, :3] = np.where(c[:, :3] <= 0.0031308, c[:, :3] * 12.92,
                    1.055 * np.power(np.clip(c[:, :3], 0.0031308, None), 1.0 / 2.4) - 0.055)
            rgba.pixels.foreach_set(np.clip(px, 0.0, 1.0))
            rgba.colorspace_settings.name = img.colorspace_settings.name
            img.user_remap(rgba)
            print("%s: %d-bit image made 8-bit RGBA for WebP" % (img.name, img.depth))

# a conversion gone wrong says so (it would still export): wheels that don't match side to side or
# corner to corner, the body through the ground, the driver's eyes outside the car
warn = []
r = parts["radius"]
if max(r) > min(r) * 1.06:
    warn.append("the wheels' radii differ: %s" % ", ".join("%.3f" % x for x in r))
w = parts["wheels"]
for a, b, axle in ((0, 1, "front"), (2, 3, "rear")):
    if abs(w[a][0] + w[b][0]) > 0.02 or abs(w[a][1] - w[b][1]) > 0.02 or abs(w[a][2] - w[b][2]) > 0.02:
        warn.append("the %s wheels aren't mirror images: %s / %s" % (axle, w[a], w[b]))
if bb[:, 2].min() < -0.02:
    warn.append("the body goes %.0f mm through the ground" % (-bb[:, 2].min() * 1000))
if cockpit:
    e = spec["_cock"]["eye"]
    lo, hi = parts["body_min"], parts["body_max"]
    if not all(lo[k] < e[k] < hi[k] for k in range(3)):
        warn.append("the driver's eyes %s are outside the body" % e)
for m in warn:
    print("WARNING: %s" % m)

os.makedirs(out_dir, exist_ok=True)
glb = os.path.join(out_dir, spec["id"] + ".glb")
bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', export_yup=True, export_apply=True,
    export_materials='EXPORT', export_image_format=spec.get("tex_format", "AUTO").upper())   # ("webp": far smaller, alpha kept)
# blended materials that aren't see-through made opaque or cut out (tools/glb_alpha.py: many
# models mark everything blended, and Godot draws those in its transparent pass)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb_alpha import fix_alpha
ga = fix_alpha(glb)
print("alpha: %d blended materials -> %d opaque, %d cut out, %d left blended (%s)" % (
    sum(len(v) for v in ga.values()), len(ga["OPAQUE"]), len(ga["MASK"]), len(ga["BLEND"]), ", ".join(ga["BLEND"][:8])))
# the spec's material fixes ("glb_patch": tools/glb_patch.py)
if spec.get("glb_patch"):
    from glb_patch import apply as glb_patch
    print("patched materials: %s" % glb_patch(glb, spec["glb_patch"]))
json.dump(parts, open(os.path.join(out_dir, "parts.json"), "w"), indent=2)
print("wrote %s (%d KB), body %d triangles" % (glb, os.path.getsize(glb) // 1024, tris(body)))
