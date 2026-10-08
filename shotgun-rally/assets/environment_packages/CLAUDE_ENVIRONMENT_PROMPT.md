# Autonomous environment integration prompt for Claude

Work autonomously in my private repository:

https://github.com/pbelfand-dot/Stock-multiplay-game

Read and follow `shotgun-rally/CLAUDE.md` before changing anything. Do not stop after making a plan. Make normal implementation decisions yourself, preserve the working game, test your work, and continue unless an action truly requires my account authorization.

## Goal

Use the curated environment library in `shotgun-rally/assets/environment_packages/` to make SHOTGUN RALLY's Japanese touge, rally stages, highways, toll plazas, and cutting-up mode look realistic and cohesive. Build reusable Godot systems instead of dropping giant unoptimized scenes into the game.

There is no artificial 30 MB runtime-asset limit. Optimize according to visual quality, frame rate, memory, draw calls, and loading time. Use Git LFS for genuinely large runtime binaries if the repository supports it. Do not split files that Godot needs to load directly.

## Sources

The CC0 assets are ready for immediate use:

- `cc0/polyhaven/rock_moss_set_01_2k`: six realistic mossy rocks.
- `cc0/polyhaven/rock_face_01_2k`: realistic cliff and retaining-cut rock face.
- `cc0/polyhaven/forrest_ground_01_2k`: PBR forest-floor material.
- `cc0/polyhaven/asphalt_02_2k`: PBR road/asphalt material.
- `cc0/kenney/kenney_city-kit-roads.zip`: 95 modular pieces in GLB, FBX, and OBJ, plus signs and traffic lights.

Read `CC0_SOURCES.md` and preserve its source/license record.

Restore the packaged user-provided sources with:

```sh
shotgun-rally/tools/restore_environment_assets.sh
```

That produces `shotgun-rally/assets/environment_restored/` containing:

- A 12-model conifer pack with FBX meshes and PBR maps.
- A Robinia pseudoacacia broadleaf tree in FBX.
- A tall-pine Blender model with diffuse and normal maps.
- A 22-building city set with Blend, FBX, OBJ, GLB, and texture variants.
- A 31-building background set in FBX, OBJ, and 3ds Max formats.
- A highway-prop set containing road geometry, crash barriers, pylons, signs, and related materials.

These six packages are marked `license-review-required`. Before opening, parsing, converting, or committing their contents, locate and preserve the marketplace license. If an asset is marked `no AI`, do not expose its raw data to an AI system. Keep it quarantined and continue with the CC0 library and procedural systems instead. Do not let a license-blocked pack stop the rest of the work.

Do not commit the restored source directory. Put approved, converted runtime assets in a separate organized location such as `shotgun-rally/assets/environment_runtime/`.

## First phase: audit and asset pipeline

Create an environment inventory covering every source, available formats, texture maps, approximate triangle counts, scale, intended biome, intended LOD, collision needs, license status, and import status.

Prefer GLB/glTF for Godot when quality is equal. Use FBX when it preserves a better hierarchy or materials. Use Blender headlessly for repeatable conversions. Do not destructively modify original sources.

Build reusable import and optimization tools that can:

- Normalize scale and orientation.
- Preserve UVs and PBR materials.
- Generate or retain practical LODs.
- Create lightweight collision meshes.
- Convert unsupported formats to GLB.
- Produce material instances instead of duplicate meshes.
- Verify missing textures and broken paths.
- Record source and license metadata.

## Vegetation and biome system

Build a data-driven biome system rather than placing every tree manually.

Required biome presets:

1. Japanese cedar/pine mountain forest for touge roads.
2. Mixed temperate broadleaf forest.
3. Dense conifer rally forest.
4. Rocky alpine mountain terrain.
5. Wet forest and muddy rally terrain.
6. Snow-covered winter mountain terrain.
7. Suburban highway verge.
8. Urban and industrial highway corridor.

Each biome should control tree species, density, height range, scale variation, rotation, ground cover, rocks, cliff frequency, fog, lighting, weather, and road-edge dressing.

Support seasonal variants where practical:

- Spring: fresh foliage, wet soil, lighter grass.
- Summer: dense green foliage and dry-to-normal road surfaces.
- Autumn: warmer leaves, leaf litter, damp forest floor.
- Winter: sparse deciduous foliage, snow layers, icy or wet roads.

Use biome-correct vegetation. Do not scatter every species everywhere. Touge forests should feel Japanese and mountainous; broadleaf roadside trees should be used differently from dense pines.

Implement vegetation using `MultiMeshInstance3D`, chunked spawning, or an equivalent efficient system. Include deterministic seeds, density controls, exclusion zones around roads, distance culling, LODs or impostors, and optional wind animation. Avoid full collision on distant vegetation.

## Materials and shaders

Create production-quality Godot materials and shaders for:

