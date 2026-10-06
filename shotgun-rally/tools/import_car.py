"""Turns a car model (OBJ, FBX or .blend) into a game car: one GLB with a Body,
four wheels and their calipers, plus parts.json (where the wheels are, how big,
where the paint and the windows are). Run with headless Blender, its scripts
off (a .blend can carry Python):

    blender -b -Y --python tools/import_car.py -- tools/cars/<id>.json <model> [texture dir ...]

The spec (tools/cars/<id>.json) says what's what in the model:
  * "pre_scale": the model's units to m before anything else (an FBX in cm: 100)
  * "front": which way its nose points after loading ("+X", "-X", "+Y", "-Y";
    Blender's axes, Z up)
  * "wheelbase": the real car's (m): the model is scaled to it
  * "wheel": name patterns of the parts that spin with a wheel (tyre, rim, hub,
    disc); "caliper": the parts that stay on the hub without spinning. A part
    holding more than one wheel is cut up, each face going to the corner it's in. "straighten": false leaves
    the front wheels as they are (they're found turned by more than 2 deg)
  * "wheel_mats" / "caliper_mats": a model all in one piece: the material
    patterns of its wheels' (calipers') faces, made parts of their own;
    "split_mats": {"name": [patterns]}: more parts of their own ("<part>_name":
    an interior, to thin harder with "decimate_parts")
  * "mirror": name patterns of parts the model only has on one side (a missing
    tyre): copied, mirrored, to the other
  * "drop": name patterns of parts to leave out (badges); "drop_mats": material
    name patterns whose faces go (logos and nameplates: the cars have no real brands);
    "drop_boxes": [{"box": [x0, x1, y0, y1, z0, z1], "mats": [patterns]}]: faces in a
    box in the car's frame (m: x right, y forward, z up from the ground), lettering
    and badges modelled into the body; "retexture": [[file name pattern, file]]: a
    texture swapped for a cleaned copy (a logo painted out)
  * "paint": material name patterns of the body paint: all become one material,
    "paint" (the game paints it from the garage); "glass": the windows' (their
    lowest point along the sides is the window line, for the livery)
  * "materials": [[pattern, {color, metal, rough, alpha, emit, texture}], ...]:
    how a material looks, for models whose materials didn't come with them; or
    one of the usual looks by name (LOOKS: "glass", "chrome", "red_lens" ...), or
    {"look": name, ...changes}. "rims": the wheel material patterns the game
    colours from the garage (renamed "rim")
  * "sidewall": {"mats": [patterns], "from": 0.7}: a wheel modelled with its
    tyre's sidewalls in the rim's material: those faces past "from" x the tyre's
    radius become rubber
  * "decimate_parts": [[name pattern, ratio]]: parts thinned harder first (an
    interior seen through the windows)
  * "wheel_faces" / "body_faces": the most triangles a wheel / the body keeps
    (decimated: the download stays small)
Then every part's transform and modifiers are applied, a front wheel saved
turned is straightened (its axle found from the shape: the tyre's thinnest
way), the car is turned nose to +Y (in the GLB: -Z, the game's forward), scaled
to the wheelbase, its tyres on the ground (z 0) and the middle between the axles
at the origin. Each corner becomes Wheel_FL / FR / RL / RR (and Caliper_..),
its origin at the wheel's centre; the rest is one Body. Images are shrunk to
512 px ("tex_max"). "--survey" after the paths prints every material (where, how big,
its colour) in the car's own frame instead of exporting.
"""
import bpy, bmesh, sys, json, re, math, os
import numpy as np
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
survey = "--survey" in argv
argv = [a for a in argv if a != "--survey"]
spec_path, src = argv[0], argv[1]
tex_dirs = [os.path.dirname(os.path.abspath(src))] + [os.path.abspath(d) for d in argv[2:]]
spec = json.load(open(spec_path))
out_dir = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(spec_path)), "..", "..", "assets", "models", "cars", spec["id"]))
CORNERS = ["FL", "FR", "RL", "RR"]


def matches(name, patterns):
    return any(re.search(p, name, re.I) for p in patterns)


