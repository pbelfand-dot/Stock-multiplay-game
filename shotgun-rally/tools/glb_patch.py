"""Material fixes for a converted car, written in its spec (tools/cars/<id>.json
"glb_patch") and applied to its GLB: only the GLB's JSON changes (the binary
chunk, every mesh and image, stays byte for byte). tools/import_car.py applies
them to every car it writes; run it on its own to fix a GLB already made:

  python3 tools/glb_patch.py tools/cars/<id>.json [path/to/<id>.glb]

"glb_patch": {"materials": {"<material name pattern>": {...}}}, each pattern's
changes (a regex, matched against the GLB's material names):
  * "base_from_emissive": true: the colour texture is the glow's (a game rip's
    lamps whose colour texture is blank and whose colours are in the glow map)
  * "emissive_from_base": strength: the glow is the colour texture's, that bright
  * "emissive": [r, g, b]: the glow's factor (0, 0, 0: no glow)
  * "emissive_strength": k: how bright the glow is (KHR_materials_emissive_strength; 1: plain)
  * "color": [r, g, b] or [r, g, b, a]: the colour factor
  * "no_base_texture": true: the colour texture dropped (the factor alone)
  * "alpha": "OPAQUE" / "MASK" / "BLEND" (+ "cutoff" for MASK)
  * "double_sided": true / false
  * "no_occlusion": true: the occlusion map dropped (a rip whose packed map's red channel
    isn't occlusion: it darkened a whole cabin to black in the shade)
  * "metal" / "rough": the metallic / roughness factors (x the map, if it has one)
"""
import json
import os
import re
import struct
import sys


def read(path):
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    return json.loads(b[20:20 + n]), b[20 + n:]


def write(path, j, rest):
    s = json.dumps(j, separators=(",", ":")).encode()
    s += b" " * (-len(s) % 4)
    head = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(s) + len(rest))
    open(path, "wb").write(head + struct.pack("<I4s", len(s), b"JSON") + s + rest)


def apply(path, patch):
    """Applies a spec's "glb_patch" to the GLB at path; returns what it changed."""
    if not patch:
        return []
    j, rest = read(path)
    done = []
    for pat, ch in patch.get("materials", {}).items():
        for m in j.get("materials", []):
            if not re.search(pat, m.get("name", ""), re.I):
                continue
            pbr = m.setdefault("pbrMetallicRoughness", {})
            if ch.get("base_from_emissive") and "emissiveTexture" in m:
                pbr["baseColorTexture"] = dict(m["emissiveTexture"])
            if "emissive_from_base" in ch and "baseColorTexture" in pbr:
                m["emissiveTexture"] = dict(pbr["baseColorTexture"])
                k = float(ch["emissive_from_base"])
                m["emissiveFactor"] = [min(k, 1.0)] * 3
                if k > 1.0:
                    m.setdefault("extensions", {})["KHR_materials_emissive_strength"] = {"emissiveStrength": k}
            if "emissive" in ch:
                m["emissiveFactor"] = list(ch["emissive"])
                if max(ch["emissive"]) <= 0:
                    m.pop("emissiveTexture", None)
                    m.get("extensions", {}).pop("KHR_materials_emissive_strength", None)
            if "emissive_strength" in ch:
                k = float(ch["emissive_strength"])
                if k == 1.0:
                    m.get("extensions", {}).pop("KHR_materials_emissive_strength", None)
                else:
                    m.setdefault("extensions", {})["KHR_materials_emissive_strength"] = {"emissiveStrength": k}
            if "color" in ch:
                c = list(ch["color"])
                pbr["baseColorFactor"] = c + [pbr.get("baseColorFactor", [1, 1, 1, 1])[3]] if len(c) == 3 else c
            if ch.get("no_base_texture"):
                pbr.pop("baseColorTexture", None)
            if "alpha" in ch:
                if ch["alpha"] == "OPAQUE":
                    m.pop("alphaMode", None)
                    m.pop("alphaCutoff", None)
                else:
                    m["alphaMode"] = ch["alpha"]
                    if ch["alpha"] == "MASK":
                        m["alphaCutoff"] = float(ch.get("cutoff", 0.5))
                    else:
                        m.pop("alphaCutoff", None)
            if "double_sided" in ch:
                m["doubleSided"] = bool(ch["double_sided"])
            if ch.get("no_occlusion"):
                m.pop("occlusionTexture", None)
            if "metal" in ch:
                pbr["metallicFactor"] = float(ch["metal"])
            if "rough" in ch:
                pbr["roughnessFactor"] = float(ch["rough"])
            done.append(m.get("name", "?"))
    if "extensions" in json.dumps(j.get("materials", [])) and any(
            "KHR_materials_emissive_strength" in m.get("extensions", {}) for m in j.get("materials", [])):
        used = j.setdefault("extensionsUsed", [])
        if "KHR_materials_emissive_strength" not in used:
            used.append("KHR_materials_emissive_strength")
    write(path, j, rest)
    return done


if __name__ == "__main__":
    spec_path = sys.argv[1]
    spec = json.load(open(spec_path))
    here = os.path.dirname(os.path.abspath(__file__))
    glb = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "..", "assets", "models", "cars", spec["id"], spec["id"] + ".glb")
    print("%s: patched %s" % (os.path.basename(glb), apply(glb, spec.get("glb_patch"))))
