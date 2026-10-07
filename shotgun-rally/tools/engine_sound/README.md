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

## The engines now: markeasting/engine-audio's sounds (engine_sound.gd)
The engine loops come from [markeasting/engine-audio](https://github.com/markeasting/engine-audio)
(its code MIT, (c) 2025 Mark Oosting), and the game plays them its way.
- **The sets**, converted to mono 16-bit 44.1 kHz WAVs at matched loudness:
  - `assets/sfx/engine/bac/`: a BAC Mono's four-cylinder.
  - `procar/`: a BMW M1 Procar's straight six.
  - `v8/`: a Ferrari 458's V8.
  - `gearbox/`: its gearbox-whine samples, the on-load one cut to a 6 s crossfaded loop.
- **The playing** follows its configurations:
  - The revs each loop was recorded at.
  - Equal-power crossfades: low into high between 3,000 and 6,500 rpm, on into off with the throttle.
  - Each loop pitched 0.2 cents per rpm from the revs it was recorded at.
  - The limiter loop over the last 8 % of the revs.
  - The gearbox detune: on-load `rpm x ratio x 0.05 - 100` cents, off-load `x 0.035 - 800`.
- **The Fiesta WRC recordings** still give an anti-lag car its overrun crackle and pops, and a
  sequential its shift bang (the pull loops `idle`/`mid`/`high` are no longer used).

**Licence: the owner chose to use these sounds.** engine-audio's licence covers its code, not its
recordings. Their names (`on_high {5a92afe9-...}.wav`) look like exports from a racing sim's sound
banks, and BAC Mono, Ferrari 458 and M1 Procar are Assetto Corsa cars. As with the YouTube
recordings above: fine among friends; replace them with licensed recordings before the game is sold
or put up publicly. The loops drop in as `on_low`/`on_high`/`off_low`/`off_high`/`limiter` with
their recorded revs in `EngineSound.SETS`.

Each car's engine type (Catalog `"engine"`, `EngineSound.ENGINES`) picks its set and its character:
turbo whistle, supercharger, anti-lag crackle, pops, blow-off hiss, how loud the gearbox whines, the
shift's bang, and the tone (an EQ on a bus of its own into SFX).
