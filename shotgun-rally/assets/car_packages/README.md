# Private car asset packages

This directory stores the owner's car assets for the private SHOTGUN RALLY repository.

- There is no project-level 30 MB asset limit.
- Originals below GitHub's 100 MB single-file limit are stored directly.
- Larger originals are stored as ordered 25,000,000-byte parts in a matching `.parts` directory.
- `CAR_ASSET_MANIFEST.tsv` records each original path, byte size, SHA-256 checksum, and storage location.

Restore and verify the complete source collection from the repository root:

```sh
shotgun-rally/tools/restore_car_assets.sh
```

To restore somewhere else:

```sh
shotgun-rally/tools/restore_car_assets.sh /absolute/output/path
```

Keep this repository private. The collection includes third-party assets whose licenses may prohibit redistribution of raw source files.
