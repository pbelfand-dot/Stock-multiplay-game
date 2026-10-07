# Modes: the touge and cut up

Two ways to drive besides the rally stages, both from **MODES** on the home screen
(`scripts/ui/modes_panel.gd`), both solo. They're stages like any other underneath: the
generator (`scripts/stage/stage_gen.gd`) makes a road of a different *kind*, the builder
(`scripts/stage/stage_builder.gd`) dresses it, and the game (`scripts/game.gd`) runs the
mode's rules on top. `scripts/game/modes.gd` holds the options each mode loads a stage with.

Command line (tests and pictures): `--solo --mode=touge [--dir=up|down] [--rules=time|drift]`
or `--solo --mode=cutup [--difficulty=easy|normal|hard|insane]`; `--street=sim|arcade` overrides
Settings > STREET HANDLING; `--seen_cars_only` keeps the no-AI cars out of screenshot traffic.

## Touge (a Japanese mountain pass)

**The road** (`StageGen` kind `"touge"`): about 5 km of two narrow lanes (6.1-6.7 m),
built from the same pieces as a rally stage but weighted to hairpins and tight S-bends
(typically 50 corners, 15-25 of them tighter than 20 m). It falls (DOWNHILL) or climbs
(UPHILL) the **whole way, never the other way** (`_touge_profile`): 7.5-12.5 % on the
straights and sweepers, easing to ~5 % round the hairpins (switchbacks are laid flatter),
about 8 % on average: a 5 km pass drops ~430 m. Night, mostly (the night look comes with the
graphics work). No jumps, bridges,
villages or puddles: asphalt end to end. Each seed is its own pass with its own name
("KAZEMAKI PASS"), the same on every machine.

**The look**: a solid yellow centre line (no overtaking, as on Japanese mountain roads),
white edge lines; white-painted guardrail wherever the road drops away *and* round the
outside of every tight bend; some concrete parapets; sugi cedar forest (tall, narrow,
dark spires); at each hairpin an orange curve mirror and yellow chevron boards pointing
the way it turns; kilometre posts; the pass's name board and a vending machine at the
start; a GOAL arch. No spectators, no co-driver.

**TIME ATTACK**: the clock, with a split every kilometre against your best run on that
pass (green ahead, red behind); the best time and its splits are kept per pass, direction
and rules (`Profile.mode_best`). Your record also drives with you as a **GHOST**
(`scripts/game/ghost.gd`): a see-through copy of the car you set it in, played back at the
same clock, that you can't hit (it fades out within 12 m of you and is gone within 4 m, so
at the start it isn't in your cockpit). A new record without resets replaces it (saved
beside the profile, `ghost_<key>.bin`, ~10 samples a second). The HUD shows the running
clock, the last split's gain or loss, the best and the speed (the chase camera has no dash). **DRIFT**: points while the car slides more than 10°
off its direction of travel at over 30 km/h: (angle - 10) x km/h x 0.05 a second, times a
chain multiplier that grows from x1 to x4 the longer the chain lasts. 1.2 s of straight
driving banks the chain; hitting something, dropping a wheel off the road or resetting
loses it (`scripts/game/touge_rules.gd`). R resets to the road (+5 s) as on a stage.

## Cut up: the LAKESHORE LOOP

**The map** (`scripts/stage/loop_gen.gd`, built by `scripts/stage/loop_builder.gd`; designed
by `tools/loop_map.py` into `data/maps/lakeshore_loop.json`): one fixed loop of divided
highway, 28.0 km round, the same every time, and it never ends: you load in, cut up as
long as you like, and END RUN in the pause menu ends it (the score, the best). Its
stretches, in the direction you drive:

| From | To | Stretch |
|---|---|---|
| 0 km | 6.6 km | the CITY: an expressway on a viaduct (to 5.9 km) between towers |
| 6.6 km | 14.0 km | the HILLS: cuttings, embankments, sugi forest and three tunnels (HIGASHIYAMA 0.6 km, KITAMINE 0.8 km, TAKIZAWA 0.5 km) |
| 14.0 km | 25.0 km | the LAKES: viaducts and three suspension bridges, KAIGAN GRAND (1,100 m main span, 1.76 km long), SHIRASAGI (620 m) and MINATO (560 m) |
| 25.0 km | 28.0 km | back into the CITY on a viaduct |

It's built as a real highway would be (AASHTO's figures): four 3.6 m lanes each way, a
3 m right shoulder, a 2 m median with a 1.07 m concrete barrier, curves no tighter than
the 667 m that 120 km/h needs, grades of 4 % at most, banked up to 4 % in the bends.
24 on- and off-ramps (both sides), 6 overpasses, 12 sign gantries, lamp posts, the
oncoming carriageway across the median. The bridges' towers, cables and hangers are
the real proportions (sag about 1/9.5 of the main span, towers about 0.11 of it above the deck).
Everything you can hit is solid; the materials are textured (asphalt, concrete, grass,
water) through `scripts/render/world_materials.gd` when the realistic-graphics work
provides it, noise-textured fallbacks otherwise.

**The traffic** (`scripts/stage/traffic.gd`): the registry's traffic cars
(`VehicleRegistry.traffic_pool()`), painted from their palettes, their wheels turning.
Only the stretch round the player is populated (160 m back to 650 m ahead); cars that
drop out come back in a gap. They're kinematic (solid to your car, not simulated) and
drive with **IDM** (Treiber et al. 2000: their own desired speeds, a 1.3 s gap, smooth
braking) and **MOBIL** (Kesting et al. 2007: they change lane when it pays, politely, never
making the car behind brake harder than 3.5 m/s²). On HARD and INSANE they come in
**packs**: 5-9 (hard) or 8-16 (insane) cars across all four lanes, close together, with
160-300 m of open road between packs: thread the pack, breathe, the next one. Cars **join
from the on-ramps** (merging into a gap in lane 0) and **leave by the off-ramps**. The
**oncoming carriageway** has its own traffic (for the view; the median barrier keeps it
from you).

