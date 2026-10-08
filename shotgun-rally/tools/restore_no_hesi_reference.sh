#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
parts_dir="$project_dir/docs/reference/no_hesi_realistic_physics.mp4.parts"
output_path="${1:-$project_dir/docs/reference/no_hesi_realistic_physics.mp4}"
expected_sha="1a8211c5e9287525baaa37ec53a913cbf360f7d793931634413ef5ea48f2e057"
temp_path="$output_path.tmp.$$"

if [ -e "$output_path" ]; then
  echo "Refusing to overwrite existing file: $output_path" >&2
  exit 1
fi

cleanup() {
  rm -f -- "$temp_path"
}
trap cleanup EXIT HUP INT TERM

cat "$parts_dir"/no_hesi_realistic_physics.mp4.part-* > "$temp_path"
actual_sha=$(shasum -a 256 "$temp_path" | awk '{print $1}')

if [ "$actual_sha" != "$expected_sha" ]; then
  echo "Checksum mismatch: expected $expected_sha, got $actual_sha" >&2
  exit 1
fi

mv -- "$temp_path" "$output_path"
trap - EXIT HUP INT TERM
echo "Restored: $output_path"
