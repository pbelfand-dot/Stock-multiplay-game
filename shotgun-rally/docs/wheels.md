# Wheels: the WheelPreset system

The garage's **WHEELS** tab now has a **TYPE** as well as a colour: a whole wheel assembly
(rim, tyre, brake disc and caliper) fitted to the car, corner by corner. It's data-driven:
the presets are in `data/wheel_presets.json`, the code is `scripts/vehicle/wheel_presets.gd`
(fitting and assembling) and `scripts/vehicle/wheel_gen.gd` (building wheels in code to any
size). Track Mode's spec asked for it (`docs/GT_F1_TRACK_MODE_CLAUDE_PROMPT.md`, "Vehicle and
wheel integration").

## What a preset is

Each preset has:

- a **rim**: a style built in code (spokes, a kind: straight, split, cross-laced mesh, Y; spoke width, taper, concave, lip depth, lug nuts or a centre-lock nut), or a converted mesh;
- a **tyre**: tread `street`, `slick`, `wet` or `vintage` (with a whitewall), its **aspect** (sidewall over width) or a fixed rim size (`rim_in`), **width_k** and **offset** against the stock wheel, its **compound** and **pressure** (for the track physics, phase 4);
- a **brake package** (`street` 2-pot, `sport` 4-pot, `race` 6-pot, `carbon`): the disc's size against the barrel, the caliper's pistons and colour;
- its **classes** (road, track, formula) and a **price**.

There are 9 types plus STOCK:

| Name | Kind | Rim | Tyre | Brakes | Offered on |
|---|---|---|---|---|---|
| ORBITA STRADA 5 | street | five broad spokes | street | 2-pot | road and track cars |
| ORBITA TORRE 10 | street | ten slim spokes | street | 4-pot | road and track cars |
| KAZEWORKS SPLIT 6 | street | six split spokes, deep concave | street | 4-pot | road and track cars |
| KREUZ LATTICE | street | cross-laced mesh, polished lip | street | 4-pot | road cars |
| MERIDIAN CITY 5 | street | the converted Innerscene 17 in | its 225/45 R17 | 2-pot | road cars |
| OLDSMITH DISH | vintage | deep dish, eight slots | tall, whitewall | 2-pot | road cars |
| KAZEWORKS WIDE 5 | wide | split, deep lip, +12 % wide, 12 mm out | street | 4-pot | road cars where it fits |
| APEX RACING CL6 | track | forged Y-spoke centre-lock | slick | 6-pot | GT and prototype cars |
| FORMULA 18 | formula | 18 in, ten spokes, centre-lock | low-profile slick | carbon | single-seaters (none yet) |

All the names are made up, and there are no logos.

## How it goes on a car

- **The tyre's outside is always the car's own.** Each corner's tyre is sized to that corner's stock radius and width from the model's `parts.json`. Front and rear are sized separately; on the GT3 R the rears are bigger.
- **The physics radius never changes**, at any LOD.
- **Separate nodes:** the tyre, rim and disc go on the wheel's spinner (they roll), the caliper on the pivot (it steers but doesn't roll).
- **Left wheels are mirrored, not copied**, as real wheels are mounted, so the face is outwards and directional tread runs the right way on both sides.
- The car's own wheels and calipers are hidden, not dropped: STOCK brings them back.
- The rims take the garage's wheel colour.
- Only cars with a model of their own take presets. The four Higgsfield rally cars keep their own rally wheels.

Each part has a full mesh (64 segments round) out to 22 m, a lighter one (20 segments) to 70 m,
and beyond that a low-poly CC0 stand-in from the converted library, scaled to the wheel.

## Does it fit? (`data/wheel_fit.json`)

The garage only offers a type that suits the car's class and clears its arches.
`tools/wheel_fit.gd` measures this for every car model in the registry: it moves the preset's
tyre through the positions a fitment check uses (full lock at ride height, the bump stop going
straight, and half of each together) and tests it against every vertex and triangle centre of
the car's body. The bump stop comes from each car's suspension, its travel past its rest.

It fits if it touches nothing the stock tyre, moved the same way, doesn't already touch. A
model's arch liner can sit inside its own tyre, so only what the new wheel adds counts.

The result is honest:

- the standard-width types fit every car;
- **KAZEWORKS WIDE 5 fits only two** (the LANCER IX and the STROMER 4). The other models fill their arches with the stock tyre, so the wider, pushed-out wheel rubs a fender lip at full bump, the way a real one would without arch work.

The garage says how many types won't clear a car's arches.

Run `godot --headless --path . -s tools/wheel_fit.gd` after changing a preset or adding a car.
`tests/wheel_check.gd` fails if the file is stale.

## The converted CC0 library (`assets/wheels/`)

`python3 -I tools/import_wheels.py` converts `assets/wheel_packages/Free_Wheels/` in two stages:

1. System Python reads the USD Mini Car Kit's wheels with pxr (Ubuntu's Blender has no USD import), unpacks the IceMaan rims and copies the Innerscene X3D.
2. Blender imports them all and makes one GLB per wheel (11 in all):
   - parts split by material or by size into **Tyre**, **Rim** and **Disc**;
   - turned so the axle runs along x and the face is at +x;
   - centred on the tyre (a wheel's nuts and cap can stand proud of it);
   - a `wheel.json` beside each one with its diameter, width, triangles, source and licence.

| Wheel | Triangles | Used as |
|---|---|---|
| `innerscene_street5` (Innerscene 17 in five-spoke, 225/45 R17, real scale) | 11,908 | MERIDIAN CITY 5 (a garage type) |
| `cc96_rim1` ... `cc96_rim4` (IceMaan CC96 rims) | 1,156-1,568 | the far stand-ins of STRADA 5, TORRE 10, SPLIT 6 and APEX CL6 |
| `usd_normal`, `usd_wide`, `usd_vintage`, `usd_largerim`, `usd_black`, `usd_red` (USD Mini Car Kit) | 236-332 | the far stand-ins of MERIDIAN, WIDE 5, OLDSMITH, FORMULA 18, KREUZ and the street default |

The README's high-detail Sketchfab candidates (BMW, Porsche, F1 tyres...) are links only: they
were never downloaded, so nothing pretends they are here.

## Checks (`tests/wheel_check.gd`, in `tests/run_all.sh`)

- **The presets:** each is complete; names are fictional (checked against real wheel and tyre brands); every kind the spec names exists; every kind has its far stand-in.
- **Every converted wheel:**
  - loads with its Tyre and Rim apart;
  - the tyre matches its `wheel.json`;
  - it sits on the x axle, centred, face at +x.
- **Every preset at every corner of three cars** (the ELFER R, SYLPH S15, STROMER 4; 108 assemblies):
  - the axle sits on the hub, and the wheel is round about it (it spins in place);
  - the tyre's bottom is on the ground at the physics radius, at the width it should be;
  - the face points outwards on both sides;
  - the caliper is over the disc, inside the barrel's drop centre, clear of the rim's metal;
  - the near, lighter and far meshes are all there.
- **The fit:**
  - the file is up to date and covers every garage car;
  - three cars measured again agree;
  - the garage offers road cars road wheels and GT cars track ones, and nobody the formula wheel.
- **On a car:**
  - a preset goes on with the car's own wheels hidden and the physics radius unchanged;
  - the tyre rolls and the caliper doesn't, and both steer;
  - STOCK brings the car's own wheels back;
  - another car comes on its own wheels.

`tools/wheel_sheet.gd` renders a contact sheet of the whole library, from the face or from
behind (`--back`).
