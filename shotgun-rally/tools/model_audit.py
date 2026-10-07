"""Checks every car model (assets/models/cars/<id>/<id>.glb) for the glitches you
see in the game: what Godot will draw, read straight from the GLB (one-sided
faces are culled from behind; "BLEND" and "MASK" materials by their alpha).

  * the wheels: all four, round about their axle (a wheel spun off centre
    wobbles), a tyre all the way round, a rim you can see from outside (not
    a see-through or inside-out hub, not a rim that faces the car), and
    nothing left of a wheel in the Body (a second wheel that doesn't turn)
  * the tail lights: red you can see from behind, at the back of the car
  * the body: faces wound against their normals or facing in (drawn from
    the wrong side, so missing from outside), see-through materials that
    aren't glass, plain white materials (a texture that went missing)

Run in Blender (it decodes the textures):
  blender -b -Y --python tools/model_audit.py -- [model ids ...] [--json out.json]
Prints one block per car, its FLAG lines first; exits 1 if any car has a FLAG.
Every check is from the files (numbers, not looks): it's how the cars whose
licences say no AI are checked.
"""
import glob
import json
import math
import os
import re
import struct
import sys
import tempfile

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CARS = os.path.join(ROOT, "assets", "models", "cars")
CORNERS = ["FL", "FR", "RL", "RR"]
GLASS = re.compile(r"glass|window|wind|screen|lens|light|lamp|clear|visor|transp|vetro|glas|crystal|mirror|refl|chrome|"
                   r"decal|detail|text|logo|grid|grill|mesh", re.I)
LIGHT = re.compile(r"light|lamp|tail|brake|stop|led|lens|rear_?l|fanal|feu|luz|optic|emiss|glow|indicat|blink|signal|rlight", re.I)
COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
EXT = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp"}


class Glb:
    def __init__(self, path):
        self.path = path
        b = open(path, "rb").read()
        n = struct.unpack("<I", b[12:16])[0]
        self.j = json.loads(b[20:20 + n])
        rest = b[20 + n:]
        self.bin = rest[8:8 + struct.unpack("<I", rest[:4])[0]] if rest else b""
        self.images = {}

    def accessor(self, i):
        a = self.j["accessors"][i]
        dt = COMP[a["componentType"]]
        nc = NCOMP[a["type"]]
        out = np.zeros((a["count"], nc), dtype=np.float64)
        if "bufferView" in a:
            bv = self.j["bufferViews"][a["bufferView"]]
            off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
            item = np.dtype(dt).itemsize * nc
            stride = bv.get("byteStride", item)
            raw = np.frombuffer(self.bin, dtype=np.uint8, count=stride * (a["count"] - 1) + item, offset=off)
            if stride == item:
                out = np.frombuffer(raw.tobytes(), dtype=dt).reshape(a["count"], nc).astype(np.float64)
            else:
                rows = np.lib.stride_tricks.as_strided(raw, shape=(a["count"], item), strides=(stride, 1))
                out = np.frombuffer(rows.copy().tobytes(), dtype=dt).reshape(a["count"], nc).astype(np.float64)
            if a.get("normalized"):
                out /= float(np.iinfo(dt).max)
        return out

    def image(self, tex_index):
        """The texture's pixels, (h, w, 4) floats, row 0 at the top (glTF's v = 0)."""
        t = self.j["textures"][tex_index]
        src = t.get("source", t.get("extensions", {}).get("EXT_texture_webp", {}).get("source"))
        if src is None:
            return None
        if src in self.images:
            return self.images[src]
        im = self.j["images"][src]
        px = None
        tmp = None
        try:
            if "bufferView" in im:
                bv = self.j["bufferViews"][im["bufferView"]]
                data = self.bin[bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]]
                fd, tmp = tempfile.mkstemp(suffix=EXT.get(im.get("mimeType"), ".png"))
                os.write(fd, data)
                os.close(fd)
                path = tmp
            else:
                path = os.path.join(os.path.dirname(self.path), im.get("uri", ""))
            img = bpy.data.images.load(path)
            img.alpha_mode = 'STRAIGHT'
            w, h = img.size
            if w * h > 0:
                a = np.empty(w * h * 4, dtype=np.float32)
                img.pixels.foreach_get(a)
                px = a.reshape(h, w, 4)[::-1]          # Blender's row 0 is the bottom
                if img.channels < 4:
                    px[..., 3] = 1.0
                # colour textures: Blender hands over sRGB images as stored (0..1)
            bpy.data.images.remove(img)
        except Exception as e:  # unreadable: judged by its factor alone
            px = None
        finally:
            if tmp:
                os.remove(tmp)
        self.images[src] = px
        return px


