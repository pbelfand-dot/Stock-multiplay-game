# Car asset source packages

This directory stores the owner's SHOTGUN RALLY source assets. The GitHub repository was
changed to **PRIVATE** on 2026-10-11 before the unlicensed user-download batch was added.
Do not make it public again until every package has been audited for redistribution rights
and any disallowed sources have been removed from the complete Git history.

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

Treat the full collection as private-use source material. Some third-party packages may
prohibit redistribution; audit or remove those packages and their Git history before ever
treating the repository as a public asset library.

`Track_Mode_Cars/` contains separately attributed non-commercial/share-alike GT candidates,
public-repo-safe CC0 Formula and generic GT race-car candidates, and a private user-download
batch sorted into `Formula/`, `GT3/`, and `Street/`. See its README and
`USER_CAR_BATCH_MANIFEST.tsv` before using or redistributing that batch.
`../wheel_packages/` contains the wheel/tyre source library and its own license manifest.
