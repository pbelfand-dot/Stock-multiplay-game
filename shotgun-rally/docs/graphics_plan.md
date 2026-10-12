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
6. **Lamps**: the head and tail lamp materials found by name ("led" only as a word: not
   "Recycled" or "untitled", which made every material of the ripped cars a lamp), existing
   glow and where they sit on the car (front / back quarter), given emission masked by their
   own texture: dim running lights by day, brake lights when braking, full at night
   (CarLook). A lamp material that reaches past the nose or the tail (both ends in one, bits
   of the cabin with it) is split by where its triangles are at load (the front 24 %, the
   back 24 %), so only the lamps glow and the tails glow red. Lamps the names don't give
   away (headlamps in the glass, lamps named like wheels, the generated bodies' tail blocks)
   come from the model's parts.json `"lamps"` hints (`[{kind, mat, box}]`, also in its
   tools/cars spec so a re-import keeps them). Each side's lamp is the cluster round the
   area-weighted middle of its lamp faces (a third brake light by the roof doesn't drag it
   off), worked out once per model. `tools/lamp_survey.gd` lists every model's lamps (text
   only: safe on the no-AI cars). The real lights are CarLamps' (see 9).
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
| speed blur | - | 6 taps | 10 taps | 10 taps |
| AA (in a stage) | MSAA 2x | FXAA | TAA | TAA |
| AA (the garage) | MSAA 2x | MSAA 2x | TAA + MSAA 2x | TAA + MSAA 4x |
| view distance | x0.8 | x1 | x1.15 | x1.3 |

Compatibility ignores what it can't do (SSIL, SSR, SDFGI, TAA, PCSS, card trees, the speed
blur) without errors, and its glow is off by day (its simpler glow blooms the road lines),
on at night (the lamps).

8. **Time of day** (`WorldMaterials.setup(parent, mood, hour)`, Settings > WORLD > TIME OF
   DAY through `Modes.with_time()` and the builders' `time_of_day`): an hour lights the world
   for that hour: the sun on its arc (up ~06:00, 60 degrees at 13:00, down ~19:30), the two
   nearest sky photos blended (night: a drawn sky with stars and a moon), the exposure, fog,
   colour grade and the sun's colour from a table of hours. `night_amount` (0 day .. 1
   night) fades the night pieces in through dusk and out at dawn: the cars' lamps, the
   beams (from 0.3), the street lamps (from 0.05, dimmer at dusk), lit windows. The mood
   then only says overcast or not; the builders' `mood` becomes the hour's (the game's night
   switch reads it), so a rally stage at 23:00 is a night stage.
