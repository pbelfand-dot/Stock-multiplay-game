# Build the engine loops and one-shots from the owner's two videos.
# Each loop: a stretch whose firing frequency we tracked (fine.py), read at a
# varying speed so its pitch is steady at the target (reading speed = target /
# pitch there: faster where the engine was lower), then cut to a whole number of
# firing cycles and crossfaded end-into-start (no click, no phasing).
import wave, numpy as np
SR = 44100
OUT = "out/"


def load(p):
    w = wave.open(p)
    return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768.0


def save(p, y):
    y = np.clip(y, -1, 1)
    w = wave.open(OUT + p, 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((y * 32767).astype(np.int16).tobytes()); w.close()


def track(p):
    a = np.loadtxt(p)
    return a[:, 0], a[:, 1]


def flatten(x, t0, t1, tt, ff, target):
    out = []
    tau = t0
    while tau < t1:
        f0 = np.interp(tau, tt, ff)
        i = tau * SR; k = int(i); fr = i - k
        out.append(x[k] * (1 - fr) + x[k + 1] * fr)
        tau += (target / f0) / SR
    return np.array(out)


def even(y, win=0.06):
    # take out slow swells in loudness (the pull was getting louder): divide by the
    # smoothed level, so a loop doesn't pulse at its own length
    n = int(win * SR)
    env = np.sqrt(np.convolve(y * y, np.ones(n) / n, mode="same")) + 1e-6
    env = np.convolve(env, np.ones(n) / n, mode="same")
    return y / env * np.mean(env)


def make_loop(y, target, seconds, fade=0.04):
    period = SR / target                       # samples per firing cycle
    L = int(round(round(seconds * target) * period))
    F = int(fade * SR)
    assert len(y) >= L + F, (len(y), L + F)
    z = y[:L].copy()
    w = np.sqrt(np.linspace(0, 1, F))           # equal power
    z[:F] = y[:F] * w + y[L:L + F] * np.sqrt(1 - w * w)
    return z


def rms(y):
    return np.sqrt(np.mean(y * y))


def norm(y, level=0.22):
    y = y - np.mean(y)
    return y * (level / rms(y))


a = load("a.wav")
b = load("b.wav")
loops = {}
# idle: the Fiesta WRC on the start line, anti-lag idle (~2,915 rpm, firing 97 Hz)
tt, ff = track("idle.txt")
y = flatten(b, 0.62, 1.30, tt, ff, 97.2)
loops["engine_idle"] = (make_loop(even(y), 97.2, 0.5), 2915)
# on the throttle, mid: the first pull, 5,400 -> 6,450 rpm, steadied at 5,900
tt, ff = track("pull1.txt")
y = flatten(a, 26.95, 27.70, tt, ff, 196.7)
loops["engine_mid"] = (make_loop(even(y), 196.7, 0.55), 5900)
# on the throttle, high: the same pull, 6,800 -> 7,850 rpm, steadied at 7,350
y = flatten(a, 27.93, 28.62, tt, ff, 245.0)
loops["engine_high"] = (make_loop(even(y), 245.0, 0.5), 7350)
# off the throttle, high: the launch control, anti-lag crackle (~6,350 rpm)
tt, ff = track("lc.txt")
y = flatten(b, 4.30, 5.20, tt, ff, 211.7)
loops["engine_overrun"] = (make_loop(y, 211.7, 0.7), 6350)
for name, (z, rpm) in loops.items():
    save(name + ".wav", norm(z))
    print("%s: %.2f s, %d rpm" % (name, len(z) / SR, rpm))

# the upshift: the cut and the bang as the revs drop (first pull, 28.70 -> 29.15 s)
s = a[int(28.70 * SR):int(29.15 * SR)].copy()
s[:int(0.005 * SR)] *= np.linspace(0, 1, int(0.005 * SR))
s[-int(0.08 * SR):] *= np.linspace(1, 0, int(0.08 * SR))
save("shift.wav", norm(s, 0.25))

# anti-lag bangs: the loudest sharp onsets in the launch control (energy above 2 kHz)
seg0, seg1 = 3.9, 7.8
x = b[int(seg0 * SR):int(seg1 * SR)]
hp = np.diff(x, prepend=0.0)
hp = np.diff(hp, prepend=0.0)                    # crude high-pass (2nd difference)
win = int(0.005 * SR)
env = np.sqrt(np.convolve(hp * hp, np.ones(win) / win, mode="same"))
base = np.convolve(env, np.ones(int(0.2 * SR)) / int(0.2 * SR), mode="same")
ratio = env / (base + 1e-9)
picks = []
order = np.argsort(-ratio)
for k in order:
    if ratio[k] < 2.5 or len(picks) >= 4:
        break
    if all(abs(k - p) > int(0.25 * SR) for p in picks):
        picks.append(k)
for n, k in enumerate(sorted(picks)):
    s0 = max(k - int(0.01 * SR), 0)
    s = x[s0:s0 + int(0.16 * SR)].copy()
    s[:int(0.003 * SR)] *= np.linspace(0, 1, int(0.003 * SR))
    s[-int(0.09 * SR):] *= np.linspace(1, 0, int(0.09 * SR)) ** 2
    save("pop%d.wav" % (n + 1), norm(s, 0.3))
    print("pop%d at %.2f s (x%.1f the surrounding level)" % (n + 1, seg0 + k / SR, ratio[k]))
