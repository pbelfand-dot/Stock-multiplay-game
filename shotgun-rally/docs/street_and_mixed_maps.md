# Street (tarmac) and mixed-surface maps: the plan

Asked for: "street and mixed maps... street control would be different than the control on the
dirt". Decided so far: **both kinds of street map, mountain tarmac first** (Monte Carlo / Spain /
Croatia style), town streets later; **mixed = sections in one stage** (part gravel, part tarmac,
like Rally Catalunya, which has run a gravel day then asphalt days since 2010).

## What it would be

**Mountain tarmac stages**
- An asphalt road (dark grey, a white line at each edge, sometimes a centre line), narrower than the
  forest roads in places, climbing and dropping more: switchback hairpins on a hillside.
- The edges tell you what a mistake costs: a low stone wall or armco on the drop side, a cut bank
  on the uphill side, grass verges on the flat. No forest crowding the inside of every bend: you
  can see further, so you go faster, which is what tarmac is.
- Villages: a few houses and a church tower close to the road, spectators on walls.
- Corner cutting drags gravel onto the asphalt: the inside of a well-used corner is dirty and
  slippery (a strip of "gravel" surface on the tarmac), like real tarmac rallies.

**Mixed stages**
- One stage, two or three sections: e.g. 1.2 km gravel, 1.4 km tarmac, a last 0.3 km of gravel. The
  join is a junction or a bridge: the co-driver calls it, the grip changes under you, and the first
  corners on the new surface are where you find out whether you adjusted.
- Gravel carried onto the tarmac for the first ~50 m after the join.

**Town streets (later)**
- Buildings right at the road, kerbs, 90-degree junctions, a cobbled square, barriers and crowds.

## How it drives differently (the new physics already does this)

Physics v2 has asphalt as its own surface (phase 6). With the car's gravel tyre:

| | Gravel | Asphalt |
|---|---|---|
| Cornering limit | 0.90 g | 1.14 g |
| Grip peaks at | 7 degrees of slip | 4.2 degrees |
| A sliding tyre keeps | 85 % | 78 % |
| Braking from 40 km/h | 7.7 m | 6.3 m |

So on tarmac the car grips harder, lets go earlier and more suddenly, and punishes a slide: neat,
precise lines and late braking. On gravel you slide it and steer it with the throttle. A mixed
stage makes you switch between the two. Two more pieces would make it real:
- **Tyres**: a tarmac tyre (more grip on asphalt, much less on gravel) as its own `TireConfig`, and
  choosing tyres for a mixed stage becomes a decision.
- **Setups**: "gravel" and "tarmac" presets in the garage (tarmac: lower, stiffer springs and
  bars, quicker steering).

The current car (the one in the game today) has a tarmac grip figure too, so a first version can
run before the new physics replaces it, but it won't feel properly different until then.

## Three lenses

### 1. If it works: why it's good
- Variety from the same generator: every seed can be a forest gravel stage, a mountain tarmac stage
  or a mixed one. Story mode gets a "Monte" rally and a mixed rally.
- It shows off the new physics: the same car, the same controls, and you can feel the surface.
- For the crew game it's better still: tarmac is faster, so the co-driver's timing matters more,
  and a surface change is a call the driver can't afford to miss.

### 2. What won't work, or what we're not counting on
- **Art**: tarmac needs its own scenery kit (walls, armco, cut banks, houses, road lines). The
  forest kit doesn't carry over. This is the biggest piece of work.
- **The co-driver's voice** has no words for "bridge", "tarmac", "gravel", "junction", "narrows"
  or "keep in / keep out" (today a bridge is called "caution"). New clips in the same voice, or
  the notes stay with the words we have.
- **Speed**: tarmac is faster, so the AI co-driver's call timing, the autopilot the tests drive
  with, and the stage lengths need retuning.
- **The current car**: tarmac grip is one number for it; real tarmac handling needs the new
  physics in the game first (phase 9 and the switch).
- **Dirt on the road** has to be a surface patch the tyres can find, not just a darker colour.
- **Online**: both machines must agree on the surface sections (they come from the seed, so they
  will, but it needs a test).
- **Performance**: walls and houses add a lot of objects; they need the same chunking and draw
  distances the trees use.

### 3. Is it worth it (cost, competitors)
- **Competitors**: DiRT Rally 2.0 and EA Sports WRC have tarmac rallies; art of rally shows a
  stylised game can carry several surfaces. None of them is built around one person driving and
  a friend reading the map, which is what this game is. Tarmac and mixed stages are content that
  makes that idea last longer; they aren't the reason to buy it.
- **Cost**: it's development time, not money, except for new voice clips if we generate them (the
  pack was generated before; more clips may cost credits on that service: your call).
- **Order that gives the most for the least**: surface sections and the asphalt road first (cheap,
  it uses the generator and the new physics), then the mountain kit, then tyres / setups, then
  towns (most art, least new driving).

## Proposed order

1. **Surface sections** in the generator (gravel / asphalt per stretch of road), the asphalt road
   look (dark, edge lines, no wheel tracks or berms), the "asphalt" surface on the road's bodies so
   both cars feel it; mixed stages with a junction or bridge at each join; dirt carried onto the
   tarmac after a join.
2. **Mountain tarmac kit**: walls and armco on the drop side, cut banks, fewer trees, villages, more
   climb and switchbacks.
3. **Tyres and setups** in the garage (with the new physics).
4. **Town streets**.
5. **Story mode**: a tarmac rally and a mixed rally in the championship.

## Questions to settle before building
- Snow and ice patches on the tarmac (a real Monte Carlo thing), or dry tarmac only?
- Tarmac tyres and setup presets in the garage: yes?
- New co-driver words in the same voice (may cost credits), or keep to the words we have?
- Should the first tarmac stages wait for the new physics to be in the game (it feels right only then), or go in now on the current car?
