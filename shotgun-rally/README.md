# SHOTGUN RALLY

![SHOTGUN RALLY: you drive, your friend rides shotgun with the map](docs/screens/banner.jpg)

**You drive. Your friend rides shotgun with the map.** A 2-player online co-op rally
game. One of you drives, blind past the next crest. The other sits in the passenger seat with a
map of the road ahead, works out what's coming and yells it: "LEFT! TIGHT LEFT! OVER THE CREST!"
No friend online? The **AI co-driver** takes the seat.

Plus **MODES**, alone or **online with up to 8 drivers**, each in their own car: the **TOUGE**, a
Japanese mountain pass at night lit only by its street lamps and your headlights (time attack
against your ghost, drift, or online a race to the bottom), and **CUT UP**, weaving through
heavy highway traffic on an endless 28 km loop ([docs/modes.md](docs/modes.md)).

> SHOTGUN RALLY lives in this `shotgun-rally/` folder, next to BAGHOLDERS on `main`. It's its own Godot
> project with its own build, so the two games never touch each other. Both games' downloads are on
> the [repo's front page](../README.md).

| | |
|---|---|
| ![The home screen: the logo and menu over your car flat out on a stage](docs/screens/home.jpg) | ![MODES: the touge and cut up, alone or online up to 8](docs/screens/modes.jpg) |
| ![The touge at night: sodium street lamps, your headlights, the cedars close](docs/screens/touge_night.jpg) | ![Cut up at night: the LAKESHORE LOOP's towers lit, lamps along the highway](docs/screens/cutup.jpg) |
| ![An online touge's results: the podium](docs/screens/results.jpg) | ![GO: the start lights](docs/screens/start_lights.jpg) |
| ![The garage: buy, paint, upgrade](docs/screens/garage.jpg) | ![The loading screen: the night touge's key art](docs/screens/loading.jpg) |
| ![The realistic cars: Rotora FD in the garage, real power and weight](docs/screens/garage_fd.jpg) | ![The nine realistic cars](docs/screens/cars_lineup.jpg) |
| ![Story mode: the Shotgun Series](docs/screens/maps.jpg) | ![Mountains on the horizon, the Mud & Mist rally's fog](docs/screens/mud_mist.jpg) |
| ![Driver](docs/screens/driver.jpg) | ![Co-driver looking at the map](docs/screens/codriver.jpg) |
| ![Mountain tarmac: switchbacks up a hillside, a village, snow and armco on a winter stage](docs/screens/mountain.jpg) | ![Into a village: houses with shutters, a church tower, a stone wall](docs/screens/village.jpg) |
| ![Tarmac and mixed: gravel dragged onto the asphalt after a join, ice on one lane, snow along an edge, back onto gravel](docs/screens/tarmac.jpg) | ![The FPV drone chasing the car behind the menu](docs/screens/fpv.jpg) |
| ![Through a town: pavements, crowd barriers, the square, the street winding through](docs/screens/town.jpg) | ![The town from the driver's seat](docs/screens/town_seat.jpg) |
| ![Mud on the windshield](docs/screens/mud.jpg) | ![The start: five lights and a clock each side of the road](docs/screens/start.jpg) |
| ![Your co-driver, seen from the driver's seat](docs/screens/crew.jpg) | ![The chase camera (C): the wheels steer and bounce, the mud flaps swing](docs/screens/chase.jpg) |
| ![Handbrake: the right hand leaves the wheel and yanks the lever](docs/screens/handbrake.jpg) | ![The loading screen](docs/screens/loading.jpg) |
| ![Drift dirt: lumpy dust clouds and a ribbon of gravel off the tyres](docs/screens/drift.jpg) | ![The dust rolling past the side window](docs/screens/drift_window.jpg) |
| ![A big jump: off the brow at 120 km/h, the landing slope ahead](docs/screens/jump.jpg) | ![The same jump from the chase camera, 1.4 m up](docs/screens/jump_chase.jpg) |
| ![A narrow, technical section (4.6 m): two worn wheel tracks, looser gravel at the edges](docs/screens/road_narrow.jpg) | ![A wide, fast section (6.8 m)](docs/screens/road_wide.jpg) |
| ![A wooden bridge over a gully: plank deck, rails, timber trestles, the stream below](docs/screens/bridge.jpg) | ![Onto the bridge from the driver's seat](docs/screens/bridge_seat.jpg) |
| ![Spectators behind the tape at a jump, waving flags](docs/screens/crowd.jpg) | ![The crowds at the start](docs/screens/crowd_start.jpg) |
| ![Racing gloves on the wheel, gauntlets over the sleeves](docs/screens/gloves.jpg) | ![Numbered dials, shift lights and the gear](docs/screens/dials.jpg) |
| ![The cockpit from the co-driver's seat: the driver belted in, the wheel, switch panel, sequential lever and handbrake](docs/screens/interior.jpg) | ![Driving in third: a shift light on, the wipers clearing a mud splat](docs/screens/dash.jpg) |
| ![Belted in: six-point harness, padded shoulder straps, steel adjusters, the cam-lock buckle](docs/screens/belts.jpg) | ![A gear change: the right hand on the sequential lever, pulling it back](docs/screens/shift.jpg) |
| ![The rear-view mirror works: the road behind, framed by the cage](docs/screens/mirror.jpg) | ![The deep-dish suede wheel, the gloves at 9 and 3](docs/screens/wheel.jpg) |

## ⬇ Download (always the newest build)

The links never change. Every change to this folder on `main` replaces the files behind them (same as BAGHOLDERS):

- **Mac:** [ShotgunRally.zip](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/shotgun-latest/ShotgunRally.zip)
- **Mac (older Intel, pre-2020):** [ShotgunRally-Intel.zip](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/shotgun-latest/ShotgunRally-Intel.zip)
- Windows: [ShotgunRally-Windows.zip](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/shotgun-latest/ShotgunRally-Windows.zip) · Linux: [ShotgunRally-Linux.zip](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/shotgun-latest/ShotgunRally-Linux.zip)
- **Chromebook:** turn on Linux once (Settings → About ChromeOS → Developers → Linux development
  environment → Set up), download [ShotgunRally-Chromebook.deb](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/shotgun-latest/ShotgunRally-Chromebook.deb),
  double-click it in Files → Install, then open SHOTGUN RALLY from the launcher (online play works). An
  ARM Chromebook (MediaTek / Snapdragon; `chrome://version` says `aarch64`): [ShotgunRally-Chromebook-ARM.deb](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/shotgun-latest/ShotgunRally-Chromebook-ARM.deb).
  School Chromebooks often have Linux switched off: for those there's a browser version,
  [ShotgunRally-Web.zip](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/shotgun-latest/ShotgunRally-Web.zip)
  (solo play: a browser can't connect two machines), which has to be put on a web host first:
  upload the zip to [itch.io](https://itch.io) as an HTML game (free), or GitHub Pages (possible now the repo is public; not tried yet).
- All of them on one page: [releases/shotgun-latest](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/tag/shotgun-latest)
- **itch.io:** set-up steps in [`docs/ITCH.md`](docs/ITCH.md)

> The repo is **public**: the links work for anyone, no GitHub account needed.

**It updates itself.** The menu shows your build number top right. Every time you open the game
it checks for a newer build, downloads it in the background (the whole game, ~490 MB), checks it's complete, and
shows **RESTART TO UPDATE** (or it switches over by itself the next time you start it). If an
update ever fails to start, the game drops it and starts as you installed it. Some changes (a
new Godot version, new project settings) can't be sent that way: then the button says
**OPEN DOWNLOAD PAGE** and you download the zip again.
- **The first build with the updater has to be downloaded by hand once** (older copies don't
  have it).
- Playing together: both of you need the same build. If you're on different builds the game tells
  the one who joined who needs to update.

The first time you open it:
- **Mac:** unzip, double-click `SHOTGUN RALLY.app`. macOS will say it "could not verify" the app:
  open **System Settings → Privacy & Security** and click **Open Anyway**.
- **Windows:** SmartScreen may say "unrecognized app". Click **More info → Run anyway**.
- **Linux:** run `chmod +x ShotgunRally.x86_64`, then `./ShotgunRally.x86_64`.

Free, PC only (Windows, Mac, Linux). Built in **Godot 4.7**, like BAGHOLDERS.

## The home screen, story mode and the garage

The game runs behind the menu: your own car, in your colours, flat out on a stage in the evening
light, filmed like rally TV: an FPV drone chasing it (low behind, alongside, over the roof and out in
front, banking into the turns), trackside cameras it flashes past, a chase camera, a helicopter shot.

- **PLAY NOW**: a random stage, straight in, the AI co-driver on the notes.
- **MAPS**: story mode, **the Shotgun Series**: nine rallies of three stages each, every one with its
  own character: Pine Valley (short, gentle), Lakeland (fast, big jumps), Golden Hour (low sun),
  Mud & Mist (fog, puddles everywhere), Highland (narrow and twisty), Costa Mixta (gravel and
  tarmac in the same stage), Isola Rossa (dry mountain tarmac, hairpins and villages), Riviera Alps
  (snow and ice), the Grand Final (long stages). You're timed against five rival crews; finish a rally to open the next, and where you
  finish pays prize money. Drive it alone or host it for a friend.
- **CARS**: the garage. Thirteen look-alike cars with their own names (no real brands or badges).
  - **The rally cars on the shared body:** the **Kestrel R4** you start with, the blue-and-gold
    **Blue Comet WRC** (gold wheels), the white **Vortex Evo** with red and black slashes, and the
    **Martello 037** in white with navy, sky blue and red stripes (nearly all its power at the back:
    it slides). Each weighs what its real class did: R4 1,300 kg, WRC 1,230 kg, the 037 960 kg.
  - **Nine realistic cars with bodies of their own and the real cars' numbers** (weight, engine
    curve, turbo, gearbox, which wheels drive: [docs/cars.md](docs/cars.md) has the sources):
    - five stock touge cars: the rear-drive **Hachi 86** (AE86 Trueno: 120 PS, 940 kg, the
      cheapest), the front-drive **Nimbus EG** (Civic EG6: 170 PS, 1,050 kg), the rear-drive
      rotaries **Rotora FC** (RX-7 FC Turbo II: 205 PS) and **Rotora FD** (RX-7 FD: 255 PS, 50/50),
      and the **Sylph S15** (Silvia Spec-R on a widebody kit: 250 PS turbo, six-speed);
    - four rally cars: the **Kaiser 30** (E30 M3 Group A: ~290 PS, 1,050 kg, rear-drive), the
      **Martello Sedici** (Delta Integrale Group A, 1992: ~315 PS, 1,100 kg, four-wheel drive with
      the Martello's stripes), the **Vierrad S1** (Sport quattro Group B: ~455 PS, turbo lag, a
      locked centre diff), and the **Ocelot R1** (Puma Rally1: ~385 PS, spool, wings).
  - **The look** ([docs/graphics_plan.md](docs/graphics_plan.md)): on a PC or Mac the game draws
    with Godot's Forward+ renderer: photographed skies, scanned asphalt, gravel, grass and rock (all
    CC0: [docs/CREDITS_WORLD.md](docs/CREDITS_WORLD.md)), clear-coated paint, glass and chrome on the
    cars, speed blur. **SETTINGS > WORLD > TIME OF DAY** sets the hour (dawn, golden hour, night with
    the street lamps, the cars' own lamps and the city's lit windows); **SETTINGS > GRAPHICS** has
    LOW / MEDIUM / HIGH / ULTRA (LOW: flat colours and light shadows, for weak laptops) and a render
    scale. The web build and Chromebooks use the lighter Compatibility renderer. The garage shows
    each car's real power, weight and drive layout.
  - Paint any car you own (main, accent and stripe colours, free). Liveries (11, from twin stripes
    to tricolore and goldline) and wheels are bought once and fit any car, the realistic ones too.
    Pick your race number, buy three steps each of engine, tyre and brake upgrades, and pick gravel
    or tarmac tyres and setup (SETUP; AUTO matches the stage).
- **Credits** come from finishing stages: a base, more for a longer stage, a bonus for beating the
  pace and for a clean run, x1.5 in story mode, plus the rally prizes. Both players in a crew
  earn. There's no real money anywhere.
- **MODES** ([docs/modes.md](docs/modes.md)), alone or **online with up to 8 drivers**, each in
  their own car (the host picks collisions or ghosts): **TOUGE**, a Japanese mountain pass at
  night, uphill or downhill, lit only by its street lamps and your headlights, cedars streaming
  past, now and then a local driver on the road; TIME ATTACK (splits every km against your best,
  your record as a ghost) or DRIFT (points for sliding, chained); online, a race to the bottom;
  **CUT UP**, the **LAKESHORE LOOP**: one endless 28 km loop of divided highway (a city expressway
  on viaducts, three tunnels through the hills, three suspension bridges over the lakes, the
  longest with a 1,100 m main span) full of traffic. Weave through it as close as you dare, as
  long as you like (END RUN in the pause menu); on HARD and INSANE the traffic comes in packs
  across all four lanes, cars join and leave by the ramps, the other carriageway has its own.
  **Highway battles**: a rival with a nickname turns up in the traffic; get right behind it and
  flash your lights (H) to race it 3 km through the traffic to a finish gate.
- **ONLINE**: your name, host a crew (pick your seat), or join a crew or a friend's street session
  by IP.
- **SETTINGS**: mouse look, invert Y, volume, the co-driver's call timing, the driving aids for
  the new physics (each its own switch), TYRE GRIP for the rally, and **STREET HANDLING** for the
  touge and cut up: **SIM** (out of the box: each car on the road tyres it really has, its real
  skid-pad grip, no drift helpers, factory ABS: Assetto Corsa-like) or **ARCADE** (as the rally).

## How a stage plays

| | Driver | Co-driver (shotgun) |
|---|---|---|
| Sees | The road through the windshield. **No map, no minimap**: just the start lights and the stage clock. Thick forest on both sides, crests hide what's next | The **map board** in their lap: the road ahead and where the car is, nothing else. *Or* the road if they look up. Never both at once |
| Does | Steers, brakes, handbrakes, trusts | Reads the bends off the map and turns them into calls (that's the skill), counts down the start, works the **wipers** when a puddle covers the windshield in mud |
| Alone? | The **AI co-driver** calls the stage in the "Fraser" voice ("4 left, 100, over crest") from **where the car is**: each call ~2 s before its corner at the speed you're doing, one at a time, never corners you've already passed. It wipes the mud off for you too | — |

1. **Start line.** The camera circles the car on the line until the host presses ENTER; then you're
   in your seat for the 5-second countdown: **five start lights** on screen and a start clock on each
   side of the road. Moving off early is a **jump start: +10 s**. The stage clock (and any penalties)
   stays at the top of the screen.
2. **The stage** is ~2.7 km of gravel through thick forest (~30,000 trees, ferns along the verges, a far belt out to 150 m): corners graded 6 (nearly flat) to 1 (very slow) plus
   hairpins, corners that tighten or open, blind crests, jumps, puddles and wooden bridges over
   gullies with a stream in them (about one a stage, on straight level road: a plank deck that
   drives like wood, rails each side, the co-driver calls "caution"). Every stage is generated
   from a number, so there's always a new one.
   - **Room to save it:** the road's edge is flush with the grass, and it stays nearly flat for ~6 m
     before the hills start (no ditch to drop a wheel into, berms only a low ridge, the trees stand
     back 4.5 m+): run wide in a drift and you can catch it and get back on.
   - **Mountains on the horizon**, snow on the highest peaks, mist at their feet, tinted to the light
     (blue by day, warm at golden hour, grey in the fog); they keep their distance like real ones.
   - **Jumps, Finland style** (modelled on WRC Rally Finland footage): on the long straights, a gentle
     run-up, a sharp brow and a long landing slope that falls about as fast as the car flies, then a
     dip. How far you fly is up to your speed: under ~70 km/h the car stays down, at 100 km/h it's
     ~0.6 s in the air, at 120 km/h ~0.9 s, and a **big jump** (the co-driver says "caution, jump")
     ~1.1 s and 1.4 m up. Land at the right speed and all four wheels touch down together.
   - **The road's width changes**, section by section, like real gravel roads: wide and fast (6.8 m),
     normal (5.6 m), narrow and technical (4.6 m). Twisty sections lean narrow, open ones wide. The
     co-driver's numbers account for it: on a narrow road the same bend is a lower (slower) number.
   - **Spectators** stand well back behind red-and-white tape at the start, the finish, every jump
     and some of the slow corners, in bright jackets, waving flags. They jump and cheer as you come past.
   - **Tarmac and mixed stages.** A stage can also be **asphalt** all the way (dark road, white
     edge lines, a dashed centre line where it's wide enough, gravel shoulders; no jumps, wooden
     bridges or mud puddles) or **mixed**: two or three sections, gravel and asphalt in turn (like
     Rally Catalunya), each join on a straight, called "caution", with gravel dragged across the
     asphalt for 50 m after a join and on the inside of slow corners where the cars cut them (the
     co-driver adds "don't cut"). Some tarmac stages have **Monte Carlo's winter**: snow ploughed
     along an edge and **ice** across a lane ("caution, keep left") or, on a straight, the whole
     road. Each is its own surface to the tyres (asphalt 1.18 g in a corner, gravel 0.93, snow 0.42,
     ice 0.13), so it drives differently: on tarmac the car grips harder and lets go sooner, and
     a sliding tyre squeals. The co-driver's map shows the asphalt in grey and the ice in blue.
     PLAY NOW picks the surface (SETTINGS > STAGES > SURFACE: any, gravel, tarmac, mixed).
   - **Tarmac stages are mountain roads** (Monte Carlo, Corsica): the road climbs across a hillside,
     level along it and up or down as it turns across it, so pairs of hairpins make switchbacks
     (twice as many hairpins as a forest stage); a rock bank cut in above, a drop below with **armco
     or a stone wall**; sparse trees and open slopes; **villages** with houses close to the road,
     shutters, tiled roofs and a church tower; on a winter stage, snow lying about. Most have a
     **town** too: 260-360 m through the streets, buildings shoulder to shoulder right behind raised
     pavements (a kerb a wheel can hit), crowd barriers along both sides, side streets, and the
     square with its fountain and a crowd.
   - **Tyres and setup** (CARS > SETUP, free): tyres and setup each AUTO (matches the stage),
     GRAVEL or TARMAC. Tarmac tyres corner ~10 % harder on asphalt but ~25 % worse on gravel (on a
     mixed stage, a gamble); the tarmac setup (stiffer springs, dampers and anti-roll bars, a
     quicker rack) rolls about a third less.
3. **The map board** (our own design, not the reference's tablet) shows **only the map and where you
   are**: the road ahead as a line, heading-up like a GPS, ~300 m of it, with the stopwatch clipped on
   top. No grades, no warnings: reading the road and calling it is the co-driver's job.
4. **Mud:** a puddle at speed throws cartoon mud splats over the windshield: a big one right where
   the driver looks at the road, more across the glass the harder the hit, flicked droplets, and
   drips that slowly run down. The wipers smear through their two arcs (it takes about two strokes
   to see properly) and the corners stay dirty.
5. Stuck? **R** puts the car back on the road (**+5 s**). Driver: **C** swaps to a chase camera
   behind the car (the co-driver stays in their seat).
6. **Flying finish**, results (the camera circles the car again), then the host picks: next stage,
   retry, or swap seats.

### Inside the car

- **Hands that drive.** Racing gloves wrap round the rim: pre-curved fingers, the thumb across the
  rim, padded knuckles, a panel in the suit's colour on the back, and a gauntlet with a strap and a
  white edge that goes over the sleeve and turns with the forearm. Turn and the hands go with
  the wheel; past where an arm can go, one hand lets go and takes a new grip further round
  (hand-over-hand, never two at once, so the driver's arms never twist), and back near straight
  they drift home to 9 and 3. **Handbrake:** the right hand drops off the wheel, grabs the tall
  hydraulic lever beside the seat and yanks it back, then goes back to the wheel. **Gear
  changes:** at every change the right hand flicks across to the sequential lever, pulls it back
  (up a gear) or pushes it forward (down) and is back on the wheel in about a third of a second;
  with the wheel wound round past ~70 degrees it stays on the wheel.
- **Belted in.** Both crew wear six-point harnesses fitted to their bodies as they sit: the
  shoulder straps come off the harness bar, through the seat's slots, over the shoulders (padded)
  and down the chest; lap belts over the thighs; crotch straps; steel adjusters and a round
  cam-lock buckle. Each strap is laid on the posed body like a tight strap (pulled straight, pushed
  out of the suit, turned to lie flat on it), once when the stage loads.
- **A real cockpit,** stripped out like a rally car: bucket seats (a Higgsfield model) and a
  350 mm deep-dish suede wheel like a Momo Mod.08 (yellow marker at 12, three black spokes with
  slots machined out, horn button, six bolts, quick-release boss); a black flock dash (no glare in the windshield) with numbered dials (revs
  0-8 x1000 with the red line, km/h 0-200), a green gear digit and **shift lights** that climb
  green, yellow, red with the revs and flash on the limiter; a **switch panel** (ignition under a
  red flip guard, START, the FIRE button, labelled toggles); a tall **sequential gear lever** and
  the hydraulic handbrake; carbon door cards with red pull straps; a wide rear-view mirror **that
  works** (a camera behind the glass looks back down the car: the cage, the rear window, the road
  behind) and a sun strip; the co-driver's trip meter, map lamp and
  ribbed aluminium footrest; a fire extinguisher, padding and a spare wheel strapped down in the back.
- **Each car's own interior.** The cars with realistic bodies keep the interior their model came
  with (dash, seats, door cards, its own steering wheel, gear lever and handbrake), and the crew fit
  into it: they sit in its seats at real size, on the right in a right-hand-drive car (the HACHI,
  NIMBUS and SYLPH) with the co-driver and the map board on the left. The gloves grip and turn its own
  wheel; the hand nearer the middle works its own gear lever: an H-pattern through the gates, a
  sequential pulled and pushed, an automatic left alone (the hand stays on the wheel); its own
  handbrake comes up. Its own rear-view mirror shows the road behind, and the mud and the wipers
  go on its windshield. Cars whose interior is too rough to sit in (both ROTORAs) and the four on
  the shared body get the rally cockpit above. See [docs/cars.md](docs/cars.md).
- **The car outside** has its own wheels now: they steer, spin and move up and down with the
  suspension, and the mud flaps swing behind them.
- **Drift dirt** (modelled on WRC Sardinia and Finland footage): slide, flick the handbrake or
  throw it sideways and the tyres kick up lumpy cartoon dust clouds, warm on top and dark
  underneath, that swell to a couple of times the car's height, hang for a few seconds drifting
  downwind and break up into lumps. A low dark ribbon of gravel roosts straight back off the tyres
  and stones fan out to the outside of the slide, bouncing once; landing a jump throws up a burst.
  Mostly off the rear wheels. Tan off gravel, brown off dirt, clods off mud, green bits off the
  grass; at speed a light trail follows the rear wheels. Your co-driver sees the same spray.
- **Loading screen:** the stage number, how long it is and how many corners, a rally tip, and a
  progress bar that follows the build ("Planting ten thousand trees..."). It stays up through the
  first frames of the stage, which stutter while the graphics warm up, then fades out.

### The engine sound (markeasting/engine-audio's, each car its own engine type)

The engines are [markeasting/engine-audio](https://github.com/markeasting/engine-audio)'s sounds,
played its way. Each set is four loops: on the throttle and off it, low and high in the revs. Its
equal-power crossfades blend low into high between 3,000 and 6,500 rpm and on into off with the
throttle, and each loop is pitched up and down with the revs. A limiter loop comes in at the top of
the revs (the engine cuts and fires against it), and its gearbox whine rises with the revs and the
gear, loud on a straight-cut rally box.

Each car has an engine type (`EngineSound.ENGINES`):
- **Four-cylinders** play a BAC Mono's racing four:
  - **WRC** (Kestrel, Comet, Vortex, Ocelot): with anti-lag crackle and pops (from the Fiesta WRC
    recordings), a turbo whistle and a bang on every shift.
  - **Group A** (Sedici): a turbo, pops on a lift.
  - **Martello 037**: the supercharger's whine.
  - **Race four** (Kaiser), **road four** (Nimbus, Hachi: no pops, a quiet gearbox) and **road turbo**
    (Sylph: the blow-off valve hisses when you lift).
- **Vierrad** (the five-cylinder quattro) plays a BMW M1 Procar's straight six, the nearest.
- **Both Rotoras** play a Ferrari 458's V8, for the rotary's high-revving scream, with a turbo and a
  blow-off.

The co-driver's machine hears the same. Every effect dips ~10 dB whenever the co-driver talks
(SETTINGS: EFFECTS and CO-DRIVER VOICE). Where the sounds come from, and a licence note (not cleared
for a public release): [tools/engine_sound/README.md](tools/engine_sound/README.md).

### The car's physics (v2: in the game)

The car's physics, closer to Dirt Rally / RBR
([docs/physics_rebuild.md](docs/physics_rebuild.md)): a RigidBody3D chassis on four ShapeCast tyres
with real suspension, then tyres, drivetrain, surfaces, aero and driver aids (each its own switch),
in nine tested phases, at 120 Hz. **All nine are done:** the chassis on its springs, dampers
and bump stops; the tyres' grip sideways (slip angle) and along (slip ratio), sharing one patch of
rubber (brake in a corner and it runs wide; trail-brake into one and it rotates), a loaded tyre
gripping less per newton; each wheel spinning on its own, brakes that lock a wheel only when they
beat its grip; Ackermann steering; a turbo engine (400 N m, 307 hp, anti-lag), a clutch that slips
it away, a five-speed sequential box (0-100 km/h in 4.2 s, as a Fabia Rally2), and Rally2-style four-wheel drive (no
centre diff, limited-slip diffs front and rear: put a wheel on ice and it still pulls away);
surfaces, each wheel on its own (asphalt, wet asphalt, gravel, dirt, snow, ice, mud, grass: their
grip, where it peaks, what a sliding tyre keeps, rolling resistance; 1.14 g on asphalt, 0.90 on
gravel, 0.41 on snow, 0.13 on ice); a hydraulic handbrake that lets the rear axle's drive go
(the rears lock, the fronts keep driving), anti-roll bars (2.75 degrees of roll per g) and
two-stage dampers (firm for the body, soft for sharp hits); aero (drag, ~60 kg of downforce at 150
km/h); seven driver aids, each its own switch in **SETTINGS** (ABS, traction control, stability
control, steering smoothing, damping, countersteer help, speed-sensitive steering: all off is the
car as it is, and with them on it's the same car until you reach the limit); telemetry you can
record to a CSV (F2); and the rally tuning, tested as manoeuvres: lift-off oversteer, power
oversteer, a four-wheel drift held, a countersteer catch, the Scandinavian flick, a pendulum slide
to slide. Try it in
the physics lab (`godot --path . scenes/physics_lab.tscn`: arrows steer / throttle / brake, space handbrake,
E / Q gears, C tow, R reset, J drop, B / N bumps, P / O slope, 1-8 surface pads, 9 split pad, F5-F12
aids, F2 record, F3 telemetry, F4 force arrows).

**In the game now.** It replaced the first car (October 2026): the same game around it (cockpit,
dust, sound, the co-driver's stream, the garage's power / grip / brakes / drive split), 120
physics ticks a second. Out of the box five aids are on: steering smoothing and speed-sensitive
steering, countersteer help (without it, holding the speed at the limit at 110 km/h spins it),
drift assist and high-speed stability (below); switch any of them in SETTINGS. Countersteer help was retuned
after "I'm going into drift for no reason": at 100 km/h off the throttle, a keyboard lane change
(right half a second, left half a second) or full lock held a second and let go spun the car
(~80 deg sideways); now it slides 10-12 deg and straightens (the help points the front wheels
fully where the car's going once the tail's 10 deg out, instead of 70 % of the way, which left
them still pushing it round), and speed-sensitive steering gives a key press only what the tyres
can use. Then "it's just super slippery": real gravel tyres (0.9 g in a corner, 85 % of the grip
kept in a slide) feel like ice to most players, so **SETTINGS > TYRE GRIP** adds grip on top of
the real tyres. **ARCADE, out of the box,** drives like a GTA V / FiveM rally car, built from
their handling.meta numbers (the rally-ish cars: a sliding tyre keeps ~82-90 % of its grip, and
off tarmac it loses only ~0.4 of what it would): 1.42 g in a corner on gravel and 1.48 on asphalt
(gravel 96 % of asphalt; on the real tyres 81 %), 100-0 km/h in 28 m on either, a sliding tyre
keeps 95 % of its grip so a slide builds slowly and holds, the loose gravel at the edges costs 0.4
of what it does; handbrake turns still swing it round (105-110 deg), and a keyboard lane change at
100 km/h slides 14 deg and straightens. Snow, mud and ice are still slippery, just less. GRIPPY
(the step before): on gravel 1.20 g instead of 0.93, 100-0 km/h in 34 m instead of 47; asphalt
1.30 g instead of 1.15. MORE GRIP: 1.33 g on gravel. REAL: the tyres as they are (the physics
tests run on those). Settings saved on GRIPPY (the old out of the box) move to ARCADE once; any
other choice stays. Then "I spin out every time I drift" and "the car flips over a lot while
turning": it was mostly rolling over. Anti-roll bars only share the load across an axle and keep
the body flatter; a car tips once its tyres grip harder than its track and centre of mass allow
(~1.6 g here), and ARCADE on tarmac tyres grips ~1.9 g, so full lock at 80-110 km/h, a flick, or
a corner over bumps rolled it onto its roof (6 of 30 hard-turning cases). Now, on any extra grip,
a **tip guard** pushes a side that lifts in a corner back down (0 of 90 cases tip; 8 deg of roll
at most; in the air it leaves the car alone, so jumps land as before).

**Handling for touge and cutting up (October 2026).** "It doesn't feel connected." Measured
first (tests/feel_check.gd: scripted drives on keys and on a stick, the 4WD and the rear-drive
car), the causes were: countersteer help took over 50-67 % of the front wheels in a drift
(steering into it left them countersteering, and it straightened every drift); speed-sensitive
steering *capped* the angle, so above ~100 km/h any key or a fifth of a stick already asked for all
the grip and the rest did nothing (twitchy and numb at once); ARCADE's tarmac tyres gripped 1.9 g
and a sliding rear kept 95 %, so it gripped straight back up (drifts died at 10-20 deg flat out)
and a car tipped; and the squeal only came on at the limit. Now:
- **Steering asks for a share of the grip**: half a stick, half of what the front tyres can give
  at that speed (all of it: 98 %), through the tyre's own curve; keys ramp in (slower at speed:
  a tap at 200 km/h is a small correction), a stick is left almost raw (0.04 s).
- **DRIFT ASSIST v2**: in a drift your steering sets the angle: into the corner more (up to ~40
  deg on the throttle), let go and it eases straight, countersteer and it straightens quicker;
  it steers the fronts (a little inside the slide, so they carry their share) and turns the body
  toward that angle, damped, and never lets it spin. With it on it does countersteer help's job.
  Below ~25 km/h it steps aside: a slow handbrake U-turn or a tight hairpin goes round just as it
  would with it off.
- **ARCADE on tarmac**: x1.1 instead of x1.3 (1.44-1.51 g on tarmac tyres), a sliding or
  spinning rear keeps 85 % (the throttle holds a drift), the grip peaks later on asphalt
  (progressive); gravel x1.65 (1.44 g).
- **HIGH-SPEED STABILITY** (its own switch, on out of the box): from ~90 km/h, yaw the steering
  didn't ask for (a wobble, a clipped tail) is damped; it stays out of a drift you're steering.
- **The squeal warns**: it follows how much of each tyre's grip is in use: 0.3 at 80 % of the
  limit, 0.6 at 90 %, full in a slide (it was 0.1 at 90 %, then full on).
- REAL tyres with every aid off is the pure sim, unchanged (1.36 g, no aid holds anything).

| (out of the box, keys / stick) | before | after |
|---|---|---|
| drift angle, steering into it (RWD) | 13 / 13 deg | 28 / 21 deg |
| half a stick into it | 12 deg (same as full) | 11 deg (half of full) |
| let go in a drift: straight in | 0.96 s | 0.42 s |
| a long drift held (of 6.4 s) | 1.4 / 1.4 s | 3.9 / 6.1 s |
| lane change at 200 km/h: corrections the driver needs | 41-43 | 1 |
| a quick weave at 250 km/h: slip / settles in | 9.9 deg / 1.26 s | 1.2 deg / 0.12 s |
| a 0.15 s tap at 200 km/h turns it | 21 deg | 1 deg |
| clipped on the rear corner at 150: slip / straight in | 31 deg / 1.3 s | 14 deg / 0.36 s |
| a fifth of the stick vs half at 200 km/h | 95-98 % | 48-58 % |
| squeal at 80 / 90 % of the limit | 0.08 / 0.10 | 0.31 / 0.56 |
| tarmac grip | 1.86-1.90 g | 1.44-1.51 g |

Braking from 200 km/h stays straight (98-102 m). Every manoeuvre has a pass/fail limit in
tests/feel_check.gd (run on both cars in the suite), plus tests/drift_check.gd. The autopilot (the tests'
driver, the menu's car) steers like a driver: the curve it wants, the slip angle the tyres need
for it, countersteer when the tail steps out. Found on the way, all fixed: a bottomed-out wheel
read as "no compression" (big landings slammed the body down), a car put down somewhere new kicked
itself into the air (its suspension remembered the old spot), braking in the air didn't dip the
nose (the wheels now hand their spin to the body), and the bump stop's damping hit all at once
(now it builds over the last 8 cm: the big jump lands at 11 g instead of 16).

### How the car drives

Rebuilt from research on real rally tyres and rally games (DiRT Rally, Richard Burns Rally, Assetto
Corsa's gamepad assist; sources in the commit history):

- **Steering asks the front tyres for grip, not for an angle.** Full steering = the most the front
  tyres can do at that speed (their peak slip angle), wherever the car is pointing, so on keys or a
  stick you never steer past the limit and plough on (that was the "always understeering" feeling).
  Full opposite lock in a slide = the most countersteer. At parking speeds it's plain steering.
- **Gravel tyres:** grip builds to a peak at ~8 deg of slip and then fades slowly (a gravel tyre
  pushes a little bank of stones), so a slide is something you drive.
- **Weight transfer matters:** each tyre grips a bit less per kilo the more it's loaded, and the
  forces act at the contact patches. Brake or lift into a bend and the loaded nose bites; a light
  tail steps out. The handbrake locks the rears and declutches them (all the power to the front,
  like a real Rally2 car) for the hairpin flick.
- **Grippy on purpose:** ~0.95 g of cornering on gravel, a bit more than a real Rally2 car (~0.8 g),
  and the steering answers fast: on keys it comes on fully in ~0.17 s and centres in ~0.12 s. 0-100 km/h in 4.3 s (a Rally2 car: ~4.2 s), 45 / 55 AWD.
- **Wheels that spin and lock.** Each wheel has its own spin, so the tyres slip forwards as well as
  sideways and share one grip between the two: a launch spins the rears up a little, and power or
  brakes mid-corner eat into the cornering grip. Rally cars have no ABS: **full brake while
  turning locks a front wheel and the car stops steering**. Brake in a straight line, then turn
  in (the brake key comes on over a quarter of a second; a trigger is analog). The diffs are
  limited-slip, locking under power and letting go off it.
- **Where you drive on the road matters.** The two darker worn wheel tracks grip best, the loose
  crown between them a little less, and the "marbles" out toward the edges least (down to 84 %),
  so running wide costs you. The gravel is looser (lighter) where the grip is worse, and it piles up in
  berms on the outside of the bends.
- **In the air** it flies as it was launched (nothing steers it), and the pedals work like a real
  car's: **brake in the air and the nose drops** (the wheels stop and hand their spin to the body,
  ~14 deg over a big jump), gas lifts it a little. Landings squash the springs once and stay
  down: the dampers soak up a big landing deep in their travel instead of throwing the car back up.
- **A calmer ride.** The bouncing came from three things, all fixed: the hills were too steep
  (up to 31 %: now at most 16 %, smoothed, and crests land gently), the springs hit a hard stop on
  big landings (now a progressive bump stop, softer damping on the way down, and tyres that give a
  little), and the camera was bolted to the car (now your head sits on a neck that soaks up the
  jolts). The shaking at the driver's eye went from 8.6 to 4.0 m/s² on stage 3 and from ~12 to 3.5
  on stage 15; the hardest landing from 20–25 g to 4–8 g (`tests/ride_check.gd` measures it).
- **No more shaking when the frame rate drops.** The head's neck spring was worked out once per
  frame, so below ~20 fps it went unstable and slammed the view 6 cm up and down every frame: the
  car seemed to bounce very fast with nothing on the road. It now steps in fixed 1/120 s steps at
  any frame rate (`tests/view_check.gd` runs the view at 144 down to 12 fps and through hitches).
- `tests/handling_check.gd` measures it: at 50 / 80 / 110 km/h full steering has to be the most
  grip (before the rework, full steering at 110 km/h gave 0.68 g and 25 % gave 0.80 g).

**SIM STREET handling (October 2026).** "Assetto Corsa-style handling" for the touge and cut
up: Settings > STREET HANDLING > SIM (out of the box) puts each car on the road tyres it really
has. Its asphalt grip is set so it holds its real skid-pad figure (measured where magazines
published one: GR Supra 1.07 g, GT-R 1.00, Hellcat ~0.93, 911 GT3 RS 1.24; estimated by age
and tyre otherwise), the grip peaks at a road tyre's 7.5 deg and a sliding one keeps 85 %, it
brakes at ~1.1x its cornering grip with the balance following the weight, and there's no drift
assist or countersteer help (factory ABS and traction control where the real car has them;
HIGH-SPEED STABILITY stays a Settings switch).
`tests/sim_check.gd` measures nine cars on a skid pad and from 100 km/h: all within 6 % of their
real figures (the Supra 1.06 g and 37 m). ARCADE keeps the rally's grip for those who'd rather.
Details: [docs/modes.md](docs/modes.md).

## Controls

| | Keyboard / mouse | Controller |
|---|---|---|
| Steer | A / D, ← / → | left stick |
| Gas / brake (hold brake when stopped = reverse) | W / S, ↑ / ↓ | RT / LT |
| Handbrake | SPACE | B / X |
| **Co-driver:** look at the map | hold RIGHT MOUSE or Q | hold LT |
| **Co-driver:** wipers (the driver's job when alone) | F | A |
| Look around | mouse | right stick |
| Reset car (+5 s) | R | Y |
| **Driver:** chase camera on / off | C | right stick click |
| **Cut up:** flash your lights (challenge the rival ahead) | H | LB |
| Start / next stage (host) | ENTER | START |
| Pause | ESC | BACK |

## Play with friends

1. One person opens **ONLINE** and clicks **HOST · I DRIVE** or **HOST · I RIDE SHOTGUN** (or hosts a story rally
   from **MAPS**). The other seat is the friend's. The driver's car from their garage is the car on the stage.
2. The friend types the host's IP and clicks **JOIN**. The port is 7777.
   - **Same Wi-Fi / same house:** the host's local IP (shown on the host's screen while it waits).
   - **Different houses (easiest):** both install **[Tailscale](https://tailscale.com)** (free) and
     join with the host's `100.x.y.z` address. No router setup.
   - **Different houses (advanced):** the host forwards **UDP 7777** on their router.
3. Use Discord (or any voice chat) to talk. Yelling is the game.

**Racing each other (up to 8):** the host opens **MODES**, picks **HOST ONLINE (UP TO 8)** and
**COLLISIONS: ON** or **GHOSTS**, then starts a touge or a cut-up difficulty; everyone else
JOINs from ONLINE as above, each in their own garage car. A touge is first to the bottom (the
results show the podium); in cut up the host's traffic is everyone's.

The driver's computer runs the car and streams it to the co-driver ~30 times a second; the
co-driver's screen plays it back 0.1 s behind, smoothly, so the passenger seat never jitters.

## Based on *Left Left Left!*

Inspired by ***Left Left Left!*** ([@leftleftleftgame on TikTok](https://www.tiktok.com/@leftleftleftgame)):
two players in one car, both in first person, one with the map. The breakdown of the four reference
clips is in [`docs/VIDEO_BREAKDOWN.md`](docs/VIDEO_BREAKDOWN.md).

What's ours: the name and look, **our own map device** (a wooden map board), **the real
co-driver's jobs** ([`docs/CO_DRIVER_JOBS.md`](docs/CO_DRIVER_JOBS.md)), and an **AI co-driver** with a
real voice.

## Roadmap

| Phase | What | Status |
|---|---|---|
| 0 | Reference breakdown, name, plan, co-driver research, voice pack | ✅ done |
| 1 | **Playable grey box:** generated forest gravel stages, raycast rally car, first-person driver + co-driver seats, the co-driver's map board, mud + wipers, start countdown, jump starts, resets, results, 2 players online, builds | ✅ done |
| 2 | **AI co-driver** | ✅ basic version done (calls by time, countdown, finish). Next: quick-call wheel for the human co-driver, call-timing setting in the menu, more lines |
| 3 | **Art:** the car is a Higgsfield model (concept art -> 3D); the crew are your racer (rigged, posed in their seats: hands on the wheel / the map board, heads turning where the player looks), the car's wheels and mud flaps move, racing gloves + hand-over-hand steering, a stripped rally interior (numbered dials, shift lights, switch panel, sequential lever, a deep-dish wheel, a working mirror), six-point harnesses fitted to the crew, the hand reaching for the lever at each gear change, the loading screen; next: better trees | car + crew + cockpit ✅ |
| 4 | **Jobs + content:** OK board, warning triangle, pushing the car, punctures, time cards, road book, recce mode, more biomes, wooden bridges, street (tarmac) and mixed-surface stages ([the plan](docs/street_and_mixed_maps.md)) | bridges ✅, tarmac + mixed stages ✅ |
| 5 | Polish, crews racing each other | |

## Run from source / keep building it

1. Install **Godot 4.7** (free) and open the `shotgun-rally/` folder (its `project.godot`), or run
   `godot --path shotgun-rally` from the repo root.
2. Tests (headless, ~6 minutes): `GODOT=/path/to/godot shotgun-rally/tests/run_all.sh`
   - compiles every script; checks 20 generated stages (deterministic, never crossing themselves,
     every corner gets a note, no hill steeper than 17 %)
   - the autopilot drives whole stages: 0–100 km/h on gravel, braking, the handbrake flick; and a
     mountain tarmac stage with snow and ice and a mixed one, the tyres feeling each surface, the
     barriers and villages there
   - stages: tarmac and mixed rules (no jumps, bridges or mud on asphalt, joins on straights and
     called, ice never in a slow corner), mountains (the hillside meets the road, more hairpins,
     villages on the asphalt), every word the co-driver says has a voice clip
   - tyres and setup: tarmac tyres corner harder on asphalt and far worse on gravel, the tarmac setup
     rolls less at the same ride height, AUTO picks for the stage
   - handling: full steering is the most grip at 50 / 80 / 110 km/h; lift-off and handbrake turns rotate the car;
     a launch spins the wheels a little; full brake while steering locks a front, half brake still steers
   - ride: how much the car shakes at the driver's eye on two stages, and the hardest landing
   - view: the driver's eye at 144 down to 12 fps and through hitches, never shaking frame to frame
   - sound: the engine's loops blend by the revs, it sounds its shifts and pops, the co-driver is over the effects
   - jumps: air time by speed (a hop at 80 km/h, ~0.9 s at 120, longer off a big jump), landings on all
     four wheels within 12 deg of the slope, no second bounce, still on the road, and braking in the air dips the nose
   - drift dirt: dust and stones when the car slides, a light trail at speed, a burst on landing, nothing when cruising or in the air
   - garage + story: stage credits, buying (not without the money, not twice), upgrades, car setups, rallies
     unlocking in order, the standings and prizes, the save reloading
   - road edges: the ground is flush with the road's edge and flat for 6 m past it (no ditch, no lip), the
     trees stand back, and running wide at 70 km/h you can get back on the road
   - the cockpit: the driver's sleeves are skinned on the CPU with the hands on the wheel (straight, turned both
     ways) and on the handbrake, and every sleeve end has to be inside its glove's gauntlet; numbered dials; shift lights
   - interiors: each car with one of its own keeps it; the driver's eyes are in it on its wheel's side, the gloves
     on its rim, the steering turns its wheel, the hand takes its lever through the gates (or pulls a sequential,
     or stays put in an automatic) and pulls its handbrake
   - the AI co-driver says every call in time (90–240 m before the corner)
   - **2 players, both ways round:** one machine drives, the other rides along; both see the finish,
     and on a mixed stage both built the same surfaces
   - **the updater, start to finish:** a "build 5" copy finds "build 6" on a local web server,
     downloads it, checks its SHA-256, restarts as build 6; a bad download is thrown away, an update
     that never reached the menu is dropped
3. Screenshots without a screen: `xvfb-run godot --path shotgun-rally -- --seed=11 --screenshot=out.png --shot_seat=codriver --shot_read`
   (more options at the top of `scripts/main.gd`: look around, chase view, steering, handbrake, the loading screen)
4. **Releasing:** push to `main`. CI tests it, builds the zips, stamps the build number, and
   uploads the zips plus the update pack (`ShotgunRally.pck` + `version.json`) to the
   `shotgun-latest` release. Everyone's game picks it up the next time they open it.

| Folder | What's in it |
|---|---|
| `scripts/stage/` | the stage generator, the pacenotes, the world builder |
| `scripts/vehicle/` | the rally car, cockpit + crew, map board, seat camera, AI co-driver, autopilot |
| `scripts/net/` | settings, the input map, the 2-player connection, the updater |
| `scripts/ui/` | the menu, the loading screen, the start lights |
| `assets/voice/fraser/` | the co-driver voice clips (new lines: [`assets/voice/fraser/README.md`](assets/voice/fraser/README.md)) |
| `tests/` | the headless tests |
| `docs/` | the plan, the reference breakdown, co-driver research, itch.io set-up, the car references, the physics rebuild plan |

## Credits & notes

- The cars' sources, authors and licences (and what to settle before any public release):
  [`docs/CREDITS.md`](docs/CREDITS.md), generated from the vehicle registry.
- Car and seats: made with Higgsfield (GPT Image concept art -> Meshy
  image-to-3D), from your account; the loading screen art too. The concept art is in
  `docs/reference/models/`.
- The crew: your racer (the Claude Racer character: a Mixamo-rigged F1-style driver with 2K PBR
  textures), made game-ready by `tools/import_crew.py` (bones named for the game, one mesh, the
  textures wired up; the co-driver's suit dyed blue). The original files aren't in the repo.
- Co-driver voice: Higgsfield Seed Audio 1.0, preset voice "Fraser", made for the Rally Co-Driver
  GPS app ([driver-test-app](https://github.com/pbelfand-dot/driver-test-app)).
- Sound effects are synthesized (`tools/make_sfx.py`, plus BAGHOLDERS' engine / crash / bell sounds,
  also synthesized). No samples.
- Font: [Oswald](https://github.com/googlefonts/OswaldFont), SIL Open Font License (`assets/fonts/OFL-Oswald.txt`).
- *Left Left Left!* belongs to its creator. We borrow the idea of the game, not their art, name or UI.
