# SHOTGUN RALLY

![SHOTGUN RALLY: you drive, your friend rides shotgun with the map](docs/screens/banner.jpg)

**You drive. Your friend rides shotgun with the map.** A cartoony 2-player online co-op rally
game. One of you drives, blind past the next crest. The other sits in the passenger seat with a
map of the road ahead, works out what's coming and yells it: "LEFT! TIGHT LEFT! OVER THE CREST!"
No friend online? The **AI co-driver** takes the seat.

> SHOTGUN RALLY lives in this `shotgun-rally/` folder, next to BAGHOLDERS on `main`. It's its own Godot
> project with its own build, so the two games never touch each other. Both games' downloads are on
> the [repo's front page](../README.md).

| | |
|---|---|
| ![Driver](docs/screens/driver.jpg) | ![Co-driver looking at the map](docs/screens/codriver.jpg) |
| ![Mud on the windshield](docs/screens/mud.jpg) | ![The start: five lights and a clock each side of the road](docs/screens/start.jpg) |
| ![Your co-driver, seen from the driver's seat](docs/screens/crew.jpg) | ![The chase camera (C): the wheels steer and bounce, the mud flaps swing](docs/screens/chase.jpg) |
| ![Handbrake: the right hand leaves the wheel and yanks the lever](docs/screens/handbrake.jpg) | ![The loading screen](docs/screens/loading.jpg) |

## ⬇ Download (always the newest build)

The links never change. Every change to this folder on `main` replaces the files behind them (same as BAGHOLDERS):

- **Mac:** [ShotgunRally.zip](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/shotgun-latest/ShotgunRally.zip)
- **Mac (older Intel, pre-2020):** [ShotgunRally-Intel.zip](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/shotgun-latest/ShotgunRally-Intel.zip)
- Windows: [ShotgunRally-Windows.zip](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/shotgun-latest/ShotgunRally-Windows.zip) · Linux: [ShotgunRally-Linux.zip](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/shotgun-latest/ShotgunRally-Linux.zip)
- All of them on one page: [releases/shotgun-latest](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/tag/shotgun-latest)
- **itch.io:** set-up steps in [`docs/ITCH.md`](docs/ITCH.md)

> While this repo is **private**, the links only work for people with access to it.

**It updates itself.** The menu shows your build number top right. Every time you open the game
it checks for a newer build, downloads it in the background (a few MB), checks it's complete, and
shows **RESTART TO UPDATE** (or it switches over by itself the next time you start it). If an
update ever fails to start, the game drops it and starts as you installed it. Some changes (a
new Godot version, new project settings) can't be sent that way: then the button says
**OPEN DOWNLOAD PAGE** and you download the zip again.
- **The first build with the updater has to be downloaded by hand once** (older copies don't
  have it).
- **While the repo is private** the game can't reach the update files: it says so and the button
  opens the download page instead. Once the repo is public, updates just work, nothing to change.
- Playing together: both of you need the same build. If you're on different builds the game tells
  the one who joined who needs to update.

The first time you open it:
- **Mac:** unzip, double-click `SHOTGUN RALLY.app`. macOS will say it "could not verify" the app:
  open **System Settings → Privacy & Security** and click **Open Anyway**.
- **Windows:** SmartScreen may say "unrecognized app". Click **More info → Run anyway**.
- **Linux:** run `chmod +x ShotgunRally.x86_64`, then `./ShotgunRally.x86_64`.

Free, PC only (Windows, Mac, Linux). Built in **Godot 4.7**, like BAGHOLDERS.

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
2. **The stage** is ~2.7 km of gravel through thick forest (~10,000 trees): corners graded 6 (nearly flat) to 1 (very slow) plus
   hairpins, corners that tighten or open, crests, jumps, puddles and rocks on the inside of the
   "don't cut" corners. Every stage is generated from a number, so there's always a new one.
3. **The map board** (our own design, not the reference's tablet) shows **only the map and where you
   are**: the road ahead as a line, heading-up like a GPS, ~300 m of it, with the stopwatch clipped on
   top. No grades, no warnings: reading the road and calling it is the co-driver's job.
4. **Mud:** a puddle at speed covers the **whole windshield**. The wipers clear their two arcs, a bit
   more each stroke (it takes about two to see properly), and the corners stay dirty.
5. Stuck? **R** puts the car back on the road (**+5 s**). Driver: **C** swaps to a chase camera
   behind the car (the co-driver stays in their seat).
6. **Flying finish**, results (the camera circles the car again), then the host picks: next stage,
   retry, or swap seats.

### Inside the car

- **Hands that drive.** Gloves wrap round the rim, fingers and thumb. Turn and the hands go with
  the wheel; past where an arm can go, one hand lets go and takes a new grip further round
  (hand-over-hand, never two at once, so the driver's arms never twist), and back near straight
  they drift home to 9 and 3. **Handbrake:** the right hand drops off the wheel, grabs the tall
  hydraulic lever beside the seat and yanks it back, then goes back to the wheel.
- **A real cockpit:** bucket seats and a three-spoke suede wheel (Higgsfield models), a dial
  binnacle (revs, speed, gear), the co-driver's trip meter, a fire extinguisher, padding and mats.
- **The car outside** has its own wheels now: they steer, spin and move up and down with the
  suspension, and the mud flaps swing behind them.
- **Loading screen:** the stage number, how long it is and how many corners, a rally tip, and a
  progress bar that follows the build ("Planting ten thousand trees..."). It stays up through the
  first frames of the stage, which stutter while the graphics warm up, then fades out.

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
- **A calmer ride.** The bouncing came from three things, all fixed: the hills were too steep
  (up to 31 %: now at most 16 %, smoothed, and crests land gently), the springs hit a hard stop on
  big landings (now a progressive bump stop, softer damping on the way down, and tyres that give a
  little), and the camera was bolted to the car (now your head sits on a neck that soaks up the
  jolts). The shaking at the driver's eye went from 8.6 to 4.0 m/s² on stage 3 and from ~12 to 3.5
  on stage 15; the hardest landing from 20–25 g to 4–8 g (`tests/ride_check.gd` measures it).
- `tests/handling_check.gd` measures it: at 50 / 80 / 110 km/h full steering has to be the most
  grip (before the rework, full steering at 110 km/h gave 0.68 g and 25 % gave 0.80 g).

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
| Start / next stage (host) | ENTER | START |
| Pause | ESC | BACK |

## Play with friends

1. One person clicks **HOST · I DRIVE** or **HOST · I RIDE SHOTGUN**. The other seat is the friend's.
2. The friend types the host's IP and clicks **JOIN**. The port is 7777.
   - **Same Wi-Fi / same house:** the host's local IP (shown on the host's screen while it waits).
   - **Different houses (easiest):** both install **[Tailscale](https://tailscale.com)** (free) and
     join with the host's `100.x.y.z` address. No router setup.
   - **Different houses (advanced):** the host forwards **UDP 7777** on their router.
3. Use Discord (or any voice chat) to talk. Yelling is the game.

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
| 3 | **Art:** the car and both crew are Higgsfield models (concept art -> 3D, the crew rigged and posed in their seats: hands on the wheel / the map board, heads turning where the player looks), the car's wheels and mud flaps move, gripping gloves + hand-over-hand steering, the interior, the loading screen; next: better trees | car + crew + cockpit ✅ |
| 4 | **Jobs + content:** OK board, warning triangle, pushing the car, punctures, time cards, road book, recce mode, more biomes | |
| 5 | Polish, crews racing each other | |

## Run from source / keep building it

1. Install **Godot 4.7** (free) and open the `shotgun-rally/` folder (its `project.godot`), or run
   `godot --path shotgun-rally` from the repo root.
2. Tests (headless, ~6 minutes): `GODOT=/path/to/godot shotgun-rally/tests/run_all.sh`
   - compiles every script; checks 20 generated stages (deterministic, never crossing themselves,
     every corner gets a note, no hill steeper than 17 %)
   - the autopilot drives whole stages: 0–100 km/h on gravel, braking, the handbrake flick
   - handling: full steering is the most grip at 50 / 80 / 110 km/h; lift-off and handbrake turns rotate the car
   - ride: how much the car shakes at the driver's eye on two stages, and the hardest landing
   - the AI co-driver says every call in time (90–240 m before the corner)
   - **2 players, both ways round:** one machine drives, the other rides along; both see the finish
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
| `docs/` | the plan, the reference breakdown, co-driver research, itch.io set-up |

## Credits & notes

- Car, crew, seats and steering wheel: made with Higgsfield (GPT Image concept art -> Meshy
  image-to-3D, the crew auto-rigged), from your account; the loading screen art too. The concept
  art is in `docs/reference/models/`.
- Co-driver voice: Higgsfield Seed Audio 1.0, preset voice "Fraser", made for the Rally Co-Driver
  GPS app ([driver-test-app](https://github.com/pbelfand-dot/driver-test-app)).
- Sound effects are synthesized (`tools/make_sfx.py`, plus BAGHOLDERS' engine / crash / bell sounds,
  also synthesized). No samples.
- Font: [Oswald](https://github.com/googlefonts/OswaldFont), SIL Open Font License (`assets/fonts/OFL-Oswald.txt`).
- *Left Left Left!* belongs to its creator. We borrow the idea of the game, not their art, name or UI.
