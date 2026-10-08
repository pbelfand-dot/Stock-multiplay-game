#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
parts_dir="$project_dir/docs/reference/racing_games_biggest_issue.mp4.parts"
output_path="${1:-$project_dir/docs/reference/racing_games_biggest_issue.mp4}"
expected_sha="7867ec5b90856956d5525f579736428af2819665edf9c3b27b03d0f015ba225c"
temp_path="$output_path.tmp.$$"

if [ -e "$output_path" ]; then
  echo "Refusing to overwrite existing file: $output_path" >&2
  exit 1
fi

cleanup() {
  rm -f -- "$temp_path"
}
trap cleanup EXIT HUP INT TERM

cat "$parts_dir"/racing_games_biggest_issue.mp4.part-* > "$temp_path"
actual_sha=$(shasum -a 256 "$temp_path" | awk '{print $1}')

if [ "$actual_sha" != "$expected_sha" ]; then
  echo "Checksum mismatch: expected $expected_sha, got $actual_sha" >&2
  exit 1
fi

mv -- "$temp_path" "$output_path"
trap - EXIT HUP INT TERM
echo "Restored: $output_path"
