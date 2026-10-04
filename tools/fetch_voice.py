#!/usr/bin/env python3
"""Downloads new co-driver lines listed in assets/voice/fraser/new_clips.json
(Higgsfield result URLs), turns each into a small MP3 like the other 56 clips
(silence trimmed, mono, 24 kHz, 64 kbps), adds it to manifest.json and empties
the list. Runs in GitHub Actions (.github/workflows/voice.yml), because the
Claude sandbox can't reach the clip host; or locally:

    python3 tools/fetch_voice.py        # needs ffmpeg on PATH
"""
import json
import os
import subprocess
import tempfile
import urllib.request

DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "voice", "fraser")
TRIM = ("silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
        "silenceremove=start_periods=1:start_threshold=-45dB,areverse,apad=pad_dur=0.02")


def main() -> None:
    new_path = os.path.join(DIR, "new_clips.json")
    new = json.load(open(new_path))
    clips = new.get("clips", {})
    if not clips:
        print("No new clips.")
        return
    man_path = os.path.join(DIR, "manifest.json")
    man = json.load(open(man_path))
    with tempfile.TemporaryDirectory() as tmp:
        for name, url in clips.items():
            wav = os.path.join(tmp, name + ".wav")
            urllib.request.urlretrieve(url, wav)
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-af", TRIM, "-ac", "1",
                            "-ar", "24000", "-c:a", "libmp3lame", "-b:a", "64k",
                            os.path.join(DIR, name + ".mp3")], check=True)
            if name not in man["clips"]:
                man["clips"].append(name)
            man.setdefault("source", {}).setdefault("clips", {})[name] = url
            print("saved", name)
    json.dump(man, open(man_path, "w"), indent=2)
    open(man_path, "a").write("\n")
    new["clips"] = {}
    json.dump(new, open(new_path, "w"), indent=2)
    open(new_path, "a").write("\n")


if __name__ == "__main__":
    main()
