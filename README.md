# SHOTGUN RALLY

**You drive. Your friend rides shotgun with the notes.** A cartoony 2-player online co-op rally
game. One of you drives, blind past the next crest. The other sits in the passenger seat with the
roadbook and yells the road at you: "LEFT 3! DON'T CUT! OVER CREST!" No friend online? The **AI
co-driver** takes the seat.

> This is the rally game's own branch (`shotgun-rally`) in the BAGHOLDERS repo. Nothing here touches
> the trading game on `main`.

## ⬇ Download (always the newest build)

> **No build yet.** These links start working when the first playable build is pushed (phase 1 below).
> They're set up the same way as BAGHOLDERS: the links never change, and every update replaces the
> files behind them.

- **Mac:** [ShotgunRally.zip](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/shotgun-latest/ShotgunRally.zip)
- **Mac (older Intel, pre-2020):** [ShotgunRally-Intel.zip](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/shotgun-latest/ShotgunRally-Intel.zip)
- Windows: [ShotgunRally-Windows.zip](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/shotgun-latest/ShotgunRally-Windows.zip) · Linux: [ShotgunRally-Linux.zip](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/shotgun-latest/ShotgunRally-Linux.zip)
- All of them on one page: [releases/shotgun-latest](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/tag/shotgun-latest)

Free, PC only (Windows, Mac, Linux). Built in **Godot 4.7**, like BAGHOLDERS.

## Based on *Left Left Left!*

Inspired by ***Left Left Left!*** ([@leftleftleftgame on TikTok](https://www.tiktok.com/@leftleftleftgame)):
two players in one car, both in first person, one with the map. The full breakdown of the four
reference clips is in [`docs/VIDEO_BREAKDOWN.md`](docs/VIDEO_BREAKDOWN.md), with frames in
[`docs/reference/`](docs/reference/).

What's ours:
- The name, the look, and **our own map device**: a paper roadbook roll instead of their tablet.
- **The real co-driver's jobs**, not just calling turns
  ([`docs/CO_DRIVER_JOBS.md`](docs/CO_DRIVER_JOBS.md)).
- An **AI co-driver** for solo, with a real voice.

## How a stage plays (the plan)

| | Driver | Co-driver (shotgun) |
|---|---|---|
| Sees | The road through the windshield. **No map, no minimap, no HUD** | The **roadbook roll** in their hands, *or* the road if they look up. Never both at once |
| Does | Steers, brakes, handbrakes, trusts | Calls the corners, counts down the start, works the wipers, shows the OK board after a crash, runs the warning triangle back, helps push the car out |
| Alone? | The AI co-driver calls the stage in the **Fraser** voice | — |

**Controls:** keyboard, controller, or a steering wheel.

## Play with friends (when the first build is out)

The same way as BAGHOLDERS: one person hosts, the other joins with the host's IP. From different
houses, the easiest way is **[Tailscale](https://tailscale.com)** (free): join with the host's
`100.x.y.z` address.

## Roadmap

| Phase | What | Status |
|---|---|---|
| 0 | Reference breakdown, name, plan, co-driver research, voice pack | ✅ done |
| 1 | **Grey-box prototype:** one generated forest gravel stage, the rally car, first-person driver + co-driver seats, roadbook roll, 2 players online | next |
| 2 | **AI co-driver:** notes written from the road, Fraser voice, quick-call wheel, call timing setting | |
| 3 | **Art:** low-poly car and cockpit (Blender scripts + Higgsfield), toon forest | |
| 4 | **Jobs + content:** OK board, triangle, pushing, time cards, road book, recce mode, more biomes | |
| 5 | Polish, steering wheel tuning, crews racing each other | |

## Docs

- [`docs/PLAN.md`](docs/PLAN.md): the plan (why it works, what could break, cost, competitors)
- [`docs/VIDEO_BREAKDOWN.md`](docs/VIDEO_BREAKDOWN.md): the *Left Left Left!* clips, shot by shot
- [`docs/CO_DRIVER_JOBS.md`](docs/CO_DRIVER_JOBS.md): what real co-drivers do → in-game tasks
- [`assets/voice/fraser/`](assets/voice/fraser/): the co-driver voice clips

## Credits & notes

- Co-driver voice: Higgsfield Seed Audio 1.0, preset voice "Fraser", from the Rally Co-Driver GPS
  app ([driver-test-app](https://github.com/pbelfand-dot/driver-test-app)).
- Car makes are parodies, like BAGHOLDERS' BEMZE and AUDY. No real brands.
- *Left Left Left!* belongs to its creator. We borrow the idea of the game, not their art, name or UI.
