# The cars: final report (October 2026)

The 10-phase vehicle mandate: restore and inventory every car package, make every usable car
work (its interior, the driver fitted to it, researched numbers, physics from them), the registry,
the touge and cut-up modes, then test everything. This is where it ended up.

1. **44 vehicles in the registry** (`data/vehicles/`): 39 in the garage, 9 that appear as traffic,
   40 with a model of their own, 37 with their own cockpit. All 43 restored candidates are
   accounted for in `docs/VEHICLE_PROGRESS.md`.
2. **New in this round (14 cars):** BRAWLER 70 (Camaro), HELLHOUND traffic (standard Hellcat),
   UNO HYBRID (AMG ONE), CENTURIA 16 (Chiron Mansory), VENTO CINQUE (Zonda), BOLT W16 (Bolide),
   VEE-SR GTP (Cadillac), 963 GTP (Porsche 963), ELFER R and ELFER R EVO (911 GT3 R, 2023 and 2026),
   ELFER RS (911 GT3 RS), MOCHI e (Honda e), GHOST J (Jesko), BISCIONE V6 (Alfa 155 DTM).
3. **The hero car** is the Hellcat Widebody (HELLHOUND WB); the standard-body Hellcat, GLS 63, RS 6,
   M3 Touring, M8 and now the Honda e are the uncommon traffic on the highway.
4. **One car blocked: the McLaren P1 GTR.** Its file is a 45-degree-turned kitbash (an SR20 valve
   cover in the engine bay), 3.8M triangles, no textures of its own, and the conversion runs out of
   memory (14 GB) in Blender's scene update at export, even pre-thinned to 1.36M triangles with
   plain materials. Next step: rebuild it part by part in a fresh scene, or a cleaner model.
5. **Not used, on purpose:** the second M4 (a duplicate), the alternate M8, the second GT3 RS
   package (a GTA-style port with uncoloured panels).
6. **Every car has researched numbers** (power, weight, drive, gearbox, wheelbase, top speed) with
   their sources in its entry, and what's an estimate (torque curves, ratios, aero) says so.
   Physics comes from them through `tools/vehicle_physics.py`.
7. **Interiors and driver fit:** the crew sit in each car's own cockpit, the gloves on its own wheel,
   the hand on its own lever (H4/H5/H6 gates, sequential, paddles); driver fit (head, seat, hands,
   pedals, door) is sane in all 39 cockpits (F9 shows it).
8. **A rendering fix for many cars (`tools/glb_alpha.py`):** game rips mark every material as
   see-through; Godot drew those in its transparent pass (the 963 had 76 of 78 surfaces there).
   Only real glass stays blended now; 15 cars improved, and every new conversion gets it.
9. **An electric car's sound** for the Honda e: a motor whine that rises with its revs, quieter on
   the regen, an inverter tone and the reduction gear; no limiter, no shifts.
10. **Converter (`tools/import_car.py`) learned:** textures saved under other names, missing ones
    unlinked, WebP for grayscale and float images, a turn for models saved at an angle, a given
    steering-wheel axis, empty parts dropped, wheel trim, unmixing game-mod materials, turning
    wheels saved backwards, letting floating tyres down, and per-part thinning (cars are 6-34 MB).
11. **Cut up:** a reset (R) now lands in the clearest lane instead of on the centre line, often
    inside a crashed car; that also fixed an intermittent test failure.
12. **The crowd** no longer floods every log with a physics-interpolation warning.
13. **The touge** (hairpins, guardrails, cedars, time attack and drift) and **cut up** (four-lane
    highway, IDM + MOBIL traffic, near-miss combos) are both in MODES, from earlier in the round.
14. **Tests: everything passes** (`tests/run_all.sh`: registry, stages, drives, physics, models,
    interiors, cockpit, sound, modes, touge drive, updater). New checks: the electric sound, a
    reset into the clearest lane.
15. **Not yet in the download.** `main` has everything, but GitHub refuses to start the build:
    "recent account payments have failed or your spending limit needs to be increased". The
    download is still build 143. Fix it in GitHub Settings, Billing and plans, then re-run the
    latest workflow run on main (or push again).
16. **No-AI handling:** 7 entries (the three generic traffic cars, the standard Hellcat, the S13,
    the Alfa 155 and the GT3 R evo) were converted and checked by local scripts only; their looks
    have never been checked by eye, only by the tests.
17. **Provenance:** several models are game rips (CSR Racing 2, Assetto Corsa, Forza, GTA-style
    ports) or carry NonCommercial licences: fine among friends, but every one is listed in
    `docs/CREDITS.md` to replace or clear before anything public or paid.
