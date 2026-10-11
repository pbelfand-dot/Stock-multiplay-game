#!/usr/bin/env python3
"""Every 3D asset in the repository, where it stands: the source packages (assets/car_packages,
assets/environment_packages, assets/wheel_packages: kept on GitHub, never in a build) and the
game-ready derivatives made from them (assets/models, assets/environment_runtime), joined up
through the vehicle registry (data/vehicles/*.json), the environment library
(data/environment_assets.json), the packages' manifests and the notes below.

    python3 -I tools/asset_audit.py write    # docs/ASSET_INTEGRATION_STATUS.md + data/asset_catalog.json
    python3 -I tools/asset_audit.py check    # exit 1 if a 3D source isn't accounted for, a runtime file
                                             # is missing, the doc is stale or a package could reach a build

The source list comes from git (`git ls-tree HEAD`), so it's complete even in a sparse checkout
without the packages; a derivative's numbers (meshes, triangles, materials, textures, LOD nodes)
are read from its GLB. Nothing is silently skipped: a source that isn't in the game yet is a row
saying what it's waiting for, and one that can't be imported is marked NEEDS REPAIR with why.
"""
import json
import os
import re
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                         # shotgun-rally/
DOC = os.path.join(ROOT, "docs", "ASSET_INTEGRATION_STATUS.md")
CATALOG = os.path.join(ROOT, "data", "asset_catalog.json")
PACKAGE_DIRS = ["assets/car_packages", "assets/environment_packages", "assets/wheel_packages"]
SOURCE_EXT = (".zip", ".rar", ".7z", ".glb", ".gltf", ".fbx", ".obj", ".blend", ".dae", ".usd", ".usda",
              ".usdc", ".usdz", ".x3d", ".3ds", ".max", ".stl", ".ply")

# Statuses
IN_GAME = "In game"
PENDING = "Pending"
ALTERNATE = "Alternate (unused)"
DUPLICATE = "Duplicate"
BLOCKED = "Blocked"
REPAIR = "NEEDS REPAIR"
TEXTURES = "Texture set"

