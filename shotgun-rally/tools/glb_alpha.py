"""Blended materials that aren't see-through, made opaque (or cut out) in a GLB.

Game-ripped and racing-sim models often mark every material as alpha-blended
("alphaMode": "BLEND"). Godot draws a blended surface in its transparent pass
(with a depth pre-pass): every one costs a second pass, it gets no ambient
occlusion, and the car's real glass, drawn in the same pass, sorts wrong against
it (the windows lose their tint over the interior). So each BLEND material is
judged by what its alpha really is (the base colour factor's times its texture's):
  * all opaque (factor 1, the texture's alpha all over 0.98): "OPAQUE"
  * holes with hard edges (under 5 % of the texture's pixels in between): "MASK"
    (cut out at 0.5: drawn with the opaque surfaces)
  * anything else (glass, soft decals, a factor under 1): left "BLEND"
Only the GLB's JSON changes (the materials' alphaMode / alphaCutoff); the binary
chunk, every mesh and image, stays byte for byte.

Run in Blender (it decodes the images: PNG, JPEG, WebP):
  blender -b -Y --python tools/glb_alpha.py -- a.glb [b.glb ...] [--dry]
tools/import_car.py runs it on every car it writes.
"""
import json, os, struct, sys, tempfile

import bpy
import numpy as np

EXT = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp"}


def _read(path):
    b = open(path, "rb").read()
    magic, version, total = struct.unpack("<4sII", b[:12])
    if magic != b"glTF":
        raise ValueError("%s: not a GLB" % path)
    n, kind = struct.unpack("<I4s", b[12:20])
    assert kind == b"JSON"
    return json.loads(b[20:20 + n]), b[20 + n:]


def _write(path, j, rest):
    s = json.dumps(j, separators=(",", ":")).encode()
    s += b" " * (-len(s) % 4)
    head = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(s) + len(rest))
    open(path, "wb").write(head + struct.pack("<I4s", len(s), b"JSON") + s + rest)


def _alpha_of(j, rest, tex_index, cache):
    """The texture's alpha channel (a flat array, 0..1), or None if it has none."""
    src = j["textures"][tex_index].get("source")
    if src is None:
        return None
    if src in cache:
        return cache[src]
    im = j["images"][src]
    if "bufferView" not in im:
        cache[src] = None
        return None
    bv = j["bufferViews"][im["bufferView"]]
    # the binary chunk: its 8-byte header, then the buffer
    data = rest[8 + bv.get("byteOffset", 0): 8 + bv.get("byteOffset", 0) + bv["byteLength"]]
    fd, tmp = tempfile.mkstemp(suffix=EXT.get(im.get("mimeType"), ".png"))
    os.write(fd, data)
    os.close(fd)
    try:
        img = bpy.data.images.load(tmp)
        img.alpha_mode = 'STRAIGHT'
        a = None
        if img.channels == 4 and img.size[0] * img.size[1] > 0:
            px = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
            img.pixels.foreach_get(px)
            a = px[3::4].copy()
        bpy.data.images.remove(img)
    finally:
        os.remove(tmp)
    cache[src] = a
    return a


def verdict(j, rest, m, cache):
    """'OPAQUE', 'MASK' or 'BLEND': what this material's alpha needs."""
    pbr = m.get("pbrMetallicRoughness", {})
    factor = pbr.get("baseColorFactor", [1, 1, 1, 1])[3]
    if factor < 0.999:
        return "BLEND"
    t = pbr.get("baseColorTexture")
    if t is None:
        return "OPAQUE"
    a = _alpha_of(j, rest, t["index"], cache)
    if a is None or float(a.min()) > 0.98:
        return "OPAQUE"
    soft = float(((a > 0.1) & (a < 0.9)).mean())
    return "MASK" if soft < 0.05 else "BLEND"


def fix_alpha(path, dry=False):
    """Judges every blended material in the GLB at path; rewrites it (unless dry).
    Returns {verdict: [material names]} for the ones it judged."""
    j, rest = _read(path)
    cache = {}
    out = {"OPAQUE": [], "MASK": [], "BLEND": []}
    for m in j.get("materials", []):
        if m.get("alphaMode") != "BLEND":
            continue
        v = verdict(j, rest, m, cache)
        out[v].append(m.get("name", "?"))
        if v == "OPAQUE":
            del m["alphaMode"]
            m.pop("alphaCutoff", None)
        elif v == "MASK":
            m["alphaMode"] = "MASK"
            m["alphaCutoff"] = 0.5
    if not dry and (out["OPAQUE"] or out["MASK"]):
        _write(path, j, rest)
    return out


if __name__ == "__main__" and "--" in sys.argv:
    args = sys.argv[sys.argv.index("--") + 1:]
    dry = "--dry" in args
    for p in [a for a in args if a != "--dry"]:
        r = fix_alpha(p, dry)
        print("%s: %d blended -> %d opaque, %d cut out, %d left blended %s" % (
            os.path.basename(p), sum(len(v) for v in r.values()), len(r["OPAQUE"]), len(r["MASK"]),
            len(r["BLEND"]), r["BLEND"][:12]))
