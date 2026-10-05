#!/usr/bin/env python3
"""Finds where the word actually is in each co-driver clip, with speech
recognition (faster-whisper, word timestamps), and writes
assets/voice/fraser/spans.json: {clip: {"text": ..., "words": [[word, start, end], ...]}}.
tools/trim_voice.py then cuts each clip down to its word. Runs in GitHub Actions
(.github/workflows/shotgun-rally-voice-spans.yml): the Claude sandbox can't
download the speech model.
"""
import glob
import json
import os
import subprocess

import numpy as np
from faster_whisper import WhisperModel

DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "voice", "fraser")


def main() -> None:
    model = WhisperModel("small.en", device="cpu", compute_type="int8")
    out = {}
    for path in sorted(glob.glob(os.path.join(DIR, "*.mp3"))):
        name = os.path.basename(path)[:-4]
        # decode with ffmpeg ourselves (faster-whisper's PyAV call breaks with some av versions)
        raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", "16000",
                              "-f", "f32le", "-"], capture_output=True, check=True).stdout
        audio = np.frombuffer(raw, dtype=np.float32)
        segs, _ = model.transcribe(audio, word_timestamps=True, language="en", beam_size=5,
                                   vad_filter=False, condition_on_previous_text=False)
        words = []
        text = ""
        for s in segs:
            text += s.text
            for w in s.words or []:
                words.append([w.word.strip(), round(w.start, 3), round(w.end, 3)])
        out[name] = {"text": text.strip(), "words": words}
        print("%-16s %-28s %s" % (name, text.strip(), words))
    json.dump(out, open(os.path.join(DIR, "spans.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
