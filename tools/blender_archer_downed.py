# Builds assets/characters/animations/archer_downed.glb ("crawl" + "downed" clips on the archer armature).
# Run from the project folder:  blender -b --python tools/blender_archer_downed.py
import bpy, math, os
from mathutils import Euler

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(PROJECT, "assets", "characters", "archer.glb")
OUTPUT = os.path.join(PROJECT, "assets", "characters", "animations", "archer_downed.glb")
R = math.radians
def q(x=0,y=0,z=0):
    return Euler((R(x),R(y),R(z)),'XYZ').to_quaternion()

TILT = 84
LIFT = 0.13
BACK = 0.36
def crawl_pose(t):
    """t in [0,1) cycle phase."""
    s=math.sin(2*math.pi*t); c=math.cos(2*math.pi*t)
    P={}
    P['root']=(q(TILT, s*7, 0),(0,LIFT+0.015*abs(c),-BACK))
    P['torso']=(q(-6, s*-4, 0),(0,0,0))
    P["head"]=(q(-28, s*6, 0),(0,0,0))
    # left arm: reach when s>0
    la=max(s,0); ra=max(-s,0)
    P['arm-left']=(q(30-20*la, 0, 20+95*(0.5+0.5*s)),(0,0,0))
    P['arm-right']=(q(30-20*ra, 0, -(20+95*(0.5-0.5*s))),(0,0,0))
    P['leg-left']=(q(-10+18*s,0,-6),(0,0,0))
    P['leg-right']=(q(-10-18*s,0,6),(0,0,0))
    return P
def idle_pose(t):
    s=math.sin(2*math.pi*t)
    P={}
    P['root']=(q(TILT,3,0),(0,LIFT+0.008*s,-BACK))
    P['torso']=(q(-6+1.5*s,0,0),(0,0,0))
    P['head']=(q(-40+4*s,-8,0),(0,0,0))
    P['arm-left']=(q(35,0,70+6*s),(0,0,0))
    P['arm-right']=(q(28,0,-30),(0,0,0))
    P['leg-left']=(q(-8,0,-6),(0,0,0))
    P['leg-right']=(q(-14,0,8),(0,0,0))
    return P
def apply(arm,P):
    for n,(rot,loc) in P.items():
        pb=arm.pose.bones[n]; pb.rotation_mode='QUATERNION'; pb.rotation_quaternion=rot; pb.location=loc
def build(arm,name,fn,frames,step):
    act=bpy.data.actions.new(name); arm.animation_data_create(); arm.animation_data.action=act
    for f in range(0,frames+1,step):
        apply(arm,fn((f%frames)/frames))
        for n in ('root','torso','head','arm-left','arm-right','leg-left','leg-right'):
            pb=arm.pose.bones[n]
            pb.keyframe_insert('rotation_quaternion',frame=f); pb.keyframe_insert('location',frame=f)
    return act


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SOURCE)
sc = bpy.context.scene
arm = [o for o in sc.objects if o.type == 'ARMATURE'][0]
arm.animation_data_create()
arm.animation_data.action = None
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
if sc.objects.get("Icosphere"):
    bpy.data.objects.remove(sc.objects["Icosphere"])
for a in (build(arm, "crawl", crawl_pose, 24, 2), build(arm, "downed", idle_pose, 48, 4)):
    a.use_fake_user = True
arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.location = (0, 0, 0)
for o in sc.objects:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUTPUT, export_format='GLB', use_selection=True,
    export_animation_mode='ACTIONS', export_animations=True, export_materials='NONE')
