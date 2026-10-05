#!/usr/bin/env bash
# Runs every headless test. Usage: GODOT=/path/to/godot tests/run_all.sh
set -u
G="${GODOT:-godot}"
cd "$(dirname "$0")/.."
fail=0
# a private port per run, so parallel runs (other checkouts) never cross wires
P=${SR_PORT:-$((20000 + RANDOM % 30000))}
T=$(mktemp -d)
echo "== compile check"
"$G" --headless --path . -s tests/check_scripts.gd 2>&1 | grep -E "checked|COMPILE FAIL" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== stages: 20 seeds, deterministic, no crossings, every corner has a note"
"$G" --headless --path . -s tests/stage_check.gd 2>&1 | grep -E "\[stage\] (FAIL|STAGES|words)" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== car + stage: the autopilot drives whole stages, 0-100, braking, handbrake flick"
for seed in 3 7 15; do
  "$G" --headless --fixed-fps 60 --path . -s tests/drive_check.gd -- --seed=$seed 2>&1 | grep -E "\[drive\] (FAIL|DRIVE|ok   finished)" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
done
echo "== AI co-driver: every call said in time"
"$G" --headless --fixed-fps 60 --path . -- --aicheck --autostart --autopilot --seed=8 --timeout=400 2>&1 | grep -E "\[ai\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
for case in "driver codriver" "codriver driver"; do
  set -- $case
  echo "== 2 players: host $1, guest $2 (the driver's machine streams the car)"
  hp_ap=""; cl_ap=""
  [ "$1" = driver ] && hp_ap="--autopilot" || cl_ap="--autopilot"
  "$G" --headless --path . -- --host --seat=$1 --autostart $hp_ap --smoke=host --port=$P --seed=5 --length=900 --timeout=180 > $T/host.log 2>&1 &
  hp=$!
  sleep 3
  "$G" --headless --path . -- --join=127.0.0.1 --port=$P --name=Bob $cl_ap --smoke=client --length=900 --timeout=180 > $T/client.log 2>&1; c=$?
  wait $hp; h=$?
  grep -h "\[smoke\]" $T/host.log $T/client.log
  if grep -hE -A2 "^(SCRIPT ERROR|ERROR: Node not found)" $T/host.log $T/client.log; then echo "!! engine errors above"; fail=1; fi
  [ $c -eq 0 ] && [ $h -eq 0 ] || fail=1
  P=$((P + 1))
done
[ $fail -eq 0 ] && echo "ALL TESTS PASSED" || { echo "TESTS FAILED"; exit 1; }
