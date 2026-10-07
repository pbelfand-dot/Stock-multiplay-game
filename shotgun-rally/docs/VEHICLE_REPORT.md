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
