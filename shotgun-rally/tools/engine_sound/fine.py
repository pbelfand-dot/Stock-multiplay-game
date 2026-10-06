# Fine firing-frequency track in a window, following the line continuously (each
# frame searches +-6 % around the last value), seeded from a known start.
import sys, wave, numpy as np
src, t0, t1, seed = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
w = wave.open(src); sr = w.getframerate()
x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32)/32768.0
N = int(0.08*sr); nfft = 1 << 16; f = np.fft.rfftfreq(nfft, 1/sr)
cur = seed
for i in range(int(t0*sr), int(t1*sr)-N, int(0.02*sr)):
    seg = x[i:i+N]*np.hanning(N); m = np.abs(np.fft.rfft(seg, nfft))
    best, bf = -1, cur
    for c in np.linspace(cur*0.94, cur*1.06, 121):
        s = 0.0
        for h in (1, 2, 3, 4):
            k = int(round(c*h*nfft/sr)); s += np.log(m[k-1:k+2].max()+1e-6) * (1.0 if h < 3 else 0.7)
        if s > best: best, bf = s, c
    cur = bf
    print("%.3f %.1f %.0f" % (i/sr + 0.04, cur, cur*30))
