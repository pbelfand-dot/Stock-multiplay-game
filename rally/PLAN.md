# RALLY (working title): the plan, before the videos

What you asked for: a **cartoony online rally game**. One player **drives**, the other is the
**co-driver**: they have the map and yell the callouts ("LEFT 4, DON'T CUT, OVER CREST!"). If
you have no friend online, an **AI co-driver** does the calls. 3D models (cars, interiors) come
later from Higgsfield. You're sending four videos of the game this is based on, and this plan
gets updated once they're in (`VIDEO_BREAKDOWN.md` goes next to it, like BAGHOLDERS had).

This folder has a `.gdignore`, so the BAGHOLDERS Godot project skips it. Nothing here touches
the trading game.

---

## The one idea everything hangs on: split the information

The game only works if **neither player can win alone**:

| | Driver sees | Co-driver sees |
|---|---|---|
| Road | The road right in front: fog, dust, night, blind crests, trees on the inside of corners | Little or none (a small shaky dash cam at most) |
| Where the road goes | **Nothing.** No minimap, no arrows | **The whole map** + the pacenote book (the notes for the next corners) |
| Hazards | Only when it's too late | Marked on the map: rocks, cows, water splash, junctions |

That's the same trick as *Keep Talking and Nobody Explodes* (one person sees the bomb, the other
has the manual). If the driver can see far enough to drive alone, the co-driver is useless and
the game dies. **Fog, crests, dust and night are features, not decoration.**

---

## Part 1: why it works (the optimist)

1. **The fun is built in.** Real rally is two people trusting each other at 150 km/h. In a game
   that turns into yelling, blame and clutch saves, which is exactly what people clip for TikTok.
2. **Good timing.**
   - EA / Codemasters **stopped making rally games in May 2025** (no more DiRT or EA WRC
     updates). Rally fans get fewer new games now.
   - Co-op "play with your friends" games are the biggest indie trend: **R.E.P.O.** ($9.99) and
     **PEAK** were the two top-selling new games of 2025 by units, ahead of big-budget games.
     Almost all of them run on **voice chat**, and this game's whole point is talking.
3. **We already built half the hard parts in BAGHOLDERS** (same Godot 4.7 setup):

   | Already there | File | Use in the rally game |
   |---|---|---|
   | Car physics: grip, weight transfer, handbrake drift, steering ratios | `scripts/vehicle/car.gd` | Starting point for the rally car (needs gravel, jumps; see Part 2) |
   | Chase cam + cockpit cam (hands on the wheel) | `scripts/vehicle/drive_cam.gd` | Driver's view as it is |
   | Road as data: a centerline with distances along it | `scripts/world/highway.gd`, `road_mesh.gd` | The stage: road, map **and** pacenotes all come from one line |
   | AI that follows a path | `scripts/vehicle/ai_driver.gd` | Testing stages without a human |
   | Online play: host + join, only the driver's PC runs the car | `scripts/net/net.gd` | Driver hosts, co-driver joins |
   | Blender scripts that build cars and characters | `tools/blender/` | Cleaning up the Higgsfield models |
   | Auto-build for Windows / Mac / Linux on every push | `.github/workflows/build.yml` | Same downloads page |
4. **Lag barely matters.** Real co-drivers call 1–3 corners **ahead**. A 100 ms delay on the
   co-driver's screen changes nothing. Only the driver needs a smooth game, and their own PC runs
   the car.
5. **The AI co-driver is very doable.** Pacenotes are a small, fixed language:
   - how sharp the corner is (most rally games use 6 = almost flat out down to 1 = very slow,
     plus "hairpin"; some real crews flip the scale),
   - the distance to the next one ("100"),
   - and a few modifiers ("tightens", "opens", "long", "don't cut", "over crest", "into").

   The game reads the bend of the road and writes the notes itself, then plays pre-recorded
   clips one after another. Real rally games work from recorded clips too (DiRT Rally 2.0 recorded
   its pace notes three times). The vocabulary is roughly **150–300 clips**, recorded once.
6. **Endless stages for free.** If stages are generated from a seed, every new stage
   automatically gets a map for the human co-driver and calls for the AI one.
7. **Cartoony is cheap and forgiving.** Higgsfield's Meshy models have a **low-poly mode**, and a
   toon look hides the flaws AI meshes have. Trees, rocks and terrain can be made in code, the way
   BAGHOLDERS makes its roads (costs nothing).

---

## Part 2: what won't work / what you're not counting (the critic)

