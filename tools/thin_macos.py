#!/usr/bin/env python3
"""Split Godot's universal macOS export into Apple Silicon / Intel zips.

Godot only ships a universal (fat) macOS template, which is ~2x the size.
This extracts one architecture slice (like `lipo -thin`); each slice keeps
its own ad-hoc code signature, so the app still launches.

Usage: python3 tools/thin_macos.py build/macos/Bagholders.zip build/
"""
import os
import struct
import sys
import zipfile

ARCHES = {"AppleSilicon": 0x0100000C, "Intel": 0x01000007}


def main(src: str, out_dir: str) -> None:
    z = zipfile.ZipFile(src)
    exe = next(n for n in z.namelist() if "/Contents/MacOS/" in n and not n.endswith("/"))
    data = z.read(exe)
    magic, n = struct.unpack(">II", data[:8])
    assert magic in (0xCAFEBABE, 0xCAFEBABF), "not a universal binary"
    slices = {}
    for k in range(n):
        if magic == 0xCAFEBABE:
            ct, _, off, size, _ = struct.unpack(">iiIII", data[8 + k * 20: 28 + k * 20])
        else:
            ct, _, off, size, _, _ = struct.unpack(">iiQQII", data[8 + k * 32: 40 + k * 32])
        slices[ct & 0xFFFFFFFF] = data[off: off + size]
    for label, cpu in ARCHES.items():
        # the Apple Silicon one is THE download: just "Bagholders.zip"
        out = os.path.join(out_dir, "Bagholders.zip" if label == "AppleSilicon" else f"Bagholders-{label}.zip")
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zo:
            for info in z.infolist():
                body = slices[cpu] if info.filename == exe else z.read(info.filename)
                zi = zipfile.ZipInfo(info.filename, date_time=info.date_time)
                zi.external_attr = info.external_attr   # keep the executable bit
                zi.create_system = info.create_system
                zi.compress_type = zipfile.ZIP_DEFLATED
                zo.writestr(zi, body)
        print(f"{out}: {os.path.getsize(out) / 1048576:.1f} MiB")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
