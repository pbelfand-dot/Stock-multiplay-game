#!/usr/bin/env python3
"""Synthesizes every sound effect in assets/sfx (no samples, no licensing).

Run: python3 tools/make_sfx.py      (needs numpy)
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")


def t(dur):
    return np.arange(int(SR * dur)) / SR


def env(x, attack=0.005, decay=0.3):
    n = len(x)
    e = np.ones(n)
    a = max(1, int(SR * attack))
    e[:a] = np.linspace(0, 1, a)
    e *= np.exp(-np.arange(n) / (SR * decay))
    return x * e


def bell_strike(f, dur=1.4, decay=0.5):
    tt = t(dur)
    partials = [(1.0, 1.0), (2.76, 0.5), (5.4, 0.25), (8.93, 0.12), (0.5, 0.3)]
    s = sum(a * np.sin(2 * np.pi * f * m * tt) * np.exp(-tt * (1 + m) / (decay * 3)) for m, a in partials)
    return env(s, 0.001, decay * 2)


def mix(parts, dur):
    out = np.zeros(int(SR * dur))
    for start, sig in parts:
        i = int(SR * start)
        j = min(len(out), i + len(sig))
        out[i:j] += sig[: j - i]
    return out


def square(f, tt):
    return np.sign(np.sin(2 * np.pi * f * tt))


def saw(f, tt):
    return 2 * ((f * tt) % 1.0) - 1


def noise(dur):
    return np.random.default_rng(3).uniform(-1, 1, int(SR * dur))


def lowpass(x, a=0.1):
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc)
        y[i] = acc
    return y


def save(name, x, gain=0.8):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) or 1.0
    x = (x / peak * gain * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(x.tobytes())
    print("wrote", name)


def main():
    # Opening bell: DING DING DING
    save("bell", mix([(0.0, bell_strike(880)), (0.45, bell_strike(880)), (0.9, bell_strike(880, 2.0, 0.8))], 3.0))

    # Cha-ching: register rattle + two bright dings
    rattle = env(lowpass(noise(0.12), 0.4), 0.001, 0.04)
    save("cash", mix([(0.0, rattle), (0.08, bell_strike(2093, 0.6, 0.15)), (0.16, bell_strike(2637, 0.9, 0.25))], 1.1))

    # Sad trombone wah-wah-wah-waaah
    parts = []
    for i, f in enumerate([392, 370, 349]):
        tt = t(0.42)
        parts.append((i * 0.45, env(lowpass(saw(f, tt), 0.08), 0.02, 0.35)))
    tt = t(1.1)
    vib = 330 + 8 * np.sin(2 * np.pi * 6 * tt)
    last = lowpass(2 * ((np.cumsum(vib) / SR) % 1.0) - 1, 0.08)
    parts.append((1.35, env(last, 0.02, 0.8)))
    save("lose", mix(parts, 2.5), 0.6)

    # Police siren (loopable 2s two-tone sweep)
    tt = t(2.0)
    f = 800 + 250 * np.sign(np.sin(2 * np.pi * 0.5 * tt))
    f = lowpass(f, 0.0015)
    ph = np.cumsum(f) / SR
    siren = 0.6 * np.sin(2 * np.pi * ph) + 0.4 * np.sign(np.sin(2 * np.pi * ph)) * 0.3
    save("siren", siren, 0.5)

    # Slot reel tick
    save("tick", env(np.sin(2 * np.pi * 1800 * t(0.03)) + noise(0.03) * 0.3, 0.0005, 0.008), 0.5)

    # Jackpot arpeggio
    notes = [523, 659, 784, 1047, 784, 1047, 1319, 1568]
    save("jackpot", mix([(i * 0.09, env(square(n, t(0.2)) * 0.5, 0.002, 0.12)) for i, n in enumerate(notes)]
                        + [(0.8, bell_strike(2093, 1.0, 0.4))], 2.0), 0.55)

    # News sting: brassy three notes
    sting = [(0.0, 294, 0.18), (0.2, 294, 0.18), (0.4, 440, 0.7)]
    save("news", mix([(s, env(lowpass(saw(f, t(d)) + 0.5 * saw(f * 2, t(d)), 0.12), 0.01, d * 0.8)) for s, f, d in sting], 1.3), 0.6)

    # Camera flash (mugshot)
    whine = np.sin(2 * np.pi * np.linspace(3000, 6000, int(SR * 0.4)).cumsum() / SR) * np.linspace(0, 0.3, int(SR * 0.4))
    pop = env(noise(0.15), 0.0005, 0.03)
    save("flash", mix([(0.0, whine), (0.4, pop)], 0.8), 0.7)

    # Coin clink (buy / small win)
    save("coin", mix([(0.0, bell_strike(3136, 0.4, 0.08)), (0.06, bell_strike(3951, 0.5, 0.1))], 0.6), 0.6)

    # Liquidation boom
    tt = t(1.2)
    boom = np.sin(2 * np.pi * np.cumsum(np.linspace(120, 35, len(tt))) / SR) * np.exp(-tt * 3)
    save("liquidated", boom + env(lowpass(noise(1.2), 0.05), 0.001, 0.3) * 0.6, 0.8)

    # Swish (basketball through the net)
    n = noise(0.35)
    save("swish", env(lowpass(n, 0.3) - lowpass(n, 0.05), 0.02, 0.12), 0.6)

    # Heartbeat (blood pressure): lub-dub, low thumps
    def thump(f, d):
        tt_ = t(d)
        return env(np.sin(2 * np.pi * np.cumsum(np.linspace(f, f * 0.55, len(tt_))) / SR), 0.002, d * 0.35)
    save("heartbeat", mix([(0.0, thump(70, 0.18)), (0.22, thump(58, 0.2))], 0.6), 0.9)

    # The chest-thump hum (Wall Street lunch warm-up): two chest thumps + a
    # low nasal "mm-MM mm-mm" melody
    def hum(f, d):
        tt_ = t(d)
        vib = 1 + 0.01 * np.sin(2 * np.pi * 5.5 * tt_)
        ph = np.cumsum(f * vib) / SR
        s_ = sum(a * np.sin(2 * np.pi * k * ph) for k, a in ((1, 1.0), (2, 0.5), (3, 0.3), (4, 0.15)))
        e = np.minimum(1, tt_ / 0.04) * np.minimum(1, (d - tt_) / 0.06)
        return lowpass(s_ * e, 0.08)
    parts = [(0.0, thump(80, 0.16)), (0.28, thump(80, 0.16))]
    tune = [(0.55, 147, 0.26), (0.85, 175, 0.4), (1.3, 147, 0.26), (1.6, 131, 0.5)]
    parts += [(st, hum(f, d) * 0.5) for st, f, d in tune]
    parts += [(2.2, thump(80, 0.16)), (2.48, thump(80, 0.16))]
    save("hum", mix(parts, 2.8), 0.8)

    # Whoosh (dive)
    n = noise(0.5)
    sweep = np.linspace(0.02, 0.4, len(n))
    y = np.zeros_like(n)
    acc = 0.0
    for i, v in enumerate(n):
        acc += sweep[i] * (v - acc)
        y[i] = acc
    save("whoosh", env(y, 0.1, 0.2), 0.6)

    # UI click
    save("click", env(square(1200, t(0.02)), 0.0005, 0.006), 0.35)

    # Money-gun brrrt
    tt = t(0.25)
    save("brrt", env(square(90, tt) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 30 * tt))) + noise(0.25) * 0.2, 0.002, 0.2), 0.45)


if __name__ == "__main__":
    main()
