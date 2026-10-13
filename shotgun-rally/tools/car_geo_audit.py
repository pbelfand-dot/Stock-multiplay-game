"""Geometry checks on the car models (assets/models/cars/<id>/<id>.glb), numbers only, read
straight from the GLB (no Blender, no pictures: how the cars whose licences say no AI are checked
too). tools/model_audit.py checks the looks (rims, tail lights, textures); this the shapes:

  * the wheels: each corner's node (where it steers about) against its tyre's middle, left
    against right (the same tyre each side of an axle, one axle), the wheel round its axle
  * the tyres against the body beside them: how far each sticks out (open-wheelers excepted)
  * the wheels' parts left in the Body: round pieces inside a wheel (a rim, a cover, a disc) or on
    its axle (a nut, a cap) neither spin nor steer (glb_patch "body_to_wheels" moves them)
  * loose pieces of the Body far from anything else (floating)
  * z-fighting: the same faces twice in two opaque materials (they flicker; glb_patch
    "drop_dupes"), and faces of two materials side by side in one plane (a note: often fine)
  * mirror-smooth metal over a big area not named chrome or metal

  python3 tools/car_geo_audit.py [model ids ...] [--json out.json]

Prints one block per car, its FLAG lines first.
"""
import glob, json, os, re, sys
import numpy as np
from scipy.spatial import cKDTree
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import glb_patch as gp

ROOT = os.path.join(os.path.dirname(HERE), 'assets', 'models', 'cars')
CORNERS = ['FL', 'FR', 'RL', 'RR']


def local(n):
    if 'matrix' in n:
        return np.array(n['matrix'], float).reshape(4, 4).T
    x, y, z, w = n.get('rotation', [0, 0, 0, 1])
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m = np.eye(4)
    m[:3, :3] = r * np.array(n.get('scale', [1, 1, 1]))
    m[:3, 3] = n.get('translation', [0, 0, 0])
    return m


class Car:
    def __init__(self, mid):
        self.id = mid
        self.j, data = gp.read(os.path.join(ROOT, mid, mid + '.glb'))
        self.data = data[8:]
        self.nodes = self.j['nodes']
        self.parent = {}
        for i, n in enumerate(self.nodes):
            for c in n.get('children', []):
                self.parent[c] = i
        self.mats = [m.get('name', '-') for m in self.j.get('materials', [])]

    def world(self, i):
        m = local(self.nodes[i])
        while i in self.parent:
            i = self.parent[i]
            m = local(self.nodes[i]) @ m
        return m

    def subtree(self, i):
        out = [i]
        for c in self.nodes[i].get('children', []):
            out += self.subtree(c)
        return out

    def find(self, name):
        for i, n in enumerate(self.nodes):
            if n.get('name') == name:
                return i
        return None

    def prims(self, i, frame=None):
        """[(material index, verts (frame's space), tris)] of node i's subtree (frame: a 4x4 to put them in)."""
        out = []
        for k in self.subtree(i):
            if 'mesh' not in self.nodes[k]:
                continue
            M = self.world(k) if frame is None else frame @ self.world(k)
            for p in self.j['meshes'][self.nodes[k]['mesh']]['primitives']:
                v = gp._accessor(self.j, self.data, p['attributes']['POSITION']).astype(float)
                v = (np.c_[v, np.ones(len(v))] @ M.T)[:, :3]
                t = gp._accessor(self.j, self.data, p['indices']).reshape(-1, 3).astype(np.int64) if 'indices' in p \
                    else np.arange(len(v)).reshape(-1, 3)
                out.append((p.get('material'), v, t))
        return out


def islands(v, t, q=4000.0):
    """Connected pieces (faces sharing a corner position): a label per triangle."""
    key = np.round(v * q).astype(np.int64)
    _, vid = np.unique(key, axis=0, return_inverse=True)
    vid = vid.ravel()
    parent = np.arange(vid.max() + 1)

    def f(a):
        r = a
        while parent[r] != r:
            r = parent[r]
        while parent[a] != r:
            parent[a], a = r, parent[a]
        return r
    tt = vid[t]
    for a, b, c in tt:
        ra, rb, rc = f(a), f(b), f(c)
        if ra != rb:
            parent[rb] = ra
        if ra != rc:
            parent[f(rc)] = ra
    return np.array([f(a) for a in tt[:, 0]])


