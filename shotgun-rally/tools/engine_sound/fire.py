# Firing frequency per frame: the strongest harmonic series whose base is the
# loudest line between 70 and 350 Hz (as in the launch control and idle checks),
# refined so 2x, 3x, 4x line up. rpm (4-cylinder) = 30 x firing frequency.
import sys, wave, numpy as np
w = wave.open(sys.argv[1]); sr = w.getframerate()
x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32)/32768.0
hop = float(sys.argv[2]) if len(sys.argv) > 2 else 0.05
N = int(0.15*sr); nfft = 1 << 15; f = np.fft.rfftfreq(nfft, 1/sr)
lo, hi = np.searchsorted(f, 70), np.searchsorted(f, 350)
for i in range(0, len(x)-N, int(hop*sr)):
    seg = x[i:i+N]*np.hanning(N)
    m = np.abs(np.fft.rfft(seg, nfft))
    lvl = 20*np.log10(np.sqrt(np.mean(seg**2))+1e-9)
    if lvl < -45: print("%.2f - - %.0f" % (i/sr, lvl)); continue
    k0 = lo + np.argmax(m[lo:hi]); f0 = f[k0]
    # refine with the 2nd..4th harmonics (each nearest peak / its number)
    est = [f0]
    for h in (2, 3, 4):
        k = int(round(f0*h*nfft/sr)); r = int(0.04*f0*h*nfft/sr)+2
        kk = k-r + np.argmax(m[k-r:k+r+1]); est.append(f[kk]/h)
    fr = float(np.median(est))
    print("%.2f %.1f %.0f %.0f" % (i/sr, fr, fr*30, lvl))
