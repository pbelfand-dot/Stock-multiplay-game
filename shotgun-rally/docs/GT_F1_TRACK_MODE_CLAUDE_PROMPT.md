# Claude prompt: GT and Formula track mode

Copy everything below this line into Claude:

---

Work autonomously in the SHOTGUN RALLY repository and build a complete new **TRACK MODE**
with both **GT racing** and **Formula racing**. I am going to bed, so do not stop to ask me
routine design questions. Inspect the existing project, follow `shotgun-rally/CLAUDE.md`,
make sensible professional choices yourself, preserve all current rally/touge/cut-up/garage
features, test your work, merge it to `main`, and make sure the SHOTGUN RALLY GitHub Actions
workflow and `shotgun-latest` release succeed. Do not merely write a plan: implement and
verify the mode incrementally.

## Source assets already in the repository

Read these before doing anything:

- `shotgun-rally/assets/wheel_packages/README.md`
- `shotgun-rally/assets/wheel_packages/WHEEL_ASSET_MANIFEST.tsv`
- `shotgun-rally/assets/wheel_packages/Free_Wheels/USD_Mini_Car_Kit/`
- `shotgun-rally/assets/wheel_packages/Free_Wheels/ice-maan-cc96-four-rim-pack.zip`
- `shotgun-rally/assets/wheel_packages/Free_Wheels/innerscene-17in-five-spoke-wheel-tyre.x3d`
- `shotgun-rally/assets/car_packages/Track_Mode_Cars/README.md`
- `shotgun-rally/assets/car_packages/Track_Mode_Cars/2024-porsche-992-gt3-r.zip`
- `shotgun-rally/assets/car_packages/Track_Mode_Cars/mercedes-amg-gt3-red-bull-racing.zip`
- `shotgun-rally/assets/car_packages/Track_Mode_Cars/Formula/`
- `shotgun-rally/assets/car_packages/Track_Mode_Cars/GT3/`
- `shotgun-rally/assets/environment_packages/Track_Mode_Props/`
- `shotgun-rally/assets/TRACK_MODE_ASSET_MANIFEST.tsv`
- `shotgun-rally/docs/VEHICLE_PROGRESS.md`
- `shotgun-rally/docs/modes.md`
- the existing garage, vehicle registry, multiplayer, HUD, physics, AI, and track/stage code

The USD mini car kit is CC0 and includes six wheel variants plus a small Formula car. The
IceMaan four-rim FBX pack and the Innerscene wheel/tyre/brake assembly are also CC0. The two
GT3 archives are CC BY-NC-SA 4.0 and must retain attribution. The Porsche package is an
alternate to a GT3 R already in the game; compare them and use the better runtime source
instead of creating a duplicate garage entry. The Formula model may be used as a temporary
placeholder or scale/reference source, but replace or substantially improve it if it is not
visually consistent with the game.

The newer `Formula/`, `GT3/`, and `Track_Mode_Props/` GLBs are original generic CC0 assets
with preserved upstream JSON and exact hashes in `TRACK_MODE_ASSET_MANIFEST.tsv`. Their
upstream contributor reports AI generation with Claude Fable 5.1; none carries a `No AI`
restriction. Use the two modern halo/open-wheel cars to establish the FORMULA class, the four
generic closed-cockpit race cars to diversify the AI grid, and the pit/marshal props to dress
the circuit. Their presence in the repository is not integration: import them through Godot,
create appropriate collisions/LODs/materials, register the cars, fit the player/camera, tune
physics, place the props, and verify the results in a running build.

## Product goal

Add TRACK MODE to the 3D garage/main menu alongside the existing modes. It must feel like a
real circuit-racing part of the same game, not a disconnected prototype. Provide two clearly
different classes:

1. **GT** — closed-wheel GT3-style racing using the best suitable cars already available,
   including the Porsche 992 GT3 R and Mercedes-AMG GT3 candidate after proper optimization.
