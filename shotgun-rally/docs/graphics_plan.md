# The graphics pass: from flat colours to an Assetto Corsa / Forza look

The owner asked for the realistic look of Assetto Corsa / Forza instead of the flat-colour
"art of rally" style: Forward+ on the desktop builds (Compatibility stays on the web and
Chromebook builds), a lighting pass, real materials (car paint, glass, chrome, textured
roads and ground), glowing lamps ready for night maps, and a graphics quality setting so
weak PCs still run it.

## What gets built (in order of visual win per effort)

1. **The renderer.** `project.godot`: `rendering_method="forward_plus"`, with
   `.web` and `.mobile` overrides to `gl_compatibility`. The Chromebook `.deb`s are the
   Linux exports, so their launcher passes `--rendering-method gl_compatibility`
   (`tools/make_deb.sh`). A machine without Vulkan falls back to OpenGL by itself
   (`rendering/rendering_device/fallback_to_opengl3`, on by default; checked here: no
   Vulkan ICD -> "switching to OpenGL 3"). Settings gets a RENDERER choice (AUTO /
   COMPATIBILITY) written to `user://renderer.cfg`, which the engine reads at start
   through `application/config/project_settings_override` (checked here: the override
   file switches `get_current_rendering_method()`), so an old laptop can drop to the light
   renderer without a command line.
2. **Sky and light** (`scripts/render/world_materials.gd`: `environment(mood)`,
   `sun(mood)`). A photographed sky per mood (CC0 Poly Haven "pure sky" HDRIs: partly
   cloudy midday, sunset, overcast), stored log-encoded in an 8-bit 2048 x 569 WebP (40 KB
   each instead of 5 MB of HDR) and drawn by a sky shader that turns it so its sun sits
   where the DirectionalLight is, draws the sun disc, and fades below the horizon into the
   ground's colour (no blue light from under the road). The sky lights the scene (ambient
   and reflections), the fog takes its colour from the sky (aerial perspective on
   Forward+), AgX tonemapping, a gentle colour grade per mood. Shadows: 4 cascades tuned
   for driving (a sharp first split round the car, out to 100-220 m by level), soft
   (PCSS) on Ultra. SSAO from Medium, SSIL + SSR from High, SDFGI on Ultra, glow from
   Medium.
3. **Ground and road materials**, one shader for all (`world_materials.gd`): world-space
   triplanar (no UVs needed, works on the stage builder's meshes and anyone's), the
   texture's albedo + roughness + normal map, two scales mixed against tiling. The
   stage's vertex colours keep their meaning: in "colour" mode the vertex colour is the
   colour and the texture adds its detail (so the wheel tracks, the berms, the paint
   lines, snow patches, rock on the banks all stay where they were); in "multiply" mode
   (the default, for other meshes) the vertex colour tints the texture. The ground picks
   grass / dirt / rock / snow by its vertex colour. Ground and road get smooth normals.
   Textures: 7 CC0 Poly Haven scans (asphalt, gravel, grass, mud, rock, concrete, snow),
   1K, VRAM-compressed on import.
