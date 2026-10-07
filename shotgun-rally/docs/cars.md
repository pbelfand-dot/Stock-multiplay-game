# The cars with bodies of their own

Nine garage cars have realistic bodies of their own and the real cars' numbers. In the
game they go by look-alike names, and their maker badges and nameplates are taken off
the models (the game has no real brands):

| Garage name | Based on | Drive | Weight | Power | 0-100 km/h in the game (gravel) |
|---|---|---|---|---|---|
| HACHI 86 | Toyota Sprinter Trueno GT-APEX (AE86, 1983-85) | rear | 940 kg | 120 PS | ~10.2 s |
| NIMBUS EG | Honda Civic SiR II (EG6, 1992) | front | 1,050 kg | 170 PS | ~9.3 s |
| ROTORA FC | Mazda RX-7 FC3S Turbo II (JDM GT-X, 1989) | rear | 1,250 kg | 205 PS | ~6.3 s |
| SYLPH S15 | Nissan Silvia Spec-R (S15, 1999-2002), on a widebody kit | rear | 1,240 kg | 250 PS | ~5.8 s |
| KAISER 30 | BMW M3 E30, Prodrive Group A rally car (1987) | rear | 1,050 kg | ~290 PS | ~4.3 s |
| ROTORA FD | Mazda RX-7 FD3S Type R (1992) | rear | 1,260 kg | 255 PS | ~5.4 s |
| MARTELLO SEDICI | Lancia Delta HF Integrale, Group A works rally car (1992) | all | 1,100 kg | ~315 PS | ~3.8 s |
| VIERRAD S1 | Audi Sport quattro, Group B rally car (1984-85) | all | 1,100 kg | ~455 PS | ~3.5 s |
| OCELOT R1 | Ford Puma Rally1 (2022) | all | 1,260 kg | ~385 PS | ~3.4 s (real: ~3.2 s) |

The touge cars (HACHI, NIMBUS, both ROTORAs, SYLPH) are stock road cars. The rally cars are their
rally versions.

The four rally cars on the shared body weigh what their real class weighed:

| Garage name | Class | Weight | Source |
|---|---|---|---|
| KESTREL R4 | FIA R4 (over 2 litres, turbo, four-wheel drive) | 1,300 kg | the R4 minimum (Wikipedia: Group R) |
| BLUE COMET WRC | World Rally Car, 1997-2010 | 1,230 kg | the WRC minimum; the Impreza WRC and Lancer WRC both ran at it |
| VORTEX EVO | World Rally Car, 1997-2010 | 1,230 kg | as above |
| MARTELLO 037 | Group B | 960 kg | the Lancia Rally 037's competition weight |

Their springs, dampers, anti-roll bars and brakes scale with the weight (`CarSpecs.rally`),
the same way the cars with their own bodies do.

## Their interiors

Each car keeps the interior its model came with, and the crew fit into it rather than the other way
round:

| Garage name | Interior | Driver sits | Gears (the hand) | Handbrake |
|---|---|---|---|---|
| HACHI 86 | the model's, full | right (right-hand drive) | 5-speed H-pattern, left hand | its lever between the seats |
| NIMBUS EG | the model's | right | 5-speed H-pattern, left hand | its lever |
| SYLPH S15 | the model's, full (bucket seat, harness) | right | 6-speed H-pattern, left hand | its lever beside the console |
| KAISER 30 | the model's, basic | left | 5-speed H-pattern, right hand: a lever added (none modelled) | none modelled |
| MARTELLO SEDICI | the model's, basic | left | 5-speed H-pattern, right hand: a lever added (none modelled) | none modelled |
| VIERRAD S1 | the model's | left | 5-speed H-pattern, right hand | its lever between the seats |
| OCELOT R1 | the model's, full rally (cage, buckets) | left | its sequential lever, right hand | its tall hydraulic lever |
| ROTORA FC, ROTORA FD | too rough to sit in (blocks; a broken wheel ring): the game's rally cockpit | left | | |

- The crew sit in its seats: the driver behind its steering wheel (on the right in a right-hand-drive
  car, with the co-driver and the map board on the left), at near real size (the interior is). Their
  eyes are found from the seat: rays down onto its cushion and back onto its back, clear of the roof.
- The gloves grip its own wheel's rim and turn it about its own column.
- The hand nearer the middle works its own gear lever. An H-pattern lever goes out of gear, across
  the gate and into the next, and stays there. A sequential is pulled back or pushed forward and
  springs back. An automatic shifts itself and the hand stays on the wheel. (The game shifts for
  you in every car; the lever shows it.)
- Its own handbrake comes up from its pivot.
- An interior modelled without a gear lever (KAISER 30, MARTELLO SEDICI) gets one made for it by the
  converter (`"shifter": {"add": ...}`): a rod and knob standing on its tunnel where the real car's is,
  in a leather boot, so the hand has something to shift. The rest of the interior is the model's.
