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
"glb_patch": {"wheels_from": {"from": "FR", "to": ["FL", "RL", "RR"]}}: those corners' wheels
replaced by a copy of the "from" corner's (mirrored for the other side), each standing where its
own tyre's outside face was, its node at the copy's middle; its caliper left where it was (its
node moved with the wheel's, its corners back by as much). For a model whose wheels lost part of
their tyres in the import (KASTEN 63: three tyres only their outer wall, the inside half dropped as
a stray); the copies are added to the binary chunk, and parts.json's "wheels", "radius" and
"width" follow (the file next to the GLB, or the dictionary passed to apply). Done once: a corner
already copied is left.
"glb_patch": {"wheel_centre": {"tyre": pattern, "to_body": [patterns]}}: each corner's wheel node
moved to its tyre's middle (the tyre: its primitives of that material; the rest of the wheel and
the caliper stay where they were, their corners moved back by as much), and its pieces of the
"to_body" materials put in the Body (their own node, "WheelBits_<corner>": they don't spin), but
those round the hub inside the wheel ("hub": within 0.125 m of the axle: the nuts, the cap). For a
model whose wheel nodes took in the suspension (WOKING 800: wishbones and uprights spinning with
the wheel, the node 0.38 m inboard of the tyre, the physics' track a metre); parts.json follows.
Done once.
"glb_patch": {"body_to_wheels": {"mats": [patterns], "skip_mats": [patterns], "caliper_mats": [patterns]}}:
the wheels' parts the import left in the Body (they neither spun nor steered: a rim, an aero cover, a
brake disc, a centre nut): every piece of the Body (of those materials; all if none given) wholly
inside a wheel's drum (its tyre's radius and width, give or take 2-3 cm) that's round about its axle
and at least "min" (0.3 m) across, or lies on the axle (within "axle", 0.06 m), moved into that wheel
(into its caliper: "caliper_mats", steering but not spinning). Applied after the moves above. Done once.
"glb_patch": {"drop_dupes": [{"keep": pattern, "drop": pattern}]}: faces of the "drop" materials that
are a face of the "keep" material's again (the same three corners' middle, within 0.5 mm) left out:
a part modelled twice over in two materials fights itself in the depth buffer, flickering between
them (the KAISER 8's front grille in four finishes at once; the TEMPESTA URSA's lamps lit and unlit).
Done once.
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


