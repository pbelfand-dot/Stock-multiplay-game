#!/usr/bin/env python3
"""SHOTGUN RALLY sound effects, synthesized (no samples): plain Python, no numpy.

Run:  python3 tools/make_sfx.py      -> assets/sfx/{gravel,splat,wiper,thud}.wav
engine / screech / crash / swish / tick / bell / click come from BAGHOLDERS' own
tools/make_sfx.py (also synthesized), copied as-is.
"""
import math
import os
import random
import struct
import wave

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
random.seed(7)


def save(name, xs, gain=0.8):
    peak = max(1e-6, max(abs(v) for v in xs))
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(v / peak * gain * 32767)) for v in xs))
    print("saved", name)


def lowpass(xs, a):
    out, y = [], 0.0
    for v in xs:
        y += a * (v - y)
        out.append(y)
    return out


def gravel():
    """A seamless 2 s loop of tyres on loose stones: crunchy grains over a rumble."""
    n = SR * 2
    rumble = lowpass([random.uniform(-1, 1) for _ in range(n)], 0.02)
    grains = [0.0] * n
    for _ in range(900):                       # little stones popping under the tread
        at = random.randrange(n)
        amp = random.uniform(0.2, 1.0)
        f = random.uniform(1800, 4200)
        for k in range(int(SR * 0.006)):
            i = (at + k) % n                     # wraps: the loop has no seam
            grains[i] += amp * math.sin(2 * math.pi * f * k / SR) * math.exp(-k / (SR * 0.0015))
    xs = [rumble[i] * 3.0 + grains[i] * 0.35 for i in range(n)]
    # crossfade the first 50 ms with the tail so the lowpass start doesn't click
    m = int(SR * 0.05)
    for i in range(m):
        t = i / m
        xs[i] = xs[i] * t + xs[n - m + i] * (1 - t)
    save("gravel", xs, 0.7)


def splat():
    """Mud slapping the windshield: a wet thump and a spray of droplets."""
    n = int(SR * 0.45)
    xs = []
    for i in range(n):
        t = i / SR
        thump = math.sin(2 * math.pi * (90 - 60 * t) * t) * math.exp(-t * 18)
        spray = random.uniform(-1, 1) * math.exp(-t * 9) * 0.5
        xs.append(thump + spray)
    save("splat", lowpass(xs, 0.35), 0.8)


def wiper():
    """One wiper stroke: rubber squeak over the motor."""
    n = int(SR * 0.42)
    xs = []
    for i in range(n):
        t = i / SR
        env = math.sin(math.pi * t / 0.42)
        squeak = math.sin(2 * math.pi * (620 + 140 * math.sin(t * 30)) * t) * 0.25
        motor = math.sin(2 * math.pi * 110 * t) * 0.2 + random.uniform(-1, 1) * 0.15
        xs.append((squeak + motor) * env)
    save("wiper", lowpass(xs, 0.5), 0.6)


def thud():
    """A landing / big bump: low body thump."""
    n = int(SR * 0.35)
    xs = [math.sin(2 * math.pi * (70 - 40 * (i / SR)) * i / SR) * math.exp(-(i / SR) * 14)
          + random.uniform(-1, 1) * math.exp(-(i / SR) * 30) * 0.3 for i in range(n)]
    save("thud", lowpass(xs, 0.3), 0.9)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    gravel()
    splat()
    wiper()
    thud()