18. **Real names:** the garage uses made-up names, but real badges remain in some textures
    (the AMG wheel and screen, the Bolide's, Porsche crests). Still waiting on your call: keep
    the real names among friends, or scrub them.
19. **Size:** this round added ~264 MB of car files; the cars total 543 MB and the repository's
    history is 2.9 GB (GitHub's guidance is under 5 GB). Before many more cars: Git LFS for the
    GLBs, or a separate downloadable car pack.
20. **Known look issues to polish:** carbon cockpits pick up a green cast from the grass in the
    ambient light; the Jesko's package came with no textures (plain looks); the Alfa's eye sits
    a little high; the Honda e's 0-100 on gravel (10.7 s) is slower than its real 8.3 s on tarmac.

## Six SUVs (October 2026)

The owner's six internet packages (`assets/car_packages/Internet_New_Cars/`): all six are in the
garage and in highway traffic, each with its own cockpit. The registry now has 50 entries:
45 in the garage, 15 that appear as traffic, 46 with a model of their own, 45 with their own cockpit.

| Garage name | Based on | Role | Drive | Weight | Power | 0-100 in the game (gravel) | Traffic |
|---|---|---|---|---|---|---|---|
| STROMER 4 (`stromer`) | VW ID.4 Pro Performance (2021) | heavy EV crossover; free (every profile owns it, like the rally car) | rear | 2,049 kg | 201 hp, 310 N m, one gear, regen | 8.9 s (real 8.5 s) | crossover, common (0.3) |
| WARHAWK 707 (`warhawk`) | Jeep Grand Cherokee Trackhawk (2018) | brutal supercharged SUV | all | 2,433 kg | 707 hp, 875 N m, 8-speed | 3.1 s (real ~3.7 s) | luxury, rare (0.06) |
| PUEBLO 392 (`pueblo`) | Dodge Durango SRT 392 (2021) | heavy, stable, naturally aspirated V8 | all | 2,439 kg | 475 hp, 637 N m, 8-speed | 4.5 s (real ~4.6 s) | SUV (0.15) |
| KAISER 5X (`kaiser_5x`) | BMW X5 M F85 (2016) | sharp but heavy | all | 2,275 kg | 567 hp, 750 N m, 8-speed | 3.4 s (real 4.2 s) | luxury, rare (0.06) |
| KAISER 7X (`kaiser_7x`) | BMW X7 M50i G07 (2020) | luxury, soft but quick | all | 2,480 kg | 523 hp, 750 N m, 8-speed | 3.9 s (real 4.7 s) | SUV, common (0.25) |
| KASTEN 63 (`kasten`) | Mercedes-AMG G 63 W463 (2020) | tall, rolls, twin-turbo V8 | all | 2,560 kg | 577 hp, 850 N m, 9-speed | 3.5 s (real 4.5 s) | luxury, rare (0.07) |

- **Physics:** two new chassis classes (`car_specs.gd`): `sport_suv` (Trackhawk, X5 M: firmer, more
  anti-roll, sharper steering) and `tall_suv` (G 63: soft, slow springs, a high centre of mass, so it
  rolls and pitches). The Durango, X7 and ID.4 use the existing `suv`. The ID.4 is the second EV: a
  constant-torque-then-constant-power motor curve, one 13:1 gear (160 km/h at its limit),
  regenerative braking when you lift (`"regen"` in its physics: the engine model's new
  `regen_torque`), and the electric sound. Like the other cars, the SUVs run 0-100 quicker on the
  test's gravel pad than the real cars do on tarmac (the cut-up handling work will look at it).
- **Interiors kept whole** (none deleted or replaced): the crew sit in each one's own seats, the
  gloves on its own wheel (which turns about its own column), automatics (no lever: both hands stay
  on the wheel). The ID.4 and X7 are game rips with simple, all-black cabins (one palette
  texture): their pure blacks are lifted to dark grey (`"lift"`) and a wrong occlusion map dropped
  (`glb_patch` `"no_occlusion"`), or the cabins rendered solid black. The Durango's package has no
  textures: its white and black materials got plain looks (leather wheel, trims, gauges, a black
  grille). The G 63's four spinning-wheel shells (from its game) hung 3 cm below the road: dropped.
- **Driver fit:** the Trackhawk's wheel cut caught its stalks (it read the rim as 267 mm: the arms
  stretched x1.87): the rim radius is given (`"radius"`, a new converter option) and its eye moved;
  the ID.4's seat was found too low: its eye is given. Both now stretch x1.25-1.36, like the rest.
- **Lamps:** the Trackhawk's French material names renamed so the lamp finder knows them; the G 63's
  every material name held "Recycled" (it found "led" in it: its grilles glowed): the prefix is cut
  (`"rename"` now takes a regex); the ID.4's and X7's lamps are painted into their one atlas: their
  lamp areas are copied into lamp materials (`remat_boxes`), the same texture, so only the bright
  lamp graphics glow.
- **Converter (`tools/import_car.py`) learned:** `wheel_islands` (one-piece models: the tyres find
  the wheels and calipers), `rotate`, `rename` (regex), `lift`, a given rim `radius`.
- **Tests:** registry, the models check (all six build, sit on their wheels, clear the ground, pull
  away on the right wheels), the interiors check (seats, gloves on the rims, the wheel turning,
  sleeves), the live-dash check (the dome light in all 45), the look check, the modes check
  (traffic with them in it) and the three-player online cut up all pass.
- **Left to do:** real badges remain in some textures (the VW, BMW, Jeep and Mercedes emblems on
  grilles and steering wheels), like the earlier cars; live gauges (`data/dash/`) for the six aren't
  written yet (they have the dome light and their own static dials); the ID.4 and X7 cabins are
  low-detail by nature.
