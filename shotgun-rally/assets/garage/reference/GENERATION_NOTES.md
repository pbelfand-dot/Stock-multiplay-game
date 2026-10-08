# Garage reference views: generation notes

Generated 2026-10-08 with Higgsfield (the owner's account, authorised for this task).
Higgsfield credits: 602.65 before step 1, 564.67 after steps 1 and 2 were submitted (see the totals at the end).

## Naming / orientation convention

The four views look out from inside the same room:

| File | Camera | Looks at |
|---|---|---|
| `garage_front.png` | near the back wall, eye level ~1.5 m | the front wall (wide closed sectional roll-up door with an LED frame) |
| `garage_rear.png` | just inside the roll-up door, eye level | the back wall (workbench/tool wall framed by LED strips, personnel door, photo) |
| `garage_left.png` | against the right wall, eye level | the LEFT wall (helmet shelf + bucket seat, two tyre racks, cabinet run); back of the room at frame left, door at frame right |
| `garage_right.png` | against the left wall, eye level | the RIGHT wall (two-post lift, tool chest, detailing shelf + hose reel); door at frame left, back of the room at frame right |

"Left" and "right" are as seen by someone standing in the room facing the roll-up door.

## Models (checked against the unfiltered `models_explore` list, 2026-10-08)

- `soul_location` (Higgsfield Soul Location, "Environment and location generation"): no parameters
  besides aspect ratio, **no reference-image input, no seed**. Output 2048x1152 PNG at 16:9. 0.12 credits per image.
- `3d_jutsu_angles` (3D Jutsu Angles, "powered by Seedream 5.0 Pro"): takes `image_references`,
  `resolution` 1k/1.5k/2k, 16:9 supported. Output 2720x1536 PNG at 2k. 2.5 credits per image.
  Higgsfield's own `/3d-jutsu/references/location-new-angles` guidance was followed: since Soul
  Location cannot be conditioned, the approved front image was used as the identity reference
  ("master") and a 3D blockout render of the same room supplied the new camera and layout.

## Step 1a: front view (master), Soul Location

Model `soul_location`, `aspect_ratio` 16:9, `count` 4 (one request, 4 variants). Exact prompt:

```
A premium contemporary performance-car garage designed as the main menu environment for a realistic racing game. Large enough for one hero vehicle with generous camera-orbit clearance. Dark charcoal polished concrete floor with subtle realistic reflections, graphite walls, black steel beams, restrained architectural LED strips, soft overhead area lighting, believable ray-traced light falloff, tire racks, tool cabinets, hydraulic lift, workbench, motorsport equipment, small detailing supplies, tasteful Japanese and European street-racing influences, subtle touge and expressway culture, realistic ventilation, roll-up garage door, organized functional layout, high-end automotive photography atmosphere, physically plausible dimensions, detailed but not cluttered, no people, no visible brand logos, no text, no distorted geometry. All four images must represent precisely the same garage.

VIEW 1 of 4 - FRONT-FACING: wide interior photograph taken from just in front of the back wall at eye level (1.5 m), looking straight toward the front wall, symmetrical one-point perspective, 24 mm lens, whole room visible. Room about 10 m wide, 12 m deep, 5 m high, rectangular, no windows. Front wall: one wide closed dark-grey roll-up sectional garage door centred, with slim vertical warm-white LED strips on both sides. Left wall: tall black steel tire racks with stacked performance tires and spare wheels near the front, then a row of black tool cabinets with a workbench top. Right wall: an empty two-post hydraulic lift with folded arms, a rolling tool chest and a small detailing cart with bottles and microfibre towels. Ceiling: exposed black steel I-beams running left to right, linear LED fixtures between them, a large rectangular soft light panel above the centre, ventilation ducts. The centre of the floor is a completely empty, unobstructed display area of polished concrete: no car, no objects in the middle.
```

| Job id | Result | Verdict |
|---|---|---|
| `f1845c33-27fc-412f-b273-4b2d61bb70ca` | symmetric room, LED-framed sectional door, 2 tyre racks + cabinet run left, two-post lift + tool chest right, trusses/ducts/linear LEDs, suspended pale light box, empty centre | **APPROVED -> `garage_front.png`** (master) |
| `406f3c3a-995d-4fe8-b771-e16b9160c899` | stray patio umbrella, open bin of bags in the foreground, odd floor step at the bottom, mesh windows | rejected (nonsense props, impossible floor step) |
| `a8bec5a4-9fd8-40a2-9cca-329abf1d81ac` | good photographic look but long narrow tunnel-like room, lift arms scattered on the floor, half-cut cart at frame edge | rejected (proportions, malformed lift) |
| `0ad5cf00-27b3-46f8-b612-485279862280` | extreme low angle, oversized room (~20 m wide) with tiny props, huge ceiling panel | rejected (scale, sparse) |

Rejected images are kept outside the repo in `/root/srwork/garage/rejected/`.

## Step 1b: blockout for the other three cameras (local, no credits)

`/root/srwork/garage/tools/blockout.py` (Blender 4.0.2, EEVEE under xvfb) builds a primitive
blockout fitted to the master: room 10 m (X) x 14 m (Y) x 4.8 m, door 7.6 x 3.0 m with LED frame,
tyre racks / cabinet run on the left wall, lift / tool chest on the right wall, trusses at 3.7-4.5 m,
light box 4.4 x 5 m with its underside at 3.6 m, plus the hidden areas that the master does not show
(back wall: LED-framed workbench + pegboard + helmet shelf + vent grille, framed photo, personnel
door; back half of the left wall: helmet shelf + bucket seat; back half of the right wall: detailing
cabinet + bottle shelf + hose reel). Cameras: rear (0, 6.3, 1.5) looking -Y 24 mm; left (4.3, 0.5,
1.5) looking -X 20 mm; right (-4.3, 0.5, 1.5) looking +X 20 mm. The renders
(`/root/srwork/garage/blockout/blockout_{rear,left,right}.png`) were uploaded as media
`e812d821-3538-4403-916e-ad9e393f6203` (rear), `1f208d86-bcad-4a9d-acfd-192b8b29aec9` (left),
`ae1a86f0-70a4-429e-bb67-973b4729f739` (right).

## Step 1c: rear / left / right views, 3D Jutsu Angles (Seedream 5.0 Pro)

Model `3d_jutsu_angles`, `aspect_ratio` 16:9, `resolution` 2k, `medias` = [master job
`f1845c33-...` (Image 1, identity/materials/lighting), blockout render (Image 2, camera/layout)],
role `image_references`. No seed parameter exists for this model. All three were approved on the
first attempt (no regenerations).

| View | Job id | Blockout media | Verdict |
|---|---|---|---|
| rear | `98cf4a10-4ab3-4bad-8d07-41b1f71bae1a` | `e812d821-...` | **APPROVED -> `garage_rear.png`** |
| left | `5099573d-c0a6-4956-94a3-61faec7730b2` | `1f208d86-...` | **APPROVED -> `garage_left.png`** |
| right | `e2607a94-4204-458b-ad3c-88028a6689a7` | `ae1a86f0-...` | **APPROVED -> `garage_right.png`** |

Consistency check (by eye, all four side by side): same graphite walls, charcoal polished concrete,
black steel trusses with linear LEDs and spiral ducts, the same pale-concrete suspended light box,
the same LED-framed sectional door (seen edge-on at the correct end of both side views), the same
two caster tyre racks with two silver multi-spoke wheels at the bottom of the first rack, the same
cabinet run with wood top / backsplash / charger, the same black two-post lift with red pads and a
silver cylinder, the same tool chest with amber bottles and a blue towel. Hidden-area items are
consistent between the views that share them (helmet shelf + bucket seat: rear and left;
detailing shelf + hose reel + low cabinet: rear and right). Known small deviations: the master is
slightly softer/hazier (different model) and 2048x1152 vs 2720x1536 for the others; the master's
tyre sidewalls show a thin red stripe that the side view does not resolve; the bucket seat in the
rear view carries a tiny unreadable orange tag.

The shared core of the three prompts is the owner's brief (verbatim). Exact prompts:

### rear (98cf4a10)

```
Image 1 is the approved photograph of the garage (front-facing view toward the closed roll-up door). Image 2 is a grey 3D blockout of the SAME garage rendered from the new camera. Use Image 2 only for camera position, perspective, room shape and the placement, size and facing of every object. Use Image 1 for all materials, colours, lighting mood, realism and object design. Output a photorealistic photograph of the real room, not a render of blocks. Proxy key for Image 2: grey cylinders = black tyres on the steel tire rack, white spheres = white racing helmets, small orange cylinders = amber detailing bottles, teal disc = blue compressed-air hose reel, dark box on a low stand = carbon-fibre racing bucket seat, dark rectangle on the back wall = framed photograph, grey rectangle high on the back wall = ventilation grille, white glowing lines = slim warm-white LED strips, big white ceiling rectangle = underside of the suspended light box.

<owner's brief, verbatim>

VIEW 2 of 4 - REAR-FACING: the camera stands just inside the closed roll-up door at eye level (1.5 m), turned 180 degrees from Image 1, looking straight at the back wall; symmetrical one-point perspective, 24 mm lens, horizon at mid-frame. The roll-up door is behind the camera and not visible. Back wall centre: a long black steel workbench with drawers and a dark wood top, a dark pegboard tool wall above it with neatly hung chrome hand tools, a narrow black shelf above holding two white racing helmets, a slim ventilation grille high above; the workbench alcove is outlined by the same slim warm-white LED strip used around the garage door in Image 1 (two vertical strips from the floor and one across the top). Back wall, frame right: one framed black-and-white photograph of a winding mountain pass road at night. Back wall, frame left near the corner: a plain black steel personnel door. Frame-left side wall: a low black cabinet, a wall shelf with a neat row of amber detailing bottles and a blue air-hose reel above. Frame-right side wall: a black wall shelf with two white helmets and a carbon racing bucket seat on a low stand, and at the far right edge the end of the same black steel tire rack with tyres from Image 1. Ceiling identical to Image 1 seen from the other end: black steel trusses running front to back on both sides with linear LED fixtures, spiral ventilation ducts along both side walls, black I-beams across, and the same large suspended pale-grey concrete light box over the centre with a softly glowing underside. Floor: the same dark charcoal polished concrete with soft reflections of the LED strips; the centre of the floor is completely empty. Lighting and palette identical to Image 1: low-key and moody, main light is the soft downward glow of the central light box plus the slim LED strips, graphite walls falling off into shadow, neutral-warm white balance. No car, no people, no text, no logos, no neon.
```

### left (5099573d)

```
Image 1 is the approved photograph of the garage (front-facing view toward the closed roll-up door). Image 2 is a grey 3D blockout of the SAME garage rendered from the new camera. Use Image 2 only for camera position, perspective, room shape and the placement, size and facing of every object. Use Image 1 for all materials, colours, lighting mood, realism and object design. Output a photorealistic photograph of the real room, not a render of blocks. Proxy key for Image 2: grey cylinders = rows of black performance tyres standing upright on the black steel tire racks, two silver discs at the bottom of the first rack = two silver multi-spoke spare wheels, white spheres = white racing helmets, dark box on a low stand = carbon-fibre racing bucket seat, small dark box on the bench = black battery charger, white glowing lines = slim warm-white LED strips, big white ceiling shape = underside of the suspended light box.

<owner's brief, verbatim>

VIEW 3 of 4 - LEFT SIDE: the camera stands against the garage's right wall at eye level (1.5 m), turned 90 degrees left from Image 1, looking straight across the empty centre of the floor at the LEFT wall; 20 mm lens, wall parallel to the frame, horizon at mid-frame. The back of the garage is at frame left and the roll-up door end is at frame right. Visible along the left wall from frame left to frame right: the dark back corner; a black wall shelf with two white racing helmets above a carbon racing bucket seat on a low stand; the same two tall black steel tire racks on casters from Image 1, now seen face-on, four tiers each with rows of black performance tyres standing upright and two silver multi-spoke wheels at the bottom of the first rack; then the same long black tool-cabinet run with drawers, a dark wood workbench top, a dark backsplash panel behind it and a small black charger on the bench; at the far right edge the front corner where the garage door's slim warm-white LED frame is seen edge-on. Ceiling identical to Image 1: black steel truss running left to right across the upper frame with a row of linear LED fixtures, a spiral ventilation duct along the top of the wall, black I-beams, and the edge of the large suspended pale-grey concrete light box overhead with its softly glowing underside. Floor: the same dark charcoal polished concrete with soft reflections; the centre of the floor between camera and wall is completely empty. Lighting and palette identical to Image 1: low-key and moody, main light is the soft downward glow of the central light box plus the LED strips, graphite walls falling off into shadow, neutral-warm white balance. No car, no people, no text, no logos, no neon.
```

### right (e2607a94)

```
Image 1 is the approved photograph of the garage (front-facing view toward the closed roll-up door). Image 2 is a grey 3D blockout of the SAME garage rendered from the new camera. Use Image 2 only for camera position, perspective, room shape and the placement, size and facing of every object. Use Image 1 for all materials, colours, lighting mood, realism and object design. Output a photorealistic photograph of the real room, not a render of blocks. Proxy key for Image 2: the black frame with two posts and an overhead bar = the black two-post hydraulic lift from Image 1 with red arm pads and a silver hydraulic cylinder, black box with orange cylinders and a blue strip on top = the black rolling tool chest with amber detailing bottles and a blue microfibre towel, teal disc = blue compressed-air hose reel, small orange cylinders on the shelf = amber detailing bottles, white glowing lines = slim warm-white LED strips, big white ceiling shape = underside of the suspended light box.

<owner's brief, verbatim>

VIEW 4 of 4 - RIGHT SIDE: the camera stands against the garage's left wall at eye level (1.5 m), turned 90 degrees right from Image 1, looking straight across the empty centre of the floor at the RIGHT wall; 20 mm lens, wall parallel to the frame, horizon at mid-frame. The roll-up door end is at frame left and the back of the garage is at frame right. Visible along the right wall from frame left to frame right: at the far left edge the front corner where the garage door's slim warm-white LED frame is seen edge-on; the same empty black two-post hydraulic lift from Image 1, now seen face-on against the wall, two black posts joined by an overhead crossbar, folded lift arms with red pads, a silver hydraulic cylinder on one post; next to it the same black rolling tool chest on casters with amber detailing bottles and a blue microfibre towel on top; further right a low black cabinet with a wall shelf holding a neat row of amber detailing bottles and a blue air-hose reel above; then the dark back corner at the right edge. Ceiling identical to Image 1: black steel truss running left to right across the upper frame with a row of linear LED fixtures, a spiral ventilation duct along the top of the wall, black I-beams, and the edge of the large suspended pale-grey concrete light box overhead with its softly glowing underside. Floor: the same dark charcoal polished concrete with soft reflections; the centre of the floor between camera and wall is completely empty. Lighting and palette identical to Image 1: low-key and moody, main light is the soft downward glow of the central light box plus the LED strips, graphite walls falling off into shadow, neutral-warm white balance. No car, no people, no text, no logos, no neon.
```

`<owner's brief, verbatim>` stands for the paragraph that starts "A premium contemporary
performance-car garage..." exactly as in the Step 1a prompt above (it was sent in full each time).

## Step 2: multi-image to 3D

Model `multi_image_to_3d` (provider Meshy; "1-4 images of the same subject to 3D GLB mesh"). The
other multiview-capable 3D models in the catalogue were not used: `meshy_multi_image_to_3d`
(an alias of the same Meshy model), `tripo_h3_1_multiview_to_3d`, and `hunyuan3d_v3_image_to_3d`.

- Job id: `f872e59c-c5dd-428f-8f2a-8a59f11cbb1e`; cost 30 credits.
- Images, role `image`, in this order: front `f1845c33-27fc-412f-b273-4b2d61bb70ca`, rear
  `98cf4a10-4ab3-4bad-8d07-41b1f71bae1a`, left `5099573d-c0a6-4956-94a3-61faec7730b2`, right
  `e2607a94-4204-458b-ad3c-88028a6689a7` (the four approved PNGs above).
- Parameters: `should_texture: true`, `enable_pbr: true`, `should_remesh: true`, `topology: "triangle"`,
  `target_polycount: 300000`, `symmetry_mode: "off"`, rigging/animation off. No prompt: this model
  ignores prompts, and `texture_prompt` was deliberately left unset so the texture comes only from
  the images. The model has an optional `seed` parameter; none was set.
- Output: one GLB with embedded textures, downloaded unmodified as `garage_hf.glb`
  (29,241,292 bytes, sha256 `b5fd46c74baea115472b4053e355f47ce8c1d1d9fb5a2f723a6d81442c256651`).
  The four embedded images were extracted byte-for-byte
  (`garage_hf_basecolor.jpg`, `garage_hf_metallic_roughness.jpg`, `garage_hf_normal.png`,
  `garage_hf_emissive.jpg`, each 2048x2048).

## Step 3: assessment summary (details in the hand-off report)

- 1 mesh, 1 material (double-sided, PBR + emissive), 291,185 triangles, 326,268 vertices (144,443 after welding).
- Raw bounding box 1.90 x 1.91 x 0.64 units (glTF Y-up). Calibrated by cabinet height (~0.9 m) at about
  6.5 m per unit, that gives a 12.3 x 12.4 x 4.2 m room. The reference room is about 10 x 14 m, so the footprint came out square.
- No floor (4 of 625 grid samples hit anything near floor level). The roof is open: only trusses, ducts and the light
  box, so 47% of upward rays escape. The back wall is missing from the floor to about 1.9 m across its full
  width, so nothing from the rear view was reconstructed (workbench, LED frame, personnel door,
  photo, detailing station). The door wall is a flat slab with no roll-up door and no LED frame.
- Props are mushy or misplaced: lift arms melted, the bucket seat fused to a lift post on the wrong wall,
  tyre racks and cabinet run recognisable but soft.
- Texture: a single 2048² atlas of tiny islands, almost greyscale, about 47 px per metre on average.
- Verdict: **not production-ready; no runtime copy was made.** Recommendation: build the garage
  from modular primitives and assets, using the four reference images as the visual target.
- Not committed: being unusable, the GLB (29 MB) and its textures were kept out of the public
  repository (the hash above identifies the file; Higgsfield job f872e59c can re-download it).

## Credits

| Item | Count | Credits |
|---|---|---|
| Soul Location front candidates | 4 | 0.48 |
| 3D Jutsu Angles (rear/left/right, 2k) | 3 | 7.50 |
| Multi-Image to 3D (textured + PBR) | 1 | 30.00 |
| **Total** | | **37.98** (602.65 -> 564.67) |

## Godot import

`reference/` contains a `.gdignore` file, following the project's convention for
non-runtime source folders. Without them, Godot imports the 29 MB GLB and the large reference PNGs,
and because the export preset uses `export_filter="all_resources"`, they would end up in the
player's download.
