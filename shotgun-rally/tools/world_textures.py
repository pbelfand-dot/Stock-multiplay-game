#!/usr/bin/env python3
"""The world's textures and skies (scripts/render/world_materials.gd uses them), made
from CC0 scans off Poly Haven (https://polyhaven.com, CC0: no attribution needed, but
docs/CREDITS_WORLD.md credits every one). Re-run to remake them:

    python3 tools/world_textures.py [--cache DIR] [textures] [local] [skies] [foliage] [credits]
    (local: the CC0 sets already in assets/environment_packages, no download)

Textures (assets/textures/world/<name>_*.webp, 1024 px):
  <name>_albedo.webp   the colour (sRGB) in RGB, the roughness in A
  <name>_normal.webp   the normal map (OpenGL: green up, as Godot wants)
  textures.json        per texture: how many metres it covers, its mean colour (linear)
                       and roughness, where it came from
Skies (assets/textures/sky/<mood>.webp, 2048 x 569): the upper half of a "pure sky"
HDRI plus 10 degrees below the horizon, scaled so the light it sheds on flat ground is
1.0, then log-encoded into 8 bits (v = log2(x / SKY_LO) / log2(SKY_HI / SKY_LO): ~2.7 %
a step everywhere, no banding), the sun itself taken out (the sky shader draws it where
the DirectionalLight is); sky.json: where its sun was, the horizon's and the zenith's
colour (linear, in those units), the encoding.

Needs Pillow and numpy (pip install pillow numpy).
"""
import argparse, io, json, math, os, struct, sys, urllib.request

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TEX_OUT = os.path.join(ROOT, "assets", "textures", "world")
SKY_OUT = os.path.join(ROOT, "assets", "textures", "sky")
SIZE = 1024
SKY_W = 2048
SKY_BELOW = 10.0           # degrees under the horizon kept
SKY_LO = 0.04             # the encoding's range (x the sky's own light on flat ground):
SKY_HI = 48.0             # the darkest cloud base to the sun's glow (the sun itself is drawn)

# name -> Poly Haven id. What each is for: world_materials.gd.
TEXTURES = {
    "asphalt": "asphalt_01",
    "gravel": "gravel_ground_01",
    "grass": "leafy_grass",
    "dirt": "brown_mud_02",
    "rock": "rock_face_03",
    "concrete": "concrete_floor_02",
    "snow": "snow_02",
}
# mood -> Poly Haven pure-sky HDRI
SKIES = {
    "day": "kloofendal_48d_partly_cloudy_puresky",
    "golden": "kloppenheim_06_puresky",
    "overcast": "overcast_soil_puresky",
}


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "shotgun-rally-world-textures/1.0"})
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()


def fetch(cache, asset, kind, res, fmt):
    """A Poly Haven file (cached): kind 'Diffuse' / 'nor_gl' / 'Rough' / 'hdri'."""
    os.makedirs(os.path.join(cache, asset), exist_ok=True)
    files = json.loads(get("https://api.polyhaven.com/files/" + asset))
    entry = files[kind][res][fmt]
    path = os.path.join(cache, asset, os.path.basename(entry["url"]))
    if not os.path.exists(path) or os.path.getsize(path) != entry["size"]:
        open(path, "wb").write(get(entry["url"]))
    return path


def info(cache, asset):
    path = os.path.join(cache, asset, "info.json")
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "wb").write(get("https://api.polyhaven.com/info/" + asset))
    return json.load(open(path))


def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def load_rgb(path, size=SIZE):
    im = Image.open(path).convert("RGB")
    if im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    return np.asarray(im).astype(np.float32) / 255.0


