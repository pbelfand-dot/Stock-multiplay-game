"""BAGHOLDERS real cars — the owner's real 3D car models turned into drivable BEMZE props (bpy + PIL + numpy).

Run:  REALCARS_SRC=/path/to/models python3 tools/blender/build_realcars.py        (needs `pip install bpy==4.5.*`)
      ... build_realcars.py --only M4,M2      (a subset: the other cars are left out of the glb, quick looks)
Out:  assets/props/realcars_kit.glb (+ the reference points printed as car_refs.gd entries, and written to
      $REALCARS_REF_JSON). Godot extracts the atlases next to it (realcars_kit_RC_*.jpg/png); their .import files
      are set to VRAM compression, and the glb's to use_node_type_suffixes=false (else "*_Wheel" imports as a
      VehicleWheel3D).

The source models are NOT in the repo (they are big and they are the owner's): $REALCARS_SRC holds the unpacked
folders named in CARS below (FBX + textures). Everything the game needs is baked into the one glb.

GAME CONVENTIONS (same as build_bemze.py; read its docstring): metres, the car faces -Z in Godot (the glTF
exporter turns Blender +Y into Godot -Z, so the cars are built nose to Blender +Y), +Y up, the driver on the
LEFT (-X), origin on the ground centred between the axles. Per car <M>:

  RC_<M>          the body: paint, glass, lights, grilles, badges, the interior (engine, suspension, drivetrain
                  and duplicate / optional parts are deleted). NO wheels, NO steering wheel, NO front calipers.
  RC_<M>_Wheel    one front wheel (tire + rim + brake disc), origin = hub centre, axle along X, the rim face at
                  +X (the right side). The game turns it round for the left side.
  RC_<M>_WheelR   the rear wheel, only when it differs from the front (staggered sizes).
  RC_<M>_Caliper  the front-right brake caliper, origin = the front hub: it steers with the wheel but does not
                  spin (the game mirrors it, scale.x = -1, for the left). Rear calipers stay on the body.
  RC_<M>_Steer    the steering wheel cut out of the interior: origin = hub, rim in the XY plane facing +Z (the
                  driver); the game tilts it by column_tilt about X and spins it about Z.

MATERIALS (PropKit keeps every material whose name starts with RC_ as imported, see prop_kit.gd):
  CarPaint        the shared kit paint: WHITE vertex colours (times the model's baked AO where it has one);
                  the game tints it per car (factory colours, resprays).
  RC_<M>          ONE opaque material per car for everything else: a 1024 atlas (albedo, metal/rough, emission)
                  built from the source textures. Plain-coloured parts (palette swatches, carbon, rubber) point
                  at a white swatch and carry their colour as vertex colours. Head / running lights glow through
                  the emission atlas.
  RC_<M>_Tail     the same atlas for the red tail / brake light faces: the game brightens its emission on the
                  brakes.
  RC_<M>_Wheel    the wheel atlas (512): tire, rim, disc, caliper.
  RC_Glass        see-through tinted glass (vertex colour tint + alpha), double sided.
So a car is ~4 surfaces for the body + 1 per wheel / caliper / steering wheel.

BRAND: the game is a parody (docs/BRANDS.md, BMW -> BEMZE). Every BMW roundel on the badge / wheel / steering
wheel textures is painted over with the BEMZE roundel (a quartered ORANGE / WHITE disc in a black ring), "BMW"
lettering becomes "BEMZE" or is blanked, the tricolour stripes turn orange, the number plates read BEMZE.

BUDGET: body <= ~90k tris, wheel <= ~8k, steering wheel <= ~3k (quadric decimation weighted toward the paint and
the silhouette, the interior and hidden parts go first); custom normals are transferred back from the full
model so the panels shade like the original.
"""
import json
import math
import os
import re
import sys
import tempfile

import bpy  # noqa: I001  (bpy must be imported before bmesh/mathutils)
import bmesh
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get("REALCARS_OUT") or os.path.join(HERE, "..", "..", "assets", "props", "realcars_kit.glb")
SRC = os.environ.get("REALCARS_SRC", "")
TMP = os.environ.get("REALCARS_TMP") or os.path.join(tempfile.gettempdir(), "realcars_tmp")
ATLAS = 1024
WHEEL_ATLAS = 1024
ORANGE = (255, 115, 13)
FONT_PATHS = ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"]

# ============================================================================= per-car setup
#
# parts:    [regex on "object/parent/...|material,..." -> role]; first match wins. Roles: drop, body,
#           wheel (the quadrant comes from "Front|Rear L|R" in the name, else from the position),
#           caliper (same), steer (the steering wheel, when the model has it as its own object).
#           Anything unmatched is body.
# mats:     [regex on material name -> class dict]; first match wins:
#             {"c": "paint", "ao": bool}               CarPaint (optionally the texture as baked AO)
#             {"c": "tex", "r":, "m":, "emit": file|"self", "cap": px, "tail": True}   atlas region
#             {"c": "flat", "col": (r,g,b) or None (= sample the texture per vertex), "r":, "m":,
#              "emit": (r,g,b), "tail": True}                                          vertex colour
#             {"c": "glass", "col": (r,g,b), "a": alpha}
#             {"c": "drop"}
#           "w" = decimation weight (1 = keep the most detail), "tex" = texture file override,
#           "emit_uv": 1 + "emit": file -> faces lit on that UV set become glowing swatches.
# faces:    optional [regex on object name, material regex, new material name]: those faces get their own
#           material (then classed by `mats` like any other).
# edits:    {texture file: [ops]} brand edits in texture fractions: ("roundel", cx, cy, r),
#           ("fill", x0, y0, x1, y1, rgb | (u, v) sample point | None = the border's median), ("text", x0, y0, x1, y1, "BEMZE", fg, bg), ("orange", x0, y0, x1, y1)
# steer:    where to look for the steering wheel: regex on object|material of the parts it's cut from.

GREY_TIRE = (0.045, 0.045, 0.05)
DARK = (0.03, 0.03, 0.035)
BLACK_GLOSS = (0.015, 0.015, 0.018)

CARS = {}

CARS["M4"] = dict(
    fbx="0c3c5c73-2025-bmw-m4-competition/src/FINAL_MODEL_25.fbx", scale=100.0,
    texdirs=["0c3c5c73-2025-bmw-m4-competition/src", "0c3c5c73-2025-bmw-m4-competition/textures"],
    parts=[
        (r"brake_pad_front", "caliper"),
        (r"(Tire|Rim|BrakeDisc) (Front|Rear)", "wheel"),
    ],
    mats=[
        (r"car_body1|car_hood1|car_bodykit1", {"c": "paint", "ao": True}),
        (r"car_glass1", {"c": "glass", "sample": True}),
        (r"car_emissive1", {"c": "tex", "r": 0.25, "m": 0.0, "emit": "self", "tailred": True, "w": 0.9}),
        (r"car_interior1", {"c": "tex", "r": 0.65, "m": 0.0, "emit": "Interior_em.png", "w": 0.45}),
        (r"car_spoiler1", {"c": "flat", "col": (0.035, 0.035, 0.04), "r": 0.3, "m": 0.1}),
        (r"car_grill1", {"c": "flat", "col": (0.02, 0.02, 0.022), "r": 0.5, "m": 0.0}),
        (r"car_bodykit_plast1|car_plast1", {"c": "tex", "r": 0.45, "m": 0.05, "w": 0.7}),
        (r"TireBlur", {"c": "tex", "r": 0.9, "m": 0.0}),
        (r"BrakeDisc", {"c": "tex", "r": 0.4, "m": 0.6}),
        (r"Rim_072", {"c": "tex", "r": 0.35, "m": 0.6}),
        (r"red_caliper", {"c": "flat", "col": (0.62, 0.04, 0.04), "r": 0.35, "m": 0.1}),
        (r"metal_Capiler", {"c": "flat", "col": (0.35, 0.35, 0.37), "r": 0.4, "m": 0.5}),
        (r"phong11", {"c": "flat", "col": (0.85, 0.85, 0.85), "r": 0.4, "m": 0.0}),
        (r"phong23", {"c": "flat", "col": DARK, "r": 0.6, "m": 0.0}),
    ],
    steer=r"m4:body_Mesh_0|car_interior1",
    edits={
        # hood / trunk roundels + M4 badge on the plastics sheet, the steering-wheel roundel on the interior
        "Plast_d.png": [("roundel", 0.411, 0.869, 0.066), ("roundel", 0.910, 0.904, 0.094), ("orange", 0.67, 0.94, 0.73, 0.98)],
        "Interior_d.png": [("roundel", 0.951, 0.814, 0.034), ("orange", 0.83, 0.835, 0.885, 0.855)],
        "Emissive_d.png": [("fill", 0.53, 0.376, 0.71, 0.404, (0.77, 0.39))],     # "BMW Laser" on the tail lamp
        "e14b7d8afc2df141b7b3c29215efed40.png": [("orange", 0.0, 0.3, 0.5, 0.7)],
    },
)

