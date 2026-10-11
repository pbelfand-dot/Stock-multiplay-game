# Track-mode source cars

Unmodified local downloads staged for the proposed GT/F1 track mode. They are source
packages, not registered or playable vehicles yet.

| Package | Contents checked | Source / attribution | License | Status |
|---|---|---|---|---|
| `2024-porsche-992-gt3-r.zip` | Valid GLB 2.0; 489,304 indexed triangles; 151 meshes; separate LF/LR/RF/RR rims, tyres, calipers, high-detail cockpit, steering wheel, seat, dash, and race-display objects | [2024 Porsche 992 GT3 R](https://sketchfab.com/3d-models/2024-porsche-992-gt3-r-6b690bc63c8040c791d25a060ab20e1b) by VTX; listing credits Dave Love / Tyler_Dave | CC BY-NC-SA 4.0 | Alternate, lighter source for the existing Porsche GT3 R; compare before integrating |
| `mercedes-amg-gt3-red-bull-racing.zip` | Valid GLB 2.0; 496,613 indexed triangles; 57 meshes; separate cockpit screen, console, carbon chassis, pedals, seat, steering wheel, rim, tyre, and caliper materials | [Mercedes-AMG GT3 Red Bull Racing](https://sketchfab.com/3d-models/mercedes-amg-gt3-red-bull-racing-035f061cb6624effbc483d5f9b5ecaba) by VTX; listing credits toddeppe | CC BY-NC-SA 4.0 | New pending GT3 candidate; remove real sponsor marks for a public game build |

Both packages are non-commercial and share-alike. Keep this README with the files, retain
the attribution, and treat any real brand or sponsor artwork as identification/reference,
not as an endorsement.

## Public-repo-safe CC0 additions

The `Formula/` and `GT3/` subdirectories contain original, generic, game-ready GLBs from
3DAssets.dev. They are CC0 1.0 Universal, use fictional/unbranded designs, and are suitable
for the public repository. They were generated with AI tools by their upstream contributor;
none carries a `No AI` restriction.

- `Formula/` contains two modern halo/open-wheel candidates with named wheel pivots and a
  `wheel-roll` clip.
- `GT3/` contains four visually distinct closed-cockpit race-car candidates for building a
  varied AI grid. They are generic GT/GT4/cup designs, not replicas of branded manufacturers.
- `../../TRACK_MODE_ASSET_MANIFEST.tsv` records sources, sizes, hashes, geometry counts,
  animations, licensing, and AI provenance for every new GLB.

The upstream JSON responses are preserved beside the cars. These GLBs are source candidates,
not proof that a vehicle is registered, physically tuned, or selectable in the game.
