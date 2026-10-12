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

## The CARS grid (October 2026)

The owner's sketch: every car on one grid, a column for each kind (`scripts/game/car_columns.gd`,
by the registry's category and role), and every car free (`Profile.owns` says so for any garage car;
liveries, wheels and upgrades still cost credits).

| Column | What goes in it | Cars |
|---|---|---|
| STREET | the road cars (JDM, EURO, AMERICAN, the SUVs): the touge's | 38 |
| GT3 | the race cars (`race` category: GT3, DTM, GT2, the prototypes); the track's GT class takes its 12 | 15 |
| F1 | the Formula cars (`formula` role): the FORMULA class | 3 |
| RALLY | the rally cars: PLAY NOW and the Shotgun Series | 8 |
| HYPERCARS | the `hyper` category (the ONE, the 800, the Bolide ...): any mode but the touge | 10 |

Each tile's picture is the car's own 3D model in its own colours, three-quarters from the front in a
plain studio (`tools/car_thumbs.gd` writes `assets/ui/cars/<id>.webp`; run it again when a car's
model changes). A mode's START opens the grid on its column with only its cars to pick
(`CarColumns.for_mode`); cut up takes any car. With `--seen_cars_only` (screenshots) the no-AI cars'
tiles show their names only. `tests/car_grid_check.gd` and the menu test (`tests/menu_garage_check.gd`)
drive it.

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
| ROTORA FD | the model's, very plain (a black dash and floor tray, the seat backs, a spokeless wheel ring) | left | 5-speed H-pattern, right hand: a lever added (none modelled) | none modelled |
| ROTORA FC | none: the model has no cabin (glass and door cards round an empty shell): the bonnet camera | | | |

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

### The live instruments (`data/dash/`)

