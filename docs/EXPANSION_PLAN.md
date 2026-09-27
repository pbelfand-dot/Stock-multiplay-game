# BAGHOLDERS: going bigger (with the Schedule I look)

What you asked for: "copy this style" (the Schedule I thumbnail) and "plan on making the game bigger".

## Facts checked (Sept 2026)
- **Schedule I** is made by **TVGS**, a solo Australian developer named Tyler, in Unity. It launched in Early Access on **24 Mar 2025** at **$19.99**. It's a first-person drug-empire sim with **up to 4-player co-op**, set in the fictional city of Hyland Point.
- It peaked at about **459k concurrent players** within weeks and passed **4M copies** early on. Later third-party *estimates* range from about 6.5M to 14M copies. These are guesses, not official numbers.
- The map has **6 regions unlocked by rank**: Northtown (start) → Westville (Hoodlum) → Downtown (Hustler) → Docks (Enforcer) → Suburbia (Block Boss) → Uptown (Baron). You earn XP at the end of each day, based on how much money you made.
- Reviewers credit its success to minigames that turn chores into fun, chaotic co-op moments people clip and share, and constant updates.

## The style, and what it means for our models
Our characters already share the "egg head + tired bulging eyes" DNA. To push them toward the Schedule I look:

| Schedule I trait | Our change |
|---|---|
| Tall bean skull, almost no neck | Taller skull, head sits lower on the collar, thicker neck |
| Huge round eyes with tiny black pupils | Bigger eyeballs, smaller pupils, heavier lids |
| **Bloodshot red-veined eyes** when high | New eye texture that switches on with Nose Candy / cigars |
| Thick flat brows, chin goatees, chinstraps | New beard styles: chin goatee, chinstrap |
| Flat, saturated clothes with soft shading | Soft two-tone "toon ramp" shading on all character materials |
| Cops in navy **POLICE** vest + cap | New cop outfit: vest with POLICE text, POLICE ball cap |
| Bowler hat / trench coat, green cap + shades | New hats: bowler, bucket, trucker. New coat: trench |

It's legal to copy a *style*. We don't copy their actual characters, names or logos. Parody names stay ours: TRAMP, TJZ, KIMCHEE, and so on.

## Making it bigger: the plan
Keep **trading** as the core loop, and wrap a city and a progression system around it, the way Schedule I wraps one around its production loop.

**Ranks** (earned from end-of-day profit): Intern → Analyst → Trader → Degen → Whale → Market Maker → Wolf. Each rank unlocks a new area.

| Rank | Unlock | What's there |
|---|---|---|
| Intern (start) | **Mom's basement** | Laptop trading, tiny position sizes, ramen. The tutorial. |
| Analyst | **The trading floor** (what we have now) | Terminals, Tony, slots, streamers |
| Trader | **The street block** | Luxury store (ROFLEX, LOUIE BATON, Supreme), pawn shop, barber/tailor, hot-dog cart, Tony's alley |
| Degen | **DEGEN casino** | Slots v2, blackjack, roulette, VIP room with red carpet |
| Whale | **Penthouse + garage** | Buy it, decorate it with trophies, park your Lambo, throw parties |
| Market Maker | **Docks / yacht** | Launch your own coin (pump → rug pull), yacht deals |
| Wolf | **Uptown HQ** | Hire employees (interns auto-trade, analysts give tips), own buildings |

**New systems, in build order:**
1. **Save file + progression.** Net worth, rank and owned items persist between sessions, saved by the host.
2. **Luxury and property sinks.** Somewhere to spend money: flex items, desk trophies, a penthouse, cars.
3. **Market sessions.** Asia, London and New York sessions with a day/night cycle. Tramp tweets and news move prices.
4. **City NPCs.** Citizens with daily schedules who buy your "signals" (a paid group). Pumping a coin to them builds heat.
5. **Police → SEC.** Heat per district, investigations, the courthouse, and Saul Goodmann.
6. **Employees.** Hire NPC traders who make money while you run around.

## Build phases
| Phase | Content | Size |
|---|---|---|
| **0 (next)** | Grey-blue office recolor, Schedule I character style pass, luxury flex items, phone tweet feed, emotes + sitting in chairs, slots v2 + decor | 1 PR each or a few together |
| 1 | Save/progression + ranks + rank-up screen | medium |
| 2 | Lobby → street block with 5 shops (world streaming starts here) | large |
| 3 | Casino + penthouse (buying and decorating property) | large |
| 4 | Basement tutorial + city NPCs + signals group | large |
| 5 | SEC/courthouse, employees, docks/coin launch | large |

## Step 1: What's good about this
- It follows a proven formula: a sim loop, co-op chaos and rank-gated districts (Schedule I). Plus our own hook: real-feeling trading with parody streamers and presidents.
- Everything we've built carries over. The props kit and character kit pipeline can churn out new rooms fast. Host-authoritative netcode already handles 4+ players.
- Each phase is playable on its own, so you and your friends get new stuff every PR.

## Step 2: What could break, and what we're not accounting for
- **Scope creep** is the #1 killer. A city is 10× the office. The fix is to add one block at a time and only move on once it's fun.
- **Mac performance.** A bigger world needs streaming: load and unload areas behind doors and the elevator. Draw calls and triangles must stay near today's numbers. I measure this on every screenshot run now.
- **Multiplayer sync.** More NPCs means more network traffic. NPCs need to be host-simulated and sent only to players who are close by.
- **Saves.** Who owns the save in co-op? Proposal: the host's save is the "company", and each player keeps their own wallet and trophies.
- **Download size.** Builds will outgrow the 30 MB file I can send in chat. We'll use GitHub Releases (the CI already builds them on tags).
- **Testing.** My headless tests catch crashes and sync bugs, but *fun* needs you and your friends playing. Plan short playtests after each phase.
- **Legal.** Copying the style is fine. Copying Broke Street's exact concept and Schedule I's characters is only OK while this stays free and private among friends.

## Step 3: Business, competitors and money
- **Cost right now: $0.** Godot, Blender and GitHub Actions are free (private repos get 2,000 CI minutes a month).
- **If you ever sell it:** Steam Direct costs $100 per game, and Valve pays it back after $1,000 in sales. Before that you'd need original art and names that don't lean on Broke Street's concept.
- **Competitors:**
  - **Broke Street**: the trading-office game from your videos. Same idea, still in wishlist phase.
  - **Schedule I**: the genre king. Crime sim, $19.99, huge co-op audience.
  - Other simulators on Steam: *Drug Dealer Simulator*, and shop sims like *Supermarket Simulator*.
- **Our angle:** "Schedule I, but it's Wall Street degeneracy." Trading, streamers, presidents' tweets, and SEC cops. Nobody fully owns that niche yet.

## My opinion
Do Phase 0 now: it's what your clips show and it makes the office feel finished. Then do **Phase 1 (progression)** *before* building more map. Schedule I's regions work because every unlock feels earned. A bigger map without ranks and money sinks would just be empty streets.
