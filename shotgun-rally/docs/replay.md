# Replay

Every run is recorded as you drive it, and you can watch it back with proper cameras: a TV
director's trackside cameras, an FPV drone, a helicopter, cameras bolted to the car, a free
cam to fly anywhere, a free-follow orbit, and cameras you place yourself (with a director
that cuts between them). It works the same in every mode: rally stages, the touge, cut up
(with the traffic) and Track Mode.

- **From the results:** the **REPLAY** button, or **V** (**X** on a controller). It plays the
  run from just before GO.
- **From the pause menu:** **REPLAY** (or **V**): an instant replay of the last 30 seconds
  before you paused, and you can scrub back to the start.

**ESC** or **BACKSPACE** (**B** or **BACK**) leaves it, and the game carries on exactly where it
was: the results, or paused.

## Controls

| | Keyboard / mouse | Controller |
|---|---|---|
| Play / pause | SPACE | A |
| Rewind / fast-forward | hold ← / → (6x) | hold LT / RT (up to 8x), or hold d-pad ◀ / ▶ |
| Step 5 s back / forward | tap ← / → | tap d-pad ◀ / ▶ |
| Speed (0.25x, 0.5x, 1x, 2x, 4x) | ↑ / ↓ (or + / −) | d-pad ▲ / ▼ |
| Scrub | click or drag on the timeline | |
| Jump to the start / the end | HOME / END | START (at the start: the end) |
| Next / previous car to follow | TAB or PAGE DOWN / PAGE UP | Y, RB / LB |
| Next / previous camera | C / X | X |
| Pick a camera | 1 … 9, 0 (the list's first ten) | |
| Place a camera here | P | R3 |
| Director (cuts between the placed cameras) | G (or through C) | through X |
| Clear the placed cameras | DELETE | |
| Hide / show the bar | H | L3 |
| Leave the replay | ESC or BACKSPACE | B or BACK |
| **Free cam:** fly | W A S D | left stick |
| **Free cam:** down / up | Q / E | LB / RB |
| **Free cam:** fast / slow | hold SHIFT / CTRL | RT / LT |
| **Free cam:** look | hold RIGHT MOUSE and move | right stick |
| **Free follow:** orbit | hold RIGHT MOUSE and move, or A / D | right stick |
| **Free follow:** zoom | mouse wheel, or W / S | LT / RT |
| **Free follow:** lower / raise | Q / E | LB / RB |
| **Cockpit:** look round | hold RIGHT MOUSE and move | right stick |

The bar along the bottom shows the timeline (GO in green, the finish in white, where you
paused in red), the time and the total, PLAY / PAUSED / REWIND and the speed, the camera,
the car it follows and the keys (a controller's buttons when one is plugged in). Top left, a
red REPLAY tag.

## The cameras

In the order **C** cycles them (the number keys pick the first ten):

1. **CHASE**: the game's own chase camera (`SeatCam` worked as a rig), the same distance behind
   at any speed, swinging round after the car; rally style on stages, street style (low and
   close) in cut up and on the touge, and Settings' CHASE CAM HEIGHT counts.
2. **COCKPIT**: your seat (the SeatCam's seat view: the crew, the gloves on the wheel, the
   dials, the road's shiver; riding shotgun online, from the co-driver's seat). Another
   driver's car with an interior of its own is seen from its driver's eyes; one without, from
   the hood.
3. **HOOD**: on the bonnet looking down the road, the bonnet in view.
4. **BUMPER**: low on the front bumper.
5. **WHEEL**: low beside the front wheel, looking forward along the flank: the wheel turns,
   steers and rides its spring.
6. **FPV DRONE**: the home screen's drone, reused: a little quad flying a spring round the car,
   swooping from low behind to alongside, over the roof and ahead, banking into its turns, a
   wide lens and a touch of prop wash. It flies on the replay's clock, so it keeps up at 4x and
   hovers when the replay is paused; never into the ground or behind a tree.
7. **HELICOPTER**: high and off to the side, a little behind, tracking (the showcase's).
8. **TRACKSIDE TV**: a camera by the road ~2.5 s ahead of the car, on the outside of the next
   bend: on a stage on a crane 4 m up over the road's edge line (clear of the tree wall; a spot
   with a trunk, a bank or a wall close by is passed over for the next one), on the highway
   beyond its shoulder, on a circuit up a tower past the run-off, over the catch fences. It pans to follow the car and zooms with the distance (the field of view keeps the
   car framed); once the car has gone by, or something's in the way for a moment, the next one
   up the road takes over.
9. **FREE FOLLOW**: an orbit locked on the car, turned with it (eased): orbit, zoom, lower and
   raise it; it keeps following the car.
10. **FREE CAM**: fly anywhere, in real time (pause the replay and fly round a frozen moment).
    It never goes below the ground.
11. **SIDE**: alongside the rear quarter, the flank and the trees flying by.
12. **FRONT**: ahead of the car looking back at it.
13. **CAM 1, CAM 2 …**: placed cameras. **P** drops a camera where the current camera is (fly
    there with the free cam first); it stays put, turns to follow the car and zooms with the
    distance. Place as many as you like.
14. **DIRECTOR**: cuts between the placed cameras by itself: the nearest one that can see the car,
    held at least two seconds before the next cut.

No camera goes below the ground (a ray down from above it; the stage's own land where the ray
finds nothing). Placed cameras are kept for the stage (its mode and seed) in
`replay_cams.cfg` beside the profile, so they're there the next time you drive it.

## How it works

`scripts/game/replay.gd` (the recorder and the player), `scripts/vehicle/replay_cam.gd` (the
cameras), `scripts/ui/replay_bar.gd` (the bar).

**Recording.** The Game lists the cars to record in `replay_targets()`: yours, the other
drivers' online, and a `RaceField`'s cars when one is on the track (any RallyCar can be added;
each gets its own track, keyed by its path under the Game). Every car is sampled 60 times a
second (every other physics tick) from the countdown to the finish: where it is and how it's
turned, its velocity, the steering, the revs and the gear, each spring's squash and each
wheel's spin, the throttle, the brake, the handbrake, the slide and the surface (26 floats).
Cut up's traffic (every car on both carriageways, the ramps', a rival), the touge's stray car
and its ghost are recorded 15 times a second (where each is, how it's turned). Between samples
the playback interpolates.

**Memory.** Each track is a ring that keeps the last **10 minutes**:

| | a minute | the 10 minutes kept |
|---|---|---|
| a car | 366 KB | 3.6 MB |
| cut up's traffic, HARD (~86 cars on screen) | 2.4 MB | 24 MB |

(measured by `tests/replay_check.gd`; a rally stage alone is 3.6 MB at most, eight players
online 29 MB).

**Playback holds the live game.** Alone, the whole scene tree is paused (the physics, the
traffic, the clock, the co-driver mid-sentence). The cars and the moving things are captured
first, then posed from the recording each frame through `RallyCar.replay_pose()`: the wheels
roll, steer and ride their springs, the brake lights come on, the engine sounds its recorded
revs and throttle, the dust flies when the car slides. When you leave, everything is put back
exactly as it was (transform, velocities, wheel spin, springs, steering; the drivetrain and the
tyres' state are never touched), and the run carries on.

**Online the replay is local.** The session can't stop for one player: while you watch, your
car waits on the brake as it does in the pause menu (still simulated, still streamed), and the
others' streams keep coming in. The poses are laid over the live scene each frame and taken off
again at the start of every physics tick, so nothing posed is ever simulated or sent to anyone,
and the host's traffic keeps running round everyone.

## Tests

`tests/replay_check.gd` (in `tests/run_all.sh`), on real runs with the autopilot driving:

- recording: ~20 s of a rally stage, 60 samples a second, the memory measured;
- pose: at sampled times the car played back sits where it was recorded (to the mm at the
  samples, within a cm between them), its springs and wheel spin too;
- controls: scrubbing back and forward (and the timeline clicked and dragged), the speed (the
  clock runs at 0.25x, 1x and 4x), rewind held, a tap steps 5 s, the end stops it, the start;
- cameras: every mode a sane view (near the car where it should be, above the ground, the car
  in view or the camera looking down the road with it), the trackside camera handing over, the
  free cam flying on its keys and stopping above the ground, a placed camera turning onto the
  car, the director cutting between two;
- exit: the car exactly as it was live, the tree running, the pause menu or the results back,
  the run carrying on;
- cut up: the traffic played back where it was and put back exactly;
- the touge and Track Mode: a replay opens, films the car and closes.

`tools/replay_shots.gd` takes pictures of every camera (under xvfb; `--seen_cars_only`).
