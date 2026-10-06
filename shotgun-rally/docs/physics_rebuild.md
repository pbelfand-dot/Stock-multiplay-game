# Rally physics rebuild: inspection and plan

Status: **all nine phases done** (the chassis on its suspension; the tyres' side grip and the
steering; the wheels' spin, the drive / brake force and the brakes; the combined-slip ellipse and
load sensitivity; the engine, clutch, sequential gearbox and four-wheel-drive diffs; surfaces; the
handbrake, anti-roll bars and two-stage dampers; aero, the driver aids and telemetry; the rally
tuning and manoeuvres; see "Phase reports" at the end). Next: it replaces the current car in the
game (section 4). Decisions:
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
| `surfaces.gd` | collider → `SurfaceConfig`: the body's `surface` metadata (already on every stage body) names a `.tres` |
| `driver_assist.gd` | ABS, traction control, stability control, steering filtering / damping, countersteer help, speed-sensitive steering: all optional, off for the base physics |
| `rally_telemetry.gd` | the HUD (every wheel's numbers + the car's) and the debug drawing |

### Resources: `scripts/vehicle/physics/config/` → `data/`

`CarConfig` (mass, centre of mass x / y / z, inertia, wheel positions, brakes and bias, handbrake,
aero: Cd, frontal area, downforce and its front/rear balance), `SuspensionConfig`, `TireConfig`,
`EngineConfig`, `DrivetrainConfig`, `DifferentialConfig`, `SteeringConfig` (rack ratio, max angle,
Ackermann, smoothing, controller curve), `AssistConfig`, `SurfaceConfig`.

- `data/cars/awd_rally.tres`: the first profile, a modern AWD rally car: ~1,280 kg, front-mounted
  turbo engine, 5-speed sequential, short wheelbase (~2.5 m), gravel tyres, long-travel
  suspension, strong brakes, hydraulic handbrake.
- `data/surfaces/`: asphalt, wet asphalt, gravel (loose), dirt (packed), mud, snow, ice, grass.
  The stage's surfaces map onto these: the road → gravel, with the game's grip across it (the
  packed wheel tracks, the loose crown and edges) on top; the verges → grass; the puddles → mud.

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

### Phase 6: surfaces

**1. The code**
- `config/surface_config.gd` (`SurfaceConfig`): a surface as four figures that scale the car's
  tyre (whose own figures are for loose gravel): **grip** (the friction coefficient, both ways),
  **peak scale** (where the grip peaks: on a loose surface the tyre ploughs and digs, so it builds
  its grip over more slip and has less cornering stiffness; on asphalt it bites early), **slide
  grip** (how much a sliding, locked or spinning tyre keeps: on gravel, snow and mud it pushes a
  wedge of the surface up and keeps most; on asphalt, grass and ice it skates and loses more) and
  **rolling scale** (soft ground sinks under the tyre and drags).
- `surfaces.gd`: what a tyre is on. Every body the tyres touch says so with its meta
  `surface` (the stage already does): a name, looked up in `data/surfaces/<name>.tres` (spaces
  as underscores) and kept, or a `SurfaceConfig` itself. No meta, or an unknown name: gravel.
  `tarmac` and `road` mean asphalt.
- `tire_model.gd`: `on_surface(tyre, surface)` gives the tyre on that surface, made once per
  tyre and surface: mu x grip, both peaks x the peak scale, and the shape C set so the curve keeps
  the surface's share past the peak (`kept(C) = sin(C pi / 2)`, `shape_keeping()` inverts it).
- `rally_wheel.gd`: each wheel looks up its own surface whenever what it touches changes, and
  every tyre calculation uses the tyre on that surface, so two wheels on grass and two on gravel
  each do their own thing. `surface_mu` stays as an extra factor on top (the game's grip across
  the road; the phase 5 ice-patch test).
- Telemetry: each wheel's surface by name. Lab: a row of 240 m pads (asphalt, wet asphalt,
  gravel, dirt, snow, ice, mud, grass) and a split pad (ice on the left, asphalt on the right);
  keys 1-8 put the car on a pad rolling at 15 m/s, 9 on the split pad; `--lab=snow` (any surface)
  for a picture.

**2. Where:** `scripts/vehicle/physics/config/surface_config.gd`, `scripts/vehicle/physics/surfaces.gd`,
`data/surfaces/*.tres`.

