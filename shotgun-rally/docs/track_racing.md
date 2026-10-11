# Track Mode: qualifying, races and the AI field

MODES > **TRACK** has two classes:

- **GT** (APEX GT CHALLENGE): closed-wheel GT3 cars with ABS and traction control; rolling starts. The
  ELFER R, ELFER EVO, AFFALTER GT3, HALDANE GT3, VESPERA GT3, VALKO GT4 and STILETTO CUP.
- **FORMULA** (FORMULA APEX): open-wheel single-seaters with no ABS or traction control, DRS and a
  hybrid; standing starts. The ORION FA1 and the ZEPHYR GE (below).

Each runs four sessions on CINDER RIDGE:

- **PRACTICE:** alone, laps against the clock (`docs/modes.md`).
- **QUALIFYING:** the clock (5, 10, 15 or 20 minutes) with the AI field on track. Your best valid lap sets your place.
- **QUICK RACE:** a race of 3, 5, 10 or any number of laps. You start where GRID says: FRONT, MIDDLE, BACK or RANDOM (the field lines up by pace).
- **RACE WEEKEND:** qualifying, then the race from where you qualified, against the same drivers in the same cars.

The options:

- **LAPS;**
- **CARS:** 0-15 AI opponents;
- **AI:** EASY, MEDIUM, HARD or PRO;
- **START:** ROLLING, STANDING, or the class's own (the GT class's is rolling);
- **QUALIFYING:** its length;
- **GRID:** a quick race's place for you;
- **DAMAGE:** on or off.

The plan this follows is `docs/GT_F1_TRACK_MODE_CLAUDE_PROMPT.md`.

## The race

`scripts/game/race_control.gd` (RaceControl) is pure logic on top of TrackSession's timing: the
same inputs give the same calls, which is what an online host needs.

- **The start:**
  - **STANDING:** five red lights come on a second apart on the gantry and on screen, stay lit for a random 0.2-3 s, and go out. Moving more than a metre from your box before then is a **jump start: +5 s**.
  - **ROLLING:** the field sets off in its double file 350 m behind the grid and rolls up at the pace speed (80 km/h), each car a length behind the one ahead. GREEN comes as the leader nears the line. Crossing the line ahead of a car that started in front of you is a pass before the start: **+5 s**.
- **The flags:**
  - **GREEN** at the start.
  - **YELLOW:** a car stopped or crawling on the track for 2.5 s puts a yellow over its 250 m and the 250 m before. No passing there (a stricken car excepted): **+5 s**.
  - **BLUE:** a car a lap up is within ~1.2 s behind you; let it by. In qualifying: a car on a flying lap behind your out-lap.
  - **BLACK AND WHITE:** your third track-limits warning.
  - **BLACK:** 30 s of penalties, disqualified.
  - **RED:** three cars stopped at once. Everyone slows to 80 km/h with no passing, then after 15 s a standing restart from the order the race was in. Cars on the lead lap restart on the leader's lap, and each car's partial lap is run again.
  - **CHEQUERED:** once the leader has done the laps, everyone finishes as they next cross the line (their time at the line itself, to the ms). Five minutes on, the race is over, every car home or not.
- **The penalties** escalate:
  - **TRACK LIMITS:** a lap's excursion with all four wheels past the white line that kept its speed: warnings 1-3, then +5 s each time.
  - **CORNER CUTTING:** off on the inside of a corner: one warning, then +5 s.
  - **PIT LANE SPEEDING:** over 60 km/h between the lines: +5 s each time.
  - **CROSSING THE PIT EXIT LINE** before the lane's taper ends: +5 s.
  - Two wheels over the line, or a kerb, is never anything (all four must be past it).
  - In qualifying, track limits delete the lap; the rest are warnings.
- **The classification:** by laps, then time with the penalties added; retirements (DNF) and disqualifications (DSQ) last. The fastest lap is shown. Your best finish per kind is saved, and the last ten classifications are kept (`Profile.track_results`).

