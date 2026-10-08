# Environment asset packages

This directory contains a curated source library for SHOTGUN RALLY's highway, touge, rally, and traffic environments.

## Ready-to-use CC0 assets

The `cc0/` directory contains assets that may be used, modified, and processed by automated tools:

- Poly Haven `rock_moss_set_01` at 2K: six mossy rocks for forest and mountain dressing.
- Poly Haven `rock_face_01` at 2K: a realistic cliff/rock-face module.
- Poly Haven `forrest_ground_01` at 2K: forest-floor PBR material.
- Poly Haven `asphalt_02` at 2K: asphalt PBR material for roads and shoulders.
- Kenney City Kit (Roads): modular road, sign, and traffic-light pieces for layout and collision foundations.

See `CC0_SOURCES.md` for source URLs and license details.

## Packaged user-provided sources

The `user_sources/` directory contains the strongest portable assets found in the recent downloads:

- 12-model conifer vegetation collection with FBX meshes and PBR maps.
- Robinia pseudoacacia broadleaf tree in FBX format.
- Tall-pine Blender model with diffuse and normal maps.
- 22-building city set with Blend, FBX, OBJ, GLB, and texture variants.
- 31 separate background-building models in FBX, OBJ, and 3ds Max formats.
- Highway prop collection containing roads, barriers, pylons, and signs.

Large source archives are stored as ordered 90,000,000-byte chunks solely to remain below GitHub's normal single-file limit. There is no 30 MB runtime-asset limit.

Restore and verify these sources from the repository root:

```sh
shotgun-rally/tools/restore_environment_assets.sh
```

To restore somewhere else:

```sh
shotgun-rally/tools/restore_environment_assets.sh /absolute/output/path
```

The manifest records each source's original size, SHA-256 checksum, storage location, and license-review status.

## License boundary

The user-provided archive licenses were not included in their downloads. Treat them as `license-review-required`: keep the repository private, locate and preserve the relevant marketplace license before redistribution, and do not feed any asset marked `no AI` into an AI system. The CC0 assets can be used immediately.