def _wheels_from(j, rest, op, parts):
    """The "wheels_from" change: returns the new binary chunk (rest) and what changed."""
    data = bytearray(rest[8:])
    nodes = j["nodes"]
    names = {n.get("name"): i for i, n in enumerate(nodes)}
    corners = ["FL", "FR", "RL", "RR"]
    src = names.get("Wheel_" + op["from"])
    if src is None or "mesh" not in nodes[src]:
        raise SystemExit("glb_patch wheels_from: no Wheel_%s" % op["from"])
    for k in corners:                                   # (the wheels and calipers sit straight in the model: only moved)
        for pre in ("Wheel_", "Caliper_"):
            n = nodes[names[pre + k]] if pre + k in names else {}
            if "matrix" in n or any(abs(a - b) > 1e-6 for a, b in zip(n.get("rotation", [0, 0, 0, 1]), [0, 0, 0, 1])) \
                    or any(abs(a - 1) > 1e-6 for a in n.get("scale", [1, 1, 1])):
                raise SystemExit("glb_patch wheels_from: %s%s isn't only moved" % (pre, k))
    mid_x = float(np.mean([nodes[names["Wheel_" + k]].get("translation", [0, 0, 0])[0] for k in corners]))
    src_left = nodes[src].get("translation", [0, 0, 0])[0] < mid_x

    def add(arr, ct, target, kind):
        data.extend(b"\0" * (-len(data) % 4))
        raw = np.ascontiguousarray(arr.astype(_TYPES[ct])).tobytes()
        j["bufferViews"].append({"buffer": 0, "byteOffset": len(data), "byteLength": len(raw), "target": target})
        data.extend(raw)
        acc = {"bufferView": len(j["bufferViews"]) - 1, "componentType": ct, "count": int(arr.shape[0]), "type": kind}
        if kind == "VEC3" and target == 34962:
            acc["min"] = [float(v) for v in arr.min(0)]
            acc["max"] = [float(v) for v in arr.max(0)]
        j["accessors"].append(acc)
        return len(j["accessors"]) - 1

    def xs(mesh):
        return np.concatenate([_accessor(j, data, p["attributes"]["POSITION"])[:, 0].astype(float)
                               for p in j["meshes"][mesh]["primitives"]])
    src_mesh = nodes[src]["mesh"]
    sx = xs(src_mesh)
    done = []
    for k in op["to"]:
        w = names.get("Wheel_" + k)
        if w is None or "mesh" not in nodes[w]:
            raise SystemExit("glb_patch wheels_from: no Wheel_%s" % k)
        if j["meshes"][nodes[w]["mesh"]].get("name", "").endswith("_from_" + op["from"]):
            continue                                    # (copied already)
        at = list(nodes[w].get("translation", [0, 0, 0]))
        left = at[0] < mid_x
        flip = left != src_left
        own = xs(nodes[w]["mesh"])
        outside = at[0] + (own.min() if left else own.max())          # (its own tyre's outer face: it stays)
        prims = []
        for p in j["meshes"][src_mesh]["primitives"]:
            q = dict(p, attributes=dict(p["attributes"]))
            if flip:
                pos = _accessor(j, data, p["attributes"]["POSITION"]).astype(np.float32).copy()
                pos[:, 0] *= -1.0
                q["attributes"]["POSITION"] = add(pos, 5126, 34962, "VEC3")
                if "NORMAL" in p["attributes"]:
                    nm = _accessor(j, data, p["attributes"]["NORMAL"]).astype(np.float32).copy()
                    nm[:, 0] *= -1.0
                    q["attributes"]["NORMAL"] = add(nm, 5126, 34962, "VEC3")
                if "TANGENT" in p["attributes"]:
                    tg = _accessor(j, data, p["attributes"]["TANGENT"]).astype(np.float32).copy()
                    tg[:, 0] *= -1.0
                    tg[:, 3] *= -1.0
                    q["attributes"]["TANGENT"] = add(tg, 5126, 34962, "VEC4")
                ct = j["accessors"][p["indices"]]["componentType"]
                tri = _accessor(j, data, p["indices"]).reshape(-1, 3)[:, [0, 2, 1]]     # (mirrored: wound the other way)
                q["indices"] = add(tri.ravel(), ct, 34963, "SCALAR")
            prims.append(q)
        j["meshes"].append({"name": "Wheel_%s_from_%s" % (k, op["from"]), "primitives": prims})
        nodes[w]["mesh"] = len(j["meshes"]) - 1
        cx = -sx if flip else sx                        # (the copy's corners across, in its node)
        new_x = outside - (cx.min() if left else cx.max())
        shift = new_x - at[0]
        nodes[w]["translation"] = [float(new_x), at[1], at[2]]
        c = names.get("Caliper_" + k)
        if c is not None:                               # (the caliper stays put: its node moves with the wheel's, its corners back)
            c_at = list(nodes[c].get("translation", [0, 0, 0]))
            nodes[c]["translation"] = [float(c_at[0] + shift), c_at[1], c_at[2]]
            if nodes[c].get("mesh") is not None:
                for p in j["meshes"][nodes[c]["mesh"]]["primitives"]:
                    pos = _accessor(j, data, p["attributes"]["POSITION"]).astype(np.float32).copy()
                    pos[:, 0] -= shift
                    p["attributes"]["POSITION"] = add(pos, 5126, 34962, "VEC3")
        if parts is not None and "wheels" in parts:
            ci, si = corners.index(k), corners.index(op["from"])
            parts["wheels"][ci][0] = float(new_x)
            parts["radius"][ci] = float(parts["radius"][si])
            parts["width"][ci] = float(parts["width"][si])
        done.append("Wheel_%s: Wheel_%s's%s, at x %.3f (was %.3f)" % (k, op["from"], " mirrored" if flip else "", new_x, at[0]))
    data.extend(b"\0" * (-len(data) % 4))
    j["buffers"][0]["byteLength"] = len(data)
    return struct.pack("<I4s", len(data), b"BIN\0") + bytes(data), done


