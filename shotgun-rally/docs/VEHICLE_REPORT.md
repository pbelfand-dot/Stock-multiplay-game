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

## The street batch (October 2026)

Fourteen road cars from the owner's private download batch (`assets/car_packages/Track_Mode_Cars/Street/`;
the owner waived the licence question for this game with friends: they stay out of public credit
lists). All fourteen are in the garage (not traffic), each under a fictional name. The registry now
has 79 entries: 74 in the garage, 75 with a model of their own, 67 with their own cockpit.

| Garage name | Based on | Role | Drive | Weight | Power | 0-100 in the game (gravel) |
|---|---|---|---|---|---|---|
| TEMPESTA URSA (`tempesta_ursa`) | Lamborghini Urus Performante (2023) | super-SUV | all | 2,150 kg | 657 hp, 850 N m, 8-speed | 2.9 s (real 3.3 s) |
| WOKING 600 SPIDER (`woking_600`) | McLaren 600LT Spider (2020) | hypercar | rear | 1,300 kg | 592 hp, 620 N m, 7-speed DCT | 3.6 s (real 2.9 s) |
| AFFALTER SLR 722 (`affalter_slr`) | Mercedes-Benz SLR McLaren 722 Edition (2006) | hypercar | rear | 1,724 kg | 641 hp, 820 N m, 5-speed auto, supercharged | 4.7 s (real 3.6 s) |
| AFFALTER GT BLACK (`affalter_gtb`) | Mercedes-AMG GT Black Series (2021) | hypercar | rear | 1,540 kg | 720 hp, 800 N m, 7-speed DCT | 4.0 s (real 3.2 s) |
| VIERRAD R7 (`vierrad_r7`) | Audi RS 7 Sportback C8 (2020) | road | all | 2,065 kg | 592 hp, 800 N m, 8-speed | 2.9 s (real 3.6 s) |
| AFFALTER A45 S (`affalter_a45`) | Mercedes-AMG A 45 S 4MATIC+ (2023) | road | all | 1,635 kg | 415 hp, 500 N m, 8-speed DCT | 3.5 s (real 3.9 s) |
| KAISER 5 TOURING (`kaiser_5t`) | BMW M5 Touring G99 (2025) | road | all | 2,550 kg | 717 hp, 1,000 N m, 8-speed | 2.9 s (real 3.6 s) |
| KAISER 5 G (`kaiser_5g`) | BMW M5 G90 (2025) | road | all | 2,510 kg | 717 hp, 1,000 N m, 8-speed | 2.9 s (real 3.5 s) |
| KAISER 3X (`kaiser_3x`) | BMW X3 M40i G45 (2024) | road (SUV) | all | 1,980 kg | 393 hp, 580 N m, 8-speed | 3.6 s (real 4.6 s) |
| KAISER 235 GC (`kaiser_235`) | BMW M235i xDrive Gran Coupe F44 (2019) | road | all | 1,570 kg | 302 hp, 450 N m, 8-speed | 3.8 s (real 4.9 s) |
| KAISER 2 CARBON (`kaiser_2c`) | BMW M2 G87 with ADRO's carbon kit (2023) | touge (grip) | rear | 1,725 kg | 454 hp, 550 N m, 8-speed | 4.5 s (real 4.1 s) |
| AFFALTER S EXECUTIVE (`affalter_s`) | Mercedes-Maybach S-Class Z223 (2021), run as the S 680 | road | all | 2,350 kg | 604 hp, 900 N m, 9-speed | 3.2 s (real 4.5 s) |
| WOKING 800 (`woking_800`) | McLaren Senna (2018) | hypercar | rear | 1,300 kg | 789 hp, 800 N m, 7-speed DCT | 3.6 s (real 2.8 s) |
| WOKING ONE (`woking_one`) | McLaren P1 (2013) | hypercar | rear | 1,395 kg | 903 hp, 900 N m, 7-speed DCT | 3.6 s (real 2.8 s) |

- **Acceleration against the real cars:** the same pattern as the earlier cars. The heavy
  four-wheel-drive cars launch hard on the test's gravel pad and beat their real tarmac times by
  0.4-1.3 s (the Maybach and the BMW X3 most; the RS 6 wagon, KOMBI, already ran 3.1 s against a real 3.6 s).
  The rear-drive hypercars are traction-bound and 0.7-1.1 s slow (as the 911 GT3 RS, 4.3 s against 3.2 s).
  The specs are the real ones (power, torque, weight, ratios, top speed); the gap is the test and the
  tyre model, not the numbers. The torque curves, gear ratios beyond the published ones and the aero are estimates.
