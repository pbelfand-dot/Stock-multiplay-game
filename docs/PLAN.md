# SHOTGUN RALLY: the plan

*Updated 2026-10-04: phase 1 (the playable grey box) is built and tested.*

## What's decided

| Question | Answer |
|---|---|
| Based on | ***Left Left Left!*** ([@leftleftleftgame](https://www.tiktok.com/@leftleftleftgame)). Breakdown: [`VIDEO_BREAKDOWN.md`](VIDEO_BREAKDOWN.md) |
| Name | **SHOTGUN RALLY** ✅ confirmed. "Riding shotgun" is the passenger seat, and the passenger seat is the game |
| Where | Its own branch, `shotgun-rally`, in this repo. Downloads come from a separate release tag, `shotgun-latest` |
| Price | **Free**: GitHub downloads + **itch.io** (set-up ready: [`ITCH.md`](ITCH.md)) |
| Budget | This Claude plan + your Higgsfield credits (**844.5**, Plus plan, checked 2026-10-04) |
| Co-driver | Sits in the car and can look out the windows. Does **the real co-driver's jobs**: see [`CO_DRIVER_JOBS.md`](CO_DRIVER_JOBS.md) |
| Players | 2 (one crew) now. Crews racing each other later |
| Controls | Keyboard + controller (no steering wheel for now: you don't have one to test with) |
| Platforms | PC only: Windows, Mac, Linux (same builds as BAGHOLDERS) |
| Voice | **Fraser** (Higgsfield Seed Audio), 56 clips from your driver-test-app: [`assets/voice/fraser/`](../assets/voice/fraser/) |

## The core idea (what the videos taught us)

In *Left Left Left!* **both players sit in the car in first person**, and the navigator holds the map
in their hands. The split between the two players doesn't come from fog. It comes from **where you
look**:

| | Driver | Co-driver |
|---|---|---|
| Looks at the road | Always. It's all they have | Only when they look up, and then they've lost their place on the map |
| Looks at the map | Never: there's no map, minimap or HUD | Only when they look down, and then they can't see the road coming |

The map shows **only the road and where the car is, no callouts**: turning bends into calls is the
co-driver's skill. On top of that we add rally conditions that make the calls matter more: blind crests, trees on the
inside of corners, dust, mud on the glass, night and fog stages.

---

## Part 1: why it works (the optimist)

1. **The hook already works on TikTok.** *Left Left Left!* is building an audience on that one
   idea, and **Backseat Drivers** (Steam, Oct 2025: "Gramma can't see and you can't drive") got
   about 1,165 reviews, ~78% positive (one tracker's count). Two people yelling directions is
   proven fun.
2. **Good timing.** EA / Codemasters **stopped making rally games in 2025**. Co-op "play with
   friends" games are the biggest indie trend (R.E.P.O. and PEAK were 2025's top-selling new games
   by units).
3. **Most of the hard code already exists, in your own repos:**

   | Already built | Where | Use |
   |---|---|---|
   | **A pacenote engine:** road → "4 left, 100, 3 right tightens 2" (grades 1–6, tightens/opens, long, caution, "into" links) plus a tracker that follows the car's position and speed along the road | `driver-test-app/rally/pacenotes.js` (982 lines) | Port to GDScript: the AI co-driver's brain. Stage x/z replaces GPS lat/lng |
   | **The co-driver voice** + a clip-stitching player | `driver-test-app/rally/voice/`, `voicepack.js` | Copied into this branch already |
   | Car physics: grip, weight transfer, handbrake drift, real steering ratios | `main: scripts/vehicle/car.gd` | The starting point for the rally car |
   | Cockpit camera with **hands on the wheel** | `main: scripts/vehicle/drive_cam.gd`, `scripts/art/character.gd` | The driver's first-person view |
   | Roads as data + a procedural road mesh | `main: scripts/world/highway.gd`, `road_mesh.gd` | Stages: one centerline drives the road, the co-driver's map *and* the AI's calls |
   | AI that follows a path | `main: scripts/vehicle/ai_driver.gd` | Test stages without a human |
   | Online host/join, the driver's PC runs the car | `main: scripts/net/net.gd` | Driver hosts, co-driver joins |
   | Auto-builds for Windows/Mac/Linux + download links | `main: .github/workflows/build.yml` | Same on this branch, its own release tag |
4. **Lag barely matters.** Calls happen 1–3 corners ahead. Only the driver needs a smooth car, and
   the driver's own PC runs it.
5. **Cheap voice.** More lines in the same Fraser voice cost **0.2 credits each**. The whole list of
   missing calls is under 10 credits.
6. **Endless stages.** Generate stages from a seed and every stage automatically gets a map
   for the human and calls for the AI.
7. **Low poly is fast to make.** The interior in the clips is simple shapes, which our Blender
   scripts can build. Higgsfield's Meshy has a low-poly mode for the rest.

---

## Part 2: what won't work / what you're not counting (the critic)

| # | Problem | Why it matters | Fix |
|---|---|---|---|
| 1 | **"It's a copy of Left Left Left!"** | They're still pre-release on TikTok. If ours looks the same, people will call it a ripoff (rightly) | Copying the *idea* is legal (US Copyright Office: game ideas and rules aren't protected). Copying art, name and UI isn't. Ours gets its own name, a **wooden map board** instead of their orange tablet, real co-driver jobs, an AI co-driver and recce mode |
| 2 | **They might launch first** | They'll own "the co-driver game" on TikTok | Fine for a free game. Our edges: free, solo-able with the AI co-driver, more to do in the passenger seat |
| 3 | **The game can't hear voice chat** | It can't grade the co-driver's calls | Score the **team** (time, offs, penalties). Grade quick-wheel calls for timing. Voice recognition later, maybe |
| 4 | **The co-driver gets bored** | Calling turns for 4 minutes isn't enough | The jobs list: start countdown, wipers, OK board, triangle run, pushing the car, time cards, road book, recce |
| 5 | **Voice chat itself** | Building in-game voice is real work | Phase 1: use Discord. Later: in-game voice. The quick-call wheel covers people without a mic |
| 6 | **Connecting** | Host + IP + Tailscale is fine between friends (BAGHOLDERS works this way) | Keep it for now. A lobby / relay is only needed if strangers play together |
| 7 | **The repo is private** | Download links only work for people with access to the repo. Your friends get a 404 | Make the repo public, or add friends as collaborators. *(BAGHOLDERS' links have the same problem today)* |
| 8 | **Releases share one page** | BAGHOLDERS' "releases/latest" link could start pointing at the rally build | The rally release uses its own tag (`shotgun-latest`) and is **never marked "latest"** |
| 9 | **Rally physics ≠ highway physics** | Gravel, mud, jumps, landings, rollovers. The BAGHOLDERS car body isn't built for airtime | Phase 1's biggest job: a raycast-suspension car, tested before any art |
| 10 | **Steering wheels** | Godot reads most wheels like a controller with axes, but **force feedback** is the hard part and every wheel maps differently | Keyboard + controller first. A wheel calibration screen next. Force feedback last (tell me which wheel you have) |
| 11 | **AI 3D models come out as one solid piece** | Cars need separate wheels, a steering wheel and pivots | Build the cockpit and wheels with Blender scripts. Use Higgsfield for the car body, props, animals and spectators |
| 12 | **Generated stages look the same** | Endless random roads get boring | Hand-made set pieces (water splash, big jump, village hairpin, bridge) and 3–4 biomes |
| 13 | **AI calls at the wrong time** | Too early, you forget; too late, you crash | Call by *time* to the corner (the driver-test-app tracker already knows the car's speed and position), plus a calls earlier/later setting |
| 14 | **Two games at once** | BAGHOLDERS is still live | Separate branch, so they can't break each other. Pick one per week |

---

## Part 3: does it work as a business? (the investor)

It's free, so "business" means **getting players and keeping costs at zero.**

### Costs

| Item | Cost |
|---|---|
| Godot, GitHub, GitHub Actions builds | $0 (Actions minutes are free on public repos; private repos get a monthly free allowance) |
| Voice (more Fraser lines) | ~0.2 credits a line, **< 10 credits** total |
| 3D models (Higgsfield Meshy, textured low poly) | 25 credits each. Budget: **~150–250 credits** for a car body or two, props, animals and spectators |
| Images (concept art, map board art, logo) | a few credits each |
| Keep in reserve | **~500 credits** for later content |
| Mac signing ($99/yr) | Skip it, like BAGHOLDERS (players use "Open Anyway") |

### Getting players (free)

- **TikTok clips of the yelling.** That's exactly how *Left Left Left!* is marketing. Every crash with
  a "WIPER! WIPER!" moment is a clip.
- **GitHub releases** for the downloads (once the repo is public).
- **Suggestion: a free itch.io page.** Nobody browses GitHub for games, but people do browse itch.io.
  It costs $0, and the download can just point at the GitHub build. *(Your call: you said GitHub.)*

### Competitors (checked 2026-10-04)

| Game | What it is | For us |
|---|---|---|
| ***Left Left Left!*** | The reference: 2 players in one car, first person, navigator with a tablet. No store page found; looks pre-release | Closest by far. Be clearly different (see Part 2, #1) |
| **Backseat Drivers** (GhostJam / Deadcat, Oct 2025) | 2–4 player co-op: Gramma navigates, you drive a terrible car | Proves the yelling-directions hook. Not rally |
| **#DRIVE Rally** | Arcade '90s rally with 6 AI co-drivers with personalities | Our AI co-driver has to be at least this fun |
| **art of rally** | Stylized rally, solo | Proves stylized rally has fans |
| **Rally Together** (Q4 2026) | Co-op rally where you're the **pit crew** | Adjacent, not driving |
| **Drive Together** (May 2026) | Each player controls part of one car | Co-op car chaos is popular right now |
| **EA WRC / DiRT** | Sim rally, stopped in 2025 | A gap, not a rival |

---

## Build order

| Phase | What | Credits | Done when |
|---|---|---|---|
| 0 ✅ | Breakdown, name, plan, co-driver research, voice pack, branch | 0 | This doc |
| 1 | **Grey box:** Godot project on this branch, one generated forest gravel stage, the rally car (raycast suspension), first-person driver seat with hands, co-driver seat with a working **map board**, wipers + mud, start countdown, 2 players online, builds + download links live | 0 | You and a friend finish a stage on Discord and want another |
| 2 | **AI co-driver:** port `pacenotes.js` → GDScript, play the Fraser clips, quick-call wheel, timing setting, generate the missing lines | ~10 | You can drive alone and trust the calls |
| 3 | **Art:** low-poly red hatchback (parody name), cockpit, helmets and arms, toon forest | ~150–250 | It looks like a real game in a TikTok clip |
| 4 | **Jobs + content:** OK board, triangle run, pushing the car, punctures, time cards + road book, recce mode, 3–4 biomes, set pieces | some | 20+ minutes of stuff |
| 5 | **Polish:** wheel calibration + force feedback, scoring, crews racing each other | — | Strangers play it |

## Still open

1. **Making the repo public: careful.** This repo also holds BAGHOLDERS, and BAGHOLDERS has
   8 commercial songs in `assets/music/` (Rick Ross, Moneybagg Yo, Martin Solveig & GTA...) plus the
   real car models baked into `realcars_kit.glb`. Making the repo public would publish those files and
   their whole history. **Better:** give SHOTGUN RALLY its own public repo (this branch has none of
   that) and keep this one private.
2. **itch.io:** make the page and add the two GitHub settings in [`ITCH.md`](ITCH.md).
3. **Phase 2 next:** the quick-call wheel for the human co-driver, call timing in the menu, more lines.

## Sources

- The clips: [`VIDEO_BREAKDOWN.md`](VIDEO_BREAKDOWN.md). Co-driver research: [`CO_DRIVER_JOBS.md`](CO_DRIVER_JOBS.md)
- Backseat Drivers: [Steam](https://store.steampowered.com/app/3558400/Backseat_Drivers/), [review count (Wasdland)](https://www.wasdland.com/game/backseat-drivers-3558400/)
- EA / Codemasters pause rally: [Push Square](https://www.pushsquare.com/news/2025/05/codemasters-pausing-development-on-rally-games-ea-sports-wrc-support-concludes)
- Co-op trend: [Creative Bloq](https://creativebloq.com/3d/video-game-design/what-is-friendslop-and-why-it-it-taking-over-gaming-in-2026), [Alinea Analytics](https://alineaanalytics.substack.com/p/the-top-new-2025-games-by-players)
- #DRIVE Rally: [Steam](https://store.steampowered.com/app/2494780/DRIVE_Rally/). art of rally: [Wikipedia](https://en.wikipedia.org/wiki/Art_of_Rally)
- Rally Together: [Steam](https://store.steampowered.com/app/5127350/Rally_Together/). Drive Together: [Steam](https://store.steampowered.com/app/4117320/Drive_Together/)
- "Ride or Die" taken: [MobyGames: 187 Ride or Die](https://mobygames.com/game/24079/187-ride-or-die)
- Game ideas aren't copyrighted: [US Copyright Office FL-108 (archived)](https://webharvest.gov/peth04/20041015023438/http://www.copyright.gov/fls/fl108.html)
- Higgsfield prices (25 credits per low-poly 3D model, 0.2 per voice line) and the 844.5-credit balance: checked with the Higgsfield tools on 2026-10-04
