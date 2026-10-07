#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
package_dir="${script_dir:h}/assets/car_packages"
output_dir=${1:-"${script_dir:h}/assets/cars_restored"}
output_dir=${output_dir:A}
manifest="$package_dir/CAR_ASSET_MANIFEST.tsv"

if [[ ! -f "$manifest" ]]; then
  echo "Manifest not found: $manifest" >&2
  exit 2
fi

mkdir -p "$output_dir"

tail -n +2 "$manifest" | while IFS=$'\t' read -r mode original_path size_bytes checksum storage_path; do
  destination="$output_dir/$original_path"
  mkdir -p "${destination:h}"

  if [[ "$mode" == "direct" ]]; then
    cp -p "$package_dir/$storage_path" "$destination"
  elif [[ "$mode" == "split" ]]; then
    part_files=("$package_dir/$storage_path"*(N))
    if (( ${#part_files} == 0 )); then
      echo "No parts found for: $original_path" >&2
      exit 1
    fi
    cat "${part_files[@]}" > "$destination"
  else
    echo "Unknown storage mode '$mode' for $original_path" >&2
    exit 1
  fi

  restored_size=$(stat -f '%z' "$destination")
  restored_checksum=$(shasum -a 256 "$destination" | awk '{print $1}')
  if [[ "$restored_size" != "$size_bytes" || "$restored_checksum" != "$checksum" ]]; then
    echo "Verification failed for: $original_path" >&2
    exit 1
  fi
  echo "Restored: $original_path"
done

echo "All car assets restored and verified in: $output_dir"

