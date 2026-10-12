# Modes: the touge, cut up and Track Mode

Three ways to drive besides the rally stages, both from **MODES** on the home screen
(`scripts/ui/modes_panel.gd`), alone or online with up to eight friends (below). They're
stages like any other underneath: the
generator (`scripts/stage/stage_gen.gd`) makes a road of a different *kind*, the builder
(`scripts/stage/stage_builder.gd`) dresses it, and the game (`scripts/game.gd`) runs the
mode's rules on top. `scripts/game/modes.gd` holds the options each mode loads a stage with.

Command line (tests and pictures): `--solo --mode=touge [--dir=up|down] [--rules=time|drift]`
or `--solo --mode=cutup [--difficulty=easy|normal|hard|insane]`
or `--solo --mode=track [--track_class=gt] [--session=practice]`; `--street=sim|arcade` overrides
Settings > STREET HANDLING; `--seen_cars_only` keeps the no-AI cars out of screenshot traffic.

Every mode records its runs for the **replay** ([replay.md](replay.md)): from the results or the
pause menu, every camera (the drone, trackside TV, the free cam, placed cameras and the director
...). Cut up's replay has its traffic (both carriageways, the ramps, a rival), the touge's its
stray car and your ghost, Track Mode's any AI race cars a `RaceField` puts on the track, and
online every other driver's car (the replay is local: your car waits on the brake meanwhile, as
in the pause menu).

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
white edge lines; white-painted guardrail wherever the road drops away, round the
outside of every tight bend *and* in front of every street lamp; some concrete parapets;
sugi cedar forest (tall, narrow, dark spires); a power line on single wooden poles behind the
guardrail on the right; at each hairpin an orange curve mirror and yellow chevron boards
pointing the way it turns; kilometre posts; the pass's name board and a vending machine at
the start; a GOAL arch. No spectators, no co-driver.

**At night** the only light on the mountain is the street lamps' (`scripts/stage/street_lamps.gd`)
and the cars' own. A lamp stands before every tight bend (on its outside, 3-16 m before it),
just past the start and the finish, and never more than ~110 m from the next (about 14 a
kilometre, the posts there by day too). Each post stands 1.6 m past the road's edge behind a
guardrail, on the ground there (as level a spot as there is nearby, not up the cut bank),
clear of every part of the road, the roadside things and the trees (planned before the forest
is planted: the cedars keep 6 m back); it's solid; its arm reaches over the road, the head
hung under its end. Each lamp's sodium head glows with a glare round it and a pool of light on
the road under it, faked (no real light: a pass of them costs next to nothing), lying on the
road's grade and stopping where the ground falls away; the four lamps nearest your car get
real lights as well, so the car, the guardrail and the cedars light up as you pass and fall
dark behind, one handing over to the next without a pop. `tests/lamps_check.gd` measures all
of it over 8 passes, up and down. The cedars stand closer to the road than on a
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
drop out come back in a gap (their bodies put away and used again: a pack of 20 doesn't
load 20 models at once). They're kinematic (solid to your car, not simulated) and
drive with **IDM** (Treiber et al. 2000: their own desired speeds, a 1.3 s gap (closer
on HARD and INSANE: x0.85, x0.75), smooth braking) and **MOBIL** (Kesting et al. 2007:
they change lane when it pays, politely, never making the car behind brake harder than
3.5 m/s²). On INSANE they come in **packs**: 14-26 cars across all four lanes, bumper to
bumper, with 40-90 m between packs (one coming up behind you from the start). Cars further
than 160 m from every player are moved every other tick and their wheels don't turn, and
past 300 m they think every 8th tick (nobody sees either from there): 2.6x the cars of the
old INSANE cost 1.5x the time. Cars **join
from the on-ramps** (merging into a gap in lane 0) and **leave by the off-ramps**. The
**oncoming carriageway** has its own traffic (for the view; the median barrier keeps it
from you).

