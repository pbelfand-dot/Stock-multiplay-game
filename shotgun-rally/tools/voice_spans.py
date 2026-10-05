#!/usr/bin/env python3
"""Finds which part of each co-driver clip is the word. Some of the first clips
carry a scrap of another word before the real one ("finally... right",
"and... 70"), a click after it, or the word twice, with ~1 s of silence
between. This splits each clip into its sounds (loud stretches more than
0.25 s apart) and transcribes each one on its own with speech recognition
(faster-whisper), writing assets/voice/fraser/spans.json:

    {clip: [{"start": s, "end": s, "text": "..."}, ...]}

tools/trim_voice.py then keeps the sound(s) that say the clip's word. Runs in
GitHub Actions (.github/workflows/shotgun-rally-voice-spans.yml): the Claude
sandbox can't download the speech model. Needs ffmpeg.
"""
import glob
import json
import os
import subprocess

import numpy as np
from faster_whisper import WhisperModel

DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "voice", "fraser")
RATE = 16000
FRAME = 160          # 10 ms
GAP = 25             # 250 ms of quiet splits two sounds


def sounds(a):
    n = len(a) // FRAME
    rms = np.sqrt(np.mean(a[:n * FRAME].reshape(n, FRAME) ** 2, axis=1))
    loud = rms > rms.max() * 0.06
    runs = []
    for i, on in enumerate(loud):
        if not on:
            continue
        if runs and i - runs[-1][1] <= GAP:
            runs[-1][1] = i
        else:
            runs.append([i, i])
    return [(r[0] * FRAME / RATE, (r[1] + 1) * FRAME / RATE, float(np.sum(rms[r[0]:r[1] + 1] ** 2))) for r in runs]


def main() -> None:
    model = WhisperModel("small.en", device="cpu", compute_type="int8")
    out = {}
    for path in sorted(glob.glob(os.path.join(DIR, "*.mp3"))):
        name = os.path.basename(path)[:-4]
        raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(RATE),
                              "-f", "f32le", "-"], capture_output=True, check=True).stdout
        a = np.frombuffer(raw, dtype=np.float32)
        parts = []
        for s, e, energy in sounds(a):
            seg = a[max(0, int((s - 0.05) * RATE)):int((e + 0.05) * RATE)]
            pad = np.zeros(int(0.3 * RATE), dtype=np.float32)
            segs, _ = model.transcribe(np.concatenate([pad, seg, pad]), language="en", beam_size=5,
                                       vad_filter=False, condition_on_previous_text=False)
            text = "".join(x.text for x in segs).strip()
            parts.append({"start": round(s, 3), "end": round(e, 3), "energy": round(energy, 4), "text": text})
        out[name] = parts
        print("%-16s %s" % (name, " | ".join("%.2f-%.2f %r" % (p["start"], p["end"], p["text"]) for p in parts)))
    json.dump(out, open(os.path.join(DIR, "spans.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
