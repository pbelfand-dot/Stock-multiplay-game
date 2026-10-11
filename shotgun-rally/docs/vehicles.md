# The vehicle registry

Every vehicle in the game is one JSON file in `data/vehicles/<id>.json`. The game reads them
through `scripts/game/vehicle_registry.gd`, and everything that needs the list of cars uses it:

- the garage: `Catalog.CARS`, the entries with a `garage` block, in `order`;
- the physics: `CarSpecs.SPECS`, each model's `physics` block;
- traffic: `VehicleRegistry.traffic_pool()`, the entries with a `traffic` block;
- the tests, which go through `Catalog.CARS`.

There is no other list to keep in step. Add a file and the car is in the game. Remove the `garage`
block and it leaves the garage but can still be traffic.

`python3 tools/vehicle_registry.py check` validates every entry. It checks that each file is named
after its id, that the ids are unique, that roles and categories are known, that every model exists
and every own-model car has physics, and that no race car is traffic. `fmt` rewrites them in the
compact layout, and `table` prints a markdown table of them all.

## An entry

| Key | What it is |
|---|---|
| `id` | Stable id: the save file, the garage and multiplayer use it. Never rename one. |
| `name` | The name in the garage. The game's names are fictional and show no badges or brands. |
| `order` | Position in the garage. |
| `model` | `assets/models/cars/<model>/` (the GLB and `parts.json` from `tools/import_car.py`); `""` = the shared Higgsfield body. |
| `category` | `rally`, `jdm`, `euro`, `american`, `hyper`, `race`, `traffic` (the garage's tabs). |
| `role` | `rally`, `touge_grip`, `drift`, `player_road`, `track`, `hypercar`, `race_prototype`, `traffic`, `premium_traffic`, `special`. |
| `real` | The real car: `manufacturer`, `model`, `year`, `trim`, `race_class`. |
| `specs` | Its researched numbers: `power_hp`, `weight_kg`, `drivetrain`, `transmission`, `wheelbase_mm`, `top_speed_kmh`, `front_weight`, plus `notes` (where they come from, which are estimates). |
| `garage` | Its garage entry: `price`, `engine_sound` (EngineSound's sets), `livery`, `number`, `colours` ([r, g, b] × 4: body, the livery's two, the wheels' trim), `wheels`, `power` / `grip` / `brakes` (× its own), `drive_front`, `blurb`, and `mass` for the shared body. |
| `traffic` | If it can be traffic: `weight` (how often, against the others) and `paints` ([r, g, b] each). |
| `physics` | `CarSpecs`' spec: `mass`, `front` (weight on the front axle), `torque` + `curve`, `idle`, `limiter`, `turbo` + `spool`, `gears`, `final`, `drive` (+ `front_share`), diffs `centre` / `front_diff` / `rear` as [`"open"`/`"locked"`/`"lsd"`, power lock, coast lock, preload N m], `cd`, `area`, `down`, `brake`. |
| `interior` | `own` (its model's interior is used), `camera` (the seat view works), `view` (`"hood"`: the model has no cabin, so the driver's view is a camera over its bonnet: its parts.json `"view"`, which the game reads), `notes`. |
| `driver_seat` | Overrides for how the crew sit in it (see docs/cars.md, Their interiors). |
| `source` | The package it came from, its candidate number, the author, the licence and URL. |
| `research` | Where the numbers come from (URLs, or the publication). |
| `limitations` | What isn't right yet. |

Progress on the owner's 43 car candidates is in [`VEHICLE_PROGRESS.md`](VEHICLE_PROGRESS.md).