| # | Problem | Why it matters | Fix |
|---|---|---|---|
| 1 | **The co-driver gets bored** | Reading a map for 4 minutes isn't a game unless it has some skill to it | Give them a score (call accuracy and timing), route choices at junctions, hazard warnings, a stage clock to manage, and later small jobs (wipers, lights, horn at spectators) |
| 2 | **The driver just looks at the road** | Then nobody needs the co-driver | Fog, dust from the car ahead, night stages, blind crests, no minimap for the driver. Tune it so it's tense but never unfair |
| 3 | **Voice chat is the whole game** | Building in-game voice is a real job | First version: players use **Discord**. Later: Steam voice (GodotSteam). Also a **quick-call wheel**: press a button and the AI voice says "LEFT 3!" for you. That covers players with no mic, strangers, and accessibility |
| 4 | **Connecting online** | BAGHOLDERS uses IP + Tailscale: fine for friends testing, not OK for a public release | For Steam: Steam lobbies + relay through GodotSteam (no port forwarding). Needs the Steam app set up ($100, Part 3) |
| 5 | **The voices you have might not be usable** | The best-known free rally voice set on GitHub (`rallymodemod` for BeamNG) has a version built from **real rally footage of Alex Gelsomino**, Ken Block's co-driver. You can't sell a game with a real person's voice without permission | Check the license of the folder you meant. Safe options: record yourself or a friend, or make a voice with Higgsfield audio and own the result |
| 6 | **AI 3D models come out as one solid piece** | A car needs separate wheels (to spin and steer), a steering wheel for the cockpit view, the right pivot point and a collision shape | Every Higgsfield car goes through a Blender cleanup step (we already have Blender scripts). Or generate the **body only** and use code-made wheels. Ask for low-poly (~5–15k triangles) |
| 7 | **Rally physics ≠ highway physics** | The BAGHOLDERS car is tuned for asphalt. Rally needs gravel, snow, mud, **jumps and landings**, bumps and rollovers. The current car body type isn't great at airtime | Expect real work here. It's the #1 thing that decides if the game feels good. Probably a raycast-suspension car. Prototype it first, before any art |
| 8 | **Generated stages look the same** | Endless random roads get boring fast | Mix generated road with hand-made **set pieces** (big jump, water splash, hairpin in a village, bridge) and 3–4 biomes (forest gravel, snow, desert, mud) |
| 9 | **AI calls at the wrong time** | Too early and you forget it; too late and you crash | Call by **time** to the corner, not distance (faster = earlier). A setting for "calls earlier / later", like real rally games have |
| 10 | **Testing needs 2 people** | You can't test the main mode alone | The AI co-driver (and the AI driver from BAGHOLDERS) let one person test both seats |
| 11 | **Real car brands** | Car makers license their designs and names | Parody names and shapes, like BAGHOLDERS already does (BEMZE, AUDY). Don't use "WRC" or "DiRT" either |
| 12 | **Two games at once** | BAGHOLDERS is still getting updates. The biggest risk is two half-finished games | Pick which one gets the week. Keep the rally game in its own repo so the two don't break each other |

---

## Part 3: does it work as a business? (the investor)

### Competitors (checked Oct 2026)

| Game | What it is | What it means for us |
|---|---|---|
| **#DRIVE Rally** (Pixel Perfect Dude) | Arcade '90s rally, stylized look, **6 AI co-drivers with personalities**, an "Emotional mode" where the co-pilot reacts to your driving. Local party mode is take-turns | **Closest competitor for the solo / AI co-driver part.** Our AI co-driver has to be at least this fun. Their weak spot, as far as I found: no friend co-driving online |
| **art of rally** (Funselektor, 2020) | Stylized top-down rally | Proof a stylized rally game sells. One third-party *estimate*: ~170K copies on Steam, ~$2.6M (a guess, not official) |
| **EA Sports WRC / DiRT** | Sim rally | Development stopped in 2025. A gap in the market, not a rival |
| **Assetto Corsa Rally** (Nov 2025, Early Access) | Hardcore sim for steering-wheel players | A different audience. Don't compete on realism |
| **Rally Together** (Q4 2026) | Co-op rally, but you're the **pit crew fixing the car**, not driving | Close in name and idea. Make sure our name is clearly different |
| **Drive Together** (May 2026) | Each player controls part of the same car | Co-op car chaos is being made right now. Our edge: it's *real* rally teamwork, not random chaos |
| **Food Truck Together** | "One drives, one navigates" + cooking in the truck | Same split, different theme |
| **The game in your videos** | To be checked when you send them | If it's already a hit, we need a twist of our own (see below) |

**Our angle, in one line:** *the only cartoony rally game where your friend is your co-driver, and
the AI co-driver is good enough for solo.*

### Money (what it actually costs)

| Item | Cost | Notes |
|---|---|---|
| Godot engine | **$0** | Free, already set up |
| Steam page (Steam Direct) | **$100 per game** | You get it back after the game makes $1,000. Steam keeps 30% of sales |
| Higgsfield 3D models | **25 credits per textured low-poly model** (checked the price) | You have **844.5 credits** (Plus plan). That's ~33 tries; with retries, about **10–15 finished models**. Spend them on cars and the cockpit, not trees and rocks (those are free in code) |
| Co-driver voice | $0 → a few $ | Record yourself (free) or use Higgsfield audio credits. ~150–300 short clips |
| Mac signing (optional) | $99 / year | Same as BAGHOLDERS, you can skip it at first |
| Marketing | $0 | TikTok / Shorts clips of the yelling. Put the Steam page up early to collect wishlists |

