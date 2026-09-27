# Reference Video Breakdown — "Broke Street" Steam Page Trailer

Source: a 17.2 s vertical (720×1280, 30 fps) Instagram clip from **@brokestreetgame** with the caption
"WE LAUNCHED OUR STEAM PAGE 🔥". Every frame was pulled at 2 fps, and the trading terminal was pulled
again at full resolution. The key frames are in [`reference/`](reference/).

## What the game is (verified)

- **Broke Street** ([Steam page](https://store.steampowered.com/app/4674810/Broke_Street/)) is a
  "1–6 player co-op roguelike trading sim". The players start broke at a Wall Street hedge fund,
  **share one balance**, make risky trades, **use items** to find winning strategies, and have to
  **hit quotas that rise** to survive each day. Each round lasts **5 minutes**.
- Developer: the Ukrainian 3D artist "Driko" (also making *Catomino*) plus two programmers from Turkey,
  so three people in total. Planned release is **Q4 2026** — i.e. right about now.
  ([dev.ua](https://dev.ua/en/news/cymuliator-brokera-broke-street-u-styli-vovka-z-voll-strit-1790153372))
- The tone is *Wolf of Wall Street*: cigars, money guns, cops, a casino, and parody news.
- Not verified: one search summary said "500,000 wishlists per day". That looks wrong, so don't rely on it.

## Shot-by-shot timeline

| Time | What happens | Mechanic it implies |
|---|---|---|
| 0.0–1.5 s | First-person view. The player holds a huge lit cigar. A suited NPC is also smoking and reaches out to take it. | Held **items** / props; NPCs you can interact with |
| 1.5–3.0 s | A smoke cloud (a translucent silhouette) wraps the NPC. **Two cops walk out of the elevator with guns drawn** (the elevator display reads floor 12). | **Police raid** event; possibly a smoke item that hides you |
| 3.5–4.0 s | A character **dives / ragdolls** away from the cops. An arcade cabinet is on the left. | Escape / chase; ragdoll physics |
| 4.5–6.0 s | Third-person shot: a gray pinstripe suit, sunglasses and a gold watch, spinning on an office chair and firing a red **"FLEX" money gun**. Bills fly everywhere. | Cosmetics; a flex / emote item |
| 6.0–7.0 s | First person: the player **shoots a basketball** into a hoop on the office wall. Framed certificates hang nearby. Cigars and white powder lie on the floor. | Physics toys / office minigame |
| 7.5–8.5 s | **Trading terminal** (full breakdown below). A big popup reads "TRADE CLOSED **+$120.05K** / +121%" over a sunburst. | Core loop |
| 9.0–10.0 s | **NYPD mugshot #004298**: front and side profile against a lineup wall. | **Getting arrested** is a fail state or punishment |
| 10.5–12.0 s | Double doors open onto a trading floor with **red carpet**: an energy-drink vending machine, a lounge, a wall clock, an LED **ticker strip** (REX, BTC, OIL), **slot machines**, and rows of desks with CRTs. | Hub level; a casino inside the office |
| 12.0–13.5 s | Close-up of a cubicle: beige CRT, desk lamp, keyboard, mouse, a cigarette pack and an ashtray, with the city skyline outside. Trades close for +$50.1K and **+$723.88K**; session profit goes $4.32M → $8.83M. | Every desk is a trading station |
| 13.5–15.0 s | **Slot machine**. Reels: cherry, clover, bell, 7. The bet is set with −/+ (**$300**). The player pulls the lever and hits three bells: **$1.61K** payout with a coin explosion and confetti. | Gambling side-activity (a high-variance money source) |
| 15.0–16.0 s | A bearded NPC fires a money gun at the camera in front of a whiteboard that says "**MONEY TALKS**". | Juice / flex |
| 16.5–17.2 s | TV broadcast. The chyron reads "**LIVE — TRAMP: YOU'LL BE TIRED OF WINNING**" behind a podium with flags. | **News events that move markets** |

## The trading terminal, element by element (screenshot 06b)

**Header:** a `Free Mode` tag, a **pen tool** (draw on the chart) and a **trash** icon (clear the drawings).

**Chart**
- Candlesticks: green and red, a few seconds per candle.
- Volume bars along the bottom, with a `Vol` toggle.
- Time axis: `00:15 … 01:15`, so this is a run clock.
- Price axis: `1,000 – 1,020`, with a horizontal line at the entry price.
- Mouse cursor visible, which means the terminal is point-and-click on an in-world CRT.

**Watchlist**

| Symbol | Price | Change |
|---|---|---|
| BTC | 1,015.38 | +1.54% |
| GOLD | 1,501.24 | +0.32% |
| OIL | 1,496.03 | −0.33% |
| BNN | 101.01 | +1.01% |
| REX | 1,502.51 | +0.13% |

All five are fictional or rebalanced, with starting prices around 100, 1,000 and 1,500.

**Order panel**
- Asset card: ₿ **Bitcoin** — `BTC | Crypto` — `$1,015.38` `+1.54%`.
- Size: `−` **$1M** `+`, which steps the position size.
- `BUY` · `x100` · `SELL`. **x100 is leverage.** BUY is long, SELL is short.

**Positions**
- Tabs: `OPEN 0` · `CLOSED 1` · `Close All`.
- Columns: Asset · Side · Margin · Units · Profit · **Fees**.

**MY SESSION**
- `OPEN PROFIT +$1.03M`
- `LAST TRADE $0`

**Checking the math:** +121% on margin at x100 leverage means the price moved about **1.21%**, and BTC
shows +1.54% on the day. The numbers add up, so the model is a simple leveraged CFD:
`profit = margin × leverage × (exit/entry − 1) × side − fees`.

## Game systems we can infer

1. **Shared fund balance.** Everyone on the team trades out of one pot.
2. **Day = a 5-minute round** with a **profit quota**. Miss it and the run is over (it's a roguelike).
   The quota goes up each day.
3. **Markets:** about 5 assets, each with a random walk plus volatility and trend. News events
   ("TRAMP" speech) cause spikes.
4. **Leverage trading** (x1 up to x100), long or short, with position sizing, fees and liquidation.
5. **Items:** things like cigars, a smoke cloud or a money gun, probably bought between days to
   change the odds (as in Balatro or Lethal Company).
6. **Heat / police:** doing shady things raises heat. Cops raid from the elevator, and if they catch
   you it's a **mugshot** (a penalty or you're out).
7. **Casino & toys:** slots (a −/+ bet and a lever), basketball, an arcade. These are gambling side
   income and something to do while trades run.
8. **Setting:** a first-person 3D office with a hub trading floor, cubicles, an elevator and a lounge.
   The art is stylized low-poly cartoon with big eyes and flat shading.
9. **Juice:** big number popups, sunbursts, confetti, coin explosions, flying bills, LED tickers.

The audio sounds like a continuous music bed. I couldn't transcribe it (no speech model in this
environment), and I didn't hear any obvious voice lines.

---

## The 3-lens review (your 3-step format)

### 1 · How the plan works — the upside
- The core loop is simple, readable and social: *watch chart → go long or short → scream at your friends*.
  Sharing one balance creates moments like "you lost our money!", which is exactly the kind of
  streamer and clip content that made Lethal Company and R.E.P.O. blow up.
- A 5-minute round with a rising quota gives natural tension and a "one more run" hook.
- The trading math is cheap to build: it's all numbers and UI. The expensive parts (3D office, cops,
  ragdolls) can come in layers later.
- The multiplayer is **authoritative server + price ticks broadcast to everyone**, which is well-understood tech.

### 2 · What could break or what we're not accounting for
- **We'd be cloning a game that's launching right now.** Same name, same look or the "TRAMP" gag
  would be a copyright/trademark problem, and we'd lose to the original on day one anyway. We need
  our own name, art, and **at least one signature twist**.
- **Brand names**: the video shows a *Monster Energy* vending machine. Don't ship real brands.
- **Drugs / real-politician parody** content can hurt console ratings and ad-friendliness. Some
  streamers will skip it.
- **Pure random-walk charts feel like a slot machine.** If skill doesn't matter, the game gets old
  fast. We need readable patterns, news "tells" and items that reward reading the chart.
- **Multiplayer is the hardest part**: sync, latency, cheating, and players who drop mid-run while
  holding shared money. Steam networking vs. our own servers, plus hosting costs.
- **3D scope**: first-person 3D, animated NPCs, a police AI and ragdolls is a lot of work for a
  small team. The original has a dedicated 3D artist.
- **Real-money gambling laws**: fine as long as there's **no real money and no paid loot boxes**.
  Keep the slots purely in-game.

### 3 · The business side: does it work, competitors, money
- **Competitors in the same niche:**
  - *Broke Street* itself: co-op, the same fantasy, launching Q4 2026.
  - *Insider Trading* (Naiive Studio): a stock-market roguelike deckbuilder that launched on Steam on
    18 Feb 2026. It sits at "Mostly Positive" (79% of about 600 reviews), while its demo is at 96%.
    That shows real demand, but also that people are harsh once the price tag is on.
  - *Money Simulator*, *Trading Simulator* and *Market Street Tycoon* on Steam.
- **The opportunity:** the genre is proven and hot right now. The gap is **something Broke Street
  doesn't do**. Some examples:
  - PvP / rival hedge funds
  - Market manipulation and one player secretly being the SEC informant (a social-deduction angle)
  - Being browser / mobile-first with instant join by link
- **Money reality:** a web-based 2D/2.5D version can be built for close to $0. Hosting can run on
  free tiers until there are real players. Steam charges a $100 fee per game. A 3D Unity/Godot
  version with custom art usually needs either an artist or roughly $500–$3k in asset packs. I need
  your budget to size this properly.

### My opinion
Don't try to out-3D Broke Street. Start with **the part that makes the game fun: the shared-balance
multiplayer trading round** (terminal, 5 assets, leverage, quota, news events, 5-minute timer). Build
it as a web game you can play with friends by sharing a link. Once the loop is fun, add the office
around it (items, heat/cops, slots) and pick our twist. Then decide whether it's worth porting to a
3D engine for Steam.

## Open questions for you
1. **Engine / platform:** browser game (fastest to test with friends), or Unity/Godot for Steam from day one?
2. **2D/2.5D or full first-person 3D** like the video?
3. **Budget and team:** how much money can go into this, and is anyone else helping (art, code)?
4. **Co-op only (shared balance) or PvP too?** What's our twist?
5. **Name / theme**: we need our own. Any ideas?
6. **How much edgy content** (cigars, powder, politician parody): keep it, tone it down, or cut it?

---

## Decisions (answered)

| Question | Answer |
|---|---|
| Engine / platform | **Godot 4.7**, desktop app (Windows / macOS / Linux), free for friends. **Not** on Steam. |
| View | **First-person** 3D |
| Budget / team | Minimal; AI builds everything (all art is procedural, fonts are OFL, sounds are synthesized) |
| Mode | **Co-op** first (shared fund), plus **PvP** (own accounts, 3 days, snitching) |
| Name | **BAGHOLDERS** — "Everyone shares the bag." |
| Edgy content | Keep everything from the video: cigars, powder ("Nose Candy"), president parody ("TRAMP"), cops and mugshots |
| Streamers | Added as parodies: **TJZ** (TJR-style day trader, "OH MY GOD, TRADE!"), **KIMCHEE** (memecoin whale who pumps and rugs), **ROARING KITTEH**, **JIM CRAMMER** (inverse him) |

See the main [README](../README.md) for how the game plays.
