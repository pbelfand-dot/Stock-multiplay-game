# No Hesi: what the owner's three clips show, and what cut up takes from them

No Hesi is a set of Assetto Corsa cut-up servers: dozens of players on one long highway
map full of AI traffic, weaving through it as fast and close as they dare. The owner sent
three vertical clips (about 14 s each; frames pulled every second with ffmpeg, looked at
as contact sheets):

| Clip | What's in it |
|---|---|
| "My Best No Hesi Clip" | Night. A white M5 weaving through dense traffic on a Shutoko-style elevated expressway: sodium street lamps, toll booths and gantries, office towers lit up, tail lights glowing. Chase camera. |
| "No Hesi in 4K Max Graphics" | Day, overcast. A grey M3 on an urban US highway under overpasses, past high-rises, into a dark tunnel lit orange. Heavy motion blur; traffic smears past. |
| "Satisfying drifting in No Hesi" | Day, sunny, Los Angeles-style freeway (palm trees, green "San Bernardino / Cesar Chavez Ave" signs, concrete lanes, yellow left edge line). A winged E92 M3 drifting through traffic at freeway speed on a wheel and pedals; black tyre marks all over the road; another player's car with a floating name tag and score ("slaptrain #125.1K"). It ends off the freeway in a car park. |

## What they do, against what we had

| | No Hesi | SHOTGUN RALLY cut up (before) | Now |
|---|---|---|---|
| Camera | low and close behind (~1.5 m up, ~5 m back), over the roof to the horizon, wide and widening with speed, trailing as the car weaves | high (2.3 m) and back (6.5 m), looking down at the road | **street chase camera** (cut up, touge): 1.5 m up, 5.2 m back, horizon high, 72° to 88° with speed, trails a little |
| Speed | strong motion blur at 150-250 km/h; the car stays sharp | none | the graphics agent's **speed blur** (radial, speed-scaled, sharp within ~6 m; off on LOW and the web build) |
| Night | sodium lamps, glowing tail and head lights, lit windows | day / golden only | the graphics agent's night pieces (lamp heads with glare, light pools on the road, glowing traffic lamps, lit windows), to be wired into the loop |
| Traffic | dense and mixed: saloons, SUVs, vans, box trucks (the slow lanes' rolling walls) | dense packs (insane), cars only | packs as before; **no trucks yet** (see below) |
| Handling | Assetto Corsa: real tyres, weight transfer; drifting is a skill | ARCADE | **SIM STREET** (real road-tyre grip per car, factory ABS and TC, no drift helpers) |
| Tyre marks | black lines stay on the road | smoke only | **tyre marks** on sealed roads (slides, lock-ups, wheelspin), kept |
| Other players | many cars on one server, name tags with scores | one car, two seats (driver and co-driver) | not yet (see below) |
| Map | long real-world-style highways (Shutoko, LA freeways) | the LAKESHORE LOOP: city viaduct, tunnels, three suspension bridges | the same loop; green US-style signs are a small next step |

## The bigger items, three ways

**1. Trucks and vans in the traffic** (box trucks, a delivery van, an articulated lorry).
- *Why it works:* in every No Hesi clip the slow lanes are walls of trucks; they're what
  make the weaving lines and the near misses. Our traffic code takes any registry car with
  a "traffic" block: a truck is a model plus a JSON.
- *What won't work / not counted on:* no truck model exists in our inventory. CLAUDE.md:
  anything the player looks at is made with Higgsfield, after telling the owner (it spends
  credits). Trucks are long (8-16 m), so the traffic's lane changes and gaps need their
  real length (the code reads each model's bounds, so mostly yes). Kinematic trucks never
  roll or jack-knife.
- *Worth it:* yes, the biggest single change to how cut up feels after the handling. Cost:
  three Higgsfield 3D generations (credits), then the usual converter and checks.
- **Waiting on the owner's go-ahead to spend Higgsfield credits.**

**2. Online cut up: several cars on the loop together** (No Hesi's servers).
- *Why it works:* it's the heart of No Hesi (racing your friends through the traffic, name
  tags, scores). Our networking already streams a car ~30 times a second to the co-driver.
- *What won't work / not counted on:* the game is built round one car with two seats;
  several cars need each driver's car simulated on their own machine and streamed to the
  others, the traffic agreed between machines (one machine's traffic, sent to all, or the
  same seed and clock everywhere), collisions between cars that are each simulated
  elsewhere (the hard part in every racing game), a lobby for more than two. Days of work,
  and it touches the parts that make co-op work today.
- *Worth it:* for a game played with friends, probably the most fun thing it could add, but
  it's a project of its own: plan it properly first (one question for the owner: how many
  of you would drive at once?).

**3. Night on the loop.**
- *Why it works:* clip 1 is the iconic look. The pieces are being made in the graphics pass
  (cheap fake light pools rather than real lights: well under 0.5 ms).
- *What won't work:* on the web/Chromebook build (Compatibility renderer) it'll be plainer
  (no glow); real headlight beams cost frame time on weak PCs (the quality setting decides).
- *Worth it:* yes, once the graphics work is approved and merged: wiring it into the loop
  is small.
