"""Environment converter: a source model (Poly Haven, Kenney, the owner's packs) to a runtime GLB
for the game, by a spec in tools/environment_specs.json. Run headless (one spec per run):

    blender -b -Y --python shotgun-rally/tools/import_environment.py -- <spec id> [--list]
        [--work DIR] (the unpacked packs somewhere else: another checkout's environment_work)
        [--out FILE] (a trial: write there instead of the spec's runtime file)

A spec ({"id": {...}}):
  src       the source file, relative to assets/environment_packages/ (the CC0 library) or
            assets/environment_work/ (a restored and unpacked pack: tools/restore_environment_assets.py)
  srcs      (instead of src) several files, each one's meshes joined into a part named after
            the file (a kit of separate models into one GLB)
  out       the runtime GLB, relative to assets/environment_runtime/
  objects   (optional) only these objects (names; "*" globs), each kept as a part of its own
  rename    (optional) {source name: part name}
  join      (optional) {part name: [source names]}: pieces that belong together joined into one part
  origin    "base" (each part's origin at the middle of its foot: the game stands it on the
            ground) or "keep"
  scale     (optional) a factor (sources in cm: 0.01)
  max_tex   the longest side a texture keeps (px)
  tex_format "webp" (default) or "jpeg" / "png"
  mode      "props" (default), "tree" (tools/vegetation.py: the LODs and the billboard),
            "building" (tools/buildings.py: light, one baked material, a window mask; one GLB
            per building; extra arguments after the spec id: just those source files) or
            "skyline" (tools/skyline.py: the far tier's silhouettes, no material, all in one
            GLB; extra arguments: just those source files, for a trial with --out)
Each part ends up a node of its own in the GLB, its mesh in its own space; the game takes the
meshes by part name (scripts/stage/env_assets.gd). The source files are only read.
"""
import bpy, fnmatch, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
LIB = os.path.join(GAME, "assets", "environment_packages")
WORK = os.path.join(GAME, "assets", "environment_work")
RUNTIME = os.path.join(GAME, "assets", "environment_runtime")


def spec_for(sid):
    specs = json.load(open(os.path.join(HERE, "environment_specs.json")))
    if sid not in specs:
        raise SystemExit("no spec %s (have: %s)" % (sid, ", ".join(sorted(specs))))
    s = dict(specs[sid])
    s["id"] = sid
    return s


def source_path(rel):
    for root in (LIB, WORK):
        p = os.path.join(root, rel)
        if os.path.exists(p):
            return p
    raise SystemExit("source not found: %s (restore it: tools/restore_environment_assets.py)" % rel)


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ext = os.path.splitext(path)[1].lower()
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    elif ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=path, load_ui=False, use_scripts=False)
    else:
        raise SystemExit("can't read %s" % ext)