## The screen

`scripts/ui/race_tower.gd` (top left):

- your position and lap (**P3 / 12 · LAP 4 / 10**), or qualifying's clock;
- the timing tower: places, numbers, names, the gap to the leader (or best laps in qualifying), PIT, penalties, DNF;
- the gap to the cars just ahead and just behind;
- the flag being shown to you, as a banner across the top.

The car panel (bottom left) in a Formula car shows its hybrid (ERS: the store's charge, the mode, what's
left of the lap's 4 MJ; green while it deploys) instead of ABS and TC, and DRS above it: grey, white when
you may open it, green open.

The start lights are the existing on-screen gantry (`scripts/ui/start_lights.gd`, its race mode)
and the circuit's own gantry (`CircuitBuilder.set_lights`).

The car panel (tyres, brakes, fuel, ABS / TC, the limiter) is `docs/track_cars.md`'s.

## Pit stops

Drive into your box in the pit lane and stop: the crew does the work, and the car is held until it's done.

- **New tyres:** if they're worn past 30 % (in qualifying: always).
- **Fuel:** to the end of the race.
- **Repairs:** if the session has damage on.

Its time: ~3 s, plus 12 s for tyres, fuel at 2 l/s, and up to 30 s of repairs. The AI pit the
same way (below). A pit strategy screen comes with P8.

## Damage (DAMAGE: ON)

RaceSim takes a hit's lost speed:

- bodywork past 4 m/s: up to 35 % less downforce and a little more drag;
- suspension past 7 m/s: up to 12 % less grip;
- the engine past 14 m/s: up to 35 % less power.

Repairs mend it. The AI cars take damage the same way, and pit when it passes 30 %.

## The slipstream

A car within 40 m behind another, nearly in line, loses up to 30 % of its drag (the tow) and up
to 15 % of its downforce (the dirty air). RaceField works it out for every car, and RaceSim's
`drag_mul` / `down_mul` apply it to the car's aero.

## The AI

### The line and its speeds

`scripts/game/race_line.gd` (RaceLine) works out the speed a car can carry along the circuit's
racing line, the way a lap-time simulation does:

- **Each corner's limit:** v² × curvature = μ (g + downforce / m). The tyres' grip per newton falls a little as the downforce loads them (their load sensitivity, as the tyre model has it).
- **Braking** back from each corner (backward pass): the grip, drag and slope, less what the corner already uses (the friction circle).
- **Accelerating** out of each (forward pass): the engine's force in its best gear, up to what the driven tyres can put down, less drag, rolling resistance and the climb.

A driver's **pace** (0.82-1.0) is how near the car's limit it drives: its grip and braking × pace.
It never gets more grip or power than the car has.

- **K_PHYS 0.92:** the share of the tyres' grip a driver really uses, measured against the AI's own laps on the physics.
- **The AFFALTER GT3's numbers:** the line laps CINDER RIDGE in 1:34 at the limit; 279 km/h at the end of the pit straight; 80 km/h through the hairpin.

### The driver

`scripts/vehicle/race_driver.gd` (RaceDriver) drives with a player's inputs (steering, throttle,
brake). The car's own ABS and TC catch the rest.

- **Steering:** the autopilot's method (the path's bend ahead, back parallel to it, onto it), with the front tyres' slip angle for the side force asked of them. Never more lock than the tyres' peak: past it, more lock only scrubs.
- **Speed:** its line's at its pace.
  - flat out while the line's speed is rising;
  - a corner's speed held;
  - braked to the line's;
  - power out of a corner as the grip allows: less while it's still cornering hard, off while the tail steps out, half while it's running wide.
