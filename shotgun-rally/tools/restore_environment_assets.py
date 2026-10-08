#!/usr/bin/env python3
"""Restores the owner's environment packages (assets/environment_packages/user_sources/:
whole files and files split into 90 MB parts, listed in ENVIRONMENT_ASSET_MANIFEST.tsv)
and checks each one's size and SHA-256 against the manifest. The same job as
restore_environment_assets.sh (zsh, macOS), on any system with Python 3 and git:

    python3 shotgun-rally/tools/restore_environment_assets.py [--out DIR] [--only TEXT ...] [--list]

  * the parts are read from the working tree when they're there, else straight
    from git (a sparse checkout without the 2 GB of packages still restores)
  * --out: where to (default shotgun-rally/assets/environment_restored/, which git
    and Godot both ignore: a .gdignore is put in it)
  * --only: just the files whose path contains one of these (case-insensitive)
  * a file already restored with the right checksum is left as it is
  * --list: print the manifest (path, size) and restore nothing
The packages themselves are never changed.
"""
import argparse, hashlib, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
PKG = os.path.join(GAME, "assets", "environment_packages")
PKG_GIT = "shotgun-rally/assets/environment_packages"
REPO = os.path.dirname(GAME)


def git(*args, **kw):
    return subprocess.run(["git", "-C", REPO] + list(args), check=True, **kw)


def manifest():
    path = os.path.join(PKG, "ENVIRONMENT_ASSET_MANIFEST.tsv")
    if os.path.exists(path):
        text = open(path, encoding="utf-8").read()
    else:
        text = git("show", "HEAD:%s/ENVIRONMENT_ASSET_MANIFEST.tsv" % PKG_GIT, capture_output=True).stdout.decode()
    rows = []
    for line in text.splitlines()[1:]:
        if line.strip():
            mode, original, size, sha, storage, licence = line.split("\t")
            rows.append({"mode": mode, "path": original, "size": int(size), "sha256": sha, "storage": storage,
                         "licence": licence})
    return rows


_blobs = None


def blobs():
    """Every file under the packages in HEAD: path (relative to the packages) -> blob id."""
    global _blobs
    if _blobs is None:
        out = git("ls-tree", "-r", "-z", "HEAD", "--", PKG_GIT + "/", capture_output=True).stdout.decode()
        _blobs = {}
        for rec in out.split("\0"):
            if rec:
                meta, path = rec.split("\t", 1)
                _blobs[path[len(PKG_GIT) + 1:]] = meta.split()[2]
    return _blobs


def sources(row):
    """The files (in order) that make up this entry: (working-tree path or None, blob id or None)."""
    if row["mode"] == "direct":
        names = [row["storage"]]
    else:
        prefix = row["storage"]
        names = sorted(p for p in blobs() if p.startswith(prefix))
        if not names:          # (not in git: maybe only on disk)
            d = os.path.join(PKG, os.path.dirname(prefix))
            base = os.path.basename(prefix)
            names = sorted(os.path.join(os.path.dirname(prefix), f) for f in os.listdir(d) if f.startswith(base)) if os.path.isdir(d) else []
    out = []
    for n in names:
        disk = os.path.join(PKG, n)
        out.append((disk if os.path.isfile(disk) else None, blobs().get(n)))
    return out


def checksum(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def restore(row, out_dir):
    dest = os.path.join(out_dir, row["path"])
    if os.path.exists(dest) and os.path.getsize(dest) == row["size"] and checksum(dest) == row["sha256"]:
        return "ok (already)"
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    parts = sources(row)
    if not parts:
        raise SystemExit("no parts found for %s" % row["path"])
    tmp = dest + ".part"
    with open(tmp, "wb") as f:
        for disk, blob in parts:
            if disk:
                with open(disk, "rb") as src:
                    for chunk in iter(lambda: src.read(1 << 20), b""):
                        f.write(chunk)
            elif blob:
                f.flush()
                git("cat-file", "blob", blob, stdout=f)
            else:
                raise SystemExit("a part of %s is neither on disk nor in git" % row["path"])
    if os.path.getsize(tmp) != row["size"] or checksum(tmp) != row["sha256"]:
        os.remove(tmp)
        raise SystemExit("verification failed for %s" % row["path"])
    os.replace(tmp, dest)
    return "restored (%d parts)" % len(parts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(GAME, "assets", "environment_restored"))
    ap.add_argument("--only", nargs="*", default=[])
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    rows = manifest()
    if a.only:
        rows = [r for r in rows if any(t.lower() in r["path"].lower() for t in a.only)]
    if a.list:
        for r in rows:
            print("%10d  %-50s %s" % (r["size"], r["path"], r["licence"]))
        return
    os.makedirs(a.out, exist_ok=True)
    open(os.path.join(a.out, ".gdignore"), "a").close()      # (Godot: don't import the raw sources)
    for r in rows:
        print("%-80s %s" % (r["path"], restore(r, a.out)), flush=True)
    print("%d file(s) restored and verified in %s" % (len(rows), a.out))


if __name__ == "__main__":
    main()