# Sources the registry and the environment library don't explain: what each is and why it isn't
# (or is) in the game. Keyed by the package's path under assets/ (a split archive by its name
# without ".parts/...").
NOTES = {
    # cars
    "car_packages/bmw-m4-widebody-wwwvecarzcom.zip": (DUPLICATE, "the same file as bmw-m4-modified-widebody.zip (SHA-256 751c816b...): one car, KAISER 4 WB (kaiser_4)", "m4_widebody"),
    "car_packages/free-hyper-realistic-bmw-m8-competition-model.zip": (ALTERNATE, "a second M8 Competition (USDZ, 1.19M triangles; part names suggest a Forza extraction); KAISER 8 (kaiser_8) uses bmw-m8-f92-coupe-competition (1).zip, which imports directly. Blender here has no USD import", "m8_f92"),
    "car_packages/porsche-992-gt3-rs.zip": (ALTERNATE, "the second GT3 RS package (a GTA-style port, uncoloured panels); ELFER RS (elfer_rs) uses porsche-992-gt3-rs-2024.zip", "gt3rs_992"),
    "car_packages/textures (1).rar": (DUPLICATE, "byte-identical to the GLS 63's textures.rar in CGTrader_New_Cars/traffic (the GLB embeds the same set)", "gls63"),
    "car_packages/gls63.glb": (DUPLICATE, "byte-identical copy of CGTrader_New_Cars/traffic/mercedes_gls_63_amg's GLB: GRAND SUV 63 (gls)", "gls63"),
    "car_packages/CGTrader_New_Cars/mclaren_p1_gtr": (BLOCKED, "handled as no-AI (scripts only, renders never viewed). The FBX is 3.8M triangles (295k a tyre), kitbashed (another car's engine bay), turned 45 degrees, and has no textures of its own (the package's texture folders are an apartment scene's). Converted to assets/models/cars/p1_gtr for measurement only; not registered", "p1_gtr"),
    "car_packages/Internet_New_Cars/2023-bmw-320i-xdrive-2k.glb": (PENDING, "Track P9: a 2023 BMW 320i (G20) for road and traffic; the GLB is the runtime-ready one, the source zip its original", ""),
    "car_packages/Internet_New_Cars/2023-bmw-320i-xdrive-source.zip": (PENDING, "Track P9: the 320i's original source (the 2k GLB is the one to convert)", ""),
    "car_packages/Track_Mode_Cars/2024-porsche-992-gt3-r.zip": (ALTERNATE, "compared with ELFER R's model (Track P4): the same car, and the same lineage (both are racing-sim ports: this one's materials are ACC-style 'MI_Tyre_Flex_Dry', 'EXT_Carpaint_Inst', 'PHISICS_DASH'). It has per-corner rims, tyres, discs and calipers and a full cockpit (489k triangles), but ELFER R's CGTrader file already imports with its own wheels and cockpit, and its licence is the less restrictive (this one is CC BY-NC-SA 4.0). Kept as the source to fall back on", ""),
    # environment: the owner's packs
    "environment_packages/user_sources/city/31_model_separate_files.rar": (IN_GAME, "", ""),
    # environment: CC0 source packs not in the game yet (Track P9 places them at the circuit and on the stages)
    "environment_packages/cc0/source_packs/kenney/Kenney_City_Kit_Commercial_2.1.zip": (PENDING, "Track P9: shops and offices for the circuit's paddock and town stages", ""),
    "environment_packages/cc0/source_packs/kenney/Kenney_City_Kit_Industrial_2.0.zip": (PENDING, "Track P9: sheds, tanks and chimneys (the circuit's service area, stage dressing)", ""),
    "environment_packages/cc0/source_packs/kenney/Kenney_City_Kit_Suburban_2.0.zip": (PENDING, "Track P9: houses for villages", ""),
    "environment_packages/cc0/source_packs/opengameart/OpenGameArt_Traffic_Road_Assets.zip": (PENDING, "Track P9: signs, cones and barriers", ""),
    "environment_packages/cc0/source_packs/quaternius/Downtown_City_MegaKit_Standard.zip": (PENDING, "Track P9: modular city blocks", ""),
    "environment_packages/cc0/source_packs/quaternius/Universal_Base_Characters_Standard.zip": (PENDING, "Track P9: rigged people for marshals, pit crew and crowds", ""),
}
# Poly Haven source packs: one note for all, the asset named from the file
POLYHAVEN_PLAN = {
    "concrete_road_barrier_02": "the circuit's concrete barriers and the stages' road works",
    "dead_tree_trunk": "forest floor dressing", "dry_branches_medium_01": "forest floor dressing",
    "fern_02": "undergrowth", "fir_sapling": "young firs", "fir_sapling_medium": "young firs",
    "fir_tree_01": "a scanned fir (hero tree near the road)", "grass_medium_01": "grass clumps on verges",
    "modular_chainlink_fence": "fences round the paddock and service roads",
    "modular_electricity_poles": "power lines along rural stages", "moss_01": "rock and trunk moss",
    "old_tyre": "tyre stacks and junk", "pine_roots": "forest floor dressing",
    "pine_sapling_medium": "young pines", "pine_sapling_small": "young pines",
    "pine_tree_01": "a scanned pine (hero tree)", "rock_moss_set_02": "a second set of mossy rocks",
    "security_camera_01": "the pit lane's and garages' cameras", "street_lamp_01": "street lamps",
    "tree_stump_01": "stumps", "tree_stump_02": "stumps",
}
# The environment manifest's original paths -> words that name them in environment_assets.json's "source"
ENV_SOURCE_KEYS = {
    "vegetation/chvegetation_vol5_fbx.rar": "chvegetation vol5",
    "vegetation/tree_robinia_pseudoacacia_fbx.zip": "Robinia",
    "vegetation/tall_pines_blend.zip": "Tall Pines",
    "city/22_buildings_2024_v2.zip": "22 Buildings",
    "city/31_model_separate_files.rar": "31 Model",
    "highway/highway_props_model.rar": "highway props",
    "kenney/kenney_city-kit-roads.zip": "Kenney City Kit (Roads)",
    "polyhaven/rock_moss_set_01_2k": "rock_moss_set_01",
    "polyhaven/rock_face_01_2k": "rock_face_01",
    # the owner's CC0 track props (one GLB: props/track_props.glb, the circuit's pits and marshal posts)
    "Track_Mode_Props/blank-marshal-flag-on-pole.glb": "3DAssets.dev",
    "Track_Mode_Props/double-bay-pit-garage.glb": "3DAssets.dev",
    "Track_Mode_Props/front-quick-lift-jack.glb": "3DAssets.dev",
    "Track_Mode_Props/gravity-fuel-rig-and-hose.glb": "3DAssets.dev",
    "Track_Mode_Props/helmet-equipment-rack.glb": "3DAssets.dev",
    "Track_Mode_Props/marshal-observation-hut.glb": "3DAssets.dev",
    "Track_Mode_Props/pit-gantry-signal-lights.glb": "3DAssets.dev",
    "Track_Mode_Props/pit-wall-monitor-stand.glb": "3DAssets.dev",
    "Track_Mode_Props/pneumatic-wheel-gun-and-hose.glb": "3DAssets.dev",
    "Track_Mode_Props/quick-lift-air-jack-rig.glb": "3DAssets.dev",
    "Track_Mode_Props/rear-quick-lift-jack.glb": "3DAssets.dev",
    "Track_Mode_Props/six-tyre-warmer-rack.glb": "3DAssets.dev",
    "Track_Mode_Props/straight-tyre-stack-wall.glb": "3DAssets.dev",
    "Track_Mode_Props/tyre-stack-warming-blankets.glb": "3DAssets.dev",
}
# What each environment kind is used for and how it's solid (the builders' code)
ENV_USE = {
    "tree": ("every stage, the touge, the loop, the circuit (Biomes picks them)", "trunk cylinder (stage_builder.gd), leaves none", "LOD0 / LOD1 / billboard (BB) parts"),
    "rock": ("rally stages and the touge (verges, cuts)", "box per rock (stage_builder.gd)", "one mesh (low-poly already)"),
    "cliff": ("rally stage cut faces", "the cut's own ribbon", "one mesh"),
    "prop": ("the loop's roadworks and toll plaza, CINDER RIDGE's pits and marshal posts, stage dressing", "box where solid (loop_builder.gd; the pit lane's nose tyre walls)", "one mesh (low-poly already)"),
    "building": ("CUT UP's city front rows", "box per building (loop_builder.gd)", "LOD0 + LOD1"),
    "skyline": ("CUT UP's city far tier (city_skyline.gd)", "none (out of reach)", "LOD1 only (far)"),
}