def load_kit(paths):
    """Several files into one scene: each file's meshes joined into one part named after it."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for path in paths:
        before = set(bpy.data.objects)
        ext = os.path.splitext(path)[1].lower()
        if ext == ".fbx":
            bpy.ops.import_scene.fbx(filepath=path)
        elif ext in (".glb", ".gltf"):
            bpy.ops.import_scene.gltf(filepath=path)
        elif ext == ".obj":
            bpy.ops.wm.obj_import(filepath=path)
        new = [o for o in bpy.data.objects if o not in before]
        meshes = [o for o in new if o.type == "MESH"]
        flatten(meshes, 1.0)
        for o in new:
            if o.type != "MESH":
                bpy.data.objects.remove(o, do_unlink=True)
        bpy.ops.object.select_all(action="DESELECT")
        for o in meshes:
            o.select_set(True)
        bpy.context.view_layer.objects.active = meshes[0]
        if len(meshes) > 1:
            bpy.ops.object.join()
        part = bpy.context.view_layer.objects.active
        part.name = os.path.splitext(os.path.basename(path))[0].replace("-", "_")


def keep_only(patterns):
    """Deletes every mesh not matching one of the patterns (and empties left with nothing)."""
    keep = [o for o in bpy.context.scene.objects if o.type == "MESH" and any(fnmatch.fnmatch(o.name, p) for p in patterns)]
    if not keep:
        raise SystemExit("no object matches %s" % patterns)
    for o in list(bpy.context.scene.objects):
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    return keep


def flatten(objs, scale):
    """Each part on its own: parents cleared (world transform kept), the transform applied
    (with the spec's scale), so the mesh is in world units at its place in the source."""
    for o in objs:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
        o.scale = (o.scale[0] * scale, o.scale[1] * scale, o.scale[2] * scale)
        o.location = o.location * scale
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def base_origin(o):
    """The part's origin at the middle of its foot (Blender is Z up: lowest z, middle x, y)."""
    import mathutils
    vs = [v.co for v in o.data.vertices]
    if not vs:
        return
    mn = mathutils.Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = mathutils.Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    foot = mathutils.Vector(((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mn.z))
    o.data.transform(mathutils.Matrix.Translation(-foot))
    o.location = o.location + foot


def shrink_textures(max_px):
    for img in bpy.data.images:
        if img.size[0] == 0 or img.size[1] == 0:
            continue
        f = max_px / float(max(img.size[0], img.size[1]))
        if f < 1.0:
            img.scale(max(1, int(img.size[0] * f)), max(1, int(img.size[1] * f)))


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def main():
    global WORK
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not argv or argv[0] == "--list":
        print("\n".join(sorted(json.load(open(os.path.join(HERE, "environment_specs.json"))))))
        return
    out_file = ""
    for flag in ("--work", "--out"):                          # (--work DIR: the packs unpacked elsewhere; --out FILE: a trial)
        if flag in argv:
            k = argv.index(flag)
            if flag == "--work":
                WORK = os.path.abspath(argv[k + 1])
            else:
                out_file = os.path.abspath(argv[k + 1])
            del argv[k:k + 2]
    spec = spec_for(argv[0])
    if spec.get("mode", "props") == "skyline":
        sys.path.insert(0, HERE)
        import skyline
        only = argv[1:]
        if only and not out_file:
            raise SystemExit("just some of the files would make a GLB with just those: give --out FILE (a trial)")
        objs, rows = [], []
        bpy.ops.wm.read_factory_settings(use_empty=True)
        for rel in spec["srcs"]:
            if only and not any(o == os.path.splitext(os.path.basename(rel))[0] for o in only):
                continue
            rows += skyline.convert(spec, source_path(rel), objs)
        skyline.export(objs, out_file or os.path.join(RUNTIME, spec["out"]))
        print("skyline total: %d buildings, %d triangles" % (len(rows), sum(r["tris"] for r in rows)))
        return
    if spec.get("mode", "props") == "building":
        sys.path.insert(0, HERE)
        import buildings
        only = argv[1:]                                        # (optional: just the sources whose name has one of these)
        for rel in spec["srcs"]:
            if only and not any(o in os.path.basename(rel) for o in only):
                continue
            buildings.convert(spec, source_path(rel), WORK, RUNTIME)
        return
    if spec.get("mode", "props") == "tree":
        sys.path.insert(0, HERE)
        import vegetation
        vegetation.convert(spec, None, os.path.join(RUNTIME, spec["out"]))
        return
    if spec.get("srcs"):
        load_kit([source_path(s) for s in spec["srcs"]])
    else:
        load(source_path(spec["src"]))
    objs = keep_only(spec.get("objects", ["*"]))
    flatten(objs, float(spec.get("scale", 1.0)))
    for part, members in spec.get("join", {}).items():          # (pieces that belong together: one part)
        group = [o for o in objs if o.name in members]
        if len(group) > 1:
            bpy.ops.object.select_all(action="DESELECT")
            for o in group:
                o.select_set(True)
            bpy.context.view_layer.objects.active = group[0]
            bpy.ops.object.join()
            for o in group[1:]:
                objs.remove(o)
        if group:
            group[0].name = part
            group[0].data.name = part
    for o in objs:
        name = o.name
        for pat, new in spec.get("rename", {}).items():        # (patterns: some names hide zero-width spaces)
            if fnmatch.fnmatch(o.name.replace("\u200b", ""), pat.replace("\u200b", "")):
                name = new
                break
        o.name = name
        o.data.name = name
        if spec.get("origin", "base") == "base":
            base_origin(o)
    shrink_textures(int(spec.get("max_tex", 2048)))
    out = os.path.join(RUNTIME, spec["out"])
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True, export_apply=True,
        export_materials="EXPORT", export_image_format=spec.get("tex_format", "webp").upper())
    for o in objs:
        d = o.dimensions
        print("part %-28s %7d tris  %.2f x %.2f x %.2f m" % (o.name, tris(o), d.x, d.y, d.z))
    print("wrote %s (%.1f MB)" % (out, os.path.getsize(out) / 1e6))


if __name__ == "__main__":
    main()