- **Learning:** each corner's pace is learnt as it goes. A corner run wide is a little slower next lap, and slowly comes back up.
- **Racecraft**, every tick, from where the others are:
  - **A car ahead it's catching:** a side with room, the inside of the next corner first, committed to until it's past. With no room it follows, a length and ~0.3 s back.
  - **A car alongside:** it keeps a car's width away and never turns into it (you included), and backs out of a squeeze.
  - **Defending:** a car behind catching it before a braking zone: it moves to the inside, once a straight.
  - **Flags:** under blue it moves off the line, away from the leader, and lifts on the straight. Under yellow, no passing (a stricken car excepted) and a lift.
  - **A crawling car ahead:** it goes round it.
- **Mistakes**, by consistency: now and then a corner run wide, or braked late; a little pace lost or found from corner to corner.
- **The start:** held on the brakes until the lights go out, then its reaction time (0.18-0.4 s). Or its place in the rolling start's double file.
- **Pit stops:** down the lane on the limiter, into its box, stopped while it's serviced, back out along the lane and onto the track only past the exit line's end.
- **Qualifying:** out of its box one by one, an out-lap at 86 % pace, three flying laps, back to its box.
- **Stuck:** a spun or beached car is put back on the track's edge once nothing's coming, as R does for you; stuck for 40 s, it retires.

### The field

`scripts/game/race_field.gd` (RaceField). A car's full physics costs about 0.9-1.5 ms a tick in
this engine; four fifths of it is the tyre and drivetrain steps.

So:

- **AI cars on the physics** run 4 steps a tick (yours: 8). Their laps come out the same.
- **The nearest few** AI cars to you (by the graphics level: LOW 2, MEDIUM 3, HIGH 4, ULTRA 6; `--near_max=N`) run the full physics, out to 110 m and kept on it to 150 m.
- **Farther away**, a car is moved along its line at the speed its car and driver would do, accelerating and braking as the line works out, at 98.5 % of it (`FAR_K`, measured: an AI car on the physics with warm tyres laps at that share). While far it touches nothing. Its fuel, tyres and brakes keep their running state (`RaceSim.coast`).
- **Switching** carries the car's place, heading and speed over, wheels spinning and in the gear for that speed, so it doesn't show.

The field (`Modes.track_field`):

