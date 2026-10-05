# Gold vein: a mossy boulder cluster (gold_vein_rock.glb) and the gold crystals growing out of it
# (gold_vein_crystals.glb, a separate model so the game can shrink them as the vein is mined).
#   blender -b --python tools/blender_gold_vein.py -- --check [--preview out.png --yaw 35]
import os, sys, math
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import blender_kit as kit
from mathutils import Matrix, Euler

OUT = os.path.join(kit.PROJECT, "assets", "environment", "gold")

# Boulders: (x, y, z, radius, yaw, pitch, roll, cell); y = height of the center (Godot space, meters).
BOULDERS = [
	(0.0, 0.34, 0.0, 0.5, 0.3, 0.2, 0.1, kit.STONE),
	(0.42, 0.2, 0.22, 0.34, 1.1, 0.5, 0.3, kit.SLATE),
	(-0.4, 0.18, 0.2, 0.31, 2.0, 0.4, 0.7, kit.STONE),
	(-0.12, 0.16, -0.42, 0.3, 2.7, 0.9, 0.2, kit.SLATE),
	(0.3, 0.12, -0.32, 0.22, 0.8, 1.3, 0.5, kit.MOSS),
]

# Crystals: base point (inside a boulder) -> tip, base radius.
CRYSTALS = [
	((0.02, 0.55, 0.02), (0.08, 1.2, 0.1), 0.13),
	((0.12, 0.5, 0.12), (0.42, 0.98, 0.3), 0.1),
	((-0.1, 0.5, 0.06), (-0.42, 0.95, 0.22), 0.1),
	((0.02, 0.48, -0.12), (-0.08, 0.92, -0.42), 0.09),
	((0.42, 0.3, 0.24), (0.66, 0.66, 0.42), 0.08),
	((-0.42, 0.26, 0.2), (-0.66, 0.58, 0.36), 0.075),
	((-0.14, 0.26, -0.42), (-0.3, 0.55, -0.66), 0.07),
	((0.3, 0.2, -0.3), (0.5, 0.44, -0.5), 0.06),
]


def build_rock():
	for i, (x, y, z, r, yaw, pitch, roll, cell) in enumerate(BOULDERS):
		frame = Matrix.Translation(kit.G(x, y, z)) @ Euler((pitch, roll, yaw)).to_matrix().to_4x4()
		kit.ball("boulder_%d" % i, (0.0, 0.0, 0.0), r, cell, frame, subdivisions=1, gradient=True)


def build_crystals():
	for i, (base, tip, r) in enumerate(CRYSTALS):
		kit.grod("crystal_%d" % i, base, tip, r, 0.0, kit.YELLOW, segments=6, gradient=True)


kit.run(build_rock, "gold_vein_rock", os.path.join(OUT, "gold_vein_rock.glb"), aim=(0.0, 0.0, 0.4))
kit.run(build_crystals, "gold_vein_crystals", os.path.join(OUT, "gold_vein_crystals.glb"), aim=(0.0, 0.0, 0.6))
