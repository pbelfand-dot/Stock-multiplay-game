# The car models: an audit (2026-10-13)

Every car model in the game: the garage's 70 cars with bodies of their own and the four on the
shared rally body, the race fields' cars (the GT3, GT4, prototype and Formula fields are garage
cars too, plus the generic HALDANE, VESPERA, VALKO and STILETTO) and the traffic (SALOON,
CROSSOVER, PEOPLE MOVER, the HELLHOUND and the garage cars that also drive in traffic).

Checked outside: proportions, the wheels (size, place, tyres, rims, calipers, what spins and
steers with them), gaps and holes, faces missing or drawn from the wrong side, z-fighting, stray
parts, textures, chrome and metal, glass, lamps and badges; how each car sits on the ground and
on its springs. Inside: what's left after today's cabin fixes.

How:
- **By script, every car:** `tools/model_audit.py` (Blender: wheels round about their axle, rims
  seen from outside, wheels left in the body, red you can see from behind, faces wound against
  their normals, see-through and plain-white materials), `tools/car_geo_audit.py` (new, numbers
  from the GLB: each wheel's node against its tyre's middle, left against right, the tyres against
  the body beside them, the body's loose pieces, faces drawn twice in two materials, mirror-smooth
  metal), the body parts left inside a wheel (in it, but neither spinning nor steering), the lamp
  materials CarLook makes, the tests below.
- **By eye, the seen cars only:** four views of each (`tools/car_shots.gd`, now with the car parked
  at its standing squash as the garage shows it), the wheels close up and steered
  (`--set=wheels --steer=25`), the lamps by day and at night (`tools/lamp_shots.gd`), the cabins
  from the seat in the game itself.
- **The no-AI cars by script only** (no picture of them was made or looked at): SALOON, CROSSOVER,
  PEOPLE MOVER, HELLHOUND, KITSUNE 13, BISCIONE V6, ELFER R EVO and WOKING ONE. Their four
  interiors (KITSUNE, BISCIONE, ELFER R EVO, WOKING ONE) wait for the owner.

## The checks (in the tests)