- made-up drivers (`data/track_drivers.json`), each in one of the class's cars, in its own colours, livery and number;
- skill round the difficulty's (pace, consistency, aggression, reaction);
- the same field for the same seed (a weekend's qualifying and race).

In Track Mode every car runs at its homologated spec: no garage upgrades.

## Tests (`tests/race_ai_check.gd`, in `tests/run_all.sh`)

- **line:** the GT3's lap, top speed and hairpin speed; never over a corner's limit; braking within the grip; a slower driver slower by its pace; inside the white lines.
- **rules:** the lights a second apart and the random hold; a jump start; track limits 3 warnings then +5 s; two wheels over is nothing; a corner cut; pit speeding; the pit exit line; a yellow and passing under it; a blue flag; a red flag and the restart's grid with the laps kept; the chequered flag and the finish order with penalties; disqualification; the rolling start.
- **quali:** the clock, the flying lap at the flag finished, a deleted lap, the order.
- **driver:** an AI car on the physics: two flying laps within 2.5 % of its line at its pace, on the track the whole way.
- **far:** the same car moved far away laps within 1.5 % of it. The switch onto the physics at 250 km/h keeps its place, speed and gear.
- **pit:** down the lane at the limit, stopped in its box, new tyres and fuel, back out across no line.
- **weekend:** qualifying in the game: the AI out one by one, everyone timed, the flag, the order, the race's grid from it, the same field.
- **race:** a 6-car race over 2 laps in the game: the lights, no jump starts, everyone finishing, places changing (17 times in the last run), no hard hits, the classification and the results.
- **drs:** the DRS rules with no physics (not before the leader's third lap; a second at the detection point; never under a yellow or a red; free in practice).
- **Formula** (`--class=formula`, the ORION FA1; `--car=zephyr` for the other): the driver test on the physics (two flying laps within 2.5 % of its line, on the track), far, pit, DRS and the hybrid down the pit straight, and a 6-car 3-lap race with a standing start (DRS enabled, the AI deploying their hybrids).

## FORMULA APEX

The game's own series: no real team, car or branding. Its numbers are 2022-25 Formula 1's:

- **800 kg** with the driver and without fuel (the FIA's 2025 minimum, up from 798 kg), ~45 % on the
  front (McLaren's MCL39 sheet: 44.6-46.1 %).
- **A 1.6 V6 turbo hybrid:** ~590 kW from the engine, its power flat above 10,500 rpm as the fuel flow
  cap holds it, the limiter at 12,500 here; **eight gears**, a 0.02 s seamless shift.
- **A 120 kW MGU-K** deploying at most 4 MJ a lap and recovering at most 2 MJ under braking (McLaren's
  sheet); the turbo's MGU-H tops the store up at full throttle (~30 kW here).
- **Pirelli's 18 in slicks:** 305 / 405 mm wide, 720 mm across. In the game they're a "formula" tyre:
  ~1.7 g before the wings, rated at 4 kN a tyre so the downforce costs them little grip per newton.
- **Aero:** a lift coefficient of ~3.6 on ~1.5 m² (published estimates for post-2017 cars): about
  the car's weight in downforce by ~180 km/h, 5 g in CINDER RIDGE's fastest corners on the AI's line.
- **No ABS, no traction control.** A 145 l tank (110 kg: the most a race starts with), its fuel flow
  capped (~0.037 l/s flat out); ~2.4 l a lap here.

Sources: the McLaren MCL39 technical specification, the FIA's July 2024 F1 Commission statement
(the 800 kg), Pirelli's 2022 18 in tyre launch, the DRS article on Wikipedia (the FIA's +10-12 km/h).
Power, torque, the ratios, the aero and DRS's effect are estimates: teams don't publish them.

The cars (the owner's CC0 models, at their own size):

- **ORION FA1:** the halo open-wheeler, a 3,250 mm wheelbase: the shorter, the more agile.
- **ZEPHYR GE:** the ground-effect car, 3,575 mm (the rules allowed up to 3,600): more downforce,
  a little more drag.

Their cockpits: a race wheel made for each (a carbon yoke, two grips, a screen: the converter's
`"add"`), the driver alone and lying back (no co-driver, no map board, no windshield), the helmet up
under the halo. The AI's single-seaters show their drivers' helmets.

### DRS

The circuit's three zones, each with a detection point before it (`data/maps/cinder_ridge.json`
"drs"): the pit straight, the run through SKYLINE, the back straight.

- **In a race:** enabled two laps after the start (or a restart). A car within a second of the car
  ahead of it on the road (lapped or not) at a zone's detection point may open its flap in that zone.
  Never under a yellow in the zone, never under a red.
- **In practice and qualifying:** free in the zones.
- **The flap:** E (RB on a pad) opens it when you may; it shuts on the brakes or out of the zone. Open, it
  sheds 18 % of the drag and 13 % of the rear axle's downforce.
- **The AI** opens it whenever it may, flat out; the far cars (RaceField's cheap mode) get its gain too.

Measured (tests/race_ai_check.gd): down the pit straight 307 km/h with DRS shut and the hybrid off,
322 with both (+15 km/h).

### The hybrid (ERS)

O (d-pad left) cycles its mode: **OFF** (it only recharges), **BALANCED** (it deploys flat out above
~110 km/h, where it's worth most), **OVERTAKE** (whenever it's flat out). The AI runs BALANCED, and its
racing line counts the push (the share of the lap the 4 MJ lasts).

### The AI in a Formula car

A racing driver feels for the edge of the grip with their feet; the AI's pedals lean on ABS and
traction control for that. So in a class without either, the AI's and the autopilot's cars run them
as stand-ins for their feet: no more grip than the tyres have, they only keep them at their peak.
Your own car has neither (FORMULA APEX's rules). The AI also takes 94 % of the line's grip in a
Formula car (`"ai_grip"`): its sharper tyres and snappier car are harder to hold at the limit.

## The GT grid

The owner's four CC0 GT models joined the class, balanced on the AI's line to within 0.8 % of each
other and the AFFALTER (SIM STREET's GT3 slicks, 1.6 g): HALDANE GT3 (front-engined twin-turbo V8),
VESPERA GT3 (mid-engined twin-turbo V6), VALKO GT4 (a GT4 built up to the GT3s) and STILETTO CUP (a
rear-engined cup car). They have no cabins of their own (low-poly, tinted glass): from inside, the
shared cockpit.

## The pits and the marshals

The owner's 14 CC0 track props (`assets/environment_runtime/props/track_props.glb`), placed by
`CircuitBuilder._pit_props`:

- **Between the boxes:** each team's tyres in their blankets, a warmer rack and a wheel gun.
- **The boxes:** a jack at each end of each box; an air-jack rig, a helmet rack or a fuel rig every
  other box. Nothing in a box or the fast lane.
- **The pit wall:** a monitor stand opposite each box.
- **The lane:** signal lights at both ends, solid tyre walls on the noses of the entry and exit.
- **The paddock:** a row of team garages behind the garage block.
- **The marshal posts:** an observation hut with a flag pole beside it at all 34.

`tools/circuit_shots.gd` shoots them without the game.

## The start

For 12 s after the lights go out (or a restart), a car slow off its grid box throws no yellow, and the
field sorting itself out round it isn't passing under one: the start's own chaos, not an offence.

## Online

MODES > **HOST ONLINE (UP TO 8)**, then the TRACK card's class, session and options and START: the
host's machine opens a street session on CINDER RIDGE (port 7777). Friends **JOIN** from ONLINE with
the host's IP, as for the touge. Everyone drives their own car: their garage car if it's in the
session's class, else the class's own (`Modes.track_car`), at its homologated spec, in their colours
and number.

- **The sessions:**
  - **PRACTICE:** everyone's laps on one tower; END RUN ends your own run, not the others'.
  - **QUALIFYING:** the clock.
  - **QUICK RACE.**
  - **RACE WEEKEND:** qualifying, then the race from qualifying's order (the host's ENTER at the results).
- **The grid:** the players in the roster's order (the host first) or, in a weekend, qualifying's
  order; the AI behind them (by pace). The players' pit boxes are 8-15, the AI's the rest. Everyone
  loads the same circuit and starts on the host's lights: standing for FORMULA, rolling for GT (or
  the START option).
- **The host is race control** (`scripts/game/track_net.gd`, TrackNet). RaceControl and
  TrackSession run on the host only, on every car: the positions, laps, timing, flags, track-limit
  warnings and penalties, jump starts, DRS, pit-lane speeding, the chequered flag and the results.
  - Each guest's machine runs its own car (as in the touge) and sends the host where it is on the
    track (s, d, speed, in the pit lane) 20 times a second, stamped with its own clock (its physics
    time).
  - Race control judges every car at the same moment, 0.12 s back on the host's clock (a guest's
    position can't be fresher than that, so nobody's is: the host's own car and the AI aren't judged
    a little ahead of the guests, for the running order, gaps, DRS, flags and penalties). A guest's
    car then: its positions at that moment on its clock (our clock less the stamps' offset, the
    quickest packet of the last 3 s eased into, plus half the round trip they took).
  - A guest's laps and sectors are timed on its own clock: each line's crossing between the two
    positions either side, on their stamps. So they come out as its own machine would time them, to
    the millisecond (the test checks it), even when the host's physics falls behind real time (a
    busy machine's does: the first test runs here had the host's clock 10 % slow, and a guest's laps
    12 s short).
  - A race's finishing times are each car's crossing of the line itself (between two ticks, on the
    session's clock; a guest's from its own), not the tick race control saw it in.
  - Five minutes after the leader's flag the race is over, every car home or not (a car stuck on the
    track, still connected, can't hold everyone's results).
  - The host sends every machine the race's state 5 times a second: the phase and the lights, the
    clock, the yellows and blue flags, who may open their DRS, and the timing board (the running
    order, each car's laps, gaps, best and last laps, penalties, status).
  - Its news goes out as it happens: the lights, the flags, penalties and warnings, the guests' laps
    and sectors (the HUD's messages). The classification goes out once a second while it changes, and
    the last one when everyone's done.
  - A guest keeps a copy of race control and the timing, never run there, and draws its HUD from it:
    the tower, the lights, the flags, its DRS, the results.
  - Each time the host puts the cars in their places (the start, a red flag's restart) the grid's
    epoch goes up by one. A guest's positions carry the epoch it has, and older ones are dropped, so
    a car moved to its grid box isn't judged on where it was.
- **The other players' cars:** the street session's own (each simulated on its driver's machine,
  streamed ~30 times a second, played back 0.1 s behind, a name over it).
- **The AI:** the card's **CARS** fills the grid online too (0-12; 0 for friends only;
  `--opponents=N` on the command line, 0 by default). The host simulates them (RaceField: on the
  physics near any player, moved along their line away from everyone) and streams them to every
  machine 20 times a second, drawn there like a remote car (`RaceField.setup_view`); the same race
  control classifies them. Practice is friends only.
- **Collisions:** online, every car passes through the others for now. A remote player's car is only
  drawn on your machine, not simulated there; the street session's remote cars have never touched
  each other in fact (both on collision layer 2 and mask 1, so neither looks for the other, whatever
  COLLISIONS says). The AI pass through the players as well, so no machine gets contact with them
  that the others don't. The AI still race each other for real.
- **Joining late:** someone who joins once the session's on loads the circuit, gets the state and
  starts from a free pit box, out of the pit lane (in a race, laps down). Once the chequered flag is
  out they wait for the next session.
- **Leaving:** a player who leaves is out (DNF) at once. One whose positions stop coming for 20 s
  while still connected is out too. The race never waits on them.
- **The results:** every machine shows the host's classification: positions, times, gaps, best laps
  and penalties. R at the results (the host) runs the session again for everyone.

Command lines (port 7777, `--port=N` for another):

- host: `--host --street --mode=track --track_class=gt --session=race --laps=5 [--opponents=N] [--start=standing|rolling] [--minutes=M] [--name=Ann]`;
- join: `--join=HOST_IP [--name=Bob]`.

The test (`tests/run_all.sh`): one host and two guests on localhost, all on `--autopilot`, race 2
laps (a standing start) with 2 AI cars filling the grid. Each must:

- be shown the five lights and the green;
- see the two other players' cars and the AI moving;
- have the same classification as the host, which has every car classified and every player at the flag;
- (a guest) have its laps timed by the host within 5 ms of its own timing of them (0.0-1.5 ms in the runs here);
- show a sane running lap clock on its HUD (never below 0, never past 300 s).

Tried by hand, not in the suite (each run takes minutes on four machines' worth of CPU):

- online qualifying (2.5 minutes, three players and 2 AI): everyone timed, the same order everywhere;
- online practice (two machines, 3 minutes in the FORMULA class): out of their boxes and onto their
  timed laps, one tower, no errors (practice has no finish to check);
- the GT class's rolling start online (the test's race with `--start=rolling`): the formation, the
  green, no penalties, everyone home, the same classification everywhere;
- joining late and leaving: a fourth player joining 70 s into the race starts from the pit lane and
  is classified a lap down, its laps timed to 0.0 ms; one killed 90 s in is DNF and the race finishes
  without them; all agree.

Not done online yet:

- contact between the players (each car runs on its own machine: it needs prediction);
- a quick race's GRID option (online the players start in the roster's order);
- the AI in practice;
- not tried online: a race weekend's race from qualifying's order, a red flag's restart
  (`tests/race_ai_check.gd` tests it alone).

## Still to come (P8)

- a pit strategy screen;
- GT and Formula engine sounds of their own;
- broadcast cameras and championships;
- the wet preset.
