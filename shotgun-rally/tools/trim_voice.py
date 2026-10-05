#!/usr/bin/env python3
"""Cuts each co-driver voice clip (assets/voice/fraser/*.mp3) down to its word.

The first 56 clips came with ~1 s of silence in them, and many with a scrap of
another word before the real one ("finally... right", "and... 70"), a click
after it, or the word twice: every word took ~1.5 s to say and a call of six
words took 9. This keeps only the sound(s) that say the clip's word, found by
speech recognition (assets/voice/fraser/spans.json, made by tools/voice_spans.py
on GitHub), plus 30 ms before and 60 ms after, with tiny fades. Without a
transcript match it keeps the sound with the most energy (clicks don't count).

    python3 tools/trim_voice.py          # needs ffmpeg; run it on the ORIGINAL clips
"""
import difflib
import glob
import json
import os
import re
import struct
import subprocess

DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "voice", "fraser")
RATE = 24000
FRAME = 240          # 10 ms
GAP = 25             # frames of quiet that split two sounds (250 ms)


def decode(path):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(RATE),
                          "-f", "s16le", "-"], capture_output=True, check=True).stdout
    return struct.unpack("<%dh" % (len(raw) // 2), raw)


def word_span(s):
    frames = [s[i:i + FRAME] for i in range(0, len(s), FRAME)]
    rms = [(sum(x * x for x in f) / max(len(f), 1)) ** 0.5 for f in frames]
    loud = [r > max(rms) * 0.06 for r in rms]
    # sounds: runs of loud frames, joined when less than GAP apart
    runs = []
    for i, on in enumerate(loud):
        if not on:
            continue
        if runs and i - runs[-1][1] <= GAP:
            runs[-1][1] = i
        else:
            runs.append([i, i])
    # the word = the sound with the most energy in it (not the loudest single
    # frame: a click at the start can be louder than the word)
    real = [r for r in runs if r[1] - r[0] >= 12] or runs     # clicks (< 0.12 s) aren't words
    a, b = max(real, key=lambda r: sum(x * x for x in rms[r[0]:r[1] + 1]))
    return max(0, a * FRAME - RATE * 30 // 1000), min(len(s), (b + 1) * FRAME + RATE * 60 // 1000)


NUMBER_WORDS = {"one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6"}
SOUNDS_LIKE = {"square": ["squirt", "squared"], "tightens": ["titans", "tightness"], "ferry": ["fairy"],
               "exit": ["it", "exits"], "2": ["to", "too"], "4": ["for", "four"]}


def norm(t):
    t = t.lower().replace(",", "")
    t = re.sub(r"(\d)\.(\d)", r"\1\2", t)          # "1.50" (one fifty) -> 150
    t = re.sub(r"[^a-z0-9 ]", " ", t)
    words = [NUMBER_WORDS.get(w, w) for w in t.split()]
    out = []
    for w in words:                                  # "2 50" (two... fifty) -> 250
        if out and w.isdigit() and out[-1].isdigit():
            out[-1] += w
        else:
            out.append(w)
    return " ".join(out)


def match(name, text):
    want = norm(name.replace("-", " "))
    got = norm(text)
    if not got:
        return 0.0
    if want in got.split() or want == got:
        return 1.0
    for alt in SOUNDS_LIKE.get(name, []):
        if alt in got.split():
            return 0.9
    if want.isdigit():
        return 0.0                                   # a number is that number or nothing ("50" isn't "250")
    return difflib.SequenceMatcher(None, want, got).ratio()


def pick(name, parts):
    """[(start, end), ...] seconds of the sound(s) that say `name`, or None."""
    parts = [p for p in parts if p["end"] - p["start"] >= 0.06]
    best, span = 0.0, None
    for i in range(len(parts)):
        for j in range(i, min(len(parts), i + 4)):
            text = " ".join(p["text"] for p in parts[i:j + 1])
            sc = match(name, text) - 0.03 * (j - i)
            dur = parts[j]["end"] - parts[i]["start"]
            # the best match; on a tie (the word said twice) the longer, fuller take
            if sc > best + 0.01 or (span and abs(sc - best) <= 0.01 and dur > span[-1][1] - span[0][0]):
                best, span = max(sc, best), [(p["start"], p["end"]) for p in parts[i:j + 1]]
    return span if best >= 0.55 else None


def main():
    spans_path = os.path.join(DIR, "spans.json")
    spans = json.load(open(spans_path)) if os.path.exists(spans_path) else {}
    for path in sorted(glob.glob(os.path.join(DIR, "*.mp3"))):
        name = os.path.basename(path)[:-4]
        s = decode(path)
        span = pick(name, spans.get(name, []))
        how = "speech"
        if span is None:
            a, b = word_span(s)
            span = [(a / RATE, b / RATE)]
            how = "energy"
        # each sound with 30 ms before / 60 ms after; several sounds (a phrase, or a word
        # the voice split with a pause) are joined with a short gap instead of the pause
        cuts = [(max(0.0, a - 0.03), min(len(s) / RATE, b + 0.06)) for a, b in span]
        if len(cuts) == 1 and cuts[0][0] < 0.05 and len(s) / RATE - cuts[0][1] < 0.1:
            print("ok      %-16s %.2f s" % (name, len(s) / RATE))
            continue
        dur = sum(b - a for a, b in cuts) + 0.08 * (len(cuts) - 1)
        tmp = path + ".tmp.mp3"
        graph = []
        for k, (a, b) in enumerate(cuts):
            graph.append("[0:a]atrim=%.3f:%.3f,asetpts=PTS-STARTPTS,afade=t=in:d=0.01,afade=t=out:st=%.3f:d=0.02%s[p%d]"
                         % (a, b, max(b - a - 0.02, 0.0), ",apad=pad_dur=0.08" if k < len(cuts) - 1 else "", k))
        graph.append("".join("[p%d]" % k for k in range(len(cuts))) + "concat=n=%d:v=0:a=1[out]" % len(cuts))
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", path, "-filter_complex", ";".join(graph),
                        "-map", "[out]", "-ac", "1", "-ar", str(RATE), "-c:a", "libmp3lame", "-b:a", "64k", tmp],
                       check=True)
        os.replace(tmp, path)
        print("trimmed %-16s %.2f s -> %.2f s (%s%s)" % (name, len(s) / RATE, dur, how,
                                                     ", %d sounds joined" % len(cuts) if len(cuts) > 1 else ""))


if __name__ == "__main__":
    main()
