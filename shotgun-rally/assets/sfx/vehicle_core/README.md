# Vehicle core audio

This folder contains 191 WAV files selected as the practical core vehicle-audio library for Shotgun Rally.

## `nox_recorded/`

- 161 real vehicle recordings at 48 kHz / 24-bit.
- `car/` contains engine idle, 1000 RPM, 2000 RPM, interior/exterior driving loops, doors, windows, controls, horns, keys, seat belts, trunk, warning sounds, and wipers.
- `truck/` contains truck and van driving/idle loops plus doors, controls, horns, keys, seat belts, warning sounds, and wipers.
- Source: https://nox-sound-design.itch.io/essentials-series-sfx-nox-sound
- License: CC0 1.0 Universal; attribution is optional.

## `vehicle_sfx_free/`

- 30 game-ready WAV effects at 48 kHz / 24-bit.
- Includes engine start/stop/rev/acceleration, backfire, pass-by, skids, tyre burst, crashes, metal scrape, glass, doors, horns, siren, indicator, air brake, and reverse beeper.
- Six files ending in `_loop` are seamless loops.
- Source: https://heyheythere.itch.io/vehicle-sfx-free
- License: CC BY 4.0. Preserve `LICENSE.txt` and the credit below.
- AI disclosure: the author says these sounds were synthesized in code with AI assistance, then checked and levelled.

Required credit:

> Vehicle SFX Free by heyheythere - https://heyheythere.itch.io/vehicle-sfx-free - CC BY 4.0

## Integration guidance

- Crossfade multiple RPM layers instead of pitch-shifting one sample across the entire rev range.
- Keep separate interior and exterior mixes.
- Layer throttle/load, coast, shift, backfire, tyre slip, wind, and road-surface sounds independently.
- Do not load all 191 files for every car. Build small per-car banks and stream or preload only the active bank.

The larger 96 kHz performance-car source recordings remain outside the repository because they are 356 MB of raw editing material rather than game-ready core assets.
