# Co-driver voice: "Fraser"

**62 short clips** that the AI co-driver strings together ("3 left, 100, into 2 right"). These are
copied from your Rally Co-Driver GPS app:
[`pbelfand-dot/driver-test-app` → `rally/voice/`](https://github.com/pbelfand-dot/driver-test-app/tree/claude/focused-johnson-xpi0q4/rally/voice)
(commit `0faa958`).

- **Voice:** Higgsfield Seed Audio 1.0, preset voice **Fraser** (speech_rate +20, loudness +10).
  The full settings are in [`manifest.json`](manifest.json).
- **Format:** mono MP3, 24 kHz, 64 kbps, cut down to just the word. Godot plays MP3 directly.
- **Trimmed (2026-10-05):** the first 56 clips arrived with ~1 s of silence in them, and many with a
  scrap of another word before the real one ("finally... right", "and... 70"), a click, or the word
  twice, so every word took ~1.5 s and a call of six words took 9 s (the calls fell behind the car).
  Speech recognition on GitHub found which sound in each clip is the word
  ([`spans.json`](spans.json), from `tools/voice_spans.py`) and `tools/trim_voice.py` kept only
  that: words are now 0.3-0.6 s. A few keep a little "and" in front ("and 100", "and tightens"),
  which reads naturally in a call.
- **Ownership:** you generated these with your own Higgsfield account. No other person's voice is
  in them.

## What's here

| Group | Clips |
|---|---|
| Corner grade (6 = fastest, 1 = slowest) | `1` `2` `3` `4` `5` `6` |
| Distances (m) | `30` `40` `50` `60` `70` `80` `100` `120` `150` `200` `250` `300` `350` `400` `450` `500` `600` `700` `800` `900` `1000` |
| Corners | `left` `right` `hairpin` `square` `keep` |
| Modifiers | `long` `tightens` `opens` `caution` `into` `and` `at` |
| Start / finish | `ready` `go` `finish` `stage-complete` |
| Road hazards (useful for road sections) | `bump` `rail-crossing` `stop-sign` `lights` `ramp` `merge` `exit` `roundabout` `ferry` `speed-camera` |
| GPS-app only (probably unused) | `off-route` `new-route` `reroute-failed` |

The countdown can reuse `5` `4` `3` `2` `1` `go`.

## Added for SHOTGUN RALLY (same voice, same settings)

`over-crest` · `jump` · `dont-cut` · `water` · `wipers` · `nice`: 6 lines, 1.2 credits, made on
2026-10-04 and fetched by the **store new voice lines** workflow (the Claude sandbox can't reach the
clip host, GitHub can).

## Still to make

One line costs **0.2 credits**. To add lines: generate them with Higgsfield (Seed Audio, preset
"Fraser", speech_rate +20, loudness +10), put `name: url` pairs in
[`new_clips.json`](new_clips.json) and push; the workflow converts them and commits the MP3s.

`ruts` · `narrow` · `cow` · `spectators` · `slow` · `brake` · `ok-board` · `triangle-out` · `push` ·
`jump-start` · `puncture` · `good-job` · `you-okay` · `back-on-the-road` · `left-left-left` ·
`right-right-right` · `time-control` · `junction` · `too-early` · `were-late`