**The score** (`scripts/game/cutup_score.gd`): a NEAR MISS is passing a car with less than
the difficulty's gap between the bodies (1.6 m easy down to 0.7 m insane), at 80 km/h or
more and 10 km/h faster than it: 100 x closeness (1-3) x speed (1-2), times the combo.
Each near miss adds one to the combo; 4 s without one banks it. Over 140 km/h a trickle of
points joins the combo's pot. A CRASH (losing 4 m/s or more at once: a car or the barrier)
throws the unbanked pot away and costs 500. Bests are kept per difficulty.

| Difficulty | Cars per km | Their speeds | Near miss within | Lane changes | Packs |
|---|---|---|---|---|---|
| EASY | 7 | 70-110 km/h | 1.6 m | rarely | no |
| NORMAL | 12 | 80-120 km/h | 1.2 m | sometimes | no |
| HARD | 18 | 90-130 km/h | 0.9 m | often | 5-9 cars |
| INSANE | 30 | 90-140 km/h | 0.7 m | a lot | 8-16 cars |

**HIGHWAY BATTLES** (`scripts/game/rivals.gd`, like Tokyo Xtreme Racer's): now and then a
RIVAL shows up in the traffic, a garage car with a nickname ("BLUE THUNDER", "TOFU
RUNNER" ...), cruising a little under your pace. Catch it, get within 45 m right behind it
and **FLASH YOUR LIGHTS (H, or the left shoulder button)**: 3, 2, 1, GO, and it's a race
through the traffic to a FINISH gate 3 km up the road. First through wins; so does leaving
the other 500 m behind; after 3 minutes whoever's ahead does. A win pays into the score
(2,000 to 10,000, by the rival's level 1-5). Rivals drive in the traffic like you (the
same lanes, the same cars in the way): power against drag up to their real top speed,
picking the most open lane. The results show rivals beaten and lost.

A hit car stops where it is. R (+5 s) puts you back in the lane with the most room.

## Street handling: SIM or ARCADE (Settings)

**STREET HANDLING (CUT UP, TOUGE)** in Settings: **SIM** out of the box, **ARCADE** to drive
these modes like the rally (`Config.street_handling`). Rally stages always use TYRE GRIP.

SIM is Assetto Corsa-like: each car on the road tyres it really has (`TireModel.street`,
`Catalog.street_grip`):
- **its real grip**: the asphalt peak set so the car holds its real skid-pad figure, measured
  where magazines published it (GR Supra 1.07 g, GT-R 1.00, Hellcat 0.92-0.95, 911 GT3 RS
  1.24), estimated by age and tyre otherwise (a 1970s car ~0.78, 1980s ~0.82, 1990s
  0.84-0.92, today's sports cars ~1.0, economy cars ~0.86; race cars on slicks 1.45-1.7, their
  wings adding downforce on top);
- **a road tyre's shape**: the grip peaks at 7.5° of slip angle (production tyres 6-10°,
  Milliken; Cup-type 6°, slicks 4.5°), a sliding tyre keeps 85 % (as Assetto Corsa's street
  tyres), the slip ratio peaks at 12 %, twice the load gives ~12 % less grip per newton;
- **braking** ~1.1x the cornering grip (as the magazines' tests show); the brakes can lock
  the tyres, and the brake balance follows the weight at the stop (a 911 brakes on its rear
  tyres too);
- **the aids**: no drift assist, no countersteer help (the car slides as the tyres let it);
  HIGH-SPEED STABILITY as its Settings switch says (on out of the box: it catches a clip in
  traffic); factory ABS and traction control where the real car has them as standard (the
  classics, the prototypes and the rally cars without; their switches still force them on;
  no traction control in the touge's DRIFT rules).

Measured (`tests/sim_check.gd`, a 76 km/h ramp-steer skid pad and 100-0 km/h): the Supra
1.06 g and 37 m, the GT-R 1.00 g and 36 m, the AE86 0.80 g and 43 m, the GT3 RS 1.28 g and
29 m; ARCADE gives the same road cars 1.4-1.6 g (the GT3 RS 1.96). What SIM means at the wheel: real cars slide
earlier and need smoother hands; with HIGH-SPEED STABILITY switched off, a clip on the rear
corner at 150 km/h spins the car, as it would in Assetto Corsa. ARCADE is there for those who'd
rather.

## Tests

`tests/modes_check.gd` (in `tests/run_all.sh`): the touge's hairpins, widths, climb,
grade limit and determinism, its guardrail and props; the highway's lanes, sweepers,
grades and barriers; the LAKESHORE LOOP (closes exactly, radii, grades, the bridges and
tunnels where they should be, never near itself, s unwrapping lap after lap, the road,
towers and trees solid where a ray hits them); a minute of traffic with the player weaving
through (no collisions, lanes kept, speeds held, MOBIL lane changes, the population
steady), packs, the oncoming carriageway, ramp joins and exits; the score's near misses,
combo, banking and crash; highway battles (a challenge, a win, a loss); the touge's splits
and drift chains; every traffic car loading car-sized on four wheels; a reset landing in
the clearest lane; and a run of each mode in the game (cut up: a minute on the loop, then
END RUN). `tests/drive_check.gd --kind=touge` has the autopilot drive a pass.
`tests/sim_check.gd` and `tests/feel_check.gd --cfg=street`: SIM street handling.