def git_files():
    """[(path relative to shotgun-rally/, 0)] for everything tracked under the package folders. (No sizes:
    CI's checkout is partial, blob:none, and asking git for a blob's size would download it.)"""
    out = subprocess.run(["git", "-C", ROOT, "ls-tree", "-r", "HEAD", "--"] + PACKAGE_DIRS,
                         capture_output=True, text=True, check=True).stdout
    prefix = subprocess.run(["git", "-C", ROOT, "rev-parse", "--show-prefix"], capture_output=True, text=True).stdout.strip()
    files = []
    for line in out.splitlines():
        path = line.split("\t", 1)[1]
        if path.startswith('"'):
            path = json.loads(path)
        files.append((path[len(prefix):] if prefix and path.startswith(prefix) else path, 0))
    return files


def packages(files):
    """The source packages: archives (a split one as one), loose 3D files, and the folders that hold a
    package's pieces (CGTrader's per-car folders, the USD kit, the Poly Haven texture sets)."""
    pk = {}

    def add(key, size, kind):
        p = pk.setdefault(key, {"path": key, "size": 0, "files": 0, "kind": kind})
        p["size"] += size
        p["files"] += 1

    for path, size in files:
        rel = path[len("assets/"):]
        low = rel.lower()
        parts = rel.split("/")
        if parts[0] == "car_packages" and len(parts) > 3 and parts[1] in ("CGTrader_New_Cars",):
            add("/".join(parts[:3 if parts[2] != "traffic" else 4]), size, "folder")
            continue
        m = re.match(r"(.*)\.parts/[^/]*\.part-[a-z]+$", rel)
        if m:
            add(m.group(1), size, "split archive")
            continue
        if parts[0] == "wheel_packages" and "USD_Mini_Car_Kit" in parts:
            i = parts.index("USD_Mini_Car_Kit")
            sub = parts[i + 1:]
            if len(sub) >= 4 and sub[0] == "assets" and sub[1] in ("wheels", "vehicles") and sub[2] not in ("cards", "thumbnails"):
                add("/".join(parts[:i + 4]), size, "USD asset")
            else:
                add("/".join(parts[:i + 1]) + " (materials, textures, cards)", size, "USD shared files")
            continue
        if parts[0] == "environment_packages" and len(parts) > 3 and parts[1] == "cc0" and parts[2] == "polyhaven":
            add("/".join(parts[:4]), size, "texture set")
            continue
        if low.endswith(SOURCE_EXT):
            add(rel, size, "file")
    return pk


def glb_stats(path):
    """A GLB's numbers: meshes, triangles, materials, images (embedded / external), LOD and
    collision nodes. {} if it isn't there."""
    full = os.path.join(ROOT, path)
    if not os.path.isfile(full):
        return {}
    with open(full, "rb") as f:
        head = f.read(20)
        if head[:4] != b"glTF":
            return {"bad": True}
        jlen = struct.unpack("<I", head[12:16])[0]
        j = json.loads(f.read(jlen))
    acc = j.get("accessors", [])
    tris = 0
    for m in j.get("meshes", []):
        for p in m.get("primitives", []):
            if "indices" in p:
                tris += acc[p["indices"]]["count"] // 3
            elif "POSITION" in p.get("attributes", {}):
                tris += acc[p["attributes"]["POSITION"]]["count"] // 3
    names = [n.get("name", "") for n in j.get("nodes", [])]
    imgs = j.get("images", [])
    return {"meshes": len(j.get("meshes", [])), "tris": tris, "materials": len(j.get("materials", [])),
            "images": len(imgs), "external": sum(1 for i in imgs if "uri" in i and not i["uri"].startswith("data:")),
            "lod_nodes": sum(1 for n in names if re.search(r"(lod\d|_lod|LOD|_BB$)", n)),
            "col_nodes": sum(1 for n in names if re.search(r"(-col|_col\b|^COL_|collision)", n, re.I)),
            "bytes": os.path.getsize(full)}