`scripts/vehicle/dash_live.gd` makes a car's own instruments work, from its spec in
`data/dash/<model>.json`; nothing of the model's look is replaced. A screen that has a picture of
its own keeps it (the readings that change are drawn over it where the model painted them); a
screen the model left blank gets a board laid exactly on its faces (measured by rays from the
driver's eye) with a live page in the car's accent colour. Every car with its own cabin has a dome
light (L), backlit screens at night and the warning lamps; the luxury cars have ambient lighting.

| Garage name (model) | What's live | Limits |
|---|---|---|
| GRAND SUV 63 (the GLS 63) | the two round dials (needles), the screen between them, the floating centre screen (map / driving data), ambient | the model's cabin is the previous GLS's; its dials are blank, so the dials are drawn |
| AFFALTER S EXECUTIVE (Maybach S) | the driver display (two dials in rose gold), the portrait centre screen (its menu as tabs across the top), warm ambient | the screens are blank in the model; the windscreen was modelled in the black trim's material and is made glass by `glb_patch` |
| KASTEN 63 (G 63) | the widescreen: two dials behind the wheel, the centre screen beside them, ambient | blank in the model |
| KAISER 7X (X7) | the curved display's two halves (a BMW cluster, the iDrive), ambient | a low-detail cabin: the display is laid on its plain dash slab |
| KAISER 5 G (M5 G90) | its own painted M cluster made live (the digits covered, the speed and gear in their frames, the scales filling), the iDrive under it | the painted scales' numbers stay as painted |
| KAISER 5 TOURING (M5 Touring) | the curved display: a BMW cluster and the iDrive, on the model's blank quads | |
| KAISER 5X (X5 M) | the painted speedometer's and rev counter's needles turn (the painted ones taken out of a copy of the texture), the iDrive, a night glow | the needles are flat (drawn on the dial), not meshes |
| KAISER 320 (320i) | its own painted cluster made live (the speed, mph, gear and clock in their places, the speed and revs filling its hexagon's two bent bands), the centre screen; the buttons backlit; ambient | the map in the cluster stays as painted |
| TEMPESTA URSA (Urus Performante) | the digital cluster and the centre screen, in its green, ambient | blank in the model |
| VIERRAD R7 (RS 7) | its painted Virtual Cockpit made live (the revs band climbing, the speed and gear), the MMI screen's pages | the climate screen stays as painted |
| KOMBI V8 (RS 6 Avant) | the Virtual Cockpit and the upper MMI screen, on the model's blank quads | |
| AFFALTER GT BLACK | the binnacle's cluster (two dials), the centre screen, red ambient | an untextured cabin |
| WOKING 800 (Senna) | the driver display and the portrait centre screen (tabs across the top) | |
| WOKING 720 GT3 | the race display on the column | |
| RAIDEN GT (GT-R) | its painted speedometer's and rev counter's needles turn, each along its own scale (the speedometer's uneven one, 20 to 100 in 20s then 130 to 340 in 30s, measured tick by tick: `marks`), the painted needles taken out of a copy of the texture (the striped face copied from beside them along its stripes: `cover_off`); the centre screen's pages; the cluster glows at night | the two small gauges' needles stay as painted |
| AFFALTER GT3 (AMG GT3 Evo) | its own race display (stored upside down in its texture: `flip_v`) made live: the speed, the gear, the lap time to the thousandth, the fuel in litres (Track Mode's tank, else a share of RaceSim's 120 l default), the water, oil and gearbox temperatures warming up, the ABS and TC maps; the PITSPEED ACTIVE banner only with the pit limiter on (the speed in it to a tenth); the lamps only while they're on (dipped beam at night, main beam flashing, F-Pump OFF in the bulb check) | V Batt (14.2), MAP and the blank time box stay as painted |
| BOLT W16 (Bolide) | its own race display made live (UVs a tile over: `uv_wrap`): the revs filling the bar under the REF scale, the gear, the lap time, the oil temperature climbing its uneven scale as the engine warms; the model's own LED blocks lit (`leds`): the fuel gauge's 14 red ones with the fuel, the five green and one red over the rev bar as shift lights | |
| ELFER R (911 GT3 R, 992) | its own race display made live (its UVs sit a tile over in the texture: `uv_wrap`): the gear in the big middle box, the speed over it, the oil temperature and pressure, the water temperature, the lap time, the fuel left in litres, the ABS and TC levels, the four tyres' temperatures in Track Mode ("--" elsewhere), DRY or WET | MAP / AC / THR / FC1, the water pressure, Lap, Time Diff and Pred. Time stay as painted |
| AFFALTER A45 S (A 45 S) | its own painted driver display made live: the g-meter's dot, both rev scales filling (red past 6,800), the speed, the accelerator and brake pedals' percentages in the panel that names them, the fuel bar emptying and the range over it, the selector's letter lit (the others dimmed) | the drive-mode screen and the temperature bar stay as painted |
| AKATSUKI V (GR Supra A90) | its own painted driver display made live, though the texture holds it sideways (`transpose`): the painted rev needle hidden under the dial's face copied from further round and a live one turning with the revs, the gear and the box's mode where the painted "1 M" was, the speed over km/h, the clock | the outside temperature and the car picture stay as painted |
| MOCHI e (Honda e) | its own screens kept: the battery's percentage live in the driver display's ring and on the charging page; the speed, the gear (D), the range, the clock and the lamps on the display's dark sides | the EV menu and the media page stay as painted |
| KAISER 4 WB, KAISER 2 WB, KAISER T, KAISER 8 GC | a digital cluster and the iDrive pages (the M4 over its own texture; the M2's, M3's and M8's blank screens get panels) | |
| KAISER 5 E (M5 E34) | its own modelled needles (speed, revs, fuel) turn, the dials glow orange at night, the console clock | |
| KAISER 235 GC (M235i Gran Coupe) | its own painted cluster made live (the speed, gear, range and clock in their places; both bands filling along their painted outlines, each point carrying its value); the iDrive's own picture kept, the live road round the car in its painted map's window (`map`: day colours, the streets round about, nothing drawn past the window's edges), its clock and today's date; ambient | the cluster's map, the media card and the climate figures stay as painted |
| KAISER 3X (X3 M40i) | its own painted cluster made live (the speed, mph, range, clock and gear; both bands lighting up along their dark red strips); the iDrive shows its own welcome page for the first seconds after the engine starts (`intro`), then the centre screen's pages; ambient | the cluster's map, the electric range and the outside temperature stay as painted |
| KAISER 2 CARBON (M2 with a carbon kit) | the M2's curved display as a panel (its cabin is the M2's, 4 cm higher in this model): a BMW cluster and the iDrive pages; ambient | the wheel's rim hides most of the cluster from the driver's eye |
| UNO HYBRID (AMG ONE) | its steering wheel turns whole now: the model's cut took only the yoke's centre, so its grips, buttons, LED row and screens are moved onto it (`wheel_parts`); its own race display (stored upside down) made live: the rev scale lit only up to the revs, the gear in its ring, the speed over km/h, the battery and fuel bars emptying; the wheel's 12 LEDs as shift lights, green, red and blue (`leds` with a row's own `color`); the centre screen shows its own AMG splash, then the centre screen's pages | the CHARGE and POWER arcs and the wheel's two small screens stay as painted |
| ELFER RS (911 GT3 RS, 992) | its steering wheel's chrome buttons and switches turn with it now (left in the body by the model's cut: `wheel_parts` within its rim, `disc`); the central rev counter's modelled needle turns; its two screens' own pictures (a tile over, upside down, painted squashed) made live: the speedometer's needle along its painted scale (`sy`: an elliptical dial), the speed in its digital slot, the oil temperature, the water temperature and fuel needles (`min`: a scale not from 0), the range | the rev counter's face is blank grey in the model; the drive-mode dial stays on Track |
| CENTURIA 16 (Chiron by a tuner) | its own modelled speedometer needle turns along the painted 500 km/h scale as the driver sees it (`marks` on a modelled needle: each 50 km/h's turn measured from the driver's eye); the left screen's own rev counter lights its dotted arc with the revs; the right screen's own Chrono page shows the lap time; the dials and screens glow at night; turquoise ambient | the power scale and the odometers stay as painted |
| VENTO CINQUE (Zonda Cinque) | its own modelled needles turn, each in the plane of its dial's face: the rev counter's and the speedometer's along their scales as the driver sees them (`marks`), the fuel and water gauges; the 14 green and 4 red LEDs over the dials as shift lights; a few cluster pieces the model had put in the front left brake caliper (they swung with the steering) moved back into the body (`body_parts`); the dials glow at night | the cluster's glass is milky in the model (`glb_patch`), so the dials look washed out by day |
| WOKING 600 SPIDER (600LT) | boards on its blank driver display (a cluster in McLaren orange) and portrait centre screen (tabs across the top); orange ambient | blank in the model |
| GHOST J (Jesko) | a board on the screen on its steering wheel, turning with the wheel (`on_wheel`), and on its centre screen, in red; red ambient | an untextured cabin |
| PUEBLO 392 (Durango SRT 392) | boards on its blank cluster plate: the speedometer and rev counter as round dials either side of a small digital cluster; the centre screen's pages | an untextured cabin |
| STROMER 4 (ID.4) | boards where its displays sit (none are modelled): the small driver display on the column's hood, the centre screen on the dash; electric: the charge, the range, D | a low-detail cabin |
| WARHAWK 707 (Grand Cherokee Trackhawk) | its needles were cut out with the steering wheel and swung round with it: moved back into the body (`body_parts`); the centre screen's own radio page (stored mirrored: `flip_h`) with its clock live | the needles stay still; the cluster's own picture is mapped too unevenly to draw on |
| BRAWLER 70 ('70 Camaro) | its speedometer's and rev counter's own photographs made live: a needle along each painted scale (the mph speedometer's uneven one: `marks`), the photographed needles taken out of a copy of the picture; the overlay drawn on both sides of the dials' double-sided faces (modelled facing away); the dials glow at night | the three small console gauges stay as photographed |
| AFFALTER SLR 722 | its own modelled needles turn along the painted scales (the speedometer to 360, the rev counter, the water temperature warming up, the fuel gauge anticlockwise); they're thin parts of the chrome trim's material, so only small parts count (`max_size`) and the steering wheel's chrome still turns with the wheel; the dials glow at night, the needles lit; the clock and the gear on the big dials' small displays | |
| SYLPH S15 (Silvia S15) | its own modelled needles turn, each about its dial's middle along its painted ticks (`marks`): the rev counter's (0-2,000 rpm closer spaced), the speedometer's, the fuel and water gauges, and the boost gauge in its pod by the windscreen pillar, reading the turbo (`boost`: a vacuum at idle and off the throttle, boost with the throttle and the revs); the rev counter's small LCD is the clock, the speedometer's the trip meter (`trip`); the dials glow at night | |
| LANCER IX (Lancer Evolution IX) | its five dial faces are modelled with UVs of their own but blank (plain white): each is a dial page in the car's style, white on black with red needles: the rev counter (red from 7,000), the speedometer, the water temperature, the fuel and the boost (`dial` pages for any reading, with their own sweep and end words) | blank in the model |
| HAKO 2000 (Skyline C10) | its own modelled needles turn (thin parts of the dash's material near each hub cap, the needles' tails with them: per-needle `grow`): the two big aftermarket boost gauges behind the wheel read the turbo along their painted psi and inHg ticks (`marks` as the driver sees the faces, which the model maps turned half round), and the little clock's one hand shows the hour (`clock_h`) | the four small gauges (oil temperature, volts, oil pressure, the TURBO arc) stay still: their scales are too small in the texture to measure |
| VIERRAD S1 (Sport quattro S1) | its cluster photograph made live: the speedometer's (resting on 20) and rev counter's needles along their measured ticks (`marks`), the boost, fuel and battery voltmeter needles (`volts`), each photographed needle taken out of a copy of the picture; the LCD clock shows the time, the mechanical trip counter the km driven; the dials glow at night | the warning lamp grid stays as photographed |
| OCELOT R1 (Puma Rally1) | its blank display on the column gets a cluster of its own (the revs band, the speed, the gear, the clock, the stage time, the lamps) in orange; the same material's sliver on the wheel left as it is (`off_wheel`) | the wheel's centre bar hides much of the screen |
| NIMBUS EG (Civic EG) | its untextured cabin's glossy cluster face gets a panel: two round dials (speed, revs) with the gear and the fuel between them | an untextured cabin |
| TORO R26 | its steering wheel's near-blank screen made live: the revs bar across the top, the gear, the speed, the fuel in litres, the lap time | |
| VEE-F 26 | its steering wheel's screen made live: the gear in green where its painted digits were, the revs filling the STRAT boxes, the speed and the lap time above | |

A cabin whose screens are part of a texture shared with everything else (most of the rest of the
own-interior cars) has the dome light, the lamps and the night glow but no live pages yet.
`tests/dash_check.gd` checks every spec: the boards and panels are found and sized to their
screens, the needles point at their scales' ends at the top values, the centre screens flip pages
and are laid out for their shape.

### Driver fit (F9)

`scripts/vehicle/fit_debug.gd` works out where the crew go in each car from its own interior: the
driver's eyes (the seat camera) and the co-driver's, the hip point, the hands at a quarter to three
on the rim, the gear lever's pivot and knob and the handbrake's grip, the pedals (estimated under the
column: no model marks its pedals), where the driver gets in (outside the driver's door) and the
chase camera's anchor. **F9** in a stage (or `--fit_debug` from the start) draws them over the car,
seen through the body, with each wheel's centre and suspension travel, the collision boxes and an
arrow along the car's forward. `tests/interior_check.gd` judges the fit in every car with an
interior: the head under the roof, the wheel 0.35-0.9 m in front of the eyes, the hands within
reach of the shoulders, the pedals 0.55-1.3 m ahead of the seat and below it, the door outside the
body.

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
   - A texture the model asks for that isn't where it says is found by name in the texture
     folders: also under a longer name (`x_(Personalizado).png` for `x.png`) or a cut-short one
     (`x_B.png` for `x_BaseColor.png`). One found nowhere is taken off its material (which keeps
     its colour); left on, it exported as a texture with no image and Godot refused the file.
     With `"tex_format": "webp"`, grayscale, 16-bit and float images are made 8-bit RGBA first
     (Blender can't write those as WebP).
   - Materials the model marks as blended but that aren't see-through come out opaque, or cut out
     where their texture has hard-edged holes (`tools/glb_alpha.py`, run on every car it writes).
     Game rips often mark every material blended, and Godot draws those in its transparent pass:
     a second pass each, and the car's own glass sorts wrong against them. Only real soft alpha
     (glass, soft decals) stays blended. The tool also runs on its own on a GLB already written:
     `blender -b -Y --python tools/glb_alpha.py -- <car>.glb`.
   - Every part's normals are saved when the model loads and put back just before export. Cutting
     and joining parts otherwise spoils Blender's stored normals, and so does the glTF exporter's
     own clean-up of invalid geometry. Either way the panels came out blotchy, or looked caved in.
   - An interior worth keeping gets a `"cockpit"` key: where its steering wheel, gear lever and
     handbrake are (name patterns, a box round the loose pieces, or materials in a box) and what
     the gearbox is (`"h4"`, `"h5"`, `"h6"`, `"seq"`, `"auto"`). They're cut out as parts of their own,
     each turning about its pivot (the wheel's column found from its shape, or given as `"axis"`
     where the shape misleads: a squat race wheel on a deep hub), and `parts.json` says where they are, where the driver's eyes
     go and where the windshield is. `--parts` lists every part, where it is and how big;
     `--snapshot file.blend` saves the car as the tool sees it, to look at. A model with no cabin
     at all gets `"view": "hood"` instead: the game drives it from a camera low over its bonnet and
     makes no cockpit up for it (no garage car is left on the game's made-up rally cockpit but the
     four on the shared rally body, whose cockpit is theirs). The converter can be run again on a
     GLB it made (a car whose source archive isn't kept): the glass and rims it renamed aren't
     renamed twice.
   - Lamps and lenses that came without their colours: `"glow"` makes a lamp glow in its own
     colour (its texture), `"remat_boxes"` with `"new": true` gives the faces of a material in a
     box a new one (the back half of a lens shared front and back made a red lens), or with
     `"copy_of"` a copy that keeps its textures. `"glb_patch"` (`tools/glb_patch.py`) changes
     materials in the written GLB, JSON only: a colour, a glow (from the material's own texture
     or its glow map), the colour texture taken from the glow map, the alpha mode, two-sided.
     It runs at the end of every conversion and on its own on a GLB already made:
     `python3 tools/glb_patch.py tools/cars/<id>.json`.
4. Check how it looks:
   - `blender -b -Y --python tools/model_audit.py -- <id>` checks the GLB by numbers (what Godot
     will draw: one-sided faces culled from behind, blended and cut-out materials by their alpha):
     all four wheels, round about their axle and on centre (else they wobble), a tyre all round, a
     rim you can see from outside (not see-through, not inside out, not turned to face the car,
     the same on both sides), no wheel left behind in the Body, red tail lights you can see from
     behind (not glowing white), no big material that lost its colour (a white "black"), nothing
     invisible that isn't glass. It's how the cars whose licences say no AI are checked.
   - `xvfb-run -a godot --path . --resolution 1280x800 -s tools/car_shots.gd -- --out=<dir> --ids=<registry id>`
     takes four pictures of it in the game's light (front and rear three-quarter, the side,
     straight behind; `--set=wheels`: each wheel close up).
5. Add its registry entry, `data/vehicles/<id>.json` (`docs/vehicles.md`): the researched numbers in `specs`,
   its `physics` from `tools/vehicle_physics.py` (power, weight, drive, engine kind, chassis), a `garage` and/or
   `traffic` block, its `source` and `limitations`; `python3 tools/vehicle_registry.py check`, and
   `python3 tools/vehicle_credits.py > docs/CREDITS.md`.
6. `tests/car_models_check.gd` checks it:
   - it builds;
   - it sits on its wheels;
   - its body clears the ground;
   - it does 0-100 in a sane time, with the right wheels driven.

   `tests/interior_check.gd` checks its interior: the driver's eyes are in the car on its wheel's
   side, the gloves are on its rim, the steering turns its wheel, the hand works its lever through
   the gates (or stays put in an automatic) and pulls its handbrake.

## The model audit (October 2026)

Every car was checked with `tools/model_audit.py` and pictured with `tools/car_shots.gd`. What was
wrong and how each was put right (in its `tools/cars/<id>.json`):

- **CENTURIA 16 (Chiron):** its left wheels were inside out on one-sided materials, so their
  rims vanished from outside (you saw the hollow back of the wheel and the brake); the old
  `turn_wheels` made it worse (it turned the brakes round too). Now: no turn, the wheels two-sided.
  Its lamps glowed white (a white colour texture under a glow map holding the real colours): the
  colour now comes from the glow map, so the tail lights are red.
- **HELLHOUND WB (Hellcat Widebody):** "Dark" and "Light Glass" came with no colour (white), so
  the tail lamps were two white bars; now a dark housing behind clear glass with the red ring.
- **HELLHOUND (Hellcat, traffic):** its tail lamps lost their colours (grey); now red lenses.
- **KAISER 8 (M8):** its red tail glass was grey and its arch liners, diffuser and trims white;
  now red lights and black trim.
- **HACHI (AE86):** its lamp covers' texture wasn't linked in the FBX (grey lenses); now linked,
  with its red, amber and clear. (The converter also kept a retextured image from being dropped
  as missing: the seatbelts had lost theirs.)
- **OCELOT (Puma Rally1):** one lens material front and back, set to chrome; the back half is a red lens.
- **BOLT W16 (Bolide):** its tyres were only their lettering decal (see-through, silver-white):
  now black rubber; a see-through cockpit (carbon at 27 % alpha) made solid; its X tail light
  glowed white at 200x: now red.
- **UNO HYBRID (AMG ONE):** its lamps had no colour and no glow: the back ones are red now.
- **VENTO CINQUE (Zonda):** white tail lamps under opaque white covers: red, the covers clear.
- **VIERRAD (Sport quattro):** its red tail glass was nearly black: red glass now.
- **SYLPH (S15):** a white driver's seat; its red lamp ring glows.
- **ELFER R EVO (GT3 R evo), traffic minivan:** no AI, fixed from the numbers only: the evo's
  lamps glowed white (now their own colours); the minivan's black trim, rubber and underside were
  white (now the colours the sedan from the same set has).
- **BISCIONE (Alfa 155), MOCHI e (Honda e):** grilles and decals with hard-edged alpha now cut out
  (the alpha fixer had treated every WebP-textured car's materials as opaque: it couldn't read
  WebP images; fixed). Parts that are never see-through (rims, tyres, chrome, carbon) stay opaque
  whatever their texture's alpha holds (often a shine mask in game rips).

## The SUVs (October 2026)

Six more garage cars, each also uncommon-to-rare highway traffic (details, numbers and test results:
`docs/VEHICLE_REPORT.md`, "Six SUVs"; sources: `docs/CREDITS.md`):

| Garage name | Based on | Interior | Driver sits | Gears (the hand) |
|---|---|---|---|---|
| STROMER 4 | VW ID.4 Pro Performance (2021), electric | the model's, simple (one black palette, lifted to dark grey) | left | one gear (EV): both hands on the wheel |
| WARHAWK 707 | Jeep Grand Cherokee Trackhawk (2018) | the model's, full (textured dash, GPS screen, dials) | left | automatic: both hands on the wheel |
| PUEBLO 392 | Dodge Durango SRT 392 (2021) | the model's, full (no textures in the package: plain dark looks) | left | automatic |
| KAISER 5X | BMW X5 M F85 (2016) | the model's M interior (textured) | left | automatic |
| KAISER 7X | BMW X7 M50i G07 (2020) | the model's, simple (as the ID.4: same author) | left | automatic |
| KASTEN 63 | Mercedes-AMG G 63 W463 (2020) | the model's, full (diamond-stitched seats, wide screen) | left | automatic |

Their chassis: `sport_suv` (WARHAWK, KAISER 5X: firm, sharp), `suv` (PUEBLO, KAISER 7X, STROMER:
heavy, calm), `tall_suv` (KASTEN: soft and tall, it rolls and pitches).

## The street batch (October 2026)

Fourteen garage cars from the owner's private batch (details, numbers and test results:
`docs/VEHICLE_REPORT.md`, "The street batch"). All are automatics or dual clutches (both hands stay
on the wheel), left-hand drive:

| Garage name | Based on | Interior |
|---|---|---|
| TEMPESTA URSA | Lamborghini Urus Performante (2023) | the model's own |
| WOKING 600 SPIDER | McLaren 600LT Spider (2020) | the model's own |
| AFFALTER SLR 722 | Mercedes-Benz SLR McLaren 722 (2006) | the model's own |
| AFFALTER GT BLACK | Mercedes-AMG GT Black Series (2021) | the model's own (low-detail, untextured: flat dark greys) |
| VIERRAD R7 | Audi RS 7 Sportback C8 (2020) | the model's own |
| AFFALTER A45 S | Mercedes-AMG A 45 S (2023) | the model's own |
| KAISER 5 TOURING / KAISER 5 G | BMW M5 G99 Touring / G90 saloon (2025) | the model's own |
| KAISER 3X | BMW X3 M40i G45 (2024) | the model's own |
| KAISER 235 GC | BMW M235i Gran Coupe F44 (2019) | the model's own |
| KAISER 2 CARBON | BMW M2 G87, ADRO carbon kit (2023) | the model's own |
| AFFALTER S EXECUTIVE | Mercedes-Maybach S-Class Z223 (2021) | the model's own |
| WOKING 800 | McLaren Senna (2018) | the model's own |
| WOKING ONE | McLaren P1 (2013) | the model's own (fitted by measurement: handled as no-AI) |

Their chassis: `sport_suv` (URSA, 3X), `sport` (the rest).

And one more from the internet batch: **KAISER 320**, a 2023 BMW 320i xDrive saloon (G20) with its own
interior, an automatic, left-hand drive, on the `road` chassis (details: `docs/VEHICLE_REPORT.md`,
"The BMW 320i").

## Suspension: how the road cars lean (October 2026)

The road cars (every chassis class but the rally cars' own) work out their suspension from their own
weight instead of scaling the rally car's (`CarSpecs._road_suspension`, the numbers in `CHASSIS`):

- **springs** for a ride frequency on each corner's share of the weight: 1.15-1.35 Hz on the SUVs,
  1.4-1.5 a road car, 1.65-1.75 a sports car, 2.4-2.6 a GT3, ~3 a prototype;
- **dampers** a share of critical on those springs (softer in bump than in rebound), so a bump or a
  lane change settles in a bob or two;
- **anti-roll bars** for a roll gradient (how far the body leans per g of cornering) with the centre
  of mass at a real height (0.74 m the G 63, 0.62-0.66 the other SUVs, 0.52 a road car, 0.46 a
  sports car, 0.40 a GT3), the front axle taking 58-66 % of the roll stiffness (road cars push
  before they slide);
- room to lean and nod before the bump stops.

In street mode the road cars no longer get the rally car's tarmac setup (springs and bars x1.5,
for gravel cars on asphalt); the rally cars keep it. Measured (`/root/srwork/feel` harness, steady
0.6 g at 100 km/h; braking at 0.6 g):

| Car | Body roll (deg per g), before -> after | Braking nose dive (deg per g), before -> after |
|---|---|---|
| KASTEN 63 (G 63) | 1.5 -> 5.1 | 1.4 -> 3.3 |
| KAISER 7X, PUEBLO 392, STROMER 4, GLS | 1.3-1.7 -> 4.1-4.3 | 1.0-1.2 -> 2.3-2.7 |
| KAISER 5X, WARHAWK 707 | 1.1 -> 3.3 | 0.8 -> 1.9 |
| BRAWLER 70 (road) | 1.2 -> 2.9 | 0.7 -> 1.9 |
| Sports cars (Supra, M4, Hellcat) | 0.6-0.7 -> 2.1 | 0.4-0.5 -> 1.1-1.5 |
| ELFER RS (GT3 RS) | 0.3 -> 1.1 | 0.2 -> 0.7 |

Real cars lean about 3.5-5 deg/g (an SUV), 2-3 (a sports car) and 1-1.5 (a GT3). The skid-pad grip
and the 100-0 stops are unchanged (`tests/sim_check.gd`), and the street feel checks, drifting,
the touge drive, tyre setups and handling tests all pass.
