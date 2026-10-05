# Rally physics rebuild: inspection and plan

Status: **phases 1-5 done** (the chassis on its suspension; the tyres' side grip and the
steering; the wheels' spin, the drive / brake force and the brakes; the combined-slip ellipse and
load sensitivity; the engine, clutch, sequential gearbox and four-wheel-drive diffs; in the lab,
see "Phase reports" at the end). Decisions:
- built **alongside** the current car (a lab scene, a `--physics=v2` switch once it drives), and it
  becomes the car once it passes every current test plus the manoeuvre tests;
- physics at **120 Hz** (set by whatever runs the v2 car, so the current car and the auto-updater's
  `project.godot` stay as they are until the switch);
- **every driver aid is its own switch in Settings** (ABS, traction control, stability control,
  steering smoothing, steering damping, countersteer help, speed-sensitive steering); the base
  physics is the same whatever is switched on.

The brief: a custom rally-car physics system in GDScript on a `RigidBody3D` chassis (no
`VehicleBody3D`), with its own wheels, suspension, tyres, drivetrain and surfaces, closer to Dirt
Rally / RBR / BeamNG than to an arcade racer, and controllable with a controller. Built in nine
phases, each tested before the next.

## 1. What already exists (`scripts/vehicle/rally_car.gd`, 675 lines, one script)

### Keep: it already matches the brief

| Brief item | What's there now |
|---|---|
| RigidBody3D chassis, forces at each contact patch | `apply_force(n*Fz + f*Fx + side*Fy, r)` per wheel at its contact point: pitch and roll emerge |
| Contact-point velocity, not just `linear_velocity` | `vp = v + ω × r`, then split into longitudinal / lateral along the wheel's own axes (front wheels at their steering angle) |
| Slip angle, safe at low speed | `atan2(v_lat, |v_long|)`, with a relaxation length (0.4 m) so the force builds as the tyre rolls |
| A lateral curve that peaks and falls off | Magic-Formula shape `sin(C·atan(B·x))`, peak at the surface's own slip angle, slow fall-off past it |
| Per-wheel spin, inertia, slip ratio | `omega[k]`, `WHEEL_I`, `κ = (ωr − v_long) / max(|v_long|, 3 m/s)`, an implicit step so it doesn't oscillate |
| Friction circle | one combined slip vector (κ and α, each in "peaks"), the grip shared out along it |
| Load sensitivity | μ falls 15 % per extra static load |
| Spring, separate bump / rebound damping, bump stops | progressive hydraulic bump stop, position-sensitive rebound |
| Anti-roll bars | force from the left/right compression difference, front and rear separate |
| Drag | `−v·|v|·DRAG` |
| Surfaces by collider | `meta "surface"` on every stage body; per-surface μ, peak slip angle, peak slip ratio; the road's lane grip (wheel tracks / crown / loose edges) |
| Networking | the driver's machine simulates, streams 30 Hz state to the co-driver's machine (interpolated) |
| Public API the rest of the game uses | `inp`, `steer`, `speed`, `rpm`, `gear`, `comp[]`, `omega[]`, `wheel_slip[]`, `grounded`, `on_surface`, `place()`, `set_lanes()`, `kmh()`, `apply_setup()`, `set_simulating()`, `hit` / `landed` signals; used by the game, cockpit, drift dirt, autopilot, AI co-driver and 9 tests |

### Replace: fakes the brief forbids, or missing pieces

