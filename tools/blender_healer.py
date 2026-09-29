# Builds assets/environment/buildings/healer.glb (+ healer.tscn): the trading post Healer (own model, Kenney mini
# style, on tools/blender_kit.py): a white timber-framed cottage with a blue tile roof, a round window and drying
# herbs on the front, a herb garden beside it, and in the yard the potion table, clay pots, a bubbling cauldron over
# a fire and a red-cross signpost. The table, potions, pots, plants and rain barrel are the game's own models
# (tools/blender_props.py, placed with kit.prop()); only what the game has no model of is built here.
# Run from the project folder:  blender -b --python tools/blender_healer.py [-- --check] [-- --preview out.png]
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_kit as kit
from blender_kit import *  # palette cells, G* helpers, generic pieces
import blender_props as props  # the game's existing models, placed with kit.prop()
from mathutils import Matrix, Vector

OUTPUT = os.path.join(kit.PROJECT, "assets", "environment", "buildings", "healer.glb")

# --- Layout ------------------------------------------------------------------------------------------------
# Godot stall space, meters: x right, y up, +z toward the trading post center (customers stand at z = 1.7).
# KEEP IN SYNC with the healer "block" in scenes/world/shop_station.gd (collision footprint).
MODEL_SCALE = 1.5
HOUSE = (-1.3, 1.2, -2.0, -0.9)       # x0, x1, z0, z1
HOUSE_H = 1.7                         # wall height (eaves)
GARDEN = (-1.95, -1.45, -1.9, -0.95)  # herb bed beside the house (left)
YARD_Z = 0.5
DOOR_X = -0.55
LIQUID = (6, 1)                       # green potion brew


def cauldron(x, z):
	"""Round iron pot on three legs over a small fire, green brew with bubbles."""
	base = 0.16
	rings = [(0.0, ngon(0.12, 0.12, 10)), (0.08, ngon(0.21, 0.21, 10)), (0.2, ngon(0.235, 0.235, 10)),
			(0.3, ngon(0.2, 0.2, 10))]
	loft("cauldron", rings, DARK, True, Matrix.Translation(G(x, base, z)))
	gcyl("brew", (x, base + 0.305, z), 0.17, 0.01, LIQUID, 10)
	for i, (dx, dz, r) in enumerate(((0.05, 0.02, 0.035), (-0.06, -0.04, 0.028), (0.0, 0.08, 0.022))):
		ball("bubble", Vector(G(x + dx, base + 0.315 + r * 0.4, z + dz)), r, (WHITE, PALE, WHITE)[i])
	for i in range(3):
		a = math.tau * i / 3 + 0.3
		top = (x + math.cos(a) * 0.15, base + 0.06, z + math.sin(a) * 0.15)
		foot = (x + math.cos(a) * 0.22, 0.0, z + math.sin(a) * 0.22)
		grod("cauldron_leg", foot, top, 0.018, 0.018, DARK, 6)
	for a in (0.2, 1.3, 2.4):
		c, s = math.cos(a), math.sin(a)
		grod("firewood", (x - c * 0.14, 0.035, z - s * 0.14), (x + c * 0.14, 0.035, z + s * 0.14), 0.03, 0.03, WOOD, 6, True)
	gcube("fire", (x, 0.1, z), (0.12, 0.12, 0.12), ORANGE, False, yaw=math.radians(45))
	gcube("fire", (x, 0.13, z), (0.07, 0.08, 0.07), YELLOW, False, yaw=math.radians(20))


def herb_bundle(x, y_top, z):
	"""Bunch of herbs hanging head-down from a string."""
	grod("herb_string", (x, y_top, z), (x, y_top - 0.08, z), 0.006, 0.006, TAN, 4)
	loft("herbs", [(0.0, ngon(0.012, 0.012, 6)), (0.1, ngon(0.05, 0.05, 6)), (0.2, ngon(0.035, 0.035, 6))], GREEN,
			True, Matrix.Translation(G(x, y_top - 0.3, z)) @ Matrix.Rotation(math.pi, 4, "X") @ Matrix.Translation((0, 0, -0.2)))
	gcyl("herb_tie", (x, y_top - 0.105, z), 0.02, 0.02, RED, 6)


