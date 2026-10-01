# Builds assets/characters/keeper.glb: the Graveyard Kit keeper (a rigid model, one mesh per body part
# animated by node transforms) skinned onto the human's armature, so it gets the same Skeleton3D, bones
# and clips as every other character (weapons on arm bones, holding poses, downed clips).
# Run from the project folder:  blender -b --python tools/blender_keeper_rig.py
import bpy, json, os, struct

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RIG = os.path.join(PROJECT, "assets", "characters", "human.glb")
SOURCE = os.path.join(PROJECT, "pre-assets", "kenney_graveyard-kit_5.0", "Models", "GLB format", "character-keeper.glb")
OUTPUT = os.path.join(PROJECT, "assets", "characters", "keeper.glb")
PALETTE = os.path.join(PROJECT, "assets", "textures", "palettes", "graveyard_colormap.png")
BONES = ("root", "leg-left", "leg-right", "torso", "arm-left", "arm-right", "head")


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


bpy.ops.wm.read_factory_settings(use_empty=True)
rig_objects = import_glb(RIG)
armature = next(o for o in rig_objects if o.type == 'ARMATURE')
rig_actions = set(bpy.data.actions)
for o in rig_objects:
    if o.type == 'MESH':
        bpy.data.objects.remove(o)

parts = import_glb(SOURCE)
for o in parts:
    o.animation_data_clear()
for action in list(bpy.data.actions):
    if action not in rig_actions:
        bpy.data.actions.remove(action)
bpy.context.view_layer.update()

# Every part mesh in its rest place, weighted fully to the bone of the same name.
worlds = {o.name: o.matrix_world.copy() for o in parts}
for o in parts:
    o.parent = None
    o.matrix_world = worlds[o.name]
bpy.context.view_layer.update()
meshes = []
for o in parts:
    if o.type != 'MESH':
        continue
    bone = o.name.split(".")[0]
    if bone not in BONES:
        raise SystemExit("keeper part without a bone: " + o.name)
    o.data = o.data.copy()
    o.data.transform(o.matrix_world)
    o.matrix_world.identity()
    group = o.vertex_groups.new(name=bone)
    group.add(range(len(o.data.vertices)), 1.0, 'REPLACE')
    meshes.append(o)
for o in parts:
    if o.type != 'MESH':
        bpy.data.objects.remove(o)

bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = "body-mesh"
body.parent = armature
body.modifiers.new("Armature", 'ARMATURE').object = armature
armature.name = "character-keeper"
armature.animation_data_create()
armature.animation_data.action = None
for pb in armature.pose.bones:
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.location = (0, 0, 0)
    pb.scale = (1, 1, 1)

bpy.ops.object.select_all(action='DESELECT')
for o in (armature, body):
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUTPUT, export_format='GLB', use_selection=True,
    export_animation_mode='ACTIONS', export_animations=True)

# Link the shared palette instead of the embedded copy of the kit's colormap.
data = open(OUTPUT, "rb").read()
json_len = struct.unpack("<I", data[12:16])[0]
doc = json.loads(data[20:20 + json_len])
rel = os.path.relpath(PALETTE, os.path.dirname(OUTPUT)).replace("\\", "/")
doc["images"] = [{"uri": rel, "name": "graveyard_colormap"} for _ in doc.get("images", [])]
chunk = json.dumps(doc, separators=(",", ":")).encode()
chunk += b" " * (-len(chunk) % 4)
body_bytes = struct.pack("<I4s", len(chunk), b"JSON") + chunk + data[20 + json_len:]
with open(OUTPUT, "wb") as f:
    f.write(struct.pack("<4sII", b"glTF", 2, 12 + len(body_bytes)) + body_bytes)
print("KEEPER OK", len(doc.get("animations", [])), "clips")