| Problem | Why it has to go | Replaced by |
|---|---|---|
| `steer_target()` turns the stick into "the tyre's best slip angle" inside the physics | input assistance welded into physical steering | rack ratio + Ackermann in the physics; any help lives in `DriverAssist` (optional) |
| `AIR_LEVEL` torque turns the car toward the ground in the air | a scripted correction | nothing: the car flies as it was launched |
| `AIR_BRAKE` / `AIR_GAS` pitch torques | scripted | the wheels' own spin: braking spinning wheels hands their momentum to the body (reaction torque), so the nose dips by itself |
| Handbrake sets the rear `omega = 0` + a special "locked tyre" path | scripted lock | handbrake torque on the rear wheels through the same wheel model: they lock only when the torque beats the grip. (Kept: the hydraulic handbrake opens the centre coupling, as real rally cars do) |
| Diffs that average wheel speeds (`DIFF_LOCK`, `CENTRE_LOCK`) | not torque-based | open / locked / LSD (power lock, coast lock, preload) acting on torque from the wheel-speed difference |
| Engine = constant power, gears by speed thresholds, rpm only for sound | no engine at all | RPM, torque curve, inertia, throttle response, engine braking, limiter, turbo; clutch; sequential box with ratios, final drive, shift time |
| Low-speed "parked / creeping" clamp, `TYRE_GIVE` smoothing | special cases | a proper low-speed tyre (slip floor + a damped "sticking" spring at standstill) and a ShapeCast that rolls over panel joints |
| ~50 constants at the top of one file | not tunable | Resources (`CarConfig`, `TireConfig`, …) edited in the inspector, saved as `.tres` |
| Missing | — | asphalt / snow / ice surfaces, aero (drag + downforce with front/rear balance), configurable centre of mass and inertia, ABS / TC / ESC, debug HUD and force vectors |

## 2. Architecture

### Scene: `scenes/rally_car_v2.tscn`

```
RallyCarV2 (RigidBody3D)                   rally_car_v2.gd     config: CarConfig (.tres)
├── CollisionShape3D                       convex hull of the body (low, so it can roll over and slide on its roof)
├── CarMesh (Node3D)                       the body model + livery (visual only)
├── CenterOfMass (Marker3D)                its position = RigidBody3D.center_of_mass (custom mode), drawn in debug
├── FL_WheelPoint (Node3D)                 rally_wheel.gd      the suspension mount (top of travel)
│   ├── ShapeCast3D                        a sphere the tyre's radius, cast down the travel
│   └── WheelMesh (Node3D)                 placed from the simulation each frame (visual only)
├── FR_WheelPoint …  RL_WheelPoint …  RR_WheelPoint …
├── Telemetry (CanvasLayer)                rally_telemetry.gd  F3 HUD, F4 force vectors
```

ShapeCast3D, not RayCast3D: a ray drops into every crack between road panels and catches edges;
a sphere rolls over them like a tyre and gives the true contact point and normal.

### Scripts: `scripts/vehicle/physics/`

| Script | Job |
|---|---|
| `rally_car_v2.gd` | coordinator (named v2 while both cars exist): input → `DriverAssist` (optional) → steering → drivetrain → wheels → aero; keeps today's public API, so the game, cockpit, FX, autopilot and network don't change |
| `rally_wheel.gd` | one wheel: the cast, contact, compression and its velocity, load, wheel spin; asks `TireModel` for forces; applies them at the contact |
| `suspension.gd` | spring, bump / rebound damping, bump stop, max force (pure functions) |
| `tire_model.gd` | slip → forces: separate longitudinal / lateral curves per surface, combined-slip ellipse, load sensitivity, relaxation, the loose-gravel "wedge" (extra resistance building in front of a sliding tyre on loose surfaces) |
| `engine.gd` | RPM, torque curve (a `Curve`), inertia, throttle response, engine braking, rev limiter, turbo spool |
| `gearbox.gd` | sequential: ratios, final drive, neutral, reverse, shift timing, the clutch |
| `differential.gd` | open / locked / LSD with power lock, coast lock, preload |
| `drivetrain.gd` | engine → clutch → gearbox → centre diff → front / rear diffs → wheels, solved together (implicit, sub-stepped) |
| `surface_detector.gd` | collider → `RallySurface`: the body's `surface` metadata (already on every stage body) names a `.tres` |
| `driver_assist.gd` | ABS, traction control, stability control, steering filtering / damping, countersteer help, speed-sensitive steering: all optional, off for the base physics |
| `rally_telemetry.gd` | the HUD (every wheel's numbers + the car's) and the debug drawing |

### Resources: `scripts/vehicle/physics/config/` → `data/`

`CarConfig` (mass, centre of mass x / y / z, inertia, wheel positions, brakes and bias, handbrake,
aero: Cd, frontal area, downforce and its front/rear balance), `SuspensionConfig`, `TireConfig`,
`EngineConfig`, `DrivetrainConfig`, `DifferentialConfig`, `SteeringConfig` (rack ratio, max angle,
Ackermann, smoothing, controller curve), `AssistConfig`, `RallySurface`.