def build():
	hx0, hx1, hz0, hz1 = HOUSE
	hcz = (hz0 + hz1) * 0.5
	fz = hz1 + 0.03  # front face of the plaster

	# Ground: yard in front with flagstones to the door.
	gbox("yard", hx0 - 0.15, hx1 + 0.2, 0, 0.025, hz1 + 0.05, YARD_Z, TAN, False)
	for dx, z, w, d in ((0.02, -0.45, 0.26, 0.2), (-0.03, -0.15, 0.24, 0.2), (0.03, 0.17, 0.26, 0.2)):
		x = DOOR_X + dx
		gbox("flagstone", x - w / 2, x + w / 2, 0.025, 0.04, z - d / 2, z + d / 2, PALE, False)

	# Cottage: stone course, white plaster with a timber frame, blue tile roof, chimney.
	gbox("plinth", hx0 - 0.04, hx1 + 0.04, 0, 0.12, hz0 - 0.04, hz1 + 0.04, DARK)
	gbox("stone", hx0, hx1, 0, 0.5, hz0, hz1, STONE)
	gbox("sill_beam", hx0 - 0.05, hx1 + 0.05, 0.48, 0.56, hz0 - 0.05, hz1 + 0.05, WOOD)
	gbox("plaster", hx0 - 0.03, hx1 + 0.03, 0.56, HOUSE_H, hz0 - 0.03, hz1 + 0.03, WHITE)
	for x in (hx0 - 0.05, hx1 + 0.05):
		for z in (hz0 - 0.05, hz1 + 0.05):
			gcube("frame_post", (x, (0.56 + HOUSE_H - 0.01) * 0.5, z), (0.08, HOUSE_H - 0.57, 0.08), WOOD)
	for x in (-0.15, 0.15):
		gcube("frame_stud", (x, (0.56 + HOUSE_H) * 0.5, hz0 - 0.045), (0.06, HOUSE_H - 0.58, 0.03), WOOD)
	for side in (-1, 1):
		x = hx1 + 0.045 if side > 0 else hx0 - 0.045
		gcube("frame_brace", (x, (0.56 + HOUSE_H) * 0.5, hcz), (0.03, 0.06, 1.05), WOOD, False, pitch=math.radians(40 * side))
	masonry("x", hx0, -1, hz0 + 0.1, hz1 - 0.1, 0.16, 0.44, 3)
	masonry("x", hx1, 1, hz0 + 0.1, hz1 - 0.1, 0.16, 0.44, 3)
	masonry("z", hz0, -1, hx0 + 0.1, hx1 - 0.1, 0.16, 0.44, 6)
	masonry("z", hz1, 1, 0.1, hx1 - 0.1, 0.16, 0.44, 3)
	gbox("top_plate", hx0 - 0.08, hx1 + 0.08, HOUSE_H - 0.02, HOUSE_H + 0.06, hz0 - 0.08, hz1 + 0.08, WOOD)
	half, pitch = tile_roof(hx0 - 0.08, hx1 + 0.08, hz0 - 0.08, hz1 + 0.08, HOUSE_H + 0.06, 0.7, rows=3, cell=BLUE,
			overhang=0.2)
	for x in (hx0 - 0.06, hx1 + 0.02):
		facade_prism("gable", [(-(half - 0.22), 0), (half - 0.22, 0), (0, 0.64)], 0.04, WHITE, x + 0.02,
				HOUSE_H + 0.06, hcz, True, yaw=math.radians(90))
	gbox("chimney", 0.7, 0.95, 1.9, 2.75, -1.75, -1.5, STONE)
	gbox("chimney_cap", 0.66, 0.99, 2.75, 2.82, -1.79, -1.46, DARK, False)
	for side in (-1, 1):
		window(hx1 + 0.03 if side > 0 else hx0 - 0.03, 1.15, hcz, yaw=math.radians(90 * side), w=0.3, h=0.32)
	window(-0.5, 1.15, hz0 - 0.03, yaw=math.radians(180), w=0.3, h=0.32)

	# Front: arched door under a small tiled hood, a round window, drying herbs between them.
	facade_prism("door_frame", arch(0.56, 0.62), 0.03, WOOD, DOOR_X, 0.12, fz + 0.015, False)
	facade_prism("door", arch(0.46, 0.6), 0.03, TAN, DOOR_X, 0.12, fz + 0.04, True)
	for y in (0.35, 0.7):
		gcube("door_band", (DOOR_X, y, fz + 0.062), (0.44, 0.04, 0.015), WOOD, False)
	gcube("door_ring", (DOOR_X + 0.14, 0.55, fz + 0.075), (0.04, 0.04, 0.02), YELLOW, False)
	lean_to(DOOR_X - 0.4, DOOR_X + 0.4, fz, fz + 0.38, 1.38, 1.2, cell=BLUE)
	for side in (-1, 1):
		grod("hood_brace", (DOOR_X + side * 0.34, 0.95, fz), (DOOR_X + side * 0.34, 1.17, fz + 0.33), 0.018, 0.018,
				WOOD, 6)
	wx, wy = 0.45, 1.15
	m = Matrix.Rotation(math.radians(90), 4, "X")
	cylinder("round_frame", G(wx, wy, fz + 0.02), 0.25, 0.04, WOOD, 12, False, m)
	cylinder("round_glass", G(wx, wy, fz + 0.035), 0.2, 0.04, SLATE, 12, False, m)
	gcube("round_cross", (wx, wy, fz + 0.06), (0.38, 0.035, 0.015), WOOD, False)
	gcube("round_cross", (wx, wy, fz + 0.062), (0.035, 0.38, 0.019), WOOD, False)
	gbox("flower_box", wx - 0.28, wx + 0.28, 0.72, 0.84, fz, fz + 0.16, WOOD)
	gbox("flower_soil", wx - 0.25, wx + 0.25, 0.84, 0.85, fz + 0.02, fz + 0.14, DARK, False)
	for dx in (-0.14, 0.13):
		prop(props.PLANT, (wx + dx, 0.85, fz + 0.08), yaw=dx * 9, scale=1.1)
	grod("herb_rod", (-0.25, 1.52, fz + 0.05), (0.2, 1.52, fz + 0.05), 0.012, 0.012, WOOD, 6)
	for x in (-0.18, -0.03, 0.12):
		herb_bundle(x, 1.51, fz + 0.05)

	# Herb garden beside the house: a raised wooden bed of soil with the game's plants.
	gx0, gx1, gz0, gz1 = GARDEN
	gbox("garden_bed", gx0, gx1, 0, 0.18, gz0, gz1, WOOD)
	gbox("garden_soil", gx0 + 0.04, gx1 - 0.04, 0.18, 0.19, gz0 + 0.04, gz1 - 0.04, DARK, False)
	for i, z in enumerate((-1.72, -1.42, -1.12)):
		prop(props.PLANT, ((gx0 + gx1) * 0.5 + (0.05 if i % 2 else -0.05), 0.19, z), yaw=i * 1.7, scale=1.4)

	# Yard: the potion table (the game's table and potions), clay pots by the door, the cauldron, a rain barrel.
	tx, tz = 0.45, -0.3
	prop(props.TABLE, (tx, 0.0, tz), scale=1.3)
	top = 0.31 * 1.3
	for dx, dz, s, yaw in ((-0.3, 0.02, 1.0, 0.3), (0.0, -0.08, props.SCALE_POTION, 0.0), (0.28, 0.05, 0.9, -0.5)):
		prop(props.POTION, (tx + dx, top, tz + dz), yaw=yaw, scale=s)
	prop(props.POT, (-1.1, 0.0, -0.62), yaw=0.4, scale=1.2)
	prop(props.POT, (-0.12, 0.0, -0.68), yaw=-0.3, scale=0.8)
	cauldron(-1.05, 0.1)
	prop(props.BARREL, (hx1 + 0.3, 0.0, -1.55), yaw=0.2, scale=0.95)

	# Signpost on the right with a red cross on a white board.
	px, pz = hx1 - 0.05, 0.3
	gcube("sign_post", (px, 0.65, pz), (0.08, 1.3, 0.08), WOOD, True)
	gcube("sign_post_cap", (px, 1.32, pz), (0.11, 0.04, 0.11), WOOD, False)
	sx = px + 0.36
	gcube("sign_arm", (px + 0.22, 1.24, pz), (0.4, 0.05, 0.05), WOOD, False)
	for dx in (-0.1, 0.1):
		gcube("sign_chain", (sx + dx, 1.185, pz), (0.015, 0.07, 0.015), SLATE, False)
	gcube("sign_board", (sx, 1.0, pz), (0.3, 0.3, 0.04), WHITE, True)
	for side in (-1, 1):
		gcube("sign_cross", (sx, 1.0, pz + side * 0.027), (0.07, 0.22, 0.012), RED, False)
		gcube("sign_cross", (sx, 1.0, pz + side * 0.022), (0.22, 0.07, 0.008), RED, False)


run(build, "healer", OUTPUT, scale=MODEL_SCALE,
		aim=Vector(G(0.0, 0.7, -0.8)) / MODEL_SCALE, dist=3.6, height=3.0)