def wheel_check(car, out):
    res = {}
    for k in CORNERS:
        i = car.find('Wheel_' + k)
        if i is None:
            out['flags'].append('no Wheel_%s node' % k)
            continue
        W = car.world(i)
        Wi = np.linalg.inv(W)
        pts = np.vstack([v for _, v, _ in car.prims(i, Wi)])        # the wheel in its own node's frame
        r = np.hypot(pts[:, 1], pts[:, 2])
        R = r.max()
        tread = pts[r > R * 0.93]                                   # the tread: the outermost ring
        lo, hi = pts.min(0), pts.max(0)
        res[k] = dict(at=W[:3, 3], R=R, tread=(tread[:, 0].min(), tread[:, 0].max()), box=(lo, hi),
                      yz=((lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2))
    if len(res) < 4:
        return res
    cx = (res['FL']['at'][0] + res['FR']['at'][0]) / 2
    for a, b in (('FL', 'FR'), ('RL', 'RR')):
        A, B = res[a], res[b]
        ta = A['at'][0] + np.array(A['tread'])     # the tread across, in the model
        tb = B['at'][0] + np.array(B['tread'])
        mid_a, mid_b = ta.mean(), tb.mean()
        out['notes'].append('%s/%s: nodes x %.3f / %.3f, treads x %.3f..%.3f / %.3f..%.3f (widths %.3f / %.3f), radius %.3f / %.3f, z %.3f / %.3f' % (
            a, b, A['at'][0], B['at'][0], ta[0], ta[1], tb[0], tb[1], ta[1] - ta[0], tb[1] - tb[0], A['R'], B['R'], A['at'][2], B['at'][2]))
        for nm, W_, mid in ((a, A, mid_a), (b, B, mid_b)):
            off = mid - W_['at'][0]
            if abs(off) > 0.025:
                out['flags'].append('%s: the tyre\'s middle is %.3f m %s of its node (it steers about a point off its middle)' % (
                    nm, abs(off), 'outboard' if (off > 0) == (W_['at'][0] > cx) else 'inboard'))
            yz = W_['yz']
            if max(abs(yz[0]), abs(yz[1])) > 0.01:
                out['flags'].append('%s: the wheel is %.3f m off its axle (it wobbles as it turns)' % (nm, max(abs(yz[0]), abs(yz[1]))))
        if abs((ta[1] - ta[0]) - (tb[1] - tb[0])) > 0.03:
            out['flags'].append('%s/%s: tread widths differ, %.3f against %.3f m' % (a, b, ta[1] - ta[0], tb[1] - tb[0]))
        if abs(A['R'] - B['R']) > 0.01:
            out['flags'].append('%s/%s: tyre radius differs, %.3f against %.3f m' % (a, b, A['R'], B['R']))
        if abs(A['at'][2] - B['at'][2]) > 0.01:
            out['flags'].append('%s/%s: not on one axle, z %.3f against %.3f' % (a, b, A['at'][2], B['at'][2]))
    return res


def body_check(car, out, wheels):
    i = car.find('Body')
    if i is None:
        out['flags'].append('no Body node')
        return
    prims = car.prims(i)
    V = np.vstack([v for _, v, _ in prims])
    out['size'] = [round(float(x), 3) for x in V.max(0) - V.min(0)]
    cx = (V.max(0)[0] + V.min(0)[0]) / 2
    # the tyres against the body beside them: the body's widest point within the wheel's length, above the hub
    for k, w in wheels.items():
        at = w['at']
        side = 1 if at[0] > cx else -1
        tyre_out = at[0] + (w['tread'][1] if side > 0 else w['tread'][0])
        sel = (np.abs(V[:, 2] - at[2]) < w['R'] * 0.9) & (V[:, 1] > at[1]) & (V[:, 1] < at[1] + w['R'] * 1.6) & (V[:, 0] * side > 0)
        if sel.sum() < 10:
            continue
        body_out = V[sel, 0].max() if side > 0 else V[sel, 0].min()
        poke = (tyre_out - body_out) * side
        w['poke'] = poke
        if poke > 0.025 and not out.get('open_wheel'):
            out['flags'].append('%s: the tyre sticks out %.3f m past the body beside it' % (k, poke))
    # stray pieces: loose bits far from the rest
    tri_c, tri_p, tri_a = [], [], []
    allv, allt, base = [], [], 0
    for mi, v, t in prims:
        allv.append(v)
        allt.append(t + base)
        base += len(v)
    v = np.vstack(allv)
    t = np.vstack(allt)
    lab = islands(v, t)
    uniq, inv, counts = np.unique(lab, return_inverse=True, return_counts=True)
    big = uniq[np.argmax(counts)]
    tree_v = v[np.unique(t[lab == big])]
    # every piece's vertices against everything else: the gap to the nearest other piece
    piece_v = {}
    for u in uniq:
        piece_v[u] = np.unique(t[lab == u].ravel())
    tree = cKDTree(v)
    far = []
    owner = np.full(len(v), -1)
    for u in uniq:
        owner[piece_v[u]] = u
    for u in uniq:
        idx = piece_v[u]
        if len(idx) > 3000 or u == big:
            continue
        pv = v[idx]
        kk = min(len(idx) + 24, len(v))
        d, jj = tree.query(pv, k=kk)
        other = owner[jj] != u
        dd = np.where(other, d, np.inf)
        gap = float(dd.min())
        if not np.isfinite(gap):
            gap = 9.0
        if gap > 0.08:
            size = float(np.linalg.norm(pv.max(0) - pv.min(0)))
            far.append((gap, size, pv.mean(0)))
    far.sort(key=lambda f: -f[0])
    for gap, size, c in far[:6]:
        out['flags' if gap > 0.15 and size > 0.03 else 'notes'].append(
            'a loose piece %.2f m across, %s from anything else, at (%.2f, %.2f, %.2f)' % (size, ('%.2f m' % gap) if gap < 9 else 'far', c[0], c[1], c[2]))
    # z-fighting: faces of two materials in one plane overlapping
    cs, ns, ds, ms, ar = [], [], [], [], []
    for mi, vv, tt in prims:
        a, b, c = vv[tt[:, 0]], vv[tt[:, 1]], vv[tt[:, 2]]
        n = np.cross(b - a, c - a)
        area = np.linalg.norm(n, axis=1) * 0.5
        ok = area > 1e-6
        n = n[ok] / (2 * area[ok])[:, None]
        cen = (a[ok] + b[ok] + c[ok]) / 3
        cs.append(cen); ns.append(n); ds.append((n * cen).sum(1)); ms.append(np.full(ok.sum(), -1 if mi is None else mi)); ar.append(area[ok])
    C, N, D, M, A = map(np.concatenate, (cs, ns, ds, ms, ar))
    tree = cKDTree(C)
    pairs = tree.query_pairs(0.01, output_type='ndarray')
    if len(pairs):
        a_, b_ = pairs[:, 0], pairs[:, 1]
        same_plane = ((N[a_] * N[b_]).sum(1) > 0.995) & (np.abs((N[a_] * (C[b_] - C[a_])).sum(1)) < 0.0004)
        diff = M[a_] != M[b_]
        blend = np.array([(car.j['materials'][int(m)].get('alphaMode', 'OPAQUE') == 'BLEND') if m >= 0 else False for m in range(-1, len(car.mats))])
        opaque = ~blend[M[a_] + 1] & ~blend[M[b_] + 1]
        same = np.linalg.norm(C[a_] - C[b_], axis=1) < 0.0005
        for label, sel, lim in (('the same faces twice', same_plane & diff & opaque & same, 0.005),
                                ('coplanar, side by side or overlapping', same_plane & diff & opaque & ~same, 1e9)):
            fight = {}
            for p, q in zip(a_[sel], b_[sel]):
                key = tuple(sorted((int(M[p]), int(M[q]))))
                fight[key] = fight.get(key, 0.0) + min(A[p], A[q])
            for (m1, m2), area in sorted(fight.items(), key=lambda kv: -kv[1])[:4]:
                if area < 0.003:
                    continue
                msg = 'z-fighting (%s): %s against %s, %.4f m2' % (label, car.mats[m1] if m1 >= 0 else '-', car.mats[m2] if m2 >= 0 else '-', area)
                out['flags' if area > lim else 'notes'].append(msg)
        dup = same_plane & ~diff & same
        if dup.sum():
            out['notes'].append('%d faces doubled in the same material (same place)' % dup.sum())
    # mirror metal outside
    for mi in set(int(m) for m in M if m >= 0):
        mat = car.j['materials'][mi]
        pbr = mat.get('pbrMetallicRoughness', {})
        met, rough = pbr.get('metallicFactor', 1.0), pbr.get('roughnessFactor', 1.0)
        if met >= 0.9 and rough <= 0.15 and 'metallicRoughnessTexture' not in pbr:
            area = float(A[M == mi].sum())
            n = car.mats[mi].lower()
            if area > 0.5 and not re.search(r'chrome|metal|alu|steel|silver|exhaust|mirror|rim|wheel', n):
                out['notes'].append("mirror-smooth metal '%s' (%.2f m2, metallic %.2f, roughness %.2f)" % (car.mats[mi], area, met, rough))


def drum_check(car, out, wheels):
    """Body pieces inside a wheel (its tyre's radius, across its tread): round ones or on the axle are
    the wheel's (a rim, a cover, a disc, a nut) left behind: they neither spin nor steer."""
    i = car.find('Body')
    if i is None or len(wheels) < 4:
        return
    prims = [(mi, v, t) for mi, v, t in car.prims(i)]
    left, small = [], 0
    for mi, v, t in prims:
        if len(t) == 0:
            continue
        lab = islands(v, t)
        order = np.argsort(lab, kind='stable')
        for grp in np.split(order, np.flatnonzero(np.diff(lab[order])) + 1):
            q = v[np.unique(t[grp])]
            for k, w in wheels.items():
                d = q - w['at']
                rr = np.hypot(d[:, 1], d[:, 2])
                if rr.max() < w['R'] + 0.02 and d[:, 0].min() > w['tread'][0] - 0.03 and d[:, 0].max() < w['tread'][1] + 0.03:
                    sy, sz = np.ptp(q[:, 1]), np.ptp(q[:, 2])
                    if (min(sy, sz) >= 0.15 and abs(sy - sz) < 0.15 * max(sy, sz)) or rr.max() < 0.06:
                        left.append('%s: %s, %.2f m across, %d faces' % (k, car.mats[mi] if mi is not None else '-', max(sy, sz), len(grp)))
                    elif len(grp) >= 20:
                        small += 1
                    break
    for msg in left[:8]:
        out['flags'].append('a wheel\'s part left in the Body (it neither spins nor steers): ' + msg)
    if small:
        out['notes'].append('%d other pieces of the Body inside the wheels (brakes, uprights: they steer with nothing)' % small)


def run(mid):
    out = {'id': mid, 'flags': [], 'notes': []}
    try:
        car = Car(mid)
        pj = os.path.join(ROOT, mid, 'parts.json')
        out['open_wheel'] = os.path.exists(pj) and json.load(open(pj)).get('cockpit', {}).get('seats', 2) == 1
        wheels = wheel_check(car, out)
        body_check(car, out, wheels)
        drum_check(car, out, wheels)
        out['poke'] = {k: round(float(w.get('poke', 0.0)), 3) for k, w in wheels.items()}
    except Exception as e:
        out['flags'].append('audit failed: %r' % e)
    return out


if __name__ == '__main__':
    args = sys.argv[1:]
    jpath = None
    if '--json' in args:
        jpath = args[args.index('--json') + 1]
        args = [a for a in args if a not in ('--json', jpath)]
    ids = args or sorted(os.path.basename(p) for p in glob.glob(ROOT + '/*') if os.path.exists(os.path.join(p, os.path.basename(p) + '.glb')))
    res = []
    for mid in ids:
        o = run(mid)
        res.append(o)
        print('== %s' % mid)
        for f in o['flags']:
            print('  FLAG ' + f)
        for n in o['notes']:
            print('       ' + n)
        sys.stdout.flush()
    if jpath:
        json.dump(res, open(jpath, 'w'), indent=1, default=float)