def strip_loose(bm):
    """Vertices and edges no face uses go (some models carry them: they'd stretch a part's bounds)."""
    bmesh.ops.delete(bm, geom=[e for e in bm.edges if not e.link_faces], context='EDGES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')


# ── load: real meshes, modifiers and transforms applied ──────────────────
if src.lower().endswith(".blend"):
    bpy.ops.wm.open_mainfile(filepath=src, load_ui=False)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if src.lower().endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=src)
    else:
        bpy.ops.wm.obj_import(filepath=src)
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
for o in list(bpy.data.objects):
    if matches(o.name, spec.get("drop", [])) or len(o.data.polygons) == 0:
        bpy.data.objects.remove(o, do_unlink=True)
meshes = list(bpy.data.objects)
if spec.get("pre_scale", 1.0) != 1.0:
    for o in meshes:
        o.data.transform(Matrix.Scale(spec["pre_scale"], 4))

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

# images the model was saved with under another name (Sketchfab renames them): found by name
def _key(n):
    n = os.path.splitext(os.path.basename(n))[0].lower()
    n = re.sub(r"\(\d+\)", "", n)
    return re.sub(r"[^a-z0-9]", "", n)

found = {}
for d in tex_dirs:
    for root, _, files in os.walk(d):
        for f in files:
            if f.lower().endswith((".png", ".jpg", ".jpeg", ".tga", ".bmp", ".tif", ".tiff")):
                found.setdefault(_key(f), os.path.join(root, f))
for img in bpy.data.images:
    if img.packed_file or img.source != 'FILE':
        continue
    p = bpy.path.abspath(img.filepath)
    if not os.path.exists(p):
        for k in (_key(img.filepath), _key(img.name)):
            if k in found:
                img.filepath = found[k]
                img.reload()
                break
        else:
            print("missing image:", img.name, img.filepath)


# textures swapped for cleaned copies (a logo painted out): by the image's file name
for pat, f in spec.get("retexture", []):
    path = next((os.path.join(d, f) for d in tex_dirs if os.path.exists(os.path.join(d, f))), f)
    new = None
    for img in list(bpy.data.images):
        if re.search(pat, os.path.basename(bpy.path.abspath(img.filepath)) or img.name, re.I):
            new = new or bpy.data.images.load(path)
            for m in bpy.data.materials:
                if m.use_nodes:
                    for n in m.node_tree.nodes:
                        if n.type == 'TEX_IMAGE' and n.image == img:
                            n.image = new
            print("retextured %s -> %s" % (img.name, f))


def verts(o):
    return np.array([v.co[:] for v in o.data.vertices], dtype=float)


def centre(objs):
    pts = np.vstack([verts(o) for o in objs])
    return Vector(((pts.min(0) + pts.max(0)) * 0.5).tolist()), pts


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
        n.name = o.name + suffix
        meshes.append(n)
        print("%s: %d faces by material" % (n.name, len(n.data.polygons)))
spec["wheel"] = spec.get("wheel", []) + (["_wheelpart$"] if spec.get("wheel_mats") else [])
spec["caliper"] = spec.get("caliper", []) + (["_caliperpart$"] if spec.get("caliper_mats") else [])
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
    n.data.transform(m)
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
                    o.data.transform(m)
                print("straightened %s by %.1f deg" % (k, math.degrees(ang)))
    corner[k]["c"] = centre(corner[k]["spin"])[0]

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
    o.data.transform(M)
for k in CORNERS:
    corner[k]["c"] = M @ corner[k]["c"]
print("scaled x%.4f (model wheelbase %.3f -> %.3f m)" % (s, base, spec["wheelbase"]))