CARS["M2"] = dict(
    fbx="50bf8c5b-2026-bmw-m2-cs/src/FINAL_MODEL_CS25.fbx", scale=100.0,
    texdirs=["50bf8c5b-2026-bmw-m2-cs/src", "50bf8c5b-2026-bmw-m2-cs/textures"],
    parts=[
        (r"Engine_Geo|WindowInside_Geo", "drop"),
        (r"Calliper", "caliper"),
        (r"3DWheel", "wheel"),
    ],
    mats=[
        (r"Paint_Material", {"c": "paint"}),
        (r"Window_Material|Glass_Light", {"c": "glass", "col": (0.05, 0.06, 0.07), "a": 0.55}),
        (r"Red_glass", {"c": "glass", "tail": True}),
        (r"Base_Material", {"c": "flat", "col": BLACK_GLOSS, "r": 0.6, "m": 0.0, "w": 0.5}),
        (r"Coloured_Material", {"c": "flat", "col": None, "r": 0.45, "m": 0.1, "w": 0.6}),
        (r"Carbon1Details", {"c": "flat", "col": (0.03, 0.03, 0.035), "r": 0.25, "m": 0.1, "w": 0.6}),
        (r"InteriorA", {"c": "tex", "r": 0.7, "m": 0.0, "w": 0.4, "tex": "BMW_M2CSG87_2025_InteriorA_DiffuseAOSO.png"}),
        (r"LightA", {"c": "tex", "r": 0.2, "m": 0.2, "w": 0.7, "emit": "BMW_M2CSG87_2025_LightA_Emissive.png", "emit_uv": 1}),
        (r"BadgeA", {"c": "tex", "r": 0.3, "m": 0.5, "tex": "BMW_M2CSG87_2025_BadgeA_DiffuseAOSO.png"}),
        (r"Grille", {"c": "tex", "r": 0.5, "m": 0.1, "w": 0.6}),
        (r"ManufacturerPlate", {"c": "tex", "r": 0.4, "m": 0.0, "plate": True}),
        (r"CallipersCalliperBad", {"c": "flat", "col": (0.9, 0.9, 0.9), "r": 0.4, "m": 0.0}),
        (r"Caliper_Color|CalliperA_Z", {"c": "flat", "col": (0.62, 0.04, 0.04), "r": 0.35, "m": 0.1}),
        (r"Wheel1A", {"c": "tex", "r": 0.45, "m": 0.45, "tex": "BMW_M2CSG87_2025_Wheel1A_DiffuseAOSO.png"}),
        (r"emiss:", {"c": "flat", "col": (0.8, 0.1, 0.1), "r": 0.4, "m": 0.0, "emit": (0.8, 0.1, 0.1)}),
    ],
    steer=r"Interior_Geo",
    edits={
        "BMW_M2CSG87_2025_BadgeA_DiffuseAOSO.png": [("roundel", 0.418, 0.4, 0.395), ("orange", 0.72, 0.03, 0.98, 0.2)],
        "BMW_M2CSG87_2025_Wheel1A_DiffuseAOSO.png": [("roundel", 0.1, 0.87, 0.085), ("orange", 0.0, 0.05, 0.28, 0.15)],
        "BMW_M2CSG87_2025_LightA_Diffuse.png": [("fill", 0.7, 0.28, 0.99, 0.37, None)],
        "BMW_M2CSG87_2025_InteriorA_DiffuseAOSO.png": [("orange", 0.77, 0.47, 0.9, 0.52)],
    },
)

CARS["M5"] = dict(
    fbx="5128af4b-bmw-m5-g90/src/m5/FINAL_MODEL_S.fbx", scale=100.0,
    texdirs=["5128af4b-bmw-m5-g90/src/m5", "5128af4b-bmw-m5-g90/src/textures", "5128af4b-bmw-m5-g90/textures"],
    parts=[
        (r"Engine_Geo|WindowInside_Geo", "drop"),
        (r"Calliper", "caliper"),
        (r"3DWheel", "wheel"),
    ],
    mats=[
        (r"Paint_Material", {"c": "paint"}),
        (r"Window_Material", {"c": "glass", "col": (0.05, 0.06, 0.07), "a": 0.55}),
        (r"red_glass", {"c": "glass", "tail": True}),
        (r"Base_Material", {"c": "flat", "col": BLACK_GLOSS, "r": 0.6, "m": 0.0, "w": 0.5}),
        (r"Coloured_Material", {"c": "flat", "col": None, "r": 0.45, "m": 0.1, "w": 0.6}),
        (r"Carbon1", {"c": "flat", "col": (0.03, 0.03, 0.035), "r": 0.25, "m": 0.1, "w": 0.6}),
        (r"InteriorTilling", {"c": "flat", "col": None, "r": 0.7, "m": 0.0, "w": 0.4}),
        (r"InteriorA", {"c": "tex", "r": 0.7, "m": 0.0, "w": 0.4, "tex": "BMW_M5Sedan_2024_InteriorA_DiffuseAOSO.png"}),
        (r"^emis$", {"c": "tex", "r": 0.5, "m": 0.0, "w": 0.4, "tex": "BMW_M5Sedan_2024_InteriorA_DiffuseAOSO.png",
                     "emit": "BMW_M5Sedan_2024_InteriorA_Emissive.png"}),
        (r"LightA", {"c": "tex", "r": 0.2, "m": 0.2, "w": 0.7, "emit": "BMW_M5Sedan_2024_LightA_Emissive.png", "emit_uv": 1}),
        (r"Light_emis", {"c": "flat", "col": (1.0, 0.98, 0.95), "r": 0.3, "m": 0.0, "emit": (1.0, 0.98, 0.95)}),
        (r"^gold$", {"c": "flat", "col": (0.75, 0.55, 0.2), "r": 0.3, "m": 0.6}),
        (r"^purple$", {"c": "flat", "col": (0.3, 0.3, 0.32), "r": 0.3, "m": 0.3}),
        (r"BadgeA", {"c": "tex", "r": 0.3, "m": 0.5, "tex": "BMW_M5Sedan_2024_BadgeA_DiffuseAOSO.png"}),
        (r"Grille", {"c": "tex", "r": 0.5, "m": 0.1, "w": 0.6}),
        (r"ManufacturerPlate", {"c": "tex", "r": 0.4, "m": 0.0, "plate": True}),
        (r"CallipersCalliperBadge", {"c": "flat", "col": (0.9, 0.9, 0.9), "r": 0.4, "m": 0.0}),
        (r"CalliperA_Zon", {"c": "flat", "col": (0.08, 0.2, 0.62), "r": 0.35, "m": 0.1}),
        (r"Wheel", {"c": "tex", "r": 0.45, "m": 0.45}),
    ],
    steer=r"Interior_Geo",
    edits={
        "BMW_M5Sedan_2024_BadgeA_DiffuseAOSO.png": [("roundel", 0.5, 0.5, 0.49)],
        "BMW_M5Sedan_2024_Wheel2A_DiffuseAOSO.png": [("roundel", 0.126, 0.873, 0.12), ("orange", 0.7, 0.86, 0.99, 0.98)],
        "BMW_M5Sedan_2024_LightA_Diffuse.png": [("fill", 0.0, 0.0, 0.1, 0.62, None), ("fill", 0.42, 0.08, 0.52, 0.45, None)],
        "BMW_M5Sedan_2024_InteriorA_DiffuseAOSO.png": [("roundel", 0.25, 0.145, 0.02), ("orange", 0.74, 0.62, 0.95, 0.72)],
    },
)

# the M8 is a mod with every option in one file (widebody kits, trim / mirror / grille / light variants):
# keep one stock M8 Competition: black trim, carbon roof, stock bumpers, fenders, diffuser, mirrors
M8_DROP = (r"^keyvany_|^manhart_|^wb_logo|^#m8f92_gauges|^m5f90_gauges|_dark|_(alu|cf|gold|p)(\.\d+)?$|"
           r"_L2|_R2|_L3|_R3|_cs(\.\d+)?$|^m8f92_fender_[LR](\.\d+)?$|^m8f92_mirror_[LR]_blk|^m8f92_bodyroof_black|"
           r"^m8f92_grille_[bcd]|^m8f92_logo_F_c|^m8f92_bumper_F_lip_cf|^m8f92_caliper_[FR]|^m8f92_tubs_wide|"
           r"^m8f92_(engine|engbaycrap|enginecover|radsupport(\.|$)|radiator_x|driveshaft|halfshaft|hub_|lowerarm|"
           r"upperarm|shock|spring|strut|subframe|swaybar|tierod|steeringbox|transfercase|transmission|fueltank|"
           r"heatshield|diff|exhaust|bumperbar|decals_gauges|body_badge)")
