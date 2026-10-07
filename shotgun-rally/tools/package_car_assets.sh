#!/bin/zsh
set -euo pipefail

if (( $# != 2 )); then
  echo "Usage: $0 SOURCE_CARS_DIRECTORY DESTINATION_PACKAGE_DIRECTORY" >&2
  exit 2
fi

source_dir=${1:A}
destination_dir=${2:A}
max_direct_bytes=30000000
chunk_bytes=25000000

if [[ ! -d "$source_dir" ]]; then
  echo "Source directory does not exist: $source_dir" >&2
  exit 2
fi

if [[ -e "$destination_dir/CAR_ASSET_MANIFEST.tsv" ]]; then
  echo "Package manifest already exists; refusing to overwrite it: $destination_dir" >&2
  exit 2
fi

mkdir -p "$destination_dir"
manifest="$destination_dir/CAR_ASSET_MANIFEST.tsv"
printf 'mode\toriginal_path\tsize_bytes\tsha256\tstorage_path\n' > "$manifest"

while IFS= read -r -d '' source_file; do
  relative_path=${source_file#"$source_dir"/}
  [[ "$relative_path" == ".DS_Store" ]] && continue

  size_bytes=$(stat -f '%z' "$source_file")
  checksum=$(shasum -a 256 "$source_file" | awk '{print $1}')

  if (( size_bytes < max_direct_bytes )); then
    stored_file="$destination_dir/$relative_path"
    mkdir -p "${stored_file:h}"
    cp -p "$source_file" "$stored_file"
    printf 'direct\t%s\t%s\t%s\t%s\n' \
      "$relative_path" "$size_bytes" "$checksum" "$relative_path" >> "$manifest"
  else
    part_directory="$destination_dir/$relative_path.parts"
    part_prefix="${source_file:t}.part-"
    mkdir -p "$part_directory"
    split -a 3 -b "$chunk_bytes" "$source_file" "$part_directory/$part_prefix"
    storage_prefix="$relative_path.parts/$part_prefix"
    printf 'split\t%s\t%s\t%s\t%s\n' \
      "$relative_path" "$size_bytes" "$checksum" "$storage_prefix" >> "$manifest"
  fi
done < <(find "$source_dir" -type f -print0 | sort -z)

echo "Packaged car assets in: $destination_dir"
echo "Manifest: $manifest"