- **Interiors:** all fourteen keep their own cabin, the steering wheel cut out to turn about its own
  column and the eye placed by hand from section views (`tools/cars/<model>.json`, `"cockpit"`). All
  are automatics or dual clutches, so both hands stay on the wheel. The GT Black Series' cabin is
  low-detail and its textures aren't linked in the file: it is kept (the model's own), in flat dark
  colours set for the parts the textures would have covered (`glb_patch`). Its first conversion had
  the body back to front on its wheels (the nose at the back, its real front wheels still steered
  15 degrees): converted again from that GLB (the source archive isn't kept) with `"front": "-Y"`. The P1's wheel was
  found by measurement (its hub badge and stitching materials) rather than by eye: it is handled as
  no-AI, checked by scripts only, and left out of screenshots (`--seen_cars_only`).
- **Badges:** the separate badge parts are dropped on eight of them (`drop_mats`). The 235 GC, the
  2 CARBON and the 800 still carry theirs, and so do any badges painted into textures (each entry's
  `limitations` says which).
- **SIM STREET:** today's performance tyres (0.9-1.04 g), cup tyres for the 600, GT Black, 800 and ONE
  (1.1-1.2 g); factory ABS and traction control on all fourteen (`catalog.gd`).
- **Engine sounds:** the existing sets (`v8_turbo`, `v8_sc` for the SLR, `i6_turbo`, `turbo4`).
- **Skipped:** the 720S Spider (one heavy OBJ whose rims share the body's material, so the wheels
  can't turn; it would be a third 720S) and the BMW 540i E34 (a 3ds Max `.max` scene only: Blender
  can't read it). Both are rows in `docs/ASSET_INTEGRATION_STATUS.md`.
- **Converter (`tools/import_car.py`) fixes:** object names cut to Blender's 63 characters before
  the wheel and caliper suffixes (long Forza-style names lost their tag, so no wheels were found), and
  extra UV maps removed by name (removing them by reference crashed on a stale one, the SLR's `MaskUv`).
- **Tests:** registry, models (all fourteen build, sit on their wheels and pull away), interiors
  (eye, gloves on the rim, the wheel turning, sleeves), wheels (fit regenerated for the fourteen
  models), sound and the asset audit pass.

## The BMW 320i (October 2026)

**KAISER 320 (`kaiser_3`)**: a 2023 BMW 320i xDrive saloon (G20, the 2022 facelift), the last car
of the internet batch (`Internet_New_Cars/2023-bmw-320i-xdrive-2k.glb`, "2023 bmw 3 series" by
solid3DDD, CC BY 4.0). The cheapest European car in the garage (8,000), not traffic.

| Garage name | Based on | Role | Drive | Weight | Power | 0-100 in the game (gravel) |
|---|---|---|---|---|---|---|
| KAISER 320 (`kaiser_3`) | BMW 320i xDrive G20 LCI (2023) | road | all | 1,580 kg | 181 hp, 300 N m, 8-speed | 7.2 s (real 7.7 s) |

- **Numbers** from ADAC's catalogue: 135 kW (184 PS) at 5,000 rpm, 300 N m from 1,350 rpm, an
  eight-speed Steptronic, 1,655 kg EU (1,580 kg without the 75 kg driver), 230 km/h, 2,851 mm
  wheelbase, 225/50 R17. The ratios are the ZF 8HP's; the final drive (3.385), weight split (53 %
  front) and drag area are estimates. `road` chassis, touring tyres in SIM STREET (0.92 g), factory
  ABS and traction control.
- **The model** is dense (2.7 M triangles; its wheels 266 k each): the wheels are thinned to 12 k, the
  calipers to 2.5 k and the body to 411 k, the paint and glass kept whole. Thinning the paint too
  (the converter's new `"paint_faces"` option) left the door panels visibly wavy, so it's off for this
  car; the option stays for models that can take it. Its axes came in turned (`"front": "-X"`).
- **Badges:** the roundels and wheel caps (their own material) and the boot's 320i and xDrive letters
  (loose pieces, by box) are gone; the grille's kidney shape stays.
- **Lamps:** the tail-light glow, lens and red parts and the headlight lenses renamed so the game
  finds them (`"rename"`).
- **Interior:** its own (dash screens, seats, door cards); the steering wheel cut out to turn about
  its column (found from section views: 0.35 m across, its centre 0.85 m up), the eye placed by hand.
- **Tests:** registry, models (builds, sits on its wheels, 0-100 in 7.2 s against a 9.5 s limit, all
  four wheels driven), wheels (fits six of the seven road presets; the wide one touches the front
  arch at full bump) and the asset audit pass.


## The models' own cabins, the lamps and the live screens (October 2026)

- **Every interior is the model's.** 65 cars keep their own cabin; none is made up. The five models
  with no cabin at all (the ROTORA FC, HALDANE, STILETTO, VALKO, VESPERA: tinted glass over an empty
  shell) are driven from a camera over their bonnet (`"view": "hood"`), its height found by rays down
  onto the bonnet, the crew hidden from the first frame. Only the four on the shared rally body keep
  the rally cockpit (theirs). The ROTORA FD and the AFFALTER GT BLACK now use their own cabins.
- **Windscreens:** a script check from each driver's eye (rays ahead, through glass) found the
  AFFALTER S EXECUTIVE's windscreen modelled in the black trim's material (opaque: the driver saw
  black). Its two sheets get the side windows' glass (`glb_patch` `"faces"`: whole pieces of a
  material inside a box given another material; the rain sensor's small pieces stay black), and its
  cockpit windshield is measured from them. The other own-cabin cars see out (checked in the seat
  renders; the no-AI cars by script only).
- **Textures:** the BOLT 16's cabin carbon and its dash were drawn lavender: their colour textures
  were normal maps (a rip's mix-up). Now the carbon has the car's carbon weave for its colour and the
  old picture as its normals, and the dash the colour map its twin material uses (`glb_patch`
  `"normal_from_base"`, `"base_texture_of"`). A scan of every car's colour textures found no other.
- **Headlights:** every model's head and tail lamps are found (74 models), each side's lamp on its
  own; the beams start at the lamps' lenses, with no glowing balls in front of them.
- **Live screens:** 21 cars' instruments work (`data/dash/`, the table in `docs/cars.md`), the
  luxury cars first; a tall or square centre screen (the Maybach's, the Senna's) puts its menu across
  the top as tabs.
- **Left to do:** the live pages for the cars whose screens are painted into a texture shared with
  the rest of the cabin (the A 45 S, Supra, AMG GT3, 911 GT3 R, Bolide, the GT-R's dials).
  The 320i's cluster keeps its painted art now, made live over it, and so do the Honda e's screens.
