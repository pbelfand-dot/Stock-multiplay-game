# SHOTGUN RALLY: how to work on it

## Standing instructions from the owner
- **Merge after every piece of work**: fast-forward `main` to the work branch, then check that
  main's CI run (`.github/workflows/shotgun-rally.yml`) passes and the `shotgun-latest` release
  (the download) has the new build.
- Plans get three lenses: if it works (why it's good), what won't work / what's not counted on,
  and is it worth it (cost, competitors). Ask questions freely; double-check facts (search, don't
  guess); give opinions.

## Making assets: Higgsfield or Blender
- **Looks matter more than function** (car bodies, tyres, liveries, crew, scenery, anything the
  player looks at): Higgsfield. **Always tell the owner what you are going to generate, and on
  what, before using it** (it spends their credits).
- **Mechanical parts** (drivetrain, suspension arms, anything functional or hidden: the car has a
  steel skid plate underneath, so the drivetrain isn't seen): build them procedurally, in Blender
  (headless, `blender -b --python ...`; install with apt if missing) or in code. Not Higgsfield.

## Tests
- `GODOT=/path/to/godot tests/run_all.sh` runs everything headless (~10 minutes; each run gets a
  fresh user:// through XDG_DATA_HOME). The physics runs at 120 ticks a second: tests use
  `--fixed-fps 120`. The physics suite alone: `godot --headless --fixed-fps 120 --path . -s
  tests/physics_v2_check.gd` (~30 s).
- New test run names in `tests/physics_v2_check.gd` become judge function names (`_judge_<name>`):
  no hyphens or colons, and no " on " (that marks a surface run).
