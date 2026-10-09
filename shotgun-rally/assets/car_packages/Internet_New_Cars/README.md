# Internet car candidates — 2026-10-08

These are the original free download packages. They are intentionally not converted or integrated yet. Every retained model has usable cabin geometry; exterior-only models were rejected.

| Car | Source | Creator | License | Original | Interior evidence |
|---|---|---|---|---|---|
| BMW 320i xDrive (G20) 2023 | https://sketchfab.com/3d-models/2023-bmw-3-series-82534fdddd7e46e4bdb202d6c1d3c0e7 | solid3DDD | CC BY 4.0 | Original Blender ZIP plus 2K GLB, 2.7M triangles | The listing explicitly tags an interior; the source archive includes `interior_imagini_3s.png`, and the creator says lower-poly detached components are included for editing. Preserve the full-detail source for garage views, but build optimized driving LODs before runtime use. |
| Volkswagen ID.4 2021 | https://sketchfab.com/3d-models/volkswagen-id4-2021-502c1a0c911b4dfbaae57a7b25ec890f | ItsDiyor | CC BY 4.0 | GLB, 224.9k triangles | Seats/cabin visible in the live viewer; high-detail opaque/transparent meshes and interior texture atlas retained. |
| Jeep Grand Cherokee Trackhawk | https://sketchfab.com/3d-models/jeep-grand-cherokee-trackhawk-f8024595e11c48119877c9c7cc554abc | David_Holiday | CC BY 4.0 | OBJ, 363.1k triangles | Dedicated `InteriorA`, `InteriorTillingA`, speedometer, GPS, and engine textures; interior material groups in OBJ. |
| Dodge Durango SRT 392 | https://sketchfab.com/3d-models/dodge-durango-srt-392-ff66f958267b479ebe8fd0780277bcba | fvrenbld | CC BY 4.0 | OBJ, 256.2k triangles | Cabin mesh includes steering-wheel and door-seal groups; retain the opaque dark cabin rather than deleting it during conversion. |
| BMW X5 M 2016 | https://sketchfab.com/3d-models/2016-bmw-x5-m-349f567cc7614acabd91a297a8e4dc75 | Ddiaz Design | CC BY-NC-SA 4.0 | FBX, 44.8k triangles | Explicit `M_Internal_Interior_High` mesh plus diffuse, normal, and material textures for the interior. Personal/private use only. |
| BMW X7 2020 | https://sketchfab.com/3d-models/bmw-x7-2020-3524d3cfb92443f596be10e5fde78677 | ItsDiyor | CC BY 4.0 | GLB, 199.5k triangles | Seats and cabin are visible through the windows in the live viewer; preserve all interior geometry. |
| Mercedes-Benz G-Class AMG G63 2020 | https://sketchfab.com/3d-models/2020-mercedes-benz-g-class-amg-g63-52296f1a65d54a85a2ed7cb67604e554 | Outlaw Games | CC BY-NC 4.0 | GLB, 230.3k triangles | Front and rear seats, headrests, cabin trim, and dashboard are visible in the live viewer. Personal/private use only. |

Rejected during this pass:

- Audi RS Q8 2020 from CGTrader: the listing explicitly says it has no interior.
- The requested Cream Drift S13 from CGTrader: not downloaded because the Premium monthly allowance is exhausted and its page asks for payment; the repository already contains a different S13/240SX package.

Attribution is required for every retained Sketchfab model. Keep this file with the packages and carry its credits into any in-game credits screen.

## BMW 320i xDrive files

- `2023-bmw-320i-xdrive-source.zip` is the untouched original download. It contains the Blender scene and the creator's logo, interior, and tyre textures.
- `2023-bmw-320i-xdrive-2k.glb` is Sketchfab's 2K-textured GLB conversion for inspection and import.
- Credit line: **“2023 bmw 3 series” by solid3DDD, licensed under CC BY 4.0.**
- The car is a base-model 2023 BMW 320i xDrive, not a 540i or M3. Label and tune it accordingly.
- The high-detail GLB is about 80.5 MB and 2.7M triangles. It is suitable as a preserved source and possibly a garage LOD, but not as the unoptimized racing mesh.
