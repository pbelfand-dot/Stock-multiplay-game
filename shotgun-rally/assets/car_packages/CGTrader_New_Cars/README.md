# Car Asset Pack

This folder contains the requested high-detail race cars plus a small everyday-traffic set. Each vehicle is isolated in its own folder so imports and texture relinking stay manageable.

## Newly added favorite

- `dodge_challenger_srt_hellcat_widebody_2022/gltf.zip` — best first choice for web and portable workflows
- `dodge_challenger_srt_hellcat_widebody_2022/fbx.zip` — best first choice for Unity, Unreal, Godot, or Blender
- `dodge_challenger_srt_hellcat_widebody_2022/textures.zip`
- Source: https://www.cgtrader.com/3d-models/car/sport-car/dodge-challenger-srt-hellcat-widebody-2022

## Everyday traffic

- `traffic/generic_sedan/` — rigged, low-poly FBX with PBR textures
- `traffic/generic_crossover/` — rigged, low-poly FBX with PBR textures
- `traffic/generic_minivan/` — rigged, low-poly FBX with PBR textures
- `traffic/mercedes_gls_63_amg/` — higher-detail GLB SUV with textures

Sources:

- https://www.cgtrader.com/3d-models/car/car/sedan-car-dc697a25-b91b-458f-972a-b9f695fbd5f3
- https://www.cgtrader.com/3d-models/car/suv/crossover-car
- https://www.cgtrader.com/3d-models/car/car/minivan-car
- https://www.cgtrader.com/3d-models/car/suv/mercedes-benz-gls-63-amg-1c516e66-3d66-42f8-8494-b380cd886d5e

## Import guidance

1. Keep each model and its texture archive together.
2. For the Hellcat, try the GLTF package first; use FBX when your engine needs separate wheel objects or a custom vehicle rig.
3. For traffic, instance the same mesh with several paint materials instead of duplicating geometry.
4. Use LODs and simpler collision meshes on traffic vehicles so dense streets remain performant.
5. Preserve the untouched originals. Make engine-specific copies before renaming bones, applying transforms, or merging meshes.

## License caution

The generic sedan, crossover, and minivan pages displayed **Royalty Free License (no AI)**. Do not upload those source assets to Claude or another AI service unless the license terms explicitly permit your intended use. You can safely give Claude the included text manifest and ask it to write import/configuration code that references the local paths without inspecting the model contents. Check the individual CGTrader license for every other model before uploading its source files to an AI service.

