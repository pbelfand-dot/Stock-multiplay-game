# The engine sound

Made from two videos the owner supplied (October 2026):
- *PURE SOUND | Launch Control Ford Fiesta WRC* (12.7 s): the car on a stage start line: its
  anti-lag idle, the launch control on the limiter with anti-lag crackle, the launch.
- *Rally Car Sound Effect* (61 s, a still of the Lotos Ford Fiesta RS WRC over the audio): six clips
  of the car pulling through its gears flat out on gravel.

**Licence: these are YouTube recordings, not sounds we own.** Fine for playing with friends; before
the game is sold or put up publicly, replace them with licensed recordings (or get permission) and
re-run `build.py` on the new ones.

## How the loops were made (`build.py`, numpy + scipy)
1. `fire.py` / `fine.py`: the engine's firing frequency through each clip (a four-cylinder fires
   twice a turn: rpm = 30 x firing frequency). Checked against the harmonic peaks: the launch
   control is a series on 209 Hz (419, 630, 840 Hz...) = ~6,300 rpm; the idle a series on 48.7 Hz
   whose strongest line is 97 Hz = firing at ~2,915 rpm (a WRC car's anti-lag idle).
2. Each loop's stretch is read at a varying speed (target / pitch) so its pitch is steady, cut to
   a whole number of firing cycles, its slow swells in loudness evened out, and crossfaded
   end-into-start: `idle` (2,915 rpm, launch-control video 0.62-1.30 s), `mid` (5,900 rpm, the
   first pull 26.95-27.70 s), `high` (7,350 rpm, 27.93-28.62 s), `overrun` (6,350 rpm, the launch
   control 4.30-5.20 s, off-throttle crackle).
3. One-shots: `shift.wav` (the upshift at 28.70-29.15 s: the cut and the bang), `pop1-4.wav` (the
   four sharpest anti-lag bangs in the launch control).

Re-make: put the videos' audio (mono 44.1 kHz) here as `a.wav` (the sound effect) and `b.wav`
(the launch control), then `python3 build.py` (writes `out/`; copy to `assets/sfx/engine/`).
The game blends them in `scripts/vehicle/engine_sound.gd`; `tests/sound_check.gd` checks it.

## How the game plays them (engine_sound.gd)
The method is [markeasting/engine-audio](https://github.com/markeasting/engine-audio)'s
(MIT, (c) 2025 Mark Oosting). We use its approach only, not its WAV files: their names look like
exports from a racing sim's sound banks, and its licence covers the code, not those recordings.
- The loops play on the throttle (on-load) and off it (off-load), with equal-power crossfades
  between neighbouring loops by the revs and between on- and off-load by the throttle.
- Off-load is the same loops through a low-pass, quieter, except for the overrun crackle on an
  anti-lag engine.
- Against the limiter the throttle cuts and fires 11 times a second.
- A gearbox whine and a turbo or supercharger whistle are tones made in code, pitched by the road
  speed, the boost or the revs. So is a road turbo's blow-off hiss.

Each car's engine type (Catalog `"engine"`, `EngineSound.ENGINES`) sets its character: how fast it
fires for its revs (a five-cylinder 1.25 x a four's), turbo, supercharger, anti-lag, pops, blow-off,
how loud the gearbox whines, the shift's bang, and the tone (an EQ, plus an overdrive for the rotary,
on a bus of its own that sends into SFX).

These are still one recorded engine with different characters. A real rotary, five-cylinder or road
four needs recordings of that engine: steady pulls through the revs, and lifts. Give them to
`build.py` the same way and add the loops to that engine type.