| What | Where it's checked |
|---|---|
| Sits on its wheels, the body clear of the ground | `tests/car_models_check.gd` (every garage model: the tyres' bottoms within 3 cm of the ground standing, the physics wheels under the model's) |
| Each wheel turns about its own middle, nothing else spins with it, both of an axle the same tyre | `tests/car_models_check.gd` (new: the tread's middle within 2.5 cm of the steering pivot, the spinning part no wider than its tyre allows, left and right treads within 3 cm) |
| Lamps: the tail lamps red, the headlamps' glass clear | `tests/car_models_check.gd` (new: a see-through tail lens deep red over the reflector, the glow a red that stays red; a headlamp lens clear glass, also one left opaque in the file; a headlamp all one flat colour a polished reflector, barely glowing; a small LED still glowing) |
| Wheel presets fit the arches | `tests/wheel_check.gd` (data/wheel_fit.json measured again for the 15 models whose wheels changed) |
| Cabins: matte, nothing on the steering wheel but the wheel, feet on the floor | `tests/interior_check.gd` |
| The lamps found and lit, glass and chrome | `tests/render_check.gd`, `tests/lamps_check.gd` |

## What was found, by kind

| Kind | Found | Fixed | Left |
|---|---|---|---|
| Lamps (every car) | Tail lamps pink, not red; headlamps a glazed white plate by day | Yes, in `scripts/render/car_look.gd` for every car (below) | - |
| Wheels steering about the wrong point | KASTEN 63 (three wheels 7 cm off), WOKING 800 (all four 0.2-0.4 m off, the physics' track a metre) | Yes: the wheel nodes at their tyres' middles, `parts.json` (the physics' wheels) with them | - |
| Wheels missing part of their tyre | KASTEN 63: three tyres only their outer wall | Yes: each wheel a copy of the complete one | - |
| Suspension spinning with the wheels | WOKING 800: its wishbones and uprights were in the wheel nodes | Yes: into the body (the nuts and the cap still spin) | - |
| Wheel parts left in the body (they neither spun nor steered) | Rims (WOKING 800, two of the AFFALTER SLR 722's), aero covers (UNO HYBRID), brake discs and rings (OCELOT R1, VEE-SR GTP, AFFALTER CLK DTM, TEMPESTA GT3, WOKING ONE), hub caps, centre nuts and hubs (MOCHI e, AKATSUKI V, TORO R26, KAISER 8 GC rears, KITSUNE 13), a caliper (SLR 722) | Yes: moved into their wheels (the caliper onto its hub, steering, not spinning) | Pieces that belong with the body or are too small to matter: uprights, drive-shaft ends and brake ducts (they don't spin anyway), the AFFALTER GT3's carbon backing plates behind its brakes (they don't steer with the front wheels; hidden by the rims), two-face logo decals on the AFFALTER GT BLACK's and KAISER 2 CARBON's wheel centres (they don't spin) |
| Z-fighting (the same faces twice in two materials) | KAISER 8 GC's front grille four times over in four finishes, and 0.09 m2 of its cabin twice; ELFER RS's tail lens and headlamps twice; PUEBLO 392's headlamp reflectors; LANCER IX's indicators (amber and chrome) | Yes: the copies left out (`drop_dupes`) | Doubles in one colour or out of sight: AKATSUKI V (0.17 m2 of black trim, gloss and matt), KAISER 5 E (0.03 m2, black on black), GHOST J (0.05 m2, engine bay and cabin), WOKING 720 GT3 and AFFALTER GT BLACK (0.01 m2 each, cabin) |
| Mirror chrome where there's none | WOKING 800 (wing, diffuser, carbon, chassis at full metal and zero roughness), AFFALTER GT3 (its exterior details left at the glTF default, full metal) | Yes: satin, not metal | - |
| Glass | Windows and lamp covers left metallic: a dark mirror (ROTORA FC), silver covers (GHOST J), half-metal glass on six more | Yes: glass is never metal (`car_look.gd`) | - |
| How the cars sit | Every garage model's tyres within 2 cm of the ground standing, the body clear of it (0.03 m, the SYLPH S15 on its kit, to 0.24 m); the four traffic-only models' tyres on the ground (0.001 m) | - | - |
| Proportions | Every model's wheelbase is the real car's (the import scales to it); tracks and widths match their real cars or their kits | - | KITSUNE 13 (below) |
| Faces drawn from the wrong side, textures | None left (`tools/model_audit.py`; the magenta fill on the HAKO's bumper was fixed earlier). model_audit still flags 21 cars' tail lights (the three Formula cars' a rain light): it reads the files, where those red lenses are see-through or left without their colour; CarLook makes them red as the game draws them (measured below) | - | - |
| Badges and lettering | Real makers' logos and sponsors' names are in many models' textures (grilles, wheel centres, tyres, race liveries) | - | Listed per car: painting them out needs the owner's say (and new textures) |

## The lamps (every car)

The owner: "the headlights look glazed, not like real headlights" and "the rear lights are pink, not
red". Both were CarLook's, so both are fixed for every car at once (the garage, the race fields and
the traffic: `CarLook.dress` and `CarLook.glow_model`):

- **Tail lamps.** Their glow is a deep red now that stays red through the game's AgX tonemapper (a
  bright, not quite pure red went pink). A see-through red lens over a white reflector (alpha 0.22-0.64
  in the files) is a deep red lens (alpha at least 0.78) and the reflector behind it red too; a faint
  red over white read pink. The brakes are red on top (at most 4.5 bright at night, was 10).
- **Headlamps.** A see-through lens is clear glass (alpha 0.16, smooth): what's behind it shows,
  the reflectors and LEDs. Six cars' lenses were grey or tinted plates: KAISER 320 (alpha 0.50),
  WARHAWK 707 (0.40), GRAND SUV 63 (0.54), WOKING 600 (0.58), AKATSUKI V (0.50), BISCIONE V6 (0.25). A
  lens left opaque in the file but named glass or lens (AFFALTER A45 S, alpha 0.48 never drawn) is
  drawn as glass too. A headlamp that is all one flat colour is a polished reflector glowing a little
  by day (it was a white plate: about two dozen
  cars); a small one the model made glow itself (an LED, a running light, under 0.04 m2) keeps glowing. By day a headlamp glows 0.9 (was 2.2), at night 5.5.
- **Measured** (the day shots' tail lamps, the brightest red pixels of the straight-behind view;
  saturation before -> after on the same pictures; on a red car its paint mixes in): AFFALTER GT
  BLACK 0.23 -> 0.61, RAIDEN GT 0.30 -> 0.62, SYLPH S15 0.31 -> 0.58, HELLHOUND WB 0.38 -> 0.63,
  TEMPESTA URSA 0.38 -> 0.53, KASTEN 63 0.50 -> 0.79, PLEIAD 22 0.61 -> 0.94, MOCHI e 0.33 -> 0.67, the
  four generic GT cars (HALDANE, VESPERA, VALKO, STILETTO) hue +16 deg (orange) -> +1 deg, 0.65 -> 0.81.
  At night on the touge, the KAISER 320 from behind: hue 15 deg, saturation 0.42 (salmon) -> hue 9 deg,
  0.97 (red).
- **Checked** in `tests/car_models_check.gd` (the lamp materials CarLook makes, from synthetic ones).

## Every car

In the game's order. "Lamps" means the lamp fix above made the difference that row names. A no-AI car's row comes from the scripts alone.

| Car | What was wrong | What was fixed | What's left |
|---|---|---|---|
| KESTREL R4 (`kestrel`) | - | - | - |
| BLUE COMET WRC (`comet`) | - | - | - |
| VORTEX EVO (`vortex`) | - | - | - |
| MARTELLO 037 (`martello`) | - | - | - |
| NIMBUS EG (`nimbus`) | headlamps a flat white glaze by day | lamps | - |
| ROTORA FC (`rotora_fc`) | the windows a dark metal mirror (the glass left fully metallic); headlamps a flat white glaze by day | glass not metal; lamps | - |
| HACHI 86 (`hachi`) | - | - | - |
| SYLPH S15 (`sylph`) | tail lamps pale (saturation 0.31) | lamps | - |
| KAISER 30 (`kaiser`) | headlamps a flat white glaze by day | lamps | plain dash with no instrument faces: live boards need the owner's OK |
| ROTORA FD (`rotora_fd`) | headlamps a flat white glaze by day | lamps | plain dash with no instrument faces: live boards need the owner's OK; its tail lamps dark by day (smoked in the model), lit at night |
| MARTELLO SEDICI (`sedici`) | - | - | plain dash with no instrument faces: live boards need the owner's OK |
| VIERRAD S1 (`vierrad`) | its red tail glass half metal | glass not metal | the real drivetrain's name on the tail |
| OCELOT R1 (`ocelot`) | its brake discs' rims stood in the body (they neither spun nor steered); headlamps a flat white glaze by day | the discs moved into the wheels; lamps | - |
| HELLHOUND WB (`hellhound`) | headlamp glass opaque and flat (a glaze over the lamp); tail lamps' red see-through, pink over the reflector | lamps | plain dash with no instrument faces: live boards need the owner's OK |
| BRAWLER 70 (`brawler`) | - | - | - |
| WARHAWK 707 (`warhawk`) | headlamp glass a grey glaze over the lamp; tail lamps' red see-through, pink over the reflector | lamps | the real maker's name on the grille and tailgate |
| PUEBLO 392 (`pueblo`) | headlamp reflector a flat plate, and drawn twice (in its own and the body's material: they flickered) | lamps; the copy left out | - |
| PLEIAD 22 (`pleiad`) | headlamps a flat white glaze by day; tail lens see-through | lamps; its window trim glass not metal | - |
| HAKO 2000 (`hako`) | - | - | four small gauges too small in the texture to make live |
| MOCHI e (`mochi`) | headlamp glass opaque and flat; its hub caps stood in the body (didn't spin or steer) | lamps; the hub caps into the wheels | the real maker's name on the tailgate |
| LANCER IX (`lancer`) | headlamps a flat white glaze by day; its indicators drawn twice (amber and chrome, flickering) | lamps; the chrome copy left out | - |
| AKATSUKI V (`akatsuki`) | headlamps a flat white glaze by day; its hub centres stood in the body | lamps; the hubs into the wheels | 0.17 m2 of black trim drawn twice (gloss and matt, both black: no visible flicker) |
| RAIDEN GT (`raiden`) | tail lamps pale (saturation 0.30) | lamps | - |
| KITSUNE 13 (`kitsune`) (no AI) | a chrome ring and a black disc inside the front wheels stood in the body (scripts only: no pictures) | moved into the wheels | its model is 2.08 m wide over a 1.72 m track (the stock car: 1.69 m, 1.47 m): a wide-arch kit or a model stretched sideways, which only a picture could tell; its cabin waits for the owner (no-AI licence) |
| KOMBI V8 (`kombi`) | - | - | - |
| KAISER T (`kaiser_t`) | - | - | - |
| KAISER 2 WB (`kaiser_2`) | its window trim glass half metal | glass not metal | - |
| KAISER 2 CARBON (`kaiser_2c`) | - | - | a two-face wheel-maker's decal on each wheel centre stays with the body (it doesn't spin); a real tuner's name on the number plate |
| KAISER 4 WB (`kaiser_4`) | tail lamps' red see-through, pink over the reflector | lamps | - |
| KAISER 5 E (`kaiser_5`) | - | - | - |
| KAISER 8 GC (`kaiser_8`) | its front grille modelled four times over in four finishes (black, carbon, aluminium, silver): they flickered through each other; 0.09 m2 of its cabin twice in two colours; its rear hubs stood in the body | the copies left out (the carbon grille kept); the hubs into the wheels; lamps | - |
| KAISER 320 (`kaiser_3`) | headlamp glass a grey glaze over the lamp (alpha 0.50); tail lamps' red see-through, pink over the reflector (alpha 0.64) | lamps | - |
| KAISER 235 GC (`kaiser_235`) | - | - | a real maker's roundel on the steering wheel boss (in the texture) |
| KAISER 5 G (`kaiser_5g`) | - | - | - |
| KAISER 5 TOURING (`kaiser_5t`) | - | - | - |
| STROMER 4 (`stromer`) | its glass half metal | glass not metal | the real maker's logo front and back |
| KAISER 5X (`kaiser_5x`) | - | - | - |
| KAISER 3X (`kaiser_3x`) | - | - | - |
| KAISER 7X (`kaiser_7x`) | its glass half metal | glass not metal | - |
| KASTEN 63 (`kasten`) | three of its four tyres only their outer wall (the inner half lost in the import), those wheels steering about a point 7 cm off their middle and the physics' front track 7 cm narrow; tail lamps' red see-through, pink over the reflector | every wheel the complete one (the front right, mirrored), each at its tyre's middle, the physics' wheels with them; lamps | - |
| TEMPESTA URSA (`tempesta_ursa`) | tail lamps' red see-through, pink over the reflector | lamps | - |
| VIERRAD R7 (`vierrad_r7`) | - | - | - |
| AFFALTER A45 S (`affalter_a45`) | headlamp glass opaque (alpha 0.48 left opaque in the file); tail lamps' red see-through, pink over the reflector | lamps | - |
| AFFALTER S EXECUTIVE (`affalter_s`) | - | - | - |
| SALOON (`traffic_sedan`) (no AI) | - (scripts only: no pictures) | - | - |
| CROSSOVER (`traffic_crossover`) (no AI) | - (scripts only: no pictures) | - | - |
| PEOPLE MOVER (`traffic_minivan`) (no AI) | - (scripts only: no pictures) | - | - |
| GRAND SUV 63 (`gls`) | headlamp lens a grey-green glaze (alpha 0.54) | lamps | - |
| HELLHOUND (`hellhound_s`) (no AI) | - (scripts only: no pictures) | - | - |
| ELFER RS (`elfer_rs`) | its tail light bar under an opaque silver lens with a second copy of the lens over it: the bar read white, the copies flickered; its headlamps drawn twice; headlamps a flat white glaze by day | the lens clear glass, the copies left out; lamps | - |
| UNO HYBRID (`uno`) | its wheels' aero covers and centre caps stood in the body (they neither spun nor steered) | moved into the wheels | - |
| CENTURIA 16 (`centuria`) | - | - | - |
| VENTO CINQUE (`vento`) | tail lamps' red see-through, pink over the reflector; its lamp covers half metal | lamps; glass not metal | - |
| GHOST J (`ghost`) | its lamp covers opaque silver (glass left metal and opaque) | glass: clear covers; lamps | 0.05 m2 of the engine bay and cabin drawn twice |
| BOLT W16 (`bolt16`) | headlamps a flat white glaze by day | lamps | the real maker's name across the tail |
| WOKING 600 SPIDER (`woking_600`) | tail lamps' red see-through, pink over the reflector | lamps | - |
| AFFALTER SLR 722 (`affalter_slr`) | two of its rims (front right, rear left) and a front caliper stood in the body: those rims neither spun nor steered; tail lamps' red see-through, pink over the reflector | the rims into their wheels, the caliper onto its hub; lamps | - |
| AFFALTER GT BLACK (`affalter_gtb`) | headlamps a flat white glaze by day; tail lamps pale (saturation 0.23) | lamps | a two-face logo decal on each wheel centre stays with the body (it doesn't spin) |
| WOKING 800 (`woking_800`) | its wheel nodes held the suspension (wishbones and uprights spun with the wheels), each node 0.2-0.4 m inboard of its tyre, the physics' track 1.01 m; its rims and centre nuts stood in the body (they neither spun nor steered); the wing, diffuser, carbon and chassis mirror chrome | the suspension into the body, each wheel at its tyre's middle (track 1.77 m), the rims and nuts into the wheels, the finishes satin; lamps | - |
| WOKING ONE (`woking_one`) (no AI) | its brake discs and hub details stood in the body; tail lamps' red see-through, pink over the reflector (scripts only: no pictures) | moved into the wheels; lamps | its cabin waits for the owner (no-AI licence) |
| BISCIONE V6 (`biscione`) (no AI) | headlamps a flat white glaze by day (scripts only: no pictures) | lamps | its cabin waits for the owner (no-AI licence) |
| ELFER R (`elfer_r`) | - | - | - |
| AFFALTER GT3 (`affalter`) | its exterior details (wing, grille, diffuser) mirror chrome: the material left at full metal; tail lamps' red see-through, pink over the reflector | satin, not metal; lamps | its carbon brake backing plates stay with the body (they don't steer with the front wheels; behind the rims) |
| ELFER R EVO (`elfer_evo`) (no AI) | tail lamps' red see-through, pink over the reflector (scripts only: no pictures) | lamps | its cabin waits for the owner (no-AI licence) |
| HALDANE GT3 (`haldane`) | headlamps a flat white glaze by day | lamps | - |
| VESPERA GT3 (`vespera`) | headlamps a flat white glaze by day | lamps | - |
| VALKO GT4 (`valko`) | headlamps a flat white glaze by day | lamps | - |
| STILETTO CUP (`stiletto`) | headlamps a flat white glaze by day | lamps | - |
| KAISER 4 GT3 (`kaiser4_gt3`) | - | - | the cabin untextured in the model |
| TEMPESTA GT3 (`tempesta_gt3`) | its rims' centres and nuts stood in the body; tail lamps' red see-through, pink over the reflector | moved into the wheels; lamps | its team livery carries real sponsors' names |
| WOKING 720 GT3 (`woking_gt3`) | - | - | its team livery carries real sponsors' names and a tyre maker's |
| AFFALTER CLK DTM (`affalter_dtm`) | its brake rings and centre nuts stood in the body (they neither spun nor steered) | moved into the wheels | its team livery carries real sponsors' names |
| ELFER GT2 CS (`elfer_gt2cs`) | - | - | the real maker's name on the windscreen banner |
| VEE-SR GTP (`vsr`) | its carbon brake rings stood in the body | moved into the wheels | model_audit still sees a ring of body inside the front tyres' radius: the arch's inner edge close round the wheel (the pictures show nothing wrong); a real tyre maker's name on the sidewalls |
| 963 GTP (`gtp963`) | - | - | its livery carries the real maker's and sponsors' names |
| TORO R26 (`toro`) | its wheel nuts stood in the body | moved into the wheels | its team livery; a real tyre maker's name on the sidewalls |
| VEE-F 26 (`vee_f`) | - | - | a real tyre maker's lettering on the sidewalls |
| AFFALTER W17 (`affalter_w17`) | - | - | its team livery |

## Left, and why

- **Real makers' logos and sponsors' names in the textures:** most road cars still carry their
  maker's badge on the grille, the boot and the wheel centres (small, in the models' own textures);
  the bigger ones, lettering and liveries, are named per car above. They are pictures inside
  the models' own textures; taking them out means painting the textures, one by one, and the race
  liveries are the cars' own (`own_livery`). The owner's call.
- **The four no-AI cabins** (KITSUNE 13, BISCIONE V6, ELFER R EVO, WOKING ONE): waiting for the owner.
- **Four plain dashes** (KAISER 30, ROTORA FD, MARTELLO SEDICI, HELLHOUND WB): no dial faces, screens
  or needles in the models; making them live means adding boards, which needs the owner's OK.
- **KITSUNE 13's width:** its model is 2.08 m wide over a 1.72 m track, where the stock car is 1.69 m
  and 1.47 m (its length and wheelbase match). A wide-arch kit modelled on, or a model stretched
  sideways: only a picture would tell, and this car may not be pictured.
- **Small pieces inside the wheels that stay with the body** (brake ducts, uprights, backing plates):
  they don't steer with the front wheels, but they sit behind the rims and are smaller than 15 cm.
- **Faces side by side in one plane** (`tools/car_geo_audit.py` notes them: a trim strip continuing the
  paint, a sticker on glass). These aren't the same faces twice, and the pictures show no flicker on
  them; a note, not a fault.
- **Cabins after today's fixes:** HAKO 2000's four small gauges (their scales too small in the texture),
  PLEIAD 22's needle caps glow white at night, VEE-SR GTP's LED row and two boxes stay blank, KAISER 4
  GT3's cabin is untextured in the model, ELFER GT2 CS and TEMPESTA GT3 have no faces of their own
  (panels drawn on them), the AFFALTER CLK DTM's Modes frame and the 963 GTP page's other figures
  stay as painted.

## Running the checks again

```
python3 tools/car_geo_audit.py [model ids]                      # shapes, numbers only
blender -b -Y --python tools/model_audit.py -- [model ids]      # looks, numbers only
godot --headless --fixed-fps 120 --path . -s tests/car_models_check.gd
xvfb-run -a -s "-screen 0 1280x800x24" godot --path . --resolution 1280x800 \
  -s tools/car_shots.gd -- --seen_cars_only --ids=<seen cars> [--set=wheels --steer=25]
```

A fix to a model goes in its spec's `glb_patch` (`tools/cars/<model>.json`, applied by
`tools/glb_patch.py`, and again by `tools/import_car.py` on a fresh import): this audit added
`wheels_from`, `wheel_centre`, `body_to_wheels` and `drop_dupes` to the materials and faces it had.
After changing a GLB, import it (`godot --headless --path . --import`) and measure the wheel presets'
fit again (`tools/wheel_fit.gd -- --only=<model>`).