- Leaf and needle wind motion.
- Alpha-cutout foliage with stable shadows.
- Bark and trunk PBR response.
- Wetness controlled by weather.
- Snow accumulation or seasonal blending.
- Asphalt with albedo, normal, and roughness maps.
- Worn shoulder and dirty-road blending.
- Forest-floor and rock blending.
- Tunnel and toll-plaza lighting.
- Reflective road paint, signs, and lane markers.

Avoid excessive shader cost. Provide quality levels for lower-end machines. Test foliage for shimmering, sorting problems, overdraw, and unrealistic brightness.

## Touge and mountain environment

Use the rock face, mossy rocks, forest ground, and approved tree sources to improve the procedural touge generator.

Add:

- Rock cuts along steep roads.
- Retaining walls.
- Guardrails.
- Drainage channels.
- Mossy boulders.
- Forest-floor transitions.
- Dense but performant tree coverage.
- Utility poles and believable roadside details.
- Tunnels and bridge approaches.
- Scenic overlooks and small parking areas.
- Fog and layered mountain silhouettes.
- Day, night, rain, autumn, and winter variants.

The environment must never place trees, rocks, walls, or guardrails on the drivable surface. Tie prop placement to the road spline and terrain slope. Validate generated routes for impossible grades, self-intersections, blocked lanes, and floating scenery.

## Highway and cutting-up environment

Use the CC0 modular road kit as a layout and collision foundation, then upgrade its appearance with the realistic asphalt material, road markings, barriers, lights, signs, and approved building sources.

Build reusable modules for:

- Straight highway segments.
- Gentle and sharp curves.
- Elevation changes.
- Multi-lane sections.
- Merge and exit lanes.
- Interchanges.
- Overpasses.
- Tunnels.
- Bridge segments.
- Urban expressways.
- Industrial outskirts.
- Suburban corridors.
- Service roads.
- Rest areas.
- Gas-station surroundings.

Keep lane widths and clearances consistent. Generate traffic navigation lanes from the same source data as the visible roads so cars do not drift between lanes or collide with barriers.

Use the building packs as varied skyline and roadside dressing, not as one giant imported scene. Create foreground, midground, and distant-building tiers. Use simplified collisions only where the player can reach a building.

## Toll-plaza system

Build a modular realistic toll plaza suitable for the cutting-up mode.

Include:

- Toll canopy.
- Individual booths.
- Multiple lanes.
- Barrier gates.
- Concrete islands.
- Crash barriers.
- Lane signals.
- Overhead signs.
- Cameras or sensor props.
- Lighting for night driving.
- Closed-lane and open-lane states.
- Traffic navigation through each open lane.
- Safe collision geometry.
- Spawn and despawn zones beyond the plaza.

If there is no legally usable toll-booth model, create a clean modular booth procedurally from simple geometry and approved materials. Do not block the whole system waiting for one marketplace model.

Traffic should choose open lanes, slow appropriately, avoid stopped vehicles, pass through, and accelerate away. Provide configuration for all-open high-speed gameplay, realistic mixed lanes, and event/race layouts.

## Rally environments

Create or improve rally-stage scenery using the same biome system:

- Forest gravel stage.
- Wet muddy forest stage.
- Rocky mountain stage.
- Snowy winter stage.
- Mixed paved/gravel stage.

Add believable road shoulders, ditches, signs, barriers, spectator-safe zones, service areas, and distant scenery. Surface visuals and physics must agree: wet, gravel, snow, mud, and asphalt should look and drive differently.

## Performance requirements

Target a stable frame rate with traffic and scenery active together.

Use:

- Chunk or sector streaming.
- MultiMesh for repeated vegetation and props.
- LODs or HLODs.
- Distance culling.
- Occlusion where useful.
- Shared materials.
- Texture compression.
- Object pooling.
- Simplified distant shadows.
- Lightweight distant geometry.

Do not use the full-resolution source mesh everywhere. Keep a high-quality source and generate practical runtime variants. Measure draw calls, triangle counts, memory, and loading times before and after optimization.

## Testing and acceptance

For every system, test:

- Godot import with no missing resources.
- Day and night lighting.
- Dry and wet weather.
- Multiple biome seeds.
- Road collision and reset behavior.
- Traffic navigation.
- Toll-lane selection.
- Vegetation exclusion from roads.
- LOD transitions.
- Material correctness.
- No obvious floating or buried props.
- Performance with dense traffic.
- Multiplayer compatibility where applicable.
- Existing game tests and CI.

Follow `CLAUDE.md` for branches, merging, CI, and release verification. Do not claim something works without testing it.

## Autonomous decision rules

Make ordinary decisions yourself. Prefer, in order:

1. A working and recoverable repository.
2. License compliance.
3. Visual realism.
4. Stable performance.
5. Reusable procedural systems.
6. Clean organization and documentation.

If an individual source is unusable, record why and continue. Do not ask me to choose every tree, material, LOD distance, road module, or building. Use professional judgment and keep moving.

At completion, report the assets used, license decisions, generated runtime files, biome presets, shaders, highway modules, toll-plaza behavior, rally improvements, tests, performance measurements, commits, CI status, release status, and any remaining blockers.