- `data/cars/awd_rally.tres`: the first profile, a modern AWD rally car: ~1,280 kg, front-mounted
  turbo engine, 5-speed sequential, short wheelbase (~2.5 m), gravel tyres, long-travel
  suspension, strong brakes, hydraulic handbrake.
- `data/surfaces/`: dry asphalt, wet asphalt, gravel, compact dirt, loose dirt, mud, snow, ice,
  grass. The stage's surfaces map onto these: the road's wheel tracks → compact dirt, its crown
  and edges → loose gravel, the verges → grass, the puddles → mud.

## 3. Physics tick rate: 120 Hz

The stiff part is the wheel spin. With a wheel's inertia ~1.2 kg·m² against a gravel tyre's slip
stiffness (~20 kN per unit slip ratio at normal load, r ≈ 0.31 m), slip settles with a time
constant of about `I·v / (C·r²)`: ~3 ms at 5 m/s, under 1 ms near a standstill. A plain (explicit)
integration step would need to be shorter than that to stay stable, which no tick rate gives, so
the wheels and the drivetrain are integrated implicitly and sub-stepped inside each tick (cheap:
a few numbers per wheel). The body itself is gentle (~1.5 Hz on its springs), but landings put
the bump stops at ~25 rad/s; 120 Hz keeps those steps small and halves the error everywhere else.

- **Project Settings → Physics → Common → Physics Ticks per Second: 120** (from 60).
- **Physics interpolation: on** (it already is): smooth at any frame rate, nothing depends on the
  rendering FPS.
- 240 Hz isn't needed for one car and doubles the cost. One car is 4 shape casts and some
  arithmetic per tick: GDScript is fast enough, no need for C#.

## 4. How it replaces the current car

Built next to the current car, not on top of it. A physics lab scene (`scenes/physics_lab.tscn`: a
flat pad, bumps and potholes, a skid pad, a slalom, a jump and a crest, asphalt / gravel / snow /
ice patches) to drive and watch the HUD in, a `--physics=v2` flag to try it on real stages, and a
headless test for every phase. When it passes all of today's tests (driving whole stages, handling,
ride, jumps, run-off) plus the manoeuvre tests below, it becomes the car, the autopilot is retuned to
it, and the old script goes.

## 5. Phases and their tests

| Phase | Built | Tested (headless, numbers) |
|---|---|---|
| 1 | chassis, 4 ShapeCast suspensions, debug drawing, HUD (suspension) | sits level at its static ride height; ~1.5 Hz bounce that settles; a drop lands without a bounce war; driving over bumps pitches and rolls it (forces at the corners) |
| 2 | contact velocity, slip angle, lateral force | steady cornering on a skid pad: lateral g vs steering, the front and rear slip angles |
| 3 | wheel spin, slip ratio, longitudinal force, brakes | 0–100, braking distance; locking only when brake torque beats grip |
| 4 | combined-slip ellipse, load sensitivity | braking while turning loses cornering; trail braking rotates the car |
| 5 | engine, clutch, sequential box, AWD diffs | wheelspin off the line, gear changes, the diff settings changing power-on balance |
| 6 | surfaces | the same manoeuvres on asphalt / gravel / snow / ice give the right different numbers |
| 7 | handbrake, anti-roll bars, advanced suspension | handbrake hairpin, roll-bar changes moving the balance |
| 8 | aero, driver aids, telemetry | downforce ~nothing at 30 km/h, noticeable at 150; aids off = same car |
| 9 | full rally tuning | lift-off oversteer, power oversteer, four-wheel drift, countersteer catch, Scandinavian flick, pendulum, slide-to-slide transitions: each driven by a scripted input sequence and measured. None of them has its own code: they come from the tyres |

## Phase reports

### Phase 1: the chassis on four ShapeCast suspensions

**1. The code**
- `scripts/vehicle/physics/config/car_config.gd`: `CarConfig` (mass, centre of mass, inertia, axle
  positions and tracks, mount height, tyre radius and width, a suspension per axle, the collision
  boxes; `mounts()`, `static_loads()`).
