# The world: final report (October 2026)

The environment mandate was to turn the uploaded car and environment libraries into one game across touge, cut-up
highway traffic, rally (surfaces and seasons) and the toll plaza and expressway. It had to keep
multiplayer, events, progression and replay working, stay performant, and be tested at each step.
This is where it ended up. The cars have their own report (`VEHICLE_REPORT.md`); the details of
every asset are in `ENVIRONMENT_INVENTORY.md`.

## What's in the game now

1. **A converter for the owner's environment packs** (`tools/import_environment.py`, with
   `tools/vegetation.py` for trees and `tools/buildings.py` for buildings).
   - It reads the packs restored from git (`tools/restore_environment_assets.py`, checksums checked) and never changes them.
   - It opens them in Blender with scripts off.
   - It writes the runtime GLBs to `assets/environment_runtime/`.
2. **Trees: 21 species** from the owner's three packs: 12 conifers, 4 black locusts (Robinia) and 5 tall pines. Each has three levels:
   - a full model up close (11-23 k triangles, its trunk rebuilt as a clean tube);
   - a lighter one further off (1.3-2.2 k);
   - two crossed cards far away (rendered in Blender).

   They're lit with light through the leaves and a softer normal map, with the leaf alpha cut set per species.
3. **Biomes** (`data/biomes.json`): 8 lands, with seasons that recolour them:
   - Japanese cedar mountain;
   - conifer rally forest;
   - broadleaf;
   - rocky alpine;
   - wet forest;
   - winter mountain;
   - suburban verge;
   - urban corridor.

   Every stage stands in one, picked from what the stage is (touge, ice, tarmac, mixed, puddles, gravel) or named by its story rally. A stage grows 4 conifers and 2 broadleaves of its biome, chosen by the stage's seed.
4. **Stage dressing:**
   - mossy boulders (Poly Haven, CC0);
   - scanned rock cuts on mountain roads;
   - a wooden power line along the touge;
   - warning signs from the owner's highway pack: winding road before tight bends, slippery road on wet and icy stages.

   Forest-floor and second-asphalt textures come from the CC0 library.
5. **The toll plaza** on the LAKESHORE LOOP (22.7 km):
   - the lanes fan out round islands;
   - booths (lit at night), a canopy on columns, lights over each lane;
   - green arrows or red Xs over the lanes, with ETC / CLOSED / GO boards;
   - cameras and readers, barrier arms, yellow-and-black crash cushions;
   - gantry signs 1 km and 400 m before it, both ways.

   It has three layouts in the cut-up menu, the same on every machine online:
   - **ALL OPEN**: full speed through.
   - **MIXED LANES**: the right-hand lane closed, coned off and gated; traffic slowed to 60 km/h.
   - **EVENT**: all GO, the canopy saying SHOTGUN RALLY.

   Traffic keeps to its lane through it, leaves a closed lane beforehand and never touches an island. The rivals obey it, and the autopilot takes a lane.
6. **The city's front rows** are the owner's 22 European apartment and office buildings:
   - each at most 60 k triangles with Godot's LODs below that;
   - one facade image each, painted from renders of the full building;
   - their windows lit at night.

   The drawn towers stay behind them.
7. **Traffic types:** compacts, saloons, crossovers, people movers, SUVs, luxury cars and vans. Each has its own speed, following gap, keep-right habit and eagerness to change lanes.

## Fixed along the way

- **The highway's sign text faced away from the drivers** (every exit gantry's board was blank from the road). It faces them now, sized to fit its board.
- **The touge's power line and the new signs could vanish**: a group running the whole stage was judged by its middle for its draw distance. They're always drawn now (they cost almost nothing).
- **A rival could swerve into a lane right behind a much slower car** and go through it (it only checked for 6 m of room). It now needs the room to brake for the speed it's closing at.
- **The auto-update test copied gigabytes of source packs**, twice, and filled the disk. It copies only the game now.

## Performance

Measured with `tools/stage_perf.gd`: a driver's-eye view down the road at several places, using
xvfb's software renderer, so the counts are right but the frame times aren't a real GPU's.

| Where (graphics level) | Triangles in view | Draw calls | Shadow triangles | Video memory |
|---|---|---|---|---|
| Gravel stage, LOW (the old cone trees) | 0.40-0.59 M | 62-74 | 0.34 M | 253 MB |
| Gravel stage, MEDIUM, **before** (the first real trees) | 13.5-14.9 M | 1,237-1,430 | 41-48 M | 362 MB |
| Gravel stage, MEDIUM, **now** | 1.73-2.27 M | 877-1,058 | 0.32-0.53 M | 401 MB |
| Gravel stage, HIGH, before | 15.5-19.2 M | 1,282-1,573 | 63-80 M | 418 MB |
| Gravel stage, HIGH, now (each tree its own shadow) | 1.95-2.47 M | 972-1,187 | 8.1-9.9 M | 455 MB |
| Touge, MEDIUM, by day | 0.84-0.87 M | 535-677 | 0.51-0.53 M | 458 MB |
| The loop's city, MEDIUM (the real buildings) | 2.03-2.05 M | 221-224 | 0.24-0.38 M | 760 MB |
| The loop's toll plaza, MEDIUM | 0.24 M | 165 | 0.11 M | 760 MB |

