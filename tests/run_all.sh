#!/usr/bin/env bash
# Runs every headless test. Usage: GODOT=/path/to/godot tests/run_all.sh
set -u
G="${GODOT:-godot}"
cd "$(dirname "$0")/.."
fail=0
# a private port range + log dir per run, so parallel runs (other checkouts) never cross wires
P=${BH_PORT:-$((20000 + RANDOM % 30000))}
T=$(mktemp -d)
echo "== compile check";  "$G" --headless --path . -s tests/check_scripts.gd 2>&1 | grep -E "checked|FAIL|SCRIPT ERROR" || true
"$G" --headless --path . -s tests/check_scripts.gd >/dev/null 2>&1 || fail=1
echo "== sim unit tests"; "$G" --headless --path . -s tests/test_sim.gd 2>&1 | grep -E "sim tests|FAIL" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== terminal clicks (BUY/SELL/auto-sell)"
"$G" --headless --path . -- --host --autostart --clicktest --port=$((P+0)) 2>&1 | grep -E "\[click\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== save -> continue"
"$G" --headless --path . -- --savecheck=1 --host --autostart --day_seconds=3 --name=Trader --port=$((P+1)) 2>&1 | grep -E "\[save\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
"$G" --headless --path . -- --savecheck=3 --host --commute=0 --name=Bob --port=$((P+1)) 2>&1 | grep -E "\[save\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
"$G" --headless --path . -- --savecheck=2 --host --commute=0 --name=Trader --port=$((P+1)) 2>&1 | grep -E "\[save\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== hair motion (spring bones swing and settle)"
"$G" --headless --path . -- --lineup=$T/hair --hairmotion 2>&1 | grep -E "hairmotion:" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== car handling (0-60, top speed, brakes, grip, crashes slow you down, scrapes don't)"
for car in bz_m3 beater; do
  "$G" --headless --path . -- --drivecheck --car=$car 2>&1 | grep -E "\[drive\] (FAIL|DRIVE)" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
done
echo "== day events, contracts, upgrades, milestones"
"$G" --headless --path . -- --eventcheck --host --autostart --day_seconds=150 --day_event=flash_crash --name=Trader --port=$((P+2)) 2>&1 | grep -E "\[events\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
"$G" --headless --path . -- --eventcheck --pvp --host --autostart --day_seconds=4 --day_event=none --name=Trader --port=$((P+3)) 2>&1 | grep -E "\[events\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== commute: wake up at home, drive the highway in, overslept + late"
"$G" --headless --path . -- --commutecheck --host --autostart --commute=120 --name=Trader --port=$((P+6)) 2>&1 | grep -E "\[commute\] (COMMUTE|the AI)" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== cabs: the taxi drives you there (hood -> BEMZE -> downtown -> home, get out early, skip)"
"$G" --headless --path . -- --cabcheck --host --autostart --commute=0 --port=$((P+7)) 2>&1 | grep -E "\[cab\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== neighborhood: build, buy a house, taxis, traffic (IDM/MOBIL), dealership lot"
"$G" --headless --path . -- --host --autostart --hoodcheck --port=$((P+5)) 2>&1 | grep -E "\[hood\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
for mode in coop pvp; do
  echo "== multiplayer smoke ($mode)"
  extra=""; [ "$mode" = pvp ] && extra="--pvp"
  "$G" --headless --path . -- --host --autostart --smoke=host --port=$((P+4)) $extra > $T/host.log 2>&1 &
  hp=$!
  sleep 3
  "$G" --headless --path . -- --join=127.0.0.1 --port=$((P+4)) --name=Bob --smoke=client > $T/client.log 2>&1; c=$?
  wait $hp; h=$?
  grep -h "smoke:" $T/host.log $T/client.log
  if grep -hE -A2 "^(ERROR|SCRIPT ERROR)" $T/host.log $T/client.log; then echo "!! engine errors above"; fail=1; fi
  [ $c -eq 0 ] && [ $h -eq 0 ] || fail=1
done
[ $fail -eq 0 ] && echo "ALL TESTS PASSED" || { echo "TESTS FAILED"; exit 1; }