def mb(n):
    return "%.1f MB" % (n / 1e6) if n >= 1e5 else "%d KB" % max(1, n // 1000)


def import_lods(glb):
    imp = os.path.join(ROOT, glb + ".import")
    if not os.path.isfile(imp):
        return None
    txt = open(imp).read()
    return "meshes/generate_lods=true" in txt


def car_rows(pk, used):
    rows = []
    reg_dir = os.path.join(ROOT, "data", "vehicles")
    for fn in sorted(os.listdir(reg_dir)):
        if not fn.endswith(".json"):
            continue
        v = json.load(open(os.path.join(reg_dir, fn)))
        src = v.get("source", {})
        model = v.get("model", "")
        glb = "assets/models/cars/%s/%s.glb" % (model, model) if model else "assets/models/rally_car.glb"
        st = glb_stats(glb)
        pkg = str(src.get("package", ""))
        matched = []
        for key in pk:
            k = key.split("/")[-1]
            if key.startswith("car_packages/") and (k in pkg or key[len("car_packages/"):] in pkg):
                matched.append(key)
        for key in matched:
            used.add(key)
        modes = []
        if "garage" in v:
            modes.append("rally, touge, cut up" + (", track (%s)" % v["role"] if v.get("role") in ("track", "race_prototype", "formula") else ""))
        if "traffic" in v:
            modes.append("cut-up traffic")
        interior = v.get("interior", {}) or {}
        lods = import_lods(glb)
        problems = list(v.get("limitations", []))
        noai = "no-AI" in json.dumps(src)
        rows.append({
            "name": "%s (%s)" % (v["name"], v["id"]), "category": "car" if "garage" in v else "traffic car",
            "source": ", ".join(matched) if matched else pkg or "-",
            "runtime": glb if st else "(missing: %s)" % glb,
            "licence": str(src.get("license", "") or "see registry"),
            "conversion": "GLB: tools/import_car.py" if model else "GLB: Higgsfield (the game's own body)",
            "materials": ("%d materials, %d textures%s" % (st["materials"], st["images"], " (external .webp)" if st.get("external") else "")) if st else "-",
            "tris": st.get("tris", 0),
            "collision": "physics in code (RallyCar: chassis box + 4 suspension shape casts)" if "garage" in v else "box (Traffic)",
            "lod": "Godot importer LODs (generate_lods)" if lods else ("none" if lods is False else "-"),
            "interior": ("own interior, crew fitted (driver_seat)" if interior.get("own") else "shared cockpit") if "garage" in v else "-",
            "modes": "; ".join(modes) or "-",
            "catalog": ("garage: %s" % ("for sale" if v.get("garage", {}).get("price", 0) else "free")) + ("; traffic list" if "traffic" in v else "") if "garage" in v else ("traffic list" if "traffic" in v else "registry only"),
            "verified": ("tests/car_models_check.gd (builds, sits on its wheels, pulls away); interior_check" if "garage" in v else "tests/modes_check.gd (every traffic car loads car-sized on four wheels)") + ("; scripts only (no-AI: renders never viewed)" if noai else ""),
            "status": IN_GAME if st else REPAIR,
            "problems": "; ".join(problems)[:300] if problems else "",
        })
    return rows


def env_rows(pk, used):
    rows = []
    lib = json.load(open(os.path.join(ROOT, "data", "environment_assets.json")))["assets"]
    groups = {}
    for aid, a in lib.items():
        g = groups.setdefault(a["glb"], {"ids": [], "kinds": set(), "sources": set()})
        g["ids"].append(aid)
        g["kinds"].add(a["kind"])
        g["sources"].add(str(a.get("source", "")))
    manifest = {}
    mf = os.path.join(ROOT, "assets", "environment_packages", "ENVIRONMENT_ASSET_MANIFEST.tsv")
    if os.path.isfile(mf):
        for line in open(mf).read().splitlines()[1:]:
            c = line.split("\t")
            if len(c) >= 6:
                manifest[c[1]] = {"storage": c[4], "licence": c[5]}
    for glb_res, g in sorted(groups.items()):
        glb = glb_res.replace("res://", "")
        st = glb_stats(glb)
        srcs = " / ".join(sorted(g["sources"]))
        matched = []
        for orig, word in ENV_SOURCE_KEYS.items():
            if word.lower() in srcs.lower():
                for key in pk:
                    if key.startswith("environment_packages/") and (orig.split("/")[-1] in key):
                        matched.append(key)
        for key in matched:
            used.add(key)
        kind = sorted(g["kinds"])[0]
        use = ENV_USE.get(kind, ("-", "-", "-"))
        lic = "CC0" if ("CC0" in srcs or "Kenney" in srcs) else "owner's pack (licence review: see ENVIRONMENT_ASSET_MANIFEST.tsv)"
        rows.append({
            "name": "%s (%d: %s)" % (os.path.basename(glb), len(g["ids"]), ", ".join(sorted(g["ids"])[:4]) + (" ..." if len(g["ids"]) > 4 else "")),
            "category": "environment: %s" % "/".join(sorted(g["kinds"])),
            "source": ", ".join(sorted(set(matched))) or srcs, "runtime": glb if st else "(missing: %s)" % glb,
            "licence": lic, "conversion": "GLB: tools/import_environment.py (environment_specs.json)",
            "materials": ("%d materials, %d textures" % (st["materials"], st["images"])) if st else "-", "tris": st.get("tris", 0),
            "collision": use[1], "lod": use[2] if kind != "tree" or st.get("lod_nodes") else use[2] + " (none found!)",
            "interior": "-", "modes": use[0], "catalog": "data/environment_assets.json (EnvAssets, Biomes)",
            "verified": "tests/environment_check.gd (every LOD and far card loads; nothing on the road)",
            "status": IN_GAME if st else REPAIR, "problems": "",
        })
    return rows


def wheel_rows(pk, used):
    """The converted CC0 wheel library (assets/wheels/<id>/: tools/import_wheels.py) and what uses each."""
    rows = []
    presets = json.load(open(os.path.join(ROOT, "data", "wheel_presets.json")))
    users = {}
    for pid, p in presets["presets"].items():
        if p.get("mesh"):
            users.setdefault(p["mesh"], []).append("%s (the garage type)" % p["name"])
        if p.get("far"):
            users.setdefault(p["far"], []).append("%s's far stand-in" % p["name"])
    for kind, wid in presets.get("far", {}).items():
        if not kind.startswith("_") and isinstance(wid, str):
            users.setdefault(wid, []).append("the %s kind's far stand-in" % kind)
    base = os.path.join(ROOT, "assets", "wheels")
    for wid in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        info_p = os.path.join(base, wid, "wheel.json")
        if not os.path.isfile(info_p):
            continue
        info = json.load(open(info_p))
        glb = "assets/wheels/%s/%s.glb" % (wid, wid)
        st = glb_stats(glb)
        src = ""
        if wid.startswith("innerscene"):
            src = "wheel_packages/Free_Wheels/innerscene-17in-five-spoke-wheel-tyre.x3d"
        elif wid.startswith("cc96"):
            src = "wheel_packages/Free_Wheels/ice-maan-cc96-four-rim-pack.zip"
        elif wid.startswith("usd_"):
            nm = {"largerim": "LargeRim"}.get(wid[4:], wid[4:].capitalize())
            src = "wheel_packages/Free_Wheels/USD_Mini_Car_Kit/assets/wheels/wheel" + nm
        if src in pk:
            used.add(src)
        u = users.get(wid, [])
        rows.append({"name": wid, "category": "wheel", "source": src or info.get("source", "-"), "runtime": glb if st else "(missing: %s)" % glb,
                     "licence": info.get("licence", "CC0"), "conversion": "GLB: tools/import_wheels.py (Tyre / Rim%s apart, axle x, face +x)" % (" / Disc" if "Disc" in info.get("parts", []) else ""),
                     "materials": ("%d materials" % st["materials"]) if st else "-", "tris": st.get("tris", 0),
                     "collision": "none (the physics wheel is a shape cast)", "lod": "is a LOD itself (far stand-in)" if info.get("detail") == "low" else "Godot importer LODs; far stand-in past 70 m",
                     "interior": "-", "modes": "every car with a preset on (garage, every mode)" if u else "-",
                     "catalog": "; ".join(u) if u else "converted, unused", "verified": "tests/wheel_check.gd (sizes, axle, face, on three cars)",
                     "status": IN_GAME if (st and u) else (REPAIR if not st else ALTERNATE),
                     "problems": ("low-poly (%s triangles): only ever seen far away" % "{:,}".format(st.get("tris", 0)) if info.get("detail") == "low" else "")
                     + ("; the pack's three body kits and spoiler (for its own low-poly CC96 car) aren't used: no car here takes them" if wid == "cc96_rim1" else "")})
    return rows


def other_runtime_rows():
    """The crew, the cockpit and the game's own bodies: assets/models outside the car folders."""
    items = [
        ("Racer (driver)", "character", "assets/models/driver.glb", "the owner's Claude_Racer FBX (tools/import_crew.py)", "the owner's",
         "every mode: the driver in the seat (cockpit.gd)", "tests/cockpit_check.gd, interior_check.gd"),
        ("Racer (co-driver)", "character", "assets/models/codriver.glb", "the owner's Claude_Racer FBX (tools/import_crew.py)", "the owner's",
         "rally: the co-driver beside you", "tests/cockpit_check.gd"),
        ("Racing gloves", "character", "assets/models/gloves/gloves.glb", "tools/fit_glove.py (sized to a real hand, fitted to the rim)", "see CREDITS.md",
         "every car's first-person view (driver_hands.gd)", "tests/cockpit_check.gd (the gloves cover the sleeve ends)"),
        ("Bucket seat", "cockpit", "assets/models/seat.glb", "Higgsfield", "the owner's (Higgsfield)", "the shared cockpit (cars without their own interior)", "tests/cockpit_check.gd"),
        ("Rally car body (KESTREL and the other Higgsfield cars)", "car", "assets/models/rally_car.glb", "Higgsfield; split into body, wheels and flaps (tools/split_car.gd -> assets/models/car_parts/*.res)",
         "the owner's (Higgsfield)", "rally (the four Higgsfield rally cars)", "tests/car_models_check.gd"),
    ]
    rows = []
    for name, cat, glb, conv, lic, modes, ver in items:
        st = glb_stats(glb)
        rows.append({"name": name, "category": cat, "source": "(generated / the owner's upload)", "runtime": glb if st else "(missing: %s)" % glb,
                     "licence": lic, "conversion": conv,
                     "materials": ("%d materials, %d textures" % (st["materials"], st["images"])) if st else "-", "tris": st.get("tris", 0),
                     "collision": "none (inside the car)" if cat != "car" else "physics in code (RallyCar)",
                     "lod": "none (always close)" if cat != "car" else "Godot importer LODs", "interior": "-",
                     "modes": modes, "catalog": "built in (cockpit / garage)", "verified": ver,
                     "status": IN_GAME if st else REPAIR, "problems": ""})
    return rows


# The owner's CC0 Track Mode uploads (assets/TRACK_MODE_ASSET_MANIFEST.tsv: source, licence, hash):
# what each is for until it's in the game.
TRACK_PLAN = {"formula": "Track P7: the FORMULA class's car (CC0, halo open-wheeler)",
              "gt": "Track P7: a GT class car for the AI grid (CC0, generic closed-cockpit racer)",
              "prop": "Track P7: pit lane and marshal dressing for CINDER RIDGE (CC0)"}


def track_manifest():
    """{path under assets/: {category, license, source_url, ...}} from TRACK_MODE_ASSET_MANIFEST.tsv."""
    out = {}
    mf = os.path.join(ROOT, "assets", "TRACK_MODE_ASSET_MANIFEST.tsv")
    if os.path.exists(mf):
        with open(mf) as f:
            head = f.readline().rstrip("\n").split("\t")
            for line in f:
                row = dict(zip(head, line.rstrip("\n").split("\t")))
                if row.get("file"):
                    out[row["file"]] = row
    return out


def leftover_rows(pk, used):
    """Every package not yet joined to a runtime asset: from NOTES, or a row of its own."""
    rows = []
    tm = track_manifest()
    wheel_plan = "Track P3: the WheelPreset system converts it into separate rim, tyre, disc and caliper meshes with LODs, offered as garage wheel options"
    for key in sorted(pk):
        if key in used:
            continue
        p = pk[key]
        status, why, runtime = PENDING, "", ""
        if key in NOTES:
            status, why, runtime = NOTES[key]
        elif key in tm:
            why = TRACK_PLAN.get(tm[key].get("category", ""), "Track P7") + "; source %s" % tm[key].get("source_url", "-")
        elif key.startswith("car_packages/Track_Mode_Cars/Formula/"):
            why = "Private 2026 Formula source candidate: no licence or provenance document was present in the archive; review before redistribution, replace real branding, then complete the full vehicle integration"
        elif key.startswith("car_packages/Track_Mode_Cars/GT3/"):
            why = "Private GT/DTM source candidate: no licence or provenance document was present in the archive; review before redistribution, replace real branding, then complete the full vehicle integration"
        elif key.startswith("car_packages/Track_Mode_Cars/Street/"):
            why = "Private street-car source candidate: no licence or provenance document was present in the archive; review before redistribution, replace real branding, then complete the full vehicle integration"
        elif key.startswith("wheel_packages/"):
            if "USD_Mini_Car_Kit" in key and "/vehicles/" in key:
                nm = key.split("/")[-1]
                why = ("Track P7: a reference for the formula car's proportions (USD, CC0); low-poly" if nm == "formula"
                       else "a low-poly USD vehicle (CC0): not wanted as a car (the game's cars are detailed); kept as a source")
                status = PENDING if nm == "formula" else ALTERNATE
            elif "USD_Mini_Car_Kit" in key and "/wheels/" in key:
                why = wheel_plan + " (USD: converted with usd-core, not Blender)"
            elif "(materials" in key:
                why, status = "the USD kit's shared materials, textures and preview cards: the converted wheels use only its geometry (the game's own rubber and rim materials)", TEXTURES
            else:
                why = wheel_plan
        elif "/polyhaven/" in key:
            status, why = TEXTURES, "a Poly Haven PBR texture set (CC0) used by the world's materials (WorldMaterials): not a 3D model"
        elif "/poly_haven/" in key:
            nm = re.sub(r"_2k_gltf\.zip$", "", key.split("/")[-1])
            why = "Track P9: %s (Poly Haven, CC0, glTF 2k)" % POLYHAVEN_PLAN.get(nm, "dressing")
        elif key.startswith("environment_packages/user_sources/"):
            why = "an owner's pack not converted yet: review it in docs/ENVIRONMENT_INVENTORY.md"
        else:
            status, why = REPAIR, "not accounted for: inspect it, then add it to tools/asset_audit.py's NOTES"
        if key in tm:
            lic = tm[key].get("license", "see the package's README / manifest").replace("CC0-1.0", "CC0")
        elif "cc0" in key or "wheel_packages" in key:
            lic = "CC0"
        elif key in ("car_packages/Track_Mode_Cars/2024-porsche-992-gt3-r.zip",
                     "car_packages/Track_Mode_Cars/mercedes-amg-gt3-red-bull-racing.zip"):
            lic = "CC BY-NC-SA 4.0"
        elif key.startswith("car_packages/Track_Mode_Cars/"):
            lic = "unknown (private source; review required)"
        else:
            lic = "see the package's README / manifest"
        cat = "car" if key.startswith("car_packages/") else ("wheel" if key.startswith("wheel_packages/") else "environment")
        if "/vehicles/" in key:
            cat = "car (low-poly reference)"
        rows.append({"name": key.split("/")[-1].replace(".zip", "").replace(".rar", ""), "category": cat,
                     "source": "%s (%s, %d file%s)" % (key, p["kind"], p["files"], "" if p["files"] == 1 else "s"),
                     "runtime": ("assets/models/cars/%s" % runtime) if runtime else "-", "licence": lic,
                     "conversion": "-" if status != IN_GAME else "done", "materials": "-", "tris": 0, "collision": "-", "lod": "-",
                     "interior": "-", "modes": "-", "catalog": "data/asset_catalog.json (%s)" % status.lower(), "verified": "no",
                     "status": status, "problems": why})
    return rows


def exclusion_problems():
    """A package folder that a build could take: each needs a .gdignore (Godot never imports or exports
    it) and an export_presets.cfg exclude for every preset."""
    probs = []
    for d in PACKAGE_DIRS:
        tracked = subprocess.run(["git", "-C", ROOT, "ls-tree", "--name-only", "HEAD", d + "/.gdignore"],
                                 capture_output=True, text=True).stdout.strip()
        if not tracked:
            probs.append("%s has no .gdignore" % d)
    cfg = open(os.path.join(ROOT, "export_presets.cfg")).read()
    for m in re.finditer(r'exclude_filter="([^"]*)"', cfg):
        flt = m.group(1)
        for d in PACKAGE_DIRS:
            if d + "/*" not in flt:
                probs.append("an export preset doesn't exclude %s/*" % d)
    return sorted(set(probs))


def build():
    files = git_files()
    pk = packages(files)
    used = set()
    rows = car_rows(pk, used) + env_rows(pk, used) + wheel_rows(pk, used) + other_runtime_rows()
    # the owner's 31-building pack is in the game through bld31.glb (the skyline)
    for key in pk:
        if key in NOTES and NOTES[key][0] == IN_GAME:
            used.add(key)
    rows += leftover_rows(pk, used)
    return rows, pk, files


COLS = [("Asset", "name"), ("Category", "category"), ("Source", "source"), ("Runtime", "runtime"), ("Licence", "licence"),
        ("Conversion", "conversion"), ("Materials / textures", "materials"), ("Triangles", "tris"), ("Collision", "collision"),
        ("LOD", "lod"), ("Interior", "interior"), ("Game modes", "modes"), ("Catalog / menu", "catalog"),
        ("Verified in Godot", "verified"), ("Status", "status"), ("Remaining problems / plan", "problems")]


def cell(v):
    if isinstance(v, int):
        return "{:,}".format(v) if v else "-"
    return str(v).replace("|", "/").replace("\n", " ") or "-"


def render(rows, pk, files):
    from collections import Counter
    by = Counter(r["status"] for r in rows)
    out = ["# Asset integration status", "",
           "Every 3D asset in the repository and where it stands, generated by `tools/asset_audit.py write`",
           "(`check` runs in `tests/run_all.sh`: a new source package that isn't accounted for, a missing",
           "runtime file or a package a build could pick up fails it). Don't edit by hand: change the",
           "registry (`data/vehicles/`), the environment library (`data/environment_assets.json`) or the",
           "notes in the tool, then run it. The machine-readable copy is `data/asset_catalog.json`.", "",
           "**Sources stay on GitHub, out of every build.** The package folders (%s: %d files in git)" % (
               ", ".join("`%s/`" % d for d in PACKAGE_DIRS), len(files)),
           "each have a `.gdignore` (Godot never imports them) and every export preset excludes them; CI's",
           "checkout leaves the big ones out (sparse). The game uses only the converted derivatives",
           "(`assets/models/`, `assets/environment_runtime/`).", "",
           "**Statuses:** %s." % ", ".join("%s %d" % (k, by[k]) for k in [IN_GAME, PENDING, ALTERNATE, DUPLICATE, BLOCKED, REPAIR, TEXTURES] if by[k]),
           "*In game*: converted, registered, used and checked by the tests. *Pending*: queued for the Track",
           "Mode phase named (docs/GT_F1_TRACK_MODE_CLAUDE_PROMPT.md). *Alternate* / *Duplicate*: another",
           "package is the one used. *Blocked* and *NEEDS REPAIR*: can't be used as it is (the reason is",
           "given). *Texture set*: materials, not a model.", "",
           "Cars handled as no-AI (listed in the registry) are converted and checked by scripts only; their",
           "renders are never viewed.", ""]
    sections = [("Cars (the vehicle registry)", lambda r: r["category"] in ("car", "traffic car") and r["source"] != "(generated / the owner's upload)" and r["status"] == IN_GAME),
                ("Crew, cockpit and the game's own bodies", lambda r: r["source"] == "(generated / the owner's upload)"),
                ("Environment (the environment library)", lambda r: r["category"].startswith("environment:")),
                ("Wheels (the WheelPreset system's converted CC0 library)", lambda r: r["category"] == "wheel" and r["runtime"].startswith("assets/wheels")),
                ("Source packages not in the game (yet)", lambda r: r["status"] != IN_GAME or (r["category"] not in ("car", "traffic car", "wheel") and not r["category"].startswith("environment:") and r["source"] != "(generated / the owner's upload)"))]
    done = set()
    for title, pred in sections:
        sel = [r for i, r in enumerate(rows) if i not in done and pred(r)]
        for i, r in enumerate(rows):
            if i not in done and pred(r):
                done.add(i)
        if not sel:
            continue
        out += ["## %s (%d)" % (title, len(sel)), ""]
        out.append("| " + " | ".join(c for c, _ in COLS) + " |")
        out.append("|" + "---|" * len(COLS))
        for r in sel:
            out.append("| " + " | ".join(cell(r[k]) for _, k in COLS) + " |")
        out.append("")
    probs = exclusion_problems()
    out += ["## Build exclusion", "", "No problems: every package folder has its `.gdignore` and is excluded by every export preset." if not probs
            else "Problems:\n\n" + "\n".join("- " + p for p in probs), ""]
    return "\n".join(out)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    rows, pk, files = build()
    doc = render(rows, pk, files)
    cat = {"_doc": "Every 3D asset and its status (tools/asset_audit.py writes this; docs/ASSET_INTEGRATION_STATUS.md is the readable copy).",
           "assets": rows}
    if cmd == "write":
        open(DOC, "w").write(doc)
        open(CATALOG, "w").write(json.dumps(cat, indent=1, ensure_ascii=False) + "\n")
        print("wrote %s and %s: %d assets" % (os.path.relpath(DOC, ROOT), os.path.relpath(CATALOG, ROOT), len(rows)))
        return 0
    fails = []
    for r in rows:
        if r["status"] == REPAIR and "not accounted for" in r["problems"]:
            fails.append("not accounted for: %s" % r["source"])
        if r["status"] == IN_GAME and str(r["runtime"]).startswith("(missing"):
            fails.append("missing runtime file: %s" % r["runtime"])
    fails += exclusion_problems()
    if not os.path.isfile(DOC) or open(DOC).read() != doc:
        fails.append("docs/ASSET_INTEGRATION_STATUS.md is stale: run python3 -I tools/asset_audit.py write")
    from collections import Counter
    by = Counter(r["status"] for r in rows)
    print("[assets] %d assets (%s), %d source packages" % (len(rows), ", ".join("%s %d" % kv for kv in sorted(by.items())), len(pk)))
    for f in fails:
        print("[assets] FAIL " + f)
    print("[assets] %s" % ("ASSETS OK" if not fails else "ASSETS FAIL"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
