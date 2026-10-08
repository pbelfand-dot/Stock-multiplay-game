# Modes: the touge and cut up

Two ways to drive besides the rally stages, both from **MODES** on the home screen
(`scripts/ui/modes_panel.gd`), alone or online with up to eight friends (below). They're
stages like any other underneath: the
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
about 8 % on average: a 5 km pass drops ~430 m. Run at night (Settings' TIME OF DAY can make
it any hour). No jumps, bridges, villages or puddles: asphalt end to end. Each seed is its own pass with its own name
("KAZEMAKI PASS"), the same on every machine. **It never comes back past or under itself**:
every part of the road stays 55 m from every part that isn't its neighbour (`CLEARANCE`).
A whole layout is drawn up to 60 times for one that comes out clear; when none does (more
than half of the 5 km passes, all those hairpins), the road is grown a stretch at a time
instead (`_grow_pieces`): each new stretch is drawn again until it keeps clear, and when it's
boxed in the last one is taken back. (Before, the last try was kept: such a pass could run
under its own hillside, a wall in the middle of the road.)

**The look**: a solid yellow centre line (no overtaking, as on Japanese mountain roads),
white edge lines; white-painted guardrail wherever the road drops away *and* round the
outside of every tight bend; some concrete parapets; sugi cedar forest (tall, narrow,
dark spires); at each hairpin an orange curve mirror and yellow chevron boards pointing
the way it turns; kilometre posts; the pass's name board and a vending machine at the
start; a GOAL arch. No spectators, no co-driver.

**At night** the only light on the mountain is the street lamps' (`scripts/stage/street_lamps.gd`)
and the cars' own. A lamp stands before every tight bend (on its outside, behind the guardrail),
at the start and the finish, and never more than ~120 m from the next (about 12 a kilometre,
the posts there by day too). Each lamp's sodium head glows with a glare round it and a pool of
light on the road under it, faked (no real light: a pass of them costs next to nothing); the
four lamps nearest your car get real lights as well, so the car, the guardrail and the cedars
light up as you pass and fall dark behind. The cedars stand closer to the road than on a
rally stage (6.4 m from the centreline), a wall streaming past in the lights. No moon to speak
of, no glow on the horizon: black ridges, the forest fading into black. Every car's lamps are
on (`scripts/vehicle/car_lamps.gd`): a headlight beam down the road, the lamps' glow, red tail
lamps; in the driver's seat the dials glow just enough to see the wheel and your hands. (The
web and Chromebook build draws at most 12 lights on anything at once: the other drivers'
beams are the two nearest you, the rest glow.)

**The stray car** (`scripts/game/stray_car.gd`): now and then a local is out on the pass. It
turns up 260-420 m ahead (out of sight round a bend), 20-45 s into the run, then 40-90 s after
the last one has gone: mostly coming up the other way in its own lane (Japan drives on the
left: ours is the left lane, theirs the right as you look up the road), sometimes pottering
along ahead in yours at 32-46 km/h for you to get past. It takes the bends at a local's pace
(it brakes for the next 50 m: ~27 km/h in a hairpin), its lamps lit at night. Hit it and it
stops where it is, hazards blinking, until you're 140 m past. Each machine has its own (an
online racer's stray isn't in anyone else's world); the tests' autopilot runs without one.

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
making the car behind brake harder than 3.5 m/s²). On INSANE they come in
**packs**: 6-12 cars across all four lanes, close together, with
80-160 m of open road between packs: thread the pack, breathe, the next one. Cars **join
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
| NORMAL | 15 | 80-120 km/h | 1.2 m | sometimes | no |
| HARD | 30 | 85-130 km/h | 0.9 m | often | no: busy all the way |
| INSANE | 45 | 90-140 km/h | 0.7 m | a lot | 6-12 cars across the lanes, 80-160 m between |

HARD and INSANE are as busy as Assetto Corsa's No Hesi servers in the owner's clips (counted
from the frames: ~35 cars a km by day, ~45 at night, across the lanes).

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

## Online: street sessions (up to 8)

MODES > **HOST ONLINE (UP TO 8)**, then START a touge or a cut-up difficulty: the host's
machine opens a street session (`Net.host(..., "street", collide)`, port 7777). Friends join
from **ONLINE > JOIN** with the host's IP (as for a crew), each driving their own garage car:
every car is simulated on its own driver's machine and streamed to the others ~30 times a
second, played back smoothly 0.1 s behind (snapshot interpolation), with a name over it. The
host picks **COLLISIONS: ON** (you can hit each other) or **GHOSTS** (you drive through each
other). The grid: two abreast on a touge, across four lanes in cut up, rows 9 m apart. The
host starts the countdown for everyone (ENTER), as for a crew. Someone joining late loads the
stage the host is on: on the loop they drive straight in; on a touge they wait for the next
race (R at the results runs the pass again for everyone).

- **Touge online is a race to the bottom** (or the top): first across the line wins. The HUD
  shows your place (POS 2 / 5) as you go; each finish goes to every machine, and the results
  show THE RACE in order (time plus penalties) with gold, silver and bronze badges, and who's
  still on the way. No ghost online (your friends are the race).
- **Cut up online**: the host's machine runs the traffic round every player (as AssettoServer
  runs AI traffic per player on a No Hesi server) and sends each machine the cars round its
  driver 10 times a second (7 numbers a car); the others play it back, easing to it and
  dead-reckoning between updates. Hit a car and your machine tells the host, so it stops for
  everyone. Each driver keeps their own score; no rival battles online.

Command line (tests): `--host --street --mode=touge|cutup [--ghosts] [--min_racers=N]
--autostart --autopilot`, the others `--join=127.0.0.1 --autopilot`; `tests/run_all.sh` races
three machines down a touge (all three agree on the order) and runs three on the loop (the
host's traffic round each).

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
grade limit and determinism, 24 passes of 5 km all clear of themselves, its guardrail and
props, nothing solid on the road (a car-sized box swept down both lanes); the highway's lanes, sweepers,
grades and barriers; the LAKESHORE LOOP (closes exactly, radii, grades, the bridges and
tunnels where they should be, never near itself, s unwrapping lap after lap, the road,
towers and trees solid where a ray hits them); a minute of traffic with the player weaving
through (no collisions, lanes kept, speeds held, MOBIL lane changes, the population
steady), packs, the oncoming carriageway, ramp joins and exits; the score's near misses,
combo, banking and crash; highway battles (a challenge, a win, a loss); the touge's splits
and drift chains; every traffic car loading car-sized on four wheels; a reset landing in
the clearest lane; and a run of each mode in the game (cut up: a minute on the loop, then
END RUN); the night touge (lamps before every tight bend and never more than ~120 m apart,
lit only at night, the real lights following the car and fading away from the lamps) and the
stray car (turns up ahead, keeps its lane, slows for hairpins, stops when hit, goes once
you're past). `tests/drive_check.gd --kind=touge` has the autopilot drive a pass.
`tests/sim_check.gd` and `tests/feel_check.gd --cfg=street`: SIM street handling.
