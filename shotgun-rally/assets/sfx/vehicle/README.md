# The car's start-up sounds

Played by `scripts/vehicle/engine_sound.gd` (`start_up()`): the door shutting and the engine
starting, at a stage's start and when you pick DRIVE THIS ONE in the garage.

| File | From |
|---|---|
| `engine_start.ogg` | `Vehicle_Car_Start_Engine_Exterior_Mono.wav` |
| `door_shut_out_1..3.ogg` | `Vehicle_Car_Door_Closing_Exterior_Mono_01..03.wav` |
| `door_shut_in_1..3.ogg` | `Vehicle_Car_Door_Closing_Interior_Mono_01..03.wav` |

All from Nox Sound Design's *Vehicle Essentials*
(https://nox-sound-design.itch.io/essentials-series-sfx-nox-sound), CC0 1.0: the originals are in
`assets/sfx/vehicle_core/nox_recorded/car/` (that library is kept out of the game's builds by its
`.gdignore`). Converted to mono OGG Vorbis (48 kHz, quality 6) with ffmpeg, nothing else changed.
