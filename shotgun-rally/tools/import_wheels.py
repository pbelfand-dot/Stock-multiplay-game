#!/usr/bin/env python3
"""The CC0 wheel library (assets/wheel_packages/Free_Wheels/) converted for the game's WheelPreset
system (scripts/vehicle/wheel_presets.gd): one GLB a wheel in assets/wheels/<id>/<id>.glb with its
parts as separate nodes (Tyre, Rim, and Disc where the source has one), in metres, centred, the axle
along x and the wheel's face at +x (a left wheel is the same one mirrored by the game), plus
assets/wheels/<id>/wheel.json (diameter, width, rim diameter, triangles, source, licence).

    python3 -I tools/import_wheels.py            # everything (stage 1 here, stage 2 in Blender)

Stage 1 (system Python, which has the pxr USD module) unpacks the IceMaan rims, copies the
Innerscene X3D and reads the USD Mini Car Kit's wheels into JSON meshes (Blender here has no
USD import); stage 2 (`blender -b --python tools/import_wheels.py -- --stage2 WORK`) imports them,
splits and orients the parts, and exports the GLBs. The work folder is assets/wheels_work/
(git-ignored, Godot-ignored).

The sources (all CC0): the Innerscene 17 in five-spoke on a 225/45 R17 (real scale: a garage
preset), the IceMaan CC96 pack's four rims (low-poly: far stand-ins), the USD Mini Car Kit's six
wheels (very low-poly: far stand-ins). Which preset uses which: data/wheel_presets.json.
"""
import json
import os
import shutil
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "assets", "wheel_packages", "Free_Wheels")
OUT = os.path.join(ROOT, "assets", "wheels")
WORK = os.path.join(ROOT, "assets", "wheels_work")
USD_WHEELS = ["Normal", "Wide", "Vintage", "LargeRim", "Black", "Red"]


def stage1():
    if os.path.isdir(WORK):
        shutil.rmtree(WORK)
    os.makedirs(WORK)
    open(os.path.join(WORK, ".gdignore"), "w").close()
    jobs = []
    # the Innerscene assembly
    x3d = os.path.join(SRC, "innerscene-17in-five-spoke-wheel-tyre.x3d")
    shutil.copy(x3d, os.path.join(WORK, "innerscene.x3d"))
    jobs.append({"id": "innerscene_street5", "kind": "x3d", "file": "innerscene.x3d",
                 "source": "Innerscene Parts Library: 17 in five-spoke alloy wheel and 225/45 R17 tyre (X3D)",
                 "url": "https://www.innerscene.com/tools/library/3d-parts/17-inch-five-spoke-alloy-wheel-and-tyre-x3d-50c20c60",
                 "licence": "CC0"})
    # the IceMaan rims (the right-hand ones: the game mirrors them for the left)
    zdir = os.path.join(WORK, "icemaan")
    with zipfile.ZipFile(os.path.join(SRC, "ice-maan-cc96-four-rim-pack.zip")) as z:
        for n in z.namelist():
            if n.endswith("_R.fbx") or n.endswith("licence.txt"):
                z.extract(n, zdir)
    for k in range(1, 5):
        rel = os.path.join("icemaan", "CC96", "Rims", "Rims%d_R.fbx" % k)
        if os.path.isfile(os.path.join(WORK, rel)):
            jobs.append({"id": "cc96_rim%d" % k, "kind": "fbx", "file": rel,
                         "source": "IceMaan: Free Low Poly Car CC96 (3 body kits, 4 rims), Rims%d_R.fbx" % k,
                         "url": "https://icemaan.itch.io/free-low-poly-car3-3-body-kits-4-rims", "licence": "CC0"})
    # the USD Mini Car Kit's wheels, read with pxr
    from pxr import Usd, UsdGeom
    for name in USD_WHEELS:
        gdir = os.path.join(SRC, "USD_Mini_Car_Kit", "assets", "wheels", "wheel" + name, "geo")
        geo = next(os.path.join(gdir, f) for f in sorted(os.listdir(gdir)) if f.startswith("wheel%sGeo.usd" % name))
        st = Usd.Stage.Open(geo)
        mesh = None
        for p in st.Traverse():
            if p.IsA(UsdGeom.Mesh):
                mesh = UsdGeom.Mesh(p)
                break
        pts = [tuple(float(c) for c in v) for v in mesh.GetPointsAttr().Get()]
        counts = list(mesh.GetFaceVertexCountsAttr().Get())
        idx = list(mesh.GetFaceVertexIndicesAttr().Get())
        faces = []
        i = 0
        for c in counts:
            faces.append(idx[i:i + c])
            i += c
        part = ["Tyre"] * len(faces)
        subs = UsdGeom.Subset.GetAllGeomSubsets(mesh)
        # the subsets: the tyre is the one holding the outermost faces (the tread), the rest is the rim
        def reach(sub):
            fs = list(sub.GetIndicesAttr().Get())
            best = 0.0
            for f in fs[:400]:
                for vi in faces[f]:
                    y, z = pts[vi][1], pts[vi][2]
                    best = max(best, (y * y + z * z) ** 0.5)
            return best
        if subs:
            tyre_sub = max(subs, key=reach)
            for sub in subs:
                for f in sub.GetIndicesAttr().Get():
                    part[f] = "Tyre" if sub == tyre_sub else "Rim"
            print("  usd wheel%s: subsets %s, the tyre %s" % (name, [x.GetPrim().GetName() for x in subs], tyre_sub.GetPrim().GetName()))
        rel = "usd_%s.json" % name.lower()
        json.dump({"points": pts, "faces": faces, "part": part, "metres_per_unit": UsdGeom.GetStageMetersPerUnit(st)},
                  open(os.path.join(WORK, rel), "w"))
        jobs.append({"id": "usd_%s" % name.lower(), "kind": "usdjson", "file": rel,
                     "source": "USD Working Group: USD_Mini_Car_Kit, wheel%s" % name,
                     "url": "https://github.com/usd-wg/assets/tree/3b75c2dad6a494897557dcca0098257bcf42a8c6/full_assets/Vehicles/USD_Mini_Car_Kit",
                     "licence": "CC0"})
    json.dump(jobs, open(os.path.join(WORK, "jobs.json"), "w"), indent=1)
    r = subprocess.run(["blender", "-b", "--factory-startup", "--python", os.path.abspath(__file__), "--", "--stage2", WORK])
    if r.returncode != 0:
        sys.exit(r.returncode)
    print("wheels: %d converted into %s" % (len(jobs), os.path.relpath(OUT, ROOT)))