**3. Nodes:** none new. Any `StaticBody3D` gets a surface with `set_meta("surface", "snow")` (or
`set_meta("surface", preload("res://data/surfaces/snow.tres"))`).

**4. In the inspector** (`data/surfaces/*.tres`) and what they make of the car's gravel tyre:

| Surface | Grip | Peak slip angle | Peak slip ratio | Kept sliding (side / along) | Rolling resistance |
|---|---|---|---|---|---|
| asphalt | 1.30 | 4.2° | 0.090 | 78 % / 70 % | 0.0125 |
| wet asphalt | 0.95 | 4.2° | 0.090 | 72 % / 65 % | 0.0150 |
| gravel (loose) | 1.00 | 7.0° | 0.150 | 85 % / 76 % | 0.025 |
| dirt (packed) | 1.05 | 6.0° | 0.128 | 81 % / 72 % | 0.020 |
| snow (packed) | 0.45 | 9.1° | 0.195 | 90 % / 80 % | 0.050 |
| ice | 0.15 | 4.9° | 0.105 | 64 % / 57 % | 0.0125 |
| mud | 0.45 | 10.5° | 0.225 | 94 % / 84 % | 0.100 |
| grass | 0.60 | 7.7° | 0.165 | 77 % / 68 % | 0.070 |

Where they come from: published tyre-road friction tables put loose gravel at about 0.6 peak / 0.55
sliding (gravel sliding on itself), dry asphalt 0.8-1.0, wet asphalt 0.5-0.8, packed snow 0.2-0.3,
ice 0.07-0.2 and mud 0.15-0.4; the grips above are those as a share of gravel's, so the car keeps
its 0.9 g on gravel. Rolling resistance from the engineering tables (asphalt ~0.013, rolled gravel
0.02, snow 0.04-0.15, grass 0.06-0.11, soft ground 0.08-0.15). These are for the car's **gravel
tyre**: studded tyres grip up to 2.5 times better on ice and about the same on snow, and a tarmac
tyre more on asphalt; those are other `TireConfig`s (phase 9 / the garage).

**5. How to test:** `godot --headless --fixed-fps 120 --path . -s tests/physics_v2_check.gd` (the
suite now runs in ~30 s). In the lab: 1-8, steer, brake, F3.

**6. What correct looks like** (measured, the same runs on every surface):