- The mud splats on the outside of its windshield, and wipers sweep it.

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
- **AE86 Sprinter Trueno GT-APEX (zenki)**
  - 4A-GEU: Toyota's catalogue says 130 PS @ 6,600 and 149 Nm @ 5,200, but those are the old
    Japanese *gross* figures. The game uses the net figures, 120 PS and 142 Nm, because every other
    car here is rated net.
  - 940 kg kerb weight. Toyota's history page lists 1,215 kg, but that is the gross vehicle weight.
  - 7,500 rpm redline.
  - T50 gearbox 3.587 / 2.022 / 1.384 / 1.000 / 0.861, final drive 4.300.
  - An LSD was an option, so the game fits a mild one.
  - Wheelbase 2,400 mm, tyres 185/70R13.
  - The ~53/47 weight split is an *estimate*.
  - Sources: toyota-global.com (75 years, vehicle lineage), kurumaerabi.com catalogue, ateupwithmotor, aeu86.org, Wikipedia (Toyota AE86).
- **Silvia S15 Spec-R**
  - SR20DET: 250 PS @ 6,400, 275 Nm @ 4,800, 7,500 rpm redline.
  - 1,240 kg (1,250 with the aero kit or HICAS).
  - Aisin AZ6 six-speed 3.626 / 2.200 / 1.541 / 1.213 / 1.000 / 0.767, final drive 3.692.
  - Helical LSD as standard.
  - Wheelbase 2,525, track 1,470 / 1,460 mm.
  - The model has a widebody kit; the numbers are the stock car's.
  - The ~55/45 weight split is an *estimate*.
  - Sources: goo-net.com and 221616.com catalogues, Wikipedia (Nissan Silvia, ja and en), supercars.net, jdmbuysell.
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
- **Delta HF Integrale Evoluzione, Group A works car (1992)**
  - 1,100 kg, the FIA minimum for its class. Turbo engines count ×1.7, so its 1,995 cc counts as 3,392 cc.
  - The 38 mm turbo restrictor limits it to 300+ hp @ 6,000 and 420+ Nm @ 4,500 (4T magazine, March 1992). Other sites claim 330-365 hp; the game uses ~315 PS.
  - A 45/55 front/rear split through a viscous centre diff, with LSDs front and rear.
  - A six-speed Abarth gearbox. Its ratios aren't published, so they're *estimates*, and so is the final drive.
  - Wheelbase 2,480, track 1,575 / 1,565 mm.
  - It was nose-heavy; the 57/43 split is an *estimate*.
  - No anti-lag in the game, because none is confirmed for it.
  - The model is the Evo II road car (215 PS, 1,340 kg); the game runs it as the 1992 rally car, like the other rally cars.
  - Sources: FIA Appendix J 1992 (Art. 252-3.1, 255-4, 255-5.1.8.3), iceal.wikidot (reprints 4T #258), tech-racingcars.wikidot (Lancia Deltona), rallysportmag, Wikipedia (Lancia Delta HF).
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
   Paint parts shaped by a normal map (a door handle plate, a fuel cap) go in `"paint_normal"`:
   they're painted and keep their shape. If a model's materials come in too shiny (the Quattro's
   FBX dash and seats were half metal and mirror-smooth, so they read as chrome from the seat),
   `"finish"` sets the metal and roughness of the materials it names, where no texture drives them.
3. `blender -b -Y --python tools/import_car.py -- tools/cars/<id>.json <model> [texture dir]`
   writes `assets/models/cars/<id>/<id>.glb` and `parts.json`. `-Y` keeps any scripts in a .blend switched off.
   - The paint and the glass are never simplified, because simplifying them dents the panels.
     Only the hidden parts (the interior, the underside) are, and those keep their original shading.
   - Every part's normals are saved when the model loads and put back just before export. Cutting
     and joining parts otherwise spoils Blender's stored normals, and so does the glTF exporter's
     own clean-up of invalid geometry. Either way the panels came out blotchy, or looked caved in.
   - An interior worth keeping gets a `"cockpit"` key: where its steering wheel, gear lever and
     handbrake are (name patterns, a box round the loose pieces, or materials in a box) and what
     the gearbox is (`"h5"`, `"h6"`, `"seq"`, `"auto"`). They're cut out as parts of their own,
     each turning about its pivot, and `parts.json` says where they are, where the driver's eyes
     go and where the windshield is. `--parts` lists every part, where it is and how big;
     `--snapshot file.blend` saves the car as the tool sees it, to look at. Leave the key out and
     the game builds its own rally cockpit instead (an interior too rough to sit in).
4. Add the car's numbers to `SPECS` in `scripts/vehicle/car_specs.gd`, and a garage entry with `"model": "<id>"` in `scripts/game/catalog.gd`.
5. `tests/car_models_check.gd` checks it:
   - it builds;
   - it sits on its wheels;
   - its body clears the ground;
   - it does 0-100 in a sane time, with the right wheels driven.

   `tests/interior_check.gd` checks its interior: the driver's eyes are in the car on its wheel's
   side, the gloves are on its rim, the steering turns its wheel, the hand works its lever through
   the gates (or stays put in an automatic) and pulls its handbrake.
