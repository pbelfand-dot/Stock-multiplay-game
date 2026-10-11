"""Material fixes for a converted car, written in its spec (tools/cars/<id>.json
"glb_patch") and applied to its GLB: only the GLB's JSON changes (the binary
chunk, every mesh and image, stays byte for byte; "faces" adds index lists to its
end). tools/import_car.py applies them to every car it writes; run it on its own
to fix a GLB already made:

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
  * "no_uv_transform": true: the colour texture's KHR_texture_transform dropped (Blender's re-export
    hung another map's tiling on it: the CLK DTM's livery sampled at 3 % of its size, one black corner)
  * "alpha": "OPAQUE" / "MASK" / "BLEND" (+ "cutoff" for MASK)
  * "double_sided": true / false
  * "no_occlusion": true: the occlusion map dropped (a rip whose packed map's red channel
    isn't occlusion: it darkened a whole cabin to black in the shade)
  * "metal" / "rough": the metallic / roughness factors (x the map, if it has one)
  * "normal_from_base": true: the colour texture is really a normal map (a rip's mix-up: a cabin
    drawn lavender): it becomes the normal map
  * "base_texture_of": pattern: the colour texture taken from another of the model's materials
    (after "normal_from_base": the carbon weave's colour for a carbon whose colour was its normals)
"glb_patch": {"faces": [{"from": pattern, "to": pattern, "box": [x0, x1, y0, y1, z0, z1],
"min_faces": n}]}: whole pieces of mesh (faces joined at their corners) of the material "from",
wholly inside the box (the game's model space, m: x right, y up, z back) and of at least n
faces, given the material "to" (a windscreen modelled in the black trim's material: the
window glass's); the same corners, their own list of faces. Done once: run again, nothing's left to move.
"""
import json
import os
import re
import struct
import sys

import numpy as np


def read(path):
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    return json.loads(b[20:20 + n]), b[20 + n:]


def write(path, j, rest):
    s = json.dumps(j, separators=(",", ":")).encode()
    s += b" " * (-len(s) % 4)
    head = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(s) + len(rest))
    open(path, "wb").write(head + struct.pack("<I4s", len(s), b"JSON") + s + rest)


