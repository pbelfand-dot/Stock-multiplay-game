#!/usr/bin/env python3
"""The cars' textures (the images Godot extracts from each car's GLB into
assets/models/cars/<id>/) imported as Basis Universal: about the download size of
the lossless default, but compressed in video memory (a 2048 px texture: ~2.8 MB
instead of ~22 MB uncompressed), which matters with several cars on screen.

    python3 tools/car_textures.py [car id ...]     # all cars when none given

Run it after a car's first import (the .import files exist then), then import again.
"""
import os, re, sys

CARS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "models", "cars")
MODE = 4            # ResourceImporterTexture compress/mode: Basis Universal


def main():
    ids = sys.argv[1:] or sorted(os.listdir(CARS))
    n = 0
    for cid in ids:
        d = os.path.join(CARS, cid)
        if not os.path.isdir(d):
            continue
        for f in os.listdir(d):
            if not f.endswith(".import") or f.endswith(".glb.import"):
                continue
            p = os.path.join(d, f)
            s = open(p, encoding="utf-8").read()
            if 'importer="texture"' not in s:
                continue
            new = re.sub(r"^compress/mode=\d+", "compress/mode=%d" % MODE, s, flags=re.M)
            new = re.sub(r"^detect_3d/compress_to=\d+", "detect_3d/compress_to=0", new, flags=re.M)
            if new != s:
                open(p, "w", encoding="utf-8").write(new)
                n += 1
    print("%d texture import(s) set to Basis Universal" % n)


if __name__ == "__main__":
    main()