# ── stage 2: in Blender ───────────────────────────────────────────────────

def stage2(work):
    import bpy
    import bmesh
    from mathutils import Matrix, Vector

    def clear():
        bpy.ops.wm.read_factory_settings(use_empty=True)

    def mat(name, col, metal, rough):
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
        b.inputs["Metallic"].default_value = metal
        b.inputs["Roughness"].default_value = rough
        return m

    def join(objs, name):
        objs = [o for o in objs if o and o.type == "MESH"]
        if not objs:
            return None
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        o = bpy.context.view_layer.objects.active
        o.name = name
        o.data.name = name
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        return o

    def split_by_material(o, groups):
        """o's faces into one object per group {name: [material names]} (the rest to the first group)."""
        out = {}
        names = [m.name if m else "" for m in o.data.materials]
        for gname, mats in groups.items():
            c = o.copy()
            c.data = o.data.copy()
            bpy.context.collection.objects.link(c)
            bm = bmesh.new()
            bm.from_mesh(c.data)
            keep = set(i for i, n in enumerate(names) if any(n.startswith(x) for x in mats))
            first = gname == list(groups)[0]
            others = set()
            for g2, m2 in groups.items():
                if g2 != gname:
                    others |= set(i for i, n in enumerate(names) if any(n.startswith(x) for x in m2))
            dead = [f for f in bm.faces if not (f.material_index in keep or (first and f.material_index not in others))]
            bmesh.ops.delete(bm, geom=dead, context="FACES")
            bm.to_mesh(c.data)
            bm.free()
            c.name = gname
            out[gname] = c if len(c.data.polygons) else None
        bpy.data.objects.remove(o)
        return out

    def axle_and_face(objs, rim, tyre=None):
        """Turn the parts so the axle runs along x and the face (the rim's spokes: its mass sits
        towards the face) is at +x; centre them on the tyre (the rim's nuts and cap can stand proud
        of it). Returns (diameter, width): the tyre's."""
        allv = [o.matrix_world @ v.co for o in ([tyre] if tyre else objs) for v in o.data.vertices]
        lo = Vector((min(v.x for v in allv), min(v.y for v in allv), min(v.z for v in allv)))
        hi = Vector((max(v.x for v in allv), max(v.y for v in allv), max(v.z for v in allv)))
        size = hi - lo
        axis = min(range(3), key=lambda i: size[i])          # the axle: the thin way
        centre = (hi + lo) * 0.5
        rv = [rim.matrix_world @ v.co for v in rim.data.vertices] if rim else allv
        mean = sum((v[axis] for v in rv), 0.0) / max(1, len(rv))
        face_sign = 1.0 if mean > centre[axis] else -1.0
        # the rotation taking the axle (and the face's way) to +x
        to_x = {0: Matrix.Identity(4), 1: Matrix.Rotation(-1.5707963, 4, "Z"), 2: Matrix.Rotation(1.5707963, 4, "Y")}[axis]
        flip = Matrix.Rotation(3.14159265, 4, "Z") if face_sign < 0 else Matrix.Identity(4)
        m = flip @ to_x @ Matrix.Translation(-centre)
        for o in objs:
            o.matrix_world = m @ o.matrix_world
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        diam = max(size[i] for i in range(3) if i != axis)
        return diam, size[axis]

    def export(jid, parts, meta):
        d = os.path.join(OUT, jid)
        os.makedirs(d, exist_ok=True)
        bpy.ops.object.select_all(action="DESELECT")
        for o in parts.values():
            if o:
                o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(d, jid + ".glb"), export_format="GLB", use_selection=True,
                                  export_apply=True, export_yup=True)
        tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in parts.values() if o)
        meta.update({"id": jid, "parts": sorted(k for k, o in parts.items() if o), "triangles": tris,
                     "axle": "x", "face": "+x", "units": "m"})
        json.dump(meta, open(os.path.join(d, "wheel.json"), "w"), indent=1)
        print("wheel %-20s %6d tris  d %.3f m  w %.3f m  parts %s" % (jid, tris, meta["diameter"], meta["width"], meta["parts"]))

    rubber = lambda: mat("rubber", (0.055, 0.055, 0.06), 0.0, 0.88)
    rimpaint = lambda: mat("rim_paint", (0.72, 0.73, 0.75), 0.75, 0.3)
    metal = lambda: mat("rim_metal", (0.86, 0.87, 0.88), 1.0, 0.18)
    iron = lambda: mat("disc", (0.36, 0.35, 0.34), 0.85, 0.42)
    jobs = json.load(open(os.path.join(work, "jobs.json")))
    for job in jobs:
        clear()
        path = os.path.join(work, job["file"])
        meta = {"source": job["source"], "url": job["url"], "licence": job["licence"]}
        if job["kind"] == "x3d":
            bpy.ops.import_scene.x3d(filepath=path)
            meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
            # the biggest round thing is the tyre, the next the rim; the small bits (cap, nuts, valve) go with the rim
            meshes.sort(key=lambda o: -max(o.dimensions))
            tyre = join([meshes[0]], "Tyre")
            rim_parts = meshes[1:]
            for o in rim_parts[1:]:
                o.data.materials.clear()
                o.data.materials.append(metal())
            rim_parts[0].data.materials.clear()
            rim_parts[0].data.materials.append(rimpaint())
            rim = join(rim_parts, "Rim")
            tyre.data.materials.clear()
            tyre.data.materials.append(rubber())
            diam, width = axle_and_face([tyre, rim], rim, tyre)
            rim_d = max(rim.dimensions[1], rim.dimensions[2])
            meta.update({"diameter": diam, "width": width, "rim_diameter": rim_d, "detail": "hero"})
            export(job["id"], {"Tyre": tyre, "Rim": rim}, meta)
        elif job["kind"] == "fbx":
            bpy.ops.import_scene.fbx(filepath=path)
            src = join([o for o in bpy.context.scene.objects if o.type == "MESH"], "Wheel")
            parts = split_by_material(src, {"Rim": ["Rims"], "Tyre": ["Tires"], "Disc": ["Disc"]})
            for nm, o in parts.items():
                if o:
                    o.data.materials.clear()
                    o.data.materials.append({"Rim": rimpaint, "Tyre": rubber, "Disc": iron}[nm]())
            objs = [o for o in parts.values() if o]
            diam, width = axle_and_face(objs, parts.get("Rim"), parts.get("Tyre"))
            rim = parts.get("Rim")
            rim_d = max(rim.dimensions[1], rim.dimensions[2]) if rim else 0.0
            meta.update({"diameter": diam, "width": width, "rim_diameter": rim_d, "detail": "low"})
            export(job["id"], parts, meta)
        else:
            d = json.load(open(path))
            parts = {}
            for nm in ["Tyre", "Rim"]:
                faces = [f for f, p in zip(d["faces"], d["part"]) if p == nm]
                if not faces:
                    continue
                me = bpy.data.meshes.new(nm)
                me.from_pydata(d["points"], [], faces)
                bm = bmesh.new()                             # (every point came along: drop the other part's)
                bm.from_mesh(me)
                bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
                bm.to_mesh(me)
                bm.free()
                me.validate()
                o = bpy.data.objects.new(nm, me)
                bpy.context.collection.objects.link(o)
                o.data.materials.append(rubber() if nm == "Tyre" else rimpaint())
                parts[nm] = o
            objs = list(parts.values())
            # (their units are tiny: a toy's; the game scales every wheel to the car's anyway)
            for o in objs:
                o.scale = (0.1, 0.1, 0.1)
            bpy.ops.object.select_all(action="DESELECT")
            for o in objs:
                o.select_set(True)
            bpy.context.view_layer.objects.active = objs[0]
            bpy.ops.object.transform_apply(scale=True)
            for o in objs:
                for p in o.data.polygons:
                    p.use_smooth = True
            diam, width = axle_and_face(objs, parts.get("Rim"), parts.get("Tyre"))
            rim = parts.get("Rim")
            rim_d = max(rim.dimensions[1], rim.dimensions[2]) if rim else 0.0
            meta.update({"diameter": diam, "width": width, "rim_diameter": rim_d, "detail": "low"})
            export(job["id"], parts, meta)


if __name__ == "__main__":
    if "--stage2" in sys.argv:
        stage2(sys.argv[sys.argv.index("--stage2") + 1])
    else:
        stage1()
