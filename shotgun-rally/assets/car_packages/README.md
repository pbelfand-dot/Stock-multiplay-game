# Car asset source packages

This directory stores the owner's SHOTGUN RALLY source assets. GitHub reported this
repository as **PUBLIC** on 2026-10-09, so only redistributable packages should be added
while that remains true. Make the repository private before adding restricted source files.

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

Treat the full collection as private-use source material. Some older third-party packages may
prohibit redistribution even though the repository is currently public; audit or remove those
packages before treating the repository as a public asset library.

`Track_Mode_Cars/` contains separately attributed non-commercial/share-alike GT candidates
plus public-repo-safe CC0 Formula and generic GT race-car candidates in subdirectories.
`../wheel_packages/` contains the wheel/tyre source library and its own license manifest.
