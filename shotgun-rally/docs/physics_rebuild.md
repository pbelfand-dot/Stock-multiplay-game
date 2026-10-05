# Rally physics rebuild: inspection and plan

Status: **phase 1 done** (the chassis on its suspension, in the lab; see "Phase reports" at the
end). Decisions:
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
