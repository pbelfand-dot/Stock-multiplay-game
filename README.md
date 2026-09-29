# BAGHOLDERS

**Everyone shares the bag.** A first-person, 1–6 player trading floor game for you and your friends.
You're a desk of degenerate traders at a hedge fund. Everyone trades from **one shared fund**, you have
**5 minutes a day** to hit a **profit quota that keeps going up**, and if you get too greedy, **the cops
come out of the elevator.**

## ⬇ Download (always the newest build)

The links never change. Every update to `main` replaces the files behind them:

- **Mac:** [Bagholders.zip](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/latest/Bagholders.zip)
- **Mac (older Intel, pre-2020):** [Bagholders-Intel.zip](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/latest/Bagholders-Intel.zip)
- Windows: [Bagholders-Windows.zip](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/latest/Bagholders-Windows.zip) · Linux: [Bagholders-Linux.zip](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/download/latest/Bagholders-Linux.zip)
- All of them on one page: [releases/latest](https://github.com/pbelfand-dot/Stock-multiplay-game/releases/tag/latest)

On a Mac: unzip it, then **right-click BAGHOLDERS.app → Open** the first time.

Inspired by the *Broke Street* trailer (see [`docs/VIDEO_BREAKDOWN.md`](docs/VIDEO_BREAKDOWN.md)).
Built in **Godot 4.7** — free, no accounts, no store.

![The cast](docs/screens/lineup.jpg)

| | |
|---|---|
| ![The Tailor](docs/screens/tailor.jpg) | ![Hair & facial hair](docs/screens/hair_styles.jpg) |

| | |
|---|---|
| ![Trading floor](docs/screens/office.jpg) | ![Terminal](docs/screens/terminal.jpg) |
| ![TRAMP on the office TV](docs/screens/tv_tramp.jpg) | ![Tony the Plug](docs/screens/tony.jpg) |
| ![Trade closed](docs/screens/trade_closed.jpg) | ![Slots](docs/screens/slots.jpg) |
| ![Cops](docs/screens/cops.jpg) | ![Mugshot](docs/screens/mugshot.jpg) |
| ![Streamer corner](docs/screens/streamers.jpg) | ![Tony the Plug](docs/screens/shop.jpg) |

---

## Modes

| Mode | How it works |
|---|---|
| **Co-op** (default) | One shared fund (starts at $25K). Hit each day's quota (x1.5 every day) or the fund is busted. Overhead gets paid every night. See how many days you survive. |
| **PvP** | Everyone gets their own $25K. Same market, same news. Miss the quota and you're out. Richest after 5 days wins and takes a championship trophy home for good. No catch-up help: best one wins. Snitching allowed. |
| **Solo** | Co-op with just you. |

## Progression

- **Random day events.** Most mornings something is going on, announced on the TV and at the top of
  your screen, and the after-hours summary shows **tomorrow's forecast** so you can plan:
  FLASH CRASH (everything dumps, then the circuit breaker halts trading for 20s), FED DAY (Powww
  speaks halfway through, 5–8% moves), MEME MANIA, BULL RUN, BEAR MARKET, SEC AUDIT (heat x2),
  TRAMP TWEETSTORM, BLACK FRIDAY (boutiques 35% off), REX EARNINGS, CRACKDOWN (cops at 70 heat),
  LIQUIDITY CRUNCH (fees/spreads up) and BONUS DAY (the firm pays the overhead).
- **Tony's contracts.** Three goals every morning (easy, medium, hard), shown on the left of the
  screen. Finish one and Tony pays cash + XP on the spot. Event days swap in a themed one.
- **Ranks with perks.** ANALYST gets a 4th contract, TRADER cheaper fees, DEGEN bigger contract
  payouts, WHALE lower overhead, MARKET MAKER half spreads, WOLF sees every headline 3s early.
- **Flex that does something.** Every bag and watch has a perk (Crownwell: cops respect the watch,
  heat cools 30% faster; Valmont: fees −15%; Chavél: +15% XP...).
- **Office upgrades** at the FLEX SHOP counter, yours for good and on your desk: Standing Desk Mat,
  Tony's Rolodex, Police Scanner, Unpaid Intern, Bloomberg Terminal, Prime Broker Account.
- **Co-op milestones.** The fund passing $100K, $250K, $1M... pays the whole desk XP.
- **Saves are the host's.** Only the trader who started a run can load it (friends just rejoin).
- **Ready-up.** After the closing bell (and in the lobby) the game waits: walk around, shop, then
  press ENTER when you're ready. The bell rings once everyone is ready ("waiting on Bob"); the host can
  START ANYWAY if someone went AFK. SAVE GAME is on the after-hours screen and in the ESC menu
  (mid-day it keeps that morning).

## What's in the office

- **Trading terminal** at every desk, like the trailer's: candlesticks, volume, pen tool, watchlist,
  size −/+, **x1–x100 leverage**, BUY (long) / SELL (short), positions with profit and fees, MY SESSION,
  and a big **TRADE CLOSED +$120.05K** popup. Get liquidated and you lose the margin.
- **18 tickers** (all parody): crypto (BTC, ETHR, DOGGO, BNN, $WAGMI), stocks (REX, PEAR, NVDUH, GAMR,
  AIRX, BURG, PHRM, JPMG), commodities (GOLD, OIL, GAS) and indexes (SPX, FEAR). **Sectors move
  together**: news on a leader drags its followers a beat later (BTC → the other coins, SPX → the
  stocks, OIL up → the airline down, FEAR goes the opposite way of the S&P). The terminal's SELL
  button reads **SHORT** when you have nothing to sell.
- **LIVE TV + news** that moves the market (all parody):
  - **TRAMP** — "YOU'LL BE TIRED OF WINNING", tariffs, "I love Bitcoin"…
  - **TJZ** (day-trading streamer) — "OH MY GOD, TRADE! LONG BTC!" He's right about 65% of the time.
  - **KIMCHEE** (memecoin whale) — pumps $WAGMI… then usually rugs it. Sell in time.
  - **JIM CRAMMER** — "BUY BUY BUY!" Inverse him: he's wrong 75% of the time.
  - **ROARING KITTEH** — posts a cat meme and REX goes nuts.
  - **FED CHAIR POWWW** — rate cuts and hikes. Plus **BREAKING** news.
  - The streamers sit in the **streamer corner** with speech bubbles.
- **Tony "The Plug"** in the lounge sells items (keys **1–6** to use them):

  | Item | Price | Heat | What it does |
  |---|---|---|---|
  | Victory Cigar | $5K | +5 | Zero trading fees for 60s, plus a smoke cloud |
  | Nose Candy | $15K | +25 | Sprint x1.6 for 40s, and you see headlines 6s early |
  | Insider Tip | $25K | +40 | Tells you exactly what the next headline will do |
  | FLEX Gun | $10K | 0 | Hold left mouse to make it rain; cops stop to grab bills |
  | Saul Goodmann | $30K | 0 | Your next arrest gets dismissed |
  | SEC Snitch Line | $20K | 0 | PvP only: +60 heat on the richest rival |

- **Heat & cops.** Shady items and huge wins add heat. At 100 heat two cops come out of the elevator
  after you. Sprint, **dive (C / Ctrl)**, or make it rain to shake them. Survive 35s and they leave.
  If they catch you:
  - you get an **NYPD mugshot**
  - you're **fined 15%**
  - you sit in the holding cell for 20s
- **BAG SLOTS** in the casino corner: set your bet with −/+ and pull the lever. Three 7s pay 60x.
- **Characters in the trailer's style, modeled in Blender.** `tools/blender/build_characters.py`
  builds them procedurally into `assets/characters/character_kit.glb`:
  - **Base:** one skinned "stick figure" skeleton, and a smooth base body with bone-heat weights.
  - **Face (the same for everyone):** the trailer's egg head with bulging tired eyes, droopy lids,
    dark bags, an orange nose, thick brows and a thin mouth.
  - **Clothing layers:**
    - suit jacket (lapels, pockets, buttons), shirt V, cuffs, tie or long tie
    - dress shirt, cop uniform with duty belt, hoodie, tee
    - slacks, dress shoes, sneakers
  - **Hair styles:** slick, swept, swoop, short, buzz, messy, afro, long, bald.
  - **Facial hair:** mustache, goatee, full, stubble.
  - **Glasses:** shades, specs.
  - **Hats:** cop, headset, headband, beanie, cap.
  - **Accessories:** watch, ring, gold chain.
  - Clothing copies the body's weights, so it moves with the body. Every pose is driven on the bones
    (walk, blink, talk, aim, smoke, dive, cuffed and more).
- **The Tailor** (main menu): customize your trader with a live 3D preview.
  - Outfit, suit color, pinstripes, shirt, tie, pants, shoes, hair, skin tone, facial hair, glasses,
    hat, watch, chain and ring. There's also a randomize button.
  - Your look is saved and sent to everyone in the game.
- **TRAMP on the office TV** at a podium between two flags, and a **3D mugshot of your own character**
  holding the NYPD placard.
- **Basketball hoop.** Grab the ball (E), throw it (left mouse). A swish is +$1,000 to the fund.
- The rest of the office: red carpet, CRT desks, city skyline, the MONEY TALKS whiteboard, the ticker
  strip and the opening bell.

## The commute

Every morning you wake up at home in Magnolia Heights (buy a house from a FOR SALE sign, or rent one until you do) with your car in the driveway, and you have 2:45 to get to BAGHOLDER CAPITAL downtown before the opening bell: out the neighborhood, up the on-ramp, 1.5 km down the highway, off at downtown, up the elevator. Some mornings the alarm doesn't go off and you have about a minute and a half: cut up through traffic. Miss the bell and you're LATE until you're up the elevator.

Hold 110+ mph and highway patrol may clock you: lose them (230 m away for 6 s) or get pulled over (jail + a ticket). Crashes cost you speed. You start with no car: a cab from the Magnolia roundabout costs $300 and crawls through rush hour, so your first buy is the used TOROLA ($8K) at the BEMZE dealership (its own highway exit, half a kilometre past Magnolia Heights), which also sells the 540i, M2, M3, M4, M5 and M8 in ten factory colors.

Cabs are real: call one at a taxi stand or from the phone's RIDES app and a yellow cab pulls up where you are (downtown, Magnolia St, your house, the BEMZE lot), you ride in the back and the cabbie drives you to downtown, Magnolia Heights, home or BEMZE on the real roads and highway. SPACE skips the ride (in rush hour the minutes still go by), E gets you out wherever you are.

The highway is a New York expressway (brick walk-ups with water towers, Jersey barriers, green exit signs, potholes, yellow cabs) and a 7.5 km loop: past BEMZE it curves round and comes back along a second leg and through the Bagholder-Battery Tunnel to downtown, so you can keep driving forever. Its traffic is the same for everyone: the host runs it round every player and streams each one the cars near them.

## Controls

| Key | Action |
|---|---|
| WASD / Shift / Space | Move / sprint / jump |
| C or Ctrl | Dive |
| E | Use desk terminal, slots, Tony, grab ball, ATM, money counter |
| Left mouse | Throw ball / FLEX gun / fire your gun |
| Right mouse | Aim (with a gun out) |
| Q | Draw your gun / next gun / holster (buy them at BIG IRON on the street) |
| J | Flash the cash you're carrying |
| N | Lay your cash out on the table / floor (N again picks it up) |
| K | Photo mode (fly the camera, pose, filters, SNAP: saved to Pictures/BAGHOLDERS) |
| E (at your car) | Get in / out. Driving: W gas · S brake/reverse · A/D steer · Space handbrake · C cockpit/chase cam |
| P | Phone (works at the terminal too; P or Esc puts it away). Home screen apps: FEED (Tramp posts before the TV), KWIK LIVE (stream + ride to the studio), BANK (fund, cash, today's P&L, open positions), MAPS (live commute map), RIDES (pick your car or call a cab), TONY (today's contracts as texts), HOMES (your place + listings), CAMERA (photo mode) |
| 1–6 | Use items |
| Tab | Scoreboard |
| T | Chat |
| Enter | (Host) ring the opening bell / back to lobby |
| Esc | Close panel / pause (mouse sensitivity is in there) |

**Terminal hotkeys:**

| Key | Action |
|---|---|
| B / S | Buy / Sell |
| Q / E | Size down / up |
| L | Cycle leverage |
| C | Close all |
| 1–6 | Switch asset |

## Play with friends

1. Everyone downloads the game for their computer (see **Get the game** below).
2. One person clicks **HOST CO-OP** (or **HOST PVP**).
3. Everyone else types the host's IP and clicks **JOIN**. The port is 7777.
   - **Same Wi-Fi / same house:** use the host's local IP, e.g. `192.168.1.23`.
     On Windows run `ipconfig`; on Mac it's in System Settings → Wi-Fi → Details.
   - **Different houses (easiest):** everyone installs **[Tailscale](https://tailscale.com)**
     (free, takes 2 minutes) and logs into the same account or tailnet. Then join with the
     host's Tailscale IP (`100.x.y.z`). No router setup needed.
   - **Different houses (advanced):** the host forwards **UDP 7777** on their router and shares
     their public IP.
4. The host presses **Enter** to ring the opening bell. Trade, gamble, run from the cops.

The first time you host, Windows Firewall will ask to allow it. Click **Allow**.

## Get the game

Every push builds the game automatically:

1. Go to the repo's **Actions** tab and open the latest **Test & Build** run.
2. Download **Bagholders-Windows**, **Bagholders-macOS** or **Bagholders-Linux** from Artifacts.
3. Unzip it and send it to your friends. For a public download link, push a tag like `v0.1`.
   That creates a GitHub Release with all three zips.

Each platform needs one extra step the first time:

- **Windows:** it's a single `Bagholders.exe`. SmartScreen may say "unrecognized app". Click
  **More info → Run anyway**. That happens because the exe isn't code-signed.
- **macOS:** grab **Bagholders** (M1/M2/M3/M4 Macs) or **Bagholders-Intel**
  (older Macs). **Bagholders-macOS** is the universal build that works on both, at twice the size.
  - Unzip it and double-click `BAGHOLDERS.app`. macOS will say it "could not verify" the app.
  - Click **Done**, then open **System Settings → Privacy & Security**, scroll down, and click
    **Open Anyway**. Do it within an hour of the warning.
  - Since macOS 15 (Sequoia), right-click → Open no longer skips this step.
  - Terminal alternative: `xattr -dr com.apple.quarantine BAGHOLDERS.app`
  - Getting rid of the warning entirely needs Apple's $99/yr developer program.
- **Linux:** run `chmod +x Bagholders.x86_64`, then `./Bagholders.x86_64`.

## Run from source / keep building it

1. Install **[Godot 4.7.2](https://godotengine.org/download)** (standard build, not .NET).
2. Open `project.godot` and press **F5**.

Everything is plain GDScript and there are no binary scenes: the level, characters and UI are all
built in code, so an AI can keep extending it.

```
scripts/
  sim/      market.gd (price model), news.gd (TRAMP/TJZ/KIMCHEE...), ledger.gd (leverage math), rules.gd (tuning)
  net/      net.gd (ENet host/join), match.gd (server-authoritative game loop), config.gd, sfx.gd
  art/      character.gd (skinned kit loader: looks, presets, bone animation), props.gd, shapes.gd, batcher.gd
  world/    world.gd, office_builder.gd (the whole level), ball.gd
  player/   player.gd (first person), cop.gd (navmesh chase AI)
  ui/       hud.gd, terminal.gd, chart.gd, slots_ui.gd, shop_ui.gd, trade_popup.gd, overlays.gd, tv_screen.gd, main_menu.gd
tests/      test_sim.gd, smoke_driver.gd (2-player end-to-end), screenshot_driver.gd, run_all.sh
tools/      blender/build_characters.py (the character kit), make_sfx.py (sound effects),
            thin_macos.py (splits the Mac build per chip)
assets/     characters/character_kit.glb, fonts/, sfx/
```

Tuning (money, quotas, heat, item prices, slot odds) lives in `scripts/sim/rules.gd`.

**Rebuilding the characters:** run `pip install bpy==4.5.14`, then
`python3 tools/blender/build_characters.py`. That takes about 10 seconds and rewrites
`character_kit.glb`. To add a new hair style or garment, add a builder function to that script, then
add the option to `OPTIONS` in `scripts/art/character.gd`.

### Tests

```bash
GODOT=/path/to/godot tests/run_all.sh
```

That runs:

- a compile check
- about 5,000 sim unit checks (the x100 leverage math matches the trailer: +1.21% move → +121%;
  day events, contracts and perks)
- save → continue, and someone else can't load your save
- day events end to end: a forced flash crash + circuit breaker, contracts paying, upgrades,
  Black Friday prices, the Fed tip, a co-op milestone, the PvP championship trophy
- a real two-instance multiplayer smoke test, once in co-op and once in PvP

The smoke test drives a full session: join, trade, buy and use an item, slots, chat, basketball,
then a cop raid, an arrest and the jail teleport. CI runs all of it on every push.

## Credits & notes

- Font: [Oswald](https://github.com/googlefonts/OswaldFont), SIL Open Font License (`assets/fonts/OFL-Oswald.txt`).
- Sound effects are synthesized by `tools/make_sfx.py`. No samples are used.
- Every person, brand and event in the game is **parody / fiction**. Nothing in it is financial
  advice. There's no real money anywhere.
