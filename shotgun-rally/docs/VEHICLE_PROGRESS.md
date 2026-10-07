# Vehicle integration progress

The working inventory of the owner's 43 car candidates (`assets/car_packages/`, restored with
`tools/restore_car_assets.py`), kept up to date as each car is done. Updated 2026-10-07.

Statuses: **in game** = converted, in the registry and tested; **pending** = not yet integrated;
**blocked** = see Blockers. Game names are fictional (the game shows no real brands); the real
car is in each registry entry (`data/vehicles/<id>.json`).

| # | Vehicle | Game model id | Source | Formats | Textures | Interior | Wheels | Quality | Duplicates | Licence / attribution | Best source | Role | Import status | Known problems |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1970 Nissan Skyline 2000GT-R (C10), tuned | skyline_c10 | 1970-nissan-skyline-high-poly-interior.zip (79 MB) | Collada .dae (Blender here can't read it: converted to GLB with assimp) | 68 JPEG/PNG in textures/ (not embedded) | full: dash, seats, rear seat, interior parts, steering wheel | all four in one mesh ("Wheels"): split by geometry | high (772k tris) | - | Sketchfab download (see licence notes) | the .dae via assimp | touge grip | pending | tuned car (NOS bottles, coilovers modelled) |
| 2 | 1992 Honda Civic SiR-II EG | civic_eg | 1992-honda-civic-sir-ii-eg.zip | .blend (in a .rar) | 17 PNG | the model's (kept) | separate | good | - | Sketchfab download | the .blend | touge grip (FWD) | in game (NIMBUS EG) before this project |  |
| 3 | 1998 Subaru Impreza 22B STI | impreza_22b | 1998-subaru-impreza-22b-sti.zip | GLB (vecarz) | 21 embedded, 1024 px | to check (generic names; "int1" material) | "wheel"/"tire"/"rotor" materials | medium (80k tris) | - | Sketchfab download (vecarz) | the GLB | touge grip / rally road car | pending |  |
| 4 | 2017 Nissan GT-R R35, AimGain Type 2 kit | gtr_r35 | 2017-nissan-aimgain-gt-r-r35-type-2.zip | GLB | 32 embedded, 1024 px | "InteriorA" materials: likely | "Wheel1A" material | high (549k) | - | Sketchfab download | the GLB | touge grip / player road | pending | Part/material names follow Forza Horizon's asset naming ("RewardRecycled", "TNR", "Geo_lodA"): likely extracted from that game. Fine in this private repo among friends; replace before any public release. |
| 5 | Mitsubishi Lancer Evolution IX (2005) | evo9 | CGTrader mitsubishi_lancer_evo_2005.fbx + textures.rar | FBX | 68 in textures.rar (not embedded) | few interior names: to check | 13 wheel-like parts | high (708k) | - | CGTrader purchase (licence: see notes) | the FBX + textures | touge grip (AWD) | pending |  |
| 6 | Nissan 240SX S13 (Rocket Bunny kit) | s13 | CGTrader nissan_240sx_s13.fbx | FBX | none (11 plain materials) | "S13 240SX Interior" part | separate (Forgestar wheels, Brembo brakes) | very high (1.7M) | - | CGTrader purchase | the FBX | drift | pending | no textures: colours from its materials |
| 7 | Nissan Silvia S15 / 200SX | s15 | nissan-silvia-s15-india-spec-200sx.zip | OBJ (in a zip) | 35 PNG | the model's (kept) | separate | good | - | Sketchfab download | the OBJ | drift | in game (SYLPH S15) before this project |  |
| 8 | Mazda RX-7 FC | rx7_fc | mazda-rx-7-fc.zip | .blend | 4 PNG | too rough: the game's rally cockpit | separate | low-medium | - | Sketchfab download | the .blend | drift | in game (ROTORA FC) before this project | interior unusable |
| 9 | Mazda RX-7 FD | rx7_fd | mazda-rx-7-fd.zip | .blend | 5 PNG | too rough: the game's rally cockpit | separate | low-medium | - | Sketchfab download | the .blend | touge grip | in game (ROTORA FD) before this project | interior unusable |
| 10 | Toyota AE86 Sprinter Trueno Zenki | ae86 | toyota-ae86-sprinter-trueno-zenki.zip | FBX | 39 JPEG/PNG | full (kept) | separate | high | - | Sketchfab download | the FBX | drift | in game (HACHI 86) before this project |  |
| 11 | Toyota Supra Mk5 A90 | supra_a90 | toyota-supra-mk5-a90.zip | OBJ (in a zip) | to check (in the zip) | a few interior parts | 10 wheel-like parts | high (857k) | - | Sketchfab download | the OBJ | touge grip / player road | pending |  |
| 12 | 1984 Audi Sport Quattro | sport_quattro | 1984-audi-sport-quattro.zip | FBX (in a zip) | 20 | the model's (kept) | separate | good | - | Sketchfab download | the FBX | rally | in game (VIERRAD S1) before this project |  |
| 13 | 2020 Audi RS6 Avant (C8) | rs6_c8 | 2020-audi-rs6-avant (1).zip | FBX (in a zip) | 52 embedded, 512 px | "Kit1_Interior" part | "Wheel1A" parts | medium (233k) | - | Sketchfab download | the FBX | player road / premium traffic | pending | Part/material names follow Forza Horizon's asset naming ("RewardRecycled", "TNR", "Geo_lodA"): likely extracted from that game. Fine in this private repo among friends; replace before any public release. |
| 14 | 2021 Ford Puma Rally1 | puma_rally1 | 2021-ford-puma-rally1.zip | FBX | 10 | full rally (kept) | separate | high | - | Sketchfab download | the FBX | rally | in game (OCELOT R1) before this project |  |
| 15 | 2023 BMW M3 Touring (G81) | m3_touring | 2023-bmw-m3-touring.zip | FBX (in a zip) | 49 embedded | "Interior_Geo" part | "Wheel1A" parts | medium (256k) | - | Sketchfab download | the FBX | player road / premium traffic | pending | Part/material names follow Forza Horizon's asset naming ("RewardRecycled", "TNR", "Geo_lodA"): likely extracted from that game. Fine in this private repo among friends; replace before any public release. |
| 16 | 2026 Zacoe BMW M2 G87 widebody, carbon kit | m2_g87 | 2026-zacoe-bmw-g87-m2-widebody-carbon-fiber-kit.zip | FBX (in a zip) | 57 embedded, 800 px | "Interior_Geo" part | rim parts | medium (271k) | - | Sketchfab download | the FBX | player road / touge grip | pending | Part/material names follow Forza Horizon's asset naming ("RewardRecycled", "TNR", "Geo_lodA"): likely extracted from that game. Fine in this private repo among friends; replace before any public release. |
| 17 | Alfa Romeo 155 V6 TI DTM | alfa155_dtm | alfa-romeo-155-v6-ti-dtm.zip | GLB | 37 embedded, 2048 px | yes (40 interior-named parts) | 24 wheel-like parts | good (145k) | - | Sketchfab download ("ac_": likely an Assetto Corsa extraction) | the GLB | track (DTM) | pending | Name prefix "ac_" suggests it was taken from Assetto Corsa: replace before a public release. |
| 18 | BMW M4 Modified Widebody | m4_widebody | bmw-m4-modified-widebody.zip | GLB | 23 embedded, 2048 px | "InteriorA" material | to check | high (533k) | #19: byte-identical GLB | Sketchfab download | the GLB (one entry for #18 and #19) | player road / drift | pending | Part/material names follow Forza Horizon's asset naming ("RewardRecycled", "TNR", "Geo_lodA"): likely extracted from that game. Fine in this private repo among friends; replace before any public release. |
| 19 | BMW M4 Widebody (vecarz) | m4_widebody | bmw-m4-widebody-wwwvecarzcom.zip | GLB | same as #18 | same as #18 | same | same | #18: same file (SHA-256 751c816b...) | Sketchfab download | duplicate of #18: not a separate car | - | merged into #18 |  |
| 20 | BMW M5 E34 | m5_e34 | bmw-m5-e34.zip | GLB | 49 embedded, 2048 px | yes (40 interior-named parts) | 31 wheel-like parts | good (292k) | - | Sketchfab download | the GLB | player road / premium traffic | pending |  |
| 21 | BMW M8 F92 Coupe Competition | m8_f92 | bmw-m8-f92-coupe-competition (1).zip | FBX | 15 PNG | yes (40 interior-named parts) | 40 wheel-like parts | good (350k, 430 parts) | #22: the same car | Sketchfab download | this FBX (primary) | player road / premium traffic | pending |  |
| 22 | BMW M8 Competition (hyper-realistic) | m8_f92 | free-hyper-realistic-bmw-m8-competition-model.zip | USDZ | 24 JPEG (in the USDZ) | yes (interior, seat belts) | separate rims/tyres | high (1.19M) | #21: the same car | Sketchfab download | not used: #21 is the same car and imports directly | - | alternate, unused | Blender here has no USD import; part names ("BMW_M8RewardRecycled_2020") suggest a Forza extraction. |
| 23 | Lancia Delta HF Integrale Evo 2 | delta_evo2 | free-lancia-delta-hf-integrale-evo-2.zip | FBX (in a zip) | 47 | basic (kept; a gear lever added) | separate | good | - | Sketchfab download | the FBX | rally | in game (MARTELLO SEDICI) before this project |  |
| 24 | Mercedes-AMG ONE | amg_one | mercedes-amg-one.zip | GLB | 52 embedded, 1024 px | to check ("Fsteer" material: a steering wheel) | to check (generic names) | high (275k) | - | Sketchfab download | the GLB | hypercar | pending | material names ("Bumpfrontok", "Doorlfok") look like another game's export |
| 25 | Mercedes-AMG GLS 63 | gls63 | CGTrader traffic/mercedes_gls_63_amg (GLB + textures.rar); gls63.glb | GLB | 19 embedded + textures.rar (the same set) | few interior names | 5 wheel-like parts | high (334k) | gls63.glb and "textures (1).rar" are byte-identical copies | CGTrader purchase (licence to verify: owner's note) | the CGTrader GLB | premium traffic (SUV) | pending |  |
| 26 | 2009 Pagani Zonda Cinque | zonda_cinque | 2009-pagani-zonda-cinque.zip | GLB | 29 embedded, 2048 px | materials suggest one (INT_*, gauges) | everything is ONE mesh: wheels cut out by material | good (201k) | - | Sketchfab download | the GLB | hypercar | pending | single mesh |
| 27 | Bugatti Bolide | bolide | CGTrader bugatti_bolide.glb | GLB | 29 embedded, 4096 px | 13 interior-named parts | 32 wheel-like parts | high (230k) | - | CGTrader purchase | the GLB | track hypercar | pending |  |
| 28 | Bugatti Chiron (Mansory) | chiron_mansory | bugatti-chiron-mansory.zip | GLB | 92 embedded, 1024 px | interior, console, seats parts | LOD_A tyre/wheel/rotor materials | high (362k) | - | Sketchfab download | the GLB | hypercar | pending | material names ("LOD_A_TYRE_mm") look like another game's export |
| 29 | Cadillac V-Series.R | cadillac_vr | CGTrader cadillac_v_series_r.glb | GLB | 45 embedded, 4096 px | 12 interior-named parts | 12 wheel-like parts | high (406k) | - | CGTrader purchase | the GLB | race prototype (GTP) | pending |  |
| 30 | McLaren P1 GTR | p1_gtr | CGTrader mclaren_p1_gtr.fbx + textures.zip | FBX | TIF/JPEG in textures.zip (+ 2 unrelated texture packs) | few interior names | 9 wheel-like parts | very high (3.8M) | - | CGTrader purchase | the FBX | track car | pending |  |
| 31 | Koenigsegg Jesko Absolut | jesko | koenigsegg-jesko-absolut-model.zip | .blend | packed in the .blend | "Interior" part | 4 wheel parts | high (242k) | - | Sketchfab download | the .blend | hypercar | pending | materials named "CSR2_*": likely extracted from CSR Racing 2; replace before a public release |
| 32 | Porsche 911 GT3 R (992) | gt3r_992 | CGTrader porsche_911_992_gt3_r.glb | GLB | 51 embedded, 4096 px | yes (40 interior-named parts) | 28 wheel-like parts | very high (1.18M) | - | CGTrader purchase | the GLB | track (GT3) | pending |  |
| 33 | Porsche 911 GT3 R evo (2026) | gt3r_evo26 | CGTrader porsche_911_gt3_r_evo_2026.fbx + textures.zip | FBX | 47 PNG in textures.zip | to check ("Int Details", "Alcantra" materials) | "por.Wheel.*" parts | high (476k) | #32: a different year/spec | CGTrader purchase | the FBX | track (GT3) | pending |  |
| 34 | Porsche 963 | porsche_963 | CGTrader porsche_963.glb | GLB | 56 embedded, 4096 px | yes (40 interior-named parts) | 20 wheel-like parts | very high (903k) | - | CGTrader purchase | the GLB | race prototype (LMDh) | pending |  |
| 35 | Porsche 911 GT3 RS (992) 2024 (vecarz) | gt3rs_992 | porsche-992-gt3-rs-2024.zip | GLB | 48 embedded, up to 8192 px | to check (generic names) | "Wheel_Paint" materials | very high (1.72M, 361 parts) | #36: the same car | Sketchfab download (vecarz) | to compare with #36 | player road / track | pending |  |
| 36 | Porsche 911 GT3 RS (992), second package | gt3rs_992 | porsche-992-gt3-rs.zip | GLB | 85 embedded, 2400 px | some interior names | 40 wheel-like parts | high (346k, 205 parts) | #35: the same car | Sketchfab download | to compare with #35 | player road / track | pending |  |
| 37 | 1970 Chevrolet Camaro | camaro70 | CGTrader camaro_1970.fbx + textures.rar | FBX | 61 in textures.rar | few interior names | 4 wheel-like parts | very high (2.0M) | - | CGTrader purchase | the FBX | player road (muscle) | pending |  |
| 38 | Dodge Challenger SRT Hellcat (2015-19 body) | hellcat | CGTrader dodge_challenger_hellcat.fbx | FBX | none (plain materials) | none found by name: to check | "car.Wheel.*" parts | high (882k) | #39: related model, different body (standard vs widebody) | CGTrader purchase | the FBX | player road / premium traffic | pending |  |
| 39 | Dodge Challenger SRT Hellcat Widebody 2022 (hero) | hellcat_wb | CGTrader fbx.zip, gltf.zip, textures.zip | FBX and GLB, each high- and low-poly | 18 (PNG/JPEG/TIF/HDR) | few names: to check | 16 wheel-like parts | very high (3.8M high / 0.4M low) | #38 | CGTrader purchase (owner's favourite) | high-poly GLB for the player car; low-poly for LOD/traffic | hero player car | pending | the scene includes something ~250 m across (a studio floor?) |
| 40 | Generic sedan | traffic_sedan | CGTrader traffic/generic_sedan (FBX + textures.rar) | FBX | 26 PNG | simple | separate (9 wheel-like parts) | low-poly (114k) | - | CGTrader "Royalty Free (no AI)" | the FBX | traffic | pending | no-AI licence: processed only by local scripts; nobody looks at its textures or renders |
| 41 | Generic crossover | traffic_crossover | CGTrader traffic/generic_crossover (FBX + textures.rar) | FBX | 25 PNG | simple | separate | low-poly (113k) | - | CGTrader "Royalty Free (no AI)" | the FBX | traffic | pending | no-AI licence: as #40 |
| 42 | Generic minivan | traffic_minivan | CGTrader traffic/generic_minivan (FBX + textures.rar) | FBX | 25 PNG | simple | separate | low-poly (104k) | - | CGTrader "Royalty Free (no AI)" | the FBX | traffic | pending | no-AI licence: as #40 |
| 43 | Honda e (2021) | honda_e | free-honda-e-detailed-interior-2021.zip | FBX | 39 JPEG/PNG | detailed (40+ interior parts) | 1 wheel-like name: to check | very high (2.19M, 367 parts) | - | Sketchfab download | the FBX | traffic (EV) / player road | pending |  |

## Duplicate and alternate-source decisions

- **#18 / #19 BMW M4 widebody:** The two zips hold the same GLB, byte for byte (SHA-256 751c816b...). One car: m4_widebody.
- **#21 / #22 BMW M8 Competition:** The same car. #21 (FBX: 430 parts, its interior and wheels separate) imports directly; #22 is a USDZ that this Blender can't read, and its part names ("BMW_M8RewardRecycled_2020") suggest it was extracted from Forza Horizon. #21 is the car; #22 isn't used.
- **#25 Mercedes GLS 63:** gls63.glb at the top of the packages and "textures (1).rar" are byte-identical copies of the CGTrader GLS files. One car.
- **#35 / #36 Porsche 992 GT3 RS:** The same car from two sellers: compared when it's converted (see its row).
- **#38 / #39 Dodge Challenger Hellcat:** Different bodies of the same car: the 2015-19 standard body and the 2022 widebody. Both kept if both convert well; the widebody is the hero car.
- **#39 Hellcat Widebody: high or low poly:** The high-poly GLB (3.8M triangles) for the player car, thinned to the game's budget with its interior kept whole; the low-poly one (0.4M) for traffic and distant LODs.

## Provenance

Several downloads look like models extracted from commercial games rather than made by their
uploaders: Forza Horizon's asset naming ("RewardRecycled", "TNR", "Geo_lodA") in #4, #13, #15,
#16, #18 and #22; "CSR2_" materials (CSR Racing 2) in #31; an "ac_" (Assetto Corsa) prefix on #17.
They are integrated because the owner asked for every car and the repository is private and shared
among friends, as with the engine recordings. Replace them before any public release.

## Licences

The Sketchfab downloads carry no licence file; each one's page (author, licence) is recorded in
its registry entry's `source`. The CGTrader generic sedan, crossover and minivan are "Royalty Free
(no AI)": they are converted only by local scripts (`tools/import_car.py`), and nobody, human
or AI, looks at their textures or renders while doing so; they are checked by automated tests.

## Blockers

None so far.
