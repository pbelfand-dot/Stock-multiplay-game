"""A GLB's PNG images re-encoded as WEBP (EXT_texture_webp, as Blender's exporter writes them):
tools/buildings.py exports its buildings with PNG images (Blender 4.0's exporter turned a baked
2048 px image into rows of smeared colour when it wrote WEBP itself) and this shrinks them after.
Needs Pillow (the system's python3, not Blender's).

    python3 tools/glb_webp.py <file.glb> [quality, default 90]

Lossy, the alpha kept. Every other byte of the GLB stays as it was (its buffer views moved).
"""
import io
import json
import struct
import sys

from PIL import Image


def _pad(b, fill=b"\0"):
    return b + fill * ((4 - len(b) % 4) % 4)


def convert(path, quality=90):
    data = open(path, "rb").read()
    jl = struct.unpack("<I", data[12:16])[0]
    j = json.loads(data[20:20 + jl])
    off = 20 + jl
    bl = struct.unpack("<I", data[off:off + 4])[0]
    blob = data[off + 8:off + 8 + bl]
    views = j.get("bufferViews", [])
    changed = {}
    for im in j.get("images", []):
        if im.get("mimeType") != "image/png" or "bufferView" not in im:
            continue
        v = views[im["bufferView"]]
        o = v.get("byteOffset", 0)
        pic = Image.open(io.BytesIO(blob[o:o + v["byteLength"]]))
        out = io.BytesIO()
        pic.save(out, "WEBP", quality=quality, method=6, exact=True)
        changed[im["bufferView"]] = out.getvalue()
        im["mimeType"] = "image/webp"
    if not changed:
        return 0
    # the binary chunk again: each view's bytes (the changed ones new), 4-byte aligned
    order = sorted(range(len(views)), key=lambda k: views[k].get("byteOffset", 0))
    new = b""
    for k in order:
        v = views[k]
        o = v.get("byteOffset", 0)
        b = changed.get(k, blob[o:o + v["byteLength"]])
        new = _pad(new)
        v["byteOffset"] = len(new)
        v["byteLength"] = len(b)
        new += b
    new = _pad(new)
    j["buffers"][0]["byteLength"] = len(new)
    # the textures read the images through EXT_texture_webp
    for t in j.get("textures", []):
        src = t.pop("source", None)
        if src is not None:
            t.setdefault("extensions", {})["EXT_texture_webp"] = {"source": src}
    used = j.setdefault("extensionsUsed", [])
    if "EXT_texture_webp" not in used:
        used.append("EXT_texture_webp")
    js = _pad(json.dumps(j, separators=(",", ":")).encode(), b" ")
    total = 12 + 8 + len(js) + 8 + len(new)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(new), 0x004E4942) + new)
    return len(changed)


if __name__ == "__main__":
    n = convert(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 90)
    print("%s: %d image(s) to WEBP" % (sys.argv[1], n))