def _mat4(node):
    if "matrix" in node:
        return np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T
    t = node.get("translation", [0, 0, 0])
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    s = node.get("scale", [1, 1, 1])
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m = np.eye(4)
    m[:3, :3] = r * np.array(s)[None, :]
    m[:3, 3] = t
    return m


class Tris:
    """Every triangle of a part, in the car's space (m): corners, the side Godot
    draws (the front face's normal, from the winding), the stored normals'
    average, area, centroid, its material, the colour and alpha Godot draws it
    with there (the factor times the texture at the centroid)."""

    def __init__(self, glb, roots):
        j = glb.j
        P, N, UVC, UVE, M = [], [], [], [], []
        self.mats = j.get("materials", [])

        def walk(ni, parent):
            node = j["nodes"][ni]
            m = parent @ _mat4(node)
            if "mesh" in node:
                for pr in j["meshes"][node["mesh"]]["primitives"]:
                    if pr.get("mode", 4) != 4:
                        continue
                    pos = glb.accessor(pr["attributes"]["POSITION"])
                    nrm = glb.accessor(pr["attributes"]["NORMAL"]) if "NORMAL" in pr["attributes"] else None
                    mi = pr.get("material", -1)
                    tc = 0
                    if mi >= 0:
                        t = self.mats[mi].get("pbrMetallicRoughness", {}).get("baseColorTexture")
                        tc = t.get("texCoord", 0) if t else 0
                    uv = glb.accessor(pr["attributes"]["TEXCOORD_%d" % tc]) if "TEXCOORD_%d" % tc in pr["attributes"] else np.zeros((len(pos), 2))
                    et = self.mats[mi].get("emissiveTexture") if mi >= 0 else None
                    ec = et.get("texCoord", 0) if et else tc       # (the glow can use its own UV set)
                    uve = glb.accessor(pr["attributes"]["TEXCOORD_%d" % ec]) if "TEXCOORD_%d" % ec in pr["attributes"] else uv
                    idx = glb.accessor(pr["indices"]).astype(np.int64).ravel() if "indices" in pr else np.arange(len(pos))
                    idx = idx[: len(idx) // 3 * 3].reshape(-1, 3)
                    wp = pos @ m[:3, :3].T + m[:3, 3]
                    nm = np.linalg.inv(m[:3, :3]).T
                    if np.linalg.det(m[:3, :3]) < 0:   # a mirrored node: glTF turns its winding round
                        idx = idx[:, ::-1]
                    P.append(wp[idx])
                    if nrm is not None:
                        wn = nrm @ nm.T
                        N.append(wn[idx].sum(axis=1))
                    else:
                        N.append(np.zeros((len(idx), 3)))
                    UVC.append(uv[idx].mean(axis=1))
                    UVE.append(uve[idx].mean(axis=1))
                    M.append(np.full(len(idx), mi))
            for c in node.get("children", []):
                walk(c, m)

        for r in roots:
            walk(r, np.eye(4))
        if not P:
            self.n = 0
            return
        self.p = np.concatenate(P)
        self.n = len(self.p)
        g = np.cross(self.p[:, 1] - self.p[:, 0], self.p[:, 2] - self.p[:, 0])
        self.area = np.linalg.norm(g, axis=1) * 0.5
        self.g = g / np.maximum(np.linalg.norm(g, axis=1), 1e-12)[:, None]
        sn = np.concatenate(N)
        self.sn = sn / np.maximum(np.linalg.norm(sn, axis=1), 1e-12)[:, None]
        self.c = self.p.mean(axis=1)
        self.mat = np.concatenate(M)
        uv = np.concatenate(UVC)
        uve = np.concatenate(UVE)
        # what Godot draws there: colour, alpha, whether it's culled from behind
        self.rgb = np.ones((self.n, 3))
        self.emit = np.zeros((self.n, 3))
        self.alpha = np.ones(self.n)
        self.two_sided = np.zeros(self.n, dtype=bool)
        self.mode = np.array(["OPAQUE"] * self.n, dtype=object)
        for mi in np.unique(self.mat):
            sel = self.mat == mi
            if mi < 0:
                continue
            m = self.mats[mi]
            pbr = m.get("pbrMetallicRoughness", {})
            f = np.array(pbr.get("baseColorFactor", [1, 1, 1, 1]), dtype=np.float64)
            col = np.tile(f, (sel.sum(), 1))
            t = pbr.get("baseColorTexture")
            if t is not None:
                px = glb.image(t["index"])
                if px is not None:
                    h, w = px.shape[:2]
                    u = np.mod(uv[sel, 0], 1.0)
                    v = np.mod(uv[sel, 1], 1.0)
                    s = px[np.clip((v * h).astype(int), 0, h - 1), np.clip((u * w).astype(int), 0, w - 1)]
                    col = col * s
            self.rgb[sel] = col[:, :3]
            e = np.array(m.get("emissiveFactor", [0, 0, 0]), dtype=np.float64)
            et = m.get("emissiveTexture")
            if e.max() > 0:
                ecol = np.tile(e, (sel.sum(), 1))
                if et is not None:
                    px = glb.image(et["index"])
                    if px is not None:
                        h, w = px.shape[:2]
                        u = np.mod(uve[sel, 0], 1.0)
                        v = np.mod(uve[sel, 1], 1.0)
                        ecol = ecol * px[np.clip((v * h).astype(int), 0, h - 1), np.clip((u * w).astype(int), 0, w - 1)][:, :3]
                self.emit[sel] = ecol
            mode = m.get("alphaMode", "OPAQUE")
            self.mode[sel] = mode
            if mode == "OPAQUE":
                self.alpha[sel] = 1.0
            elif mode == "MASK":
                self.alpha[sel] = (col[:, 3] >= m.get("alphaCutoff", 0.5)).astype(float)
            else:
                self.alpha[sel] = col[:, 3]
            self.two_sided[sel] = bool(m.get("doubleSided", False))

    def name(self, mi):
        return self.mats[mi].get("name", "?") if mi >= 0 else "(none)"

    def seen_from(self, d):
        """How much of each triangle is seen looking from direction d (a unit
        vector from the car out to the eye): its area across that line, if it
        is drawn from that side (two-sided, or its front face that way) and
        not see-through."""
        dot = self.g @ np.asarray(d, dtype=np.float64)
        drawn = self.two_sided | (dot > 0)
        return self.area * np.abs(dot) * drawn * (self.alpha >= 0.3)


def red(rgb):
    r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
    return (r > 0.25) & (r > 1.7 * g) & (r > 1.7 * b)


def audit(mid):
    path = os.path.join(CARS, mid, mid + ".glb")
    glb = Glb(path)
    j = glb.j
    names = {n.get("name", ""): i for i, n in enumerate(j["nodes"])}
    parts = json.load(open(os.path.join(CARS, mid, "parts.json")))
    flags, notes = [], []
    out = {"id": mid, "flags": flags, "notes": notes}
    if "Body" not in names:
        flags.append("no Body node")
        return out
    body = Tris(glb, [names["Body"]])
    lo, hi = body.p.reshape(-1, 3).min(axis=0), body.p.reshape(-1, 3).max(axis=0)
    length = hi[2] - lo[2]
    out["size"] = [round(float(x), 2) for x in hi - lo]
    out["tris"] = int(body.n)

    # --- the wheels
    rim_ok = 0
    hubs = {}
    for k, cn in enumerate(CORNERS):
        nm = "Wheel_" + cn
        if nm not in names:
            flags.append("%s: no wheel" % cn)
            continue
        node = j["nodes"][names[nm]]
        w = Tris(glb, [names[nm]])
        if w.n == 0:
            flags.append("%s: the wheel is empty" % cn)
            continue
        o = np.array(node.get("translation", [0, 0, 0]))
        side = 1.0 if o[0] > 0 else -1.0
        q = w.p.reshape(-1, 3) - o
        r = np.hypot(q[:, 1], q[:, 2])
        R = float(r.max())
        ext = q.max(axis=0) - q.min(axis=0)
        wid = float(ext[0])
        cy, cz = (q[:, 1].max() + q[:, 1].min()) * 0.5, (q[:, 2].max() + q[:, 2].min()) * 0.5
        info = "%s r %.3f w %.3f" % (cn, R, wid)
        if math.hypot(cy, cz) > 0.012:
            flags.append("%s: the wheel turns %.0f mm off its centre (it wobbles)" % (cn, 1000 * math.hypot(cy, cz)))
        if abs(ext[1] - ext[2]) > 0.04 * 2 * R:
            flags.append("%s: not round about its axle (%.3f tall, %.3f long: tilted)" % (cn, ext[1], ext[2]))
        if wid > 1.4 * R:
            flags.append("%s: %.2f m wide for a %.2f m radius: is its axle x?" % (cn, wid, R))
        pr = float(parts.get("radius", [R] * 4)[k])
        if abs(pr - R) > 0.02:
            flags.append("%s: the model's tyre is %.3f m, the physics' %.3f (floats or sinks)" % (cn, R, pr))
        # the tyre all the way round (24 slices, the outer tenth)
        ang = np.arctan2(q[:, 2], q[:, 1])
        outer = r > 0.88 * R
        bins = np.unique(((ang[outer] + math.pi) / (2 * math.pi) * 24).astype(int) % 24)
        if len(bins) < 24:
            flags.append("%s: the tyre has gaps (%d of 24 slices)" % (cn, len(bins)))
        # the rim, seen from outside: inside the tyre's lip, what's drawn facing out
        cr = np.hypot(w.c[:, 1] - o[1], w.c[:, 2] - o[2])
        inner = cr < 0.62 * R
        seen_out = w.seen_from([side, 0, 0])
        disc = math.pi * (0.62 * R) ** 2
        fill = float(seen_out[inner].sum()) / disc
        seen_in = float(w.seen_from([-side, 0, 0])[inner].sum()) / disc
        info += ", rim seen from outside %.0f %% (from inside %.0f %%)" % (100 * fill, 100 * seen_in)
        if fill < 0.15:
            why = "a see-through or missing rim"
            if seen_in > 0.3:
                why = "the rim is there but faces the car (drawn only from inside)"
            elif float((w.area[inner] * (w.alpha[inner] < 0.3)).sum()) > 0.3 * disc:
                why = "the rim is see-through (alpha)"
            flags.append("%s: no rim from outside (%.0f %% of the wheel's middle): %s" % (cn, 100 * fill, why))
        else:
            rim_ok += 1
        # inside out: the faces on the wheel's outer half that look along the axle should mostly
        # face out (by their winding: the side Godot draws); a mirrored copy whose faces weren't
        # turned round faces in, and one-sided it vanishes from outside (the rim looks hollow)
        ax_out = ((w.c[:, 0] - o[0]) * side > 0) & (np.abs(w.g[:, 0]) > 0.7)
        if w.area[ax_out].sum() > 0:
            facing_out = float(w.area[ax_out & (w.g[:, 0] * side > 0)].sum() / w.area[ax_out].sum())
            info += ", outer faces facing out %.0f %%" % (100 * facing_out)
            one_sided = float(w.area[ax_out & ~w.two_sided].sum() / w.area[ax_out].sum())
            if facing_out < 0.4 and one_sided > 0.5:
                flags.append("%s: inside out (%.0f %% of its outer faces face the car): one-sided, so the rim vanishes from outside" % (cn, 100 * (1 - facing_out)))
            elif facing_out < 0.4:
                info += " (inside out, but two-sided: Godot draws its back faces lit right)"
        # which way the rim faces: its middle (the hub and spokes) sits toward the
        # outer side of the tyre; a wheel mirrored the wrong way has it toward the car
        hub = np.hypot(q[:, 1], q[:, 2]) < 0.5 * R
        if hub.sum() > 20:
            tx = (q[:, 0].max() + q[:, 0].min()) * 0.5
            out_x = float(np.percentile((q[hub, 0] - tx) * side, 95)) / max(0.5 * wid, 1e-3)
            info += ", hub face %+.2f of the half-width out" % out_x
            hubs[cn] = out_x
            if out_x < 0.0:
                flags.append("%s: the rim faces the car (its hub %+.2f of the half-width inward: mirrored the wrong way)" % (cn, out_x))
        # the tyre's colour: dark rubber (light grey or white: its texture didn't come)
        tyre = (cr > 0.8 * R) & (w.alpha > 0.3)
        if tyre.any():
            lum = float(np.average(w.rgb[tyre].mean(axis=1), weights=w.area[tyre]))
            info += ", tyre brightness %.2f" % lum
            if lum > 0.55:
                flags.append("%s: the tyre is light (%.2f): a missing texture?" % (cn, lum))
        # a second wheel left in the Body: a ring of it round this wheel's tyre
        # (chassis bits, brakes, an exhaust reach in there too, but not all round)
        bq = body.c - o
        br = np.hypot(bq[:, 1], bq[:, 2])
        ring = (br > 0.72 * R) & (br < 0.99 * R) & (np.abs(bq[:, 0]) < 0.5 * wid) & (body.alpha > 0.3)
        slices = len(np.unique(((np.arctan2(bq[ring, 2], bq[ring, 1]) + math.pi) / (2 * math.pi) * 24).astype(int) % 24))
        a_in = float(body.area[ring].sum())
        if slices >= 20 and a_in > 0.05:
            top = np.bincount(body.mat[ring] + 1, weights=body.area[ring])
            mm = [body.name(i - 1) for i in np.argsort(top)[::-1][:3] if top[i] > 0]
            flags.append("%s: the Body has a ring inside this tyre (%.2f m2, %d of 24 slices: a wheel left behind that doesn't turn?): %s" % (cn, a_in, slices, mm))
        notes.append(info)
    out["rims"] = rim_ok
    # the two wheels of an axle are mirror images: one whose rim sits much further in
    # than its partner's was copied across without being turned round
    for a, b in (("FL", "FR"), ("RL", "RR")):
        if a in hubs and b in hubs and abs(hubs[a] - hubs[b]) > 0.35:
            lo_c = a if hubs[a] < hubs[b] else b
            flags.append("%s: its rim sits %.2f of the half-width further in than the other side's (turned the wrong way?)" % (lo_c, abs(hubs[a] - hubs[b])))

    # --- the tail lights: red, at the back, seen from behind
    rear = (body.c[:, 2] > hi[2] - 0.14 * length) & (body.c[:, 1] > lo[1] + 0.25)
    from_behind = body.seen_from([0, 0, 1])
    paint = np.array([body.name(m) == "paint" for m in body.mat])   # (the livery's colour, not a lamp)
    glow = body.emit.max(axis=1) > 0.2
    shown = np.where(glow[:, None], body.emit, body.rgb)       # a lamp that glows shows its glow
    redm = rear & red(shown) & ~paint
    red_seen = float(from_behind[redm].sum())
    red_all = float(body.area[redm].sum())
    out["tail_red_m2"] = round(red_seen, 3)
    lamps = sorted({body.name(m) for m in np.unique(body.mat[rear]) if LIGHT.search(body.name(m))})
    info = "tail lights: %.3f m2 of red seen from behind (%.3f m2 red at the back)" % (red_seen, red_all)
    if lamps:
        info += "; light materials at the back: %s" % lamps[:6]
    # lamps glowing white at the back (a glow mask over the whole cluster: the red gone)
    white_glow = rear & (body.emit.min(axis=1) > 0.5) & ~paint
    wg = float(from_behind[white_glow].sum())
    if wg > 0.01:
        flags.append("tail lights: %.3f m2 glows white from behind (a glow mask over red lamps?)" % wg)
    if red_seen < 0.03:
        why = ""
        if red_all > 0.02:
            why = ": the red is there but not drawn from behind (inside-out, or see-through)"
        elif lamps:
            why = ": light materials there, none red (lenses without their colour?)"
        flags.append("tail lights: almost no red from behind (%.3f m2)%s" % (red_seen, why))
    notes.append(info)

    # --- the body's materials
    for mi in np.unique(body.mat):
        sel = body.mat == mi
        a = float(body.area[sel].sum())
        if a < 0.02:
            continue
        nm = body.name(mi)
        m = body.mats[mi] if mi >= 0 else {}
        # wound against its normals: Godot draws it from the side its normals don't face
        dis = float(body.area[sel & ((body.g * body.sn).sum(axis=1) < -0.2)].sum()) / a
        if dis > 0.5 and not m.get("doubleSided"):
            flags.append("material %r (%.2f m2): %.0f %% of it wound against its normals and one-sided (missing from outside, lit wrong)" % (nm, a, 100 * dis))
        mode = m.get("alphaMode", "OPAQUE")
        if mode == "BLEND" and not GLASS.search(nm):
            meanalpha = float(np.average(body.alpha[sel], weights=body.area[sel]))
            notes.append("see-through material %r (%.2f m2, alpha %.2f)" % (nm, a, meanalpha))
            if meanalpha < 0.3 and a > 0.1:
                flags.append("material %r (%.2f m2) is nearly invisible (alpha %.2f) and isn't glass" % (nm, a, meanalpha))
        pbr = m.get("pbrMetallicRoughness", {})
        if "baseColorTexture" not in pbr and nm != "paint" and min(pbr.get("baseColorFactor", [1, 1, 1, 1])[:3]) > 0.97 and a > 0.3 \
                and not re.search(r"chrome|silver|alu|metal|mirror", nm, re.I):
            # (a big one, or one named dark or black, is a texture or colour that didn't come)
            if a > 0.8 or re.search(r"dark|black|trim|plastic|rubber|tyre|tire", nm, re.I):
                flags.append("plain white material %r (%.2f m2): a texture or colour that didn't come?" % (nm, a))
            else:
                notes.append("plain white material %r (%.2f m2): a texture that didn't come?" % (nm, a))
    # faces turned in, seen from outside: the share of the car's outline drawn from each side
    for d, label in (([0, 0, -1], "front"), ([0, 0, 1], "rear"), ([1, 0, 0], "right"), ([-1, 0, 0], "left")):
        dd = np.array(d, dtype=float)
        facing = body.area * np.abs(body.g @ dd)
        towards = ((body.c - (lo + hi) * 0.5) @ dd) > 0
        shell = towards & (body.alpha >= 0.3)
        drawn = float(body.seen_from(d)[shell].sum())
        total = float(facing[shell].sum())
        if total > 0 and drawn / total < 0.3:
            flags.append("the %s half is mostly not drawn from outside (%.0f %%: faces turned in)" % (label, 100 * drawn / total))
    return out


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    jpath = None
    if "--json" in args:
        jpath = args[args.index("--json") + 1]
        args = [a for a in args if a not in ("--json", jpath)]
    ids = args or sorted(os.path.basename(d) for d in glob.glob(os.path.join(CARS, "*")) if os.path.exists(os.path.join(d, os.path.basename(d) + ".glb")))
    res = []
    bad = 0
    for mid in ids:
        try:
            r = audit(mid)
        except Exception as e:
            r = {"id": mid, "flags": ["audit failed: %r" % e], "notes": []}
        res.append(r)
        bad += bool(r["flags"])
        print("== %s%s" % (mid, "" if r["flags"] else "  ok"))
        for f in r["flags"]:
            print("  FLAG %s" % f)
        for n in r["notes"]:
            print("       %s" % n)
        sys.stdout.flush()
    print("[audit] %d of %d models flagged" % (bad, len(res)))
    if jpath:
        json.dump(res, open(jpath, "w"), indent=1)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