def _subset(j, data, p, tri, shift):
    """A primitive of p's triangles tri alone: only their corners (every attribute), moved back by shift."""
    used, remap = np.unique(tri.ravel(), return_inverse=True)
    attrs = {}
    for name, ai in p["attributes"].items():
        a = j["accessors"][ai]
        arr = _accessor(j, data, ai)[used]
        if name == "POSITION":
            arr = arr.astype(np.float32) - np.asarray(shift, np.float32)
        arr = np.ascontiguousarray(arr.reshape(len(used), -1).astype(_TYPES[a["componentType"]]))
        data.extend(b"\0" * (-len(data) % 4))
        raw = arr.tobytes()
        j["bufferViews"].append({"buffer": 0, "byteOffset": len(data), "byteLength": len(raw), "target": 34962})
        data.extend(raw)
        acc = {"bufferView": len(j["bufferViews"]) - 1, "componentType": a["componentType"], "count": int(len(used)), "type": a["type"]}
        if a.get("normalized"):
            acc["normalized"] = True
        if name == "POSITION":
            acc["min"] = [float(v) for v in arr.min(0)]
            acc["max"] = [float(v) for v in arr.max(0)]
        j["accessors"].append(acc)
        attrs[name] = len(j["accessors"]) - 1
    ct = 5125 if len(used) > 65535 else 5123
    ix = np.ascontiguousarray(remap.astype(_TYPES[ct]))
    data.extend(b"\0" * (-len(data) % 4))
    raw = ix.tobytes()
    j["bufferViews"].append({"buffer": 0, "byteOffset": len(data), "byteLength": len(raw), "target": 34963})
    data.extend(raw)
    j["accessors"].append({"bufferView": len(j["bufferViews"]) - 1, "componentType": ct, "count": int(ix.size), "type": "SCALAR"})
    return dict(p, attributes=attrs, indices=len(j["accessors"]) - 1)