2. **FORMULA** — a fictional top-level open-wheel class inspired by modern Formula racing,
   with exposed slicks, strong aero, low mass, high power, DRS-style overtaking, and a proper
   cockpit/halo view. Do not use official Formula 1 branding, team logos, driver names, or
   sponsor marks in the shipped game. Use a fictional series name such as FORMULA APEX.

Use fictional in-game car and series names even when a source asset represents a real car.
Remove or replace real sponsor graphics where practical. Never claim endorsement by a real
manufacturer or racing organization.

## Circuit and race weekend

Build one polished permanent circuit first, approximately 4.5-6.0 km, 14-20 corners, with a
recognizable mix of a long straight, heavy-braking hairpin, medium-speed technical section,
fast sweepers, elevation change, and at least two safe passing zones. Include:

- start/finish line, correctly spaced grid boxes, pit lane, pit entry/exit, pit stalls,
  garages, pit wall, timing gantries, sector lines, marshal posts, service roads, tire walls,
  TecPro-style barriers, debris fencing, curbs, drainage, grass/gravel/asphalt runoff,
  grandstands, trackside cameras, distance boards, and night lighting;
- collision that matches the visible barriers without invisible snag points;
- sensible racing surface widths and cambers, no impossible crests, no self-intersections,
  and enough runoff for the approach speed;
- dry day, dry night, and wet presets, with the same deterministic layout online;
- garage/menu preview, loading art, circuit map, sector map, and a short track description.

Support PRACTICE, QUALIFYING, QUICK RACE, and RACE WEEKEND. Add standing starts for Formula,
rolling starts for GT, formation-lap behavior, false-start handling, lap/sector timing,
personal bests, qualifying order, race classification, fastest lap, DNFs, restarts, and
results persistence. Include 3-, 5-, 10-, and custom-lap choices.

## Race rules and HUD

Implement checkered, green, yellow, blue, black, and red-flag states at a practical game
level. Add track limits, invalidated qualifying laps, jump starts, pit-lane speeding, unsafe
pit exit, corner cutting, and escalating warnings/time penalties. Do not punish harmless
two-wheel curb use. Make penalties deterministic and synchronized online.

The HUD must show position, lap, class, current/best lap, sector and delta, gap ahead/behind,
gear, speed, RPM/shift lights, fuel/energy, tyre compound and temperatures, tyre wear, brake
temperature, damage, flag state, penalties, DRS availability for Formula, ABS/TC setting for
GT, and pit limiter. Keep cockpit, bumper, hood, chase, replay, and broadcast cameras usable.

## Vehicle and wheel integration

Create a reusable data-driven `WheelPreset`/wheel-assembly system instead of hard-coding one
mesh per car. It must support separate front/rear diameter, width, offset, tyre aspect,
compound, pressure, visual mesh, and brake package. Keep tyre, rim, disc, and caliper as
separate nodes: tyre/rim/disc rotate; caliper stays fixed; steering pivots around the axle;
left/right directional tread and UVs must remain correct. Physics radius must be independent
of visual LOD. Preserve each car's original wheels as a STOCK preset.

Use the CC0 wheel library for prototypes, traffic/LOD needs, and optional garage choices.
Do not put obviously low-poly prototype wheels on a hero car in close view. The README lists
high-detail CC BY candidates for BMW, Nissan, Porsche, Mercedes-Benz, Dodge, Audi, Honda,
Mazda, Toyota, Bugatti, and Formula tyres; only import a candidate if the actual file is
present and its license/attribution are preserved. Do not pretend a linked-only candidate was
downloaded.

For every fitted wheel, automatically validate axle center, rotation axis, ground contact,
clearance at full steering lock and suspension travel, brake/caliper placement, no body
clipping, and no left/right mirroring mistakes. Provide garage controls for stock, street,
track, vintage, wide, and Formula-compatible presets only where they actually fit.

