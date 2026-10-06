#!/usr/bin/env bash
# Runs every headless test. Usage: GODOT=/path/to/godot tests/run_all.sh
set -u
G="${GODOT:-godot}"
cd "$(dirname "$0")/.."
fail=0
# a private port per run, so parallel runs (other checkouts) never cross wires
P=${SR_PORT:-$((20000 + RANDOM % 30000))}
T=$(mktemp -d)
# a fresh user:// for every run (settings, saves): the results can't depend on what
# this machine saved before (the car reads its driver aids from the settings)
export XDG_DATA_HOME="$T/data"
# Every Godot run has a time limit: a hang fails that one test (and says so at
# the end) instead of stalling the whole job with no log.
run_g() {
  local limit=$1; shift
  timeout -k 10 "$limit" "$G" "$@"
  local rc=$?
  [ $rc -eq 124 ] || [ $rc -eq 137 ] && echo "timed out after ${limit} s: godot $*" >> "$T/timeouts.log"
  return $rc
}
echo "== compile check"
run_g 180 --headless --path . -s tests/check_scripts.gd 2>&1 | grep -E "checked|COMPILE FAIL" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== stages: 20 seeds, deterministic, no crossings, every corner has a note, wooden bridges; tarmac and mixed stages"
run_g 240 --headless --path . -s tests/stage_check.gd 2>&1 | grep -E "\[stage\] (FAIL|STAGES|words|[0-9]+ wooden)" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== car + stage: the autopilot drives whole stages, 0-100, braking, handbrake flick"
for seed in 3 7 15; do
  run_g 360 --headless --fixed-fps 120 --path . -s tests/drive_check.gd -- --seed=$seed 2>&1 | grep -E "\[drive\] (FAIL|DRIVE|ok   finished)" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
done
echo "== tarmac (with snow and ice) and a mixed stage: the autopilot drives them, the tyres feel each surface"
for args in "--seed=21 --surface=tarmac --ice" "--seed=7 --surface=mixed"; do
  run_g 360 --headless --fixed-fps 120 --path . -s tests/drive_check.gd -- $args 2>&1 | grep -E "\[drive\] (FAIL|DRIVE|ok   finished|ok   the tyres)" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
done
echo "== handling: full steering = the most grip at 50 / 80 / 110 km/h, lift-off + handbrake rotation"
run_g 300 --headless --fixed-fps 120 --path . -s tests/handling_check.gd 2>&1 | grep -E "\[handling\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== tyres and setup: tarmac tyres grip more on asphalt and far less on gravel, the tarmac setup rolls less, AUTO picks for the stage"
run_g 180 --headless --fixed-fps 120 --path . -s tests/tuning_check.gd 2>&1 | grep -E "\[tuning\] (ok|FAIL|TUNING)" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== jumps: air time by speed, clean four-wheel landings, no second bounce, braking in the air dips the nose"
run_g 300 --headless --fixed-fps 120 --path . -s tests/jump_check.gd 2>&1 | grep -E "\[jump\] (ok|FAIL|JUMPS|seed)" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== drift dirt: dust + stones when it slides, none when it cruises or flies"
run_g 180 --headless --fixed-fps 120 --path . -s tests/fx_check.gd 2>&1 | grep -E "\[fx\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== garage + story: credits, buying, upgrades, car setups, championship unlocks and standings"
run_g 120 --headless --path . -s tests/story_check.gd -- --profile=$T/story.cfg 2>&1 | grep -E "\[story\] (FAIL|STORY)" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== road edges: flush flat grass past the edge, trees stand back, a slide wide can be saved"
run_g 300 --headless --fixed-fps 120 --path . -s tests/runoff_check.gd 2>&1 | grep -E "\[runoff\] (FAIL|RUNOFF|ok   off)" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== physics v2 (phases 1-9): suspension, bumps; skid pad, slope; drive, wheelspin, brakes, lock-ups; braking in turns, trail braking; engine, gears, diffs; surfaces; handbrake, anti-roll bars, dampers; aero, driver aids, Settings, telemetry; the rally manoeuvres (120 Hz)"
run_g 180 --headless --fixed-fps 120 --path . -s tests/physics_v2_check.gd 2>&1 | grep -E "\[physics\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== cockpit: the gloves cover the sleeve ends wherever the hands are, both crew belted in, the hand on the gear lever, numbered dials, shift lights"
run_g 180 --headless --path . -s tests/cockpit_check.gd 2>&1 | grep -E "\[cockpit\] (FAIL|COCKPIT|ok   straight)" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== ride: how much the car bounces on two stages (shaking at the eye, the hardest landing)"
for seed in 3 15; do
  run_g 360 --headless --fixed-fps 120 --path . -s tests/ride_check.gd -- --seed=$seed 2>&1 | grep -E "\[ride\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
done
echo "== view: the driver's eye at 144 down to 12 fps and through hitches: no shaking frame to frame"
run_g 120 --headless --fixed-fps 120 --path . -s tests/view_check.gd 2>&1 | grep -E "\[view\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== sound: the engine's four loops blended by the revs, shifts and anti-lag pops, the co-driver over the effects"
run_g 120 --headless --fixed-fps 120 --path . -s tests/sound_check.gd 2>&1 | grep -E "\[sound\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== AI co-driver: every call said in time, from where the car is"
run_g 480 --headless --fixed-fps 120 --path . -- --aicheck --autostart --autopilot --seed=8 --timeout=400 --profile=$T/ai.cfg 2>&1 | grep -E "\[ai\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
for case in "driver codriver gravel" "codriver driver mixed"; do
  set -- $case
  echo "== 2 players: host $1, guest $2 (the driver's machine streams the car), a $3 stage: both build the same surfaces"
  hp_ap=""; cl_ap=""
  [ "$1" = driver ] && hp_ap="--autopilot" || cl_ap="--autopilot"
  run_g 260 --headless --path . -- --host --seat=$1 --autostart $hp_ap --smoke=host --port=$P --seed=5 --surface=$3 --length=900 --timeout=180 --profile=$T/host.cfg > $T/host.log 2>&1 &
  hp=$!
  sleep 3
  run_g 260 --headless --path . -- --join=127.0.0.1 --port=$P --name=Bob $cl_ap --smoke=client --length=900 --timeout=180 --profile=$T/client.cfg > $T/client.log 2>&1; c=$?
  wait $hp; h=$?
  grep -h "\[smoke\]" $T/host.log $T/client.log
  hs=$(grep -ho "surfaces .*" $T/host.log); cs=$(grep -ho "surfaces .*" $T/client.log)
  if [ -z "$hs" ] || [ "$hs" != "$cs" ]; then echo "!! the two machines built different surfaces: '$hs' / '$cs'"; fail=1; fi
  if grep -hE -A2 "^(SCRIPT ERROR|ERROR: Node not found)" $T/host.log $T/client.log; then echo "!! engine errors above"; fail=1; fi
  [ $c -eq 0 ] && [ $h -eq 0 ] || fail=1
  P=$((P + 1))
done
echo "== auto-update: a build-5 copy finds, downloads, checks and runs build 6 from a local server"
GODOT="$G" timeout -k 10 600 tests/update_check.sh 2>&1 | grep -E "\[update\] (ok|FAIL|UPDATER)" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
[ -s "$T/timeouts.log" ] && { cat "$T/timeouts.log"; fail=1; }
[ $fail -eq 0 ] && echo "ALL TESTS PASSED" || { echo "TESTS FAILED"; exit 1; }
