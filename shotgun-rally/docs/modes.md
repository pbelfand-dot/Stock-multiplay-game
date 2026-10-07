# Modes: the touge and cut up

Two ways to drive besides the rally stages, both from **MODES** on the home screen
(`scripts/ui/modes_panel.gd`), both solo. They're stages like any other underneath: the
generator (`scripts/stage/stage_gen.gd`) makes a road of a different *kind*, the builder
(`scripts/stage/stage_builder.gd`) dresses it, and the game (`scripts/game.gd`) runs the
mode's rules on top. `scripts/game/modes.gd` holds the options each mode loads a stage with.

Command line (tests and pictures): `--solo --mode=touge [--dir=up|down] [--rules=time|drift]`
or `--solo --mode=cutup [--difficulty=easy|normal|hard|insane]`.

## Touge (a Japanese mountain pass)

**The road** (`StageGen` kind `"touge"`): about 5 km of two narrow lanes (6.1-6.7 m),
built from the same pieces as a rally stage but weighted to hairpins and tight S-bends
(typically 50 corners, 15-25 of them tighter than 20 m). The mountainside's slope runs
*along* the road (`TOUGE_RISE`), so the pass climbs (UPHILL) or falls (DOWNHILL) about
5 % of its length overall, 170-270 m, never steeper than 13 %. No jumps, bridges,
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
and rules (`Profile.mode_best`). **DRIFT**: points while the car slides more than 10°
off its direction of travel at over 30 km/h: (angle - 10) x km/h x 0.05 a second, times a
chain multiplier that grows from x1 to x4 the longer the chain lasts. 1.2 s of straight
driving banks the chain; hitting something, dropping a wheel off the road or resetting
loses it (`scripts/game/touge_rules.gd`). R resets to the road (+5 s) as on a stage.

## Cut up (highway traffic)

**The road** (`StageGen` kind `"highway"`): 8 km, four lanes one way (3.6 m each) with
1.5 m shoulders, long straights and sweepers of 900-2,500 m radius, grades of 4 % at most.
Concrete New Jersey barriers both sides the whole way (solid), lamp posts every 70 m,
distance gantries every 2 km, dashed lane lines.

**The traffic** (`scripts/stage/traffic.gd`): the registry's traffic cars
(`VehicleRegistry.traffic_pool()`: the generic saloon, crossover and people mover often;
the GLS 63, RS 6, M3 Touring, M8 and a standard-body Hellcat now and then), painted from their registry palettes,
their wheels turning. Only the stretch round the player is populated (160 m back to 650 m
ahead); a car that drops out of it comes back elsewhere in a gap. They're kinematic
(AnimatableBody3D: solid to the player's car, not simulated) and drive with:
- **IDM** (Intelligent Driver Model, Treiber et al. 2000) for speed: each has its own
  desired speed (the right-hand lanes slower), keeps a 1.3 s gap and brakes smoothly as
  it closes on the car ahead in its lane, the player included;
- **MOBIL** (Kesting, Treiber, Helbing 2007) for lane changes: it moves over when the
  other lane lets it go faster by a margin (with some politeness to whoever it would cut
  up, and a keep-right bias), never if the car behind there would have to brake harder
  than 3.5 m/s²; it eases across in 3 s.

A hit car stops where it is.

**The score** (`scripts/game/cutup_score.gd`): a NEAR MISS is passing a car with less than
the difficulty's gap between the bodies (1.6 m easy down to 0.7 m insane), at 80 km/h or
more and 10 km/h faster than it: 100 x closeness (1-3) x speed (1-2), times the combo.
Each near miss adds one to the combo; 4 s without one banks it. Over 140 km/h a trickle of
points joins the combo's pot. A CRASH (losing 4 m/s or more at once: a car or the barrier)
throws the unbanked pot away and costs 500. Bests are kept per difficulty.

| Difficulty | Cars per km | Their speeds | Near miss within | Lane changes |
|---|---|---|---|---|
| EASY | 7 | 70-110 km/h | 1.6 m | rarely |
| NORMAL | 12 | 80-120 km/h | 1.2 m | sometimes |
| HARD | 18 | 90-130 km/h | 0.9 m | often |
| INSANE | 26 | 90-140 km/h | 0.7 m | a lot |

## Tests

`tests/modes_check.gd` (in `tests/run_all.sh`): the touge's hairpins, widths, climb,
grade limit and determinism, its guardrail and props; the highway's lanes, sweepers,
grades and barriers; a minute of traffic with the player weaving through (no
collisions, lanes kept, speeds held, MOBIL lane changes, the population steady); the
score's near misses, combo, banking and crash; the touge's splits and drift chains; every traffic car loading car-sized on four wheels;
and a run of each mode in the game. `tests/drive_check.gd --kind=touge` has the
autopilot drive a pass.