def _wheel_centre(j, rest, op, parts):
    """The "wheel_centre" change: returns the new binary chunk (rest) and what changed."""
    data = bytearray(rest[8:])
    nodes = j["nodes"]
    names = {n.get("name"): i for i, n in enumerate(nodes)}
    mats = [m.get("name", "") for m in j.get("materials", [])]
    corners = ["FL", "FR", "RL", "RR"]
    body = names.get("Body")
    if body is None:
        raise SystemExit("glb_patch wheel_centre: no Body")
    for nm in ["Body"] + ["Wheel_" + k for k in corners] + ["Caliper_" + k for k in corners]:
        n = nodes[names[nm]] if nm in names else {}
        if "matrix" in n or any(abs(a - b) > 1e-6 for a, b in zip(n.get("rotation", [0, 0, 0, 1]), [0, 0, 0, 1])) \
                or any(abs(a - 1) > 1e-6 for a in n.get("scale", [1, 1, 1])) or (nm == "Body" and any(abs(a) > 1e-6 for a in n.get("translation", [0, 0, 0]))):
            raise SystemExit("glb_patch wheel_centre: %s isn't only moved (or the Body not at the origin)" % nm)
    users = {}
    for n in nodes:
        if "mesh" in n:
            users[n["mesh"]] = users.get(n["mesh"], 0) + 1

    def moved(p, shift):
        pos = _accessor(j, data, p["attributes"]["POSITION"]).astype(np.float32) - np.asarray(shift, np.float32)
        data.extend(b"\0" * (-len(data) % 4))
        raw = np.ascontiguousarray(pos).tobytes()
        j["bufferViews"].append({"buffer": 0, "byteOffset": len(data), "byteLength": len(raw), "target": 34962})
        data.extend(raw)
        j["accessors"].append({"bufferView": len(j["bufferViews"]) - 1, "componentType": 5126, "count": int(len(pos)),
                               "type": "VEC3", "min": [float(v) for v in pos.min(0)], "max": [float(v) for v in pos.max(0)]})
        return dict(p, attributes=dict(p["attributes"], POSITION=len(j["accessors"]) - 1))
    def sub(p, tri, shift):
        return _subset(j, data, p, tri, shift)
    done = []
    for k in corners:
        w = names.get("Wheel_" + k)
        if w is None or "mesh" not in nodes[w]:
            raise SystemExit("glb_patch wheel_centre: no Wheel_%s" % k)
        at = np.array(nodes[w].get("translation", [0, 0, 0]), float)
        prims = j["meshes"][nodes[w]["mesh"]]["primitives"]
        pat = "|".join(op.get("to_body", [])) or "$^"
        off = [p for p in prims if "material" in p and re.search(pat, mats[p["material"]])]
        tyre = [p for p in prims if p not in off and "material" in p and re.search(op["tyre"], mats[p["material"]])]
        if not tyre:
            raise SystemExit("glb_patch wheel_centre: Wheel_%s has no %s" % (k, op["tyre"]))
        pts = np.vstack([_accessor(j, data, p["attributes"]["POSITION"]).astype(float) for p in tyre])
        shift = (pts.min(0) + pts.max(0)) * 0.5
        lo_x, hi_x = pts[:, 0].min() - 0.01, pts[:, 0].max() + 0.01
        split = {}                                      # off primitive's position in prims -> its triangles that stay (the hub's)
        for pi, p in enumerate(prims):
            if p not in off:
                continue
            # (the hub's own bits, round its axle inside the wheel, still spin: the nuts, the cap; the rest doesn't)
            v = _accessor(j, data, p["attributes"]["POSITION"]).astype(float)
            tri = _accessor(j, data, p["indices"]).astype(np.int64).reshape(-1, 3)
            _, weld = np.unique(np.round(v / 1e-4).astype(np.int64), axis=0, return_inverse=True)
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
            hub = np.zeros(len(tri), bool)
            for u in set(piece.tolist()):
                q = v[np.unique(tri[piece == u])] - shift
                if q[:, 0].min() >= lo_x - shift[0] and q[:, 0].max() <= hi_x - shift[0] and np.hypot(q[:, 1], q[:, 2]).max() < float(op.get("hub", 0.125)):
                    hub |= piece == u
            split[pi] = (tri, hub)
        if np.abs(shift).max() < 0.002 and all(h.all() for _, h in split.values()):
            continue                                    # (done already)
        if users.get(nodes[w]["mesh"], 1) > 1:
            raise SystemExit("glb_patch wheel_centre: Wheel_%s's mesh is shared" % k)
        new_prims, bits = [], []
        for pi, p in enumerate(prims):
            if pi not in split:
                new_prims.append(moved(p, shift))
                continue
            tri, hub = split[pi]
            if hub.all():
                new_prims.append(moved(p, shift))
                continue
            if hub.any():
                new_prims.append(sub(p, tri[hub], shift))
            bits.append(sub(p, tri[~hub], np.zeros(3)))
        if bits:                                        # (the suspension's bits into the Body: they don't spin)
            j["meshes"].append({"name": "WheelBits_" + k, "primitives": bits})
            nodes.append({"name": "WheelBits_" + k, "mesh": len(j["meshes"]) - 1, "translation": [float(v) for v in at]})
            nodes[body].setdefault("children", []).append(len(nodes) - 1)
        j["meshes"][nodes[w]["mesh"]]["primitives"] = new_prims
        nodes[w]["translation"] = [float(v) for v in at + shift]
        c = names.get("Caliper_" + k)
        if c is not None:                               # (the caliper stays put: its node with the wheel's, its corners back)
            nodes[c]["translation"] = [float(v) for v in np.array(nodes[c].get("translation", [0, 0, 0]), float) + shift]
            if nodes[c].get("mesh") is not None:
                j["meshes"][nodes[c]["mesh"]]["primitives"] = [moved(p, shift) for p in j["meshes"][nodes[c]["mesh"]]["primitives"]]
        tp = pts - shift
        if parts is not None and "wheels" in parts:
            ci = corners.index(k)
            parts["wheels"][ci] = [float(v) for v in at + shift]
            parts["radius"][ci] = float(np.hypot(tp[:, 1], tp[:, 2]).max())
            parts["width"][ci] = float(tp[:, 0].max() - tp[:, 0].min())
        done.append("Wheel_%s: %d of its parts to the Body, its middle moved %s" % (k, len(bits), np.round(shift, 3).tolist()))
    data.extend(b"\0" * (-len(data) % 4))
    j["buffers"][0]["byteLength"] = len(data)
    return struct.pack("<I4s", len(data), b"BIN\0") + bytes(data), done


def _piece_labels(v, tri):
    """Each triangle's piece (faces joined at their corners, welded within 0.1 mm)."""
    _, weld = np.unique(np.round(v / 1e-4).astype(np.int64), axis=0, return_inverse=True)
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
    return np.array([find(int(weld[t[0]])) for t in tri])