9. **Night** (the touge, mostly; any map at a night hour):
   - **Street lamps** (`scripts/stage/street_lamps.gd`, made by `WorldMaterials.street_lights()`):
     the touge's posts (before every tight bend, no gap over ~120 m), the highway stage's,
     and the LAKESHORE LOOP's (the median posts on the viaducts, bridges and through the
     city, one head over each carriageway: ~700 lamps). Each: a lit sodium head, a glare
     sprite, a pool of light on the road, faked: on Forward+ with the lamps apart (the
     touge) a disc that multiplies what's under it (asphalt brightens as its colour allows,
     a white line more: like a real light), where pools overlap (the highway stage, the
     loop: 48 m apart, both carriageways) and on Compatibility an added one (multiplied twice
     over the road blows out to white; Compatibility can't brighten past white by
     multiplying). The four lamps nearest the player's car get real omni lights that fade
     in and out with distance (the car's paint, the guardrails and trees light up as they
     pass); where the pools multiply, not the road (`WorldMaterials.ROAD_LAYER`: it keeps its
     pool, no light counted twice). All batched: three MultiMeshes.
   - **The cars' lamps**: CarLook (emission on the lamp lenses, red tails, brake lights)
     and CarLamps (`scripts/vehicle/car_lamps.gd`): the headlight beams (two, one on each
     headlamp, on Forward+ MEDIUM+, yours casting one shadow on HIGH / ULTRA; one between the
     lenses on LOW and Compatibility), a red glow on the road behind yours, hazards. The light
     comes from the lamps themselves: their glowing lenses (and the bloom), and each beam
     starts on its own headlamp's lens, 2 cm out. CarLook finds where each side's light comes
     out: the lamp's middle as seen from in front, on its outermost face (the lens cover).
     The front of the lamp's box, where the beams used to start, was up to 34 cm in front of
     the lens on a lamp swept back round the wing (10 cm on the median model). A beam
     never lights its own car (its cull and shadow-caster masks leave the car's layer out): a
     spot light a few cm from its own bumper, grille and lens lit them white-hot, the bloom
     made a ball of it and the beam seemed to come out of that ball (worst with the single
     beam everyone else had, in the middle of the nose, inside the grille). And each beam's
     light runs on down the road from the lamp: a wide cone (50 degrees), aimed 3 degrees
     under the level, gathered toward its middle and slow to fall off with distance, so a flat
     road is lit from ~0.75 m out of the lamp and still has a quarter of its brightest at
     10 m, a tenth at 20 m. The old cone (34 degrees, 4 down) left the first 0.75 m dark, lit
     1-3 m ahead brightest by far and had a tenth of that at 10 m: a round pool of light on
     the road on its own just in front of the car, the brightest thing in view. (A projector's
     low-beam pattern would be better still, but Godot only uses a light's projector with its
     shadows on: a shadow pass for every beam.) Your car's meshes
     are on CAR_LAYER, any other car CarLamps fits on OTHER_LAYER: your beams light the cars
     ahead of you and theirs light yours. Only a body whose lamps are painted into its
     texture (the shared rally body: parts.json `"lamp_boxes"`) gets a soft glow laid flat on
     each lamp, facing out; where no lamp is known at all the beams start at the body's front
     and nothing is added. The game fits them at night, CarLook at dusk or with CAR LIGHTS
     ALWAYS; OFF leaves only your own beam at night. The other drivers' and Track Mode's AI
     cars' beams are on for the two nearest you only. `tools/lamp_shots.gd` takes night
     pictures of them all (yours, another driver's, the stray car, the traffic) and times the
     beams; `tools/lamp_survey.gd` lists each model's lamps and lenses.
   - **The traffic** (cut up): its lamps glow (CarLook.glow_model) and at night each car
     throws a faked pool of headlight on the road ahead and red behind (one additive mesh,
     200 m) instead of real lights (dozens of cars). It starts at the lamps, a lobe out of
     each headlamp, brightest just ahead of the car and gone by 14 m (it was a round pool
     centred 9 m out, nearly dark at the bumper: a ball of light on the road ahead).
   - **The loop's city**: the towers' facade shader lights ~40 % of the windows at night
     (warm and cold white); the bridge towers' red beacons; no shadows from the moon.
   - A dash glow in the cockpit (the game), the stray local car's lamps (CarLamps + glow).
10. **Speed blur** (`scripts/render/speed_blur.gd`, a compositor pass, Forward+ MEDIUM+):
   the world smears along its motion vectors plus a pull toward where the camera's heading,
   stronger at the screen's edges, from ~90 km/h, all of it by ~220; the car and cockpit
   (no motion relative to the camera) stay sharp. The motion vectors and depth read as
   empty under MSAA (checked on llvmpipe; the resolve isn't filled in for a compositor
   effect), so while the blur is on the stage drops MSAA for FXAA / TAA (the table).

11. **The look pass** (October 2026: an overall look at every screen and world, the cheapest fixes
    for what looked worst, nothing that costs frames on the presets the owner plays):
   - **The ground isn't a lawn**: the stages' grass was one pale, even green from the road to the
     trees (the vertex colours set the colour; the photo's own showed at 20 %). The terrain shader
     now lays big soft patches over it (two value noises a pixel, ~25 m and ~6 m: no textures, no
     branch), where up to 62 % of the photo's colour shows (moss, dry grass, needles, leaves; at
     80 % the alpine slopes went khaki) and where it's lighter or darker (x0.66-1.1): MEDIUM and
     up, LOW keeps its flat colours. The gravel road's colours a little darker (x0.82: it was
     near white in the sun). (A branch round the two noises crashed llvmpipe outright; written
     without one.)
   - **Puddles**: a mud puddle was a hard-edged 9-sided polygon, a sheet of navy blue from afar.
     Now 18 sides with a lobed outline of its own, a ragged edge frayed by noise from the
     mesh's vertex alpha (1 in the middle, 0 at the rim), a rim of wet mud, then muddy water.
   - **Street lamps at night**: the glare round each head was a straight ramp out to its edge,
     which read as a hard orange disc (a moon behind the trees); now a hot core and a halo that
     falls off softly. (The heads themselves still burn out white; dimming them was tried and
     not kept: the pictures couldn't settle it.)
   - **CINDER RIDGE's garages**: the twenty open doors were flat black slabs. Each is now drawn
     by the camera's ray (interior mapping, one quad, a few dozen instructions a pixel): a
     grey room with the team's colour in a band round it, cabinets, a floor and strip lights,
     darker toward the back, lit from inside (it glows a little at night). The circuit's
     concrete walls are painted light grey (the bare photo read as tan sandstone).
   - **Cut up's hills**: the LAKESHORE LOOP's trees were the last low-poly cones in the game.
     On MEDIUM and up they're the library's: two tall cedars for the hills' sugi forest and two
     broadleaves for the lakes (by the loop's seed), at the cones' spots; LOD1 near the road and
     the camera (shadows on HIGH and ULTRA), the far card everywhere else (~2 s more at load).
     Sparser to look at than the solid cones (the cards are see-through), but no toy trees.
   - **Guardrails**: the mountain stages' armco, the touge's white guardrail and the loop's were
     a flat band, a grey slab; the face to the road is now a W in section (four flat-shaded
     strips, two ridges 3 cm proud), so it reads as pressed steel.
   - **Tyre marks** soft-edged with the tread's grooves faint in them (a 64 x 1 profile texture),
     overlapping less at the joints (they were hard strips, tape on the road, darker every 30 cm).
   - **The menus**: the home screen's item lines were clipped after being sized (a Label sized
     while it doesn't clip grows to its text), so the long ones ran off their plates; the help
     line along the bottom and the status line got a dark outline (the garage floor's light
     reflections washed them out).
   - **Performance: RENDER SCALE AUTO** keeps the 3D within a pixel budget per level (LOW
     1920 x 1080, MEDIUM 2304 x 1296, HIGH 2560 x 1440, ULTRA 2688 x 1512 worth of pixels),
     FSR scaling it up past that, re-applied when the window changes size. A MacBook's Retina
     screen (2880 x 1800 up to 3456 x 2234) drew the 3D at every one of its pixels, ~2.7x a
     1080p screen's: at 3024 x 1964 it's now drawn at 79 % on HIGH, 83 % on ULTRA (checked:
     a 1920 x 1080 window goes back to 100 %, a RENDER SCALE picked by hand is kept). A 1080p or
     1440p screen is under every budget, and the movie maker (--write-movie) always draws every
     pixel: unchanged.
   - **Performance: the near trees' shadows** come from their lighter version (LOD1, ~1.9k
     triangles) at every level, as MEDIUM already did, not the full tree (LOD0, ~19k) on HIGH and
     ULTRA. On a forest stage (stage_perf, seed 5, HIGH) the shadow passes went from 9.2 / 11.2 /
     7.7 million triangles a frame to 4.7 / 7.1 / 4.5 at three places; side by side the shadows
     look the same.
   - Looked at and left alone: the day's exposure against the sky (lowering it and lifting the
     sky changed little once the grass was fixed, and would have changed every shot of the
     owner's video); a blue-white tree or two standing out of the dark forest on the night
     touge (moonlit leaves; darkening the far cards at night didn't change it, so the cause
     wasn't found); the paddock's plain white team
     garages (the prop's own look); the far mountains' flat silhouettes (shaded darker toward
     their feet they looked no different through the haze); the pause menu's plain buttons
     (no picture of it could be had: the render queue); ULTRA's SDFGI (its GI at half
     resolution would save the most on a laptop, but ULTRA's pictures pass this machine's
     memory cap, so it couldn't be looked at).

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
- The night is mostly faked where it's cheap and real where you look: hundreds of street
  lamps are three batched MultiMeshes (a lit head, a glare, a pool that brightens the road
  as a lamp would), with only the four nearest the car real lights; the traffic's
  headlights on the road are one additive mesh a car. The player's car gets real beams,
  the paint catches the street lamps' real lights as it passes them. One system for every
  map: the touge, the highway stage and the loop all call `WorldMaterials.street_lights()`.
- The time of day is one table of hours blended (sun, sky photos, exposure, fog, grade),
  so any hour is lit, dusk and dawn included, and every night piece fades with
  `night_amount` instead of switching on at a mood.

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

- **Night on weak PCs and Chromebooks**: at night there are ~6-9 real lights (4 street-lamp
  omnis following the car, your two beams (one shadowed on HIGH+), the red tail glow,
  online the two nearest drivers' beams). Forward+ handles that easily; Compatibility pays
  per light per object, so a Chromebook at night costs more than by day (the work branch's
  night had the same count; CAR LIGHTS OFF drops everyone's beams but your own).
  Compatibility's glow is on at night only, untested on a real Chromebook GPU.
- **The speed blur and MSAA**: the blur's inputs read as empty under MSAA (seen on
  llvmpipe; maybe not on every GPU, but there's no way to tell here), so in a stage the
  blur levels use FXAA / TAA: MEDIUM's edges are softer than with MSAA 2x (and cheaper);
  the garage keeps MSAA. TAA can still ghost behind the car.
- **The faked pools** are flat discs: on a crest or a steep camber their edge can sink
  into the road (the loop's lie on the road's slope; the touge's on its own level), and a
  pool doesn't light the car or the guardrail (the four real lights do that near the car;
  they leave the road to the pools, so the road under a lamp looks the same near or far).
- **The loop's tunnels** were on render layer 2, which the driver's seat camera leaves out
  (the helmet's): from the cockpit the tunnels' walls and lamps vanished. Now layer 14.
- **The time of day** is static in a run (no clock running), the sky photos are fixed
  (the clouds don't move, the golden photo is turned to the sun's direction at dusk and
  dawn alike), and 18:00-20:00 blends two photos, which shows as a slightly soft sky.
- **The loop by night** has no lamps on its embankments and in the hills (lit only by the
  cars and the city's glow), the towers' windows are a pattern (no interiors), the loop's
  trees stay low-poly (no card trees there yet).
- **Lamp finding** on the rips is still heuristic; a car whose lamps weren't found gets
  sprites at its body's corners, which can sit a little off its real lamps.

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
- **The night and the time of day** cost no download (all code and shaders) and a few real
  lights' worth of GPU at night, which Forward+ hardly notices; against Assetto Corsa (whose night needs
  mods: real headlights, emissive lamps, baked street lighting) this is the same recipe
  (emissive + bloom + a few real lights + faked pools); Forza Horizon's night adds real
  shadows from every lamp and wet roads, which would mean many shadowed lights: not for
  this game's weak-PC promise.
