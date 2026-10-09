# Wheel and tyre source packages

Free source assets for replacement wheels, tyre variants, racing prototypes, and
wheel-fitment tests. These files are source material only; they are not wired into the
vehicle registry yet.

## Included packages

| Package | What is included | Format | License | Source |
|---|---|---|---|---|
| `Free_Wheels/USD_Mini_Car_Kit/` | Six interchangeable wheel variants (`Black`, `LargeRim`, `Normal`, `Red`, `Vintage`, `Wide`) plus a small Formula car and other vehicle examples | USD / USDA | CC0 | [Academy Software Foundation USD Working Group assets](https://github.com/usd-wg/assets/tree/main/full_assets/Vehicles/USD_Mini_Car_Kit), source commit `3b75c2dad6a494897557dcca0098257bcf42a8c6` |
| `Free_Wheels/ice-maan-cc96-four-rim-pack.zip` | Four left/right FBX rim designs, three body kits, and a spoiler | FBX in ZIP | CC0; license text is inside the archive | [IceMaan on itch.io](https://icemaan.itch.io/free-low-poly-car3-3-body-kits-4-rims) |
| `Free_Wheels/innerscene-17in-five-spoke-wheel-tyre.x3d` | Real-scale 225/45 R17 five-spoke rim, tyre, brake disc, and caliper assembly | X3D | CC0 | [Innerscene Parts Library](https://www.innerscene.com/tools/library/3d-parts/17-inch-five-spoke-alloy-wheel-and-tyre-x3d-50c20c60) |

The USD and CC96 assets are low-poly prototypes and useful LODs. The Innerscene asset is
the most dimensionally useful included source. Do not silently replace a detailed hero
car's original wheel with a prototype: preserve the stock wheel and offer replacements as
garage options after checking fitment.

## Repeated makes and initial presets

These are visual starting points, not claims that the generic wheels are factory OEM
designs. Keep fictional in-game names and do not add real logos to generic rims.

| Make represented by multiple cars | Initial included presets | High-detail candidate to download after Sketchfab login |
|---|---|---|
| BMW | `LargeRim`, `Black`, CC96 rim 3 | [BMW Wheel by 3DChecker Studio — CC BY 4.0, 206k triangles](https://sketchfab.com/3d-models/bmw-wheel-4fb80177b54549d4adea93c389a3e649) |
| Nissan | `Wide`, `Red`, CC96 rims 1/2 | [Apex ARC-8 — CC BY 4.0, 408.8k triangles](https://sketchfab.com/3d-models/apex-arc-8-wheel-free-model-6d88cf85bbf740dbbe2c6f0f04d7e084) |
| Porsche | `LargeRim`, `Black`, CC96 rim 4 | [911 GT3 RS rim — CC BY 4.0, 6k triangles](https://sketchfab.com/3d-models/porsche-911-gt3rs-rim-9f5ece33b2554a3687935305c7afd7da) |
| Mercedes-Benz | `Normal`, `Black`, CC96 rim 4 | [AMG Monoblock Aero 2 — CC BY 4.0, 355.4k triangles](https://sketchfab.com/3d-models/mercedes-benz-wheel-amg-monoblock-aero-2-cfdf7e25c5a94f36a213ab524abcb1e7) |
| Dodge | `Wide`, `LargeRim`, Innerscene five-spoke | [Magnesium racing wheel — CC BY 4.0, 446k triangles](https://sketchfab.com/3d-models/free-wheels-magnesium-rims-sdc-bcb587252fb2449aa5862dafdc06b294) |
| Audi | `Black`, `LargeRim`, CC96 rim 3 | [Audi R8 wheel and tyre — CC BY 4.0, 775.3k triangles](https://sketchfab.com/3d-models/wheel-and-tire-3d-model-audi-r8-wheel-b2e5049f151f40ac9e484b03c395cec4) |
| Honda | `Normal`, Innerscene five-spoke, CC96 rim 1 | [Spoon SW388 low/high poly — CC BY 4.0, 35.4k triangles](https://sketchfab.com/3d-models/spoon-sw388-lowhigh-poly-069b86d4b4a2492e92eb3349805479f9) |
| Mazda | `Wide`, `Red`, CC96 rim 2 | [Turbofan / wide-stance wheel — CC BY 4.0, 621.5k triangles](https://sketchfab.com/3d-models/turbofan-super-wide-stance-wheel-free-model-da5a98a0fedf4057a44a70919cbcf148) |
| Toyota | `Wide`, `Red`, CC96 rims 1/2 | [Apex ARC-8 — CC BY 4.0, 408.8k triangles](https://sketchfab.com/3d-models/apex-arc-8-wheel-free-model-6d88cf85bbf740dbbe2c6f0f04d7e084) |
| Bugatti | `LargeRim`, `Black`, CC96 rim 4 | [Bugatti wheel — CC BY 4.0, 336.1k triangles](https://sketchfab.com/3d-models/bugatti-wheel-mustafa-stra-vfx-1057a478119847728c11ecac323cd993) |

Formula candidate: [Best F1 Tire by MemesaMillion — CC BY 4.0, 125k
triangles](https://sketchfab.com/3d-models/best-f1-tire-9d6d4f69a6c8475ab47dc8a6bf8deeaf).
Sketchfab showed a login requirement in the ChatGPT browser, so these high-detail branded
candidates are documented but not falsely marked as downloaded.

## Integration rules

- Keep rim, tyre, brake disc, and caliper separate. Wheels rotate; calipers do not.
- Put the wheel pivot at the axle center and align the local axle consistently.
- Scale from measured tyre diameter, not by eye. Store front and rear width, diameter,
  offset, and radius independently.
- Mirror geometry only when it is safe; directional tyre tread needs distinct left/right
  meshes or corrected UVs.
- Generate at least garage, race, and distance LODs. The physics wheel radius must not
  change with the visual LOD.
- Preserve every source URL, author, and license in the game's credits.