def _body_to_wheels(j, rest, op):
    """The "body_to_wheels" change: returns the new binary chunk (rest) and what moved."""
    data = bytearray(rest[8:])
    nodes = j["nodes"]
    names = {n.get("name"): i for i, n in enumerate(nodes)}
    mats = [m.get("name", "") for m in j.get("materials", [])]
    corners = ["FL", "FR", "RL", "RR"]
    if "Body" not in names or "mesh" not in nodes[names["Body"]]:
        raise SystemExit("glb_patch body_to_wheels: no Body mesh")
    for nm in ["Body"] + ["Wheel_" + k for k in corners] + ["Caliper_" + k for k in corners]:
        n = nodes[names[nm]] if nm in names else {}
        if "matrix" in n or any(abs(a - b) > 1e-6 for a, b in zip(n.get("rotation", [0, 0, 0, 1]), [0, 0, 0, 1])) \
                or any(abs(a - 1) > 1e-6 for a in n.get("scale", [1, 1, 1])) or (nm == "Body" and any(abs(a) > 1e-6 for a in n.get("translation", [0, 0, 0]))):
            raise SystemExit("glb_patch body_to_wheels: %s isn't only moved (or the Body not at the origin)" % nm)
    drums = []
    for k in corners:
        w = nodes[names["Wheel_" + k]]
        pts = []
        for p in j["meshes"][w["mesh"]]["primitives"]:
            v = _accessor(j, data, p["attributes"]["POSITION"]).astype(float)
            pts.append(v[np.unique(_accessor(j, data, p["indices"]))] if "indices" in p else v)
        pts = np.vstack(pts)
        r = np.hypot(pts[:, 1], pts[:, 2])
        tread = pts[r > r.max() * 0.93, 0]
        drums.append((np.array(w.get("translation", [0, 0, 0]), float), float(r.max()), float(tread.min()), float(tread.max())))
    pat = "|".join(op.get("mats", [])) or "."
    skip = "|".join(op.get("skip_mats", [])) or "$^"
    cal = "|".join(op.get("caliper_mats", [])) or "$^"
    big, axle = float(op.get("min", 0.3)), float(op.get("axle", 0.06))
    body_mesh = j["meshes"][nodes[names["Body"]]["mesh"]]
    keep, gone, done = [], {}, []
    for p in body_mesh["primitives"]:
        name = mats[p["material"]] if "material" in p else ""
        if "indices" not in p or p.get("mode", 4) != 4 or not re.search(pat, name) or re.search(skip, name):
            keep.append(p)
            continue
        v = _accessor(j, data, p["attributes"]["POSITION"]).astype(float)
        tri = _accessor(j, data, p["indices"]).astype(np.int64).reshape(-1, 3)
        lab = _piece_labels(v, tri)
        go = np.full(len(tri), -1)
        order = np.argsort(lab, kind="stable")
        for grp in np.split(order, np.flatnonzero(np.diff(lab[order])) + 1):
            q = v[np.unique(tri[grp])]
            for ci, (at, R, lo, hi) in enumerate(drums):
                d = q - at
                rr = np.hypot(d[:, 1], d[:, 2])
                if rr.max() < R + 0.02 and d[:, 0].min() > lo - 0.03 and d[:, 0].max() < hi + 0.03:
                    sy, sz = np.ptp(q[:, 1]), np.ptp(q[:, 2])
                    if (min(sy, sz) >= big and abs(sy - sz) < 0.15 * max(sy, sz)) or rr.max() < axle:
                        go[grp] = ci           # (a wheel's: round about its axle, or on it)
                    break
        if (go < 0).all():
            keep.append(p)
            continue
        if (go < 0).any():
            keep.append(_subset(j, data, p, tri[go < 0], np.zeros(3)))
        for ci in sorted(set(go[go >= 0].tolist())):
            k = corners[ci]
            target = ("Caliper_" if re.search(cal, name) and "Caliper_" + k in names else "Wheel_") + k
            at = np.array(nodes[names[target]].get("translation", [0, 0, 0]), float)
            gone.setdefault(target, []).append(_subset(j, data, p, tri[go == ci], at))
            done.append("%s: %d faces of %s from the Body" % (target, int((go == ci).sum()), name))
    body_mesh["primitives"] = keep
    users = {}
    for n in nodes:
        if "mesh" in n:
            users[n["mesh"]] = users.get(n["mesh"], 0) + 1
    for target, prims in gone.items():
        n = nodes[names[target]]
        if "mesh" not in n:
            j["meshes"].append({"name": target, "primitives": []})
            n["mesh"] = len(j["meshes"]) - 1
        elif users.get(n["mesh"], 1) > 1:
            raise SystemExit("glb_patch body_to_wheels: %s's mesh is shared" % target)
        j["meshes"][n["mesh"]]["primitives"] += prims
    data.extend(b"\0" * (-len(data) % 4))
    j["buffers"][0]["byteLength"] = len(data)
    return struct.pack("<I4s", len(data), b"BIN\0") + bytes(data), done


