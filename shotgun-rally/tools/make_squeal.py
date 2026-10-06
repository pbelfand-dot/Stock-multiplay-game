# The tyre squeal for the asphalt (assets/sfx/squeal.wav): the screech one-shot
# (tools/make_sfx.py) made into a seamless loop, its end crossfaded into its
# start (equal power), so the game can hold it as long as a slide lasts.
# Run from shotgun-rally/: python3 tools/make_squeal.py
import wave
import numpy as np

src = wave.open("assets/sfx/screech.wav")
sr = src.getframerate()
x = np.frombuffer(src.readframes(src.getnframes()), dtype=np.int16).astype(np.float64) / 32768.0
fade = int(0.12 * sr)
body = x[:len(x) - fade].copy()
w = np.sqrt(np.linspace(0.0, 1.0, fade))
body[:fade] = x[:fade] * w + x[len(x) - fade:] * np.sqrt(1.0 - w * w)
body *= 0.22 / np.sqrt(np.mean(body * body))
out = wave.open("assets/sfx/squeal.wav", "wb")
out.setnchannels(1)
out.setsampwidth(2)
out.setframerate(sr)
out.writeframes((np.clip(body, -1, 1) * 32767).astype(np.int16).tobytes())
out.close()
print("squeal.wav: %.2f s" % (len(body) / sr))