| Surface | Cornering limit | Braking from 40 km/h | 0-40 km/h (phase 7's launch: quicker) | Coasting at 20 m/s |
|---|---|---|---|---|
| asphalt | 11.2 m/s² (1.14 g) | 9.7 m/s², 6.3 m | 2.3 s | 0.12 m/s² |
| wet asphalt | 8.3 (0.85 g) | 6.8, 9.2 m | 2.3 s | 0.14 |
| gravel | 8.8 (0.90 g) | 8.1, 7.7 m | 2.3 s | 0.24 |
| dirt | 9.2 (0.94 g) | 8.2, 7.6 m | 2.3 s | 0.19 |
| snow | 4.0 (0.41 g) | 3.9, 16.0 m | 3.0 s | 0.47 |
| ice | 1.3 (0.13 g) | 1.0, 61.9 m | 11.5 s | 0.12 |
| mud | 3.9 (0.39 g) | 4.0, 15.4 m | 3.2 s | 0.95 |
| grass | 5.3 (0.54 g) | 4.7, 13.2 m | 2.8 s | 0.66 |

- cornering (the wheel wound to 15 degrees from 15 m/s): each surface holds its grip x gravel's
  within 3 %, and the looser the surface the bigger the slip angle it lets go at (fronts at 6.6
  degrees on asphalt, 10.2 on gravel, 14.6 on snow, 15.4 on mud);
- braking on full brakes (no ABS: phase 8): the wheels lock on every surface and it stops on what
  locked tyres keep there, within 4 % of the prediction; asphalt shortest, ice by far the longest;
- pulling away: on asphalt, gravel and dirt the engine and clutch set the time, not the grip; on
  snow and mud the grip does (3.0 and 3.2 s, against 2.5 s at the very best); on ice the wheels
  spin up and it changes up on them (traction control is phase 8), 11.5 s against 7.6 at best;
- coasting: each surface's rolling resistance exactly;
- split surface (left wheels on ice, right on asphalt, full brakes from 60 km/h): it turns 33
  degrees toward the asphalt in 0.75 s. With every wheel locked nothing holds it straight, so it
  goes on round unless the driver steers against it or eases off: a real car without ABS does
  the same.

On asphalt the car rolls 5.4 degrees at 1.07 g and the inside rear nearly lifts (0.5 kN): there
are no anti-roll bars yet (phase 7).

**7. Bugs found** (in the tests, not the physics):
- the first cornering run held the speed with the lab's tow, which pushes along the car's nose:
  sliding on ice, part of that push counted as cornering, and the car "cornered" at 1.9 m/s², past
  ice's own 1.47. It coasts now, measured by its acceleration across its path;
- the braking bound added rolling resistance to the locked-tyre figure, but a locked tyre slides,
  it doesn't roll;
- the split-surface car turned toward the asphalt as it should, then on round past 180 degrees,
  which the test read as 137 degrees the wrong way: it measures the first 0.75 s now.

One simplification to know: rolling resistance acts as a torque on the wheel (like a light brake),
so a wheel already spinning on its grip doesn't pass it on to the car. Pulling away in mud comes out
2 % quicker than grip minus rolling resistance would allow. Deep mud or snow that drags the body
whatever the wheels do would be an extra force; it isn't needed yet.

### Phase 7: handbrake, anti-roll bars, two-stage dampers (and a better launch)

**1. The code**
- **Handbrake** (`rally_car_v2.gd` `_brakes()`): the hydraulic handbrake adds its torque to the
  rear brakes, through the same friction path as the pedal, so the rears lock only because it
  beats their grip (3,000 N m against the ~1,800 the rear tyres can take on gravel). Its lever
  also works **the rear axle's clutch** (`drivetrain.gd`), as on a Rally2 car: a light pull lets
  the rear drive go, so the gearbox drives the fronts and the rears only through that clutch,
  slipping (a friction-limited coupling in the solver). Let go, it bites again over 0.25 s.
- **Anti-roll bars** (`_anti_roll()`): each axle's bar pushes its more squashed corner up and
  pulls the other down by its rate x the difference in squash, as extra strut force (so it's part
  of the tyre's load). With one wheel in the air the bar lifts that light wheel into its arch until
  its spring balances the bar, so the bar carries only what that spring can (continuous as a
  wheel lifts). `rally_wheel.gd` now senses the ground (`step()`) and works out the load
  (`settle()`) separately, so the car can work out the bars from both corners in between.
- **Two-stage dampers** (`suspension.gd` `damping()`): firm up to a knee speed (the body rolling,
  pitching, bouncing), the softer high-speed rates above it (a wheel hitting a bump or dropping
  into a hole), bump and rebound each, like a rally damper's low- and high-speed adjusters.
  `roll_stiffness()` gives each axle's roll stiffness (springs and bar).
- **The launch** (`drivetrain.gd` `control()`): pulling away, the automatic clutch now slips
  holding the engine near a target (launch_rpm flat out, lower with less throttle), biting harder
  as the revs rise past it. The old one bit by revs alone, so under a heavy load the engine
  bogged at the revs where it bit hardest: with the rears locked on the handbrake it sat at
  1,800 rpm and the car didn't move.
- Telemetry: a handbrake line (the lever, how far in the rear axle's drive is). Lab: space is the
  handbrake, `--lab=handbrake` a handbrake turn.

**2. Where:** `suspension.gd`, `config/suspension_config.gd` (damper and anti-roll groups),
`rally_car_v2.gd`, `rally_wheel.gd`, `drivetrain.gd`, `config/drivetrain_config.gd` (Handbrake
group), `config/car_config.gd` (`handbrake_torque`).

**3. Nodes:** none new.

**4. In the inspector:**
- dampers: knee 0.25 m/s; front 1,900 / 3,400 N per m/s slow (bump / rebound), 1,100 / 2,500 fast;
  rear 1,600 / 2,900 slow, 950 / 2,100 fast;
- anti-roll bars: front 14,000 N/m, rear 9,000 N/m (the axles' roll stiffness: front 70,000, rear
  52,000 N m per radian with the springs);
- handbrake 3,000 N m on the two rears; the rear axle's clutch on (`handbrake_disconnects_rear`),
  6,000 N m when in, 0.25 s to bite again.

**5. How to test:** the physics test (10 new runs). In the lab: space in a turn, F3.

**6. What correct looks like** (measured):
- handbrake turn at 15 m/s (the wheel at 18 degrees, the handbrake for 0.8 s): it turns 134
  degrees in 2 s against 66 without, the tail out to 75 degrees of slip (3 without); while it's
  pulled the rears are locked and the fronts keep rolling the whole time;
- rolling at 36 km/h, handbrake and full throttle: the rears stay locked while the fronts drive.
  Without the rear axle's clutch the engine turns the rears through the locked centre: they never
  lock, the handbrake only drags;
- body roll: 2.75 degrees per g in a steady corner, against 2.85 predicted from the springs and
  bars (road cars ~1-1.8, a gravel rally car softer); without the bars 5.05 (predicted 5.39): they
  take 45 % of the roll out. On asphalt at 1.07 g it rolls 2.9 degrees (5.4 before), but the inside
  wheels unload just as much (the rear to 0.7 kN): the weight shifted in a corner is set by the
  centre of mass's height and the track (4.0 kN here, m a h / t, as measured), not by the bars.
  The bars cut the roll and decide which end takes the shift: the front 57.5 %, its share of the
  roll stiffness;
- at the limit, front bar x 3: front slip 4.9 / rear 2.6 degrees (more push); rear bar x 3: 5.6 /
  3.8 (the tail working), and 7 % more cornering (9.04 against 8.43 m/s²);
- sharp bumps at 15 m/s: the body's hardest jolt 7.5 m/s² with the two-stage dampers, 10.0 with
  plain ones; the full-width bumps now pitch it 0.7 degrees (1.0 before), the 1 m drop uses 280 of
  the 300 mm travel (268 before) and still never touches;
- the launch: 0-100 km/h in **4.2 s** (4.9 before; Škoda quotes about 4.2 s for the Fabia RS
  Rally2). Flat out off the line the tyres spin hard (253 % slip at walking pace: the engine puts
  ~5,500 N m to the wheels in first against the ~4,000 gravel can take) and hook up as it gathers
  speed (23 % by 50 km/h). A driver feathers the throttle; traction control (phase 8) will. The
  phase 6 pulls to 40 km/h are quicker too: asphalt 1.4 s, wet 1.9, gravel 1.6, dirt 1.6, snow
  3.2, mud 3.1, grass 2.7, ice 11.7 (the order unchanged).

**7. Bugs found:**
- the old automatic clutch bogged the engine under a heavy load (above): replaced;
- a test run named "two-stage" made its judge function's name invalid (a hyphen); the suite
  then stalled on the error every tick instead of failing. Renamed.

### Phase 8: aero, the driver aids (each a Settings switch), telemetry

**1. The code**
- `aero.gd` (pure functions): drag `½ ρ Cd A v²` against the motion, at the centre of mass;
  downforce `½ ρ (Cl A) v²` along the car's down, split front / rear by the aero balance and pushed
  at each axle (so it loads the tyres, more grip at speed, and a little more rolling resistance).
  `rally_car_v2.gd` `_aero()` applies them each tick.
- `config/assist_config.gd` (`AssistConfig`): seven switches, all off by default (that's the base
  physics), and their figures. `driver_assist.gd`: the aids sit between the controls and the car
  and only change what each wheel's brake, the throttle and the steering are asked for:
  - **ABS**: a braking wheel past its tyre's peak slip (on that surface) gets its pedal brake eased
    in proportion, so it brakes near the peak and still steers (the handbrake isn't touched);
  - **traction control**: a driven wheel spinning past its peak cuts the throttle in proportion
    (cut fast, back on in ~0.1 s); measured against a floor speed so it can pull away;
  - **stability control**: compares the yaw rate with what the steering asks for (no more than the
    grip allows) and brakes one wheel: sliding round too far, the outside front; not turning
    enough, the inside rear (off with the handbrake pulled, and under 18 km/h);
  - **steering smoothing** (the input eased, 0.2 s), **damping** (above 12 m/s the wheels turn more
    slowly, in proportion), **speed-sensitive steering** (never more angle than the fronts can use
    at that speed: the tightest turn their grip allows plus their peak slip angle; less is left
    alone) and **countersteer help** (with the tail sliding past 4 degrees, the front wheels are
    pointed toward where the front axle is going).
- `drivetrain.gd`: the automatic clutch, pulling away, now **carries what the engine makes** (plus
  0.5 N m per rpm over the launch revs, less under them). Before, it bit by revs alone, so when
  traction control cut the throttle the revs fell, the clutch let go, then grabbed ~200 N m when
  they came back: on ice the wheels flared every 0.4 s and it was slower than without the aid.
  It also stays slipping until the car catches up with the launch revs in first (it locked in as
  soon as the spinning wheels' speed passed 1,100 rpm, and traction control then dragged the
  engine down to 1,400 rpm). The clutch follows the driver's foot, the engine the cut throttle.
- Settings (`scripts/ui/settings_panel.gd`, SETTINGS on the home screen): the game had no settings
  screen; now mouse look, invert Y, volume, the co-driver's call timing, and the seven aids, each
  an ON / OFF switch with a line on what it does, saved in `Config` (`[aids]` in
  `user://settings.cfg`). A v2 car reads them when it's made.
- Telemetry: an air line (drag, downforce front / rear), an aids line (which are on and what
  they're doing: ABS easing a wheel, the TC cut, the ESC brake, the countersteer angle), and **F2
  records** every tick to `user://telemetry/v2_<date>_<time>.csv` (54 columns: speed, rpm, gear,
  pedals, steering, g, yaw, pitch, roll, aero, the aids, and each wheel's squash, load, slip angle,
  slip ratio, speed, forces, ABS and surface).
- Lab: F5-F11 switch the aids, F2 records.

**2. Where:** `scripts/vehicle/physics/aero.gd`, `driver_assist.gd`, `config/assist_config.gd`,
`scripts/ui/settings_panel.gd`, `scripts/net/config.gd` (`aids`).

**3. Nodes:** none new (the assist is an object the car owns, `car.assist`, with `car.assists` its config).

**4. In the inspector:** aero: Cd 0.40, frontal area 2.15 m², downforce area (Cl A) 0.55 m² (a
Rally2 car's ~60 kg at 150 km/h), 45 % on the front. Aids: ABS band 0.1 past the peak; TC band
0.15, floor speed 3 m/s; ESC 4,000 N m per rad/s, at most 1,500 N m, deadband 0.1 rad/s;
smoothing 0.2 s; damping from 12 m/s; countersteer strength 0.7.

**5. How to test:** the physics test (phases 1-7 run with the aero off and the aids off, so their
numbers stay about what they test; phase 8's runs switch them on). In the game: SETTINGS. In the
lab: F5-F11, F3 to see them work, F2 to record.

**6. What correct looks like** (measured):
- coasting from 150 km/h: 0.90 m/s², as predicted (drag 0.65 + rolling resistance with the
  downforce 0.25); downforce 22 N at 30 km/h (nothing), 573 N (58 kg) at 150 against 585
  predicted, 45 % on the front;
- **all seven aids on, inside the grip, the same car**: a steady corner 5.63 m/s² with the same
  slip angles to 0.01 degree; braking at 30 % 3.782 against 3.783 m/s²;
- ABS: full brakes from 100 km/h stop in 41.1 m (locked: 47.6 m), a wheel locked 1 % of the time;
  full brakes with the wheel at 15 degrees from 80 km/h: it turns 68 degrees in 2 s (locked: 21,
  sliding straight on);
- traction control: flat out off the line the tyres spin up to 25 % once rolling (280 % without)
  and it's quicker, 0-100 in 4.09 s (4.17 without); on ice 0-40 km/h in 8.6 s (11.7 without; the
  grip allows 7.6 at best);
- stability control: a flick on snow at 72 km/h, the tail out to 11 degrees of slip (30 without);
- speed-sensitive steering: full lock at 90 km/h, the fronts work at 10 degrees of slip instead of
  ploughing at 31, and it corners 10 % harder (8.98 against 8.19 m/s²);
- smoothing: a key press reaches 25 degrees in 0.36 s (0.14 without), the same lock; damping: at 108
  km/h the wheels take 0.14 s to turn 10 degrees (0.06 without);
- countersteer help: a handbrake slide let go of at 65 km/h with the power on and hands off turns
  121 degrees more and ends rotating at 11 degrees/s; without it 154 degrees and still spinning at
  40;
- the Settings panel has the eight switches, and ABS switched on there gives a new car ABS;
  recording a second of driving writes 121 rows of 54 columns.

**7. Bugs found:**
- the launch clutch fighting traction control (above): rebuilt to carry the engine's torque;
- test runs named with " on " were taken for surface runs ("aids on corner", "flick on snow")
  and never ended: renamed;
- the first speed-sensitive steering scaled the whole input, so it changed the car inside its
  grip too: it's a ceiling now;
- the tow that holds the downforce run's speed pulls at the centre of mass against rolling
  resistance at the ground: that couple moves ~60 N onto the front, which the test subtracts.

### Phase 9: rally tuning and the manoeuvres

**1. The code:** no new physics. Phase 9 is the tuning, and the tests that prove the car does what
a rally car does, each as a scripted driver on gravel (`tests/physics_v2_check.gd`
`_manoeuvre()`): none of the manoeuvres has code of its own in the car; they come from the
tyres, the diffs and the weight moving.

**What the tuning found.** With the phase 5-8 set-up the car was safe and dull: at the limit the
fronts ploughed at ~10 degrees of slip while the rears used 3 of their 7, lifting mid-corner
changed nothing (rear slip 3.2 -> 3.5 degrees), and a Scandinavian flick rotated the car *less*
than turning in plain. Trying the candidates one at a time (the stiffer bar at the rear, softer
diffs, more load sensitivity, 50/50 weight, all diffs open) showed what held the tail: the
limited-slip diffs' **coast lock and preload**, which tie the rear wheels together on a lift, and
the front-biased anti-roll bars. The tuning (a gravel set-up):

| | Before | After |
|---|---|---|
| Front LSD (power / coast / preload) | 0.40 / 0.20 / 50 N m | 0.25 / 0.10 / 25 N m |
| Rear LSD | 0.60 / 0.35 / 70 N m | 0.45 / 0.12 / 30 N m |
| Anti-roll bars (front / rear) | 14,000 / 9,000 N/m | 7,000 / 16,000 N/m |

The rear still locks under power (0.45: the drive out of a corner); it's the coast side that's
looser, so the tail is free to come round on a lift. The total roll stiffness is the same (so the
roll gradient is unchanged, 2.75 degrees per g); its balance moved to the rear (44 % front), as gravel cars
run it. The centre stays locked (Rally2: no centre diff).

**4. In the inspector:** the table above (`data/cars/awd_rally.tres`: Drivetrain > the front and
rear diffs; each axle's suspension > Anti-roll bar).

**5. How to test:** the physics test (8 new runs). In the lab: lift mid-corner, flick, F3.

**6. What correct looks like** (measured):
- **lift-off oversteer**: lifting mid-corner at 75 km/h, the rear slip goes 4.0 -> 7.6 degrees and
  the car tightens its line, 22 -> 30 degrees/s, without spinning;
- **power oversteer**: flat out mid-corner, the body slip goes -1 -> +20 degrees in a second (rear
  tyres 3 -> 23 degrees): the tail swings wide;
- **four-wheel drift**: a driver holding the slide keeps all four tyres past their peak for 2.5 s
  (front 12, rear 8 degrees, the body 7 degrees sideways) at 79 km/h, without spinning. (Tidy: an AWD
  car with a locked centre drifts neatly; the big-angle slides are for rear-drive cars);
- **countersteer catch**: after a handbrake flick at 58 km/h, steering where it's going straightens
  it 1.5 s after letting go (75 degrees of turn); hands off, it spins (181 degrees);
- **Scandinavian flick** at 72 km/h: a flick away first rotates it 59 degrees in 2.5 s with the tail
  out to 23 degrees; turning in plain, 55 degrees with the tail at 7;
- **pendulum**: a driver steering slide to slide, left, right, left at 72 km/h: two swings, the
  body angle from -12 to +13 degrees, never spinning.

And what the tuning moved elsewhere (all the earlier checks still pass): the skid pad limit 0.89
-> 0.94 g with the rear slip nearer the front's (a more neutral car); turn-in yaw for the steering
0.87 -> 0.93 coasting, 1.06 -> 1.18 trail braking; the snow flick without stability control now
swings the tail to 42 degrees (12 with it). Two checks were narrower than what they meant and were
widened: the slip angle the surfaces let go at (snow and mud came out 14.8 and 14.6: both looser
than gravel is the point), and speed-sensitive steering (the fronts at 13.7 degrees of slip now the
car slides as a whole: less than half the 33 degrees it ploughs at without the aid is the point).

**7. Bugs found:** none in the physics. In the tests: a fixed left-right steering pattern isn't a
pendulum (with nobody catching each slide it ends in one big slide or a spin): the pendulum and
the drift are driven by a driver that steers toward where the car's going and reacts to the slide.

**Physics v2 is complete.** Next: it replaces the current car in the game (section 4: the same
public API, the cockpit, the effects, the autopilot and the network switched over and their tests
passing), then the drone-chase cinematic on the home screen.
