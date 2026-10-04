# Co-driver voice: "Fraser"

**56 short clips** that the AI co-driver strings together ("3 left, 100, into 2 right"). These are
copied from your Rally Co-Driver GPS app:
[`pbelfand-dot/driver-test-app` → `rally/voice/`](https://github.com/pbelfand-dot/driver-test-app/tree/claude/focused-johnson-xpi0q4/rally/voice)
(commit `0faa958`).

- **Voice:** Higgsfield Seed Audio 1.0, preset voice **Fraser** (speech_rate +20, loudness +10).
  The full settings are in [`manifest.json`](manifest.json).
- **Format:** mono MP3, 24 kHz, 64 kbps, silence trimmed. Godot plays MP3 directly.
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

## Still to make (same voice, same settings)

One line costs **0.2 credits** (checked on 2026-10-04), so all of these come to about **6–8 credits**:

`over` · `crest` · `jump` · `don't cut` · `flat` · `water` · `narrow` · `ruts` · `cow` · `spectators` ·
`slow` · `brake` · `wipers` · `OK board` · `triangle out` · `push` · `jump start` · `puncture` ·
`nice` · `good job` · `you okay?` · `back on the road` · `left left left` · `right right right` ·
`time control` · `junction` · `too early` · `we're late`