4. **Car materials** (`scripts/render/car_look.gd`, called once from
   `rally_car.gd`'s `_build_own_model()`): the livery paint gets a sharper clear coat;
   window glass and chrome get proper glossy values; a reflection probe rides above the
   car on High / Ultra so the paint reflects the trees and the road, not just the sky.
5. **Lamps**: the head and tail lamp materials found by name, colour and where they sit
   on the car (front / rear third) and given emission (their own texture as the mask):
   dim running lights by day, brake lights when braking, full at night; real lights (two
   spot headlights, two small red omni lights) at night or when Settings says so.
6. **Settings: GRAPHICS** (`scripts/ui/graphics_settings.gd`, two lines in
   `settings_panel.gd`): QUALITY LOW / MEDIUM / HIGH / ULTRA (first run: picked from the
   GPU: discrete -> HIGH, integrated -> MEDIUM, Compatibility / CPU -> LOW), RENDER SCALE,
   CAR LIGHTS, RENDERER. Applied live to the viewport and environment; textures on the
   next stage.

| | LOW | MEDIUM | HIGH | ULTRA |
|---|---|---|---|---|
| textures | flat vertex colours (today's look) | albedo + normal + roughness, one projection | + triplanar rock, anti-tiling | same |
| shadows | 2 splits, 60 m, 2K | 4 splits, 110 m, 4K | 4 splits, 150 m, 4K, soft | 4 splits, 220 m, 8K, PCSS |
| AO / GI | - | SSAO (half) | SSAO + SSIL | SSAO + SSIL + SDFGI |
| reflections | sky | sky | + SSR, car probe | + SSR full size |
| glow | - | yes | yes | yes |
| AA | MSAA 2x | MSAA 2x | TAA + MSAA 2x | TAA + MSAA 4x |
| view distance | x0.8 | x1 | x1.15 | x1.3 |

Compatibility ignores what it can't do (SSIL, SSR, SDFGI, TAA, PCSS) without errors.

## Lens 1: why it works and is good

- Most of "realistic" is light, not geometry: a real sky (clouds, a proper horizon) that
  also lights and reflects in everything, physically based materials, shadows with
  contact AO, a filmic tonemapper. Those are cheap on a GPU and need no new models.
- One shader for every surface keeps it small and consistent, and the vertex-colour
  "colour" mode means the stage builder's whole design (tracks, berms, snow, paint,
  rock) carries over untouched: no UVs to add to thousands of lines of mesh code.
- The material library (`world_materials.gd`) is shared: the new highway loop map just
  calls `asphalt()`, `concrete()` ... on meshes with metre UVs or none at all.
- Everything degrades: LOW is today's look on the new sky, Compatibility silently skips
  what it can't do, and the renderer can be switched without a command line.
- Download cost is small: ~9 MB of textures (WebP sources; ~20 MB VRAM-compressed in the
  pack), 0.1 MB of skies.

## Lens 2: what won't work, or isn't accounted for

- **Weak PCs.** Forward+ has a higher base cost than Compatibility on old Intel iGPUs,
  even with everything off. LOW + RENDER SCALE 70 % should hold 60 fps on a 2018 Intel
  UHD laptop, but that's a guess: **llvmpipe can't measure real frame rates** (a frame
  takes seconds on the CPU here). The RENDERER = COMPATIBILITY switch is the safety net.
- **Chromebooks**: the amd64 `.deb` is the same binary as the Linux build; only its
  launcher forces Compatibility (started from a terminal as `/opt/shotgun-rally/ShotgunRally`
  it would try Forward+, and fall back to OpenGL when there's no Vulkan). A Chromebook
  with working Vulkan (Venus) could run Forward+, but it's not worth the risk.
- **The art direction clashes.** The trees, houses, crowd, signs and mountains are
  low-poly flat-colour models. Realistic ground and light under cartoon cones is a mixed
  look; the trees are the biggest gap (they stay low-poly, vertex-coloured, slightly
  better lit). Real foliage (cards or scanned trees) is the next step, and a big one.
- **The car models are game rips** with uneven materials: the lamp finder works by
  names / colours / positions and will miss or misjudge some cars (it's conservative:
  better a lamp that doesn't glow than a door that does). Glass and chrome fixes only
  touch materials with clear names.
- **SDFGI** at rally speed can lag (its cascades scroll with the camera) and costs a lot;
  it's ULTRA only. SSR on rough roads adds little; it's for wet puddles, water, glass.
- **TAA** can ghost behind a fast car; it's HIGH / ULTRA only, and FSR2 isn't used.
- The HDRI skies are static (no time of day, no moving clouds); a golden HDRI has its
  sun 5 degrees up, so the golden sun is lifted to 14 degrees to keep the stages lit.
- The update pack (`ShotgunRally.pck`) is exported from the Linux x86_64 preset, so its
  VRAM-compressed textures are S3TC/BPTC only (true for the car textures already): an
  ARM Chromebook updating through the pack would need ETC2. Not new, but worth knowing.
- `project.godot` changes, so the updater's "base" changes: players get the
  download-page prompt once, not a silent pack update.

## Lens 3: is it worth it

- **Cost**: a few days of work, ~10 MB of download, more GPU on HIGH / ULTRA. Tests are
  headless and unaffected.
- **Compared with the targets**: Assetto Corsa's look is mostly its sky, tonemapping and
  the car shaders (clear coat, dynamic cubemap reflections); Forza adds photogrammetry
  scenery and dense foliage; BeamNG has the soft-body and terrain detail. This pass gets
  the sky / tonemapping / car shader / reflection part (the cheap, high-impact half);
  scenery density and foliage would take real assets (scanned trees, rocks, roadside
  clutter) and an LOD system, which is where most of those games' budgets go.
- **Biggest win for least work**, in order: the sky + tonemapping + shadows (an hour of
  tuning, transforms every frame), the road and ground textures (the road is what you
  look at), the car's reflections and clear coat, lamps. Trees next, if this is liked.
