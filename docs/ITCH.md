# Putting SHOTGUN RALLY on itch.io

Everything on the GitHub side is ready. Every push to `shotgun-rally` builds the game, and once
the two settings below exist, the build also uploads itself to itch.io (Windows, Linux and Mac).
itch.io is free to use, and for a free game you never pay anything.

## 1. Make the itch.io page (about 10 minutes, once)

1. Make a free account at [itch.io](https://itch.io/register) if you don't have one.
2. Go to **Dashboard → Create new project** and fill it in:

   | Field | What to put |
   |---|---|
   | Title | `SHOTGUN RALLY` |
   | Project URL | `shotgun-rally` (the page becomes `your-name.itch.io/shotgun-rally`) |
   | Short description | `You drive. Your friend rides shotgun with the map.` |
   | Classification | Game |
   | Kind of project | Downloadable |
   | Pricing | **No payments** (or "$0 or donate" if you want tips) |
   | Uploads | leave empty: GitHub uploads the builds for you |
   | Description | the text in the box below |
   | Genre | Racing |
   | Tags | `rally`, `co-op`, `multiplayer`, `driving`, `low-poly`, `first-person`, `racing`, `funny` |
   | Cover image | `docs/itch/cover.png` (630 × 500) |
   | Screenshots | the four in `docs/screens/` |
   | Visibility | start with **Draft**, switch to **Public** when you're happy |

3. Save.

```text
SHOTGUN RALLY is a cartoony co-op rally game for two.

One of you DRIVES. The other RIDES SHOTGUN with a map of the road ahead, works out
what's coming and yells it: "LEFT! TIGHT LEFT! OVER THE CREST!" The driver can't see
round the next bend. The co-driver can look at the map or watch the road, never both.

- Endless stages: every stage is generated, a new road through the forest every time
- Real co-driver jobs: count the start, call the corners, work the wipers when mud covers the windshield
- No friend online? The AI co-driver takes the seat and calls the stage for you
- Keyboard or controller

PLAY WITH A FRIEND
One of you clicks HOST (pick your seat), the other types the host's IP and clicks JOIN.
Same Wi-Fi: use the host's local IP. Different houses: both install Tailscale (free)
and join with the host's Tailscale IP.

DRIVER: WASD / arrows, SPACE handbrake, R reset (+5 s)
CO-DRIVER: hold RIGHT MOUSE (or Q) to look at the map, F wipers, mouse to look around
```

## 2. Connect GitHub to it (2 minutes, once)

1. On itch.io go to **Settings → API keys**
   ([itch.io/user/settings/api-keys](https://itch.io/user/settings/api-keys)) → **Generate new API key**,
   and copy it.
2. On GitHub open this repo → **Settings → Secrets and variables → Actions**:
   - **Secrets** tab → **New repository secret**: name `BUTLER_API_KEY`, value = the key.
   - **Variables** tab → **New repository variable**: name `ITCH_PROJECT`, value =
     `your-itch-name/shotgun-rally`.
3. Done. The next push to `shotgun-rally` (or **Actions → SHOTGUN RALLY · test & build → Run workflow**)
   uploads three builds to the page: `windows`, `linux` and `mac-universal`.

The key is a password: it only goes in that Secrets box, never in a file or a chat.

## How it works

The workflow `.github/workflows/build.yml` runs the tests, exports the game, then uses itch.io's
uploader (**butler**) to push each zip to its own channel. butler only uploads what changed, and
the itch app keeps players updated automatically. If the two settings aren't there, that step is
skipped, and the GitHub download links still work on their own.