- `scripts/vehicle/physics/config/suspension_config.gd`: `SuspensionConfig` (travel, spring rate,
  bump / rebound damping, bump-stop start / rate / damping, max force).
- `scripts/vehicle/physics/suspension.gd`: the force (spring + damper + progressive bump stop,
  never pulling), the static squash under a load, the ride frequency, the damping ratios.
- `scripts/vehicle/physics/rally_wheel.gd`: one corner. Sweeps a tyre-sized sphere down the travel
  every tick (`force_shapecast_update`), works out the compression and its speed, pushes the body
  up **at the contact patch, along the ground's normal**, by the strut force's share square to the
  ground (the tyre's load, for phase 2). The wheel's look follows.
- `scripts/vehicle/physics/rally_car_v2.gd`: the body (mass / CoM / inertia from the config, no
  damping of its own), builds or finds the four `*_WheelPoint`s, steps them each tick, `place()`,
  `ride_height()`, the same public names as the current car where they exist.
- `scripts/vehicle/physics/rally_telemetry.gd`: F3 numbers, F4 force arrows.
- `data/cars/awd_rally.tres`: the first car. `scenes/rally_car_v2.tscn`: the car scene.
  `scenes/physics_lab.tscn` + `scripts/physics_lab.gd`: the lab. `tests/physics_v2_check.gd`.

**2. Where it goes:** as listed (everything new; the game doesn't use it yet).

**3. The nodes:** `RallyCarV2` (RigidBody3D, `rally_car_v2.gd`, `config` = the .tres) > `Body`,
`Cabin` (CollisionShape3D), `CarMesh` (the look), `CenterOfMass` (Marker3D), `FL_WheelPoint`,
`FR_WheelPoint`, `RL_WheelPoint`, `RR_WheelPoint` (Node3D, `rally_wheel.gd`, `front` on / off) each
with a `ShapeCast3D` and a `WheelMesh`, `Telemetry` (CanvasLayer). The script sets the casts up
(sphere = tyre radius, cast = the travel, mask 1, the car excluded).

**4. In the inspector** (`data/cars/awd_rally.tres`): 1,280 kg; centre of mass (0, -0.05, -0.12)
(55 % on the front axle); inertia (1850, 2050, 520) kg m²; axles at -1.24 / +1.26 (2.5 m wheelbase),
1.54 m tracks; 0.32 m tyres; 300 mm travel; springs 31.0 / 25.5 kN/m front / rear (1.49 / 1.50 Hz
with each corner's weight); dampers 1,900 bump / 3,400 rebound front, 1,600 / 2,900 rear
(about 0.3 / 0.5 of critical); bump stops from 220 mm, 4×10⁶ N/m², 9,000 N/(m/s).

**5. How to test:** `godot --path . scenes/physics_lab.tscn` (R reset, J drop from 1 m, B the bumps,
N the left-side bumps, F3 / F4), or headless:
`godot --headless --fixed-fps 120 --path . -s tests/physics_v2_check.gd` (in `tests/run_all.sh`).

**6. What correct looks like** (what the test measured):
- standing still: each corner squashed by its weight over its spring, 111 / 110 mm (within 1.1 mm),
  the mounts at the 0.509 m ride height, level (pitch -0.03°, roll 0.00°), still;
- lifted 5 cm and let go: it bounces at ~1.2 Hz (1.5 Hz springs, slowed by the damping) and is
  within 0.1 mm of settled 2 s later;
- dropped from 1 m: 264 of the 300 mm travel used (into the bump stops), the body stays 175 mm off
  the ground, no wheel leaves the ground again, settled within 5 mm in 0.9 s;
- over the 8 cm bumps at 12 m/s: pitches up to 0.9° with 0.02° of roll; over bumps under the left
  wheels only: rolls up to 0.9°. Nothing levels it: pitch and roll come from where the forces act.

**7. Bugs found:** in a headless test run, scripts it loads can't name the autoloads (`Config`):
the lab looks it up by path instead. A test that can't load its car now fails at once instead of
looping on errors until the time limit.

No tyre grip yet: the car rolls like it's on ice (phase 2 adds contact velocity, slip angle and the
lateral force).

### Phase 2: contact velocity, slip angle, side force, steering

**1. The code**
- `config/tire_config.gd`: `TireConfig` (lateral mu, peak slip angle, Magic Formula shape,
  relaxation length, standstill damping). `config/steering_config.gd`: `SteeringConfig` (lock,
  rack speed, Ackermann). Both on `CarConfig` (`front_tire`, `rear_tire`, `steering`).
- `tire_model.gd`: the side force (`mu x load x sin(C atan(B slip))`, B from the peak angle), the
  cornering stiffness, and the slip state: `d(slip)/dt = (-v_y - |v_x| slip) / relaxation_length`,
  stepped implicitly. At speed it's the slip angle (lagging over the relaxation length); at a
  standstill it winds up with the patch's sideways movement, so the carcass is a spring and a
  parked car holds; crawling and sliding, it's capped where the tyre lets go.
- `rally_wheel.gd`: the contact patch's velocity (`v + omega x r` to the patch), split along /
  across the wheel's heading in the ground's plane; the side force pushed at the patch. Also: the
  compression is now solved exactly from the contact point and the ground's normal (the cast's own
  distance comes in ~2 mm steps, which read as jolts of suspension speed: noisy loads).
- `rally_car_v2.gd`: the steering. Input x lock, no faster than the rack, split by Ackermann (the
  inside wheel turns more); the wheel nodes turn; `wheel_angles`, `accel`.
- The lab: a skid pad, a 10 degree side slope, the tow (C: 15 m/s through the centre of mass,
  standing in for the engine until phase 5), arrow keys steer. Telemetry: slip angle and side
  force per wheel, lateral g, the steering; orange side-force arrows.

**2-3. Where / nodes:** as phase 1; the `*_WheelPoint` nodes now turn (their Y rotation is the
steering).

**4. In the inspector:** tyres mu 1.0, peak 7 degrees (a gravel tyre peaks late), shape 1.35 (85 %
left far past the peak), relaxation 0.35 m, standstill damping 8,000 N/(m/s). Steering: 30 degree
lock, 180 deg/s at the road wheels, Ackermann 0.4.

**5. How to test:** the lab (arrows + C on the skid pad, S for the slope), or
`tests/physics_v2_check.gd`.

**6. What correct looks like** (measured):
- skid pad at 15 m/s: 2 degrees of steering gives 3.14 m/s² (the geometry predicts 3.14), 4 degrees
  6.22 (6.28): below the limit the car goes where it's steered, front and rear slip equal
  (0.75 / 0.75, 1.70 / 1.71 degrees: neutral, as tyres whose grip is proportional to load must be);
  8 degrees reaches the limit, 9.4 m/s² (0.96 g); 15 degrees stays there (9.3 m/s²) with the fronts
  past their peak (12.6 degrees) and the rears at 4: it understeers at the limit and never exceeds
  mu g. At the limit it hunts slowly, as a real car does; it never spins or lifts a wheel;
- body roll ~5 degrees at 1 g, the outside tyres carrying ~80 % of the load (no anti-roll bars yet);
- parked across a 10 degree slope with no brakes: holds, 0.0 mm of creep;
- straight at 20 m/s: 0.00 deg/s of yaw.

**7. Bugs found:** the cast's coarse distance (fixed: solved exactly); the first slip model
unwound at a minimum speed, which made a parked car creep 1.6 mm/s (fixed: no floor, a slide cap
instead); a car put down kept its old steering lock (fixed: `place()` straightens the wheels).

Balance note: with every tyre's grip exactly proportional to its load, the car is neutral until
the fronts pass their peak. Load sensitivity (phase 4) and the anti-roll bars (phase 7) are what
give a real car its balance; there's no drive yet, so no power oversteer either.

### Phase 3: wheel spin, slip ratio, the force along the wheel, brakes

**1. The code**
- `tire_model.gd`: the force along the wheel (`mu x load x sin(C atan(B slip))`, its own peak and
  shape) and `spin_step()`: the wheel's spin and its slip-ratio state solved together, implicitly
  (backward Euler, the tyre force linearised about the current slip):
  `inertia x d(spin)/dt = drive - force x radius - friction` and
  `d(slip)/dt = ((spin x radius - v_x) - |v_x| slip) / longitudinal_relaxation`. The brakes and
  rolling resistance are friction torques: they slow the wheel, can hold it, never turn it back,
  so a wheel locks only when its brake beats what its tyre can take from the road. Slow or
  stopped, the carcass is damped along the wheel as across it. `air_spin()` for a wheel in the air.
- `rally_wheel.gd`: each wheel has its own spin (`omega`), `drive_torque` (the drivetrain will set
  it in phase 5; the lab and the tests do now) and `brake_torque`. The tyre (both directions) is
  stepped 8 times a tick with the body's velocity held; the body gets the average force. Side and
  drive / brake force together are capped at mu x load (phase 4 makes that the combined-slip
  ellipse). `set_speed()` on the car launches it with its wheels turning.
- `rally_car_v2.gd`: the brake pedal x the brakes' torque, split by the bias.
- Config: `TireConfig` longitudinal mu / peak / shape / relaxation, rolling resistance;
  `CarConfig` wheel inertia, brake torque, brake bias.
- Lab: up / W a test torque on all four wheels (600 N m each), down / S the brakes, O nose up the
  slope. Telemetry: each wheel's own speed, slip ratio, drive / brake force, LOCKED; violet arrows.

**4. In the inspector:** longitudinal mu 1.0, peak slip 0.15 (gravel digs in: late), shape 1.45
(a locked tyre keeps 83 % at -100 % slip), relaxation 0.12 m, rolling resistance 0.025; wheel
inertia 1.1 kg m²; brakes 5,000 N m at full pedal, 70 % on the front (they lock first, so it stays
straight).

**6. What correct looks like** (measured):
- 400 N m on each wheel: 3.56 m/s² (torque / (mass + the wheels' spin inertia), minus rolling
  resistance: 3.54), the tyres slipping under 4 %;
- 2,500 N m on each wheel (more than the grip): wheelspin, 7.5 m/s², what the tyres can take;
- brakes at 30 %: 3.78 m/s² exactly as the brakes' torque gives, no locking (slip under 4 %);
- full brakes from 100 km/h: all four lock (the rears, whose brakes only just beat their grip, a
  moment later), stopped in 47 m and 3.3 s, 0.85 g on locked tyres, the nose down 1.6 degrees and
  70 % of the load on the front;
- coasting: rolling resistance, 0.237 m/s² (as predicted);
- nose up a 10 degree slope: held by the brakes, 0.0 mm; brakes off, it rolls back down at 1.39 m/s²
  (gravity minus rolling resistance: 1.41).

**7. Bugs found:** a braked car rocked on its tyres on a slope (the carcass's fore-aft spring had no
damping at a standstill: fixed); a test applied the previous run's torque for one tick (fixed);
scripts that place a car before it's in the scene tree now get a car that waits.

No engine yet: the drive is a test torque, so there's no rev limit and a wheel given more than its
grip spins up without end. Phase 5 brings the engine, clutch, gearbox and diffs.

### Phase 4: the combined-slip ellipse, load sensitivity

**1. The code**
- `tire_model.gd`: `combined()`: each slip measured against its own peak (slip ratio / peak, tan
  slip angle / peak), one combined slip from the two, each force its own curve at the combined
  slip, shared out in the direction of the slip. At the limit the forces trace an ellipse; with one
  slip it's exactly that slip's curve (phases 2-3 unchanged). The wheel-spin solve takes the
  combined force's slope along the slip ratio, so braking in a turn and turning while braking are
  solved together. `load_mu_factor()`: `mu x (1 - load_sensitivity x (load / nominal - 1))`.
- `rally_wheel.gd`: both forces from `combined()`; mu scaled by the load. The circle cap from phase
  3 now only catches the standstill damping's extra.
- `TireConfig`: nominal load 3,200 N, load sensitivity 0.12.

**6. What correct looks like** (measured):
- at the cornering limit (9.2 m/s²), 40 % brakes: the cornering drops to 6.5 m/s², and braking and
  cornering together never pass 9.2 m/s² (the tyres' 9.8);
- entering a corner under the limit (2.5 degrees at 20 m/s, ~7 m/s²): coasting, the car turns a
  touch less than the geometry asks (0.96: mild understeer); braking at 25 %, it rotates 25 % more
  (1.20), the rear slip angle overtaking the front (2.6 vs 2.1 degrees) as the nose loads and the
  tail goes light. That's trail braking, and no code asks for it;
- a tyre with twice the load grips 12 % less per newton;
- the skid pad: load sensitivity alone now gives the car its mild understeer (front slip above the
  rear: 5.9 vs 4.2 degrees at 8 degrees of steering), the limit is 0.93 g (the outside tyres,
  carrying most of the load, grip less per newton), and the slow hunt at the limit is gone (an
  understeering car is stable there).

**7. Bugs found:** none in the code. The first trail-braking test used a corner (5 degrees at
20 m/s, asking for 14 m/s²) far past the tyres' grip: both runs were four-wheel slides, which
proves nothing about trail braking; it now uses a corner under the limit.

### Phase 5: engine, clutch, sequential gearbox, four-wheel-drive diffs

**1. The code**
- `engine.gd` (pure functions): the torque curve (points, straight lines between), the turbo
  (a share of the torque that comes with boost; boost spools between two rpm figures over a spool
  time, anti-lag keeping it up off the throttle), friction (fixed + per rpm, more with the throttle
  shut: that's engine braking), power.
- `drivetrain.gd` (the state: engine spin, boost, gear, clutch):
  - `control()`, once a tick: the shift timer (a sequential box: the drive is cut for 0.06 s and
    the next gear is in), the limiter (cuts at 7,600 rpm, back on 150 rpm lower), idle control,
    the boost, the automatic clutch (out in neutral and while shifting; pulling away it takes up
    as the revs rise, higher with more throttle; rolling it's in), auto-shift (up at 7,200 rpm,
    down at 3,300 if the lower gear won't over-rev).
  - `solve()`, each of the 8 substeps: the engine and the four wheels together. The engine spins up
    with its torque and down with its friction; each wheel brings its spin from its tyre alone
    and how heavy it feels (its inertia plus the tyre's grip resisting a change of speed). Then the
    couplings, as friction-limited constraints solved 8 times round (sequential impulses): the
    clutch (engine speed = ratio x the driveline's speed, up to the clutch's capacity, then it
    slips carrying its capacity), the centre diff (front / rear), the front and rear diffs
    (left / right), and the brakes and rolling resistance (friction holding each wheel, up to
    their torque). An **open** diff adds nothing (so a light wheel spins up and its partner gets
    only what it takes to spin it); **locked** holds both sides together; an **LSD** holds them
    together up to preload + lock x the torque going through it (power and coast figures). None
    of the diffs' behaviour is scripted: it's the couplings and the tyres.
- `tire_model.gd`: the wheel's spin solve is split in two so the drivetrain can sit in between:
  `spin_predict()` (the tyre alone, implicit, returning the effective inertia) and
  `slip_after()` (the slip ratio follows the final spin). Phase 3's `spin_step()` is gone.
- `rally_wheel.gd`: `tyre_predict()` / `tyre_finalize()` around the drivetrain each substep;
  `resist_torque` (brake + rolling resistance) for the solver.
- `rally_car_v2.gd`: the substep loop (predict → drivetrain → finalize, 8 times, then the forces);
  `gear` and `rpm`; the pedals: stopped in gear and holding the brake for 0.35 s selects reverse,
  where the brake pedal drives it backwards and the throttle brakes (as in the current car).
- Config: `EngineConfig`, `DrivetrainConfig`, `DifferentialConfig` (`data/cars/awd_rally.tres`
  has all three as sub-resources).
- Lab: up / W is now the throttle through the engine, E / Q change up / down (it also changes by
  itself), `--lab=launch` a full-throttle start. Telemetry (F3): an engine line (rpm, gear,
  throttle, boost, clutch, engine torque, what the clutch carries, SHIFT / LIMITER).

**2. Where:** `scripts/vehicle/physics/engine.gd`, `drivetrain.gd`,
`config/engine_config.gd`, `config/drivetrain_config.gd`, `config/differential_config.gd`.

**3. Nodes:** none new: the drivetrain is a plain object the car owns (`car.drivetrain`), set up
from `CarConfig.engine` / `.drivetrain`. A car with no engine config keeps phase 4's free wheels.

**4. In the inspector** (`data/cars/awd_rally.tres` → Engine / Drivetrain):
- engine: 400 N m peak at 4,000 rpm, 229 kW (307 hp) at 7,000, idle 1,000, limiter 7,600, inertia
  0.15 kg m², friction 15 + 0.004 / rpm (+ 0.006 / rpm with the throttle shut), turbo 35 % of the
  torque, spooling 2,200-3,800 rpm in 0.35 s, anti-lag on. (A Rally2 car quotes about 214 kW and
  425 N m; phase 9 tunes the curve.)
- gearbox: 2.92 / 2.05 / 1.60 / 1.29 / 1.06, final drive 4.7 (63 / 90 / 116 / 143 / 174 km/h at
  7,200 rpm; 184 km/h on the limiter), reverse 3.0, 0.06 s shifts; clutch 600 N m, launch rpm 4,000.
- four-wheel drive: 50 / 50; centre **locked** (Rally2 cars have no centre diff at all, a solid
  shaft, which is the same thing); front LSD 0.4 power / 0.2 coast / 50 N m preload; rear LSD
  0.6 / 0.35 / 70 N m. Auto-shift on (an aid: it'll be its own Settings switch in phase 8).

**5. How to test:** `godot --headless --fixed-fps 120 --path . -s tests/physics_v2_check.gd`
(phases 1-4 run in neutral so their numbers stay about the tyres; phase 5 adds five runs). In the
lab: hold W from a standstill, watch the engine line with F3.

**6. What correct looks like** (measured):
- full throttle from a standstill: 0-100 km/h in **4.9 s**, the tyres slipping up to 20 % pulling
  away (gravel digs in at 15 %); it changes up by itself at ~7,200 rpm, and in each gear the engine
  turns at exactly the gear's ratio x the wheels' speed (within 3 %), so each change drops the revs
  by the ratio (7,229 → 5,677 rpm for 1 → 2: x0.70); the limiter holds it under 7,230 rpm;
- the clutch carries +178 N m on average pulling away (+ = driving);
- lifting off in third at 80 km/h: engine braking, 1.25 m/s² (coasting in neutral: 0.24), the
  clutch carrying -58 N m (the wheels turning the engine);
- one rear wheel on ice: with all three diffs open the car barely moves (1.20 m/s², that wheel
  spinning at 225 km/h with the car at 11); with the car's locked centre and LSDs it pulls away at
  4.39 m/s²;
- stopped, holding the brake: reverse, and it backs up.

The drivetrain changes how the car corners, as it does in a real one: the locked centre diff
makes the front and rear axles turn at the same average speed, but in a corner the front wheels
travel further, so the tyres fight it and the car pushes on a little more. With the diffs open the
phase 2-4 numbers come back exactly; with the car's diffs the skid pad limit is 0.89 g (open:
0.93 g) and turn-in yaw for the steering 0.87 coasting / 1.06 trail braking (open: 0.96 / 1.20).
Trail braking still rotates the car 22 % more. Phase 7's handbrake disconnects the rear (as a
Rally2 car's handbrake clutch does), which is how a rally driver gets it turned anyway.

**7. Bugs found:**
- the clutch's torque came out with the wrong sign (its impulse is negative when the engine drives
  the wheels), so under power the LSDs used their *coast* lock and the telemetry said the clutch
  carried -113 N m while pulling away. Found in the launch screenshot; fixed, with a test that the
  clutch reads + driving and - engine braking;
- neutral selected reverse (stopped in neutral with the brake held): reverse now only comes from
  a gear;
- the ice test changed up on the spinning wheel (the revs hit 7,200 with the car at 11 km/h): those
  runs have auto-shift off, as a driver would hold first;
- `Engine` shadowed Godot's own class and `preload` is a keyword: renamed `EngineModel`,
  `preload_torque`.