_TYPES = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
_SIZES = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def _accessor(j, data, i):
    a = j["accessors"][i]
    bv = j["bufferViews"][a["bufferView"]]
    ct, n = _TYPES[a["componentType"]], _SIZES[a["type"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0)
    item = np.dtype(ct).itemsize * n
    if stride and stride != item:
        raw = np.frombuffer(data, np.uint8, stride * (a["count"] - 1) + item, off)
        r = np.lib.stride_tricks.as_strided(raw, (a["count"], item), (stride, 1)).copy().view(ct)
    else:
        r = np.frombuffer(data, ct, a["count"] * n, off)
    return r.reshape(a["count"], n) if n > 1 else r


def _node_xf(j):
    """Each mesh's nodes' transforms (4x4, the scene's space)."""
    out, parent = {}, {}
    for i, n in enumerate(j.get("nodes", [])):
        for c in n.get("children", []):
            parent[c] = i

    def local(n):
        if "matrix" in n:
            return np.array(n["matrix"], float).reshape(4, 4).T
        x, y, z, w = n.get("rotation", [0, 0, 0, 1])
        r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                      [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                      [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
        m = np.eye(4)
        m[:3, :3] = r * np.array(n.get("scale", [1, 1, 1]))
        m[:3, 3] = n.get("translation", [0, 0, 0])
        return m
    for i, n in enumerate(j.get("nodes", [])):
        if "mesh" not in n:
            continue
        m, k = local(n), i
        while k in parent:
            k = parent[k]
            m = local(j["nodes"][k]) @ m
        out.setdefault(n["mesh"], []).append(m)
    return out


def _move_faces(j, rest, ops):
    """The "faces" changes: returns the new binary chunk (rest) and what moved."""
    data = bytearray(rest[8:])
    names = [m.get("name", "") for m in j.get("materials", [])]
    xfs = _node_xf(j)
    done = []
    for op in ops:
        to = [i for i, n in enumerate(names) if re.search(op["to"], n)]
        if not to:
            raise SystemExit("glb_patch faces: no material %s" % op["to"])
        x0, x1, y0, y1, z0, z1 = op["box"]
        for mi, mesh in enumerate(j.get("meshes", [])):
            for xf in xfs.get(mi, [])[:1]:
                prims = mesh["primitives"]
                for pi in range(len(prims) - 1, -1, -1):
                    p = prims[pi]
                    if "material" not in p or "indices" not in p or not re.search(op["from"], names[p["material"]]) or p.get("mode", 4) != 4:
                        continue
                    pos = _accessor(j, data, p["attributes"]["POSITION"]).astype(float)
                    pos = pos @ xf[:3, :3].T + xf[:3, 3]
                    tri = _accessor(j, data, p["indices"]).astype(np.int64).reshape(-1, 3)
                    # (the pieces: corners welded where they meet, 0.1 mm)
                    _, weld = np.unique(np.round(pos / 1e-4).astype(np.int64), axis=0, return_inverse=True)
                    weld = weld.ravel()
                    root = list(range(int(weld.max()) + 1))

                    def find(a):
                        while root[a] != a:
                            root[a] = root[root[a]]
                            a = root[a]
                        return a
                    for t in weld[tri]:
                        a = find(int(t[0]))
                        root[find(int(t[1]))] = a
                        root[find(int(t[2]))] = a
                    piece = np.array([find(int(weld[t[0]])) for t in tri])
                    q = pos[tri]
                    inside = ((q[..., 0] >= x0) & (q[..., 0] <= x1) & (q[..., 1] >= y0) & (q[..., 1] <= y1)
                              & (q[..., 2] >= z0) & (q[..., 2] <= z1)).all(axis=1)
                    move = np.zeros(len(tri), bool)
                    for k in set(piece[inside].tolist()):
                        mine = piece == k
                        if inside[mine].all() and mine.sum() >= int(op.get("min_faces", 1)):
                            move |= mine
                    if not move.any():
                        continue
                    ct = j["accessors"][p["indices"]]["componentType"]

                    def add(ix):
                        data.extend(b"\0" * (-len(data) % 4))
                        raw = np.ascontiguousarray(ix.ravel().astype(_TYPES[ct])).tobytes()
                        j["bufferViews"].append({"buffer": 0, "byteOffset": len(data), "byteLength": len(raw), "target": 34963})
                        data.extend(raw)
                        j["accessors"].append({"bufferView": len(j["bufferViews"]) - 1, "componentType": ct,
                                               "count": int(ix.size), "type": "SCALAR"})
                        return len(j["accessors"]) - 1
                    p["indices"] = add(tri[~move])
                    moved = dict(p, indices=add(tri[move]), material=to[0])
                    prims.insert(pi + 1, moved)
                    done.append("%s: %d faces %s -> %s" % (mesh.get("name", mi), int(move.sum()), names[p["material"]], names[to[0]]))
    data.extend(b"\0" * (-len(data) % 4))
    j["buffers"][0]["byteLength"] = len(data)
    return struct.pack("<I4s", len(data), b"BIN\0") + bytes(data), done


def apply(path, patch):
    """Applies a spec's "glb_patch" to the GLB at path; returns what it changed."""
    if not patch:
        return []
    j, rest = read(path)
    done = []
    if patch.get("faces"):
        rest, moved = _move_faces(j, rest, patch["faces"])
        done += moved
    for pat, ch in patch.get("materials", {}).items():
        for m in j.get("materials", []):
            if not re.search(pat, m.get("name", ""), re.I):
                continue
            pbr = m.setdefault("pbrMetallicRoughness", {})
            src = None
            if ch.get("base_texture_of"):
                src = [o for o in j.get("materials", []) if o is not m and re.search(ch["base_texture_of"], o.get("name", ""))
                       and "baseColorTexture" in o.get("pbrMetallicRoughness", {})]
                if not src:
                    raise SystemExit("glb_patch: no material %s with a colour texture" % ch["base_texture_of"])
                src = src[0]["pbrMetallicRoughness"]["baseColorTexture"]
            fresh = src is None or pbr.get("baseColorTexture", {}).get("index") != src["index"]   # (not done already)
            if ch.get("normal_from_base") and "baseColorTexture" in pbr and fresh:
                m["normalTexture"] = {k: v for k, v in pbr.pop("baseColorTexture").items() if k in ("index", "texCoord", "extensions")}
            if src is not None:
                pbr["baseColorTexture"] = dict(src)
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
            if ch.get("no_uv_transform") and "baseColorTexture" in pbr:
                pbr["baseColorTexture"].get("extensions", {}).pop("KHR_texture_transform", None)
                if not pbr["baseColorTexture"].get("extensions", True):
                    pbr["baseColorTexture"].pop("extensions")
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