Building a stage takes 3.4-5.6 s here, the loop 17.6 s (the loading screen covers it).

The first measurement after adding the real trees was 14.9 M triangles in view and 48 M in shadows at MEDIUM.
Three things brought it down:

- **Smaller groups:** Godot swaps a group's level of detail by the distance to its middle, so the groups are now small, and the full trees are only in the first 12 m off the road.
- **Shadow proxies:** at MEDIUM the full trees' shadows come from their lighter version.
- **Fewer species per stage:** each species is its own draw per group.

## Tests

`tests/run_all.sh` passed in full here: the compile check, stages, render, driving, handling, drift, feel, SIM street, tuning, jumps, effects, story, car models, run-off, physics, cockpit, interiors, ride, view, sound, modes (traffic, battles, the loop, the game), the two new suites below, the touge drive, the AI co-driver, the 2-player and online sessions, and the updater.

- **New: `tests/environment_check.gd`.**
  - Every tree's three levels within budget, the rocks and props loading.
  - Each stage in its biome, and the season's colours.
  - Five stages in five lands: real trees, boulders, rock cuts, poles and signs where the biome has them.
  - Nothing on any part of the road, and a car-sized box down the road touching nothing.
  - The solid trunks, boulders and poles identical at LOW and MEDIUM.
- **New: `tests/toll_check.gd`.**
  - In each layout: a car down every lane, both ways, touches nothing, while the closed lanes' gates stop it.
  - The islands are solid, with 3.6 m between them.
  - The boards, lights, median and cones are right.
  - The autopilot's line goes between the islands.
  - A minute of insane traffic through the mixed layout behaves.

GitHub CI on `main`: see the last section (filled in once the run finished).

## Not done (yet)

- **The 31-building pack** (220 MB, geometry only, 166-534 k triangles each): planned as the far tier (simplified silhouettes, a window shader). The procedural towers fill that role for now.
- **The highway props pack on the loop:** its barriers, signs and pylons are converted and registered, but the loop still draws its own. Its two warning signs are in the stages.
- **The McLaren P1 GTR** is still blocked (handled as no-AI: scripts and numbers only). Retried:
  - The pre-thinned model exports fine on its own (36.5 MB in 6 s), so the export isn't the problem.
  - The converter gets through every decimation, then a 400 MB allocation fails in the step right after the body's decimation (the livery guides).
  - Next: thin the 118 k triangles of paint and glass it keeps whole, or skip the guides for this car.
- **The other carriageway doesn't slow down at the plaza** in the mixed layout. Those cars keep their speed (they're scenery across the median and can't brake for each other), but they do keep out of their closed lane.
- **The biggest buildings' facades are coarse up close:** the 150 m office complexes get 6 px a metre in one 2048 px image; the small blocks get up to 31.
- **The download grew about 30 %**: the update pack was 499 MB in the last release and is 646 MB in this build's update test. The buildings' facades alone are 87 MB imported (2048 px each, with an alpha for the glass, in both desktop and mobile compressed formats); the trees and the rocks are another 79 MB. Halving the big buildings' images, or dropping the mobile format, would claw most of it back.
- **HIGH's shadows are heavy** (8-10 M shadow triangles: every near tree casts its own). MEDIUM, with shadow proxies, is 0.3-0.5 M.

## Three lenses on what's next

**1. The far tier from the 31-building pack**

- *Why it would work:* the skyline is the one place the drawn boxes still show.
- *What won't:* 166-534 k triangles each with no materials means heavy simplification and a shader for the windows. It's an hour of conversion, and it's only seen from far off.
- *Worth it:* medium.

**2. Trim the download**

- *Why it would work:* compress the trees' and buildings' textures for size and drop the GLB-embedded copies, likely 100 MB+ off.
- *What won't:* the updater downloads whole packs, so every big asset change costs players the full download.
- *Worth it:* high.

**3. The P1 GTR**

- *Why it would work:* the cause is narrowed to one step.
- *What won't:* the source is a kitbash with no textures of its own, so even converted it's the weakest model in the garage.
- *Worth it:* low, unless a cleaner model turns up.