CARS["M8"] = dict(
    fbx="8d80d7d5-bmw-m8-f92-coupe-competition/source/M8.fbx", scale=1.0,
    texdirs=["8d80d7d5-bmw-m8-f92-coupe-competition/textures"],
    parts=[
        (M8_DROP, "drop"),
        (r"^m8f92_Caliper(LF|RF|LR|RR)", "caliper"),
        (r"^m8f92_(Wheel_|brakedisc_)", "wheel"),
        (r"^m8f92_steer", "steer"),
    ],
    mats=[
        (r"^m8f92_CarPaint2?$", {"c": "paint"}),
        (r"^m8f92_glass$", {"c": "glass", "col": (0.05, 0.06, 0.07), "a": 0.55}),
        (r"^m8f92_glass_red$", {"c": "glass", "tail": True}),
        (r"^m8f92_(Engine|EngineA)$|^mirror_dummy", {"c": "drop"}),
        (r"^m8f92_Coloured$", {"c": "flat", "col": (0.025, 0.025, 0.028), "r": 0.45, "m": 0.05, "w": 0.6}),
        (r"^m8f92_Base$", {"c": "flat", "col": BLACK_GLOSS, "r": 0.6, "m": 0.0, "w": 0.5}),
        (r"^m8f92_Alu$", {"c": "flat", "col": (0.6, 0.6, 0.62), "r": 0.3, "m": 0.8}),
        (r"^m8f92_Carbon1$", {"c": "flat", "col": (0.035, 0.035, 0.04), "r": 0.25, "m": 0.1, "w": 0.6}),
        (r"^m8f92_SpecularTintA$", {"c": "flat", "col": (0.12, 0.12, 0.13), "r": 0.3, "m": 0.6}),
        (r"^m8f92_Rim2A$", {"c": "flat", "col": (0.1, 0.1, 0.11), "r": 0.35, "m": 0.5}),
        (r"^m8f92_Tire1A$", {"c": "flat", "col": GREY_TIRE, "r": 0.9, "m": 0.0}),
        (r"^m8f92_Interior$", {"c": "tex", "tex": "m8f92_Interior_diff.png", "r": 0.7, "m": 0.0, "w": 0.4}),
        (r"^m8f92_Interior_Buttons$", {"c": "tex", "tex": "m8f92_InteriorButtons_diff.png", "r": 0.5, "m": 0.0, "w": 0.4}),
        (r"^m8f92_InteriorA$", {"c": "flat", "col": (0.05, 0.05, 0.055), "r": 0.5, "m": 0.2, "w": 0.4}),
        (r"^m8f92_Interior(Color2|ColourZone|TillingColourZone)$", {"c": "flat", "col": (0.12, 0.12, 0.125), "r": 0.75, "m": 0.0, "w": 0.4}),
        (r"^m8f92_Light$", {"c": "tex", "tex": "m8f92_Light_diff.png", "r": 0.2, "m": 0.3, "w": 0.7}),
        (r"^m8f92_(lowbeam|highbeam|runninglight|headlight)$", {"c": "flat", "col": (1.0, 1.0, 0.97), "r": 0.2, "m": 0.0, "emit": (1.0, 1.0, 0.97)}),
        (r"^m8f92_(signal_[LR]|foglight)$", {"c": "flat", "col": (1.0, 0.55, 0.1), "r": 0.2, "m": 0.0, "emit": (0.5, 0.25, 0.04)}),
        (r"^m8f92_taillight$", {"c": "flat", "col": (0.9, 0.05, 0.03), "r": 0.3, "m": 0.0, "emit": (0.9, 0.05, 0.03), "tail": True}),
        (r"^m8f92_reverselight$", {"c": "flat", "col": (0.85, 0.85, 0.85), "r": 0.2, "m": 0.0}),
        (r"^m8f92_Badge$", {"c": "tex", "tex": "m8f92_Badge_diff.png", "r": 0.3, "m": 0.5}),
        (r"^m8f92_Badge_blk$", {"c": "tex", "tex": "m8f92_Badge_blk_diff.png", "r": 0.3, "m": 0.3}),
        (r"^m8f92_Grille1$", {"c": "tex", "tex": "m8f92_Grille1_diff.png", "r": 0.5, "m": 0.0}),
        (r"^m8f92_Grille2$", {"c": "tex", "tex": "m8f92_Grille2_diff.png", "r": 0.5, "m": 0.0}),
        (r"^m8f92_Grille3$", {"c": "tex", "tex": "m8f92_Grille3_diff.png", "r": 0.5, "m": 0.0}),
        (r"^m8f92_Grille6$", {"c": "tex", "tex": "m8f92_Grille6_diff.png", "r": 0.5, "m": 0.0}),
        (r"^m8f92_Grille\d$", {"c": "flat", "col": DARK, "r": 0.5, "m": 0.0}),
        (r"^m8f92_gauges_screen$", {"c": "tex", "tex": "Gauges.png", "r": 0.2, "m": 0.0, "emit": "self"}),
        (r"^m8f92_screen$", {"c": "tex", "tex": "M_bootscreen.png", "r": 0.2, "m": 0.0, "emit": "self"}),
        (r"^mirror\.001$", {"c": "flat", "col": (0.55, 0.58, 0.6), "r": 0.05, "m": 0.9}),
        (r"^m8f92_disc$", {"c": "flat", "col": (0.3, 0.3, 0.31), "r": 0.4, "m": 0.6}),
        (r"^m8f92_Calliper_Color$", {"c": "flat", "col": (0.05, 0.16, 0.62), "r": 0.35, "m": 0.1}),
        (r"^m8f92_Calliper_Textured$", {"c": "flat", "col": DARK, "r": 0.5, "m": 0.1}),
        (r"^m8f92_CalliperBadge$", {"c": "flat", "col": (0.9, 0.9, 0.9), "r": 0.4, "m": 0.0}),
        (r"^m8f92$", {"c": "flat", "col": DARK, "r": 0.8, "m": 0.0, "w": 0.3}),
        (r".", {"c": "drop"}),                 # the warning-light decals etc.
    ],
    faces=[
        (r"^m8f92_brakedisc", r"^m8f92$", "m8f92_disc"),
    ],
    steer=None,
    edits={
        "m8f92_Badge_diff.png": [],
        "m8f92_Badge_blk_diff.png": [],
    },
)

ORDER = ["M4", "M2", "M5", "M8"]

# ============================================================================= helpers

R3 = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))   # Godot (x, y, z) -> Blender (x, -z, y)


def gd(v):
    """Blender -> Godot coordinates, rounded for the report."""
    return (round(v[0], 4), round(v[2], 4), round(-v[1], 4))


def srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def link(ob):
    bpy.context.scene.collection.objects.link(ob)


def select_only(obs):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]


def join(obs, name):
    obs = [o for o in obs if o is not None]
    if not obs:
        return None
    if len(obs) > 1:
        select_only(obs)
        with bpy.context.temp_override(active_object=obs[0], selected_editable_objects=obs, selected_objects=obs):
            bpy.ops.object.join()
    ob = obs[0]
    ob.name = name
    ob.data.name = name
    return ob


def alive(ob):
    try:
        ob.name
        return True
    except ReferenceError:
        return False


def tris(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons) if ob else 0


def apply_mods(ob):
    select_only([ob])
    for m in list(ob.modifiers):
        with bpy.context.temp_override(object=ob, active_object=ob):
            bpy.ops.object.modifier_apply(modifier=m.name)


def copy_ob(ob, name=None):
    c = ob.copy()
    c.data = ob.data.copy()
    c.name = name or (ob.name + "_copy")
    link(c)
    return c