def textures(cache):
    os.makedirs(TEX_OUT, exist_ok=True)
    table = {}
    for name, asset in TEXTURES.items():
        meta = info(cache, asset)
        diff = load_rgb(fetch(cache, asset, "Diffuse", "1k", "jpg"))
        rough = load_rgb(fetch(cache, asset, "Rough", "1k", "jpg"))[:, :, 0]
        nor = load_rgb(fetch(cache, asset, "nor_gl", "1k", "jpg"))
        rgba = np.dstack([diff, rough])
        Image.fromarray((rgba * 255.0 + 0.5).astype(np.uint8), "RGBA").save(
            os.path.join(TEX_OUT, name + "_albedo.webp"), quality=90, alpha_quality=80, method=6)
        Image.fromarray((nor * 255.0 + 0.5).astype(np.uint8), "RGB").save(
            os.path.join(TEX_OUT, name + "_normal.webp"), quality=92, method=6)
        lin = srgb_to_linear(diff)
        dims = meta.get("dimensions") or [2000, 2000]
        table[name] = {
            "size_m": round(float(dims[0]) / 1000.0, 3),
            "mean_linear": [round(float(x), 4) for x in lin.reshape(-1, 3).mean(axis=0)],
            "roughness": round(float(rough.mean()), 3),
            "source": "Poly Haven: %s (%s)" % (meta.get("name", asset), asset),
            "url": "https://polyhaven.com/a/" + asset,
            "authors": meta.get("authors", {}),
            "licence": "CC0",
        }
        print(name, table[name]["size_m"], "m", table[name]["mean_linear"], table[name]["roughness"])
    json.dump(table, open(os.path.join(TEX_OUT, "textures.json"), "w"), indent=1)
    local_textures()                                 # (the library's own sets kept in the table)


# name -> (the CC0 library's folder under assets/environment_packages/cc0/polyhaven, its Poly Haven id,
# metres one repeat covers: the glTF plane it came with): already in the repository, no download
LOCAL_TEXTURES = {
    "forest": ("forrest_ground_01_2k", "forrest_ground_01", 2.0, "Forest Ground 01"),
    "asphalt2": ("asphalt_02_2k", "asphalt_02", 3.0, "Asphalt 02"),
}


def local_textures():
    """The library's CC0 sets (assets/environment_packages/cc0/polyhaven) made into the world's
    textures like the downloaded ones, added to textures.json."""
    lib = os.path.join(ROOT, "assets", "environment_packages", "cc0", "polyhaven")
    path = os.path.join(TEX_OUT, "textures.json")
    table = json.load(open(path)) if os.path.exists(path) else {}
    for name, (folder, asset, size_m, title) in LOCAL_TEXTURES.items():
        d = os.path.join(lib, folder, "textures")
        diff = load_rgb(os.path.join(d, "%s_diff_2k.jpg" % asset))
        rough = load_rgb(os.path.join(d, "%s_rough_2k.jpg" % asset))[:, :, 0]
        nor = load_rgb(os.path.join(d, "%s_nor_gl_2k.jpg" % asset))
        rgba = np.dstack([diff, rough])
        Image.fromarray((rgba * 255.0 + 0.5).astype(np.uint8), "RGBA").save(
            os.path.join(TEX_OUT, name + "_albedo.webp"), quality=90, alpha_quality=80, method=6)
        Image.fromarray((nor * 255.0 + 0.5).astype(np.uint8), "RGB").save(
            os.path.join(TEX_OUT, name + "_normal.webp"), quality=92, method=6)
        lin = srgb_to_linear(diff)
        table[name] = {
            "size_m": size_m,
            "mean_linear": [round(float(x), 4) for x in lin.reshape(-1, 3).mean(axis=0)],
            "roughness": round(float(rough.mean()), 3),
            "source": "Poly Haven: %s (%s), from the CC0 library in assets/environment_packages" % (title, asset),
            "url": "https://polyhaven.com/a/" + asset,
            "authors": {},
            "licence": "CC0",
        }
        print(name, size_m, "m", table[name]["mean_linear"], table[name]["roughness"])
    json.dump(table, open(path, "w"), indent=1)


def read_hdr(path):
    """A Radiance .hdr (RGBE, new-style run-length scanlines) -> float32 HxWx3."""
    f = open(path, "rb")
    line = f.readline()
    if not line.startswith(b"#?"):
        raise ValueError("not a Radiance file")
    while True:
        line = f.readline().strip()
        if line == b"":
            break
    dims = f.readline().split()
    h, w = int(dims[1]), int(dims[3])
    data = np.zeros((h, w, 4), np.uint8)
    for y in range(h):
        head = f.read(4)
        if head[0] != 2 or head[1] != 2 or (head[2] << 8 | head[3]) != w:
            raise ValueError("unsupported scanline encoding")
        for c in range(4):
            x = 0
            row = data[y, :, c]
            while x < w:
                n = f.read(1)[0]
                if n > 128:
                    n -= 128
                    row[x:x + n] = f.read(1)[0]
                else:
                    row[x:x + n] = np.frombuffer(f.read(n), np.uint8)
                x += n
    e = data[:, :, 3].astype(np.int32)
    scale = np.where(e > 0, np.ldexp(1.0, e - 136), 0.0).astype(np.float32)
    return data[:, :, :3].astype(np.float32) * scale[:, :, None]


