#!/usr/bin/env bash
# Runs every headless test. Usage: GODOT=/path/to/godot tests/run_all.sh
set -u
G="${GODOT:-godot}"
cd "$(dirname "$0")/.."
fail=0
echo "== compile check";  "$G" --headless --path . -s tests/check_scripts.gd 2>&1 | grep -E "checked|FAIL|SCRIPT ERROR" || true
"$G" --headless --path . -s tests/check_scripts.gd >/dev/null 2>&1 || fail=1
echo "== sim unit tests"; "$G" --headless --path . -s tests/test_sim.gd 2>&1 | grep -E "sim tests|FAIL" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== terminal clicks (BUY/SELL/auto-sell)"
"$G" --headless --path . -- --host --autostart --clicktest --port=7790 2>&1 | grep -E "\[click\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== save -> continue"
"$G" --headless --path . -- --savecheck=1 --host --autostart --day_seconds=3 --name=Trader --port=7791 2>&1 | grep -E "\[save\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
"$G" --headless --path . -- --savecheck=3 --host --name=Bob --port=7791 2>&1 | grep -E "\[save\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
"$G" --headless --path . -- --savecheck=2 --host --name=Trader --port=7791 2>&1 | grep -E "\[save\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== hair motion (spring bones swing and settle)"
"$G" --headless --path . -- --lineup=/tmp/bh_hair --hairmotion 2>&1 | grep -E "hairmotion:" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== day events, contracts, upgrades, milestones"
"$G" --headless --path . -- --eventcheck --host --autostart --day_seconds=150 --day_event=flash_crash --name=Trader --port=7792 2>&1 | grep -E "\[events\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
"$G" --headless --path . -- --eventcheck --pvp --host --autostart --day_seconds=4 --day_event=none --name=Trader --port=7793 2>&1 | grep -E "\[events\]" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
for mode in coop pvp; do
  echo "== multiplayer smoke ($mode)"
  extra=""; [ "$mode" = pvp ] && extra="--pvp"
  "$G" --headless --path . -- --host --autostart --smoke=host --port=7788 $extra > /tmp/bh_host.log 2>&1 &
  hp=$!
  sleep 3
  "$G" --headless --path . -- --join=127.0.0.1 --port=7788 --name=Bob --smoke=client > /tmp/bh_client.log 2>&1; c=$?
  wait $hp; h=$?
  grep -h "smoke:" /tmp/bh_host.log /tmp/bh_client.log
  if grep -hE "^(ERROR|SCRIPT ERROR)" /tmp/bh_host.log /tmp/bh_client.log; then echo "!! engine errors above"; fail=1; fi
  [ $c -eq 0 ] && [ $h -eq 0 ] || fail=1
done
[ $fail -eq 0 ] && echo "ALL TESTS PASSED" || { echo "TESTS FAILED"; exit 1; }
