# The cars with bodies of their own

Six garage cars have realistic bodies of their own and the real cars' numbers. In the
game they go by look-alike names, and their maker badges and nameplates are taken off
the models (the game has no real brands):

| Garage name | Based on | Drive | Weight | Power | 0-100 km/h in the game (gravel) |
|---|---|---|---|---|---|
| NIMBUS EG | Honda Civic SiR II (EG6, 1992) | front | 1,050 kg | 170 PS | ~9.3 s |
| ROTORA FC | Mazda RX-7 FC3S Turbo II (JDM GT-X, 1989) | rear | 1,250 kg | 205 PS | ~6.3 s |
| KAISER 30 | BMW M3 E30, Prodrive Group A rally car (1987) | rear | 1,050 kg | ~290 PS | ~4.3 s |
| ROTORA FD | Mazda RX-7 FD3S Type R (1992) | rear | 1,260 kg | 255 PS | ~5.4 s |
| VIERRAD S1 | Audi Sport quattro, Group B rally car (1984-85) | all | 1,100 kg | ~455 PS | ~3.5 s |
| OCELOT R1 | Ford Puma Rally1 (2022) | all | 1,260 kg | ~385 PS | ~3.4 s (real: ~3.2 s) |

The touge cars (NIMBUS, both ROTORAs) are stock road cars. The rally cars are their
rally versions.

## Where the numbers come from

All the numbers are in `scripts/vehicle/car_specs.gd` (SPECS). Weights, outputs,
dimensions and gear ratios were cross-checked online; the main sources are below. The
ones marked *estimate* aren't published, so they're the closest sensible value.

- **Civic EG6 SiR II**
  - B16A: 170 PS @ 7,800, 157 Nm @ 7,300, 8,200 rpm limit.
  - 1,050 kg (Honda's factbook says 1,040).
  - Gearbox 3.230 / 2.105 / 1.458 / 1.107 / 0.848, final drive 4.400.
  - Wheelbase 2,570, track 1,475 / 1,465 mm.
  - Weight split 61/39 is an *estimate*.
  - Sources: honda.co.jp factbook (CIVIC 1991-09), 221616.com catalogue, carfromjapan specs.
- **RX-7 FC Turbo II**
  - 13B-T in the 1989-91 JDM tune: 205 PS @ 6,500, 270 Nm (27.5 kgm) @ 3,500, 1,250 kg.
  - The US Turbo II has 182 hp and weighs ~1,300 kg.
  - Gearbox 3.483 / 2.015 / 1.391 / 1.000 / 0.762, final drive 4.100. Sources disagree on 5th: 0.762 vs 0.806.
  - Redline 7,000 rpm and a ~50/50 weight split are *estimates*.
  - Sources: carfromjapan GT-X specs, jdmbuysell FC3S guide, rx7.com drivetrain.
- **RX-7 FD Type R**
  - 13B-REW: 255 PS @ 6,500, 294 Nm @ 5,000, 8,000 rpm limit.
  - 1,260 kg, 50/50 weight split, Torsen LSD.
  - Gearbox 3.483 / 2.015 / 1.391 / 1.000 / 0.719, final drive 4.100.
  - Wheelbase 2,425, track 1,460 mm.
  - Sources: automobile-catalog (Efini RX-7 Type R), carfromjapan, encycarpedia.
- **E30 M3, Prodrive Group A**
  - 1,050 kg in 1987 (later 1,025 kg).
  - 280-300 hp @ 8,400 and 285 Nm @ 6,500: 270 bhp in 1987, rising to 295 by 1989.
  - Getrag five-speed 3.72 / 2.40 / 1.77 / 1.26 / 1.00.
  - The rally final drive (4.10) and the weight split are *estimates*.
  - Sources: tech-racingcars.wikidot (BMW E30 M3), bimmerlife, speedholics, ultimatecarpage.
- **Sport quattro, Group B**
  - 450 hp @ 7,500 and 460 Nm @ 5,500, from a KKK K27 turbo.
  - 1,100 kg, 52/48 weight split.
  - Gearbox 3.500 / 2.083 / 1.368 / 0.962 / 0.821, with a final drive of 3.875-5.857 (4.857 here).
  - Centre diff 100 % locked, LSDs front and rear.
  - Wheelbase 2,224 mm, the most cited figure (2,204 is also quoted).
  - Source: tech-racingcars.wikidot (Audi Sport quattro); audi.com and audi-mediacenter for the road car.
- **Puma Rally1**
  - 1,260 kg minimum weight (2022-24).
  - ~380 hp / 420 Nm from the engine; with the hybrid's 100 kW boosts, over 500 hp and over 500 Nm. The game has no hybrid: 450 Nm stands in for it.
  - Spool (fixed 50/50), mechanical LSDs front and rear.
  - Five-speed sequential; M-Sport doesn't publish the ratios, so they're *estimates*.
  - Wheelbase 2,600, width 1,875 mm.
  - Sources: media.ford.com (2022 Rally1 launch), fia.com, juwra.com.
- **All cars:** frontal areas are *estimates*, and so is the rally cars' drag.

The body sizes (wheelbase, track, tyre size, length, height) come from each model,
scaled to the real wheelbase. The physics wheels are put where the model's are, so
the body always sits on them.

## How the physics is built

`CarSpecs.config(model)` takes the AWD rally car (`data/cars/awd_rally.tres`) and makes it over:
- the wheels go where the model's are;
- weight and weight split come from the spec, and the inertia is scaled by weight and size;
- springs, dampers and anti-roll bars are scaled with the weight (the same ride frequencies), and the brakes with weight and tyre size;
- engine curve, limiter, turbo (lag, anti-lag), gears, final drive, which wheels are driven, and the diffs come from the spec;
- the collision boxes come from the model's body.

Rear- and front-drive cars have no rally handbrake clutch. Pulling the handbrake dips
the clutch instead, like a driver's left foot.

The garage shows each car's real power (peak of its torque curve, with engine
upgrades) and weight.

## Adding a car

1. Unzip the model (OBJ, FBX or .blend) into its own folder, outside the repo.
2. Write `tools/cars/<id>.json`:
   - which way the nose points, the real wheelbase;
   - the name patterns of the wheel parts (and calipers), the paint and glass materials;
   - materials to restyle (`"glass"`, `"chrome"`, `"red_lens"` ... see LOOKS in the tool);
   - logo materials to drop.

   `--survey` lists every material, where it is on the car and how big, to help write it.
3. `blender -b -Y --python tools/import_car.py -- tools/cars/<id>.json <model> [texture dir]`
   writes `assets/models/cars/<id>/<id>.glb` and `parts.json`. `-Y` keeps any scripts in a .blend switched off.
4. Add the car's numbers to `SPECS` in `scripts/vehicle/car_specs.gd`, and a garage entry with `"model": "<id>"` in `scripts/game/catalog.gd`.
5. `tests/car_models_check.gd` checks it:
   - it builds;
   - it sits on its wheels;
   - its body clears the ground;
   - it does 0-100 in a sane time, with the right wheels driven.