def delete_faces(ob, keep_fn):
    """Delete the faces for which keep_fn(poly) is False."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    kill = [f for f in bm.faces if not keep_fn(me.polygons[f.index])]
    if kill:
        bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(me)
    bm.free()


def split_faces(ob, pick_fn, name):
    """Move the faces where pick_fn(poly) is True into a new object (returns it, or None)."""
    me = ob.data
    sel = np.array([bool(pick_fn(p)) for p in me.polygons])
    if not sel.any():
        return None
    new = copy_ob(ob, name)
    delete_faces(new, lambda p: sel[p.index])
    delete_faces(ob, lambda p: not sel[p.index])
    return new


def verts_np(ob):
    me = ob.data
    a = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", a)
    return a.reshape(-1, 3)


def bounds(obs):
    pts = np.concatenate([verts_np(o) for o in obs if o and len(o.data.vertices)])
    return pts.min(0), pts.max(0)


def loose_parts(ob):
    """Face index lists of the connected pieces of a mesh."""
    me = ob.data
    nv = len(me.vertices)
    parent = list(range(nv))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for e in me.edges:
        a, b = find(e.vertices[0]), find(e.vertices[1])
        if a != b:
            parent[a] = b
    groups = {}
    for p in me.polygons:
        groups.setdefault(find(p.vertices[0]), []).append(p.index)
    return list(groups.values())


# ============================================================================= textures

class Textures:
    def __init__(self, car):
        self.car = car
        self.dirs = [os.path.join(SRC, d) for d in car.get("texdirs", [])]
        self.cache = {}

    def path(self, name):
        if not name:
            return None
        base = os.path.basename(name.replace("\\", "/"))
        stem = os.path.splitext(base)[0]
        for d in self.dirs:
            for cand in (base, stem + ".png", stem + ".jpg", stem + ".jpeg"):
                p = os.path.join(d, cand)
                if os.path.exists(p):
                    return p
        return None

    def get(self, name):
        """float32 HxWx4 array (sRGB 0..1), brand edits applied; None if the file is missing."""
        p = self.path(name)
        if p is None:
            return None
        if p in self.cache:
            return self.cache[p]
        im = Image.open(p).convert("RGBA")
        for op in self.car.get("edits", {}).get(os.path.basename(p), []):
            im = brand_edit(im, op)
        a = np.asarray(im, dtype=np.float32) / 255.0
        self.cache[p] = a
        return a


def font(px):
    for f in FONT_PATHS:
        if os.path.exists(f):
            return ImageFont.truetype(f, max(6, int(px)))
    return ImageFont.load_default()


def draw_roundel(size):
    """The BEMZE roundel, RGBA size x size: black ring, thin chrome edges, quartered orange / white centre."""
    S = size * 4
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = S / 2
    r = S / 2 - 1
    d.ellipse((c - r, c - r, c + r, c + r), fill=(12, 12, 14, 255))
    d.ellipse((c - r, c - r, c + r, c + r), outline=(190, 192, 196, 255), width=max(2, S // 60))
    ri = r * 0.64
    d.ellipse((c - ri - S * 0.02, c - ri - S * 0.02, c + ri + S * 0.02, c + ri + S * 0.02), fill=(190, 192, 196, 255))
    for q in range(4):
        col = ORANGE + (255,) if q % 2 == 0 else (246, 246, 242, 255)
        d.pieslice((c - ri, c - ri, c + ri, c + ri), -90 + q * 90, q * 90, fill=col)
    w = max(1, S // 120)
    d.line((c - ri, c, c + ri, c), fill=(20, 20, 22, 255), width=w)
    d.line((c, c - ri, c, c + ri), fill=(20, 20, 22, 255), width=w)
    # a small "B" at the top of the ring (not the real lettering)
    f = font(r * 0.26)
    d.text((c, c - r * 0.82), "B", font=f, fill=(215, 215, 218, 255), anchor="mm")
    return im.resize((size, size), Image.LANCZOS)


def brand_edit(im, op):
    W, H = im.size
    kind = op[0]
    if kind == "roundel":
        _, cx, cy, r = op
        s = max(4, int(2 * r * W))
        ro = draw_roundel(s)
        x, y = int(cx * W - s / 2), int(cy * H - s / 2)
        base = im.crop((x, y, x + s, y + s))
        base.alpha_composite(ro)
        # keep the texture's own alpha (AO / mask channels) where the roundel sits
        im.paste(base, (x, y))
        return im
    x0, y0, x1, y1 = int(op[1] * W), int(op[2] * H), int(op[3] * W), int(op[4] * H)
    if kind == "fill":
        col = op[5]
        if isinstance(col, (tuple, list)) and len(col) == 2 and all(isinstance(v, float) for v in col) and max(col) <= 1.0:
            col = im.getpixel((int(col[0] * W), int(col[1] * H)))[:3]     # the colour at a sample point
        if col is None:     # the region's own dark background (median of its border)
            a = np.asarray(im.crop((x0, y0, x1, y1)).convert("RGB"), dtype=np.float32)
            edge = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
            col = tuple(int(v) for v in np.median(edge, axis=0))
        d = ImageDraw.Draw(im)
        d.rectangle((x0, y0, x1, y1), fill=tuple(col) + (im.getpixel((x0, y0))[3],))
        return im
    if kind == "text":
        _, _, _, _, _, s, fg, bg = op
        d = ImageDraw.Draw(im)
        if bg is not None:
            d.rectangle((x0, y0, x1, y1), fill=tuple(bg) + (255,))
        d.text(((x0 + x1) / 2, (y0 + y1) / 2), s, font=font((y1 - y0) * 0.7), fill=tuple(fg) + (255,), anchor="mm")
        return im
    if kind == "orange":
        # the M tricolour: saturated blues / reds -> BEMZE orange shades (greys untouched)
        a = np.asarray(im, dtype=np.float32).copy()
        reg = a[y0:y1, x0:x1, :3]
        mx, mn = reg.max(-1), reg.min(-1)
        sat = (mx - mn) / np.maximum(mx, 1)
        m = (sat > 0.35) & (mx > 40)
        lum = (0.3 * reg[..., 0] + 0.59 * reg[..., 1] + 0.11 * reg[..., 2]) / 255.0
        k = np.clip(0.55 + lum, 0.5, 1.2)[..., None]
        reg[m] = (np.array(ORANGE, dtype=np.float32)[None, None, :] * k)[m].clip(0, 255)
        a[y0:y1, x0:x1, :3] = reg
        return Image.fromarray(a.astype(np.uint8), "RGBA")
    raise ValueError(op)


def plate_image(w=512, h=256):
    """A BEMZE number plate: white, black border, BEMZE in the middle."""
    im = Image.new("RGBA", (w, h), (236, 236, 232, 255))
    d = ImageDraw.Draw(im)
    b = max(3, h // 22)
    d.rounded_rectangle((b, b, w - b, h - b), radius=h // 10, outline=(20, 20, 24, 255), width=b)
    d.text((w / 2, h * 0.53), "BEMZE", font=font(h * 0.5), fill=(18, 18, 22, 255), anchor="mm")
    d.rectangle((w * 0.1, h * 0.12, w * 0.9, h * 0.2), fill=(255, 115, 13, 255))
    return np.asarray(im, dtype=np.float32) / 255.0


TAIL_EMIT = (0.6, 0.03, 0.02)   # the tail lamps' glow (the game scales it up on the brakes)
LENS_Z = 0.9          # glass faces lower than this (m) are head / tail lamp lenses, not windows
_SOFT = {}


def soft(img):
    """A blurred copy of a texture (cached)."""
    if id(img) not in _SOFT:
        from PIL import ImageFilter
        im = Image.fromarray((img * 255).astype(np.uint8), "RGBA").filter(ImageFilter.GaussianBlur(img.shape[1] / 150))
        _SOFT[id(img)] = np.asarray(im, np.float32) / 255
    return _SOFT[id(img)]


def unwrap_tiles(ob):
    """Wrapping UVs (faces in the 1..2 tile etc. that repeat the texture): move every face's first UV set back
    into the 0..1 tile by whole tiles, so an atlas region can hold it."""
    me = ob.data
    if not me.uv_layers:
        return
    nl, npoly = len(me.loops), len(me.polygons)
    uv = np.zeros(nl * 2)
    me.uv_layers[0].data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    ls = np.zeros(npoly, int)
    lt = np.zeros(npoly, int)
    me.polygons.foreach_get("loop_start", ls)
    me.polygons.foreach_get("loop_total", lt)
    fl = np.repeat(np.arange(npoly), lt)
    cu = np.bincount(fl, weights=uv[:, 0], minlength=npoly) / np.maximum(lt, 1)
    cv = np.bincount(fl, weights=uv[:, 1], minlength=npoly) / np.maximum(lt, 1)
    uv[:, 0] -= np.floor(cu)[fl]
    uv[:, 1] -= np.floor(cv)[fl]
    me.uv_layers[0].data.foreach_set("uv", uv.reshape(-1))


def sample(img, uv):
    """Nearest texel of img (HxWx4) at uv (N x 2, wrapping)."""
    H, W = img.shape[:2]
    x = np.floor(np.mod(uv[:, 0], 1.0) * W).astype(int).clip(0, W - 1)
    y = np.floor(np.mod(1.0 - uv[:, 1], 1.0) * H).astype(int).clip(0, H - 1)
    return img[y, x]


def region_crop(img, u0, v0, u1, v1, w, h):
    """Resample the UV rectangle [u0,u1]x[v0,v1] of img (wrapping) into an h x w array."""
    H, W = img.shape[:2]
    sw = max(1, int(round((u1 - u0) * W)))
    sh = max(1, int(round((v1 - v0) * H)))
    xs = np.floor(np.mod(u0 + (np.arange(sw) + 0.5) / sw * (u1 - u0), 1.0) * W).astype(int).clip(0, W - 1)
    ys = np.floor(np.mod(1.0 - (v1 - (np.arange(sh) + 0.5) / sh * (v1 - v0)), 1.0) * H).astype(int).clip(0, H - 1)
    crop = img[ys][:, xs]
    pim = Image.fromarray((crop * 255).clip(0, 255).astype(np.uint8), "RGBA")
    pim = pim.resize((w, h), Image.LANCZOS if (w < sw or h < sh) else Image.BILINEAR)
    return np.asarray(pim, dtype=np.float32) / 255.0


class Atlas:
    """Shelf-packed texture atlas: textured regions + small swatches (white albedo, fixed metal / rough /
    emission) for vertex-coloured faces."""
    PAD = 4

    def __init__(self, size):
        self.size = size
        self.regions = {}     # key -> dict(img, emit, r, m, w, h)
        self.swatches = {}    # key -> dict(r, m, emit)
        self.place = {}

    def add_region(self, key, img, emit, r, m, want_w, want_h):
        self.regions[key] = dict(img=img, emit=emit, r=r, m=m, w=want_w, h=want_h)

    def swatch(self, r, m, emit=(0, 0, 0)):
        key = (round(r, 2), round(m, 2), tuple(round(float(e), 2) for e in emit))
        self.swatches.setdefault(key, dict(r=r, m=m, emit=emit))
        return key

    def pack(self):
        scale = 1.0
        for _ in range(40):
            items = [(k, max(4, int(v["w"] * scale)), max(4, int(v["h"] * scale))) for k, v in self.regions.items()]
            items += [(("sw",) + k, 8, 8) for k in self.swatches]
            items.sort(key=lambda t: -t[2])
            place, x, y, row = {}, 0, 0, 0
            ok = True
            P = self.PAD
            for k, w, h in items:
                if x + w + 2 * P > self.size:
                    x, y, row = 0, y + row, 0
                if y + h + 2 * P > self.size:
                    ok = False
                    break
                place[k] = (x + P, y + P, w, h)
                x += w + 2 * P
                row = max(row, h + 2 * P)
            if ok:
                self.place = place
                return scale
            scale *= 0.9
        raise RuntimeError("atlas overflow")

    def uv_of_swatch(self, key):
        x, y, w, h = self.place[("sw",) + key]
        return ((x + w / 2) / self.size, 1.0 - (y + h / 2) / self.size)

    def uv_map(self, key, uv, box):
        """Source UVs inside box (u0, v0, u1, v1) -> atlas UVs of the region `key`."""
        x, y, w, h = self.place[key]
        u0, v0, u1, v1 = box
        fu = ((uv[:, 0] - u0) / max(u1 - u0, 1e-6)).clip(0, 1)
        fv = ((v1 - uv[:, 1]) / max(v1 - v0, 1e-6)).clip(0, 1)
        au = (x + fu * w) / self.size
        av = 1.0 - (y + fv * h) / self.size
        return np.stack([au, av], 1)

    def render(self):
        S, P = self.size, self.PAD
        alb = np.zeros((S, S, 3), np.float32)
        orm = np.zeros((S, S, 3), np.float32)
        emi = np.zeros((S, S, 3), np.float32)
        orm[..., 0] = 1.0
        orm[..., 1] = 0.6

        def put(x, y, w, h, a, o, e):
            # pixel extension into the padding (no seams when mip-mapped)
            ys = np.clip(np.arange(y - P, y + h + P) - y, 0, h - 1)
            xs = np.clip(np.arange(x - P, x + w + P) - x, 0, w - 1)
            alb[y - P:y + h + P, x - P:x + w + P] = a[ys][:, xs]
            orm[y - P:y + h + P, x - P:x + w + P] = o[ys][:, xs]
            emi[y - P:y + h + P, x - P:x + w + P] = e[ys][:, xs]
        for k, v in self.regions.items():
            x, y, w, h = self.place[k]
            a = region_crop(v["img"], *v["box"], w, h)[..., :3] if "box" in v else v["img"][..., :3]
            if a.shape[:2] != (h, w):
                a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS), np.float32) / 255
            o = np.empty((h, w, 3), np.float32)
            o[..., 0], o[..., 1], o[..., 2] = 1.0, v["r"], v["m"]
            if v["emit"] is None:
                e = np.zeros((h, w, 3), np.float32)
            else:
                e = region_crop(v["emit"], *v["box"], w, h)[..., :3]
            put(x, y, w, h, a, o, e)
        for k, v in self.swatches.items():
            x, y, w, h = self.place[("sw",) + k]
            a = np.ones((h, w, 3), np.float32)
            o = np.empty((h, w, 3), np.float32)
            o[..., 0], o[..., 1], o[..., 2] = 1.0, v["r"], v["m"]
            e = np.empty((h, w, 3), np.float32)
            e[...] = np.asarray(v["emit"], np.float32)
            put(x, y, w, h, a, o, e)
        return alb, orm, emi


def save_img(arr, path, jpeg):
    im = Image.fromarray((arr.clip(0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
    if jpeg:
        im.save(path, quality=90, subsampling=0)
    else:
        im.save(path, optimize=True)
    return path


# ============================================================================= materials (Blender side)

BMATS = {}


def bl_mat(name, alb=None, orm=None, emi=None, glass=False):
    if name in BMATS:
        return BMATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    if name == "CarPaint":
        # (no vertex-colour node: with one the exporter writes COLOR_0 without alpha, and the glass needs it)
        bsdf.inputs["Roughness"].default_value = 0.2
        bsdf.inputs["Metallic"].default_value = 0.35
    if glass:
        bsdf.inputs["Base Color"].default_value = (0.05, 0.06, 0.07, 1)
        bsdf.inputs["Alpha"].default_value = 0.5
        bsdf.inputs["Roughness"].default_value = 0.05
        m.surface_render_method = "BLENDED"
    if alb:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(alb)
        nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    if orm:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(orm)
        t.image.colorspace_settings.name = "Non-Color"
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(t.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    if emi:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(emi)
        nt.links.new(t.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
    BMATS[name] = m
    return m


# ============================================================================= the pipeline

class Car:
    def __init__(self, key):
        self.key = key
        self.cfg = CARS[key]
        self.tex = Textures(self.cfg)
        self.mat_info = {}      # source material name -> {"diffuse": file, "base": rgba}
        self.parts = []         # [object] with ob["role"], ob["quad"], ob["chain"]
        self.ref = {}

    # ---------------------------------------------------------------- import
    def load(self):
        path = os.path.join(SRC, self.cfg["fbx"])
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=path, use_custom_normals=True)
        new = [o for o in bpy.data.objects if o not in before]
        for m in bpy.data.materials:
            if m.name in self.mat_info or not m.use_nodes:
                continue
            info = {"diffuse": None, "base": (1, 1, 1, 1)}
            b = m.node_tree.nodes.get("Principled BSDF")
            if b:
                info["base"] = tuple(b.inputs["Base Color"].default_value)
                for l in b.inputs["Base Color"].links:
                    if l.from_node.type == "TEX_IMAGE" and l.from_node.image:
                        info["diffuse"] = l.from_node.image.filepath
            self.mat_info[m.name] = info
        dg = bpy.context.evaluated_depsgraph_get()
        M = Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Scale(self.cfg["scale"], 4)
        out = []
        for ob in new:
            if ob.type != "MESH" or len(ob.data.polygons) == 0:
                continue
            chain, o = [], ob
            while o:
                chain.append(o.name)
                o = o.parent
            mats = [s.material.name if s.material else "" for s in ob.material_slots]
            me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
            W = M @ ob.matrix_world
            me.transform(W)
            if W.to_3x3().determinant() < 0:
                me.flip_normals()
            for i, uvl in enumerate(me.uv_layers):
                uvl.name = "UV%d" % i
            no = bpy.data.objects.new("%s_%d" % (self.key, len(out)), me)
            no["chain"] = "/".join(chain)
            no["mats"] = ",".join(mats)
            out.append(no)
        for o in new:
            bpy.data.objects.remove(o)
        for no in out:
            link(no)
        self.parts = out
        print("[%s] imported %d meshes, %d tris" % (self.key, len(out), sum(tris(o) for o in out)))

    # ---------------------------------------------------------------- classify
    def mat_class(self, mname, obname=""):
        for rx, c in self.cfg["mats"]:
            if re.search(rx, mname):
                return c
        return {"c": "flat", "col": None, "r": 0.5, "m": 0.0, "w": 0.5}

    def classify(self):
        keep = []
        for ob in self.parts:
            key = ob["chain"] + "|" + ob["mats"]
            role = "body"
            for rx, r in self.cfg["parts"]:
                if re.search(rx, key):
                    role = r
                    break
            if role == "drop":
                bpy.data.objects.remove(ob)
                continue
            # per-object material overrides
            for obre, mre, newname in self.cfg.get("faces", []):
                if re.search(obre, ob["chain"].split("/")[0]):
                    for sl in ob.material_slots:
                        if sl.material and re.search(mre, sl.material.name):
                            nm = bpy.data.materials.get(newname) or sl.material.copy()
                            nm.name = newname
                            self.mat_info[newname] = self.mat_info.get(sl.material.name, {})
                            sl.material = nm
            # faces of dropped material classes go now
            names = [s.material.name if s.material else "" for s in ob.material_slots]
            obname = ob["chain"].split("/")[0]
            dropm = {i for i, n in enumerate(names) if self.mat_class(n, obname)["c"] == "drop"}
            if dropm:
                delete_faces(ob, lambda p: p.material_index not in dropm)
                if len(ob.data.polygons) == 0:
                    bpy.data.objects.remove(ob)
                    continue
            if role == "wheel":
                lo, hi = bounds([ob])
                if hi[0] - lo[0] < 0.03 and hi[2] - lo[2] > 0.4:
                    # a flat card over the whole wheel face: the motion-blur disc some models carry
                    print("   [%s] drop blur disc %s" % (self.key, ob["chain"].split("/")[0]))
                    bpy.data.objects.remove(ob)
                    continue
            ob["role"] = role
            m = re.search(r"(Front|Rear) ?([LR])\b", ob["chain"]) or re.search(r"([FR])([LR])(_|$)", ob["chain"].split("/")[0].replace("Caliper", "_"))
            ob["quad"] = ""
            if m:
                fr = "F" if m.group(1)[0] == "F" else "R"
                ob["quad"] = fr + m.group(2)
            keep.append(ob)
        self.parts = keep
        # parts without a quadrant in the name (one mesh holding all four calipers ...): split by position
        more = []
        for ob in self.parts:
            if ob["role"] in ("wheel", "caliper") and not ob["quad"]:
                lo, hi = bounds([ob])
                if hi[0] > 0.2 and lo[0] < -0.2 or hi[1] > 0 and lo[1] < 0:
                    me = ob.data
                    cent = {p.index: p.center.copy() for p in me.polygons}
                    for q in ("FL", "FR", "RL", "RR"):
                        sx = -1 if q[1] == "L" else 1
                        sy = 1 if q[0] == "F" else -1
                        piece = copy_ob(ob, ob.name + q)
                        delete_faces(piece, lambda p, sx=sx, sy=sy: cent[p.index].x * sx > 0 and cent[p.index].y * sy > 0)
                        if len(piece.data.polygons):
                            piece["quad"] = q
                            more.append(piece)
                        else:
                            bpy.data.objects.remove(piece)
                    bpy.data.objects.remove(ob)
                    continue
                c = (lo + hi) / 2
                ob["quad"] = ("F" if c[1] > 0 else "R") + ("L" if c[0] < 0 else "R")
            more.append(ob)
        self.parts = more
        # a quadrant name L/R is the car's own left / right: after the turn round the left is -x
        for ob in self.parts:
            if ob["role"] in ("wheel", "caliper"):
                lo, hi = bounds([ob])
                c = (lo + hi) / 2
                want = ("F" if c[1] > 0 else "R") + ("L" if c[0] < 0 else "R")
                if want != ob["quad"]:
                    ob["quad"] = want
        roles = {}
        for ob in self.parts:
            k = ob["role"] + (":" + ob["quad"] if ob["quad"] and ob["role"] != "body" else "")
            roles[k] = roles.get(k, 0) + tris(ob)
        print("[%s] roles: %s" % (self.key, ", ".join("%s %d" % kv for kv in sorted(roles.items()))))

    # ---------------------------------------------------------------- origin + wheels
    def normalise(self):
        hubs = {}
        for q in ("FL", "FR", "RL", "RR"):
            obs = [o for o in self.parts if o["role"] == "wheel" and o["quad"] == q]
            tire = [o for o in obs if re.search(r"(?i)tire|3DWheel|Wheel_01", o["chain"] + o["mats"])] or obs
            lo, hi = bounds(tire)
            wl, wh = bounds(obs)
            hubs[q] = dict(c=(lo + hi) / 2, r=(hi[2] - lo[2]) / 2, width=hi[0] - lo[0], lo=wl, hi=wh)
        ground = min(h["c"][2] - h["r"] for h in hubs.values())
        yf = (hubs["FL"]["c"][1] + hubs["FR"]["c"][1]) / 2
        yr = (hubs["RL"]["c"][1] + hubs["RR"]["c"][1]) / 2
        xm = sum(h["c"][0] for h in hubs.values()) / 4
        off = Vector((-xm, -(yf + yr) / 2, -ground))
        T = Matrix.Translation(off)
        for ob in self.parts:
            ob.data.transform(T)
        for h in hubs.values():
            h["c"] = h["c"] + np.array(off)
        self.hubs = hubs
        self.wheelbase = yf - yr
        rf = (hubs["FL"]["r"] + hubs["FR"]["r"]) / 2
        rr = (hubs["RL"]["r"] + hubs["RR"]["r"]) / 2
        print("[%s] wheelbase %.3f  r front %.3f rear %.3f  width f %.3f r %.3f" % (
            self.key, self.wheelbase, rf, rr, hubs["FR"]["width"], hubs["RR"]["width"]))

    # ---------------------------------------------------------------- steering wheel
    def cut_steering_wheel(self):
        named = [o for o in self.parts if o["role"] == "steer"]
        if named:
            steer = join(named, "steer_src")
        else:
            srcs = [o for o in self.parts if o["role"] == "body" and re.search(self.cfg["steer"], o["chain"] + "|" + o["mats"])]
            best = None
            for ob in srcs:
                me = ob.data
                V = verts_np(ob)
                for faces in loose_parts(ob):
                    vi = np.unique(np.concatenate([np.array(me.polygons[f].vertices) for f in faces]))
                    P = V[vi]
                    lo, hi = P.min(0), P.max(0)
                    c, s = (lo + hi) / 2, hi - lo
                    if not (c[0] < -0.2 and 0.05 < c[1] < 0.9 and 0.6 < c[2] < 1.15):
                        continue
                    big = sorted(s)
                    if not (0.3 < big[2] < 0.46 and big[1] > 0.25):
                        continue
                    score = big[2] + big[1] - 2 * big[0]
                    if best is None or score > best[0]:
                        best = (score, ob, faces, P)
            if best is None:
                raise RuntimeError("no steering wheel rim found")
            _, rob, rfaces, P = best
            c = (P.min(0) + P.max(0)) / 2
            n = self._axis(P, c)
            rad = np.linalg.norm((P - c) - np.outer((P - c) @ n, n), axis=1).max()
            picked = []
            for ob in srcs:
                me = ob.data
                V = verts_np(ob)
                sel = set()
                for faces in loose_parts(ob):
                    vi = np.unique(np.concatenate([np.array(me.polygons[f].vertices) for f in faces]))
                    d = V[vi] - c
                    ax = d @ n
                    rr = np.linalg.norm(d - np.outer(ax, n), axis=1)
                    inside = (rr < rad + 0.012) & (ax > -0.075) & (ax < 0.07)
                    if inside.mean() > 0.97:
                        sel.update(faces)
                if sel:
                    part = split_faces(ob, lambda p, sel=sel: p.index in sel, ob.name + "_steer")
                    if part:
                        picked.append(part)
            steer = join(picked, "steer_src")
        P = verts_np(steer)
        lo, hi = P.min(0), P.max(0)
        # the rim: points far from the middle of the bbox give the plane
        c = (lo + hi) / 2
        n = self._axis(P, c)
        # hub = the centre of the rim ring (the widest ring of points around the axis)
        d = P - c
        rr = np.linalg.norm(d - np.outer(d @ n, n), axis=1)
        ring = P[rr > rr.max() * 0.8]
        c = ring.mean(0)
        self.steer_src = steer
        self.steer_hub = Vector(c)
        self.steer_axis = Vector(n)
        self.steer_r = float(rr.max())
        steer["role"] = "steer"
        steer["quad"] = ""
        self.parts = [o for o in self.parts if alive(o) and o["role"] != "steer"] + [steer]
        print("[%s] steering wheel: %d tris, hub %s, radius %.3f, axis %s" % (
            self.key, tris(steer), gd(c), self.steer_r, gd(n)))

    @staticmethod
    def _axis(P, c):
        """The steering wheel's column axis (the plane normal), pointing at the driver (Blender -Y) and up."""
        d = P - c
        w, v = np.linalg.eigh(d.T @ d)
        n = v[:, 0]
        if n[1] > 0:
            n = -n
        return n / np.linalg.norm(n)

    # ---------------------------------------------------------------- props
    def build_props(self):
        K = self.key
        body = [o for o in self.parts if o["role"] == "body"]
        props = {}
        # wheels: the right-hand ones (rim face +x), hub at the origin
        fr = [o for o in self.parts if o["role"] == "wheel" and o["quad"] == "FR"]
        rr = [o for o in self.parts if o["role"] == "wheel" and o["quad"] == "RR"]
        hf, hr = self.hubs["FR"], self.hubs["RR"]
        stagger = abs(hf["r"] - hr["r"]) > 0.006 or abs(hf["width"] - hr["width"]) > 0.012
        props["RC_%s_Wheel" % K] = (fr, Vector(hf["c"]), 8000)
        if stagger:
            props["RC_%s_WheelR" % K] = (rr, Vector(hr["c"]), 8000)
        cal = [o for o in self.parts if o["role"] == "caliper" and o["quad"] == "FR"]
        if cal:
            props["RC_%s_Caliper" % K] = (cal, Vector(hf["c"]), 1500)
        body += [o for o in self.parts if o["role"] == "caliper" and o["quad"][0] == "R"]
        props["RC_%s" % K] = (body, Vector((0, 0, 0)), 90000)
        props["RC_%s_Steer" % K] = ([self.steer_src], self.steer_hub, 3000)
        # the rest (left wheels / calipers) are not needed
        used = {o.name for v in props.values() for o in v[0]}
        for o in list(self.parts):
            if o.name not in used:
                bpy.data.objects.remove(o)
        self.stagger = stagger
        self.props = {}
        for name, (obs, origin, budget) in props.items():
            self.props[name] = self.decimate(name, obs, budget)
            ob = self.props[name]
            if name.endswith("_Steer"):
                # upright: the column axis -> +Z Godot (= -Y Blender), about X only
                n = self.steer_axis
                tilt = math.atan2(n.z, -n.y)          # Godot: atan2(-n_g.y, n_g.z) with n_g = (x, z, -y)
                tilt = -tilt
                self.column_tilt = tilt
                ob.data.transform(Matrix.Rotation(-tilt, 4, "X") @ Matrix.Translation(-origin))
            else:
                ob.data.transform(Matrix.Translation(-origin))
            print("[%s] %-18s %6d tris" % (K, name, tris(ob)))

    def decimate(self, name, obs, budget):
        """Join per decimation weight, collapse-decimate toward the budget, transfer the custom normals back."""
        groups = {}
        for ob in obs:
            names = [s.material.name if s.material else "" for s in ob.material_slots]
            obn = ob["chain"].split("/")[0] if "chain" in ob else ""
            # split multi-material objects by weight class
            ws = {}
            for p in ob.data.polygons:
                n = names[p.material_index] if p.material_index < len(names) else ""
                w = float(self.mat_class(n, obn).get("w", 1.0 if self.mat_class(n, obn)["c"] in ("paint", "glass") else 0.7))
                ws.setdefault(w, []).append(p.index)
            if len(ws) == 1:
                groups.setdefault(list(ws)[0], []).append(ob)
            else:
                for w, faces in ws.items():
                    fs = set(faces)
                    piece = copy_ob(ob, ob.name + "_w%.2f" % w)
                    delete_faces(piece, lambda p, fs=fs: p.index in fs)
                    groups.setdefault(w, []).append(piece)
                bpy.data.objects.remove(ob)
        joined = {w: join(g, "%s_g%.2f" % (name, w)) for w, g in groups.items()}
        total = sum(tris(o) for o in joined.values())
        if total > budget:
            # ratio_g = min(1, k * w): solve for k
            lo_k, hi_k = 0.0, 4.0
            for _ in range(40):
                k = (lo_k + hi_k) / 2
                t = sum(tris(o) * min(1.0, k * w) for w, o in joined.items())
                lo_k, hi_k = (k, hi_k) if t < budget else (lo_k, k)
            k = lo_k
            for w, o in joined.items():
                ratio = min(1.0, k * w)
                if ratio < 0.999 and tris(o) > 200:
                    ref = copy_ob(o, o.name + "_ref")
                    dm = o.modifiers.new("dec", "DECIMATE")
                    dm.decimate_type = "COLLAPSE"
                    dm.ratio = ratio
                    dm.use_collapse_triangulate = True
                    apply_mods(o)
                    dt = o.modifiers.new("nrm", "DATA_TRANSFER")
                    dt.object = ref
                    dt.use_loop_data = True
                    dt.data_types_loops = {"CUSTOM_NORMAL"}
                    dt.loop_mapping = "POLYINTERP_NEAREST"
                    apply_mods(o)
                    bpy.data.objects.remove(ref)
        ob = join(list(joined.values()), name)
        return ob

    # ---------------------------------------------------------------- materials, atlas, vertex colours
    def texture_for(self, mname, cls):
        if cls.get("plate"):
            return plate_image()
        f = cls.get("tex") or self.mat_info.get(mname, {}).get("diffuse")
        return self.tex.get(f) if f else None

    def bake_materials(self, props, atlas_size, mat_name):
        """Final materials for `props` (all sharing one atlas): UVs into the atlas, vertex colours, slots."""
        atlas = Atlas(atlas_size)
        for ob in props:
            unwrap_tiles(ob)
        # pass 1: per source material, its class and the UV range its faces use
        info = {}
        for ob in props:
            me = ob.data
            names = [s.material.name if s.material else "" for s in ob.material_slots]
            uv = np.zeros(len(me.loops) * 2)
            if me.uv_layers:
                me.uv_layers[0].data.foreach_get("uv", uv)
            uv = uv.reshape(-1, 2)
            obn = ob.get("src_names", "")
            for i, n in enumerate(names):
                cls = self.mat_class(n, obn)
                rec = info.setdefault(n, {"cls": cls, "uvs": []})
                if cls["c"] == "tex":
                    li = [li for p in me.polygons if p.material_index == i for li in p.loop_indices]
                    if li:
                        rec["uvs"].append(uv[li])
        for n, rec in info.items():
            cls = rec["cls"]
            if cls["c"] != "tex":
                continue
            img = self.texture_for(n, cls)
            if img is None or not rec["uvs"]:
                print("   [%s] %s: no texture -> flat" % (self.key, n))
                rec["cls"] = dict(cls, c="flat", col=cls.get("col", (0.5, 0.5, 0.5)))
                continue
            U = np.concatenate(rec["uvs"])
            lo = np.percentile(U, 0.1, axis=0)
            hi = np.percentile(U, 99.9, axis=0)
            if (hi - lo).max() > 1.05:
                print("   [%s] %s: tiling UVs %s..%s -> sampled vertex colours" % (self.key, n, lo.round(2), hi.round(2)))
                rec["cls"] = dict(cls, c="flat", col=None)
                continue
            emit = None
            if cls.get("emit") == "self":
                emit = img
            elif isinstance(cls.get("emit"), str) and not cls.get("emit_uv"):
                emit = self.tex.get(cls["emit"])
            rec["box"] = (float(lo[0]), float(lo[1]), float(hi[0]), float(hi[1]))
            rec["img"] = img
            rec["emit"] = emit
            # materials sharing one texture (and finish) share one region: the union of their UV boxes
            rec["rkey"] = (id(img), round(cls.get("r", 0.5), 2), round(cls.get("m", 0.0), 2), id(emit))
        groups = {}
        for n, rec in info.items():
            if "rkey" in rec:
                groups.setdefault(rec["rkey"], []).append(rec)
        for gi, (rk, recs) in enumerate(groups.items()):
            box = (min(r["box"][0] for r in recs), min(r["box"][1] for r in recs),
                   max(r["box"][2] for r in recs), max(r["box"][3] for r in recs))
            img, cls = recs[0]["img"], recs[0]["cls"]
            H, W = img.shape[:2]
            px_w = max(8, int((box[2] - box[0]) * W))
            px_h = max(8, int((box[3] - box[1]) * H))
            s_ = min(1.0, max(r["cls"].get("cap", 512) for r in recs) / max(px_w, px_h))
            atlas.add_region(rk, img, recs[0]["emit"], cls.get("r", 0.5), cls.get("m", 0.0), int(px_w * s_), int(px_h * s_))
            atlas.regions[rk]["box"] = box
            for r in recs:
                r["box"] = box
        # pass 2: faces -> slots, UVs, colours (swatch UVs are filled in after packing)
        slot_names = ["CarPaint", "RC_Glass", mat_name, mat_name + "_Tail"]
        jobs = []
        for ob in props:
            me = ob.data
            names = [s.material.name if s.material else "" for s in ob.material_slots]
            nl, npoly = len(me.loops), len(me.polygons)
            uvs = []
            for k in range(len(me.uv_layers)):
                a = np.zeros(nl * 2)
                me.uv_layers[k].data.foreach_get("uv", a)
                uvs.append(a.reshape(-1, 2))
            if not uvs:
                uvs.append(np.zeros((nl, 2)))
            out_uv = np.zeros((nl, 2))
            out_col = np.ones((nl, 4))
            slot = np.full(npoly, 2, int)
            ls = np.zeros(npoly, int)
            lt = np.zeros(npoly, int)
            mi = np.zeros(npoly, int)
            me.polygons.foreach_get("loop_start", ls)
            me.polygons.foreach_get("loop_total", lt)
            me.polygons.foreach_get("material_index", mi)
            sw_loops = []
            for i, n in enumerate(names):
                faces = np.nonzero(mi == i)[0]
                if not len(faces):
                    continue
                rec = info[n]
                cls = rec["cls"]
                li = np.concatenate([np.arange(ls[f], ls[f] + lt[f]) for f in faces])
                fl = np.repeat(faces, lt[faces])
                uv0 = uvs[0][li]
                c = cls["c"]
                if c == "paint":
                    slot[faces] = 0
                    col = np.ones((len(li), 3))
                    if cls.get("ao"):
                        img = self.texture_for(n, cls)
                        if img is not None:
                            # a soft version of the baked AO (per-vertex samples of a sharp map pick up the
                            # dark outlines of the UV islands)
                            g = np.clip(sample(soft(img), uv0)[:, :3].mean(1), 0.0, 1.0)
                            g = 0.45 + 0.55 * g
                            col = np.repeat(srgb_to_lin(g)[:, None], 3, 1)
                    out_col[li, :3] = col
                elif c == "glass":
                    slot[faces] = 1
                    out_col[li, :3] = cls.get("col", (0.05, 0.06, 0.07))
                    out_col[li, 3] = cls.get("a", 0.5)
                    fz = np.array([me.polygons[f].center.z for f in fl])
                    low = fz < LENS_Z
                    red = np.zeros(len(li), bool)
                    img = self.texture_for(n, cls) if cls.get("sample") else None
                    if img is not None:
                        # tint and opacity from the model's glass texture (dark windows, clear / red lenses)
                        t = sample(img, uv0)
                        out_col[li, :3] = t[:, :3] * 0.6
                        out_col[li, 3] = np.clip(t[:, 3], 0.08, 0.8)
                        red = (t[:, 0] > 0.25) & (t[:, 0] > 2.0 * t[:, 1]) & low
                    elif not cls.get("keep"):
                        # below the beltline it's a lamp lens: nearly clear
                        out_col[li[low], :3] = (0.85, 0.87, 0.9)
                        out_col[li[low], 3] = 0.12
                    if cls.get("tail"):
                        red[:] = True
                    if red.any():
                        # red lenses: the opaque, glowing brake-light surface
                        fr = np.bincount(fl, weights=red.astype(float), minlength=npoly)
                        fc = np.maximum(np.bincount(fl, minlength=npoly), 1)
                        tf = faces[(fr[faces] / fc[faces]) > 0.5]
                        slot[tf] = 3
                        tl = np.isin(fl, tf)
                        out_col[li[tl]] = (0.75, 0.04, 0.03, 1.0)
                        sw_loops.append((li[tl], atlas.swatch(0.2, 0.0, TAIL_EMIT)))
                elif c == "tex":
                    slot[faces] = 2
                    sw_loops.append((li, ("reg", rec["rkey"], uv0, rec["box"])))
                    if cls.get("tailred") and rec.get("emit") is not None:
                        e = sample(rec["emit"], uv0)[:, :3]
                        red = ((e[:, 0] > 0.3) & (e[:, 0] > 2.2 * e[:, 1]) & (e[:, 0] > 2.2 * e[:, 2])).astype(float)
                        fr = np.bincount(fl, weights=red, minlength=npoly)
                        fc = np.maximum(np.bincount(fl, minlength=npoly), 1)
                        slot[faces[(fr[faces] / fc[faces]) > 0.5]] = 3
                    if cls.get("emit_uv") and isinstance(cls.get("emit"), str):
                        self._emit_faces(atlas, cls, uvs, li, fl, faces, slot, out_col, npoly, sw_loops)
                else:   # flat
                    if cls.get("col") is None:
                        img = self.texture_for(n, cls)
                        if img is not None:
                            col = sample(img, uv0)[:, :3]
                        else:
                            col = np.tile(np.array(self.mat_info.get(n, {}).get("base", (0.5, 0.5, 0.5, 1))[:3]), (len(li), 1))
                    else:
                        col = np.tile(np.array(cls["col"], float), (len(li), 1))
                    out_col[li, :3] = col
                    em = cls.get("emit") if isinstance(cls.get("emit"), (tuple, list)) else (0, 0, 0)
                    sw = atlas.swatch(cls.get("r", 0.5), cls.get("m", 0.0), em)
                    slot[faces] = 3 if cls.get("tail") else 2
                    sw_loops.append((li, sw))
            jobs.append((ob, out_uv, out_col, slot, sw_loops))
        scale = atlas.pack()
        alb, orm, emi = atlas.render()
        os.makedirs(TMP, exist_ok=True)
        pa = save_img(alb, os.path.join(TMP, mat_name + "_albedo.jpg"), True)
        po = save_img(orm, os.path.join(TMP, mat_name + "_orm.png"), False)
        pe = save_img(emi, os.path.join(TMP, mat_name + "_emission.jpg"), True) if emi.max() > 0.02 else None
        bl_mat(mat_name, pa, po, pe)
        bl_mat(mat_name + "_Tail", pa, po, pe)
        for ob, out_uv, out_col, slot, sw_loops in jobs:
            for li, key in sw_loops:
                if key[0] == "reg":
                    out_uv[li] = atlas.uv_map(key[1], key[2], key[3])
                else:
                    out_uv[li] = atlas.uv_of_swatch(key)
            self._write(ob, out_uv, out_col, slot, slot_names)
        print("[%s] atlas %s: %d regions, %d swatches, scale %.2f" % (self.key, mat_name, len(atlas.regions), len(atlas.swatches), scale))
        self.atlases = getattr(self, "atlases", {})
        self.atlases[mat_name] = (atlas, emi)
        return atlas

    def _emit_faces(self, atlas, cls, uvs, li, fl, faces, slot, out_col, npoly, sw_loops):
        """Forza-style lamps: the emissive map sits on the 2nd UV set. Faces lit there become glowing swatches
        (the red ones go to the brake-light material)."""
        k = cls["emit_uv"]
        em = self.tex.get(cls["emit"])
        if k >= len(uvs) or em is None:
            return
        e = sample(em, uvs[k][li])[:, :3]
        sums = np.stack([np.bincount(fl, weights=e[:, j], minlength=npoly) for j in range(3)], 1)
        fe = sums / np.maximum(np.bincount(fl, minlength=npoly), 1)[:, None]
        lit = faces[fe[faces].max(1) > 0.25]
        pos = {f: np.nonzero(fl == f)[0] for f in lit}
        for f in lit:
            col = np.clip(fe[f] / max(fe[f].max(), 1e-3), 0, 1)
            red = col[0] > 0.8 and col[1] < 0.45
            amber = not red and col[1] < 0.8 and col[2] < 0.5
            key_col = (1.0, 0.08, 0.04) if red else ((1.0, 0.55, 0.1) if amber else (1.0, 1.0, 0.97))
            sw = atlas.swatch(0.25, 0.0, key_col)
            out_col[li[pos[f]], :3] = key_col
            slot[f] = 3 if red else 2
            sw_loops.append((li[pos[f]], sw))

    def _write(self, ob, out_uv, out_col, slot, slot_names):
        me = ob.data
        while me.uv_layers:
            me.uv_layers.remove(me.uv_layers[0])
        uvl = me.uv_layers.new(name="UVMap")
        uvl.data.foreach_set("uv", out_uv.reshape(-1).astype(np.float32))
        for a in list(me.color_attributes):
            me.color_attributes.remove(a)
        ca = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        ca.data.foreach_set("color", out_col.reshape(-1).astype(np.float32))
        me.color_attributes.active_color = ca
        me.materials.clear()
        for s in slot_names:
            me.materials.append(BMATS.get(s) or bl_mat(s))
        me.polygons.foreach_set("material_index", slot.astype(np.int32))
        used = set(slot.tolist())
        for i in reversed(range(len(slot_names))):
            if i not in used:
                me.materials.pop(index=i)

    # ---------------------------------------------------------------- reference points
    def refs(self):
        K = self.key
        body = self.props["RC_%s" % K]
        me = body.data
        bm = bmesh.new()
        bm.from_mesh(me)
        bvh = BVHTree.FromBMesh(bm)
        bm.free()
        lo, hi = bounds([body])
        # the collision box's width: the body without the door mirrors
        V = verts_np(body)
        width = float(np.percentile(np.abs(V[V[:, 2] < 0.85, 0]), 99.95))
        hub = self.steer_hub
        # the driver's eyes: behind and above the wheel hub; then clear of the roof and the headrest
        eye = Vector((hub.x, hub.y - 0.62, hub.z + 0.26))
        for _ in range(20):
            up = bvh.ray_cast(eye, Vector((0, 0, 1)), 1.0)
            if up[0] is not None and up[3] < 0.13:
                eye.z -= 0.01
                continue
            back = bvh.ray_cast(eye, Vector((0, -1, 0)), 1.0)
            if back[0] is not None and back[3] < 0.2:
                eye.y += 0.01
                continue
            break
        roof = bvh.ray_cast(eye, Vector((0, 0, 1)), 1.0)
        rest = bvh.ray_cast(eye, Vector((0, -1, 0)), 1.0)
        # lamps: lit faces (atlas emission) at the front, the brake-light faces at the back
        atlas, emi = self.atlases["RC_%s" % K]
        uvl = me.uv_layers[0].data
        head, tail = {-1: [], 1: []}, {-1: [], 1: []}
        names = [m.name for m in me.materials]
        S = emi.shape[0]
        for p in me.polygons:
            c = p.center
            nm = names[p.material_index]
            if nm.endswith("_Tail") and c.y < 0:
                tail[1 if c.x > 0 else -1].append((c.copy(), p.area))
            elif nm == "RC_%s" % K and c.y > 0.8:
                u = sum(uvl[i].uv[0] for i in p.loop_indices) / p.loop_total
                v = sum(uvl[i].uv[1] for i in p.loop_indices) / p.loop_total
                e = emi[int(np.clip((1 - v) * S, 0, S - 1)), int(np.clip(u * S, 0, S - 1))]
                if e.max() > 0.5:
                    head[1 if c.x > 0 else -1].append((c.copy(), p.area))

        def centroid(lst):
            if not lst:
                return None
            w = sum(a for _, a in lst) or 1.0
            return sum((c * a for c, a in lst), Vector()) / w
        hub_g = {q: gd(Vector(self.hubs[q]["c"])) for q in self.hubs}
        rf = (self.hubs["FL"]["r"] + self.hubs["FR"]["r"]) / 2
        rr = (self.hubs["RL"]["r"] + self.hubs["RR"]["r"]) / 2
        ref = {
            "wheelbase": round(self.wheelbase, 4), "wheel_r": round(rf, 4),
            "wheels": {q: hub_g[q] for q in hub_g},
            "eye": gd(eye), "wheel_hub": gd(hub), "column_tilt": round(self.column_tilt, 4),
            "head": [gd(v) for v in (centroid(head[-1]), centroid(head[1])) if v is not None],
            "tail": [gd(v) for v in (centroid(tail[-1]), centroid(tail[1])) if v is not None],
            "box": (round(2 * width, 3), round(hi[2] - lo[2], 3), round(hi[1] - lo[1], 3)),
            "box_center": gd((lo + hi) / 2),
            "door": (round(-width, 3), 0.86, round(-eye.y + 0.1, 3)),
            "wheel_prop": "RC_%s_Wheel" % K, "steer_prop": "RC_%s_Steer" % K, "kit": True, "tail_mat": True,
        }
        if self.stagger:
            ref["wheel_prop_rear"] = "RC_%s_WheelR" % K
            ref["wheel_r_rear"] = round(rr, 4)
        if "RC_%s_Caliper" % K in self.props:
            ref["caliper_prop"] = "RC_%s_Caliper" % K
        self.ref = ref
        print("[%s] eye %s (roof %.2f m above, headrest %.2f m behind)" % (
            K, gd(eye), roof[3] if roof[0] else -1, rest[3] if rest[0] else -1))
        return ref


