# The graphics pass: from flat colours to an Assetto Corsa / Forza look

The owner asked for the realistic look of Assetto Corsa / Forza instead of the flat-colour
"art of rally" style: Forward+ on the desktop builds (Compatibility stays on the web and
Chromebook builds), a lighting pass, real materials (car paint, glass, chrome, textured
roads and ground), glowing lamps ready for night maps, and a graphics quality setting so
weak PCs still run it. This is the plan (with what was checked while building it).

## What gets built (in order of visual win per effort)

1. **The renderer.** `project.godot`: `rendering_method="forward_plus"`, with `.web` and
   `.mobile` overrides to `gl_compatibility`. The Chromebook `.deb`s are the Linux exports
   (the amd64 one is the very same binary), so their launcher passes `--rendering-method
   gl_compatibility` (`tools/make_deb.sh`, the menu entry and `/usr/bin/shotgun-rally`), and
   the game itself writes the Compatibility choice for its next start when it finds it's
   on a Chromebook (Crostini's `/dev/.cros_milestone`), which also covers the updater's
   restart. A machine without Vulkan falls back to OpenGL by itself
   (`rendering/rendering_device/fallback_to_opengl3`, on by default; checked here with no
   Vulkan driver: "switching to OpenGL 3"). Settings gets RENDERER (FORWARD+ /
   COMPATIBILITY) written to `user://renderer.cfg`, which the engine reads at start through
   `application/config/project_settings_override` (checked: it switches
   `RenderingServer.get_current_rendering_method()`), so an old laptop can drop to the
   light renderer without a command line. The code always asks the running renderer, not
   the setting (a command line can differ).
2. **Sky and light** (`scripts/render/world_materials.gd`: `setup()`, `environment(mood)`,
   `sun(mood)`). A photographed sky per mood (CC0 Poly Haven "pure sky" HDRIs: partly
   cloudy midday, sunset, overcast), stored log-encoded in an 8-bit 2048 x 569 WebP (30-45
   KB each instead of 5 MB of HDR; 0.5-0.75 MB imported) and drawn by a sky shader that
   turns it so its sun sits where the DirectionalLight is, draws the sun disc, and fades
   below the horizon into the ground's colour (no blue light from under the road). The sky
   lights the scene (ambient and reflections), the fog takes its colour from the sky
   (aerial perspective on Forward+), AgX tonemapping, a gentle colour grade per mood (a
   generated 3D LUT). Shadows: 4 cascades tuned for driving (a sharp first split of ~12 m
   round the car, out to 110-220 m by level), soft (PCSS) on Ultra. SSAO from Medium, SSIL
   + SSR from High, SDFGI on Ultra, glow from Medium. A night mood (`--mood=night`) exists
   for the lamps and for night maps later.
3. **Ground and road materials**, one shader for all (`world_materials.gd`): world-space
   projection (top-down, triplanar on walls / banks and everything on HIGH+, no UVs needed,
   works on the stage builder's meshes and anyone's; or the mesh's metre UVs), the texture's
   albedo + roughness + normal map, mixed with itself at another scale against tiling (HIGH
   +). The stage's vertex colours keep their meaning: in "colour" mode the vertex colour is
   the colour (its brightness; part of the hue comes from the photo) and the texture adds
   its detail, so the wheel tracks, berms, paint lines, snow patches and rock on the banks
   all stay where they were; in "tint" mode (the default, for other meshes) the vertex
   colour tints the texture. The ground picks grass / dirt / rock / snow by its vertex
   colour. Ground and road get smooth normals (MEDIUM+). Textures: 7 CC0 Poly Haven scans
   (asphalt, gravel, grass, mud, rock, concrete, snow), 1K (512 for the minor ones), Basis
   Universal like the car textures (one file transcoded on load for any GPU, so the
   update pack works on ARM too): 11.6 MB imported, skies included.
4. **Trees** (`scripts/render/foliage.gd`, HIGH / ULTRA): the near forest (out to ~190 m)
   becomes trees of cards: a trunk and whorls of crossed cards showing a photographed fir
   sprig (the twig atlas of Poly Haven's CC0 `fir_tree_01`, 0.5 MB), ~400 triangles a
   tree; the low-poly cones are kept beyond that and on LOW / MEDIUM.
5. **Car materials** (`scripts/render/car_look.gd`, called once from `rally_car.gd`'s
   `_build_own_model()`): the livery paint gets a sharper clear coat (the Higgsfield body a
   clear coat at all); window glass and chrome get proper gloss; a reflection probe rides
   over the roof on HIGH / ULTRA so the paint reflects the trees and the road, not just the
   sky; the mirror's camera gets the world's light without the costly effects.
6. **Lamps**: the head and tail lamp materials found by name, existing glow and where they
   sit on the car (front / back quarter), given emission masked by their own texture: dim
   running lights by day, brake lights when braking, full at night; real lights (two spot
   headlights, two small red omni lights) at night or when Settings says so.
7. **Settings: GRAPHICS** (`scripts/ui/graphics_settings.gd`, two lines in
   `settings_panel.gd`): QUALITY LOW / MEDIUM / HIGH / ULTRA (first run: picked from the GPU:
   discrete -> HIGH, integrated -> MEDIUM, Compatibility / software -> LOW), RENDER SCALE,
   CAR LIGHTS, RENDERER. Applied live to the viewport and environment; textures and trees
   on the next stage.

| | LOW | MEDIUM | HIGH | ULTRA |
|---|---|---|---|---|
| textures | flat vertex colours (today's look) | albedo + normal + roughness, one projection | + triplanar, anti-tiling | same |
| trees | low-poly | low-poly, textured | cards near, low-poly far | same |
| shadows | 2 splits, 60 m, 2K | 4 splits, 110 m, 4K | 4 splits, 150 m, 4K, soft | 4 splits, 220 m, 8K, PCSS |
| AO / GI | - | SSAO (half) | SSAO + SSIL | SSAO + SSIL + SDFGI |
| reflections | sky | sky | + SSR, car probe | + SSR full size |
| glow | - | yes | yes | yes |
| AA | MSAA 2x | MSAA 2x | TAA + MSAA 2x | TAA + MSAA 4x |
| view distance | x0.8 | x1 | x1.15 | x1.3 |

Compatibility ignores what it can't do (SSIL, SSR, SDFGI, TAA, PCSS, card trees) without
errors, and its glow is off (its simpler glow blooms the road lines).

## Lens 1: why it works and is good

- Most of "realistic" is light, not geometry: a real sky (clouds, a proper horizon) that
  also lights and reflects in everything, physically based materials, shadows with
  contact AO, a filmic tonemapper. Those are cheap on a GPU and need no new models.
- One shader for every surface keeps it small and consistent, and the vertex-colour
  "colour" mode means the stage builder's whole design (tracks, berms, snow, paint,
  rock) carries over untouched: no UVs to add to thousands of lines of mesh code.
- The material library (`world_materials.gd`) is shared: the new highway loop map just
  calls `asphalt()`, `concrete()` ... on meshes with metre UVs or none at all.
- Everything degrades: LOW is today's look under the new sky, Compatibility silently skips
  what it can't do, and the renderer can be switched without a command line.
- Download cost is small: 12 MB imported (textures, skies, the twig atlas).

## Lens 2: what won't work, or isn't accounted for

- **Weak PCs.** Forward+ has a higher base cost than Compatibility on old Intel iGPUs,
  even with everything off. LOW + RENDER SCALE 70 % should hold 60 fps on a 2018 Intel
  UHD laptop, but that's a guess: **llvmpipe can't measure real frame rates** (a frame
  takes seconds on the CPU here). The RENDERER = COMPATIBILITY switch is the safety net.
- **Chromebooks**: a Chromebook with working Vulkan (Venus) could run Forward+, but most
  can't, and a software Vulkan would be a slideshow: Compatibility it is.
- **The art direction clashes.** The houses, crowd, signs, ferns and mountains stay
  low-poly flat-colour models; under realistic light and ground they read as stylised.
  The card trees fix the biggest offender on HIGH / ULTRA only.
- **The car models are game rips** with uneven materials: the lamp finder works by names /
  colours / positions and will miss or misjudge some cars (it's conservative: better a
  lamp that doesn't glow than a door that does). Glass and chrome fixes only touch
  materials with clear names.
- **SDFGI** at rally speed can lag (its cascades scroll with the camera) and costs a lot;
  ULTRA only. SSR on rough roads adds little; it's for puddles, water, glass and paint.
- **TAA** can ghost behind a fast car; HIGH / ULTRA only. FSR2 isn't used.
- The HDRI skies are static (no time of day, no moving clouds); the golden HDRI has its
  sun 5 degrees up, so the golden sun is lifted to 14 degrees to keep the stages lit.
- Compatibility draws the photographed sky deeper blue than Forward+ (not tracked down);
  it's a plausible sky, just more saturated.
- `project.godot` changes, so the updater's "base" changes: players get the download-page
  prompt once, not a silent pack update.

## Lens 3: is it worth it

- **Cost**: a few days of work, ~12 MB of download, more GPU on HIGH / ULTRA. Tests are
  headless and unaffected (the render code skips itself without a screen).
- **Compared with the targets**: Assetto Corsa's look is mostly its sky, tonemapping, the
  car shaders (clear coat, a dynamic cubemap) and cross-quad trees; Forza adds
  photogrammetry scenery and dense foliage; BeamNG soft bodies and terrain detail. This
  pass gets the sky / tonemapping / car shader / reflection / card-tree part (the cheap,
  high-impact half); scenery density (rocks, roadside clutter, grass blades, real houses)
  would take real assets and an LOD system, which is where most of those games' budgets go.
- **Biggest win for least work**, in order: the sky + tonemapping + shadows, the road and
  ground textures (the road is what you look at), the trees, the car's reflections and
  clear coat, the lamps.
