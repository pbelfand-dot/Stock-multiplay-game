# Track Mode: qualifying, races and the AI field

MODES > **TRACK** has four sessions on CINDER RIDGE:

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
  - **CHEQUERED:** once the leader has done the laps, everyone finishes as they next cross the line.
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
- **race:** a 6-car race over 2 laps in the game: the lights, no jump starts, everyone finishing, places changing (18 times in the run that set it), no hard hits, the classification and the results.

## Still to come (P7-P8)

- the FORMULA class (its car, DRS, energy deployment);
- online races (the grid, lights, flags, penalties and results synced from the host);
- a pit strategy screen;
- GT and Formula engine sounds;
- broadcast cameras and championships;
- the wet preset.
