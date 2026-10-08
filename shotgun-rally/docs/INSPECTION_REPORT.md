# Full inspection (October 2026): what was found and fixed

The owner asked for the whole game to be gone through after the world release, and said "the
steering wheel also locks". This is what was checked, what was wrong, and what changed.

## The steering lock

**Found: the car stuck to barriers, and steering away did nothing.** The steering itself was
fine. The keys and a stick were driven through the real game (`Input` presses, rally, touge and
cut up, ARCADE and SIM handling), and the rack always followed the input and came back when it
was let go. The lock was what the steering was turning against.

- **Each wheel finds the ground by sweeping a sphere the tyre's radius down its strut.** That
  sphere is wider than the tyre (0.64 m across against a 0.2 m tread). Driven alongside a barrier,
  its side touched the barrier's face before the road.
  - The game took the wall for the ground.
  - Both wheels on that side "stood" on it with no load and no grip.
  - The car slumped against the barrier.
- **The loop's road also stopped at the shoulder, 0.4 m short of its guardrails and parapets.** A
  wheel pushed against one dropped into the slot and the car hung on the road's edge.
- **Measured in cut up:** the car hit the barrier at 120 km/h and was then held on full left lock
  at 72 km/h for 3 s. Its heading didn't change by a degree, and it stayed glued to the barrier.
  One tick even kicked a wheel with 72 kN.

**Fixed:**

1. **A steep contact gets a second look** (`rally_wheel.gd`).
   - If the sphere's hit is more than ~45° off the strut, a small sphere inside the tread sweeps
     the same travel.
   - If that only finds the wall too, a ray goes straight down the strut's line.
   - A wall with no ground under it is no longer ground.
2. **The loop is paved up to its barriers.** The 0.4 m strip between the road's edge and each
   guardrail or parapet is now road surface, and solid (`loop_builder.gd _ledge`).
3. **The stage barriers are one solid each,** not a box per 2 m piece:
   - the mountain and touge armco and walls;
   - the highway's concrete;
   - the town's crowd barriers;
   - the bridge rails and their wheel guards.

   A car scraping along the separate boxes caught on their seams and stopped dead (52 to 5 km/h
   on a touge guardrail). The pieces now meet at the very same points in one mesh, and the car
   slides along.

**Now:** in the same cut-up run, steering left turns the car off the barrier at once. It is
11 m off it in 1.6 s. **New test, `tests/barrier_check.gd`** (in `run_all.sh`), which scrapes:

- the loop's guardrail and parapet at 100 km/h;
- a touge guardrail at 55;
- mountain armco at 70.

| Run | Wheel-ticks on the barrier's face or hanging (of 196) | Off the barrier 2 s after steering away |
|---|---|---|
| Loop guardrail, before | 194 | 2.6 m |
| Loop guardrail, now | 0 | 16.8 m |
| Loop parapet, before | 196 | 3.3 m |
| Loop parapet, now | 0 | 16.8 m |
| Touge guardrail, before | 110 | 7.5 m |
| Touge guardrail, now | 0 | 10.0 m |
| Mountain armco, before | 174 | 15.2 m |
| Mountain armco, now | 0 | 14.2 m |

## The cockpit's steering wheel: the hands bunched together

Steering to full lock (the wheel turns about 258°) could leave both gloves on one spot on top
of the rim, one inside the other. The hand-over-hand logic measured each hand's angle wrapped to
±180°. A big turn between two frames, on a slow machine or straight after a reset, read as a turn
the other way, and the hands took their new grips on top of each other.

**Fixed (`driver_hands.gd`):**

- The angle is measured unwrapped, from where the hand took hold.
- A new grip is never within ~50° of the other hand.

Measured (`tests/cockpit_check.gd` now checks it):

| Winding to full lock | Closest the gloves got | Apart while the lock is held |
|---|---|---|
| 60 fps, before | 0.9 cm | 0.32 m |
| 60 fps, now | 6 cm | 0.15 m |
| 8 fps, before | 5 cm | 0.11 m (touching) |
| 8 fps, now | 17 cm | 0.17 m |

## Everything else checked

| Area | How | Found |
|---|---|---|
| Menus: home, maps, cars, online, settings, modes | Screenshots, fresh profile | 3 text errors (below) |
| Garage numbers | Every car's spec line against its simulated engine | 5 mismatches (below) |
| Quick play gravel, tarmac with ice, a story stage, a downhill drift touge, insane cut up with the mixed toll | Autopilot runs, logs scanned | No script errors. One warning: the mirror camera (fixed). |
| In the car | Screenshots of the rally cockpit, full lock, night touge, the loop's city, a mountain stage, the results, the loading screen | The hands (above); the results text (below) |
| The loop | Its length, bridges and tunnels against the menu's text | 28.0 km, 3 bridges, 3 tunnels: correct |
| Every test suite | `tests/run_all.sh` | All green, including online (2-player, street session, 3-player cut up) and the updater |

**Fixed along the way:**

- **The home screen said the series has six rallies.** It has nine (the Maps panel had it right).
- **The MODES button's line ran past its card.** It's shorter now.
- **After a touge or cut-up run the results said "ENTER next stage".** It's "new pass" or "new run"
  now, which is what ENTER does.
- **The garage's spec line didn't match the engine in the game** for the four rally cars. They
  said 280-325 hp; their engines make 10-16 % more. They're fictional cars, so the spec line now
  says what the game gives: Kestrel 307, Comet 331, Vortex 346, Martello 368 hp. Every other car
  already matched within 1 %.
- **The Brawler said 360 hp and gives 304 PS.** That one's on purpose: the 1970 rating is SAE
  gross, and the physics uses the net figure. It now says "360 hp SAE gross".
- **The rear-view mirror's camera** logged a physics-interpolation warning every run. It's placed
  every frame, so it no longer interpolates.

## Not changed: three aids that can feel like "locked" steering

If the steering still feels locked, it may be one of these. Each is a switch in **Settings >
DRIVING AIDS**.

- **SPEED-SENSITIVE STEERING (on out of the box).**
  - At speed, full input asks only for what the front tyres can use: about 10° at 60 km/h and 6°
    at 120.
  - The cockpit's wheel turns that much, not the full 258°.
- **DRIFT ASSIST (on, rally stages and ARCADE street).**
  - In a drift it points the front wheels where the car is going.
  - Your steering sets the drift's angle, not the wheels'.
  - Steering into the corner shows countersteer on the wheel.
- **The wheel's 258° stop.** Like a real car's lock, past it the wheel doesn't turn any further.
