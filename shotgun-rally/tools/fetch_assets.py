#!/usr/bin/env python3
"""Downloads files listed in assets/incoming.json into the project, then empties
the list. For files the Claude sandbox can't reach itself (Higgsfield results):
runs in GitHub Actions (.github/workflows/shotgun-rally-assets.yml), or locally.

    {"files": {"assets/models/car.glb": "https://...", "docs/reference/models/car.jpg": "https://..."}}

Paths are relative to shotgun-rally/. A .jpg target from a .png source is
converted (and shrunk to 1024 px) so reference images stay small.

    python3 tools/fetch_assets.py
"""
import io
import json
import os
import urllib.request

ROOT = os.path.join(os.path.dirname(__file__), "..")
LIST = os.path.join(ROOT, "assets", "incoming.json")


def main() -> None:
    data = json.load(open(LIST))
    files = data.get("files", {})
    if not files:
        print("Nothing to fetch.")
        return
    for rel, url in files.items():
        dest = os.path.normpath(os.path.join(ROOT, rel))
        if not dest.startswith(os.path.normpath(ROOT) + os.sep):
            raise SystemExit("refusing to write outside the project: " + rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        raw = urllib.request.urlopen(url, timeout=120).read()
        if dest.endswith(".jpg") and not url.split("?")[0].lower().endswith((".jpg", ".jpeg")):
            from PIL import Image
            im = Image.open(io.BytesIO(raw)).convert("RGB")
            im.thumbnail((1024, 1024))
            im.save(dest, quality=85)
        else:
            open(dest, "wb").write(raw)
        print("saved", rel, os.path.getsize(dest), "bytes")
    data["files"] = {}
    json.dump(data, open(LIST, "w"), indent=2)
    open(LIST, "a").write("\n")


if __name__ == "__main__":
    main()