Each traffic car has a **type** (its registry entry's `traffic.type`), and it drives like one:

| Type | Cars | Speed (x its lane's) | Time gap | Keeps right | Lane changes |
|---|---|---|---|---|---|
| compact | MOCHI e | 0.96 | 1.3 s | a little more | as often |
| sedan | SALOON, KAISER T | 1.0 | 1.3 s | as usual | as often |
| crossover | CROSSOVER | 0.98 | 1.4 s | a little more | a little less |
| minivan | PEOPLE MOVER | 0.93 | 1.6 s | more | less |
| SUV | GRAND SUV 63 | 1.01 | 1.3 s | a little less | as often |
| luxury | HELLHOUND, KAISER 8 GC | 1.06 (never over the difficulty's top speed) | 1.05 s | hardly | more, for smaller gains |
| van | KOMBI V8 | 0.9 | 1.7 s | most | least |

**The start: a gas station** (`LoopGen.station`, built by `LoopBuilder._station`). A run
starts at the pumps of a services forecourt off the highway, where one of our side's
junctions ends up (its exit's and the next entry's ramps, 59 m apart, joined by the
forecourt; `_find_station` picks the flattest, nearest the start line: just before the
loop's 0 km, in the city), and you drive out yourself: across the forecourt, up the entry
ramp and merge into the traffic from its acceleration lane. 68 x 48 m of asphalt (the land
under it flattened, the towers and trees kept off it), a canopy on six columns over three
pump islands (two pumps each, lit screens, a red band, lights under it that light the
forecourt at night), the shop at the back (glass front lit at night, SHOTGUN FUEL over it,
24/7), parking bays, a price pylon facing the highway, and a planter wall round it, open
where the two ramps come in. No brands. Eight pumps' places (two rows of four lanes between
the islands): online, everyone starts at their own. The traffic starts round the station's
stretch of highway; R puts you on the highway. The autopilot (tests) follows a route out
(`LoopGen.station_route`) before it takes the highway's line. `--highway_start`: the old grid
on the highway. `tests/station_check.gd`.

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
| HARD | 70 | 85-130 km/h | 0.9 m | often | no: every lane busy all the way |
| INSANE | 100 | 90-140 km/h | 0.7 m | a lot | 14-26 cars across the lanes, 40-90 m between |

HARD and INSANE are a real highway's rush hour (the owner: "the cars should legit be in
traffic"), measured by the Highway Capacity Manual's levels of service for a basic freeway
segment (density in cars a km a lane: A up to 7, B 11, C 16, D 22, E 28, the road's capacity;
F past it, a queue): HARD ~17.6 a km a lane (LOS D: busy, flowing), INSANE ~26 (LOS E: at
capacity, in waves). `tests/modes_check.gd` checks both. They were 30 and 45 (Assetto
Corsa's No Hesi servers in the owner's clips: ~7.5 and ~11 a km a lane, LOS B).

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

**THE TOLL PLAZA** (`LoopGen.toll`, `LoopBuilder._toll_plaza`, Traffic's rules there): one
across both carriageways at 22.7 km (the lakes; the generator finds the first stretch that's
on the ground, straight from 400 m before to 150 m after, and clear of ramps, overpasses and
gantries, so it's the same place every time). Real highway plazas widen; this one fans the
lanes out instead: through the plaza each carriageway's lanes are 1.25 times as far apart
(eased in over 160 m, about 1.3 m sideways for the outer lanes), so the booths' islands
(0.9 m wide, a 0.25 m kerb) stand on the lane lines with a full 3.6 m of lane between them.
The outer ones stand on the shoulders and the middle one on the median, whose barrier gives
way to it. Nobody has to change lanes for it, the painted lines fan out with the lanes, and
they're solid for the last 80 m. It has:

- a booth on each lane's driver's side (lit windows at night);
- a yellow-and-black crash cushion at every nose the traffic comes at;
- a canopy over both carriageways on columns, with lights over each lane (StreetLamps' pools at night);
- over each lane, a green arrow or a red X and a board (ETC / CLOSED / GO);
- cameras on the fascia and readers under the canopy;
- barrier arms past the booths;
- gantry signs 1 km and 400 m before it, each way.

Everything solid is solid (islands, booths, columns, crash cushions, a closed lane's gate).

| Layout (cut-up menu: TOLL PLAZA) | Lanes | Gates | Traffic |
|---|---|---|---|
| ALL OPEN (the default) | all 8 open | up | full speed through, in lane |
| MIXED LANES | each way's right-hand lane closed (a red X, CLOSED, a line of cones from 150 m before, its arm down and solid) | the open ones up | out of the closed lane from 820 m before (smaller gaps as it gets close; stopping short of the gate if it can't), slowed to 60 km/h from 80 m before the islands |
| EVENT | all open, every board GO, the canopy's name SHOTGUN RALLY | up | full speed through |

The traffic's rules (all layouts):

- nobody starts a lane change from 320 m before the islands until past them (one would straddle an island);
- no car appears among the booths or in a closed lane before them;
- the other carriageway's cars fan out the same way and keep out of their closed lane;
- the rivals obey it too;
- the autopilot (the menu's showcase, the tests) takes the middle of a lane through it, never the line between two.

The layout goes to every machine with the stage (online: the host's).

## Track Mode: CINDER RIDGE (a permanent circuit)

MODES > **TRACK**: a class (**GT**, or **FORMULA**: open-wheelers with DRS and a hybrid), a
session (**PRACTICE**, **QUALIFYING**, **QUICK RACE**, **RACE WEEKEND**) and, for the last three,
the race's options (laps, the AI field and its skill, the start, qualifying's length, your grid
place, damage), then START. Qualifying, races, flags, penalties, pit stops and the AI field are
in `docs/track_racing.md`; the cars and their race physics in `docs/track_cars.md`. The full plan
is `docs/GT_F1_TRACK_MODE_CLAUDE_PROMPT.md`.

**The circuit** is designed once, offline, by `tools/circuit_map.py` (run it to change the
layout: `python3 -I tools/circuit_map.py --png map.png --profile profile.png`) into
`data/maps/cinder_ridge.json`, and every machine builds the same track from that file. It's
a polygon of 17 corners filleted with arcs, the curvature eased so nothing jumps, closed
exactly. The numbers:

- **5.03 km** clockwise, **17 corners**, from a 24 m hairpin to 260 m sweepers;
- 45 m of climb over the ridge, grades up to 6.4 %, banking up to 3 %;
- **12 m** wide (15 m on the pit straight);
- a GT3's lap on its racing line is about **1:34** at the limit (RaceLine: `docs/track_racing.md`), 1:47 on the centreline; the AI's own laps on the physics ~1:43, the practice test's cautious autopilot 2:37.

`scripts/stage/circuit_gen.gd` (CircuitGen, on LoopGen's road API, so the car, autopilot,
HUD and builder work as on the highway loop) answers what's across the track at any s:

- the asphalt to the white lines;
- the **kerbs** outside them: apex kerbs on every corner's inside, exit kerbs on the outside, entry kerbs where it's braked hard, wider chicane kerbs;
- the **run-off**: grass, gravel traps where a car would go straight on, asphalt;
- the **barrier**: armco, tyre walls (TecPro-style blocks), or a concrete wall with debris fencing;
- the **pit lane**, with its taper in, the 60 km/h limiter lines, **20 boxes**, the line out and the taper back.

Also: a **20-place grid**, two by two, behind the line; **three sectors** (1.66 / 1.71 / 1.66 km);
**three DRS zones** on the straights (each with its detection point, for the formula class);
marshal posts, 300/200/100 m boards before the big stops, grandstands and floodlight towers.

Each surface is a SurfaceConfig: a kerb is `data/surfaces/kerb.tres` (a touch less grip than
the asphalt, rougher), and the gravel and grass are the rally's own.

`scripts/stage/circuit_builder.gd` (CircuitBuilder) dresses it:

- the track (cambered, kerbs striped), the run-off and the land (rolling hills eased into the verges, out to the horizon);
- the barriers;
- the pits: the lane and its lines, the pit wall with its fence, numbered garages, the paddock and a control tower;
- the grid boxes, the start gantry with its lights, the grandstands, the marshal posts and boards;
- floodlights (lit at night) and the biome's forest beyond.

**Practice** (`scripts/game/track_session.gd`, TrackSession: pure logic, so the tests drive it
directly) works like real timing loops:

- You start in your **pit box**. The autopilot (or you) drives down the lane under the limit (the HUD warns "PIT LIMIT 60 KM/H" if you're over) and out onto the track on an **out-lap**, untimed.
- Crossing the line on the track starts the timed lap; each sector line flashes its time against your best (purple: the session's best, green: your best, yellow: slower).
- The line ends the lap: "LAP 3  1:52.418", PERSONAL BEST, or INVALID.
- **Track limits**: all four wheels past the white line (more than a car's half-width beyond it) invalidates the lap. Two wheels over on a kerb is fine.
- Crossing the line in the pit lane makes it an in-lap, and the next is an out-lap.
- The HUD shows the running lap, LAST and BEST.
- END RUN (pause menu) shows the best lap and saves it per circuit, class and car: the TRACK card shows your best.
- Crossing times are interpolated between physics ticks, so laps are timed to the millisecond.

The GT class runs the **ELFER R**, the **AFFALTER GT3**, or the ELFER EVO if that's your garage
car (the class list is `data/track_classes.json`), at its homologated spec (no garage upgrades).
Online, everyone in their own car of the class on one circuit, the host's machine race control for
all: below, and `docs/track_racing.md`'s "Online".

## Online: street sessions (up to 8)

MODES > **HOST ONLINE (UP TO 8)**, then START a touge, a cut-up difficulty or a TRACK session: the host's
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
- **Track Mode online** (`docs/track_racing.md`, "Online"): practice, qualifying, a race or a race
  weekend on CINDER RIDGE, each player in a car of the session's class (the class's own if their
  garage car isn't one). The grid is the roster's order (or qualifying's); the host's machine runs
  race control for everyone (`scripts/game/track_net.gd`): each guest's machine sends where its car
  is on the track, the host times it, judges it and sends back the race's state, its news and the
  classification. CARS fills the grid with the host's AI, streamed to everyone. Someone joining once
  it's on starts from the pit lane; someone leaving is out (DNF). Every car passes through the
  others online for now.

Command line (tests): `--host --street --mode=touge|cutup [--ghosts] [--min_racers=N]
--autostart --autopilot`, or `--host --street --mode=track [--track_class=gt|formula
--session=practice|qualifying|race --laps=N --opponents=N --start=standing|rolling]`, the others
`--join=127.0.0.1 --autopilot`; `tests/run_all.sh` races three machines down a touge (all three
agree on the order), runs three on the loop (the host's traffic round each) and races three
round CINDER RIDGE with the host's AI (all three agree on the classification).

## Street handling: SIM or ARCADE (Settings)

**STREET HANDLING (CUT UP, TOUGE)** in Settings: **SIM** out of the box, **ARCADE** to drive
these modes like the rally (`Config.street_handling`). Rally stages always use TYRE GRIP.

SIM is Assetto Corsa-like: each car on the road tyres it really has (`TireModel.street`,
`Catalog.street_grip`):
- **its real grip**: the asphalt peak set so the car holds its real skid-pad figure (0.99 of it
  on average across `tests/sim_check.gd`'s nine cars; until October 2026 0.95), measured
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
  HIGH-SPEED STABILITY has its own street switch, HIGH-SPEED STABILITY (CUT UP, TOUGE), off out
  of the box (the video study: an invisible hand that snapped every slide straight in 0.1 s felt
  fake); factory ABS, and traction control and stability control (ESC) where the real car has
  them as standard (the classics, the prototypes and the rally cars without; their switches
  still force them on; no traction control in the touge's DRIFT rules). Its ESC brakes one
  wheel (harder on a heavier car), counts a wide slide as well as the yaw, and cuts the engine
  while it catches one; its reference (the yaw the steering asks for) follows the steering as a
  car's yaw does and allows for the car's understeer, so a lane change's unwinding isn't a slide
  (it used to brake a wheel and cut the engine in ordinary lane changes). Traction control holds
  the driven tyres' spin at their peak from an estimate of what they can take, less while they
  corner (the combined-slip ellipse: under power the tyres keep their grip sideways), counts them
  sliding sideways (power oversteer), and never cuts below the throttle where the engine neither
  drives nor brakes (cutting to nothing was a lift: lift-off oversteer). The automatic and
  dual-clutch boxes (the cars with factory traction control) match the revs on a change;
- **the steering** (with SPEED-SENSITIVE STEERING on, out of the box): the stick asks for that
  share of the car's grip, in proportion (a quarter of the stick a quarter, half half), through
  the turn's geometry and the car's understeer, which it learns as it's driven (every car's is
  its own); the last tenth of the stick adds the front tyres' peak slip (full lock pushes wide,
  never spins it). Sliding, steering toward the slide may turn the wheels to where the front
  axle's going and past (a slide can be caught by hand; nothing steers for you). **Keys**: the
  steering builds in proportion to the time a key's held, slower the faster it goes (5 /s up to
  54 km/h, 1.2 /s from 126 km/h, between on a log scale: `AssistConfig.street_key_rate`): at
  200 km/h a 0.3 s tap is a calm ~0.15 g move, 0.6 s ~0.45 g, a key held ~1 s a hard ~0.8 g
  turn; and on keys the last of the travel adds the fronts' peak slip only at low speed (a
  hairpin), so a held key never pushes them past their grip (at 200 km/h the road wheels stay
  under 1 deg, the steering wheel under ~13 deg; until October 2026 a held key swung them to
  7.7 deg in a second and the car ploughed on, smoking). Sliding (the body past 2 deg) or on the
  handbrake the keys stay quick (catching a slide, holding a drift). The stick's deadzone is
  0.07 (it was 0.2: the first fifth of the stick did nothing);
- **traffic has weight**: running into a car shares the hit by weight as two real cars do
  (`Traffic.shove`): a rear-ender at 133 into 100 km/h costs you 17 km/h (it was ~50, as off a
  wall) with a ~5 g jolt, the car is shoved on, hard enough it's a crash and it pulls up; a rub
  alongside shoves it off its line and it steers back into its lane;
- **the camera** shivers a hair at speed and with the revs (~0.08 deg rms at 200 km/h flat out),
  more on gravel than asphalt;
- **tyre smoke and marks** on tarmac only when a tyre really slides: past its grip's peak slip
  angle (and fast enough sideways), or spinning / locking (`DriftFx`, `SkidMarks`). They came on
  with 1.2 m/s of sideways speed at the tyre: at 200 km/h a tyre at half its grip, so every lane
  change smoked. Drifts smoke as before; gravel throws its dust as before.
- **HIGH-SPEED STABILITY (CUT UP, TOUGE)** on only damps yaw the steering didn't ask for and a slide
  past 2.5 deg: it used to also fight the degree or two of body slip every car runs cornering
  hard, so the car turned less than it was steered.

Measured (`tests/sim_check.gd`, a 76 km/h ramp-steer skid pad and 100-0 km/h): the Supra
1.06 g and 37 m, the GT-R 1.00 g and 36 m, the AE86 0.80 g and 43 m, the GT3 RS 1.28 g and
29 m; ARCADE gives the same road cars 1.4-1.6 g (the GT3 RS 1.96). What SIM means at the wheel: real cars slide
earlier and need smoother hands. Measured with the study's harness (GR Supra, at 200 km/h):
a quarter / half / three-quarters / all of the stick gives 26 / 51 / 76 / 98 % of its grip (it
was 71 / 91 / 98 / 99 %); lane changes settle in 0.3-0.7 s with no rebound and no hidden push on
the body (the old aid pushed with 7-22 kN m); a clip the size a hit with traffic now is (1.5 m/s
at the rear axle) peaks at 8-9 deg of slide and is straight again in under a second, by the
car's own ESC; a hard one (3 m/s) slides 40-57 deg but no longer spins the Supra or the G 63;
flooring it out of a 60 km/h corner no longer spins the Supra. ARCADE is there for those who'd
rather.

`tests/tarmac_check.gd` measures the owner's three complaints (October 2026): the M5 G90's
acceleration against the real car's (0-60 mph 3.0 s, 0-100 km/h 3.2 s against BMW's 3.5,
60-100 mph from a cruise 3.7 s, 100-200 km/h 6.9 s, 0-200 10.0 s against BMW's 10.9); a GT3
car's standing launch in Track Mode on cold slicks with no steering (straight, 0-100 km/h in
~3.2-3.5 s) and keys tapped on the throttle at 80 km/h (no spin: it spun on a 0.2 s tap); a
lane change at 200 km/h on keys and a stick (no smoke, no marks, ~0.3 g, the front tyres under
half their peak slip, ESC untouched), a key tapped and held at 200 km/h.

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
END RUN); the night touge (lamps before every tight bend and never more than ~130 m apart,
lit only at night, the real lights following the car and fading away from the lamps) and the
stray car (turns up ahead, keeps its lane, slows for hairpins, stops when hit, goes once
you're past). `tests/drive_check.gd --kind=touge` has the autopilot drive a pass.
`tests/sim_check.gd`, `tests/feel_check.gd --cfg=street` and `tests/tarmac_check.gd`: SIM street handling.
`tests/track_check.gd`: Track Mode:

- the circuit: deterministic, closed (position and heading), evenly sampled, 4.5-6 km, 14-20 corners, no corner under 14 m radius, grades and banking, never within 45 m of itself;
- the grid: behind the line, inside the white lines;
- the pit lane: its lines in order, right of the track behind the wall, the boxes in the lane under the limit;
- sectors, DRS zones on straights, an apex kerb at every corner, a barrier the whole way round both sides, each surface in its place, `locate()` two laps round;
- the session: a car driven at a known speed timed to 0.000 s, sectors adding up, the kerb kept, the cut lap invalidated once, the in-lap and out-lap, the classification;
- the game: CINDER RIDGE builds, the car starts in its box, the autopilot drives down the pit lane under the limit and round a valid timed lap, END RUN shows the best lap.

`tests/toll_check.gd`: the toll plaza in each layout:

- where it is, and that it's straight and on the ground;
- a car-sized box down the middle of every lane both ways touches nothing, while the mixed layout's closed lanes stop it;
- the islands are solid, with 3.6 m between them;
- the boards, the lights, the median and the cones;
- the autopilot's line goes between the islands;
- a minute of insane traffic through the mixed layout: out of the closed lane beforehand, nobody changing lanes or touching an island at the booths, slowed to 60, and the other carriageway clear of the islands too.
