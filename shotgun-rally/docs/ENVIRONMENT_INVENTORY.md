# Environment inventory

What the world is built from: the owner's uploaded packs and the CC0 library in
`assets/environment_packages/`, what was taken from each, how it was converted, where it ends
up in the game and what it costs to draw. (The cars have their own: `VEHICLE_REPORT.md`.)

## The pipeline

| Step | Tool | Where |
|---|---|---|
| Restore a pack from its 90 MB parts and check its size and SHA-256 against the manifest (from the working tree, or straight from git in a sparse checkout) | `tools/restore_environment_assets.py [--only TEXT] [--list]` | `assets/environment_restored/` (git- and Godot-ignored) |
| Unpack it: each archive into its own new folder, paths checked, scripts never run | Python `zipfile` / `unrar` | `assets/environment_work/` (ignored) |
| Convert, one spec at a time (`tools/environment_specs.json`); sources are only read, opened with scripts off | `blender -b -Y --python tools/import_environment.py -- <spec> [files] [--work DIR]` (modes: props, `tree` → `tools/vegetation.py`, `building` → `tools/buildings.py`, `skyline` → `tools/skyline.py`; `--work`: the packs unpacked in another checkout) | `assets/environment_runtime/` (committed: the GLBs and the textures Godot takes out of them) |
| Register what each part is (kind, size, trunk, tags, source) | `data/environment_assets.json` | read by `scripts/stage/env_assets.gd` |
| Group it into lands with seasons | `data/biomes.json` | `scripts/stage/biomes.gd` |
| Place it | `scripts/stage/stage_builder.gd` (rally and touge), `scripts/stage/loop_builder.gd` (the highway loop; its city's far tier: `scripts/stage/city_skyline.gd`) | |
| Check it | `tests/environment_check.gd`, `tests/toll_check.gd`; pictures: `tools/env_preview.gd`, `tools/loop_shots.gd`; costs: `tools/stage_perf.gd`; numbers: `tools/env_stats.gd` | |

## The owner's packs

The manifest marks these "user-provided-license-review-required". The owner made them (or
licensed them) and asked for them to be used, so their licence isn't tracked here. Only the
converted runtime files are committed; the restored and unpacked sources stay out of git.

| Pack (manifest) | Size | Format | What's in it | What the game takes | Runtime | Status |
|---|---|---|---|---|---|---|
| `vegetation/chvegetation_vol5_fbx.rar` | 496 MB | 12 FBX + maps | 12 conifers (Scots-pine-like: tall bare trunks, crowns high up), 0.4-1.9 M triangles each, needle cards + bark | all 12, as `conifer_01..12` (25.9, 26.4, 26.4, 18.0, 21.5, 26.0, 25.1, 25.5, 24.8, 17.1, 21.3, 27.5 m tall) | `vegetation/conifers.glb` | in the game |
| `vegetation/tree_robinia_pseudoacacia_fbx.zip` | 89 MB | FBX | 4 black locusts (Robinia), 0.2-0.5 M triangles; its leaf texture didn't come in the pack | all 4 as `robinia_a..d` (6.6-9.9 m); the leaflets drawn by the converter, the bark the conifer pack's, tinted | `vegetation/robinia.glb` | in the game |
| `vegetation/tall_pines_blend.zip` | 40 MB | .blend | 5 tall pines, 59-274 k triangles | all 5 as `tall_pine_1..5` (11.2-24.4 m) | `vegetation/tall_pines.glb` | in the game |
| `city/22_buildings_2024_v2.zip` | 1.16 GB | .blend (+ FBX, OBJ, GLB copies, 143 textures) | 22 European apartment and office buildings, 3 k-365 k triangles, 7-34 materials each | the .blend files, each building made light (60 k triangles at most, Godot's LODs below that) with one facade image (its colour x its ambient occlusion, its glass in the alpha for lit windows at night) | `city/bld22_*.glb` | in the game: the loop city's front rows |
| `city/31_model_separate_files.rar` | 220 MB | 31 FBX (124 MB unpacked) | 30 files of apartment and office buildings, 61-534 k triangles each, geometry only (no materials, no UVs worth having), in millimetres; `01.FBX` holds two buildings side by side; the 31st file, `Rooftop.FBX`, is a kit of 18 roof props (tanks, masts, a billboard) | all 31 buildings, as `bld31_01a`, `bld31_01b`, `bld31_02..30`: silhouettes for far off in three levels (voxel-remeshed: 1.0-3.4 k triangles, 250-680 beyond 650 m, 120-240 beyond 1.8 km), real size (18-141 m tall in the source, 17-138 m as silhouettes: the masts go; floors measured at 2.7-4.1 m), no textures: a shader draws the facade and windows. The roof-prop kit isn't taken (too small to see from the far tier) | `city/bld31.glb` (2.3 MB) | in the game: the loop city's far tier |
| `highway/highway_props_model.rar` | 42 MB | .blend | a pylon and its cable insulator, two crash barriers, three road signs (winding road, slippery road, speed limit) | all 7 | `props/highway_props.glb` | converted and registered; the loop's barriers, signs and pylons are still its own procedural ones |

## The CC0 library (`assets/environment_packages/cc0/`, `CC0_SOURCES.md`)

| Source | Licence | What the game takes | Runtime |
|---|---|---|---|
| Poly Haven `rock_moss_set_01` (2K) | CC0 | 6 mossy rocks (`rock_moss_01..06`): boulders by the stages | `rocks/rock_moss_set.glb` |
| Poly Haven `rock_face_01` (2K) | CC0 | a scanned rock face (`rock_face_01`, 4.95 x 3.56 x 3.83 m): the rock cuts on mountain stages | `rocks/rock_face_01.glb` |
| Poly Haven `forrest_ground_01` (2K) | CC0 | the forest floor texture (`forest`) | `assets/textures/world/forest_*.webp` |
| Poly Haven `asphalt_02` (2K) | CC0 | a second asphalt (`asphalt2`): the touge's and the alpine roads | `assets/textures/world/asphalt2_*.webp` |
| Kenney City Kit (Roads) 2.1 | CC0 | 22 props: poles, lights, cones, barriers, signs, traffic lights, pillars, a dumpster (in toy units: the registry scales each to its real size) | `props/kenney_props.glb` |

Credits for all of these are in `docs/CREDITS_WORLD.md`.

## How each kind is converted

**Trees** (`tools/vegetation.py`, budgets in the specs). Three levels per tree:

- **LOD0** (11-23 k triangles): the leaf cards picked as whole islands with a bias to the crown's outside, then enlarged so the crown stays full. The bark keeps its biggest pieces, the twigs go. The trunk is rebuilt as a clean tube from its measured profile and is left out of the decimation. The crown's normals point outward.
- **LOD1** (1.3-2.2 k): the same, sparser and coarser.
- **Far card**: two crossed pairs of one-sided cards, the picture rendered in Cycles in even light, framed on the tree's real bounds.

Every tree in a pack shares one bark and one or two leaf materials. In the game (`EnvAssets.foliage`) the leaves are:

- cut out by alpha, with alpha-to-coverage; the cut is per species, lower for thin needles whose mipmaps fade: conifers 0.3, tall pines 0.2;
- drawn on both sides;
- lit with wrap lighting and backlight, so the shaded side of a crown isn't black;
- given a softened normal map.

**Rocks, rock faces and props**: joined per part, the origin at the foot, textures resized (2K rocks, 512 px props), WebP in the GLB.

**Buildings** (`tools/buildings.py`):

- the building's meshes in world space, with stray loose parts far off the building cut;
- flat areas dissolved, collapsed to 60 k triangles at most;
- the full building's flat normals copied onto the light one;
- each face laid onto the side it faces (four walls and the roof, one 2048 px image at one scale: 6 px a metre on the 150 m complexes up to 31 on the small blocks);
- that image painted from orthographic Cycles pictures of the full building from each side (its diffuse colour times its ambient occlusion, its glass from a second picture where the glass glows);
- Godot generates the distance LODs.

In the game (`EnvAssets.building`) the glass is glossy, and at night some windows are lit, warm or cold-white, one per window-sized cell of the wall.

**Far-tier buildings** (`tools/skyline.py`, the 31-building pack: geometry only):

- each file's meshes in metres (the pack is in millimetres), grouped into buildings by their footprints (`01.FBX` gives two);
- closed at the foot (the models have no floor), voxel-remeshed at 0.5 m: the window reveals, balcony rails and sills close up, the masts go, what's left is the outline you see from 200 m and more;
- collapsed to 6x the budget, its near-flat faces dissolved into the walls' planes, collapsed to the budget (2.4 k triangles per 100 m of height, 1 k to 4 k: kept low, a whole district of them is drawn at once), normals smooth within 30 degrees and sharp at the corners;
- two lighter copies, each remeshed again from the full model with coarser voxels (1 m, 2 m: that closes the gaps behind balconies and round the roof's plant, which a collapse can't take away), the loose pieces under 3 / 6 m left out: LOD1 a fifth of the full one (250 at least) for beyond 650 m, LOD2 a third of that (120 at least) for beyond 1.8 km;
- the full model's floor height and window bay measured (the strongest repeat of its sills' heights and its reveals' sides), and its main roof's height (the pack's `Roof_*` meshes are the plant on it), into the registry for the shader;
- all 93 meshes in one GLB, no material, no UVs; imported without Godot's own LODs (its simplifier crumpled them far off: the copies are the levels), tangents or shadow meshes (they cast none).

In the game (`CitySkyline.material`) one shader draws them all, from where a pixel is on the building (its own space, in metres): the instance's facade colour; on each wall a window grid at the building's own floors and bays (each building its own window shape); the glass dark and bluish by day with the sky in it at a glancing angle and a few blinds drawn; at night a share of the windows lit (16-42 % by building), warm or cold-white, by the same night signal as the towers (`WorldMaterials.night_amount`); the roof and the plant on it plain; far off, where a floor is a pixel or two, the grid fades to its average by day (no shimmer) and at night each lit window's whole cell glows (points of light, not a glowing wall). No textures; it runs on Forward+ and Compatibility.

## The lands (biomes, `data/biomes.json`)

| Biome | Trees (a stage takes 4 of these + 2 broadleaves, by its seed) | Broadleaf share | Rocks | Rock cuts | Other | Seasons | Ground / road |
|---|---|---|---|---|---|---|---|
| japan_cedar (touge) | conifers 01, 02, 03, 05, 06, 07, 08, 09, 10, 12 | the forest's own | 12 % | yes | a power line on wooden poles | summer, autumn, winter | forest floor, asphalt 2 |
| temperate_broadleaf (mixed stages, golden autumn rally) | tall pines 1-5, conifers 04, 05, 11 | 60 % | 5 % | | | summer, autumn, winter | forest floor |
| conifer_rally (gravel) | conifers (11), tall pines 1-5 | the forest's own | 5 % | | | summer, autumn, winter | forest floor |
| alpine_rock (mountain tarmac) | conifers 04, 05, 10, 11 | none | 30 % | yes | | summer, winter | asphalt 2 |
| wet_forest (puddles, mud rally) | conifers (11) | the forest's own | 18 % | | | autumn | forest floor |
| winter_mountain (ice) | conifers (11) | none | 12 % | yes | snow | winter | |
| suburban_verge (the loop) | tall pines, conifers 04, 05, 11 | 70 % | | | | summer, autumn | |
| urban_corridor | conifers 04, 05, 11 | 85 % | | | | summer | |

A stage picks its biome from what it is (a touge, ice, tarmac, mixed, puddles, gravel), or
from the story rally that names one (`championship.gd`). The season comes from the rally or
the biome's own, and recolours the leaves (autumn: the broadleaves turn).

## Placement rules

- **Nothing on the road.** Trees, boulders, rock faces and poles are each checked against every sample of the road (switchbacks pass close to other parts of themselves), and a car-sized box swept down both lanes touches none of them (`tests/environment_check.gd`).
- **Trees** stand behind the stage's tree line and are grouped for their LODs:
  - the first 12 m off the road's edge per 32 m of road (full tree to 30 m, the lighter one to 90 m, the card beyond);
  - the forest behind per 48 m and side (the lighter tree to 60 m, then the card);
  - the far belt (76-150 m off) only ever as the card.

  All distances are times the graphics level's view distance. Godot swaps a group's level by the distance to its middle, so the groups are kept small.
- **Shadows:** at HIGH and up every near tree casts its own. At MEDIUM the full trees' shadows come from their lighter versions and the rest cast none. At LOW the old low-poly cone trees stay, with no library trees.
- **Solid things:** the trunks near the road, boulders taller than 0.9 m within 20 m, and the poles. Species come from a hash of the spot, so the solid things are identical at every graphics level and every machine in an online race agrees (tested: 1,812 of them on a touge, LOW = MEDIUM).
- **Boulders, rock cuts and poles** each use their own seeded dice: the same stage gives the same dressing.
- **The loop's city:**
  - the library's buildings in the front rows (to 190 m from the road's middle), each its own node with its LODs, long side to the road, never overlapping or on a road;
  - the far tier behind (`scripts/stage/city_skyline.gd`), from 200 m to the city's edge (645 m): the 31-building pack, in place of the drawn towers that stood there. Each building on the ground as drawn (the land's own triangles under its footprint, flat to 0.8 m, its foot 0.1 m under the lowest of it), on the city's ground (none in the water), 40 m and more from the road and its ramps, never on another building, long side to the road (a square one any way round). Each kilometre of road (a district, both sides) is built from 6 of the designs (2 towers, 3 mid-rises, a low block), mixed: the taller likelier further out and in the middle of town, now and then a tower anywhere, gaps between the blocks: about 1,100 buildings in all. The ground steps where the road's land ribbons end (about 300-345 m out), so that band stays open. One MultiMesh per design and district, by the distance to the district's middle: the full silhouettes to 650 m, LOD1 to 1.8 km, LOD2 to 4 km x the level's view distance (the low blocks from LOD1); no shadows (past the sun's shadow map anyway). Their own dice: the rest of the city and the trees come out as before. `--no_skyline` (stage_perf, loop_shots) builds the city without it, for a comparison.

## What it costs to draw

Measured with `tools/stage_perf.gd` (a driver's-eye view down the road at several places; xvfb's software renderer, so the counts are right but the times aren't a real GPU's).

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
| The loop's city at s 1500, 3600, 5200, 26600, MEDIUM, **before** the far tier (the drawn towers behind) | 1.56-2.05 M | 185-228 | 0.24-0.41 M | 793 MB |
| The same, MEDIUM, **with the far tier** (about 1,100 of the 31-building pack) | 1.74-2.35 M (+11-17 %) | 192-246 (+7-21) | 0.20-0.40 M | 795 MB |
| The same, ULTRA, before | 1.56-2.05 M | 185-229 | 0.45-0.77 M | 1,266 MB |
| The same, ULTRA, with the far tier (drawn 1.3x further) | 1.74-2.37 M (+11-19 %) | 192-254 (+7-27) | 0.42-0.76 M | 1,267 MB |

Building a stage takes 3.4-5.6 s here, the loop 17.6 s (the loading screen covers it); the far tier adds next to nothing to that (the city's step took 3.1-3.2 s before it, 3.0-3.5 s with it, on a loaded machine).

The far tier's triangles in view are mostly the district round the camera at full detail (about 100 buildings, 200-300 k triangles); the light and lightest copies further on add 50-130 k. Godot's own LODs are off for it: on these meshes they crumpled the far silhouettes (and without them the first try drew 3.2 M triangles: hence the light copies, the lower budget and the 650 m switch).

## Not done yet

- The highway props pack placed on the loop (its barriers, signs and pylons are still procedural).
- Signs on the touge and rally stages (the winding-road sign before bends, the slippery one on wet and ice).

## Every asset in the library

From `tools/env_stats.gd` (triangles as loaded in Godot; sizes in metres, x the registry's scale for the props; a building's LOD0, Godot's own LODs below it; a far-tier building's silhouette / LOD1 / LOD2).

| Asset | Kind | Runtime file | Triangles (LOD0 / LOD1 / far card) | Size (m) | Source |
|---|---|---|---|---|---|
| `bld22_01` | building | bld22_01.glb | 59997 | 90.2 x 73.8 x 115.1 | owner's pack: 22 Buildings 2024 (Blender), 237426 triangles in the source |
| `bld22_02` | building | bld22_02.glb | 46682 | 47.4 x 42.0 x 32.5 | owner's pack: 22 Buildings 2024 (Blender), 46682 triangles in the source |
| `bld22_03` | building | bld22_03.glb | 13952 | 32.3 x 55.1 x 50.8 | owner's pack: 22 Buildings 2024 (Blender), 13952 triangles in the source |
| `bld22_04` | building | bld22_04.glb | 12691 | 58.0 x 49.9 x 34.6 | owner's pack: 22 Buildings 2024 (Blender), 12691 triangles in the source |
| `bld22_05` | building | bld22_05.glb | 27652 | 39.7 x 49.9 x 32.3 | owner's pack: 22 Buildings 2024 (Blender), 27659 triangles in the source |
| `bld22_06` | building | bld22_06.glb | 11741 | 49.7 x 55.3 x 47.6 | owner's pack: 22 Buildings 2024 (Blender), 11741 triangles in the source |
| `bld22_07` | building | bld22_07.glb | 56838 | 56.5 x 47.6 x 35.1 | owner's pack: 22 Buildings 2024 (Blender), 56838 triangles in the source |
| `bld22_08` | building | bld22_08.glb | 15426 | 104.8 x 98.8 x 139.7 | owner's pack: 22 Buildings 2024 (Blender), 15426 triangles in the source |
| `bld22_09` | building | bld22_09.glb | 60000 | 44.0 x 64.6 x 42.5 | owner's pack: 22 Buildings 2024 (Blender), 82564 triangles in the source |
| `bld22_10` | building | bld22_10.glb | 15949 | 35.5 x 56.0 x 36.7 | owner's pack: 22 Buildings 2024 (Blender), 15949 triangles in the source |
| `bld22_11` | building | bld22_11.glb | 25410 | 50.0 x 49.0 x 35.6 | owner's pack: 22 Buildings 2024 (Blender), 25410 triangles in the source |
| `bld22_12` | building | bld22_12.glb | 8559 | 30.9 x 39.7 x 33.4 | owner's pack: 22 Buildings 2024 (Blender), 8559 triangles in the source |
| `bld22_13` | building | bld22_13.glb | 59982 | 47.4 x 148.1 x 47.3 | owner's pack: 22 Buildings 2024 (Blender), 365086 triangles in the source |
| `bld22_14` | building | bld22_14.glb | 13931 | 48.7 x 38.7 x 26.5 | owner's pack: 22 Buildings 2024 (Blender), 13931 triangles in the source |
| `bld22_15` | building | bld22_15.glb | 10315 | 115.9 x 44.6 x 102.2 | owner's pack: 22 Buildings 2024 (Blender), 10315 triangles in the source |
| `bld22_16` | building | bld22_16.glb | 29158 | 81.9 x 54.0 x 37.3 | owner's pack: 22 Buildings 2024 (Blender), 29158 triangles in the source |
| `bld22_17` | building | bld22_17.glb | 28676 | 68.4 x 88.0 x 64.2 | owner's pack: 22 Buildings 2024 (Blender), 28676 triangles in the source |
| `bld22_18` | building | bld22_18.glb | 24268 | 150.0 x 64.5 x 110.3 | owner's pack: 22 Buildings 2024 (Blender), 24268 triangles in the source |
| `bld22_19` | building | bld22_19.glb | 26592 | 54.6 x 44.9 x 40.9 | owner's pack: 22 Buildings 2024 (Blender), 26592 triangles in the source |
| `bld22_20a` | building | bld22_20a.glb | 59999 | 39.0 x 66.1 x 25.2 | owner's pack: 22 Buildings 2024 (Blender), 87742 triangles in the source |
| `bld22_20b` | building | bld22_20b.glb | 8676 | 39.9 x 34.7 x 21.3 | owner's pack: 22 Buildings 2024 (Blender), 8692 triangles in the source |
| `bld22_20c` | building | bld22_20c.glb | 3319 | 19.8 x 33.0 x 20.0 | owner's pack: 22 Buildings 2024 (Blender), 3320 triangles in the source |
| `bld31_01a` | skyline | bld31.glb | 1046 / 248 / 120 | 17.2 x 40.9 x 8.4 | owner's pack: 31 Model separate Files (FBX), 01.FBX, 94381 triangles in the source |
| `bld31_01b` | skyline | bld31.glb | 1000 / 250 / 120 | 17.2 x 27.4 x 8.4 | owner's pack: 31 Model separate Files (FBX), 01.FBX, 72151 triangles in the source |
| `bld31_02` | skyline | bld31.glb | 1006 / 250 / 120 | 11.0 x 38.9 x 6.1 | owner's pack: 31 Model separate Files (FBX), 02.FBX, 76885 triangles in the source |
| `bld31_03` | skyline | bld31.glb | 1246 / 250 / 120 | 14.6 x 49.1 x 18.4 | owner's pack: 31 Model separate Files (FBX), 03.FBX, 168601 triangles in the source |
| `bld31_04` | skyline | bld31.glb | 1000 / 250 / 120 | 17.8 x 23.5 x 10.3 | owner's pack: 31 Model separate Files (FBX), 04.FBX, 534253 triangles in the source |
| `bld31_05` | skyline | bld31.glb | 1662 / 332 / 120 | 21.7 x 66.3 x 14.0 | owner's pack: 31 Model separate Files (FBX), 05.FBX, 88524 triangles in the source |
| `bld31_06` | skyline | bld31.glb | 2234 / 446 / 156 | 30.3 x 85.7 x 47.2 | owner's pack: 31 Model separate Files (FBX), 06.FBX, 305923 triangles in the source |
| `bld31_07` | skyline | bld31.glb | 1000 / 250 / 120 | 25.0 x 26.2 x 17.1 | owner's pack: 31 Model separate Files (FBX), 07.FBX, 90865 triangles in the source |
| `bld31_08` | skyline | bld31.glb | 1000 / 250 / 120 | 15.9 x 18.1 x 21.4 | owner's pack: 31 Model separate Files (FBX), 08.FBX, 71848 triangles in the source |
| `bld31_09` | skyline | bld31.glb | 1000 / 250 / 120 | 24.1 x 27.0 x 10.6 | owner's pack: 31 Model separate Files (FBX), 09.FBX, 74577 triangles in the source |
| `bld31_10` | skyline | bld31.glb | 1000 / 250 / 120 | 41.0 x 35.1 x 20.5 | owner's pack: 31 Model separate Files (FBX), 10.FBX, 205439 triangles in the source |
| `bld31_11` | skyline | bld31.glb | 3295 / 658 / 230 | 50.3 x 129.8 x 38.5 | owner's pack: 31 Model separate Files (FBX), 11.FBX, 451157 triangles in the source |
| `bld31_12` | skyline | bld31.glb | 2334 / 466 / 162 | 35.6 x 89.7 x 27.1 | owner's pack: 31 Model separate Files (FBX), 12.FBX, 335336 triangles in the source |
| `bld31_13` | skyline | bld31.glb | 3214 / 642 / 224 | 25.7 x 126.7 x 25.7 | owner's pack: 31 Model separate Files (FBX), 13.FBX, 209480 triangles in the source |
| `bld31_14` | skyline | bld31.glb | 3393 / 678 / 236 | 25.2 x 134.2 x 25.3 | owner's pack: 31 Model separate Files (FBX), 14.FBX, 271658 triangles in the source |
| `bld31_15` | skyline | bld31.glb | 998 / 250 / 120 | 19.6 x 36.6 x 11.2 | owner's pack: 31 Model separate Files (FBX), 15.FBX, 114029 triangles in the source |
| `bld31_16` | skyline | bld31.glb | 1000 / 250 / 118 | 21.0 x 20.4 x 9.1 | owner's pack: 31 Model separate Files (FBX), 16.FBX, 60895 triangles in the source |
| `bld31_17` | skyline | bld31.glb | 998 / 250 / 118 | 13.9 x 34.5 x 14.4 | owner's pack: 31 Model separate Files (FBX), 17.FBX, 130998 triangles in the source |
| `bld31_18` | skyline | bld31.glb | 1000 / 250 / 120 | 15.6 x 30.0 x 14.8 | owner's pack: 31 Model separate Files (FBX), 18.FBX, 85856 triangles in the source |
| `bld31_19` | skyline | bld31.glb | 1000 / 250 / 120 | 15.2 x 30.4 x 11.2 | owner's pack: 31 Model separate Files (FBX), 19.FBX, 108485 triangles in the source |
| `bld31_20` | skyline | bld31.glb | 1000 / 250 / 120 | 16.5 x 27.1 x 25.4 | owner's pack: 31 Model separate Files (FBX), 20.FBX, 112081 triangles in the source |
| `bld31_21` | skyline | bld31.glb | 1886 / 376 / 130 | 41.4 x 70.9 x 21.3 | owner's pack: 31 Model separate Files (FBX), 21.FBX, 308902 triangles in the source |
| `bld31_22` | skyline | bld31.glb | 1676 / 334 / 120 | 20.1 x 66.9 x 26.8 | owner's pack: 31 Model separate Files (FBX), 22.FBX, 111417 triangles in the source |
| `bld31_23` | skyline | bld31.glb | 1800 / 360 / 124 | 46.5 x 67.9 x 18.3 | owner's pack: 31 Model separate Files (FBX), 23.FBX, 251454 triangles in the source |
| `bld31_24` | skyline | bld31.glb | 3306 / 657 / 229 | 51.1 x 137.5 x 41.9 | owner's pack: 31 Model separate Files (FBX), 24.FBX, 491733 triangles in the source |
| `bld31_25` | skyline | bld31.glb | 1000 / 250 / 120 | 47.0 x 17.9 x 56.0 | owner's pack: 31 Model separate Files (FBX), 25.FBX, 225795 triangles in the source |
| `bld31_26` | skyline | bld31.glb | 1172 / 250 / 118 | 15.7 x 46.3 x 18.1 | owner's pack: 31 Model separate Files (FBX), 26.FBX, 111773 triangles in the source |
| `bld31_27` | skyline | bld31.glb | 1000 / 248 / 120 | 11.8 x 30.9 x 29.1 | owner's pack: 31 Model separate Files (FBX), 27.FBX, 102639 triangles in the source |
| `bld31_28` | skyline | bld31.glb | 998 / 250 / 120 | 12.8 x 31.1 x 22.8 | owner's pack: 31 Model separate Files (FBX), 28.FBX, 110557 triangles in the source |
| `bld31_29` | skyline | bld31.glb | 998 / 248 / 120 | 30.3 x 18.0 x 25.9 | owner's pack: 31 Model separate Files (FBX), 29.FBX, 112259 triangles in the source |
| `bld31_30` | skyline | bld31.glb | 1204 / 250 / 120 | 25.3 x 47.4 x 15.5 | owner's pack: 31 Model separate Files (FBX), 30.FBX, 152883 triangles in the source |
| `bridge_pillar` | prop | kenney_props.glb | 38 | 1.6 x 8.0 x 1.6 | Kenney City Kit (Roads) 2.1 (CC0) |
| `bridge_pillar_wide` | prop | kenney_props.glb | 38 | 2.2 x 8.0 x 2.2 | Kenney City Kit (Roads) 2.1 (CC0) |
| `conifer_01` | tree | conifers.glb | 18770 / 1866 / 8 | 7.9 x 25.9 x 9.6 | owner's pack: chvegetation vol5 (conifers), chvol5_01.fbx |
| `conifer_02` | tree | conifers.glb | 19848 / 2008 / 8 | 8.4 x 26.4 x 8.0 | owner's pack: chvegetation vol5 (conifers), chvol5_02.fbx |
| `conifer_03` | tree | conifers.glb | 18867 / 1908 / 8 | 10.1 x 26.4 x 8.9 | owner's pack: chvegetation vol5 (conifers), chvol5_03.fbx |
| `conifer_04` | tree | conifers.glb | 19261 / 1938 / 8 | 7.5 x 18.1 x 7.4 | owner's pack: chvegetation vol5 (conifers), chvol5_04.fbx |
| `conifer_05` | tree | conifers.glb | 18653 / 1914 / 8 | 6.8 x 21.4 x 7.8 | owner's pack: chvegetation vol5 (conifers), chvol5_05.fbx |
| `conifer_06` | tree | conifers.glb | 18455 / 1900 / 8 | 7.5 x 26.0 x 7.5 | owner's pack: chvegetation vol5 (conifers), chvol5_06.fbx |
| `conifer_07` | tree | conifers.glb | 18409 / 1820 / 8 | 7.1 x 25.1 x 7.4 | owner's pack: chvegetation vol5 (conifers), chvol5_07.fbx |
| `conifer_08` | tree | conifers.glb | 19761 / 1904 / 8 | 8.1 x 25.4 x 8.4 | owner's pack: chvegetation vol5 (conifers), chvol5_08.fbx |
| `conifer_09` | tree | conifers.glb | 19673 / 1952 / 8 | 7.6 x 24.7 x 7.6 | owner's pack: chvegetation vol5 (conifers), chvol5_09.fbx |
| `conifer_10` | tree | conifers.glb | 22872 / 2242 / 8 | 9.5 x 17.1 x 9.6 | owner's pack: chvegetation vol5 (conifers), chvol5_10.fbx |
| `conifer_11` | tree | conifers.glb | 21620 / 2192 / 8 | 10.3 x 21.3 x 10.2 | owner's pack: chvegetation vol5 (conifers), chvol5_11.fbx |
| `conifer_12` | tree | conifers.glb | 18980 / 2000 / 8 | 8.9 x 27.4 x 7.2 | owner's pack: chvegetation vol5 (conifers), chvol5_12.fbx |
| `construction_barrier` | prop | kenney_props.glb | 60 | 1.1 x 1.0 x 1.8 | Kenney City Kit (Roads) 2.1 (CC0) |
| `construction_cone` | prop | kenney_props.glb | 66 | 0.6 x 0.8 x 0.6 | Kenney City Kit (Roads) 2.1 (CC0) |
| `construction_fence` | prop | kenney_props.glb | 136 | 0.6 x 1.4 x 3.0 | Kenney City Kit (Roads) 2.1 (CC0) |
| `construction_light` | prop | kenney_props.glb | 144 | 0.6 x 1.9 x 0.6 | Kenney City Kit (Roads) 2.1 (CC0) |
| `crash_barrier_a` | prop | highway_props.glb | 372 | 4.4 x 1.2 x 0.4 | owner's pack: highway props (Models.blend) |
| `crash_barrier_b` | prop | highway_props.glb | 372 | 4.4 x 1.2 x 0.4 | owner's pack: highway props (Models.blend) |
| `dumpster` | prop | kenney_props.glb | 234 | 1.9 x 1.5 x 2.6 | Kenney City Kit (Roads) 2.1 (CC0) |
| `electricity_pole` | prop | kenney_props.glb | 416 | 10.4 x 9.4 x 3.9 | Kenney City Kit (Roads) 2.1 (CC0) |
| `electricity_pole_single` | prop | kenney_props.glb | 176 | 1.4 x 9.4 x 3.9 | Kenney City Kit (Roads) 2.1 (CC0) |
| `electricity_pole_wide` | prop | kenney_props.glb | 544 | 19.4 x 9.4 x 3.9 | Kenney City Kit (Roads) 2.1 (CC0) |
| `electricity_wires` | prop | kenney_props.glb | 72 | 9.1 x 1.2 x 3.3 | Kenney City Kit (Roads) 2.1 (CC0) |
| `light_curved` | prop | kenney_props.glb | 92 | 0.7 x 9.4 x 3.1 | Kenney City Kit (Roads) 2.1 (CC0) |
| `light_curved_double` | prop | kenney_props.glb | 152 | 0.7 x 9.4 x 5.6 | Kenney City Kit (Roads) 2.1 (CC0) |
| `light_square_double` | prop | kenney_props.glb | 88 | 0.7 x 8.4 x 5.9 | Kenney City Kit (Roads) 2.1 (CC0) |
| `pylon` | prop | highway_props.glb | 8886 | 0.7 x 11.5 x 4.0 | owner's pack: highway props (Models.blend) |
| `pylon_cable` | prop | highway_props.glb | 2304 | 40.4 x 2.0 x 3.5 | owner's pack: highway props (Models.blend) |
| `road_sign_stop` | prop | kenney_props.glb | 104 | 0.5 x 3.0 x 0.8 | Kenney City Kit (Roads) 2.1 (CC0) |
| `road_sign_street` | prop | kenney_props.glb | 154 | 1.2 x 2.9 x 1.2 | Kenney City Kit (Roads) 2.1 (CC0) |
| `road_sign_warning` | prop | kenney_props.glb | 104 | 0.5 x 3.0 x 0.9 | Kenney City Kit (Roads) 2.1 (CC0) |
| `robinia_a` | tree | robinia.glb | 18285 / 1502 / 8 | 5.3 x 6.6 x 3.6 | owner's pack: Robinia pseudoacacia (FBX; leaf texture drawn, bark from the conifer pack) |
| `robinia_b` | tree | robinia.glb | 18156 / 1526 / 8 | 6.0 x 8.5 x 5.2 | owner's pack: Robinia pseudoacacia (FBX; leaf texture drawn, bark from the conifer pack) |
| `robinia_c` | tree | robinia.glb | 18476 / 1500 / 8 | 5.1 x 6.6 x 4.1 | owner's pack: Robinia pseudoacacia (FBX; leaf texture drawn, bark from the conifer pack) |
| `robinia_d` | tree | robinia.glb | 19029 / 1632 / 8 | 7.8 x 10.0 x 6.1 | owner's pack: Robinia pseudoacacia (FBX; leaf texture drawn, bark from the conifer pack) |
| `rock_face_01` | cliff | rock_face_01.glb | 20174 | 5.0 x 3.6 x 3.8 | Poly Haven rock_face_01 (CC0) |
| `rock_moss_01` | rock | rock_moss_set.glb | 11000 | 2.2 x 1.5 x 3.4 | Poly Haven rock_moss_set_01 (CC0) |
| `rock_moss_02` | rock | rock_moss_set.glb | 10996 | 2.7 x 1.3 x 3.3 | Poly Haven rock_moss_set_01 (CC0) |
| `rock_moss_03` | rock | rock_moss_set.glb | 5000 | 2.1 x 1.1 x 2.1 | Poly Haven rock_moss_set_01 (CC0) |
| `rock_moss_04` | rock | rock_moss_set.glb | 10589 | 2.1 x 1.8 x 2.0 | Poly Haven rock_moss_set_01 (CC0) |
| `rock_moss_05` | rock | rock_moss_set.glb | 16548 | 1.8 x 1.2 x 3.0 | Poly Haven rock_moss_set_01 (CC0) |
| `rock_moss_06` | rock | rock_moss_set.glb | 8994 | 2.1 x 1.3 x 2.8 | Poly Haven rock_moss_set_01 (CC0) |
| `sign_highway` | prop | kenney_props.glb | 180 | 1.2 x 6.4 x 9.0 | Kenney City Kit (Roads) 2.1 (CC0) |
| `sign_highway_detailed` | prop | kenney_props.glb | 256 | 1.2 x 7.4 x 9.0 | Kenney City Kit (Roads) 2.1 (CC0) |
| `sign_highway_wide` | prop | kenney_props.glb | 144 | 1.2 x 6.4 x 9.0 | Kenney City Kit (Roads) 2.1 (CC0) |
| `sign_slippery` | prop | highway_props.glb | 516 | 0.6 x 2.2 x 0.1 | owner's pack: highway props (Models.blend) |
| `sign_speed_limit` | prop | highway_props.glb | 584 | 0.7 x 2.2 x 0.1 | owner's pack: highway props (Models.blend) |
| `sign_winding` | prop | highway_props.glb | 512 | 0.8 x 2.2 x 0.1 | owner's pack: highway props (Models.blend) |
| `tall_pine_1` | tree | tall_pines.glb | 11053 / 1282 / 8 | 3.9 x 11.2 x 3.6 | owner's pack: Tall Pines (Blender) |
| `tall_pine_2` | tree | tall_pines.glb | 11710 / 1332 / 8 | 5.0 x 15.0 x 4.9 | owner's pack: Tall Pines (Blender) |
| `tall_pine_3` | tree | tall_pines.glb | 11658 / 1476 / 8 | 5.9 x 18.9 x 5.4 | owner's pack: Tall Pines (Blender) |
| `tall_pine_4` | tree | tall_pines.glb | 11515 / 1568 / 8 | 4.9 x 22.0 x 6.0 | owner's pack: Tall Pines (Blender) |
| `tall_pine_5` | tree | tall_pines.glb | 11702 / 1548 / 8 | 7.1 x 24.4 x 6.2 | owner's pack: Tall Pines (Blender) |
| `traffic_light` | prop | kenney_props.glb | 212 | 1.2 x 5.1 x 0.9 | Kenney City Kit (Roads) 2.1 (CC0) |
| `traffic_light_hanging` | prop | kenney_props.glb | 230 | 1.2 x 5.1 x 3.0 | Kenney City Kit (Roads) 2.1 (CC0) |