Optimize every new car without destroying its cabin. Separate all four wheels, steering
wheel, brake discs, calipers, doors only if needed, and any animated cockpit controls. Keep
the driver model seated correctly, hands on the steering wheel, feet near pedals, head below
the roof/halo, and cameras clear of geometry. Preserve detailed interiors for cockpit and
garage views, with lower exterior/cockpit LODs for racing and distant cars. Use simplified
convex collision, never the render mesh.

## Driving physics

Extend the existing physics; do not replace working rally/street handling. Track cars need:

- load-sensitive tyre grip, combined longitudinal/lateral slip, smooth breakaway and recovery,
  realistic slip-angle ranges, rolling resistance, flat-spot/wear hooks, and wet grip;
- tyre carcass/surface temperature, pressure, wear, cold/optimal/overheated behavior, dry
  slick and wet compounds, and pit-reset/replacement behavior;
- brake temperature, fade, bias adjustment, ABS for GT, no ABS for Formula unless the chosen
  fictional rules explicitly enable an assist;
- speed-sensitive downforce and drag, front/rear aero balance, ride-height sensitivity,
  drafting/slipstream, dirty-air loss, curb/grass/gravel grip changes, and floor/plank damage;
- GT traction control and ABS settings, sequential paddle shift, pit limiter, realistic mass,
  power band, gearing, final drive, fuel use, and damage;
- Formula energy deployment/recovery, DRS-style rear-wing state with detection/activation
  zones, anti-stall, launch behavior, fast paddle shift, and much stronger aero sensitivity.

Research reliable manufacturer, homologation, or major motorsport sources for horsepower,
torque, mass, wheelbase, dimensions, gearing, tyre sizes, and aero/rules after each real car
is integrated. Save sources in the vehicle metadata/docs. When BoP values vary, model a
plausible balanced race spec and clearly document it. Do not tune every car to the same feel:
GT should be heavier, more forgiving, and electronics-assisted; Formula should be much more
responsive, aero-dependent, and punishing at low speed or in dirty air.

## AI, pit strategy, multiplayer, and audio

Create racing AI that follows a racing line but can pass, defend once, yield under blue flags,
avoid stopped cars, recover from mistakes, use slipstream, respect pit entry/exit, manage
tyres/fuel, choose wet tyres, and vary by skill without cheating grip or power. It must race
side-by-side without blindly turning into the player. Add qualifying traffic awareness and
formation/rolling-start logic.

Implement functional pit stops for tyres, fuel where the class uses it, and repair. Provide
pit strategy UI and a safe default strategy. Synchronize grid, lights, flags, laps, timing,
penalties, car state, pit work, weather preset, and results for the existing online player
count. Late joiners should spectate until the next session or start safely from the pits.

Add suitable GT V8/flat-six and Formula turbo-hybrid-style audio layers without copying
copyrighted recordings. Include transmission whine, shifts, limiter, tyre scrub, marbles,
curb strikes, aero rush, pit ambience, crowd, PA, rain, and wet spray. Keep audio scalable so
many cars do not overwhelm performance.

## Quality bar and completion

Use level-of-detail, texture budgets, occlusion/culling, instancing, pooled effects, and
limited dynamic lights so the mode remains playable on the project's supported hardware.
Add automated tests for circuit closure, grid/pit validity, lap/sector timing, invalid laps,
flags/penalties, wheel pivots and ground contact, tyre state, DRS zones, pit stops, AI laps,
results, save/load, and online synchronization. Add command-line smoke tests for GT and
Formula races. Run all existing tests to ensure rally, touge, cut-up, garage, updater, and
multiplayer behavior do not regress.

Update the mode documentation, controls, credits, asset manifests, and vehicle progress as
you work. At completion, report exactly what is playable, what assets were used, measured
performance, tests run, any remaining blockers, the final commit, CI run, and updated release.
Do not call a placeholder complete. If one piece genuinely cannot be finished, ship the
largest stable playable vertical slice and document the precise remaining work without
breaking existing modes.

---