**Rough math (a rule of thumb, not a promise):** at **$9.99**, after Steam's 30%, taxes,
regional prices and refunds, you keep roughly **$5–6 a copy**. So about **2,000 copies ≈ $10K**.

### A plan that fits a small budget

- **Phase 0–2 cost $0.** Prototype with boxes, a code-made stage and Discord voice. Only spend
  Higgsfield credits **after** two people have played it and said "again!".
- One **hero car** first (generate → clean up → test in game). If that pipeline works, do the rest.

---

## Build order

| Phase | What | Cost | Done when |
|---|---|---|---|
| 0 | Your videos → `VIDEO_BREAKDOWN.md`. Choose a name and a repo | $0 | We both agree on what we're copying and what's ours |
| 1 | **Grey-box prototype:** one generated gravel stage, one box car with rally handling, driver view with fog, co-driver map screen, 2 players online, Discord for voice | $0 | Two people finish a stage and it was fun to yell |
| 2 | **AI co-driver:** notes written from the road, placeholder voice, quick-call wheel, call timing setting | $0 | You can drive alone and trust the calls |
| 3 | **Art:** one Higgsfield hero car + cockpit, toon shading, trees and rocks in code | ~100–200 credits | It looks like the videos |
| 4 | **Content:** 3–4 biomes, set pieces, damage, scores, unlocks | some credits | 20+ minutes of things to do |
| 5 | **Steam:** page, lobbies + voice through GodotSteam, playtest, launch | $100 | People you don't know are playing it |

---

## Questions for you (they change the plan)

1. **What's the game in the videos called?** Then I can look it up properly and check how it sells.
2. **New repo or this one?** I'd make a new repo (e.g. `rally-game`) so the rally game and
   BAGHOLDERS each keep their own builds and downloads.
3. **Which GitHub folder has the co-driver voices?** Send the link and I'll check whether its
   license lets you use it.
4. **Budget:** how much can you spend in total (more Higgsfield credits, Steam's $100, voice)?
5. **Free for friends (like BAGHOLDERS) or sold on Steam?**
6. **What does the co-driver see:** only the map, or the map plus a small road view?
7. **How many players:** strictly 2, or several driver + co-driver teams racing the same stage?
8. **Keyboard, controller or both?** PC only?

## Sources (checked Oct 2026)

- EA / Codemasters pause rally games: [Push Square](https://www.pushsquare.com/news/2025/05/codemasters-pausing-development-on-rally-games-ea-sports-wrc-support-concludes), [GamingOnLinux](https://www.gamingonlinux.com/2025/04/ea-and-codemasters-no-longer-making-wrc-world-rally-championship-games)
- Co-op indie trend, R.E.P.O. / PEAK top sellers: [Creative Bloq](https://creativebloq.com/3d/video-game-design/what-is-friendslop-and-why-it-it-taking-over-gaming-in-2026), [Alinea Analytics](https://alineaanalytics.substack.com/p/the-top-new-2025-games-by-players)
- R.E.P.O. price $9.99: [SteamDB](https://steamdb.com/pt-BR/tools/steam-price-history/3241660-r-e-p-o)
- #DRIVE Rally: [Steam](https://store.steampowered.com/app/2494780/DRIVE_Rally/), [co-driver discussion](https://steamcommunity.com/app/2494780/discussions/0/4424310637510966527/)
- art of rally estimate: [Raijin](https://raijin.gg/app/550320/art_of_rally), [Wikipedia](https://en.wikipedia.org/wiki/Art_of_Rally)
- Rally Together: [Steam](https://store.steampowered.com/app/5127350/Rally_Together/); Drive Together: [Steam](https://store.steampowered.com/app/4117320/Drive_Together/)
- Assetto Corsa Rally: [Wikipedia](https://en.wikipedia.org/wiki/Assetto_Corsa_Rally)
- DiRT Rally 2.0 pace notes: [GTPlanet](https://gtplanet.net/dirt-rally-2-0s-pace-notes-are-recorded-three-times-for-maximum-realism)
- Rally voice samples, Gelsomino footage: [BeamNG Rally Mode](https://www.beamng.com/resources/rally-mode-smart-co-driver-stages-with-pacenotes.21824), [GitHub: rallymodemod](https://github.com/lellolillili/rallymodemod)
- Steam Direct $100 and the 30% cut: [Fungies](https://fungies.io/steam-revenue-share-explained/)
- Steam voice and lobbies in Godot: [GodotSteam asset](https://godotengine.org/asset-library/asset/2113), [80.lv](https://80.lv/articles/free-godot-multiplayer-framework-with-steam-support)
- Higgsfield 3D price and credit balance: checked with the Higgsfield tools on 2026-10-04