# badges and lettering modelled into the body: the faces inside a box (the car's frame,
# m: x right, y forward, z up) of the given materials go
for b in spec.get("drop_boxes", []):
    x0, x1, y0, y1, z0, z1 = b["box"]
    gone = 0
    for o in [o for o in meshes if all(o not in corner[k]["spin"] + corner[k]["cal"] for k in CORNERS)]:
        idx = {i for i, sl in enumerate(o.material_slots) if sl.material and matches(sl.material.name, b.get("mats", [".*"]))}
        bm = bmesh.new()
        bm.from_mesh(o.data)
        dead = [f for f in bm.faces if f.material_index in idx and x0 <= f.calc_center_median().x <= x1
            and y0 <= f.calc_center_median().y <= y1 and z0 <= f.calc_center_median().z <= z1]
        gone += len(dead)
        bmesh.ops.delete(bm, geom=dead, context='FACES')
        strip_loose(bm)
        bm.to_mesh(o.data)
        bm.free()
    print("dropped %d faces in %s" % (gone, b["box"]))

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
            if os.path.exists(os.path.join(d, path)):
                path = os.path.join(d, path)
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
    m.name = "glass_" + m.name
for m in bpy.data.materials:
    if matches(m.name, spec.get("rims", [])):
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


def decimate(o, most):
    n = tris(o)
    if most and n > most:
        m = o.modifiers.new("dec", 'DECIMATE')
        m.ratio = most / n
        vl.objects.active = o
        bpy.ops.object.modifier_apply(modifier=m.name)
        smooth(o)
        print("%s: %d -> %d triangles" % (o.name, n, tris(o)))


def smooth(o):
    """After a decimation: smooth shading again, creases kept (by angle), so the
    surfaces aren't left faceted."""
    for p in o.data.polygons:
        p.use_smooth = True
    if hasattr(o.data, "use_auto_smooth"):
        o.data.use_auto_smooth = True
        o.data.auto_smooth_angle = math.radians(40.0)


def game(v):
    return [float(v[0]), float(v[2]), float(-v[1])]      # the game's axes: y up, -z forward


# parts that only show through the windows (an interior): thinned harder before the body's budget
for pat, ratio in spec.get("decimate_parts", []):
    for o in meshes:
        if re.search(pat, o.name, re.I) and all(o not in corner[k]["spin"] + corner[k]["cal"] for k in CORNERS):
            n = tris(o)
            m = o.modifiers.new("dec", 'DECIMATE')
            m.ratio = ratio
            vl.objects.active = o
            bpy.ops.object.modifier_apply(modifier=m.name)
            smooth(o)
            print("%s: %d -> %d triangles (its own ratio)" % (o.name, n, tris(o)))

parts = {"wheels": [], "radius": [], "width": []}
rest = set(meshes)
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
        join(corner[k]["cal"], "Caliper_" + k, c)
        rest -= set(corner[k]["cal"])
body = join(list(rest), "Body", Vector((0, 0, 0)))
decimate(body, spec.get("body_faces"))
bb = verts(body)
parts["body_min"] = [float(bb[:, 0].min()), float(bb[:, 2].min()), float(-bb[:, 1].max())]
parts["body_max"] = [float(bb[:, 0].max()), float(bb[:, 2].max()), float(-bb[:, 1].min())]
parts["wheelbase"] = spec["wheelbase"]
# the livery's guides: the sills (the paint's lowest point between the axles) and the window line
mid = abs(bb[:, 1]) < spec["wheelbase"] * 0.25
def lowest(mats):
    idx = {i for i, sl in enumerate(body.material_slots) if sl.material in mats}
    zs = [p.center.z for p in body.data.polygons if p.material_index in idx and abs(p.center.y) < spec["wheelbase"] * 0.25]
    return float(min(zs)) if zs else None
parts["sill"] = lowest([paint]) if paint else float(bb[:, 2].min())
parts["belt"] = lowest(glass)
most = spec.get("tex_max", 512)
for img in bpy.data.images:
    if img.size[0] > most or img.size[1] > most:
        f = float(most) / max(img.size[0], img.size[1])
        img.scale(max(1, int(img.size[0] * f)), max(1, int(img.size[1] * f)))

os.makedirs(out_dir, exist_ok=True)
glb = os.path.join(out_dir, spec["id"] + ".glb")
bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', export_yup=True, export_apply=True,
    export_materials='EXPORT', export_image_format='AUTO')
json.dump(parts, open(os.path.join(out_dir, "parts.json"), "w"), indent=2)
print("wrote %s (%d KB), body %d triangles" % (glb, os.path.getsize(glb) // 1024, tris(body)))