def _drop_dupes(j, rest, ops):
    """The "drop_dupes" change: returns the new binary chunk (rest) and what went."""
    data = bytearray(rest[8:])
    mats = [m.get("name", "") for m in j.get("materials", [])]
    xfs = _node_xf(j)
    done = []
    for op in ops:
        keep_c = []                                     # the kept material's faces: their middles (the scene's space)
        for mi, mesh in enumerate(j.get("meshes", [])):
            for xf in xfs.get(mi, [])[:1]:
                for p in mesh["primitives"]:
                    if "material" in p and "indices" in p and re.search(op["keep"], mats[p["material"]]):
                        v = _accessor(j, data, p["attributes"]["POSITION"]).astype(float) @ xf[:3, :3].T + xf[:3, 3]
                        tri = _accessor(j, data, p["indices"]).astype(np.int64).reshape(-1, 3)
                        keep_c.append(v[tri].mean(axis=1))
        if not keep_c:
            raise SystemExit("glb_patch drop_dupes: no material %s" % op["keep"])
        keep_c = np.vstack(keep_c)
        key = {tuple(k) for k in np.round(keep_c / 0.0005).astype(np.int64).tolist()}
        for mi, mesh in enumerate(j.get("meshes", [])):
            for xf in xfs.get(mi, [])[:1]:
                for p in mesh["primitives"]:
                    if "material" not in p or "indices" not in p or not re.search(op["drop"], mats[p["material"]]) \
                            or re.search(op["keep"], mats[p["material"]]):
                        continue
                    v = _accessor(j, data, p["attributes"]["POSITION"]).astype(float) @ xf[:3, :3].T + xf[:3, 3]
                    tri = _accessor(j, data, p["indices"]).astype(np.int64).reshape(-1, 3)
                    c = np.round(v[tri].mean(axis=1) / 0.0005).astype(np.int64)
                    # (a face whose middle is the kept one's, give or take 0.5 mm: the same face twice)
                    dup = np.array([any((a + dx, b + dy, cc + dz) in key for dx in (-1, 0, 1) for dy in (-1, 0, 1) for dz in (-1, 0, 1))
                                    for a, b, cc in c.tolist()])
                    if not dup.any():
                        continue
                    ct = j["accessors"][p["indices"]]["componentType"]
                    ix = np.ascontiguousarray(tri[~dup].ravel().astype(_TYPES[ct]))
                    data.extend(b"\0" * (-len(data) % 4))
                    raw = ix.tobytes()
                    j["bufferViews"].append({"buffer": 0, "byteOffset": len(data), "byteLength": len(raw), "target": 34963})
                    data.extend(raw)
                    j["accessors"].append({"bufferView": len(j["bufferViews"]) - 1, "componentType": ct, "count": int(ix.size), "type": "SCALAR"})
                    p["indices"] = len(j["accessors"]) - 1
                    done.append("%s: %d faces of %s that were %s's twice" % (mesh.get("name", mi), int(dup.sum()), mats[p["material"]], op["keep"]))
    data.extend(b"\0" * (-len(data) % 4))
    j["buffers"][0]["byteLength"] = len(data)
    return struct.pack("<I4s", len(data), b"BIN\0") + bytes(data), done


def apply(path, patch, parts=None):
    """Applies a spec's "glb_patch" to the GLB at path; returns what it changed. parts: the model's
    parts.json as a dictionary, changed to match ("wheels_from"); none: the file next to the GLB."""
    if not patch:
        return []
    j, rest = read(path)
    done = []
    if patch.get("faces"):
        rest, moved = _move_faces(j, rest, patch["faces"])
        done += moved
    if patch.get("wheels_from") or patch.get("wheel_centre"):
        parts_file = os.path.join(os.path.dirname(os.path.abspath(path)), "parts.json") if parts is None else None
        if parts_file and os.path.exists(parts_file):
            parts = json.load(open(parts_file))
        changed = []
        if patch.get("wheel_centre"):
            rest, ch = _wheel_centre(j, rest, patch["wheel_centre"], parts)
            changed += ch
        if patch.get("wheels_from"):
            rest, ch = _wheels_from(j, rest, patch["wheels_from"], parts)
            changed += ch
        done += changed
        if parts_file and parts is not None and changed:
            json.dump(parts, open(parts_file, "w"), indent=2)
    if "body_to_wheels" in patch:
        rest, moved = _body_to_wheels(j, rest, patch["body_to_wheels"])
        done += moved
    if patch.get("drop_dupes"):
        rest, gone = _drop_dupes(j, rest, patch["drop_dupes"])
        done += gone
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
