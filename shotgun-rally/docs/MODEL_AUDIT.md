# The world's models: an audit (2026-10-13)

Every model in the game that isn't a car: the city's buildings, the rally towns and touge
villages, CINDER RIDGE's paddock and trackside, the gas station and the toll plaza, the trees
and plants, the rocks, the props (signs, lamps, barriers, bridges, pit kit, the crowds) and the
ground. Checked for: distortion (import axes or scale, stretched placement), faces drawn from
the wrong side (normals or winding), missing, stretched or magenta textures, floating or sunk
placement, clipping into roads or each other, level-of-detail pops, far cards facing wrong and
wrong materials (metal, mirror-smooth or glowing where they shouldn't be).

How: `tools/world_audit.gd` (every library model as the game loads it, from its data: size
against its entry, winding against normals, textures, materials, levels), the tests (below),
and pictures of each place (`tools/env_preview.gd`, `tools/circuit_shots.gd`,
`tools/loop_shots.gd`, the game's `--screenshot`).

## The checks (now in the tests)

| Category | Where it's checked |
|---|---|
| Distortion (size against the source / the entry, no scaled placement) | `tests/city_check.gd` (the city's buildings against their sources' measured size; every building on the loop placed, never scaled), `tests/environment_check.gd` (every library model its entry's size) |
| Faces drawn from the wrong side | `tests/city_check.gd` (the buildings), `tests/environment_check.gd` (every one-sided surface of the library) |
| Missing or wrong textures | `tests/city_check.gd` (each building's UVs inside its one baked image), `tools/world_audit.gd` (plain white where an image was expected, magenta, tiny images) |
| Floating or sunk | `tests/environment_check.gd` (every tree, boulder, rock face, fern, pole and sign on five stages against the ground as drawn), `tests/modes_check.gd` (the city's far tier) |
| Clipping into roads or each other | `tests/environment_check.gd` (nothing on the road, a car-sized box down the road), `tests/city_check.gd` (no building on a street or another building, nothing on the road), `tests/modes_check.gd`, `tests/lamps_check.gd` |
| Level-of-detail pops, far cards | `tests/environment_check.gd` (a tree's levels the same height, its far card upright) |
| Materials | `tests/environment_check.gd` (nothing in the library glows or is mirror-smooth) |

## What was wrong

| Model | What was wrong | Fixed | Left |
|---|---|---|---|
| The city's 22 front-row buildings (`bld22_*.glb`, cut up) | Distorted on import: one (bld22_18) cut down to its podium (its 200 m tower thrown away as a stray bit); every face painted from five orthographic renders (anything they saw at a slant smeared: balconies, reveals, courtyards, curved walls); the normals copied from the full building's nearest face, the wrong one on back-to-back faces (0.4-15 % of a building lit from behind, its occlusion baked from inside: dark blotches); one's entry 1.6 m too deep (loose vertices counted) | Yes: re-baked (`tools/buildings.py`: their own UV map, each face's own colour from the face itself, shaded from their own faces; 4096 images for the six that would get under 6.5 px a metre). Each now its source's measured size (to 1 %), its faces 0.00 % against their normals; `tests/city_check.gd` | Texel density 5-21 px a metre (it was ~8-30 on the faces the renders saw square on, smeared elsewhere): soft from closer than ~40 m. Godot's own LODs on them as before |
| Marshal huts and flag poles (CINDER RIDGE trackside, `track_props.glb`) | The flag pole stood at its hut's height 2 m away: in the air beside a hut on a slope | Yes: the pole on the land at its own spot, the hut on the lowest land under its corners | - |
| Trees, boulders, rock faces and the forest floor on the rally and touge stages (`StageBuilder`) | Stood by the ground profile's formula from one sample of the road, not on the ground as drawn: 0.25-4.6 m in the air on the gentle stages (gravel, wet forest), up to 50 m on the mountain stages (alpine, winter: over the mountainside where it's tucked in under the road's ribbons) and 88 m on the touge's switchbacks | Yes: once the ground is built, `_ground_height` is the drawn ground's (the ribbons and the mountainside) wherever there is one; on five test stages the highest foot is now 0.00 m over it. Every machine still agrees on the solid trunks (the same ground at every graphics level) | Power poles stand on the lowest ground under their foot: up to 1.5 m into a steep bank on its uphill side (by design: never floating on the downhill side) |
| Pit garages, fuel rigs, helmet racks (CINDER RIDGE paddock, `track_props.glb`) | Their white paint glowed a little (emission 0.12 from the pack): lit grey at night | Yes: the entries' `no_glow` (EnvAssets turns their glow off) | - |
| Power pylon (`highway_props.glb`, not placed anywhere) | Its entry's size had its width and depth swapped (4.0 x 0.65 against the mesh's 0.65 x 4.0) | Yes: the entry | - |
| Team garages in CINDER RIDGE's paddock (`pit_garage_double`) | From above (the paddock camera) plain white boxes: the pack's model is flat colours, mostly white (by design: untextured) | - | Looks bare from the air; a texture or a darker roof would need a new model |
| The rest of the library: conifers, robinias, tall pines (their LOD0, LOD1 and far cards), rocks and rock faces, the forest floor, the highway, Kenney and track props | Checked (`tools/world_audit.gd`, 256 models and levels): each its entry's size, its one-sided faces wound the way their normals face, no magenta or missing image, no stray glow; a tree's levels the same height; far cards two crossed planes, upright | Nothing to fix | The track props are untextured flat colours (their pack); the huts' and stands' windows are glass at roughness 0.08 |
| The city's far tier (`bld31.glb`, 31 silhouettes) | Checked: sizes, faces; on the ground, none on another building or a street (`tests/modes_check.gd`, `tests/city_check.gd`) | Nothing to fix | - |
| Rally towns and touge villages, the gas station, the toll plaza, the crowds, the wooden bridges (drawn in code) | Looked at (pictures at LOW and HIGH); the houses, crowds and street furniture stand on the ground the stage draws (the same `_ground_height` the trees now use) | Nothing further | - |

## Pictures

Before and after for every city building (source | before | after, Godot renders against Cycles
renders of the source), the city from the road and the air by day and night, the stages' forests,
villages and towns at LOW and HIGH, CINDER RIDGE's pits, paddock and a marshal post, the toll
plaza: taken with the scripts above (`--seen_cars_only` where a car can show; none of these
build traffic).