# ============================================================================= main

def gd_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return '"%s"' % v
    if isinstance(v, (int, float)):
        return repr(round(float(v), 4))
    if isinstance(v, dict):
        return "{" + ", ".join('"%s": %s' % (k, gd_value(x)) for k, x in v.items()) + "}"
    if isinstance(v, (list, tuple)) and len(v) == 3 and all(isinstance(x, (int, float)) for x in v):
        return "Vector3(%s, %s, %s)" % tuple(repr(round(float(x), 4)) for x in v)
    return "[" + ", ".join(gd_value(x) for x in v) + "]"


def export(kit, refs):
    keep = {o.name for o in kit}
    for o in list(bpy.data.objects):
        if o.name not in keep:
            bpy.data.objects.remove(o)
    total = 0
    for o in kit:
        t = tris(o)
        total += t
        lo, hi = bounds([o])
        print("  %-18s %6d tris  %d surfaces  x[%.3f,%.3f] y[%.3f,%.3f] z[%.3f,%.3f]" % (
            o.name, t, len(o.data.materials), lo[0], hi[0], lo[2], hi[2], -hi[1], -lo[1]))
    print("props:", len(kit), " tris:", total)
    for name, ref in refs.items():
        print('\t"%s": {' % name)
        print("\t\t" + ",\n\t\t".join('"%s": %s' % (k, gd_value(v)) for k, v in ref.items()) + "},")
    if os.environ.get("REALCARS_REF_JSON"):
        with open(os.environ["REALCARS_REF_JSON"], "w") as fh:
            json.dump(refs, fh, indent=1)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_vertex_color="ACTIVE",
                              export_apply=True, export_yup=True, export_materials="EXPORT",
                              export_normals=True, export_image_format="AUTO", export_tangents=False)
    print("wrote", os.path.abspath(OUT), os.path.getsize(OUT) // 1024, "KB")


def main():
    argv = sys.argv[1:]
    only = ORDER
    if "--only" in argv:
        only = argv[argv.index("--only") + 1].split(",")
    if not SRC or not os.path.isdir(SRC):
        sys.exit("set REALCARS_SRC to the folder holding the unpacked source models")
    reset()
    bl_mat("CarPaint")
    bl_mat("RC_Glass", glass=True)
    kit, refs = [], {}
    for key in [k for k in ORDER if k in only]:
        car = Car(key)
        car.load()
        car.classify()
        car.normalise()
        car.cut_steering_wheel()
        car.build_props()
        body = [car.props[n] for n in car.props if not re.search(r"_Wheel", n)]
        wheels = [car.props[n] for n in car.props if re.search(r"_Wheel", n)]
        car.bake_materials(body, ATLAS, "RC_%s" % key)
        car.bake_materials(wheels, WHEEL_ATLAS, "RC_%s_Wheel" % key)
        refs["RC_%s" % key] = car.refs()
        kit += list(car.props.values())
        # the next car starts from a clean scene of its own (keep the finished props)
        for o in list(bpy.data.objects):
            if o not in kit:
                bpy.data.objects.remove(o)
    export(kit, refs)


if __name__ == "__main__":
    main()
