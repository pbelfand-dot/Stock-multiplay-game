"""Turns a rigged character (an FBX with a Mixamo skeleton and its PBR textures)
into the game's crew: assets/models/driver.glb and codriver.glb, rigged the way
scripts/vehicle/crew_model.gd poses them. Run with headless Blender:

    blender -b -Y --python tools/import_crew.py -- <rig.fbx> <textures dir> [--out DIR]

  * the bones lose the "mixamorig:" prefix and take the names crew_model.gd
    looks for: Spine -> Spine02 (the lower back, leaned toward the wheel),
    Spine1 -> Spine01, Spine2 -> Spine (the chest: the harness), Neck -> neck,
    HeadTop_End -> head_end; Hips, Head, the arms and legs keep theirs
  * all its parts (helmet, gloves, suit, boots) become one skinned mesh: the
    game cuts the helmet out (your own camera sits in it) and the hands
    (every bone from the hand down: the driver wears the game's gloves)
  * it's turned to face +Z, as the game expects of a crew model
  * its material gets the textures: base colour (sRGB), normal, roughness,
    metallic, emissive (the height map isn't used); in the GLB as JPEG, the
    base colour and normal at 2048 px, the rest at 1024
  * the co-driver is the same model, the white of the suit dyed blue (the red
    and black trim stays), so the two can be told apart
The original files aren't changed. No animations go in: the game poses the crew
itself, every frame.
"""
import bpy, sys, os, math
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
out_dir = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models"))
if "--out" in argv:
    k = argv.index("--out")
    out_dir = os.path.abspath(argv[k + 1])
    argv = argv[:k] + argv[k + 2:]
fbx, tex_dir = argv[0], argv[1]

RENAME = {"Spine": "Spine02", "Spine1": "Spine01", "Spine2": "Spine", "Neck": "neck", "HeadTop_End": "head_end"}
CODRIVER_SUIT = (0.22, 0.38, 0.85)      # what the white of the suit is dyed for the co-driver


def tex(stem):
    """The texture whose file name starts with the stem (F1_Driver_Base_Color.PNG.png ...)."""
    for f in sorted(os.listdir(tex_dir)):
        if f.lower().startswith(stem.lower()):
            return os.path.join(tex_dir, f)
    return None


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=fbx)
arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
for o in list(bpy.context.scene.objects):
    if o.type not in ('ARMATURE', 'MESH'):
        bpy.data.objects.remove(o, do_unlink=True)
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
if arm.animation_data:
    arm.animation_data_clear()
# bone names: the game's (a mesh's vertex groups follow the bones' names, renamed with them)
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
for b in arm.data.bones:
    new = b.name.split(":")[-1]
    new = RENAME.get(new, new)
    for m in meshes:
        g = m.vertex_groups.get(b.name)
        if g:
            g.name = new
    b.name = new
# one mesh (each part's texture coordinates under the same name first: joined under
# different names, the parts' UVs would land in separate layers, the rest zero)
for m in meshes:
    uv = m.data.uv_layers
    act = uv.active
    for layer in [l for l in uv if l != act]:
        uv.remove(layer)
    if uv.active:
        uv.active.name = "UVMap"
bpy.ops.object.select_all(action='DESELECT')
for m in meshes:
    m.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = "Body"
# facing +Z in the GLB (+Y in Blender's frame turns to -Z: the model faced -Z)
arm.rotation_euler.z += math.pi
# the material: its textures
mat = body.data.materials[0]
mat.use_nodes = True
nt = mat.node_tree
for n in list(nt.nodes):
    nt.nodes.remove(n)
bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
outn = nt.nodes.new("ShaderNodeOutputMaterial")
nt.links.new(bsdf.outputs["BSDF"], outn.inputs["Surface"])
images = {}


def image(stem, colour, size):
    path = tex(stem)
    if not path:
        print("no texture for", stem)
        return None
    img = bpy.data.images.load(path)
    img.colorspace_settings.name = 'sRGB' if colour else 'Non-Color'
    if img.size[0] > size:
        img.scale(size, size)
    img.file_format = 'JPEG'
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = img
    images[stem] = img
    return n


base = image("F1_Driver_Base_Color", True, 2048)
nt.links.new(base.outputs["Color"], bsdf.inputs["Base Color"])
nrm = image("F1_Driver_Normal", False, 2048)
if nrm:
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(nrm.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
rough = image("F1_Driver_Roughness", False, 1024)
if rough:
    nt.links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
metal = image("F1_Driver_Metallic", False, 1024)
if metal:
    nt.links.new(metal.outputs["Color"], bsdf.inputs["Metallic"])
emit = image("F1_Driver_Emissive", True, 1024)
if emit:
    key = "Emission Color" if "Emission Color" in bsdf.inputs else "Emission"
    nt.links.new(emit.outputs["Color"], bsdf.inputs[key])
    if "Emission Strength" in bsdf.inputs:
        bsdf.inputs["Emission Strength"].default_value = 1.0

os.makedirs(out_dir, exist_ok=True)


def export(name):
    path = os.path.join(out_dir, name + ".glb")
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_yup=True, export_skins=True,
        export_animations=False, export_materials='EXPORT', export_image_format='JPEG', export_jpeg_quality=90)
    print("wrote %s (%d KB)" % (path, os.path.getsize(path) // 1024))


export("driver")
# the co-driver: the suit's white dyed (pixels near white or light grey, not the red, black or carbon trim)
img = images["F1_Driver_Base_Color"]
px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
rgb = px[:, :3]
hi, lo = rgb.max(axis=1), rgb.min(axis=1)
white = np.clip((lo - 0.45) / 0.2, 0.0, 1.0) * np.clip(1.0 - (hi - lo) / 0.12, 0.0, 1.0)
dyed = rgb.mean(axis=1, keepdims=True) * np.array(CODRIVER_SUIT, dtype=np.float32) * 1.25
px[:, :3] = rgb * (1.0 - white[:, None]) + np.clip(dyed, 0.0, 1.0) * white[:, None]
img.pixels[:] = px.reshape(-1)
img.update()
export("codriver")