def skies(cache):
    os.makedirs(SKY_OUT, exist_ok=True)
    table = {}
    for mood, asset in SKIES.items():
        meta = info(cache, asset)
        hdr = read_hdr(fetch(cache, asset, "hdri", "2k", "hdr"))
        h, w = hdr.shape[:2]
        lum = hdr @ np.array([0.2126, 0.7152, 0.0722], np.float32)
        # the sun: the brightest spot (Poly Haven panoramas: u = 0.5 looks down -Z, u grows clockwise from above)
        sy, sx = np.unravel_index(np.argmax(lum), lum.shape)
        sun_u = (sx + 0.5) / w
        sun_v = (sy + 0.5) / h
        elevation = 90.0 - sun_v * 180.0
        # the light from the sky without the sun's disc (a ~4 degree hole filled from its rim)
        sun_r = int(w * 2.0 / 360.0) + 2
        yy, xx = np.mgrid[0:h, 0:w]
        dx = np.minimum(np.abs(xx - sx), w - np.abs(xx - sx))
        hole = (dx ** 2 + (yy - sy) ** 2) <= sun_r ** 2
        rim = ((dx ** 2 + (yy - sy) ** 2) <= (sun_r + 3) ** 2) & ~hole
        sun_peak = float(lum[sy, sx])
        hdr[hole] = hdr[rim].mean(axis=0)
        rows = int(round(h * (90.0 + SKY_BELOW) / 180.0))
        top = hdr[:rows]
        horizon = hdr[int(h * 0.47):int(h * 0.5)].reshape(-1, 3).mean(axis=0)
        zenith = hdr[:int(h * 0.08)].reshape(-1, 3).mean(axis=0)
        upper = hdr[:h // 2].reshape(-1, 3)
        # irradiance on a flat surface from the upper half (cos-weighted), for the ambient's strength
        theta = (np.arange(h // 2) + 0.5) / h * math.pi
        wgt = (np.cos(theta) * np.sin(theta))[:, None].repeat(w, 1).reshape(-1)
        irr = (upper * wgt[:, None]).sum(axis=0) / wgt.sum()
        norm = 1.0 / float(irr @ np.array([0.2126, 0.7152, 0.0722], np.float32))
        top = top * norm
        horizon, zenith, irr = horizon * norm, zenith * norm, irr * norm
        enc = np.log2(np.clip(top, SKY_LO, SKY_HI) / SKY_LO) / math.log2(SKY_HI / SKY_LO)
        img = Image.fromarray((np.clip(enc, 0, 1) * 255.0 + 0.5).astype(np.uint8), "RGB")
        img = img.resize((SKY_W, int(round(SKY_W * rows / w))), Image.LANCZOS)
        img.save(os.path.join(SKY_OUT, mood + ".webp"), quality=92, method=6)
        table[mood] = {
            "sun_u": round(float(sun_u), 4), "sun_elevation": round(float(elevation), 2),
            "sun_peak": round(sun_peak * norm, 1), "scale": round(norm, 4),
            "horizon_linear": [round(float(x), 4) for x in horizon],
            "zenith_linear": [round(float(x), 4) for x in zenith],
            "irradiance_linear": [round(float(x), 4) for x in irr],
            "below_deg": SKY_BELOW, "lo": SKY_LO, "hi": SKY_HI,
            "source": "Poly Haven: %s (%s)" % (meta.get("name", asset), asset),
            "url": "https://polyhaven.com/a/" + asset,
            "authors": meta.get("authors", {}),
            "licence": "CC0",
        }
        print(mood, json.dumps(table[mood]))
    json.dump(table, open(os.path.join(SKY_OUT, "sky.json"), "w"), indent=1)


FOLIAGE_OUT = os.path.join(ROOT, "assets", "textures", "foliage")
FIR = "fir_tree_01"          # Poly Haven model whose twig atlas (sprigs + a bark strip) the card trees use


def fetch_model_file(cache, asset, name):
    """A file a Poly Haven model's .fbx brings along (its textures), cached."""
    os.makedirs(os.path.join(cache, asset), exist_ok=True)
    files = json.loads(get("https://api.polyhaven.com/files/" + asset))
    entry = files["fbx"]["1k"]["fbx"]["include"]["textures/" + name]
    path = os.path.join(cache, asset, name)
    if not os.path.exists(path) or os.path.getsize(path) != entry["size"]:
        open(path, "wb").write(get(entry["url"]))
    return path


def foliage(cache):
    """assets/textures/foliage/fir_twig.webp: the fir's twig atlas, colour + its alpha cut-out."""
    os.makedirs(FOLIAGE_OUT, exist_ok=True)
    meta = info(cache, FIR)
    diff = Image.open(fetch_model_file(cache, FIR, FIR + "_twig_diff_1k.png")).convert("RGB")
    alpha = Image.open(fetch_model_file(cache, FIR, FIR + "_twig_alpha_1k.png")).convert("L")
    rgba = diff.copy()
    rgba.putalpha(alpha)
    rgba.save(os.path.join(FOLIAGE_OUT, "fir_twig.webp"), quality=90, alpha_quality=90, method=6)
    table = {"fir_twig": {"source": "Poly Haven: %s (%s), its twig texture" % (meta.get("name", FIR), FIR),
                          "url": "https://polyhaven.com/a/" + FIR, "authors": meta.get("authors", {}), "licence": "CC0"}}
    json.dump(table, open(os.path.join(FOLIAGE_OUT, "foliage.json"), "w"), indent=1)
    print("fir_twig", os.path.getsize(os.path.join(FOLIAGE_OUT, "fir_twig.webp")), "bytes")


def credits():
    """docs/CREDITS_WORLD.md: every world texture and sky, from the two json files."""
    rows = []
    for folder, kind in ((TEX_OUT, "texture"), (SKY_OUT, "sky"), (FOLIAGE_OUT, "foliage")):
        path = os.path.join(folder, {"texture": "textures.json", "sky": "sky.json", "foliage": "foliage.json"}[kind])
        if not os.path.exists(path):
            continue
        for name, e in json.load(open(path)).items():
            authors = ", ".join("%s (%s)" % (k, v.strip()) for k, v in e.get("authors", {}).items())
            files = {"texture": "assets/textures/world/%s_albedo.webp, %s_normal.webp" % (name, name),
                     "sky": "assets/textures/sky/%s.webp" % name, "foliage": "assets/textures/foliage/%s.webp" % name}[kind]
            rows.append("| %s `%s` | %s | [%s](%s) | %s | %s |" % (kind, name, files, e["source"], e["url"], authors, e["licence"]))
    out = ["# Credits: the world's textures and skies", "",
           "Generated by `tools/world_textures.py` (don't edit by hand; re-run it after changing its lists).",
           "All are CC0 (public domain: no attribution required, credited anyway). The textures are",
           "1K scans, repacked (colour + roughness in one file, the normal map in another); the skies",
           "are the upper half of each HDRI, log-encoded into 8 bits; the card trees use a fir model's",
           "twig texture (sprigs and a strip of bark). The cars' credits: `CREDITS.md`.", "",
           "| What | Files | Source | Authors | Licence |", "|---|---|---|---|---|"] + rows
    open(os.path.join(ROOT, "docs", "CREDITS_WORLD.md"), "w").write("\n".join(out) + "\n")
    print("wrote docs/CREDITS_WORLD.md (%d rows)" % len(rows))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=os.path.join(ROOT, "build", "texture_cache"))
    ap.add_argument("what", nargs="*", default=["textures", "skies", "foliage", "credits"])
    a = ap.parse_args()
    if "textures" in a.what:
        textures(a.cache)
    if "local" in a.what:
        local_textures()
    if "skies" in a.what:
        skies(a.cache)
    if "foliage" in a.what:
        foliage(a.cache)
    if set(a.what) & {"credits", "textures", "local", "skies", "foliage"}:
        credits()


if __name__ == "__main__":
    main()
