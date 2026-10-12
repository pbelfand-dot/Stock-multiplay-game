# Track Mode: the GT class and its race physics

Track Mode's GT class (`data/track_classes.json`: APEX GT CHALLENGE) races GT3 cars. Its cars,
the race physics added on top of the existing car physics, and why each number is what it is.
The plan they come from: `docs/GT_F1_TRACK_MODE_CLAUDE_PROMPT.md`.

## The cars

| Game name | Real car | Model | Its numbers (sources in its registry entry) |
|---|---|---|---|
| ELFER R | Porsche 911 GT3 R (992) | CGTrader `porsche_911_992_gt3_r` | 4.2 flat-six, 565 PS (BoP), ~1,250 kg, 2,507 mm |
| ELFER R EVO | Porsche 911 GT3 R (992.2) | CGTrader (no-AI: scripts only) | as the ELFER R |
| **AFFALTER GT3** (new) | Mercedes-AMG GT3 Evo | VTX's Sketchfab model (`Track_Mode_Cars/`) | 6.2 NA V8, ~550 bhp (BoP), 1,285 kg, 2,630 mm |

**The AFFALTER GT3** (`data/vehicles/affalter.json`, model `amg_gt3`, spec `tools/cars/amg_gt3.json`):

- **Paint:** its Red Bull livery is gone. The body is the game's paint and takes the garage's colours and liveries. The grille badge and the cabin and window stickers are dropped.
- **Badges that stay:** the stars on the steering wheel, boot lid and grille are in the model's mesh and textures (as the GLS's grille star is), and are noted in its limitations.
- **Size:** its tyres measure 680 mm front and 710 mm rear, 300 / 310 mm wide: GT3's 30/68-18 and 31/71-18. Its wheelbase is 2,630 mm and the driver sits on the left, both as on the real car.
- **The numbers:**
  - Motorsport Magazine's 2016 track test: the 6,208 cc naturally aspirated V8 carried over from the SLS GT3, about 550 bhp with restrictors, 1,285 kg homologated (1,265 kg dry), a six-speed Hewland transaxle, a wheelbase 50 mm shorter than the SLS's 2,680 mm.
  - conceptcarz: 4,746 mm long, 2,049 mm wide.
  - Torque, rpm, ratios, the weight split (~47 % front: front-mid engine, rear transaxle) and aero are estimates, and the entry says so.
- **Provenance:** its materials are named like Assetto Corsa Competizione's (Unreal "MI_..." instances), so it's noted as a game-asset port, as the repo's other ports are.

**The second 992 GT3 R package** (`Track_Mode_Cars/2024-porsche-992-gt3-r.zip`, VTX) was compared
with the ELFER R's model and not used:

- It's the same car, from the same lineage of racing-sim ports.
- The ELFER R's file already imports with its own wheels and cockpit, and its CGTrader licence is less restrictive than this one's CC BY-NC-SA.

It stays as the source to fall back on (`docs/ASSET_INTEGRATION_STATUS.md`).

## Race physics (`scripts/vehicle/physics/race_sim.gd`)

A Track Mode car carries a **RaceSim** (setup `"race_sim": true`), which sits on top of the car's
physics without replacing any of it. Each of its factors is 1 at the ideal: a tyre in its window
at the right pressure, a warm disc. Without it (every rally, touge and cut-up car) nothing changes;
`tests/race_check.gd` checks that too.

- **Tyre heat:**
  - Each tyre has a skin (3 kJ/K) and a core (12 kJ/K).
  - The skin is heated by its slip power (force times sliding speed, along and across), the carcass flexing (about 1.2 % of load times speed, a race tyre's rolling loss) and the track. The air takes heat off it at 20 + 2.2 W/K per m/s (about 1.3 m² of rubber).
  - The core follows the skin with a lag of about 100 s, so a lap or two to warm up.
  - The grip follows the temperature: cold below the window (a cold slick about 18 % down), full in it, greasy past it. (Until October 2026 a cold tyre also lost grip to its cold pressure, counting the cold twice: 25 % down. The pressure now counts once the tyre's near its window.)
- **Pressure:** the hot pressure comes from the cold setting by the gas law, on absolute pressure (gauge + 1.013 bar). 1.40 bar cold reaches ~1.95 bar with the core at ~90 °C, as a GT3 slick does. Away from the ideal, it loses grip.
- **Wear:** by slip energy. A slow fade to 70 % worn, then a cliff to 82 % grip worn out. A locked wheel at speed grinds a flat spot.
- **Compounds** (`data/tyre_compounds.json`): SOFT, MEDIUM, HARD and WET. Each has its window, grip, wear, heating and wet grip: the soft wears about 1.6 times as fast as the medium and 2.7 times the hard.
- **Brakes:** each disc's heat comes from the brake's own work (torque times spin), and the air cools it, much more at speed. A cold disc bites 10 % less, and past 700 °C it fades to 65 % at 1,000 °C.
- **Fuel:** burnt by throttle and revs (~280 g/kWh at a GT3's ~405 kW: about 2.5 l a minute flat out). The car's mass carries it at 0.745 kg/l: a 120 l tank, practice on 60.
- **Pit limiter** (P, or the pad's d-pad down): holds the pit lane's 60 km/h. The autopilot drives the lane on it.
- **ABS and TC:** the car's own levels (1-10, 0 off), not the rally's Settings switches. A GT3 has ABS and traction control and no stability control (Porsche's 992 GT3 R: Porsche Motorsport traction control and a racing ABS; the 991's adjustable). TC aims the rears' spin at their peak slip x 1.4 (level 1) .. x 0.75 (10): level 4, out of the box, ~x 1.2. It used to let the spin run up to 0.3 past the peak before it cut, and on cold slicks a tap of steering on the throttle spun the car.

At the autopilot's gentle pace (about 30 % off race pace, as in `tests/track_check.gd`), the
mediums warm to 35-55 °C over the out-lap and a lap, under their window: slicks driven gently
don't come in. At race pace the slip heat is several times greater and they do.

The panel in the corner (`scripts/ui/race_hud.gd`) shows the four tyres from above:

- each coloured blue, green or red against the window, with its temperature, a wear bar and its pressure;
- the compound and the brakes' heat;
- the fuel and the laps it's good for (from the last lap's burn);
- ABS and TC, and PIT LIMITER when it's on.

The numbers are the game's own, chosen to sit where the published figures put a real car:
Pirelli and Michelin give GT3 slicks a window of roughly 80-110 °C and 1.35-1.45 bar cold, and a
5 km lap burns 2.5-3 l. A tyre or brake supplier's own data would refine them.
